{pkgs, ...}: {
  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      oh-my-zsh = {
        enable = true;
        plugins = ["sudo"];
      };
    };

    oh-my-posh = {
      enable = true;
      enableZshIntegration = true;
      useTheme = "M365Princess";
    };
  };
}
