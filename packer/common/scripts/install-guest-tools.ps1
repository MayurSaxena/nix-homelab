# The VirtIO guest tools: every VirtIO driver plus the QEMU guest agent.
#
# Deliberately the full virtio-win-gt-x64.msi rather than the standalone qemu-ga MSI. The
# guest agent does not talk to the host over the network; it uses a VirtIO serial port, whose
# driver (vioserial) the standalone agent package does not ship. Install only the agent and
# the service starts, reports healthy, and is invisible to Proxmox forever -- `qm agent ping`
# times out, the VM shows no IP address, and OpenTofu waits out its whole timeout on every
# create. Observed exactly that on the first template.
$ErrorActionPreference = 'Stop'

# The VirtIO guest tools: every driver plus the QEMU guest agent, from one installer.
#
# virtio-win-guest-tools.exe rather than the two MSIs it wraps, and the distinction matters
# because getting it wrong is invisible. virtio-win-gt-x64.msi ships the vioserial driver the
# guest agent needs but not the agent itself; guest-agent\qemu-ga-x86_64.msi ships the agent
# but not the driver. Install either alone and Proxmox never sees the guest -- with only the
# agent, a service with no channel to the host; with only the drivers, no QEMU-GA service at
# all. Both of those shipped in a template before this script asserted its way out of it.
$ErrorActionPreference = 'Stop'

# The virtio-win ISO's drive letter is assigned at boot and is not predictable, so find the
# volume by looking for the installer rather than assuming D: or E:.
$exe = Get-PSDrive -PSProvider FileSystem |
    ForEach-Object { Join-Path $_.Root 'virtio-win-guest-tools.exe' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $exe) {
    throw "virtio-win-guest-tools.exe not found on any drive. Is the virtio-win ISO still attached? Packer unmounts it only after provisioning."
}

Write-Host "Installing VirtIO guest tools from $exe"
$p = Start-Process $exe -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru -NoNewWindow
if ($p.ExitCode -notin @(0, 3010)) { throw "guest tools installer exited $($p.ExitCode)" }

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
