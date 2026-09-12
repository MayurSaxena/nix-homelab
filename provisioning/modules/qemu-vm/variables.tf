variable "pve_node_name" {
  type        = string
  nullable    = false
  description = "The Proxmox node to build on."
  default     = "proxmox"
}

variable "vm_name" {
  type        = string
  nullable    = false
  description = "Guest hostname. Also what cloud-init sets inside the guest."
}

variable "vm_description" {
  type    = string
  default = "Managed by Terraform."
}

variable "template_vm_id" {
  type        = number
  nullable    = false
  description = <<-EOT
    VMID of the Packer-built template to clone. See packer/ for how these are made
    and provisioning/rbac.tf for the block of ids reserved for them.
  EOT
}

variable "os_type" {
  type        = string
  default     = "l26"
  description = <<-EOT
    Proxmox ostype. "win11" covers Windows 11 and Server 2022/2025; "l26" is any modern
    Linux. It is not cosmetic: Proxmox uses it to pick guest-appropriate device defaults
    and timer behaviour, and Windows guests keep worse time without it.
  EOT
}

variable "bios" {
  type        = string
  default     = "ovmf"
  description = "ovmf (UEFI) or seabios. Windows 11 and Server 2025 both require UEFI."
}

variable "machine" {
  type        = string
  default     = "q35"
  description = <<-EOT
    q35 is required for OVMF, and drops the legacy IDE controller in the process, which is
    why anything attaching an ISO to one of these guests must use SATA.
  EOT
}

variable "num_cpu_cores" {
  type    = number
  default = 2
}

variable "memory_size_mb" {
  type    = number
  default = 4096
}

variable "disk_size_gb" {
  type        = number
  default     = 64
  description = <<-EOT
    Must be at least the template's own disk size. Proxmox can grow a cloned disk but never
    shrink one, and a smaller value here fails the clone rather than being ignored.
  EOT
}

variable "vm_disk_datastore" {
  type    = string
  default = "local-zfs"
}

variable "network_interfaces" {
  type        = map(number)
  description = "Interface name to VLAN id, e.g. { eth0 = 90 }. Matches the nixos-lxc module."
}

variable "ipv4_settings" {
  type        = string
  description = <<-EOT
    Either "dhcp", or "<cidr>;<gateway>" for a static address, e.g.
    "10.0.90.10/24;10.0.90.1". The lab VLAN has no DHCP server, so lab guests must be
    static. Same encoding as the nixos-lxc module, deliberately.
  EOT
}

variable "dns_servers" {
  type    = list(string)
  default = ["10.0.10.2"]
}

variable "domain" {
  type    = string
  default = "lab.internal"
}

variable "ci_username" {
  type        = string
  default     = "Administrator"
  description = "Account cloud-init sets the password on. Administrator for Windows guests."
}

variable "ci_password" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Password cloud-init (cloudbase-init, on Windows) sets on first boot. This lands in
    provisioning/terraform.tfstate, which is gitignored and local-only; treat it as a
    bootstrap credential that Ansible replaces with key auth, not a lasting secret.
  EOT
}

variable "ci_public_keys" {
  type        = list(string)
  default     = []
  description = "SSH public keys to authorise, so Ansible never needs the password again."
}

variable "enable_agent" {
  type        = bool
  default     = true
  description = <<-EOT
    Requires the QEMU guest agent inside the guest. With this on and the agent missing,
    Proxmox reports no IP and waits the full timeout on every stop. The templates in
    packer/ install it.
  EOT
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "pool_id" {
  type    = string
  default = null
}

variable "startup_order" {
  type        = number
  default     = null
  description = "Set to also mark the guest as start-on-boot, matching the nixos-lxc module."
}

variable "enable_cloud_init" {
  type        = bool
  default     = true
  description = <<-EOT
    Attach a cloud-init drive. True for any template built by this repo's Packer
    configurations, which install cloudbase-init on Windows and use the distribution's own
    cloud-init on Linux.

    Set it false for an image that has no cloud-init agent, so that OpenTofu does not
    declare an address and an account the guest will never read. Such a guest needs its
    address from DHCP or from its Ansible role, and `ipv4_settings`, `ci_username`,
    `ci_password` and `ci_public_keys` are ignored.
  EOT
}
