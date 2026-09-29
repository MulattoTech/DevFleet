# DevFleet source part 036

Full-source UTF-8 byte interval [1627500, 1674000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8b31d1cef30dbcbe91ffc4a8cf8888ee366a2a206f306be74568e937dfbe5ca6

<!-- BEGIN SOURCE SLICE -->
tTo-WpfUtcInstant (Get-WpfContractValue $Report 'deadlineUtc')
        $expectedDeadline = ConvertTo-WpfUtcInstant (Get-WpfContractValue $Specification 'driverDeadlineUtc')
        if ($reportDeadline.Ticks -ne $expectedDeadline.Ticks) { $Reason.Value = 'report deadline identity mismatch'; return $false }
    } catch { $Reason.Value = 'report deadline identity is missing or malformed'; return $false }
    $sequence = 0
    if (-not [int]::TryParse([string](Get-WpfContractValue $Report 'sequence'), [ref]$sequence) -or $sequence -le $MinimumSequenceExclusive) { $Reason.Value = 'report sequence is missing or non-monotonic'; return $false }
    $status = [string](Get-WpfContractValue $Report 'status')
    if ($status -notin @('PASS','REBOOT_REQUIRED','DURABLE_PENDING','OBSERVER_HANDOFF','PRODUCT_FAILURE','FAIL','OBSERVER_FAILURE','CANCELLED')) { $Reason.Value = "report status is not terminal: $status"; return $false }
    $completion = [bool](Get-WpfContractValue $Report 'completionVerified')
    if ($status -eq 'PASS' -and -not $completion) { $Reason.Value = 'PASS omitted verified completion'; return $false }
    if ($status -ne 'PASS' -and $completion) { $Reason.Value = "$status cannot assert verified completion"; return $false }
    $cleanupDisposition = [string](Get-WpfContractValue $Report 'cleanupDisposition')
    if ($status -eq 'PASS' -and $cleanupDisposition -cne 'CLEANUP_EXACT_CANDIDATE') { $Reason.Value = 'PASS omitted exact-candidate cleanup ownership'; return $false }
    if ($status -eq 'REBOOT_REQUIRED' -and (-not [bool](Get-WpfContractValue $Report 'rebootRequired') -or $cleanupDisposition -cne 'RELINQUISH_VERIFIED_PENDING')) { $Reason.Value = 'REBOOT_REQUIRED omitted validated pending ownership'; return $false }
    if ($status -eq 'DURABLE_PENDING') {
        $basis = [string](Get-WpfContractValue $Report 'pendingBasis')
        if (-not [bool](Get-WpfContractValue $Report 'durableCompletionPending') -or
            -not [bool](Get-WpfContractValue $Report 'durableStateVerified') -or
            -not [bool](Get-WpfContractValue $Report 'ownershipTransferVerified') -or
            [bool](Get-WpfContractValue $Report 'productOutcomeClaimed') -or
            $cleanupDisposition -cne 'RELINQUISH_VERIFIED_PENDING' -or
            $basis -cne 'EXACT_TRANSACTION_DURABLE_STATE') {
            $Reason.Value = 'DURABLE_PENDING omitted validated durable product identity and ownership transfer'; return $false
        }
        if ($expectedTransaction -notmatch '^[0-9a-fA-F]{32}$') { $Reason.Value = 'durable pending omitted exact transaction identity'; return $false }
    }
    if ($status -eq 'OBSERVER_HANDOFF') {
        $basis = [string](Get-WpfContractValue $Report 'handoffBasis')
        if (-not [bool](Get-WpfContractValue $Report 'ownershipTransferVerified') -or
            [bool](Get-WpfContractValue $Report 'productOutcomeClaimed') -or
            [bool](Get-WpfContractValue $Report 'durableCompletionPending') -or
            [string](Get-WpfContractValue $Report 'observerContract') -cne 'Wait-DevFleetProductLifecycleTransition' -or
            $cleanupDisposition -cne 'RELINQUISH_LIFECYCLE_OWNER' -or
            $basis -notin @('GENERATION_ZERO_PRODUCT_OBSERVER_HANDOFF','EXACT_TRANSACTION_PRODUCT_OBSERVER_HANDOFF')) {
            $Reason.Value = 'OBSERVER_HANDOFF omitted an exact no-outcome ownership transfer'; return $false
        }
        if ($basis -eq 'EXACT_TRANSACTION_PRODUCT_OBSERVER_HANDOFF' -and $expectedTransaction -notmatch '^[0-9a-fA-F]{32}$') { $Reason.Value = 'transaction-bound handoff omitted exact transaction identity'; return $false }
        if ($basis -eq 'GENERATION_ZERO_PRODUCT_OBSERVER_HANDOFF' -and $expectedTransaction) { $Reason.Value = 'generation-zero handoff contradicted an existing transaction identity'; return $false }
    }
    return $true
}

function Resolve-WpfProviderObservation {
    param([AllowNull()][object]$ProviderValue,[Parameter(Mandatory)][ValidateSet('TERMINAL','PROGRESS')][string]$Kind,[Parameter(Mandatory)][datetime]$Now)
    if ($null -eq $ProviderValue) { return [pscustomobject]@{value=$null;establishedAtUtc=$Now;metadataValid=$true;reason=''} }
    if ([string](Get-WpfContractValue $ProviderValue 'contract') -cne 'devfleet-wpf-file-observation-v1') {
        return [pscustomobject]@{value=$ProviderValue;establishedAtUtc=$Now;metadataValid=$true;reason='collection time is the only establishment evidence'}
    }
    if ([string](Get-WpfContractValue $ProviderValue 'kind') -cne $Kind) {
        return [pscustomobject]@{value=$null;establishedAtUtc=$Now;metadataValid=$false;reason='provider observation kind mismatch'}
    }
    try { $established = ConvertTo-WpfUtcInstant (Get-WpfContractValue $ProviderValue 'fileWriteUtc') }
    catch { return [pscustomobject]@{value=$null;establishedAtUtc=$Now;metadataValid=$false;reason='provider observation fileWriteUtc is missing or malformed'} }
    if ($established -gt $Now) { return [pscustomobject]@{value=$null;establishedAtUtc=$established;metadataValid=$false;reason='provider observation claims a future file write'} }
    $value = Get-WpfContractValue $ProviderValue 'value'
    if ($null -eq $value) { return [pscustomobject]@{value=$null;establishedAtUtc=$established;metadataValid=$false;reason='provider observation omitted its value'} }
    return [pscustomobject]@{value=$value;establishedAtUtc=$established;metadataValid=$true;reason='atomic file write time'}
}

function Test-WpfBoundProgress {
    param([AllowNull()][object]$Progress,[Parameter(Mandatory)][object]$Specification,[int]$MinimumSequenceExclusive,[int]$MinimumSemanticSequenceExclusive,[ref]$Sequence,[ref]$SemanticSequence,[ref]$Reason)
    $Reason.Value='';$Sequence.Value=0;$SemanticSequence.Value=0
    if($null -eq $Progress){$Reason.Value='progress absent';return $false}
    if([string](Get-WpfContractValue $Progress 'contract') -cne 'devfleet-wpf-checkpoint-v2' -or [int](Get-WpfContractValue $Progress 'schemaVersion') -lt 2){$Reason.Value='progress contract is missing or stale';return $false}
    foreach($name in @('runId','launchId','transactionId','payloadSha256','candidateSha256')){if([string](Get-WpfContractValue $Progress $name) -cne [string](Get-WpfContractValue $Specification $name)){$Reason.Value="progress $name mismatch";return $false}}
    try{$progressDeadline=ConvertTo-WpfUtcInstant (Get-WpfContractValue $Progress 'deadlineUtc');$expectedDeadline=ConvertTo-WpfUtcInstant (Get-WpfContractValue $Specification 'driverDeadlineUtc');if($progressDeadline.Ticks-ne$expectedDeadline.Ticks){$Reason.Value='progress deadline identity mismatch';return $false}}catch{$Reason.Value='progress deadline identity is missing or malformed';return $false}
    $sequenceValue=0;if(-not[int]::TryParse([string](Get-WpfContractValue $Progress 'sequence'),[ref]$sequenceValue)-or$sequenceValue-le$MinimumSequenceExclusive){$Reason.Value='progress sequence is missing or non-monotonic';return $false}
    $Sequence.Value=$sequenceValue
    $semanticValue=0;if(-not[int]::TryParse([string](Get-WpfContractValue $Progress 'semanticProgressSequence'),[ref]$semanticValue)-or$semanticValue-le$MinimumSemanticSequenceExclusive){$Reason.Value='progress semantic sequence is missing or non-monotonic';return $false}
    $SemanticSequence.Value=$semanticValue
    if([string](Get-WpfContractValue $Progress 'semanticProgressKind') -ne 'DURABLE_PRODUCT_PROGRESS' -or [string](Get-WpfContractValue $Progress 'progressSource') -ne 'DURABLE_PRODUCT_OBSERVER'){$Reason.Value='observer breadcrumb is not durable semantic product progress';return $false}
    if([string](Get-WpfContractValue $Progress 'transactionId') -notmatch '^[0-9a-fA-F]{32}$'){$Reason.Value='durable semantic progress lacks an exact transaction identity';return $false}
    return $true
}

function Get-WpfCleanupDisposition {
    param([Parameter(Mandatory)][string]$Status, [switch]$CompletionVerified)
    switch ($Status) {
        'ALREADY_RUNNING' { return 'CONTINUE_OBSERVATION' }
        'DURABLE_PENDING' { return 'RELINQUISH_VERIFIED_PENDING' }
        'OBSERVER_HANDOFF' { return 'RELINQUISH_LIFECYCLE_OWNER' }
        'REBOOT_REQUIRED' { return 'RELINQUISH_VERIFIED_PENDING' }
        'OBSERVER_FAILURE' { return 'RELINQUISH_LIFECYCLE_OWNER' }
        'CANCELLED' { return 'RELINQUISH_LIFECYCLE_OWNER' }
        'PASS' { if ($CompletionVerified) { return 'CLEANUP_EXACT_CANDIDATE' }; return 'REJECT_INCOMPLETE_PASS' }
        default { return 'CLEANUP_EXACT_CANDIDATE' }
    }
}

function New-WpfSupervisorFailure {
    param([Parameter(Mandatory)][object]$Specification, [Parameter(Mandatory)][string]$FailureClass, [Parameter(Mandatory)][string]$Error, [Parameter(Mandatory)][datetime]$Now, [int]$LastSequence = 0, [string]$LastDurableStep = 'LAUNCH_REQUESTED')
    return [pscustomobject][ordered]@{
        schemaVersion=2; contract='devfleet-wpf-terminal-v2'; status='OBSERVER_FAILURE'; terminal=$true; completionVerified=$false; failureClass=$FailureClass; error=$Error;
        runId=[string](Get-WpfContractValue $Specification 'runId'); launchId=[string](Get-WpfContractValue $Specification 'launchId');
        transactionId=[string](Get-WpfContractValue $Specification 'transactionId'); payloadSha256=[string](Get-WpfContractValue $Specification 'payloadSha256');
        candidateSha256=[string](Get-WpfContractValue $Specification 'candidateSha256'); sequence=([Math]::Max(0,$LastSequence)+1); phase='SUPERVISOR'; lastDurableStep=$LastDurableStep; productStarted=$true;
        deadlineUtc=[string](Get-WpfContractValue $Specification 'driverDeadlineUtc'); timestampUtc=$Now.ToString('o'); cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER'
    }
}

function Invoke-WpfBoundProviderCall {
    param(
        [Parameter(Mandatory)][scriptblock]$Provider,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][ValidateRange(1,60)][int]$TimeoutSeconds
    )
    $runspace=$null
    $pipeline=$null
    $invocation=$null
    $quarantined=$false
    try {
        $runspace=[runspacefactory]::CreateRunspace()
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable('DevFleetWpfBoundProvider',$Provider)
        $pipeline=[powershell]::Create()
        $pipeline.Runspace=$runspace
        [void]$pipeline.AddScript('& $DevFleetWpfBoundProvider')
        $invocation=$pipeline.BeginInvoke()
        if (-not $invocation.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            try {
                $stopInvocation=$pipeline.BeginStop($null,$null)
                [void]$stopInvocation.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(2))
            } catch {}
            [void]$script:WpfAbandonedProviderCalls.Add([pscustomobject]@{pipeline=$pipeline;runspace=$runspace;invocation=$invocation;kind=$Kind})
            $quarantined=$true
            return [pscustomobject]@{ok=$false;timedOut=$true;value=$null;error="$Kind did not return within its bounded $TimeoutSeconds-second call window."}
        }
        try {
            $values=@($pipeline.EndInvoke($invocation))
            if($pipeline.HadErrors){
                $providerErrors=@($pipeline.Streams.Error)
                $providerError=if($providerErrors.Count){[string]$providerErrors[0].Exception.Message}else{"$Kind failed without a preserved error record."}
                return [pscustomobject]@{ok=$false;timedOut=$false;value=$null;error=$providerError}
            }
            $value=if($values.Count -eq 0){$null}elseif($values.Count -eq 1){$values[0]}else{$values}
            return [pscustomobject]@{ok=$true;timedOut=$false;value=$value;error=''}
        } catch {
            $providerErrors=@($pipeline.Streams.Error)
            $providerError=if($providerErrors.Count){[string]$providerErrors[0].Exception.Message}else{[string]$_.Exception.Message}
            return [pscustomobject]@{ok=$false;timedOut=$false;value=$null;error=$providerError}
        }
    } finally {
        if(-not$quarantined){
            if($pipeline){$pipeline.Dispose()}
            if($runspace){$runspace.Close();$runspace.Dispose()}
        }
    }
}

function Wait-WpfBoundReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Specification,
        [Parameter(Mandatory)][scriptblock]$ReportProvider,
        [Parameter(Mandatory)][scriptblock]$WorkerStateProvider,
        [Parameter(Mandatory)][scriptblock]$StopWorker,
        [scriptblock]$ProgressProvider = { $null },
        [scriptblock]$ClockProvider = { (Get-Date).ToUniversalTime() },
        [scriptblock]$SleepProvider = { param($Seconds) Start-Sleep -Seconds $Seconds },
        [ValidateRange(1,60)][int]$ProviderCallTimeoutSeconds = 30,
        [Parameter(Mandatory)][scriptblock]$TerminalWriter
    )
    $deadline = ConvertTo-WpfUtcInstant (Get-WpfContractValue $Specification 'driverDeadlineUtc')
    $semanticNoProgressSeconds = [int](Get-WpfContractValue $Specification 'semanticNoProgressSeconds')
    if ($semanticNoProgressSeconds -le 0) { throw 'WPF semantic no-progress deadline is missing or invalid.' }
    $lastRejected = ''
    $lastSequence = 0
    $lastDurableStep = 'LAUNCH_REQUESTED'
    $lastSemanticSequence = 0
    $semanticDeadline = $null
    while ($true) {
        $now = ConvertTo-WpfUtcInstant (& $ClockProvider)
        if (-not $semanticDeadline) { $semanticDeadline = $now.AddSeconds($semanticNoProgressSeconds) }
        $reportCall=Invoke-WpfBoundProviderCall -Provider $ReportProvider -Kind 'REPORT_PROVIDER' -TimeoutSeconds $ProviderCallTimeoutSeconds
        if(-not $reportCall.ok){
            try{&$StopWorker}catch{}
            $failureNow=ConvertTo-WpfUtcInstant (&$ClockProvider)
            $failureClass=if($reportCall.timedOut){'REPORT_PROVIDER_TIMEOUT'}else{'REPORT_PROVIDER_FAILURE'}
            $failure=New-WpfSupervisorFailure -Specification $Specification -FailureClass $failureClass -Error ([string]$reportCall.error) -Now $failureNow -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            &$TerminalWriter $failure|Out-Null
            return $failure
        }
        $reportObservation = Resolve-WpfProviderObservation -ProviderValue $reportCall.value -Kind TERMINAL -Now $now
        $report = $reportObservation.value
        if ($null -ne $report) {
            $reason = ''
            $validReport = Test-WpfTerminalReport -Report $report -Specification $Specification -Reason ([ref]$reason) -MinimumSequenceExclusive $lastSequence
            if ($validReport -and $reportObservation.metadataValid -and $reportObservation.establishedAtUtc -lt $deadline) { return $report }
            if ($validReport -and $reportObservation.establishedAtUtc -ge $deadline) { $reason = 'matching terminal report was first established at or after the immutable deadline' }
            if (-not $reportObservation.metadataValid) { $reason = $reportObservation.reason }
            $lastRejected = $reason
            $sameLaunch = [string](Get-WpfContractValue $report 'runId') -ceq [string](Get-WpfContractValue $Specification 'runId') -and [string](Get-WpfContractValue $report 'launchId') -ceq [string](Get-WpfContractValue $Specification 'launchId')
            if ($sameLaunch -and $now -lt $deadline) {
                $reportSequence = 0;if([int]::TryParse([string](Get-WpfContractValue $report 'sequence'),[ref]$reportSequence) -and $reportSequence -gt $lastSequence){$lastSequence=$reportSequence}
                $failure = New-WpfSupervisorFailure -Specification $Specification -FailureClass 'MALFORMED_BOUND_REPORT' -Error "Matching launch emitted an invalid terminal report: $reason" -Now $now -LastSequence $lastSequence -LastDurableStep $lastDurableStep
                & $TerminalWriter $failure | Out-Null
                return $failure
            }
        }
        if (-not $reportObservation.metadataValid) { $lastRejected = $reportObservation.reason }
        if ($now -ge $deadline) {
            & $StopWorker
            $failure = New-WpfSupervisorFailure -Specification $Specification -FailureClass 'UIA_DEADLINE_EXHAUSTED' -Error "UIA worker exceeded the finite inherited deadline. lastRejected=$lastRejected" -Now $now -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            & $TerminalWriter $failure | Out-Null
            return $failure
        }
        $progressCall=Invoke-WpfBoundProviderCall -Provider $ProgressProvider -Kind 'PROGRESS_PROVIDER' -TimeoutSeconds $ProviderCallTimeoutSeconds
        if(-not $progressCall.ok){
            try{&$StopWorker}catch{}
            $failureNow=ConvertTo-WpfUtcInstant (&$ClockProvider)
            $failureClass=if($progressCall.timedOut){'PROGRESS_PROVIDER_TIMEOUT'}else{'PROGRESS_PROVIDER_FAILURE'}
            $failure=New-WpfSupervisorFailure -Specification $Specification -FailureClass $failureClass -Error ([string]$progressCall.error) -Now $failureNow -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            &$TerminalWriter $failure|Out-Null
            return $failure
        }
        $progressObservation = Resolve-WpfProviderObservation -ProviderValue $progressCall.value -Kind PROGRESS -Now $now
        if ($progressObservation.metadataValid -and $null -ne $progressObservation.value -and $progressObservation.establishedAtUtc -lt $deadline) {
            $progressSequence=0;$semanticSequence=0;$progressReason=''
            if(Test-WpfBoundProgress -Progress $progressObservation.value -Specification $Specification -MinimumSequenceExclusive $lastSequence -MinimumSemanticSequenceExclusive $lastSemanticSequence -Sequence ([ref]$progressSequence) -SemanticSequence ([ref]$semanticSequence) -Reason ([ref]$progressReason)){
                $lastSequence=$progressSequence;$lastSemanticSequence=$semanticSequence;$lastDurableStep=[string](Get-WpfContractValue $progressObservation.value 'phase');$semanticDeadline=$now.AddSeconds($semanticNoProgressSeconds)
            }elseif($progressReason){$lastRejected=$progressReason}
        }elseif(-not $progressObservation.metadataValid){$lastRejected=$progressObservation.reason}
        $workerStateCall=Invoke-WpfBoundProviderCall -Provider $WorkerStateProvider -Kind 'WORKER_STATE_PROVIDER' -TimeoutSeconds $ProviderCallTimeoutSeconds
        if(-not $workerStateCall.ok){
            try{&$StopWorker}catch{}
            $failureNow=ConvertTo-WpfUtcInstant (&$ClockProvider)
            $failureClass=if($workerStateCall.timedOut){'WORKER_STATE_PROVIDER_TIMEOUT'}else{'WORKER_STATE_PROVIDER_FAILURE'}
            $failure=New-WpfSupervisorFailure -Specification $Specification -FailureClass $failureClass -Error ([string]$workerStateCall.error) -Now $failureNow -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            &$TerminalWriter $failure|Out-Null
            return $failure
        }
        $workerState = [string]$workerStateCall.value
        if ($workerState -in @('Exited','Failed','Stopped','Completed')) {
            # The worker can atomically publish its terminal record and exit after the
            # report poll above but before this state poll. Re-read the terminal once
            # at the exit boundary so a valid, in-deadline handoff is not misclassified
            # as EARLY_WORKER_EXIT.
            $exitReportCall=Invoke-WpfBoundProviderCall -Provider $ReportProvider -Kind 'REPORT_PROVIDER' -TimeoutSeconds $ProviderCallTimeoutSeconds
            if($exitReportCall.ok){
                $exitNow=ConvertTo-WpfUtcInstant (&$ClockProvider)
                $exitObservation=Resolve-WpfProviderObservation -ProviderValue $exitReportCall.value -Kind TERMINAL -Now $exitNow
                $exitReport=$exitObservation.value
                if($null -ne $exitReport){
                    $exitReason=''
                    $validExitReport=Test-WpfTerminalReport -Report $exitReport -Specification $Specification -Reason ([ref]$exitReason) -MinimumSequenceExclusive $lastSequence
                    if($validExitReport -and $exitObservation.metadataValid -and $exitObservation.establishedAtUtc -lt $deadline){return $exitReport}
                    if($validExitReport -and $exitObservation.establishedAtUtc -ge $deadline){$exitReason='matching terminal report was first established at or after the immutable deadline'}
                    if(-not $exitObservation.metadataValid){$exitReason=$exitObservation.reason}
                    if($exitReason){$lastRejected=$exitReason}
                }elseif(-not $exitObservation.metadataValid){$lastRejected=$exitObservation.reason}
            }else{
                $lastRejected="final terminal recheck failed: $([string]$exitReportCall.error)"
            }
            $failure = New-WpfSupervisorFailure -Specification $Specification -FailureClass 'EARLY_WORKER_EXIT' -Error "UIA worker exited before a valid terminal report. lastRejected=$lastRejected" -Now $now -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            & $TerminalWriter $failure | Out-Null
            return $failure
        }
        if ($now -ge $semanticDeadline) {
            & $StopWorker
            $failure = New-WpfSupervisorFailure -Specification $Specification -FailureClass 'UIA_SEMANTIC_NO_PROGRESS' -Error "UIA worker produced no durable semantic product progress within $semanticNoProgressSeconds seconds. lastRejected=$lastRejected" -Now $now -LastSequence $lastSequence -LastDurableStep $lastDurableStep
            & $TerminalWriter $failure | Out-Null
            return $failure
        }
        & $SleepProvider 1
    }
}

Export-ModuleMember -Function New-WpfLaunchSpecification,Copy-WpfLaunchSpecification,Assert-WpfDriverBinding,Test-WpfRegisteredTaskBinding,Test-WpfTerminalReport,Test-WpfBoundProgress,Wait-WpfBoundReport,Get-WpfCleanupDisposition,Get-WpfCandidateArguments,Get-WpfNavigationDisposition,Write-WpfAtomicJson,Get-WpfFileSha256,ConvertTo-WpfUtcInstant,ConvertTo-WpfCommandLine

```


## FILE: automation/release-e2e/tests/DependencyPolicyRunner/ArgumentAwareProcessRunner.cs

SHA256: f961705e4e4a12eceda370814e59b4fcdd6fab3871215ce8fed14232d702a25d | Bytes: 4263 | Git mode: 100644

```
using DevFleet.Setup;

namespace DependencyPolicyRunner;

public enum ProcessProbe
{
    Unknown,
    AppxPackageTrust,
    Authenticode,
    WingetVersion,
    WingetSourceList,
    WingetSearch,
    WingetDownload,
    Version,
    Other
}

public sealed record RecordedProcessInvocation(
    string FileName,
    IReadOnlyList<string> Arguments,
    string? WorkingDirectory,
    ProcessProbe IntendedProbe,
    ProcessResult Result);

internal sealed record FixtureKey(string Executable, string Arguments, ProcessProbe IntendedProbe);

/// <summary>
/// Deterministic test-only process runner. Fixtures are selected by the
/// executable, normalized argument vector, and classified probe. A missing
/// fixture is an explicit failure; it can never consume another probe's result
/// or silently turn an unmodeled operation into success.
/// </summary>
public sealed class ArgumentAwareProcessRunner : IProcessRunner
{
    private readonly Dictionary<FixtureKey, Queue<ProcessResult>> _fixtures = new();

    public List<RecordedProcessInvocation> Invocations { get; } = [];

    public void QueueResult(string fileName, IReadOnlyList<string> arguments, ProcessResult result, ProcessProbe? intendedProbe = null)
    {
        var probe = intendedProbe ?? Classify(fileName, arguments);
        var key = MakeKey(fileName, arguments, probe);
        if (!_fixtures.TryGetValue(key, out var queue))
        {
            queue = new Queue<ProcessResult>();
            _fixtures.Add(key, queue);
        }
        queue.Enqueue(result);
    }

    public ProcessResult Run(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null)
    {
        var probe = Classify(fileName, arguments);
        var key = MakeKey(fileName, arguments, probe);
        ProcessResult result;
        if (_fixtures.TryGetValue(key, out var queue) && queue.Count > 0)
        {
            result = queue.Dequeue();
        }
        else
        {
            result = new ProcessResult(127, "", $"No deterministic fixture for {probe}: {fileName} {string.Join(' ', arguments)}");
        }

        Invocations.Add(new RecordedProcessInvocation(fileName, arguments.ToArray(), workingDirectory, probe, result));
        return result;
    }

    public static ProcessProbe Classify(string fileName, IReadOnlyList<string> arguments)
    {
        var normalized = arguments.Select(argument => argument.Trim()).ToArray();
        var all = string.Join(" ", normalized);
        if (all.Contains("Get-AppxPackage", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.AppxPackageTrust;
        if (all.Contains("Get-AuthenticodeSignature", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.Authenticode;

        var executable = Path.GetFileName(fileName);
        if (executable.Equals("winget.exe", StringComparison.OrdinalIgnoreCase))
        {
            if (normalized.SequenceEqual(["--version"], StringComparer.OrdinalIgnoreCase)) return ProcessProbe.WingetVersion;
            if (normalized.Length >= 2 && normalized[0].Equals("source", StringComparison.OrdinalIgnoreCase) && normalized[1].Equals("list", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.WingetSourceList;
            if (normalized.Length >= 1 && normalized[0].Equals("search", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.WingetSearch;
            if (normalized.Length >= 1 && normalized[0].Equals("download", StringComparison.OrdinalIgnoreCase)) return ProcessProbe.WingetDownload;
        }
        if (normalized.SequenceEqual(["--version"], StringComparer.OrdinalIgnoreCase)) return ProcessProbe.Version;
        return ProcessProbe.Other;
    }

    private static FixtureKey MakeKey(string fileName, IReadOnlyList<string> arguments, ProcessProbe probe)
        => new(NormalizeExecutable(fileName), NormalizeArguments(arguments), probe);

    private static string NormalizeExecutable(string fileName)
    {
        try { return Path.GetFullPath(fileName).TrimEnd(Path.DirectorySeparatorChar).ToUpperInvariant(); }
        catch { return fileName.Trim().ToUpperInvariant(); }
    }

    private static string NormalizeArguments(IReadOnlyList<string> arguments)
        => string.Join("\u001f", arguments.Select(argument => argument.Trim()));
}

```


## FILE: automation/release-e2e/tests/DependencyPolicyRunner/DependencyPolicyRunner.csproj

SHA256: 66171a9c8d3bad0472e75ec38cfa7045fd42c8e234525e4c971162f7c83d4f36 | Bytes: 924 | Git mode: 100644

```
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <EnableWindowsTargeting>true</EnableWindowsTargeting>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <!-- The referenced installer is a self-contained WinExe. Keep this
         executable in the same RID graph so NETSDK1151 cannot silently
         discard the real project reference. -->
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../../../../installer-source/DevFleet.Setup/DevFleet.Setup.csproj"
                      GlobalPropertiesToRemove="SelfContained;RuntimeIdentifier;PublishSingleFile"
                      AdditionalProperties="SelfContained=false;RuntimeIdentifier=;PublishSingleFile=false" />
  </ItemGroup>
</Project>

```


## FILE: automation/release-e2e/tests/DependencyPolicyRunner/Program.cs

SHA256: a2a05ddc6b7f7546d10955366ae3aea016031f2139796d86388520be47e8f188 | Bytes: 17382 | Git mode: 100644

```
using System.Net;
using System.Net.Http;
using DevFleet.Setup;
using DependencyPolicyRunner;

if (args.Contains("--runner-self-test", StringComparer.OrdinalIgnoreCase))
{
    RunRunnerSelfTest();
    return;
}

static object Row(string scenario, string branch, bool reached, ArgumentAwareProcessRunner runner, string? selectedFallback = null, string? detail = null, bool physicalPathExists = false)
    => new {
        scenario,
        requestedScenario = scenario,
        actualResolverBranch = branch,
        queuedProcessOutputs = runner.Invocations.Select(i => new { i.FileName, arguments = i.Arguments, intendedProbe = i.IntendedProbe.ToString(), result = i.Result }).ToArray(),
        actualInvocations = runner.Invocations.Count,
        selectedFallback,
        detectedVersionOrPath = detail,
        physicalPathExists,
        authenticityProbeReached = runner.Invocations.Any(i => i.IntendedProbe == ProcessProbe.Authenticode),
        versionProbeReached = runner.Invocations.Any(i => i.IntendedProbe is ProcessProbe.Version or ProcessProbe.WingetVersion),
        trustedPathPolicyReached = runner.Invocations.Count > 0,
        expectedOutcome = "policy branch exercised and fails closed on mismatch",
        actualOutcome = reached ? "intended branch reached" : "intended branch not reached",
        actualConditionProven = reached,
        status = reached ? "PASS" : "FAIL",
        evidenceClass = "ADVERSARIAL_PRODUCT_POLICY"
    };

var rows = new List<object>();

// Missing WinGet is a real resolver call with a process-scoped empty PATH.
var originalPath = Environment.GetEnvironmentVariable("PATH");
try
{
    Environment.SetEnvironmentVariable("PATH", "");
    var missingRunner = new ArgumentAwareProcessRunner();
    var missing = new DependencyService(missingRunner).GetWingetHealth();
    rows.Add(Row("WinGet-Missing", missing.Status, missing.Status == "Missing", missingRunner, detail: missing.Detail));
}
finally { Environment.SetEnvironmentVariable("PATH", originalPath); }

// These cases use the real dependency resolver with argument-aware fixtures.
// The AppX and Authenticode probes are keyed separately from the WinGet
// operation, so they cannot consume --version/source/search results.
foreach (var (scenario, expected) in new[] {
    ("WinGet-Broken", "Broken"),
    ("WinGet-Source-Broken", "SourceBroken")
})
{
    var runner = new ArgumentAwareProcessRunner();
    var physicalWinget = LocatePhysicalWingetPackage();
    ConfigureWingetFixtures(runner, scenario);
    var health = new DependencyService(runner).GetWingetHealth();
    rows.Add(Row(scenario, health.Status, health.Status.Equals(expected, StringComparison.OrdinalIgnoreCase), runner, detail: health.Detail, physicalPathExists: File.Exists(physicalWinget.Executable)));
}

// Official direct fallback is exercised with the real HttpClient injection,
// using an allowlisted synthetic metadata response and no machine mutation.
var fallbackRunner = new ArgumentAwareProcessRunner();
var handler = new StubHandler();
using var http = new HttpClient(handler);
var dependency = new DependencyDefinition {
    Id = "fixture-direct",
    DisplayName = "Fixture Direct",
    DirectOfficialVendorResolver = new OfficialResolver {
        Type = "official-download-page",
        MetadataUri = "https://downloads.example.invalid/release.json",
        DirectUri = "https://downloads.example.invalid/fixture.exe",
        AllowedHosts = ["downloads.example.invalid"],
        AssetRegex = "^fixture\\.exe$"
    }
};
var fallbackRoot = Path.Combine(Path.GetTempPath(), "devfleet-policy-runner-" + Guid.NewGuid().ToString("N"));
var fallbackPath = new DependencyService(fallbackRunner, http).DownloadOfficial(dependency, fallbackRoot);
var fallbackReached = File.Exists(fallbackPath) && string.Equals(Path.GetFileName(fallbackPath), "fixture.exe", StringComparison.OrdinalIgnoreCase);
rows.Add(Row("Official-Direct-Fallback", "DirectOfficialFallback", fallbackReached, fallbackRunner, selectedFallback: fallbackPath, detail: handler.LastUri));
try { Directory.Delete(fallbackRoot, recursive: true); } catch { }

// Nonstandard-path detection selects only a physically existing executable
// from real machine roots.  The selection is deliberately not a temp fixture:
// Detect() remains the authority for the unmodified shipping trust policy.
var nonstandardRunner = new ArgumentAwareProcessRunner();
var trustedFixtureCandidates = new[] {
    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe"),
    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "where.exe"),
    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
}.Where(File.Exists).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
var trustedFixturePath = trustedFixtureCandidates.FirstOrDefault();
if (trustedFixturePath is null) {
    rows.Add(Row("Valid-Nonstandard-Path", "TrustedDiscoveryCompatible", false, nonstandardRunner, detail: "No physically existing executable was available in a real trusted-root candidate set.", physicalPathExists: false));
    rows.Add(Row("Outdated-Prerequisites", "OutdatedVersion", false, nonstandardRunner, detail: "No physically existing executable was available in a real trusted-root candidate set.", physicalPathExists: false));
    goto Emit;
}
QueueAuthenticodeFixture(nonstandardRunner, trustedFixturePath, new ProcessResult(1, "", "unsigned fixture is accepted by the explicit test policy"));
nonstandardRunner.QueueResult(trustedFixturePath, ["--version"], new ProcessResult(0, "7.4.0", ""));
var nonstandard = new DependencyService(nonstandardRunner).Detect(new DependencyDefinition {
    Id = "fixture-path", DisplayName = "Fixture Path", KnownVendorInstallLocations = [trustedFixturePath],
    MinimumSupportedVersion = "1.0.0", VersionProbe = new VersionProbe { Regex = "(\\d+\\.\\d+)" },
    InstallerAuthenticityPolicy = new InstallerAuthenticityPolicy { InstalledExecutableTrust = "signed-installer-locked-path" }
});
var nonstandardReached = nonstandard.Found && nonstandard.Version is not null && nonstandard.Compatible
    && string.Equals(nonstandard.ExecutablePath, trustedFixturePath, StringComparison.OrdinalIgnoreCase)
    && nonstandardRunner.Invocations.Count >= 2;
rows.Add(Row("Valid-Nonstandard-Path", "TrustedDiscoveryCompatible", nonstandardReached, nonstandardRunner, detail: $"{nonstandard.ExecutablePath}|version={nonstandard.Version}", physicalPathExists: File.Exists(trustedFixturePath)));

// Outdated prerequisites is represented by a real incompatible detection.
var outdatedRunner = new ArgumentAwareProcessRunner();
QueueAuthenticodeFixture(outdatedRunner, trustedFixturePath, new ProcessResult(1, "", "unsigned fixture is accepted by the explicit test policy"));
outdatedRunner.QueueResult(trustedFixturePath, ["--version"], new ProcessResult(0, "1.0.0", ""));
var outdated = new DependencyService(outdatedRunner).Detect(new DependencyDefinition {
    Id = "fixture-outdated", DisplayName = "Fixture Outdated", KnownVendorInstallLocations = [trustedFixturePath],
    MinimumSupportedVersion = "99.0.0", VersionProbe = new VersionProbe { Regex = "(\\d+\\.\\d+)" },
    InstallerAuthenticityPolicy = new InstallerAuthenticityPolicy { InstalledExecutableTrust = "signed-installer-locked-path" }
});
var outdatedReached = outdated.Found && outdated.Version is not null && outdated.Version < new Version("99.0.0")
    && !outdated.Compatible && outdated.Classification.Length > 0 && outdatedRunner.Invocations.Count >= 2;
rows.Add(Row("Outdated-Prerequisites", "OutdatedVersion", outdatedReached, outdatedRunner, detail: $"{outdated.ExecutablePath}|version={outdated.Version}|minimum=99.0.0", physicalPathExists: File.Exists(trustedFixturePath)));
Emit:
Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(rows));
var requiredScenarios = new[] { "WinGet-Missing", "WinGet-Broken", "WinGet-Source-Broken", "Official-Direct-Fallback", "Valid-Nonstandard-Path", "Outdated-Prerequisites" };
var actualScenarios = rows.Select(row => (string)row.GetType().GetProperty("scenario")!.GetValue(row)! ).ToArray();
if (actualScenarios.Length != requiredScenarios.Length || actualScenarios.Distinct(StringComparer.Ordinal).Count() != requiredScenarios.Length ||
    !requiredScenarios.All(id => actualScenarios.Contains(id, StringComparer.Ordinal)))
    Environment.ExitCode = 2;
if (rows.Any(row => !(bool)row.GetType().GetProperty("actualConditionProven")!.GetValue(row)!))
    Environment.ExitCode = 1;

static void ConfigureWingetFixtures(ArgumentAwareProcessRunner runner, string scenario)
{
    var (packageRoot, winget) = LocatePhysicalWingetPackage();
    var powershell = GetPowerShellPath();
    var appxArguments = new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", "Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' | ForEach-Object { Join-Path $_.InstallLocation 'winget.exe' }" };
    runner.QueueResult(powershell, appxArguments,
        new ProcessResult(0, winget, ""), ProcessProbe.AppxPackageTrust);
    var packageIdentityArguments = new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", "Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' | ForEach-Object { $_.Name + '|' + $_.PublisherId + '|' + $_.InstallLocation }" };
    runner.QueueResult(powershell, packageIdentityArguments,
        new ProcessResult(0, $"Microsoft.DesktopAppInstaller|8wekyb3d8bbwe|{packageRoot}", ""), ProcessProbe.AppxPackageTrust);
    QueueAuthenticodeFixture(runner, winget,
        new ProcessResult(0, "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US", ""));

    if (scenario.Equals("WinGet-Broken", StringComparison.OrdinalIgnoreCase))
    {
        runner.QueueResult(winget, ["--version"], new ProcessResult(1, "", "fixture winget failure"), ProcessProbe.WingetVersion);
        return;
    }

    runner.QueueResult(winget, ["--version"], new ProcessResult(0, "v1.9.0", ""), ProcessProbe.WingetVersion);
    runner.QueueResult(winget, ["source", "list", "--disable-interactivity"], new ProcessResult(1, "", "fixture source failure"), ProcessProbe.WingetSourceList);
}

static (string PackageRoot, string Executable) SelectPhysicalWingetPackage(IEnumerable<string> directories, string windowsApps)
{
    var appsRoot = Path.GetFullPath(windowsApps).TrimEnd(Path.DirectorySeparatorChar);
    const string prefix = "Microsoft.DesktopAppInstaller_";
    const string suffix = "_x64__8wekyb3d8bbwe";
    var matches = directories
        .Select(path => Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar))
        .Where(path => string.Equals(Path.GetDirectoryName(path)?.TrimEnd(Path.DirectorySeparatorChar), appsRoot, StringComparison.OrdinalIgnoreCase))
        .Where(path => !new DirectoryInfo(path).Attributes.HasFlag(FileAttributes.ReparsePoint))
        .Select(path => {
            var basename = Path.GetFileName(path);
            var versionText = basename.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) && basename.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)
                ? basename[prefix.Length..^suffix.Length]
                : "";
            return (Root: path, Version: Version.TryParse(versionText, out var version) ? version : null as Version, Executable: Path.Combine(path, "winget.exe"));
        })
        .Where(item => item.Version is not null && File.Exists(item.Executable) && !File.GetAttributes(item.Executable).HasFlag(FileAttributes.ReparsePoint))
        .OrderByDescending(item => item.Version)
        .ThenBy(item => item.Root, StringComparer.OrdinalIgnoreCase)
        .ToArray();
    if (matches.Length == 0) throw new InvalidOperationException("No physical Microsoft.DesktopAppInstaller x64 package with winget.exe was found.");
    return (matches[0].Root, matches[0].Executable);
}

static (string PackageRoot, string Executable) LocatePhysicalWingetPackage()
{
    if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("The dependency matrix requires the Windows physical WinGet package.");
    var windowsApps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsApps");
    return SelectPhysicalWingetPackage(
        Directory.EnumerateDirectories(windowsApps, "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe", SearchOption.TopDirectoryOnly),
        windowsApps);
}

static void QueueAuthenticodeFixture(ArgumentAwareProcessRunner runner, string executable, ProcessResult result)
{
    var escaped = executable.Replace("'", "''", StringComparison.Ordinal);
    var command = "$s=Get-AuthenticodeSignature -LiteralPath '" + escaped + "'; if($s.Status -ne 'Valid'){exit 9}; $s.SignerCertificate.Subject";
    runner.QueueResult(GetPowerShellPath(),
        ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command], result, ProcessProbe.Authenticode);
}

static string GetPowerShellPath()
{
    var candidates = new[]
    {
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    };
    return candidates.FirstOrDefault(File.Exists) ?? "pwsh.exe";
}

static void RunRunnerSelfTest()
{
    var winget = @"C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe";
    var runner = new ArgumentAwareProcessRunner();
    runner.QueueResult(winget, [" --version "], new ProcessResult(1, "", "exact version failure"), ProcessProbe.WingetVersion);
    runner.QueueResult(winget, ["source", "list", "--disable-interactivity"], new ProcessResult(0, "source-ok", ""), ProcessProbe.WingetSourceList);

    // Deliberately call source before version: keyed dispatch must preserve
    // each fixture's intended operation instead of consuming FIFO output.
    var source = runner.Run(winget, ["source", "list", "--disable-interactivity"]);
    var version = runner.Run(winget, ["--version"]);
    var unknown = runner.Run(winget, ["search", "--id", "fixture"]);
    if (source.ExitCode != 0 || source.StandardOutput != "source-ok" || source != runner.Invocations[0].Result ||
        version.ExitCode != 1 || version.StandardError != "exact version failure" || version != runner.Invocations[1].Result ||
        unknown.ExitCode != 127 || runner.Invocations.Count != 3 ||
        runner.Invocations[0].IntendedProbe != ProcessProbe.WingetSourceList ||
        runner.Invocations[1].IntendedProbe != ProcessProbe.WingetVersion ||
        runner.Invocations[2].IntendedProbe != ProcessProbe.WingetSearch)
        throw new InvalidOperationException("Argument-aware process runner self-test failed.");

    var selectionRoot = Path.Combine(Path.GetTempPath(), "devfleet-winget-selection-" + Guid.NewGuid().ToString("N"));
    var selectionWindowsApps = Path.Combine(selectionRoot, "WindowsApps");
    var selectionPackages = new[] {
        Path.Combine(selectionWindowsApps, "Microsoft.DesktopAppInstaller_1.0.0.0_x64__8wekyb3d8bbwe"),
        Path.Combine(selectionWindowsApps, "Microsoft.DesktopAppInstaller_1.0.0.1_x64__8wekyb3d8bbwe")
    };
    Directory.CreateDirectory(selectionWindowsApps);
    try
    {
        foreach (var package in selectionPackages)
        {
            Directory.CreateDirectory(package);
            File.WriteAllText(Path.Combine(package, "winget.exe"), "fixture");
        }
        var selected = SelectPhysicalWingetPackage(selectionPackages, selectionWindowsApps);
        if (!selected.PackageRoot.EndsWith("1.0.0.1_x64__8wekyb3d8bbwe", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Physical WinGet package selection did not choose the highest valid package version.");
    }
    finally { try { Directory.Delete(selectionRoot, recursive: true); } catch { } }

    Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new
    {
        status = "PASS",
        contract = "executable+normalized-arguments+intended-probe",
        invocationOrder = runner.Invocations.Select(i => new { i.IntendedProbe, i.FileName, arguments = i.Arguments, result = i.Result }).ToArray(),
        missingFixture = new { unknown.ExitCode, unknown.StandardError }
    }));
}

sealed class StubHandler : HttpMessageHandler
{
    public string LastUri { get; private set; } = "";
    private HttpResponseMessage Build(HttpRequestMessage request)
    {
        LastUri = request.RequestUri?.ToString() ?? "";
        var content = request.RequestUri?.AbsolutePath.EndsWith("fixture.exe", StringComparison.OrdinalIgnoreCase) == true
            ? new ByteArrayContent([0x4d, 0x5a, 0x46, 0x49, 0x58, 0x54, 0x55, 0x52, 0x45])
            : new StringContent("{\"tag_name\":\"fixture\",\"assets\":[]}");
        return new HttpResponseMessage(HttpStatusCode.OK) { Content = content };
    }
    protected override HttpResponseMessage Send(HttpRequestMessage request, CancellationToken cancellationToken) => Build(request);
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        => Task.FromResult(Build(request));
}

```


## FILE: automation/release-e2e/tests/Invoke-HarnessTests.ps1

SHA256: 59d3982927f6d3637514917b0db42b974c38cec9e64c17fc7ee3fff1bdc496e8 | Bytes: 61808 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
$moduleRoot=Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\modules')).Path ''
foreach($m in @('Candidate','HostSafety','ResumeState','Cleanup','Evidence','FullRelease','HarnessBudget')){Import-Module (Join-Path $moduleRoot "$m.psm1") -Force}
$total=0;$passed=0;$failures=[System.Collections.Generic.List[string]]::new()
function Assert-That([bool]$Condition,[string]$Name){$script:total++;if($Condition){$script:passed++}else{$script:failures.Add($Name)}}
function Assert-DisposableNameTest([string]$Name) { return $Name -like 'DevFleet-E2E-*' }
function Get-HarnessCandidateFingerprint([string]$Root) {
    try { return Get-CandidateFingerprint -WorkspaceRoot $Root }
    catch {
        if ($_.Exception.Message -ne 'Candidate evidence says the candidate is stale or requires rebuild.') { throw }
        $version=(Get-Content -LiteralPath (Join-Path $Root 'source\VERSION') -Raw).Trim()
        $outputs=Join-Path $Root 'outputs'
        $exe=@(Get-ChildItem -LiteralPath $outputs -Filter "DevFleet-Setup-v$version-w