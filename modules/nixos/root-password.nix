{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  options.custom.root-password = {
    enable = lib.mkEnableOption "root password";
  };

  config = lib.mkIf config.custom.root-password.enable {
    sops = {
      secrets."passwords/root" = {
        sopsFile = ./../../secrets/common.yaml;
        neededForUsers = true;
      };
    };

    users.users.root = {
      hashedPasswordFile = config.sops.secrets."passwords/root".path;
    };
  };
}
