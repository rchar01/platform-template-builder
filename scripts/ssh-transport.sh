#!/usr/bin/env bash
# shellcheck disable=SC2034

ssh_transport_expand_path() {
  case $1 in
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${1:2}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

ssh_transport_die() {
  if declare -F die >/dev/null 2>&1; then
    die "$@"
  fi

  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

ssh_transport_cleanup() {
  if [[ -n "${SSH_TRANSPORT_TEMP_CONFIG:-}" && -f "$SSH_TRANSPORT_TEMP_CONFIG" ]]; then
    rm -f -- "$SSH_TRANSPORT_TEMP_CONFIG"
  fi
}

ssh_transport_init() {
  local config_file=${1:-}
  local fallback_host=${2:-}

  [[ -n "$fallback_host" ]] || ssh_transport_die 'Missing fallback SSH host'

  SSH_TRANSPORT_TARGET=$fallback_host
  SSH_TRANSPORT_DISPLAY=$fallback_host
  SSH_TRANSPORT_RSYNC_RSH='ssh'
  SSH_TRANSPORT_SSH_ARGS=()
  SSH_TRANSPORT_CONFIG_SOURCE=''

  if [[ -z "$config_file" || ! -f "$config_file" ]]; then
    return 0
  fi

  set -a
  # shellcheck source=/dev/null
  . "$config_file"
  set +a

  [[ -n "${SSH_HOST:-}" ]] || ssh_transport_die "SSH transport config ${config_file} is missing SSH_HOST"
  [[ -n "${SSH_KEY_PATH:-}" ]] || ssh_transport_die "SSH transport config ${config_file} is missing SSH_KEY_PATH"

  SSH_USER=${SSH_USER:-$(id -un)}
  local key_path
  key_path=$(ssh_transport_expand_path "$SSH_KEY_PATH")
  [[ -f "$key_path" ]] || ssh_transport_die "SSH private key not found: ${key_path}"
  command -v mktemp >/dev/null 2>&1 || ssh_transport_die 'mktemp is required when using an SSH transport config'

  SSH_TRANSPORT_TEMP_CONFIG=$(mktemp "${TMPDIR:-/tmp}/template-builder-ssh.XXXXXX")
  chmod 600 "$SSH_TRANSPORT_TEMP_CONFIG"

  {
    printf 'Host __platform_template_builder_target\n'
    printf '  HostName %s\n' "$SSH_HOST"
    printf '  User %s\n' "$SSH_USER"
    printf '  IdentityFile %s\n' "$key_path"
    printf '  IdentitiesOnly yes\n'
  } >"$SSH_TRANSPORT_TEMP_CONFIG"

  SSH_TRANSPORT_TARGET='__platform_template_builder_target'
  SSH_TRANSPORT_DISPLAY="${SSH_USER}@${SSH_HOST}"
  SSH_TRANSPORT_RSYNC_RSH="ssh -F ${SSH_TRANSPORT_TEMP_CONFIG}"
  SSH_TRANSPORT_SSH_ARGS=(-F "$SSH_TRANSPORT_TEMP_CONFIG")
  SSH_TRANSPORT_CONFIG_SOURCE=$config_file

  trap ssh_transport_cleanup EXIT
}

ssh_transport_ssh() {
  # shellcheck disable=SC2029
  ssh "${SSH_TRANSPORT_SSH_ARGS[@]}" "$SSH_TRANSPORT_TARGET" "$@"
}
