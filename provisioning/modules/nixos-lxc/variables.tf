variable "pve_node_name" {
  type        = string
  nullable    = false
  description = "The name of the PVE node to create the container on."
}

variable "ct_description" {
  type        = string
  nullable    = false
  description = "Brief description of the container."
  default     = "Managed by Terraform."
}

variable "rootfs_size_gb" {
  type        = number
  nullable    = false
  description = "The size of the root filesystem in GB."
  default     = 2
}

variable "hostname" {
  type        = string
  nullable    = false
  description = "Hostname of the container."
}

variable "domain" {
  type        = string
  nullable    = false
  description = "Domain of the container."
}

variable "dns_servers" {
  type        = list(string)
  nullable    = false
  description = "DNS servers to utilise."
  default     = ["2403:5816:df19:1::2", "10.0.10.2"]
}

variable "ipv4_settings" {
  type        = string
  nullable    = false
  description = "String of form 'dhcp' or 'A.B.C.D/E;F.G.H.I"
}

variable "ipv6_settings" {
  type        = string
  nullable    = false
  description = "String of form 'auto', 'dhcp' or 'IPv6/CIDR;IPv6"
}

variable "memory_size_mb" {
  type        = number
  nullable    = false
  description = "The amount of RAM in MB."
}

variable "num_cpu_cores" {
  type        = number
  nullable    = false
  description = "The number of CPU cores to assign."
}

variable "swap_size_mb" {
  type        = number
  nullable    = false
  description = "The amount of swap in MB."
  default     = 512
}

variable "persistent_fs_size_gb" {
  type        = number
  nullable    = false
  description = "The size of the persistent filesystem in GB."
  default     = 2
}

variable "nix_fs_size_gb" {
  type        = number
  nullable    = false
  description = "The size of the Nix store filesystem in GB."
  default     = 4
}

variable "additional_mount_points" {
  type = list(object({
    vol     = string,
    ct_path = string,
    size    = optional(string, null)
    backup  = optional(bool, false)
  }))
  nullable    = false
  description = "Additional mount points within CT."
  default     = []
}

variable "network_interfaces" {
  type        = map(number)
  nullable    = false
  description = "A map of the form {IF_NAME: VLAN_ID}"
}

variable "ct_template_id" {
  type        = string
  nullable    = false
  description = "The ID of the CT image to use."
}

variable "rootfs_impermanence" {
  type        = bool
  nullable    = false
  description = "Whether the container's root filesystem should be impermanent."
  default     = false
}

variable "pool_id" {
  type        = string
  nullable    = true
  description = "Pool to assign the CT to."
  default     = null
}

variable "startup_order" {
  type        = number
  nullable    = true
  description = "Non-negative number defining startup order of CT."
  default     = null
}

variable "tags" {
  type        = list(string)
  nullable    = false
  description = "Tags to assign to this CT."
  default     = []
}

variable "custom_hookscript" {
  type        = string
  nullable    = true
  description = "File identifier for executable hook script."
  default     = null
}

variable "ct_disk_datastore" {
  type        = string
  nullable    = false
  description = "Name of the datastore to store the CT disks in."
  default     = "local-zfs"
}