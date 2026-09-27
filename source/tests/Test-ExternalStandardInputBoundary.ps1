$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    & $pwshPath -NoProfile -File $PSCommandPath
    exit $LASTEXITCODE
}
$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root 'windows\DevFleet.Common.psm1'
Import-Module $modulePath -Force

$shell = (Get-Command powershell.exe -ErrorAction Stop).Source
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$python = Join-Path (Split-Path -Parent $root) '.venv-test\Scripts\python.exe'
$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0

function Check {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

function Invoke-IsolatedInputProbe {
    param(
        [Parameter(Mandatory)][string]$ChildCommand,
        [Parameter(Mandatory)][int]$InputLength,
        [Parameter(Mandatory)][int]$OwnerTimeoutSeconds,
        [Parameter(Mandatory)][int]$OuterTimeoutSeconds
    )
    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-stdin-probe-' + [guid]::NewGuid().ToString('N'))
    $runnerPath = Join-Path $probeRoot 'runner.ps1'
    $inputPath = Join-Path $probeRoot 'input.txt'
    $process = $null
    try {
        New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
        [IO.File]::WriteAllText($inputPath, ('X' * $InputLength), [Text.UTF8Encoding]::new($false))
$runner = @'
$ErrorActionPreference='Stop'
$ModulePath=$env:DEVFLEET_TEST_MODULE
$ShellPath=$env:DEVFLEET_TEST_SHELL
$ChildCommand=$env:DEVFLEET_TEST_CHILD_COMMAND
$InputPath=$env:DEVFLEET_TEST_INPUT_PATH
$TimeoutSeconds=[int]$env:DEVFLEET_TEST_TIMEOUT_SECONDS
Import-Module $ModulePath -Force
$inputText=[IO.File]::ReadAllText($InputPath)
try {
    $result=Invoke-External -FilePath $ShellPath -ArgumentList @('-NoProfile','-NonInteractive','-Command',$ChildCommand) -TimeoutSeconds $TimeoutSeconds -StandardInputText $inputText -Capture
    [Console]::Out.Write($result)
    exit 0
} catch {
    [Console]::Error.Write($_.Exception.Message)
    exit 91
}
'@
        [IO.File]::WriteAllText($runnerPath, $runner, [Text.UTF8Encoding]::new($false))
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $pwsh
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.Arguments = "-NoProfile -File `"$runnerPath`""
        $psi.EnvironmentVariables['DEVFLEET_TEST_MODULE'] = $modulePath
        $psi.EnvironmentVariables['DEVFLEET_TEST_SHELL'] = $shell
        $psi.EnvironmentVariables['DEVFLEET_TEST_CHILD_COMMAND'] = $ChildCommand
        $psi.EnvironmentVariables['DEVFLEET_TEST_INPUT_PATH'] = $inputPath
        $psi.EnvironmentVariables['DEVFLEET_TEST_TIMEOUT_SECONDS'] = [string]$OwnerTimeoutSeconds
        $process = [Diagnostics.Process]::Start($psi)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $finished = $process.WaitForExit($OuterTimeoutSeconds * 1000)
        if (-not $finished) {
            try { $process.Kill($true) } catch {}
            [void]$process.WaitForExit(5000)
        }
        $timer.Stop()
        [void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))
        return [pscustomobject]@{
            finished = $finished
            elapsedSeconds = $timer.Elapsed.TotalSeconds
            exitCode = if ($finished) { $process.ExitCode } else { $null }
            stdout = if ($stdoutTask.IsCompletedSuccessfully) { $stdoutTask.Result } else { '' }
            stderr = if ($stderrTask.IsCompletedSuccessfully) { $stderrTask.Result } else { '' }
        }
    } finally {
        if ($process -and -not $process.HasExited) { try { $process.Kill($true) } catch {} }
        if ($process) { $process.Dispose() }
        Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$neverReads = Invoke-IsolatedInputProbe -ChildCommand 'Start-Sleep -Seconds 30' -InputLength (4MB) -OwnerTimeoutSeconds 2 -OuterTimeoutSeconds 7
Check ($neverReads.finished -and $neverReads.exitCode -eq 91 -and $neverReads.stderr -match 'timed out') 'stdin writer is bounded when the child never reads stdin'

$backpressureCommand = "[Console]::Out.Write(('O'*1048576));[Console]::Error.Write(('E'*1048576));`$text=[Console]::In.ReadToEnd();if(`$text.Length -ne $([int](4MB))){exit 12};[Console]::Out.Write('|INPUT_OK|')"
$backpressure = Invoke-IsolatedInputProbe -ChildCommand $backpressureCommand -InputLength (4MB) -OwnerTimeoutSeconds 15 -OuterTimeoutSeconds 20
Check ($backpressure.finished -and $backpressure.exitCode -eq 0 -and $backpressure.stdout -match '\|INPUT_OK\|') 'stdout/stderr drains start before stdin delivery and avoid pipe backpressure deadlock'

$eofResult = Invoke-External -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command','$text=[Console]::In.ReadToEnd();[Console]::Out.Write($text.Length)') -TimeoutSeconds 5 -StandardInputText 'dummy-input' -Capture
Check ($eofResult -eq '11') 'stdin content and EOF are delivered exactly once'

$earlyExitError = ''
try {
    Invoke-External -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command','exit 23') -TimeoutSeconds 5 -StandardInputText ('X' * (4MB)) -Capture | Out-Null
} catch {
    $earlyExitError = $_.Exception.Message
}
Check ($earlyExitError -match 'failed with exit code 23') 'early child exit preserves direct exit-code semantics instead of surfacing a broken-pipe wrapper'

$brokenPipeError = ''
$brokenPipeTimer = [Diagnostics.Stopwatch]::StartNew()
try {
    Invoke-External -FilePath $python -ArgumentList @('-c','import os,time; os.close(0); time.sleep(30)') -TimeoutSeconds 10 -StandardInputText ('X' * (4MB)) -Capture | Out-Null
} catch {
    $brokenPipeError = $_.Exception.Message
} finally {
    $brokenPipeTimer.Stop()
}
Check ($brokenPipeError -match 'input delivery failed' -and $brokenPipeError -notmatch 'timed out after' -and $brokenPipeTimer.Elapsed.TotalSeconds -lt 4) 'a live child that breaks stdin preserves the input transport error and is bounded'

$deadlineError = ''
$deadlineTimer = [Diagnostics.Stopwatch]::StartNew()
try {
    Invoke-External -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 3;$null=[Console]::In.ReadToEnd();Start-Sleep -Seconds 30') -TimeoutSeconds 20 -DeadlineUtc ([datetime]::UtcNow.AddSeconds(5)) -StandardInputText ('X' * (4MB)) -Capture | Out-Null
} catch {
    $deadlineError = $_.Exception.Message
} finally {
    $deadlineTimer.Stop()
}
Check ($deadlineError -match 'timed out' -and $deadlineTimer.Elapsed.TotalSeconds -lt 5.5) 'one absolute deadline is shared across delayed stdin delivery and execution'

[pscustomobject]@{
    status = if ($failures.Count) { 'FAIL' } else { 'PASS' }
    passed = $passed
    failures = @($failures)
    neverReadElapsedSeconds = [math]::Round($neverReads.elapsedSeconds, 3)
    backpressureElapsedSeconds = [math]::Round($backpressure.elapsedSeconds, 3)
    brokenPipeElapsedSeconds = [math]::Round($brokenPipeTimer.Elapsed.TotalSeconds, 3)
    sharedDeadlineElapsedSeconds = [math]::Round($deadlineTimer.Elapsed.TotalSeconds, 3)
} | ConvertTo-Json -Depth 4
if ($failures.Count) { exit 1 }
