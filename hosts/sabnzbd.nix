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

  services.sabnzbd = {
    enable = true;
    openFirewall = true; #TCP 8080
    user = "sabnzbd";
    group = "sabnzbd";
  };

  # Have to SSH to the host and make a tunnel to localhost:8080 because the default
  # config doesn't listen on all interfaces :(
  # TODO: Front this with an nginx or something?

  # So that the user running the program can access the host mount
  users.users.sabnzbd.extraGroups = ["lxc_share"];

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/sabnzbd";
      }
    ];
  };
}
