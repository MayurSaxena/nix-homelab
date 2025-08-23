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
      PAPERLESS_URL = "https://paperless.home.mayursaxena.com";
      PAPERLESS_USE_X_FORWARD_HOST = true;
      PAPERLESS_USE_X_FORWARD_PORT = true;
      PAPERLESS_PROXY_SSL_HEADER = ["HTTP_X_FORWARDED_PROTO" "https"];
    };
  };

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/paperless";
      }
    ];
  };
}
