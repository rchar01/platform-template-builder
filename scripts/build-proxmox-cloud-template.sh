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

storage_exists() {
  local storage=$1
  pvesm status | awk 'NR > 1 { print $1 }' | grep -Fxq "$storage"
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

vm_exists() {
  qm status "$TEMPLATE_VMID" >/dev/null 2>&1
}

destroy_existing_vm() {
  local status

  warn "FORCE_RECREATE=true; destroying existing VMID ${TEMPLATE_VMID} (${TEMPLATE_NAME})"
  qm config "$TEMPLATE_VMID"

  status=$(qm status "$TEMPLATE_VMID" | awk -F': ' '/status:/ { print $2 }')
  if [[ "$status" == "running" ]]; then
    warn "Stopping running VMID ${TEMPLATE_VMID} before destroy"
    qm shutdown "$TEMPLATE_VMID" --timeout 60 || qm stop "$TEMPLATE_VMID"
  fi

  qm destroy "$TEMPLATE_VMID" --purge
}

download_image() {
  mkdir -p "$IMAGE_CACHE_DIR"

  if [[ -f "$IMAGE_PATH" ]]; then
    ok "Reusing cached image ${IMAGE_PATH}"
  else
    info "Downloading ${IMAGE_URL}"
    if command_exists curl; then
      curl -fL "$IMAGE_URL" -o "${IMAGE_PATH}.tmp"
    elif command_exists wget; then
      wget -O "${IMAGE_PATH}.tmp" "$IMAGE_URL"
    else
      die "Neither curl nor wget is available for image download"
    fi
    mv "${IMAGE_PATH}.tmp" "$IMAGE_PATH"
  fi

  if [[ -n "${IMAGE_SHA256:-}" ]]; then
    command_exists sha256sum || die "IMAGE_SHA256 is set, but sha256sum is unavailable"
    printf '%s  %s\n' "$IMAGE_SHA256" "$IMAGE_PATH" | sha256sum -c - >/dev/null
    ok "Image checksum verified"
  fi
}

attach_imported_disk() {
  local imported_disk

  imported_disk=$(qm config "$TEMPLATE_VMID" | awk '/^unused[0-9]+:/ { sub(/^[^:]+: /, ""); print; exit }')
  if [[ -z "$imported_disk" ]]; then
    die "Could not find imported unused disk in qm config for VMID ${TEMPLATE_VMID}"
  fi

  info "Attaching imported disk ${imported_disk} as ${DISK_BUS}0"
  qm set "$TEMPLATE_VMID" --"${DISK_BUS}0" "$imported_disk"
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

IMAGE_CACHE_DIR="${ROOT_DIR}/.cache/images"
IMAGE_PATH="${IMAGE_CACHE_DIR}/${IMAGE_NAME}"

info "Checking Proxmox environment"
[[ -d /etc/pve ]] || die "This script must run on a Proxmox node; /etc/pve is missing"
command_exists qm || die "Required command not found: qm"
command_exists pvesm || die "Required command not found: pvesm"
command_exists ip || die "Required command not found: ip"
command_exists curl || command_exists wget || die "Required command not found: curl or wget"
pvesm status >/dev/null || die "pvesm status failed; check Proxmox storage subsystem"

info "Checking Proxmox storage"
storage_exists "$DISK_STORAGE" || die "Storage ${DISK_STORAGE} does not exist; check pvesm status"
storage_exists "$CLOUDINIT_STORAGE" || die "Storage ${CLOUDINIT_STORAGE} does not exist; check pvesm status"

info "Checking network bridge ${BRIDGE}"
ip link show "$BRIDGE" >/dev/null 2>&1 || die "Bridge ${BRIDGE} does not exist; check ip link show type bridge"

if vm_exists; then
  if [[ "$FORCE_RECREATE" == "true" ]]; then
    destroy_existing_vm
  else
    die "VMID ${TEMPLATE_VMID} already exists. Use a different TEMPLATE_VMID or set FORCE_RECREATE=true after verifying it is safe."
  fi
fi

download_image

info "Creating VM shell ${TEMPLATE_VMID} (${TEMPLATE_NAME})"
qm create "$TEMPLATE_VMID" \
  --name "$TEMPLATE_NAME" \
  --memory "$MEMORY_MB" \
  --cores "$CPU_CORES" \
  --net0 "virtio,bridge=${BRIDGE}" \
  --ostype l26 \
  --scsihw "$SCSI_CONTROLLER" \
  --machine "$MACHINE_TYPE" \
  --bios "$BIOS_TYPE"

info "Importing cloud image disk"
qm importdisk "$TEMPLATE_VMID" "$IMAGE_PATH" "$DISK_STORAGE"
attach_imported_disk

info "Attaching cloud-init drive"
qm set "$TEMPLATE_VMID" --ide2 "${CLOUDINIT_STORAGE}:cloudinit"

info "Applying hardware and cloud-init defaults"
qm set "$TEMPLATE_VMID" --boot order="${DISK_BUS}0"
qm set "$TEMPLATE_VMID" --serial0 socket --vga serial0
qm set "$TEMPLATE_VMID" --ciuser "$CLOUDINIT_USER"

if [[ "$ENABLE_QEMU_AGENT" == "true" ]]; then
  qm set "$TEMPLATE_VMID" --agent enabled=1
fi

info "Converting VM to template"
qm template "$TEMPLATE_VMID"

ok "Template created successfully"
printf '\n'
printf 'Name: %s\n' "$TEMPLATE_NAME"
printf 'VMID: %s\n' "$TEMPLATE_VMID"
printf 'Storage: %s\n' "$DISK_STORAGE"
printf 'Bridge: %s\n' "$BRIDGE"
