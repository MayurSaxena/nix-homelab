output "ct_id" {
  value = proxmox_virtual_environment_container.ct.vm_id
}

output "ct_address" {
  value = {
    v4 = [for k, v in proxmox_virtual_environment_container.ct.ipv4 : v]
    v6 = [for k, v in proxmox_virtual_environment_container.ct.ipv6 : v]
  }
}