[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$')][string]$InstanceName)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Tailscale.psm1') -Force
$mp=Get-MultipassExe
$deadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetStageBudgetSeconds 'tailscale'))
$activeTransaction = $null
try { $activeTransaction = Get-ActiveDevFleetTransaction } catch { }
$transactionId = if ($activeTransaction) { [string]$activeTransaction.transactionId } else { '' }
$payloadSha256 = if ($activeTransaction) { [string]$activeTransaction.payloadSha256 } else { '' }
$evidenceName = if ($transactionId -match '^[0-9a-fA-F]{32}$') { "setup-tailscale-pairing-$transactionId.log" } else { "setup-tailscale-pairing-pid-$PID.log" }
$evidencePath = Join-Path (Join-Path $env:ProgramData 'M-TechLabs\DevFleet\Logs') $evidenceName
$profile=Get-DevFleetTailscaleEnrollmentProfile
$expectedPeer=if([string]$profile.hostName){[string]$profile.hostName}else{"$env:COMPUTERNAME-devfleet-host"}
try {
    $result=Invoke-DevFleetTailscaleOAuthPairing -FilePath $mp -InstanceName $InstanceName -Hostname $InstanceName -ExpectedPeer $expectedPeer -DeadlineUtc $deadline -EvidencePath $evidencePath -RunId ([string]$env:DEVFLEET_RUN_ID) -TransactionId $transactionId -PayloadSha256 $payloadSha256 -StageName 'tailscale' -TargetRole 'Guest' -PendingRebootProvider { Test-PendingReboot }
} catch {
    if ([string]$_.Exception.Message -match '^DEVFLEET_REBOOT_REQUIRED:') {
        Write-Warning "Windows servicing requires a reboot during guest Tailscale stage for $InstanceName; returning 3010 before Vault completion is published."
        exit 3010
    }
    throw
}
Write-Host "$InstanceName authenticated Tailscale IP: $($result.ipv4)" -ForegroundColor Green
