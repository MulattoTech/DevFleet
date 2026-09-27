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
