# DevFleet source part 090

Full-source UTF-8 byte interval [4138500, 4185000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 05b2ad58d8703a0ee8fd9b1e580c63857adb74335af263f157f9d171066cf87d

<!-- BEGIN SOURCE SLICE -->
TotalSeconds, 3)
} | ConvertTo-Json -Depth 4
if ($failures.Count) { exit 1 }

```


## FILE: source/tests/Test-HostSecretRecovery.ps1

SHA256: 8057414f92b8d1c4f9f68a64507737d4a1eac26b6a73051c774a86b0fa7f75ec | Bytes: 2163 | Git mode: 100644

```
$ErrorActionPreference = 'Stop'
$originalProgramData = $env:ProgramData
$testProgramData = Join-Path ([IO.Path]::GetTempPath()) "devfleet-secret-tests-$([guid]::NewGuid().ToString('N'))"
$env:ProgramData = $testProgramData
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\DevFleet.Common.psm1') -Force

function Reset-State([switch]$Existing) {
    $root = Get-DevFleetStateRoot
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $root 'secrets') -Force | Out-Null
    if ($Existing) { [IO.File]::WriteAllText((Join-Path $root 'node-identity.json'),' {"schema_version":1,"node_id":"fixture"} ') }
    return $root
}
function Assert-RecoveryRequired([scriptblock]$Action) {
    try { & $Action; throw 'Expected SECRET RECOVERY REQUIRED.' }
    catch { if ($_.Exception.Message -notmatch '^SECRET RECOVERY REQUIRED') { throw } }
}

try {
    $root = Reset-State
    $fresh = Get-OrCreateSecrets
    if (-not (Test-DevFleetSecretRecord $fresh) -or [int]$fresh.SchemaVersion -ne 2 -or [string]$fresh.SecretGeneration -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Fresh secret generation is invalid.' }

    $root = Reset-State -Existing
    Assert-RecoveryRequired { Get-OrCreateSecrets | Out-Null }

    $root = Reset-State -Existing
    [IO.File]::WriteAllText((Join-Path $root 'secrets\host-secrets.json'),'{not-json')
    Assert-RecoveryRequired { Get-OrCreateSecrets | Out-Null }

    $root = Reset-State -Existing
    [IO.File]::WriteAllText((Join-Path $root 'secrets\host-secrets.json'),'{"PortalAdminUser":"dylan"}')
    Assert-RecoveryRequired { Get-OrCreateSecrets | Out-Null }

    $first = New-DevFleetSecretRecord
    $second = New-DevFleetSecretRecord
    if ($first.SecretGeneration -eq $second.SecretGeneration -or $first.NodeApiToken -eq $second.NodeApiToken) { throw 'Re-key generations or token material were reused.' }
    'PASS host secret fail-closed and generation tests'
} finally {
    $env:ProgramData = $originalProgramData
    if (Test-Path -LiteralPath $testProgramData) { Remove-Item -LiteralPath $testProgramData -Recurse -Force }
}

```


## FILE: source/tests/Test-MultipassLaunchTimeoutEnvelope.ps1

SHA256: 01bec115b8ef4905b78b5391341c5c62a6ebc1955795a756ba19d9fbc6bfda97 | Bytes: 12850 | Git mode: 100644

```
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

```


## FILE: source/tests/Test-MultipassStandardInputTransport.ps1

SHA256: 919655da1d747a27c7e965502ade0de80ac42feeb9592df7b84effa7b79c2ae0 | Bytes: 12157 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$sourceRoot=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $sourceRoot 'windows/DevFleet.Common.psm1') -Force -DisableNameChecking
$module=Get-Module DevFleet.Common
$bash='C:\Program Files\Git\bin\bash.exe'
$python=(Get-Command python.exe -ErrorAction Stop).Source
if(-not(Test-Path $bash)){throw 'Existing Git Bash is required for the local shell boundary tests.'}
function UnixPath([string]$Path){$p=[IO.Path]::GetFullPath($Path).Replace('\','/');if($p-match'^([A-Za-z]):/(.*)$'){return '/'+$Matches[1].ToLowerInvariant()+'/'+$Matches[2]};$p}
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-input transport O'Hara "+[guid]::NewGuid().ToString('N'))
$checks=[Collections.Generic.List[object]]::new()
$priorContext=Get-DevFleetDeadlineContext
try {
    New-Item -ItemType Directory -Path $fixtureRoot|Out-Null
    $bin=Join-Path $fixtureRoot 'bin';New-Item -ItemType Directory -Path $bin|Out-Null
    # jq is an external dependency. Use a real JSON parser for this local
    # fixture, while executing the production Bash input helper unchanged.
    $jq=@'
#!/usr/bin/env bash
"$DEVFLEET_TEST_PYTHON" -c 'import json,sys; value=json.load(open(sys.argv[-1],encoding="utf-8")); sys.exit(0 if isinstance(value,dict) else 1)' "$(cygpath -w "${@: -1}")"
'@
    [IO.File]::WriteAllText((Join-Path $bin 'jq'),$jq.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
    & $bash --noprofile --norc -c ('chmod +x -- '+(ConvertTo-ShellSingleQuotedScalar (UnixPath (Join-Path $bin 'jq'))))
    if($LASTEXITCODE-ne0){throw 'Local JSON parser fixture could not be made executable.'}
    $originalExternal=& $module {(Get-Command Invoke-External).ScriptBlock}
    $parserProbe=Join-Path $fixtureRoot 'parser-probe.json'
    [IO.File]::WriteAllText($parserProbe,'{"kind":"dummy"}',[Text.UTF8Encoding]::new($false))
    $parserCommand='export DEVFLEET_TEST_PYTHON='+(ConvertTo-ShellSingleQuotedScalar (UnixPath $python))+'; '+(ConvertTo-ShellSingleQuotedScalar (UnixPath (Join-Path $bin 'jq')))+' -e '+(ConvertTo-ShellSingleQuotedScalar 'type == "object"')+' '+(ConvertTo-ShellSingleQuotedScalar (UnixPath $parserProbe))
    & $originalExternal $bash @('--noprofile','--norc','-c',$parserCommand) -TimeoutSeconds 10
    & $module {param($original)$script:TransportOriginalExternal=$original} $originalExternal
    & $module {
        function script:Invoke-External {
            param($FilePath,[string[]]$ArgumentList,[int]$TimeoutSeconds,[datetime]$DeadlineUtc,[string]$StandardInputText,[switch]$Capture)
            $s=$script:TransportFixture;$index=$s.calls.Count+1
            $s.calls.Add([pscustomobject]@{index=$index;verb=$ArgumentList[0];hasInput=([bool]$StandardInputText);argumentContainsDummy=([bool](($ArgumentList-join' ').Contains($s.dummy)));deadline=$DeadlineUtc;timeout=$TimeoutSeconds})
            if($ArgumentList[0]-ceq'transfer'){
                if($ArgumentList[1]-cne'-'-or$ArgumentList[2]-notmatch'^[A-Za-z0-9._-]+:/run/devfleet-input-[0-9a-f]{32}/input$'){throw 'Unexpected transfer framing.'}
                $program='import pathlib,sys; p=pathlib.Path(sys.argv[1]); assert p.is_file(); data=sys.stdin.buffer.read(); p.write_bytes(data); sys.exit(int(sys.argv[2]))'
                $exitCode=if($s.mode-in@('transfer-failure','combined-failure')){77}else{0}
                & $script:TransportOriginalExternal $s.python @('-c',$program,$s.localInput,[string]$exitCode) -StandardInputText $StandardInputText -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $DeadlineUtc
                $s.transferredSha256=(Get-FileHash -LiteralPath $s.localInput -Algorithm SHA256).Hash.ToLowerInvariant()
                $s.transferredBytes=(Get-Item -LiteralPath $s.localInput).Length
                if($s.mode-ceq'bad-file-mode'){& $script:TransportOriginalExternal $s.bash @('--noprofile','--norc','-c',('chmod 0644 -- '+(ConvertTo-ShellSingleQuotedScalar $s.unixInput))) -TimeoutSeconds 5}
                return
            }
            if($ArgumentList[0]-cne'exec'-or$ArgumentList[2]-cne'--'-or$ArgumentList[3]-cne'bash'-or$ArgumentList[4]-cne'-lc'-or$StandardInputText){throw 'Unexpected exec or secret bytes on exec.'}
            if(($s.mode-ceq'cleanup-failure'-and$index-eq4)-or($s.mode-ceq'combined-failure'-and$index-eq3)){throw 'fixture cleanup unavailable'}
            $command=[string]$ArgumentList[5]
            $match=[regex]::Match($command,'/run/devfleet-input-[0-9a-f]{32}')
            if(-not$match.Success){throw 'No exact private input path.'}
            $remoteDirectory=$match.Value
            $command=$command.Replace((ConvertTo-ShellSingleQuotedScalar ($remoteDirectory+'/input')),(ConvertTo-ShellSingleQuotedScalar $s.unixInput)).Replace((ConvertTo-ShellSingleQuotedScalar $remoteDirectory),(ConvertTo-ShellSingleQuotedScalar $s.unixDirectory))
            if($s.mode-ceq'prepare-collision'-and$index-eq1){New-Item -ItemType Directory -Path $s.localDirectory|Out-Null;[IO.File]::WriteAllText((Join-Path $s.localDirectory 'foreign-marker'),'keep')}
            # Git Bash cannot enforce Linux mkdir modes on the inherited
            # Windows ACL. Map sudo/mode observations as external OS I/O;
            # keep real creation, collision, content, redirection and unlink.
            $modeFailure=if($s.mode-ceq'bad-file-mode'-and$index-ge3){'1'}else{'0'}
            $prepareFailure=if($s.mode-ceq'prepare-partial-failure'){'1'}else{'0'}
            $prefix='sudo(){ if [[ "$1" == mkdir ]]; then command mkdir -- "${@: -1}"; elif [[ "$1" == chown && "$DEVFLEET_TEST_PREPARE_FAILURE" == 1 ]]; then return 42; else "$@"; fi; }; stat(){ if [[ "$2" == "%a:%u" ]]; then if [[ "${@: -1}" == */input ]]; then if [[ "$DEVFLEET_TEST_BAD_MODE" == 1 ]]; then printf "644:%s\n" "$(id -u)"; else printf "600:%s\n" "$(id -u)"; fi; else printf "700:%s\n" "$(id -u)"; fi; else command stat "$@"; fi; }; export -f sudo stat; export DEVFLEET_TEST_PREPARE_FAILURE='+$prepareFailure+'; export DEVFLEET_TEST_BAD_MODE='+$modeFailure+'; export PATH='+(ConvertTo-ShellSingleQuotedScalar $s.unixBin)+':"$PATH"; export DEVFLEET_TEST_PYTHON='+(ConvertTo-ShellSingleQuotedScalar $s.unixPython)+'; export DEVFLEET_TEST_STAGE_DIR='+(ConvertTo-ShellSingleQuotedScalar $s.unixDirectory)+'; '
            & $script:TransportOriginalExternal $s.bash @('--noprofile','--norc','-c',($prefix+$command)) -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $DeadlineUtc -Capture:$Capture
        }
    }
    foreach($mode in @('success','unicode','transfer-failure','consumer-failure','bad-file-mode','prepare-collision','prepare-partial-failure','cleanup-failure','combined-failure','expired-owner','short-stage','bad-identity','bad-command','empty-input')){
        $caseRoot=Join-Path $fixtureRoot $mode;New-Item -ItemType Directory -Path $caseRoot|Out-Null
        $dummy=if($mode-ceq'unicode'){'{"kind":"dummy café","value":"quote\" and escaped\nline"}'}else{'{"kind":"dummy"}'}
        if($mode-ceq'empty-input'){$dummy=''}
        $state=[pscustomobject]@{mode=$mode;dummy=$dummy;calls=[Collections.Generic.List[object]]::new();transferredSha256='';transferredBytes=0;bash=$bash;python=$python;localDirectory=(Join-Path $caseRoot 'stage');localInput=(Join-Path $caseRoot 'stage/input');unixDirectory=(UnixPath (Join-Path $caseRoot 'stage'));unixInput=(UnixPath (Join-Path $caseRoot 'stage/input'));unixBin=(UnixPath $bin);unixPython=(UnixPath $python)}
        & $module {param($state)$script:TransportFixture=$state} $state
        $global:DevFleetDeadlineContext=$null
        $helper=ConvertTo-ShellSingleQuotedScalar (UnixPath (Join-Path $sourceRoot 'linux/bootstrap-input.sh'))
        $consumer='set -Eeuo pipefail; test ! -e "$DEVFLEET_TEST_STAGE_DIR"; source '+$helper+'; captured=$(devfleet_capture_json_stdin "$1/captured.XXXXXX" $(($(date +%s)+3))); trap ''rm -f -- "$captured"'' EXIT; sha256sum "$captured" | cut -d " " -f 1'
        if($mode-ceq'consumer-failure'){$consumer='exit 23'}
        if($mode-ceq'bad-command'){$consumer="echo invalid`ncommand"}
        $deadline=[datetime]::UtcNow.AddSeconds(45)
        if($mode-ceq'expired-owner'){$deadline=[datetime]::UtcNow.AddSeconds(5)}
        if($mode-ceq'short-stage'){Set-DevFleetDeadlineContext -TransactionDeadlineUtc ([datetime]::UtcNow.AddSeconds(5)) -StageName 'test' -StageBudgetSeconds 5|Out-Null}
        $name=if($mode-ceq'bad-identity'){'foreign;command'}else{'devfleet-primary'}
        $output='';$errorText='';$timer=[Diagnostics.Stopwatch]::StartNew()
        try{$output=Invoke-MultipassWithStandardInput -FilePath 'fixture-multipass.exe' -InstanceName $name -CommandArgumentList @('bash','-c',$consumer,'--',(UnixPath $caseRoot)) -StandardInputText $dummy -TimeoutSeconds 45 -DeadlineUtc $deadline -Capture}catch{$errorText=$_.Exception.Message}
        $timer.Stop()
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($dummy))).ToLowerInvariant()
        $exists=Test-Path $state.localDirectory
        $secretOnlyOnTransfer=@($state.calls|Where-Object{$_.hasInput-and$_.verb-cne'transfer'}).Count-eq0
        $noSecretArgs=@($state.calls|Where-Object argumentContainsDummy).Count-eq0
        $bounded=@($state.calls|Where-Object{$_.deadline-gt$deadline.AddSeconds(-5)}).Count-eq0
        if($state.calls.Count-ge2){$bounded=$bounded-and($state.calls[0].deadline-le$deadline.AddSeconds(-15))-and($state.calls[1].deadline-le$deadline.AddSeconds(-15))}
        $pass=switch($mode){
            {$_-in@('success','unicode')} {$output.Trim()-ceq$hash-and-not$errorText-and-not$exists-and$state.calls.Count-eq4;break}
            'transfer-failure' {$errorText-match'exit code 77'-and-not$exists-and$state.calls.Count-eq3;break}
            'consumer-failure' {$errorText-match'exit code 23'-and-not$exists-and$state.calls.Count-eq4;break}
            'bad-file-mode' {$errorText-match'exit code 1'-and-not$exists-and$state.calls.Count-eq4;break}
            'prepare-collision' {$errorText-match'exit code 1'-and(Test-Path (Join-Path $state.localDirectory 'foreign-marker'))-and$state.calls.Count-eq1;break}
            'prepare-partial-failure' {$errorText-match'exit code 42'-and-not$exists-and$state.calls.Count-eq1;break}
            'cleanup-failure' {$errorText-match'cleanup unavailable'-and-not$exists-and$state.calls.Count-eq4;break}
            'combined-failure' {$errorText-match'exit code 77'-and$errorText-match'Guest input cleanup failed'-and$errorText-match'cleanup unavailable'-and$exists-and$state.calls.Count-eq3;break}
            default {$errorText-and$state.calls.Count-eq0-and-not$exists}
        }
        $checks.Add([pscustomobject]@{case=$mode;pass=[bool]($pass-and$secretOnlyOnTransfer-and$noSecretArgs-and$bounded-and(-not$dummy-or-not$errorText.Contains($dummy)));calls=$state.calls.Count;elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3);stagingRemains=$exists;transferredBytes=$state.transferredBytes;expectedBytes=[Text.Encoding]::UTF8.GetByteCount($dummy);transferredHashMatches=($state.transferredSha256-ceq$hash);error=if($pass){''}else{$errorText}})
    }
} finally {
    $global:DevFleetDeadlineContext=$priorContext
    $resolved=[IO.Path]::GetFullPath($fixtureRoot);$tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not$resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup escaped the temporary directory.'}
    if(Test-Path $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
[pscustomobject]@{status=if(@($checks|Where-Object{-not$_.pass}).Count){'FAIL'}else{'PASS'};passed=@($checks|Where-Object pass).Count;total=$checks.Count;checks=@($checks);vmOperations=0;realMultipassOperations=0;fixtureBoundary='Multipass external I/O, remote filesystem root/sudo and Linux mode observations are fixtures. Production orchestration, shell parsing, collision rejection, input helper, JSON parser, native stdin writer, file content/EOF and unlink execute locally. Linux ACL enforcement requires the actual guest gate.'}|ConvertTo-Json -Depth 5
if(@($checks|Where-Object{-not$_.pass}).Count){exit 1}

```


## FILE: source/tests/Test-PendingReboot.ps1

SHA256: 0dae89d672d2e5250c009b50f69f4b248e9315bd169cbb82a8828f72d7fff966 | Bytes: 1582 | Git mode: 100644

```
$ErrorActionPreference = 'Stop'
$common = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\DevFleet.Common.psm1'
Import-Module $common -Force
$cases = @(
    @{ name='clean absent'; cbs=$false; wu=$false; pfro=$null; expected=$false },
    @{ name='empty value'; cbs=$false; wu=$false; pfro=@(); expected=$false },
    @{ name='empty strings'; cbs=$false; wu=$false; pfro=@('','   '); expected=$false },
    @{ name='real rename'; cbs=$false; wu=$false; pfro=@('C:\source.tmp','C:\destination.tmp'); expected=$true },
    @{ name='real delete'; cbs=$false; wu=$false; pfro=@('C:\source.tmp',''); expected=$true },
    @{ name='CBS with empty value'; cbs=$true; wu=$false; pfro=@(''); expected=$true },
    @{ name='Windows Update with empty value'; cbs=$false; wu=$true; pfro=@(''); expected=$true },
    @{ name='multiple operations'; cbs=$false; wu=$false; pfro=@('C:\one','C:\two','C:\three',''); expected=$true }
)
foreach ($case in $cases) {
    $actual = Test-PendingRebootState -CbsPending:$case.cbs -WindowsUpdatePending:$case.wu -PendingFileRenameOperations $case.pfro
    if ([bool]$actual -ne [bool]$case.expected) { throw "PFRO semantic case failed: $($case.name) expected=$($case.expected) actual=$actual" }
}
$source = Get-Content $common -Raw
if ($source -match '(?m)\b(Remove|Set)-Item(Property)?\b[^\r\n]*PendingFileRenameOperations') { throw 'PFRO regression test detected registry mutation in shipping reboot detection.' }
[ordered]@{ status='PASS'; cases=$cases.Count; cbsAndWindowsUpdatePreserved=$true; registryMutated=$false } | ConvertTo-Json -Compress

```


## FILE: source/tests/Test-ProcessOutputDrain.ps1

SHA256: a553a80e8fbe8c2863faeacf3ccccf4261e7b7e636e819443a1f7410b44bbf1c | Bytes: 5755 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'windows\DevFleet.Common.psm1') -Force

$shell=(Get-Command powershell.exe -ErrorAction Stop).Source
$normal=Invoke-External -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command',"[Console]::Out.Write('complete-output')") -Capture
if($normal -cne 'complete-output'){throw 'Invoke-External did not preserve ordinary complete output.'}

$pidPath=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-common-inherited-pipe-"+[guid]::NewGuid().ToString('N')+'.pid')
$descendantPid=0
try{
    $escapedPidPath=$pidPath.Replace("'","''")
    $parentCommand="`$childInfo=[Diagnostics.ProcessStartInfo]::new();`$childInfo.FileName=(Get-Command powershell.exe).Source;`$childInfo.UseShellExecute=`$false;`$childInfo.CreateNoWindow=`$true;`$childInfo.ArgumentList.Add('-NoProfile');`$childInfo.ArgumentList.Add('-NonInteractive');`$childInfo.ArgumentList.Add('-Command');`$childInfo.ArgumentList.Add('Start-Sleep -Seconds 30');`$child=[Diagnostics.Process]::Start(`$childInfo);[IO.File]::WriteAllText('$escapedPidPath',[string]`$child.Id);exit 0"
    $timer=[Diagnostics.Stopwatch]::StartNew();$blocked=$false
    try{Invoke-External -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command',$parentCommand) -Capture|Out-Null}catch{if($_.Exception.Message -match 'redirected output was incomplete after the bounded post-exit drain'){$blocked=$true}else{throw}}
    $timer.Stop()
    if(-not $blocked -or $timer.Elapsed -ge [TimeSpan]::FromSeconds(15)){throw 'Invoke-External did not fail closed within the bounded post-exit drain allowance.'}
    if(-not(Test-Path -LiteralPath $pidPath) -or -not [int]::TryParse([IO.File]::ReadAllText($pidPath),[ref]$descendantPid)){throw 'Invoke-External inherited-handle fixture did not publish its descendant PID.'}
    $descendant=Get-Process -Id $descendantPid -ErrorAction Stop
    if($descendant.HasExited){throw 'Invoke-External killed a descendant merely to manufacture redirected-output EOF.'}
}finally{
    if($descendantPid -gt 0){Stop-Process -Id $descendantPid -Force -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

$tx='a'*32;$payload='b'*64
$computeBoundary=New-DevFleetBootstrapBoundary -Kind compute -InstanceName 'devfleet-primary' -TransactionId $tx -PayloadSha256 $payload -BootstrapMaxSeconds 6600 -PackageVersion '1.2.13' -NodeRole 'primary'
if($computeBoundary.multipassResolvedStageName -cne 'compute-devfleet-primary-multipass-resolved' -or $computeBoundary.isolationVerifiedStageName -cne 'compute-devfleet-primary-isolation-verified' -or $computeBoundary.instanceAbsentStageName -cne 'compute-devfleet-primary-instance-absent' -or $computeBoundary.instanceLaunchedStageName -cne 'compute-devfleet-primary-instance-launched' -or $computeBoundary.instanceReadyStageName -cne 'compute-devfleet-primary-instance-ready' -or $computeBoundary.payloadTransferredStageName -cne 'compute-devfleet-primary-payload-transferred' -or $computeBoundary.payloadExtractedStageName -cne 'compute-devfleet-primary-payload-extracted' -or $computeBoundary.completionStageName -cne 'compute-devfleet-primary'){throw 'Compute bootstrap boundary did not produce the allowlisted substep names.'}
if($computeBoundary.extractionCommand -notmatch 'unzip.+devfleet-payload\.zip' -or $computeBoundary.extractionCommand -match 'sudo\s+bash|(?i)password|apitoken|secret='){throw 'Compute extraction did not remain a distinct non-secret production boundary.'}
if($computeBoundary.bootstrapCommand -notmatch "bootstrap-compute\.sh.*--transaction-id '$tx'.*--payload-sha256 '$payload'.*--bootstrap-max-seconds '6600'.*--package-version '1\.2\.13'.*--node-role 'primary'" -or $computeBoundary.bootstrapCommand -match '(?i)password|apitoken|secret='){throw 'Compute bootstrap command did not preserve its non-secret identity contract.'}
$vaultBoundary=New-DevFleetBootstrapBoundary -Kind vault -InstanceName 'devfleet-vault' -TransactionId $tx -PayloadSha256 $payload -BootstrapMaxSeconds 3900 -PackageVersion 'vault' -NodeRole 'vault'
if($vaultBoundary.multipassResolvedStageName -cne 'vault-multipass-resolved' -or $vaultBoundary.isolationVerifiedStageName -cne 'vault-isolation-verified' -or $vaultBoundary.instancePresentStageName -cne 'vault-instance-present' -or $vaultBoundary.instanceStartedStageName -cne 'vault-instance-started' -or $vaultBoundary.instanceReadyStageName -cne 'vault-instance-ready' -or $vaultBoundary.payloadTransferredStageName -cne 'vault-payload-transferred' -or $vaultBoundary.payloadExtractedStageName -cne 'vault-payload-extracted' -or $vaultBoundary.completionStageName -cne 'vault'){throw 'Vault bootstrap boundary did not produce the allowlisted substep names.'}
if($vaultBoundary.extractionCommand -notmatch 'unzip.+devfleet-vault-payload\.zip' -or $vaultBoundary.extractionCommand -match 'sudo\s+bash|(?i)password|resticpassword|secret='){throw 'Vault extraction did not remain a distinct non-secret production boundary.'}
if($vaultBoundary.bootstrapCommand -notmatch "bootstrap-vault\.sh.*--transaction-id '$tx'.*--payload-sha256 '$payload'.*--bootstrap-max-seconds '3900'.*--package-version 'vault'.*--node-role 'vault'" -or $vaultBoundary.bootstrapCommand -match '(?i)password|resticpassword|secret='){throw 'Vault bootstrap command did not preserve its non-secret identity contract.'}

[ordered]@{ok=$true;tests=8;ordinaryCompleteOutput=$true;inheritedPipeFailsClosedBoundedly=$true;computeExtractionSeparated=$true;vaultExtractionSeparated=$true;computeBoundaryIdentityBound=$true;vaultBoundaryIdentityBound=$true;substepNamesAllowlisted=$true;secretsExcludedFromArguments=$true}|ConvertTo-Json -Compress

```


## FILE: source/tests/Test-TailscaleBrowserPairing.ps1

SHA256: 4cae989aa96639e30e27d4a444b2bf1ae1c6f922d1cb5203f522b5db7e52408e | Bytes: 5498 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$WarningPreference='SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot '../windows/DevFleet.Tailscale.psm1') -Force
$module=Get-Module DevFleet.Tailscale
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$results.Add([pscustomobject]@{case=$Name;pass=$Pass})}
foreach($item in @(
    @('https://login.tailscale.com/a/fixture123',$true),
    @('http://login.tailscale.com/a/fixture123',$false),
    @('https://login.tailscale.com.evil.example/a/fixture123',$false),
    @('https://evil.example/?https://login.tailscale.com/a/fixture123',$false),
    @('https://evil@login.tailscale.com/a/fixture123',$false),
    @('https://login.tailscale.com:8443/a/fixture123',$false),
    @('https://login.tailscale.com/a/fixture123?redirect=evil',$false),
    @('https://login.tailscale.com/a/fixture123#evil',$false),
    @('https://login.tailscale.com/a/one https://login.tailscale.com/a/two',$false),
    @('https://login.tailscale.com/a/fixture123 https://login.tailscale.com/a/fixture123',$true)
)){
    $uri=&$module {param($s)Get-DevFleetTailscaleAuthenticationUri $s} $item[0]
    Check ('official browser URL case '+$results.Count) ([bool]$uri-eq$item[1])
}
foreach($item in @(@('Running','100.64.1.2',$true),@('NeedsLogin','100.64.1.2',$false),@('Running','192.168.1.2',$false),@('Running','100.1.1.2',$false),@('Running','100.128.1.2',$false),@('Running','fd7a:115c:a1e0::1',$false))){
    $ip=&$module {param($s,$ip)Get-DevFleetAuthenticatedTailscaleIPv4 (@{BackendState=$s;TailscaleIPs=@($ip)}|ConvertTo-Json -Compress)} $item[0] $item[1]
    Check ('authenticated private IPv4 '+$item[0]+'/'+$item[1]) ([bool]$ip-eq$item[2])
}
&$module {
    function script:Get-DevFleetDeadlineContext {return $script:PairingFixtureContext}
    function script:Open-DevFleetTailscaleAuthenticationPage {param($Uri)$script:PairingFixtureOpened++;if($Uri.AbsoluteUri-cne'https://login.tailscale.com/a/fixture123'){throw 'Unexpected browser target.'}}
    function script:Start-Sleep {param($Milliseconds)}
    function script:Invoke-External {
        param($FilePath,$ArgumentList,[switch]$Capture,[switch]$IgnoreExitCode,$TimeoutSeconds,$DeadlineUtc)
        if(-not$Capture-or-not$IgnoreExitCode-or$TimeoutSeconds-gt35-or$DeadlineUtc-gt$script:PairingFixtureDeadline){throw 'Native command lost its bounded capture contract.'}
        $script:PairingFixtureCalls.Add([pscustomobject]@{path=$FilePath;args=@($ArgumentList);timeout=$TimeoutSeconds})
        if($ArgumentList-contains'up'){
            $script:PairingFixtureUp++
            if($ArgumentList-notcontains'--timeout=30s'-or$ArgumentList-notcontains'--accept-dns=false'-or$ArgumentList-contains'--auth-key'){throw 'Unexpected authentication authority.'}
            if($script:PairingFixtureCase-eq'bad-url'){return 'https://evil.example/a/fake'}
            return 'To authenticate, visit: https://login.tailscale.com/a/fixture123'
        }
        if($ArgumentList-notcontains'--json'){throw 'Status request arguments were lost.'}
        if($script:PairingFixtureCase-eq'malformed'){return 'malformed status'}
        $connected=$script:PairingFixtureCase-eq'already-connected'-or$script:PairingFixtureOpened-gt0
        return (@{BackendState=if($connected){'Running'}else{'NeedsLogin'};TailscaleIPs=if($connected){@('100.64.1.2')}else{@()}}|ConvertTo-Json -Compress)
    }
}
foreach($target in @('windows','guest')){
    foreach($case in @('already-connected','browser-required','bad-url','deadline-exhausted','parent-deadline')){
        $v=&$module {
            param($Case,$Target)
            $script:PairingFixtureCase=$Case;$script:PairingFixtureOpened=0;$script:PairingFixtureUp=0;$script:PairingFixtureCalls=[Collections.Generic.List[object]]::new();$script:PairingFixtureContext=$null
            $script:PairingFixtureDeadline=[datetime]::UtcNow.AddSeconds($(if($Case-eq'deadline-exhausted'){3}else{60}))
            if($Case-eq'parent-deadline'){$script:PairingFixtureContext=[pscustomobject]@{StageDeadlineUtc=[datetime]::UtcNow.AddSeconds(3)}}
            $parameters=@{FilePath=if($Target-eq'guest'){'multipass-fixture.exe'}else{'tailscale-fixture.exe'};Hostname='devfleet-fixture';DeadlineUtc=$script:PairingFixtureDeadline}
            if($Target-eq'guest'){$parameters.InstanceName='devfleet-vault'}
            $result=$null;$failed=$false
            try{$result=Invoke-DevFleetTailscaleBrowserPairing @parameters}catch{$failed=$true}
            [pscustomobject]@{result=$result;failed=$failed;calls=@($script:PairingFixtureCalls);up=$script:PairingFixtureUp;opened=$script:PairingFixtureOpened}
        } $case $target
        $pass=switch($case){
            'already-connected' {-not$v.failed-and$v.result.authenticated-and$v.up-eq0-and$v.opened-eq0}
            'browser-required' {-not$v.failed-and$v.result.authenticated-and$v.up-eq1-and$v.opened-eq1}
            'bad-url' {$v.failed-and$v.up-eq1-and$v.opened-eq0}
            default {$v.failed-and$v.calls.Count-eq0-and$v.opened-eq0}
        }
        if($target-eq'guest'-and$v.calls.Count){$pass=$pass-and($v.calls[0].args[0..4]-join' ')-ceq'exec devfleet-vault -- sudo tailscale'}
        Check ($target+' '+$case) $pass
    }
}
$results|ConvertTo-Json -Depth 4
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Browser pairing qualification failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) browser pairing checks; no browser, network or VM operations performed."

```


## FILE: source/tests/Test-TailscaleGuestOAuthTransport.ps1

SHA256: 3767e97aab7be361db254c680245813726b437c4baf2017511d4dbcffbec5dab | Bytes: 7089 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

$sourceRoot = Join-Path $WorkspaceRoot 'source'
$commonPath = Join-Path $sourceRoot 'windows\DevFleet.Common.psm1'
$tailscalePath = Join-Path $sourceRoot 'windows\DevFleet.Tailscale.psm1'
$commonModule = Import-Module $commonPath -Force -PassThru
$state = [ordered]@{
    calls = [System.Collections.Generic.List[object]]::new()
    transferInputs = [System.Collections.Generic.List[string]]::new()
    consume = ''
    consumeIgnoreExitCode = $false
    statusCalls = 0
    initialStatus = [ordered]@{ BackendState = 'NeedsLogin'; Self = [ordered]@{ HostName = 'fixture-node'; Online = $false }; TailscaleIPs = @(); Health = @() } | ConvertTo-Json -Depth 5 -Compress
    finalStatus = [ordered]@{ BackendState = 'Running'; Self = [ordered]@{ HostName = 'fixture-node'; Online = $true }; TailscaleIPs = @('100.64.1.2'); Health = @() } | ConvertTo-Json -Depth 5 -Compress
    preferences = ([ordered]@{ AdvertiseTags = @('tag:devfleet-e2e') } | ConvertTo-Json -Depth 3 -Compress)
}
$originalExternal = & $commonModule { (Get-Command Invoke-External -CommandType Function).ScriptBlock }
$fixtureState = $state
$externalFixture = {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int[]]$RedactArgumentIndexes = @(),
        [int]$TimeoutSeconds = 900,
        [int]$MaxDiagnosticChars = 12000,
        [string]$EvidenceLogPath = '',
        [string]$StandardInputText = '',
        [datetime]$DeadlineUtc = [datetime]::MinValue,
        [int[]]$AllowedExitCodes = @(0),
        [switch]$IgnoreExitCode,
        [switch]$Capture
    )
    $s = $fixtureState
    $args = @($ArgumentList)
    [void]$s.calls.Add([pscustomobject]@{ arguments = $args; input = [string]$StandardInputText })
    if ($args.Count -ge 6 -and $args[0] -ceq 'exec' -and $args[3] -ceq 'bash' -and $args[4] -ceq '-lc') {
        $command = [string]$args[5]
        if ($command -match 'mkdir -m 0700') { return }
        if ($command -match "exec 'bash' '-lc' ") {
            $s.consume = $command
            $s.consumeIgnoreExitCode = [bool]$IgnoreExitCode
            if (-not $IgnoreExitCode) { throw 'fixture multipass failed with exit code 1 DEVFLEET_TAILSCALE_UP_EXIT=0' }
            return 'DEVFLEET_TAILSCALE_UP_EXIT=0'
        }
        if ($command -match 'test -e') { return }
    }
    if ($args.Count -gt 0 -and $args[0] -ceq 'transfer') {
        [void]$s.transferInputs.Add([string]$StandardInputText)
        return
    }
    if ($args -contains 'status') {
        $s.statusCalls = [int]$s.statusCalls + 1
        if ([int]$s.statusCalls -eq 1) { return [string]$s.initialStatus }
        return [string]$s.finalStatus
    }
    if ($args -contains 'debug') { return $s.preferences }
    throw 'Unexpected command in guest OAuth transport fixture.'
}.GetNewClosure()
$result = $null
$errorText = ''
& $commonModule { param($stub) Set-Item Function:\Invoke-External -Value $stub } $externalFixture
try {
    # Common is already loaded with the fixture, so the Tailscale module
    # imports that exact fixture-backed dependency and the production pairing
    # takes its no-CommandInvoker path.
    $tailscaleModule = Import-Module $tailscalePath -Force -PassThru
    $optionsProvider = { [pscustomobject]@{ mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true; hostname = 'fixture-node'; targetRole = 'Fixture'; instanceName = 'fixture-guest'; secret = 'fixture-oauth-client-secret'; credentialSource = 'fixture-only' } }
    $parameters = @{
        FilePath = 'fixture-multipass.exe'; InstanceName = 'fixture-guest'; Hostname = 'fixture-node'; DeadlineUtc = [datetime]::UtcNow.AddSeconds(60)
        RunId = 'oauth-transport-fixture'; StageName = 'TAILSCALE-AUTH'; TargetRole = 'Fixture'
        EnrollmentProfileProvider = { [pscustomobject]@{ mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true } }
        EnrollmentOptionsProvider = $optionsProvider
        TailnetLockProvider = { [pscustomobject]@{ status = 'DISABLED'; observed = $true; enabled = $false } }
        ServiceStateProvider = { 'Running' }; PendingRebootProvider = { $false }
    }
    $result = & $tailscaleModule { param($p) Invoke-DevFleetTailscaleOAuthPairing @p } $parameters
} catch {
    $errorText = [string]$_.Exception.Message
} finally {
    & $commonModule { param($original) Set-Item Function:\Invoke-External -Value $original } $originalExternal
}

$secret = 'fixture-oauth-client-secret'
$argumentText = (@($state.calls) | ForEach-Object { @($_.arguments) -join ' ' }) -join ' '
$marker = "exec 'bash' '-lc' "
$markerIndex = [string]$state.consume.IndexOf($marker)
$guestArgument = if ([int]$markerIndex -ge 0) { [string]$state.consume.Substring([int]$markerIndex + $marker.Length).TrimEnd([char]13, [char]10) } else { '' }
$guestSyntaxPass = $false
$guestSyntaxError = ''
if ($guestArgument.Length -ge 2 -and $guestArgument.StartsWith("'") -and $guestArgument.EndsWith("'")) {
    $decodedGuestScript = $guestArgument.Substr