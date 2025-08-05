{
  config,
  pkgs,
  ...
}: {
  services.technitium-dns-server = {
    enable = true;
    openFirewall = true;
  };

  environment.persistence."/persistent" = {
    directories = [
      "/etc/dns"
    ];
  };
}
