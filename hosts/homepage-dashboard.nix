{
  inputs,
  outputs,
  config,
  pkgs,
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

  sops.secrets = {
    "homepage-secrets" = {
      format = "dotenv";
      sopsFile = ./../secrets/homepage-dashboard-secrets.env;
      restartUnits = ["homepage-dashboard.service"];
    };
  };

  systemd.services.homepage-dashboard = {
    path = [pkgs.iputils];
  };

  services.homepage-dashboard = {
    enable = true;
    openFirewall = true;
    listenPort = 8082;
    environmentFiles = [config.sops.secrets."homepage-secrets".path];
    allowedHosts = "localhost:8082,127.0.0.1:8082,homepage.${domain}:8082,${domain}";
    widgets = [
      {
        unifi_console = {
          href = "https://bikinibottom.${domain}";
          url = "https://bikinibottom.${domain}";
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
      startUrl = "https://${domain}";
      target = "_self";
      layout = [
        {
          "Core Network" = {
            icon = "mdi-lan-connect";
            style = "row";
            columns = 2;
          };
        }

        {
          "Downloads" = {
            icon = "mdi-download-box";
            style = "row";
          };
        }

        {
          "Media" = {
            icon = "mdi-multimedia";
            style = "row";
            columns = 2;
          };
        }

        {
          "Media Tools" = {
            icon = "mdi-play-network-outline";
            style = "row";
            columns = 3;
          };
        }

        {
          "Monitoring" = {
            icon = "mdi-monitor-dashboard";
            style = "row";
            columns = 2;
          };
        }

        {
          "Apps" = {
            icon = "mdi-application-brackets-outline";
            style = "column";
            rows = 2;
            useEqualHeights = true;
          };
        }
      ];
    };
    services = [
      {
        "Core Network" = [
          {
            Proxmox = {
              description = "Hypervisor";
              href = "https://proxmox-web.${domain}";
              icon = "proxmox";
              # ping = "proxmox.${domain}";
              widget = {
                fields = [
                  "vms"
                  "lxc"
                ];
                password = "{{HOMEPAGE_VAR_PROXMOX_PASSWORD}}";
                type = "proxmox";
                url = "https://proxmox-web.${domain}";
                username = "{{HOMEPAGE_VAR_PROXMOX_USERNAME}}";
              };
            };
          }
          {
            DNS = {
              description = "Technitium DNS";
              href = "https://dns-web.${domain}";
              icon = "technitium";
              #ping = "dns.${domain}";
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
                url = "https://dns-web.${domain}";
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
              href = "https://radarr.${domain}";
              icon = "radarr";
              #ping = "servarr.${domain}";
              widget = {
                enableQueue = false;
                key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
                type = "radarr";
                url = "https://radarr.${domain}";
              };
            };
          }
          {
            Sonarr = {
              description = "TV Shows";
              href = "https://sonarr.${domain}";
              icon = "sonarr";
              #ping = "servarr.${domain}";
              widget = {
                enableQueue = false;
                key = "{{HOMEPAGE_VAR_SONARR_KEY}}";
                type = "sonarr";
                url = "https://sonarr.${domain}";
              };
            };
          }
          {
            Bazarr = {
              description = "Subtitles";
              href = "https://bazarr.${domain}";
              icon = "bazarr";
              #ping = "servarr.${domain}";
              widget = {
                key = "{{HOMEPAGE_VAR_BAZARR_KEY}}";
                type = "bazarr";
                url = "https://bazarr.${domain}";
              };
            };
          }
          {
            Prowlarr = {
              description = "Indexers";
              href = "https://prowlarr.${domain}";
              icon = "prowlarr";
              widget = {
                key = "{{HOMEPAGE_VAR_PROWLARR_KEY}}";
                type = "prowlarr";
                url = "https://prowlarr.${domain}";
              };
            };
          }
        ];
      }
      {
        "Media" = [
          {
            Plex = {
              description = "Media Library";
              href = "https://plex-web.${domain}";
              icon = "plex";
              #ping = "plex.${domain}";
              widget = {
                key = "{{HOMEPAGE_VAR_PLEX_KEY}}";
                type = "plex";
                url = "https://plex-web.${domain}";
              };
            };
          }
          {
            Overseerr = {
              description = "Media Requests";
              href = "https://overseerr-web.${domain}";
              icon = "overseerr";
              #ping = "overseerr.${domain}";
              widget = {
                key = "{{HOMEPAGE_VAR_OVERSEERR_KEY}}";
                type = "overseerr";
                url = "https://overseerr-web.${domain}";
              };
            };
          }
        ];
      }
      {
        "Downloads" = [
          {
            SABnzbd = {
              description = "Usenet Downloader";
              href = "https://sabnzbd-web.${domain}";
              icon = "sabnzbd";
              #ping = "sabnzbd.${domain}";
              widget = {
                key = "{{HOMEPAGE_VAR_SABNZBD_KEY}}";
                type = "sabnzbd";
                url = "https://sabnzbd-web.${domain}";
              };
            };
          }
        ];
      }
      {
        "Monitoring" = [
          {
            Beszel = {
              description = "Monitoring Dashboard";
              href = "https://beszel.${domain}";
              icon = "beszel";
              # widget = {
              #   type = "beszel";
              #   url = "https://beszel.${domain}";
              #   username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
              #   password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
              #   version = 2;
              #   fields = [];
              # };
            };
          }
        ];
      }
      {
        "Apps" = [
          {
            "Actual Budget" = {
              description = "Budgeting";
              href = "https://budget.${domain}";
              icon = "actual-budget";
              #ping = "actualbudget.${domain}";
            };
          }
          {
            Paperless = {
              description = "Document Management";
              href = "https://paperless-web.${domain}";
              icon = "paperless-ngx";
              #ping = "paperless-ngx.${domain}";
              widget = {
                fields = [
                  "total"
                  "inbox"
                ];
                key = "{{HOMEPAGE_VAR_PAPERLESS_KEY}}";
                type = "paperlessngx";
                url = "https://paperless-web.${domain}";
              };
            };
          }
        ];
      }
    ];
  };
}
