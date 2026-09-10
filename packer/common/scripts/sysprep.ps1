# Generalise the image. This is what strips the machine SID, and a clone without a fresh SID
# cannot join a domain -- two members would present the same identity. It also rearms the
# evaluation clock, so every clone starts its own full term however old the template is.
$ErrorActionPreference = 'Stop'

$cbDir    = Join-Path $env:ProgramFiles 'Cloudbase Solutions\Cloudbase-Init'
$unattend = Join-Path $cbDir 'conf\Unattend.xml'
if (-not (Test-Path $unattend)) { throw "cloudbase-init's Unattend.xml is missing at $unattend; did install-cloudbase-init.ps1 run?" }
if (-not $env:CLONE_PASSWORD)   { throw "CLONE_PASSWORD is not set; the build must pass it in." }

# Guarantee the clone's state from SetupComplete.cmd rather than from the answer file.
#
# The answer file was tried first and does not work: writing AdministratorPassword into
# cloudbase-init's Unattend.xml produced a clone whose account still rejected every
# credential. What a clone's OOBE actually leaves behind is a machine in the Public firewall
# profile with only the explicit all-profiles WinRM rule reachable -- 135, 139, 445 and 3389
# all closed -- and sshd not running. None of that is recoverable remotely, which is how a
# working template produces an unreachable guest.
#
# SetupComplete.cmd, by contrast, provably runs on this image: it is how cloudbase-init gets
# started, and cloudbase-init is the one thing that has worked on every clone. So append to
# it. It runs once, as SYSTEM, before any login.
#
# The password is set here as an emergency console credential and the file truncates itself
# afterwards, so it does not persist in cleartext inside every clone. Ansible does not use it;
# it authenticates with the key baked in by install-openssh.ps1.

# Registers cloudbase-init to run during the clone's first boot, which is what applies the
# network configuration before anyone can log in. This writes SetupComplete.cmd.
& (Join-Path $cbDir 'bin\SetSetupComplete.cmd')

$setupComplete = Join-Path $env:SystemRoot 'Setup\Scripts\SetupComplete.cmd'
if (-not (Test-Path $setupComplete)) { throw "SetSetupComplete.cmd did not produce $setupComplete" }

# The DHCP reset is first, and it is what makes a bare clone usable.
#
# The build gives itself a static address so Packer has a deterministic host to connect to,
# and that address survives into the image: a clone taken straight from the template, with no
# cloud-init drive, comes up on 10.0.90.99 with its adapter still named Ethernet. Verified on
# a scratch clone. Two of those would collide, and none of them sit in the DHCP scope.
#
# Resetting here rather than before sysprep is deliberate: this script talks to Packer over
# that very address, so tearing it down mid-build would drop the connection before sysprep
# ran. SetupComplete.cmd runs on the clone instead, before the cloudbase-init service starts,
# so a clone with a cloud-init drive still ends up with whatever address cloud-init assigns.
Add-Content -Path $setupComplete -Encoding ASCII -Value @"
powershell -NoProfile -Command "Get-NetAdapter -Physical | ForEach-Object { Remove-NetIPAddress -InterfaceIndex `$_.ifIndex -AddressFamily IPv4 -Confirm:`$false -ErrorAction SilentlyContinue; Set-NetIPInterface -InterfaceIndex `$_.ifIndex -Dhcp Enabled; Set-DnsClientServerAddress -InterfaceIndex `$_.ifIndex -ResetServerAddresses }"
net user Administrator "$env:CLONE_PASSWORD" /active:yes
sc config sshd start= auto
net start sshd
netsh advfirewall firewall add rule name="OpenSSH-22" dir=in action=allow protocol=TCP localport=22
type nul > "%~f0"
"@
Write-Host "first-boot commands appended to $setupComplete"

Write-Host "Running sysprep; the VM will power off and Packer will convert it to a template."
& "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /generalize /oobe /shutdown /unattend:"$unattend"
