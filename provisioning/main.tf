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
  domain             = "dev.home.mayursaxena.com"
  network_interfaces = { "eth0" = 60 }
  ipv4_settings      = "dhcp"
  ipv6_settings      = "auto"
  memory_size_mb     = 4096
  num_cpu_cores      = 4
  rootfs_size_gb     = 8
  ct_template_id     = proxmox_virtual_environment_download_file.nixos-standard-prod.id
  startup_order      = 3
  tags               = ["terraform", "builder"]
}

module "dns-server" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Technitium DNS Server (Terraform)"
  hostname              = "dns"
  domain                = "home.mayursaxena.com"
  dns_servers           = ["127.0.0.1", "::1"]
  network_interfaces    = { "eth0" = 10 }
  ipv4_settings         = "10.0.10.2/24;10.0.10.1"
  ipv6_settings         = "2403:5816:961a:1::2/64;2403:5816:961a:1::1"
  memory_size_mb        = 1024
  num_cpu_cores         = 2
  persistent_fs_size_gb = 2
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
  domain                = "home.mayursaxena.com"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 1024
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
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
  domain                = "home.mayursaxena.com"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 1024
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
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
  domain                = "home.mayursaxena.com"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 1024
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
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
  domain                = "home.mayursaxena.com"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 2048
  num_cpu_cores         = 4
  persistent_fs_size_gb = 8
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
  domain                = "home.mayursaxena.com"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 1024
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
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
  domain                = "home.mayursaxena.com"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 2048
  num_cpu_cores         = 2
  persistent_fs_size_gb = 16
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