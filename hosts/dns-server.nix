{
  inputs,
  outputs,
  config,
  ...
}: {
  imports = [
    ./base-nixos-lxc-proxmox-impermanent-remote.nix
    ./../modules/nixos/root-password.nix
  ];
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

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

  # So that dynamic-user folders stay private because impermanence default perms are 755
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
