# platform-template-builder

Build reusable Proxmox VM templates from upstream Linux cloud images.

This repository owns only the image/template lifecycle: it validates template config, syncs build scripts to a Proxmox node, downloads or reuses a cloud image, imports the disk, attaches cloud-init support, applies base hardware defaults, and converts the VM into a Proxmox template.

It does not provision real workload VMs, assign production IP addresses, run OpenTofu, run Ansible, configure applications, manage Kubernetes, or store secrets.

## Platform Project

This repository is one part of a five-repository homelab platform project.

The repositories are split by responsibility so that template building, infrastructure provisioning, system configuration, Kubernetes bastion tooling, and documentation can evolve independently.

| Repository | Purpose |
|---|---|
| [`platform-template-builder`](https://codeberg.org/rch/platform-template-builder.git) | Builds reusable Proxmox VM templates from cloud images. |
| [`platform-infra`](TODO_URL) | Provisions platform infrastructure with OpenTofu. |
| [`platform-config`](TODO_URL) | Configures operating systems and services with Ansible. |
| [`platform-k8s-bastion`](TODO_URL) | Contains Kubernetes bastion tooling and operational helpers. |
| [`platform-docs`](TODO_URL) | Contains architecture notes, runbooks, diagrams, and operational documentation. |

Typical workflow:

```text
platform-template-builder
  -> platform-infra
  -> platform-config
  -> platform-k8s-bastion

platform-docs documents the design and operations across all repositories.
```

## Install

Clone the repository and enter the project directory:

```bash
git clone https://codeberg.org/rch/platform-template-builder.git
cd platform-template-builder
make help
```

## Quick Start

Create a private Rocky 9 config, edit it for your Proxmox host, then validate and build:

```bash
cp configs/rocky-9-cloud-base.env.example configs/rocky-9-cloud-base.env
# edit configs/rocky-9-cloud-base.env for your Proxmox host/storage/bridge
make validate TEMPLATE=rocky-9
make build TEMPLATE=rocky-9
```

Supported `TEMPLATE` values:

- `rocky-9`
- `rocky-10.1`
- `debian-12`
- `ubuntu-24.04`

## SSH Bootstrap

Template builds use SSH and `rsync` from this workstation to the Proxmox node. You can initialize a dedicated local SSH key and config snippet for template-building access:

```bash
cp configs/ssh/template-builder.env.example configs/ssh/template-builder.env
# edit configs/ssh/template-builder.env
make init-ssh
```

The helper loads a private SSH bootstrap config from `configs/ssh/template-builder.env`, creates an ed25519 key at `~/.ssh/platform-template-builder_ed25519` if it does not already exist, prints an SSH config block, and prints the `ssh-copy-id` command needed to install the public key on Proxmox. By default, `ssh-keygen` prompts for a key passphrase. It does not install keys on Proxmox, create users, create API tokens, or write to `~/.ssh/config` unless explicitly requested.

To append the generated host block to `~/.ssh/config` and test access after installing the public key:

```bash
make init-ssh SSH_WRITE_CONFIG=1
ssh-copy-id -i ~/.ssh/platform-template-builder_ed25519.pub root@192.168.1.10
make init-ssh SSH_TEST=1
```

Set `PROXMOX_HOST="pve-template-builder"` in your private template config when using the generated alias.

## Requirements

Local machine:

- Bash
- Make
- SSH client with key access to the Proxmox node
- `ssh-keygen` when using `make init-ssh`
- `rsync`
- standard Unix tools such as `awk`, `date`, `basename`, `mkdir`, and `tee`

Proxmox node:

- Bash
- SSH enabled
- user can run `qm` and `pvesm`
- `qm`, `pvesm`, `ip`, `rsync`, and `curl` or `wget`
- target disk storage, cloud-init storage, and bridge exist
- write access to `PROXMOX_REMOTE_DIR`

See `docs/proxmox-requirements.md` for detailed checks.

## Configuration

Template builds use private `.env` files copied from committed examples:

```bash
cp configs/rocky-9-cloud-base.env.example configs/rocky-9-cloud-base.env
```

Private `.env` files are ignored and must not be committed.

SSH bootstrap uses a separate private config copied from `configs/ssh/template-builder.env.example` to `configs/ssh/template-builder.env`.

Template configs reference committed image profiles under `configs/images/`:

```bash
IMAGE_PROFILE="configs/images/rocky-9.env"
```

Image profiles contain upstream image metadata such as `IMAGE_URL`, `IMAGE_NAME`, optional `IMAGE_SHA256`, and the default cloud-init user for that OS.

## Usage

Use Make for normal local operation:

```bash
make check-tools TEMPLATE=rocky-9
make validate TEMPLATE=rocky-9
make build TEMPLATE=rocky-9
make cleanup TEMPLATE=rocky-9
```

`make check-tools` checks local tools first. If `configs/<TEMPLATE>-cloud-base.env` exists, it also checks the configured Proxmox host over SSH.

The generic Make targets resolve configs as:

```text
configs/<TEMPLATE>-cloud-base.env
```

You can override the config path explicitly:

```bash
make validate CONFIG=configs/rocky-9-cloud-base.env
```

Direct script usage is also available:

```bash
./scripts/check-tools.sh configs/rocky-9-cloud-base.env
./scripts/validate-config.sh configs/rocky-9-cloud-base.env
./scripts/remote-run-template-build.sh configs/rocky-9-cloud-base.env
```

`scripts/build-proxmox-cloud-template.sh` is intended to run on the Proxmox node, not directly from the local workstation.

Remote build logs are saved locally under:

```text
logs/YYYYMMDD-HHMMSS-<template-name>.log
```

## Documentation

Start with `docs/README.md` for the documentation index.

Key docs:

- `docs/proxmox-requirements.md`
- `docs/template-conventions.md`
- `docs/troubleshooting.md`
- `docs/roadmap.md`

## Secrets Policy

Never commit SSH private keys, Proxmox API tokens, passwords, real `.env` files, downloaded VM images, or logs containing credentials.
