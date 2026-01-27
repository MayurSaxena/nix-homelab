{
  inputs,
  outputs,
  config,
  lib,
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
    "sabnzbd-secrets" = {
      format = "ini";
      owner = config.services.sabnzbd.user;
      group = config.services.sabnzbd.group;
      sopsFile = ./../secrets/sabnzbd.ini;
      restartUnits = ["sabnzbd.service"];
    };
  };

  services.sabnzbd = {
    enable = true;
    openFirewall = true; #TCP 8080
    user = "sabnzbd";
    group = "sabnzbd";
    secretFiles = [config.sops.secrets."sabnzbd-secrets".path];
    settings = {
      misc = {
        host = "::";
        bandwidth_max = "15M";
        inet_exposure = 0;
        local_ranges = "10.0.0.0/16, 2403:5816:df19::/48";
        permissions = "777";
        download_dir = "/data/incomplete";
        complete_dir = "/data/complete";
        cache_limit = "500M";
        host_whitelist = "sabnzbd-web.home.mayursaxena.com";
      };
      servers = {
        newsgroup_ninja = {
          name = "news.newsgroup.ninja";
          displayname = "news.newsgroup.ninja";
          host = "news.newsgroup.ninja";
          port = 563;
          enable = false;
          priority = 3;
        };

        news_newsgroupdirect = {
          name = "news.newsgroupdirect.com";
          displayname = "news.newsgroupdirect.com";
          host = "news.newsgroupdirect.com";
          port = 563;
          connections = 15;
          enable = true;
          priority = 0;
        };

        super_newsgroupdirect = {
          name = "super.newsgroupdirect.com";
          displayname = "super.newsgroupdirect.com";
          host = "super.newsgroupdirect.com";
          port = 563;
          connections = 10;
          enable = true;
          priority = 2;
        };

        farm_newsgroupdirect = {
          name = "farm.newsgroupdirect.com";
          displayname = "farm.newsgroupdirect.com";
          host = "farm.newsgroupdirect.com";
          port = 443;
          connections = 15;
          enable = true;
          priority = 1;
        };
      };
    };
  };

  # So that the user running the program can access the host mount
  users.users.${config.services.sabnzbd.user}.extraGroups = ["lxc_share"];

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/sabnzbd";
      }
    ];
  };
}
