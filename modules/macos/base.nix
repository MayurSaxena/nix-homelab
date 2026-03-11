{pkgs, ...}: {
  # By default on any new Mac install things in macos/packages.nix at the system level
  imports = [
    ./packages.nix
    ./remote-builds.nix
  ];

  # Determinate Nix manages nix.conf directly (gc, optimise, settings).
  # nix.* options in nix-darwin are a no-op when determinateNix.enable = true.
  determinateNix.enable = true;

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
