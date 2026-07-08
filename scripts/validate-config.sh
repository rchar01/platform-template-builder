#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  printf 'Usage: %s <config.env>\n' "${0##*/}" >&2
}

reject_profile_variable_in_config() {
  local name=$1
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*= ]]; then
      die "Template config must not set image profile variable ${name}"
    fi
  done <"$CONFIG_FILE"
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

if [[ ! -f "$CONFIG_FILE" ]]; then
  die "Config file not found: ${CONFIG_FILE}"
fi

info "Validating config ${CONFIG_FILE}"

reject_profile_variable_in_config IMAGE_URL
reject_profile_variable_in_config IMAGE_NAME
reject_profile_variable_in_config IMAGE_SHA256
reject_profile_variable_in_config IMAGE_SHA512
reject_profile_variable_in_config IMAGE_OS_FAMILY
reject_profile_variable_in_config IMAGE_EXPECTS_QEMU_AGENT
reject_profile_variable_in_config IMAGE_FILESYSTEM_LAYOUT
reject_profile_variable_in_config CLOUDINIT_USER

set -a
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

ptb_require_var IMAGE_PROFILE
PROFILE_FILE=$(ptb_resolve_profile_file "$IMAGE_PROFILE" "$ROOT_DIR") || die "Image profile not found: ${IMAGE_PROFILE}"

unset IMAGE_URL IMAGE_NAME IMAGE_SHA256 IMAGE_SHA512 IMAGE_OS_FAMILY
unset IMAGE_EXPECTS_QEMU_AGENT IMAGE_FILESYSTEM_LAYOUT CLOUDINIT_USER

set -a
# shellcheck source=/dev/null
. "$PROFILE_FILE"
set +a

required_vars=(
  TEMPLATE_NAME
  TEMPLATE_VMID
  IMAGE_PROFILE
  IMAGE_URL
  IMAGE_NAME
  IMAGE_OS_FAMILY
  IMAGE_EXPECTS_QEMU_AGENT
  IMAGE_FILESYSTEM_LAYOUT
  PROXMOX_HOST
  PROXMOX_REMOTE_DIR
  DISK_STORAGE
  CLOUDINIT_STORAGE
  BRIDGE
  CPU_CORES
  MEMORY_MB
  BIOS_TYPE
  MACHINE_TYPE
  DISK_BUS
  SCSI_CONTROLLER
  CLOUDINIT_USER
  ENABLE_QEMU_AGENT
  FORCE_RECREATE
)

for name in "${required_vars[@]}"; do
  ptb_require_var "$name"
done

ptb_is_number "$TEMPLATE_VMID" || die "TEMPLATE_VMID must be numeric"
ptb_is_number "$CPU_CORES" || die "CPU_CORES must be numeric"
ptb_is_number "$MEMORY_MB" || die "MEMORY_MB must be numeric"

(( CPU_CORES >= 1 )) || die "CPU_CORES must be >= 1"
(( MEMORY_MB >= 512 )) || die "MEMORY_MB must be >= 512"

ptb_is_bool "$ENABLE_QEMU_AGENT" || die "ENABLE_QEMU_AGENT must be true or false"
ptb_is_bool "$IMAGE_EXPECTS_QEMU_AGENT" || die "IMAGE_EXPECTS_QEMU_AGENT must be true or false"
ptb_is_bool "$FORCE_RECREATE" || die "FORCE_RECREATE must be true or false"
ptb_is_safe_remote_dir "$PROXMOX_REMOTE_DIR" || die "PROXMOX_REMOTE_DIR must be an absolute path with safe characters and no dot path segments"
if [[ -n "${PREPARE_GUEST_IMAGE:-}" ]]; then
  ptb_is_bool "$PREPARE_GUEST_IMAGE" || die "PREPARE_GUEST_IMAGE must be true or false"
fi
if [[ -n "${GUEST_PREP_TIMEOUT_SECONDS:-}" ]]; then
  ptb_is_number "$GUEST_PREP_TIMEOUT_SECONDS" || die "GUEST_PREP_TIMEOUT_SECONDS must be numeric"
  (( GUEST_PREP_TIMEOUT_SECONDS > 0 )) || die "GUEST_PREP_TIMEOUT_SECONDS must be greater than 0"
fi
if [[ -n "${TEMPLATE_CONSOLE_MODE:-}" ]]; then
  ptb_require_one_of TEMPLATE_CONSOLE_MODE "$TEMPLATE_CONSOLE_MODE" serial vga-serial
fi
if [[ -n "${GUEST_PREP_MODE:-}" ]]; then
  ptb_require_one_of GUEST_PREP_MODE "$GUEST_PREP_MODE" safe full
fi

ptb_require_one_of BIOS_TYPE "$BIOS_TYPE" seabios ovmf
ptb_require_one_of DISK_BUS "$DISK_BUS" scsi
ptb_require_one_of IMAGE_OS_FAMILY "$IMAGE_OS_FAMILY" debian rhel
ptb_require_one_of IMAGE_FILESYSTEM_LAYOUT "$IMAGE_FILESYSTEM_LAYOUT" unknown plain-ext4 plain-xfs lvm-ext4 lvm-xfs other

effective_prepare_guest_image=${PREPARE_GUEST_IMAGE:-true}
effective_guest_prep_mode=${GUEST_PREP_MODE:-full}
if [[ "$IMAGE_EXPECTS_QEMU_AGENT" == "true" ]]; then
  [[ "$ENABLE_QEMU_AGENT" == "true" ]] || die "IMAGE_EXPECTS_QEMU_AGENT=true requires ENABLE_QEMU_AGENT=true"
  [[ "$effective_prepare_guest_image" == "true" ]] || die "IMAGE_EXPECTS_QEMU_AGENT=true requires PREPARE_GUEST_IMAGE=true"
  [[ "$effective_guest_prep_mode" == "full" ]] || die "IMAGE_EXPECTS_QEMU_AGENT=true requires GUEST_PREP_MODE=full"
fi

checksum_count=0
if [[ -n "${IMAGE_SHA256:-}" ]]; then
  ptb_is_sha256 "$IMAGE_SHA256" || die "IMAGE_SHA256 must be a 64-character hexadecimal sha256 digest"
  checksum_count=$((checksum_count + 1))
fi
if [[ -n "${IMAGE_SHA512:-}" ]]; then
  ptb_is_sha512 "$IMAGE_SHA512" || die "IMAGE_SHA512 must be a 128-character hexadecimal sha512 digest"
  checksum_count=$((checksum_count + 1))
fi
(( checksum_count == 1 )) || die "Set exactly one image checksum: IMAGE_SHA256 or IMAGE_SHA512"

ok "Template config valid"
printf '\n'
printf 'Template:\n'
printf '  Name: %s\n' "$TEMPLATE_NAME"
printf '  VMID: %s\n' "$TEMPLATE_VMID"
printf '\n'
printf 'Proxmox:\n'
printf '  Host: %s\n' "$PROXMOX_HOST"
printf '  Remote dir: %s\n' "$PROXMOX_REMOTE_DIR"
printf '  Disk storage: %s\n' "$DISK_STORAGE"
printf '  Cloud-init storage: %s\n' "$CLOUDINIT_STORAGE"
printf '  Bridge: %s\n' "$BRIDGE"
printf '  CPU type: %s\n' "${CPU_TYPE:-default}"
printf '  Console mode: %s\n' "${TEMPLATE_CONSOLE_MODE:-vga-serial}"
printf '\n'
printf 'Image:\n'
printf '  Profile: %s\n' "$IMAGE_PROFILE"
printf '  OS family: %s\n' "$IMAGE_OS_FAMILY"
printf '  Expects QEMU guest agent: %s\n' "$IMAGE_EXPECTS_QEMU_AGENT"
printf '  Filesystem layout: %s\n' "$IMAGE_FILESYSTEM_LAYOUT"
printf '  URL: %s\n' "$IMAGE_URL"
printf '  File: %s\n' "$IMAGE_NAME"
