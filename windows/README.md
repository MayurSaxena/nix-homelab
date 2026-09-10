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
Upload*. The file name matters, because `provisioning/windows.tf` refers to it:

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
