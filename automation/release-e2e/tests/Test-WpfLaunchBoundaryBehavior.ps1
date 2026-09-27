[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }

$modulePath = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\WpfLaunchContract.psm1'
$driverPath = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-WpfUiAutomation.ps1'
$passed = 0
$failures = [System.Collections.Generic.List[string]]::new()
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("devfleet-wpf-boundary-test-{0}" -f [guid]::NewGuid().ToString('N'))

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Import-Module $modulePath -Force

    $driverTokens = $null
    $driverParseErrors = $null
    $driverAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $driverPath).Path,
        [ref]$driverTokens,
        [ref]$driverParseErrors
    )
    $readObservedAst = $driverAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'Read-ObservedJsonFile'
    }, $true)
    Check (@($driverParseErrors).Count -eq 0 -and $null -ne $readObservedAst) 'WPF driver observation helper remains parseable and discoverable'
    if ($null -ne $readObservedAst) {
        $readObservedText = [string]$readObservedAst.Extent.Text
        $inaccessibleObservation = & {
            function Test-Path { throw [System.UnauthorizedAccessException]::new('Access is denied') }
            Invoke-Expression $readObservedText
            Read-ObservedJsonFile -Path 'C:\blocked-observation' -Kind TERMINAL
        }
        Check ($null -eq $inaccessibleObservation) 'inaccessible observation files are treated as absent so the bounded WPF watchdog can retry'
        $observedJsonPath=Join-Path $scratch 'observed-terminal.json'
        [IO.File]::WriteAllText($observedJsonPath,'{"status":"PASS"}'+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
        $observedWithoutContentProvider=& {
            function Get-Content { throw [InvalidOperationException]::new('Get-Content must not own atomic WPF observation reads') }
            Invoke-Expression $readObservedText
            Read-ObservedJsonFile -Path $observedJsonPath -Kind TERMINAL
        }
        Check ([string]$observedWithoutContentProvider.value.status -ceq 'PASS') 'atomic WPF terminal/progress observation reads do not depend on the stalled PowerShell content provider'
    }

    $readBootstrapAst = $driverAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'Read-BootstrapLaunchSpecification'
    }, $true)
    Check ($null -ne $readBootstrapAst) 'WPF bootstrap request reader remains parseable and discoverable'
    if ($null -ne $readBootstrapAst) {
        $readBootstrapText = [string]$readBootstrapAst.Extent.Text
        $bootstrapRequestPath = Join-Path $scratch 'bootstrap-read-request.json'
        [IO.File]::WriteAllText($bootstrapRequestPath, '{"candidateSha256":"' + ('a' * 64) + '"}' + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        $bootstrapRead = & {
            function Get-Content { throw [InvalidOperationException]::new('Get-Content must not be used for task-context bootstrap reads') }
            Invoke-Expression $readBootstrapText
            Read-BootstrapLaunchSpecification -Path $bootstrapRequestPath -DeadlineUtc ([DateTime]::UtcNow.AddMinutes(1).ToString('o'))
        }
        Check ([string]$bootstrapRead.candidateSha256 -ceq ('a' * 64)) 'task-context bootstrap request reader uses bounded .NET file I/O rather than the hanging PowerShell content provider'
        $absentRequestFailure='';try{& {Invoke-Expression $readBootstrapText;Read-BootstrapLaunchSpecification -Path (Join-Path $scratch 'absent-request.json') -DeadlineUtc ([DateTimeOffset]::UtcNow.AddMilliseconds(900).ToString('o'))}|Out-Null}catch{$absentRequestFailure=$_.Exception.Message}
        Check ($absentRequestFailure -match 'did not become visible before the bounded bootstrap deadline') 'absent launch request fails within its inherited bootstrap deadline'
        $corruptRequestPath=Join-Path $scratch 'corrupt-request.json';[IO.File]::WriteAllText($corruptRequestPath,'{"schemaVersion":',[Text.UTF8Encoding]::new($false))
        $corruptRequestFailure='';try{& {Invoke-Expression $readBootstrapText;Read-BootstrapLaunchSpecification -Path $corruptRequestPath -DeadlineUtc ([DateTimeOffset]::UtcNow.AddSeconds(2).ToString('o'))}|Out-Null}catch{$corruptRequestFailure=$_.Exception.Message}
        Check ($corruptRequestFailure -match 'was not readable before the bounded bootstrap deadline') 'corrupt launch request fails within its inherited bootstrap deadline'
    }

    foreach($role in @('Primary / Desktop','Laptop / Surrogate')){
        foreach($mode in @('initial','direct','resume')){
            $arguments=Get-WpfCandidateArguments -LaunchMode $mode -Action FreshInstall -Role $role -ElevatedResume:($mode-eq'resume')
            Check (($arguments-contains'--defer-network-pairing')-eq($role-eq'Primary / Desktop')) "$role $mode honors supported network-pairing choice"
            Check ($arguments[$arguments.IndexOf('--role')+1]-ceq$role) "$role $mode preserves exact reviewed role"
        }
    }

    $now = [datetime]'2026-09-05T20:00:00Z'
    $ownerDeadline = $now.AddSeconds(480)
    $common = @{
        DriverPath = $driverPath
        ExePath = (Get-Command powershell.exe).Source
        Action = 'FreshInstall'
        Role = 'Primary / Desktop'
        OutputPath = (Join-Path $scratch 'final.json')
        StartedPath = (Join-Path $scratch 'started.json')
        CheckpointPath = (Join-Path $scratch 'checkpoint.json')
        WorkerResultPath = (Join-Path $scratch 'worker.json')
        LaunchRequestPath = (Join-Path $scratch 'request.json')
        RunId = 'wpf-boundary-regression'
        LaunchId = ('1' * 32)
        TransactionId = ('2' * 32)
        PayloadSha256 = ('3' * 64)
        ExpectedInteractiveSessionId = 1
        AllowMutation = $true
        AllowRebootRequired = $true
        OwnerDeadlineUtc = $ownerDeadline
        ClockProvider = { $now }
    }

    $resume = New-WpfLaunchSpecification @common -LaunchMode resume -ElevatedResume
    Check ($resume.taskArguments -match '(?:^| )-ElevatedResume(?: |$)' -and $resume.taskArguments -match '-LaunchMode (?:"resume"|resume)') 'resume mode reaches the actual driver task arguments'
    Check (@($resume.candidateArguments)[0] -eq '--elevated-resume') 'resume mode reaches the actual candidate argument vector'
    Check ([datetime]$resume.boundaryDeadlineUtc -eq $ownerDeadline -and [datetime]$resume.driverDeadlineUtc -lt $ownerDeadline) 'child and terminalization deadlines consume the finite remaining owner budget'
    $actualBinding=@{ExePath=$resume.exePath;Action=$resume.action;Role=$resume.role;OutputPath=$resume.outputPath;StartedPath=$resume.startedPath;CheckpointPath=$resume.checkpointPath;WorkerResultPath=$resume.workerResultPath;LaunchRequestPath=$resume.launchRequestPath;RunId=$resume.runId;LaunchId=$resume.launchId;TransactionId=$resume.transactionId;PayloadSha256=$resume.payloadSha256;LaunchMode=$resume.launchMode;ObserverDeadlineUtc=$resume.driverDeadlineUtc;ExpectedInteractiveSessionId=$resume.expectedInteractiveSessionId;AllowMutation=$resume.allowMutation;AllowRebootRequired=$resume.allowRebootRequired;UseDurableCompletionFallback=$resume.useDurableCompletionFallback;ElevatedResume=$resume.elevatedResume;ContractProbe=$resume.contractProbe;ContractModulePath=''}
    $wrongRunBinding=@{}+$actualBinding;$wrongRunBinding.RunId='wrong-run';$wrongRunRejected=$false;try{Assert-WpfDriverBinding -Specification $resume -Actual $wrongRunBinding|Out-Null}catch{$wrongRunRejected=$_.Exception.Message -match 'runId'}
    Check $wrongRunRejected 'launch request with a wrong run identity is rejected before product start'
    $wrongHashSpec=$resume|Select-Object *;$wrongHashSpec.candidateSha256='f'*64;$wrongHashRejected=$false;try{Assert-WpfDriverBinding -Specification $wrongHashSpec -Actual $actualBinding|Out-Null}catch{$wrongHashRejected=$_.Exception.Message -match 'candidate hash'}
    Check $wrongHashRejected 'launch request with a wrong candidate hash is rejected before product start'

    $handoffCommon = @{} + $common
    $handoffCommon.LaunchId = ('d' * 32)
    $handoffCommon.OutputPath = Join-Path $scratch 'handoff-final.json'
    $handoffCommon.StartedPath = Join-Path $scratch 'handoff-started.json'
    $handoffCommon.CheckpointPath = Join-Path $scratch 'handoff-checkpoint.json'
    $handoffCommon.WorkerResultPath = Join-Path $scratch 'handoff-worker.json'
    $handoffCommon.LaunchRequestPath = Join-Path $scratch 'handoff-request.json'
    $handoffSpec = New-WpfLaunchSpecification @handoffCommon -LaunchMode resume -ElevatedResume -UseDurableCompletionFallback -ContractProbe
    Write-WpfAtomicJson -Path $handoffSpec.launchRequestPath -Value $handoffSpec
    $handoffProbe = Start-Process -FilePath $handoffSpec.taskExecutable -ArgumentList ([string]$handoffSpec.taskArguments) -PassThru -Wait
    $handoffProbeReport = Get-Content -LiteralPath $handoffSpec.outputPath -Raw | ConvertFrom-Json
    Check ($handoffProbe.ExitCode -eq 0 -and [string]$handoffProbeReport.status -eq 'CONTRACT_PROBE_PASS') 'resume product-observer handoff survives actual task argument construction and driver parsing'
    $pageSeparator=[char]0x00B7
    Check ((Get-WpfNavigationDisposition -LaunchMode initial -ElevatedResume $false -WindowOwnerMatches $true -PageKicker "STEP 1 OF 8 $pageSeparator WELCOME" -OperationStatus '' -NextEnabled $true -ExecutePresent $false -ExecuteEnabled $false) -eq 'NAVIGATE') 'initial launch navigates only when the exact owned window exposes Next'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $true -PageKicker "STEP 1 OF 8 $pageSeparator WELCOME" -OperationStatus '' -NextEnabled $true -ExecutePresent $false -ExecuteEnabled $false) -eq 'WAIT') 'elevated resume ignores a transient pre-auto-execution Next control'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $true -PageKicker "STEP 7 OF 8 $pageSeparator EXECUTE" -OperationStatus 'Invoking actual installer lifecycle' -NextEnabled $false -ExecutePresent $true -ExecuteEnabled $false) -eq 'OBSERVE_EXISTING') 'elevated resume observes the exact owned in-flight auto-execution page'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $true -PageKicker "STEP 7 OF 8 $pageSeparator EXECUTE" -OperationStatus 'Reboot required; checkpoint preserved' -NextEnabled $false -ExecutePresent $true -ExecuteEnabled $true) -eq 'OBSERVE_EXISTING') 'elevated resume observes terminal reboot state even after Execute is re-enabled'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $true -PageKicker "STEP 8 OF 8 $pageSeparator FINISH" -OperationStatus 'Completed and verified' -NextEnabled $false -ExecutePresent $false -ExecuteEnabled $false) -eq 'OBSERVE_EXISTING') 'elevated resume observes an already-completed Finish page'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $false -PageKicker "STEP 7 OF 8 $pageSeparator EXECUTE" -OperationStatus 'Completed and verified' -NextEnabled $false -ExecutePresent $true -ExecuteEnabled $true) -eq 'REJECT_OWNER_MISMATCH') 'post-launch window ownership divergence is rejected immediately'

    $longOwnerCommon = @{} + $common
    $longOwnerCommon.OwnerDeadlineUtc = $now.AddSeconds(2400)
    $longOwnerCommon.LaunchId = ('c' * 32)
    $longOwner = New-WpfLaunchSpecification @longOwnerCommon -LaunchMode resume -ElevatedResume -SemanticNoProgressSeconds 1800
    Check ([datetime]$longOwner.driverDeadlineUtc -eq ([datetime]$longOwner.ownerDeadlineUtc).AddSeconds(-60) -and [int]$longOwner.semanticNoProgressSeconds -eq 1800) 'WPF launch inherits the owner deadline and configured semantic no-progress budget without a hidden clamp'

    $bootstrapRoot = Join-Path $scratch 'bootstrap-failure'
    New-Item -ItemType Directory -Path $bootstrapRoot -Force | Out-Null
    $bootstrapDriver = Join-Path $bootstrapRoot 'Invoke-WpfUiAutomation.ps1'
    Copy-Item -LiteralPath $driverPath -Destination $bootstrapDriver -Force
    $bootstrapCommon = @{} + $common
    $bootstrapCommon.DriverPath = $bootstrapDriver
    $bootstrapCommon.OutputPath = Join-Path $bootstrapRoot 'terminal.json'
    $bootstrapCommon.StartedPath = Join-Path $bootstrapRoot 'started.json'
    $bootstrapCommon.CheckpointPath = Join-Path $bootstrapRoot 'checkpoint.json'
    $bootstrapCommon.WorkerResultPath = Join-Path $bootstrapRoot 'worker.json'
    $bootstrapCommon.LaunchRequestPath = Join-Path $bootstrapRoot 'request.json'
    $bootstrapCommon.LaunchId = ('b' * 32)
    $bootstrapSpec = New-WpfLaunchSpecification @bootstrapCommon -LaunchMode initial -ContractProbe
    Write-WpfAtomicJson -Path $bootstrapSpec.launchRequestPath -Value $bootstrapSpec
    $bootstrapProcess = Start-Process -FilePath $bootstrapSpec.taskExecutable -ArgumentList ([string]$bootstrapSpec.taskArguments) -PassThru -Wait
    $bootstrapReport = Get-Content -LiteralPath $bootstrapSpec.outputPath -Raw | ConvertFrom-Json
    Check ($bootstrapProcess.ExitCode -eq 2 -and [string]$bootstrapReport.status -eq 'OBSERVER_FAILURE' -and [string]$bootstrapReport.failureClass -eq 'DRIVER_BOOTSTRAP_FAILURE' -and [bool]$bootstrapReport.terminal -and -not [bool]$bootstrapReport.completionVerified -and [string]$bootstrapReport.runId -ceq $bootstrapSpec.runId -and [string]$bootstrapReport.launchId -ceq $bootstrapSpec.launchId -and [string]$bootstrapReport.payloadSha256 -ceq $bootstrapSpec.payloadSha256 -and [string]$bootstrapReport.candidateSha256 -ceq $bootstrapSpec.candidateSha256 -and $bootstrapReport.productStarted -eq $false -and -not [bool]$bootstrapReport.mutationInvoked -and -not (Test-Path -LiteralPath $bootstrapSpec.startedPath)) 'actual driver publishes an identity-bound terminal with productStarted=false before candidate launch when contract bootstrap fails'

    $delayedRoot = Join-Path $scratch 'delayed-launch-request'
    New-Item -ItemType Directory -Path $delayedRoot -Force | Out-Null
    $delayedDriver = Join-Path $delayedRoot 'Invoke-WpfUiAutomation.ps1'
    Copy-Item -LiteralPath $driverPath -Destination $delayedDriver -Force
    Copy-Item -LiteralPath $modulePath -Destination (Join-Path $delayedRoot 'WpfLaunchContract.psm1') -Force
    $delayedCommon = @{} + $common
    $delayedCommon.DriverPath = $delayedDriver
    $delayedCommon.OutputPath = Join-Path $delayedRoot 'terminal.json'
    $delayedCommon.StartedPath = Join-Path $delayedRoot 'started.json'
    $delayedCommon.CheckpointPath = Join-Path $delayedRoot 'checkpoint.json'
    $delayedCommon.WorkerResultPath = Join-Path $delayedRoot 'worker.json'
    $delayedCommon.LaunchRequestPath = Join-Path $delayedRoot 'request.json'
    $delayedCommon.LaunchId = ('8' * 32)
    $delayedCommon.ClockProvider = { (Get-Date).ToUniversalTime() }
    $delayedCommon.OwnerDeadlineUtc = (Get-Date).ToUniversalTime().AddMinutes(5)
    $delayedSpec = New-WpfLaunchSpecification @delayedCommon -LaunchMode initial -ContractProbe
    $delayedProbe = Start-Process -FilePath $delayedSpec.taskExecutable -ArgumentList ([string]$delayedSpec.taskArguments) -PassThru
    Start-Sleep -Milliseconds 500
    Write-WpfAtomicJson -Path $delayedSpec.launchRequestPath -Value $delayedSpec
    $delayedProbe.WaitForExit()
    $delayedReport = Get-Content -LiteralPath $delayedSpec.outputPath -Raw | ConvertFrom-Json
    Check ($delayedProbe.ExitCode -eq 0 -and [string]$delayedReport.status -eq 'CONTRACT_PROBE_PASS' -and [string]$delayedReport.candidateSha256 -ceq $delayedSpec.candidateSha256) 'driver waits for the exact launch request when task startup races remote file visibility'

    $sidResolver = { param($account) if ($account -in @('DEVFLEET-E2E-01\E2EAdmin','E2EAdmin')) { 'S-1-5-21-100-200-300-1001' } else { 'S-1-5-21-100-200-300-9999' } }
    $requestedPrincipal = [pscustomobject]@{UserId='DEVFLEET-E2E-01\E2EAdmin';LogonType=3;RunLevel=1}
    $registered = [pscustomobject]@{Actions=@([pscustomobject]@{Execute=$resume.taskExecutable.ToUpperInvariant();Arguments=$resume.taskArguments});Principal=[pscustomobject]@{UserId='E2EAdmin';LogonType=3;RunLevel=1}}
    $taskReason='';$taskEvidence=$null
    Check ((Test-WpfRegisteredTaskBinding -Specification $resume -RegisteredTask $registered -RequestedPrincipal $requestedPrincipal -Reason ([ref]$taskReason) -Evidence ([ref]$taskEvidence) -SidResolver $sidResolver) -and $taskEvidence.verifiedBeforeStart -and $taskEvidence.principalSidSha256 -match '^[0-9a-f]{64}$') 'registered task accepts normalized account text only when the principal SID, enums, executable, and arguments are exact'
    $wrongPrincipal = [pscustomobject]@{Actions=$registered.Actions;Principal=[pscustomobject]@{UserId='OtherUser';LogonType=3;RunLevel=1}}
    $taskReason='';$taskEvidence=$null
    Check (-not (Test-WpfRegisteredTaskBinding -Specification $resume -RegisteredTask $wrongPrincipal -RequestedPrincipal $requestedPrincipal -Reason ([ref]$taskReason) -Evidence ([ref]$taskEvidence) -SidResolver $sidResolver) -and $taskReason -eq 'registered task principal SID diverged') 'registered task rejects a different principal identity before start'
    $wrongArguments = [pscustomobject]@{Actions=@([pscustomobject]@{Execute=$resume.taskExecutable;Arguments=($resume.taskArguments+' -ElevatedResume')});Principal=$registered.Principal}
    $taskReason='';$taskEvidence=$null
    Check (-not (Test-WpfRegisteredTaskBinding -Specification $resume -RegisteredTask $wrongArguments -RequestedPrincipal $requestedPrincipal -Reason ([ref]$taskReason) -Evidence ([ref]$taskEvidence) -SidResolver $sidResolver) -and $taskReason -eq 'registered task arguments diverged') 'registered task rejects post-registration argument divergence before start'
    $realPhaseSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1') -Raw
    Check ($realPhaseSource -notmatch 'Import-Module \(\[string\]\$spec\.contractModulePath\)' -and $realPhaseSource -match 'Resolve-TaskSid' -and $realPhaseSource -match 'REGISTERED_TASK_BINDING_MISMATCH') 'restricted PowerShell Direct pre-start validation does not import a staged script module'

    $initialCommon = @{} + $common
    $initialCommon.LaunchId = ('4' * 32)
    $initialCommon.OutputPath = Join-Path $scratch 'initial-final.json'
    $initialCommon.StartedPath = Join-Path $scratch 'initial-started.json'
    $initialCommon.CheckpointPath = Join-Path $scratch 'initial-checkpoint.json'
    $initialCommon.WorkerResultPath = Join-Path $scratch 'initial-worker.json'
    $initialCommon.LaunchRequestPath = Join-Path $scratch 'initial-request.json'
    $initial = New-WpfLaunchSpecification @initialCommon -LaunchMode initial
    Check ($initial.taskArguments -notmatch '(?:^| )-ElevatedResume(?: |$)' -and @($initial.candidateArguments) -notcontains '--elevated-resume') 'initial mode cannot silently inherit resume arguments'

    $initialProbeSpec = Copy-WpfLaunchSpecification -Specification $initial -ContractProbe
    Write-WpfAtomicJson -Path $initialProbeSpec.launchRequestPath -Value $initialProbeSpec
    $initialProbe = Start-Process -FilePath $initialProbeSpec.taskExecutable -ArgumentList ([string]$initialProbeSpec.taskArguments) -PassThru -Wait
    $initialProbeReport = Get-Content -LiteralPath $initialProbeSpec.outputPath -Raw | ConvertFrom-Json
    Check ($initialProbe.ExitCode -eq 0 -and [string]$initialProbeReport.status -eq 'CONTRACT_PROBE_PASS') 'Windows PowerShell parser binds the exact generated initial task action'
    Check ([string]$initialProbeReport.launchMode -eq 'initial' -and -not [bool]$initialProbeReport.elevatedResume -and (@($initialProbeReport.candidateArguments) -join [char]0) -ceq (@($initial.candidateArguments) -join [char]0) -and @($initialProbeReport.candidateArguments) -notcontains '--elevated-resume') 'driver parser acknowledgement keeps initial mode free of resume candidate arguments'

    Write-WpfAtomicJson -Path $resume.launchRequestPath -Value $resume
    $probeSpec = Copy-WpfLaunchSpecification -Specification $resume -ContractProbe
    Write-WpfAtomicJson -Path $probeSpec.launchRequestPath -Value $probeSpec
    $probe = Start-Process -FilePath $probeSpec.taskExecutable -ArgumentList ([string]$probeSpec.taskArguments) -PassThru -Wait
    $probeReport = Get-Content -LiteralPath $probeSpec.outputPath -Raw | ConvertFrom-Json
    Check ($probe.ExitCode -eq 0 -and [string]$probeReport.status -eq 'CONTRACT_PROBE_PASS') 'Windows PowerShell parser binds the exact generated resume task action'
    Check ([string]$probeReport.launchMode -eq 'resume' -and [bool]$probeReport.elevatedResume -and @($probeReport.candidateArguments)[0] -eq '--elevated-resume') 'driver parser acknowledgement matches requested mode and candidate arguments'

    $expected = [pscustomobject]$resume
    $complete = [pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-terminal-v2';status='PASS';terminal=$true;completionVerified=$true;runId=$resume.runId;launchId=$resume.launchId;transactionId=$resume.transactionId;payloadSha256=$resume.payloadSha256;candidateSha256=$resume.candidateSha256;sequence=8;cleanupDisposition='CLEANUP_EXACT_CANDIDATE';deadlineUtc=$resume.driverDeadlineUtc}
    $reason = ''
    Check (Test-WpfTerminalReport -Report $complete -Specification $expected -Reason ([ref]$reason)) 'completed report with exact launch identity is accepted'
    $incomplete = $complete | Select-Object *
    $incomplete.completionVerified = $false
    $reason = ''
    Check (-not (Test-WpfTerminalReport -Report $incomplete -Specification $expected -Reason ([ref]$reason))) 'completed-lifecycle PASS with completionVerified false is rejected'
    $stale = $complete | Select-Object *
    $stale.launchId = ('9' * 32)
    $reason = ''
    Check (-not (Test-WpfTerminalReport -Report $stale -Specification $expected -Reason ([ref]$reason))) 'stale or wrong-launch report is rejected'
    $wrongPayload = $complete | Select-Object *
    $wrongPayload.payloadSha256 = ('a' * 64)
    $reason = ''
    Check (-not (Test-WpfTerminalReport -Report $wrongPayload -Specification $expected -Reason ([ref]$reason))) 'wrong-payload report is rejected'
    foreach($mismatchName in @('runId','transactionId','candidateSha256')){
        $mismatched=$complete|Select-Object *;$mismatched.$mismatchName=if($mismatchName-eq'candidateSha256'){('b'*64)}elseif($mismatchName-eq'transactionId'){('c'*32)}else{'another-run'};$reason=''
        Check (-not(Test-WpfTerminalReport -Report $mismatched -Specification $expected -Reason ([ref]$reason))) "wrong-$mismatchName report is rejected"
    }
    $reason=''
    Check (-not(Test-WpfTerminalReport -Report $complete -Specification $expected -Reason ([ref]$reason) -MinimumSequenceExclusive 8)) 'duplicate or regressed terminal sequence is rejected against prior accepted evidence'
    $unverifiedPending = $complete | Select-Object *
    $unverifiedPending.status = 'DURABLE_PENDING'
    $unverifiedPending.completionVerified = $false
    $reason = ''
    Check (-not (Test-WpfTerminalReport -Report $unverifiedPending -Specification $expected -Reason ([ref]$reason))) 'pending without durable identity and ownership transfer is rejected'
    $verifiedPending = $unverifiedPending | Select-Object *
    $verifiedPending | Add-Member -NotePropertyName durableCompletionPending -NotePropertyValue $true -Force
    $verifiedPending | Add-Member -NotePropertyName durableStateVerified -NotePropertyValue $true -Force
    $verifiedPending | Add-Member -NotePropertyName ownershipTransferVerified -NotePropertyValue $true -Force
    $verifiedPending | Add-Member -NotePropertyName productOutcomeClaimed -NotePropertyValue $false -Force
    $verifiedPending | Add-Member -NotePropertyName pendingBasis -NotePropertyValue 'EXACT_TRANSACTION_DURABLE_STATE' -Force
    $verifiedPending.cleanupDisposition = 'RELINQUISH_VERIFIED_PENDING'
    $reason = ''
    Check (Test-WpfTerminalReport -Report $verifiedPending -Specification $expected -Reason ([ref]$reason)) 'durable pending requires exact transaction-bound durable state and ownership transfer'

    $observerHandoff = $unverifiedPending | Select-Object *
    $observerHandoff.status = 'OBSERVER_HANDOFF'
    $observerHandoff.cleanupDisposition = 'RELINQUISH_LIFECYCLE_OWNER'
    $observerHandoff | Add-Member -NotePropertyName durableCompletionPending -NotePropertyValue $false -Force
    $observerHandoff | Add-Member -NotePropertyName ownershipTransferVerified -NotePropertyValue $true -Force
    $observerHandoff | Add-Member -NotePropertyName productOutcomeClaimed -NotePropertyValue $false -Force
    $observerHandoff | Add-Member -NotePropertyName handoffBasis -NotePropertyValue 'EXACT_TRANSACTION_PRODUCT_OBSERVER_HANDOFF' -Force
    $observerHandoff | Add-Member -NotePropertyName observerContract -NotePropertyValue 'Wait-DevFleetProductLifecycleTransition' -Force
    $reason = ''
    Check (Test-WpfTerminalReport -Report $observerHandoff -Specification $expected -Reason ([ref]$reason)) 'observer handoff transfers exact launch ownership without fabricating durable pending or product completion'

    $script:clock = $now
    $script:stopped = $false
    $script:terminalWrites = 0
    $timeout = Wait-WpfBoundReport -Specification $expected -ReportProvider { $null } -WorkerStateProvider { 'Running' } -StopWorker { $script:stopped = $true } -ClockProvider { $value=$script:clock; $script:clock=$value.AddSeconds(90); $value } -SleepProvider { param($seconds) } -TerminalWriter { param($value) $script:terminalWrites++; $value }
    Check ([string]$timeout.status -eq 'OBSERVER_FAILURE' -and [string]$timeout.failureClass -eq 'UIA_SEMANTIC_NO_PROGRESS' -and $script:stopped -and $script:terminalWrites -eq 1) 'stuck UIA worker is isolated, stopped, and terminalized by the semantic no-progress watchdog'

    # The provider itself is outside the supervisor's trust boundary. A
    # provider that never returns must not strand the driver until the outer
    # proof watchdog; the supervisor must cancel that exact provider call,
    # stop the exact worker, and publish one terminal record.
    $neverProviderJob = Start-ThreadJob -ScriptBlock {
        param($ContractModulePath,$Specification)
        Import-Module $ContractModulePath -Force
        $script:neverProviderStopped=$false;$script:neverProviderTerminalWrites=0
        $result=Wait-WpfBoundReport -Specification $Specification `
            -ReportProvider { while($true){Start-Sleep -Milliseconds 100} } `
            -WorkerStateProvider { 'Running' } `
            -StopWorker { $script:neverProviderStopped=$true } `
            -ProviderCallTimeoutSeconds 1 `
            -ClockProvider { [datetime]'2026-09-05T20:00:00Z' } `
            -SleepProvider { param($seconds) } `
            -TerminalWriter { param($value) $script:neverProviderTerminalWrites++; $value }
        [pscustomobject]@{result=$result;stopped=$script:neverProviderStopped;terminalWrites=$script:neverProviderTerminalWrites}
    } -ArgumentList $modulePath,$expected
    try {
        $neverProviderCompleted=Wait-Job -Job $neverProviderJob -Timeout 5
        $neverProviderOutcome=if($neverProviderCompleted){Receive-Job -Job $neverProviderJob -ErrorAction SilentlyContinue}else{$null}
        Check ($neverProviderCompleted -and [string]$neverProviderOutcome.result.failureClass -eq 'REPORT_PROVIDER_TIMEOUT' -and $neverProviderOutcome.result.productStarted -eq $true -and [bool]$neverProviderOutcome.stopped -and [int]$neverProviderOutcome.terminalWrites -eq 1) 'a report provider that never returns after product start is cancelled, stops the exact worker, and terminalizes once'
    } finally {
        Stop-Job -Job $neverProviderJob -ErrorAction SilentlyContinue
        Remove-Job -Job $neverProviderJob -Force -ErrorAction SilentlyContinue
    }

    $script:throwingProviderStopped=$false;$script:throwingProviderTerminalWrites=0
    $throwingProvider=Wait-WpfBoundReport -Specification $expected `
        -ReportProvider { throw 'controlled original report-provider error' } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:throwingProviderStopped=$true } `
        -ProviderCallTimeoutSeconds 2 `
        -ClockProvider { [datetime]'2026-09-05T20:00:00Z' } `
        -SleepProvider { param($seconds) } `
        -TerminalWriter { param($value) $script:throwingProviderTerminalWrites++; $value }
    Check ([string]$throwingProvider.failureClass -eq 'REPORT_PROVIDER_FAILURE' -and [string]$throwingProvider.error -match 'controlled original report-provider error' -and $script:throwingProviderStopped -and $script:throwingProviderTerminalWrites -eq 1) 'a throwing report provider preserves the original error while stopping and terminalizing once'

    $script:neverProgressStopped=$false;$script:neverProgressTerminalWrites=0
    $neverProgress=Wait-WpfBoundReport -Specification $expected `
        -ReportProvider { $null } `
        -ProgressProvider { while($true){Start-Sleep -Milliseconds 100} } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:neverProgressStopped=$true } `
        -ProviderCallTimeoutSeconds 1 `
        -ClockProvider { [datetime]'2026-09-05T20:00:00Z' } `
        -SleepProvider { param($seconds) } `
        -TerminalWriter { param($value) $script:neverProgressTerminalWrites++; $value }
    Check ([string]$neverProgress.failureClass -eq 'PROGRESS_PROVIDER_TIMEOUT' -and $neverProgress.productStarted -eq $true -and $script:neverProgressStopped -and $script:neverProgressTerminalWrites -eq 1) 'a progress provider that never returns after product start is cancelled, stops the exact worker, and terminalizes once'

    $longComplete = $complete | Select-Object *
    $longComplete.launchId = $longOwner.launchId
    $longComplete.deadlineUtc = $longOwner.driverDeadlineUtc
    $script:clock = $now
    $script:round = 0
    $script:stopped = $false
    $script:terminalWrites = 0
    $longSilence = Wait-WpfBoundReport -Specification $longOwner -ReportProvider { $script:round++; if($script:round -ge 5){$longComplete}else{$null} } -WorkerStateProvider { 'Running' } -StopWorker { $script:stopped = $true } -ClockProvider { $value=$script:clock; $script:clock=$value.AddSeconds(200); $value } -SleepProvider { param($seconds) } -TerminalWriter { param($value) $script:terminalWrites++; $value }
    Check ([string]$longSilence.status -eq 'PASS' -and -not $script:stopped -and $script:terminalWrites -eq 0) 'a real product operation may remain semantically quiet for more than five minutes while still bounded by inherited deadlines'

    $script:clock = $now
    $script:round = 0
    $script:semantic = 0
    $script:terminalWrites = 0
    $eventual = Wait-WpfBoundReport -Specification $expected -ReportProvider { $script:round++; if($script:round -ge 3){$complete}else{$null} } -WorkerStateProvider { 'Running' } -StopWorker { $script:stopped=$true } -ProgressProvider { $script:semantic++; [pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$resume.runId;launchId=$resume.launchId;transactionId=$resume.transactionId;payloadSha256=$resume.payloadSha256;candidateSha256=$resume.candidateSha256;deadlineUtc=$resume.driverDeadlineUtc;sequence=(8+$script:semantic);phase='PRODUCT_STATUS_CHANGED';semanticProgressSequence=$script:semantic;semanticProgressKind='OBSERVER_BREADCRUMB'} } -ClockProvider { $value=$script:clock; $script:clock=$value.AddSeconds(240); $value } -SleepProvider { param($seconds) } -TerminalWriter { param($value) $script:terminalWrites++; $value }
    Check ([string]$eventual.status -eq 'OBSERVER_FAILURE' -and [string]$eventual.failureClass -eq 'UIA_DEADLINE_EXHAUSTED' -and $script:terminalWrites -eq 1) 'a report first produced after the immutable cutoff cannot revive the launch and UI breadcrumbs cannot extend it'

    $lateCollectedSpecCommon = @{} + $common
    $lateCollectedSpecCommon.LaunchId = ('e' * 32)
    $lateCollected = New-WpfLaunchSpecification @lateCollectedSpecCommon -LaunchMode resume -ElevatedResume
    $lateCollectedReport = $complete | Select-Object *
    $lateCollectedReport.launchId = $lateCollected.launchId
    $lateCollectedReport.deadlineUtc = $lateCollected.driverDeadlineUtc
    $script:clock = $now.AddSeconds(480)
    $collected = Wait-WpfBoundReport -Specification $lateCollected -ReportProvider { [pscustomobject]@{contract='devfleet-wpf-file-observation-v1';kind='TERMINAL';value=$lateCollectedReport;fileWriteUtc=$now.AddSeconds(400).ToString('o')} } -WorkerStateProvider { 'Running' } -StopWorker { throw 'an in-deadline terminal must not be stopped merely because collection was delayed' } -ClockProvider { $script:clock } -SleepProvider { param($seconds) } -TerminalWriter { param($value) throw 'an in-deadline terminal must not be replaced' }
    Check ([string]$collected.status -eq 'PASS') 'a valid terminal atomically established before cutoff remains collectable after cutoff'

    $wrongProgressCommon = @{} + $common
    $wrongProgressCommon.LaunchId = ('f' * 32)
    $wrongProgress = New-WpfLaunchSpecification @wrongProgressCommon -LaunchMode resume -ElevatedResume -SemanticNoProgressSeconds 300
    $script:clock = $now
    $script:terminalWrites = 0
    $wrongIdentityProgress = Wait-WpfBoundReport -Specification $wrongProgress -ReportProvider { $null } -WorkerStateProvider { 'Running' } -StopWorker { $script:stopped=$true } -ProgressProvider { [pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$wrongProgress.runId;launchId=$wrongProgress.launchId;transactionId=('9'*32);payloadSha256=$wrongProgress.payloadSha256;candidateSha256=$wrongProgress.candidateSha256;deadlineUtc=$wrongProgress.driverDeadlineUtc;sequence=9;phase='PRODUCT_STATUS_CHANGED';semanticProgressSequence=1;semanticProgressKind='DURABLE_PRODUCT_PROGRESS'} } -ClockProvider { $value=$script:clock;$script:clock=$value.AddSeconds(150);$value } -SleepProvider { param($seconds) } -TerminalWriter { param($value)$script:terminalWrites++;$value }
    Check ([string]$wrongIdentityProgress.failureClass -eq 'UIA_SEMANTIC_NO_PROGRESS' -and $script:terminalWrites -eq 1) 'wrong-transaction progress cannot extend the semantic deadline'

    $validProgressCommon = @{} + $common
    $validProgressCommon.LaunchId = ('a' * 32)
    $validProgressCommon.OwnerDeadlineUtc = $now.AddSeconds(1200)
    $validProgress = New-WpfLaunchSpecification @validProgressCommon -LaunchMode resume -ElevatedResume -SemanticNoProgressSeconds 300
    $validProgressReport = $complete | Select-Object *
    $validProgressReport.launchId = $validProgress.launchId
    $validProgressReport.deadlineUtc = $validProgress.driverDeadlineUtc
    $validProgressReport.sequence = 100
    $script:clock=$now;$script:round=0;$script:semantic=0;$script:terminalWrites=0
    $progressThenComplete=Wait-WpfBoundReport -Specification $validProgress -ReportProvider {$script:round++;if($script:round-ge5){$validProgressReport}else{$null}} -WorkerStateProvider {'Running'} -StopWorker {throw 'valid in-deadline progress must preserve the worker'} -ProgressProvider {$script:semantic++;[pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$validProgress.runId;launchId=$validProgress.launchId;transactionId=$validProgress.transactionId;payloadSha256=$validProgress.payloadSha256;candidateSha256=$validProgress.candidateSha256;deadlineUtc=$validProgress.driverDeadlineUtc;sequence=(10+$script:semantic);phase='PRODUCT_DURABLE_PROGRESS';semanticProgressSequence=$script:semantic;semanticProgressKind='DURABLE_PRODUCT_PROGRESS';progressSource='DURABLE_PRODUCT_OBSERVER'}} -ClockProvider {$value=$script:clock;$script:clock=$value.AddSeconds(150);$value} -SleepProvider {param($seconds)} -TerminalWriter {param($value)$script:terminalWrites++;$value}
    Check ([string]$progressThenComplete.status -eq 'PASS' -and $script:terminalWrites -eq 0) 'only exact transaction/payload-bound durable product progress can extend the semantic deadline inside the immutable cutoff'

    foreach($badProgressCase in @('MALFORMED','NONMONOTONIC')){
        $script:clock=$now;$script:semantic=0;$script:terminalWrites=0
        $badProgress=Wait-WpfBoundReport -Specification $wrongProgress -ReportProvider {$null} -WorkerStateProvider {'Running'} -StopWorker {$script:stopped=$true} -ProgressProvider {if($badProgressCase-eq'MALFORMED'){[pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$wrongProgress.runId;launchId=$wrongProgress.launchId;transactionId=$wrongProgress.transactionId;payloadSha256=$wrongProgress.payloadSha256;candidateSha256=$wrongProgress.candidateSha256;deadlineUtc=$wrongProgress.driverDeadlineUtc;sequence='bad';phase='PRODUCT_DURABLE_PROGRESS';semanticProgressSequence='bad';semanticProgressKind='DURABLE_PRODUCT_PROGRESS';progressSource='DURABLE_PRODUCT_OBSERVER'}}else{[pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-checkpoint-v2';runId=$wrongProgress.runId;launchId=$wrongProgress.launchId;transactionId=$wrongProgress.transactionId;payloadSha256=$wrongProgress.payloadSha256;candidateSha256=$wrongProgress.candidateSha256;deadlineUtc=$wrongProgress.driverDeadlineUtc;sequence=9;phase='PRODUCT_DURABLE_PROGRESS';semanticProgressSequence=1;semanticProgressKind='DURABLE_PRODUCT_PROGRESS';progressSource='DURABLE_PRODUCT_OBSERVER'}}} -ClockProvider {$value=$script:clock;$script:clock=$value.AddSeconds(150);$value} -SleepProvider {param($seconds)} -TerminalWriter {param($value)$script:terminalWrites++;$value}
        Check ([string]$badProgress.failureClass -eq 'UIA_SEMANTIC_NO_PROGRESS' -and $script:terminalWrites -eq 1) "$badProgressCase progress cannot extend the semantic deadline"
    }

    $raceReport = $observerHandoff | Select-Object *
    $raceReport.sequence = 9
    $script:raceReportReads = 0
    $script:raceTerminalWrites = 0
    $raceObserved = Wait-WpfBoundReport -Specification $expected -ReportProvider {
        $script:raceReportReads++
        if ($script:raceReportReads -ge 2) { $raceReport } else { $null }
    } -WorkerStateProvider { 'Exited' } -StopWorker {
        throw 'terminal handoff written immediately before worker exit must not be stopped'
    } -ClockProvider { $now } -SleepProvider { param($seconds) } -TerminalWriter {
        param($value)
        $script:raceTerminalWrites++
        $value
    }
    Check ([string]$raceObserved.status -eq 'OBSERVER_HANDOFF' -and $script:raceReportReads -eq 2 -and $script:raceTerminalWrites -eq 0) 'worker exit rechecks a just-written valid terminal handoff before classifying EARLY_WORKER_EXIT'

    $script:terminalWrites = 0
    $early = Wait-WpfBoundReport -Specification $expected -ReportProvider { $null } -WorkerStateProvider { 'Exited' } -StopWorker { throw 'must not stop an already exited worker' } -ClockProvider { $now } -SleepProvider { param($seconds) } -TerminalWriter { param($value) $script:terminalWrites++; $value }
    Check ([string]$early.status -eq 'OBSERVER_FAILURE' -and [string]$early.failureClass -eq 'EARLY_WORKER_EXIT' -and $script:terminalWrites -eq 1) 'early startup failure writes the minimal primary observer error'

    Check ((Get-WpfCleanupDisposition -Status 'ALREADY_RUNNING' -CompletionVerified:$false) -eq 'CONTINUE_OBSERVATION') 'already-running execution cannot be treated as completed or cleaned up'
    Check ((Get-WpfCleanupDisposition -Status 'DURABLE_PENDING' -CompletionVerified:$false) -eq 'RELINQUISH_VERIFIED_PENDING') 'durable pending transfers cleanup ownership'
    Check ((Get-WpfCleanupDisposition -Status 'OBSERVER_HANDOFF' -CompletionVerified:$false) -eq 'RELINQUISH_LIFECYCLE_OWNER') 'observer handoff transfers exact candidate cleanup ownership without a pending claim'
    Check ((Get-WpfCleanupDisposition -Status 'OBSERVER_FAILURE' -CompletionVerified:$false) -eq 'RELINQUISH_LIFECYCLE_OWNER') 'observer failure does not kill the in-flight candidate'
    Check ((Get-WpfCleanupDisposition -Status 'PASS' -CompletionVerified:$true) -eq 'CLEANUP_EXACT_CANDIDATE') 'completed candidate returns exact cleanup ownership to the driver'

    $summary = [pscustomobject]@{status=if($failures.Count){'FAIL'}else{'PASS'};passed=$passed;total=($passed+$failures.Count);failures=@($failures)}
    $summary | ConvertTo-Json -Depth 6
    if ($failures.Count) { exit 1 }
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
