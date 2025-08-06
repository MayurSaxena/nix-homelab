{
  inputs,
  outputs,
  config,
  ...
}: {
  imports = [
    ./../modules/nixos/base.nix
    ./../modules/nixos/proxmox-lxc.nix
  ];
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  services.openssh.extraConfig = "PermitEmptyPasswords yes";

  users.users.nixbuild = {
    createHome = true;
    isNormalUser = true;
    hashedPassword = "";
  };
}
