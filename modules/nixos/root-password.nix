{
  inputs,
  config,
  pkgs,
  ...
}: {
  sops = {
    secrets."passwords/root" = {
      sopsFile = ./../../secrets/common.yaml;
      neededForUsers = true;
    };
  };

  users.users.root = {
    hashedPasswordFile = config.sops.secrets."passwords/root".path;
  };
}
