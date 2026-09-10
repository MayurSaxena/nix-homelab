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
  # remote-builds would point this host at itself.
  custom.remote-builds.enable = false;
  # Uncommented drift: the builder has no PVE-console password. Root is still
  # reachable over SSH with a YubiKey, which is how it is actually administered.
  custom.root-password.enable = false;
  custom.beszel-monitoring-agent.enable = true;

  # Every other host builds on, and substitutes from, this store over SSH as
  # the nix-ssh account. nix.sshServe creates that account and makes sshd
  # force `nix-store --serve --write` for it (no TTY, no forwarding, no
  # tunnels), so the key that every host holds can talk to the Nix store and
  # do nothing else. `write` is what lets remote builds upload their inputs;
  # `trusted` is what lets those uploads be unsigned, which remote building
  # requires. Both are deliberate: this store is the fleet's trust root either
  # way, and the forced command is what keeps that from also being a shell.
  nix.sshServe = {
    enable = true;
    write = true;
    trusted = true;
    keys = [
      (builtins.readFile ./../assets/remote-builder.pub)
      # TRANSITIONAL -- remove with the `nix` user below once every host and
      # the Mac have switched to the rotated key (one autoUpgrade cycle after
      # this lands). Hosts still on the old config connect with this key.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIId8MHk0je00VbyRtjvTfHIIvXPyMi93SuU30rNi5d5N"
    ];
  };

  # TRANSITIONAL -- the account the old key logged in as, kept only so hosts
  # that haven't yet upgraded past the key rotation can still build tonight.
  # It has a shell and is a trusted user, which is exactly the problem the
  # rotation fixes; delete this block and the trusted-users line together
  # with the old key above.
  users.users.nix = {
    createHome = true;
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIId8MHk0je00VbyRtjvTfHIIvXPyMi93SuU30rNi5d5N"
    ];
  };
  nix.settings.trusted-users = ["nix"];
}
