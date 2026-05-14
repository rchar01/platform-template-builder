#!/usr/bin/env bash
set -euo pipefail

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'USAGE'
Usage: init-proxmox-ssh.sh <ssh-config.env> [options]

This is a repository wrapper for the shared platform-tools command
`platform-ssh-init`. The helper is optional; template builds only require that
SSH access already works for the configured PROXMOX_HOST.

Install platform-tools or set PLATFORM_SSH_INIT to the tool path, for example:

  PLATFORM_SSH_INIT=../platform-tools/bin/platform-ssh-init make init-ssh

If you do not use platform-tools, generate the key manually and ensure the
private template config points to a working SSH alias or user@host.
USAGE
}

resolve_platform_ssh_init() {
  local tool=${PLATFORM_SSH_INIT:-platform-ssh-init}

  case $tool in
    */*)
      [[ -x "$tool" ]] || return 1
      printf '%s\n' "$tool"
      ;;
    *)
      command -v "$tool" 2>/dev/null || return 1
      ;;
  esac
}

if [[ ${1:-} == '-h' || ${1:-} == '--help' ]]; then
  usage
  exit 0
fi

PLATFORM_SSH_INIT_BIN=$(resolve_platform_ssh_init) || die "Missing platform-ssh-init. Install platform-tools, set PLATFORM_SSH_INIT=/path/to/platform-ssh-init, or generate SSH keys manually so PROXMOX_HOST works with ssh."

exec "$PLATFORM_SSH_INIT_BIN" "$@"
