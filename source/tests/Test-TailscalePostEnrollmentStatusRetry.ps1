[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

$sourceModule = Join-Path $WorkspaceRoot 'windows\DevFleet.Tailscale.psm1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-tailscale-post-status-test-' + [guid]::NewGuid().ToString('N'))
$passed = 0
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

function New-FixtureStatusJson {
    param([bool]$Authenticated)
    if ($Authenticated) {
        [ordered]@{
            BackendState = 'Running'
            Self = [ordered]@{ HostName = 'fixture-node'; Online = $true; Tags = @('tag:devfleet-e2e') }
            TailscaleIPs = @('100.64.1.2')
            Health = @()
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        [ordered]@{
            BackendState = 'NeedsLogin'
            Self = [ordered]@{ HostName = ''; Online = $false }
            TailscaleIPs = @()
            Health = @()
        } | ConvertTo-Json -Depth 5 -Compress
    }
}

function New-FixturePreferencesJson {
    [ordered]@{ AdvertiseTags = @('tag:devfleet-e2e') } | ConvertTo-Json -Depth 3 -Compress
}

function New-FixtureInvoker {
    param([Parameter(Mandatory)][hashtable]$State)
    $statusJson = ${function:New-FixtureStatusJson}.GetNewClosure()
    $preferencesJson = ${function:New-FixturePreferencesJson}.GetNewClosure()
    $invoker = {
        param([string[]]$Arguments)
        $verb = [string]$Arguments[0]
        [void]$State.commands.Add(($Arguments -join ' '))
        switch ($verb) {
            'status' {
                $State.statusCalls = [int]$State.statusCalls + 1
                if ([int]$State.authCalls -eq 0) {
                    return [pscustomobject]@{ exitCode = 0; output = & $statusJson -Authenticated:$false }
                }
                $State.postStatusCalls = [int]$State.postStatusCalls + 1
                if ([int]$State.postStatusCalls -le [int]$State.postStatusFailures) {
                    if ([int]$State.statusFailureDelaySeconds -gt 0) { Start-Sleep -Seconds ([int]$State.statusFailureDelaySeconds) }
                    return [pscustomobject]@{ exitCode = 7; output = '' }
                }
                return [pscustomobject]@{ exitCode = 0; output = & $statusJson -Authenticated:$true }
            }
            'debug' {
                return [pscustomobject]@{ exitCode = 0; output = & $preferencesJson }
            }
            'up' {
                $State.authCalls = [int]$State.authCalls + 1
                return [pscustomobject]@{ exitCode = 0; output = 'fixture enrollment accepted' }
            }
            default { return [pscustomobject]@{ exitCode = 0; output = '' } }
        }
    }.GetNewClosure()
    return $invoker
}

function Invoke-Fixture {
    param([Parameter(Mandatory)][int]$PostStatusFailures, [Parameter(Mandatory)][string]$EvidencePath, [int]$StatusFailureDelaySeconds = 0)
    $state = @{
        authCalls = 0
        statusCalls = 0
        postStatusCalls = 0
        postStatusFailures = $PostStatusFailures
        statusFailureDelaySeconds = $StatusFailureDelaySeconds
        commands = [System.Collections.Generic.List[string]]::new()
    }
    $profile = [pscustomobject]@{ mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true }
    $optionsProvider = {
        param([string]$RequestedHostname, [string]$InstanceName, [string]$TargetRole)
        [pscustomobject]@{
            mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true
            hostname = $RequestedHostname; targetRole = $TargetRole; instanceName = $InstanceName
            secret = 'fixture-oauth-client-secret'; credentialSource = 'fixture-only'
        }
    }
    $result = $null
    $errorText = ''
    $started = [datetime]::UtcNow
    try {
        $result = Invoke-DevFleetTailscaleOAuthPairing `
            -FilePath 'fixture-tailscale.exe' -InstanceName 'fixture-guest' -Hostname 'fixture-node' `
            -DeadlineUtc ([datetime]::UtcNow.AddSeconds(180)) -EvidencePath $EvidencePath `
            -RunId 'post-status-retry-fixture' -TransactionId '0123456789abcdef0123456789abcdef' `
            -PayloadSha256 ('a' * 64) -StageName 'TAILSCALE-AUTH' -TargetRole 'Fixture' `
            -CommandInvoker (New-FixtureInvoker -State $state) `
            -EnrollmentProfileProvider { $profile } -EnrollmentOptionsProvider $optionsProvider `
            -TailnetLockProvider { [pscustomobject]@{ status = 'DISABLED'; observed = $true; enabled = $false } } `
            -ServiceStateProvider { 'Running' }
    } catch { $errorText = [string]$_.Exception.Message }
    $events = if (Test-Path -LiteralPath $EvidencePath -PathType Leaf) {
        @(Get-Content -LiteralPath $EvidencePath | ForEach-Object { $_ | ConvertFrom-Json })
    } else { @() }
    [pscustomobject]@{
        result = $result
        error = $errorText
        state = $state
        events = $events
        elapsedSeconds = ([datetime]::UtcNow - $started).TotalSeconds
    }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Import-Module $sourceModule -Force

    $transientEvidence = Join-Path $scratch 'transient.jsonl'
    $transient = Invoke-Fixture -PostStatusFailures 1 -EvidencePath $transientEvidence
    $transientRetries = @($transient.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' })
    Check ($transient.result -and [bool]$transient.result.authenticated -and [int]$transient.state.authCalls -eq 1 -and [int]$transient.state.postStatusCalls -eq 2 -and [int]$transient.state.statusCalls -eq 3 -and $transientRetries.Count -eq 1 -and ($transient.commands -join ' ') -notmatch 'fixture-oauth-client-secret' -and @($transient.commands | Where-Object { $_ -match '(^|\s)status\s' -and $_ -notmatch '--peers=false' }).Count -eq 0) 'one transient post-enrollment status failure recovers with one bounded retry and one OAuth attempt using self-only status'

    $extendedEvidence = Join-Path $scratch 'extended.jsonl'
    $extended = Invoke-Fixture -PostStatusFailures 5 -EvidencePath $extendedEvidence
    $extendedRetries = @($extended.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' })
    Check ($extended.result -and [bool]$extended.result.authenticated -and [int]$extended.state.authCalls -eq 1 -and [int]$extended.state.postStatusCalls -eq 6 -and [int]$extended.state.statusCalls -eq 7 -and $extendedRetries.Count -eq 5 -and ($extended.commands -join ' ') -notmatch 'fixture-oauth-client-secret') 'extended post-enrollment control-plane convergence recovers within a finite retry window without repeating OAuth'

    $timeoutEvidence = Join-Path $scratch 'timeout-convergence.jsonl'
    $timeoutConvergence = Invoke-Fixture -PostStatusFailures 3 -StatusFailureDelaySeconds 10 -EvidencePath $timeoutEvidence
    $timeoutRetries = @($timeoutConvergence.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' })
    Check ($timeoutConvergence.result -and [bool]$timeoutConvergence.result.authenticated -and [int]$timeoutConvergence.state.authCalls -eq 1 -and [int]$timeoutConvergence.state.postStatusCalls -eq 4 -and [int]$timeoutConvergence.state.statusCalls -eq 5 -and $timeoutRetries.Count -eq 3 -and ($timeoutConvergence.commands -join ' ') -notmatch 'fixture-oauth-client-secret') 'three ten-second post-enrollment status timeouts still converge within the bounded wall-clock window without repeating OAuth'

    $persistentEvidence = Join-Path $scratch 'persistent.jsonl'
    $persistent = Invoke-Fixture -PostStatusFailures 99 -EvidencePath $persistentEvidence
    $persistentRetries = @($persistent.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' })
    Check (-not $persistent.result -and $persistent.error -match '^TAILSCALE_CONTROL_PLANE_OFFLINE' -and [int]$persistent.state.authCalls -eq 1 -and [int]$persistent.state.postStatusCalls -eq 8 -and [int]$persistent.state.statusCalls -eq 9 -and $persistentRetries.Count -eq 7 -and [double]$persistent.elapsedSeconds -lt 18) 'persistent post-enrollment status failure remains fail-closed within the expanded finite retry budget'
} catch {
    [void]$failures.Add('unexpected post-enrollment status retry fixture exception')
} finally {
    if (Test-Path -LiteralPath $scratch -PathType Container) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

$summary = [ordered]@{
    status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    passed = $passed
    failed = $failures.Count
    failures = @($failures)
    diagnostic = [ordered]@{
        transient = if ($transient) { [ordered]@{ result = [bool]$transient.result; error = [string]$transient.error; authCalls = [int]$transient.state.authCalls; statusCalls = [int]$transient.state.statusCalls; postStatusCalls = [int]$transient.state.postStatusCalls; retryEvents = @($transient.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' }).Count } } else { $null }
        extended = if ($extended) { [ordered]@{ result = [bool]$extended.result; error = [string]$extended.error; authCalls = [int]$extended.state.authCalls; statusCalls = [int]$extended.state.statusCalls; postStatusCalls = [int]$extended.state.postStatusCalls; retryEvents = @($extended.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' }).Count } } else { $null }
        persistent = if ($persistent) { [ordered]@{ result = [bool]$persistent.result; error = [string]$persistent.error; authCalls = [int]$persistent.state.authCalls; statusCalls = [int]$persistent.state.statusCalls; postStatusCalls = [int]$persistent.state.postStatusCalls; retryEvents = @($persistent.events | Where-Object { [string]$_.eventClass -ceq 'POST_ENROLLMENT_STATUS_RETRY' }).Count } } else { $null }
    }
}
$summary | ConvertTo-Json -Depth 8
if ($failures.Count -ne 0) { exit 1 }
