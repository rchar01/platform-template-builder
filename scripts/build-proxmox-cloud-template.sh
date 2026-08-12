#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  printf 'Usage: %s <config.env>\n' "${0##*/}" >&2
}

require_guest_prep_command() {
  local command_name=$1
  local package_name=$2

  ptb_command_exists "$command_name" || die "${command_name} not found; install ${package_name} on the template build host."
}

storage_exists() {
  local storage=$1
  pvesm status | awk 'NR > 1 { print $1 }' | grep -Fxq "$storage"
}

vm_exists() {
  qm status "$TEMPLATE_VMID" >/dev/null 2>&1
}

destroy_existing_vm() {
  warn "FORCE_RECREATE=true; destroying existing VMID ${TEMPLATE_VMID} (${TEMPLATE_NAME})"
  qm config "$TEMPLATE_VMID"
  proxmox_vm_destroy "$TEMPLATE_VMID"
}

download_image() {
  local checksum_tool
  local checksum_value

  mkdir -p "$IMAGE_CACHE_DIR"

  if [[ -f "$IMAGE_PATH" ]]; then
    ok "Reusing cached image ${IMAGE_PATH}"
  else
    info "Downloading ${IMAGE_URL}"
    if ptb_command_exists curl; then
      curl -fL "$IMAGE_URL" -o "${IMAGE_PATH}.tmp"
    elif ptb_command_exists wget; then
      wget -O "${IMAGE_PATH}.tmp" "$IMAGE_URL"
    else
      die "Neither curl nor wget is available for image download"
    fi
    mv "${IMAGE_PATH}.tmp" "$IMAGE_PATH"
  fi

  if [[ -n "${IMAGE_SHA256:-}" ]]; then
    checksum_tool=sha256sum
    checksum_value=$IMAGE_SHA256
  elif [[ -n "${IMAGE_SHA512:-}" ]]; then
    checksum_tool=sha512sum
    checksum_value=$IMAGE_SHA512
  else
    die "Set IMAGE_SHA256 or IMAGE_SHA512 before importing cloud images"
  fi

  ptb_command_exists "$checksum_tool" || die "${checksum_tool} is required for image checksum verification"
  printf '%s  %s\n' "$checksum_value" "$IMAGE_PATH" | "$checksum_tool" -c - >/dev/null
  ok "Image checksum verified with ${checksum_tool}"
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

apply_console_defaults() {
  case $TEMPLATE_CONSOLE_MODE in
    serial)
      qm set "$TEMPLATE_VMID" --serial0 socket --vga serial0
      ;;
    vga-serial)
      qm set "$TEMPLATE_VMID" --serial0 socket --vga std
      ;;
    *)
      die "TEMPLATE_CONSOLE_MODE must be one of: serial vga-serial"
      ;;
  esac
}

guest_prep_packages() {
  case ${IMAGE_OS_FAMILY:-} in
    debian)
      printf '%s\n' 'cloud-init,qemu-guest-agent,openssh-server,network-manager'
      ;;
    rhel)
      printf '%s\n' 'cloud-init,qemu-guest-agent,openssh-server,NetworkManager'
      ;;
    *)
      die "IMAGE_OS_FAMILY must be one of: debian rhel"
      ;;
  esac
}

guest_ssh_service() {
  case ${IMAGE_OS_FAMILY:-} in
    debian) printf '%s\n' 'ssh.service' ;;
    rhel) printf '%s\n' 'sshd.service' ;;
    *) die "IMAGE_OS_FAMILY must be one of: debian rhel" ;;
  esac
}

guest_console_command() {
  case $TEMPLATE_CONSOLE_MODE in
    serial)
      printf '%s\n' "if command -v grubby >/dev/null 2>&1; then grubby --update-kernel=ALL --remove-args='console=tty0 console=ttyS0 console=ttyS0,115200n8' || true; grubby --update-kernel=ALL --args='console=ttyS0,115200n8'; fi"
      ;;
    vga-serial)
      printf '%s\n' "if command -v grubby >/dev/null 2>&1; then grubby --update-kernel=ALL --remove-args='console=tty0 console=ttyS0 console=ttyS0,115200n8' || true; grubby --update-kernel=ALL --args='console=tty0 console=ttyS0,115200n8'; fi"
      ;;
    *)
      die "TEMPLATE_CONSOLE_MODE must be one of: serial vga-serial"
      ;;
  esac
}

prepare_guest_image() {
  local -a finalization_commands
  local packages
  local console_command
  local package_install_command
  local releasever_assertion
  local ssh_service
  local version_assertion

  PREPARED_IMAGE_PATH="${IMAGE_CACHE_DIR}/${TEMPLATE_NAME}-prepared.qcow2"

  info "Preparing guest image ${PREPARED_IMAGE_PATH}"
  rm -f -- "${PREPARED_IMAGE_PATH}" "${PREPARED_IMAGE_PATH}.tmp"
  timeout --kill-after=10s "$GUEST_PREP_TIMEOUT_SECONDS" qemu-img convert -O qcow2 "$IMAGE_PATH" "${PREPARED_IMAGE_PATH}.tmp" || die "qemu-img failed while preparing ${PREPARED_IMAGE_PATH}"
  mv "${PREPARED_IMAGE_PATH}.tmp" "$PREPARED_IMAGE_PATH"

  if [[ "$GUEST_PREP_MODE" == "safe" ]]; then
    info "Using safe guest preparation; copied upstream image without guest modifications"
    return 0
  fi

  console_command=$(guest_console_command)
  packages=$(guest_prep_packages)
  ssh_service=$(guest_ssh_service)

  if [[ -n "${IMAGE_EXPECTED_VERSION_ID:-}" ]]; then
    version_assertion=$(ptb_guest_version_assertion "$IMAGE_EXPECTED_VERSION_ID")
    info "Verifying source guest VERSION_ID=${IMAGE_EXPECTED_VERSION_ID}"
    timeout --kill-after=10s "$GUEST_PREP_TIMEOUT_SECONDS" virt-customize -a "$PREPARED_IMAGE_PATH" \
      --run-command "$version_assertion" || die "Source guest VERSION_ID does not match ${IMAGE_EXPECTED_VERSION_ID}"
  fi

  info "Installing guest packages: ${packages}"
  if [[ -n "${IMAGE_DNF_RELEASEVER:-}" ]]; then
    package_install_command=$(ptb_rhel_package_install_command "$packages")
    timeout --kill-after=10s "$GUEST_PREP_TIMEOUT_SECONDS" virt-customize -a "$PREPARED_IMAGE_PATH" \
      --run-command "$package_install_command" || die "virt-customize failed while installing guest packages from pinned repositories in ${PREPARED_IMAGE_PATH}"
  else
    timeout --kill-after=10s "$GUEST_PREP_TIMEOUT_SECONDS" virt-customize -a "$PREPARED_IMAGE_PATH" \
      --install "$packages" || die "virt-customize failed while installing guest packages in ${PREPARED_IMAGE_PATH}"
  fi

  info "Configuring cloud-init, guest services, and serial console"
  timeout --kill-after=10s "$GUEST_PREP_TIMEOUT_SECONDS" virt-customize -a "$PREPARED_IMAGE_PATH" \
    --run-command "mkdir -p /etc/cloud/cloud.cfg.d" \
    --run-command "rm -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg" \
    --run-command "printf '%s\n' 'datasource_list: [ NoCloud, ConfigDrive ]' > /etc/cloud/cloud.cfg.d/90-proxmox-datasource.cfg" \
    --run-command "systemctl enable cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service qemu-guest-agent.service ${ssh_service} NetworkManager.service serial-getty@ttyS0.service" \
    --run-command "$console_command" || die "virt-customize failed while configuring guest services in ${PREPARED_IMAGE_PATH}"

  info "Cleaning guest network state and clone identity"
  timeout --kill-after=10s "$GUEST_PREP_TIMEOUT_SECONDS" virt-customize -a "$PREPARED_IMAGE_PATH" \
    --run-command "rm -f /etc/NetworkManager/system-connections/*" \
    --run-command "if [ -d /etc/sysconfig/network-scripts ]; then find /etc/sysconfig/network-scripts -type f -name 'ifcfg-*' ! -name 'ifcfg-lo' -delete; fi" \
    --run-command "rm -rf /var/lib/cloud/*" \
    --run-command "rm -f /var/log/cloud-init.log /var/log/cloud-init-output.log" \
    --run-command "rm -f /etc/ssh/ssh_host_*" || die "virt-customize failed while cleaning guest state in ${PREPARED_IMAGE_PATH}"

  timeout --kill-after=10s "$GUEST_PREP_TIMEOUT_SECONDS" virt-sysprep -a "$PREPARED_IMAGE_PATH" \
    --operations ssh-hostkeys,logfiles,tmp-files,bash-history || die "virt-sysprep failed while cleaning ${PREPARED_IMAGE_PATH}"

  info "Finalizing guest identity and boot sanity checks"
  finalization_commands=(
    --run-command "test -e /etc/os-release"
    --run-command "test -x /sbin/init"
    --run-command ": > /etc/machine-id"
    --run-command "if [ -d /var/lib/dbus ]; then rm -f /var/lib/dbus/machine-id && ln -s /etc/machine-id /var/lib/dbus/machine-id; fi"
    --run-command "rm -rf /var/lib/cloud/*"
  )
  if [[ -n "${IMAGE_EXPECTED_VERSION_ID:-}" ]]; then
    finalization_commands+=(--run-command "$version_assertion")
  fi
  if [[ -n "${IMAGE_DNF_RELEASEVER:-}" ]]; then
    releasever_assertion=$(ptb_guest_dnf_releasever_assertion "$IMAGE_DNF_RELEASEVER")
    finalization_commands+=(--run-command "$releasever_assertion")
  fi
  timeout --kill-after=10s "$GUEST_PREP_TIMEOUT_SECONDS" virt-customize -a "$PREPARED_IMAGE_PATH" \
    "${finalization_commands[@]}" || die "virt-customize failed while finalizing guest identity or validating the exact-version contract in ${PREPARED_IMAGE_PATH}"

  if [[ "$IMAGE_OS_FAMILY" == "rhel" ]]; then
    info "Relabeling SELinux contexts"
    timeout --kill-after=10s "$GUEST_PREP_TIMEOUT_SECONDS" virt-customize -a "$PREPARED_IMAGE_PATH" --selinux-relabel || die "virt-customize failed while relabeling SELinux contexts in ${PREPARED_IMAGE_PATH}"
  fi
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
# shellcheck source=scripts/proxmox-vm-destroy.sh
. "${SCRIPT_DIR}/proxmox-vm-destroy.sh"

"${SCRIPT_DIR}/validate-config.sh" "$CONFIG_FILE"
ptb_load_template_config "$CONFIG_FILE" "$ROOT_DIR"

IMAGE_CACHE_DIR="${ROOT_DIR}/.cache/images"
IMAGE_PATH="${IMAGE_CACHE_DIR}/${IMAGE_NAME}"
PREPARE_GUEST_IMAGE=${PREPARE_GUEST_IMAGE:-true}
GUEST_PREP_MODE=${GUEST_PREP_MODE:-full}
GUEST_PREP_TIMEOUT_SECONDS=${GUEST_PREP_TIMEOUT_SECONDS:-1800}
TEMPLATE_CONSOLE_MODE=${TEMPLATE_CONSOLE_MODE:-vga-serial}
IMPORT_IMAGE_PATH=$IMAGE_PATH
REPLACE_EXISTING_VM=false

info "Checking Proxmox environment"
[[ -d /etc/pve ]] || die "This script must run on a Proxmox node; /etc/pve is missing"
ptb_command_exists qm || die "Required command not found: qm"
ptb_command_exists pvesm || die "Required command not found: pvesm"
ptb_command_exists ip || die "Required command not found: ip"
ptb_command_exists curl || ptb_command_exists wget || die "Required command not found: curl or wget"
pvesm status >/dev/null || die "pvesm status failed; check Proxmox storage subsystem"

if [[ "$PREPARE_GUEST_IMAGE" == "true" ]]; then
  case $GUEST_PREP_MODE in
    safe | full) ;;
    *) die "GUEST_PREP_MODE must be one of: safe full" ;;
  esac
  ptb_is_number "$GUEST_PREP_TIMEOUT_SECONDS" || die "GUEST_PREP_TIMEOUT_SECONDS must be numeric"
  (( GUEST_PREP_TIMEOUT_SECONDS > 0 )) || die "GUEST_PREP_TIMEOUT_SECONDS must be greater than 0"
  require_guest_prep_command timeout coreutils
  require_guest_prep_command qemu-img qemu-utils
  if [[ "$GUEST_PREP_MODE" == "full" ]]; then
    require_guest_prep_command virt-customize libguestfs-tools
    require_guest_prep_command virt-sysprep libguestfs-tools
  fi
elif [[ "$PREPARE_GUEST_IMAGE" != "false" ]]; then
  die "PREPARE_GUEST_IMAGE must be true or false"
fi

case $TEMPLATE_CONSOLE_MODE in
  serial | vga-serial) ;;
  *) die "TEMPLATE_CONSOLE_MODE must be one of: serial vga-serial" ;;
esac

info "Checking Proxmox storage"
storage_exists "$DISK_STORAGE" || die "Storage ${DISK_STORAGE} does not exist; check pvesm status"
storage_exists "$CLOUDINIT_STORAGE" || die "Storage ${CLOUDINIT_STORAGE} does not exist; check pvesm status"

info "Checking network bridge ${BRIDGE}"
ip link show "$BRIDGE" >/dev/null 2>&1 || die "Bridge ${BRIDGE} does not exist; check ip link show type bridge"

if vm_exists; then
  if [[ "$FORCE_RECREATE" == "true" ]]; then
    REPLACE_EXISTING_VM=true
  else
    die "VMID ${TEMPLATE_VMID} already exists. Use a different TEMPLATE_VMID or set FORCE_RECREATE=true after verifying it is safe."
  fi
fi

download_image

if [[ "$PREPARE_GUEST_IMAGE" == "true" ]]; then
  prepare_guest_image
  IMPORT_IMAGE_PATH=$PREPARED_IMAGE_PATH
fi

if [[ "$REPLACE_EXISTING_VM" == "true" ]]; then
  destroy_existing_vm
fi

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
qm importdisk "$TEMPLATE_VMID" "$IMPORT_IMAGE_PATH" "$DISK_STORAGE"
attach_imported_disk

info "Attaching cloud-init drive"
qm set "$TEMPLATE_VMID" --ide2 "${CLOUDINIT_STORAGE}:cloudinit"

info "Applying hardware and cloud-init defaults"
qm set "$TEMPLATE_VMID" --boot order="${DISK_BUS}0"
if [[ -n "${CPU_TYPE:-}" ]]; then
  qm set "$TEMPLATE_VMID" --cpu "$CPU_TYPE"
fi
apply_console_defaults
qm set "$TEMPLATE_VMID" --citype nocloud
qm set "$TEMPLATE_VMID" --ciupgrade 0
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
