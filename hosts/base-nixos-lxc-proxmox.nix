{
  inputs,
  outputs,
  config,
  ...
}: {
  # Base image for Proxmox LXC containers.
  # Impermanence and remote-builds are disabled by default and enabled
  # via inline module overrides in flake.nix for each image variant.
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;
}
