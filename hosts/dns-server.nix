{
  inputs,
  outputs,
  config,
  ...
}: {
  imports = [
    ./../modules/nixos/base.nix
    ./../modules/nixos/proxmox-lxc.nix
    ./../modules/nixos/impermanence.nix

    ./../services/technitium-dns.nix
  ];
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";
}
