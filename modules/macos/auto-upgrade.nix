{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.custom.auto-upgrade-mac;

  home = config.users.users.${cfg.user}.home;

  flakeUrl = "https://github.com/${cfg.githubRepository}.git";
  flakeRef = "github:${cfg.githubRepository}";

  # Wake shortly before the window so the switch runs at the hour rather than
  # whenever the lid next opens.
  wakeAt = let
    total = cfg.hour * 60 + cfg.minute - cfg.wakeLeadMinutes;
    wrapped =
      if total < 0
      then total + 1440
      else total;
    h = wrapped / 60;
    m = wrapped - h * 60;
    pad = n:
      if n < 10
      then "0${toString n}"
      else toString n;
  in "${pad h}:${pad m}:00";

  upgrade = pkgs.writeShellApplication {
    name = "darwin-auto-upgrade";
    runtimeInputs = [pkgs.coreutils pkgs.git pkgs.curl pkgs.jq];
    text = ''
      user="${cfg.user}"
      uid=$(/usr/bin/id -u "$user")
      webhook="${cfg.webhookFile}"

      log() { echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"; }

      # Banners must come from the user's Aqua session, which a root daemon is
      # not in -- hence launchctl asuser, the same mechanism nix-darwin uses to
      # run home-manager activation. It fails when nobody is logged in; that is
      # logged and never fatal, because Discord still gets through.
      banner() {
        /bin/launchctl asuser "$uid" /usr/bin/sudo -u "$user" /usr/bin/osascript \
          -e "display notification \"$2\" with title \"nix-homelab\" subtitle \"$1\"" \
          >/dev/null 2>&1 || echo "could not post banner (nobody logged in?)" >&2
      }

      discord() {
      ${lib.optionalString (!cfg.discord.enable) "  return 0"}
        # Legitimately absent rather than an error: this webhook is decrypted
        # from a YubiKey by the user's login agent, so after a boot without the
        # key the symlink dangles.
        if [ ! -r "$webhook" ]; then
          echo "webhook at $webhook unreadable (YubiKey absent at login?); skipping Discord" >&2
          return 0
        fi
        # jq -Rs turns arbitrary text -- log excerpts with quotes, newlines and
        # backslashes -- into one correctly escaped JSON string.
        payload=$(printf '%s' "$1" | jq -Rs '{content: .}')
        # --fail because curl exits 0 on an HTTP 4xx, so a revoked webhook would
        # report success forever. stderr is dropped because curl's messages
        # embed the effective URL, which would write the webhook into this log.
        if ! curl -sS --fail --max-time 20 \
          -H 'Content-Type: application/json' \
          -X POST -d "$payload" "$(cat "$webhook")" >/dev/null 2>&1; then
          echo "Discord POST failed" >&2
        fi
      }

      log "starting"

      # The job usually runs because the Mac just woke for it, and Wi-Fi is
      # often not up yet. Retrying beats a spurious failure every morning.
      sha=""
      attempt=0
      while [ "$attempt" -lt ${toString cfg.networkAttempts} ]; do
        sha=$(git ls-remote "${flakeUrl}" "refs/heads/${cfg.branch}" 2>/dev/null | head -n1 | cut -f1 || true)
        # `[ -n "$sha" ] && break` would be a bug here: an AND-list whose test
        # fails returns non-zero, and under errexit that exits the script -- so
        # the first unreachable attempt would end the run instead of retrying.
        if [ -n "$sha" ]; then
          break
        fi
        attempt=$((attempt + 1))
        sleep ${toString cfg.networkRetrySeconds}
      done

      if [ -z "$sha" ]; then
        log "cannot reach ${flakeUrl}, giving up"
        banner "upgrade could not start" "GitHub is unreachable."
        discord "🔴 **${cfg.configurationName}**: nightly upgrade could not start -- GitHub unreachable after ${toString cfg.networkAttempts} attempts."
        exit 1
      fi

      log "resolved ${cfg.branch} to $sha"
      banner "upgrade started" "Applying the latest configuration."

      # Pinned to the resolved commit, not the branch. An immutable ref is
      # exempt from Nix's tarball TTL (so --refresh is unnecessary), and it
      # means the verification below compares against the commit that was
      # actually applied rather than whatever landed on the branch meanwhile.
      #
      # caffeinate -i holds off idle sleep: the Mac may have woken solely for
      # this and would otherwise drop back to sleep mid-activation.
      #
      # </dev/null so Homebrew's `brew bundle` cleanup fails rather than
      # blocking forever if it ever prompts (see the taps comment in
      # modules/macos/packages.nix).
      if /usr/bin/caffeinate -i /run/current-system/sw/bin/darwin-rebuild switch \
        --flake "${flakeRef}/$sha#${cfg.configurationName}" </dev/null; then
        status=0
      else
        status=$?
      fi
      log "darwin-rebuild exited $status"

      current=$(readlink /run/current-system)
      if ! target=$(/nix/var/nix/profiles/default/bin/nix eval --raw \
        "${flakeRef}/$sha#darwinConfigurations.${cfg.configurationName}.config.system.build.toplevel" 2>/dev/null); then
        target=""
      fi

      # Uncommitted work is no longer applied to this Mac -- but only worth
      # mentioning if it would have changed *this* machine, since most edits in
      # this repo touch the Linux hosts. Comparing the closure the working tree
      # builds against the one its own committed HEAD builds answers that
      # exactly, and because both sides are local it is unaffected by how far
      # behind the branch the checkout happens to be. If either eval fails --
      # a syntax error mid-edit, an untracked file the flake cannot see -- it
      # degrades to a generic warning rather than staying silent.
      #
      # Run as the checkout's owner: git refuses a repository owned by another
      # user, and root is another user here.
      eval_toplevel() {
        /usr/bin/sudo -u "$user" --set-home /nix/var/nix/profiles/default/bin/nix eval --raw \
          "$1#darwinConfigurations.${cfg.configurationName}.config.system.build.toplevel" 2>/dev/null || true
      }

      drift=""
      if [ -d "${cfg.checkoutPath}/.git" ]; then
        changed=$(/usr/bin/sudo -u "$user" git -C "${cfg.checkoutPath}" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || true)
        if [ -n "$changed" ] && [ "$changed" -gt 0 ]; then
          head_sha=$(/usr/bin/sudo -u "$user" git -C "${cfg.checkoutPath}" rev-parse HEAD 2>/dev/null || true)
          worktree_top=$(eval_toplevel "${cfg.checkoutPath}")
          head_top=""
          if [ -n "$head_sha" ]; then
            head_top=$(eval_toplevel "git+file://${cfg.checkoutPath}?rev=$head_sha")
          fi

          if [ -n "$worktree_top" ] && [ -n "$head_top" ]; then
            if [ "$worktree_top" != "$head_top" ]; then
              drift="Uncommitted changes in ${cfg.checkoutPath} change this Mac's configuration, and are no longer applied to it."
            fi
          else
            drift="$changed uncommitted file(s) in ${cfg.checkoutPath}; could not work out whether they affect this Mac."
          fi
        fi
      fi

      if [ "$status" -ne 0 ]; then
        headline="upgrade failed (exit $status)"
      elif [ -z "$target" ]; then
        # A clean exit means activate() reached its last line, so this is
        # unlikely -- but an unverifiable result is exactly what a lax notifier
        # would wave through, so it counts as a failure.
        headline="upgraded, but the result could not be verified"
      elif [ "$target" != "$current" ]; then
        headline="exited cleanly but the system does not match ${cfg.branch}"
      else
        headline=""
      fi

      if [ -z "$headline" ]; then
        if [ -n "$drift" ]; then
          # Still a success, but deliberately its own colour: the upgrade did
          # what it should and quietly took local work out of the running
          # system, which is the one success worth looking at.
          log "success, local changes reverted"
          banner "upgrade succeeded, local changes reverted" "$drift"
          discord "🟠 **${cfg.configurationName}**: upgrade succeeded, but local changes were reverted"$'\n'"$drift"
        else
          log "success"
          banner "upgrade succeeded" "Your Mac is up to date."
          discord "🟢 **${cfg.configurationName}**: upgrade succeeded -- your Mac is up to date."
        fi
        exit 0
      fi

      log "failure: $headline"
      banner "$headline" "See ${cfg.errorLogFile}."
      detail=""
      if [ -n "$drift" ]; then
        detail=$'\n'"$drift"
      fi
      # The tail of this very run's stderr, the only record of why. The file is
      # still open for writing; reading it back is fine.
      excerpt=$(tail -n 25 "${cfg.errorLogFile}" 2>/dev/null | tail -c 1400 || true)
      if [ -n "$excerpt" ]; then
        detail="$detail"$'\n'"\`\`\`"$'\n'"$excerpt"$'\n'"\`\`\`"
      fi
      discord "🔴 **${cfg.configurationName}**: $headline$detail"
      exit "$status"
    '';
  };
in {
  options.custom.auto-upgrade-mac = {
    enable = lib.mkEnableOption "a daily unattended darwin-rebuild switch";

    githubRepository = lib.mkOption {
      type = lib.types.str;
      default = "MayurSaxena/nix-homelab";
      example = "owner/repo";
      description = ''
        `owner/repo` on GitHub. Both the `git ls-remote` URL and the `github:`
        flake ref are derived from this. HTTPS deliberately: this runs with no
        ssh-agent, and the SSH key is itself a YubiKey-gated secret.
      '';
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = ''
        Branch to follow. This repository deploys from `main` with no staging
        step, the same as the NixOS hosts.
      '';
    };

    configurationName = lib.mkOption {
      type = lib.types.str;
      default = "Mayurs-MacBook-Pro";
      description = ''
        The `darwinConfigurations` attribute key to switch to -- whatever
        `flake.nix` registered, which need not be the machine's live hostname.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = config.system.primaryUser;
      description = ''
        User whose session receives the notification banners, and whose
        checkout is inspected for uncommitted work.
      '';
    };

    hour = lib.mkOption {
      type = lib.types.ints.between 0 23;
      default = 4;
      description = ''
        Local hour to switch at, matching the NixOS hosts' window (18:00 UTC +
        jitter is roughly 4AM AEST) so the fleet moves together.
      '';
    };

    minute = lib.mkOption {
      type = lib.types.ints.between 0 59;
      default = 0;
      description = ''
        Minute within `hour`. Must be set: an unset `Minute` in a launchd
        `StartCalendarInterval` is a wildcard, which would start a switch every
        minute of that hour.
      '';
    };

    wake = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Schedule a `pmset repeat wakeorpoweron` shortly before the window, so
        the switch happens at the hour rather than whenever the lid next opens.
        launchd running the missed job on wake is the fallback, not the intent.

        macOS supports exactly one repeating power schedule, so enabling this
        takes ownership of it -- any `pmset repeat` set by hand is replaced on
        the next activation.
      '';
    };

    wakeLeadMinutes = lib.mkOption {
      type = lib.types.ints.between 1 60;
      default = 5;
      description = ''
        How long before the window to wake, giving the machine time to bring up
        Wi-Fi before the first `git ls-remote`.
      '';
    };

    networkAttempts = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = ''
        How many times to try resolving the branch before reporting the run as
        unable to start. A freshly woken Mac frequently has no network for the
        first few seconds.
      '';
    };

    networkRetrySeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Delay between those attempts.";
    };

    checkoutPath = lib.mkOption {
      type = lib.types.str;
      default = "${home}/Projects/nix-homelab";
      description = ''
        Local clone. Inspected only with `git status --porcelain`, to warn that
        uncommitted work has just been reverted, and to quote the applied
        commit's subject when the checkout happens to have it.
      '';
    };

    webhookFile = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.config/sops-nix/secrets/discord/mac-update-webhook";
      description = ''
        Decrypted Discord webhook. It lives under the user's home rather than
        /run/secrets because this Mac has no system-level sops: decryption needs
        the YubiKey, which only the user's login agent has. Root can read it,
        and its absence is handled rather than fatal.
      '';
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/darwin-auto-upgrade.log";
      description = "Where the daemon's stdout goes.";
    };

    errorLogFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/darwin-auto-upgrade.err";
      description = ''
        Where the daemon's stderr goes. Its tail is quoted in the failure
        notification, since nothing else records why a switch failed.
      '';
    };

    discord.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Post the outcome to a Discord webhook as well as the banner, so a run
        that finishes while nobody is logged in is still reported.

        Deliberately a different webhook from `custom.failure-notifications`':
        that channel is for hosts breaking, this one carries a routine daily
        success, and mixing them would make the failures easier to miss.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # On the system path so the plist can invoke it at a path that does not
    # move. nix-darwin's launchd activation runs `launchctl unload` on any
    # daemon whose plist content changed, which terminates a running job -- and
    # it unloads *before* copying the new plist, so a plist embedding a store
    # path would change on every nixpkgs bump, kill its own switch partway
    # through activation, and never install the replacement. Referencing
    # /run/current-system/sw/bin keeps the plist byte-identical forever.
    #
    # The corollary: changing an option above does change the plist, so apply
    # such a change with a manual switch rather than letting the daemon apply
    # it to itself.
    environment.systemPackages = [upgrade];

    launchd.daemons.darwin-auto-upgrade = {
      serviceConfig = {
        ProgramArguments = ["/run/current-system/sw/bin/darwin-auto-upgrade"];
        StartCalendarInterval = [
          {
            Hour = cfg.hour;
            Minute = cfg.minute;
          }
        ];
        StandardOutPath = cfg.logFile;
        StandardErrorPath = cfg.errorLogFile;
        # A root daemon, so no sudo and no Touch ID prompt. It does still need
        # the user logged in for the banner and for home-manager's own
        # activation, which nix-darwin runs via `launchctl asuser <uid> sudo -u`.
        EnvironmentVariables = {
          PATH = "/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };
    };

    system.activationScripts.postActivation.text = lib.mkIf cfg.wake (lib.mkAfter ''
      # Wake (or power on) shortly before the upgrade window. macOS allows one
      # repeating schedule, so this owns it.
      /usr/bin/pmset repeat wakeorpoweron MTWRFSU ${wakeAt}
    '');
  };
}
