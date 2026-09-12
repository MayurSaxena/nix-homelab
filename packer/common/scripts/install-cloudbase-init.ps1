# Cloudbase-init is the Windows counterpart to cloud-init. It is what makes a clone of this
# template come up with its own hostname, address and administrator password instead of a
# copy of the template's, and it reads those from the cloud-init drive Proxmox attaches.
#
# Proxmox writes configdrive2 for a Windows guest, which is the format cloudbase-init was
# built around and the only one that carries an administrator password -- see the conf
# written below, and LAB.md for how long it took to establish that. It is configured for
# ConfigDrive and nothing else on purpose.
$ErrorActionPreference = 'Stop'

# From the project's GitHub releases, not cloudbase.it.
#
# cloudbase.it hosts a floating "Stable" MSI, and it is a single small site: it went down
# mid-build here, six minutes in, and took the build with it. Two things are wrong with
# depending on it. The obvious one is availability. The subtler one is that "Stable" is not
# a version -- two builds a month apart could install different software with nothing in
# this repo recording that, which is the opposite of a reproducible template.
#
# The GitHub release asset is version-pinned and checksummed below, so a build either
# installs exactly this or fails loudly. Bump both together.
$version = '1.1.8'
$sha256  = '0E7FA42E0CBC0CE7657F85730B0C6CC7AFC4087A3639DF0FF51A721A0BE19BD5'
$url     = "https://github.com/cloudbase/cloudbase-init/releases/download/$version/CloudbaseInitSetup_${version}_x64.msi"
$msi     = Join-Path $env:TEMP "CloudbaseInitSetup_${version}_x64.msi"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Retried, because this is the one step in the build that reaches outside the lab, and
# failing it wastes the fifteen minutes of Windows installation that came before.
$attempt = 0
while ($true) {
    $attempt++
    try {
        Write-Host "Downloading cloudbase-init $version (attempt $attempt)"
        Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
        break
    } catch {
        if ($attempt -ge 3) { throw "could not download cloudbase-init from $url after $attempt attempts: $_" }
        Start-Sleep -Seconds (10 * $attempt)
    }
}

$actual = (Get-FileHash -Path $msi -Algorithm SHA256).Hash
if ($actual -ne $sha256) { throw "cloudbase-init checksum mismatch: expected $sha256, got $actual" }
Write-Host "Verified cloudbase-init $version

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
