Set-StrictMode -Version Latest

function Get-DevFleetPassiveColdLaunchTelemetry {
    <# Independent diagnostic data only. The body is self-contained for PSDirect. #>
    param(
        [Parameter(Mandatory)]$ActiveTransaction,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Processes,
        [Parameter(Mandatory)][string]$TransactionId,
        [Parameter(Mandatory)][string]$PayloadSha256,
        [Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$RoleKind,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$InvocationStartUtc,
        [Parameter(Mandatory)][string]$ExpectedCandidateStartUtc,
        [Parameter(Mandatory)][int]$CandidateProcessId,
        [Parameter(Mandatory)][string]$ExpectedComputeInstanceName,
        [Parameter(Mandatory)][datetime]$ObservationDeadlineUtc,
        [ValidateRange(0,2000)][int]$CaptureMilliseconds=750,
        [scriptblock]$ProcessProvider,[scriptblock]$ConfigProvider,
        [scriptblock]$ServiceProvider,[scriptblock]$EventProvider,[scriptblock]$CacheMetadataProvider
    )
    $get={param($obj,$key)if($null-eq$obj){return $null};if($obj-is[Collections.IDictionary]){return $obj[$key]};$p=$obj.PSObject.Properties[$key];if($p){return $p.Value};return $null}
    $utc={param($value)try{([datetimeoffset]$value).UtcDateTime}catch{[datetime]::MinValue}}
    $out=[ordered]@{schemaVersion=1;kind='PASSIVE_COLD_LAUNCH_TELEMETRY';status='UNVERIFIED';certificationCredit=$false;launches=@();effectiveCompute=$null;services=@();events=@();cache=$null;errors=@();captureElapsedMilliseconds=0;rawCommandLineCaptured=$false;rawEventTextCaptured=$false;sampledUtc=[datetime]::UtcNow.ToString('o')}
    if($ObservationDeadlineUtc.ToUniversalTime()-le[datetime]::UtcNow){$out.status='OWNER_EXPIRED';return [pscustomobject]$out}
    $start=&$utc $InvocationStartUtc;$expectedRootStart=&$utc $ExpectedCandidateStartUtc;$prepared=&$utc (&$get $ActiveTransaction 'preparedUtc')
    $root=@($Processes|Where-Object{[int](&$get $_ 'ProcessId')-eq$CandidateProcessId})
    $rootStart=if($root.Count-eq1){&$utc (&$get $root[0] 'CreationDate')}else{[datetime]::MinValue}
    $instance=if($RoleKind-ceq'Laptop'){'devfleet-failover'}else{'devfleet-primary'}
    if($TransactionId -notmatch '^[0-9a-fA-F]{32}$' -or $PayloadSha256 -notmatch '^[0-9a-f]{64}$' -or
        $ExpectedComputeInstanceName -cne $instance -or $start -eq [datetime]::MinValue -or
        $prepared -lt $start -or $prepared -gt [datetime]::UtcNow -or $root.Count -ne 1 -or
        $expectedRootStart -eq [datetime]::MinValue -or $rootStart -lt $start -or $rootStart -gt [datetime]::UtcNow -or
        [math]::Abs(($rootStart-$expectedRootStart).Ticks) -gt 9 -or
        [string](&$get $root[0] 'Name') -notmatch '^DevFleet-Setup.*\.exe$' -or
        [string](&$get $ActiveTransaction 'transactionId') -cne $TransactionId -or
        [string](&$get $ActiveTransaction 'payloadSha256') -cne $PayloadSha256 -or
        [string](&$get $ActiveTransaction 'action') -cne $Action -or
        [string](&$get $ActiveTransaction 'role') -cne $RoleKind){$out.errors=@('TRANSACTION_PROCESS_FRESHNESS_BINDING_UNVERIFIED');return [pscustomobject]$out}
    # CIM DMTF creation timestamps retain microseconds; the WPF acknowledgement
    # may retain 100ns ticks. Require the same instant within that representation.
    $out.binding=[ordered]@{transactionId=$TransactionId;payloadSha256=$PayloadSha256;role=$RoleKind;action=$Action;invocationStartUtc=$start.ToString('o');preparedUtc=$prepared.ToString('o');candidatePid=$CandidateProcessId;candidateStartUtc=$rootStart.ToString('o');acknowledgedCandidateStartUtc=$expectedRootStart.ToString('o');instanceName=$instance}
    $vendor=Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'
    $cloud=Join-Path $env:ProgramData ('DevFleet\tmp\cloud-'+$instance+'.yaml')
    $grammar='^\s*(?:"(?<exe>[^"]+)"|(?<exe>\S+))\s+launch\s+--timeout\s+(?<timeout>[1-9][0-9]{0,3})\s+(?<image>[0-9]{2}\.[0-9]{2})\s+--name\s+(?<name>[a-zA-Z0-9._-]+)\s+--cpus\s+(?<cpus>[1-9][0-9]?)\s+--memory\s+(?<memory>[1-9][0-9]?G)\s+--disk\s+(?<disk>[1-9][0-9]{1,2}G)\s+--cloud-init\s+(?:"(?<cloud>[^"]+)"|(?<cloud>\S+))\s*$'
    $seen=[Collections.Generic.HashSet[string]]::new();$watch=[Diagnostics.Stopwatch]::StartNew();$rows=$Processes
    do {
        foreach($row in @($rows|Where-Object{[string](&$get $_ 'Name')-ieq'multipass.exe'})){
            $created=&$utc (&$get $row 'CreationDate');$pidValue=[int](&$get $row 'ProcessId')
            if($created-lt$prepared-or$created-lt$rootStart-or$created-gt[datetime]::UtcNow-or[int](&$get $row 'SessionId')-ne[int](&$get $root[0] 'SessionId')){continue}
            $owned=$false;$parent=[int](&$get $row 'ParentProcessId');$visited=[Collections.Generic.HashSet[int]]::new()
            for($depth=0;$depth-lt12-and$visited.Add($parent);$depth++){
                if($parent-eq$CandidateProcessId){$owned=$true;break}
                $ancestor=@($rows|Where-Object{[int](&$get $_ 'ProcessId')-eq$parent})
                if($ancestor.Count-ne1-or(&$utc (&$get $ancestor[0] 'CreationDate'))-lt$rootStart-or(&$utc (&$get $ancestor[0] 'CreationDate'))-gt$created-or[int](&$get $ancestor[0] 'SessionId')-ne[int](&$get $root[0] 'SessionId')){break}
                $parent=[int](&$get $ancestor[0] 'ParentProcessId')
            }
            if(-not$owned){continue}
            $m=[regex]::Match([string](&$get $row 'CommandLine'),$grammar)
            if(-not $m.Success -or $m.Groups['name'].Value -cne $instance -or
                $m.Groups['exe'].Value -ine $vendor -or [string](&$get $row 'ExecutablePath') -ine $vendor -or
                $m.Groups['cloud'].Value -ine $cloud -or [int]$m.Groups['timeout'].Value -gt 900 -or
                [int]$m.Groups['cpus'].Value -gt 12 -or [int]$m.Groups['memory'].Value.TrimEnd('G') -gt 32){continue}
            if($seen.Add("${pidValue}:$($created.ToString('o'))")){
                $out.launches+=,[ordered]@{pid=$pidValue;parentPid=[int](&$get $row 'ParentProcessId');startUtc=$created.ToString('o');sessionId=[int](&$get $row 'SessionId');executablePath=$vendor;image=$m.Groups['image'].Value;timeoutSeconds=[int]$m.Groups['timeout'].Value;instanceName=$instance;cpus=[int]$m.Groups['cpus'].Value;memory=$m.Groups['memory'].Value;disk=$m.Groups['disk'].Value;cloudInitPath=$cloud;ownership='FRESH_CANDIDATE_DESCENDANT';rawCommandLineCaptured=$false}
            }
        }
        if($out.launches.Count-or$watch.ElapsedMilliseconds-ge$CaptureMilliseconds-or($ObservationDeadlineUtc.ToUniversalTime()-[datetime]::UtcNow).TotalSeconds-lt2){break}
        Start-Sleep -Milliseconds 100
        try{$rows=if($ProcessProvider){@(&$ProcessProvider 1)}else{@(Get-CimInstance Win32_Process -OperationTimeoutSec 1 -ErrorAction Stop)}}catch{$out.errors+='PASSIVE_PROCESS_SNAPSHOT_UNVERIFIED';break}
    }while($true)
    $watch.Stop();$out.captureElapsedMilliseconds=[int]$watch.ElapsedMilliseconds
    if(-not$ConfigProvider){$ConfigProvider={
        $path=Join-Path $env:ProgramData 'DevFleet\devfleet.config.json';$item=Get-Item -LiteralPath $path -ErrorAction Stop
        if($item.Attributes-band[IO.FileAttributes]::ReparsePoint-or$item.Length-gt1048576){throw 'Config boundary'}
        Get-Content -LiteralPath $path -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    }}
    if(-not$ServiceProvider){$ServiceProvider={
        foreach($s in @(Get-CimInstance Win32_Service -Filter "Name='Multipass'" -OperationTimeoutSec 1 -ErrorAction Stop)){
            $daemon=Join-Path $env:ProgramFiles 'Multipass\bin\multipassd.exe';$proc=Get-Process -Id ([int]$s.ProcessId) -ErrorAction SilentlyContinue
            $image=if([int]$s.ProcessId-gt0){Get-CimInstance Win32_Process -Filter ("ProcessId="+[int]$s.ProcessId) -OperationTimeoutSec 1 -ErrorAction SilentlyContinue}else{$null}
            $serviceImage=[regex]::Match([string]$s.PathName,'^\s*(?:"(?<exe>[^"]+)"|(?<exe>\S+))(?:\s|$)')
            $verified=($serviceImage.Success-and$serviceImage.Groups['exe'].Value-ieq$daemon-and$image-and[string]$image.ExecutablePath-ieq$daemon)
            [pscustomobject]@{name=$s.Name;state=$s.State;pid=$s.ProcessId;startTimeUtc=if($proc){$proc.StartTime.ToUniversalTime().ToString('o')}else{''};executableVerified=[bool]$verified;binarySha256=if($verified-and(Test-Path -LiteralPath $daemon -PathType Leaf)){(Get-FileHash -LiteralPath $daemon).Hash.ToLowerInvariant()}else{''};version=if($verified-and(Test-Path -LiteralPath $daemon -PathType Leaf)){[Diagnostics.FileVersionInfo]::GetVersionInfo($daemon).ProductVersion}else{''}}
        }
    }}
    if(-not$EventProvider){$EventProvider={Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Multipass';StartTime=$start.ToLocalTime()} -MaxEvents 32 -ErrorAction SilentlyContinue}}
    if(-not$CacheMetadataProvider){$CacheMetadataProvider={
        # Effective daemon environment is unavailable: these are candidates,
        # not asserted active storage. Never read data/certificates/cache bytes.
        $paths=@((Join-Path $env:ProgramData 'Multipass\cache\network-cache'),(Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Roaming\multipassd\cache\network-cache'))
        $records=@(foreach($p in $paths){$item=Get-Item -LiteralPath $p -ErrorAction SilentlyContinue;if($item-and-not($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){[ordered]@{candidatePath=$p;lastWriteUtc=$item.LastWriteTimeUtc.ToString('o');contentCaptured=$false}}})
        [pscustomobject]@{status='EFFECTIVE_PATH_UNVERIFIED';source='UPSTREAM_WINDOWS_DEFAULT_CANDIDATES';records=$records;contentsCaptured=$false}
    }}
    try{
        if([datetime]::UtcNow-lt$ObservationDeadlineUtc.ToUniversalTime()){
            $config=&$ConfigProvider;$node=&$get $config $(if($RoleKind-ceq'Laptop'){'Failover'}else{'Primary'})
            if([string](&$get $node 'InstanceName')-cne$instance){throw 'Config target'}
            $image=[string](&$get $node 'UbuntuImage');$imageStatus=if($image-eq''){'EMPTY'}elseif($image-match'^[0-9]{2}\.[0-9]{2}$'){'OBSERVED'}else{'UNRECOGNIZED_REDACTED'}
            $out.effectiveCompute=[ordered]@{instanceName=$instance;ubuntuImage=if($imageStatus-ceq'OBSERVED'){$image}else{''};imageStatus=$imageStatus;cpus=if([string](&$get $node 'Cpus')-match'^(?:[2-9]|1[0-2])$'){[int](&$get $node 'Cpus')}else{$null};memory=if([string](&$get $node 'Memory')-match'^(?:[2-9]|[12][0-9]|3[0-2])G$'){[string](&$get $node 'Memory')}else{''};disk=if([string](&$get $node 'Disk')-match'^[1-9][0-9]{1,2}G$'){[string](&$get $node 'Disk')}else{''};otherConfigFieldsCaptured=$false}
        }
    }catch{$out.errors+='EFFECTIVE_CONFIG_UNVERIFIED'}
    try{if([datetime]::UtcNow-lt$ObservationDeadlineUtc.ToUniversalTime()){
        $out.services=@(foreach($s in @(&$ServiceProvider)){
            if([string](&$get $s 'name')-ine'Multipass'){continue}
            $verified=(&$get $s 'executableVerified')-is[bool]-and(&$get $s 'executableVerified')-eq$true
            [ordered]@{name='Multipass';state=if([string](&$get $s 'state')-in@('Running','Stopped','Start Pending','Stop Pending')){[string](&$get $s 'state')}else{'UNVERIFIED'};pid=[int](&$get $s 'pid');startTimeUtc=if((&$utc (&$get $s 'startTimeUtc'))-ne[datetime]::MinValue){(&$utc (&$get $s 'startTimeUtc')).ToString('o')}else{''};executableVerified=$verified;binarySha256=if($verified-and[string](&$get $s 'binarySha256')-match'^[a-f0-9]{64}$'){[string](&$get $s 'binarySha256')}else{''};version=if($verified-and[string](&$get $s 'version')-match'^[0-9]+\.[0-9]+\.[0-9]+(?:[+.-][A-Za-z0-9]+)?$'){[string](&$get $s 'version')}else{''};contextOnly=$true}
        })
    }}catch{$out.errors+='MULTIPASS_SERVICE_UNVERIFIED'}
    try{if([datetime]::UtcNow-lt$ObservationDeadlineUtc.ToUniversalTime()){
        $out.events=@(foreach($e in @(&$EventProvider|Select-Object -First 32)){
            $eventTime=&$utc (&$get $e 'TimeCreated');if($eventTime-lt$start-or$eventTime-gt[datetime]::UtcNow){continue}
            $message=[string](&$get $e 'Message');$class=''
            if($message-match'(?i)(failed|failure|error).*cdimage\.ubuntu\.com/ubuntu-core'){$class='CUSTOM_METADATA_DOWNLOAD_FAILURE'}
            elseif($message-match'(?i)Could not update manifest|QFutureWatcher caught DownloadException'){$class='MANIFEST_UPDATE_FAILURE'}
            elseif($message-match'(?i)fetch manifest periodically'){$class='PERIODIC_MANIFEST_FETCH_STARTED'}
            elseif($message-match'(?i)fetch manifest from the internet'){$class='FORCED_MANIFEST_FETCH_OBSERVED'}
            elseif($message-match'(?i)trying cache'){$class='NETWORK_CACHE_FALLBACK'}
            elseif($message-match'(?i)download_timeout|Qt error'){$class='DOWNLOADER_FAILURE_CONTEXT'}
            if($class){[ordered]@{eventId=[int](&$get $e 'Id');recordId=[long](&$get $e 'RecordId');timestampUtc=$eventTime.ToString('o');classification=$class;temporalContextOnly=$true;rawMessageCaptured=$false}}
        })
    }}catch{$out.errors+='MANIFEST_EVENT_CONTEXT_UNVERIFIED'}
    try{if([datetime]::UtcNow-lt$ObservationDeadlineUtc.ToUniversalTime()){
        $cache=&$CacheMetadataProvider
        $allowed=@((Join-Path $env:ProgramData 'Multipass\cache\network-cache'),(Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Roaming\multipassd\cache\network-cache'))
        $out.cache=[ordered]@{status=if([string](&$get $cache 'status')-in@('NOT_OBSERVED','EFFECTIVE_PATH_UNVERIFIED')){[string](&$get $cache 'status')}else{'UNVERIFIED'};source='UPSTREAM_WINDOWS_DEFAULT_CANDIDATES';contentsCaptured=$false;records=@(foreach($record in @(&$get $cache 'records')){
            $path=[string](&$get $record 'candidatePath');$modified=&$utc (&$get $record 'lastWriteUtc')
            if($path-in$allowed-and$modified-ne[datetime]::MinValue){[ordered]@{candidatePath=$path;lastWriteUtc=$modified.ToString('o');contentCaptured=$false}}
        })}
    }}catch{$out.errors+='CACHE_METADATA_UNVERIFIED'}
    $out.manifestCompletion='NOT_OBSERVED; upstream has no successful completion log'
    $out.status=if($out.launches.Count){'OBSERVED'}else{'LAUNCH_NOT_OBSERVED'}
    [pscustomobject]$out
}

function Get-DevFleetPassiveColdLaunchTelemetryScript {
    (Get-Command Get-DevFleetPassiveColdLaunchTelemetry -Module ProductLaunchTelemetry).ScriptBlock
}

Export-ModuleMember -Function Get-DevFleetPassiveColdLaunchTelemetry,Get-DevFleetPassiveColdLaunchTelemetryScript
