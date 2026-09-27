# DevFleet source part 114

Full-source UTF-8 byte interval [5254500, 5301000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 023488ccd43f68cb791f705f7f949dc7a3e2f94c4ec9bc6b5838cf441853a10b

<!-- BEGIN SOURCE SLICE -->


SHA256: 5c8c3ebb294bb267995747ebbe96d17a03f433d3882b1d8573352fe497b9312d | Bytes: 238 | Git mode: 100644

```
[CmdletBinding()]
param([string]$Workspace = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Build-AIAuditBundle.ps1') -Workspace $Workspace
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

```


## FILE: tools/Build-AIAuditBundle.ps1

SHA256: 4befd0c71379996d857fff6abb84ca07bd4bb021851d70a1e36c72926b3f8b58 | Bytes: 95333 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$Workspace = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('Auto','PreAcceptanceReleaseAudit')]
    [string]$Operation = 'Auto',
    [string]$ReleaseAuditRunId
)

$ErrorActionPreference = 'Stop'
$env:PYTHONDONTWRITEBYTECODE = '1'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
Import-Module (Join-Path $Workspace 'tools\PythonRuntime.psm1') -Force
$python = Resolve-DevFleetPython -Workspace $Workspace
$Outputs = Join-Path $Workspace 'outputs'
$Audit = Join-Path $Workspace 'audit'
$releaseVersion = (Get-Content -LiteralPath (Join-Path $Workspace 'source\VERSION') -Raw).Trim()
$installerVersion = (Get-Content -LiteralPath (Join-Path $Workspace 'installer-source\INSTALLER_VERSION') -Raw).Trim()
$zipPath = Join-Path $Outputs ("DevFleet-v{0}-AI-Audit-LATEST.zip" -f $releaseVersion)
$sidecarPath = "$zipPath.sha256.txt"
$manifestPath = "$zipPath.manifest.json"
$stage = Join-Path ([IO.Path]::GetTempPath()) ("DevFleet AI Audit bundle {0}" -f [guid]::NewGuid().ToString('N'))
$sourceStage = Join-Path $stage 'source'
$installerStage = Join-Path $stage 'installer-source'
$automationStage = Join-Path $stage 'automation'
$toolingStage = Join-Path $stage 'release-tooling'
$evidenceStage = Join-Path $stage 'evidence'
$auditStage = Join-Path $stage 'audit'
$outputMetadataStage = Join-Path $stage 'outputs'

function Rel([string]$Path) { return ([IO.Path]::GetFullPath($Path)).Substring($Workspace.Length).TrimStart('\','/').Replace('\','/') }
function Read-Json([string]$Path) { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Write-Json([string]$Path,$Value) { $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function Write-AtomicJson([string]$Path,$Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,(($Value | ConvertTo-Json -Depth 40) + [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-StringHash([string]$Value) { $sha=[Security.Cryptography.SHA256]::Create(); try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() } }
function Is-Excluded([IO.FileInfo]$File,[string]$Relative) {
    $parts = $Relative.Split('/')
    $blocked = @('.git','.venv','node_modules','bin','obj','__pycache__','.pytest_cache','.test-runtime','build','dist','outputs','audit-extract','transient-source-quarantine','stale-portable-metadata-quarantine','VHDX','snapshots','browser-profiles')
    foreach ($part in $parts) { if ($blocked -contains $part -or $part -like '.venv-*') { return $true } }
    if ($File.Name -match '(?i)\.(pyc|pyo|exe|dll|pdb|msi|iso|img|vhd|vhdx|avhdx|zip|7z|cab|tar|gz|tgz|png|jpg|jpeg|gif|bmp|ico|webp|woff|woff2|ttf)$') { return $true }
    return $false
}
function Add-Tree {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][string]$BundlePrefix)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Required audit source root is missing: $Root" }
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse -Force) {
        $relative = ([IO.Path]::GetFullPath($file.FullName)).Substring(([IO.Path]::GetFullPath($Root)).Length).TrimStart('\','/').Replace('\','/')
        $bundlePath = "$BundlePrefix/$relative"
        if (Is-Excluded $file $bundlePath) { continue }
        $destination = Join-Path $DestinationRoot ($relative -replace '/','\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
}
function Add-CompactFile([string]$Source,[string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return $false }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    return $true
}
function Add-AuthorizationLedgerClosure([string]$Repository,[string]$EvidenceRoot) {
    $selected=@(
        [ordered]@{name='df-audit-convergence-20260924-a-ledger.json';policyId='DF-AUDIT-CONVERGENCE-20260924-A'},
        [ordered]@{name='df-rdc-certification-continuation-20260924-b-ledger.json';policyId='DF-RDC-CERTIFICATION-CONTINUATION-20260924-B'}
    )
    $rows=[Collections.Generic.List[object]]::new();$sources=@{}
    foreach($entry in $selected){
        $relative='evidence/campaigns/'+[string]$entry.name
        if($relative -notmatch '^evidence/campaigns/[A-Za-z0-9-]+-ledger\.json$'){throw 'Authorization ledger path is outside the fixed safe allowlist.'}
        $source=Join-Path $Repository ('evidence\campaigns\'+[string]$entry.name);$checked=$Repository
        foreach($component in $relative.Split('/')){$checked=Join-Path $checked $component;$componentItem=Get-Item -LiteralPath $checked -Force -ErrorAction Stop;if(($componentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Authorization ledger path rejects reparse-point components.'}}
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Required adopted authorization ledger is missing: $relative"}
        $item=Get-Item -LiteralPath $source -Force
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Authorization ledger staging rejects reparse-point inputs.'}
        $sourceHash=Get-Hash $source;$sourceBytes=[int64]$item.Length;$row=Read-Json $source
        if([string]$row.policyId -cne [string]$entry.policyId){throw "Authorization ledger policy substitution rejected: $relative"}
        $sources[[string]$entry.policyId]=[pscustomobject]@{row=$row;path=$relative;sha256=$sourceHash;bytes=$sourceBytes}
    }
    $b=$sources['DF-RDC-CERTIFICATION-CONTINUATION-20260924-B'];$a=$sources['DF-AUDIT-CONVERGENCE-20260924-A']
    if([string]$b.row.continuation.predecessor.path -cne [string]$a.path -or [string]$b.row.continuation.predecessor.sha256 -cne [string]$a.sha256){throw 'Adopted authorization ledger predecessor/hash closure is inconsistent.'}
    foreach($entry in $selected){
        $relative='evidence/campaigns/'+[string]$entry.name;$source=Join-Path $Repository ('evidence\campaigns\'+[string]$entry.name);$destination=Join-Path $EvidenceRoot ('campaigns\'+[string]$entry.name)
        if(-not(Add-CompactFile $source $destination)){throw "Authorization ledger disappeared during staging: $relative"}
        if((Get-Hash $source) -cne $sources[[string]$entry.policyId].sha256 -or (Get-Hash $destination) -cne $sources[[string]$entry.policyId].sha256 -or [int64](Get-Item -LiteralPath $destination).Length -ne $sources[[string]$entry.policyId].bytes){throw "Authorization ledger hash/length changed during staging: $relative"}
        $row=$sources[[string]$entry.policyId].row
        $adoptedAt=$row.authorization.adoptedAtUtc;if($adoptedAt -is [datetime]){$adoptedAt=$adoptedAt.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
        $rows.Add([ordered]@{policyId=[string]$entry.policyId;sourcePath=$relative;sourceBytes=$sources[[string]$entry.policyId].bytes;sourceSha256=$sources[[string]$entry.policyId].sha256;stagedPath='evidence/campaigns/'+[string]$entry.name;stagedBytes=[int64](Get-Item -LiteralPath $destination).Length;stagedSha256=(Get-Hash $destination);status=[string]$row.status;adoptedAtUtc=[string]$adoptedAt;counters=$row.counters;baseline=$row.baseline;maximumTopLevelInvocations=$row.maximumTopLevelInvocations;sharedCorrectivePool=$row.sharedCorrectivePool;activeReservationPresent=($null -ne $row.activeReservation)})
    }
    $malformedPath='evidence/campaigns/df-tailscale-peer-convergence-20260921-a-ledger.json';$malformed=$null
    $historical=$a.row.continuation.preservedLedgerFiles|Where-Object{[string]$_.path -ceq $malformedPath}|Select-Object -First 1
    if($historical){$malformedSource=Join-Path $Repository ($malformedPath.Replace('/','\'));$actualHash=if(Test-Path -LiteralPath $malformedSource -PathType Leaf){Get-Hash $malformedSource}else{''};$matches=($actualHash -ceq [string]$historical.sha256);$malformed=[ordered]@{path=$malformedPath;recordedSourceSha256=[string]$historical.sha256;observedSourceSha256=$actualHash;sourceHashMatchesRecorded=$matches;parseStatus=if($matches){[string]$historical.observedParseStatus}else{'SOURCE_HASH_MISMATCH'};authorizationInterpretation='UNKNOWN'}}
    $projection=[ordered]@{schemaVersion=1;kind='SANITIZED_REVIEW_PROJECTION';authority=$false;runtimeAuthorizationGranted=$false;ledgers=@($rows);malformedHistoricalLedger=$malformed}
    $projectionPath=Join-Path $EvidenceRoot 'campaigns\authorization-ledger-closure.json';Write-Json $projectionPath $projection
    $projectionText=Get-Content -LiteralPath $projectionPath -Raw
    if($projectionText -match '(?i)"(password|secret|hmac|dpapi|privateKey)"\s*:'){throw 'Authorization review projection contains a prohibited secret-bearing field.'}
    return $projection
}
function Add-AstraCausalEvidence([string]$Repository,[string]$EvidenceRoot) {
    # This frozen allowlist retains historical causal bytes, never proof credit.
    # Do not discover runs by timestamps or recursively adopt diagnostic folders.
    $manifestPath=Join-Path $Repository 'tools/astra-causal-evidence.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop|ConvertFrom-Json
    if($manifest.schemaVersion -ne 1 -or -not @($manifest.records).Count){throw 'Astra causal evidence allowlist is empty or unsupported.'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($record in $manifest.records){
        $relative=[string]$record.source;$destination=[string]$record.destination
        if($relative -notmatch '^audit/automation-harness/[A-Za-z0-9._/-]+$' -or $relative.Split('/') -contains '..' -or $relative.Split('/') -contains '.' -or $relative.Contains('//')){throw 'Astra causal source escapes its allowlisted namespace.'}
        if($destination -notmatch '^[A-Za-z0-9_-]+/[A-Za-z0-9._/-]+$' -or $destination.Split('/') -contains '..' -or $destination.Split('/') -contains '.' -or $destination.Contains('//')){throw 'Astra causal destination is malformed.'}
        if(@($destination.Split('/')|Where-Object{$_ -in @('snapshots','outputs','build','dist','.git')}).Count -or -not $seen.Add($destination)){throw 'Astra causal destination is excluded or duplicated.'}
        if([string]$record.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Astra causal evidence hash is malformed.'}
        $source=Join-Path $Repository $relative
        if(-not(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Hash $source) -cne [string]$record.sha256){throw "Astra causal evidence is missing or changed: $relative"}
        $target=Join-Path $EvidenceRoot ('astra-causal/'+$destination)
        if(-not(Add-CompactFile $source $target) -or (Get-Hash $target) -cne [string]$record.sha256){throw "Astra causal evidence copy did not verify: $relative"}
    }
    if(-not(Add-CompactFile $manifestPath (Join-Path $EvidenceRoot 'astra-causal/allowlist.json'))){throw 'Astra causal allowlist was not retained.'}
    return $seen.Count
}
function Add-GitBlob([string]$Commit,[string]$RepositoryPath,[string]$Destination) {
    $code='import pathlib,subprocess,sys; data=subprocess.check_output(["git","-C",sys.argv[1],"show",sys.argv[2]]); pathlib.Path(sys.argv[3]).write_bytes(data)'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    & $python -c $code $Workspace ("$Commit`:$RepositoryPath") $Destination
    if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $Destination -PathType Leaf)){throw "Could not recover exact historical Git blob $Commit`:$RepositoryPath."}
    return $true
}
function Find-Artifact([object[]]$Rows,[string]$Leaf) { return @($Rows | Where-Object { [IO.Path]::GetFileName([string]$_.path) -eq $Leaf } | Select-Object -First 1)[0] }

New-Item -ItemType Directory -Force -Path $Outputs,$Audit,$stage,$sourceStage,$installerStage,$automationStage,$toolingStage,$evidenceStage,$auditStage,$outputMetadataStage | Out-Null
try {
    $statePath = Join-Path $Workspace 'finalization-state.json'
    $artifactPath = Join-Path $Outputs 'final-artifact-hashes.json'
    if (-not (Test-Path -LiteralPath $statePath) -or -not (Test-Path -LiteralPath $artifactPath)) { throw 'Current candidate state or artifact manifest is missing.' }
    $state = Read-Json $statePath
    $artifactManifest = Read-Json $artifactPath
    $preAcceptanceAudit = $Operation -eq 'PreAcceptanceReleaseAudit'
    $releaseValidator = Join-Path $Workspace 'tools\validate_release_bundle.py'
    $workspaceValidation = $null
    if ($preAcceptanceAudit) {
        $workspaceValidationOutput = @(& $python $releaseValidator --workspace-root $Workspace --check release-evidence 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Pre-acceptance RELEASE audit refused current evidence: $($workspaceValidationOutput -join "`n")" }
        try { $workspaceValidation = ($workspaceValidationOutput -join "`n") | ConvertFrom-Json } catch { throw 'Pre-acceptance workspace validator did not return JSON.' }
        if ([string]$workspaceValidation.status -ne 'PASS' -or [bool]$workspaceValidation.releaseEligible) { throw 'Pre-acceptance workspace validation was not a non-promoting PASS.' }
    } else {
        $finalValidationOutput = @(& $python $releaseValidator --workspace-root $Workspace --check final-acceptance 2>&1)
        $finalAcceptanceValid = $LASTEXITCODE -eq 0
        if ($finalAcceptanceValid) {
            try { $workspaceValidation = ($finalValidationOutput -join "`n") | ConvertFrom-Json } catch { $finalAcceptanceValid = $false }
        }
        if ($finalAcceptanceValid -and ([string]$workspaceValidation.status -ne 'PASS' -or -not [bool]$workspaceValidation.internalPromotionAllowed)) { $finalAcceptanceValid = $false }
    }
    $releaseFingerprintPath = Join-Path $Outputs 'release-fingerprint.json'
    $toolingCurrentPath = Join-Path $Outputs 'tooling-fingerprint-current.json'
    $advisoryPath = Join-Path $Outputs 'dependency-advisory-gate.json'
    $osvReconciliationPath = Join-Path $Outputs 'independent-osv-reconciliation.json'
    $signingProviderPath = Join-Path $Outputs 'signing-provider.json'
    if (-not (Test-Path -LiteralPath $releaseFingerprintPath -PathType Leaf) -or -not (Test-Path -LiteralPath $toolingCurrentPath -PathType Leaf) -or -not (Test-Path -LiteralPath $advisoryPath -PathType Leaf) -or -not (Test-Path -LiteralPath $osvReconciliationPath -PathType Leaf) -or -not (Test-Path -LiteralPath $signingProviderPath -PathType Leaf)) { throw 'Current release identity, signing provider, or dependency advisory evidence is missing.' }
    $releaseFingerprint = Read-Json $releaseFingerprintPath
    $toolingCurrent = Read-Json $toolingCurrentPath
    $signingProvider = Read-Json $signingProviderPath
    if ([int]$releaseFingerprint.schemaVersion -ne 2 -or [int]$toolingCurrent.schemaVersion -ne 2 -or [int]$toolingCurrent.releaseFingerprintSchemaVersion -ne 2) { throw 'Current audit identity must use release fingerprint schema v2.' }
    if ([int]$signingProvider.schemaVersion -ne 1 -or [bool]$signingProvider.privateKeyExported -or [bool]$signingProvider.privateKeyExportable -or [bool]$signingProvider.publicPublisherTrust -or [bool]$signingProvider.publicPromotionAllowed) { throw 'Signing provider metadata is missing or violates the private-signing release contract.' }
    $artifactRows = @($artifactManifest.artifacts)
    $branch = (& git -C $Workspace branch --show-current).Trim()
    $head = (& git -C $Workspace rev-parse HEAD).Trim()
    # Candidate currency is bound to deterministic shipping-input identity;
    # repository/tooling HEAD may advance without changing shipping bytes.
    $gitClean = (@(& git -C $Workspace status --porcelain) | Measure-Object).Count -eq 0

    $artifactNames = [ordered]@{
        exe = "DevFleet-Setup-v$releaseVersion-win-x64.exe"
        tar = "devfleet-v$releaseVersion.tar.gz"
        portable = "DevFleet-v$releaseVersion-Portable-Codebase-Verified-r1.zip"
        installerSource = "DevFleet-v$releaseVersion-Installer-Source.zip"
    }
    $candidateArtifacts = [ordered]@{}
    foreach ($key in $artifactNames.Keys) {
        $row = Find-Artifact $artifactRows $artifactNames[$key]
        $path = if ($row) { [string]$row.path } else { Join-Path $Outputs $artifactNames[$key] }
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $Workspace $path }
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $candidateArtifacts[$key] = [ordered]@{
            name = $artifactNames[$key]; path = (Rel $path); bytes = if ($exists) { [int64](Get-Item -LiteralPath $path).Length } else { 0 }
            sha256 = if ($exists) { Get-Hash $path } else { '' }
            manifestSha256 = if ($row) { [string]$row.sha256 } else { '' }
            exists = $exists
        }
    }
    $releaseId = [string]$state.releaseFingerprintId
    $toolingId = [string]$state.toolingFingerprintId
    $sourceChanged = [bool]$state.source_changed_since_candidate
    $rebuildRequired = [bool]$state.rebuild_required
    $workingToolingId = [string]$state.working_tree_tooling_fingerprint_id
    if (-not $releaseId -or -not $toolingId) { throw 'Current state has no release/tooling fingerprint tuple.' }
    if ($artifactManifest.releaseFingerprintId -ne $releaseId -or $artifactManifest.toolingFingerprintId -ne $toolingId) { throw 'Artifact manifest disagrees with finalization state fingerprints.' }
    if ($releaseFingerprint.releaseFingerprintId -ne $releaseId -or $releaseFingerprint.toolingFingerprint.toolingFingerprintId -ne $toolingId -or $toolingCurrent.releaseFingerprintId -ne $releaseId -or $toolingCurrent.toolingFingerprintId -ne $toolingId) { throw 'Current release/tooling fingerprint files disagree with finalization state.' }
    foreach ($item in $candidateArtifacts.Values) {
        if (-not $item.exists -or $item.sha256 -ne $item.manifestSha256) { $artifactMismatch = $true }
    }
    $candidateCommit = [string]$state.candidateGitCommit
    if (-not $candidateCommit) { $candidateCommit = [string]$state.candidate_git_commit }
    if (-not $candidateCommit) { $candidateCommit = [string]$state.candidateCommit }
    if (-not $candidateCommit) { $candidateCommit = $head }
    if ($candidateCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'Candidate commit is missing or malformed.' }
    $failedAttemptSnapshotRelative = 'audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json'
    $failedAttemptSnapshotPath = Join-Path $Workspace ($failedAttemptSnapshotRelative -replace '/','\')
    $failedAttemptContract = (Test-Path -LiteralPath $failedAttemptSnapshotPath -PathType Leaf) -and
        $candidateCommit -eq '21752fc0e50978183322204c523b40947d073aa0' -and
        [string]$state.blocker_code -eq 'REPLACEMENT_CANDIDATE_BINDING_MISMATCH'
    # Compute both sides from the live filesystem and the exact candidate commit
    # using source/tools/release_fingerprint.py.  Never treat the current
    # release-fingerprint.json rows as a live identity: they are candidate
    # metadata and may be stale after tooling-only commits.
    $identityArguments = @('--workspace',$Workspace,'--candidate-commit',$candidateCommit)
    foreach ($artifactName in $candidateArtifacts.Keys) {
        $artifactFullPath = Join-Path $Workspace ([string]$candidateArtifacts[$artifactName].path)
        $identityArguments += @('--artifact',"$artifactName=$artifactFullPath")
    }
    $identityRaw = @(& $python (Join-Path $Workspace 'tools\compute_shipping_input_identity.py') @identityArguments)
    if ($LASTEXITCODE -ne 0 -or $identityRaw.Count -eq 0) { throw 'Live/candidate shipping-input identity computation failed.' }
    try { $identity = ($identityRaw -join "`n") | ConvertFrom-Json } catch { throw "Shipping-input identity output was not valid JSON: $($_.Exception.Message)" }
    function Normalize-ShippingRows([object[]]$Rows) {
        return @($Rows | Sort-Object root,path | ForEach-Object {
            [ordered]@{root=[string]$_.root;path=[string]$_.path;bytes=[int64]$_.bytes;sha256=[string]$_.sha256;mode=[string]$_.mode}
        })
    }
    $liveRows = Normalize-ShippingRows @($identity.liveShippingInputs)
    $candidateRows = Normalize-ShippingRows @($identity.candidateShippingInputs)
    if ($liveRows.Count -eq 0 -or $candidateRows.Count -eq 0) { throw 'Shipping-input identity computation returned no inputs.' }
    $liveMode = ($identity.liveShippingModeContract | ConvertTo-Json -Compress -Depth 10)
    $candidateMode = ($identity.candidateShippingModeContract | ConvertTo-Json -Compress -Depth 10)
    # The Python identity tool is the authoritative canonical algorithm.  Do
    # not hash a PowerShell serialization of rows here; that would omit the
    # version and mode contract and could silently disagree with validators.
    $rawLiveShippingInputIdentity = [string]$identity.liveShippingInputIdentity
    $currentShippingInputIdentity = $rawLiveShippingInputIdentity
    $candidateComputedIdentity = [string]$identity.candidateShippingInputIdentity
    $candidateShippingInputIdentity = [string]$state.shipping_input_identity
    if (-not $candidateShippingInputIdentity) { $candidateShippingInputIdentity = [string]$state.shippingInputIdentity }
    if (-not $candidateShippingInputIdentity) { $candidateShippingInputIdentity = [string]$artifactManifest.shippingInputIdentity }
    if ($failedAttemptContract) { $currentShippingInputIdentity = [string]$state.failed_replacement_attempt.buildTimeShippingInputIdentity }
    $historicalDiagnosticTuple = $candidateCommit -eq '2739e0366d070285e44b4fc764ef9247d40b2f94' -and
        $candidateShippingInputIdentity -eq 'daa30ef9f521a47fedb4bacce91e3440c20e1a8f05543b4d5e823e5c3541e64e' -and
        [string]$state.releaseFingerprintId -eq '80c8b88c2f2ec828f5ab0f9713d63fa3f4cc4cbad7c382aa2f154f3196c3de84' -and
        [bool]$state.source_changed_since_candidate -and [bool]$state.rebuild_required -and -not [bool]$state.candidate_is_current
    if (-not $currentShippingInputIdentity -or -not $candidateShippingInputIdentity -or ($candidateComputedIdentity -ne $candidateShippingInputIdentity -and -not $historicalDiagnosticTuple -and -not $failedAttemptContract)) { throw 'Candidate-bound shipping-input identity does not match the exact candidate commit rows.' }
    $embeddedFingerprintRows = Normalize-ShippingRows @($releaseFingerprint.shippingInputs)
    if (($embeddedFingerprintRows | ConvertTo-Json -Compress -Depth 12) -cne ($candidateRows | ConvertTo-Json -Compress -Depth 12)) { throw 'release-fingerprint.json shipping rows are not the exact candidate Git-object rows.' }
    if ([string]$identity.candidateReleaseFingerprintId -cne $releaseId -or [string]$releaseFingerprint.releaseFingerprintId -cne $releaseId) { throw 'Declared release fingerprint does not recompute from the candidate Git-object rows and exact artifact tuple.' }
    $liveToolingId = [string]$identity.liveToolingFingerprint.toolingFingerprintId
    if ($liveToolingId -cne $toolingId) {
        if (-not $sourceChanged -or -not $rebuildRequired -or $workingToolingId -notmatch '^[0-9a-f]{64}$' -or $liveToolingId -cne $workingToolingId) {
            throw 'Live release tooling differs from the candidate tuple without an exact fail-closed working-tree tooling fingerprint.'
        }
    }
    if (($releaseFingerprint.shippingModeContract | ConvertTo-Json -Compress -Depth 10) -cne ($identity.candidateShippingModeContract | ConvertTo-Json -Compress -Depth 10)) { throw 'release-fingerprint.json mode contract is not candidate-bound.' }
    $rawAuthorizedShippingPaths = @($state.authorized_correction.shipping_paths | ForEach-Object { ([string]$_).Trim().Replace('\\','/').TrimStart('/') } | Where-Object { $_ })
    $authorizedShippingPaths = @($rawAuthorizedShippingPaths | Sort-Object -Unique)
    if ($authorizedShippingPaths.Count -ne $rawAuthorizedShippingPaths.Count -or @($authorizedShippingPaths | Where-Object { $_ -notmatch '^(source|installer-source)/[^/].*$' -or $_ -match '(^|/)\.\.(/|$)' }).Count -gt 0) {
        throw 'Authorized shipping correction paths are duplicated, malformed, or outside the shipping roots.'
    }
    $liveByPath = @{}; foreach ($row in $liveRows) { $liveByPath[(([string]$row.root).TrimEnd('/') + '/' + [string]$row.path)] = ($row | ConvertTo-Json -Compress -Depth 10) }
    $candidateByPath = @{}; foreach ($row in $candidateRows) { $candidateByPath[(([string]$row.root).TrimEnd('/') + '/' + [string]$row.path)] = ($row | ConvertTo-Json -Compress -Depth 10) }
    $shippingChangedPaths = @((@($liveByPath.Keys) + @($candidateByPath.Keys)) | Sort-Object -Unique | Where-Object { $liveByPath[$_] -cne $candidateByPath[$_] })
    # A Windows checkout may materialize committed LF blobs as CRLF without
    # changing the canonical Git-object candidate.  Prove this narrowly with
    # Git's EOL-only diff mode before accepting the candidate as unchanged.
    $crlfOnlyPaths = [Collections.Generic.List[string]]::new()
    $substantiveShippingChangedPaths = [Collections.Generic.List[string]]::new()
    foreach ($changedPath in $shippingChangedPaths) {
        if (-not $liveByPath.ContainsKey($changedPath) -or -not $candidateByPath.ContainsKey($changedPath)) {
            $substantiveShippingChangedPaths.Add($changedPath)
            continue
        }
        & git -C $Workspace diff --quiet --ignore-space-at-eol $candidateCommit -- $changedPath
        if ($LASTEXITCODE -eq 0) { $crlfOnlyPaths.Add($changedPath); continue }
        if ($LASTEXITCODE -eq 1) { $substantiveShippingChangedPaths.Add($changedPath); continue }
        throw "Git could not classify the candidate/live line-ending delta for $changedPath."
    }
    $crlfOnlyPaths = @($crlfOnlyPaths | Sort-Object -Unique)
    $substantiveShippingChangedPaths = @($substantiveShippingChangedPaths | Sort-Object -Unique)
    $crlfOnlyMaterialization = $shippingChangedPaths.Count -gt 0 -and $substantiveShippingChangedPaths.Count -eq 0
    if ($crlfOnlyMaterialization) { $currentShippingInputIdentity = $candidateComputedIdentity }
    $postFailurePaths = @($state.failed_replacement_attempt.postFailureEvidenceTooling.paths | ForEach-Object { ([string]$_.path).Trim().Replace('\','/') } | Where-Object { $_ })
    $attemptedChangedPaths = @($shippingChangedPaths | Where-Object { $postFailurePaths -notcontains $_ })
    $historicalCrlfPaths = @($attemptedChangedPaths | Where-Object { $authorizedShippingPaths -notcontains $_ })
    $unknownHistoricalPaths = @($historicalCrlfPaths | Where-Object { $_ -notmatch '^(source|installer-source)/' })
    if (($historicalDiagnosticTuple -or $failedAttemptContract) -and ($historicalCrlfPaths.Count -ne 28 -or $unknownHistoricalPaths.Count -ne 0)) { throw "Historical CRLF/current-change partition is not exactly 28 classified shipping rows (rows=$($historicalCrlfPaths.Count), unknown=$($unknownHistoricalPaths.Count))." }
    $splitIdentityCorrectionAllowed = $sourceChanged -and $rebuildRequired -and $substantiveShippingChangedPaths.Count -gt 0 -and
        ((@($substantiveShippingChangedPaths) -join "`n") -ceq (@($authorizedShippingPaths) -join "`n"))
    if ($rawLiveShippingInputIdentity -cne $candidateComputedIdentity -or $liveMode -cne $candidateMode -or [string]$identity.liveVersion -cne [string]$identity.candidateVersion -or [string]$identity.liveInstallerVersion -cne [string]$identity.candidateInstallerVersion) {
        if (-not $splitIdentityCorrectionAllowed -and -not $historicalDiagnosticTuple -and -not $failedAttemptContract -and -not $crlfOnlyMaterialization) { throw 'Live shipping inputs differ from the candidate-bound source/installer identity without an authorized, fail-closed replacement correction.' }
    }
    $allChanges = @(& git -C $Workspace diff --name-only $candidateCommit --; & git -C $Workspace ls-files --others --exclude-standard)
    $allowedToolingOnly = $true
    foreach ($change in $allChanges) {
        $normalized = ([string]$change).Trim().Replace('\','/')
        if (-not $normalized) { continue }
        # Shipping classification is defined by the canonical candidate/live
        # inventory, not by a folder allowlist. Release-control documentation
        # and installed skill files can legitimately live outside tools/ while
        # remaining non-shipping; a newly added shipping file appears in the
        # live inventory and is rejected here.
        $isShippingPath = $liveByPath.ContainsKey($normalized) -or $candidateByPath.ContainsKey($normalized)
        if (-not $isShippingPath -or $crlfOnlyPaths -contains $normalized) { continue }
        $allowedToolingOnly = $false
        break
    }
    if ($candidateShippingInputIdentity -ne $currentShippingInputIdentity -or -not $allowedToolingOnly -or $failedAttemptContract) { $sourceChanged = $true; $rebuildRequired = $true }
    if ($artifactMismatch) { $sourceChanged = $true; $rebuildRequired = $true }
    $candidateIsCurrent = [bool]$state.candidate_is_current -and -not $sourceChanged -and -not $rebuildRequired -and -not $failedAttemptContract
    $status = if ($preAcceptanceAudit) { 'PRE_ACCEPTANCE_RELEASE_AUDIT' } elseif ($finalAcceptanceValid) { 'PASS' } elseif ($failedAttemptContract) { 'BLOCKED — USER ACTION REQUIRED' } elseif (-not $candidateIsCurrent -or [string]$state.status -match '(?i)blocked') { 'BLOCKED' } elseif ([string]$state.status -match '(?i)awaiting|progress') { 'READY_FOR_FULLRELEASE' } else { 'IN_PROGRESS' }
    $bundleMode = if ($preAcceptanceAudit -or $finalAcceptanceValid) { 'release' } else { 'diagnostic' }
    $releaseValidationMode = if ($preAcceptanceAudit) { 'pre-acceptance' } else { $bundleMode }

    Add-Tree (Join-Path $Workspace 'source') $sourceStage 'source'
    Add-Tree (Join-Path $Workspace 'installer-source') $installerStage 'installer-source'
    if ($crlfOnlyPaths.Count -gt 0) {
        # Normalize only independently proven EOL-only rows to their canonical
        # Git-object bytes.  Mixed substantive changes remain live in the
        # diagnostic bundle and are bound by authorized_correction below.
        foreach ($crlfPath in $crlfOnlyPaths) {
            $parts = $crlfPath -split '/', 2
            $destinationRoot = if ($parts[0] -eq 'source') { $sourceStage } else { $installerStage }
            Add-GitBlob $candidateCommit $crlfPath (Join-Path $destinationRoot ($parts[1] -replace '/','\\')) | Out-Null
        }
    }
    $stagedIdentityArguments = @('--source-root',$sourceStage,'--installer-root',$installerStage)
    foreach ($artifactName in $candidateArtifacts.Keys) {
        $artifactFullPath = Join-Path $Workspace ([string]$candidateArtifacts[$artifactName].path)
        $stagedIdentityArguments += @('--artifact',"$artifactName=$artifactFullPath")
    }
    $stagedIdentityRaw = @(& $python (Join-Path $Workspace 'tools\compute_shipping_input_identity.py') @stagedIdentityArguments)
    if ($LASTEXITCODE -ne 0 -or $stagedIdentityRaw.Count -eq 0) { throw 'Canonicalized diagnostic shipping-input identity computation failed.' }
    try { $stagedIdentity = ($stagedIdentityRaw -join "`n") | ConvertFrom-Json } catch { throw "Canonicalized diagnostic shipping-input identity output was not valid JSON: $($_.Exception.Message)" }
    $currentShippingInputIdentity = [string]$stagedIdentity.shippingInputIdentity
    if ($currentShippingInputIdentity -notmatch '^[0-9a-f]{64}$') { throw 'Canonicalized diagnostic shipping-input identity is malformed.' }
    if ($crlfOnlyMaterialization -and $currentShippingInputIdentity -cne $candidateComputedIdentity) { throw 'EOL-only normalization did not reproduce the candidate Git-object shipping identity.' }
    Add-Tree (Join-Path $Workspace 'automation\release-e2e') (Join-Path $automationStage 'release-e2e') 'automation/release-e2e'
    Add-Tree (Join-Path $Workspace 'tools') $toolingStage 'release-tooling'
    # Carry the installed release-control contract and its durable Markdown
    # memory as review context. These files are not promotion authority and do
    # not enter the shipping-source inventory below.
    $releaseControlStage = Join-Path $stage 'release-control'
    Add-Tree (Join-Path $Workspace 'docs\ai\devfleet-release') (Join-Path $releaseControlStage 'workflow') 'release-control/workflow'
    Add-CompactFile (Join-Path $Workspace '.agents\skills\devfleet-release-control\SKILL.md') (Join-Path $releaseControlStage 'installed-skill\SKILL.md') | Out-Null
    # Include only the reviewed audit-convergence skill closure. It is advisory
    # review evidence, not a second release authority or a source of runtime grants.
    $auditSkillRoot = Join-Path $Workspace '.agents/skills/devfleet-audit-convergence'
    if (Test-Path -LiteralPath $auditSkillRoot -PathType Container) {
        $auditSkillFiles = @(
            'SKILL.md', 'agents/openai.yaml', 'scripts/audit_io.py',
            'scripts/audit_convergence.py', 'scripts/native_runner.py',
            'references/completion-contract.md', 'tests/test_audit_convergence.py',
            'tests/Test-AuditSkillPackaging.ps1'
        )
        foreach ($skillRelative in $auditSkillFiles) {
            $inputRelative = '.agents/skills/devfleet-audit-convergence/' + $skillRelative
            $checkedPath = $Workspace
            foreach ($component in $inputRelative.Split('/')) {
                $checkedPath = Join-Path $checkedPath $component
                $item = Get-Item -LiteralPath $checkedPath -Force -ErrorAction Stop
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'Audit skill packaging rejects reparse-point inputs.'
                }
            }
            if (-not (Test-Path -LiteralPath $checkedPath -PathType Leaf)) {
                throw "Required audit skill file is missing: $skillRelative"
            }
            $beforeHash = Get-Hash $checkedPath
            $destination = Join-Path $releaseControlStage ('audit-convergence-skill/' + $skillRelative)
            if (-not (Add-CompactFile $checkedPath $destination)) {
                throw "Audit skill staging failed: $skillRelative"
            }
            if ((Get-Hash $destination) -cne $beforeHash -or (Get-Hash $checkedPath) -cne $beforeHash) {
                throw "Audit skill changed during staging: $skillRelative"
            }
        }
    }
    $agentMemoryRoot = Join-Path $Workspace 'audit\agent-memory'
    if (Test-Path -LiteralPath $agentMemoryRoot -PathType Container) {
        foreach ($memoryFile in @(Get-ChildItem -LiteralPath $agentMemoryRoot -Recurse -File -Filter '*.md')) {
            $relativeMemory = $memoryFile.FullName.Substring($agentMemoryRoot.Length).TrimStart('\','/')
            Add-CompactFile $memoryFile.FullName (Join-Path $auditStage (Join-Path 'agent-memory' $relativeMemory)) | Out-Null
        }
    }
    if ($historicalDiagnosticTuple) {
        # Include exact old-candidate bytes for every independently recomputed
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
        candidateIsCurrent = $candidateIsCurrent; sourceChangedSinceCandidate = $sourceChanged; rebuildReq