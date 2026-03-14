# CLAUDE.md — nix-homelab

AI assistant guide for the `nix-homelab` repository.

## Project Overview

A declarative homelab infrastructure project managing:
- **NixOS** hosts (LXC containers on Proxmox)
- **nix-darwin** for macOS (`Mayurs-MacBook-Pro`)
- **Home-Manager** for user-level dotfiles
- **OpenTofu** for Proxmox LXC provisioning
- **SOPS + age + YubiKey** for secrets management

**Core philosophy:** Every host is fully declarative and can be rebuilt from scratch using this repository.

---

## Repository Structure

```
nix-homelab/
├── flake.nix                  # Entry point: all hosts, inputs, outputs, helper functions
├── flake.lock                 # Locked dependency versions (do not edit manually)
├── .sops.yaml                 # SOPS encryption rules (age keys per host)
├── hosts/                     # Per-host NixOS/macOS configuration files
├── modules/
│   ├── nixos/                 # NixOS shared modules
│   ├── macos/                 # nix-darwin shared modules
│   ├── home-manager/          # User-level dotfiles and tools
│   └── beszel-agent.nix       # Monitoring agent module
├── overlays/default.nix       # Custom package overlays
├── packages/                  # Custom package derivations
├── provisioning/              # OpenTofu/Terraform for LXC creation
├── secrets/                   # SOPS-encrypted secret files
├── assets/                    # Non-secret static files (SSH keys, hookscripts)
└── util/                      # Helper scripts
```

---

## Key Files

| File | Purpose |
|------|---------|
| `flake.nix` | Defines all inputs, `nixosConfigurations`, `darwinConfigurations`, and helper functions `mkNixOSConfig` / `mkDarwinConfig` |
| `modules/nixos/default.nix` | Base NixOS config: firewall, SSH (YubiKey-only), auto-upgrade, GC, `custom.domain` option |
| `modules/nixos/impermanence.nix` | Ephemeral rootfs with `/persistent` mount |
| `modules/nixos/proxmox-lxc.nix` | Proxmox LXC tweaks (disables systemd-resolved, `lxc_share` group) |
| `modules/nixos/remote-builds.nix` | Delegates nix builds to `nix-builder.home.internal` and adds it as a binary cache substituter |
| `modules/nixos/root-password.nix` | Sets root password via SOPS |
| `modules/nixos/scrobblex.nix` | Custom `services.scrobblex` — Plex→Trakt scrobbler (Node.js webhook receiver) |
| `modules/beszel-agent.nix` | Beszel monitoring agent with custom filesystem tracking |
| `modules/macos/base.nix` | macOS: Touch ID + Watch ID sudo, Dock/Finder prefs, auto-updates, Determinate Nix |
| `modules/home-manager/msaxena.nix` | User env: zsh, starship, git, SSH config, SOPS secrets |
| `.sops.yaml` | Defines which age keys can decrypt which secret files |
| `assets/rootfs-impermanence.sh` | Proxmox hookscript: rolls back ZFS subvolume before each boot |

---

## Hosts

### NixOS (LXC on Proxmox)

| Host | Services | Impermanent | Remote Builds |
|------|----------|-------------|---------------|
| `nix-builder` | Nix remote build server | No | N/A (is the builder) |
| `dns` | Technitium DNS | Yes | Yes |
| `caddy` | Reverse proxy, ACME/TLS | Yes | Yes |
| `actualbudget` | Finance tracking | Yes | Yes |
| `sabnzbd` | Usenet downloader | Yes | Yes |
| `homepage` | Services dashboard | Yes | Yes |
| `plex` | Plex media server | Yes | Yes |
| `overseerr` | Media request manager | Yes | Yes |
| `paperless` | Document management | Yes | Yes |
| `minecraft` | Paper + Geyser/Floodgate | No | No |
| `files` | Samba + TimeMachine | Yes | Yes |
| `beszel-hub` | Monitoring hub | Yes | Yes |
| `servarr` | Radarr, Sonarr, Bazarr, Prowlarr | Yes | Yes |

### macOS (nix-darwin)
- `Mayurs-MacBook-Pro` — Personal laptop with homebrew, App Store apps, home-manager

---

## Nix Conventions

### flake.nix — Adding a New Host

```nix
# In nixosConfigurations:
# Single file:
my-new-host = mkNixOSConfig ./hosts/my-new-host.nix;

# With inline overrides (pass a list):
my-new-host = mkNixOSConfig [
  ./hosts/my-new-host.nix
  { custom.impermanence.enable = true; }     # optional
  { custom.remote-builds.enable = true; }    # optional
];
```

### Host File Pattern (`hosts/<name>.nix`)

```nix
{ inputs, outputs, config, pkgs, ... }:
let
  domain = config.custom.domain;  # "home.mayursaxena.com"
in {
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;
  custom.impermanence.enable = true;
  custom.remote-builds.enable = true;
  custom.root-password.enable = true;
  custom.beszel-monitoring-agent.enable = true;

  services.my-service = {
    enable = true;
    # ...
  };

  # For services that need secrets:
  sops.secrets."my-service/api-key" = {
    sopsFile = ./../secrets/my-service.env;
    format = "dotenv";
    restartUnits = [ "my-service.service" ];
  };
  services.my-service.environmentFile = config.sops.secrets."my-service/api-key".path;

  # For impermanent hosts, declare persistent storage:
  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [ "/var/lib/my-service" ];
  };

  networking.firewall.allowedTCPPorts = [ 8080 ];
}
```

### Module Pattern

```nix
{ config, lib, pkgs, ... }:
let cfg = config.custom.my-feature; in {
  options.custom.my-feature = {
    enable = lib.mkEnableOption "my feature";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on";
    };
  };

  config = lib.mkIf cfg.enable {
    # configuration here
  };
}
```

### Custom Options Namespace

All local options live under `custom.*`:
- `custom.domain` — base domain (default: `home.mayursaxena.com`)
- `custom.proxmox-lxc.enable` — Proxmox LXC tweaks (network, resolvconf, `lxc_share` group)
- `custom.impermanence.enable` / `custom.impermanence.persistence-root`
- `custom.remote-builds.enable` / `custom.remote-builds.remote-host` — NixOS only
- `custom.remote-builds-mac.enable` / `custom.remote-builds-mac.remote-host` — macOS only
- `custom.root-password.enable` — sets root password from SOPS `common.yaml`
- `custom.beszel-monitoring-agent.enable` / `custom.beszel-monitoring-agent.extraFilesystems`

---

## Secrets Management (SOPS)

### Encryption

All secrets in `secrets/` are SOPS-encrypted with age keys. Each host has its own age key (derived from its SSH host key). The user's YubiKey can also decrypt all secrets.

### Adding a Secret

1. Ensure the host's age key is in `.sops.yaml` under the appropriate `path_regex` rule.
2. Edit/create the secret file: `sops secrets/my-service.env`
3. Reference in NixOS config:
   ```nix
   sops.secrets."key-name" = {
     sopsFile = ./../secrets/my-service.env;
     format = "dotenv";  # or "yaml", "binary"
     owner = "service-user";  # if needed
     restartUnits = [ "my-service.service" ];
   };
   ```

### Secret File Formats
- `.env` files → `format = "dotenv"`
- `.yaml` files → `format = "yaml"` (or omit, yaml is default)
- `.ini` files → treated as binary (`format = "binary"`)

---

## Impermanence Pattern

Hosts with `custom.impermanence.enable = true` have an ephemeral rootfs. On every boot, the root ZFS subvolume is reset to blank. Only `/persistent`, `/nix`, `/boot`, `/sbin`, `/bin` survive reboots.

**What the base module already persists** (in `modules/nixos/impermanence.nix`):
- `/var/log`, `/var/lib/nixos`, `/var/lib/systemd`
- `/etc/machine-id`
- SSH host keys at `/persistent/etc/ssh/` (both RSA and ed25519) — also used as the SOPS age key source

**What host configs must additionally persist:**
- Service state directories: `/var/lib/<service>`
- Config files that get modified at runtime: `/etc/<file>`

**Pattern in host config:**
```nix
environment.persistence."${config.custom.impermanence.persistence-root}" = {
  directories = [
    "/var/lib/my-service"
    { directory = "/var/lib/private/my-service"; user = "my-service"; group = "my-service"; mode = "0700"; }
  ];
  files = [ "/etc/my-config-file" ];
};
```

---

## Provisioning (OpenTofu)

### Adding a New LXC Container

1. Add module to `provisioning/main.tf`:
   ```hcl
   module "my_host" {
     source = "./modules/nixos-lxc"
     # ... variables
   }
   ```
2. Run `tofu apply` → creates LXC, outputs age key
3. Update `.sops.yaml` with the new host's age key
4. Add host config `hosts/my-host.nix`
5. Register in `flake.nix` `nixosConfigurations`
6. Create/encrypt secrets: `sops secrets/my-host.yaml`
7. Commit and push
8. On the container: `nixos-rebuild switch --flake github:MayurSaxena/nix-homelab#my-host`

---

## CI/CD

### GitHub Actions Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `generate-lxc.yml` | `prod`/`nightly` tags | Builds 4 base LXC image variants via nixos-generators, releases as `.tar.xz`. `prod` tag = stable release, `nightly` tag = prerelease |
| `update-flake-lock.yml` | Daily (5PM UTC) | Runs `nix flake update`, commits `flake.lock` directly, and force-pushes the `nightly` tag — which cascades into triggering `generate-lxc.yml` |

### LXC Image Variants (CI)
- `base-lxc` — Standard base
- `base-lxc-impermanent` — With impermanence
- `base-lxc-remote` — With remote builds
- `base-lxc-impermanent-remote` — Both impermanence and remote builds

---

## Network Topology

- **Internal domain:** `*.home.internal` (resolved by Technitium DNS)
- **External domain:** `*.home.mayursaxena.com` (Cloudflare, ACME certs via Caddy)
- **Reverse proxy:** All services behind Caddy (caddy host)
- **Monitoring:** Beszel hub + agents on all hosts
- **Remote builds:** Containers with `custom.remote-builds.enable = true` delegate builds to and pull substitutes from `nix-builder.home.internal` (exceptions: `minecraft` and `nix-builder` itself)

---

## Common Operations

### Rebuild a Host

```bash
# On the host itself:
nixos-rebuild switch --flake github:MayurSaxena/nix-homelab#<hostname>

# Or via SSH:
nixos-rebuild switch --flake .#<hostname> --target-host root@<ip>
```

### Format Nix Code

```bash
nix fmt .
```

### Check a Configuration Without Switching

```bash
nix build .#nixosConfigurations.<hostname>.config.system.toplevel
```

### Edit Secrets

```bash
sops secrets/<file>.yaml
sops secrets/<file>.env
```

### Update Flake Inputs

```bash
nix flake update
# or update a single input:
nix flake update nixpkgs
```

---

## Style Conventions

1. **Nix formatting:** Use `alejandra` (run via `nix fmt .`)
2. **Module options:** Always under `custom.*` namespace for local options
3. **`let domain = config.custom.domain;`** at top of host files for readable service URLs
4. **Impermanent hosts:** Always declare persistence for any service that writes state
5. **Secrets:** Never hardcode credentials; always use SOPS-encrypted files
6. **Services:** Prefer upstream NixOS modules (`services.*`) over custom systemd units when available
7. **Commit messages:** Descriptive imperative present tense (e.g., `Adding bazarr to lxc_share group.`)
8. **SSH access:** Only public key auth; YubiKey is the primary credential

---

## What NOT to Do

- Do not edit `flake.lock` manually — use `nix flake update`
- Do not commit unencrypted secrets — always use `sops` to edit secret files
- Do not add `security.sudo.wheelNeedsPassword = false` without good reason — hosts use YubiKey
- Do not bypass impermanence for new services — always declare persistent directories
- Do not add packages directly to `environment.systemPackages` in host files unless truly global; prefer service-specific package options
- Do not modify `.sops.yaml` age keys manually after provisioning — use OpenTofu outputs
