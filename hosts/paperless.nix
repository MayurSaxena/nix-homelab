{
  inputs,
  outputs,
  config,
  ...
}: {
  imports = [
    ./base-nixos-lxc-proxmox-impermanent-remote.nix
    ./../modules/nixos/root-password.nix
  ];
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  sops.secrets = {
    "paperless-secrets" = {
      format = "dotenv";
      sopsFile = ./../secrets/paperless.env;
    };
  };

  services.paperless = {
    enable = true;
    dataDir = "/var/lib/paperless";
    consumptionDir = "/mnt/paperless-consume";
    environmentFile = config.sops.secrets."paperless-secrets".path;
    address = "::";
    port = 8000;
    database.createLocally = true;
    configureTika = true;
    settings = {
      PAPERLESS_URL = "https://paperless-web.home.mayursaxena.com";
      PAPERLESS_USE_X_FORWARD_HOST = true;
      PAPERLESS_USE_X_FORWARD_PORT = true;
      PAPERLESS_PROXY_SSL_HEADER = ["HTTP_X_FORWARDED_PROTO" "https"];
    };
  };

  networking.firewall.allowedTCPPorts = [config.services.paperless.port];

  systemd.tmpfiles.rules = [
    "d /persistent/var/lib/private 0700 root root"
    "d /persistent/${config.services.paperless.dataDir} 0755 paperless paperless"
    "d /persistent/${config.services.paperless.mediaDir} 0755 paperless paperless"
  ];

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/paperless";
        user = "paperless";
        group = "paperless";
      }
      {
        directory = "/var/lib/redis-paperless";
        user = "redis-paperless";
        group = "redis-paperless";
        mode = "0700";
      }
      {
        directory = "/var/lib/postgresql";
        user = "postgres";
        group = "postgres";
        mode = "0750";
      }
      {
        directory = "/var/lib/private/tika";
      }
    ];
  };
}
