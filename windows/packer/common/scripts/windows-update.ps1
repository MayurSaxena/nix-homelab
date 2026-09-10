# Optional, and off by default while the template itself is being iterated on. Turn it on
# with -var install_updates=true for a template you intend to keep for a while.
$ErrorActionPreference = 'Stop'

if ($env:INSTALL_UPDATES -ne 'true') {
    Write-Host "INSTALL_UPDATES is '$env:INSTALL_UPDATES'; skipping Windows Update."
    exit 0
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name PSWindowsUpdate -Force -Confirm:$false

Import-Module PSWindowsUpdate
# -IgnoreReboot: Packer owns the reboot decision, and a surprise restart mid-provisioner
# looks to it like a failed connection rather than an expected one.
Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -Verbose
