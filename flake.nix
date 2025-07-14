{
  description = "Nix flakes for my home network (macOS and nixOS)";

  inputs = {
    # Use the nixpkgs-unstable branch
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Use nix-darwin branch which uses nixpkgs-unstable
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs = inputs @ {
    self,
    nix-darwin,
    nixpkgs,
    ...
  }: let
    inherit (self) outputs;

    systems = ["x86_64-linux" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;

    mkNixOSConfig = path:
      nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [path];
      };

    mkDarwinConfig = path:
      nix-darwin.lib.darwinSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [path];
      };
  in {
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    darwinConfigurations = {
      "Mayurs-MacBook-Pro" = mkDarwinConfig ./hosts/Mayurs-MacBook-Pro.nix;
    };

    nixosConfigurations = {
      "nixos-test" = mkNixOSConfig ./hosts/nixos-test.nix;
    };
  };
}
