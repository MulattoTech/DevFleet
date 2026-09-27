# DevFleet source part 047

Full-source UTF-8 byte interval [2139000, 2185500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 926195af8dabbd902831714c023f81221cabb16ca8ff86d269c47f9cae3f974b

<!-- BEGIN SOURCE SLICE -->
ha256;candidate=$request.candidate;execution=[pscustomobject]$execution;paths=[pscustomobject]@{workspaces='/home/devrunner/workspaces';quarantine='/home/devrunner/.devfleet-quarantine';runtimeRoot='/var/lib/devfleet/runtime'};baseUrl='http://127.0.0.1:8787'}
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
Check ($cleanupSource -match '\[Parameter\(Mandatory\)\]\[string\]\$L2Name' -and $cleanupSource -match 'DevFleet-H10-Linux') 'terminal L2 evidence requires configured name and protects foreign H10 resource'
$finalizationSource=Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\FullRelease.psm1')
Check ($finalizationSource -match 'Get-VM -Id' -and $finalizationSource -match 'terminalL1Hash' -and $finalizationSource -match 'l2ExactAbsent') 'post-cleanup finalization performs live terminal checks and consumes hashes'
$buildSource=Get-Content -Raw (Join-Path $Workspace 'installer-source\Build-Release.ps1')
Check ($buildSource -match 'authorizedCorrection' -and $buildSource -match 'authorized_correction=\$authorizedCorrection' -and $buildSource -match 'RELEASE BLOCKED — authorized correction path is invalid') 'release build preserves only validated authorized-correction shipping paths in generated authority'
if($failed.Count){[pscustomobject]@{status='FAIL';passed=$passed;failures=@($failed)}|ConvertTo-Json -Depth 5;exit 1}
[pscustomobject]@{status='PASS';passed=$passed;failures=@()}|ConvertTo-Json -Depth 5

```


## FILE: automation/release-e2e/tests/Test-SecurityPoisonFailureEvidence.ps1

SHA256: b4073442a9c880cc11bfc9da083c4215d770313127d95829cd3bd54b1b6da28b | Bytes: 7129 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$checks.Add([pscustomobject]@{name=$Name;pass=$Pass})}
$root=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-security-evidence-'+[guid]::NewGuid().ToString('N'))
$global:DevFleetSecurityFixture=@{childCalls=0;provisioningExit=0;childComputerName='';childProgramFilesX86=''}
$originalComputerName=[Environment]::GetEnvironmentVariable('COMPUTERNAME','Process')
$originalProgramFilesX86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)','Process')
$expectedComputerName=[Environment]::MachineName
$expectedProgramFilesX86=[Environment]::GetFolderPath('ProgramFilesX86')
try {
    $execDir=Join-Path $root 'automation/release-e2e/modules/executors'
    New-Item -ItemType Directory -Path $execDir,(Join-Path $root 'source') -Force|Out-Null
    $executor=Join-Path $execDir 'Invoke-SecurityPoisonPhase.ps1'
    Copy-Item (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-SecurityPoisonPhase.ps1') $executor
    Copy-Item (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Evidence.psm1') (Join-Path $execDir '../Evidence.psm1')
    $candidate=Join-Path $root 'candidate-fixture.exe'
    [IO.File]::WriteAllText($candidate,'not executable; hash-bound test fixture')
    $sha=(Get-FileHash $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    $bytes=(Get-Item $candidate).Length
    function Get-Command {
        param([string]$Name,[string]$ErrorAction)
        if($Name -eq 'python.exe'){return [pscustomobject]@{Source='Invoke-TestPython'}}
        Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction Stop
    }
    function Invoke-TestPython {
        param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Arguments)
        $global:DevFleetSecurityFixture.childCalls++
        Set-Variable -Name LASTEXITCODE -Value 0 -Scope 1
        'fixture python passed'
    }
    function pwsh.exe {
        param([switch]$NoProfile,[switch]$NonInteractive,[string]$ExecutionPolicy,[string]$File,[string]$WorkspaceRoot)
        $global:DevFleetSecurityFixture.childCalls++
        $global:DevFleetSecurityFixture.childComputerName=[string]$env:COMPUTERNAME
        $global:DevFleetSecurityFixture.childProgramFilesX86=[string]${env:ProgramFiles(x86)}
        Set-Variable -Name LASTEXITCODE -Value $global:DevFleetSecurityFixture.provisioningExit -Scope 1
        if($global:DevFleetSecurityFixture.provisioningExit){'fixture failure: '+('x'*4500)}else{'fixture provisioning passed'}
    }
    Remove-Item -LiteralPath 'Env:COMPUTERNAME' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'Env:ProgramFiles(x86)' -ErrorAction SilentlyContinue
    foreach($case in @('failure','success','identity-mismatch','preserve-nonempty')){
        $global:DevFleetSecurityFixture.childCalls=0
        $global:DevFleetSecurityFixture.provisioningExit=if($case -eq 'failure'){23}else{0}
        if($case -eq 'preserve-nonempty'){$env:COMPUTERNAME='PRESERVE-COMPUTERNAME';${env:ProgramFiles(x86)}='C:\Preserve-ProgramFilesX86'}
        $runDir=Join-Path $root $case
        $ctx=[ordered]@{runDir=$runDir;candidate=[ordered]@{releaseFingerprintId='release-fixture';toolingFingerprintId='tooling-fixture';gitCommit='commit-fixture';candidate=[ordered]@{path=$candidate;sha256=if($case -eq 'identity-mismatch'){'0'*64}else{$sha};bytes=$bytes}}}
        $caught=$null
        try { & $executor -ContextJson ($ctx|ConvertTo-Json -Depth 8 -Compress)|Out-Null } catch {$caught=$_.Exception.Message}
        $path=Join-Path $runDir 'SECURITY-POISON-evidence.json'
        $exists=Test-Path -LiteralPath $path
        if($case -eq 'failure'){
            Check 'native scenario failure is rethrown' ($caught -match 'PROVISIONING-OWNERSHIP')
            Check 'failed scenario evidence exists before throw' $exists
            Check 'no scenario runs after first failure' ($global:DevFleetSecurityFixture.childCalls -eq 2)
            if($exists){
                $e=Get-Content $path -Raw|ConvertFrom-Json
                Check 'failure cannot claim REAL E2E PASS' ($e.status -eq 'FAIL' -and -not $e.allRequiredScenariosPassed)
                Check 'prior PASS and failed row both retained' ($e.scenarios.Count -eq 2 -and $e.scenarios[0].status -eq 'PASS' -and $e.scenarios[1].status -eq 'FAIL')
                Check 'native nonzero exit retained' ($e.scenarios[1].exitCode -eq 23)
                Check 'failed output is bounded' ($e.scenarios[1].outputExcerpt.Length -eq 4000)
                Check 'candidate binding retained' ($e.candidate.exeSha256 -eq $sha -and $e.candidate.toolingFingerprintId -eq 'tooling-fixture')
                Check 'missing process COMPUTERNAME comes from native machine identity' ($global:DevFleetSecurityFixture.childComputerName -ceq $expectedComputerName)
                Check 'missing process ProgramFiles(x86) comes from trusted Windows API' ($global:DevFleetSecurityFixture.childProgramFilesX86 -ceq $expectedProgramFilesX86)
            }
        } elseif($case -eq 'success'){
            Check 'all-success control does not throw' (-not $caught)
            Check 'success requires all seven children' ($global:DevFleetSecurityFixture.childCalls -eq 7)
            Check 'all-success evidence exists' $exists
            if($exists){$e=Get-Content $path -Raw|ConvertFrom-Json;Check 'unchanged success contract requires seven PASS rows' ($e.status -eq 'REAL E2E PASS' -and $e.allRequiredScenariosPassed -and $e.scenarios.Count -eq 7 -and @($e.scenarios|Where-Object status -ne 'PASS').Count -eq 0)}
        } elseif($case -eq 'identity-mismatch') {
            Check 'changed candidate rejected before children' ($caught -match 'exact candidate changed' -and $global:DevFleetSecurityFixture.childCalls -eq 0)
            Check 'identity rejection produces no success evidence' (-not $exists)
        } else {
            Check 'nonempty process COMPUTERNAME is preserved' ($global:DevFleetSecurityFixture.childComputerName -ceq 'PRESERVE-COMPUTERNAME')
            Check 'nonempty process ProgramFiles(x86) is preserved' ($global:DevFleetSecurityFixture.childProgramFilesX86 -ceq 'C:\Preserve-ProgramFilesX86')
        }
    }
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
    if($null -eq $originalComputerName){Remove-Item -LiteralPath 'Env:COMPUTERNAME' -ErrorAction SilentlyContinue}else{$env:COMPUTERNAME=$originalComputerName}
    if($null -eq $originalProgramFilesX86){Remove-Item -LiteralPath 'Env:ProgramFiles(x86)' -ErrorAction SilentlyContinue}else{${env:ProgramFiles(x86)}=$originalProgramFilesX86}
    Remove-Variable -Name DevFleetSecurityFixture -Scope Global -ErrorAction SilentlyContinue
}
$failed=@($checks|Where-Object {-not $_.pass})
[ordered]@{scope='VM_FREE_PRODUCTION_EXECUTOR_REGRESSION';releaseCredit=$false;status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;checks=@($checks)}|ConvertTo-Json -Depth 6
if($failed.Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-SecurityPoisonHostAgent.ps1

SHA256: 611abf463f61e0b1c29e11819eabe9772c54e2751075bd18cd89af69711d0224 | Bytes: 5702 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
$agent=Join-Path $WorkspaceRoot 'source\windows\DevFleet-HostAgent.ps1'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) "devfleet-security-poison-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot -Force|Out-Null
try {
    $tokenPath=Join-Path $testRoot 'token.txt';[IO.File]::WriteAllText($tokenPath,('x'*48))
    $configPath=Join-Path $testRoot 'config.json'
    $config=[ordered]@{
        HostId='SECURITY-POISON-HOST';HostName='SECURITY-POISON-HOST';TokenPath=$tokenPath
        MultipassPath=(Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
        SshConfigPath=(Join-Path $testRoot 'ssh-config');SshKnownHostsPath=(Join-Path $testRoot 'known-hosts')
        SshPrivateKeyPath=(Join-Path $testRoot 'key');BootTimeoutSeconds=1;UbuntuImage='test-image'
        ResourcePolicy=@{MaxProjectCpus=8;MaxProjectMemoryGb=32;MaxProjectDiskGb=500}
    }
    $config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
    . $agent -ConfigPath $configPath -LibraryOnly
    $registry=Read-Registry;Write-Registry $registry

    # Multiple independent pwsh processes exercise the real inter-process mutex,
    # latest-read transaction, and atomic replacement. Every worker owns a distinct
    # project record; a missing record proves a lost update.
    $workerPath=Join-Path $testRoot 'registry-worker.ps1'
    $worker=@'
param()
$ErrorActionPreference='Stop'
$Agent=$env:DEVFLEET_SECURITY_AGENT;$Config=$env:DEVFLEET_SECURITY_CONFIG;$Slug=$env:DEVFLEET_SECURITY_SLUG;$Index=[int]$env:DEVFLEET_SECURITY_INDEX
. $Agent -ConfigPath $Config -LibraryOnly
$record=@{managed_by='devfleet';host_id='SECURITY-POISON-HOST';project_id=([guid]::NewGuid().ToString());slug=$Slug;runtime_id="runtime-$Slug";vm_name="vm-$Slug";state='ready';worker=$Index;updated_at=(Get-Date).ToUniversalTime().ToString('o')}
Update-ProjectRecord $Slug $record|Out-Null
'PASS'
'@
    [IO.File]::WriteAllText($workerPath,$worker)
    $processes=[Collections.Generic.List[Diagnostics.Process]]::new()
    for($i=0;$i -lt 24;$i++){
        $slug="parallel-$i"
        $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=(Get-Command pwsh.exe).Source;$psi.UseShellExecute=$false
        $psi.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$workerPath`""
        $psi.Environment['DEVFLEET_SECURITY_AGENT']=$agent;$psi.Environment['DEVFLEET_SECURITY_CONFIG']=$configPath;$psi.Environment['DEVFLEET_SECURITY_SLUG']=$slug;$psi.Environment['DEVFLEET_SECURITY_INDEX']=[string]$i
        $p=[Diagnostics.Process]::new();$p.StartInfo=$psi;if(-not $p.Start()){throw "Could not start registry worker $i"};$processes.Add($p)
    }
    foreach($p in $processes){if(-not $p.WaitForExit(60000)){try{$p.Kill($true)}catch{};throw 'Registry worker timed out.'};if($p.ExitCode -ne 0){throw "Registry worker failed with $($p.ExitCode)."}}
    $after=Read-Registry
    $missing=@(0..23|Where-Object{-not $after.projects.ContainsKey("parallel-$_")})
    if($missing.Count -gt 0){throw "Registry lost $($missing.Count) concurrent project updates: $($missing -join ',')."}
    $json=Get-Content -LiteralPath $script:RegistryPath -Raw|ConvertFrom-Json
    if(@($json.projects.PSObject.Properties).Count -lt 24){throw 'Concurrent registry result was not valid complete JSON.'}

    # Repeat the TOCTOU collision at launch. The foreign VM is created only by the
    # fake launch boundary; launch_succeeded remains false, so cleanup must never
    # issue delete/purge and the foreign inventory remains observable.
    $raceResults=[Collections.Generic.List[object]]::new()
    function Assert-ResourceRequest { }
    function New-CloudInit { param([string]$Slug,[string]$ProjectId,[string]$GitUrl,[string]$ProvisioningAttemptId);return 'fixture-cloud-init' }
    function Get-MultipassVms { if($script:ForeignCreated){return @([pscustomobject]@{name=$script:ForeignName;state='RUNNING'})};return @() }
    function Invoke-Multipass {
        param([string[]]$ArgumentList,[int]$TimeoutSeconds=120)
        if([string]$ArgumentList[0] -eq 'launch'){$script:ForeignCreated=$true;throw 'fixture same-name foreign launch collision'}
        if([string]$ArgumentList[0] -eq 'delete'){$script:DeleteCalls++;throw 'DELETE MUST NOT BE CALLED AGAINST FOREIGN VM'}
        return [pscustomobject]@{ExitCode=0;Text=''}
    }
    for($i=0;$i -lt 20;$i++){
        $script:ForeignName="devfleet-project-race-$i";$script:ForeignCreated=$false;$script:DeleteCalls=0
        $projectId=[guid]::NewGuid().ToString();$threw=$false
        try{Ensure-ProjectVm "race-$i" $projectId 1 2 20}catch{$threw=$true}
        if(-not $threw -or -not $script:ForeignCreated -or $script:DeleteCalls -ne 0){throw "Same-name race iteration $i did not fail closed."}
        $raceResults.Add([ordered]@{iteration=$i;operation='Ensure-ProjectVm';launch='collision';foreignVmSurvived=$true;deletePurges=0;registryClaimRemoved=(-not (Read-Registry).projects.ContainsKey("race-$i"))})
    }
    if(@($raceResults|Where-Object{-not $_.registryClaimRemoved}).Count -gt 0){throw 'Failed launch left a provisional registry claim.'}
    [ordered]@{status='PASS';schemaVersion=1;registryConcurrency=[ordered]@{iterations=24;lostUpdates=0;validJson=$true};sameNameVmToctou=[ordered]@{iterations=20;foreignVmSurvived=$true;purgesAgainstForeign=0;provisionalClaims=0};evidenceScope='owned temporary fixture resources only'}|ConvertTo-Json -Depth 12 -Compress
}finally{Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}

```


## FILE: automation/release-e2e/tests/Test-StandardTokenCandidateEvidenceContract.ps1

SHA256: ed4e8167e2af5b31f3643141b4de172ce0e5a90bf3667825144d19d2bdc51cfa | Bytes: 2621 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop';if([string]::IsNullOrWhiteSpace($WorkspaceRoot)){$WorkspaceRoot=Join-Path $PSScriptRoot '..\..\..'};$root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$candidate=Get-Content -Raw (Join-Path $root 'automation\release-e2e\modules\Candidate.psm1');$standard=Get-Content -Raw (Join-Path $root 'automation\release-e2e\tests\Test-InstallerSelfTestStandardToken.ps1')
$checks=[ordered]@{
    candidateAcceptsCallerReportPath=$candidate -match '\[string\]\$ReportPath' -and $candidate -match 'already exists; a unique path is required'
    candidateDoesNotDeleteCallerReport=$candidate -match 'if \(\$callerSuppliedReportPath\) \{ throw' -and $candidate -match 'Remove-Item -LiteralPath \$reportPath -Force -ErrorAction Stop'
    candidateCapturesToken=$candidate -match 'Get-WindowsTokenEvidence' -and $candidate -match 'integrityLevelSid' -and $candidate -match 'S-1-16-'
    candidatePowerShell51Compatible=$candidate -notmatch '\?\?' -and $candidate -match 'shipping_input_identity' -and $candidate -match 'shippingInputIdentity'
    standardRejectsAdminAndElevated=$standard -match 'standardNonAdministratorToken' -and $candidate -match 'S-1-5-32-544'
    standardPowerShell51DefaultResolution=$standard -match 'param\(\[string\]\$WorkspaceRoot' -and $standard -match 'IsNullOrWhiteSpace\(\$WorkspaceRoot\)' -and $standard -match '\$PSScriptRoot'
    standardUsesExactSignedCandidate=$standard -match 'Get-CandidateFingerprint' -and $standard -match 'PRIVATE_SELF_SIGNED' -and $standard -match 'authenticode'
    standardUsesImmutableEvidenceRoot=$standard -match 'evidence/standard-token' -and $standard -match 'installer-self-test-raw\.txt' -and $standard -match 'standard-token-evidence\.json'
    standardBindsTupleAndHashes=$standard -match 'candidateBuildCommit' -and $standard -match 'shippingInputIdentity' -and $standard -match 'releaseFingerprintId' -and $standard -match 'toolingFingerprintId' -and $standard -match 'reportSha256' -and $standard -match 'runnerRelative'
    standardAtomicCurrentPointer=$standard -match 'CURRENT-STANDARD-TOKEN\.json' -and $standard -match 'Write-AtomicJson'
    noBuildOrSign=$standard -notmatch 'dotnet publish|Build-Release|Set-AuthenticodeSignature'
}
$failed=@($checks.GetEnumerator()|Where-Object{-not[bool]$_.Value});$result=[ordered]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=($checks.Count-$failed.Count);total=$checks.Count;checks=$checks}
$result|ConvertTo-Json -Depth 8;if($failed.Count){throw "Standard-token candidate evidence contract failed: $(@($failed.Name)-join ',')"}

```


## FILE: automation/release-e2e/tests/Test-TailscaleBrowserPairingObservability.ps1

SHA256: 924883c14680e33733106aac103ad9e612cf159ab004e6635261d3626a612bb9 | Bytes: 7442 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
$windowsRoot = Join-Path $WorkspaceRoot 'source/windows'
Import-Module (Join-Path $windowsRoot 'DevFleet.Tailscale.psm1') -Force -DisableNameChecking
$module = Get-Module DevFleet.Tailscale
$checks = [Collections.Generic.List[object]]::new()

function Check([string]$Name, [bool]$Pass) {
    $checks.Add([pscustomobject]@{ name = $Name; pass = $Pass })
}

function Read-Events([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Invoke-FixtureCase([string]$Case) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-Tailscale-Observability-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $eventPath = Join-Path $root 'pairing-events.log'
    try {
        $record = & $module {
            param($FixtureCase, $FixtureEventPath)
            $script:PairingFixtureCase = $FixtureCase
            $script:PairingFixtureOpened = 0
            $script:PairingFixtureStatusCalls = 0

            function script:Get-DevFleetDeadlineContext { return $null }
            function script:Start-Sleep { param($Milliseconds) }
            function script:Open-DevFleetTailscaleAuthenticationPage {
                param($Uri)
                $script:PairingFixtureOpened++
                if ($script:PairingFixtureCase -eq 'launch-failure') { throw 'fixture browser launch failure' }
                [pscustomobject]@{ apiAccepted = $true; processId = 4242; processSessionId = 1 }
            }
            function script:Invoke-External {
                param($FilePath, $ArgumentList, [switch]$Capture, [switch]$IgnoreExitCode, $TimeoutSeconds, $DeadlineUtc)
                if (-not $Capture -or -not $IgnoreExitCode -or $TimeoutSeconds -le 0) { throw 'fixture lost bounded capture contract' }
                if ($ArgumentList -contains 'up') {
                    if ($script:PairingFixtureCase -eq 'no-uri') { return 'https://evil.example/a/fake' }
                    return 'To authenticate, visit: https://login.tailscale.com/a/fixture123'
                }
                if ($ArgumentList -notcontains '--json') { throw 'fixture lost status JSON contract' }
                $script:PairingFixtureStatusCalls++
                if ($script:PairingFixtureCase -eq 'poll-command-failure' -and $script:PairingFixtureOpened -gt 0) { throw 'fixture status command timeout' }
                $connected = $script:PairingFixtureCase -eq 'already-connected' -or
                    ($script:PairingFixtureCase -eq 'auth-after-launch' -and $script:PairingFixtureOpened -gt 0)
                return (@{
                        BackendState = if ($connected) { 'Running' } else { 'NeedsLogin' }
                        TailscaleIPs = if ($connected) { @('100.64.1.2') } else { @() }
                        Self = if ($connected) { @{ HostName = 'devfleet-fixture' } } else { $null }
                    } | ConvertTo-Json -Compress)
            }

            $deadline = if ($FixtureCase -eq 'deadline-before-command') { [datetime]::UtcNow.AddSeconds(-1) } else { [datetime]::UtcNow.AddSeconds(60) }
            $result = $null
            $failed = $false
            $errorText = ''
            try {
                $result = Invoke-DevFleetTailscaleBrowserPairing `
                    -FilePath 'tailscale-fixture.exe' `
                    -Hostname 'devfleet-fixture' `
                    -DeadlineUtc $deadline `
                    -EvidencePath $FixtureEventPath `
                    -RunId 'fixture-run-observability' `
                    -TransactionId ('a' * 32) `
                    -PayloadSha256 ('b' * 64) `
       