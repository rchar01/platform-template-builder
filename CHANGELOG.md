# Changelog

All notable changes to `platform-template-builder` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Guest image preparation with `qemu-img`, `virt-customize`, and `virt-sysprep` before Proxmox disk import so clones have cloud-init, QEMU guest agent, SSH, NetworkManager, serial getty, and clean identity/state.
- `make smoke-test` for cloning a temporary VM from a built template and validating cloud-init networking, QEMU guest agent, SSH login, and graceful shutdown before handoff to `platform-infra`.
- Configurable template console mode, defaulting to VGA/noVNC plus serial port support for failed-boot debugging.
- `make cleanup-smoke-test` for safely stopping and destroying only the configured smoke-test VMID.

### Changed

- Prepared builds now require `qemu-img`, `virt-customize`, and `virt-sysprep` on the Proxmox build host unless `PREPARE_GUEST_IMAGE=false` is set for troubleshooting.
- Image profiles now include `IMAGE_OS_FAMILY` so guest preparation can choose OS-specific package and service names.
- Template builds now set Proxmox cloud-init type to `nocloud` explicitly.
- Smoke tests now keep QEMU guest-agent timeout failures automatically and print Proxmox diagnostics before exiting.
- Guest cleanup now performs final machine-id setup after `virt-sysprep` and relabels SELinux contexts for RHEL-family images to avoid broken first boots.
- Guest preparation now defaults to safe mode to preserve upstream cloud image bootability; full offline customization remains opt-in with `GUEST_PREP_MODE="full"`.
- Safe guest preparation now aligns kernel console arguments with `TEMPLATE_CONSOLE_MODE` when `grubby` is available, so noVNC can show kernel boot output in `vga-serial` mode.
- Template and smoke-test cleanup now share a Proxmox destroy helper that purges VM job config and destroys unreferenced disks when supported.

## [1.1.0] - 2026-05-14

### Changed

- Refactored `make init-ssh` to wrap the shared `platform-ssh-init` helper from `platform-tools`; template builds still require only working SSH access, not the helper.
- Added `CONFIG_ROOT` support so private template and SSH configs can live in an external private repository such as `platform-private`.
- `check-tools`, `build`, and `cleanup` now use `$(SSH_CONFIG)` directly when it exists, so automation no longer requires writing aliases to `~/.ssh/config`.

## [1.0.0] - 2026-05-13

### Added

- Rocky 10.1 template example config and upstream image profile.
- Local Proxmox SSH bootstrap helper with a dedicated private config file for template-builder SSH keys and config snippets.
- Template config reference documentation that maps private config variables to Proxmox discovery commands.
- Platform project context documenting the relationship to `platform-infra`, `platform-config`, `platform-k8s-bastion`, and `platform-docs`.
- Install instructions for cloning the repository from Codeberg.
- Documentation for installing Proxmox SSH public keys through `ssh-copy-id` or manual `authorized_keys` setup.

### Changed

- Standardized documented SSH examples and committed template examples on the `pve-template-builder` alias.
- Reworked `docs/README.md` into a concise documentation index.
- Clarified `.gitignore` intent for private `.env` configs, image profiles, generated artifacts, and local SSH material.

## [0.1.0] - 2026-05-12

### Added

- Initial Bash-based Proxmox cloud template builder.
- Generic Make targets: `check-tools`, `validate`, `build`, `cleanup`, `verify`, and `shellcheck`.
- Local and remote tool verification through `scripts/check-tools.sh`.
- Config validation through `scripts/validate-config.sh`, including image profile loading and required-field checks.
- Remote build runner through `scripts/remote-run-template-build.sh`, including SSH/rsync sync and local log capture.
- Proxmox-node builder through `scripts/build-proxmox-cloud-template.sh`, including VM creation, disk import, cloud-init drive attachment, serial console setup, optional guest agent enablement, and template conversion.
- Safe cleanup script through `scripts/cleanup-template-vm.sh`, limited to the configured `TEMPLATE_VMID`.
- Image profiles for Rocky 9, Debian 12, and Ubuntu 24.04 under `configs/images/`.
- Example template configs for Rocky 9, Debian 12, and Ubuntu 24.04.
- Documentation for requirements, template conventions, troubleshooting, roadmap, and repository file responsibilities.
- Repo-local `AGENTS.md` guidance for future OpenCode sessions.

### Security

- Private `.env` configs, downloaded images, generated logs, SSH material, and other local artifacts are ignored by default.
- Proxmox API tokens, OpenTofu provisioning, Ansible configuration, production IPs, and workload VM definitions are intentionally out of scope.
