# Template Conventions

## VMID Range

Base templates should use VMIDs in the `9000-9099` range.

Initial template IDs:

```text
9000 rocky-9-cloud-base
9001 debian-12-cloud-base
9002 ubuntu-24.04-cloud-base
```

## Template Rules

- Templates should not contain environment-specific application config.
- Templates should not contain real workload IP addresses.
- Templates should not contain secrets.
- Templates should be generic and cloneable.
- Cloud-init values should be minimal.
- Upstream image URLs and filenames should live in committed image profiles under `configs/images/`.
- Local Proxmox values should live in private `configs/*-cloud-base.env` files copied from examples.

## Image Profiles

Image profiles define the upstream cloud image source for an operating system:

```bash
IMAGE_URL="https://example.invalid/cloud-image.qcow2"
IMAGE_NAME="cloud-image.qcow2"
IMAGE_SHA256=""
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
- Serial console.
- Cloud-init drive.
- QEMU guest agent enabled.
