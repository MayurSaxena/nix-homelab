# nix-homelab

Declarative homelab infrastructure using NixOS, nix-darwin, and OpenTofu on Proxmox.

Every host's configuration is self-documenting: if a machine dies, rebuild it from this repo.

## Repository Structure

```
flake.nix              # Entry point — all hosts, inputs, and helpers
hosts/                 # Per-host NixOS and macOS configurations
modules/               # Reusable NixOS and macOS modules
  nixos/               # Base NixOS config, impermanence, proxmox-lxc, etc.
  macos/               # Base macOS config, packages, remote builds
  home-manager/        # User-level dotfiles (zsh, git, ssh)
  beszel-agent.nix     # Monitoring agent module
overlays/              # nixpkgs overlays for packages not yet upstream
packages/              # Custom package definitions (e.g. scrobblex)
provisioning/          # OpenTofu configs for Proxmox LXC provisioning
secrets/               # SOPS-encrypted secrets (age + YubiKey)
assets/                # SSH keys, impermanence hookscript
.github/workflows/     # CI: LXC image generation, flake.lock auto-update
```

## Key Design Decisions

- **Impermanence**: Most LXC containers use an ephemeral rootfs that resets on every boot. Only `/nix`, `/persistent`, and `/boot` survive reboots. This forces all state to be declared in Nix.
- **SOPS + age + YubiKey**: Secrets are encrypted at rest in the repo. Each host has an age key derived from its SSH host key; decryption requires either the host key or a YubiKey.
- **Remote builds**: Most containers delegate builds to a dedicated `nix-builder` LXC to save RAM/CPU.
- **Single domain variable**: All services share `custom.domain` (default: `home.mayursaxena.com`), defined once in `modules/nixos/default.nix`.

## Deploying a New NixOS LXC

Provisioning is handled by OpenTofu in `provisioning/`:

1. Add a new module block in `provisioning/main.tf` with the desired specs.
2. Add a host config in `hosts/<name>.nix`.
3. Add the hostname to `nixosConfigurations` in `flake.nix`.
4. Run `cd provisioning && tofu apply`.
   - OpenTofu creates the LXC, derives its age key, and updates `.sops.yaml` automatically.
5. Generate any new secrets: `sops secrets/<file>`.
6. Push to GitHub, then on the container: `nixos-rebuild switch --flake github:MayurSaxena/nix-homelab`

### Setting Up Impermanence

For impermanent containers, OpenTofu handles:
- Mount points: `/boot`, `/nix`, `/persistent`, `/sbin`, `/bin`
- The hookscript (`assets/rootfs-impermanence.sh`) that rolls back the rootfs ZFS subvolume to `@blank` before each boot

The `/sbin` and `/bin` mounts are persistent volumes that survive rootfs wipes. NixOS populates `/sbin/init` (symlink → `/nix/var/nix/profiles/system/init`) at activation time; because `/nix` is also a persistent mount, the init chain is always valid without any special Proxmox entrypoint configuration.

SSH host keys and `machine-id` are seeded automatically on first boot via `systemd-tmpfiles` rules in `modules/nixos/impermanence.nix` (`C` rules copy from the ephemeral paths if no persistent copy exists yet). No manual key generation is needed.

### What The Base Image Provides

- Firewall enabled
- SSH with YubiKey-only root access (password auth disabled)
- Root password via SOPS (for Proxmox console access)
- Daily auto-upgrade from `github:MayurSaxena/nix-homelab` at ~4 AM AEST
- Daily garbage collection (older than 7 days)
- Impermanence: persists SSH host keys, machine-id, `/var/log`, `/var/lib/nixos`, `/var/lib/private`
- Beszel monitoring agent on all hosts

## Deploying on a New Mac

1. Install [Determinate Nix](https://determinate.systems/nix-installer/).
2. Ensure the Mac's hostname has an entry in `flake.nix` under `darwinConfigurations`.
3. Run: `sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake github:MayurSaxena/nix-homelab`
4. Plug in a YubiKey for secrets decryption.

This configures: Touch ID/Watch sudo, Homebrew casks, App Store apps, shell (zsh + starship), SSH keys, Dock/Finder preferences, and remote Nix builds.
