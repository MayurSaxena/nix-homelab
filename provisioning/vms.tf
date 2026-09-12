# QEMU guests. main.tf stays LXC-only.
#
# Only *durable* lab machines belong here. Disposable guests -- CTF boxes, research VMs,
# anything booted from a live ISO -- are cloned ad hoc and take DHCP, because declaring them
# would apply a rebuild-from-repo guarantee to machines defined by not needing one. See the
# ownership table in LAB.md.

# Templates are found by tag, not by a hardcoded id.
#
# Packer lets PVE allocate whatever id is free and tags the result, so a new template can be
# built alongside the one it replaces and the old one retired only once the new one exists.
# Nothing here needs to know a number, and nothing needs a block of ids reserved in advance.
#
# `one()` is the assertion, not a convenience: it returns null when no template carries the
# tag and errors outright when more than one does. Both are worth failing on. Two matches
# means a build is in flight or a retirement did not complete, and cloning in that window
# would silently pick an arbitrary one.
data "proxmox_virtual_environment_vms" "ws2025_template" {
  tags = ["template", "ws2025"]

  filter {
    name   = "template"
    values = ["true"]
  }

  # Without this, "no template" surfaces as "Attempt to get attribute from null value",
  # which names neither the tag nor the fix.
  lifecycle {
    postcondition {
      condition     = length(self.vms) == 1
      error_message = "Expected exactly one template tagged ws2025, found ${length(self.vms)}. None means it has not been built yet: run `just packer-build windows ws2025`. More than one means a build is in flight, or a retirement did not finish."
    }
  }
}

locals {
  ws2025_template_id = one(data.proxmox_virtual_environment_vms.ws2025_template.vms).vm_id
}

module "dc01" {
  source        = "./modules/qemu-vm"
  pve_node_name = var.pve_node_name

  vm_name        = "dc01"
  vm_description = "lab.internal domain controller (Terraform)"
  template_vm_id = local.ws2025_template_id

  os_type = "win11" # covers Server 2022/2025 as well as Windows 11
  bios    = "ovmf"
  machine = "q35"

  num_cpu_cores  = 2
  memory_size_mb = 4096
  disk_size_gb   = 60

  network_interfaces = { eth0 = 90 }

  # Static, and it has to be: every domain member resolves the forest through this address,
  # and a domain controller that moves is a domain controller nobody can find.
  ipv4_settings = "10.0.90.10/24;10.0.90.1"

  # Points at technitium while the forest is being created, because at that moment the DC is
  # not yet a DNS server and still needs to resolve things. Promotion installs the DNS role
  # and repoints the host at itself, with technitium as the forwarder.
  dns_servers = ["10.0.10.2"]
  domain      = "lab.internal"

  ci_username = "Administrator"
  ci_password = var.lab_admin_password

  pool_id = "lab"
  tags    = ["terraform", "windows", "lab", "ad"]

  # Deliberately no startup_order: the range is not production and should not compete with it
  # for boot resources, nor come back automatically after a host reboot.
}

# The Kali template, built from the downloaded cloud image.
#
# This exists so that every guest in the lab is the same kind of thing: a full clone of a
# template. Windows needs a template because Microsoft ships no usable image and one has to
# be installed; Kali ships a finished, cloud-init-ready disk, so there is nothing to install
# and no Packer stage. That difference belongs to the vendors, and it is allowed to show up
# in how a template is *made* -- but not in how a guest is *deployed*, which is why this is
# a template rather than an image each guest imports for itself.
#
# Kali rather than Parrot, and that was a real choice: Parrot publishes no cloud image at
# all -- only live ISOs that install through Calamares, and ~10GB desktop appliances. See
# LAB.md for the options if Parrot itself is ever wanted.
#
# Note the image filename is stable, so re-running `just lab-image kali` replaces the file
# without OpenTofu seeing any change here. That is deliberate: moving to a newer Kali is an
# explicit rebuild of this template, not something that happens under a guest during an
# unrelated apply.
resource "proxmox_virtual_environment_vm" "kali_template" {
  node_name   = var.pve_node_name
  name        = "tpl-kali"
  description = "Kali Linux cloud image. Rebuilt by tainting this resource; do not edit in place."
  tags        = ["terraform", "template", "kali"]
  pool_id     = "lab"
  template    = true
  started     = false

  operating_system { type = "l26" }

  # seabios, not the ovmf the Windows templates use: OVMF needs an EFI vars disk, which
  # Packer creates for those. The cloud image boots BIOS perfectly well.
  bios    = "seabios"
  machine = "q35"

  cpu { type = "host" }

  # Sized to match what clones ask for, so cloning never has to resize.
  scsi_hardware = "virtio-scsi-single"
  disk {
    datastore_id = "local-zfs"
    file_id      = "local:iso/kali-cloud-amd64.img"
    interface    = "scsi0"
    size         = 60
    file_format  = "raw"
    cache        = "writeback"
    iothread     = true
    ssd          = true
  }

  # A template holds no cloud-init drive and no address. Clones get their own, from the
  # module, which is the whole point of the split.
  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    vlan_id  = 90
    firewall = false
  }

  agent { enabled = true }
}

module "kali01" {
  source        = "./modules/qemu-vm"
  pve_node_name = var.pve_node_name

  vm_name        = "kali01"
  vm_description = "Kali Linux attack box (Terraform)"
  template_vm_id = proxmox_virtual_environment_vm.kali_template.vm_id

  os_type = "l26"

  # Matches the template it is cloned from; see the comment there.
  bios    = "seabios"
  machine = "q35"

  num_cpu_cores  = 4
  memory_size_mb = 8192
  disk_size_gb   = 60

  network_interfaces = { eth0 = 90 }
  ipv4_settings      = "10.0.90.50/24;10.0.90.1"

  # technitium, not the domain controller.
  #
  # Only a domain *member* has to resolve against AD DNS, and this is not one. Pointing a
  # non-member at the DC makes it depend on the DC being up to resolve anything at all,
  # including the internet, which is the wrong failure mode for the box you attack the DC
  # *from*. technitium conditionally forwards lab.internal to the DC, so the forest stays
  # fully resolvable from here, which is what actually matters.
  #
  # It sits in the pets block at .50, not the workstation block: nothing looks it up at a
  # fixed address, but it is a machine you come back to rather than throw away.
  dns_servers = ["10.0.10.2"]
  domain      = "lab.internal"

  # kali, not root: the cloud image's own default user, and the one its sudo rules expect.
  ci_username    = "kali"
  ci_password    = var.lab_admin_password
  ci_public_keys = [var.lab_ansible_public_key]

  pool_id = "lab"
  tags    = ["terraform", "linux", "lab", "kali"]
}

# Renames, not replacements.
#
# Guests were prefixed lab- until the whole lab moved under lab.internal, which said it
# twice. Without these, OpenTofu reads a renamed module as "destroy that one, create this
# one" -- which for dc01 would mean rebuilding the forest to change a label.
#
# Safe to keep indefinitely and safe to run against state that never held the old names:
# a moved block whose source does not exist is a no-op.
moved {
  from = module.lab-dc01
  to   = module.dc01
}

moved {
  from = module.lab-kali01
  to   = module.kali01
}
