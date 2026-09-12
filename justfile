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
    # Linux guests are built from a stock cloud image with no key baked in, so cloud-init
    # has to authorise one. The Windows templates carry it already.
    export TF_VAR_lab_ansible_public_key=$(sops -d --extract '["ansible-ssh-public-key"]' secrets/lab.yaml)
    # Some operations go over SSH to the node rather than through the API, because PVE has
    # no API for them: uploading a snippet, and importing a disk image. The provider reads
    # the ssh-agent for those and explicitly ignores ~/.ssh/config, so the key your own ssh
    # uses is invisible to it -- which surfaces as "attempted methods [none password]", a
    # message that looks like a credential problem rather than an empty agent.
    #
    # This is the sops-decrypted Mac key, not one of the YubiKey sk keys, so it needs no
    # touch and the apply stays unattended. Re-adding an already-loaded key is a no-op.
    ssh-add -q ~/.ssh/id_ed25519 2>/dev/null || echo "warning: could not load ~/.ssh/id_ed25519 into ssh-agent; operations that go over SSH to the node will fail" >&2
    cd provisioning && tofu plan {{args}}

# Apply OpenTofu changes; scope to one host with `just apply -target=module.<name>`.
apply *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source util/pve-auth.sh
    export TF_VAR_lab_admin_password=$(sops -d --extract '["clone-admin-password"]' secrets/lab.yaml)
    # Linux guests are built from a stock cloud image with no key baked in, so cloud-init
    # has to authorise one. The Windows templates carry it already.
    export TF_VAR_lab_ansible_public_key=$(sops -d --extract '["ansible-ssh-public-key"]' secrets/lab.yaml)
    # Some operations go over SSH to the node rather than through the API, because PVE has
    # no API for them: uploading a snippet, and importing a disk image. The provider reads
    # the ssh-agent for those and explicitly ignores ~/.ssh/config, so the key your own ssh
    # uses is invisible to it -- which surfaces as "attempted methods [none password]", a
    # message that looks like a credential problem rather than an empty agent.
    #
    # This is the sops-decrypted Mac key, not one of the YubiKey sk keys, so it needs no
    # touch and the apply stays unattended. Re-adding an already-loaded key is a no-op.
    ssh-add -q ~/.ssh/id_ed25519 2>/dev/null || echo "warning: could not load ~/.ssh/id_ed25519 into ssh-agent; operations that go over SSH to the node will fail" >&2
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

# Build a golden VM template with Packer: `just packer-build windows ws2025`.
#
# `family` is a directory under packer/ -- one Packer configuration per class of guest,
# because the builder itself differs (Windows installs from an ISO and an answer file;
# a Linux cloud image is cloned from a disk image and configured by cloud-init). `target`
# is a key of that configuration's catalog, and names the template it produces.

# Build a golden VM template with Packer: `just packer-build windows win11-pro`.
packer-build family target *args:
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
    tmpl_tag="{{target}}"
    templates_with_tag() {
        curl -sk "${auth[@]}" "${PKR_VAR_proxmox_url}/nodes/proxmox/qemu" \
          | jq -r --arg t "$tmpl_tag" '.data[] | select(.template==1) | select((.tags // "") | split(";") | index($t)) | .vmid'
    }
    before=$(templates_with_tag | sort -n | tr '\n' ' ')
    echo "existing ${tmpl_tag} templates before this build: ${before:-none}"

    (cd packer/{{family}} && packer init . && packer build -var target={{target}} {{args}} .)

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

# The lab's base images, and how each one is made.
#
# One verb, because "produce the base image for X" is one idea. How it gets produced is not
# a distinction worth making at the command line:
#
#   Windows  ->  Packer installs the OS from an ISO, because Microsoft ships no usable
#                image, and converts the result to a template.
#   Linux    ->  download the distribution's cloud image, which already carries cloud-init.
#                There is no OS to install, so there is no build; `tofu apply` turns the
#                downloaded image into a template. The guest agent is not always in the
#                image -- Kali's is not -- so Ansible installs it.
#
# Cloud images need unpacking, which is the one thing OpenTofu cannot do for itself:
# `download_file` decompresses gz, lzo, zst and bz2, and the images ship as .tar.xz or
# .zip. Fetching runs on the node, so the image crosses the internet once rather than being
# pulled to the Mac and pushed back.
#
# No version is pinned. The archive name and its checksum both come from the published
# SHA256SUMS of the `current` release, so this fetches whatever is current and verifies it,
# and writes a stable filename that provisioning/vms.tf can refer to forever. Re-running it
# replaces the image; nothing rebuilds until you taint the template, which is deliberate --
# moving to a newer Kali should not happen under a guest during an unrelated apply.

# Produce a base image: `just lab-image win11-pro`, `just lab-image kali`.
lab-image name:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{name}}" in
      ws2025|win11-pro)
        exec just packer-build windows "{{name}}"
        ;;
      kali)
        base="https://kali.download/cloud-images/current"
        member="disk.raw"   # what is inside the tar
        out="kali-cloud-amd64.img"
        ;;
      *)
        echo "unknown image '{{name}}'. Known: ws2025, win11-pro, kali" >&2
        exit 1
        ;;
    esac

    # .img rather than .qcow2, and the ISO datastore rather than a PVE 9 "import" one: PVE
    # lists .iso and .img as ISO content, so this needs no storage reconfiguration on the
    # node, and the provider imports a disk from that volume id perfectly well.
    iso_dir="/var/lib/vz/template/iso"

    ssh root@10.0.10.3 bash -seu <<REMOTE
    base="$base"; member="$member"; out="$out"; iso_dir="$iso_dir"
    # Not /tmp: it is tmpfs on this node, and these images unpack to tens of gigabytes.
    work="/var/lib/vz/tmp-cloud-image"
    mkdir -p "\$work" "\$iso_dir"
    trap 'rm -rf "\$work"' EXIT
    cd "\$work"

    curl -sSLf -o SHA256SUMS "\$base/SHA256SUMS"
    line=\$(grep 'amd64' SHA256SUMS | head -1)
    archive=\$(echo "\$line" | awk '{print \$2}')
    echo "current image: \$archive"

    curl -SLf --progress-bar -o "\$archive" "\$base/\$archive"
    echo "\$line" | sha256sum -c -

    # -S writes the file sparsely; these images are mostly holes, so this is the difference
    # between a couple of hundred megabytes and the image's full apparent size.
    tar -xSJf "\$archive" "\$member"
    mv -f "\$member" "\$iso_dir/\$out"
    echo "wrote \$iso_dir/\$out  (\$(du -h --apparent-size "\$iso_dir/\$out" | cut -f1) apparent, \$(du -h "\$iso_dir/\$out" | cut -f1) on disk)"
    REMOTE

# The pet lifecycle: deploy, configure, snapshot, work, revert, occasionally rebuild.
#
# Snapshots are recipes rather than OpenTofu resources, and that is a judgement rather than
# a workaround for the provider lacking one. A snapshot is a point in time, not a desired
# state: declaring it would have OpenTofu forever comparing "the snapshot that exists" with
# "the snapshot that should exist" and re-taking it, which is the opposite of what a restore
# point is for.
#
# `golden` is the convention: the state a machine is in once its Ansible role has converged
# and before you start breaking it. Take one after every rebuild, revert to it after a CTF.

# Take a restore point: `just lab-snapshot kali01 [name]`.
lab-snapshot guest name="golden":
    #!/usr/bin/env bash
    set -euo pipefail
    source util/pve-auth.sh
    auth=(-H "Cookie: PVEAuthCookie=${PROXMOX_VE_AUTH_TICKET}"
          -H "CSRFPreventionToken: ${PROXMOX_VE_CSRF_PREVENTION_TOKEN}")
    api="${PROXMOX_VE_ENDPOINT}api2/json/nodes/proxmox/qemu"
    vmid=$(curl -sk "${auth[@]}" "$api" | jq -er --arg n "{{guest}}" '.data[] | select(.name==$n) | .vmid')
    # Re-taking a name means replacing it. PVE refuses a duplicate, and the alternative --
    # accumulating golden-1, golden-2 -- turns "revert to fresh" into "work out which one".
    if curl -sk "${auth[@]}" "$api/$vmid/snapshot" | jq -e --arg s "{{name}}" '.data[] | select(.name==$s)' >/dev/null; then
        echo "replacing existing snapshot {{name}} on {{guest}} ($vmid)"
        curl -sk -X DELETE "${auth[@]}" "$api/$vmid/snapshot/{{name}}" >/dev/null
        # DELETE returns as soon as the task is queued, so the create below can race it.
        until ! curl -sk "${auth[@]}" "$api/$vmid/snapshot" | jq -e --arg s "{{name}}" '.data[] | select(.name==$s)' >/dev/null; do sleep 2; done
    fi
    # No vmstate: a restore point wants a clean boot, not a resumed one, and RAM would add
    # the guest's memory size to every snapshot for nothing.
    curl -sk -X POST "${auth[@]}" --data-urlencode 'snapname={{name}}' \
        --data-urlencode 'description=Taken by `just lab-snapshot`. Safe to roll back to.' \
        "$api/$vmid/snapshot" >/dev/null
    echo "snapshot {{name}} taken on {{guest}} ($vmid)"

# Roll a guest back to a restore point: `just lab-revert kali01 [name]`.
lab-revert guest name="golden":
    #!/usr/bin/env bash
    set -euo pipefail
    source util/pve-auth.sh
    auth=(-H "Cookie: PVEAuthCookie=${PROXMOX_VE_AUTH_TICKET}"
          -H "CSRFPreventionToken: ${PROXMOX_VE_CSRF_PREVENTION_TOKEN}")
    api="${PROXMOX_VE_ENDPOINT}api2/json/nodes/proxmox/qemu"
    vmid=$(curl -sk "${auth[@]}" "$api" | jq -er --arg n "{{guest}}" '.data[] | select(.name==$n) | .vmid')
    curl -sk "${auth[@]}" "$api/$vmid/snapshot" | jq -er --arg s "{{name}}" '.data[] | select(.name==$s)' >/dev/null \
        || { echo 'no snapshot named {{name}} on {{guest}}; `just lab-snapshot {{guest}}` takes one' >&2; exit 1; }
    # A rollback of a running guest is refused, so stop it first rather than making the
    # caller discover that. Pull the plug: the point of reverting is that this guest's
    # current state is being discarded, so a clean shutdown would only be slower.
    if [ "$(curl -sk "${auth[@]}" "$api/$vmid/status/current" | jq -r '.data.status')" = "running" ]; then
        echo "stopping {{guest}}"
        curl -sk -X POST "${auth[@]}" "$api/$vmid/status/stop" >/dev/null
        until [ "$(curl -sk "${auth[@]}" "$api/$vmid/status/current" | jq -r '.data.status')" = "stopped" ]; do sleep 2; done
    fi
    echo "rolling {{guest}} back to {{name}}"
    curl -sk -X POST "${auth[@]}" "$api/$vmid/snapshot/{{name}}/rollback" >/dev/null
    # Rollback is a task; starting before it finishes fails.
    until [ "$(curl -sk "${auth[@]}" "$api/$vmid/status/current" | jq -r '.data.lock // "none"')" = "none" ]; do sleep 3; done
    curl -sk -X POST "${auth[@]}" "$api/$vmid/status/start" >/dev/null
    echo "{{guest}} reverted to {{name}} and starting"
