{
  config,
  pkgs,
  ...
}: {
  services.technitium-dns-server = {
    enable = true;
    openFirewall = true;
    firewallUDPPorts = [
      53
      67 #DHCP
    ];
    firewallTCPPorts = [
      53
      5380
    ];
  };

  systemd.tmpfiles.rules = [
    "d /persistent/var/lib/private 0700 root root"
  ];

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/private/technitium-dns-server";
      }
    ];
  };
}
