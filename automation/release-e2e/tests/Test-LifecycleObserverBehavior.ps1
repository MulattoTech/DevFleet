[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
$module=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1'
Import-Module $module -Force
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\HarnessBudget.psm1') -Force
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\GuestSession.psm1') -Force
$passed=0;$failed=[System.Collections.Generic.List[string]]::new();$script:testEvidenceDirs=[System.Collections.Generic.List[string]]::new();$lifeRoot=$null
try {
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{[void]$script:failed.Add($Name)}}
$prior=[pscustomobject]@{checkpointGeneration=1;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}
function Obs([hashtable]$Values){$base=[ordered]@{checkpointPresent=$false;checkpoint=$null;matchingConsumedReceipt=$false;installStateValid=$false;canonicalOwnershipValid=$false;authenticatedHealthOk=$false;terminalFailure=$false};foreach($k in $Values.Keys){$base[$k]=$Values[$k]};[pscustomobject]$base}
$next=Obs @{checkpointPresent=$true;checkpoint=[pscustomobject]@{checkpointGeneration=2;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}}
Check ((Get-DurableProgressClassification -Observation $next -PriorCheckpoint $prior -MaxGeneration 3) -eq 'NEXT_REBOOT') 'generation advancement returns NEXT_REBOOT'
$gen1=Obs @{checkpointPresent=$true;checkpoint=$prior}
Check ((Get-DurableProgressClassification -Observation $gen1 -PriorCheckpoint $prior -MaxGeneration 3) -eq 'NO_PROGRESS') 'generation 1 persistence is not another reboot'
$complete=Obs @{matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true}
Check ((Get-DurableProgressClassification -Observation $complete -PriorCheckpoint $prior) -eq 'COMPLETED') 'matching receipt/install/ownership/authenticated health returns COMPLETED'
$mismatch=Obs @{checkpointPresent=$true;checkpoint=[pscustomobject]@{checkpointGeneration=2;transactionId='c'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}}
$mismatch.terminalFailure=$true
Check ((Get-DurableProgressClassification -Observation $mismatch -PriorCheckpoint $prior) -eq 'TERMINAL_FAILURE') 'binding mismatch returns TERMINAL_FAILURE'
$completedCheckpoint=Obs @{checkpointPresent=$true;checkpoint=$next.checkpoint;matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true;status='COMPLETED'}
Check ((Get-DurableProgressClassification -Observation $completedCheckpoint -PriorCheckpoint $prior -MaxGeneration 3) -eq 'TERMINAL_FAILURE') 'COMPLETED carrying an active checkpoint fails closed'
$hiddenForeignCheckpoint=Obs @{checkpointPresent=$false;checkpoint=$mismatch.checkpoint}
Check ((Get-DurableProgressClassification -Observation $hiddenForeignCheckpoint -PriorCheckpoint $prior -MaxGeneration 3) -eq 'TERMINAL_FAILURE') 'checkpointPresent false cannot hide a foreign checkpoint'
$flagWithoutCheckpoint=Obs @{checkpointPresent=$true;checkpoint=$null}
Check ((Get-DurableProgressClassification -Observation $flagWithoutCheckpoint -PriorCheckpoint $prior -MaxGeneration 3) -eq 'TERMINAL_FAILURE') 'checkpointPresent true with null checkpoint fails closed'
$pending=Obs @{}
Check ((Get-DurableProgressClassification -Observation $pending -PriorCheckpoint $prior) -ne 'NO_PROGRESS_TIMEOUT') 'DURABLE_PENDING is an intermediate observation, never timeout'
Check ((Get-Command Wait-DevFleetProductLifecycleTransition).Name -eq 'Wait-DevFleetProductLifecycleTransition') 'observer is callable at runtime'
$realPhaseModule=Get-Module Invoke-RealProductPhase
# A source test must remain runnable while shipping edits await a new signed
# candidate. Bind a temporary fixture inventory to an exact copy of this config;
# never modify the live CURRENT-CANDIDATE authority to run a unit regression.
$identityFixture=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-observer-identity-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $identityFixture 'source/config') -Force|Out-Null
[void]$script:testEvidenceDirs.Add($identityFixture)
$identityConfig=Join-Path $identityFixture 'source/config/devfleet.config.json'
Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'source/config/devfleet.config.json') -Destination $identityConfig
$identityHash=(Get-FileHash -LiteralPath $identityConfig).Hash.ToLowerInvariant()
[ordered]@{candidateIsCurrent=$true;sourceChangedSinceCandidate=$false;rebuildRequired=$false;shippingInputIdentity=('c'*64);candidateShippingInputIdentity=('c'*64);candidateGitCommit=('d'*40);candidateShippingInputs=@([ordered]@{root='source';path='config/devfleet.config.json';sha256=$identityHash})}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $identityFixture 'CURRENT-CANDIDATE.json') -Encoding utf8NoBOM
$productionContext=[pscustomobject]@{workspaceRoot=$identityFixture;runDir=(Join-Path $identityFixture 'audit/automation-harness/runs/behavioral-product-compute-identity');config=[pscustomobject]@{NestedLinux=[pscustomobject]@{Name='DevFleet-E2E-Linux-01'}}}
$productComputeName=& $realPhaseModule {param($ctx) Get-DevFleetProductComputeInstanceName -Context $ctx} $productionContext
Check ([string]$productComputeName -ceq 'devfleet-primary') 'production caller derives the exact candidate Primary instance identity'
Check ([string]$productComputeName -cne [string]$productionContext.config.NestedLinux.Name) 'product Primary identity remains distinct from the harness cleanup L2 identity'
$laptopComputeName='';$laptopIdentityError=''
try{$laptopComputeName=& $realPhaseModule {param($ctx) Get-DevFleetProductComputeInstanceName -Context $ctx -Role 'Laptop / Surrogate'} $productionContext}catch{$laptopIdentityError=$_.Exception.Message}
Check ([string]$laptopComputeName -ceq 'devfleet-failover' -and [string]::IsNullOrWhiteSpace($laptopIdentityError)) 'production caller derives candidate Failover identity for Laptop / Surrogate'
$desktopIdentity=& $realPhaseModule {param($ctx) Get-DevFleetProductObservationIdentity -Context $ctx -Role 'Primary / Desktop'} $productionContext
$laptopIdentity=& $realPhaseModule {param($ctx) Get-DevFleetProductObservationIdentity -Context $ctx -Role 'Laptop / Surrogate'} $productionContext
Check ([string]$desktopIdentity.computeInstanceName -ceq 'devfleet-primary' -and -not $desktopIdentity.vaultInstanceName -and @($desktopIdentity.targets).Count -eq 1 -and [string]$desktopIdentity.targets[0].nodeRole -ceq 'primary') 'Desktop observation identity authorizes only candidate Primary'
Check ([string]$laptopIdentity.computeInstanceName -ceq 'devfleet-failover' -and [string]$laptopIdentity.vaultInstanceName -ceq 'devfleet-vault' -and @($laptopIdentity.targets).Count -eq 2 -and (@($laptopIdentity.targets.nodeRole)-join ',') -ceq 'surrogate,vault') 'Laptop observation identity requires candidate Failover and Vault'
Check ([string]$desktopIdentity.configSha256 -ceq (Get-FileHash -LiteralPath (Join-Path $WorkspaceRoot 'source\config\devfleet.config.json') -Algorithm SHA256).Hash.ToLowerInvariant()) 'role identity binds the exact current candidate config hash'
$unsupportedRoleRejected=$false;try{& $realPhaseModule {param($ctx) Get-DevFleetProductObservationIdentity -Context $ctx -Role 'Desktop'} $productionContext|Out-Null}catch{$unsupportedRoleRejected=$true};Check $unsupportedRoleRejected 'unsupported shorthand role fails closed before observation'
Check (& $realPhaseModule {param($name) Test-DevFleetLifecycleStageMarkerName 'stage-compute-devfleet-primary-multipass-resolved.complete' $name} $productComputeName) 'collector allowlists the production-bound Multipass resolution boundary'
Check (& $realPhaseModule {Test-DevFleetLifecycleStageMarkerName 'stage-compute-devfleet-primary-instance-launched.complete' 'devfleet-primary'}) 'collector allowlists the bound launch boundary'
Check (& $realPhaseModule {Test-DevFleetLifecycleStageMarkerName 'stage-compute-devfleet-primary-payload-extracted.complete' 'devfleet-primary'}) 'collector allowlists the bound extraction boundary'
Check (-not (& $realPhaseModule {Test-DevFleetLifecycleStageMarkerName 'stage-vault-payload-extracted.complete' 'devfleet-primary'})) 'Desktop collector does not indiscriminately authorize Vault markers'
Check (& $realPhaseModule {Test-DevFleetLifecycleStageMarkerName 'stage-compute-devfleet-failover-payload-extracted.complete' 'devfleet-failover' 'devfleet-vault'}) 'Laptop collector authorizes candidate Failover markers'
Check (& $realPhaseModule {Test-DevFleetLifecycleStageMarkerName 'stage-vault-payload-extracted.complete' 'devfleet-failover' 'devfleet-vault'}) 'Laptop collector authorizes the required Vault marker path'
Check (-not (& $realPhaseModule {Test-DevFleetLifecycleStageMarkerName 'stage-compute-devfleet-primary-arbitrary-heartbeat.complete' 'devfleet-primary'})) 'collector rejects arbitrary host breadcrumbs as semantic stages'
Check (-not (& $realPhaseModule {Test-DevFleetLifecycleStageMarkerName 'stage-compute-devfleet-primary-multipass-resolved.complete' 'DevFleet-E2E-Linux-01'})) 'cleanup L2 identity cannot authorize product Primary stage markers'
$normalizedMarkerError=& $realPhaseModule {param($value) ConvertTo-NormalizedLifecycleObservation $value} ([pscustomobject]@{stageMarkerErrors=@([pscustomobject]@{name='stage-compute-unexpected.complete';error='stage marker name is not allowlisted'})})
Check (@($normalizedMarkerError.stageMarkerErrors).Count -eq 1 -and [string]$normalizedMarkerError.stageMarkerErrors[0].name -eq 'stage-compute-unexpected.complete') 'normalized evidence preserves the exact rejected stage marker name'
$explicitExitObservation=[pscustomobject]@{terminalFailure=$true;failure='candidate process exited before a durable checkpoint or completion state';error='candidate process exited before a durable checkpoint or completion state';status='TERMINAL_FAILURE'}
$normalizedExitObservation=& $realPhaseModule {param($value) ConvertTo-NormalizedLifecycleObservation $value} $explicitExitObservation
Check ([string]$normalizedExitObservation.failure -eq 'candidate process exited before a durable checkpoint or completion state') 'explicit product-owned terminal failure survives observation normalization'
$unclassifiedProductFailure=& $realPhaseModule {param($value) Get-WpfFailureDescriptor -Report $value} ([pscustomobject]@{status='PRODUCT_FAILURE';error='Candidate UI reported a product failure.'})
Check ([string]$unclassifiedProductFailure.failureClass -eq 'UNCLASSIFIED_PRODUCT_FAILURE' -and [string]$unclassifiedProductFailure.error -eq 'Candidate UI reported a product failure.') 'product failure without optional class preserves its primary error under strict mode'
$l2AbsentWithoutRuntime=Resolve-DevFleetNestedL2Inventory -ExpectedName 'DevFleet-E2E-Linux-01' -ExecutablePresent:$false
Check ([string]$l2AbsentWithoutRuntime.status -eq 'UNVERIFIED' -and $null -eq $l2AbsentWithoutRuntime.present) 'Multipass executable absence alone cannot prove nested L2 absence'
$emptyBackends=@([pscustomobject]@{provider='Hyper-V';status='PASS';names=@();verification='bounded Msvm inventory'},[pscustomobject]@{provider='VirtualBox';status='PASS';names=@();verification='bounded VBox inventory'})
$l2BackendAbsent=Resolve-DevFleetNestedL2Inventory -ExpectedName 'DevFleet-E2E-Linux-01' -ExecutablePresent:$false -BackendInventories $emptyBackends
Check ([string]$l2BackendAbsent.status -eq 'ABSENT' -and $l2BackendAbsent.present -eq $false -and @($l2BackendAbsent.backendInventories).Count -eq 2) 'successful in-L1 inventories of every supported backend prove exact nested L2 absence'
$remotedEmptyBackends=@([pscustomobject]@{provider='Hyper-V';status='PASS';names=[System.Collections.ArrayList]::new();verification='bounded Msvm inventory'},[pscustomobject]@{provider='VirtualBox';status='PASS';names=[System.Collections.ArrayList]::new();verification='bounded VBox inventory'})
$l2RemotedBackendAbsent=Resolve-DevFleetNestedL2Inventory -ExpectedName 'DevFleet-E2E-Linux-01' -ExecutablePresent:$false -BackendInventories $remotedEmptyBackends
Check ([string]$l2RemotedBackendAbsent.status -eq 'ABSENT' -and $l2RemotedBackendAbsent.present -eq $false -and @($l2RemotedBackendAbsent.backendInventories).Count -eq 2) 'PowerShell-remoted empty backend name collections preserve complete in-L1 absence evidence'
$backendPresent=@([pscustomobject]@{provider='Hyper-V';status='PASS';names=@('DevFleet-E2E-Linux-01');verification='bounded Msvm inventory'},[pscustomobject]@{provider='VirtualBox';status='PASS';names=@();verification='bounded VBox inventory'})
$l2BackendPresent=Resolve-DevFleetNestedL2Inventory -ExpectedName 'DevFleet-E2E-Linux-01' -ExecutablePresent:$false -BackendInventories $backendPresent
Check ([string]$l2BackendPresent.status -eq 'PRESENT' -and $l2BackendPresent.present -eq $true) 'an exact nested name in a supported backend remains PRESENT even when Multipass CLI is absent'
$l2BackendIncomplete=Resolve-DevFleetNestedL2Inventory -ExpectedName 'DevFleet-E2E-Linux-01' -ExecutablePresent:$false -BackendInventories @([pscustomobject]@{provider='Hyper-V';status='PASS';names=@();verification='bounded Msvm inventory'})
Check ([string]$l2BackendIncomplete.status -eq 'UNVERIFIED' -and $null -eq $l2BackendIncomplete.present) 'an incomplete supported-backend inventory cannot claim nested L2 absence'
$l2Present=Resolve-DevFleetNestedL2Inventory -ExpectedName 'DevFleet-E2E-Linux-01' -ExecutablePresent:$true -InventoryJson '{"list":[{"name":"DevFleet-E2E-Linux-01"}]}'
Check ([string]$l2Present.status -eq 'PRESENT' -and $l2Present.present -eq $true) 'nested L2 inventory identifies the exact owned instance'
$l2OtherOnly=Resolve-DevFleetNestedL2Inventory -ExpectedName 'DevFleet-E2E-Linux-01' -ExecutablePresent:$true -InventoryJson '{"list":[{"name":"foreign-instance"}]}'
Check ([string]$l2OtherOnly.status -eq 'ABSENT' -and $l2OtherOnly.inventoryCount -eq 1) 'nested L2 inventory distinguishes unrelated instance names'
$l2Malformed=Resolve-DevFleetNestedL2Inventory -ExpectedName 'DevFleet-E2E-Linux-01' -ExecutablePresent:$true -InventoryJson 'not-json'
Check ([string]$l2Malformed.status -eq 'UNVERIFIED' -and $null -eq $l2Malformed.present) 'malformed nested inventory fails closed as unverified'
function Invoke-NestedResolverRegressionCase {
    param([hashtable]$Parameters)
    try { return Resolve-DevFleetNestedL2Inventory @Parameters }
    catch { return [pscustomobject]@{status='THREW';present=$null;errorType=$_.Exception.GetType().FullName} }
}
$l2MissingList=Invoke-NestedResolverRegressionCase @{ExpectedName='DevFleet-E2E-Linux-01';ExecutablePresent=$true;InventoryJson='{"instances":[]}'}
Check ([string]$l2MissingList.status -eq 'UNVERIFIED' -and $null -eq $l2MissingList.present) 'valid JSON without the required Multipass list field is incomplete, not absence'
$l2WrongListType=Invoke-NestedResolverRegressionCase @{ExpectedName='DevFleet-E2E-Linux-01';ExecutablePresent=$true;InventoryJson='{"list":"not-an-array"}'}
Check ([string]$l2WrongListType.status -eq 'UNVERIFIED' -and $null -eq $l2WrongListType.present) 'Multipass list with the wrong type is unverified'
$l2MissingBackendNames=Invoke-NestedResolverRegressionCase @{ExpectedName='DevFleet-E2E-Linux-01';ExecutablePresent=$false;BackendInventories=@([pscustomobject]@{provider='Hyper-V';status='PASS';verification='bounded Msvm inventory'},[pscustomobject]@{provider='VirtualBox';status='PASS';names=@();verification='bounded VBox inventory'})}
Check ([string]$l2MissingBackendNames.status -eq 'UNVERIFIED' -and $null -eq $l2MissingBackendNames.present) 'successful backend row without a names inventory is incomplete'
$l2InvalidBackendNames=Invoke-NestedResolverRegressionCase @{ExpectedName='DevFleet-E2E-Linux-01';ExecutablePresent=$false;BackendInventories=@([pscustomobject]@{provider='Hyper-V';status='PASS';names='not-an-array';verification='bounded Msvm inventory'},[pscustomobject]@{provider='VirtualBox';status='PASS';names=@();verification='bounded VBox inventory'})}
Check ([string]$l2InvalidBackendNames.status -eq 'UNVERIFIED' -and $null -eq $l2InvalidBackendNames.present) 'backend names must be a complete array before absence can be claimed'
$l2Failed=Resolve-DevFleetNestedL2Inventory -ExpectedName 'DevFleet-E2E-Linux-01' -ExecutablePresent:$true -InventoryJson '{}' -ExitCode 1
Check ([string]$l2Failed.status -eq 'UNVERIFIED' -and $null -eq $l2Failed.present) 'failed nested inventory cannot claim absence'
$emptyGuestInventory='{"list":[]}'|ConvertFrom-Json
$emptyGuestHasListProperty=($null -ne $emptyGuestInventory -and $null -ne $emptyGuestInventory.PSObject.Properties['list'])
$emptyGuestRecords=if($emptyGuestHasListProperty){@($emptyGuestInventory.list)}elseif($emptyGuestInventory -is [System.Array]){@($emptyGuestInventory)}else{$null}
Check ($emptyGuestHasListProperty -and @($emptyGuestRecords).Count -eq 0) 'empty in-L1 Multipass list remains a valid inventory'
$firstServicing=[pscustomobject]@{cbs=$false;windowsUpdate=$false;pendingCount=2;RunspaceId=[guid]::NewGuid();PSComputerName='L1'}
$secondServicing=[pscustomobject]@{cbs=$false;windowsUpdate=$false;pendingCount=2;RunspaceId=[guid]::NewGuid();PSComputerName='L1'}
$servicingMetadataMatch=& $realPhaseModule {param($first,$second) Test-ProductServicingSamplesMatch -First $first -Second $second} $firstServicing $secondServicing
Check ([bool]$servicingMetadataMatch) 'servicing settlement ignores per-session remoting metadata'
$secondServicing.pendingCount=3
$servicingStateMismatch=& $realPhaseModule {param($first,$second) Test-ProductServicingSamplesMatch -First $first -Second $second} $firstServicing $secondServicing
Check (-not [bool]$servicingStateMismatch) 'servicing settlement detects semantic state changes'
$servicingMissingState=& $realPhaseModule {param($first,$second) Test-ProductServicingSamplesMatch -First $first -Second $second} $firstServicing ([pscustomobject]@{cbs=$false;windowsUpdate=$false})
Check (-not [bool]$servicingMissingState) 'servicing settlement fails closed on incomplete samples'
$source=Get-Content -Raw $module
Check ($source -match 'Invoke-HostAgentAuthenticatedJson' -and $source -notmatch 'Invoke-RestMethod -Uri ''http://127\.0\.0\.1:8790/healthz''') 'observer uses authenticated Host Agent protocol'
Check ($source -match 'progressSamples' -and $source -match 'cpuSeconds' -and $source -match 'Bootstrap-Install' -and $source -match 'Get-NetTCPConnection') 'observer records forward progress evidence'
Check ($source -match 'EvidenceLabel' -and $source -match 'resume-generation-' -and $source -match 'processStartTime' -and $source -match 'bootIdentity') 'WPF lifecycle legs have distinct immutable identity evidence'
Check ($source -match "PSObject\.Properties\['list'\]") 'in-L1 inventory observer checks list property presence rather than truthiness'

# Behavioral seam: these tests use only an injected observation, clock, and
# sleep provider. They are intentionally VM-free and exercise the same wait
# loop used by the real observer.
function LifecycleObs([hashtable]$Values) {
    $base=[ordered]@{checkpointPresent=$false;checkpoint=$null;matchingConsumedReceipt=$false;installStateValid=$false;canonicalOwnershipValid=$false;authenticatedHealthOk=$false;terminalFailure=$false;processTree=@();timestampUtc='2026-01-01T00:00:00Z';progress=[ordered]@{checkpointGeneration=1;checkpointState='waiting-for-reboot';completedStages=@('bootstrap');resumeStage='install';stages=@([ordered]@{name='DevFleet.Setup';path='C:\DevFleet.Setup.exe';commandClass='candidate-child'});cpuSeconds=0;installStateSha256=$null;ownershipSha256=$null;receiptMatch=$false;health=$false;hostAgentTaskState='Running';listener=$false}}
    foreach($k in $Values.Keys){$base[$k]=$Values[$k]};[pscustomobject]$base
}
function RunInjectedWait([object[]]$Samples,[int]$NoProgress=2,[int]$Absolute=20,[double]$CpuThreshold=1.0) {
    $global:DevFleetTestClock=[datetime]'2026-01-01T00:00:00Z';$script:testIndex=0
    $clock={ $current=[datetime]$global:DevFleetTestClock; $global:DevFleetTestClock=$current.AddSeconds(5); return $current };$sleep={param($seconds)}
    $provider={param($state)$i=[Math]::Min([int]$state.observationIndex,$state.providerContext.Count-1);return $state.providerContext[$i]}
    $testEvidenceDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-test-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $testEvidenceDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($testEvidenceDir)
    $path=Join-Path $testEvidenceDir 'observer-result.json'
    try{$result=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Action 'FreshInstall' -Role 'Primary / Desktop' -PriorGeneration 1 -MaxGeneration 3 -BudgetSeconds $Absolute -NoProgressBudgetSeconds $NoProgress -AbsoluteBudgetSeconds $Absolute -PollSeconds 10 -CpuDeltaThreshold $CpuThreshold -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -EvidencePath $path -ObservationProvider $provider -ObservationProviderContext $Samples -ClockProvider $clock -SleepProvider $sleep;$result|Add-Member -NotePropertyName testEvidencePath -NotePropertyValue $path -Force;return $result}
    finally{$script:testIndex=0}
}
function RunInjectedWaitWithStep([object[]]$Samples,[int]$NoProgress,[int]$Absolute,[int]$StepSeconds) {
    $global:DevFleetLongClock=[datetime]'2026-01-01T00:00:00Z'
    $clock={ $current=[datetime]$global:DevFleetLongClock; $global:DevFleetLongClock=$current.AddSeconds($StepSeconds); return $current }
    $provider={param($state)$i=[Math]::Min([int]$state.observationIndex,$state.providerContext.Count-1);return $state.providerContext[$i]}
    $testEvidenceDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-long-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $testEvidenceDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($testEvidenceDir)
    $path=Join-Path $testEvidenceDir 'observer-result.json'
    $result=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Action 'FreshInstall' -Role 'Primary / Desktop' -PriorGeneration 1 -MaxGeneration 3 -BudgetSeconds $Absolute -NoProgressBudgetSeconds $NoProgress -AbsoluteBudgetSeconds $Absolute -PollSeconds 10 -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -EvidencePath $path -ObservationProvider $provider -ObservationProviderContext $Samples -ClockProvider $clock -SleepProvider {param($seconds)}
    $result|Add-Member -NotePropertyName testEvidencePath -NotePropertyValue $path -Force
    return $result
}
function CompletionSample([hashtable]$Values){$sample=LifecycleObs @{matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true};$sample.progress.checkpointGeneration=0;$sample.progress.checkpointState='';$sample.progress.resumeStage='';foreach($k in $Values.Keys){$sample|Add-Member -NotePropertyName $k -NotePropertyValue $Values[$k] -Force};return $sample}
function Check-WaitTerminalEvidence([psobject]$Result,[string]$Name){$path=[string]$Result.testEvidencePath;$dir=if($path){Split-Path -Parent $path}else{''};$journal=if($dir){Join-Path $dir 'product-lifecycle-progress.jsonl'}else{''};$current=if($dir){Join-Path $dir 'product-lifecycle-progress-current.json'}else{''};$present=($path -and (Test-Path -LiteralPath $path) -and (Test-Path -LiteralPath $journal) -and (Test-Path -LiteralPath $current));$matches=$false;if($present){try{$last=@(Get-Content -LiteralPath $journal|Where-Object{$_})[-1]|ConvertFrom-Json;$matches=([string]$last.event -eq 'TERMINAL' -and [string]$last.terminalReason -eq [string]$Result.outcome)}catch{}};Check ($present -and $matches) "$Name writes terminal/current/journal evidence"}
function ProviderForm([int]$Kind,[hashtable]$Values){if($Kind -eq 0){return [pscustomobject]$Values};if($Kind -eq 1){return $Values};if($Kind -eq 2){$ordered=[ordered]@{};foreach($key in $Values.Keys){$ordered[$key]=$Values[$key]};return $ordered};$generic=[Collections.Generic.Dictionary[string,object]]::new();foreach($key in $Values.Keys){$generic[$key]=$Values[$key]};return $generic}
$staticRole=LifecycleObs @{}
$staticRole.progress.guestProgressMarkers=@([ordered]@{instanceName='devfleet-primary';nodeRole='primary';marker=[ordered]@{schemaVersion=1;transactionId='a'*32;payloadSha256='b'*64;sequence=9;component='rootlessRuntime';state='STARTED';updatedUtc='2026-01-01T00:00:00Z';packageVersion='1.2.13';nodeRole='primary'}})
$staticRoleCopy=$staticRole|ConvertTo-Json -Depth 16|ConvertFrom-Json
Check (-not (& $realPhaseModule {param($a,$b) Test-ProductMeaningfulProgress -Previous $a -Current $b -TransactionId ('a'*32) -PayloadSha256 ('b'*64)} $staticRole $staticRoleCopy)) 'unchanged serialized per-role marker does not reset semantic progress'
$advancedRole=$staticRole|ConvertTo-Json -Depth 16|ConvertFrom-Json
$advancedRole.progress.guestProgressMarkers[0].marker.sequence=10
$advancedRole.progress.guestProgressMarkers[0].marker.state='COMPLETED'
Check (& $realPhaseModule {param($a,$b) Test-ProductMeaningfulProgress -Previous $a -Current $b -TransactionId ('a'*32) -PayloadSha256 ('b'*64)} $staticRole $advancedRole) 'completed per-role component advances semantic progress'
$staticRoleResult=RunInjectedWait @($staticRole,$staticRoleCopy,$staticRoleCopy) 60 120
Check ([string]$staticRoleResult.outcome -eq 'NO_PROGRESS_TIMEOUT') 'repeated per-role STARTED marker naturally reaches the no-progress deadline'
Check-WaitTerminalEvidence $staticRoleResult 'static per-role marker timeout'
$twoRoles=$staticRole|ConvertTo-Json -Depth 16|ConvertFrom-Json
$vaultRecord=$staticRole.progress.guestProgressMarkers[0]|ConvertTo-Json -Depth 12|ConvertFrom-Json
$vaultRecord.instanceName='devfleet-vault';$vaultRecord.nodeRole='vault';$vaultRecord.marker.nodeRole='vault';$vaultRecord.marker.component='restServer';$vaultRecord.marker.packageVersion='vault'
$twoRoles.progress.guestProgressMarkers=@($twoRoles.progress.guestProgressMarkers[0],$vaultRecord)
$reorderedRoles=$twoRoles|ConvertTo-Json -Depth 16|ConvertFrom-Json
$reorderedRoles.progress.guestProgressMarkers=@($reorderedRoles.progress.guestProgressMarkers[1],$reorderedRoles.progress.guestProgressMarkers[0])
Check (-not (& $realPhaseModule {param($a,$b) Test-ProductMeaningfulProgress -Previous $a -Current $b -TransactionId ('a'*32) -PayloadSha256 ('b'*64)} $twoRoles $reorderedRoles)) 'unchanged Failover/Vault marker ordering is not progress'
$stable=LifecycleObs @{}
$stableResult=RunInjectedWait @($stable,$stable,$stable) 60 120
Check ([string]$stableResult.outcome -eq 'NO_PROGRESS_TIMEOUT') 'OBS-01 stable lifecycle naturally returns NO_PROGRESS_TIMEOUT'
Check ([int]$stableResult.progressSampleCount -ge 2) 'OBS-01 bounded timeline has repeated observations'
$churn=LifecycleObs @{};$churn.processTree=@([ordered]@{ProcessId=100;Name='powershell.exe';CommandLine='-ServerMode V2SocketServerMode'})
$churnResult=RunInjectedWait @($churn,$churn,$churn) 60 120
Check ([string]$churnResult.outcome -eq 'NO_PROGRESS_TIMEOUT') 'OBS-02/03 observer remoting and V2SocketServerMode churn do not reset clock'
$tiny=LifecycleObs @{};$tiny.progress.cpuSeconds=.2
$tinyResult=RunInjectedWait @($stable,$tiny,$tiny,$tiny) 60 120
Check ([string]$tinyResult.outcome -eq 'NO_PROGRESS_TIMEOUT') 'OBS-04 tiny CPU noise does not reset clock'
$meaningful=LifecycleObs @{};$meaningful.progress.cpuSeconds=2
$meaningfulResult=RunInjectedWait @($stable,$meaningful,$meaningful,$meaningful,$meaningful) 60 120
Check ([string]$meaningfulResult.outcome -eq 'NO_PROGRESS_TIMEOUT') 'OBS-05 CPU delta is activity only and cannot reset the semantic deadline'
$durable=LifecycleObs @{};$durable.progress.resumeStage='next-stage'
$durableResult=RunInjectedWait @($stable,$durable,$durable,$durable,$durable) 60 120
Check ([string]$durableResult.outcome -eq 'NO_PROGRESS_TIMEOUT' -and [int]$durableResult.progressSampleCount -gt [int]$meaningfulResult.progressSampleCount) 'OBS-05 durable resume-stage transition resets semantic deadline'
$markerPrior=[pscustomobject]@{transactionId='a'*32;payloadSha256='b'*64;sequence=1;component='packagePrerequisites';state='STARTED';nodeRole='primary'}
$markerNext=[pscustomobject]@{transactionId='a'*32;payloadSha256='b'*64;sequence=2;component='packagePrerequisites';state='COMPLETED';nodeRole='primary'}
$markerObservation=LifecycleObs @{};$markerObservation.progress.guestProgressMarker=$markerNext
$markerPrevious=LifecycleObs @{};$markerPrevious.progress.guestProgressMarker=$markerPrior
Check (& $realPhaseModule {param($a,$b) Test-ProductMeaningfulProgress -Previous $a -Current $b -TransactionId ('a'*32) -PayloadSha256 ('b'*64)} $markerPrevious $markerObservation) 'OBS-07 matching monotonic guest marker is semantic progress'
$timestampMarker=LifecycleObs @{};$timestampMarker.progress.guestProgressMarker=($markerPrior|ConvertTo-Json|ConvertFrom-Json)
Check (-not (& $realPhaseModule {param($a,$b) Test-ProductMeaningfulProgress -Previous $a -Current $b -TransactionId ('a'*32) -PayloadSha256 ('b'*64)} $markerPrevious $timestampMarker)) 'OBS-07 timestamp-only/same-sequence marker rewrite is not progress'
$foreignMarker=LifecycleObs @{};$foreignMarker.progress.guestProgressMarker=[pscustomobject]@{transactionId='c'*32;payloadSha256='b'*64;sequence=2;component='packagePrerequisites';state='COMPLETED';nodeRole='primary'}
Check (-not (& $realPhaseModule {param($a,$b) Test-ProductMeaningfulProgress -Previous $a -Current $b -TransactionId ('a'*32) -PayloadSha256 ('b'*64)} $markerPrevious $foreignMarker)) 'OBS-07 stale transaction marker is rejected'
$payloadMarker=LifecycleObs @{};$payloadMarker.progress.guestProgressMarker=[pscustomobject]@{transactionId='a'*32;payloadSha256='c'*64;sequence=2;component='packagePrerequisites';state='COMPLETED';nodeRole='primary'}
Check (-not (& $realPhaseModule {param($a,$b) Test-ProductMeaningfulProgress -Previous $a -Current $b -TransactionId ('a'*32) -PayloadSha256 ('b'*64)} $markerPrevious $payloadMarker)) 'OBS-07 payload-mismatched marker is rejected'
$validMarkerJson=[ordered]@{schemaVersion=1;transactionId='a'*32;payloadSha256='b'*64;sequence=1;component='secretsInput';state='STARTED';updatedUtc='2026-01-01T00:00:00Z';packageVersion='1.2.13';nodeRole='primary'}|ConvertTo-Json -Compress
$validMarkerRead=Resolve-GuestProgressMarkerRead -Text $validMarkerJson -ExitCode 0 -ExpectedTransactionId ('a'*32) -ExpectedPayloadSha256 ('b'*64) -InstanceName 'devfleet-primary'
$absentMarkerRead=Resolve-GuestProgressMarkerRead -Text '' -ExitCode 44 -ExpectedTransactionId ('a'*32) -ExpectedPayloadSha256 ('b'*64) -InstanceName 'devfleet-primary'
$failedMarkerRead=Resolve-GuestProgressMarkerRead -Text 'transport detail' -ExitCode 5 -ExpectedTransactionId ('a'*32) -ExpectedPayloadSha256 ('b'*64) -InstanceName 'devfleet-primary'
$timeoutMarkerRead=Resolve-GuestProgressMarkerRead -Text '' -ExitCode $null -TimedOut -ExpectedTransactionId ('a'*32) -ExpectedPayloadSha256 ('b'*64) -InstanceName 'devfleet-primary'
$malformedMarkerRead=Resolve-GuestProgressMarkerRead -Text '{not-json' -ExitCode 0 -ExpectedTransactionId ('a'*32) -ExpectedPayloadSha256 ('b'*64) -InstanceName 'devfleet-primary'
$incompleteMarkerRead=Resolve-GuestProgressMarkerRead -Text '{"schemaVersion":1}' -ExitCode 0 -ExpectedTransactionId ('a'*32) -ExpectedPayloadSha256 ('b'*64) -InstanceName 'devfleet-primary'
$wrongRoleShapeJson=([ordered]@{schemaVersion=1;transactionId='a'*32;payloadSha256='b'*64;sequence=1;component='restServer';state='STARTED';updatedUtc='2026-01-01T00:00:00Z';packageVersion='1.2.13';nodeRole='primary'}|ConvertTo-Json -Compress)
$wrongRoleShapeRead=Resolve-GuestProgressMarkerRead -Text $wrongRoleShapeJson -ExitCode 0 -ExpectedTransactionId ('a'*32) -ExpectedPayloadSha256 ('b'*64) -InstanceName 'devfleet-primary'
$wrongMarkerJson=([ordered]@{schemaVersion=1;transactionId='c'*32;payloadSha256='b'*64;sequence=1;component='secretsInput';state='STARTED';updatedUtc='2026-01-01T00:00:00Z';packageVersion='1.2.13';nodeRole='primary'}|ConvertTo-Json -Compress)
$wrongMarkerRead=Resolve-GuestProgressMarkerRead -Text $wrongMarkerJson -ExitCode 0 -ExpectedTransactionId ('a'*32) -ExpectedPayloadSha256 ('b'*64) -InstanceName 'devfleet-primary'
Check ([string]$validMarkerRead.status -eq 'VALID' -and [string]$validMarkerRead.marker.component -eq 'secretsInput') 'guest marker reader accepts a valid current marker'
Check ([string]$absentMarkerRead.status -eq 'ABSENT' -and [int]$absentMarkerRead.exitCode -eq 44) 'guest marker reader requires an explicit remote absence exit code'
Check ([string]$failedMarkerRead.status -eq 'NATIVE_FAILURE' -and [int]$failedMarkerRead.exitCode -eq 5) 'guest marker reader preserves a nonzero native read failure'
Check ([string]$timeoutMarkerRead.status -eq 'TIMEOUT') 'guest marker reader keeps timeout distinct from absence'
Check ([string]$malformedMarkerRead.status -eq 'MALFORMED') 'guest marker reader keeps invalid JSON distinct from absence'
Check ([string]$incompleteMarkerRead.status -eq 'MALFORMED') 'guest marker reader fails an incomplete marker schema closed'
Check ([string]$wrongRoleShapeRead.status -eq 'MALFORMED') 'guest marker reader rejects a component/version/role combination from the wrong bootstrap contract'
Check ([string]$wrongMarkerRead.status -eq 'IDENTITY_MISMATCH' -and $null -eq $wrongMarkerRead.marker) 'guest marker reader rejects wrong transaction identity before attachment'
$failedGuestJson=[ordered]@{schemaVersion=1;transactionId='a'*32;payloadSha256='b'*64;sequence=2;component='secretsInput';state='TIMED_OUT';updatedUtc='2026-01-01T00:00:01Z';packageVersion='1.2.13';nodeRole='primary'}|ConvertTo-Json -Compress
$failedGuestRead=Resolve-GuestProgressMarkerRead -Text $failedGuestJson -ExitCode 0 -ExpectedTransactionId ('a'*32) -ExpectedPayloadSha256 ('b'*64) -InstanceName 'devfleet-primary'
$failedGuestObservation=Add-GuestProgressMarkerObservation -Observation (LifecycleObs @{}) -ReadResult $failedGuestRead
Check ([bool]$failedGuestObservation.terminalFailure -and [string]$failedGuestObservation.status -eq 'TERMINAL_FAILURE' -and [string]$failedGuestObservation.failure -match 'secretsInput reported TIMED_OUT') 'valid guest failure marker becomes an immediate product terminal'
foreach($attachmentRead in @($validMarkerRead,$absentMarkerRead,$timeoutMarkerRead,$failedGuestRead)){
    $attachmentObservation=LifecycleObs @{}
    $attachmentObservation.progress.guestProgressMarkerStatus='DEFERRED'
    $attachmentObservation|Add-Member -NotePropertyName progressMarker -NotePropertyValue ($attachmentObservation.progress|ConvertTo-Json -Compress -Depth 20) -Force
    $attached=Add-GuestProgressMarkerObservation -Observation $attachmentObservation -ReadResult $attachmentRead
    Check ([string]$attached.progressMarker -ceq ($attached.progress|ConvertTo-Json -Compress -Depth 20)) "guest marker attachment refreshes serialized evidence for $([string]$attachmentRead.status)"
}
$inputStart=LifecycleObs @{};$inputStart.progress.guestProgressMarker=$validMarkerRead.marker
$inputCompleted=LifecycleObs @{};$inputCompleted.progress.guestProgressMarker=[pscustomobject]@{schemaVersion=1;transactionId='a'*32;payloadSha256='b'*64;sequence=2;component='secretsInput';state='COMPLETED';packageVersion='1.2.13';nodeRole='primary'}
Check (& $realPhaseModule {param($a,$b) Test-ProductMeaningfulProgress -Previous $a -Current $b -TransactionId ('a'*32) -PayloadSha256 ('b'*64)} $inputStart $inputCompleted) 'bound secrets input acknowledgement advances semantic guest progress'
$longProgressSamples=@();for($i=1;$i -le 6;$i++){$sample=LifecycleObs @{};$sample.progress.operationStatus='Invoking actual connected installation chain';$sample.progress.guestProgressMarker=[pscustomobject]@{transactionId='a'*32;payloadSha256='b'*64;sequence=$i;component=if($i -lt 3){'packagePrerequisites'}elseif($i -lt 5){'dockerRepositoryAndInstall'}else{'tailscaleRepositoryAndInstall'};state=if($i%2){'STARTED'}else{'COMPLETED'};nodeRole='primary'};$longProgressSamples+=$sample};$longCompletion=CompletionSample @{};$longCompletion.progress.operationStatus='Invoking actual connected installation chain';$longCompletion.progress.guestProgressMarker=[pscustomobject]@{transactionId='a'*32;payloadSha256='b'*64;sequence=7;component='rootlessRuntime';state='STARTED';nodeRole='primary'};$longProgressSamples+=$longCompletion
$longProgressResult=RunInjectedWaitWithStep $longProgressSamples 1800 7200 200
$longProgressElapsed=([datetime]$longProgressResult.lastMeaningfulProgressUtc-[datetime]$longProgressResult.startUtc).TotalSeconds
Check ([string]$longProgressResult.outcome -eq 'COMPLETED' -and $longProgressElapsed -gt 1800 -and @($longProgressSamples.progress.operationStatus|Select-Object -Unique).Count -eq 1) 'transaction/payload-bound durable guest progress carries a static WPF status beyond 1800 simulated seconds within the fixed owner deadline'
$heartbeatSamples=@();for($i=0;$i -lt 20;$i++){$sample=LifecycleObs @{};$sample.progress.cpuSeconds=($i*2);$sample.progress.resumeStage="step-$i";$heartbeatSamples+=$sample};$absoluteResult=RunInjectedWait $heartbeatSamples 7200 120
Check ([string]$absoluteResult.outcome -eq 'ABSOLUTE_TIMEOUT') 'OBS-06 immutable absolute deadline cannot be extended'
$global:DevFleetInheritedClock=[datetime]'2026-01-01T00:01:50Z';$inheritedClock={$value=[datetime]$global:DevFleetInheritedClock;$global:DevFleetInheritedClock=$value.AddSeconds(5);$value};$inheritedDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-inherited-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $inheritedDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($inheritedDir);$inheritedResult=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Primary / Desktop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -NoProgressBudgetSeconds 60 -AbsoluteBudgetSeconds 120 -AbsoluteDeadlineUtc '2026-01-01T00:02:00Z' -ObservationProvider {param($s)$s.providerContext} -ObservationProviderContext $stable -ClockProvider $inheritedClock -SleepProvider {param($seconds)} -EvidencePath (Join-Path $inheritedDir 'observer.json')
Check ([string]$inheritedResult.outcome -eq 'ABSOLUTE_TIMEOUT' -and [int]$inheritedResult.effectiveAbsoluteBudgetSeconds -eq 10 -and [datetime]$inheritedResult.absoluteLifecycleDeadlineUtc -eq [datetime]'2026-01-01T00:02:00Z') 'inherited lifecycle owner deadline charges already-consumed time and never grants a fresh child budget'
$badVersionRejected=$false;try{Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Primary / Desktop' -ExpectedDevFleetVersion '' -ExpectedInstallerVersion '1.4.1' -AbsoluteBudgetSeconds 1}catch{$badVersionRejected=$true}
Check ($badVersionRejected) 'OBS-06 expected version identity is fail-closed'
Check ([int]$stableResult.effectiveNoProgressBudgetSeconds -eq 60 -and [int]$stableResult.effectiveAbsoluteBudgetSeconds -eq 120 -and [int]$stableResult.requestedBudgetSeconds -eq 120) 'OBS-06 effective budgets preserve requested finite values without silent clamping'
$policy=Get-HarnessBudgetPolicy -Config (Get-Content (Join-Path $WorkspaceRoot 'automation\release-e2e\config\devfleet-e2e.defaults.json') -Raw|ConvertFrom-Json)
Check ([int]$policy.observerAbsoluteBudgetSeconds -gt [int]$policy.productTransactionAbsoluteBudgetSeconds -and [int]$policy.fullReleaseWatchdogSeconds -gt [int]$policy.observerAbsoluteBudgetSeconds -and [int]$policy.exactProofOuterWatchdogSeconds -gt [int]$policy.exactProofInnerBoundSeconds) 'OBS-15 composed parent deadlines strictly dominate their children'
Check ((Assert-HarnessBudgetPolicy -Policy $policy) -eq $true) 'OBS-16 invalid hierarchy policy is rejected by the authoritative validator'
$genJump=LifecycleObs @{checkpointPresent=$true;checkpoint=[pscustomobject]@{checkpointGeneration=3;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}}
Check ((Get-DurableProgressClassification -Observation $genJump -PriorCheckpoint $prior -MaxGeneration 3) -eq 'TERMINAL_FAILURE') 'OBS-07/09 generation jump fails closed'
$foreign=LifecycleObs @{checkpointPresent=$true;checkpoint=[pscustomobject]@{checkpointGeneration=2;transactionId='c'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}}
Check ((Get-DurableProgressClassification -Observation $foreign -PriorCheckpoint $prior -MaxGeneration 3) -eq 'TERMINAL_FAILURE') 'OBS-10 foreign transaction fails closed'
$complete2=LifecycleObs @{matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true}
$complete2.progress.checkpointGeneration=0;$complete2.progress.checkpointState='';$complete2.progress.resumeStage=''
Check ((Get-DurableProgressClassification -Observation $complete2 -PriorCheckpoint $prior) -eq 'COMPLETED') 'OBS-11 matching consumed receipt and authenticated health completes'
$orderedComplete=[ordered]@{checkpointPresent=$false;checkpoint=$null;matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true;progress=[ordered]@{checkpointGeneration=0;checkpointState='';completedStages=@('complete');resumeStage='';stages=@();productChildInstances=@();cpuSeconds=0;receiptMatch=$true;health=$true;hostAgentTaskState='Running';listener=$true}}
$orderedCompleteResult=RunInjectedWait @($orderedComplete) 60 120
Check ([string]$orderedCompleteResult.outcome -eq 'COMPLETED') 'OBS-11 exact production-shaped zero checkpoint generation completes'
$orderedCheckpoint=[ordered]@{checkpointGeneration=2;generation=2;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'};$orderedNext=[ordered]@{checkpointPresent=$true;checkpoint=$orderedCheckpoint;matchingConsumedReceipt=$false;installStateValid=$false;canonicalOwnershipValid=$false;authenticatedHealthOk=$false;progress=[ordered]@{checkpointGeneration=2;checkpointState='waiting-for-reboot';completedStages=@('bootstrap');resumeStage='install';stages=@();productChildInstances=@();cpuSeconds=1;receiptMatch=$false;health=$false;hostAgentTaskState='Running';listener=$true}}
$orderedNextResult=RunInjectedWait @($orderedNext) 60 120
Check ([string]$orderedNextResult.outcome -eq 'NEXT_REBOOT') 'OBS-11 OrderedDictionary checkpoint reaches NEXT_REBOOT with exact binding'
$generationZeroDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-generation-zero-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $generationZeroDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($generationZeroDir)
$generationZeroTx='f'*32;$generationZeroCheckpoint=[pscustomobject]@{checkpointGeneration=1;generation=1;transactionId=$generationZeroTx;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'};$generationZeroObservation=LifecycleObs @{checkpointPresent=$true;checkpoint=$generationZeroCheckpoint};$global:DevFleetGenerationZeroClock=[datetime]'2026-01-01T00:00:00Z';$generationZeroClock={$value=[datetime]$global:DevFleetGenerationZeroClock;$global:DevFleetGenerationZeroClock=$value.AddSeconds(1);$value};$generationZeroProvider={param($state)$state.providerContext};$generationZeroResult=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId '' -PayloadSha256 ('b'*64) -Action 'FreshInstall' -Role 'Primary / Desktop' -PriorGeneration 0 -MaxGeneration 3 -BudgetSeconds 60 -NoProgressBudgetSeconds 60 -AbsoluteBudgetSeconds 60 -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -EvidencePath (Join-Path $generationZeroDir 'observer.json') -ObservationProvider $generationZeroProvider -ObservationProviderContext $generationZeroObservation -ClockProvider $generationZeroClock -SleepProvider {param($seconds)}
Check ([string]$generationZeroResult.outcome -eq 'NEXT_REBOOT' -and [string]$generationZeroResult.checkpoint.transactionId -eq $generationZeroTx) 'OBS-12 generation-zero observer safely adopts the first exact transaction checkpoint'
$generationZeroBindingTx='e'*32;$generationZeroBindingActiveTransaction=[pscustomobject]@{path='C:\ProgramData\DevFleet\active-transaction.json';transactionId=$generationZeroBindingTx;payloadSha256='b'*64;action='FreshInstall';role='Desktop';preparedUtc='2026-01-01T00:00:00Z'}
$generationZeroBindingStageMarkers=@([pscustomobject]@{name='stage-compute-devfleet-primary-multipass-resolved.complete';transactionId=$generationZeroBindingTx;payloadSha256='b'*64;action='FreshInstall';role='Desktop';stage='stage-compute-devfleet-primary-multipass-resolved';completedUtc='2026-01-01T00:00:05Z'})
$generationZeroBindingActive=LifecycleObs @{activeTransaction=$generationZeroBindingActiveTransaction}
$generationZeroBindingStage=LifecycleObs @{activeTransaction=$generationZeroBindingActiveTransaction;stageMarkers=$generationZeroBindingStageMarkers}
$generationZeroBindingComplete=LifecycleObs @{activeTransaction=$generationZeroBindingActiveTransaction;stageMarkers=$generationZeroBindingStageMarkers;receipt=[pscustomobject]@{transactionId=$generationZeroBindingTx;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop'};matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true}
$generationZeroBindingComplete.progress.checkpointGeneration=0;$generationZeroBindingComplete.progress.checkpointState='';$generationZeroBindingComplete.progress.resumeStage=''
$generationZeroBindingTrace=[Collections.Generic.List[string]]::new();$generationZeroBindingSamples=@($generationZeroBindingActive,$generationZeroBindingStage,$generationZeroBindingComplete)
$generationZeroBindingProvider={param($state)[void]$generationZeroBindingTrace.Add([string]$state.transactionId);$generationZeroBindingSamples[[Math]::Min([int]$state.observationIndex,$generationZeroBindingSamples.Count-1)]}
$global:DevFleetGenerationZeroBindingClock=[datetime]'2026-01-01T00:00:00Z';$generationZeroBindingClock={$value=[datetime]$global:DevFleetGenerationZeroBindingClock;$global:DevFleetGenerationZeroBindingClock=$value.AddSeconds(1);$value}
$generationZeroBindingDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-generation-zero-binding-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $generationZeroBindingDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($generationZeroBindingDir)
$generationZeroBindingResult=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId '' -PayloadSha256 ('b'*64) -Action 'FreshInstall' -Role 'Primary / Desktop' -PriorGeneration 0 -MaxGeneration 3 -BudgetSeconds 60 -NoProgressBudgetSeconds 60 -AbsoluteBudgetSeconds 60 -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ExpectedComputeInstanceName 'devfleet-primary' -InvocationStartUtc '2026-01-01T00:00:00Z' -EvidencePath (Join-Path $generationZeroBindingDir 'observer.json') -ObservationProvider $generationZeroBindingProvider -ObservationProviderContext $generationZeroBindingSamples -ClockProvider $generationZeroBindingClock -SleepProvider {param($seconds)}
Check ([string]$generationZeroBindingResult.outcome -eq 'COMPLETED' -and $generationZeroBindingTrace.Count -ge 3 -and [string]$generationZeroBindingTrace[0] -eq '' -and [string]$generationZeroBindingTrace[1] -eq '' -and [string]$generationZeroBindingTrace[2] -ceq $generationZeroBindingTx) 'OBS-17 generation-zero observer adopts a current candidate-bound stage-marker transaction before receipt consumption'
$completionForms=@([pscustomobject]$orderedComplete,@{checkpointPresent=$false;checkpoint=$null;matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true;progress=[ordered]@{checkpointGeneration=0;checkpointState='';completedStages=@('complete');resumeStage='';stages=@();productChildInstances=@();cpuSeconds=0}},$orderedComplete)
$genericCompletion=[Collections.Generic.Dictionary[string,object]]::new();foreach($key in $orderedComplete.Keys){$genericCompletion[$key]=$orderedComplete[$key]};$completionForms+=,$genericCompletion
foreach($index in 0..($completionForms.Count-1)){Check ((Get-DurableProgressClassification -Observation ([psobject]$completionForms[$index]) -PriorCheckpoint $prior) -eq 'COMPLETED') "OBS-11 production-shaped completion representation $($index+1) returns COMPLETED"}
$global:DevFleetDeadlineClock=[datetime]'2026-01-01T00:00:00Z';$global:DevFleetDeadlineCalls=0;$deadlineClock={if($global:DevFleetDeadlineCalls -lt 2){$global:DevFleetDeadlineCalls++;$current=[datetime]$global:DevFleetDeadlineClock;if($global:DevFleetDeadlineCalls -eq 2){$global:DevFleetDeadlineClock=$current.AddSeconds(61)};return $current};return [datetime]$global:DevFleetDeadlineClock};$deadlineProvider={param($s)$s.providerContext};$deadlineDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-deadline-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $deadlineDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($deadlineDir);$deadlineResult=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Primary / Desktop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -NoProgressBudgetSeconds 60 -AbsoluteBudgetSeconds 60 -ObservationProvider $deadlineProvider -ObservationProviderContext $complete2 -ClockProvider $deadlineClock -EvidencePath (Join-Path $deadlineDir 'observer.json')
Check ([string]$deadlineResult.outcome -eq 'ABSOLUTE_TIMEOUT' -and [string]$deadlineResult.terminalReason -match 'after observation') 'OBS-11 completion one tick after absolute deadline fails closed'
$journalResult=RunInjectedWait @($stable,$stable,$stable) 60 120
Check ($journalResult.startUtc -and $journalResult.absoluteLifecycleDeadlineUtc) 'OBS-13 terminal result includes bounded clock evidence'
Check ((Test-Path -LiteralPath $journalResult.testEvidencePath) -and (Test-Path -LiteralPath ([IO.Path]::Combine([IO.Path]::GetDirectoryName([string]$journalResult.testEvidencePath),'product-lifecycle-progress.jsonl'))) -and (@(Get-Content -LiteralPath ([IO.Path]::Combine([IO.Path]::GetDirectoryName([string]$journalResult.testEvidencePath),'product-lifecycle-progress.jsonl')) | Where-Object { $_ -match '"event":"START"' }).Count -ge 1)) 'OBS-14 interruption journal exists before first observation'
Check ($source -match 'product-lifecycle-progress.jsonl' -and $source -match "event='TERMINAL'") 'OBS-14 interruption-safe incremental journal/current snapshot is wired'
$errorEvidenceDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-error-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $errorEvidenceDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($errorEvidenceDir);$errorProvider={param($s)throw 'controlled provider failure'};$errorResult=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Primary / Desktop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ObservationProvider $errorProvider -EvidencePath (Join-Path $errorEvidenceDir 'observer.json')
Check ([string]$errorResult.outcome -eq 'TERMINAL_FAILURE' -and (Test-Path -LiteralPath (Join-Path $errorEvidenceDir 'observer.json'))) 'observer provider error normalizes to strict-safe terminal evidence'
$transportRecoveryDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-transport-recovery-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $transportRecoveryDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($transportRecoveryDir);$global:DevFleetTransportRecoveryClock=[datetime]'2026-01-01T00:00:00Z';$transportRecoveryClock={$value=[datetime]$global:DevFleetTransportRecoveryClock;$global:DevFleetTransportRecoveryClock=$value.AddSeconds(5);$value};$transportRecoveryProvider={param($s)if([int]$s.observationIndex -lt 2){throw 'The background process reported an error with the following message: "The Hyper-V socket target process has ended."'};return $s.providerContext};$transportRecoveryResult=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Primary / Desktop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -NoProgressBudgetSeconds 60 -AbsoluteBudgetSeconds 120 -ObservationProvider $transportRecoveryProvider -ObservationProviderContext (LifecycleObs @{}) -ClockProvider $transportRecoveryClock -SleepProvider {param($seconds)} -EvidencePath (Join-Path $transportRecoveryDir 'observer.json')
Check ([string]$transportRecoveryResult.outcome -eq 'NO_PROGRESS_TIMEOUT' -and @($transportRecoveryResult.transportRecoveryAttempts).Count -eq 2) 'transient Hyper-V transport failure is retried finitely without resetting lifecycle deadlines'
Check ([string]$transportRecoveryResult.transportRecoveryAttempts[0].error -match 'Hyper-V socket target process has ended' -and [int]$transportRecoveryResult.transportRecoveryAttempts[0].delaySeconds -le 5) 'transport recovery evidence records the bounded error and delay'
$credentialErrorDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-credential-error-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $credentialErrorDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($credentialErrorDir)
$credentialErrorProvider={param($s)throw 'LAB_CREDENTIAL_STALE: canonical E2E credential was rejected by the exact disposable guest before WPF execution.'}
$credentialErrorResult=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Primary / Desktop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ObservationProvider $credentialErrorProvider -EvidencePath (Join-Path $credentialErrorDir 'observer.json')
Check ([string]$credentialErrorResult.outcome -eq 'TERMINAL_FAILURE' -and @($credentialErrorResult.transportRecoveryAttempts).Count -eq 0 -and [string]$credentialErrorResult.terminalReason -match 'LAB_CREDENTIAL_STALE') 'credential-labelled session failure remains terminal with zero transport retries'
# The actual guest-session failure formatter must not introduce new retry permission.
foreach($sessionError in @('Access is denied.','The credential is invalid.','Credential parameter conversion failed','Guest session establishment exceeded its finite 60-second open deadline.')){
    $safeFailure=& (Get-Module GuestSession) {param($message)try{throw $message}catch{New-DevFleetGuestSessionFailure -Failure $_ -AttemptCount 3}} $sessionError
    $safeProvider={param($state)throw $state.providerContext}
    $safeResult=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Primary / Desktop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ObservationProvider $safeProvider -ObservationProviderContext $safeFailure.Message
    Check ([string]$safeResult.outcome -eq 'TERMINAL_FAILURE' -and @($safeResult.transportRecoveryAttempts).Count -eq 0 -and [string]$safeResult.terminalReason -match [regex]::Escape($safeFailure.Data['failureCode'])) "safe $($safeFailure.Data['failureCode']) remains terminal with zero transport retries"
}
$m5TransportMessage='An error has occurred which PowerShell cannot handle. A remote session might have ended.'
foreach($m5Case in @('transient','persistent','credential-labelled')){
    $m5Dir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-m5-transport-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $m5Dir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($m5Dir)
    $global:DevFleetM5TransportClock=[datetime]'2026-01-01T00:00:00Z'
    $m5Clock={$value=[datetime]$global:DevFleetM5TransportClock;$global:DevFleetM5TransportClock=$value.AddSeconds(5);$value}
    $m5Provider={param($s)if($s.providerContext.mode-ceq'credential-labelled'){throw ('LAB_CREDENTIAL_STALE: '+$s.providerContext.message)};if($s.providerContext.mode-ceq'persistent'-or[int]$s.observationIndex-lt2){throw $s.providerContext.message};$s.providerContext.observation}
    $m5Context=[pscustomobject]@{mode=$m5Case;message=$m5TransportMessage;observation=(LifecycleObs @{})}
    $m5Result=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Primary / Desktop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -NoProgressBudgetSeconds 60 -AbsoluteBudgetSeconds 120 -ObservationProvider $m5Provider -ObservationProviderContext $m5Context -ClockProvider $m5Clock -SleepProvider {param($seconds)} -EvidencePath (Join-Path $m5Dir 'observer.json')
    $m5Expected=if($m5Case-ceq'transient'){2}elseif($m5Case-ceq'persistent'){3}else{0}
    $m5Outcome=if($m5Case-ceq'transient'){'NO_PROGRESS_TIMEOUT'}else{'TERMINAL_FAILURE'}
    Check ([string]$m5Result.outcome-ceq$m5Outcome-and@($m5Result.transportRecoveryAttempts).Count-eq$m5Expected) "observed M5 remoting error $m5Case respects the existing finite recovery policy"
}
$waitForeignCp=[pscustomobject]@{checkpointGeneration=2;generation=2;transactionId='c'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}
$waitCases=[ordered]@{
    'raw checkpoint object with false presence'=(CompletionSample @{checkpointPresent=$false;checkpoint=$waitForeignCp})
    'raw true presence with null checkpoint'=(CompletionSample @{checkpointPresent=$true;checkpoint=$null})
    'raw top-level generation'=(CompletionSample @{generation=1})
    'raw top-level checkpointGeneration'=(CompletionSample @{checkpointGeneration=1})
    'nested observation checkpoint/generation'=(CompletionSample @{observation=[pscustomobject]@{checkpointPresent=$true;checkpoint=[pscustomobject]@{generation=1;checkpointGeneration=1}}})
    'waiting-for-reboot state'=(CompletionSample @{state='waiting-for-reboot'})
    'terminal claim'=(CompletionSample @{terminalFailure=$true;failure='controlled terminal claim';status='TERMINAL_FAILURE'})
    'GUID generation'=(CompletionSample @{generation=([guid]::NewGuid()).ToString('D')})
    'malformed generation'=(CompletionSample @{generation='not-a-number'})
    'NEXT_REBOOT foreign binding'=(LifecycleObs @{checkpointPresent=$true;checkpoint=$waitForeignCp})
}
$deepSignal=[pscustomobject]@{generation=1};for($d=0;$d -lt 14;$d++){$deepSignal=[pscustomobject]@{nested=$deepSignal}};$deepSample=CompletionSample @{};$deepSample|Add-Member -NotePropertyName deepSignal -NotePropertyValue $deepSignal -Force;$waitCases['depth cutoff active signal']=$deepSample
foreach($waitCase in $waitCases.GetEnumerator()){$waitCaseResult=RunInjectedWait @($waitCase.Value) 60 120;Check ([string]$waitCaseResult.outcome -eq 'TERMINAL_FAILURE') "Wait $($waitCase.Key) fails closed";Check-WaitTerminalEvidence $waitCaseResult "Wait $($waitCase.Key)"}
# Execute the real lifecycle loop with all external effects injected. This is
# intentionally a local candidate/hash check and never opens a VM session.
$testExe=Join-Path $WorkspaceRoot 'outputs\DevFleet-Setup-v1.2.13-win-x64.exe';$testTar=Join-Path $WorkspaceRoot 'outputs\devfleet-v1.2.13.tar.gz';$exeItem=Get-Item -LiteralPath $testExe;$exeHash=(Get-FileHash -LiteralPath $testExe -Algorithm SHA256).Hash.ToLowerInvariant();$tarHash=(Get-FileHash -LiteralPath $testTar -Algorithm SHA256).Hash.ToLowerInvariant();$lifeRoot=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-life-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $lifeRoot -Force|Out-Null
$lifeContext=[pscustomobject]@{phaseId='LIFE-TEST';runDir=$lifeRoot;vmId=([guid]::NewGuid());vmName='test-disposable';candidate=[pscustomobject]@{candidate=[pscustomobject]@{path=$testExe;bytes=$exeItem.Length;sha256=$exeHash};tar=[pscustomobject]@{sha256=$tarHash};releaseVersion='1.2.13';installerVersion='1.4.1';releaseFingerprintId='test-release';toolingFingerprintId='test-tooling'};config=[pscustomobject]@{};phaseBudgetSeconds=60}
$lifeTrace=[System.Collections.Generic.List[string]]::new();$lifeTx='d'*32;$wpfCount=0;$global:DevFleetProductDispatchCount=0
$wpf = {
    param($s)
    $g=[int]$s.generation
    $produced=if($g -eq 0){1}else{$g+1}
    [void]$lifeTrace.Add("WPF:$produced")
    [pscustomobject]@{status='REAL E2E OBSERVER HANDOFF';guest=[pscustomobject]@{processId=0;role='Primary / Desktop'}}
}
$transition = {
    param($s)
    $g=[int]$s.priorGeneration+1
    if([int]$s.priorGeneration -eq 0){$global:DevFleetProductDispatchCount++}
    [void]$lifeTrace.Add("OBSERVE:$g")
    $cp=[pscustomobject]@{checkpointGeneration=$g;generation=$g;transactionId=$lifeTx;payloadSha256=$s.payloadSha256;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}
    if($g -le 3){
        [pscustomobject]@{outcome='NEXT_REBOOT';checkpointPresent=$true;checkpoint=$cp;observation=[pscustomobject]@{}}
    } else {
        [pscustomobject]@{outcome='COMPLETED';checkpointPresent=$false;checkpoint=$null;observation=[pscustomobject]@{matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true;installLedger=[pscustomobject]@{DevFleetVersion='1.2.13';InstallerVersion='1.4.1';PackageSha256=$s.payloadSha256;InstallationGeneration='11111111-1111-1111-1111-111111111111';WindowsIntegrationOwnershipPath='C:\ProgramData\DevFleetHostAgent\integration-ownership.json'};ownershipLedger=[pscustomobject]@{SchemaVersion=1;InstallationGeneration='11111111-1111-1111-1111-111111111111';ScheduledTasks=@();FirewallRules=@();Services=@()}}}
    }
}
$reboot = {
    param($s)
    [void]$lifeTrace.Add("REBOOT:$($s.generation)")
    [pscustomobject]@{bootIdentityChanged=$true}
}
$settle = {
    param($s)
    [void]$lifeTrace.Add("SETTLE:$($s.generation)")
    [pscustomobject]@{stable=$true}
}
$lifeResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $transition -RebootProvider $reboot -SettleProvider $settle
Check ([bool]$lifeResult.completionVerified) 'LIFE-01 real lifecycle loop reaches explicit completion authority'

# OAuth staging is owned by the complete product lifecycle, not by a WPF
# handoff that may return while the candidate is still executing.  This seam
# uses no VM or credential; it records the production cleanup callback order.
$handoffTrace=[System.Collections.Generic.List[string]]::new()
$handoffContext=[pscustomobject]@{phaseId='OAUTH-HANDOFF-CLEANUP';runDir=(Join-Path $lifeRoot 'oauth-handoff-cleanup');vmId=$lifeContext.vmId;vmName='test-disposable';candidate=$lifeContext.candidate;config=[pscustomobject]@{Tailscale=[pscustomobject]@{Authentication=[pscustomobject]@{Provider='OAuthClientSecretStore'}}};phaseBudgetSeconds=60;oauthCredentialCleanupRequired=$true}
$handoffWpf={param($s)[void]$handoffTrace.Add('WPF-HANDOFF');[pscustomobject]@{status='REAL E2E OBSERVER HANDOFF';guest=[pscustomobject]@{processId=0;role='Primary / Desktop'}}}
$handoffCompletion=CompletionSample @{};$handoffCompletion|Add-Member -NotePropertyName installLedger -NotePropertyValue ([pscustomobject]@{DevFleetVersion='1.2.13';InstallerVersion='1.4.1';PackageSha256=$lifeContext.candidate.tar.sha256;InstallationGeneration='55555555-5555-5555-5555-555555555555';WindowsIntegrationOwnershipPath='C:\ProgramData\DevFleetHostAgent\integration-ownership.json'}) -Force;$handoffCompletion|Add-Member -NotePropertyName ownershipLedger -NotePropertyValue ([pscustomobject]@{SchemaVersion=1;InstallationGeneration='55555555-5555-5555-5555-555555555555';ScheduledTasks=@();FirewallRules=@();Services=@()}) -Force
$handoffTransition={param($s)[void]$handoffTrace.Add('OBSERVE');$g=[int]$s.priorGeneration+1;if($g -eq 1){$cp=[pscustomobject]@{checkpointGeneration=1;generation=1;transactionId=('a'*32);payloadSha256=$s.payloadSha256;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'};[pscustomobject]@{outcome='NEXT_REBOOT';checkpointPresent=$true;checkpoint=$cp;observation=[pscustomobject]@{checkpointPresent=$true;checkpoint=$cp}}}else{[pscustomobject]@{outcome='COMPLETED';checkpointPresent=$false;checkpoint=$null;observation=$handoffCompletion}}}
$handoffReboot={param($s)[void]$handoffTrace.Add('REBOOT');[pscustomobject]@{bootIdentityChanged=$true}}
$handoffSettle={param($s)[void]$handoffTrace.Add('SETTLE');[pscustomobject]@{stable=$true}}
$handoffCleanup={param($ctx)[void]$handoffTrace.Add('CLEANUP');[pscustomobject]@{status='PASS'}}
$handoffResult=Invoke-ProductFreshInstallLifecycle -Context $handoffContext -Role 'Primary / Desktop' -WpfProvider $handoffWpf -TransitionProvider $handoffTransition -RebootProvider $handoffReboot -SettleProvider $handoffSettle -OAuthCredentialCleanupProvider $handoffCleanup
Check ([bool]$handoffResult.completionVerified -and ($handoffTrace -join ',') -eq 'WPF-HANDOFF,OBSERVE,REBOOT,SETTLE,WPF-HANDOFF,OBSERVE,CLEANUP') 'OAuth credential cleanup remains with the lifecycle owner after an observer handoff and runs after completion'
$failureHandoffTrace=[System.Collections.Generic.List[string]]::new()
$failureHandoffContext=$handoffContext|ConvertTo-Json -Depth 16|ConvertFrom-Json;$failureHandoffContext.phaseId='OAUTH-HANDOFF-CLEANUP-FAILURE';$failureHandoffContext.runDir=(Join-Path $lifeRoot 'oauth-handoff-cleanup-failure');$failureHandoffContext.oauthCredentialCleanupRequired=$true
$failureHandoffWpf={param($s)[void]$failureHandoffTrace.Add('WPF-HANDOFF');[pscustomobject]@{status='REAL E2E OBSERVER HANDOFF';guest=[pscustomobject]@{processId=0;role='Primary / Desktop'}}}
$failureHandoffTransition={param($s)[void]$failureHandoffTrace.Add('OBSERVE');[pscustomobject]@{outcome='NO_PROGRESS_TIMEOUT';checkpointPresent=$false;checkpoint=$null;observation=[pscustomobject]@{}}}
$failureHandoffCleanup={param($ctx)[void]$failureHandoffTrace.Add('CLEANUP');[pscustomobject]@{status='PASS'}}
$failureHandoffResult=Invoke-ProductFreshInstallLifecycle -Context $failureHandoffContext -Role 'Primary / Desktop' -WpfProvider $failureHandoffWpf -TransitionProvider $failureHandoffTransition -OAuthCredentialCleanupProvider $failureHandoffCleanup
Check ([string]$failureHandoffResult.status -eq 'TERMINAL_FAILURE' -and ($failureHandoffTrace -join ',') -eq 'WPF-HANDOFF,OBSERVE,CLEANUP') 'OAuth credential cleanup still runs after a terminal lifecycle handoff failure'
$matrixTx='e'*32;foreach($matrixKind in 0..3){$matrixWpf={param($s)ProviderForm $matrixKind @{status='REAL E2E OBSERVER HANDOFF';guest=(ProviderForm $matrixKind @{processId=0})}};$matrixTransition={param($s)if([int]$s.priorGeneration -eq 0){$matrixCp=ProviderForm $matrixKind @{checkpointGeneration=1;generation=1;transactionId=$matrixTx;payloadSha256=$s.payloadSha256;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'};ProviderForm $matrixKind @{outcome='NEXT_REBOOT';checkpointPresent=$true;checkpoint=$matrixCp;observation=(ProviderForm $matrixKind @{checkpointPresent=$true;checkpoint=$matrixCp})}}else{ProviderForm $matrixKind @{outcome='COMPLETED';checkpointPresent=$false;checkpoint=$null;observation=(ProviderForm $matrixKind @{matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true;progress=(ProviderForm $matrixKind @{checkpointGeneration=0});installLedger=(ProviderForm $matrixKind @{DevFleetVersion='1.2.13';InstallerVersion='1.4.1';PackageSha256=$s.payloadSha256;InstallationGeneration='22222222-2222-2222-2222-222222222222';WindowsIntegrationOwnershipPath='C:\ProgramData\DevFleetHostAgent\integration-ownership.json'});ownershipLedger=(ProviderForm $matrixKind @{SchemaVersion=1;InstallationGeneration='22222222-2222-2222-2222-222222222222';ScheduledTasks=@();FirewallRules=@();Services=@()})})}}};$matrixReboot={param($s)ProviderForm $matrixKind @{bootIdentityChanged=$true}};$matrixSettle={param($s)ProviderForm $matrixKind @{stable=$true}};$matrixResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $matrixWpf -TransitionProvider $matrixTransition -RebootProvider $matrixReboot -SettleProvider $matrixSettle;Check ([bool]$matrixResult.completionVerified) "provider representation matrix $($matrixKind+1)/4 executes WPF/transition/reboot/settlement contracts"}

# Producer-to-consumer integration: execute the production lifecycle, role
# resolver, waiter, collector normalization, stage allowlist, guest marker
# identity policy and completion verifier. Only external WPF/VM/transport I/O
# is replaced by local fixtures; the correct product names are never injected.
$fixtureConfig=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'automation\release-e2e\config\devfleet-e2e.defaults.json') -Raw|ConvertFrom-Json
$roleFixtureWpf={param($s)[pscustomobject]@{status='REAL E2E OBSERVER HANDOFF';guest=[pscustomobject]@{processId=0;role=[string]$s.role}}}
$roleFixtureRemote={
    param($s)
    $tx=[string]$s.context.transactionId;$completed=([datetime]$s.invocationStartUtc).AddSeconds(1).ToUniversalTime().ToString('o');$stageMarkers=@()
    foreach($target in @($s.targets)){$name=if([string]$target.kind -ceq 'vault'){'stage-vault.complete'}else{"stage-compute-$([string]$target.instanceName).complete"};$stageMarkers+=,[pscustomobject][ordered]@{name=$name;transactionId=$tx;payloadSha256=[string]$s.payloadSha256;action=[string]$s.action;role=[string]$s.roleKind;stage=$name.Substring(0,$name.Length-9);completedUtc=$completed}}
    $progress=[ordered]@{checkpointGeneration=if($s.transactionId){0}else{1};checkpointState=if($s.transactionId){''}else{'waiting-for-reboot'};completedStages=@();resumeStage=if($s.transactionId){''}else{'install'};stageMarkerSet='';guestProgressMarker=$null}
    if(-not $s.transactionId){$checkpoint=[pscustomobject][ordered]@{checkpointGeneration=1;generation=1;transactionId=$tx;payloadSha256=[string]$s.payloadSha256;action=[string]$s.action;role=[string]$s.role;state='waiting-for-reboot';completedStages=@();resumeStage='install'};return [pscustomobject][ordered]@{checkpointPresent=$true;checkpoint=$checkpoint;matchingConsumedReceipt=$false;installStateValid=$false;canonicalOwnershipValid=$false;authenticatedHealthOk=$false;terminalFailure=$false;stageMarkers=$stageMarkers;stageMarkerErrors=@();progress=$progress;timestampUtc=$completed}}
    $generation=[string]$s.context.installationGeneration
    return [pscustomobject][ordered]@{checkpointPresent=$false;checkpoint=$null;receipt=[pscustomobject]@{transactionId=$tx;payloadSha256=[string]$s.payloadSha256;action=[string]$s.action;role=[string]$s.role;consumedUtc=$completed};matchingConsumedReceipt=$true;installStateValid=$true;installLedger=[pscustomobject]@{DevFleetVersion='1.2.13';InstallerVersion='1.4.1';PackageSha256=[string]$s.payloadSha256;InstallationGeneration=$generation;WindowsIntegrationOwnershipPath='C:\ProgramData\DevFleetHostAgent\integration-ownership.json'};canonicalOwnershipValid=$true;ownershipLedger=[pscustomobject]@{SchemaVersion=1;InstallationGeneration=$generation;ScheduledTasks=@();FirewallRules=@();Services=@()};authenticatedHealthOk=$true;terminalFailure=$false;stageMarkers=$stageMarkers;stageMarkerErrors=@();progress=$progress;timestampUtc=$completed}
}
$roleFixtureGuest={
    param($s)
    $reads=@();$updated=(Get-Date).ToUniversalTime().ToString('o')
    foreach($target in @($s.targets)){$marker=[ordered]@{schemaVersion=1;transactionId=[string]$s.context.transactionId;payloadSha256=[string]$s.payloadSha256;sequence=9;component='bootstrap';state='COMPLETED';updatedUtc=$updated;packageVersion=if([string]$target.nodeRole -ceq 'vault'){'vault'}else{'1.2.13'};nodeRole=[string]$target.nodeRole};$reads+=,[pscustomobject]@{instanceName=[string]$target.instanceName;text=($marker|ConvertTo-Json -Compress);exitCode=0;timedOut=$false}}
    [pscustomobject]@{status='READS_COLLECTED';error='';inventoryExitCode=0;probedInstances=@($s.targets.instanceName);markerReads=$reads}
}
$roleFixtureReboot={param($s)[pscustomobject]@{bootIdentityChanged=$true}}
$roleFixtureSettle={param($s)[pscustomobject]@{stable=$true}}
foreach($fixtureRole in @('Primary / Desktop','Laptop / Surrogate')){
    $roleDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-role-chain-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $roleDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($roleDir)
    $fixtureTx=if($fixtureRole -ceq 'Primary / Desktop'){'1'*32}else{'2'*32};$fixtureGeneration=if($fixtureRole -ceq 'Primary / Desktop'){'33333333-3333-3333-3333-333333333333'}else{'44444444-4444-4444-4444-444444444444'}
    $fixtureContext=[pscustomobject]@{workspaceRoot=$identityFixture;phaseId='ROLE-BOUND-CHAIN';runDir=$roleDir;vmId=([guid]::NewGuid());vmName='test-disposable';candidate=$lifeContext.candidate;config=$fixtureConfig;phaseBudgetSeconds=60}
    $adapterContext=[pscustomobject]@{transactionId=$fixtureTx;installationGeneration=$fixtureGeneration}
    $fixtureResult=Invoke-ProductFreshInstallLifecycle -Context $fixtureContext -Role $fixtureRole -WpfProvider $roleFixtureWpf -RebootProvider $roleFixtureReboot -SettleProvider $roleFixtureSettle -RemoteObservationProvider $roleFixtureRemote -GuestMarkerReadProvider $roleFixtureGuest -ObservationAdapterContext $adapterContext
    $fixtureComplete=([bool]$fixtureResult.completionVerified -and [string]$fixtureResult.role -ceq $fixtureRole -and [string]$fixtureResult.transactionId -ceq $fixtureTx);Check $fixtureComplete "production role-bound lifecycle reaches exact completion for $fixtureRole (status=$([string]$fixtureResult.status); error=$([string]$fixtureResult.error))"
    $observerRef=if($fixtureComplete){@($fixtureResult.evidenceReferences|Where-Object{[string]$_.kind -ceq 'observer-summary'}|Select-Object -Last 1)}else{@()};$observerPath=if($observerRef){[string]$observerRef[0].path}else{''};if(-not $observerPath -or -not(Test-Path -LiteralPath $observerPath)){$debugPath=@(Get-ChildItem -LiteralPath $roleDir -Filter 'product-lifecycle-observer-generation-*.json' -File -Recurse -ErrorAction SilentlyContinue|Select-Object -Last 1);if($debugPath){$observerPath=$debugPath[0].FullName}else{$debugText='';Check $false "production role-bound lifecycle emits observer evidence for $fixtureRole$debugText";continue}};$observerRecord=Get-Content -LiteralPath $observerPath -Raw|ConvertFrom-Json;$observedNames=@($observerRecord.observation.progress.guestProgressMarkers.instanceName)
    if($fixtureRole -ceq 'Primary / Desktop'){Check ((@($observedNames)-join ',') -ceq 'devfleet-primary' -and @($observerRecord.observation.stageMarkers.name) -notcontains 'stage-vault.complete') 'Desktop production chain observes Primary only'}else{Check ((@($observedNames)-join ',') -ceq 'devfleet-failover,devfleet-vault' -and @($observerRecord.observation.stageMarkers.name) -contains 'stage-vault.complete') 'Laptop production chain observes exact Failover plus Vault'}
}

$laptopTargets=@($laptopIdentity.targets);$currentTx='a'*32;$currentPayload='b'*64;$validUpdated='2026-01-01T00:00:00Z'
function New-RawRoleMarker([string]$Instance,[string]$NodeRole,[string]$Component='bootstrap',[string]$Transaction=$currentTx,[string]$Payload=$currentPayload,[string]$JsonOverride=''){$text=if($JsonOverride){$JsonOverride}else{([ordered]@{schemaVersion=1;transactionId=$Transaction;payloadSha256=$Payload;sequence=1;component=$Component;state='COMPLETED';updatedUtc=$validUpdated;packageVersion=if($NodeRole -ceq 'vault'){'vault'}else{'1.2.13'};nodeRole=$NodeRole}|ConvertTo-Json -Compress)};[pscustomobject]@{instanceName=$Instance;text=$text;exitCode=0;timedOut=$false}}
function Resolve-RawRoleReads([object[]]$Reads){& $realPhaseModule {param($remote,$targets,$tx,$payload) Resolve-DevFleetRoleBoundGuestMarkerReads -RemoteResult $remote -Targets $targets -TransactionId $tx -PayloadSha256 $payload} ([pscustomobject]@{status='READS_COLLECTED';error='';inventoryExitCode=0;probedInstances=@($Reads.instanceName);markerReads=$Reads}) $laptopTargets $currentTx $currentPayload}
$wrongRoleReads=Resolve-RawRoleReads @((New-RawRoleMarker 'devfleet-failover' 'primary'),(New-RawRoleMarker 'devfleet-vault' 'vault'))
$cleanupNameReads=Resolve-RawRoleReads @((New-RawRoleMarker 'DevFleet-E2E-Linux-01' 'surrogate'))
$unknownStepReads=Resolve-RawRoleReads @((New-RawRoleMarker 'devfleet-failover' 'surrogate' 'unknownStep'),(New-RawRoleMarker 'devfleet-vault' 'vault'))
$staleReads=Resolve-RawRoleReads @((New-RawRoleMarker 'devfleet-failover' 'surrogate' 'bootstrap' ('c'*32)),(New-RawRoleMarker 'devfleet-vault' 'vault'))
$wrongPayloadReads=Resolve-RawRoleReads @((New-RawRoleMarker 'devfleet-failover' 'surrogate' 'bootstrap' $currentTx ('c'*64)),(New-RawRoleMarker 'devfleet-vault' 'vault'))
$malformedReads=Resolve-RawRoleReads @((New-RawRoleMarker 'devfleet-failover' 'surrogate' 'bootstrap' $currentTx $currentPayload '{not-json'),(New-RawRoleMarker 'devfleet-vault' 'vault'))
Check (-not [bool]$wrongRoleReads.requiredMarkersValid -and @($wrongRoleReads.readResults.status) -contains 'ROLE_MISMATCH') 'wrong-role guest marker cannot satisfy Laptop product identity'
Check (-not [bool]$cleanupNameReads.requiredMarkersValid -and @($cleanupNameReads.rejectedReadNames) -contains 'DevFleet-E2E-Linux-01') 'harness cleanup name is rejected as a product marker source'
Check (-not [bool]$unknownStepReads.requiredMarkersValid -and @($unknownStepReads.readResults.status) -contains 'MALFORMED') 'unknown guest bootstrap step cannot satisfy product identity'
Check (-not [bool]$staleReads.requiredMarkersValid -and @($staleReads.readResults.status) -contains 'IDENTITY_MISMATCH') 'stale transaction guest marker cannot satisfy product identity'
Check (-not [bool]$wrongPayloadReads.requiredMarkersValid -and @($wrongPayloadReads.readResults.status) -contains 'IDENTITY_MISMATCH') 'wrong-payload guest marker cannot satisfy product identity'
Check (-not [bool]$malformedReads.requiredMarkersValid -and @($malformedReads.readResults.status) -contains 'MALFORMED') 'malformed guest marker cannot satisfy product identity'
$falseCompletion=CompletionSample @{};$falseCompletion|Add-Member -NotePropertyName productRoleIdentityValid -NotePropertyValue $false -Force
Check ((Get-DurableProgressClassification -Observation $falseCompletion -PriorCheckpoint $prior) -eq 'TERMINAL_FAILURE') 'completion cannot revive invalid role-bound marker evidence'
$stageFixture=[pscustomobject]@{stageMarkers=@([pscustomobject]@{name='stage-compute-wrong.complete';transactionId=$currentTx;payloadSha256=$currentPayload;action='FreshInstall';role='Laptop';stage='stage-compute-wrong';completedUtc='2026-01-01T00:00:01Z'});stageMarkerErrors=@([pscustomobject]@{name='stage-known-rejected.complete';error='original collector failure'},[pscustomobject]@{error='historical collector failure without a name'})}
$resolvedStage=& $realPhaseModule {param($value,$tx,$payload) Resolve-DevFleetLifecycleStageMarkerObservation -Observation $value -AllowedPattern (Get-DevFleetLifecycleStageMarkerPattern 'devfleet-failover' 'devfleet-vault') -ExpectedStageRole 'Laptop' -TransactionId $tx -PayloadSha256 $payload -Action 'FreshInstall' -InvocationStartUtc '2026-01-01T00:00:00Z'} $stageFixture $currentTx $currentPayload
$normalizedStage=& $realPhaseModule {param($value) ConvertTo-NormalizedLifecycleObservation $value} $resolvedStage
Check (@($normalizedStage.stageMarkerErrors).Count -eq 3 -and [string]$normalizedStage.stageMarkerErrors[0].name -ceq 'stage-known-rejected.complete' -and [string]$normalizedStage.stageMarkerErrors[1].name -ceq '' -and [string]$normalizedStage.stageMarkerErrors[2].name -ceq 'stage-compute-wrong.complete') 'collector normalization preserves original errors and observed rejected names without reconstructing missing names'
$authorityTerminalRejected=$false;try{$terminalAuthoritySample=CompletionSample @{terminalFailure=$true;failure='constructor terminal claim'};New-ProductLifecycleCompletionAuthority -Context $lifeContext -Candidate $lifeContext.candidate -Role 'Primary / Desktop' -TransactionId $lifeTx -PayloadSha256 $lifeContext.candidate.tar.sha256 -Observation $terminalAuthoritySample -Legs @()|Out-Null}catch{$authorityTerminalRejected=$true}
Check $authorityTerminalRejected 'completion authority constructor rejects terminal claim before PASS'
$missingLedgerRejected=$false;try{New-ProductLifecycleCompletionAuthority -Context $lifeContext -Candidate $lifeContext.candidate -Role 'Primary / Desktop' -TransactionId $lifeTx -PayloadSha256 $lifeContext.candidate.tar.sha256 -Observation (CompletionSample @{}) -Legs @()|Out-Null}catch{$missingLedgerRejected=$true}
Check $missingLedgerRejected 'completion authority rejects missing install/ownership ledgers without raw strict-mode failure'
$terminalRebootCalls=0;$terminalWpf={param($s)[pscustomobject]@{status='REAL E2E OBSERVER HANDOFF';guest=[pscustomobject]@{processId=0}}};$terminalTransition={param($s)[pscustomobject]@{outcome='COMPLETED';observation=(CompletionSample @{terminalFailure=$true;failure='two-step terminal claim'})}};$terminalReboot={param($s)$script:terminalRebootCalls++;[pscustomobject]@{bootIdentityChanged=$true}};$terminalLifecycleResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $terminalWpf -TransitionProvider $terminalTransition -RebootProvider $terminalReboot -SettleProvider $settle
Check ([string]$terminalLifecycleResult.status -eq 'TERMINAL_FAILURE' -and $terminalRebootCalls -eq 0) 'two-step lifecycle terminal claim rejects before any reboot'
$mismatchCheckpoint=[ordered]@{checkpointGeneration=1;generation=1;transactionId=$lifeTx;payloadSha256=$lifeContext.candidate.tar.sha256;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'};$mismatchTransitions=@([pscustomobject]@{outcome='NEXT_REBOOT';checkpointPresent=$false;checkpoint=$mismatchCheckpoint;observation=[pscustomobject]@{}},[ordered]@{outcome='NEXT_REBOOT';checkpointPresent=$false;checkpoint=$mismatchCheckpoint;observation=[ordered]@{}},[pscustomobject]@{outcome='NEXT_REBOOT';checkpointPresent=$true;checkpoint=$null;observation=[pscustomobject]@{}},[ordered]@{outcome='NEXT_REBOOT';checkpointPresent=$true;checkpoint=$null;observation=[ordered]@{checkpointPresent=$false;checkpoint=$mismatchCheckpoint}})
foreach($mismatchTransition in $mismatchTransitions){$mismatchCalls=0;$mismatchWpf={param($s)[pscustomobject]@{status='REAL E2E OBSERVER HANDOFF';guest=[pscustomobject]@{processId=0}}};$mismatchReboot={param($s)$script:mismatchCalls++;[pscustomobject]@{bootIdentityChanged=$true}};$mismatchResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $mismatchWpf -TransitionProvider {param($s)$mismatchTransition} -RebootProvider $mismatchReboot -SettleProvider $settle;Check ([string]$mismatchResult.status -eq 'TERMINAL_FAILURE' -and $mismatchCalls -eq 0) 'top-level transition checkpoint presence mismatch fails before reboot'}
Check (($lifeTrace -join ',') -eq 'WPF:1,OBSERVE:1,REBOOT:1,SETTLE:1,WPF:2,OBSERVE:2,REBOOT:2,SETTLE:2,WPF:3,OBSERVE:3,REBOOT:3,SETTLE:3,WPF:4,OBSERVE:4') 'LIFE-01/03 actual loop orders three product reboots and final post-gen3 observation'
Check ($lifeTrace.IndexOf('OBSERVE:1') -lt $lifeTrace.IndexOf('REBOOT:1') -and $lifeTrace.IndexOf('OBSERVE:2') -lt $lifeTrace.IndexOf('REBOOT:2')) 'LIFE-02 NEXT_REBOOT is preserved over raw WPF status'
Check ($lifeTrace -contains 'REBOOT:3' -and $lifeTrace -contains 'OBSERVE:4' -and $lifeTrace -notcontains 'REBOOT:4') 'LIFE-03 generation 3 reboot is allowed but generation 4 is not'
$gen4Rejected=$false;$gen4Transition={param($s);$cp=[pscustomobject]@{checkpointGeneration=4;generation=4;transactionId=$lifeTx;payloadSha256=$s.payloadSha256;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'};[pscustomobject]@{outcome='NEXT_REBOOT';checkpointPresent=$true;checkpoint=$cp;observation=[pscustomobject]@{}}};try{$gen4Result=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $gen4Transition -RebootProvider $reboot -SettleProvider $settle;$gen4Rejected=([string]$gen4Result.status -eq 'TERMINAL_FAILURE')}catch{$gen4Rejected=$true}
Check ($gen4Rejected) 'LIFE-03 generation 4 checkpoint is rejected fail-closed'
$badShapeRejected=$false;$badShapeTransition={param($s);$cp=[pscustomobject]@{checkpointGeneration='not-a-number';generation='not-a-number';transactionId=$lifeTx;payloadSha256=$s.payloadSha256;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'};[pscustomobject]@{outcome='NEXT_REBOOT';checkpointPresent=$true;checkpoint=$cp;observation=[pscustomobject]@{}}};try{$badShapeResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $badShapeTransition -RebootProvider $reboot -SettleProvider $settle;$badShapeRejected=([string]$badShapeResult.status -eq 'TERMINAL_FAILURE')}catch{$badShapeRejected=$true}
Check ($badShapeRejected) 'real-shaped malformed checkpoint generation fails closed with terminal evidence'
$nullWpf={param($s)$null};$nullWpfResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $nullWpf -TransitionProvider $transition -RebootProvider $reboot -SettleProvider $settle
$nullTransition={param($s)$null};$nullTransitionResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $nullTransition -RebootProvider $reboot -SettleProvider $settle
$errorReboot={param($s)throw 'controlled reboot failure'};$errorRebootResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $transition -RebootProvider $errorReboot -SettleProvider $settle
$nullSettlement={param($s)$null};$nullSettlementResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $transition -RebootProvider $reboot -SettleProvider $nullSettlement
Check ([string]$nullWpfResult.status -eq 'TERMINAL_FAILURE') 'WpfProvider null fails closed'
Check ([string]$nullTransitionResult.status -eq 'TERMINAL_FAILURE') 'TransitionProvider null fails closed'
Check ([string]$errorRebootResult.status -eq 'TERMINAL_FAILURE') 'RebootProvider error fails closed'
Check ([string]$nullSettlementResult.status -eq 'TERMINAL_FAILURE') 'SettlementProvider null fails closed'
function Check-FullLifecycleTerminalEvidence([psobject]$Result,[string]$Name){
    $terminal=[string]$Result.evidencePath;$dir=if($terminal){Split-Path -Parent $terminal}else{''};$journal=if($dir){Join-Path $dir 'product-lifecycle-progress.jsonl'}else{''};$current=if($dir){Join-Path $dir 'product-lifecycle-progress-current.json'}else{''};$providerDetail=if($dir){Join-Path $dir 'product-lifecycle-provider-failure.json'}else{''};$pathsPresent=($terminal -and (Test-Path -LiteralPath $terminal) -and (Test-Path -LiteralPath $journal) -and (Test-Path -LiteralPath $current) -and (Test-Path -LiteralPath $providerDetail));$journalMatches=$false;if($pathsPresent){try{$last=@(Get-Content -LiteralPath $journal|Where-Object{$_})[-1]|ConvertFrom-Json;$journalMatches=([string]$last.event -eq 'TERMINAL' -and [string]$last.terminalReason -eq 'TERMINAL_FAILURE')}catch{}};Check ($pathsPresent -and $journalMatches) "$Name writes terminal/provider/current/journal evidence with matching terminal reason"
}
Check-FullLifecycleTerminalEvidence $nullWpfResult 'WpfProvider null'
Check-FullLifecycleTerminalEvidence $nullTransitionResult 'TransitionProvider null'
Check-FullLifecycleTerminalEvidence $errorRebootResult 'RebootProvider exception'
Check-FullLifecycleTerminalEvidence $nullSettlementResult 'SettlementProvider null'
$sessionFailureDir=Join-Path $lifeRoot 'session-failure-causal-evidence'
$sessionFailureError=[InvalidOperationException]::new('LAB_GUEST_AUTHENTICATION_REJECTED: guest authentication was rejected; credential freshness remains unverified. Bounded attempts: 3.')
$sessionFailureError.Data['failureCode']='LAB_GUEST_AUTHENTICATION_REJECTED';$sessionFailureError.Data['attemptCount']=3;$sessionFailureError.Data['authenticationOutcome']='REJECTED';$sessionFailureError.Data['credentialFreshness']='UNVERIFIED';$sessionFailureError.Data['nativeErrorCode']=1326
& (Get-Module Invoke-RealProductPhase) {param($failure) function script:Connect-DevFleetGuest { throw $script:SessionFixtureFailure };$script:SessionFixtureFailure=$failure} $sessionFailureError
$sessionFailureContext=[pscustomobject]@{phaseId='SESSION-FAILURE-CAUSAL';runDir=$sessionFailureDir;workspaceRoot=$WorkspaceRoot;vmId=$lifeContext.vmId;vmName=$lifeContext.vmName;candidate=$lifeContext.candidate;config=(Get-Content -Raw (Join-Path $WorkspaceRoot 'source\config\devfleet.config.json')|ConvertFrom-Json);phaseBudgetSeconds=60}
$sessionFailureWpf={param($s)[pscustomobject]@{status='REAL E2E OBSERVER HANDOFF';guest=[pscustomobject]@{processId=0;role='Primary / Desktop'}}}
$sessionFailureCallError='';try{$sessionFailureResult=Invoke-ProductFreshInstallLifecycle -Context $sessionFailureContext -Role 'Primary / Desktop' -WpfProvider $sessionFailureWpf}catch{$sessionFailureCallError=$_.Exception.Message}
Check ([string]::IsNullOrEmpty($sessionFailureCallError) -and $null -ne $sessionFailureResult) 'real lifecycle caller returns a terminal result for session-open failure'
if($sessionFailureCallError){Write-Output "session failure fixture invocation: $sessionFailureCallError"}
$sessionFailureTerminal=Get-ChildItem -LiteralPath $sessionFailureDir -Filter 'product-lifecycle-terminal.json' -File -Recurse|Select-Object -First 1
$sessionFailureEvidence=if($sessionFailureTerminal){Get-Content -Raw $sessionFailureTerminal.FullName|ConvertFrom-Json}else{[pscustomobject]@{safeFailure=$null;error=''}}
Check ([string]$sessionFailureResult.provider -eq 'TransitionObserver' -and [string]$sessionFailureEvidence.safeFailure.failureCode -eq 'LAB_GUEST_AUTHENTICATION_REJECTED' -and [int]$sessionFailureEvidence.safeFailure.nativeErrorCode -eq 1326 -and [int]$sessionFailureEvidence.safeFailure.attemptCount -eq 3) 'real guest caller to observer to terminal evidence preserves allowlisted native failure metadata'
Check (([string]$sessionFailureEvidence.error -notmatch 'DEMO_SECRET|password|credentialFreshness=') -and [string]$sessionFailureEvidence.safeFailure.credentialFreshness -eq 'UNVERIFIED') 'terminal failure evidence contains only safe fields and no raw exception text'
$unknownSessionFailureDir=Join-Path $lifeRoot 'session-failure-unknown-evidence'
& (Get-Module Invoke-RealProductPhase) {$script:SessionFixtureFailure=[InvalidOperationException]::new('deserialized remote authentication/session failure')}
$unknownSessionFailureContext=$sessionFailureContext.PSObject.Copy();$unknownSessionFailureContext.runDir=$unknownSessionFailureDir;$unknownSessionFailureContext.phaseId='SESSION-FAILURE-UNKNOWN'
$unknownSessionFailureResult=Invoke-ProductFreshInstallLifecycle -Context $unknownSessionFailureContext -Role 'Primary / Desktop' -WpfProvider $sessionFailureWpf
$unknownSessionFailureTerminal=Get-ChildItem -LiteralPath $unknownSessionFailureDir -Filter 'product-lifecycle-terminal.json' -File -Recurse|Select-Object -First 1
$unknownSessionFailureEvidence=if($unknownSessionFailureTerminal){Get-Content -Raw $unknownSessionFailureTerminal.FullName|ConvertFrom-Json}else{[pscustomobject]@{safeFailure=$null}}
Check ([string]$unknownSessionFailureResult.status -eq 'TERMINAL_FAILURE' -and $null -eq $unknownSessionFailureEvidence.safeFailure) 'wrapped or deserialized session errors remain terminal with cause UNKNOWN'
& (Get-Module Invoke-RealProductPhase) {Remove-Item Function:Connect-DevFleetGuest -ErrorAction SilentlyContinue;$script:SessionFixtureFailure=$null}
$completedObservation=[pscustomobject]@{matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true;progress=[ordered]@{}}
$completedVariants=[ordered]@{
    'valid checkpoint object'=[pscustomobject]@{checkpoint=$next.checkpoint}
    'checkpointPresent false with object'=[pscustomobject]@{observation=[pscustomobject]@{checkpointPresent=$false;checkpoint=$next.checkpoint}}
    'top-level generation only'=[pscustomobject]@{generation=1}
    'top-level checkpointGeneration only'=[pscustomobject]@{checkpointGeneration=1}
    'embedded observation checkpoint/generation'=[pscustomobject]@{observation=[pscustomobject]@{checkpointPresent=$true;checkpoint=[pscustomobject]@{generation=1;checkpointGeneration=1;state='waiting-for-reboot'}}}
    'waiting-for-reboot state'=[pscustomobject]@{observation=[pscustomobject]@{state='waiting-for-reboot'}}
}
$variantTraceStart=$lifeTrace.Count;foreach($variant in $completedVariants.GetEnumerator()){$variantTransition={param($s)$result=[ordered]@{outcome='COMPLETED';observation=$completedObservation};foreach($p in $thisVariant.PSObject.Properties){$result[$p.Name]=$p.Value};[pscustomobject]$result};$thisVariant=$variant.Value;$variantResult=Invoke-ProductFreshInstallLifecycle -Context $lifeContext -Role 'Primary / Desktop' -WpfProvider $wpf -TransitionProvider $variantTransition -RebootProvider $reboot -SettleProvider $settle;Check ([string]$variantResult.status -eq 'TERMINAL_FAILURE') "COMPLETED $($variant.Key) is rejected";Check-FullLifecycleTerminalEvidence $variantResult "COMPLETED $($variant.Key)"}
Check (@($lifeTrace|Select-Object -Skip $variantTraceStart|Where-Object{$_ -match '^REBOOT:'}).Count -eq 0) 'presence/checkpoint inconsistencies fail before any reboot provider call'
Check ((Get-ProductLifecycleConsumerMode -PhaseId 'REBOOT-RESUME') -eq 'SYNTHETIC_THEN_PRODUCT' -and (Get-ProductLifecycleConsumerMode -PhaseId 'LINUX') -eq 'PRODUCT_ONLY' -and (Get-ProductLifecycleConsumerMode -PhaseId 'SURROGATE-DISPOSABLE') -eq 'PRODUCT_ONLY' -and (Get-ProductLifecycleConsumerMode -PhaseId 'MAINTENANCE-READY-PROVISION') -eq 'PRODUCT_ONLY' -and (Get-ProductLifecycleConsumerMode -PhaseId 'DEPENDENCY-MATRIX') -eq 'PRODUCT_ONLY') 'LIFE-04/LIFE-05 consumer dispatch proves synthetic independence'
Check ([string]$lifeResult.phase -eq 'LIFE-TEST' -and [string]$lifeResult.invocationId -and (Test-Path -LiteralPath ([string]$lifeResult.evidencePath))) 'LIFE-04 invocation identity and isolated authority evidence are exposed'
$lifeEvidenceDir=Split-Path -Parent ([string]$lifeResult.evidencePath);$observerEvidence=Join-Path $lifeEvidenceDir 'product-lifecycle-observer-generation-1.json';$generationEvidence=Join-Path $lifeEvidenceDir 'product-lifecycle-generation-1.json'
Check ((Test-Path -LiteralPath $observerEvidence) -and (Test-Path -LiteralPath $generationEvidence) -and ([IO.Path]::GetFullPath($observerEvidence) -cne [IO.Path]::GetFullPath($generationEvidence)) -and @($lifeResult.evidenceReferences|Where-Object{$_.kind -eq 'observer-summary' -and $_.sha256}).Count -gt 0 -and @($lifeResult.evidenceReferences|Where-Object{$_.kind -eq 'lifecycle-generation' -and $_.sha256}).Count -gt 0) 'observer summary and lifecycle-generation evidence remain isolated with hash references'
$dispatchTrace=[System.Collections.Generic.List[string]]::new()
$syntheticProvider={param($s);[void]$dispatchTrace.Add('SYNTHETIC');[pscustomobject]@{status='PASS';productLifecycleTouched=$false}}
$dispatchContext=[pscustomobject]@{phaseId='REBOOT-RESUME';runDir=$lifeRoot;vmId=$lifeContext.vmId;vmName=$lifeContext.vmName;candidate=$lifeContext.candidate;config=$lifeContext.config;phaseBudgetSeconds=60;lifecycleWpfProvider=$wpf;lifecycleTransitionProvider=$transition;lifecycleRebootProvider=$reboot;lifecycleSettleProvider=$settle;syntheticRebootProvider=$syntheticProvider}
$dispatchBefore=$global:DevFleetProductDispatchCount;$dispatchResult=Invoke-ProductLifecycleConsumer -Context $dispatchContext
Check ([string]$dispatchResult.contract -eq 'synthetic-probe-then-pure-product-lifecycle' -and $dispatchTrace[0] -eq 'SYNTHETIC' -and ($global:DevFleetProductDispatchCount-$dispatchBefore) -eq 1) 'LIFE-04 actual REBOOT-RESUME dispatch invokes synthetic then exactly one product lifecycle'
$pureBefore=$dispatchTrace.Count;$pureProductBefore=$global:DevFleetProductDispatchCount
foreach($purePhase in @('LINUX','SURROGATE-DISPOSABLE','DEPENDENCY-MATRIX','MAINTENANCE-READY-PROVISION')){$dispatchContext.phaseId=$purePhase;[void](Invoke-ProductLifecycleConsumer -Context $dispatchContext)}
Check ($dispatchTrace.Count -eq $pureBefore -and ($global:DevFleetProductDispatchCount-$pureProductBefore) -eq 4) 'LIFE-05 actual Linux/surrogate/dependency/maintenance dispatch each invokes product once and synthetic zero'
$maintenanceDispatch=[pscustomobject]@{phaseId='MAINTENANCE-READY';runDir=$lifeRoot;vmId=$lifeContext.vmId;vmName=$lifeContext.vmName;candidate=$lifeContext.candidate;config=$lifeContext.config;phaseBudgetSeconds=60;lifecycleWpfProvider=$wpf;lifecycleTransitionProvider=$transition;lifecycleRebootProvider=$reboot;lifecycleSettleProvider=$settle};Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\FullRelease.psm1') -Force;$maintenanceDispatchResult=Invoke-MaintenanceReadyProductLifecycle -WorkspaceRoot $WorkspaceRoot -Context $maintenanceDispatch
Check ([string]$maintenanceDispatchResult.phase -eq 'MAINTENANCE-READY-PROVISION' -and [bool]$maintenanceDispatchResult.completionVerified) 'FullRelease maintenance provisioning uses dedicated pure product dispatch'
Check ($source -match "'FRESH-INSTALL-WPF'" -and $source -match "Invoke-SupportedFreshInstallLifecycle[\s\S]{0,180}-CompleteLifecycle" -and $source -match 'FRESH-INSTALL-WPF requires verified lifecycle completion') 'LIFE-05 FRESH-INSTALL-WPF cannot promote a non-terminal lifecycle boundary'
} finally {
    foreach($dir in @($script:testEvidenceDirs)){if($dir -and (Test-Path -LiteralPath $dir)){$resolved=[IO.Path]::GetFullPath($dir);if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^devfleet-(?:observer-[a-z0-9-]+|role-chain)-[a-f0-9]{32}$'){throw 'Observer fixture cleanup path rejected.'};Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}}
    if($lifeRoot -and (Test-Path -LiteralPath $lifeRoot)){$resolved=[IO.Path]::GetFullPath($lifeRoot);if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^devfleet-life-[a-f0-9]{32}$'){throw 'Lifecycle fixture cleanup path rejected.'};Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
}
[pscustomobject]@{status=if($failed.Count -eq 0){'PASS'}else{'FAIL'};passed=$passed;failures=@($failed)}|ConvertTo-Json -Depth 5
if($failed.Count){exit 1}
