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

# Configured for ConfigDrive, which is what Proxmox emits for a Windows guest.
#
# Proxmox's generate_configdrive2 branches on ostype: for Windows it calls
# cloudbase_configdrive2_metadata, which puts admin_pass and public_keys into metadata
# exactly where cloudbase-init's ConfigDriveService looks for them. Pointing this at NoCloud
# instead -- which an earlier revision did -- throws all of that away, because
# NoCloudConfigDriveService implements no get_admin_password at all and SetUserPasswordPlugin
# then falls through to generating a random one.
$confBody = @"
[DEFAULT]
username=Administrator
groups=Administrators
inject_user_password=true

# The password arrives in metadata rather than being invented here, so the user plugins are
# wanted. They were removed once, when the password appeared to be randomised; the cause was
# the metadata service above, not the plugins.
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService

plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,cloudbaseinit.plugins.windows.createuser.CreateUserPlugin,cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin,cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,cloudbaseinit.plugins.common.userdata.UserDataPlugin

# Leaves the account logged-off rather than forcing a password change at first logon, which
# would make the credential in sops correct and unusable at the same time.
first_logon_behaviour=no

config_drive_raw_hhd=true
config_drive_cdrom=true
config_drive_vfat=true
bsdtar_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\bsdtar.exe
mtools_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin
mtu_use_dhcp_config=true
ntp_use_dhcp_config=false
local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\
logdir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
logfile=cloudbase-init.log
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
verbose=true
"@
$confBody | Set-Content -Path (Join-Path $confDir 'cloudbase-init.conf') -Encoding ASCII
# The unattend pass reads its own file; give it the same configuration.
$confBody | Set-Content -Path (Join-Path $confDir 'cloudbase-init-unattend.conf') -Encoding ASCII

Write-Host "cloudbase-init installed and configured"
