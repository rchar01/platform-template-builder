#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

script_dir() {
  local source_dir
  source_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  printf '%s\n' "$source_dir"
}

usage() {
  printf 'Usage: %s <config.env>\n' "${0##*/}" >&2
}

is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_bool() {
  [[ "$1" == "true" || "$1" == "false" ]]
}

require_var() {
  local name=$1
  if [[ -z "${!name:-}" ]]; then
    die "Required config variable ${name} is missing or empty"
  fi
}

require_one_of() {
  local name=$1
  local value=$2
  shift 2

  local allowed
  for allowed in "$@"; do
    if [[ "$value" == "$allowed" ]]; then
      return 0
    fi
  done

  die "${name} must be one of: $*"
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

if [[ ! -f "$CONFIG_FILE" ]]; then
  die "Config file not found: ${CONFIG_FILE}"
fi

info "Validating config ${CONFIG_FILE}"

set -a
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

require_var IMAGE_PROFILE
PROFILE_FILE=$(resolve_profile_file "$IMAGE_PROFILE" "$ROOT_DIR") || die "Image profile not found: ${IMAGE_PROFILE}"

set -a
# shellcheck source=/dev/null
. "$PROFILE_FILE"
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

required_vars=(
  TEMPLATE_NAME
  TEMPLATE_VMID
  IMAGE_PROFILE
  IMAGE_URL
  IMAGE_NAME
  IMAGE_OS_FAMILY
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
  require_var "$name"
done

is_number "$TEMPLATE_VMID" || die "TEMPLATE_VMID must be numeric"
is_number "$CPU_CORES" || die "CPU_CORES must be numeric"
is_number "$MEMORY_MB" || die "MEMORY_MB must be numeric"

(( CPU_CORES >= 1 )) || die "CPU_CORES must be >= 1"
(( MEMORY_MB >= 512 )) || die "MEMORY_MB must be >= 512"

is_bool "$ENABLE_QEMU_AGENT" || die "ENABLE_QEMU_AGENT must be true or false"
is_bool "$FORCE_RECREATE" || die "FORCE_RECREATE must be true or false"
if [[ -n "${PREPARE_GUEST_IMAGE:-}" ]]; then
  is_bool "$PREPARE_GUEST_IMAGE" || die "PREPARE_GUEST_IMAGE must be true or false"
fi
if [[ -n "${GUEST_PREP_TIMEOUT_SECONDS:-}" ]]; then
  is_number "$GUEST_PREP_TIMEOUT_SECONDS" || die "GUEST_PREP_TIMEOUT_SECONDS must be numeric"
  (( GUEST_PREP_TIMEOUT_SECONDS > 0 )) || die "GUEST_PREP_TIMEOUT_SECONDS must be greater than 0"
fi

require_one_of BIOS_TYPE "$BIOS_TYPE" seabios ovmf
require_one_of DISK_BUS "$DISK_BUS" scsi
require_one_of IMAGE_OS_FAMILY "$IMAGE_OS_FAMILY" debian rhel

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
printf '\n'
printf 'Image:\n'
printf '  Profile: %s\n' "$IMAGE_PROFILE"
printf '  OS family: %s\n' "$IMAGE_OS_FAMILY"
printf '  URL: %s\n' "$IMAGE_URL"
printf '  File: %s\n' "$IMAGE_NAME"
