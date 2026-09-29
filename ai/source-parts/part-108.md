# DevFleet source part 108

Full-source UTF-8 byte interval [4975500, 5022000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: a56c47514d59d1e4000dcf3f2f335e297c7d60fe0b8f669a8a4a9efa4386ccee

<!-- BEGIN SOURCE SLICE -->
ink or special file")
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
    param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][double]$Cpus,[Parameter(Mandatory)][double]$MemoryGb,[Parameter(Mandatory)][double]$DiskGb,[string]$GitUrl='')
    $Slug=Assert-Slug $Slug;$ProjectId=Assert-ProjectId $ProjectId;$vmName=Get-ProjectVmName $Slug;$registry=Read-Registry;$key=$Slug.ToLowerInvariant();$inventory=@(Get-MultipassVms|Where-Object{$_.name -eq $vmName});$existing=$null;if($registry.projects.ContainsKey($key)){$existing=$registry.projects[$key]}
    if($existing -and $existing.project_id -ne $ProjectId){throw 'Project identifier does not match the host ownership registry.'}
    if(-not $existing -and $inventory.Count -gt 0){throw 'A VM with the deterministic project name exists but is not DevFleet-owned.'}
    if($inventory.Count -gt 1){throw 'Duplicate deterministic project VMs detected.'}
    if($inventory.Count -eq 1){$record=Assert-OwnedProjectVm $Slug -AllowStoppedTransition;if($record.cpus -ne $Cpus -or $record.memory_gb -ne $MemoryGb -or $record.disk_gb -ne $DiskGb){throw 'Existing project VM resources do not match persisted allocation; resize is not automatic.'};$info=Get-ProjectVmInfo $vmName;if([string]$info.state -ne 'RUNNING'){Invoke-Multipass @('start',$vmName) 120|Out-Null;Wait-ProjectVmReady $vmName|Out-Null};return Refresh-ProjectVmConnectionState $Slug $record}
    $lock=New-ProvisioningLock
    try {
        # Discovery before the mutex is only advisory.  Re-read after locking
        # so a same-name runtime created by another process is never adopted.
        $registry=Read-Registry;$inventory=@(Get-MultipassVms|Where-Object{$_.name -eq $vmName});$existing=$null;if($registry.projects.ContainsKey($key)){$existing=$registry.projects[$key]}
        if($existing -and [string]$existing.project_id -ne $ProjectId){throw 'Project identifier does not match the host ownership registry.'}
        if(-not $existing -and $inventory.Count -gt 0){throw 'A VM with the deterministic project name exists but is not DevFleet-owned.'}
        if($inventory.Count -gt 1){throw 'Duplicate deterministic project VMs detected.'}
        Assert-ResourceRequest $Cpus $MemoryGb $DiskGb
        $runtimeId=$vmName;$attemptId=[guid]::NewGuid().ToString();$attempt=[ordered]@{provisioning_attempt_id=$attemptId;project_id=$ProjectId;runtime_id=$runtimeId;host_id=[string]$script:Config.HostId;launch_succeeded=$false};$launchSucceeded=$false;$record=[ordered]@{managed_by='devfleet';host_id=$script:Config.HostId;project_id=$ProjectId;slug=$Slug;runtime_id=$runtimeId;vm_name=$vmName;provisioning_attempt_id=$attemptId;cpus=$Cpus;memory_gb=$MemoryGb;disk_gb=$DiskGb;state='creating';address='';gpu_enabled=$false;gpu_passthrough=$false;created_at=(Get-Date).ToUniversalTime().ToString('o');updated_at=(Get-Date).ToUniversalTime().ToString('o');git_url=$GitUrl}
        Update-ProjectRecord $Slug $record|Out-Null;Write-AgentLog 'create' $ProjectId $runtimeId 'creating' 'Creating owned GPU-free project VM.';$cloudPath=Join-Path $script:Root "$vmName.cloud-init.yaml"
        try { New-CloudInit $Slug $ProjectId $GitUrl $attemptId | Set-Content -LiteralPath $cloudPath -Encoding UTF8;Invoke-Multipass @('launch',$script:Config.UbuntuImage,'--name',$vmName,'--cpus',[string]$Cpus,'--memory',"${MemoryGb}G",'--disk',"${DiskGb}G",'--cloud-init',$cloudPath) 1200|Out-Null;$launchSucceeded=$true;$attempt.launch_succeeded=$true;$record.state='booting';$record.updated_at=(Get-Date).ToUniversalTime().ToString('o');Update-ProjectRecord $Slug $record|Out-Null;Wait-ProjectVmReady $vmName|Out-Null;$refreshed=Refresh-ProjectVmConnectionState $Slug $record;Write-AgentLog 'create' $ProjectId $runtimeId 'ready' 'Project VM bootstrap health passed and connection state reconciled.';return $refreshed }
        catch { $errorMessage=$_.Exception.Message;Remove-PartiallyCreatedProjectVm $Slug $record $attempt;if(-not $launchSucceeded){Remove-ProvisionalProjectRecord $Slug $ProjectId $attemptId|Out-Null}else{$record.state='failed';$record.error=$errorMessage;$record.updated_at=(Get-Date).ToUniversalTime().ToString('o');Update-ProjectRecord $Slug $record|Out-Null};Write-AgentLog 'create' $ProjectId $runtimeId 'failed' $errorMessage;throw }
        finally { if(Test-Path -LiteralPath $cloudPath){Remove-Item -LiteralPath $cloudPath -Force -ErrorAction SilentlyContinue} }
    } finally { try{$lock.ReleaseMutex()}catch{};$lock.Dispose() }
}

function Backup-ProjectVm { param([Parameter(Mandatory)]$Record,[bool]$IncludeGenerated=$false)
    New-Item -ItemType Directory -Force -Path $script:BackupRoot | Out-Null
    $slug=Assert-Slug ([string]$Record.slug);$backupId="$slug-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))-$([guid]::NewGuid().ToString('N').Substring(0,8))";$archivePath=Join-Path $script:BackupRoot "$backupId.tar.gz";$manifestPath=Join-Path $script:BackupRoot "$backupId.json";$remoteArchive="/tmp/devfleet-backup-$([guid]::NewGuid().ToString('N')).tar.gz";$workspace="/home/devrunner/workspaces/$slug"
    try {
        $archiveInspection=New-VerifiedRemoteWorkspaceArchive $Record.vm_name $remoteArchive $slug $IncludeGenerated
        $sourceArchiveHash=[string]$archiveInspection.archive_sha256
        Invoke-Multipass @('transfer',"$($Record.vm_name):$remoteArchive",$archivePath) 1200|Out-Null
        if(-not(Test-Path -LiteralPath $archivePath)){throw 'Host did not receive the workspace backup archive.'}
        $archiveHash=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if($archiveHash -ne $sourceArchiveHash){throw 'Workspace backup archive SHA-256 differs between the project VM and host.'}
        $manifest=[ordered]@{schema_version=1;backup_id=$backupId;created_at=(Get-Date).ToUniversalTime().ToString('o');host_id=$script:Config.HostId;provider='multipass';project_id=$Record.project_id;slug=$slug;runtime_id=$Record.runtime_id;vm_name=$Record.vm_name;archive_path=$archivePath;archive_sha256=$archiveHash;source_archive_sha256=$sourceArchiveHash;host_archive_sha256=$archiveHash;archive_bytes=(Get-Item -LiteralPath $archivePath).Length;verification='verified';consistency_level=if($IncludeGenerated){'quiesced'}else{'live-best-effort'};gpu_enabled=$false};$json=$manifest|ConvertTo-Json -Depth 20;[IO.File]::WriteAllText($manifestPath,$json,(New-Object Text.UTF8Encoding($false)));$manifestHash=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant();$reference=[ordered]@{provider='multipass-host-agent';backup_id=$backupId;project_id=$Record.project_id;slug=$slug;runtime_id=$Record.runtime_id;host_id=$script:Config.HostId;archive_sha256=$archiveHash;archive_bytes=$manifest.archive_bytes;manifest_sha256=$manifestHash;created_at=$manifest.created_at;consistency_level=$manifest.consistency_level};Write-AgentLog 'backup' $Record.project_id $Record.runtime_id 'verified' "Workspace archive $backupId verified with equal source and host SHA-256.";return [ordered]@{ok=$true;backup_status='verified';backup_id=$backupId;backup_sha256=$archiveHash;manifest_sha256=$manifestHash;archive_bytes=$manifest.archive_bytes;backup_reference=$reference;runtime_id=$Record.runtime_id;host_name=$script:Config.HostName;host_id=$script:Config.HostId;project_id=$Record.project_id}
    } finally {if($remoteArchive){try{Invoke-Multipass @('exec',$Record.vm_name,'--','sudo','rm','-f',$remoteArchive) 30|Out-Null}catch{}}}
}

function Get-VerifiedProjectBackup {
    param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$BackupId)
    $BackupId=Assert-BackupId $BackupId
    $manifestPath=Join-Path $script:BackupRoot "$BackupId.json"
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'The requested backup manifest is not present on the host.'}
    try{$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -AsHashtable}catch{throw 'The requested backup manifest is not valid JSON.'}
    if([string]$manifest.backup_id -ne $BackupId -or [string]$manifest.project_id -ne [string]$Record.project_id -or [string]$manifest.slug -ne [string]$Record.slug -or [string]$manifest.runtime_id -ne [string]$Record.runtime_id){throw 'Backup manifest identity does not match this project VM.'}
    $backupRootFull=[IO.Path]::GetFullPath($script:BackupRoot).TrimEnd('\')+'\'
    $archivePath=[IO.Path]::GetFullPath([string]$manifest.archive_path)
    if(-not $archivePath.StartsWith($backupRootFull,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $archivePath -PathType Leaf)){throw 'Backup archive is missing or outside the host backup root.'}
    $expected=[string]$manifest.archive_sha256
    if($expected -notmatch '^[0-9a-f]{64}$' -or [string]$manifest.source_archive_sha256 -ne $expected -or [string]$manifest.host_archive_sha256 -ne $expected){throw 'Backup manifest does not prove equal source and host SHA-256 values.'}
    $actual=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $expected){throw 'Workspace backup archive hash no longer matches its verified manifest.'}
    $manifestHash=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant();return [ordered]@{backup_id=$BackupId;backup_sha256=$actual;archive_bytes=(Get-Item -LiteralPath $archivePath).Length;backup_reference=[ordered]@{provider='multipass-host-agent';backup_id=$BackupId;project_id=$Record.project_id;slug=$Record.slug;runtime_id=$Record.runtime_id;host_id=$script:Config.HostId;archive_sha256=$actual;archive_bytes=(Get-Item -LiteralPath $archivePath).Length;manifest_sha256=$manifestHash;created_at=[string]$manifest.created_at;consistency_level=[string]$manifest.consistency_level};manifest=$manifest}
}

function Get-ProjectVmBackups {
    param([Parameter(Mandatory)]$Record)
    New-Item -ItemType Directory -Force -Path $script:BackupRoot|Out-Null
    $items=@()
    foreach($manifestPath in @(Get-ChildItem -LiteralPath $script:BackupRoot -Filter '*.json' -File|Sort-Object LastWriteTimeUtc -Descending)){
        try{$raw=Get-Content -LiteralPath $manifestPath.FullName -Raw|ConvertFrom-Json -AsHashtable}catch{continue}
        if([string]$raw.project_id -ne [string]$Record.project_id -or [string]$raw.slug -ne [string]$Record.slug -or [string]$raw.runtime_id -ne [string]$Record.runtime_id){continue}
        $backupId=[string]$raw.backup_id
        try{
            $archivePath=[string]$raw.archive_path;$archiveInfo=Get-Item -LiteralPath $archivePath -Force;$manifestHash=(Get-FileHash -LiteralPath $manifestPath.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$cacheKey="$backupId|$manifestHash|$($archiveInfo.Length)|$($archiveInfo.LastWriteTimeUtc.Ticks)|$([string]$raw.archive_sha256)"
            if($script:BackupVerificationCache.ContainsKey($cacheKey)){$verified=$script:BackupVerificationCache[$cacheKey]}else{$verified=Get-VerifiedProjectBackup $Record $backupId;$script:BackupVerificationCache[$cacheKey]=$verified}
            $items += [ordered]@{backup_id=$backupId;created_at=[string]$raw.created_at;provider='multipass-host-agent';runtime_id=[string]$Record.runtime_id;archive_bytes=$verified.archive_bytes;archive_sha256=$verified.backup_sha256;sha_verified=$true;restore_eligible=$true;reason='';status='eligible';backup_reference=$verified.backup_reference}
        }catch{$items += [ordered]@{backup_id=$backupId;created_at=[string]$raw.created_at;provider='multipass-host-agent';runtime_id=[string]$Record.runtime_id;archive_bytes=[int64]($raw.archive_bytes -as [int64]);archive_sha256=[string]$raw.archive_sha256;sha_verified=$false;restore_eligible=$false;reason=$_.Exception.Message;status='invalid'}}
    }
    return @($items)
}

function Restore-ProjectVmBackup {
    param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$BackupId,[Parameter(Mandatory)][bool]$ConfirmRestore)
    if(-not $ConfirmRestore){throw 'Backup restore requires explicit confirmation.'}
    $verified=Get-VerifiedProjectBackup $Record $BackupId
    $vmName=[string]$Record.vm_name;$slug=Assert-Slug ([string]$Record.slug);$workspace="/home/devrunner/workspaces/$slug"
    $info=Get-ProjectVmInfo $vmName
    if([string]$info.state -ne 'RUNNING'){Invoke-Multipass @('start',$vmName) 120|Out-Null;Wait-ProjectVmReady $vmName|Out-Null}
    $safety=Backup-ProjectVm $Record
    $nonce=[guid]::NewGuid().ToString('N');$remoteArchive="/tmp/devfleet-restore-$nonce.tar.gz";$stage="/home/devrunner/workspaces/.devfleet-restore-$slug-$nonce";$oldPath="${workspace}-before-restore-$nonce";$promoted=$false
    try{
        Invoke-Multipass @('transfer',[string]$verified.archive_path,"${vmName}:$remoteArchive") 1200|Out-Null
        $remoteHash=((Invoke-Multipass @('exec',$vmName,'--','sha256sum',$remoteArchive) 60).Text -split '\s+')[0].ToLowerInvariant()
        if($remoteHash -ne [string]$verified.backup_sha256){throw 'Restore archive SHA-256 differs between the host and project VM.'}
        Invoke-Multipass @('exec',$vmName,'--','sudo','mkdir','-p',$stage) 30|Out-Null
        Invoke-Multipass @('exec',$vmName,'--','sudo','tar','-xzf',$remoteArchive,'-C',$stage,'--no-same-owner','--no-same-permissions') 600|Out-Null
        $restoredMetadata="$stage/$slug/.devfleet/project.json"
        Invoke-Multipass @('exec',$vmName,'--','sudo','test','-f',$restoredMetadata) 30|Out-Null
        $restoredProjectId=(Invoke-Multipass @('exec',$vmName,'--','sudo','python3','-c','import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("project_id",""))',$restoredMetadata) 30).Text.Trim()
        if($restoredProjectId -ne [string]$Record.project_id){throw 'Restored workspace project identity does not match the owned project VM.'}
        Invoke-Multipass @('exec',$vmName,'--','sudo','mv',$workspace,$oldPath) 60|Out-Null
        Invoke-Multipass @('exec',$vmName,'--','sudo','mv',"$stage/$slug",$workspace) 60|Out-Null;$promoted=$true
        Invoke-Multipass @('exec',$vmName,'--','sudo','chown','-R','devrunner:devrunner',$workspace) 120|Out-Null
        $finalProjectId=(Invoke-Multipass @('exec',$vmName,'--','sudo','python3','-c','import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("project_id",""))',"$workspace/.devfleet/project.json") 30).Text.Trim()
        if($finalProjectId -ne [string]$Record.project_id){throw 'Promoted restore failed final project identity verification.'}
        Invoke-Multipass @('exec',$vmName,'--','sudo','rm','-rf',$oldPath) 120|Out-Null
        Write-AgentLog 'restore-backup' $Record.project_id $Record.runtime_id 'verified' "Restored $BackupId after verified safety backup $($safety.backup_id)."
        return [ordered]@{ok=$true;host_name=$script:Config.HostName;provider='multipass-host-agent';runtime_id=$Record.runtime_id;project_id=$Record.project_id;backup_id=$BackupId;backup_sha256=$verified.backup_sha256;safety_backup_id=$safety.backup_id;safety_backup_sha256=$safety.backup_sha256;state='restored';message='Project VM workspace restored after staging, identity verification, and safety backup.'}
    }catch{
        if($promoted){try{Invoke-Multipass @('exec',$vmName,'--','sudo','rm','-rf',$workspace) 120|Out-Null;Invoke-Multipass @('exec',$vmName,'--','sudo','mv',$oldPath,$workspace) 120|Out-Null}catch{Write-AgentLog 'restore-backup' $Record.project_id $Record.runtime_id 'rollback-incomplete' $_.Exception.Message}}
        throw
    }finally{
        try{Invoke-Multipass @('exec',$vmName,'--','rm','-f',$remoteArchive) 30|Out-Null}catch{}
        try{Invoke-Multipass @('exec',$vmName,'--','sudo','rm','-rf',$stage) 60|Out-Null}catch{}
    }
}

function Get-ProjectCommandManifest { param([Parameter(Mandatory)]$Record)
    $slug=Assert-Slug ([string]$Record.slug);$workspace="/home/devrunner/workspaces/$slug";$metadataPath="$workspace/.devfleet/project.json"
    $text=(Invoke-Multipass @('exec',$Record.vm_name,'--','sudo','cat',$metadataPath) 30).Text
    try {$metadata=$text|ConvertFrom-Json -AsHashtable} catch {throw 'Project command manifest is not valid JSON.'}
    if(-not $metadata -or ($metadata.runtime_type -and [string]$metadata.runtime_type -notin @('vm','container'))){throw 'Project command manifest declares an unsupported runtime type.'}
    return $metadata
}

function Get-TrustedProjectCommand { param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$CommandKey,[int]$Tail=150)
    $key=$CommandKey.ToLowerInvariant();$allowed=@('bootstrap_command','health_command','test_command','format_command','lint_command','start_command','stop_command','restart_command','rebuild_command','logs_command','codexpro_command')
    if($key -notin $allowed){throw 'Unsupported project command key.'}
    $metadata=Get-ProjectCommandManifest $Record;$value=$metadata[$key];if($null -eq $value -and $metadata.commands){$value=$metadata.commands[$key]}
    if($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)){throw "Project command '$key' is not configured in .devfleet/project.json."}
    $cmd=[string]$value
    $hookAllowed=$cmd -match '^\./\.devfleet/(bootstrap|health-check|smoke-test|codexpro-bootstrap)\.sh$'
    $composeAllowed=@('docker compose up -d --build','docker compose down --remove-orphans','docker compose restart','docker compose build && docker compose up -d','docker compose logs') -contains $cmd
    if($cmd.Length -gt 512 -or -not ($hookAllowed -or $composeAllowed) -or $cmd -match '[\r\n`$<>]' -or $cmd -match '(?i)(^|\s)(sudo|su|shutdown|reboot|poweroff|systemctl|service|multipass)(\s|$)' -or $cmd -match '(?i)(rm\s+-rf|docker\s+(run|exec)|curl\s+|wget\s+)'){throw "Project command '$key' is unsafe or unsupported."}
    if($key -eq 'logs_command'){$cmd="$cmd --tail $([math]::Max(1,[math]::Min($Tail,500)))"}
    return $cmd
}

function Invoke-ProjectCommand { param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$CommandKey,[int]$Tail=150)
    $slug=Assert-Slug ([string]$Record.slug);$slug=Assert-Slug $slug;$workspace="/home/devrunner/workspaces/$slug";$cmd=Get-TrustedProjectCommand $Record $CommandKey $Tail
    if($workspace -notmatch '^/home/devrunner/workspaces/[a-z0-9][a-z0-9._-]{1,62}$'){throw 'Project workspace boundary validation failed.'}
    # The command is selected only from the fixed allowlist above. Keep the
    # workspace separately validated immediately before the unavoidable shell
    # boundary and use exec so no extra shell remains after the trusted command.
    $result=Invoke-Multipass @('exec',$Record.vm_name,'--','sudo','-u','devrunner','bash','--noprofile','--norc','-lc',"cd -- '$workspace' && exec $cmd") 3600
    return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$Record.runtime_id;project_id=$Record.project_id;command_key=$CommandKey.ToLowerInvariant();output=$result.Text;state='completed'}
}

# Treat remote existence checks as data. Invoke-Multipass throws on a negative
# test, so relying on $LASTEXITCODE would make a valid first import fail.
function Export-ProjectWorkspaceToSource { param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$SourceVm,[Parameter(Mandatory)][string]$ProjectId,[bool]$ReplaceSource=$false)
    $Slug=Assert-Slug $Slug
    $ProjectId=Assert-ProjectId $ProjectId
    if([string]$Record.project_id -ne $ProjectId){throw 'Project identifier does not match the target VM ownership registry.'}
    if($SourceVm -notmatch '^devfleet-[a-z0-9][a-z0-9._-]{1,62}$' -or $SourceVm -eq $Record.vm_name){throw 'The export source VM is invalid.'}
    $sourceInventory=@(Get-MultipassVms|Where-Object{$_.name -eq $SourceVm})
    if($sourceInventory.Count -ne 1 -or [string]$sourceInventory[0].state -ne 'RUNNING'){throw 'The DevFleet source VM must be running for a VM workspace export.'}
    $remoteArchive="/tmp/devfleet-export-$([guid]::NewGuid().ToString('N')).tar.gz"
    $localArchive=Join-Path $