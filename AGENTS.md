# AGENTS.md

## Agent Workflow Expectations

- Read relevant code before editing.
- Prefer minimal changes that match existing patterns.
- Keep `README.md`, `AGENTS.md`, and skill docs current when repository behavior changes.
- If your runtime provides specialized tools or subagents for codebase exploration, use them when the repository structure, ownership boundaries, or relevant files are unclear.
- If your runtime provides specialized tools or subagents for verification, use them for non-trivial test runs, runtime-backed checks, or command-heavy validation.
- If your runtime provides specialized tools or subagents for review, use them after substantial edits to catch regressions, missing updates, or doc/code drift.
- If your runtime provides specialized tools or subagents for research, use them when behavior depends on external tooling or upstream docs.
- Prefer local repository docs, scripts, and configuration first; use web research when local sources are insufficient or freshness matters.
- Summarize any specialist-tool or subagent findings you rely on.
- Do not revert unrelated worktree changes.

## Repository Boundary

- This repo only builds reusable Proxmox templates from cloud images.
- Do not add OpenTofu provisioning, Ansible configuration, workload VM definitions, production IPs, application config, Proxmox API tokens, or secret management here.
- `scripts/build-proxmox-cloud-template.sh` is for the Proxmox node; local runs should use `make build TEMPLATE=...` or `scripts/remote-run-template-build.sh`.

## Highest-Value Sources

- Start with `README.md`, `Makefile`, `docs/README.md`, and the relevant script in `scripts/`.
- Use `docs/proxmox-requirements.md` for tool/access requirements, `docs/template-conventions.md` for template/image-profile rules, and `docs/troubleshooting.md` for failure handling.
- Trust executable sources (`Makefile`, `scripts/*.sh`, `configs/*.env.example`, `configs/images/*.env`) over prose if they conflict; update docs to match verified behavior.

## Commands Agents Should Not Guess

- Show supported targets: `make help`.
- Check local tools, and remote tools if the private config exists: `make check-tools TEMPLATE=rocky-9`.
- Validate a private config: `make validate TEMPLATE=rocky-9`.
- Build remotely through SSH/rsync: `make build TEMPLATE=rocky-9`.
- Cleanup only the configured VMID: `make cleanup TEMPLATE=rocky-9`.
- Syntax verification only: `make verify`.
- ShellCheck verification: `make shellcheck`.
- Validate an example without creating a private env: `make validate CONFIG=configs/rocky-9-cloud-base.env.example`.

## Config And Makefile Conventions

- Keep Make targets generic; do not re-add OS-specific convenience targets like `build-rocky-9`.
- `TEMPLATE ?= rocky-9` resolves to `CONFIG ?= configs/$(TEMPLATE)-cloud-base.env`.
- Private `configs/*-cloud-base.env` files are ignored and must not be committed.
- Committed image metadata belongs in `configs/images/*.env`; template configs reference it with `IMAGE_PROFILE`.
- If adding a new template, add both `configs/<template>-cloud-base.env.example` and `configs/images/<template>.env`, then update `README.md`, `docs/README.md`, and `docs/template-conventions.md`.

## Verification Notes

- `make verify` only runs `bash -n scripts/*.sh`; run `make shellcheck` after script edits.
- `make check-tools` can legitimately fail on a workstation missing `rsync`; that is a real prerequisite for remote builds.
- Remote build verification requires a real private config and SSH access to `PROXMOX_HOST`; do not fake a successful Proxmox run.

## Safety Rules

- Never commit real `.env` files, SSH keys, Proxmox API tokens, downloaded images, or generated logs.
- Cleanup and force-recreate paths must only destroy the configured `TEMPLATE_VMID`.
- Preserve the separation between image profiles, local Proxmox template config, and downstream infrastructure/configuration repositories.
