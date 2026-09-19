# The lab (VLAN 90)

The intended lab on `10.0.90.0/24` combines an Active Directory range (`ad.lab.internal`)
with persistent research workstations and disposable Windows/Linux test guests. The full
range has not been deployed; see the validation log at the end of this document for what
currently exists.

Unlike the NixOS hosts, none of this is configured by the flake. The pipeline is Packer for
golden images, OpenTofu for cloning them into guests, and Ansible for configuring
guest-specific roles and installing tooling. Read `CLAUDE.md` for how that sits beside the
LXC pipeline; this file covers the lab's own decisions.

Two standards apply, and they pull in different directions on purpose:

- **The AD range should be reproducible.** Forest, DNS and OU creation exist in the
  playbook. GPO/weakness seeding is future work, and unattended DC rebuild reliability
  has passed fresh deployments; the recovery branch for a missing SYSVOL still needs a live test.
- **Everything else works out of the box, or close to it.** A CTF box or a research VM should
  boot, get an address and be usable. If a machine needs a bespoke build to be useful, that is
  a reason to question the machine, not to write more automation.

## End-to-end workflow

Three layers, each built on the previous one:

**Layer 1 — Base OS templates (Packer).** The slow, expensive step (~20 min). Builds a
Windows template from an ISO. The result is a stopped Proxmox VM, generalized via Sysprep,
ready to clone. Linux images are downloaded, not built.

```bash
just packer-build windows win11-pro    # build from ISO (~20 min)
just packer-build windows ws2025       # Server 2025
just lab-image kali                    # downloads cloud image, no Packer needed
```

The template contains: Windows installed, OpenSSH configured, QEMU guest agent + VirtIO
drivers, Ansible SSH public key, cloudbase-init ready to apply per-VM hostname/password/address
on first boot. The adapter is left on DHCP.

**Layer 2 — Guest deployment (OpenTofu).** Clones a template into a named VM with a static
IP, hostname, and the lab password via cloud-init. Persistent guests (`dc01`, `kali01`,
`ctf01`, `flare01`) are declared in `provisioning/vms.tf`. Throwaway guests use `lab-spawn`
and skip OpenTofu.

```bash
just apply -target=module.ctf01        # deploy a declared persistent guest
just lab-spawn tpl-win11-pro test01    # throwaway clone, DHCP, no HCL needed
just lab-despawn test01                # destroy a throwaway
```

**Layer 3 — Configuration (Ansible).** Configures the running guest over SSH. `site.yml`
handles baselines (RDP, firewall, etc.). Separate playbooks install tooling or join the
domain.

```bash
just lab-play site.yml --limit ctf01              # baseline a guest
just lab-play tools-ctf.yml -e targets=ctf01      # install CTF tools
just lab-play tools-flare.yml -e targets=flare01  # install FLARE-VM
just lab-play join.yml -e targets=ctf01            # join to domain (optional)
```

**Lifecycle after setup.** Snapshot, work, revert:

```bash
just lab-snapshot ctf01                # take/replace the golden snapshot
just lab-revert ctf01                  # rewind to golden
just lab-rebuild ctf01                 # nuke and pave from template + re-ansible
```

**Full "new CTF workstation" sequence:**

1. `just packer-build windows win11-pro` (skip if template exists)
2. `just apply -target=module.ctf01`
3. Wait for SSH: `just lab-play site.yml --limit ctf01`
4. `just lab-play tools-ctf.yml -e targets=ctf01`
5. RDP in, run the staged Npcap installer (free license requires GUI)
6. `just lab-snapshot ctf01`

After that, `just lab-revert ctf01` restores to step 6 in seconds.

## Addressing and DNS

VLAN 90 is `10.0.90.0/24`, gateway `10.0.90.1`, with **technitium serving DHCP from `.100`
to `.199`** (its `VLAN90` scope) and handing out the `lab.internal` search suffix, so a
disposable guest comes up resolvable by name with nothing configured on it.

| Block | Use | Assigned by |
|---|---|---|
| `.10`&ndash;`.19` | Servers. `dc01` is `.10`. | OpenTofu, static |
| `.20`&ndash;`.39` | Domain-joined workstations. | OpenTofu, static |
| `.50`&ndash;`.59` | Pets. `kali01` is `.50`, `ctf01` `.51`, `flare01` `.52`. | OpenTofu, static |
| `.99` | Packer builds, and nothing else. | The unattend, static |
| `.100`&ndash;`.199` | Everything disposable: ad-hoc test hosts, live ISOs. | technitium DHCP |

**Static only where it earns it.** A machine takes a static address if something must find it
at a known place: the domain controller, anything domain-joined (which also needs the DC as
its resolver), the persistent workstations in the address table, and the Packer build.
Disposable guests use DHCP. The `qemu-vm` module accepts
`ipv4_settings = "dhcp"` for exactly this, so it is a choice per guest rather than a policy.

**DHCP hands out technitium, not the domain controller**, and that is deliberate in both
directions. Pointing it at the DC would make every CTF box depend on the DC being up to
resolve anything at all. Pointing it at the DC *with technitium as a secondary* is worse
still: a Windows domain member that queries a non-AD resolver gets NXDOMAIN for the SRV
records it needs and then fails intermittently, in ways that look like AD is broken.
Microsoft's guidance is that domain members resolve only against AD DNS, and the way to
honour that here is to give them their resolver statically rather than through DHCP.

**DNS is split into two zones by design:**

- **`lab.internal`** is owned by Technitium with static A records for every VLAN 90 host.
  This zone is always available regardless of DC state, so non-domain hosts (Kali,
  disposable guests) and the Mac can always resolve lab hosts by name.
- **`ad.lab.internal`** is the Active Directory forest domain, served by the DC's own DNS.
  Technitium conditionally forwards this subdomain to the DC (`10.0.90.10`). AD services
  (SRV records, Kerberos, LDAP) live here and are only available when the DC is up.

Domain members point their DNS at the DC. The DC forwards non-forest queries to Technitium,
so domain members can still resolve `lab.internal` names and the internet. Non-domain hosts
point at Technitium directly and never depend on the DC for name resolution.

The Technitium zone and conditional forwarder are runtime configuration in Technitium's web
UI, not declared in the repository. Keeping the lab on one VLAN allows direct traffic
between exercise targets and attack stations.

`.99` exists because a Packer build has no OpenTofu behind it. It is deliberately outside
every other block, so two concurrent builds collide with each other, which is obvious, rather
than with a range VM, which would not be. It also sits just below the DHCP pool, so it can
never be handed to anything else.

The address is build-only, but only because the build explicitly gives it back. `sysprep.ps1`
generalises Windows while SSH is still available, checks the result, then starts a SYSTEM
scheduled task that resets the adapter to DHCP and shuts down. Packer waits for shutdown
through the Proxmox API before converting the VM to a template. Resetting the address inside
the SSH provisioner breaks its own transport and can abort the build before capture.

## Media

Three ISOs are needed. Two are declared in `provisioning/images.tf` and arrive with
`tofu apply`. **One must be uploaded by hand, once**, and that split is forced by Microsoft
rather than by this repo:

| ISO | How it arrives |
|---|---|
| Windows Server 2025 evaluation | `tofu apply` (stable `go.microsoft.com/fwlink` redirect) |
| virtio-win drivers | `tofu apply` (pinned Fedora archive URL) |
| Windows 11 Pro | manual, see below |

Microsoft's Evaluation Center and the consumer download page both mint a **signed CDN URL
that expires roughly 24 hours after the page generates it**, and regenerate it per visit. A
URL committed here would fail the next day, at apply time, on a machine that worked
yesterday. So do not add one.

To upload it by hand, from the Proxmox web UI: *Datacenter → proxmox → local → ISO Images →
Upload*. The file name matters, because `provisioning/vms.tf` refers to it:

- `windows-11-pro.iso` from the [consumer download page][consumer]

[consumer]: https://www.microsoft.com/software-download/windows11
[eval]: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise

## When to build an image, and when not to

**Packer is the expensive option. Reach for it only when there is no image to download.**

Windows is that case, and essentially the only one: Microsoft ships no cloud image, so a
usable Windows guest has to be built. That build is why `packer/` exists.

Most Linux distributions publish a cloud image that already carries cloud-init, which is the
bulk of what a Packer build would add. For those there is no build step at all: `proxmox_download_file` with `content_type = "import"`
fetches the qcow2, a `disk { import_from = ... }` builds the guest straight from it, and
Ansible does the rest. Less to write than a Packer template, and nothing to maintain.

**The guest agent is the one thing not to assume.** Kali's genericcloud image ships without
`qemu-guest-agent`, so Proxmox attaches the virtio port and nothing answers on it: the guest
reports no address in the summary and takes the full timeout on every shutdown. The
`linux_baseline` Ansible role installs it. It is deliberately not done through cloud-init's
`packages:`, because that needs a custom user-data snippet and Proxmox's `cicustom`
*replaces* the user-data it generates rather than adding to it -- taking the administrator
password and the SSH keys with it. One package is not worth re-implementing cloud-init's
user handling.

**Check that the distribution you want actually publishes an image at all; do not assume.**
Kali does.
**Parrot does not** -- as of 7.3 its download directory carries live ISOs and desktop
appliances (ova, qcow2, vmdk, libvirt box) and no cloud image, and the appliance qcow2 is
zipped, which `decompression_algorithm` cannot handle (it takes gz, lzo, zst and bz2). Its
ISOs install through Calamares rather than the Debian installer, so there is no preseed
either. A distribution in that position needs a deliberate decision rather than a template:
see the note in the Parrot section below.

Build a Linux template only when something must exist *before first boot* that cloud-init
cannot do at boot time. That is rare. A slow package install is not a reason on its own;
a snapshot after first configuration gets you the same speed without a second pipeline.

The `qemu-vm` module does not care which kind of thing it is cloning, so this is a decision
per image rather than an architectural fork. It does care whether the guest can read a
cloud-init drive: `enable_cloud_init = false` stops it attaching one, for an image that has
no cloud-init agent at all. Attaching a drive such a guest ignores would leave OpenTofu
declaring an address nothing reads, with a clean plan and a wrong answer.

### Other images and Windows editions

Kali is the selected Linux attack station in `provisioning/vms.tf`; it uses a downloaded
cloud image and an OpenTofu-managed template. Parrot VM 200 predates this work and was left
untouched. Recheck current vendor media before adding another distribution. `lab-spawn`
requires an existing cloud-init-capable template, and arbitrary Linux templates need the
correct image username. A live ISO/appliance without cloud-init needs a separate bootstrap
path; the existing helper does not automate its installation.

The Windows Packer catalog currently supports `ws2025` (Server 2025 Standard Evaluation,
Desktop Experience) and `win11-pro`. Both persistent Windows workstations use the Pro
base. Adding a catalog key also requires updating the explicit `target` validation list;
it is not only an ISO filename change.

Do not infer licensing entitlement or unlimited evaluation renewal from successful builds.
The previous claim that every clone gets a fresh full evaluation period regardless of
its template's age was not established and has been removed. Inspect the actual guest's
activation/evaluation state and remaining rearm count before choosing a rebuild cadence.
`baseline_rearm_evaluation` is off by default; cloning an aging template is not proof of a
fresh evaluation. A fresh media build and a forest/member recovery plan may be needed.

## CTF and FLARE tool installation

Tools are installed on running guests via Ansible playbooks, not baked into separate
templates. Every Windows guest — CTF, FLARE, or plain — clones from the same base
`tpl-win11-pro` template. Stock guests from `tpl-ws2025` remain available too.

```bash
just lab-play tools-ctf.yml -e targets=ctf01
just lab-play tools-flare.yml -e targets=flare01
```

**CTF tools** (`tools-ctf.yml`): installs Chocolatey packages (Wireshark, Ghidra, x64dbg,
etc.), extracts Nmap via 7-Zip (the NSIS installer hangs headless), stages Npcap, and
configures Sysinternals. After the playbook finishes, RDP or console in and run the staged
Npcap installer — the free license requires an interactive GUI install.

**FLARE-VM** (`tools-flare.yml`): checks Tamper Protection, disables Defender via policy,
reboots, verifies Defender is stopped, then fires the pinned FLARE installer async. The
SSH connection drops because Boxstarter owns reboots. Monitor progress via RDP; it takes
roughly an hour. When it finishes, check `C:\ProgramData\_VM\failed_packages.txt` and
take a golden snapshot.

**Npcap:** the free interactive installer cannot be silently automated (`/S` is OEM-only).
The playbook stages the checksum-pinned installer at `C:\Windows\Temp\npcap-setup.exe`.
RDP or console in and run it. During Packer base template builds, this was automated via
QEMU sendkey console keystrokes, but that mechanism is not used on running guests.

**Nmap:** the Chocolatey package starts AutoHotkey to drive a GUI (hangs headless), and the
upstream NSIS installer stalls in Session 0. The fix extracts the NSIS package as an archive
using 7-Zip, which avoids running the installer entirely.

**To create a reusable template from a configured guest:** Sysprep it
(`C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /quit`), then convert to a
template with `qm template <vmid>` on the Proxmox host. This is entirely optional — the
playbook workflow means you can always rebuild tools on a fresh clone.

OpenTofu's `ctf01` and `flare01` both clone from the base `tpl-win11-pro` template.
Existing persistent guests retain their disks and snapshots when a template is replaced
because clone-source changes are ignored.

## The forest, and planned weaknesses

Implemented today: forest/DNS creation, forwarding and the OU tree below. The weakness
toggles and AD CS discussed here are design proposals, not existing roles or group vars.

**Structure.** Everything lives under one top-level `LAB` OU rather than in the default
`Users` and `Computers` containers, for the reason that makes it a good habit rather than a
preference: **you cannot link a GPO to the default containers.** Anything that starts life in
`CN=Computers` needs moving before policy reaches it, and `redircmp` exists precisely because
so many environments discover this late.

```
ad.lab.internal
└── LAB
    ├── Servers
    ├── Workstations
    ├── Groups
    └── Users
        ├── Staff
        ├── IT
        └── ServiceAccounts
```

**Weaknesses are declared, not improvised.** A range you cannot attack teaches nothing, but a
weakness you forget you planted teaches the wrong lesson: you find a path six months later and
cannot tell whether it is something you built or something you broke. The proposed interface
is an entry in `group_vars`, toggled by name; it is not implemented:

```yaml
lab_weaknesses:
  - kerberoastable_service_account   # SPN on a user with a crackable password
  - asrep_roastable_user             # preauth disabled
  - acl_path_to_domain_admins        # helpdesk group holds GenericAll over a privileged group
  - unconstrained_delegation_host    # a member server trusted for delegation
  - credential_in_sysvol_script      # a logon script with a password in it
```

Three properties follow from that shape and are the whole point of it. The list is a
**review surface**: you can read what the range is supposed to be vulnerable to without
reading the roles. It is **reversible**: turn one off, rerun, and check whether your detection
still fires, which is the difference between an attack lab and a detection lab. And it makes
the forest **honest about itself**, because a clean forest is `lab_weaknesses: []` and is worth
building at least once, so you know what normal looks like before you break it.

Seeded account passwords belong in `secrets/lab.yaml` even though several are meant to be
crackable. Not because they are sensitive, but so the repository never carries something that
reads like a real credential list.

**Later, and worth its own toggles:** Active Directory Certificate Services. The ESC family of
misconfigurations is a large part of the modern attack surface and none of it exists until a
CA does. Add it as a member server role with its own declared weaknesses rather than folding
it into the DC.

## What OpenTofu owns, and what it deliberately does not

The repo's invariant is that any host can be rebuilt from this repository alone. That is
worth its cost for a machine whose loss would cost you something. The persistent `ctf01`,
`flare01` and `kali01` workstations belong in OpenTofu. A disposable
exercise target does not: it can be created and deleted without an HCL edit.

So the line is durability, not technology:

| | Declared in `provisioning/vms.tf` | Created ad hoc |
|---|---|---|
| **What** | `dc01`, `kali01`, `ctf01`, `flare01`, member servers | Ad-hoc test hosts, anything booted from a live ISO |
| **Address** | Static, from OpenTofu | DHCP |
| **Config** | Ansible role, reproducible | Whatever the task needs; usually nothing |
| **If lost** | Rebuild from the playbook | Shrug |
| **Snapshots** | A `golden` snapshot after Ansible converges; revert to it freely | Take your own, mid-task, and lose them with the guest |

Both land in the `lab` pool and on VLAN 90, so the two kinds can see each other, which is the
entire point of keeping the lab flat. The ad-hoc helper clones existing templates without entering OpenTofu state; preparing a
new Linux template from a downloaded image is a separate operation.

## Ansible: inventory and how it authenticates

**Static inventory, covering the declared machines only.** They have known addresses, so
nothing dynamic is needed. Should that change, `community.general.proxmox` provides an
inventory plugin that can filter by pool, which is a second reason the `lab` pool earns its
place. Do not build that until something needs it. An ad-hoc guest that wants a playbook run
can use a temporary inventory rather than an entry in the committed inventory.

**Ansible uses the lab SSH key from its first connection.** Packer's OpenSSH installation
writes `C:\ProgramData\ssh\administrators_authorized_keys` with the required ACL for Windows.
Linux cloud images receive their key through cloud-init. `just lab-play` decrypts the private
key from SOPS into a temporary mode-0600 file, sets `ANSIBLE_PRIVATE_KEY_FILE`, and removes
the file on exit. The baseline role does not bootstrap the key using a password.

The standing login password is separately supplied through cloud-init. A working Ansible
connection does not prove it was set successfully. Validate password-only login too.
Windows administrator keys must be in the shared administrators file, not merely the user's
`~/.ssh/authorized_keys`.

For an ad-hoc playbook run, use a temporary inventory with the appropriate `windows` or
`linux` group and connection variables. An IP-only inventory does not automatically match
`hosts: windows` or supply the Windows PowerShell connection settings.

## Getting into a guest

Everything below uses one credential, `clone-admin-password` in `secrets/lab.yaml`, which
cloud-init sets on every guest at first boot:

```bash
just lab-cred clone-admin-password    # copies it to the clipboard
just lab-cred                         # lists what else is in there
```

| | Account | RDP | SSH |
|---|---|---|---|
| Windows (`dc01`, `ctf01`, `flare01`) | `Administrator` | enabled by the `baseline` role | key **or** password |
| Kali (`kali01`) | `kali` | needs the `linux_remote_desktop` role | key **or** password |
| Ad-hoc guests | as above, by OS | same, once the role has run | key or password after cloud-init completes |

SSH is available after first-boot provisioning completes, including any hostname reboot.
RDP needs Ansible: it is off by default on Windows, and a Linux cloud image has no desktop
for RDP to show. Run the baseline or desktop role before attempting an RDP login.

**The SSH key is the same one Ansible uses**, and it is in `secrets/lab.yaml` as
`ansible-ssh-private-key`. For a guest whose address you know:

```bash
just lab-cred ansible-ssh-private-key   # or extract it to a file and use ssh -i
```

Password authentication is deliberately enabled on Linux guests
(`linux_ssh_password_auth`), because the cloud image ships it off and you need the password
for the console and RDP anyway. Turn it off for anything ever exposed beyond VLAN 90.

**One password opens every guest, and that is a deliberate lab trade-off.** It keeps
`just lab-cred` a single lookup rather than a per-host hunt, on a range whose forest is
seeded with deliberate weaknesses anyway. It is the wrong pattern for anything holding real
data, and the place to change it is `ci_password` in `provisioning/vms.tf`, which is a
per-guest argument already.

## The pet lifecycle

Declared guests share one shape, whichever OS they run: **deploy, configure, snapshot,
work, revert, occasionally rebuild.** Only the Ansible role differs between them.

```bash
just lab-snapshot  kali01                  # take/replace the golden restore point
just lab-snapshot  kali01 before-exploit   # take an ad-hoc one, alongside golden
just lab-snapshots kali01                  # what restore points exist
just lab-revert    kali01 [name]           # rewind, discarding everything since
just lab-rebuild   kali01                  # destroy, redeploy on the current template, reconfigure, re-snapshot
```

**`golden` is the only reserved name, and the only one this tooling will ever overwrite.**
It means: the state a machine is in once its role has converged and before you start
breaking it. `lab-rebuild` re-takes it every time, which is the step that is easy to forget
and the one that makes the *next* revert possible, and letting it accumulate as `golden-1`,
`golden-2` would turn "revert to fresh" into "work out which one".

**Every other snapshot is yours, and nothing here will touch it.** Re-taking a name that
already exists is refused rather than silently replaced.

**So there is nothing to remember about which tool to use.** The Proxmox UI, `qm snapshot`
and `just lab-snapshot` are the same mechanism, and no part of this repo tracks snapshots,
so there is no state to desync. Take ad-hoc snapshots wherever is convenient. The recipes
exist for the two things the UI cannot do for you: keeping `golden` single, and re-taking
it as the last step of a rebuild.

**Revert is not rebuild.** Revert rewinds the machine you have and keeps everything the
image gave it. Rebuild throws the machine away and clones the template again, which is how
you pick up a newer base image -- a rebuilt Kali is a newer Kali, a reverted one is not.

**Snapshots are recipes, not OpenTofu resources**, and that is a judgement rather than a
workaround for the provider lacking one. A snapshot is a point in time, not a desired
state; declaring one would have OpenTofu forever comparing the snapshot that exists against
the snapshot that should exist and re-taking it.

## Throwaway guests

```bash
just lab-spawn tpl-win11-pro test01    # clone, cloud-init to DHCP, start
just lab-spawn tpl-debian test02 debian # other Linux templates need their image username
just lab-despawn test01                # stop and destroy
```

These are deliberately outside OpenTofu, for the reason in the ownership table above. They
land in the `lab` pool on VLAN 90, take a lease from technitium's `.100`-`.199` range with
the `lab.internal` suffix, and carry the lab password and the Ansible key from first boot,
once their first-boot configuration finishes. The template must contain Cloudbase-Init
(Windows) or cloud-init (Linux). The command adds a metadata drive when missing, preserves
the cloned NIC's MAC/model, and places it on the lab bridge and VLAN. Kali's user is known;
other Linux images use the template's configured `ciuser` or the explicit third argument.

**They are not domain-joined.** Joining is the thing most often worth *testing*, so it is a
play you run rather than something that has already happened to the box.

`lab-despawn` requires both `adhoc` and `lab` tags and refuses templates or anything tagged
`terraform` or `template`. Untagged VMs are not assumed to be disposable. Snapshot, rollback,
clone and deletion commands wait for the returned Proxmox task to finish successfully;
API errors, task failures and timeouts stop the command.

## Linux guests: two things that bite on the second boot

Both of these are invisible on the boot that creates the machine, which is what makes them
worth writing down.

**Test the second boot, always.** A cloud image is built and tested at one set of package
versions, and Proxmox's cloud-init turns on `package_upgrade` by default, so the first boot
dist-upgrades it to whatever the distribution's HEAD is before you ever log in. That can
cross a major version boundary of a package the machine needs in order to boot correctly.
Treat "reboot it once and confirm it comes back" as a mandatory acceptance check for any new
Linux guest, exactly like the second-activation check when onboarding an LXC.

That is not hypothetical. It is precisely what happened here:

1. Proxmox's `ciupgrade` default dist-upgraded Kali on first boot.
2. That took netplan from 1.1.2 to 1.2.1.
3. netplan 1.2 deliberately moved `.network`/`.link` generation **out** of its systemd
   generator -- which now only validates and writes unit symlinks -- into a new
   `netplan-configure.service`.
4. That unit installed **disabled** (see below), so nothing generated the network config.

First boot still worked, because cloud-init applies the network itself for a new instance
and then writes `/run/cloud-init/.skip-network` and correctly stays out of the way. Every
boot after that came up with `eth0` unmanaged and no address, reachable only from the
console. `linux_baseline` enables the unit.

**On Kali, a package installed after the image was built arrives disabled.**
`/usr/lib/systemd/system-preset/99-default.preset` is `disable *.service` and
`95-kali.preset` is the whitelist, so dpkg's preset policy switches off anything the
whitelist does not name -- and the whitelist predates netplan 1.2. Every `enabled: true` in
`linux_baseline` is therefore load-bearing rather than belt-and-braces, and anything added
there needs the same treatment.

The diagnostic order for "the address is right in the YAML but the interface is down" is
`ls /run/systemd/network` and `systemctl is-enabled netplan-configure.service` -- not
cloud-init, which is a red herring here and correctly reports itself done.

**Leaving `package_upgrade` on is the deliberate choice.** Turning it off
(`initialization { upgrade = false }`) would have hidden this, but only until someone ran
`apt upgrade`, and it would leave every lab guest unpatched on first boot. Fix what the
upgrade breaks; do not stop upgrading.

## Backups

Rebuilding restores declared configuration, not research notes, captures, samples or other
user data. All three workstations are intended to be persistent. Decide which of their data
needs backup before rollout; do not assume only FLARE-VM matters. Golden snapshots provide
local rollback, not an independent backup. No lab-wide backup/restore test was performed.

## What a bare clone gives you

A Windows template should also work when cloned without a cloud-init drive or OpenTofu.
The image carries OpenSSH, the Ansible public key and the QEMU guest agent. The capture
sequence leaves the adapter configured for DHCP; cloud-init adds a chosen hostname,
administrator password and optional static address when its drive is attached.

| | Bare clone | Clone through OpenTofu |
|---|---|---|
| Reachable by SSH key | yes | yes |
| Guest agent reporting | yes | yes |
| Address | DHCP lease | the one in `vms.tf` |
| Hostname | OOBE-generated, e.g. `ADMINIS-FNNQLK3` | the name in `vms.tf` |
| Administrator password | Not configured by metadata; use the SSH key | the one in `secrets/lab.yaml` |
| In the `lab` pool, tagged | only if you say so | yes |

Templates built before the finalisation fix can still carry `.99`; changing the script does
not repair existing images. `just packer-build` refuses to start when anything answers on
that address. Validate a replacement with a bare clone as well as a clone with cloud-init.

### The capture gate

`sysprep.ps1` uses `/generalize /oobe /quit` and waits for the process. It requires both a
zero exit code and `IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE`. Sysprep can return zero after
rejecting its command line, so checking only the exit code can publish an unprepared image.
The Cloudbase-Init answer file is copied to a path without spaces for this invocation.
Its specialize pass also enables the built-in Administrator account: client Windows
disables it during generalisation, and updating an existing account's password does not
enable it. This command contains no password and does not configure automatic login.

`finalize-network.ps1` runs as SYSTEM through Task Scheduler. It resets IPv4 and DNS to
DHCP, verifies DHCP is enabled, removes the task, and shuts down only if those steps succeed.
Its transcript is `C:\Windows\Temp\packer-finalize.log`. The API wait has a timeout and
rejects failed API calls or an ambiguous build VM instead of treating a lost SSH connection
as success. Use `-on-error=abort` while diagnosing a build to preserve the VM and its logs.

The installation answer file disables automatic device encryption for capture. Sysprep's
preflight refuses an encrypted OS volume; suspending BitLocker is insufficient. A retained
failed build must finish decrypting before capture is retried. This setting follows
[Microsoft's image-building guidance](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/oem-bitlocker).

The Cloudbase-Init setup pass has its own minimal configuration: MTU and hostname plugins,
`allow_reboot=false`, and an empty-metadata fallback after ConfigDrive. Account, password
and network provisioning remain in the normal Windows service. A missing metadata drive
must not prevent a bare clone from completing Setup: the installer's answer file maps a
discovery failure to exit 2, which [Windows Setup interprets as reboot and retry](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous-runsynchronouscommand-willreboot).
The [empty metadata service](https://cloudbase-init.readthedocs.io/en/1.1.8/services.html)
provides the supported fallback without generating account credentials.

## Cloud-init does the whole job, once Proxmox is left alone

Proxmox has first-class cloudbase-init support and this repo spent a long time fighting it.

`generate_configdrive2` in Proxmox's `Cloudinit.pm` branches on the guest's ostype. For a
Windows one it calls `cloudbase_configdrive2_metadata`, which writes **`admin_pass`** and
**`public_keys`** into metadata, exactly where cloudbase-init's `ConfigDriveService` looks for
them. Proxmox even defaults to that format for Windows without being asked, with the comment:

> No format specified, default based on ostype because windows' cloudbased-init only supports
> configdrivev2

The `qemu-vm` module set `type = "nocloud"` instead, and everything that followed came from
that one line. `NoCloudConfigDriveService` implements no `get_admin_password` at all, so
`SetUserPasswordPlugin` fell through to `Generating a random user password`. Chasing that
produced a sysprep answer file that did not apply, a `SetupComplete.cmd` that stopped running
and left the password in cleartext in every image, and a documented break-glass credential
that had never once worked.

So the split is simply:

- **Cloud-init owns hostname, address and the administrator password**, per VM, from
  `vms.tf`. The clone password is not deliberately baked into the image; a bare clone has
  not received this credential and must not be assumed to have it.
- **The template owns the SSH key**, baked into `administrators_authorized_keys` with
  inheritance stripped, because Windows sshd ignores the usual file for administrators.
- **Ansible owns everything after that**, and authenticates by key.

**A trap worth knowing:** `qm cloudinit dump <vmid> meta` does not show this. It calls a
different function and prints the generic metadata, so `admin_pass` is absent from its output
even when the drive the guest actually reads contains it. Believing that output is what sent
this repo down the detour above.

### Telling whether cloud-init actually ran

Not from the console: a healthy lock screen looks the same either way. Three signals do tell
you, and two need no login.

| Signal | Cloud-init ran | It did not |
|---|---|---|
| Hostname | the name from `vms.tf` | OOBE-generated, e.g. `ADMINIS-SS8OQIO` |
| Address | the assigned static address or DHCP lease | DHCP from the template; no static metadata applied |
| Administrator password | a password-only login with `secrets/lab.yaml` succeeds | rejected (also check password policy and whether the account is enabled) |

`qm agent <vmid> network-get-interfaces` reports addresses; use `hostname` over SSH or the
guest agent to check the hostname. Each plugin can fail independently, so validate all three.

**The interface name is not a signal.** Under `nocloud` cloudbase-init renames the adapter to
`eth0`, which makes a tempting tell; under `configdrive2` -- the format Proxmox picks for
Windows -- it stays `Ethernet` on a guest where cloud-init demonstrably worked. Verified on a
clone carrying the right hostname, address and password with an adapter still called
`Ethernet`.

### The guest agent needs a driver, not just a service

The QEMU guest agent does not reach the host over the network. It uses a VirtIO serial port,
and the standalone `qemu-ga` MSI does not ship that port's driver. Install only the agent and
the service starts, reports itself healthy, and is invisible to Proxmox forever: `qm agent
ping` times out, the VM reports no address, and OpenTofu waits out its entire timeout on
every create before declaring success anyway.

The templates install `virtio-win-guest-tools.exe`, which includes drivers and the agent.
`install-guest-tools.ps1` verifies both the VirtIO Serial device and the QEMU-GA service.
The `virtio-win-gt-x64.msi` alone does not supply the guest agent.

## Resetting, and what that means for the DC

Snapshots are an optimisation here, not the lifecycle. The forest is built by `microsoft.ad`
from `ansible/group_vars`, so the source of truth for the domain is the playbook, not a
snapshot sitting on the node. The intended DC rebuild is a clone, promotion and reboot; see
the validation log for the unresolved first-boot DFSR/domain-discovery failure. Reproducibility
requires that **anything worth keeping in the forest
goes into the role, never only into the running DC.** It is the same invariant the NixOS
hosts run on, and it is what makes a DC safe to throw away.

So a domain controller never *has* to be rolled back. It gets rolled back because that takes
seconds instead of half an hour.

Three reset needs, and only one of them touches the DC:

| Situation | What to do |
|---|---|
| Broke a workstation, or detonated something on it | Revert that VM alone; the DC is untouched |
| Rerun a whole exercise | Revert the range as a set, DC and members together |
| Changed the forest design, or the evaluation expired | Rebuild with `tofu apply` and the playbook |

The middle row is why snapshot names are shared across the range rather than chosen per VM.
A range rollback moves every machine backwards in lockstep, and the lockstep is what makes
it safe.

### The two failure modes

**USN rollback** is the famous one, and it does not apply here. It is a *replication*
divergence, so it takes two or more DCs to happen at all, and the range runs a single DC by
default. If you later add a second — itself a worthwhile exercise — Proxmox exposes a VM
Generation ID (`vmgenid` in the VM config, present on every VM on this node). Windows Server
2012 and later use it to notice they have been rolled back: the DC resets its invocation ID,
drops its RID pool and performs a non-authoritative restore rather than silently diverging.

**Machine account passwords** are the one that will actually bite, and unlike USN rollback it
bites with a single DC too. Domain members rotate their computer account password on a
schedule. Revert the DC past a rotation and the member loses its secure channel, which
surfaces as "the trust relationship between this workstation and the primary domain failed".
The current `domain_controller` role sets `DisablePasswordChange` only on the DC itself;
it does **not** deploy a domain-wide GPO. Domain members can therefore still rotate their
passwords. Revert an exercise's DC and members together, or repair/rejoin affected members.
A rebuilt forest also has new identities even when its DNS name is unchanged: persistent
members need to join the new forest. The standalone Kali, CTF and FLARE workstations do not
have this dependency unless deliberately joined.

Time skew is a distant third. A reverted DC's clock jumps backwards, Kerberos tolerates only
a few minutes of drift, and it resyncs on boot.

### One thing still unverified

The Proxmox OpenTofu provider does not expose `vmgenid`, so VMs created by
`provisioning/vms.tf` inherit whatever PVE does by default. Every VM already on this node
carries one, so that default appears to be "generate" — but **whether PVE issues a _new_ one
on rollback has not been confirmed here**, and a rollback that leaves the ID unchanged is a
rollback Windows cannot detect. Verify it before relying on DC snapshot recovery:
note `qm config <vmid> | grep vmgenid`, snapshot, change something, roll back, compare. File rollback alone does not establish AD-safe snapshot recovery, even with one DC.

## What here is Windows-specific, and what is not


Almost none of this pipeline is about Windows. It is about *guests the flake cannot
configure*, which covers the whole lab and, beyond it, the two VMs already on the node
(`parrot`, `onion`) that are built by hand outside OpenTofu today.

The line drawn here is **whether a thing holds OpenTofu state**, because that decides
whether generalising it later is free or painful:

| Piece | Generic? | Why now, or why later |
|---|---|---|
| `provisioning/modules/qemu-vm` | **Yes, from the start** | Holds state. Renaming it later means `moved` blocks or `tofu state mv` against every VM built from it. Costs nothing to name generically today. |
| `provisioning/vms.tf` | **Yes, from the start** | One file for every QEMU guest, lab and production alike, keeping `main.tf` LXC-only. |
| `packer@pve` ACL block | **Yes, from the start** | Grants the lab pool, storage, node audit and bridge use. `VM.GuestAgent.Audit` permits DHCP discovery for clone builds. |
| `packer/` and `ansible/` layout | **Yes, now** | Held no state, so this was deferred while a second image pipeline was speculative. It stopped being speculative, so they were hoisted to the repo root and `windows/` was retired. The move cost a `git mv` and one path in a recipe, exactly as predicted. |
| Windows roles and unattend files | **No, and that is fine** | `sysprep`, cloudbase-init, VirtIO driver injection and `microsoft.ad` are Windows by nature. |

So `modules/qemu-vm` takes `os_type`, `bios`, `machine` and whether to attach TPM state as
variables rather than hardcoding the Windows answers. Windows guests pass `win11`, OVMF and
TPM; a Linux guest passes `l26` and skips the TPM. Everything else — clone source, cloud-init,
CPU, memory, disk, VLAN, tags, pool, `lifecycle.ignore_changes` on the template — is identical
either way and is why the module is worth having at all.

**The obvious follow-on**, not done here: `parrot` and `onion` exist outside OpenTofu, so
they contradict the repo's rebuild-from-this-repo-alone invariant. Once `qemu-vm` is proven
by the lab, importing them is a `tofu import` per VM plus a module block, and the invariant
holds for the whole node rather than just the containers.

## Tooling

The provisioning tools come from this repository's Nix development shell, not the Mac's
home-manager profile. Use `nix develop` (or the repo's direnv configuration).

Start with checks that create no VMs:

```bash
just lab-check
```

This runs mocked lifecycle tests, shell syntax checks, Packer formatting/HCL syntax,
OpenTofu validation and Ansible syntax checking. Provider plugins/modules must already be
initialised. It does not establish that a Windows installer or an Ansible role works at
runtime. For that, build a template, test a disposable clone, and configure only the host
being validated with an explicit Ansible limit. A full `just apply` would deploy all declared
guests; it is not a smoke test.

`plan`, `apply`, and Windows `lab-spawn` check the clone password before provisioning:
at least eight characters, three of uppercase/lowercase/digits/punctuation, no account
name, and no newline or NUL. This is a conservative local preflight, not an implementation
of every Windows password policy. Windows can still reject a password due to custom policy
or history. Verify password-only remote login on a fresh clone; SSH key access alone does
not prove that Cloudbase-Init successfully set `clone-admin-password`.

**There is no `ansible-galaxy install` step.** nixpkgs' `ansible` attribute already ships
the collections the roles here use. Do not be misled by its `pname`,
which is `ansible-core`: that is the interpreter it is built from, and the community
collection bundle is layered on top. A real `ansible-core` install would carry none of the
below. Their versions follow the flake lock:

| Collection | Used for |
|---|---|
| `microsoft.ad` | forest creation, DC promotion, domain join |
| `ansible.windows` | features, packages, registry, reboots |
| `community.windows` | the gaps in `ansible.windows` |
| `chocolatey.chocolatey` | workstation and analysis tooling |
| `community.sops` | reading secrets/ from a playbook, so no plaintext vars |

Pin nothing by hand here. These move with `flake.lock` like everything else, and a
`requirements.yml` would quietly shadow the versions Nix already provides.

Later, an always-on `lab-controller` LXC can take this role over. Nothing under `packer/` or `ansible/`
would need to change; it would gain the same two packages and a checkout, and its age key
would be added to the `secrets/lab.yaml` rule.

## Validation log

### Checkpoint — 14 September 2026

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

**Verified:**

- Full Windows 11 ISO build using the latest encryption/account fixes succeeded (21m35s),
  producing template 109. Its generated ISO was removed by Packer.
- Fresh `base-check` clone reached `IMAGE_STATE_COMPLETE`, remained `FullyDecrypted`,
  applied its hostname, used DHCP, and accepted password-only SSH. The test clone and
  superseded template 124 were deleted.
- `just lab-check` passed all regression tests, shell/Packer syntax and formatting,
  OpenTofu validation, and Ansible syntax checks.
- Packer's clone builder connected over DHCP and invoked Ansible after fixing IPv4 discovery
  and adding the missing API permission.
- CTF tool template built, captured, and clone-verified end-to-end (see below).
- Earlier live tests proved disposable spawn/despawn and a regular Windows snapshot rollback.

**CTF template validation:**

`just packer-build workstations ctf` completed in 24 minutes 19 seconds, producing
template 114. Ansible ran 22 ok, 11 changed, 0 failed. Template conversion succeeded.
Three fixes validated: Nmap 7-Zip extraction (the Chocolatey package hangs headless),
Npcap QEMU sendkey console automation (free license requires GUI), and Sysprep Appx
cleanup (Chocolatey's `notepadplusplus` installs a per-user MSIX that Sysprep rejects).
Clone verification (ctf-check, VMID 115 — destroyed) confirmed: password-only SSH,
all Chocolatey packages present, Nmap 7.991 functional, Npcap service running,
dumpcap enumerating interfaces.

**Note:** the CTF template (114) was built with the old `packer/workstations` pipeline
before the architecture simplification. It remains valid as a template. New CTF guests
are now configured via `tools-ctf.yml` on running guests cloned from the base template.

**Cloudbase-init behavior notes:**

- `CreateUserPlugin` "can't sign in" log is cosmetic — Sysprep disables Administrator
  during generalization; cloudbase-init's CreateUserPlugin runs before the specialize
  Unattend.xml re-enables it. Password is still set correctly.
- `UserDataPlugin` "unsupported" for password/ssh_authorized_keys/chpasswd is expected —
  these are handled by dedicated plugins reading from configdrive2 metadata.

**Packer discovery fixes validated:**

1. With Proxmox plugin 1.2.4, setting `vm_interface` selects the first address even if IPv6.
   Leaving it unset selects IPv4.
2. The token returned 403 for guest-agent network queries. `VM.GuestAgent.Audit` was added
   to `PackerBuild` in `provisioning/rbac.tf`.

**FLARE status:** no FLARE installation has been run or tested. The `tools-flare.yml`
playbook uses pinned/checksummed official installer and config revision
`4f8769522bda53ab53da2de85def532efaa033ee`. Upstream `-noGui` still calls `Read-Host`;
the role supplies `-noChecks -noGui -noWait` and fires async. Reboot survival, package
success, credential cleanup, GUI/Npcap needs, and disk capacity remain unproven.

**DC evidence:** fresh DC deployment, promotion, readiness and configuration passed; a
second Ansible run changed zero tasks. The test DC was destroyed. **The DFSR recovery
branch has not been exercised live.** Technitium zone/forwarder configuration and Kali
fresh deployment remain unverified.

### Remaining gaps

- FLARE playbook has not been tested on a running guest.
- DC recovery-path (DFSR/domain-discovery failure on first boot) unexercised.
- Technitium `lab.internal` zone and `ad.lab.internal` conditional forwarder not configured.
- Kali fresh deployment, Linux disposable validation, full GUI RDP login not performed.
- Backup/restore, DC evaluation tracking, VM Generation ID on rollback unverified.
- AD weakness toggles and GPO seeding are proposals, not implemented.

### Safeguards

Use scoped, reviewed plans for persistent validation guests; delete saved plans afterward
because they contain sensitive data. The lifecycle helper deletes only owned ad-hoc guests.
Never use historical IDs without checking identity/tags. Keep the Server/stock Windows
bases and pre-existing guests. Never print passwords, keys, metadata or secret logs.

**Retirement caveat:** `just packer-build` checks deletion responses and waits for tasks,
but retires a previous matching template after Packer succeeds, before a fresh-clone test.
Preserve a known-good predecessor until replacement validation when rebuilding an existing
image. Only ISO builds use fixed `.99`.
