[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Tailscale.psm1') -Force
Assert-Administrator
$service=Get-Service -Name Tailscale -ErrorAction SilentlyContinue
$ts=Get-TailscaleExe
$deadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetStageBudgetSeconds 'windowsTailscale'))
$activeTransaction = $null
try { $activeTransaction = Get-ActiveDevFleetTransaction } catch { }
$transactionId = if ($activeTransaction) { [string]$activeTransaction.transactionId } else { '' }
$payloadSha256 = if ($activeTransaction) { [string]$activeTransaction.payloadSha256 } else { '' }
$evidenceName = if ($transactionId -match '^[0-9a-fA-F]{32}$') { "setup-tailscale-pairing-$transactionId.log" } else { "setup-tailscale-pairing-pid-$PID.log" }
$evidencePath = Join-Path (Join-Path $env:ProgramData 'M-TechLabs\DevFleet\Logs') $evidenceName
$hostname = ("{0}-devfleet-host" -f $env:COMPUTERNAME.ToLower())
try {
    $result=Invoke-DevFleetTailscaleOAuthPairing -FilePath $ts -Hostname $hostname -DeadlineUtc $deadline -EvidencePath $evidencePath -RunId ([string]$env:DEVFLEET_RUN_ID) -TransactionId $transactionId -PayloadSha256 $payloadSha256 -StageName 'windows-tailscale' -TargetRole 'Host' -PendingRebootProvider { Test-PendingReboot }
} catch {
    if ([string]$_.Exception.Message -match '^DEVFLEET_REBOOT_REQUIRED:') {
        Write-Warning 'Windows servicing requires a reboot during the Tailscale stage; returning 3010 before the stage marker is written.'
        exit 3010
    }
    throw
}
Write-Host "Windows host $env:COMPUTERNAME authenticated Tailscale IP: $($result.ipv4)" -ForegroundColor Green
