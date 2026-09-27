[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/MultipassDiagnostic.psm1'
$scratch=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('devfleet-backend-fixture-'+[guid]::NewGuid().ToString('N'))))
$results=[Collections.Generic.List[object]]::new()
$io=@'
            $script:backendName=$Name
            if($ObserveProduct){$env:ProgramData=$env:DEVFLEET_BACKEND_ROOT}
            function Get-CimInstance {
                param($ClassName,$OperationTimeoutSec)
                if($env:DEVFLEET_BACKEND_FIXTURE-ceq'timeout'){Start-Sleep 20}
                if($env:DEVFLEET_BACKEND_FIXTURE-ceq'partial'){throw 'fixture provider failure token=private-value'}
                if($ClassName-ceq'Win32_Service'){[pscustomobject]@{Name='Multipass';State='Running';ProcessId=42;ExitCode=0;StartMode='Auto';StartName='LocalSystem'}}
                else {
                    @([pscustomobject]@{Name='multipassd.exe';ProcessId=42;ParentProcessId=1;CreationDate=[datetime]::UtcNow},[pscustomobject]@{Name='powershell.exe';ProcessId=43;ParentProcessId=42;CreationDate=[datetime]::UtcNow})
                    if($ObserveProduct){
                        $exe=Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe';$cloud=Join-Path $env:ProgramData 'DevFleet\tmp\cloud-devfleet-primary.yaml'
                        $command='"'+$exe+'" launch 24.04 --name devfleet-primary --cpus 4 --memory 9G --disk 220G --cloud-init "'+$cloud+'"'
                        if($env:DEVFLEET_BACKEND_FIXTURE-ceq'product-unknown-args'){$command+=' --token private-value'}
                        [pscustomobject]@{Name='multipass.exe';ProcessId=50;ParentProcessId=60;CreationDate=[datetime]::UtcNow;SessionId=1;CommandLine=$command}
                    }
                }
            }
            function Invoke-CimMethod {param($InputObject,$MethodName)[pscustomobject]@{ReturnValue=0;Sid='S-1-5-21-123-456-789-1000'}}
            function Get-VM {[pscustomobject]@{Name=$script:backendName;Id=[guid]'11111111-1111-1111-1111-111111111111';State='Running';Status='Operating normally';Generation=2;ProcessorCount=4;MemoryStartup=9GB;MemoryAssigned=9GB;Uptime=[timespan]::FromSeconds(5)}}
            function Get-VMHardDiskDrive {param($VM)[pscustomobject]@{Path='fixture.vhdx'}}
            function Get-VHD {param($Path)[pscustomobject]@{Size=220GB;FileSize=3GB;VhdType='Dynamic';Attached=$true}}
            function Get-VMNetworkAdapter {param($VM)[pscustomobject]@{SwitchName='Default Switch';Status=@('Ok');IPAddresses=@('172.20.0.5')}}
            function Get-WinEvent {
                param($ListLog,$FilterHashtable,$MaxEvents)
                if($ListLog){[pscustomobject]@{IsEnabled=$true}}
                else {
                    # Windows event filtering interprets the supplied wall time as
                    # local even when DateTime.Kind is UTC. M4 recovered events
                    # only when the same instant was explicitly converted locally.
                    if($FilterHashtable.StartTime.Kind-ne[DateTimeKind]::Local-or$FilterHashtable.StartTime.ToUniversalTime()-ne$Since.ToUniversalTime()){throw 'Event filter did not preserve the requested instant as local wall time.'}
                    [pscustomobject]@{ProviderName='Microsoft-Windows-Hyper-V-VMMS';Id=100;RecordId=200;TimeCreated=[datetime]::UtcNow;Message='fixture boot event token=private-value'}
                }
            }
'@
try{
    New-Item -ItemType Directory -Path $scratch|Out-Null
    $text=[IO.File]::ReadAllText($source);$needle='param($Name,$Since,$ObserveProduct,$Payload)'
    if(([regex]::Matches($text,[regex]::Escape($needle))).Count-ne1){throw 'Actual backend I/O fixture boundary is ambiguous.'}
    $fixtureModule=Join-Path $scratch 'MultipassDiagnostic.psm1';[IO.File]::WriteAllText($fixtureModule,$text.Replace($needle,$needle+[Environment]::NewLine+$io),[Text.UTF8Encoding]::new($false))
    Import-Module $fixtureModule -Force -DisableNameChecking
    foreach($case in @('complete','partial','timeout','product-success','product-wrong-payload','product-bad-config','product-unknown-args')){
        $env:DEVFLEET_BACKEND_FIXTURE=$case;$timer=[Diagnostics.Stopwatch]::StartNew()
        $parameters=@{InstanceName='DevFleet-E2E-E-M1-fixture';SinceUtc=[datetime]::UtcNow.AddMinutes(-1);OwnerDeadlineUtc=[datetime]::UtcNow.AddSeconds(25);TimeoutSeconds=if($case-ceq'timeout'){1}else{15}}
        if($case-like'product-*'){
            $dataRoot=Join-Path $scratch $case;$env:DEVFLEET_BACKEND_ROOT=$dataRoot;New-Item -ItemType Directory -Path (Join-Path $dataRoot 'DevFleet/tmp'),(Join-Path $dataRoot 'M-TechLabs/DevFleet/Logs')|Out-Null
            @{Primary=@{InstanceName='devfleet-primary';Cpus=4;Memory=if($case-ceq'product-bad-config'){'token=private-value'}else{'9G'};Disk='220G';UbuntuImage='24.04'};Token='private-value'}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $dataRoot 'DevFleet/devfleet.config.json')
            @{transactionId=('b'*32);payloadSha256=if($case-ceq'product-wrong-payload'){'f'*64}else{'a'*64};secret='private-value'}|ConvertTo-Json|Set-Content (Join-Path $dataRoot 'DevFleet/active-transaction.json')
            '#cloud-config'|Set-Content (Join-Path $dataRoot 'DevFleet/tmp/cloud-devfleet-primary.yaml')
            'state=failed error=native failed token=private-value Bearer private-value'|Set-Content (Join-Path $dataRoot 'M-TechLabs/DevFleet/Logs/setup-fixture.log')
            $parameters.InstanceName='devfleet-primary';$parameters.ProductContext=$true;$parameters.ExpectedPayloadSha256='a'*64
        }
        $snapshot=Get-DevFleetCampaignEBackendSnapshot @parameters
        $timer.Stop();$pass=$true
        if($case-ceq'complete'){$pass=$snapshot.status-ceq'COMPLETE'-and@($snapshot.data.processes).Count-eq2-and@($snapshot.data.backend.owned).Count-eq1-and$snapshot.data.backend.owned[0].disks[0].virtualBytes-eq220GB-and@($snapshot.data.events).Count-eq2}
        elseif($case-ceq'partial'){$pass=$snapshot.status-ceq'PARTIAL'-and@($snapshot.errors).Count-eq1-and$snapshot.data.backend.status-ceq'PASS'}
        elseif($case-ceq'timeout'){$pass=$snapshot.status-ceq'UNVERIFIED'-and$timer.Elapsed.TotalSeconds-lt10}
        elseif($case-cin@('product-wrong-payload','product-bad-config')){$pass=$snapshot.status-ceq'PARTIAL'-and$snapshot.data.product.status-ceq'UNVERIFIED'}
        else{
            $pass=$snapshot.status-ceq'COMPLETE'-and$snapshot.data.product.status-ceq'TRANSACTION_OBSERVED'-and$snapshot.data.product.effectivePrimary.cpus-eq4-and$snapshot.data.product.cloudInit.sha256-match'^[a-f0-9]{64}$'-and$snapshot.data.product.failureRecords[0].tail-match'native failed'-and@($snapshot.data.events).Count-eq3-and$snapshot.data.services[0].startMode-ceq'Auto'-and$snapshot.data.backend.owned[0].networkAdapters[0].ipAddresses[0]-ceq'172.20.0.5'
            if($case-ceq'product-success'){$pass=$pass-and$snapshot.data.launches.Count-eq1-and$snapshot.data.launches[0].sessionId-eq1-and$snapshot.data.launches[0].principalStatus-ceq'OBSERVED'-and$snapshot.data.launches[0].principalSidSha256-match'^[a-f0-9]{64}$'-and-not$snapshot.data.launches[0].rawCommandLineCaptured}else{$pass=$pass-and$snapshot.data.launches.Count-eq0}
        }
        $pass=$pass-and($snapshot|ConvertTo-Json -Depth 12)-notmatch'private-value'
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;status=$snapshot.status;elapsed=[math]::Round($timer.Elapsed.TotalSeconds,2);detail=if(-not$pass){$snapshot}else{$null}})
    }
}finally{
    Remove-Item Env:\DEVFLEET_BACKEND_FIXTURE -ErrorAction SilentlyContinue
    Remove-Item Env:\DEVFLEET_BACKEND_ROOT -ErrorAction SilentlyContinue
    if(-not$scratch.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($scratch)-notlike'devfleet-backend-fixture-*'){throw 'Backend fixture cleanup escaped its boundary.'}
    if(Test-Path $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
$results|ConvertTo-Json -Depth 12
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Actual bounded backend observer regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) bounded backend observer checks ($($PSVersionTable.PSVersion))"
