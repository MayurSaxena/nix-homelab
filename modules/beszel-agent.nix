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
    # Required to avoid a D-Bus activation deadlock when beszel-agent starts
    # early in boot before the full D-Bus socket is ready. "broker" mode is
    # lighter and doesn't exhibit the race.
    services.dbus.implementation = "broker";
    services.beszel.agent = {
      enable = true;
      openFirewall = true;
      environment = {
        # Format: "path__Display Name" — beszel separates path and label with "__"
        EXTRA_FILESYSTEMS = lib.concatStringsSep "," (
          ["/nix__Nix Store"]
          ++ lib.optionals config.custom.impermanence.enable ["${config.custom.impermanence.persistence-root}__Persistent Storage"]
          ++ map (m: "${m.path}__${m.name}") cfg.extraFilesystems
        );
        # Public key of the Beszel Hub. Hardcoded so agents can be deployed
        # automatically without a manual key exchange step — the hub's private
        # key never leaves the hub container.
        KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvFWswu12TgUd9mGWKTaAjniR5fwbxLdpCyW9j5XWBJ";
        LISTEN = "45876"; # Beszel agent default port
      };
    };
  };
}
