output "vm_id" {
  value = proxmox_virtual_environment_vm.vm.vm_id
}

output "vm_address" {
  description = "Reported by the guest agent, so empty until the agent is up."
  value = {
    # ipv4_addresses is list(list(string)) — one list per NIC as the agent sees it. Flatten
    # and drop loopback so the shape matches the CT module's flat list and [0] gives the
    # routable address.
    v4 = [for addr in flatten(proxmox_virtual_environment_vm.vm.ipv4_addresses) : addr if addr != "127.0.0.1"]
    v6 = [for addr in flatten(proxmox_virtual_environment_vm.vm.ipv6_addresses) : addr if addr != "::1"]
  }
}
