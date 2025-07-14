{
  inputs,
  outputs,
  vars,
  ...
}: {
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./../macos/base.nix
  ];

  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "aarch64-darwin";

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs vars;};
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${vars.userName} = {
      imports = [
        ./../home-manager/base.nix
        ./../home-manager/zsh.nix
        ./../home-manager/git.nix
        ./../home-manager/user_packages.nix
      ];
    };
  };
}
