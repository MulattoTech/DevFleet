[CmdletBinding()]
param([string]$Workspace = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$env:PYTHONDONTWRITEBYTECODE = '1'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
Import-Module (Join-Path $Workspace 'tools\PythonRuntime.psm1') -Force
Import-Module (Join-Path $Workspace 'automation\release-e2e\modules\Candidate.psm1') -Force
$python = Resolve-DevFleetPython -Workspace $Workspace
$statePath = Join-Path $Workspace 'finalization-state.json'
$finalPath = Join-Path $Workspace 'evidence\FINAL-ACCEPTANCE.json'
$pendingFinalPath = "$finalPath.$([guid]::NewGuid().ToString('N')).pending"

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required JSON is missing: $Path" }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}
function Write-AtomicJson([string]$Path,$Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,(($Value | ConvertTo-Json -Depth 50) + [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
function Set-Field($Object,[string]$Name,$Value) {
    if ($Object.PSObject.Properties.Name -contains $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}
function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

try {
    # This validator closes FullRelease, U01-U05, standard-token, proofs,
    # cleanup/live terminal records, and the distinct immutable RELEASE audit.
    $validator = Join-Path $Workspace 'tools\validate_release_bundle.py'
    $validationOutput = @(& $python $validator --workspace-root $Workspace --check pre-acceptance 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "PRE_ACCEPTANCE_VALIDATION_FAILED: $($validationOutput -join "`n")" }
    try { $validated = ($validationOutput -join "`n") | ConvertFrom-Json } catch { throw 'PRE_ACCEPTANCE_VALIDATOR_OUTPUT_INVALID' }
    if ([string]$validated.status -ne 'PASS' -or [bool]$validated.releaseEligible -or [bool]$validated.internalPromotionAllowed) { throw 'PRE_ACCEPTANCE_VALIDATOR_GRANTED_PROMOTION' }

    $state = Read-Json $statePath
    $manifest = Read-Json (Join-Path $Workspace 'outputs\final-artifact-hashes.json')
    $release = Read-Json (Join-Path $Workspace 'outputs\release-fingerprint.json')
    $tooling = Read-Json (Join-Path $Workspace 'outputs\tooling-fingerprint-current.json')
    $signing = Read-Json (Join-Path $Workspace 'outputs\SIGNING-PROVIDER.json')
    $authority = Read-Json (Join-Path $Workspace 'evidence\CURRENT-RELEASE-AUTHORITY.json')
    $handoff = Read-Json (Join-Path $Workspace 'audit\NEXT-CODEX-HANDOFF.json')
    $expected = $validated.candidateTuple
    $head = (& git -C $Workspace rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -cne [string]$expected.repositoryHead) { throw 'REPOSITORY_HEAD_CHANGED_AFTER_CERTIFICATION' }

    $identityArguments = @('--workspace',$Workspace,'--candidate-commit',[string]$expected.candidateCommit)
    foreach ($artifactName in @('exe','tar','portable','installerSource')) {
        $artifactRow = @($manifest.artifacts | Where-Object { [string]$_.name -ceq $artifactName })
        if ($artifactRow.Count -ne 1) { throw "ARTIFACT_MANIFEST_$($artifactName.ToUpperInvariant())_CARDINALITY" }
        $artifactPath = Join-Path $Workspace ([string]$artifactRow[0].path)
        $identityArguments += @('--artifact',"$artifactName=$artifactPath")
    }
    $identityOutput = @(& $python (Join-Path $Workspace 'tools\compute_shipping_input_identity.py') @identityArguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'LIVE_CANDIDATE_IDENTITY_RECOMPUTE_FAILED' }
    try { $identity = ($identityOutput -join "`n") | ConvertFrom-Json } catch { throw 'LIVE_CANDIDATE_IDENTITY_OUTPUT_INVALID' }
    $shippingExact = [string]$identity.liveShippingInputIdentity -ceq [string]$expected.shippingInputIdentity
    $canonicalEolOnly = [bool]$identity.crlfOnlyMaterialization -and [string]$identity.candidateShippingInputIdentity -ceq [string]$expected.shippingInputIdentity
    if (-not $shippingExact -and -not $canonicalEolOnly) { throw 'LIVE_SHIPPING_INPUTS_DIFFER_FROM_SIGNED_CANDIDATE' }
    $observedRelease = if ($shippingExact) { [string]$identity.liveReleaseFingerprintId } else { [string]$identity.candidateReleaseFingerprintId }
    if ($observedRelease -cne [string]$expected.releaseFingerprintId) { throw 'LIVE_RELEASE_FINGERPRINT_CHANGED' }
    if ([string]$identity.liveToolingFingerprint.toolingFingerprintId -cne [string]$expected.toolingFingerprintId) { throw 'LIVE_TOOLING_FINGERPRINT_CHANGED' }
    if ([string]$manifest.candidateGitCommit -cne [string]$expected.candidateCommit -or [string]$manifest.shippingInputIdentity -cne [string]$expected.shippingInputIdentity -or [string]$manifest.releaseFingerprintId -cne [string]$expected.releaseFingerprintId -or [string]$manifest.toolingFingerprintId -cne [string]$expected.toolingFingerprintId) { throw 'ARTIFACT_MANIFEST_TUPLE_MISMATCH' }
    if ([string]$release.releaseFingerprintId -cne [string]$expected.releaseFingerprintId -or [string]$release.toolingFingerprint.toolingFingerprintId -cne [string]$expected.toolingFingerprintId -or [string]$tooling.toolingFingerprintId -cne [string]$expected.toolingFingerprintId) { throw 'RELEASE_TOOLING_FINGERPRINT_RECORD_MISMATCH' }

    $artifactClosure = [ordered]@{}
    foreach ($name in @('exe','tar','portable','installerSource')) {
        $row = @($manifest.artifacts | Where-Object { [string]$_.name -ceq $name })
        if ($row.Count -ne 1) { throw "ARTIFACT_MANIFEST_$($name.ToUpperInvariant())_CARDINALITY" }
        $artifactPath = Join-Path $Workspace ([string]$row[0].path)
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf) -or (Get-Hash $artifactPath) -cne [string]$row[0].sha256 -or [int64](Get-Item -LiteralPath $artifactPath).Length -ne [int64]$row[0].bytes) { throw "SIGNED_ARTIFACT_CHANGED: $name" }
        $validatedArtifact = $validated.artifacts.$name
        if ([string]$validatedArtifact.sha256 -cne [string]$row[0].sha256 -or [int64]$validatedArtifact.bytes -ne [int64]$row[0].bytes) { throw "VALIDATED_ARTIFACT_TUPLE_MISMATCH: $name" }
        $artifactClosure[$name] = [ordered]@{sha256=[string]$row[0].sha256;bytes=[int64]$row[0].bytes}
    }

    $certificatePath = Join-Path $Workspace ([string]$manifest.publicCertificate.path)
    if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf) -or (Get-Hash $certificatePath) -cne [string]$manifest.publicCertificate.sha256 -or [int64](Get-Item $certificatePath).Length -ne [int64]$manifest.publicCertificate.bytes) { throw 'PUBLIC_SIGNING_CERTIFICATE_CHANGED' }
    $exeRow = @($manifest.artifacts | Where-Object name -ceq 'exe')[0]
    $signature = Test-PrivateAuthenticodeSignature -Path (Join-Path $Workspace ([string]$exeRow.path)) -PublicCertificatePath $certificatePath -ExpectedThumbprint ([string]$signing.signerThumbprint)
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
    $rsa = $null
    try {
        $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
        if (-not $rsa -or $rsa.KeySize -ne 3072) { throw 'SIGNING_CERTIFICATE_RSA_SIZE_MISMATCH' }
        if ([string]$certificate.Subject -cne [string]$signing.signerSubject -or [string]$certificate.Thumbprint -cne [string]$signing.signerThumbprint) { throw 'SIGNING_CERTIFICATE_IDENTITY_MISMATCH' }
    } finally { if ($rsa) { $rsa.Dispose() }; $certificate.Dispose() }
    if ([string]$signature.status -ne 'PASS' -or [string]$signature.effectiveSignatureStatus -ne 'Valid' -or -not [bool]$signature.exactCertificateMatch -or -not [bool]$signature.codeSigningEkuVerified -or [bool]$signature.trustStoreMutated -or [bool]$signature.publicPublisherTrust) { throw 'AUTHENTICODE_REVALIDATION_FAILED' }
    if (-not [bool]$signing.codeSigningEkuVerified -or [string]$signing.codeSigningEku -cne '1.3.6.1.5.5.7.3.3' -or [int]$signing.rsaBits -ne 3072 -or [bool]$signing.privateKeyExportable -or [bool]$signing.privateKeyExported -or [bool]$signing.publicPublisherTrust -or [bool]$signing.publicPromotionAllowed) { throw 'SIGNING_PROVIDER_CONTRACT_UNSAFE' }

    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) { throw 'HYPERV_LIVE_STATE_UNAVAILABLE' }
    $liveVms = @(Get-VM -ErrorAction Stop)
    $l1 = @($liveVms | Where-Object { [string]$_.Id -ceq '84b7d8b8-ee6c-4085-aa29-4b0adc316de2' })
    if ($l1.Count -ne 1 -or [string]$l1[0].Name -cne 'DevFleet-E2E-Win11-01' -or [string]$l1[0].State -cne 'Off') { throw 'LIVE_L1_NOT_EXACT_GUID_NAME_OFF' }
    if (@($liveVms | Where-Object { [string]$_.Name -ceq 'DevFleet-E2E-Linux-01' }).Count -ne 0) { throw 'LIVE_L2_NOT_ABSENT' }

    if (-not [bool]$state.production_safety.production_unchanged -or [bool]$state.production_safety.mulattotechsurface_touched -or [string]$state.production_safety.scope -notmatch '(?i)disposable') { throw 'PRODUCTION_SAFETY_INVARIANT_FAILED' }
    if ([bool]$authority.f005.attempted -or [bool]$authority.f005.formatterOnlyAuditCleanupPerformed -or [bool]$authority.f005.structuralRefactoringPerformed) { throw 'F005_WAS_ATTEMPTED_OR_PERFORMED' }
    $handoffHead = if ($handoff.repository -and $handoff.repository.head) { [string]$handoff.repository.head } else { [string]$handoff.repositoryHead }
    $handoffTooling = if ($handoff.candidate -and $handoff.candidate.toolingFingerprintId) { [string]$handoff.candidate.toolingFingerprintId } else { [string]$handoff.toolingFingerprintId }
    if ($handoffHead -cne [string]$expected.repositoryHead -or $handoffTooling -cne [string]$expected.toolingFingerprintId) { throw 'SAFETY_HANDOFF_TUPLE_IS_STALE' }
    foreach ($name in @('protectedProductionMutated','hostRebooted','amdRadeonTouched','biosUefiTouched','mulattoTechSurfaceTouched','githubPushed','privateSigningKeyExported')) {
        if ($handoff.safety.$name -isnot [bool] -or [bool]$handoff.safety.$name) { throw "SAFETY_FLAG_UNSAFE_OR_MISSING: $name" }
    }

    $releaseAudit = $validated.releaseAudit
    $final = [ordered]@{
        schemaVersion=1; contract='devfleet-internal-final-acceptance-v1'; generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
        status='PASS'; releaseEligible=$true; internalPromotionAllowed=$true; publicPromotionAllowed=$false; publicPublisherTrust=$false
        candidate=[ordered]@{
            repositoryHead=[string]$expected.repositoryHead; candidateCommit=[string]$expected.candidateCommit
            shippingInputIdentity=[string]$expected.shippingInputIdentity; releaseFingerprintId=[string]$expected.releaseFingerprintId; toolingFingerprintId=[string]$expected.toolingFingerprintId
            artifacts=$artifactClosure
            authenticode=[ordered]@{status='PASS';signatureStatus='Valid';signerThumbprint=[string]$signing.signerThumbprint;signerSubject=[string]$signing.signerSubject;codeSigningEkuVerified=$true;rsaBits=3072;exactCertificateMatch=$true;privateKeyExported=$false}
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
