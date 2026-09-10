# The guest agent is what lets Proxmox report a VM's IP and shut it down cleanly, and what
# `qm agent <id> ping` answers. OpenTofu's windows-vm module sets agent=1, and without this
# installed the VM shows as running with no address forever.
$ErrorActionPreference = 'Stop'

# The virtio-win ISO's drive letter is assigned at boot and is not predictable, so find the
# volume by looking for the installer rather than assuming D: or E:.
$msi = Get-PSDrive -PSProvider FileSystem |
    ForEach-Object { Join-Path $_.Root 'guest-agent\qemu-ga-x86_64.msi' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $msi) {
    throw "qemu-ga-x86_64.msi not found on any drive. Is the virtio-win ISO still attached? Packer unmounts it only after provisioning."
}

Write-Host "Installing QEMU guest agent from $msi"
$p = Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart' -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { throw "msiexec exited $($p.ExitCode)" }

Set-Service -Name QEMU-GA -StartupType Automatic
Start-Service -Name QEMU-GA
Write-Host "QEMU guest agent: $((Get-Service QEMU-GA).Status)"
