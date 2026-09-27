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
