#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'USAGE'
Usage: init-proxmox-ssh.sh <ssh-config.env> [options]

Options:
  --empty-passphrase      Create a key without prompting for a passphrase.
  --write-config          Append the SSH Host block to ~/.ssh/config.
  --test                  Test SSH access and required Proxmox commands after setup.
  -h, --help              Show this help.

The config file may define SSH_HOST, SSH_USER, SSH_ALIAS, and SSH_KEY_PATH.
This script creates only local SSH client material. It does not install the
public key on Proxmox and does not create Proxmox users or API tokens.
USAGE
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

expand_path() {
  case $1 in
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${1:2}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

print_ssh_config() {
  printf 'Host %s\n' "$SSH_ALIAS"
  printf '  HostName %s\n' "$PROXMOX_HOST"
  printf '  User %s\n' "$PROXMOX_USER"
  printf '  IdentityFile %s\n' "$KEY_PATH_INPUT"
  printf '  IdentitiesOnly yes\n'
}

host_alias_exists() {
  local config_file=$1
  local alias=$2

  [[ -f "$config_file" ]] || return 1
  awk -v alias="$alias" '
    /^[[:space:]]*Host[[:space:]]+/ {
      for (i = 2; i <= NF; i++) {
        if ($i == alias) {
          found = 1
        }
      }
    }
    END { exit found ? 0 : 1 }
  ' "$config_file"
}

write_ssh_config() {
  local ssh_dir=$1
  local config_file=$2

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  touch "$config_file"
  chmod 600 "$config_file"

  if host_alias_exists "$config_file" "$SSH_ALIAS"; then
    die "SSH config already contains Host ${SSH_ALIAS}; edit ${config_file} manually or choose another --alias"
  fi

  {
    printf '\n'
    print_ssh_config
  } >>"$config_file"

  ok "Wrote SSH config alias ${SSH_ALIAS} to ${config_file}"
}

test_connection() {
  info "Testing SSH access to ${SSH_ALIAS}"
  ssh "$SSH_ALIAS" 'hostname; test -d /etc/pve; command -v qm; command -v pvesm; command -v rsync; command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1'
  ok "SSH access and required remote commands are available"
}

SSH_HOST=''
SSH_USER='root'
SSH_ALIAS='pve-template-builder'
SSH_KEY_PATH="${HOME}/.ssh/platform-template-builder_ed25519"
WRITE_CONFIG='false'
RUN_TEST='false'
EMPTY_PASSPHRASE='false'
CONFIG_FILE=''

while [[ $# -gt 0 ]]; do
  case $1 in
    --write-config)
      WRITE_CONFIG='true'
      shift
      ;;
    --empty-passphrase)
      EMPTY_PASSPHRASE='true'
      shift
      ;;
    --test)
      RUN_TEST='true'
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      [[ -z "$CONFIG_FILE" ]] || die 'Only one config file may be provided'
      CONFIG_FILE=$1
      shift
      ;;
  esac
done

[[ -n "$CONFIG_FILE" ]] || { usage; exit 2; }
[[ -f "$CONFIG_FILE" ]] || die "Config file not found: ${CONFIG_FILE}"

set -a
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

SSH_USER=${SSH_USER:-root}
SSH_ALIAS=${SSH_ALIAS:-pve-template-builder}
SSH_KEY_PATH=${SSH_KEY_PATH:-"${HOME}/.ssh/platform-template-builder_ed25519"}

[[ -n "$SSH_HOST" ]] || die 'Required config variable SSH_HOST is missing or empty'

command_exists ssh || die 'ssh is required'
command_exists ssh-keygen || die 'ssh-keygen is required'

PROXMOX_HOST=$SSH_HOST
PROXMOX_USER=$SSH_USER
KEY_PATH_INPUT=$SSH_KEY_PATH
KEY_PATH=$(expand_path "$KEY_PATH_INPUT")
KEY_DIR=$(dirname -- "$KEY_PATH")
SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

if [[ -e "$KEY_PATH" ]]; then
  ok "SSH key already exists: ${KEY_PATH}"
else
  info "Creating dedicated ed25519 SSH key: ${KEY_PATH}"
  if [[ "$EMPTY_PASSPHRASE" == 'true' ]]; then
    ssh-keygen -t ed25519 -a 100 -N '' -f "$KEY_PATH" -C "platform-template-builder ${SSH_ALIAS}"
  else
    ssh-keygen -t ed25519 -a 100 -f "$KEY_PATH" -C "platform-template-builder ${SSH_ALIAS}"
  fi
  ok "Created SSH key: ${KEY_PATH}"
fi

printf '\nSSH config block:\n\n'
print_ssh_config

printf '\nInstall the public key on Proxmox if needed:\n\n'
printf 'ssh-copy-id -i %s.pub %s@%s\n' "$KEY_PATH_INPUT" "$PROXMOX_USER" "$PROXMOX_HOST"

if [[ "$WRITE_CONFIG" == 'true' ]]; then
  write_ssh_config "$SSH_DIR" "$SSH_CONFIG"
else
  printf '\nRun again with --write-config to append this Host block to %s.\n' "$SSH_CONFIG"
fi

if [[ "$RUN_TEST" == 'true' ]]; then
  test_connection
else
  printf '\nAfter installing the public key, test access with:\n\n'
  printf 'ssh %s '\''hostname && test -d /etc/pve && command -v qm && command -v pvesm'\''\n' "$SSH_ALIAS"
fi
