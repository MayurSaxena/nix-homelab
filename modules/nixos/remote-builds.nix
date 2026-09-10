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
    # The remote-builder private key is committed to the repo in the clear.
    # KNOWN ISSUE, planned for rotation (see CLAUDE.md, Known drift). The repo
    # is public; the key unlocks the `nix` account on the builder, which is a
    # plain isNormalUser with the default shell -- not the ForceCommand-
    # restricted `nix-ssh` account that nix.sshServe creates -- and that
    # account is a Nix trusted user. Every host substitutes unsigned paths from
    # that store, so the blast radius is the whole fleet, not build capacity.
    # The original justification (impermanent hosts can't decrypt sops before
    # their first switch) no longer holds: the CI image doesn't enable
    # remote-builds, and onboard-host.sh builds through root@nix-builder.
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
