{
  inputs,
  config,
  pkgs,
  ...
}: {
  environment.etc.remote-builder-key = {
    source = ./../../assets/remote-builder;
    mode = "0400";
  };

  nix = {
    buildMachines = [
      {
        hostName = "10.0.60.2";
        protocol = "ssh";
        system = "x86_64-linux";
        sshUser = "nixbuild";
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

  programs.ssh.extraConfig = "StrictHostKeyChecking=accept-new";
}
