# CI publishes a single LXC base image, rebuilt on every push of the `nightly`
# tag (see .github/workflows/generate-lxc.yml). There used to be a `prod` tag
# and a `remotebuild` variant that pre-baked custom.remote-builds.enable for
# hosts that couldn't reach nix-builder during bootstrap — both are gone.
# `prod` was never automated (nothing but a human ever pushed it, and it had
# gone stale), and the first-switch workflow now always passes
# --build-host/--target-host explicitly (see provisioning/onboard-host.sh), so
# there's no "can't reach nix-builder yet" case left for a pre-baked image to
# solve.
#
# Impermanence was never a template dimension: OpenTofu creates the persistent
# mount points itself, and the host's own flake turns impermanence on during
# the first `nixos-rebuild switch`.

resource "proxmox_virtual_environment_download_file" "nixos-standard-nightly" {
  content_type = "vztmpl"
  datastore_id = "local"
  file_name    = "nixos-standard-nightly.tar.xz"
  node_name    = var.pve_node_name
  url          = "https://github.com/MayurSaxena/nix-homelab/releases/download/nightly/nixos-proxmox-lxc-standard.tar.xz"
  overwrite    = true
}
