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

  services.plex = {
    enable = true;
    openFirewall = true;
    user = "plex";
    group = "plex";
    dataDir = "/var/lib/plex";
  };

  # So that the user running the program can access the host mount
  users.users.plex.extraGroups = ["lxc_share"];

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/plex";
        user = "plex";
        group = "plex";
        mode = "0755";
      }
    ];
  };
}
