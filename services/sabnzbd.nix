{
  config,
  pkgs,
  ...
}: {
  services.sabnzbd = {
    enable = true;
    openFirewall = true; #TCP 8080
    user = "sabnzbd";
    group = "sabnzbd";
  };

  # Have to SSH to the host and make a tunnel to localhost:8080 because the default
  # config doesn't listen on all interfaces :(
  # TODO: Front this with an nginx or something?

  users.users.sabnzbd.extraGroups = [ "lxc_share" ];

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/sabnzbd";
      }
    ];
  };
}
