# The lab (VLAN 90)

Everything on `10.0.90.0/24`: a proper Active Directory range (domain controller, member
servers, domain-joined workstations), plus research boxes, CTF machines and tool machines of
whatever operating system a task needs. Forest `lab.internal`.

Unlike the NixOS hosts, none of this is configured by the flake. The pipeline is Packer for
golden images that have to be built, OpenTofu for cloning them into guests, and Ansible for
turning a clone into a role. Read `CLAUDE.md` for how that sits beside the LXC pipeline; this
file covers the lab's own decisions.

Two standards apply, and they pull in different directions on purpose:

- **The AD range is built properly.** Real forest, real DNS, real GPO, static addressing,
  reproducible from the playbook.
- **Everything else works out of the box, or close to it.** A CTF box or a research VM should
  boot, get an address and be usable. If a machine needs a bespoke build to be useful, that is
  a reason to question the machine, not to write more automation.

## Addressing and DNS

VLAN 90 is `10.0.90.0/24`, gateway `10.0.90.1`, with **UniFi serving DHCP from `.100` to
`.199`** and handing out technitium (`10.0.10.2`) as the resolver.

| Block | Use | Assigned by |
|---|---|---|
| `.10`&ndash;`.19` | Servers. `lab-dc01` is `.10`. | OpenTofu, static |
| `.20`&ndash;`.39` | Domain-joined workstations. `lab-ws01` is `.21`. | OpenTofu, static |
| `.50`&ndash;`.59` | Pets. `flare01` is `.50`. | OpenTofu, static |
| `.99` | Packer builds, and nothing else. | The unattend, static |
| `.100`&ndash;`.199` | Everything disposable: CTF boxes, research VMs, live ISOs. | UniFi DHCP |

**Static only where it earns it.** A machine takes a static address if something must find it
at a known place: the domain controller, anything domain-joined (which also needs the DC as
its resolver), and the Packer build. Everything else DHCPs. The `qemu-vm` module accepts
`ipv4_settings = "dhcp"` for exactly this, so it is a choice per guest rather than a policy.

**DHCP hands out technitium, not the domain controller**, and that is deliberate in both
directions. Pointing it at the DC would make every CTF box depend on the DC being up to
resolve anything at all. Pointing it at the DC *with technitium as a secondary* is worse
still: a Windows domain member that queries a non-AD resolver gets NXDOMAIN for the SRV
records it needs and then fails intermittently, in ways that look like AD is broken.
Microsoft's guidance is that domain members resolve only against AD DNS, and the way to
honour that here is to give them their resolver statically rather than through DHCP.

Technitium conditionally forwards `lab.internal` to the DC, so a disposable box on DHCP can
still resolve `lab-dc01.lab.internal` in order to attack it. That is the point of keeping the
whole lab on one flat VLAN rather than separating the AD range: a firewall between your Kali
box and your domain controller sits in the path of exactly the traffic you care about.

`.99` exists because a Packer build has no OpenTofu behind it. It is deliberately outside
every other block, so two concurrent builds collide with each other, which is obvious, rather
than with a range VM, which would not be. The address is build-only: sysprep discards it, and
cloud-init assigns the clone its real one.

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

Most Linux distributions publish a cloud image that already carries cloud-init and the QEMU
guest agent, which is the entire content of a Packer build. Kali and Parrot both do. For
those, download the image with a `proxmox_virtual_environment_download_file` resource next to
the ISOs in `provisioning/images.tf`, clone it with `qemu-vm`, and configure it with Ansible
if it needs anything at all. That is less work to write and nothing to maintain, and it is
what "works out of the box" actually looks like.

Build a Linux template only when something must exist *before first boot* that cloud-init
cannot do at boot time. That is rare. A slow package install is not a reason on its own;
a snapshot after first configuration gets you the same speed without a second pipeline.

The `qemu-vm` module does not care which kind of thing it is cloning, so this is a decision
per image rather than an architectural fork.

## Which edition goes where, and why

**Every Windows client here is Windows 11 Pro, left unactivated.** Both the domain-joined
range workstations and the FLARE-VM analysis box come from one template. Only the servers
run evaluation media, because there is no non-evaluation Server 2025 to be had without a
licence.

That is one Windows 11 template rather than two, one manual ISO rather than two, and no
expiry to manage on any client. Pro joins a domain (Home cannot), and domain join is not
gated on activation, so nothing about the range needs Enterprise. Unactivated Windows only
watermarks the desktop and greys out personalisation settings; an *expired evaluation*, by
contrast, blacks the desktop and shuts the machine down every hour, which would be ruinous
on a box holding analysis state and merely annoying on the rest.

**What Pro gives up, and when to revisit.** The one security-relevant gap is **Credential
Guard**, which is Enterprise and Education only. It is what stops LSASS credential dumping
on a modern corporate endpoint, so an exercise about *why Mimikatz fails* and how that is
evaded cannot be staged on Pro. Everything a beginner-to-intermediate AD exercise needs —
domain join, GPO, Kerberos, delegation, LSASS dumping without VBS in the way — works on Pro,
and works more simply, since Credential Guard is not silently blocking the lesson.

If Credential Guard ever becomes the point, add a `tpl-win11-ent` template from the standard
Enterprise 90-day [evaluation][eval] (**not** LTSC, which omits the Store, the UWP stack,
Edge, Copilot and Teams, and so removes the very surface a real endpoint has). It is a copy
of the Pro Packer config with a different ISO and edition string. `provisioning/rbac.tf`
already grants `packer@pve` on `/vms/9101`, deliberately left unused, so no permission
change is needed when that day comes.

**The servers are the only expiry to track.** Server 2025 evaluation runs 180 days, and
`sysprep /generalize` rearms that clock, so each clone starts its own full term from first
boot however old the template is, up to three rearms. Treat it as a template rebuild
cadence rather than a problem to solve — but note that if you ever want the *forest itself*
to live longer than a couple of rebuild cycles, the DC's evaluation is the binding
constraint, not the workstations.

The node already carries a Windows 10 22H2 consumer ISO from earlier work. It would also
serve for `flare01`, but Windows 10 passed end of support in October 2025, so prefer 11.

## The forest, and its deliberate weaknesses

**Structure.** Everything lives under one top-level `LAB` OU rather than in the default
`Users` and `Computers` containers, for the reason that makes it a good habit rather than a
preference: **you cannot link a GPO to the default containers.** Anything that starts life in
`CN=Computers` needs moving before policy reaches it, and `redircmp` exists precisely because
so many environments discover this late.

```
lab.internal
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
cannot tell whether it is something you built or something you broke. So every deliberate
misconfiguration is an entry in `group_vars`, toggled by name:

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
worth its cost for a machine whose loss would cost you something. A CTF box exists precisely
because losing it costs nothing, so declaring it in `vms.tf` applies a durability guarantee
to a thing defined by not needing one, and charges you an HCL edit and a git commit for a
machine you will delete this evening.

So the line is durability, not technology:

| | Declared in `provisioning/vms.tf` | Created ad hoc |
|---|---|---|
| **What** | `lab-dc01`, member servers, `lab-ws01`, `flare01` | CTF boxes, research VMs, anything booted from a live ISO |
| **Address** | Static, from OpenTofu | DHCP |
| **Config** | Ansible role, reproducible | Whatever the task needs; usually nothing |
| **If lost** | Rebuild from the playbook | Shrug |

Both land in the `lab` pool and on VLAN 90, so the two kinds can see each other, which is the
entire point of keeping the lab flat. Ad-hoc guests are cloned straight from a template or a
downloaded cloud image without going near OpenTofu state.

## Ansible: inventory and how it authenticates

**Static inventory, covering the declared machines only.** They have known addresses, so
nothing dynamic is needed. Should that change, `community.general.proxmox` provides an
inventory plugin that can filter by pool, which is a second reason the `lab` pool earns its
place. Do not build that until something needs it. An ad-hoc guest that wants a playbook run
can take one with `-i <address>,` and no inventory entry at all.

**Key authentication, bootstrapped once over a password.** The public key goes to declared
guests through cloud-init (`ci_public_keys` on the `qemu-vm` module); the private key lives in
`secrets/lab.yaml` and is read with the `community.sops` lookup, so playbooks stay
committable.

There is a Windows-specific trap in that, and it is worth knowing before it wastes an
afternoon. Windows OpenSSH does **not** read `~/.ssh/authorized_keys` for any account in the
Administrators group. It reads `C:\ProgramData\ssh\administrators_authorized_keys`, and it
refuses that file unless its ACL grants only SYSTEM and Administrators. Cloudbase-init's key
plugin writes to the user profile, so a key injected that way is silently ignored and every
connection falls back to asking for a password.

Rather than weaken `sshd_config` to paper over it, the `baseline` role authenticates its
first run with the password cloudbase-init set, writes the key to
`administrators_authorized_keys` with the right ACL, and every run after that uses the key.
The password stays a bootstrap credential rather than becoming a standing one.

## Backups

Reproducibility is the backup for most of this. Range VMs rebuild from the playbook and
templates rebuild from Packer, so backing either up stores a copy of something the repo
already describes.

`flare01` is the exception, because it accumulates analysis state that exists nowhere else.
Back that one up, and leave the rest of the `lab` pool out of the job. This is the same
judgement the LXC side already makes by setting `backup = true` on `/persistent` alone.

## What cloud-init does and does not do here

Proxmox and cloudbase-init only half agree, and the half that fails does so silently. Verified
on the first clone (`qm cloudinit dump <vmid> user|network|meta`):

| Setting | Where Proxmox writes it | Where cloudbase-init looks | Works? |
|---|---|---|---|
| Network | `network-config`, version 1 | the same | **Yes** |
| Password | `user-data`, as cloud-config `password:` | `admin_pass` in `meta-data` | No |
| Hostname | `user-data`, as cloud-config `hostname:` | `local-hostname` in `meta-data` | No |

Proxmox's generated meta-data contains an instance-id and nothing else, so the two plugins
that read it find nothing and do nothing. There is no error anywhere: the clone boots on the
correct static address, with a hostname nobody chose and a password nobody knows, and the
first symptom is a 401 from WinRM twenty minutes later.

There is a second layer to this, found by trying the obvious fix and watching it fail.
Writing `AdministratorPassword` into the sysprep answer file **also does not work**: a clone
built that way still rejected every credential. What a clone's OOBE actually leaves behind is
a machine sitting in the **Public** firewall profile with sshd not running, reachable on
nothing but the one all-profiles WinRM rule the build's own unattend created. Ports 135, 139,
445 and 3389 are all closed. None of that is fixable remotely, which is how a template that
built perfectly produces a guest nobody can reach.

So the work is split by what provably runs, not by what ought to:

- **Cloud-init owns the network.** The one thing Proxmox and cloudbase-init agree on.
- **`SetupComplete.cmd` owns the clone's initial state.** It runs once, as SYSTEM, before any
  login, and it is how cloudbase-init itself gets started -- which makes it the only
  first-boot mechanism on this image with a perfect record. `sysprep.ps1` appends to it:
  enable the account, force sshd on, open port 22 on all profiles, and move the connection
  out of the Public profile. It truncates itself afterwards so the password it sets does not
  persist in cleartext in every clone.
- **The template owns the SSH key.** Baked into `administrators_authorized_keys` at build
  time, with the ACL stripped to SYSTEM and Administrators.
- **Ansible owns everything after that**, and needs no bootstrap credential at all.

That last point is a reversal from the original design, where Ansible would authenticate once
with a cloud-init password and install its own key. Nothing sets that password, so the
bootstrap step was removed rather than repaired -- which is how cloud images have always
worked. Every clone trusting one lab key is the same trust model as every clone sharing one
baked password, without the password. `clone-admin-password` survives in `secrets/lab.yaml`
purely as an emergency console credential.

### A clone's first reported address is the wrong one

A guest boots briefly on the address baked into the template by the build, and cloudbase-init
replaces it with the real one a moment later. OpenTofu polls the guest agent as soon as it
answers, which can land inside that window, so `ipv4_addresses` in state sometimes records
`10.0.90.99` rather than the guest's actual address.

Harmless -- nothing reads that attribute, and the module's output is informational -- but
worth knowing before it sends someone chasing a network fault that does not exist. The
authority is `qm agent <vmid> network-get-interfaces`, or simply connecting. A give-away that
you are looking at the settled state rather than the transient one: cloudbase-init renames the
interface to `eth0`, so an adapter still called `Ethernet` has not been configured yet.

### The guest agent needs a driver, not just a service

The QEMU guest agent does not reach the host over the network. It uses a VirtIO serial port,
and the standalone `qemu-ga` MSI does not ship that port's driver. Install only the agent and
the service starts, reports itself healthy, and is invisible to Proxmox forever: `qm agent
ping` times out, the VM reports no address, and OpenTofu waits out its entire timeout on
every create before declaring success anyway.

The templates therefore install the full `virtio-win-gt-x64.msi` and inject `vioserial`
alongside the storage and network drivers, then assert the VirtIO Serial device exists rather
than trusting that it does.

## Resetting, and what that means for the DC

Snapshots are an optimisation here, not the lifecycle. The forest is built by `microsoft.ad`
from `ansible/group_vars`, so the source of truth for the domain is the playbook, not a
snapshot sitting on the node. Rebuilding `lab-dc01` from nothing is a clone, a promotion and
a reboot. That stays true only under one discipline: **anything worth keeping in the forest
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
The `domain_controller` role therefore sets a GPO disabling machine account password changes
domain-wide. That would be indefensible in production and is exactly right here: it removes
the whole class of problem and lets the DC and its members be reverted independently of each
other.

Time skew is a distant third. A reverted DC's clock jumps backwards, Kerberos tolerates only
a few minutes of drift, and it resyncs on boot.

### One thing still unverified

The Proxmox OpenTofu provider does not expose `vmgenid`, so VMs created by
`provisioning/vms.tf` inherit whatever PVE does by default. Every VM already on this node
carries one, so that default appears to be "generate" — but **whether PVE issues a _new_ one
on rollback has not been confirmed here**, and a rollback that leaves the ID unchanged is a
rollback Windows cannot detect. Establish it at the Phase 2 gate rather than assuming it:
note `qm config <vmid> | grep vmgenid`, snapshot, change something, roll back, compare. This
only matters once a second DC exists, but it is cheap to settle while the range is small.

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
| `packer@pve` ACL block | **Yes, from the start** | Grants a reserved template VMID range rather than the ids in use, so a new template needs no permission change. |
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

These decisions belong in `CLAUDE.md` eventually, alongside the LXC decision procedures.
They live here until Phase 5, when there is enough built to describe accurately.

## Tooling

`packer` and `ansible` come from the Mac's home-manager profile
(`modules/home-manager/msaxena.nix`), so `just mac` is all that is needed to get them.

**There is no `ansible-galaxy install` step.** nixpkgs' `ansible` attribute already ships
every collection the roles here use, 92 of them in total. Do not be misled by its `pname`,
which is `ansible-core`: that is the interpreter it is built from, and the community
collection bundle is layered on top. A real `ansible-core` install would carry none of the
below. Verified against this flake's pinned build, not the registry's:

| Collection | Version | Used for |
|---|---|---|
| `microsoft.ad` | 1.12.0 | forest creation, DC promotion, domain join |
| `ansible.windows` | 3.7.0 | features, packages, registry, reboots |
| `community.windows` | 3.3.0 | the gaps in `ansible.windows` |
| `chocolatey.chocolatey` | 1.6.0 | workstation and analysis tooling |
| `community.sops` | 2.4.0 | reading secrets/ from a playbook, so no plaintext vars |

Pin nothing by hand here. These move with `flake.lock` like everything else, and a
`requirements.yml` would quietly shadow the versions Nix already provides.

Later, an always-on `lab-controller` LXC can take this role over. Nothing under `packer/` or `ansible/`
would need to change; it would gain the same two packages and a checkout, and its age key
would be added to the `secrets/lab.yaml` rule.
