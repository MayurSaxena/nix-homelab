{
  config,
  pkgs,
  ...
}: {
  services.actual = {
    enable = true;
    openFirewall = true;
  };

  systemd.tmpfiles.rules = [
    "d /persistent/var/lib/private 0700 root root"
  ];

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/private/actual";
      }
    ];
  };
}
