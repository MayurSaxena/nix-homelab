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
    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.users.users.${config.system.primaryUser}.home}/.config/sops-nix/secrets/remote-builder/private-key";
      description = ''
        Decrypted builder key to copy into /etc/nix. It lives under the
        primary user's home rather than /run/secrets because this Mac has no
        system-level sops: decryption needs the YubiKey, which only the
        user's login agent has (the same arrangement as
        custom.auto-upgrade-mac.webhookFile). Root can read it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Copy the SSH private key with correct permissions (0400) and write the
    # machines file. We use extraActivation because nix-darwin only interpolates
    # a fixed set of named activation script slots; arbitrary names are silently
    # ignored.
    #
    # The key is legitimately absent after a boot without the YubiKey (the
    # sops-nix agent leaves a dangling symlink), so a missing source is a
    # warning that keeps whatever /etc/nix already holds, not an activation
    # failure -- otherwise every keyless switch would abort here.
    system.activationScripts.extraActivation.text = lib.mkAfter ''
      echo "Setting up Nix remote builder..." >&2
      if [ -r "${cfg.keyFile}" ]; then
        install -m 0400 -o root "${cfg.keyFile}" /etc/nix/remote-builder-key
      else
        echo "warning: ${cfg.keyFile} unreadable (YubiKey absent at login?); leaving /etc/nix/remote-builder-key as is" >&2
      fi
      echo "ssh://nix-ssh@${cfg.remote-host} x86_64-linux /etc/nix/remote-builder-key 3 1 kvm,nixos-test,big-parallel" > /etc/nix/machines
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
        User nix-ssh
    '';
  };
}
