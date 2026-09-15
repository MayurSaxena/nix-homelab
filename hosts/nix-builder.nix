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
    ];
  };
}
