resource "proxmox_virtual_environment_download_file" "nixos-standard-prod" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-standard-prod.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/prod/nixos-proxmox-lxc-standard.tar.xz"
  overwrite    = true
}

resource "proxmox_virtual_environment_download_file" "nixos-impermanent-prod" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-impermanent-prod.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/prod/nixos-proxmox-lxc-impermanent.tar.xz"
  overwrite    = true
}

resource "proxmox_virtual_environment_download_file" "nixos-standard-remotebuild-prod" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-standard-remotebuild-prod.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/prod/nixos-proxmox-lxc-standard-remotebuild.tar.xz"
  overwrite    = true
}

resource "proxmox_virtual_environment_download_file" "nixos-impermanent-remotebuild-prod" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-impermanent-remotebuild-prod.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/prod/nixos-proxmox-lxc-impermanent-remotebuild.tar.xz"
  overwrite    = true
}

resource "proxmox_virtual_environment_download_file" "nixos-standard-nightly" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-standard-nightly.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/nightly/nixos-proxmox-lxc-standard.tar.xz"
  overwrite    = true
}

resource "proxmox_virtual_environment_download_file" "nixos-impermanent-nightly" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-impermanent-nightly.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/nightly/nixos-proxmox-lxc-impermanent.tar.xz"
  overwrite    = true
}

resource "proxmox_virtual_environment_download_file" "nixos-standard-remotebuild-nightly" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-standard-remotebuild-nightly.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/nightly/nixos-proxmox-lxc-standard-remotebuild.tar.xz"
  overwrite    = true
}

resource "proxmox_virtual_environment_download_file" "nixos-impermanent-remotebuild-nightly" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-impermanent-remotebuild-nightly.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/nightly/nixos-proxmox-lxc-impermanent-remotebuild.tar.xz"
  overwrite    = true
}