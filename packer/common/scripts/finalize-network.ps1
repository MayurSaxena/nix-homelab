# Run by Task Scheduler as SYSTEM, not by an SSH child process. Removing the build address
# terminates that connection; Windows must finish resetting DNS and shutting down anyway.
$ErrorActionPreference = 'Stop'
Start-Transcript -Path 'C:\Windows\Temp\packer-finalize.log' -Force
try {
    # Give Packer's launching provisioner time to return before its transport disappears.
    Start-Sleep -Seconds 15

    $state = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State').ImageState
    if ($state -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
        throw "Refusing to shut down an image that has not been generalised: $state"
    }

    $adapters = @(Get-NetAdapter -Physical | Where-Object Status -eq 'Up')
    if ($adapters.Count -ne 1) { throw "Expected one active build adapter, found $($adapters.Count)" }
    $index = $adapters[0].ifIndex
    Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 |
        Where-Object PrefixOrigin -eq 'Manual' |
        Remove-NetIPAddress -Confirm:$false
    Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 |
        Where-Object DestinationPrefix -eq '0.0.0.0/0' |
        Remove-NetRoute -Confirm:$false
    Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Enabled
    Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses
    if ((Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4).Dhcp -ne 'Enabled') {
        throw 'DHCP did not become enabled'
    }
    # Keep a failed task available for LastTaskResult inspection; remove it only on success.
    Unregister-ScheduledTask -TaskName 'PackerFinalizeNetwork' -Confirm:$false
    Write-Host 'Generalised image has DHCP enabled; shutting down for capture.'
    Stop-Transcript
    & "$env:SystemRoot\System32\shutdown.exe" /s /t 0
    if ($LASTEXITCODE -ne 0) { throw "shutdown.exe exited $LASTEXITCODE" }
} catch {
    Write-Error $_ -ErrorAction Continue
    Stop-Transcript -ErrorAction SilentlyContinue
    exit 1
}
