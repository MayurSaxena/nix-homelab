# Windows Server 2025 golden template.
#
# Build with `just packer-build ws2025`, which decrypts the Proxmox token and the local
# administrator password from sops and exports them as PKR_VAR_*. Nothing here reads a
# credential from disk, and no credential is written to one.

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type    = string
  default = "https://10.0.10.3:8006/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "Token id, e.g. packer@pve!packerbuild. From proxmox/packer-token-id."
}

variable "proxmox_token" {
  type      = string
  sensitive = true
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Local Administrator password for the build only. Sysprep generalises it away and
    cloudbase-init sets a per-clone password on first boot, so this never reaches a
    running range VM.
  EOT
}

variable "node" {
  type    = string
  default = "proxmox"
}

variable "install_updates" {
  type        = bool
  default     = false
  description = <<-EOT
    Run Windows Update during the build. Adds anywhere from twenty minutes to over an
    hour and several reboots, so it defaults off while iterating on the template itself.
    Turn it on for a template you intend to keep.
  EOT
}

source "proxmox-iso" "ws2025" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = true
  node                     = var.node

  # Fixed, because provisioning/rbac.tf grants packer@pve on a reserved block of template
  # VMIDs rather than on /vms. A VMID outside 9100-9109 will fail with a permission error.
  vm_id                = 9100
  vm_name              = "tpl-ws2025"
  template_name        = "tpl-ws2025"
  template_description = "Windows Server 2025 Standard Eval, Desktop Experience. Built by Packer; do not edit in place."

  # Windows 11 and Server 2025 both expect UEFI plus a TPM. q35 rather than i440fx because
  # OVMF wants a PCIe machine type.
  machine = "q35"
  bios    = "ovmf"
  efi_config {
    efi_storage_pool  = "local-zfs"
    efi_type          = "4m"
    pre_enrolled_keys = true
  }
  tpm_config {
    tpm_storage_pool = "local-zfs"
    tpm_version      = "v2.0"
  }

  cpu_type = "host"
  cores    = 4
  memory   = 4096
  os       = "win11"

  scsi_controller = "virtio-scsi-single"
  disks {
    disk_size    = "60G"
    storage_pool = "local-zfs"
    type         = "scsi"
    format       = "raw"
    cache_mode   = "writeback"
    io_thread    = true
  }

  network_adapters {
    bridge   = "vmbr0"
    model    = "virtio"
    vlan_tag = "90"
  }

  # SATA rather than IDE for every attached ISO: q35 drops the legacy IDE controller, so an
  # ide-typed drive here is silently absent inside setup.
  boot_iso {
    type     = "sata"
    iso_file = "local:iso/windows-server-2025-eval.iso"
    unmount  = true
  }

  additional_iso_files {
    type     = "sata"
    index    = 1
    iso_file = "local:iso/virtio-win.iso"
    unmount  = true
  }

  # Generated rather than committed, so the administrator password is only ever in memory
  # and in sops. Setup looks for autounattend.xml in the root of every removable volume.
  additional_iso_files {
    type             = "sata"
    index            = 2
    cd_label         = "unattend"
    iso_storage_pool = "local"
    unmount          = true
    cd_content = {
      "autounattend.xml" = templatefile("${path.root}/autounattend.xml", {
        admin_password = var.admin_password
      })
    }
  }

  qemu_agent = true

  # Answering the "press any key to boot from CD or DVD" prompt. Miss this window and the
  # VM falls through to the empty disk and sits at a UEFI shell until the build times out.
  boot_wait    = "3s"
  boot_command = ["<enter>"]

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  # Generous: this covers the whole unattended install, not just a reboot.
  winrm_timeout = "90m"
}

build {
  name    = "ws2025"
  sources = ["source.proxmox-iso.ws2025"]

  provisioner "powershell" {
    scripts = [
      "${path.root}/../common/scripts/install-qemu-guest-agent.ps1",
      "${path.root}/../common/scripts/install-openssh.ps1",
      "${path.root}/../common/scripts/install-cloudbase-init.ps1",
    ]
  }

  # The script decides whether to do anything, rather than the block being conditional:
  # Packer rejects a provisioner whose `scripts` list evaluates to empty.
  provisioner "powershell" {
    environment_vars = ["INSTALL_UPDATES=${var.install_updates}"]
    # Reboots between update passes are expected; Packer reconnects on its own.
    scripts = ["${path.root}/../common/scripts/windows-update.ps1"]
  }

  provisioner "powershell" {
    scripts = ["${path.root}/../common/scripts/sysprep.ps1"]
    # sysprep shuts the VM down, which looks like a dropped connection to Packer.
    valid_exit_codes = [0, 2, 259]
  }
}
