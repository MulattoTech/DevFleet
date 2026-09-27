# DevFleet source part 089

Full-source UTF-8 byte interval [4092000, 4138500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: c01338f122a9319e5a75720afbf3ef2f4849e17aaf9b8601c10bc26627e6f866

<!-- BEGIN SOURCE SLICE -->
   Check ($LASTEXITCODE -eq 0) "shell syntax is valid for $([IO.Path]::GetFileName($scriptPath))"
    }
    function Invoke-InvalidIdentityEntrypoint {
        param([string]$ScriptPath,[string]$PackageVersion,[string]$NodeRole)
        $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$bash;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        foreach($argument in @('--noprofile','--norc',(ConvertTo-MsysPath $ScriptPath),'/nonexistent-devfleet-test-payload','--secrets-stdin','--transaction-id','invalid','--payload-sha256',('b'*64),'--bootstrap-max-seconds','30','--package-version',$PackageVersion,'--node-role',$NodeRole)){[void]$psi.ArgumentList.Add($argument)}
        $process=[Diagnostics.Process]::Start($psi);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$timer=[Diagnostics.Stopwatch]::StartNew()
        try{$finished=$process.WaitForExit(3000);$timer.Stop();if(-not$finished){try{$process.Kill($true)}catch{}};[pscustomobject]@{finished=$finished;exitCode=if($finished){$process.ExitCode}else{$null};elapsed=$timer.Elapsed.TotalSeconds}}
        finally{if(-not$process.HasExited){try{$process.Kill($true)}catch{}};$process.Dispose()}
    }
    $computeIdentity=Invoke-InvalidIdentityEntrypoint -ScriptPath $computePath -PackageVersion '1.2.13' -NodeRole 'primary'
    $vaultIdentity=Invoke-InvalidIdentityEntrypoint -ScriptPath $vaultPath -PackageVersion 'vault' -NodeRole 'vault'
    Check ($computeIdentity.finished -and $computeIdentity.exitCode -eq 64 -and $computeIdentity.elapsed -lt 2) 'compute entrypoint rejects invalid identity before waiting on withheld stdin'
    Check ($vaultIdentity.finished -and $vaultIdentity.exitCode -eq 64 -and $vaultIdentity.elapsed -lt 2) 'Vault entrypoint rejects invalid identity before waiting on withheld stdin'
    $valid=Invoke-InputProbe -InputText '{"kind":"dummy"}'
    Check ($valid.finished -and $valid.stdout -match 'RC=0;SIZE=16;COUNT=0') 'valid dummy JSON and EOF are captured once and caller cleanup removes the secret file'
    $empty=Invoke-InputProbe -InputText ''
    Check ($empty.finished -and $empty.stdout -match 'RC=65;SIZE=0;COUNT=0') 'empty stdin fails distinctly and removes its temporary secret file'
    $invalid=Invoke-InputProbe -InputText 'not-json'
    Check ($invalid.finished -and $invalid.stdout -match 'RC=65;SIZE=0;COUNT=0') 'invalid JSON fails distinctly and removes its temporary secret file'
    $truncated=Invoke-InputProbe -InputText '{"kind":'
    Check ($truncated.finished -and $truncated.stdout -match 'RC=65;SIZE=0;COUNT=0') 'truncated JSON fails distinctly and removes its temporary secret file'
    $withheld=Invoke-InputProbe -InputText '' -Withhold -InputSeconds 2 -OuterSeconds 6
    Check ($withheld.finished -and $withheld.stdout -match 'RC=124;SIZE=0;COUNT=0' -and $withheld.elapsed -lt 4.5) 'withheld stdin is terminated by the same finite input deadline and removes its temporary file'
} finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failed);observed=[ordered]@{valid=$valid.stdout;empty=$empty.stdout;invalid=$invalid.stdout;truncated=$truncated.stdout;withheld=$withheld.stdout}}|ConvertTo-Json -Depth 4
if($failed.Count){exit 1}

```


## FILE: source/tests/Test-BootstrapTerminalReporting.ps1

SHA256: 8c7a792717408ec8048e7941b0d54698402d8832bc91e9e2cfbcc644997a13c9 | Bytes: 5546 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$sourceRoot=Split-Path -Parent $PSScriptRoot
$bash='C:\Program Files\Git\bin\bash.exe'
if(-not(Test-Path -LiteralPath $bash -PathType Leaf)){throw 'Existing Git for Windows bash is required.'}
$passed=0;$failed=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{[void]$script:failed.Add($Name)}}
function UnixPath([string]$Path){$full=[IO.Path]::GetFullPath($Path).Replace('\','/');if($full -match '^([A-Za-z]):/(.*)$'){return '/'+$Matches[1].ToLowerInvariant()+'/'+$Matches[2]};return $full}
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-bootstrap-terminal-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $fixtureRoot|Out-Null
    foreach($entrypoint in @('bootstrap-compute.sh','bootstrap-vault.sh')){
        $component=if($entrypoint -eq 'bootstrap-compute.sh'){'rootlessRuntime'}else{'restServer'}
        $source=Get-Content -LiteralPath (Join-Path $sourceRoot "linux/$entrypoint") -Raw
        # Execute the production exit/error handlers; replace only their external
        # progress sink and temporary paths. No bootstrap provisioning is run.
        $handler=[regex]::Match($source,'(?ms)^(?:finish_bootstrap\(\).*?^\}|trap [^\r\n]+ EXIT)\r?\ntrap [^\r\n]+(?:\r?\ntrap [^\r\n]+)?').Value
        if(-not $handler){throw "No production terminal handler found in $entrypoint"}
        $cases=@(
            @{name='explicit rejection';body='exit 5';rc=5;markers='rootlessRuntime FAILED'},
            @{name='command failure';body='false';rc=1;markers='rootlessRuntime FAILED'},
            @{name='already timed out';body='write_progress "$CURRENT_COMPONENT" TIMED_OUT; COMPONENT_TERMINALIZED=1; exit 124';rc=124;markers='rootlessRuntime TIMED_OUT'},
            @{name='already failed';body='write_progress "$CURRENT_COMPONENT" FAILED; COMPONENT_TERMINALIZED=1; exit 4';rc=4;markers='rootlessRuntime FAILED'},
            @{name='success';body='CURRENT_COMPONENT=""; exit 0';rc=0;markers=''},
            @{name='failed progress sink';body='write_progress() { return 17; }; exit 5';rc=5;markers=''},
            @{name='cleanup failure after completion';body='CURRENT_COMPONENT=""; rm() { command rm "$@"; return 23; }; exit 0';rc=23;markers='bootstrap FAILED'},
            @{name='cleanup preserves primary failure';body='rm() { command rm "$@"; return 23; }; exit 5';rc=5;markers='rootlessRuntime FAILED'}
        )
        foreach($case in $cases){
            $caseRoot=Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $caseRoot|Out-Null
            $preamble=@'
set -Eeuo pipefail
cd "$1"
CURRENT_COMPONENT=__COMPONENT__
COMPONENT_TERMINALIZED=0
SECRETS_SOURCE="$PWD/secrets"
SECRETS_ENV_TMP="$PWD/secrets-env-temp"
DOCKER_KEY="$PWD/docker-key"
TAILSCALE_KEY="$PWD/tailscale-key"
NPM_TMP="$PWD/npm-temp"
touch "$SECRETS_SOURCE" "$DOCKER_KEY" "$TAILSCALE_KEY"
if [[ __COMPONENT__ == rootlessRuntime ]]; then printf 'fixture secret' > "$SECRETS_ENV_TMP"; fi
mkdir "$NPM_TMP"
write_progress() { printf '%s %s\n' "$1" "$2" >> "$PWD/markers"; }
'@
            $scriptPath=Join-Path $caseRoot 'probe.sh'
            [IO.File]::WriteAllText($scriptPath,($preamble.Replace('__COMPONENT__',$component)+"`n"+$handler+"`n"+$case.body+"`n").Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
            $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$bash;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
            foreach($arg in @('--noprofile','--norc',(UnixPath $scriptPath),(UnixPath $caseRoot))){[void]$psi.ArgumentList.Add($arg)}
            $process=[Diagnostics.Process]::Start($psi);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
            try{
                if(-not $process.WaitForExit(10000)){ $process.Kill($true);throw "Terminal handler timed out: $entrypoint/$($case.name)" }
                [void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait(3000))
                $markers=if(Test-Path -LiteralPath (Join-Path $caseRoot 'markers')){(Get-Content -LiteralPath (Join-Path $caseRoot 'markers') -Raw).Trim()}else{''}
                Check ($process.ExitCode -eq $case.rc -and $markers -ceq $case.markers.Replace('rootlessRuntime',$component)) "$entrypoint $($case.name) preserves original status and one terminal marker"
                $clean=-not(Test-Path -LiteralPath (Join-Path $caseRoot 'secrets'))
                if($entrypoint -eq 'bootstrap-compute.sh'){foreach($name in @('secrets-env-temp','docker-key','tailscale-key','npm-temp')){$clean=$clean -and -not(Test-Path -LiteralPath (Join-Path $caseRoot $name))}}
                Check $clean "$entrypoint $($case.name) cleans owned temporary inputs"
            }finally{if(-not $process.HasExited){$process.Kill($true)};$process.Dispose()}
        }
    }
    [ordered]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failed)}|ConvertTo-Json
    if($failed.Count){exit 1}
}finally{
    $resolved=[IO.Path]::GetFullPath($fixtureRoot);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'devfleet-bootstrap-terminal-*'){throw 'Fixture cleanup path rejected.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: source/tests/Test-ComputePendingRebootHandoff.ps1

SHA256: 3f20ae26add6a6e9ac4e733debd795750d1ce3d9ecf73a2b880746c37ea2d50d | Bytes: 7325 | Git mode: 100644

```
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$productionScript = Join-Path $sourceRoot 'windows\02-Provision-ComputeNode.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-compute-reboot-' + [guid]::NewGuid().ToString('N'))

try {
    $fixtureWindows = Join-Path $fixtureRoot 'windows'
    $fixturePackage = Join-Path $fixtureRoot 'package'
    $fixtureState = Join-Path $fixtureRoot 'state'
    New-Item -ItemType Directory -Path $fixtureWindows, (Join-Path $fixturePackage 'cloud-init'), (Join-Path $fixtureState 'tmp') -Force | Out-Null
    Copy-Item -LiteralPath $productionScript -Destination (Join-Path $fixtureWindows '02-Provision-ComputeNode.ps1')
    Set-Content -LiteralPath (Join-Path $fixturePackage 'VERSION') -Value '1.2.13' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $fixturePackage 'cloud-init\compute.yaml') -Value "node=__NODE_NAME__`nrole=__NODE_ROLE__`nname=__GIT_NAME_SHELL__`nemail=__GIT_EMAIL_SHELL__" -Encoding utf8

    $markerLog = Join-Path $fixtureRoot 'markers.txt'
    $module = @'
function Assert-PowerShell7 {}
function Assert-Administrator {}
function Get-DevFleetDeadlineContext { [pscustomobject]@{ StageDeadlineUtc = [datetime]::UtcNow.AddMinutes(20) } }
function Set-DevFleetDeadlineContext { param($TransactionDeadlineUtc,$StageName,$StageBudgetSeconds) }
function Get-DevFleetStageBudgetSeconds { param($Name) 1200 }
function Get-DevFleetOperationMaximumSeconds { param($Name) 1200 }
function Get-DevFleetConfig {
    [pscustomobject]@{
        Failover = [pscustomobject]@{ InstanceName='devfleet-failover'; UbuntuImage='24.04'; Cpus=2; Memory='4G'; Disk='20G'; FriendlyName='Failover' }
        Primary = [pscustomobject]@{ InstanceName='devfleet-primary' }
        Git = [pscustomobject]@{ UserName='Fixture User'; Email='fixture@example.invalid' }
    }
}
function Get-PackageRootFromState { $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE }
function Wait-ActiveDevFleetTransaction {
    param($ExpectedRole)
    [pscustomobject]@{ transactionId=('a'*32); payloadSha256=('b'*64); action='FreshInstall'; role='Laptop'; preparedUtc='2026-09-22T00:00:00Z' }
}
function Test-DevFleetTransactionBinding { $true }
function New-DevFleetBootstrapBoundary {
    [pscustomobject]@{
        multipassResolvedStageName='compute-multipass-resolved'
        isolationVerifiedStageName='compute-isolation-verified'
        instancePresentStageName='compute-instance-present'
        instanceAbsentStageName='compute-instance-absent'
        instanceLaunchedStageName='compute-instance-launched'
        instanceStartedStageName='compute-instance-started'
        instanceReadyStageName='compute-instance-ready'
        payloadTransferredStageName='compute-payload-transferred'
        payloadExtractedStageName='compute-payload-extracted'
        completionStageName='compute-complete'
        bootstrapMaxSeconds=1200
        extractionCommand='true'
        bootstrapCommand='true'
    }
}
function Get-MultipassExe { 'multipass.exe' }
function Write-StageMarker { param($Name,$Transaction) Add-Content -LiteralPath $env:DEVFLEET_COMPUTE_REBOOT_MARKERS -Value $Name }
function Assert-MultipassIsolation { param($InstanceNames) }
function Get-OrCreateSecrets { [pscustomobject]@{} }
function Get-OrCreateNodeIdentity { param($Role) [pscustomobject]@{} }
function Test-MultipassInstance { param($Name) $false }
function Get-DevFleetStateRoot { $env:DEVFLEET_COMPUTE_REBOOT_STATE }
function ConvertTo-YamlSingleQuotedScalar { param($Value) "'$Value'" }
function ConvertTo-ShellSingleQuotedScalar { param($Value) "'$Value'" }
function Invoke-MultipassLaunchWithReadinessRecovery { throw 'fixture launch failed after servicing transition' }
function Test-PendingReboot { $env:DEVFLEET_COMPUTE_REBOOT_PENDING -eq '1' }
Export-ModuleMember -Function *
'@
    Set-Content -LiteralPath (Join-Path $fixtureWindows 'DevFleet.Common.psm1') -Value $module -Encoding utf8

    $oldPackage = $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE
    $oldState = $env:DEVFLEET_COMPUTE_REBOOT_STATE
    $oldMarkers = $env:DEVFLEET_COMPUTE_REBOOT_MARKERS
    $oldPending = $env:DEVFLEET_COMPUTE_REBOOT_PENDING
    try {
        $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE = $fixturePackage
        $env:DEVFLEET_COMPUTE_REBOOT_STATE = $fixtureState
        $env:DEVFLEET_COMPUTE_REBOOT_MARKERS = $markerLog
        $env:DEVFLEET_COMPUTE_REBOOT_PENDING = '1'
        $pwsh = (Get-Process -Id $PID).Path
        $process = Start-Process -FilePath $pwsh -ArgumentList @(
            '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
            (Join-Path $fixtureWindows '02-Provision-ComputeNode.ps1'),
            '-NodeRole','Failover'
        ) -Wait -PassThru -NoNewWindow
    } finally {
        $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE = $oldPackage
        $env:DEVFLEET_COMPUTE_REBOOT_STATE = $oldState
        $env:DEVFLEET_COMPUTE_REBOOT_MARKERS = $oldMarkers
        $env:DEVFLEET_COMPUTE_REBOOT_PENDING = $oldPending
    }

    if ($process.ExitCode -ne 3010) {
        throw "Compute launch failure with a new servicing obligation did not hand off as reboot-required: exit=$($process.ExitCode)."
    }
    $markers = @(Get-Content -LiteralPath $markerLog)
    foreach ($required in @('compute-multipass-resolved','compute-isolation-verified','compute-instance-absent')) {
        if ($markers -notcontains $required) { throw "Production compute path did not reach expected pre-launch marker: $required" }
    }
    if ($markers -contains 'compute-instance-ready' -or $markers -contains 'compute-complete') {
        throw 'Reboot-required compute handoff fabricated readiness or completion.'
    }

    $oldPackage = $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE
    $oldState = $env:DEVFLEET_COMPUTE_REBOOT_STATE
    $oldMarkers = $env:DEVFLEET_COMPUTE_REBOOT_MARKERS
    $oldPending = $env:DEVFLEET_COMPUTE_REBOOT_PENDING
    try {
        $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE = $fixturePackage
        $env:DEVFLEET_COMPUTE_REBOOT_STATE = $fixtureState
        $env:DEVFLEET_COMPUTE_REBOOT_MARKERS = $markerLog
        $env:DEVFLEET_COMPUTE_REBOOT_PENDING = '0'
        $nonRebootProcess = Start-Process -FilePath $pwsh -ArgumentList @(
            '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
            (Join-Path $fixtureWindows '02-Provision-ComputeNode.ps1'),
            '-NodeRole','Failover'
        ) -Wait -PassThru -NoNewWindow
    } finally {
        $env:DEVFLEET_COMPUTE_REBOOT_PACKAGE = $oldPackage
        $env:DEVFLEET_COMPUTE_REBOOT_STATE = $oldState
        $env:DEVFLEET_COMPUTE_REBOOT_MARKERS = $oldMarkers
        $env:DEVFLEET_COMPUTE_REBOOT_PENDING = $oldPending
    }
    if ($nonRebootProcess.ExitCode -eq 3010 -or $nonRebootProcess.ExitCode -eq 0) {
        throw "A non-servicing Multipass failure was incorrectly converted to reboot success: exit=$($nonRebootProcess.ExitCode)."
    }

    [ordered]@{
        status = 'PASS'
        exitCode = $process.ExitCode
        rebootRequired = $true
        ordinaryFailureExitCode = $nonRebootProcess.ExitCode
        ordinaryFailurePreserved = $true
        fabricatedCompletion = $false
    } | ConvertTo-Json -Compress
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

```


## FILE: source/tests/Test-DependencyProbeBoundary.ps1

SHA256: 5bc9343b93da6d7b99475b22475bd1dd9cbd9047052b5dae71f59b7dc6054a8e | Bytes: 4911 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'windows\DevFleet.Common.psm1') -Force

$pwsh=(Get-Command pwsh.exe -ErrorAction Stop).Source
$subject=(Get-AuthenticodeSignature -LiteralPath $pwsh).SignerCertificate.Subject
$dependency=[pscustomobject]@{
    id='devfleet-dependency-probe-fixture'
    minimumSupportedVersion='1.0.0'
    maximumMajor=9
    executableProbes=@()
    knownVendorInstallLocations=@($pwsh)
    installerAuthenticityPolicy=[pscustomobject]@{
        allowedSignerSubjectsExact=@($subject)
        allowedSignerPatterns=@()
        installedExecutableTrust='signed-installer-locked-path'
    }
    versionProbe=[pscustomobject]@{
        arguments=@('-NoProfile','-NonInteractive','-Command',"Start-Sleep -Seconds 8; Write-Output 'fixture 1.2.3'")
        regex='fixture\s+(\d+\.\d+\.\d+)'
    }
}
$multipassDependency=[pscustomobject]@{id='multipass'}
if((Get-DevFleetDependencyProbeAttemptLimit -Dependency $multipassDependency) -ne 8){throw 'Multipass dependency probe did not receive the bounded five-attempt headroom.'}
if((Get-DevFleetDependencyProbeAttemptLimit -Dependency $dependency) -ne 3){throw 'Non-Multipass dependency probe limit changed unexpectedly.'}

# The production dependency resolver must inherit the existing stage owner.
# Before the correction its native call ignored this context and ran for the
# fixture's full eight seconds.
$transactionDeadline=[datetime]::UtcNow.AddSeconds(30)
Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'compute' -StageBudgetSeconds 2 | Out-Null
$timer=[Diagnostics.Stopwatch]::StartNew()
$status=Get-DependencyStatus -Dependency $dependency
$timer.Stop()
if($timer.Elapsed -ge [TimeSpan]::FromSeconds(5)){
    throw "Dependency version probe escaped its two-second stage deadline ($([math]::Round($timer.Elapsed.TotalSeconds,3)) seconds)."
}
if([string]$status.Status -cne 'Broken' -or [string]$status.Detail -notmatch 'bounded version probe failed'){
    throw 'A timed-out dependency version probe did not return the bounded Broken classification.'
}
Remove-Variable -Scope Global -Name DevFleetDeadlineContext -ErrorAction SilentlyContinue

# Exercise the retry controller with fake time while retaining the same
# immutable deadline. A later compatible result is accepted, while malformed
# or non-Broken terminal states are never retried into a fabricated success.
$state=[pscustomobject]@{Now=[datetime]'2026-09-06T12:00:00Z';Calls=0}
$clock={ $state.Now }.GetNewClosure()
$sleep={param([double]$Seconds)$state.Now=$state.Now.AddSeconds($Seconds)}.GetNewClosure()
$provider={
    param($Dependency,[datetime]$DeadlineUtc,[int]$ProbeTimeoutSeconds)
    $state.Calls++
    if($state.Calls -eq 1){return [pscustomobject]@{Status='Broken';Path=$pwsh;Version=$null;Detail='first bounded probe failed'}}
    return [pscustomobject]@{Status='Compatible';Path=$pwsh;Version=[version]'1.2.3';Detail='second probe passed'}
}.GetNewClosure()
$retried=Wait-DevFleetDependencyStatus -Dependency $dependency -DeadlineUtc $state.Now.AddSeconds(10) -MaximumAttempts 3 -StatusProvider $provider -ClockProvider $clock -SleepProvider $sleep
if([string]$retried.Status -cne 'Compatible' -or $state.Calls -ne 2){throw 'Dependency status retry did not accept the first compatible bounded result.'}

$state.Calls=0
$terminalProvider={param($Dependency,[datetime]$DeadlineUtc,[int]$ProbeTimeoutSeconds)$state.Calls++;[pscustomobject]@{Status='Unsupported-Major';Path=$pwsh;Version=[version]'10.0.0';Detail='unsupported'}}.GetNewClosure()
$terminal=Wait-DevFleetDependencyStatus -Dependency $dependency -DeadlineUtc $state.Now.AddSeconds(10) -MaximumAttempts 3 -StatusProvider $terminalProvider -ClockProvider $clock -SleepProvider $sleep
if([string]$terminal.Status -cne 'Unsupported-Major' -or $state.Calls -ne 1){throw 'A non-Broken dependency result was incorrectly retried.'}

$state.Calls=0
$state.Now=[datetime]'2026-09-06T12:00:00Z'
$exhaustedProvider={
    param($Dependency,[datetime]$DeadlineUtc,[int]$ProbeTimeoutSeconds)
    $state.Calls++
    $state.Now=$state.Now.AddSeconds($ProbeTimeoutSeconds)
    [pscustomobject]@{Status='Broken';Path=$pwsh;Version=$null;Detail='bounded probe failed'}
}.GetNewClosure()
$exhausted=Wait-DevFleetDependencyStatus -Dependency $dependency -DeadlineUtc $state.Now.AddSeconds(5) -MaximumAttempts 3 -StatusProvider $exhaustedProvider -ClockProvider $clock -SleepProvider $sleep
if([string]$exhausted.Status -cne 'Broken' -or $state.Now -gt [datetime]'2026-09-06T12:00:05Z'){
    throw 'Dependency retries granted fresh time beyond the immutable owner deadline.'
}

[ordered]@{ok=$true;tests=5;nativeProbeBoundedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3);multipassRetryHeadroomBounded=$true;retryAcceptedCompatible=$true;nonBrokenNotRetried=$true;sharedDeadlinePreserved=$true}|ConvertTo-Json -Compress

```


## FILE: source/tests/Test-DependencyTrustedRoot.ps1

SHA256: ee713cc06579ca475c5de829259f295c144484c88a39abf1504577828ceecd83 | Bytes: 1928 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$sourcePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\DevFleet.Common.psm1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($sourcePath,[ref]$tokens,[ref]$errors)
if($errors){throw "Common module parse failed: $($errors -join '; ')"}
$definition=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-TrustedSystemRootForExecutable'},$true))
if($definition.Count -ne 1){throw 'Expected one Get-TrustedSystemRootForExecutable definition.'}
Invoke-Expression $definition[0].Extent.Text

function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$names=@('ProgramFiles','ProgramFiles(x86)','WINDIR')
$saved=@{};foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try {
  [Environment]::SetEnvironmentVariable('ProgramFiles','C:\Program Files','Process')
  [Environment]::SetEnvironmentVariable('ProgramFiles(x86)','C:\Program Files (x86)','Process')
  [Environment]::SetEnvironmentVariable('WINDIR','C:\Windows','Process')
  $programFilesRoot=Get-TrustedSystemRootForExecutable 'C:\Program Files\Git\cmd\git.exe'
  Assert-That ($programFilesRoot -ceq 'C:\Program Files') 'A single matching trusted root was collapsed to its first character.'
  $windowsRoot=Get-TrustedSystemRootForExecutable 'C:\Windows\System32\msiexec.exe'
  Assert-That ($windowsRoot -ceq 'C:\Windows') 'The Windows trusted root was not preserved as a full path.'
  Assert-That ($null -eq (Get-TrustedSystemRootForExecutable 'C:\Untrusted\tool.exe')) 'A path outside the exact trusted roots was accepted.'
} finally {
  foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
}

[pscustomobject]@{status='PASS';tests=3;scalarRootPreserved=$true;ancestorWideningRejected=$true}|ConvertTo-Json -Compress

```


## FILE: source/tests/Test-DevFleetHostAgentCurrent.ps1

SHA256: ec2aada5cb00d6e5d1e52e1eb125157ef86ceb0679fdca7ef69df689aeb2a7ca | Bytes: 7807 | Git mode: 100644

```
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-current-hostagent-"+[guid]::NewGuid().ToString('N'))
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
    sharedDeadlineElapsedSeconds = [math]::Round($deadlineTimer.Elapsed.