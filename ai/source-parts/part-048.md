# DevFleet source part 048

Full-source UTF-8 byte interval [2185500, 2232000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 80c856c2058c84918a5241c6931e4af5b9f70227c83aec57308ca8c34c978159

<!-- BEGIN SOURCE SLICE -->
       $pass = $snapshot.status -eq 'OBSERVED' -and $ordinaryRecord.Count -eq 1 -and $ordinaryRecord[0].tail -match 'IndentationError' -and $ordinaryRecord[0].tail.Length -le 16384 -and $pairingRecord.Count -eq 1 -and $pairingRecord[0].tail -match 'PAIRING_STARTED' -and $pairingRecord[0].tail -match 'BROWSER_LAUNCH_ACCEPTED' -and $pairingRecord[0].tail -match 'PAIRING_FAILED' -and $pairingRecord[0].tailOnly -eq $false -and $pairingRecord[0].headLineLimit -eq 32 -and $serialized -notmatch 'private multiword|private-token'
        } elseif ($case -eq 'stale') {
            $pass = $snapshot.status -eq 'NO_RECENT_LOG' -and $snapshot.records.Count -eq 0
        } else {
            $pass = $snapshot.status -eq 'UNAVAILABLE' -and $snapshot.records.Count -eq 0
        }
        if ($case -eq 'timeout') { $pass = $pass -and $watch.Elapsed.TotalSeconds -lt 7 }
        $results.Add(@{ case = $case; pass = [bool]$pass; status = $snapshot.status; elapsedSeconds = [math]::Round($watch.Elapsed.TotalSeconds, 2) })
    }
    @{transactionId=('a'*32);payloadSha256=('b'*64)}|ConvertTo-Json|Set-Content -LiteralPath $active
    'IndentationError: unexpected indent'|Set-Content -LiteralPath $log
    $remote={param($s) [pscustomobject]@{terminalFailure=$false;stageMarkers=@();stageMarkerErrors=@();progress=@{checkpointState='';productChildInstances=@()};timestampUtc=[datetime]::UtcNow.ToString('o')}}
    $marker={param($s)
        $reads=@(foreach($target in $s.targets){
            $value=@{schemaVersion=1;transactionId=$s.transactionId;payloadSha256=$s.payloadSha256;sequence=16;component=if($target.kind-eq'vault'){'serviceConfiguration'}else{'serviceAndFirewallFinalization'};state='FAILED';updatedUtc=[datetime]::UtcNow.ToString('o');packageVersion=if($target.kind-eq'vault'){'vault'}else{'1.2.13'};nodeRole=$target.nodeRole}
            [pscustomobject]@{instanceName=$target.instanceName;text=($value|ConvertTo-Json -Compress);exitCode=0;timedOut=$false}
        })
        [pscustomobject]@{status='READS_COLLECTED';error='';inventoryExitCode=0;probedInstances=@($s.targets.instanceName);markerReads=$reads}
    }
    foreach($entry in @(@{role='Primary / Desktop';capture='OBSERVED'},@{role='Laptop / Surrogate';capture='OBSERVED'},@{role='Primary / Desktop';capture='UNAVAILABLE'})){
        $role=$entry.role
        if($entry.capture-eq'UNAVAILABLE'){@{transactionId=('c'*32);payloadSha256=('b'*64)}|ConvertTo-Json|Set-Content -LiteralPath $active}
        $observation=& $module {
            param($Role,$Remote,$Marker,$Since)
            $p=@{Session='fixture';TransactionId=('a'*32);PayloadSha256=('b'*64);Role=$Role;ExpectedDevFleetVersion='1.2.13';ExpectedInstallerVersion='1.4.1';InvocationStartUtc=$Since;ObservationTimeoutSeconds=20;ExpectedNestedLinuxName='DevFleet-E2E-Linux-01';RemoteObservationProvider=$Remote;GuestMarkerReadProvider=$Marker}
            $p.ExpectedComputeInstanceName=if($Role-eq'Primary / Desktop'){'devfleet-primary'}else{'devfleet-failover'}
            if($Role-eq'Laptop / Surrogate'){$p.ExpectedVaultInstanceName='devfleet-vault'}
            Get-ProductLifecycleObservation @p
        } $role $remote $marker $since
        $pass=$observation.terminalFailure-and$observation.terminalReason-match'reported FAILED'-and$observation.failureLogSnapshot.status-eq$entry.capture
        if($entry.capture-eq'OBSERVED'){$pass=$pass-and$observation.failureLogSnapshot.records[0].tail-match'IndentationError'}else{$pass=$pass-and$observation.failureLogSnapshot.records.Count-eq0}
        $results.Add(@{case=$role+' terminal observer capture '+$entry.capture;pass=[bool]$pass;status=$observation.failureLogSnapshot.status})
        $summaryPath=Join-Path $root ('wait-'+$results.Count+'/observer.json')
        $waited=& $module {
            param($Observation,$Role,$Evidence,$Since)
            Wait-DevFleetProductLifecycleTransition -Session 'fixture' -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role $Role -BudgetSeconds 15 -PollSeconds 1 -ObservationTimeoutSeconds 10 -InvocationStartUtc $Since -EvidencePath $Evidence -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ObservationProvider {param($s) $s.providerContext} -ObservationProviderContext $Observation
        } $observation $role $summaryPath $since
        $saved=Get-Content -LiteralPath $summaryPath -Raw|ConvertFrom-Json
        $journal=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $summaryPath) 'product-lifecycle-progress.jsonl') -Raw
        $pass=$waited.outcome-eq'TERMINAL_FAILURE'-and$saved.observation.failureLogSnapshot.status-eq$entry.capture-and$journal-match'failureLogSnapshot'
        $results.Add(@{case=$role+' wait journal retains '+$entry.capture;pass=[bool]$pass;status=$waited.outcome})
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if([IO.Path]::GetDirectoryName($resolved)-cne$tempParent-or[IO.Path]::GetFileName($resolved)-notmatch'^devfleet-failure-logs-[0-9a-f]{32}$'){throw 'Fixture cleanup escaped its owner boundary.'}
    if(Test-Path -LiteralPath $resolved){if((Get-Item -LiteralPath $resolved).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Fixture root is a reparse point.'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}
$results|ConvertTo-Json -Depth 4
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Product failure-log capture qualification failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) native failure-log capture checks"

```


## FILE: automation/release-e2e/tests/Test-ProductLaunchObserverDeferral.ps1

SHA256: 8543a7358c2932c66808e4b95e285784a32e5e3f2f11351e19c6a5fd6cf20634 | Bytes: 7096 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force
$module=Get-Module Invoke-RealProductPhase
$checks=[Collections.Generic.List[object]]::new()
$remote={param($s)$s.context.observation}
$guest={
    param($s)
    $s.context.probeCalls++
    $reads=@(foreach($target in $s.targets){
        $marker=@{schemaVersion=1;transactionId=$s.transactionId;payloadSha256=$s.payloadSha256;sequence=9;component='bootstrap';state='COMPLETED';updatedUtc='2026-01-01T00:00:06Z';packageVersion=if($target.nodeRole-ceq'vault'){'vault'}else{'1.2.13'};nodeRole=$target.nodeRole}
        [pscustomobject]@{instanceName=$target.instanceName;text=($marker|ConvertTo-Json -Compress);exitCode=0;timedOut=$false}
    })
    [pscustomobject]@{status='READS_COLLECTED';error='';inventoryExitCode=0;probedInstances=@($s.targets.instanceName);markerReads=$reads}
}
foreach($case in @('desktop-launch','laptop-compute-launch','laptop-vault-launch','started','launched','ready','payload-transferred','payload-extracted','complete','no-native-child','foreign-parent','stale-child','unbound-transaction','wrong-payload','wrong-stage-role','wrong-instance-stage','duplicate-pid','foreign-native-path','parent-cycle','stale-transaction','existing-terminal')){
    $role=if($case-like'laptop-*'){'Laptop / Surrogate'}else{'Primary / Desktop'}
    $kind=if($case-like'laptop-*'){'Laptop'}else{'Desktop'}
    $compute=if($kind-ceq'Laptop'){'devfleet-failover'}else{'devfleet-primary'}
    $prefix=if($case-ceq'laptop-vault-launch'){'stage-vault'}else{"stage-compute-$compute"}
    $stage=[pscustomobject]@{name="$prefix-instance-absent.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-absent";completedUtc='2026-01-01T00:00:04Z'}
    $candidate=[pscustomobject]@{pid=100;parentPid=99;name='DevFleet-Setup.exe';commandClass='DevFleet-Setup';startTimeUtc='2026-01-01T00:00:01Z'}
    $bootstrap=[pscustomobject]@{pid=101;parentPid=100;name='pwsh.exe';commandClass='Bootstrap-Install';startTimeUtc='2026-01-01T00:00:02Z'}
    $installer=[pscustomobject]@{pid=102;parentPid=101;name='pwsh.exe';commandClass='Install-DevFleet';startTimeUtc='2026-01-01T00:00:03Z'}
    $native=[pscustomobject]@{pid=103;parentPid=102;name='multipass.exe';path='C:\Program Files\Multipass\bin\multipass.exe';commandClass='multipass';startTimeUtc='2026-01-01T00:00:05Z'}
    $observation=[pscustomobject]@{candidateProcess=$candidate;activeTransaction=[pscustomobject]@{transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;preparedUtc='2026-01-01T00:00:02Z'};stageMarkers=@($stage);stageMarkerErrors=@();terminalFailure=$false;progress=[pscustomobject]@{productChildInstances=@($candidate,$bootstrap,$installer,$native);guestProgressMarkerStatus='DEFERRED'}}
    switch($case){
        'started' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-instance-started.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-started";completedUtc='2026-01-01T00:00:06Z'}}
        'launched' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-instance-launched.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-launched";completedUtc='2026-01-01T00:00:06Z'}}
        'ready' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-instance-ready.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-ready";completedUtc='2026-01-01T00:00:06Z'}}
        'payload-transferred' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-payload-transferred.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-payload-transferred";completedUtc='2026-01-01T00:00:06Z'}}
        'payload-extracted' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-payload-extracted.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-payload-extracted";completedUtc='2026-01-01T00:00:06Z'}}
        'complete' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage=$prefix;completedUtc='2026-01-01T00:00:06Z'}}
        'no-native-child' {$observation.progress.productChildInstances=@($candidate,$bootstrap,$installer)}
        'foreign-parent' {$native.parentPid=900}
        'stale-child' {$native.startTimeUtc='2025-12-31T23:59:59Z'}
        'unbound-transaction' {$observation.activeTransaction.transactionId='c'*32}
        'wrong-payload' {$stage.payloadSha256='c'*64}
        'wrong-stage-role' {$stage.role='Laptop'}
        'wrong-instance-stage' {$stage.name='stage-compute-foreign-instance-absent.complete';$stage.stage='stage-compute-foreign-instance-absent'}
        'duplicate-pid' {$observation.progress.productChildInstances+=,$native}
        'foreign-native-path' {$native.path='C:\unrelated\multipass.exe'}
        'parent-cycle' {$installer.parentPid=103}
        'stale-transaction' {$observation.activeTransaction.preparedUtc='2025-12-31T23:59:59Z'}
        'existing-terminal' {$observation.terminalFailure=$true}
    }
    $context=[pscustomobject]@{observation=$observation;probeCalls=0}
    $parameters=@{Session=[pscustomobject]@{};TransactionId=('a'*32);PayloadSha256=('b'*64);Action='FreshInstall';Role=$role;PriorGeneration=1;MaxGeneration=3;CandidateProcessId=100;ExpectedDevFleetVersion='1.2.13';ExpectedInstallerVersion='1.4.1';ObservationTimeoutSeconds=10;InvocationStartUtc='2026-01-01T00:00:00Z';ExpectedComputeInstanceName=$compute;RemoteObservationProvider=$remote;GuestMarkerReadProvider=$guest;ObservationAdapterContext=$context}
    if($kind-ceq'Laptop'){$parameters.ExpectedVaultInstanceName='devfleet-vault'}
    $result=& $module {param($p)Get-ProductLifecycleObservation @p} $parameters
    $expectDeferred=$case-in@('desktop-launch','laptop-compute-launch','laptop-vault-launch')
    $pass=if($expectDeferred){$context.probeCalls-eq0-and$result.progress.guestProgressMarkerStatus-ceq'DEFERRED_PRODUCT_LAUNCH'-and-not$result.productRoleIdentityValid}else{$context.probeCalls-eq1-and$result.progress.guestProgressMarkerStatus-ceq'VALID'}
    if($case-in@('wrong-payload','wrong-stage-role','wrong-instance-stage')){$pass=$pass-and@($result.stageMarkerErrors).Count-eq1}
    $checks.Add([pscustomobject]@{case=$case;pass=[bool]$pass;probeCalls=$context.probeCalls;status=$result.progress.guestProgressMarkerStatus})
}
[pscustomobject]@{status=if(@($checks|Where-Object{-not$_.pass}).Count){'FAIL'}else{'PASS'};passed=@($checks|Where-Object{$_.pass}).Count;total=$checks.Count;checks=@($checks);vmOperations=0}|ConvertTo-Json -Depth 5
if(@($checks|Where-Object{-not$_.pass}).Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-RealUseAcceptancePhase.ps1

SHA256: 7d005da688720961d3a40d7182dee22ea146080d382043a726c6eab6cec04c7c | Bytes: 29495 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $WorkspaceRoot 'automation/release-e2e/modules/RealUseAcceptance.psm1'
Import-Module $modulePath -Force -DisableNameChecking
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Evidence.psm1') -Force -DisableNameChecking
$checks = [Collections.Generic.List[object]]::new()

function Check([string]$Name, [bool]$Pass) { $checks.Add([pscustomobject]@{name=$Name;pass=$Pass}) }
function Rejects([scriptblock]$Action) { try { & $Action; return $false } catch { return $true } }
function CaptureError([scriptblock]$Action) { try { & $Action | Out-Null; return '' } catch { return [string]$_.Exception.Message } }
function Clone($Value) { return ($Value | ConvertTo-Json -Depth 32 | ConvertFrom-Json) }

$temp = Join-Path $env:TEMP "DevFleet-RealUse-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $runId = 'fullrelease-real-use-fixture-20260916T000000Z'
    $runDir = Join-Path $temp 'run'; New-Item -ItemType Directory -Path $runDir | Out-Null
    $candidatePath = Join-Path $temp 'candidate.exe'; [IO.File]::WriteAllText($candidatePath,'candidate',[Text.UTF8Encoding]::new($false))
    $runnerDir = Join-Path $temp 'automation/release-e2e/modules/executors'; New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
    $runnerPath = Join-Path $runnerDir 'Invoke-RealUseAcceptance.py'; [IO.File]::WriteAllText($runnerPath,"#!/usr/bin/env python3`n",[Text.UTF8Encoding]::new($false))
    $exeHash = (Get-FileHash $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $tarHash = '2' * 64; $releaseHash = '3' * 64; $toolingHash = '4' * 64; $shippingHash = '5' * 64
    $repositoryHead = '6' * 40; $candidateCommit = '7' * 40; $transaction = '8' * 32; $invocation = '9' * 32
    $candidate = [pscustomobject][ordered]@{
        repositoryHead=$repositoryHead;gitCommit=$candidateCommit;shippingInputIdentity=$shippingHash;releaseFingerprintId=$releaseHash;toolingFingerprintId=$toolingHash
        candidate=[pscustomobject]@{path=$candidatePath;sha256=$exeHash;bytes=(Get-Item $candidatePath).Length}
        tar=[pscustomobject]@{path=(Join-Path $temp 'candidate.tar.gz');sha256=$tarHash;bytes=1}
    }
    $targets = @(
        [pscustomobject]@{instanceName='devfleet-failover';nodeRole='surrogate';kind='compute'},
        [pscustomobject]@{instanceName='devfleet-vault';nodeRole='vault';kind='vault'}
    )
    $lifeDir = Join-Path $runDir "lifecycle-SURROGATE-DISPOSABLE-$invocation"; New-Item -ItemType Directory -Path $lifeDir | Out-Null
    $authorityPath = Join-Path $lifeDir 'product-lifecycle-completion-authority.json'
    $authority = [ordered]@{status='REAL E2E PASS';contract='product-lifecycle-completion-authority';transactionId=$transaction;invocationId=$invocation;payloadSha256=$tarHash;role='Laptop / Surrogate';completionVerified=$true;authenticatedHealth=$true;guest=[ordered]@{roleEvidence=[ordered]@{requiredTargets=$targets}}}
    Write-EvidenceJson -Path $authorityPath -Value $authority
    $product = [pscustomobject][ordered]@{status='REAL E2E PASS';phase='SURROGATE-DISPOSABLE';contract='product-lifecycle-completion-authority';transactionId=$transaction;invocationId=$invocation;payloadSha256=$tarHash;role='Laptop / Surrogate';completionVerified=$true;candidate=$candidate;guest=[pscustomobject]@{roleEvidence=[pscustomobject]@{requiredTargets=$targets}};evidencePath=$authorityPath}
    $records = @([ordered]@{id='SURROGATE-DISPOSABLE';status='PASS';error=$null;evidence=[ordered]@{executor=[ordered]@{status='REAL E2E PASS';phase='SURROGATE-DISPOSABLE';product=$product}}})
    Write-EvidenceJson -Path (Join-Path $runDir 'fullrelease-phase-records.json') -Value $records
    $context = [pscustomobject][ordered]@{runId=$runId;phaseId='REAL-USE-ACCEPTANCE';vmName='DevFleet-E2E-Test';vmId='11111111-1111-1111-1111-111111111111';runDir=$runDir;workspaceRoot=$temp;candidate=$candidate;config=[pscustomobject]@{RealUseAcceptance=[pscustomobject]@{TimeoutSeconds=36000}}}
    $candidateTuple=[pscustomobject][ordered]@{repositoryHead=$repositoryHead;candidateCommit=$candidateCommit;shippingInputIdentity=$shippingHash;releaseFingerprintId=$releaseHash;toolingFingerprintId=$toolingHash;exeSha256=$exeHash;tarSha256=$tarHash}
    $deploymentId='22222222-2222-2222-2222-222222222222';$computeNodeId='33333333-3333-3333-3333-333333333333';$primaryNodeId='55555555-5555-5555-5555-555555555555';$vaultNodeId='66666666-6666-6666-6666-666666666666'
    $pairingPath=Join-Path $runDir 'real-use-primary-pairing.json'
    $pairing=[ordered]@{schemaVersion=1;contract='devfleet-real-use-primary-pairing-v1';status='PASS';runId=$runId;phaseId='FRESH-INSTALL-WPF';candidate=$candidateTuple;lifecycle=[ordered]@{transactionId=('a'*32);invocationId=('b'*32);payloadSha256=$tarHash;role='Primary / Desktop'};encryptedBundle=[ordered]@{sha256=('c'*64);bytes=256;format='DFENV001'};primary=[ordered]@{deploymentId=$deploymentId;nodeId=$primaryNodeId;nodeName='devfleet-primary';nodeRole='primary';registrationState='coordinator'};sensitiveValuesPersisted=$false}
    Write-EvidenceJson -Path $pairingPath -Value $pairing;$pairingHash=(Get-FileHash $pairingPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $joinPath=Join-Path $runDir 'real-use-cluster-join.json'
    $join=[ordered]@{schemaVersion=1;contract='devfleet-real-use-cluster-join-v1';status='PASS';runId=$runId;phaseId='REAL-USE-ACCEPTANCE';candidate=$candidateTuple;surrogateLifecycle=[ordered]@{transactionId=$transaction;invocationId=$invocation;payloadSha256=$tarHash;role='Laptop / Surrogate'};primaryCapture=[ordered]@{path=$pairingPath;sha256=$pairingHash;encryptedBundleSha256=('c'*64)};primary=[ordered]@{deploymentId=$deploymentId;nodeId=$primaryNodeId;nodeName='devfleet-primary';nodeRole='primary'};laptop=[ordered]@{deploymentId=$deploymentId;nodeId=$computeNodeId;nodeName='DevFleet-E2E-Test';nodeRole='surrogate';coordinatorNodeId=$primaryNodeId;registrationState='joined'};compute=[ordered]@{deploymentId=$deploymentId;nodeId=$computeNodeId;nodeName='devfleet-failover';nodeRole='surrogate';coordinatorNodeId=$primaryNodeId;registrationState='joined'};vault=[ordered]@{deploymentId=$deploymentId;nodeId=$vaultNodeId;nodeName='devfleet-vault';nodeRole='vault'};sensitiveValuesPersisted=$false}
    Write-EvidenceJson -Path $joinPath -Value $join;$joinHash=(Get-FileHash $joinPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $context|Add-Member -NotePropertyName realUseClusterJoin -NotePropertyValue ([pscustomobject][ordered]@{evidence=[pscustomobject]$join;evidencePath=$joinPath;evidenceSha256=$joinHash})

    $assertions = [ordered]@{
        U01=@('authenticatedDashboard','templateCreated','identityBound','assetsPresent','credentialsNotLogged')
        U02=@('startCompleted','healthCompleted','testCompleted','smokeOutputObserved','uiBackendContainerAgree')
        U03=@('stopCompleted','restartCompleted','serviceRestartObserved','sameProjectAndData','noDuplicateWriter','noPendingOperations','healthRecovered')
        U04=@('immediateBackupVerified','vaultUploadVerified','backupBeforeQuarantine','quarantineReversible','foreignCollisionRejected','collisionPreserved','restoreCompleted','contentRecovered')
        U05=@('vaultCopyCompleted','copyIdentityBound','copyContentRecovered','originalUnchanged','copyStartRejected','securityStartRejected','foreignLeaseStartRejected','originalUsable','onlyIntendedOwnerStarts')
    }
    $providerBody = {
        param($request)
        $execution = [ordered]@{role='Laptop / Surrogate';vmName=$request.vmName;vmId=$request.vmId;computeInstanceName=$request.computeInstanceName;vaultInstanceName=$request.vaultInstanceName;deploymentId=$request.deploymentId;nodeId=$request.nodeId;nodeName=$request.computeInstanceName;transactionId=$request.transactionId;invocationId=$request.invocationId;surrogateEvidenceSha256=$request.surrogateEvidenceSha256}
        $input = [pscustomobject][ordered]@{schemaVersion=1;runId=$request.runId;deadlineUtc=$request.deadlineUtc;runnerSha256=$request.runnerSha256;candidate=$request.candidate;execution=[pscustomobject]$execution;paths=[pscustomobject]@{workspaces='/home/devrunner/workspaces';quarantine='/home/devrunner/.devfleet-quarantine';runtimeRoot='/var/lib/devfleet/runtime'};baseUrl='http://127.0.0.1:8787'}
        $reportExecution = [ordered]@{}; foreach($name in $execution.Keys){$reportExecution[$name]=$execution[$name]};$reportExecution.uiTransport='authenticated-http-form';$reportExecution.browserJavascriptExercised=$false
        $prepareJourneys = @(); foreach($id in @('U01','U02','U03','U04','U05')){$status=switch($id){'U01'{'PASS'}'U02'{'PASS'}'U03'{'IN_PROGRESS'}default{'NOT_RUN'}};$fixed=[ordered]@{};if($status-eq'PASS'){foreach($name in $assertions[$id]){$fixed[$name]=$true}};$prepareJourneys+=,[pscustomobject][ordered]@{id=$id;status=$status;assertions=[pscustomobject]$fixed;observations=[pscustomobject]@{}}}
        $finalJourneys = @(); foreach($id in @('U01','U02','U03','U04','U05')){$fixed=[ordered]@{};foreach($name in $assertions[$id]){$fixed[$name]=$true};$finalJourneys+=,[pscustomobject][ordered]@{id=$id;status='PASS';assertions=[pscustomobject]$fixed;observations=[pscustomobject]@{evidence='allowlisted'}}}
        $operations=@();foreach($number in 1..5){$operations+=,[pscustomobject][ordered]@{id="op-$number";kind='health';project='df-accept-fixture';state='completed';expectedState='completed';route='/projects/df-accept-fixture/health';httpStatus=303;renderedState='completed';smokeOutputObserved=($number-eq 2)}}
        $fixture=[pscustomobject][ordered]@{slug='df-accept-fixture';projectId='44444444-4444-4444-4444-444444444444';sentinelSha256=('a'*64);originalPath='/home/devrunner/workspaces/df-accept-fixture';recoveredPath='/home/devrunner/workspaces/df-accept-fixture-recovered-20260916-abcdef12'}
        $common=[ordered]@{schemaVersion=1;contract='devfleet-real-use-acceptance-v1';runId=$request.runId;phaseId='REAL-USE-ACCEPTANCE';candidate=$request.candidate;execution=[pscustomobject]$reportExecution;runnerSha256=$request.runnerSha256;startedAtUtc=[datetime]::UtcNow.AddSeconds(-2).ToString('o');finishedAtUtc=[datetime]::UtcNow.AddSeconds(-1).ToString('o');deadlineUtc=$request.deadlineUtc;operations=$operations;fixture=$fixture;failure=$null;cleanupFailure=$null}
        $prepare=$common|ConvertTo-Json -Depth 32|ConvertFrom-Json;$prepare|Add-Member -NotePropertyName stage -NotePropertyValue 'prepare';$prepare|Add-Member -NotePropertyName status -NotePropertyValue 'PREPARED';$prepare|Add-Member -NotePropertyName journeys -NotePropertyValue $prepareJourneys;$prepare|Add-Member -NotePropertyName cleanup -NotePropertyValue ([pscustomobject]@{status='NOT_RUN';ownedOnly=$true;resources=@();errors=@();vaultSnapshots='RETAINED_APPEND_ONLY_IN_DISPOSABLE_VAULT'})
        $resume=$common|ConvertTo-Json -Depth 32|ConvertFrom-Json;$resume|Add-Member -NotePropertyName stage -NotePropertyValue 'resume';$resume|Add-Member -NotePropertyName status -NotePropertyValue 'PASS';$resume|Add-Member -NotePropertyName journeys -NotePropertyValue $finalJourneys;$resume|Add-Member -NotePropertyName cleanup -NotePropertyValue ([pscustomobject]@{status='PASS';ownedOnly=$true;resources=@([pscustomobject]@{kind='project';path='/home/devrunner/workspaces/df-accept-fixture';status='REMOVED'});errors=@();vaultSnapshots='RETAINED_APPEND_ONLY_IN_DISPOSABLE_VAULT'})
        [pscustomobject][ordered]@{input=$input;preflight=[pscustomobject]@{laptopInstalled=$true;failoverReady=$true;vaultReady=$true;brokerReady=$true;tailscaleReady=$true;secretFilePolicy=$true;credentialBoundary=$true};stage=[pscustomobject]@{l1Sha256=$request.runnerSha256;l2Sha256=$request.runnerSha256;inputSha256=('b'*64);onlyRunnerStaged=$true;l1Path="C:\Users\Public\DevFleet-E2E\$($request.runId)\REAL-USE-ACCEPTANCE\Invoke-RealUseAcceptance.py";ownedRootsRemoved=$true};prepareReport=$prepare;prepareExitCode=0;restart=[pscustomobject]@{unit='devfleet.service';invocationChanged=$true;otherUnitsRestarted=$false};resumeReport=$resume;resumeExitCode=0;cleanupReport=$null;cleanupExitCode=$null;ownedRootRemoved=$true}
    }
    $provider = $providerBody.GetNewClosure()

    $binding = Get-RealUseAcceptanceSurrogateBinding -Context $context
    Check 'immediate Surrogate authority binds the same run, transaction, candidate, Failover, and Vault' ($binding.runId -ceq $runId -and $binding.transactionId -ceq $transaction -and $binding.invocationId -ceq $invocation -and $binding.computeInstanceName -ceq 'devfleet-failover' -and $binding.vaultInstanceName -ceq 'devfleet-vault' -and $binding.surrogateEvidenceSha256 -match '^[0-9a-f]{64}$')
    $result = Invoke-RealUseAcceptancePhase -Context $context -TransportProvider $provider
    Check 'provider-driven phase reaches native REAL E2E PASS without VM operations' ([string]$result.status -ceq 'REAL E2E PASS' -and [string]$result.phase -ceq 'REAL-USE-ACCEPTANCE' -and -not [bool]$result.internalPromotionAllowed)
    $badEvidence=@();foreach($name in @('binding','prepare','report','summary')){$pathName="${name}Path";$hashName="${name}Sha256";$path=$result.evidence.$pathName;$hash=$result.evidence.$hashName;if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()-cne$hash){$badEvidence+=$name}}
    Check 'phase writes four hash-bound evidence records' ($badEvidence.Count -eq 0)
    Check 'FullRelease phase validator consumes the durable report and hashes' (Assert-RealUseAcceptancePhaseEvidence -PhaseResult $result -Context $context)
    Check 'native preflight records the credential boundary without credential detail' ($result.preflight.credentialBoundary -is [bool] -and [bool]$result.preflight.credentialBoundary)
    $weakBoundary=Clone $result;$weakBoundary.preflight.credentialBoundary=$false
    Check 'FullRelease rejects an unproven credential boundary' (Rejects {Assert-RealUseAcceptancePhaseEvidence -PhaseResult $weakBoundary -Context $context|Out-Null})

    $sampleRequest=[pscustomobject]@{runId=$runId;vmName=$context.vmName;vmId=$context.vmId;candidate=$binding.candidate;computeInstanceName=$binding.computeInstanceName;vaultInstanceName=$binding.vaultInstanceName;deploymentId=$binding.deploymentId;nodeId=$binding.nodeId;transactionId=$transaction;invocationId=$invocation;surrogateEvidenceSha256=$binding.surrogateEvidenceSha256;runnerSha256=(Get-FileHash $runnerPath).Hash.ToLowerInvariant();deadlineUtc=[datetime]::UtcNow.AddMinutes(10).ToString('o')}
    $input = $null; $sample = & $provider $sampleRequest;$input=$sample.input
    Check 'validator accepts exact U01-U05 and owned cleanup PASS' (Assert-RealUseAcceptanceReport -Report $sample.resumeReport -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass)
    $unjoined=Clone $input;$unjoined.execution.deploymentId=''
    Check 'input validator fails before mutation for a legitimate but unjoined blank deployment identity' (Rejects {Assert-RealUseAcceptanceInput -Input $unjoined -Request $sampleRequest|Out-Null})
    $missing = Clone $sample.resumeReport; $missing.journeys=@($missing.journeys|Where-Object id -ne U05)
    Check 'validator rejects missing U05' (Rejects {Assert-RealUseAcceptanceReport -Report $missing -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass|Out-Null})
    $weakAssertions = Clone $sample.resumeReport; $weakAssertions.journeys[0].assertions.PSObject.Properties.Remove('assetsPresent')
    Check 'validator rejects incomplete fixed assertion sets' (Rejects {Assert-RealUseAcceptanceReport -Report $weakAssertions -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass|Out-Null})
    $mismatch = Clone $sample.resumeReport; $mismatch.candidate.toolingFingerprintId='c'*64
    Check 'validator rejects candidate tuple drift' (Rejects {Assert-RealUseAcceptanceReport -Report $mismatch -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass|Out-Null})
    $secret = Clone $sample.resumeReport; $secret.journeys[0].observations|Add-Member -NotePropertyName password -NotePropertyValue 'not-allowed'
    Check 'validator rejects secret-shaped evidence fields' (Rejects {Assert-RealUseAcceptanceReport -Report $secret -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass|Out-Null})
    $unclean = Clone $sample.resumeReport; $unclean.cleanup.status='BLOCKED';$unclean.cleanup.errors=@('RESOURCE_REMAINS')
    Check 'validator rejects incomplete cleanup' (Rejects {Assert-RealUseAcceptanceReport -Report $unclean -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass|Out-Null})
    $wrongChannel = Clone $sample.resumeReport; $wrongChannel.execution.browserJavascriptExercised=$true
    Check 'validator rejects a substituted UI execution channel' (Rejects {Assert-RealUseAcceptanceReport -Report $wrongChannel -Input $input -ExpectedStage resume -AllowedStatus @('PASS') -RequirePass|Out-Null})
    $earlyBlocked=Clone $sample.prepareReport;$earlyBlocked.status='BLOCKED';$earlyBlocked.fixture=[pscustomobject]@{};$earlyBlocked.failure=[pscustomobject]@{code='DASHBOARD_LOGIN_FAILED';journey='U01'};$earlyBlocked.journeys[0].status='BLOCKED';$earlyBlocked.cleanup.status='BLOCKED';$earlyBlocked.cleanup.errors=@('DASHBOARD_LOGIN_FAILED')
    Check 'full early BLOCKED report accepts a truthful partial fixture for durable diagnostics' (Assert-RealUseAcceptanceReport -Report $earlyBlocked -Input $input -ExpectedStage prepare -AllowedStatus @('BLOCKED'))

    $minimalBlockedProvider={
        param($request)
        $value=&$provider $request
        $value.prepareReport=[pscustomobject][ordered]@{schemaVersion=1;contract='devfleet-real-use-acceptance-v1';status='BLOCKED';stage='prepare';phaseId='REAL-USE-ACCEPTANCE';failure=[pscustomobject]@{code='DRIVER_INITIALIZATION_FAILED'};cleanup=[pscustomobject]@{status='NOT_RUN';ownedOnly=$true}}
        $value.prepareExitCode=1;$value.restart=$null;$value.resumeReport=$null;$value.resumeExitCode=$null
        $value.cleanupReport=[pscustomobject][ordered]@{schemaVersion=1;contract='devfleet-real-use-acceptance-v1';status='BLOCKED';stage='cleanup';phaseId='REAL-USE-ACCEPTANCE';failure=[pscustomobject]@{code='DRIVER_INITIALIZATION_FAILED'};cleanup=[pscustomobject]@{status='NOT_RUN';ownedOnly=$true}};$value.cleanupExitCode=1
        return $value
    }.GetNewClosure()
    $minimalError=CaptureError {Invoke-RealUseAcceptancePhase -Context $context -TransportProvider $minimalBlockedProvider}
    $durableMinimal=Get-Content (Join-Path $runDir 'real-use-acceptance-prepare.json') -Raw|ConvertFrom-Json;$durableMinimalCleanup=Get-Content (Join-Path $runDir 'real-use-acceptance-cleanup.json') -Raw|ConvertFrom-Json
    Check 'minimal initialization BLOCKED envelope and cleanup are persisted before phase failure' ($minimalError -match 'prepare did not reach' -and [string]$durableMinimal.failure.code -ceq 'DRIVER_INITIALIZATION_FAILED' -and [string]$durableMinimalCleanup.stage -ceq 'cleanup')

    $blockedResumeProvider={
        param($request)
        $value=&$provider $request;$blocked=$value.resumeReport|ConvertTo-Json -Depth 32|ConvertFrom-Json;$blocked.status='BLOCKED';$blocked.failure=[pscustomobject]@{code='RESUME_ACCEPTANCE_FAILED';journey='U03'};$blocked.journeys[2].status='BLOCKED';$blocked.cleanup.status='PASS';$value.resumeReport=$blocked;$value.resumeExitCode=1
        $cleanup=$blocked|ConvertTo-Json -Depth 32|ConvertFrom-Json;$cleanup.stage='cleanup';$value.cleanupReport=$cleanup;$value.cleanupExitCode=1
        return $value
    }.GetNewClosure()
    $resumeError=CaptureError {Invoke-RealUseAcceptancePhase -Context $context -TransportProvider $blockedResumeProvider}
    $durableBlocked=Get-Content (Join-Path $runDir 'real-use-acceptance-report.json') -Raw|ConvertFrom-Json;$durableCleanup=Get-Content (Join-Path $runDir 'real-use-acceptance-cleanup.json') -Raw|ConvertFrom-Json
    Check 'BLOCKED resume and explicit cleanup evidence are durable before PASS enforcement' ($resumeError -match 'resume did not reach PASS' -and $resumeError -match 'cleanupEvidence=' -and [string]$durableBlocked.failure.code -ceq 'RESUME_ACCEPTANCE_FAILED' -and [string]$durableCleanup.stage -ceq 'cleanup')

    $realUseModule=Get-Module | Where-Object {[string]$_.Path -eq [string](Resolve-Path $modulePath)} | Select-Object -First 1
    $bridgeText=& $realUseModule { (Get-RealUseAcceptanceSecurePwsh7Bridge).ToString() }
    $bridgeChild={param($request,[Security.SecureString]$bundlePassphrase)Write-Host 'fixture product status';[pscustomobject]@{runtimeMajor=$PSVersionTable.PSVersion.Major;fixtureLength=$bundlePassphrase.Length;marker=[string]$request.marker}}.ToString()
    $bridgeText64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bridgeText));$bridgeChild64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bridgeChild))
    $windowsPowerShellBody=@'
$ErrorActionPreference='Stop'
$bridge=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__BRIDGE__'))
$child=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CHILD__'))
$secure=ConvertTo-SecureString 'public-fixture-passphrase-12345' -AsPlainText -Force
try{$value=& ([scriptblock]::Create($bridge)) $child '{"marker":"fixture-json"}' $secure 30 'REAL_USE_LOCAL_BRIDGE_TEST_FAILED';[Console]::Out.Write(($value|ConvertTo-Json -Compress))}finally{$secure.Dispose()}
'@
    $windowsPowerShellBody=$windowsPowerShellBody.Replace('__BRIDGE__',$bridgeText64).Replace('__CHILD__',$bridgeChild64)
    $windowsPowerShellEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($windowsPowerShellBody))
    $windowsPowerShell='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $bridgeRaw=& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $windowsPowerShellEncoded 2>$null
    $bridgeExit=$LASTEXITCODE
    $bridgeProbe=($bridgeRaw-join"`n")|ConvertFrom-Json -ErrorAction Stop
    Check 'secure bridge crosses Windows PowerShell 5.1 to installed PowerShell 7 through ciphertext stdin and suppresses product host output' ($bridgeExit-eq 0 -and [int]$bridgeProbe.runtimeMajor-eq 7 -and [int]$bridgeProbe.fixtureLength-eq 31 -and [string]$bridgeProbe.marker-ceq'fixture-json')

    $planModule=Join-Path $WorkspaceRoot 'automation/release-e2e/modules/FullRelease.psm1';Import-Module $planModule -Force -DisableNameChecking;$plan=@(Get-FullReleasePhasePlan);$index=[Array]::IndexOf(@($plan.id),'REAL-USE-ACCEPTANCE')
    Check 'phase is exactly after Surrogate and before Tailscale with no checkpoint' ($index -gt 0 -and $plan[$index-1].id -ceq 'SURROGATE-DISPOSABLE' -and $plan[$index+1].id -ceq 'TAILSCALE-DEFERRED' -and $null -eq $plan[$index].checkpoint)
    $config=Get-Content (Join-Path $WorkspaceRoot 'automation/release-e2e/config/devfleet-e2e.defaults.json') -Raw|ConvertFrom-Json
    Check 'phase has a configured native executor and bounded ten-hour owner deadline' ([string]$config.FullReleaseExecutors.'REAL-USE-ACCEPTANCE' -ceq 'automation/release-e2e/modules/executors/Invoke-HostAgentPhase.ps1' -and [int]$config.RealUseAcceptance.TimeoutSeconds -eq 36000)
    $realProduct=Get-Content (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Raw
    Check 'native dispatch and RECONCILE both require validated acceptance evidence' ($realProduct -match "'REAL-USE-ACCEPTANCE'\s*\{\s*return Invoke-RealUseAcceptancePhase" -and $realProduct -match '\$required\s*=.*''REAL-USE-ACCEPTANCE''' -and $realProduct -match 'Assert-RealUseAcceptancePhaseEvidence')
    $moduleSource=Get-Content $modulePath -Raw
    Check 'production transport stages only the runner and hash-verifies both hops' ($moduleSource -match 'onlyRunnerStaged=\$true' -and $moduleSource -match 'Get-StageIntegrity' -and $moduleSource -match 'l1Stage\.localSha256' -and $moduleSource -match 'l1Stage\.remoteSha256' -and $moduleSource.Contains("'sudo','sha256sum',`$l2Runner") -and $moduleSource.Contains("'sudo','sha256sum',`$inputPath") -and $moduleSource -notmatch '@\(''transfer'',\$tar')
    Check 'runner staging uses a collision-rejecting ubuntu-traversable incoming root and never clears an existing run journal' ($moduleSource -match '/home/ubuntu/\.devfleet-real-use-incoming-' -and $moduleSource -match 'REAL_USE_INCOMING_COLLISION_OR_CREATE_FAILED' -and $moduleSource -match 'REAL_USE_L1_ROOT_COLLISION' -and $moduleSource -match 'REAL_USE_L2_ROOT_COLLISION_OR_CREATE_FAILED' -and $moduleSource -notmatch "rm','-rf','--',`$l2Root[^\r\n]+mkdir")
    Check 'transient driver units have remote runtime bounds and proven quiescence before owned-root deletion' ($moduleSource -match 'RuntimeMaxSec=\$\{runtime\}s' -and $moduleSource -match 'KillMode=control-group' -and $moduleSource -match 'Confirm-DriverUnitQuiescent' -and $moduleSource -match 'REAL_USE_DRIVER_UNIT_QUIESCENCE_UNPROVEN' -and $moduleSource -match 'ownedRootsRemoved')
    Check 'driver-unit observation fails closed and binds load state, active state, and main PID' ($moduleSource -match "'--property=LoadState','--property=ActiveState','--property=MainPID'" -and $moduleSource -match 'REAL_USE_DRIVER_UNIT_OBSERVATION_FAILED' -and $moduleSource -notmatch "exitCode-ne 0\)\{return 'absent'")
    Check 'interrupted driver stages run bounded cleanup and retain the private journal unless cleanup is proven' ($moduleSource.Contains("Invoke-DriverStage 'cleanup' `$cleanupPath") -and $moduleSource -match 'Test-DriverCleanupProven' -and $moduleSource -match 'REAL_USE_OWNED_ROOT_RETAINED_FOR_RECOVERY')
    Check 'production restart is limited to exact L2 devfleet.service' ($moduleSource -match "systemctl','restart','devfleet\.service" -and $moduleSource -notmatch "systemctl','restart','tailscaled" -and $moduleSource -notmatch "systemctl','restart','rest-server")
    Check 'production preflight proves least-privilege restic and control-root boundaries using boolean evidence only' ($moduleSource -match '/etc/devfleet/restic\.env' -and $moduleSource -match 'root:devfleet-backup:640:regular file' -and $moduleSource -match 'REAL_USE_RESTIC_CREDENTIAL_BOUNDARY_INVALID' -and $moduleSource -match 'REAL_USE_BACKUP_CONTROL_ROOT_BOUNDARY_INVALID' -and $moduleSource -match 'credentialBoundary=\$true')
    Check 'driver wrapper sources the fixed secret file only inside a clean shell and exports only admin credentials' ($moduleSource -match "'/usr/bin/env','-i'" -and $moduleSource -match '\. /etc/devfleet/secrets\.env' -and $moduleSource -match 'export DEVFLEET_ADMIN_USER DEVFLEET_ADMIN_PASSWORD' -and $moduleSource -notmatch 'DEVFLEET_ADMIN_PASSWORD="\$' -and $moduleSource -notmatch 'EnvironmentFile=/etc/devfleet/secrets\.env')
    $fullReleaseSource=Get-Content $planModule -Raw
    Check 'FullRelease captures a genuine encrypted Primary invitation before later CLEAN restores and consumes it only after Surrogate PASS' ($fullReleaseSource -match 'New-RealUseAcceptancePrimaryPairingCapture' -and $fullReleaseSource -match 'Complete-RealUseAcceptanceClusterJoin' -and $fullReleaseSource -match 'Remove-RealUseAcceptancePrivateState' -and $moduleSource -match 'ConvertFrom-SecureString' -and $moduleSource -match '-NonInteractive -BundlePassphrase \$bundlePassphrase' -and $moduleSource -match '-DesktopPairingBundlePath \$bundle -BundlePassphrase \$bundlePassphrase')
    Check 'pairing helpers execute under installed PowerShell 7 with DPAPI ciphertext stdin and no host-output contamination' ($moduleSource.Contains("C:\Program Files\PowerShell\7\pwsh.exe") -and $moduleSource.Contains('RedirectStandardInput=$true') -and $moduleSource.Contains('ConvertTo-SecureString -String $cipher') -and $moduleSource.Contains('6>$null') -and $moduleSource -notmatch 'StandardInputEncoding')
    Check 'decrypted pairing work is confined to an explicit private L1 ACL root' ($moduleSource.Contains('C:\ProgramData\DevFleet\tmp\real-use-pairing-') -and $moduleSource.Contains('SetAccessRuleProtection($true,$false)') -and $moduleSource -match 'REAL_USE_CLUSTER_JOIN_ROOT_ACL_INVALID' -and -not $moduleSource.Contains('C:\Users\Public\DevFleet-E2E\$($Context.runId)\REAL-USE-PAIRING'))
    Check 'cluster join verification does not collide with the read-only PowerShell Host automatic variable' ($moduleSource -match '\$hostAfter=Get-Content' -and $moduleSource -notmatch '(?im)^\s*\$host\s*=')
    Check 'pairing and join evidence bind only encrypted hash and public identities, never the DPAPI or bundle private paths' ($result.binding.clusterJoin.evidenceSha256 -ceq $joinHash -and [string]$result.binding.clusterJoin.primaryPairingEvidenceSha256 -ceq $pairingHash -and (($result.binding|ConvertTo-Json -Depth 16) -notmatch 'pairing-passphrase\.dpapi|Private\\RealUseAcceptance|primary-pairing\.dfe'))
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{status=if(@($checks|Where-Object{-not$_.pass}).Count){'FAIL'}else{'PASS'};scope='LOCAL_REAL_USE_ACCEPTANCE_PHASE_CONTRACT';passed=@($checks|Where-Object pass).Count;total=$checks.Count;checks=@($checks)}
$result|ConvertTo-Json -Depth 8
if($result.status-ne'PASS'){exit 1}
Write-Host "PASS $($result.passed)/$($result.total) REAL-USE-ACCEPTANCE phase checks; no VM, service, product, secret, or lab operation performed."

```


## FILE: automation/release-e2e/tests/Test-ReleaseIntegrityContracts.ps1

SHA256: b17cf60aad448fb292eea8bf11d71ecdf7e4de6c9b1edbaa018a03543693147c | Bytes: 4854 | Git mode: 100644

```
[CmdletBinding()]
param([string]$Workspace = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\modules\TailscaleE2E.psm1') -Force
$passed=0;$failed=[System.Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{[void]$script:failed.Add($Name)}}
$attemptedFalseRejected=$false
try { Assert-TailscaleAuthenticationResult -Result ([pscustomobject]@{authenticationAttempted=$false;authenticationSucceeded=$true}) | Out-Null } catch { $attemptedFalseRejected=$true }
Check $attemptedFalseRejected 'TAILSCALE-AUTH rejects authenticationAttempted=false'
$providerFailureRejected=$false
try { Assert-TailscaleAuthenticationResult -Result ([pscustomobject]@{authenticationAttempted=$true;authenticationSucceeded=$false}) | Out-Null } catch { $providerFailureRejected=$true }
Check $providerFailureRejected 'TAILSCALE-AUTH rejects provider failure'
$providerSuccess = Assert-TailscaleAuthenticationResult -Result ([pscustomobject]@{authenticationAttempted=$true;authenticationSucceeded=$true})
Check ([bool]$providerSuccess) 'TAILSCALE-AUTH accepts only attempted provider success'
$old=$env:DEVFLEET_TAILSCALE_AUTH_KEY
try {
    Remove-Item Env:DEVFLEET_TAILSCALE_AUTH_KEY -ErrorAction SilentlyContinue
    $missing=Get-TailscaleAuthenticationSecret -Config ([pscustomobject]@{Authentication=[pscustomobject]@{Provider='AuthKeyEnvironment';SecretEnvironmentVariable='DEVFLEET_TAILSCALE_AUTH_KEY'}})
Check (-not [bool]$missing.available -and $missing.secret -eq $null) 'Tailscale credentials are absent without leaking a secret'
} finally { if($null -eq $old){Remove-Item Env:DEVFLEET_TAILSCALE_AUTH_KEY -ErrorAction SilentlyContinue}else{$env:DEVFLEET_TAILSCALE_AUTH_KEY=$old} }
$dummyKey='DEVELOPMENT-FIXTURE-NOT-A-CREDENTIAL'
$observedAuthFile=$null;$observedArguments=@()
$success=Invoke-TailscaleAuthKeyFileCommand -AuthKey $dummyKey -TimeoutSeconds 7 -CommandInvoker {
    param($authFile,$arguments)
    $script:observedAuthFile=$authFile;$script:observedArguments=@($arguments)
    [pscustomobject]@{exitCode=0;output='fixture success'}
}
Check (($observedArguments -contains "--auth-key=file:$observedAuthFile") -and ($observedArguments -contains '--timeout=7s') -and ($observedArguments -notcontains $dummyKey) -and $success.authKeyFileRemoved -and -not(Test-Path -LiteralPath $observedAuthFile)) 'Tailscale auth uses a private file argument, finite timeout, and removes the dummy-key file on success'
$emptyRejected=$false;try{Invoke-TailscaleAuthKeyFileCommand -AuthKey '   ' -CommandInvoker {param($authFile,$arguments);throw 'must not run'}|Out-Null}catch{$emptyRejected=$true}
Check $emptyRejected 'Tailscale auth rejects missing key input before command invocation'
$timeoutPath=$null;$timeout=Invoke-TailscaleAuthKeyFileCommand -AuthKey $dummyKey -TimeoutSeconds 1 -CommandInvoker {param($authFile,$arguments);$script:timeoutPath=$authFile;[pscustomobject]@{exitCode=124;output='fixture timeout'}}
Check ($timeout.exitCode -eq 124 -and $timeout.authKeyFileRemoved -and -not(Test-Path -LiteralPath $timeoutPath)) 'Tailscale auth preserves bounded timeout result and removes the dummy-key file'
$failurePath=$null;$earlyFailureCleaned=$false;try{Invoke-TailscaleAuthKeyFileCommand -AuthKey $dummyKey -CommandInvoker {param($authFile,$arguments);$script:failurePath=$authFile;throw 'fixture early failure'}|Out-Null}catch{$earlyFailureCleaned=(-not(Test-Path -LiteralPath $failurePath))}
Check $earlyFailureCleaned 'Tailscale auth removes the dummy-key file after an early provider failure'
$cleanupSource=Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\Cleanup.psm1')
Check ($cleanupSource -match '\[Parameter\(Mandatory\)\]\[string\]\$L2Name' -and $cleanupSource -match 'DevFleet-H10-Linux') 'ter