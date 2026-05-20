# Troubleshooting

## SSH Fails

Symptom: `ssh pve-template-builder` fails or prompts for an unexpected password.

Likely cause: SSH config, hostname, user, or key is incorrect.

Check:

```bash
ssh -v pve-template-builder 'qm list'
```

Fix: Update your local SSH config and verify key-based access outside this project.

## `qm` Command Not Found

Symptom: Build fails with `Required command not found: qm`.

Likely cause: The build script is not running on a Proxmox node.

Check:

```bash
ssh pve-template-builder 'command -v qm && test -d /etc/pve'
```

Fix: Run builds through `make build TEMPLATE=rocky-9` so the remote Proxmox node executes the builder.

## Image Profile Not Found

Symptom: Validation fails with `Image profile not found`.

Likely cause: `IMAGE_PROFILE` points to a missing file or a path outside the synced `configs/images/` directory.

Check:

```bash
ls configs/images
grep IMAGE_PROFILE configs/rocky-9-cloud-base.env
```

Fix: Set `IMAGE_PROFILE` to one of the committed profiles, such as `configs/images/rocky-9.env`.

## Storage Does Not Exist

Symptom: Build fails with `Storage local-lvm does not exist`.

Likely cause: `DISK_STORAGE` or `CLOUDINIT_STORAGE` does not match the Proxmox storage name.

Check:

```bash
ssh pve-template-builder 'pvesm status'
```

Fix: Update the config with storage names from `pvesm status`.

## Bridge Does Not Exist

Symptom: Build fails with `Bridge vmbr0 does not exist`.

Likely cause: `BRIDGE` does not match a Proxmox network bridge.

Check:

```bash
ssh pve-template-builder 'ip link show type bridge'
```

Fix: Update `BRIDGE` in the config.

## VMID Already Exists

Symptom: Build refuses to continue because the VMID already exists.

Likely cause: The VMID is already assigned to a VM or template.

Check:

```bash
ssh pve-template-builder 'qm status 9000 || true; qm config 9000'
```

Fix: Use a different `TEMPLATE_VMID`, or set `FORCE_RECREATE=true` only after verifying the existing VMID can be destroyed.

## Cloud Image Download Fails

Symptom: `curl` or `wget` exits non-zero.

Likely cause: The Proxmox node cannot reach the image URL, DNS is unavailable, or the URL changed.

Check:

```bash
ssh pve-template-builder 'curl -I https://download.rockylinux.org/'
```

Fix: Restore network access, update `IMAGE_URL`, or pre-cache the image under `.cache/images/` on the remote build directory.

## Disk Import Succeeds But Attach Fails

Symptom: `qm importdisk` succeeds, but the script cannot find an imported unused disk.

Likely cause: Proxmox produced an unexpected disk reference or import did not update VM config.

Check:

```bash
ssh pve-template-builder 'qm config 9000'
```

Fix: Inspect the `unusedX` disk entry and attach it manually if needed, then update the script based on the observed output.

## Template Has No Network After Cloning

Symptom: Cloned VM boots without network access.

Likely cause: Wrong bridge, missing clone cloud-init network configuration, failed guest image preparation, cloud-init network disabled in the guest, or stale guest network profiles.

Check:

```bash
ssh pve-template-builder 'qm config 9000 | grep net0'
ssh pve-template-builder 'qm config 9000 | grep citype'
make smoke-test TEMPLATE=rocky-9 \
  SMOKE_TEST_IPV4=<temporary-ip/cidr> \
  SMOKE_TEST_GATEWAY=<gateway-ip> \
  SMOKE_TEST_DNS=<dns-ip> \
  SMOKE_TEST_SSH_KEY=~/.ssh/<cloud-init-test-key>
```

Fix: Verify the bridge on the template, rebuild with `PREPARE_GUEST_IMAGE=true`, and use smoke-test output to confirm Proxmox cloud-init static networking before handing the template to `platform-infra`.

## Cloud-Init Does Not Apply

Symptom: Cloned VM ignores cloud-init user or network settings.

Likely cause: Cloud-init drive missing, cloned VM not configured with cloud-init values, or guest image issue.

Check:

```bash
ssh pve-template-builder 'qm config 9000 | grep ide2'
ssh pve-template-builder 'qm config 9000 | grep citype'
```

Fix: Ensure the template has `ide2: <storage>:cloudinit` and `citype: nocloud`, then rebuild so guest preparation installs/enables cloud-init and removes `/var/lib/cloud` state. Set clone-specific cloud-init values in the infrastructure repository.

## QEMU Guest Agent Not Available Inside Guest

Symptom: Proxmox shows guest agent unavailable after cloning.

Likely cause: The template enables the Proxmox agent flag, but the guest image was not prepared, or the in-guest `qemu-guest-agent.service` failed to start.

Check:

```bash
ssh pve-template-builder 'qm config 9000 | grep agent'
make smoke-test TEMPLATE=rocky-9 \
  SMOKE_TEST_IPV4=<temporary-ip/cidr> \
  SMOKE_TEST_GATEWAY=<gateway-ip> \
  SMOKE_TEST_DNS=<dns-ip> \
  SMOKE_TEST_SSH_KEY=~/.ssh/<cloud-init-test-key>
```

Fix: Rebuild the template with guest preparation enabled. The builder installs and enables `qemu-guest-agent` before template conversion, and the smoke test fails if `qm agent <vmid> ping` does not respond.

## Console Has No Login Prompt

Symptom: Proxmox serial console or noVNC opens but no useful boot output or login prompt appears.

Likely cause: The guest did not boot, the guest did not enable `serial-getty@ttyS0`, kernel console output is not configured, or the VM display is set to serial-only without guest support.

Check:

```bash
ssh pve-template-builder 'qm config 9000 | grep -E "^(serial0|vga):"'
```

Fix: Rebuild the template with `TEMPLATE_CONSOLE_MODE="vga-serial"`. The builder keeps `serial0: socket` and uses `vga: std` for noVNC debugging. If the guest still fails before login, temporarily switch to `GUEST_PREP_MODE="safe"` to isolate offline guest filesystem mutation from console issues.

## Guest Kernel Panics Killing Init

Symptom: noVNC shows `Kernel panic - not syncing: Attempted to kill init` during early boot.

Likely cause: Guest image preparation left the clone with broken machine identity, init/systemd state, or SELinux labels.

Check:

```bash
ssh pve-template-builder 'qm config 9000'
ssh pve-template-builder 'qm config 9900'
```

Fix: For Rocky/RHEL 10, rebuild the template with `CPU_TYPE="host"` or another x86-64-v3-capable CPU model; Proxmox's generic default CPU can be too old for early userspace. If the CPU is already compatible and the panic persists, temporarily rebuild with `GUEST_PREP_MODE="safe"` to isolate offline package installation, sysprep, machine-id rewrites, SELinux relabeling, and other guest filesystem mutation.

## Rocky 10 Stops Before SSH Or QEMU Guest Agent

Symptom: Rocky 10 reaches GRUB or early kernel output, but SSH and QEMU guest agent never start.

Likely cause: The VM is using Proxmox's default generic CPU model, which may not expose the CPU features required by Rocky/RHEL 10 userspace.

Check:

```bash
ssh pve-template-builder 'qm config 9003 | grep -E "^(cpu|machine|bios):"'
ssh pve-template-builder 'qm config 9900 | grep -E "^(cpu|machine|bios):"'
```

Fix: Set `CPU_TYPE="host"` in the Rocky 10.1 template config, rebuild the template, and rerun the smoke test.

## Smoke Test Times Out During Cloud-Init Status

Symptom: `make smoke-test` reaches SSH, then fails while checking cloud-init and guest services, sometimes with exit code `124`.

Likely cause: On Rocky/RHEL 10 images, unprivileged `cloud-init status` may fail reading runtime state, and `cloud-init status --wait` may exit `2` when cloud-init completed with only recoverable deprecation warnings from Proxmox-generated user data.

Fix: Use the current smoke-test script. It runs the cloud-init status check as root when already root, or through `sudo -n` when testing as a non-root user with sudo available. It accepts exit code `2` only when JSON status is `done` and top-level `errors` is empty. If the script still fails here, inspect the kept VM with `sudo cloud-init status --long` and `/var/log/cloud-init.log`.

## Smoke Test Times Out Waiting For QEMU Guest Agent

Symptom: `make smoke-test` starts the clone, then fails with `Timed out waiting for qm agent <vmid> ping`.

Likely cause: The guest did not boot, QEMU guest agent failed to start, or first boot is slower than the smoke-test timeout.

Check:

```bash
ssh pve-template-builder 'qm config 9900'
ssh pve-template-builder 'qm status 9900'
ssh pve-template-builder 'qm agent 9900 ping'
```

Fix: The smoke test keeps QGA-timeout VMs automatically. Open noVNC for the kept VM, inspect boot output, and rerun with `SMOKE_TEST_BOOT_TIMEOUT_SECONDS=900` or higher only if the guest is booting normally but slowly.

## Smoke-Test VMID Already Exists

Symptom: `make smoke-test` refuses to continue because VMID `9900` already exists.

Likely cause: The default smoke-test VMID is already assigned.

Check:

```bash
ssh pve-template-builder 'qm status 9900 || true; qm config 9900'
```

Fix: Use a different temporary VMID with `SMOKE_TEST_VMID=<free-vmid>`, or set `SMOKE_TEST_FORCE_RECREATE=true` only after verifying the existing VMID can be destroyed.

To remove a kept smoke-test VM directly:

```bash
make cleanup-smoke-test TEMPLATE=rocky-9 SMOKE_TEST_VMID=9900
```

For repeated local debugging after checking the VMID:

```bash
CLEANUP_ASSUME_YES=true make cleanup-smoke-test TEMPLATE=rocky-9 SMOKE_TEST_VMID=9900
```

Cleanup force-stops the smoke-test VM before destroying it, so it still works when the guest is kernel-panicked or QEMU guest agent is unavailable.
