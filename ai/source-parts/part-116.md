# DevFleet source part 116

Full-source UTF-8 byte interval [5347500, 5394000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8f028bffebe0a5331ff1813c3e988e056f6340220663d4cc893c19b6293de928

<!-- BEGIN SOURCE SLICE -->
[ordered]@{workspacePath="$auditWorkspacePrefix/$immutableManifestName";bundlePath="$auditBundlePrefix/$immutableManifestName";bytes=[int64](Get-Item $manifestImmutable).Length;sha256=(Get-Hash $manifestImmutable)}
                releaseValidation=[ordered]@{workspacePath="$auditWorkspacePrefix/$preValidationName";bundlePath="$auditBundlePrefix/$preValidationName";bytes=[int64](Get-Item $validationImmutable).Length;sha256=(Get-Hash $validationImmutable)}
            }
            checks=[ordered]@{cleanExtraction='PASS';secrets='PASS';coherence='PASS';sourceCount='PASS';releaseValidation='PASS'}
            gates=[ordered]@{candidate='PASS';proofs='2/2 PASS';fullRelease='PASS';realUseAcceptance='U01-U05 PASS';maintenance='5/5 PASS';standardToken='PASS';reconcile='PASS';cleanup='PASS';l1='OFF';l2='ABSENT';releaseAudit='PASS'}
        }
        Write-AtomicJson (Join-Path $Workspace 'evidence\CURRENT-RELEASE-AUDIT.json') $releaseAuditPointer
    }
    # The outer sidecar is the final filesystem write after all ZIP and
    # manifest validation. The ZIP is never modified after this point.
    @("PATH: $([IO.Path]::GetFullPath($zipPath))","BYTES: $zipBytes","SHA-256: $zipSha") | Set-Content -LiteralPath $sidecarPath -Encoding UTF8
    [pscustomobject]@{path=$zipPath;bytes=$zipBytes;sha256=$zipSha;expectedSourceCount=$inventory.Count;includedSourceCount=$inventory.Count;status=$status;selfTest=$selfTestStatus} | ConvertTo-Json -Depth 8
}
finally {
    if ($releaseAuditStage -and (Test-Path -LiteralPath $releaseAuditStage)) {
        $resolvedAuditStage=[IO.Path]::GetFullPath($releaseAuditStage)
        $resolvedAuditParent=[IO.Path]::GetFullPath((Join-Path $Audit 'release-audits')).TrimEnd('\','/')
        if ((Split-Path -Parent $resolvedAuditStage) -cne $resolvedAuditParent -or (Split-Path -Leaf $resolvedAuditStage) -cnotmatch '^\.release-audit-[A-Za-z0-9-]+\.[0-9a-f]{32}\.tmp$') { throw 'Release-audit cleanup path escaped its immutable-run parent.' }
        Remove-Item -LiteralPath $resolvedAuditStage -Recurse -Force -ErrorAction SilentlyContinue
    }
    $resolvedStage=[IO.Path]::GetFullPath($stage)
    $tempParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
    if((Split-Path -Parent $resolvedStage) -cne $tempParent -or (Split-Path -Leaf $resolvedStage) -cnotmatch '^DevFleet AI Audit bundle [0-9a-f]{32}$'){throw 'Audit cleanup path escaped its owned temporary parent.'}
    foreach($cleanupPath in @($tempParent,$resolvedStage)){
        if((Test-Path -LiteralPath $cleanupPath) -and ((Get-Item -LiteralPath $cleanupPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Audit cleanup path is a reparse point.'}
    }
    if (Test-Path -LiteralPath $resolvedStage) { Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction SilentlyContinue }
}

```


## FILE: tools/Build-ChatGPT-AuditBundle.ps1

SHA256: 6b122224f06cdf7baaba463372aea1ae686dbce43489d9c3f8647a4d8390a393 | Bytes: 350 | Git mode: 100644

```
[CmdletBinding()]
param([string]$Workspace = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
Write-Warning 'Build-ChatGPT-AuditBundle.ps1 is deprecated; it now delegates to the universal AI audit bundle.'
& (Join-Path $PSScriptRoot 'Build-AIAuditBundle.ps1') -Workspace $Workspace
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

```


## FILE: tools/Complete-DevFleetInternalAcceptance.ps1

SHA256: 5310a03dd6251268e8bf6a76dabf074bc4ad91d1f47586b928bb15e620fdd849 | Bytes: 17249 | Git mode: 100644

```
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
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($byte