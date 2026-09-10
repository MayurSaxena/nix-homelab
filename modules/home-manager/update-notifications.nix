{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.custom.update-notifications;

  githubUrl = "https://github.com/${cfg.githubRepository}.git";

  webhookPath = config.sops.secrets.${cfg.discord.secret}.path or "";

  # The Determinate Nix client rather than `pkgs.nix`: Determinate owns the
  # daemon on this Mac (modules/macos/base.nix sets determinateNix.enable), and
  # pointing a differently-versioned client at it buys nothing. Absolute
  # because a launchd agent inherits almost no PATH.
  nix = "/nix/var/nix/profiles/default/bin/nix";

  check = pkgs.writeShellApplication {
    name = "nix-homelab-update-check";
    runtimeInputs = [pkgs.coreutils pkgs.git pkgs.curl pkgs.jq];
    text = ''
      state_dir="${cfg.stateDirectory}"
      mkdir -p "$state_dir"
      cache="$state_dir/evaluated-toplevel"

      # HTTPS, not the checkout's git@github.com remote: this runs from a
      # launchd agent with no ssh-agent and no decrypted key (the SSH key is
      # itself one of the YubiKey-gated sops secrets), so an SSH remote would
      # fail every time. The repository is public, so an unauthenticated
      # ls-remote is enough to learn where the branch points.
      if ! remote_sha=$(git ls-remote "${githubUrl}" "refs/heads/${cfg.branch}" | cut -f1); then
        echo "cannot reach ${githubUrl}; skipping this check" >&2
        exit 0
      fi
      if [ -z "$remote_sha" ]; then
        echo "no such branch ${cfg.branch} at ${githubUrl}" >&2
        exit 1
      fi

      current=$(readlink /run/current-system)

      # Evaluating the whole darwin config is the only check that answers the
      # real question -- "would switching change anything on *this* Mac" --
      # rather than "has some commit landed". Most commits in this repo touch
      # only the Linux hosts, and a SHA comparison would nag about every one of
      # them. The tradeoff is that this is a full eval of nixpkgs +
      # home-manager, so its result is cached against the commit that produced
      # it and only recomputed when the branch actually moves.
      target=""
      if [ -r "$cache" ]; then
        read -r cached_sha cached_target < "$cache" || true
        if [ "''${cached_sha:-}" = "$remote_sha" ]; then
          target="''${cached_target:-}"
        fi
      fi

      if [ -z "$target" ]; then
        # Pinned to the exact commit instead of passing the branch ref with
        # --refresh. A `github:owner/repo` ref is subject to Nix's tarball TTL,
        # so a check running shortly after a push can silently evaluate the
        # *previous* commit with no error -- the same trap CLAUDE.md documents
        # for manual switches. A full-SHA ref is immutable and always exact.
        if ! target=$(${nix} eval --raw \
          "github:${cfg.githubRepository}/$remote_sha#darwinConfigurations.${cfg.configurationName}.config.system.build.toplevel"); then
          echo "failed to evaluate $remote_sha; skipping this check" >&2
          exit 0
        fi
        printf '%s %s\n' "$remote_sha" "$target" > "$cache"
      fi

      if [ "$target" = "$current" ]; then
        exit 0
      fi

      # Distinguish "upstream moved" from "this Mac is running uncommitted
      # local work", which look identical in the comparison above but mean
      # opposite things. `cat-file -e` first because merge-base needs the
      # object present locally; a commit the checkout has never fetched is by
      # definition not an ancestor of HEAD.
      local_has_remote=0
      if [ -d "${cfg.checkoutPath}/.git" ] \
        && git -C "${cfg.checkoutPath}" cat-file -e "$remote_sha^{commit}" 2>/dev/null \
        && git -C "${cfg.checkoutPath}" merge-base --is-ancestor "$remote_sha" HEAD 2>/dev/null; then
        local_has_remote=1
      fi

      short=$(printf '%.7s' "$remote_sha")

      ${lib.optionalString (!cfg.notifyOnLocalDrift) ''
        if [ "$local_has_remote" -eq 1 ]; then
          echo "running system differs from ${cfg.branch}@$short, but the checkout already has that commit -- treating as local drift and staying quiet" >&2
          exit 0
        fi
      ''}

      # Both strings are standalone phrases, because each is used twice: as the
      # notification banner's subtitle, and after the bold host name in Discord.
      if [ "$local_has_remote" -eq 1 ]; then
        headline="running uncommitted local config"
        detail="Commit and push it, or the nightly switch will revert it."
      else
        headline="has not applied the latest ${cfg.branch}"
        detail="See ${cfg.autoUpgradeLog}."
      fi

      # The tail of the failed switch's own log, which is the only place the
      # reason is recorded -- nothing else reads it. Best-effort: launchd creates
      # this world-readable, but a run that never started leaves nothing here.
      log_excerpt=""
      if [ -r "${cfg.autoUpgradeLog}" ]; then
        log_excerpt=$(tail -n 20 "${cfg.autoUpgradeLog}" 2>/dev/null | tail -c 1200 || true)
      fi

      # Every delivery below is best-effort and independent: a denied
      # notification permission must not cost the Discord message, and a
      # revoked webhook must not cost the banner. Failures are logged and
      # counted, and the script exits non-zero only if *nothing* got through,
      # so a silently broken notifier shows up as a failing agent rather than
      # as nothing at all.
      delivered=0

      # `display notification` is attributed to whichever process sends the
      # AppleEvent, so macOS can silently drop it if that process has no
      # notification permission. Nothing is observable from here when it does,
      # which is exactly why the Discord half exists.
      if /usr/bin/osascript \
        -e "display notification \"$detail\" with title \"nix-homelab\" subtitle \"$headline\"" 2>/dev/null; then
        delivered=1
      else
        echo "osascript could not post a notification banner" >&2
      fi

      ${lib.optionalString cfg.discord.enable ''
        webhook=""
        # Legitimately absent rather than an error: this user's secrets are
        # decrypted from a YubiKey by a login agent (see msaxena.nix), so after
        # a boot with the key unplugged the symlink dangles and `-r` is false.
        if [ -r "${webhookPath}" ]; then
          webhook=$(cat "${webhookPath}")
        else
          echo "webhook secret at ${webhookPath} is unreadable (YubiKey absent at login?); skipping Discord" >&2
        fi

        if [ -n "$webhook" ]; then
          subject=""
          if [ -d "${cfg.checkoutPath}/.git" ]; then
            subject=$(git -C "${cfg.checkoutPath}" log -1 --format=%s "$remote_sha" 2>/dev/null || true)
          fi

          # Deliberately no store paths. The two closure paths differ only in
          # their hash, which tells a reader nothing, and at ~60 characters
          # each they crowded out every line that actually said something.
          payload=$(jq -n \
            --arg headline "$headline" \
            --arg detail "$detail" \
            --arg host "${cfg.configurationName}" \
            --arg sha "$short" \
            --arg subject "$subject" \
            --arg log "$log_excerpt" \
            '{content: ("🟡 **\($host)**: \($headline)"
                        + "\n`\($sha)`" + (if $subject == "" then "" else " \($subject)" end)
                        + "\n\($detail)"
                        + (if $log == "" then "" else "\n```\n\($log)\n```" end))}')

          # --fail because curl exits 0 on an HTTP 4xx, so a revoked webhook
          # would otherwise report success forever. stderr is dropped because
          # curl's messages embed the effective URL, which would write the
          # webhook into this agent's persisted log on every failure. Both
          # points are the same ones documented in
          # modules/nixos/failure-notifications.nix.
          if curl -sS --fail --max-time 20 \
            -H "Content-Type: application/json" \
            -X POST -d "$payload" "$webhook" >/dev/null 2>&1; then
            delivered=1
          else
            echo "failed to POST update notification to Discord" >&2
          fi
        fi
      ''}

      if [ "$delivered" -eq 0 ]; then
        echo "an update is available but no notification could be delivered" >&2
        exit 1
      fi
    '';
  };
in {
  options.custom.update-notifications = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Notify when this Mac's configuration is behind the flake's default
        branch.

        This is the watchdog over `custom.auto-upgrade-mac`, not a prompt to go
        and switch by hand: it runs hours *after* the nightly switch, so in the
        happy path it is silent every day and only speaks up when the switch
        did not happen. nix-darwin has no `system.autoUpgrade` and therefore no
        equivalent of the NixOS hosts' `OnFailure` notifier, so without this a
        broken nightly switch is completely silent -- the same failure mode that
        left `homepage`'s OOM-killed upgrades undetected for two weeks.

        It compares evaluated system closures rather than commit SHAs, so a
        commit touching only the Linux hosts never triggers it.

        Defaults to true rather than being an `mkEnableOption` for the reason
        `custom.failure-notifications` does: every consumer wants it, and the
        body is already guarded on Darwin, so a Linux home-manager user would
        get nothing from it either way.
      '';
    };

    githubRepository = lib.mkOption {
      type = lib.types.str;
      default = "MayurSaxena/nix-homelab";
      example = "owner/repo";
      description = ''
        `owner/repo` on GitHub. Both the `git ls-remote` URL and the `github:`
        flake ref used for the evaluation are derived from this.
      '';
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = ''
        Branch to compare against. This repository deploys from `main` with no
        staging step, so that is the branch a host is expected to be running.
      '';
    };

    configurationName = lib.mkOption {
      type = lib.types.str;
      default = "Mayurs-MacBook-Pro";
      description = ''
        The `darwinConfigurations` attribute key to evaluate. Not derivable
        from anything home-manager knows about, and not necessarily the
        machine's live hostname -- it is whatever `flake.nix` registered.
      '';
    };

    checkoutPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Projects/nix-homelab";
      description = ''
        Local clone, used only to tell "upstream has moved" apart from "this
        Mac is running uncommitted local changes", and to quote the offending
        commit's subject. A missing path is not an error: the check falls back
        to reporting an unapplied upstream commit.
      '';
    };

    notifyOnLocalDrift = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to notify when the running system differs from the branch even
        though the checkout already contains the branch tip -- i.e. the Mac is
        running uncommitted local work.

        Off by default because that state is self-inflicted and often
        deliberate mid-change, and a notification that fires every single day
        while you are working on something is a notification you learn to
        ignore. Turn it on if you would rather be nagged about config that
        exists only on this laptop.
      '';
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.cacheHome}/nix-homelab-update-check";
      description = ''
        Where the cached evaluation result is kept, so a day on which the
        branch has not moved costs one `git ls-remote` instead of a full
        nixpkgs evaluation.
      '';
    };

    autoUpgradeLog = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/darwin-auto-upgrade.err";
      description = ''
        stderr of the `custom.auto-upgrade-mac` daemon. Its tail is quoted in
        the Discord message, since a failed unattended switch leaves its reason
        nowhere else. Hardcoded rather than read from the system config: this is
        a home-manager module and cannot see nix-darwin's options.
      '';
    };

    hour = lib.mkOption {
      type = lib.types.ints.between 0 23;
      default = 9;
      description = ''
        Local hour at which to check. Deliberately hours after
        `custom.auto-upgrade-mac.hour`, so the nightly switch has had every
        chance to succeed first and a notification means something really is
        wrong. Also during the working day, so it reaches someone who can act
        on it. launchd runs a missed `StartCalendarInterval` job once on wake,
        so a laptop that was asleep still gets its check.
      '';
    };

    minute = lib.mkOption {
      type = lib.types.ints.between 0 59;
      default = 30;
      description = ''
        Minute within `hour`. Must be set: an unset `Minute` in a launchd
        `StartCalendarInterval` is a wildcard, which would run this check every
        minute of that hour.
      '';
    };

    discord = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Also post to a Discord webhook, so the notification survives macOS
          silently withholding notification permission from the agent, and
          reaches you when you are away from the Mac.

          The webhook is deliberately a different one from
          `custom.failure-notifications`' -- that channel is for hosts failing,
          this one is a routine reminder, and mixing them makes the failures
          easier to miss.
        '';
      };

      secret = lib.mkOption {
        type = lib.types.str;
        default = "discord/mac-update-webhook";
        description = ''
          Key in this user's sops file holding the webhook URL. The key must
          exist before the config will even build -- sops-nix validates its
          manifest against the sops file's key structure in a derivation, and a
          sops YAML keeps that structure in plaintext, so a missing key is a
          build failure rather than the activation failure you would expect.
        '';
      };
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    sops.secrets = lib.mkIf cfg.discord.enable {
      ${cfg.discord.secret} = {};
    };

    # `gui` (the default domain) is load-bearing: posting a notification
    # banner needs the user's Aqua session, which the `user` domain does not
    # provide.
    launchd.agents.nix-homelab-update-check = {
      enable = true;
      config = {
        Program = lib.getExe check;
        StartCalendarInterval = [
          {
            Hour = cfg.hour;
            Minute = cfg.minute;
          }
        ];
        # Both logs are wanted: stdout is empty on the happy path, and stderr
        # is the only place a withheld notification permission or a rejected
        # webhook is visible.
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/NixHomelabUpdateCheck/stdout";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/NixHomelabUpdateCheck/stderr";
        ProcessType = "Background";
        LowPriorityIO = true;
      };
    };

    # So the same check can be run by hand, which is the only way to see its
    # output interactively -- a launchd agent's failure is otherwise just a
    # line in a log file nobody opens.
    home.packages = [check];
  };
}
