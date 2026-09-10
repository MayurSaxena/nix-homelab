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
      error_message = "Expected exactly one template tagged ws2025, found ${length(self.vms)}. None means it has not been built yet: run `just packer-build ws2025`. More than one means a build is in flight, or a retirement did not finish."
    }
  }
}

locals {
  ws2025_template_id = one(data.proxmox_virtual_environment_vms.ws2025_template.vms).vm_id
}

module "lab-dc01" {
  source        = "./modules/qemu-vm"
  pve_node_name = var.pve_node_name

  vm_name        = "lab-dc01"
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
