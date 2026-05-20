#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  printf 'Usage: %s <config.env>\n' "${0##*/}" >&2
}

script_dir() {
  local source_dir
  source_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  printf '%s\n' "$source_dir"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_bool() {
  [[ "$1" == "true" || "$1" == "false" ]]
}

is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_ipv4() {
  local octet
  local o1
  local o2
  local o3
  local o4

  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r o1 o2 o3 o4 <<<"$1"

  for octet in "$o1" "$o2" "$o3" "$o4"; do
    (( octet <= 255 )) || return 1
  done
}

is_ipv4_cidr() {
  local address=${1%/*}

  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]] || return 1
  is_ipv4 "$address"
}

is_safe_bridge_name() {
  [[ "$1" =~ ^[A-Za-z0-9_.:-]+$ ]]
}

is_safe_domain_name() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}

is_safe_guest_user() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]
}

is_safe_vm_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]]
}

shell_quote() {
  printf "'%s'" "${1//\'/\'\"\'\"\'}"
}

resolve_profile_file() {
  local profile=$1
  local root_dir=$2

  if [[ "$profile" == /* ]]; then
    printf '%s\n' "$profile"
  elif [[ -f "$profile" ]]; then
    printf '%s\n' "$profile"
  elif [[ -f "${root_dir}/${profile}" ]]; then
    printf '%s\n' "${root_dir}/${profile}"
  else
    return 1
  fi
}

guest_ssh_service() {
  case ${IMAGE_OS_FAMILY:-} in
    debian) printf '%s\n' 'ssh' ;;
    rhel) printf '%s\n' 'sshd' ;;
    *) die "IMAGE_OS_FAMILY must be one of: debian rhel" ;;
  esac
}

expected_template_vga() {
  case ${TEMPLATE_CONSOLE_MODE:-vga-serial} in
    serial) printf '%s\n' 'serial0' ;;
    vga-serial) printf '%s\n' 'std' ;;
    *) die "TEMPLATE_CONSOLE_MODE must be one of: serial vga-serial" ;;
  esac
}

print_smoke_diagnostics() {
  if [[ "$REMOTE_SMOKE_READY" != "true" ]]; then
    return 0
  fi

  run_remote_smoke_action diagnostics || true
}

fail_keep_vm() {
  SMOKE_TEST_KEEP_FAILED=true
  print_smoke_diagnostics
  die "$@"
}

guest_ssh() {
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$SMOKE_TEST_SSH_KEY_PATH" \
    "${SMOKE_TEST_USER}@${SMOKE_TEST_IP_ONLY}" \
    "$@"
}

guest_ssh_timeout() {
  local seconds=$1
  shift

  timeout --kill-after=10s "$seconds" ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$SMOKE_TEST_SSH_KEY_PATH" \
    "${SMOKE_TEST_USER}@${SMOKE_TEST_IP_ONLY}" \
    "$@"
}

guest_cloud_init_wait() {
  local seconds=$1

  # shellcheck disable=SC2016
  guest_ssh_timeout "$seconds" '
if [ "$(id -u)" -eq 0 ]; then
  cloud_init_output=$(cloud-init status --wait --format json 2>&1)
elif command -v sudo >/dev/null 2>&1; then
  cloud_init_output=$(sudo -n cloud-init status --wait --format json 2>&1)
else
  cloud_init_output=$(cloud-init status --wait --format json 2>&1)
fi
cloud_init_rc=$?

if [ "$cloud_init_rc" -eq 0 ]; then
  exit 0
fi

if [ "$cloud_init_rc" -eq 2 ]; then
  if printf "%s\n" "$cloud_init_output" | python3 -c "import json, sys; data = json.load(sys.stdin); sys.exit(0 if data.get(\"status\") == \"done\" and not data.get(\"errors\") else 1)"; then
    exit 0
  fi
fi

printf "%s\n" "$cloud_init_output" >&2
exit "$cloud_init_rc"
'
}

write_payload_value() {
  local key=$1
  local value=$2

  [[ "$value" != *$'\n'* ]] || die "Payload value for ${key} must not contain newlines"
  printf '%s=%s\n' "$key" "$value" >>"$LOCAL_PAYLOAD_TEMP"
}

write_remote_smoke_payload() {
  : >"$LOCAL_PAYLOAD_TEMP"
  write_payload_value TEMPLATE_VMID "$TEMPLATE_VMID"
  write_payload_value SMOKE_TEST_VMID "$SMOKE_TEST_VMID"
  write_payload_value SMOKE_TEST_NAME "$SMOKE_TEST_NAME"
  write_payload_value SMOKE_TEST_IPV4 "$SMOKE_TEST_IPV4"
  write_payload_value SMOKE_TEST_GATEWAY "$SMOKE_TEST_GATEWAY"
  write_payload_value SMOKE_TEST_DNS "$SMOKE_TEST_DNS"
  write_payload_value SMOKE_TEST_BRIDGE "$SMOKE_TEST_BRIDGE"
  write_payload_value SMOKE_TEST_USER "$SMOKE_TEST_USER"
  write_payload_value SMOKE_TEST_SEARCHDOMAIN "${SMOKE_TEST_SEARCHDOMAIN:-}"
  write_payload_value SMOKE_TEST_FORCE_RECREATE "$SMOKE_TEST_FORCE_RECREATE"
  write_payload_value SMOKE_TEST_BOOT_TIMEOUT_SECONDS "$SMOKE_TEST_BOOT_TIMEOUT_SECONDS"
  write_payload_value EXPECTED_TEMPLATE_VGA "$EXPECTED_TEMPLATE_VGA"
  write_payload_value SMOKE_TEST_PUBLIC_KEY_FILE "$REMOTE_PUBLIC_KEY_FILE_REL"
}

cleanup_remote_smoke_files() {
  # shellcheck disable=SC2029
  ssh_transport_ssh "rm -rf ${ESC_REMOTE_SMOKE_DIR}" >/dev/null 2>&1 || true
}

run_remote_smoke_action() {
  local action=$1

  case $action in
    prepare | diagnostics | qga-check | shutdown | cleanup) ;;
    *) die "Unsupported remote smoke-test action: ${action}" ;;
  esac

  # shellcheck disable=SC2029
  ssh_transport_ssh "cd ${ESC_PROXMOX_REMOTE_DIR} && ./scripts/proxmox-smoke-test-runner.sh ${ESC_REMOTE_PAYLOAD_FILE} ${action}"
}

sync_remote_smoke_runner() {
  info "Syncing smoke-test runner to ${SSH_TRANSPORT_DISPLAY}"
  # shellcheck disable=SC2029
  ssh_transport_ssh "mkdir -p ${ESC_REMOTE_SCRIPT_DIR} ${ESC_REMOTE_SMOKE_DIR}"
  rsync -az -e "$SSH_TRANSPORT_RSYNC_RSH" "${SCRIPT_DIR}/proxmox-smoke-test-runner.sh" "${SSH_TRANSPORT_TARGET}:${PROXMOX_REMOTE_DIR}/scripts/proxmox-smoke-test-runner.sh"
  rsync -az -e "$SSH_TRANSPORT_RSYNC_RSH" "$LOCAL_PAYLOAD_TEMP" "${SSH_TRANSPORT_TARGET}:${PROXMOX_REMOTE_DIR}/${REMOTE_PAYLOAD_FILE_REL}"
  rsync -az -e "$SSH_TRANSPORT_RSYNC_RSH" "$SMOKE_TEST_PUBLIC_KEY_PATH" "${SSH_TRANSPORT_TARGET}:${PROXMOX_REMOTE_DIR}/${REMOTE_PUBLIC_KEY_FILE_REL}"
  # shellcheck disable=SC2029
  ssh_transport_ssh "test -x ${ESC_PROXMOX_REMOTE_DIR}/scripts/proxmox-smoke-test-runner.sh" || die "Remote smoke-test runner is not executable on ${SSH_TRANSPORT_DISPLAY}"
  REMOTE_SMOKE_READY=true
}

cleanup_smoke_vm() {
  rm -f -- "${LOCAL_PUBLIC_KEY_TEMP:-}"
  rm -f -- "${LOCAL_PAYLOAD_TEMP:-}"

  if [[ "$REMOTE_SMOKE_READY" != "true" ]]; then
    return 0
  fi

  if [[ "$SMOKE_TEST_FAILED" == "true" && "$SMOKE_TEST_KEEP_FAILED" == "true" ]]; then
    warn "Keeping failed smoke-test VM ${SMOKE_TEST_VMID} for debugging"
    cleanup_remote_smoke_files
    return 0
  fi

  if [[ "$SMOKE_TEST_CLEANUP" != "true" ]]; then
    warn "Keeping smoke-test VM ${SMOKE_TEST_VMID} because SMOKE_TEST_CLEANUP=false"
    cleanup_remote_smoke_files
    return 0
  fi

  info "Destroying smoke-test VM ${SMOKE_TEST_VMID}"
  run_remote_smoke_action cleanup >/dev/null 2>&1 || true
  cleanup_remote_smoke_files
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

CONFIG_FILE=$1
SCRIPT_DIR=$(script_dir)
ROOT_DIR=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)
# shellcheck source=scripts/ssh-transport.sh
. "${SCRIPT_DIR}/ssh-transport.sh"

"${SCRIPT_DIR}/validate-config.sh" "$CONFIG_FILE"

set -a
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

PROFILE_FILE=$(resolve_profile_file "$IMAGE_PROFILE" "$ROOT_DIR") || die "Image profile not found: ${IMAGE_PROFILE}"

set -a
# shellcheck source=/dev/null
. "$PROFILE_FILE"
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

command_exists ssh || die "ssh is required"
command_exists ssh-keygen || die "ssh-keygen is required"
command_exists mktemp || die "mktemp is required"
command_exists rsync || die "rsync is required"
command_exists timeout || die "timeout is required"

ssh_transport_init "${TEMPLATE_BUILDER_SSH_CONFIG:-}" "$PROXMOX_HOST"

SMOKE_TEST_VMID=${SMOKE_TEST_VMID:-9900}
SMOKE_TEST_NAME=${SMOKE_TEST_NAME:-platform-template-smoke-${SMOKE_TEST_VMID}}
SMOKE_TEST_BRIDGE=${SMOKE_TEST_BRIDGE:-$BRIDGE}
SMOKE_TEST_USER=${SMOKE_TEST_USER:-$CLOUDINIT_USER}
SMOKE_TEST_DNS=${SMOKE_TEST_DNS:-${SMOKE_TEST_GATEWAY:-}}
SMOKE_TEST_KEEP_FAILED=${SMOKE_TEST_KEEP_FAILED:-false}
SMOKE_TEST_CLEANUP=${SMOKE_TEST_CLEANUP:-true}
SMOKE_TEST_FORCE_RECREATE=${SMOKE_TEST_FORCE_RECREATE:-false}
SMOKE_TEST_BOOT_TIMEOUT_SECONDS=${SMOKE_TEST_BOOT_TIMEOUT_SECONDS:-900}
SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS=${SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS:-180}
REMOTE_SMOKE_READY=false
SMOKE_TEST_FAILED=true
LOCAL_PUBLIC_KEY_TEMP=''
LOCAL_PAYLOAD_TEMP=''
SMOKE_TEST_SSH_SERVICE=$(guest_ssh_service)
EXPECTED_TEMPLATE_VGA=$(expected_template_vga)

trap cleanup_smoke_vm EXIT

[[ "$SMOKE_TEST_VMID" =~ ^[0-9]+$ ]] || die "SMOKE_TEST_VMID must be numeric"
[[ -n "${SMOKE_TEST_IPV4:-}" ]] || die "SMOKE_TEST_IPV4 is required, for example <temporary-ip/cidr>"
is_ipv4_cidr "$SMOKE_TEST_IPV4" || die "SMOKE_TEST_IPV4 must use IPv4 CIDR format, for example <temporary-ip/cidr>"
[[ -n "${SMOKE_TEST_GATEWAY:-}" ]] || die "SMOKE_TEST_GATEWAY is required"
is_ipv4 "$SMOKE_TEST_GATEWAY" || die "SMOKE_TEST_GATEWAY must be an IPv4 address"
[[ -n "${SMOKE_TEST_DNS:-}" ]] || die "SMOKE_TEST_DNS is required"
is_ipv4 "$SMOKE_TEST_DNS" || die "SMOKE_TEST_DNS must be an IPv4 address"
[[ -n "${SMOKE_TEST_SSH_KEY:-}" ]] || die "SMOKE_TEST_SSH_KEY is required"
is_safe_bridge_name "$SMOKE_TEST_BRIDGE" || die "SMOKE_TEST_BRIDGE may contain only letters, numbers, dot, underscore, colon, and dash"
is_safe_guest_user "$SMOKE_TEST_USER" || die "SMOKE_TEST_USER must be a safe Linux user name"
is_safe_vm_name "$SMOKE_TEST_NAME" || die "SMOKE_TEST_NAME may contain only letters, numbers, dot, underscore, and dash"
if [[ -n "${SMOKE_TEST_SEARCHDOMAIN:-}" ]]; then
  is_safe_domain_name "$SMOKE_TEST_SEARCHDOMAIN" || die "SMOKE_TEST_SEARCHDOMAIN must be a DNS search domain"
fi
is_number "$SMOKE_TEST_BOOT_TIMEOUT_SECONDS" || die "SMOKE_TEST_BOOT_TIMEOUT_SECONDS must be numeric"
is_number "$SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS" || die "SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS must be numeric"
(( SMOKE_TEST_BOOT_TIMEOUT_SECONDS > 0 )) || die "SMOKE_TEST_BOOT_TIMEOUT_SECONDS must be greater than 0"
(( SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS > 0 )) || die "SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS must be greater than 0"
is_bool "$SMOKE_TEST_KEEP_FAILED" || die "SMOKE_TEST_KEEP_FAILED must be true or false"
is_bool "$SMOKE_TEST_CLEANUP" || die "SMOKE_TEST_CLEANUP must be true or false"
is_bool "$SMOKE_TEST_FORCE_RECREATE" || die "SMOKE_TEST_FORCE_RECREATE must be true or false"

SMOKE_TEST_IP_ONLY=${SMOKE_TEST_IPV4%%/*}
REMOTE_SMOKE_DIR_REL="tmp/smoke-test-${SMOKE_TEST_VMID}"
REMOTE_PAYLOAD_FILE_REL="${REMOTE_SMOKE_DIR_REL}/payload.env"
REMOTE_PUBLIC_KEY_FILE_REL="${REMOTE_SMOKE_DIR_REL}/authorized_key.pub"
ESC_PROXMOX_REMOTE_DIR=$(shell_quote "$PROXMOX_REMOTE_DIR")
ESC_REMOTE_SCRIPT_DIR=$(shell_quote "${PROXMOX_REMOTE_DIR}/scripts")
ESC_REMOTE_SMOKE_DIR=$(shell_quote "${PROXMOX_REMOTE_DIR}/${REMOTE_SMOKE_DIR_REL}")
ESC_REMOTE_PAYLOAD_FILE=$(shell_quote "$REMOTE_PAYLOAD_FILE_REL")
SMOKE_TEST_SSH_KEY_PATH=$(ssh_transport_expand_path "$SMOKE_TEST_SSH_KEY")
[[ -f "$SMOKE_TEST_SSH_KEY_PATH" ]] || die "Smoke-test SSH private key not found: ${SMOKE_TEST_SSH_KEY_PATH}"
if command_exists stat; then
  key_mode=$(stat -c '%a' "$SMOKE_TEST_SSH_KEY_PATH")
  if [[ ${key_mode: -2} != "00" ]]; then
    warn "Smoke-test SSH private key has group/other permissions (${key_mode}); ssh may reject it"
  fi
fi

if [[ -n "${SMOKE_TEST_SSH_PUBLIC_KEY:-}" ]]; then
  SMOKE_TEST_PUBLIC_KEY_PATH=$(ssh_transport_expand_path "$SMOKE_TEST_SSH_PUBLIC_KEY")
  [[ -f "$SMOKE_TEST_PUBLIC_KEY_PATH" ]] || die "Smoke-test SSH public key not found: ${SMOKE_TEST_PUBLIC_KEY_PATH}"
else
  LOCAL_PUBLIC_KEY_TEMP=$(mktemp "${TMPDIR:-/tmp}/template-smoke-key.XXXXXX.pub")
  ssh-keygen -y -f "$SMOKE_TEST_SSH_KEY_PATH" >"$LOCAL_PUBLIC_KEY_TEMP"
  SMOKE_TEST_PUBLIC_KEY_PATH=$LOCAL_PUBLIC_KEY_TEMP
fi

LOCAL_PAYLOAD_TEMP=$(mktemp "${TMPDIR:-/tmp}/template-smoke-payload.XXXXXX.env")
write_remote_smoke_payload

info "Checking SSH access to ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
ssh_transport_ssh 'true' || die "Cannot connect to Proxmox host ${PROXMOX_HOST}"

sync_remote_smoke_runner
run_remote_smoke_action prepare || fail_keep_vm "Remote smoke-test preparation failed; kept VM for console/noVNC debugging"

info "Waiting for SSH as ${SMOKE_TEST_USER}@${SMOKE_TEST_IP_ONLY}"
deadline=$((SECONDS + SMOKE_TEST_BOOT_TIMEOUT_SECONDS))
until guest_ssh true >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    die "Timed out waiting for SSH to ${SMOKE_TEST_USER}@${SMOKE_TEST_IP_ONLY}"
  fi
  sleep 5
done
ok "SSH login succeeded"

info "Checking cloud-init and guest services"
guest_cloud_init_wait "$SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS"
guest_ssh_timeout "$SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS" "systemctl is-active '${SMOKE_TEST_SSH_SERVICE}'" >/dev/null
ok "cloud-init and SSH service are healthy"

run_remote_smoke_action qga-check || fail_keep_vm "QEMU guest-agent checks failed; kept VM for console/noVNC debugging"
guest_ssh "systemctl is-active qemu-guest-agent" >/dev/null
ok "QEMU guest agent service is healthy"

run_remote_smoke_action shutdown

SMOKE_TEST_FAILED=false
ok "Template smoke test passed"
