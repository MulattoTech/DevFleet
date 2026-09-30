[CmdletBinding()]
param([switch]$SerializedCollector)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/ProductLaunchTelemetry.psm1') -Force
$collector=if($SerializedCollector){[scriptblock]::Create((Get-DevFleetPassiveColdLaunchTelemetryScript).ToString())}else{Get-Command Get-DevFleetPassiveColdLaunchTelemetry}
$results=[Collections.Generic.List[object]]::new()
$base=[datetime]::UtcNow.AddSeconds(-15);$tx='a'*32;$payload='b'*64
$root=[pscustomobject]@{ProcessId=100;ParentProcessId=1;Name='DevFleet-Setup-v1.2.13-win-x64.exe';ExecutablePath='C:\ProgramData\DevFleet\E2E\fixture\DevFleet-Setup-v1.2.13-win-x64.exe';SessionId=1;CreationDate=$base.AddSeconds(1)}
$parent=[pscustomobject]@{ProcessId=101;ParentProcessId=100;Name='pwsh.exe';ExecutablePath='C:\Program Files\PowerShell\7\pwsh.exe';SessionId=1;CreationDate=$base.AddSeconds(3)}
$child=[pscustomobject]@{ProcessId=102;ParentProcessId=101;Name='multipass.exe';ExecutablePath='C:\Program Files\Multipass\bin\multipass.exe';SessionId=1;CreationDate=$base.AddSeconds(5);CommandLine='"C:\Program Files\Multipass\bin\multipass.exe" launch --timeout 569 24.04 --name devfleet-failover --cpus 4 --memory 9G --disk 220G --cloud-init C:\ProgramData\DevFleet\tmp\cloud-devfleet-failover.yaml'}
$active=[pscustomobject]@{transactionId=$tx;payloadSha256=$payload;action='FreshInstall';role='Laptop';preparedUtc=$base.AddSeconds(2).ToString('o')}
$config={ [pscustomobject]@{Failover=[pscustomobject]@{InstanceName='devfleet-failover';UbuntuImage='24.04';Cpus=4;Memory='9G';Disk='220G'};Secret='do-not-emit-fixture-secret'} }
$service={ [pscustomobject]@{name='multipass';state='Running';pid=300;startTimeUtc=$base.ToString('o');executableVerified=$true;binarySha256=('c'*64);version='1.16.4+win'} }.GetNewClosure()
$events={ @([pscustomobject]@{Id=7;RecordId=8;TimeCreated=[datetime]::UtcNow;Message='Download failed for https://cdimage.ubuntu.com/ubuntu-core/24/stable/current/SHA256SUMS token=do-not-emit-fixture-secret'}) }
$cache={ [pscustomobject]@{status='NOT_OBSERVED';reason='Effective storage configuration unavailable';records=@()} }
function Invoke-Case {
    param([string]$Name,[hashtable]$Overrides,[scriptblock]$Assert)
    $p=@{ActiveTransaction=$active;Processes=@($root,$parent,$child);TransactionId=$tx;PayloadSha256=$payload;RoleKind='Laptop';Action='FreshInstall';InvocationStartUtc=$base.ToString('o');ExpectedCandidateStartUtc=$root.CreationDate.ToString('o');CandidateProcessId=100;ExpectedComputeInstanceName='devfleet-failover';ObservationDeadlineUtc=[datetime]::UtcNow.AddSeconds(5);CaptureMilliseconds=0;ConfigProvider=$config;ServiceProvider=$service;EventProvider=$events;CacheMetadataProvider=$cache}
    foreach($key in $Overrides.Keys){$p[$key]=$Overrides[$key]}
    $value=& $collector @p
    if(-not(& $Assert $value)){throw "Passive telemetry case failed: $Name"}
    if(($value|ConvertTo-Json -Depth 12)-match'do-not-emit-fixture-secret'){throw "Telemetry exposed arbitrary fixture text: $Name"}
    if($value.certificationCredit-or$value.PSObject.Properties['progressMarker']-or$value.PSObject.Properties['terminalFailure']){throw 'Passive telemetry acquired lifecycle authority'}
    $results.Add([pscustomobject]@{case=$Name;status=$value.status;pass=$true})
}
Invoke-Case 'exact bound timeout launch and sanitized config/events' @{} {param($v)$v.status-ceq'OBSERVED'-and$v.launches.Count-eq1-and$v.launches[0].timeoutSeconds-eq569-and$v.launches[0].image-ceq'24.04'-and$v.effectiveCompute.ubuntuImage-ceq'24.04'-and$v.events[0].classification-ceq'CUSTOM_METADATA_DOWNLOAD_FAILURE'-and-not$v.launches[0].rawCommandLineCaptured}
foreach($case in @('wrong-payload','stale-transaction','wrong-role','reused-root-pid')){
    $a=$active.PSObject.Copy();$r=$root.PSObject.Copy()
    switch($case){'wrong-payload'{$a.payloadSha256='f'*64};'stale-transaction'{$a.preparedUtc=$base.AddSeconds(-1).ToString('o')};'wrong-role'{$a.role='Desktop'};'reused-root-pid'{$r.CreationDate=$base.AddSeconds(4)}}
    $never={throw 'Unbound telemetry reached an I/O provider'}
    Invoke-Case $case @{ActiveTransaction=$a;Processes=@($r,$parent,$child);ConfigProvider=$never;ServiceProvider=$never;EventProvider=$never;CacheMetadataProvider=$never} {param($v)$v.status-ceq'UNVERIFIED'-and$v.launches.Count-eq0}
}
foreach($case in @('wrong-parent','wrong-instance','unknown-secret-argument','stale-child','wrong-session')){
    $c=$child.PSObject.Copy()
    switch($case){'wrong-parent'{$c.ParentProcessId=999};'wrong-instance'{$c.CommandLine=$c.CommandLine.Replace('devfleet-failover','foreign-instance')};'unknown-secret-argument'{$c.CommandLine+=' --token do-not-emit-fixture-secret'};'stale-child'{$c.CreationDate=$base.AddSeconds(-1)};'wrong-session'{$c.SessionId=2}}
    Invoke-Case $case @{Processes=@($root,$parent,$c)} {param($v)$v.launches.Count-eq0}
}
Invoke-Case 'expired observation does not read providers' @{ObservationDeadlineUtc=[datetime]::UtcNow.AddSeconds(-1);ConfigProvider={throw 'expired read'}} {param($v)$v.status-ceq'OWNER_EXPIRED'}
Invoke-Case 'empty effective image is observed without changing it' @{ConfigProvider={ [pscustomobject]@{Failover=[pscustomobject]@{InstanceName='devfleet-failover';UbuntuImage='';Cpus=4;Memory='9G';Disk='220G'}} }} {param($v)$v.effectiveCompute.imageStatus-ceq'EMPTY'-and$v.effectiveCompute.ubuntuImage-eq''}
Invoke-Case 'unknown config image cannot expose arbitrary text' @{ConfigProvider={ [pscustomobject]@{Failover=[pscustomobject]@{InstanceName='devfleet-failover';UbuntuImage='do-not-emit-fixture-secret';Cpus=4;Memory='9G';Disk='220G'}} }} {param($v)$v.effectiveCompute.imageStatus-ceq'UNRECOGNIZED_REDACTED'}
Invoke-Case 'cache provider is projected through a metadata allowlist' @{CacheMetadataProvider={ [pscustomobject]@{status='NOT_OBSERVED';reason='do-not-emit-fixture-secret';records=@();private='do-not-emit-fixture-secret'} }} {param($v)$v.cache.status-ceq'NOT_OBSERVED'}
Invoke-Case 'unverified daemon executable cannot claim binary identity' @{ServiceProvider={ [pscustomobject]@{name='multipass';state='Running';pid=300;executableVerified=$false;binarySha256=('c'*64);version='1.16.4+win'} }} {param($v)-not$v.services[0].executableVerified-and$v.services[0].binarySha256-eq''-and$v.services[0].version-eq''}
$resumed=$root.PSObject.Copy();$resumed.CreationDate=$base.AddSeconds(3)
$resumeParent=$parent.PSObject.Copy();$resumeParent.CreationDate=$base.AddSeconds(4)
Invoke-Case 'acknowledged resume root may follow transaction preparation' @{Processes=@($resumed,$resumeParent,$child);ExpectedCandidateStartUtc=$resumed.CreationDate.ToString('o')} {param($v)$v.launches.Count-eq1}
$state=[pscustomobject]@{calls=0};$poll={param($seconds)$state.calls++;if($state.calls-eq1){@($root,$parent,$child)}else{@($root,$parent)}}.GetNewClosure()
Invoke-Case 'short lived child captured inside bounded passive window' @{Processes=@($root,$parent);ProcessProvider=$poll;CaptureMilliseconds=350} {param($v)$v.launches.Count-eq1-and$v.captureElapsedMilliseconds-lt1500}
$results|ConvertTo-Json -Depth 4
Write-Host "PASS $($results.Count)/$($results.Count) synthetic passive cold-launch telemetry cases; no native credit"
