# DevFleet source part 107

Full-source UTF-8 byte interval [4929000, 4975500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 7a4e2e6e1b41d256171136bfb99f56cc6f92494cee56bdf35d7d31b7acac1e85

<!-- BEGIN SOURCE SLICE -->
atory)][string]$Slug,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][double]$Cpus,[Parameter(Mandatory)][double]$MemoryGb,[Parameter(Mandatory)][double]$DiskGb,[string]$GitUrl='')
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
    $localArchive=Join-Path $script:Root "imports\$([guid]::NewGuid().ToString('N')).tar.gz"
    $sourceArchive="/tmp/devfleet-export-source-$([guid]::NewGuid().ToString('N')).tar.gz"
    $stage="/home/devrunner/workspaces/.devfleet-export-$Slug-$([guid]::NewGuid().ToString('N'))"
    $workspace="/home/devrunner/workspaces/$Slug"
    $oldPath="/home/devrunner/workspaces/$Slug-before-vm-export-$([guid]::NewGuid().ToString('N'))"
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $localArchive)|Out-Null
        $archiveInspection=New-VerifiedRemoteWorkspaceArchive $Record.vm_name $remoteArchive $Slug
        $sourceArchiveHash=[string]$archiveInspection.archive_sha256
        Invoke-Multipass @('transfer',"$($Record.vm_name):$remoteArchive",$localArchive) 1200|Out-Null
        $hash=(Get-FileHash -LiteralPath $localArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        if($hash -ne $sourceArchiveHash){throw 'Workspace export archive SHA-256 differs between the project VM and host.'}
        Invoke-Multipass @('transfer',$localArchive,"${SourceVm}:$sourceArchive") 1200|Out-Null
        Invoke-Multipass @('exec',$SourceVm,'--','sudo','mkdir','-p',$stage) 30|Out-Null
        Invoke-Multipass @('exec',$SourceVm,'--','sudo','tar','-xzf',$sourceArchive,'-C',$stage,'--no-same-owner','--no-same-permissions') 600|Out-Null
        $sourceVmArchiveHash=((Invoke-Multipass @('exec',$SourceVm,'--','sha256sum',$sourceArchive) 60).Text -split '\s+')[0].ToLowerInvariant()
        if($sourceVmArchiveHash -ne $hash){throw 'Workspace export archive SHA-256 differs between the host and source VM.'}
        Invoke-Multipass @('exec',$SourceVm,'--','sudo','test','-f',"$stage/$Slug/.devfleet/project.json") 30|Out-Null
        if($ReplaceSource){
            $sourceState=(Invoke-Multipass @('exec',$SourceVm,'--','sudo','bash','-lc',"if [ -d '$workspace' ]; then printf exists; else printf absent; fi") 30).Text.Trim()
            $hasExisting=$sourceState -eq 'exists'
            if($hasExisting){Invoke-Multipass @('exec',$SourceVm,'--','sudo','mv',$workspace,$oldPath) 60|Out-Null}
            Invoke-Multipass @('exec',$SourceVm,'--','sudo','mv',"$stage/$Slug",$workspace) 60|Out-Null
            Invoke-Multipass @('exec',$SourceVm,'--','sudo','chown','-R','devrunner:devrunner',$workspace) 120|Out-Null
            Write-AgentLog 'export-to-source' $Record.project_id $Record.runtime_id 'verified' "VM workspace exported to $SourceVm with equal source, host, and source-VM SHA-256."
            return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$Record.runtime_id;project_id=$Record.project_id;source_vm=$SourceVm;archive_sha256=$hash;source_archive_sha256=$sourceArchiveHash;host_archive_sha256=$hash;source_vm_archive_sha256=$sourceVmArchiveHash;workspace_path=$workspace;previous_workspace_path=if($hasExisting){$oldPath}else{''};state='verified';message='Dedicated VM workspace exported and promoted to the source VM after archive equality verification.'}
        }
        return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$Record.runtime_id;project_id=$Record.project_id;source_vm=$SourceVm;archive_sha256=$hash;source_archive_sha256=$sourceArchiveHash;host_archive_sha256=$hash;source_vm_archive_sha256=$sourceVmArchiveHash;staging_path="$stage/$Slug";state='staged';message='Dedicated VM workspace exported to a verified staging directory after archive equality verification.'}
    } finally {
        Remove-Item -LiteralPath $localArchive -Force -ErrorAction SilentlyContinue
        try{Invoke-Multipass @('exec',$Record.vm_name,'--','sudo','rm','-f',$remoteArchive) 30|Out-Null}catch{}
        try{Invoke-Multipass @('exec',$SourceVm,'--','sudo','rm','-f',$sourceArchive) 30|Out-Null}catch{}
        if(-not $ReplaceSource){try{Invoke-Multipass @('exec',$SourceVm,'--','sudo','rm','-rf',$stage) 30|Out-Null}catch{}}
    }
}

function Remove-ImportFailedProjectVm {
    param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$Payload)
    $Slug=Assert-Slug $Slug
    if([string]$Record.state -notin @('creating','booting','ready','stopped')){throw 'Cleanup-only VM removal is limited to a newly provisioned project VM.'}
    if(-not [bool]$Payload.backup_verified -or [string]::IsNullOrWhiteSpace([string]$Payload.backup_id)){throw 'Cleanup-only removal requires a verified provider-aware recovery backup.'}
    foreach($name in 'backup_sha256','local_archive_sha256'){if([string]$Payload.$name -notmatch '^[0-9a-fA-F]{64}$'){throw "Cleanup-only removal requires a valid $name value."}}
    $stage=[string]$Payload.cleanup_stage;if($stage -notin @('pre-import','post-import')){throw 'Cleanup-only removal requires an explicit pre-import or post-import stage.'}
    $vmName=[string]$Record.vm_name
    if($vmName -ne (Get-ProjectVmName $Slug) -or [string]$Record.runtime_id -ne $vmName -or [string]$Record.managed_by -ne 'devfleet' -or [string]$Record.host_id -ne [string]$script:Config.HostId){throw 'Cleanup-only removal failed the ownership registry identity check.'}
    $inventory=@(Get-MultipassVms|Where-Object{$_.name -eq $vmName});if($inventory.Count -ne 1){throw 'Cleanup-only removal requires exactly one deterministic project VM.'}
    $runtimeText=(Invoke-Multipass @('exec',$vmName,'--','sudo','cat','/etc/devfleet/project-runtime.json') 30).Text
    try{$runtimeMeta=$runtimeText|ConvertFrom-Json -AsHashtable}catch{throw 'The project VM runtime identity document is invalid.'}
    if([string]$runtimeMeta.managed_by -ne 'devfleet' -or [string]$runtimeMeta.slug -ne $Slug -or [string]$runtimeMeta.project_id -ne [string]$Record.project_id){throw 'The project VM runtime identity does not match the ownership registry.'}
    $workspace="/home/devrunner/workspaces/$Slug";$projectMetaPath="$workspace/.devfleet/project.json"
    if($stage -eq 'pre-import'){
        Invoke-Multipass @('exec',$vmName,'--','sudo','bash','-lc',"test ! -e '$projectMetaPath'") 30|Out-Null
    } else {
        $projectText=(Invoke-Multipass @('exec',$vmName,'--','sudo','cat',$projectMetaPath) 30).Text
        try{$projectMeta=$projectText|ConvertFrom-Json -AsHashtable}catch{throw 'The imported project metadata is invalid.'}
        if([string]$projectMeta.slug -ne $Slug -or ([string]$projectMeta.identity -and [string]$projectMeta.identity -ne $Slug)){throw 'The imported workspace identity does not match the cleanup request.'}
        if([string]$projectMeta.project_id -and [string]$projectMeta.project_id -ne [string]$Record.project_id){throw 'The imported workspace project identifier does not match the ownership registry.'}
        $payloadImport=[string]$Payload.import_archive_sha256;$recordImport=[string]$Record.import_archive_sha256
        if($payloadImport -and $payloadImport -notmatch '^[0-9a-fA-F]{64}$'){throw 'Cleanup-only removal received an invalid import archive SHA-256.'}
        if($recordImport -and (!$payloadImport -or $recordImport -ne $payloadImport)){throw 'The cleanup import archive does not match the persisted import evidence.'}
    }
    $lock=New-ProvisioningLock
    try {
        $info=Get-ProjectVmInfo $vmName;if([string]$info.state -eq 'RUNNING'){Invoke-Multipass @('stop',$vmName) 120|Out-Null}
        Invoke-Multipass @('delete',$vmName,'--purge') 600|Out-Null
        if(@(Get-MultipassVms|Where-Object{$_.name -eq $vmName}).Count -ne 0){throw 'Multipass still reports the cleanup VM after deletion.'}
        Remove-ProjectVmSshAlias $Record.runtime_id $Record.project_id
        $Record.state='destroyed';$Record.cleanup_stage=$stage;$Record.destroyed_at=(Get-Date).ToUniversalTime().ToString('o');$Record.updated_at=$Record.destroyed_at;Update-ProjectRecord $Slug $Record|Out-Null
        Write-AgentLog 'import-cleanup' $Record.project_id $Record.runtime_id 'destroyed' "Removed the verified $stage failed-migration VM and released its allocation."
        return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$Record.runtime_id;vm_name=$vmName;project_id=$Record.project_id;state='destroyed';cleanup_only=$true;cleanup_stage=$stage;allocation_released=$true;runtime_identity_verified=$true;workspace_identity_verified=($stage -eq 'post-import');message='Failed-migration project VM reconciled after deterministic identity and recovery-evidence checks.'}
    } finally {try{$lock.ReleaseMutex()}catch{};$lock.Dispose()}
}

# The project-VM section is intentionally independent from the ordinary
# DevFleet aliases created by Configure-SSH.ps1.  It is the only section this
# service changes, preserving all user configuration and the primary aliases.
function Get-ProjectVmSshMarkers { param([Parameter(Mandatory)][string]$RuntimeId)
    $safe=[regex]::Escape($RuntimeId)
    return @{Begin="# BEGIN DEVFLEET PROJECT VM $RuntimeId";End="# END DEVFLEET PROJECT VM $RuntimeId";Pattern="(?ms)^# BEGIN DEVFLEET PROJECT VM $safe\r?\n.*?^# END DEVFLEET PROJECT VM $safe\r?\n?"}
}

function Get-ProjectVmKnownHostMarkers { param([Parameter(Mandatory)][string]$RuntimeId)
    $safe=[regex]::Escape($RuntimeId)
    return @{Begin="# BEGIN DEVFLEET PROJECT VM HOST KEY $RuntimeId";End="# END DEVFLEET PROJECT VM HOST KEY $RuntimeId";Pattern="(?ms)^# BEGIN DEVFLEET PROJECT VM HOST KEY $safe\r?\n.*?^# END DEVFLEET PROJECT VM HOST KEY $safe\r?\n?"}
}

function Set-DevFleetManagedTextBlock {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Pattern,[string]$Block='')
    $directory=Split-Path -Parent $Path;if($directory){New-Item -ItemType Directory -Force -Path $directory|Out-Null}
    $existing=if(Test-Path -LiteralPath $Path){[IO.File]::ReadAllText($Path)}else{''}
    $updated=[regex]::Replace($existing,$Pattern,'').TrimEnd()
    if($Block){if($updated){$updated+="`r`n`r`n"};$updated+=$Block.Trim()+"`r`n"}elseif($updated){$updated+="`r`n"}
    if($updated -ne $existing){$temp="$Path.$([guid]::NewGuid().ToString('N')).tmp";[IO.File]::WriteAllText($temp,$updated,(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath $temp -Destination $Path -Force}
    return $updated
}

function Sync-ProjectVmSshAlias {
    param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)]$Record,[object]$VmInfo=$null,[string]$Address='')
    $slug=Assert-Slug $Slug;$runtimeId=[string]$Record.runtime_id
    if($runtimeId -ne (Get-ProjectVmName $slug)){throw 'Project VM SSH alias does not match the deterministic owned runtime identity.'}
    $configPath=[string]$script:Config.SshConfigPath;$keyPath=[string]$script:Config.SshPrivateKeyPath;$knownHostsPath=[string]$script:Config.SshKnownHostsPath
    if([string]::IsNullOrWhiteSpace($configPath) -or [string]::IsNullOrWhiteSpace($keyPath) -or [string]::IsNullOrWhiteSpace($knownHostsPath)){throw 'Host-agent SSH alias and known-host paths are not configured.'}
    if(-not(Test-Path -LiteralPath $keyPath)){throw 'Configured DevFleet SSH private key is not available for project aliases.'}
    $info=if($VmInfo){$VmInfo}else{Get-ProjectVmInfo ([string]$Record.vm_name)}
    $address=if($Address){$Address}else{Get-PrimaryProjectVmIpv4 $info}
    if([string]::IsNullOrWhiteSpace($address)){throw 'Project VM has no address available for its SSH alias.'}
    $hostKey=(Invoke-Multipass @('exec',$record.vm_name,'--','sudo','cat','/etc/ssh/ssh_host_ed25519_key.pub') 30).Text.Trim();$hostKeyParts=$hostKey -split '\s+'
    if($hostKeyParts.Count -lt 2 -or $hostKeyParts[0] -ne 'ssh-ed25519' -or $hostKeyParts[1] -notmatch '^[A-Za-z0-9+/]+={0,3}$'){throw 'Project VM did not provide a valid Ed25519 SSH host key.'}
    $knownMarkers=Get-ProjectVmKnownHostMarkers $runtimeId;$knownBlock="$($knownMarkers.Begin)`r`n$runtimeId ssh-ed25519 $($hostKeyParts[1])`r`n$($knownMarkers.End)"
    Set-DevFleetManagedTextBlock $knownHostsPath $knownMarkers.Pattern $knownBlock|Out-Null
    $markers=Get-ProjectVmSshMarkers $runtimeId
    $identity=$keyPath.Replace('\','/');$knownHosts=$knownHostsPath.Replace('\','/')
    $block=@"
$($markers.Begin)
Host $runtimeId
    HostName $address
    User devrunner
    IdentityFile $identity
    IdentitiesOnly yes
    ForwardAgent no
    HostKeyAlias $runtimeId
    UserKnownHostsFile $knownHosts
    StrictHostKeyChecking yes
$($markers.End)
"@
    Set-DevFleetManagedTextBlock $configPath $markers.Pattern $block|Out-Null
    $ssh=Resolve-TrustedHostExecutable @((Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'),(Join-Path $env:ProgramFiles 'OpenSSH\ssh.exe'))
    $resolved=& $ssh -F $configPath -G $runtimeId 2>$null
    if($LASTEXITCODE -ne 0){throw 'OpenSSH could not resolve the managed project VM alias.'}
    $text=$resolved -join "`n"
    if($text -notmatch "(?m)^hostname\s+$([regex]::Escape($address))$" -or $text -notmatch '(?m)^user\s+devrunner$' -or $text -notmatch '(?m)^identitiesonly\s+yes$' -or $text -notmatch '(?m)^forwardagent\s+no$' -or $text -notmatch '(?m)^stricthostkeychecking\s+(yes|true)$' -or $text -notmatch "(?m)^hostkeyalias\s+$([regex]::Escape($runtimeId))$"){throw 'Managed project VM SSH alias did not pass pinned configuration validation.'}
    # The service runs as SYSTEM while the managed alias must remain usable by
    # the installing developer. OpenSSH correctly rejects that developer-owned
    # private key when SYSTEM evaluates its ACL, so validate with a short-lived
    # SYSTEM-only copy of the same key and never expose its contents.
    $validationKey=Join-Path $script:Root "ssh-validation-$([guid]::NewGuid().ToString('N'))"
    try {
        Copy-Item -LiteralPath $keyPath -Destination $validationKey -Force
        $keyAcl=New-Object System.Security.AccessControl.FileSecurity;$keyAcl.SetAccessRuleProtection($true,$false)
        $keyAcl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','Allow')))
        $keyAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','Allow')))
        Set-Acl -LiteralPath $validationKey -AclObject $keyAcl
        $sshOutput=& $ssh -F $configPath -i $validationKey -o BatchMode=yes -o ConnectTimeout=15 $runtimeId 'id -un' 2>&1
        if($LASTEXITCODE -ne 0 -or (($sshOutput -join "`n").Trim() -ne 'devrunner')){throw 'Managed project VM SSH alias did not pass an authenticated pinned host-key connection test.'}
    } finally {Remove-Item -LiteralPath $validationKey -Force -ErrorAction SilentlyContinue}
    $vsCode=if(Get-Command Sync-DevFleetVsCodeRemotePlatform -ErrorAction SilentlyContinue){Sync-DevFleetVsCodeRemotePlatform $runtimeId}else{[ordered]@{ok=$true;status='skipped';reason='VS Code helper is not installed.';alias=$runtimeId;platform='linux'}}
    $Record.address=$address;$Record.ssh_alias=$runtimeId;$Record.updated_at=(Get-Date).ToUniversalTime().ToString('o');Update-ProjectRecord $slug $Record|Out-Null
    Write-AgentLog 'sync-ssh-alias' $Record.project_id $runtimeId 'ready' 'Dedicated project VM SSH alias and managed Ed25519 host key passed configuration and authenticated connection checks.'
    return [ordered]@{ok=$true;host_name=$script:Config.HostName;project_id=$Record.project_id;runtime_id=$runtimeId;ssh_alias=$runtimeId;address=$address;host_key_algorithm='ssh-ed25519';host_key_pinned=$true;authenticated_connection=$true;validated=$true;vscode_remote_platform=$vsCode}
}

function Refresh-ProjectVmConnectionState {
    param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)]$Record)
    $slug=Assert-Slug $Slug
    $owned=Assert-OwnedProjectVm $slug ([string]$Record.runtime_id)
    if([string]$owned.project_id -ne [string]$Record.project_id){throw 'Project identifier does not match the ownership registry.'}
    $info=Get-ProjectVmInfo ([string]$owned.vm_name)
    $address=Get-PrimaryProjectVmIpv4 $info
    $sync=Sync-ProjectVmSshAlias $slug $owned -VmInfo $info -Address $address
    $latest=Get-ProjectRecord $slug
    $latest.state='ready';$latest.address=$address;$latest.updated_at=(Get-Date).ToUniversalTime().ToString('o');Update-ProjectRecord $slug $latest|Out-Null
    Write-AgentLog 'refresh-connection-state' $latest.project_id $latest.runtime_id 'ready' "Reconciled owned project VM address $address and managed SSH alias."
    return [ordered]@{ok=$true;host_name=$script:Config.HostName;project_id=$latest.project_id;runtime_id=$latest.runtime_id;vm_name=$latest.vm_name;address=$address;state='ready';registry_address=$address;ssh_alias=$sync.ssh_alias;host_key_pinned=[bool]$sync.host_key_pinned;authenticated_connection=[bool]$sync.authenticated_connection;validated=[bool]$sync.validated;workspace_provisioned=$true;vscode_remote_platform=$sync.vscode_remote_platform;info=$info}
}

function Remove-ProjectVmSshAlias {
    param([Parameter(Mandatory)][string]$RuntimeId,[Parameter(Mandatory)][string]$ProjectId)
    $configPath=[string]$script:Config.SshConfigPath;$knownHostsPath=[string]$script:Config.SshKnownHostsPath;$removed=$false
    if($configPath -and (Test-Path -LiteralPath $configPath)){$markers=Get-ProjectVmSshMarkers $RuntimeId;$before=[IO.File]::ReadAllText($configPath);Set-DevFleetManagedTextBlock $configPath $markers.Pattern|Out-Null;$removed=$removed -or ([IO.File]::ReadAllText($configPath) -ne $before)}
    if($knownHostsPath -and (Test-Path -LiteralPath $knownHostsPath)){$knownMarkers=Get-ProjectVmKnownHostMarkers $RuntimeId;$before=[IO.File]::ReadAllText($knownHostsPath);Set-DevFleetManagedTextBlock $knownHostsPath $knownMarkers.Pattern|Out-Null;$removed=$removed -or ([IO.File]::ReadAllText($knownHostsPath) -ne $before)}
    $vsCode=if(Get-Command Remove-DevFleetVsCodeRemotePlatform -ErrorAction SilentlyContinue){Remove-DevFleetVsCodeRemotePlatform @(Get-DevFleetVsCodeSettingsPaths) $RuntimeId}else{[ordered]@{ok=$true;status='skipped';reason='VS Code helper is not installed.';alias=$RuntimeId}}
    if($removed){Write-AgentLog 'remove-ssh-alias' $ProjectId $RuntimeId 'removed' 'Removed only the destroyed project VM SSH alias and its managed host-key pin.'}
}

function Restore-PreviousSourceWorkspace { param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$SourceVm,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$PreviousWorkspacePath)
    $Slug=Assert-Slug $Slug;$ProjectId=Assert-ProjectId $ProjectId
    if([string]$Record.project_id -ne $ProjectId){throw 'Project identifier does not match the target VM ownership registry.'}
    if($SourceVm -notmatch '^devfleet-[a-z0-9][a-z0-9._-]{1,62}$' -or $SourceVm -eq $Record.vm_name){throw 'The export source VM is invalid.'}
    $expected="^/home/devrunner/workspaces/$([regex]::Escape($Slug))-before-vm-export-[0-9a-f]{32}$"
    if($PreviousWorkspacePath -notmatch $expected){throw 'The retained previous workspace path is invalid.'}
    $sourceInventory=@(Get-MultipassVms|Where-Object{$_.name -eq $SourceVm})
    if($sourceInventory.Count -ne 1 -or [string]$sourceInventory[0].state -ne 'RUNNING'){throw 'The DevFleet source VM must be running to restore its retained workspace.'}
    $workspace="/home/devrunner/workspaces/$Slug";$rollbackPath="/home/devrunner/workspaces/$Slug-failed-migration-$([guid]::NewGuid().ToString('N'))";$metadataPath="$PreviousWorkspacePath/.devfleet/project.json"
    $oldMetaText=(Invoke-Multipass @('exec',$SourceVm,'--','sudo','cat',$metadataPath) 30).Text
    try{$oldMeta=$oldMetaText|ConvertFrom-Json -AsHashtable}catch{throw 'The retained previous workspace metadata is invalid.'}
    if([string]$oldMeta.project_id -ne $ProjectId){throw 'The retained previous workspace belongs to a different project.'}
    $lock=New-ProvisioningLock
    try {
        Invoke-Multipass @('exec',$SourceVm,'--','sudo','test','-d',$workspace) 30|Out-Null
        Invoke-Multipass @('exec',$SourceVm,'--','sudo','test','-d',$PreviousWorkspacePath) 30|Out-Null
        Invoke-Multipass @('exec',$SourceVm,'--','sudo','mv',$workspace,$rollbackPath) 60|Out-Null
        try {Invoke-Multipass @('exec',$SourceVm,'--','sudo','mv',$PreviousWorkspacePath,$workspace) 60|Out-Null}
        catch {try{Invoke-Multipass @('exec',$SourceVm,'--','sudo','mv',$rollbackPath,$workspace) 60|Out-Null}catch{};throw}
        Invoke-Multipass @('exec',$SourceVm,'--','sudo','chown','-R','devrunner:devrunner',$workspace) 120|Out-Null
        Write-AgentLog 'restore-previous-source' $Record.project_id $Record.runtime_id 'restored' 'Atomically reinstated the retained source workspace after migration rollback.'
        return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$Record.runtime_id;project_id=$Record.project_id;source_vm=$SourceVm;workspace_path=$workspace;consumed_previous_workspace_path=$PreviousWorkspacePath;replaced_workspace_path=$rollbackPath;state='restored';message='Retained source workspace restored atomically.'}
    } finally {try{$lock.ReleaseMutex()}catch{};$lock.Dispose()}
}

function Invoke-ProjectVmOperation { param([Parameter(Mandatory)][string]$Operation,[Parameter(Mandatory)]$Payload,[string]$RuntimeId='')
    $Operation=$Operation.ToLowerInvariant();if($Operation -eq 'capacity'){return [ordered]@{ok=$true;host_name=$script:Config.HostName;capacity=Get-HostCapacity}};if($Operation -eq 'provider'){return [ordered]@{ok=$true;host_name=$script:Config.HostName;provider='multipass';provider_version=$script:Config.MultipassVersion;gpu_enabled=$false}}
    $slug=Assert-Slug ([string]$Payload.slug);$payloadProjectId=Assert-ProjectId ([string]$Payload.project_id);$record=Assert-OwnedProjectVm $slug $RuntimeId -AllowStoppedTransition:($Operation -eq 'start');if($payloadProjectId -ne [string]$record.project_id){throw 'Project identifier does not match the ownership registry.'};$vmName=[string]$record.vm_name;if($Operation -eq 'destroy' -and [bool]$Payload.cleanup_only){if([string]$Payload.confirm_slug -ne $slug -or [string]$Payload.confirm_phrase -cne "DESTROY $slug"){throw 'Cleanup-only removal requires the exact project confirmation phrase.'};return Remove-ImportFailedProjectVm $slug $record $Payload}
    switch($Operation){
        'sync-ssh-alias' {return Sync-ProjectVmSshAlias $slug $record}
        'refresh-connection-state' {return Refresh-ProjectVmConnectionState $slug $record}
        'start' {Invoke-Multipass @('start',$vmName) 120|Out-Null;Wait-ProjectVmReady $vmName|Out-Null;return Refresh-ProjectVmConnectionState $slug $record}
        'stop' {Invoke-Multipass @('stop',$vmName) 120|Out-Null;if([string]$record.address){$record.last_known_address=[string]$record.address};$record.address='';$record.state='stopped';$record.updated_at=(Get-Date).ToUniversalTime().ToString('o');Update-ProjectRecord $slug $record|Out-Null;Write-AgentLog 'stop' $record.project_id $record.runtime_id 'stopped' 'Project VM stopped; current address cleared and retained only as last_known_address.';return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;vm_name=$vmName;state='stopped';runtime_address='';last_known_address=$record.last_known_address;message='Dedicated project VM stopped.'}}
        'restart' {Invoke-Multipass @('restart',$vmName) 180|Out-Null;Wait-ProjectVmReady $vmName|Out-Null;return Refresh-ProjectVmConnectionState $slug $record}
        'inspect' {$info=Get-ProjectVmInfo $vmName;return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;record=$record;info=$info;gpu_enabled=$false}}
        'health' {$info=Get-ProjectVmInfo $vmName;if([string]$info.state -ne 'RUNNING'){return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;state='stopped';vm_name=$vmName;project_id=$record.project_id;gpu_enabled=$false;healthy=$false;runtime_health='not-run-stopped';health_scope='runtime-only';application_healthy=$false;application_health='not-run-stopped';guest_exec_performed=$false;info=$info}};$health=Invoke-Multipass @('exec',$vmName,'--','sudo','/usr/local/sbin/devfleet-project-health') 30;return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;state='healthy';vm_name=$vmName;project_id=$record.project_id;gpu_enabled=$false;healthy=$true;runtime_health='healthy';health_scope='runtime-only';application_healthy=$false;application_health='not-run';guest_exec_performed=$true;info=$info}}
        'backup' {return Backup-ProjectVm $record ([bool]$Payload.destructive)}
        'list-backups' {return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;project_id=$record.project_id;backups=@(Get-ProjectVmBackups $record)}}
        'inspect-backup' {$verified=Get-VerifiedProjectBackup $record ([string]$Payload.backup_id);return [ordered]@{ok=$true;host_name=$script:Config.HostName;host_id=$script:Config.HostId;runtime_id=$record.runtime_id;project_id=$record.project_id;backup=[ordered]@{backup_reference=$verified.backup_reference;sha_verified=$true;restore_eligible=$true}}}
        'restore-backup' {return Restore-ProjectVmBackup $record ([string]$Payload.backup_id) ([bool]$Payload.confirm_restore)}
        'export' {return Backup-ProjectVm $record}
        'export-to-source' {return Export-ProjectWorkspaceToSource $slug $record ([string]$Payload.source_vm) ([string]$Payload.project_id) ([bool]$Payload.replace_source)}
        'restore-previous-source' {return Restore-PreviousSourceWorkspace $slug $record ([string]$Payload.source_vm) ([string]$Payload.project_id) ([string]$Payload.previous_workspace_path)}
        'project-start' {return Invoke-ProjectCommand $record 'start_command'}
        'project-stop' {return Invoke-ProjectCommand $record 'stop_command'}
        'project-restart' {$manifest=Get-ProjectCommandManifest $record;if($manifest.restart_command -or ($manifest.commands -and $manifest.commands.restart_command)){return Invoke-ProjectCommand $record 'restart_command'};Invoke-ProjectCommand $record 'stop_command'|Out-Null;return Invoke-ProjectCommand $record 'start_command'}
        'project-health' {return Invoke-ProjectCommand $record 'health_command'}
        'project-test' {return Invoke-ProjectCommand $record 'test_command'}
        'project-bootstrap' {if([string]$Payload.command_key -eq 'codexpro'){return Invoke-ProjectCommand $record 'codexpro_command'};return Invoke-ProjectCommand $record 'bootstrap_command'}
        'project-rebuild' {return Invoke-ProjectCommand $record 'rebuild_command'}
        'project-logs' {return Invoke-ProjectCommand $record 'logs_command' ([int]$Payload.tail)}
        'quarantine' {if((Get-ProjectVmInfo $vmName).state -eq 'RUNNING'){Invoke-Multipass @('stop',$vmName) 120|Out-Null};$record.state='quarantined';Update-ProjectRecord $slug $record|Out-Null;return [ordered]@{ok=$true;host_name=$script