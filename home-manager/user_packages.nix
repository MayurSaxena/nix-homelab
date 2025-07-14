{pkgs, ...}: {
  home = {
    packages = with pkgs; [
      openssh
      curl
      wget
      jq
      nerd-fonts.fira-code
      nixos-rebuild
      alejandra
    ];
  };
}
