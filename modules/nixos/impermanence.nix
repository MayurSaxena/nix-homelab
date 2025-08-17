{
  inputs,
  config,
  pkgs,
  ...
}: {
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

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

  systemd.tmpfiles.rules = [
    "d /persistent/etc 0755 root root -"
    "d /persistent/etc/ssh 0700 root root -"
    # If persistent copy doesn’t exist, copy the ephemeral one
    "C /persistent/etc/machine-id - - - - /etc/machine-id"
    # This might be useful if we're upgrading a permanent system to an impermanent one
    "C /persistent/etc/ssh/ssh_host_rsa_key - - - - /etc/ssh/ssh_host_rsa_key"
    "C /persistent/etc/ssh/ssh_host_ed25519_key - - - - /etc/ssh/ssh_host_ed25519_key"
  ];

  environment.persistence."/persistent" = {
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
}
