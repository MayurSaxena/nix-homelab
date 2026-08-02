{
  inputs,
  outputs,
  config,
  lib,
  ...
}: let
  domain = config.custom.domain;
in {
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
    group = "lxc_share";
    secretFiles = [config.sops.secrets."sabnzbd-secrets".path];
    configFile = null;
    settings = {
      misc = {
        host = "::";
        bandwidth_max = "15M";
        inet_exposure = 0;
        local_ranges = "10.0.0.0/16, 2403:5816:df19::/48";
        permissions = "770";
        download_dir = "/data/incomplete";
        complete_dir = "/data/complete";
        cache_limit = "500M";
        host_whitelist = "sabnzbd-web.${domain}";
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

  # group = "lxc_share" above already makes lxc_share the process's primary
  # group, which is what grants access to the host mount — no extraGroups
  # line is needed on top of it.

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/sabnzbd";
        # Derived so a change to services.sabnzbd.user/group can't desync.
        # The unit sets StateDirectory=sabnzbd, so systemd re-applies these on
        # every start regardless; spelling them out documents the intent and
        # gets the bind mount right the first time it is created.
        user = config.services.sabnzbd.user;
        group = config.services.sabnzbd.group;
        mode = "0755";
      }
    ];
  };
}
