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
    };
    taps = [];
    brews = []; # Realistically anything here should just be imported with `nix` in `environment.systemPackages`
    casks = [
      # GUI apps are better through Homebrew for now because they symlink properly
      "wireshark-app"
      "db-browser-for-sqlite"
      "discord"
      "plex"
      "signal"
      "visual-studio-code"
      "yubico-authenticator"
      "windows-app"
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
