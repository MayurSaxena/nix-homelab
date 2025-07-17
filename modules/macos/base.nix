{
  pkgs,
  ...
}: {
  # By default on any new Mac install things in macos/packages.nix at the system level
  imports = [./packages.nix];

  nix = {
    # Automatic garbage collection (12AM every day hopefully)
    gc = {
      automatic = true;
      interval = {
        Hour = 0;
        Minute = 0;
      };
    };
    optimise = {
      # Optimise every day at 1AM
      automatic = true;
      interval = {
        Hour = 1;
        Minute = 0;
      };
    };
    settings = {
      experimental-features = "nix-command flakes"; # Enable flakes
      sandbox = true; # Enable sandboxed builds
      # Allow these paths to be accessed in the sandbox (unsure if still necessary)
      extra-sandbox-paths = ["/private/tmp/" "/private/var/tmp/"];
      # Root and users in the admin group can manage the nix install
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

  # User info
  users.users.msaxena = {
    name = "msaxena";
    home = "/Users/msaxena";
  };

  system = {
    stateVersion = 6; # some default thing I'll probably never touch
    primaryUser = "msaxena";
    defaults = {
      NSGlobalDomain = {
        # Auto switch light and dark mode based on time
        AppleInterfaceStyleSwitchesAutomatically = true;
        # Trackpad tracking speed hopefully
        "com.apple.trackpad.scaling" = 0.875;
      };
      # System alert sound
      ".GlobalPreferences"."com.apple.sound.beep.sound" = /System/Library/Sounds/Basso.aiff;
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true; # Auto OS updates
      controlcenter.BatteryShowPercentage = true; # Show the battery percent (what does this look like on desktops?)

      # Minimal dock since I use Spotlight to launch stuff anyways
      dock = {
        orientation = "left";
        show-process-indicators = false;
        show-recents = false;
        static-only = true;
      };

      # A Finder that shows extensions (and lets me change them), starts searching in the current folder and shows path and available space
      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
        FXEnableExtensionChangeWarning = false;
        FXDefaultSearchScope = "SCcf";
        ShowStatusBar = true;
      };

      # Probably useful
      iCal = {
        "TimeZone support enabled" = true;
      };

      # Menu bar clock settings
      menuExtraClock = {
        Show24Hour = false;
        ShowAMPM = true;
        ShowDate = 0;
        ShowDayOfWeek = true;
      };

      # Trackpad gestures
      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };
  };
}
