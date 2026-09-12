{
  lib,
  pkgs,
  config,
  ...
}: {
  imports = [
    ./shell.nix # zsh, prompt, CLI tools, Ghostty
    ./git.nix # git, delta, lazygit, gh, ssh
    # ./aerospace.nix # tiling window manager; delete this import to go back to plain macOS
  ];

  home = rec {
    stateVersion = "25.05";
    username = "msaxena";
    packages = with pkgs; [
      curl
      wget
      jq
      # Default global Node. Needed on PATH for GUI apps that spawn node/npx and never see
      # a shell - Claude Desktop's MCP servers - so direnv/devenv can't cover it; per-project
      # majors still come from devenv. Shadows the unmanaged /usr/local/bin/node 18 pkg
      # install, since /etc/profiles/per-user precedes /usr/local/bin on PATH.
      nodejs_24
      nixos-rebuild
      alejandra
      opentofu
      devenv
      claude-code
      just # runs the recipes in ./justfile
      nano # the editor the shell history actually shows; EDITOR is set below
      dust # du, readable
      duf # df, readable
      uv # `uv venv` / `uv pip` instead of hand-made ~/venv virtualenvs from here on
      nil # Nix language server for VS Code's nix-ide extension
      terminal-notifier # Claude Code notification hook, see .claude/notify.sh below
      # Only this user decrypts secrets (the YubiKey is in the login session), so these are
      # per-user rather than in environment.systemPackages.
      age
      age-plugin-yubikey
      sops
      ykman
    ];

    # Set the home directory differently based on platform
    homeDirectory = lib.mkMerge [
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux "/home/${username}")
      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin "/Users/${username}")
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

      # system.defaults.screencapture.location points here; macOS silently falls back to
      # the Desktop when the folder is missing, so make sure it exists.
      "Pictures/Screenshots/.keep".text = "";

      # VS Code settings, out-of-store on purpose: VS Code writes this file from its own
      # settings UI, which a read-only store symlink would break, so the symlink points at
      # the checkout and git tracks the edits instead. The absolute path is required (a
      # relative one would resolve to the flake's store copy) and ties this to the same
      # checkout location custom.auto-upgrade-mac.checkoutPath already assumes.
      "Library/Application Support/Code/User/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/Projects/nix-homelab/modules/home-manager/vscode/settings.json";

      # Claude Code status line. Referenced from ~/.claude/settings.json (statusLine.command),
      # which stays hand-managed: Claude Code writes to that file itself, and home-manager's
      # programs.claude-code would turn it into a read-only store symlink.
      ".claude/statusline.sh" = {
        executable = true;
        text = ''
          #!/bin/sh
          ${pkgs.jq}/bin/jq -r '[
            .model.display_name,
            (.workspace.current_dir | sub("^" + env.HOME; "~")),
            ((.context_window.used_percentage // 0 | floor | tostring) + "% ctx"),
            ("$" + ((.cost.total_cost_usd // 0) * 100 | round / 100 | tostring))
          ] | join("  ")'
        '';
      };
      # Claude Code notification hook. Indirection so the hook line in settings.json never
      # embeds a store path that goes stale on the next nixpkgs bump.
      ".claude/notify.sh" = {
        executable = true;
        text = ''
          #!/bin/sh
          exec ${pkgs.terminal-notifier}/bin/terminal-notifier \
            -title "Claude Code" -message "''${1:-Needs attention}" -group claude-code
        '';
      };
    };

    # Environment variables to be set.
    sessionVariables = {
      SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
      EDITOR = "nano";
      VISUAL = "nano";
    };
  };

  # One theme for every program home-manager knows how to theme (Ghostty, bat, fzf,
  # starship, btop, delta, lazygit...). Mocha matches the VS Code theme already in use; the
  # terminal stays dark while macOS itself follows AppleInterfaceStyleSwitchesAutomatically.
  catppuccin = {
    enable = true;
    autoEnable = true; # explicit: upstream is changing enable's meaning and warns otherwise
    flavor = "mocha";
  };

  # Because DS_Store files on Mac are annoying
  targets.darwin.defaults = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    "com.apple.desktopservices".DSDontWriteNetworkStores = true;
    "com.apple.desktopservices".DSDontWriteUSBStores = true;
  };

  sops = {
    # the age key file can be found at the following path
    # look for referenced secrets in the secrets file named after the user
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ./../../secrets/msaxena.yaml;
    # need this so that the launchd agent uses age-plugin-yubikey to decrypt the secrets using a yubikey
    environment = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      PATH = lib.mkForce "${pkgs.age-plugin-yubikey}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    };
    # Secrets that need to be decrypted and made available.
    secrets = {
      "ssh-keys/mbp-ed25519" = {
        mode = "0600";
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
      };
      # Declared here but consumed by the root auto-upgrade daemon
      # (custom.auto-upgrade-mac), which reads the decrypted file from this
      # user's home. The Mac has no system-level sops, because decryption needs
      # the YubiKey and only this user's login agent has it.
      "discord/mac-update-webhook" = {};
      # Same arrangement: decrypted here, copied into /etc/nix by
      # custom.remote-builds-mac's activation script. Read from common.yaml
      # (encrypted to *all-keys, which includes msaxena-keys) so the fleet and
      # the Mac share one key with one place to rotate it.
      "remote-builder/private-key" = {
        sopsFile = ./../../secrets/common.yaml;
      };
    };
  };
}
