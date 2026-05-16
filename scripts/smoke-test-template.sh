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

is_ipv4_cidr() {
  local address=${1%/*}
  local octet
  local o1
  local o2
  local o3
  local o4

  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]] || return 1
  IFS=. read -r o1 o2 o3 o4 <<<"$address"

  for octet in "$o1" "$o2" "$o3" "$o4"; do
    (( octet <= 255 )) || return 1
  done
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
  if [[ "$SMOKE_VM_CREATED" != "true" ]]; then
    return 0
  fi

  warn "Smoke-test VM ${SMOKE_TEST_VMID} diagnostics follow"
  printf '%s\n' '--- qm status ---'
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm status '${SMOKE_TEST_VMID}'" || true
  printf '%s\n' '--- qm config ---'
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm config '${SMOKE_TEST_VMID}'" || true
  printf '%s\n' '--- cloud-init network ---'
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm cloudinit dump '${SMOKE_TEST_VMID}' network" || true
  printf '%s\n' '--- qemu guest agent ping ---'
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm agent '${SMOKE_TEST_VMID}' ping" || true
}

fail_keep_vm() {
  SMOKE_TEST_KEEP_FAILED=true
  print_smoke_diagnostics
  die "$@"
}

remote_check_command() {
  local command_name=$1

  # shellcheck disable=SC2029
  ssh_transport_ssh "command -v '${command_name}' >/dev/null 2>&1" || die "Remote command missing on ${SSH_TRANSPORT_DISPLAY}: ${command_name}"
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

cleanup_smoke_vm() {
  if [[ -n "${REMOTE_PUBLIC_KEY_FILE:-}" ]]; then
    # shellcheck disable=SC2029
    ssh_transport_ssh "rm -f '${REMOTE_PUBLIC_KEY_FILE}'" >/dev/null 2>&1 || true
  fi

  rm -f -- "${LOCAL_PUBLIC_KEY_TEMP:-}"

  if [[ "$SMOKE_VM_CREATED" != "true" ]]; then
    return 0
  fi

  if [[ "$SMOKE_TEST_FAILED" == "true" && "$SMOKE_TEST_KEEP_FAILED" == "true" ]]; then
    warn "Keeping failed smoke-test VM ${SMOKE_TEST_VMID} for debugging"
    return 0
  fi

  if [[ "$SMOKE_TEST_CLEANUP" != "true" ]]; then
    warn "Keeping smoke-test VM ${SMOKE_TEST_VMID} because SMOKE_TEST_CLEANUP=false"
    return 0
  fi

  info "Destroying smoke-test VM ${SMOKE_TEST_VMID}"
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm status '${SMOKE_TEST_VMID}' >/dev/null 2>&1" || return 0
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm stop '${SMOKE_TEST_VMID}' >/dev/null 2>&1 || true" || true
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm destroy '${SMOKE_TEST_VMID}' --purge >/dev/null 2>&1 || true" || true
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
SMOKE_VM_CREATED=false
SMOKE_TEST_FAILED=true
REMOTE_PUBLIC_KEY_FILE=''
LOCAL_PUBLIC_KEY_TEMP=''
SMOKE_TEST_SSH_SERVICE=$(guest_ssh_service)
EXPECTED_TEMPLATE_VGA=$(expected_template_vga)

trap cleanup_smoke_vm EXIT

[[ "$SMOKE_TEST_VMID" =~ ^[0-9]+$ ]] || die "SMOKE_TEST_VMID must be numeric"
[[ -n "${SMOKE_TEST_IPV4:-}" ]] || die "SMOKE_TEST_IPV4 is required, for example <temporary-ip/cidr>"
is_ipv4_cidr "$SMOKE_TEST_IPV4" || die "SMOKE_TEST_IPV4 must use IPv4 CIDR format, for example <temporary-ip/cidr>"
[[ -n "${SMOKE_TEST_GATEWAY:-}" ]] || die "SMOKE_TEST_GATEWAY is required"
[[ -n "${SMOKE_TEST_DNS:-}" ]] || die "SMOKE_TEST_DNS is required"
[[ -n "${SMOKE_TEST_SSH_KEY:-}" ]] || die "SMOKE_TEST_SSH_KEY is required"
is_number "$SMOKE_TEST_BOOT_TIMEOUT_SECONDS" || die "SMOKE_TEST_BOOT_TIMEOUT_SECONDS must be numeric"
is_number "$SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS" || die "SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS must be numeric"
(( SMOKE_TEST_BOOT_TIMEOUT_SECONDS > 0 )) || die "SMOKE_TEST_BOOT_TIMEOUT_SECONDS must be greater than 0"
(( SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS > 0 )) || die "SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS must be greater than 0"
is_bool "$SMOKE_TEST_KEEP_FAILED" || die "SMOKE_TEST_KEEP_FAILED must be true or false"
is_bool "$SMOKE_TEST_CLEANUP" || die "SMOKE_TEST_CLEANUP must be true or false"
is_bool "$SMOKE_TEST_FORCE_RECREATE" || die "SMOKE_TEST_FORCE_RECREATE must be true or false"

SMOKE_TEST_IP_ONLY=${SMOKE_TEST_IPV4%%/*}
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

info "Checking SSH access to ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
ssh_transport_ssh 'true' || die "Cannot connect to Proxmox host ${PROXMOX_HOST}"

remote_check_command qm
remote_check_command ip
remote_check_command ping
remote_check_command mktemp
remote_check_command cat
remote_check_command grep

info "Checking template VMID ${TEMPLATE_VMID} on ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
ssh_transport_ssh "qm status '${TEMPLATE_VMID}' >/dev/null 2>&1" || die "Template VMID ${TEMPLATE_VMID} does not exist"
# shellcheck disable=SC2029
ssh_transport_ssh "qm config '${TEMPLATE_VMID}' | grep -Eq '^template: 1$'" || die "VMID ${TEMPLATE_VMID} is not a Proxmox template"
# shellcheck disable=SC2029
ssh_transport_ssh "qm config '${TEMPLATE_VMID}' | grep -Eq '^ide2: .*cloudinit'" || die "Template VMID ${TEMPLATE_VMID} is missing a cloud-init disk"
# shellcheck disable=SC2029
ssh_transport_ssh "qm config '${TEMPLATE_VMID}' | grep -Eq '^agent: .*enabled=1'" || die "Template VMID ${TEMPLATE_VMID} does not enable the QEMU guest agent"
# shellcheck disable=SC2029
ssh_transport_ssh "qm config '${TEMPLATE_VMID}' | grep -Eq '^citype: nocloud'" || die "Template VMID ${TEMPLATE_VMID} does not set citype nocloud"
# shellcheck disable=SC2029
ssh_transport_ssh "qm config '${TEMPLATE_VMID}' | grep -Eq '^serial0: socket'" || die "Template VMID ${TEMPLATE_VMID} is missing serial0 socket"
# shellcheck disable=SC2029
ssh_transport_ssh "qm config '${TEMPLATE_VMID}' | grep -Eq '^vga: ${EXPECTED_TEMPLATE_VGA}$'" || die "Template VMID ${TEMPLATE_VMID} is missing vga ${EXPECTED_TEMPLATE_VGA}"

info "Checking smoke-test bridge ${SMOKE_TEST_BRIDGE}"
# shellcheck disable=SC2029
ssh_transport_ssh "ip link show '${SMOKE_TEST_BRIDGE}' >/dev/null 2>&1" || die "Smoke-test bridge ${SMOKE_TEST_BRIDGE} does not exist"

if ssh_transport_ssh "qm status '${SMOKE_TEST_VMID}' >/dev/null 2>&1"; then
  if [[ "$SMOKE_TEST_FORCE_RECREATE" != "true" ]]; then
    die "Smoke-test VMID ${SMOKE_TEST_VMID} already exists; choose another VMID or set SMOKE_TEST_FORCE_RECREATE=true"
  fi

  warn "SMOKE_TEST_FORCE_RECREATE=true; destroying existing VMID ${SMOKE_TEST_VMID}"
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm stop '${SMOKE_TEST_VMID}' >/dev/null 2>&1 || true"
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm destroy '${SMOKE_TEST_VMID}' --purge"
fi

REMOTE_PUBLIC_KEY_FILE=$(ssh_transport_ssh "mktemp '/tmp/template-smoke-key.XXXXXX.pub'")
# shellcheck disable=SC2029
ssh "${SSH_TRANSPORT_SSH_ARGS[@]}" "$SSH_TRANSPORT_TARGET" "cat > '${REMOTE_PUBLIC_KEY_FILE}'" <"$SMOKE_TEST_PUBLIC_KEY_PATH"

info "Cloning template ${TEMPLATE_VMID} to smoke-test VM ${SMOKE_TEST_VMID} (${SMOKE_TEST_NAME})"
# shellcheck disable=SC2029
ssh_transport_ssh "qm clone '${TEMPLATE_VMID}' '${SMOKE_TEST_VMID}' --name '${SMOKE_TEST_NAME}' --full 1"
SMOKE_VM_CREATED=true

info "Applying smoke-test cloud-init data"
# shellcheck disable=SC2029
ssh_transport_ssh "qm set '${SMOKE_TEST_VMID}' --net0 'virtio,bridge=${SMOKE_TEST_BRIDGE}' --agent enabled=1 --citype nocloud --ciuser '${SMOKE_TEST_USER}' --ipconfig0 'ip=${SMOKE_TEST_IPV4},gw=${SMOKE_TEST_GATEWAY}' --nameserver '${SMOKE_TEST_DNS}' --sshkeys '${REMOTE_PUBLIC_KEY_FILE}' >/dev/null"
if [[ -n "${SMOKE_TEST_SEARCHDOMAIN:-}" ]]; then
  # shellcheck disable=SC2029
  ssh_transport_ssh "qm set '${SMOKE_TEST_VMID}' --searchdomain '${SMOKE_TEST_SEARCHDOMAIN}' >/dev/null"
fi

info "Dumping generated cloud-init data"
# shellcheck disable=SC2029
ssh_transport_ssh "qm cloudinit dump '${SMOKE_TEST_VMID}' meta >/dev/null && qm cloudinit dump '${SMOKE_TEST_VMID}' user >/dev/null && qm cloudinit dump '${SMOKE_TEST_VMID}' network >/dev/null"

info "Starting smoke-test VM ${SMOKE_TEST_VMID}"
# shellcheck disable=SC2029
ssh_transport_ssh "qm start '${SMOKE_TEST_VMID}'"

info "Waiting for Proxmox host to reach ${SMOKE_TEST_IP_ONLY}"
deadline=$((SECONDS + SMOKE_TEST_BOOT_TIMEOUT_SECONDS))
until ssh_transport_ssh "ping -c 1 -W 2 '${SMOKE_TEST_IP_ONLY}' >/dev/null 2>&1"; do
  if (( SECONDS >= deadline )); then
    fail_keep_vm "Timed out waiting for Proxmox host to reach ${SMOKE_TEST_IP_ONLY}; kept VM for console/noVNC debugging"
  fi
  sleep 5
done
ok "Proxmox host can reach ${SMOKE_TEST_IP_ONLY}"

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

info "Waiting for QEMU guest agent"
deadline=$((SECONDS + SMOKE_TEST_BOOT_TIMEOUT_SECONDS))
until ssh_transport_ssh "qm agent '${SMOKE_TEST_VMID}' ping >/dev/null 2>&1"; do
  if (( SECONDS >= deadline )); then
    fail_keep_vm "Timed out waiting for qm agent ${SMOKE_TEST_VMID} ping after SSH succeeded; qemu-guest-agent may be missing or stopped"
  fi
  sleep 5
done
ok "QEMU guest agent responded"

info "Checking guest IP ${SMOKE_TEST_IP_ONLY} through QEMU guest agent"
# shellcheck disable=SC2029
ssh_transport_ssh "qm agent '${SMOKE_TEST_VMID}' network-get-interfaces | grep -F '${SMOKE_TEST_IP_ONLY}' >/dev/null" || die "Guest agent did not report ${SMOKE_TEST_IP_ONLY}"
guest_ssh "systemctl is-active qemu-guest-agent" >/dev/null
ok "QEMU guest agent service is healthy"

info "Testing graceful shutdown through Proxmox"
# shellcheck disable=SC2029
ssh_transport_ssh "qm shutdown '${SMOKE_TEST_VMID}' --timeout 120"
# shellcheck disable=SC2029
ssh_transport_ssh "i=0; while [ \"\$i\" -lt 120 ]; do if qm status '${SMOKE_TEST_VMID}' | grep -Eq '^status:[[:space:]]+stopped$'; then exit 0; fi; i=\$((i + 1)); sleep 1; done; exit 1" || die "Smoke-test VM ${SMOKE_TEST_VMID} did not shut down cleanly"
ok "Graceful shutdown succeeded"

SMOKE_TEST_FAILED=false
ok "Template smoke test passed"
