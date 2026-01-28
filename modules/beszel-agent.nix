{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.custom.beszel-monitoring-agent;
in {
  options.custom.beszel-monitoring-agent = {
    enable = lib.mkEnableOption "custom beszel monitoring agent";

    extraFilesystems = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "Filesystem path";
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name";
          };
        };
      });
      default = [];
      description = "Extra filesystems to monitor for disk usage.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.dbus.implementation = "broker"; # there's a bug in systemd right now?
    services.beszel.agent = {
      enable = true;
      openFirewall = true;
      environment = {
        EXTRA_FILESYSTEMS = lib.concatStringsSep "," (
          ["/nix__Nix Store"]
          ++ lib.optionals config.custom.impermanence.enable ["${config.custom.impermanence.persistence-root}__Persistent Storage"]
          ++ map (m: "${m.path}__${m.name}") cfg.extraFilesystems
        );
        KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvFWswu12TgUd9mGWKTaAjniR5fwbxLdpCyW9j5XWBJ";
        LISTEN = "45876";
      };
    };
  };
}
