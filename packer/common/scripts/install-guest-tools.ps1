# The VirtIO guest tools: every VirtIO driver plus the QEMU guest agent.
#
# Deliberately the full virtio-win-gt-x64.msi rather than the standalone qemu-ga MSI. The
# guest agent does not talk to the host over the network; it uses a VirtIO serial port, whose
# driver (vioserial) the standalone agent package does not ship. Install only the agent and
# the service starts, reports healthy, and is invisible to Proxmox forever -- `qm agent ping`
# times out, the VM shows no IP address, and OpenTofu waits out its whole timeout on every
# create. Observed exactly that on the first template.
$ErrorActionPreference = 'Stop'

# Two packages, not one, and the distinction cost a whole build to find.
#
#   virtio-win-gt-x64.msi   every VirtIO driver, including vioserial
#   guest-agent\qemu-ga-x86_64.msi   the QEMU-GA service itself
#
# The guest tools package installs the driver the agent needs but not the agent, and the
# standalone agent package installs the agent but not the driver. Install either alone and
# Proxmox never sees the guest: with only the agent, the service runs with no channel to the
# host; with only the tools, `Get-Service QEMU-GA` reports that no such service exists.
$ErrorActionPreference = 'Stop'

# The virtio-win ISO's drive letter is assigned at boot and is not predictable, so find the
# volume by looking for the installers rather than assuming D: or E:.
function Find-OnAnyDrive([string]$relative) {
    Get-PSDrive -PSProvider FileSystem |
        ForEach-Object { Join-Path $_.Root $relative } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
}

foreach ($pkg in 'virtio-win-gt-x64.msi', 'guest-agent\qemu-ga-x86_64.msi') {
    $msi = Find-OnAnyDrive $pkg
    if (-not $msi) {
        throw "$pkg not found on any drive. Is the virtio-win ISO still attached? Packer unmounts it only after provisioning."
    }
    Write-Host "Installing $msi"
    $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart' -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -notin @(0, 3010)) { throw "msiexec exited $($p.ExitCode) for $pkg" }
}

foreach ($svc in 'QEMU-GA', 'BalloonService') {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        Set-Service -Name $svc -StartupType Automatic
        Start-Service -Name $svc -ErrorAction SilentlyContinue
        Write-Host "$svc : $((Get-Service $svc).Status)"
    }
}

# Prove the serial channel exists rather than assuming it. Without vioserial this device is
# absent and the agent is mute, which is the failure this script exists to prevent.
$vs = Get-PnpDevice -Class System -ErrorAction SilentlyContinue |
      Where-Object { $_.FriendlyName -match 'VirtIO Serial' }
if (-not $vs) { throw "No VirtIO Serial device present: the guest agent would have no channel to the host." }
Write-Host "VirtIO Serial: $($vs.Status)"

# And the service, which is the half the guest tools package does not provide. Asserting only
# the device is what let a template ship with drivers and no agent.
$ga = Get-Service QEMU-GA -ErrorAction SilentlyContinue
if (-not $ga) { throw "QEMU-GA service is absent: virtio-win-gt-x64.msi installs the driver but not the agent." }
Write-Host "QEMU-GA: $($ga.Status)"
