My journey through learning Nix is contained in this repo.

The motivation behind this is to have a declarative set up for my homelab VM's and LXC's so that I don't have to document anything.

For other configurations like MacOS, it's nice to have a script for if I ever set up a new Mac.

## Deploying on a new Mac

- Presumably `git` needs to be installed for Flakes.
- Install Nix from Determinate Systems - but do the `--determinate` version because that works better with `nix-darwin`?
- Run the Flake install command (making sure the hostname has an entry in `flake.nix`)
  - `sudo nix run nix-darwin/master#darwin-rebuild -- switch` TODO: Put the git thing somewhere in here.
- One of the YubiKeys must be plugged in so that we can get our secrets decrypted.

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
