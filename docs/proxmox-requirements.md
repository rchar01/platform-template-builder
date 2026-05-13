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

Root SSH with key authentication is acceptable for the first homelab version. This repository can create local SSH client material for template-build access, but it does not create Proxmox users or manage Proxmox authorization policy.

## SSH Bootstrap

This repository can initialize local SSH client material for template-building access:

```bash
cp configs/ssh/template-builder.env.example configs/ssh/template-builder.env
# edit configs/ssh/template-builder.env
make init-ssh
```

The helper loads `configs/ssh/template-builder.env`, creates a dedicated ed25519 key under `~/.ssh/` if missing, prints an SSH config block, and prints the `ssh-copy-id` command to install the public key on Proxmox. By default, `ssh-keygen` prompts for a key passphrase. The helper does not install the key automatically, create Proxmox users, create API tokens, or write to `~/.ssh/config` unless `SSH_WRITE_CONFIG=1` is set.

After installing the public key, test the alias:

```bash
make init-ssh SSH_TEST=1
```

Use the resulting alias in private template configs:

```bash
PROXMOX_HOST="pve-template-builder"
```

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
