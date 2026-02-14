{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.custom.remote-builds;
in {
  #### OPTION DEFINITION ####
  options.custom.remote-builds = {
    enable = lib.mkEnableOption "remote building";
    remote-host = lib.mkOption {
      default = "nix-builder.dev.internal";
      type = lib.types.str;
      example = "host.example.com";
      description = "Hostname of remote build machine.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc.remote-builder-key = {
      source = ./../../assets/remote-builder;
      mode = "0400";
    };

    nix = {
      buildMachines = [
        {
          hostName = "${cfg.remote-host}";
          protocol = "ssh";
          system = "x86_64-linux";
          sshUser = "nix";
          sshKey = "/etc/remote-builder-key";
          maxJobs = 3;
          supportedFeatures = [
            "kvm"
            "nixos-test"
            "big-parallel"
          ];
        }
      ];
      distributedBuilds = true;
    };

    nix.settings.substituters = [
      "ssh://nix@${cfg.remote-host}?ssh-key=/etc/remote-builder-key"
    ];

    programs.ssh.extraConfig = "StrictHostKeyChecking=accept-new";
  };
}
