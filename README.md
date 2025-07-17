My journey through learning Nix is contained in this repo.

The motivation behind this is to have a declarative set up for my homelab VM's and LXC's so that I don't have to document anything.

For other configurations like MacOS, it's nice to have a script for if I ever set up a new Mac.

## Deploying on a new Mac

- Presumably `git` needs to be installed for Flakes.
- Install Nix from Determinate Systems - but do the `--determinate` version because that works better with `nix-darwin`?
- Run the Flake install command (making sure the hostname has an entry in `flake.nix`)
  - `sudo nix run nix-darwin/master#darwin-rebuild -- switch` TODO: Put the git thing somewhere in here.
- One of the YubiKeys must be plugged in so that we can get our secrets decrypted.

### What It Does
 - Enables lots of settings, such as:
   - Touch ID and Watch ID sudo
   - Menu bar widgets like clock and battery percentage
   - Minimal Dock
   - More powerful Finder
   - Installs Homebrew and some GUI casks and apps from the App Store
   - Command line tools I use often enough
   - `zsh` aliases and theme
   - Imports my ED25519 keypair from secrets
   - TODO: SSH config
   - TODO: Some prebaked `nix` dev shells (e.g. Python)
  

## Deploying a new NixOS System

- Boot up a new box (probably on Proxmox as an LXC)
- Generate a new ED25519 SSH host key in /etc/ssh/ssh_host_ed25519_key{.pub}
- TODO: Figure out the command for this.
- Spin up a new Nix shell with the `ssh-to-age` package
- `cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age`
- Back on a dev system, make a new entry for the hostname in `flake.nix` - and any necessary files in `hosts/` and `services/`
- Add the generated `age` key to `.sops.yaml` and associate it with the relevant secrets files.
- Run `sops <filename.yaml>` and add the secrets required for the new box.
- Push to Github.
- Run the command to run the flake.
- TODO: `nixos-rebuild switch --flake ...`?

### What The Base Image Does
 - Enables the firewall
 - Adds my Yubikeys as authorized keys for root via SSH
 - Adds a password in case I never have my Yubikeys (for use through Proxmox console)
 - Enables SSH but disallows root password logins
 - Shell aliases
 - Auto update
   - TODO: Need to find a way to update the Flake lock (maybe Github action)

TODO: Can we get impermanence on Proxmox LXC?
