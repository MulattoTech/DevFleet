# DevFleet source part 109

Full-source UTF-8 byte interval [5022000, 5068500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2eb442f7c2167f48f438651e3214f13918671879f850280da33034f1d9e69141

<!-- BEGIN SOURCE SLICE -->
script:Root "imports\$([guid]::NewGuid().ToString('N')).tar.gz"
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
        'quarantine' {if((Get-ProjectVmInfo $vmName).state -eq 'RUNNING'){Invoke-Multipass @('stop',$vmName) 120|Out-Null};$record.state='quarantined';Update-ProjectRecord $slug $record|Out-Null;return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;state='quarantined';message='Project VM quarantined and preserved.'}}
        'restore' {Invoke-Multipass @('start',$vmName) 120|Out-Null;Wait-ProjectVmReady $vmName|Out-Null;$record.state='ready';Update-ProjectRecord $slug $record|Out-Null;return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;state='ready';message='Project VM restored.'}}
        'import' {return Import-ProjectWorkspace $slug $RuntimeId ([string]$Payload.source_vm) ([string]$Payload.project_id)}
        'destroy' {$payloadProjectId=Assert-ProjectId ([string]$Payload.project_id);if($payloadProjectId -ne [string]$record.project_id){throw 'Project identifier does not match the ownership registry.'};if([string]$Payload.confirm_slug -ne $slug -or [string]$Payload.confirm_phrase -cne "DESTROY $slug"){throw 'Permanent destruction requires the exact project slug and confirmation phrase.'};if(-not [bool]$Payload.backup_verified -or -not [string]$Payload.backup_id -or -not [string]$Payload.backup_sha256){throw 'A specific verified workspace backup is required before permanent VM destruction.'};$manifestPath=Join-Path $script:BackupRoot "$(Assert-BackupId ([string]$Payload.backup_id)).json";if(-not(Test-Path -LiteralPath $manifestPath)){throw 'The requested backup manifest is not present on the host.'};$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -AsHashtable;if([string]$manifest.project_id -ne [string]$record.project_id -or [string]$manifest.slug -ne $slug -or [string]$manifest.runtime_id -ne [string]$record.runtime_id -or [string]$manifest.archive_sha256 -ne [string]$Payload.backup_sha256 -or [string]$manifest.source_archive_sha256 -ne [string]$manifest.host_archive_sha256 -or [string]$manifest.host_archive_sha256 -ne [string]$Payload.backup_sha256){throw 'Backup manifest identity or source/host hash equality does not match the project VM.'};$archiveHash=(Get-FileHash -LiteralPath ([string]$manifest.archive_path) -Algorithm SHA256).Hash.ToLowerInvariant();if($archiveHash -ne [string]$Payload.backup_sha256){throw 'Workspace backup archive hash no longer matches its verified manifest.'};$lock=New-ProvisioningLock;try{$info=Get-ProjectVmInfo $vmName;if([string]$info.state -eq 'RUNNING'){Invoke-Multipass @('stop',$vmName) 120|Out-Null};Invoke-Multipass @('delete',$vmName,'--purge') 600|Out-Null;if(@(Get-MultipassVms|Where-Object{$_.name -eq $vmName}).Count -ne 0){throw 'Multipass still reports the project VM after deletion.'};Remove-ProjectVmSshAlias $record.runtime_id $record.project_id;$record.state='destroyed';$record.destroyed_at=(Get-Date).ToUniversalTime().ToString('o');Update-ProjectRecord $slug $record|Out-Null;Write-AgentLog 'destroy' $record.project_id $record.runtime_id 'destroyed' 'Permanent project VM destruction completed after archive verification.';return [ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;vm_name=$vmName;state='destroyed';backup_id=$Payload.backup_id;message='Dedicated project VM destroyed after verified workspace backup.'}}finally{try{$lock.ReleaseMutex()}catch{};$lock.Dispose()}}
        default {throw 'Unsupported host VM operation.'}
    }
}

function Send-JsonResponse { param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Body,[int]$StatusCode=200);$json=$Body|ConvertTo-Json -Depth 20 -Compress;$bytes=[Text.Encoding]::UTF8.GetBytes($json);$Context.Response.StatusCode=$StatusCode;$Context.Response.ContentType='application/json';$Context.Response.ContentEncoding=[Text.Encoding]::UTF8;$Context.Response.ContentLength64=$bytes.Length;$Context.Response.OutputStream.Write($bytes,0,$bytes.Length);$Context.Response.Close() }
function Send-AuthenticatedJsonResponse {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Body,[int]$StatusCode=200,[Parameter(Mandatory)]$Auth)
    $json=$Body|ConvertTo-Json -Depth 20 -Compress
    $bytes=[Text.Encoding]::UTF8.GetBytes($json)
    $material=([string]$Auth.Method.ToUpperInvariant()+"`n"+[string]$Auth.Path+"`n"+[string]$Auth.Timestamp+"`n"+[string]$Auth.Nonce+"`n"+[string]$StatusCode+"`n"+$json+"`n"+[string]$Auth.Expected)
    $hmac=[Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes([string]$script:Token))
    try{$signature=([BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($material)))-replace '-','').ToLowerInvariant()}finally{$hmac.Dispose()}
    $Context.Response.Headers['X-DevFleet-Host-Response-Signature']=$signature
    $Context.Response.StatusCode=$StatusCode;$Context.Response.ContentType='application/json';$Context.Response.ContentEncoding=[Text.Encoding]::UTF8;$Context.Response.ContentLength64=$bytes.Length;$Context.Response.OutputStream.Write($bytes,0,$bytes.Length);$Context.Response.Close()
}
function Read-JsonBody { param([Parameter(Mandatory)][string]$Text);if(-not $Text){return @{}};try{return $Text|ConvertFrom-Json -AsHashtable}catch{throw 'Request body is not valid JSON.'} }
$script:NonceStatePath=Join-Path $script:Root 'seen-request-nonces.json'
$script:SeenRequestNonces=@{}
function Read-NonceState {
    $script:SeenRequestNonces=@{}
    if(-not (Test-Path -LiteralPath $script:NonceStatePath -PathType Leaf)){return}
    try {
        $data=Get-Content -LiteralPath $script:NonceStatePath -Raw | ConvertFrom-Json -AsHashtable
        foreach($entry in $data.GetEnumerator()){[int64]$stamp=0;if([int64]::TryParse([string]$entry.Value,[ref]$stamp)){$script:SeenRequestNonces[[string]$entry.Key]=$stamp}}
    } catch { Write-AgentLog 'nonce-state' '' '' 'warning' 'Persisted nonce state was unreadable; starting with an empty bounded replay set.' }
}
function Save-NonceState {
    param([int64]$Now)
    foreach($key in @($script:SeenRequestNonces.Keys)){if(($Now-[int64]$script:SeenRequestNonces[$key])-gt 120){$script:SeenRequestNonces.Remove($key)}}
    $tmp="$script:NonceStatePath.$([guid]::NewGuid().ToString('N')).tmp"
    try { $script:SeenRequestNonces | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmp -Encoding UTF8; Move-Item -LiteralPath $tmp -Destination $script:NonceStatePath -Force }
    finally { if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue} }
}
Read-NonceState
function Test-RequestToken {
    param([Parameter(Mandatory)]$Context)
    $reader=[IO.StreamReader]::new($Context.Request.InputStream,[Text.Encoding]::UTF8);try{$body=$reader.ReadToEnd()}finally{$reader.Dispose()}
    $timestamp=[string]$Context.Request.Headers['X-DevFleet-Host-Timestamp'];$nonce=[string]$Context.Request.Headers['X-DevFleet-Host-Nonce'];$expected=[string]$Context.Request.Headers['X-DevFleet-Host-Expected'];$provided=[string]$Context.Request.Headers['X-DevFleet-Host-Signature'];$epoch=0L
    if(-not [long]::TryParse($timestamp,[ref]$epoch)){return $null};$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if([math]::Abs($now-$epoch)-gt 60 -or [string]::IsNullOrWhiteSpace($nonce) -or [string]::IsNullOrWhiteSpace($provided)){return $null}
    if($expected -ne [string]$script:Config.HostName -and $expected -ne [string]$script:Config.HostId){return $null}
    foreach($key in @($script:SeenRequestNonces.Keys)){if(($now-[int64]$script:SeenRequestNonces[$key])-gt 120){$script:SeenRequestNonces.Remove($key)}}
    $material=([string]$Context.Request.HttpMethod.ToUpperInvariant()+"`n"+[string]$Context.Request.Url.AbsolutePath+"`n"+$timestamp+"`n"+$nonce+"`n"+$body+"`n"+$expected)
    $hmac=[Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes([string]$script:Token));try{$actual=([BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($material)))-replace '-','').ToLowerInvariant()}finally{$hmac.Dispose()}
    $left=[Text.Encoding]::UTF8.GetBytes($actual);$right=[Text.Encoding]::UTF8.GetBytes($provided.ToLowerInvariant())
    if($left.Length -ne $right.Length -or -not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($left,$right)){return $null}
    if($script:SeenRequestNonces.ContainsKey($nonce)){return $null}
    $script:SeenRequestNonces[$nonce]=$now;Save-NonceState $now
    return [pscustomobject]@{Body=$body}
}

if($LibraryOnly){return}

# Hyper-V checkpoint restore and Windows virtual-network recreation can leave an
# owned firewall filter pointing at an old adapter identity or subnet. Refresh
# only rules whose immutable fields still prove exact DevFleet ownership before
# the listener is exposed. A missing deferred interface is preserved and can be
# reconciled on a later service restart.
$ownershipModulePath = Join-Path $script:Root 'DevFleet-WindowsIntegrationOwnership.psm1'
if (-not (Test-Path -LiteralPath $ownershipModulePath -PathType Leaf)) { throw 'Host-agent Windows integration ownership module is missing.' }
Import-Module $ownershipModulePath -Force
$firewallRefresh = Invoke-DevFleetOwnedFirewallRefresh -Path (Join-Path $script:Root 'integration-ownership.json') -WaitSeconds 30
Write-AgentLog 'firewall-refresh' '' '' ([string]$firewallRefresh.status) ("changed={0}; skipped={1}" -f [int]$firewallRefresh.changed,[int]$firewallRefresh.skipped)

$workerScript = {
    param([string]$ScriptPath,[string]$ConfigPath,[psobject]$Request)
    . $ScriptPath -ConfigPath $ConfigPath -LibraryOnly
    try {
        $path=$Request.path.TrimEnd('/');$method=$Request.method.ToUpperInvariant();$payload=if($Request.body){$Request.body|ConvertFrom-Json -AsHashtable}else{@{}}
        $parts=$path.Trim('/').Split('/');$runtimeId=if($parts.Count -ge 3){[uri]::UnescapeDataString($parts[2])}else{''}
        if($method -eq 'GET' -and $path -eq '/v1/host'){ $result=[ordered]@{ok=$true;host_id=$script:Config.HostId;host_name=$script:Config.HostName;agent_version=$script:AgentVersion;provider='multipass';capacity=Get-HostCapacity} }
        elseif($method -eq 'GET' -and $path -eq '/v1/host/capacity'){ $result=[ordered]@{ok=$true;host_name=$script:Config.HostName;capacity=Get-HostCapacity} }
        elseif($method -eq 'GET' -and $path -eq '/v1/provider'){ $result=[ordered]@{ok=$true;host_name=$script:Config.HostName;provider='multipass';provider_version=$script:Config.MultipassVersion;gpu_enabled=$false} }
        elseif($parts.Count -lt 2 -or $parts[0] -ne 'v1' -or $parts[1] -ne 'project-vms'){ throw 'Not found.' }
        elseif($method -eq 'POST' -and $parts.Count -eq 2){$limits=$payload.resource_limits;if(-not $limits){throw 'resource_limits is required.'};$result=Ensure-ProjectVm ([string]$payload.slug) ([string]$payload.project_id) ([double]$limits.cpus) ([double]$limits.memory_gb) ([double]$limits.disk_gb) ([string]$payload.git_url)}
        elseif($method -eq 'GET' -and $parts.Count -eq 3){$slug=Get-ProjectSlugByRuntime $runtimeId;$record=Assert-OwnedProjectVm $slug $runtimeId;$result=[ordered]@{ok=$true;host_name=$script:Config.HostName;runtime_id=$record.runtime_id;record=$record;info=Get-ProjectVmInfo $record.vm_name;gpu_enabled=$false}}
        elseif($parts.Count -ne 4){throw 'Not found.'}
        else {$operation=$parts[3];if($method -eq 'DELETE'){$result=Invoke-ProjectVmOperation 'destroy' $payload $runtimeId}elseif($method -eq 'POST'){$result=Invoke-ProjectVmOperation $operation $payload $runtimeId}else{throw 'Method not allowed.'}}
        [pscustomobject]@{status=200;body=$result}
    } catch { [pscustomobject]@{status=400;body=[ordered]@{ok=$false;error=$_.Exception.Message}} }
}
$listener=[Net.HttpListener]::new();$listener.Prefixes.Add([string]$script:Config.ListenPrefix);$listener.Start();Write-AgentLog 'agent' '' '' 'started' "Listening on $($script:Config.ListenPrefix)"
$pool=[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1,4);$pool.Open()
$jobs=[Collections.Generic.List[object]]::new();$accept=$listener.BeginGetContext($null,$null)
try {
    while($listener.IsListening) {
        if($accept.IsCompleted) {
            $context=$null;$auth=$null;$responseAuth=$null
            try {
                $context=$listener.EndGetContext($accept);$accept=$listener.BeginGetContext($null,$null);$path=$context.Request.Url.AbsolutePath.TrimEnd('/');$method=$context.Request.HttpMethod.ToUpperInvariant()
                $auth=Test-RequestToken $context
                if(-not $auth){Send-JsonResponse $context @{ok=$false;error='Unauthorized.'} 401;continue}
                $responseAuth=[pscustomobject]@{Timestamp=[string]$context.Request.Headers['X-DevFleet-Host-Timestamp'];Nonce=[string]$context.Request.Headers['X-DevFleet-Host-Nonce'];Expected=[string]$context.Request.Headers['X-DevFleet-Host-Expected'];Method=$method;Path=$path}
                if($method -eq 'GET' -and $path -eq '/healthz'){Send-AuthenticatedJsonResponse $context ([ordered]@{ok=$true;service='devfleet-host-agent';agent_version=$script:AgentVersion;host_name=$script:Config.HostName;host_id=$script:Config.HostId}) 200 $responseAuth;continue}
                if($jobs.Count -ge 4){Send-AuthenticatedJsonResponse $context ([ordered]@{ok=$false;error='Host Agent is busy; retry this request.'}) 503 $responseAuth;continue}
                $ps=[PowerShell]::Create();$ps.RunspacePool=$pool;[void]$ps.AddScript($workerScript).AddArgument($PSCommandPath).AddArgument($ConfigPath).AddArgument([pscustomobject]@{path=$path;method=$method;body=[string]$auth.Body});$async=$ps.BeginInvoke();$jobs.Add([pscustomobject]@{PowerShell=$ps;Async=$async;Context=$context;Auth=$responseAuth})
            } catch { try{if($auth -and $responseAuth){Send-AuthenticatedJsonResponse $context ([ordered]@{ok=$false;error=$_.Exception.Message}) 400 $responseAuth}else{Send-JsonResponse $context @{ok=$false;error=$_.Exception.Message} 400}}catch{} }
        }
        for($i=$jobs.Count-1;$i -ge 0;$i--) {
            $job=$jobs[$i]
            if(-not $job.Async.IsCompleted){continue}
            try{$output=@($job.PowerShell.EndInvoke($job.Async));$response=if($output.Count -gt 0){$output[$output.Count-1]}else{[pscustomobject]@{status=500;body=@{ok=$false;error='Worker returned no response.'}}};Send-AuthenticatedJsonResponse $job.Context $response.body ([int]$response.status) $job.Auth}
            catch{try{Send-AuthenticatedJsonResponse $job.Context ([ordered]@{ok=$false;error='Host Agent worker failed.'}) 500 $job.Auth}catch{}}
            finally{$job.PowerShell.Dispose();$jobs.RemoveAt($i)}
        }
        $pollMilliseconds=if($jobs.Count -gt 0){20}else{200}
        Start-Sleep -Milliseconds $pollMilliseconds
    }
} finally {
    try{$listener.Stop();$listener.Close()}catch{}
    foreach($job in @($jobs)){try{$job.PowerShell.Stop()}catch{};try{$job.PowerShell.Dispose()}catch{}}
    try{$pool.Close();$pool.Dispose()}catch{}
    Write-AgentLog 'agent' '' '' 'stopped' 'Host agent listener stopped.'
}

```


## FILE: source/windows/DevFleet-HostAgentProtocol.psm1

SHA256: 6e1b0bcea1194b7a4b5443f80b8af01e8331ed6772578cac272867de3334034f | Bytes: 4785 | Git mode: 100644

```
Set-StrictMode -Version Latest

function ConvertTo-HostAgentHmac {
    param([Parameter(Mandatory)][byte[]]$Key,[Parameter(Mandatory)][byte[]]$Material)
    $hmac=[Security.Cryptography.HMACSHA256]::new($Key)
    try { return (([BitConverter]::ToString($hmac.ComputeHash($Material)) -replace '-','').ToLowerInvariant()) }
    finally { $hmac.Dispose() }
}

function New-HostAgentRequestAuthentication {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Body,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$ExpectedHost
    )
    if([string]::IsNullOrWhiteSpace($Key) -or [string]::IsNullOrWhiteSpace($ExpectedHost)){throw 'Host Agent authentication configuration is incomplete.'}
    $timestamp=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
    $nonceBytes=New-Object byte[] 18;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($nonceBytes)}finally{$rng.Dispose()}
    $nonce=[Convert]::ToBase64String($nonceBytes).TrimEnd('=').Replace('+','-').Replace('/','_')
    $material=[Text.Encoding]::UTF8.GetBytes(([string]$Method.ToUpperInvariant()+"`n"+$Path+"`n"+$timestamp+"`n"+$nonce+"`n"+[Text.Encoding]::UTF8.GetString($Body)+"`n"+$ExpectedHost))
    return [ordered]@{Timestamp=$timestamp;Nonce=$nonce;Expected=$ExpectedHost;Signature=(ConvertTo-HostAgentHmac ([Text.Encoding]::UTF8.GetBytes($Key)) $material)}
}

function Test-HostAgentResponseAuthentication {
    param(
        [Parameter(Mandatory)][string]$Method,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Body,[Parameter(Mandatory)][string]$Key,[Parameter(Mandatory)][string]$ExpectedHost,
        [Parameter(Mandatory)][string]$Timestamp,[Parameter(Mandatory)][string]$Nonce,[Parameter(Mandatory)][string]$Provided
    )
    $material=[Text.Encoding]::UTF8.GetBytes(([string]$Method.ToUpperInvariant()+"`n"+$Path+"`n"+$Timestamp+"`n"+$Nonce+"`n"+$StatusCode.ToString([Globalization.CultureInfo]::InvariantCulture)+"`n"+[Text.Encoding]::UTF8.GetString($Body)+"`n"+$ExpectedHost))
    $actual=ConvertTo-HostAgentHmac ([Text.Encoding]::UTF8.GetBytes($Key)) $material
    $left=[Text.Encoding]::ASCII.GetBytes($actual);$right=[Text.Encoding]::ASCII.GetBytes(([string]$Provided).ToLowerInvariant())
    if($left.Length -ne $right.Length -or -not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($left,$right)){throw 'Host Agent response authentication failed.'}
    return $true
}

function Invoke-HostAgentAuthenticatedJson {
    param([Parameter(Mandatory)][string]$Uri,[Parameter(Mandatory)][string]$Method,[Parameter(Mandatory)][string]$Key,[Parameter(Mandatory)][string]$ExpectedHost,[hashtable]$Body=@{})
    $parsed=[Uri]$Uri;$path=$parsed.AbsolutePath;$bodyBytes=[Text.Encoding]::UTF8.GetBytes(($Body|ConvertTo-Json -Depth 20 -Compress));if($Method.ToUpperInvariant() -eq 'GET'){$bodyBytes=[byte[]]@()}
    $auth=New-HostAgentRequestAuthentication $Method $path $bodyBytes $Key $ExpectedHost
    $request=[Net.HttpWebRequest]::Create($Uri);$request.Method=$Method.ToUpperInvariant();$request.Timeout=3000;$request.ReadWriteTimeout=3000;$request.Headers['X-DevFleet-Host-Timestamp']=$auth.Timestamp;$request.Headers['X-DevFleet-Host-Nonce']=$auth.Nonce;$request.Headers['X-DevFleet-Host-Expected']=$auth.Expected;$request.Headers['X-DevFleet-Host-Signature']=$auth.Signature
    if($bodyBytes.Length -gt 0){$request.ContentType='application/json';$request.ContentLength=$bodyBytes.Length;$stream=$request.GetRequestStream();try{$stream.Write($bodyBytes,0,$bodyBytes.Length)}finally{$stream.Dispose()}}
    $response=$null;$responseBody=[byte[]]@()
    try{$response=$request.GetResponse()}catch [Net.WebException]{if(-not $_.Exception.Response){throw};$response=$_.Exception.Response}
    try{$stream=$response.GetResponseStream();$memory=[IO.MemoryStream]::new();try{$stream.CopyTo($memory);$responseBody=$memory.ToArray()}finally{$memory.Dispose();$stream.Dispose()};$status=[int]$response.StatusCode;$signature=[string]$response.Headers['X-DevFleet-Host-Response-Signature'];Test-HostAgentResponseAuthentication $Method $path $status $responseBody $Key $ExpectedHost $auth.Timestamp $auth.Nonce $signature|Out-Null;if($status -lt 200 -or $status -ge 300){throw "Host Agent rejected authenticated request ($status)."};return ([Text.Encoding]::UTF8.GetString($responseBody)|ConvertFrom-Json)}finally{if($response){$response.Dispose()}}
}

Export-ModuleMember -Function New-HostAgentRequestAuthentication,Test-HostAgentResponseAuthentication,Invoke-HostAgentAuthenticatedJson

```


## FILE: source/windows/DevFleet-VSCode.ps1

SHA256: 6e7ab0758d482f69112085ce84d153b9d5a7ab645d70da1a92963d24e38f7248 