{
  inputs,
  outputs,
  config,
  ...
}: {
  imports = [
    ./../modules/nixos/proxmox-lxc.nix
    ./../modules/nixos/remote-builds.nix
  ];
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";
}
