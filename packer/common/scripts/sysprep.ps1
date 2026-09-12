# Generalise the image. This strips the machine SID, and a clone without a fresh one cannot
# join a domain, because two members would present the same identity. It also rearms the
# evaluation clock, so every clone starts its own full term however old the template is.
$ErrorActionPreference = 'Stop'

$cbDir    = Join-Path $env:ProgramFiles 'Cloudbase Solutions\Cloudbase-Init'
$unattend = Join-Path $cbDir 'conf\Unattend.xml'
if (-not (Test-Path $unattend)) { throw "cloudbase-init's Unattend.xml is missing at $unattend; did install-cloudbase-init.ps1 run?" }

# No password is set here any more, and that is the point of the detour above.
#
# Proxmox delivers a per-VM password through cloud-init metadata for a Windows guest, and
# cloudbase-init applies it. Baking one at build time was a workaround for that not
# happening, and the reason it was not happening was this repo telling Proxmox to use NoCloud
# instead of the configdrive2 format it picks for Windows on its own. With that corrected,
# every clone gets its own password from `ci_password` in the module rather than sharing one
# compiled into the image.

# The one thing that genuinely does not survive. Its installer leaves the service on Manual,
# and a clone therefore never applies its cloud-init configuration: no address, no hostname,
# an adapter still named Ethernet rather than eth0. A start type is a build-time setting, so
# this one line replaces the entire first-boot script it used to take.
Set-Service -Name cloudbase-init -StartupType Automatic
Write-Host "cloudbase-init will start on every boot and apply cloud-init config"

# Hand the adapter back to DHCP before generalising.
#
# The build gives itself a fixed address (Packer pins ssh_host, because the Proxmox
# plugin's own address discovery does not resolve here). Sysprep does not undo that, so
# every clone of this template came up on the build address until cloud-init got around to
# changing it -- and a clone made *without* cloud-init, which is exactly what an ad-hoc
# throwaway is, simply sat on it forever. Two of those at once is an address conflict, and
# one of them is the next Packer build connecting to the wrong machine.
#
# Resetting here means the template's resting state is DHCP: a declared guest still gets
# its static address from cloud-init, and an ad-hoc clone gets a lease and is reachable
# with no further help.
$adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
if ($adapter) {
    # -Confirm:$false because this runs unattended and both cmdlets prompt by default.
    Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Enabled
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses
    Write-Host "Adapter reset to DHCP; the template no longer carries the build address"
}

Write-Host "Running sysprep; the VM will power off and Packer will convert it to a template."
& "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /generalize /oobe /shutdown /unattend:"$unattend"
