#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ptb-profile-validation.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  local expected=$1
  shift
  local output

  if output=$("$@" 2>&1); then
    fail "command unexpectedly succeeded: $*"
  fi
  [[ "$output" == *"$expected"* ]] ||
    fail "expected failure containing '$expected', got: $output"
}

"$ROOT_DIR/scripts/validate-config.sh" \
  "$ROOT_DIR/configs/rocky-10.1-cloud-base.env.example" >/dev/null

cp "$ROOT_DIR/configs/rocky-10.1-cloud-base.env.example" "$TMP_DIR/override.env"
printf '%s\n' 'IMAGE_EXPECTED_VERSION_ID="10.2"' >>"$TMP_DIR/override.env"
expect_failure \
  'Template config must not set image profile variable IMAGE_EXPECTED_VERSION_ID' \
  "$ROOT_DIR/scripts/validate-config.sh" "$TMP_DIR/override.env"

cp "$ROOT_DIR/configs/images/rocky-10.1.env" "$TMP_DIR/incomplete-profile.env"
sed -i '/^IMAGE_DNF_APPSTREAM_URL=/d' "$TMP_DIR/incomplete-profile.env"
sed "s|^IMAGE_PROFILE=.*|IMAGE_PROFILE=\"$TMP_DIR/incomplete-profile.env\"|" \
  "$ROOT_DIR/configs/rocky-10.1-cloud-base.env.example" >"$TMP_DIR/incomplete.env"
expect_failure \
  'Set IMAGE_DNF_RELEASEVER, IMAGE_DNF_BASEOS_URL, IMAGE_DNF_APPSTREAM_URL, and IMAGE_DNF_GPGKEY together' \
  "$ROOT_DIR/scripts/validate-config.sh" "$TMP_DIR/incomplete.env"

cp "$ROOT_DIR/configs/images/rocky-10.1.env" "$TMP_DIR/mismatch-profile.env"
sed -i 's/^IMAGE_DNF_RELEASEVER=.*/IMAGE_DNF_RELEASEVER="10.2"/' \
  "$TMP_DIR/mismatch-profile.env"
sed "s|^IMAGE_PROFILE=.*|IMAGE_PROFILE=\"$TMP_DIR/mismatch-profile.env\"|" \
  "$ROOT_DIR/configs/rocky-10.1-cloud-base.env.example" >"$TMP_DIR/mismatch.env"
expect_failure \
  'IMAGE_DNF_RELEASEVER must match IMAGE_EXPECTED_VERSION_ID' \
  "$ROOT_DIR/scripts/validate-config.sh" "$TMP_DIR/mismatch.env"

cp "$ROOT_DIR/configs/rocky-10.1-cloud-base.env.example" "$TMP_DIR/safe.env"
sed -i 's/^GUEST_PREP_MODE=.*/GUEST_PREP_MODE="safe"/' "$TMP_DIR/safe.env"
expect_failure \
  'IMAGE_EXPECTED_VERSION_ID requires GUEST_PREP_MODE=full' \
  "$ROOT_DIR/scripts/validate-config.sh" "$TMP_DIR/safe.env"

cp "$ROOT_DIR/configs/rocky-10.1-cloud-base.env.example" "$TMP_DIR/disabled.env"
sed -i 's/^PREPARE_GUEST_IMAGE=.*/PREPARE_GUEST_IMAGE="false"/' "$TMP_DIR/disabled.env"
expect_failure \
  'IMAGE_EXPECTED_VERSION_ID requires PREPARE_GUEST_IMAGE=true' \
  "$ROOT_DIR/scripts/validate-config.sh" "$TMP_DIR/disabled.env"

IMAGE_EXPECTED_VERSION_ID=10.2 \
IMAGE_DNF_RELEASEVER=10.2 \
IMAGE_DNF_BASEOS_URL=https://example.invalid/baseos/ \
IMAGE_DNF_APPSTREAM_URL=https://example.invalid/appstream/ \
IMAGE_DNF_GPGKEY=file:///example/key \
bash -c '
  set -euo pipefail
  . "$1/scripts/common.sh"
  ptb_load_template_config "$1/configs/rocky-9-cloud-base.env.example" "$1"
  test -z "${IMAGE_EXPECTED_VERSION_ID:-}"
  test -z "${IMAGE_DNF_RELEASEVER:-}"
  test -z "${IMAGE_DNF_BASEOS_URL:-}"
  test -z "${IMAGE_DNF_APPSTREAM_URL:-}"
  test -z "${IMAGE_DNF_GPGKEY:-}"
' _ "$ROOT_DIR"

printf '[OK] Image profile version validation\n'
