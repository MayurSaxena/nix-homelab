{
  inputs,
  config,
  pkgs,
  vars,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/virtualisation/proxmox-lxc.nix")];
  proxmoxLXC = {
    manageNetwork = false;
    manageHostName = false;
  };
  # make an LXC share group that can be used at any point
  users.groups.lxc_share = {
    name = "lxc_share";
    gid = 110000;
  };
}
