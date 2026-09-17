<div align="center">
  <img src="assets/brand/platform-template-builder-forge-avatar-transparent-512.png" width="256" alt="platform-template-builder logo">

  <h1>platform-template-builder</h1>

  <p>Build reusable Proxmox VM templates from upstream Linux cloud images.</p>
</div>

---

This repository validates template configs, prepares checksum-verified cloud
images and builds reusable Proxmox templates over SSH and `rsync`. An optional
smoke test checks a disposable clone before handoff.

Workload VM provisioning belongs in
[`platform-infra`](https://codeberg.org/rch/platform-infra), and guest/service
configuration in [`platform-config`](https://codeberg.org/rch/platform-config).
Keep production IPs, applications, OpenTofu, Ansible and secrets out of this repo.

**Start here: [Documentation Index](docs/README.md)** for requirements,
configuration, troubleshooting and the infrastructure handoff.

## Requirements

- **Workstation:** Bash, Make, OpenSSH client, `rsync` and standard Unix tools;
  smoke tests also require `ssh-keygen` and `timeout`.
- **Proxmox node:** SSH access with permission to run `qm`/`pvesm`, the selected
  storage and bridge, and a writable `PROXMOX_REMOTE_DIR`. Full guest preparation
  requires `qemu-img`, `virt-customize` and `virt-sysprep` (`libguestfs-tools` on
  Proxmox/Debian), plus access to the selected package repositories.

See [Proxmox Requirements](docs/proxmox-requirements.md) for the full tool/access
checks. `make check-tools` contacts Proxmox when the selected config exists.

## Quick Start

Use Make from the workstation; the underlying builder runs on the Proxmox node.
Supported `TEMPLATE` values are `rocky-9` (Make's default), `rocky-10.0`,
`rocky-10.1`, `rocky-10.2`, `debian-12` and `ubuntu-24.04`.

```bash
git clone https://codeberg.org/rch/platform-template-builder
cd platform-template-builder
make help

cp configs/rocky-9-cloud-base.env.example configs/rocky-9-cloud-base.env
cp configs/ssh/template-builder.env.example configs/ssh/template-builder.env
```

Edit both files for your Proxmox host, storage, bridge, safe template VMID, SSH
user and key using the [Config Reference](docs/template-config-reference.md).
Establish SSH access before continuing, using an existing key or the
[optional helper](#optional-ssh-helper). Private `.env` files are ignored and
must not be committed; keep keys, tokens, images and generated logs out of Git.

```bash
make validate TEMPLATE=rocky-9
make check-tools TEMPLATE=rocky-9
make build TEMPLATE=rocky-9

# Replace placeholders with non-conflicting temporary network values.
make smoke-test TEMPLATE=rocky-9 \
  SMOKE_TEST_IPV4='<temporary-ip/cidr>' \
  SMOKE_TEST_GATEWAY='<gateway-ip>' \
  SMOKE_TEST_DNS='<dns-ip>'
```

Smoke testing is strongly recommended before the
[platform-infra handoff](docs/platform-infra-handoff.md). Check that the default
smoke VMID `9900` is free, or pass `SMOKE_TEST_VMID=<free-vmid>`. Do not reuse
workload addresses, DHCP leases or reservations.

### Separate Private Config Root

For real deployment configs, keep the same files under a private root, for
example `../platform-private/template-builder/rocky-9-cloud-base.env` and
`../platform-private/template-builder/ssh/template-builder.env`. Add
`CONFIG_ROOT` to the same Make commands above:

```bash
make validate TEMPLATE=rocky-9 CONFIG_ROOT=../platform-private/template-builder
```

Make resolves `CONFIG=$(CONFIG_ROOT)/$(TEMPLATE)-cloud-base.env` and
`SSH_CONFIG=$(CONFIG_ROOT)/ssh/template-builder.env`. Both can be overridden
explicitly. Image profiles remain in this public checkout under
[`configs/images/`](configs/images/); private configs select `IMAGE_PROFILE`
without redefining profile-owned metadata. See
[Private Config Setup](docs/template-config-reference.md#running-with-separate-private-config-repo).

### Optional SSH Helper

If [`platform-tools`](https://codeberg.org/rch/platform-tools) provides
`platform-ssh-init` on `PATH`, run `make init-ssh` with your edited `SSH_CONFIG`.
Alternatively, set `PLATFORM_SSH_INIT` to the helper path. It creates a local key
if missing and prints the SSH config and public-key installation command; it
does not install access on Proxmox. After installing the public key, use
`make init-ssh SSH_TEST=1`.

Make reads an existing `SSH_CONFIG` directly. `SSH_WRITE_CONFIG=1` additionally
writes the SSH alias; `SSH_EMPTY_PASSPHRASE=1` intentionally creates an unencrypted
key. See [SSH Bootstrap](docs/proxmox-requirements.md#ssh-bootstrap) for setup,
manual console fallback and CI key custody. Existing managed SSH access does not
require this helper.

## Build and Smoke-Test Boundaries

- Full guest preparation is the default: it installs guest services and clears
  stale cloud-init, machine identity, network and SSH host-key state. It needs
  outbound libguestfs package access even with a cached image. `GUEST_PREP_MODE=safe`
  is copy-only troubleshooting, not the clone-ready path for profiles requiring
  QEMU guest-agent support.
- Rocky 10.0, 10.1 and 10.2 are **exact-minor profiles**. Preparation and smoke
  verify `VERSION_ID` and persistent DNF `releasever`; package installation uses
  the matching BaseOS/AppStream repositories and guest-local Rocky signing key.
  Templates/clones use `ciupgrade=0` to prevent implicit first-boot upgrades.
  **10.0 and 10.1 Vault repositories are unsupported and receive no current
  security fixes.** 10.0 is retained for scoped migration tests, not new or
  long-lived deployments. 10.2 receives active exact-minor errata; move its
  profile to Vault deliberately when those paths retire.
- **Rocky/RHEL 10 requires x86-64-v3 CPU features.** Use `CPU_TYPE="host"` as in
  the examples unless deliberately selecting another compatible model. Proxmox's
  generic default may not boot these guests. Keep `vga-serial` console mode for
  noVNC debugging unless serial-only operation has been verified.
- Image checksum and guest preparation checks precede replacement of an existing
  template. Set `FORCE_RECREATE=true` only after verifying `TEMPLATE_VMID` is safe
  to destroy. See [Template Conventions](docs/template-conventions.md).

The smoke test checks cloud-init, SSH login, guest services, QEMU guest agent,
the configured IP, profile-pinned version and graceful shutdown, then destroys
the temporary clone by default. Certain failures retain it for console debugging;
see [Smoke-Test Requirements](docs/proxmox-requirements.md#template-smoke-test)
and [Troubleshooting](docs/troubleshooting.md).

With an existing `SSH_CONFIG`, the smoke test defaults to its `SSH_KEY_PATH`.
Only the derived public key is injected into the temporary clone; the private
key is neither copied to Proxmox nor baked into the template. Set
`SMOKE_TEST_SSH_KEY` for a separate guest-test identity; any supplied
`SMOKE_TEST_SSH_PUBLIC_KEY` must match it. **Disposable smoke-test SSH uses
`StrictHostKeyChecking=no` and `UserKnownHostsFile=/dev/null`: it does not
authenticate the clone's host key.** A passing login is not authenticated host
identity evidence for downstream workloads.

## Cleanup and Logs

Run cleanup only after reviewing the selected config and VMID:

```bash
make cleanup-smoke-test TEMPLATE=rocky-9 SMOKE_TEST_VMID=9900
make cleanup TEMPLATE=rocky-9
```

The first destroys only `SMOKE_TEST_VMID`; the second destroys only
`TEMPLATE_VMID`. Both force-stop running guests and require typing the target
VMID unless `CLEANUP_ASSUME_YES=true` is set. Use that override, or
`SMOKE_TEST_FORCE_RECREATE=true` for an existing smoke VMID, only after verifying
the target is safe to destroy. Cleanup uses purge and unreferenced-disk cleanup
where supported by Proxmox.

Remote build logs are saved locally as
`logs/YYYYMMDD-HHMMSS-<template-name>.log`.

## Development

Local verification needs no private config or Proxmox access:

```bash
make help
make verify
make shellcheck
```

`make verify` runs Bash syntax and local profile/version contract tests;
`make shellcheck` requires ShellCheck. These do not qualify a remote build or
clone. Separately, `make check-images` checks committed upstream image URLs
without downloading image bodies and requires network access.

## Documentation

- [Documentation Index](docs/README.md)
- [Proxmox Requirements and SSH Setup](docs/proxmox-requirements.md)
- [Template Config Reference](docs/template-config-reference.md)
- [Template Conventions](docs/template-conventions.md)
- [Troubleshooting](docs/troubleshooting.md)
- [platform-infra Handoff](docs/platform-infra-handoff.md)
- [Roadmap](docs/roadmap.md)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
