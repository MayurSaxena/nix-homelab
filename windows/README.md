# windows

The Windows half of the homelab: a small Active Directory range plus a persistent analysis
workstation, on VLAN 90 (`10.0.90.0/24`, forest `lab.internal`).

Unlike the NixOS hosts, none of this is configured by the flake. The pipeline is Packer for
golden templates, OpenTofu for cloning them into VMs, and Ansible for turning a clone into a
domain controller, a member, or the FLARE-VM box. Read `CLAUDE.md` for how that fits beside
the LXC pipeline; this file covers only what the repo cannot do for itself.

## Media

Four ISOs are needed. Two are declared in `provisioning/images.tf` and arrive with
`tofu apply`. **Two must be uploaded by hand, once**, and that split is forced by Microsoft
rather than by this repo:

| ISO | How it arrives |
|---|---|
| Windows Server 2025 evaluation | `tofu apply` (stable `go.microsoft.com/fwlink` redirect) |
| virtio-win drivers | `tofu apply` (pinned Fedora archive URL) |
| Windows 11 Enterprise evaluation | manual, see below |
| Windows 11 Pro | manual, see below |

Microsoft's Evaluation Center and the consumer download page both mint a **signed CDN URL
that expires roughly 24 hours after the page generates it**, and regenerate it per visit. A
URL committed here would fail the next day, at apply time, on a machine that worked
yesterday. So do not add one.

To upload one by hand, from the Proxmox web UI: *Datacenter → proxmox → local → ISO Images →
Upload*. The file names matter, because `provisioning/windows.tf` refers to them:

- `windows-11-enterprise-eval.iso` from the [Evaluation Center][eval]
- `windows-11-pro.iso` from the [consumer download page][consumer]

[eval]: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise
[consumer]: https://www.microsoft.com/software-download/windows11

## Which edition goes where, and why

The range is cattle and the analysis box is a pet, so they take different media:

- **Range VMs** (`lab-dc01`, `lab-ws01`, any member server) use evaluation media. Server 2025
  runs 180 days and Windows 11 Enterprise 90, and `sysprep /generalize` resets that clock, so
  every clone starts fresh no matter how old the template is. Expiry is a template rebuild
  cadence, not a problem to solve.
- **`flare01`** uses Windows 11 Pro left unactivated. An evaluation build eventually stops
  booting, which is fine for a VM you rebuild and wrong for one you keep. Unactivated
  consumer Windows runs indefinitely with a watermark and some personalisation settings
  greyed out, neither of which matters for opening minidumps.

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
