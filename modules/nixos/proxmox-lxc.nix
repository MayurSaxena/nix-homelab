{
  inputs,
  config,
  pkgs,
  modulesPath,
  lib,
  ...
}: {
  imports = [(modulesPath + "/virtualisation/proxmox-lxc.nix")];

  options.custom.proxmox-lxc = {
    enable = lib.mkEnableOption "Proxmox LXC specific settings";
  };

  config = lib.mkIf config.custom.proxmox-lxc.enable {
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
  };
}
