{
  inputs,
  outputs,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./base-nixos-lxc-proxmox-impermanent-remote.nix
    ./../modules/nixos/root-password.nix
  ];
  # Set system architecture for this host
  nixpkgs.hostPlatform = inputs.nixpkgs.lib.mkDefault "x86_64-linux";

  sops.secrets = {
    "passwords/timemachine" = {
      neededForUsers = true;
      sopsFile = ./../secrets/fileserver.yaml;
    };
    "passwords/msaxena" = {
      neededForUsers = true;
      sopsFile = ./../secrets/fileserver.yaml;
    };
  };

  users.users.timemachine = {
    hashedPasswordFile = config.sops.secrets."passwords/timemachine".path;
    isNormalUser = true;
    extraGroups = ["lxc_share"];
  };

  users.users.msaxena = {
    hashedPasswordFile = config.sops.secrets."passwords/msaxena".path;
    isNormalUser = true;
    extraGroups = ["lxc_share"];
  };

  users.users.ubnt = {
    isNormalUser = true;
    extraGroups = ["lxc_share"];
    shell = pkgs.scponly;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDZHlCICwIQXr1FCNkE7cwa29KNGr4amqf8H5Fxa7wvqo8KfWRP7M2m+N7cdqtXd6dy3+dKvuh261y0yl9lKUsN03D+SNYp0mK9Z8CjoDMCNLRVewgSt8aM6FklMvza68ImZoc9fD4aYwUfXwxiL2s32pQ54DDYFrImtGtl8U5Gu+Y1eyZqKHI0eIPGo7HFw3VlgO8ZZ/t7u9jJ1+HDSeG9/e5GCsrulbKqZYVNvzTfng/gcJRrR5nieAeG4BVe/K7+FUZWu/xs7/CGSv/n7wb/d8xTPPk/clGv5LihK3dYgceajHl8AgAA58j3QBJbVEoUugzbHmHNRXjwHVhFl02jKgkvmcCFYG0BrPgmT1WT+6uFAgOTH71m3vEI+apnKfV2mHG2C3SaPgdgry7QPrwWr4Pj81soTyvXwheGk8GrYSnkFaaHj7wHxKxlp3GE5UVH+KdAlFLPmmq7G5vk2Nc7kIJq7zTBGIH3lk15iwEwxMuL9lpkcisiDMx3+SldemM="
    ];
  };

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "min protocol" = "SMB2";
        "server min protocol" = "SMB2";

        "security" = "user";
        "workgroup" = "WORKGROUP";
        "netbios name" = "FILES";
        "wide links" = "no";
        "unix extensions" = "no";
        "spotlight" = "yes";
        "map to guest" = "bad user";
        "guest account" = "nobody";

        "vfs objects" = "recycle acl_xattr catia fruit streams_xattr";
        "fruit:nfc_aces" = "no";
        "fruit:aapl" = "yes";
        "fruit:model" = "MacSamba";
        "fruit:posix_rename" = "yes";
        "fruit:metadata" = "stream";
        "fruit:delete_empty_adfiles" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";

        "recycle:touch" = "yes";
        "recycle:keeptree" = "yes";
        "recycle:versions" = "yes";
        "recycle:exclude_dir" = "tmp quarantine";

        "unix password sync" = "yes";
        "passwd program" = "/run/wrappers/bin/passwd %u";
        "passwd chat" = "*Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .";
      };
      "TimeMachine" = {
        "writeable" = "yes";
        "available" = "yes";
        "force directory mode" = "0775";
        "path" = "/media/TimeCapsule";
        "valid users" = "timemachine";
        "guest ok" = "no";
        "comment" = "Backups";
        "create mask" = "0664";
        "directory mask" = "0775";
        "fruit:time machine" = "yes";
        "force create mode" = "0664";
        "vfs objects" = "catia fruit streams_xattr";
      };
      "NetShare" = {
        "public" = "yes";
        "guest ok" = "yes";
        "path" = "/media/NetShare";
        "wide links" = "no";
        "directory mode" = "777";
        "valid users" = "msaxena,nobody";
        "comment" = "Public Network Share";
        "create mode" = "777";
        "writeable" = "yes";
      };
    };
  };

  services.samba.nmbd.enable = true;
  services.samba-wsdd.enable = true;

  # Make sure to add valid Samba users below to sync Unix password to Samba
  system.activationScripts.sambaUsers = {
    text = ''
      for user in timemachine msaxena; do
        pw=$(${pkgs.coreutils}/bin/cat /run/secrets-for-users/passwords/$user)
        printf "%s\n%s\n" "$pw" "$pw" \
          | ${pkgs.samba}/bin/smbpasswd -a -s "$user" || true
      done
    '';
  };

  environment.persistence."/persistent" = {
    directories = [
      {
        directory = "/var/lib/samba";
      }
    ];
  };
}
