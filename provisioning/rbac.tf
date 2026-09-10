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

  # ACLs are declared here rather than as separate proxmox_virtual_environment_acl resources.
  #
  # This resource carries its own `acl` block, and the two models do not coexist: with acl
  # resources alongside it, OpenTofu reads the live ACLs into this resource at refresh, plans
  # to delete them all because the config declares none, and the two fight on every apply --
  # visible in a plan only as an innocuous "1 to change", and capable of removing rows nothing
  # asked it to touch. An earlier revision suppressed that with ignore_changes. Declaring the
  # grants here removes the conflict instead of hiding it, and puts the whole grant in one
  # readable place.
  #
  # Scoped to a pool rather than to guest ids. PVE deletes a guest's ACL entries when the
  # guest is destroyed, so a grant on /vms/<id> revokes itself the first time a build fails
  # and cleans up after itself -- the next build then 403s at "Creating VM". A pool is not a
  # guest and outlives the guests inside it, so one entry replaces a block of reserved ids and
  # there is nothing to reserve in advance or to keep in step with the templates.
  acl {
    path      = "/pool/${proxmox_virtual_environment_pool.lab.pool_id}"
    role_id   = proxmox_virtual_environment_role.packer_build.role_id
    propagate = true
  }

  acl {
    path      = "/storage/local" # read the install ISOs; upload and remove the generated autounattend ISO
    role_id   = proxmox_virtual_environment_role.packer_build.role_id
    propagate = true
  }

  acl {
    path      = "/storage/local-zfs" # allocate the build VM's disks
    role_id   = proxmox_virtual_environment_role.packer_build.role_id
    propagate = true
  }

  acl {
    path      = "/sdn/zones/localnetwork" # SDN.Use on vmbr0, propagating to the bridge and its VLANs
    role_id   = proxmox_virtual_environment_role.packer_build.role_id
    propagate = true
  }

  acl {
    path      = "/nodes/proxmox" # Sys.Audit only; the rest of the role is meaningless here
    role_id   = proxmox_virtual_environment_role.packer_build.role_id
    propagate = true
  }
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
