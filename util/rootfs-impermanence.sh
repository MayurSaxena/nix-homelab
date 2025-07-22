#!/bin/bash

# Proxmox Hook Script for rolling back ZFS subvolumes to @blank
# Store in /var/lib/vz/snippets/
# Usage: set this script as a hookscript in the VM/CT config
# pct set <ctid> --hookscript local:snippets/root-impermanence

VMID="$1"
PHASE="$2"

# Set your ZFS pool name here
ZFS_POOL="rpool"  # change this to your actual ZFS pool name

log() {
  echo "[$(date +%F_%T)] [VMID $VMID] $1"
}

rollback_to_blank() {
  local dataset="$1"
  local snapshot="${dataset}@blank"

  if zfs list -H -o name "$dataset" >/dev/null 2>&1; then
    if zfs list -H -o name "$snapshot" >/dev/null 2>&1; then
      log "Rolling back '$dataset' to '@blank'..."
      if zfs rollback -r "$snapshot"; then
        log "Rollback successful for '$dataset'."
      else
        log "ERROR: Rollback failed for '$dataset'."
      fi
    else
      log "Snapshot '@blank' not found for '$dataset'. Skipping rollback."
    fi
  else
    log "Dataset '$dataset' does not exist. Skipping."
  fi
}

# Hook phase logic
case "$PHASE" in
  pre-start)
    log "Hook: pre-start"

    # Only want to attempt to roll back the rootfs of the VM/CT
    rollback_to_blank "${ZFS_POOL}/data/subvol-${VMID}-disk-0"
    ;;

  post-start|pre-stop|post-stop)
    log "Hook: $PHASE - no action taken."
    ;;

  *)
    log "Unknown phase: $PHASE"
    ;;
esac
