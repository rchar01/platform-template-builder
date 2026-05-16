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
IMAGE_SHA256=""
IMAGE_OS_FAMILY="rhel"
CLOUDINIT_USER="example"
```

Template configs reference profiles with `IMAGE_PROFILE`, for example:

```bash
IMAGE_PROFILE="configs/images/rocky-9.env"
```

## Hardware Defaults

- 2 cores.
- 2048 MB RAM.
- Virtio network.
- SCSI disk.
- `virtio-scsi-pci` controller.
- VGA/noVNC console with a serial port attached by default.
- Cloud-init drive.
- QEMU guest agent enabled.
- Proxmox cloud-init type `nocloud`.

## Guest Preparation

Safe guest preparation preserves the upstream cloud image package/service state, verifies basic boot files, and aligns kernel console arguments with `TEMPLATE_CONSOLE_MODE` when `grubby` is available before the disk is imported into Proxmox. Full guest preparation is available for testing and attempts to install and enable guest-side services before import:

- `cloud-init` and the standard cloud-init systemd units.
- `qemu-guest-agent` and `qemu-guest-agent.service`.
- `openssh-server` and the OS-specific SSH service.
- NetworkManager for virtio NIC configuration from Proxmox cloud-init data.
- `serial-getty@ttyS0.service` for serial-console login.

Full guest preparation also removes stale cloud-init state, SSH host keys, NetworkManager connection profiles, non-loopback legacy network-scripts profiles, cloud-init logs, and machine identity files. The template conversion happens only after the selected preparation mode succeeds.

Use `TEMPLATE_CONSOLE_MODE="vga-serial"` by default so noVNC remains useful when networking or QEMU guest agent startup fails. `TEMPLATE_CONSOLE_MODE="serial"` sets `vga: serial0` and should only be used once serial-only behavior is verified for that image.
