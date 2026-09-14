# Generalise the image so each clone receives a fresh Windows machine identity at first boot.
$ErrorActionPreference = 'Stop'

if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive
    if ($volume.VolumeStatus -ne 'FullyDecrypted') {
        throw "The capture volume is $($volume.VolumeStatus). Fully decrypt it before Sysprep; automatic encryption must be disabled in the installation answer file."
    }
}

$cbDir    = Join-Path $env:ProgramFiles 'Cloudbase Solutions\Cloudbase-Init'
$unattend = Join-Path $cbDir 'conf\Unattend.xml'
if (-not (Test-Path $unattend)) { throw "cloudbase-init's Unattend.xml is missing at $unattend; did install-cloudbase-init.ps1 run?" }

# Sysprep parses its own command line and does not reliably preserve quotes within the
# /unattend: argument. Use a path without spaces rather than relying on PowerShell quoting.
$captureUnattend = 'C:\Windows\Temp\packer-unattend.xml'
Copy-Item -Path $unattend -Destination $captureUnattend -Force

# Client Windows disables the built-in Administrator during generalisation. Cloudbase's
# existing-user password update does not re-enable it. Enable the lab account in specialize,
# after hostname setup, without putting a password or autologon in the answer file.
[xml]$answer = Get-Content -Raw $captureUnattend
$ns = New-Object System.Xml.XmlNamespaceManager($answer.NameTable)
$ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
$commands = $answer.SelectSingleNode('//u:settings[@pass="specialize"]/u:component[@name="Microsoft-Windows-Deployment"]/u:RunSynchronous', $ns)
if (-not $commands) { throw 'Cloudbase-Init specialize commands are missing' }
$command = $answer.CreateElement('RunSynchronousCommand', $answer.DocumentElement.NamespaceURI)
$command.SetAttribute('action', 'http://schemas.microsoft.com/WMIConfig/2002/State', 'add')
foreach ($entry in @(@('Order', '2'), @('Path', 'net.exe user Administrator /active:yes'), @('Description', 'Enable the lab Administrator account'))) {
    $element = $answer.CreateElement($entry[0], $answer.DocumentElement.NamespaceURI)
    $element.InnerText = $entry[1]
    [void]$command.AppendChild($element)
}
[void]$commands.AppendChild($command)
$answer.Save($captureUnattend)

$finalizer = 'C:\Windows\Temp\packer-finalize-network.ps1'
if (-not (Test-Path $finalizer)) { throw "Missing network finaliser: $finalizer" }
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($finalizer, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count) { throw "Invalid network finaliser: $parseErrors" }

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

# Sysprep refuses to generalise when per-user Appx packages are not provisioned for all
# users. Chocolatey's notepadplusplus (and potentially others) registers an MSIX bridge
# package that triggers this. Remove all per-user-only Appx packages before generalising.
$provisioned = Get-AppxProvisionedPackage -Online | Select-Object -ExpandProperty PackageName
Get-AppxPackage | Where-Object {
    $pkg = $_.PackageFullName
    -not ($provisioned | Where-Object { $pkg -like "$_*" })
} | Remove-AppxPackage -ErrorAction SilentlyContinue
Write-Host "Removed per-user-only Appx packages that would block Sysprep."

# Keep the SSH connection until generalisation has actually succeeded. /quit lets Packer
# inspect both the process exit code and Windows' image state before network finalisation.
Write-Host "Running sysprep and waiting for generalisation to complete."
$p = Start-Process -FilePath "$env:SystemRoot\System32\Sysprep\Sysprep.exe" `
    -ArgumentList '/generalize', '/oobe', '/quit', '/quiet', "/unattend:$captureUnattend" `
    -Wait -PassThru
if ($p.ExitCode -ne 0) {
    Get-Content "$env:SystemRoot\System32\Sysprep\Panther\setuperr.log" -Tail 30 -ErrorAction SilentlyContinue
    throw "Sysprep exited $($p.ExitCode); see the Sysprep Panther logs."
}
$state = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State').ImageState
if ($state -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
    Get-Content "$env:SystemRoot\System32\Sysprep\Panther\setupact.log" -Tail 20 -ErrorAction SilentlyContinue
    throw "Sysprep returned successfully but the image is not ready for capture: $state"
}
Write-Host "Sysprep verified: $state"

# Task Scheduler owns the final network change, so it survives losing the SSH transport.
# The following shell-local provisioner waits for shutdown through the Proxmox API.
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File $finalizer"
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName 'PackerFinalizeNetwork' -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName 'PackerFinalizeNetwork'
Write-Host 'Network finalisation handed to Task Scheduler.'
