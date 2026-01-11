{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.custom.impermanence;
in {
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  #### OPTION DEFINITION ####
  options.custom.impermanence = {
    enable = lib.mkEnableOption "impermanence setup";
    persistence-root = lib.mkOption {
      default = "/persistent";
      type = lib.types.path;
      example = "/persistent";
      description = "The root folder of where persistent files will be stored.";
    };
  };

  #### CONDITIONAL CONFIG ####
  config = lib.mkIf cfg.enable {
    services.openssh.hostKeys = [
      {
        bits = 4096;
        path = "${cfg.persistence-root}/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
      }
      {
        path = "${cfg.persistence-root}/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];

    sops.age.sshKeyPaths = ["${cfg.persistence-root}/etc/ssh/ssh_host_ed25519_key"];

    systemd.tmpfiles.rules = [
      "d ${cfg.persistence-root}/etc 0755 root root -"
      "d ${cfg.persistence-root}/etc/ssh 0700 root root -"
      # If persistent copy doesn’t exist, copy the ephemeral one
      "C ${cfg.persistence-root}/etc/machine-id - - - - /etc/machine-id"
      # This might be useful if we're upgrading a permanent system to an impermanent one
      "C ${cfg.persistence-root}/etc/ssh/ssh_host_rsa_key - - - - /etc/ssh/ssh_host_rsa_key"
      "C ${cfg.persistence-root}/etc/ssh/ssh_host_ed25519_key - - - - /etc/ssh/ssh_host_ed25519_key"
    ];

    environment.persistence."${cfg.persistence-root}" = {
      hideMounts = true;
      directories = [
        "/var/log"
        "/var/lib/nixos"
        "/var/lib/systemd"
      ];
      files = [
        "/etc/machine-id"
      ];
    };
  };
}
