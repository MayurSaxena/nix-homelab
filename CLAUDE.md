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
| `modules/nixos/default.nix` | Base NixOS config applied to every host: firewall, SSH (YubiKey sk keys only), auto-upgrade, GC, store optimisation, `custom.domain` option; imports all sub-modules including `services.scrobblex` from NUR |
| `modules/nixos/impermanence.nix` | Ephemeral rootfs support: declares base persistent paths, SSH host keys, SOPS age key path |
| `modules/nixos/proxmox-lxc.nix` | Proxmox LXC tweaks: disables systemd-resolved/resolvconf, creates `lxc_share` group (gid 10000) |
| `modules/nixos/remote-builds.nix` | Delegates nix builds to `nix-builder.home.internal` and adds it as a binary cache substituter |
| `modules/nixos/root-password.nix` | Sets root password from SOPS `secrets/common.yaml` |
| `modules/beszel-agent.nix` | Beszel monitoring agent with custom filesystem tracking |
| `modules/macos/base.nix` | macOS: Touch ID + Watch ID sudo, Dock/Finder prefs, auto-updates, Determinate Nix |
| `modules/macos/remote-builds.nix` | macOS remote builds via activation scripts (separate from NixOS module) |
| `modules/home-manager/msaxena.nix` | User env: zsh, starship, direnv, git, SSH config, SOPS secrets |
| `.sops.yaml` | Defines which age keys can decrypt which secret files |
| `assets/rootfs-impermanence.sh` | Proxmox hookscript: rolls back ZFS subvolume to `@blank` snapshot on `pre-start` |
| `provisioning/modules/nixos-lxc/main.tf` | OpenTofu module that creates LXC containers and auto-patches `.sops.yaml` |
| `provisioning/images.tf` | Downloads CI-built LXC templates from GitHub Releases into Proxmox |

### services.scrobblex

The `services.scrobblex` module (Plex→Trakt webhook scrobbler) is sourced from the NUR repo at `github:MayurSaxena/nurpkgs`. It is imported automatically via `inputs.nur.repos.msaxena.modules.nixos.scrobblex` in `modules/nixos/default.nix`, so the option is available on every NixOS host. Only the `plex` host enables it.

---

## Hosts

### NixOS (LXC on Proxmox)

| Host | File | Services | Impermanent | Remote Builds |
|------|------|----------|-------------|---------------|
| `nix-builder` | `remote-builder.nix` | Nix remote build server | No | N/A (is the builder) |
| `dns` | `dns-server.nix` | Technitium DNS | Yes | Yes |
| `caddy` | `caddy.nix` | Reverse proxy, ACME/TLS | Yes | Yes |
| `actualbudget` | `actualbudget.nix` | Actual Budget | Yes | Yes |
| `sabnzbd` | `sabnzbd.nix` | SABnzbd (Usenet downloader) | Yes | Yes |
| `homepage` | `homepage-dashboard.nix` | Homepage dashboard | Yes | Yes |
| `plex` | `plex-server.nix` | Plex, Scrobblex | Yes | Yes |
| `overseerr` | `overseerr.nix` | Jellyseerr (media requests) | Yes | Yes |
| `paperless` | `paperless.nix` | Paperless-ngx | Yes | Yes |
| `minecraft` | `minecraft.nix` | Paper + Geyser/Floodgate | No | No |
| `files` | `files.nix` | Samba, TimeMachine, Avahi | Yes | Yes |
| `beszel-hub` | `beszel-hub.nix` | Beszel monitoring hub | Yes | Yes |
| `servarr` | `servarr.nix` | Radarr, Sonarr, Bazarr, Prowlarr | Yes | Yes |

### macOS (nix-darwin)
- `Mayurs-MacBook-Pro` — `hosts/Mayurs-MacBook-Pro.nix` — Personal laptop; homebrew, App Store apps, home-manager, remote builds via `custom.remote-builds-mac`

---

## Nix Conventions

### flake.nix — Registering a New Host

```nix
# In nixosConfigurations — single file is the normal pattern:
"my-host" = mkNixOSConfig ./hosts/my-host.nix;
```

> Inline module overrides (passing a list) are only used for the CI base image variants. Real hosts set all `custom.*` flags inside their host file.

### Host File Pattern (`hosts/<name>.nix`)

The minimal skeleton — always present:

```nix
{ inputs, outputs, config, ... }:
{
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;
  custom.impermanence.enable = true;
  custom.remote-builds.enable = true;
  custom.root-password.enable = true;
  custom.beszel-monitoring-agent.enable = true;

  services.my-service = {
    enable = true;
    openFirewall = true;
  };
}
```

Add each of the following only when the service actually needs it:

**`pkgs` in args** — only when referencing packages directly (e.g. `pkgs.caddy.withPlugins`):
```nix
{ inputs, outputs, config, pkgs, ... }:
```

**`let domain = config.custom.domain;`** — only when service config embeds the domain in URLs or hostnames:
```nix
let domain = config.custom.domain; in {
  services.my-service.settings.hostWhitelist = "my-service.${domain}";
}
```

**`imports`** — only when the host needs a module not in the standard set (e.g. `inputs.nix-minecraft.nixosModules.minecraft-servers`):
```nix
{ inputs, outputs, config, ... }:
{
  imports = [ inputs.some-flake.nixosModules.something ];
  ...
}
```

**`sops.secrets`** — only when the service needs encrypted secrets:
```nix
sops.secrets."my-service-secrets" = {
  sopsFile = ./../secrets/my-service.env;
  format = "dotenv";
  restartUnits = [ "my-service.service" ];
};
services.my-service.environmentFile = config.sops.secrets."my-service-secrets".path;
```

**`environment.persistence`** — only for impermanent hosts, for every directory the service writes state to:
```nix
environment.persistence."${config.custom.impermanence.persistence-root}" = {
  directories = [
    { directory = "/var/lib/my-service"; user = "my-service"; group = "my-service"; mode = "0750"; }
    { directory = "/var/lib/private/my-service"; }  # DynamicUser pattern
  ];
};
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
- `custom.impermanence.enable` / `custom.impermanence.persistence-root` (default: `/persistent`)
- `custom.remote-builds.enable` / `custom.remote-builds.remote-host` — NixOS only
- `custom.remote-builds-mac.enable` / `custom.remote-builds-mac.remote-host` — macOS only
- `custom.root-password.enable` — sets root password from SOPS `common.yaml`
- `custom.beszel-monitoring-agent.enable` / `custom.beszel-monitoring-agent.extraFilesystems`

---

## Secrets Management (SOPS)

All secrets in `secrets/` are SOPS-encrypted with age keys. Each host has its own age key derived from its SSH host ed25519 key. The `msaxena-keys` group (SSH key on MacBook + two YubiKey age keys) can decrypt all secrets.

### Adding a New Secret File

When creating a **new** secrets file, manually add a `path_regex` rule to `.sops.yaml` first. Every rule must always include `*msaxena-keys`, plus only the specific host(s) that need access at runtime:

```yaml
# Single host:
- path_regex: secrets/my-service.env$
  key_groups:
    - age:
      - *msaxena-keys
      - *my-host

# All hosts (use the existing *all-keys anchor, which already includes *msaxena-keys):
- path_regex: secrets/common.yaml$
  key_groups:
    - age: *all-keys
```

Then create the file: `sops secrets/my-service.env`

### Referencing a Secret in NixOS Config

```nix
sops.secrets."key-name" = {
  sopsFile = ./../secrets/my-service.env;
  format = "dotenv";  # or "yaml", "ini"
  owner = "service-user";  # if needed
  restartUnits = [ "my-service.service" ];
};
```

### Secret File Formats
- `.env` files → `format = "dotenv"`
- `.yaml` files → `format = "yaml"` (or omit; yaml is the default)
- `.ini` files → `format = "ini"`

---

## Impermanence Pattern

Hosts with `custom.impermanence.enable = true` have an ephemeral rootfs. On every boot the root ZFS subvolume is rolled back to `@blank` by the Proxmox hookscript (`assets/rootfs-impermanence.sh`). Separate ZFS volumes survive reboots: `/persistent`, `/nix`, `/boot`, `/sbin`, `/bin`.

**What `modules/nixos/impermanence.nix` already persists:**
- `/var/log`, `/var/lib/nixos`, `/var/lib/systemd`
- `/etc/machine-id`
- SSH host keys at `/persistent/etc/ssh/` (RSA + ed25519) — also the SOPS age key source

**What each host must additionally declare:**
- Every `/var/lib/<service>` directory the service writes to
- `/var/lib/private/<service>` for DynamicUser services (systemd stores state there)
- Any runtime config files under `/etc/`

**Pattern:**
```nix
environment.persistence."${config.custom.impermanence.persistence-root}" = {
  directories = [
    { directory = "/var/lib/my-service"; user = "my-service"; group = "my-service"; mode = "0750"; }
    { directory = "/var/lib/private/my-service"; }  # DynamicUser
  ];
  files = [ "/etc/my-config-file" ];
};
```

---

## Provisioning (OpenTofu)

### Template Selection

The `ct_template_id` in `provisioning/main.tf` must match the host's impermanence/remote-builds settings. Use the Terraform resource names from `provisioning/images.tf`:

| Host type | `ct_template_id` |
|-----------|-----------------|
| Impermanent + remote builds (most hosts) | `proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id` |
| Not impermanent, no remote builds (`minecraft`) | `proxmox_virtual_environment_download_file.nixos-standard-nightly.id` |
| Impermanent + remote builds, prod-stable (`nix-builder` doesn't apply; `dns` uses prod) | `proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-prod.id` |
| Not impermanent, prod-stable (`nix-builder`) | `proxmox_virtual_environment_download_file.nixos-standard-prod.id` |

Most new hosts should use `nixos-impermanent-remotebuild-nightly`.

### VLAN Convention (`network_interfaces`)

```hcl
network_interfaces = { "eth0" = 20 }   # general services (most hosts)
network_interfaces = { "eth0" = 10 }   # networking/proxy (caddy, dns, beszel-hub)
network_interfaces = { "eth0" = 40 }   # gaming (minecraft)
```

### Adding a New LXC Container

1. Add module to `provisioning/main.tf`:
   ```hcl
   module "my-host" {
     source                = "./modules/nixos-lxc"
     pve_node_name         = var.pve_node_name
     ct_description        = "My Service (Terraform)"
     hostname              = "my-host"
     domain                = "home.internal"
     network_interfaces    = { "eth0" = 20 }
     ipv4_settings         = "dhcp"
     ipv6_settings         = "auto"
     memory_size_mb        = 1024
     num_cpu_cores         = 2
     persistent_fs_size_gb = 4          # required when rootfs_impermanence = true
     nix_fs_size_gb        = 8          # required when rootfs_impermanence = true
     ct_template_id        = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
     pool_id               = "production"
     startup_order         = 3
     rootfs_impermanence   = true
     custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id  # required when rootfs_impermanence = true
     tags                  = ["terraform", "my-tag"]
   }
   ```
2. Add host config `hosts/my-host.nix`
3. Register in `flake.nix` `nixosConfigurations`
4. If the host needs secrets, add a `path_regex` rule to `.sops.yaml` and create the file with `sops secrets/my-host.yaml`
5. Commit and push
6. Run `tofu apply` — this automatically:
   - Creates the LXC container
   - SSH-scans it to get the host ed25519 key
   - Converts it to an age key (`ssh-to-age`) and patches `.sops.yaml`
   - Re-encrypts all secrets with `sops updatekeys`
7. On the container: `nixos-rebuild switch --flake github:MayurSaxena/nix-homelab#my-host`

> `tofu destroy` automatically removes the host's age key from `.sops.yaml` and re-encrypts secrets.

---

## CI/CD

### GitHub Actions Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `generate-lxc.yml` | `prod`/`nightly` tags | Builds 4 base LXC image variants via nixos-generators, releases as `.tar.xz`. `prod` = stable, `nightly` = prerelease |
| `update-flake-lock.yml` | Daily (5PM UTC) | Runs `nix flake update`, commits `flake.lock` directly, and force-pushes the `nightly` tag — which cascades into triggering `generate-lxc.yml` |

### LXC Image Variants
- `base-lxc` → `nixos-proxmox-lxc-standard`
- `base-lxc-impermanent` → `nixos-proxmox-lxc-impermanent`
- `base-lxc-remote` → `nixos-proxmox-lxc-standard-remotebuild`
- `base-lxc-impermanent-remote` → `nixos-proxmox-lxc-impermanent-remotebuild`

---

## Network Topology

- **Internal domain:** `*.home.internal` (resolved by Technitium DNS on the `dns` host)
- **External domain:** `*.home.mayursaxena.com` (Cloudflare DNS-01 ACME via Caddy)
- **Reverse proxy:** All external services proxied through the `caddy` host
- **Monitoring:** Beszel hub on `beszel-hub`; agents on every host via `custom.beszel-monitoring-agent`
- **Remote builds:** Hosts with `custom.remote-builds.enable = true` delegate builds to and pull substitutes from `nix-builder.home.internal` (exceptions: `minecraft` and `nix-builder` itself)

---

## Common Operations

### Rebuild a Host

```bash
# On the host itself:
nixos-rebuild switch --flake github:MayurSaxena/nix-homelab#<hostname>

# Or via SSH from the repo:
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
# or a single input:
nix flake update nixpkgs
```

---

## Style Conventions

1. **Nix formatting:** `alejandra` via `nix fmt .`
2. **Module options:** Local options always under `custom.*` namespace
3. **`let domain = config.custom.domain;`** at top of host files that reference service URLs
4. **Impermanent hosts:** Declare persistence for every directory a service writes to
5. **Secrets:** Never hardcode credentials; always use SOPS-encrypted files
6. **Commit messages:** Imperative present tense (e.g., `Adding bazarr to lxc_share group.`)
7. **SSH access:** Only public key auth; authorised keys are YubiKey sk keys only

---

## What NOT to Do

- Do not edit `flake.lock` manually — use `nix flake update`
- Do not commit unencrypted secrets — always use `sops` to edit secret files
- Do not bypass impermanence for new services — always declare persistent directories
- Do not add packages directly to `environment.systemPackages` in host files unless truly global
- Do not modify `.sops.yaml` age keys manually — `tofu apply`/`tofu destroy` handle this via local-exec provisioners
- Do not add `nixpkgs.overlays` in host files — the base module no longer sets an overlay; use NUR or upstream nixpkgs
