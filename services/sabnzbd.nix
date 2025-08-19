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

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/sabnzbd";
      }
    ];
  };
}
