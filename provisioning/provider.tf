terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.80.0"
    }
  }
}

provider "proxmox" {
  ssh {
    agent    = true
    username = "root"
  }
}