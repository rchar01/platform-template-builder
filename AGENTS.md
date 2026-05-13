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

## Homelab Platform Context

This repository is one part of a five-repository homelab platform:

- `platform-template-builder`: builds reusable Proxmox VM templates from cloud images using SSH, `rsync`, and Proxmox `qm` commands.
- `platform-infra`: provisions Proxmox VMs from those templates using OpenTofu and the Proxmox API.
- `platform-config`: configures guest operating systems and services using Ansible over SSH.
- `platform-k8s-bastion`: contains Kubernetes bastion tooling and operational helpers.
- `platform-docs`: contains architecture notes, runbooks, diagrams, and operational decisions.

The intended lifecycle is:

1. Build base Proxmox templates in this repository.
2. Provision VMs from templates in `platform-infra`.
3. Generate or update Ansible inventory from infrastructure outputs.
4. Configure VMs in `platform-config`.
5. Use `platform-k8s-bastion` for Kubernetes operational access and helpers.
6. Document design and operations in `platform-docs`.

Keep responsibility boundaries strict. When a requested change starts to involve long-lived VM provisioning, OpenTofu resources, Ansible roles, Kubernetes operations, application configuration, production IPs, or secrets, do not add it here. Instead, identify the appropriate downstream repository.

## Highest-Value Sources

- Start with `README.md`, `Makefile`, `docs/README.md`, and the relevant script in `scripts/`.
- Use `docs/proxmox-requirements.md` for tool/access requirements, `docs/template-config-reference.md` for config variable discovery, `docs/template-conventions.md` for template/image-profile rules, and `docs/troubleshooting.md` for failure handling.
- Trust executable sources (`Makefile`, `scripts/*.sh`, `configs/*.env.example`, `configs/ssh/*.env.example`, `configs/images/*.env`) over prose if they conflict; update docs to match verified behavior.

## Commands Agents Should Not Guess

- Show supported targets: `make help`.
- Initialize local SSH key/config helper: `make init-ssh SSH_CONFIG=configs/ssh/template-builder.env`.
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
- `SSH_CONFIG ?= configs/ssh/template-builder.env` resolves the private SSH bootstrap config for `make init-ssh`.
- Private `configs/*-cloud-base.env` files are ignored and must not be committed.
- Private `configs/ssh/*.env` files are ignored and must not be committed.
- Committed image metadata belongs in `configs/images/*.env`; template configs reference it with `IMAGE_PROFILE`.
- If adding a new template, add both `configs/<template>-cloud-base.env.example` and `configs/images/<template>.env`, then update `README.md`, `docs/README.md`, and `docs/template-conventions.md`.

## Verification Notes

- `make verify` only runs `bash -n scripts/*.sh`; run `make shellcheck` after script edits.
- `make check-tools` can legitimately fail on a workstation missing `rsync`; that is a real prerequisite for remote builds.
- Remote build verification requires a real private config and SSH access to `PROXMOX_HOST`; do not fake a successful Proxmox run.

## Safety Rules

- Commit only examples such as `.env.example`; never commit private SSH keys, Proxmox API tokens, CA private keys, real `.env` files, real `.tfvars`, Ansible Vault passwords, production inventories, downloaded images, or generated logs.
- Cleanup and force-recreate paths must only destroy the configured `TEMPLATE_VMID`.
- Preserve the separation between image profiles, local Proxmox template config, and downstream infrastructure/configuration repositories.
