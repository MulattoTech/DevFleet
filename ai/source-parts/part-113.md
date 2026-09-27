# DevFleet source part 113

Full-source UTF-8 byte interval [5208000, 5254500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 89f3e2da14a65f7bb1085b8ec2540f48994e87ef6a0640a0553830e42f73c8fb

<!-- BEGIN SOURCE SLICE -->
Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $taskDescription -Force | Out-Null
$taskBinding = [ordered]@{Name=$taskName;Executable=$powerShellPath;Arguments=$taskArguments;Principal='SYSTEM';LogonType='ServiceAccount';RunLevel='Highest';Description=$taskDescription;Generation=$generation;Marker='M-TechLabs DevFleet Host Agent';Version=$version}
$firewallBindings = @()
Remove-PriorOwnedFirewallRules -Ownership $existingOwnership
if (-not $SkipFirewall) {
    $multipassAdapter = Get-NetAdapter -Name 'vEthernet (Default Switch)' -ErrorAction SilentlyContinue
    $tailscaleAdapter = Get-NetAdapter -Name 'Tailscale' -ErrorAction SilentlyContinue
    if ($multipassAdapter) {
        $multipassAddress = Get-NetIPAddress -InterfaceIndex $multipassAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1
        if (-not $multipassAddress) { throw 'Multipass adapter has no usable IPv4 subnet; refusing a broad host-agent firewall rule.' }
        $multipassSubnet = ConvertTo-DevFleetCanonicalFirewallRemoteAddress "$($multipassAddress.IPAddress)/$($multipassAddress.PrefixLength)"
        $firewallBindings += [ordered]@{Name="DevFleetHostAgent-$Port-Multipass";DisplayName="DevFleet Host Agent $Port - Multipass";Group='M-TechLabs DevFleet Host Agent';Description="M-TechLabs DevFleet Host Agent v$version; generation=$generation; scope=Multipass";Direction='Inbound';Action='Allow';Protocol='TCP';LocalPort=[string]$Port;InterfaceAlias=[string]$multipassAdapter.Name;RemoteAddress=$multipassSubnet;Profile='Any';Generation=$generation;Marker='M-TechLabs DevFleet Host Agent';Version=$version}
    }
    if ($tailscaleAdapter) {
        $firewallBindings += [ordered]@{Name="DevFleetHostAgent-$Port-Tailscale";DisplayName="DevFleet Host Agent $Port - Tailscale";Group='M-TechLabs DevFleet Host Agent';Description="M-TechLabs DevFleet Host Agent v$version; generation=$generation; scope=Tailscale";Direction='Inbound';Action='Allow';Protocol='TCP';LocalPort=[string]$Port;InterfaceAlias=[string]$tailscaleAdapter.Name;RemoteAddress=(ConvertTo-DevFleetCanonicalFirewallRemoteAddress '100.64.0.0/10');Profile='Any';Generation=$generation;Marker='M-TechLabs DevFleet Host Agent';Version=$version}
    }
    if (-not $multipassAdapter -and -not $tailscaleAdapter) { throw 'No supported narrow host-agent interface was found; refusing a broad firewall rule.' }

    foreach ($desired in $firewallBindings) {
        $sameDisplay = @(Get-NetFirewallRule -DisplayName ([string]$desired.DisplayName) -ErrorAction SilentlyContinue)
        foreach ($live in $sameDisplay) {
            $owned = @()
            if ($existingOwnership) { $owned = @($existingOwnership.FirewallRules | Where-Object { [string]$_.Name -eq [string]$live.Name }) }
            $portFilter = $live | Get-NetFirewallPortFilter; $addressFilter = $live | Get-NetFirewallAddressFilter; $interfaceFilter = $live | Get-NetFirewallInterfaceFilter
            $actual = @{Name=[string]$live.Name;DisplayName=[string]$live.DisplayName;Group=[string]$live.Group;Description=[string]$live.Description;Direction=[string]$live.Direction;Action=[string]$live.Action;Protocol=[string]$portFilter.Protocol;LocalPort=[string]$portFilter.LocalPort;InterfaceAlias=[string]$interfaceFilter.InterfaceAlias;RemoteAddress=[string]$addressFilter.RemoteAddress;Profile=[string]$live.Profile;Generation=if($owned.Count -eq 1){[string]$owned[0].Generation}else{'legacy-explicit-adoption'}}
            if ($owned.Count -eq 1) { Assert-DevFleetFirewallBinding -Expected $owned[0] -Actual $actual | Out-Null }
            elseif ($AdoptLegacyDevFleetIntegrations) {
                $legacyExpected = @{}
                foreach ($key in $desired.Keys) { $legacyExpected[$key] = $desired[$key] }
                $legacyExpected.Name=[string]$live.Name;$legacyExpected.Group=[string]$live.Group;$legacyExpected.Description=[string]$live.Description;$legacyExpected.Generation='legacy-explicit-adoption'
                Assert-DevFleetFirewallBinding -Expected $legacyExpected -Actual $actual | Out-Null
            } else { throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: same-name firewall rule '$($desired.DisplayName)' has no owned binding. Foreign rule preserved." }
            $live | Remove-NetFirewallRule -Confirm:$false
        }
        New-NetFirewallRule -Name ([string]$desired.Name) -DisplayName ([string]$desired.DisplayName) -Group ([string]$desired.Group) -Description ([string]$desired.Description) -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -RemoteAddress ([string]$desired.RemoteAddress) -InterfaceAlias ([string]$desired.InterfaceAlias) -Profile Any | Out-Null
    }
}
$integrationLedger = [ordered]@{SchemaVersion=1;InstallationGeneration=$generation;DevFleetVersion=$version;Marker='M-TechLabs DevFleet Host Agent';ScheduledTasks=@($taskBinding);FirewallRules=@($firewallBindings);Services=@();UpdatedUtc=(Get-Date).ToUniversalTime().ToString('o')}
Write-DevFleetIntegrationOwnership -Path $ownershipPath -Ledger $integrationLedger
Start-ScheduledTask -TaskName $taskName
$healthExpectedHost = if($expectedHost){$expectedHost}else{$env:COMPUTERNAME}
for ($i = 0; $i -lt 30; $i++) {
    try { $health = Invoke-HostAgentAuthenticatedJson -Uri "http://127.0.0.1:$Port/healthz" -Method GET -Key $token -ExpectedHost $healthExpectedHost; if ($health.ok) { $health | ConvertTo-Json -Compress; exit 0 } } catch {}
    Start-Sleep -Seconds 1
}
throw 'DevFleet host agent did not pass its local health check.'

```


## FILE: source/windows/Invoke-Quarantine-Maintenance.ps1

SHA256: 6770649aab6111d099e0ef4652238910cbfc61a69b4815686fadf052068e6eb8 | Bytes: 865 | Git mode: 100644

```
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([int]$OlderThanDays=30,[string]$InstanceName)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$mp=Get-MultipassExe
if(-not $InstanceName){$InstanceName=$config.Failover.InstanceName}
Write-Warning 'This is the only included permanent project-file deletion path. Verify GitHub and vault backups first.'
$phrase=Read-Host "Type PURGE QUARANTINE $InstanceName to continue"
if($phrase -ne "PURGE QUARANTINE $InstanceName"){throw 'Confirmation phrase did not match.'}
if($PSCmdlet.ShouldProcess($InstanceName,"Permanently delete quarantine entries older than $OlderThanDays days")){
 Invoke-External $mp @('exec',$InstanceName,'--','sudo','-u','devrunner','/usr/local/bin/devfleet-purge-quarantine',[string]$OlderThanDays)
}

```


## FILE: source/windows/Invoke-Vault-Maintenance.ps1

SHA256: ebf2557670dfd98191f8918699b08ef6607f166429943034fb96f2d4473944dd | Bytes: 611 | Git mode: 100644

```
[CmdletBinding(SupportsShouldProcess)]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$config=Get-DevFleetConfig;$mp=Get-MultipassExe;$name=$config.Vault.InstanceName
if($PSCmdlet.ShouldProcess($name,'Stop append-only server temporarily, apply retention locally, prune and check repository')){
 Invoke-External $mp @('snapshot',$name,'--name',"pre-maintenance-$((Get-Date).ToString('yyyyMMdd-HHmmss'))") -IgnoreExitCode
 Invoke-External $mp @('exec',$name,'--','sudo','/usr/local/sbin/devfleet-vault-maintenance',[string]$config.Backup.KeepWithin)
}

```


## FILE: source/windows/Migrate-Config.ps1

SHA256: 05506c1475b1562de935be365873970bb297f6f5adff8d281d7b82db9e20ec7f | Bytes: 2289 | Git mode: 100644

```
[CmdletBinding(SupportsShouldProcess)]
param([string]$ConfigPath=(Join-Path $env:ProgramData 'DevFleet\devfleet.config.json'),[string]$OutputPath=$ConfigPath,[switch]$PreviewOnly)
$ErrorActionPreference='Stop';$package=Split-Path -Parent $PSScriptRoot;$defaults=Get-Content (Join-Path $package 'config\devfleet.config.json') -Raw|ConvertFrom-Json -AsHashtable;$existing=Get-Content $ConfigPath -Raw|ConvertFrom-Json -AsHashtable
if([int]$existing.SchemaVersion -gt 2){throw "Configuration schema $($existing.SchemaVersion) is newer than supported."}
function Merge-Map([System.Collections.IDictionary]$Base,[System.Collections.IDictionary]$Overlay){$r=[ordered]@{};foreach($k in $Base.Keys){$v=$Base[$k];$r[$k]=if($v -is [System.Collections.IDictionary]){Merge-Map $v @{}}else{$v}};foreach($k in $Overlay.Keys){$v=$Overlay[$k];if($v -is [System.Collections.IDictionary] -and $r.Contains($k) -and $r[$k] -is [System.Collections.IDictionary]){$r[$k]=Merge-Map $r[$k] $v}else{$r[$k]=$v}};return $r}
$m=Merge-Map $defaults $existing
if([int]$existing.SchemaVersion -eq 1){$m.Development.Profile='strict';$m.Docker.PrimaryMode='rootless';$m.Docker.FailoverMode='rootless'}
$m.SchemaVersion=2;$m.PackageVersion='1.1.0';$m.Primary.InstanceName=[string]$existing.Primary.InstanceName;$m.Failover.InstanceName=[string]$existing.Failover.InstanceName;$m.Vault.InstanceName=[string]$existing.Vault.InstanceName
$preview=[ordered]@{Source=$ConfigPath;Output=$OutputPath;PreviousSchema=[int]$existing.SchemaVersion;NewSchema=2;PreservedInstanceNames=@($m.Primary.InstanceName,$m.Failover.InstanceName,$m.Vault.InstanceName);DevelopmentProfile=$m.Development.Profile;PrimaryDockerMode=$m.Docker.PrimaryMode;FailoverDockerMode=$m.Docker.FailoverMode;MigrationSafety='Existing values, instance names, Docker stores, credentials and data are preserved';Generated=(Get-Date).ToString('o')}
$previewPath=Join-Path (Split-Path $OutputPath) "devfleet-v1.1.0-migration-preview-$((Get-Date).ToString('yyyyMMdd-HHmmss')).json";$preview|ConvertTo-Json -Depth 20|Set-Content $previewPath -Encoding utf8;Write-Host ($preview|ConvertTo-Json -Depth 20)
if($PreviewOnly){return};if($PSCmdlet.ShouldProcess($OutputPath,'Write schema-2 configuration')){$m|ConvertTo-Json -Depth 40|Set-Content $OutputPath -Encoding utf8}

```


## FILE: source/windows/Remove-DevFleet-OwnedIntegrations.ps1

SHA256: a3fa2f7e42741649e8c5098b24574a4d2dd49b0c6f1815f5df25e096e64e1d80 | Bytes: 4357 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$OwnershipPath = 'C:\ProgramData\DevFleetHostAgent\integration-ownership.json',
    [Parameter(Mandatory)][string]$ExpectedGeneration
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet-WindowsIntegrationOwnership.psm1') -Force
$canonicalOwnershipPath = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'DevFleetHostAgent\integration-ownership.json'))
if (-not [IO.Path]::GetFullPath($OwnershipPath).Equals($canonicalOwnershipPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'Windows integration ownership ledger path is not canonical; all resources preserved.' }
$ledger = Read-DevFleetIntegrationOwnership -Path $OwnershipPath
if ([string]$ledger.InstallationGeneration -ne $ExpectedGeneration) { throw 'Windows integration ownership generation changed; foreign resources preserved.' }

foreach ($binding in @($ledger.ScheduledTasks)) {
    $task = Get-ScheduledTask -TaskName ([string]$binding.Name) -ErrorAction SilentlyContinue
    if (-not $task) { continue }
    if (@($task.Actions).Count -ne 1) { throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: scheduled task action count changed. Foreign resource preserved.' }
    $actual = @{
        Name=[string]$task.TaskName; Executable=[string]$task.Actions[0].Execute; Arguments=[string]$task.Actions[0].Arguments
        Principal=[string]$task.Principal.UserId; LogonType=[string]$task.Principal.LogonType; RunLevel=[string]$task.Principal.RunLevel
        Description=[string]$task.Description; Generation=[string]$binding.Generation
    }
    Assert-DevFleetTaskBinding -Expected $binding -Actual $actual | Out-Null
    Stop-ScheduledTask -TaskName ([string]$binding.Name) -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName ([string]$binding.Name) -Confirm:$false
}

foreach ($binding in @($ledger.FirewallRules)) {
    $rules = @(Get-NetFirewallRule -Name ([string]$binding.Name) -ErrorAction SilentlyContinue)
    if ($rules.Count -eq 0) { continue }
    if ($rules.Count -ne 1) { throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall identity is ambiguous. Foreign resources preserved.' }
    $rule = $rules[0]; $port = $rule | Get-NetFirewallPortFilter; $address = $rule | Get-NetFirewallAddressFilter; $interface = $rule | Get-NetFirewallInterfaceFilter
    $actual = @{
        Name=[string]$rule.Name; DisplayName=[string]$rule.DisplayName; Group=[string]$rule.Group; Description=[string]$rule.Description
        Direction=[string]$rule.Direction; Action=[string]$rule.Action; Protocol=[string]$port.Protocol; LocalPort=[string]$port.LocalPort; Profile=[string]$rule.Profile
        InterfaceAlias=[string]$interface.InterfaceAlias; RemoteAddress=[string]$address.RemoteAddress; Generation=[string]$binding.Generation
    }
    Assert-DevFleetFirewallBinding -Expected $binding -Actual $actual | Out-Null
    $rule | Remove-NetFirewallRule -Confirm:$false
}

foreach ($binding in @($ledger.Services)) {
    $escapedServiceName = ([string]$binding.Name).Replace('"','""')
    $serviceFilter = "Name=`"$escapedServiceName`""
    $service = Get-CimInstance Win32_Service -Filter $serviceFilter -ErrorAction SilentlyContinue
    if (-not $service) { continue }
    $actual = @{Name=[string]$service.Name;ImagePath=[string]$service.PathName;Account=[string]$service.StartName;StartMode=[string]$service.StartMode;Generation=[string]$binding.Generation}
    Assert-DevFleetServiceBinding -Expected $binding -Actual $actual | Out-Null
    Stop-Service -Name ([string]$binding.Name) -ErrorAction SilentlyContinue
    & (Join-Path $env:SystemRoot 'System32\sc.exe') delete ([string]$binding.Name) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Owned service deletion failed: $($binding.Name)" }
}

foreach ($binding in @($ledger.ScheduledTasks)) { if (Get-ScheduledTask -TaskName ([string]$binding.Name) -ErrorAction SilentlyContinue) { throw "Owned scheduled task remains after cleanup: $($binding.Name)" } }
foreach ($binding in @($ledger.FirewallRules)) { if (Get-NetFirewallRule -Name ([string]$binding.Name) -ErrorAction SilentlyContinue) { throw "Owned firewall rule remains after cleanup: $($binding.Name)" } }
foreach ($binding in @($ledger.Services)) { if (Get-Service -Name ([string]$binding.Name) -ErrorAction SilentlyContinue) { throw "Owned service remains after cleanup: $($binding.Name)" } }

```


## FILE: source/windows/Repair-DevFleet.ps1

SHA256: a0c494824681657502694ef8cdd9622a247a9401d549fefb17fdbf37632e9ad5 | Bytes: 728 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstanceName)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
$mp=Get-MultipassExe
Invoke-External $mp @('set','local.privileged-mounts=false')
Assert-MultipassIsolation -InstanceNames @($InstanceName)
# Snapshot before repair. No deletions or pruning.
$snap="pre-repair-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
New-DevFleetSnapshotSafe -InstanceName $InstanceName -SnapshotName $snap|Out-Null
Invoke-External $mp @('start',$InstanceName) -IgnoreExitCode
Invoke-External $mp @('exec',$InstanceName,'--','sudo','/usr/local/sbin/devfleet-repair')
Write-Host "Safe repair complete. Snapshot: $snap" -ForegroundColor Green

```


## FILE: source/windows/Repair-DevFleetHostSecrets.ps1

SHA256: 6c3233e1643fa8a5e317ee04a98da27b40c297ad15f961a68c5d5ccfd0ceba4b | Bytes: 14840 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('REKEY DEVFLEET HOST SECRETS')][string]$ConfirmReKey
)

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'DevFleet.Common.psm1'
$protocol = Join-Path $PSScriptRoot 'DevFleet-HostAgentProtocol.psm1'
$ownership = Join-Path $PSScriptRoot 'DevFleet-WindowsIntegrationOwnership.psm1'
Import-Module $common -Force
Import-Module $protocol -Force
Import-Module $ownership -Force
Assert-PowerShell7
Assert-Administrator
if (-not (Test-ExistingDeploymentState)) { throw 'SECRET RECOVERY REQUIRED applies only to an existing deployment; use normal fresh installation for a new host.' }

function Write-AtomicUtf8 {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text)
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,$Text,[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Get-ExactGuestIdentity {
    param([Parameter(Mandatory)][string]$Multipass,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Path)
    $raw = Invoke-External $Multipass @('exec',$Name,'--','sudo','cat',$Path) -Capture
    try { return $raw | ConvertFrom-Json }
    catch { throw "SECRET RECOVERY REQUIRED: $Name returned invalid immutable identity evidence." }
}

$stateRoot = Get-DevFleetStateRoot
$config = Get-DevFleetConfig
$hostIdentityPath = Join-Path $stateRoot 'node-identity.json'
$hostIdentity = Get-Content -LiteralPath $hostIdentityPath -Raw | ConvertFrom-Json
if ([string]$hostIdentity.node_id -notmatch '^[0-9a-fA-F-]{36}$' -or [string]$hostIdentity.deployment_id -notmatch '^[0-9a-fA-F-]{36}$') {
    throw 'SECRET RECOVERY REQUIRED: deployment/node inventory is incomplete; no credentials were changed.'
}
$generation = [guid]::NewGuid().ToString('D')
$newSecrets = New-DevFleetSecretRecord -Generation $generation
$newHostToken = New-RandomSecret 40
$multipass = Get-MultipassExe
$instances = @(Get-MultipassInstances)
$computeName = if ([string]$hostIdentity.node_role -eq 'primary') { [string]$config.Primary.InstanceName } elseif ([string]$hostIdentity.node_role -eq 'surrogate') { [string]$config.Failover.InstanceName } else { throw 'SECRET RECOVERY REQUIRED: unsupported host node role.' }
if (@($instances | Where-Object name -eq $computeName).Count -ne 1) { throw "SECRET RECOVERY REQUIRED: exact compute instance inventory is ambiguous or missing: $computeName" }
Assert-MultipassIsolation -InstanceNames @($computeName)
Invoke-External $multipass @('start',$computeName) -IgnoreExitCode
$computeIdentity = Get-ExactGuestIdentity -Multipass $multipass -Name $computeName -Path '/etc/devfleet/node-identity.json'
if ([string]$computeIdentity.node_id -ne [string]$hostIdentity.node_id -or [string]$computeIdentity.deployment_id -ne [string]$hostIdentity.deployment_id -or [string]$computeIdentity.node_name -ne $computeName) {
    throw 'SECRET RECOVERY REQUIRED: compute identity does not match the exact deployment inventory; no credentials were changed.'
}

$vaultName = $null
$vaultIdentity = $null
if ([string]$hostIdentity.node_role -eq 'surrogate') {
    $vaultName = [string]$config.Vault.InstanceName
    if (@($instances | Where-Object name -eq $vaultName).Count -ne 1) { throw "SECRET RECOVERY REQUIRED: exact vault instance inventory is ambiguous or missing: $vaultName" }
    $vaultIdentityPath = Join-Path $stateRoot 'vault-node-identity.json'
    if (-not (Test-Path -LiteralPath $vaultIdentityPath -PathType Leaf)) { throw 'SECRET RECOVERY REQUIRED: vault identity metadata is missing; use the explicit legacy vault-adoption procedure before re-keying.' }
    $vaultIdentity = Get-Content -LiteralPath $vaultIdentityPath -Raw | ConvertFrom-Json
    Assert-MultipassIsolation -InstanceNames @($vaultName)
    Invoke-External $multipass @('start',$vaultName) -IgnoreExitCode
    $liveVaultIdentity = Get-ExactGuestIdentity -Multipass $multipass -Name $vaultName -Path '/etc/devfleet-vault-identity.json'
    if ([string]$vaultIdentity.deployment_id -ne [string]$hostIdentity.deployment_id -or [string]$liveVaultIdentity.deployment_id -ne [string]$hostIdentity.deployment_id -or [string]$liveVaultIdentity.node_id -ne [string]$vaultIdentity.node_id -or [string]$liveVaultIdentity.node_name -ne $vaultName) {
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