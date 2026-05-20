#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }
die() { error "$*"; exit 1; }

usage() {
  printf 'Usage: %s [config.env]\n' "${0##*/}" >&2
}

script_dir() {
  local source_dir
  source_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  printf '%s\n' "$source_dir"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

check_local_command() {
  local command_name=$1

  if command_exists "$command_name"; then
    ok "Local command available: ${command_name}"
  else
    error "Local command missing: ${command_name}"
    MISSING=1
  fi
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

check_remote_command() {
  local command_name=$1

  # shellcheck disable=SC2029
  if ssh_transport_ssh "command -v '${command_name}' >/dev/null 2>&1"; then
    ok "Remote command available on ${SSH_TRANSPORT_DISPLAY}: ${command_name}"
  else
    error "Remote command missing on ${SSH_TRANSPORT_DISPLAY}: ${command_name}"
    MISSING=1
  fi
}

check_remote_any() {
  local label=$1
  shift

  local remote_check=''
  local command_name

  for command_name in "$@"; do
    if [[ -n "$remote_check" ]]; then
      remote_check+=" || "
    fi
    remote_check+="command -v '${command_name}' >/dev/null 2>&1"
  done

  # shellcheck disable=SC2029
  if ssh_transport_ssh "$remote_check"; then
    ok "Remote command available for ${label} on ${SSH_TRANSPORT_DISPLAY}: $*"
  else
    error "No remote command available for ${label} on ${SSH_TRANSPORT_DISPLAY}: $*"
    MISSING=1
  fi
}

check_remote_proxmox_marker() {
  # shellcheck disable=SC2029
  if ssh_transport_ssh "test -d /etc/pve"; then
    ok "Remote Proxmox marker found on ${SSH_TRANSPORT_DISPLAY}: /etc/pve"
  else
    error "Remote Proxmox marker missing on ${SSH_TRANSPORT_DISPLAY}: /etc/pve"
    MISSING=1
  fi
}

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

SCRIPT_DIR=$(script_dir)
ROOT_DIR=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)
# shellcheck source=scripts/ssh-transport.sh
. "${SCRIPT_DIR}/ssh-transport.sh"
MISSING=0

info "Checking local required tools"
local_required=(
  bash
  make
  ssh
  rsync
  awk
  basename
  cp
  date
  dirname
  grep
  mkdir
  mktemp
  pwd
  sort
  tee
)

for command_name in "${local_required[@]}"; do
  check_local_command "$command_name"
done

if command_exists shellcheck; then
  ok "Optional local command available: shellcheck"
else
  warn "Optional local command missing: shellcheck; make shellcheck will fail until installed"
fi

if [[ $# -eq 0 ]]; then
  if [[ "$MISSING" -ne 0 ]]; then
    die "One or more required local tools are missing"
  fi
  ok "Local tool check complete"
  exit 0
fi

CONFIG_FILE=$1
if [[ ! -f "$CONFIG_FILE" ]]; then
  die "Config file not found: ${CONFIG_FILE}"
fi

info "Validating config before remote tool checks"
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

ssh_transport_init "${TEMPLATE_BUILDER_SSH_CONFIG:-}" "$PROXMOX_HOST"

info "Checking SSH access to ${SSH_TRANSPORT_DISPLAY}"
if ! ssh_transport_ssh 'true'; then
  error "Cannot connect to Proxmox host ${PROXMOX_HOST}"
  if [[ -n "${SSH_TRANSPORT_CONFIG_SOURCE:-}" ]]; then
    error "SSH transport config was loaded from ${SSH_TRANSPORT_CONFIG_SOURCE}; check SSH_HOST, SSH_USER, SSH_KEY_PATH, and the remote authorized_keys file"
  else
    error "No SSH transport config was loaded; ensure ${PROXMOX_HOST} resolves through SSH config, DNS, or /etc/hosts"
  fi
  die "Remote SSH access check failed"
fi

info "Checking remote required tools on ${SSH_TRANSPORT_DISPLAY}"
remote_required=(
  bash
  qm
  pvesm
  ip
  rsync
  awk
  grep
  dirname
  mkdir
  mv
  pwd
)

for command_name in "${remote_required[@]}"; do
  check_remote_command "$command_name"
done

check_remote_any "image download" curl wget

if [[ -n "${IMAGE_SHA256:-}" ]]; then
  check_remote_command sha256sum
elif [[ -n "${IMAGE_SHA512:-}" ]]; then
  check_remote_command sha512sum
else
  error "Set IMAGE_SHA256 or IMAGE_SHA512 before importing cloud images"
  MISSING=1
fi

check_remote_proxmox_marker

PREPARE_GUEST_IMAGE=${PREPARE_GUEST_IMAGE:-true}
GUEST_PREP_MODE=${GUEST_PREP_MODE:-full}
if [[ "$PREPARE_GUEST_IMAGE" == "true" ]]; then
  if [[ "$GUEST_PREP_MODE" != "safe" && "$GUEST_PREP_MODE" != "full" ]]; then
    error "GUEST_PREP_MODE must be one of: safe full"
    MISSING=1
  fi
  check_remote_command timeout
  check_remote_command qemu-img
  if [[ "$GUEST_PREP_MODE" == "full" ]]; then
    check_remote_command virt-customize
    check_remote_command virt-sysprep
  fi
elif [[ "$PREPARE_GUEST_IMAGE" != "false" ]]; then
  error "PREPARE_GUEST_IMAGE must be true or false"
  MISSING=1
fi

if [[ "$MISSING" -ne 0 ]]; then
  die "One or more required tools are missing"
fi

ok "Tool check complete"
