# DevFleet source part 035

Full-source UTF-8 byte interval [1581000, 1627500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 21dfed828ad75de0594eb77cd28213aa8f5fbac7702afe5aad51041101ed257c

<!-- BEGIN SOURCE SLICE -->
didateArguments=@($candidateArguments);driverPath=$PSCommandPath;driverIdentity=(Get-ProcessIdentityEvidence $driverPid $driverSessionId)
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

```


## FILE: automation/release-e2e/modules/executors/WpfLaunchContract.psm1

SHA256: 613270ead8d20ae457b4a64569d0d9db985f317d2bc82fd34ad60a80f3a417e5 | Bytes: 43448 | Git mode: 100644

```
Set-StrictMode -Version Latest
$script:WpfAbandonedProviderCalls=New-Object System.Collections.ArrayList

function Get-WpfContractValue {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { if ([string]$key -ieq $Name) { return $Value[$key] } }
        return $null
    }
    foreach ($property in @($Value.PSObject.Properties)) { if ([string]$property.Name -ieq $Name) { return $property.Value } }
    return $null
}

function ConvertTo-WpfUtcInstant {
    param([Parameter(Mandatory)][object]$Value)
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    if ($Value -is [datetime]) {
        $date = [datetime]$Value
        if ($date.Kind -eq [DateTimeKind]::Unspecified) { throw 'UTC instant omitted its offset/kind.' }
        return $date.ToUniversalTime()
    }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
        throw "UTC instant was malformed: $Value"
    }
    return $parsed.UtcDateTime
}

function ConvertTo-WpfCommandLineToken {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Value.IndexOf([char]0) -ge 0 -or $Value.Contains('"')) { throw 'WPF launch argument contained a forbidden quote or NUL.' }
    if ($Value -eq '' -or $Value -match '\s') { return '"' + $Value + '"' }
    return $Value
}

function ConvertTo-WpfCommandLine {
    param([Parameter(Mandatory)][object[]]$Tokens)
    return (@($Tokens | ForEach-Object { ConvertTo-WpfCommandLineToken -Value ([string]$_) }) -join ' ')
}

function Write-WpfAtomicJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 24) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Get-WpfFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-WpfTextSha256 {
    param([Parameter(Mandatory)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Resolve-WpfPrincipalSid {
    param([Parameter(Mandatory)][string]$Account, [scriptblock]$SidResolver)
    if ($SidResolver) { $resolved = [string](& $SidResolver $Account) }
    else {
        $candidates = if ($Account -notmatch '[\\@]' -and $env:COMPUTERNAME) { @("$env:COMPUTERNAME\$Account", $Account) } else { @($Account) }
        $resolved = ''
        foreach ($candidate in $candidates) {
            try { $resolved = ([Security.Principal.NTAccount]::new($candidate)).Translate([Security.Principal.SecurityIdentifier]).Value; break } catch {}
        }
    }
    if ($resolved -notmatch '^S-\d-(?:\d+-)+\d+$') { throw "Scheduled-task principal did not resolve to a SID: $Account" }
    return $resolved
}

function Test-WpfRegisteredTaskBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Specification,
        [Parameter(Mandatory)][object]$RegisteredTask,
        [Parameter(Mandatory)][object]$RequestedPrincipal,
        [Parameter(Mandatory)][ref]$Reason,
        [Parameter(Mandatory)][ref]$Evidence,
        [scriptblock]$SidResolver
    )
    $Reason.Value = ''
    $Evidence.Value = $null
    $expectedExecute = [Environment]::ExpandEnvironmentVariables([string](Get-WpfContractValue $Specification 'taskExecutable'))
    $expectedArguments = [string](Get-WpfContractValue $Specification 'taskArguments')
    $expectedUser = [string](Get-WpfContractValue $Specification 'taskPrincipalUserId')
    $expectedLogonType = [int](Get-WpfContractValue $Specification 'taskLogonTypeValue')
    $expectedRunLevel = [int](Get-WpfContractValue $Specification 'taskRunLevelValue')
    $actions = @((Get-WpfContractValue $RegisteredTask 'Actions'))
    $principal = Get-WpfContractValue $RegisteredTask 'Principal'
    $actualExecute = if ($actions.Count -eq 1) { [Environment]::ExpandEnvironmentVariables([string](Get-WpfContractValue $actions[0] 'Execute')) } else { '' }
    $actualArguments = if ($actions.Count -eq 1) { [string](Get-WpfContractValue $actions[0] 'Arguments') } else { '' }
    $requestedUser = [string](Get-WpfContractValue $RequestedPrincipal 'UserId')
    $actualUser = [string](Get-WpfContractValue $principal 'UserId')
    $requestedLogonType = -1
    $actualLogonType = -1
    $requestedRunLevel = -1
    $actualRunLevel = -1
    try { $requestedLogonType = [Convert]::ToInt32((Get-WpfContractValue $RequestedPrincipal 'LogonType'), [Globalization.CultureInfo]::InvariantCulture) } catch {}
    try { $actualLogonType = [Convert]::ToInt32((Get-WpfContractValue $principal 'LogonType'), [Globalization.CultureInfo]::InvariantCulture) } catch {}
    try { $requestedRunLevel = [Convert]::ToInt32((Get-WpfContractValue $RequestedPrincipal 'RunLevel'), [Globalization.CultureInfo]::InvariantCulture) } catch {}
    try { $actualRunLevel = [Convert]::ToInt32((Get-WpfContractValue $principal 'RunLevel'), [Globalization.CultureInfo]::InvariantCulture) } catch {}
    $expectedSid = ''
    $requestedSid = ''
    $actualSid = ''
    try {
        $expectedSid = Resolve-WpfPrincipalSid -Account $expectedUser -SidResolver $SidResolver
        $requestedSid = Resolve-WpfPrincipalSid -Account $requestedUser -SidResolver $SidResolver
        $actualSid = Resolve-WpfPrincipalSid -Account $actualUser -SidResolver $SidResolver
    } catch {
        $Reason.Value = "principal SID resolution failed: $($_.Exception.Message)"
    }
    $sidHash = if ($actualSid) { Get-WpfTextSha256 -Value $actualSid } else { '' }
    $Evidence.Value = [pscustomobject][ordered]@{
        actionCount = $actions.Count
        requestedExecute = $expectedExecute
        registeredExecute = $actualExecute
        argumentsMatched = [string]::Equals($actualArguments, $expectedArguments, [StringComparison]::Ordinal)
        expectedUserId = $expectedUser
        requestedUserId = $requestedUser
        registeredUserId = $actualUser
        principalSidSha256 = $sidHash
        requestedLogonTypeValue = $requestedLogonType
        registeredLogonTypeValue = $actualLogonType
        requestedRunLevelValue = $requestedRunLevel
        registeredRunLevelValue = $actualRunLevel
        verifiedBeforeStart = $false
    }
    if ($Reason.Value) { return $false }
    if ($actions.Count -ne 1) { $Reason.Value = 'registered task action count diverged'; return $false }
    try {
        $expectedExecute = [IO.Path]::GetFullPath($expectedExecute)
        $actualExecute = [IO.Path]::GetFullPath($actualExecute)
    } catch { $Reason.Value = 'registered task executable path was malformed'; return $false }
    if (-not [string]::Equals($actualExecute, $expectedExecute, [StringComparison]::OrdinalIgnoreCase)) { $Reason.Value = 'registered task executable identity diverged'; return $false }
    if (-not [string]::Equals($actualArguments, $expectedArguments, [StringComparison]::Ordinal)) { $Reason.Value = 'registered task arguments diverged'; return $false }
    if ($expectedSid -cne $requestedSid -or $expectedSid -cne $actualSid) { $Reason.Value = 'registered task principal SID diverged'; return $false }
    if ($requestedLogonType -ne $expectedLogonType -or $actualLogonType -ne $expectedLogonType) { $Reason.Value = 'registered task logon type diverged'; return $false }
    if ($requestedRunLevel -ne $expectedRunLevel -or $actualRunLevel -ne $expectedRunLevel) { $Reason.Value = 'registered task run level diverged'; return $false }
    $Evidence.Value.verifiedBeforeStart = $true
    return $true
}

function Get-WpfCandidateArguments {
    param(
        [Parameter(Mandatory)][ValidateSet('direct','initial','resume','fallback')][string]$LaunchMode,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Role,
        [switch]$ElevatedResume
    )
    if ($LaunchMode -eq 'resume' -and -not $ElevatedResume) { throw 'Resume launch mode requires ElevatedResume.' }
    if ($LaunchMode -ne 'resume' -and $ElevatedResume) { throw 'ElevatedResume is only valid for resume launch mode.' }
    $arguments = @('--action', $Action, '--role', $Role)
    if($Role-notmatch'(?i)Laptop'){$arguments+='--defer-network-pairing'}
    if ($ElevatedResume) { $arguments = @('--elevated-resume') + $arguments }
    return @($arguments)
}

function Get-WpfNavigationDisposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('direct','initial','resume','fallback')][string]$LaunchMode,
        [Parameter(Mandatory)][bool]$ElevatedResume,
        [Parameter(Mandatory)][bool]$WindowOwnerMatches,
        [AllowEmptyString()][string]$PageKicker = '',
        [AllowEmptyString()][string]$OperationStatus = '',
        [Parameter(Mandatory)][bool]$NextEnabled,
        [Parameter(Mandatory)][bool]$ExecutePresent,
        [Parameter(Mandatory)][bool]$ExecuteEnabled
    )
    if (-not $WindowOwnerMatches) { return 'REJECT_OWNER_MISMATCH' }
    $executePage = $PageKicker -match '^STEP 7 OF 8 . EXECUTE$'
    $finishPage = $PageKicker -match '^STEP 8 OF 8 . FINISH$'
    $executionStatus = $OperationStatus -match '(?i)invoking actual|reboot required|completed|failed|verif'
    if ($LaunchMode -eq 'resume') {
        if (-not $ElevatedResume) { return 'REJECT_MODE_MISMATCH' }
        if (($executePage -and (($ExecutePresent -and -not $ExecuteEnabled) -or $executionStatus)) -or ($finishPage -and $OperationStatus -match '(?i)completed and verified')) {
            return 'OBSERVE_EXISTING'
        }
        return 'WAIT'
    }
    if ($NextEnabled) { return 'NAVIGATE' }
    if ($executePage -and $ExecutePresent -and -not $ExecuteEnabled -and $executionStatus) { return 'OBSERVE_EXISTING' }
    return 'WAIT'
}

function New-WpfLaunchSpecification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DriverPath,
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$StartedPath,
        [Parameter(Mandatory)][string]$CheckpointPath,
        [Parameter(Mandatory)][string]$WorkerResultPath,
        [Parameter(Mandatory)][string]$LaunchRequestPath,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{32}$')][string]$LaunchId,
        [AllowEmptyString()][ValidatePattern('^$|^[0-9a-fA-F]{32}$')][string]$TransactionId = '',
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$PayloadSha256,
        [Parameter(Mandatory)][ValidateSet('direct','initial','resume','fallback')][string]$LaunchMode,
        [Parameter(Mandatory)][ValidateRange(1,65535)][int]$ExpectedInteractiveSessionId,
        [switch]$AllowMutation,
        [switch]$AllowRebootRequired,
        [switch]$UseDurableCompletionFallback,
        [switch]$ElevatedResume,
        [Parameter(Mandatory)][object]$OwnerDeadlineUtc,
        [ValidateRange(1,2147483647)][int]$SemanticNoProgressSeconds = 300,
        [scriptblock]$ClockProvider = { (Get-Date).ToUniversalTime() },
        [switch]$ContractProbe,
        [string]$DriverSha256,
        [string]$CandidateSha256,
        [string]$TaskExecutable,
        [switch]$SkipPathValidation
    )
    if (-not $SkipPathValidation) { foreach ($path in @($DriverPath, $ExePath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "WPF launch input is absent: $path" } } }
    $now = ConvertTo-WpfUtcInstant (& $ClockProvider)
    $ownerDeadline = ConvertTo-WpfUtcInstant $OwnerDeadlineUtc
    $boundaryDeadline = $ownerDeadline
    $driverDeadline = $boundaryDeadline.AddSeconds(-60)
    if ($driverDeadline -le $now.AddSeconds(30)) { throw 'Insufficient remaining owner budget for WPF launch and terminalization.' }
    $candidateArguments = @(Get-WpfCandidateArguments -LaunchMode $LaunchMode -Action $Action -Role $Role -ElevatedResume:$ElevatedResume)
    $driverHash = if ($DriverSha256) { $DriverSha256.ToLowerInvariant() } else { Get-WpfFileSha256 -Path $DriverPath }
    $candidateHash = if ($CandidateSha256) { $CandidateSha256.ToLowerInvariant() } else { Get-WpfFileSha256 -Path $ExePath }
    if ($driverHash -notmatch '^[0-9a-f]{64}$' -or $candidateHash -notmatch '^[0-9a-f]{64}$') { throw 'WPF launch input hashes were malformed.' }
    $taskExecutableValue = if ($TaskExecutable) { $TaskExecutable } else { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    $tokens = @(
        '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-STA','-File',$DriverPath,
        '-ExePath',$ExePath,'-Action',$Action,'-Role',$Role,'-OutputPath',$OutputPath,
        '-StartedPath',$StartedPath,'-CheckpointPath',$CheckpointPath,'-WorkerResultPath',$WorkerResultPath,
        '-LaunchRequestPath',$LaunchRequestPath,'-RunId',$RunId,'-LaunchId',$LaunchId,
        '-TransactionId',$TransactionId,'-PayloadSha256',$PayloadSha256,'-LaunchMode',$LaunchMode,
        '-ObserverDeadlineUtc',$driverDeadline.ToString('o'),'-ExpectedInteractiveSessionId',[string]$ExpectedInteractiveSessionId
    )
    if ($AllowMutation) { $tokens += '-AllowMutation' }
    if ($AllowRebootRequired) { $tokens += '-AllowRebootRequired' }
    if ($UseDurableCompletionFallback) { $tokens += '-UseDurableCompletionFallback' }
    if ($ElevatedResume) { $tokens += '-ElevatedResume' }
    if ($ContractProbe) { $tokens += '-ContractProbe' }
    $specification = [ordered]@{
        schemaVersion = 2
        contract = 'devfleet-wpf-launch-v2'
        runId = $RunId
        launchId = $LaunchId.ToLowerInvariant()
        transactionId = $TransactionId.ToLowerInvariant()
        payloadSha256 = $PayloadSha256.ToLowerInvariant()
        launchMode = $LaunchMode
        elevatedResume = [bool]$ElevatedResume
        action = $Action
        role = $Role
        allowMutation = [bool]$AllowMutation
        allowRebootRequired = [bool]$AllowRebootRequired
        useDurableCompletionFallback = [bool]$UseDurableCompletionFallback
        expectedInteractiveSessionId = $ExpectedInteractiveSessionId
        driverPath = $DriverPath
        driverSha256 = $driverHash
        exePath = $ExePath
        candidateSha256 = $candidateHash
        candidateArguments = @($candidateArguments)
        outputPath = $OutputPath
        startedPath = $StartedPath
        checkpointPath = $CheckpointPath
        workerResultPath = $WorkerResultPath
        launchRequestPath = $LaunchRequestPath
        ownerDeadlineUtc = $ownerDeadline.ToString('o')
        boundaryDeadlineUtc = $boundaryDeadline.ToString('o')
        driverDeadlineUtc = $driverDeadline.ToString('o')
        terminalizationMarginSeconds = 60
        semanticNoProgressSeconds = $SemanticNoProgressSeconds
        taskExecutable = $taskExecutableValue
        taskPrincipalUserId = 'DEVFLEET-E2E-01\E2EAdmin'
        taskLogonType = 'Interactive'
        taskLogonTypeValue = 3
        taskRunLevel = 'Highest'
        taskRunLevelValue = 1
        driverArgumentTokens = @($tokens)
        taskArguments = ConvertTo-WpfCommandLine -Tokens $tokens
        contractProbe = [bool]$ContractProbe
        sequence = 0
        createdAtUtc = $now.ToString('o')
    }
    return [pscustomobject]$specification
}

function Copy-WpfLaunchSpecification {
    param([Parameter(Mandatory)][object]$Specification, [switch]$ContractProbe)
    $copy = [ordered]@{}
    foreach ($property in @($Specification.PSObject.Properties)) { $copy[$property.Name] = $property.Value }
    $tokens = @($copy.driverArgumentTokens | ForEach-Object { [string]$_ })
    if ($ContractProbe -and $tokens -notcontains '-ContractProbe') { $tokens += '-ContractProbe' }
    $copy.driverArgumentTokens = $tokens
    $copy.taskArguments = ConvertTo-WpfCommandLine -Tokens $tokens
    $copy.contractProbe = [bool]$ContractProbe
    return [pscustomobject]$copy
}

function Assert-WpfDriverBinding {
    param(
        [Parameter(Mandatory)][object]$Specification,
        [Parameter(Mandatory)][hashtable]$Actual
    )
    $pairs = @{
        exePath='ExePath'; action='Action'; role='Role'; outputPath='OutputPath'; startedPath='StartedPath'; checkpointPath='CheckpointPath';
        workerResultPath='WorkerResultPath'; launchRequestPath='LaunchRequestPath'; runId='RunId'; launchId='LaunchId'; transactionId='TransactionId';
        payloadSha256='PayloadSha256'; launchMode='LaunchMode'
    }
    foreach ($expectedName in $pairs.Keys) {
        $expected = [string](Get-WpfContractValue $Specification $expectedName)
        $actualValue = [string]$Actual[$pairs[$expectedName]]
        if ($expected -cne $actualValue) { throw "WPF driver binding mismatch for $expectedName." }
    }
    foreach ($booleanName in @('AllowMutation','AllowRebootRequired','UseDurableCompletionFallback','ElevatedResume','ContractProbe')) {
        $expectedProperty = $booleanName.Substring(0,1).ToLowerInvariant() + $booleanName.Substring(1)
        if ([bool](Get-WpfContractValue $Specification $expectedProperty) -ne [bool]$Actual[$booleanName]) { throw "WPF driver binding mismatch for $booleanName." }
    }
    if ([int](Get-WpfContractValue $Specification 'expectedInteractiveSessionId') -ne [int]$Actual.ExpectedInteractiveSessionId) { throw 'WPF driver binding mismatch for interactive session.' }
    $deadlineExpected = ConvertTo-WpfUtcInstant (Get-WpfContractValue $Specification 'driverDeadlineUtc')
    $deadlineActual = ConvertTo-WpfUtcInstant $Actual.ObserverDeadlineUtc
    if ($deadlineExpected.Ticks -ne $deadlineActual.Ticks) { throw 'WPF driver binding mismatch for observer deadline.' }
    $driverPath = [string](Get-WpfContractValue $Specification 'driverPath')
    $exePath = [string](Get-WpfContractValue $Specification 'exePath')
    if ((Get-WpfFileSha256 -Path $driverPath) -cne [string](Get-WpfContractValue $Specification 'driverSha256')) { throw 'WPF driver hash diverged after launch request creation.' }
    if ((Get-WpfFileSha256 -Path $exePath) -cne [string](Get-WpfContractValue $Specification 'candidateSha256')) { throw 'WPF candidate hash diverged after launch request creation.' }
    $contractModulePath = [string](Get-WpfContractValue $Specification 'contractModulePath')
    $contractModuleSha256 = [string](Get-WpfContractValue $Specification 'contractModuleSha256')
    if ($contractModulePath -or $contractModuleSha256) {
        if (-not $contractModulePath -or -not $contractModuleSha256 -or [string]$Actual.ContractModulePath -cne $contractModulePath) { throw 'WPF contract module path binding diverged after launch request creation.' }
        if ((Get-WpfFileSha256 -Path $contractModulePath) -cne $contractModuleSha256) { throw 'WPF contract module hash diverged after launch request creation.' }
    }
    $actualArguments = @(Get-WpfCandidateArguments -LaunchMode ([string]$Actual.LaunchMode) -Action ([string]$Actual.Action) -Role ([string]$Actual.Role) -ElevatedResume:([bool]$Actual.ElevatedResume))
    $expectedArguments = @((Get-WpfContractValue $Specification 'candidateArguments') | ForEach-Object { [string]$_ })
    if (($actualArguments -join [char]0) -cne ($expectedArguments -join [char]0)) { throw 'WPF candidate argument vector diverged from the launch request.' }
    return $true
}

function Test-WpfTerminalReport {
    param([AllowNull()][object]$Report, [Parameter(Mandatory)][object]$Specification, [ref]$Reason, [int]$MinimumSequenceExclusive = 0)
    $Reason.Value = ''
    if ($null -eq $Report) { $Reason.Value = 'report absent'; return $false }
    if ([string](Get-WpfContractValue $Report 'contract') -cne 'devfleet-wpf-terminal-v2') { $Reason.Value = 'report contract is missing or stale'; return $false }
    if ([int](Get-WpfContractValue $Report 'schemaVersion') -lt 2) { $Reason.Value = 'report schema is stale'; return $false }
    if (-not [bool](Get-WpfContractValue $Report 'terminal')) { $Reason.Value = 'report is not terminal'; return $false }
    foreach ($name in @('runId','launchId','payloadSha256','candidateSha256')) {
        if ([string](Get-WpfContractValue $Report $name) -cne [string](Get-WpfContractValue $Specification $name)) { $Reason.Value = "report $name mismatch"; return $false }
    }
    $expectedTransaction = [string](Get-WpfContractValue $Specification 'transactionId')
    if ([string](Get-WpfContractValue $Report 'transactionId') -cne $expectedTransaction) { $Reason.Value = 'report transactionId mismatch'; return $false }
    try {
        $reportDeadline = Conver