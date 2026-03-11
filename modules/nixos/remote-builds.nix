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
      default = "nix-builder.home.internal";
      type = lib.types.str;
      example = "host.example.com";
      description = "Hostname of remote build machine.";
    };
  };

  config = lib.mkIf cfg.enable {
    # The remote-builder private key is committed to the repo. This is an
    # intentional trade-off: impermanent LXC containers have no persistent
    # state on first boot, so they can't decrypt SOPS secrets to retrieve a
    # key. The nix user on the builder has no shell and only serves the Nix
    # store — the blast radius of key exposure is limited to build capacity.
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
