# Identities OpenTofu manages for tooling that cannot use the root@pam ticket that
# util/pve-auth.sh mints. Kept out of main.tf, which stays LXC-only.
#
# Packer authenticates with an API token and nothing else: it has no way to consume a
# pre-fetched auth ticket. That is fine here, unlike the container hookscript case that
# forces root@pam elsewhere in this directory, because nothing Packer does is one of the
# operations PVE hard-codes to the root@pam identity.

resource "proxmox_virtual_environment_role" "packer_build" {
  role_id = "PackerBuild"

  # Verified against this node's own PVE 9.1.7 privilege list rather than copied from a
  # guide: VM.Monitor appears in most published Packer role recipes but no longer exists
  # in PVE 9, and including it makes role creation fail outright.
  #
  # Also deliberately absent, though widely recommended: Sys.Modify (node and network
  # config), and Datastore.Allocate, which creates and destroys storage *definitions* —
  # uploading an ISO needs only Datastore.AllocateTemplate.
  privileges = [
    "VM.Allocate",     # create the build VM
    "VM.Audit",        # read its config back
    "VM.Clone",        # unused by proxmox-iso; needed only if a proxmox-clone build is added
    "VM.Config.CDROM", # install ISO, virtio-win ISO, and the generated autounattend CD
    "VM.Config.CPU",
    "VM.Config.Cloudinit",
    "VM.Config.Disk",   # covers the EFI disk and TPM state that Windows 11 refuses to install without
    "VM.Config.HWType", # q35 machine type, OVMF BIOS
    "VM.Config.Memory",
    "VM.Config.Network",
    "VM.Config.Options",
    "VM.Console", # Packer answers "press any key to boot from CD" over VNC
    "VM.PowerMgmt",
    "Datastore.Audit",            # locate the ISOs on local
    "Datastore.AllocateSpace",    # the build VM's disks on local-zfs
    "Datastore.AllocateTemplate", # upload the unattend ISO, and convert the finished VM to a template
    "SDN.Use",                    # attach a NIC to vmbr0
    "SDN.Audit",
    "Sys.Audit", # read-only node status
  ]
}

resource "proxmox_virtual_environment_user" "packer" {
  user_id = "packer@pve"
  comment = "Packer image builds (Terraform). Token auth only; no password is set."
  enabled = true
}

# Scoped deliberately, NOT granted at "/".
#
# An earlier version of this file granted PackerBuild on "/" with propagate, matching the
# existing opentofu@pve entry. An audit against PVE's own effective-permission computation
# (GET /access/permissions) showed why that was wrong: at "/" the token holds VM.Allocate,
# VM.Config.*, VM.PowerMgmt and VM.Console on *every* existing guest. VM.Allocate covers
# destroy and VM.Console is an interactive console, so a build-tool token could have
# deleted or logged into caddy, dns or plex. The role blocks privilege escalation; it does
# nothing to limit blast radius across guests. Only the ACL path can do that.
#
# Packer builds each template at a fixed vm_id, so the guest-level grants name those three
# ids exactly. PVE stores ACLs as plain strings and does not require the guest to exist, so
# these can be granted before the first build creates them.
locals {
  # id => path. Keys are cosmetic, but keep tofu's plan output readable.
  packer_acl_paths = {
    tpl_ws2025    = "/vms/9100"               # Server 2025 template build VM
    tpl_win11_ent = "/vms/9101"               # Windows 11 Enterprise template build VM
    tpl_win11_pro = "/vms/9102"               # Windows 11 Pro template build VM
    iso_store     = "/storage/local"          # read the install ISOs, upload the generated autounattend ISO
    disk_store    = "/storage/local-zfs"      # allocate the build VM's disks
    bridge        = "/sdn/zones/localnetwork" # SDN.Use on vmbr0; propagates to the bridge and its VLAN subpaths
    node          = "/nodes/proxmox"          # Sys.Audit only; everything else in the role is meaningless here
  }
}

# One entry per path. The role is a superset at every path: granting VM.Config.CPU on
# /storage/local is inert, and splitting the role into per-path subsets would trade real
# clarity for no additional restriction.
resource "proxmox_virtual_environment_acl" "packer" {
  for_each = local.packer_acl_paths

  user_id   = proxmox_virtual_environment_user.packer.user_id
  role_id   = proxmox_virtual_environment_role.packer_build.role_id
  path      = each.value
  propagate = true
}

# The API token is deliberately NOT declared here.
#
# OpenTofu would store its secret in provisioning/terraform.tfstate as a plain string on the
# resource's `value` attribute, and that file is committed to this public repository. State
# encryption makes that ciphertext rather than cleartext, but it would still be the only
# credential in the repo not protected by the age/YubiKey path every other secret uses, and
# marking an attribute sensitive only suppresses CLI output, never storage.
#
# So tofu owns the parts with no secret in them (the role, the user, the ACLs above) and the
# credential is minted out-of-band and kept in secrets/msaxena.yaml alongside the Proxmox
# password and TOTP seed. `just packer-token` does that, and rotating is the same command.
# Nothing else needs the token: the Windows VM modules authenticate with the root@pam ticket
# util/pve-auth.sh mints, exactly as the LXC modules already do.
