{
  inputs,
  outputs,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./base-nixos-lxc-proxmox-impermanent-remote.nix
    ./../modules/nixos/root-password.nix
  ];
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  sops.secrets = {
    "caddy-secrets" = {
      format = "dotenv";
      sopsFile = ./../secrets/caddy.env;
    };
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = ["github.com/caddy-dns/cloudflare@v0.2.1"];
      hash = "sha256-j+xUy8OAjEo+bdMOkQ1kVqDnEkzKGTBIbMDVL7YDwDY=";
    };
    environmentFile = config.sops.secrets."caddy-secrets".path;
    # Uncomment for development.
    # acmeCA = "https://acme-staging-v02.api.letsencrypt.org/directory";
    email = "mayur.saxena1997@gmail.com";
    globalConfig = "";
    extraConfig = ''
      (use-external-dns-acme) {
        tls {
          dns cloudflare {$CF_API_TOKEN}
          resolvers 1.1.1.1 1.0.0.1
        }
      }
    '';
    virtualHosts = {
      "bikinibottom.home.mayursaxena.com".extraConfig = ''
        reverse_proxy https://10.0.10.1 {
          transport http {
            tls_insecure_skip_verify
          }
        }
        import use-external-dns-acme
      '';
      "proxmox-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy https://proxmox.home.mayursaxena.com:8006
        import use-external-dns-acme
      '';
      "dns-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://dns.home.mayursaxena.com:5380
        import use-external-dns-acme
      '';
      "home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://homepage.home.mayursaxena.com:8082
        import use-external-dns-acme
      '';

      "budget.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://actualbudget.home.mayursaxena.com:3000
        import use-external-dns-acme
      '';
      "grafana-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://grafana.home.mayursaxena.com:3000
        import use-external-dns-acme
      '';
      "influxdb-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://influxdb.home.mayursaxena.com:8086
        import use-external-dns-acme
      '';
      "paperless-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://paperless.home.mayursaxena.com:8000
        import use-external-dns-acme
      '';
      "plex-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://plex.home.mayursaxena.com:32400
        import use-external-dns-acme
      '';
      "overseerr-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://overseerr.home.mayursaxena.com:5055
        import use-external-dns-acme
      '';
      "sabnzbd-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://sabnzbd.home.mayursaxena.com:8080
        import use-external-dns-acme
      '';

      "radarr.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://servarr.home.mayursaxena.com:7878
        import use-external-dns-acme
      '';
      "sonarr.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://servarr.home.mayursaxena.com:8989
        import use-external-dns-acme
      '';
      "bazarr.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://servarr.home.mayursaxena.com:6767
        import use-external-dns-acme
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [80 443];

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/caddy";
        user = "caddy";
        group = "caddy";
        mode = "0755";
      }
    ];
  };
}
