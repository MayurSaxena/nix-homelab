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

  imports = [inputs.nur.repos.msaxena.modules.nixos.trek];

  sops.secrets = {
    "trek-secrets" = {
      format = "dotenv";
      sopsFile = ./../secrets/trek.env;
      restartUnits = ["trek.service"];
    };
  };

  services.trek = {
    enable = true;
    # Default listenAddress (127.0.0.1) assumes the Docker single-container
    # case; the shared caddy fronting this host lives in a different
    # container, so it needs to be reachable over the LAN.
    listenAddress = "0.0.0.0";
    openFirewall = true;
    allowedOrigins = ["https://trek.${domain}"];
    # Caddy terminates TLS in front of this host and forwards
    # X-Forwarded-Proto, which TREK always trusts (see module doc) --
    # only enable this behind a TLS-terminating proxy, which is the case here.
    forceHttps = true;
    environmentFiles = [config.sops.secrets."trek-secrets".path];
  };

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/trek";
        user = "trek";
        group = "trek";
        mode = "0700";
      }
    ];
  };
}
