output "vm_id" {
  value = proxmox_virtual_environment_vm.vm.vm_id
}

output "vm_address" {
  description = "Reported by the guest agent, so empty until the agent is up."
  value = {
    v4 = proxmox_virtual_environment_vm.vm.ipv4_addresses
    v6 = proxmox_virtual_environment_vm.vm.ipv6_addresses
  }
}
