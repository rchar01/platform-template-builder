# Documentation Index

Short descriptions of the repository files and documentation.

## Root Files

- `README.md`: Quick start, requirements summary, usage, and links to detailed docs.
- `AGENTS.md`: Repo-specific instructions for future OpenCode sessions.
- `CHANGELOG.md`: Versioned list of notable changes.
- `NEWS.md`: Short release-oriented summary for each version.
- `Makefile`: Generic `check-tools`, `validate`, `build`, `cleanup`, `verify`, and `shellcheck` entry points.
- `.gitignore`: Keeps private configs, downloaded images, logs, temporary files, and SSH material out of Git.
- `.editorconfig`: Basic editor formatting defaults for shell scripts and Makefiles.

## Configs

- `configs/rocky-9-cloud-base.env.example`: Rocky 9 template config example; copy to `configs/rocky-9-cloud-base.env` before building.
- `configs/debian-12-cloud-base.env.example`: Debian 12 template config example; copy to `configs/debian-12-cloud-base.env` before building.
- `configs/ubuntu-24.04-cloud-base.env.example`: Ubuntu 24.04 template config example; copy to `configs/ubuntu-24.04-cloud-base.env` before building.
- `configs/images/rocky-9.env`: Rocky 9 upstream image profile.
- `configs/images/debian-12.env`: Debian 12 upstream image profile.
- `configs/images/ubuntu-24.04.env`: Ubuntu 24.04 upstream image profile.

## Scripts

- `scripts/validate-config.sh`: Validates a template config and its referenced image profile.
- `scripts/check-tools.sh`: Verifies required local tools and, when given a config, required tools on the configured Proxmox node.
- `scripts/remote-run-template-build.sh`: Runs from the local machine, syncs files to Proxmox, executes the remote builder, and writes a local log.
- `scripts/build-proxmox-cloud-template.sh`: Runs on the Proxmox node and creates the actual VM template with `qm` commands.
- `scripts/cleanup-template-vm.sh`: Safely destroys only the configured VMID after explicit confirmation.

## Docs

- `docs/README.md`: This documentation index.
- `docs/proxmox-requirements.md`: Required local and Proxmox access, tools, storage, bridge, and validation commands.
- `docs/template-conventions.md`: Template naming, VMID range, image profile rules, and hardware defaults.
- `docs/troubleshooting.md`: Common failure symptoms, checks, and fixes.
- `docs/roadmap.md`: Future improvements intentionally left out of the first implementation.

## Examples And Runtime Directories

- `examples/ssh-config.example`: Generic SSH config example for the Proxmox host.
- `logs/.gitkeep`: Keeps the log directory present while ignoring generated log files.
