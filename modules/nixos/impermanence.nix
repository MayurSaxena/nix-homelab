{
  inputs,
  config,
  pkgs,
  ...
}: {
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

#   systemd.tmpfiles.settings."persistent-var-log"."/persistent/var/log" = {d = {};};
#   systemd.tmpfiles.settings."persistent-var-lib"."/persistent/var/lib" = {d = {};};
  services.openssh.hostKeys = [
    {
      bits = 4096;
      path = "/persistent/etc/ssh/ssh_host_rsa_key";
      type = "rsa";
    }
    {
      path = "/persistent/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  sops.age.sshKeyPaths = ["/persistent/etc/ssh/ssh_host_ed25519_key"];

  environment.persistence."/persistent" = {
    directories = [
      "/var/log"
      "/var/lib/nixos"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
    ];
  };
}
