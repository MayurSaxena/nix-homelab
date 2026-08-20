{
  inputs,
  outputs,
  config,
  ...
}: let
  domain = config.custom.domain;
  staticProxyPort = 8000;
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
    timeZone = "Australia/Canberra";
    urls = ["https://yamtrack.${domain}"];
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

  # gunicorn doesn't serve its own static assets (no whitenoise; see the
  # module's `host` option doc) and Caddy lives on a separate host with no
  # access to this container's /nix/store, so a small local Caddy serves
  # /static/ from the package output and proxies everything else to
  # gunicorn. Keeps the shared Caddy's vhost a single reverse_proxy line.
  services.caddy = {
    enable = true;
    virtualHosts."http://:${toString staticProxyPort}".extraConfig = ''
      handle_path /static/* {
        root * ${config.services.yamtrack.package}/share/yamtrack/src/staticfiles
        file_server
      }
      reverse_proxy 127.0.0.1:${toString config.services.yamtrack.port}
    '';
  };

  networking.firewall.allowedTCPPorts = [staticProxyPort];

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/yamtrack";
        user = "yamtrack";
        group = "yamtrack";
        mode = "0750";
      }
      # redis-yamtrack holds only cache/broker data (module's own doc: not
      # a concern for impermanence) and the local caddy above does no ACME
      # (HTTP-only, no domain) -- neither needs a persistence entry.
    ];
  };
}
