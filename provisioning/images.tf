# CI publishes a single LXC base image, rebuilt by the nightly workflow after
# it bumps flake.lock (see .github/workflows/nightly.yml); the `nightly` tag
# and release always track the tip of main. There used to be a `prod` tag
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

# ---------------------------------------------------------------------------
# Windows lab media (see LAB.md).
#
# Only two of the three ISOs the Windows pipeline needs can be declared here, and the
# split is an upstream constraint rather than a gap worth closing:
#
#   Server 2025 evaluation  fwlink redirects to a stable software-static.download URL
#   virtio-win              Fedora publishes permanent, versioned archive URLs
#   Windows 11 Pro          Microsoft's consumer download page signs a per-session CDN
#                           URL that expires ~24h after the page generates it
#
# The last therefore cannot be a `url` here at all: any value committed would fail the
# very next day. It is a documented one-time manual upload to local:iso, and
# provisioning/vms.tf refers to it by file name only. Do not "fix" this by pasting
# a fresh signed link -- it will break, and it will break a day later, at apply time,
# on a machine that was working yesterday.
#
# One Windows 11 ISO covers every client: the domain-joined workstations and the
# FLARE-VM box all come from a single Pro template, left unactivated. See the edition
# rationale in LAB.md, including the one thing that would justify adding an
# Enterprise template later.
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_download_file" "windows_server_2025_eval" {
  content_type = "iso"
  datastore_id = "local"
  file_name    = "windows-server-2025-eval.iso"
  node_name    = var.pve_node_name

  # fwlink 2293312 is Microsoft's stable entry point for the en-us x64 Server 2025
  # evaluation; it currently lands on build 26100.1742. Left un-pinned deliberately,
  # since the evaluation clock resets at sysprep /generalize and a newer build only
  # means less to patch during the Packer run.
  url = "https://go.microsoft.com/fwlink/?linkid=2293312"

  # ~5.6GB. The provider's default upload timeout assumes something appliance-sized and
  # aborts partway through a download this large.
  upload_timeout = 7200

  # An interrupted download leaves a short file that Packer would boot into a failed
  # install rather than a clear error, so let a re-apply replace it.
  overwrite = true
}

resource "proxmox_virtual_environment_download_file" "virtio_win" {
  content_type = "iso"
  datastore_id = "local"
  file_name    = "virtio-win.iso"
  node_name    = var.pve_node_name

  # Pinned to an exact version, unlike the Windows ISO above: these are the storage and
  # network drivers Windows setup loads to see its own disk, so a silent driver bump is a
  # way to make a previously working template build start failing for no visible reason.
  # The moving "stable-virtio/virtio-win.iso" URL redirects here; follow it to find the
  # current version when bumping.
  url = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/virtio-win-0.1.302.iso"

  # Fedora publishes a CHECKSUM file for the RPMs in that directory but not for the ISO,
  # so there is nothing upstream to verify against. The pinned version is the control.
  upload_timeout = 1800
}
