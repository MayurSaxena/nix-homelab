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

    # Catppuccin theme modules for home-manager: one flavor setting themes ghostty, bat,
    # fzf, starship, btop, delta, lazygit and friends on the Mac
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Prebuilt nix-index database, so `comma` can run any program in nixpkgs without
    # installing it and without spending an hour indexing locally first
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Homebrew manager and associated taps. homebrew/bundle is deliberately absent:
    # `brew bundle` merged into Homebrew/brew itself and the tap is an empty stub.
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
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

    # NUR - community package repository
    nur = {
      url = "github:nix-community/NUR";
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

    # Every host as a check, so `nix flake check --no-build --all-systems` proves that
    # everything still *evaluates* -- which is what CI runs on every push. Building is
    # what the hosts themselves do nightly; the checks are never built in CI.
    checks = {
      x86_64-linux =
        nixpkgs.lib.mapAttrs (_: host: host.config.system.build.toplevel)
        self.nixosConfigurations;
      aarch64-darwin =
        nixpkgs.lib.mapAttrs (_: host: host.config.system.build.toplevel)
        self.darwinConfigurations;
    };

    # The tools this repo's scripts and recipes reach for, pinned by this lock. `.envrc`
    # loads it through direnv on the Mac; CI runs the linters through it. Nothing here
    # is a service dependency -- those come from the host configurations.
    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          sops
          age
          age-plugin-yubikey
          ssh-to-age # tofu provisioner: host key -> age recipient
          oath-toolkit # util/pve-auth.sh: TOTP for the Proxmox API
          opentofu
          just
          alejandra
          statix
          deadnix
          jq
        ];
      };
    });

    # All Mac builds go here, where key is hostname and value is the config file
    darwinConfigurations = {
      "Mayurs-MacBook-Pro" = mkDarwinConfig ./hosts/Mayurs-MacBook-Pro.nix;
    };

    # All NixOS builds go here, where key is hostname and value is the config file
    nixosConfigurations = let
      baseLxc = ./hosts/base-nixos-lxc-proxmox.nix;
    in {
      # CI image — one base file, no variants. Impermanence isn't pre-baked
      # (OpenTofu creates the persistent mounts, and the host's own flake
      # turns it on during the first switch); remote-builds isn't pre-baked
      # either, now that the first-switch workflow always passes
      # --build-host/--target-host explicitly (see provisioning/onboard-host.sh).
      "base-lxc" = mkNixOSConfig baseLxc;

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
      "yamtrack" = mkNixOSConfig ./hosts/yamtrack.nix;
      "trek" = mkNixOSConfig ./hosts/trek.nix;
    };
  };
}
