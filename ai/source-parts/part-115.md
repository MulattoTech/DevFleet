# DevFleet source part 115

Full-source UTF-8 byte interval [5301000, 5347500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: e6a9e3a653220f37c7e7d7717d73fd55bef56b09ca533f32868cf6e4c18b1e36

<!-- BEGIN SOURCE SLICE -->
uired = $rebuildRequired
        failedReplacementAttempt = if ($failedAttemptContract) { $state.failed_replacement_attempt } else { $null }
        selfTest = [string]$state.self_test
        authenticode = if ($candidateArtifacts.exe.exists) { try { [string](Get-AuthenticodeSignature -LiteralPath (Join-Path $Workspace $candidateArtifacts.exe.path)).Status } catch { 'UNAVAILABLE' } } else { 'MISSING' }
        signingState = [string]$artifactManifest.signingState; privateSigningProfile = [string]$artifactManifest.privateSigningProfile
        signerSubject = [string]$signingProvider.signerSubject; signerThumbprint = [string]$signingProvider.signerThumbprint
        codeSigningEku = [string]$signingProvider.codeSigningEku; rsaBits = [int]$signingProvider.rsaBits
        privateKeyExportable = [bool]$signingProvider.privateKeyExportable; privateKeyExported = [bool]$signingProvider.privateKeyExported
        timestampState = [string]$signingProvider.timestampState; signatureStatus = [string]$signingProvider.signatureStatus
        tamperedCopyVerification = [string]$signingProvider.tamperedCopyVerification
        publicPublisherTrust = [bool]$signingProvider.publicPublisherTrust; publicPromotionAllowed = [bool]$signingProvider.publicPromotionAllowed
        embeddedTarIdentity = [ordered]@{tarSha256=$candidateArtifacts.tar.sha256;selfTestPayload=([string]$state.self_test -match [regex]::Escape($candidateArtifacts.tar.sha256))}
    }
    $authorityPath = Join-Path $Workspace 'evidence\CURRENT-RELEASE-AUTHORITY.json'
    $currentStatusPath = Join-Path $Workspace 'evidence\CURRENT-STATUS.json'
    $currentGatesPath = Join-Path $Workspace 'evidence\CURRENT-GATES.json'
    $currentProofPath = Join-Path $Workspace 'evidence\CURRENT-PROOF.json'
    $fullSummaryPath = Join-Path $Workspace 'evidence\FULLRELEASE-SUMMARY.json'
    $currentHandoffPath = Join-Path $Workspace 'evidence\CURRENT-HANDOFF.json'
    foreach($authorityFile in @($authorityPath,$currentStatusPath,$currentGatesPath,$currentProofPath,$fullSummaryPath,$currentHandoffPath)){if(-not(Test-Path -LiteralPath $authorityFile -PathType Leaf)){throw "Current authority file is missing: $authorityFile"}}
    $currentAuthority=Read-Json $authorityPath;$currentStatus=Read-Json $currentStatusPath;$currentGates=Read-Json $currentGatesPath;$currentProof=Read-Json $currentProofPath;$fullReleaseSummary=Read-Json $fullSummaryPath;$currentHandoff=Read-Json $currentHandoffPath
    $authorityId=[string]$currentAuthority.authorityId
    if($authorityId -notmatch '^[0-9a-f]{64}$' -or @(@($currentStatus,$currentGates,$currentProof,$fullReleaseSummary,$currentHandoff)|Where-Object{[string]$_.authorityId -cne $authorityId}).Count){throw 'Current release authority files do not share one authorityId.'}
    foreach($authorityRecord in @($currentAuthority,$currentStatus,$currentGates,$currentProof,$fullReleaseSummary,$currentHandoff)){
        if([string]$authorityRecord.repositoryHead -cne $head -or [string]($authorityRecord.candidateCommit ?? $authorityRecord.candidateGitCommit) -cne $candidateCommit -or [string]$authorityRecord.shippingInputIdentity -cne $candidateShippingInputIdentity -or [string]$authorityRecord.releaseFingerprintId -cne $releaseId -or [string]$authorityRecord.toolingFingerprintId -cne $toolingId){throw 'Current release authority tuple is stale or contradictory.'}
    }
    $authorityWorkingShipping=[string]$currentAuthority.workingTree.shippingInputIdentity
    $crlfWorkingTupleAccepted=$crlfOnlyMaterialization -and $authorityWorkingShipping -ceq $candidateComputedIdentity
    if(($authorityWorkingShipping -cne $rawLiveShippingInputIdentity -and -not $crlfWorkingTupleAccepted) -or [string]$currentAuthority.workingTree.toolingFingerprintId -cne $workingToolingId){throw 'Current release authority working-tree tuple is stale or contradictory.'}
    if (-not $preAcceptanceAudit -and -not $finalAcceptanceValid) { $status=[string]$currentAuthority.status }
    $bundleMode=if($preAcceptanceAudit -or $finalAcceptanceValid){'release'}else{'diagnostic'}
    $releaseValidationMode=if($preAcceptanceAudit){'pre-acceptance'}else{$bundleMode}
    $candidate.authorityId=$authorityId
    Write-Json (Join-Path $stage 'CURRENT-CANDIDATE.json') $candidate

    $runRoot = Join-Path $Audit 'automation-harness\runs'
    $explicitFullReleaseId = [string]$state.full_release_run_id
    $latestRun = if ((Test-Path -LiteralPath $runRoot -PathType Container) -and $explicitFullReleaseId) { Get-Item -LiteralPath (Join-Path $runRoot $explicitFullReleaseId) -ErrorAction SilentlyContinue } else { $null }
    if ($latestRun) {
        $runStateFile = Join-Path $latestRun.FullName 'run-state.json'
        if (Test-Path -LiteralPath $runStateFile) {
            $runState = Read-Json $runStateFile
            $fullReleaseSummary.latestRunId=$latestRun.Name; $fullReleaseSummary.status=[string]$runState.finalStatus; $fullReleaseSummary.lastCompletedPhase=@($runState.completedPhases | Select-Object -Last 1); $fullReleaseSummary.historicalEvidenceOnly=$false
            $fullReleaseSummary.candidateTuple=$runState.candidateHashes
            New-Item -ItemType Directory -Force -Path (Join-Path $evidenceStage 'current-fullrelease') | Out-Null
            Copy-Item -LiteralPath $runStateFile -Destination (Join-Path $evidenceStage "current-fullrelease\run-state.json") -Force
            foreach($name in @('fullrelease-phase-records.json','l1-terminal-state.json','l2-terminal-state.json','nested-l2-terminal-observation.json','reconcile-finalization.json','final-cleanup.json','post-cleanup-finalization.json','dependency-policy-runner.json','dotnet-sdk-evidence.json','real-use-acceptance-binding.json','real-use-acceptance-prepare.json','real-use-acceptance-report.json','real-use-acceptance-evidence.json')) {
                Add-CompactFile (Join-Path $latestRun.FullName $name) (Join-Path $evidenceStage "current-fullrelease\$name") | Out-Null
            }
            # Final bundles expose the authoritative terminal files at the
            # current-evidence root as well as under the bound FullRelease.
            foreach($terminalName in @('l1-terminal-state.json','l2-terminal-state.json')) {
                Add-CompactFile (Join-Path $latestRun.FullName $terminalName) (Join-Path $evidenceStage $terminalName) | Out-Null
            }
        }
    }
    # Exact proof runs are authoritative even when they do not emit a
    # FullRelease run-state.json. Preserve one compact, secret-safe current
    # proof directory so an independent auditor can inspect the blocker.
    $explicitProofId = [string]$state.current_proof_run_id
    $proofIds = if ($bundleMode -eq 'release') {
        @($currentAuthority.proofs.runs | ForEach-Object { [string]$_.runId } | Where-Object { $_ } | Select-Object -Unique)
    } else {
        @(@($state.proof_run_ids)+@($state.diagnostic_run_ids)+$explicitProofId|Where-Object{$_}|Select-Object -Unique)
    }
    $proofRuns = if ((Test-Path -LiteralPath $runRoot -PathType Container) -and $proofIds.Count) { @($proofIds | ForEach-Object { Get-Item -LiteralPath (Join-Path $runRoot $_) -ErrorAction SilentlyContinue } | Where-Object { $_.PSIsContainer -and $_.Name -match '^e2e-(?:(?:exact-candidate-)?proof|lifecycle-diagnostic)' -and (Test-Path (Join-Path $_.FullName 'proof-start.json')) }) } else { @() }
    if ($proofRuns.Count -gt 0) {
        $proofRun = @($proofRuns | Where-Object Name -ceq $explicitProofId | Select-Object -First 1)[0]; if(-not $proofRun){$proofRun=$proofRuns[0]}; $proofStage = Join-Path $evidenceStage 'current-proof'; New-Item -ItemType Directory -Force -Path $proofStage | Out-Null
        $proofFiles = @('proof-start.json','proof-final.json','proof-error.json','product-checkpoint-boundary.json','product-lifecycle-terminal.json','product-lifecycle-observer-summary.json','product-lifecycle-observer-generation-0.json','product-lifecycle-observer-generation-1.json','product-lifecycle-observer-generation-2.json','product-lifecycle-observer-generation-3.json','product-lifecycle-provider-failure.json','product-lifecycle-progress.jsonl','product-lifecycle-progress-current.json','product-lifecycle-generation-1.json','product-lifecycle-generation-2.json','product-lifecycle-generation-3.json','product-lifecycle-completion-authority.json','FreshInstall-wpf-evidence.json','initial-FreshInstall-wpf-evidence.json','resume-generation1-wpf-evidence.json','resume-generation-1-wpf-evidence.json','resume-generation2-wpf-evidence.json','resume-generation-2-wpf-evidence.json','resume-generation3-wpf-evidence.json','resume-generation-3-wpf-evidence.json','final-FreshInstall-wpf-evidence.json','reboot-resume-new-process-wpf-evidence.json','durable-observation-samples.json','cleanup-state.json','reboot-resume-baseline-preflight.json','l1-terminal-state.json','l2-terminal-state.json')
        foreach ($name in $proofFiles) { $match=Get-ChildItem -LiteralPath $proofRun.FullName -Filter $name -File -Recurse -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1;if($match){Add-CompactFile $match.FullName (Join-Path $proofStage $name)|Out-Null} }
        # Retain the exact current launch/request/driver/checkpoint/terminal
        # lineage. Launch IDs keep the two WPF legs distinct; no historical
        # record can satisfy a current proof merely by sharing a generic name.
        $nestedWpfStage = Join-Path $proofStage 'nested-wpf'
        foreach ($pattern in @('wpf-*-launch-request.json','wpf-*-driver-bound.json','wpf-*-checkpoint.json','wpf-*-worker-terminal.json','wpf-*-terminal.json')) {
            foreach ($match in @(Get-ChildItem -LiteralPath $proofRun.FullName -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
                Add-CompactFile $match.FullName (Join-Path $nestedWpfStage $match.Name) | Out-Null
            }
        }
        # Retain every explicitly bound fair proof run, but keep the current
        # pointer separate so historical runs can never become current by
        # directory timestamp alone.
        $proofArchive = Join-Path $evidenceStage 'proof-runs'; New-Item -ItemType Directory -Force -Path $proofArchive | Out-Null
        foreach ($run in $proofRuns) {
            $runStage = Join-Path $proofArchive $run.Name; New-Item -ItemType Directory -Force -Path $runStage | Out-Null
            foreach ($name in $proofFiles) { $match=Get-ChildItem -LiteralPath $run.FullName -Filter $name -File -Recurse -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1;if($match){Add-CompactFile $match.FullName (Join-Path $runStage $name)|Out-Null} }
        }
        foreach ($terminalName in @('l1-terminal-state.json','l2-terminal-state.json')) {
            Add-CompactFile (Join-Path $proofRun.FullName $terminalName) (Join-Path $evidenceStage $terminalName) | Out-Null
        }
        $proofStart = if (Test-Path -LiteralPath (Join-Path $proofRun.FullName 'proof-start.json')) { try { Read-Json (Join-Path $proofRun.FullName 'proof-start.json') } catch { $null } } else { $null }
        $proofError = if (Test-Path -LiteralPath (Join-Path $proofRun.FullName 'proof-error.json')) { try { Read-Json (Join-Path $proofRun.FullName 'proof-error.json') } catch { $null } } else { $null }
        $proofTerminal = if (Test-Path -LiteralPath (Join-Path $proofRun.FullName 'product-lifecycle-terminal.json')) { try { Read-Json (Join-Path $proofRun.FullName 'product-lifecycle-terminal.json') } catch { $null } } else { $null }
        if($proofStart) {
            $historicalRoot=Join-Path $toolingStage ("historical\{0}" -f $proofRun.Name);New-Item -ItemType Directory -Force -Path $historicalRoot | Out-Null
            # These commits are the exact Git objects whose bytes were bound
            # by the preserved proof-start record; they are never replaced by
            # current tooling bytes.
            $proofSourceCommit=[string]$proofStart.provenance.repositoryHead
            if($proofSourceCommit -notmatch '^[0-9a-f]{40}$'){throw "Proof $($proofRun.Name) has no exact tooling source commit."}
            Add-GitBlob $proofSourceCommit 'audit/run-exact-candidate-proof.ps1' (Join-Path $historicalRoot 'run-exact-candidate-proof.ps1') | Out-Null
            Add-GitBlob $proofSourceCommit 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1' (Join-Path $historicalRoot 'Invoke-RealProductPhase.psm1') | Out-Null
            Add-GitBlob $proofSourceCommit 'automation/release-e2e/modules/executors/Invoke-WpfUiAutomation.ps1' (Join-Path $historicalRoot 'Invoke-WpfUiAutomation.ps1') | Out-Null
            $historicalBindings=@(@{name='proofScriptSha256';file='run-exact-candidate-proof.ps1'},@{name='invokeRealProductPhaseSha256';file='Invoke-RealProductPhase.psm1'},@{name='invokeWpfUiAutomationSha256';file='Invoke-WpfUiAutomation.ps1'})
            if($proofStart.provenance.PSObject.Properties.Name -contains 'wpfLaunchContractSha256'){
                Add-GitBlob $proofSourceCommit 'automation/release-e2e/modules/executors/WpfLaunchContract.psm1' (Join-Path $historicalRoot 'WpfLaunchContract.psm1') | Out-Null
                $historicalBindings+=@{name='wpfLaunchContractSha256';file='WpfLaunchContract.psm1'}
            }
            $historicalBindingEvidence=@()
            $historicalBindingMismatch=$false
            foreach($binding in $historicalBindings){
                $expected=[string]$proofStart.provenance.($binding.name)
                $observed=Get-Hash (Join-Path $historicalRoot $binding.file)
                $matches=($expected -match '^[0-9a-f]{64}$' -and $observed -ceq $expected)
                if(-not $matches){$historicalBindingMismatch=$true}
                $historicalBindingEvidence+=[ordered]@{name=$binding.name;file=$binding.file;expectedSha256=$expected;observedSha256=$observed;matches=$matches}
            }
            if($historicalBindingMismatch -and $bundleMode -ne 'diagnostic'){throw "Proof $($proofRun.Name) historical source binding failed outside diagnostic mode."}
            Add-CompactFile (Join-Path $proofRun.FullName 'proof-start.json') (Join-Path $historicalRoot 'proof-start.json') | Out-Null
            $sourceCommitMap=[ordered]@{proofScript=$proofSourceCommit;invokeRealProductPhase=$proofSourceCommit;invokeWpfUiAutomation=$proofSourceCommit}
            if($proofStart.provenance.PSObject.Properties.Name -contains 'wpfLaunchContractSha256'){$sourceCommitMap.wpfLaunchContract=$proofSourceCommit}
            Write-Json (Join-Path $historicalRoot 'historical-source-manifest.json') ([ordered]@{schemaVersion=2;runId=$proofRun.Name;proofStartSource='proof-start.json';sourceCommitMap=$sourceCommitMap;verification=if($historicalBindingMismatch){'MISMATCH_RETAINED_FOR_DIAGNOSTIC'}else{'PASS'};bindings=$historicalBindingEvidence;releaseEligible=$false;note=if($historicalBindingMismatch){'The immutable proof-start hashes do not match the claimed repositoryHead Git blobs. The commit snapshot is retained as unverified context and is not promoted.'}else{'Every retained historical source matches proof-start provenance.'}})
        }
        # Only the proof runner's own proof-final record is a natural proof
        # terminal result.  Product lifecycle/provider terminal diagnostics
        # remain nested evidence and must not promote a blocked proof pointer.
        $proofFinalPath = Join-Path $proofRun.FullName 'proof-final.json'
        $proofFinal = if (Test-Path -LiteralPath $proofFinalPath) { try { Read-Json $proofFinalPath } catch { $null } } else { $null }
        $proofOutcome = if ($proofFinal) { [string]$proofFinal.outcome } else { 'NOT_OBSERVED' }
        $proofCompleted = [string]$proofOutcome -in @('PASS','REAL E2E PASS','COMPLETED')
        # A preserved interrupted proof may have been started with an older
        # tooling fingerprint. Keep its exact proof-start bytes in the
        # archived run, but do not let that historical tuple masquerade as a
        # current authority. A naturally completed proof started with the
        # current tooling remains fully bound here.
        $proofStartForCurrent = if ($proofStart -and [string]$proofStart.provenance.toolingFingerprint -eq $toolingId) { $proofStart } else { $null }
        if([string]$currentProof.runId -ceq $proofRun.Name -and [string]$currentProof.outcome -eq 'PASS' -and -not $proofCompleted){throw 'Current proof authority claims PASS without a natural proof-final PASS record.'}
    }
    if(-not $failedAttemptContract){[void](Add-AstraCausalEvidence $Workspace $evidenceStage)}
    Write-Json (Join-Path $evidenceStage 'CURRENT-PROOF.json') $currentProof
    foreach($terminalName in @('l1-terminal-state.json','l2-terminal-state.json')) {
        Add-CompactFile (Join-Path $Workspace "evidence\$terminalName") (Join-Path $evidenceStage $terminalName) | Out-Null
    }
    $baselinePointerPath=Join-Path $Workspace 'evidence\baselines\CURRENT.json'
    if(Test-Path -LiteralPath $baselinePointerPath -PathType Leaf){
        $baselinePointer=Read-Json $baselinePointerPath
        $baselineReceiptFile=[string]$baselinePointer.receiptFile
        if($baselineReceiptFile -cnotmatch '^[0-9a-f]{32}\.json$'){throw 'Accepted baseline receipt filename is invalid.'}
        $baselineReceiptPath=Join-Path $Workspace (Join-Path 'evidence\baselines\receipts' $baselineReceiptFile)
        if((Get-Hash $baselineReceiptPath) -cne [string]$baselinePointer.receiptSha256){throw 'Accepted baseline receipt hash does not match its pointer.'}
        if(-not(Add-CompactFile $baselineReceiptPath (Join-Path $evidenceStage "baselines\receipts\$baselineReceiptFile"))){throw 'Accepted baseline receipt is missing.'}
        if([int]$baselinePointer.generation -eq 2){
            $previousHash=[string]$baselinePointer.previousPointerSha256
            if($previousHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Rebound baseline predecessor hash is invalid.'}
            $historyPath=Join-Path $Workspace "evidence\baselines\history\$previousHash.json"
            if((Get-Hash $historyPath) -cne $previousHash){throw 'Rebound baseline predecessor pointer hash differs.'}
            $previousPointer=Read-Json $historyPath
            $previousReceiptFile=[string]$previousPointer.receiptFile
            if([int]$previousPointer.generation -ne 1 -or $previousReceiptFile -cnotmatch '^[0-9a-f]{32}\.json$'){throw 'Rebound baseline predecessor pointer is invalid.'}
            $previousReceiptPath=Join-Path $Workspace (Join-Path 'evidence\baselines\receipts' $previousReceiptFile)
            if((Get-Hash $previousReceiptPath) -cne [string]$previousPointer.receiptSha256){throw 'Rebound baseline predecessor receipt hash differs.'}
            if(-not(Add-CompactFile $historyPath (Join-Path $evidenceStage "baselines\history\$previousHash.json"))){throw 'Rebound baseline predecessor pointer is missing.'}
            if(-not(Add-CompactFile $previousReceiptPath (Join-Path $evidenceStage "baselines\receipts\$previousReceiptFile"))){throw 'Rebound baseline predecessor receipt is missing.'}
        }
        if(-not(Add-CompactFile $baselinePointerPath (Join-Path $evidenceStage 'baselines\CURRENT.json'))){throw 'Accepted baseline pointer is missing.'}
    }
    $interactiveLoginEvidence=Join-Path $Workspace 'evidence\CURRENT-INTERACTIVE-LOGIN.json'
    if(Test-Path -LiteralPath $interactiveLoginEvidence -PathType Leaf){Add-CompactFile $interactiveLoginEvidence (Join-Path $evidenceStage 'CURRENT-INTERACTIVE-LOGIN.json') | Out-Null}
    Write-Json (Join-Path $evidenceStage 'CURRENT-STATUS.json') $currentStatus
    Write-Json (Join-Path $evidenceStage 'CURRENT-GATES.json') $currentGates
    Write-Json (Join-Path $evidenceStage 'FULLRELEASE-SUMMARY.json') $fullReleaseSummary
    Write-Json (Join-Path $evidenceStage 'CURRENT-RELEASE-AUTHORITY.json') $currentAuthority
    # Standard-token evidence is an independent release obligation.  Carry the
    # atomic pointer plus the exact immutable raw/canonical bytes it names.
    $standardPointerPath = Join-Path $Workspace 'evidence\CURRENT-STANDARD-TOKEN.json'
    if (Test-Path -LiteralPath $standardPointerPath -PathType Leaf) {
        $standardPointer = Read-Json $standardPointerPath
        $standardRunId = [string]$standardPointer.runId
        if ($standardRunId -notmatch '^standard-token-[A-Za-z0-9-]+$') { throw 'CURRENT-STANDARD-TOKEN RunId is malformed.' }
        $standardRunRoot = Join-Path $Workspace "evidence\standard-token\$standardRunId"
        foreach ($standardName in @('installer-self-test-raw.txt','standard-token-evidence.json')) {
            $standardSource = Join-Path $standardRunRoot $standardName
            if (-not (Add-CompactFile $standardSource (Join-Path $evidenceStage "standard-token\$standardRunId\$standardName"))) { throw "Immutable standard-token evidence is missing: $standardName" }
        }
        Add-CompactFile $standardPointerPath (Join-Path $evidenceStage 'CURRENT-STANDARD-TOKEN.json') | Out-Null
    } elseif ($bundleMode -eq 'release') { throw 'Release audit/bundle requires CURRENT-STANDARD-TOKEN.json.' }

    # A final release bundle embeds FINAL-ACCEPTANCE and the immutable
    # pre-acceptance audit report/manifest/validation it closes over.  The
    # archive itself remains outside the bundle to avoid recursive archives.
    if ($finalAcceptanceValid -and -not $preAcceptanceAudit) {
        $finalAcceptancePath = Join-Path $Workspace 'evidence\FINAL-ACCEPTANCE.json'
        $releaseAuditPointerPath = Join-Path $Workspace 'evidence\CURRENT-RELEASE-AUDIT.json'
        if (-not (Add-CompactFile $finalAcceptancePath (Join-Path $evidenceStage 'FINAL-ACCEPTANCE.json'))) { throw 'Valid FINAL-ACCEPTANCE disappeared while staging.' }
        if (-not (Add-CompactFile $releaseAuditPointerPath (Join-Path $evidenceStage 'CURRENT-RELEASE-AUDIT.json'))) { throw 'CURRENT-RELEASE-AUDIT disappeared while staging.' }
        $releaseAuditPointer = Read-Json $releaseAuditPointerPath
        foreach ($bindingName in @('report','manifest','releaseValidation')) {
            $binding = $releaseAuditPointer.evidence.$bindingName
            $workspaceRelative = ([string]$binding.workspacePath).Replace('/','\')
            $bundleRelative = [string]$binding.bundlePath
            if ($workspaceRelative -notmatch '^audit\\release-audits\\[A-Za-z0-9-]+\\[A-Za-z0-9._-]+$' -or $bundleRelative -notmatch '^evidence/release-audits/[A-Za-z0-9-]+/[A-Za-z0-9._-]+$') { throw "Release-audit $bindingName binding path is unsafe." }
            $sourceBinding = Join-Path $Workspace $workspaceRelative
            $destinationBinding = Join-Path $stage ($bundleRelative.Replace('/','\'))
            if (-not (Add-CompactFile $sourceBinding $destinationBinding)) { throw "Immutable release-audit binding is missing: $bindingName" }
            if ((Get-Hash $sourceBinding) -cne [string]$binding.sha256 -or [int64](Get-Item -LiteralPath $sourceBinding).Length -ne [int64]$binding.bytes) { throw "Immutable release-audit binding changed: $bindingName" }
        }
    }
    $triageJson = Join-Path $Audit 'external-ai-findings-triage-v1.2.13.json'; $triageMd = Join-Path $Audit 'external-ai-findings-triage-v1.2.13.md'
    Add-CompactFile $triageJson (Join-Path $auditStage 'external-ai-findings-triage-v1.2.13.json') | Out-Null
    Add-CompactFile $triageMd (Join-Path $auditStage 'external-ai-findings-triage-v1.2.13.md') | Out-Null
    foreach ($evidenceName in @('production-ram-h10.json','resource-policy-h10.json','linux-native-h10.json','registry-persistence-attribution.json')) {
        Add-CompactFile (Join-Path $Audit $evidenceName) (Join-Path $auditStage $evidenceName) | Out-Null
    }
    foreach ($durableName in @('CODEX-RESUME-CHECKPOINT.json','CODEX-RESUME-CHECKPOINT.md','NEXT-CODEX-HANDOFF.json','NEXT-CODEX-HANDOFF.md')) {
        $sourceDurable = Join-Path $Audit $durableName
        if(-not (Test-Path -LiteralPath $sourceDurable)){ continue }
        # This checkpoint is a superseded, candidate-invalidation-era resume
        # record. Preserve it in the bundle, but keep it under the explicit
        # historical namespace so coherence tooling cannot treat its old
        # tuple as a current authority.
        $historical = $durableName -like 'CODEX-RESUME-CHECKPOINT.*'
        if($durableName -like '*.json' -and -not $historical){
            try { $historical = [bool]((Read-Json $sourceDurable).historical) } catch { $historical = $false }
        } elseif($durableName -notlike '*.json') {
            $historical = (Get-Content -LiteralPath $sourceDurable -Raw) -match '(?im)historical|superseded|obsolete'
        }
        $destination = if($historical){ New-Item -ItemType Directory -Force -Path (Join-Path $auditStage 'historical') | Out-Null; Join-Path $auditStage "historical\$durableName" } else { Join-Path $auditStage $durableName }
        Add-CompactFile $sourceDurable $destination | Out-Null
    }
    Add-CompactFile (Join-Path $Workspace 'audit\FINALIZER-PRIMARY-BLOCKER.json') (Join-Path $auditStage 'FINALIZER-PRIMARY-BLOCKER.json') | Out-Null
    $afterActionReport = Join-Path $Workspace 'audit\AFTER-ACTION-REPORT.md'
    if (Test-Path -LiteralPath $afterActionReport -PathType Leaf) {
        Add-CompactFile $afterActionReport (Join-Path $auditStage 'AFTER-ACTION-REPORT.md') | Out-Null
    }
    foreach ($coordinationName in @('YOLO-RESUME-HANDOFF.json','YOLO-RESUME-HANDOFF.md','SOL-HELPER-ALLOCATION-LEDGER.json','SOL-HELPER-FINDINGS.json')) {
        Add-CompactFile (Join-Path $Audit $coordinationName) (Join-Path $auditStage $coordinationName) | Out-Null
    }
    foreach ($campaignName in @('wpf-no-report-20260905-ledger.json','wpf-replay2-terminal-cleanup.json')) {
        $campaignEvidence = Join-Path $Workspace "evidence\campaigns\$campaignName"
        if (Test-Path -LiteralPath $campaignEvidence -PathType Leaf) {
            Add-CompactFile $campaignEvidence (Join-Path $evidenceStage "campaigns\$campaignName") | Out-Null
        }
    }
    Add-AuthorizationLedgerClosure -Repository $Workspace -EvidenceRoot $evidenceStage | Out-Null
    $readinessStage = Join-Path $evidenceStage 'readiness-runs'
    foreach ($readinessRun in @(Get-ChildItem -LiteralPath $runRoot -Directory -Filter 'wpf-boundary-stable-readiness-*' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $readinessResult = Join-Path $readinessRun.FullName 'wpf-boundary-contract-diagnostic.json'
        if (Test-Path -LiteralPath $readinessResult -PathType Leaf) {
            Add-CompactFile $readinessResult (Join-Path $readinessStage "$($readinessRun.Name)\wpf-boundary-contract-diagnostic.json") | Out-Null
        }
    }
    $diagnosticStage = Join-Path $evidenceStage 'wpf-boundary-diagnostics'
    foreach ($diagnosticRun in @(Get-ChildItem -LiteralPath $runRoot -Directory -Filter 'wpf-boundary-live-diagnostic-*' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 2)) {
        $diagnosticResult = Join-Path $diagnosticRun.FullName 'wpf-boundary-contract-diagnostic.json'
        if (Test-Path -LiteralPath $diagnosticResult -PathType Leaf) {
            Add-CompactFile $diagnosticResult (Join-Path $diagnosticStage "$($diagnosticRun.Name)\wpf-boundary-contract-diagnostic.json") | Out-Null
        }
    }
    $blockerClassification=[string]$currentAuthority.blockerClassification
    $nextAction=[string]$currentAuthority.nextAction
    Write-Json (Join-Path $auditStage 'CURRENT-HANDOFF.json') $currentHandoff
    Write-Json (Join-Path $evidenceStage 'CURRENT-HANDOFF.json') $currentHandoff
    # A failed replacement attempt has three current blocker records that
    # must travel together.  Copy the authoritative records after any
    # historical-proof synthesis so a generated bundle cannot silently
    # substitute an older CURRENT-PROOF or omit the binding evidence.
    $evidenceInventory = @()
    if ($failedAttemptContract) {
        $requiredBlockerRecords = @(
            @{ source = (Join-Path $Workspace 'evidence\CURRENT-PROOF.json'); destination = (Join-Path $evidenceStage 'CURRENT-PROOF.json'); relative = 'evidence/CURRENT-PROOF.json' },
            @{ source = (Join-Path $Workspace 'audit\attemptedReplacementCandidate.json'); destination = (Join-Path $auditStage 'attemptedReplacementCandidate.json'); relative = 'audit/attemptedReplacementCandidate.json' },
            @{ source = (Join-Path $Workspace 'audit\candidateBindingFailure.json'); destination = (Join-Path $auditStage 'candidateBindingFailure.json'); relative = 'audit/candidateBindingFailure.json' }
        )
        foreach ($record in $requiredBlockerRecords) {
            if (-not (Add-CompactFile $record.source $record.destination)) { throw "Failed-attempt diagnostic blocker record is missing: $($record.relative)" }
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $auditStage 'external-ai-findings-triage-v1.2.13.json'))) { Write-Json (Join-Path $auditStage 'external-ai-findings-triage-v1.2.13.json') ([ordered]@{schemaVersion=1;status='NOT_IMPORTED_IN_THIS_SESSION';candidate=$candidate;findings=@()}) }
    if (-not (Test-Path -LiteralPath (Join-Path $auditStage 'external-ai-findings-triage-v1.2.13.md'))) { Set-Content -LiteralPath (Join-Path $auditStage 'external-ai-findings-triage-v1.2.13.md') -Value '# DevFleet v1.2.13 external AI findings`n`nNo external finding file was available in the current workspace.' -Encoding UTF8 }
    foreach ($evidenceRoot in @($auditStage,$evidenceStage)) {
        if (-not (Test-Path -LiteralPath $evidenceRoot -PathType Container)) { continue }
        foreach ($evidenceFile in @(Get-ChildItem -LiteralPath $evidenceRoot -Recurse -File -Force)) {
            $relativeEvidence = $evidenceFile.FullName.Substring($stage.Length).TrimStart('\','/').Replace('\','/')
            $evidenceInventory += [ordered]@{path=$relativeEvidence;bytes=[int64]$evidenceFile.Length;sha256=(Get-Hash $evidenceFile.FullName);mode='0644'}
        }
    }
    # OrderedDictionary keys are not Sort-Object properties. Use an explicit
    # key expression or -Unique collapses the complete inventory to one row.
    $evidenceInventory = @($evidenceInventory | Sort-Object { $_['path'] } -Unique)
    Write-Json (Join-Path $stage 'EVIDENCE-MODES.json') @($evidenceInventory | ForEach-Object { [ordered]@{path=$_.path;posixMode=420;mode='0644';executable=$false} })
    Set-Content -LiteralPath (Join-Path $stage 'EVIDENCE-SHA256SUMS.txt') -Value @($evidenceInventory | ForEach-Object { '{0}  {1}' -f $_.sha256,$_.path }) -Encoding UTF8

    $readme = @("# DevFleet v$releaseVersion — Universal AI Audit Bundle",'',"This is the one canonical source, tooling, compact-evidence, and audit bundle for independent review by ChatGPT, Gemini, Grok, Claude, or another reviewer.","", "Status: $status", "DevFleet: $releaseVersion / installer: $installerVersion", "Git: $branch / $head", "Current candidate: $candidateIsCurrent; source changed: $sourceChanged; rebuild required: $rebuildRequired",'', 'The bundle intentionally excludes compiled release binaries, nested archives, VM images, caches, credentials, tokens, and raw giant transcripts. The exact binary names, sizes, hashes, PE/AuthentiCode result, embedded TAR identity, and release/tooling fingerprints are in CURRENT-CANDIDATE.json.', '', 'The complete release-E2E automation source is under automation/release-e2e/. Historical evidence is explicitly marked and is not promoted to current-candidate PASS.', '', "Clean-extraction entrypoint: python release-tooling/run_portable_audit_tests.py --root . --output portable-audit-test-result.json", "Bundle validator: python source/tools/validate_ai_audit_bundle.py --archive DevFleet-v$releaseVersion-AI-Audit-LATEST.zip --mode $bundleMode")
    Set-Content -LiteralPath (Join-Path $stage 'AUDIT-README.md') -Value $readme -Encoding UTF8
    $manifest = [ordered]@{schemaVersion=2;bundle='DevFleet Universal AI Audit';status=$status;authorityId=$authorityId;generatedAt=(Get-Date).ToUniversalTime().ToString('o');devfleetVersion=$releaseVersion;installerVersion=$installerVersion;repositoryHead=$head;gitCommit=$head;candidateGitCommit=$candidateCommit;branch=$branch;shippingInputIdentity=$currentShippingInputIdentity;candidateShippingInputIdentity=$candidateShippingInputIdentity;workingTreeTuple=$candidate.workingTreeTuple;shippingModeContract=$identity.candidateShippingModeContract;candidateIsCurrent=$candidateIsCurrent;sourceChangedSinceCandidate=$sourceChanged;rebuildRequired=$rebuildRequired;releaseFingerprintId=$releaseId;toolingFingerprintId=$toolingId;expectedSourceCount=$inventory.Count;includedSourceCount=$inventory.Count;sourceInventory=$inventory;evidenceInventory=$evidenceInventory;candidate=$candidate;historicalProvenance=$historicalProvenance;exclusions=@('.git','.venv','.venv-*','node_modules','bin','obj','.pytest_cache','__pycache__','build caches','VHDX','ISO','VM snapshots','raw giant E2E transcripts','browser profiles','credentials','tokens','private keys','compiled artifacts');releaseE2EToolingIncluded=$true;compiledArtifactsEmbedded=$false;selfTestStatus='PASS';entrypoints=[ordered]@{portableAuditTests='release-tooling/run_portable_audit_tests.py';pathResolver='release-tooling/audit_bundle_paths.py';auditValidator='source/tools/validate_ai_audit_bundle.py';coherenceValidator='source/tools/validate_audit_coherence.py';releaseValidator='release-tooling/validate_release_bundle.py'};dependencySecurity=[ordered]@{customGate='outputs/dependency-advisory-gate.json';independentOracle='outputs/independent-osv-reconciliation.json'}}
    Write-Json (Join-Path $stage 'AUDIT-MANIFEST.json') $manifest

    # The candidate-bound source validator stays byte-identical in source/;
    # current authority/coherence checks run from release-tooling/.  A blocked
    # historical tuple is explicitly diagnostic and must be accepted only as
    # PASS_WITH_BLOCKER; the candidate validator is never allowed to silently
    # fall back to the release mode.
    & $python (Join-Path $toolingStage 'validate_audit_coherence.py') --root $stage
    if ($LASTEXITCODE -ne 0) { throw 'Universal AI Audit current-authority coherence validation failed.' }
    # The immutable shipping validator runs in the same explicit mode as the
    # packaged wrapper.  It is a required validator, including diagnostic
    # bundles; a failed candidate-bound result is never tolerated or relabeled.
    $candidateValidatorOutput = @(& $python (Join-Path $stage 'source/tools/validate_audit_coherence.py') --root $stage --mode $bundleMode 2>&1)
    $candidateValidatorExit = $LASTEXITCODE
    if ($candidateValidatorExit -ne 0) { throw "Universal AI Audit candidate-bound validator failed ($bundleMode): $($candidateValidatorOutput -join "`n")" }
    try { $candidateValidatorResult = ($candidateValidatorOutput -join "`n") | ConvertFrom-Json } catch { throw "Universal AI Audit candidate-bound validator did not return JSON: $($_.Exception.Message)" }
    $expectedCandidateStatus = if ($bundleMode -eq 'diagnostic') { 'PASS_WITH_BLOCKER' } else { 'PASS' }
    if ([string]$candidateValidatorResult.status -ne $expectedCandidateStatus -or ($bundleMode -eq 'diagnostic' -and [bool]$candidateValidatorResult.releaseEligible)) { throw "Universal AI Audit candidate-bound validator returned an invalid $bundleMode result." }
    Write-Json (Join-Path $toolingStage 'candidate-bound-validator-result.json') ([ordered]@{schemaVersion=1;status=[string]$candidateValidatorResult.status;releaseEligible=[bool]$candidateValidatorResult.releaseEligible;bundleMode=$bundleMode;exitCode=$candidateValidatorExit;repositoryHead=$head;candidateCommit=$candidateCommit;output=($candidateValidatorOutput -join "`n");candidateValidatorIsShippingSource=$true})

    # The validator result is generated only after the staged source closure
    # has been checked, but it is itself part of that closure.  Bind its bytes
    # into the inventory, modes, and checksum list before packaging so the
    # packaged validator cannot report an unexplained extra release-tooling
    # file.
    $candidateResultPath = Join-Path $toolingStage 'candidate-bound-validator-result.json'
    $candidateResultRelative = 'release-tooling/candidate-bound-validator-result.json'
    $candidateResultFile = Get-Item -LiteralPath $candidateResultPath
    $inventory += [ordered]@{path=$candidateResultRelative;bytes=[int64]$candidateResultFile.Length;sha256=(Get-Hash $candidateResultPath);root='release-tooling';mode='0644'}
    $modeInventory += [ordered]@{path=$candidateResultRelative;posixMode=420;mode='0644';executable=$false}
    # Other compact historical proof files are intentionally staged after the
    # initial walk.  Reconcile the complete staged source closure here so all
    # such evidence is explicitly hashed rather than appearing as an
    # unclassified package extra.
    $knownInventoryPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $inventory) { [void]$knownInventoryPaths.Add([string]$entry.path) }
    foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse -Force) {
        $relative = ([IO.Path]::GetFullPath($file.FullName)).Substring($stage.Length).TrimStart('\','/').Replace('\','/')
        if ($relative -notmatch '^(source|installer-source|automation/release-e2e|release-tooling)/' -or $knownInventoryPaths.Contains($relative)) { continue }
        $inventory += [ordered]@{path=$relative;bytes=[int64]$file.Length;sha256=(Get-Hash $file.FullName);root=($relative.Split('/')[0]);mode='0644'}
        $modeInventory += [ordered]@{path=$relative;posixMode=420;mode='0644';executable=$false}
        [void]$knownInventoryPaths.Add($relative)
    }
    $hashLines = @($inventory | ForEach-Object { '{0}  {1}' -f $_.sha256,$_.path })
    Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Value $hashLines -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $stage 'AUDIT-TREE.txt') -Value (@('DevFleet universal AI audit source tree','') + @($inventory | ForEach-Object path)) -Encoding UTF8
    Write-Json (Join-Path $stage 'SOURCE-MODES.json') $modeInventory
    $manifest.sourceInventory = $inventory
    $manifest.expectedSourceCount = $inventory.Count
    $manifest.includedSourceCount = $inventory.Count
    Write-Json (Join-Path $stage 'AUDIT-MANIFEST.json') $manifest

    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    & $python (Join-Path $Workspace 'source\tools\write_posix_zip.py') --stage $stage --output $zipPath --modes (Join-Path $stage 'SOURCE-MODES.json')
    if ($LASTEXITCODE -ne 0) { throw 'Universal AI Audit ZIP creation failed.' }
    $validator = Join-Path $Workspace 'source\tools\validate_ai_audit_bundle.py'
    $aiOutput = @(& $python $validator --archive $zipPath --report (Join-Path $Audit 'ai-audit-bundle-self-test.json') --mode $bundleMode)
    $bundleSelfTestExit = $LASTEXITCODE
    if ($bundleSelfTestExit -ne 0) { throw "Universal AI Audit ZIP $bundleMode self-test failed: $($aiOutput -join "`n")" }
    try { $aiResult = ($aiOutput -join "`n") | ConvertFrom-Json } catch { throw "Universal AI Audit validator did not return JSON: $($_.Exception.Message)" }
    $expectedAiStatus = if ($bundleMode -eq 'diagnostic') { 'PASS_WITH_BLOCKER' } else { 'COMPLETE_FOR_AI_AUDIT' }
    if ([string]$aiResult.status -ne $expectedAiStatus -or ($bundleMode -eq 'diagnostic' -and [bool]$aiResult.releaseEligible)) { throw "Universal AI Audit validator returned an invalid $bundleMode result." }
    $releaseValidator = Join-Path $Workspace 'tools\validate_release_bundle.py'
    $releaseOutput = @(& $python $releaseValidator --archive $zipPath --mode $releaseValidationMode)
    if ($LASTEXITCODE -ne 0) { throw "Post-cleanup $releaseValidationMode release-bundle validation failed: $($releaseOutput -join "`n")" }
    try { $releaseResult = ($releaseOutput -join "`n") | ConvertFrom-Json } catch { throw "Release-bundle validator did not return JSON: $($_.Exception.Message)" }
    $expectedReleaseStatus = if ($bundleMode -eq 'diagnostic') { 'PASS_WITH_BLOCKER' } else { 'PASS' }
    if ([string]$releaseResult.status -ne $expectedReleaseStatus -or (($bundleMode -eq 'diagnostic' -or $preAcceptanceAudit) -and [bool]$releaseResult.releaseEligible)) { throw "Release-bundle validator returned an invalid $releaseValidationMode result." }
    $zipBytes = [int64](Get-Item -LiteralPath $zipPath).Length; $zipSha = Get-Hash $zipPath
    $selfTestStatus = if($bundleSelfTestExit -eq 0){'PASS'}else{'DIAGNOSTIC-PASS — candidate-bound validator correctly rejected advanced tooling HEAD'}
    if ($preAcceptanceAudit) {
        $releaseAuditReportPath = Join-Path $Audit 'ai-audit-bundle-self-test.json'
        $releaseAuditReport = Read-Json $releaseAuditReportPath
        foreach ($entry in ([ordered]@{archiveSha256=$zipSha;archiveBytes=$zipBytes;candidateTuple=$releaseResult.candidateTuple;fullReleaseRunId=[string]$releaseResult.fullReleaseRunId;standardTokenRunId=[string]$releaseResult.standardTokenRunId;proofRunIds=@($releaseResult.proofRunIds);internalPromotionAllowed=$false;publicPromotionAllowed=$false;publicPublisherTrust=$false}).GetEnumerator()) {
            if ($releaseAuditReport.PSObject.Properties.Name -contains $entry.Key) { $releaseAuditReport.($entry.Key) = $entry.Value }
            else { $releaseAuditReport | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value }
        }
        Write-Json $releaseAuditReportPath $releaseAuditReport
    }
    Write-Json $manifestPath ([ordered]@{path=([IO.Path]::GetFullPath($zipPath));bytes=$zipBytes;sha256=$zipSha;expectedSourceCount=$inventory.Count;includedSourceCount=$inventory.Count;releaseE2EToolingIncluded=$true;status=$status;selfTest=$selfTestStatus})
    if ($preAcceptanceAudit) {
        # Preserve the audit and all of its verification products beneath a
        # never-overwritten run directory before publishing the current
        # pointer. FINAL-ACCEPTANCE is intentionally absent from this archive.
        $effectiveAuditRunId = if ($ReleaseAuditRunId) { $ReleaseAuditRunId } else { "release-audit-$explicitFullReleaseId" }
        if ($effectiveAuditRunId -notmatch '^release-audit-[A-Za-z0-9-]+$') { throw 'Release-audit RunId is malformed.' }
        $releaseAuditParent = Join-Path $Audit 'release-audits'
        $releaseAuditFinal = Join-Path $releaseAuditParent $effectiveAuditRunId
        if (Test-Path -LiteralPath $releaseAuditFinal) { throw "Immutable release-audit run already exists: $effectiveAuditRunId" }
        New-Item -ItemType Directory -Force -Path $releaseAuditParent | Out-Null
        $releaseAuditStage = Join-Path $releaseAuditParent (".{0}.{1}.tmp" -f $effectiveAuditRunId,[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $releaseAuditStage | Out-Null
        $preValidationName = 'pre-acceptance-validation.json'
        $preValidationPath = Join-Path $releaseAuditStage $preValidationName
        Write-Json $preValidationPath $releaseResult
        $immutableArchiveName = 'release-audit.zip'
        $immutableReportName = 'ai-audit-bundle-self-test.json'
        $immutableManifestName = 'release-audit.manifest.json'
        Copy-Item -LiteralPath $zipPath -Destination (Join-Path $releaseAuditStage $immutableArchiveName)
        Copy-Item -LiteralPath (Join-Path $Audit 'ai-audit-bundle-self-test.json') -Destination (Join-Path $releaseAuditStage $immutableReportName)
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $releaseAuditStage $immutableManifestName)
        Move-Item -LiteralPath $releaseAuditStage -Destination $releaseAuditFinal
        $releaseAuditStage = $null
        $archiveImmutable = Join-Path $releaseAuditFinal $immutableArchiveName
        $reportImmutable = Join-Path $releaseAuditFinal $immutableReportName
        $manifestImmutable = Join-Path $releaseAuditFinal $immutableManifestName
        $validationImmutable = Join-Path $releaseAuditFinal $preValidationName
        $auditWorkspacePrefix = "audit/release-audits/$effectiveAuditRunId"
        $auditBundlePrefix = "evidence/release-audits/$effectiveAuditRunId"
        $releaseAuditPointer = [ordered]@{
            schemaVersion=1; contract='devfleet-pre-acceptance-release-audit-v1'; runId=$effectiveAuditRunId
            generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o'); status='PASS'; bundleMode='release'
            releaseEligible=$false; internalPromotionAllowed=$false; publicPromotionAllowed=$false; publicPublisherTrust=$false
            candidate=[ordered]@{repositoryHead=$head;candidateCommit=$candidateCommit;shippingInputIdentity=$candidateShippingInputIdentity;releaseFingerprintId=$releaseId;toolingFingerprintId=$toolingId}
            fullReleaseRunId=[string]$releaseResult.fullReleaseRunId; standardTokenRunId=[string]$releaseResult.standardTokenRunId; proofRunIds=@($releaseResult.proofRunIds)
            inputs=[ordered]@{fullReleaseRunStateSha256=[string]$workspaceValidation.fullRelease.runStateSha256;fullReleasePhaseRecordsSha256=[string]$workspaceValidation.fullRelease.phaseRecordsSha256;realUseBindingSha256=[string]$workspaceValidation.fullRelease.realUseBindingSha256;realUsePrepareSha256=[string]$workspaceValidation.fullRelease.realUsePrepareSha256;realUseReportSha256=[string]$workspaceValidation.fullRelease.realUseReportSha256;realUseSummarySha256=[string]$workspaceValidation.fullRelease.realUseSummarySha256;cleanupSha256=[string]$workspaceValidation.fullRelease.cleanupSha256;postCleanupSha256=[string]$workspaceValidation.fullRelease.postCleanupSha256;terminalL1Sha256=[string]$workspaceValidation.fullRelease.l1Sha256;terminalL2Sha256=[string]$workspaceValidation.fullRelease.l2Sha256;standardTokenPointerSha256=[string]$workspaceValidation.standardToken.pointerSha256;proofRunIds=@($workspaceValidation.proofRunIds)}
            evidence=[ordered]@{
                archive=[ordered]@{workspacePath="$auditWorkspacePrefix/$immutableArchiveName";bundlePath=$null;bytes=[int64](Get-Item $archiveImmutable).Length;sha256=(Get-Hash $archiveImmutable)}
                report=[ordered]@{workspacePath="$auditWorkspacePrefix/$immutableReportName";bundlePath="$auditBundlePrefix/$immutableReportName";bytes=[int64](Get-Item $reportImmutable).Length;sha256=(Get-Hash $reportImmutable)}
                manifest=