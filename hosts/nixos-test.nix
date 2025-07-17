{
  inputs,
  outputs,
  config,
  ...
}: {
  imports = [
    ./../modules/nixos/base.nix
    ./../modules/nixos/proxmox-lxc.nix
    #./../services/netbox.nix
  ];
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  # host-specific secrets
  sops = {
    defaultSopsFile = ./../secrets/nixos-test.yaml;
  };
}
