{
  pkgs,
  vars,
  ...
}: {
  system.stateVersion = "25.05";
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
    };
  };

  users.mutableUsers = false;
  users.users.msaxena = {
    isNormalUser = true;
    description = "msaxena";
    extraGroups = ["networkmanager" "wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMDUuPzOBdRwbr6st5HJ4MveSMM6QvrjRzqF5FVLfS5 msaxena@Mayurs-MacBook-Pro.local"
    ];
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  environment.systemPackages = with pkgs; [
    git
  ];
}
