# CLAUDE.md — nix-homelab

Guide for AI assistants working in this repository.

Read this for the *mental model and the decision procedures*. It deliberately does not
give you a fill-in-the-blanks host template, because the parts that vary — the
`services.*` block, what gets persisted, how a secret is consumed — are determined by the
upstream nixpkgs module for whatever service you're adding, not by this repo. Where a
choice depends on the service, this document tells you **how to work out the answer** and
**what to go read**. Follow that rather than pattern-matching an existing file.

---

## What this is

A declarative homelab. Thirteen NixOS hosts run as unprivileged LXC containers on a single
Proxmox node, plus one nix-darwin Mac. Containers are provisioned by OpenTofu, built from
CI-published base images, and configured entirely from this flake. Most have an ephemeral
root filesystem that is wiped on every boot.

**The invariant everything serves:** any host can be destroyed and rebuilt from this
repository alone. If a change only works because of state you created by hand on a running
box, it is wrong.

---

## How it fits together

Four systems hand off to each other. Knowing the seams is most of the job.

**1. OpenTofu creates the container.** `provisioning/main.tf` declares one module block per
host. On apply it creates the LXC, and a `local-exec` provisioner SSH-scans the new box,
converts its ed25519 host key to an age key with `ssh-to-age`, splices that key into
`.sops.yaml`, and runs `sops updatekeys` over `secrets/*`. A matching destroy-time
provisioner removes the key and re-encrypts. **You never edit `.sops.yaml` age keys by
hand** — apply and destroy own that file's anchor list.

For impermanent hosts the module also creates the separate volumes that survive the
rootfs wipe (`/boot`, `/nix`, `/persistent`, `/sbin`, `/bin`). Only `/persistent` is set
`backup = true`. Attaching the hookscript that actually does the wiping is a **separate,
ungated variable** (`custom_hookscript`) — `rootfs_impermanence = true` alone gets you the
volumes and no rollback. See Provisioning.

**2. The container boots a CI base image.** GitHub Actions builds two LXC images per
release tag via nixos-generators and attaches them to a GitHub Release. These are just
enough NixOS to be SSH-reachable and sops-capable — they are a bootstrap, not the host.

**3. The first `nixos-rebuild switch` applies the real config.** This is where the host
becomes itself: impermanence turns on, services start, secrets get decrypted using the
host key that tofu already registered.

**4. `system.autoUpgrade` keeps it current.** Every host pulls
`github:MayurSaxena/nix-homelab` daily (18:00 UTC + up to 120min jitter) and switches. A
separate daily workflow runs `nix flake update`, commits `flake.lock` straight to main, and
force-pushes the `nightly` tag — which re-triggers the image build. So a merged change
reaches every host within a day without anyone touching a container.

The consequence worth internalising: **pushing to main deploys.** There is no staging step.

---

## Layout

```
flake.nix              Inputs, both config builders, every host registration
.sops.yaml             Which age keys decrypt which secret files (tofu-managed)
hosts/<name>.nix       One file per host — service config and little else
modules/nixos/         Base module + the custom.* capability modules
modules/macos/         nix-darwin equivalents (deliberately not shared with NixOS)
modules/home-manager/  The Mac user's dotfiles and personal secrets
modules/beszel-agent.nix   Monitoring agent (shared, imported by the NixOS base)
provisioning/          OpenTofu: container definitions and base-image downloads
secrets/               SOPS-encrypted files
assets/                Files committed in the clear — hookscript, pubkeys, and the
                       deliberately-committed builder *private* key. Anything genuinely
                       secret belongs in secrets/, not here.
util/                  pve-auth.sh — sourced, not executed, for 2FA against the PVE API
```

There is no `overlays/` or `packages/` directory. The README still mentions them; it is
stale. Do not recreate them.

---

## The two builders

```nix
mkNixOSConfig  = paths: nixosSystem { specialArgs = {inherit inputs outputs;};
                                      modules = [./modules/nixos] ++ lib.toList paths; };
mkDarwinConfig = paths: darwinSystem { specialArgs = {inherit inputs outputs;};
                                       modules = [inputs.determinate.darwinModules.default]
                                                 ++ lib.toList paths; };
```

Three things follow, and all three catch people out:

- **`modules/nixos/default.nix` is always module zero.** A NixOS host never imports it.
  `mkDarwinConfig` is asymmetric — it does *not* inject `modules/macos/base.nix`, so the Mac
  host file imports its own base explicitly.
- **No `system` argument is passed**, which is why every host file must set
  `nixpkgs.hostPlatform` itself.
- **`lib.toList` means the argument may be a path or a list of modules.** Bare path is the
  rule — there are exactly two list-form call sites in the whole flake: the `base-lxc-remote`
  CI variant (which toggles `custom.remote-builds.enable` on the shared base file), and
  `minecraft`, which is how `nixpkgs.overlays` gets applied since host files are forbidden
  from setting it.

`specialArgs` is the whole extra-args surface: `inputs` and `outputs`. No *NixOS* host file
reads `outputs` — it's destructured there for uniformity. The one real consumer is
`hosts/Mayurs-MacBook-Pro.nix`, which forwards it into home-manager via `extraSpecialArgs`,
so don't strip it from that file.

### What every NixOS host already has

Do not write any of this in a host file — it is all in the base module. The list is
representative, not exhaustive; **`modules/nixos/default.nix` is the authority**, so read it
before adding anything system-wide:

`system.stateVersion` · `nixpkgs.config.allowUnfree` · `nix.gc` / `nix.optimise` /
`nix.settings` · `time.timeZone` · `system.autoUpgrade` · `networking.firewall.enable` ·
`services.openssh` and root's authorized keys (YubiKey sk-keys only) · `users.mutableUsers = false` ·
`sops.defaultSopsFile` and `sops.age.sshKeyPaths` ·
`age`/`age-plugin-yubikey`/`sops`/`git` in `systemPackages` · `environment.shellAliases` ·
`programs.ssh.extraConfig` · `custom.domain`

Also in scope automatically, via the base module's imports: sops-nix, NUR (`pkgs.nur`), the
out-of-tree `services.scrobblex` option, the upstream impermanence module (pulled in
transitively by `modules/nixos/impermanence.nix`), and all five `custom.*` modules.

**Never set `networking.hostName`** — `proxmox-lxc.nix` sets `manageHostName = false` and
Proxmox supplies it.

---

## The `custom.*` namespace

All repo-local options live under `custom.*`. Five toggles are the standard host preamble:

| Option | What enabling it does | When to turn it off |
|---|---|---|
| `custom.proxmox-lxc.enable` | Disables resolved/resolvconf so Proxmox's resolv.conf wins; creates the `lxc_share` group at gid 10000 (maps to 110000 on the PVE host) | Never — every host sets it |
| `custom.impermanence.enable` | Persists SSH host keys, machine-id, `/var/log`, `/var/lib/{nixos,systemd}`; creates `/persistent/var/lib/private` at 0700 | When the host genuinely needs a large mutable rootfs |
| `custom.remote-builds.enable` | Delegates builds to `nix-builder.home.internal` **and** adds it as a substituter | On `nix-builder` itself (would point at itself) |
| `custom.root-password.enable` | Root password from `secrets/common.yaml` via `neededForUsers` | Headless hosts with no console consumer |
| `custom.beszel-monitoring-agent.enable` | Monitoring agent; also takes `extraFilesystems` | Never — every host sets it |

Plus `custom.domain` (default `home.mayursaxena.com`) and, on macOS only,
`custom.remote-builds-mac.*`.

**Write all five explicitly, including `false`, with a comment when you deviate.** Eleven of
thirteen hosts set all five true. `nix-builder` disables impermanence (a wiped Nix store
defeats a build cache), remote-builds (it would point at itself) and root-password;
`minecraft` disables impermanence and remote-builds.

Note the *comment* half of that rule is aspirational: of those five disabled toggles only
`nix-builder`'s impermanence actually carries an explanation. The other four are bare. That's
drift — comment yours anyway.

---

## Host files

The fixed part is small. Everything after it is judgement.

```nix
{inputs, outputs, config, ...}: {
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;
  custom.impermanence.enable = true;
  custom.remote-builds.enable = true;
  custom.root-password.enable = true;
  custom.beszel-monitoring-agent.enable = true;

  # ... service config, secrets, persistence — all judgement, see below
}
```

Keep the five toggles in that order as a contiguous block. Add to the argument head only
what you use: `pkgs` when you name a package, a `let domain = config.custom.domain;` binding
only under the test below. **Never add `lib`** — no host file uses it (`sabnzbd.nix`
destructures it unused; that's a leftover, not a pattern).

### Writing the `services.*` block

This repo has essentially no house style here, because the block's shape is not this repo's
decision — it's whatever the upstream module offers. **Read the nixpkgs module for the
service at the revision pinned in `flake.lock`** (which moves daily; never write service
config from memory). From it, establish: does it expose `openFirewall`? a `dataDir`/
`stateDir`? a `user`/`group`? a settings attrset you can push config into? an env-file hook?

Push into Nix everything the module exposes. When it exposes nothing — `services.bazarr` has
no settings and no env-file support at all — say so in a comment and record where the
imperative state lives, as `servarr.nix` does.

### Opening the port

Four strategies exist and you cannot tell which applies without reading the module:

- `openFirewall = true` — most services
- `openFirewall` plus module-specific port lists — technitium's `firewallUDPPorts`/`firewallTCPPorts`
- No firewall support at all → write `networking.firewall.allowedTCPPorts` yourself, and
  prefer deriving it (`[config.services.paperless.port]`) over a literal
- `openFirewall` plus manual ports for a sidecar protocol the module doesn't know about —
  minecraft's Geyser/Bedrock UDP+TCP 19132

### Do you need `let domain = config.custom.domain;`?

Only if the service's own config must emit its public hostname — a URL base it advertises, a
Host-header allowlist, a CSRF/trusted-origin list. **Test:** scan the block you just wrote
for any string that would be wrong if the base domain changed.

Being proxied through Caddy is *not* sufficient — plex, overseerr and servarr are all
proxied and none of them reference `domain`. Don't add an unused binding.

### Do you need `imports`?

Almost never. Exactly one host has one (`minecraft`, for `inputs.nix-minecraft.nixosModules.minecraft-servers`).
Anything in nixpkgs needs no import, and the base module already brings in sops-nix, NUR,
scrobblex, impermanence and the `custom.*` modules. Adding a third-party module is a
three-place change: flake input, host `imports`, and — if it needs an overlay — an inline
module list in `flake.nix`, never `nixpkgs.overlays` in the host file.

---

## Persistence — the decision procedure

This is where mistakes are silent and expensive. On an impermanent host the root filesystem
is rolled back to a blank ZFS snapshot on every boot; anything not declared here is gone.

The base module already persists `/var/log`, `/var/lib/nixos`, `/var/lib/systemd`,
`/etc/machine-id` and the SSH host keys. **Never redeclare those.**

### Step 1 — is a block needed at all?

If `custom.impermanence.enable = false`, write nothing. If true, it still might be nothing:
`homepage-dashboard.nix` is 300+ lines, impermanent, and has no persistence block, because
its config is fully generated from Nix and its secrets are re-decrypted from SOPS each boot.
Decide from whether the service writes state *you care about surviving*, not from the toggle.

### Step 2 — find out how the service stores state

Do not guess. Ask the built system:

```bash
nix eval .#nixosConfigurations.<host>.config.systemd.services.<unit>.serviceConfig
```

Read `DynamicUser`, `StateDirectory`, `StateDirectoryMode`, `User`, `Group`. If that's
awkward, build the toplevel and read `result/etc/systemd/system/<unit>.service`, or read the
nixpkgs module at the pinned revision.

### Step 3 — pick the shape from `DynamicUser`

`DynamicUser` and `StateDirectory` are two different axes and it's worth keeping them apart:

- **`StateDirectory=<name>`** gives you the *name*. systemd creates the directory and chowns
  it to the unit's `User`/`Group` on every start.
- **`DynamicUser=true`** changes the *path and the ownership model*. There is no such user at
  activation time — systemd allocates a UID when the unit starts — so state goes to
  `/var/lib/private/<name>` with a `/var/lib/<name>` symlink, and systemd owns permissions
  inside the `0700` parent the base module creates.

That second point is the whole reason the two shapes differ: for a `DynamicUser` service you
**cannot** name an owner, because the user doesn't exist yet.

```nix
environment.persistence."${config.custom.impermanence.persistence-root}" = {
  directories = [
    # Static user — the user exists at activation, so you can name it.
    { directory = "/var/lib/radarr"; user = "radarr"; group = "radarr"; mode = "0750"; }

    # DynamicUser — bare attrset, NO user/group/mode. Naming one is impossible;
    # systemd allocates the UID at runtime and manages ownership itself.
    { directory = "/var/lib/private/prowlarr"; }
  ];
};
```

**Do you *have* to spell out `user`/`group`/`mode` for a static-user service?** It depends on
whether the unit sets `StateDirectory=`:

- If it does, systemd chowns the directory at every start, so the bind-mounted directory's
  own ownership self-corrects and the explicit values are belt-and-braces. `sabnzbd.nix`
  relies on exactly this and persists `/var/lib/sabnzbd` bare.
- If it doesn't — the directory is created by a `preStart`, a tmpfiles rule, or the
  application itself — nothing fixes ownership, the bind mount stays root-owned, and the
  service fails on first boot after a rollback. Then the explicit values are load-bearing.

Since you can't tell which without checking, and being explicit also documents intent, the
repo's dominant style is to spell them out. Do that unless you've confirmed otherwise.

`servarr.nix` is the proof that this is per-service: four *arr services on one host, and
radarr/sonarr/bazarr take the first form while prowlarr takes the second. A doc that told you
"use `/var/lib/private/<service>`" would cause silent data loss on three of them.

### Step 4 — get the directory NAME right

It is the systemd `StateDirectory`, which frequently differs from the NixOS option name, the
package name, the host name, and the flake key. Real divergences in this repo:

- `services.seerr` → `/var/lib/private/jellyseerr`, on a host named `overseerr`
- `services.actual` → `actual`, on a host named `actualbudget`
- `services.paperless.configureTika = true` → `tika`, a name appearing nowhere in the config you wrote

Getting this wrong fails silently: the bind mount points at an unused directory and the real
state still evaporates on reboot.

### Step 5 — enumerate every unit the option set created

One `enable = true` can oblige several entries. `services.paperless` with
`database.createLocally` and `configureTika` produces four — paperless, redis-paperless,
postgresql, tika — each with different ownership. (`configureTika` also starts Gotenberg,
correctly persisted nowhere because it's stateless.)

To enumerate: diff `nix eval .#nixosConfigurations.<host>.config.systemd.services --apply builtins.attrNames`
against a build without your service.

### Step 6 — mode

There is no repo-wide default. Observed: redis 0700, postgresql 0750, the *arrs 0750, caddy
and plex 0755, paperless deliberately omitting it. Read `StateDirectoryMode` or the module's
own tmpfiles rules. Too tight breaks startup; too loose can make a hardened unit refuse to
start. Omitting is correct when the service doesn't care.

### When you also need `systemd.tmpfiles.rules`

Usually never — exactly one host does it. Add one when the `/persistent`-side directory must
pre-exist with the right owner before the unit's own pre-start runs. `paperless.nix` is the
sole example; copy its idiom of interpolating `config.services.paperless.dataDir` rather than
hardcoding a path, but don't copy the rule itself unless you've established the same need.
The symptom that you need it is a permission failure on first boot after a rollback.

### PVE bind mounts and `lxc_share`

If the service reads or writes storage that lives on the Proxmox host, it needs to be in the
`lxc_share` group. Two spellings exist and which is available depends on upstream: set the
service's own `group = "lxc_share"` option, or append via `users.users.<x>.extraGroups`.
Pick one deliberately (`sabnzbd` redundantly does both).

---

## Secrets

Every secret is SOPS-encrypted. Each host decrypts with an age key derived from its SSH host
key; the `msaxena-keys` group (Mac SSH key + two YubiKeys) can decrypt everything.

### Which file

Ask whether more than one host needs the value **at runtime**.

- **`secrets/common.yaml`** — encrypted to `*all-keys`. Today holds exactly one key,
  `passwords/root`.
- **A dedicated per-host file** — the default for anything service-specific. Encrypted to
  `*msaxena-keys` plus that one host, so compromising one container doesn't expose another's
  credentials. One file per *host* is right even when several services share it
  (`servarr.env` feeds radarr, sonarr and prowlarr, each picking its own variable by prefix).
- **`secrets/msaxena.yaml`** — `*msaxena-keys` only, no host key, decrypted interactively by
  YubiKey via home-manager on the Mac.

**A new secret file needs a `path_regex` rule added to `.sops.yaml` by hand, before you
create it.** Always include `*msaxena-keys`, plus only the hosts that need runtime access:

```yaml
- path_regex: secrets/my-service.env$
  key_groups:
    - age:
      - *msaxena-keys
      - *my-host
```

(Host anchors themselves are managed by tofu. You add the rule; tofu maintains the keys.)

Then `sops secrets/my-service.env`.

### Extension → `format` → what the secret NAME means

These are one decision, and it's the most load-bearing rule here:

- **`dotenv`, `ini`, `binary`** — sops-nix **ignores** the secret's name and writes the whole
  decrypted file to one path. The name is a free-choice label, hence the `"<service>-secrets"`
  convention. `"caddy-secrets"` works even though no such key exists inside `secrets/caddy.env`.
- **`yaml`, `json`** — the name **is** a slash-separated lookup path into the decrypted tree.
  That's how `"passwords/timemachine"` and `"passwords/msaxena"` pull two scalars out of one
  `fileserver.yaml`.

Note there's no naming rule for the *file*: `secrets/homepage-dashboard-secrets.env` is
declared as `"homepage-secrets"` on a host whose flake key is `homepage`.

### The remaining choices

- **`owner`/`group`** — default is root:root 0400. Set them only when a non-root process
  opens the file itself (sabnzbd's `secretFiles`), and derive them symbolically from
  `config.services.<x>.user` so a rename can't desync. You usually do *not* need them for
  `environmentFile`, because systemd reads that as root before dropping privileges.
- **`neededForUsers = true`** — only for values consumed while users are created, in practice
  only `hashedPasswordFile` (required here because `users.mutableUsers = false`). It
  relocates the secret to `/run/secrets-for-users` and forbids a non-root owner, so never
  combine it with `owner`. The root password is the only instance.
- **`restartUnits`** — **set it.** The intent is that a service picks up a rotated secret
  (env var, token, API key) without anyone restarting it by hand, so any unit that reads the
  secret at startup belongs in the list. Only `homepage` and `sabnzbd` currently set it;
  caddy, paperless, plex and servarr are drift, not precedent. For a file several services
  share, list every unit that reads it. The unit name is *not* derivable from the secret name
  or the `services.*` attribute — it's whatever unit the module actually defines.

### How the path gets consumed

Entirely upstream's API, with no repo convention. Five shapes already exist:
`environmentFile` (singular string), `environmentFiles` (list), `secretFiles` (list, paired
with `configFile = null`), `hashedPasswordFile`, and an explicit `path =` relocation in
home-manager. Some modules accept none at all (bazarr) — then the honest answer is a
documented manual migration, not a workaround.

The file's *internal* shape is dictated by the consuming application and fails silently at
runtime, not at build time: dotenv variable names must be exactly what the app reads
(`CF_API_TOKEN` interpolated as `{$CF_API_TOKEN}` in the Caddyfile; the *arr
`SERVICE__AUTH__APIKEY` double-underscore convention).

---

## Writing a `custom.*` module

Reach for one when a *capability* should be switchable per host — the test is whether a host
would ever want it off. Shared values that are always present can be a bare option on
`default.nix` (that's what `custom.domain` is).

The observed pattern:

```nix
{config, lib, pkgs, ...}: let
  cfg = config.custom.my-feature;
in {
  options.custom.my-feature = {
    enable = lib.mkEnableOption "my feature";
    remote-host = lib.mkOption {
      type = lib.types.str;
      default = "...";
      example = "...";
      description = "...";
    };
  };

  config = lib.mkIf cfg.enable { /* ... */ };
}
```

Judgement inside that shape:

- **Bind `cfg` only when the body needs a non-`enable` value.** remote-builds, beszel and
  impermanence all bind because they read one; `proxmox-lxc` and `root-password` are
  enable-only and spell out `config.custom.<x>.enable` inline.
- **Pick the narrowest accurate type** — `types.path` for `persistence-root`, `types.str` for
  hostnames, `listOf (submodule { options = ...; })` with `default = []` for structured lists.
- **Naming** — kebab-case feature names. Sub-options are camelCase when following NixOS
  convention (`extraFilesystems`) and kebab-case for repo-local coinages (`remote-host`).
  Match the file you're editing.
- **Document side effects at the point of compromise.** Enabling the beszel agent sets
  `services.dbus.implementation = "broker"` host-wide to dodge an early-boot deadlock, and
  says so in a comment. Match that.
- **Check it's safe for the CI base images.** Both images build on a stock runner with no
  remote builder, no age key and no homelab network. `sops.secrets` *declarations* are fine
  (decryption happens at activation, and `validateSopsFiles = false` stops eval reading the
  encrypted files), but anything referenced via `environment.etc` must exist in-repo.
- **Do not try to share a module with macOS.** `remote-builds` deliberately exists twice with
  byte-for-byte parallel option declarations and completely divergent `config` bodies,
  because Determinate Nix makes nix-darwin's `nix.*` options inert. Separate module,
  `-mac`-suffixed option, duplicated declarations.
- **Does it need a Terraform counterpart?** If it changes storage or boot behaviour, yes —
  `custom.impermanence` is meaningless without `rootfs_impermanence`, `custom_hookscript` and
  sized volumes on the tofu side.

---

## Provisioning

One module block per host in `provisioning/main.tf`. `hostname` must equal the flake
attribute key. Read the existing blocks for current per-host values rather than trusting
numbers written here — they're tuned per service and change.

**What to decide:**

- **VLAN** — a network-role decision, not per-service. Observed membership: `10` holds dns,
  caddy and beszel-hub; `40` holds minecraft (untrusted external exposure); `20` holds
  everything else and is the default for anything new. Don't over-infer a rule for `10` from
  the word "infrastructure" — `nix-builder` is depended on by every other host and still sits
  on `20`. Unless a host is clearly one of those two special cases, it's `20`. Tags do not
  predict VLAN.
- **Memory / CPU** — derive from the nearest analogue. 2 cores is standard; 4 only for
  genuinely parallel or transcoding work. Because builds are delegated to `nix-builder`, you
  do **not** size RAM for compilation.
- **Disks** — which variables apply depends on impermanence. If impermanent, leave
  `rootfs_size_gb` at its default and set `nix_fs_size_gb` (to the closure size) and
  `persistent_fs_size_gb` (to the service's state). If not, size `rootfs_size_gb`.
  These have defaults (2 and 4), so **omitting them under-provisions silently** rather than
  erroring — `beszel-hub` already does this and gets a 4GB `/nix`.
- **`custom_hookscript`** — the genuinely dangerous omission. It also defaults to null, and
  without it a host is impermanent in name only: the flake enables impermanence but nothing
  ever rolls the subvolume back.
- **`additional_mount_points`** — only for storage on the PVE host. Three coupled follow-ups:
  point the service at the container-side path, add its user to `lxc_share`, and optionally
  register the path in `custom.beszel-monitoring-agent.extraFilesystems`. The path choice
  itself is a judgement call — servarr mounts all of `/mnt/MediaBox` while sabnzbd mounts only
  `/mnt/MediaBox/usenet`, deliberately, so completed downloads can be hardlinked within one
  filesystem.
- **`tags`** — only two rules are mechanical: `terraform` first, and `host-mount` iff
  `additional_mount_points` is set. The rest is an open vocabulary.

### Choosing `ct_template_id`

CI publishes **two** images, each for the `prod` and `nightly` tags — four resources in
`provisioning/images.tf`. Impermanence is no longer a template dimension: tofu creates the
persistent mounts itself and the host's own flake enables impermanence on first switch.

- **Axis 1 — `standard` vs `remotebuild`.** This is purely a bootstrap question: can you
  reach `nix-builder` over SSH from the machine you're deploying *from*? If yes, `standard`
  is correct for any host, and you do the first switch with `--build-host`/`--target-host`.
  `remotebuild` pre-bakes `custom.remote-builds.enable` and is the fallback for when you
  can't. It matters because `nixos-rebuild` reads the *currently active* system's `nix.conf`
  to decide where to build — a freshly-imported vanilla container has no build machines yet,
  and these LXCs are sized for their service, not for compiling.
- **Axis 2 — `prod` vs `nightly`.** `prod` for hosts everything else bootstraps through
  (today `nix-builder` and `dns`); `nightly` otherwise.

Derive the valid resource names by reading `images.tf`, and cross-check its URLs against the
`RELEASE_PATH=` basenames in `.github/workflows/generate-lxc.yml` — those two must agree or
apply fails on a 404.

Changing `ct_template_id` on an existing host is safe: the module sets
`ignore_changes = [operating_system["template_file_id"]]`, so it only affects newly-created
containers.

### Adding a container

1. Write `hosts/<name>.nix`, register it in `flake.nix`.
2. Add the module block to `provisioning/main.tf`.
3. If it needs secrets, add the `.sops.yaml` rule and create the file.
4. Commit and push (autoUpgrade and the flake URL both read from GitHub, not your worktree).
5. `cd provisioning && tofu apply` — creates the LXC and registers its age key automatically.
6. First switch, from a machine that can reach both:

   ```bash
   nixos-rebuild switch \
     --flake github:MayurSaxena/nix-homelab#<host> \
     --build-host nix@nix-builder.home.internal \
     --target-host root@<container-ip> \
     --use-remote-sudo
   ```

`tofu destroy` removes the host's age key and re-encrypts on the way out.

---

## Common operations

```bash
nix fmt .                                                    # alejandra
nix build .#nixosConfigurations.<host>.config.system.toplevel  # check without switching
nix eval .#nixosConfigurations.<host>.config.systemd.services.<unit>.serviceConfig
nix flake update [<input>]
sops secrets/<file>
nixos-rebuild switch --flake .#<host> --target-host root@<ip>
```

---

## Style

1. `nix fmt .` (alejandra) before committing.
2. Local options always under `custom.*`.
3. Destructure only what you use in a host file's argument head.
4. **Comment the rationale wherever a choice is surprising.** This is the strongest
   convention in the repo — the committed builder key, D-Bus broker mode, the 0700 on
   `/var/lib/private`, every disabled toggle. Match that density.
5. Derive rather than hardcode: `[config.services.paperless.port]`, not `[8000]`.
6. Commit messages in imperative present tense.

---

## Guardrails

- Don't edit `flake.lock` by hand — `nix flake update`.
- Don't edit `.sops.yaml` **age keys** by hand — tofu owns them. (You do add `path_regex`
  rules by hand.)
- Don't commit an unencrypted secret.
- Don't set `nixpkgs.overlays` in a host file — use an inline module list in `flake.nix`.
- Don't set `networking.hostName`, or any of the base-module settings listed above.
- Don't add to `environment.systemPackages` in a host file unless it's genuinely global.
- Don't skip persistence for a new service on an impermanent host — the failure is silent
  and only shows up after a reboot.

---

## Known drift

Things that are currently inconsistent, so you don't "fix" them into the wrong shape or
copy them as precedent:

- `README.md` documents `overlays/` and `packages/` directories that no longer exist.
- `restartUnits` is missing on caddy, paperless, plex and servarr. The intent is that every
  service restarts when its secrets change, so treat those as unfinished rather than as a
  deliberate opt-out.
- `sabnzbd.nix` persists `/var/lib/sabnzbd` bare while every comparable static-user host
  spells out `user`/`group`/`mode`. It is safe — the unit sets `StateDirectory=`, so systemd
  chowns on start — just less explicit than its neighbours.
- `provisioning/main.tf:4` — the `proxmox_virtual_environment_file` resource that uploads
  `assets/rootfs-impermanence.sh` hardcodes `node_name = "proxmox"`, while every `module`
  block below it passes `pve_node_name = var.pve_node_name`. A second node or a rename would
  break the hookscript upload only.
- The create-time provisioner's only readiness guard before `ssh-keyscan` is a 5-second
  sleep; on a slow node it can write an empty age key into `.sops.yaml`.
- `sops.templates` is available via sops-nix but used nowhere, so there's no in-repo
  precedent for embedding a secret inside an otherwise-declarative config file. Today the
  ad-hoc answer is an activation script (`files.nix`).
