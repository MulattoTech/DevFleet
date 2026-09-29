# DevFleet source part 107

Full-source UTF-8 byte interval [4929000, 4975500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 647c807cd75728680265a63bb0afb3303f38cb82e1dfaf39bbb59d24e70c85a4

<!-- BEGIN SOURCE SLICE -->
ool]$config.Development.AllowTailnetPortPublishing; BackupBeforeRebuild=[bool]$config.Development.BackupBeforeRebuild; BackupBeforeQuarantine=[bool]$config.Development.BackupBeforeQuarantine
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
$nodeFile=Join-Path (Get-DevFleetStateRoot) 'tmp\primary-node.json';$primaryNode|ConvertTo-Json|Set-Content $nodeFile -Encoding utf8
Invoke-External $mp @('transfer',$nodeFile,"${name}:/tmp/primary-node.json")
Invoke-External $mp @('exec',$name,'--','sudo','/usr/local/sbin/devfleet-join-deployment','/tmp/primary-node.json')
$hostIdentityPath=Join-Path (Get-DevFleetStateRoot) 'node-identity.json'
$hostIdentity=Get-Content -LiteralPath $hostIdentityPath -Raw|ConvertFrom-Json
if($hostIdentity.node_role -ne 'surrogate' -or -not $hostIdentity.node_id){throw 'Local surrogate identity is incomplete.'}
$hostIdentity.deployment_id=[string]$primaryNode.deployment_id;$hostIdentity.coordinator_node_id=[string]$primaryNode.node_id;$hostIdentity.registration_state='joined'
$vaultIdentity=Get-OrCreateVaultIdentity
$vaultIdentity.deployment_id=[string]$primaryNode.deployment_id
$vaultIdentityPath=Join-Path (Get-DevFleetStateRoot) 'vault-node-identity.json'
$vaultIdentity|ConvertTo-Json|Set-Content -LiteralPath $vaultIdentityPath -Encoding utf8
$vaultName=[string]$config.Vault.InstanceName
if(Test-MultipassInstance $vaultName){
 $vaultPublic=(Invoke-External $mp @('exec',$vaultName,'--','sudo','cat','/etc/devfleet-vault-public.json') -Capture)|ConvertFrom-Json
 $localSecrets=Get-OrCreateSecrets
 if([string]$vaultPublic.cluster -ne [string]$config.ClusterName -or [string]$vaultPublic.user -ne [string]$localSecrets.VaultRestUser){throw 'Vault legacy adoption identity does not match the exact local cluster/credential binding.'}
 $vaultIdentityTransfer=Join-Path (Get-DevFleetStateRoot) 'tmp\vault-node-identity.json';$vaultIdentity|ConvertTo-Json|Set-Content -LiteralPath $vaultIdentityTransfer -Encoding utf8
 Invoke-External $mp @('transfer',$vaultIdentityTransfer,"${vaultName}:/tmp/devfleet-vault-identity.json")
 Invoke-External $mp @('exec',$vaultName,'--','sudo','install','-o','root','-g','root','-m','0600','/tmp/devfleet-vault-identity.json','/etc/devfleet-vault-identity.json')
 Invoke-External $mp @('exec',$vaultName,'--','sudo','rm','-f','--','/tmp/devfleet-vault-identity.json')
}
$hostIdentity|ConvertTo-Json|Set-Content -LiteralPath $hostIdentityPath -Encoding utf8
Protect-DevFleetStateAcl
Add-LocalSshKeyToInstance -InstanceName $name -PublicKeyPath (Join-Path $dest 'desktop-client.pub')
Write-Host 'Failover node paired with primary. Cluster setup is complete.' -ForegroundColor Green
} finally {
 Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
 if($tmp){Remove-Item $tmp -Force -ErrorAction SilentlyContinue}
}

try { & (Join-Path (Get-PackageRootFromState) 'client\Configure-SSH.ps1') -SkipConnectivityTest } catch { Write-Warning $_ }

try { & (Join-Path (Get-PackageRootFromState) 'client\Configure-VSCode.ps1') -ExtensionSets core } catch { Write-Warning $_ }
if (Get-Command docker.exe -ErrorAction SilentlyContinue) { try { & (Join-Path (Get-PackageRootFromState) 'client\Configure-DockerContext.ps1') } catch { Write-Warning $_ } }

```


## FILE: source/windows/Configure-DevFleet-HostControl.ps1

SHA256: 0c386e55d8d961d12708551ea4e30b0b2c224c1d25fd48f6a1c84f16bafa6432 | Bytes: 3931 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$VmName = 'devfleet-primary',
    [string]$HostAddress = 'mulattotechbox',
    [int]$Port = 8790,
    [switch]$PreviewOnly,
    [switch]$AllowPermanentDelete
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
if ($VmName -notmatch '^devfleet-primary$') { throw 'Only the existing primary dashboard VM may be configured by this utility.' }
$multipass = Get-MultipassExe
$installRoot = 'C:\ProgramData\DevFleetHostAgent'
$tokenPath = Join-Path $installRoot 'token.txt'
$url = "http://${HostAddress}:$Port"

if (-not (Test-Path -LiteralPath $tokenPath)) { throw 'Host-agent token is missing; install the host agent first.' }
$token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
if ($token.Length -lt 40) { throw 'Host-agent token is unexpectedly short.' }
$overlay = [ordered]@{
    host_control_enabled = $true
    host_control_url = $url
    host_control_token = $token
    expected_host_name = $env:COMPUTERNAME
    host_agent_timeout_seconds = 30
    host_resource_policy = [ordered]@{
        policy_version = '1.0.0'
        physical_floor_min_gb = 8
        physical_floor_percent = 0.10
        commit_headroom_floor_min_gb = 16
        commit_headroom_percent = 0.20
        commit_usage_limit_percent = 80
        reserved_logical_processors = 2
        minimum_free_disk_gb = 50
        maximum_vm_count = 4
        maximum_parallel_provisioning = 1
        max_project_cpus = 6
        max_project_memory_gb = 12
        max_project_disk_gb = 120
    }
}
if ($AllowPermanentDelete) { $overlay.allow_permanent_delete = $true }
if ($PreviewOnly) {
    [ordered]@{ok=$true;preview_only=$true;vm_name=$VmName;host_control_url=$url;expected_host_name=$env:COMPUTERNAME;gpu_passthrough=$false;allow_permanent_delete=[bool]$AllowPermanentDelete} | ConvertTo-Json -Compress
    exit 0
}

$payloadPath = Join-Path $env:TEMP "devfleet-host-control-$([guid]::NewGuid().ToString('N')).json"
try {
    [IO.File]::WriteAllText($payloadPath,($overlay | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
    & $multipass transfer $payloadPath "${VmName}:/tmp/devfleet-host-control.json" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to transfer the host-control overlay to the primary VM.' }
    $remote = @'
set -Eeuo pipefail
sudo -n python3 - /tmp/devfleet-host-control.json <<'PY'
import grp, json, os, tempfile
config_path = '/etc/devfleet/config.json'
overlay_path = '/tmp/devfleet-host-control.json'
with open(config_path, encoding='utf-8') as fh:
    config = json.load(fh)
with open(overlay_path, encoding='utf-8') as fh:
    config.update(json.load(fh))
fd, temp_path = tempfile.mkstemp(prefix='.config-', dir='/etc/devfleet')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as fh:
        json.dump(config, fh, separators=(',', ':'))
        fh.flush()
        os.fsync(fh.fileno())
    os.chown(temp_path, 0, grp.getgrnam('devrunner').gr_gid)
    os.chmod(temp_path, 0o640)
    os.replace(temp_path, config_path)
except Exception:
    try: os.unlink(temp_path)
    except FileNotFoundError: pass
    raise
PY
sudo -n rm -f /tmp/devfleet-host-control.json
'@
    & $multipass exec $VmName -- bash -lc $remote | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The primary VM rejected the atomic host-control configuration update.' }
    & $multipass exec $VmName -- sudo -n systemctl restart devfleet.service | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The primary DevFleet service did not restart after host-control configuration.' }
    $health = (& $multipass exec $VmName -- curl -fsS --connect-timeout 5 http://127.0.0.1:8787/healthz | Out-String).Trim()
    [ordered]@{ok=$true;configured_vm=$VmName;host_control_url=$url;dashboard_health=$health;gpu_passthrough=$false} | ConvertTo-Json -Compress
} finally {
    if (Test-Path -LiteralPath $payloadPath) { [IO.File]::Delete($payloadPath) }
}

```


## FILE: source/windows/Configure-GitHub.ps1

SHA256: 39ad88bc44596bfcb497d0b69f92130d859e338b878b6ad27d8fa1376f62e9d4 | Bytes: 675 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstanceName)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$mp=Get-MultipassExe
Invoke-External $mp @('exec',$InstanceName,'--','sudo','-u','devrunner','git','config','--global','user.name',[string]$config.Git.UserName)
Invoke-External $mp @('exec',$InstanceName,'--','sudo','-u','devrunner','git','config','--global','user.email',[string]$config.Git.Email)
Write-Host 'Complete the GitHub browser/device authentication below.' -ForegroundColor Yellow
& $mp exec $InstanceName -- sudo -iu devrunner gh auth login --web --git-protocol ssh

```


## FILE: source/windows/Configure-Ollama.ps1

SHA256: fffd6eb381da44ab8239be426bccf4260b196b4d48cdb9606289df62d2b322bd | Bytes: 2506 | Git mode: 100644

```
[CmdletBinding()]
param(
    [ValidateSet('stable-interactive','large-context','parallel-agents')][string]$Profile='stable-interactive',
    [string]$LanFallback='http://192.168.1.243:11434/v1'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7
Assert-Administrator
$root=Get-PackageRootFromState
$profiles=Get-Content (Join-Path $root 'config\ollama-profiles.json') -Raw|ConvertFrom-Json -AsHashtable
$selected=$profiles[$Profile]
if(-not $selected){throw 'Profile not found.'}
$tailscaleIp=$null
$magicDns=$null
try {
    $ts=Get-TailscaleExe
    $tailscaleIp=(Invoke-External $ts @('ip','-4') -Capture).Trim().Split("`n")[0]
    $status=Invoke-External $ts @('status','--json') -Capture|ConvertFrom-Json
    $magicDns=([string]$status.Self.DNSName).TrimEnd('.')
} catch { Write-Warning "Tailscale identity could not be resolved: $_" }
$hostValue=if($tailscaleIp){$tailscaleIp}else{'127.0.0.1'}
if($hostValue -in @('0.0.0.0','::')){throw 'Wildcard Ollama binding is refused.'}
[Environment]::SetEnvironmentVariable('OLLAMA_HOST',"$hostValue`:11434",'User')
foreach($kv in $selected.Environment.GetEnumerator()){
    [Environment]::SetEnvironmentVariable([string]$kv.Key,[string]$kv.Value,'User')
}
$ruleName='DevFleet Ollama Tailnet Only'
Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue|Remove-NetFirewallRule
if($tailscaleIp){
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalAddress $tailscaleIp -LocalPort 11434 -RemoteAddress '100.64.0.0/10' -Profile Any|Out-Null
}
$state=Get-DevFleetStateRoot
$cfg=Get-DevFleetConfig
$cfg.Ollama.Profile=$Profile
$cfg.Ollama.PreferredBaseUrl=if($magicDns){"http://$magicDns`:11434/v1"}elseif($tailscaleIp){"http://$tailscaleIp`:11434/v1"}else{$LanFallback}
Save-DevFleetConfig $cfg
[ordered]@{
    Profile=$Profile
    BindHost=$hostValue
    MagicDns=$magicDns
    PreferredBaseUrl=$cfg.Ollama.PreferredBaseUrl
    LanFallback=$LanFallback
    Environment=$selected.Environment
    FirewallScope=if($tailscaleIp){'Tailscale local IP; remote 100.64.0.0/10'}else{'No inbound DevFleet rule created'}
    Configured=(Get-Date).ToString('o')
}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $state 'ollama-effective.json') -Encoding utf8
Write-Host 'Restart Ollama completely, then run Test-Ollama.ps1. Re-run compute-node provisioning to propagate a changed endpoint into an already installed VM.' -ForegroundColor Green

```


## FILE: source/windows/DevFleet-HostAgent.ps1

SHA256: bf68455620a50dab6d3d470f54b264899d4712f553632c5180d7dc420e130bf2 | Bytes: 96997 | Git mode: 100644

```
[CmdletBinding()]
param([string]$ConfigPath = 'C:\ProgramData\DevFleetHostAgent\config.json',[switch]$ValidateOnly,[switch]$LibraryOnly)

$ErrorActionPreference = 'Stop'

# Fixed structured operations exposed by this agent: 'ensure', 'start', 'stop',
# 'restart', 'inspect', 'health', 'backup', 'quarantine', 'restore', 'destroy',
# plus host 'capacity'. There is no arbitrary command execution endpoint.
$script:Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$script:Root = Split-Path -Parent $ConfigPath
$script:Token = (Get-Content -LiteralPath $script:Config.TokenPath -Raw).Trim()
function Resolve-TrustedHostExecutable {
    param([Parameter(Mandatory)][string[]]$Candidates)
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:WINDIR) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') + '\' }
    foreach ($candidate in $Candidates) {
        try {
            $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($candidate))
            if ((Test-Path -LiteralPath $full -PathType Leaf) -and -not ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -and @($roots | Where-Object { $full.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { return $full }
        } catch { continue }
    }
    throw 'No trusted machine executable matched the host-agent configuration.'
}
# Multipass resolves its Windows client certificate below LOCALAPPDATA.  The
# installer places the authenticated client in the SYSTEM profile because this
# agent runs as SYSTEM; keep the lookup explicit and host-portable.
if ($script:Config.MultipassClientCertificateRoot) {
    $env:LOCALAPPDATA = Split-Path -Parent ([string]$script:Config.MultipassClientCertificateRoot)
}
$script:Multipass = Resolve-TrustedHostExecutable @($script:Config.MultipassPath, (Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Multipass\bin\multipass.exe'))
$script:RegistryPath = Join-Path $script:Root 'projects.json'
$script:LogPath = Join-Path $script:Root 'agent.jsonl'
$script:BackupRoot = Join-Path $script:Root 'backups'
$script:BackupVerificationCache = @{}
$script:ReconciliationRequired = $false
$script:AgentVersion = '2.5.0'
$script:VsCodeHelperPath = Join-Path $script:Root 'DevFleet-VSCode.ps1'
if (Test-Path -LiteralPath $script:VsCodeHelperPath -PathType Leaf) { . $script:VsCodeHelperPath }

if ($ValidateOnly) {
    if ([string]$script:Config.HostName -ne [string]$env:COMPUTERNAME) { throw "Host config identity mismatch: $($script:Config.HostName) vs $env:COMPUTERNAME" }
    if ((Get-Content -LiteralPath $script:Config.TokenPath -Raw).Trim().Length -lt 40) { throw 'Host-agent token is unexpectedly short.' }
    $policy = $script:Config.ResourcePolicy
    foreach ($name in 'PolicyVersion','PhysicalFloorMinGb','PhysicalFloorPercent','CommitHeadroomFloorMinGb','CommitHeadroomPercent','CommitUsageLimitPercent','ReservedLogicalProcessors','ReservedHostDiskGb','MaximumVmCount','MaximumParallelProvisioning','MaxProjectCpus','MaxProjectMemoryGb','MaxProjectDiskGb') {
        if ($null -eq $policy.$name) { throw "Resource policy is missing $name." }
    }
    [ordered]@{ok=$true;mode='validate-only';host_name=$script:Config.HostName;host_id=$script:Config.HostId;agent_version=$script:AgentVersion;provider='multipass';gpu_enabled=$false} | ConvertTo-Json -Compress
    exit 0
}

function Write-AgentLog {
    param([string]$Action,[string]$ProjectId = '',[string]$RuntimeId = '',[string]$State = 'info',[string]$Message = '')
    $entry = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        operation_id = [guid]::NewGuid().ToString()
        project_id = $ProjectId
        runtime_id = $RuntimeId
        host_id = [string]$script:Config.HostId
        provider = 'multipass'
        action = $Action
        result = $State
        message = $Message
    }
    ($entry | ConvertTo-Json -Compress) | Add-Content -LiteralPath $script:LogPath -Encoding UTF8
}

function Read-Registry {
    if (-not (Test-Path -LiteralPath $script:RegistryPath)) { return @{schema_version = 2; host_id = [string]$script:Config.HostId; projects = @{}} }
    try {
        $data = Get-Content -LiteralPath $script:RegistryPath -Raw | ConvertFrom-Json -AsHashtable
        if (-not $data.projects) { $data.projects = @{} }
        return $data
    } catch { throw 'Host agent registry is not valid JSON.' }
}

function Write-Registry {
    param([hashtable]$Data)
    $tmp = "$script:RegistryPath.$([guid]::NewGuid().ToString('N')).tmp"
    $json = $Data | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $script:RegistryPath -Force
}

function Invoke-Multipass {
    param([Parameter(Mandatory)][string[]]$ArgumentList,[int]$TimeoutSeconds = 120)
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = [string]$script:Multipass
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($arg in $ArgumentList) { [void]$psi.ArgumentList.Add([string]$arg) }
    $process = [Diagnostics.Process]::new();$process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw 'Unable to start the configured Multipass executable.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync();$stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit([Math]::Max(1,$TimeoutSeconds) * 1000)) {
            try { $process.Kill($true) } catch {}
            try {[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5)))} catch {}
            $commandLabel=($ArgumentList|Select-Object -First 5)-join ' '
            throw "Multipass command timed out after $TimeoutSeconds seconds: $commandLabel"
        }
        $exitCode=$process.ExitCode
        $outputComplete=$false
        try {$outputComplete=[Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask)).Wait([TimeSpan]::FromSeconds(5))} catch {$outputComplete=$false}
        $stdout=if($stdoutTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stdoutTask.GetAwaiter().GetResult()}else{''}
        $stderr=if($stderrTask.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderrTask.GetAwaiter().GetResult()}else{''}
        if (-not $outputComplete) { $commandLabel=($ArgumentList|Select-Object -First 5)-join ' ';throw "Multipass exited with code $exitCode, but redirected output was incomplete after the bounded post-exit drain: $commandLabel" }
        if ($exitCode -ne 0) { $detail = ($stderr + $stdout).Trim(); throw "Multipass failed ($exitCode): $detail" }
        return [pscustomobject]@{ExitCode=$exitCode;Text=(($stdout + "`n" + $stderr).Trim());OutputComplete=$true}
    } finally { $process.Dispose() }
}

function Assert-Slug { param([Parameter(Mandatory)][string]$Slug); if ($Slug -notmatch '^[a-z0-9][a-z0-9._-]{1,62}$') { throw 'Invalid project slug.' }; return $Slug.ToLowerInvariant() }
function Assert-ProjectId { param([Parameter(Mandatory)][string]$ProjectId); if ($ProjectId -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Invalid project identifier.' }; return $ProjectId }
function Assert-BackupId { param([Parameter(Mandatory)][string]$BackupId);if($BackupId -notmatch '^[a-z0-9][a-z0-9._-]{1,159}$'){throw 'Invalid backup identifier.'};return $BackupId.ToLowerInvariant() }
function Get-Policy { return $script:Config.ResourcePolicy }

function New-VerifiedRemoteWorkspaceArchive {
    param(
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string]$Slug,
        [bool]$IncludeGenerated = $false
    )
    $Slug=Assert-Slug $Slug
    if($Archive -notmatch '^/tmp/devfleet-(backup|export|import)-[a-z0-9._-]+\.tar\.gz$'){throw 'Remote workspace archive path is invalid.'}
    $workspace="/home/devrunner/workspaces/$Slug"
    $archiveScript=@'
import hashlib
import json
import sys
import tarfile
from pathlib import Path, PurePosixPath

archive, workspace, slug, include_generated = sys.argv[1:]
include_generated = include_generated.lower() == "true"
root = Path(workspace)
if not root.is_dir():
    raise SystemExit("workspace is missing")
excluded = {"node_modules", ".next", "build", "dist", ".venv", "venv", ".pytest_cache", "__pycache__", ".test-runtime"}
members = []

def archive_filter(info):
    name = info.name.replace("\\", "/")
    pure = PurePosixPath(name)
    if pure.is_absolute() or ".." in pure.parts or not (name == slug or name.startswith(slug + "/")):
        raise SystemExit("unsafe workspace archive path")
    if not include_generated and any(part in excluded for part in pure.parts[1:]):
        return None
    if info.issym() or info.islnk() or info.isfifo() or info.isdev():
        raise SystemExit("workspace archive contains a l