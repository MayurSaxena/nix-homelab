#!/usr/bin/env bash
#
# onboard-host.sh — the manual second half of bringing up a new NixOS LXC.
#
# `tofu apply` (via the local-exec provisioners in
# provisioning/modules/nixos-lxc/main.tf) only creates the container and
# registers its age key in ../.sops.yaml. It deliberately stops there — a
# multi-minute remote build and a YubiKey-gated `nixos-rebuild switch` don't
# belong inside a provisioner that gates tofu apply/destroy's success/failure.
#
# This script is the next step, run by hand (or by Claude) once `tofu apply`
# has finished:
#
#   1. Commits and pushes .sops.yaml / secrets/* if tofu's provisioner left
#      uncommitted changes. Idempotent — re-running after a partial failure
#      with nothing left to commit is not an error. Skipped in --local mode.
#   2. Builds the host's flake configuration on nix-builder and ships +
#      activates the closure on the new container over SSH.
#
# Usage:
#   ./onboard-host.sh [--local] <flake-host-key> <container-ip>
#
# --local deploys from this working tree (--flake .#<host>, no --refresh —
# meaningless for a local ref) instead of GitHub, and skips the commit/push
# step entirely. Use it to verify a change actually works before pushing;
# without --local, autoUpgrade will silently revert the host back to
# whatever's on GitHub the next time it runs, since nothing was committed.
#
# <flake-host-key> is the attribute name under `nixosConfigurations` in
# flake.nix — NOT necessarily the module/output name in provisioning/main.tf
# or outputs.tf. Three hosts differ: module dns-server -> flake key dns,
# module plex-server -> flake key plex, module fileserver -> flake key files.
#
# <container-ip> is whatever tofu apply / tofu output just printed.
#
# Requires a YubiKey inserted for both the root@nix-builder and root@<ip> SSH
# prompts — root SSH is hardware-key-only on every host, so this step can't
# be unattended. Building goes through root@nix-builder rather than the `nix`
# user: the `nix` account's key (/etc/nix/remote-builder-key) is deliberately
# root-only-readable locally and reserved for the unattended
# custom.remote-builds/autoUpgrade daemon path. Using root@ here reuses the
# same YubiKey-gated identity already required for --target-host, instead of
# forcing this whole script under sudo (which then hits a second problem:
# root's own local known_hosts is essentially empty).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") [--local] <flake-host-key> <container-ip>" >&2
  exit 1
}

local_mode=0
if [ "${1:-}" = "--local" ]; then
  local_mode=1
  shift
fi

[ $# -eq 2 ] || usage
host="$1"
ip="$2"

cd "${repo_root}"

if ! nix eval ".#nixosConfigurations.${host}.config.system.stateVersion" >/dev/null 2>&1; then
  echo "ERROR: no nixosConfigurations.\"${host}\" in flake.nix." >&2
  echo "Check the flake key, not the provisioning/main.tf module name — e.g. the" >&2
  echo "dns-server module is flake key 'dns', plex-server is 'plex', fileserver is 'files'." >&2
  exit 1
fi

if [ "${local_mode}" -eq 1 ]; then
  echo "==> --local: deploying from this working tree, not committing/pushing anything"
  flake_ref="."
else
  if [ -n "$(git status --porcelain -- .sops.yaml secrets/)" ]; then
    echo "==> Committing .sops.yaml/secrets/ changes for ${host}"
    git add .sops.yaml secrets/
    git commit -m "Add ${host} to .sops.yaml"
    git push
  else
    echo "==> .sops.yaml/secrets/ already clean, nothing to commit for ${host}"
  fi
  flake_ref="github:MayurSaxena/nix-homelab"
fi

echo "==> Building ${host} on nix-builder and switching root@${ip}"
echo "    (YubiKey required for both root@nix-builder and root@${ip} — touch it when it blinks)"
set +e
if [ "${local_mode}" -eq 1 ]; then
  nixos-rebuild switch \
    --flake "${flake_ref}#${host}" \
    --build-host root@nix-builder.home.internal \
    --target-host "root@${ip}"
else
  # --refresh is required, not optional: a github: flake ref is subject to
  # Nix's tarball-ttl caching, so a switch run shortly after a push can
  # silently rebuild the *previous* commit with no error or warning at all --
  # only a diff against the store path actually deployed reveals it. This
  # bit us live while switching caddy right after pushing a fix. Meaningless
  # for a local ref (no tarball involved), so only passed in the non-local
  # branch.
  nixos-rebuild switch \
    --flake "${flake_ref}#${host}" \
    --build-host root@nix-builder.home.internal \
    --target-host "root@${ip}" \
    --refresh
fi
switch_status=$?
set -e

# Known first-switch quirk: impermanence's own machine-id persistence unit
# refuses to bind-mount over /etc/machine-id if that path is already a
# non-empty regular file -- which it always is, since systemd writes a real
# one during the base image's first boot, before this unit ever gets a
# chance to run its own placeholder workaround (see nix-community/impermanence
# PR #242). Self-heal it here rather than making every onboarding rediscover
# the fix by hand.
#
# This check (and its fix, when needed) runs as plain `ssh` calls, separate
# from whatever socket nixos-rebuild switch just used for the same host --
# without multiplexing, that's a third YubiKey touch on every single
# invocation, on top of the two nixos-rebuild switch already needs for its
# own build-host/target-host legs. ControlPersist keeps this connection
# alive briefly after the script exits too, so a follow-up run against the
# same host (e.g. the idempotency check in CLAUDE.md's local-verification
# step) can reuse it instead of prompting again.
ssh_control_dir="/tmp/nix-homelab-ssh-mux"
mkdir -p "${ssh_control_dir}"
ssh_mux_opts=(-o ControlMaster=auto -o "ControlPath=${ssh_control_dir}/%r@%h:%p" -o ControlPersist=10m)

unit='persist-persistent-etc-machine\x2did.service'
if ssh "${ssh_mux_opts[@]}" "root@${ip}" "systemctl is-failed '${unit}'" 2>/dev/null | grep -q '^failed$'; then
  echo "==> Known quirk: ${unit} failed on first activation, checking if it's safe to self-heal"
  if ssh "${ssh_mux_opts[@]}" "root@${ip}" 'diff -q /etc/machine-id /persistent/etc/machine-id' >/dev/null 2>&1; then
    echo "==> /etc/machine-id matches the persisted copy -- removing the stray file, retrying the mount, and restarting journald"
    # journald appears to open/cache /etc/machine-id at its own startup and
    # doesn't notice the swap from a plain file to this bind mount, even
    # though the content is identical -- observed live on yamtrack's
    # onboarding as journalctl silently returning zero entries, system-wide,
    # for the whole host, with journald itself still "active (running)".
    # Restarting it is cheap and idempotent either way, so do it
    # unconditionally here rather than trying to detect the symptom first.
    ssh "${ssh_mux_opts[@]}" "root@${ip}" "rm -f /etc/machine-id && systemctl restart '${unit}' && systemctl restart systemd-journald"
  else
    echo "WARNING: ${unit} failed but /etc/machine-id doesn't match the persisted copy." >&2
    echo "Not auto-fixing -- investigate by hand on root@${ip}." >&2
  fi
fi

if [ "${switch_status}" -ne 0 ]; then
  # nixos-rebuild switch returns non-zero if *any* unit failed during
  # activation -- including the known machine-id quirk above, even when its
  # self-heal fully fixed it. Re-check the target's actual state rather than
  # trusting this stale exit code: if nothing is failed anymore, the heal was
  # the whole story and this isn't a real error. Fail closed if the recheck
  # itself can't reach the host -- an unreachable host is not evidence of
  # health, so don't let that masquerade as "nothing failed".
  ssh_check_ok=1
  remaining_failed=$(ssh "${ssh_mux_opts[@]}" "root@${ip}" 'systemctl --failed --no-legend' 2>/dev/null) || ssh_check_ok=0
  if [ "${ssh_check_ok}" -eq 1 ] && [ -z "${remaining_failed}" ]; then
    echo "==> nixos-rebuild switch exited ${switch_status}, but no units are failed on ${host} now -- the self-heal above resolved it."
  else
    echo "ERROR: nixos-rebuild switch exited ${switch_status}. Check the output above" >&2
    if [ "${ssh_check_ok}" -eq 1 ]; then
      echo "Still-failed units on ${host}:" >&2
      echo "${remaining_failed}" >&2
    else
      echo "(couldn't re-check ${host}'s unit status to confirm)" >&2
    fi
    exit "${switch_status}"
  fi
fi

if [ "${local_mode}" -eq 1 ]; then
  echo "==> --local deploy complete. Nothing was committed or pushed --" \
       "commit and push once you're happy, or the next autoUpgrade cycle" \
       "will revert ${host} back to whatever's currently on GitHub."
fi
