{
  config,
  inputs,
  ...
}: {
  # By default on any new Mac install things in macos/packages.nix at the system level
  imports = [
    inputs.nur.modules.darwin.default
    ./packages.nix
    ./remote-builds.nix
    ./auto-upgrade.nix
  ];

  # Determinate Nix manages nix.conf directly (gc, optimise, settings).
  # nix.* options in nix-darwin are a no-op when determinateNix.enable = true.
  determinateNix = {
    enable = true;
    # nix.gc is inert under Determinate, so this is the only declarative GC knob. Left
    # unset it silently falls back to the daemon default; explicit is better with an
    # 18 GB store.
    determinateNixd.garbageCollector.strategy = "automatic";
  };

  # claude-code is unfree; NixOS hosts get this from modules/nixos/default.nix,
  # but mkDarwinConfig doesn't inject a shared base, so it's set here instead.
  nixpkgs.config.allowUnfree = true;

  # Enable Touch ID and Watch ID for sudo
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
  };

  # Turn on the firewall
  networking.applicationFirewall.enable = true;

  # nix-darwin's programs.zsh runs compinit from /etc/zshrc and home-manager runs it again
  # from ~/.zshrc. Keep the system half (nix-zsh-completions on fpath) but let only the user
  # shell call compinit: two compinits cost startup time and were part of the completion
  # breakage that led to commit 619ab4d disabling completion altogether.
  programs.zsh.enableGlobalCompInit = false;

  # Focus ring around the active window. AeroSpace (modules/home-manager/aerospace.nix)
  # draws no decoration of its own, so without this it is easy to lose track of which tile
  # has focus. Colours are Catppuccin Mocha mauve / surface1 to match everything else.
  services.jankyborders = {
    enable = true;
    width = 5.0;
    hidpi = true;
    active_color = "0xffcba6f7";
    inactive_color = "0xff45475a";
  };

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
        # Trackpad tracking speed
        "com.apple.trackpad.scaling" = 0.875;

        # Captured from the live machine so a fresh Mac lands in the same place.
        AppleShowAllExtensions = true;
        AppleMeasurementUnits = "Centimeters";
        AppleMetricUnits = 1; # nix-darwin types this as an enum 0/1, not a bool
        AppleTemperatureUnit = "Celsius";
        "com.apple.swipescrolldirection" = false; # "natural" scrolling off
        NSAutomaticPeriodSubstitutionEnabled = false;

        # Opinionated. Each one is a one-line revert.
        KeyRepeat = 2; # faster than the GUI slider allows
        InitialKeyRepeat = 15;
        ApplePressAndHoldEnabled = false; # holding a key repeats it instead of the accent popup
        NSAutomaticQuoteSubstitutionEnabled = false; # smart quotes corrupt pasted shell and Nix
        NSAutomaticDashSubstitutionEnabled = false;
        NSNavPanelExpandedStateForSaveMode = true; # save dialogs open expanded
        NSNavPanelExpandedStateForSaveMode2 = true;
        NSDocumentSaveNewDocumentsToCloud = false; # save to disk, not iCloud, by default
      };
      # System alert sound
      ".GlobalPreferences"."com.apple.sound.beep.sound" = /System/Library/Sounds/Basso.aiff;
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true; # Auto OS updates
      controlcenter.BatteryShowPercentage = true; # Show the battery percent

      # Minimal dock: only running apps plus Mail, on the left. Spotlight launches everything.
      dock = {
        orientation = "left";
        show-process-indicators = false;
        show-recents = false;
        static-only = true;
        tilesize = 128;
        # The live machine had magnification on with a magnified size *smaller* than
        # tilesize, so icons shrank on hover. Off is what it effectively looked like.
        magnification = false;
        # 1 = disabled. Declared so a new Mac doesn't inherit Apple's defaults.
        wvous-tl-corner = 1;
        wvous-bl-corner = 1;
        wvous-tr-corner = 1;
        wvous-br-corner = 1;
        minimize-to-application = true;
        expose-group-apps = true;
        mru-spaces = false; # never reorder Spaces by most recent use
        persistent-apps = [{app = "/System/Applications/Mail.app";}];
      };

      # A Finder that shows everything (extensions, hidden files, path and status bars),
      # opens on Home in list view, and searches the current folder first.
      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        ShowPathbar = true;
        ShowStatusBar = true;
        FXEnableExtensionChangeWarning = false;
        FXDefaultSearchScope = "SCcf";
        FXPreferredViewStyle = "Nlsv"; # list view
        NewWindowTarget = "Home"; # nix-darwin writes this as PfHm
        ShowExternalHardDrivesOnDesktop = true;
        ShowRemovableMediaOnDesktop = true;
        ShowHardDrivesOnDesktop = false;
        ShowMountedServersOnDesktop = false;
        _FXSortFoldersFirst = true;
        FXRemoveOldTrashItems = true; # empty items older than 30 days
      };

      screencapture = {
        # Absolute on purpose: this key does not expand ~. The folder itself is created by
        # home-manager (macOS silently falls back to the Desktop if it is missing).
        location = "${config.users.users.msaxena.home}/Pictures/Screenshots";
        type = "png";
        disable-shadow = true;
      };

      # Stage Manager off. Native drag-to-edge tiling stays on for the odd mouse-driven
      # layout even though AeroSpace does the day-to-day tiling.
      WindowManager = {
        GloballyEnabled = false;
        EnableTilingByEdgeDrag = true;
        EnableTopTilingByEdgeDrag = true;
        EnableTilingOptionAccelerator = true;
        EnableTiledWindowMargins = false;
        EnableStandardClickToShowDesktop = false;
      };

      # Each display gets its own Spaces
      spaces.spans-displays = false;

      # Probably useful
      iCal = {
        "TimeZone support enabled" = true;
      };

      loginwindow.GuestEnabled = false;

      # Menu bar clock settings
      menuExtraClock = {
        Show24Hour = false;
        ShowAMPM = true;
        ShowDate = 0;
        ShowDayOfWeek = true;
        ShowSeconds = false;
      };

      # Trackpad gestures
      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
        TrackpadRightClick = true;
      };

      # Domains nix-darwin has no typed option for
      CustomUserPreferences = {
        "com.apple.TextEdit".RichText = false; # plain text by default
        "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
      };
    };
  };
}
