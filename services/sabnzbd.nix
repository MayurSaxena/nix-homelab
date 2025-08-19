{
  config,
  pkgs,
  ...
}: {
  services.sabnzbd = {
    enable = true;
    openFirewall = true;
    user = "sabnzbd";
    group = "sabnzbd";
  };

  users.users.sabnzbd.extraGroups = [ "lxc_share" ];

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/sabnzbd";
      }
    ];
  };
}
