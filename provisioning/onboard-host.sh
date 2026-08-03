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
#      with nothing left to commit is not an error.
#   2. Builds the host's flake configuration on nix-builder and ships +
#      activates the closure on the new container over SSH.
#
# Usage:
#   ./onboard-host.sh <flake-host-key> <container-ip>
#
# <flake-host-key> is the attribute name under `nixosConfigurations` in
# flake.nix — NOT necessarily the module/output name in provisioning/main.tf
# or outputs.tf. Three hosts differ: module dns-server -> flake key dns,
# module plex-server -> flake key plex, module fileserver -> flake key files.
#
# <container-ip> is whatever tofu apply / tofu output just printed.
#
# Requires a YubiKey inserted for the root@<ip> SSH prompt — root SSH is
# hardware-key-only on every host, so this step can't be unattended.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <flake-host-key> <container-ip>" >&2
  exit 1
}

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

if [ -n "$(git status --porcelain -- .sops.yaml secrets/)" ]; then
  echo "==> Committing .sops.yaml/secrets/ changes for ${host}"
  git add .sops.yaml secrets/
  git commit -m "Add ${host} to .sops.yaml"
  git push
else
  echo "==> .sops.yaml/secrets/ already clean, nothing to commit for ${host}"
fi

echo "==> Building ${host} on nix-builder and switching root@${ip}"
echo "    (YubiKey required for root SSH — touch it when it blinks)"
nixos-rebuild switch \
  --flake "github:MayurSaxena/nix-homelab#${host}" \
  --build-host nix@nix-builder.home.internal \
  --target-host "root@${ip}" \
  --use-remote-sudo
