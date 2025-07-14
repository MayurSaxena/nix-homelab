{
  lib,
  pkgs,
  vars,
  ...
}: {
  home = {
    stateVersion = "25.05";
    username = vars.userName;
    homeDirectory = lib.mkMerge [
      (lib.mkIf pkgs.stdenv.isLinux "/home/${vars.userName}")
      (lib.mkIf pkgs.stdenv.isDarwin "/Users/${vars.userName}")
    ];

    shellAliases = {
      "ll" = "ls -al";
      ".." = "cd ..";
    };
  };

  systemd.user.startServices = "sd-switch";
}
