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
    # Every unit that reads this file, so a rotated key takes effect without a
    # manual restart. Bazarr is absent deliberately — its module has no
    # environmentFiles support, so it never reads this secret.
    restartUnits = [
      "radarr.service"
      "sonarr.service"
      "prowlarr.service"
    ];
  };

  # ── Radarr (movies) ───────────────────────────────────────────────────────
  services.radarr = {
    enable = true;
    openFirewall = true; # TCP 7878
    group = "lxc_share";
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
    group = "lxc_share";
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
    group = "lxc_share";
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
  # host-mounted media library, and Bazarr writes subtitles alongside them —
  # hence group = "lxc_share" on all three above. Setting the service's own
  # group option already makes it the process's primary group, so no
  # users.users.<x>.extraGroups line is needed. Prowlarr works over HTTP APIs
  # only and needs no filesystem access.

  # The group here must be each service's *effective* Group=, which is lxc_share
  # (set above), not "<service>". The upstream modules only create a "<service>"
  # group when their own group option is left at its default, so radarr/sonarr/
  # bazarr groups don't exist on this host — and impermanence chowns these
  # directories to "$user:$group" when it first creates them.
  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/radarr";
        user = "radarr";
        group = "lxc_share";
        mode = "0750";
      }
      {
        directory = "/var/lib/sonarr";
        user = "sonarr";
        group = "lxc_share";
        mode = "0750";
      }
      {
        directory = "/var/lib/bazarr";
        user = "bazarr";
        group = "lxc_share";
        mode = "0750";
      }
      {
        directory = "/var/lib/private/prowlarr";
      }
    ];
  };
}
