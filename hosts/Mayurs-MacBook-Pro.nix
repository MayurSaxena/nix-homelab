{
  inputs,
  outputs,
  pkgs,
  vars,
  ...
}: {
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./../macos/base.nix
  ];

  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "aarch64-darwin";
  home-manager = {
    extraSpecialArgs = {inherit inputs outputs vars;};
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [inputs.sops-nix.homeManagerModules.sops];
    users.msaxena = {
      imports = [
        ./../home-manager/base.nix
        ./../home-manager/git.nix
        ./../home-manager/ssh.nix
        /../home-manager/zsh.nix
      ];
      sops = {
        age.keyFile = "/Users/msaxena/.config/sops/age/keys.txt";
        defaultSopsFile = ./../secrets/msaxena.yaml;
      };
      # need this so that the launchd agent uses age-plugin-yubikey to decrypt the secrets using a yubikey
      launchd.agents.sops-nix.config.EnvironmentVariables = {
        PATH = "${pkgs.age-plugin-yubikey}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };
}
