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
hand** — apply and destroy own that file's anchor list. The provisioner deliberately stops
there: it never commits, pushes, or runs the first switch, because a multi-minute remote
build and a YubiKey-gated SSH prompt don't belong inside a provisioner that gates `apply`'s
success or failure. That's `provisioning/onboard-host.sh`'s job — run by hand, or by Claude,
once `tofu apply` finishes.

For impermanent hosts the module also creates the separate volumes that survive the
rootfs wipe (`/boot`, `/nix`, `/persistent`, `/sbin`, `/bin`). Only `/persistent` is set
`backup = true`. Attaching the hookscript that actually does the wiping is a **separate,
ungated variable** (`custom_hookscript`) — `rootfs_impermanence = true` alone gets you the
volumes and no rollback. See Provisioning.

**2. The container boots a CI base image.** GitHub Actions builds one LXC image on every push
of the `nightly` tag via nixos-generators and attaches it to a GitHub Release. This is just
enough NixOS to be SSH-reachable and sops-capable — a bootstrap, not the host.

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

There is no `overlays/` or `packages/` directory — scrobblex moved out to NUR. Do not
recreate them; see *When a package isn't in nixpkgs*. An overlay that a host genuinely needs
is applied from an inline module list in `flake.nix`.

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
  rule — there is exactly one list-form call site in the whole flake: `minecraft`, which is
  how `nixpkgs.overlays` gets applied since host files are forbidden from setting it.

`specialArgs` is the whole extra-args surface: `inputs` and `outputs`. **Nothing in the repo
actually reads `outputs`** — every host destructures it for uniformity, and
`hosts/Mayurs-MacBook-Pro.nix` forwards it into home-manager via `extraSpecialArgs` where
`modules/home-manager/msaxena.nix` ignores it too. Keep passing it for consistency; don't go
looking for a consumer.

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
| `custom.root-password.enable` | Root password from `secrets/common.yaml` via `neededForUsers` | Only `nix-builder` turns it off, uncommented — treat as unexplained drift, not a rule. The password's only consumer is PVE console login |
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
    # (caddy leaves services.caddy.group at its default, so the caddy group exists.)
    { directory = "/var/lib/caddy"; user = "caddy"; group = "caddy"; mode = "0755"; }

    # DynamicUser — bare attrset, NO user/group/mode. Naming one is impossible;
    # systemd allocates the UID at runtime and manages ownership itself.
    { directory = "/var/lib/private/prowlarr"; }
  ];
};
```

**Do you *have* to spell out `user`/`group`/`mode` for a static-user service?** It depends on
whether *anything upstream* re-asserts ownership after the bind mount appears. Three cases:

1. **The unit sets `StateDirectory=`** — systemd creates and chowns the directory to
   `User`/`Group` on every start, so ownership self-corrects. Your explicit values are
   belt-and-braces.
2. **The module ships a `systemd.tmpfiles` `d` entry carrying user/group** — a `d` line
   adjusts mode and ownership on a directory that already exists, and tmpfiles runs every
   boot after the bind mounts. This also self-corrects. Several nixpkgs modules do this
   *instead of* `StateDirectory=`, so "no StateDirectory" does not imply "broken".
3. **Only a create-if-missing `preStart`, or the application itself** — e.g. an
   `ExecStartPre` that runs `install -d` guarded by `! test -d` never touches an existing
   directory. Nothing self-corrects, the bind mount stays root-owned, and the service fails
   on first boot after a rollback. Here the explicit values are the only thing that works.

You cannot tell which case you're in without checking, and being explicit also documents
intent, so the repo's dominant style is to spell them out. Do that unless you've confirmed
otherwise.

**The `group` you name must be the unit's *effective* `Group=`, and must actually exist.**
Many nixpkgs modules only define `<service>` as a group when the module's own `group` option
is left at its default — override `group` (e.g. to `lxc_share`) and the `<service>` group is
never created. impermanence's `create-directories.bash` runs `chown "$user:$group"` under
`set -o errexit`, so naming a group that doesn't exist fails when the persistent directory is
first created. Read the module's `users.groups` block, don't assume `user == group`.

`servarr.nix` is the proof that this is per-service: four *arr services on one host, and
radarr/sonarr/bazarr take the first form while prowlarr takes the second. A doc that told you
"use `/var/lib/private/<service>`" would cause silent data loss on three of them.

### Step 4 — get the directory NAME right

It is the systemd `StateDirectory`, which frequently differs from the NixOS option name, the
package name, the host name, and the flake key. Real divergences in this repo:

- `services.seerr` → `/var/lib/private/jellyseerr`, on a host named `overseerr` — and the
  upstream module gates that name on `system.stateVersion`, so it changes at 26.05. Exactly
  why you read the module instead of memorising names.
- `services.actual` → `actual`, on a host named `actualbudget`
- `services.paperless.configureTika = true` → `tika`, a name appearing nowhere in the config you wrote

Getting this wrong fails silently: the bind mount points at an unused directory and the real
state still evaporates on reboot.

### Step 5 — enumerate every state directory the option set created

One `enable = true` can oblige several entries, and **unit names and state-directory names do
not line up**. `services.paperless` with `database.createLocally` and `configureTika` yields
four persistence entries — paperless, redis-paperless, postgresql, tika — but produces
roughly nine units to get there (`paperless-scheduler`, `paperless-task-queue`,
`paperless-consumer`, `paperless-web`, `paperless-secret-key`, plus redis-paperless,
postgresql, tika and gotenberg). There is no `paperless.service` at all, so Step 2's eval has
to name a real unit. Gotenberg is correctly persisted nowhere — it's a stateless converter.

To enumerate: diff `nix eval .#nixosConfigurations.<host>.config.systemd.services --apply builtins.attrNames`
against a build without your service, then map each unit to its `StateDirectory` — several
units routinely share one directory.

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

**Use the module's own `group` when it has one** — that sets the process's primary group, so
an `extraGroups` line on top of it is redundant. Reach for `extraGroups` only when the
service's group is pinned to something else you need to keep. `plex` is the live example:
`services.plex.group = "plex"` owns its state directory, so `lxc_share` has to arrive as a
supplementary group. `files.nix` likewise, since `timemachine` and `msaxena` are plain
`isNormalUser` accounts with no service `group` option at all.

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
- **`secrets/msaxena.yaml`** — `*msaxena-keys` only, no host key, decrypted by a plugged-in
  YubiKey (no PIN or touch prompt) via home-manager on the Mac.

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

**For a brand-new host**, that host's anchor doesn't exist until `tofu apply` creates it —
see *Provisioning → Adding a container*, which provisions the container before any of its
secrets specifically to avoid a `.sops.yaml` chicken-and-egg deadlock. This only matters for
a host's *first* secret; adding a secret to an already-onboarded host has no such trap.

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
  only `hashedPasswordFile` (required because `/run/secrets` isn't populated yet at the point
  activation creates users). It relocates the secret to `/run/secrets-for-users` and forbids
  a non-root owner, so never combine it with `owner`. The root password is the only instance.
- **`restartUnits`** — **set it on any secret a systemd unit reads at startup**, so a rotated
  value takes effect without a manual restart. Every such secret in the repo now does. For a
  file several services share, list *every* unit that reads it — `servarr.env` names radarr,
  sonarr and prowlarr but not bazarr, whose module has no `environmentFiles` support.
  The unit name is *not* derivable from the secret name or the `services.*` attribute: it's
  whatever unit the module actually defines, and there may be several. `services.paperless`
  puts `environmentFile` in a shared `defaultServiceConfig` consumed by four units and
  defines no `paperless.service` at all.
  It does **not** apply to secrets no unit consumes. Two live exceptions: `passwords/root`
  is read while users are created (`neededForUsers`), and `files.nix`'s samba passwords are
  read by an activation script that runs on every switch — restarting smbd would change
  nothing, since smbpasswd has already written them into the passdb.

### How the path gets consumed

Entirely upstream's API, with no repo convention. Six shapes already exist:
`environmentFile` (singular string), `environmentFiles` (list), `secretFiles` (list, paired
with `configFile = null`), `hashedPasswordFile`, an explicit `path =` relocation in
home-manager, and a raw read of the decrypted path from an activation script (`files.nix`,
which hardcodes `/run/secrets/passwords/$user` — don't copy the hardcoding). Some modules
accept none at all (bazarr) — then the honest answer is a documented manual migration, or an
activation script where there's nothing to migrate.

The file's *internal* shape is dictated by the consuming application and fails silently at
runtime, not at build time: dotenv variable names must be exactly what the app reads
(`CF_API_TOKEN` interpolated as `{$CF_API_TOKEN}` in the Caddyfile; the *arr
`SERVICE__AUTH__APIKEY` double-underscore convention).

---

## Writing a `custom.*` module

Reach for one when a *capability* should be switchable per host — the test is whether a host
would ever want it off. Shared values that are always present can be a bare option on
`default.nix` (that's what `custom.domain` is).

The shape to write (note the in-repo modules all use the wider head
`{inputs, config, pkgs, lib, ...}` and carry `inputs`/`pkgs` even where unused —
`root-password.nix` uses neither; trim yours to what you actually reference):

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

## When a package isn't in nixpkgs

Work down this list; don't skip a rung because the one below is quicker.

1. **It's in nixpkgs** — just use it. `flake.lock` moves daily, so check the current pin
   rather than assuming from memory.
2. **It isn't, but it could be** — package it for nixpkgs and upstream it. That's the
   preferred home for anything genuinely reusable: it gets CI, review, and other people
   maintaining it after you.
3. **It can't go to nixpkgs** — package it in the owner's own NUR repo,
   [`MayurSaxena/nurpkgs`](https://github.com/MayurSaxena/nurpkgs), registered in NUR as
   `msaxena`.
4. **Never** recreate a local `packages/` or `overlays/` directory. Both existed once, for
   scrobblex, and were deliberately removed when it moved to NUR.

The usual reasons something fails rung 2 are worth knowing, because they're the test for
whether to jump to rung 3: unfree or unredistributable binaries, no tagged releases or stable
versioning, vendored dependencies that can't be fixed-output-hashed, a build that needs
network access, or software too personal or niche to be worth anyone else's maintenance
burden.

### Consuming it

NUR is a flake input (`github:nix-community/NUR`, with `nixpkgs` followed), and its module is
imported on **both** platforms — `inputs.nur.modules.nixos.default` in
`modules/nixos/default.nix`, `inputs.nur.modules.darwin.default` in `modules/macos/base.nix`.
So two shapes are available anywhere without further wiring:

- **A package** — `pkgs.nur.repos.msaxena.<name>`. Nothing in the repo uses one yet, so
  you'd be setting the precedent.
- **A NixOS module** — `inputs.nur.repos.msaxena.modules.nixos.<name>`, imported like any
  other module. `services.scrobblex` is the live example, and it's imported by the *base*
  module, which is why the option exists on every host while only `plex` enables it.

Import a NUR module from the base module only when every host should see the option;
otherwise put it in the one host's `imports`.

Read `nurpkgs` itself for its layout and conventions before adding to it — this document
deliberately doesn't mirror them, since they belong to that repo and would go stale here.

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
  `nix_fs_size_gb` defaults to 4 and `persistent_fs_size_gb` to 2 (as does `rootfs_size_gb`),
  so **omitting them under-provisions silently** rather than erroring — `beszel-hub` already
  does this and gets a 4GB `/nix`.
- **`custom_hookscript`** — the genuinely dangerous omission. It also defaults to null, and
  without it a host is impermanent in name only: the flake enables impermanence but nothing
  ever rolls the subvolume back.
- **`additional_mount_points`** — only for storage on the PVE host. Follow-ups: point the
  service at the container-side path; add its user to `lxc_share` **if** the share is owned
  by the PVE-side `lxc_share` gid (paperless's consume dir is the counterexample — it only
  reads, and takes no group); and optionally register the path in
  `custom.beszel-monitoring-agent.extraFilesystems` to graph it. The path choice
  itself is a judgement call — servarr mounts all of `/mnt/MediaBox` so it can hardlink
  completed downloads into the library within one filesystem, while sabnzbd mounts only
  `/mnt/MediaBox/usenet`, scoped to what it needs. (The rationale isn't recorded in
  `main.tf`; if you rely on it, add a comment there.)
- **`tags`** — only two rules are mechanical: `terraform` first, and `host-mount` iff
  `additional_mount_points` is set. The rest is an open vocabulary.

### Choosing `ct_template_id`

There's no choice to make. CI publishes a single image, rebuilt on every push of the
`nightly` tag — one resource, `nixos-standard-nightly`, in `provisioning/images.tf` — and
every host's `ct_template_id` points at it. There used to be a `prod` tag (never automated;
only a human could push it, and it had gone stale) and a `remotebuild` variant (pre-baked
`custom.remote-builds.enable` for hosts that couldn't reach `nix-builder` during bootstrap);
both are gone now that the first-switch workflow (`provisioning/onboard-host.sh`) always
passes `--build-host`/`--target-host` explicitly, so nothing needs remote-builds pre-baked
into the image.

Changing `ct_template_id` on an existing host is safe: the module sets
`ignore_changes = [operating_system["template_file_id"]]`, so it only affects newly-created
containers.

### Authenticating to the Proxmox API

`provisioning/provider.tf` authenticates as `root@pam` with a password/ticket, not an API
token. **Don't try to move this to a token** — PVE hard-codes several operations, including
setting a container's hookscript (`hook_script_file_id`, which 11 of the 13 hosts set), to
literally require the `root@pam` identity. No role or privilege grant on a token bypasses
this; it's a PVE limitation, not a provider one ([provider issue #570][pve-570],
[PVE bugzilla #2582][pve-bz-2582], unlikely to be fixed). Since almost every host needs a
hookscript, there's no host mix here where token auth would avoid the requirement.

`root@pam` has TOTP enabled, so a plain password isn't enough either. The provider's own
`otp` argument is deprecated and not the right tool — the correct mechanism is a pre-fetched
auth ticket. `util/pve-auth.sh` drives that exchange (calls `/access/ticket`, detects
`NeedTFA`, re-authenticates with `password=totp:<code>`) and exports
`PROXMOX_VE_AUTH_TICKET`/`PROXMOX_VE_CSRF_PREVENTION_TOKEN` for tofu to pick up. Source it
before `tofu plan`/`apply`, from anywhere inside the repo:

```bash
source util/pve-auth.sh
```

The live TOTP code is derived automatically — the script decrypts `proxmox/root_pam-totp-secret`
from `secrets/msaxena.yaml` and computes the current code with `oathtool`, so nothing needs
to be typed in from a phone or authenticator app. Passing a code manually as `$1` still works
as a fallback (`source util/pve-auth.sh 123456`) if the secret isn't set up yet.

The script is fully self-contained — `PROXMOX_VE_ENDPOINT`/`PROXMOX_VE_USERNAME`/
`PROXMOX_VE_INSECURE` default inside it and `PROXMOX_VE_PASSWORD` decrypts from
`proxmox/root_pam-password` in the same secrets file, so `provisioning/.envrc` is no longer a
prerequisite. It's still there as an optional override (e.g. a different endpoint) — anything
you export yourself before sourcing wins over the script's defaults.

[pve-570]: https://github.com/bpg/terraform-provider-proxmox/issues/570
[pve-bz-2582]: https://bugzilla.proxmox.com/show_bug.cgi?id=2582

### Adding a container

If the host needs secrets, provision it *before* creating any of them — otherwise a
`.sops.yaml` rule referencing the new host's (not-yet-existing) age-key anchor makes
`.sops.yaml` unparseable for every `sops` invocation in the repo until the anchor exists,
including `util/pve-auth.sh` itself (it needs `sops` to decrypt the Proxmox credentials
required to run `tofu apply` — the one thing that *creates* the anchor). Doing the tofu step
first avoids the trap entirely rather than working around it.

1. Add the module block to `provisioning/main.tf`.
2. `cd provisioning && tofu apply -target=module.<name>` — creates the LXC and splices its
   age key into `.sops.yaml` automatically. The anchor now exists, so this host's secrets can
   be added normally with no ordering trap.
3. Write `hosts/<name>.nix`, register it in `flake.nix`. If it needs secrets: add the
   `.sops.yaml` rule (see *Secrets → Which file*) and `sops`-encrypt the file directly — the
   anchor already exists, so this is one step, not a bootstrap dance.
4. If the service is proxied through the shared `caddy` host, add its `virtualHosts` entry in
   `hosts/caddy.nix` now too — its own switch happens separately, in step 8.
5. `nix fmt .`, sanity-build: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`.
6. Commit and push everything (autoUpgrade and the flake URL both read from GitHub, not your
   worktree).
7. `provisioning/onboard-host.sh <flake-host-key> <container-ip>` — commits any leftover
   `.sops.yaml`/`secrets/` change if there is one (usually a no-op now, since step 3 already
   committed it), then runs the first switch from a machine that can reach both nix-builder
   and the container:

   ```bash
   nixos-rebuild switch \
     --flake github:MayurSaxena/nix-homelab#<host> \
     --build-host root@nix-builder.home.internal \
     --target-host root@<container-ip> \
     --refresh
   ```

   `--refresh` is required, not optional: a `github:` flake ref is subject to Nix's
   tarball-ttl caching, so a switch run shortly after a push can silently rebuild the
   *previous* commit with no error or warning — only a diff against the store path actually
   deployed reveals it. This applies to *any* manual switch against a `github:` ref for this
   repo, not just onboarding (e.g. redeploying `caddy` right after pushing a fix).

   `<flake-host-key>` is the `nixosConfigurations` attribute name, which isn't always the
   `provisioning/main.tf` module name (`dns-server` → `dns`, `plex-server` → `plex`,
   `fileserver` → `files`). Root SSH is YubiKey-hardware-key-only on every host, so this step
   needs someone at the keyboard — for *both* legs: `root@nix-builder` reuses the same
   YubiKey-gated identity already required for `root@<container-ip>`, rather than the
   `nix@nix-builder` account, whose key (`/etc/nix/remote-builder-key`) is deliberately
   root-only-readable locally and reserved for the unattended `custom.remote-builds`/
   `autoUpgrade` daemon path. Using that account here would force the whole command under
   `sudo`, which then hits a second problem: root's own local `known_hosts` is essentially
   empty, so even `--target-host` fails host-key verification non-interactively.

   The script also self-heals a known first-switch quirk: impermanence's machine-id
   persistence unit almost always fails on a brand-new host's very first activation (the base
   image's first boot already wrote a real `/etc/machine-id` before impermanence gets a
   chance to run its own placeholder workaround), and the script removes the stray file and
   restarts that one unit once it confirms the persisted copy already matches.

8. If step 4 added a caddy vhost, switch `caddy` too — it won't route to the new host until
   its own config is rebuilt (or the next daily `autoUpgrade` picks it up, within a day).
   Caddy fronts every other service, so this deserves its own deliberate switch, not folded
   into step 7's script. **Known gotcha:** `hosts/caddy.nix`'s `caddy.withPlugins` pins a
   `hash` for the Cloudflare DNS-01 plugin's vendored Go modules; because `nixpkgs` moves
   daily via the flake-lock auto-update, caddy's own upstream source can drift and change
   that fixed-output hash even though nothing in this repo changed. A caddy switch failing
   with `hash mismatch in fixed-output derivation` is expected drift, not a real problem —
   update `hash = "sha256-...";` to the reported `got:` value and retry.

`tofu destroy` removes the host's age key and re-encrypts on the way out.

---

## Common operations

```bash
nix fmt .                                                    # alejandra
nix build .#nixosConfigurations.<host>.config.system.build.toplevel  # check without switching
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

- **`sops.templates` is available via sops-nix but used nowhere.** It renders a file whose
  *content* is a Nix string with `config.sops.placeholder."<name>"` markers substituted at
  activation, so a config file can stay fully declarative while embedding a secret that never
  reaches the world-readable Nix store. There is no in-repo precedent, so if you hit "this
  service wants one config file containing both plain settings and a credential", you're
  choosing between introducing it and copying `files.nix`'s activation-script approach.
  Prefer `sops.templates` for anything new — the activation script exists because samba keeps
  its own out-of-band passdb, not because it's the better pattern.
- `minecraft`'s two disabled toggles and `nix-builder`'s remote-builds and root-password
  carry no explanatory comment, unlike `nix-builder`'s impermanence. Comment yours anyway.
