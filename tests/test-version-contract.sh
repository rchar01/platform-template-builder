#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ptb-version-contract.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
# shellcheck source=scripts/common.sh
. "$ROOT_DIR/scripts/common.sh"

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected command to contain: $2"
}

expected_assertion=". /etc/os-release && test \"\${VERSION_ID:-}\" = '10.1'"
[[ "$(ptb_guest_version_assertion '10.1')" == "$expected_assertion" ]] ||
  fail "unexpected guest version assertion"

expected_releasever_assertion="test \"\$(cat /etc/dnf/vars/releasever)\" = '10.1'"
releasever_assertion=$(ptb_guest_dnf_releasever_assertion '10.1')
[[ "$releasever_assertion" == "$expected_releasever_assertion" ]] ||
  fail "unexpected guest DNF releasever assertion"

releasever_path="$TMP_DIR/releasever"
releasever_test_assertion=${releasever_assertion//\/etc\/dnf\/vars\/releasever/$releasever_path}
printf '10.1\n' >"$releasever_path"
bash -c "$releasever_test_assertion" || fail "matching DNF releasever was rejected"
printf '10.2\n' >"$releasever_path"
if bash -c "$releasever_test_assertion"; then
  fail "mismatched DNF releasever was accepted"
fi
rm -f "$releasever_path"
if bash -c "$releasever_test_assertion" >/dev/null 2>&1; then
  fail "missing DNF releasever was accepted"
fi

IMAGE_DNF_RELEASEVER=10.1
IMAGE_DNF_BASEOS_URL=https://dl.rockylinux.org/vault/rocky/10.1/BaseOS/x86_64/os/
IMAGE_DNF_APPSTREAM_URL=https://dl.rockylinux.org/vault/rocky/10.1/AppStream/x86_64/os/
IMAGE_DNF_GPGKEY=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-10
command=$(ptb_rhel_package_install_command 'cloud-init,qemu-guest-agent')

assert_contains "$command" "--disablerepo='*'"
assert_contains "$command" "ptb-baseos,${IMAGE_DNF_BASEOS_URL}"
assert_contains "$command" "ptb-appstream,${IMAGE_DNF_APPSTREAM_URL}"
assert_contains "$command" 'gpgcheck=1'
assert_contains "$command" "printf '%s\\n' '10.1' > /etc/dnf/vars/releasever"
assert_contains "$command" 'install cloud-init qemu-guest-agent'

mkdir -p "$TMP_DIR/etc/dnf/vars"
dnf() {
  printf '%s\n' "$@" >"$DNF_ARGV_FILE"
}
export -f dnf
command=${command//\/etc\/dnf\/vars/$TMP_DIR\/etc\/dnf\/vars}
DNF_ARGV_FILE="$TMP_DIR/dnf.argv" bash -c "$command"

mapfile -t dnf_argv <"$TMP_DIR/dnf.argv"
expected_argv=(
  -y
  "--disablerepo=*"
  "--repofrompath=ptb-baseos,${IMAGE_DNF_BASEOS_URL}"
  "--repofrompath=ptb-appstream,${IMAGE_DNF_APPSTREAM_URL}"
  --setopt=ptb-baseos.gpgcheck=1
  --setopt=ptb-baseos.gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-10
  --setopt=ptb-appstream.gpgcheck=1
  --setopt=ptb-appstream.gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-10
  install
  cloud-init
  qemu-guest-agent
)
# Package signatures are verified with the image's Rocky key. Repository
# metadata signatures are not enabled because Rocky Vault repodata is unsigned.
[[ "${dnf_argv[*]}" == "${expected_argv[*]}" ]] ||
  fail "unexpected DNF argv: ${dnf_argv[*]}"
[[ "$(<"$TMP_DIR/etc/dnf/vars/releasever")" == 10.1 ]] ||
  fail "releasever was not persisted"

ptb_is_safe_version 10.1 || fail "10.1 should be a safe version"
if ptb_is_safe_version '10.1;touch /tmp/bad'; then
  fail "unsafe version was accepted"
fi
ptb_is_https_url "$IMAGE_DNF_BASEOS_URL" || fail "Vault URL should be accepted"
if ptb_is_https_url 'http://example.test/repo'; then
  fail "non-HTTPS repository URL was accepted"
fi
ptb_is_file_url "$IMAGE_DNF_GPGKEY" || fail "guest GPG key URL should be accepted"
if ptb_is_file_url 'https://example.test/key'; then
  fail "non-file GPG key URL was accepted"
fi

smoke_runner=$(<"$ROOT_DIR/scripts/proxmox-smoke-test-runner.sh")
assert_contains "$smoke_runner" '--ciupgrade 0'

template_builder=$(<"$ROOT_DIR/scripts/build-proxmox-cloud-template.sh")
# shellcheck disable=SC2016
assert_contains "$template_builder" 'qm set "$TEMPLATE_VMID" --ciupgrade 0'

smoke_test=$(<"$ROOT_DIR/scripts/smoke-test-template.sh")
# shellcheck disable=SC2016
cloud_init_gate='guest_cloud_init_wait "$SMOKE_TEST_CLOUDINIT_TIMEOUT_SECONDS"'
# shellcheck disable=SC2016
version_gate='if [[ -n "${IMAGE_EXPECTED_VERSION_ID:-}" ]]; then'
[[ "$smoke_test" == *"$cloud_init_gate"*"$version_gate"* ]] ||
  fail "guest version gate must run after cloud-init completion"
# shellcheck disable=SC2016
releasever_gate='if [[ -n "${IMAGE_DNF_RELEASEVER:-}" ]]; then'
[[ "$smoke_test" == *"$cloud_init_gate"*"$releasever_gate"* ]] ||
  fail "guest DNF releasever gate must run after cloud-init completion"

printf '[OK] Exact version command contract\n'
