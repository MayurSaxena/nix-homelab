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

  system.stateVersion = "25.05";
  nixpkgs.config.allowUnfree = true;
  nix = {
    gc = {
      # Automatic garbage collection every day
      automatic = true;
      dates = "daily";
    };
    settings = {
      # enable flakes
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
      # allow root and sudoers
      trusted-users = ["root" "@wheel"];
    };
  };
  # enable the firewall
  networking.firewall.enable = true;

  # not even sure if this does anything
  security.pam.sshAgentAuth.enable = true;

  sops = {
    defaultSopsFile = pkgs.lib.mkDefault ./../../secrets/common.yaml;
    secrets."passwords/root" = {
      sopsFile = ./../../secrets/common.yaml;
      neededForUsers = true;
    };
  };

  # don't allow changes to users to persist
  users.mutableUsers = false;

  # Set root user login methods
  users.users.root = {
    hashedPasswordFile = config.sops.secrets."passwords/root".path;
    openssh.authorizedKeys.keys = [
      vars.yubiRockSSHKey
      vars.yubiBlackSSHKey
    ];
  };
  # system wide packages
  environment.systemPackages = with pkgs; [
    git
  ];

  environment.shellAliases = {
    ll = "ls -al";
    ".." = "cd ..";
  };

  # Configure SSH to be allowed through firewall, only allow key-based root access
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "prohibit-password";
    };
  };
}
