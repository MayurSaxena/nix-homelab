#!/usr/bin/env bash

set -e -u -o pipefail

if [ "$(uname)" == "Darwin" ]; then
  echo "do something..."

elif [ "$(uname)" == "Linux" ]; then

  mkdir -p /persistent/{etc/ssh,var/{lib/nixos,log}}
  systemctl start sshd-keygen.service
  cp /etc/ssh/ssh_host_* /persistent/etc/ssh/
  cp /etc/machine-id /persistent/etc/
  cp -r /var/lib/nixos/ /persistent/var/lib/nixos/
  nix shell "nixpkgs#ssh-to-age" --extra-experimental-features "nix-command flakes" --command ssh-to-age -i /persistent/etc/ssh/ssh_host_ed25519_key.pub
  echo "Remember to run the following: nixos-rebuild switch --flake github:MayurSaxena/nix-homelab"

fi