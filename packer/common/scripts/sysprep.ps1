# Generalise the image. This is what strips the machine SID, and a clone without a fresh SID
# cannot join a domain -- two members would present the same identity. It also rearms the
# evaluation clock, so every clone starts its own full term however old the template is.
$ErrorActionPreference = 'Stop'

$cbDir    = Join-Path $env:ProgramFiles 'Cloudbase Solutions\Cloudbase-Init'
$unattend = Join-Path $cbDir 'conf\Unattend.xml'
if (-not (Test-Path $unattend)) { throw "cloudbase-init's Unattend.xml is missing at $unattend; did install-cloudbase-init.ps1 run?" }
if (-not $env:CLONE_PASSWORD)   { throw "CLONE_PASSWORD is not set; the build must pass it in." }

# Bake the Administrator password into the sysprep answer file.
#
# It cannot come from cloud-init, and the reason is worth writing down because everything
# about the setup looks like it should work. Proxmox puts the password and the hostname in
# *user-data*, as Linux cloud-config (`password:`, `hostname:`). Cloudbase-init does not read
# them there: SetUserPasswordPlugin wants `admin_pass` and SetHostNamePlugin wants
# `local-hostname`, both from *meta-data*, and the meta-data Proxmox generates contains
# nothing but an instance-id. Network configuration is the exception -- Proxmox writes it in
# the version-1 format cloudbase-init does understand, which is why a clone comes up on the
# right address with credentials nobody can use.
#
# So: cloud-init owns the network, this owns the password, and Ansible owns the hostname.
# Setting AdministratorPassword here also enables the built-in account, which OOBE otherwise
# leaves disabled on a generalised image. Windows scrubs the password from the copy it caches
# in C:\Windows\Panther, so it does not persist in the clone in cleartext.
[xml]$x = Get-Content $unattend
$ns  = 'urn:schemas-microsoft-com:unattend'
$nsm = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
$nsm.AddNamespace('u', $ns)

$oobe = $x.SelectSingleNode("/u:unattend/u:settings[@pass='oobeSystem']", $nsm)
if (-not $oobe) {
    $oobe = $x.CreateElement('settings', $ns)
    $oobe.SetAttribute('pass', 'oobeSystem')
    $x.DocumentElement.AppendChild($oobe) | Out-Null
}
$comp = $oobe.SelectSingleNode("u:component[@name='Microsoft-Windows-Shell-Setup']", $nsm)
if (-not $comp) {
    $comp = $x.CreateElement('component', $ns)
    $comp.SetAttribute('name', 'Microsoft-Windows-Shell-Setup')
    $comp.SetAttribute('processorArchitecture', 'amd64')
    $comp.SetAttribute('publicKeyToken', '31bf3856ad364e35')
    $comp.SetAttribute('language', 'neutral')
    $comp.SetAttribute('versionScope', 'nonSxS')
    $oobe.AppendChild($comp) | Out-Null
}
$existing = $comp.SelectSingleNode('u:UserAccounts', $nsm)
if ($existing) { $comp.RemoveChild($existing) | Out-Null }

$ua = $x.CreateElement('UserAccounts', $ns)
$ap = $x.CreateElement('AdministratorPassword', $ns)
$v  = $x.CreateElement('Value', $ns);     $v.InnerText  = $env:CLONE_PASSWORD
$pt = $x.CreateElement('PlainText', $ns); $pt.InnerText = 'true'
$ap.AppendChild($v)  | Out-Null
$ap.AppendChild($pt) | Out-Null
$ua.AppendChild($ap) | Out-Null
$comp.AppendChild($ua) | Out-Null
$x.Save($unattend)
Write-Host "Administrator password written into $unattend"

# Registers cloudbase-init to run during the clone's first boot, which is what applies the
# network configuration before anyone can log in.
& (Join-Path $cbDir 'bin\SetSetupComplete.cmd')

Write-Host "Running sysprep; the VM will power off and Packer will convert it to a template."
& "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /generalize /oobe /shutdown /unattend:"$unattend"
