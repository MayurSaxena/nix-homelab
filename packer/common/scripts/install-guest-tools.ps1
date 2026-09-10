# The VirtIO guest tools: every VirtIO driver plus the QEMU guest agent.
#
# Deliberately the full virtio-win-gt-x64.msi rather than the standalone qemu-ga MSI. The
# guest agent does not talk to the host over the network; it uses a VirtIO serial port, whose
# driver (vioserial) the standalone agent package does not ship. Install only the agent and
# the service starts, reports healthy, and is invisible to Proxmox forever -- `qm agent ping`
# times out, the VM shows no IP address, and OpenTofu waits out its whole timeout on every
# create. Observed exactly that on the first template.
$ErrorActionPreference = 'Stop'

# The virtio-win ISO's drive letter is assigned at boot and is not predictable, so find the
# volume by looking for the installer rather than assuming D: or E:.
$msi = Get-PSDrive -PSProvider FileSystem |
    ForEach-Object { Join-Path $_.Root 'virtio-win-gt-x64.msi' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $msi) {
    throw "virtio-win-gt-x64.msi not found on any drive. Is the virtio-win ISO still attached? Packer unmounts it only after provisioning."
}

Write-Host "Installing VirtIO guest tools from $msi"
$p = Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart' -Wait -PassThru -NoNewWindow
if ($p.ExitCode -notin @(0, 3010)) { throw "msiexec exited $($p.ExitCode)" }

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
if (-not $vs) { throw "No VirtIO Serial device present: the guest agent will be unreachable from Proxmox." }
Write-Host "VirtIO Serial: $($vs.Status)"
