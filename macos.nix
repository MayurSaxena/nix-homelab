{ pkgs, ...}:
{
    # List packages installed in system profile. To search by name, run:
    # $ nix-env -qaP | grep wget
    environment.systemPackages =
      [ pkgs.vim
        pkgs.wget
        pkgs.mas
      ];

    # Not needed if using Determinate Systems installer but needed for normal Nix.
    nix.settings.experimental-features = "nix-command flakes";

    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    # TODO: Figure out what this means.
    system.stateVersion = 6;


    security.pam.services.sudo_local.touchIdAuth = true;
    security.pam.services.sudo_local.watchIdAuth = true;

    networking.applicationFirewall.enable = true;

    programs.tmux = {
      enable = true;
      enableMouse = true;
      enableSensible = true;
    };

    programs.vim = {
      enable = true;
      enableSensible = true;
    };

    programs.zsh = {
      enable = true;
      enableAutosuggestions = true;
      enableFastSyntaxHighlighting = true;
    };

    users.users.msaxena = {
        name = "msaxena";
        home = "/Users/msaxena";
    };

    system.primaryUser = "msaxena";

    system.defaults.".GlobalPreferences"."com.apple.mouse.scaling" = 1.0;
    system.defaults.".GlobalPreferences"."com.apple.sound.beep.sound" = /System/Library/Sounds/Basso.aiff;

    homebrew = {
      enable = true;
      onActivation.cleanup = "uninstall";
      taps = [];
      brews = [ ];
      casks = [ "wireshark-app" "db-browser-for-sqlite" "discord" "plex" "signal" "visual-studio-code"];
      masApps = {
        "Bitwarden" = 1352778147;
        "Yubico Authenticator" = 1497506650;
        "The Unarchiver" = 425424353;
        "Tailscale" = 1475387142;
        "WireGuard" = 1451685025;
        "Windows App" = 1295203466;

        "Keynote" = 409183694;
        "Numbers" = 409203825;
        "Pages" = 409201541;
        "Pixelmator Pro" = 1289583905;

        "Xcode" = 497799835;
      };
    };  
  }