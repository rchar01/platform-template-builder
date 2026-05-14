# Template Config Reference

Template configs are private `.env` files copied from committed examples under `configs/`. They describe one reusable Proxmox template build.

For a normal first build, copy an example and edit only the Proxmox-specific values:

```bash
cp configs/rocky-10.1-cloud-base.env.example configs/rocky-10.1-cloud-base.env
```

## Private Config Location

For local experiments, copying examples into this repository is acceptable because private `.env` files are ignored.

For real homelab or production use, prefer storing private configs in `platform-private` and point Make at them with `CONFIG_ROOT` or `CONFIG`:

```text
../platform-private/template-builder/configs/
  rocky-10.1-cloud-base.env
  ssh/template-builder.env
```

```bash
make validate TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder/configs
make check-tools TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder/configs
make build TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder/configs
```

The committed image profiles remain in this repository under `configs/images/`. Private template configs should continue to reference them, for example:

```bash
IMAGE_PROFILE="configs/images/rocky-10.1.env"
```

CI/CD should not generate SSH keys. It should provide private keys and private configs through the CI secret system or a checked-out private repo, then run `make check-tools` and `make build` with `CONFIG_ROOT` or `CONFIG`.

## First-Time Discovery Commands

These commands assume your SSH bootstrap alias is `pve-template-builder`. If you used another alias, replace it in the commands.

```bash
ssh pve-template-builder 'hostname'
ssh pve-template-builder 'qm list'
ssh pve-template-builder 'pvesm status'
ssh pve-template-builder 'ip link show type bridge'
ssh pve-template-builder 'command -v qm && command -v pvesm && command -v rsync'
ssh pve-template-builder 'command -v curl || command -v wget'
```

## Variables

| Variable | Source | How To Choose Or Discover |
|---|---|---|
| `TEMPLATE_NAME` | Local convention | Use the example name unless adding a new template. See `template-conventions.md`. |
| `TEMPLATE_VMID` | Local choice plus Proxmox check | Use `ssh pve-template-builder 'qm list'`; pick a free ID in the template range from `template-conventions.md`. |
| `IMAGE_PROFILE` | Repo config | Use a committed file under `configs/images/`. |
| `PROXMOX_HOST` | SSH setup | Use a working SSH alias or `user@host`; the optional SSH bootstrap config defaults to `pve-template-builder`. |
| `PROXMOX_REMOTE_DIR` | Local choice on Proxmox node | Use a writable path on the Proxmox node. `/root/platform-template-builder` is suitable when using root SSH. |
| `DISK_STORAGE` | Proxmox storage | Use `ssh pve-template-builder 'pvesm status'` and choose storage that can hold VM disks. |
| `CLOUDINIT_STORAGE` | Proxmox storage | Use `ssh pve-template-builder 'pvesm status'` and choose storage that supports cloud-init snippets/drives in your Proxmox setup. |
| `BRIDGE` | Proxmox network | Use `ssh pve-template-builder 'ip link show type bridge'`; common default is `vmbr0`. |
| `CPU_CORES` | Local template default | Default `2` is fine for base templates. |
| `MEMORY_MB` | Local template default | Default `2048` is fine for base templates. |
| `BIOS_TYPE` | Template default | Use `seabios` unless you specifically need UEFI/OVMF. |
| `MACHINE_TYPE` | Template default | Use `q35`. |
| `DISK_BUS` | Script-supported value | Use `scsi`; the validation script currently accepts only `scsi`. |
| `SCSI_CONTROLLER` | Template default | Use `virtio-scsi-pci`. |
| `ENABLE_QEMU_AGENT` | Local choice | Usually `true`; the Proxmox flag is enabled, but the guest package may still need later configuration. |
| `FORCE_RECREATE` | Safety switch | Keep `false` unless you intentionally want to destroy and recreate the configured `TEMPLATE_VMID`. |

## Values Usually Edited First

For a first build, these are usually the only values you need to change:

```bash
PROXMOX_HOST="pve-template-builder"
PROXMOX_REMOTE_DIR="/root/platform-template-builder"
DISK_STORAGE="<from pvesm status>"
CLOUDINIT_STORAGE="<from pvesm status>"
BRIDGE="<from ip link show type bridge>"
```

## Image Profile Variables

Image profiles are committed files under `configs/images/`. Template configs reference them with `IMAGE_PROFILE`.

| Variable | Source |
|---|---|
| `IMAGE_URL` | Committed image profile. |
| `IMAGE_NAME` | Committed image profile. |
| `IMAGE_SHA256` | Committed image profile when upstream provides a checksum. |
| `CLOUDINIT_USER` | Committed image profile default for the OS. |

Do not copy image metadata into private template configs unless you are intentionally adding or changing an image profile.

## Validate And Build

After editing the private template config:

```bash
make validate TEMPLATE=rocky-10.1
make check-tools TEMPLATE=rocky-10.1
make build TEMPLATE=rocky-10.1
```

Verify the resulting template on Proxmox:

```bash
ssh pve-template-builder 'qm list'
ssh pve-template-builder 'qm config 9003'
```
