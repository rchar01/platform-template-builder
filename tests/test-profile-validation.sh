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

declare -A expected_vmids=(
  [rocky-10.0]=9004
  [rocky-10.1]=9003
  [rocky-10.2]=9005
)
declare -A expected_image_urls=(
  [rocky-10.0]="https://download.rockylinux.org/vault/rocky/10.0/images/x86_64/Rocky-10-GenericCloud-LVM-10.0-20250609.1.x86_64.qcow2"
  [rocky-10.1]="https://download.rockylinux.org/vault/rocky/10.1/images/x86_64/Rocky-10-GenericCloud-LVM-10.1-20251116.0.x86_64.qcow2"
  [rocky-10.2]="https://download.rockylinux.org/pub/rocky/10.2/images/x86_64/Rocky-10-GenericCloud-LVM-10.2-20260525.0.x86_64.qcow2"
)
declare -A expected_repo_roots=(
  [rocky-10.0]="https://dl.rockylinux.org/vault/rocky/10.0"
  [rocky-10.1]="https://dl.rockylinux.org/vault/rocky/10.1"
  [rocky-10.2]="https://dl.rockylinux.org/pub/rocky/10.2"
)

for template in rocky-10.0 rocky-10.1 rocky-10.2; do
  config_file="$ROOT_DIR/configs/${template}-cloud-base.env.example"
  profile_file="$ROOT_DIR/configs/images/${template}.env"

  "$ROOT_DIR/scripts/validate-config.sh" "$config_file" >/dev/null

  (
    set -a
    # shellcheck source=/dev/null
    . "$config_file"
    # shellcheck source=/dev/null
    . "$profile_file"
    set +a

    expected_version=${template#rocky-}
    [[ "$TEMPLATE_NAME" == "${template}-cloud-base" ]] ||
      fail "unexpected template name for ${template}: ${TEMPLATE_NAME}"
    [[ "$TEMPLATE_VMID" == "${expected_vmids[$template]}" ]] ||
      fail "unexpected VMID for ${template}: ${TEMPLATE_VMID}"
    [[ "$IMAGE_PROFILE" == "configs/images/${template}.env" ]] ||
      fail "unexpected image profile for ${template}: ${IMAGE_PROFILE}"
    [[ "$IMAGE_EXPECTED_VERSION_ID" == "$expected_version" ]] ||
      fail "unexpected VERSION_ID for ${template}: ${IMAGE_EXPECTED_VERSION_ID}"
    [[ "$IMAGE_DNF_RELEASEVER" == "$expected_version" ]] ||
      fail "unexpected DNF releasever for ${template}: ${IMAGE_DNF_RELEASEVER}"
    [[ "$IMAGE_URL" == "${expected_image_urls[$template]}" ]] ||
      fail "unexpected image URL for ${template}: ${IMAGE_URL}"
    [[ "$IMAGE_DNF_BASEOS_URL" == "${expected_repo_roots[$template]}/BaseOS/x86_64/os/" ]] ||
      fail "unexpected BaseOS URL for ${template}: ${IMAGE_DNF_BASEOS_URL}"
    [[ "$IMAGE_DNF_APPSTREAM_URL" == "${expected_repo_roots[$template]}/AppStream/x86_64/os/" ]] ||
      fail "unexpected AppStream URL for ${template}: ${IMAGE_DNF_APPSTREAM_URL}"
    [[ "$IMAGE_DNF_GPGKEY" == file:///* ]] ||
      fail "missing guest GPG key for ${template}"
    [[ "$IMAGE_OS_FAMILY" == rhel ]] ||
      fail "unexpected OS family for ${template}: ${IMAGE_OS_FAMILY}"
    [[ "$IMAGE_EXPECTS_QEMU_AGENT" == true ]] ||
      fail "QEMU guest agent must be expected for ${template}"
    [[ "$IMAGE_FILESYSTEM_LAYOUT" == lvm-xfs ]] ||
      fail "unexpected filesystem layout for ${template}: ${IMAGE_FILESYSTEM_LAYOUT}"
    [[ "$CLOUDINIT_USER" == rocky ]] ||
      fail "unexpected cloud-init user for ${template}: ${CLOUDINIT_USER}"
    [[ "$CPU_TYPE" == host ]] ||
      fail "host CPU type is required for ${template}"
    [[ "$PREPARE_GUEST_IMAGE" == true && "$GUEST_PREP_MODE" == full ]] ||
      fail "full guest preparation is required for ${template}"
    [[ -n "${IMAGE_SHA256:-}" && -z "${IMAGE_SHA512:-}" ]] ||
      fail "exactly one SHA-256 checksum is required for ${template}"
  )
done

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
