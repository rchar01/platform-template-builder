# platform-infra Handoff

This handoff is for the OpenTofu coding agent working in `platform-infra` after a template has been built and smoke-tested here.

This repository stops at reusable Proxmox templates. Do not add OpenTofu resources, workload VM definitions, production IP addresses, Ansible inventory, application configuration, or secrets here.

## Template Contract

Available Rocky 10 exact-minor build profiles:

| Template | Example VMID | Runtime status |
|---|---:|---|
| `rocky-10.0-cloud-base` | 9004 | Migration-test profile; real Proxmox smoke test pending. |
| `rocky-10.1-cloud-base` | 9003 | Validated handoff contract. |
| `rocky-10.2-cloud-base` | 9005 | Available profile; real Proxmox smoke test pending. |

Rocky 10.1 remains the required validated Proxmox cloud-init template contract:

```text
Template name: rocky-10.1-cloud-base
Template VMID in the current example/private config: 9003
Cloud-init user: rocky
Proxmox cloud-init type: nocloud
CPU model: host
Machine type: q35
BIOS type: seabios
Disk bus: scsi
SCSI controller: virtio-scsi-pci
Console: vga std plus serial0 socket
QEMU guest agent: enabled
Cloud-init package upgrades: disabled (`ciupgrade=0`)
Expected guest VERSION_ID: 10.1
Persistent DNF releasever: 10.1
```

The latest real smoke test confirmed the base template mechanics:

- clone from template succeeds
- static cloud-init networking is applied
- SSH login as `rocky` works
- cloud-init reaches completed status without top-level errors
- `sshd` is active
- QEMU guest agent responds and reports the guest IP
- Proxmox graceful shutdown succeeds
- temporary smoke-test VM cleanup succeeds

Exact-version profiles add a stricter current handoff gate: the profile's
`IMAGE_EXPECTED_VERSION_ID` must pass during image preparation and in a fresh
smoke-test clone, and any persistent package-manager release pin must match it.
Do not infer the running clone version from the template name alone.

Template VMID 9003 was rebuilt on 2026-08-12. A fresh smoke-test clone confirmed
`VERSION_ID=10.1` and persistent DNF `releasever=10.1` after cloud-init,
responsive SSH and QEMU guest agent services, the configured address, graceful
shutdown, and successful temporary-VM cleanup.

Before coding against a template in `platform-infra`, verify the current template name and VMID in the private template-builder config or with `qm config <template-vmid>` on Proxmox. Re-run the current smoke test after rebuilding an exact-version profile. Do not treat Rocky 10.0 or 10.2 as validated handoff contracts until their own fresh clones pass the complete smoke test. Treat example VMIDs as local conventions, not as values to hard-code in reusable modules.

Rocky 10.0 is retained to test controlled migration and upgrade paths from an
archived baseline. Do not select it as the default for new or long-lived
workloads; use its clones only in an explicitly scoped migration test.

## OpenTofu Responsibilities

In `platform-infra`, clone workload VMs from the template instead of rebuilding images.

The OpenTofu configuration should provide environment-specific values only in the downstream private/infrastructure layer:

- VM name and VMID
- target Proxmox node
- CPU core count and memory size
- disk size if the workload needs more than the template base disk
- bridge and network model
- unique workload IP address, CIDR, gateway, DNS, and search domain
- SSH public keys for the cloud-init user
- tags, descriptions, and lifecycle settings used by the infra repository

`platform-template-builder` owns only generic base-template hardware defaults. Workload-specific disk and controller tuning, including disk size, cache mode, discard/TRIM, iothreads, storage performance choices, backup policy, and replication settings, belongs in `platform-infra` or private downstream configuration.

Keep application setup, package installation, service configuration, Kubernetes setup, and secrets out of OpenTofu. Those belong in `platform-config`, `platform-k8s-bastion`, or a private secrets mechanism.

## Rocky/RHEL 10 Requirements

Rocky Linux 10 requires x86-64-v3 CPU features. All Rocky 10 template examples use `CPU_TYPE="host"`.

When cloning the template, do not override the CPU model back to Proxmox's generic default. Either inherit the template CPU configuration or explicitly set a compatible CPU model, normally `host` for Rocky/RHEL 10 templates.

If a cloned Rocky/RHEL 10 VM reaches GRUB or early boot but never starts SSH or QEMU guest agent, check the clone config first:

```bash
qm config <vmid> | grep -E '^(cpu|machine|bios|agent|serial0|vga):'
```

The clone should keep `cpu: host`, `machine: q35`, `agent: enabled=1`, `serial0: socket`, and `vga: std` unless there is a deliberate workload-specific reason to change them.

## Cloud-Init Contract

The template is cloud-init ready, but workload identity and network data must come from `platform-infra`.

Set cloud-init data for each cloned VM:

- `ciuser` should be `rocky` for Rocky templates unless the template/image profile changes.
- SSH public keys should be supplied through Proxmox cloud-init, not baked into the template.
- Networking should use a real workload IP or DHCP plan owned by `platform-infra`; never reuse smoke-test addresses.
- DNS and search domain should match the target environment.
- Keep `citype: nocloud` unless the template family changes and has been revalidated.
- Keep automatic cloud-init package upgrades disabled; package lifecycle belongs
  in the explicitly reviewed downstream configuration workflow.

Do not assume any smoke-test address is available for workloads. Smoke-test addresses are temporary validation inputs and should stay separate from workload IP allocation.

## Guest Agent And Readiness

Enable and use QEMU guest agent for readiness where the OpenTofu provider supports it. The template has QGA enabled and the smoke test verified it.

Recommended readiness sequence for downstream automation:

1. Clone VM from the template.
2. Apply cloud-init user, SSH key, and networking data.
3. Start the VM.
4. Wait for the configured IP to become reachable.
5. Wait for SSH as the cloud-init user.
6. Wait for QEMU guest agent to respond and report the expected IP.
7. Hand the VM to `platform-config` for OS and service configuration.

Rocky/RHEL 10 cloud-init may report `degraded done` when Proxmox-generated user data triggers recoverable deprecation warnings. Treat this as acceptable only when cloud-init status is `done` and the top-level `errors` list is empty. Do not ignore real cloud-init errors.

## Boundary Reminders

The OpenTofu agent should not modify this repository to provision machines. If more template behavior is needed, request or implement it here as generic template-builder functionality first, then rebuild and smoke-test the template before using it downstream.

The OpenTofu agent should keep long-lived infrastructure values in `platform-infra` or the private config repository, not in committed examples here.
