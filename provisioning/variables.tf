variable "lab_admin_password" {
  type        = string
  nullable    = false
  sensitive   = true
  description = <<-EOT
    Local Administrator password cloud-init sets on each lab guest at first boot, so
    Ansible has something to authenticate with before it installs its key. Exported as
    TF_VAR_lab_admin_password by the justfile's plan/apply recipes, which decrypt it from
    clone-admin-password in secrets/lab.yaml.

    Distinct from the Packer build password: that one is generalised away by sysprep and
    never reaches a running guest.
  EOT
}

variable "pve_node_name" {
  type        = string
  nullable    = false
  description = "The name of the storage where VM/CT data volumes are stored."
  default     = "proxmox"
}
