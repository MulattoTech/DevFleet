# DevFleet source part 091

Full-source UTF-8 byte interval [4185000, 4231500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8b1d0764a41a579e4c2407997feea5060c91fc5da71c8c05d2457e09f77e83e9

<!-- BEGIN SOURCE SLICE -->
[IO.Path]::GetTempPath()) ("devfleet-current-hostagent-"+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force|Out-Null
try {
    $tokenPath=Join-Path $testRoot 'token.txt';[IO.File]::WriteAllText($tokenPath,('x'*48))
    $configPath=Join-Path $testRoot 'config.json';$sshConfig=Join-Path $testRoot 'ssh-config';$knownHosts=Join-Path $testRoot 'known-hosts'
    @{HostId='mulattotechbox';HostName='MULATTOTECHBOX';TokenPath=$tokenPath;MultipassPath='multipass.exe';SshConfigPath=$sshConfig;SshKnownHostsPath=$knownHosts;SshPrivateKeyPath=(Join-Path $testRoot 'key')}|ConvertTo-Json|Set-Content -LiteralPath $configPath
    . (Join-Path $root 'windows\DevFleet-HostAgent.ps1') -ConfigPath $configPath -LibraryOnly

    $shell=(Get-Command powershell.exe -ErrorAction Stop).Source
    $script:Multipass=$shell
    $pidPath=Join-Path $testRoot 'hostagent-inherited-pipe.pid';$descendantPid=0
    try{
        $escapedPidPath=$pidPath.Replace("'","''")
        $parentCommand="`$childInfo=[Diagnostics.ProcessStartInfo]::new();`$childInfo.FileName=(Get-Command powershell.exe).Source;`$childInfo.UseShellExecute=`$false;`$childInfo.CreateNoWindow=`$true;`$childInfo.ArgumentList.Add('-NoProfile');`$childInfo.ArgumentList.Add('-NonInteractive');`$childInfo.ArgumentList.Add('-Command');`$childInfo.ArgumentList.Add('Start-Sleep -Seconds 30');`$child=[Diagnostics.Process]::Start(`$childInfo);[IO.File]::WriteAllText('$escapedPidPath',[string]`$child.Id);exit 0"
        $timer=[Diagnostics.Stopwatch]::StartNew();$blocked=$false
        try{Invoke-Multipass @('-NoProfile','-NonInteractive','-Command',$parentCommand) 20|Out-Null}catch{if($_.Exception.Message -match 'redirected output was incomplete after the bounded post-exit drain'){$blocked=$true}else{throw}}
        $timer.Stop()
        if(-not $blocked -or $timer.Elapsed -ge [TimeSpan]::FromSeconds(15)){throw 'Host Agent Multipass runner did not fail closed within the bounded post-exit drain allowance.'}
        if(-not(Test-Path -LiteralPath $pidPath) -or -not [int]::TryParse([IO.File]::ReadAllText($pidPath),[ref]$descendantPid)){throw 'Host Agent inherited-handle fixture did not publish its descendant PID.'}
        $descendant=Get-Process -Id $descendantPid -ErrorAction Stop
        if($descendant.HasExited){throw 'Host Agent runner killed a descendant merely to manufacture redirected-output EOF.'}
    }finally{
        if($descendantPid -gt 0){Stop-Process -Id $descendantPid -Force -ErrorAction SilentlyContinue}
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
        $script:Multipass='multipass.exe'
    }

    $runtime='devfleet-project-demo-project'
    [IO.File]::WriteAllText($knownHosts,"unrelated.example ssh-ed25519 AAAAunrelated`r`n")
    $markers=Get-ProjectVmKnownHostMarkers $runtime
    $first="$($markers.Begin)`r`n$runtime ssh-ed25519 AAAAfirst`r`n$($markers.End)"
    Set-DevFleetManagedTextBlock $knownHosts $markers.Pattern $first|Out-Null
    $initial=[IO.File]::ReadAllText($knownHosts)
    if($initial -notmatch 'AAAAfirst' -or $initial -notmatch 'AAAAunrelated'){throw 'Initial managed host-key pin did not preserve unrelated content.'}
    Set-DevFleetManagedTextBlock $knownHosts $markers.Pattern $first|Out-Null
    if([IO.File]::ReadAllText($knownHosts) -cne $initial){throw 'Re-syncing the same host key was not idempotent.'}
    $second="$($markers.Begin)`r`n$runtime ssh-ed25519 AAAAsecond`r`n$($markers.End)"
    Set-DevFleetManagedTextBlock $knownHosts $markers.Pattern $second|Out-Null
    $changed=[IO.File]::ReadAllText($knownHosts)
    if($changed -match 'AAAAfirst' -or $changed -notmatch 'AAAAsecond' -or $changed -notmatch 'AAAAunrelated'){throw 'Host-key rotation changed unrelated known-host content.'}

    $aliasMarkers=Get-ProjectVmSshMarkers $runtime
    [IO.File]::WriteAllText($sshConfig,"Host unrelated`r`n    HostName 192.0.2.10`r`n`r`n$($aliasMarkers.Begin)`r`nHost $runtime`r`n$($aliasMarkers.End)`r`n")
    Remove-ProjectVmSshAlias $runtime '12345678-1234-1234-1234-123456789abc'
    if((Get-Content -LiteralPath $sshConfig -Raw) -notmatch 'Host unrelated' -or (Get-Content -LiteralPath $sshConfig -Raw) -match [regex]::Escape($runtime)){throw 'Alias removal did not preserve unrelated SSH config.'}
    if((Get-Content -LiteralPath $knownHosts -Raw) -notmatch 'AAAAunrelated' -or (Get-Content -LiteralPath $knownHosts -Raw) -match 'AAAAsecond'){throw 'Host-key removal did not preserve unrelated entries.'}

    $bad=@{state='ready';managed_by='someone-else';host_id='mulattotechbox';runtime_id=$runtime;vm_name=$runtime;project_id='12345678-1234-1234-1234-123456789abc'}
    try {Remove-ImportFailedProjectVm 'demo-project' $bad @{backup_verified=$true;backup_id='backup';backup_sha256=('a'*64);local_archive_sha256=('b'*64);cleanup_stage='pre-import'}|Out-Null;throw 'Unowned VM cleanup unexpectedly succeeded.'} catch {if($_.Exception.Message -notmatch 'ownership registry'){throw}}

    $script:Alive=@{}
    function Get-MultipassVms {return @($script:Alive.GetEnumerator()|Where-Object{$_.Value}|ForEach-Object{[pscustomobject]@{name=$_.Key;state='RUNNING'}})}
    function Get-ProjectVmInfo {param([string]$VmName);return [pscustomobject]@{state='RUNNING'}}
    function New-ProvisioningLock {$lock=[pscustomobject]@{};$lock|Add-Member ScriptMethod ReleaseMutex {};$lock|Add-Member ScriptMethod Dispose {};return $lock}
    function Invoke-Multipass {
        param([string[]]$ArgumentList,[int]$TimeoutSeconds=120)
        $vm=[string]$ArgumentList[1]
        if($ArgumentList[0] -eq 'delete'){$script:Alive[$vm]=$false;return [pscustomobject]@{ExitCode=0;Text=''}}
        if($ArgumentList[0] -eq 'exec' -and ($ArgumentList -contains '/etc/devfleet/project-runtime.json')){$slug=$vm.Substring('devfleet-project-'.Length);return [pscustomobject]@{ExitCode=0;Text=(@{managed_by='devfleet';slug=$slug;project_id='12345678-1234-1234-1234-123456789abc'}|ConvertTo-Json -Compress)}}
        if($ArgumentList[0] -eq 'exec' -and ($ArgumentList|Where-Object{$_ -like '*/.devfleet/project.json'})){$slug=$vm.Substring('devfleet-project-'.Length);return [pscustomobject]@{ExitCode=0;Text=(@{slug=$slug;identity=$slug;project_id='12345678-1234-1234-1234-123456789abc'}|ConvertTo-Json -Compress)}}
        return [pscustomobject]@{ExitCode=0;Text=''}
    }
    foreach($case in @(@{slug='pre-import';stage='pre-import'},@{slug='post-import';stage='post-import'})){
        $vm="devfleet-project-$($case.slug)";$script:Alive[$vm]=$true
        $record=@{slug=$case.slug;state='ready';managed_by='devfleet';host_id='mulattotechbox';runtime_id=$vm;vm_name=$vm;project_id='12345678-1234-1234-1234-123456789abc';cpus=4;memory_gb=8;disk_gb=80}
        $registry=Read-Registry;$registry.projects[$case.slug]=$record;Write-Registry $registry
        $payload=@{backup_verified=$true;backup_id='backup';backup_sha256=('a'*64);local_archive_sha256=('b'*64);import_archive_sha256='';cleanup_stage=$case.stage}
        $result=Remove-ImportFailedProjectVm $case.slug $record $payload
        if(-not $result.allocation_released -or $result.state -ne 'destroyed' -or $script:Alive[$vm]){throw "$($case.stage) cleanup did not release its allocation."}
        if((Read-Registry).projects[$case.slug].state -ne 'destroyed'){throw "$($case.stage) cleanup did not persist the destroyed state."}
    }
    [ordered]@{ok=$true;tests=8;bounded_output_drain=$true;initial_pin=$true;idempotent_resync=$true;rotated_pin=$true;unrelated_preserved=$true;selective_remove=$true;unowned_refused=$true;pre_and_post_import_cleanup=$true}|ConvertTo-Json -Compress
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: source/tests/Test-EncryptedBundlePassphrase.ps1

SHA256: a25a97f7316a0c0d99bee1ecd3ca8da05cf74d20fce6dbf917f142a7240f1f27 | Bytes: 6875 | Git mode: 100644

```
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\DevFleet.Common.psm1'
$bundleModule = Import-Module $modulePath -Force -PassThru -DisableNameChecking
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "devfleet-pairing-passphrase-$([guid]::NewGuid().ToString('N'))"
$fixtureRoot = [IO.Path]::GetFullPath($fixtureRoot)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $fixtureRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture root escaped the temporary directory.' }
$checks = [Collections.Generic.List[object]]::new()
$fixturePassphrase = 'isolated-pairing-passphrase-2026'
$secure = ConvertTo-SecureString $fixturePassphrase -AsPlainText -Force
$wrong = ConvertTo-SecureString 'different-isolated-passphrase' -AsPlainText -Force
$short = ConvertTo-SecureString 'short' -AsPlainText -Force
$empty = [Security.SecureString]::new()

function Check([string]$Name, [bool]$Pass) {
    $checks.Add([pscustomobject]@{name=$Name;pass=$Pass})
    if (-not $Pass) { throw "Encrypted bundle regression failed: $Name" }
}
function Rejects([scriptblock]$Action) {
    try { & $Action | Out-Null; return $false }
    catch {
        if ($_.Exception.Message.Contains($fixturePassphrase)) { throw 'Passphrase was included in an exception.' }
        return $true
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $payload = Join-Path $fixtureRoot 'payload'; New-Item -ItemType Directory -Path $payload | Out-Null
    [IO.File]::WriteAllText((Join-Path $payload 'public-fixture.json'), '{"fixture":"isolated-pairing"}', [Text.UTF8Encoding]::new($false))
    & $bundleModule {
        param([Security.SecureString]$Value)
        $script:BundleTestPromptValue = $Value
        $script:BundleTestPromptCount = 0
        $script:BundleTestAllowPrompt = $false
        function script:Read-Host {
            param([string]$Prompt, [switch]$AsSecureString)
            $script:BundleTestPromptCount++
            if (-not $script:BundleTestAllowPrompt -or -not $AsSecureString) { throw 'Unexpected interactive passphrase request.' }
            return $script:BundleTestPromptValue
        }
    } $secure

    Check 'common helper parameters are SecureString' ((Get-Command New-EncryptedBundle).Parameters['Passphrase'].ParameterType -eq [Security.SecureString] -and (Get-Command Expand-EncryptedBundle).Parameters['Passphrase'].ParameterType -eq [Security.SecureString])
    foreach ($scriptName in @('10-Export-Desktop-Pairing.ps1', 'Complete-Cluster.ps1')) {
        $command = Get-Command (Join-Path (Split-Path -Parent $modulePath) $scriptName)
        Check "$scriptName accepts an in-process SecureString" ($command.Parameters['BundlePassphrase'].ParameterType -eq [Security.SecureString])
    }

    $bundle = Join-Path $fixtureRoot 'supplied.dfe'; $restored = Join-Path $fixtureRoot 'restored'
    $output = @(& {
        New-EncryptedBundle -SourceDirectory $payload -OutputPath $bundle -Passphrase $secure
        Expand-EncryptedBundle -BundlePath $bundle -Destination $restored -Passphrase $secure
    } *>&1)
    Check 'supplied passphrase round-trips without prompting' ((& $bundleModule { $script:BundleTestPromptCount }) -eq 0 -and (Get-FileHash (Join-Path $payload 'public-fixture.json')).Hash -ceq (Get-FileHash (Join-Path $restored 'public-fixture.json')).Hash)
    Check 'caller retains its SecureString and output is passphrase-free' ($secure.Length -eq $fixturePassphrase.Length -and -not (($output | ForEach-Object { [string]$_ }) -join "`n").Contains($fixturePassphrase))
    Check 'temporary ZIP is removed on successful creation and expansion' (-not (Test-Path -LiteralPath "$bundle.zip.tmp"))

    $wrongDestination = Join-Path $fixtureRoot 'wrong-password'
    Check 'incorrect passphrase is rejected before extraction' (Rejects { Expand-EncryptedBundle -BundlePath $bundle -Destination $wrongDestination -Passphrase $wrong })
    Check 'failed authentication leaves no plaintext destination or ZIP' (-not (Test-Path -LiteralPath $wrongDestination) -and -not (Test-Path -LiteralPath "$bundle.zip.tmp"))
    $tampered = Join-Path $fixtureRoot 'tampered.dfe'; $tamperedBytes = [IO.File]::ReadAllBytes($bundle)
    $tamperedBytes[$tamperedBytes.Length - 1] = $tamperedBytes[$tamperedBytes.Length - 1] -bxor 1
    [IO.File]::WriteAllBytes($tampered, $tamperedBytes)
    Check 'tampered authentication tag remains rejected' (Rejects { Expand-EncryptedBundle -BundlePath $tampered -Destination (Join-Path $fixtureRoot 'tampered-output') -Passphrase $secure })
    Check 'short explicitly supplied passphrase never falls back to prompting' (Rejects { New-EncryptedBundle -SourceDirectory $payload -OutputPath (Join-Path $fixtureRoot 'short.dfe') -Passphrase $short })
    Check 'empty explicitly supplied passphrase never falls back to prompting' (Rejects { New-EncryptedBundle -SourceDirectory $payload -OutputPath (Join-Path $fixtureRoot 'empty.dfe') -Passphrase $empty })
    Check 'failure paths did not prompt' ((& $bundleModule { $script:BundleTestPromptCount }) -eq 0)

    & $bundleModule { $script:BundleTestAllowPrompt = $true }
    $interactive = Join-Path $fixtureRoot 'interactive.dfe'
    New-EncryptedBundle -SourceDirectory $payload -OutputPath $interactive
    Expand-EncryptedBundle -BundlePath $interactive -Destination (Join-Path $fixtureRoot 'interactive-output')
    Check 'omitted passphrases retain both interactive SecureString prompts' ((& $bundleModule { $script:BundleTestPromptCount }) -eq 2)
    $leakedFiles = @(Get-ChildItem -LiteralPath $fixtureRoot -File -Recurse | Where-Object { [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($_.FullName)).Contains($fixturePassphrase) })
    Check 'passphrase was never persisted in any fixture file' ($leakedFiles.Count -eq 0)
    Write-Host "PASS $($checks.Count)/$($checks.Count) encrypted-bundle passphrase checks; temporary files only, no installed state or lab touched."
} finally {
    & $bundleModule { Remove-Item Function:script:Read-Host -ErrorAction SilentlyContinue; Remove-Variable BundleTestPromptValue,BundleTestPromptCount,BundleTestAllowPrompt -Scope Script -ErrorAction SilentlyContinue }
    foreach ($value in @($secure, $wrong, $short, $empty)) { if ($null -ne $value) { $value.Dispose() } }
    if (Test-Path -LiteralPath $fixtureRoot) {
        $resolvedFixture = (Get-Item -LiteralPath $fixtureRoot).FullName
        if (-not $resolvedFixture.Equals($fixtureRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside the exact fixture root.' }
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

```


## FILE: source/tests/Test-ExternalStandardInputBoundary.ps1

SHA256: b4f3ddb532ed8d70ea694c63bdec8ded08bfc36747f5f79cbee54ba7bbc97a91 | Bytes: 7495 | Git mode: 100644

```
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
        $output='';$errorText='';$timer=[Diagnostics.Stopwatch]::St