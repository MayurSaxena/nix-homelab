{
  inputs,
  outputs,
  config,
  ...
}: {
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;
  custom.impermanence.enable = true;
  custom.remote-builds.enable = true;
  custom.root-password.enable = true;
  custom.beszel-monitoring-agent.enable = true;

  sops.secrets = {
    "scrobblex-secrets" = {
      format = "dotenv";
      sopsFile = ./../secrets/scrobblex.env;
    };
  };

  services.plex = {
    enable = true;
    openFirewall = true;
    user = "plex";
    group = "plex";
    dataDir = "/var/lib/plex";
  };

  services.scrobblex = {
    enable = true;
    port = 3090;
    plexUser = ["MayurSaxena"];
    openFirewall = true;
    environmentFile = config.sops.secrets.scrobblex-secrets.path;
  };

  # So that the user running the program can access the host mount
  users.users.plex.extraGroups = ["lxc_share"];

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/plex";
        user = "plex";
        group = "plex";
        mode = "0755";
      }
      {
        directory = "/var/lib/private/scrobblex";
      }
    ];
  };
}
