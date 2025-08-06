#!/usr/bin/env bash

set -e -u -o pipefail

if [ "$(uname)" == "Darwin" ]; then
  echo "do something..."

elif [ "$(uname)" == "Linux" ]; then
  # Generate SSH keys
  systemctl start sshd-keygen.service
  SSH_KEY_LOCATION="/etc/ssh/ssh_host_ed25519_key.pub"
  
  if [ -d "/persistent/" ]; then
    # Make folders required to house base persistence files
    mkdir -p /persistent/{etc/ssh,var/{lib/{nixos,systemd},log}}
    # Copy files to persistent locations - could move as well
    mv -f /etc/ssh/ssh_host_* /persistent/etc/ssh/
    SSH_KEY_LOCATION="/persistent/etc/ssh/ssh_host_ed25519_key.pub"
    cp /etc/machine-id /persistent/etc/

    # Copy current contents of folders (don't move so we don't break running things?)
    cp -r /var/lib/nixos/ /persistent/var/lib/nixos/
    cp -r /var/lib/systemd/ /persistent/var/lib/systemd/
    cp -r /var/log/ /persistent/var/log/
  fi
  
  # Output age key for secrets decryption
  nix shell "nixpkgs#ssh-to-age" --extra-experimental-features "nix-command flakes" --command ssh-to-age -i $SSH_KEY_LOCATION
fi