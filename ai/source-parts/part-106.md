# DevFleet source part 106

Full-source UTF-8 byte interval [4882500, 4929000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: bc34910005215268fc5fdd545f19591c8492331febc0b76ec961f19411a4b4bf

<!-- BEGIN SOURCE SLICE -->
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
        raise SystemExit("workspace archive contains a link or special file")
    members.append(name)
    return info

with tarfile.open(archive, "w:gz") as bundle:
    bundle.add(root, arcname=slug, recursive=True, filter=archive_filter)
if not members:
    raise SystemExit("workspace archive is empty")
digest = hashlib.sha256()
with Path(archive).open("rb") as stream:
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(block)
digest = digest.hexdigest()
print(json.dumps({"archive_sha256": digest, "member_count": len(members)}))
'@
    $result=Invoke-Multipass @('exec',$VmName,'--','sudo','python3','-c',$archiveScript,$Archive,$workspace,$Slug,([string]$IncludeGenerated)) 1200
    try{$inspection=$result.Text|ConvertFrom-Json -AsHashtable}catch{throw 'Project VM did not return valid workspace archive verification JSON.'}
    if([string]$inspection.archive_sha256 -notmatch '^[0-9a-f]{64}$' -or [int]$inspection.member_count -lt 1){throw 'Project VM returned incomplete workspace archive verification.'}
    return $inspection
}

function Get-HostCapacity {
    $computer = Get-CimInstance Win32_ComputerSystem;$os = Get-CimInstance Win32_OperatingSystem
    $processor = Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum
    $drive = $env:SystemDrive.TrimEnd(':') + ':';$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'"
    $registry = Read-Registry;$committedCpu = 0.0;$committedMemory = 0.0;$committedDisk = 0.0;$vmCount = 0
    foreach ($item in $registry.projects.Values) {
        if ($item.state -notin @('destroyed')) { $committedCpu += [double]$item.cpus;$committedMemory += [double]$item.memory_gb;$committedDisk += [double]$item.disk_gb;$vmCount++ }
    }
    $policy = Get-Policy
    $totalGb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
    $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
    $availableGb = [math]::Round([double]$memory.AvailableBytes / 1GB, 2)
    $commitGb = 0.0; $commitLimitGb = 0.0
    try {
        $commitGb = [math]::Round((Get-Counter '\Memory\Committed Bytes' -MaxSamples 1 -ErrorAction Stop).CounterSamples.CookedValue / 1GB, 2)
        $commitLimitGb = [math]::Round((Get-Counter '\Memory\Commit Limit' -MaxSamples 1 -ErrorAction Stop).CounterSamples.CookedValue / 1GB, 2)
    } catch {}
    $diskFreeGb = [math]::Round($disk.FreeSpace / 1GB, 2)
    $reservedCpu = [double]$policy.ReservedLogicalProcessors
    $reservedDisk = [double]$policy.ReservedHostDiskGb
    $physicalFloor = [math]::Max([double]$policy.PhysicalFloorMinGb, $totalGb * [double]$policy.PhysicalFloorPercent)
    $commitFloor = [math]::Max([double]$policy.CommitHeadroomFloorMinGb, $commitLimitGb * [double]$policy.CommitHeadroomPercent)
    $commitPercent = if ($commitLimitGb -gt 0) { [math]::Round($commitGb / $commitLimitGb * 100, 2) } else { 100 }
    $resourceExhaustion = @()
    try { $resourceExhaustion = @(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Resource-Exhaustion-Detector';StartTime=(Get-Date).AddMinutes(-10)} -ErrorAction SilentlyContinue) } catch {}
    $commitHeadroom = [math]::Max(0, $commitLimitGb - $commitGb)
    $physicalHealthy = $availableGb -ge $physicalFloor
    $commitHealthy = $commitHeadroom -ge $commitFloor -and $commitPercent -lt [double]$policy.CommitUsageLimitPercent
    $adaptiveHealthy = $physicalHealthy -and $commitHealthy -and @($resourceExhaustion).Count -eq 0
    $cpuPercent = 0.0
    try { $cpuPercent = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -MaxSamples 1 -ErrorAction Stop).CounterSamples.CookedValue, 1) } catch {}
    return [ordered]@{
        host_id = [string]$script:Config.HostId;host_name = [string]$script:Config.HostName;agent_version = $script:AgentVersion;provider = 'multipass';provider_version = [string]$script:Config.MultipassVersion
        resource_policy_version = [string]$policy.PolicyVersion;logical_cpus = [int]$processor.Sum;total_memory_gb = $totalGb;available_memory_gb = $availableGb;free_memory_gb = $availableGb;cpu_percent = $cpuPercent;disk_free_gb = $diskFreeGb
        physical_floor_gb = [math]::Round($physicalFloor, 2);commit_headroom_floor_gb = [math]::Round($commitFloor, 2);commit_gb = $commitGb;commit_limit_gb = $commitLimitGb;commit_headroom_gb = $commitHeadroom;commit_usage_percent = $commitPercent;resource_exhaustion = @($resourceExhaustion).Count -gt 0
        reserved_host_cpus = $reservedCpu;reserved_host_disk_gb = $reservedDisk
        committed_project_cpus = [math]::Round($committedCpu, 2);committed_project_memory_gb = [math]::Round($committedMemory, 2);committed_project_disk_gb = [math]::Round($committedDisk, 2);managed_vm_count = $vmCount
        allocatable_cpus = [math]::Max(0,[math]::Round([int]$processor.Sum - $reservedCpu - $committedCpu, 2))
        allocatable_memory_gb = [math]::Max(0,[math]::Round([math]::Min($availableGb - $physicalFloor, $commitHeadroom - $commitFloor), 2))
        allocatable_disk_gb = [math]::Max(0,[math]::Round($diskFreeGb - $reservedDisk - $committedDisk, 2))
        health = if (-not $adaptiveHealthy -or $diskFreeGb -lt $reservedDisk -or $cpuPercent -ge 95) { 'degraded' } else { 'healthy' }
    }
}

function Assert-HostCapacity {
    $capacity = Get-HostCapacity;$policy = Get-Policy
    if ($capacity.health -ne 'healthy') { throw 'Host capacity is temporarily below the configured safe threshold. No VM was created.' }
    if ([int]$capacity.managed_vm_count -ge [int]$policy.MaximumVmCount) { throw 'The maximum managed VM count has been reached.' }
    return $capacity
}

function Assert-ResourceRequest {
    param([double]$Cpus,[double]$MemoryGb,[double]$DiskGb)
    $policy = Get-Policy
    if ($Cpus -lt 1 -or $Cpus -gt [double]$policy.MaxProjectCpus) { throw 'Requested project CPU allocation exceeds host-agent policy.' }
    if ($MemoryGb -lt 2 -or $MemoryGb -gt [double]$policy.MaxProjectMemoryGb) { throw 'Requested project memory allocation exceeds host-agent policy.' }
    if ($DiskGb -lt 20 -or $DiskGb -gt [double]$policy.MaxProjectDiskGb) { throw 'Requested project disk allocation exceeds host-agent policy.' }
    $capacity = Assert-HostCapacity
    if ($Cpus -gt $capacity.allocatable_cpus -or $MemoryGb -gt $capacity.allocatable_memory_gb -or $DiskGb -gt $capacity.allocatable_disk_gb) { throw ('Insufficient host capacity. Available: {0} CPU, {1} GB RAM, {2} GB disk.' -f $capacity.allocatable_cpus,$capacity.allocatable_memory_gb,$capacity.allocatable_disk_gb) }
}

function Get-ProjectVmName {
    param([Parameter(Mandatory)][string]$Slug)
    $Slug = Assert-Slug $Slug;$base = "devfleet-project-$Slug"
    if ($base.Length -le 60) { return $base }
    $sha = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Slug));$hash = (($sha | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0,12)
    return "devfleet-project-$($Slug.Substring(0,35))-$hash"
}

function Get-MultipassVms { $result = Invoke-Multipass @('list','--format','json') 30;try { return @((($result.Text | ConvertFrom-Json).list)) } catch { throw 'Multipass did not return valid VM inventory JSON.' } }
function Get-ProjectRecord { param([Parameter(Mandatory)][string]$Slug);$registry=Read-Registry;$key=(Assert-Slug $Slug).ToLowerInvariant();if(-not $registry.projects.ContainsKey($key)){throw 'Project VM is not registered with the DevFleet host agent.'};return $registry.projects[$key] }
function Get-ProjectSlugByRuntime { param([Parameter(Mandatory)][string]$RuntimeId);$registry=Read-Registry;foreach($entry in $registry.projects.GetEnumerator()){if([string]$entry.Value.runtime_id -eq $RuntimeId){return [string]$entry.Key}};throw 'Runtime identity is not registered with the DevFleet host agent.' }
function Assert-OwnedProjectVm { param([Parameter(Mandatory)][string]$Slug,[string]$RuntimeId='', [switch]$AllowStoppedTransition)
    $record=Get-ProjectRecord $Slug;$expected=Get-ProjectVmName $Slug
    if($record.vm_name -ne $expected -or $record.managed_by -ne 'devfleet' -or $record.host_id -ne $script:Config.HostId){throw 'Project VM ownership registry mismatch.'}
    if($RuntimeId -and $record.runtime_id -ne $RuntimeId){throw 'Runtime identity does not match the ownership registry.'}
    $inventory=@(Get-MultipassVms|Where-Object{$_.name -eq $record.vm_name});if($inventory.Count -ne 1){throw 'Registered project VM is missing or duplicated.'}
    $info=Get-ProjectVmInfo $record.vm_name
    if([string]$info.state -ne 'RUNNING'){
        if($AllowStoppedTransition){return $record}
        throw 'Live project VM ownership cannot be verified while the guest is stopped; refusing the operation.'
    }
    $runtimeText=(Invoke-Multipass @('exec',$record.vm_name,'--','sudo','cat','/etc/devfleet/project-runtime.json') 30).Text
    try{$runtime=$runtimeText|ConvertFrom-Json -AsHashtable}catch{throw 'Live project VM ownership document is missing or malformed.'}
    foreach($key in @('managed_by','project_id','slug','runtime_id','host_id','provisioning_attempt_id')){
        if([string]$runtime[$key] -ne [string]$record[$key]){throw "Live project VM ownership mismatch for $key; refusing the operation."}
    }
    return $record
}

function New-CloudInit {
    param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)][string]$ProjectId,[string]$GitUrl='', [Parameter(Mandatory)][string]$ProvisioningAttemptId)
    $Slug=Assert-Slug $Slug;$ProjectId=Assert-ProjectId $ProjectId
    if($GitUrl -and $GitUrl -notmatch '^(https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?|git@github\.com:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?)$'){throw 'Only GitHub repository URLs are accepted for VM bootstrap.'}
    $publicKeyPath=[string]$script:Config.SshPublicKeyPath
    if([string]::IsNullOrWhiteSpace($publicKeyPath) -or -not(Test-Path -LiteralPath $publicKeyPath -PathType Leaf)){throw 'Configured DevFleet SSH public key is not available for project VM provisioning.'}
    $key=(Get-Content -LiteralPath $publicKeyPath -Raw).Trim()
    if([string]::IsNullOrWhiteSpace($key) -or $key -match "['\r\n]"){throw 'Configured DevFleet SSH public key is invalid.'}
    $keyProperty="    ssh_authorized_keys:`n      - '$key'"
    $workspace="/home/devrunner/workspaces/$Slug";$cloneLine="mkdir -p '$workspace'";if($GitUrl){$cloneLine="git clone --depth 1 '$GitUrl' '$workspace'"}
    $cloud=@"
#cloud-config
package_update: true
packages:
  - openssh-server
  - git
  - curl
  - ca-certificates
  - docker.io
  - docker-compose-v2
users:
  - default
  - name: devrunner
    groups: [users]
    shell: /bin/bash
$keyProperty
write_files:
  - path: /etc/devfleet/project-runtime.json
    permissions: !!str 0644
    content: |
      {"managed_by":"devfleet","project_id":"$ProjectId","slug":"$Slug","runtime_id":"$(Get-ProjectVmName $Slug)","host_id":"$($script:Config.HostId)","provisioning_attempt_id":"$ProvisioningAttemptId","bootstrap_version":"1","gpu_enabled":false}
  - path: /usr/local/sbin/devfleet-project-health
    permissions: !!str 0755
    content: |
      #!/usr/bin/env bash
      set -eu
      test -f /etc/devfleet/project-runtime.json
      test -d /home/devrunner/workspaces/$Slug
      docker --version >/dev/null
      docker compose version >/dev/null
runcmd:
  - [ bash, -lc, "$cloneLine" ]
  - [ bash, -lc, "mkdir -p /home/devrunner/workspaces/$Slug && chown -R devrunner:devrunner /home/devrunner/workspaces/$Slug" ]
  - [ systemctl, enable, --now, ssh ]
  - [ systemctl, enable, --now, docker ]
"@
    return $cloud
}

function Get-ProjectVmInfo { param([Parameter(Mandatory)][string]$VmName);$result=Invoke-Multipass @('info',$VmName,'--format','json') 30;try{$data=$result.Text|ConvertFrom-Json;if($data.info.$VmName){return $data.info.$VmName};return $data}catch{throw 'Multipass did not return valid project VM information.'} }
function Get-PrimaryProjectVmIpv4 {
    param([Parameter(Mandatory)]$Info)
    if([string]$Info.state -ne 'RUNNING'){throw 'Project VM is not running; its address is unavailable.'}
    $candidates=@($Info.ipv4|Where-Object{$_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and $_ -notmatch '^(127\.|169\.254\.|172\.(17|18|19)\.)'})
    if($candidates.Count -eq 0){throw 'Running project VM did not report a guest-reachable primary IPv4 address.'}
    return [string]$candidates[0]
}
function Wait-ProjectVmReady { param([Parameter(Mandatory)][string]$VmName)
    $deadline=(Get-Date).AddSeconds([int]$script:Config.BootTimeoutSeconds)
    $attempt=0
    while((Get-Date)-lt $deadline){
        $attempt++;$remaining=[math]::Max(0,($deadline-(Get-Date)).TotalSeconds);$info=$null
        try {
            $info=Invoke-Multipass @('info',$VmName,'--format','json') 30
            if($info.Text -match 'RUNNING'){
                try{$health=Invoke-Multipass @('exec',$VmName,'--','sudo','/usr/local/sbin/devfleet-project-health') 30;if($health.ExitCode -eq 0){return $true};Write-AgentLog 'readiness' '' $VmName 'waiting' "Project VM health probe returned exit $($health.ExitCode); $([math]::Round($remaining,1)) seconds remain."}catch{Write-AgentLog 'readiness' '' $VmName 'waiting' "Project VM health probe failed on attempt $attempt; $([math]::Round($remaining,1)) seconds remain."}
            } else {Write-AgentLog 'readiness' '' $VmName 'waiting' "Project VM is not RUNNING on attempt $attempt; $([math]::Round($remaining,1)) seconds remain."}
        } catch {Write-AgentLog 'readiness' '' $VmName 'waiting' "Project VM readiness inventory failed on attempt $attempt; $([math]::Round($remaining,1)) seconds remain."}
        $remaining=[math]::Max(0,($deadline-(Get-Date)).TotalSeconds);if($remaining -le 0){break};Start-Sleep -Seconds ([int][math]::Min(5,[math]::Max(1,$remaining)))
    }
    throw "Project VM did not become ready within $($script:Config.BootTimeoutSeconds) seconds."
}

function Import-ProjectWorkspace {
    param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)][string]$RuntimeId,[Parameter(Mandatory)][string]$SourceVm,[Parameter(Mandatory)][string]$ProjectId)
    $Slug=Assert-Slug $Slug;$ProjectId=Assert-ProjectId $ProjectId;$record=Assert-OwnedProjectVm $Slug $RuntimeId
    if([string]$record.project_id -ne $ProjectId){throw 'Project identifier does not match the target VM ownership registry.'}
    if($SourceVm -notmatch '^devfleet-[a-z0-9][a-z0-9._-]{1,62}$'){throw 'Workspace imports are limited to a DevFleet source VM.'}
    if($SourceVm -eq $record.vm_name){throw 'The source VM and target project VM must be different.'}
    $lock=New-ProvisioningLock
    $sourceArchive='';$localArchive='';$importRoot="/home/devrunner/workspaces/.devfleet-import-$([guid]::NewGuid().ToString('N'))"
    try {
        $sourceInventory=@(Get-MultipassVms|Where-Object{$_.name -eq $SourceVm});if($sourceInventory.Count -ne 1){throw 'The DevFleet source VM is missing or duplicated.'}
        if([string]$sourceInventory[0].state -ne 'RUNNING'){throw 'The DevFleet source VM must already be running; the import will not start or stop it.'}
        $targetInfo=Get-ProjectVmInfo $record.vm_name;if([string]$targetInfo.state -ne 'RUNNING'){throw 'The target project VM is not running.'}
        $sourcePath="/home/devrunner/workspaces/$Slug";$archiveName="devfleet-import-$Slug-$([guid]::NewGuid().ToString('N')).tar.gz";$sourceArchive="/tmp/$archiveName";$imports=Join-Path $script:Root 'imports';New-Item -ItemType Directory -Force -Path $imports|Out-Null;$localArchive=Join-Path $imports $archiveName
        Invoke-Multipass @('exec',$SourceVm,'--','sudo','test','-d',$sourcePath) 30|Out-Null
        Invoke-Multipass @('exec',$SourceVm,'--','sudo','tar','-czf',$sourceArchive,'-C','/home/devrunner/workspaces',$Slug) 600|Out-Null
        $archiveValidator=@'
import hashlib
import json
import sys
import tarfile
from pathlib import PurePosixPath

archive, slug = sys.argv[1:]
names = []
with tarfile.open(archive, "r:gz") as bundle:
    for member in bundle.getmembers():
        name = member.name.replace("\\", "/")
        pure = PurePosixPath(name)
        if pure.is_absolute() or ".." in pure.parts or "\x00" in name or not (name == slug or name.startswith(slug + "/")):
            raise SystemExit("unsafe archive path")
        if member.issym() or member.islnk() or member.isdev() or not (member.isdir() or member.isfile()):
            raise SystemExit("unsupported archive member type")
        if member.mode & 0o7000:
            raise SystemExit("unsafe archive mode")
        names.append(name)
    if slug not in names or slug + "/.devfleet/project.json" not in names:
        raise SystemExit("archive root or project metadata is missing")
digest = hashlib.sha256()
with open(archive, "rb") as stream:
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(block)
print(json.dumps({"archive_sha256": digest.hexdigest(), "member_count": len(names)}))
'@
        $sourceValidationText=(Invoke-Multipass @('exec',$SourceVm,'--','sudo','python3','-c',$archiveValidator,$sourceArchive,$Slug) 180).Text
        try{$sourceValidation=$sourceValidationText|ConvertFrom-Json -AsHashtable}catch{throw 'Source VM archive validator did not return structured JSON.'}
        if([string]$sourceValidation.archive_sha256 -notmatch '^[0-9a-f]{64}$' -or [int]$sourceValidation.member_count -lt 2){throw 'Source VM archive failed structured validation.'}
        Invoke-Multipass @('transfer',"${SourceVm}:$sourceArchive",$localArchive) 600|Out-Null
        if(-not(Test-Path -LiteralPath $localArchive)){throw 'The host did not receive the workspace archive.'}
        $digest=(Get-FileHash -LiteralPath $localArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        if($digest -ne [string]$sourceValidation.archive_sha256){throw 'Host archive hash does not match the immutable source validation hash.'}
        Invoke-Multipass @('transfer',$localArchive,"$($record.vm_name):$sourceArchive") 600|Out-Null
        $targetDigest=((Invoke-Multipass @('exec',$record.vm_name,'--','sha256sum',$sourceArchive) 60).Text -split '\s+')[0].ToLowerInvariant()
        if($targetDigest -ne $digest){throw 'Workspace archive integrity verification failed on the target VM.'}
        $targetValidationText=(Invoke-Multipass @('exec',$record.vm_name,'--','sudo','python3','-c',$archiveValidator,$sourceArchive,$Slug) 180).Text
        try{$targetValidation=$targetValidationText|ConvertFrom-Json -AsHashtable}catch{throw 'Target VM archive validator did not return structured JSON.'}
        if([string]$targetValidation.archive_sha256 -ne $digest){throw 'Target VM archive validation hash differs from the transferred archive.'}
        Invoke-Multipass @('exec',$record.vm_name,'--','sudo','mkdir','-p',$importRoot) 30|Out-Null
        Invoke-Multipass @('exec',$record.vm_name,'--','sudo','tar','-xzf',$sourceArchive,'-C',$importRoot,'--no-same-owner','--no-same-permissions') 600|Out-Null
        Invoke-Multipass @('exec',$record.vm_name,'--','sudo','test','-d',"$importRoot/$Slug") 30|Out-Null
        $targetPath="/home/devrunner/workspaces/$Slug";$existing=(Invoke-Multipass @('exec',$record.vm_name,'--','sudo','find',$targetPath,'-mindepth','1','-maxdepth','1','-print') 30).Text.Trim();if($existing){throw 'Target workspace is not empty; import refused to avoid overwriting data.'}
        Invoke-Multipass @('exec',$record.vm_name,'--','sudo','rmdir',$targetPath) 30|Out-Null
        Invoke-Multipass @('exec',$record.vm_name,'--','sudo','mv',"$importRoot/$Slug",$targetPath) 30|Out-Null
        Invoke-Multipass @('exec',$record.vm_name,'--','sudo','rmdir',$importRoot) 30|Out-Null
        Invoke-Multipass @('exec',$record.vm_name,'--','sudo','chown','-R','devrunner:devrunner',$targetPath) 120|Out-Null
        Invoke-Multipass @('exec',$record.vm_name,'--','sudo','test','-f',"$targetPath/.devfleet/project.json") 30|Out-Null
        $record.import_state='verified';$record.import_archive_sha256=$digest;$record.import_source_vm=$SourceVm;$record.imported_at=(Get-Date).ToUniversalTime().ToString('o');$record.updated_at=$record.imported_at;Update-ProjectRecord $Slug $record|Out-Null
        Write-AgentLog 'import' $record.project_id $record.runtime_id 'ready' "Existing workspace imported from $SourceVm with verified archive $digest."
        return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;vm_name=$record.vm_name;source_vm=$SourceVm;archive_sha256=$digest;target_archive_sha256=$targetDigest;workspace_preserved=$true;state='ready';message='Existing workspace imported into the dedicated VM.'}
    } finally {
        Remove-Item -LiteralPath $localArchive -Force -ErrorAction SilentlyContinue
        if($sourceArchive){try { Invoke-Multipass @('exec',$SourceVm,'--','sudo','rm','-f',$sourceArchive) 30|Out-Null } catch {}}
        if($sourceArchive){try { Invoke-Multipass @('exec',$record.vm_name,'--','sudo','rm','-f',$sourceArchive) 30|Out-Null } catch {}}
        try { Invoke-Multipass @('exec',$record.vm_name,'--','sudo','rm','-rf',$importRoot) 30|Out-Null } catch {}
        try {$lock.ReleaseMutex()}catch{};$lock.Dispose()
    }
}

function New-RegistryLock {
    $mutex=[Threading.Mutex]::new($false,'Global\DevFleetHostAgent-Registry')
    try { $acquired=$mutex.WaitOne(30000) }
    catch [Threading.AbandonedMutexException] { Write-AgentLog 'registry-lock' '' '' 'recovery-required' 'An abandoned registry mutex was recovered; exact live ownership reconciliation is required.'; $script:ReconciliationRequired=$true; $acquired=$true }
    if(-not $acquired){$mutex.Dispose();throw 'Host agent registry is busy; retry the operation.'}
    if($script:ReconciliationRequired){
        $registry=Read-Registry
        foreach($entry in $registry.projects.GetEnumerator()){
            if([string]$entry.Value.state -eq 'destroyed'){continue}
            $null=Assert-OwnedProjectVm ([string]$entry.Key) ([string]$entry.Value.runtime_id)
        }
        $script:ReconciliationRequired=$false
        Write-AgentLog 'registry-reconciliation' '' '' 'reconciled' 'Abandoned registry lock state was re-read and every active project VM passed exact live ownership verification.'
    }
    return $mutex
}
function Invoke-RegistryTransaction {
    param([Parameter(Mandatory)][scriptblock]$Mutation)
    $lock=New-RegistryLock
    try { $registry=Read-Registry; $result=& $Mutation $registry; Write-Registry $registry; return $result }
    finally { try{$lock.ReleaseMutex()}catch{};$lock.Dispose() }
}
function Update-ProjectRecord { param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)]$Record);$key=(Assert-Slug $Slug).ToLowerInvariant();Invoke-RegistryTransaction { param($registry);$registry.projects[$key]=$Record;return $Record } }
function Remove-ProvisionalProjectRecord {
    param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$ProvisioningAttemptId)
    $key=(Assert-Slug $Slug).ToLowerInvariant()
    Invoke-RegistryTransaction { param($registry);if($registry.projects.ContainsKey($key)){ $record=$registry.projects[$key]; if([string]$record.project_id -eq $ProjectId -and [string]$record.provisioning_attempt_id -eq $ProvisioningAttemptId){$registry.projects.Remove($key);return $true} };return $false }
}
function New-ProvisioningLock {
    $mutex=[Threading.Mutex]::new($false,'Global\DevFleetHostAgent-Provisioning')
    try { $acquired=$mutex.WaitOne(1000) }
    catch [Threading.AbandonedMutexException] {
        Write-AgentLog 'provisioning-lock' '' '' 'recovery-required' 'An abandoned provisioning mutex was recovered; state reconciliation is required before continuing.'
        $script:ReconciliationRequired=$true
        $acquired=$true
    }
    if(-not $acquired){ $mutex.Dispose();throw 'Another project VM provisioning operation is already active.' }
    if($script:ReconciliationRequired){
        $registry=Read-Registry
        foreach($entry in $registry.projects.GetEnumerator()){
            if([string]$entry.Value.state -eq 'destroyed'){continue}
            $null=Assert-OwnedProjectVm ([string]$entry.Key) ([string]$entry.Value.runtime_id)
        }
        $script:ReconciliationRequired=$false
        Write-AgentLog 'provisioning-reconciliation' '' '' 'reconciled' 'Abandoned provisioning lock state was re-read and every active project VM passed exact live ownership verification.'
    }
    return $mutex
}
function Remove-PartiallyCreatedProjectVm {
    param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$Attempt)
    try {
        if(-not [bool]$Attempt.launch_succeeded){Write-AgentLog 'create-cleanup' ([string]$Record.project_id) ([string]$Record.runtime_id) 'skipped' 'Provisioning launch did not succeed; cleanup is forbidden because a same-named runtime may be foreign.';return}
        $vmName=Get-ProjectVmName $Slug
        $inventory=@(Get-MultipassVms|Where-Object{$_.name -eq $vmName})
        if($inventory.Count -ne 1){return}
        $runtimeText=(Invoke-Multipass @('exec',$vmName,'--','sudo','cat','/etc/devfleet/project-runtime.json') 30).Text
        try{$runtimeMeta=$runtimeText|ConvertFrom-Json -AsHashtable}catch{Write-AgentLog 'create-cleanup' ([string]$Record.project_id) ([string]$Record.runtime_id) 'skipped' 'Runtime identity proof was unavailable; cleanup was forbidden.';return}
        if([string]$runtimeMeta.managed_by -ne 'devfleet' -or [string]$runtimeMeta.project_id -ne [string]$Record.project_id -or [string]$runtimeMeta.slug -ne $Slug -or [string]$runtimeMeta.runtime_id -ne [string]$Record.runtime_id -or [string]$runtimeMeta.host_id -ne [string]$script:Config.HostId -or [string]$runtimeMeta.provisioning_attempt_id -ne [string]$Attempt.provisioning_attempt_id){Write-AgentLog 'create-cleanup' ([string]$Record.project_id) ([string]$Record.runtime_id) 'skipped' 'Exact provisioning attempt/runtime ownership proof failed; cleanup was forbidden.';return}
        $info=Get-ProjectVmInfo $vmName
        if([string]$info.state -eq 'RUNNING'){Invoke-Multipass @('stop',$vmName) 120|Out-Null}
        Invoke-Multipass @('delete',$vmName,'--purge') 600|Out-Null
        if(@(Get-MultipassVms|Where-Object{$_.name -eq $vmName}).Count -ne 0){throw 'Multipass still reports the partially-created project VM after cleanup.'}
        Write-AgentLog 'create-cleanup' $Record.project_id $Record.runtime_id 'cleaned' 'Removed a project VM left behind by a failed first-time provisioning attempt.'
    } catch {
        Write-AgentLog 'create-cleanup' ([string]$Record.project_id) ([string]$Record.runtime_id) 'cleanup-failed' $_.Exception.Message
    }
}

function Ensure-ProjectVm {
    param([Parameter(Mand