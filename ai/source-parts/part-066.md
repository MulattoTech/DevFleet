# DevFleet source part 066

Full-source UTF-8 byte interval [3022500, 3069000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 0ba7babe15ca99c16d5d65f95ef6d8ae408668905fcfd49203aaaeabc5efec3b

<!-- BEGIN SOURCE SLICE -->
ates were checked for required formatter, linter, test, bootstrap, and health metadata.
- Native sample tests executed successfully where the sandbox toolchain was available: Python, Python/FastAPI, Node.js, and Go.
- Preservation comparison against the verified v1.0.0 ZIP confirmed that no baseline file path was removed.
- Embedded SHA-256 verification and independent post-extraction archive verification are performed after the final manifests are frozen.

## PowerShell validation boundary

The package includes `tools/Verify-Package.ps1`, which uses the real PowerShell AST parser on Windows before installation. PowerShell was not installed in the offline Linux sandbox, and outbound DNS prevented downloading it, so the final sandbox pass uses the companion structural PowerShell validator. The real AST check remains a hard preflight on the target Windows machines.

## Checks requiring Dylan's actual environment

These cannot be truthfully completed offline and remain installation/preflight tests:

- Hyper-V or VirtualBox selection and firmware virtualization.
- Multipass launch, stopped-state snapshots, VM refresh, and host-mount disablement.
- Rootless/rootful Docker stores, BuildKit, Compose validation against a live daemon, and Docker-over-SSH context.
- Tailscale login, MagicDNS, ACL reachability, tailnet-only port/firewall behavior, and peer transfer.
- Append-only rest-server/restic credentials, backup/restore, vault retention authority, and encrypted offline export.
- GitHub device authorization and private-repository access.
- VS Code Remote SSH/Dev Containers against `CodexDevVM`.
- CodexPro installation/connector authorization and project bootstrap against Dylan's live service.
- Windows Ollama, RX 7900 XTX observation, expected model availability, concurrency profiles, and OpenAI-compatible `/v1` behavior.

The install and upgrade scripts stop rather than silently bypassing these checks when a required real-machine prerequisite is missing.

```


## FILE: source/INSTALL-CHECKLIST.txt

SHA256: 1eaa7f8e5513960dce8b9ef1501f9d1f6a60383aa6f0529c906666a08b04a163 | Bytes: 2117 | Git mode: 100644

```
DEVFLEET SAFE REMOTE DEVELOPMENT v1.1.0 — INSTALL / UPGRADE CHECKLIST

CLEAN INSTALL
[ ] Extract locally on both Windows computers; do not run from a cloud-synced folder.
[ ] Review config/devfleet.config.json and docs/00-HARD-STOPS-AND-ASSUMPTIONS.md.
[ ] Close MuMu/other hypervisors during provisioning.
[ ] Laptop Administrator: START-HERE-LAPTOP.cmd
[ ] Approve Tailscale for Windows, failover VM, and vault VM.
[ ] Transfer encrypted laptop bootstrap bundle to desktop.
[ ] Desktop Administrator: START-HERE-DESKTOP.cmd
[ ] Review the rootful-Docker explanation; type ENABLE ROOTFUL CODEXDEVVM only when you accept VM-internal rootful authority.
[ ] Approve Tailscale for Windows and devfleet-primary.
[ ] Transfer encrypted desktop pairing bundle to laptop.
[ ] Laptop: windows\Complete-Cluster.ps1 -DesktopPairingBundlePath <bundle>
[ ] Confirm Complete-Cluster configured the CodexDevVM SSH alias and core VS Code extensions.
[ ] Optional: client\Configure-VSCode.ps1 -ExtensionSets core,python,web,enterprise,systems
[ ] Optional Docker CLI: client\Configure-DockerContext.ps1
[ ] Desktop: windows\Configure-Ollama.ps1 -Profile stable-interactive
[ ] Restart Ollama, then windows\Test-Ollama.ps1 -ProbeGeneration
[ ] Create a disposable test project; start, test, back up, quarantine, and restore it.

UPGRADE
[ ] Keep and verify the original v1.0.0 ZIP.
[ ] Administrator: pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0 -PreviewOnly
[ ] Review the migration preview and backup path under C:\ProgramData\DevFleet.
[ ] Administrator: pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0
[ ] Confirm pre-v1-1-0 snapshots and the upgrade-result.json file.
[ ] Confirm baseline deployments remain Strict/rootless.
[ ] Test health, backup, restore, CodexPro, analyzer, and ownership transfer before changing profile.

NEVER
[ ] Never enable Multipass host mounts.
[ ] Never expose Docker 2375 or unauthenticated Docker TCP.
[ ] Never mount Windows profiles/drives/cloud shares into projects.
[ ] Never give ordinary project containers docker.sock.
[ ] Never prune vault history with compute credentials.

```


## FILE: source/Install-DevFleet.ps1

SHA256: a6eb7b82456f5de4c0d9446aa1901b70311e2dc8adf8bd8311affa25688d494e | Bytes: 12735 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Laptop','Desktop')]
    [string]$Role,
    [string]$BootstrapBundlePath,
    [string]$PackageRoot,
    [ValidateSet('Connected')]
    [string]$InstallationMode = 'Connected',
    [switch]$NonInteractive,
    [switch]$SkipWindowsUpdates,
    [switch]$ForceReprovision,
  [switch]$DeferNetworkPairing,
  [switch]$AcknowledgeRootfulDocker,
  [string]$TransactionDeadlineUtc,
  [string]$TransactionId,
  [string]$TransactionPayloadSha256,
  [string]$TransactionAction,
  [string]$TransactionRole,
  [string]$TransactionPreparedUtc,
  [string]$DeadlinePolicyVersion = '1.0.0'
)

$ErrorActionPreference = 'Stop'
if($Role-eq'Laptop'-and$DeferNetworkPairing){throw 'Laptop / Failover / Vault setup requires connected Tailscale pairing. Clear Configure network pairing later before installing or repairing this role.'}
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$packageRoot = if ($PackageRoot) { (Resolve-Path -LiteralPath $PackageRoot).Path } else { $here }
if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'windows\00-Preflight.ps1'))) { throw "Package root is not a valid DevFleet package: $packageRoot" }
Import-Module (Join-Path $here 'windows\DevFleet.Common.psm1') -Force
if($DeadlinePolicyVersion -ne '1.0.0'){throw "Unsupported deadline policy version: $DeadlinePolicyVersion"}
$transactionDeadline = if($TransactionDeadlineUtc){try{[datetime]::Parse($TransactionDeadlineUtc).ToUniversalTime()}catch{throw 'Transaction deadline is not a valid UTC timestamp.'}}else{[datetime]::UtcNow.AddSeconds((Get-DevFleetTransactionBudgetSeconds $Role))}
Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'preflight' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'preflight') | Out-Null
Assert-PowerShell7
Assert-Administrator
Initialize-DevFleetState -PackageRoot $here
# Establish the host-secret record before any durable deployment identity is
# created. A prerequisite 3010 boundary must resume with credentials intact.
Get-OrCreateSecrets | Out-Null
$activeTransaction=Wait-ActiveDevFleetTransaction -ExpectedRole $Role
if(-not (Test-DevFleetTransactionBinding -Transaction $activeTransaction -ExpectedRole $Role) -and $TransactionId -and $TransactionPayloadSha256 -and $TransactionAction -and $TransactionRole -and $TransactionPreparedUtc){
 $propagated=[pscustomobject]@{transactionId=$TransactionId;payloadSha256=$TransactionPayloadSha256;action=$TransactionAction;role=$TransactionRole;preparedUtc=$TransactionPreparedUtc}
 if(Test-DevFleetTransactionBinding -Transaction $propagated -ExpectedRole $Role){$activeTransaction=$propagated}
}
if(-not (Test-DevFleetTransactionBinding -Transaction $activeTransaction -ExpectedRole $Role)){throw 'The installer parent could not establish an exact active transaction binding before child stages.'}
$checkpointPath=Join-Path (Join-Path $env:ProgramData 'M-TechLabs\DevFleet\Installer') 'resume-checkpoint.json'
$resumedTransaction=$false
if(Test-Path -LiteralPath $checkpointPath -PathType Leaf){
 try{
  $checkpoint=Get-Content -LiteralPath $checkpointPath -Raw|ConvertFrom-Json
  $checkpointRole=if([string]$checkpoint.role -match '(?i)Laptop'){'Laptop'}elseif([string]$checkpoint.role -match '(?i)Desktop'){'Desktop'}else{''}
  if([string]$checkpoint.state -ne 'waiting-for-reboot' -or
     [string]$checkpoint.transactionId -cne [string]$activeTransaction.transactionId -or
     [string]$checkpoint.payloadSha256 -cne [string]$activeTransaction.payloadSha256 -or
     [string]$checkpoint.action -cne [string]$activeTransaction.action -or
     $checkpointRole -cne [string]$activeTransaction.role){throw 'The installer resume checkpoint does not match the active DevFleet transaction.'}
  $resumedTransaction=$true
 }catch{throw "The installer resume checkpoint could not be established safely: $($_.Exception.Message)"}
}
Set-DevFleetPendingRebootBaseline -ResumedTransaction:$resumedTransaction | Out-Null
$transactionStageArgs=@{
    TransactionId=[string]$activeTransaction.transactionId
    TransactionPayloadSha256=[string]$activeTransaction.payloadSha256
    TransactionAction=[string]$activeTransaction.action
    TransactionRole=[string]$activeTransaction.role
    TransactionPreparedUtc=[string]$activeTransaction.preparedUtc
}

Write-Host "`n=== DevFleet installation: $Role ===" -ForegroundColor Cyan
& (Join-Path $here 'windows\00-Preflight.ps1') -Role $Role -InstallationMode $InstallationMode
if(-not (Test-StageMarker "prereqs-$Role")){ Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'prerequisites' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'prerequisites') | Out-Null; & (Join-Path $here 'windows\01-Install-Prerequisites.ps1') -Role $Role -OfflinePackageRoot $packageRoot -InstallationMode $InstallationMode -SkipWindowsUpdates:$SkipWindowsUpdates }

if (Test-PendingReboot) {
    Write-Warning 'Windows requires a reboot before VM provisioning. Re-run this same command after reboot; completed stages will be detected.'
    exit 3010
}

# Do not create durable deployment identity before the prerequisite stage has
# crossed its reboot boundary.
$nodeIdentity = Get-OrCreateNodeIdentity -Role $Role

if (-not $DeferNetworkPairing -and -not (Test-StageMarker 'windows-tailscale')) {
    Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'windowsTailscale' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'windowsTailscale') | Out-Null
    & (Join-Path $here 'windows\04a-Connect-WindowsTailscale.ps1')
    if ([int]$LASTEXITCODE -eq 3010) { exit 3010 }
    Write-StageMarker 'windows-tailscale'
} elseif ($DeferNetworkPairing) { Write-Warning 'Windows Tailscale pairing was deliberately deferred; complete it from Maintenance.' }
if (Test-PendingReboot) {
    Write-Warning 'Windows reported a new reboot requirement after the Windows Tailscale stage. Re-run this same transaction after reboot; completed stages will be detected.'
    exit 3010
}
if(-not (Test-StageMarker 'host-agent')){ Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'hostAgent' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'hostAgent') | Out-Null; & (Join-Path $here 'windows\Install-DevFleet-HostAgent.ps1'); Write-StageMarker 'host-agent' }

if ($Role -eq 'Desktop') {
    $installedConfig = Get-DevFleetConfig
if ($AcknowledgeRootfulDocker -and [string]$installedConfig.Docker.PrimaryMode -eq 'rootful') { $installedConfig.Docker.RootfulModeAcknowledged = $true; Save-DevFleetConfig -Config $installedConfig }
if ([string]$installedConfig.Docker.PrimaryMode -eq 'rootful' -and -not [bool]$installedConfig.Docker.RootfulModeAcknowledged) {
        if ($NonInteractive) { throw 'NonInteractive installation cannot acknowledge rootful Docker; configure rootless mode or provide an explicit reviewed configuration.' }
        $phrase = Read-Host 'CodexDevVM is an isolated VM, but rootful Docker has broader VM-level authority. Type ENABLE ROOTFUL CODEXDEVVM to continue'
        if ($phrase -ne 'ENABLE ROOTFUL CODEXDEVVM') { throw 'Rootful Docker acknowledgement did not match. Set Docker.PrimaryMode to rootless or rerun and acknowledge it.' }
        $installedConfig.Docker.RootfulModeAcknowledged = $true
        Save-DevFleetConfig -Config $installedConfig
    }
}

if ($Role -eq 'Laptop') {
    if(-not (Test-StageMarker 'compute-devfleet-failover')){ Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'compute' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'compute') | Out-Null; & (Join-Path $here 'windows\02-Provision-ComputeNode.ps1') -NodeRole Failover -ForceReprovision:$ForceReprovision @transactionStageArgs }
    if(-not (Test-StageMarker 'vault')){ Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'vault' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'vault') | Out-Null; & (Join-Path $here 'windows\03-Provision-Vault.ps1') -ForceReprovision:$ForceReprovision @transactionStageArgs }
    if (-not $DeferNetworkPairing) { Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'tailscale' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'tailscale') | Out-Null; & (Join-Path $here 'windows\04-Connect-Tailscale.ps1') -InstanceName (Get-DevFleetConfig).Failover.InstanceName; & (Join-Path $here 'windows\04-Connect-Tailscale.ps1') -InstanceName (Get-DevFleetConfig).Vault.InstanceName }
    Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'vaultClient' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'vaultClient') | Out-Null; & (Join-Path $here 'windows\05-Configure-LocalVaultClient.ps1') -InstanceName (Get-DevFleetConfig).Failover.InstanceName
    Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'shortcuts' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'shortcuts') | Out-Null; & (Join-Path $here 'windows\08-Install-Shortcuts.ps1') -LocalInstanceName (Get-DevFleetConfig).Failover.InstanceName
    $sevenzip = @((Get-CanonicalDependencyManifest -PackageRoot $packageRoot).dependencies) | Where-Object id -eq 'sevenzip' | Select-Object -First 1
    if ($sevenzip -and (Get-DependencyStatus -Dependency $sevenzip).Status -eq 'Compatible') {
        Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'export' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'export') | Out-Null; & (Join-Path $here 'windows\09-Export-Laptop-Bootstrap.ps1')
    } else {
        Write-Warning '7-Zip is not available; encrypted laptop bootstrap export is unavailable, but core Laptop installation remains complete.'
    }
    Write-Host "`nLaptop stage complete. Copy the encrypted bootstrap bundle shown above to the desktop." -ForegroundColor Green
} else {
    if(-not (Test-StageMarker 'compute-devfleet-primary')){ Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'compute' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'compute') | Out-Null; & (Join-Path $here 'windows\02-Provision-ComputeNode.ps1') -NodeRole Primary -ForceReprovision:$ForceReprovision @transactionStageArgs }
    if (-not $DeferNetworkPairing) { Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'tailscale' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'tailscale') | Out-Null; & (Join-Path $here 'windows\04-Connect-Tailscale.ps1') -InstanceName (Get-DevFleetConfig).Primary.InstanceName }
    if ($BootstrapBundlePath) {
        & (Join-Path $here 'windows\06-Import-Laptop-Bootstrap.ps1') -BundlePath $BootstrapBundlePath
    } else {
        Write-Warning 'No laptop bootstrap bundle was supplied. The primary works locally, but backups and peer control are not configured yet.'
    }
    Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'shortcuts' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'shortcuts') | Out-Null; & (Join-Path $here 'windows\08-Install-Shortcuts.ps1') -LocalInstanceName (Get-DevFleetConfig).Primary.InstanceName
    $sevenzip = @((Get-CanonicalDependencyManifest -PackageRoot $packageRoot).dependencies) | Where-Object id -eq 'sevenzip' | Select-Object -First 1
    if ($sevenzip -and (Get-DependencyStatus -Dependency $sevenzip).Status -eq 'Compatible') {
        Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'export' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'export') | Out-Null; & (Join-Path $here 'windows\10-Export-Desktop-Pairing.ps1') -NonInteractive:$NonInteractive
    } else {
        Write-Warning '7-Zip is not available; encrypted desktop pairing export is unavailable, but core Desktop installation remains complete.'
    }
    Write-Host "`nDesktop stage complete. Copy the desktop pairing bundle back to the laptop and run Complete-Cluster.ps1." -ForegroundColor Green
}

# A servicing signal can appear asynchronously while Host Agent or nested
# compute provisioning is running. Surface it before final verification so the
# lifecycle persists a new bounded reboot generation instead of committing
# install-state over an outstanding Windows reboot obligation.
if (Test-PendingReboot) {
    Write-Warning 'Windows reported a new reboot requirement after provisioning. Re-run this same transaction after reboot; completed stages will be detected.'
    exit 3010
}

Set-DevFleetDeadlineContext -TransactionDeadlineUtc $transactionDeadline -StageName 'verification' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'verification') | Out-Null
& (Join-Path $here 'windows\Test-DevFleet.ps1') -AllLocalInstances

```


## FILE: source/MIGRATION-ROLLBACK.md

SHA256: f777b8611323924d101515ff1d8a0401d1f2d4b0e5d4b1fe1e1afafdb8c91552 | Bytes: 179 | Git mode: 100644

```
# Migration and Rollback

Mutations use a transaction state machine and retain recovery artifacts before reinstall/removal. Rollback-incomplete is surfaced rather than hidden.

```


## FILE: source/README-FIRST.md

SHA256: 5ec4487ad07cec2145a6ade137e641047c19769957c03628978218a06dfb05a4 | Bytes: 3346 | Git mode: 100644

````
# DevFleet Safe Remote Development v1.2.13

DevFleet turns an installed Windows host into isolated primary compute and a separately configured Windows host into the optional client, failover compute, and append-only vault host. It preserves the v1.0.0 three-VM recovery architecture while adding configurable development profiles, rootless/rootful Docker modes, reusable caches, language-aware templates, first-class CodexPro status/bootstrap, nonblocking dashboard operations, ownership leases, Ollama profiles, and a friendly `CodexDevVM` SSH alias. The internal Multipass instance remains `devfleet-primary`.

## Clean install

1. Review `docs/00-HARD-STOPS-AND-ASSUMPTIONS.md` and `config/devfleet.config.json`.
2. On the configured Surrogate host run `START-HERE-LAPTOP.cmd` as Administrator.
3. Transfer the encrypted pairing bundle and run `START-HERE-DESKTOP.cmd` on the configured Primary host.
4. Return the encrypted desktop pairing bundle and run `windows\Complete-Cluster.ps1` on the laptop.
5. `Complete-Cluster.ps1` configures SSH and core VS Code support automatically; optionally run the client scripts again for additional language extension groups or a Docker-over-SSH context.
6. Configure/test Windows Ollama with `windows\Configure-Ollama.ps1` and `windows\Test-Ollama.ps1`.
7. Run the health shortcut and a disposable create/start/test/backup/quarantine/restore exercise.

A clean installation defaults to Balanced with rootless Docker on both CodexDevVM and failover. Rootful mode requires the exact `ENABLE ROOTFUL CODEXDEVVM` acknowledgement and a separately provisioned privileged helper; the bootstrap does not provision that helper. Windows host folders remain unavailable to all VMs and containers.

## Upgrade v1.0.0

```powershell
pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0 -PreviewOnly
pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0
```

The upgrade backs up installed state and creates stopped-state Multipass snapshots before service changes. A baseline v1.0 deployment remains Strict/rootless until you explicitly change profile or Docker store.

## CodexPro

The project hook is an idempotent adapter using only capabilities verified in the connected CodexPro interface. It validates the active root, creates `.ai-bridge/local-agent` runtime folders, checks loopback health, invokes the verified `codexpro start` command when installed, and writes actionable logs. Private installation sources and connector authorization are never embedded. A documented multi-workspace registration command was not exposed, so DevFleet does not invent one.

## Safety invariants

All profiles retain the Windows-host filesystem boundary, project-root/path/symlink validation, no unauthenticated Docker TCP, no ordinary application access to `docker.sock`, append-only compute backup credentials, separate vault-admin retention authority, backup-before-quarantine, reversible quarantine, one writable owner per project identity, explicit split-brain acknowledgement, offline encrypted vault export, and GitHub as off-device committed history.

## Audit reports

- `DevFleet-v1.1.0-VALIDATION.md` and `DevFleet-v1.1.0-FILE-CHANGES.md` are historical records only.
- Current v1.2.13 release identity, hashes, and audit state are generated from `VERSION`, `INSTALLER_VERSION`, and the universal AI Audit bundle.

````


## FILE: source/SECURITY-NOTES.txt

SHA256: 85ba7a2aa2c127e12f830f96aa1787f237598fae20e3ae7543828552b161f469 | Bytes: 607 | Git mode: 100644

```
DevFleet intentionally does NOT:
- expose Docker over TCP;
- mount Windows folders, drives, SMB shares, or Google Drive into guests;
- mount Docker sockets into project containers;
- execute CodexPro hooks on the VM host;
- offer permanent deletion in the web dashboard;
- run docker system prune, docker volume prune, or compose down -v;
- run automatic restic forget/prune from compute nodes;
- automatically fail over when a peer is unreachable;
- give the dashboard VM/vault/Windows administration authority;
- store encrypted-bundle passphrases;
- bypass Tailscale or GitHub interactive authorization.

```


## FILE: source/START-HERE-DESKTOP.cmd

SHA256: 155b462f564dd1c2ae210029544d39194c14c0c85fb8062d31eb2a614e84d42f | Bytes: 232 | Git mode: 100644

```
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0Bootstrap-Install.ps1"" -Role Desktop'"
endlocal

```


## FILE: source/START-HERE-LAPTOP.cmd

SHA256: 97b7b3a91ffa320f1729e1662da3d615bf82bc6aa116e276c2bf373d0b6fd065 | Bytes: 231 | Git mode: 100644

```
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0Bootstrap-Install.ps1"" -Role Laptop'"
endlocal

```


## FILE: source/Upgrade-DevFleet.ps1

SHA256: 3905ac18b10325246b765a33daac907f548c000372a1144ef736f44ef9136b2a | Bytes: 3712 | Git mode: 100644

```
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][ValidateSet('1.0.0')][string]$FromVersion,[ValidateSet('Auto','Laptop','Desktop')][string]$Role='Auto',[switch]$PreviewOnly)
$ErrorActionPreference='Stop';$here=Split-Path -Parent $MyInvocation.MyCommand.Path;Import-Module (Join-Path $here 'windows\DevFleet.Common.psm1') -Force;Assert-PowerShell7;Assert-Administrator
$state=Get-DevFleetStateRoot;$configPath=Join-Path $state 'devfleet.config.json';if(-not(Test-Path $configPath)){throw 'No installed DevFleet configuration found.'};$old=Get-Content $configPath -Raw|ConvertFrom-Json;$schema=[int]$old.SchemaVersion;$version=[string]$old.PackageVersion;$isV10=($schema -eq 1 -and ([string]::IsNullOrWhiteSpace($version) -or $version -eq '1.0.0'));$isV11=($schema -eq 2 -and $version -eq '1.1.0');if(-not($isV10 -or $isV11)){throw "Unsupported source schema/package: $schema/$version"};$label=if($isV10){'v1.0.0'}else{'v1.1.0-rerun'};$stamp=(Get-Date).ToString('yyyyMMdd-HHmmss');$backup=Join-Path $state "upgrade-backups\$label-$stamp";New-Item -ItemType Directory $backup -Force|Out-Null;Copy-Item $configPath (Join-Path $backup 'devfleet.config.json');foreach($n in @('secrets','exports')){if(Test-Path(Join-Path $state $n)){Copy-Item (Join-Path $state $n) (Join-Path $backup $n) -Recurse -Force}};if(Test-Path(Join-Path $state 'package-root.txt')){Copy-Item (Join-Path $state 'package-root.txt') $backup}
& (Join-Path $here 'windows\Migrate-Config.ps1') -ConfigPath $configPath -OutputPath $configPath -PreviewOnly;if($PreviewOnly){Write-Host "Preview complete. Backup: $backup";return}
$instances=Get-MultipassInstances;$localNames=@($instances|ForEach-Object name);$targets=@();foreach($n in @([string]$old.Primary.InstanceName,[string]$old.Failover.InstanceName,[string]$old.Vault.InstanceName)){if($n -and $n -in $localNames){$targets+=$n}}
foreach($n in $targets){New-DevFleetSnapshotSafe -InstanceName $n -SnapshotName "pre-v1-1-0-$stamp"|Out-Null}
& (Join-Path $here 'windows\Migrate-Config.ps1') -ConfigPath $configPath -OutputPath $configPath -Confirm:$false;Protect-DevFleetStateAcl;Set-Content (Join-Path $state 'package-root.txt') $here -Encoding utf8;$config=Get-DevFleetConfig
if($config.Primary.InstanceName -in $localNames){& (Join-Path $here 'windows\02-Provision-ComputeNode.ps1') -NodeRole Primary};if($config.Failover.InstanceName -in $localNames){& (Join-Path $here 'windows\02-Provision-ComputeNode.ps1') -NodeRole Failover};if($config.Vault.InstanceName -in $localNames){& (Join-Path $here 'windows\03-Provision-Vault.ps1')}
$local=if($config.Primary.InstanceName -in $localNames){$config.Primary.InstanceName}elseif($config.Failover.InstanceName -in $localNames){$config.Failover.InstanceName}else{$null};if($local){& (Join-Path $here 'windows\08-Install-Shortcuts.ps1') -LocalInstanceName $local};if($Role -eq 'Laptop' -or ($Role -eq 'Auto' -and $config.Failover.InstanceName -in $localNames)){try{& (Join-Path $here 'client\Configure-SSH.ps1') -SkipConnectivityTest}catch{Write-Warning $_};try{& (Join-Path $here 'client\Configure-VSCode.ps1') -ExtensionSets core}catch{Write-Warning $_}}
& (Join-Path $here 'windows\Test-DevFleet.ps1') -AllLocalInstances;[ordered]@{From=$label;To='1.1.0';Completed=(Get-Date).ToString('o');StateBackup=$backup;Snapshots=$targets;Preserved='VMs, projects, Git repositories, both Docker stores, volumes, credentials, restic snapshots, vault data, Tailscale identities, SSH keys, dashboard credentials, pairing, quarantine and custom configuration'}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $backup 'upgrade-result.json') -Encoding utf8;Write-Host "DevFleet v1.1.0 upgrade complete. Recovery: $backup" -ForegroundColor Green

```


## FILE: source/VERSION

SHA256: c21698334b1e2308b8556ac1d10402342b8d3e837f65fa1c431eb23392824b1d | Bytes: 7 | Git mode: 100644

```
1.2.13

```


## FILE: source/app/devfleet/__init__.py

SHA256: 2736ff45f82f5c2ae6fd243801f786562d4ddfa6326f19cce66a72c6b9e28602 | Bytes: 33 | Git mode: 100644

```
from .version import __version__

```


## FILE: source/app/devfleet/analyzer.py

SHA256: 0ebb618f06b728c84a5e8cfeeb04485536824f11bce37e752f5ed9c9a160e785 | Bytes: 28948 | Git mode: 100644

```
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

import yaml

from .core import SETTINGS, atomic_json
from .metadata_io import read_project_metadata
from .profiles import get_profile


# The analyzer intentionally supports a reviewed subset instead of invoking a
# resolver on attacker-controlled files. Changing either identifier changes the
# analyzer's security boundary and therefore its cache identity.
ANALYZER_POLICY_VERSION = "2.0.0"
COMPOSE_SUPPORTED_SCHEMA = "compose-spec-safe-subset-2026-08"
DEVCONTAINER_SUPPORTED_SCHEMA = "devcontainer-json-safe-subset-2026-08"
MAX_REFERENCE_DEPTH = 8
MAX_REFERENCE_FILES = 256
MAX_REFERENCE_BYTES = 32 * 1024 * 1024

WINDOWS_PATH = re.compile(r"^[a-z]:[\\/]", re.I)
UNC_PATH = re.compile(r"^(?:\\\\|//)")
DOCKER_SOCKET = re.compile(r"(?:docker\.sock|/run/user/\d+/docker\.sock)", re.I)
RELEVANT_NAMES = {"compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml", "devcontainer.json", ".env", "project.json"}
COMPOSE_FILES = ("compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml", ".devcontainer/compose.yaml", ".devcontainer/docker-compose.yml")

# Current Docker Compose service keys. Unknown keys are blocking so a future
# execution-affecting field cannot silently disappear from review.
COMPOSE_SERVICE_KEYS = {
    "annotations", "attach", "build", "blkio_config", "cpu_count", "cpu_percent", "cpu_shares", "cpu_period",
    "cpu_quota", "cpu_rt_runtime", "cpu_rt_period", "cpus", "cpuset", "cap_add", "cap_drop", "cgroup",
    "cgroup_parent", "command", "configs", "container_name", "credential_spec", "depends_on", "deploy", "develop",
    "device_cgroup_rules", "devices", "dns", "dns_opt", "dns_search", "domainname", "entrypoint", "env_file",
    "environment", "expose", "external_links", "extra_hosts", "gpus", "group_add", "healthcheck", "hostname",
    "image", "init", "ipc", "isolation", "labels", "label_file", "links", "logging", "mac_address", "mem_limit",
    "mem_reservation", "mem_swappiness", "memswap_limit", "models", "network_mode", "networks", "oom_kill_disable",
    "oom_score_adj", "pid", "pids_limit", "platform", "ports", "post_start", "pre_start", "pre_stop", "privileged",
    "profiles", "provider", "pull_policy", "read_only", "restart", "runtime", "scale", "secrets", "security_opt",
    "shm_size", "stdin_open", "stop_grace_period", "stop_signal", "storage_opt", "sysctls", "tmpfs", "tty",
    "ulimits", "use_api_socket", "user", "userns_mode", "uts", "volumes", "volumes_from", "working_dir", "extends",
}
COMPOSE_TOP_LEVEL_KEYS = {"name", "version", "services", "networks", "volumes", "secrets", "configs", "models", "include"}
COMPOSE_UNSUPPORTED_KEYS = {
    "include", "extends", "use_api_socket", "volumes_from", "provider", "post_start", "pre_start", "pre_stop",
    "credential_spec", "runtime", "gpus", "device_cgroup_rules", "cgroup_parent", "sysctls", "tmpfs", "isolation",
}
COMPOSE_HOST_NAMESPACE_KEYS = {"network_mode", "pid", "ipc", "uts", "userns_mode"}

DEVCONTAINER_KEYS = {
    "name", "image", "dockerFile", "dockerfile", "context", "build", "dockerComposeFile", "service", "workspaceFolder",
    "workspaceMount", "shutdownAction", "overrideCommand", "remoteUser", "containerUser", "containerEnv", "remoteEnv",
    "mounts", "runArgs", "privileged", "capAdd", "securityOpt", "features", "overrideFeatureInstallOrder",
    "initializeCommand", "onCreateCommand", "updateContentCommand", "postCreateCommand", "postStartCommand",
    "postAttachCommand", "forwardPorts", "portsAttributes", "otherPortsAttributes", "appPort", "init", "customizations",
    "hostRequirements", "waitFor", "userEnvProbe", "secrets",
}


def finding(severity: str, code: str, message: str, file: str = "") -> dict[str, str]:
    return {"severity": severity, "code": code, "message": message, "file": file}


def _unsafe_source(source: str) -> str | None:
    source = source.strip()
    norm = source.replace("\\", "/")
    if not source:
        return "empty path"
    if "$" in source:
        return "environment-variable interpolation"
    if WINDOWS_PATH.search(source) or UNC_PATH.search(source):
        return "Windows/UNC host path"
    if DOCKER_SOCKET.search(source):
        return "Docker socket"
    if source.startswith(("/", "~")):
        return "absolute host path"
    if ".." in PurePosixPath(norm).parts:
        return "parent-directory traversal"
    return None


def _severity(profile: str, kind: str) -> str:
    p = get_profile(profile)
    if kind in {"hardening", "health"}:
        return "critical" if p.block_hardening else "warning"
    if kind in {"device", "privileged"}:
        return "warning" if p.name == "fast" else "critical"
    return "critical"


def _inside_project(project: Path, candidate: Path) -> bool:
    try:
        candidate.resolve(strict=False).relative_to(project.resolve())
        return True
    except ValueError:
        return False


def _contains_symlink(project: Path, candidate: Path) -> bool:
    try:
        relative = candidate.relative_to(project)
    except ValueError:
        return True
    current = project
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            return True
    return False


def _reference(project: Path, base: Path, raw: Any, rel: str, kind: str, findings: list[dict[str, str]], references: set[Path], *, required: bool = False) -> Path | None:
    path_code = "docker.mount-resolution" if kind == "bind mount source" else "docker.build-context" if kind == "build.context" else "compose.path-escape"
    value = str(raw or "").strip()
    reason = _unsafe_source(value)
    if reason:
        findings.append(finding("critical", "compose.path-reference", f"{kind} is unsafe ({reason}): {value!r}.", rel))
        return None
    candidate = (base / value).resolve(strict=False)
    if not _inside_project(project, candidate):
        findings.append(finding("critical", path_code, f"{kind} resolves outside the project boundary: {value!r}.", rel))
        return None
    lexical = base / value
    if _contains_symlink(project, lexical):
        findings.append(finding("critical", path_code, f"{kind} may not traverse a symlink: {value!r}.", rel))
        return None
    if required and not candidate.is_file():
        findings.append(finding("critical", "compose.missing-reference", f"Referenced {kind} does not exist: {value!r}.", rel))
        return None
    references.add(candidate)
    return candidate


def _short_bind_source(value: str) -> str | None:
    value = value.strip()
    if not value:
        return None
    if WINDOWS_PATH.search(value) or UNC_PATH.search(value) or DOCKER_SOCKET.search(value):
        return value
    if ":" not in value:
        return value if value.startswith((".", "..", "/", "~")) else None
    return value.split(":", 1)[0]


def _volume_source(value: Any) -> tuple[str, bool]:
    if isinstance(value, dict):
        kind = str(value.get("type", "volume")).lower()
        source = str(value.get("source") or value.get("src") or "")
        return source, kind == "bind"
    source = _short_bind_source(str(value))
    return source or "", source is not None


def _parse_yaml(path: Path) -> dict[str, Any] | None:
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return None
    return value if isinstance(value, dict) else None


def _iter_env_files(value: Any) -> Iterable[Any]:
    if isinstance(value, (str, dict)):
        return (value,)
    return value or ()


def _strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from _strings(key)
            yield from _strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)


def _preflight_compose(project: Path, path: Path, findings: list[dict[str, str]], references: set[Path], seen: set[Path], state: dict[str, int], depth: int) -> dict[str, Any] | None:
    rel = str(path.relative_to(project)) if _inside_project(project, path) else str(path)
    if depth > MAX_REFERENCE_DEPTH:
        findings.append(finding("critical", "compose.reference-depth", "Compose reference depth exceeds the bounded policy.", rel))
        return None
    path = path.resolve(strict=False)
    if path in seen:
        return _parse_yaml(path)
    if len(seen) >= MAX_REFERENCE_FILES:
        findings.append(finding("critical", "compose.reference-count", "Compose reference count exceeds the bounded policy.", rel))
        return None
    seen.add(path)
    if not path.is_file():
        findings.append(finding("critical", "compose.missing-reference", "Compose configuration is missing.", rel))
        return None
    state["bytes"] += path.stat().st_size
    if state["bytes"] > MAX_REFERENCE_BYTES:
        findings.append(finding("critical", "compose.reference-bytes", "Compose referenced input bytes exceed the bounded policy.", rel))
        return None
    data = _parse_yaml(path)
    if data is None:
        findings.append(finding("error", "yaml.invalid", "Compose configuration is not a YAML object.", rel))
        return None
    if any("${" in text for text in _strings(data)):
        findings.append(finding("critical", "compose.interpolation", "Compose environment interpolation is blocked in the security-reviewed subset.", rel))
    for key in data:
        if not str(key).startswith("x-") and key not in COMPOSE_TOP_LEVEL_KEYS:
            findings.append(finding("critical", "compose.unknown-field", f"Unreviewed top-level Compose field is blocked: {key!r}.", rel))
    includes = data.get("include")
    if includes:
        findings.append(finding("critical", "compose.include", "Compose include is blocked until a bounded resolver is certified.", rel))
        entries = includes if isinstance(includes, list) else [includes]
        for entry in entries:
            include_path = entry.get("path") if isinstance(entry, dict) else entry
            included = _reference(project, path.parent, include_path, rel, "Compose include", findings, references)
            if included and included.is_file():
                _preflight_compose(project, included, findings, references, seen, state, depth + 1)
    services = data.get("services") or {}
    if not isinstance(services, dict):
        findings.append(finding("error", "compose.services", "Compose services must be a mapping.", rel))
        return data
    for name, service in services.items():
        if not isinstance(service, dict):
            findings.append(finding("error", "compose.service", f"Compose service {name!r} must be a mapping.", rel))
            continue
        for key in service:
            if key not in COMPOSE_SERVICE_KEYS and not str(key).startswith("x-"):
                findings.append(finding("critical", "compose.unknown-field", f"Unreviewed service field is blocked: {name}.{key}.", rel))
        extends = service.get("extends")
        if extends:
            findings.append(finding("critical", "compose.extends", "Compose extends is blocked until effective-model resolution is certified.", rel))
            if isinstance(extends, dict) and extends.get("file"):
                inherited = _reference(project, path.parent, extends.get("file"), rel, "Compose extends file", findings, references)
                if inherited and inherited.is_file():
                    _preflight_compose(project, inherited, findings, references, seen, state, depth + 1)
        for env_file in _iter_env_files(service.get("env_file")):
            env_path = env_file.get("path") if isinstance(env_file, dict) else env_file
            _reference(project, path.parent, env_path, rel, "env_file", findings, references)
        build = service.get("build")
        if isinstance(build, str):
            _reference(project, path.parent, build, rel, "build.context", findings, references)
        elif isinstance(build, dict):
            context = build.get("context")
            if context:
                context_path = _reference(project, path.parent, context, rel, "build.context", findings, references)
                if context_path and build.get("dockerfile"):
                    _reference(project, context_path.parent, build.get("dockerfile"), rel, "build.dockerfile", findings, references, required=True)
        for volume in service.get("volumes") or ():
            source, is_bind = _volume_source(volume)
            if is_bind:
                _reference(project, path.parent, source, rel, "bind mount source", findings, references)
        for key in ("secrets", "configs"):
            value = service.get(key)
            if value:
                findings.append(finding("critical", "compose.secret-config", f"Service {name}.{key} is blocked until host-file authorization is certified.", rel))
    for key in ("secrets", "configs"):
        declarations = data.get(key)
        if isinstance(declarations, dict):
            for name, declaration in declarations.items():
                if isinstance(declaration, dict) and declaration.get("file"):
                    _reference(project, path.parent, declaration["file"], rel, f"{key}.{name} file", findings, references, required=True)
                if declaration:
                    findings.append(finding("critical", "compose.secret-config", f"Top-level {key}.{name} is blocked until host-file authorization is certified.", rel))
    return data


def _scan_compose_service(project: Path, path: Path, name: str, svc: dict[str, Any], profile: str, out: list[dict[str, str]]) -> None:
    rel = str(path.relative_to(project))
    metadata: dict[str, Any] = {}
    try:
        value = read_project_metadata(project).value
        metadata = value if isinstance(value, dict) else {}
    except Exception:
        pass
    for key in COMPOSE_UNSUPPORTED_KEYS:
        if key in svc and svc.get(key) not in (None, False, [], {}):
            out.append(finding("critical", f"compose.{key.replace('_', '-')}", f"{name}.{key} is blocked by the supported Compose security policy.", rel))
    if svc.get("container_name"):
        out.append(finding("critical" if profile == "strict" else "warning", "docker.container-name", f"{name}: explicit container_name can collide across projects.", rel))
    if svc.get("privileged") is True:
        severity = _severity(profile, "privileged")
        if profile == "fast" and not metadata.get("allow_privileged"):
            severity = "critical"
        out.append(finding(severity, "docker.privileged", f"{name}: privileged mode requires Fast Trusted plus project-level acknowledgement.", rel))
    for key in COMPOSE_HOST_NAMESPACE_KEYS:
        value = str(svc.get(key, "")).lower()
        if value == "host" or value.startswith(("container:", "service:")):
            out.append(finding("critical", "docker.host-namespace", f"{name}: {key}={value} is forbidden.", rel))
    caps = [str(x).upper() for x in (svc.get("cap_add") or [])]
    if caps:
        severity = _severity(profile, "device")
        if profile == "fast" and not metadata.get("allow_privileged"):
            severity = "critical"
        out.append(finding(severity, "docker.capabilities", f"{name}: capabilities require explicit reviewed acknowledgement: {caps}.", rel))
    if svc.get("devices"):
        severity = _severity(profile, "device")
        if profile == "fast" and not metadata.get("allow_devices"):
            severity = "critical"
        out.append(finding(severity, "docker.devices", f"{name}: device access requires Fast Trusted plus project-level acknowledgement.", rel))
    for volume in svc.get("volumes") or ():
        source, is_bind = _volume_source(volume)
        if is_bind:
            reason = _unsafe_source(source)
            if reason:
                out.append(finding("critical", "docker.mount", f"{name}: rejected {reason}: {source!r}.", rel))
    build = svc.get("build")
    if build:
        context = build if isinstance(build, str) else str(build.get("context", "."))
        reason = _unsafe_source(context)
        if reason and context not in {".", "./"}:
            out.append(finding("critical", "docker.build-context", f"{name}: rejected {reason}: {context}.", rel))
        if isinstance(build, dict) and build.get("privileged"):
            out.append(finding("critical", "docker.build-privileged", f"{name}: privileged image builds are blocked.", rel))
        if isinstance(build, dict) and build.get("secrets"):
            out.append(finding("critical", "docker.build-secrets", f"{name}: build secrets are blocked.", rel))
        context_path = (path.parent / context).resolve(strict=False)
        dockerfile_name = "Dockerfile" if isinstance(build, str) else str(build.get("dockerfile", "Dockerfile"))
        dockerfile = (context_path / dockerfile_name).resolve(strict=False)
        if _inside_project(project, dockerfile) and dockerfile.is_file():
            users = []
            for line in dockerfile.read_text(encoding="utf-8", errors="ignore").splitlines():
                parts = line.split(None, 1)
                if len(parts) == 2 and parts[0].upper() == "USER":
                    users.append(parts[1].strip())
            if not users or users[-1].lower() in {"root", "0", "0:0"}:
                out.append(finding(_severity(profile, "hardening"), "docker.non-root-user", f"{name}: Dockerfile does not finish with a non-root USER.", str(dockerfile.relative_to(project))))
    for env_file in _iter_env_files(svc.get("env_file")):
        value = str(env_file.get("path", "")) if isinstance(env_file, dict) else str(env_file)
        reason = _unsafe_source(value)
        if reason:
            out.append(finding("critical", "docker.env-file", f"{name}: unsafe env_file ({reason}): {value}.", rel))
    for port in svc.get("ports") or ():
        state, text = _port_state(port)
        if state == "public":
            out.append(finding("critical", "docker.port-public", f"{name}: public/unbound port publication is forbidden: {text}.", rel))
        elif state == "tailnet" and not (get_profile(profile).allow_tailnet and SETTINGS.allow_tailnet_ports):
            out.append(finding("critical", "docker.port-tailnet", f"{name}: tailnet port requires policy approval: {text}.", rel))
    if "healthcheck" not in svc:
        out.append(finding(_severity(profile, "health"), "docker.healthcheck", f"{name}: no container healthcheck is defined.", rel))
    image = str(svc.get("image", ""))
    if image.endswith(":latest") or (image and ":" not in image):
        out.append(finding(_severity(profile, "hardening"), "docker.unpinned-image", f"{name}: development image is not pinned.", rel))
    security = [str(x).lower() for x in (svc.get("security_opt") or [])]
    if any("unconfined" in x for x in security):
        out.append(finding("critical", "docker.unconfined", f"{name}: unconfined security profile is forbidden.", rel))
    if not any("no-new-privileges" in x for x in security):
        out.append(finding(_severity(profile, "hardening"), "docker.no-new-privileges", f"{name}: no-new-privileges is not set.", rel))


def _strip_jsonc(text: str) -> str:
    result: list[str] = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        char = text[i]
        if in_string:
            result.append(char)
            if escaped:
                escaped = False