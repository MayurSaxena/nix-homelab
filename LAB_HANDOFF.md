# VM automation handoff — 14 September 2026

## Scope and guardrails

The user wants a stable, simple Packer → OpenTofu → Ansible process, **not a full lab
rollout yet**. Prefer local checks, deploy only necessary validation guests, clean up failed
builds and temporary guests. Keep this document current during work. Nothing has been
committed or pushed; pushing main can deploy the Nix fleet. Preserve the working tree and
user's encrypted `secrets/lab.yaml` edits. Never print passwords, keys, metadata or secret logs.

Keep stock Windows templates available. Tools are installed on running guests via Ansible
playbooks (`tools-ctf.yml`, `tools-flare.yml`), not baked into separate Packer templates.
Persistent workstations retain their disks and golden snapshots until explicitly
reverted/rebuilt. The eventual DC is periodically rebuilt; Kali, CTF and FLARE are
persistent, with disposable Windows/Linux guests available on demand.
Read `CLAUDE.md` for repo guardrails and `LAB.md` for operating details; validate against code.

## Live checkpoint — CTF validated, FLARE next

Proxmox `10.0.10.3`, node `proxmox`; storage `local-zfs`, ISO storage `local`.
VLAN 90: `10.0.90.0/24`, gateway `.1`, DHCP `.100–.199`, DNS `10.0.10.2`.

| VMID | Last observed identity | State / meaning |
|---|---|---|
| 109 | tpl-win11-pro | Stopped, verified stock Windows 11 template |
| 114 | tpl-ctf | **Stopped, validated CTF tool template** (built 14 Sep 2026, 24m19s) |
| 122 | tpl-ws2025 | Stopped Server template; previous successful build/clone tests |
| 201 | onion | Pre-existing stopped guest; untouched |

Refresh this inventory before acting: IDs have been reused. No persistent lab fleet was
deployed. The verification clone (ctf-check, VMID 115) was spawned, verified, and destroyed.

## CTF template — validated

**Build:** `just packer-build workstations ctf` completed in 24 minutes 19 seconds, producing
template 114. Ansible ran 22 ok, 11 changed, 0 failed. Template conversion succeeded.

**Three fixes validated in this build:**

1. **Nmap 7-Zip extraction** — the Chocolatey package starts AutoHotkey to drive a GUI
   (hangs headless), and the upstream NSIS installer stalls in Session 0 regardless of
   execution context. The fix extracts the NSIS package as an archive using 7-Zip. Verified:
   `nmap --version` returns `7.991` compiled with `Npcap-1.89`.

2. **Npcap automated console install via QEMU sendkey** — the free Npcap license requires an
   interactive GUI installer (`/S` is OEM-only). Automation sends keystrokes to the VM
   console via `qm sendkey <vmid> <key>`: wake display → Ctrl+Alt+Del → type password →
   Enter to log in → Win+R → type installer path → navigate wizard (Tab Tab Enter for
   "I Agree" → Tab Enter for "Install" → wait 30s → Enter for "Finish"). No human
   interaction required. The `wait-tool-image.ps1` script detected the npcap driver and
   continued automatically.

   **Implementation note:** the automation script (`npcap-auto-install.sh` in the scratchpad)
   had a backslash character-mapping bug in `type_string()` — the bash `case` pattern
   `'\\'` in single quotes matches two backslashes, not one, so `C:\Windows\Temp\...`
   had its backslashes silently dropped. The working approach sent individual
   `qm sendkey <vmid> backslash` commands for path separators. A future integration into the
   build pipeline should fix the script's `type_string()` or use individual sendkey calls.

3. **Sysprep Appx cleanup** — Chocolatey's `notepadplusplus` installs an MSIX bridge package
   that is per-user, not provisioned for all users. Sysprep rejects this. The fix in
   `sysprep.ps1` removes all per-user Appx packages not in the provisioned set before
   running Sysprep. Verified: "Removed per-user-only Appx packages that would block Sysprep."
   appeared in output, followed by successful generalization
   (`IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE`).

**Clone verification (ctf-check, VMID 115 — destroyed):**

All checks passed via QEMU Guest Agent exec and SSH:

- Password-only SSH: working (hostname=ctf-check, whoami=ctf-check\administrator)
- All Chocolatey packages present (33 packages including dependencies)
- Nmap 7.991 functional, compiled with Npcap-1.89
- Npcap service: Running, StartType=System
- Dumpcap: 5 interfaces enumerated (Ethernet, Npcap Loopback, etc.)
- Image manifest: complete JSON at `C:\ProgramData\Lab\image.json`

**Cloudbase-init behavior notes:**

- `CreateUserPlugin` logs "This user can't sign in because this account is currently
  disabled" — this is because Sysprep disables Administrator during generalization, and
  cloudbase-init's CreateUserPlugin runs before the specialize Unattend.xml re-enables it.
  **Cosmetic; password is still set correctly** by `SetUserPasswordPlugin`, which reads from
  configdrive2 `admin_pass` metadata.
- `UserDataPlugin` logs "unsupported" for `password`, `ssh_authorized_keys`, and `chpasswd`
  in cloud-config YAML — these are handled by separate dedicated plugins
  (`SetUserPasswordPlugin`, etc.) that read from configdrive2 metadata, not cloud-config.
  **Expected behavior, not errors.**

## Verified progress (cumulative)

- Full Windows 11 ISO build using the latest encryption/account fixes succeeded (21m35s),
  producing template 109. Its generated ISO was removed by Packer.
- Fresh `base-check` clone reached `IMAGE_STATE_COMPLETE`, remained `FullyDecrypted`,
  applied its hostname, used DHCP, and accepted password-only SSH. The test clone and
  superseded template 124 were deleted.
- `just lab-check` passed all regression tests, shell/Packer syntax and formatting,
  OpenTofu validation, and Ansible syntax checks for both playbooks.
- Packer's clone builder connected over DHCP and invoked Ansible after fixing IPv4 discovery
  and adding the missing API permission.
- CTF tool template built, captured, and clone-verified end-to-end (see above).
- Earlier live tests proved disposable spawn/despawn and a regular Windows snapshot rollback.

## Current implementation

**Architecture simplified:** the Packer workstation builder (`packer/workstations/`) and
`tool-image.yml` have been removed. Only base OS templates are built by Packer (under
`packer/windows/`). Tools are installed on running guests via separate Ansible playbooks:

- `tools-ctf.yml` — CTF tools (Chocolatey packages, Nmap extraction, Npcap staging)
- `tools-flare.yml` — FLARE-VM (Defender disable, async installer, monitor via RDP)

`provisioning/vms.tf` clones `ctf01` and `flare01` from the base `tpl-win11-pro` template.
Clone-source changes are ignored for existing persistent guests; adoption requires explicit
rebuild.

Two Packer discovery fixes are in code and were exercised:

1. With Proxmox plugin 1.2.4, setting `vm_interface` selects the first address even if IPv6.
   Leaving it unset selects IPv4. Direct key SSH worked when discovery was failing.
2. The token returned 403 for guest-agent network queries. `VM.GuestAgent.Audit` was added
   to `PackerBuild` in `provisioning/rbac.tf` and applied with a reviewed role-only plan.

**Npcap:** the free interactive installer is automated via QEMU sendkey during the Packer
build. The role stages checksum-pinned Npcap 1.89 as `C:\Windows\Temp\npcap-setup.exe` and
sets Administrator's console password from SOPS. Automation sends keystrokes to navigate the
wizard. Capture requires a running Npcap driver and no remaining installer process. Stock
Windows images do not get Npcap.

## FLARE status — implementation only

No FLARE installation has been run or tested. The `tools-flare.yml` playbook uses
pinned/checksummed official installer and config revision
`4f8769522bda53ab53da2de85def532efaa033ee`; package versions still follow upstream feeds.
It checks Tamper Protection, applies Defender policy and reboots, then requires Defender
stopped. The observed stock clone had TamperProtection=1 and Defender running; the policy
transition has not been tested.

Upstream `-noGui` still calls `Read-Host`, including a snapshot prompt. The role validates
prerequisites then supplies `-noChecks -noGui -noWait`; it fires the installer async and
drops the SSH connection. Boxstarter owns reboots. Monitor progress via RDP; check
`C:\ProgramData\_VM\failed_packages.txt` when finished. Reboot survival, package success,
credential cleanup, GUI/Npcap needs, and disk capacity remain unproven.

## Earlier DC evidence and remaining operating gaps

Claude renamed the forest to `ad.lab.internal`, NetBIOS `ADLAB`. Fresh DC deployment,
promotion, readiness and configuration passed; a second Ansible run changed zero tasks.
Password-only SSH as `ad.lab.internal\Administrator`, `dcdiag /test:Advertising`, SYSVOL and
`nltest /dsgetdc` passed. RDP was checked only at transport level (port/TLS/certificate), not
as a GUI login. The test DC was destroyed. The previous lab-kali01 was also destroyed;
`module.kali01` now describes `.50` from the Kali cloud-image template, without deployed state.

The DC role waits for AD services, sets self-DNS, checks SYSVOL, conditionally restarts DFSR
and Netlogon/registers DNS, then gates on Advertising. **The recovery branch has not been
exercised live.** A post-reboot Ansible task cannot repair a condition that prevents SSH from
reconnecting. Do not describe the original startup race as conclusively resolved.

Technitium is intended to own `lab.internal` and conditionally forward `ad.lab.internal`
to the DC. Those runtime zones/records/forwarding still need configuration and verification.
Kali fresh deployment, Linux disposable validation, full GUI RDP, backup/restore, DC evaluation
tracking, forest rebuild/member rejoin and VM Generation ID behavior on rollback remain.
AD weakness toggles and GPO seeding are proposals, not implemented.

## Next actions, in order

1. Test the FLARE playbook on a running guest and validate the full workflow.
2. Finish remaining DNS/DC/Kali/rollback operating checks when needed for the next claim.

## Commands and safeguards

```bash
nix develop
just lab-check
just packer-build windows win11-pro
just packer-build windows ws2025
# Spawn guests from base templates:
just lab-spawn tpl-win11-pro test01
just lab-spawn tpl-ws2025 server-test
just lab-despawn test01
just lab-despawn server-test
# Install tools on running guests:
just lab-play tools-ctf.yml -e targets=ctf01
just lab-play tools-flare.yml -e targets=flare01
```

Use scoped, reviewed plans for persistent validation guests; delete saved plans afterward
because they contain sensitive data. The lifecycle helper deletes only owned ad-hoc guests.
Never use historical IDs without checking identity/tags. Keep the Server/stock Windows
bases and pre-existing guests. No commits/pushes unless asked.

**Retirement caveat:** `just packer-build` checks deletion responses and waits for tasks,
but retires a previous matching template after Packer succeeds, before a fresh-clone test.
Preserve a known-good predecessor until replacement validation when rebuilding an existing
image. Only ISO builds use fixed `.99`.

**Node SSH workaround:** the Mac's `~/.ssh/id_ed25519` symlink currently points to a missing
decrypted SOPS file, and hardware-key signing failed. Access worked by extracting
`["ssh-keys"]["mbp-ed25519"]` from `secrets/msaxena.yaml` into a chmod-600 temporary file,
using `ssh -i FILE -o IdentitiesOnly=yes -o BatchMode=yes -o ControlPath=none root@10.0.10.3`,
and deleting the key with an EXIT trap. Do not reconfigure the Mac for this task.
QGA diagnostics and console screenshots are available through that connection. Pace and
acknowledge console key events; piping them faster than SSH connects lost password characters.
Temporary `/tmp/lab-*` wrappers are conveniences, not part of the supported workflow.
