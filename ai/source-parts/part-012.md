# DevFleet source part 012

Full-source UTF-8 byte interval [511500, 558000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 0a55a823fe88a9fd8a21f4068069beec987b14f3708305fddef2595c164f98e2

<!-- BEGIN SOURCE SLICE -->
{
            [IO.File]::WriteAllText($tmp,(($finalCurrent|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $tmp -Destination $finalPath -Force
        } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        & (Join-Path $WorkspaceRoot 'tools\Update-CurrentReleaseAuthority.ps1') -Workspace $WorkspaceRoot -FullReleaseRunId $runId | Out-Null
        Show-Result 'FullRelease' 'PASS' 'all configured real product phases completed with durable evidence'
        return
    } catch {
        $primaryFailure=$_
        $failureCleanupRecord=[ordered]@{schemaVersion=1;runId=$runId;status='NOT_RUN';scope='failure-handler-only';certifiedReleaseCleanup=$false;primaryFailurePreserved=$true;boundary='policy';startedAt=(Get-Date).ToUniversalTime().ToString('o')}
        if (-not $KeepLab -and $vm) {
            try {
                $failureCleanupRecord.boundary='manifest'
                $failureCleanup=New-CleanupManifest -Vm $vm -RunId $runId
                $failureCleanupRecord.boundary='exact-identity'
                $failureVm=Get-AssertedDisposableVm -ExpectedVm $vm
                $durable=$false
                if([string]$failureVm.State -eq 'Off'){$durable=$true}else{
                    $failureCleanupRecord.boundary='interactive-logon'
                    $failureLogon=Clear-DevFleetE2EInteractiveLogonState -VmId ([guid][string]$vm.Id)
                    $durable=([string]$failureLogon.status -eq 'PASS' -and [bool]$failureLogon.registryCleanupPersisted -and [bool]$failureLogon.temporaryDefaultPasswordRemovalPersisted -and -not [bool]$failureLogon.ordinaryDefaultPasswordPresent)
                }
                if(-not $durable){throw 'FullRelease failure cleanup did not establish durable interactive-login cleanup.'}
                $failureCleanupRecord.boundary='stop-exact-vm'
                Stop-ManifestVm -Manifest $failureCleanup
                $failureCleanupRecord.boundary='terminal-evidence'
                Write-TerminalVmEvidence -Vm $vm -RunDir $runDir -L2Name ([string]$config.NestedLinux.Name) | Out-Null
                $failureCleanupRecord.status='COMPLETED'
            } catch {
                $failureCleanupRecord.status='FAIL'
                # Exception messages can contain guest credentials; retain the typed boundary only.
                $failureCleanupRecord.errorType=$_.Exception.GetType().FullName
                Write-Warning "Failure cleanup did not complete at $($failureCleanupRecord.boundary); the primary FullRelease failure is preserved."
            }
        }
        $failureCleanupRecord.completedAt=(Get-Date).ToUniversalTime().ToString('o')
        try { Write-EvidenceJson -Path (Join-Path $runDir 'failure-cleanup.json') -Value $failureCleanupRecord }
        catch { Write-Warning 'Could not persist failure-cleanup evidence; the primary FullRelease failure is preserved.' }
        try { & (Join-Path $WorkspaceRoot 'tools\Update-CurrentReleaseAuthority.ps1') -Workspace $WorkspaceRoot -FullReleaseRunId $runId | Out-Null }
        catch { Write-Warning 'Could not refresh failed FullRelease authority; the primary failure is preserved.' }
        Show-Result 'FullRelease' 'BLOCKED' $primaryFailure.Exception.Message
        throw $primaryFailure
    }
}

if ($Mode -eq 'Closeout') {
    $finalStatePath=Join-Path $WorkspaceRoot 'finalization-state.json'
    $finalState=Read-StrictJson -Path $finalStatePath
    $tailStatus=$null; $guestState=$null; $session=$null
    try {
        $session=Connect-DevFleetGuest -VmId $vm.Id
        $guestState=Get-InteractiveGuestState -Session $session
        $tailStatus=Get-TailscaleGuestStatus -Session $session -ExpectedNodePattern ([string]$config.Tailscale.ExpectedGuestNodePattern)
    } catch { $tailStatus=[pscustomobject]@{status='UNVERIFIED';error=$_.Exception.Message;credentialsStoredInEvidence=$false} }
    finally { if($session){Remove-PSSession $session} }
    $cleanupManifest=New-CleanupManifest -Vm $vm -RunId $runId
    $cleanupPath=Join-Path $runDir 'cleanup-manifest.json'; Write-EvidenceJson -Path $cleanupPath -Value $cleanupManifest
    $tailGate = 'FAIL'
    if($tailStatus -and (Test-TailscaleConnected $tailStatus)) { $tailGate = 'REAL E2E PASS' }
    $cleanupGate = 'FAIL'
    if(Test-CleanupManifest $cleanupManifest) { $cleanupGate = 'UNIT/INTEGRATION TESTED' }
    $gateRecords=@(
        (Gate 'candidate' 'REAL E2E PASS' $fingerprint.candidate.sha256),
        (Gate 'accepted-final-state' 'REAL E2E PASS' ([string]$finalState.status)),
        (Gate 'tailscale-connected-state' $tailGate 'read-only guest status plus bounded WPF state was independently verified'),
        (Gate 'cleanup-manifest' $cleanupGate 'exact disposable VM identity; production deny list; no fuzzy deletion')
    )
    $closeout=[ordered]@{status=if(@($gateRecords|Where-Object status -eq 'FAIL').Count -eq 0){'PASS'}else{'FAIL'};candidate=$fingerprint;acceptedGates=$finalState.gates;guest=$guestState;tailscale=$tailStatus;gates=$gateRecords;cleanupManifest=$cleanupPath;destructiveActionsPerformed=$false}
    Write-EvidenceJson -Path (Join-Path $runDir 'closeout.json') -Value $closeout
    $state.currentPhase='Closeout'; $state.completedPhases=@($state.completedPhases)+@('Closeout'); $state.cleanupManifestPath=$cleanupPath; $state.finalStatus=$closeout.status; Save-State $state $statePath
    Show-Result 'Closeout smoke' $closeout.status 'current candidate, accepted evidence, Tailscale state, and cleanup safety verified'
}
} catch {
    $script:DevFleetFinalConvergencePrimaryBlocker = $_.Exception.Message
    throw
} finally {
    # Every controlled entrypoint outcome, including early HOST-SAFETY and
    # FullRelease failures, goes through the same fail-safe audit finalizer.
    $finalizerFailure=$null
    try {
        $finalizer = Join-Path $WorkspaceRoot 'tools\Invoke-DevFleetFinalConvergence.ps1'
        $finalizerArgs = @('-Workspace',$WorkspaceRoot,'-RunId',$runId,'-RunDirectory',$runDir)
        if ($script:DevFleetFinalConvergencePrimaryBlocker) {
            $finalizerArgs += @('-PrimaryBlocker',$script:DevFleetFinalConvergencePrimaryBlocker,'-PrimaryBlockerClassification','BLOCKED — RELEASE HARNESS / PLATFORM')
        }
        Invoke-RequiredReleaseFinalizer -PowerShellPath (Get-Command pwsh.exe -ErrorAction Stop).Source -FinalizerPath $finalizer -ArgumentList $finalizerArgs | Write-Output
    } catch {
        $finalizerFailure=$_.Exception.Message
    }
    if($finalizerFailure){
        if($script:DevFleetFinalConvergencePrimaryBlocker){Write-Warning "Mandatory finalizer invocation failed after the primary release failure; original blocker remains primary. Finalizer: $finalizerFailure"}
        else{throw "Mandatory finalizer invocation failed: $finalizerFailure"}
    }
}

```


## FILE: automation/release-e2e/Invoke-FocusedMaintenanceSentinels.ps1

SHA256: 3ddd160b47a2c2e25b86f42f6b280fed370ab78261730e113b5194f5bdff2227 | Bytes: 4953 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$Candidate,
    [string]$ConfigPath,
    [string]$RunId,
    [switch]$AllowRamPressure
)
$ErrorActionPreference='Stop'
$scriptRoot=$PSScriptRoot
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $scriptRoot '..\..')).Path}else{$WorkspaceRoot=(Resolve-Path $WorkspaceRoot).Path}
if(-not $ConfigPath){$ConfigPath=Join-Path $scriptRoot 'config\devfleet-e2e.defaults.json'}
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
foreach($m in @('Candidate','HostSafety','ResumeState','Evidence','Cleanup','GuestSession','FullRelease')){Import-Module (Join-Path $scriptRoot "modules\$m.psm1") -Force}
$script:evidenceModulePath=Join-Path $scriptRoot 'modules\Evidence.psm1'
# The product lifecycle imports modules in nested scopes and can unload the
# repository module by name. Rebind it by full path for every wrapper write.
function Write-FocusedMaintenanceEvidence {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Value)
    $module=Import-Module $script:evidenceModulePath -Force -PassThru
    $command=$module.ExportedCommands['Write-EvidenceJson']
    if(-not $command){throw 'Focused maintenance evidence writer export is unavailable.'}
    & $command -Path $Path -Value $Value
}
$fingerprint=Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath $Candidate
$runId=if($RunId){$RunId}else{"focused-maintenance-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))-$([guid]::NewGuid().ToString('N').Substring(0,8))"}
$runDir=New-RunEvidenceDirectory -WorkspaceRoot $WorkspaceRoot -RunId $runId
$vm=$null;$evidence=[ordered]@{status='BLOCKED';runId=$runId;phase='MAINTENANCE-READY/WINDOWS-SENTINELS';candidate=$fingerprint;runDir=$runDir;cleanup=$null}
try{
    $vm=Get-DisposableVm -Pattern ([string]$config.DisposableVmNamePattern);Assert-DisposableOwnership -Vm $vm|Out-Null
    $hostSafety=Apply-RamPressureOverride -Snapshot (Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB ([double]$config.ExpectedVmStartCostGiB)) -AllowRamPressure:$AllowRamPressure
    Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'focused-host-safety.json') -Value $hostSafety
    if(-not[bool]$hostSafety.effectiveE2EStartAuthorized){throw 'USER ACTION REQUIRED — fresh HOST-SAFETY startSafe=false.'}
    $fixture=Ensure-MaintenanceReadyFixture -Vm $vm -Fingerprint $fingerprint -Config $config -WorkspaceRoot $WorkspaceRoot -RunId $runId -RunDir $runDir
    Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'maintenance-ready-provenance-evidence.json') -Value $fixture
    $restored=Restore-MaintenanceReadyCheckpoint -Vm $vm -Fingerprint $fingerprint -WorkspaceRoot $WorkspaceRoot
    $context=[ordered]@{runId=$runId;phaseId='WINDOWS-SENTINELS';label='WINDOWS FOREIGN SENTINELS';checkpoint='DevFleet-E2E-MAINTENANCE-READY';destructive=$true;candidate=$fingerprint;vmName=$vm.Name;vmId=$vm.Id.ToString();runDir=$runDir;config=$config}
    $executor=Get-ExecutorPath -Config $config -PhaseId 'WINDOWS-SENTINELS' -WorkspaceRoot $WorkspaceRoot
    if(-not $executor){throw 'WINDOWS-SENTINELS executor is not configured.'}
    $sentinelEvidence=Invoke-ConfiguredExecutor -Path $executor -Context ([pscustomobject]$context)
    if([string]$sentinelEvidence.status -notin @('PASS','REAL E2E PASS') -or [string]$sentinelEvidence.sentinels.status -ne 'PASS' -or -not[bool]$sentinelEvidence.sentinels.unchanged){throw 'WINDOWS-SENTINELS did not prove foreign resources survived.'}
    Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'windows-sentinels-focused-evidence.json') -Value ([ordered]@{status='PASS';runId=$runId;hostSafety=$hostSafety;fixture=$fixture;independentRestore=$restored;windowsSentinels=$sentinelEvidence;foreignResourcesMutated=$false})
    $evidence.status='PASS';$evidence.hostSafety=$hostSafety;$evidence.fixture=$fixture;$evidence.independentRestore=$restored;$evidence.windowsSentinels=$sentinelEvidence;$evidence.foreignResourcesMutated=$false
}catch{
    $evidence.error=$_.Exception.Message
    Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'focused-maintenance-error.json') -Value $evidence
    throw
}finally{
    if($vm){
        try{$manifest=New-CleanupManifest -Vm $vm -RunId $runId;Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'cleanup-manifest.json') -Value $manifest;Stop-ManifestVm -Manifest $manifest;$final=Get-AssertedDisposableVm -ExpectedVm $vm;$evidence.cleanup=[ordered]@{manifest=(Join-Path $runDir 'cleanup-manifest.json');l1Name=$final.Name;l1Id=$final.Id.ToString();l1State=[string]$final.State;runOwnedOnly=$true};Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'focused-maintenance-final.json') -Value $evidence}catch{$evidence.cleanupError=$_.Exception.Message;Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'focused-maintenance-final.json') -Value $evidence}}
}
$evidence|ConvertTo-Json -Depth 32

```


## FILE: automation/release-e2e/README.md

SHA256: 7a8b6b433154a7fe0cc8c1bdac810d887e4a786c35c6bbda0398d9e84aa1b232 | Bytes: 5414 | Git mode: 100644

````
# DevFleet E2E Automation Harness

Version: 1.5.0
Profile: local/free, disposable-only, non-shipping release tooling

The entry point is `Invoke-DevFleetReleaseE2E.ps1`. It discovers the candidate and its
associated release artifacts, hashes them, runs the unsigned self-test before expensive
work, records a durable atomic run state, and refuses ambiguous VM ownership.

## Prerequisites

PowerShell 7, Hyper-V PowerShell, a positively identified `DevFleet-E2E-*` VM, an
appropriate clean checkpoint, and enough free host RAM for the configured fixed-memory
guest. The default preference is 20 GiB available before starting a fixed 16 GiB L1.
Production VMs are read-only observations and are never cleanup targets.

The mandatory Windows/release Python lane must set
`DEVFLEET_REQUIRE_PWSH_TESTS=1`. On general cross-platform lanes, migration tests
report `SKIP — platform prerequisite` when `pwsh` is absent; the mandatory lane
instead blocks during collection and cannot silently convert required coverage into
a skip.

Initialize the local DPAPI-bound disposable credential store once:

```powershell
.\Initialize-DevFleetE2ESecrets.ps1
```

The store is under the user's local application data, never in this workspace. A one-time
migration from an existing disposable credential file is supported with
`-CredentialFile`; the file is not copied into evidence.

## Modes

```powershell
.\Invoke-DevFleetReleaseE2E.ps1 -Mode PlanOnly -Candidate <path-to-installer>
.\Invoke-DevFleetReleaseE2E.ps1 -Mode Preflight -Candidate <path-to-installer>
.\Invoke-DevFleetReleaseE2E.ps1 -Mode Quick -Candidate <path-to-installer>
.\Invoke-DevFleetReleaseE2E.ps1 -Mode Closeout -Candidate <path-to-installer>
.\Invoke-DevFleetReleaseE2E.ps1 -Mode Resume -RunStatePath <run-state.json>
.\Invoke-DevFleetReleaseE2E.ps1 -Mode FullRelease
```

`PlanOnly` is non-mutating. `Preflight`, `Quick`, and `Closeout` are read-only/smoke
operations. `Resume` verifies candidate and recorded disposable identity before it
continues. `FullRelease` is guarded by `-ConfirmDisposableLab -ExecuteExpensive` and
executes the ordered durable phase plan from exact disposable checkpoints. It performs
host/candidate verification, clean restore, guest-session establishment, then invokes
only explicitly configured real product executors for the dependency, install,
maintenance, destructive, recovery, ownership, Vault, Tailscale, AI-bundle, and
reconciliation phases. Each executor stages and hashes the exact candidate, drives the
real product/UI or guest lifecycle for its phase, and returns structured independent
evidence. Missing or incomplete action evidence fails closed; a candidate self-test or
script exit code is never
promoted to PASS merely because a scenario group was recorded.

Tailscale supports Deferred (no authentication during the install stage) and the
production `OAuthClientSecretStore` path used by the Tailscale authentication phase.
Disposable E2E enrollment is preauthorized, tagged `tag:devfleet-e2e`, and ephemeral;
persistent fixtures use `tag:devfleet` and non-ephemeral semantics. The provider uses
the installed client's file-backed `--client-secret=file:<path>` input, one bounded
enrollment attempt, and structured readiness: service, backend/auth/online, expected
identity/tag/IP/health, expected peer, and the configured DevFleet endpoint.

`AuthKeyEnvironment` remains an explicit degraded `AUTH_KEY_FALLBACK`, with the same
protected storage, redaction, file cleanup, and finite-deadline rules. Browser/device
login is emergency/manual recovery only. One-time auth URLs, OAuth secrets, auth keys,
passwords, tokens, and cookies are never placed in durable evidence.

## Evidence and cleanup

Each run is written under `audit/automation-harness/runs/<RunId>/` with artifact hashes,
host safety, run state, gate records, and a cleanup manifest. Cleanup requires exact VM
identity plus the `DevFleet-E2E-*` boundary. Unknown or production-named resources fail
closed. A passed release may power down the disposable L1; a failure can retain the
checkpoint and evidence for diagnosis.

The current development candidate uses this harness for static tests, PlanOnly, Closeout smoke,
and exact-candidate FullRelease evidence. Run:

```powershell
.\Invoke-DevFleetReleaseE2E.ps1 -Mode FullRelease
```

from a clean checkpoint to certify the full dependency, WPF, Primary, maintenance,
stopped-project, and Tailscale scenario groups.

The `LINUX` phase is a real nested path, not a WSL syntax probe. The exact
candidate TAR is hashed on the host, staged into the disposable Windows L1,
transferred into a positively owned Ubuntu 24.04 Multipass L2, and hashed again
before the candidate's `linux/bootstrap-compute.sh` is invoked. The phase verifies
systemd, the DevFleet service, the explicitly selected `devrunner` rootless Docker
socket, control-account access to that socket, container execution, local `/healthz`,
configuration ownership/modes, and OOM absence. The L2 is deleted with
`multipass delete --purge` only after its run marker is positively verified; an
unbound resource is retained and the phase fails closed.

Nested Linux resource sizing is kept in `config/devfleet-e2e.defaults.json`.
Hyper-V nested virtualization is a disposable-lab prerequisite. Multipass and the
Linux bootstrap remain product prerequisites and are exercised through the
candidate's normal installation/bootstrap path.

````


## FILE: automation/release-e2e/Set-DevFleetTailscaleOAuthCredential.ps1

SHA256: ae362cec16bf67643eb8f0f081f8e300f17fcce14d68206ddd99bef018a3eeb2 | Bytes: 645 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$ClientId = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\Secrets.psm1') -Force
if (-not $ClientId) { $ClientId = Read-Host 'Tailscale OAuth client ID (optional; direct client-secret enrollment does not require it)' }
$secret = Read-Host 'Tailscale OAuth client secret' -AsSecureString
try {
    $path = Save-DevFleetTailscaleOAuthCredential -ClientId $ClientId -ClientSecret $secret
    [pscustomobject]@{ status='PASS';provider='OAuthClientSecretStore';path=$path;secretPrinted=$false;secretInEvidence=$false } | ConvertTo-Json -Compress
} finally { $secret=$null }

```


## FILE: automation/release-e2e/config/devfleet-e2e.defaults.json

SHA256: 8c6950ea31bc4e517f4c0ffc31f17ae6244fe9fe94df5646046fb1c6d07095b7 | Bytes: 5246 | Git mode: 100644

```
{
  "schemaVersion": 1,
  "HarnessVersion": "1.5.0",
  "DisposableVmNamePattern": "DevFleet-E2E-*",
  "PreferredVmName": null,
  "ExpectedVmStartCostGiB": 14.38,
  "HostSafetyPolicyVersion": "1.0.0",
  "PostStartSampleSeconds": 60,
  "RunEvidenceRoot": "audit/automation-harness/runs",
  "CredentialStoreRelativePath": "LOCALAPPDATA/DevFleet/E2E/secrets.json",
  "ProductionNameDenyList": [
    "devfleet-primary",
    "devfleet-project-m-techlabs-job-finder",
    "MulattoTechSurface",
    "MULATTOTECHBOX"
  ],
  "Tailscale": {
    "Mode": "Deferred",
    "ExpectedGuestNodePattern": "DevFleet-E2E-*",
    "Authentication": {
      "Provider": "OAuthClientSecretStore",
      "Profile": "E2E",
      "Tag": "tag:devfleet-e2e",
      "Ephemeral": true,
      "Preauthorized": true,
      "Unattended": true,
      "SecretStore": "LOCALAPPDATA/DevFleet/E2E/secrets.json"
    },
    "PollSeconds": 3,
    "PollTimeoutSeconds": 120
  },
  "NestedLinux": {
    "Name": "DevFleet-E2E-Linux-01",
    "UbuntuImage": "24.04",
    "Cpus": 2,
    "Memory": "4G",
    "Disk": "40G",
    "BootstrapTimeoutSeconds": 6600,
    "RequireSystemd": true,
    "RequireRootlessDocker": true
  },
  "DeadlinePolicy": {
    "Version": "1.0.0",
    "OperationMaximumsSeconds": {
      "bootstrap": 240,
      "preflight": 120,
    "dependencyProbe": 60,
    "dependencyHealth": 180,
    "dependencyInstall": 1800,
    "dependencyVerification": 60,
    "windowsCapability": 900,
    "windowsFeature": 900,
    "multipassConfiguration": 600,
    "vscodeExtension": 300,
    "prerequisites": 17700,
      "windowsTailscale": 900,
      "hostAgent": 300,
      "multipassLaunch": 900,
      "multipassReadiness": 1200,
      "payloadTransfer": 900,
      "guestBootstrap": 6600,
      "vaultBootstrap": 3900,
      "sshAndMarker": 300,
      "vaultSnapshot": 300,
      "tailscale": 900,
      "vaultClient": 300,
      "shortcuts": 180,
      "export": 300,
      "verification": 300
    },
    "GuestBootstrapComponentsSeconds": {
      "packagePrerequisites": 900,
      "dockerRepositoryAndInstall": 1200,
      "tailscaleRepositoryAndInstall": 1200,
      "rootlessRuntime": 600,
      "nodeToolchain": 600,
      "pythonRuntime": 1200,
      "serviceAndFirewallFinalization": 600
    },
    "TransactionTerminalizationMarginSeconds": 600,
    "ObserverTerminalizationMarginSeconds": 600,
    "FullReleaseTerminalizationMarginSeconds": 600,
    "ExactProofTerminalizationMarginSeconds": 600,
    "ObserverNoProgressBudgetSeconds": 1800,
    "MaxRebootBoundaries": 3,
    "MaximumExactProofOuterWatchdogSeconds": 180000
  },
  "FullReleaseScenarioGroups": [
    "dependency-matrix",
    "wpf-uia",
    "primary",
    "maintenance-independent-checkpoints",
    "permanent-delete",
    "delete-restore",
    "stopped-project",
    "windows-sentinels",
    "real-use-acceptance",
    "tailscale"
  ],
  "RealUseAcceptance": {
    "TimeoutSeconds": 36000
  },
  "FullReleaseExecutors": {
    "DEPENDENCY-MATRIX": "automation/release-e2e/modules/executors/Invoke-DependencyMatrix.ps1",
    "SECURITY-POISON": "automation/release-e2e/modules/executors/Invoke-SecurityPoisonPhase.ps1",
    "FRESH-INSTALL-WPF": "automation/release-e2e/modules/executors/Invoke-WpfPhase.ps1",
    "PRIMARY": "automation/release-e2e/modules/executors/Invoke-PrimaryPhase.ps1",
    "LINUX": "automation/release-e2e/modules/executors/Invoke-LinuxPhase.ps1",
    "HTTP-HOSTILE": "automation/release-e2e/modules/executors/Invoke-HttpHostilePhase.ps1",
    "REPAIR": "automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1",
    "CLEAN-REINSTALL": "automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1",
    "UNINSTALL": "automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1",
    "FACTORY-RESET": "automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1",
    "REBOOT-RESUME": "automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1",
    "PERMANENT-DELETE": "automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1",
    "DELETE-RESTORE": "automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1",
    "STOPPED-PROJECT": "automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1",
    "HOST-CONCURRENCY": "automation/release-e2e/modules/executors/Invoke-HostAgentPhase.ps1",
    "OPERATION-RECOVERY": "automation/release-e2e/modules/executors/Invoke-HostAgentPhase.ps1",
    "OWNERSHIP": "automation/release-e2e/modules/executors/Invoke-HostAgentPhase.ps1",
    "WINDOWS-SENTINELS": "automation/release-e2e/modules/executors/Invoke-MaintenancePhase.ps1",
    "VAULT": "automation/release-e2e/modules/executors/Invoke-HostAgentPhase.ps1",
    "SURROGATE-DISPOSABLE": "automation/release-e2e/modules/executors/Invoke-WpfPhase.ps1",
    "REAL-USE-ACCEPTANCE": "automation/release-e2e/modules/executors/Invoke-HostAgentPhase.ps1",
    "TAILSCALE-DEFERRED": "automation/release-e2e/modules/executors/Invoke-TailscalePhase.ps1",
    "TAILSCALE-AUTH": "automation/release-e2e/modules/executors/Invoke-TailscalePhase.ps1",
    "AI-BUNDLE": "automation/release-e2e/modules/executors/Invoke-AuditPhase.ps1",
    "RECONCILE": "automation/release-e2e/modules/executors/Invoke-AuditPhase.ps1"
  }
}

```


## FILE: automation/release-e2e/modules/BaselineLineage.psm1

SHA256: 624dacfae365be77fb7dbce76924b1628994eedbdc6576ef400e4bc8a6e74e96 | Bytes: 9067 | Git mode: 100644

```
Set-StrictMode -Version Latest

function ConvertTo-DevFleetBaselineUtc([object]$Value) {
    $parsed=[datetimeoffset]::MinValue
    if($Value -is [datetime]){
        if($Value.Kind -ne [datetimekind]::Utc){throw 'Baseline evidence instant is not UTC.'}
        $parsed=[datetimeoffset]$Value
    }elseif(-not[datetimeoffset]::TryParse([string]$Value,[ref]$parsed)){
        throw 'Baseline evidence instant is malformed.'
    }
    if($parsed.Offset -ne [timespan]::Zero){throw 'Baseline evidence instant is not UTC.'}
    return $parsed
}

function Get-DevFleetAcceptedBaseline {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[psobject]$Fingerprint)
    $root=(Resolve-Path -LiteralPath $WorkspaceRoot -ErrorAction Stop).Path
    $oldName='DevFleet-E2E-CLEAN'
    $oldId='19865b76-4c3a-44f7-ba39-841e9d3c40c9'
    $vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
    $pointerPath=Join-Path $root 'evidence\baselines\CURRENT.json'
    if(-not(Test-Path -LiteralPath $pointerPath -PathType Leaf)){
        return [pscustomobject]@{name=$oldName;id=$oldId;vmName='DevFleet-E2E-Win11-01';vmId=$vmId;predecessorId=$null;receiptSha256=$null;legacyOriginal=$true}
    }
    if($null -eq $Fingerprint){throw 'Adopted baseline requires a current native candidate fingerprint.'}
    $pointerItem=Get-Item -LiteralPath $pointerPath -Force -ErrorAction Stop
    if(($pointerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $pointerItem.Length -gt 1048576){throw 'Accepted baseline pointer is linked or oversized.'}
    $pointer=Get-Content -LiteralPath $pointerPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    if([int]$pointer.generation -in @(2,3,4,5)){
        # The rebound reader validates the complete archived pointer and
        # immutable receipt chain in the native strict-JSON transaction module.
        $expected=[ordered]@{
            repositoryHead=[string]$Fingerprint.repositoryHead
            candidateBuildCommit=[string]$Fingerprint.gitCommit
            shippingInputIdentity=[string]$Fingerprint.shippingInputIdentity
            releaseFingerprintId=[string]$Fingerprint.releaseFingerprintId
            toolingFingerprintId=[string]$Fingerprint.toolingFingerprintId
            candidateSha256=[string]$Fingerprint.candidate.sha256
        }
        $tuplePath=[IO.Path]::GetTempFileName()
        try {
            [IO.File]::WriteAllText($tuplePath,($expected|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
            $python=(Get-Command python.exe -ErrorAction Stop).Source
            $script=Join-Path $root 'tools\baseline_lineage.py'
            $lines=@(& $python $script inspect --root $root --tuple $tuplePath)
            if($LASTEXITCODE -ne 0){throw 'Native rebound baseline lineage rejected.'}
            $resolved=($lines -join "`n")|ConvertFrom-Json -ErrorAction Stop
            if([string]$resolved.receiptSha256 -cne [string]$pointer.receiptSha256 -or [string]$resolved.id -cne [string]$pointer.checkpoint.id){throw 'Native rebound baseline result differs.'}
            return $resolved
        } finally {Remove-Item -LiteralPath $tuplePath -Force -ErrorAction SilentlyContinue}
    }
    if([int]$pointer.schemaVersion -ne 1 -or [string]$pointer.contract -cne 'devfleet-accepted-baseline-v1' -or [int]$pointer.generation -ne 1 -or [string]$pointer.status -cne 'ACCEPTED'){
        throw 'Accepted baseline pointer contract is invalid.'
    }
    $receiptFile=[string]$pointer.receiptFile
    if($receiptFile -cnotmatch '^[0-9a-f]{32}\.json$'){throw 'Accepted baseline receipt filename is invalid.'}
    $receiptPath=Join-Path $root (Join-Path 'evidence\baselines\receipts' $receiptFile)
    $receiptItem=Get-Item -LiteralPath $receiptPath -Force -ErrorAction Stop
    if($receiptItem.PSIsContainer -or ($receiptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $receiptItem.Length -gt 1048576){throw 'Accepted baseline receipt is linked or oversized.'}
    $receiptHash=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if([string]$pointer.receiptSha256 -cne $receiptHash){throw 'Accepted baseline receipt hash mismatch.'}
    $receipt=Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    if([int]$receipt.schemaVersion -ne 1 -or [string]$receipt.contract -cne 'devfleet-baseline-adoption-receipt-v1' -or [string]$receipt.status -cne 'ADOPTED' -or [string]$receipt.receiptId -cne $receiptFile.Substring(0,32) -or $receipt.certificationCredit -isnot [bool] -or $receipt.certificationCredit -or $receipt.secretValuesRecorded -isnot [bool] -or $receipt.secretValuesRecorded){throw 'Accepted baseline receipt contract is invalid.'}
    if([string]$receipt.predecessor.name -cne $oldName -or [string]$receipt.predecessor.id -cne $oldId){throw 'Accepted baseline predecessor identity differs.'}
    $replacement=$receipt.replacement
    $newId=[guid]::Empty
    if(-not[guid]::TryParse([string]$replacement.id,[ref]$newId) -or $newId -eq [guid]$oldId -or [string]$replacement.name -cne 'DevFleet-E2E-CLEAN-R2' -or [string]$replacement.vmId -cne $vmId -or [string]$replacement.parentSnapshotId -cne $oldId){throw 'Accepted replacement identity or parent differs.'}
    if([string]$pointer.checkpoint.name -cne [string]$replacement.name -or [string]$pointer.checkpoint.id -cne [string]$replacement.id -or [string]$pointer.checkpoint.vmId -cne $vmId -or [string]$pointer.checkpoint.parentSnapshotId -cne $oldId){throw 'Pointer and immutable receipt checkpoint disagree.'}
    $expected=[ordered]@{
        repositoryHead=[string]$Fingerprint.repositoryHead
        candidateBuildCommit=[string]$Fingerprint.gitCommit
        shippingInputIdentity=[string]$Fingerprint.shippingInputIdentity
        releaseFingerprintId=[string]$Fingerprint.releaseFingerprintId
        toolingFingerprintId=[string]$Fingerprint.toolingFingerprintId
        candidateSha256=[string]$Fingerprint.candidate.sha256
    }
    foreach($key in $expected.Keys){
        if([string]$receipt.candidate.$key -cne $expected[$key]){throw "Accepted baseline candidate/material mismatch: $key"}
    }
    $expiry=ConvertTo-DevFleetBaselineUtc $receipt.passwordExpiresUtc
    $lastSet=ConvertTo-DevFleetBaselineUtc $receipt.passwordLastSetUtc
    $storeUpdated=ConvertTo-DevFleetBaselineUtc $receipt.protectedStoreUpdatedUtc
    $authObserved=ConvertTo-DevFleetBaselineUtc $receipt.authenticatedGuest.sourceObservedUtc
    if($expiry -le [datetimeoffset]::UtcNow -or $lastSet -gt $storeUpdated -or $storeUpdated -gt $authObserved -or $authObserved -ge $expiry){throw 'Accepted baseline account freshness or expiry is unknown or elapsed.'}
    if([string]$receipt.adoptionAuthority.decision -cne 'APPROVE' -or [string]$receipt.adoptionAuthority.approvedBy -cne 'ACCOUNT_OWNER' -or [string]$receipt.authenticatedGuest.computerName -cne 'DEVFLEET-E2E-01' -or [string]$receipt.authenticatedGuest.principal -cne 'DEVFLEET-E2E-01\E2EAdmin' -or $receipt.authenticatedGuest.accountEnabled -isnot [bool] -or -not $receipt.authenticatedGuest.accountEnabled -or [string]$receipt.nestedL2.status -cne 'ABSENT' -or $receipt.nestedL2.present -isnot [bool] -or $receipt.nestedL2.present -or [string]$receipt.nestedL2.expectedName -cne 'DevFleet-E2E-Linux-01' -or [int]$receipt.nestedL2.exactMatchCount -ne 0 -or [string]$receipt.finalL1.state -cne 'Off' -or [string]$receipt.finalL1.name -cne 'DevFleet-E2E-Win11-01' -or [string]$receipt.finalL1.id -cne $vmId){throw 'Accepted baseline adoption authority, guest, nested inventory, or terminal L1 is invalid.'}
    $inventories=@($receipt.nestedL2.backendInventories)
    if($inventories.Count -ne 2 -or @($inventories|Where-Object{$_.provider -ceq 'Hyper-V' -and $_.status -ceq 'PASS'}).Count -ne 1 -or @($inventories|Where-Object{$_.provider -ceq 'VirtualBox' -and $_.status -ceq 'PASS'}).Count -ne 1){throw 'Accepted baseline nested backend inventory is incomplete.'}
    foreach($inventory in $inventories){
        if($inventory.names -isnot [array] -or [string]::IsNullOrWhiteSpace([string]$inventory.verification) -or @($inventory.names|Where-Object{$_ -ceq 'DevFleet-E2E-Linux-01'}).Count -gt 0){throw 'Accepted baseline nested backend inventory is incomplete or present.'}
    }
    foreach($sourceKey in @('proposalSha256','predecessorEvidenceSha256','approvalSha256','authenticatedGuestSha256','nativeInventorySha256','currentTupleSha256','r2LedgerSha256')){
        if([string]$receipt.sources.$sourceKey -cnotmatch '^[0-9a-f]{64}$'){throw "Accepted baseline source hash missing: $sourceKey"}
    }
    if([string]$receipt.adoptionAuthority.sourceSha256 -cne [string]$receipt.sources.approvalSha256){throw 'Accepted baseline adoption approval hash differs.'}
    return [pscustomobject]@{name=[string]$replacement.name;id=[string]$replacement.id;vmName='DevFleet-E2E-Win11-01';vmId=$vmId;predecessorId=$oldId;receiptSha256=$receiptHash;receiptFile=$receiptFile;legacyOriginal=$false}
}

Export-ModuleMember -Function Get-DevFleetAcceptedBaseline

```


## FILE: automation/release-e2e/modules/Candidate.psm1

SHA256: e7b13883df7716fae759c6240369cec274ab09b6e3413e2644c5e133c50a32b1 | Bytes: 17395 | Git mode: 100644

```
Set-StrictMode -Version Latest

function Get-FileHashRecord {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $item = Get-Item -LiteralPath $resolved -ErrorAction Stop
    [pscustomobject]@{
        path = $resolved
        bytes = [int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-WindowsTokenEvidence {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $groupSids = @($identity.Groups | ForEach-Object { [string]$_.Value })
    $whoami = Join-Path $env:SystemRoot 'System32\whoami.exe'
    if (-not (Test-Path -LiteralPath $whoami -PathType Leaf)) {
        throw 'Windows token inspection utility is unavailable.'
    }
    $groupRows = @(& $whoami /groups /fo csv /nh 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Windows token groups could not be inspected.' }
    $groupText = [string]::Join([Environment]::NewLine, $groupRows)
    $integrityMatches = @([regex]::Matches($groupText, 'S-1-16-(?<rid>\d+)'))
    if ($integrityMatches.Count -ne 1) {
        throw "Windows token integrity evidence is ambiguous: found $($integrityMatches.Count) labels."
    }
    $integrityRid = [int]$integrityMatches[0].Groups['rid'].Value
    $integritySid = "S-1-16-$integrityRid"
    $integrityLevel = switch ($integrityRid) {
        4096 { 'Low' }
        8192 { 'Medium' }
        8448 { 'MediumPlus' }
        12288 { 'High' }
        16384 { 'System' }
        default { 'Unknown' }
    }
    $administratorMember = (
        'S-1-5-32-544' -in $groupSids -or
        $groupText -match '(?<!\d)S-1-5-32-544(?!\d)'
    )
    $administratorEnabled = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    $elevated = $integrityRid -ge 12288
    [pscustomobject]@{
        userName = [string]$identity.Name
        isAdministratorMember = [bool]$administratorMember
        isAdministratorEnabled = [bool]$administratorEnabled
        isElevated = [bool]$elevated
        integrityLevelSid = $integritySid
        integrityLevel = $integrityLevel
        standardNonAdministratorToken = [bool](
            $integrityRid -in @(8192, 8448) -and
            -not $administratorMember -and
            -not $administratorEnabled -and
            -not $elevated
        )
    }
}

function Test-PrivateAuthenticodeSignature {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$PublicCertificatePath,
        [Parameter(Mandatory)][string]$ExpectedThumbprint
    )
    $resolved=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $certificatePath=(Resolve-Path -LiteralPath $PublicCertificatePath -ErrorAction Stop).Path
    $trustedCertificate=$null;$chain=$null;$tampered=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-authenticode-tampered-{0}.exe" -f [guid]::NewGuid().ToString('N'))
    try{
        $trustedCertificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
        if($trustedCertificate.Thumbprint -cne $ExpectedThumbprint){throw 'Public verifier certificate thumbprint differs from the private signing manifest.'}
        $signature=Get-AuthenticodeSignature -LiteralPath $resolved
        if(-not $signature.SignerCertificate){throw 'Private candidate has no Authenticode signer certificate.'}
        if($signature.SignerCertificate.Thumbprint -cne $ExpectedThumbprint){throw 'Private candidate signer thumbprint differs from the final manifest.'}
        if([Convert]::ToBase64String($signature.SignerCertificate.RawData) -cne [Convert]::ToBase64String($trustedCertificate.RawData)){throw 'Private candidate signer differs from the exact supplied public certificate.'}
        if([string]$signature.Status -notin @('Valid','UnknownError')){throw "Private candidate Authenticode returned an unexpected status: $($signature.Status)."}
        if([string]$signature.Status -eq 'UnknownError' -and [string]$signature.StatusMessage -notmatch '(?i)trust|root|certificate chain'){throw "Private candidate Authenticode UnknownError was not solely an untrusted-root condition: $($signature.StatusMessage)"}
        if('1.3.6.1.5.5.7.3.3' -notin @($signature.SignerCertificate.EnhancedKeyUsageList|ForEach-Object{[string]$_.ObjectId})){throw 'Private candidate signer lacks Code Signing EKU.'}
        $chain=[Security.Cryptography.X509Certificates.X509Chain]::new()
        $chain.ChainPolicy.RevocationMode=[Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $chain.ChainPolicy.VerificationFlags=[Security.Cryptography.X509Certificates.X509VerificationFlags]::AllowUnknownCertificateAuthority
        $null=$chain.ChainPolicy.ExtraStore.Add($trustedCertificate)
        if(-not $chain.Build($signature.SignerCertificate)){throw "Private candidate exact-certificate chain validation failed: $(@($chain.ChainStatus|ForEach-Object Status)-join ', ')"}
        $unexpected=@($chain.ChainStatus|Where-Object{[string]$_.Status -notin @('NoError','UntrustedRoot')})
        if($unexpected.Count){throw "Private candidate chain has unexpected status: $(@($unexpected|ForEach-Object Status)-join ', ')"}
        Copy-Item -LiteralPath $resolved -Destination $tampered
        $stream=[IO.File]::Open($tampered,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try{$stream.Position=4096;$byte=$stream.ReadByte();if($byte -lt 0){throw 'Candidate is too small for the tamper negative control.'};$stream.Position=4096;$stream.WriteByte(($byte -bxor 1))}finally{$stream.Dispose()}
        $tamperedStatus=[string](Get-AuthenticodeSignature -LiteralPath $tampered).Status
        if($tamperedStatus -ne 'HashMismatch'){throw "Private candidate tampered-copy verification returned $tamperedStatus instead of HashMismatch."}
        [pscustomobject]@{status='PASS';effectiveSignatureStatus='Valid';platformSignatureStatus=[string]$signature.Status;platformSignatureStatusMessage=[string]$signature.StatusMessage;signerThumbprint=$signature.SignerCertificate.Thumbprint;exactCertificateMatch=$true;codeSigningEkuVerified=$true;explicitTrustValidation='PASS';trustMode='IN_MEMORY_EXACT_CERTIFICATE';chainStatuses=@($chain.ChainStatus|ForEach-Object{[string]$_.Status});tamperedCopyStatus=$tamperedStatus;trustStoreMutated=$false;publicPublisherTrust=$false}
    }finally{
        Remove-Item -LiteralPath $tampered -Force -ErrorAction SilentlyContinue
        if($chain){$chain.Dispose()}
        if($trustedCertificate){$trustedCertificate.Dispose()}
    }
}

function Get-CandidateFingerprint {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [string]$CandidatePath
    )
    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot -ErrorAction Stop).Path
    $outputs = Join-Path $workspace 'outputs'
    if ($CandidatePath) {
        $exe = (Resolve-Path -LiteralPath $CandidatePath -ErrorAction Stop).Path
    } else {
        $choices = @(Get-ChildItem -LiteralPath $outputs -Filter 'DevFleet-Setup-*.exe' -File | Sort-Object LastWriteTimeUtc -Descending)
        if ($choices.Count -ne 1) { throw "Candidate discovery is ambiguous: found $($choices.Count) installer EXEs." }
        $exe = $choices[0].FullName
    }
    $leaf = Split-Path -Leaf $exe
    $match = [regex]::Match($leaf, '(?i)v(?<version>\d+\.\d+\.\d+)')
    if ($match.Success) { $version = $match.Groups['version'].Value }
    else {
        $version = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion -replace '[^0-9.].*$',''
        if (-not $version) { throw 'Unable to determine candidate version.' }
    }
    $tar = Join-Path $outputs "devfleet-v$version.tar.gz"
    $portable = @(Get-ChildItem -LiteralPath $outputs -Filter "DevFleet-v$version-Portable*.zip" -File)
    $sourceZip = Join-Path $outputs "DevFleet-v$version-Installer-Source.zip"
    foreach ($required in @($tar,$sourceZip)) { if (-not (Test-Path -LiteralPath $required)) { throw "Associated release artifact missing: $required" } }
    if ($portable.Count -ne 1) { throw "Portable artifact discovery is ambiguous: found $($portable.Count)." }
    $installerVersionPath = Join-Path $workspace 'installer-source\INSTALLER_VERSION'
    $installerVersion = if (Test-Path -LiteralPath $installerVersionPath) { (Get-Content -LiteralPath $installerVersionPath -Raw).Trim() } else { 'UNKNOWN' }
    $releaseFingerprintId = $null
    $toolingFingerprintId = $null
    $candidateGitCommit = $null
    $candidateStatePath = Join-Path $workspace 'finalization-state.json'
    $candidateManifestPath = Join-Path $outputs 'final-artifact-hashes.json'
    if(-not (Test-Path -LiteralPath $candidateStatePath) -or -not (Test-Path -LiteralPath $candidateManifestPath)){throw 'Current candidate evidence state is missing.'}
    $candidateState=Get-Content -LiteralPath $candidateStatePath -Raw|ConvertFrom-Json
    $candidateManifest=Get-Content -LiteralPath $candidateManifestPath -Raw|ConvertFrom-Json
    if(-not [bool]$candidateState.candidate_is_current -or [bool]$candidateState.source_changed_since_candidate -or [bool]$candidateState.rebuild_required){throw 'Candidate evidence says the candidate is stale or requires rebuild.'}
    $candidateGitCommit=[string]$candidateManifest.candidateGitCommit
    if(-not $candidateGitCommit){$candidateGitCommit=[string]$candidateState.candidate_git_commit}
    $head=(& git -C $workspace rev-parse HEAD 2>$null).Trim()
    if($candidateGitCommit -notmatch '^[0-9a-fA-F]{40}$'){throw 'Candidate evidence has an invalid shipping candidate commit.'}
    $candidateIdentity = [string]$candidateState.shipping_input_identity
    if ([string]::IsNullOrWhiteSpace($candidateIdentity)) { $candidateIdentity = [string]$candidateState.shippingInputIdentity }
    if ([string]::IsNullOrWhiteSpace($candidateIdentity)) { $candidateIdentity = [string]$candidateManifest.shippingInputIdentity }
    if($candidateIdentity -notmatch '^[0-9a-fA-F]{64}$'){throw 'Candidate evidence is missing deterministic shipping-input identity.'}
    if([string]$candidateManifest.candidateGitCommit -and [string]$candidateManifest.candidateGitCommit -ne $candidateGitCommit){throw 'Candidate manifest commit fields disagree.'}
    $candidateRecord=@($candidateManifest.artifacts|Where-Object name -eq 'exe')
    if($candidateRecord.Count -ne 1){throw 'Candidate manifest must contain exactly one EXE artifact identity.'}
    $observedCandidate=Get-FileHashRecord -Path $exe
    if([string]$candidateRecord[0].sha256 -ne $observedCandidate.sha256 -or [int64]$candidateRecord[0].bytes -ne $observedCandidate.bytes){throw 'Candidate EXE does not match its final post-sign manifest identity.'}
    $privateSigningProfile=if($candidateManifest.PSObject.Properties['privateSigningProfile']){[string]$candidateManifest.privateSigningProfile}else{''}
    $privateSigningThumbprint=if($candidateManifest.PSObject.Properties['privateSigningCertificateThumbprint']){[string]$candidateManifest.privateSigningCertificateThumbprint}else{''}
    $manifestPublicPublisherTrust=if($candidateManifest.PSObject.Properties['publicPublisherTrust']){[bool]$candidateManifest.publicPublisherTrust}else{$false}
    $manifestPublicPromotionAllowed=if($candidateManifest.PSObject.Properties['publicPromotionAllowed']){[bool]$candidateManifest.publicPromotionAllowed}else{$false}
    $publicCertificate=$null
    if($privateSigningProfile -eq 'PRIVATE_SELF_SIGNED'){
        if($manifestPublicPublisherTrust -or $manifestPublicPromotionAllowed){throw 'Private self-signed candidate evidence incorrectly enables public trust or promotion.'}
        if($privateSigningThumbprint -notmatch '^[0-9A-Fa-f]{40}$'){throw 'Private signing manifest thumbprint is invalid.'}
        $publicCertificatePath=Join-Path $outputs 'DevFleet-Private-Personal-Code-Signing.cer'
        if(-not(Test-Path -LiteralPath $publicCertificatePath -PathType Leaf)){throw 'Private candidate public verifier certificate is missing.'}
        $publicCertificate=Get-FileHashRecord -Path $publicCertificatePath
        $authenticode=Test-PrivateAuthenticodeSignature -Path $exe -PublicCertificatePath $publicCertificatePath -ExpectedThumbprint $privateSigningThumbprint
    }
    $releaseFingerprintPath = Join-Path $outputs 'release-fingerprint.json'
    if (Test-Path -LiteralPath $releaseFingerprintPath) {
        $releaseMetadata = Get-Content -LiteralPath $releaseFingerprintPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $releaseFingerprintId = [string]$releaseMetadata.releaseFingerprintId
        $toolingFingerprintId = [string]$releaseMetadata.toolingFingerprint.toolingFingerprintId
    }
    [pscustomobject]@{
        releaseVersion = $version
        installerVersion = $installerVersion
        gitCommit = $candidateGitCommit
        repositoryHead = $head
        shippingInputIdentity = $candidateIdentity
        releaseFingerprintId = $releaseFingerprintId
        toolingFingerprintId = $toolingFingerprintId
        candidate = $observedCandidate
        tar = Get-FileHashRecord -Path $tar
        portable = Get-FileHashRecord -Path $portable[0].F