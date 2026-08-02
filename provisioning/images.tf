# CI publishes two LXC base images per release tag (see .github/workflows/generate-lxc.yml).
# Impermanence is deliberately not pre-baked: OpenTofu creates the persistent
# mount points itself, and the host's own flake turns impermanence on during the
# first `nixos-rebuild switch`. The only dimension worth pre-building is
# remote-builds, because `nixos-rebuild` reads the *currently active* nix.conf to
# decide where to build — a freshly-imported vanilla container has no build
# machines configured yet.
#
# Preferred bootstrap is the plain `standard` image plus a first switch run with
# --build-host/--target-host (see README). The `remotebuild` image is the
# fallback for when the deploying machine can't reach nix-builder.

resource "proxmox_virtual_environment_download_file" "nixos-standard-prod" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-standard-prod.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/prod/nixos-proxmox-lxc-standard.tar.xz"
  overwrite    = true
}

resource "proxmox_virtual_environment_download_file" "nixos-remotebuild-prod" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-remotebuild-prod.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/prod/nixos-proxmox-lxc-remotebuild.tar.xz"
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

resource "proxmox_virtual_environment_download_file" "nixos-remotebuild-nightly" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-remotebuild-nightly.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/nightly/nixos-proxmox-lxc-remotebuild.tar.xz"
  overwrite    = true
}
