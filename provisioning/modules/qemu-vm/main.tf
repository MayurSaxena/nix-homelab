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
      version = ">= 0.113.1" # see provisioning/provider.tf for why this floor
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

  # Two ways to come into existence, and a guest uses exactly one.
  #
  # clone: from a Packer-built template, which is the Windows path, because Microsoft
  # publishes no cloud image and one has to be built.
  #
  # disk.file_id below: straight from a downloaded cloud image, which is the Linux path.
  # That image already carries cloud-init and the guest agent, so a Packer stage would add
  # nothing -- there is no template to build, rebuild or find by tag.
  #
  # The precondition is worth the four lines: with neither set the provider creates a
  # blank VM that boots to firmware and looks like a broken image, and with both set the
  # clone silently wins and the image is ignored.
  # Rebuilding a template must not destroy the VMs already cloned from it, and re-fetching a
  # cloud image must not destroy the guests built from it. Same reasoning as the nixos-lxc
  # module ignoring template_file_id: the source matters at creation and is meaningless
  # afterwards.
  lifecycle {
    ignore_changes = [clone, disk[0].file_id]

    precondition {
      condition     = (var.template_vm_id != null) != (var.source_image_file_id != null)
      error_message = "Set exactly one of template_vm_id (clone a template) or source_image_file_id (build from a cloud image)."
    }
  }

  dynamic "clone" {
    for_each = var.template_vm_id != null ? [var.template_vm_id] : []
    content {
      vm_id = clone.value
      # A full clone, not a linked one. Linked clones stay tethered to the template, so a
      # template rebuild would be blocked by its own children and a range reset could not
      # outlive the image it came from.
      full = true
    }
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
    # Null when cloning, since the clone brings its own disk. Set, it imports that image
    # into a fresh disk -- a copy, so the image can be replaced later without touching any
    # guest already built from it.
    file_id     = var.source_image_file_id
    interface   = "scsi0"
    size        = var.disk_size_gb
    file_format = "raw"
    cache       = "writeback"
    iothread    = true
    ssd         = true
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

  # A guest whose image has no cloud-init agent gets no cloud-init drive.
  #
  # Attaching one anyway is not harmless: Proxmox adds a CD-ROM the guest ignores, and
  # OpenTofu then owns an address the guest never reads, so `ip_config` here and the real
  # address on the box drift apart silently while the plan stays clean. Better to have no
  # opinion than a wrong one that looks authoritative.
  #
  # Such a guest has to reach its address some other way -- DHCP reservation, or a step in
  # its Ansible role -- and is configured by Ansible over SSH exactly like any other, since
  # nothing downstream of here depends on how the address was set.
  dynamic "initialization" {
    for_each = var.enable_cloud_init ? [1] : []
    content {
      datastore_id = var.vm_disk_datastore
      # No `type`. Proxmox picks the cloud-init format from the guest's ostype, and its choice
      # is already correct for every OS this module will ever clone:
      #
      #     if (defined(my $format = $conf->{citype})) { return $format; }
      #     if (defined(my $ostype = $conf->{ostype})) {
      #         return 'configdrive2' if windows_version($ostype);
      #     }
      #     return 'nocloud';
      #
      # configdrive2 for Windows, because that is the only format cloudbase-init reads, and it
      # is the branch where Proxmox writes admin_pass and public_keys into metadata. nocloud
      # for everything else, because Linux cloud-init wants MAC-based interface matching.
      #
      # Both of the obvious overrides are wrong. "nocloud" was set here first and cost days:
      # NoCloudConfigDriveService implements no get_admin_password, so cloudbase-init invented a
      # random password and every workaround built on top of that was solving a problem this
      # line had created. Pinning "configdrive2" instead fixes Windows and breaks Linux. Saying
      # nothing is the only setting that is right for both.

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


}
