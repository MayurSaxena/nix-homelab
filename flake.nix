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

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, nix-homebrew, homebrew-bundle, homebrew-core, homebrew-cask }: {
    darwinConfigurations = {
      "Mayurs-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [ ./macos.nix
                    home-manager.darwinModules.home-manager
                    nix-homebrew.darwinModules.nix-homebrew
                    {
                      nix-homebrew = {
                        user = "msaxena";
                        enable = true;
                        taps = {
                          "homebrew/homebrew-core" = homebrew-core;
                          "homebrew/homebrew-cask" = homebrew-cask;
                          "homebrew/homebrew-bundle" = homebrew-bundle;
                        };
                        mutableTaps = false;
                        autoMigrate = true;
                      };
                    }
                    ./msaxena.nix
                  ];
      };
    };
  };
}
