variable "pve_node_name" {
  type        = string
  nullable    = false
  description = "The name of the storage where VM/CT data volumes are stored."
  default     = "proxmox"
}
