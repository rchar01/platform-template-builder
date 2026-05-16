#!/usr/bin/env bash

proxmox_vm_destroy_die() {
  if declare -F die >/dev/null 2>&1; then
    die "$@"
  fi

  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

proxmox_vm_destroy_info() {
  if declare -F info >/dev/null 2>&1; then
    info "$@"
  else
    printf '[INFO] %s\n' "$*"
  fi
}

proxmox_vm_destroy_warn() {
  if declare -F warn >/dev/null 2>&1; then
    warn "$@"
  else
    printf '[WARN] %s\n' "$*"
  fi
}

proxmox_vm_exists() {
  local vmid=$1

  qm status "$vmid" >/dev/null 2>&1
}

proxmox_vm_destroy_supports_unreferenced_disks() {
  qm destroy 2>&1 | grep -q -- '--destroy-unreferenced-disks'
}

proxmox_vm_stop_if_running() {
  local vmid=$1

  if qm status "$vmid" | grep -Eq '^status:[[:space:]]+running$'; then
    proxmox_vm_destroy_warn "Stopping running VMID ${vmid} before destroy"
    qm shutdown "$vmid" --timeout 60 || qm stop "$vmid"
  fi
}

proxmox_vm_destroy() {
  local vmid=$1

  proxmox_vm_exists "$vmid" || proxmox_vm_destroy_die "VMID ${vmid} does not exist"
  proxmox_vm_stop_if_running "$vmid"

  proxmox_vm_destroy_warn "Destroying VMID ${vmid} with purge enabled"
  if proxmox_vm_destroy_supports_unreferenced_disks; then
    qm destroy "$vmid" --purge --destroy-unreferenced-disks 1
  else
    proxmox_vm_destroy_warn "qm destroy does not support --destroy-unreferenced-disks on this Proxmox version; using --purge only"
    qm destroy "$vmid" --purge
  fi
}
