# DevFleet source part 117

Full-source UTF-8 byte interval [5394000, 5440500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: c53c81932d3a87592a34c40687f79865726d68020a69b35b067da360f8e5445d

<!-- BEGIN SOURCE SLICE -->
s)).ToLowerInvariant()
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
        if(-not $result.l2Observation){$result.l2State='UNVERIFIED';$result.l2ExactAbsent=$false;$result.l2Observation=[ordered]@{schemaVersion=2;expectedName=$L2Name;status='UNVERIFIED';present=$null;verificationMethod='Nested L2 terminal observation could not be validated';ownershipScope='exact expected nested L2 name inside exact disposable L1';evidenceClass='finalizer observation; non-certifying'}}
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
    $proofStartCurrent = [string]$proofStart.provenance.repositoryHead -ceq $head -and [string]$proofStart.provenance.candidateCommit -ceq $candidateCommit -and [string]$proofStart.provenance.shippingInputIdentity -ceq $shippingIdentity -and [string]$proofStart.provenance.releaseFingerprint -ceq $releaseId -and [string]$proofStart.provenance.tool