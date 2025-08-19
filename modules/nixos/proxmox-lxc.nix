{
  inputs,
  config,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/virtualisation/proxmox-lxc.nix")];
  proxmoxLXC = {
    manageNetwork = false;
    manageHostName = false;
  };

  services.resolved.enable = false;
  networking.resolvconf.enable = false;

  # make an LXC share group that can be used at any point
  # maps to group 110000 on the PVE host.
  users.groups.lxc_share = {
    name = "lxc_share";
    gid = 10000;
  };
}
