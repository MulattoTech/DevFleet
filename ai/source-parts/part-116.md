# DevFleet source part 116

Full-source UTF-8 byte interval [5347500, 5394000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8ac38a3fe7f7026a5fc7c3f30ae99531cb530c541d8ab8fa5cc000db95f2be04

<!-- BEGIN SOURCE SLICE -->
ndently recomputed
        # CRLF-only path. Row hashes alone cannot prove normalized-content
        # equality, so diagnostic validation consumes this materialization.
        foreach ($historicalPath in $historicalCrlfPaths) {
            $historicalDestination = Join-Path $stage ('release-tooling\historical-candidate-2739\' + ($historicalPath -replace '/','\'))
            Add-GitBlob $candidateCommit $historicalPath $historicalDestination | Out-Null
        }
    }
    if ($failedAttemptContract) {
        Add-CompactFile $failedAttemptSnapshotPath (Join-Path $auditStage ($failedAttemptSnapshotRelative -replace '^audit/','')) | Out-Null
    }
    # Preserve distinct repository/tooling HEAD and candidate commit fields;
    # staging must never rewrite current HEAD to the signed candidate.
    $proofRunner = Join-Path $Workspace 'audit\run-exact-candidate-proof.ps1'
    if (Test-Path -LiteralPath $proofRunner -PathType Leaf) {
        Add-CompactFile $proofRunner (Join-Path $toolingStage 'proof-entrypoints\run-exact-candidate-proof.ps1') | Out-Null
    }
    # Every source hash recorded by proof-start is independently verifiable
    # under the non-shipping release-tooling namespace.
    Add-CompactFile (Join-Path $Workspace 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1') (Join-Path $toolingStage 'proof-entrypoints\Invoke-RealProductPhase.psm1') | Out-Null
    Add-CompactFile (Join-Path $Workspace 'automation\release-e2e\modules\executors\Invoke-WpfUiAutomation.ps1') (Join-Path $toolingStage 'proof-entrypoints\Invoke-WpfUiAutomation.ps1') | Out-Null
    Add-CompactFile (Join-Path $Workspace 'automation\release-e2e\modules\executors\WpfLaunchContract.psm1') (Join-Path $toolingStage 'proof-entrypoints\WpfLaunchContract.psm1') | Out-Null
    $stagedState = Read-Json $statePath
    if ($stagedState.PSObject.Properties.Name -contains 'repository_head') { $stagedState.repository_head = $head }
    else { $stagedState | Add-Member -NotePropertyName repository_head -NotePropertyValue $head }
    # Regenerated/staged authority must carry the same exact reviewed path set
    # consumed by the live partition and candidate-bound validators.
    if ($null -eq $stagedState.authorized_correction) {
        $stagedState | Add-Member -NotePropertyName authorized_correction -NotePropertyValue ([pscustomobject]@{ shipping_paths=@() }) -Force
    } elseif ($null -eq $stagedState.authorized_correction.shipping_paths) {
        $stagedState.authorized_correction | Add-Member -NotePropertyName shipping_paths -NotePropertyValue @() -Force
    }
    $stagedState.authorized_correction.shipping_paths = @($authorizedShippingPaths)
    Write-Json (Join-Path $stage 'finalization-state.json') $stagedState
    $stagedArtifactManifest = Read-Json $artifactPath
    if ($stagedArtifactManifest.PSObject.Properties.Name -contains 'repositoryHead') { $stagedArtifactManifest.repositoryHead = $head }
    else { $stagedArtifactManifest | Add-Member -NotePropertyName repositoryHead -NotePropertyValue $head }
    Write-Json (Join-Path $outputMetadataStage 'final-artifact-hashes.json') $stagedArtifactManifest
    Copy-Item -LiteralPath $releaseFingerprintPath -Destination (Join-Path $outputMetadataStage 'release-fingerprint.json') -Force
    Copy-Item -LiteralPath $toolingCurrentPath -Destination (Join-Path $outputMetadataStage 'tooling-fingerprint-current.json') -Force
    Copy-Item -LiteralPath $advisoryPath -Destination (Join-Path $outputMetadataStage 'dependency-advisory-gate.json') -Force
    Copy-Item -LiteralPath $osvReconciliationPath -Destination (Join-Path $outputMetadataStage 'independent-osv-reconciliation.json') -Force
    Copy-Item -LiteralPath $signingProviderPath -Destination (Join-Path $stage 'SIGNING-PROVIDER.json') -Force
    $hookData = $null
    $hookManifest = & $python (Join-Path $Workspace 'source\tools\hook_modes.py') (Join-Path $Workspace 'source') 2>$null
    if ($LASTEXITCODE -eq 0) { $hookData = $hookManifest | ConvertFrom-Json }

    $inventory = [Collections.Generic.List[object]]::new()
    $modeInventory = [Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse -Force) {
        $bundleRelative = ([IO.Path]::GetFullPath($file.FullName)).Substring($stage.Length).TrimStart('\','/').Replace('\','/')
        if ($bundleRelative -notmatch '^(source|installer-source|automation/release-e2e|release-tooling)/') { continue }
        $mode = 420
        if ($bundleRelative -match '^source/') {
            if ($hookData) {
                $hookRelative = $bundleRelative.Substring(7)
                if (@($hookData.executable_by_contract) -contains $hookRelative) { $mode = 493 }
            }
        }
        $canonicalMode = if ($mode -eq 493) { '0755' } else { '0644' }
        $inventory.Add([ordered]@{path=$bundleRelative;bytes=[int64]$file.Length;sha256=(Get-Hash $file.FullName);mode=$canonicalMode})
        $modeInventory.Add([ordered]@{path=$bundleRelative;posixMode=$mode;executable=($mode -eq 493)})
    }
    if ($inventory.Count -eq 0) { throw 'No shipping source was collected for the universal audit bundle.' }
    $inventory = @($inventory | Sort-Object path)
    $modeInventory = @($modeInventory | Sort-Object path)
    $hashLines = @($inventory | ForEach-Object { '{0}  {1}' -f $_.sha256,$_.path })
    Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Value $hashLines -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $stage 'AUDIT-TREE.txt') -Value (@('DevFleet universal AI audit source tree','') + @($inventory | ForEach-Object path)) -Encoding UTF8
    Write-Json (Join-Path $stage 'SOURCE-MODES.json') $modeInventory

    # A blocked pre-rebuild workspace can still produce a diagnostic bundle,
    # but only with an explicit, immutable historical-provenance contract.
    # This record is evidence metadata; it never changes the preserved old
    # artifact hashes or promotes the candidate.
    $historicalProvenance = $null
    if (-not $candidateIsCurrent -and $candidateCommit -eq '2739e0366d070285e44b4fc764ef9247d40b2f94') {
        $historicalProvenance = [ordered]@{
            schemaVersion = 1
            candidateCommit = '2739e0366d070285e44b4fc764ef9247d40b2f94'
            provenanceCommit = 'f334a6eff999287b170fdbd9b6a31c3ef24a6119'
            materialization = 'git-archive'
            coreAutocrlf = $false
            lineEndingComparison = 'CRLF_ONLY'
            historicalShippingInputIdentity = 'daa30ef9f521a47fedb4bacce91e3440c20e1a8f05543b4d5e823e5c3541e64e'
            historicalReleaseFingerprintId = '80c8b88c2f2ec828f5ab0f9713d63fa3f4cc4cbad7c382aa2f154f3196c3de84'
            identityLabels = [ordered]@{legacyShippingInputIdentity='daa30ef9f521a47fedb4bacce91e3440c20e1a8f05543b4d5e823e5c3541e64e';preservedCanonicalShippingInputIdentity='454edc...';rawGitShippingInputIdentity='cdab...';historicalReleaseFingerprintId='80c8b88c2f2ec828f5ab0f9713d63fa3f4cc4cbad7c382aa2f154f3196c3de84';rawGitReleaseFingerprintId='eba40...'}
            recomputedCandidateShippingInputIdentity = $candidateComputedIdentity
            recomputedHistoricalReleaseFingerprintId = '80c8b88c2f2ec828f5ab0f9713d63fa3f4cc4cbad7c382aa2f154f3196c3de84'
            authorizedCurrentShippingPaths = @($authorizedShippingPaths)
            crlfOnlyHistoricalPaths = @($historicalCrlfPaths)
            crlfOnlyHistoricalPathCount = [int]$historicalCrlfPaths.Count
             unknownHistoricalPaths = @($unknownHistoricalPaths)
             currentAuthorizedChangePaths = @($shippingChangedPaths | Where-Object { $authorizedShippingPaths -contains $_ })
             historicalMaterializationRoot = 'release-tooling/historical-candidate-2739'
             releaseEligible = $false
            promotionAllowed = $false
        }
    }
    $candidate = [ordered]@{
        schemaVersion = 2; devfleetVersion = $releaseVersion; installerVersion = $installerVersion; branch = $branch; repositoryHead = $head; gitCommit = $candidateCommit; gitClean = $gitClean
        releaseFingerprintId = $releaseId; toolingFingerprintId = $toolingId; shippingInputIdentity = $currentShippingInputIdentity; liveMaterializedShippingInputIdentity = $rawLiveShippingInputIdentity; lineEndingComparison = if($substantiveShippingChangedPaths.Count -gt 0){'MIXED_OR_SUBSTANTIVE'}elseif($crlfOnlyPaths.Count -gt 0){'CRLF_ONLY'}else{'BYTE_EXACT'}; candidateShippingInputIdentity = $candidateShippingInputIdentity; candidateCommit = $candidateCommit
        candidateTuple = [ordered]@{candidateCommit=$candidateCommit;shippingInputIdentity=$candidateShippingInputIdentity;releaseFingerprintId=$releaseId;toolingFingerprintId=$toolingId}
        # Authority stores the canonical candidate shipping identity for a
        # CRLF-only checkout; the raw materialized identity is retained in the
        # explicit live-materialization field for independent reconciliation.
        workingTreeTuple = [ordered]@{repositoryHead=$head;shippingInputIdentity=$candidateShippingInputIdentity;canonicalizedShippingInputIdentity=$currentShippingInputIdentity;releaseFingerprintWithHistoricalArtifacts=[string]$state.working_tree_release_fingerprint_with_historical_artifacts;toolingFingerprintId=$workingToolingId;crlfOnlyPaths=@($crlfOnlyPaths);substantivePaths=@($substantiveShippingChangedPaths)}
        candidateShippingInputs = @($identity.candidateShippingInputs); candidateShippingModeContract = $identity.candidateShippingModeContract; shippingModeContract = $identity.candidateShippingModeContract
        historicalProvenance = $historicalProvenance
        exeSha256 = $candidateArtifacts.exe.sha256; exeBytes = $candidateArtifacts.exe.bytes
        tarSha256 = $candidateArtifacts.tar.sha256; tarBytes = $candidateArtifacts.tar.bytes
        portableSha256 = $candidateArtifacts.portable.sha256; portableBytes = $candidateArtifacts.portable.bytes
        installerSourceSha256 = $candidateArtifacts.installerSource.sha256; installerSourceBytes = $candidateArtifacts.installerSource.bytes
        sourceIdentityMatchesCandidate = [bool]$state.source_identity_matches_candidate; artifactTupleMatchesCandidate = [bool]$state.artifact_tuple_matches_candidate; candidateBuildCurrent = [bool]$state.candidate_build_current
        candidateIsCurrent = $candidateIsCurrent; sourceChangedSinceCandidate = $sourceChanged; rebuildRequired = $rebuildRequired
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
        if([int]$baselinePointer.generation -in @(3,4)){
            $baselineReceipt=Read-Json $baselineReceiptPath
            foreach($sourceHash in @([string]$baselineReceipt.successorLedgerSha256,[string]$baselineReceipt.nativeInventorySha256)){
                if($sourceHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Rebound baseline source hash is invalid.'}
                $sourcePath=Join-Path $Workspace "evidence\baselines\sources\$sourceHash.json"
                if((Get-Hash $sourcePath) -cne $sourceHash){throw 'Rebound baseline source hash differs.'}
                $stagedSource=Join-Path $evidenceStage "baselines\sources\$sourceHash.json"
                if(-not(Add-CompactFile $sourcePath $stagedSource)){throw 'Rebound baseline source is missing.'}
                if((Get-Hash $stagedSource) -cne $sourceHash){throw 'Rebound staged baseline source hash differs.'}
            }
            if([int]$baselinePointer.generation -eq 4){
                $artifactBinding=$null
                $ledgerSource=Join-Path $Workspace ("evidence\baselines\sources\{0}.json" -f [string]$baselineReceipt.successorLedgerSha256)
                if(Test-Path -LiteralPath $ledgerSource -PathType Leaf){
                    $ledgerSourceJson=Read-Json $ledgerSource
                    $artifactBinding=$ledgerSourceJson.artifactReceipt
                }
                $artifactHash=[string]$artifactBinding.sha256
                $artifactSource=[string]$artifactBinding.path
                if($artifactHash -notmatch '^[0-9a-f]{64}$' -or [string]$baselineReceipt.artifactReceiptSha256 -cne $artifactHash){throw 'Repair-3 signed-output receipt hash is missing, malformed, or not bound by the baseline receipt.'}
                if(-not(Test-Path -LiteralPath $artifactSource -PathType Leaf)){
                    $artifactSource=Join-Path $Workspace ("evidence\baselines\sources\{0}.json" -f $artifactHash)
                }
                if(-not(Test-Path -LiteralPath $artifactSource -PathType Leaf) -or (Get-Hash $artifactSource) -cne $artifactHash){throw 'Repair-3 signed-output receipt is missing or hash-mismatched.'}
                $artifactDestination=Join-Path $evidenceStage ("baselines\sources\{0}.json" -f $artifactHash)
                if(-not(Add-CompactFile $artifactSource $artifactDestination) -or (Get-Hash $artifactDestination) -cne $artifactHash){throw 'Repair-3 signed-output receipt staging failed hash verification.'}
            }
        }
        $cursor=$baselinePointer
        if([int]$cursor.generation -lt 1 -or [int]$cursor.generation -gt 4){throw 'Unsupported accepted baseline generation.'}
        while([int]$cursor.generation -gt 1){
            $previousHash=[string]$cursor.previousPointerSha256
            if($previousHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Rebound baseline predecessor hash is invalid.'}
            $historyPath=Join-Path $Workspace "evidence\baselines\history\$previousHash.json"
            if((Get-Hash $historyPath) -cne $previousHash){throw 'Rebound baseline predecessor pointer hash differs.'}
            $previousPointer=Read-Json $historyPath
            $previousReceiptFile=[string]$previousPointer.receiptFile
            if([int]$previousPointer.generation -ne ([int]$cursor.generation-1) -or $previousReceiptFile -cnotmatch '^[0-9a-f]{32}\.json$'){throw 'Rebound baseline predecessor pointer is invalid.'}
            $previousReceiptPath=Join-Path $Workspace (Join-Path 'evidence\baselines\receipts' $previousReceiptFile)
            if((Get-Hash $previousReceiptPath) -cne [string]$previousPointer.receiptSha256){throw 'Rebound baseline predecessor receipt hash differs.'}
            if([int]$previousPointer.generation -eq 3){
                $previousReceipt=Read-Json $previousReceiptPath
                foreach($sourceHash in @([string]$previousReceipt.successorLedgerSha256,[string]$previousReceipt.nativeInventorySha256)){
                    if($sourceHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Predecessor baseline source hash is invalid.'}
                    $sourcePath=Join-Path $Workspace "evidence\baselines\sources\$sourceHash.json"
                    if((Get-Hash $sourcePath) -cne $sourceHash){throw 'Predecessor baseline source hash differs.'}
                    $stagedSource=Join-Path $evidenceStage "baselines\sources\$sourceHash.json"
                    if(-not(Add-CompactFile $sourcePath $stagedSource)){throw 'Predecessor baseline source is missing.'}
                }
            }
            if(-not(Add-CompactFile $historyPath (Join-Path $evidenceStage "baselines\history\$previousHash.json"))){throw 'Rebound baseline predecessor pointer is missing.'}
            if(-not(Add-CompactFile $previousReceiptPath (Join-Path $evidenceStage "baselines\receipts\$previousReceiptFile"))){throw 'Rebound baseline predecessor receipt is missing.'}
            $cursor=$previousPointer
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
    $manifest = [ordered]@{schemaVersion=2;bundle='DevFleet Universal AI Audit';status=$status;authorityId=$authorityId;generatedAt=(Get-Date).ToUniversalTime().ToString('o');devfleetVersion=$releaseVersion;installerVersion=$installerVersion;repositoryHead=$head;gitCommit=$head;candidateGitCommit=$candidateCommit;branch=$branch;shippingInputIdentity=$currentShippingInputIdentity;candidateShippingInputIdentity=$candidateShippingInputIdentity;workingTreeTuple=$candidate.workingTreeTuple;shippingModeContract=$identity.candidateShippingModeContract;candidateIsCurrent=$candidateIsCurrent;sourceChangedSinceCandidate=$sourceChange