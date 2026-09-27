# DevFleet source part 043

Full-source UTF-8 byte interval [1953000, 1999500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 205ceffb1915307f80ab4dbaf19f8ea5dd6a3b8967e7174eea46a9eaf95edcb7

<!-- BEGIN SOURCE SLICE -->
2E credential was rejected by the exact disposable guest before WPF execution.'}
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

```


## FILE: automation/release-e2e/tests/Test-MaintenanceFallbackHealth.ps1

SHA256: 26c4b4a811d3107f8e533fd8ed460cf825f77fc7aafd5155f1ad646abe516e8c | Bytes: 4264 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot,[string]$ReportPath)
$ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
if(-not$WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
$module=Get-Module Invoke-RealProductPhase
$results=& $module {
    # Inert typed identity only: no session constructor, connection or methods.
    # Every external remoting/clock/file boundary below is replaced.
    $script:FallbackSession=[Runtime.Serialization.FormatterServices]::GetUninitializedObject([System.Management.Automation.Runspaces.PSSession])
    function script:Get-Date {return $script:FallbackClock}
    function script:Start-Sleep {param($Seconds)$script:FallbackClo