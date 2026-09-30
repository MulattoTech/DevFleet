[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$modulePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/executors/Invoke-RealProductPhase.psm1'
Import-Module $modulePath -Force
$module=Get-Module Invoke-RealProductPhase
$samples=@(foreach($i in 1..12){[pscustomobject]@{
    checkpointPresent=$false;checkpoint=$null;terminalFailure=$false
    matchingConsumedReceipt=$false;installStateValid=$false
    canonicalOwnershipValid=$false;authenticatedHealthOk=$false
    launchTelemetry=[pscustomobject]@{kind='PASSIVE_COLD_LAUNCH_TELEMETRY';status='OBSERVED';certificationCredit=$false;launches=@([pscustomobject]@{pid=100+$i;image='24.04';instanceName='devfleet-failover'});errors=@('CACHE_METADATA_UNVERIFIED')}
    progress=[ordered]@{checkpointGeneration=0;checkpointState='';completedStages=@();resumeStage='';stages=@();cpuSeconds=0;receiptMatch=$false;health=$false}
}})
$normalized=& $module {param($value) ConvertTo-NormalizedLifecycleObservation $value} $samples[0]
if(-not $normalized.PSObject.Properties['launchTelemetry'] -or $normalized.launchTelemetry.launches.Count-ne1){throw 'Passive telemetry was discarded by normalization'}
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-cold-observer-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch|Out-Null
try{
    $state=[pscustomobject]@{now=[datetime]'2026-01-01T00:00:00Z'}
    $clock={ $current=$state.now;$state.now=$current.AddSeconds(5);$current }.GetNewClosure()
    $provider={param($s)$s.providerContext[[Math]::Min([int]$s.observationIndex,$s.providerContext.Count-1)]}
    $result=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Surrogate / Laptop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -BudgetSeconds 120 -NoProgressBudgetSeconds 60 -AbsoluteBudgetSeconds 120 -PollSeconds 5 -EvidencePath (Join-Path $scratch 'result.json') -ObservationProvider $provider -ObservationProviderContext $samples -ClockProvider $clock -SleepProvider {param($seconds)}
    $state.now=[datetime]'2026-01-01T00:00:00Z'
    $control=$samples[0].PSObject.Copy();$control.PSObject.Properties.Remove('launchTelemetry')
    $baseline=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Surrogate / Laptop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -BudgetSeconds 120 -NoProgressBudgetSeconds 60 -AbsoluteBudgetSeconds 120 -PollSeconds 5 -ObservationProvider {param($s)$s.providerContext} -ObservationProviderContext $control -ClockProvider $clock -SleepProvider {param($seconds)}
    if($result.outcome-cne'NO_PROGRESS_TIMEOUT'-or$baseline.outcome-cne$result.outcome-or$result.lastMeaningfulProgressUtc-cne$baseline.lastMeaningfulProgressUtc-or$result.noMeaningfulProgressDeadlineUtc-cne$baseline.noMeaningfulProgressDeadlineUtc){throw 'Passive telemetry earned credit or extended the semantic deadline relative to the control'}
    $journal=@(Get-Content -LiteralPath (Join-Path $scratch 'product-lifecycle-progress.jsonl')|ForEach-Object{$_|ConvertFrom-Json})
    $recorded=@($journal|Where-Object{$_.PSObject.Properties['observation']-and$_.observation.launchTelemetry.launches.Count-eq1})
    if(-not$recorded.Count){throw 'Supported lifecycle journal lost passive telemetry'}
    Write-Host 'PASS 3/3 synthetic telemetry observer cases: normalization, bounded non-credit, durable journal'
}finally{
    $resolved=[IO.Path]::GetFullPath($scratch)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not$resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup boundary'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
