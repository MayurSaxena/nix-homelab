terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"

      # Floor, not a pin: .terraform.lock.hcl is committed and is what actually selects the
      # version. 0.113.1 is the floor because of two fixes this repo depends on -- cloud-init
      # password changes applied in place rather than forcing a worse remedy, and
      # ipv4_addresses restored on refresh, which this repo saw as an empty address list on
      # VMs that were plainly reachable. 0.113.0 itself was never published to the registry.
      #
      # This provider is pre-1.0 and does ship breaking changes in minors (0.109 renamed an
      # agent attribute), so bump with `tofu init -upgrade` and read the release notes rather
      # than letting it drift.
      version = ">= 0.113.1"
    }
  }
}

provider "proxmox" {
  ssh {
    agent    = true
    username = "root"
  }
}