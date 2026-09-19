resource "proxmox_backup_job" "prod-backup" {
  all          = null
  bwlimit      = null
  compress     = "zstd"
  enabled      = true
  exclude      = null
  exclude_path = null
  fleecing = {
    enabled = false
    storage = null
  }
  id                        = "backup-c5a5a3b2-d996"
  ionice                    = null
  lockwait                  = null
  mailnotification          = null
  mailto                    = null
  maxfiles                  = null
  mode                      = "snapshot"
  node                      = null
  notes_template            = "{{guestname}} ({{vmid}})"
  pbs_change_detection_mode = null
  performance               = null
  pigz                      = null
  pool                      = "production"
  protected                 = null
  prune_backups = {
    keep-daily   = "7"
    keep-monthly = "6"
    keep-weekly  = "4"
  }
  remove        = null
  repeat_missed = true
  schedule      = "02:00"
  script        = null
  starttime     = null
  stdexcludes   = null
  stopwait      = null
  storage       = "local"
  tmpdir        = null
  vmid          = null
  zstd          = null
}