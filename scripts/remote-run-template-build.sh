#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
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
CONFIG_BASENAME=$(basename -- "$CONFIG_FILE")

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
command_exists tee || die "tee is required"

mkdir -p "${ROOT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${ROOT_DIR}/logs/${TIMESTAMP}-${TEMPLATE_NAME}.log"

info "Preparing remote directory ${PROXMOX_HOST}:${PROXMOX_REMOTE_DIR}"
# shellcheck disable=SC2029
ssh "$PROXMOX_HOST" "mkdir -p '${PROXMOX_REMOTE_DIR}/scripts' '${PROXMOX_REMOTE_DIR}/configs' '${PROXMOX_REMOTE_DIR}/configs/images' '${PROXMOX_REMOTE_DIR}/.cache/images'"

info "Syncing scripts to ${PROXMOX_HOST}"
rsync -az --delete "${ROOT_DIR}/scripts/" "${PROXMOX_HOST}:${PROXMOX_REMOTE_DIR}/scripts/"

info "Syncing selected config ${CONFIG_BASENAME}"
rsync -az "$CONFIG_FILE" "${PROXMOX_HOST}:${PROXMOX_REMOTE_DIR}/configs/${CONFIG_BASENAME}"

info "Syncing image profiles"
rsync -az "${ROOT_DIR}/configs/images/" "${PROXMOX_HOST}:${PROXMOX_REMOTE_DIR}/configs/images/"

info "Starting remote template build; log: ${LOG_FILE}"
# shellcheck disable=SC2029
ssh "$PROXMOX_HOST" "cd '${PROXMOX_REMOTE_DIR}' && ./scripts/build-proxmox-cloud-template.sh './configs/${CONFIG_BASENAME}'" 2>&1 | tee "$LOG_FILE"

ok "Remote build completed"
printf 'Log: %s\n' "$LOG_FILE"
