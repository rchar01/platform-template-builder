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

info "Checking VMID ${TEMPLATE_VMID} on ${PROXMOX_HOST}"
# shellcheck disable=SC2029
if ! ssh "$PROXMOX_HOST" "qm status '${TEMPLATE_VMID}' >/dev/null 2>&1"; then
  die "VMID ${TEMPLATE_VMID} does not exist on ${PROXMOX_HOST}"
fi

warn "Target for cleanup: VMID ${TEMPLATE_VMID} (${TEMPLATE_NAME}) on ${PROXMOX_HOST}"
# shellcheck disable=SC2029
ssh "$PROXMOX_HOST" "qm config '${TEMPLATE_VMID}'"

if [[ "${CLEANUP_ASSUME_YES:-false}" != "true" ]]; then
  printf 'Type VMID %s to destroy: ' "$TEMPLATE_VMID"
  read -r confirmation
  if [[ "$confirmation" != "$TEMPLATE_VMID" ]]; then
    die "Confirmation did not match; cleanup aborted"
  fi
fi

warn "Destroying only VMID ${TEMPLATE_VMID}"
# shellcheck disable=SC2029
ssh "$PROXMOX_HOST" "status=\$(qm status '${TEMPLATE_VMID}' | awk -F': ' '/status:/ { print \$2 }'); if [ \"\$status\" = 'running' ]; then qm shutdown '${TEMPLATE_VMID}' --timeout 60 || qm stop '${TEMPLATE_VMID}'; fi; qm destroy '${TEMPLATE_VMID}' --purge"

ok "Destroyed VMID ${TEMPLATE_VMID}"
