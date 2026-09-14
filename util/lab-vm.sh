#!/usr/bin/env bash
# The imperative half of the lab lifecycle. OpenTofu owns pets; this script owns tasks and
# disposable clones. A queued Proxmox task is not a completed operation.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
action=${1:?Expected snapshot, revert, snapshots, spawn or despawn}
guest=${2:?Expected a guest or template name}
name=${3:-golden}
[[ "$guest" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || { echo 'Invalid guest name' >&2; exit 1; }
case "$action" in
    snapshot|revert) [[ "$name" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || { echo 'Invalid snapshot name' >&2; exit 1; } ;;
    spawn) [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || { echo 'Invalid clone name' >&2; exit 1; } ;;
    snapshots|despawn) ;;
    *) echo "Unknown action: $action" >&2; exit 1 ;;
esac

if [[ -z ${PROXMOX_VE_AUTH_TICKET:-} || -z ${PROXMOX_VE_CSRF_PREVENTION_TOKEN:-} ]]; then
    # The auth script's optional first positional parameter is a TOTP, not our action.
    source "$repo/util/pve-auth.sh" ""
fi
base="${PROXMOX_VE_ENDPOINT:-https://10.0.10.3:8006/}"
base="${base%/}/api2/json"
node=${LAB_PVE_NODE:-proxmox}
vms="nodes/$node/qemu"
auth=(-H "Cookie: PVEAuthCookie=$PROXMOX_VE_AUTH_TICKET"
      -H "CSRFPreventionToken: $PROXMOX_VE_CSRF_PREVENTION_TOKEN")
timeout=${LAB_TASK_TIMEOUT:-900}
interval=${LAB_POLL_INTERVAL:-2}
[[ "$timeout" =~ ^[1-9][0-9]*$ && "$interval" =~ ^[0-9]+$ ]] || { echo 'Invalid task timeout or polling interval' >&2; exit 1; }

request() {
    local method=$1 path=$2 response
    shift 2
    local args=()
    while (( $# )); do args+=(--data-urlencode "$1"); shift; done
    # Proxmox rejects request bodies on DELETE; curl must put these fields in the URL.
    if [[ "$method" == GET || "$method" == DELETE ]]; then args+=(--get); fi
    response=$(curl --silent --show-error --fail --insecure --connect-timeout 10 --max-time 30 \
        -X "$method" "${auth[@]}" "${args[@]}" "$base/$path") || {
        echo "$method $path failed" >&2; return 1;
    }
    jq -e 'type == "object" and has("data") and .errors == null' >/dev/null <<<"$response" || return
    jq -c '.data' <<<"$response"
}

task() {
    local upid encoded status deadline
    upid=$(request "$@" | jq -er 'select(type == "string" and startswith("UPID:"))')
    encoded=$(jq -rn --arg id "$upid" '$id | @uri')
    deadline=$((SECONDS + timeout))
    while (( SECONDS < deadline )); do
        status=$(request GET "nodes/$node/tasks/$encoded/status")
        case "$(jq -er '.status' <<<"$status")" in
            stopped)
                if [[ $(jq -r '.exitstatus' <<<"$status") != OK ]]; then
                    echo "Proxmox task failed: $(jq -r '.exitstatus' <<<"$status") ($upid)" >&2
                    return 1
                fi
                return 0 ;;
            running) sleep "$interval" ;;
            *) echo "Invalid task status for $upid" >&2; return 1 ;;
        esac
    done
    echo "Timed out waiting for $upid; inspect the task before retrying." >&2
    return 1
}

guests=$(request GET "$vms")
vm=$(jq -ce --arg n "$guest" '[.[] | select(.name == $n)] |
    if length == 1 then .[0] else error("Expected exactly one VM named " + $n) end' <<<"$guests")
id=$(jq -er '.vmid' <<<"$vm")
path="$vms/$id"
if [[ "$action" != spawn && $(jq -r '.template // 0' <<<"$vm") == 1 ]]; then
    echo "$guest is a template, not a guest" >&2; exit 1
fi

case "$action" in
    snapshots)
        request GET "$path/snapshot" | jq -r 'sort_by(.snaptime)[] | select(.name != "current") |
            "\(.name)\t\(.snaptime | strftime("%Y-%m-%d %H:%M"))\t\(.description // "")"'
        ;;
    snapshot|revert)
        snapshots=$(request GET "$path/snapshot")
        exists=$(jq --arg n "$name" 'any(.[]; .name == $n)' <<<"$snapshots")
        if [[ "$action" == snapshot ]]; then
            if [[ "$exists" == true ]]; then
                [[ "$name" == golden ]] || { echo "Snapshot $name already exists; only golden is replaceable" >&2; exit 1; }
                task DELETE "$path/snapshot/$name"
            fi
            task POST "$path/snapshot" "snapname=$name" 'vmstate=0' 'description=Lab restore point'
            echo "Snapshot $name completed on $guest ($id)"
        else
            [[ "$exists" == true ]] || { echo "No snapshot $name on $guest" >&2; exit 1; }
            status=$(request GET "$path/status/current" | jq -er '.status')
            if [[ "$status" == running ]]; then task POST "$path/status/stop"; fi
            task POST "$path/snapshot/$name/rollback"
            task POST "$path/status/start"
            echo "$guest ($id) reverted to $name and started"
        fi
        ;;
    despawn)
        tags=";$(jq -r '.tags // ""' <<<"$vm");"
        [[ "$tags" == *';adhoc;'* && "$tags" == *';lab;'* && "$tags" != *';terraform;'* && "$tags" != *';template;'* ]] || {
            echo "$guest is not an explicitly tagged ad-hoc lab VM; refusing deletion" >&2; exit 1;
        }
        status=$(request GET "$path/status/current" | jq -er '.status')
        if [[ "$status" == running ]]; then task POST "$path/status/stop"; fi
        task DELETE "$path" 'purge=1' 'destroy-unreferenced-disks=1'
        echo "$guest ($id) destroyed"
        ;;
    spawn)
        [[ $(jq -r '.template // 0' <<<"$vm") == 1 ]] || { echo "$guest is not a template" >&2; exit 1; }
        ! jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null <<<"$guests" || { echo "$name already exists" >&2; exit 1; }
        config=$(request GET "$path/config")
        user=${4:-$(jq -r '.ciuser // empty' <<<"$config")}
        os=$(jq -er '.ostype' <<<"$config")
        case "$os" in
            win*|w2k*|wxp|wvista)
                user=${user:-Administrator}
                (( ${#name} <= 15 )) || { echo 'Windows hostnames must be at most 15 characters' >&2; exit 1; } ;;
            l26|l24)
                if [[ -z "$user" && "$guest" == *kali* ]]; then user=kali; fi
                [[ -n "$user" ]] || { echo 'Specify the Linux image user: just lab-spawn TEMPLATE NAME USER' >&2; exit 1; } ;;
            *) echo "Unsupported cloud-init OS type: $os" >&2; exit 1 ;;
        esac
        [[ "$user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || { echo 'Invalid cloud-init username' >&2; exit 1; }
        # Discover a free drive slot before cloning. Never overwrite a template's disk/CD.
        drive=$(jq -r 'to_entries[] | select(.key | test("^(ide|sata|scsi)[0-9]+$")) |
            select(.value | contains("cloudinit")) | .key' <<<"$config")
        attach=()
        if [[ -z "$drive" ]]; then
            for slot in ide2 sata0 sata1 sata2 sata3 sata4 sata5; do
                if ! jq -e --arg s "$slot" 'has($s)' >/dev/null <<<"$config"; then drive=$slot; break; fi
            done
            [[ -n "$drive" ]] || { echo 'No free cloud-init drive slot on template' >&2; exit 1; }
            attach=("$drive=${LAB_VM_STORAGE:-local-zfs}:cloudinit")
        fi
        password=$(sops -d --extract '["clone-admin-password"]' "$repo/secrets/lab.yaml")
        key=$(sops -d --extract '["ansible-ssh-public-key"]' "$repo/secrets/lab.yaml")
        [[ -n "$password" && -n "$key" ]] || { echo 'Missing lab credentials' >&2; exit 1; }
        case "$os" in
            win*|w2k*|wxp|wvista) printf '%s' "$password" | python3 "$repo/util/check-lab-password.py" "$user" ;;
        esac
        # PVE's sshkeys schema requires a URL-encoded value inside the form field. Curl's
        # form encoding alone is decoded before schema validation and is insufficient.
        key=$(jq -rn --arg key "$key" '$key | @uri')
        newid=$(request GET cluster/nextid | jq -er '.')
        task POST "$path/clone" "newid=$newid" "name=$name" 'full=1' 'pool=lab' "target=$node"
        echo "Cloned $guest to $name ($newid); configuring metadata"
        path="$vms/$newid"
        # Mark ownership before further configuration so a failed bootstrap can still be
        # removed with lab-despawn, instead of retaining the source template's tags.
        request POST "$path/config" 'tags=adhoc;lab' >/dev/null
        # Preserve the cloned MAC/model, but always place test traffic on the lab VLAN.
        net=$(request GET "$path/config" | jq -er '.net0')
        net=$(printf '%s' "$net" | tr ',' '\n' | awk '!/^(bridge|tag|trunks)=/' | paste -sd, -)
        request POST "$path/config" "${attach[@]}" "net0=$net,bridge=vmbr0,tag=90" \
            "ciuser=$user" "cipassword=$password" "sshkeys=$key" 'ipconfig0=ip=dhcp' \
            'nameserver=10.0.10.2' 'searchdomain=lab.internal' >/dev/null
        task POST "$path/status/start"
        echo "$name ($newid) started; check its DHCP lease or guest-agent addresses."
        ;;
esac
