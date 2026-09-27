# DevFleet source part 034

Full-source UTF-8 byte interval [1534500, 1581000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 251cf6d7fe4e2c370c087847f55c8b52a0a662e5d958a36b195b2784b1599c86

<!-- BEGIN SOURCE SLICE -->
toryResetPhraseSet -and (Set-UiTextValue -Root $window -AutomationId 'ControlPhraseBox' -Value 'DELETE DEVFLEET')){$factoryResetPhraseSet=$true;$actions+=[ordered]@{name='factory-reset-control-plane-confirmation';result='SET_EXACT_REVIEWED_SCOPE'}}
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
        $reportDeadline = ConvertTo-WpfUtcInstant (Get-WpfContractValue $Report 'deadlineUtc')
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
        $reportObservation = Resolve-WpfProviderObservation -ProviderValue $reportCall.value -Kind TERMINAL -