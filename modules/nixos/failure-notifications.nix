{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.custom.failure-notifications;
in {
  options.custom.failure-notifications = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Post to Discord when one of `units` fails.

        Deliberately not `mkEnableOption`: every real host wants this, and the
        only config that must opt out is the `base-lxc` CI image, whose host
        key isn't in .sops.yaml and so can't decrypt the webhook at
        activation. Defaulting to true keeps this off the standard host
        preamble, which would otherwise gain an entry that is `true` in every
        host file.
      '';
    };

    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["nixos-upgrade" "nix-gc" "nix-optimise"];
      example = ["nixos-upgrade"];
      description = ''
        Units to attach an OnFailure notifier to, without the `.service`
        suffix. Each must actually exist, or the mere act of setting
        `onFailure` on it here will synthesise a unit with no ExecStart. All
        three defaults are defined unconditionally by the base module
        (`nix.gc.automatic`, `nix.optimise.automatic`, `system.autoUpgrade`).

        These are the timer-driven nix maintenance units, and they are exactly
        the ones Beszel cannot report on: its agent skips any unit whose
        ActiveEnterTimestamp is 0, which is every Type=oneshot unit that
        doesn't set RemainAfterExit. Long-running units like nix-daemon are
        already visible in Beszel and are deliberately absent here.

        Do NOT try to make these visible to Beszel by setting
        RemainAfterExit=yes. A timer-triggered start job on an already-active
        unit is a no-op, so the unit sticks in "active (exited)" after its
        first success and never runs again. That was tried twice and silently
        stopped nixos-upgrade and nix-optimise from running for over two
        weeks; see commit 579f379.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Lives in common.yaml (encrypted to *all-keys) rather than a per-host
    # file: every host needs the same webhook at runtime.
    sops.secrets."discord/service-failure-webhook" = {};

    systemd.services =
      {
        "notify-failure@" = {
          description = "Report failure of %i to Discord";
          # Already reached whenever these timers fire; wanted defensively so a
          # failure early in boot still gets delivered rather than silently
          # dropped on an unconfigured network.
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig.Type = "oneshot";
          scriptArgs = "%i";
          script = ''
            set -uo pipefail
            unit="$1"

            url=$(cat ${config.sops.secrets."discord/service-failure-webhook".path})
            # networking.hostName is unset repo-wide (Proxmox supplies it), so
            # read the live kernel value rather than a build-time constant.
            host=$(cat /proc/sys/kernel/hostname)

            # Every detail lookup is non-fatal. NixOS prepends `set -e`, so
            # without the `|| true` a hiccup in journalctl or systemctl would
            # abort before the POST and lose the alert entirely -- exactly the
            # silent failure this module exists to prevent. Better to deliver a
            # notification with a blank field than none at all.
            result=$(${config.systemd.package}/bin/systemctl show "$unit.service" -p Result --value || true)
            code=$(${config.systemd.package}/bin/systemctl show "$unit.service" -p ExecMainStatus --value || true)

            # Scope the excerpt to the failing run. A bare `journalctl -n 25`
            # returns the last 25 lines across *all* invocations, so a unit that
            # fails quietly gets padded out with stale output from earlier runs
            # and the report reads as though far more happened than did.
            #
            # --since on InactiveExitTimestamp (when this run started) is used
            # rather than _SYSTEMD_INVOCATION_ID, which scopes correctly but
            # drops systemd's own "Main process exited"/"Failed with result"
            # lines -- the most useful part of the excerpt.
            since=$(${config.systemd.package}/bin/systemctl show "$unit.service" -p InactiveExitTimestamp --value || true)
            if [ -n "$since" ]; then
              log=$(${config.systemd.package}/bin/journalctl -u "$unit.service" --since "$since" -n 25 --no-pager -o cat 2>/dev/null | tail -c 1200 || true)
            else
              log=$(${config.systemd.package}/bin/journalctl -u "$unit.service" -n 25 --no-pager -o cat 2>/dev/null | tail -c 1200 || true)
            fi

            payload=$(${pkgs.jq}/bin/jq -n \
              --arg host "$host" \
              --arg unit "$unit.service" \
              --arg result "$result" \
              --arg code "$code" \
              --arg log "$log" \
              '{content: "🔴 **\($unit)** failed on **\($host)**\nresult=`\($result)` exit=`\($code)`\n```\n\($log)\n```"}')

            # --fail is load-bearing: without it curl exits 0 on an HTTP 4xx, so
            # a webhook Discord rejected (revoked, wrong channel, malformed
            # payload) would report success and this unit would go on silently
            # delivering nothing.
            #
            # curl's stderr is dropped rather than surfaced: its error messages
            # embed the effective URL, which would write the webhook secret
            # into the persisted journal on every delivery failure.
            if ! ${pkgs.curl}/bin/curl -sS --fail --max-time 20 \
              -H "Content-Type: application/json" \
              -X POST -d "$payload" "$url" >/dev/null 2>&1; then
              echo "failed to POST failure notification for $unit.service to Discord" >&2
              exit 1
            fi
          '';
        };
      }
      // lib.genAttrs cfg.units (unit: {
        onFailure = ["notify-failure@${unit}.service"];
      });
  };
}
