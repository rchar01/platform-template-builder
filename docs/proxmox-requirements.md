# Proxmox Requirements

This project builds templates by SSHing to a Proxmox node and running local Proxmox CLI commands.

## Required Access

- SSH access to the Proxmox node.
- A user that can run `qm` and `pvesm` commands.
- Bash on the Proxmox node.
- `qm`, `pvesm`, `ip`, `ping`, `rsync`, `qemu-img`, and either `curl` or `wget`.
- Target VM disk storage exists.
- Target cloud-init storage exists.
- Target Linux bridge exists.
- Proxmox node has internet access, or the image is already cached under `.cache/images/`.
- The SSH user can write to `PROXMOX_REMOTE_DIR`.

The Proxmox node also needs `sha256sum` or `sha512sum`, matching the required checksum field in the selected image profile. Builds fail before import if the downloaded or cached image does not match the profile checksum.

`virt-customize` and `virt-sysprep` come from `libguestfs-tools` on Proxmox/Debian and are required for the default `GUEST_PREP_MODE="full"`. Install it on the template build host before building full-prep templates. It may pull a sizable dependency set. Missing tools fail early with messages such as `virt-customize not found; install libguestfs-tools on the template build host.` Guest-prep commands are bounded by `GUEST_PREP_TIMEOUT_SECONDS`, which defaults to `1800` seconds per step. Set `GUEST_PREP_MODE="safe"` only for copy-only troubleshooting.

Root SSH with key authentication is acceptable for the first homelab version. This repository can create local SSH client material for template-build access, but it does not create Proxmox users or manage Proxmox authorization policy.

## SSH Bootstrap

SSH access to Proxmox is required for template builds. The key generator is optional; use it only when you want the shared [`platform-tools`](https://codeberg.org/rch/platform-tools) helper to create local SSH client material.

Install `platform-tools` so `platform-ssh-init` is on `PATH`, or set `PLATFORM_SSH_INIT` to the tool path:

```bash
git clone https://codeberg.org/rch/platform-tools ../platform-tools
make -C ../platform-tools install
```

When using a sibling checkout directly instead:

```bash
make init-ssh PLATFORM_SSH_INIT=../platform-tools/bin/platform-ssh-init
```

Initialize local SSH client material for template-building access:

```bash
cp configs/ssh/template-builder.env.example configs/ssh/template-builder.env
# edit configs/ssh/template-builder.env
make init-ssh
```

For real homelab use, the SSH bootstrap config may live in `platform-private` and be selected with `CONFIG_ROOT`:

```bash
make init-ssh CONFIG_ROOT=../platform-private/template-builder
```

The helper loads the configured SSH bootstrap file from `SSH_CONFIG`, which defaults to `$(CONFIG_ROOT)/ssh/template-builder.env`. It creates a dedicated ed25519 key at the configured `SSH_KEY_PATH` if missing, prints an SSH config block, and prints the `ssh-copy-id` command to install the public key on Proxmox. By default, `ssh-keygen` prompts for a key passphrase. The helper does not install the key automatically, create Proxmox users, create API tokens, or write to `~/.ssh/config` unless `SSH_WRITE_CONFIG=1` is set. Build automation reads this same file directly, so writing `~/.ssh/config` is optional.

CI/CD should normally skip `make init-ssh`. Put the private key and SSH config in place through the CI secret system, then run `make check-tools TEMPLATE=...` to verify access.

To create the SSH key without a passphrase:

```bash
make init-ssh SSH_EMPTY_PASSPHRASE=1
```

Use this only if you intentionally want an unencrypted local private key.

To install the public key on Proxmox when password SSH login already works:

```bash
ssh-copy-id -i ~/.ssh/platform-template-builder_ed25519.pub root@192.0.2.10
```

If password SSH login does not work yet, use the Proxmox console or web shell and install the public key manually. First show the public key on this workstation:

```bash
cat ~/.ssh/platform-template-builder_ed25519.pub
```

Then on the Proxmox node:

```bash
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat >> /root/.ssh/authorized_keys
```

Paste the public key, press `Ctrl-D`, then run:

```bash
chmod 600 /root/.ssh/authorized_keys
```

After installing the public key, test direct access through `template-builder.env`; writing the SSH alias to `~/.ssh/config` is optional:

```bash
make init-ssh SSH_WRITE_CONFIG=1
make init-ssh SSH_TEST=1
ssh pve-template-builder 'hostname && qm list && pvesm status'
```

Use the resulting alias in private template configs:

```bash
PROXMOX_HOST="pve-template-builder"
```

## Checks

Run these from the local machine:

```bash
ssh pve-template-builder 'qm list'
ssh pve-template-builder 'pvesm status'
ssh pve-template-builder 'ip link show type bridge'
ssh pve-template-builder 'command -v rsync'
ssh pve-template-builder 'command -v qemu-img'
ssh pve-template-builder 'command -v curl || command -v wget'
```

For `GUEST_PREP_MODE="full"`, also check:

```bash
ssh pve-template-builder 'command -v virt-customize && command -v virt-sysprep'
```

For mapping `pvesm`, `qm`, and bridge output to template config variables, see `template-config-reference.md`.

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
command -v qemu-img
```

## Template Smoke Test

Run a smoke test before handing a rebuilt template to `platform-infra`:

```bash
make smoke-test TEMPLATE=rocky-9 \
  SMOKE_TEST_IPV4=<temporary-ip/cidr> \
  SMOKE_TEST_GATEWAY=<gateway-ip> \
  SMOKE_TEST_DNS=<dns-ip> \
  SMOKE_TEST_SSH_KEY=~/.ssh/<cloud-init-test-key>
```

Choose a temporary IP that is not used by workload VMs, DHCP leases, reservations, or other hosts. The default smoke-test VMID is `9900`, but the script refuses to continue if that VMID already exists unless `SMOKE_TEST_FORCE_RECREATE=true` is set. Failed clones are destroyed by default except QEMU guest-agent timeouts, which print diagnostics and keep the VM automatically for noVNC/console debugging. The default boot wait is `SMOKE_TEST_BOOT_TIMEOUT_SECONDS=900`.

Clean a kept smoke-test VM without starting a new smoke test:

```bash
make cleanup-smoke-test TEMPLATE=rocky-9 SMOKE_TEST_VMID=9900
```

Use `CLEANUP_ASSUME_YES=true` only when you have verified the configured VMID is safe to destroy.

Cleanup force-stops running VMs before destroying them. This is intentional because failed smoke-test guests may not have working QEMU guest agent or ACPI shutdown paths.
