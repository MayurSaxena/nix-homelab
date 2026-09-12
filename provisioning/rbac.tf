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
    # Removing content from a datastore, NOT (as several guides imply) creating and destroying
    # storage definitions. Packer generates the autounattend ISO, uploads it, and deletes it
    # again at the end of a build; without this the build fails at cleanup with "403 Permission
    # check failed (/storage/local, Datastore.Allocate)" after everything else has succeeded.
    "Datastore.Allocate",
    "SDN.Use", # attach a NIC to vmbr0
    "SDN.Audit",
    "Sys.Audit", # read-only node status
  ]
}

# Packer builds into this pool, and OpenTofu puts lab guests in it, which also makes a range
# wipe a pool filter rather than a list of names to remember.
resource "proxmox_virtual_environment_pool" "lab" {
  pool_id = "lab"
  comment = "Lab guests on VLAN 90, and the templates they are cloned from."
}

resource "proxmox_virtual_environment_user" "packer" {
  user_id = "packer@pve"
  comment = "Packer image builds (Terraform). Token auth only; no password is set."
  enabled = true

  # No acl blocks here: the grants are proxmox_acl resources below.
  #
  # They were declared inline for a while, because on provider 0.98.1 the two models could
  # not coexist -- refresh read the live ACLs into this resource, saw a config declaring
  # none, and planned to delete them all, which showed up in a plan only as an innocuous
  # "1 to change". Provider 0.107.0 fixed that by no longer populating this block from the
  # cluster, and deprecated it in the same release, so the inline form is now the
  # deprecated half of a problem that no longer exists.
}

# The grants, one resource per path.
#
# Scoped to a pool rather than to guest ids. PVE deletes a guest's ACL entries when the
# guest is destroyed, so a grant on /vms/<id> revokes itself the first time a build fails
# and cleans up after itself, and the next build then 403s at "Creating VM". A pool is not
# a guest and outlives the guests inside it, so one entry replaces a block of reserved ids
# with nothing to reserve in advance or keep in step with the templates.
#
# The token is created with privilege separation off, so it inherits these rather than
# needing its own copies.
#
# After changing anything here, check PVE's own answer rather than the apply's exit code:
#
#   GET /access/permissions?userid=packer@pve!packerbuild
#
# That endpoint returns the privileges PVE actually computes for the token, and it is the
# only thing that has reliably told the truth about whether a grant landed.
resource "proxmox_acl" "packer" {
  for_each = {
    # Create, configure and destroy the build VM, and the template it becomes.
    "/pool/${proxmox_virtual_environment_pool.lab.pool_id}" = true
    # Read the install ISOs; upload and remove the generated autounattend ISO.
    "/storage/local" = true
    # Allocate the build VM's disks, EFI vars and TPM state.
    "/storage/local-zfs" = true
    # SDN.Use on vmbr0, propagating to the bridge and its VLANs.
    "/sdn/zones/localnetwork" = true
    # Sys.Audit only; the rest of the role means nothing at this path.
    "/nodes/proxmox" = true
  }

  path      = each.key
  user_id   = proxmox_virtual_environment_user.packer.user_id
  role_id   = proxmox_virtual_environment_role.packer_build.role_id
  propagate = each.value
}

# The API token is deliberately NOT declared here.
#
# OpenTofu would store its secret in provisioning/terraform.tfstate as a plain string on the
# resource's `value` attribute. That file is gitignored today, but it is a working copy on
# one Mac with no backup, and marking an attribute sensitive only suppresses CLI output,
# never storage. Keeping the credential out of it entirely means the question does not
# reopen if the state ever does get committed.
#
# `just packer-token` mints and rotates it into secrets/msaxena.yaml instead, alongside the
# Proxmox password and TOTP seed.
