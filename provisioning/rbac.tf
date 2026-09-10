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
    # Removing content from a datastore, NOT (as several guides imply, and as an earlier
    # revision of this file asserted) creating and destroying storage definitions -- that is
    # Datastore.AllocateSpace plus node-level rights. Packer generates the autounattend ISO,
    # uploads it, and deletes it again at the end of a build; without this the whole build
    # fails at cleanup with "403 Permission check failed (/storage/local, Datastore.Allocate)"
    # after everything else has already succeeded.
    "Datastore.Allocate",
    "SDN.Use", # attach a NIC to vmbr0
    "SDN.Audit",
    "Sys.Audit", # read-only node status
  ]
}

resource "proxmox_virtual_environment_user" "packer" {
  user_id = "packer@pve"
  comment = "Packer image builds (Terraform). Token auth only; no password is set."
  enabled = true

  # This resource can carry `acl` blocks, and declaring none here does not mean "leave them
  # alone" -- it means "there should be none", so every apply deletes the rows the acl
  # resources below just created. See the note above them.
  lifecycle {
    ignore_changes = [acl]
  }
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
# Packer builds each template at a fixed vm_id, so the guest-level grants name ids rather
# than the whole of /vms. They name a reserved *block* rather than the ids currently in use:
# PVE stores ACLs as plain strings and does not require the guest to exist, so reserving the
# block up front means adding a template later -- a Linux image, or the Windows 11 Enterprise
# build that Credential Guard work would need -- costs no permission change and no second
# apply against RBAC. Ten is far more templates than this node will plausibly carry, and is
# still nothing like granting /vms.
locals {
  packer_template_vmids = range(9100, 9110)

  # id => path. Keys are cosmetic, but keep tofu's plan output readable.
  packer_acl_paths = merge(
    { for id in local.packer_template_vmids : "template_${id}" => "/vms/${id}" },
    {
      iso_store  = "/storage/local"          # read the install ISOs, upload the generated autounattend ISO
      disk_store = "/storage/local-zfs"      # allocate the build VM's disks
      bridge     = "/sdn/zones/localnetwork" # SDN.Use on vmbr0; propagates to the bridge and its VLAN subpaths
      node       = "/nodes/proxmox"          # Sys.Audit only; everything else in the role is meaningless here
    }
  )
}

# NOTE: proxmox_virtual_environment_user manages ACLs too, via an `acl` block of its own.
#
# With no acl blocks declared on the user above, OpenTofu reads whatever ACLs exist at
# refresh into that resource's state and then plans to remove all of them, because the
# config says there should be none. The separate acl resources below immediately add them
# back. The two fight on every single apply, and the damage depends on which order they
# happen to run in: an apply that planned "10 to add, 3 to destroy" also removed four rows
# nothing had asked it to touch, leaving state claiming fourteen entries while PVE had ten.
#
# It is invisible in a plan unless you read the user resource's diff rather than the summary
# line -- it shows only as an innocuous-looking "1 to change" -- and the symptom is a
# permission failure much later, partway through a build.
#
# ignore_changes on that block is what stops it. The acl resources here are the single
# writer; the user resource is told to keep its hands off. Verify against PVE's own
# GET /access/permissions after any ACL change rather than trusting the apply's exit code,
# which reports success either way.

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
# resource's `value` attribute. That file is gitignored today, but it is a working copy on
# one Mac with no backup, and marking an attribute sensitive only suppresses CLI output,
# never storage. Keeping the credential out of it entirely means the question does not
# reopen if the state ever does get committed.
#
# So tofu owns the parts with no secret in them (the role, the user, the ACLs above) and the
# credential is minted out-of-band and kept in secrets/msaxena.yaml alongside the Proxmox
# password and TOTP seed. `just packer-token` does that, and rotating is the same command.
# Nothing else needs the token: the Windows VM modules authenticate with the root@pam ticket
# util/pve-auth.sh mints, exactly as the LXC modules already do.
