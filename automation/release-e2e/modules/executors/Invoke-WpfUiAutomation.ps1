[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExePath,
    [Parameter(Mandatory)][string]$Action,
    [string]$Role = 'Primary / Desktop',
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$StartedPath,
    [string]$CheckpointPath,
    [string]$WorkerResultPath,
    [Parameter(Mandatory)][string]$LaunchRequestPath,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$LaunchId,
    [AllowEmptyString()][string]$TransactionId = '',
    [Parameter(Mandatory)][string]$PayloadSha256,
    [Parameter(Mandatory)][ValidateSet('direct','initial','resume','fallback')][string]$LaunchMode,
    [Parameter(Mandatory)][string]$ObserverDeadlineUtc,
    [Parameter(Mandatory)][int]$ExpectedInteractiveSessionId,
    [switch]$AllowMutation,
    [switch]$AllowRebootRequired,
    [switch]$UseDurableCompletionFallback,
    [switch]$ElevatedResume,
    [switch]$ContractProbe,
    [switch]$WorkerMode,
    [int]$CandidateProcessId,
    [string]$ExpectedCandidateStartUtc
)

$ErrorActionPreference = 'Stop'
$contractModule = Join-Path $PSScriptRoot 'WpfLaunchContract.psm1'
$driverPid = [int]$PID
$driverSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
$candidateHash = ''
$candidateArguments = @()
$process = $null
$cleanupDisposition = 'NONE'
$sequence = 0
$semanticProgressSequence = 0
$specification = $null

function Write-BootstrapAtomicJson([string]$Path, [object]$Value) {
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 24) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Read-BootstrapLaunchSpecification([string]$Path, [string]$DeadlineUtc) {
    # PowerShell Direct can start the registered task just before the atomic
    # launch-request move becomes visible in the task's interactive session.
    # Wait only for that bounded visibility condition; the immutable binding
    # and all hash/identity checks still run after the exact request is read.
    $waitDeadline = [DateTime]::UtcNow.AddSeconds(15)
    try {
        $observerDeadline = ([DateTimeOffset]::Parse($DeadlineUtc)).UtcDateTime
        if ($observerDeadline.AddSeconds(-1) -lt $waitDeadline) { $waitDeadline = $observerDeadline.AddSeconds(-1) }
    } catch {}
    $lastReadError = $null
    do {
        try {
            if (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop) {
                return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop)
            }
        } catch { $lastReadError = $_.Exception.Message }
        if ([DateTime]::UtcNow -ge $waitDeadline) { break }
        Start-Sleep -Milliseconds 100
    } while ($true)
    if ($lastReadError) { throw "Launch request was not readable before the bounded bootstrap deadline: $lastReadError" }
    throw "Launch request did not become visible before the bounded bootstrap deadline: $Path"
}

try {
    $specification = Read-BootstrapLaunchSpecification -Path $LaunchRequestPath -DeadlineUtc $ObserverDeadlineUtc
    $candidateHash = [string]$specification.candidateSha256
    Import-Module $contractModule -Force -ErrorAction Stop
} catch {
    $bootstrapError = $_.Exception.Message
    try {
        Write-BootstrapAtomicJson -Path $OutputPath -Value ([ordered]@{
            schemaVersion=2; contract='devfleet-wpf-terminal-v2'; status='OBSERVER_FAILURE'; terminal=$true; completionVerified=$false;
            failureClass='DRIVER_BOOTSTRAP_FAILURE'; error="WPF driver bootstrap failed before contract binding: $bootstrapError";
            runId=$RunId; launchId=$LaunchId; transactionId=$TransactionId; payloadSha256=$PayloadSha256; candidateSha256=$candidateHash;
            sequence=1; phase='DRIVER_BOOTSTRAP'; lastDurableStep='TASK_PROCESS_STARTED'; launchMode=$LaunchMode; elevatedResume=[bool]$ElevatedResume;
            action=$Action; role=$Role; driverPid=$driverPid; driverSessionId=$driverSessionId; processId=$null; candidateArguments=@();
            mutationInvoked=$false; productStarted=$false; cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER'; deadlineUtc=$ObserverDeadlineUtc;
            contractModulePath=$contractModule; timestampUtc=(Get-Date).ToUniversalTime().ToString('o')
        })
    } catch {}
    exit 2
}

function Get-ProcessIdentityEvidence([int]$Id, [int]$ExpectedSessionId) {
    try {
        $row = Get-CimInstance Win32_Process -Filter "ProcessId=$Id" -ErrorAction Stop
        if (-not $row) { return $null }
        $owner = Invoke-CimMethod -InputObject $row -MethodName GetOwner -ErrorAction Stop
        $processInfo = Get-Process -Id $Id -ErrorAction Stop
        if ([int]$processInfo.SessionId -ne $ExpectedSessionId) { return $null }
        return [ordered]@{present=$true;pid=$Id;user=[string]$owner.User;domain=[string]$owner.Domain;owner=([string]$owner.Domain+'\'+[string]$owner.User);sessionId=[int]$processInfo.SessionId}
    } catch { return $null }
}

function Write-BoundaryCheckpoint([string]$Phase, [string]$Status, [hashtable]$Detail) {
    $script:sequence++
    $entry = [ordered]@{
        schemaVersion=2; contract='devfleet-wpf-checkpoint-v2'; runId=$RunId; launchId=$LaunchId; transactionId=$TransactionId;
        payloadSha256=$PayloadSha256; candidateSha256=$script:candidateHash; sequence=$script:sequence; phase=$Phase; status=$Status;
        deadlineUtc=$ObserverDeadlineUtc; timestampUtc=(Get-Date).ToUniversalTime().ToString('o')
    }
    if ($Detail) { foreach ($key in $Detail.Keys) { $entry[$key] = $Detail[$key] } }
    if ($CheckpointPath) { Write-WpfAtomicJson -Path $CheckpointPath -Value $entry }
    return [pscustomobject]$entry
}

function New-MinimalTerminal([string]$Status, [string]$FailureClass, [string]$ErrorMessage, [string]$LastStep) {
    $script:sequence++
    return [pscustomobject][ordered]@{
        schemaVersion=2; contract='devfleet-wpf-terminal-v2'; status=$Status; terminal=$true; completionVerified=$false;
        failureClass=$FailureClass; error=$ErrorMessage; runId=$RunId; launchId=$LaunchId; transactionId=$TransactionId;
        payloadSha256=$PayloadSha256; candidateSha256=$script:candidateHash; sequence=$script:sequence; phase='WPF'; lastDurableStep=$LastStep;
        launchMode=$LaunchMode; elevatedResume=[bool]$ElevatedResume; action=$Action; role=$Role; driverPid=$driverPid;
        driverSessionId=$driverSessionId; processId=if($script:process){[int]$script:process.Id}else{$null};
        candidateArguments=@($script:candidateArguments); cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER';
        deadlineUtc=$ObserverDeadlineUtc; timestampUtc=(Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-MinDeadline([datetime]$Maximum) {
    $absolute = ConvertTo-WpfUtcInstant $ObserverDeadlineUtc
    if ($absolute -lt $Maximum) { return $absolute }
    return $Maximum
}

function Read-ObservedJsonFile([string]$Path,[ValidateSet('TERMINAL','PROGRESS')][string]$Kind) {
    try {
        # The worker publishes these files with an atomic replace while the
        # supervisor polls them.  A short-lived access-denied from the guest
        # filesystem must remain an absent observation; the bounded watchdog
        # below will retry and will still terminalize on its deadline.
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop)) { return $null }
        $value = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return [pscustomobject][ordered]@{contract='devfleet-wpf-file-observation-v1';kind=$Kind;value=$value;fileWriteUtc=$item.LastWriteTimeUtc.ToString('o')}
    } catch { return $null }
}

$actualBinding = @{
    ExePath=$ExePath;Action=$Action;Role=$Role;OutputPath=$OutputPath;StartedPath=$StartedPath;CheckpointPath=$CheckpointPath;
    WorkerResultPath=$WorkerResultPath;LaunchRequestPath=$LaunchRequestPath;RunId=$RunId;LaunchId=$LaunchId;TransactionId=$TransactionId;
    PayloadSha256=$PayloadSha256;LaunchMode=$LaunchMode;ObserverDeadlineUtc=$ObserverDeadlineUtc;
    ExpectedInteractiveSessionId=$ExpectedInteractiveSessionId;AllowMutation=[bool]$AllowMutation;AllowRebootRequired=[bool]$AllowRebootRequired;
    UseDurableCompletionFallback=[bool]$UseDurableCompletionFallback;ElevatedResume=[bool]$ElevatedResume;ContractProbe=[bool]$ContractProbe;
    ContractModulePath=$contractModule
}

if (-not $WorkerMode) {
    try {
        Assert-WpfDriverBinding -Specification $specification -Actual $actualBinding | Out-Null
        $candidateHash = [string]$specification.candidateSha256
        $candidateArguments = @($specification.candidateArguments | ForEach-Object { [string]$_ })
        if ($ContractProbe) {
            Write-WpfAtomicJson -Path $OutputPath -Value ([ordered]@{
                schemaVersion=2;status='CONTRACT_PROBE_PASS';terminal=$false;completionVerified=$false;runId=$RunId;launchId=$LaunchId;
                transactionId=$TransactionId;payloadSha256=$PayloadSha256;candidateSha256=$candidateHash;launchMode=$LaunchMode;
                elevatedResume=[bool]$ElevatedResume;candidateArguments=@($candidateArguments);driverPid=$driverPid;driverSessionId=$driverSessionId
            })
            exit 0
        }
        if ($driverSessionId -ne $ExpectedInteractiveSessionId -or $driverSessionId -eq 0) { throw 'WPF supervisor did not bind to the expected interactive session.' }
        $bound = Write-BoundaryCheckpoint -Phase 'DRIVER_BOUND' -Status 'PASS' -Detail @{driverPid=$driverPid;driverSessionId=$driverSessionId;driverSha256=[string]$specification.driverSha256;launchMode=$LaunchMode;elevatedResume=[bool]$ElevatedResume}
        if ($StartedPath) { Write-WpfAtomicJson -Path $StartedPath -Value $bound }

        $process = Start-Process -FilePath $ExePath -ArgumentList (ConvertTo-WpfCommandLine -Tokens $candidateArguments) -PassThru
        Start-Sleep -Milliseconds 200
        $process.Refresh()
        $processStartUtc = $process.StartTime.ToUniversalTime().ToString('o')
        if ($process.SessionId -ne $ExpectedInteractiveSessionId -or $process.SessionId -eq 0) { throw 'Exact candidate launched outside the expected interactive session.' }
        $candidateIdentity = Get-ProcessIdentityEvidence -Id $process.Id -ExpectedSessionId $ExpectedInteractiveSessionId
        if (-not $candidateIdentity) { throw 'Exact candidate launch identity could not be proven.' }
        $launchAck = Write-BoundaryCheckpoint -Phase 'LAUNCH_ACKNOWLEDGED' -Status 'PASS' -Detail @{
            processId=[int]$process.Id;processStartTime=$processStartUtc;sessionId=[int]$process.SessionId;candidateIdentity=$candidateIdentity;
            candidatePath=$ExePath;candidateArguments=@($candidateArguments);driverPath=$PSCommandPath;driverIdentity=(Get-ProcessIdentityEvidence $driverPid $driverSessionId)
        }

        Remove-Item -LiteralPath $WorkerResultPath -Force -ErrorAction SilentlyContinue
        $workerTokens = @(
            '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-STA','-File',$PSCommandPath,'-WorkerMode',
            '-ExePath',$ExePath,'-CandidateProcessId',[string]$process.Id,'-ExpectedCandidateStartUtc',$processStartUtc,
            '-Action',$Action,'-Role',$Role,'-OutputPath',$WorkerResultPath,'-CheckpointPath',$CheckpointPath,
            '-LaunchRequestPath',$LaunchRequestPath,'-RunId',$RunId,'-LaunchId',$LaunchId,'-TransactionId',$TransactionId,
            '-PayloadSha256',$PayloadSha256,'-LaunchMode',$LaunchMode,'-ObserverDeadlineUtc',$ObserverDeadlineUtc,
            '-ExpectedInteractiveSessionId',[string]$ExpectedInteractiveSessionId
        )
        if ($AllowMutation) { $workerTokens += '-AllowMutation' }
        if ($AllowRebootRequired) { $workerTokens += '-AllowRebootRequired' }
        if ($UseDurableCompletionFallback) { $workerTokens += '-UseDurableCompletionFallback' }
        if ($ElevatedResume) { $workerTokens += '-ElevatedResume' }
        $worker = Start-Process -FilePath ([string]$specification.taskExecutable) -ArgumentList (ConvertTo-WpfCommandLine -Tokens $workerTokens) -PassThru
        $terminal = Wait-WpfBoundReport -Specification $specification `
            -ReportProvider { Read-ObservedJsonFile -Path $WorkerResultPath -Kind TERMINAL } `
            -WorkerStateProvider { try { $worker.Refresh(); if ($worker.HasExited) { 'Exited' } else { 'Running' } } catch { 'Exited' } } `
            -StopWorker { try { if (-not $worker.HasExited) { $worker.Kill() } } catch {} } `
            -ProgressProvider { Read-ObservedJsonFile -Path $CheckpointPath -Kind PROGRESS } `
            -TerminalWriter { param($value) Write-WpfAtomicJson -Path $OutputPath -Value $value }

        $terminal | Add-Member -NotePropertyName driverPid -NotePropertyValue $driverPid -Force
        $terminal | Add-Member -NotePropertyName driverSessionId -NotePropertyValue $driverSessionId -Force
        $terminal | Add-Member -NotePropertyName driverIdentity -NotePropertyValue (Get-ProcessIdentityEvidence $driverPid $driverSessionId) -Force
        $terminal | Add-Member -NotePropertyName candidateIdentity -NotePropertyValue $candidateIdentity -Force
        $terminal | Add-Member -NotePropertyName processId -NotePropertyValue ([int]$process.Id) -Force
        $terminal | Add-Member -NotePropertyName processStartTime -NotePropertyValue $processStartUtc -Force
        $terminal | Add-Member -NotePropertyName launchAcknowledgement -NotePropertyValue $launchAck -Force
        $cleanupDisposition = Get-WpfCleanupDisposition -Status ([string]$terminal.status) -CompletionVerified:([bool]$terminal.completionVerified)
        $terminal | Add-Member -NotePropertyName cleanupDisposition -NotePropertyValue $cleanupDisposition -Force
        Write-WpfAtomicJson -Path $OutputPath -Value $terminal
        if ([string]$terminal.status -in @('OBSERVER_FAILURE','CANCELLED')) { exit 2 }
        if ([string]$terminal.status -in @('PRODUCT_FAILURE','FAIL')) { exit 3 }
        exit 0
    } catch {
        $primary = New-MinimalTerminal -Status 'OBSERVER_FAILURE' -FailureClass 'DRIVER_STARTUP_OR_SUPERVISION_FAILURE' -ErrorMessage $_.Exception.Message -LastStep $(if($sequence -ge 2){'LAUNCH_ACKNOWLEDGED'}elseif($sequence -ge 1){'DRIVER_BOUND'}else{'LAUNCH_REQUESTED'})
        Write-WpfAtomicJson -Path $OutputPath -Value $primary
        $cleanupDisposition = 'RELINQUISH_LIFECYCLE_OWNER'
        try {
            Write-WpfAtomicJson -Path ($OutputPath + '.diagnostic.json') -Value ([ordered]@{status='DIAGNOSTIC';primaryError=$_.Exception.Message;driverPid=$driverPid;driverSessionId=$driverSessionId;processId=if($process){$process.Id}else{$null};timestampUtc=(Get-Date).ToUniversalTime().ToString('o')})
        } catch {}
        exit 2
    } finally {
        if ($process -and $cleanupDisposition -eq 'CLEANUP_EXACT_CANDIDATE') {
            try { $process.Refresh(); if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 1; $process.Refresh(); if (-not $process.HasExited) { $process.Kill() } } } catch {}
        }
    }
}

# UI Automation is intentionally isolated in this worker process. The parent
# supervisor can terminate this exact worker and publish a primary terminal
# report even if a synchronous COM/UIA call below never returns.
$actions = @()
$visible = @()
$diagnostics = @()
$postConfirmationState = $null
$window = $null
try {
    $candidateHash = Get-WpfFileSha256 -Path $ExePath
    $candidateArguments = @($specification.candidateArguments | ForEach-Object { [string]$_ })
    if ($RunId -cne [string]$specification.runId -or $LaunchId -cne [string]$specification.launchId -or $PayloadSha256 -cne [string]$specification.payloadSha256 -or $candidateHash -cne [string]$specification.candidateSha256) { throw 'UIA worker launch identity did not match the immutable launch request.' }
    if ($TransactionId -and $TransactionId -cne [string]$specification.transactionId) { throw 'UIA worker transaction identity did not match the launch request.' }
    $process = Get-Process -Id $CandidateProcessId -ErrorAction Stop
    $actualStartUtc = $process.StartTime.ToUniversalTime()
    if ($actualStartUtc.Ticks -ne (ConvertTo-WpfUtcInstant $ExpectedCandidateStartUtc).Ticks -or $process.SessionId -ne $ExpectedInteractiveSessionId) { throw 'UIA worker candidate PID/start-time/session binding failed.' }
    $sequence = 2
    [void](Write-BoundaryCheckpoint -Phase 'UIA_LOADING' -Status 'STARTED' -Detail @{workerPid=$driverPid;candidatePid=$process.Id})
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    if (-not ('DevFleetE2EWindowProbe' -as [type])) {
        Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DevFleetE2EWindowProbe {
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
'@
    }
    if (-not ('DevFleetE2EWin32' -as [type])) {
        Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DevFleetE2EWin32 {
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr hWndParent, IntPtr hWndChildAfter, string lpszClass, string lpszWindow);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder className, int maxCount);
}
'@
    }
    [void](Write-BoundaryCheckpoint -Phase 'UIA_READY' -Status 'PASS' -Detail @{workerPid=$driverPid})

    function Get-UiElements { param([Parameter(Mandatory)]$Root) @($Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)) }
    function Ensure-UiCheckbox {
        param([Parameter(Mandatory)]$Root,[Parameter(Mandatory)][string]$Pattern)
        $element=Get-UiElements $Root|Where-Object{$_.Current.ControlType -eq [System.Windows.Automation.ControlType]::CheckBox -and $_.Current.Name -match $Pattern}|Select-Object -First 1
        if(-not $element){return $false};$toggle=$element.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if($toggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On){$toggle.Toggle();Start-Sleep -Milliseconds 300};return $true
    }
    function Set-UiTextValue {
        param([Parameter(Mandatory)]$Root,[Parameter(Mandatory)][string]$AutomationId,[Parameter(Mandatory)][string]$Value)
        $element=Get-UiElements $Root|Where-Object{$_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and $_.Current.AutomationId -eq $AutomationId}|Select-Object -First 1
        if(-not $element){return $false}
        $valuePattern=$element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if([string]$valuePattern.Current.Value -cne $Value){$valuePattern.SetValue($Value);Start-Sleep -Milliseconds 300}
        if([string]$valuePattern.Current.Value -cne $Value){throw "UI text control $AutomationId did not accept the exact reviewed value."}
        return $true
    }
    function Get-UiDiagnosticValues {
        param([Parameter(Mandatory)]$Root)
        $values=@();foreach($edit in @(Get-UiElements $Root|Where-Object{$_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit})){try{$value=$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value;if($value){$values+=[string]$value}}catch{}};return $values
    }

    $windowDeadline = Get-MinDeadline ((Get-Date).ToUniversalTime().AddSeconds(90))
    while((Get-Date).ToUniversalTime() -lt $windowDeadline -and -not $window){Start-Sleep -Milliseconds 500;$process.Refresh();if($process.MainWindowHandle -ne 0){try{$window=[System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)}catch{}}}
    if(-not $window){throw "Exact candidate did not expose a WPF window for action $Action."}
    [void](Write-BoundaryCheckpoint -Phase 'WINDOW_ACQUIRED' -Status 'PASS' -Detail @{candidatePid=$process.Id;windowTitle=[string]$window.Current.Name})
    $all=Get-UiElements $window;$buttons=@($all|Where-Object{$_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button})
    $actions=@([ordered]@{name='startup';result='PASS';window=$window.Current.Name})
    $navigationReady=$null;$executionAlreadyStarted=$false;$factoryResetPhraseSet=$false;$navigationDeadline=Get-MinDeadline ((Get-Date).ToUniversalTime().AddSeconds(120))
    while((Get-Date).ToUniversalTime() -lt $navigationDeadline -and -not $navigationReady -and -not $executionAlreadyStarted){
        $all=Get-UiElements $window;$buttons=@($all|Where-Object{$_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button})
        $nextControl=$buttons|Where-Object{$_.Current.IsEnabled -and $_.Current.Name -match '^(Next|Continue)$'}|Select-Object -First 1
        $executeControl=$buttons|Where-Object{$_.Current.Name -eq 'Execute verified plan'}|Select-Object -First 1
        $windowHandle=[IntPtr]$process.MainWindowHandle;$windowOwner=0;if($windowHandle -ne [IntPtr]::Zero){[void][DevFleetE2EWindowProbe]::GetWindowThreadProcessId($windowHandle,[ref]$windowOwner)}
        $pageKickerElement=@($all|Where-Object{$_.Current.AutomationId -eq 'PageKicker'}|Select-Object -First 1);$statusElement=@($all|Where-Object{$_.Current.AutomationId -eq 'OperationStatus'}|Select-Object -First 1)
        $pageKicker=if($pageKickerElement){[string]$pageKickerElement.Current.Name}else{''};$operationStatus=if($statusElement){[string]$statusElement.Current.Name}else{''}
        $navigationDisposition=Get-WpfNavigationDisposition -LaunchMode $LaunchMode -ElevatedResume ([bool]$ElevatedResume) -WindowOwnerMatches ($windowOwner -eq [uint32]$process.Id) -PageKicker $pageKicker -OperationStatus $operationStatus -NextEnabled ([bool]$nextControl) -ExecutePresent ([bool]$executeControl) -ExecuteEnabled ([bool]($executeControl -and $executeControl.Current.IsEnabled))
        if($navigationDisposition -eq 'REJECT_OWNER_MISMATCH'){throw 'Candidate UI window ownership diverged after launch acknowledgement.'}
        if($navigationDisposition -eq 'REJECT_MODE_MISMATCH'){throw 'Resume navigation state diverged from the elevated-resume launch binding.'}
        if($navigationDisposition -eq 'NAVIGATE'){$navigationReady=$nextControl;break}
        if($navigationDisposition -eq 'OBSERVE_EXISTING'){$executionAlreadyStarted=$true;$actions+=[ordered]@{name='execution-state';result='EXACT_CANDIDATE_EXECUTION_OBSERVED';page=$pageKicker;status=$operationStatus};[void](Write-BoundaryCheckpoint -Phase 'RESUME_EXECUTION_OBSERVED' -Status 'OBSERVER_STATE' -Detail @{candidatePid=$process.Id;operationStatus=$operationStatus;semanticProgressKind='OBSERVER_BREADCRUMB'});break}
        Start-Sleep -Milliseconds 500
    }
    if(-not $navigationReady -and -not $executionAlreadyStarted){
        if($LaunchMode -eq 'resume'){throw "Action $Action resume did not expose an exact owned auto-execution or terminal state before the inherited navigation deadline."}
        throw "Action $Action did not expose an enabled Next control after preflight."
    }
    if(-not $executionAlreadyStarted){
        for($i=0;$i -lt 8;$i++){
            if($Role-notmatch'(?i)Laptop'){[void](Ensure-UiCheckbox $window 'Configure network pairing later')};[void](Ensure-UiCheckbox $window 'I explicitly acknowledge rootful Docker')
            if($AllowMutation -and $Action -eq 'FactoryReset'){
                $projectData=@($all|Where-Object{$_.Current.ControlType -eq [System.Windows.Automation.ControlType]::CheckBox -and ($_.Current.AutomationId -eq 'ProjectDataCheck' -or $_.Current.Name -match '^Factory Reset: include selected project data') }|Select-Object -First 1)
                if($projectData){$projectToggle=$projectData.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern);if($projectToggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On){throw 'Factory Reset UI automation refuses project-data scope; only the explicitly authorized control-plane scope may be automated.'}}
                if(-not $factoryResetPhraseSet -and (Set-UiTextValue -Root $window -AutomationId 'ControlPhraseBox' -Value 'DELETE DEVFLEET')){$factoryResetPhraseSet=$true;$actions+=[ordered]@{name='factory-reset-control-plane-confirmation';result='SET_EXACT_REVIEWED_SCOPE'}}
            }
            $button=$buttons|Where-Object{$_.Current.IsEnabled -and $_.Current.Name -match '^(Next|Continue)$'}|Select-Object -First 1;if(-not $button){break};$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();$actions+=[ordered]@{name='navigation';result='INVOKED';label=$button.Current.Name};Start-Sleep -Milliseconds 600;$all=Get-UiElements $window;$buttons=@($all|Where-Object{$_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button})
        }
        $visible=@($all|ForEach-Object{$_.Current.Name}|Where-Object{$_})
        if($AllowMutation){
            $execute=$buttons|Where-Object{$_.Current.IsEnabled -and $_.Current.Name -match 'Execute verified plan'}|Select-Object -First 1;if(-not $execute){throw "Action $Action never exposed the reviewed execute control."}
            $execute.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();$actions+=[ordered]@{name='execute';result='INVOKED'};Start-Sleep -Seconds 2
            $root=[System.Windows.Automation.AutomationElement]::RootElement;$yes=$null;$confirmDeadline=Get-MinDeadline ((Get-Date).ToUniversalTime().AddSeconds(10))
            while((Get-Date).ToUniversalTime() -lt $confirmDeadline -and -not $yes){$yes=@($root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)|Where-Object{$_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $_.Current.IsEnabled -and $_.Current.Name -eq 'Yes' -and $_.Current.ProcessId -eq $process.Id}|Select-Object -First 1);if(-not $yes){Start-Sleep -Milliseconds 500}}
            if($yes){$yes.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();$actions+=[ordered]@{name='confirmation';result='INVOKED'}}else{
                $dialog=[DevFleetE2EWin32]::FindWindow('#32770','Confirm exact plan');if($dialog -eq [IntPtr]::Zero){throw 'The exact native confirmation dialog was not found.'}
                $dialogProcessId=0;[void][DevFleetE2EWin32]::GetWindowThreadProcessId($dialog,[ref]$dialogProcessId);if($dialogProcessId -ne [uint32]$process.Id){throw 'The native confirmation dialog was not owned by the exact candidate process.'}
                $yesButton=[IntPtr]::Zero;$child=[IntPtr]::Zero;do{$child=[DevFleetE2EWin32]::FindWindowEx($dialog,$child,$null,$null);if($child -eq [IntPtr]::Zero){break};$classBuffer=[Text.StringBuilder]::new(128);$captionBuffer=[Text.StringBuilder]::new(128);[void][DevFleetE2EWin32]::GetClassName($child,$classBuffer,$classBuffer.Capacity);[void][DevFleetE2EWin32]::GetWindowText($child,$captionBuffer,$captionBuffer.Capacity);if($classBuffer.ToString() -eq 'Button' -and ([DevFleetE2EWin32]::GetDlgCtrlID($child) -eq 6 -or ($captionBuffer.ToString() -replace '&','').Trim() -eq 'Yes')){$yesButton=$child;break}}while($true)
                if($yesButton -eq [IntPtr]::Zero){[void][DevFleetE2EWin32]::SendMessage($dialog,0x0111,[IntPtr]6,[IntPtr]::Zero);$confirmationResult='NATIVE_IDYES_EXACT_DIALOG_PROCESS_VERIFIED'}else{$buttonProcessId=0;[void][DevFleetE2EWin32]::GetWindowThreadProcessId($yesButton,[ref]$buttonProcessId);if($buttonProcessId -ne [uint32]$process.Id){throw 'The native Yes button was not owned by the exact candidate process.'};[void][DevFleetE2EWin32]::SendMessage($yesButton,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero);$confirmationResult='NATIVE_YES_EXACT_PROCESS_VERIFIED'}
                $confirmationVerified=$false;$verifyDeadline=Get-MinDeadline ((Get-Date).ToUniversalTime().AddSeconds(10));while((Get-Date).ToUniversalTime() -lt $verifyDeadline){if(-not [DevFleetE2EWin32]::IsWindow($dialog)){$confirmationVerified=$true;break};Start-Sleep -Milliseconds 250};if(-not $confirmationVerified){throw 'The exact candidate confirmation dialog did not demonstrably close.'};$actions+=[ordered]@{name='confirmation';result=$confirmationResult}
            }
            $semanticProgressSequence++
            [void](Write-BoundaryCheckpoint -Phase 'EXECUTION_INVOKED' -Status 'PASS' -Detail @{candidatePid=$process.Id;semanticProgressSequence=$semanticProgressSequence;semanticProgressKind='PRODUCT_EXECUTION_ACCEPTED'})
        }
    }

    if($AllowMutation){
        if($UseDurableCompletionFallback){
            $handoffBasis=if($TransactionId){'EXACT_TRANSACTION_PRODUCT_OBSERVER_HANDOFF'}else{'GENERATION_ZERO_PRODUCT_OBSERVER_HANDOFF'}
            $result=[ordered]@{status='OBSERVER_HANDOFF';terminal=$true;completionVerified=$false;durableCompletionPending=$false;ownershipTransferVerified=$true;productOutcomeClaimed=$false;handoffBasis=$handoffBasis;observerContract='Wait-DevFleetProductLifecycleTransition';handoffExecutionState=if($executionAlreadyStarted){'EXACT_IN_FLIGHT_OBSERVED'}else{'EXACT_EXECUTION_INVOKED'}}
            $cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER'
        }else{
            $completeDeadline=ConvertTo-WpfUtcInstant $ObserverDeadlineUtc;$completed=$false;$failed=$false;$rebootRequired=$false;$windowLostSince=$null;$lastProductStatus=''
            while((Get-Date).ToUniversalTime() -lt $completeDeadline){
                $process.Refresh();$windowHandle=[IntPtr]$process.MainWindowHandle;$windowOwner=0;if($windowHandle -ne [IntPtr]::Zero){[void][DevFleetE2EWindowProbe]::GetWindowThreadProcessId($windowHandle,[ref]$windowOwner)};$windowValid=$windowHandle -ne [IntPtr]::Zero -and [DevFleetE2EWindowProbe]::IsWindow($windowHandle) -and $windowOwner -eq [uint32]$process.Id
                if($process.HasExited -or -not $windowValid){if(-not $windowLostSince){$windowLostSince=(Get-Date).ToUniversalTime()}elseif((((Get-Date).ToUniversalTime())-$windowLostSince).TotalSeconds -ge 5){throw "Candidate UI window disappeared during completion polling; processExited=$([bool]$process.HasExited); candidatePid=$($process.Id)."}}else{$windowLostSince=$null}
                $all=Get-UiElements $window;$visible=@($all|ForEach-Object{$_.Current.Name}|Where-Object{$_});$diagnostics=Get-UiDiagnosticValues $window
                $statusElement=@($all|Where-Object{$_.Current.AutomationId -eq 'OperationStatus'}|Select-Object -First 1);$productStatus=if($statusElement){[string]$statusElement.Current.Name}else{''}
                if($productStatus -and $productStatus -cne $lastProductStatus){$lastProductStatus=$productStatus;$semanticProgressSequence++;[void](Write-BoundaryCheckpoint -Phase 'PRODUCT_STATUS_CHANGED' -Status 'SEMANTIC_PROGRESS' -Detail @{candidatePid=$process.Id;operationStatus=$productStatus;semanticProgressSequence=$semanticProgressSequence;semanticProgressKind='PRODUCT_STATUS_CHANGED'})}
                $completed=@($visible|Where-Object{$_ -eq 'Completed and verified'}).Count -gt 0;$rebootRequired=@($visible|Where-Object{$_ -eq 'Reboot required; checkpoint preserved'}).Count -gt 0;$failed=@($visible|Where-Object{$_ -match 'Failed|FAILED|error|blocked'}).Count -gt 0
                if($completed -or $rebootRequired -or $failed){break};Start-Sleep -Seconds 3
            }
            if($failed){$result=[ordered]@{status='PRODUCT_FAILURE';terminal=$true;completionVerified=$false;failureClass='PRODUCT_UI_FAILURE';error='Candidate UI reported a product failure.'};$cleanupDisposition='CLEANUP_EXACT_CANDIDATE'}
            elseif($rebootRequired -and $AllowRebootRequired){$result=[ordered]@{status='REBOOT_REQUIRED';terminal=$true;completionVerified=$false;rebootRequired=$true};$cleanupDisposition='RELINQUISH_VERIFIED_PENDING'}
            elseif($completed){$actions+=[ordered]@{name='completion';result='VERIFIED'};$result=[ordered]@{status='PASS';terminal=$true;completionVerified=$true};$cleanupDisposition='CLEANUP_EXACT_CANDIDATE'}
            else{throw "Action $Action exhausted its inherited deadline without a terminal product state."}
        }
    } else {$result=[ordered]@{status='PASS';terminal=$true;completionVerified=$true};$cleanupDisposition='CLEANUP_EXACT_CANDIDATE'}
    $sequence++
    foreach($pair in ([ordered]@{schemaVersion=2;contract='devfleet-wpf-terminal-v2';runId=$RunId;launchId=$LaunchId;transactionId=$TransactionId;payloadSha256=$PayloadSha256;candidateSha256=$candidateHash;sequence=$sequence;phase='WPF';lastDurableStep=if($executionAlreadyStarted){'ALREADY_RUNNING_OBSERVED'}elseif($AllowMutation){'EXECUTION_INVOKED'}else{'WINDOW_ACQUIRED'};launchMode=$LaunchMode;elevatedResume=[bool]$ElevatedResume;action=$Action;role=$Role;processId=[int]$process.Id;processStartTime=$actualStartUtc.ToString('o');sessionId=[int]$process.SessionId;driverPid=$driverPid;driverSessionId=$driverSessionId;driverIdentity=(Get-ProcessIdentityEvidence $driverPid $driverSessionId);candidateIdentity=(Get-ProcessIdentityEvidence $process.Id $process.SessionId);windowTitle=[string]$window.Current.Name;visibleNames=@($visible);actions=@($actions);diagnostics=@($diagnostics);mutationInvoked=([bool]$AllowMutation -and -not [bool]$executionAlreadyStarted);executionAlreadyStarted=[bool]$executionAlreadyStarted;candidateArguments=@($candidateArguments);cleanupDisposition=$cleanupDisposition;deadlineUtc=$ObserverDeadlineUtc;timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}).GetEnumerator()){$result[$pair.Key]=$pair.Value}
    Write-WpfAtomicJson -Path $OutputPath -Value $result
    exit $(if([string]$result.status -in @('PASS','REBOOT_REQUIRED','OBSERVER_HANDOFF')){0}else{3})
} catch {
    $primary=New-MinimalTerminal -Status 'OBSERVER_FAILURE' -FailureClass 'UIA_WORKER_FAILURE' -ErrorMessage $_.Exception.Message -LastStep $(if($sequence -gt 0){'UIA_BOUNDARY'}else{'LAUNCH_ACKNOWLEDGED'})
    Write-WpfAtomicJson -Path $OutputPath -Value $primary
    # Diagnostic enrichment is deliberately after the primary atomic report.
    try {
        $snapshot=@();if($window){$snapshot=@(Get-UiElements $window|ForEach-Object{[ordered]@{name=[string]$_.Current.Name;controlType=[string]$_.Current.ControlType.ProgrammaticName;enabled=[bool]$_.Current.IsEnabled;automationId=[string]$_.Current.AutomationId;processId=[int]$_.Current.ProcessId}})}
        Write-WpfAtomicJson -Path ($OutputPath+'.diagnostic.json') -Value ([ordered]@{status='DIAGNOSTIC';primaryError=$_.Exception.Message;uiSnapshot=$snapshot;actions=$actions;visibleNames=$visible;timestampUtc=(Get-Date).ToUniversalTime().ToString('o')})
    } catch {}
    exit 2
}
