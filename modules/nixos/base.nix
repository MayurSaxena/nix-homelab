{
  inputs,
  config,
  pkgs,
  ...
}: {
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  system.stateVersion = "25.11";
  nixpkgs.config.allowUnfree = true;
  nix = {
    gc = {
      # Automatic garbage collection every day
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 7d";
    };
    settings = {
      # enable flakes
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
      # allow root and sudoers
      trusted-users = ["root" "@wheel"];
    };
  };

  time.timeZone = "Australia/Canberra";

  # Every day around 4AM AEST so that I wake up to a nice surprise if it breaks.
  system.autoUpgrade = {
    enable = true;
    dates = "*-*-* 18:00:00 UTC";
    randomizedDelaySec = "90min";
    flake = "github:MayurSaxena/nix-homelab";
    flags = ["--refresh"];
    runGarbageCollection = true;
  };

  # enable the firewall
  networking.firewall.enable = true;

  sops = {
    defaultSopsFile = pkgs.lib.mkDefault ./../../secrets/common.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    validateSopsFiles = false;
  };
  # don't allow changes to users to persist
  users.mutableUsers = false;
  # Set root user login methods
  users.users.root = {
    openssh.authorizedKeys.keys = [
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIBKp4APmkFKNrZiS2yYZsKOgkik5XehIbqU+Li2tsFwVAAAABHNzaDo= YubiRock"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPRoNwOsZ2aVCvntOlrVKxVku+kXu8UigYvpEblIYqooAAAABHNzaDo= YubiBlack"
    ];
  };
  # system wide packages
  environment.systemPackages = with pkgs; [
    age
    age-plugin-yubikey
    sops
    git
  ];

  environment.shellAliases = {
    ll = "ls -al";
    ".." = "cd ..";
  };

  # Configure SSH to be allowed through firewall, only allow key-based root access
  services.openssh = {
    enable = true;
    startWhenNeeded = false;
    openFirewall = true;
    authorizedKeysInHomedir = false;
    settings = {
      PermitRootLogin = "prohibit-password";
    };
  };

  programs.ssh.extraConfig = "StrictHostKeyChecking=accept-new";
}
