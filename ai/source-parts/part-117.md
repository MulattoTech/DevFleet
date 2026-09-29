# DevFleet source part 117

Full-source UTF-8 byte interval [5394000, 5440500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 526ad50cf4dab731a8d2c74c4e6fab4d0941c51f47aa00f056429527a05344e9

<!-- BEGIN SOURCE SLICE -->
signed-output receipt is missing or hash-mismatched.'}
                $artifactDestination=Join-Path $evidenceStage ("baselines\sources\{0}.json" -f $artifactHash)
                if(-not(Add-CompactFile $artifactSource $artifactDestination) -or (Get-Hash $artifactDestination) -cne $artifactHash){throw 'Repair-3 signed-output receipt staging failed hash verification.'}
            }
        }
        $cursor=$baselinePointer
        if([int]$cursor.generation -lt 1 -or [int]$cursor.generation -gt 5){throw 'Unsupported accepted baseline generation.'}
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
            if([int]$previousPointer.generation -in @(3,4)){
                $previousReceipt=Read-Json $previousReceiptPath
                foreach($sourceHash in @([string]$previousReceipt.successorLedgerSha256,[string]$previousReceipt.nativeInventorySha256)){
                    if($sourceHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Predecessor baseline source hash is invalid.'}
                    $sourcePath=Join-Path $Workspace "evidence\baselines\sources\$sourceHash.json"
                    if((Get-Hash $sourcePath) -cne $sourceHash){throw 'Predecessor baseline source hash differs.'}
                    $stagedSource=Join-Path $evidenceStage "baselines\sources\$sourceHash.json"
                    if(-not(Add-CompactFile $sourcePath $stagedSource)){throw 'Predecessor baseline source is missing.'}
                }
                if([int]$previousPointer.generation -eq 4){
                    $artifactBinding=$null
                    $ledgerSource=Join-Path $Workspace ("evidence\baselines\sources\{0}.json" -f [string]$previousReceipt.successorLedgerSha256)
                    if(Test-Path -LiteralPath $ledgerSource -PathType Leaf){
                        $ledgerSourceJson=Read-Json $ledgerSource
                        $artifactBinding=$ledgerSourceJson.artifactReceipt
                    }
                    $artifactHash=[string]$artifactBinding.sha256
                    $artifactSource=[string]$artifactBinding.path
                    if($artifactHash -notmatch '^[0-9a-f]{64}$' -or [string]$previousReceipt.artifactReceiptSha256 -cne $artifactHash){throw 'Repair-3 predecessor signed-output receipt hash is missing, malformed, or not bound by the baseline receipt.'}
                    if(-not(Test-Path -LiteralPath $artifactSource -PathType Leaf)){$artifactSource=Join-Path $Workspace ("evidence\baselines\sources\{0}.json" -f $artifactHash)}
                    if(-not(Test-Path -LiteralPath $artifactSource -PathType Leaf) -or (Get-Hash $artifactSource) -cne $artifactHash){throw 'Repair-3 predecessor signed-output receipt is missing or hash-mismatched.'}
                    $artifactDestination=Join-Path $evidenceStage ("baselines\sources\{0}.json" -f $artifactHash)
                    if(-not(Add-CompactFile $artifactSource $artifactDestination) -or (Get-Hash $artifactDestination) -cne $artifactHash){throw 'Repair-3 predecessor signed-output receipt staging failed hash verification.'}
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
                manifest=[ordered]@{workspacePath="$auditWorkspacePrefix/$immutableManifestName";bundlePath="$auditBundlePrefix/$immutableManifestName";bytes=[int64](Get-Item $manifestImmutable).Length;sha256=(Get-Hash $manifestImmutable)}
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
            authenticode=[ordered]@{status='PASS';signatureStatus='