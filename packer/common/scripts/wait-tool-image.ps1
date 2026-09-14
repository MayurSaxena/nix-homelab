# Retried by Packer if Boxstarter reboots. The on-disk start time bounds the entire wait,
# rather than granting another two hours after each reconnect.
$ErrorActionPreference = 'Stop'
if ($env:TOOL_IMAGE -eq 'flare') {
    $started = [DateTime]::Parse((Get-Content 'C:\ProgramData\Lab\flare-started.txt')).ToUniversalTime()
    $deadline = $started.AddHours(2)
    while ($true) {
        if (Test-Path 'C:\ProgramData\Lab\flare-failed.txt') { throw 'FLARE installer failed; inspect guest installer logs.' }
        $failures = 'C:\ProgramData\_VM\failed_packages.txt'
        $log = 'C:\ProgramData\_VM\log.txt'
        if ((Test-Path $failures) -and (Test-Path $log) -and
            (Select-String -Path $log -SimpleMatch '[*] Install Complete!' -Quiet)) {
            $failed = @(Get-Content $failures | Where-Object { $_.Trim() })
            if ($failed.Count) { throw "FLARE packages failed: $($failed -join ', ')" }
            # Let Boxstarter finish its cleanup; never capture its temporary auto-login.
            $auto = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue).AutoAdminLogon
            if ($auto -ne '1' -and -not (Get-Process choco -ErrorAction SilentlyContinue)) { break }
        }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'FLARE did not complete cleanly within two hours' }
        Start-Sleep -Seconds 15
    }
} elseif ($env:TOOL_IMAGE -eq 'ctf') {
    Write-Host 'Waiting for the Npcap console installer to finish (C:\Windows\Temp\npcap-setup.exe).'
    New-Item 'C:\ProgramData\Lab' -ItemType Directory -Force | Out-Null
    $startFile = 'C:\ProgramData\Lab\ctf-wait-started.txt'
    if (-not (Test-Path $startFile)) { [DateTime]::UtcNow.ToString('o') | Set-Content $startFile }
    $deadline = ([DateTime]::Parse((Get-Content $startFile))).ToUniversalTime().AddMinutes(30)
    while ($true) {
        $driver = Get-CimInstance Win32_SystemDriver -Filter "Name='npcap'" -ErrorAction SilentlyContinue
        $installer = Get-Process -ErrorAction SilentlyContinue | Where-Object ProcessName -Like 'npcap*'
        if ($driver -and -not $installer) {
            Start-Service npcap -ErrorAction Stop
            if ((Get-Service npcap).Status -eq 'Running') { break }
        }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Npcap interactive preparation was not completed within 30 minutes' }
        Start-Sleep -Seconds 5
    }
} else { throw 'Unknown tool image' }

$packages = & 'C:\ProgramData\chocolatey\bin\choco.exe' list --limit-output
if ($LASTEXITCODE -ne 0) { throw 'Could not inventory installed tools' }
New-Item 'C:\ProgramData\Lab' -ItemType Directory -Force | Out-Null
$nativeTools = @{}
$nmap = 'C:\Program Files (x86)\Nmap\nmap.exe'
if (Test-Path $nmap) {
    $nativeTools.nmap = @(& $nmap --version)
    if ($LASTEXITCODE -ne 0) { throw 'Nmap does not start' }
}
@{
    image = $env:TOOL_IMAGE
    captured_utc = [DateTime]::UtcNow.ToString('o')
    windows_build = (Get-CimInstance Win32_OperatingSystem).BuildNumber
    packages = @($packages)
    native_tools = $nativeTools
} | ConvertTo-Json -Depth 3 | Set-Content 'C:\ProgramData\Lab\image.json'
Write-Host "Tool image $env:TOOL_IMAGE completed and package inventory recorded."
