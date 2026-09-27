[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
$windowsRoot = Join-Path $WorkspaceRoot 'source/windows'
Import-Module (Join-Path $windowsRoot 'DevFleet.Tailscale.psm1') -Force -DisableNameChecking
$module = Get-Module DevFleet.Tailscale
$checks = [Collections.Generic.List[object]]::new()

function Check([string]$Name, [bool]$Pass) {
    $checks.Add([pscustomobject]@{ name = $Name; pass = $Pass })
}

function Read-Events([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Invoke-FixtureCase([string]$Case) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-Tailscale-Observability-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $eventPath = Join-Path $root 'pairing-events.log'
    try {
        $record = & $module {
            param($FixtureCase, $FixtureEventPath)
            $script:PairingFixtureCase = $FixtureCase
            $script:PairingFixtureOpened = 0
            $script:PairingFixtureStatusCalls = 0

            function script:Get-DevFleetDeadlineContext { return $null }
            function script:Start-Sleep { param($Milliseconds) }
            function script:Open-DevFleetTailscaleAuthenticationPage {
                param($Uri)
                $script:PairingFixtureOpened++
                if ($script:PairingFixtureCase -eq 'launch-failure') { throw 'fixture browser launch failure' }
                [pscustomobject]@{ apiAccepted = $true; processId = 4242; processSessionId = 1 }
            }
            function script:Invoke-External {
                param($FilePath, $ArgumentList, [switch]$Capture, [switch]$IgnoreExitCode, $TimeoutSeconds, $DeadlineUtc)
                if (-not $Capture -or -not $IgnoreExitCode -or $TimeoutSeconds -le 0) { throw 'fixture lost bounded capture contract' }
                if ($ArgumentList -contains 'up') {
                    if ($script:PairingFixtureCase -eq 'no-uri') { return 'https://evil.example/a/fake' }
                    return 'To authenticate, visit: https://login.tailscale.com/a/fixture123'
                }
                if ($ArgumentList -notcontains '--json') { throw 'fixture lost status JSON contract' }
                $script:PairingFixtureStatusCalls++
                if ($script:PairingFixtureCase -eq 'poll-command-failure' -and $script:PairingFixtureOpened -gt 0) { throw 'fixture status command timeout' }
                $connected = $script:PairingFixtureCase -eq 'already-connected' -or
                    ($script:PairingFixtureCase -eq 'auth-after-launch' -and $script:PairingFixtureOpened -gt 0)
                return (@{
                        BackendState = if ($connected) { 'Running' } else { 'NeedsLogin' }
                        TailscaleIPs = if ($connected) { @('100.64.1.2') } else { @() }
                        Self = if ($connected) { @{ HostName = 'devfleet-fixture' } } else { $null }
                    } | ConvertTo-Json -Compress)
            }

            $deadline = if ($FixtureCase -eq 'deadline-before-command') { [datetime]::UtcNow.AddSeconds(-1) } else { [datetime]::UtcNow.AddSeconds(60) }
            $result = $null
            $failed = $false
            $errorText = ''
            try {
                $result = Invoke-DevFleetTailscaleBrowserPairing `
                    -FilePath 'tailscale-fixture.exe' `
                    -Hostname 'devfleet-fixture' `
                    -DeadlineUtc $deadline `
                    -EvidencePath $FixtureEventPath `
                    -RunId 'fixture-run-observability' `
                    -TransactionId ('a' * 32) `
                    -PayloadSha256 ('b' * 64) `
                    -StageName 'windows-tailscale' `
                    -TargetRole 'Host'
            } catch {
                $failed = $true
                $errorText = $_.Exception.Message
            }
            [pscustomobject]@{
                result = $result
                failed = $failed
                error = $errorText
                opened = $script:PairingFixtureOpened
                statusCalls = $script:PairingFixtureStatusCalls
            }
        } $Case $eventPath
        [pscustomobject]@{ case = $Case; record = $record; events = @(Read-Events $eventPath); raw = if (Test-Path -LiteralPath $eventPath) { Get-Content -Raw -LiteralPath $eventPath } else { '' } }
    } finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

foreach ($case in @('already-connected', 'auth-after-launch', 'launch-failure', 'no-uri', 'poll-command-failure', 'deadline-before-command')) {
    $value = Invoke-FixtureCase $case
    $events = @($value.events)
    Check "$case writes sanitized event evidence" ($events.Count -gt 0)
    Check "$case event evidence has no URL or fixture token" ($value.raw -notmatch 'https?://|login\.tailscale\.com|fixture123')
    Check "$case event evidence binds transaction and target" (@($events | Where-Object { $_.transactionId -eq ('a' * 32) -and $_.requestedHostname -eq 'devfleet-fixture' -and $_.stage -eq 'windows-tailscale' }).Count -gt 0)
    switch ($case) {
        'already-connected' {
            Check "$case records authenticated state" (@($events | Where-Object eventClass -eq 'PAIRING_AUTHENTICATED').Count -gt 0 -and -not $value.record.failed)
        }
        'auth-after-launch' {
            Check "$case records accepted browser launch and authentication" (@($events | Where-Object eventClass -eq 'BROWSER_LAUNCH_ACCEPTED').Count -gt 0 -and @($events | Where-Object eventClass -eq 'PAIRING_AUTHENTICATED').Count -gt 0 -and -not $value.record.failed)
        }
        'launch-failure' {
            Check "$case records browser launch failure" (@($events | Where-Object { $_.eventClass -eq 'BROWSER_LAUNCH_FAILED' -and $_.failureClass -eq 'BROWSER_LAUNCH_API_FAILED' }).Count -gt 0 -and $value.record.failed)
        }
        'no-uri' {
            Check "$case records missing official URI" (@($events | Where-Object { $_.eventClass -eq 'PAIRING_FAILED' -and $_.failureClass -eq 'NO_VALID_OFFICIAL_URI' }).Count -gt 0 -and $value.record.failed)
        }
        'poll-command-failure' {
            Check "$case records wait and poll command failure" (@($events | Where-Object eventClass -eq 'PAIRING_WAIT_ENTERED').Count -gt 0 -and @($events | Where-Object eventClass -eq 'COMMAND_FAILED').Count -gt 0 -and $value.record.failed)
        }
        'deadline-before-command' {
            Check "$case records owner deadline before command" (@($events | Where-Object eventClass -eq 'COMMAND_BLOCKED_DEADLINE').Count -gt 0 -and $value.record.failed)
        }
    }
}

$result = [ordered]@{
    status = if (@($checks | Where-Object { -not $_.pass }).Count) { 'FAIL' } else { 'PASS' }
    scope = 'LOCAL_PRODUCTION_TAILSCALE_PAIRING_BOUNDARY_WITH_SANITIZED_EVENT_FIXTURES'
    passed = @($checks | Where-Object pass).Count
    total = $checks.Count
    checks = @($checks)
}
$result | ConvertTo-Json -Depth 8
if ($result.status -ne 'PASS') { exit 1 }
Write-Host "PASS $($result.passed)/$($result.total) Tailscale pairing observability checks; no browser, network, VM or auth-store operations performed."
