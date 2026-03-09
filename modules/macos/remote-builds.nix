{
  config,
  lib,
  ...
}: let
  cfg = config.custom.remote-builds-mac;
in {
  options.custom.remote-builds-mac = {
    enable = lib.mkEnableOption "remote building";
    remote-host = lib.mkOption {
      default = "nix-builder.home.internal";
      type = lib.types.str;
      example = "host.example.com";
      description = "Hostname of remote build machine.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Copy the SSH private key with correct permissions (0400) and write the
    # machines file. We use extraActivation because nix-darwin only interpolates
    # a fixed set of named activation script slots; arbitrary names are silently
    # ignored.
    system.activationScripts.extraActivation.text = lib.mkAfter ''
      echo "Setting up Nix remote builder..." >&2
      install -m 0400 -o root ${./../../assets/remote-builder} /etc/nix/remote-builder-key
      echo "ssh://nix@${cfg.remote-host} x86_64-linux /etc/nix/remote-builder-key 3 1 kvm,nixos-test,big-parallel" > /etc/nix/machines
    '';

    # Determinate Nix manages nix.conf and regenerates nix.custom.conf on each
    # activation. nix.settings / nix.buildMachines are no-ops with determinateNix.
    # Instead, append the builders setting in postActivation, which runs after
    # the etc phase has regenerated nix.custom.conf.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      if ! grep -q "^builders" /etc/nix/nix.custom.conf; then
        printf "\nbuilders = @/etc/nix/machines\n" >> /etc/nix/nix.custom.conf
      fi
    '';

    # Avoid interactive host key prompts when the daemon first connects.
    environment.etc."ssh/ssh_config.d/nix-builder.conf".text = ''
      Host ${cfg.remote-host}
        StrictHostKeyChecking accept-new
        IdentityFile /etc/nix/remote-builder-key
        User nix
    '';
  };
}
