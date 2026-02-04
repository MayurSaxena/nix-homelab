{
  lib,
  pkgs,
  config,
  ...
}: {
  home = rec {
    stateVersion = "25.05";
    username = "msaxena";
    packages = with pkgs; [
      curl
      wget
      jq
      nerd-fonts.fira-code
      nixos-rebuild
      alejandra
      opentofu
      starship
      devenv
    ];

    # Set the home directory differently based on platform
    homeDirectory = lib.mkMerge [
      (lib.mkIf pkgs.stdenv.isLinux "/home/${username}")
      (lib.mkIf pkgs.stdenv.isDarwin "/Users/${username}")
    ];

    # Plaintext files that can be mirrored or set.
    file = {
      ".ssh/id_ed25519.pub" = {
        enable = true;
        source = ./../../assets/id_ed25519.pub;
      };
      ".config/sops/age/keys.txt" = {
        enable = true;
        source = ./../../assets/age_keys.txt;
      };
    };

    # Environment variables to be set.
    sessionVariables = lib.mkIf pkgs.stdenv.isDarwin {
      SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
    };
  };

  # Individual program configurations
  programs = {
    zsh = {
      enable = true;
      enableCompletion = false;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        "ll" = "ls -al";
        ".." = "cd ..";
      };
      initContent = ''
        eval "$(ssh-agent -s)" &> /dev/null
        ssh-add ~/.ssh/id_ed25519 &> /dev/null
        ssh-add ~/.ssh/id_ed25519_sk &> /dev/null
        ssh-add ~/.ssh/id_ed25519_sk2 &> /dev/null
      '';

      # oh-my-zsh = {
      #   enable = true;
      #   plugins = ["sudo"];
      # };
    };

    starship = {
      enable = true;
    };

    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    # oh-my-posh = {
    #   enable = true;
    #   enableZshIntegration = true;
    #   useTheme = "aliens";
    # };

    ssh = {
      enable = true;
      package = pkgs.openssh;
      extraConfig = "StrictHostKeyChecking accept-new";
    };

    git = {
      enable = true;
      settings = {
        user = {
          email = "me@mayursaxena.com";
          name = "Mayur Saxena";
        };
      };
    };
  };

  # Because DS_Store files on Mac are annoying
  targets.darwin.defaults = lib.mkIf (pkgs.stdenv.isDarwin) {
    "com.apple.desktopservices".DSDontWriteNetworkStores = true;
    "com.apple.desktopservices".DSDontWriteUSBStores = true;
  };

  # Graceful service starting on activation (ignored on Mac?)
  systemd.user.startServices = "sd-switch";

  sops = {
    # the age key file can be found at the following path
    # look for referenced secrets in the secrets file named after the user
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ./../../secrets/msaxena.yaml;
    # need this so that the launchd agent uses age-plugin-yubikey to decrypt the secrets using a yubikey
    environment = lib.mkIf (pkgs.stdenv.isDarwin) {
      PATH = lib.mkForce "${pkgs.age-plugin-yubikey}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    };
    # Secrets that need to be decrypted and made available.
    secrets = {
      "ssh-keys/mbp-ed25519" = {
        mode = "0600";
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
      };
    };
  };
}
