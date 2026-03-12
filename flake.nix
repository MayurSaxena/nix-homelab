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

    # For Determinate Nix
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    # Home-manager for user-level config: zsh, git, SSH keys, sops secrets
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

    # Minecraft server module with Spigot/Paper support
    nix-minecraft.url = "github:Infinidoge/nix-minecraft";

    # GeyserMC allows Bedrock (mobile/console) clients to connect to the Java
    # server. Floodgate handles Bedrock player auth. Pinned directly because
    # nix-minecraft doesn't package them and GeyserMC requires exact version
    # matches between Geyser, Floodgate, and the server build.
    geysermc-geyser-spigot = {
      url = "https://download.geysermc.org/v2/projects/geyser/versions/2.9.2/builds/1022/downloads/spigot";
      flake = false;
    };

    geysermc-floodgate-spigot = {
      url = "https://download.geysermc.org/v2/projects/floodgate/versions/2.2.5/builds/126/downloads/spigot";
      flake = false;
    };

    geysermc-3p-cosmetics = {
      url = "https://download.geysermc.org/v2/projects/thirdpartycosmetics/versions/1.0.0/builds/9/downloads/thirdpartycosmetics";
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

    # All the systems I work on - which is 64 bit Linux (NixOS) and ARM64 Mac
    systems = ["x86_64-linux" "aarch64-darwin"];
    # Generator construct
    forAllSystems = nixpkgs.lib.genAttrs systems;

    # Helper function to simply make a NixOS config, passing in inputs, outputs and variables
    mkNixOSConfig = paths:
      nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [./modules/nixos] ++ nixpkgs.lib.toList paths;
      };

    # Helper function to simply make a Darwin (Mac) config, passing in inputs, outputs and variables
    mkDarwinConfig = paths:
      nix-darwin.lib.darwinSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [inputs.determinate.darwinModules.default] ++ nixpkgs.lib.toList paths;
      };
  in {
    # so that we can use `nix fmt .` at the shell
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # All Mac builds go here, where key is hostname and value is the config file
    darwinConfigurations = {
      "Mayurs-MacBook-Pro" = mkDarwinConfig ./hosts/Mayurs-MacBook-Pro.nix;
    };

    # All NixOS builds go here, where key is hostname and value is the config file
    nixosConfigurations = let
      baseLxc = ./hosts/base-nixos-lxc-proxmox.nix;
    in {
      # CI image variants — one base file, composed with inline overrides
      "base-lxc" = mkNixOSConfig baseLxc;
      "base-lxc-impermanent" = mkNixOSConfig [baseLxc {custom.impermanence.enable = true;}];
      "base-lxc-remote" = mkNixOSConfig [baseLxc {custom.remote-builds.enable = true;}];
      "base-lxc-impermanent-remote" = mkNixOSConfig [
        baseLxc
        {
          custom.impermanence.enable = true;
          custom.remote-builds.enable = true;
        }
      ];

      "nix-builder" = mkNixOSConfig ./hosts/remote-builder.nix;
      "dns" = mkNixOSConfig ./hosts/dns-server.nix;
      "actualbudget" = mkNixOSConfig ./hosts/actualbudget.nix;
      "sabnzbd" = mkNixOSConfig ./hosts/sabnzbd.nix;
      "homepage" = mkNixOSConfig ./hosts/homepage-dashboard.nix;
      "plex" = mkNixOSConfig ./hosts/plex-server.nix;
      "overseerr" = mkNixOSConfig ./hosts/overseerr.nix;
      "paperless" = mkNixOSConfig ./hosts/paperless.nix;
      "minecraft" = mkNixOSConfig [
        ./hosts/minecraft.nix
        {nixpkgs.overlays = [inputs.nix-minecraft.overlay];}
      ];
      "files" = mkNixOSConfig ./hosts/files.nix;
      "caddy" = mkNixOSConfig ./hosts/caddy.nix;
      "beszel-hub" = mkNixOSConfig ./hosts/beszel-hub.nix;
      "servarr" = mkNixOSConfig ./hosts/servarr.nix;
    };
  };
}
