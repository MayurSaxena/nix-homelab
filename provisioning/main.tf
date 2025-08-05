resource "proxmox_virtual_environment_download_file" "lxc_nixos-2505-x86_64" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-25.05-x86_64.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://hydra.nixos.org/job/nixos/release-25.05/nixos.proxmoxLXC.x86_64-linux/latest/download/1"
}

resource "proxmox_virtual_environment_file" "nixos_lxc_impermanence_hookscript" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "proxmox"
  file_mode    = 0700
  source_file {
    path = "../util/rootfs-impermanence.sh"
  }
}

module "nixos-test-imp" {
  source              = "./modules/nixos-lxc"
  pve_node_name       = var.pve_node_name
  ct_template_id      = proxmox_virtual_environment_download_file.lxc_nixos-2505-x86_64.id
  hostname            = "nixos-test-imp"
  domain              = "dev.home.mayursaxena.com"
  network_interfaces  = { "eth0" = 60 }
  rootfs_impermanence = true
  custom_hookscript   = proxmox_virtual_environment_file.nixos_lxc_impermanence_hookscript.id
  tags = [ "testing" ]
}

output "nixos-test-imp_info" {
  value = {
    id = module.nixos-test-imp.ct_id
    addrs = module.nixos-test-imp.ct_address
  }
}