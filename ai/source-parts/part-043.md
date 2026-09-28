# DevFleet source part 043

Full-source UTF-8 byte interval [1953000, 1999500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 88eca0f82fd632812dcfc9a3913a42c7ef734c04f01ecce5f3dd9ef0e502119c

<!-- BEGIN SOURCE SLICE -->
unDir=(Join-Path $identityFixture 'audit/automation-harness/runs/behavioral-product-compute-identity');config=[pscustomobject]@{NestedLinux=[pscustomobject]@{Name='DevFleet-E2E-Linux-01'}}}
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
$errorEvidenceDir=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-observer-error-{0}" -f ([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Path $errorEvidenceDir -Force|Out-Null;[void]$script:testEvidenceDirs.Add($errorEvidenceDir);$errorProvider={param($s)throw 'controlled provider failure'};$errorResult=Wait-DevFleetProductLifecycleTransition -Session ([pscustomobject]@{}) -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role 'Primary / Desktop' -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ObservationP