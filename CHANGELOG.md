# Changelog

All notable changes to `platform-template-builder` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
