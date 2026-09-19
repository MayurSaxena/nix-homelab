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

  # Remove the cloud-init CD-ROM after the guest has consumed it. The drive holds the
  # bootstrap password in plaintext metadata, and leaving it mounted is leaving a credential
  # on a virtual disc anyone with console access can read.
  #
  # By the time this provisioner fires the provider has already waited for the guest agent
  # (agent.enabled = true), so cloud-init / cloudbase-init has finished and the drive is no
  # longer needed. The PVE API credentials are in the environment from `source
  # util/pve-auth.sh`, which is a prerequisite for any tofu apply in this repo.
  provisioner "local-exec" {
    command = <<-EOT
      endpoint="$PROXMOX_VE_ENDPOINT"
      ticket="$PROXMOX_VE_AUTH_TICKET"
      csrf="$PROXMOX_VE_CSRF_PREVENTION_TOKEN"
      node="${var.pve_node_name}"
      vmid="${self.vm_id}"

      # Nothing to eject when there was no cloud-init drive.
      if [ "${var.enable_cloud_init}" != "true" ]; then exit 0; fi

      if [ -z "$endpoint" ] || [ -z "$ticket" ]; then
        echo "WARN: PVE API credentials not in environment; skipping cloud-init drive removal." >&2
        echo "Run manually: ssh root@$node qm set $vmid --delete ide2" >&2
        exit 0
      fi

      # Strip a trailing slash so the path join is clean.
      endpoint="$${endpoint%/}"

      result=$(curl -s -k \
        -H "Cookie: PVEAuthCookie=$ticket" \
        -H "CSRFPreventionToken: $csrf" \
        -X PUT \
        "$endpoint/api2/json/nodes/$node/qemu/$vmid/config" \
        -d "delete=ide2" 2>&1)

      if echo "$result" | grep -q '"data"'; then
        echo "cloud-init drive (ide2) removed from vmid $vmid"
      else
        echo "WARN: could not remove cloud-init drive from vmid $vmid: $result" >&2
        echo "Run manually: ssh root@$node qm set $vmid --delete ide2" >&2
      fi
    EOT
  }

  # Publishing a newer template must not replace a persistent workstation during an
  # unrelated apply. `lab-rebuild` explicitly requests replacement, which uses the current
  # template configuration when creating the new VM.
  #
  # initialization is ignored because the provisioner above removes the cloud-init drive
  # after the guest consumes it. Without this, the next apply would see "ide2 missing but
  # declared" and re-attach the drive, undoing the removal. Cloud-init only runs on first
  # boot, so there is nothing to update afterward.
  lifecycle {
    ignore_changes = [clone, initialization]
  }
}
