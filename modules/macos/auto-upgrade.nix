{
  config,
  lib,
  ...
}: let
  cfg = config.custom.auto-upgrade-mac;

  flakeRef = "${cfg.flake}#${cfg.configurationName}";

  # Every path here is deliberately a *stable* one -- /bin, /usr/bin, the
  # Determinate Nix profile, and /run/current-system -- and this runs as an
  # inline `/bin/sh -c` string rather than through launchd.daemons.<n>.script.
  #
  # That is not stylistic. nix-darwin's launchd activation is:
  #
  #   if ! diff <new plist> <installed plist>; then
  #     launchctl unload <installed>; cp; launchctl load -w
  #
  # and `launchctl unload` terminates a job that is currently running. A plist
  # embedding a store path changes whenever nixpkgs moves, which is daily -- so
  # this daemon would unload, and kill, its own switch partway through
  # activation, leaving a half-applied system. Keeping the plist byte-identical
  # across nixpkgs bumps is what prevents that.
  #
  # The corollary: changing an option below *does* change the plist, so apply
  # such a change with a manual switch rather than letting the daemon apply it
  # to itself.
  switchScript = ''
    set -u
    echo "=== $(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ') switching to ${flakeRef}"

    # No tty, deliberately. Homebrew's activation runs `brew bundle` with
    # cleanup = "zap" on every switch, and it has prompted interactively on this
    # machine before (see the taps comment in modules/macos/packages.nix). A
    # prompt with an open stdin would wedge this job until someone noticed;
    # </dev/null makes it fail and get reported instead.
    exec </dev/null

    # --refresh is not optional for a `github:` ref: it is subject to Nix's
    # tarball TTL, so a run shortly after a push can silently rebuild the
    # *previous* commit with no error at all.
    /run/current-system/sw/bin/darwin-rebuild switch --flake '${flakeRef}' --refresh
    status=$?

    echo "=== finished with status $status, now on $(/usr/bin/readlink /run/current-system)"
    exit $status
  '';
in {
  options.custom.auto-upgrade-mac = {
    enable = lib.mkEnableOption "a daily unattended darwin-rebuild switch";

    flake = lib.mkOption {
      type = lib.types.str;
      default = "github:MayurSaxena/nix-homelab";
      description = ''
        Flake to switch to. GitHub rather than a local checkout on purpose, so
        this Mac follows the same "pushing to main deploys" rule as the NixOS
        hosts.

        The consequence is the same one as on those hosts: uncommitted local
        config that is currently activated gets reverted by the next run.
      '';
    };

    configurationName = lib.mkOption {
      type = lib.types.str;
      default = "Mayurs-MacBook-Pro";
      description = ''
        The `darwinConfigurations` attribute key to switch to -- whatever
        `flake.nix` registered, which is not necessarily the machine's live
        hostname.
      '';
    };

    hour = lib.mkOption {
      type = lib.types.ints.between 0 23;
      default = 4;
      description = ''
        Local hour to switch at. 4AM to match the NixOS hosts' upgrade window
        (18:00 UTC + jitter is roughly 4AM AEST), so the whole fleet moves to
        the same commit at about the same time.

        launchd runs a missed `StartCalendarInterval` job once on wake, so a
        laptop that was asleep still upgrades -- shortly after it opens rather
        than at this hour.
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

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/darwin-auto-upgrade.log";
      description = "Where the daemon's stdout goes.";
    };

    errorLogFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/darwin-auto-upgrade.err";
      description = ''
        Where the daemon's stderr goes. `custom.update-notifications` quotes the
        tail of this file when it reports that the Mac has fallen behind, which
        is the only way the reason for a failed unattended switch reaches
        anyone -- nothing else watches it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.darwin-auto-upgrade = {
      serviceConfig = {
        ProgramArguments = ["/bin/sh" "-c" switchScript];
        StartCalendarInterval = [
          {
            Hour = cfg.hour;
            Minute = cfg.minute;
          }
        ];
        StandardOutPath = cfg.logFile;
        StandardErrorPath = cfg.errorLogFile;
        # A root daemon, so no sudo and therefore no Touch ID prompt to hang on.
        # It does still need the user logged in: nix-darwin runs home-manager's
        # activation through `launchctl asuser <uid> sudo -u <user>`, which needs
        # a live user session and fails at the login window. A Mac left asleep
        # while logged in -- the normal case -- is fine.
        EnvironmentVariables = {
          PATH = "/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };
    };
  };
}
