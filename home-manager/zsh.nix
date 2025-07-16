{pkgs, ...}: {
  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        "ll" = "ls -al";
        ".." = "cd ..";
      };

      oh-my-zsh = {
        enable = true;
        plugins = ["sudo"];
      };
    };

    oh-my-posh = {
      enable = true;
      enableZshIntegration = true;
      useTheme = "aliens";
    };
  };
}
