<div align="center">
  <img src="assets/brand/platform-template-builder-forge-avatar-transparent-512.png" width="256" alt="platform-template-builder logo">

  <h1>platform-template-builder</h1>

  <p>Build reusable Proxmox VM templates from upstream Linux cloud images.</p>
</div>

---

This repository owns only the image/template lifecycle: it validates template config, syncs build scripts to a Proxmox node, downloads or reuses a cloud image, prepares the guest image, imports the disk, attaches cloud-init support, applies base hardware defaults, optionally smoke-tests a clone, and converts the VM into a Proxmox template.

It does not provision real workload VMs, assign production IP addresses, run OpenTofu, run Ansible, configure applications, manage Kubernetes, or store secrets.

## Platform Project

This repository is the Proxmox template-building layer of a broader platform toolchain.

The repositories are split by responsibility so that template building, infrastructure provisioning, system configuration, Kubernetes bastion tooling, documentation, and shared helper tools can evolve independently.

| Repository | Purpose |
|---|---|
| [`platform-template-builder`](https://codeberg.org/rch/platform-template-builder) | Builds reusable Proxmox VM templates from cloud images. |
| [`platform-infra`](https://codeberg.org/rch/platform-infra) | Provisions platform infrastructure with OpenTofu. |
| [`platform-config`](https://codeberg.org/rch/platform-config) | Configures operating systems and services with Ansible. |
| [`platform-k8s-bastion`](https://codeberg.org/rch/platform-k8s-bastion) | Contains Kubernetes bastion tooling and operational helpers. |
| [`platform-docs`](https://codeberg.org/rch/platform-docs) | Contains architecture notes, runbooks, diagrams, and operational documentation. |
| [`platform-tools`](https://codeberg.org/rch/platform-tools) | Provides shared optional helper tools used by the platform repositories. |

Typical workflow:

```text
platform-template-builder
  -> platform-infra
  -> platform-config
  -> platform-k8s-bastion

platform-tools provides optional shared helper commands.
platform-docs documents the design and operations across all repositories.
```

## Install

Clone the repository and enter the project directory:

```bash
git clone https://codeberg.org/rch/platform-template-builder
cd platform-template-builder
make help
```

Supported `TEMPLATE` values:

- `rocky-9`
- `rocky-10.0`
- `rocky-10.1`
- `rocky-10.2`
- `debian-12`
- `ubuntu-24.04`

## Workflows

Use either the default local config workflow or a separate private config repository. The build behavior is the same; only the config location changes.

`make init-ssh` prints the SSH config block by default, but does not write it to `~/.ssh/config`. `make check-tools`, `make build`, and `make cleanup` use `SSH_CONFIG`, which defaults to `$(CONFIG_ROOT)/ssh/template-builder.env`, directly when that file exists. Add `SSH_WRITE_CONFIG=1` only when you also want the helper to append the `Host pve-template-builder` block to `~/.ssh/config`. Add `SSH_EMPTY_PASSPHRASE=1` only when you intentionally want an unencrypted local private key.

### Default Local Config

Use this flow for local experiments or a single workstation. Private `.env` files stay in this checkout and are ignored by Git.

```bash
git clone https://codeberg.org/rch/platform-template-builder
cd platform-template-builder

git clone https://codeberg.org/rch/platform-tools ../platform-tools
make -C ../platform-tools install

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

# strongly recommended before handing the template to platform-infra
make smoke-test TEMPLATE=rocky-10.1 \
  SMOKE_TEST_IPV4=<temporary-ip/cidr> \
  SMOKE_TEST_GATEWAY=<gateway-ip> \
  SMOKE_TEST_DNS=<dns-ip>
```

If password SSH login is not available, use the manual `/root/.ssh/authorized_keys` fallback in `SSH Bootstrap`.

### Separate Private Config Repo

Use this flow for real deployment configs. Keep real `.env` files in a sibling private repository and point Make at that config root.

Expected private layout:

```text
../platform-private/template-builder/
  rocky-10.1-cloud-base.env
  ssh/template-builder.env
```

Run from the public `platform-template-builder` checkout:

```bash
git clone https://codeberg.org/rch/platform-template-builder
cd platform-template-builder

git clone https://codeberg.org/rch/platform-tools ../platform-tools
make -C ../platform-tools install

# clone or place your private config repo as ../platform-private
# git clone <your-platform-private-url> ../platform-private

# ensure ../platform-private/template-builder exists with real values
make init-ssh CONFIG_ROOT=../platform-private/template-builder

# run the ssh-copy-id command printed by make init-ssh, for example:
ssh-copy-id -i ~/.ssh/platform-template-builder_ed25519.pub root@<proxmox-ip>
make init-ssh SSH_TEST=1 CONFIG_ROOT=../platform-private/template-builder

make check-tools TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder
make validate TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder
make build TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder

# choose a temporary IP that does not conflict with platform-infra VMs
make smoke-test TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder \
  SMOKE_TEST_IPV4=<temporary-ip/cidr> \
  SMOKE_TEST_GATEWAY=<gateway-ip> \
  SMOKE_TEST_DNS=<dns-ip>
```

If you do not want to install `platform-tools`, run the helper from a sibling checkout:

```bash
make init-ssh \
  PLATFORM_SSH_INIT=../platform-tools/bin/platform-ssh-init \
  CONFIG_ROOT=../platform-private/template-builder
```

## SSH Bootstrap

Template builds use SSH and `rsync` from this workstation to the Proxmox node. SSH access is required, but this repository does not require the key generator if you already manage keys yourself.

The optional `make init-ssh` helper uses the shared `platform-ssh-init` command from [`platform-tools`](https://codeberg.org/rch/platform-tools). Install `platform-tools` so `platform-ssh-init` is on `PATH`, or set `PLATFORM_SSH_INIT` to the tool path.

Install the shared tools repository when needed:

```bash
git clone https://codeberg.org/rch/platform-tools ../platform-tools
make -C ../platform-tools install
```

You can initialize a dedicated local SSH key and config snippet for template-building access:

```bash
cp configs/ssh/template-builder.env.example configs/ssh/template-builder.env
# edit configs/ssh/template-builder.env
make init-ssh
```

If `platform-ssh-init` is not installed, run with an explicit path:

```bash
make init-ssh PLATFORM_SSH_INIT=../platform-tools/bin/platform-ssh-init
```

The helper loads the configured SSH bootstrap file from `SSH_CONFIG`, which defaults to `$(CONFIG_ROOT)/ssh/template-builder.env`. It creates an ed25519 key at the configured `SSH_KEY_PATH` if it does not already exist, prints an SSH config block, and prints the `ssh-copy-id` command needed to install the public key on Proxmox. By default, `ssh-keygen` prompts for a key passphrase. It does not install keys on Proxmox, create users, create API tokens, or write to `~/.ssh/config` unless explicitly requested. Build automation reads this same file directly, so writing `~/.ssh/config` is optional.

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

To test access after installing the public key, and optionally append the generated host block to `~/.ssh/config`:

```bash
make init-ssh SSH_WRITE_CONFIG=1
make init-ssh SSH_TEST=1
ssh pve-template-builder 'hostname && qm list && pvesm status'
```

Set `PROXMOX_HOST="pve-template-builder"` in your private template config when using the generated alias.

## Requirements

Local machine:

- Bash
- Make
- SSH client with key access to the Proxmox node
- `platform-ssh-init` from `platform-tools` and `ssh-keygen` when using optional `make init-ssh`
- `ssh-keygen` and `timeout` when running smoke tests
- `rsync`
- standard Unix tools such as `awk`, `date`, `basename`, `mkdir`, and `tee`

Proxmox node:

- Bash
- SSH enabled
- user can run `qm` and `pvesm`
- `qm`, `pvesm`, `ip`, `ping`, `rsync`, `timeout`, and `curl` or `wget`
- `qemu-img` for guest image preparation
- `virt-customize` and `virt-sysprep` for the default `GUEST_PREP_MODE="full"`
- target disk storage, cloud-init storage, and bridge exist
- write access to `PROXMOX_REMOTE_DIR`

`virt-customize` and `virt-sysprep` are provided by `libguestfs-tools` on Proxmox/Debian. Installing that package may pull a sizable dependency set. Set `GUEST_PREP_MODE="safe"` only when you need copy-only preparation that does not require `libguestfs-tools`.

Guest image preparation defaults to `PREPARE_GUEST_IMAGE="true"` and `GUEST_PREP_MODE="full"`. Full mode copies the upstream image, installs/enables cloud-init, QEMU guest agent, SSH, NetworkManager, and serial console services, then removes stale cloud-init state, SSH host keys, network profiles, logs, and machine identity before import. Package installation customizes a shut-down image but still uses outbound libguestfs networking. Safe mode only copies the upstream image with `qemu-img` and does not mount or mutate the guest filesystem, so it is not the reusable-template path for image profiles that expect QEMU guest-agent support.

The Rocky 10.0, 10.1, and 10.2 profiles are exact-minor pinned. Full preparation
verifies the profile's `VERSION_ID`, installs packages only from its matching
BaseOS and AppStream repositories, persists the matching DNF `releasever`, and
verifies both values before replacing or importing a template. The profiles use
the guest-local Rocky 10 signing key to verify installed packages. Templates set
Proxmox `ciupgrade=0`, so first boot does not silently advance the reviewed guest
release before downstream configuration.

Rocky 10.0 and 10.1 use historical Vault repositories, which are unsupported and
do not receive current security fixes. Rocky 10.2 uses the active exact-minor
repositories and receives 10.2 errata without advancing to a later minor. Move
the 10.2 profile to Vault deliberately when Rocky retires its active 10.2 paths.
The Rocky 10.0 profile is retained specifically for testing controlled migration
and upgrade paths from the 10.0 baseline; it is not recommended for new or
long-lived deployments.

Template console mode defaults to `TEMPLATE_CONSOLE_MODE="vga-serial"`, which keeps a serial port attached but uses normal VGA/noVNC output for debugging. Set `TEMPLATE_CONSOLE_MODE="serial"` only after serial-only guest console behavior is proven for the image.

Rocky/RHEL 10 requires x86-64-v3 CPU features that Proxmox's generic default CPU may not expose. All Rocky 10 examples set `CPU_TYPE="host"`; use that value in private Rocky 10 configs unless you have deliberately selected another x86-64-v3-capable CPU model.

See `docs/proxmox-requirements.md` for detailed checks.

## Configuration

Template builds use private `.env` files copied from committed examples:

```bash
cp configs/rocky-9-cloud-base.env.example configs/rocky-9-cloud-base.env
```

Private `.env` files are ignored and must not be committed. Keep private configs, SSH keys, Proxmox tokens, downloaded images, and generated logs out of this public repository.

For real deployment use, keep private configs outside this public repository, for example in `platform-private`:

```text
../platform-private/template-builder/
  rocky-10.1-cloud-base.env
  ssh/template-builder.env
```

Use that private config root with:

```bash
make validate TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder
make check-tools TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder
make build TEMPLATE=rocky-10.1 CONFIG_ROOT=../platform-private/template-builder
```

You can also point at one explicit config file:

```bash
make build CONFIG=../platform-private/template-builder/rocky-10.1-cloud-base.env
```

SSH bootstrap uses a separate private config copied from `configs/ssh/template-builder.env.example` to `$(CONFIG_ROOT)/ssh/template-builder.env`.

The SSH bootstrap helper is optional. CI/CD or manually configured workstations only need the configured private key and SSH transport values to exist before running `make check-tools` or `make build`.

When using a private config root, the same root is used for SSH bootstrap:

```bash
make init-ssh CONFIG_ROOT=../platform-private/template-builder
```

For a variable-by-variable guide to filling in private template configs, see `docs/template-config-reference.md`.

Template configs reference committed image profiles under `configs/images/`:

```bash
IMAGE_PROFILE="configs/images/rocky-9.env"
```

Image profiles contain upstream image metadata such as `IMAGE_URL`, `IMAGE_NAME`, exactly one required checksum (`IMAGE_SHA256` or `IMAGE_SHA512`), `IMAGE_OS_FAMILY`, `IMAGE_EXPECTS_QEMU_AGENT`, `IMAGE_FILESYSTEM_LAYOUT`, and `CLOUDINIT_USER`. A profile may independently declare an expected guest version. Pinned DNF profiles must define the release, BaseOS and AppStream repositories, and guest-local signing key as one complete set, and the release must match the expected guest version. Template configs select an image profile but must not redefine profile-owned metadata. The filesystem layout value records the upstream image layout; the builder does not intentionally convert ext4, XFS, LVM, or other guest disk layouts.

## Usage

Use Make for normal local operation:

```bash
make check-tools TEMPLATE=rocky-9
make check-images
make validate TEMPLATE=rocky-9
make build TEMPLATE=rocky-9
make smoke-test TEMPLATE=rocky-9 \
  SMOKE_TEST_IPV4=<temporary-ip/cidr> \
  SMOKE_TEST_GATEWAY=<gateway-ip> \
  SMOKE_TEST_DNS=<dns-ip>
make cleanup-smoke-test TEMPLATE=rocky-9 SMOKE_TEST_VMID=9900
make cleanup TEMPLATE=rocky-9
```

`make check-images` checks every committed image URL from the local machine without downloading the image body. `make check-tools` checks local build and SSH transport tools first. If `configs/<TEMPLATE>-cloud-base.env` exists, it also checks the configured Proxmox host over SSH. When the selected image is cached remotely, `check-tools` verifies its committed checksum; otherwise, it checks the image URL from the Proxmox node. Smoke-test-only local tools such as `ssh-keygen` and `timeout` are checked by `make smoke-test` when that workflow starts.

Builds download, verify, and prepare the selected image before replacing an existing `TEMPLATE_VMID`, so image, package, or exact-version failures cannot trigger `FORCE_RECREATE` destruction first. A valid cached image remains usable when the upstream image URL is temporarily unavailable, but full preparation still needs access to its selected package repositories.

`make smoke-test` clones a temporary VM from the template, disables cloud-init package upgrades, injects cloud-init user/network/SSH data, waits for the QEMU guest agent, verifies the configured IP and SSH login, checks any profile-pinned exact guest version after cloud-init completes, checks guest services, tests graceful shutdown, and destroys the temporary VM by default. The default smoke-test VMID is `9900`; the script refuses to use it if it already exists unless `SMOKE_TEST_FORCE_RECREATE=true` is set. Remote preparation failures and QEMU guest-agent timeouts print Proxmox diagnostics and keep the failed VM automatically for noVNC/console debugging. `SMOKE_TEST_DNS` defaults to `SMOKE_TEST_GATEWAY` when omitted, but passing it explicitly is clearer.

When `SSH_CONFIG` points to an existing template-builder transport config,
`SMOKE_TEST_SSH_KEY` defaults to its `SSH_KEY_PATH`. The smoke test derives and
injects that key's public half into only the temporary clone; the private key is
not copied to Proxmox or baked into the source template. Set
`SMOKE_TEST_SSH_KEY` explicitly to use a separate guest-test key. An optional
`SMOKE_TEST_SSH_PUBLIC_KEY` must match the selected private key; otherwise, the
smoke test fails before creating a clone.

`make cleanup-smoke-test` destroys only `SMOKE_TEST_VMID`, force-stopping it first if needed so broken guests do not block cleanup on QEMU guest agent or ACPI shutdown. `make cleanup` destroys only `TEMPLATE_VMID` with the same destroy flow. Both require typing the target VMID unless `CLEANUP_ASSUME_YES=true` is set, and both use Proxmox purge cleanup plus unreferenced-disk cleanup when supported by the installed Proxmox version.

The generic Make targets resolve configs as:

```text
$(CONFIG_ROOT)/<TEMPLATE>-cloud-base.env
```

`CONFIG_ROOT` defaults to `configs`, so local example-based configs still resolve to `configs/<TEMPLATE>-cloud-base.env`.

You can override the config path explicitly:

```bash
make validate CONFIG=configs/rocky-9-cloud-base.env
```

Direct script usage is also available:

```bash
./scripts/check-tools.sh configs/rocky-9-cloud-base.env
./scripts/check-image-urls.sh
./scripts/validate-config.sh configs/rocky-9-cloud-base.env
./scripts/remote-run-template-build.sh configs/rocky-9-cloud-base.env
./scripts/smoke-test-template.sh configs/rocky-9-cloud-base.env
./scripts/cleanup-smoke-test-vm.sh configs/rocky-9-cloud-base.env
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
- `docs/template-config-reference.md`
- `docs/template-conventions.md`
- `docs/troubleshooting.md`
- `docs/roadmap.md`

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
