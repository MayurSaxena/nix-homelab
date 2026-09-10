# Version control and the SSH client it (and everything else here) rides on.
{
  lib,
  outputs,
  pkgs,
  ...
}: let
  # Every NixOS host in this flake is reached as root over SSH, so give each one an alias
  # and stop typing `root@`. Derived from nixosConfigurations rather than listed by hand:
  # registering a host in flake.nix is then the only step, and this list cannot drift from
  # the hosts that actually exist. base-lxc is excluded because it is the CI image, not a
  # machine that runs anywhere.
  #
  # This is the one place in the repo that reads `outputs` (= self). Only the attribute
  # *names* are forced, never the configurations themselves, so it costs nothing to
  # evaluate and cannot recurse back into this Darwin config.
  homelabHosts =
    builtins.filter (h: h != "base-lxc")
    (builtins.attrNames outputs.nixosConfigurations);
in {
  programs = {
    git = {
      enable = true;
      settings = {
        user = {
          email = "me@mayursaxena.com";
          name = "Mayur Saxena";
        };
        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
        fetch.prune = true;
        rebase.autoStash = true;
        diff.algorithm = "histogram";
        merge.conflictstyle = "zdiff3";
        rerere.enabled = true;
        branch.sort = "-committerdate";
        column.ui = "auto";
      };
      ignores = [
        ".DS_Store"
        ".direnv/"
        "**/.claude/settings.local.json"
      ];
      # SSH commit signing with the non-touch key, so a commit never needs a YubiKey tap.
      # The public half is already committed at assets/id_ed25519.pub; the private half is
      # decrypted from secrets/msaxena.yaml at login. Register the same public key as a
      # *signing* key on GitHub for the Verified badge.
      signing = {
        format = "ssh"; # the default is null at this stateVersion, so explicit
        key = "~/.ssh/id_ed25519.pub";
        signByDefault = true;
        allowedSigners = "me@mayursaxena.com ${builtins.readFile ./../../assets/id_ed25519.pub}";
      };
    };

    delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        line-numbers = true;
      };
    };

    lazygit = {
      enable = true;
      settings.git.paging = {
        colorArg = "always";
        pager = "delta --dark --paging=never";
      };
    };

    gh = {
      enable = true;
      # Only config.yml is managed; hosts.yml (the login token) is left alone.
      settings = {
        git_protocol = "ssh";
        aliases.co = "pr checkout";
      };
    };

    ssh = {
      enable = true;
      # nixpkgs openssh, not Apple's: only this build understands sk- (YubiKey) keys.
      # Consequence: UseKeychain is an Apple-only directive and must not appear here.
      package = pkgs.openssh;
      enableDefaultConfig = false;
      settings."*" = {
        # No per-shell ssh-agent (the old initContent leaked one process per terminal
        # tab). launchd's agent is always there; these three keys are offered directly.
        IdentityFile = [
          "~/.ssh/id_ed25519_sk"
          "~/.ssh/id_ed25519_sk2"
          "~/.ssh/id_ed25519"
        ];
        IdentitiesOnly = true;
        AddKeysToAgent = "yes"; # Apple's agent silently ignores the sk keys; harmless
        ForwardAgent = false;
        # One YubiKey touch per host per 10 minutes: later ssh/scp/nixos-rebuild to the
        # same host reuse the master connection. %C hashes user@host:port so the socket
        # path stays under the unix-socket length limit.
        ControlMaster = "auto";
        ControlPath = "~/.ssh/cm-%C";
        ControlPersist = "10m";
        StrictHostKeyChecking = "accept-new";
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
      };
      # `ssh plex` instead of `ssh root@plex`. Hostnames deliberately are not pinned here:
      # the short name already resolves through the home.internal search domain on the LAN,
      # and leaving it alone keeps whatever resolution works elsewhere (Tailscale) working.
      matchBlocks = lib.genAttrs homelabHosts (_: {user = "root";});
    };
  };
}
