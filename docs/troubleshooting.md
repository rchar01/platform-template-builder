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

Likely cause: Wrong bridge, missing cloud-init network configuration in the provisioning repository, or guest OS naming differences.

Check:

```bash
ssh pve-template-builder 'qm config 9000 | grep net0'
```

Fix: Verify the bridge on the template and apply clone-specific network config from infrastructure/cloud-init.

## Cloud-Init Does Not Apply

Symptom: Cloned VM ignores cloud-init user or network settings.

Likely cause: Cloud-init drive missing, cloned VM not configured with cloud-init values, or guest image issue.

Check:

```bash
ssh pve-template-builder 'qm config 9000 | grep ide2'
```

Fix: Ensure the template has `ide2: <storage>:cloudinit` and set clone-specific cloud-init values in the infrastructure repository.

## QEMU Guest Agent Not Available Inside Guest

Symptom: Proxmox shows guest agent unavailable after cloning.

Likely cause: The template enables the Proxmox agent flag, but the guest image may not include or start the agent package.

Check:

```bash
ssh pve-template-builder 'qm config 9000 | grep agent'
```

Fix: Install and enable the guest agent later through the configuration repository if the image does not include it.
