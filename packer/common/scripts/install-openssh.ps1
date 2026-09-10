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

# The Ansible public key is baked in, which is a reversal worth explaining. The original plan
# was for Ansible to bootstrap over a per-clone password and install its own key. That plan
# depended on something setting a password a clone's first boot, and nothing does: cloud-init
# cannot (Proxmox and cloudbase-init disagree about where passwords live) and the sysprep
# answer file demonstrably does not either -- a clone comes up with the built-in account in
# whatever state OOBE left it and no credential anyone holds.
#
# Baking the key removes the bootstrap step rather than fixing it, which is how cloud images
# have always worked. Every clone trusting one lab key is the same trust model as every clone
# sharing one baked password, without the password.
#
# It must go here, not in ~/.ssh/authorized_keys: Windows sshd ignores that file for anyone in
# the Administrators group, reading this one instead, and refuses it outright unless the ACL
# grants nobody but SYSTEM and Administrators. Inherited permissions from ProgramData are
# enough to make it reject the file silently and fall back to asking for a password.
if (-not $env:ANSIBLE_PUBLIC_KEY) { throw "ANSIBLE_PUBLIC_KEY is not set; the build must pass it in." }
$akf = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
Set-Content -Path $akf -Value $env:ANSIBLE_PUBLIC_KEY -Encoding ASCII
icacls $akf /inheritance:r /grant 'SYSTEM:F' /grant 'BUILTIN\Administrators:F' | Out-Null
Write-Host "authorized key installed at $akf"

Write-Host "sshd: $((Get-Service sshd).Status)"
