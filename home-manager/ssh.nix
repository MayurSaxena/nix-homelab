{
  pkgs,
  vars,
  config,
  ...
}: {
  programs.ssh = {
    enable = true;
    package = pkgs.openssh;
  };
  home = {
    file = {
      ".ssh/id_ed25519.pub" = {
        enable = true;
        text = "${vars.ed25519SSHKey}";
      };
    };
  };
  sops.secrets."ssh-keys/mbp-ed25519" = {
    mode = "0600";
    path = "${config.home.homeDirectory}/.ssh/id_ed25519";
  };
}
