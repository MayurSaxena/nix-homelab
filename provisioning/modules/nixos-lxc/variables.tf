variable "pve_node_name" {
  type        = string
  nullable    = false
  description = "The name of the PVE node to create the container on."
}

variable "num_cpu_cores" {
  type        = number
  nullable    = false
  description = "The number of CPU cores to assign."
  default     = 2
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
  description = "The size of the impermanent root filesystem in GB."
  default     = 2
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
  default     = ["2403:5816:961a:1::2", "10.0.10.2"]
}

variable "hostname" {
  type        = string
  nullable    = false
  description = "Hostname of the container."
}

variable "ipv4_settings" {
  type        = string
  nullable    = false
  description = "String of form 'dhcp' or 'A.B.C.D/E;F.G.H.I"
  default     = "dhcp"
}

variable "ipv6_settings" {
  type        = string
  nullable    = false
  description = "String of form 'auto', 'dhcp' or 'IPv6/CIDR;IPv6"
  default     = "auto"
}

variable "memory_size_mb" {
  type        = number
  nullable    = false
  description = "The amount of RAM in MB."
  default     = 2048
}

variable "swap_size_mb" {
  type        = number
  nullable    = false
  description = "The amount of swap in MB."
  default     = 256
}

variable "persistent_fs_size_gb" {
  type        = number
  nullable    = false
  description = "The size of the persistent filesystem in GB."
  default     = 4
}

variable "additional_mount_points" {
  type = list(object({
    vol     = string,
    ct_path = string,
    size    = string
    backup  = bool
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