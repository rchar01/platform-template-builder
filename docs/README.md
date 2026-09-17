# Documentation Index

Use this page as a navigation index for the repository docs.

## Start Here

- [Project README](../README.md): Scope, [quick start](../README.md#quick-start), private config root, optional SSH helper and [development checks](../README.md#development).
- [Makefile](../Makefile): Supported local entry points. Run `make help` to see them.

## Docs In This Directory

- [Proxmox Requirements](proxmox-requirements.md): Required access, SSH bootstrap, Proxmox tool checks, storage requirements, and bridge checks.
- [Template Config Reference](template-config-reference.md): Maps template config variables to Proxmox discovery commands and recommended values.
- [Template Conventions](template-conventions.md): Template naming, VMID range, image profile rules, and default hardware conventions.
- [platform-infra Handoff](platform-infra-handoff.md): Notes for the OpenTofu agent cloning validated templates in `platform-infra`.
- [Troubleshooting](troubleshooting.md): Common failure modes, validation checks, and recovery steps.
- [Roadmap](roadmap.md): Improvements intentionally left out of the current version.

## Common Tasks

- First-time setup: start with the [quick start](../README.md#quick-start), then use [Proxmox Requirements](proxmox-requirements.md).
- Fill in a private template config: use the [Config Reference](template-config-reference.md).
- Use private configs from `platform-private`: use [Separate Private Config Setup](template-config-reference.md#running-with-separate-private-config-repo).
- Add or update a template: use [Template Conventions](template-conventions.md), add the matching example and image profile under [configs](../configs/), and register its selector and VMID in the project documentation.
- Hand off a smoke-tested template to OpenTofu: use [platform-infra Handoff](platform-infra-handoff.md).
- Smoke-test or debug a failed build/clone: use [Troubleshooting](troubleshooting.md) and review the [smoke-test boundaries](../README.md#build-and-smoke-test-boundaries).
- Understand repository boundaries: read the [README](../README.md) and [AGENTS.md](../AGENTS.md).

## Key Repo Paths

- [configs](../configs/): Private template config examples (`*.env.example`) to copy locally.
- [SSH bootstrap example](../configs/ssh/template-builder.env.example): Optional config for the shared `platform-ssh-init` helper.
- [Image profiles](../configs/images/): Committed upstream image metadata.
- [scripts](../scripts/): Executable implementation for validation, SSH bootstrap, remote build, smoke testing, smoke-test cleanup, and template cleanup.
