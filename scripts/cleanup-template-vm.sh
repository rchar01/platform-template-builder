#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
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

"${SCRIPT_DIR}/validate-config.sh" "$CONFIG_FILE"
ptb_load_template_config "$CONFIG_FILE" "$ROOT_DIR"

ptb_command_exists ssh || die "ssh is required"
ptb_command_exists rsync || die "rsync is required"

ssh_transport_init "${TEMPLATE_BUILDER_SSH_CONFIG:-}" "$PROXMOX_HOST"

info "Checking SSH access to ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
ssh_transport_ssh 'true' || die "Cannot connect to Proxmox host ${PROXMOX_HOST}. Check TEMPLATE_BUILDER_SSH_CONFIG, SSH_HOST, SSH_USER, SSH_KEY_PATH, and the remote authorized_keys file."

info "Checking VMID ${TEMPLATE_VMID} on ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
if ! ssh_transport_ssh "qm status '${TEMPLATE_VMID}' >/dev/null 2>&1"; then
  die "VMID ${TEMPLATE_VMID} does not exist on ${SSH_TRANSPORT_DISPLAY}"
fi

warn "Target for cleanup: VMID ${TEMPLATE_VMID} (${TEMPLATE_NAME}) on ${SSH_TRANSPORT_DISPLAY}"
# shellcheck disable=SC2029
ssh_transport_ssh "qm config '${TEMPLATE_VMID}'"

if [[ "${CLEANUP_ASSUME_YES:-false}" != "true" ]]; then
  printf 'Type VMID %s to destroy: ' "$TEMPLATE_VMID"
  read -r confirmation
  if [[ "$confirmation" != "$TEMPLATE_VMID" ]]; then
    die "Confirmation did not match; cleanup aborted"
  fi
fi

warn "Destroying only VMID ${TEMPLATE_VMID}"
info "Syncing destroy helper to ${SSH_TRANSPORT_DISPLAY}"
ESC_PROXMOX_REMOTE_DIR=$(ptb_shell_quote "$PROXMOX_REMOTE_DIR")
ESC_REMOTE_SCRIPT_DIR=$(ptb_shell_quote "${PROXMOX_REMOTE_DIR}/scripts")
# shellcheck disable=SC2029
ssh_transport_ssh "mkdir -p ${ESC_REMOTE_SCRIPT_DIR}"
rsync -az -e "$SSH_TRANSPORT_RSYNC_RSH" "${SCRIPT_DIR}/proxmox-vm-destroy.sh" "${SSH_TRANSPORT_TARGET}:${PROXMOX_REMOTE_DIR}/scripts/proxmox-vm-destroy.sh"
# shellcheck disable=SC2029
ssh_transport_ssh "cd ${ESC_PROXMOX_REMOTE_DIR} && . './scripts/proxmox-vm-destroy.sh' && proxmox_vm_destroy '${TEMPLATE_VMID}'"

ok "Destroyed VMID ${TEMPLATE_VMID}"
