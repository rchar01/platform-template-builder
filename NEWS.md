# News

This file gives a short, release-oriented view of what changed between versions.

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
