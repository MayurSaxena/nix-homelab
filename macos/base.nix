{
  pkgs,
  vars,
  ...
}: {
  imports = [./packages.nix];

  nix = {
    gc = {
      automatic = true;
    };
    optimise = {
      automatic = true;
    };
    settings = {
      experimental-features = "nix-command flakes";
      sandbox = true;
      extra-sandbox-paths = ["/private/tmp/" "/private/var/tmp/"];
      trusted-users = [
        "root"
        "@admin"
      ];
    };
  };

  # Enable Touch ID and Watch ID for sudo
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
  };

  # Turn on the firewall
  networking.applicationFirewall.enable = true;

  users.users.${vars.userName} = {
    name = vars.userName;
    home = "/Users/${vars.userName}";
  };

  programs.zsh.enable = true;

  system = {
    stateVersion = 6;
    primaryUser = vars.userName;
    defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyleSwitchesAutomatically = true;
        "com.apple.trackpad.scaling" = 0.875;
      };

      ".GlobalPreferences"."com.apple.sound.beep.sound" = /System/Library/Sounds/Basso.aiff;
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;
      controlcenter.BatteryShowPercentage = true;

      dock = {
        orientation = "left";
        show-process-indicators = false;
        show-recents = false;
        static-only = true;
      };

      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
        FXEnableExtensionChangeWarning = false;
        FXDefaultSearchScope = "SCcf";
        ShowStatusBar = true;
      };

      iCal = {
        "TimeZone support enabled" = true;
      };

      menuExtraClock = {
        Show24Hour = false;
        ShowAMPM = true;
        ShowDate = 0;
        ShowDayOfWeek = true;
      };

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };
  };
}
