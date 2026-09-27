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
