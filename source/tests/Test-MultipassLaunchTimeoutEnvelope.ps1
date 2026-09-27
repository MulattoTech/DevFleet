[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\windows\DevFleet.Common.psm1'
Import-Module (Resolve-Path $modulePath) -Force
$module = Get-Module DevFleet.Common
$calls = [System.Collections.Generic.List[object]]::new()

# Replace only external process, executable lookup, and readiness boundaries;
# the production recovery helper itself remains under test.
$result = $module.Invoke({
    param($callLog, $deadline)
    function Get-MultipassExe { 'multipass.exe' }
    function Invoke-External {
        param(
            [string]$FilePath,
            [string[]]$ArgumentList,
            [switch]$Capture,
            [int]$TimeoutSeconds,
            [datetime]$DeadlineUtc = [datetime]::MinValue
        )
        [void]$callLog.Add([pscustomobject]@{
            file = $FilePath
            args = @($ArgumentList)
            timeoutSeconds = $TimeoutSeconds
            deadlineUtc = $DeadlineUtc
        })
        if (@($ArgumentList) -contains 'list') { return '{"list":[]}' }
        return ''
    }
    function Wait-MultipassReady { param($Name,$TimeoutSeconds,$DeadlineUtc) }
    Invoke-MultipassLaunchWithReadinessRecovery `
        -InstanceName 'devfleet-primary' `
        -LaunchArguments @('launch','24.04','--name','devfleet-primary') `
        -ReadinessTimeoutSeconds 1200 `
        -LaunchTimeoutSeconds 900 `
        -DeadlineUtc $deadline
}, $calls, ([datetime]::UtcNow.AddSeconds(900)))

$launch = @($calls | Where-Object { $_.args -contains 'launch' }) | Select-Object -First 1
if (-not $launch) { throw 'Expected the production helper to invoke a launch operation.' }
$innerTimeoutIndex = [Array]::IndexOf([string[]]$launch.args, '--timeout')
if ($innerTimeoutIndex -lt 0) { throw 'Expected the helper to supply an explicit Multipass inner timeout.' }
$innerTimeout = [int]$launch.args[$innerTimeoutIndex + 1]

# The intended invariant is a real grace between Multipass self-termination
# and the wrapper tree-kill deadline, within the existing 900-second envelope.
if ($innerTimeout -ge $launch.timeoutSeconds) {
    throw "Timeout envelope has no supervisor grace: inner=$innerTimeout supervisor=$($launch.timeoutSeconds)."
}
if (($launch.timeoutSeconds + (900 - $launch.timeoutSeconds)) -gt 900) {
    throw 'Launch envelope exceeds the existing stage budget.'
}

[pscustomobject]@{
    status = 'PASS'
    innerTimeoutSeconds = $innerTimeout
    supervisorTimeoutSeconds = $launch.timeoutSeconds
    resultReady = [bool]$result.ready
} | ConvertTo-Json -Depth 4

$explicitTimeoutError = $module.Invoke({
    param($deadline)
    function Get-MultipassExe { 'multipass.exe' }
    function Invoke-External { throw 'external boundary should not be reached' }
    function Wait-MultipassReady { }
    try {
        Invoke-MultipassLaunchWithReadinessRecovery `
            -InstanceName 'devfleet-primary' `
            -LaunchArguments @('launch','24.04','--name','devfleet-primary','--timeout','7') `
            -ReadinessTimeoutSeconds 1200 `
            -LaunchTimeoutSeconds 900 `
            -DeadlineUtc $deadline
    } catch { $_.Exception.Message }
}, ([datetime]::UtcNow.AddSeconds(900)))
if ([string]$explicitTimeoutError -notmatch 'rejects caller-supplied --timeout') {
    throw "Caller-supplied Multipass timeout was not rejected by the production helper: $explicitTimeoutError"
}

$recoveryCalls = [System.Collections.Generic.List[object]]::new()
$recoveryError = $module.Invoke({
    param($callLog, $deadline)
    $script:inventoryCount = 0
    function Get-MultipassExe { 'multipass.exe' }
    function Invoke-External {
        param(
            [string]$FilePath,
            [string[]]$ArgumentList,
            [switch]$Capture,
            [int]$TimeoutSeconds,
            [datetime]$DeadlineUtc = [datetime]::MinValue
        )
        [void]$callLog.Add([pscustomobject]@{ args=@($ArgumentList); timeoutSeconds=$TimeoutSeconds })
        if (@($ArgumentList) -contains 'list') {
            $script:inventoryCount++
            if ($script:inventoryCount -eq 1) { return '{"list":[]}' }
            return '{"list":[{"name":"devfleet-primary"}]}'
        }
        if (@($ArgumentList) -contains 'launch') { throw 'native launch failed' }
        if (@($ArgumentList) -contains 'start') { throw 'wrapper start failed' }
        return ''
    }
    function Wait-MultipassReady { }
    try {
        Invoke-MultipassLaunchWithReadinessRecovery `
            -InstanceName 'devfleet-primary' `
            -LaunchArguments @('launch','24.04','--name','devfleet-primary') `
            -ReadinessTimeoutSeconds 1200 `
            -LaunchTimeoutSeconds 900 `
            -DeadlineUtc $deadline
    } catch { $_.Exception.Message }
}, $recoveryCalls, ([datetime]::UtcNow.AddSeconds(900)))
if ([string]$recoveryError -notmatch 'Original launch error: native launch failed' -or [string]$recoveryError -notmatch 'Recovery error: wrapper start failed') {
    throw "Recovery error did not preserve both causal layers: $recoveryError"
}
$start = @($recoveryCalls | Where-Object { $_.args -contains 'start' }) | Select-Object -First 1
if (-not $start) { throw 'Expected bounded recovery to invoke an exact-instance start.' }
$startTimeoutIndex = [Array]::IndexOf([string[]]$start.args, '--timeout')
$startInner = [int]$start.args[$startTimeoutIndex + 1]
if ($startInner -ge $start.timeoutSeconds) {
    throw "Recovery start has no supervisor grace: inner=$startInner supervisor=$($start.timeoutSeconds)."
}

# A failed fresh launch can wedge the Multipass daemon/control socket.  Retrying
# `list` against the same daemon is not recovery.  Prove that the production
# helper repairs the exact trusted service once, re-probes inventory, and only
# then continues with the already-bounded exact-instance stop/start path.
$controlPlaneCalls = [System.Collections.Generic.List[object]]::new()
$controlPlaneRecoveries = [System.Collections.Generic.List[object]]::new()
$controlPlaneResult = $module.Invoke({
    param($callLog, $recoveryLog, $deadline)
    $script:inventoryCount = 0
    function Get-MultipassExe { 'multipass.exe' }
    function Invoke-External {
        param(
            [string]$FilePath,
            [string[]]$ArgumentList,
            [switch]$Capture,
            [int]$TimeoutSeconds,
            [datetime]$DeadlineUtc = [datetime]::MinValue
        )
        [void]$callLog.Add([pscustomobject]@{ args=@($ArgumentList); timeoutSeconds=$TimeoutSeconds })
        if (@($ArgumentList) -contains 'list') {
            $script:inventoryCount++
            if ($script:inventoryCount -eq 1) { return '{"list":[]}' }
            if ($script:inventoryCount -eq 2) { throw 'External command timed out after 60 seconds: multipass.exe list --format json' }
            return '{"list":[{"name":"devfleet-primary"}]}'
        }
        if (@($ArgumentList) -contains 'launch') { throw 'native launch failed with exit code 5' }
        return ''
    }
    function Wait-MultipassReady { param($Name,$TimeoutSeconds,$DeadlineUtc) }
    $recover = {
        param($Reason,$MultipassPath,$OwnerDeadlineUtc)
        [void]$recoveryLog.Add([pscustomobject]@{ reason=$Reason; path=$MultipassPath; deadline=$OwnerDeadlineUtc })
        [pscustomobject]@{ status='PASS'; service='Multipass'; reason=$Reason; forcedDaemonTermination=$false }
    }
    Invoke-MultipassLaunchWithReadinessRecovery `
        -InstanceName 'devfleet-primary' `
        -LaunchArguments @('launch','24.04','--name','devfleet-primary') `
        -ReadinessTimeoutSeconds 1200 `
        -LaunchTimeoutSeconds 900 `
        -DeadlineUtc $deadline `
        -ControlPlaneRecoveryProvider $recover
}, $controlPlaneCalls, $controlPlaneRecoveries, ([datetime]::UtcNow.AddSeconds(900)))
if ($controlPlaneRecoveries.Count -ne 1) { throw "Expected one exact Multipass control-plane recovery; observed $($controlPlaneRecoveries.Count)." }
if ([string]$controlPlaneRecoveries[0].reason -cne 'POST_LAUNCH_INVENTORY_TRANSPORT_FAILURE') { throw "Unexpected recovery reason: $($controlPlaneRecoveries[0].reason)" }
if ([string]$controlPlaneResult.recovery -cne 'multipass-service-and-instance-stop-start' -or -not [bool]$controlPlaneResult.ready) {
    throw "Control-plane recovery did not return a ready exact instance: $($controlPlaneResult | ConvertTo-Json -Compress -Depth 6)"
}

# Exercise the real service-recovery algorithm with only its Windows service
# boundaries mocked.  It must bind the exact Multipass service to the trusted
# multipassd path and LocalSystem identity before stop/start.
$serviceControls = [System.Collections.Generic.List[string]]::new()
$serviceStates = [System.Collections.Generic.Queue[object]]::new()
@(
    [pscustomobject]@{ Name='Multipass'; State='Running'; ProcessId=4242; PathName='"C:\Program Files\Multipass\bin\multipassd.exe" /svc'; StartName='LocalSystem' },
    [pscustomobject]@{ Name='Multipass'; State='Stopped'; ProcessId=0; PathName='"C:\Program Files\Multipass\bin\multipassd.exe" /svc'; StartName='LocalSystem' },
    [pscustomobject]@{ Name='Multipass'; State='Running'; ProcessId=4243; PathName='"C:\Program Files\Multipass\bin\multipassd.exe" /svc'; StartName='LocalSystem' }
) | ForEach-Object { $serviceStates.Enqueue($_) }
$serviceRecovery = $module.Invoke({
    param($controls,$states,$deadline)
    $lookup = { if ($states.Count -gt 1) { $states.Dequeue() } else { $states.Peek() } }
    $control = { param($Action) [void]$controls.Add([string]$Action) }
    Invoke-DevFleetMultipassControlPlaneRecovery `
        -Reason 'POST_LAUNCH_INVENTORY_TRANSPORT_FAILURE' `
        -MultipassPath 'C:\Program Files\Multipass\bin\multipass.exe' `
        -OwnerDeadlineUtc $deadline `
        -ServiceLookupProvider $lookup `
        -ServiceControlProvider $control `
        -DaemonLookupProvider { throw 'daemon fallback was not expected' } `
        -DaemonStopProvider { throw 'daemon fallback was not expected' } `
        -SleepProvider { param($Milliseconds) }
}, $serviceControls, $serviceStates, ([datetime]::UtcNow.AddSeconds(120)))
if (($serviceControls -join '|') -cne 'stop|start') { throw "Expected exact Multipass stop/start; observed $($serviceControls -join '|')." }
if ([string]$serviceRecovery.status -cne 'PASS' -or [bool]$serviceRecovery.forcedDaemonTermination) {
    throw "Trusted Multipass service recovery did not PASS normally: $($serviceRecovery | ConvertTo-Json -Compress -Depth 6)"
}

$forcedControls = [System.Collections.Generic.List[string]]::new()
$forcedDaemonIds = [System.Collections.Generic.List[int]]::new()
$forcedRecovery = $module.Invoke({
    param($controls,$daemonIds,$deadline)
    $script:lookupCount = 0
    $script:daemonStopped = $false
    $script:serviceStarted = $false
    $script:clock = [datetime]::UtcNow
    $lookup = {
        $script:lookupCount++
        $state = if ($script:serviceStarted) { 'Running' } elseif ($script:daemonStopped) { 'Stopped' } elseif ($script:lookupCount -eq 1) { 'Running' } else { 'Stop Pending' }
        [pscustomobject]@{ Name='Multipass'; State=$state; ProcessId=4242; PathName='"C:\Program Files\Multipass\bin\multipassd.exe" /svc'; StartName='NT AUTHORITY\SYSTEM' }
    }
    $control = { param($Action) [void]$controls.Add([string]$Action); if ($Action -eq 'start') { $script:serviceStarted = $true } }
    $clockProvider = { $script:clock = $script:clock.AddSeconds(5); $script:clock }
    $daemonStop = { param($Id) [void]$daemonIds.Add([int]$Id); $script:daemonStopped = $true }
    Invoke-DevFleetMultipassControlPlaneRecovery `
        -Reason 'POST_LAUNCH_INVENTORY_TRANSPORT_FAILURE' `
        -MultipassPath 'C:\Program Files\Multipass\bin\multipass.exe' `
        -OwnerDeadlineUtc $deadline `
        -ServiceLookupProvider $lookup `
        -ServiceControlProvider $control `
        -DaemonLookupProvider { param($Id) [pscustomobject]@{ ProcessName='multipassd'; Path='C:\Program Files\Multipass\bin\multipassd.exe' } } `
        -DaemonStopProvider $daemonStop `
        -ClockProvider $clockProvider `
        -SleepProvider { param($Milliseconds) }
}, $forcedControls, $forcedDaemonIds, ([datetime]::UtcNow.AddSeconds(180)))
if (-not [bool]$forcedRecovery.forcedDaemonTermination -or ($forcedDaemonIds -join '|') -cne '4242') {
    throw "Stop-Pending fallback did not terminate only the exact service-bound daemon PID: $($forcedRecovery | ConvertTo-Json -Compress -Depth 6) ids=$($forcedDaemonIds -join '|')"
}
if (($forcedControls -join '|') -cne 'stop|start') { throw "Forced recovery service controls differed: $($forcedControls -join '|')." }

[pscustomobject]@{
    status = 'PASS'
    controlPlaneRecovery = [string]$controlPlaneResult.recovery
    trustedServiceRecovery = [string]$serviceRecovery.status
    forcedDaemonRecovery = [bool]$forcedRecovery.forcedDaemonTermination
} | ConvertTo-Json -Depth 4
