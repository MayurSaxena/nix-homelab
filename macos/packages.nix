{
  inputs,
  vars,
  ...
}: {
  imports = [inputs.nix-homebrew.darwinModules.nix-homebrew];

  nix-homebrew = {
    user = "msaxena";
    enable = true;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
    };
    mutableTaps = false;
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    global = {
      autoUpdate = true;
    };
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };
    taps = [];
    brews = [];
    casks = [
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
