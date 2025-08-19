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
    ./../modules/nixos/remote-builds.nix
    ./../modules/nixos/root-password.nix

    ./../services/actual-budget.nix
  ];
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";
}
