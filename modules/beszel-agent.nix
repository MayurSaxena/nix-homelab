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
        );
        KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvFWswu12TgUd9mGWKTaAjniR5fwbxLdpCyW9j5XWBJ";
        LISTEN = "45876";
      };
    };
  };
}
