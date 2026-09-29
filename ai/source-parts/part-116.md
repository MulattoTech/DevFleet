# DevFleet source part 116

Full-source UTF-8 byte interval [5347500, 5394000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8486afd1713f5b9bf38a50aec499891e004a989c5426a1715aeb7ef5dc12c134

<!-- BEGIN SOURCE SLICE -->
978183322204c523b40947d073aa0' -and
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
        if([int]$baselinePointer.generation -in @(3,4,5)){
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
                if(-not(Test-Path -LiteralPath $artifactSource -PathType Leaf) -or (Get-Hash $artifactSource) -cne $artifactHash){throw 'Repair-3 