# Recipes for the operations this repo needs most often. `just` with no argument lists them.
#
# Deliberately thin: every recipe is a command you could type by hand, gathered here so the
# flags you have to remember (--build-host, --refresh, the Proxmox auth dance) live in one
# reviewable place instead of your shell history. See CLAUDE.md for what each one is doing
# and why.

# List every recipe.
default:
    @just --list

# Format every Nix file (alejandra).
fmt:
    nix fmt .

# Every host this flake can build, one per line.
hosts:
    @nix eval --raw .#nixosConfigurations --apply \
        'c: builtins.concatStringsSep "\n" (builtins.attrNames c)'

# Build a host without switching. Proves it evaluates and builds, nothing more.
check host:
    nix build .#nixosConfigurations.{{host}}.config.system.build.toplevel

# Build this Mac without switching.
check-mac:
    nix build .#darwinConfigurations.Mayurs-MacBook-Pro.config.system.build.toplevel

# Evaluate every host and the Mac without building anything: what CI does on every push.
check-all:
    nix flake check --no-build --all-systems

# The linters CI runs (statix, deadnix), from the flake's devShell.
lint:
    nix develop --command statix check .
    nix develop --command deadnix --fail --no-lambda-pattern-names .

# Read a unit's serviceConfig, for working out persistence (CLAUDE.md step 2).
unit host name:
    nix eval .#nixosConfigurations.{{host}}.config.systemd.services.{{name}}.serviceConfig

# Switch this Mac to the working tree. Needs Touch ID.
mac:
    sudo darwin-rebuild switch --flake .

# Deploy a host from the working tree without committing. The real test for a new host.
deploy host ip:
    provisioning/onboard-host.sh --local {{host}} {{ip}}

# Deploy a host from what is on GitHub, and commit/push first if needed.
onboard host ip:
    provisioning/onboard-host.sh {{host}} {{ip}}

# Update every flake input, or just the named one: `just update nixpkgs`.
update input="":
    nix flake update {{input}}

# Edit an encrypted file: `just secret caddy.env`.
secret file:
    sops secrets/{{file}}

# Show what OpenTofu would change, authenticating to Proxmox first.
plan *args:
    #!/usr/bin/env bash
    # bash, not sh: pve-auth.sh uses [[ ]] and herestrings, and must be sourced rather than
    # executed so its exported ticket survives into tofu. It decrypts the Proxmox password
    # and derives a live TOTP code from secrets/msaxena.yaml, so a YubiKey must be present.
    set -euo pipefail
    source util/pve-auth.sh
    # Lab guests take their initial Administrator password from here. Decrypted per run
    # rather than kept in a .tfvars file, so it exists only in this process's environment.
    export TF_VAR_lab_admin_password=$(sops -d --extract '["clone-admin-password"]' secrets/lab.yaml)
    cd provisioning && tofu plan {{args}}

# Apply OpenTofu changes; scope to one host with `just apply -target=module.<name>`.
apply *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source util/pve-auth.sh
    export TF_VAR_lab_admin_password=$(sops -d --extract '["clone-admin-password"]' secrets/lab.yaml)
    cd provisioning && tofu apply {{args}}

# Delete old system generations, keeping the last five.
gc:
    nh clean all --keep 5

# Deliberately not OpenTofu's job: tofu owns packer@pve's role, user and ACLs, but a token
# secret it managed would sit in the committed state file. See provisioning/rbac.tf. PVE
# reveals a token's secret only at creation, so rotating is delete-then-create; both the old
# and new token carry the same privileges, which come from the ACLs, not from the token.

# The private key is materialised into a mode-0600 file for the length of the run and removed
# afterwards, because ssh will not take a key on stdin or from an environment variable. The
# very first run against a fresh clone has no key installed yet and falls back to the
# bootstrap password from group_vars; the baseline role installs the key, and every run after
# that uses it.

# Run an Ansible playbook against the lab: `just lab-play` or `just lab-play dc.yml`.
lab-play playbook="site.yml" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    key=$(mktemp); trap 'rm -f "$key"' EXIT
    chmod 600 "$key"
    sops -d --extract '["ansible-ssh-private-key"]' secrets/lab.yaml > "$key"
    cd ansible
    ANSIBLE_PRIVATE_KEY_FILE="$key" ansible-playbook playbooks/{{playbook}} {{args}}

# Credentials are decrypted straight into the process environment rather than written to a
# .pkrvars file, so nothing lands on disk and nothing lands in shell history. PKR_VAR_ is
# Packer's own convention for populating an input variable from the environment.

# Build a golden VM template with Packer: `just packer-build ws2025`.
packer-build template:
    #!/usr/bin/env bash
    set -euo pipefail
    export PKR_VAR_proxmox_username=$(sops -d --extract '["proxmox"]["packer-token-id"]' secrets/msaxena.yaml)
    export PKR_VAR_proxmox_token=$(sops -d --extract '["proxmox"]["packer-token-secret"]' secrets/msaxena.yaml)
    export PKR_VAR_admin_password=$(sops -d --extract '["build-admin-password"]' secrets/lab.yaml)
    export PKR_VAR_clone_password=$(sops -d --extract '["clone-admin-password"]' secrets/lab.yaml)
    export PKR_VAR_ansible_public_key=$(sops -d --extract '["ansible-ssh-public-key"]' secrets/lab.yaml)
    # Packer will not replace an existing VMID, so a second build of the same template dies
    # at "Creating VM" with "already exists". Retire the old one first. Safe because the
    # qemu-vm module takes full clones rather than linked ones: guests already built from
    # this template hold no reference to it, so removing it cannot affect them.
    #
    # Uses the Packer token rather than the root ticket, both because this recipe has no
    # reason to hold root and because it exercises exactly the permissions the build itself
    # will need. API-token auth does not use a CSRF token.
    export PKR_VAR_proxmox_url="${PKR_VAR_proxmox_url:-https://10.0.10.3:8006/api2/json}"
    vmid=$(grep -oE '^[[:space:]]*vm_id[[:space:]]*=[[:space:]]*[0-9]+' packer/{{template}}/build.pkr.hcl | grep -oE '[0-9]+' | head -1)
    auth=(-H "Authorization: PVEAPIToken=${PKR_VAR_proxmox_username}=${PKR_VAR_proxmox_token}")
    cfg=$(curl -sk "${auth[@]}" "${PKR_VAR_proxmox_url}/nodes/proxmox/qemu/${vmid}/config" 2>/dev/null || true)
    if [ "$(jq -r '.data.template // 0' <<<"${cfg:-{}}" 2>/dev/null)" = "1" ] \
       && [[ "$(jq -r '.data.name // ""' <<<"${cfg:-{}}" 2>/dev/null)" == tpl-* ]]; then
        echo "retiring existing template ${vmid} ($(jq -r .data.name <<<"$cfg"))"
        curl -sk -X DELETE "${auth[@]}" "${PKR_VAR_proxmox_url}/nodes/proxmox/qemu/${vmid}" >/dev/null
        # PVE deletes asynchronously; creating into the id before it is gone fails identically.
        for _ in $(seq 1 30); do
            curl -sk "${auth[@]}" "${PKR_VAR_proxmox_url}/nodes/proxmox/qemu/${vmid}/config" \
              | jq -e '.data.name' >/dev/null 2>&1 || break
            sleep 2
        done
    elif [ -n "$(jq -r '.data.name // ""' <<<"${cfg:-{}}" 2>/dev/null)" ]; then
        echo "ERROR: VMID ${vmid} exists but is not a tpl-* template. Refusing to touch it." >&2
        exit 1
    fi
    cd packer/{{template}}
    packer init .
    packer build .

# Mint or rotate the Packer API token into secrets/msaxena.yaml.
packer-token:
    #!/usr/bin/env bash
    set -euo pipefail
    source util/pve-auth.sh
    user="packer@pve"; tok="packerbuild"
    auth=(-H "Cookie: PVEAuthCookie=${PROXMOX_VE_AUTH_TICKET}"
          -H "CSRFPreventionToken: ${PROXMOX_VE_CSRF_PREVENTION_TOKEN}")
    url="${PROXMOX_VE_ENDPOINT}api2/json/access/users/${user}/token/${tok}"
    # A first run has nothing to delete; a rotation does. Neither case should abort.
    curl -sk -X DELETE "${auth[@]}" "$url" >/dev/null || true
    value=$(curl -sk -X POST "${auth[@]}" \
        --data-urlencode 'privsep=0' \
        --data-urlencode 'comment=Packer image builds. Secret lives in secrets/msaxena.yaml.' \
        "$url" | jq -er '.data.value')
    sops set secrets/msaxena.yaml '["proxmox"]["packer-token-id"]' "\"${user}!${tok}\""
    sops set secrets/msaxena.yaml '["proxmox"]["packer-token-secret"]' "\"${value}\""
    echo "wrote proxmox/packer-token-id and proxmox/packer-token-secret to secrets/msaxena.yaml"
