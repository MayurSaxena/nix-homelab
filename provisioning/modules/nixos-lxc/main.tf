terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.80.0"
    }
  }
}

resource "proxmox_virtual_environment_container" "ct" {
  node_name = var.pve_node_name
  console {
    enabled = true
    type    = "tty"
  }
  cpu {
    architecture = "amd64"
    units        = 100
    cores        = var.num_cpu_cores
  }
  description = var.ct_description
  disk {
    datastore_id = var.ct_disk_datastore
    size         = var.rootfs_size_gb
  }
  initialization {
    dns {
      domain  = var.domain
      servers = var.dns_servers
    }
    hostname = var.hostname
    ip_config {
      ipv4 {
        address = var.ipv4_settings == "dhcp" ? var.ipv4_settings : split(";", var.ipv4_settings)[0]
        gateway = var.ipv4_settings == "dhcp" ? null : split(";", var.ipv4_settings)[1]
      }
      ipv6 {
        address = (var.ipv6_settings == "auto" || var.ipv6_settings == "dhcp") ? var.ipv6_settings : split(";", var.ipv6_settings)[0]
        gateway = (var.ipv6_settings == "auto" || var.ipv6_settings == "dhcp") ? null : split(";", var.ipv6_settings)[1]
      }
    }
    # USER ACCOUNT omitted
  }
  memory {
    dedicated = var.memory_size_mb
    swap      = var.swap_size_mb
  }

  dynamic "mount_point" {
    for_each = var.rootfs_impermanence ? [
      { "vol" : "${var.ct_disk_datastore}"
        "ct_path" : "/boot"
        "backup" : false
        "size" : "1G"
      },
      { "vol" : "${var.ct_disk_datastore}"
        "ct_path" : "/nix"
        "backup" : false
        "size" : "${var.nix_fs_size_gb}G"
      },
      { "vol" : "${var.ct_disk_datastore}"
        "ct_path" : "/persistent"
        "backup" : true
        "size" : "${var.persistent_fs_size_gb}G"
      },
      { "vol" : "${var.ct_disk_datastore}"
        "ct_path" : "/sbin"
        "backup" : false
        "size" : "1G"
      }
      , { "vol" : "${var.ct_disk_datastore}"
        "ct_path" : "/bin"
        "backup" : false
        "size" : "1G"
    }] : []
    iterator = mp
    content {
      backup = mp.value["backup"]
      path   = mp.value["ct_path"]
      volume = mp.value["vol"]
      size   = mp.value["size"]
    }
  }

  dynamic "mount_point" {
    for_each = var.additional_mount_points
    iterator = mp
    content {
      backup = mp.value["backup"]
      path   = mp.value["ct_path"]
      volume = mp.value["vol"]
      size   = mp.value["size"]
    }
  }


  dynamic "network_interface" {
    for_each = var.network_interfaces
    iterator = netif
    content {
      bridge   = "vmbr0"
      enabled  = true
      firewall = false
      name     = netif.key
      vlan_id  = netif.value
    }
  }

  operating_system {
    template_file_id = var.ct_template_id
    type             = "nixos"
  }
  pool_id = var.pool_id
  started = true

  dynamic "startup" {
    for_each = var.startup_order != null ? [var.startup_order] : []
    iterator = start_order
    content {
      order = start_order.value
    }
  }

  start_on_boot = var.startup_order != null
  tags          = var.tags

  unprivileged = true
  features {
    nesting = true
  }
  hook_script_file_id = var.custom_hookscript

  provisioner "local-exec" {
    command = <<EOT
HOSTNAME=${self.ipv4["eth0"]} #${self.initialization[0].hostname}.${self.initialization[0].dns[0].domain}
# Poll until sshd actually offers an ed25519 host key. A fixed sleep raced the
# container's first boot: ssh-keyscan would come back empty, ssh-to-age would
# emit nothing, and an anchor with an empty key got spliced into .sops.yaml —
# which then silently encrypts nothing to this host. Fail loudly instead.
age_key=""
attempt=1
while [ "$attempt" -le 30 ]; do
  candidate=$(nix shell nixpkgs#ssh-to-age --command sh -c "ssh-keyscan -t ed25519 -T 5 $HOSTNAME 2>/dev/null | ssh-to-age" 2>/dev/null | head -n1 || true)
  case "$candidate" in
    age1*)
      age_key=$candidate
      break
      ;;
  esac
  echo "waiting for sshd on $HOSTNAME to offer a host key (attempt $attempt/30)"
  attempt=$((attempt + 1))
  sleep 2
done
if [ -z "$age_key" ]; then
  echo "ERROR: could not derive an age key for ${self.initialization[0].hostname} at $HOSTNAME." >&2
  echo "The container exists but never offered an ed25519 host key. Nothing was written to" >&2
  echo ".sops.yaml. Check the container is booted and reachable, then re-run tofu apply." >&2
  exit 1
fi
echo "derived age key for ${self.initialization[0].hostname}: $age_key"
sed -i '' -r "/^.+&all-keys.*$/a\\
    - &${self.initialization[0].hostname} $age_key
" ../.sops.yaml
sops updatekeys ../secrets/* -y
# A git push and a multi-minute remote build/switch don't belong in a
# provisioner that gates `tofu apply`'s success/failure — a slow SSH session
# or a delayed YubiKey touch would hang or fail the whole apply with no
# rollback. Finish onboarding by hand (or have Claude do it) instead:
echo "Next: ./onboard-host.sh ${self.initialization[0].hostname} $HOSTNAME"
EOT
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
sed -i '' -r '/^.+[&\*]${self.initialization[0].hostname}( +age.+)?$/d' ../.sops.yaml
sops updatekeys ../secrets/* -y
echo "Next: git -C .. add .sops.yaml secrets/ && git -C .. commit -m 'Remove ${self.initialization[0].hostname} from .sops.yaml' && git -C .. push"
EOT
  }

  lifecycle {
    ignore_changes = [operating_system["template_file_id"]]
  }
}