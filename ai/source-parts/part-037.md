# DevFleet source part 037

Full-source UTF-8 byte interval [1674000, 1720500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ae6ff127aca741b060d836b9f0e1922ac7c3d00eb3116729e0c2a0be23748069

<!-- BEGIN SOURCE SLICE -->
in-x64.exe" -File)
        $portable=@(Get-ChildItem -LiteralPath $outputs -Filter "DevFleet-v$version-Portable*.zip" -File)
        if($exe.Count -ne 1 -or $portable.Count -ne 1){throw 'Harness fixture artifact discovery is ambiguous.'}
        $release=Get-Content -LiteralPath (Join-Path $outputs 'release-fingerprint.json') -Raw|ConvertFrom-Json
        return [pscustomobject]@{
            releaseVersion=$version
            installerVersion=(Get-Content -LiteralPath (Join-Path $Root 'installer-source\INSTALLER_VERSION') -Raw).Trim()
            gitCommit=(& git -C $Root rev-parse HEAD).Trim()
            releaseFingerprintId=[string]$release.releaseFingerprintId
            toolingFingerprintId=[string]$release.toolingFingerprint.toolingFingerprintId
            candidate=Get-FileHashRecord -Path $exe[0].FullName
            tar=Get-FileHashRecord -Path (Join-Path $outputs "devfleet-v$version.tar.gz")
            portable=Get-FileHashRecord -Path $portable[0].FullName
            installerSource=Get-FileHashRecord -Path (Join-Path $outputs "DevFleet-v$version-Installer-Source.zip")
        }
    }
}
$temp=Join-Path $env:TEMP "DevFleet-E2E-HarnessTests-$([guid]::NewGuid().ToString('N'))"; New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $candidate=Get-HarnessCandidateFingerprint -Root $WorkspaceRoot
    Assert-That ($candidate.releaseVersion -match '^\d+\.\d+\.\d+$') 'version parsing'
    Assert-That ($candidate.candidate.sha256.Length -eq 64 -and $candidate.tar.sha256.Length -eq 64) 'artifact hashing'
    Assert-That ((Test-CandidateFingerprint -Expected $candidate -Actual (Get-HarnessCandidateFingerprint -Root $WorkspaceRoot)) -eq $true) 'candidate fingerprint equality'

    $unsafeProjection=Get-ProjectedHostMemorySafety -AvailableMemoryGiB 25.16 -ExpectedVmStartCostGiB 14.38 -InstalledUsableMemoryGiB 64 -CommitLimitGiB 64 -CommittedGiB 50
    Assert-That (-not $unsafeProjection.startSafe) 'projected post-start memory rejects unsafe VM start'
    Assert-That ($unsafeProjection.projectedPostStartAvailableMemoryGiB -eq 10.78) 'projected post-start memory records expected remainder'
    $overrideBlocked=Apply-RamPressureOverride -Snapshot ([pscustomobject]@{startSafe=$false;resourceExhaustion=$false})
    Assert-That (-not $overrideBlocked.effectiveE2EStartAuthorized -and -not $overrideBlocked.ramPressureOverrideAuthorized) 'RAM override defaults disabled'
    $overrideAllowed=Apply-RamPressureOverride -Snapshot ([pscustomobject]@{startSafe=$false;resourceExhaustion=$false}) -AllowRamPressure
    Assert-That ($overrideAllowed.effectiveE2EStartAuthorized -and -not $overrideAllowed.rawHostSafetyStartSafe -and $overrideAllowed.ramPressureOverrideAuthorized) 'RAM override authorizes memory-only failure and preserves raw result'
    $overrideDenied=Apply-RamPressureOverride -Snapshot ([pscustomobject]@{startSafe=$false;resourceExhaustion=$true}) -AllowRamPressure
    Assert-That (-not $overrideDenied.effectiveE2EStartAuthorized) 'RAM override cannot bypass resource exhaustion'
    $safeProjection=Get-ProjectedHostMemorySafety -AvailableMemoryGiB 35 -ExpectedVmStartCostGiB 14.38 -InstalledUsableMemoryGiB 64 -CommitLimitGiB 64 -CommittedGiB 30
    Assert-That $safeProjection.startSafe 'projected post-start memory accepts safe VM start'
    $runningProjection=Get-ProjectedHostMemorySafety -AvailableMemoryGiB 21 -ExpectedVmStartCostGiB 14.38 -InstalledUsableMemoryGiB 64 -CommitLimitGiB 64 -CommittedGiB 30 -VmAlreadyRunning $true
    Assert-That ($runningProjection.startSafe -and $runningProjection.expectedVmStartCostGiB -eq 0) 'running VM uses observed post-start memory'

    $space=Join-Path $temp 'path with spaces'; New-Item -ItemType Directory -Path $space | Out-Null
    $statePath=Join-Path $space 'run-state.json'; $obj=[pscustomobject]@{schemaVersion=1;candidate=$candidate.candidate.sha256}
    Write-AtomicJson -Path $statePath -Value $obj; $read=Read-StrictJson -Path $statePath
    Assert-That ($read.candidate -eq $candidate.candidate.sha256) 'atomic state write/read with spaces'
    Set-Content -LiteralPath $statePath -Value '{bad json' -Encoding utf8
    $invalidCaught=$false;try{Read-StrictJson -Path $statePath}catch{$invalidCaught=$true}; Assert-That $invalidCaught 'corrupted state rejection'
    Write-AtomicJson -Path $statePath -Value $obj

    $lockReady=Join-Path $space 'run-state-lock-ready.txt'
    $locker=Start-Job -ArgumentList @($statePath,$lockReady) -ScriptBlock {
        param([string]$Target,[string]$Ready)
        $handle=[IO.File]::Open($Target,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            [IO.File]::WriteAllText($Ready,'ready',[Text.UTF8Encoding]::new($false))
            Start-Sleep -Milliseconds 500
        } finally { $handle.Dispose() }
    }
    $lockDeadline=(Get-Date).AddSeconds(10)
    while(-not(Test-Path -LiteralPath $lockReady) -and (Get-Date) -lt $lockDeadline){Start-Sleep -Milliseconds 25}
    $replacement=[pscustomobject]@{schemaVersion=1;candidate='replacement-after-transient-contention'}
    $replacementSucceeded=$false
    try {
        if(-not(Test-Path -LiteralPath $lockReady)){throw 'test locker did not acquire the run-state file'}
        Write-AtomicJson -Path $statePath -Value $replacement
        $replacementSucceeded=([string](Read-StrictJson -Path $statePath).candidate -ceq [string]$replacement.candidate)
    } catch {
        $replacementSucceeded=$false
    } finally {
        Wait-Job -Job $locker -Timeout 5 | Out-Null
        Remove-Job -Job $locker -Force -ErrorAction SilentlyContinue
    }
    Assert-That $replacementSucceeded 'atomic state replace tolerates brief Windows destination contention'
    Assert-That (@(Get-ChildItem -LiteralPath $space -Filter 'run-state.json.*.tmp' -File -ErrorAction SilentlyContinue).Count -eq 0) 'atomic state replace removes temporary files after contention'

    $runState=[pscustomobject]@{candidateHashes=[pscustomobject]@{exe=$candidate.candidate.sha256;tar=$candidate.tar.sha256};vmId='expected'}
    $mismatchCaught=$false;try{Assert-ResumeIdentity -State $runState -Fingerprint $candidate -Vm ([pscustomobject]@{Id=[guid]::NewGuid()})|Out-Null}catch{$mismatchCaught=$true}; Assert-That $mismatchCaught 'checkpoint/VM identity mismatch rejection'
    $hashMismatch=[pscustomobject]@{candidateHashes=[pscustomobject]@{exe=('0'*64);tar=$candidate.tar.sha256}}
    $candidateCaught=$false;try{Assert-ResumeIdentity -State $hashMismatch -Fingerprint $candidate}catch{$candidateCaught=$true}; Assert-That $candidateCaught 'candidate hash mismatch rejection'

    $fakeVm=[pscustomobject]@{Name='DevFleet-E2E-Test';Id=([guid]::NewGuid())}; $manifest=New-CleanupManifest -Vm $fakeVm -RunId 'synthetic'; Assert-That (Test-CleanupManifest $manifest) 'cleanup manifest exact ownership'; Assert-That (-not (Assert-DisposableNameTest -Name 'devfleet-primary')) 'production name denied'
    $summaryRoot=Join-Path $temp 'cleanup-summary';$summaryEvidence=Join-Path $summaryRoot 'evidence';$summaryRunDir=Join-Path $summaryRoot 'audit\automation-harness\runs\unit-cleanup';New-Item -ItemType Directory -Force -Path $summaryEvidence,$summaryRunDir|Out-Null
    $summaryCleanupPath=Join-Path $summaryRunDir 'cleanup-state.json';$summaryCleanup=[ordered]@{runId='unit-cleanup';status='PASS';runOwnedOnly=$true;cleanupOwner='run-exact-candidate-proof.ps1';l1=[ordered]@{status='OFF';name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';observedUtc='2026-09-06T09:23:01.1613702Z'};l2=[ordered]@{status='ABSENT';expectedName='DevFleet-E2E-Linux-01';present=$false;exactMatchCount=0;verification='Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend';backendInventories=@([ordered]@{provider='Hyper-V';status='PASS';names=@();verification='bounded Hyper-V inventory'},[ordered]@{provider='VirtualBox';status='PASS';names=@();verification='bounded VirtualBox inventory'});observedUtc='2026-09-06T09:22:55.9889986Z'}}
    Write-EvidenceJson -Path $summaryCleanupPath -Value $summaryCleanup;$published=Publish-DevFleetTerminalCleanupSummary -WorkspaceRoot $summaryRoot -CleanupEvidencePath $summaryCleanupPath;$publishedL2=Get-Content -LiteralPath (Join-Path $summaryEvidence 'l2-terminal-state.json') -Raw|ConvertFrom-Json
    $publishedL2TimestampValue=$publishedL2.timestampUtc
    $publishedL2Timestamp=if($publishedL2TimestampValue -is [datetime]){([datetime]$publishedL2TimestampValue).ToUniversalTime()}elseif($publishedL2TimestampValue -is [datetimeoffset]){([datetimeoffset]$publishedL2TimestampValue).UtcDateTime}else{[datetime]::ParseExact([string]$publishedL2TimestampValue,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}
    $publishedL2TimestampUtc=$publishedL2Timestamp.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
    Assert-That ([string]$published.sourceRunId -ceq 'unit-cleanup' -and $publishedL2TimestampUtc -ceq '2026-09-06T09:22:55.9889986Z' -and -not [bool]$publishedL2.certifiedReleaseCleanup -and @($publishedL2.backendInventories).Count -eq 2) 'terminal cleanup summary preserves exact source provenance and complete backend evidence without claiming release CLEANUP'
    $cliOnlyPath=Join-Path (New-Item -ItemType Directory -Force -Path (Join-Path $summaryRoot 'audit\automation-harness\runs\unit-cli-only')) 'cleanup-state.json';$cliOnly=$summaryCleanup|ConvertTo-Json -Depth 10|ConvertFrom-Json;$cliOnly.runId='unit-cli-only';$cliOnly.l2.backendInventories=@();$cliOnly.l2.verification='Multipass executable absent inside exact L1';Write-EvidenceJson -Path $cliOnlyPath -Value $cliOnly;$cliOnlyRejected=$false;try{Publish-DevFleetTerminalCleanupSummary -WorkspaceRoot $summaryRoot -CleanupEvidencePath $cliOnlyPath|Out-Null}catch{$cliOnlyRejected=$true};Assert-That $cliOnlyRejected 'terminal cleanup summary rejects CLI absence without complete in-L1 backend inventory'
    function Test-TerminalCleanupSummaryRejects([string]$RunSuffix,[scriptblock]$Mutation){
        $runId="unit-$RunSuffix";$runDir=Join-Path $script:summaryRoot (Join-Path 'audit\automation-harness\runs' $runId);New-Item -ItemType Directory -Force -Path $runDir|Out-Null
        $record=$script:summaryCleanup|ConvertTo-Json -Depth 10|ConvertFrom-Json;$record.runId=$runId;&$Mutation $record
        $path=Join-Path $runDir 'cleanup-state.json';Write-EvidenceJson -Path $path -Value $record
        try{Publish-DevFleetTerminalCleanupSummary -WorkspaceRoot $script:summaryRoot -CleanupEvidencePath $path|Out-Null;$false}catch{$true}
    }
    Assert-That (Test-TerminalCleanupSummaryRejects 'missing-exact-count' {param($r)$r.l2.PSObject.Properties.Remove('exactMatchCount')}) 'terminal cleanup summary rejects a missing nested exact-match count'
    Assert-That (Test-TerminalCleanupSummaryRejects 'boolean-exact-count' {param($r)$r.l2.exactMatchCount=$false}) 'terminal cleanup summary rejects a Boolean masquerading as nested exact-match count'
    Assert-That (Test-TerminalCleanupSummaryRejects 'host-only-method' {param($r)$r.l2.verification='Get-VM -Name exact returned no VM'}) 'terminal cleanup summary rejects a host-only inventory method even with backend rows'
    Assert-That (Test-TerminalCleanupSummaryRejects 'present-target' {param($r)$r.l2.backendInventories[0].names=@('DevFleet-E2E-Linux-01')}) 'terminal cleanup summary rejects a supported backend inventory containing the target L2'
    $fixtureVm=[pscustomobject]@{Name='DevFleet-E2E-Test';Id=([guid]::NewGuid())}; $fixtureSnapshot=[pscustomobject]@{Name='DevFleet-E2E-MAINTENANCE-READY';Id=([guid]::NewGuid())}; $generation=([guid]::NewGuid()).ToString('D')
    $fixtureProvenance=[pscustomobject]@{schemaVersion=1;contract='maintenance-ready-provenance-v1';vmName=$fixtureVm.Name;vmId=$fixtureVm.Id.ToString();checkpointName=$fixtureSnapshot.Name;checkpointId=$fixtureSnapshot.Id.ToString();candidate=[pscustomobject]@{gitCommit=$candidate.gitCommit;releaseVersion=$candidate.releaseVersion;installerVersion=$candidate.installerVersion;releaseFingerprintId=$candidate.releaseFingerprintId;toolingFingerprintId=$candidate.toolingFingerprintId;payloadSha256=$candidate.tar.sha256};install=[pscustomobject]@{installationGeneration=$generation};ownership=[pscustomobject]@{schemaVersion=1;installationGeneration=$generation}}
    $fixtureProvenance|Add-Member -NotePropertyName vault -NotePropertyValue ([pscustomobject]@{status='PASS';configurationPresent=$true;authenticatedTransport=$true;proofCredit=$false;primaryRole='primary';payloadSha256=$candidate.tar.sha256;primaryId='11111111-1111-1111-1111-111111111111';vaultId='22222222-2222-2222-2222-222222222222';deploymentId='33333333-3333-3333-3333-333333333333'})
    Assert-That (Assert-MaintenanceReadyProvenance -Provenance $fixtureProvenance -Vm $fixtureVm -Snapshot $fixtureSnapshot -Fingerprint $candidate) 'current maintenance provenance accepted'
    $unconfiguredFixture=$fixtureProvenance|ConvertTo-Json -Depth 8|ConvertFrom-Json;$unconfiguredFixture.vault.configurationPresent=$false;$unconfiguredCaught=$false;try{Assert-MaintenanceReadyProvenance -Provenance $unconfiguredFixture -Vm $fixtureVm -Snapshot $fixtureSnapshot -Fingerprint $candidate|Out-Null}catch{$unconfiguredCaught=$true};Assert-That $unconfiguredCaught 'unconfigured maintenance prerequisite is rejected'
    $staleFixture=$fixtureProvenance|ConvertTo-Json -Depth 8|ConvertFrom-Json; $staleFixture.candidate.payloadSha256=('0'*64); $staleCaught=$false; try { Assert-MaintenanceReadyProvenance -Provenance $staleFixture -Vm $fixtureVm -Snapshot $fixtureSnapshot -Fingerprint $candidate|Out-Null } catch {$staleCaught=$true}; Assert-That $staleCaught 'stale maintenance candidate provenance rejected'
    $transferSource=Join-Path $space 'stage.ps1'; $transferTarget=Join-Path $space 'remote-stage.ps1'; [IO.File]::WriteAllBytes($transferSource,[Text.Encoding]::UTF8.GetBytes("Write-Output 'ok'`n")); Copy-Item $transferSource $transferTarget; Assert-That ((Get-FileHash $transferSource).Hash -eq (Get-FileHash $transferTarget).Hash) 'stage transfer SHA equality'; Assert-That (-not ([IO.File]::ReadAllBytes($transferTarget) -contains 0)) 'UTF-8 stage has no null bytes'

    $old=Join-Path $temp 'stale-run-state.json'; Write-AtomicJson -Path $old -Value ([pscustomobject]@{runId='stale';timestamp=(Get-Date).AddDays(-2).ToString('o')}); Assert-That ((Read-StrictJson $old).runId -eq 'stale') 'stale state remains inspectable'
    $sw=[Diagnostics.Stopwatch]::StartNew(); Start-Sleep -Milliseconds 25; $sw.Stop(); Assert-That ($sw.ElapsedMilliseconds -lt 1000) 'bounded wait'; Assert-That ($sw.ElapsedMilliseconds -ge 0) 'no infinite polling'

    $configPath=Join-Path $WorkspaceRoot 'automation\release-e2e\config\devfleet-e2e.defaults.json'
    $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $linuxBootstrapSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'source\linux\bootstrap-compute.sh')
    $budgetPolicy=Get-HarnessBudgetPolicy -Config $config
    $guestComponentSum=[int](($budgetPolicy.guestBootstrapComponentsSeconds.PSObject.Properties.Value | Measure-Object -Sum).Sum)
    Assert-That ($guestComponentSum + 300 -eq [int]$budgetPolicy.operationMaximumsSeconds.guestBootstrap -and [int]$config.NestedLinux.BootstrapTimeoutSeconds -eq [int]$budgetPolicy.operationMaximumsSeconds.guestBootstrap) 'guest bootstrap timeout includes the explicit terminalization margin exactly once'
    Assert-That ([int]$budgetPolicy.stageBudgetsSeconds.compute -eq ([int]$budgetPolicy.operationMaximumsSeconds.multipassLaunch + [int]$budgetPolicy.operationMaximumsSeconds.multipassReadiness + [int]$budgetPolicy.operationMaximumsSeconds.payloadTransfer + [int]$budgetPolicy.operationMaximumsSeconds.guestBootstrap + [int]$budgetPolicy.operationMaximumsSeconds.sshAndMarker) -and [int]$budgetPolicy.stageBudgetsSeconds.vault -eq ([int]$budgetPolicy.operationMaximumsSeconds.vaultSnapshot + [int]$budgetPolicy.operationMaximumsSeconds.multipassLaunch + [int]$budgetPolicy.operationMaximumsSeconds.multipassReadiness + [int]$budgetPolicy.operationMaximumsSeconds.payloadTransfer + [int]$budgetPolicy.operationMaximumsSeconds.vaultBootstrap + [int]$budgetPolicy.operationMaximumsSeconds.sshAndMarker)) 'provisioning stages compose their role-specific child operation maxima'
    Assert-That ([int]$budgetPolicy.observerAbsoluteBudgetSeconds -gt [int]$budgetPolicy.productTransactionAbsoluteBudgetSeconds) 'observer absolute strictly dominates product transaction'
    Assert-That ([int]$budgetPolicy.fullReleaseWatchdogSeconds -gt [int]$budgetPolicy.observerAbsoluteBudgetSeconds) 'FullRelease watchdog strictly dominates observer absolute'
    Assert-That ([int]$budgetPolicy.exactProofOuterWatchdogSeconds -gt [int]$budgetPolicy.exactProofInnerBoundSeconds) 'exact-proof outer strictly dominates calculated inner bound'
    $prerequisiteMaximum = 6 * ([int]$budgetPolicy.operationMaximumsSeconds.dependencyProbe + [int]$budgetPolicy.operationMaximumsSeconds.dependencyHealth + [int]$budgetPolicy.operationMaximumsSeconds.dependencyInstall + [int]$budgetPolicy.operationMaximumsSeconds.dependencyVerification) + [int]$budgetPolicy.operationMaximumsSeconds.windowsCapability + [int]$budgetPolicy.operationMaximumsSeconds.windowsFeature + (4 * [int]$budgetPolicy.operationMaximumsSeconds.multipassConfiguration) + (3 * [int]$budgetPolicy.operationMaximumsSeconds.vscodeExtension)
    Assert-That ([int]$budgetPolicy.operationMaximumsSeconds.prerequisites -eq $prerequisiteMaximum) 'prerequisite stage is derived from every finite sequential operation'
    $plan=@(Get-FullReleasePhasePlan)
    $requiredPhases=@('HOST-SAFETY','CANDIDATE-VERIFY','RESTORE-CLEAN','ESTABLISH-SESSION','DEPENDENCY-MATRIX','SECURITY-POISON','FRESH-INSTALL-WPF','PRIMARY','LINUX','HTTP-HOSTILE','MAINTENANCE-READY','REPAIR','CLEAN-REINSTALL','UNINSTALL','FACTORY-RESET','REBOOT-RESUME','PERMANENT-DELETE','DELETE-RESTORE','STOPPED-PROJECT','HOST-CONCURRENCY','OPERATION-RECOVERY','OWNERSHIP','WINDOWS-SENTINELS','VAULT','SURROGATE-DISPOSABLE','REAL-USE-ACCEPTANCE','TAILSCALE-DEFERRED','TAILSCALE-AUTH','AI-BUNDLE','RECONCILE','CLEANUP')
    Assert-That (@($requiredPhases | Where-Object { @($plan.id) -notcontains $_ }).Count -eq 0) 'phase plan contains all configured mandatory phases'
    $rebootResumePhase=@($plan | Where-Object { [string]$_.id -ceq 'REBOOT-RESUME' })
    $maintenanceReadyPhase=@($plan | Where-Object { [string]$_.id -ceq 'MAINTENANCE-READY' })
    $realUseIndex=[Array]::IndexOf(@($plan.id),'REAL-USE-ACCEPTANCE')
    Assert-That ($rebootResumePhase.Count -eq 1 -and [string]$rebootResumePhase[0].checkpoint -ceq 'DevFleet-E2E-CLEAN' -and $maintenanceReadyPhase.Count -eq 1 -and [string]$maintenanceReadyPhase[0].checkpoint -ceq 'DevFleet-E2E-MAINTENANCE-READY') 'REBOOT-RESUME uses the clean product-install baseline while maintenance phases retain the installed maintenance baseline'
    Assert-That ($realUseIndex -gt 0 -and [string]$plan[$realUseIndex-1].id -ceq 'SURROGATE-DISPOSABLE' -and [string]$plan[$realUseIndex+1].id -ceq 'TAILSCALE-DEFERRED' -and $null -eq $plan[$realUseIndex].checkpoint -and [int]$config.RealUseAcceptance.TimeoutSeconds -eq 36000) 'REAL-USE-ACCEPTANCE consumes the installed Surrogate state before Tailscale checkpoint restoration under its bounded owner deadline'
    $executorRequired=@($requiredPhases | Where-Object { $_ -notin @('HOST-SAFETY','CANDIDATE-VERIFY','RESTORE-CLEAN','ESTABLISH-SESSION','MAINTENANCE-READY','CLEANUP') })
    $executorMissing=@($executorRequired | Where-Object { -not $config.FullReleaseExecutors.PSObject.Properties[$_] })
    Assert-That ($executorMissing.Count -eq 0) 'phase plan executor coverage'
    $realPhase=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1')
    $deadlineCommonSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'source\windows\DevFleet.Common.psm1')
    $fullReleaseBudgetSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\FullRelease.psm1')
    $realUseSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\RealUseAcceptance.psm1')
    $guestSessionSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\GuestSession.psm1')
    $exactProofSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'audit\run-exact-candidate-proof.ps1')
    Assert-That ($realPhase -match 'function ConvertTo-LfShellText' -and @([regex]::Matches($realPhase,'ConvertTo-LfShellText \$')).Count -ge 3 -and $realPhase -match '\.Replace\("`r`n", "`n"\)') 'Linux shell wrappers are materialized with LF-only line endings for Bash'
    $rootlessUserIndex=$linuxBootstrapSource.IndexOf('getent passwd devfleet-control')
    $controlGroupGrantIndex=$linuxBootstrapSource.IndexOf('run_bounded chown root:devfleet-control /var/lib/devfleet')
    $runtimeIndex=$linuxBootstrapSource.IndexOf('run_bounded install -d -o devfleet-control -g devfleet-control -m 0750 /var/lib/devfleet/runtime')
    Assert-That ($linuxBootstrapSource -match 'install -d -o root -g root -m 0750 /var/lib/devfleet' -and $rootlessUserIndex -ge 0 -and $controlGroupGrantIndex -gt $rootlessUserIndex -and $runtimeIndex -gt $controlGroupGrantIndex) 'Linux bootstrap grants the restricted control service traversal after creating its service group'
    $linuxRemoteStart=$realPhase.IndexOf('$linuxResult = Invoke-Command -Session $session -ScriptBlock {')
    $linuxRemoteHelper=$realPhase.IndexOf('function ConvertTo-LfShellText([string]$Text) {',$linuxRemoteStart)
    $linuxRemoteFirstUse=$realPhase.IndexOf('(ConvertTo-LfShellText $bootstrapScript)',$linuxRemoteStart)
    Assert-That ($linuxRemoteStart -ge 0 -and $linuxRemoteHelper -gt $linuxRemoteStart -and $linuxRemoteFirstUse -gt $linuxRemoteHelper) 'remote Linux script defines the LF conversion helper before using it'
    Assert-That ($realPhase -match "bootstrap-compute\.sh /tmp/devfleet-e2e-payload --secrets-stdin --transaction-id '__TRANSACTION_ID__' --payload-sha256 '__PAYLOAD_SHA256__' --bootstrap-max-seconds '__BOOTSTRAP_MAX_SECONDS__' --package-version '__PACKAGE_VERSION__' --node-role '__NODE_ROLE__'") 'nested Linux bootstrap binds every non-secret launch identity before secret stdin'
    Assert-That ($realPhase -match 'Get-HarnessBudgetPolicy' -and $realPhase -notmatch 'Math\]::Min\([^\r\n]*7200') 'observer consumes authoritative policy without silent 7200 clamp'
    Assert-That ($deadlineCommonSource -match 'DeadlineUtc \$deadline' -and $deadlineCommonSource -match 'remaining=\[int\]\[math\]::Floor') 'readiness probes consume remaining owning deadline'
    Assert-That ($deadlineCommonSource -match '\$deadlines = @\(\)' -and $deadlineCommonSource -match 'Measure-Object -Minimum') 'explicit child deadlines cannot escape the active owning stage'
    Assert-That ($guestSessionSource -match 'BeginInvoke\(\)' -and $guestSessionSource -match 'WaitOne\(60000\)' -and $guestSessionSource -match '\$pipeline\.Stop\(\)') 'guest-session establishment has an explicit finite open timeout'
    Assert-That ($deadlineCommonSource -match 'Get-DevFleetOperationMaximumSeconds.*guestBootstrap' -and $deadlineCommonSource -notmatch 'compute\s*=\s*9600|vault\s*=\s*9900') 'Windows stage budgets are composed from operation maxima'
    Assert-That ((Get-Content -Raw (Join-Path $WorkspaceRoot 'source\windows\02-Provision-ComputeNode.ps1')) -notmatch 'TimeoutSeconds 1800' -and (Get-Content -Raw (Join-Path $WorkspaceRoot 'source\windows\03-Provision-Vault.ps1')) -notmatch 'TimeoutSeconds 1800') 'compute and vault bootstrap use the derived guest operation budget'
    Assert-That ($fullReleaseBudgetSource -match 'Get-HarnessBudgetPolicy' -and $fullReleaseBudgetSource -match 'strictly exceed the observer absolute') 'FullRelease executor validates parent deadline hierarchy'
    Assert-That ($fullReleaseBudgetSource -match 'Assert-RealUseAcceptancePhaseEvidence' -and $realPhase -match "'REAL-USE-ACCEPTANCE'\s*\{\s*return Invoke-RealUseAcceptancePhase" -and $realPhase -match '\$required\s*=.*''REAL-USE-ACCEPTANCE''' -and $realUseSource -match 'Get-StageIntegrity' -and $realUseSource -match 'real-use-acceptance-report\.json' -and $realUseSource -match "systemctl','restart','devfleet\.service") 'REAL-USE-ACCEPTANCE uses native dispatch, durable validation, runner-only staging, and the exact service restart'
    Assert-That ($exactProofSource -match 'Assert-HarnessBudgetPolicy' -and $exactProofSource -match 'exactProofOuterWatchdogSeconds' -and $exactProofSource -notmatch 'Min\([^\r\n]*60000') 'exact proof rejects invalid outer bounds instead of silently truncating'
    Assert-That ($exactProofSource -match 'Proof lifecycle job failed:' -and $exactProofSource -match 'returned no terminal evidence \(state=') 'exact proof preserves failed child-job diagnostics'
    $pwshCommand=Get-Command pwsh.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1
    $pwshPath=[IO.Path]::GetFullPath([string]$pwshCommand.Source)
    if(-not(Test-Path -LiteralPath $pwshPath -PathType Leaf)-or[IO.Path]::GetFileName($pwshPath)-cne'pwsh.exe'){throw 'Harness could not resolve an exact PowerShell 7 executable.'}
    $behaviorTest=Join-Path $WorkspaceRoot 'automation\release-e2e\tests\Test-LifecycleObserverBehavior.ps1'
    if(Test-Path -LiteralPath $behaviorTest){
        $behaviorRaw=@(& $pwshPath -NoProfile -ExecutionPolicy Bypass -File $behaviorTest -WorkspaceRoot $WorkspaceRoot 2>$null)
        $behavior=$null;try{$jsonStart=0;while($jsonStart -lt $behaviorRaw.Count -and ([string]$behaviorRaw[$jsonStart]).Trim() -ne '{'){$jsonStart++};if($jsonStart -lt $behaviorRaw.Count){$behavior=($behaviorRaw[$jsonStart..($behaviorRaw.Count-1)] -join "`n")|ConvertFrom-Json}}catch{}
        Assert-That ($behavior -and [string]$behavior.status -eq 'PASS') 'behavioral lifecycle observer regressions execute and pass'
    }else{Assert-That $false 'behavioral lifecycle observer regression script exists'}
    foreach($focusedContract in @(
        @{path='automation\release-e2e\tests\Test-FinalizerNestedTerminalEvidence.ps1';name='production finalizer nested terminal evidence and status propagation regressions'},
        @{path='automation\release-e2e\tests\Test-FinalizerProcessExitBoundary.ps1';name='production release caller propagates finalizer child failure'},
        @{path='automation\release-e2e\tests\Test-TerminalCleanupBoundaries.ps1';name='production cleanup writer and nested evidence consumer regressions'},
        @{path='automation\release-e2e\tests\Test-WpfLaunchBoundaryBehavior.ps1';name='identity-bound WPF launch/report regressions'},
        @{path='automation\release-e2e\tests\Test-AuthorityTimestampRoundTrip.ps1';name='authority UTC round-trip regression'},
        @{path='automation\release-e2e\tests\Test-ToolRuntimeResolution.ps1';name='repository-local release-tool runtime resolution'},
        @{path='automation\release-e2e\tests\Test-TailscaleOAuthAutomation.ps1';name='Tailscale OAuth automation/readiness contract regressions'},
        @{path='automation\release-e2e\tests\Test-MaintenanceVaultPrivateFailurePreservation.ps1';name='Maintenance Vault encrypted failure-preservation regression'},
        @{path='automation\release-e2e\tests\Test-NestedProductScenarioContract.ps1';name='nested destructive scenario ownership and staging regressions'},
        @{path='automation\release-e2e\tests\Test-NestedProductScenarioArgumentBinding.ps1';name='nested scenario remoting identity argument binding regression'},
        @{path='automation\release-e2e\tests\Test-GuestSessionCredentialRetryBoundary.ps1';name='bounded guest-session credential retry regression'},
        @{path='automation\release-e2e\tests\Test-WpfProviderPowerShell51Compatibility.ps1';name='Windows PowerShell 5.1 bounded WPF provider compatibility regression';engine='powershell'}
    )){
        $focusedPath=Join-Path $WorkspaceRoot $focusedContract.path
        if(Test-Path -LiteralPath $focusedPath){
            $focusedEngine=if([string]$focusedContract.engine -ceq 'powershell'){Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'}else{$pwshPath}
            $focusedRaw=@(& $focusedEngine -NoProfile -ExecutionPolicy Bypass -File $focusedPath -WorkspaceRoot $WorkspaceRoot 2>$null)
            $focusedResult=$null;try{$jsonStart=0;while($jsonStart -lt $focusedRaw.Count -and ([string]$focusedRaw[$jsonStart]).Trim() -ne '{'){$jsonStart++};if($jsonStart -lt $focusedRaw.Count){$focusedResult=($focusedRaw[$jsonStart..($focusedRaw.Count-1)] -join "`n")|ConvertFrom-Json}}catch{}
            Assert-That ($focusedResult -and [string]$focusedResult.status -eq 'PASS') "$($focusedContract.name) execute and pass"
        }else{Assert-That $false "$($focusedContract.name) script exists"}
    }
    $interactiveTest=Join-Path $WorkspaceRoot 'automation\release-e2e\tests\Test-InteractiveLogonContracts.ps1'
    if(Test-Path -LiteralPath $interactiveTest){
        $interactiveRaw=@(& $pwshPath -NoProfile -ExecutionPolicy Bypass -File $interactiveTest -WorkspaceRoot $WorkspaceRoot 2>$null)
        $interactive=$null;try{$jsonStart=0;while($jsonStart -lt $interactiveRaw.Count -and ([string]$interactiveRaw[$jsonStart]).Trim() -ne '{'){$jsonStart++};if($jsonStart -lt $interactiveRaw.Count){$interactive=($interactiveRaw[$jsonStart..($interactiveRaw.Count-1)] -join "`n")|ConvertFrom-Json}}catch{}
        Assert-That ($interactive -and [string]$interactive.status -eq 'PASS') 'deterministic interactive autologon regressions execute and pass'
    }else{Assert-That $false 'interactive autologon regression script exists'}
    $linuxPhase=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-LinuxPhase.ps1')
    Assert-That ($realPhase -match 'Invoke-AiBundlePhase' -and $realPhase -notmatch "bundle='deferred to post-run verifier'") 'AI-BUNDLE waits for current verifier'
    Assert-That ($realPhase -match 'Invoke-ReconcilePhase' -and $realPhase -notmatch 'reconciled=\$true') 'RECONCILE performs actual checks'
    Assert-That ($realPhase -match 'generic Diagnostics is not a contract proof') 'generic Diagnostics cannot promote named contracts'
    Assert-That ($realPhase -match 'multipass.*launch' -and $realPhase -match 'bootstrap-compute\.sh' -and $realPhase -match 'rootless' -and $realPhase -match 'failureOperation' -and $realPhase -match "ErrorActionPreference='Continue'") 'LINUX has real nested bootstrap and native-error evidence contract'
    Assert-That ($realPhase -match "PSObject\.Properties\.Name -contains 'ArgumentList'" -and $realPhase -match '\$psi\.Arguments=' -and $realPhase -match 'quotedArguments') 'LINUX native Multipass launcher supports Windows PowerShell legacy argument transport'
    Assert-That ($realPhase -match "cloud-init/compute\.yaml" -and $realPhase -match "'--cloud-init'" -and $realPhase -match 'cloud-init status --format=json' -and $realPhase -match 'devrunnerIdentityPreBootstrap') 'LINUX applies exact candidate cloud-init before bootstrap'
    Assert-That ($realPhase -match 'ai-bundle-linux-roundtrip' -and $realPhase -match 'SOURCE-MODES\.json' -and $realPhase -match 'unzip -q' -and $realPhase -match 'validate_audit_coherence\.py' -and $realPhase -match 'python3 -m compileall' -and $realPhase -match "bash -n") 'focused LINUX can validate current AI bundle with standard unzip and POSIX modes'
    Assert-That ($realPhase -match 'sudo -n -u devfleet-control -- test -s /etc/devfleet/config\.json' -and $realPhase -match 'sudo -n -u devfleet-control -- jq -e \. /etc/devfleet/config\.json' -and $realPhase -match 'sudo -n -u devrunner test -S /run/user/\$uid/docker\.sock' -and $realPhase -match 'sudo -n -u devfleet-control -- stat -c %U:%G:%a /etc/devfleet/config\.json' -and $realPhase -match 'pass=\[bool\]\$pass') 'focused LINUX postconditions respect restricted identities and serialize booleans'
    $linuxQuiesceStopNeedle='Invoke-Mp @(''stop'',$productCompute)';$linuxLaunchNeedle='Invoke-Mp @(''launch'',$image';$linuxQuiesceStopIndex=$realPhase.IndexOf($linuxQuiesceStopNeedle);$linuxLaunchIndex=$realPhase.IndexOf($linuxLaunchNeedle)
    Assert-That ($realPhase -match 'Get-DevFleetProductComputeInstanceName -Context \$context -Role ''Primary / Desktop''' -and $realPhase -match 'productQuiescence' -and $realPhase -match 'initialState' -and $realPhase -match 'finalState' -and $realPhase -match "-cne'Stopped'" -and $linuxQuiesceStopIndex -ge 0 -and $linuxLaunchIndex -gt $linuxQuiesceStopIndex) 'LINUX quiesces the exact candidate-bound product child before allocating the nested L2'
    Assert-That ($linuxPhase.Length -gt 100 -and $linuxPhase -notmatch 'syntax|sourceOnly|WSL') 'LINUX executor is not a syntax-only stub'
    $httpPhase=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-HttpHostilePhase.ps1')
    Assert-That ($httpPhase -match 'test_request_admission\.py' -and $httpPhase -match 'candidate\.tar\.sha256') 'HTTP-HOSTILE runs exact candidate request-admission regressions'
    Assert-That ($realPhase -match 'Invoke-SurrogateDisposablePhase' -and $realPhase -match "Role 'Laptop / Surrogate'") 'disposable surrogate uses real candidate WPF role path'
    $intentionalMandatoryThrows=@('STOPPED-PROJECT','HOST-CONCURRENCY','OPERATION-RECOVERY','OWNERSHIP','VAULT')|Where-Object{$realPhase -match ("'"+[regex]::Escape($_)+"'\s*\{\s*throw")}
    Assert-That ($intentionalMandatoryThrows.Count -eq 0) 'mandatory phase executors contain no intentional throw stubs'
    Assert-That ($realPhase -notmatch "'REBOOT-RESUME'\s*\{\s*return Invoke-ActualWpfAction.*'Resume'") 'reboot/resume crosses a real process and boot boundary'
    Assert-That ($realPhase -match 'AllowRebootRequired' -and $realPhase -match "REAL E2E REBOOT REQUIRED" -and $realPhase -match 'Invoke-ProductFreshInstallLifecycle') 'reboot/resume records the expected WPF reboot-required boundary through the product lifecycle loop'
    Assert-That ($realPhase -match "'OBSERVER_HANDOFF'\s*\{\s*'REAL E2E OBSERVER HANDOFF'" -and $realPhase -match "'REBOOT_REQUIRED'\s*\{\s*'REAL E2E REBOOT REQUIRED'") 'observer ownership transfer and REBOOT_REQUIRED remain distinct harness outcomes'
    Assert-That ($realPhase -match 'Test-RebootBoundaryIdentity' -and $realPhase -match 'checkpointGeneration.*-ne.*PriorCheckpoint.*\+ 1') 'generation advancement, not generation-1 presence, authorizes another reboot'
    Assert-That ($realPhase -match 'Get-PhaseAwareBudgetSeconds' -and $realPhase -match 'NoProgressBudgetSeconds' -and $realPhase -match 'AbsoluteBudgetSeconds') 'product lifecycle observer uses two bounded phase-aware clocks'
    Assert-That ($realPhase -match '\$guestProcessId=Get-LifecycleProperty \$currentGuest ''processId''' -and $realPhase -match '\$guestProcessId=Get-LifecycleProperty \$current ''processId''' -and $realPhase -match '\$candidateProcessId=if\(' -and $realPhase -match '-CandidateProcessId \$candidateProcessId' -and $realPhase -notmatch '-CandidateProcessId \(if\(') 'product lifecycle observer resolves top-level or nested process identity through valid PowerShell expressions'
    Assert-That ($realPhase -match 'ProgramData\\DevFleetHostAgent\\integration-ownership\.json') 'durable completion observes canonical Host Agent ownership path'
    Assert-That ($realPhase -match 'Invoke-SupportedFreshInstallLifecycle' -and $realPhase -match 'CompleteLifecycle') 'shared supported fresh-install lifecycle helper is used by dependent phases'
    Assert-That ($realPhase -match 'Wait-DevFleetProductLifecycleTransition' -and $realPhase -match "outcome='NEXT_REBOOT'" -and $realPhase -match "outcome='COMPLETED'" -and $realPhase -match "outcome='TERMINAL_FAILURE'" -and $realPhase -match "outcome='NO_PROGRESS_TIMEOUT'" -and $realPhase -match "'ABSOLUTE_TIMEOUT'") 'progress-aware lifecycle observer has bounded semantic terminal outcomes'
    Assert-That ($realPhase -match 'Invoke-ProductFreshInstallLifecycle' -and $realPhase -match 'resume-generation-' -and $realPhase -match 'transactionId=') 'complete lifecycle uses one same-transaction product-owned loop instead of replacement FreshInstall'
    Assert-That ($realPhase -match "SURROGATE-DISPOSABLE requires genuine final lifecycle PASS" -and $realPhase -notmatch "return \[ordered\]@\{status=''REAL E2E PASS'';phase=''SURROGATE-DISPOSABLE''[\s\S]{0,120}result\.status") 'surrogate rejects intermediate lifecycle states'
    Assert-That ($realPhase -match "LINUX requires a genuine supported FreshInstall lifecycle PASS") 'Linux rejects intermediate lifecycle states before Multipass'
    Assert-That ($realPhase -notmatch 'DEVFLEET_DEPENDENCY_FIXTURE' -and $realPhase -match 'ADVERSARIAL_PRODUCT_POLICY' -and $realPhase -match 'REAL_DISPOSABLE_L1') 'dependency matrix distinguishes one real healthy path from adversarial policy rows'
    Assert-That ($realPhase -match 'Get-LifecycleProperty -Value \$healthy -Name ''status''' -and $realPhase -match 'Get-LifecycleProperty -Value \$healthy -Name ''candidate''' -and $realPhase -match 'Get-LifecycleProperty -Value \$healthyGuest -Name ''completionVerified''' -and $realPhase -notmatch '\$healthy\.candidate|\$healthy\.guest\.completionVerified') 'dependency matrix preserves terminal lifecycle evidence without masking failures through missing properties'
    Assert-That ($realPhase -match 'DependencyPolicyRunner\.csproj' -and $realPhase -match 'actualConditionProven' -and $realPhase -notmatch "scenario=\$scenario[\s\S]{0,180}status=''PASS''") 'dependency adversarial rows come from the executable policy runner'
    Assert-That ($realPhase -match 'synthetic-reboot-probe\.json' -and $realPhase -match 'pendingCount' -and $realPhase -match 'MoveFileEx') 'synthetic probe records pre-existing pending state before its exact trigger'
    Assert-That ($realPhase -match 'unrelatedEntriesPreserved' -and $realPhase -notmatch 'synthetic probe baseline has unrelated pending state' -and $realPhase -notmatch 'Remove-ItemProperty.*PendingFileRenameOperations' -and $realPhase -notmatch 'Set-ItemProperty.*PendingFileRenameOperations') 'baseline pending state is preserved and never cleared by the harness'
    Assert-That ($realPhase.Contains('MoveFileEx') -and $realPhase.Contains('MoveFileEx($source,$destination,4)') -and $realPhase -match 'run-owned-PFRO-only' -and -not $realPhase.Contains('Enable-WindowsOptionalFeature')) 'synthetic reboot is one exact run-owned delayed move, not optional-feature servicing'
    Assert-That ($realPhase -match 'settled' -and $realPhase -match 'sourceExists' -and $realPhase -match 'destinationExists' -and $realPhase -match 'synthetic.*delayed operation did not settle') 'synthetic probe independently verifies bounded delayed-move settlement before desktop restore'
    Assert-That ($realPhase -notmatch "'TAILSCALE-(?:DEFERRED|AUTH)'\s*\{\s*return Invoke-ActualWpfAction.*'FreshInstall'") 'Tailscale phases use their official phase-specific flow'
    $nestedStart=$realPhase.IndexOf('function Invoke-NestedProductScenario')
    $nestedEnd=$realPhase.IndexOf('function Invoke-DisposableSyntheticRebootProbe',$nestedStart)
    $nestedSource=if($nestedStart -ge 0 -and $nestedEnd -gt $nestedStart){$realPhase.Substring($nestedStart,$nestedEnd-$nestedStart)}else{''}
    $readinessStart=$realPhase.IndexOf('function Get-DevFleetNestedPrimaryReadinessScriptBlock')
    $readinessBody=if($readinessStart-ge0-and$nestedStart-gt$readinessStart){$realPhase.Substring($readinessStart,$nestedStart-$readinessStart)}else{''}
    Assert-That ($nestedSource -match 'Get-DevFleetNestedPrimaryReadinessScriptBlock' -and $readinessBody -match 'function Invoke-NestedMultipass' -and $readinessBody -match 'WaitForExit\(' -and $readinessBody -match 'WhenAll' -and $readinessBody -match 'bounded-disposable-nested-HyperV-powercycle' -and $nestedSource -match 'multipassReadiness' -and $nestedSource -notmatch '(?m)^\s*&\s*\$mp\s+(?:list|info|start|exec|transfer)') 'nested product phases bound every Multipass operation and recover a stale disposable Hyper-V primary before SSH work'
    Assert-That ($realPhase -match 'checkpointReadRaceRecovered' -and $realPhase -match 'if\(-not \(Test-Path -LiteralPath \$checkpointPath -PathType Leaf\)\)') 'lifecycle observation tolerates a checkpoint disappearing during the final read while preserving fail-closed completion checks'
    $fullReleaseSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\FullRelease.psm1')
    $interactiveLogonSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\InteractiveLogon.psm1')
    $wpfExecutorSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1')
    $wpfDriverSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-WpfUiAutomation.ps1')
    $wpfContractSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\WpfLaunchContract.psm1')
    $guestSessionSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\GuestSession.psm1')
    $focusedMaintenanceSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\Invoke-FocusedMaintenanceSentinels.ps1')
    $cleanupSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\Cleanup.psm1')
    $entrypointSource=Get-Content -Raw (Join-Path $WorkspaceRoot 'automation\release-e2e\Invoke-DevFleetReleaseE2E.ps1')
    Assert-That (($config.FullReleaseExecutors.PSObject.Properties['CLEANUP'] -or $fullReleaseSource -match "phase\.id -eq 'CLEANUP'") -and $fullReleaseSource -match 'Get-AssertedDisposableVm' -and $fullReleaseSource -notmatch '(?:Start|Stop)-VM\s+-Name\s+\$Vm\.Name' -and $cleanupSource -match 'Get-VM\s+-Id' -and $cleanupSource -match 'Stop-VM\s+-VM' -and $entrypointSource -match 'Stop-ManifestVm\s+-Manifest' -and $entrypointSource -notmatch 'Stop-VM\s+-Name\s+\$vm\.Name' -and $realPhase -match 'SHA256\]::Create\(\)' -and $realPhase -notmatch 'SHA256\]::HashData' -and $realPhase.Contains("'binPath=' `$serviceCommand 'start=' 'disabled' 'DisplayName='")) 'CLEANUP and sentinel setup use ID-bound, Windows-PowerShell-compatible paths'
    Assert-That ($fullReleaseSource -match "status='NOT RUN'" -and $fullReleaseSource -match "record\.status='BLOCKED'") 'FullRelease evidence distinguishes BLOCKED and NOT RUN'
    Assert-That ($fullReleaseSource -match 'maintenance-ready-provenance-v1' -and $fullReleaseSource -match 'Checkpoint-VM' -and $fullReleaseSource -match 'Invoke-MaintenanceReadyGuestValidation' -and $fullReleaseSource -match 'Remove-VMSnapshot' -and $fullReleaseSource -notmatch 'AdoptLegacyDevFleetIntegrations') 'MAINTENANCE-READY is provenance-bound and reprovisions without legacy adoption'
    Assert-That ($fullReleaseSource.Contains("PSObject.Properties['product']") -and $fullReleaseSource.Contains("PSObject.Properties['synthetic']")) 'MAINTENANCE-READY accepts completion authority shape without StrictMode-unsafe optional properties'
    Assert-That ($fullReleaseSource.Contains('function Get-MaintenanceReadyFirewallActual') -and $fullReleaseSource.Contains('function Get-MaintenanceReadyFirewallExpected') -and $fullReleaseSource.Contains('Read-DevFleetIntegrationOwnership -Path $ownershipPath') -and $fullReleaseSource.Contains('function Assert-MaintenanceReadyFirewallBinding') -and $fullReleaseSource.Contains('Assert-DevFleetFirewallRefreshIdentity') -and $fullReleaseSource.Contains('WaitSeconds=60') -and $fullReleaseSource.Contains('Start-Sleep -Seconds 1') -and $fullReleaseSource.Contains('firewallConvergence')) 'MAINTENANCE-READY reloads provider-backed ledger state within a bounded wait while failing closed on immutable ownership'
    Assert-That ($fullReleaseSource.Contains('function Invoke-MaintenanceReadyAuthenticatedHealth') -and $fullReleaseSource.Contains('catch [Net.WebException]') -and $fullReleaseSource.Contains('hostAgentHealthProbeAttempts') -and $fullReleaseSource.Contains('WaitSeconds 60')) 'MAINTENANCE-READY waits only for bounded Host Agent connection readiness and preserves fail-closed health validation'
    Assert-That ($interactiveLogonSource -match 'boundExplorer' -and $interactiveLogonSource -match 'activeInteractiveSessionId' -and $interactiveLogonSource -match 'Assert-DevFleetE2EInteractiveDesktop') 'interactive desktop readiness binds the exact E2E user and active Explorer session'
    Assert-That ($wpfDriverSource -match 'Candidate UI window disappeared during completion polling' -and $wpfDriverSource -match 'processExited' -and $wpfDriverSource -match 'OBSERVER_HANDOFF') 'WPF driver reports window-loss diagnostics instead of hanging silently'
    Assert-That ($wpfExecutorSource -match 'UseDurableCompletionFallback' -and $wpfExecutorSource -match 'DURABLE_REBOOT_RESUME_FALLBACK' -and $wpfExecutorSource -match 'Invoke-MaintenanceReadyGuestValidation' -and $wpfExecutorSource -match 'Invoke-HostAgentAuthenticatedJson' -and $wpfExecutorSource -match 'checkpoint remains present') 'reboot-resume fallback requires durable state and authenticated health'
    Assert-That ($wpfExecutorSource -match '\[switch\]\$UseDurableCompletionFallback' -and $wpfExecutorSource -match 'DeferDurableCompletionFallback' -and $wpfExecutorSource -match 'Invoke-ProductFreshInstallLifecycle' -and $wpfExecutorSource -match 'completionVerified') 'product lifecycle defers WPF fallback and uses the observer as durable completion authority'
    Assert-That ($wpfDriverSource -match 'WorkerMode' -and $wpfDriverSource -match 'Wait-WpfBoundReport' -and $wpfDriverSource -match "cleanupDisposition -eq 'CLEANUP_EXACT_CANDIDATE'" -and $wpfContractSource -match "'OBSERVER_HANDOFF'.*'RELINQUISH_LIFECYCLE_OWNER'" -and $wpfContractSource -match "'OBSERVER_FAILURE'.*'RELINQUISH_LIFECYCLE_OWNER'") 'isolated UIA worker has explicit observer-transfer, observer-failure, and exact-candidate cleanup ownership'
    Assert-That ($wpfDriverSource -match 'using System;\s+using System\.Text;\s+using System\.Runtime\.InteropServices;\s+public static class DevFleetE2EWin32' -and $wpfDriverSource -match "FindWindow\('#32770','Confirm exact plan'\)" -and $wpfDriverSource -match 'FindWindowEx\(\$dialog' -and $wpfDriverSource -match 'GetWindowText' -and $wpfDriverSource -match 'GetDlgCtrlID' -and $wpfDriverSource -match 'SendMessa