# DevFleet source part 115

Full-source UTF-8 byte interval [5301000, 5347500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ec19f1dd5995bed90389805bc9039fc026b40b149c4dd6979a7e7e60f6b7b177

<!-- BEGIN SOURCE SLICE -->
de_id -ne [string]$vaultIdentity.node_id -or [string]$liveVaultIdentity.node_name -ne $vaultName) {
        throw 'SECRET RECOVERY REQUIRED: vault identity does not match the exact deployment inventory; no credentials were changed.'
    }
} elseif (Test-Path -LiteralPath (Join-Path $stateRoot 'secrets\vault-client.json') -PathType Leaf) {
    throw 'SECRET RECOVERY REQUIRED: this primary is bound to an external vault. Run a coordinated all-node recovery from the surrogate/vault host; no credentials were changed.'
}

$hostAgentRoot = Join-Path $env:ProgramData 'DevFleetHostAgent'
$hostTokenPath = Join-Path $hostAgentRoot 'token.txt'
$hostOwnershipPath = Join-Path $hostAgentRoot 'integration-ownership.json'
$hostOwnership = Read-DevFleetIntegrationOwnership -Path $hostOwnershipPath
$taskBinding = @($hostOwnership.ScheduledTasks | Where-Object { [string]$_.Name -eq 'DevFleet Host Agent' })
$task = Get-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue
if ($taskBinding.Count -ne 1 -or -not $task -or @($task.Actions).Count -ne 1) { throw 'SECRET RECOVERY REQUIRED: Host Agent task ownership is incomplete; no credentials were changed.' }
$taskActual = @{Name=[string]$task.TaskName;Executable=[string]$task.Actions[0].Execute;Arguments=[string]$task.Actions[0].Arguments;Principal=[string]$task.Principal.UserId;LogonType=[string]$task.Principal.LogonType;RunLevel=[string]$task.Principal.RunLevel;Description=[string]$task.Description;Generation=[string]$taskBinding[0].Generation}
Assert-DevFleetTaskBinding -Expected $taskBinding[0] -Actual $taskActual | Out-Null

$recoveryRoot = Join-Path $stateRoot "secret-recovery\$generation"
New-Item -ItemType Directory -Path $recoveryRoot -Force | Out-Null
Protect-DevFleetStateAcl
$secretPath = Join-Path $stateRoot 'secrets\host-secrets.json'
if (Test-Path -LiteralPath $secretPath -PathType Leaf) { Copy-Item -LiteralPath $secretPath -Destination (Join-Path $recoveryRoot 'host-secrets.before.json') -Force }
if (Test-Path -LiteralPath $hostTokenPath -PathType Leaf) { Copy-Item -LiteralPath $hostTokenPath -Destination (Join-Path $recoveryRoot 'host-agent-token.before.txt') -Force }
$pendingSecretsPath = Join-Path $recoveryRoot 'host-secrets.pending.json'
Write-AtomicUtf8 -Path $pendingSecretsPath -Text (($newSecrets | ConvertTo-Json -Depth 5) + [Environment]::NewLine)

$computeHelper = Join-Path (Get-PackageRootFromState) 'linux\devfleet-rotate-compute-secrets'
$vaultHelper = Join-Path (Get-PackageRootFromState) 'linux\devfleet-rotate-vault-secrets'
if (-not (Test-Path -LiteralPath $computeHelper -PathType Leaf) -or ($vaultName -and -not (Test-Path -LiteralPath $vaultHelper -PathType Leaf))) { throw 'Secret recovery helpers are missing from the exact package.' }
$remoteComputeHelper = "/tmp/devfleet-rotate-compute-$generation"
$remoteVaultHelper = "/tmp/devfleet-rotate-vault-$generation"
$computeApplied = $false
$vaultApplied = $false
$hostTokenApplied = $false
$committed = $false
$evidence = [ordered]@{schemaVersion=1;secretGeneration=$generation;deploymentId=[string]$hostIdentity.deployment_id;hostNodeId=[string]$hostIdentity.node_id;compute=[ordered]@{name=$computeName;nodeId=[string]$computeIdentity.node_id;verified=$false};vault=if($vaultName){[ordered]@{name=$vaultName;nodeId=[string]$vaultIdentity.node_id;verified=$false}}else{$null};hostAgent=[ordered]@{task='DevFleet Host Agent';ownershipGeneration=[string]$hostOwnership.InstallationGeneration;verified=$false};plaintextSecretsLogged=$false;status='IN_PROGRESS';startedAt=(Get-Date).ToUniversalTime().ToString('o')}
try {
    New-DevFleetSnapshotSafe -InstanceName $computeName -SnapshotName "pre-secret-rekey-$($generation.Substring(0,8))" | Out-Null
    Wait-MultipassReady -Name $computeName -TimeoutSeconds 600
    Invoke-External $multipass @('transfer',$computeHelper,"${computeName}:$remoteComputeHelper")
    if ($vaultName) {
        New-DevFleetSnapshotSafe -InstanceName $vaultName -SnapshotName "pre-secret-rekey-$($generation.Substring(0,8))" | Out-Null
        Wait-MultipassReady -Name $vaultName -TimeoutSeconds 600
        Invoke-External $multipass @('transfer',$vaultHelper,"${vaultName}:$remoteVaultHelper")
        $vaultPayload = [ordered]@{schema_version=1;secret_generation=$generation;deployment_id=[string]$hostIdentity.deployment_id;node_id=[string]$vaultIdentity.node_id;cluster=[string]$config.ClusterName;rest_user=[string]$newSecrets.VaultRestUser;rest_password=[string]$newSecrets.VaultRestPassword;restic_password=[string]$newSecrets.ResticPassword}
        Invoke-MultipassWithStandardInput -FilePath $multipass -InstanceName $vaultName -CommandArgumentList @('sudo','bash',$remoteVaultHelper,'apply',$generation) -StandardInputText ($vaultPayload | ConvertTo-Json -Compress)
        $vaultApplied = $true; $evidence.vault.verified = $true
    }
    $computePayload = [ordered]@{schema_version=1;secret_generation=$generation;deployment_id=[string]$hostIdentity.deployment_id;node_id=[string]$hostIdentity.node_id;admin_user=[string]$newSecrets.PortalAdminUser;admin_password=[string]$newSecrets.PortalAdminPassword;api_token=[string]$newSecrets.NodeApiToken;host_control_token=$newHostToken}
    Invoke-MultipassWithStandardInput -FilePath $multipass -InstanceName $computeName -CommandArgumentList @('sudo','bash',$remoteComputeHelper,'apply',$generation) -StandardInputText ($computePayload | ConvertTo-Json -Compress)
    $computeApplied = $true; $evidence.compute.verified = $true

    if ($vaultName) {
        $vaultIp = Get-InstanceIPv4 -Name $vaultName -PreferTailscale
        if (-not $vaultIp) { throw 'Rotated vault endpoint has no verified reachable address.' }
        $vaultClient = [ordered]@{Repository="rest:http://${vaultIp}:$($config.Network.VaultPort)/$($newSecrets.VaultRestUser)/$($config.ClusterName)";RestUser=[string]$newSecrets.VaultRestUser;RestPassword=[string]$newSecrets.VaultRestPassword;ResticPassword=[string]$newSecrets.ResticPassword;VaultIp=$vaultIp;VaultPort=[int]$config.Network.VaultPort;SecretGeneration=$generation}
        $pendingVaultClient = Join-Path $recoveryRoot 'vault-client.pending.json'
        Write-AtomicUtf8 -Path $pendingVaultClient -Text (($vaultClient | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
        Invoke-External $multipass @('transfer',$pendingVaultClient,"${computeName}:/tmp/devfleet-vault-client-$generation.json")
        $remoteVaultClient = "/tmp/devfleet-vault-client-$generation.json"
        $configureBackup = 'set -Eeuo pipefail; trap ''rm -f -- "$1"'' EXIT; /usr/local/sbin/devfleet-configure-backup "$1"'
        Invoke-External $multipass @('exec',$computeName,'--','sudo','bash','-c',$configureBackup,'--',$remoteVaultClient)
    }

    Write-AtomicUtf8 -Path $hostTokenPath -Text ($newHostToken + [Environment]::NewLine)
    $hostTokenApplied = $true
    Stop-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName 'DevFleet Host Agent'
    $hostHealth = $null
    $hostAgentConfig = Get-Content -LiteralPath (Join-Path $hostAgentRoot 'config.json') -Raw | ConvertFrom-Json
    if ([string]$hostAgentConfig.ListenPrefix -notmatch ':(\d{2,5})/$') { throw 'Host Agent listen prefix is invalid during secret verification.' }
    $hostAgentPort = [int]$Matches[1]
    for ($attempt = 0; $attempt -lt 20 -and -not $hostHealth; $attempt++) {
        try { $hostHealth = Invoke-HostAgentAuthenticatedJson -Uri "http://127.0.0.1:$hostAgentPort/healthz" -Method GET -Key $newHostToken -ExpectedHost $env:COMPUTERNAME }
        catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $hostHealth.ok) { throw 'Rotated Host Agent credential did not verify.' }
    $evidence.hostAgent.verified = $true

    if ($vaultName) {
        $pendingVaultClient = Join-Path $recoveryRoot 'vault-client.pending.json'
        $vaultClientPath = Join-Path $stateRoot 'secrets\vault-client.json'
        Write-AtomicUtf8 -Path $vaultClientPath -Text (Get-Content -LiteralPath $pendingVaultClient -Raw)
    }
    Write-AtomicUtf8 -Path $secretPath -Text (($newSecrets | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
    Protect-DevFleetStateAcl
    $committed = $true
    $evidence.status='COMMITTED';$evidence.completedAt=(Get-Date).ToUniversalTime().ToString('o')
} catch {
    $evidence.status='ROLLED_BACK';$evidence.error=$_.Exception.Message;$evidence.failedAt=(Get-Date).ToUniversalTime().ToString('o')
    if ($hostTokenApplied -and (Test-Path -LiteralPath (Join-Path $recoveryRoot 'host-agent-token.before.txt'))) {
        Copy-Item -LiteralPath (Join-Path $recoveryRoot 'host-agent-token.before.txt') -Destination $hostTokenPath -Force
        Stop-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue; Start-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue
    } elseif ($hostTokenApplied) {
        Remove-Item -LiteralPath $hostTokenPath -Force -ErrorAction SilentlyContinue
        Stop-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue
    }
    if ($computeApplied) { try { Invoke-External $multipass @('exec',$computeName,'--','sudo','bash',$remoteComputeHelper,'rollback',$generation) } catch { $evidence.compute.rollbackError=$_.Exception.Message } }
    if ($vaultApplied) { try { Invoke-External $multipass @('exec',$vaultName,'--','sudo','bash',$remoteVaultHelper,'rollback',$generation) } catch { $evidence.vault.rollbackError=$_.Exception.Message } }
    throw
} finally {
    foreach ($target in @(@($computeName,$remoteComputeHelper),@($vaultName,$remoteVaultHelper))) {
        if ($target[0]) { try { Invoke-External $multipass @('exec',[string]$target[0],'--','sudo','rm','-f','--',[string]$target[1]) -IgnoreExitCode } catch {} }
    }
    Remove-Item -LiteralPath $pendingSecretsPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $recoveryRoot 'vault-client.pending.json') -Force -ErrorAction SilentlyContinue
    Write-AtomicUtf8 -Path (Join-Path $recoveryRoot 'recovery-evidence.json') -Text (($evidence | ConvertTo-Json -Depth 8) + [Environment]::NewLine)
}
if (-not $committed) { throw 'Secret recovery did not commit.' }
[ordered]@{ok=$true;status='COMMITTED';secretGeneration=$generation;deploymentId=[string]$hostIdentity.deployment_id;compute=$computeName;vault=$vaultName;plaintextSecretsLogged=$false;recoveryEvidence=(Join-Path $recoveryRoot 'recovery-evidence.json')} | ConvertTo-Json -Compress

```


## FILE: source/windows/Set-DevFleetDockerMode.ps1

SHA256: f76be7c8d6fc8364fba6b7a142efe687351355681473e56cc30b51e021377f95 | Bytes: 2185 | Git mode: 100644

```
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('Primary','Failover')][string]$NodeRole,
    [Parameter(Mandatory)][ValidateSet('rootless','rootful')][string]$Mode,
    [switch]$AcknowledgeRootful
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7
Assert-Administrator
$config=Get-DevFleetConfig
$node=if($NodeRole -eq 'Primary'){$config.Primary}else{$config.Failover}
$instance=[string]$node.InstanceName
if($Mode -eq 'rootful' -and -not $AcknowledgeRootful){
    throw 'Rootful Docker requires -AcknowledgeRootful. It has broader authority inside the disposable VM, but still receives no Windows mounts or Docker TCP exposure.'
}
if(-not(Test-MultipassInstance $instance)){throw "Multipass instance is not installed locally: $instance"}
Assert-MultipassIsolation -InstanceNames @($instance)
$stamp=(Get-Date).ToString('yyyyMMdd-HHmmss')
$logDir=Join-Path (Get-DevFleetStateRoot) 'logs'
New-Item -ItemType Directory $logDir -Force|Out-Null
if($PSCmdlet.ShouldProcess($instance,"Switch Docker mode to $Mode without migrating or deleting either store")){
    New-DevFleetSnapshotSafe -InstanceName $instance -SnapshotName "pre-docker-mode-$Mode-$stamp"|Out-Null
    $mp=Get-MultipassExe
    Invoke-External $mp @('start',$instance) -IgnoreExitCode
    $report=Invoke-External $mp @('exec',$instance,'--','sudo','/usr/local/bin/devfleet-docker-mode-report') -Capture
    Set-Content (Join-Path $logDir "docker-mode-before-$instance-$stamp.txt") $report -Encoding utf8
    $args=@('exec',$instance,'--','sudo','/usr/local/bin/devfleet-switch-docker-mode',$Mode)
    if($Mode -eq 'rootful'){$args+='--acknowledge-rootful'}
    Invoke-External $mp $args
    if($NodeRole -eq 'Primary'){$config.Docker.PrimaryMode=$Mode}else{$config.Docker.FailoverMode=$Mode}
    if($Mode -eq 'rootful'){$config.Docker.RootfulModeAcknowledged=$true}
    Save-DevFleetConfig -Config $config
    & (Join-Path $PSScriptRoot 'Test-DevFleet.ps1') -InstanceName $instance
    Write-Host "Docker mode for $instance is now $Mode. The other Docker store was not migrated or deleted." -ForegroundColor Green
}

```


## FILE: source/windows/Set-DevFleetTailscaleOAuthCredential.ps1

SHA256: 0105c2847c27380d28d1dc28f2866309f107ced8dd750589b42185bd39bc27f3 | Bytes: 917 | Git mode: 100644

```
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Tailscale.psm1') -Force
Assert-PowerShell7
Assert-Administrator

Write-Host 'DevFleet Tailscale OAuth setup' -ForegroundColor Cyan
Write-Host 'Paste the OAuth client secret only into the local secure prompt. It is never sent to Codex, printed, or placed in a command argument.' -ForegroundColor DarkGray
$secret = Read-Host 'Tailscale OAuth client secret' -AsSecureString
try {
    $path = Set-DevFleetTailscaleOAuthClientSecret -Secret $secret
    [pscustomobject]@{
        status = 'PASS'
        provider = 'OAuthClientSecret'
        storage = 'DevFleet protected local state ACL'
        path = $path
        secretPrinted = $false
        secretInEvidence = $false
    } | ConvertTo-Json -Compress
} finally {
    $secret = $null
}

```


## FILE: source/windows/Show-DevFleet-Credentials.ps1

SHA256: 71a2690913ce61e9a48b24bcf7bcf6a6933c41b46b432375a212ebc3a2b159aa | Bytes: 647 | Git mode: 100644

```
[CmdletBinding()]
param([switch]$CopyPassword)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$secrets=Get-OrCreateSecrets
Write-Host "`nDevFleet dashboard credentials for this Windows host" -ForegroundColor Cyan
Write-Host "Username: $($secrets.PortalAdminUser)"
Write-Host "Password: $($secrets.PortalAdminPassword)"
if($CopyPassword){Set-Clipboard -Value $secrets.PortalAdminPassword;Write-Host 'Password copied to clipboard.' -ForegroundColor Yellow}
Write-Host "Stored with restricted ACLs under C:\ProgramData\DevFleet\secrets." -ForegroundColor DarkGray
Read-Host 'Press Enter to close'

```


## FILE: source/windows/Start-DevFleet.ps1

SHA256: 111e3e8828b164feae5ec9bc7a0000683bbb8bbb77c4921aab5b28713447f404 | Bytes: 1989 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstanceName,[ValidateSet('Dashboard','VSCode')][string]$Mode='Dashboard')
$ErrorActionPreference='Stop'
$InstanceName = $InstanceName.Trim() -replace '^(?i:devfleet-)+',''
$InstanceName = "devfleet-$InstanceName"
try {
 Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
 $config=Get-DevFleetConfig;$mp=Get-MultipassExe
 Assert-MultipassIsolation -InstanceNames @($InstanceName)
 Invoke-External $mp @('start',$InstanceName) -IgnoreExitCode
 Wait-MultipassReady $InstanceName 300
 $ip=Get-InstanceIPv4 $InstanceName -PreferTailscale
 if(-not $ip){throw 'Could not determine the DevFleet VM IP address.'}
 if($Mode -eq 'Dashboard'){
  $port=[int]$config.Network.PortalPort
  if(-not (Test-NetConnection -ComputerName $ip -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue)){
   throw "The DevFleet VM is running, but its dashboard is not reachable at http://${ip}:$port/. The DevFleet service may still be starting; wait one minute and try again."
  }
  Start-Process "http://${ip}:$port/"
 }else{
  $sshDir=Join-Path $env:USERPROFILE '.ssh';New-Item -ItemType Directory $sshDir -Force|Out-Null
  $cfg=Join-Path $sshDir 'config';$alias=$InstanceName
  $block=@"
Host $alias
    HostName $ip
    User devrunner
    IdentityFile $(Get-OrCreateDevFleetSshKey)
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
"@
  $existing=if(Test-Path $cfg){Get-Content $cfg -Raw}else{''}
  if($existing -notmatch "(?m)^Host\s+$([regex]::Escape($alias))$"){Add-Content $cfg "`n$block"}
  $code=Get-VsCodeCli -AllowPerUser
  if(-not $code){throw 'VS Code CLI not found.'}
  & $code --remote "ssh-remote+$alias" "/home/devrunner/workspaces"
 }
} catch {
 $message = "DevFleet could not open. $($_.Exception.Message)`n`nNo VM was recreated or reprovisioned."
 Write-Error $message
 try { (New-Object -ComObject WScript.Shell).Popup($message,0,'DevFleet launch problem',0x10) | Out-Null } catch { }
 exit 1
}

```


## FILE: source/windows/Stop-DevFleet.ps1

SHA256: e74baad7cd8e7ba9f706710b17bcae7e736266d8dc41d6f326243609a140a8e5 | Bytes: 808 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstanceName,[switch]$Force)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$mp=Get-MultipassExe
if(-not (Test-MultipassInstance $InstanceName)){throw "Instance not found: $InstanceName"}
$running=Invoke-External $mp @('exec',$InstanceName,'--','sudo','-u','devrunner','bash','-lc','export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock; docker ps --format "{{.Names}}" 2>/dev/null') -Capture -IgnoreExitCode
if($running -and -not $Force){
  throw "Running project containers were found. Stop them in the dashboard first, or rerun with -Force after verifying work is saved.`n$running"
}
Invoke-External $mp @('stop',$InstanceName)
Write-Host "$InstanceName stopped safely." -ForegroundColor Green

```


## FILE: source/windows/Test-DevFleet.ps1

SHA256: 900e430ea23f0f2980da8d9529389a5abc06c4fefc3e2195ba6e76f3bb70f245 | Bytes: 979 | Git mode: 100644

```
[CmdletBinding()]
param([switch]$AllLocalInstances,[string]$InstanceName)
$ErrorActionPreference='Continue'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$mp=Get-MultipassExe
try{Assert-MultipassIsolation -InstanceNames @($config.Primary.InstanceName,$config.Failover.InstanceName,$config.Vault.InstanceName);Write-Host 'Multipass host-mount isolation: OK' -ForegroundColor Green}catch{Write-Error $_}
$names=if($InstanceName){@($InstanceName)}elseif($AllLocalInstances){@($config.Primary.InstanceName,$config.Failover.InstanceName,$config.Vault.InstanceName)|Where-Object{Test-MultipassInstance $_}}else{@()}
foreach($name in $names){
 Write-Host "`n=== $name ===" -ForegroundColor Cyan
 Invoke-External $mp @('start',$name) -IgnoreExitCode
 $cmd=if($name -eq $config.Vault.InstanceName){'sudo /usr/local/sbin/devfleet-vault-health'}else{'sudo -u devrunner /usr/local/bin/devfleet-health'}
 & $mp exec $name -- bash -lc $cmd
}

```


## FILE: source/windows/Test-Ollama.ps1

SHA256: d64c2328cb6057dc0bccf78051fdb523da928df89ed9b6ae713f961dab30aaf1 | Bytes: 1124 | Git mode: 100644

```
[CmdletBinding()]param([switch]$ProbeGeneration)
$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force;$cfg=Get-DevFleetConfig;$base=if($cfg.Ollama.PreferredBaseUrl){$cfg.Ollama.PreferredBaseUrl}else{$cfg.Ollama.BaseUrl};$models=Invoke-RestMethod -Uri ($base.TrimEnd('/')+'/models') -TimeoutSec 15;$names=@($models.data|ForEach-Object id);$available=$cfg.Ollama.Model -in $names;$result=[ordered]@{Endpoint=$base;Reachable=$true;ExpectedModel=$cfg.Ollama.Model;ModelAvailable=$available;Profile=$cfg.Ollama.Profile;Models=$names};if($ProbeGeneration -and $available){$body=@{model=$cfg.Ollama.Model;messages=@(@{role='user';content='Reply OK'});max_tokens=4}|ConvertTo-Json -Depth 8;$r=Invoke-WebRequest -Uri ($base.TrimEnd('/')+'/chat/completions') -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 120;$result.QueueResponse=$r.StatusCode};if(Get-Command ollama.exe -ErrorAction SilentlyContinue){$result.GpuObservation=(& ollama.exe ps 2>&1|Out-String).Trim()};$result|ConvertTo-Json -Depth 10; if(-not $available){throw 'Expected model is not available.'}

```


## FILE: source/windows/Update-DevFleet.ps1

SHA256: 6eb437cd4cf6a5d29fcd25c202d50d9a7ed738e2c76d9c5763d2acc64d13ff23 | Bytes: 1712 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstanceName,[switch]$IncludeMultipass)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$manifest=Get-CanonicalDependencyManifest -PackageRoot (Split-Path -Parent $PSScriptRoot)
$mp=Get-MultipassExe
$snap="pre-update-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
New-DevFleetSnapshotSafe -InstanceName $InstanceName -SnapshotName $snap|Out-Null
Invoke-External $mp @('start',$InstanceName) -IgnoreExitCode
$config=Get-DevFleetConfig
if($InstanceName -eq $config.Primary.InstanceName){
 & (Join-Path $PSScriptRoot '02-Provision-ComputeNode.ps1') -NodeRole Primary
}elseif($InstanceName -eq $config.Failover.InstanceName){
 & (Join-Path $PSScriptRoot '02-Provision-ComputeNode.ps1') -NodeRole Failover
}else{throw "InstanceName must be the configured primary or failover compute node: $InstanceName"}
Invoke-External $mp @('exec',$InstanceName,'--','sudo','/usr/local/sbin/devfleet-safe-update')
foreach($dependency in @($manifest.dependencies)|Where-Object { $_.wingetPackageId -and ($_.required -or $_.classification -in @('ROLE_REQUIRED','RECOMMENDED')) }){Install-WingetPackage -Id $dependency.wingetPackageId -Upgrade}
if($IncludeMultipass){
 Write-Warning 'Multipass upgrade requested. Ensure vault and project backups are current.'
 $multipass=@($manifest.dependencies)|Where-Object id -eq 'multipass'|Select-Object -First 1
 Install-WingetPackage -Id $multipass.wingetPackageId -Upgrade
}else{Write-Host 'Multipass was intentionally not auto-upgraded. Re-run with -IncludeMultipass after verifying backups.' -ForegroundColor Yellow}
Write-Host "Update complete. Snapshot: $snap" -ForegroundColor Green

```


## FILE: source/windows/Update-Vault.ps1

SHA256: bbd371182a3002edfe1e3b8995ad1a437d706eac8ed4b9713a4f7252339d7069 | Bytes: 1006 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7
Assert-Administrator
$config=Get-DevFleetConfig
$name=$config.Vault.InstanceName
if(-not (Test-MultipassInstance $name)){throw 'The local DevFleet vault VM was not found.'}
Write-Host 'Refreshing the vault through the idempotent provisioner. A pre-refresh VM snapshot is taken first.' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot '03-Provision-Vault.ps1')
Invoke-External (Get-MultipassExe) @('exec',$name,'--','sudo','apt-get','update')
Invoke-External (Get-MultipassExe) @('exec',$name,'--','sudo','env','DEBIAN_FRONTEND=noninteractive','apt-get','-y','upgrade')
Invoke-External (Get-MultipassExe) @('exec',$name,'--','sudo','systemctl','restart','tailscaled','rest-server')
Invoke-External (Get-MultipassExe) @('exec',$name,'--','sudo','/usr/local/sbin/devfleet-vault-health')
Write-Host 'Vault update and health check completed.' -ForegroundColor Green

```


## FILE: source/windows/Verify-DevFleet-Host.ps1

SHA256: 1e1a37ba016238f122173ce7bd22c0909ce2b155d47c23f6430fd15440020705 | Bytes: 2174 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$HostAgentUrl = 'http://127.0.0.1:8790',
    [string]$TokenPath = 'C:\ProgramData\DevFleetHostAgent\token.txt'
)

$ErrorActionPreference = 'Stop'
$commonModule = Join-Path $PSScriptRoot 'DevFleet.Common.psm1'
$protocolModule = Join-Path $PSScriptRoot 'DevFleet-HostAgentProtocol.psm1'
Import-Module $commonModule -Force
Import-Module $protocolModule -Force
# Read-only verification utility. It never changes drivers, Windows features,
# networking, services, VM state, or scheduled tasks.

$driver = Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceName LIKE '%AMD Radeon%'" | Select-Object -First 1 DeviceName,DriverVersion,DriverDate,Status
$multipass = try { Get-MultipassExe } catch { $null }
$vmInventory = $null
if ($multipass) {
    $vmInventory = (& $multipass list --format json 2>&1 | Out-String).Trim()
}
$agent = [ordered]@{configured=$false;status='not-configured'}
try {
    if (Test-Path -LiteralPath $TokenPath) {
        try {
            $token = (Get-Content -LiteralPath $TokenPath -Raw).Trim()
            if ($token) {
                try {
                    $health = Invoke-HostAgentAuthenticatedJson -Uri "$($HostAgentUrl.TrimEnd('/'))/healthz" -Method GET -Key $token -ExpectedHost $env:COMPUTERNAME
                    $agent = [ordered]@{configured=$true;status='healthy';health=$health}
                } catch { $agent = [ordered]@{configured=$true;status='unreachable';error=$_.Exception.Message} }
            }
        } catch { $agent = [ordered]@{configured=$true;status='token-unreadable';error='Run this read-only verification utility elevated to inspect the SYSTEM-protected token.'} }
    }
} catch { $agent = [ordered]@{configured=$true;status='token-unreadable';error='Run this read-only verification utility elevated to inspect the SYSTEM-protected token.'} }
[ordered]@{
    hostname=$env:COMPUTERNAME
    amd_driver=$driver
    multipass_present=[bool]$multipass
    vm_inventory_json=$vmInventory
    host_agent=$agent
    protected_baseline=[ordered]@{amd_adrenalin='26.3.1';display_driver='32.0.23033.1002';gpu_passthrough=$false;reboot_requested=$false}
} | ConvertTo-Json -Depth 10

```


## FILE: tools/AuthorityTime.psm1

SHA256: d4be2f022fc46fc75561135149a2c6c11e9106f1bde2a653691e325084619ec1 | Bytes: 770 | Git mode: 100644

```
Set-StrictMode -Version Latest

function ConvertTo-AuthorityUtcInstant {
    param([Parameter(Mandatory)][object]$Value)
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    if ($Value -is [datetime]) {
        $date = [datetime]$Value
        if ($date.Kind -eq [DateTimeKind]::Unspecified) { throw 'Authority timestamp omitted its UTC offset/kind.' }
        return $date.ToUniversalTime()
    }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { throw "Authority timestamp was malformed: $Value" }
    return $parsed.UtcDateTime
}

Export-ModuleMember -Function ConvertTo-AuthorityUtcInstant

```


## FILE: tools/Build-AI-CodebaseBundle.ps1

SHA256: 5c8c3ebb294bb267995747ebbe96d17a03f433d3882b1d8573352fe497b9312d | Bytes: 238 | Git mode: 100644

```
[CmdletBinding()]
param([string]$Workspace = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Build-AIAuditBundle.ps1') -Workspace $Workspace
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

```


## FILE: tools/Build-AIAuditBundle.ps1

SHA256: 98011014a59a1194a40dcbdc4c9af9365a8d80a19262ad510851d26df16085de | Bytes: 100487 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$Workspace = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('Auto','PreAcceptanceReleaseAudit')]
    [string]$Operation = 'Auto',
    [string]$ReleaseAuditRunId
)

$ErrorActionPreference = 'Stop'
$env:PYTHONDONTWRITEBYTECODE = '1'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
Import-Module (Join-Path $Workspace 'tools\PythonRuntime.psm1') -Force
$python = Resolve-DevFleetPython -Workspace $Workspace
$Outputs = Join-Path $Workspace 'outputs'
$Audit = Join-Path $Workspace 'audit'
$releaseVersion = (Get-Content -LiteralPath (Join-Path $Workspace 'source\VERSION') -Raw).Trim()
$installerVersion = (Get-Content -LiteralPath (Join-Path $Workspace 'installer-source\INSTALLER_VERSION') -Raw).Trim()
$zipPath = Join-Path $Outputs ("DevFleet-v{0}-AI-Audit-LATEST.zip" -f $releaseVersion)
$sidecarPath = "$zipPath.sha256.txt"
$manifestPath = "$zipPath.manifest.json"
$stage = Join-Path ([IO.Path]::GetTempPath()) ("DevFleet AI Audit bundle {0}" -f [guid]::NewGuid().ToString('N'))
$sourceStage = Join-Path $stage 'source'
$installerStage = Join-Path $stage 'installer-source'
$automationStage = Join-Path $stage 'automation'
$toolingStage = Join-Path $stage 'release-tooling'
$evidenceStage = Join-Path $stage 'evidence'
$auditStage = Join-Path $stage 'audit'
$outputMetadataStage = Join-Path $stage 'outputs'

function Rel([string]$Path) { return ([IO.Path]::GetFullPath($Path)).Substring($Workspace.Length).TrimStart('\','/').Replace('\','/') }
function Read-Json([string]$Path) { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Write-Json([string]$Path,$Value) { $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function Write-AtomicJson([string]$Path,$Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,(($Value | ConvertTo-Json -Depth 40) + [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-StringHash([string]$Value) { $sha=[Security.Cryptography.SHA256]::Create(); try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() } }
function Is-Excluded([IO.FileInfo]$File,[string]$Relative) {
    $parts = $Relative.Split('/')
    $blocked = @('.git','.venv','node_modules','bin','obj','__pycache__','.pytest_cache','.test-runtime','build','dist','outputs','audit-extract','transient-source-quarantine','stale-portable-metadata-quarantine','VHDX','snapshots','browser-profiles')
    foreach ($part in $parts) { if ($blocked -contains $part -or $part -like '.venv-*') { return $true } }
    if ($File.Name -match '(?i)\.(pyc|pyo|exe|dll|pdb|msi|iso|img|vhd|vhdx|avhdx|zip|7z|cab|tar|gz|tgz|png|jpg|jpeg|gif|bmp|ico|webp|woff|woff2|ttf)$') { return $true }
    return $false
}
function Add-Tree {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][string]$BundlePrefix)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Required audit source root is missing: $Root" }
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse -Force) {
        $relative = ([IO.Path]::GetFullPath($file.FullName)).Substring(([IO.Path]::GetFullPath($Root)).Length).TrimStart('\','/').Replace('\','/')
        $bundlePath = "$BundlePrefix/$relative"
        if (Is-Excluded $file $bundlePath) { continue }
        $destination = Join-Path $DestinationRoot ($relative -replace '/','\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
}
function Add-CompactFile([string]$Source,[string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return $false }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    return $true
}
function Add-AuthorizationLedgerClosure([string]$Repository,[string]$EvidenceRoot) {
    $selected=@(
        [ordered]@{name='df-audit-convergence-20260924-a-ledger.json';policyId='DF-AUDIT-CONVERGENCE-20260924-A'},
        [ordered]@{name='df-rdc-certification-continuation-20260924-b-ledger.json';policyId='DF-RDC-CERTIFICATION-CONTINUATION-20260924-B'}
    )
    $rows=[Collections.Generic.List[object]]::new();$sources=@{}
    foreach($entry in $selected){
        $relative='evidence/campaigns/'+[string]$entry.name
        if($relative -notmatch '^evidence/campaigns/[A-Za-z0-9-]+-ledger\.json$'){throw 'Authorization ledger path is outside the fixed safe allowlist.'}
        $source=Join-Path $Repository ('evidence\campaigns\'+[string]$entry.name);$checked=$Repository
        foreach($component in $relative.Split('/')){$checked=Join-Path $checked $component;$componentItem=Get-Item -LiteralPath $checked -Force -ErrorAction Stop;if(($componentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Authorization ledger path rejects reparse-point components.'}}
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Required adopted authorization ledger is missing: $relative"}
        $item=Get-Item -LiteralPath $source -Force
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Authorization ledger staging rejects reparse-point inputs.'}
        $sourceHash=Get-Hash $source;$sourceBytes=[int64]$item.Length;$row=Read-Json $source
        if([string]$row.policyId -cne [string]$entry.policyId){throw "Authorization ledger policy substitution rejected: $relative"}
        $sources[[string]$entry.policyId]=[pscustomobject]@{row=$row;path=$relative;sha256=$sourceHash;bytes=$sourceBytes}
    }
    $b=$sources['DF-RDC-CERTIFICATION-CONTINUATION-20260924-B'];$a=$sources['DF-AUDIT-CONVERGENCE-20260924-A']
    if([string]$b.row.continuation.predecessor.path -cne [string]$a.path -or [string]$b.row.continuation.predecessor.sha256 -cne [string]$a.sha256){throw 'Adopted authorization ledger predecessor/hash closure is inconsistent.'}
    foreach($entry in $selected){
        $relative='evidence/campaigns/'+[string]$entry.name;$source=Join-Path $Repository ('evidence\campaigns\'+[string]$entry.name);$destination=Join-Path $EvidenceRoot ('campaigns\'+[string]$entry.name)
        if(-not(Add-CompactFile $source $destination)){throw "Authorization ledger disappeared during staging: $relative"}
        if((Get-Hash $source) -cne $sources[[string]$entry.policyId].sha256 -or (Get-Hash $destination) -cne $sources[[string]$entry.policyId].sha256 -or [int64](Get-Item -LiteralPath $destination).Length -ne $sources[[string]$entry.policyId].bytes){throw "Authorization ledger hash/length changed during staging: $relative"}
        $row=$sources[[string]$entry.policyId].row
        $adoptedAt=$row.authorization.adoptedAtUtc;if($adoptedAt -is [datetime]){$adoptedAt=$adoptedAt.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
        $rows.Add([ordered]@{policyId=[string]$entry.policyId;sourcePath=$relative;sourceBytes=$sources[[string]$entry.policyId].bytes;sourceSha256=$sources[[string]$entry.policyId].sha256;stagedPath='evidence/campaigns/'+[string]$entry.name;stagedBytes=[int64](Get-Item -LiteralPath $destination).Length;stagedSha256=(Get-Hash $destination);status=[string]$row.status;adoptedAtUtc=[string]$adoptedAt;counters=$row.counters;baseline=$row.baseline;maximumTopLevelInvocations=$row.maximumTopLevelInvocations;sharedCorrectivePool=$row.sharedCorrectivePool;activeReservationPresent=($null -ne $row.activeReservation)})
    }
    $malformedPath='evidence/campaigns/df-tailscale-peer-convergence-20260921-a-ledger.json';$malformed=$null
    $historical=$a.row.continuation.preservedLedgerFiles|Where-Object{[string]$_.path -ceq $malformedPath}|Select-Object -First 1
    if($historical){$malformedSource=Join-Path $Repository ($malformedPath.Replace('/','\'));$actualHash=if(Test-Path -LiteralPath $malformedSource -PathType Leaf){Get-Hash $malformedSource}else{''};$matches=($actualHash -ceq [string]$historical.sha256);$malformed=[ordered]@{path=$malformedPath;recordedSourceSha256=[string]$historical.sha256;observedSourceSha256=$actualHash;sourceHashMatchesRecorded=$matches;parseStatus=if($matches){[string]$historical.observedParseStatus}else{'SOURCE_HASH_MISMATCH'};authorizationInterpretation='UNKNOWN'}}
    $projection=[ordered]@{schemaVersion=1;kind='SANITIZED_REVIEW_PROJECTION';authority=$false;runtimeAuthorizationGranted=$false;ledgers=@($rows);malformedHistoricalLedger=$malformed}
    $projectionPath=Join-Path $EvidenceRoot 'campaigns\authorization-ledger-closure.json';Write-Json $projectionPath $projection
    $projectionText=Get-Content -LiteralPath $projectionPath -Raw
    if($projectionText -match '(?i)"(password|secret|hmac|dpapi|privateKey)"\s*:'){throw 'Authorization review projection contains a prohibited secret-bearing field.'}
    return $projection
}
function Add-AstraCausalEvidence([string]$Repository,[string]$EvidenceRoot) {
    # This frozen allowlist retains historical causal bytes, never proof credit.
    # Do not discover runs by timestamps or recursively adopt diagnostic folders.
    $manifestPath=Join-Path $Repository 'tools/astra-causal-evidence.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop|ConvertFrom-Json
    if($manifest.schemaVersion -ne 1 -or -not @($manifest.records).Count){throw 'Astra causal evidence allowlist is empty or unsupported.'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($record in $manifest.records){
        $relative=[string]$record.source;$destination=[string]$record.destination
        if($relative -notmatch '^audit/automation-harness/[A-Za-z0-9._/-]+$' -or $relative.Split('/') -contains '..' -or $relative.Split('/') -contains '.' -or $relative.Contains('//')){throw 'Astra causal source escapes its allowlisted namespace.'}
        if($destination -notmatch '^[A-Za-z0-9_-]+/[A-Za-z0-9._/-]+$' -or $destination.Split('/') -contains '..' -or $destination.Split('/') -contains '.' -or $destination.Contains('//')){throw 'Astra causal destination is malformed.'}
        if(@($destination.Split('/')|Where-Object{$_ -in @('snapshots','outputs','build','dist','.git')}).Count -or -not $seen.Add($destination)){throw 'Astra causal destination is excluded or duplicated.'}
        if([string]$record.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Astra causal evidence hash is malformed.'}
        $source=Join-Path $Repository $relative
        if(-not(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Hash $source) -cne [string]$record.sha256){throw "Astra causal evidence is missing or changed: $relative"}
        $target=Join-Path $EvidenceRoot ('astra-causal/'+$destination)
        if(-not(Add-CompactFile $source $target) -or (Get-Hash $target) -cne [string]$record.sha256){throw "Astra causal evidence copy did not verify: $relative"}
    }
    if(-not(Add-CompactFile $manifestPath (Join-Path $EvidenceRoot 'astra-causal/allowlist.json'))){throw 'Astra causal allowlist was not retained.'}
    return $seen.Count
}
function Add-GitBlob([string]$Commit,[string]$RepositoryPath,[string]$Destination) {
    $code='import pathlib,subprocess,sys; data=subprocess.check_output(["git","-C",sys.argv[1],"show",sys.argv[2]]); pathlib.Path(sys.argv[3]).write_bytes(data)'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    & $python -c $code $Workspace ("$Commit`:$RepositoryPath") $Destination
    if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $Destination -PathType Leaf)){throw "Could not recover exact historical Git blob $Commit`:$RepositoryPath."}
    return $true
}
function Find-Artifact([object[]]$Rows,[string]$Leaf) { return @($Rows | Where-Object { [IO.Path]::GetFileName([string]$_.path) -eq $Leaf } | Select-Object -First 1)[0] }

New-Item -ItemType Directory -Force -Path $Outputs,$Audit,$stage,$sourceStage,$installerStage,$automationStage,$toolingStage,$evidenceStage,$auditStage,$outputMetadataStage | Out-Null
try {
    $statePath = Join-Path $Workspace 'finalization-state.json'
    $artifactPath = Join-Path $Outputs 'final-artifact-hashes.json'
    if (-not (Test-Path -LiteralPath $statePath) -or -not (Test-Path -LiteralPath $artifactPath)) { throw 'Current candidate state or artifact manifest is missing.' }
    $state = Read-Json $statePath
    $artifactManifest = Read-Json $artifactPath
    $preAcceptanceAudit = $Operation -eq 'PreAcceptanceReleaseAudit'
    $releaseValidator = Join-Path $Workspace 'tools\validate_release_bundle.py'
    $workspaceValidation = $null
    if ($preAcceptanceAudit) {
        $workspaceValidationOutput = @(& $python $releaseValidator --workspace-root $Workspace --check release-evidence 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Pre-acceptance RELEASE audit refused current evidence: $($workspaceValidationOutput -join "`n")" }
        try { $workspaceValidation = ($workspaceValidationOutput -join "`n") | ConvertFrom-Json } catch { throw 'Pre-acceptance workspace validator did not return JSON.' }
        if ([string]$workspaceValidation.status -ne 'PASS' -or [bool]$workspaceValidation.releaseEligible) { throw 'Pre-acceptance workspace validation was not a non-promoting PASS.' }
    } else {
        $finalValidationOutput = @(& $python $releaseValidator --workspace-root $Workspace --check final-acceptance 2>&1)
        $finalAcceptanceValid = $LASTEXITCODE -eq 0
        if ($finalAcceptanceValid) {
            try { $workspaceValidation = ($finalValidationOutput -join "`n") | ConvertFrom-Json } catch { $finalAcceptanceValid = $false }
        }
        if ($finalAcceptanceValid -and ([string]$workspaceValidation.status -ne 'PASS' -or -not [bool]$workspaceValidation.internalPromotionAllowed)) { $finalAcceptanceValid = $false }
    }
    $releaseFingerprintPath = Join-Path $Outputs 'release-fingerprint.json'
    $toolingCurrentPath = Join-Path $Outputs 'tooling-fingerprint-current.json'
    $advisoryPath = Join-Path $Outputs 'dependency-advisory-gate.json'
    $osvReconciliationPath = Join-Path $Outputs 'independent-osv-reconciliation.json'
    $signingProviderPath = Join-Path $Outputs 'signing-provider.json'
    if (-not (Test-Path -LiteralPath $releaseFingerprintPath -PathType Leaf) -or -not (Test-Path -LiteralPath $toolingCurrentPath -PathType Leaf) -or -not (Test-Path -LiteralPath $advisoryPath -PathType Leaf) -or -not (Test-Path -LiteralPath $osvReconciliationPath -PathType Leaf) -or -not (Test-Path -LiteralPath $signingProviderPath -PathType Leaf)) { throw 'Current release identity, signing provider, or dependency advisory evidence is missing.' }
    $releaseFingerprint = Read-Json $releaseFingerprintPath
    $toolingCurrent = Read-Json $toolingCurrentPath
    $signingProvider = Read-Json $signingProviderPath
    if ([int]$releaseFingerprint.schemaVersion -ne 2 -or [int]$toolingCurrent.schemaVersion -ne 2 -or [int]$toolingCurrent.releaseFingerprintSchemaVersion -ne 2) { throw 'Current audit identity must use release fingerprint schema v2.' }
    if ([int]$signingProvider.schemaVersion -ne 1 -or [bool]$signingProvider.privateKeyExported -or [bool]$signingProvider.privateKeyExportable -or [bool]$signingProvider.publicPublisherTrust -or [bool]$signingProvider.publicPromotionAllowed) { throw 'Signing provider metadata is missing or violates the private-signing release contract.' }
    $artifactRows = @($artifactManifest.artifacts)
    $branch = (& git -C $Workspace branch --show-current).Trim()
    $head = (& git -C $Workspace rev-parse HEAD).Trim()
    # Candidate currency is bound to deterministic shipping-input identity;
    # repository/tooling HEAD may advance without changing shipping bytes.
    $gitClean = (@(& git -C $Workspace status --porcelain) | Measure-Object).Count -eq 0

    $artifactNames = [ordered]@{
        exe = "DevFleet-Setup-v$releaseVersion-win-x64.exe"
        tar = "devfleet-v$releaseVersion.tar.gz"
        portable = "DevFleet-v$releaseVersion-Portable-Codebase-Verified-r1.zip"
        installerSource = "DevFleet-v$releaseVersion-Installer-Source.zip"
    }
    $candidateArtifacts = [ordered]@{}
    foreach ($key in $artifactNames.Keys) {
        $row = Find-Artifact $artifactRows $artifactNames[$key]
        $path = if ($row) { [string]$row.path } else { Join-Path $Outputs $artifactNames[$key] }
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $Workspace $path }
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $candidateArtifacts[$key] = [ordered]@{
            name = $artifactNames[$key]; path = (Rel $path); bytes = if ($exists) { [int64](Get-Item -LiteralPath $path).Length } else { 0 }
            sha256 = if ($exists) { Get-Hash $path } else { '' }
            manifestSha256 = if ($row) { [string]$row.sha256 } else { '' }
            exists = $exists
        }
    }
    $releaseId = [string]$state.releaseFingerprintId
    $toolingId = [string]$state.toolingFingerprintId
    $sourceChanged = [bool]$state.source_changed_since_candidate
    $rebuildRequired = [bool]$state.rebuild_required
    $workingToolingId = [string]$state.working_tree_tooling_fingerprint_id
    if (-not $releaseId -or -not $toolingId) { throw 'Current state has no release/tooling fingerprint tuple.' }
    if ($artifactManifest.releaseFingerprintId -ne $releaseId -or $artifactManifest.toolingFingerprintId -ne $toolingId) { throw 'Artifact manifest disagrees with finalization state fingerprints.' }
    if ($releaseFingerprint.releaseFingerprintId -ne $releaseId -or $releaseFingerprint.toolingFingerprint.toolingFingerprintId -ne $toolingId -or $toolingCurrent.releaseFingerprintId -ne $releaseId -or $toolingCurrent.toolingFingerprintId -ne $toolingId) { throw 'Current release/tooling fingerprint files disagree with finalization state.' }
    foreach ($item in $candidateArtifacts.Values) {
        if (-not $item.exists -or $item.sha256 -ne $item.manifestSha256) { $artifactMismatch = $true }
    }
    $candidateCommit = [string]$state.candidateGitCommit
    if (-not $candidateCommit) { $candidateCommit = [string]$state.candidate_git_commit }
    if (-not $candidateCommit) { $candidateCommit = [string]$state.candidateCommit }
    if (-not $candidateCommit) { $candidateCommit = $head }
    if ($candidateCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'Candidate commit is missing or malformed.' }
    $failedAttemptSnapshotRelative = 'audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json'
    $failedAttemptSnapshotPath = Join-Path $Workspace ($failedAttemptSnapshotRelative -replace '/','\')
    $failedAttemptContract = (Test-Path -LiteralPath $failedAttemptSnapshotPath -PathType Leaf) -and
        $candidateCommit -eq '21752fc0e50