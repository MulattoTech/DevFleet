[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force
$module=Get-Module Invoke-RealProductPhase
$checks=[Collections.Generic.List[object]]::new()
$remote={param($s)$s.context.observation}
$guest={
    param($s)
    $s.context.probeCalls++
    $reads=@(foreach($target in $s.targets){
        $marker=@{schemaVersion=1;transactionId=$s.transactionId;payloadSha256=$s.payloadSha256;sequence=9;component='bootstrap';state='COMPLETED';updatedUtc='2026-01-01T00:00:06Z';packageVersion=if($target.nodeRole-ceq'vault'){'vault'}else{'1.2.13'};nodeRole=$target.nodeRole}
        [pscustomobject]@{instanceName=$target.instanceName;text=($marker|ConvertTo-Json -Compress);exitCode=0;timedOut=$false}
    })
    [pscustomobject]@{status='READS_COLLECTED';error='';inventoryExitCode=0;probedInstances=@($s.targets.instanceName);markerReads=$reads}
}
foreach($case in @('desktop-launch','laptop-compute-launch','laptop-vault-launch','started','launched','ready','payload-transferred','payload-extracted','complete','no-native-child','foreign-parent','stale-child','unbound-transaction','wrong-payload','wrong-stage-role','wrong-instance-stage','duplicate-pid','foreign-native-path','parent-cycle','stale-transaction','existing-terminal')){
    $role=if($case-like'laptop-*'){'Laptop / Surrogate'}else{'Primary / Desktop'}
    $kind=if($case-like'laptop-*'){'Laptop'}else{'Desktop'}
    $compute=if($kind-ceq'Laptop'){'devfleet-failover'}else{'devfleet-primary'}
    $prefix=if($case-ceq'laptop-vault-launch'){'stage-vault'}else{"stage-compute-$compute"}
    $stage=[pscustomobject]@{name="$prefix-instance-absent.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-absent";completedUtc='2026-01-01T00:00:04Z'}
    $candidate=[pscustomobject]@{pid=100;parentPid=99;name='DevFleet-Setup.exe';commandClass='DevFleet-Setup';startTimeUtc='2026-01-01T00:00:01Z'}
    $bootstrap=[pscustomobject]@{pid=101;parentPid=100;name='pwsh.exe';commandClass='Bootstrap-Install';startTimeUtc='2026-01-01T00:00:02Z'}
    $installer=[pscustomobject]@{pid=102;parentPid=101;name='pwsh.exe';commandClass='Install-DevFleet';startTimeUtc='2026-01-01T00:00:03Z'}
    $native=[pscustomobject]@{pid=103;parentPid=102;name='multipass.exe';path='C:\Program Files\Multipass\bin\multipass.exe';commandClass='multipass';startTimeUtc='2026-01-01T00:00:05Z'}
    $observation=[pscustomobject]@{candidateProcess=$candidate;activeTransaction=[pscustomobject]@{transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;preparedUtc='2026-01-01T00:00:02Z'};stageMarkers=@($stage);stageMarkerErrors=@();terminalFailure=$false;progress=[pscustomobject]@{productChildInstances=@($candidate,$bootstrap,$installer,$native);guestProgressMarkerStatus='DEFERRED'}}
    switch($case){
        'started' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-instance-started.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-started";completedUtc='2026-01-01T00:00:06Z'}}
        'launched' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-instance-launched.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-launched";completedUtc='2026-01-01T00:00:06Z'}}
        'ready' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-instance-ready.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-ready";completedUtc='2026-01-01T00:00:06Z'}}
        'payload-transferred' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-payload-transferred.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-payload-transferred";completedUtc='2026-01-01T00:00:06Z'}}
        'payload-extracted' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-payload-extracted.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-payload-extracted";completedUtc='2026-01-01T00:00:06Z'}}
        'complete' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage=$prefix;completedUtc='2026-01-01T00:00:06Z'}}
        'no-native-child' {$observation.progress.productChildInstances=@($candidate,$bootstrap,$installer)}
        'foreign-parent' {$native.parentPid=900}
        'stale-child' {$native.startTimeUtc='2025-12-31T23:59:59Z'}
        'unbound-transaction' {$observation.activeTransaction.transactionId='c'*32}
        'wrong-payload' {$stage.payloadSha256='c'*64}
        'wrong-stage-role' {$stage.role='Laptop'}
        'wrong-instance-stage' {$stage.name='stage-compute-foreign-instance-absent.complete';$stage.stage='stage-compute-foreign-instance-absent'}
        'duplicate-pid' {$observation.progress.productChildInstances+=,$native}
        'foreign-native-path' {$native.path='C:\unrelated\multipass.exe'}
        'parent-cycle' {$installer.parentPid=103}
        'stale-transaction' {$observation.activeTransaction.preparedUtc='2025-12-31T23:59:59Z'}
        'existing-terminal' {$observation.terminalFailure=$true}
    }
    $context=[pscustomobject]@{observation=$observation;probeCalls=0}
    $parameters=@{Session=[pscustomobject]@{};TransactionId=('a'*32);PayloadSha256=('b'*64);Action='FreshInstall';Role=$role;PriorGeneration=1;MaxGeneration=3;CandidateProcessId=100;ExpectedDevFleetVersion='1.2.13';ExpectedInstallerVersion='1.4.1';ObservationTimeoutSeconds=10;InvocationStartUtc='2026-01-01T00:00:00Z';ExpectedComputeInstanceName=$compute;RemoteObservationProvider=$remote;GuestMarkerReadProvider=$guest;ObservationAdapterContext=$context}
    if($kind-ceq'Laptop'){$parameters.ExpectedVaultInstanceName='devfleet-vault'}
    $result=& $module {param($p)Get-ProductLifecycleObservation @p} $parameters
    $expectDeferred=$case-in@('desktop-launch','laptop-compute-launch','laptop-vault-launch')
    $pass=if($expectDeferred){$context.probeCalls-eq0-and$result.progress.guestProgressMarkerStatus-ceq'DEFERRED_PRODUCT_LAUNCH'-and-not$result.productRoleIdentityValid}else{$context.probeCalls-eq1-and$result.progress.guestProgressMarkerStatus-ceq'VALID'}
    if($case-in@('wrong-payload','wrong-stage-role','wrong-instance-stage')){$pass=$pass-and@($result.stageMarkerErrors).Count-eq1}
    $checks.Add([pscustomobject]@{case=$case;pass=[bool]$pass;probeCalls=$context.probeCalls;status=$result.progress.guestProgressMarkerStatus})
}
[pscustomobject]@{status=if(@($checks|Where-Object{-not$_.pass}).Count){'FAIL'}else{'PASS'};passed=@($checks|Where-Object{$_.pass}).Count;total=$checks.Count;checks=@($checks);vmOperations=0}|ConvertTo-Json -Depth 5
if(@($checks|Where-Object{-not$_.pass}).Count){exit 1}
