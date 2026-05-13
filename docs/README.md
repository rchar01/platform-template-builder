# Documentation Index

Use this page as a navigation index for the repository docs.

## Start Here

- `../README.md`: Project overview, install, SSH bootstrap, quick start, configuration, and normal build commands.
- `../Makefile`: Supported local entry points. Run `make help` to see them.

## Docs In This Directory

- `proxmox-requirements.md`: Required access, SSH bootstrap, Proxmox tool checks, storage requirements, and bridge checks.
- `template-conventions.md`: Template naming, VMID range, image profile rules, and default hardware conventions.
- `troubleshooting.md`: Common failure modes, validation checks, and recovery steps.
- `roadmap.md`: Improvements intentionally left out of the current version.

## Common Tasks

- First-time setup: start with `../README.md`, then use `proxmox-requirements.md`.
- Add or update a template: use `template-conventions.md`, then update the matching files under `../configs/`.
- Debug a failed build: use `troubleshooting.md`.
- Understand repository boundaries: read `../README.md` and `../AGENTS.md`.

## Key Repo Paths

- `../configs/*.env.example`: Private template config examples to copy locally.
- `../configs/ssh/template-builder.env.example`: SSH bootstrap config example.
- `../configs/images/*.env`: Committed upstream image profiles.
- `../scripts/`: Executable implementation for validation, SSH bootstrap, remote build, and cleanup.
