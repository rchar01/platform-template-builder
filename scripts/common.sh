#!/usr/bin/env bash

ptb_die() {
  if declare -F die >/dev/null 2>&1; then
    die "$@"
  fi

  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

ptb_script_dir() {
  local source_path=${1:-${BASH_SOURCE[1]}}
  local source_dir

  source_dir=$(CDPATH='' cd -- "$(dirname -- "$source_path")" && pwd)
  printf '%s\n' "$source_dir"
}

ptb_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ptb_is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

ptb_is_bool() {
  [[ "$1" == "true" || "$1" == "false" ]]
}

ptb_is_sha256() {
  [[ "$1" =~ ^[A-Fa-f0-9]{64}$ ]]
}

ptb_is_sha512() {
  [[ "$1" =~ ^[A-Fa-f0-9]{128}$ ]]
}

ptb_is_safe_remote_dir() {
  [[ "$1" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
  case $1 in
    *'//'* | *'/./'* | *'/../'* | *'/.' | *'/..') return 1 ;;
    *) return 0 ;;
  esac
}

ptb_is_safe_file_name() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

ptb_shell_quote() {
  printf "'%s'" "${1//\'/\'\"\'\"\'}"
}

ptb_require_var() {
  local name=$1
  if [[ -z "${!name:-}" ]]; then
    ptb_die "Required config variable ${name} is missing or empty"
  fi
}

ptb_require_one_of() {
  local name=$1
  local value=$2
  shift 2

  local allowed
  for allowed in "$@"; do
    if [[ "$value" == "$allowed" ]]; then
      return 0
    fi
  done

  ptb_die "${name} must be one of: $*"
}

ptb_resolve_profile_file() {
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

ptb_load_template_config() {
  local config_file=$1
  local root_dir=$2

  set -a
  # shellcheck source=/dev/null
  . "$config_file"
  set +a

  PROFILE_FILE=$(ptb_resolve_profile_file "$IMAGE_PROFILE" "$root_dir") || ptb_die "Image profile not found: ${IMAGE_PROFILE}"

  set -a
  # shellcheck source=/dev/null
  . "$PROFILE_FILE"
  # shellcheck source=/dev/null
  . "$config_file"
  set +a
}
