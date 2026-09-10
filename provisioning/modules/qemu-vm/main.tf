# A QEMU guest cloned from a Packer-built template.
#
# Deliberately not named windows-vm. Nothing below is Windows-specific: the Windows answers
# arrive as variables (os_type, bios, machine, enable_tpm via the template), and a Linux
# guest uses the same module with different ones. This resource holds OpenTofu state, so
# naming it generically now avoids `moved` blocks or state surgery later -- see the
# generalisation note in LAB.md.

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.80.0"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  node_name   = var.pve_node_name
  name        = var.vm_name
  description = var.vm_description
  tags        = var.tags
  pool_id     = var.pool_id

  bios    = var.bios
  machine = var.machine

  operating_system {
    type = var.os_type
  }

  clone {
    vm_id = var.template_vm_id
    # A full clone, not a linked one. Linked clones stay tethered to the template, so a
    # template rebuild would be blocked by its own children and a range reset could not
    # outlive the image it came from.
    full = true
  }

  # No efi_disk or tpm_state block here on purpose: both are cloned from the template, which
  # Packer built with them. Declaring them again fights the clone rather than reinforcing it.

  cpu {
    cores = var.num_cpu_cores
    # host, so guests see the real CPU's instruction set. Windows 11 checks for features a
    # generic model does not advertise, and refuses to install without them.
    type = "host"
  }

  memory {
    dedicated = var.memory_size_mb

    # floating == dedicated attaches the balloon device without ever reclaiming through it.
    #
    # The earlier value here was 0, which removes the device entirely. That looked harmless
    # and was not: with no balloon device, Proxmox has no memory statistics from the guest
    # and falls back to reporting the QEMU process's resident size, which includes guest page
    # cache and emulator overhead. A domain controller genuinely using 38% of its RAM showed
    # as 4502MB of 4096MB in the Proxmox summary -- over 100%, and an invitation to solve a
    # capacity problem that does not exist.
    #
    # Ballooning reclaims only down to this floor, so setting it equal to the allocation
    # gives accurate reporting with no possibility of the host squeezing the guest. The
    # driver and service arrive with the VirtIO guest tools the templates install.
    floating = var.memory_size_mb
  }

  disk {
    datastore_id = var.vm_disk_datastore
    interface    = "scsi0"
    size         = var.disk_size_gb
    file_format  = "raw"
    cache        = "writeback"
    iothread     = true
    ssd          = true
  }

  scsi_hardware = "virtio-scsi-single"

  dynamic "network_device" {
    for_each = var.network_interfaces
    iterator = netif
    content {
      bridge   = "vmbr0"
      model    = "virtio"
      vlan_id  = netif.value
      firewall = false
    }
  }

  initialization {
    datastore_id = var.vm_disk_datastore
    # NoCloud rather than the OpenStack default: it is the format cloudbase-init's
    # NoCloudConfigDriveService reads, and the templates are configured for it.
    type = "nocloud"

    dns {
      domain  = var.domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = var.ipv4_settings == "dhcp" ? "dhcp" : split(";", var.ipv4_settings)[0]
        gateway = var.ipv4_settings == "dhcp" ? null : split(";", var.ipv4_settings)[1]
      }
    }

    user_account {
      username = var.ci_username
      password = var.ci_password
      keys     = var.ci_public_keys
    }
  }

  agent {
    enabled = var.enable_agent
  }

  dynamic "startup" {
    for_each = var.startup_order != null ? [var.startup_order] : []
    iterator = order
    content {
      order = order.value
    }
  }

  on_boot = var.startup_order != null
  started = true

  # NOTE: this only takes effect for guests created after it was added. It is read from the
  # resource's stored state at destroy time, not from configuration, so adding it to an
  # existing guest requires an apply before it helps -- a guest already stuck on a graceful
  # shutdown has to be stopped out of band first.
  #
  # Pull the plug rather than asking politely. The provider's graceful path shuts a guest
  # down through the QEMU guest agent, so a guest whose agent is broken -- which is exactly
  # the guest you are most likely to be destroying -- leaves `tofu destroy` waiting on a
  # shutdown that never happens, with no PVE task in flight to show why. These are lab VMs
  # rebuilt from a playbook; there is no state in them worth a clean unmount.
  stop_on_destroy = true

  # Rebuilding a template must not destroy the VMs already cloned from it. Same reasoning as
  # the nixos-lxc module ignoring template_file_id: the clone source matters at creation and
  # is meaningless afterwards.
  lifecycle {
    ignore_changes = [clone]
  }
}
