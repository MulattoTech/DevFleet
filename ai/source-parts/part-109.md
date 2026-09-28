# DevFleet source part 109

Full-source UTF-8 byte interval [5022000, 5068500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ad62c7188052e3389d146aeaf5cc75cc5a50dfe3a13bf91993a57222d1481aaf

<!-- BEGIN SOURCE SLICE -->
st.project_id;runtime_id=$latest.runtime_id;vm_name=$latest.vm_name;address=$address;state='ready';registry_address=$address;ssh_alias=$sync.ssh_alias;host_key_pinned=[bool]$sync.host_key_pinned;authenticated_connection=[bool]$sync.authenticated_connection;validated=[bool]$sync.validated;workspace_provisioned=$true;vscode_remote_platform=$sync.vscode_remote_platform;info=$info}
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

SHA256: 6e7ab0758d482f69112085ce84d153b9d5a7ab645d70da1a92963d24e38f7248 | Bytes: 5596 | Git mode: 100644

```
function ConvertFrom-DevFleetJsonc {
    param([Parameter(Mandatory)][string]$Text)
    $out = New-Object Text.StringBuilder
    $inString = $false; $escape = $false; $lineComment = $false; $blockComment = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]; $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
        if ($lineComment) { if ($c -eq "`r" -or $c -eq "`n") { $lineComment = $false; [void]$out.Append($c) }; continue }
        if ($blockComment) { if ($c -eq '*' -and $next -eq '/') { $blockComment = $false; $i++ }; continue }
        if ($inString) {
            [void]$out.Append($c)
            if ($escape) { $escape = $false } elseif ($c -eq '\') { $escape = $true } elseif ($c -eq '"') { $inString = $false }
            continue
        }
        if ($c -eq '"') { $inString = $true; [void]$out.Append($c); continue }
        if ($c -eq '/' -and $next -eq '/') { $lineComment = $true; $i++; continue }
        if ($c -eq '/' -and $next -eq '*') { $blockComment = $true; $i++; continue }
        [void]$out.Append($c)
    }
    return [regex]::Replace($out.ToString(), ',\s*([}\]])', '$1')
}

function Read-DevFleetVsCodeSettings {
    param([Parameter(Mandatory)][string]$Path)
    $raw = [IO.File]::ReadAllText($Path)
    try { return [pscustomobject]@{Raw=$raw;Data=(ConvertFrom-DevFleetJsonc $raw | ConvertFrom-Json -AsHashtable)} }
    catch {
        # Preserve the evidence before reporting malformed user settings. No
        # replacement is written when parsing fails.
        $backup = "$Path.devfleet-backup-$([guid]::NewGuid().ToString('N')).jsonc"
        [IO.File]::Copy($Path, $backup, $false)
        throw "VS Code settings are not valid JSONC; preserved backup $backup"
    }
}

function Write-DevFleetVsCodeSettings {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Data)
    $json = $Data | ConvertTo-Json -Depth 50
    $backup = "$Path.devfleet-backup-$([guid]::NewGuid().ToString('N')).jsonc"
    [IO.File]::Copy($Path, $backup, $false)
    $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try { [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false))); Move-Item -LiteralPath $tmp -Destination $Path -Force }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    return $backup
}

function Set-DevFleetVsCodeRemotePlatform {
    param([Parameter(Mandatory)][string[]]$Paths,[Parameter(Mandatory)][string]$Alias)
    $updated = @(); $skipped = @()
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { $skipped += $path; continue }
        $settings = Read-DevFleetVsCodeSettings $path
        $data = $settings.Data
        if ($null -eq $data) { $data = @{} }
        if (-not ($data -is [hashtable])) { throw "VS Code settings root must be an object: $path" }
        $mapping = if ($data.ContainsKey('remote.SSH.remotePlatform') -and $data['remote.SSH.remotePlatform'] -is [hashtable]) { $data['remote.SSH.remotePlatform'] } else { @{} }
        if ([string]$mapping[$Alias] -eq 'linux') { $skipped += $path; continue }
        $mapping[$Alias] = 'linux'; $data['remote.SSH.remotePlatform'] = $mapping
        $backup = Write-DevFleetVsCodeSettings $path $data
        $updated += [ordered]@{path=$path;backup=$backup;alias=$Alias;platform='linux'}
    }
    return [ordered]@{ok=$true;status='updated';updated_paths=@($updated);skipped_paths=@($skipped);alias=$Alias;platform='linux'}
}

function Remove-DevFleetVsCodeRemotePlatform {
    param([Parameter(Mandatory)][string[]]$Paths,[Parameter(Mandatory)][string]$Alias)
    $removed = @(); $skipped = @()
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { $skipped += $path; continue }
        $settings = Read-DevFleetVsCodeSettings $path; $data = $settings.Data
        if ($null -eq $data -or -not ($data -is [hashtable])) { throw "VS Code settings root must be an object: $path" }
        $mapping = $data['remote.SSH.remotePlatform']
        if ($mapping -isnot [hashtable] -or -not $mapping.ContainsKey($Alias)) { $skipped += $path; continue }
        $mapping.Remove($Alias)
        if ($mapping.Count -eq 0) { $data.Remove('remote.SSH.remotePlatform') }
        $backup = Write-DevFleetVsCodeSettings $path $data
        $removed += [ordered]@{path=$path;backup=$backup;alias=$Alias}
    }
    return [ordered]@{ok=$true;status='updated';removed_paths=@($removed);skipped_paths=@($skipped);alias=$Alias}
}

function Get-DevFleetVsCodeSettingsPaths {
    $values = @($script:Config.VsCodeSettingsPaths)
    return @($values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Sync-DevFleetVsCodeRemotePlatform {
    param([Parameter(Mandatory)][string]$Alias)
    $paths = @(Get-DevFleetVsCodeSettingsPaths)
    $knownExecutables = @(
        (Join-Path ${env:ProgramFiles} 'Microsoft VS Code\Code.exe'),
        (Join-Path ${env:LOCALAPPDATA} 'Programs\Microsoft VS Code\Code.exe'),
        (Join-Path ${env:ProgramFiles} 'Microsoft VS Code Insiders\Code - Insiders.exe'),
        (Join-Path ${env:LOCALAPPDATA} 'Programs\Microsoft VS Code Insiders\Code - Insiders.exe')
    )
    if (-not ($knownExecutables | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })) { return [ordered]@{ok=$true;status='skipped';reason='VS Code is not installed.';updated_paths=@();alias=$Alias;platform='linux'} }
    return Set-DevFleetVsCodeRemotePlatform $paths $Alias
}

```


## FILE: source/windows/DevFleet-WindowsIntegrationOwnership.psm1

SHA256: a05f3e85b4033d59e61d4ccdaa06bc8051befb711ae2b6fb26880f1ae89f1b0e | Bytes: 16444 | Git mode: 100644

```
Set-StrictMode -Version Latest

function ConvertTo-DevFleetCanonicalPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Windows integration executable path is empty.' }
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
}

function ConvertTo-DevFleetCanonicalFirewallRemoteAddress {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $text = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }
    $parts = $text -split '/', 2
    if ($parts.Count -ne 2) { return $text }

    $address = $null
    if (-not [Net.IPAddress]::TryParse($parts[0].Trim(), [ref]$address) -or
        $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $text }

    $maskText = $parts[1].Trim()
    $prefix = -1
    if (-not [int]::TryParse($maskText, [ref]$prefix)) {
        $maskAddress = $null
        if (-not [Net.IPAddress]::TryParse($maskText, [ref]$maskAddress) -or
            $maskAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $text }
        $maskBytes = $maskAddress.GetAddressBytes()
        $zeroSeen = $false
        $prefix = 0
        foreach ($maskByte in $maskBytes) {
            for ($bit = 7; $bit -ge 0; $bit--) {
                $set = (($maskByte -band (1 -shl $bit)) -ne 0)
                if ($set) {
                    if ($zeroSeen) { return $text }
                    $prefix++
                } else {
                    $zeroSeen = $true
                }
            }
        }
    }
    if ($prefix -lt 0 -or $prefix -gt 32) { return $text }

    $addressBytes = $address.GetAddressBytes()
    $canonicalMaskBytes = New-Object byte[] 4
    $remaining = $prefix
    for ($index = 0; $index -lt 4; $index++) {
        if ($remaining -ge 8) {
            $canonicalMaskBytes[$index] = 255
            $remaining -= 8
        } elseif ($remaining -le 0) {
            $canonicalMaskBytes[$index] = 0
        } else {
            $canonicalMaskBytes[$index] = [byte](256 - (1 -shl (8 - $remaining)))
            $remaining = 0
        }
    }

    $networkBytes = New-Object byte[] 4
    for ($index = 0; $index -lt 4; $index++) {
        $networkBytes[$index] = [byte]($addressBytes[$index] -band $canonicalMaskBytes[$index])
    }
    $network = ([Net.IPAddress]::new($networkBytes)).ToString()
    $canonicalMask = ([Net.IPAddress]::new($canonicalMaskBytes)).ToString()
    return "$network/$canonicalMask"
}

function Assert-DevFleetExactFields {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][hashtable]$Expected,
        [Parameter(Mandatory)][hashtable]$Actual,
        [Parameter(Mandatory)][string[]]$Fields
    )
    foreach ($field in $Fields) {
        $expectedValue = [string]$Expected[$field]
        $actualValue = [string]$Actual[$field]
        if ($field -eq 'RemoteAddress') {
            $expectedValue = ConvertTo-DevFleetCanonicalFirewallRemoteAddress $expectedValue
            $actualValue = ConvertTo-DevFleetCanonicalFirewallRemoteAddress $actualValue
        }
        $comparison = if ($field -in @('Arguments','Description')) { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
        if (-not [string]::Equals($expectedValue,$actualValue,$comparison)) {
            throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: $Kind field '$field' does not match the installation ownership ledger. Foreign resource preserved."
        }
    }
    return $true
}

function Assert-DevFleetTaskBinding {
    param([Parameter(Mandatory)][hashtable]$Expected,[Parameter(Mandatory)][hashtable]$Actual)
    $Expected.Executable = ConvertTo-DevFleetCanonicalPath ([string]$Expected.Executable)
    $Actual.Executable = ConvertTo-DevFleetCanonicalPath ([string]$Actual.Executable)
    Assert-DevFleetExactFields 'scheduled task' $Expected $Actual @('Name','Executable','Arguments','Principal','LogonType','RunLevel','Description','Generation')
}

function Assert-DevFleetFirewallBinding {
    param([Parameter(Mandatory)][hashtable]$Expected,[Parameter(Mandatory)][hashtable]$Actual)
    Assert-DevFleetExactFields 'firewall rule' $Expected $Actual @('Name','DisplayName','Group','Description','Direction','Action','Protocol','LocalPort','InterfaceAlias','RemoteAddress','Profile','Generation')
}

function Assert-DevFleetFirewallRefreshIdentity {
    param([Parameter(Mandatory)][hashtable]$Expected,[Parameter(Mandatory)][hashtable]$Actual)
    # InterfaceAlias and RemoteAddress are provider-backed network state. They
    # can legitimately change when a virtual adapter is recreated or its
    # subnet is renumbered. Every other rule field remains an immutable
    # ownership proof before a refresh is permitted.
    Assert-DevFleetExactFields 'firewall refresh' $Expected $Actual @('Name','DisplayName','Group','Description','Direction','Action','Protocol','LocalPort','Profile','Generation')
}

function Get-DevFleetLiveFirewallBinding {
    param([Parameter(Mandatory)]$Rule,[Parameter(Mandatory)][string]$Generation)
    $portFilters = @($Rule | Get-NetFirewallPortFilter -ErrorAction Stop)
    $addressFilters = @($Rule | Get-NetFirewallAddressFilter -ErrorAction Stop)
    $interfaceFilters = @($Rule | Get-NetFirewallInterfaceFilter -ErrorAction Stop)
    if ($portFilters.Count -ne 1 -or $addressFilters.Count -ne 1 -or $interfaceFilters.Count -ne 1) {
        throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall rule filter identity is ambiguous. Foreign resource preserved.'
    }
    $port = $portFilters[0]
    $address = $addressFilters[0]
    $interface = $interfaceFilters[0]
    return @{
        Name = [string]$Rule.Name
        DisplayName = [string]$Rule.DisplayName
        Group = [string]$Rule.Group
        Description = [string]$Rule.Description
        Direction = [string]$Rule.Direction
        Action = [string]$Rule.Action
        Protocol = [string]$port.Protocol
        LocalPort = [string]$port.LocalPort
        InterfaceAlias = [string]$interface.InterfaceAlias
        RemoteAddress = [string]$address.RemoteAddress
        Profile = [string]$Rule.Profile
        Generation = $Generation
    }
}

function Invoke-DevFleetOwnedFirewallRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(0,120)][int]$WaitSeconds = 0
    )
    $ledger = Read-DevFleetIntegrationOwnership -Path $Path -AllowMissing
    if (-not $ledger) {
        return [pscustomobject]@{ status = 'NO_LEDGER'; changed = 0; skipped = 0 }
    }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $newBindings = @()
    $changed = 0
    $skipped = 0
    foreach ($binding in @($ledger.FirewallRules)) {
        $bindingName = [string]$binding.Name
        $scope = if ($bindingName -match '-Multipass$') { 'Multipass' } elseif ($bindingName -match '-Tailscale$') { 'Tailscale' } else { $null }
        if (-not $scope) {
            throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall binding '$bindingName' has no supported DevFleet interface scope. Foreign resource preserved."
        }

        $adapterName = if ($scope -eq 'Multipass') { 'vEthernet (Default Switch)' } else { 'Tailscale' }
        $adapter = $null
        $multipassAddress = $null
        do {
            $adapter = @(Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $adapterName -and [string]$_.Status -eq 'Up' } | Select-Object -First 1)
            if ($adapter.Count -eq 0) { $adapter = $null }
            if ($adapter -and $scope -eq 'Multipass') {
                $multipassAddress = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1)
                if ($multipassAddress.Count -eq 0) { $multipassAddress = $null }
            }
            if ($adapter -and ($scope -eq 'Tailscale' -or $multipassAddress)) { break }
            if ((Get-Date) -ge $deadline) { break }
            Start-Sleep -Seconds 1
        } while ($true)

        if (-not $adapter -or ($scope -eq 'Multipass' -and -not $multipassAddress)) {
            # A deferred Tailscale installation legitimately has no Tailscale
            # adapter yet. Preserve the ledger and rule until a later startup
            # or explicit host-agent restart can reconcile it.
            $skipped++
            $newBindings += @{} + $binding
            continue
        }

        $desired = @{}
        foreach ($key in $binding.Keys) { $desired[$key] = $binding[$key] }
        $desired.InterfaceAlias = [string]$adapter.Name
        $desired.RemoteAddress = if ($scope -eq 'Multipass') {
            ConvertTo-DevFleetCanonicalFirewallRemoteAddress "$($multipassAddress.IPAddress)/$($multipassAddress.PrefixLength)"
        } else {
            ConvertTo-DevFleetCanonicalFirewallRemoteAddress '100.64.0.0/10'
        }

        $liveRules = @(Get-NetFirewallRule -Name $bindingName -ErrorAction SilentlyContinue)
        if ($liveRules.Count -eq 0) {
            $newBindings += $desired
            continue
        }
        if ($liveRules.Count -ne 1) {
            throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall identity '$bindingName' is ambiguous. Foreign resources preserved."
        }

        $live = $liveRules[0]
        $actual = Get-DevFleetLiveFirewallBinding -Rule $live -Generation ([string]$binding.Generation)
        Assert-DevFleetFirewallRefreshIdentity -Expected $binding -Actual $actual | Out-Null

        $actualRemote = ConvertTo-DevFleetCanonicalFirewallRemoteAddress ([string]$actual.RemoteAddress)
        $desiredRemote = ConvertTo-DevFleetCanonicalFirewallRemoteAddress ([string]$desired.RemoteAddress)
        $interfaceChanged = -not [string]::Equals([string]$actual.InterfaceAlias,[string]$desired.InterfaceAlias,[StringComparison]::OrdinalIgnoreCase)
        $addressChanged = -not [string]::Equals($actualRemote,$desiredRemote,[StringComparison]::OrdinalIgnoreCase)
        if ($interfaceChanged) {
            $interfaceFilter = @($live | Get-NetFirewallInterfaceFilter -ErrorAction Stop)
            if ($interfaceFilter.Count -ne 1) { throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall interface filter '$bindingName' is ambiguous. Foreign resource preserved." }
            $i