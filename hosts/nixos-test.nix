{
  inputs,
  outputs,
  vars,
  ...
}: {
  imports = [
    ./../nixos/base.nix
    ./../base-configurations/proxmox-lxc.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs vars;};
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${vars.userName} = {
      imports = [./../home-manager/base.nix];
    };
  };
}
