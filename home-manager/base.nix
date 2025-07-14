{
  lib,
  pkgs,
  vars,
  ...
}: {
  home = {
    stateVersion = "25.05";
    username = "msaxena";
    homeDirectory = lib.mkMerge [
      (lib.mkIf pkgs.stdenv.isLinux "/home/msaxena")
      (lib.mkIf pkgs.stdenv.isDarwin "/Users/msaxena")
    ];

    shellAliases = {
      "ll" = "ls -al";
      ".." = "cd ..";
    };
  };

  systemd.user.startServices = "sd-switch";
}
