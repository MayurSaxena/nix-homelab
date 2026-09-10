# The interactive shell: zsh, prompt, the CLI tools that replace the coreutils defaults,
# and the terminal that hosts them. Deliberately conservative: `cd` and `ls` keep their
# meaning (they are the two most-typed commands); only `ll` changes.
{config, ...}: {
  programs = {
    zsh = {
      enable = true;
      # Re-enabled. Commit 619ab4d's "conflicting subpath" was buildEnv's file-collision
      # error: enableCompletion adds nix-zsh-completions to the per-user profile, and
      # nixos-rebuild also ships share/zsh/site-functions/_nixos-rebuild. home-manager now
      # adds nix-zsh-completions with lib.lowPrio, so the two no longer collide. compinit
      # itself runs only here (programs.zsh.enableGlobalCompInit = false system-side).
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      history = {
        size = 50000;
        save = 50000;
      };
      shellAliases = {
        ll = "eza -la --git --group-directories-first";
        ".." = "cd ..";
      };
    };

    starship = {
      enable = true;
      settings = {
        add_newline = false;
        directory.truncation_length = 3;
        nix_shell.format = "via [$symbol$name]($style) ";
        # Never used; each one costs a lookup on every prompt.
        aws.disabled = true;
        gcloud.disabled = true;
        azure.disabled = true;
      };
    };

    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    zoxide.enable = true; # `z <dir>` / `zi`; cd itself is deliberately left alone

    fzf = {
      enable = true;
      defaultCommand = "fd --type f --hidden --exclude .git";
      fileWidget.command = "fd --type f --hidden --exclude .git";
      changeDirWidget.command = "fd --type d --hidden --exclude .git";
    };

    eza = {
      enable = true;
      # The integration would alias ls itself; only ll is wanted (see zsh.shellAliases).
      enableZshIntegration = false;
      git = true;
    };

    bat = {
      enable = true;
      config.style = "plain";
    };

    fd.enable = true;
    ripgrep.enable = true;
    btop.enable = true;

    # `, <command>` runs any program in nixpkgs without installing it: `, ffmpeg -i in.mov`.
    # The module also points programs.nix-index at the prebuilt database from the flake
    # input, so nothing has to be indexed locally, and gives zsh a command-not-found
    # handler that names the package providing a missing command.
    nix-index-database.comma.enable = true;

    tealdeer = {
      enable = true;
      settings.updates.auto_update = true;
    };

    # `nh darwin switch` shows a closure diff before activating and has a real progress
    # UI; `nh clean` prunes old generations. darwin-rebuild still works underneath.
    nh = {
      enable = true;
      flake = "${config.home.homeDirectory}/Projects/nix-homelab";
    };

    # Ghostty runs quick-terminal-first: no Dock icon, no window at login, and a drop-down
    # from the top of the screen on the same hotkey iTerm2's hotkey window used. Ghostty
    # documents macos-hidden as being meant for exactly this mode.
    ghostty = {
      enable = true;
      # The .app comes from the Homebrew cask (nixpkgs' ghostty is Linux-only, and
      # ghostty-bin would land in ~/Applications/Home Manager Apps and miss Ghostty's own
      # updater). null still lets home-manager own ~/.config/ghostty/config.
      package = null;
      enableZshIntegration = true;
      settings = {
        font-family = "JetBrainsMono Nerd Font";
        font-size = 13;
        # theme is written by catppuccin.ghostty

        # `global:` fires while another app is focused, which needs Accessibility
        # permission; Ghostty asks for it once on first launch.
        keybind = ["global:ctrl+backquote=toggle_quick_terminal"];
        quick-terminal-position = "top";
        # "main" is whichever screen currently has keyboard focus, so the drop-down
        # follows the laptop or a docked display without being told which.
        quick-terminal-screen = "main";
        quick-terminal-autohide = true; # get out of the way the moment focus moves

        # No Dock icon and no entry in the Cmd-Tab switcher. The trade: that applies to
        # *every* Ghostty window, not just the quick terminal, so a full window opened with
        # Cmd-N is reachable by clicking it or through AeroSpace, not by Cmd-Tab. Set this
        # to "never" to get the normal app back. It also means macOS will no longer switch
        # keyboard layouts automatically, which costs nothing here with one layout.
        macos-hidden = "always";
        initial-window = false; # launching at login must not pop a window
        window-save-state = "never"; # ... and must not restore last session's windows either
      };
    };
  };

  # Start Ghostty at login so the hotkey always has something to summon. `open` rather than
  # the binary inside the bundle: launching the Mach-O directly loses the app-bundle
  # identity macOS ties window management and permission grants to. One-shot -- `open`
  # exits as soon as Ghostty is up, and quitting Ghostty on purpose should not relaunch it.
  launchd.agents.ghostty = {
    enable = true;
    config = {
      ProgramArguments = ["/usr/bin/open" "-a" "/Applications/Ghostty.app"];
      RunAtLoad = true;
      KeepAlive = false;
    };
  };
}
