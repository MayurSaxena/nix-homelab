resource "proxmox_virtual_environment_file" "nixos_lxc_impermanence_hookscript" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "proxmox"
  file_mode    = 0700
  source_file {
    path = "../util/rootfs-impermanence.sh"
  }
}

module "nix-builder" {
  source         = "./modules/nixos-lxc"
  pve_node_name  = var.pve_node_name
  num_cpu_cores  = 4
  ct_description = <<EOT
Remote Build Server for NixOS

Managed by Terraform
EOT

  hostname            = "nix-builder"
  domain              = "dev.home.mayursaxena.com"
  network_interfaces  = { "eth0" = 60 }
  memory_size_mb      = 4096
  rootfs_size_gb      = 8
  ct_template_id      = proxmox_virtual_environment_download_file.nixos-standard-prod.id
  startup_order       = 1
  rootfs_impermanence = false
}

module "dns-server" {
  source         = "./modules/nixos-lxc"
  pve_node_name  = var.pve_node_name
  num_cpu_cores  = 1
  ct_description = <<EOT
Technitium DNS Server

Managed by Terraform
EOT

  hostname              = "dns"
  domain                = "home.mayursaxena.com"
  dns_servers           = ["127.0.0.1", "::1"]
  network_interfaces    = { "eth0" = 10 }
  ipv4_settings         = "10.0.10.2/24;10.0.10.1"
  ipv6_settings         = "2403:5816:961a:1::2/64;2403:5816:961a:1::1"
  memory_size_mb        = 1024
  persistent_fs_size_gb = 2
  ct_template_id        = proxmox_virtual_environment_download_file.nixos-impermanent-remotebuild-prod.id
  pool_id               = "production"
  startup_order         = 1
  rootfs_impermanence   = true
  custom_hookscript     = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags                  = ["dhcp", "dns", "networking"]
}
