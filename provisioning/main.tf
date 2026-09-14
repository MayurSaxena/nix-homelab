# source_raw rather than source_file, because source_file never notices an edit.
#
# The provider's read for a local source_file computes its "changed" flag by writing the
# file's mtime and size into state and then reading back the values it just wrote, so the
# comparison is against itself and is always false. Editing this script would upload
# nothing, with a clean plan and a stale script still running on the node -- and this
# script is what performs every impermanent host's rootfs rollback, so a silent no-op here
# is expensive. Upstream closed the issue as not planned and named this as the workaround.
#
# source_raw.data is ForceNew, so a content change replaces the file deterministically. One
# consequence to expect rather than be alarmed by: because the resource is replaced, its id
# reads as "known after apply", so every container referencing it plans as an in-place
# update. Those settle to the identical volume id (local:snippets/rootfs-impermanence.sh)
# and change nothing on the container; they are the cost of the script being managed at
# all, and only appear on an apply where the script's content actually changed.
resource "proxmox_virtual_environment_file" "nixos_lxc_impermanence_hookscript" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.pve_node_name
  # Quoted: the schema type is string and HCL has no octal literal, so an unquoted 0700 is
  # the decimal number 700 that happens to stringify to a value the provider then parses as
  # octal. Same result, by coincidence rather than by intent.
  file_mode = "0700"
  source_raw {
    data      = file("../assets/rootfs-impermanence.sh")
    file_name = "rootfs-impermanence.sh"
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
  memory_size_mb     = 8192
  num_cpu_cores      = 8
  rootfs_size_gb     = 32
  ct_template_id     = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
  pool_id             = "production"
  startup_order       = 3
  rootfs_impermanence = true
  custom_hookscript   = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                = ["terraform", "downloader", "host-mount"]
}

module "homepage" {
  source             = "./modules/nixos-lxc"
  pve_node_name      = var.pve_node_name
  ct_description     = "Homepage Dashboard (Terraform)"
  hostname           = "homepage"
  domain             = "home.internal"
  network_interfaces = { "eth0" = 20 }
  ipv4_settings      = "dhcp"
  ipv6_settings      = "auto"
  # Homepage itself idles around 200MB, but autoUpgrade's nightly local
  # `nix eval` of the whole flake peaks near 830MB on top of that, which
  # OOM-killed the upgrade at 1024MB. Same bump as yamtrack and trek.
  memory_size_mb        = 2048
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
  nix_fs_size_gb        = 8
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  persistent_fs_size_gb = 64
  nix_fs_size_gb        = 12
  additional_mount_points = [{
    vol     = "/mnt/MediaBox/media/"
    ct_path = "/media/IronWolf"
    backup  = false
  }]
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  nix_fs_size_gb        = 8
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  hostname           = "servarr"
  domain             = "home.internal"
  network_interfaces = { "eth0" = 20 }
  ipv4_settings      = "dhcp"
  ipv6_settings      = "auto"
  memory_size_mb     = 2048
  num_cpu_cores      = 2
  # Each *arr service stores SQLite DBs and cache under /var/lib — 20GB gives
  # comfortable headroom for four services plus index caches.
  persistent_fs_size_gb = 20
  nix_fs_size_gb        = 12
  additional_mount_points = [{
    vol     = "/mnt/MediaBox/"
    ct_path = "/media/IronWolf"
    backup  = false
  }]
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
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
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
  pool_id               = "production"
  startup_order         = 2
  rootfs_impermanence   = true
  custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                  = ["terraform", "monitoring"]
}

module "yamtrack" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "Yamtrack Media Tracker (Terraform)"
  hostname              = "yamtrack"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 2048
  num_cpu_cores         = 2
  persistent_fs_size_gb = 4
  # Yamtrack's Python dependency set (Django, Celery, Pillow, etc.) is
  # bigger than actualbudget's Node closure, so give /nix more room.
  nix_fs_size_gb      = 12
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
  pool_id             = "production"
  startup_order       = 3
  rootfs_impermanence = true
  custom_hookscript   = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                = ["terraform", "media"]
}

module "trek" {
  source                = "./modules/nixos-lxc"
  pve_node_name         = var.pve_node_name
  ct_description        = "TREK Travel Planner (Terraform)"
  hostname              = "trek"
  domain                = "home.internal"
  network_interfaces    = { "eth0" = 20 }
  ipv4_settings         = "dhcp"
  ipv6_settings         = "auto"
  memory_size_mb        = 2048
  num_cpu_cores         = 2
  persistent_fs_size_gb = 8
  nix_fs_size_gb        = 10
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-standard-nightly.id
  pool_id               = "production"
  startup_order         = 3
  rootfs_impermanence   = true
  custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                  = ["terraform", "travel"]
}
