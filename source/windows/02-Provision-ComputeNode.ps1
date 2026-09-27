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
