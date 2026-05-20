#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  printf 'Usage: %s <payload.env> <prepare|diagnostics|qga-check|shutdown|cleanup>\n' "${0##*/}" >&2
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

is_safe_relative_path() {
  [[ "$1" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
  [[ "$1" != /* ]] || return 1
  case $1 in
    *'//'* | *'/./'* | *'/../'* | './'* | '../'* | *'/.' | *'/..') return 1 ;;
    *) return 0 ;;
  esac
}

is_safe_run_id() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]]
}

is_safe_vm_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]]
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_var() {
  local name=$1
  if [[ -z "${!name:-}" ]]; then
    die "Payload variable ${name} is missing or empty"
  fi
}

load_payload() {
  local -A seen_keys=()
  local key
  local line
  local payload_file=$1
  local value

  [[ -f "$payload_file" ]] || die "Payload file not found: ${payload_file}"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    [[ "$line" != \#* ]] || continue
    [[ "$line" == *=* ]] || die "Invalid payload line: ${line}"

    key=${line%%=*}
    value=${line#*=}
    [[ -z "${seen_keys[$key]:-}" ]] || die "Duplicate payload key: ${key}"
    seen_keys[$key]=true

    case $key in
      TEMPLATE_VMID | SMOKE_TEST_VMID | SMOKE_TEST_NAME | SMOKE_TEST_IPV4 | SMOKE_TEST_GATEWAY | \
        SMOKE_TEST_DNS | SMOKE_TEST_BRIDGE | SMOKE_TEST_USER | SMOKE_TEST_SEARCHDOMAIN | \
        SMOKE_TEST_FORCE_RECREATE | SMOKE_TEST_BOOT_TIMEOUT_SECONDS | EXPECTED_TEMPLATE_VGA | \
        SMOKE_TEST_PUBLIC_KEY_FILE | SMOKE_TEST_RUN_ID)
        printf -v "$key" '%s' "$value"
        ;;
      *)
        die "Unknown payload key: ${key}"
        ;;
    esac
  done <"$payload_file"
}

validate_payload() {
  local payload_dir
  local required

  for required in \
    TEMPLATE_VMID \
    SMOKE_TEST_VMID \
    SMOKE_TEST_NAME \
    SMOKE_TEST_IPV4 \
    SMOKE_TEST_GATEWAY \
    SMOKE_TEST_DNS \
    SMOKE_TEST_BRIDGE \
    SMOKE_TEST_USER \
    SMOKE_TEST_FORCE_RECREATE \
    SMOKE_TEST_BOOT_TIMEOUT_SECONDS \
    EXPECTED_TEMPLATE_VGA \
    SMOKE_TEST_PUBLIC_KEY_FILE \
    SMOKE_TEST_RUN_ID; do
    require_var "$required"
  done

  is_number "$TEMPLATE_VMID" || die "TEMPLATE_VMID must be numeric"
  is_number "$SMOKE_TEST_VMID" || die "SMOKE_TEST_VMID must be numeric"
  is_ipv4_cidr "$SMOKE_TEST_IPV4" || die "SMOKE_TEST_IPV4 must use IPv4 CIDR format"
  is_ipv4 "$SMOKE_TEST_GATEWAY" || die "SMOKE_TEST_GATEWAY must be an IPv4 address"
  is_ipv4 "$SMOKE_TEST_DNS" || die "SMOKE_TEST_DNS must be an IPv4 address"
  is_safe_bridge_name "$SMOKE_TEST_BRIDGE" || die "SMOKE_TEST_BRIDGE has unsafe characters"
  is_safe_guest_user "$SMOKE_TEST_USER" || die "SMOKE_TEST_USER must be a safe Linux user name"
  is_safe_vm_name "$SMOKE_TEST_NAME" || die "SMOKE_TEST_NAME has unsafe characters"
  is_bool "$SMOKE_TEST_FORCE_RECREATE" || die "SMOKE_TEST_FORCE_RECREATE must be true or false"
  is_number "$SMOKE_TEST_BOOT_TIMEOUT_SECONDS" || die "SMOKE_TEST_BOOT_TIMEOUT_SECONDS must be numeric"
  (( SMOKE_TEST_BOOT_TIMEOUT_SECONDS > 0 )) || die "SMOKE_TEST_BOOT_TIMEOUT_SECONDS must be greater than 0"
  is_safe_relative_path "$SMOKE_TEST_PUBLIC_KEY_FILE" || die "SMOKE_TEST_PUBLIC_KEY_FILE must be a safe relative path"
  is_safe_run_id "$SMOKE_TEST_RUN_ID" || die "SMOKE_TEST_RUN_ID must be a safe identifier"
  if [[ "$ACTION" == "prepare" ]]; then
    [[ -f "$SMOKE_TEST_PUBLIC_KEY_FILE" ]] || die "Smoke-test public key file not found: ${SMOKE_TEST_PUBLIC_KEY_FILE}"
  fi

  case $EXPECTED_TEMPLATE_VGA in
    serial0 | std) ;;
    *) die "EXPECTED_TEMPLATE_VGA must be one of: serial0 std" ;;
  esac

  if [[ -n "${SMOKE_TEST_SEARCHDOMAIN:-}" ]]; then
    is_safe_domain_name "$SMOKE_TEST_SEARCHDOMAIN" || die "SMOKE_TEST_SEARCHDOMAIN must be a DNS search domain"
  fi

  SMOKE_TEST_IP_ONLY=${SMOKE_TEST_IPV4%%/*}
  case $PAYLOAD_FILE in
    */*) payload_dir=${PAYLOAD_FILE%/*} ;;
    *) payload_dir=. ;;
  esac
  SMOKE_TEST_OWNERSHIP_MARKER=${payload_dir}/created.marker
}

remote_check_command() {
  local command_name=$1

  command_exists "$command_name" || die "Remote command missing: ${command_name}"
}

check_required_commands() {
  local command_name

  for command_name in qm ip ping grep; do
    remote_check_command "$command_name"
  done
}

write_ownership_marker() {
  {
    printf 'MARKER_VERSION=1\n'
    printf 'TEMPLATE_VMID=%s\n' "$TEMPLATE_VMID"
    printf 'SMOKE_TEST_VMID=%s\n' "$SMOKE_TEST_VMID"
    printf 'SMOKE_TEST_NAME=%s\n' "$SMOKE_TEST_NAME"
    printf 'SMOKE_TEST_RUN_ID=%s\n' "$SMOKE_TEST_RUN_ID"
  } >"$SMOKE_TEST_OWNERSHIP_MARKER"
}

marker_matches_payload() {
  local marker_version=''
  local marker_template_vmid=''
  local marker_smoke_test_name=''
  local marker_smoke_test_run_id=''
  local marker_smoke_test_vmid=''
  local key
  local line
  local value

  [[ -f "$SMOKE_TEST_OWNERSHIP_MARKER" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    [[ "$line" == *=* ]] || return 1
    key=${line%%=*}
    value=${line#*=}

    case $key in
      MARKER_VERSION) marker_version=$value ;;
      TEMPLATE_VMID) marker_template_vmid=$value ;;
      SMOKE_TEST_VMID) marker_smoke_test_vmid=$value ;;
      SMOKE_TEST_NAME) marker_smoke_test_name=$value ;;
      SMOKE_TEST_RUN_ID) marker_smoke_test_run_id=$value ;;
      *) return 1 ;;
    esac
  done <"$SMOKE_TEST_OWNERSHIP_MARKER"

  [[ "$marker_version" == "1" && \
    "$marker_template_vmid" == "$TEMPLATE_VMID" && \
    "$marker_smoke_test_vmid" == "$SMOKE_TEST_VMID" && \
    "$marker_smoke_test_name" == "$SMOKE_TEST_NAME" && \
    "$marker_smoke_test_run_id" == "$SMOKE_TEST_RUN_ID" ]]
}

destroy_existing_smoke_vmid_for_force_recreate() {
  qm status "$SMOKE_TEST_VMID" >/dev/null 2>&1 || return 0
  qm stop "$SMOKE_TEST_VMID" >/dev/null 2>&1 || true
  qm destroy "$SMOKE_TEST_VMID" --purge >/dev/null 2>&1 || true
}

destroy_created_smoke_vm() {
  if ! marker_matches_payload; then
    warn "Skipping cleanup for VMID ${SMOKE_TEST_VMID}; this run did not create it"
    return 0
  fi

  destroy_existing_smoke_vmid_for_force_recreate
  rm -f -- "$SMOKE_TEST_OWNERSHIP_MARKER"
}

print_diagnostics() {
  if ! marker_matches_payload; then
    warn "Skipping smoke-test VM diagnostics because this run did not create VMID ${SMOKE_TEST_VMID}"
    return 0
  fi

  warn "Smoke-test VM ${SMOKE_TEST_VMID} diagnostics follow"
  if ! qm status "$SMOKE_TEST_VMID" >/dev/null 2>&1; then
    warn "Smoke-test VM ${SMOKE_TEST_VMID} does not exist"
    return 0
  fi

  printf '%s\n' '--- qm status ---'
  qm status "$SMOKE_TEST_VMID" || true
  printf '%s\n' '--- qm config ---'
  qm config "$SMOKE_TEST_VMID" || true
  printf '%s\n' '--- cloud-init network ---'
  qm cloudinit dump "$SMOKE_TEST_VMID" network || true
  printf '%s\n' '--- qemu guest agent ping ---'
  qm agent "$SMOKE_TEST_VMID" ping || true
}

prepare_smoke_vm() {
  check_required_commands
  rm -f -- "$SMOKE_TEST_OWNERSHIP_MARKER"

  info "Checking template VMID ${TEMPLATE_VMID}"
  qm status "$TEMPLATE_VMID" >/dev/null 2>&1 || die "Template VMID ${TEMPLATE_VMID} does not exist"
  qm config "$TEMPLATE_VMID" | grep -Eq '^template: 1$' || die "VMID ${TEMPLATE_VMID} is not a Proxmox template"
  qm config "$TEMPLATE_VMID" | grep -Eq '^ide2: .*cloudinit' || die "Template VMID ${TEMPLATE_VMID} is missing a cloud-init disk"
  qm config "$TEMPLATE_VMID" | grep -Eq '^agent: .*enabled=1' || die "Template VMID ${TEMPLATE_VMID} does not enable the QEMU guest agent"
  qm config "$TEMPLATE_VMID" | grep -Eq '^citype: nocloud' || die "Template VMID ${TEMPLATE_VMID} does not set citype nocloud"
  qm config "$TEMPLATE_VMID" | grep -Eq '^serial0: socket' || die "Template VMID ${TEMPLATE_VMID} is missing serial0 socket"
  qm config "$TEMPLATE_VMID" | grep -Eq "^vga: ${EXPECTED_TEMPLATE_VGA}$" || die "Template VMID ${TEMPLATE_VMID} is missing vga ${EXPECTED_TEMPLATE_VGA}"

  info "Checking smoke-test bridge ${SMOKE_TEST_BRIDGE}"
  ip link show "$SMOKE_TEST_BRIDGE" >/dev/null 2>&1 || die "Smoke-test bridge ${SMOKE_TEST_BRIDGE} does not exist"

  if qm status "$SMOKE_TEST_VMID" >/dev/null 2>&1; then
    if [[ "$SMOKE_TEST_FORCE_RECREATE" != "true" ]]; then
      die "Smoke-test VMID ${SMOKE_TEST_VMID} already exists; choose another VMID or set SMOKE_TEST_FORCE_RECREATE=true"
    fi

    warn "SMOKE_TEST_FORCE_RECREATE=true; destroying existing VMID ${SMOKE_TEST_VMID}"
    destroy_existing_smoke_vmid_for_force_recreate
  fi

  info "Cloning template ${TEMPLATE_VMID} to smoke-test VM ${SMOKE_TEST_VMID} (${SMOKE_TEST_NAME})"
  qm clone "$TEMPLATE_VMID" "$SMOKE_TEST_VMID" --name "$SMOKE_TEST_NAME" --full 1
  write_ownership_marker

  info "Applying smoke-test cloud-init data"
  qm set "$SMOKE_TEST_VMID" \
    --net0 "virtio,bridge=${SMOKE_TEST_BRIDGE}" \
    --agent enabled=1 \
    --citype nocloud \
    --ciuser "$SMOKE_TEST_USER" \
    --ipconfig0 "ip=${SMOKE_TEST_IPV4},gw=${SMOKE_TEST_GATEWAY}" \
    --nameserver "$SMOKE_TEST_DNS" \
    --sshkeys "$SMOKE_TEST_PUBLIC_KEY_FILE" >/dev/null

  if [[ -n "${SMOKE_TEST_SEARCHDOMAIN:-}" ]]; then
    qm set "$SMOKE_TEST_VMID" --searchdomain "$SMOKE_TEST_SEARCHDOMAIN" >/dev/null
  fi

  info "Dumping generated cloud-init data"
  qm cloudinit dump "$SMOKE_TEST_VMID" meta >/dev/null
  qm cloudinit dump "$SMOKE_TEST_VMID" user >/dev/null
  qm cloudinit dump "$SMOKE_TEST_VMID" network >/dev/null

  info "Starting smoke-test VM ${SMOKE_TEST_VMID}"
  qm start "$SMOKE_TEST_VMID"

  info "Waiting for Proxmox host to reach ${SMOKE_TEST_IP_ONLY}"
  deadline=$((SECONDS + SMOKE_TEST_BOOT_TIMEOUT_SECONDS))
  until ping -c 1 -W 2 "$SMOKE_TEST_IP_ONLY" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      die "Timed out waiting for Proxmox host to reach ${SMOKE_TEST_IP_ONLY}"
    fi
    sleep 5
  done
  ok "Proxmox host can reach ${SMOKE_TEST_IP_ONLY}"
}

check_qga() {
  info "Waiting for QEMU guest agent"
  deadline=$((SECONDS + SMOKE_TEST_BOOT_TIMEOUT_SECONDS))
  until qm agent "$SMOKE_TEST_VMID" ping >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      die "Timed out waiting for qm agent ${SMOKE_TEST_VMID} ping after SSH succeeded; qemu-guest-agent may be missing or stopped"
    fi
    sleep 5
  done
  ok "QEMU guest agent responded"

  info "Checking guest IP ${SMOKE_TEST_IP_ONLY} through QEMU guest agent"
  qm agent "$SMOKE_TEST_VMID" network-get-interfaces | grep -F "$SMOKE_TEST_IP_ONLY" >/dev/null || die "Guest agent did not report ${SMOKE_TEST_IP_ONLY}"
}

shutdown_smoke_vm() {
  info "Testing graceful shutdown through Proxmox"
  qm shutdown "$SMOKE_TEST_VMID" --timeout 120

  deadline=$((SECONDS + 120))
  until qm status "$SMOKE_TEST_VMID" | grep -Eq '^status:[[:space:]]+stopped$'; do
    if (( SECONDS >= deadline )); then
      die "Smoke-test VM ${SMOKE_TEST_VMID} did not shut down cleanly"
    fi
    sleep 1
  done
  ok "Graceful shutdown succeeded"
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

PAYLOAD_FILE=$1
ACTION=$2

load_payload "$PAYLOAD_FILE"
validate_payload

case $ACTION in
  prepare) prepare_smoke_vm ;;
  diagnostics) print_diagnostics ;;
  qga-check) check_qga ;;
  shutdown) shutdown_smoke_vm ;;
  cleanup) destroy_created_smoke_vm ;;
  *) usage; exit 2 ;;
esac
