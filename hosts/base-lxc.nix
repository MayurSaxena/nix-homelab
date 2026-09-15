{
  inputs,
  outputs,
  config,
  ...
}: {
  # Base image for Proxmox LXC containers — used bare, with no overrides, as
  # the single `base-lxc` CI image in flake.nix. Impermanence and
  # remote-builds are disabled here; each real host enables what it needs
  # from its own file on the first switch, not from this file or flake.nix.
  #
  # The image itself is nixpkgs' own `system.build.image` output (the proxmox-lxc tarball)
  # of this configuration (nixos-generators has been upstreamed), which the
  # nightly workflow builds and attaches to the `nightly` release.
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;

  # The only opt-out of the (default-true) failure notifier. This image's host
  # key isn't in .sops.yaml, so declaring any sops secret here would make
  # sops-install-secrets fail on the image's very first boot, before the first
  # switch ever runs.
  custom.failure-notifications.enable = false;
}
