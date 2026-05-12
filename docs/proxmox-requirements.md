# Proxmox Requirements

This project builds templates by SSHing to a Proxmox node and running local Proxmox CLI commands.

## Required Access

- SSH access to the Proxmox node.
- A user that can run `qm` and `pvesm` commands.
- Bash on the Proxmox node.
- `qm`, `pvesm`, `ip`, `rsync`, and either `curl` or `wget`.
- Target VM disk storage exists.
- Target cloud-init storage exists.
- Target Linux bridge exists.
- Proxmox node has internet access, or the image is already cached under `.cache/images/`.
- The SSH user can write to `PROXMOX_REMOTE_DIR`.

If `IMAGE_SHA256` is set in a profile under `configs/images/`, the Proxmox node also needs `sha256sum`.

Root SSH with key authentication is acceptable for the first homelab version. This repository documents SSH access but does not generate or manage SSH keys.

## Checks

Run these from the local machine:

```bash
ssh pve01 'qm list'
ssh pve01 'pvesm status'
ssh pve01 'ip link show type bridge'
ssh pve01 'command -v rsync'
ssh pve01 'command -v curl || command -v wget'
```

You can also run the project tool check locally:

```bash
make check-tools TEMPLATE=rocky-9
```

The remote checks run only after the private config file exists, because the script needs `PROXMOX_HOST` from that config.

Run these on the Proxmox node if troubleshooting locally:

```bash
qm list
pvesm status
ip link show type bridge
```
