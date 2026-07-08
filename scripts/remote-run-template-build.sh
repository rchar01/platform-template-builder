#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  printf 'Usage: %s <config.env>\n' "${0##*/}" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

CONFIG_FILE=$1
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)
# shellcheck source=scripts/common.sh
. "${SCRIPT_DIR}/common.sh"
# shellcheck source=scripts/ssh-transport.sh
. "${SCRIPT_DIR}/ssh-transport.sh"
CONFIG_BASENAME=$(basename -- "$CONFIG_FILE")
ptb_is_safe_file_name "$CONFIG_BASENAME" || die "Config file basename may contain only letters, numbers, dot, underscore, and dash"

"${SCRIPT_DIR}/validate-config.sh" "$CONFIG_FILE"
ptb_load_template_config "$CONFIG_FILE" "$ROOT_DIR"

ptb_command_exists ssh || die "ssh is required"
ptb_command_exists rsync || die "rsync is required"
ptb_command_exists tee || die "tee is required"

ssh_transport_init "${TEMPLATE_BUILDER_SSH_CONFIG:-}" "$PROXMOX_HOST"

info "Checking SSH access to ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
ssh_transport_ssh 'true' || die "Cannot connect to Proxmox host ${PROXMOX_HOST}. Check TEMPLATE_BUILDER_SSH_CONFIG, SSH_HOST, SSH_USER, SSH_KEY_PATH, and the remote authorized_keys file."

mkdir -p "${ROOT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${ROOT_DIR}/logs/${TIMESTAMP}-${TEMPLATE_NAME}.log"
ESC_PROXMOX_REMOTE_DIR=$(ptb_shell_quote "$PROXMOX_REMOTE_DIR")
ESC_REMOTE_SCRIPT_DIR=$(ptb_shell_quote "${PROXMOX_REMOTE_DIR}/scripts")
ESC_REMOTE_CONFIG_DIR=$(ptb_shell_quote "${PROXMOX_REMOTE_DIR}/configs")
ESC_REMOTE_IMAGE_DIR=$(ptb_shell_quote "${PROXMOX_REMOTE_DIR}/configs/images")
ESC_REMOTE_CACHE_DIR=$(ptb_shell_quote "${PROXMOX_REMOTE_DIR}/.cache/images")
ESC_REMOTE_CONFIG_FILE=$(ptb_shell_quote "./configs/${CONFIG_BASENAME}")

info "Preparing remote directory ${SSH_TRANSPORT_DISPLAY}:${PROXMOX_REMOTE_DIR}"
# shellcheck disable=SC2029
ssh_transport_ssh "mkdir -p ${ESC_REMOTE_SCRIPT_DIR} ${ESC_REMOTE_CONFIG_DIR} ${ESC_REMOTE_IMAGE_DIR} ${ESC_REMOTE_CACHE_DIR}"

info "Syncing scripts to ${SSH_TRANSPORT_DISPLAY}"
rsync -az --delete -e "$SSH_TRANSPORT_RSYNC_RSH" "${ROOT_DIR}/scripts/" "${SSH_TRANSPORT_TARGET}:${PROXMOX_REMOTE_DIR}/scripts/"

info "Syncing selected config ${CONFIG_BASENAME}"
rsync -az -e "$SSH_TRANSPORT_RSYNC_RSH" "$CONFIG_FILE" "${SSH_TRANSPORT_TARGET}:${PROXMOX_REMOTE_DIR}/configs/${CONFIG_BASENAME}"

info "Syncing image profiles"
rsync -az -e "$SSH_TRANSPORT_RSYNC_RSH" "${ROOT_DIR}/configs/images/" "${SSH_TRANSPORT_TARGET}:${PROXMOX_REMOTE_DIR}/configs/images/"

info "Starting remote template build; log: ${LOG_FILE}"
# shellcheck disable=SC2029
ssh_transport_ssh "cd ${ESC_PROXMOX_REMOTE_DIR} && ./scripts/build-proxmox-cloud-template.sh ${ESC_REMOTE_CONFIG_FILE}" 2>&1 | tee "$LOG_FILE"

ok "Remote build completed"
printf 'Log: %s\n' "$LOG_FILE"
