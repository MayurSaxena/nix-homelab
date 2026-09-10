# QEMU guests. main.tf stays LXC-only.
#
# Only *durable* lab machines belong here. Disposable guests -- CTF boxes, research VMs,
# anything booted from a live ISO -- are cloned ad hoc and take DHCP, because declaring them
# would apply a rebuild-from-repo guarantee to machines defined by not needing one. See the
# ownership table in LAB.md.

module "lab-dc01" {
  source        = "./modules/qemu-vm"
  pve_node_name = var.pve_node_name

  vm_name        = "lab-dc01"
  vm_description = "lab.internal domain controller (Terraform)"
  template_vm_id = 9100 # tpl-ws2025

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
