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

# The lab's Linux box, built straight from Kali's cloud image.
#
# No Packer template and no tag lookup: the image already carries cloud-init and the QEMU
# guest agent, which is the entire content of a Windows build, so the downloaded image is
# the artifact. `just lab-cloud-image kali` puts it on the node.
#
# Kali rather than Parrot, and that was a real choice: Parrot publishes no cloud image at
# all -- only live ISOs that install through Calamares, and ~10GB desktop appliances. See
# LAB.md for the options if Parrot itself is ever wanted.
module "kali01" {
  source        = "./modules/qemu-vm"
  pve_node_name = var.pve_node_name

  vm_name              = "kali01"
  vm_description       = "Kali Linux attack box, from the official cloud image (Terraform)"
  source_image_file_id = "local:iso/kali-cloud-amd64.img"

  os_type = "l26"

  # seabios, not the ovmf the Windows guests use. OVMF needs an EFI vars disk, and the
  # Windows guests get theirs from the template Packer built with one; a guest built from a
  # bare cloud image has no such inheritance, and this module deliberately declares no
  # efi_disk of its own. The image boots BIOS perfectly well, so there is nothing to gain.
  bios    = "seabios"
  machine = "q35"

  num_cpu_cores  = 4
  memory_size_mb = 8192
  # Must be at least the image's virtual size (25GiB) or the import is refused.
  disk_size_gb = 60

  network_interfaces = { eth0 = 90 }
  ipv4_settings      = "10.0.90.50/24;10.0.90.1"

  # The DC, so this box resolves lab.internal and can be pointed at the forest it is meant
  # to be attacking. It sits in the pets block at .50, not the workstation block: it is not
  # domain-joined and nothing looks it up by a fixed address, but it is a machine you come
  # back to rather than one you throw away. technitium behind it for everything else, via the DC's forwarder.
  dns_servers = ["10.0.90.10"]
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
