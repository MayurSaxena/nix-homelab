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

  services.beszel.hub = {
    enable = true;
    host = "0.0.0.0";
    environment = {
      APP_URL = "https://beszel.${domain}";
    };
  };

  networking.firewall.allowedTCPPorts = [8090];

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/private/beszel-hub";
      }
    ];
  };
}
