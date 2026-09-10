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

Write-Host "Running sysprep; the VM will power off and Packer will convert it to a template."
& "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /generalize /oobe /shutdown /unattend:"$unattend"
