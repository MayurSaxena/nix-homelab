{
  inputs,
  outputs,
  config,
  ...
}: {
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  custom.proxmox-lxc.enable = true;
  # Impermanence is intentionally disabled: the builder needs a persistent Nix
  # store so it can cache and serve build outputs. Wiping on boot defeats the purpose.
  custom.impermanence.enable = false;
  custom.remote-builds.enable = false;
  custom.root-password.enable = false;
  custom.beszel-monitoring-agent.enable = true;

  users.users.nix = {
    createHome = true;
    isNormalUser = true;
    # Allows SSH session establishment as the nix user.
    openssh.authorizedKeys.keyFiles = [
      ./../assets/remote-builder.pub
    ];
  };

  nix.sshServe = {
    enable = true;
    trusted = true;
    # Also needed for the ssh:// substituter protocol: openssh.authorizedKeys
    # lets the session in; sshServe.keys grants nix-daemon trust to the key.
    keys = [
      (builtins.readFile ./../assets/remote-builder.pub)
    ];
  };

  nix.settings.trusted-users = [
    "nix"
  ];
}
