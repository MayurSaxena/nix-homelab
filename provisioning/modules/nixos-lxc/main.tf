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
sleep 5
HOSTNAME=${self.ipv4["eth0"]} #${self.initialization[0].hostname}.${self.initialization[0].dns[0].domain}
age_key=$(nix shell nixpkgs#ssh-to-age --command sh -c "ssh-keyscan -t ed25519 $HOSTNAME | ssh-to-age")
echo $age_key
sed -i '' -r "/^.+&all-keys.*$/a\\
    - &${self.initialization[0].hostname} $(echo $age_key | tr -d '\n')\\
" ../.sops.yaml
sops updatekeys ../secrets/* -y
# git add ../.sops.yaml ../secrets/* && git commit -m "Adding ${self.initialization[0].hostname} to .sops.yaml" && git push
# sleep 5
# # echo "Hopefully YubiKey was inserted and waiting for touch."
# ssh root@$HOSTNAME nixos-rebuild switch --flake github:MayurSaxena/nix-homelab
EOT
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
sed -i '' -r '/^.+[&\*]${self.initialization[0].hostname}( +age.+)?$/d' ../.sops.yaml
sops updatekeys ../secrets/* -y
# git add ../.sops.yaml ../secrets/* && git commit -m "Removing ${self.initialization[0].hostname} from .sops.yaml" && git push
EOT
  }

  lifecycle {
    ignore_changes = [operating_system["template_file_id"]]
  }
}