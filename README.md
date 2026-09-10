# nix-homelab

Declarative homelab infrastructure using NixOS, nix-darwin, and OpenTofu on Proxmox.

The NixOS hosts run as unprivileged LXC containers on a single Proxmox node, plus one
nix-darwin Mac; `flake.nix` lists every one of them. Every host's configuration lives here:
if a machine dies, rebuild it from this repo. If a change only works because of state created
by hand on a running box, it's a bug.

> Working on this repo with an AI assistant? [`CLAUDE.md`](CLAUDE.md) documents the mental
> model and the decision procedures — how to pick a persistence shape, where a secret
> belongs, how to size a container — in more depth than this README.

## Repository Structure

```
flake.nix              # Entry point — inputs, both config builders, every host
justfile               # `just` recipes for the commands with flags worth not retyping
hosts/                 # Per-host NixOS and macOS configurations
modules/
  nixos/               # Base NixOS module + the custom.* capability modules
  macos/               # Base macOS config, packages, remote builds, auto-upgrade
  home-manager/        # The Mac user: packages, shell, git/ssh, window manager
  beszel-agent.nix     # Monitoring agent (NixOS-only, imported by the NixOS base)
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
4. **`system.autoUpgrade` keeps it current.** Each NixOS host pulls this repo daily and
   switches. A separate workflow updates `flake.lock` on main and re-tags `nightly`,
   rebuilding the images. The Mac is excluded — see *Deploying on a New Mac*.

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
- **`custom.*` namespace**: every repo-local option lives under `custom.*`. A fixed block of
  toggles opens every host file — `proxmox-lxc`, `impermanence`, `remote-builds`,
  `root-password`, `beszel-monitoring-agent`. `failure-notifications` is default-on and
  stays unset.

## Deploying a New NixOS LXC

Provision first, then write the config. The other order deadlocks: a `.sops.yaml` rule that
names the new host's age-key anchor makes every `sops` call in the repo fail until
`tofu apply` has created that anchor — including the one `util/pve-auth.sh` needs to
authenticate `tofu apply` itself.

1. Add a module block in `provisioning/main.tf`. `hostname` must equal the flake attribute
   key you register in step 3.
2. `just apply -target=module.<name>` — creates the LXC from the `base-lxc` release image,
   derives its age key, and splices it into `.sops.yaml` automatically. Impermanence and
   remote-builds don't need pre-baking (see below).
3. Write `hosts/<name>.nix` and register it in `nixosConfigurations` in `flake.nix`. If it
   needs secrets, add a `path_regex` rule to `.sops.yaml`, then `sops secrets/<file>`. If it
   is proxied, add its `virtualHosts` entry in `hosts/caddy.nix` now too.
4. `just deploy <flake-host-key> <container-ip>` — the first real switch, from your working
   tree with nothing committed. Check `systemctl --failed`, exercise the service (not just
   its unit status), then run the same command a second time to prove the activation is
   idempotent. Deploy `caddy` the same way if you changed it.
5. Commit and push — `autoUpgrade` and the flake URL read from GitHub, not your worktree, and
   the next nightly upgrade reverts anything that isn't on `main`.
6. Optionally `just onboard <flake-host-key> <container-ip>` to confirm that what GitHub
   holds matches what you verified; it should be a no-op activation.

Both deploy recipes build on `nix-builder` explicitly (`--build-host`/`--target-host`): these
LXCs get only as much RAM as their service needs, so building on the container itself can hit
the OOM killer. Root SSH is YubiKey-hardware-key-only on every host, so both need someone at
the keyboard — run them yourself, or ask Claude to. `<flake-host-key>` is the attribute name
in `nixosConfigurations`, which isn't always the module name in `provisioning/main.tf`
(`dns-server` → `dns`, `plex-server` → `plex`, `fileserver` → `files`).

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
5. Add a `discord/mac-update-webhook` key to `secrets/msaxena.yaml`, or set
   `custom.auto-upgrade-mac.discord.enable = false`. A missing key fails the *build*, not
   activation: sops-nix validates its manifest against the sops file's key structure,
   which a sops YAML keeps in plaintext.

The Mac upgrades itself: `custom.auto-upgrade-mac` is a root LaunchDaemon that wakes the
machine shortly before 4AM, resolves `main` to a commit, switches to that pinned SHA, and
then verifies the result by comparing `/run/current-system` against what the commit
evaluates to. It posts a banner when it starts, and a banner plus a Discord message when it
finishes — green on success, red on a bad exit status or a system that does not match. A
dirty checkout is reported as a footnote, since the switch has just reverted it.

Run `darwin-auto-upgrade` as root to do the same thing on demand, or
`sudo launchctl kickstart -k system/org.nixos.darwin-auto-upgrade` to exercise the daemon
itself.

This configures Touch ID / Watch sudo, Homebrew casks and VS Code extensions, App Store
apps, fonts, zsh + starship + the CLI stack, Ghostty, AeroSpace + JankyBorders, git and SSH,
macOS defaults (Dock, Finder, keyboard, screenshots), the Claude Code status line, and remote
Nix builds — everything under `modules/macos/` and `modules/home-manager/`.

A few things macOS will not let Nix do. After the first switch, by hand:

- Grant Accessibility to Ghostty (for the ⌃` quick terminal) and AeroSpace when each asks.
- Turn on Spotlight's clipboard history (System Settings → Spotlight) if wanted; it is
  reachable with ⌘Space then ⌘4.
- Arrange Ice's menu bar once. Point Shottr's save folder at `~/Pictures/Screenshots`.
- Add `~/.ssh/id_ed25519.pub` to GitHub as a *signing* key: commits are SSH-signed with it.
- Add to `~/.claude/settings.json` (Claude Code writes that file itself, so it is not
  managed here): `"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}`
  and a `Notification` hook whose command is `~/.claude/notify.sh`.
- `killall Finder` once, so the declared Finder view settings apply.

Note that under Determinate Nix the nix-darwin `nix.*` options are inert — daemon settings
are written by activation scripts instead. See `modules/macos/remote-builds.nix` and
`modules/macos/auto-upgrade.nix`.

## Common Operations

Run `just` to list the recipes. They wrap the commands below, keeping the easily-forgotten
flags in one reviewable place.

```bash
just                              # list every recipe
just fmt                          # alejandra
just hosts                        # every host this flake can build
just check <host>                 # build a host without switching
just deploy <host> <ip>           # first switch from the working tree, nothing committed
just plan / just apply            # tofu, with Proxmox auth handled (needs a YubiKey)
just secret <file>                # edit an encrypted file
just mac                          # switch this Mac
just gc                           # drop old generations
```

The same things by hand:

```bash
nix fmt .                                                       # alejandra
nix build .#nixosConfigurations.<host>.config.system.build.toplevel   # check without switching
nix eval .#nixosConfigurations.<host>.config.systemd.services.<unit>.serviceConfig
nix flake update [<input>]
sops secrets/<file>
nixos-rebuild switch --flake .#<host> --target-host root@<ip>
source util/pve-auth.sh                                                 # auth for tofu (see CLAUDE.md)
cd provisioning && tofu apply
./provisioning/onboard-host.sh <flake-host-key> <container-ip>          # finish a new host
```

Every host in `nixosConfigurations` also gets an SSH alias on the Mac automatically, so it is
`ssh plex`, not `ssh root@plex`. The list is derived, so a new host needs no SSH change.
And `, <command>` runs any program in nixpkgs without installing it.
