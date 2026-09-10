{
  inputs,
  outputs,
  ...
}: {
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./../modules/macos/base.nix # Apply the system wide default config
  ];

  # Set the platform for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "aarch64-darwin";

  custom.remote-builds-mac.enable = true;
  custom.auto-upgrade-mac.enable = true;

  # Use home-manager to manage the user configs
  home-manager = {
    extraSpecialArgs = {inherit inputs outputs;};
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops # secret management
      inputs.catppuccin.homeModules.catppuccin # one theme across every themed program
      inputs.nix-index-database.homeModules.nix-index # the database `comma` searches
    ];

    # Configure the msaxena user
    users.msaxena = {
      imports = [
        ./../modules/home-manager/msaxena.nix
      ];
    };
  };
}
