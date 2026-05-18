# News

This file gives a short, release-oriented view of what changed between versions.

## v1.3.0 - 2026-05-17

- Added a `platform-infra` handoff note for OpenTofu agents cloning validated templates downstream.
- Added branded forge avatar assets and icon token CSS under `assets/brand/`, and displayed the transparent avatar in the README.
- Example guest configs now consistently include the guest-prep timeout default, and the SSH bootstrap example keeps its test command focused on Proxmox reachability.
- Public examples now use the `192.168.100.x` documentation range instead of real-looking local network addresses.
- Private template-builder docs now use the flattened `../platform-private/template-builder` config root layout.

## v1.2.0 - 2026-05-16

- Template builds now prepare a per-template image copy with `qemu-img` before import while preserving the upstream guest filesystem in safe mode.
- Added `make smoke-test` to clone a temporary VM from a template and verify cloud-init networking, QEMU guest agent, SSH, and graceful shutdown before handing the template to `platform-infra`.
- Added `make cleanup-smoke-test` for removing kept smoke-test VMs without starting another smoke test.
- Templates now default to normal VGA/noVNC output with a serial port attached, making failed boots easier to debug than serial-only display.
- Image profiles now declare `IMAGE_OS_FAMILY`; Proxmox templates now set `citype: nocloud` explicitly.
- Rocky 10.1 now uses `CPU_TYPE="host"` in the example config to avoid Proxmox generic CPU compatibility issues.
- Smoke tests now handle Rocky/RHEL 10 cloud-init `degraded done` status when only recoverable Proxmox user-data deprecation warnings are present.

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
