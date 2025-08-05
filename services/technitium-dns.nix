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

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/private/technitium-dns-server";
        user = "technitium-dns-server";
        group = "technitium-dns-server";
        mode = "0755";
      }
    ];
  };
}
