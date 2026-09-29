# DevFleet source part 118

Full-source UTF-8 byte interval [5440500, 5487000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: fe58729356daebed4d10fe8c50de9e02042dce77b369713dff517d278bd76c0e

<!-- BEGIN SOURCE SLICE -->
Valid';signerThumbprint=[string]$signing.signerThumbprint;signerSubject=[string]$signing.signerSubject;codeSigningEkuVerified=$true;rsaBits=3072;exactCertificateMatch=$true;privateKeyExported=$false}
        }
        proofRunIds=@($validated.proofRunIds); fullReleaseRunId=[string]$validated.fullReleaseRunId
        standardTokenRunId=[string]$validated.standardTokenRunId; releaseAuditRunId=[string]$releaseAudit.runId
        bindings=[ordered]@{
            standardTokenPointerSha256=[string]$validated.standardToken.pointerSha256;standardTokenCanonicalSha256=[string]$validated.standardToken.canonicalSha256;standardTokenRawReportSha256=[string]$validated.standardToken.rawReportSha256
            fullReleaseRunStateSha256=[string]$validated.fullRelease.runStateSha256;fullReleasePhaseRecordsSha256=[string]$validated.fullRelease.phaseRecordsSha256;realUseBindingSha256=[string]$validated.fullRelease.realUseBindingSha256;realUsePrepareSha256=[string]$validated.fullRelease.realUsePrepareSha256;realUseReportSha256=[string]$validated.fullRelease.realUseReportSha256;realUseSummarySha256=[string]$validated.fullRelease.realUseSummarySha256
            cleanupSha256=[string]$validated.fullRelease.cleanupSha256;postCleanupSha256=[string]$validated.fullRelease.postCleanupSha256;terminalL1Sha256=[string]$validated.fullRelease.l1Sha256;terminalL2Sha256=[string]$validated.fullRelease.l2Sha256
            releaseAuditPointerSha256=[string]$releaseAudit.pointerSha256;releaseAuditArchiveSha256=[string]$releaseAudit.archiveSha256;releaseAuditReportSha256=[string]$releaseAudit.reportSha256;releaseAuditManifestSha256=[string]$releaseAudit.manifestSha256;releaseAuditValidationSha256=[string]$releaseAudit.releaseValidationSha256
        }
        gates=[ordered]@{candidate='PASS';proofs='2/2 PASS';fullRelease='PASS';realUseAcceptance='U01-U05 PASS';maintenance='5/5 PASS';standardToken='PASS';reconcile='PASS';cleanup='PASS';l1='OFF';l2='ABSENT';releaseAudit='PASS'}
        safety=[ordered]@{f005Attempted=$false;formatterOnlyAuditCleanupPerformed=$false;f005StructuralRefactoringPerformed=$false;protectedProductionMutated=$false;hostRebooted=$false;amdRadeonTouched=$false;biosUefiTouched=$false;mulattoTechSurfaceTouched=$false;githubPushed=$false;privateSigningKeyExported=$false;ramPressureOverrideUsed=$false;productionUnchanged=$true;disposableLabOnly=$true}
    }
    $liveVmsFinal = @(Get-VM -ErrorAction Stop)
    $l1Final = @($liveVmsFinal | Where-Object { [string]$_.Id -ceq '84b7d8b8-ee6c-4085-aa29-4b0adc316de2' })
    if ($l1Final.Count -ne 1 -or [string]$l1Final[0].Name -cne 'DevFleet-E2E-Win11-01' -or [string]$l1Final[0].State -cne 'Off' -or @($liveVmsFinal | Where-Object { [string]$_.Name -ceq 'DevFleet-E2E-Linux-01' }).Count -ne 0) { throw 'LIVE_TERMINAL_STATE_CHANGED_BEFORE_FINAL_ACCEPTANCE' }
    # Validate the exact candidate record before it becomes current authority.
    # The validator accepts this override only for workspace final-acceptance
    # checks; archive validation remains fixed to FINAL-ACCEPTANCE.json.
    Write-AtomicJson $pendingFinalPath $final
    $finalCheckOutput = @(& $python $validator --workspace-root $Workspace --check final-acceptance --final-record $pendingFinalPath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "FINAL_ACCEPTANCE_SELF_VALIDATION_FAILED: $($finalCheckOutput -join "`n")" }
    $finalCheck = ($finalCheckOutput -join "`n") | ConvertFrom-Json
    if ([string]$finalCheck.status -ne 'PASS' -or -not [bool]$finalCheck.internalPromotionAllowed -or [bool]$finalCheck.publicPromotionAllowed) { throw 'FINAL_ACCEPTANCE_SELF_VALIDATION_NOT_INTERNAL_ONLY_PASS' }
    Move-Item -LiteralPath $pendingFinalPath -Destination $finalPath -Force

    $state = Read-Json $statePath
    Set-Field $state 'validation_evidence_current' $true
    Set-Field $state 'full_release_passed' $true
    Set-Field $state 'internal_promotion_allowed' $true
    Set-Field $state 'public_promotion_allowed' $false
    Set-Field $state 'public_publisher_trust' $false
    Set-Field $state 'final_acceptance_path' 'evidence/FINAL-ACCEPTANCE.json'
    Set-Field $state 'final_acceptance_sha256' (Get-Hash $finalPath)
    Set-Field $state 'final_acceptance_blocker' $null
    Write-AtomicJson $statePath $state
    $finalCheck | ConvertTo-Json -Depth 20
} catch {
    $blocker = [string]$_.Exception.Message
    try {
        # FINAL-ACCEPTANCE is the current pointer, not historical evidence.
        # Any failed revalidation must revoke an older grant as well as a newly
        # published one because Update-CurrentReleaseAuthority intentionally
        # trusts this record instead of mutable state booleans.
        Write-AtomicJson $finalPath ([ordered]@{schemaVersion=1;contract='devfleet-internal-final-acceptance-v1';status='BLOCKED';releaseEligible=$false;internalPromotionAllowed=$false;publicPromotionAllowed=$false;publicPublisherTrust=$false;generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o');blocker=$blocker})
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $failedState = Read-Json $statePath
            Set-Field $failedState 'validation_evidence_current' $false
            Set-Field $failedState 'full_release_passed' $false
            Set-Field $failedState 'internal_promotion_allowed' $false
            Set-Field $failedState 'public_promotion_allowed' $false
            Set-Field $failedState 'public_publisher_trust' $false
            Set-Field $failedState 'final_acceptance_path' 'evidence/FINAL-ACCEPTANCE.json'
            Set-Field $failedState 'final_acceptance_sha256' $null
            Set-Field $failedState 'final_acceptance_blocker' $blocker
            Set-Field $failedState 'final_acceptance_checked_at_utc' (Get-Date).ToUniversalTime().ToString('o')
            Write-AtomicJson $statePath $failedState
        }
    } catch { $blocker = "$blocker; FAIL_CLOSED_STATE_WRITE_FAILED: $($_.Exception.Message)" }
    throw "INTERNAL_ACCEPTANCE_BLOCKED: $blocker"
} finally {
    Remove-Item -LiteralPath $pendingFinalPath -Force -ErrorAction SilentlyContinue
}

```


## FILE: tools/Finalize-CandidateEvidence.ps1

SHA256: 893ad4fee445cc8e7a82482c329015cb816317b68a86552d5a7302f69c731acd | Bytes: 19508 | Git mode: 100644

```
[CmdletBinding()]
param([string]$Workspace = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$source = Join-Path $Workspace 'source'
$installer = Join-Path $Workspace 'installer-source'
$outputs = Join-Path $Workspace 'outputs'
Import-Module (Join-Path $Workspace 'automation\release-e2e\modules\Candidate.psm1') -Force
Import-Module (Join-Path $Workspace 'tools\PythonRuntime.psm1') -Force
$python = Resolve-DevFleetPython -Workspace $Workspace
$version = (Get-Content -LiteralPath (Join-Path $source 'VERSION') -Raw).Trim()
$installerVersion = (Get-Content -LiteralPath (Join-Path $installer 'INSTALLER_VERSION') -Raw).Trim()

function Write-AtomicJson([string]$Path,$Value) {
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,(($Value | ConvertTo-Json -Depth 20) + [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Write-AtomicText([string]$Path,[string]$Value) {
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,$Value,[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Test-PreservedEmptyRootPackageLock([string]$StatusLine) {
    # A prior local npm smoke command left this exact empty lockfile at the
    # workspace root. Preserve it without treating it as candidate input, but
    # keep the exception narrow: tracked/modified, renamed, populated, or
    # differently named lockfiles must still block candidate finalization.
    if ($StatusLine -notmatch '^\?\?\s+package-lock\.json\s*$') { return $false }
    $lockPath = Join-Path $Workspace 'package-lock.json'
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return $false }
    try {
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $propertyNames = @($lock.PSObject.Properties.Name | Sort-Object)
        $expectedNames = @('lockfileVersion','name','packages','requires')
        if (($propertyNames -join '|') -cne ($expectedNames -join '|')) { return $false }
        if ([string]$lock.name -cne (Split-Path -Leaf $Workspace)) { return $false }
        if ([int]$lock.lockfileVersion -ne 3 -or $lock.requires -ne $true) { return $false }
        return (@($lock.packages.PSObject.Properties).Count -eq 0)
    } catch { return $false }
}

$artifactPaths = [ordered]@{
    exe = Join-Path $outputs "DevFleet-Setup-v$version-win-x64.exe"
    tar = Join-Path $outputs "devfleet-v$version.tar.gz"
    portable = Join-Path $outputs "DevFleet-v$version-Portable-Codebase-Verified-r1.zip"
    installerSource = Join-Path $outputs "DevFleet-v$version-Installer-Source.zip"
}
foreach ($path in $artifactPaths.Values) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Candidate artifact is missing: $path" } }
$artifactRows = @(
    foreach ($name in $artifactPaths.Keys) {
        $path = $artifactPaths[$name]
        [ordered]@{name=$name;path=('outputs/' + [IO.Path]::GetFileName($path));bytes=[int64](Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
)

$status = @(& git -C $Workspace status --short)
$unexpected = @($status | Where-Object {
    $_ -notmatch '^\s*[ MADRCU?]{1,2}\s+finalization-state\.(json|txt)\s*$' -and
    $_ -notmatch '^\s*[ MADRCU?]{1,2}\s+audit(?:\\|/)' -and
    $_ -notmatch '^\s*[ MADRCU?]{1,2}\s+audit-extract(?:\\|/)' -and
    $_ -notmatch '^\s*[ MADRCU?]{1,2}\s+evidence(?:\\|/)' -and
    $_ -notmatch '^\s*[ MADRCU?]{1,2}\s+(?:tools|automation/release-e2e)(?:\\|/)' -and
    $_ -notmatch '^\s*[ MADRCU?]{1,2}\s+source/tools/validate_audit_coherence\.py\s*$' -and
    $_ -notmatch '^\s*[ MADRCU?]{1,2}\s+CURRENT-CANDIDATE\.json\s*$' -and
    $_ -notmatch '^\?\?\s+codex-session-[0-9a-f-]+\.md\s*$' -and
    -not (Test-PreservedEmptyRootPackageLock $_)
})
if ($unexpected.Count) { throw "Candidate source/tooling tree is not clean after the generated payload closure commit: $($unexpected -join '; ')" }
$head = (& git -C $Workspace rev-parse HEAD).Trim()
$branch = (& git -C $Workspace branch --show-current).Trim()
if ($head -notmatch '^[0-9a-f]{40}$' -or -not $branch) { throw 'Final candidate Git identity is invalid.' }
$existingState = Get-Content -LiteralPath (Join-Path $Workspace 'finalization-state.json') -Raw | ConvertFrom-Json
$candidateCommit = [string]($existingState.candidate_git_commit ?? $existingState.candidateGitCommit)
if ($candidateCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'Existing candidate commit is missing or malformed; refusing to bind it to the live HEAD.' }

$identityArguments = @('--workspace',$Workspace,'--candidate-commit',$candidateCommit)
foreach ($name in $artifactPaths.Keys) { $identityArguments += @('--artifact',"$name=$($artifactPaths[$name])") }
$identityRaw = @(& $python (Join-Path $Workspace 'tools\compute_shipping_input_identity.py') @identityArguments)
if ($LASTEXITCODE -ne 0 -or $identityRaw.Count -eq 0) { throw 'Candidate Git-object fingerprint regeneration failed.' }
try { $identity = ($identityRaw -join "`n") | ConvertFrom-Json } catch { throw "Candidate fingerprint output was not valid JSON: $($_.Exception.Message)" }
$candidateIdentity = [string]$identity.candidateShippingInputIdentity
$existingCandidateIdentity = [string]($existingState.shipping_input_identity ?? $existingState.shippingInputIdentity)
if ($candidateIdentity -notmatch '^[0-9a-f]{64}$') { throw 'Candidate Git-object shipping identity is malformed.' }
$generatedAuthorityRefresh = [string]::IsNullOrWhiteSpace($existingCandidateIdentity)
if ($generatedAuthorityRefresh) {
    if (-not [bool]$existingState.candidate_is_current -or -not [bool]$existingState.candidate_build_current -or [bool]$existingState.source_changed_since_candidate -or [bool]$existingState.rebuild_required) {
        throw 'Generated candidate authority omitted its shipping identity outside the exact fresh-build state.'
    }
} elseif ($existingCandidateIdentity -notmatch '^[0-9a-f]{64}$' -or $candidateIdentity -cne $existingCandidateIdentity) {
    throw 'Candidate Git-object shipping identity differs from the preserved signed-candidate authority.'
}
if ([string]$identity.liveShippingInputIdentity -cne $candidateIdentity -and -not [bool]$identity.crlfOnlyMaterialization) { throw 'Live shipping inputs differ substantively from the preserved candidate; rebuild/sign review is required.' }
if ([string]$identity.lineEndingComparison -notin @('BYTE_EXACT','CRLF_ONLY')) { throw 'Live/candidate materialization comparison is not release-safe.' }
$fingerprint = $identity.candidateFingerprint
if (-not $fingerprint -or [int]$fingerprint.schemaVersion -ne 2) { throw 'Candidate Git-object materialization did not produce release fingerprint schema v2.' }
$existingReleaseId = [string]$existingState.releaseFingerprintId
if ([string]$fingerprint.releaseFingerprintId -notmatch '^[0-9a-f]{64}$' -or [string]$fingerprint.releaseFingerprintId -cne $existingReleaseId) { throw 'Candidate Git-object release fingerprint differs from the preserved signed-candidate authority.' }
$fingerprint | Add-Member -NotePropertyName toolingFingerprint -NotePropertyValue $identity.liveToolingFingerprint -Force
$candidateArtifactMap = @{}; foreach ($row in @($fingerprint.artifacts)) { $candidateArtifactMap[[string]$row.name] = $row }
foreach ($row in $artifactRows) {
    $candidateArtifact = $candidateArtifactMap[[string]$row.name]
    if (-not $candidateArtifact -or [int64]$candidateArtifact.bytes -ne [int64]$row.bytes -or [string]$candidateArtifact.sha256 -cne [string]$row.sha256) { throw "Candidate release fingerprint artifact tuple differs at $($row.name)." }
}
if ($candidateArtifactMap.Count -ne $artifactRows.Count) { throw 'Candidate release fingerprint artifact tuple is not exactly the four release artifacts.' }
Write-AtomicJson (Join-Path $outputs 'release-fingerprint.json') $fingerprint

$toolingCurrent = [ordered]@{schemaVersion=2;releaseFingerprintSchemaVersion=2;repositoryHead=$head;gitCommit=$head;releaseFingerprintId=$fingerprint.releaseFingerprintId;toolingFingerprintId=$identity.liveToolingFingerprint.toolingFingerprintId;toolingInputs=$identity.liveToolingFingerprint.toolingInputs;artifacts=$artifactRows;candidateGitCommit=$candidateCommit;shippingInputIdentity=$candidateIdentity;lineEndingComparison=[string]$identity.lineEndingComparison;crlfOnlyPaths=@($identity.crlfOnlyPaths);generatedAt=(Get-Date).ToUniversalTime().ToString('o')}
Write-AtomicJson (Join-Path $outputs 'tooling-fingerprint-current.json') $toolingCurrent
$providerPath = Join-Path $outputs 'signing-provider.json'
if (-not (Test-Path -LiteralPath $providerPath -PathType Leaf)) { throw 'Signed candidate provider evidence is missing.' }
$provider = Get-Content -LiteralPath $providerPath -Raw | ConvertFrom-Json -ErrorAction Stop
$signing = 'PRIVATE SELF-SIGNED AUTHENTICODE — VALID ON EXPLICITLY TRUSTED PERSONAL/TEST SYSTEMS'
$exeRow = @($artifactRows | Where-Object name -eq 'exe')
$publicCertificatePath = Join-Path $outputs 'DevFleet-Private-Personal-Code-Signing.cer'
if (-not (Test-Path -LiteralPath $publicCertificatePath -PathType Leaf)) { throw 'Private signing public verifier certificate is missing.' }
$authenticode = Test-PrivateAuthenticodeSignature -Path $artifactPaths.exe -PublicCertificatePath $publicCertificatePath -ExpectedThumbprint ([string]$provider.signerThumbprint)
$signature = Get-AuthenticodeSignature -LiteralPath $artifactPaths.exe
$providerProfile = if ([string]$provider.privateSigningProfile) { [string]$provider.privateSigningProfile } elseif ([string]$provider.signingProfile -eq 'PrivateSelfSigned') { 'PRIVATE_SELF_SIGNED' } else { '' }
$providerPrivateKeyExportable = if ($null -eq $provider.privateKeyExportable) { $false } else { [bool]$provider.privateKeyExportable }
$providerPrivateKeyExported = if ($null -eq $provider.privateKeyExported) { $false } else { [bool]$provider.privateKeyExported }
$providerPublicPublisherTrust = if ($null -eq $provider.publicPublisherTrust) { $false } else { [bool]$provider.publicPublisherTrust }
$providerPublicPromotionAllowed = if ($null -eq $provider.publicPromotionAllowed) { $false } else { [bool]$provider.publicPromotionAllowed }
$providerCodeSigningEku = if ([string]$provider.codeSigningEku) { [string]$provider.codeSigningEku } else { '1.3.6.1.5.5.7.3.3' }
$providerRsaBits = if ([int]$provider.rsaBits -gt 0) { [int]$provider.rsaBits } else { [int]$signature.SignerCertificate.PublicKey.Key.KeySize }
$providerTamperStatus = if ([string]$provider.tamperedCopyVerification) { [string]$provider.tamperedCopyVerification } else { [string]$provider.tamperedCopyStatus }
if ($exeRow.Count -ne 1 -or $providerProfile -ne 'PRIVATE_SELF_SIGNED') { throw 'Signed candidate provider profile is invalid.' }
if ($providerPrivateKeyExportable -or $providerPrivateKeyExported -or $providerPublicPublisherTrust -or $providerPublicPromotionAllowed) { throw 'Signed candidate provider violates the private-signing safety contract.' }
if ([string]$provider.finalSignedExe.sha256 -ne [string]$exeRow[0].sha256 -or [int64]$provider.finalSignedExe.bytes -ne [int64]$exeRow[0].bytes) { throw 'Signed candidate provider identity differs from the exact EXE.' }
if ([string]$authenticode.status -ne 'PASS' -or [string]$authenticode.effectiveSignatureStatus -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -cne [string]$provider.signerThumbprint) { throw 'Exact signed candidate Authenticode verification failed.' }
if ('1.3.6.1.5.5.7.3.3' -notin @($signature.SignerCertificate.EnhancedKeyUsageList | ForEach-Object { [string]$_.ObjectId })) { throw 'Exact signed candidate lacks the Code Signing EKU.' }
$canonicalProvider = [ordered]@{
    schemaVersion = 1
    provider = [string]$provider.provider
    signingProfile = 'PrivateSelfSigned'
    privateSigningProfile = 'PRIVATE_SELF_SIGNED'
    timestampState = [string]$provider.timestampState
    signatureStatus = [string]$authenticode.effectiveSignatureStatus
    platformSignatureStatus = [string]$authenticode.platformSignatureStatus
    platformSignatureStatusMessage = [string]$authenticode.platformSignatureStatusMessage
    signerSubject = [string]$provider.signerSubject
    signerThumbprint = [string]$provider.signerThumbprint
    codeSigningEkuVerified = $true
    codeSigningEku = $providerCodeSigningEku
    rsaBits = $providerRsaBits
    signtoolVerification = [string]$provider.signtoolVerification
    tamperedCopyVerification = [string]$authenticode.tamperedCopyStatus
    explicitTrustValidation = [string]$authenticode.explicitTrustValidation
    trustMode = [string]$authenticode.trustMode
    trustStoreMutated = [bool]$authenticode.trustStoreMutated
    preSignExe = $provider.preSignExe
    finalSignedExe = $provider.finalSignedExe
    publicCertificate = $provider.publicCertificate
    privateKeyExportable = $providerPrivateKeyExportable
    privateKeyExported = $providerPrivateKeyExported
    publicPublisherTrust = $providerPublicPublisherTrust
    publicPromotionAllowed = $providerPublicPromotionAllowed
}
Write-AtomicJson $providerPath $canonicalProvider
$provider = [pscustomobject]$canonicalProvider
$manifest = [ordered]@{schemaVersion=2;releaseFingerprintSchemaVersion=2;releaseVersion=$version;installerVersion=$installerVersion;repositoryHead=$head;gitCommit=$head;branch=$branch;candidateGitCommit=$candidateCommit;shippingInputIdentity=$candidateIdentity;releaseFingerprintId=$fingerprint.releaseFingerprintId;toolingFingerprintId=$identity.liveToolingFingerprint.toolingFingerprintId;artifacts=$artifactRows;preSignExe=$provider.preSignExe;sourceChangedSinceCandidate=$false;rebuildRequired=$false;sourceIdentityMatchesCandidate=$true;artifactTupleMatchesCandidate=$true;candidateBuildCurrent=$true;candidateIsCurrent=$true;validationEvidenceCurrent=$false;fullReleasePassed=$false;physicalSurrogateCertificationCurrent=$false;internalPromotionAllowed=$false;publicPromotionAllowed=$false;releaseStatus='BLOCKED';signingState=$signing;signing=$signing;privateSigningProfile='PRIVATE_SELF_SIGNED';privateSigningCertificateThumbprint=[string]$provider.signerThumbprint;signerSubject=[string]$provider.signerSubject;codeSigningEku=[string]$provider.codeSigningEku;rsaBits=[int]$provider.rsaBits;privateKeyExportable=$false;privateKeyExported=$false;publicCertificate=$provider.publicCertificate;publicPublisherTrust=$false;timestampState=[string]$provider.timestampState;gitClean=($status.Count -eq 0);lineEndingComparison=[string]$identity.lineEndingComparison;crlfOnlyPaths=@($identity.crlfOnlyPaths)}
Write-AtomicJson (Join-Path $outputs 'final-artifact-hashes.json') $manifest

$statePath = Join-Path $Workspace 'finalization-state.json'
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
$previousFullReleasePassed=[bool]$state.full_release_passed
$previousFullReleaseRunId=[string]$state.full_release_run_id
$state.release_version=$version;$state.installer_version=$installerVersion;$state.branch=$branch;$state.repository_head=$head;$state.git_commit=$head;$state.candidate_git_commit=$candidateCommit
$state.release_fingerprint_schema_version=2;$state.releaseFingerprintId=$fingerprint.releaseFingerprintId;$state.toolingFingerprintId=$identity.liveToolingFingerprint.toolingFingerprintId
$state.shipping_input_identity=$candidateIdentity
$state.working_tree_tooling_fingerprint_id=$identity.liveToolingFingerprint.toolingFingerprintId
$state.working_tree_shipping_input_identity=$candidateIdentity
$state.source_changed_since_candidate=$false;$state.rebuild_required=$false;$state.source_identity_matches_candidate=$true;$state.artifact_tuple_matches_candidate=$true;$state.candidate_build_current=$true;$state.candidate_is_current=$true
$state.validation_evidence_current=$false;$state.full_release_passed=$false;$state.internal_promotion_allowed=$false;$state.public_promotion_allowed=$false;$state.public_publisher_trust=$false;$state.release_status='BLOCKED';$state.signing_state=$signing
$state.private_signing_profile='PRIVATE_SELF_SIGNED';$state.private_signing_certificate_thumbprint=[string]$provider.signerThumbprint;$state.signing_subject=[string]$provider.signerSubject;$state.signing_code_signing_eku=[string]$provider.codeSigningEku;$state.signing_rsa_bits=[int]$provider.rsaBits;$state.private_key_exportable=$false;$state.private_key_exported=$false;$state.timestamp_state=[string]$provider.timestampState;$state.pre_sign_exe=$provider.preSignExe;$state.public_signing_certificate=$provider.publicCertificate
$state.current_phase='PRE-EXACT-PROOF';$state.last_completed_phase='CANDIDATE-EVIDENCE-BINDING';$state.status='BLOCKED — fresh exact-candidate proofs and FullRelease required'
$state.candidate_binding_utc=(Get-Date).ToUniversalTime().ToString('o')
if ($previousFullReleaseRunId -and -not $previousFullReleasePassed) {
    $state.historical_full_release_run_ids=@(@($state.historical_full_release_run_ids)+$previousFullReleaseRunId | Select-Object -Unique)
    $state.full_release_run_id=$null
}
if ($state.ai_audit_bundle) { $state.ai_audit_bundle.current=$false;$state.ai_audit_bundle.historical=$true;$state.ai_audit_bundle.historicalReason='Superseded by current release-tooling HEAD.' }
$state.blockers=@('Fresh exact-candidate proof 1 and proof 2 are required.','Fresh coherent FullRelease and maintenance 5/5 are required.')
$state.candidate=[ordered]@{exe=$artifactRows[0];tar=$artifactRows[1];portable=$artifactRows[2];installer_source=$artifactRows[3]}
Write-AtomicJson $statePath $state
$stateText=(@("DevFleet $version / Installer $installerVersion",'Status: candidate current; awaiting exact-candidate proofs and coherent FullRelease',"Repository/tooling HEAD: $head","Candidate commit: $candidateCommit","Shipping input identity: $candidateIdentity","Release fingerprint schema: 2","Release fingerprint: $($fingerprint.releaseFingerprintId)","Tooling fingerprint: $($identity.liveToolingFingerprint.toolingFingerprintId)","Line-ending comparison: $([string]$identity.lineEndingComparison)",'Signing: PRIVATE SELF-SIGNED AUTHENTICODE — VALID ON EXPLICITLY TRUSTED PERSONAL/TEST SYSTEMS','Source changed since candidate: FALSE','Rebuild required: FALSE','Candidate is current: TRUE','Acceptance gates remain unpromoted until current exact-candidate evidence exists.') -join [Environment]::NewLine) + [Environment]::NewLine
Write-AtomicText (Join-Path $Workspace 'finalization-state.txt') $stateText
$authorityOutput = @(& (Join-Path $Workspace 'tools\Update-CurrentReleaseAuthority.ps1') -Workspace $Workspace)
$authoritySucceeded = $?
if (-not $authoritySucceeded -or $authorityOutput.Count -eq 0) { throw 'Current release authority refresh failed after candidate evidence binding.' }
[pscustomobject]@{schemaVersion=2;gitCommit=$head;candidateGitCommit=$candidateCommit;shippingInputIdentity=$candidateIdentity;releaseFingerprintId=$fingerprint.releaseFingerprintId;toolingFingerprintId=$identity.liveToolingFingerprint.toolingFingerprintId;lineEndingComparison=[string]$identity.lineEndingComparison;artifacts=$artifactRows} | ConvertTo-Json -Depth 8

```


## FILE: tools/Invoke-DevFleetFinalConvergence.ps1

SHA256: d571fb3bf3d137db417fb55e1a825f98414ea51561d8bd09a94a30eed8f12478 | Bytes: 31192 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$Workspace = (Split-Path -Parent $PSScriptRoot),
    [string]$StageScript,
    [string[]]$StageArgumentList = @(),
    [ValidateSet('AUTO','PASS','BLOCKED')][string]$TerminalMode = 'AUTO',
    [string]$PrimaryBlocker,
    [string]$PrimaryBlockerClassification,
    [guid]$L1Id = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2',
    [string]$L1Name = 'DevFleet-E2E-Win11-01',
    [string]$L2Name = 'DevFleet-E2E-Linux-01',
    [string]$RunId,
    [string]$RunDirectory,
    [switch]$L1Touched,
    [switch]$InteractiveLogonArmed,
    [switch]$SkipLiveCleanup
)

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$audit = Join-Path $Workspace 'audit'
$evidence = Join-Path $Workspace 'evidence'
$outputs = Join-Path $Workspace 'outputs'
$cleanupModule = Join-Path $Workspace 'automation\release-e2e\modules\Cleanup.psm1'
Import-Module -Name $cleanupModule -Force -ErrorAction Stop
$zipPath = Join-Path $outputs 'DevFleet-v1.2.13-AI-Audit-LATEST.zip'
$sidecarPath = "$zipPath.sha256.txt"
$primaryRecordPath = Join-Path $audit 'FINALIZER-PRIMARY-BLOCKER.json'
$stageError = $null
$secondaryErrors = [System.Collections.Generic.List[string]]::new()
$finalizerStatus = 'BLOCKED'
$stageResult = $null

function Add-SecondaryError([string]$Message) {
    if ($Message -and -not $secondaryErrors.Contains($Message)) { [void]$secondaryErrors.Add($Message) }
}

function Write-AtomicJson([string]$Path, $Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 40) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Get-FileSha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Get-SafeError([object]$ErrorRecord) {
    $message = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    if (-not $message) { $message = 'Unknown controlled terminal error.' }
    return ($message -replace '(?i)(password|secret|token|hmac|dpapi|private.?key)\s*[:=]\s*[^;\r\n ]+', '$1=[REDACTED]')
}

function Write-PrimaryRecord([string]$Status, [string]$Classification, [string]$Blocker, [string[]]$Secondary) {
    Write-AtomicJson $primaryRecordPath ([ordered]@{
        schemaVersion=1; generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o'); status=$Status
        primaryBlocker=if($Blocker){$Blocker}else{$null}; primaryBlockerClassification=if($Classification){$Classification}else{$null}
        secondaryBlockers=@($Secondary); credentialsStoredInEvidence=$false; credentialValuesIncluded=$false; hostAgentSecretsIncluded=$false
    })
}

function Test-CandidateEvidenceRefreshRequired([psobject]$State) {
    <# Rebinding candidate evidence advances candidate_binding_utc and therefore
       intentionally invalidates proof starts. Only do it when the persisted
       candidate identity is absent or differs from the current committed
       tuple. A read-only terminal/finalizer pass must not age out valid proofs. #>
    if (-not $State) { return $true }
    $head = (& git -C $Workspace rev-parse HEAD 2>$null).Trim()
    if ([string]$State.repository_head -cne $head) { return $true }
    if ([string]::IsNullOrWhiteSpace([string]$State.candidate_binding_utc)) { return $true }
    if ([bool]$State.source_changed_since_candidate -or [bool]$State.rebuild_required) { return $true }
    if ([string]$State.working_tree_tooling_fingerprint_id -cne [string]$State.toolingFingerprintId) { return $true }
    if ([string]$State.working_tree_shipping_input_identity -cne [string]$State.shipping_input_identity) { return $true }
    $toolingPath = Join-Path $Workspace 'outputs\tooling-fingerprint-current.json'
    if (-not (Test-Path -LiteralPath $toolingPath -PathType Leaf)) { return $true }
    try {
        $tooling = Get-Content -LiteralPath $toolingPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string]$tooling.toolingFingerprintId) -or [string]$tooling.toolingFingerprintId -cne [string]$State.toolingFingerprintId) { return $true }
    } catch { return $true }
    return $false
}

function Get-CurrentNestedL2ReleaseEvidence {
    param([string]$ExpectedRunId,[string]$RunDirectory)
    if([string]::IsNullOrWhiteSpace($ExpectedRunId) -or [string]::IsNullOrWhiteSpace($RunDirectory)){throw 'No exact current FullRelease RunId and run directory were supplied.'}
    $expectedRunRoot=[IO.Path]::GetFullPath((Join-Path $Workspace (Join-Path 'audit\automation-harness\runs' $ExpectedRunId)))
    $actualRunRoot=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RunDirectory -ErrorAction Stop).Path)
    if([IO.Path]::GetFileName($actualRunRoot) -cne $ExpectedRunId -or -not $actualRunRoot.Equals($expectedRunRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Nested L2 evidence directory is outside the exact current FullRelease RunId root.'}
    foreach($relative in @('audit','audit\automation-harness','audit\automation-harness\runs',(Join-Path 'audit\automation-harness\runs' $ExpectedRunId))){
        $directory=Get-Item -LiteralPath (Join-Path $Workspace $relative) -Force -ErrorAction Stop
        if(-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Nested L2 evidence path contains a disallowed reparse directory.'}
    }
    $readBoundJson={
        param([string]$Path)
        $bytes=[IO.File]::ReadAllBytes($Path)
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        $encoding=[Text.UTF8Encoding]::new($false,$true)
        $text=$encoding.GetString($bytes)
        if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
        [pscustomobject]@{value=($text|ConvertFrom-Json -ErrorAction Stop);sha256=$hash}
    }
    $paths=@{
        state=(Join-Path $actualRunRoot 'run-state.json')
        phases=(Join-Path $actualRunRoot 'fullrelease-phase-records.json')
        cleanup=(Join-Path $actualRunRoot 'final-cleanup.json')
        post=(Join-Path $actualRunRoot 'post-cleanup-finalization.json')
        l1=(Join-Path $actualRunRoot 'l1-terminal-state.json')
        l2=(Join-Path $actualRunRoot 'l2-terminal-state.json')
        nested=(Join-Path $actualRunRoot 'nested-l2-terminal-observation.json')
    }
    $read=@{}
    foreach($key in $paths.Keys){if(-not(Test-Path -LiteralPath $paths[$key] -PathType Leaf)){throw "Current FullRelease terminal evidence is missing $key."};$inputFile=Get-Item -LiteralPath $paths[$key] -Force -ErrorAction Stop;if($inputFile.PSIsContainer -or ($inputFile.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Current FullRelease terminal evidence $key is not a regular non-reparse file."};$read[$key]=&$readBoundJson $paths[$key]}
    $state=$read.state.value;$cleanup=$read.cleanup.value;$post=$read.post.value;$l1=$read.l1.value;$l2=$read.l2.value;$nested=$read.nested.value
    if([string]$state.runId -cne $ExpectedRunId -or [string]$state.mode -cne 'FullRelease' -or [string]$state.finalStatus -cne 'PASS'){throw 'Current run-state does not represent a passing FullRelease.'}
    $cleanupPhases=@($read.phases.value|Where-Object{[string]$_.id -ceq 'CLEANUP'})
    if([string]$cleanup.status -cne 'PASS' -or [string]$cleanup.runId -cne $ExpectedRunId -or -not [bool]$cleanup.guest.runRootAbsent -or -not [bool]$cleanup.guest.nestedAbsent -or [bool]$cleanup.guest.foreignResourcesMutated -or $cleanupPhases.Count -ne 1 -or [string]$cleanupPhases[0].status -cne 'PASS' -or [string]$post.status -cne 'PASS' -or [string]$post.runId -cne $ExpectedRunId -or [bool]$post.cleanupConsumed -ne $true){throw 'Current FullRelease cleanup/finalization did not pass for the exact RunId.'}
    if(-not $post.liveChecks -or -not [bool]$post.liveChecks.l1ExactOff -or -not [bool]$post.liveChecks.l2ExactAbsent -or -not [bool]$post.liveChecks.hostSameNameL2Absent -or [bool]$post.liveChecks.foreignResourcesMutated){throw 'Current FullRelease post-cleanup host guard or exact terminal checks did not pass.'}
    if([string]$l1.name -cne $L1Name -or [string]$l1.id -cne $L1Id.ToString() -or [string]$l1.state -cne 'Off' -or [string]$l1.runId -cne $ExpectedRunId){throw 'Current FullRelease L1 evidence is not exact OFF for the current RunId.'}
    if([string]$l2.expectedName -cne $L2Name -or [string]$l2.status -cne 'ABSENT' -or $l2.present -ne $false -or [string]$l2.runId -cne $ExpectedRunId -or [string]$l2.sourceRunId -cne $ExpectedRunId -or [string]$l2.sourceEvidence -cne 'nested-l2-terminal-observation.json' -or [string]$l2.nestedScope -cne 'inside the exact L1 guest session' -or [string]$l2.l1Name -cne $L1Name -or [string]$l2.l1Id -cne $L1Id.ToString() -or [string]$l2.evidenceClass -cne 'FullRelease run-bound nested observation'){throw 'Current FullRelease nested L2 record is not exact, run-bound, and positively absent.'}
    if([string]$nested.status -cne 'ABSENT' -or $nested.present -isnot [bool] -or $nested.present -ne $false -or [string]$nested.runId -cne $ExpectedRunId -or [string]$nested.expectedName -cne $L2Name -or [string]$nested.nestedScope -cne 'inside the exact L1 guest session' -or [string]$nested.observer -cne 'Get-DevFleetNestedL2State' -or [string]$nested.l1.name -cne $L1Name -or [string]$nested.l1.id -cne $L1Id.ToString() -or ($nested.exactMatchCount -isnot [int] -and $nested.exactMatchCount -isnot [long]) -or [long]$nested.exactMatchCount -ne 0){throw 'Current FullRelease nested L2 source record does not support the published terminal claim.'}
    if([string]$nested.verification -ceq 'Bounded Multipass JSON inventory inside exact L1'){
        if(($nested.inventoryCount -isnot [int] -and $nested.inventoryCount -isnot [long]) -or [long]$nested.inventoryCount -lt 0){throw 'Current FullRelease Multipass inventory is incomplete.'}
    }elseif([string]$nested.verification -ceq 'Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend'){
        $providers=[Collections.Generic.List[string]]::new();$backendRows=@($nested.backendInventories)
        if($backendRows.Count -ne 2){throw 'Current FullRelease nested source is missing a supported backend inventory.'}
        foreach($backend in $backendRows){
            $provider=[string]$backend.provider
            if($provider -cnotin @('Hyper-V','VirtualBox') -or $providers.Contains($provider) -or [string]$backend.status -cne 'PASS' -or $backend.names -isnot [array] -or [string]::IsNullOrWhiteSpace([string]$backend.verification)){throw 'Current FullRelease nested backend inventory is incomplete or ambiguous.'}
            $instanceNames=[Collections.Generic.List[string]]::new()
            foreach($instanceName in $backend.names){
                if($instanceName -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$instanceName)){throw 'Current FullRelease nested backend inventory contains an invalid instance name.'}
                if($instanceNames.Contains([string]$instanceName)){throw 'Current FullRelease nested backend inventory contains a duplicate instance name.'}
                if([string]$instanceName -ceq $L2Name){throw 'Current FullRelease nested backend inventory still contains the exact L2 target.'}
                $instanceNames.Add([string]$instanceName)
            }
            $providers.Add($provider)
        }
        if($providers.Count -ne 2 -or 'Hyper-V' -notin $providers -or 'VirtualBox' -notin $providers){throw 'Current FullRelease nested source omitted a supported backend.'}
    }else{throw 'Current FullRelease nested source uses an unsupported or incomplete inventory method.'}
    if($read.nested.sha256 -cne [string]$l2.sourceEvidenceSha256 -or $read.nested.sha256 -cne [string]$post.nestedL2ObservationSha256 -or $read.l2.sha256 -cne [string]$post.terminalL2Hash -or $read.cleanup.sha256 -cne [string]$post.cleanupEvidenceHash){throw 'Current FullRelease terminal source/hash bindings do not match.'}
    if($read.l1.sha256 -cne [string]$post.terminalL1Hash -or [string]$post.terminalL2 -cne 'l2-terminal-state.json'){throw 'Current FullRelease finalization does not bind its terminal evidence.'}
    $candidateTuplePatterns=[ordered]@{
        repositoryHead='^[0-9a-f]{40}$'
        candidateCommit='^[0-9a-f]{40}$'
        shippingInputIdentity='^[0-9a-f]{64}$'
        releaseFingerprintId='^[0-9a-f]{64}$'
        toolingFingerprintId='^[0-9a-f]{64}$'
    }
    foreach($key in $candidateTuplePatterns.Keys){
        $tupleValue=''
        if($state.candidateHashes -is [System.Collections.IDictionary]){$tupleValue=[string]$state.candidateHashes[$key]}
        elseif($state.candidateHashes){$tupleProperty=$state.candidateHashes.PSObject.Properties[$key];if($tupleProperty){$tupleValue=[string]$tupleProperty.Value}}
        if($tupleValue -cnotmatch $candidateTuplePatterns[$key]){throw 'Current FullRelease candidate tuple is malformed or incomplete.'}
    }
    foreach($key in $candidateTuplePatterns.Keys){
        if([string]$l2.candidate.$key -cne [string]$state.candidateHashes.$key -or [string]$nested.candidate.$key -cne [string]$state.candidateHashes.$key -or [string]$cleanup.candidate.$key -cne [string]$state.candidateHashes.$key -or [string]$post.candidate.$key -cne [string]$state.candidateHashes.$key){throw "Current FullRelease nested evidence is stale for candidate field $key."}
    }
    $asUtcText={param($value)if($value -is [datetimeoffset]){return $value.UtcDateTime.ToString('o')}if($value -is [datetime]){return $value.ToUniversalTime().ToString('o')}return [string]$value}
    $nestedUtcText=&$asUtcText $nested.observedUtc;$l1UtcText=&$asUtcText $l1.timestampUtc;$l2UtcText=&$asUtcText $l2.timestampUtc
    $nestedUtc=[datetimeoffset]::MinValue;$l1Utc=[datetimeoffset]::MinValue
    $roundtrip=[Globalization.DateTimeStyles]::RoundtripKind;$invariant=[Globalization.CultureInfo]::InvariantCulture
    if(-not[datetimeoffset]::TryParse($nestedUtcText,$invariant,$roundtrip,[ref]$nestedUtc)-or$nestedUtc.Offset-ne[timespan]::Zero-or-not[datetimeoffset]::TryParse($l1UtcText,$invariant,$roundtrip,[ref]$l1Utc)-or$l1Utc.Offset-ne[timespan]::Zero-or$nestedUtc-gt$l1Utc-or$l2UtcText-cne$nestedUtcText){throw 'Current FullRelease nested/L1 UTC observation times are invalid or out of order.'}
    return [pscustomobject]@{terminalL2=$l2;runId=$ExpectedRunId;candidate=$l2.candidate;sourceEvidence=$paths.nested;sourceEvidenceSha256=$read.nested.sha256}
}

function Merge-FinalizerTerminalOutcome {
    param([string]$CurrentStatus,[string]$PrimaryBlocker,[string]$PrimaryBlockerClassification,[string[]]$SecondaryErrors,[psobject]$Terminal)
    $status=$CurrentStatus;$primary=$PrimaryBlocker;$classification=$PrimaryBlockerClassification
    $secondary=[Collections.Generic.List[string]]::new();foreach($item in @($SecondaryErrors)){if($item){$secondary.Add([string]$item)}}
    if([string]$Terminal.status -cne 'PASS'){
        $status='BLOCKED';$message=if($Terminal.l2Error){[string]$Terminal.l2Error}else{'Exact terminal evidence did not establish a safe PASS.'}
        if(-not $primary){$primary=$message;if(-not $classification){$classification='BLOCKED — FINALIZER TERMINAL EVIDENCE'}}
        else{$secondaryMessage="Terminal cleanup: $message";if(-not $secondary.Contains($secondaryMessage)){$secondary.Add($secondaryMessage)}}
    }
    [pscustomobject]@{status=$status;primaryBlocker=$primary;primaryBlockerClassification=$classification;secondaryErrors=@($secondary.ToArray())}
}

function Invoke-ExactTerminalCleanup {
    if ($SkipLiveCleanup) { return [ordered]@{status='SKIPPED_FOR_TEST';l1State='NOT_CHECKED';l2State='NOT_CHECKED'} }
    $result = [ordered]@{status='PASS';l1State='UNVERIFIED';l2State='UNVERIFIED';l1Name=$L1Name;l1Id=$L1Id.ToString();l2Name=$L2Name}
    try {
        $vm = Get-VM -Id $L1Id -ErrorAction Stop
        if ($vm.Name -cne $L1Name -or [guid]$vm.Id -ne $L1Id) { throw "Exact L1 identity mismatch: expected exact GUID/name $L1Id / $L1Name." }
        if ($L1Touched -and [string]$vm.State -ne 'Off') {
            Import-Module (Join-Path $Workspace 'automation\release-e2e\modules\InteractiveLogon.psm1') -Force
            $interactiveCleanup=Clear-DevFleetE2EInteractiveLogonState -VmId $L1Id
            if([string]$interactiveCleanup.status -ne 'PASS' -or -not [bool]$interactiveCleanup.registryCleanupPersisted -or [bool]$interactiveCleanup.ordinaryDefaultPasswordPresent){throw 'Exact touched L1 durable interactive cleanup did not pass before force-stop.'}
            $result.interactiveCleanup=$interactiveCleanup
            Stop-VM -VM $vm -Force -Confirm:$false -ErrorAction Stop
        }
        $vm = Get-VM -Id $L1Id -ErrorAction Stop
        if ($vm.Name -cne $L1Name -or [guid]$vm.Id -ne $L1Id) { throw 'Exact L1 GUID/name identity changed during finalization.' }
        $result.l1State = [string]$vm.State; $result.l1ExactOff = ([string]$vm.State -eq 'Off')
        $l1Timestamp=(Get-Date).ToUniversalTime().ToString('o')
        $result.l1Observation=[ordered]@{schemaVersion=1;name=$vm.Name;id=$vm.Id.ToString();state=[string]$vm.State;timestamp=$l1Timestamp;timestampUtc=$l1Timestamp;ownershipScope='exact disposable DevFleet-E2E VM identity';ownershipMethod='Get-VM -Id plus exact case-sensitive name'}
        if (-not $result.l1ExactOff) { throw 'Exact disposable L1 is not safely Off at finalization.' }
    } catch {
        $result.status='BLOCKED'; $result.l1Error=Get-SafeError $_; Add-SecondaryError "L1 terminal cleanup: $($result.l1Error)"
    }
    $nestedProof=$null
    try { $nestedProof=Get-CurrentNestedL2ReleaseEvidence -ExpectedRunId $RunId -RunDirectory $RunDirectory }
    catch { $result.l2EvidenceError=Get-SafeError $_ }
    try {
        # The exact host-name guard is distinct from nested evidence: an exact
        # Hyper-V missing-name result can satisfy only this additional exclusion.
        $hostExclusion=Get-DevFleetHostNameExclusion -Name $L2Name
        if([string]$hostExclusion.name -cne $L2Name -or [string]$hostExclusion.inventoryScope -cne 'host Hyper-V exact-name exclusion only' -or $hostExclusion.present -isnot [bool]){throw 'Host same-name exclusion result is malformed or has the wrong scope.'}
        $hostRows=@($hostExclusion.resources)
        if(($hostExclusion.present -eq $false -and ([string]$hostExclusion.status -cne 'ABSENT' -or $hostRows.Count -ne 0)) -or ($hostExclusion.present -eq $true -and ([string]$hostExclusion.status -cne 'PRESENT' -or $hostRows.Count -lt 1))){throw 'Host same-name exclusion result is incomplete or inconsistent.'}
        if($hostRows.Count -gt 1){throw "Ambiguous same-name host resource '$L2Name'; no deletion or adoption attempted."}
        $result.hostL2Exclusion=$hostExclusion
        $result.hostL2Excluded=($hostExclusion.present -eq $false)
        if($hostExclusion.present){$result.hostL2Conflict=[ordered]@{name=[string]$hostRows[0].name;id=[string]$hostRows[0].id;state=[string]$hostRows[0].state;scope='host Hyper-V foreign-resource guard only'}}
        if($nestedProof){
            $result.l2Observation=$nestedProof.terminalL2
            $result.l2State='ABSENT';$result.l2ExactAbsent=$true
        }else{
            $priorL2Path=Join-Path $evidence 'l2-terminal-state.json';$priorL2Hash=$null
            if(Test-Path -LiteralPath $priorL2Path -PathType Leaf){try{$priorL2Hash=Get-FileSha256 $priorL2Path}catch{}}
            $result.l2State='UNVERIFIED';$result.l2ExactAbsent=$false
            $result.l2Observation=[ordered]@{schemaVersion=2;expectedName=$L2Name;status='UNVERIFIED';present=$null;verificationMethod='No validated current RunId-bound nested L1 inventory was available';ownershipScope='exact expected nested L2 name inside exact disposable L1';evidenceClass='finalizer observation; non-certifying';priorCanonicalEvidenceSha256=$priorL2Hash}
            throw 'Finalizer cannot claim nested L2 absence from host-only inventory.'
        }
        if($hostExclusion.present){throw 'Same-name host resource remains; preserved without adoption or mutation.'}
    } catch {
        $result.status='BLOCKED'; $result.l2Error=Get-SafeError $_; Add-SecondaryError "L2 terminal check: $($result.l2Error)"
        if(-not $result.l2Observatio