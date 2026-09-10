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

# The lab VLAN deliberately has no DHCP server: range VMs get static addresses from
# OpenTofu, and leaving DHCP free means the lab domain controller can serve it later without
# a fight. A template build therefore has to bring its own address. .99 is reserved for that
# and sits outside every block LAB.md allocates to real machines, so two builds
# would collide with each other but never with a range VM.
variable "build_ip" {
  type    = string
  default = "10.0.90.99"
}

variable "build_prefix" {
  type    = number
  default = 24
}

variable "build_gateway" {
  type    = string
  default = "10.0.90.1"
}

variable "build_dns" {
  type        = string
  default     = "10.0.10.2"
  description = "technitium, so the build can resolve cloudbase.it to fetch cloudbase-init."
}

variable "ansible_public_key" {
  type        = string
  description = <<-EOT
    Baked into the template's administrators_authorized_keys, so a clone is reachable by key
    with no bootstrap credential at all. Not secret; it is the public half.
  EOT
}

variable "clone_password" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Administrator password baked into the template, so every clone boots with a known
    credential Ansible can bootstrap over. It cannot come from cloud-init: Proxmox writes
    the password into user-data as Linux cloud-config, while cloudbase-init reads
    admin_pass from meta-data, which Proxmox leaves empty. See sysprep.ps1.

    Ansible replaces it with key authentication on first run.
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
  vm_id   = 9100
  vm_name = "tpl-ws2025"

  # Not cosmetic. PVE deletes a guest's ACL entries when the guest is destroyed, so the
  # grant on /vms/9100 disappears every time a build fails and cleans up after itself, and
  # the next run 403s at "Creating VM". Building into a pool that packer@pve is granted on
  # gives the permission somewhere to live that outlives the VM. See provisioning/rbac.tf.
  pool = "lab"

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
        build_ip       = var.build_ip
        build_prefix   = var.build_prefix
        build_gateway  = var.build_gateway
        build_dns      = var.build_dns
      })
    }
  }

  qemu_agent = true

  # Answering the "Press any key to boot from CD or DVD" prompt.
  #
  # A single keystroke after a fixed wait does not work: the prompt appears somewhere
  # between two and eight seconds after power-on depending on how long OVMF takes, and it
  # only stays up for about five. Miss it and the VM falls through to the empty disk,
  # prints "no bootable media found", and then sits there until the WinRM timeout expires
  # -- ninety minutes of nothing, reported as a communicator failure rather than as a boot
  # failure. Observed exactly that on the first run.
  #
  # So hold the key down instead of tapping it: press Enter once a second for twenty
  # seconds, which covers the whole window wherever it lands. Extra presses after setup has
  # started are harmless, because the autounattend answers every screen they could hit.
  boot_wait    = "2s"
  boot_command = ["<enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter>"]

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  # The address is known, so do not depend on guest-agent discovery to find it. The agent is
  # still installed early by the unattend, because the builder waits on it regardless.
  winrm_host = var.build_ip
  # Generous: this covers the whole unattended install, not just a reboot.
  # Setup plus FirstLogonCommands runs in about twenty-five minutes. Forty-five leaves room
  # for a slow Windows Update pass without turning every failed run into a ninety-minute
  # wait before the log says anything useful.
  winrm_timeout = "45m"
}

build {
  name    = "ws2025"
  sources = ["source.proxmox-iso.ws2025"]

  provisioner "powershell" {
    environment_vars = ["ANSIBLE_PUBLIC_KEY=${var.ansible_public_key}"]
    scripts = [
      "${path.root}/../common/scripts/install-guest-tools.ps1",
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
    environment_vars = ["CLONE_PASSWORD=${var.clone_password}"]
    scripts          = ["${path.root}/../common/scripts/sysprep.ps1"]
    # sysprep shuts the VM down, which looks like a dropped connection to Packer.
    valid_exit_codes = [0, 2, 259]
  }
}
