{
  inputs,
  outputs,
  config,
  ...
}: {
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;
  custom.impermanence.enable = true;
  custom.remote-builds.enable = true;
  custom.root-password.enable = true;
  custom.beszel-monitoring-agent.enable = true;

  sops.secrets."servarr-secrets" = {
    # Contains RADARR__AUTH__APIKEY and SONARR__AUTH__APIKEY.
    # Keeping existing API keys so Bazarr can connect without reconfiguration
    # after migration. Create with: sops secrets/servarr.env
    format = "dotenv";
    sopsFile = ./../secrets/servarr.env;
  };

  # ── Radarr (movies) ───────────────────────────────────────────────────────
  services.radarr = {
    enable = true;
    openFirewall = true; # TCP 7878
    settings = {
      server.urlBase = "/radarr";
      auth = {
        # Keep auth enabled — access is via Caddy but login is still required.
        method = "Forms";
        required = "Enabled";
      };
      update = {
        # NixOS manages the package; disable in-app update mechanism.
        mechanism = "external";
        automatically = false;
      };
    };
    # Injects RADARR__AUTH__APIKEY so the existing API key is preserved
    # (Bazarr is configured with this key and would otherwise need reconfiguring).
    environmentFiles = [config.sops.secrets."servarr-secrets".path];
  };

  # ── Sonarr (TV shows) ────────────────────────────────────────────────────
  services.sonarr = {
    enable = true;
    openFirewall = true; # TCP 8989
    settings = {
      server.urlBase = "/sonarr";
      auth = {
        method = "Forms";
        required = "Enabled";
      };
      update = {
        mechanism = "external";
        automatically = false;
      };
    };
    # Injects SONARR__AUTH__APIKEY — same reason as Radarr above.
    environmentFiles = [config.sops.secrets."servarr-secrets".path];
  };

  # ── Bazarr (subtitles) ───────────────────────────────────────────────────
  # Bazarr's NixOS module has no settings/environmentFiles support — all
  # configuration lives in config.yaml and bazarr.db. Migrate those files to
  # /persistent/var/lib/bazarr/ when cutting over from the old container.
  # Note: --no-update True is already hardcoded in the NixOS module.
  services.bazarr = {
    enable = true;
    openFirewall = true; # TCP 6767
  };

  # ── Prowlarr (indexer manager) ───────────────────────────────────────────
  # Fresh install — Prowlarr will generate its own API key on first boot.
  # After deployment, configure Radarr/Sonarr to use Prowlarr as their
  # indexer source via the Prowlarr web UI (Settings → Apps).
  services.prowlarr = {
    enable = true;
    openFirewall = true; # TCP 9696
    settings = {
      server.urlBase = "/prowlarr";
      auth = {
        method = "Forms";
        required = "Enabled";
      };
      update = {
        mechanism = "external";
        automatically = false;
      };
    };
    # Injects PROWLARR__AUTH__APIKEY — same reason as Radarr above.
    environmentFiles = [config.sops.secrets."servarr-secrets".path];
  };

  # Radarr and Sonarr rename/move media files, so they need access to the
  # host-mounted media library. Bazarr adds subtitles. Prowlarr works over
  # HTTP APIs only.
  users.users.radarr.extraGroups = ["lxc_share"];
  users.users.sonarr.extraGroups = ["lxc_share"];
  users.users.bazarr.extraGroups = ["lxc_share"];

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/radarr";
        user = "radarr";
        group = "radarr";
        mode = "0750";
      }
      {
        directory = "/var/lib/sonarr";
        user = "sonarr";
        group = "sonarr";
        mode = "0750";
      }
      {
        directory = "/var/lib/bazarr";
        user = "bazarr";
        group = "bazarr";
        mode = "0750";
      }
      {
        directory = "/var/lib/private/prowlarr";
      }
    ];
  };
}
