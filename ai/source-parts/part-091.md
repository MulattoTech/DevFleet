# DevFleet source part 091

Full-source UTF-8 byte interval [4185000, 4231500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 892bb74613ccb732ab249cbb251a95496389a9dbda86665cfa81f96b410f72f3

<!-- BEGIN SOURCE SLICE -->
ing(1, $guestArgument.Length - 2).Replace("'\''", "'")
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

```


## FILE: source/tests/Test-TailscalePostEnrollmentStatusRetry.ps1

SHA256: 31de50a4f3beea14044a09fcf7ae763d4b495226d6ebd40d916b1d3be12bf2a2 | Bytes: 10166 | Git mode: 100644

```
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

```


## FILE: source/tests/Test-TailscaleStageDeadlineComposition.ps1

SHA256: 32076c12d01e5c0b9cbc72fb7824959e633e60aa098cadc71f76d8e41182fd23 | Bytes: 1201 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference = 'Stop'
$commonPath = Join-Path $WorkspaceRoot 'source/windows/DevFleet.Common.psm1'
Import-Module $commonPath -Force -DisableNameChecking

$windowsBudget = [int](Get-DevFleetStageBudgetSeconds 'windowsTailscale')
$guestBudget = [int](Get-DevFleetStageBudgetSeconds 'tailscale')

# The Windows stage owns service startup, browser handoff, and a real human
# approval. The exact Laptop run showed that 180 seconds could be consumed
# before the browser handoff became usable. Reuse the existing bounded guest
# pairing budget instead of introducing a second timeout policy.
if ($windowsBudget -ne 900) {
    throw "windowsTailscale stage budget must be 900 seconds for the bounded human pairing flow; observed $windowsBudget."
}
if ($windowsBudget -ne $guestBudget) {
    throw "Windows and guest Tailscale pairing budgets diverged: windows=$windowsBudget guest=$guestBudget."
}

[ordered]@{
    status = 'PASS'
    windowsTailscaleSeconds = $windowsBudget
    tailscaleSeconds = $guestBudget
    boundedHumanPairingBudgetAligned = $true
} | ConvertTo-Json -Compress

```


## FILE: source/tests/Test-WindowsIntegrationOwnership.ps1

SHA256: b1ed85f8d67c5ab506ad550fac4d6a93af97ca8a2b9b6ab2ff530ad83aa14846 | Bytes: 5263 | Git mode: 100644

```
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'windows\DevFleet-WindowsIntegrationOwnership.psm1') -Force

function Assert-ThrowsOwnershipConflict([scriptblock]$Action) {
    try { & $Action; throw 'Expected an ownership conflict.' }
    catch { if ($_.Exception.Message -notmatch 'OWNERSHIP CONFLICT') { throw } }
}

$generation = [guid]::NewGuid().ToString('D')
$task = @{Name='DevFleet Host Agent';Executable="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe";Arguments='-NoProfile -File "C:\ProgramData\DevFleetHostAgent\DevFleet-HostAgent.ps1"';Principal='SYSTEM';LogonType='ServiceAccount';RunLevel='Highest';Description="M-TechLabs DevFleet; generation=$generation";Generation=$generation;Marker='M-TechLabs DevFleet Host Agent'}
Assert-DevFleetTaskBinding -Expected $task -Actual (@{} + $task) | Out-Null
$foreignTask = @{} + $task; $foreignTask.Executable = "$env:SystemRoot\System32\cmd.exe"
Assert-ThrowsOwnershipConflict { Assert-DevFleetTaskBinding -Expected $task -Actual $foreignTask }

$firewall = @{Name='DevFleetHostAgent-8790-Tailscale';DisplayName='DevFleet Host Agent 8790 - Tailscale';Group='M-TechLabs DevFleet Host Agent';Description="M-TechLabs DevFleet; generation=$generation";Direction='Inbound';Action='Allow';Protocol='TCP';LocalPort='8790';InterfaceAlias='Tailscale';RemoteAddress='100.64.0.0/10';Profile='Any';Generation=$generation;Marker='M-TechLabs DevFleet Host Agent'}
Assert-DevFleetFirewallBinding -Expected $firewall -Actual (@{} + $firewall) | Out-Null
$providerFirewall = @{} + $firewall; $providerFirewall.RemoteAddress = '100.64.0.0/255.192.0.0'
Assert-DevFleetFirewallBinding -Expected $firewall -Actual $providerFirewall | Out-Null
$multipassFirewall = @{} + $firewall; $multipassFirewall.Name = 'DevFleetHostAgent-8790-Multipass'; $multipassFirewall.DisplayName = 'DevFleet Host Agent 8790 - Multipass'; $multipassFirewall.InterfaceAlias = 'vEthernet (Default Switch)'; $multipassFirewall.RemoteAddress = '172.23.144.1/20'
$multipassProviderFirewall = @{} + $multipassFirewall; $multipassProviderFirewall.RemoteAddress = '172.23.144.0/255.255.240.0'
Assert-DevFleetFirewallBinding -Expected $multipassFirewall -Actual $multipassProviderFirewall | Out-Null
$staleVirtualNetworkFirewall = @{} + $multipassFirewall; $staleVirtualNetworkFirewall.InterfaceAlias = '0e5a7c8a-7826-4655-8648-a711bb6d7f87'; $staleVirtualNetworkFirewall.RemoteAddress = '172.21.176.0/255.255.240.0'
Assert-DevFleetFirewallRefreshIdentity -Expected $multipassFirewall -Actual $staleVirtualNetworkFirewall | Out-Null
Assert-ThrowsOwnershipConflict { Assert-DevFleetFirewallBinding -Expected $multipassFirewall -Actual $staleVirtualNetworkFirewall }
$foreignRefreshFirewall = @{} + $staleVirtualNetworkFirewall; $foreignRefreshFirewall.Group = 'Foreign Firewall Group'
Assert-ThrowsOwnershipConflict { Assert-DevFleetFirewallRefreshIdentity -Expected $multipassFirewall -Actual $foreignRefreshFirewall }
$foreignFirewall = @{} + $firewall; $foreignFirewall.RemoteAddress = 'Any'
Assert-ThrowsOwnershipConflict { Assert-DevFleetFirewallBinding -Expected $firewall -Actual $foreignFirewall }

$service = @{Name='DevFleetHostAgent';ImagePath='C:\Program Files\M-TechLabs\DevFleet\agent.exe';Account='LocalSystem';StartMode='Auto';Generation=$generation;Marker='M-TechLabs DevFleet Host Agent'}
$liveService = @{} + $service; $liveService.ImagePath = '"C:\Program Files\M-TechLabs\DevFleet\agent.exe" --service'
Assert-DevFleetServiceBinding -Expected $service -Actual $liveService | Out-Null
$foreignService = @{} + $service; $foreignService.ImagePath = 'C:\Foreign\agent.exe'
Assert-ThrowsOwnershipConflict { Assert-DevFleetServiceBinding -Expected $service -Actual $foreignService }

$temporary = Join-Path ([IO.Path]::GetTempPath()) ("devfleet-integration-ownership-$([guid]::NewGuid().ToString('N')).json")
try {
    $ledger = @{SchemaVersion=1;InstallationGeneration=$generation;ScheduledTasks=@($task);FirewallRules=@($firewall);Services=@($service)}
    Write-DevFleetIntegrationOwnership -Path $temporary -Ledger $ledger
    $loaded = Read-DevFleetIntegrationOwnership -Path $temporary
    if ($loaded.InstallationGeneration -ne $generation) { throw 'Ledger generation did not round-trip.' }
    $ledger.FirewallRules[0].Generation = [guid]::NewGuid().ToString('D')
    Write-DevFleetIntegrationOwnership -Path $temporary -Ledger $ledger
    try { Read-DevFleetIntegrationOwnership -Path $temporary | Out-Null; throw 'Cross-generation ledger was accepted.' }
    catch { if ($_.Exception.Message -notmatch 'cross-generation') { throw } }
} finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }

$hostAgent = Get-Content -LiteralPath (Join-Path $root 'windows\DevFleet-HostAgent.ps1') -Raw
if ($hostAgent -notmatch 'Invoke-DevFleetOwnedFirewallRefresh') { throw 'Host Agent startup does not reconcile owned firewall bindings.' }
$installer = Get-Content -LiteralPath (Join-Path $root 'windows\Install-DevFleet-HostAgent.ps1') -Raw
if ($installer -notmatch 'Invoke-DevFleetOwnedFirewallRefresh') { throw 'Host Agent installation path does not reconcile prior owned firewall bindings.' }

'PASS Windows integration ownership binding tests'

```


## FILE: source/tests/_bundle_layout.py

SHA256: bcd842e85f5b6c5f4a5365ffbdf032b9b1781b4e9a1a9f811e12652d171727c3 | Bytes: 1572 | Git mode: 100644

```
from __future__ import annotations

from dataclasses import dataclass
import importlib.util
import sys
from pathlib import Path


@dataclass(frozen=True)
class BundleLayout:
    """Explicit repository/canonical-bundle roots used by path-sensitive tests."""

    bundle_root: Path
    source_root: Path
    installer_source_root: Path
    release_tooling_root: Path
    release_e2e_root: Path


def resolve_bundle_layout(anchor: Path) -> BundleLayout:
    anchor = anchor.resolve()
    for candidate in (anchor, *anchor.parents):
        for helper in (candidate / "release-tooling/audit_bundle_paths.py", candidate / "tools/audit_bundle_paths.py"):
            if not helper.is_file():
                continue
            spec = importlib.util.spec_from_file_location("devfleet_audit_bundle_paths", helper)
            if spec is None or spec.loader is None:
                continue
            module = importlib.util.module_from_spec(spec)
            # Dataclasses and other introspection-based modules expect the
            # executing module to be registered, as it is during ordinary
            # imports.  Preserve that invariant for relocated bundles.
            sys.modules[spec.name] = module
            spec.loader.exec_module(module)
            layout = module.resolve_bundle_layout(anchor)
            return BundleLayout(layout.bundle_root, layout.source_root, layout.installer_source_root, layout.release_tooling_root, layout.release_e2e_root)
    raise AssertionError(f"Could not identify a repository or canonical audit bundle root from {anchor}")

```


## FILE: source/tests/conftest.py

SHA256: 03e3e1fab21c2523e89b74fb326aca7d38c1927a1aec528997f30558f714ee64 | Bytes: 1430 | Git mode: 100644

```
import json,os,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT));sys.path.insert(0,str(ROOT/'app'))
TESTROOT=ROOT/'.test-runtime';
for d in ('workspaces','quarantine','runtime','cache','static','templates'): (TESTROOT/d).mkdir(parents=True,exist_ok=True)
config={'node_name':'test-node','deployment_id':'deployment-123','node_role':'primary','friendly_name':'CodexDevVM','portal_port':8787,'workspaces':str(TESTROOT/'workspaces'),'quarantine':str(TESTROOT/'quarantine'),'peer_file':str(TESTROOT/'peer.json'),'runtime_root':str(TESTROOT/'runtime'),'cache_root':str(TESTROOT/'cache'),'ollama_base_url':'http://127.0.0.1:11434/v1','ollama_model':'test-model','ollama_profile':'stable-interactive','development_profile':'balanced','docker_mode':'rootless','enable_shared_caches':True,'enable_analyzer_cache':True,'auto_start_codexpro':True,'allow_tailnet_ports':True,'backup_before_rebuild':False,'backup_before_quarantine':True,'require_tailscale':False,'tailnet_cidr':'100.64.0.0/10','public_binding_allowed':True}
(TESTROOT/'config.json').write_text(json.dumps(config));(TESTROOT/'peer.json').write_text('{}');os.environ.update({'DEVFLEET_CONFIG_PATH':str(TESTROOT/'config.json'),'DEVFLEET_ADMIN_USER':'test','DEVFLEET_ADMIN_PASSWORD':'test-password','DEVFLEET_API_TOKEN':'test-token','DEVFLEET_STATIC_DIR':str(ROOT/'app/static'),'DEVFLEET_TEMPLATE_DIR':str(ROOT/'app/templates')})

```


## FILE: source/tests/test_analyzer.py

SHA256: 359450217b36e714dd5411b47230100fc0723991377d4ecab213d3ef11ed2a00 | Bytes: 3363 | Git mode: 100644

```
from pathlib import Path
import tempfile
import pytest

from devfleet.analyzer import analyze_project, has_blockers


def analyze(compose: str):
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)
        (p/'compose.yaml').write_text(compose)
        return analyze_project(p)


def test_safe_relative_mount():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    volumes: [\".:/workspaces/x\"]\n    security_opt: [\"no-new-privileges:true\"]\n    healthcheck: {test: [\"CMD\", \"true\"]}\n''')
    assert not has_blockers(findings), findings


def test_absolute_mount_blocked():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    volumes: [\"/home/devrunner:/host\"]\n''')
    assert any(x['code']=='docker.mount' and x['severity']=='critical' for x in findings)


def test_parent_mount_blocked():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    volumes: [\"../other-project:/other\"]\n''')
    assert any(x['code']=='docker.mount' and x['severity']=='critical' for x in findings)


def test_socket_and_privileged_blocked():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    privileged: true\n    volumes: [\"/run/user/1001/docker.sock:/var/run/docker.sock\"]\n''')
    assert has_blockers(findings)
    assert {'docker.mount','docker.privileged'} <= {x['code'] for x in findings}

def test_public_port_and_device_blocked():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    ports: [\"3000:3000\"]\n    devices: [\"/dev/kvm:/dev/kvm\"]\n''')
    assert {'docker.port-public','docker.devices'} <= {x['code'] for x in findings}


def test_loopback_port_allowed():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    ports: [\"127.0.0.1:3000:3000\"]\n    security_opt: [\"no-new-privileges:true\"]\n    healthcheck: {test: [\"CMD\", \"true\"]}\n''')
    assert not has_blockers(findings), findings

def test_symlink_bind_source_outside_project_is_blocked(tmp_path: Path):
    outside=tmp_path/'outside'
    outside.mkdir()
    project=tmp_path/'project'
    project.mkdir()
    try:
        (project/'escape').symlink_to(outside, target_is_directory=True)
    except OSError:
        pytest.skip('Windows test host does not grant symbolic-link creation privilege')
    (project/'compose.yaml').write_text('''services:\n  app:\n    image: alpine:3.20\n    security_opt: [no-new-privileges:true]\n    volumes:\n      - ./escape:/data\n    ports:\n      - 127.0.0.1:8080:80\n''')
    findings=analyze_project(project)
    assert has_blockers(findings)
    assert any(x['code']=='docker.mount-resolution' for x in findings)


def test_rebuild_context_symlink_outside_project_is_blocked(tmp_path: Path):
    outside=tmp_path/'outside-build'
    outside.mkdir()
    project=tmp_path/'project'
    project.mkdir()
    try:
        (project/'escape-build').symlink_to(outside, target_is_directory=True)
    except OSError:
        pytest.skip('Windows test host does not grant symbolic-link creation privilege')
    (project/'compose.yaml').write_text('''services:\n  app:\n    build: ./escape-build\n    security_opt: [no-new-privileges:true]\n    ports:\n      - 127.0.0.1:8080:80\n''')
    findings=analyze_project(project)
    assert has_blockers(findings)
    assert any(x['code']=='docker.build-context' for x in findings)

```


## FILE: source/tests/test_analyzer_v11.py

SHA256: 11738fb7c631b7c0d2de4d70956ce3e458f5b0aed5d302702ff7bb60ee484ccb | Bytes: 4024 | Git mode: 100644

```
from pathlib import Path
import pytest
from devfleet.analyzer import analyze_project,has_blockers
def project(tmp_path,text):
 p=tmp_path/'demo';p.mkdir();(p/'compose.yaml').write_text(text);return p
def test_windows_mount_blocked(tmp_path):assert has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    volumes: ["C:\\\\Users:/host"]\n'),'balanced',True))
def test_parent_mount_blocked(tmp_path):assert has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    volumes: ["../:/host"]\n'),'fast',True))
def test_docker_socket_blocked_in_fast(tmp_path):assert has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    volumes: ["/var/run/docker.sock:/var/run/docker.sock"]\n'),'fast',True))
def test_loopback_port_allowed_balanced(tmp_path):assert not has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    ports: ["127.0.0.1:3000:3000"]\n    healthcheck: {test: ["CMD","true"]}\n    security_opt: ["no-new-privileges:true"]\n'),'balanced',True))
def test_tailnet_allowed_balanced(tmp_path):assert not has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    ports: ["100.64.1.2:3000:3000"]\n    healthcheck: {test: ["CMD","true"]}\n    security_opt: ["no-new-privileges:true"]\n'),'balanced',True))
def test_public_port_blocked(tmp_path):assert has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    ports: ["3000:3000"]\n'),'fast',True))
def test_symlink_escape_blocked(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    image: x:1\n')
 try:(p/'escape').symlink_to(tmp_path)
 except OSError:pytest.skip('Windows test host does not grant symbolic-link creation privilege')
 assert has_blockers(analyze_project(p,'balanced',True))
def test_cache_invalidates(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    image: x:1\n    ports: ["127.0.0.1:3000:3000"]\n');a=analyze_project(p,'balanced');(p/'compose.yaml').write_text('services:\n  x:\n    image: x:1\n    ports: ["3000:3000"]\n');b=analyze_project(p,'balanced');assert a!=b and has_blockers(b)

def test_balanced_hardening_items_are_warnings(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    build: .\n    ports: ["127.0.0.1:3000:3000"]\n');(p/'Dockerfile').write_text('FROM alpine:3.20\nRUN true\n')
 findings=analyze_project(p,'balanced',True)
 by_code={x['code']:x['severity'] for x in findings}
 assert by_code['docker.healthcheck']=='warning'
 assert by_code['docker.no-new-privileges']=='warning'
 assert by_code['docker.non-root-user']=='warning'
 assert not has_blockers(findings)

def test_strict_hardening_items_block(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    build: .\n');(p/'Dockerfile').write_text('FROM alpine:3.20\n')
 assert has_blockers(analyze_project(p,'strict',True))

def test_fast_device_requires_project_acknowledgement(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    image: alpine:3.20\n    devices: ["/dev/kvm:/dev/kvm"]\n    ports: ["127.0.0.1:3000:3000"]\n    healthcheck: {test: ["CMD","true"]}\n    security_opt: ["no-new-privileges:true"]\n')
 (p/'.devfleet').mkdir();(p/'.devfleet/project.json').write_text('{"profile":"fast","allow_devices":false}')
 assert has_blockers(analyze_project(p,'fast',True))
 (p/'.devfleet/project.json').write_text('{"profile":"fast","allow_devices":true}')
 assert not has_blockers(analyze_project(p,'fast',True))

def test_cache_invalidates_when_referenced_environment_file_changes(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    image: alpine:3.20\n    env_file: config/runtime-settings\n    ports: ["127.0.0.1:3000:3000"]\n    healthcheck: {test: ["CMD","true"]}\n    security_opt: ["no-new-privileges:true"]\n')
 (p/'config').mkdir();env=p/'config/runtime-settings';env.write_text('MODE=one\n')
 analyze_project(p,'balanced');cache=p/'.devfleet/runtime/analyzer-cache.json';first=cache.read_text()
 env.write_text('MODE=two-with-different-size\n')
 analyze_project(p,'balanced');assert cache.read_text()!=first

```


## FILE: source/tests/test_audit5_destructive.py

SHA256: 3ce81d650d6d41c7d18b76194d7eefe01feeb1231d80f772051ef845003f0ec1 | Bytes: 5863 | Git mode: 100644

```
from __future__ import annotations

import hashlib
import os
import tarfile
from pathlib import Path

import pytest
from types import SimpleNamespace

from devfleet import projects
from devfleet.workspace_archives import (
    create_workspace_archive,
    restore_workspace_archive,
    write_backup_manifest,
)


def _hash_tree(root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        result[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def _metadata(source: Path) -> None:
    metadata = source / ".devfleet" / "project.json"
    metadata.parent.mkdir(parents=True, exist_ok=True)
    metadata.write_text('{"schema_version":3,"managed_by":"devfleet","project_id":"12345678-1234-1234-1234-123456789012","slug":"demo","runtime_provider":"docker-compose","host_id":"test-node"}', encoding="utf-8")


def test_destructive_backup_preserves_generated_looking_user_files(tmp_path: Path):
    source = tmp_path / "source"
    _metadata(source)
    for relative, data in {
        "build/irreplaceable.bin": b"build-user-data",
        "dist/manual-output.dat": b"dist-user-data",
        "node_modules/user-preserved-test.txt": b"node-user-data",
        ".next/notes.txt": b"next-user-data",
        "arbitrary/nested-generated-looking/file.txt": b"nested-user-data",
    }.items():
        path = source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    archive = tmp_path / "backup.tar.gz"
    result = create_workspace_archive(source, "demo", archive, include_generated=True, consistency_level="quiesced")
    assert result["omitted_paths"] == []
    assert result["included_file_count"] == 6
    restored = tmp_path / "restored"
    restore_workspace_archive(archive, restored, "demo")
    assert _hash_tree(source) == _hash_tree(restored)


def test_routine_backup_keeps_documented_generated_directory_omission(tmp_path: Path):
    source = tmp_path / "source"
    _metadata(source)
    (source / "build").mkdir(parents=True)
    (source / "build" / "cache.bin").write_bytes(b"cache")
    archive = tmp_path / "routine.tar.gz"
    result = create_workspace_archive(source, "demo", archive)
    assert "build" in result["omitted_paths"]
    with tarfile.open(archive, "r:gz") as bundle:
        assert "demo/build/cache.bin" not in bundle.getnames()


@pytest.mark.skipif(os.name != "posix", reason="POSIX permission fidelity is unavailable on Windows")
def test_restore_preserves_safe_modes_and_strips_special_bits(tmp_path: Path):
    source = tmp_path / "source"
    source.mkdir()
    _metadata(source)
    executable = source / "hook.sh"
    private = source / "private.key"
    executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    private.write_text("secret", encoding="utf-8")
    os.chmod(executable, 0o755)
    os.chmod(private, 0o600)
    archive = tmp_path / "modes.tar.gz"
    create_workspace_archive(source, "demo", archive, include_generated=True)

    # Make the archive metadata hostile.  Restore must mask privilege-bearing
    # special bits while retaining ordinary permissions.
    rewritten = tmp_path / "hostile.tar.gz"
    with tarfile.open(archive, "r:gz") as original, tarfile.open(rewritten, "w:gz") as target:
        for member in original.getmembers():
            member.mode |= 0o6000
            if member.name.endswith("hook.sh"):
                member.mode = 0o6755
            source_file = original.extractfile(member) if member.isfile() else None
            target.addfile(member, source_file)
            if source_file is not None:
                source_file.close()

    restored = tmp_path / "restored"
    restore_workspace_archive(rewritten, restored, "demo")
    assert (restored / "hook.sh").stat().st_mode & 0o777 == 0o755
    assert (restored / "private.key").stat().st_mode & 0o777 == 0o600


def test_restore_deleted_project_uses_tombstone_and_exact_identity(tmp_path: Path, monkeypatch):
    workspaces = tmp_path / "workspaces"
    runtime = tmp_path / "runtime"
    settings = SimpleNamespace(workspaces=workspaces, runtime_root=runtime, host_id="test-node")
    monkeypatch.setattr(projects, "SETTINGS", settings)
    source = tmp_path / "source"
    _metadata(source)
    (source / "build").mkdir()
    (source / "build" / "irreplaceable.bin").write_bytes(b"keep")
    backup_dir = runtime / "workspace-backups" / "demo-backup"
    archive = backup_dir / "demo.tar.gz"
    result = create_workspace_archive(source, "demo", archive, include_generated=True, consistency_level="quiesced")
    write_backup_manifest(
        backup_dir,
        slug="demo",
        project_id="12345678-1234-1234-1234-123456789012",
        runtime={"provider": "docker-compose", "runtime_id": ""},
        archive=result,
        consistency_level="quiesced",
    )
    tombstone = {
        "project_id": "12345678-1234-1234-1234-123456789012",
        "slug": "demo",
        "runtime_provider": "docker-compose",
        "backup_id": "demo-backup",
        "backup_sha256": result["archive_sha256"],
    }
    tombstone_path = projects._recovery_tombstone_path("demo", tombstone["project_id"])
    tombstone_path.parent.mkdir(parents=True, exist_ok=True)
    tombstone_path.write_text(__import__("json").dumps(tombstone), encoding="utf-8")
    recovered = projects.restore_deleted_project(
        "demo", "demo-backup", project_id=tombstone["project_id"], confirm_restore=True
    )
    assert recovered["ok"] is True
    assert (workspaces / "demo" / "build" / "irreplaceable.bin").read_bytes() == b"keep"
    with pytest.raises(ValueError, match="absent destination"):
        projects.restore_deleted_project(
            "demo", "demo-backup", project_id=tombstone["project_id"], confirm_restore=True
        )

```


## FILE: source/tests/test_audit_coherence.py

SHA256: 58d8a589d22f1d4ff33419dbee2864b9a56fe5a9b4a6ffcf4fdc6d1079156e57 | Bytes: 36369 | Git mode: 100644

```
from __future__ import annotations

import copy
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from types import SimpleNamespace

import pytest
import importlib.util

_VALIDATOR_PATH = Path(__file__).parents[1] / "tools" / "validate_audit_coherence.py"
_SPEC = importlib.util.spec_from_file_location("validate_audit_coherence", _VALIDATOR_PATH)
assert _SPEC and _SPEC.loader
_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MODULE)
validate_root = _MODULE.validate_root

_AI_VALIDATOR_PATH = Path(__file__).parents[1] / "tools" / "validate_ai_audit_bundle.py"
_AI_SPEC = importlib.util.spec_from_file_location("validate_ai_audit_bundle", _AI_VALIDATOR_PATH)
assert _AI_SPEC and _AI_SPEC.loader
_AI_MODULE = importlib.util.module_from_spec(_AI_SPEC)
_AI_SPEC.loader.exec_module(_AI_MODULE)

ROOT = Path(__file__).parents[2]

_COMPUTE_SPEC = importlib.util.spec_from_file_location("compute_shipping_input_identity", ROOT / "tools/compute_shipping_input_identity.py")
assert _COMPUTE_SPEC and _COMPUTE_SPEC.loader
_COMPUTE_MODULE = importlib.util.module_from_spec(_COMPUTE_SPEC)
_COMPUTE_SPEC.loader.exec_module(_COMPUTE_MODULE)

_RELEASE_BUNDLE_SPEC = importlib.util.spec_from_file_location("validate_release_bundle", ROOT / "tools/validate_release_bundle.py")
assert _RELEASE_BUNDLE_SPEC and _RELEASE_BUNDLE_SPEC.loader
_RELEASE_BUNDLE_MODULE = importlib.util.module_from_spec(_RELEASE_BUNDLE_SPEC)
_RELEASE_BUNDLE_SPEC.loader.exec_module(_RELEASE_BUNDLE_MODULE)

def _fixture(tmp_path: Path) -> Path:
    root = tmp_path / "bundle"
    (root / "outputs").mkdir(parents=True)
    (root / "audit").mkdir()
    (root / "source" / "tools").mkdir(parents=True)
    # The validator recomputes release identities from the canonical helper.
    # Keep synthetic extracted fixtures self-contained just like the real
    # bundle; omitting this authority turns valid fixtures into import errors.
    shutil.copy2(ROOT / "source/tools/release_fingerprint.py", root / "source/tools/release_fingerprint.py")
    shutil.copy2(ROOT / "source/tools/hook_modes.py", root / "source/tools/hook_modes.py")
    (root / "installer-source").mkdir(parents=True)
    (root / "source" / "VERSION").write_text("1.2.13", encoding="utf-8")
    (root / "installer-source" / "INSTALLER_VERSION").write_text("1.4.1", encoding="utf-8")
    mode = {"schemaVersion": 1, "defaultMode": "0644", "executableMode": "0755", "executableByContract": []}
    rows = _fixture_shipping_rows(root)
    rows.sort(key=lambda row: (row["root"], row["path"]))
    shipping_identity = _MODULE._shipping_identity(
        {(row["root"], row["path"]): row for row in rows}, mode, "1.2.13", "1.4.1"
    )
    artifacts = {
        "exe": {"name": "exe", "path": "outputs/a.exe", "bytes": 1, "sha256": "a" * 64},
        "tar": {"name": "tar", "path": "outputs/a.tar.gz", "bytes": 2, "sha256": "b" * 64},
        "portable": {"name": "portable", "path": "outputs/a.zip", "bytes": 3, "sha256": "c" * 64},
        "installerSource": {"name": "installerSource", "path": "outputs/a-source.zip", "bytes": 4, "sha256": "d" * 64},
    }
    state = {
        "release_version": "1.2.13",
        "installer_version": "1.4.1",
        "git_commit": "1" * 40,
        "candidate_git_commit": "1" * 40,
        "releaseFingerprintId": "f" * 64,
        "toolingFingerprintId": "e" * 64,
        "shipping_input_identity": shipping_identity,
        "candidate_shipping_input_identity": shipping_identity,
        "source_changed_since_candidate": False,
        "rebuild_required": False,
        "candidate_is_current": True,
        "candidate_build_current": True,
        "validation_evidence_current": True,
        "full_release_passed": False,
        "physical_surrogate_certification_current": False,
        "internal_promotion_allowed": False,
        "public_promotion_allowed": False,
        "production_safety": {"production_unchanged": True, "mulattotechsurface_touched": False},
        "candidate": copy.deepcopy(artifacts),
        "gates": {"dependency_matrix": "UNVERIFIED"},
    }
    manifest = {
        "releaseVersion": "1.2.13",
        "installerVersion": "1.4.1",
        "gitCommit": state["git_commit"],
        "candidateGitCommit": state["git_commit"],
        "releaseFingerprintId": state["releaseFingerprintId"],
        "toolingFingerprintId": state["toolingFingerprintId"],
        "sourceChangedSinceCandidate": False,
        "rebuildRequired": False,
        "candidateIsCurrent": True,
        "artifacts": list(artifacts.values()),
        "shippingInputIdentity": shipping_identity,
        "candidateShippingInputIdentity": shipping_identity,
        "shippingModeContract": mode,
        "sourceInventory": [
            {"path": f"{row['root']}/{row['path']}", "bytes": row["bytes"], "sha256": row["sha256"], "mode": row["mode"]}
            for row in rows
        ],
        "expectedSourceCount": len(rows),
    }
    candidate_record = {
        "schemaVersion": 1,
        "candidateCommit": "1" * 40,
        "candidateShippingInputIdentity": shipping_identity,
        "shippingInputIdentity": shipping_identity,
        "candidateShippingInputs": rows,
        "candidateShippingModeContract": mode,
        "shippingModeContract": mode,
        "devfleetVersion": "1.2.13",
        "installerVersion": "1.4.1",
        "releaseFingerprintId": state["releaseFingerprintId"],
        "toolingFingerprintId": state["toolingFingerprintId"],
    }
    state["releaseFingerprintId"] = "f" * 64
    manifest["releaseFingerprintId"] = state["releaseFingerprintId"]
    (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (root / "outputs" / "final-artifact-hashes.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "CURRENT-CANDIDATE.json").write_text(json.dumps(candidate_record), encoding="utf-8")
    return root


def _fixture_shipping_rows(root: Path) -> list[dict]:
    rows = []
    for shipping_root in (root / "source", root / "installer-source"):
        label = shipping_root.name
        for path in sorted(p for p in shipping_root.rglob("*") if p.is_file()):
            relative = path.relative_to(shipping_root).as_posix()
            rows.append({
                "root": label,
                "path": relative,
                "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "mode": "0644",
            })
    rows.sort(key=lambda row: (row["root"], row["path"]))
    return rows


def _write_audit(root: Path, value: dict) -> None:
    (root / "audit" / "record.json").write_text(json.dumps(value), encoding="utf-8")


def _split_identity_fixture(tmp_path: Path, *, differing_head: bool = False) -> Path:
    root = _fixture(tmp_path)
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "outputs/final-artifact-hashes.json").read_text(encoding="utf-8"))
    candidate_record = json.loads((root / "CURRENT-CANDIDATE.json").read_text(encoding="utf-8"))
    candidate = "1" * 40
    head = "2" * 40 if differing_head else candidate
    rows = _fixture_shipping_rows(root)
    mode = {"schemaVersion": 1, "defaultMode": "0644", "executableMode": "0755", "executableByContract": []}
    identity = _MODULE._shipping_identity({(r["root"], r["path"]): r for r in rows}, mode, "1.2.13", "1.4.1")
    state.update({"git_commit": head, "repository_head": head, "candidate_git_commit": candidate, "shipping_input_identity": identity, "candidate_shipping_input_identity": identity, "source_identity_matches_candidate": True, "artifact_tuple_matches_candidate": True, "candidate_build_current": True, "candidate_is_current": True})
    manifest.update({"gitCommit": head, "repositoryHead": head, "candidateGitCommit": candidate, "shippingInputIdentity": identity, "candidateShippingInputIdentity": identity, "shippingModeContract": mode})
    candidate_record.update({"candidateCommit": candidate, "candidateShippingInputIdentity": identity, "shippingInputIdentity": identity, "candidateShippingInputs": rows, "candidateShippingModeContract": mode, "shippingModeContract": mode})
    release = {"schemaVersion": 2, "devfleetVersion": "1.2.13", "installerVersion": "1.4.1", "releaseFingerprintId": state["releaseFingerprintId"], "toolingFingerprint": {"toolingFingerprintId": state["toolingFingerprintId"]}, "shippingModeContract": mode, "shippingInputs": rows, "artifacts": list(manifest["artifacts"])}
    release["releaseFingerprintId"] = _MODULE._release_id(release)
    state["releaseFingerprintId"] = release["releaseFingerprintId"]
    manifest["releaseFingerprintId"] = release["releaseFingerprintId"]
    candidate_record["releaseFingerprintId"] = release["releaseFingerprintId"]
    (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (root / "outputs/final-artifact-hashes.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "CURRENT-CANDIDATE.json").write_text(json.dumps(candidate_record), encoding="utf-8")
    (root / "outputs/release-fingerprint.json").write_text(json.dumps(release), encoding="utf-8")
    manifest["sourceInventory"] = [{"path": f"{row['root']}/{row['path']}", "bytes": row["bytes"], "sha256": row["sha256"], "mode": row["mode"]} for row in rows]
    manifest["expectedSourceCount"] = len(rows)
    # Keep the staged inventory in AUDIT-MANIFEST separate from the artifact
    # manifest, as the real bundle does.
    (root / "AUDIT-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
    return root


def test_coherent_bundle_passes(tmp_path: Path):
    assert validate_root(_fixture(tmp_path))["status"] == "PASS"


def test_split_identity_equal_head_passes(tmp_path: Path):
    assert validate_root(_split_identity_fixture(tmp_path))["status"] == "PASS"


def test_split_identity_tooling_only_head_advance_passes(tmp_path: Path):
    assert validate_root(_split_identity_fixture(tmp_path, differing_head=True))["status"] == "PASS"


def test_shipping_inventory_requires_explicit_canonical_mode(tmp_path: Path):
    root = _split_identity