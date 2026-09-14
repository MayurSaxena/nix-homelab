#!/usr/bin/env bash
# Network finalisation deliberately disconnects SSH. Wait through the Proxmox API before
# allowing Packer to convert the guest, rather than interpreting a disconnect as success.
set -euo pipefail

endpoint=${1%/}
node=$2
name=$3
timeout=${4:-900}
[[ "$timeout" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid shutdown timeout" >&2; exit 1; }
: "${PKR_VAR_proxmox_username:?Packer token ID is required}"
: "${PKR_VAR_proxmox_token:?Packer token secret is required}"

api="$endpoint/nodes/$node/qemu"
auth=(-H "Authorization: PVEAPIToken=${PKR_VAR_proxmox_username}=${PKR_VAR_proxmox_token}")
get() {
    curl --silent --show-error --fail --insecure --connect-timeout 10 --max-time 20 "${auth[@]}" "$1"
}

# Existing templates have the same name, so exclude them. Ambiguity must fail rather than
# waiting for (and ultimately converting) the wrong build.
vmid=$(get "$api" | jq -er --arg name "$name" '
    [.data[] | select(.name == $name and ((.template // 0) == 0))] |
    if length == 1 then .[0].vmid else error("Expected exactly one non-template build VM") end')

echo "Waiting for $name ($vmid) to finish network reset and shut down"
deadline=$((SECONDS + timeout))
while (( SECONDS < deadline )); do
    status=$(get "$api/$vmid/status/current" | jq -er '.data.status')
    case "$status" in
        stopped) echo "Build VM $vmid is stopped"; exit 0 ;;
        running) sleep 3 ;;
        *) echo "Unexpected VM status: $status" >&2; exit 1 ;;
    esac
done
echo "VM $vmid did not shut down within ${timeout}s; inspect C:\\Windows\\Temp\\packer-finalize.log and the scheduled task result." >&2
exit 1
