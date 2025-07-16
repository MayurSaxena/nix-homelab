{pkgs, ...}: {
  home = {
    packages = with pkgs; [
      curl
      wget
      jq
      nerd-fonts.fira-code
      nixos-rebuild
      alejandra
    ];
  };
}
