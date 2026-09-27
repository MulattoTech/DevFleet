[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [switch]$AllowRamPressure,
    [switch]$DiagnosticOnly,
    [switch]$LaptopSurrogate
)

$ErrorActionPreference = 'Stop'
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$scriptRoot = Join-Path $WorkspaceRoot 'automation\release-e2e'
$vmId = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$cleanId = [guid]::Empty
$cleanName = $null
$baseline = $null
$l2Name = 'DevFleet-E2E-Linux-01'
$candidatePath = Join-Path $WorkspaceRoot 'outputs\DevFleet-Setup-v1.2.13-win-x64.exe'
$evidenceModulePath=Join-Path $scriptRoot 'modules\Evidence.psm1'
Import-Module $evidenceModulePath -Force
$pythonRuntimeModulePath=Join-Path $WorkspaceRoot 'tools\PythonRuntime.psm1'
Import-Module $pythonRuntimeModulePath -Force
$python=Resolve-DevFleetPython -Workspace $WorkspaceRoot
$runDir = New-RunEvidenceDirectory -WorkspaceRoot $WorkspaceRoot -RunId $RunId
$vm = $null
$result = $null
$proofExitCode = 0
$cleanupAttempted = $false
$proofRole = if($LaptopSurrogate){'Laptop / Surrogate'}else{'Primary / Desktop'}
$proofPhase = if($LaptopSurrogate){'SURROGATE-DISPOSABLE'}else{'REBOOT-RESUME'}
function Set-CurrentProofPointer([string]$Outcome) {
    $statePath=Join-Path $WorkspaceRoot 'finalization-state.json'
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){return}
    $state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
    $state.current_proof_run_id=$RunId;$state.current_proof_outcome=$Outcome;$state.current_proof_updated_utc=(Get-Date).ToUniversalTime().ToString('o')
    if($DiagnosticOnly){$state.current_diagnostic_run_id=$RunId;$state.diagnostic_run_ids=@(@($state.diagnostic_run_ids)+$RunId|Where-Object{$_}|Select-Object -Unique)}
    else{$state.proof_run_ids=@(@($state.proof_run_ids)+$RunId|Where-Object{$_}|Select-Object -Unique)}
    $tmp="$statePath.$([guid]::NewGuid().ToString('N')).tmp"
    try{[IO.File]::WriteAllText($tmp,(($state|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $tmp -Destination $statePath -Force}
    finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
}

Import-Module (Join-Path $scriptRoot 'modules\Candidate.psm1') -Force
Import-Module $evidenceModulePath -Force
Import-Module (Join-Path $scriptRoot 'modules\Cleanup.psm1') -Force
Import-Module (Join-Path $scriptRoot 'modules\GuestSession.psm1') -Force
Import-Module (Join-Path $scriptRoot 'modules\executors\Invoke-RealProductPhase.psm1') -Force
Import-Module (Join-Path $scriptRoot 'modules\HostSafety.psm1') -Force
Import-Module (Join-Path $scriptRoot 'modules\Secrets.psm1') -Global -Force
Import-Module (Join-Path $scriptRoot 'modules\FullRelease.psm1') -Global -Force
Import-Module (Join-Path $scriptRoot 'modules\Evidence.psm1') -Global -Force
Import-Module (Join-Path $scriptRoot 'modules\HarnessBudget.psm1') -Global -Force

function Invoke-ExactProofCleanup([Parameter(Mandatory)][psobject]$Vm) {
    $cleanup=[ordered]@{runId=$RunId;status='INCOMPLETE';runOwnedOnly=$true;cleanupOwner='run-exact-candidate-proof.ps1';startedAtUtc=(Get-Date).ToUniversalTime().ToString('o');l2=$null;l2Present=$null;l1=$null}
    $cleanupSession=$null
    try {
        if(-not $baseline){throw 'Accepted baseline was not bound before proof cleanup.'}
        $current=Get-VM -Id $vmId -ErrorAction Stop
        if([string]$current.Name -cne 'DevFleet-E2E-Win11-01' -or $current.Id -ne $vmId){throw 'Exact L1 cleanup identity mismatch.'}
        $snapshot=Get-ExactCheckpoint -Vm $current -Name $cleanName
        if($snapshot.Id -ne $cleanId){throw 'Exact canonical CLEAN cleanup identity mismatch.'}
        $cleanup.restore=Restore-ExactCheckpoint -Vm $current -Name $cleanName -StartAfterRestore
        Import-Module (Join-Path $scriptRoot 'modules\GuestSession.psm1') -Global -Force
        $cleanupSession=GuestSession\Connect-DevFleetGuest -VmId $vmId
        $cleanup.l2=GuestSession\Get-DevFleetNestedL2State -Session $cleanupSession -ExpectedName $l2Name
        if([string]$cleanup.l2.status -ne 'ABSENT'){throw "Exact nested L2 cleanup state was not ABSENT: $([string]$cleanup.l2.status)"}
        $cleanup.l2Present=$false
        $cleanup.status='PASS'
    } catch {
        $cleanup.status='BLOCKED'
        $cleanup.error=$_.Exception.Message
    } finally {
        if($cleanupSession){Remove-PSSession $cleanupSession -ErrorAction SilentlyContinue}
        try {
            $finalVm=Get-VM -Id $vmId -ErrorAction Stop
            if([string]$finalVm.Name -cne 'DevFleet-E2E-Win11-01' -or $finalVm.Id -ne $vmId){throw 'Final L1 cleanup identity mismatch.'}
            if($finalVm.State -ne 'Off'){Stop-VM -VM $finalVm -Force -Confirm:$false -ErrorAction Stop}
            $deadline=(Get-Date).AddMinutes(2)
            do{Start-Sleep -Seconds 2;$finalVm=Get-VM -Id $vmId -ErrorAction Stop}while($finalVm.State -ne 'Off' -and (Get-Date) -lt $deadline)
            $cleanup.l1=[ordered]@{status=if($finalVm.State -eq 'Off'){'OFF'}else{'UNVERIFIED'};name=$finalVm.Name;id=$finalVm.Id.ToString();observedUtc=(Get-Date).ToUniversalTime().ToString('o')}
        } catch {
            $cleanup.l1=[ordered]@{status='UNVERIFIED';error=$_.Exception.Message;observedUtc=(Get-Date).ToUniversalTime().ToString('o')}
        }
        if($null -eq $cleanup.l1 -or [string]$cleanup.l1.status -ne 'OFF' -or $null -eq $cleanup.l2 -or [string]$cleanup.l2.status -ne 'ABSENT'){$cleanup.status='BLOCKED'}
        $cleanup.completedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
        $cleanupPath=Join-Path $runDir 'cleanup-state.json'
        Write-EvidenceJson -Path $cleanupPath -Value $cleanup
        if([string]$cleanup.status -eq 'PASS'){Publish-DevFleetTerminalCleanupSummary -WorkspaceRoot $WorkspaceRoot -CleanupEvidencePath $cleanupPath|Out-Null}
    }
    return [pscustomobject]$cleanup
}

$configPath=Join-Path $scriptRoot 'config\devfleet-e2e.defaults.json'
$config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
$budgetPolicy=Get-HarnessBudgetPolicy -Config $config
Assert-HarnessBudgetPolicy -Policy $budgetPolicy | Out-Null

try {
    $vm = Get-VM -Id $vmId -ErrorAction Stop
    if ($vm.Name -notlike 'DevFleet-E2E-*' -or $vm.Id.ToString() -ne $vmId.ToString()) { throw 'Exact disposable VM identity assertion failed.' }
    $fingerprint = Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath $candidatePath
    $baseline=Set-DevFleetBaselineBinding -WorkspaceRoot $WorkspaceRoot -Fingerprint $fingerprint
    $cleanId=[guid][string]$baseline.id
    $cleanName=[string]$baseline.name
    $liveToolingArguments=@('--source-root',(Join-Path $WorkspaceRoot 'source'),'--installer-root',(Join-Path $WorkspaceRoot 'installer-source'))
    foreach($artifact in @(@('exe',$fingerprint.candidate.path),@('tar',$fingerprint.tar.path),@('portable',$fingerprint.portable.path),@('installerSource',$fingerprint.installerSource.path))){$liveToolingArguments+=@('--artifact',"$($artifact[0])=$($artifact[1])")}
    $liveToolingRaw=@(& $python (Join-Path $WorkspaceRoot 'tools\compute_shipping_input_identity.py') @liveToolingArguments)
    if($LASTEXITCODE -ne 0 -or $liveToolingRaw.Count -eq 0){throw 'Exact proof could not compute the live release-tooling identity.'}
    try{$liveTooling=($liveToolingRaw -join "`n")|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Exact proof live release-tooling identity was not valid JSON.'}
    if([string]$liveTooling.toolingFingerprint.toolingFingerprintId -cne [string]$fingerprint.toolingFingerprintId){throw 'Exact proof refused a tooling materialization that differs from current candidate authority.'}
    $provenance = [ordered]@{
        repositoryHead = (& git -C $WorkspaceRoot rev-parse HEAD).Trim()
        candidateCommit = [string]$fingerprint.gitCommit
        shippingInputIdentity = [string]$fingerprint.shippingInputIdentity
        releaseFingerprint = [string]$fingerprint.releaseFingerprintId
        toolingFingerprint = [string]$fingerprint.toolingFingerprintId
        liveToolingFingerprint = [string]$liveTooling.toolingFingerprint.toolingFingerprintId
        invokeRealProductPhaseSha256 = (Get-FileHash (Join-Path $scriptRoot 'modules\executors\Invoke-RealProductPhase.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
        invokeWpfUiAutomationSha256 = (Get-FileHash (Join-Path $scriptRoot 'modules\executors\Invoke-WpfUiAutomation.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
        wpfLaunchContractSha256 = (Get-FileHash (Join-Path $scriptRoot 'modules\executors\WpfLaunchContract.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
        proofScriptSha256 = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        certificationEligible = (-not [bool]$DiagnosticOnly)
        diagnosticOnly = [bool]$DiagnosticOnly
        role = $proofRole
        phaseId = $proofPhase
        cleanCheckpointId = $cleanId.ToString()
        cleanCheckpointName = $cleanName
        baselineReceiptSha256 = $baseline.receiptSha256
        invocation = [ordered]@{runId=$RunId;switches=@('-RunId', $RunId, '-WorkspaceRoot', $WorkspaceRoot) + $(if($AllowRamPressure){@('-AllowRamPressure')}else{@()}) + $(if($DiagnosticOnly){@('-DiagnosticOnly')}else{@()}) + $(if($LaptopSurrogate){@('-LaptopSurrogate')}else{@()});fastMode=$false;ramPressureOverrideAuthorized=[bool]$AllowRamPressure;diagnosticOnly=[bool]$DiagnosticOnly}
        exactArtifacts = [ordered]@{exe=$fingerprint.candidate;tar=$fingerprint.tar;portable=$fingerprint.portable;installerSource=$fingerprint.installerSource}
        deadlinePolicy = $budgetPolicy
    }
    $safety = Apply-RamPressureOverride -Snapshot (Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB 14.38) -AllowRamPressure:$AllowRamPressure
    Write-EvidenceJson -Path (Join-Path $runDir 'proof-start.json') -Value ([ordered]@{
        status = if ($safety.effectiveE2EStartAuthorized) { if($safety.ramPressureOverrideAuthorized){'PASS — USER-AUTHORIZED RAM PRESSURE'}else{'PASS'} } else { 'BLOCKED' }
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        runId = $RunId
        vmName = $vm.Name
        vmId = $vm.Id.ToString()
        hostSafety = $safety
         candidate = $fingerprint
         provenance = $provenance
         credentialLoaded = Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'DevFleet\E2E\secrets.json') -PathType Leaf
        passwordLogged = $false
    })
    if (-not $safety.effectiveE2EStartAuthorized) { throw 'BLOCKED — HOST-SAFETY' }
    $snapshot = Get-ExactCheckpoint -Vm $vm -Name $cleanName
    if($snapshot.Id -ne $cleanId){throw 'Exact canonical CLEAN proof identity mismatch.'}
    $restored = Restore-ExactCheckpoint -Vm $vm -Name $cleanName -StartAfterRestore
    $context = [ordered]@{
        runId = $RunId
        phaseId = $proofPhase
        label = "EXACT CURRENT-CANDIDATE $proofRole PROOF"
        checkpoint = $cleanName
        destructive = $true
        candidate = $fingerprint
        vmName = $vm.Name
        vmId = $vm.Id.ToString()
        runDir = $runDir
        config = $config
        deadlinePolicy = $budgetPolicy
        # A clean disposable first-install may legitimately need several minutes
        # to settle its durable reboot handoff before install-state/health appear.
        # Keep the observation bounded and fail closed; do not shorten it to the
        # generic 180-second diagnostic window.
        diagnosticObservationSeconds = 1800
    }
    # Keep a small outer bound beyond the observer's immutable lifecycle
    # deadline. A broken observer must become an explicit harness outcome,
    # never an inferred product defect and never an unbounded proof process.
    $contextJson = $context | ConvertTo-Json -Depth 32 -Compress
    # The policy is authoritative and already validated before restoring the
    # disposable checkpoint. Never silently truncate an outer watchdog.
    $innerLifecycleBoundSeconds=[int]$budgetPolicy.exactProofInnerBoundSeconds
    $outerWatchdogSeconds=[int]$budgetPolicy.exactProofOuterWatchdogSeconds
    if($outerWatchdogSeconds -le $innerLifecycleBoundSeconds){throw 'Invalid exact-proof deadline hierarchy: outer watchdog does not exceed calculated inner bound.'}
    $phaseModule = Join-Path $scriptRoot 'modules\executors\Invoke-RealProductPhase.psm1'
    $phaseJob = Start-Job -ScriptBlock {
        param($modulePath,$serializedContext)
        Import-Module $modulePath -Force
        Invoke-RealProductPhase -ContextJson $serializedContext
    } -ArgumentList $phaseModule,$contextJson
    try {
        $finished = Wait-Job -Job $phaseJob -Timeout $outerWatchdogSeconds
        if(-not $finished){
            Stop-Job -Job $phaseJob -ErrorAction SilentlyContinue
            Wait-Job -Job $phaseJob -Timeout 15 -ErrorAction SilentlyContinue | Out-Null
            $watchdog = [ordered]@{status='HARNESS_WATCHDOG_EXPIRED';classification='RELEASE HARNESS';runId=$RunId;outerWatchdogSeconds=$outerWatchdogSeconds;innerLifecycleBoundSeconds=$innerLifecycleBoundSeconds;outerExceedsInnerBound=($outerWatchdogSeconds -gt $innerLifecycleBoundSeconds);boundModel=$budgetPolicy;preserveEvidence=$true;timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
            Write-EvidenceJson -Path (Join-Path $runDir 'proof-watchdog.json') -Value $watchdog
            throw 'HARNESS_WATCHDOG_EXPIRED: proof outer watchdog exceeded the observer bound.'
        }
        $jobErrors=@($phaseJob.ChildJobs | ForEach-Object {
            $reason=$_.JobStateInfo.Reason
            if($reason){
                $message=if($reason.Exception -and $reason.Exception.Message){[string]$reason.Exception.Message}else{[string]$reason.ToString()}
                if($message){$message}
            }
        } | Where-Object { $_ })
        if($jobErrors.Count){throw "Proof lifecycle job failed: $($jobErrors -join ' | ')"}
        $jobOutput=@(Receive-Job -Job $phaseJob -ErrorAction Stop)
        if($jobOutput.Count -eq 0){throw "Proof lifecycle job returned no terminal evidence (state=$($phaseJob.State); childState=$($phaseJob.ChildJobs[0].State))."}
        $result=$jobOutput[-1]
    } finally {
        if($phaseJob){Remove-Job -Job $phaseJob -Force -ErrorAction SilentlyContinue}
    }
    if ([string]$result.status -ne 'REAL E2E PASS') { throw 'Exact candidate reboot/resume proof did not return REAL E2E PASS.' }
    $proofBinding = New-DevFleetExactProofBinding -Context ([pscustomobject]$context) -PhaseResult $result -ExpectedRole $proofRole
    $cleanupAttempted=$true
    $cleanup=Invoke-ExactProofCleanup -Vm $vm
    if([string]$cleanup.status -ne 'PASS'){throw "Exact proof cleanup did not PASS: $([string]$cleanup.error)"}
    Write-EvidenceJson -Path (Join-Path $runDir 'proof-final.json') -Value ([ordered]@{
        status = 'PASS'
        outcome = 'PASS'
        runId = $RunId
        role = $proofRole
        provenance = $provenance
        proofStartSha256 = (Get-FileHash -LiteralPath (Join-Path $runDir 'proof-start.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        transactionId = $proofBinding.transactionId
        checkpointLineageId = $proofBinding.checkpointLineageId
        proofBinding = $proofBinding
        candidate = $fingerprint
        # Hyper-V's raw VMSnapshot object exposes a recursive provider graph;
        # serializing it can emit a depth warning and stall proof finalization.
        # Persist only the exact identity already validated by Get-ExactCheckpoint.
        cleanCheckpoint = [ordered]@{name=[string]$snapshot.Name;id=[string]$snapshot.Id;verification='native exact cleanup owner'}
        restored = $restored
        phase = $result
        cleanup = $cleanup
        diagnosticOnly = [bool]$DiagnosticOnly
        certificationEligible = (-not [bool]$DiagnosticOnly)
        passwordLogged = $false
    })
    Set-CurrentProofPointer $(if($DiagnosticOnly){'DIAGNOSTIC_PASS'}else{'PASS'})
    [ordered]@{status='PASS';runId=$RunId;evidencePath=(Join-Path $runDir 'proof-final.json');candidateSha256=$fingerprint.candidate.sha256}|ConvertTo-Json -Depth 8 -Compress
} catch {
    $errorText = $_.Exception.Message
    try { Write-EvidenceJson -Path (Join-Path $runDir 'proof-error.json') -Value ([ordered]@{status='BLOCKED';runId=$RunId;error=$errorText;passwordLogged=$false}) } catch { }
    try { Set-CurrentProofPointer $(if($DiagnosticOnly){'DIAGNOSTIC_NOT_OBSERVED'}else{'NOT_OBSERVED'}) } catch { try { Write-EvidenceJson -Path (Join-Path $runDir 'authority-pointer-error.json') -Value ([ordered]@{status='TOOLING_ERROR';runId=$RunId;error=$_.Exception.Message;passwordLogged=$false}) } catch {} }
    [ordered]@{status='BLOCKED';runId=$RunId;error=$errorText;evidencePath=(Join-Path $runDir 'proof-error.json')}|ConvertTo-Json -Depth 8 -Compress
    $proofExitCode = 1
} finally {
    if(-not $cleanupAttempted -and $vm){$cleanupAttempted=$true;try{$cleanup=Invoke-ExactProofCleanup -Vm $vm;if([string]$cleanup.status -ne 'PASS'){$proofExitCode=1}}catch{$proofExitCode=1}}
    try { & (Join-Path $WorkspaceRoot 'tools\Update-CurrentReleaseAuthority.ps1') -Workspace $WorkspaceRoot -CurrentProofRunId $RunId | Out-Null } catch { try { Write-EvidenceJson -Path (Join-Path $runDir 'authority-refresh-error.json') -Value ([ordered]@{status='TOOLING_ERROR';runId=$RunId;error=$_.Exception.Message;passwordLogged=$false}) } catch {} }
}
if($proofExitCode -ne 0){exit $proofExitCode}
