# Ansible talks to these machines over SSH rather than WinRM. WinRM is used only during the
# Packer build, because it is what the unattend can bring up before anything else exists.
$ErrorActionPreference = 'Stop'

$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
if ($cap.State -ne 'Installed') {
    Write-Host "Installing $($cap.Name)"
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
}

Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd

# Ansible's Windows modules are PowerShell, so a cmd.exe default shell breaks them in ways
# that surface as unintelligible parse errors rather than as a clear "wrong shell".
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -PropertyType String -Force | Out-Null

if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

# No authorized_keys is written here. The template has no business carrying a key that every
# clone would then trust; Ansible bootstraps over the per-clone password that cloudbase-init
# sets, and installs its own key on first run.
Write-Host "sshd: $((Get-Service sshd).Status)"
