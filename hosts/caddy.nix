{
  inputs,
  outputs,
  config,
  pkgs,
  ...
}: {
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;
  custom.impermanence.enable = true;
  custom.remote-builds.enable = true;
  custom.root-password.enable = true;
  custom.beszel-monitoring-agent.enable = true;

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
      hash = "sha256-Zls+5kWd/JSQsmZC4SRQ/WS+pUcRolNaaI7UQoPzJA0=";
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
        reverse_proxy https://proxmox.home.internal:8006
        import use-external-dns-acme
      '';
      "dns-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://dns.home.internal:5380
        import use-external-dns-acme
      '';
      "home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://homepage.home.internal:8082
        import use-external-dns-acme
      '';
      "beszel.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://beszel-hub.home.internal:8090 {
          transport http {
            read_timeout 360s
          }
        }
        request_body {
          max_size 10MB
        }
        import use-external-dns-acme
      '';

      "budget.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://actualbudget.home.internal:3000
        import use-external-dns-acme
      '';
      "paperless-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://paperless.home.internal:8000
        import use-external-dns-acme
      '';
      "plex-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://plex.home.internal:32400
        import use-external-dns-acme
      '';
      "overseerr-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://overseerr.home.internal:5055
        import use-external-dns-acme
      '';
      "sabnzbd-web.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://sabnzbd.home.internal:8080
        import use-external-dns-acme
      '';

      "radarr.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://servarr.home.internal:7878
        import use-external-dns-acme
      '';
      "sonarr.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://servarr.home.internal:8989
        import use-external-dns-acme
      '';
      "bazarr.home.mayursaxena.com".extraConfig = ''
        reverse_proxy http://servarr.home.internal:6767
        import use-external-dns-acme
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [80 443];

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
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
