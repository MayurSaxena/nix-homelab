# Generalise the image. This strips the machine SID, and a clone without a fresh one cannot
# join a domain, because two members would present the same identity. It also rearms the
# evaluation clock, so every clone starts its own full term however old the template is.
$ErrorActionPreference = 'Stop'

$cbDir    = Join-Path $env:ProgramFiles 'Cloudbase Solutions\Cloudbase-Init'
$unattend = Join-Path $cbDir 'conf\Unattend.xml'
if (-not (Test-Path $unattend)) { throw "cloudbase-init's Unattend.xml is missing at $unattend; did install-cloudbase-init.ps1 run?" }
if (-not $env:CLONE_PASSWORD)   { throw "CLONE_PASSWORD is not set; the build must pass it in." }

# Set the credential every clone will carry, here, at build time.
#
# This used to be written into the sysprep answer file and then re-applied by a
# SetupComplete.cmd script on the clone's first boot. Neither worked: a clone came up with
# the answer file's password rejected and SetupComplete.cmd still at full length, when it
# truncates itself on execution. Worse, a script that never runs never scrubs itself, so
# every clone carried this password in cleartext at a known path.
#
# Testing a live clone showed the whole mechanism was unnecessary. What survives sysprep is
# almost everything it was re-establishing:
#
#   Administrator password   survives   (verified: the build's password still authenticates)
#   sshd running             survives   (start type Automatic is preserved)
#   firewall rules           survive
#   cloudbase-init running   does NOT   (its installer leaves the service on Manual)
#
# So setting it now is enough, and Packer is connected by key rather than by password, so
# changing it underneath the session is harmless.
& net user Administrator "$env:CLONE_PASSWORD" /active:yes | Out-Null
if ($LASTEXITCODE -ne 0) { throw "net user failed with $LASTEXITCODE" }
Write-Host "Administrator password set for clones"

# The one thing that genuinely does not survive. Its installer leaves the service on Manual,
# and a clone therefore never applies its cloud-init configuration: no address, no hostname,
# an adapter still named Ethernet rather than eth0. A start type is a build-time setting, so
# this one line replaces the entire first-boot script it used to take.
Set-Service -Name cloudbase-init -StartupType Automatic
Write-Host "cloudbase-init will start on every boot and apply cloud-init config"

Write-Host "Running sysprep; the VM will power off and Packer will convert it to a template."
& "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /generalize /oobe /shutdown /unattend:"$unattend"
