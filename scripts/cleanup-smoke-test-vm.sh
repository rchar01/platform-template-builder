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
command_exists rsync || die "rsync is required"

SMOKE_TEST_VMID=${SMOKE_TEST_VMID:-9900}
SMOKE_TEST_NAME=${SMOKE_TEST_NAME:-platform-template-smoke-${SMOKE_TEST_VMID}}
[[ "$SMOKE_TEST_VMID" =~ ^[0-9]+$ ]] || die "SMOKE_TEST_VMID must be numeric"

ssh_transport_init "${TEMPLATE_BUILDER_SSH_CONFIG:-}" "$PROXMOX_HOST"

info "Checking SSH access to ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
ssh_transport_ssh 'true' || die "Cannot connect to Proxmox host ${PROXMOX_HOST}. Check TEMPLATE_BUILDER_SSH_CONFIG, SSH_HOST, SSH_USER, SSH_KEY_PATH, and the remote authorized_keys file."

info "Checking smoke-test VMID ${SMOKE_TEST_VMID} on ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
if ! ssh_transport_ssh "qm status '${SMOKE_TEST_VMID}' >/dev/null 2>&1"; then
  die "Smoke-test VMID ${SMOKE_TEST_VMID} does not exist on ${SSH_TRANSPORT_DISPLAY}"
fi

warn "Target for cleanup: smoke-test VMID ${SMOKE_TEST_VMID} (${SMOKE_TEST_NAME}) on ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
ssh_transport_ssh "qm config '${SMOKE_TEST_VMID}'"

if [[ "${CLEANUP_ASSUME_YES:-false}" != "true" ]]; then
  printf 'Type VMID %s to destroy: ' "$SMOKE_TEST_VMID"
  read -r confirmation
  if [[ "$confirmation" != "$SMOKE_TEST_VMID" ]]; then
    die "Confirmation did not match; cleanup aborted"
  fi
fi

info "Syncing destroy helper to ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
ssh_transport_ssh "mkdir -p '${PROXMOX_REMOTE_DIR}/scripts'"
rsync -az -e "$SSH_TRANSPORT_RSYNC_RSH" "${SCRIPT_DIR}/proxmox-vm-destroy.sh" "${SSH_TRANSPORT_TARGET}:${PROXMOX_REMOTE_DIR}/scripts/proxmox-vm-destroy.sh"

warn "Destroying only smoke-test VMID ${SMOKE_TEST_VMID}"
# shellcheck disable=SC2029
ssh_transport_ssh "cd '${PROXMOX_REMOTE_DIR}' && . './scripts/proxmox-vm-destroy.sh' && proxmox_vm_destroy '${SMOKE_TEST_VMID}'"

ok "Destroyed smoke-test VMID ${SMOKE_TEST_VMID}"
