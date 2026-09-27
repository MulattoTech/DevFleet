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
    $decodedGuestScript = $guestArgument.Substring(1, $guestArgument.Length - 2).Replace("'\''", "'")
    $bash = 'C:\Program Files\Git\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) { throw 'Existing Git for Windows bash is required for the guest script syntax fixture.' }
    $guestSyntaxError = (& $bash --noprofile --norc -n -c $decodedGuestScript 2>&1 | Out-String).Trim()
    $guestSyntaxPass = $LASTEXITCODE -eq 0
}
$expectedTransfer = $secret + '?ephemeral=true&preauthorized=true' + "`n"
$pass = $result -and [bool]$result.authenticated -and [bool]$result.authenticationAttempted -and [int]$state.statusCalls -eq 2 -and @($state.transferInputs).Count -eq 1 -and (@($state.transferInputs)[0] -ceq $expectedTransfer) -and [bool]$state.consumeIgnoreExitCode -and $argumentText -notmatch [regex]::Escape($secret) -and $guestArgument -and $guestArgument -notmatch '[\r\n]' -and $guestArgument -match 'DEVFLEET_TAILSCALE_UP_EXIT=' -and $guestSyntaxPass
$errorClass = if (-not $pass -and $errorText -match 'Shell scalar contains a forbidden control or newline character') { 'SHELL_SCALAR_REJECTION' } elseif ($errorText) { 'OTHER_FIXTURE_ERROR' } else { '' }
[pscustomobject][ordered]@{
    status = if ($pass) { 'PASS' } else { 'FAIL' }
    authenticated = [bool]($result -and $result.authenticated)
    authenticationAttempted = [bool]($result -and $result.authenticationAttempted)
    statusCalls = [int]$state.statusCalls
    externalCalls = @($state.calls).Count
    transferCount = @($state.transferInputs).Count
    guestCommandCaptured = [bool]$state.consume
    outerExitMismatchHandled = [bool]$state.consumeIgnoreExitCode
    guestCommandHasControl = [bool]($guestArgument -match '[\r\n]')
    guestCommandSyntaxPass = $guestSyntaxPass
    secretInArguments = [bool]($argumentText -match [regex]::Escape($secret))
    errorClass = $errorClass
} | ConvertTo-Json -Depth 4
if (-not $pass) { exit 1 }
