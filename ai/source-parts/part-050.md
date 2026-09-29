# DevFleet source part 050

Full-source UTF-8 byte interval [2278500, 2325000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: cb53e8b3fd467bc35737d6a121b842f849f8c7eb4250c5a63f5191784634823c

<!-- BEGIN SOURCE SLICE -->


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
function Get-DevFleetNestedL2State { param($Session,$ExpectedName) $script:fixture.nestedCalls++;return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;observedUtc='2026-09-24T00:00:00Z';verification='controlled missing or incomplete inventory'} }
function Get-FileHash {
    [CmdletBinding()]
    param([string]$LiteralPath,[string]$Algorithm)
    $hash=[Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($LiteralPath))
    [pscustomobject]@{Hash=([Convert]::ToHexString($hash))}
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-terminal-boundary-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $script:fixture = @{vm=[pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';State='Running'};l2Name='DevFleet-E2E-Linux-01';hostL2Queries=0;hostQueryDenied=$false;hostNotFoundNative=$false;hostNotFoundTarget=$null;hostL2Present=$false;startCalls=0;stopCalls=0;remoteCalls=0;nestedCalls=0}
    $script:fixture.hostNotFoundNative=$true
    $script:fixture.hostL2Queries=0
    $hostAbsent=Get-DevFleetHostNameExclusion -Name $script:fixture.l2Name
    Check 'exact Hyper-V missing-name signature means host exclusion only' ([string]$hostAbsent.status -ceq 'ABSENT' -and $hostAbsent.present -eq $false -and [string]$hostAbsent.inventoryScope -ceq 'host Hyper-V exact-name exclusion only' -and $script:fixture.hostL2Queries -eq 1) ("status=$($hostAbsent.status) scope=$($hostAbsent.inventoryScope)")
    $script:fixture.hostQueryDenied=$true
    $deniedClassificationRejected=$false
    try { Get-DevFleetHostNameExclusion -Name $script:fixture.l2Name | Out-Null } catch { $deniedClassificationRejected=$true }
    Check 'denied host inventory is not classified as absent' $deniedClassificationRejected "rejected=$deniedClassificationRejected"
    $script:fixture.hostQueryDenied=$false;$script:fixture.hostNotFoundTarget='DevFleet-E2E-Foreign'
    $wrongTargetRejected=$false
    try { Get-DevFleetHostNameExclusion -Name $script:fixture.l2Name | Out-Null } catch { $wrongTargetRejected=$true }
    Check 'missing-name signature with a different target is rejected' $wrongTargetRejected "rejected=$wrongTargetRejected"
    $script:fixture.hostNotFoundTarget=$null
    $script:fixture.hostQueryDenied=$false;$script:fixture.hostNotFoundNative=$false;$script:fixture.hostL2Present=$true
    $hostPresent=Get-DevFleetHostNameExclusion -Name $script:fixture.l2Name
    Check 'same-name host resource remains a distinct present conflict' ([string]$hostPresent.status -ceq 'PRESENT' -and $hostPresent.present -eq $true -and @($hostPresent.resources).Count -eq 1) ("status=$($hostPresent.status) rows=$(@($hostPresent.resources).Count)")
    $script:fixture.hostL2Present=$false;$script:fixture.hostNotFoundNative=$false
    $writerRun = Join-Path $tempRoot 'writer-run'; New-Item -ItemType Directory -Path $writerRun | Out-Null
    $script:fixture.hostL2Queries=0
    $writerOutput = @(Write-TerminalVmEvidence -Vm $script:fixture.vm -RunDir $writerRun -L2Name $script:fixture.l2Name)
    $written = $writerOutput[-1]
    Check 'terminal evidence writer does not infer nested absence from host lookup' ($null -eq $written.l2.present -and [string]$written.l2.status -eq 'UNVERIFIED' -and $script:fixture.hostL2Queries -eq 0) ("l2="+($written.l2|ConvertTo-Json -Compress -Depth 5)+" hostQueries=$($script:fixture.hostL2Queries)")

    $candidateTuple=[pscustomobject]@{repositoryHead=('a'*40);gitCommit=('b'*40);candidateCommit=('b'*40);shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64)}
    $writerFingerprint=[pscustomobject]@{repositoryHead=$candidateTuple.repositoryHead;gitCommit=$candidateTuple.candidateCommit;shippingInputIdentity=$candidateTuple.shippingInputIdentity;releaseFingerprintId=$candidateTuple.releaseFingerprintId;toolingFingerprintId=$candidateTuple.toolingFingerprintId}
    $script:fixture.vm.State='Off'
    $nestedWriterObservation=[pscustomobject]@{status='ABSENT';expectedName=$script:fixture.l2Name;present=$false;observedUtc='2026-09-24T00:00:01Z';verification='Bounded Multipass JSON inventory inside exact L1';exactMatchCount=0;inventoryCount=0;backendInventories=@()}
    $writerValidRun=Join-Path $tempRoot 'writer-valid-run';New-Item -ItemType Directory -Path $writerValidRun|Out-Null
    $writerValid=Write-TerminalVmEvidence -Vm $script:fixture.vm -RunDir $writerValidRun -L2Name $script:fixture.l2Name -RunId 'writer-valid-run' -NestedL2Observation $nestedWriterObservation -Candidate $writerFingerprint -EvidenceClass 'FullRelease run-bound nested observation'
    Check 'terminal writer preserves complete nested observation and source hash' ([string]$writerValid.l2.status -ceq 'ABSENT' -and $writerValid.l2.present -eq $false -and (Test-Path -LiteralPath (Join-Path $writerValidRun 'nested-l2-terminal-observation.json')) -and -not [string]::IsNullOrWhiteSpace([string]$writerValid.l2.sourceEvidenceSha256)) ("status=$($writerValid.l2.status) runId=$($writerValid.l2.runId) sourceHash=$($writerValid.l2.sourceEvidenceSha256)")
    $hostOnlyObservation=[pscustomobject]@{status='ABSENT';expectedName=$script:fixture.l2Name;present=$false;observedUtc='2026-09-24T00:00:01Z';verification='Get-VM -Name exact returned no VM';exactMatchCount=0;inventoryCount=0;backendInventories=@()}
    $hostOnlyWriterRejected=$false;try{Write-TerminalVmEvidence -Vm $script:fixture.vm -RunDir (Join-Path $tempRoot 'writer-host-only') -L2Name $script:fixture.l2Name -RunId 'writer-host-only' -NestedL2Observation $hostOnlyObservation -Candidate $writerFingerprint -EvidenceClass 'FullRelease run-bound nested observation'|Out-Null}catch{$hostOnlyWriterRejected=$true}
    Check 'terminal writer rejects host-only absence even when passed as nested input' $hostOnlyWriterRejected "rejected=$hostOnlyWriterRejected"

    $script:fixture.vm.State='Running';$script:fixture.startCalls=0;$script:fixture.stopCalls=0;$script:fixture.remoteCalls=0;$script:fixture.nestedCalls=0
    $cleanupRun = Join-Path $tempRoot 'cleanup-running'; New-Item -ItemType Directory -Path $cleanupRun | Out-Null
    $cleanupBlocked=$false
    $cleanupArgs=@{Vm=$script:fixture.vm;Config=([pscustomobject]@{NestedLinux=[pscustomobject]@{Name=$script:fixture.l2Name}});RunId='cleanup-running';RunDir=$cleanupRun}
    if((Get-Command Invoke-FullReleaseCleanup).Parameters.ContainsKey('Fingerprint')){$cleanupArgs.Fingerprint=$candidateTuple}
    try { Invoke-FullReleaseCleanup @cleanupArgs | Out-Null }
    catch { $cleanupBlocked=$true;$cleanupError=$_.Exception.Message }
    Check 'FullRelease cleanup rejects an unverified nested inventory' ($cleanupBlocked -and $script:fixture.nestedCalls -gt 0) ("blocked=$cleanupBlocked nestedCalls=$($script:fixture.nestedCalls) error=$cleanupError")

    $script:fixture.vm.State='Off';$script:fixture.startCalls=0;$script:fixture.stopCalls=0;$script:fixture.nestedCalls=0
    $offRun = Join-Path $tempRoot 'cleanup-off'; New-Item -ItemType Directory -Path $offRun | Out-Null
    $offBlocked=$false
    $offArgs=@{Vm=$script:fixture.vm;Config=([pscustomobject]@{NestedLinux=[pscustomobject]@{Name=$script:fixture.l2Name}});RunId='cleanup-off';RunDir=$offRun}
    if((Get-Command Invoke-FullReleaseCleanup).Parameters.ContainsKey('Fingerprint')){$offArgs.Fingerprint=$candidateTuple}
    try { Invoke-FullReleaseCleanup @offArgs | Out-Null }
    catch { $offBlocked=$true;$offError=$_.Exception.Message }
    Check 'FullRelease cleanup does not restart an already-Off L1 to refresh metadata' ($offBlocked -and $script:fixture.startCalls -eq 0) ("blocked=$offBlocked starts=$($script:fixture.startCalls) error=$offError")

    $postRun = Join-Path $tempRoot 'audit/automation-harness/runs/post-run'; New-Item -ItemType Directory -Path $postRun -Force | Out-Null
    $cleanup = [ordered]@{status='PASS';runId='post-run';candidate=$candidateTuple;l1=[ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';state='Off';deleted=$false};guest=[ordered]@{runRootAbsent=$true;nestedAbsent=$true;foreignResourcesMutated=$false}}
    $l1 = [ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';state='Off';timestampUtc='2026-09-24T00:00:02Z';runId='post-run';ownershipScope='exact disposable'}
    $nested=[ordered]@{schemaVersion=1;runId='post-run';status='ABSENT';expectedName=$script:fixture.l2Name;present=$false;observedUtc='2026-09-24T00:00:01Z';verification='Bounded Multipass JSON inventory inside exact L1';exactMatchCount=0;inventoryCount=0;backendInventories=@();candidate=$candidateTuple;l1=[ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2'};nestedScope='inside the exact L1 guest session';observer='Get-DevFleetNestedL2State';evidenceClass='FullRelease run-bound nested observation'}
    $nestedPath=Join-Path $postRun 'nested-l2-terminal-observation.json';Write-EvidenceJson -Path $nestedPath -Value $nested;$nestedHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $l2=[ordered]@{schemaVersion=2;expectedName=$script:fixture.l2Name;status='ABSENT';present=$false;timestampUtc=$nested.observedUtc;verificationMethod=$nested.verification;nestedScope=$nested.nestedScope;backendInventories=@();runId='post-run';sourceRunId='post-run';sourceEvidence='nested-l2-terminal-observation.json';sourceEvidenceSha256=$nestedHash;l1Name='DevFleet-E2E-Win11-01';l1Id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';candidate=$candidateTuple;evidenceClass='FullRelease run-bound nested observation'}
    Write-EvidenceJson -Path (Join-Path $postRun 'final-cleanup.json') -Value $cleanup
    Write-EvidenceJson -Path (Join-Path $postRun 'l1-terminal-state.json') -Value $l1
    $l2Path=Join-Path $postRun 'l2-terminal-state.json'
    $hostOnlyNested=[ordered]@{schemaVersion=1;runId='post-run';status='ABSENT';expectedName=$script:fixture.l2Name;present=$false;observedUtc='2026-09-24T00:00:01Z';verification='Get-VM -Name exact returned no VM';exactMatchCount=0;inventoryCount=0;backendInventories=@();candidate=$candidateTuple;l1=[ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2'};nestedScope='inside the exact L1 guest session';observer='Get-DevFleetNestedL2State';evidenceClass='FullRelease run-bound nested observation'}
    Write-EvidenceJson -Path $nestedPath -Value $hostOnlyNested;$hostOnlyHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $hostOnlyL2=[ordered]@{};foreach($key in $l2.Keys){$hostOnlyL2[$key]=$l2[$key]};$hostOnlyL2.verificationMethod=$hostOnlyNested.verification;$hostOnlyL2.sourceEvidenceSha256=$hostOnlyHash
    Write-EvidenceJson -Path $l2Path -Value $hostOnlyL2
    $script:fixture.hostL2Queries=0;$script:fixture.hostL2Present=$false;$script:fixture.hostQueryDenied=$false
    $postRejected=$false
    $postState=[pscustomobject]@{runId='post-run';candidateHashes=$candidateTuple}
    $postArgs=@{State=$postState;Vm=([pscustomobject]@{Name=$l1.name;Id=[guid]$l1.id;State='Off'});Config=([pscustomobject]@{NestedLinux=[pscustomobject]@{Name=$script:fixture.l2Name}});RunDir=$postRun;Records=@([pscustomobject]@{id='CLEANUP';status='PASS';evidence=@{status='PASS'}})}
    if((Get-Command Write-PostCleanupFinalization).Parameters.ContainsKey('WorkspaceRoot')){$postArgs.WorkspaceRoot=$tempRoot}
    try { Write-PostCleanupFinalization @postArgs | Out-Null }
    catch { $postRejected=$true;$postError=$_.Exception.Message }
    Check 'post-cleanup finalizer rejects host-only L2 absence evidence' ($postRejected -and $postError -match 'unsupported inventory method' -and $script:fixture.hostL2Queries -eq 0) ("rejected=$postRejected hostQueries=$($script:fixture.hostL2Queries) error=$postError")

    Write-EvidenceJson -Path $nestedPath -Value $nested;$validNestedHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant();$l2.sourceEvidenceSha256=$validNestedHash
    Write-EvidenceJson -Path $l2Path -Value $l2
    $script:fixture.hostL2Queries=0;$script:fixture.hostQueryDenied=$true
    $hostDeniedRejected=$false
    try { Write-PostCleanupFinalization @postArgs | Out-Null }
    catch { $hostDeniedRejected=$true;$hostDeniedError=$_.Exception.Message }
    Check 'post-cleanup host conflict check fails closed on access denial' ($hostDeniedRejected -and $script:fixture.hostL2Queries -eq 1) ("rejected=$hostDeniedRejected hostQueries=$($script:fixture.hostL2Queries) error=$hostDeniedError")

    $script:fixture.hostL2Queries=0;$script:fixture.hostQueryDenied=$false;$script:fixture.hostNotFoundNative=$true
    $hostAbsentPost=$null;$hostAbsentPostError=$null
    try { $hostAbsentPost=Write-PostCleanupFinalization @postArgs } catch { $hostAbsentPostError=$_.Exception.Message }
    Check 'post-cleanup accepts exact host absence while retaining nested proof requirement' ($hostAbsentPost -and [string]$hostAbsentPost.status -ceq 'PASS' -and $hostAbsentPost.liveChecks.hostSameNameL2Absent -eq $true -and $hostAbsentPost.liveChecks.l2ExactAbsent -eq $true -and $script:fixture.hostL2Queries -eq 1) ("status=$($hostAbsentPost.status) hostQueries=$($script:fixture.hostL2Queries) error=$hostAbsentPostError")

    $script:fixture.hostL2Queries=0;$script:fixture.hostNotFoundNative=$false;$script:fixture.hostL2Present=$true
    $hostConflictPostRejected=$false
    try { Write-PostCleanupFinalization @postArgs | Out-Null } catch { $hostConflictPostRejected=$true }
    Check 'post-cleanup preserves same-name host resource and blocks promotion' ($hostConflictPostRejected -and $script:fixture.hostL2Queries -eq 1) "rejected=$hostConflictPostRejected"

    $script:fixture.hostL2Queries=0;$script:fixture.hostL2Present=$false;$script:fixture.hostNotFoundNative=$true;$script:fixture.hostQueryDenied=$false
    $nested.verification='Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend'
    $nested.inventoryCount=2
    $nested.backendInventories=@([ordered]@{provider='Hyper-V';status='PASS';names=@('foreign-instance','foreign-instance');verification='bounded Hyper-V inventory'},[ordered]@{provider='VirtualBox';status='PASS';names=@();verification='bounded VirtualBox inventory'})
    Write-EvidenceJson -Path $nestedPath -Value $nested;$nestedHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $l2.verificationMethod=$nested.verification;$l2.backendInventories=$nested.backendInventories;$l2.sourceEvidenceSha256=$nestedHash
    Write-EvidenceJson -Path $l2Path -Value $l2
    $malformedBackendPostRejected=$false
    try { Write-PostCleanupFinalization @postArgs | Out-Null } catch { $malformedBackendPostRejected=$true;$malformedBackendPostError=$_.Exception.Message }
    Check 'post-cleanup consumer rejects duplicate nested backend instance names' ($malformedBackendPostRejected -and $malformedBackendPostError -match 'duplicate instance name') "rejected=$malformedBackendPostRejected error=$malformedBackendPostError"

    $nested.verification='Bounded Multipass JSON inventory inside exact L1';$nested.inventoryCount=0;$nested.backendInventories=@();$nested.candidate=[ordered]@{}
    $l2.verificationMethod=$nested.verification;$l2.backendInventories=@();$l2.candidate=[ordered]@{}
    $cleanup.candidate=[ordered]@{};$postArgs.State.candidateHashes=[ordered]@{}
    Write-EvidenceJson -Path $nestedPath -Value $nested;$nestedHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $l2.sourceEvidenceSha256=$nestedHash;Write-EvidenceJson -Path $l2Path -Value $l2
    Write-EvidenceJson -Path (Join-Path $postRun 'final-cleanup.json') -Value $cleanup
    $emptyTuplePostRejected=$false
    try { Write-PostCleanupFinalization @postArgs | Out-Null } catch { $emptyTuplePostRejected=$true;$emptyTuplePostError=$_.Exception.Message }
    Check 'post-cleanup consumer rejects a missing candidate tuple' ($emptyTuplePostRejected -and $emptyTuplePostError -match 'candidate tuple is malformed or incomplete') "rejected=$emptyTuplePostRejected error=$emptyTuplePostError"
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

$failed = @($checks | Where-Object { -not $_.pass })
[ordered]@{scope='VM_FREE_PRODUCTION_TERMINAL_BOUNDARY_REGRESSION';certificationCredit=$false;status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;checks=@($checks);productionSources=@('Cleanup.psm1::Write-TerminalVmEvidence','Cleanup.psm1::Get-DevFleetHostNameExclusion','FullRelease.psm1::Invoke-FullReleaseCleanup','FullRelease.psm1::Write-PostCleanupFinalization')} | ConvertTo-Json -Depth 8
if ($failed.Count) { exit 1 }

```


## FILE: automation/release-e2e/tests/Test-ToolRuntimeResolution.ps1

SHA256: e5829ce5758969d6a5251f41f3c2005181b4955e438e18cef868229f0e9f0ed5 | Bytes: 902 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
Import-Module (Join-Path $WorkspaceRoot 'tools\PythonRuntime.psm1') -Force
$python = Resolve-DevFleetPython -Workspace $WorkspaceRoot
$version = @(& $python --version 2>&1)
$insideWorkspace = [IO.Path]::GetFullPath($python).StartsWith(([IO.Path]::GetFullPath($WorkspaceRoot) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)
$status = if($LASTEXITCODE -eq 0 -and ($version -join ' ') -match '^Python 3\.' -and (Test-Path -LiteralPath $python -PathType Leaf) -and $insideWorkspace){'PASS'}else{'FAIL'}
[pscustomobject]@{status=$status;runtime=[IO.Path]::GetFileName($python);version=($version -join ' ');repositoryLocal=$insideWorkspace}|ConvertTo-Json -Depth 4
if($status -ne 'PASS'){exit 1}

```


## FILE: automation/release-e2e/tests/Test-WpfLaunchBoundaryBehavior.ps1

SHA256: 77560263503899607a2157a4905704dcaf7713095af2887ca7358cecf5f44e9a | Bytes: 41033 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }

$modulePath = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\WpfLaunchContract.psm1'
$driverPath = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-WpfUiAutomation.ps1'
$passed = 0
$failures = [System.Collections.Generic.List[string]]::new()
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("devfleet-wpf-boundary-test-{0}" -f [guid]::NewGuid().ToString('N'))

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Import-Module $modulePath -Force

    $driverTokens = $null
    $driverParseErrors = $null
    $driverAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $driverPath).Path,
        [ref]$driverTokens,
        [ref]$driverParseErrors
    )
    $readObservedAst = $driverAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'Read-ObservedJsonFile'
    }, $true)
    Check (@($driverParseErrors).Count -eq 0 -and $null -ne $readObservedAst) 'WPF driver observation helper remains parseable and discoverable'
    if ($null -ne $readObservedAst) {
        $readObservedText = [string]$readObservedAst.Extent.Text
        $inaccessibleObservation = & {
            function Test-Path { throw [System.UnauthorizedAccessException]::new('Access is denied') }
            Invoke-Expression $readObservedText
            Read-ObservedJsonFile -Path 'C:\blocked-observation' -Kind TERMINAL
        }
        Check ($null -eq $inaccessibleObservation) 'inaccessible observation files are treated as absent so the bounded WPF watchdog can retry'
        $observedJsonPath=Join-Path $scratch 'observed-terminal.json'
        [IO.File]::WriteAllText($observedJsonPath,'{"status":"PASS"}'+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
        $observedWithoutContentProvider=& {
            function Get-Content { throw [InvalidOperationException]::new('Get-Content must not own atomic WPF observation reads') }
            Invoke-Expression $readObservedText
            Read-ObservedJsonFile -Path $observedJsonPath -Kind TERMINAL
        }
        Check ([string]$observedWithoutContentProvider.value.status -ceq 'PASS') 'atomic WPF terminal/progress observation reads do not depend on the stalled PowerShell content provider'
    }

    $readBootstrapAst = $driverAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'Read-BootstrapLaunchSpecification'
    }, $true)
    Check ($null -ne $readBootstrapAst) 'WPF bootstrap request reader remains parseable and discoverable'
    if ($null -ne $readBootstrapAst) {
        $readBootstrapText = [string]$readBootstrapAst.Extent.Text
        $bootstrapRequestPath = Join-Path $scratch 'bootstrap-read-request.json'
        [IO.File]::WriteAllText($bootstrapRequestPath, '{"candidateSha256":"' + ('a' * 64) + '"}' + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        $bootstrapRead = & {
            function Get-Content { throw [InvalidOperationException]::new('Get-Content must not be used for task-context bootstrap reads') }
            Invoke-Expression $readBootstrapText
            Read-BootstrapLaunchSpecification -Path $bootstrapRequestPath -DeadlineUtc ([DateTime]::UtcNow.AddMinutes(1).ToString('o'))
        }
        Check ([string]$bootstrapRead.candidateSha256 -ceq ('a' * 64)) 'task-context bootstrap request reader uses bounded .NET file I/O rather than the hanging PowerShell content provider'
        $absentRequestFailure='';try{& {Invoke-Expression $readBootstrapText;Read-BootstrapLaunchSpecification -Path (Join-Path $scratch 'absent-request.json') -DeadlineUtc ([DateTimeOffset]::UtcNow.AddMilliseconds(900).ToString('o'))}|Out-Null}catch{$absentRequestFailure=$_.Exception.Message}
        Check ($absentRequestFailure -match 'did not become visible before the bounded bootstrap deadline') 'absent launch request fails within its inherited bootstrap deadline'
        $corruptRequestPath=Join-Path $scratch 'corrupt-request.json';[IO.File]::WriteAllText($corruptRequestPath,'{"schemaVersion":',[Text.UTF8Encoding]::new($false))
        $corruptRequestFailure='';try{& {Invoke-Expression $readBootstrapText;Read-BootstrapLaunchSpecification -Path $corruptRequestPath -DeadlineUtc ([DateTimeOffset]::UtcNow.AddSeconds(2).ToString('o'))}|Out-Null}catch{$corruptRequestFailure=$_.Exception.Message}
        Check ($corruptRequestFailure -match 'was not readable before the bounded bootstrap deadline') 'corrupt launch request fails within its inherited bootstrap deadline'
    }

    foreach($role in @('Primary / Desktop','Laptop / Surrogate')){
        foreach($mode in @('initial','direct','resume')){
            $arguments=Get-WpfCandidateArguments -LaunchMode $mode -Action FreshInstall -Role $role -ElevatedResume:($mode-eq'resume')
            Check (($arguments-contains'--defer-network-pairing')-eq($role-eq'Primary / Desktop')) "$role $mode honors supported network-pairing choice"
            Check ($arguments[$arguments.IndexOf('--role')+1]-ceq$role) "$role $mode preserves exact reviewed role"
        }
    }

    $now = [datetime]'2026-09-05T20:00:00Z'
    $ownerDeadline = $now.AddSeconds(480)
    $common = @{
        DriverPath = $driverPath
        ExePath = (Get-Command powershell.exe).Source
        Action = 'FreshInstall'
        Role = 'Primary / Desktop'
        OutputPath = (Join-Path $scratch 'final.json')
        StartedPath = (Join-Path $scratch 'started.json')
        CheckpointPath = (Join-Path $scratch 'checkpoint.json')
        WorkerResultPath = (Join-Path $scratch 'worker.json')
        LaunchRequestPath = (Join-Path $scratch 'request.json')
        RunId = 'wpf-boundary-regression'
        LaunchId = ('1' * 32)
        TransactionId = ('2' * 32)
        PayloadSha256 = ('3' * 64)
        ExpectedInteractiveSessionId = 1
        AllowMutation = $true
        AllowRebootRequired = $true
        OwnerDeadlineUtc = $ownerDeadline
        ClockProvider = { $now }
    }

    $resume = New-WpfLaunchSpecification @common -LaunchMode resume -ElevatedResume
    Check ($resume.taskArguments -match '(?:^| )-ElevatedResume(?: |$)' -and $resume.taskArguments -match '-LaunchMode (?:"resume"|resume)') 'resume mode reaches the actual driver task arguments'
    Check (@($resume.candidateArguments)[0] -eq '--elevated-resume') 'resume mode reaches the actual candidate argument vector'
    Check ([datetime]$resume.boundaryDeadlineUtc -eq $ownerDeadline -and [datetime]$resume.driverDeadlineUtc -lt $ownerDeadline) 'child and terminalization deadlines consume the finite remaining owner budget'
    $actualBinding=@{ExePath=$resume.exePath;Action=$resume.action;Role=$resume.role;OutputPath=$resume.outputPath;StartedPath=$resume.startedPath;CheckpointPath=$resume.checkpointPath;WorkerResultPath=$resume.workerResultPath;LaunchRequestPath=$resume.launchRequestPath;RunId=$resume.runId;LaunchId=$resume.launchId;TransactionId=$resume.transactionId;PayloadSha256=$resume.payloadSha256;LaunchMode=$resume.launchMode;ObserverDeadlineUtc=$resume.driverDeadlineUtc;ExpectedInterac