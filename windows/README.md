# windows

The Windows half of the homelab: a small Active Directory range plus a persistent analysis
workstation, on VLAN 90 (`10.0.90.0/24`, forest `lab.internal`).

Unlike the NixOS hosts, none of this is configured by the flake. The pipeline is Packer for
golden templates, OpenTofu for cloning them into VMs, and Ansible for turning a clone into a
domain controller, a member, or the FLARE-VM box. Read `CLAUDE.md` for how that fits beside
the LXC pipeline; this file covers only what the repo cannot do for itself.

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

Most of this pipeline is not really about Windows. It is about *guests the flake cannot
configure*, which today means Windows but tomorrow could mean a Kali or Parrot VM in the
range, or a production appliance that ships as an image rather than a package. The two VMs
already on the node (`parrot`, `onion`) are exactly that shape and are currently built by
hand, outside OpenTofu.

The line drawn here is **whether a thing holds OpenTofu state**, because that decides
whether generalising it later is free or painful:

| Piece | Generic? | Why now, or why later |
|---|---|---|
| `provisioning/modules/qemu-vm` | **Yes, from the start** | Holds state. Renaming it later means `moved` blocks or `tofu state mv` against every VM built from it. Costs nothing to name generically today. |
| `provisioning/vms.tf` | **Yes, from the start** | One file for every QEMU guest, lab and production alike, keeping `main.tf` LXC-only. |
| `packer@pve` ACL block | **Yes, from the start** | Grants a reserved template VMID range rather than the ids in use, so a new template needs no permission change. |
| `packer/` and `ansible/` layout | **Deferred, deliberately** | No state. Hoisting them out of `windows/` later is a `git mv` and one path in a recipe. Restructuring now would be guessing at a second image pipeline that does not exist. |
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

Later, an always-on `lab-controller` LXC can take this role over. Nothing under `windows/`
would need to change; it would gain the same two packages and a checkout, and its age key
would be added to the `secrets/windows.yaml` rule.
