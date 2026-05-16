# Template Config Reference

Template configs are private `.env` files copied from committed examples under `configs/`. They describe one reusable Proxmox template build.

For a normal first build, copy an example and edit only the Proxmox-specific values:

```bash
cp configs/rocky-10.1-cloud-base.env.example configs/rocky-10.1-cloud-base.env
```

## Running With Default Local Configs

Use this flow when private configs are stored under this checkout:

```bash
cp configs/rocky-10.1-cloud-base.env.example configs/rocky-10.1-cloud-base.env
cp configs/ssh/template-builder.env.example configs/ssh/template-builder.env

# edit both files for your Proxmox host, storage, bridge, SSH user, and key
make init-ssh

# run the ssh-copy-id command printed by make init-ssh, for example:
ssh-copy-id -i ~/.ssh/platform-template-builder_ed25519.pub root@<proxmox-ip>
make init-ssh SSH_TEST=1

make check-tools TEMPLATE=rocky-10.1
make validate TEMPLATE=rocky-10.1
make build TEMPLATE=rocky-10.1

# choose a temporary IP that is not used by platform-infra VMs
make smoke-test TEMPLATE=rocky-10.1 \
  SMOKE_TEST_IPV4=<temporary-ip/cidr> \
  SMOKE_TEST_GATEWAY=<gateway-ip> \
  SMOKE_TEST_DNS=<dns-ip> \
  SMOKE_TEST_SSH_KEY=~/.ssh/<cloud-init-test-key>
```

## Running With Separate Private Config Repo

For real homelab or production use, prefer storing private configs in `platform-private` and point Make at them with `CONFIG_ROOT` or `CONFIG`:

```text
../platform-private/template-builder/
  rocky-10.1-cloud-base.env
  ssh/template-builder.env
```

```bash
# clone or place your private config repo as ../platform-private
# git clone <your-platform-private-url> ../platform-private

make init-ssh CONFIG_ROOT=../platform-private/template-builder

# run the ssh-copy-id command printed by make init-ssh, for example:
ssh-copy-id -i ~/.ssh/platform-template-builder_ed25519.pub root@<proxmox-ip>
make init-ssh SSH_TEST=1 CONFIG_ROOT=../platform-private/template-builder

make validate TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder
make check-tools TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder
make build TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder

make smoke-test TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder \
  SMOKE_TEST_IPV4=<temporary-ip/cidr> \
  SMOKE_TEST_GATEWAY=<gateway-ip> \
  SMOKE_TEST_DNS=<dns-ip> \
  SMOKE_TEST_SSH_KEY=~/.ssh/<cloud-init-test-key>
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
| `PROXMOX_HOST` | SSH setup | Use a descriptive SSH label or reachable host. When `$(CONFIG_ROOT)/ssh/template-builder.env` exists, build automation uses that file's `SSH_HOST`, `SSH_USER`, and `SSH_KEY_PATH` directly. |
| `PROXMOX_REMOTE_DIR` | Local choice on Proxmox node | Use a writable path on the Proxmox node. `/root/platform-template-builder` is suitable when using root SSH. |
| `DISK_STORAGE` | Proxmox storage | Use `ssh pve-template-builder 'pvesm status'` and choose storage that can hold VM disks. |
| `CLOUDINIT_STORAGE` | Proxmox storage | Use `ssh pve-template-builder 'pvesm status'` and choose storage that supports cloud-init snippets/drives in your Proxmox setup. |
| `BRIDGE` | Proxmox network | Use `ssh pve-template-builder 'ip link show type bridge'`; common default is `vmbr0`. |
| `CPU_CORES` | Local template default | Default `2` is fine for base templates. |
| `CPU_TYPE` | Proxmox CPU model | Optional. Use `host` for Rocky/RHEL 10 unless you have selected another x86-64-v3-capable model. Leave unset to use the Proxmox default. |
| `MEMORY_MB` | Local template default | Default `2048` is fine for base templates. |
| `BIOS_TYPE` | Template default | Use `seabios` unless you specifically need UEFI/OVMF. |
| `MACHINE_TYPE` | Template default | Use `q35`. |
| `DISK_BUS` | Script-supported value | Use `scsi`; the validation script currently accepts only `scsi`. |
| `SCSI_CONTROLLER` | Template default | Use `virtio-scsi-pci`. |
| `TEMPLATE_CONSOLE_MODE` | Template default | Use `vga-serial` for normal noVNC debugging plus serial port support. Use `serial` only after serial-only console behavior is proven. |
| `ENABLE_QEMU_AGENT` | Local choice | Usually `true`; enables the Proxmox VM setting. Safe guest prep does not install the in-guest package; smoke testing verifies whether the upstream image already has a working agent. |
| `PREPARE_GUEST_IMAGE` | Build behavior | Usually `true`; prepares a per-template image copy before import. |
| `GUEST_PREP_MODE` | Build behavior | Use `safe`; copies the upstream image without mounting or mutating the guest filesystem. `full` enables invasive offline customization for testing. |
| `GUEST_PREP_TIMEOUT_SECONDS` | Optional safety override | Defaults to `1800`; bounds each guest-prep step. |
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
| `IMAGE_OS_FAMILY` | Committed image profile; currently `rhel` or `debian` for guest preparation package/service names. |
| `CLOUDINIT_USER` | Committed image profile default for the OS. |

Do not copy image metadata into private template configs unless you are intentionally adding or changing an image profile.

## Validate And Build

After editing the private template config:

```bash
make validate TEMPLATE=rocky-10.1
make check-tools TEMPLATE=rocky-10.1
make build TEMPLATE=rocky-10.1
make smoke-test TEMPLATE=rocky-10.1 \
  SMOKE_TEST_IPV4=<temporary-ip/cidr> \
  SMOKE_TEST_GATEWAY=<gateway-ip> \
  SMOKE_TEST_DNS=<dns-ip> \
  SMOKE_TEST_SSH_KEY=~/.ssh/<cloud-init-test-key> \
  SMOKE_TEST_BOOT_TIMEOUT_SECONDS=900
```

Verify the resulting template on Proxmox:

```bash
ssh pve-template-builder 'qm list'
ssh pve-template-builder 'qm config 9003'
```
