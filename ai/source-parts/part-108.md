# DevFleet source part 108

Full-source UTF-8 byte interval [4975500, 5022000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: f7ad7bb95454191f37e1d400f60af70f54408f04183244baf05360ae58e556b1

<!-- BEGIN SOURCE SLICE -->
:Config.HostName;runtime_id=$record.runtime_id;state='quarantined';message='Project VM quarantined and preserved.'}}
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
            $interfaceFilter[0] | Set-NetFirewallInterfaceFilter -InterfaceAlias ([string]$desired.InterfaceAlias) -ErrorAction Stop | Out-Null
        }
        if ($addressChanged) {
            $addressFilter = @($live | Get-NetFirewallAddressFilter -ErrorAction Stop)
            if ($addressFilter.Count -ne 1) { throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: firewall address filter '$bindingName' is ambiguous. Foreign resource preserved." }
            $addressFilter[0] | Set-NetFirewallAddressFilter -RemoteAddress ([string]$desired.RemoteAddress) -ErrorAction Stop | Out-Null
        }

        if ($interfaceChanged -or $addressChanged) {
            $refreshedRule = @(Get-NetFirewallRule -Name $bindingName -ErrorAction Stop)
            if ($refreshedRule.Count -ne 1) { throw "WINDOWS INTEGRATION OWNERSHIP CONFLICT: refreshed firewall identity '$bindingName' is ambiguous. Foreign resource preserved." }
            $refreshedActual = Get-DevFleetLiveFirewallBinding -Rule $refreshedRule[0] -Generation ([string]$binding.Generation)
            Assert-DevFleetFirewallBinding -Expected $desired -Actual $refreshedActual | Out-Null
            $changed++
        }
        $newBindings += $desired
    }

    if ($changed -gt 0) {
        $ledger.FirewallRules = @($newBindings)
        $ledger.UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Write-DevFleetIntegrationOwnership -Path $Path -Ledger $ledger
    }
    return [pscustomobject]@{ status = if ($changed -gt 0) { 'REFRESHED' } elseif ($skipped -gt 0) { 'PARTIAL' } else { 'CURRENT' }; changed = $changed; skipped = $skipped }
}

function Assert-DevFleetServiceBinding {
    param([Parameter(Mandatory)][hashtable]$Expected,[Parameter(Mandatory)][hashtable]$Actual)
    $Expected.ImagePath = ConvertTo-DevFleetCanonicalPath ([string]$Expected.ImagePath)
    $liveImage = [string]$Actual.ImagePath
    if ($liveImage.StartsWith('"')) {
        $closingQuote = $liveImage.IndexOf('"',1)
        if ($closingQuote -lt 2) { throw 'WINDOWS INTEGRATION OWNERSHIP CONFLICT: service image path is malformed. Foreign service preserved.' }
        $liveImage = $liveImage.Substring(1,$closingQuote - 1)
    } else {
        $liveImage = ($liveImage -split '\s+',2)[0]
    }
    $Actual.ImagePath = ConvertTo-DevFleetCanonicalPath $liveImage
    Assert-DevFleetExactFields 'service' $Expected $Actual @('Name','ImagePath','Account','StartMode','Generation')
}

function Read-DevFleetIntegrationOwnership {
    param([Parameter(Mandatory)][string]$Path,[switch]$AllowMissing)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($AllowMissing) { return $null }
        throw "Windows integration ownership ledger is missing: $Path"
    }
    if ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Windows integration ownership ledger is a reparse point; all resources preserved.'
    }
    $ledger = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if (-not $ledger -or [int]$ledger.SchemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$ledger.InstallationGeneration)) {
        throw 'Windows integration ownership ledger is malformed or unsupported.'
    }
    $generation = [guid]::Empty
    if (-not [guid]::TryParse([string]$ledger.InstallationGeneration,[ref]$generation) -or $generation -eq [guid]::Empty) {
        throw 'Windows integration ownership ledger generation is invalid.'
    }
    $identities = @{}
    foreach ($kindAndBindings in @(@('ScheduledTask',@($ledger.ScheduledTasks)),@('FirewallRule',@($ledger.FirewallRules)),@('Service',@($ledger.Services)))) {
        $kind = [string]$kindAndBindings[0]
        foreach ($binding in @($kindAndBindings[1])) {
        if ([string]$binding.Generation -ne [string]$ledger.InstallationGeneration) {
            throw 'Windows integration ownership ledger contains a cross-generation binding.'
        }
            $name = [string]$binding.Name
            if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('*') -or $name.Contains('?')) { throw 'Windows integration ownership ledger contains an ambiguous identity.' }
            $identity = "$kind`0$name".ToLowerInvariant()
            if ($identities.ContainsKey($identity)) { throw 'Windows integration ownership ledger contains a duplicate identity.' }
            $identities[$identity] = $true
            $required = switch ($kind) {
                'ScheduledTask' { @('Marker','Executable','Arguments','Principal','LogonType','RunLevel','Description') }
                'FirewallRule' { @('Marker','DisplayName','Group','Description','Direction','Action','Protocol','LocalPort','InterfaceAlias','RemoteAddress','Profile') }
                'Service' { @('Marker','ImagePath','Account','StartMode') }
            }
            foreach ($field in $required) {
                if ([string]::IsNullOrWhiteSpace([string]$binding[$field])) { throw "Windows integration ownership ledger contains an incomplete $kind binding." }
            }
        }
    }
    return $ledger
}

function Write-DevFleetIntegrationOwnership {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][hashtable]$Ledger)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,($Ledger | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function ConvertTo-DevFleetCanonicalPath,ConvertTo-DevFleetCanonicalFirewallRemoteAddress,Assert-DevFleetTaskBinding,Assert-DevFleetFirewallBinding,Assert-DevFleetFirewallRefreshIdentity,Assert-DevFleetServiceBinding,Read-DevFleetIntegrationOwnership,Write-DevFleetIntegrationOwnership,Invoke-DevFleetOwnedFirewallRefresh

```


## FILE: source/windows/DevFleet.Common.psm1

SHA256: 29e4a7fae0fde808e7e295bf4c9371be7da0cd2a37979d4347f3fb207f0c59d7 | Bytes: 108153 | Git mode: 100644

```
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DevFleetPackageRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-DevFleetStateRoot {
    Join-Path $env:ProgramData 'DevFleet'
}

function Get-ActiveDevFleetTransaction {
    $path = Join-Path (Get-DevFleetStateRoot) 'active-transaction.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $value = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ([string]$value.transactionId -notmatch '^[0-9a-fA-F]{32}$' -or [string]$value.payloadSha256 -notmatch '^[0-9a-fA-F]{64}$' -or [string]$value.action -notin @('FreshInstall','Repair','CleanReinstall','LocalUpdate') -or [string]$value.role -notin @('Laptop','Desktop')) { return $null }
        return $value
    } catch { return $null }
}

function Wait-ActiveDevFleetTransaction {
    param(
        [Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$ExpectedRole,
        [int]$TimeoutSeconds = 60
    )
    if ($TimeoutSeconds -le 0) { throw 'Active transaction wait timeout must be positive.' }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $deadlineContext = Get-DevFleetDeadlineContext
    if ($deadlineContext -and [datetime]$deadlineContext.StageDeadlineUtc -lt $deadline) { $deadline = [datetime]$deadlineContext.StageDeadlineUtc }
    do {
        $transaction = Get-ActiveDevFleetTransaction
        if (Test-DevFleetTransactionBinding -Transaction $transaction -ExpectedRole $ExpectedRole) { return $transaction }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Seconds 1
    } while ($true)
    return $null
}

function ConvertTo-DevFleetPreparedUtcText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('o') }
    return ([string]$Value).Trim()
}

function Test-DevFleetTransactionBinding {
    param(
        [AllowNull()][object]$Transaction,
        [Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$ExpectedRole
    )
    if (-not $Transaction) { return $false }
    $preparedUtcText = ConvertTo-DevFleetPreparedUtcText $Transaction.preparedUtc
    return ([string]$Transaction.role).Trim() -ceq $ExpectedRole -and
        ([string]$Transaction.action).Trim() -in @('FreshInstall','Repair','CleanReinstall','LocalUpdate') -and
        ([string]$Transaction.transactionId).Trim() -match '^[0-9a-fA-F]{32}$' -and
        ([string]$Transaction.payloadSha256).Trim() -match '^[0-9a-fA-F]{64}$' -and
        $preparedUtcText -match 'T'
}

function Set-DevFleetDeadlineContext {
    param(
        [Parameter(Mandatory)][datetime]$TransactionDeadlineUtc,
        [Parameter(Mandatory)][string]$StageName,
        [Parameter(Mandatory)][int]$StageBudgetSeconds
    )
    if ($StageBudgetSeconds -le 0) { throw "Stage '$StageName' must have a finite positive budget." }
    $transactionDeadline = $TransactionDeadlineUtc.ToUniversalTime()
    if ($transactionDeadline -le [datetime]::UtcNow) { throw 'The owning DevFleet transaction deadline has expired.' }
    $stageDeadline = [datetime]::UtcNow.AddSeconds($StageBudgetSeconds)
    if ($stageDeadline -gt $transactionDeadline) { $stageDeadline = $transactionDeadline }
    $global:DevFleetDeadlineContext = [pscustomobject]@{
        TransactionDeadlineUtc = $transactionDeadline
        StageName = $StageName
        StageDeadlineUtc = $stageDeadline
        StageBudgetSeconds = $StageBudgetSeconds
    }
    return $global:DevFleetDeadlineContext
}

function Get-DevFleetDeadlineContext {
    $variable=Get-Variable -Scope Global -Name DevFleetDeadlineContext -ErrorAction SilentlyContinue
    if($variable){return $variable.Value}
    return $null
}

function Get-DevFleetStageBudgetSeconds {
    param([Parameter(Mandatory)][string]$StageName)
    if ($StageName -eq 'compute') {
        return (Get-DevFleetOperationMaximumSeconds 'multipassLaunch') + (Get-DevFleetOperationMaximumSeconds 'multipassReadiness') + (Get-DevFleetOperationMaximumSeconds 'payloadTransfer') + (Get-DevFleetOperationMaximumSeconds 'guestBootstrap') + (Get-DevFleetOperationMaximumS