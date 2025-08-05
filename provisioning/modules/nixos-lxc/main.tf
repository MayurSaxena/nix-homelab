terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.80.0"
    }
  }
}

data "proxmox_virtual_environment_datastores" "ct_storage" {
  node_name = var.pve_node_name

  filters = {
    content_types = ["images", "rootdir"]
    id            = "local-zfs" #Here for safety wonder if necessary
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
    datastore_id = data.proxmox_virtual_environment_datastores.ct_storage.datastores[0].id
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
      { "vol" : "${data.proxmox_virtual_environment_datastores.ct_storage.datastores[0].id}"
        "ct_path" : "/boot"
        "backup" : false
        "size" : "100M"
      },
      { "vol" : "${data.proxmox_virtual_environment_datastores.ct_storage.datastores[0].id}"
        "ct_path" : "/nix"
        "backup" : false
        "size" : "4G"
      },
      { "vol" : "${data.proxmox_virtual_environment_datastores.ct_storage.datastores[0].id}"
        "ct_path" : "/persistent"
        "backup" : true
        "size" : "${var.persistent_fs_size_gb}G"
      },
      { "vol" : "${data.proxmox_virtual_environment_datastores.ct_storage.datastores[0].id}"
        "ct_path" : "/sbin"
        "backup" : false
        "size" : "100M"
      }
      , { "vol" : "${data.proxmox_virtual_environment_datastores.ct_storage.datastores[0].id}"
        "ct_path" : "/bin"
        "backup" : false
        "size" : "100M"
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
age_key=$(ssh root@proxmox "pct exec ${self.id} -- sh -c '. /etc/profile ; curl -fsSL https://raw.githubusercontent.com/MayurSaxena/nix-homelab/refs/heads/main/install.sh | bash'")
sed -i '' -r "/^.+&all-keys.*$/a\\
    - &${self.initialization[0].hostname} $(echo $age_key | tr -d '\n')\\
" ../.sops.yaml
sops updatekeys ../secrets/* -y
git add ../.sops.yaml ../secrets/* && git commit -m "Adding ${self.initialization[0].hostname} to .sops.yaml" && git push
sleep 5
ssh root@proxmox "pct exec ${self.id} -- sh -c '. /etc/profile ; nixos-rebuild switch --flake github:MayurSaxena/nix-homelab'"
EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
sed -i '' -r '/^.+[&\*]${self.initialization[0].hostname}.*$/d' ../.sops.yaml
sops updatekeys ../secrets/* -y
git add ../.sops.yaml ../secrets/* && git commit -m "Removing ${self.initialization[0].hostname} from .sops.yaml" && git push
EOT
  }
}