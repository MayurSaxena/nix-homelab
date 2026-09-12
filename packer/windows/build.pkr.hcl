# Golden Windows templates, one build configuration for every version.
#
# Build with `just packer-build <target>`, where <target> is a key of local.catalog below.
# The recipe decrypts the Proxmox token and the local administrator password from sops and
# exports them as PKR_VAR_*. Nothing here reads a credential from disk, and no credential is
# written to one.
#
# Adding a Windows version is a catalog entry and nothing else. That is the whole point of
# the shape: the parts that are genuinely per-version are four strings, and everything
# around them -- the UEFI/TPM machine, the VirtIO wiring, the boot-prompt handling, the SSH
# communicator, the provisioner chain -- was arrived at painfully and should be shared
# rather than copied into a second file and left to drift.

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "target" {
  type        = string
  description = "Which catalog entry to build. `just packer-build <target>` sets this."

  # Fails in a second, with the list, rather than on a raw map-lookup error. The list is
  # spelled out because a Packer validation block may not reference locals.
  validation {
    condition     = contains(["ws2025", "win11-pro"], var.target)
    error_message = "Target must be one of: ws2025, win11-pro."
  }
}

locals {
  # The per-version facts, and the only place any of them appear.
  #
  # image_name must match an edition inside that ISO's install.wim EXACTLY -- read it, do
  # not infer it from the product name, because evaluation, retail and volume media all
  # name their editions differently. Both values below were read off the real media.
  #
  #   dism /get-wiminfo /wimfile:D:\sources\install.wim      (from WinPE, shift+F10)
  #
  # virtio_dir is the directory for that Windows version inside virtio-win.iso; see the
  # comment on DriverPaths in autounattend.pkrtpl.xml for how to list what the ISO carries.
  #
  # product_key is empty for both and is expected to stay that way; see the UserData
  # comment in the answer file for when it would not be.
  catalog = {
    ws2025 = {
      iso         = "local:iso/windows-server-2025-eval.iso"
      image_name  = "Windows Server 2025 Standard Evaluation (Desktop Experience)"
      virtio_dir  = "2k25"
      product_key = ""
      description = "Windows Server 2025 Standard Eval, Desktop Experience."
      cores       = 4
      memory      = 4096
      disk_size   = "60G"
    }
    win11-pro = {
      iso         = "local:iso/windows-11-pro.iso"
      image_name  = "Windows 11 Pro"
      virtio_dir  = "w11"
      product_key = ""
      description = "Windows 11 Pro, unactivated. The workstation and FLARE-VM base."
      cores       = 4
      memory      = 4096
      disk_size   = "80G"
    }
  }

  t = local.catalog[var.target]

  # Every template is named and tagged after its catalog key, so OpenTofu finds it by tag
  # (see provisioning/vms.tf) and the build recipe knows which older template to retire.
  # PVE joins tags with semicolons.
  template_name = "tpl-${var.target}"
  tags          = "template;${var.target}"
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
    Autologon password for the build VM, and nothing else. FirstLogonCommands only run if
    someone logs in, so the unattend needs one; Packer itself authenticates by key. Sysprep
    generalises it away, so it never reaches a clone.
  EOT
}

variable "ansible_private_key_file" {
  type        = string
  description = <<-EOT
    Path to the Ansible private key, materialised by `just packer-build` for the length of
    the run. A file rather than the key itself because ssh takes a key from neither stdin
    nor the environment.
  EOT
}

variable "ansible_public_key" {
  type        = string
  description = <<-EOT
    Baked into the template's administrators_authorized_keys, so a clone is reachable by key
    with no bootstrap credential at all. Not secret; it is the public half.
  EOT
}

# The build's own address, fixed rather than leased.
#
# Discovery through the guest agent was tried and does not work here: the agent reports the
# DHCP lease correctly and SSH is open on it, but the Proxmox plugin never resolves an
# address and waits out its whole timeout. A fixed address is the reliable option, and its
# one real hazard -- a clone inheriting it, so Packer connects to the clone instead of the
# VM it just made -- is checked for by `just packer-build` before a build starts.
#
# It also means two builds cannot run at once. That is a real limit and it is accepted:
# the check turns it into an immediate, explained refusal rather than a corrupt image.
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

source "proxmox-iso" "windows" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = true
  node                     = var.node

  # No vm_id: PVE allocates the next free one. Nothing needs a fixed id any more.
  #
  # The grant is on the lab pool rather than on a block of reserved ids (see
  # provisioning/rbac.tf), and OpenTofu finds this template by tag rather than by number
  # (see provisioning/vms.tf). Fixing an id bought nothing and cost the old build recipe a
  # delete-before-build step, which is what left the node with no template at all whenever a
  # build failed after it.
  vm_name              = local.template_name
  template_name        = local.template_name
  template_description = "${local.t.description} Built by Packer; do not edit in place."
  tags                 = local.tags

  pool = "lab"

  # Windows 11 and Server 2025 both expect UEFI plus a TPM. q35 rather than i440fx because
  # OVMF wants a PCIe machine type. Both also pass Windows 11's hardware check on these
  # settings, so no setup bypass is needed for the client editions.
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
  cores    = local.t.cores
  memory   = local.t.memory

  # win11 is PVE's newest Windows ostype and is correct for Server 2025 as well. It is
  # also what makes Proxmox generate a configdrive2 cloud-init drive carrying the
  # administrator password, which is how a clone gets a password we know. Changing it to
  # an older type silently breaks that; see LAB.md.
  os = "win11"

  scsi_controller = "virtio-scsi-single"
  disks {
    disk_size    = local.t.disk_size
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
    iso_file = local.t.iso
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
      # The unattend copies this to administrators_authorized_keys at first logon. It rides
      # on the same generated CD so nothing has to be fetched over a network that does not
      # exist yet, and it is a public key, so the CD carries no secret.
      "authorized_keys" = "${var.ansible_public_key}\n"

      "autounattend.xml" = templatefile("autounattend.pkrtpl.xml", {
        image_name     = local.t.image_name
        virtio_dir     = local.t.virtio_dir
        product_key    = local.t.product_key
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
  # prints "no bootable media found", and then sits there until the communicator timeout
  # expires -- ninety minutes of nothing, reported as a connection failure rather than as a
  # boot failure. Observed exactly that on the first run.
  #
  # So hold the key down instead of tapping it: press Enter once a second for twenty
  # seconds, which covers the whole window wherever it lands. Extra presses after setup has
  # started are harmless, because the autounattend answers every screen they could hit.
  boot_wait    = "2s"
  boot_command = ["<enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter>"]

  # SSH, not WinRM, and the same transport Ansible uses afterwards. The unattend installs
  # OpenSSH and the Ansible key at first logon, so Packer authenticates by key from the
  # start: no password crosses the wire, and the image carries one remote-management stack
  # instead of two. WinRM's four unattend commands and its basic-auth-over-unencrypted-HTTP
  # configuration are gone with it.
  communicator         = "ssh"
  ssh_username         = "Administrator"
  ssh_host             = var.build_ip
  ssh_private_key_file = var.ansible_private_key_file
  # Covers the whole unattended install, not just a reboot.
  ssh_timeout = "45m"
}

build {
  name    = var.target
  sources = ["source.proxmox-iso.windows"]

  provisioner "powershell" {
    environment_vars = ["ANSIBLE_PUBLIC_KEY=${var.ansible_public_key}"]
    scripts = [
      "${path.root}/../common/scripts/install-guest-tools.ps1",
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
