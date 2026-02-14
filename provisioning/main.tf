resource "proxmox_virtual_environment_file" "nixos_lxc_impermanence_hookscript" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "proxmox"
  file_mode    = 0700
  source_file {
    path = "../assets/rootfs-impermanence.sh"
  }
}

module "nix-builder" {
  source             = "./modules/nixos-lxc"
  pve_node_name      = var.pve_node_name
  ct_description     = "Remote Build Server for NixOS (Terraform)"
  hostname           = "nix-builder"
  domain             = "home.internal"
  network_interfaces = { "eth0" = 20 }
  ipv4_settings      = "dhcp"
  ipv6_settings      = "auto"
  memory_size_mb     = 4096
  num_cpu_cores      = 4
  rootfs_size_gb     = 32
  ct_template_id     = proxmox_virtual_environment_download_file.nixos-standard-prod.id
  startup_order      = 3
  tags               = ["terraform", "builder"]
}

module "dns-server" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Technitium DNS Server (Terraform)"
  hostname              = "dns"
  domain                = "home.internal"
  dns_servers           = ["127.0.0.1", "::1"]
  network_interfaces    = { "eth0" = 10 }
  ipv4_settings         = "10.0.10.2/24;10.0.10.1"
  ipv6_settings         = "2403:5816:df19:1::2/64;2403:5816:df19:1::1"
  memory_size_mb        = 2048
  num_cpu_cores         = 2
  persistent_fs_size_gb = 2
  nix_fs_size_gb        = 8
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-prod.id
  pool_id               = "production"
  startup_order         = 1
  rootfs_impermanence   = true
  custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                  = ["terraform", "dhcp", "dns", "networking"]
}

module "actualbudget" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Actual Budget Server (Terraform)"
  hostname              = "actualbudget"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 1024
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
  nix_fs_size_gb        = 10
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id               = "production"
  startup_order         = 3
  rootfs_impermanence   = true
  custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                  = ["terraform", "finance"]
}

module "sabnzbd" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "SABnzbd Downloader (Terraform)"
  hostname              = "sabnzbd"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 2048
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
  nix_fs_size_gb        = 8
  additional_mount_points = [{
    vol     = "/mnt/MediaBox/usenet/"
    ct_path = "/data"
    backup  = false
  }]
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id             = "production"
  startup_order       = 3
  rootfs_impermanence = true
  custom_hookscript   = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                = ["terraform", "downloader", "host-mount"]
}

module "homepage" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Homepage Dashboard (Terraform)"
  hostname              = "homepage"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 1024
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
  nix_fs_size_gb        = 8
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id               = "production"
  startup_order         = 3
  rootfs_impermanence   = true
  custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                  = ["terraform", "access", "visualisation"]
}

module "plex-server" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Plex Media Server (Terraform)"
  hostname              = "plex"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 2048
  num_cpu_cores         = 4
  persistent_fs_size_gb = 8
  nix_fs_size_gb        = 12
  additional_mount_points = [{
    vol     = "/mnt/MediaBox/media/"
    ct_path = "/media/IronWolf"
    backup  = false
  }]
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id             = "production"
  startup_order       = 3
  rootfs_impermanence = true
  custom_hookscript   = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                = ["terraform", "media", "host-mount"]
}

module "overseerr" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Overseerr Media Requests (Terraform)"
  hostname              = "overseerr"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 2048
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
  nix_fs_size_gb        = 16
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id               = "production"
  startup_order         = 3
  rootfs_impermanence   = true
  custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                  = ["terraform", "media"]
}

module "paperless" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Paperless-ngx (Terraform)"
  hostname              = "paperless"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 3072
  num_cpu_cores         = 2
  persistent_fs_size_gb = 16
  nix_fs_size_gb        = 32
  additional_mount_points = [{
    vol     = "/mnt/NetShare/paperless-consume/"
    ct_path = "/mnt/paperless-consume"
    backup  = false
  }]
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id             = "production"
  startup_order       = 3
  rootfs_impermanence = true
  custom_hookscript   = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                = ["terraform", "document", "host-mount"]
}

module "minecraft" {
  source              = "./modules/nixos-lxc"
  pve_node_name       = var.pve_node_name
  ct_description      = "Minecraft Server (Terraform)"
  hostname            = "minecraft"
  domain              = "home.internal"
  network_interfaces  = { "eth0" = 40 }
  ipv4_settings       = "dhcp"
  ipv6_settings       = "auto"
  memory_size_mb      = 6144
  num_cpu_cores       = 4
  rootfs_size_gb      = 32
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
  pool_id             = "production"
  startup_order       = 3
  rootfs_impermanence = false
  tags                = ["terraform", "games"]
}

module "fileserver" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "File Server (Terraform)"
  hostname              = "files"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 1024
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
  nix_fs_size_gb        = 8
  additional_mount_points = [{
    vol     = "/mnt/TimeCapsule/"
    ct_path = "/media/TimeCapsule"
    backup  = false
    },
    {
      vol     = "/mnt/NetShare/"
      ct_path = "/media/NetShare"
      backup  = false
  }]
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id             = "production"
  startup_order       = 3
  rootfs_impermanence = true
  custom_hookscript   = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                = ["terraform", "host-mount", "storage"]
}

module "caddy" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Caddy Reverse Proxy (Terraform)"
  hostname              = "caddy"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 10 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 1024
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id               = "production"
  startup_order         = 2
  rootfs_impermanence   = true
  custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                  = ["terraform", "networking", "proxy"]
}

module "servarr" {
  source             = "./modules/nixos-lxc"
  pve_node_name      = var.pve_node_name
  ct_description     = "Servarr (Terraform)"
  hostname           = "servarr-test"
  domain             = "home.internal"
  network_interfaces = { "eth0" = 20 }
  ipv4_settings      = "dhcp"
  ipv6_settings      = "auto"
  memory_size_mb     = 2048
  num_cpu_cores      = 2
  additional_mount_points = [{
    vol     = "/mnt/MediaBox/"
    ct_path = "/media/IronWolf"
    backup  = false
  }]
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id             = "production"
  startup_order       = 3
  rootfs_impermanence = true
  custom_hookscript   = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                = ["terraform", "media", "host-mount"]
}

module "beszel-hub" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Beszel Hub (Terraform)"
  hostname              = "beszel-hub"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 10 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 2048
  num_cpu_cores         = 2
  persistent_fs_size_gb = 8
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-nightly.id
  pool_id               = "production"
  startup_order         = 2
  rootfs_impermanence   = true
  custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                  = ["terraform", "monitoring"]
}