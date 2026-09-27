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
