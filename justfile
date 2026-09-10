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

# Copies rather than prints, because these are long random strings whose only real use is
# being pasted into an RDP or console login. `just lab-cred` on its own lists what is there.

# Copy a lab credential to the clipboard: `just lab-cred clone-admin-password`.
lab-cred key="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{key}}" ]; then
        echo "keys in secrets/lab.yaml:"
        sops -d secrets/lab.yaml | grep -E '^[a-z][a-z0-9-]*:' | cut -d: -f1 | sed 's/^/  /'
        echo
        echo "usage: just lab-cred <key>"
        exit 0
    fi
    sops -d --extract '["{{key}}"]' secrets/lab.yaml | tr -d '\n' | pbcopy
    echo "copied {{key}} to the clipboard"

# Credentials are decrypted straight into the process environment rather than written to a
# .pkrvars file, so nothing lands on disk and nothing lands in shell history. PKR_VAR_ is
# Packer's own convention for populating an input variable from the environment.

# Build a golden VM template with Packer: `just packer-build ws2025`.
packer-build template *args:
    #!/usr/bin/env bash
    set -euo pipefail
    export PKR_VAR_proxmox_username=$(sops -d --extract '["proxmox"]["packer-token-id"]' secrets/msaxena.yaml)
    export PKR_VAR_proxmox_token=$(sops -d --extract '["proxmox"]["packer-token-secret"]' secrets/msaxena.yaml)
    export PKR_VAR_admin_password=$(sops -d --extract '["build-admin-password"]' secrets/lab.yaml)
    export PKR_VAR_ansible_public_key=$(sops -d --extract '["ansible-ssh-public-key"]' secrets/lab.yaml)
    # Packer connects to the build VM by key, so it needs the private half as a file: ssh
    # takes a key from neither stdin nor the environment. Removed when the recipe exits.
    key=$(mktemp); trap 'rm -f "$key"' EXIT
    chmod 600 "$key"
    sops -d --extract '["ansible-ssh-private-key"]' secrets/lab.yaml > "$key"
    export PKR_VAR_ansible_private_key_file="$key"
    # Refuse to start if something is already answering on the build address.
    #
    # Packer connects to a fixed address rather than discovering one, because the Proxmox
    # plugin's discovery does not resolve here even when the agent reports correctly. The
    # hazard of a fixed address is that a clone can inherit it from the image, and Packer
    # would then SSH into that clone and provision it instead. That happened: a build failed
    # 41 seconds in on a machine that was never part of it, and a build that had found what
    # it expected would have carried on silently.
    build_ip="${PKR_VAR_build_ip:-10.0.90.99}"
    if nc -z -G 3 "$build_ip" 22 2>/dev/null; then
        echo "ERROR: something is already listening on ${build_ip}:22." >&2
        echo "A build would connect to it instead of the VM it creates. Find and remove the" >&2
        echo "guest sitting on that address, then retry." >&2
        exit 1
    fi

    # Build first, retire second.
    #
    # The old recipe deleted the existing template before building its replacement, because
    # Packer refuses to create a VM at an id that already exists. That left the node with no
    # template at all whenever a build then failed -- which happened twice, once when the
    # build tooling went missing from the PATH. Packer now allocates its own id, so the new
    # template can exist alongside the old one and the old one is removed only once the new
    # one is real.
    #
    # Steady state is still exactly one template per role. The difference is that there is
    # never a moment with zero.
    export PKR_VAR_proxmox_url="${PKR_VAR_proxmox_url:-https://10.0.10.3:8006/api2/json}"
    auth=(-H "Authorization: PVEAPIToken=${PKR_VAR_proxmox_username}=${PKR_VAR_proxmox_token}")
    tmpl_tag="{{template}}"
    templates_with_tag() {
        curl -sk "${auth[@]}" "${PKR_VAR_proxmox_url}/nodes/proxmox/qemu" \
          | jq -r --arg t "$tmpl_tag" '.data[] | select(.template==1) | select((.tags // "") | split(";") | index($t)) | .vmid'
    }
    before=$(templates_with_tag | sort -n | tr '\n' ' ')
    echo "existing ${tmpl_tag} templates before this build: ${before:-none}"

    (cd packer/{{template}} && packer init . && packer build {{args}} .)

    after=$(templates_with_tag | sort -n | tr '\n' ' ')
    echo "after: ${after:-none}"
    for old in $before; do
        case " $after " in *" $old "*) ;; *) continue ;; esac
        [ "$(echo "$after" | wc -w)" -le 1 ] && { echo "only one template present; nothing to retire"; break; }
        echo "retiring superseded template $old"
        curl -sk -X DELETE "${auth[@]}" "${PKR_VAR_proxmox_url}/nodes/proxmox/qemu/${old}" >/dev/null
    done

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
