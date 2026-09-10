{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.nix-homebrew.darwinModules.nix-homebrew];

  # openssh stays system-wide so that root (the nix-daemon's remote builds, sudo
  # darwin-rebuild) and the user run the same OpenSSH. age, age-plugin-yubikey and sops
  # live in home.packages instead: only the user ever decrypts, and sops-nix's launchd
  # agent references age-plugin-yubikey by store path rather than PATH.
  environment.systemPackages = [pkgs.openssh];

  # System-wide because this is the only place nix-darwin can put fonts where macOS indexes
  # them; a font in home.packages is never seen by GUI apps. The family name this installs
  # is "JetBrainsMono Nerd Font" (Ghostty and VS Code both reference it).
  fonts.packages = [pkgs.nerd-fonts.jetbrains-mono];

  # Homebrew Installation Manager
  nix-homebrew = {
    user = "msaxena"; # Primary user for homebrew is going to be me
    enable = true;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
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
      # Several casks below were installed manually before being added here. `brew bundle`
      # hard-errors on an app that already exists at a cask's target path unless told to
      # overwrite it; --force is the only bundle-level flag for that (--adopt exists on
      # `brew install --cask` but isn't exposed through `brew bundle`). It deletes the
      # existing .app and reinstalls fresh rather than adopting in place - fine here since
      # these apps keep their real state in ~/Library, not inside the bundle - and only
      # bites on first install: once a cask is in Homebrew's Caskroom, `brew bundle` skips
      # it on later switches (upgrade = false above) regardless of this flag. It is also
      # what `cleanup` itself needs since Homebrew's bundle refactor (nix-darwin #1787).
      extraFlags = ["--force"];
    };
    # nix-homebrew taps homebrew/core and homebrew/cask above, but that's a separate
    # mechanism from this Brewfile. Without these declared here too, `brew bundle cleanup`
    # sees them as untracked taps and wants to untap them - which means uninstalling every
    # cask first, since they all belong to homebrew/cask. That's what forces the
    # interactive confirmation during every switch's cleanup phase.
    taps = ["homebrew/core" "homebrew/cask"];
    brews = []; # Realistically anything here should just be imported with `nix` in `home.packages`
    # GUI apps come from Homebrew: a cask puts a real .app in /Applications with a stable
    # path, so Spotlight, the Dock and each app's own updater all just work.
    casks = [
      # Terminal and editor
      "ghostty" # config lives in modules/home-manager/shell.nix (programs.ghostty)
      "visual-studio-code" # extensions declared in `vscode` below; settings.json via home-manager

      # Desktop utilities. None of these have declarable settings; see README for the
      # one-time setup each needs.
      "jordanbaird-ice@beta" # menu bar tidy; the beta is the version that works on macOS 26
      "stats" # menu bar CPU/memory/network/battery
      "shottr" # screenshots with rulers, OCR and a colour picker
      "monitorcontrol" # brightness/volume keys for external displays (not through DisplayLink)

      # Communication
      "discord"
      "signal"

      # Media and misc
      "plex"
      "vlc"
      "notion"
      "google-chrome"
      "claude"
      "steam"

      # Networking, security, virtualisation
      "wireshark-app"
      "yubico-authenticator"
      "windows-app"
      "rustdesk"
      "utm"

      # Making things
      "db-browser-for-sqlite"
      "prusaslicer"
    ];
    # Extensions for the cask-installed VS Code. `brew bundle` only installs the missing
    # ones - it never upgrades (VS Code does that itself) and, at the pinned brew, `cleanup`
    # has no VS Code handling at all, so an extension dropped from this list has to be
    # uninstalled by hand with `code --uninstall-extension`.
    vscode = [
      "anthropic.claude-code"
      "antyos.openscad"
      "catppuccin.catppuccin-vsc"
      "cweijan.dbclient-jdbc"
      "cweijan.vscode-postgresql-client2"
      "eamodio.gitlens"
      "ginfuru.better-nunjucks"
      "github.vscode-github-actions"
      "jnoortheen.nix-ide" # Nix LSP client; the `nil` server comes from home.packages
      "ms-azuretools.vscode-containers"
      "ms-python.debugpy"
      "ms-python.python"
      "ms-python.vscode-pylance"
      "ms-python.vscode-python-envs"
      "ms-toolsai.jupyter"
      "ms-toolsai.jupyter-keymap"
      "ms-toolsai.jupyter-renderers"
      "ms-toolsai.vscode-jupyter-cell-tags"
      "ms-toolsai.vscode-jupyter-slideshow"
      "ms-vscode-remote.remote-ssh"
      "ms-vscode-remote.remote-ssh-edit"
      "ms-vscode.remote-explorer"
      "opentofu.vscode-opentofu"
    ];
    masApps = {
      # Apps that are in the Mac App Store
      "Bitwarden" = 1352778147;
      "The Unarchiver" = 425424353;
      "Tailscale" = 1475387142;
      "WireGuard" = 1451685025;
      # "Keynote" = 409183694;
      # "Numbers" = 409203825;
      # "Pages" = 409201541;
      "Pixelmator Pro" = 1289583905;
      "Xcode" = 497799835;
    };
  };
}
