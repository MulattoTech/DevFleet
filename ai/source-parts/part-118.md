# DevFleet source part 118

Full-source UTF-8 byte interval [5440500, 5487000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 03734788abb760bac371d6e6cf0021f8ab9dc919724c8cedb2e6e879a51e33e0

<!-- BEGIN SOURCE SLICE -->
ingFingerprint -ceq $toolingId -and ($finalAcceptanceValid -or $proofStartedUtc -ge $candidateBindingUtc)
}
# A failed/current smoke supersedes a stale historical proof pointer until a
# newly started proof writes its own current tuple. Preserve all old run files;
# only the current authority pointer is cleared.
if($interactiveCurrent -and [string]$interactiveCurrent.status -ne 'PASS' -and $interactiveSmokeRunId -and (-not $proofStartCurrent)){
    $CurrentProofRunId=$null
    $proofRun=$null;$proofStartRecord=$null;$proofFinalRecord=$null;$proofErrorRecord=$null;$terminalRecord=$null;$providerRecord=$null;$progressRecord=$null;$cleanupRecord=$null
    $proofStart=$null;$proofFinal=$null;$proofError=$null;$terminal=$null;$providerFailure=$null;$progress=$null
}
$certificationEligible = $proofStart -and -not ([bool](Get-FirstProperty $proofStart.provenance @('diagnosticOnly'))) -and (Get-FirstProperty $proofStart.provenance @('certificationEligible')) -ne $false
$proofNaturalPass = $proofStartCurrent -and $certificationEligible -and $proofFinal -and [string]$proofFinal.status -eq 'PASS'
$proofOutcome = if ($proofNaturalPass) { 'PASS' } else { 'NOT_OBSERVED' }
$proofStatus = if ($proofNaturalPass) { 'PASS' } else { 'BLOCKED' }
$terminalPhase = [string](Get-FirstProperty $terminal @('phase'))
$terminalProvider = [string](Get-FirstProperty $terminal @('provider'))
$terminalStable = [string](Get-FirstProperty $terminal @('lastStableStep'))
$terminalError = [string](Get-FirstProperty $terminal @('error','failure','terminalReason'))
if (-not $terminalError -and $proofError) { $terminalError = [string]$proofError.error }

$passingProofs = @()
$proofIdsForAuthority = if ($finalAcceptanceValid) { @($finalAcceptance.proofRunIds) } else { @($state.proof_run_ids | Where-Object { $_ } | Select-Object -Unique) }
foreach ($proofId in $proofIdsForAuthority) {
    $candidateRun = Join-Path $runRoot ([string]$proofId)
    $startRecord = Get-NewestJson $candidateRun 'proof-start.json'; $finalRecord = Get-NewestJson $candidateRun 'proof-final.json'
    if (-not $startRecord -or -not $finalRecord -or -not $startRecord.value.provenance) { continue }
    $p = $startRecord.value.provenance
    $eligible = -not ([bool](Get-FirstProperty $p @('diagnosticOnly'))) -and (Get-FirstProperty $p @('certificationEligible')) -ne $false
    $currentTuple = $eligible -and [string]$p.repositoryHead -ceq $head -and [string]$p.candidateCommit -ceq $candidateCommit -and [string]$p.shippingInputIdentity -ceq $shippingIdentity -and [string]$p.releaseFingerprint -ceq $releaseId -and [string]$p.toolingFingerprint -ceq $toolingId
    $proofStartedUtc=[datetime]::MinValue;$proofStartedRaw=Get-FirstProperty $startRecord.value @('generatedAtUtc','timestampUtc','startedAtUtc');try{if($proofStartedRaw){$proofStartedUtc=ConvertTo-AuthorityUtcInstant $proofStartedRaw}elseif($startRecord.lastWriteUtc){$proofStartedUtc=ConvertTo-AuthorityUtcInstant $startRecord.lastWriteUtc}}catch{$proofStartedUtc=[datetime]::MinValue}
    if ($currentTuple -and ($finalAcceptanceValid -or $proofStartedUtc -ge $candidateBindingUtc) -and [string]$finalRecord.value.status -eq 'PASS') { $passingProofs += [ordered]@{runId=[string]$proofId;proofStartPath=$startRecord.relativePath;proofFinalPath=$finalRecord.relativePath;status='PASS'} }
}
$currentCertificationStage = if($CurrentProofRunId -and $proofStartCurrent){'EXACT-CANDIDATE-PROOF'}elseif($interactiveSmokeRunId){'INTERACTIVE-LOGIN-SMOKE'}else{'EXACT-PROOF-NOT-RUN'}

if ($finalAcceptanceValid) { $FullReleaseRunId = [string]$finalAcceptance.fullReleaseRunId }
elseif (-not $FullReleaseRunId) { $FullReleaseRunId = [string]$state.full_release_run_id }
$fullRun = if ($FullReleaseRunId) { Join-Path $runRoot $FullReleaseRunId } else { $null }
$runStateRecord = if ($fullRun) { Get-NewestJson $fullRun 'run-state.json' } else { $null }
$runState = if ($runStateRecord) { $runStateRecord.value } else { $null }
$fullStatus = if ($runState) { [string]$runState.finalStatus } else { 'NOT_RUN_FOR_CURRENT_CANDIDATE' }
$fullCurrent = [bool]$FullReleaseRunId -and $runState -and
    [string]$runState.candidateHashes.repositoryHead -ceq $head -and
    [string]$runState.candidateHashes.candidateCommit -ceq $candidateCommit -and
    [string]$runState.candidateHashes.shippingInputIdentity -ceq $shippingIdentity -and
    [string]$runState.candidateHashes.releaseFingerprintId -ceq $releaseId -and
    [string]$runState.candidateHashes.toolingFingerprintId -ceq $toolingId
$fullPassed = $finalAcceptanceValid -and $fullCurrent -and $fullStatus -match '^PASS'
$fullSummary = [ordered]@{
    schemaVersion=2; generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o'); repositoryHead=$head; candidateGitCommit=$candidateCommit; shippingInputIdentity=$shippingIdentity; candidateShippingInputIdentity=$shippingIdentity; releaseFingerprintId=$releaseId; toolingFingerprintId=$toolingId
    latestRunId=if($FullReleaseRunId){$FullReleaseRunId}else{$null}; status=$fullStatus; fullReleasePassed=$fullPassed; historicalEvidenceOnly=(-not $fullCurrent); diagnosticOnly=(-not $fullPassed); lastCompletedPhase=if($runState){@($runState.completedPhases|Select-Object -Last 1)}else{@()}; currentPhase=if($runState){[string]$runState.currentPhase}else{''}
    candidateTuple=[ordered]@{repositoryHead=$head;candidateCommit=$candidateCommit;shippingInputIdentity=$shippingIdentity;releaseFingerprintId=$releaseId;toolingFingerprintId=$toolingId;exe=[string]$artifactByName.exe.sha256;tar=[string]$artifactByName.tar.sha256;portable=[string]$artifactByName.portable.sha256;installerSource=[string]$artifactByName.installerSource.sha256}
}

$releaseEligible = $finalAcceptanceValid
if ($releaseEligible) {
    $status='PASS';$blockerClassification='PASS';$blocker=$null;$nextAction='Preserve the final release state and perform independent bundle verification.'
} elseif (-not $candidateSafe) {
    $status='BLOCKED';$blockerClassification='BLOCKED — CANDIDATE INVALIDATED / PLATFORM AUTHORIZATION'
    $stateBlockers=@($state.blockers | ForEach-Object {[string]$_} | Where-Object {$_})
    $invalidation=[string](Get-FirstProperty $state @('candidate_invalidation_reason','candidateInvalidationReason'))
    $blocker=if($invalidation -and @($stateBlockers | Where-Object {$_.Contains($invalidation)}).Count -gt 0){$stateBlockers -join ' | '}else{(@($invalidation)+$stateBlockers | Where-Object {$_} | Select-Object -Unique) -join ' | '}
    if(-not $blocker){$blocker='The candidate/source/artifact authority tuple is not current.'}
    $nextAction='Under a workspace token with writable canonical Git metadata, commit the prepared batch, rebuild/sign once, bind the new candidate, then resume exact proofs under authorized Hyper-V access.'
} elseif (-not $finalAcceptanceValid -and $passingProofs.Count -ge 2 -and $fullStatus -match '^PASS') {
    $status='BLOCKED';$blockerClassification='BLOCKED — FINAL ACCEPTANCE INCOMPLETE';$blocker=$finalAcceptanceBlocker;$nextAction='Complete or repair the standard-token, immutable RELEASE-audit, and FINAL-ACCEPTANCE closure without relabeling prior evidence.'
} elseif ($proofNaturalPass) {
    $status='BLOCKED';$blockerClassification='BLOCKED — CERTIFICATION INCOMPLETE';$blocker="Current proof $CurrentProofRunId passed, but exact proofs/FullRelease acceptance is incomplete.";$nextAction='Continue the current candidate/tooling certification campaign.'
} elseif ($CurrentProofRunId) {
    $status='BLOCKED';$blockerClassification=if($terminalError -match '(?i)access denied|not authorized|insufficient privileges'){'BLOCKED — EXTERNAL HYPER-V AUTHORIZATION'}elseif($terminalProvider -match 'Checkpoint|Observer|Transition'){'BLOCKED — RELEASE HARNESS / RUNTIME OBSERVABILITY'}else{'BLOCKED — EXACT PROOF NOT OBSERVED'}
    $blocker=("RunId={0}; phase={1}; provider={2}; lastStableStep={3}; outcome={4}; error={5}" -f $CurrentProofRunId,$terminalPhase,$terminalProvider,$terminalStable,$proofOutcome,$terminalError).Trim()
    if ($proofStart -and -not $proofStartCurrent) { $blocker += '; proof-start tuple is historical relative to current tooling authority' }
    $nextAction=if($blockerClassification -match 'EXTERNAL HYPER-V'){'Resume under a token that is already authorized for Hyper-V; do not change Hyper-V security membership from the release harness.'}else{'Run the current instrumented exact-candidate lifecycle and diagnose the recorded terminal evidence.'}
} else {
    $status='BLOCKED';$blockerClassification='BLOCKED — FINAL ACCEPTANCE INCOMPLETE';$blocker=$finalAcceptanceBlocker;$nextAction='Complete the remaining current proof, FullRelease, standard-token, cleanup, RELEASE-audit, and FINAL-ACCEPTANCE gates.'
}

if ($TerminalBlocker) {
    $status = 'BLOCKED'
    $blockerClassification = if ($TerminalBlockerClassification) { $TerminalBlockerClassification } else { 'BLOCKED — FINALIZER' }
    $blocker = $TerminalBlocker
    $nextAction = 'Resolve the primary blocker, then resume the current candidate certification boundary.'
}

$proof = [ordered]@{
    schemaVersion=2; authorityGeneratedAtUtc=(Get-Date).ToUniversalTime().ToString('o'); repositoryHead=$head; candidateCommit=$candidateCommit; candidateGitCommit=$candidateCommit; shippingInputIdentity=$shippingIdentity; candidateShippingInputIdentity=$shippingIdentity; releaseFingerprintId=$releaseId; toolingFingerprintId=$toolingId
    candidateIsCurrent=$candidateFlags.candidateIsCurrent; sourceChangedSinceCandidate=$candidateFlags.sourceChangedSinceCandidate; rebuildRequired=$candidateFlags.rebuildRequired
    currentCertificationStage=$currentCertificationStage; currentSmokeRunId=$interactiveSmokeRunId; currentProofRunId=if($CurrentProofRunId){$CurrentProofRunId}else{$null}; candidateBindingUtc=if($candidateBindingUtc -gt [datetime]::MinValue){$candidateBindingUtc.ToString('o')}else{$null}; passingProofs=@($passingProofs)
    runId=if($CurrentProofRunId){$CurrentProofRunId}else{$null}; status=$proofStatus; outcome=$proofOutcome; diagnosticOnly=(-not $certificationEligible); diagnosticOutcome=if($proofFinal){[string]$proofFinal.status}else{'NOT_OBSERVED'}; certificationEligible=$certificationEligible; proofStartCurrent=$proofStartCurrent
    proofStart=if($proofStartCurrent){$proofStart}else{$null}; proofStartPath=if($proofStartCurrent -and $proofStartRecord){$proofStartRecord.relativePath}else{$null}; proofStartHistoricalPath=if(-not $proofStartCurrent -and $proofStartRecord){"release-tooling/historical/$CurrentProofRunId/proof-start.json"}else{$null}; historicalProofStart=if(-not $proofStartCurrent -and $proofStart){[ordered]@{historical=$true;runId=$CurrentProofRunId;repositoryHead=[string]$proofStart.provenance.repositoryHead;candidateCommit=[string]$proofStart.provenance.candidateCommit;toolingFingerprintId=[string]$proofStart.provenance.toolingFingerprint;sourcePath=$proofStartRecord.relativePath}}else{$null}
    proofFinal=if($proofStartCurrent -and $proofFinalRecord){$proofFinal}else{$null}; proofFinalPath=if($proofStartCurrent -and $proofFinalRecord){$proofFinalRecord.relativePath}else{$null}; proofError=$proofError; proofErrorPath=if($proofErrorRecord){$proofErrorRecord.relativePath}else{$null}
    terminal=$terminal; terminalPath=if($terminalRecord){$terminalRecord.relativePath}else{$null}; providerFailure=$providerFailure; providerFailurePath=if($providerRecord){$providerRecord.relativePath}else{$null}; progress=$progress; progressPath=if($progressRecord){$progressRecord.relativePath}else{$null}; cleanup=if($cleanupRecord){$cleanupRecord.value}else{$null}
    phase=$terminalPhase; provider=$terminalProvider; lastStableStep=$terminalStable; terminalError=$terminalError; blockerClassification=$blockerClassification; blocker=$blocker
    currentTuplePassingProofCount=$passingProofs.Count; currentTuplePassingProofs=$passingProofs; fullReleaseRunId=if($FullReleaseRunId){$FullReleaseRunId}else{$null}
}

$authorityCore = [ordered]@{
    schemaVersion=3; generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o'); status=$status; blockerClassification=$blockerClassification; blocker=$blocker; nextAction=$nextAction
    repositoryHead=$head; branch=$branch; candidateCommit=$candidateCommit; shippingInputIdentity=$shippingIdentity; candidateShippingInputIdentity=$shippingIdentity; releaseFingerprintId=$releaseId; toolingFingerprintId=$toolingId
    candidate=$candidate; workingTree=$workingTree; proof=$proof; proofs=[ordered]@{passing=$passingProofs.Count;required=2;status=if($passingProofs.Count -ge 2){'2 / 2 PASS'}else{"$($passingProofs.Count) / 2 PASS"};runs=$passingProofs}; fullRelease=$fullSummary
    candidateIsCurrent=$candidateFlags.candidateIsCurrent; sourceChangedSinceCandidate=$candidateFlags.sourceChangedSinceCandidate; rebuildRequired=$candidateFlags.rebuildRequired; validationEvidenceCurrent=$candidateFlags.validationEvidenceCurrent; fullReleasePassed=$fullPassed; internalPromotionAllowed=$candidateFlags.internalPromotionAllowed; publicPromotionAllowed=$false; publicPublisherTrust=$false; currentCertificationStage=$currentCertificationStage; currentSmokeRunId=$interactiveSmokeRunId; currentProofRunId=if($CurrentProofRunId){$CurrentProofRunId}else{$null}; passingProofs=@($passingProofs)
    f005=[ordered]@{attempted=$false;formatterOnlyAuditCleanupPerformed=$false;structuralRefactoringPerformed=$false}
}
$authorityId = Get-StringHash ($authorityCore | ConvertTo-Json -Compress -Depth 40)
$authority = [ordered]@{authorityId=$authorityId} + $authorityCore
$candidate.authorityId=$authorityId;$candidate.status=$status;$candidate.blockerClassification=$blockerClassification
$proof.authorityId=$authorityId;$fullSummary.authorityId=$authorityId

$currentStatus = [ordered]@{schemaVersion=3;authorityId=$authorityId;generatedAtUtc=$authority.generatedAtUtc;status=$status;blockerClassification=$blockerClassification;blocker=$blocker;nextAction=$nextAction;repositoryHead=$head;candidateCommit=$candidateCommit;shippingInputIdentity=$shippingIdentity;candidateShippingInputIdentity=$shippingIdentity;releaseFingerprintId=$releaseId;toolingFingerprintId=$toolingId;workingTree=$workingTree;candidateIsCurrent=$candidateFlags.candidateIsCurrent;sourceChangedSinceCandidate=$candidateFlags.sourceChangedSinceCandidate;rebuildRequired=$candidateFlags.rebuildRequired;validationEvidenceCurrent=$candidateFlags.validationEvidenceCurrent;fullReleasePassed=$fullPassed;internalPromotionAllowed=$candidateFlags.internalPromotionAllowed;publicPromotionAllowed=$false;publicPublisherTrust=$false;currentProofRunId=if($CurrentProofRunId){$CurrentProofRunId}else{$null};currentProofOutcome=$proofOutcome;proofsPassed=$passingProofs.Count;proofsRequired=2;fullReleaseRunId=if($FullReleaseRunId){$FullReleaseRunId}else{$null};f005Attempted=$false;productionUnchanged=$true;mulattoTechSurfaceTouched=$false;disposableLabOnly=$true}
$currentGates = [ordered]@{schemaVersion=3;authorityId=$authorityId;generatedAtUtc=$authority.generatedAtUtc;status=$status;repositoryHead=$head;candidateCommit=$candidateCommit;shippingInputIdentity=$shippingIdentity;releaseFingerprintId=$releaseId;toolingFingerprintId=$toolingId;candidate=$candidate;proofs=$authority.proofs;fullRelease=$fullSummary;gates=$state.gates;blockers=if($blocker){@($blocker)}else{@()};currentPhase=[string]$state.current_phase;lastCompletedPhase=[string]$state.last_completed_phase}
$l1 = Read-Json (Join-Path $evidence 'l1-terminal-state.json');$l2 = Read-Json (Join-Path $evidence 'l2-terminal-state.json')
$handoff = [ordered]@{schemaVersion=3;authorityId=$authorityId;historical=$false;generatedAtUtc=$authority.generatedAtUtc;status=$status;blockerClassification=$blockerClassification;blocker=$blocker;nextAction=$nextAction;repositoryHead=$head;candidateCommit=$candidateCommit;shippingInputIdentity=$shippingIdentity;candidateShippingInputIdentity=$shippingIdentity;releaseFingerprintId=$releaseId;toolingFingerprintId=$toolingId;currentProofRunId=if($CurrentProofRunId){$CurrentProofRunId}else{$null};currentProofOutcome=$proofOutcome;phase=$terminalPhase;provider=$terminalProvider;lastStableStep=$terminalStable;terminalError=$terminalError;proofsPassed=$passingProofs.Count;proofsRequired=2;fullReleaseRunId=if($FullReleaseRunId){$FullReleaseRunId}else{$null};fullReleaseStatus=$fullStatus;l1State=if($l1){[string]$l1.state}else{'UNVERIFIED'};l2State=if($l2){if([string]$l2.status -ceq 'ABSENT' -and $l2.present -eq $false){'ABSENT'}elseif($l2.present -eq $true){'PRESENT'}else{'UNVERIFIED'}}else{'UNVERIFIED'};f005Attempted=$false;formatterOnlyAuditCleanup=$false;f005StructuralRefactor=$false;publicPromotionAllowed=$false;publicPublisherTrust=$false}
$next = [ordered]@{schemaVersion=3;authorityId=$authorityId;historical=$false;generatedFrom='evidence/CURRENT-RELEASE-AUTHORITY.json';status=$status;blockerClassification=$blockerClassification;blocker=$blocker;nextAction=$nextAction;repository=[ordered]@{branch=$branch;head=$head;candidateCommit=$candidateCommit};candidate=$candidate;workingTree=$workingTree;runtime=[ordered]@{currentProofRunId=if($CurrentProofRunId){$CurrentProofRunId}else{$null};currentProofOutcome=$proofOutcome;proofs=$authority.proofs;fullRelease=$fullSummary;internalPromotionAllowed=$candidateFlags.internalPromotionAllowed;publicPromotionAllowed=$false;publicPublisherTrust=$false};safety=[ordered]@{protectedProductionMutated=$false;hostRebooted=$false;amdRadeonTouched=$false;biosUefiTouched=$false;mulattoTechSurfaceTouched=$false;githubPushed=$false;privateSigningKeyExported=$false};f005=$authority.f005}

Write-AtomicJson (Join-Path $evidence 'CURRENT-RELEASE-AUTHORITY.json') $authority
Write-AtomicJson (Join-Path $Workspace 'CURRENT-CANDIDATE.json') $candidate
Write-AtomicJson (Join-Path $evidence 'CURRENT-STATUS.json') $currentStatus
Write-AtomicJson (Join-Path $evidence 'CURRENT-GATES.json') $currentGates
Write-AtomicJson (Join-Path $evidence 'CURRENT-PROOF.json') $proof
Write-AtomicJson (Join-Path $evidence 'FULLRELEASE-SUMMARY.json') $fullSummary
Write-AtomicJson (Join-Path $evidence 'CURRENT-HANDOFF.json') $handoff
Write-AtomicJson (Join-Path $audit 'CURRENT-HANDOFF.json') $handoff
Write-AtomicJson (Join-Path $audit 'NEXT-CODEX-HANDOFF.json') $next
$nextMd = (@('# DevFleet v1.2.13 current release handoff','',"Authority: $authorityId","Status: $status","Repository/tooling HEAD: $head","Candidate commit: $candidateCommit","Shipping input: $shippingIdentity","Release fingerprint: $releaseId","Tooling fingerprint: $toolingId","Exact proofs: $($passingProofs.Count) / 2 PASS","FullRelease: $fullStatus",'',"Blocker: $(if($blocker){$blocker}else{'None'})","Next action: $nextAction",'','F-005 attempted: NO','Formatter-only F-005 cleanup: NO','F-005 structural refactoring: NO') -join [Environment]::NewLine) + [Environment]::NewLine
Write-AtomicText (Join-Path $audit 'NEXT-CODEX-HANDOFF.md') $nextMd

$mutableState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
$mutableState.repository_head=$head;$mutableState.git_commit=$head;$mutableState.current_authority_id=$authorityId;$mutableState.current_proof_run_id=if($CurrentProofRunId){$CurrentProofRunId}else{$null};$mutableState.current_proof_outcome=$proofOutcome;$mutableState.current_proof_updated_utc=$authority.generatedAtUtc;$mutableState.proofs_passed=[int]$passingProofs.Count;$mutableState.proofs_required=2
$mutableState.blockers=if($blocker){@($blocker)}else{@()};$mutableState.status=$status;$mutableState.release_status=$status;$mutableState.validation_evidence_current=$finalAcceptanceValid;$mutableState.full_release_passed=$finalAcceptanceValid;$mutableState.internal_promotion_allowed=$finalAcceptanceValid;$mutableState.public_promotion_allowed=$false;$mutableState.public_publisher_trust=$false
if($finalAcceptanceValid){$mutableState.candidate_is_current=$true;$mutableState.source_identity_matches_candidate=$true;$mutableState.source_changed_since_candidate=$false;$mutableState.rebuild_required=$false;$mutableState.candidate_build_current=$true;$mutableState.artifact_tuple_matches_candidate=$true;$mutableState.full_release_current=$true;$mutableState.full_release_run_id=[string]$finalAcceptance.fullReleaseRunId;$mutableState.proof_run_ids=@($finalAcceptance.proofRunIds)}
Write-AtomicJson $statePath $mutableState

[pscustomobject]@{schemaVersion=3;authorityId=$authorityId;status=$status;repositoryHead=$head;candidateCommit=$candidateCommit;releaseFingerprintId=$releaseId;toolingFingerprintId=$toolingId;currentProofRunId=$CurrentProofRunId;currentProofOutcome=$proofOutcome;passingProofs=$passingProofs.Count;fullReleaseRunId=$FullReleaseRunId;fullReleaseStatus=$fullStatus;blocker=$blocker} | ConvertTo-Json -Depth 12

```


## FILE: tools/astra-causal-evidence.json

SHA256: 1fc036786413175dd43c0fc5b79be90b884ea4f8c800179a78d1300ce571ede9 | Bytes: 137578 | Git mode: 100644

```
{
  "schemaVersion": 1,
  "purpose": "Frozen historical Astra causal originals and explicitly selected local/controller context; no release or proof credit.",
  "missingHistoricalEvidence": [
    "M2 has no original start/end operation journals for launch, info-running, ssh-ready, cloud-init or info-final: ten files remain missing. No replacements manufactured."
  ],
  "limitations": [
    "M5 live-network-and-transport.json is the original truncated invalid JSON; retry1 is separate, not a replacement.",
    "M6 initial fractional-time analysis is superseded by the selected final analysis; original raw bytes are unchanged.",
    "M4 two and M5 one UNAVAILABLE snapshots remain unavailable; inclusion is not successful observation.",
    "Local transport fixtures do not exercise actual Multipass SFTP or Linux ACL enforcement.",
    "Corrective Proof1 ended after a documented exact-worker operator stop following confirmed product exit5; the native remoting terminal reflects that stop and is not the original product cause.",
    "Corrective Proof1 confirms real launch and stdin transport through secrets input, but full installation and release eligibility remain unproven.",
    "Corrective replay2 lacks a pre-cleanup guest setup log. Its retained signed-payload Python syntax error is a demonstrated required correction in the observed failed stage, not a captured live stderr traceback.",
    "Corrective replay3 bootstrap/receipt/ownership completed but authenticated live health was not observed. Exact worker stop followed a proven PS5.1 health-client runtime incompatibility; native transport failure was the stop consequence. Local PS7 correction tests grant no proof credit.",
    "Laptop connected-pairing correction is locally qualified only. Missing Tailscale account configuration remains a prerequisite; no browser, auth provider, Vault service or proof PASS is inferred from fixtures.",
    "Replay4: exact protocol matched; hidden ProgramData Get-Item without Force prevented authentication before hashing. Generic protocol mismatch obscured the early failure. Operator stop preserved evidence and native cleanup. Zero proof; corrective4/4 exhausted.",
    "Current local maintenance transport uses supported PS7 with exact VM/protocol/candidate/deadline checks. No installed runtime credit or execution-policy override. Historical coordinator projections are preserved before current Astra closeout."
  ],
  "records": [
    {
      "source": "audit/automation-harness/runs/e2e-astra-prereq-20260907t025814z/astra-host-observations.jsonl",
      "destination": "e2e-astra-prereq-20260907t025814z/astra-host-observations.jsonl",
      "sha256": "2a8b5304d27685bdb4e48e6e07a04efda27dae6341e6bc177b459eb4e5cb6d6c",
      "bytes": 612,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/resume-generation-1-wpf-evidence.json",
      "destination": "e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/resume-generation-1-wpf-evidence.json",
      "sha256": "7b0d4e2196565c21443be289633a16e5f2add10e62060b67172bc44801ee265a",
      "bytes": 7413,
      "kind": "explicit-observer-causal-context"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/product-lifecycle-progress.jsonl",
      "destination": "e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/product-lifecycle-progress.jsonl",
      "sha256": "2d8f98127be9e4be6e4d31ad975c3cae5062b49bcc762adbb7c07919d87ba15f",
      "bytes": 1138765,
      "kind": "explicit-observer-causal-context"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/product-lifecycle-observer-generation-1.json",
      "destination": "e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/product-lifecycle-observer-generation-1.json",
      "sha256": "4788f390f1426b37d466a1ac758909ff60887070851e38b0c75df54b8c4727a7",
      "bytes": 1252694,
      "kind": "explicit-observer-causal-context"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/product-lifecycle-observer-generation-0.json",
      "destination": "e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/product-lifecycle-observer-generation-0.json",
      "sha256": "79ae25420c73745aa3a0c0ff8d473f87bff2ea7f45edb1c6a9f05006591d3842",
      "bytes": 176742,
      "kind": "explicit-observer-causal-context"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/initial-FreshInstall-wpf-evidence.json",
      "destination": "e2e-astra-m5-20260907t052903z/lifecycle-CAMPAIGN-E-M4-b060195b300a468cbc794d39bdb011b0/initial-FreshInstall-wpf-evidence.json",
      "sha256": "6c4f2bfd53aa168297befd23fe2ec39cfd3ccee72a0371807d055ec816d6398d",
      "bytes": 8597,
      "kind": "explicit-observer-causal-context"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0025-before-cleanup.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0025-before-cleanup.json",
      "sha256": "d9a13e75ca714ce9290a1e5da1ab9f21a69bf44bf3d5ee1b8c4b461e885a8379",
      "bytes": 261,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0024-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0024-during-product.json",
      "sha256": "f31ec152a4b82f8d05995bdd7822d77cb9df71c1d253e0ba45161073d2793784",
      "bytes": 5537,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0023-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0023-during-product.json",
      "sha256": "de0b08f5afb0dc970029e0a8cda5ea4aa80b3f8843cffd18edd5e0ce5c80083b",
      "bytes": 5536,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0022-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0022-during-product.json",
      "sha256": "e1556eb1b19224331555e0a730b3ca7a57aa39cdd4e85bafc3a339b3f38354e7",
      "bytes": 5535,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0021-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0021-during-product.json",
      "sha256": "7bbd371cab8d94596e2c21fe83aaad821b0b9bc8c6b92db2b6767e42d113b9bb",
      "bytes": 5694,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0020-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0020-during-product.json",
      "sha256": "7790de1d9141761c34cec0b538d317d3eb49c0ea4336d265f3a9b4c4452c6bf4",
      "bytes": 5537,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0019-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0019-during-product.json",
      "sha256": "34e31fcf28fd0d6a52ffce92472cce4bb838feae5aab9136c346e8d0803b471a",
      "bytes": 5530,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0018-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0018-during-product.json",
      "sha256": "190f2b8bdcf856380c1512533355615f285a9c96d88099ddba30c26f44414fe2",
      "bytes": 5895,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0017-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0017-during-product.json",
      "sha256": "af16378f846ee0ce3aeb3ea52c907d714d9a094a78ae8b7074a98088d1856ee3",
      "bytes": 5537,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0016-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0016-during-product.json",
      "sha256": "bff00f539b9bd2d2b2845f313b3976b9a7157c3d20032e505e4478e53547a754",
      "bytes": 5694,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0015-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0015-during-product.json",
      "sha256": "b0abb18ded605468c50f1b27950cac937bdb943a8af258065fec248e510dfe68",
      "bytes": 5695,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0014-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0014-during-product.json",
      "sha256": "e085fc623faffe96f0bf775d23cd3ca79e7ce881c890c452ef8ef9ab2622f608",
      "bytes": 5536,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0013-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0013-during-product.json",
      "sha256": "961d83fbe197c2d1be5c86aa2db6c22cf3f84a7594b3e339300afb4f53357442",
      "bytes": 5536,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0012-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0012-during-product.json",
      "sha256": "84a266037bd752d24d23e197522d3388c3bac77494a039339d0c7dc09094e6c6",
      "bytes": 5535,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0011-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0011-during-product.json",
      "sha256": "2966be7cccff3aa3a55cfdbb4b9331bb257056f5feb16c40f79783d213ea1ac0",
      "bytes": 23417,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0010-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0010-during-product.json",
      "sha256": "2652c28352b0909467f2f6ef96a36b0e82490c38f814d1b8a8292cc4dc7fe524",
      "bytes": 8488,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0009-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0009-during-product.json",
      "sha256": "a0f9762f3b82f89a939c9c6f8834b95e135c13ea53d095455b12ab100a681359",
      "bytes": 14226,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0008-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0008-during-product.json",
      "sha256": "aea3665f58f50ab433682ad3955a4a66ee9d38b1c70e54ed33d59092dc28d06c",
      "bytes": 3115,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0007-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0007-during-product.json",
      "sha256": "2ffde9ec3b986f6a391668b992661f9aef8ab2d22b74b70b7103330e79ef0948",
      "bytes": 3114,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0006-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0006-during-product.json",
      "sha256": "9df6cc38ca780c77ee4bf28336e02442439a6bb93789e408545d014363ed485f",
      "bytes": 15986,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0005-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0005-during-product.json",
      "sha256": "f2ee22b3595dc52fd5057d5ab9884206627d3b00cec4c92e19fa4f737c654088",
      "bytes": 3423,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0004-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0004-during-product.json",
      "sha256": "cd6fd5f291467d655e633efd8cbff82e57a3cca60b525b9274056fe0b0e5ef9c",
      "bytes": 3115,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/campaign-e-m4.json",
      "destination": "e2e-astra-m6-20260907t061636z/campaign-e-m4.json",
      "sha256": "c720eb39b413428d7b26c0f61686f83974de935300e47f86f9b1f6888ba4af04",
      "bytes": 19212,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0003-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0003-during-product.json",
      "sha256": "f72dfd26d63168d6050c1545ed4a752bfa7478db00446ab7ed0b5b2f461befc6",
      "bytes": 3115,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/initial-FreshInstall-wpf-evidence.json",
      "destination": "e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/initial-FreshInstall-wpf-evidence.json",
      "sha256": "405cb4c3d84c5aa2e552f366bf74ad3a4b789809cc6501d9db3c9408bf6e4bc3",
      "bytes": 8604,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/product-lifecycle-observer-generation-1.json",
      "destination": "e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/product-lifecycle-observer-generation-1.json",
      "sha256": "3759b3c1573b3fa1d266ddee22ae9e348a62bf24e08e10167cf06df58419b9ca",
      "bytes": 607655,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/bootstrap-input-regression.log",
      "destination": "astra-m6-local-20260907/bootstrap-input-regression.log",
      "sha256": "d7c253e407b43f0d5b4e29ecf254dd053a349a9b95e6ac6496e2a2ffb98c70f5",
      "bytes": 284,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/external-stdin-regression.log",
      "destination": "astra-m6-local-20260907/external-stdin-regression.log",
      "sha256": "49cc0629612736a3133a35a3c669b436226da8c75de7cd43f86df16cdd1a9bd1",
      "bytes": 516,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/transport-review-qualified.log",
      "destination": "astra-m6-local-20260907/transport-review-qualified.log",
      "sha256": "89cbc10043e255afec669317e46beb62c8e4338353e78ca41c58bbe8539bb4d8",
      "bytes": 4211,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/transport-unicode-before-fix.log",
      "destination": "astra-m6-local-20260907/transport-unicode-before-fix.log",
      "sha256": "95b78b36f3083c2d11224961d2ea6d9ec7574d5b64b7157789caa1a1c63bec6b",
      "bytes": 3467,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/native-console-fixture.ps1",
      "destination": "astra-m6-local-20260907/native-console-fixture.ps1",
      "sha256": "4dae6a58c0f0b12b7b08df2e03256538959545a67947f0f86d8918fa085fec74",
      "bytes": 891,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/reproduce-console-input.ps1",
      "destination": "astra-m6-local-20260907/reproduce-console-input.ps1",
      "sha256": "1639eb866847d44314870a605058556e7768b16a803a5466e047867c1624c085",
      "bytes": 2971,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/native-console-before-correction-qualified.json",
      "destination": "astra-m6-local-20260907/native-console-before-correction-qualified.json",
      "sha256": "cee91c1513db8201f3d95582ae26007ce7d05e038f542694e7379b1b28c4ad22",
      "bytes": 1014,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/native-console-before-correction.json",
      "destination": "astra-m6-local-20260907/native-console-before-correction.json",
      "sha256": "732cacdbe63cae3b6d5fc24e33d1e0d67d6d6f349e3e069b7c53d2eb6a915f4f",
      "bytes": 777,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/result-final.json",
      "destination": "astra-m6-local-20260907/result-final.json",
      "sha256": "6beac570d59e9943e8a0896dfdd3458890b73720bd330441b9fa513f1624e129",
      "bytes": 3100,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/shipping-qualification.json",
      "destination": "astra-m6-local-20260907/shipping-qualification.json",
      "sha256": "55f911c1652549d9f54e82c582f88147047245a409110dbe729754fe1e59d68b",
      "bytes": 3481,
      "kind": "local-causal-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/astra-result-analysis-final.json",
      "destination": "e2e-astra-m6-20260907t061636z/astra-result-analysis-final.json",
      "sha256": "171559c36ee059088eff28c546dc8e61569ab14b3347490ed7eb4470a021ac52",
      "bytes": 8307,
      "kind": "analysis-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0014-before-cleanup.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0014-before-cleanup.json",
      "sha256": "db355c12c23e1eadbc30db0f246316355b6fc1fe6fc6fb8ff0865edb1e09924d",
      "bytes": 4959,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0013-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0013-during-product.json",
      "sha256": "fb5fbdeac2d5a29d90043736f78de8ab5af4a3e2b01aa321ac5906619e28cc1d",
      "bytes": 4827,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0012-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0012-during-product.json",
      "sha256": "da38ec1b37e32bb8f1eaab75edf48fd8a79d51929c4eec23a94066de6d478720",
      "bytes": 5982,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0011-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0011-during-product.json",
      "sha256": "03b30a6f3a49da4740801b5ead531746fac8f4216c45847176c65223a7fe785f",
      "bytes": 23455,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0010-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0010-during-product.json",
      "sha256": "6ebeebf60835947a1f172841359c7cf6544ec8999e073ecb130b4a444945c653",
      "bytes": 11915,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0009-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0009-during-product.json",
      "sha256": "f317dfb50a29e73b7bc6bb34bd051663a351a2d339d1f2d825a1a249dcb7f2a5",
      "bytes": 14243,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0008-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0008-during-product.json",
      "sha256": "8922b73e846fca9dcdacbffc6649b1fad92a066fd59e03a5df14395f0e9f46ab",
      "bytes": 3115,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0007-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0007-during-product.json",
      "sha256": "4ada0afb72519a9ec679558980a125457768c6f3c4e2d45cb6ccf21a64e8bb12",
      "bytes": 3116,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0006-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0006-during-product.json",
      "sha256": "1b78a6c1074a1b7714d57a3df6b7d74564bda08e5eed133fd643bb7a97348f81",
      "bytes": 15985,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0005-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0005-during-product.json",
      "sha256": "cc0533d973656a5b68582d0129d2fdb2a87769241b66cb521d17e476ab230d32",
      "bytes": 3423,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0004-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0004-during-product.json",
      "sha256": "762f665f242cb43489fd58dab9f85782fd304a2f46fdcb27c946275c0f4215dc",
      "bytes": 3115,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0003-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0003-during-product.json",
      "sha256": "36053277db9fe1adae28fe41b78ed6696dfa67d47104df4519b316aa15ae0f8d",
      "bytes": 3116,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0002-during-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0002-during-product.json",
      "sha256": "4dcc2aa25ab6938e0b981c56f4dcf7494957d4a98a35eca4565302511322248b",
      "bytes": 5353,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/snapshot-0001-before-product.json",
      "destination": "e2e-astra-m6-20260907t061636z/snapshot-0001-before-product.json",
      "sha256": "bc3071abfa60b598b7508605be41add3bc0e1d71895c401b5967b74714079033",
      "bytes": 15931,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/resume-generation-1-wpf-evidence.json",
      "destination": "e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/resume-generation-1-wpf-evidence.json",
      "sha256": "f8cf90a68ad03a61a980e1fa44d7d78cab82ec14a3c17dcb18943d9cfd4a648a",
      "bytes": 7410,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/product-lifecycle-progress.jsonl",
      "destination": "e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/product-lifecycle-progress.jsonl",
      "sha256": "5c196200645d9f3317208fec364316fb7d6fb0a58261ef0514b07da7f2b0b2fe",
      "bytes": 601164,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/product-lifecycle-observer-generation-0.json",
      "destination": "e2e-astra-m6-20260907t061636z/lifecycle-CAMPAIGN-E-M4-d345049b688645129dc4dd4fe7c0550f/product-lifecycle-observer-generation-0.json",
      "sha256": "df5d372a3ee5b9bfbf38c5aa93fcef2f0c8c64a667dce9b53b233083f7859847",
      "bytes": 176918,
      "kind": "original"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0002-during-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0002-during-product.json",
      "sha256": "6cf854c67bdde042df387d4f3ff6f5880c3c235bb18607dd82259c1f53476e52",
      "bytes": 2786,
      "kind": "controller-bound-observation"
    },
    {
      "source": "audit/automation-harness/runs/e2e-astra-m5-20260907t052903z/snapshot-0001-before-product.json",
      "destination": "e2e-astra-m5-20260907t052903z/snapshot-0001-before-product.json",
      "sha256": "19e