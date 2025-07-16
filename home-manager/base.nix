{
  lib,
  pkgs,
  vars,
  ...
}: {
  imports = [./user_packages.nix];
  home = {
    stateVersion = "25.05";
    username = vars.userName;
    homeDirectory = lib.mkMerge [
      (lib.mkIf pkgs.stdenv.isLinux "/home/${vars.userName}")
      (lib.mkIf pkgs.stdenv.isDarwin "/Users/${vars.userName}")
    ];
    sessionVariables = lib.mkIf pkgs.stdenv.isDarwin {
      SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
    };
    file = {
      # relative to $HOME based on key name
      ".config/sops/age/keys.txt" = {
        enable = true;
        source = ./../assets/age_keys.txt;
      };
    };
  };
  targets.darwin.defaults = lib.mkIf (pkgs.stdenv.isDarwin) {
    "com.apple.desktopservices".DSDontWriteNetworkStores = true;
    "com.apple.desktopservices".DSDontWriteUSBStores = true;
  };

  systemd.user.startServices = "sd-switch";
}
