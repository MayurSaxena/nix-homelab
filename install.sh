#!/usr/bin/env bash

set -e -u -o pipefail

if [ "$(uname)" == "Darwin" ]; then
  echo "do something..."

elif [ "$(uname)" == "Linux" ]; then
  
  # Make folders required to house base persistence files
  mkdir -p /persistent/{etc/ssh,var/{lib/nixos,log}}
  # Generate SSH keys
  systemctl start sshd-keygen.service
  sleep 2
  # Copy files to persistent locations - could move as well
  mv -f /etc/ssh/ssh_host_* /persistent/etc/ssh/
  cp /etc/machine-id /persistent/etc/

  # Copy current contents of folders (don't move so we don't break running things?)
  # Start with fresh logs though (could copy those as well I suppose)
  cp -r /var/lib/nixos/ /persistent/var/lib/nixos/

  # Output age key for secrets decryption
  nix shell "nixpkgs#ssh-to-age" --extra-experimental-features "nix-command flakes" --command ssh-to-age -i /persistent/etc/ssh/ssh_host_ed25519_key.pub

fi