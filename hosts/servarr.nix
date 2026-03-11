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

  # ── Radarr (movies) ───────────────────────────────────────────────────────
  services.radarr = {
    enable = true;
    openFirewall = true; # TCP 7878
  };

  # ── Sonarr (TV shows) ────────────────────────────────────────────────────
  services.sonarr = {
    enable = true;
    openFirewall = true; # TCP 8989
  };

  # ── Bazarr (subtitles) ───────────────────────────────────────────────────
  services.bazarr = {
    enable = true;
    openFirewall = true; # TCP 6767
  };

  # ── Prowlarr (indexer manager) ───────────────────────────────────────────
  services.prowlarr = {
    enable = true;
    openFirewall = true; # TCP 9696
  };

  # Radarr and Sonarr rename/move media files, so they need access to the
  # host-mounted media library. Bazarr and Prowlarr work over HTTP APIs only.
  users.users.radarr.extraGroups = ["lxc_share"];
  users.users.sonarr.extraGroups = ["lxc_share"];

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
        directory = "/var/lib/prowlarr";
        user = "prowlarr";
        group = "prowlarr";
        mode = "0750";
      }
    ];
  };
}
