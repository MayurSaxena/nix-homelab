{
  inputs,
  outputs,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./base-nixos-lxc-proxmox.nix
    ./../modules/nixos/root-password.nix
    inputs.nix-minecraft.nixosModules.minecraft-servers
  ];

  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;
    servers.pixelheim = {
      enable = true;
      autoStart = true;
      serverProperties = {
        motd = "Pixelheim";
        max-players = 10;
        online-mode = true;
        gamemode = "survival";
        difficulty = 2;
        white-list = true;
      };
      package = pkgs.paperServers.paper;
      jvmOpts = "-Xms2G -Xmx6G";
      symlinks = {
        # TODO: Symlink in the geyser and floodgate configs? Or generate them here.
        "plugins/Geyser-Spigot.jar" = inputs.geysermc-geyser-spigot;
        "plugins/floodgate-spigot.jar" = inputs.geysermc-floodgate-spigot;
        "plugins/Geyser-Spigot/packs/GeyserOptionalPack.mcpack" = inputs.geysermc-optional-pack;
        "plugins/Geyser-Spigot/extensions/ThirdPartyCosmetics.jar" = inputs.geysermc-3p-cosmetics;
      };
      whitelist = {
        "Mercuron" = "935bb415-cb6b-433c-842c-9cb16f7bf956";
        ".Lazerblade31415" = "00000000-0000-0000-0009-01f6e397cac2";
      };
    };
  };

  programs.tmux.enable = true;

  # No impermanence yet, but would likely just be
  # - /srv/minecraft/

  networking.firewall = {
    allowedUDPPorts = [19132];
    allowedTCPPorts = [19132];
  };
}
