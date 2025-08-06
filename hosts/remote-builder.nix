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

  users.users.nixbuild = {
    createHome = true;
    isNormalUser = true;
    openssh.authorizedKeys.keyFiles = [
      ./../assets/remote-builder.pub
    ];
  };

  nix.settings.trusted-users = [
    "nixbuild"
  ];
}
