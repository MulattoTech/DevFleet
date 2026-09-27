# DevFleet source part 105

Full-source UTF-8 byte interval [4836000, 4882500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 3dd5d4cd37e6312cd859b4a4a666eba1f6f2c3c5eecd77054c4d9a384679fa94

<!-- BEGIN SOURCE SLICE -->
e,
  [Parameter(Mandatory)][string]$OfflinePackageRoot,
  [ValidateSet('Offline','Connected')][string]$InstallationMode='Offline',
  [switch]$SkipWindowsUpdates
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7; Assert-Administrator

function Test-InstalledCommand([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
$manifest=Get-CanonicalDependencyManifest -PackageRoot $OfflinePackageRoot
function Get-OfflinePayload([string]$PackageId) {
  $manifestPath=Join-Path $OfflinePackageRoot 'OFFLINE-DEPENDENCIES.json'
  if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ throw 'Release-bound offline dependency manifest is missing.' }
  $offline=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if($offline.schemaVersion -ne 2 -or [string]$offline.devfleetVersion -ne '1.2.13' -or -not $offline.releaseBinding){ throw 'Offline dependency manifest is not bound to this DevFleet release.' }
  $entries=@($offline.payloads)
  $duplicateDependency=$entries | Group-Object dependencyId | Where-Object Count -ne 1
  $duplicateFile=$entries | Group-Object filename | Where-Object Count -ne 1
  if($duplicateDependency -or $duplicateFile){ throw 'Offline dependency manifest contains duplicate payload identities.' }
  # PowerShell unwraps a one-item pipeline result. Keep the exact-match
  # collection an array before reading Count so a valid singleton payload
  # cannot fail with a missing-property error.
  $entry=@($entries | Where-Object { [string]$_.dependencyId -eq $PackageId })
  if($entry.Count -ne 1){ throw "No exact release-bound offline payload exists for $PackageId. Connected mode is required for this target." }
  if([IO.Path]::IsPathRooted([string]$entry[0].filename) -or ([string]$entry[0].filename).Contains('..')){ throw 'Offline payload filename escapes the release package root.' }
  $payloadPath=Join-Path $OfflinePackageRoot ([string]$entry[0].filename)
  if(-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)){ throw "Exact offline payload is missing: $($entry[0].filename)." }
  $item=Get-Item -LiteralPath $payloadPath -Force
  if([int64]$item.Length -ne [int64]$entry[0].sizeBytes){ throw "Offline payload size mismatch for $($item.Name)." }
  $actual=(Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actual -ne ([string]$entry[0].sha256).ToLowerInvariant()){ throw "Offline prerequisite hash mismatch for $($item.Name)." }
  $allFiles=@(Get-ChildItem -LiteralPath $OfflinePackageRoot -File -Recurse | Where-Object Name -ne 'OFFLINE-DEPENDENCIES.json')
  $allowed=@($entries | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $OfflinePackageRoot ([string]$_.filename))) })
  if(@($allFiles | Where-Object { $allowed -notcontains $_.FullName }).Count -gt 0){ throw 'Unlisted offline payload files are rejected.' }
  return $payloadPath
}
function Install-OfflinePayload([string]$PackageId,[string[]]$Arguments) {
  $payload=Get-OfflinePayload $PackageId
  $dependency=@($manifest.dependencies)|Where-Object id -eq $PackageId|Select-Object -First 1
  if(-not $dependency){throw "Dependency id is not present in canonical manifest: $PackageId"}
  $strategy=Get-AuthenticityStrategy $dependency.installerAuthenticityPolicy
  if($strategy -ne 'VendorReleaseSha256'){Test-OfficialSigner -Path $payload -Policy $dependency.installerAuthenticityPolicy}
  $ext=[IO.Path]::GetExtension($payload).ToLowerInvariant()
  if($ext -eq '.msi') { $msiexec=Join-Path $env:WINDIR 'System32\msiexec.exe';if(-not (Test-TrustedExecutableCandidate $msiexec)){throw 'Trusted Windows Installer executable was not found.'};Invoke-External -FilePath $msiexec -ArgumentList (@('/i',$payload,'/qn','/norestart')) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') -AllowedExitCodes @(0,3010) | Out-Null }
  elseif($ext -eq '.exe') { Invoke-External -FilePath $payload -ArgumentList $Arguments -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'dependencyInstall') -AllowedExitCodes @(0,3010) | Out-Null }
  else { throw "Unsupported offline installer type for ${PackageId}: $ext" }
}
function Ensure-Dependency([string]$Id,[switch]$FeatureRequested) {
  $dependency=@($manifest.dependencies)|Where-Object id -eq $Id|Select-Object -First 1
  if(-not $dependency){throw "Dependency id is not present in canonical manifest: $Id"}
  $detected=if($Id -ceq 'multipass'){
    Wait-DevFleetDependencyStatus -Dependency $dependency -MaximumAttempts (Get-DevFleetDependencyProbeAttemptLimit -Dependency $dependency)
  }else{
    Get-DependencyStatus -Dependency $dependency
  }
  Write-Host "$($dependency.displayName): detected=$($detected.Version) path=$($detected.Path) status=$($detected.Status)" -ForegroundColor Cyan
   if($detected.Status -eq 'Compatible'){Write-Host "Preserving compatible prerequisite: $($dependency.displayName)";return}
  if(-not $dependency.required -and [string]$dependency.classification -in @('OPTIONAL','RECOMMENDED') -and -not $FeatureRequested){Write-Warning "$($dependency.displayName) is $($dependency.classification.ToLowerInvariant()) for core installation; leaving its feature unavailable rather than forcing acquisition.";return}
  if($detected.Status -eq 'Unsupported-Major'){throw "$($dependency.displayName) major version $($detected.Version) is outside the supported policy."}
  if($InstallationMode -eq 'Offline'){
    if($dependency.required){Install-OfflinePayload $dependency.wingetPackageId @()}
    else{Write-Warning "Optional prerequisite is absent or incompatible and no local payload was selected: $($dependency.displayName)"}
  }else{
    $health=Get-WingetHealth
    if($health.Status -eq 'Healthy' -and $dependency.wingetPackageId){
      try { Install-WingetPackage -Id $dependency.wingetPackageId -Upgrade:($detected.Status -eq 'Outdated') }
      catch {
        if($_.Exception.Message -notmatch '(?i)External command timed out' -or -not $dependency.directOfficialVendorResolver){throw}
        Write-Warning "WinGet stalled for $($dependency.displayName); switching to the authenticated official vendor resolver."
        Install-OfficialDependency -Dependency $dependency
      }
    }
    else{Write-Warning "WinGet $($health.Status); using direct official fallback for $($dependency.displayName).";Install-OfficialDependency -Dependency $dependency}
  }
  $after=if($Id -ceq 'multipass'){
    Wait-DevFleetDependencyStatus -Dependency $dependency -MaximumAttempts (Get-DevFleetDependencyProbeAttemptLimit -Dependency $dependency)
  }else{
    Get-DependencyStatus -Dependency $dependency
  }
  if($after.Status -notin @('Compatible')){throw "$($dependency.displayName) did not reach a compatible post-install state: $($after.Status) ($($after.Detail))"}
  Write-Host "Verified post-install: $($dependency.displayName) $($after.Version) at $($after.Path)" -ForegroundColor Green
}

function Install-VsCodeExtension([string]$CodeCli,[string]$Extension) {
  $cmd=Join-Path $env:WINDIR 'System32\cmd.exe'
  if(-not (Test-TrustedExecutableCandidate $cmd)){throw 'Trusted command interpreter was not found for the optional VS Code integration.'}
  $quotedCode='"'+$CodeCli.Replace('"','""')+'"'
  $quotedExtension='"'+$Extension.Replace('"','""')+'"'
  Invoke-External -FilePath $cmd -ArgumentList @('/d','/s','/c',"$quotedCode --install-extension $quotedExtension --force") -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'vscodeExtension') | Out-Null
}

function Invoke-MultipassConfigurationProbe([string]$Multipass,[string[]]$Arguments,[string]$FailureMessage) {
  $context=Get-DevFleetDeadlineContext
  $operationDeadline=[DateTime]::UtcNow.AddSeconds((Get-DevFleetOperationMaximumSeconds 'multipassConfiguration'))
  if($context -and ([datetime]$context.StageDeadlineUtc -lt $operationDeadline)){$operationDeadline=[datetime]$context.StageDeadlineUtc}
  # The configured operation deadline is the finite retry bound. A fixed
  # attempt count can expire during a transient Multipass daemon/backend
  # readiness window after a Hyper-V checkpoint restore even though the
  # inherited 600-second operation budget is still available.
  while([DateTime]::UtcNow -lt $operationDeadline){
    $remaining=[int][math]::Floor(($operationDeadline-[DateTime]::UtcNow).TotalSeconds)
    if($remaining -le 0){break}
    try {
      return (Invoke-External $Multipass $Arguments -Capture -TimeoutSeconds ([math]::Min(60,$remaining)) -DeadlineUtc $operationDeadline)
    } catch {
      $sleepSeconds=[math]::Min(1,[math]::Max(0,$remaining-1))
      if($sleepSeconds -gt 0){Start-Sleep -Seconds $sleepSeconds}
    }
  }
  throw $FailureMessage
}

Write-Host "`nInstalling/updating Windows prerequisites ($InstallationMode) ..." -ForegroundColor Cyan
Ensure-Dependency 'git'
Ensure-Dependency 'multipass'
Ensure-Dependency 'tailscale'
Ensure-Dependency 'github-cli'
Ensure-Dependency 'sevenzip'
Ensure-Dependency 'vscode'

$ssh=Get-WindowsCapability -Online | Where-Object Name -Like 'OpenSSH.Client*' | Select-Object -First 1
if(-not $ssh){ throw 'Windows OpenSSH Client capability was not found.' }
if($ssh.State -ne 'Installed'){
  if($InstallationMode -eq 'Offline'){ throw 'OpenSSH Client is not installed and Windows capability acquisition is not supported by this Full Offline profile.' }
  Add-WindowsCapability -Online -Name $ssh.Name | Out-Null
}

$edition=(Get-ComputerInfo -Property WindowsProductName).WindowsProductName
if($edition -match 'Pro|Enterprise|Education'){
  $feature=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
  if($feature.State -ne 'Enabled'){
    Write-Warning 'Enabling Hyper-V. A reboot will be required before VM provisioning.'
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart | Out-Null
  }
}else{
  Ensure-Dependency 'virtualbox' -FeatureRequested
}

if(-not (Test-PendingReboot)){
  $mp=Get-MultipassExe
  $desiredDriver=if($edition -match 'Pro|Enterprise|Education'){'hyperv'}else{'virtualbox'}
  # Verify the restored daemon state before writing it. Re-applying an already
  # selected driver can restart Multipass while a nested instance is starting,
  # leaving the control-plane socket unavailable to the following probe.
  $selectedDriver=([string](Invoke-MultipassConfigurationProbe $mp @('get','local.driver') 'Multipass did not become ready before driver verification.')).Trim()
  if($selectedDriver -ne $desiredDriver){
    Invoke-External $mp @('set',"local.driver=$desiredDriver") -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'multipassConfiguration')
    $selectedDriver=([string](Invoke-MultipassConfigurationProbe $mp @('get','local.driver') 'Multipass did not become ready after the driver setting was applied.')).Trim()
  }
  if($selectedDriver -ne $desiredDriver){throw "Multipass did not select the required driver: $selectedDriver (expected $desiredDriver)"}
  $selectedPrivilegedMounts=([string](Invoke-MultipassConfigurationProbe $mp @('get','local.privileged-mounts') 'Multipass did not become ready before privileged-mount verification.')).Trim()
  if($selectedPrivilegedMounts -ne 'false'){
    Invoke-External $mp @('set','local.privileged-mounts=false') -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'multipassConfiguration')
    Invoke-MultipassConfigurationProbe $mp @('get','local.privileged-mounts') 'Multipass did not become ready after privileged mounts were disabled.'
  }
}else{ Write-Warning 'Hypervisor configuration will finish automatically when this installer is re-run after reboot.' }

$code=Get-VsCodeCli
if($code){
  $vsixRoot=Join-Path $OfflinePackageRoot 'vsix'
  foreach($ext in @('ms-vscode-remote.remote-ssh','ms-vscode-remote.remote-containers','ms-vscode.remote-explorer')){
    if($InstallationMode -eq 'Offline'){
      $vsix=Get-ChildItem -LiteralPath $vsixRoot -Filter "*$ext*.vsix" -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if($vsix){ Install-VsCodeExtension $code $vsix.FullName } else { Write-Warning "Optional VS Code extension payload is absent: $ext" }
    }else{ Install-VsCodeExtension $code $ext }
  }
}else{ Write-Warning 'VS Code integration is optional and its CLI is not available.' }

if(-not $SkipWindowsUpdates){ Write-Host 'Windows Update is not forced automatically. Install pending Windows security updates, then reboot if Windows requests it.' -ForegroundColor Yellow }
# A prerequisite stage is not durably complete while servicing still requires a
# reboot.  Leaving the marker absent makes the resumed transaction rerun only
# this idempotent prerequisite stage and then advance normally.
if(-not (Test-PendingReboot)){ Write-StageMarker "prereqs-$Role" } else { Write-Warning 'Prerequisite stage remains pending until Windows servicing settles; no completion marker was written.' }

```


## FILE: source/windows/02-Provision-ComputeNode.ps1

SHA256: e06b31924cb383c9d6383c70376b89b49213248f1f09e61aef5dc15d8afff7d1 | Bytes: 9264 | Git mode: 100644

```
[CmdletBinding()]
param(
 [Parameter(Mandatory)][ValidateSet('Primary','Failover')][string]$NodeRole,
 [switch]$ForceReprovision,
 [string]$TransactionId,
 [string]$TransactionPayloadSha256,
 [string]$TransactionAction,
 [string]$TransactionRole,
 [string]$TransactionPreparedUtc
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7; Assert-Administrator
$deadlineContext=Get-DevFleetDeadlineContext
if(-not $deadlineContext){$fallbackDeadline=[DateTime]::UtcNow.AddSeconds((Get-DevFleetStageBudgetSeconds 'compute'));Set-DevFleetDeadlineContext -TransactionDeadlineUtc $fallbackDeadline -StageName 'compute' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'compute') | Out-Null}
$config=Get-DevFleetConfig
$node=if($NodeRole -eq 'Primary'){$config.Primary}else{$config.Failover}
$name=$node.InstanceName
$package=Get-PackageRootFromState
$packageVersion=(Get-Content -LiteralPath (Join-Path $package 'VERSION') -Raw).Trim()
$bootstrapSeconds=Get-DevFleetOperationMaximumSeconds 'guestBootstrap'
$expectedRole=if($NodeRole -eq 'Primary'){'Desktop'}else{'Laptop'}
$activeTransaction=Wait-ActiveDevFleetTransaction -ExpectedRole $expectedRole
if(-not $activeTransaction -and $TransactionId -and $TransactionPayloadSha256 -and $TransactionAction -and $TransactionRole -and $TransactionPreparedUtc){
 $propagated=[pscustomobject]@{transactionId=$TransactionId;payloadSha256=$TransactionPayloadSha256;action=$TransactionAction;role=$TransactionRole;preparedUtc=$TransactionPreparedUtc}
 if(Test-DevFleetTransactionBinding -Transaction $propagated -ExpectedRole $expectedRole){$activeTransaction=$propagated}
}
if(-not $activeTransaction) { throw 'Active DevFleet transaction is missing, malformed, or not bound to this compute role.' }
$bootstrapNodeRole=if($NodeRole -eq 'Failover'){'surrogate'}else{'primary'}
$bootstrapBoundary=New-DevFleetBootstrapBoundary -Kind compute -InstanceName $name -TransactionId ([string]$activeTransaction.transactionId) -PayloadSha256 ([string]$activeTransaction.payloadSha256) -BootstrapMaxSeconds $bootstrapSeconds -PackageVersion $packageVersion -NodeRole $bootstrapNodeRole
$mp=Get-MultipassExe
Write-StageMarker -Name $bootstrapBoundary.multipassResolvedStageName -Transaction $activeTransaction
Assert-MultipassIsolation -InstanceNames @($name)
Write-StageMarker -Name $bootstrapBoundary.isolationVerifiedStageName -Transaction $activeTransaction
$secrets=Get-OrCreateSecrets
$nodeIdentity=Get-OrCreateNodeIdentity -Role $(if($NodeRole -eq 'Primary'){'Desktop'}else{'Laptop'})

$instancePresent=Test-MultipassInstance $name
Write-StageMarker -Name $(if($instancePresent){$bootstrapBoundary.instancePresentStageName}else{$bootstrapBoundary.instanceAbsentStageName}) -Transaction $activeTransaction
if($instancePresent){
 if($ForceReprovision){ throw "Refusing automatic destruction of existing $name. Remove it manually only after verifying backups." }
 Write-Host "$name already exists; updating the DevFleet payload in place." -ForegroundColor Yellow
  Invoke-External $mp @('start',$name) -IgnoreExitCode
  Write-StageMarker -Name $bootstrapBoundary.instanceStartedStageName -Transaction $activeTransaction
  Wait-MultipassReady $name 1200
}else{
 $cloud=Join-Path (Get-DevFleetStateRoot) "tmp\cloud-$name.yaml"
 $template=Get-Content (Join-Path $package 'cloud-init\compute.yaml') -Raw
 $template=$template.Replace('__NODE_NAME__',(ConvertTo-YamlSingleQuotedScalar $name)).Replace('__NODE_ROLE__',(ConvertTo-YamlSingleQuotedScalar $NodeRole.ToLower())).Replace('__GIT_NAME_SHELL__',(ConvertTo-ShellSingleQuotedScalar $config.Git.UserName)).Replace('__GIT_EMAIL_SHELL__',(ConvertTo-ShellSingleQuotedScalar $config.Git.Email))
 Set-Content $cloud $template -Encoding utf8
  # PowerShell `if` is a statement, not an expression; resolve the owning
  # stage deadline before passing it to the fresh-launch recovery helper.
  $launchDeadline=[datetime]::MinValue
  if($deadlineContext){$launchDeadline=([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime()}
  try {
   Invoke-MultipassLaunchWithReadinessRecovery -InstanceName $name -LaunchArguments @('launch',[string]$node.UbuntuImage,'--name',$name,'--cpus',[string]$node.Cpus,'--memory',[string]$node.Memory,'--disk',[string]$node.Disk,'--cloud-init',$cloud) -ReadinessTimeoutSeconds 1200 -DeadlineUtc $launchDeadline -OnInstanceEstablished { param($launch) Write-StageMarker -Name $bootstrapBoundary.instanceLaunchedStageName -Transaction $activeTransaction }
  } catch {
   # Windows servicing can become reboot-pending while Multipass is inside its
   # bounded launch/recovery envelope. Preserve the original launch error for
   # the post-reboot attempt, but first return the native 3010 contract so the
   # installer advances the durable checkpoint instead of treating the stale
   # Hyper-V state as a terminal compute failure.
   if(Test-PendingReboot){Write-Warning 'Windows reported a new reboot requirement during compute launch. Re-run this same transaction after reboot; completed stages will be detected.';exit 3010}
   throw
  }
  if(Test-PendingReboot){Write-Warning 'Windows reported a new reboot requirement after compute launch. Re-run this same transaction after reboot; completed stages will be detected.';exit 3010}
}
Write-StageMarker -Name $bootstrapBoundary.instanceReadyStageName -Transaction $activeTransaction

$tmp=Join-Path (Get-DevFleetStateRoot) "tmp\payload-$name"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $tmp -Force | Out-Null
foreach($d in @('linux','app','templates')){ Copy-Item (Join-Path $package $d) $tmp -Recurse }
Copy-Item (Join-Path $package 'VERSION') (Join-Path $tmp 'VERSION')
$nodeSecrets=[ordered]@{
 NodeName=$name; NodeRole=$bootstrapNodeRole; FriendlyName=[string]$node.FriendlyName; PortalPort=$config.Network.PortalPort; DeploymentId=[string]$nodeIdentity.deployment_id; NodeId=[string]$nodeIdentity.node_id; CoordinatorNodeId=[string]$nodeIdentity.coordinator_node_id; ProtocolVersion=[int]$nodeIdentity.protocol_version
 AdminUser=$secrets.PortalAdminUser; AdminPassword=$secrets.PortalAdminPassword; ApiToken=$secrets.NodeApiToken
 GitName=$config.Git.UserName; GitEmail=$config.Git.Email; OllamaBaseUrl=($(if($config.Ollama.PreferredBaseUrl){$config.Ollama.PreferredBaseUrl}else{$config.Ollama.BaseUrl})); OllamaModel=$config.Ollama.Model; OllamaProfile=$config.Ollama.Profile
 DevelopmentProfile=$config.Development.Profile; DockerMode=($(if($NodeRole -eq 'Primary'){$config.Docker.PrimaryMode}else{$config.Docker.FailoverMode}))
 EnableSharedCaches=[bool]$config.Development.EnableSharedBuildCaches; EnableAnalyzerCache=[bool]$config.Development.EnableAnalyzerCache; AutoStartCodexPro=[bool]$config.Development.AutoStartCodexPro; AllowTailnetPorts=[bool]$config.Development.AllowTailnetPortPublishing; BackupBeforeRebuild=[bool]$config.Development.BackupBeforeRebuild; BackupBeforeQuarantine=[bool]$config.Development.BackupBeforeQuarantine
 BackupIntervalMinutes=[int]$config.Backup.IntervalMinutes
 PackageVersion=$packageVersion
}
$zip=Join-Path (Get-DevFleetStateRoot) "tmp\payload-$name.zip"
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip
$payloadDeadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetOperationMaximumSeconds 'payloadTransfer'))
$payloadContext=Get-DevFleetDeadlineContext
if($payloadContext -and ([datetime]$payloadContext.StageDeadlineUtc).ToUniversalTime() -lt $payloadDeadline){$payloadDeadline=([datetime]$payloadContext.StageDeadlineUtc).ToUniversalTime()}
try {
 Invoke-External $mp @('transfer',$zip,"${name}:/tmp/devfleet-payload.zip") -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') -DeadlineUtc $payloadDeadline
 Write-StageMarker -Name $bootstrapBoundary.payloadTransferredStageName -Transaction $activeTransaction
 Invoke-External $mp @('exec',$name,'--','bash','-lc',$bootstrapBoundary.extractionCommand) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') -DeadlineUtc $payloadDeadline
 Write-StageMarker -Name $bootstrapBoundary.payloadExtractedStageName -Transaction $activeTransaction
 $bootstrapDeadline=[datetime]::UtcNow.AddSeconds($bootstrapBoundary.bootstrapMaxSeconds)
 $bootstrapContext=Get-DevFleetDeadlineContext
 if($bootstrapContext -and ([datetime]$bootstrapContext.StageDeadlineUtc).ToUniversalTime() -lt $bootstrapDeadline){$bootstrapDeadline=([datetime]$bootstrapContext.StageDeadlineUtc).ToUniversalTime()}
 Invoke-MultipassWithStandardInput -FilePath $mp -InstanceName $name -CommandArgumentList @('bash','-lc',$bootstrapBoundary.bootstrapCommand) -TimeoutSeconds $bootstrapBoundary.bootstrapMaxSeconds -DeadlineUtc $bootstrapDeadline -StandardInputText ($nodeSecrets | ConvertTo-Json -Compress)
} finally {
 Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
 Remove-Item $zip -Force -ErrorAction SilentlyContinue
 $nodeSecrets=$null
}
Add-LocalSshKeyToInstance -InstanceName $name
Write-StageMarker -Name $bootstrapBoundary.completionStageName -Transaction $activeTransaction
Write-Host "$name provisioned. Portal credentials are stored under C:\ProgramData\DevFleet\secrets." -ForegroundColor Green

```


## FILE: source/windows/03-Provision-Vault.ps1

SHA256: 620c99ab23861ad44f74b5d79ceda9e79eba20feb89ff6694e0e548e2a5308c6 | Bytes: 7647 | Git mode: 100644

```
[CmdletBinding()]
param(
 [switch]$ForceReprovision,
 [string]$TransactionId,
 [string]$TransactionPayloadSha256,
 [string]$TransactionAction,
 [string]$TransactionRole,
 [string]$TransactionPreparedUtc
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7;Assert-Administrator
$deadlineContext=Get-DevFleetDeadlineContext
if(-not $deadlineContext){$fallbackDeadline=[DateTime]::UtcNow.AddSeconds((Get-DevFleetStageBudgetSeconds 'vault'));Set-DevFleetDeadlineContext -TransactionDeadlineUtc $fallbackDeadline -StageName 'vault' -StageBudgetSeconds (Get-DevFleetStageBudgetSeconds 'vault') | Out-Null}
$config=Get-DevFleetConfig;$v=$config.Vault;$name=$v.InstanceName;$package=Get-PackageRootFromState
$activeTransaction=Wait-ActiveDevFleetTransaction -ExpectedRole 'Laptop'
if(-not $activeTransaction -and $TransactionId -and $TransactionPayloadSha256 -and $TransactionAction -and $TransactionRole -and $TransactionPreparedUtc){
 $propagated=[pscustomobject]@{transactionId=$TransactionId;payloadSha256=$TransactionPayloadSha256;action=$TransactionAction;role=$TransactionRole;preparedUtc=$TransactionPreparedUtc}
 if(Test-DevFleetTransactionBinding -Transaction $propagated -ExpectedRole 'Laptop'){$activeTransaction=$propagated}
}
if(-not $activeTransaction){throw 'Active DevFleet transaction is missing, malformed, or not bound to the Vault role.'}
$bootstrapSeconds=Get-DevFleetOperationMaximumSeconds 'vaultBootstrap'
$bootstrapBoundary=New-DevFleetBootstrapBoundary -Kind vault -InstanceName $name -TransactionId ([string]$activeTransaction.transactionId) -PayloadSha256 ([string]$activeTransaction.payloadSha256) -BootstrapMaxSeconds $bootstrapSeconds -PackageVersion 'vault' -NodeRole 'vault'
$mp=Get-MultipassExe
Write-StageMarker -Name $bootstrapBoundary.multipassResolvedStageName -Transaction $activeTransaction
Assert-MultipassIsolation -InstanceNames @($name)
Write-StageMarker -Name $bootstrapBoundary.isolationVerifiedStageName -Transaction $activeTransaction
$secrets=Get-OrCreateSecrets;$vaultIdentity=Get-OrCreateVaultIdentity
$instancePresent=Test-MultipassInstance $name
Write-StageMarker -Name $(if($instancePresent){$bootstrapBoundary.instancePresentStageName}else{$bootstrapBoundary.instanceAbsentStageName}) -Transaction $activeTransaction
if($instancePresent){
 if($ForceReprovision){throw 'Refusing automatic destruction of an existing backup vault.'}
  New-DevFleetSnapshotSafe -InstanceName $name -SnapshotName "pre-refresh-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"|Out-Null
  Invoke-External $mp @('start',$name) -IgnoreExitCode
  Write-StageMarker -Name $bootstrapBoundary.instanceStartedStageName -Transaction $activeTransaction
 Wait-MultipassReady $name 1200
 Write-Host "$name already exists; refreshing safe configuration." -ForegroundColor Yellow
}else{
 $cloud=Join-Path (Get-DevFleetStateRoot) "tmp\cloud-$name.yaml"
 $dependencyPolicy=Get-Content -LiteralPath (Join-Path $package 'linux/dependency-policy.json') -Raw|ConvertFrom-Json
 $tailscaleFingerprint=[string]$dependencyPolicy.tailscale.signingKeySha256Fingerprint
 if($tailscaleFingerprint-notmatch'^[A-F0-9]{40}$'){throw 'Canonical Tailscale signing-key fingerprint is invalid.'}
 (Get-Content (Join-Path $package 'cloud-init\vault.yaml') -Raw).Replace('__NODE_NAME__',(ConvertTo-YamlSingleQuotedScalar $name)).Replace('__TAILSCALE_SIGNING_FINGERPRINT__',$tailscaleFingerprint)|Set-Content $cloud -Encoding utf8
  # PowerShell `if` is a statement, not an expression; resolve the owning
  # stage deadline before passing it to the fresh-launch recovery helper.
  $launchDeadline=[datetime]::MinValue
  if($deadlineContext){$launchDeadline=([datetime]$deadlineContext.StageDeadlineUtc).ToUniversalTime()}
  Invoke-MultipassLaunchWithReadinessRecovery -InstanceName $name -LaunchArguments @('launch',[string]$v.UbuntuImage,'--name',$name,'--cpus',[string]$v.Cpus,'--memory',[string]$v.Memory,'--disk',[string]$v.Disk,'--cloud-init',$cloud) -ReadinessTimeoutSeconds 1200 -DeadlineUtc $launchDeadline -OnInstanceEstablished { param($launch) Write-StageMarker -Name $bootstrapBoundary.instanceLaunchedStageName -Transaction $activeTransaction }
}
Write-StageMarker -Name $bootstrapBoundary.instanceReadyStageName -Transaction $activeTransaction
if($instancePresent){
 $client=Invoke-External $mp @('exec',$name,'--','sh','-c','if command -v tailscale >/dev/null 2>&1; then printf PRESENT; else printf ABSENT; fi') -Capture -TimeoutSeconds 20
 if($client-cne'PRESENT'){throw 'The existing Vault is missing its Tailscale client. Restore the client from the verified signed repository before running Repair; the existing Vault and backups have been preserved.'}
}
# Vault bootstrap and client configuration require an authenticated tailnet.
# Fresh cloud-init installs the verified client; pair before transferring secrets
# or starting bootstrap stages that depend on tailscale0 and its private IP.
& (Join-Path $PSScriptRoot '04-Connect-Tailscale.ps1') -InstanceName $name
$tmp=Join-Path (Get-DevFleetStateRoot) 'tmp\vault-payload';Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue;New-Item -ItemType Directory $tmp -Force|Out-Null
Copy-Item (Join-Path $package 'linux') $tmp -Recurse
$vaultSecrets=[ordered]@{VaultPort=$config.Network.VaultPort;RestUser=$secrets.VaultRestUser;RestPassword=$secrets.VaultRestPassword;ResticPassword=$secrets.ResticPassword;ClusterName=$config.ClusterName;DeploymentId=$vaultIdentity.deployment_id;NodeId=$vaultIdentity.node_id;NodeName=$vaultIdentity.node_name}|ConvertTo-Json -Compress
$zip=Join-Path (Get-DevFleetStateRoot) 'tmp\vault-payload.zip';Remove-Item $zip -Force -ErrorAction SilentlyContinue;Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip
$payloadDeadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetOperationMaximumSeconds 'payloadTransfer'))
$payloadContext=Get-DevFleetDeadlineContext
if($payloadContext -and ([datetime]$payloadContext.StageDeadlineUtc).ToUniversalTime() -lt $payloadDeadline){$payloadDeadline=([datetime]$payloadContext.StageDeadlineUtc).ToUniversalTime()}
try {
 Invoke-External $mp @('transfer',$zip,"${name}:/tmp/devfleet-vault-payload.zip") -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') -DeadlineUtc $payloadDeadline
 Write-StageMarker -Name $bootstrapBoundary.payloadTransferredStageName -Transaction $activeTransaction
 Invoke-External $mp @('exec',$name,'--','bash','-lc',$bootstrapBoundary.extractionCommand) -TimeoutSeconds (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') -DeadlineUtc $payloadDeadline
 Write-StageMarker -Name $bootstrapBoundary.payloadExtractedStageName -Transaction $activeTransaction
 $bootstrapDeadline=[datetime]::UtcNow.AddSeconds($bootstrapBoundary.bootstrapMaxSeconds)
 $bootstrapContext=Get-DevFleetDeadlineContext
 if($bootstrapContext -and ([datetime]$bootstrapContext.StageDeadlineUtc).ToUniversalTime() -lt $bootstrapDeadline){$bootstrapDeadline=([datetime]$bootstrapContext.StageDeadlineUtc).ToUniversalTime()}
 Invoke-MultipassWithStandardInput -FilePath $mp -InstanceName $name -CommandArgumentList @('bash','-lc',$bootstrapBoundary.bootstrapCommand) -TimeoutSeconds $bootstrapBoundary.bootstrapMaxSeconds -DeadlineUtc $bootstrapDeadline -StandardInputText $vaultSecrets
} finally {
 Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
 Remove-Item $zip -Force -ErrorAction SilentlyContinue
 $vaultSecrets=$null
}
Write-StageMarker -Name $bootstrapBoundary.completionStageName -Transaction $activeTransaction;Write-Host "$name provisioned. Do not delete or purge this instance." -ForegroundColor Green

```


## FILE: source/windows/04-Connect-Tailscale.ps1

SHA256: a8c18e358eeeeb4c00058fc893f165c2d47f90015e06abde8265bd7ae98b077b | Bytes: 1873 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$')][string]$InstanceName)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Tailscale.psm1') -Force
$mp=Get-MultipassExe
$deadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetStageBudgetSeconds 'tailscale'))
$activeTransaction = $null
try { $activeTransaction = Get-ActiveDevFleetTransaction } catch { }
$transactionId = if ($activeTransaction) { [string]$activeTransaction.transactionId } else { '' }
$payloadSha256 = if ($activeTransaction) { [string]$activeTransaction.payloadSha256 } else { '' }
$evidenceName = if ($transactionId -match '^[0-9a-fA-F]{32}$') { "setup-tailscale-pairing-$transactionId.log" } else { "setup-tailscale-pairing-pid-$PID.log" }
$evidencePath = Join-Path (Join-Path $env:ProgramData 'M-TechLabs\DevFleet\Logs') $evidenceName
$profile=Get-DevFleetTailscaleEnrollmentProfile
$expectedPeer=if([string]$profile.hostName){[string]$profile.hostName}else{"$env:COMPUTERNAME-devfleet-host"}
try {
    $result=Invoke-DevFleetTailscaleOAuthPairing -FilePath $mp -InstanceName $InstanceName -Hostname $InstanceName -ExpectedPeer $expectedPeer -DeadlineUtc $deadline -EvidencePath $evidencePath -RunId ([string]$env:DEVFLEET_RUN_ID) -TransactionId $transactionId -PayloadSha256 $payloadSha256 -StageName 'tailscale' -TargetRole 'Guest' -PendingRebootProvider { Test-PendingReboot }
} catch {
    if ([string]$_.Exception.Message -match '^DEVFLEET_REBOOT_REQUIRED:') {
        Write-Warning "Windows servicing requires a reboot during guest Tailscale stage for $InstanceName; returning 3010 before Vault completion is published."
        exit 3010
    }
    throw
}
Write-Host "$InstanceName authenticated Tailscale IP: $($result.ipv4)" -ForegroundColor Green

```


## FILE: source/windows/04a-Connect-WindowsTailscale.ps1

SHA256: 361255d8773a9de440bac3007db55635a7940e49409d77f9245651df44c3585b | Bytes: 1720 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Tailscale.psm1') -Force
Assert-Administrator
$service=Get-Service -Name Tailscale -ErrorAction SilentlyContinue
$ts=Get-TailscaleExe
$deadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetStageBudgetSeconds 'windowsTailscale'))
$activeTransaction = $null
try { $activeTransaction = Get-ActiveDevFleetTransaction } catch { }
$transactionId = if ($activeTransaction) { [string]$activeTransaction.transactionId } else { '' }
$payloadSha256 = if ($activeTransaction) { [string]$activeTransaction.payloadSha256 } else { '' }
$evidenceName = if ($transactionId -match '^[0-9a-fA-F]{32}$') { "setup-tailscale-pairing-$transactionId.log" } else { "setup-tailscale-pairing-pid-$PID.log" }
$evidencePath = Join-Path (Join-Path $env:ProgramData 'M-TechLabs\DevFleet\Logs') $evidenceName
$hostname = ("{0}-devfleet-host" -f $env:COMPUTERNAME.ToLower())
try {
    $result=Invoke-DevFleetTailscaleOAuthPairing -FilePath $ts -Hostname $hostname -DeadlineUtc $deadline -EvidencePath $evidencePath -RunId ([string]$env:DEVFLEET_RUN_ID) -TransactionId $transactionId -PayloadSha256 $payloadSha256 -StageName 'windows-tailscale' -TargetRole 'Host' -PendingRebootProvider { Test-PendingReboot }
} catch {
    if ([string]$_.Exception.Message -match '^DEVFLEET_REBOOT_REQUIRED:') {
        Write-Warning 'Windows servicing requires a reboot during the Tailscale stage; returning 3010 before the stage marker is written.'
        exit 3010
    }
    throw
}
Write-Host "Windows host $env:COMPUTERNAME authenticated Tailscale IP: $($result.ipv4)" -ForegroundColor Green

```


## FILE: source/windows/05-Configure-LocalVaultClient.ps1

SHA256: 9687c9be4a3bf40a2e1481cd402c7d4118aaa0c4533e9037244b7bb3a25e0c62 | Bytes: 1235 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstanceName)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$secrets=Get-OrCreateSecrets;$mp=Get-MultipassExe
$vaultIp=Get-InstanceIPv4 $config.Vault.InstanceName -PreferTailscale
$pairingMode=if($vaultIp -match '^100\.'){'tailscale'}else{throw 'Authenticated Vault transport requires a Tailscale address; plaintext LAN fallback is disabled.'}
$obj=[ordered]@{Repository="rest:http://${vaultIp}:$($config.Network.VaultPort)/$($secrets.VaultRestUser)/$($config.ClusterName)";RestUser=$secrets.VaultRestUser;RestPassword=$secrets.VaultRestPassword;ResticPassword=$secrets.ResticPassword;VaultIp=$vaultIp;VaultPort=$config.Network.VaultPort;PairingMode=$pairingMode}
$tmp=Join-Path (Get-DevFleetStateRoot) 'secrets\vault-client.json';$obj|ConvertTo-Json|Set-Content $tmp -Encoding utf8
Protect-DevFleetStateAcl
Invoke-External $mp @('transfer',$tmp,"${InstanceName}:/tmp/vault-client.json")
Invoke-External $mp @('exec',$InstanceName,'--','sudo','/usr/local/sbin/devfleet-configure-backup','/tmp/vault-client.json')
Write-Host "Append-only backups configured for $InstanceName." -ForegroundColor Green

```


## FILE: source/windows/06-Import-Laptop-Bootstrap.ps1

SHA256: e38b19b780ca0a6ef94aba9a71a225d4a6cc28d5c3fe6c80333f7fa0d00c8452 | Bytes: 2442 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateScript({Test-Path $_})][string]$BundlePath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$mp=Get-MultipassExe;$dest=Join-Path (Get-DevFleetStateRoot) 'tmp\import-laptop';$peerFile=$null;Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
Expand-EncryptedBundle -BundlePath $BundlePath -Destination $dest
try {
$vault=Get-Content (Join-Path $dest 'vault-client.json') -Raw|ConvertFrom-Json
$tmp=Join-Path (Get-DevFleetStateRoot) 'secrets\vault-client.json';$vault|ConvertTo-Json|Set-Content $tmp -Encoding utf8
Protect-DevFleetStateAcl
$name=$config.Primary.InstanceName
Invoke-External $mp @('transfer',$tmp,"${name}:/tmp/vault-client.json")
Invoke-External $mp @('exec',$name,'--','sudo','/usr/local/sbin/devfleet-configure-backup','/tmp/vault-client.json')
$peer=Get-Content (Join-Path $dest 'failover-pairing.json') -Raw|ConvertFrom-Json
$surrogate=Get-Content (Join-Path $dest 'surrogate-node.json') -Raw|ConvertFrom-Json
$primaryIdentity=Get-OrCreateNodeIdentity -Role Desktop
if($surrogate.node_role -ne 'surrogate' -or -not $surrogate.node_id -or -not $primaryIdentity.deployment_id){throw 'Surrogate or Primary registration metadata is incomplete.'}
$surrogate.deployment_id=$primaryIdentity.deployment_id;$surrogate.coordinator_node_id=$primaryIdentity.node_id;$surrogate.protocol_version=$primaryIdentity.protocol_version
$peerFile=Join-Path (Get-DevFleetStateRoot) 'tmp\peer.json';$peer|ConvertTo-Json|Set-Content $peerFile -Encoding utf8
Invoke-External $mp @('transfer',$peerFile,"${name}:/tmp/peer.json")
Invoke-External $mp @('exec',$name,'--','sudo','/usr/local/sbin/devfleet-set-peer','/tmp/peer.json')
$nodeFile=Join-Path (Get-DevFleetStateRoot) 'tmp\surrogate-node.json';$surrogate|ConvertTo-Json|Set-Content $nodeFile -Encoding utf8
Invoke-External $mp @('transfer',$nodeFile,"${name}:/tmp/surrogate-node.json")
Invoke-External $mp @('exec',$name,'--','sudo','/usr/local/sbin/devfleet-register-node','/tmp/surrogate-node.json')
Add-LocalSshKeyToInstance -InstanceName $name -PublicKeyPath (Join-Path $dest 'laptop-client.pub')
Write-Host 'Vault and failover peer imported into the primary node.' -ForegroundColor Green
} finally {
 Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
 if($peerFile){Remove-Item $peerFile -Force -ErrorAction SilentlyContinue}
}

```


## FILE: source/windows/08-Install-Shortcuts.ps1

SHA256: e8295df36470ee12ca2ea696195bbee0e64333ddce1c45f80aae3a2f37844a5f | Bytes: 2685 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$LocalInstanceName)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$pkg=Get-PackageRootFromState;$pwsh=Get-DevFleetPowerShell
$launcher=Join-Path $pkg 'windows\Start-DevFleet.ps1'
New-DesktopShortcut -Name 'DevFleet - Open Dashboard' -Target $pwsh -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -InstanceName `"$LocalInstanceName`" -Mode Dashboard" -WorkingDirectory $pkg
New-DesktopShortcut -Name 'DevFleet - Open VS Code' -Target $pwsh -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -InstanceName `"$LocalInstanceName`" -Mode VSCode" -WorkingDirectory $pkg -IconLocation 'shell32.dll,220'
New-DesktopShortcut -Name 'DevFleet - Health Check' -Target $pwsh -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pkg 'windows\Test-DevFleet.ps1')`" -AllLocalInstances" -WorkingDirectory $pkg -IconLocation 'shell32.dll,167'
New-DesktopShortcut -Name 'DevFleet - Repair Safely' -Target $pwsh -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pkg 'windows\Repair-DevFleet.ps1')`" -InstanceName `"$LocalInstanceName`"" -WorkingDirectory $pkg -IconLocation 'shell32.dll,316'
New-DesktopShortcut -Name 'DevFleet - Update Safely' -Target $pwsh -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pkg 'windows\Update-DevFleet.ps1')`" -InstanceName `"$LocalInstanceName`"" -WorkingDirectory $pkg -IconLocation 'shell32.dll,238'

New-DesktopShortcut -Name 'DevFleet - Show Credentials' -Target $pwsh -Arguments "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pkg 'windows\Show-DevFleet-Credentials.ps1')`"" -WorkingDirectory $pkg -IconLocation 'shell32.dll,48'
New-DesktopShortcut -Name 'DevFleet - Stop Compute Safely' -Target $pwsh -Arguments "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pkg 'windows\Stop-DevFleet.ps1')`" -InstanceName `"$LocalInstanceName`"" -WorkingDirectory $pkg -IconLocation 'shell32.dll,28'

$config=Get-DevFleetConfig
if(Test-MultipassInstance $config.Vault.InstanceName){
  New-DesktopShortcut -Name 'DevFleet - Export Offline Vault Copy' -Target $pwsh -Arguments "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pkg 'windows\Export-Vault-OfflineCopy.ps1')`"" -WorkingDirectory $pkg -IconLocation 'shell32.dll,167'
  New-DesktopShortcut -Name 'DevFleet - Update Vault Safely' -Target $pwsh -Arguments "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pkg 'windows\Update-Vault.ps1')`"" -WorkingDirectory $pkg -IconLocation 'shell32.dll,238'
}
Write-Host 'Desktop shortcuts created.' -ForegroundColor Green

```


## FILE: source/windows/09-Export-Laptop-Bootstrap.ps1

SHA256: 806d2edbce838681979ac40678aeb452e2f6e0be87b2baafc307adb3813073c4 | Bytes: 2000 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$secrets=Get-OrCreateSecrets;$mp=Get-MultipassExe;$identity=Get-OrCreateNodeIdentity -Role Laptop
$vaultIp=Get-InstanceIPv4 $config.Vault.InstanceName -PreferTailscale
$failIp=Get-InstanceIPv4 $config.Failover.InstanceName -PreferTailscale
if($vaultIp -notmatch '^100\.' -or $failIp -notmatch '^100\.' ){throw 'Vault/failover export requires authenticated Tailscale addresses.'}
$dir=Join-Path (Get-DevFleetStateRoot) 'tmp\export-laptop';Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue;New-Item -ItemType Directory $dir -Force|Out-Null
[ordered]@{Repository="rest:http://${vaultIp}:$($config.Network.VaultPort)/$($secrets.VaultRestUser)/$($config.ClusterName)";RestUser=$secrets.VaultRestUser;RestPassword=$secrets.VaultRestPassword;ResticPassword=$secrets.ResticPassword;VaultIp=$vaultIp;VaultPort=$config.Network.VaultPort}|ConvertTo-Json|Set-Content (Join-Path $dir 'vault-client.json') -Encoding utf8
[ordered]@{Name=$config.Failover.InstanceName;Url="http://${failIp}:$($config.Network.PortalPort)";Token=$secrets.NodeApiToken}|ConvertTo-Json|Set-Content (Join-Path $dir 'failover-pairing.json') -Encoding utf8
[ordered]@{deployment_id=$identity.deployment_id;node_id=$identity.node_id;node_name=$identity.node_name;node_role=$identity.node_role;coordinator_node_id=$identity.coordinator_node_id;protocol_version=$identity.protocol_version}|ConvertTo-Json|Set-Content (Join-Path $dir 'surrogate-node.json') -Encoding utf8
Copy-Item "$(Get-OrCreateDevFleetSshKey).pub" (Join-Path $dir 'laptop-client.pub')
$out=Join-Path (Get-DevFleetStateRoot) "exports\devfleet-laptop-bootstrap-$((Get-Date).ToString('yyyyMMdd-HHmmss')).dfe"
try{New-EncryptedBundle -SourceDirectory $dir -OutputPath $out}finally{Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host "Laptop bootstrap bundle: $out" -ForegroundColor Green

```


## FILE: source/windows/10-Export-Desktop-Pairing.ps1

SHA256: a20531c8ca0e0e2a85a720a0089b97fc769410b2246a93443014074e17ea45ee | Bytes: 1877 | Git mode: 100644

```
[CmdletBinding()]
param([switch]$NonInteractive,[Security.SecureString]$BundlePassphrase)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
if($NonInteractive -and $null -eq $BundlePassphrase){Write-Warning 'Desktop pairing export was deferred because this installation chain is noninteractive. Run the supported Maintenance pairing workflow to create the encrypted bundle.';return}
$config=Get-DevFleetConfig;$secrets=Get-OrCreateSecrets;$identity=Get-OrCreateNodeIdentity -Role Desktop
if(-not $identity.deployment_id -or $identity.node_role -ne 'primary'){throw 'Primary deployment identity is missing or not a Primary.'}
$ip=Get-InstanceIPv4 $config.Primary.InstanceName -PreferTailscale
if(-not $ip){throw 'Primary Tailscale address is unavailable.'}
$dir=Join-Path (Get-DevFleetStateRoot) 'tmp\export-desktop';Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue;New-Item -ItemType Directory $dir -Force|Out-Null
[ordered]@{Name=$config.Primary.InstanceName;Url="http://${ip}:$($config.Network.PortalPort)";Token=$secrets.NodeApiToken}|ConvertTo-Json|Set-Content (Join-Path $dir 'primary-pairing.json') -Encoding utf8
[ordered]@{deployment_id=$identity.deployment_id;node_id=$identity.node_id;node_name=$identity.node_name;node_role=$identity.node_role;protocol_version=$identity.protocol_version}|ConvertTo-Json|Set-Content (Join-Path $dir 'primary-node.json') -Encoding utf8
Copy-Item "$(Get-OrCreateDevFleetSshKey).pub" (Join-Path $dir 'desktop-client.pub')
$out=Join-Path (Get-DevFleetStateRoot) "exports\devfleet-desktop-pairing-$((Get-Date).ToString('yyyyMMdd-HHmmss')).dfe"
try{New-EncryptedBundle -SourceDirectory $dir -OutputPath $out -Passphrase $BundlePassphrase}finally{Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host "Desktop pairing bundle: $out" -ForegroundColor Green

```


## FILE: source/windows/Complete-Cluster.ps1

SHA256: 0168e428da1749b5ece2d61eb2df324fab835424e3d1de4af9576aea6e4baf74 | Bytes: 4180 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateScript({Test-Path $_})][string]$DesktopPairingBundlePath,[Security.SecureString]$BundlePassphrase)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$mp=Get-MultipassExe;$dest=Join-Path (Get-DevFleetStateRoot) 'tmp\import-desktop';$tmp=$null;Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
try {
Expand-EncryptedBundle -BundlePath $DesktopPairingBundlePath -Destination $dest -Passphrase $BundlePassphrase
$peer=Get-Content (Join-Path $dest 'primary-pairing.json') -Raw|ConvertFrom-Json
$primaryNode=Get-Content (Join-Path $dest 'primary-node.json') -Raw|ConvertFrom-Json
if($primaryNode.node_role -ne 'primary' -or -not $primaryNode.deployment_id -or -not $primaryNode.node_id){throw 'Primary invitation metadata is incomplete.'}
$tmp=Join-Path (Get-DevFleetStateRoot) 'tmp\primary-peer.json';$peer|ConvertTo-Json|Set-Content $tmp -Encoding utf8
$name=$config.Failover.InstanceName
Invoke-External $mp @('transfer',$tmp,"${name}:/tmp/peer.json")
Invoke-External $mp @('exec',$name,'--','sudo','/usr/local/sbin/devfleet-set-peer','/tmp/peer.json')
