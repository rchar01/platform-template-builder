#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }
die() { error "$*"; exit 1; }

usage() {
  printf 'Usage: %s [image-profile.env ...]\n' "${0##*/}" >&2
}

check_profile_url() (
  local profile_file=$1
  local url

  unset IMAGE_URL IMAGE_NAME IMAGE_SHA256 IMAGE_SHA512
  unset IMAGE_DNF_BASEOS_URL IMAGE_DNF_APPSTREAM_URL IMAGE_DNF_GPGKEY
  set -a
  # shellcheck source=/dev/null
  . "$profile_file"
  set +a

  [[ -n "${IMAGE_URL:-}" ]] || die "IMAGE_URL is missing or empty in ${profile_file}"
  [[ -n "${IMAGE_NAME:-}" ]] || die "IMAGE_NAME is missing or empty in ${profile_file}"

  info "Checking ${IMAGE_NAME}"
  if [[ "$DOWNLOAD_TOOL" == "curl" ]]; then
    curl -fsSIL --connect-timeout 10 --max-time 30 "$IMAGE_URL" -o /dev/null
  else
    wget --spider -q --timeout=30 --tries=1 "$IMAGE_URL"
  fi
  ok "Image URL available: ${IMAGE_URL}"

  for url in "${IMAGE_DNF_BASEOS_URL:-}" "${IMAGE_DNF_APPSTREAM_URL:-}"; do
    [[ -n "$url" ]] || continue
    info "Checking pinned package repository ${url}"
    if [[ "$DOWNLOAD_TOOL" == "curl" ]]; then
      curl -fsSIL --connect-timeout 10 --max-time 30 "${url}repodata/repomd.xml" -o /dev/null
    else
      wget --spider -q --timeout=30 --tries=1 "${url}repodata/repomd.xml"
    fi
    ok "Pinned package repository available: ${url}"
  done
)

if [[ $# -gt 0 && "$1" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)

if command -v curl >/dev/null 2>&1; then
  DOWNLOAD_TOOL=curl
elif command -v wget >/dev/null 2>&1; then
  DOWNLOAD_TOOL=wget
else
  die "curl or wget is required to check image URLs"
fi
export DOWNLOAD_TOOL

if [[ $# -eq 0 ]]; then
  profiles=("${ROOT_DIR}"/configs/images/*.env)
else
  profiles=("$@")
fi

failed=0
for profile_file in "${profiles[@]}"; do
  if [[ ! -f "$profile_file" ]]; then
    error "Image profile not found: ${profile_file}"
    failed=1
    continue
  fi

  if ! check_profile_url "$profile_file"; then
    error "Image URL unavailable for profile: ${profile_file}"
    failed=1
  fi
done

(( failed == 0 )) || die "One or more image URL checks failed"
ok "Image URL checks complete"
