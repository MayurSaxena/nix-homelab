{
  inputs,
  outputs,
  config,
  ...
}: {
  imports = [
    ./base-nixos-lxc-proxmox-impermanent-remote.nix
    ./../modules/nixos/root-password.nix

    ./../services/homepage-dashboard.nix
  ];

  sops.secrets = {
    "homepage-secrets" = {
      format = "dotenv";
      sopsFile = ./../secrets/homepage-dashboard-secrets.env;
    };
  };
  # TODO: Figure out how to incorporate the ICMP binary in the systemd service path so that the ping arguments work.
  services.homepage-dashboard = {
    environmentFile = config.sops.secrets."homepage-secrets".path;
    allowedHosts = "localhost:8082,127.0.0.1:8082,homepage.home.mayursaxena.com:8082,home.mayursaxena.com";
    widgets = [
      {
        unifi_console = {
          href = "https://bikinibottom.home.mayursaxena.com";
          url = "https://bikinibottom.home.mayursaxena.com";
          username = "{{HOMEPAGE_VAR_UNIFI_USERNAME}}";
          password = "{{HOMEPAGE_VAR_UNIFI_PASSWORD}}";
        };
      }
      {
        openmeteo = {
          label = "Canberra";
          latitude = "-35.281589";
          longitude = "149.134488";
          timezone = "Australia/Sydney";
          units = "metric";
          cache = 5;
        };
      }
      {
        search = {
          provider = "google";
          focus = false;
          showSearchSuggestions = true;
          target = "_self";
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = {
            weekday = "short";
            month = "short";
            day = "numeric";
            hour = "numeric";
            minute = "2-digit";
            hour12 = true;
          };
        };
      }
    ];
    settings = {
      title = "Mayur's Network";
      headerStyle = "clean";
      startUrl = "https://home.mayursaxena.com";
      target = "_self";
      layout = {
        "Core Network" = {
          icon = "mdi-lan-connect";
          style = "row";
          columns = 3;
        };

        "Monitoring" = {
          icon = "mdi-monitor-dashboard";
          style = "row";
          columns = 2;
        };

        "Media" = {
          icon = "mdi-multimedia";
        };

        "Media Tools" = {
          icon = "mdi-play-network-outline";
          style = "column";
          rows = 2;
        };

        "Downloads" = {
          icon = "mdi-download-box";
          style = "row";
        };
      };
    };
    services = [
      {
        "Core Network" = [
          {
            Proxmox = {
              description = "Hypervisor";
              href = "https://proxmox-web.home.mayursaxena.com";
              icon = "proxmox";
               #ping = "proxmox.home.mayursaxena.com";
              widget = {
                fields = [
                  "vms"
                  "lxc"
                ];
                password = "{{HOMEPAGE_VAR_PROXMOX_PASSWORD}}";
                type = "proxmox";
                url = "https://proxmox-web.home.mayursaxena.com";
                username = "{{HOMEPAGE_VAR_PROXMOX_USERNAME}}";
              };
            };
          }
          {
            DNS = {
              description = "Technitium DNS";
              href = "https://dns-web.home.mayursaxena.com";
              icon = "technitium";
               #ping = "dns.home.mayursaxena.com";
              widget = {
                fields = [
                  "totalQueries"
                  "totalBlocked"
                  "totalCached"
                  "totalServerFailure"
                ];
                key = "{{HOMEPAGE_VAR_TECHNITIUM_KEY}}";
                range = "LastHour";
                type = "technitium";
                url = "https://dns-web.home.mayursaxena.com";
              };
            };
          }
          {
            "NGINX Proxy Manager (NPM)" = {
              description = "Reverse Proxy";
              href = "https://npm-web.home.mayursaxena.com";
              icon = "nginx-proxy-manager";
               #ping = "npm.home.mayursaxena.com";
              widget = {
                password = "{{HOMEPAGE_VAR_NGINX_PROXY_MANAGER_PASSWORD}}";
                type = "npm";
                url = "https://npm-web.home.mayursaxena.com";
                username = "{{HOMEPAGE_VAR_NGINX_PROXY_MANAGER_USERNAME}}";
              };
            };
          }
        ];
      }
      {
        "Media Tools" = [
          {
            Radarr = {
              description = "Movies";
              href = "https://radarr.home.mayursaxena.com";
              icon = "radarr";
               #ping = "servarr.home.mayursaxena.com";
              widget = {
                enableQueue = true;
                key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
                type = "radarr";
                url = "https://radarr.home.mayursaxena.com";
              };
            };
          }
          {
            Sonarr = {
              description = "TV Shows";
              href = "https://sonarr.home.mayursaxena.com";
              icon = "sonarr";
               #ping = "servarr.home.mayursaxena.com";
              widget = {
                enableQueue = true;
                key = "{{HOMEPAGE_VAR_SONARR_KEY}}";
                type = "sonarr";
                url = "https://sonarr.home.mayursaxena.com";
              };
            };
          }
          {
            Bazarr = {
              description = "Subtitles";
              href = "https://bazarr.home.mayursaxena.com";
              icon = "bazarr";
               #ping = "servarr.home.mayursaxena.com";
              widget = {
                key = "{{HOMEPAGE_VAR_BAZARR_KEY}}";
                type = "bazarr";
                url = "https://bazarr.home.mayursaxena.com";
              };
            };
          }
        ];
      }
      {
        Media = [
          {
            Plex = {
              description = "Media Library";
              href = "https://plex-web.home.mayursaxena.com";
              icon = "plex";
               #ping = "plex.home.mayursaxena.com";
              widget = {
                key = "{{HOMEPAGE_VAR_PLEX_KEY}}";
                type = "plex";
                url = "https://plex-web.home.mayursaxena.com";
              };
            };
          }
          {
            Tautulli = {
              description = "Plex Performance Monitor";
              href = "https://tautulli.home.mayursaxena.com";
              icon = "tautulli";
               #ping = "plex.home.mayursaxena.com";
              widget = {
                enableUser = true;
                expandOneStreamToTwoRows = false;
                key = "{{HOMEPAGE_VAR_TAUTULLI_KEY}}";
                showEpisodeNumber = true;
                type = "tautulli";
                url = "https://tautulli.home.mayursaxena.com";
              };
            };
          }
          {
            Overseerr = {
              description = "Media Requests";
              href = "https://overseerr-web.home.mayursaxena.com";
              icon = "overseerr";
               #ping = "overseerr.home.mayursaxena.com";
              widget = {
                key = "{{HOMEPAGE_VAR_OVERSEERR_KEY}}";
                type = "overseerr";
                url = "https://overseerr-web.home.mayursaxena.com";
              };
            };
          }
        ];
      }
      {
        Downloads = [
          {
            SABnzbd = {
              description = "Usenet Downloader";
              href = "https://sabnzbd-web.home.mayursaxena.com";
              icon = "sabnzbd";
               #ping = "sabnzbd.home.mayursaxena.com";
              widget = {
                key = "{{HOMEPAGE_VAR_SABNZBD_KEY}}";
                type = "sabnzbd";
                url = "https://sabnzbd-web.home.mayursaxena.com";
              };
            };
          }
        ];
      }
      {
        Misc = [
          {
            NAS = {
              description = "File Share Server";
              href = "https://files-web.home.mayursaxena.com";
              icon = "files";
               #ping = "files.home.mayursaxena.com";
            };
          }
        ];
      }
      {
        Monitoring = [
          {
            InfluxDB = {
              description = "Time Series Monitoring";
              href = "https://influxdb-web.home.mayursaxena.com";
              icon = "influxdb";
               #ping = "influxdb.home.mayursaxena.com";
            };
          }
          {
            Grafana = {
              description = "Dashboards";
              href = "https://grafana-web.home.mayursaxena.com";
              icon = "grafana";
               #ping = "grafana.home.mayursaxena.com";
              widget = {
                fields = [];
                password = "{{HOMEPAGE_VAR_GRAFANA_PASSWORD}}";
                type = "grafana";
                url = "https://grafana-web.home.mayursaxena.com";
                username = "{{HOMEPAGE_VAR_GRAFANA_USERNAME}}";
              };
            };
          }
        ];
      }
      {
        Apps = [
          {
            Guacamole = {
              description = "Apache Guacamole";
              href = "https://guacamole.home.mayursaxena.com";
              icon = "guacamole";
               #ping = "jumpbox.home.mayursaxena.com";
            };
          }
          {
            "Actual Budget" = {
              description = "Budgeting";
              href = "https://budget.home.mayursaxena.com";
              icon = "actual-budget";
               #ping = "actualbudget.home.mayursaxena.com";
            };
          }
          {
            Paperless = {
              description = "Document Management";
              href = "https://paperless.home.mayursaxena.com";
              icon = "paperless-ngx";
               #ping = "paperless-ngx.home.mayursaxena.com";
              widget = {
                fields = [
                  "total"
                  "inbox"
                ];
                key = "{{HOMEPAGE_VAR_PAPERLESS_KEY}}";
                type = "paperlessngx";
                url = "https://paperless.home.mayursaxena.com";
              };
            };
          }
        ];
      }
    ];
  };

  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";
}
