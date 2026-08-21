{
  inputs,
  outputs,
  config,
  ...
}: let
  domain = config.custom.domain;
in {
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;
  custom.impermanence.enable = true;
  custom.remote-builds.enable = true;
  custom.root-password.enable = true;
  custom.beszel-monitoring-agent.enable = true;

  imports = [inputs.nur.repos.msaxena.modules.nixos.yamtrack];

  sops.secrets = {
    "yamtrack-secrets" = {
      format = "dotenv";
      sopsFile = ./../secrets/yamtrack.env;
      restartUnits = [
        "yamtrack-migrate.service"
        "yamtrack.service"
        "yamtrack-worker.service"
      ];
    };
  };

  services.yamtrack = {
    enable = true;
    # The module now bundles its own co-located Caddy (mirroring upstream's
    # Docker image, which bundles nginx) that serves static assets and sets
    # X-Real-IP itself -- gunicorn is no longer directly reachable, and
    # host/port now describe that proxy instead. It defaults to 127.0.0.1,
    # matching upstream's single-container assumption, but the shared caddy
    # fronting this host lives in a different container, so it needs to be
    # reachable over the LAN.
    host = "0.0.0.0";
    timeZone = "Australia/Canberra";
    urls = ["https://yamtrack.${domain}"];
    openFirewall = true;
    environmentFiles = [config.sops.secrets."yamtrack-secrets".path];
    # SQLite is enough for a single-user personal tracker (Yamtrack's own
    # recommendation); flip database.createLocally on for Postgres later
    # if this ever needs more concurrency.
  };

  services.redis.servers.yamtrack = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/yamtrack";
        user = "yamtrack";
        group = "yamtrack";
        mode = "0750";
      }
      # redis-yamtrack holds only cache/broker data (module's own doc: not
      # a concern for impermanence); the module's own co-located proxy is
      # stateless too -- neither needs a persistence entry.
    ];
  };
}
