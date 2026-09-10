# Cloudbase-init is the Windows counterpart to cloud-init. It is what makes a clone of this
# template come up with its own hostname, address and administrator password instead of a
# copy of the template's, and it reads those from the cloud-init drive Proxmox attaches.
#
# This is the least battle-tested link in the whole pipeline: Proxmox writes NoCloud-format
# data, and cloudbase-init's NoCloud support is newer than its OpenStack support. The Phase 1
# gate exercises exactly this. If it misbehaves, the fallback is to let cloudbase-init handle
# only hostname and password and to set the static address from Ansible instead.
$ErrorActionPreference = 'Stop'

$url = 'https://www.cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi'
$msi = Join-Path $env:TEMP 'CloudbaseInitSetup_Stable_x64.msi'

Write-Host "Downloading cloudbase-init"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing

# RUN_SERVICE_AS_LOCAL_SYSTEM because the default creates a dedicated account, and a
# generalised image should not carry one. No sysprep options are passed: sysprep.ps1 runs it
# explicitly afterwards so the ordering is visible rather than buried in an installer flag.
Write-Host "Installing cloudbase-init"
$p = Start-Process msiexec.exe -ArgumentList `
    '/i', "`"$msi`"", '/qn', '/norestart', 'RUN_SERVICE_AS_LOCAL_SYSTEM=1' -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { throw "msiexec exited $($p.ExitCode)" }

$confDir = Join-Path $env:ProgramFiles 'Cloudbase Solutions\Cloudbase-Init\conf'

# Point it at the config drive and enable the plugins the clone actually needs. Written in
# full rather than patched, so what the template ships is exactly what is in this repo.
@"
[DEFAULT]
# No username/groups/inject_user_password: those configure the user plugins removed below.
config_drive_raw_hhd=true
config_drive_cdrom=true
config_drive_vfat=true
bsdtar_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\bsdtar.exe
mtu_use_dhcp_config=true
ntp_use_dhcp_config=false
local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\
logdir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
logfile=cloudbase-init.log
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
verbose=true

# NoCloud first: that is the format Proxmox writes. The others are harmless fallbacks and
# cost only a few seconds of probing if the drive is not where the first service expects.
metadata_services=cloudbaseinit.metadata.services.nocloudservice.NoCloudConfigDriveService,cloudbaseinit.metadata.services.configdrive.ConfigDriveService

# CreateUserPlugin and SetUserPasswordPlugin are deliberately absent.
#
# They do not read a password from Proxmox and then fail quietly -- they generate a random
# one and apply it. Cloudbase-init cannot get a password from a NoCloud drive at all: it
# rejects the cloud-config `password:` key that Proxmox's cloud-init tab writes ("Plugin
# 'password' is currently not supported") and reads no admin_pass from meta-data. So with
# these enabled, SetupComplete.cmd sets the break-glass password, cloudbase-init starts
# afterwards and overwrites it with something nobody has recorded, and the credential in
# secrets/lab.yaml silently becomes fiction. Verified: it was rejected on a live guest.
#
# Dropping them leaves the account exactly as the answer file left it. Nothing else here
# wants them: the SSH key is baked into the image, not injected.
plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.common.userdata.UserDataPlugin
"@ | Set-Content -Path (Join-Path $confDir 'cloudbase-init.conf') -Encoding ASCII

Write-Host "cloudbase-init installed and configured"
