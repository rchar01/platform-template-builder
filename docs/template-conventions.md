# Template Conventions

## VMID Range

Base templates should use VMIDs in the `9000-9099` range.

Initial template IDs:

```text
9000 rocky-9-cloud-base
9001 debian-12-cloud-base
9002 ubuntu-24.04-cloud-base
9003 rocky-10.1-cloud-base
```

## Template Rules

- Templates should not contain environment-specific application config.
- Templates should not contain real workload IP addresses.
- Templates should not contain secrets.
- Templates should be generic and cloneable.
- Cloud-init values should be minimal.
- Guest images should be prepared before import with cloud-init, QEMU guest agent, SSH, NetworkManager, serial getty, and clone identity cleanup.
- Templates should be smoke-tested with temporary, non-production IP addresses before handoff to `platform-infra`.
- Upstream image URLs and filenames should live in committed image profiles under `configs/images/`.
- Local Proxmox values should live in private `configs/*-cloud-base.env` files copied from examples.

## Image Profiles

Image profiles define the upstream cloud image source for an operating system:

```bash
IMAGE_URL="https://example.invalid/cloud-image.qcow2"
IMAGE_NAME="cloud-image.qcow2"
IMAGE_SHA256="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
IMAGE_OS_FAMILY="rhel"
CLOUDINIT_USER="example"
```

Set exactly one checksum field in each image profile: `IMAGE_SHA256` for upstream SHA-256 digests or `IMAGE_SHA512` for upstream SHA-512 digests. Template builds verify the downloaded or cached image before importing it into Proxmox.

Template configs reference profiles with `IMAGE_PROFILE`, for example:

```bash
IMAGE_PROFILE="configs/images/rocky-9.env"
```

## Hardware Defaults

- 2 cores.
- 2048 MB RAM.
- Host CPU model for Rocky/RHEL 10 templates.
- Virtio network.
- SCSI disk.
- `virtio-scsi-pci` controller.
- VGA/noVNC console with a serial port attached by default.
- Cloud-init drive.
- QEMU guest agent enabled.
- Proxmox cloud-init type `nocloud`.

## Guest Preparation

Full guest preparation is the default. It copies the upstream cloud image, then installs and enables guest-side services before the disk is imported into Proxmox:

- `cloud-init` and the standard cloud-init systemd units.
- `qemu-guest-agent` and `qemu-guest-agent.service`.
- `openssh-server` and the OS-specific SSH service.
- NetworkManager for virtio NIC configuration from Proxmox cloud-init data.
- `serial-getty@ttyS0.service` for serial-console login.

Full guest preparation also removes stale cloud-init state, SSH host keys, NetworkManager connection profiles, non-loopback legacy network-scripts profiles, cloud-init logs, and machine identity files. This allows clones to regenerate unique machine identity and SSH host keys on first boot. The template conversion happens only after the selected preparation mode succeeds.

Safe guest preparation remains available for troubleshooting. It only copies the upstream cloud image with `qemu-img` and does not mount or mutate the guest filesystem.

Use `TEMPLATE_CONSOLE_MODE="vga-serial"` by default so noVNC remains useful when networking or QEMU guest agent startup fails. `TEMPLATE_CONSOLE_MODE="serial"` sets `vga: serial0` and should only be used once serial-only behavior is verified for that image.
