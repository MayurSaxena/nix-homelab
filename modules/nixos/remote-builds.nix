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
        hostName = "nix-builder.dev.home.mayursaxena.com";
        protocol = "ssh";
        system = "x86_64-linux";
        sshUser = "nix";
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

  nix.settings.substituters = [
    "ssh://nix@nix-builder.dev.home.mayursaxena.com?ssh-key=/etc/remote-builder-key"
  ];

  programs.ssh.extraConfig = "StrictHostKeyChecking=accept-new";
}
