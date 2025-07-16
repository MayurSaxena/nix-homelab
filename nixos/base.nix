{
  inputs,
  config,
  pkgs,
  vars,
  ...
}: {
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  system.stateVersion = "25.11";
  nixpkgs.config.allowUnfree = true;
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
      trusted-users = ["root" "@wheel"];
    };
  };

  networking.firewall.enable = true;
  programs.zsh.enable = true;

  security.pam.sshAgentAuth.enable = true;

  sops = {
    defaultSopsFile = ./../secrets/secrets.yaml;
  };

  users.mutableUsers = false;
  users.groups.lxc_share = {
    name = "lxc_share";
    gid = 110000;
  };

  users.defaultUserShell = pkgs.zsh;

  # users.users.${vars.userName} = {
  #   enable = true;
  #   packages = [ ]; # packages only for this user
  #   shell = pkgs.zsh;
  #   isNormalUser = true;
  #   description = vars.userName;
  #   extraGroups = ["wheel"];
  #   openssh.authorizedKeys.keys = [
  #     vars.yubiRockSSHKey
  #     vars.yubiBlackSSHKey
  #   ];
  #   hashedPassword = "$6$6DZdHEo/gEypbTV1$9GGIZ0M4klwCCE4ca7GniPJrzt/ppzdh8zgWKvD.CHtmoLVM74NFr6Qo0ETCNVv7Q290O34BsvxcQkVeIGFRb1";
  # };

  users.users.root = {
    openssh.authorizedKeys.keys = [
      vars.yubiRockSSHKey
      vars.yubiBlackSSHKey
    ];
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  environment.systemPackages = with pkgs; [
    git
  ];
}
