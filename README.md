# nix-homelab

Declarative homelab infrastructure using NixOS, nix-darwin, and OpenTofu on Proxmox.

Thirteen NixOS hosts run as unprivileged LXC containers on a single Proxmox node, plus one
nix-darwin Mac. Every host's configuration lives here: if a machine dies, rebuild it from
this repo. If a change only works because of state created by hand on a running box, it's a
bug.

> Working on this repo with an AI assistant? [`CLAUDE.md`](CLAUDE.md) documents the mental
> model and the decision procedures — how to pick a persistence shape, where a secret
> belongs, how to size a container — in more depth than this README.

## Repository Structure

```
flake.nix              # Entry point — inputs, both config builders, every host
hosts/                 # Per-host NixOS and macOS configurations
modules/
  nixos/               # Base NixOS module + the custom.* capability modules
  macos/               # Base macOS config, packages, remote builds
  home-manager/        # The Mac user's dotfiles and personal secrets
  beszel-agent.nix     # Monitoring agent (shared, imported by the NixOS base)
provisioning/          # OpenTofu configs for Proxmox LXC provisioning
secrets/               # SOPS-encrypted secrets (age + YubiKey)
assets/                # Committed in the clear — hookscript, pubkeys, builder key
util/                  # pve-auth.sh — sourced, not executed, for 2FA against the PVE API
.github/workflows/     # CI: LXC image generation, flake.lock auto-update
```

## How It Fits Together

Four systems hand off to each other:

1. **OpenTofu creates the container.** `tofu apply` builds the LXC, then SSH-scans it,
   converts its ed25519 host key to an age key, splices that into `.sops.yaml`, and re-runs
   `sops updatekeys`. `tofu destroy` removes the key and re-encrypts. `.sops.yaml`'s age
   anchors are machine-managed — don't hand-edit them. The provisioner stops there: committing
   `.sops.yaml`/`secrets/*` and doing the first switch are `provisioning/onboard-host.sh`'s job
   instead, since a multi-minute remote build and a YubiKey prompt don't belong inside a
   provisioner that gates `apply`'s success or failure.
2. **The container boots a CI base image.** Just enough NixOS to be SSH-reachable and
   sops-capable. A bootstrap, not the host.
3. **The first `nixos-rebuild switch` makes it itself.** Impermanence turns on, services
   start, secrets decrypt against the host key OpenTofu already registered.
4. **`system.autoUpgrade` keeps it current.** Each host pulls this repo daily and switches.
   A separate workflow updates `flake.lock` on main and re-tags `nightly`, rebuilding the
   images.

Pushing to main therefore deploys. There is no staging step.

## Key Design Decisions

- **Impermanence**: most containers use an ephemeral rootfs that resets on every boot. Only
  the separate volumes survive — `/boot`, `/nix`, `/persistent`, `/sbin`, `/bin` — and of
  those only `/persistent` is backed up. This forces state to be declared in Nix.
- **SOPS + age + YubiKey**: secrets are encrypted at rest. Each host has an age key derived
  from its SSH host key; a file is encrypted to the operator's YubiKeys plus only the hosts
  that need it at runtime.
- **Remote builds**: most containers delegate builds to a dedicated `nix-builder` LXC, which
  also serves as a binary cache substituter. Containers are sized for their service, not for
  compiling.
- **Single domain variable**: services share `custom.domain` (default
  `home.mayursaxena.com`), defined once in `modules/nixos/default.nix`.
- **`custom.*` namespace**: every repo-local option lives under `custom.*`. Five toggles form
  the standard host preamble — `proxmox-lxc`, `impermanence`, `remote-builds`,
  `root-password`, `beszel-monitoring-agent`.

## Deploying a New NixOS LXC

1. Write `hosts/<name>.nix` and register it in `nixosConfigurations` in `flake.nix`.
2. Add a module block in `provisioning/main.tf`. `hostname` must equal the flake attribute
   key.
3. If it needs secrets, add a `path_regex` rule to `.sops.yaml`, then `sops secrets/<file>`.
4. Commit and push — `autoUpgrade` and the flake URL read from GitHub, not your worktree.
5. `cd provisioning && tofu apply`
   - Creates the LXC, derives its age key, and updates `.sops.yaml` automatically.
   - Imports the single `base-lxc` release image; impermanence and remote-builds don't need
     pre-baking (see below).
6. `./onboard-host.sh <flake-host-key> <container-ip>` — commits/pushes the `.sops.yaml`
   change from step 5 if it's still pending, then bootstraps the real config. These LXCs get
   only as much RAM as their service needs, so building on the container itself can hit the OOM
   killer; the script always delegates the build to `nix-builder` explicitly instead
   (`--build-host`/`--target-host`), the same way the daily auto-upgrade does once
   `custom.remote-builds.enable = true` takes effect from the host's own first switch.
   `<flake-host-key>` is the attribute name in `nixosConfigurations` — it isn't always the same
   as the module name in `provisioning/main.tf` (`dns-server` → `dns`, `plex-server` → `plex`,
   `fileserver` → `files`). Root SSH is YubiKey-hardware-key-only on every host, so this step
   needs someone at the keyboard — run it yourself, or ask Claude to.

### Base Images

CI publishes a single image, rebuilt on every push of the `nightly` tag: `base-lxc` →
`nixos-proxmox-lxc-standard.tar.xz`, tracked as one template resource,
`nixos-standard-nightly`, in `provisioning/images.tf`. Every host's `ct_template_id` points at
it — there used to be a `prod` tag and a `remotebuild` variant, both gone (see
`provisioning/images.tf`'s header comment for why).

Impermanence is not an image dimension: OpenTofu creates the persistent mounts, and the
host's own flake enables impermanence on first switch. Remote-builds isn't pre-baked either —
`onboard-host.sh` always passes `--build-host` explicitly on the first switch.

Changing a host's `ct_template_id` later is safe — the module sets `ignore_changes` on
`operating_system["template_file_id"]`, so it only affects newly-created containers.

### Setting Up Impermanence

For impermanent containers, OpenTofu handles:

- Mount points `/boot`, `/nix`, `/persistent`, `/sbin`, `/bin` (only `/persistent` is backed
  up)
- The hookscript (`assets/rootfs-impermanence.sh`) that rolls the rootfs ZFS subvolume back
  to `@blank` before each boot

`custom_hookscript` is a separate variable from `rootfs_impermanence` and defaults to null —
set only the latter and you get the volumes with no rollback, i.e. a host that is impermanent
in name only.

`/sbin` and `/bin` are persistent volumes that survive the wipe. NixOS populates `/sbin/init`
(symlink → `/nix/var/nix/profiles/system/init`) at activation; because `/nix` is also
persistent, the init chain stays valid without special Proxmox entrypoint configuration.

SSH host keys and `machine-id` are seeded on first boot by `systemd-tmpfiles` `C` rules in
`modules/nixos/impermanence.nix`, which copy from the ephemeral paths when no persistent copy
exists. No manual key generation is needed.

`custom.impermanence` persists `/var/log`, `/var/lib/nixos`, `/var/lib/systemd`,
`/etc/machine-id` and the SSH host keys. **Anything else a service writes must be declared by
its host file** — the failure is silent and only shows up after a reboot. It also creates
`/persistent/var/lib/private` at `0700`, which is where `DynamicUser` services land; that
directory is created, not persisted, and each host still declares its own child under it.

### What Every NixOS Host Gets

From `modules/nixos/default.nix`, which `mkNixOSConfig` injects into every host — don't
re-declare any of it in a host file:

- Firewall enabled; SSH with YubiKey-only root access, password auth disabled
- Daily auto-upgrade from `github:MayurSaxena/nix-homelab` (18:00 UTC + jitter, ~4 AM AEST)
- Daily garbage collection (older than 7 days) and store optimisation
- `sops.defaultSopsFile` / `sops.age.sshKeyPaths`, `users.mutableUsers = false`,
  `nixpkgs.config.allowUnfree`, timezone, `system.stateVersion`

The CI base image additionally sets `custom.proxmox-lxc.enable`. Everything else —
impermanence, remote-builds, the root password, the monitoring agent — comes from the host's
own file on the first switch, not from the image.

## Deploying on a New Mac

1. Install [Determinate Nix](https://determinate.systems/nix-installer/).
2. Ensure the Mac's hostname has an entry under `darwinConfigurations` in `flake.nix`. The
   host file must import `modules/macos/base.nix` itself — unlike the NixOS builder,
   `mkDarwinConfig` does not inject a base module.
3. `sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake github:MayurSaxena/nix-homelab`
4. Plug in a YubiKey for secrets decryption.

This configures Touch ID / Watch sudo, Homebrew casks, App Store apps, zsh + starship, SSH
keys, Dock/Finder preferences, and remote Nix builds.

Note that under Determinate Nix the nix-darwin `nix.*` options are inert — daemon settings
are written by activation scripts instead. See `modules/macos/remote-builds.nix`.

## Common Operations

```bash
nix fmt .                                                       # alejandra
nix build .#nixosConfigurations.<host>.config.system.toplevel   # check without switching
nix eval .#nixosConfigurations.<host>.config.systemd.services.<unit>.serviceConfig
nix flake update [<input>]
sops secrets/<file>
nixos-rebuild switch --flake .#<host> --target-host root@<ip>
source util/pve-auth.sh                                                 # auth for tofu (see CLAUDE.md)
cd provisioning && tofu apply
./provisioning/onboard-host.sh <flake-host-key> <container-ip>          # finish a new host
```
