# DevFleet source part 048

Full-source UTF-8 byte interval [2185500, 2232000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 5d664d0d83638a278818527fac28a9e8120830870340d2641976f6842ff7a2d6

<!-- BEGIN SOURCE SLICE -->
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

```


## FILE: automation/release-e2e/tests/Test-TailscaleModuleVisibility.ps1

SHA256: 74d6de4ffae1b588cff231731ed5797d3aa50e715f2ff869d4d5d4d839e80ccb | Bytes: 4845 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$WindowsRoot = (Join-Path $PSScriptRoot '../../../source/windows'),
    [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$WindowsRoot = (Resolve-Path -LiteralPath $WindowsRoot).Path
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'The installed caller requires PowerShell 7.' }
$results = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Pass) {
    $results.Add([pscustomobject]@{name=$Name;pass=$Pass})
}

# This is the actual dependency import order used by both shipping pairing scripts.
Import-Module (Join-Path $WindowsRoot 'DevFleet.Common.psm1') -Force -DisableNameChecking
$adminBefore = Get-Command Assert-Administrator -ErrorAction Stop
$commonExports = @((Get-Module DevFleet.Common).ExportedFunctions.Keys)
Import-Module (Join-Path $WindowsRoot 'DevFleet.Tailscale.psm1') -Force -DisableNameChecking
$adminAfter = Get-Command Assert-Administrator -ErrorAction SilentlyContinue
$pairingModule = Get-Module DevFleet.Tailscale
$nestedAdmin = & $pairingModule { Get-Command Assert-Administrator -ErrorAction SilentlyContinue }
Check 'Common administrator guard is visible before dependency import' ($null -ne $adminBefore)
Check 'Dependency import preserves caller administrator guard' ($null -ne $adminAfter)
Check 'Dependency retains its own Common command visibility' ($null -ne $nestedAdmin)
$expectedExports=@('Invoke-DevFleetTailscaleBrowserPairing','Invoke-DevFleetTailscaleOAuthPairing','Get-DevFleetTailscaleReadiness','Get-DevFleetTailscaleEnrollmentProfile','Get-DevFleetTailscaleOAuthSecretPath','Set-DevFleetTailscaleOAuthClientSecret')
$actualExports=@($pairingModule.ExportedFunctions.Keys)
Check 'Tailscale exports only the reviewed public pairing/readiness/credential entrypoints' ($actualExports.Count -eq $expectedExports.Count -and @($expectedExports|Where-Object{$actualExports -notcontains $_}).Count -eq 0 -and @($actualExports|Where-Object{$expectedExports -notcontains $_}).Count -eq 0)
$missingExports = @($commonExports | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
Check 'All normal caller Common exports remain visible' ($missingExports.Count -eq 0)

# Invoke the actual shipping script. The real administrator check runs unchanged;
# a caller-scope mock stops execution at the first external service boundary.
# No service, Tailscale CLI, browser, credential store or VM operation may run.
function Get-Service { throw 'LOCAL_FIXTURE_SERVICE_BOUNDARY_AFTER_REAL_ADMIN_GUARD' }
$scriptError = ''
try { & (Join-Path $WindowsRoot '04a-Connect-WindowsTailscale.ps1') }
catch { $scriptError = $_.Exception.Message }
Check 'Production Windows pairing script reaches external boundary after real guard' ($scriptError -eq 'LOCAL_FIXTURE_SERVICE_BOUNDARY_AFTER_REAL_ADMIN_GUARD')
Check 'Nested pairing caller can still resolve its Common helpers' ([bool](Get-Command Get-MultipassExe -ErrorAction SilentlyContinue) -and [bool](Get-Command Get-DevFleetStageBudgetSeconds -ErrorAction SilentlyContinue))

# Repeated stage imports are part of the same durable installer process.
Import-Module (Join-Path $WindowsRoot 'DevFleet.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $WindowsRoot 'DevFleet.Tailscale.psm1') -Force -DisableNameChecking
Check 'Repeated production import order preserves caller guard' ([bool](Get-Command Assert-Administrator -ErrorAction SilentlyContinue))
$privateHelpers = & (Get-Module DevFleet.Tailscale) {
    [bool](Get-Command Get-DevFleetDeadlineContext -ErrorAction SilentlyContinue) -and
    [bool](Get-Command Invoke-External -ErrorAction SilentlyContinue)
}
Check 'Repeated dependency load preserves internal deadline and process helpers' ([bool]$privateHelpers)

$report = [ordered]@{
    status = if (@($results | Where-Object { -not $_.pass }).Count) {'FAIL'} else {'PASS'}
    runtime = $PSVersionTable.PSVersion.ToString()
    scope = 'LOCAL_PRODUCTION_IMPORT_AND_SCRIPT_EXTERNAL_BOUNDARY_NO_RUNTIME_PROOF'
    actualScriptError = $scriptError
    callerCommonExportCount = $commonExports.Count
    missingCallerExports = $missingExports
    inputHashes = @(foreach ($name in @('DevFleet.Common.psm1','DevFleet.Tailscale.psm1','04a-Connect-WindowsTailscale.ps1')) {
        [ordered]@{name=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $WindowsRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    results = @($results)
    passed = @($results | Where-Object pass).Count
    total = $results.Count
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding utf8
[pscustomobject]@{status=$report.status;passed=$report.passed;total=$report.total;actualScriptError=$scriptError;missingCallerExportCount=$missingExports.Count} | ConvertTo-Json -Compress
if ($report.status -ne 'PASS') { exit 1 }

```


## FILE: automation/release-e2e/tests/Test-TailscaleOAuthAutomation.ps1

SHA256: 75c28c6c435b49db4f2d0703fac36f50d71af8766a7822d7a502db5d02dc3a29 | Bytes: 32684 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }

$sourceModule = Join-Path $WorkspaceRoot 'source\windows\DevFleet.Tailscale.psm1'
$e2eModule = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\TailscaleE2E.psm1'
$passed = 0
$failures = [System.Collections.Generic.List[string]]::new()
$caseCount = 0
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-tailscale-oauth-test-' + [guid]::NewGuid().ToString('N'))

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

function New-FixtureStatusJson {
    param(
        [string]$BackendState = 'Running',
        [string]$HostName = 'fixture-node',
        [bool]$Online = $true,
        [string[]]$Ips = @('100.64.1.2'),
        [string[]]$Health = @()
    )
    [ordered]@{
        BackendState = $BackendState
        Self = [ordered]@{ HostName = $HostName; Online = $Online }
        TailscaleIPs = @($Ips)
        Health = @($Health)
    } | ConvertTo-Json -Depth 5 -Compress
}

function New-FixturePreferencesJson {
    param([string[]]$Tags = @('tag:devfleet-e2e'))
    [ordered]@{ AdvertiseTags = @($Tags) } | ConvertTo-Json -Depth 3 -Compress
}

function New-FixtureCommandInvoker {
    param([Parameter(Mandatory)][hashtable]$State)
    $statusJsonBuilder = ${function:New-FixtureStatusJson}.GetNewClosure()
    $preferencesJsonBuilder = ${function:New-FixturePreferencesJson}.GetNewClosure()
    $invoker = {
        param([string[]]$Arguments)
        $command = [string]$Arguments[0]
        [void]$State.commandArguments.Add(($Arguments -join ' '))
        switch ($command) {
            'status' {
                $State.statusCalls = [int]$State.statusCalls + 1
                $afterAuth = [int]$State.authCalls -gt 0
                $backend = if ($afterAuth) { [string]$State.finalBackend } else { [string]$State.initialBackend }
                $hostName = if ($afterAuth) { [string]$State.finalHostName } else { [string]$State.initialHostName }
                $online = if ($afterAuth) { [bool]$State.finalOnline } else { [bool]$State.initialOnline }
                $ips = if ($afterAuth) { @($State.finalIps) } else { @($State.initialIps) }
                $health = if ($afterAuth) { @($State.finalHealth) } else { @($State.initialHealth) }
                return [pscustomobject]@{ exitCode = [int]$State.statusExitCode; output = & $statusJsonBuilder -BackendState $backend -HostName $hostName -Online:$online -Ips $ips -Health $health }
            }
            'debug' {
                $afterAuth = [int]$State.authCalls -gt 0
                $tags = if ($afterAuth) { @($State.finalTags) } else { @($State.initialTags) }
                return [pscustomobject]@{ exitCode = [int]$State.preferencesExitCode; output = & $preferencesJsonBuilder -Tags $tags }
            }
            'up' {
                $State.authCalls = [int]$State.authCalls + 1
                if ($State.pendingRebootOnAuth) { $State.pendingReboot = $true }
                return [pscustomobject]@{ exitCode = [int]$State.upExitCode; output = [string]$State.upOutput }
            }
            'ping' {
                $State.peerCalls = [int]$State.peerCalls + 1
                if ([int]$State.peerFailuresBeforeSuccess -ge 0 -and [int]$State.peerCalls -gt [int]$State.peerFailuresBeforeSuccess) {
                    return [pscustomobject]@{ exitCode = 0; output = 'pong' }
                }
                return [pscustomobject]@{ exitCode = [int]$State.peerExitCode; output = [string]$State.peerOutput }
            }
            default {
                return [pscustomobject]@{ exitCode = 0; output = '' }
            }
        }
    }.GetNewClosure()
    $invoker
}

function Invoke-ProductionFixture {
    param(
        [string]$InitialBackend = 'Running',
        [string]$FinalBackend = 'Running',
        [string]$InitialHostName = 'fixture-node',
        [string]$FinalHostName = 'fixture-node',
        [bool]$InitialOnline = $true,
        [bool]$FinalOnline = $true,
        [string[]]$InitialIps = @('100.64.1.2'),
        [string[]]$FinalIps = @('100.64.1.2'),
        [string[]]$InitialHealth = @(),
        [string[]]$FinalHealth = @(),
        [string[]]$InitialTags = @('tag:devfleet-e2e'),
        [string[]]$FinalTags = @('tag:devfleet-e2e'),
        [string]$EnrollmentGuestHostname = '',
        [string]$ExpectedPeer = '',
        [int]$ServicePort = 0,
        [string]$OptionsError = '',
        [string]$EvidencePath = '',
        [string]$LockStatus = 'DISABLED',
        [int]$UpExitCode = 0,
        [string]$UpOutput = '',
        [int]$PeerExitCode = 0,
        [string]$PeerOutput = '',
        [int]$PeerFailuresBeforeSuccess = -1,
        [int]$EndpointExitCode = 0,
        [int]$StatusExitCode = 0,
        [int]$PreferencesExitCode = 0,
        [bool]$Stopped = $false,
        [switch]$PendingRebootOnAuth
    )
    $state = @{
        initialBackend = $InitialBackend; finalBackend = $FinalBackend
        initialHostName = $InitialHostName; finalHostName = $FinalHostName
        initialOnline = $InitialOnline; finalOnline = $FinalOnline
        initialIps = @($InitialIps); finalIps = @($FinalIps)
        initialHealth = @($InitialHealth); finalHealth = @($FinalHealth)
        initialTags = @($InitialTags); finalTags = @($FinalTags)
        optionsError = $OptionsError; lockStatus = $LockStatus; stopped = $Stopped
        upExitCode = $UpExitCode; upOutput = $UpOutput
        peerExitCode = $PeerExitCode; peerOutput = $PeerOutput; peerFailuresBeforeSuccess = $PeerFailuresBeforeSuccess
        endpointExitCode = $EndpointExitCode; statusExitCode = $StatusExitCode; preferencesExitCode = $PreferencesExitCode
        pendingRebootOnAuth = [bool]$PendingRebootOnAuth; pendingReboot = $false; pendingRebootChecks = 0
        statusCalls = 0; authCalls = 0; startCalls = 0; endpointCalls = 0; peerCalls = 0
        commandArguments = [System.Collections.Generic.List[string]]::new()
    }
    $guestHostnames = @{}
    if ($EnrollmentGuestHostname) { $guestHostnames['fixture-guest'] = $EnrollmentGuestHostname }
    $profile = [pscustomobject]@{ mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true; guestHostnames = $guestHostnames }
    $optionsProvider = {
        param([string]$RequestedHostname, [string]$InstanceName, [string]$TargetRole)
        if ([string]$State.optionsError) { throw [string]$State.optionsError }
        [pscustomobject]@{
            mode = 'e2e'; tag = 'tag:devfleet-e2e'; ephemeral = $true; preauthorized = $true
            hostname = $RequestedHostname; targetRole = $TargetRole; instanceName = $InstanceName
            secret = 'fixture-oauth-client-secret'; credentialSource = 'fixture-only'
        }
    }.GetNewClosure()
    $lockProvider = {
        [pscustomobject]@{ status = [string]$State.lockStatus; observed = $true; enabled = ([string]$State.lockStatus -ceq 'ENABLED') }
    }.GetNewClosure()
    $serviceProvider = {
        if ([bool]$State.stopped) { 'Stopped' } else { 'Running' }
    }.GetNewClosure()
    $startProvider = {
        $State.startCalls = [int]$State.startCalls + 1
    }.GetNewClosure()
    $pendingRebootProvider = {
        $State.pendingRebootChecks = [int]$State.pendingRebootChecks + 1
        [bool]$State.pendingReboot
    }.GetNewClosure()
    $endpointInvoker = {
        param([string]$Target, [int]$Port, [string]$Path)
        $State.endpointCalls = [int]$State.endpointCalls + 1
        [pscustomobject]@{ exitCode = [int]$State.endpointExitCode; output = '' }
    }.GetNewClosure()
    $result = $null
    $errorText = ''
    try {
        $pairingParameters = @{
            FilePath = 'fixture-tailscale.exe'; InstanceName = 'fixture-guest'; Hostname = 'fixture-node'
            DeadlineUtc = [datetime]::UtcNow.AddSeconds(30); EvidencePath = $EvidencePath; RunId = 'oauth-automation-fixture'
            StageName = 'TAILSCALE-AUTH'; TargetRole = 'Fixture'; ExpectedPeer = $ExpectedPeer
            ServicePort = $ServicePort; ServicePath = '/healthz'
            CommandInvoker = (New-FixtureCommandInvoker -State $state)
            EndpointInvoker = $endpointInvoker; EnrollmentProfileProvider = { $profile }
            EnrollmentOptionsProvider = $optionsProvider; TailnetLockProvider = $lockProvider
            ServiceStateProvider = $serviceProvider; ServiceStartProvider = $startProvider
        }
        if ($PendingRebootOnAuth) { $pairingParameters.PendingRebootProvider = $pendingRebootProvider }
        $result = Invoke-DevFleetTailscaleOAuthPairing @pairingParameters
    } catch { $errorText = [string]$_.Exception.Message }
    [pscustomobject]@{ result = $result; error = $errorText; state = $state }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Import-Module $sourceModule -Force
    Import-Module $e2eModule -Force

    # 1. Healthy authenticated state is a read-only PASS.
    $caseCount++
    $healthy = Invoke-ProductionFixture
    $healthyStatusCommands = @($healthy.state.commandArguments | Where-Object { $_ -match '(^|\s)status\s' })
    Check ($healthy.result -and [bool]$healthy.result.authenticated -and -not [bool]$healthy.result.authenticationAttempted -and [int]$healthy.state.authCalls -eq 0 -and [string]$healthy.result.readiness.statusClass -eq 'READY') 'healthy state skips OAuth mutation and passes readiness'
    $caseCount++
    Check ($healthyStatusCommands.Count -gt 0 -and @($healthyStatusCommands | Where-Object { $_ -notmatch '--peers=false' }).Count -eq 0) 'status readiness excludes peer enumeration while retaining self state'

    # An E2E guest's Tailscale self hostname is generated from the run identity,
    # not copied from the Multipass instance name. Pre-auth readiness must use
    # that profile-resolved identity or it will reject an already-authenticated
    # guest as TAILSCALE_WRONG_TAG before OAuth.
    $guestProfileIdentity = Invoke-ProductionFixture -InitialHostName 'fixture-guest-e2e' -EnrollmentGuestHostname 'fixture-guest-e2e'
    $caseCount++
    Check ($guestProfileIdentity.result -and [bool]$guestProfileIdentity.result.authenticated -and -not [bool]$guestProfileIdentity.result.authenticationAttempted -and [int]$guestProfileIdentity.state.authCalls -eq 0) 'E2E guest readiness uses the profile-resolved hostname before OAuth'

    # 2. A stopped service gets one bounded recovery and is rechecked.
    $caseCount++
    $stopped = Invoke-ProductionFixture -Stopped:$true
    Check ($stopped.result -and [int]$stopped.state.startCalls -eq 1 -and [int]$stopped.result.serviceRecoveryCount -eq 1 -and [int]$stopped.state.authCalls -eq 0) 'stopped service has one recovery and one readiness recheck'

    # 3. NeedsLogin invokes the OAuth enrollment exactly once.
    $caseCount++
    $needsLogin = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -FinalBackend 'Running'
    Check ($needsLogin.result -and [bool]$needsLogin.result.authenticated -and [bool]$needsLogin.result.authenticationAttempted -and [int]$needsLogin.state.authCalls -eq 1 -and [int]$needsLogin.state.statusCalls -eq 2) 'NeedsLogin performs one OAuth enrollment and verifies the resulting state'

    # 3a. A servicing transition during OAuth must leave the auth boundary and
    # propagate a typed reboot requirement to the installer lifecycle.
    $servicingEvidencePath = Join-Path $scratch 'servicing-transition-events.jsonl'
    $servicingTransition = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -FinalBackend 'Running' -EvidencePath $servicingEvidencePath -PendingRebootOnAuth
    $caseCount++
    Check (-not $servicingTransition.result -and $servicingTransition.error -match '^DEVFLEET_REBOOT_REQUIRED:' -and [int]$servicingTransition.state.authCalls -eq 1 -and [int]$servicingTransition.state.statusCalls -eq 1 -and [int]$servicingTransition.state.pendingRebootChecks -gt 0) 'servicing transition during OAuth propagates a typed reboot requirement before readiness'
    $servicingEvents = if (Test-Path -LiteralPath $servicingEvidencePath -PathType Leaf) { @(Get-Content -LiteralPath $servicingEvidencePath | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
    $servicingEvent = $servicingEvents | Where-Object { [string]$_.eventClass -ceq 'REBOOT_REQUIRED_DURING_TAILSCALE' } | Select-Object -First 1
    $caseCount++
    Check ($servicingEvent -and [bool]$servicingEvent.rebootRequired -and [string]$servicingEvent.boundary -ceq 'oauth-enrollment' -and ($servicingEvents | ConvertTo-Json -Compress) -notmatch 'fixture-oauth-client-secret') 'servicing transition emits a bounded redacted structured event'

    $windowsTailscaleSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'source\windows\04a-Connect-WindowsTailscale.ps1') -Raw
    $installSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'source\Install-DevFleet.ps1') -Raw
    $caseCount++
    Check ($windowsTailscaleSource -match 'DEVFLEET_REBOOT_REQUIRED' -and $windowsTailscaleSource -match 'exit 3010' -and $installSource -match 'windows\\04a-Connect-WindowsTailscale\.ps1' -and $installSource -match 'LASTEXITCODE' -and $installSource -match 'Write-StageMarker ''windows-tailscale''') 'Windows Tailscale reboot result is propagated before its stage marker is published'

    $guestTailscaleSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'source\windows\04-Connect-Tailscale.ps1') -Raw
    $tailscaleSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'source\windows\DevFleet.Tailscale.psm1') -Raw
    $caseCount++
    Check ($guestTailscaleSource -match 'DEVFLEET_REBOOT_REQUIRED' -and $guestTailscaleSource -match 'exit 3010' -and $guestTailscaleSource -match '(?s)-PendingRebootProvider\s+\{\s*Test-PendingReboot\s*\}') 'Guest Tailscale reboot result is propagated before Vault completion'
    $caseCount++
    Check ($tailscaleSource -match 'OAUTH_ENROLLMENT_STARTED' -and $tailscaleSource -match "oauth-enrollment-before" -and $tailscaleSource -match 'DEVFLEET_TAILSCALE_UP_EXIT' -and $tailscaleSource -match 'timeout\s+--signal=TERM\s+--kill-after=10s') 'Guest OAuth enrollment has a bounded servicing-aware result handoff'
    $caseCount++
    Check ($tailscaleSource -match "status','--json','--peers=false") 'Guest Tailscale readiness uses self-only structured status before peer ping'

    # 3b. Guest service probes must target systemctl directly; only Tailscale
    # subcommands receive the sudo tailscale wrapper used by multipass exec.
    $tailscaleModule = Get-Module DevFleet.Tailscale | Select-Object -First 1
    $guestServiceArgs = & $tailscaleModule {
        ConvertTo-DevFleetTailscaleNativeArguments -InstanceName 'fixture-guest' -CommandKind 'System' -Arguments @('systemctl','is-active','tailscaled')
    }
    $guestTailscaleArgs = & $tailscaleModule {
        ConvertTo-DevFleetTailscaleNativeArguments -InstanceName 'fixture-guest' -CommandKind 'Tailscale' -Arguments @('status','--json','--peers=false')
    }
    $caseCount++
    Check (($guestServiceArgs -join ' ') -ceq 'exec fixture-guest -- sudo systemctl is-active tailscaled' -and ($guestTailscaleArgs -join ' ') -ceq 'exec fixture-guest -- sudo tailscale status --json --peers=false') 'guest service commands bypass the Tailscale subcommand wrapper and bound status excludes peer enumeration'

    # 4. Missing credential is deterministic and never opens a browser.
    $caseCount++
    $missing = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -OptionsError 'fixture credential is absent'
    Check (-not $missing.result -and $missing.error -ceq 'fixture credential is absent' -and [int]$missing.state.authCalls -eq 0 -and (@($missing.state.commandArguments | Where-Object { $_ -match '(?i)browser|login.tailscale' }).Count -eq 0)) 'missing OAuth credential fails closed without browser fallback'

    # 5. Invalid credential has its own failure class and no enrollment attempt.
    $caseCount++
    $invalid = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -OptionsError 'TAILSCALE_CREDENTIAL_INVALID: fixture credential cannot be decrypted'
    Check (-not $invalid.result -and $invalid.error -match '^TAILSCALE_CREDENTIAL_INVALID' -and [int]$invalid.state.authCalls -eq 0) 'invalid OAuth credential fails deterministically without authentication'

    # 6. An authenticated node with an unavailable peer is not an auth failure.
    $peerFailure = Invoke-ProductionFixture -ExpectedPeer 'fixture-peer' -PeerExitCode 1 -PeerOutput 'peer unreachable'
    $caseCount++
    Check (-not $peerFailure.result -and $peerFailure.error -match '^TAILSCALE_PEER_UNREACHABLE' -and [int]$peerFailure.state.authCalls -eq 0) 'unavailable expected peer is classified separately from authentication'

    # Peer convergence uses the shipping readiness gate, not a fixture-side retry.
    $peerConverged = Invoke-ProductionFixture -ExpectedPeer 'fixture-peer' -PeerExitCode 1 -PeerOutput 'peer unreachable' -PeerFailuresBeforeSuccess 1 -ServicePort 7443
    $caseCount++
    Check ($peerConverged.result -and $peerConverged.result.readiness.ready -and $peerConverged.result.readiness.peerLayer -eq 'PASS' -and $peerConverged.result.readiness.endpointLayer -eq 'PASS' -and $peerConverged.state.peerCalls -eq 2 -and $peerConverged.state.authCalls -eq 0 -and $peerConverged.state.endpointCalls -eq 1) 'transient peer failure converges without reenrollment and still checks the endpoint'
    $peerAfterAuth = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -ExpectedPeer 'fixture-peer' -PeerExitCode 1 -PeerOutput 'peer unreachable' -PeerFailuresBeforeSuccess 1
    $caseCount++
    Check ($peerAfterAuth.result -and $peerAfterAuth.result.readiness.ready -and $peerAfterAuth.state.peerCalls -eq 2 -and $peerAfterAuth.state.authCalls -eq 1) 'post-OAuth peer convergence preserves exactly one enrollment'
    $caseCount++
    Check (-not $peerFailure.result -and $peerFailure.error -match '^TAILSCALE_PEER_UNREACHABLE' -and $peerFailure.state.peerCalls -eq 3 -and $peerFailure.state.endpointCalls -eq 0) 'persistent peer failure stops after the finite retry allowance without endpoint credit'
    $peerDenied = Invoke-ProductionFixture -ExpectedPeer 'fixture-peer' -PeerExitCode 1 -PeerOutput 'access denied by ACL' -PeerFailuresBeforeSuccess 1 -ServicePort 7443
    $caseCount++
    Check (-not $peerDenied.result -and $peerDenied.error -match '^TAILSCALE_ACL_BLOCKED' -and $peerDenied.state.peerCalls -eq 1 -and $peerDenied.state.endpointCalls -eq 0) 'explicit peer denial remains an immediate failure even if a later ping would pass'
    $peerTimeout = Invoke-ProductionFixture -ExpectedPeer 'fixture-peer' -PeerExitCode 124 -PeerOutput 'native command timed out' -PeerFailuresBeforeSuccess 1
    $caseCount++
    Check (-not $peerTimeout.result -and $peerTimeout.error -match '^TAILSCALE_PEER_UNREACHABLE' -and $peerTimeout.state.peerCalls -eq 1) 'native peer timeout is terminal and is not retried'
    $peerEndpointFailure = Invoke-ProductionFixture -ExpectedPeer 'fixture-peer' -PeerExitCode 1 -PeerOutput 'peer unreachable' -PeerFailuresBeforeSuccess 1 -ServicePort 7443 -EndpointExitCode 1
    $caseCount++
    Check (-not $peerEndpointFailure.result -and $peerEndpointFailure.error -match '^DEVFLEET_SERVICE_UNREACHABLE_OVER_TAILSCALE' -and $peerEndpointFailure.state.peerCalls -eq 2 -and $peerEndpointFailure.state.endpointCalls -eq 1) 'peer recovery cannot bypass a failed endpoint'

    # Exercise the real helper's native timeout boundary: CommandInvoker above
    # intentionally models CLI output and does not receive MaximumSeconds.
    $peerBudgetState = @{ calls = 0; maximum = 0; arguments = @() }
    $peerBudgetInvoker = {
        param([string[]]$Arguments, [int]$MaximumSeconds)
        $peerBudgetState.calls++; $peerBudgetState.maximum = $MaximumSeconds; $peerBudgetState.arguments = @($Arguments)
        [pscustomobject]@{ exitCode = 0; output = 'pong' }
    }.GetNewClosure()
    $invokePeerBudget = {
        param([scriptblock]$Invoker, [datetime]$Deadline)
        $readiness = Get-DevFleetTailscaleReadiness -StatusJson '{"BackendState":"Running","Self":{"HostName":"fixture-node","Online":true},"TailscaleIPs":["100.64.1.2"],"Health":[]}' -ExpectedHostname 'fixture-node'
        Invoke-DevFleetTailscalePeerAndEndpointReadiness -Readiness $readiness -ExpectedPeer 'fixture-peer' -TailscaleInvoker $Invoker -DeadlineUtc $Deadline
    }
    $shortPeer = & $tailscaleModule $invokePeerBudget $peerBudgetInvoker ([datetime]::UtcNow.AddSeconds(7.5))
    $caseCount++
    Check ($shortPeer.ready -and $peerBudgetState.calls -eq 1 -and $peerBudgetState.maximum -ge 1 -and $peerBudgetState.maximum -le 2 -and @($peerBudgetState.arguments | Where-Object { $_ -match '^--timeout=[12]s$' }).Count -eq 1) 'peer native and TSMP timeouts clip to the existing owner reserve'
    $peerBudgetState.calls = 0
    $expiredPeer = & $tailscaleModule $invokePeerBudget $peerBudgetInvoker ([datetime]::UtcNow.AddSeconds(4))
    $caseCount++
    Check (-not $expiredPeer.ready -and $expiredPeer.failureClass -eq 'TAILSCALE_PEER_UNREACHABLE' -and $peerBudgetState.calls -eq 0) 'peer check cannot launch after the owner reserve is exhausted'
    $latePeerInvoker = {
        param([string[]]$Arguments, [int]$MaximumSeconds)
        Start-Sleep -Milliseconds 1400
        [pscustomobject]@{ exitCode = 0; output = 'late pong' }
    }
    $latePeer = & $tailscaleModule $invokePeerBudget $latePeerInvoker ([datetime]::UtcNow.AddSeconds(6.2))
    $caseCount++
    Check (-not $latePeer.ready -and $latePeer.failureClass -eq 'TAILSCALE_PEER_UNREACHABLE') 'peer success returned beyond its immutable deadline is rejected'
    $peerBudgetState.calls = 0
    $immediatePeer = & $tailscaleModule $invokePeerBudget $peerBudgetInvoker ([datetime]::UtcNow.AddSeconds(60))
    $caseCount++
    Check ($immediatePeer.ready -and $peerBudgetState.calls -eq 1 -and $peerBudgetState.maximum -le 10 -and $peerBudgetState.arguments -contains '--timeout=5s') 'healthy peer uses one bounded TSMP call inside the original ten-second window'
    $slowPeerState = @{ calls = 0; maximums = [Collections.Generic.List[int]]::new() }
    $slowPeerInvoker = {
        param([string[]]$Arguments, [int]$MaximumSeconds)
        $slowPeerState.calls++; $slowPeerState.maximums.Add($MaximumSeconds)
        if ($slowPeerState.calls -ge 3) { return [pscustomobject]@{ exitCode = 0; output = 'pong' } }
        Start-Sleep -Milliseconds ([math]::Min(4000,($MaximumSeconds*1000)))
        [pscustomobject]@{ exitCode = 1; output = 'peer unreachable' }
    }.GetNewClosure()
    $peerWatch = [Diagnostics.Stopwatch]::StartNew()
    $slowPeer = & $tailscaleModule $invokePeerBudget $slowPeerInvoker ([datetime]::UtcNow.AddSeconds(60))
    $peerWatch.Stop()
    $caseCount++
    Check (-not $slowPeer.ready -and $slowPeer.failureClass -eq 'TAILSCALE_PEER_UNREACHABLE' -and $slowPeerState.calls -eq 2 -and $slowPeerState.maximums[1] -lt $slowPeerState.maximums[0] -and $peerWatch.Elapsed.TotalSeconds -lt 10.5) 'peer retries share one ten-second window and cannot accept a later third pong'

    # 7. A reachable peer with a failed DevFleet endpoint is a service-layer failure.
    $serviceFailure = Invoke-ProductionFixture -ExpectedPeer 'fixture-peer' -ServicePort 7443 -EndpointExitCode 1
    $caseCount++
    Check (-not $serviceFailure.result -and $serviceFailure.error -match '^DEVFLEET_SERVICE_UNREACHABLE_OVER_TAILSCALE' -and [int]$serviceFailure.state.endpointCalls -eq 1) 'reachable peer with unavailable service endpoint is classified at layer four'

    # 8. A wrong tag fails the identity gate before any auth mutation.
    $wrongTag = Invoke-ProductionFixture -InitialTags @('tag:foreign')
    $caseCount++
    Check (-not $wrongTag.result -and $wrongTag.error -match '^TAILSCALE_WRONG_TAG' -and [int]$wrongTag.state.authCalls -eq 0) 'wrong expected tag fails ownership identity readiness'

    # 9. A blocking health entry is not treated as READY.
    $healthFailure = Invoke-ProductionFixture -InitialHealth @('fixture blocking health')
    $caseCount++
    Check (-not $healthFailure.result -and $healthFailure.error -match '^TAILSCALE_HEALTH_ERROR' -and [int]$healthFailure.state.authCalls -eq 0) 'blocking Tailscale health is a distinct readiness failure'

    # A valid-looking payload without a positive self identity is never READY.
    $missingIdentity = Invoke-ProductionFixture -InitialHostName ''
    $caseCount++
    Check (-not $missingIdentity.result -and $missingIdentity.error -match '^TAILSCALE_WRONG_TAG' -and [int]$missingIdentity.state.authCalls -eq 0) 'missing self identity fails the readiness ownership gate'

    # Native status and preference command failures cannot be promoted by valid-looking JSON.
    $statusCommandFailure = Invoke-ProductionFixture -StatusExitCode 7
    $prefsCommandFailure = Invoke-ProductionFixture -PreferencesExitCode 7
    $caseCount++
    Check (-not $statusCommandFailure.result -and $statusCommandFailure.error -match '^TAILSCALE_CONTROL_PLANE_OFFLINE' -and [int]$statusCommandFailure.state.authCalls -eq 0) 'nonzero Tailscale status exit fails closed'
    $caseCount++
    Check (-not $prefsCommandFailure.result -and $prefsCommandFailure.error -match '^TAILSCALE_HEALTH_ERROR' -and [int]$prefsCommandFailure.state.authCalls -eq 0) 'nonzero Tailscale preference exit fails closed'

    # 10. Repeated healthy execution is mutation-free and idempotent.
    $repeatOne = Invoke-ProductionFixture
    $repeatTwo = Invoke-ProductionFixture
    $caseCount++
    Check ($repeatOne.result -and $repeatTwo.result -and [int]$repeatOne.state.authCalls -eq 0 -and [int]$repeatTwo.state.authCalls -eq 0 -and [int]$repeatOne.state.startCalls -eq 0 -and [int]$repeatTwo.state.startCalls -eq 0) 'repeated healthy execution does not force reauth or create a new identity'

    # 11. E2E profiles are deterministic, tagged, preauthorized, and ephemeral.
    $profileConfig = [pscustomobject]@{
        Primary = [pscustomobject]@{ InstanceName = 'DevFleet-E2E-Primary' }
        Failover = [pscustomobject]@{ InstanceName = 'DevFleet-E2E-Failover' }
        Vault = [pscustomobject]@{ InstanceName = 'DevFleet-E2E-Vault' }
    }
    $e2eProfile = New-TailscaleE2EEnrollmentProfile -RunId 'oauth-profile-fixture' -Config $profileConfig
    $caseCount++
    Check ([string]$e2eProfile.mode -ceq 'e2e' -and [string]$e2eProfile.tag -ceq 'tag:devfleet-e2e' -and [bool]$e2eProfile.ephemeral -and [bool]$e2eProfile.preauthorized -and [string]$e2eProfile.hostName -match '^devfleet-e2e-[0-9a-f]{10}-windows$' -and @($e2eProfile.guestHostnames.Keys).Count -eq 3) 'E2E enrollment profile has deterministic disposable semantics'

    # 12. Persistent fixture semantics remain explicit and non-ephemeral.
    $persistentPath = Join-Path $scratch 'persistent-profile.json'
    $persistentDocument = [ordered]@{
        schemaVersion = 1; mode = 'persistent'; tag = 'tag:devfleet'; ephemeral = $false; preauthorized = $true
        hostName = 'devfleet-persistent-windows'; guestHostnames = [ordered]@{ 'DevFleet-E2E-Primary' = 'devfleet-persistent-primary' }
    } | ConvertTo-Json -Depth 5 -Compress
    [IO.File]::WriteAllText($persistentPath, $persistentDocument, [Text.UTF8Encoding]::new($false))
    $persistentProfile = Get-DevFleetTailscaleEnrollmentProfile -Path $persistentPath
    $caseCount++
    Check ([string]$persistentProfile.mode -ceq 'persistent' -and [string]$persistentProfile.tag -ceq 'tag:devfleet' -and -not [bool]$persistentProfile.ephemeral -and [bool]$persistentProfile.preauthorized -and [string]$persistentProfile.hostName -ceq 'devfleet-persistent-windows') 'persistent enrollment profile remains explicitly non-ephemeral and tagged'

    # 13. File-backed OAuth input keeps raw credentials out of argv/output and cleans up.
    $redactionSecret = 'fixture-oauth-secret-' + [guid]::NewGuid().ToString('N')
    $redactionExpectedKey = 'ts' + 'key-' + ('fixture' * 4)
    $redactionState = @{ filePath = ''; filePresent = $false; rawInArguments = $false; fileContainsSecret = $false }
    $redactionInvoker = {
        param([string]$AuthFile, [string[]]$Arguments)
        $redactionState.filePath = $AuthFile
        $redactionState.filePresent = Test-Path -LiteralPath $AuthFile -PathType Leaf
        $redactionState.rawInArguments = ($Arguments -join ' ').Contains($redactionSecret)
        $redactionState.fileContainsSecret = ([IO.File]::ReadAllText($AuthFile)).Contains($redactionSecret)
        $dummyKey = 'ts' + 'key-' + ('fixture' * 4)
        $dummyBearer = 'Bearer fixture-token-' + [guid]::NewGuid().ToString('N')
        [pscustomobject]@{ exitCode = 0; output = "$dummyKey oauth=$redactionSecret $dummyBearer" }
    }.GetNewClosure()
    $redactionResult = Invoke-TailscaleOAuthClientSecretFileCommand -ClientSecret $redactionSecret -Hostname 'fixture-node' -CommandInvoker $redactionInvoker -TimeoutSeconds 15
    $caseCount++
    Check ($redactionState.filePresent -and $redactionState.fileContainsSecret -and -not $redactionState.rawInArguments -and $redactionResult.output -notmatch [regex]::Escape($redactionSecret) -and $redactionResult.output -notmatch [regex]::Escape($redactionExpectedKey) -and $redactionResult.output -notmatch 'fixture-token-' -and -not (Test-Path -LiteralPath $redactionState.filePath)) 'OAuth file input redacts representative tokens and removes the temporary file'

    # 14. A never-ready post-enrollment state terminates within its owner deadline.
    $neverReadyStart = [datetime]::UtcNow
    $neverReady = Invoke-ProductionFixture -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @() -FinalBackend 'NeedsLogin' -FinalOnline:$false -FinalIps @()
    $neverReadyElapsed = ([datetime]::UtcNow - $neverReadyStart).TotalSeconds
    $caseCount++
    Check (-not $neverReady.result -and $neverReady.error -match '^TAILSCALE_NEEDS_LOGIN' -and [int]$neverReady.state.authCalls -eq 1 -and [int]$neverReady.state.statusCalls -eq 2 -and $neverReadyElapsed -lt 10) 'never-ready authentication ends after one bounded attempt within the owner deadline'

    # 15. Tailnet Lock is observed, never bypassed, and requires trusted signing.
    $locked = Invoke-ProductionFixture -LockStatus 'ENABLED' -InitialBackend 'NeedsLogin' -InitialOnline:$false -InitialIps @()
    $caseCount++
    Check (-not $locked.result -and $locked.error -match '^TAILNET_LOCK_SIGNING_REQUIRED' -and [int]$locked.state.authCalls -eq 0) 'Tailnet Lock blocks OAuth enrollment without a trusted signing path'

    # Exercise the actual protected-store classification with an isolated fixture path.
    $oauthConfig = [pscustomobject]@{ Authentication = [pscustomobject]@{ Provider = 'OAuthClientSecretStore' } }
    $savedLocalAppData = $env:LOCALAPPDATA
    try {
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $scratch, 'Process')
        $missingStore = Get-TailscaleAuthenticationSecret -Config $oauthConfig
        Check (-not [bool]$missingStore.available -and -not [bool]$missingStore.invalid -and [string]$missingStore.provider -ceq 'OAuthClientSecretStore') 'protected-store absence is classified as missing credential'
        $isolatedStorePath = Join-Path $scratch 'DevFleet\E2E\secrets.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $isolatedStorePath) -Force | Out-Null
        [IO.File]::WriteAllText($isolatedStorePath, 'not-json', [Text.UTF8Encoding]::new($false))
        $invalidStore = Get-TailscaleAuthenticationSecret -Config $oauthConfig
        Check (-not [bool]$invalidStore.available -and [bool]$invalidStore.invalid -and [string]$invalidStore.provider -ceq 'OAuthClientSecretStore') 'protected-store corruption is classified as invalid credential'
    } finally {
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $savedLocalAppData, 'Process')
    }
} catch {
    [void]$failures.Add('unexpected OAuth automation test harness exception')
} finally {
    if ($scratch -and (Test-Path -LiteralPath $scratch)) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
[pscustomobject][ordered]@{
    status = $status
    cases = $caseCount
    passed = $passed
    failed = $failures.Count
    failures = @($failures)
} | ConvertTo-Json -Depth 5
if ($status -ne 'PASS') { exit 1 }

```


## FILE: automation/release-e2e/tests/Test-TerminalCleanupBoundaries.ps1

SHA256: 0e5ed34119cfc88373e2da6eaa9934ba0f32a3e940638a26239e7ff1339ac25a | Bytes: 21398 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot,[switch]$Baseline)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Pass, [string]$Detail='') { $checks.Add([pscustomobject]@{ name=$Name; pass=$Pass; detail=$Detail }) }

function Import-ProductionFunction([string]$Path, [string]$Name, [switch]$Baseline) {
    $tokens = $null; $errors = $null
    if($Baseline){
        $relative=$Path.Substring($WorkspaceRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Replace([string][IO.Path]::DirectorySeparatorChar,'/')
        $sourceText=@(& git -C $WorkspaceRoot show ("HEAD:"+$relative) 2>$null)-join [Environment]::NewLine
        if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sourceText)){throw "Could not load baseline source for $relative"}
        $ast=[Management.Automation.Language.Parser]::ParseInput($sourceText,[ref]$tokens,[ref]$errors)
    }else{$ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)}
    if (@($errors).Count) { throw "Production source does not parse: $Path" }
    $found = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name }, $true))
    if ($found.Count -ne 1) { throw "Expected exactly one production function $Name in $Path" }
    $bodyText=$found[0].Body.Extent.Text.Trim()
    $bodyText=$bodyText.Substring(1,$bodyText.Length-2)
    $functionBody=if($found[0].ParamBlock){$found[0].ParamBlock.Extent.Text+[Environment]::NewLine+$bodyText}else{$bodyText}
    Set-Item -Path ("Function:\script:{0}" -f $Name) -Value ([scriptblock]::Create($functionBody))
}

Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Evidence.psm1') -Force
Import-ProductionFunction (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Cleanup.psm1') 'Write-TerminalVmEvidence' -Baseline:$Baseline
Import-ProductionFunction (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Cleanup.psm1') 'Get-DevFleetHostNameExclusion'
Import-ProductionFunction (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/FullRelease.psm1') 'Invoke-FullReleaseCleanup' -Baseline:$Baseline
Import-ProductionFunction (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/FullRelease.psm1') 'Write-PostCleanupFinalization' -Baseline:$Baseline

$script:fixture = $null
function Get-VM {
    [CmdletBinding()]
    param([guid]$Id, [string]$Name)
    if ($PSBoundParameters.ContainsKey('Id')) { return $script:fixture.vm }
    $script:fixture.hostL2Queries++
    if ($script:fixture.hostQueryDenied) { throw 'Mock host inventory denied.' }
    if ($script:fixture.hostNotFoundNative) {
        $message='Hyper-V was unable to find a virtual machine with name "'+$Name+'".'
        $target=if($script:fixture.hostNotFoundTarget){$script:fixture.hostNotFoundTarget}else{$Name}
        $record=[Management.Automation.ErrorRecord]::new([ArgumentException]::new($message),'InvalidParameter,Microsoft.HyperV.PowerShell.Commands.GetVM',[Management.Automation.ErrorCategory]::InvalidArgument,$target)
        throw $record
    }
    if ($script:fixture.hostL2Present) { return [pscustomobject]@{Name=$script:fixture.l2Name;Id=[guid]::NewGuid();State='Off'} }
    return @()
}
function New-CleanupManifest { param($Vm,$RunId) [pscustomobject]@{ runId=$RunId; resources=@() } }
function Test-CleanupManifest { param($Manifest) return $true }
function Get-AssertedDisposableVm { param($ExpectedVm) return $ExpectedVm }
function Start-VM { param($VM) $script:fixture.startCalls++;$script:fixture.vm.State='Running' }
function Stop-ManifestVm { param($Manifest) $script:fixture.stopCalls++;$script:fixture.vm.State='Off' }
function Connect-DevFleetGuest { param([guid]$VmId) return [pscustomobject]@{Id='mock-session'} }
function Clear-DevFleetE2EInteractiveLogonState { param([guid]$VmId) return [pscustomobject]@{status='PASS';registryCleanupPersisted=$true;temporaryDefaultPasswordRemovalPersisted=$true;ordinaryDefaultPasswordPresent=$false} }
function Invoke-Command { param($Session,$ScriptBlock,$ArgumentList) $script:fixture.remoteCalls++;return [pscustomobject]@{status='PASS';computer='L1';runRootAbsent=$true;uiaTasksAbsent=$true;nestedName=$script:fixture.l2Name;nestedAbsent=$true;foreignResourcesMutated=$false} }
function Remove-PSSession { param($Session) }
function Get-DevFleetNestedL2State { param($Session,$ExpectedName) $script:fixture.nestedCalls++;return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;observedUtc='2026-09-24T00:00:00Z';verification='controlled missing or incomplete inventory'