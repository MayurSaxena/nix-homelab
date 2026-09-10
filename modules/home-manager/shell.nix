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
        # The same hotkey iTerm2's hotkey window used. `global:` works while another app
        # is focused; Ghostty asks for Accessibility permission once for that.
        keybind = ["global:ctrl+backquote=toggle_quick_terminal"];
        # theme is written by catppuccin.ghostty
      };
    };
  };
}
