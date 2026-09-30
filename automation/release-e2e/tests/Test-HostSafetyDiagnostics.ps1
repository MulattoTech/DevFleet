# Synthetic HostSafety diagnostics only; no VM, host memory, or policy mutation.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/HostSafety.psm1') -Force

function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Reasons($Result, [string[]]$Expected, [string]$Case) {
    $actual = @($Result.blockingReasons)
    Assert-That ($actual.Count -eq $Expected.Count) "$Case reason count: $($actual -join ',')"
    foreach ($reason in $Expected) {
        Assert-That ($reason -cin $actual) "$Case missing $reason"
    }
}

$common = @{InstalledUsableMemoryGiB=64; CommitLimitGiB=100}
$safe = Get-ProjectedHostMemorySafety @common -AvailableMemoryGiB 40 -ExpectedVmStartCostGiB 16 -CommittedGiB 20
Assert-That $safe.startSafe 'safe projection changed'
Assert-Reasons $safe @() 'safe'
$physical = Get-ProjectedHostMemorySafety @common -AvailableMemoryGiB 20 -ExpectedVmStartCostGiB 16 -CommittedGiB 20
Assert-That (-not $physical.startSafe) 'physical rejection changed'
Assert-Reasons $physical @('PROJECTED_PHYSICAL_BELOW_FLOOR') 'physical'
$commit = Get-ProjectedHostMemorySafety -InstalledUsableMemoryGiB 64 -CommitLimitGiB 80 -AvailableMemoryGiB 40 -ExpectedVmStartCostGiB 16 -CommittedGiB 50
Assert-That (-not $commit.startSafe -and $commit.projectedCommitHeadroomGiB -eq 14) 'commit projection changed'
Assert-Reasons $commit @('PROJECTED_COMMIT_BELOW_FLOOR') 'commit'
$usage = Get-ProjectedHostMemorySafety @common -AvailableMemoryGiB 40 -ExpectedVmStartCostGiB 0 -CommittedGiB 80
Assert-That (-not $usage.startSafe) 'usage rejection changed'
Assert-Reasons $usage @('COMMIT_USAGE_LIMIT_REACHED') 'usage'
$exhaustion = Get-ProjectedHostMemorySafety @common -AvailableMemoryGiB 40 -ExpectedVmStartCostGiB 0 -CommittedGiB 20 -ResourceExhaustion $true
Assert-That (-not $exhaustion.startSafe) 'resource exhaustion rejection changed'
Assert-Reasons $exhaustion @('RESOURCE_EXHAUSTION_OBSERVED') 'exhaustion'
$combined = Get-ProjectedHostMemorySafety -InstalledUsableMemoryGiB 64 -CommitLimitGiB 64 -AvailableMemoryGiB 10 -ExpectedVmStartCostGiB 16 -CommittedGiB 60 -ResourceExhaustion $true
Assert-That (-not $combined.startSafe) 'combined rejection changed'
Assert-Reasons $combined @('PROJECTED_PHYSICAL_BELOW_FLOOR','PROJECTED_COMMIT_BELOW_FLOOR','COMMIT_USAGE_LIMIT_REACHED','RESOURCE_EXHAUSTION_OBSERVED') 'combined'

function global:Get-CimInstance {
    param([string]$ClassName)
    if ($ClassName -eq 'Win32_OperatingSystem') { return [pscustomobject]@{TotalVisibleMemorySize=67108864} }
    if ($ClassName -eq 'Win32_PerfFormattedData_PerfOS_Memory') {
        return [pscustomobject]@{AvailableBytes=[int64](40GB); CommitLimit=[int64](80GB); CommittedBytes=[int64](50GB); PagesPerSec=0; PageReadsPerSec=0}
    }
    throw "Unexpected CIM class: $ClassName"
}
function global:Get-VMProcessor { param($VMName) [pscustomobject]@{ExposeVirtualizationExtensions=$true} }
function global:Get-VMNetworkAdapter { param($VMName) [pscustomobject]@{MacAddressSpoofing='Off'} }
function global:Get-VM { @() }
function global:Get-WinEvent { param($FilterHashtable) @() }
$vm = [pscustomobject]@{Name='DevFleet-E2E-Win11-01'; Id=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'; State='Off'; MemoryStartup=[int64](16GB); DynamicMemoryEnabled=$false}
$snapshot = Get-HostSafetySnapshot -Vm $vm
Assert-That (-not $snapshot.startSafe) 'snapshot decision changed'
Assert-That ($snapshot.commitLimitGiB -eq 80 -and $snapshot.committedGiB -eq 50 -and $snapshot.expectedVmStartCostGiB -eq 16) 'snapshot input fields changed'
Assert-That ($snapshot.projectedCommitHeadroomGiB -eq 14 -and $snapshot.commitHeadroomFloorGiB -eq 16) 'snapshot lacks actionable commit values'
Assert-Reasons $snapshot @('PROJECTED_COMMIT_BELOW_FLOOR') 'snapshot'
Assert-That ([datetimeoffset]::Parse($snapshot.observedUtc) -gt [datetimeoffset]::UtcNow.AddMinutes(-2)) 'snapshot timestamp missing or stale'
$overridden = Apply-RamPressureOverride -Snapshot $snapshot -AllowRamPressure
Assert-That (-not $overridden.rawHostSafetyStartSafe -and $overridden.effectiveStartSafe) 'diagnostic override behavior changed'
Assert-Reasons $overridden @('PROJECTED_COMMIT_BELOW_FLOOR') 'override retains raw reason'
Write-Host 'PASS synthetic HostSafety diagnostics and unchanged decisions; VM operations 0'
