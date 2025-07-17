{
  inputs,
  outputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./../modules/macos/base.nix # Apply the system wide default config
  ];

  # Set the platform for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "aarch64-darwin";

  # Use home-manager to manage the user configs
  home-manager = {
    extraSpecialArgs = {inherit inputs outputs;};
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [inputs.sops-nix.homeManagerModules.sops]; # for secret management

    # Configure the msaxena user
    users.msaxena = {
      imports = [
        ./../modules/home-manager/msaxena.nix
      ];
    };
  };
}
