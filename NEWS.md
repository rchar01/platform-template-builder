# News

This file gives a short, release-oriented view of what changed between versions.

## Unreleased

No unreleased changes.

## v1.1.0 - 2026-05-14

- `make init-ssh` now wraps the shared `platform-ssh-init` helper from `platform-tools`; template builds remain independent of the optional helper.
- Added `CONFIG_ROOT` support for keeping real template-builder configs in an external private repository such as `platform-private`.
- `check-tools`, `build`, and `cleanup` now read the template-builder SSH config directly when present, making `SSH_WRITE_CONFIG=1` optional convenience rather than an automation requirement.

## v1.0.0 - 2026-05-13

Stable release of the Proxmox template-builder workflow after validating the real SSH and config-discovery path.

Highlights:

- Added Rocky 10.1 template configuration and image profile using the upstream GenericCloud LVM image.
- Added a local SSH bootstrap helper with a dedicated private config file for Proxmox template-build access.
- Added template config reference documentation for discovering Proxmox-derived values.
- Documented public-key installation through `ssh-copy-id` and manual Proxmox `authorized_keys` setup.
- Standardized examples and docs on the `pve-template-builder` SSH alias.
- Reworked `docs/README.md` into a concise documentation index.
- Added platform project context and Codeberg install instructions.

## v0.1.0 - 2026-05-12

Initial release of `platform-template-builder`.

This release provides a small Bash workflow for building reusable Proxmox VM templates from upstream cloud images. The primary path is Rocky 9, with Debian 12 and Ubuntu 24.04 examples included.

Highlights:

- Generic `make` entry points for checking tools, validating config, building remotely, cleaning up, and running script verification.
- Separate committed image profiles under `configs/images/` and private local Proxmox template configs under `configs/*-cloud-base.env`.
- SSH/rsync remote runner that executes the Proxmox builder on the node and writes local logs.
- Safe cleanup flow that only targets the configured VMID.
- Documentation for setup requirements, conventions, troubleshooting, future work, and future agent handoff.

This repository intentionally stops at template creation. Real VM provisioning, production IPs, OpenTofu, Ansible, application configuration, and secrets remain out of scope.
