{
  config,
  lib,
  ...
}: let
  cfg = config.custom.remote-builds;
  key = config.sops.secrets."remote-builder/private-key".path;
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
    # The builder key lives in common.yaml, encrypted to every host, and is
    # decrypted to /run/secrets at activation as root:root 0400 -- which is
    # all nix-daemon needs, since it runs the ssh as root. It used to be
    # committed in the clear under assets/ on the theory that a fresh host
    # couldn't decrypt sops before its first switch; that was never true of
    # this workflow (the CI image doesn't enable remote-builds, and
    # onboard-host.sh builds through root@nix-builder), and it left a public
    # repo holding the key to the store every host installs from. The old
    # key remains in git history, which is why it was rotated rather than
    # merely moved.
    #
    # No restartUnits: nix-daemon opens the key per connection, so a rotated
    # value is picked up by the next build with nothing to restart.
    sops.secrets."remote-builder/private-key" = {
      sopsFile = ./../../secrets/common.yaml;
    };

    nix = {
      buildMachines = [
        {
          hostName = "${cfg.remote-host}";
          protocol = "ssh";
          system = "x86_64-linux";
          # nix-ssh is the account nix.sshServe creates on the builder. sshd
          # forces `nix-store --serve --write` for it and denies TTY, port
          # forwarding and tunnels, so the key buys store access and nothing
          # else -- see hosts/remote-builder.nix.
          sshUser = "nix-ssh";
          sshKey = key;
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
      "ssh://nix-ssh@${cfg.remote-host}?ssh-key=${key}"
    ];

    programs.ssh.extraConfig = "StrictHostKeyChecking=accept-new";
  };
}
