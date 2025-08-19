{
  description = "Nix flakes for my home network.";

  inputs = {
    # Use the nixpkgs-unstable branch
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Impermanence module
    impermanence.url = "github:nix-community/impermanence";

    # Use nix-darwin branch which uses nixpkgs-unstable
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #Home-manager for user level configs (wonder if I really need this...)
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Homebrew manager and associated taps
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

    # Secrets management with sops-nix
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nix-darwin,
    nixpkgs,
    ...
  }: let
    inherit (self) outputs;

    # All the systems I work on - which is 64 bit Linux (NixOS) and ARM64 Mac
    systems = ["x86_64-linux" "aarch64-darwin"];
    # Generator construct
    forAllSystems = nixpkgs.lib.genAttrs systems;

    # Helper function to simply make a NixOS config, passing in inputs, outputs and variables
    mkNixOSConfig = path:
      nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [path];
      };

    # Helper function to simply make a Darwin (Mac) config, passing in inputs, outputs and variables
    mkDarwinConfig = path:
      nix-darwin.lib.darwinSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [path];
      };
  in {
    # so that we can use `nix fmt .` at the shell
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # All Mac builds go here, where key is hostname and value is the config file
    darwinConfigurations = {
      "Mayurs-MacBook-Pro" = mkDarwinConfig ./hosts/Mayurs-MacBook-Pro.nix;
    };

    # All NixOS builds go here, where key is hostname and value is the config file
    nixosConfigurations = {
      "base-lxc" = mkNixOSConfig ./hosts/base-nixos-lxc-proxmox.nix;
      "base-lxc-impermanent" = mkNixOSConfig ./hosts/base-nixos-lxc-proxmox-impermanent.nix;
      "base-lxc-remote" = mkNixOSConfig ./hosts/base-nixos-lxc-proxmox-remote.nix;
      "base-lxc-impermanent-remote" = mkNixOSConfig ./hosts/base-nixos-lxc-proxmox-impermanent-remote.nix;

      "nix-builder" = mkNixOSConfig ./hosts/remote-builder.nix;
      "dns" = mkNixOSConfig ./hosts/dns-server.nix;
      "actualbudget" = mkNixOSConfig ./hosts/actualbudget.nix;
      "sabnzbd" = mkNixOSConfig ./hosts/sabnzbd.nix;
      "homepage" = mkNixOSConfig ./hosts/homepage-dashboard.nix;
      "plex" = mkNixOSConfig ./hosts/plex-server.nix;
    };
  };
}
