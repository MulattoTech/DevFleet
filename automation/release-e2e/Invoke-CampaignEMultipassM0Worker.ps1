[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9+/=]+$')][string]$RequestBase64
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
try {
    $requestJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))
    $request=$requestJson|ConvertFrom-Json -ErrorAction Stop
    if([string]$request.runId-notmatch'^[A-Za-z0-9._-]+$'){throw 'Worker run identity is invalid.'}
    if([string]$request.modulePath-notlike'C:\Users\Public\DevFleet-E2E\*\M0\MultipassDiagnostic.psm1'){throw 'Worker module path is outside the exact run staging boundary.'}
    if([string]$request.runPrefix-notmatch'^DevFleet-E2E-E-[A-Za-z0-9._-]+$'){throw 'Worker run-owned prefix is invalid.'}
    Import-Module ([string]$request.modulePath) -Force -ErrorAction Stop
    $ownerDeadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.ownerDeadlineUnixMilliseconds).UtcDateTime
    $snapshot=Get-DevFleetMultipassM0Snapshot -RunId ([string]$request.runId) -ExpectedVmName ([string]$request.vmName) -ExpectedVmId ([guid]([string]$request.vmId)) -UbuntuImage ([string]$request.ubuntuImage) -CandidateInstanceNames @($request.candidateNames|ForEach-Object{[string]$_}) -RunOwnedPrefix ([string]$request.runPrefix) -OwnerDeadlineUtc $ownerDeadline
    Assert-DevFleetMultipassM0Snapshot -Snapshot $snapshot -ExpectedRunId ([string]$request.runId) -ExpectedVmName ([string]$request.vmName) -ExpectedVmId ([guid]([string]$request.vmId))|Out-Null
    [Console]::Out.Write(($snapshot|ConvertTo-Json -Depth 24 -Compress))
} catch {
    $message=[regex]::Replace([string]$_.Exception.Message,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    [Console]::Error.Write($message)
    exit 1
}
