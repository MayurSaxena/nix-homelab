{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.nix-homebrew.darwinModules.nix-homebrew];

  # TODO: Need these for secrets decryption - probably doesn't have to be system-wide though...
  environment.systemPackages = with pkgs; [
    age
    age-plugin-yubikey
    sops
    openssh
  ];

  # Homebrew Installation Manager
  nix-homebrew = {
    user = "msaxena"; # Primary user for homebrew is going to be me
    enable = true;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
    };
    mutableTaps = false; # Don't allow the user to manage taps with `brew tap`
    autoMigrate = true; # If Homebrew is already installed, bring it in.
  };

  # Homebrew config
  homebrew = {
    enable = true;
    global = {
      autoUpdate = true; # Allow Homebrew to update itself when running `brew` commands
    };
    # So that our configs are idempotent, don't update Homebrew itself or formulae / casks
    # Additionally, `zap` removes all files associated with casks - questionable which files though.
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
      # Several casks below (google-chrome, iterm2, claude, rustdesk, utm, steam,
      # prusaslicer) were installed manually before being added here. `brew bundle`
      # hard-errors on an app that already exists at a cask's target path unless told to
      # overwrite it; --force is the only bundle-level flag for that (--adopt exists on
      # `brew install --cask` but isn't exposed through `brew bundle`). It deletes the
      # existing .app and reinstalls fresh rather than adopting in place - fine here since
      # these apps keep their real state in ~/Library, not inside the bundle - and only
      # bites on first install: once a cask is in Homebrew's Caskroom, `brew bundle` skips
      # it on later switches (upgrade = false above) regardless of this flag.
      extraFlags = ["--force"];
    };
    # nix-homebrew taps homebrew/core, homebrew/cask and homebrew/bundle above, but that's
    # a separate mechanism from this Brewfile. Without these declared here too,
    # `brew bundle cleanup` sees them as untracked taps and wants to untap them - which
    # means uninstalling every cask first, since they all belong to homebrew/cask. That's
    # what forces the interactive confirmation during every switch's cleanup phase.
    taps = ["homebrew/core" "homebrew/cask" "homebrew/bundle"];
    brews = []; # Realistically anything here should just be imported with `nix` in `environment.systemPackages`
    casks = [
      # GUI apps are better through Homebrew for now because they symlink properly
      "wireshark-app"
      "db-browser-for-sqlite"
      "discord"
      "notion"
      "plex"
      "signal"
      "visual-studio-code"
      "yubico-authenticator"
      "windows-app"
      "vlc"
      "google-chrome"
      "iterm2"
      "claude"
      "rustdesk"
      "utm"
      "steam"
      "prusaslicer"
    ];
    masApps = {
      # Apps that are in the Mac App Store
      "Bitwarden" = 1352778147;
      "The Unarchiver" = 425424353;
      "Tailscale" = 1475387142;
      "WireGuard" = 1451685025;
      "Keynote" = 409183694;
      "Numbers" = 409203825;
      "Pages" = 409201541;
      "Pixelmator Pro" = 1289583905;
      "Xcode" = 497799835;
    };
  };
}
