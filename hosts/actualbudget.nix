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
