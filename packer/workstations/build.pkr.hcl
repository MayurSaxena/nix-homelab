# Derived tool images. Keep the base OS installation separate from tool updates.
packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.4"
      source  = "github.com/hashicorp/proxmox"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "target" {
  type = string
  validation {
    condition     = contains(["ctf", "flare"], var.target)
    error_message = "Target must be ctf or flare."
  }
}
variable "base_template_id" {
  type = number
}
variable "proxmox_url" {
  type    = string
  default = "https://10.0.10.3:8006/api2/json"
}
variable "proxmox_username" { type = string }
variable "proxmox_token" {
  type      = string
  sensitive = true
}
variable "ansible_private_key_file" { type = string }
variable "node" {
  type    = string
  default = "proxmox"
}

source "proxmox-clone" "workstation" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = true
  node                     = var.node
  pool                     = "lab"
  clone_vm_id              = var.base_template_id
  full_clone               = true
  vm_name                  = "tpl-${var.target}"
  template_name            = "tpl-${var.target}"
  template_description     = "Windows 11 ${var.target} tool image; managed by Packer and Ansible"
  tags                     = "template;${var.target}"
  task_timeout             = "10m"
  os                       = "win11"
  bios                     = "ovmf"
  machine                  = "q35"
  cores                    = 4
  memory                   = 8192
  cpu_type                 = "host"
  qemu_agent               = true
  scsi_controller          = "virtio-scsi-single"
  boot                     = "order=scsi0"
  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    vlan_tag = "90"
  }
  # Do not specify disks/EFI/TPM: those are inherited from the source template.
  # The bare clone gets DHCP; leaving vm_interface unset selects IPv4.
  # With vm_interface set, Proxmox plugin 1.2.4 returns the first address (often IPv6).
  cloud_init           = false
  ssh_username         = "Administrator"
  ssh_private_key_file = var.ansible_private_key_file
  ssh_timeout          = "30m"
}

build {
  sources = ["source.proxmox-clone.workstation"]
  provisioner "ansible" {
    playbook_file    = "${path.root}/../../ansible/playbooks/tool-image.yml"
    user             = "Administrator"
    use_proxy        = false
    host_alias       = "tool-image"
    groups           = ["windows"]
    extra_arguments  = ["--extra-vars", "tool_image=${var.target}", "--extra-vars", "ansible_shell_type=powershell"]
    ansible_env_vars = ["ANSIBLE_CONFIG=${abspath("${path.root}/../../ansible/ansible.cfg")}"]
  }
  provisioner "file" {
    source      = "${path.root}/../common/scripts/finalize-network.ps1"
    destination = "C:/Windows/Temp/packer-finalize-network.ps1"
  }
  provisioner "powershell" {
    environment_vars    = ["TOOL_IMAGE=${var.target}"]
    scripts             = ["${path.root}/../common/scripts/wait-tool-image.ps1"]
    timeout             = "130m"
    start_retry_timeout = "10m"
    max_retries         = var.target == "flare" ? 12 : 0
  }
  provisioner "powershell" {
    scripts          = ["${path.root}/../common/scripts/sysprep.ps1"]
    timeout          = "20m"
    valid_exit_codes = [0]
    skip_clean       = true
  }
  provisioner "shell-local" {
    inline = ["bash '${path.root}/../common/scripts/wait-for-shutdown.sh' '${var.proxmox_url}' '${var.node}' 'tpl-${var.target}'"]
  }
}
