# Generalise the image. This is what strips the machine SID, and a clone without a fresh SID
# cannot join a domain -- two members would present the same identity.
#
# It also rearms the evaluation clock, so every clone starts its own full term regardless of
# how old the template is. Evaluation media allows a limited number of rearms, and each
# template build consumes one.
$ErrorActionPreference = 'Stop'

$cbDir = Join-Path $env:ProgramFiles 'Cloudbase Solutions\Cloudbase-Init'
$unattend = Join-Path $cbDir 'conf\Unattend.xml'
if (-not (Test-Path $unattend)) { throw "cloudbase-init's Unattend.xml is missing at $unattend; did install-cloudbase-init.ps1 run?" }

# Registers cloudbase-init to run during the specialize pass of the clone's first boot,
# which is what applies hostname, address and password before anyone can log in.
& (Join-Path $cbDir 'bin\SetSetupComplete.cmd')

Write-Host "Running sysprep; the VM will power off and Packer will convert it to a template."
& "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /generalize /oobe /shutdown /unattend:"$unattend"
