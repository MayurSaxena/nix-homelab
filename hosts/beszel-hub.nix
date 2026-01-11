{
  inputs,
  outputs,
  config,
  ...
}: {
  # Set system architecture for this host
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
      APP_URL = "https://beszel.home.mayursaxena.com";
    };
  };

  networking.firewall.allowedTCPPorts = [8090];

  systemd.tmpfiles.rules = [
    "d ${config.custom.impermanence.persistence-root}/var/lib/private 0700 root root"
  ];

  environment.persistence."${config.custom.impermanence.persistence-root}" = {
    directories = [
      {
        directory = "/var/lib/private/beszel-hub";
      }
    ];
  };
}
