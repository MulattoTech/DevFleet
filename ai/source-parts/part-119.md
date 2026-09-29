# DevFleet source part 119

Full-source UTF-8 byte interval [5487000, 5533500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: f8741ddd0e230e440d6a9c3b5bf7957cef1e9562ca07019e58a173021441e348

<!-- BEGIN SOURCE SLICE -->
n){$result.l2State='UNVERIFIED';$result.l2ExactAbsent=$false;$result.l2Observation=[ordered]@{schemaVersion=2;expectedName=$L2Name;status='UNVERIFIED';present=$null;verificationMethod='Nested L2 terminal observation could not be validated';ownershipScope='exact expected nested L2 name inside exact disposable L1';evidenceClass='finalizer observation; non-certifying'}}
    }
    return $result
}

function Invoke-CanonicalAuditBundle {
    $builder=Join-Path $Workspace 'tools\Build-AIAuditBundle.ps1'
    if (-not(Test-Path -LiteralPath $builder -PathType Leaf)){throw "Canonical audit builder is missing: $builder"}
    $builderOutput=@(& (Get-Command pwsh.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $builder -Workspace $Workspace 2>&1)
    if($LASTEXITCODE -ne 0){throw "Canonical audit builder failed: $($builderOutput -join [Environment]::NewLine)"}
    if(-not(Test-Path -LiteralPath $zipPath -PathType Leaf)){throw 'Canonical audit builder returned without an audit ZIP.'}
    $zipHash=Get-FileSha256 $zipPath; $zipBytes=[int64](Get-Item -LiteralPath $zipPath).Length
    $validator=Join-Path $Workspace 'source\tools\validate_ai_audit_bundle.py'; $mode=if($finalizerStatus -eq 'PASS'){'release'}else{'diagnostic'}
    $validation=@(& python $validator --archive $zipPath --mode $mode 2>&1)
    if($LASTEXITCODE -ne 0){throw "Audit ZIP $mode validation failed: $($validation -join [Environment]::NewLine)"}
    $result=try{($validation -join "`n")|ConvertFrom-Json}catch{throw "Audit ZIP validator did not return JSON: $($_.Exception.Message)"}
    if($mode -eq 'diagnostic' -and [bool]$result.releaseEligible){throw 'Diagnostic audit ZIP was incorrectly marked release eligible.'}
    # No ZIP write occurs after this point. The sidecar is deliberately last.
    @("PATH: $([IO.Path]::GetFullPath($zipPath))","BYTES: $zipBytes","SHA-256: $zipHash")|Set-Content -LiteralPath $sidecarPath -Encoding UTF8
    [ordered]@{path=$zipPath;bytes=$zipBytes;sha256=$zipHash;sidecar=$sidecarPath;mode=$mode;validation=$result}
}

try {
    if($StageScript){if(-not(Test-Path -LiteralPath $StageScript -PathType Leaf)){throw "Stage script is missing: $StageScript"};$stageResult=@(& $StageScript @StageArgumentList);if($LASTEXITCODE -ne 0){throw "Stage exited with code $LASTEXITCODE."}}
    $finalizerStatus=if($TerminalMode -eq 'PASS'){'PASS'}elseif($TerminalMode -eq 'BLOCKED'){'BLOCKED'}elseif($PrimaryBlocker){'BLOCKED'}else{'PASS'}
} catch {
    $stageError=$_;if(-not $PrimaryBlocker){$PrimaryBlocker=Get-SafeError $_};$finalizerStatus='BLOCKED'
} finally {
    try {
        New-Item -ItemType Directory -Force -Path $audit,$evidence,$outputs|Out-Null
        # Durable interactive cleanup is performed before the touched L1 force-stop
        # inside Invoke-ExactTerminalCleanup. Do not reconnect after power-off.
    } catch { Add-SecondaryError "Interactive cleanup: $(Get-SafeError $_)" }
    try {
        $terminal=Invoke-ExactTerminalCleanup
        Write-AtomicJson (Join-Path $evidence 'FINALIZER-TERMINAL-STATE.json') $terminal
        if($terminal.l1Observation){Write-AtomicJson (Join-Path $evidence 'l1-terminal-state.json') $terminal.l1Observation}
        if($terminal.l2Observation){Write-AtomicJson (Join-Path $evidence 'l2-terminal-state.json') $terminal.l2Observation}
        $interactivePath=Join-Path $evidence 'CURRENT-INTERACTIVE-LOGIN.json'
        if(Test-Path -LiteralPath $interactivePath -PathType Leaf){
            $interactive=Get-Content -LiteralPath $interactivePath -Raw|ConvertFrom-Json -AsHashtable
            if($terminal.l1Observation){$interactive.finalL1=$terminal.l1Observation.state}
            if($terminal.l2Observation){
                $interactive.finalL2=if([string]$terminal.l2Observation.status -ceq 'ABSENT' -and $terminal.l2Observation.present -eq $false){'ABSENT'}elseif($terminal.l2Observation.present -eq $true){'PRESENT'}else{'UNVERIFIED'}
            }
            Write-AtomicJson $interactivePath $interactive
        }
        $terminalOutcome=Merge-FinalizerTerminalOutcome -CurrentStatus $finalizerStatus -PrimaryBlocker $PrimaryBlocker -PrimaryBlockerClassification $PrimaryBlockerClassification -SecondaryErrors @($secondaryErrors) -Terminal $terminal
        $finalizerStatus=$terminalOutcome.status;$PrimaryBlocker=$terminalOutcome.primaryBlocker;$PrimaryBlockerClassification=$terminalOutcome.primaryBlockerClassification
        $secondaryErrors.Clear();foreach($message in @($terminalOutcome.secondaryErrors)){Add-SecondaryError $message}
    }catch{
        $finalizerStatus='BLOCKED'
        $terminalError=Get-SafeError $_
        if(-not $PrimaryBlocker){$PrimaryBlocker=$terminalError;$PrimaryBlockerClassification='BLOCKED — FINALIZER TERMINAL EVIDENCE'}else{Add-SecondaryError "Terminal cleanup: $terminalError"}
        Add-SecondaryError "Terminal cleanup publication: $terminalError"
    }
    try { $safePrimary=if($PrimaryBlocker){Get-SafeError $PrimaryBlocker}else{$null};Write-PrimaryRecord $finalizerStatus $PrimaryBlockerClassification $safePrimary @($secondaryErrors) } catch { Add-SecondaryError "Primary blocker record: $(Get-SafeError $_)" }
    try {
        $statePath=Join-Path $Workspace 'finalization-state.json'
        if(Test-Path -LiteralPath $statePath -PathType Leaf){
            $stateBeforeRefresh=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
            if(-not [bool]$stateBeforeRefresh.full_release_passed -and (Test-CandidateEvidenceRefreshRequired -State $stateBeforeRefresh)){
                $candidateBinder=Join-Path $Workspace 'tools\Finalize-CandidateEvidence.ps1'
                $bindOutput=@(& (Get-Command pwsh.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $candidateBinder -Workspace $Workspace 2>&1)
                if($LASTEXITCODE -ne 0){throw "Current tooling fingerprint refresh failed: $($bindOutput -join [Environment]::NewLine)"}
            }
        }
        # A tooling-only commit advances the live tooling tuple without
        # invalidating shipping bytes. Before rebuilding the diagnostic
        # authority, bind the live non-shipping tuple when no release is
        # currently promoted; a promoted release remains immutable.
        $statePath=Join-Path $Workspace 'finalization-state.json'
        if(Test-Path -LiteralPath $statePath -PathType Leaf){
            $stateForAuthority=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
            if(-not [bool]$stateForAuthority.full_release_passed){
                $stateForAuthority.working_tree_tooling_fingerprint_id=[string]$stateForAuthority.toolingFingerprintId
                $stateForAuthority.working_tree_shipping_input_identity=[string]$stateForAuthority.shipping_input_identity
                Write-AtomicJson $statePath $stateForAuthority
            }
        }
        $authorityUpdater=Join-Path $Workspace 'tools\Update-CurrentReleaseAuthority.ps1';$updateArgs=@('-Workspace',$Workspace)
        if(-not[string]::IsNullOrWhiteSpace($RunId)){$updateArgs+=@('-FullReleaseRunId',$RunId)}
        if($PrimaryBlocker){$classification=if($PrimaryBlockerClassification){$PrimaryBlockerClassification}else{'BLOCKED — FINALIZER'};$updateArgs+=@('-TerminalBlocker',(Get-SafeError $PrimaryBlocker),'-TerminalBlockerClassification',$classification)}
        # Isolate the updater exit from expected nonzero nested acceptance checks.
        $authorityOutput=@(& (Get-Command pwsh.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -File $authorityUpdater @updateArgs 2>&1)
        if($LASTEXITCODE -ne 0){throw 'Current authority refresh failed.'}
    } catch {
        $authorityFailure='Current authority refresh failed.'
        if(-not $PrimaryBlocker){$PrimaryBlocker=$authorityFailure;$PrimaryBlockerClassification='BLOCKED — AUTHORITY REFRESH'}else{Add-SecondaryError "Authority refresh: $(Get-SafeError $_)"}
        $finalizerStatus='BLOCKED'
        try {$safePrimary=Get-SafeError $PrimaryBlocker;Write-PrimaryRecord $finalizerStatus $PrimaryBlockerClassification $safePrimary @($secondaryErrors)}catch{Add-SecondaryError "Primary blocker record: $(Get-SafeError $_)"}
    }
    try {
        $diff=@(& git -C $Workspace diff --check 2>&1)
        if($LASTEXITCODE -ne 0){if(-not $PrimaryBlocker){$PrimaryBlocker='Repository diff contains whitespace errors.';$PrimaryBlockerClassification='BLOCKED — WORKTREE VALIDATION'}else{Add-SecondaryError "git diff --check: $($diff -join [Environment]::NewLine)"};$finalizerStatus='BLOCKED'}
    }catch{if(-not $PrimaryBlocker){$PrimaryBlocker='Repository diff validation failed.';$PrimaryBlockerClassification='BLOCKED — WORKTREE VALIDATION'}else{Add-SecondaryError "git diff --check: $(Get-SafeError $_)"};$finalizerStatus='BLOCKED'}
    try {$bundle=Invoke-CanonicalAuditBundle}catch{
        $bundle=$null
        if(-not $PrimaryBlocker){$PrimaryBlocker='Canonical audit bundle validation or finalization failed.';$PrimaryBlockerClassification='BLOCKED — AUDIT BUNDLE FINALIZATION'}else{Add-SecondaryError "AUDIT_BUNDLE_FINALIZATION_FAILURE: $(Get-SafeError $_)"}
        $finalizerStatus='BLOCKED'
        try {$safePrimary=Get-SafeError $PrimaryBlocker;Write-PrimaryRecord $finalizerStatus $PrimaryBlockerClassification $safePrimary @($secondaryErrors)}catch{Add-SecondaryError "Primary blocker record: $(Get-SafeError $_)"}
    }
    try {
        $statePath=Join-Path $Workspace 'finalization-state.json'
        if(Test-Path -LiteralPath $statePath -PathType Leaf){$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable;$state.finalizer_primary_blocker=if($PrimaryBlocker){Get-SafeError $PrimaryBlocker}else{$null};$state.finalizer_secondary_blockers=@($secondaryErrors);$state.audit_bundle_finalization_status=if($bundle){'PASS'}else{'BLOCKED'};$state.audit_bundle_path=if($bundle){$bundle.path}else{$null};$state.audit_bundle_sha256=if($bundle){$bundle.sha256}else{$null};$state.finalizer_completed_utc=(Get-Date).ToUniversalTime().ToString('o');Write-AtomicJson $statePath $state}
    }catch{Add-SecondaryError "Finalization state update: $(Get-SafeError $_)"}
}

[ordered]@{status=$finalizerStatus;primaryBlocker=if($PrimaryBlocker){Get-SafeError $PrimaryBlocker}else{$null};secondaryBlockers=@($secondaryErrors);stageOutput=$stageResult;auditBundle=$bundle}|ConvertTo-Json -Depth 20
if($stageError){throw $stageError}
if([string]$finalizerStatus -cne 'PASS'){throw 'Final convergence remained BLOCKED because the primary stage or exact terminal evidence did not establish a safe PASS.'}

```


## FILE: tools/PythonRuntime.psm1

SHA256: 7b549bdaa54e822dc1875dbb75cbda8b610aed67a3ba4ed85a75879d87aade1d | Bytes: 1235 | Git mode: 100644

```
Set-StrictMode -Version Latest

function Resolve-DevFleetPython {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace)
    $root = (Resolve-Path -LiteralPath $Workspace).Path
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in @('.venv-test\Scripts\python.exe','source\.venv-test\Scripts\python.exe','source\.venv-test-win\Scripts\python.exe')) {
        [void]$candidates.Add((Join-Path $root $relative))
    }
    foreach ($name in @('python.exe','python')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command -and $command.Source) { [void]$candidates.Add([string]$command.Source) }
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $version = @(& $candidate --version 2>&1)
            if ($LASTEXITCODE -eq 0 -and ($version -join ' ') -match '^Python 3\.') { return (Resolve-Path -LiteralPath $candidate).Path }
        } catch { }
    }
    throw 'No working repository-local or PATH Python 3 runtime is available.'
}

Export-ModuleMember -Function Resolve-DevFleetPython

```


## FILE: tools/Test-FinalizerAuthorityExitBoundary.ps1

SHA256: 79bbec96d0e6f0db06d446c83d009230502c5ef01f7ab1b6be10fc3d941fd574 | Bytes: 3090 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$text=Get-Content (Join-Path $WorkspaceRoot 'tools/Invoke-DevFleetFinalConvergence.ps1') -Raw
$start=$text.IndexOf('$authorityUpdater=Join-Path')
$end=$text.IndexOf('    } catch { Add-SecondaryError "Authority refresh:', $start)
if($start -lt 0 -or $end -le $start){throw 'Native authority call boundary not found'}
$handler=[scriptblock]::Create($text.Substring($start,$end-$start))
$root=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-authority-exit-'+[guid]::NewGuid().ToString('N'))
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$checks.Add([pscustomobject]@{name=$Name;pass=$Pass})}
function Get-SafeError([object]$Value){[string]$Value}
try {
    New-Item -ItemType Directory -Path (Join-Path $root 'tools') -Force|Out-Null
    $fixture=@'
param($Workspace,$TerminalBlocker,$TerminalBlockerClassification)
$ErrorActionPreference='Stop'
$mode=Get-Content (Join-Path $Workspace 'mode.txt')
if($mode -eq 'throws'){throw 'Fixture authority write rejected'}
if($mode -eq 'native-nonzero'){& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -NonInteractive -Command 'exit 37'}
[ordered]@{workspace=$Workspace;blocker=$TerminalBlocker;classification=$TerminalBlockerClassification;nativeExit=$LASTEXITCODE}|ConvertTo-Json|Set-Content (Join-Path $Workspace 'receipt.json')
'completed updater without terminating error'
'@
    Set-Content (Join-Path $root 'tools/Update-CurrentReleaseAuthority.ps1') $fixture -Encoding utf8
    foreach($mode in @('native-nonzero','inherited-nonzero','throws')){
        Set-Content (Join-Path $root 'mode.txt') $mode -Encoding utf8
        Remove-Item (Join-Path $root 'receipt.json') -ErrorAction SilentlyContinue
        $Workspace=$root;$PrimaryBlocker='EXACT PROOF NOT OBSERVED; fixture';$PrimaryBlockerClassification='BLOCKED - FIXTURE'
        $LASTEXITCODE=37;$caught=$null
        try { & $handler|Out-Null } catch {$caught=$_.Exception.Message}
        $receipt=Join-Path $root 'receipt.json'
        if($mode -eq 'throws'){
            Check 'actual updater exception remains failure' ([bool]$caught)
            Check 'failed updater did not manufacture receipt' (-not(Test-Path $receipt))
        }else{
            Check ($mode+': successful updater accepted') (-not $caught)
            Check ($mode+': updater actually executed') (Test-Path $receipt)
            if(Test-Path $receipt){$j=Get-Content $receipt -Raw|ConvertFrom-Json;Check ($mode+': argument values preserved') ($j.workspace -eq $Workspace -and $j.blocker -eq $PrimaryBlocker -and $j.classification -eq $PrimaryBlockerClassification)}
        }
    }
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
$failed=@($checks|Where-Object {-not $_.pass})
[ordered]@{scope='VM_FREE_NATIVE_FINALIZER_CALL_BOUNDARY';releaseCredit=$false;status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;checks=@($checks)}|ConvertTo-Json -Depth 6
if($failed.Count){exit 1}

```


## FILE: tools/Update-CurrentReleaseAuthority.ps1

SHA256: 179bbdd0b389cc521cb59e156334bfaa9e0617a8416d1f8cde82267f99e07903 | Bytes: 37062 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$Workspace = (Split-Path -Parent $PSScriptRoot),
    [string]$CurrentProofRunId,
    [string]$FullReleaseRunId,
    [string]$TerminalBlocker,
    [string]$TerminalBlockerClassification
)

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
Import-Module (Join-Path $PSScriptRoot 'AuthorityTime.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PythonRuntime.psm1') -Force
$python = Resolve-DevFleetPython -Workspace $Workspace
$outputs = Join-Path $Workspace 'outputs'
$audit = Join-Path $Workspace 'audit'
$evidence = Join-Path $Workspace 'evidence'
$runRoot = Join-Path $audit 'automation-harness\runs'

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}
function Write-AtomicJson([string]$Path,$Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,(($Value | ConvertTo-Json -Depth 40) + [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
function Write-AtomicText([string]$Path,[string]$Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,$Value,[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
function Get-StringHash([string]$Value) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}
function Get-FirstProperty($Value,[string[]]$Names) {
    if ($null -eq $Value) { return $null }
    foreach ($name in $Names) {
        if ($Value -is [Collections.IDictionary] -and $Value.Contains($name)) { return $Value[$name] }
        if ($Value.PSObject.Properties.Name -contains $name) { return $Value.$name }
    }
    return $null
}
function Get-NewestJson([string]$Root,[string]$Name) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $null }
    $file = Get-ChildItem -LiteralPath $Root -Filter $Name -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $file) { return $null }
    try { return [ordered]@{value=(Read-Json $file.FullName);relativePath=$file.FullName.Substring($Workspace.Length).TrimStart('\','/').Replace('\','/');lastWriteUtc=$file.LastWriteTimeUtc.ToString('o')} }
    catch { return [ordered]@{value=$null;relativePath=$file.FullName.Substring($Workspace.Length).TrimStart('\','/').Replace('\','/');lastWriteUtc=$file.LastWriteTimeUtc.ToString('o');readError='JSON_UNREADABLE'} }
}

New-Item -ItemType Directory -Force -Path $audit,$evidence | Out-Null
$statePath = Join-Path $Workspace 'finalization-state.json'
$manifestPath = Join-Path $outputs 'final-artifact-hashes.json'
$releasePath = Join-Path $outputs 'release-fingerprint.json'
$toolingPath = Join-Path $outputs 'tooling-fingerprint-current.json'
$state = Read-Json $statePath
$manifest = Read-Json $manifestPath
$release = Read-Json $releasePath
$tooling = Read-Json $toolingPath
if (-not $state -or -not $manifest -or -not $release -or -not $tooling) { throw 'Current release authority inputs are incomplete.' }

$head = (& git -C $Workspace rev-parse HEAD).Trim()
$branch = (& git -C $Workspace branch --show-current).Trim()
$candidateCommit = [string](Get-FirstProperty $state @('candidate_git_commit','candidateGitCommit','candidateCommit'))
$shippingIdentity = [string](Get-FirstProperty $state @('shipping_input_identity','shippingInputIdentity'))
$releaseId = [string]$state.releaseFingerprintId
$toolingId = [string]$state.toolingFingerprintId
if ($head -notmatch '^[0-9a-f]{40}$' -or $candidateCommit -notmatch '^[0-9a-f]{40}$' -or $shippingIdentity -notmatch '^[0-9a-f]{64}$' -or $releaseId -notmatch '^[0-9a-f]{64}$' -or $toolingId -notmatch '^[0-9a-f]{64}$') { throw 'Current release authority identity tuple is malformed.' }
if ([string]$manifest.candidateGitCommit -cne $candidateCommit -or [string]$manifest.shippingInputIdentity -cne $shippingIdentity -or [string]$manifest.releaseFingerprintId -cne $releaseId -or [string]$manifest.toolingFingerprintId -cne $toolingId) { throw 'Artifact manifest disagrees with finalization authority.' }
if ([string]$release.releaseFingerprintId -cne $releaseId -or [string]$release.toolingFingerprint.toolingFingerprintId -cne $toolingId -or [string]$tooling.releaseFingerprintId -cne $releaseId -or [string]$tooling.toolingFingerprintId -cne $toolingId) { throw 'Release/tooling fingerprint records disagree with finalization authority.' }
$candidateRows = @($release.shippingInputs)
if (-not $candidateRows.Count) { throw 'Candidate-bound release fingerprint contains no shipping rows.' }

# The durable candidate authority must invalidate itself when the live shipping
# tree no longer matches the candidate-bound identity. This catches a new
# shipping commit or an uncommitted shipping edit before any newer proof prose
# can be mistaken for evidence for the old binary.
$identityTool = Join-Path $Workspace 'tools\compute_shipping_input_identity.py'
$identityJson = & $python $identityTool --workspace $Workspace --candidate-commit $candidateCommit | Select-Object -Last 1
if ($LASTEXITCODE) { throw 'Current shipping input identity could not be recomputed for authority refresh.' }
$identity = $identityJson | ConvertFrom-Json
$liveShippingIdentity = [string]$identity.liveShippingInputIdentity
if ($liveShippingIdentity -notmatch '^[0-9a-f]{64}$') { throw 'Live shipping input identity is malformed during authority refresh.' }
$substantiveShippingDrift = $liveShippingIdentity -cne $shippingIdentity -and -not [bool]$identity.crlfOnlyMaterialization
if ($substantiveShippingDrift) {
    $state.candidate_is_current = $false
    $state.source_identity_matches_candidate = $false
    $state.source_changed_since_candidate = $true
    $state.rebuild_required = $true
    $state.validation_evidence_current = $false
    $state.full_release_passed = $false
    $state.internal_promotion_allowed = $false
    $state.release_status = 'BLOCKED'
    $state.status = 'BLOCKED — CANDIDATE INVALIDATED / REBUILD REQUIRED'
    $state.current_phase = 'candidate-invalidated-rebuild-required'
    $invalidationReason = "Live shipping input identity $liveShippingIdentity differs from candidate-bound identity $shippingIdentity."
    if ($state.PSObject.Properties.Name -contains 'candidate_invalidation_reason') { $state.candidate_invalidation_reason = $invalidationReason }
    else { $state | Add-Member -NotePropertyName candidate_invalidation_reason -NotePropertyValue $invalidationReason }
    Write-AtomicJson $statePath $state
    $state = Read-Json $statePath
}

# Promotion state is derived from the independently revalidated immutable
# FINAL-ACCEPTANCE record. Mutable booleans in finalization-state.json are
# outputs/cache only and never promotion inputs.
$finalAcceptanceValid = $false
$finalAcceptance = $null
$finalAcceptanceBlocker = 'FINAL-ACCEPTANCE.json is missing or not current.'
$finalValidator = Join-Path $Workspace 'tools\validate_release_bundle.py'
$finalValidationOutput = @(& $python $finalValidator --workspace-root $Workspace --check final-acceptance 2>&1)
if ($LASTEXITCODE -eq 0) {
    try { $finalAcceptance = ($finalValidationOutput -join "`n") | ConvertFrom-Json } catch { $finalAcceptance = $null }
    $finalAcceptanceValid = $null -ne $finalAcceptance -and [string]$finalAcceptance.status -eq 'PASS' -and [bool]$finalAcceptance.internalPromotionAllowed -and -not [bool]$finalAcceptance.publicPromotionAllowed
    if (-not $finalAcceptanceValid) { $finalAcceptanceBlocker = 'FINAL-ACCEPTANCE validator did not return an internal-only PASS.' }
} else {
    $finalAcceptanceBlocker = ($finalValidationOutput -join "`n").Trim()
    if (-not $finalAcceptanceBlocker) { $finalAcceptanceBlocker = 'FINAL-ACCEPTANCE validation failed without output.' }
}
if ($TerminalBlocker) { $finalAcceptanceValid = $false }

$candidateFlags = [ordered]@{
    candidateIsCurrent = if($finalAcceptanceValid){$true}else{[bool]$state.candidate_is_current}
    sourceIdentityMatchesCandidate = if($finalAcceptanceValid){$true}else{[bool]$state.source_identity_matches_candidate}
    sourceChangedSinceCandidate = if($finalAcceptanceValid){$false}else{[bool]$state.source_changed_since_candidate}
    rebuildRequired = if($finalAcceptanceValid){$false}else{[bool]$state.rebuild_required}
    candidateBuildCurrent = if($finalAcceptanceValid){$true}else{[bool]$state.candidate_build_current}
    artifactTupleMatchesCandidate = if($finalAcceptanceValid){$true}else{[bool]$state.artifact_tuple_matches_candidate}
    validationEvidenceCurrent = $finalAcceptanceValid
    fullReleasePassed = $finalAcceptanceValid
    internalPromotionAllowed = $finalAcceptanceValid
    publicPromotionAllowed = $false
    publicPublisherTrust = $false
}
$candidateSafe = $candidateFlags.candidateIsCurrent -and $candidateFlags.sourceIdentityMatchesCandidate -and -not $candidateFlags.sourceChangedSinceCandidate -and -not $candidateFlags.rebuildRequired -and $candidateFlags.candidateBuildCurrent -and $candidateFlags.artifactTupleMatchesCandidate
$workingTree = [ordered]@{
    shippingInputIdentity = [string](Get-FirstProperty $state @('working_tree_shipping_input_identity','workingTreeShippingInputIdentity'))
    releaseFingerprintWithHistoricalArtifacts = [string](Get-FirstProperty $state @('working_tree_release_fingerprint_with_historical_artifacts','workingTreeReleaseFingerprintWithHistoricalArtifacts'))
    toolingFingerprintId = [string](Get-FirstProperty $state @('working_tree_tooling_fingerprint_id','workingTreeToolingFingerprintId'))
    preparedTarSha256 = [string](Get-FirstProperty $state @('prepared_tar_sha256','preparedTarSha256'))
    preparedPortableSha256 = [string](Get-FirstProperty $state @('prepared_portable_sha256','preparedPortableSha256'))
}

$artifactByName = [ordered]@{}
foreach ($row in @($manifest.artifacts)) { $artifactByName[[string]$row.name] = $row }
foreach ($required in @('exe','tar','portable','installerSource')) { if (-not $artifactByName.Contains($required)) { throw "Artifact manifest is missing $required." } }
$candidate = [ordered]@{
    schemaVersion=2; generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o'); releaseVersion=[string]$manifest.releaseVersion; installerVersion=[string]$manifest.installerVersion
    repositoryHead=$head; branch=$branch; gitCommit=$candidateCommit; candidateGitCommit=$candidateCommit
    shippingInputIdentity=$shippingIdentity; candidateShippingInputIdentity=$shippingIdentity; releaseFingerprintId=$releaseId; toolingFingerprintId=$toolingId
    candidateShippingInputs=$candidateRows; candidateShippingModeContract=$release.shippingModeContract; shippingModeContract=$release.shippingModeContract
    lineEndingComparison=if($candidateFlags.sourceChangedSinceCandidate){'SUBSTANTIVE'}else{[string]($tooling.lineEndingComparison ?? $manifest.lineEndingComparison ?? 'UNVERIFIED')}; crlfOnlyPaths=if($candidateFlags.sourceChangedSinceCandidate){@()}else{@($tooling.crlfOnlyPaths)}
    candidateIsCurrent=$candidateFlags.candidateIsCurrent; sourceIdentityMatchesCandidate=$candidateFlags.sourceIdentityMatchesCandidate; sourceChangedSinceCandidate=$candidateFlags.sourceChangedSinceCandidate; rebuildRequired=$candidateFlags.rebuildRequired
    candidateBuildCurrent=$candidateFlags.candidateBuildCurrent; artifactTupleMatchesCandidate=$candidateFlags.artifactTupleMatchesCandidate; validationEvidenceCurrent=$candidateFlags.validationEvidenceCurrent; fullReleasePassed=$candidateFlags.fullReleasePassed
    internalPromotionAllowed=$candidateFlags.internalPromotionAllowed; publicPromotionAllowed=$false; publicPublisherTrust=$false
    exeSha256=[string]$artifactByName.exe.sha256; exeBytes=[int64]$artifactByName.exe.bytes; tarSha256=[string]$artifactByName.tar.sha256; tarBytes=[int64]$artifactByName.tar.bytes
    portableSha256=[string]$artifactByName.portable.sha256; portableBytes=[int64]$artifactByName.portable.bytes; installerSourceSha256=[string]$artifactByName.installerSource.sha256; installerSourceBytes=[int64]$artifactByName.installerSource.bytes
    artifacts=@($manifest.artifacts); signingState=[string]$manifest.signingState; privateSigningProfile=[string]$manifest.privateSigningProfile; signerSubject=[string]$manifest.signerSubject; signerThumbprint=[string]$manifest.privateSigningCertificateThumbprint
    privateKeyExportable=$false; privateKeyExported=$false; publicCertificate=$manifest.publicCertificate
    superseded=(-not $candidateFlags.candidateIsCurrent); invalidationReason=[string](Get-FirstProperty $state @('candidate_invalidation_reason','candidateInvalidationReason'))
    f005Attempted=$false; formatterOnlyAuditCleanup=$false; f005StructuralRefactor=$false
}

$interactiveCurrent = Read-Json (Join-Path $evidence 'CURRENT-INTERACTIVE-LOGIN.json')
$interactiveSmokeRunId = if($interactiveCurrent -and [string]$interactiveCurrent.RunId){[string]$interactiveCurrent.RunId}else{$null}
if (-not $CurrentProofRunId) { $CurrentProofRunId = [string]$state.current_proof_run_id }
if ($finalAcceptanceValid -and @($finalAcceptance.proofRunIds) -notcontains $CurrentProofRunId) { $CurrentProofRunId = [string](@($finalAcceptance.proofRunIds)[-1]) }
$proofRun = if ($CurrentProofRunId) { Join-Path $runRoot $CurrentProofRunId } else { $null }
$proofStartRecord = if ($proofRun) { Get-NewestJson $proofRun 'proof-start.json' } else { $null }
$proofFinalRecord = if ($proofRun) { Get-NewestJson $proofRun 'proof-final.json' } else { $null }
$proofErrorRecord = if ($proofRun) { Get-NewestJson $proofRun 'proof-error.json' } else { $null }
$terminalRecord = if ($proofRun) { Get-NewestJson $proofRun 'product-lifecycle-terminal.json' } else { $null }
$providerRecord = if ($proofRun) { Get-NewestJson $proofRun 'product-lifecycle-provider-failure.json' } else { $null }
$progressRecord = if ($proofRun) { Get-NewestJson $proofRun 'product-lifecycle-progress-current.json' } else { $null }
$cleanupRecord = if ($proofRun) { Get-NewestJson $proofRun 'cleanup-state.json' } else { $null }
$proofStart = if ($proofStartRecord) { $proofStartRecord.value } else { $null }
$proofFinal = if ($proofFinalRecord) { $proofFinalRecord.value } else { $null }
$proofError = if ($proofErrorRecord) { $proofErrorRecord.value } else { $null }
$terminal = if ($terminalRecord) { $terminalRecord.value } else { $null }
$providerFailure = if ($providerRecord) { $providerRecord.value } else { $null }
$progress = if ($progressRecord) { $progressRecord.value } else { $null }
$proofStartCurrent = $false
$candidateBindingUtc = [datetime]::MinValue
$candidateBindingRaw = Get-FirstProperty $state @('candidate_binding_utc','candidateBindingUtc','finalizer_completed_utc')
try { if($candidateBindingRaw){$candidateBindingUtc=ConvertTo-AuthorityUtcInstant $candidateBindingRaw} } catch { $candidateBindingUtc=[datetime]::MinValue }
if ($proofStart -and $proofStart.provenance) {
    $proofStartedUtc = [datetime]::MinValue
    $proofStartedRaw = Get-FirstProperty $proofStart @('generatedAtUtc','timestampUtc','startedAtUtc')
    try { if($proofStartedRaw){$proofStartedUtc=ConvertTo-AuthorityUtcInstant $proofStartedRaw} elseif($proofStartRecord.lastWriteUtc){$proofStartedUtc=ConvertTo-AuthorityUtcInstant $proofStartRecord.lastWriteUtc} } catch { $proofStartedUtc=[datetime]::MinValue }
    $proofStartCurrent = [string]$proofStart.provenance.repositoryHead -ceq $head -and [string]$proofStart.provenance.candidateCommit -ceq $candidateCommit -and [string]$proofStart.provenance.shippingInputIdentity -ceq $shippingIdentity -and [string]$proofStart.provenance.releaseFingerprint -ceq $releaseId -and [string]$proofStart.provenance.toolingFingerprint -ceq $toolingId -and ($finalAcceptanceValid -or $proofStartedUtc -ge $candidateBindingUtc)
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

$currentStatus = [ordered]@{schemaVersion=3;authorityId=$authorityId;generatedAtUtc=$authority.generatedAtUtc;status=$status;blockerClassification=$blockerClassification;blocker=$blocker;nextAction=$nextAction;repositoryHead=$head;candidateCommit=$candidateCommit;shippingInputIdentity=$shippingIdentity;candidateShippingInputIdentity=$shippingIdentity;releaseFingerprintId=$releaseId;toolingFingerprintId=$toolingId;workingTree=$workingTree;candidateIsCurrent=$candidateFlags.candidateIsCurrent;sourceChangedSinceCandidate=$candidateFlags.sourceChangedSinceCandidate;rebuildRequired=$candidateFlags.rebuildRequired;validationEvidenceCurrent=$candidateFlags.validationEvidenceCurrent;fullReleasePassed=$fullPassed;internalPromotionAllowed=$candidateFlags.internalPromotionAllowed;publicPromotionAllowed=$false;publicPublisherTrust=$false;currentProofRunId=if($CurrentProofRunId){$CurrentProofRunId}else{$null};currentProofOutcome=$proofOutcome;proofsPassed=$passingProofs.Count;proofsRequired=2;fu