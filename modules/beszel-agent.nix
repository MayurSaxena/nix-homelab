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

    sops.secrets."beszel-agent-secrets" = {
      format = "dotenv";
      sopsFile = ./../secrets/beszel-agent.env;
      restartUnits = ["beszel-agent.service"];
    };

    services.beszel.agent = {
      enable = true;
      # TOKEN (the permanent universal token) lives in the sops secret below,
      # never here -- environment.* is baked verbatim into the world-readable
      # unit file at build time, which would defeat the whole point of
      # encrypting it.
      environmentFile = config.sops.secrets."beszel-agent-secrets".path;
      environment = {
        # Format: "path__Display Name" — beszel separates path and label with "__"
        EXTRA_FILESYSTEMS = lib.concatStringsSep "," (
          ["/nix__Nix Store"]
          ++ lib.optionals config.custom.impermanence.enable ["${config.custom.impermanence.persistence-root}__Persistent Storage"]
          ++ map (m: "${m.path}__${m.name}") cfg.extraFilesystems
        );
        # Public key of the Beszel Hub. Hardcoded so agents can be deployed
        # automatically without a manual key exchange step — the hub's private
        # key never leaves the hub container. Still required even though the
        # agent now only ever uses HUB_URL/TOKEN below: the agent's own
        # main() loads this unconditionally at startup (log.Fatal if it and
        # KEY_FILE/-key are all unset) before it even decides which
        # connection mode to use.
        KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvFWswu12TgUd9mGWKTaAjniR5fwbxLdpCyW9j5XWBJ";
        # Agent dials out to the hub and self-registers as a new system on
        # first connect (Beszel's "universal token" push mode) -- no manual
        # "Add System" step in the hub UI, ever, for any host. Routed through
        # caddy rather than beszel-hub.home.internal:8090 directly: every
        # other proxied service already reaches its target through caddy
        # instead of crossing VLANs (beszel-hub sits on VLAN 10, most hosts
        # are on VLAN 20) to hit an internal port directly, and caddy's own
        # beszel vhost already has a long read_timeout tuned for this kind of
        # persistent connection.
        HUB_URL = "https://beszel.${config.custom.domain}";
      };
    };
  };
}
