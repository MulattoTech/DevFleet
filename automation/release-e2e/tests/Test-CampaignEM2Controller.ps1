[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$release=Split-Path -Parent $PSScriptRoot;$repo=Split-Path -Parent (Split-Path -Parent $release)
Import-Module (Join-Path $release 'modules/MultipassDiagnostic.psm1') -Force -DisableNameChecking
$prefix='astra-m2-controller-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$scratch=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) $prefix));$guestParents=[Collections.Generic.List[string]]::new();$results=[Collections.Generic.List[object]]::new()
# Execute the unchanged parent. VM/session/process/file-transfer dependencies are
# isolated fixtures. Actual profile and worker entrypoints have separate tests.
$stub=@'
$script:fixtureRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$script:case=Get-Content (Join-Path $script:fixtureRoot 'case.txt') -Raw
$script:vm=[pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';State='Off'}
function Record-Call($Value){[IO.File]::AppendAllText((Join-Path $script:fixtureRoot 'calls.txt'),$Value+[Environment]::NewLine)}
function Get-VM {param($Id) $script:vm}
function Assert-DisposableOwnership {param($Vm,$ExpectedId)}
function Get-VMSnapshot {param($VM)[pscustomobject]@{Name='Fixture-Checkpoint';Id=[guid]'11111111-1111-1111-1111-111111111111';VMId=$script:vm.Id;ParentSnapshotId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'}}
function Get-HostSafetySnapshot {param($Vm,$ExpectedVmStartCostGiB)[pscustomobject]@{startSafe=$true;availableMemoryGiB=30;projectedPostStartAvailableMemoryGiB=16}}
function Get-CandidateFingerprint {param($WorkspaceRoot)[pscustomobject]@{gitCommit=('b'*40);shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64);tar=[pscustomobject]@{sha256=('a'*64)}}}
function git {'fixture-head'}
function Restore-ExactCheckpoint {param($Vm,$Name,[switch]$StartAfterRestore)Record-Call $(if($StartAfterRestore){'restore-start'}else{'restore-final'});$script:vm.State=if($StartAfterRestore){'Running'}else{'Off'};[pscustomobject]@{status='PASS'}}
function Stop-VM {param($VM,[switch]$Force,[switch]$Confirm)Record-Call 'stop';$script:vm.State='Off'}
function Connect-DevFleetGuest {param($VmId)'fixture-session'}
function Remove-PSSession {param($Session)Record-Call 'remove-session'}
function Get-DevFleetNestedL2State {param($Session,$ExpectedName)[pscustomobject]@{status='ABSENT';expectedName=$ExpectedName}}
function Write-EvidenceJson {param($Path,$Value)$Value|ConvertTo-Json -Depth 24|Set-Content -LiteralPath $Path}
function Copy-DevFleetBoundedGuestFile {param($LocalPath,$Session,$RemotePath,$TimeoutSeconds)Copy-Item -LiteralPath $LocalPath -Destination $RemotePath;[pscustomobject]@{status='PASS'}}
function Invoke-DevFleetBoundedGuestCommand {
    param($Session,$TimeoutSeconds,$ScriptBlock,$ArgumentList)
    if($ScriptBlock.ToString()-match'M2 raw collection ownership'){Record-Call 'collect-raw';if($script:case-ceq'raw-failure'){throw 'fixture raw transfer failed'}}
    if($ScriptBlock.ToString()-match'M1 cleanup ownership mismatch'){Record-Call 'delete-staging'}
    & $ScriptBlock @ArgumentList
}
function Invoke-DevFleetBoundedGuestProcess {
    param($Session,$FilePath,$ArgumentList,$OwnerDeadlineUtc)
    $request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$ArgumentList[-1]))|ConvertFrom-Json
    $now=[datetime]::UtcNow
    if([string]$ArgumentList[3]-like'*ProductProfile.ps1'){
        Record-Call 'profile'
        $record=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PRODUCT_PROFILE';status='PASS_PROFILE_ONLY';productLifecycleStarted=$false;runId=$request.runId;vmId=$request.vmId;payloadSha256=$request.payloadSha256;startedAtUtc=$now.AddSeconds(-1).ToString('o');producedAtUtc=$now.ToString('o');ownerDeadlineUtc=$OwnerDeadlineUtc.ToUniversalTime().ToString('o');childRuntime='7.6.5';inputs=$request.inputs;preflightConfigSha256=('f'*64);resources=@{cpus=4;memory='9G';disk='220G'};ubuntuImage='24.04';primaryError=''}
        if($script:case-like'm3-*'){
            if(-not$request.productLaunch-or$request.inputs.Count-ne4-or$request.instanceName-cne("DevFleet-E2E-E-M1-"+$request.runId)){throw 'Fixture detected invalid M3 profile request.'}
            $cloud=Join-Path $request.remoteRoot 'product-cloud-init.yaml';[IO.File]::WriteAllText($cloud,'#cloud-config')
            $record.productLaunch=@{mode='CANDIDATE_CLOUD_INIT_AND_INVOKE_EXTERNAL';cloudInitFileName='product-cloud-init.yaml';cloudInitSha256=(Get-FileHash $cloud -Algorithm SHA256).Hash.ToLowerInvariant();instanceName=$request.instanceName;nodeRole='primary';productTransactionStarted=$false;stageMarkerWritten=$false}
        }
        $record|ConvertTo-Json -Depth 10|Set-Content (Join-Path $request.remoteRoot 'product-profile.json')
    }else{
        Record-Call 'worker'
        $m3=$script:case-like'm3-*';$inputCount=if($m3){4}else{3}
        if(-not$request.PSObject.Properties['productProfileSha256']-or$request.productProfileInputs.Count-ne$inputCount){throw 'Fixture detected missing M2/M3 worker binding.'}
        if($m3-and(-not$request.productLaunch-or$FilePath-cne(Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe')-or$request.expectedWorkerSha256-cne(Get-FileHash $FilePath -Algorithm SHA256).Hash.ToLowerInvariant())){throw 'Fixture detected invalid M3 checkpoint PowerShell request.'}
        if([int64]$request.ownerDeadlineUnixMilliseconds-ne[DateTimeOffset]::new($OwnerDeadlineUtc).ToUnixTimeMilliseconds()){throw 'Fixture detected changed child deadline.'}
        $provider={param($operation,$path,$arguments,$seconds,$deadline)$t=[datetime]::UtcNow;$out=switch($operation){'info-running'{@{info=@{([string]$arguments[1])=@{state='Running';ipv4=@('10.0.0.2')}}}|ConvertTo-Json -Depth 5 -Compress};'info-final'{@{info=@{([string]$arguments[1])=@{state='Running'}}}|ConvertTo-Json -Depth 5 -Compress};'cloud-init'{'status: done'};default{''}};[pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;pid=55;startedAtUtc=$t.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');deadlineUtc=$deadline.ToUniversalTime().ToString('o');outputComplete=$true;stdout=$out;stderr=''}}
        $operationDeadline=[DateTimeOffset]::FromUnixTimeMilliseconds($request.operationDeadlineUnixMilliseconds).UtcDateTime
        $sequence=Invoke-DevFleetCampaignEMultipassM1Sequence -RunId $request.runId -InstanceName $request.instanceName -UbuntuImage $request.ubuntuImage -MultipassPath 'fixture.exe' -OwnerDeadlineUtc $operationDeadline -NativeProbeProvider $provider -Resources @{cpus=4;memory='9G';disk='220G'}
        $record=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_M1_RESULT';status=if($script:case-ceq'worker-failure'){'BLOCKED'}else{'PASS_DIAGNOSTIC'};runId=$request.runId;vmId=$request.vmId;payloadSha256=$request.payloadSha256;instanceName=$request.instanceName;ownerDeadlineUtc=$OwnerDeadlineUtc.ToUniversalTime().ToString('o');producedAtUtc=[datetime]::UtcNow.ToString('o');multipassSha256=('a'*64);boundaryBefore=@{activeTransactionPresent=$false;stageMarkerCount=0};boundaryAfter=@{activeTransactionPresent=$false;stageMarkerCount=0};sequence=$sequence;backendAfterCleanup=@{data=@{backend=@{status='PASS';foreignCount=0;owned=@()}}};cleanup=@{status='ABSENT_VERIFIED';instanceName=$request.instanceName;finalInventoryCount=0};productLifecycleStarted=$false;productProgressClaimed=$false;primaryError=if($script:case-ceq'worker-failure'){'fixture launch failed'}else{''}}
        if($m3){
            $record.experiment='M3';$record.executionContext=@{powerShellVersion=if($script:case-ceq'm3-wrong-runtime'){'5.1'}else{'7.6.5'};is64BitProcess=$true;workerExeSha256=$request.expectedWorkerSha256;candidateCommonSha256=[string]@($request.productProfileInputs|Where-Object{$_.path-ceq'windows/DevFleet.Common.psm1'})[0].sha256;launchImplementation='CANDIDATE_COMMON_INVOKE_EXTERNAL'}
            if($script:case-ceq'm3-missing-cloud'){Remove-Item -LiteralPath (Join-Path $request.remoteRoot 'product-cloud-init.yaml')}
        }
        $record|ConvertTo-Json -Depth 12|Set-Content (Join-Path $request.remoteRoot 'm1-worker-result.json')
        @{status='COMPLETE';instanceName=$request.instanceName}|ConvertTo-Json|Set-Content (Join-Path $request.remoteRoot 'backend-before-cleanup.json')
        foreach($name in @('backend-before.json','backend-after-cleanup.json')){@{status='COMPLETE'}|ConvertTo-Json|Set-Content (Join-Path $request.remoteRoot $name)}
        foreach($operation in @('launch','info-running','ssh-ready','cloud-init','info-final')){foreach($edge in @('start','end')){if($script:case-ceq'missing-operation'-and$operation-ceq'info-final'-and$edge-ceq'end'){continue};@{operation=$operation;edge=$edge}|ConvertTo-Json|Set-Content (Join-Path $request.remoteRoot ($operation+'-'+$edge+'.json'))}}
    }
    [pscustomobject]@{outcome='PASS';exitCode=0;pid=55;startedAtUtc=$now.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');outputComplete=$true;stdout='';stderr=''}
}
Export-ModuleMember -Function *
'@
try{
    New-Item -ItemType Directory -Path $scratch|Out-Null
    foreach($case in @('success','worker-failure','raw-failure','preexisting-run','missing-operation','m3-success','m3-wrong-runtime','m3-missing-cloud')){
        $caseRoot=Join-Path $scratch $case;$run=$prefix+'-'+$case;$guestParent=[IO.Path]::GetFullPath("C:\Users\Public\DevFleet-E2E\$run");$guestParents.Add($guestParent)
        $modules=Join-Path $caseRoot 'automation/release-e2e/modules';New-Item -ItemType Directory -Path $modules,(Join-Path $caseRoot 'outputs'),(Join-Path $caseRoot 'evidence'),(Join-Path $caseRoot 'source/windows'),(Join-Path $caseRoot 'source/config'),(Join-Path $caseRoot 'source/cloud-init')|Out-Null
        [IO.File]::WriteAllText((Join-Path $caseRoot 'case.txt'),$case)
        foreach($name in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic')){[IO.File]::WriteAllText((Join-Path $modules ($name+'.psm1')),$(if($name-ceq'MultipassDiagnostic'){[IO.File]::ReadAllText((Join-Path $release 'modules/MultipassDiagnostic.psm1'))+[Environment]::NewLine+$stub}else{'# Fixture only.'}),[Text.UTF8Encoding]::new($false))}
        foreach($file in @('Invoke-CampaignEProductProfile.ps1','Invoke-CampaignEMultipassM1Worker.ps1')){Copy-Item (Join-Path $release $file) (Join-Path $caseRoot ('automation/release-e2e/'+$file))}
        $inputs=@(foreach($relative in @('windows/00-Preflight.ps1','windows/DevFleet.Common.psm1','config/devfleet.config.json','cloud-init/compute.yaml')){$dest=Join-Path $caseRoot ('source/'+$relative);Copy-Item (Join-Path $repo ('source/'+$relative)) $dest;@{root='source';path=$relative;sha256=(Get-FileHash $dest -Algorithm SHA256).Hash.ToLowerInvariant()}})
        @{shippingInputs=$inputs}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $caseRoot 'outputs/release-fingerprint.json')
        @{candidateIsCurrent=$true;sourceChangedSinceCandidate=$false;rebuildRequired=$false;repositoryHead='fixture-head';shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64)}|ConvertTo-Json|Set-Content (Join-Path $caseRoot 'evidence/CURRENT-RELEASE-AUTHORITY.json')
        $checkpoint=Join-Path $caseRoot 'checkpoint.json';$pwsh=Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe'
        @{status='PASS_CHECKPOINT_READY';campaign='DF-STABLE-20260906-E';plan=@{ubuntuImage='24.04'};diagnosticCheckpoint=@{id='11111111-1111-1111-1111-111111111111';name='Fixture-Checkpoint';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';parentSnapshotId='19865b76-4c3a-44f7-ba39-841e9d3c40c9';l1State='OFF';l2Status='ABSENT';payloadSha256=('a'*64);powershell=@{pathSha256=(Get-FileHash $pwsh -Algorithm SHA256).Hash.ToLowerInvariant()};multipass=@{pathSha256=('a'*64)}}}|ConvertTo-Json -Depth 5|Set-Content $checkpoint
        $recordPath=Join-Path $caseRoot "audit/automation-harness/runs/$run/campaign-e-m1.json"
        if($case-ceq'preexisting-run'){New-Item -ItemType Directory -Path (Split-Path -Parent $recordPath)|Out-Null;[IO.File]::WriteAllText($recordPath,'{"status":"PRESERVED"}');$originalHash=(Get-FileHash $recordPath -Algorithm SHA256).Hash}
        $mode=if($case-like'm3-*'){'-ProductLaunch'}else{'-ProductCapacity'}
        $probe=Invoke-DevFleetBoundedNativeProbe -Operation "controller-$case" -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $release 'Invoke-CampaignEMultipassM1.ps1'),'-WorkspaceRoot',$caseRoot,'-RunId',$run,'-CheckpointEvidencePath',$checkpoint,$mode) -TimeoutSeconds 25 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(30)) -ForceLegacyArgumentString -MaxStdoutCharacters 32768
        $record=Get-Content $recordPath -Raw|ConvertFrom-Json;$calls=@(if(Test-Path (Join-Path $caseRoot 'calls.txt')){Get-Content (Join-Path $caseRoot 'calls.txt')})
        if($case-ceq'preexisting-run'){$results.Add([pscustomobject]@{case=$case;pass=($probe.exitCode-eq1-and$calls.Count-eq0-and(Get-FileHash $recordPath -Algorithm SHA256).Hash-ceq$originalHash);calls=$calls;exitCode=$probe.exitCode;error='Existing run was not adopted.'});continue}
        $expectedExperiment=if($case-like'm3-*'){'M3'}else{'M2'};$rawCount=if($case-like'm3-*'){16}else{15}
        $pass=$record.experiment-ceq$expectedExperiment-and$calls-contains'profile'-and$calls-contains'worker'-and$calls-contains'collect-raw'-and$calls-contains'stop'
        if($case-cin@('raw-failure','missing-operation','m3-missing-cloud')){$pass=$pass-and$probe.exitCode-eq1-and$calls-notcontains'delete-staging'-and(Test-Path (Join-Path $guestParent 'M1/backend-before-cleanup.json'))}
        else{$pass=$pass-and$record.rawEvidence.Count-eq$rawCount-and$calls.IndexOf('collect-raw')-lt$calls.IndexOf('delete-staging')-and$calls.IndexOf('delete-staging')-lt$calls.IndexOf('stop')-and$calls-contains'restore-final';if($case-cin@('success','m3-success')){$pass=$pass-and$probe.exitCode-eq0-and$record.status-ceq'PASS_DIAGNOSTIC'}else{$pass=$pass-and$probe.exitCode-eq1-and$record.status-ceq'BLOCKED'}}
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;calls=$calls;exitCode=$probe.exitCode;error=if($record.PSObject.Properties['primaryError']){$record.primaryError}else{''}})
    }
}finally{
    foreach($path in @($guestParents)+@($scratch)){
        $allowed=$path.StartsWith('C:\Users\Public\DevFleet-E2E\'+$prefix,[StringComparison]::Ordinal)-or$path-ceq$scratch
        if(-not$allowed-or[IO.Path]::GetFileName($path)-notlike($prefix+'*')){throw 'Controller fixture cleanup escaped exact ownership.'}
        if(Test-Path $path){Remove-Item -LiteralPath $path -Recurse -Force}
    }
}
$results|ConvertTo-Json -Depth 4
if(@($results|Where-Object{-not$_.pass}).Count){throw 'M2 actual controller integration regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) M2 actual controller integration checks"
