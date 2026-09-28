# DevFleet source part 039

Full-source UTF-8 byte interval [1767000, 1813500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: b542d555de23be1ded093692d026345867f4833909957f2c9689a6b47c6174a9

<!-- BEGIN SOURCE SLICE -->
time]::UtcNow.ToString('o');data=@{backend=@{status='PASS';foreignCount=0;owned=$owned};events=@()}}
}
Export-ModuleMember -Function Get-DevFleetCampaignEBackendSnapshot
$script:actualCandidateNativeLaunch=${function:Invoke-DevFleetCampaignECandidateNativeLaunch}
function Invoke-DevFleetCampaignECandidateNativeLaunch {
    param($CandidateCommonModule,$FilePath,$ArgumentList,$MaximumSeconds,$OwnerDeadlineUtc)
    # Only the vendor executable transport is substituted. The actual worker
    # dispatch and candidate Common native function run under real PowerShell7.
    $caseRoot=Split-Path -Parent $PSScriptRoot
    [IO.File]::AppendAllText((Join-Path $caseRoot 'native-calls.txt'),'launch'+[Environment]::NewLine)
    $ArgumentList|ConvertTo-Json -Compress|Set-Content (Join-Path $caseRoot 'launch-arguments.json')
    $MaximumSeconds|Set-Content (Join-Path $caseRoot 'requested-maximum.txt')
    $engine=(Get-Process -Id $PID).Path;$case=Split-Path -Leaf $caseRoot
    $maximum=if($case-ceq'm3-timeout'){3}else{$MaximumSeconds}
    & $script:actualCandidateNativeLaunch -CandidateCommonModule $CandidateCommonModule -FilePath $engine -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $caseRoot 'native-probe.ps1'),'-Case',$case) -MaximumSeconds $maximum -OwnerDeadlineUtc $OwnerDeadlineUtc
}
Export-ModuleMember -Function Invoke-DevFleetCampaignECandidateNativeLaunch
'@
try {
    if(Test-Path -LiteralPath $fixtureParent){throw 'Fresh worker fixture already exists.'}
    New-Item -ItemType Directory -Path $fixtureParent | Out-Null
    $programs=Join-Path $fixtureParent 'Programs';$bin=Join-Path $programs 'Multipass\bin'
    New-Item -ItemType Directory -Path $bin | Out-Null
    $fakeMultipass=Join-Path $bin 'multipass.exe'
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination $fakeMultipass
    $fakeHash=(Get-FileHash -LiteralPath $fakeMultipass -Algorithm SHA256).Hash.ToLowerInvariant()
    $env:ProgramFiles=$programs;${env:ProgramFiles(x86)}=$programs;$env:ProgramData=Join-Path $fixtureParent 'ProgramData'
    # PowerShell initializes ProgramFiles at startup; isolate external filesystem
    # discovery inside the actual child runtime, before entering the real worker.
    $entryFixture=Join-Path $fixtureParent 'enter-worker.ps1'
    $entryText=@'
param([string]$Programs,[string]$Data,[string]$Worker,[string]$Request)
$ErrorActionPreference='Stop'
$env:ProgramFiles=$Programs;${env:ProgramFiles(x86)}=$Programs;$env:ProgramData=$Data
& $Worker -RequestBase64 $Request
exit $LASTEXITCODE
'@
    [IO.File]::WriteAllText($entryFixture,$entryText,[Text.UTF8Encoding]::new($false))
    $cases=@('success','native-failure','missing-module','failed-import','expired-owner','null-list','missing-list','scalar-list','bad-json','bad-row','throw-delete','throw-inventory','m2-success','m2-profile-tampered','m2-backend-failed','m2-orphan-backend')
    if($PSVersionTable.PSVersion.Major-ge7){$cases+=@('m3-success','m3-native-failure','m3-timeout','m3-cloud-tampered','m3-common-tampered','m3-runtime-tampered')}
    foreach($case in $cases){
        $caseRoot=Join-Path $fixtureParent $case;$remoteRoot=Join-Path $caseRoot 'M1'
        New-Item -ItemType Directory -Path $remoteRoot | Out-Null
        $fixtureModule=Join-Path $remoteRoot 'MultipassDiagnostic.psm1'
        if($case-eq'failed-import'){
            [IO.File]::WriteAllText($fixtureModule,"throw 'fixture module unavailable token=fixture-private-value'",[Text.UTF8Encoding]::new($false))
        }elseif($case-ne'missing-module'){
            [IO.File]::WriteAllText($fixtureModule,([IO.File]::ReadAllText($modulePath)+[Environment]::NewLine+$nativeFixture),[Text.UTF8Encoding]::new($false))
        }
        if($case-eq'native-failure'){[IO.File]::WriteAllText((Join-Path $caseRoot 'fail-launch'),'fixture')}
        $responses=@{'null-list'='{"list":null}';'missing-list'='{}';'scalar-list'='{"list":false}';'bad-json'='{"list":[';'bad-row'='{"list":[null]}'}
        if($responses.ContainsKey($case)){[IO.File]::WriteAllText((Join-Path $caseRoot 'final-response.txt'),$responses[$case])}
        if($case-like'throw-*'){[IO.File]::WriteAllText((Join-Path $caseRoot $case),'fixture')}
        $caseRun="$run-$case";$name="DevFleet-E2E-E-M1-$caseRun"
        $owner=[datetime]::UtcNow.AddSeconds(25);$operation=$owner.AddSeconds(-5)
        if($case-like'm3-*'){$owner=[datetime]::UtcNow.AddSeconds(1230);$operation=$owner.AddSeconds(-30)}
        if($case-eq'expired-owner'){$owner=[datetime]::UtcNow.AddSeconds(-1);$operation=$owner.AddSeconds(-5)}
        $request=[ordered]@{runId=$caseRun;vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);instanceName=$name;remoteRoot=$remoteRoot;modulePath=$fixtureModule;ubuntuImage='24.04';expectedMultipassSha256=$fakeHash;ownerDeadlineUnixMilliseconds=[DateTimeOffset]::new($owner).ToUnixTimeMilliseconds();operationDeadlineUnixMilliseconds=[DateTimeOffset]::new($operation).ToUnixTimeMilliseconds()}
        $expectedResources=@{cpus=2;memory='2G';disk='10G'}
        if($case-like'm2-*'-or$case-like'm3-*'){
            $expectedResources=@{cpus=4;memory='9G';disk='220G'};$profileInputs=@(@{path='windows/00-Preflight.ps1';sha256=('b'*64)},@{path='windows/DevFleet.Common.psm1';sha256=('c'*64)},@{path='config/devfleet.config.json';sha256=('d'*64)})
            $profile=@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PRODUCT_PROFILE';status='PASS_PROFILE_ONLY';runId=$caseRun;vmId=$request.vmId;payloadSha256=$request.payloadSha256;productLifecycleStarted=$false;startedAtUtc=[datetime]::UtcNow.AddSeconds(-3).ToString('o');producedAtUtc=[datetime]::UtcNow.AddSeconds(-2).ToString('o');ownerDeadlineUtc=[datetime]::UtcNow.AddSeconds(-1).ToString('o');childRuntime='7.6.5';preflightConfigSha256=('e'*64);inputs=$profileInputs;resources=$expectedResources;ubuntuImage='24.04'}
            if($case-like'm3-*'){
                $repo=Split-Path -Parent (Split-Path -Parent $releaseRoot)
                New-Item -ItemType Directory -Path (Join-Path $remoteRoot 'profile-package/windows')|Out-Null
                $common=Join-Path $remoteRoot 'profile-package/windows/DevFleet.Common.psm1';Copy-Item (Join-Path $repo 'source/windows/DevFleet.Common.psm1') $common
                $profileInputs[1].sha256=(Get-FileHash $common -Algorithm SHA256).Hash.ToLowerInvariant();$profileInputs+=@{path='cloud-init/compute.yaml';sha256=('f'*64)};$profile.inputs=$profileInputs
                $cloud=Join-Path $remoteRoot 'product-cloud-init.yaml';[IO.File]::WriteAllText($cloud,"#cloud-config`nhostname: '$name'`n")
                $profile.productLaunch=@{mode='CANDIDATE_CLOUD_INIT_AND_INVOKE_EXTERNAL';cloudInitFileName='product-cloud-init.yaml';cloudInitSha256=(Get-FileHash $cloud -Algorithm SHA256).Hash.ToLowerInvariant();instanceName=$name;nodeRole='primary';productTransactionStarted=$false;stageMarkerWritten=$false}
                $request.productLaunch=$true;$request.expectedWorkerSha256=(Get-FileHash $engine -Algorithm SHA256).Hash.ToLowerInvariant()
                if($case-ceq'm3-runtime-tampered'){$request.expectedWorkerSha256='f'*64}
                if($case-ceq'm3-cloud-tampered'){[IO.File]::AppendAllText($cloud,'# fixture tamper')}
                if($case-ceq'm3-common-tampered'){[IO.File]::AppendAllText($common,"`n# fixture tamper")}
                @'
param($Case)
if($Case-ceq'm3-native-failure'){[Console]::Error.Write('fixture candidate native failure');exit 7}
if($Case-ceq'm3-timeout'){Start-Sleep 20}
[Console]::Out.Write('candidate-native-child-returned')
'@|Set-Content (Join-Path $caseRoot 'native-probe.ps1') -Encoding utf8
            }
            $profilePath=Join-Path $remoteRoot 'product-profile.json';$profile|ConvertTo-Json -Depth 6|Set-Content $profilePath
            $request.productProfileSha256=(Get-FileHash $profilePath -Algorithm SHA256).Hash.ToLowerInvariant();$request.productProfileInputs=$profileInputs
            if($case-ceq'm2-profile-tampered'){$request.productProfileSha256='f'*64}
            if($case-ceq'm2-backend-failed'){[IO.File]::WriteAllText((Join-Path $caseRoot 'fail-backend'),'fixture')}
            if($case-ceq'm2-orphan-backend'){[IO.File]::WriteAllText((Join-Path $caseRoot 'orphan-backend'),'fixture')}
        }
        $base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json -Depth 8 -Compress)))
        $probe=Invoke-DevFleetBoundedNativeProbe -Operation "worker-$case" -FilePath $engine -ArgumentList @('-NoProfile','-NonInteractive','-File',$entryFixture,'-Programs',$programs,'-Data',$env:ProgramData,'-Worker',$workerPath,'-Request',$base64) -TimeoutSeconds 15 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(20)) -ForceLegacyArgumentString -MaxStdoutCharacters 32768
        $durablePath=Join-Path $remoteRoot 'm1-worker-result.json';$durable=$null
        if(Test-Path -LiteralPath $durablePath){$durable=Get-Content -LiteralPath $durablePath -Raw|ConvertFrom-Json}
        $passed=($null-ne$durable-and[string]$durable.runId-ceq$caseRun-and[string]$durable.vmId-ceq$request.vmId-and[string]$durable.payloadSha256-ceq$request.payloadSha256-and-not[bool]$durable.productLifecycleStarted-and-not[bool]$durable.productProgressClaimed)
        $callsPath=Join-Path $caseRoot 'native-calls.txt';$calls=@(if(Test-Path $callsPath){Get-Content $callsPath})
        if($case-cin@('success','m2-success','m3-success')){
            $passed=$passed-and$probe.exitCode-eq0-and[string]$durable.status-ceq'PASS_DIAGNOSTIC'
            $validationError='';if($passed){try{Assert-DevFleetCampaignEM1Result -Result $durable -ExpectedRunId $caseRun -ExpectedVmId ([guid]$request.vmId) -ExpectedInstanceName $name -ExpectedPayloadSha256 $request.payloadSha256 -ExpectedResources $expectedResources|Out-Null}catch{$passed=$false;$validationError=$_.Exception.Message}}
            $runtimePath=Join-Path $caseRoot 'runtime.txt'
            $passed=$passed-and(Test-Path $runtimePath)-and((Get-Content $runtimePath -Raw)-ceq$PSVersionTable.PSVersion.ToString())-and(($calls-join'|')-ceq'baseline-inventory|launch|info-running|ssh-ready|cloud-init|info-final|delete-owned|final-inventory')
            $launchArgs=@();if(Test-Path (Join-Path $caseRoot 'launch-arguments.json')){$launchArgs=Get-Content (Join-Path $caseRoot 'launch-arguments.json') -Raw|ConvertFrom-Json}
            $expectedArguments="launch|24.04|--name|$name|--cpus|$($expectedResources.cpus)|--memory|$($expectedResources.memory)|--disk|$($expectedResources.disk)";if($case-ceq'm3-success'){$expectedArguments+='|--cloud-init|'+$cloud}
            $passed=$passed-and($launchArgs-join'|')-ceq$expectedArguments
            if($case-ceq'm3-success'){
                $launchRecord=Get-Content (Join-Path $remoteRoot 'launch-end.json') -Raw|ConvertFrom-Json
                $passed=$passed-and$durable.experiment-ceq'M3'-and$durable.executionContext.candidateCommonSha256-ceq$profileInputs[1].sha256-and$durable.executionContext.workerExeSha256-ceq$request.expectedWorkerSha256-and$launchRecord.adapter-ceq'CANDIDATE_COMMON_INVOKE_EXTERNAL'-and$launchRecord.stdout-ceq'candidate-native-child-returned'-and$null-eq$launchRecord.pid-and[int](Get-Content (Join-Path $caseRoot 'requested-maximum.txt') -Raw)-eq900
                if(-not$passed){[pscustomobject]@{validation=$validationError;arguments=$launchArgs;expectedArguments=$expectedArguments;context=$durable.executionContext;launch=$launchRecord;expectedCommon=$profileInputs[1].sha256;expectedRuntime=$request.expectedWorkerSha256}|ConvertTo-Json -Depth 5|Write-Host}
            }
            if($case-ceq'm2-success'){$infoRecord=Get-Content (Join-Path $remoteRoot 'info-running-end.json') -Raw|ConvertFrom-Json;$passed=$passed-and$infoRecord.stdout-match'image_hash';if($validationError){Write-Host ('M2 validation: '+$validationError)};$passed=$passed-and$durable.experiment-ceq'M2'-and(Test-Path (Join-Path $remoteRoot 'launch-start.json'))-and(Test-Path (Join-Path $remoteRoot 'backend-before-cleanup.json'))}
        }elseif($case-like'm3-*'){
            $passed=$passed-and$probe.exitCode-eq1-and$durable.status-ceq'BLOCKED'
            if($case-cin@('m3-native-failure','m3-timeout')){
                $launchRecord=Get-Content (Join-Path $remoteRoot 'launch-end.json') -Raw|ConvertFrom-Json
                $expectedOutcome=if($case-ceq'm3-timeout'){'TIMEOUT'}else{'COMMAND_FAILED'}
                $passed=$passed-and$launchRecord.outcome-ceq$expectedOutcome-and$launchRecord.adapter-ceq'CANDIDATE_COMMON_INVOKE_EXTERNAL'-and$durable.cleanup.status-ceq'ABSENT_VERIFIED'-and($calls-join'|')-ceq'baseline-inventory|launch|delete-owned|final-inventory'-and(Test-Path (Join-Path $remoteRoot 'backend-before-cleanup.json'))
            }else{$passed=$passed-and$calls.Count-eq0-and$durable.primaryError-match'hash mismatch|hash differs'}
        }elseif($case-eq'native-failure'){
            $passed=$passed-and$probe.exitCode-eq1-and[string]$durable.status-ceq'BLOCKED'-and[string]$durable.primaryError-match'launch returned NONZERO'-and[string]$durable.cleanup.instanceName-ceq$name-and(($calls-join'|')-ceq'baseline-inventory|launch|delete-owned|final-inventory')
        }elseif($case-ceq'm2-orphan-backend'){
            $passed=$passed-and$probe.exitCode-eq1-and$durable.status-ceq'BLOCKED'-and$durable.cleanup.status-ceq'UNVERIFIED'-and$durable.primaryError-match'final independent backend'-and(Test-Path (Join-Path $remoteRoot 'backend-after-cleanup.json'))
        }elseif($case-like'm2-*'){
            $passed=$passed-and$probe.exitCode-eq1-and[string]$durable.status-ceq'BLOCKED'-and($calls-notcontains'launch')
            if($case-ceq'm2-profile-tampered'){$passed=$passed-and$durable.primaryError-match'profile hash mismatch'-and$calls.Count-eq0}else{$passed=$passed-and$durable.primaryError-match'empty backend baseline'-and(Test-Path (Join-Path $remoteRoot 'backend-before-cleanup.json'))}
        }elseif($responses.ContainsKey($case)-or$case-like'throw-*'){
            $passed=$passed-and$probe.exitCode-eq1-and[string]$durable.status-ceq'BLOCKED'-and-not[string]::IsNullOrWhiteSpace([string]$durable.primaryError)-and($calls-contains'final-inventory')
            if($case-eq'throw-delete'){$passed=$passed-and[string]$durable.cleanup.status-ceq'ABSENT_VERIFIED'-and[string]$durable.cleanup.delete.outcome-ceq'UNVERIFIED'}else{$passed=$passed-and[string]$durable.cleanup.status-ceq'UNVERIFIED'}
        }else{
            $expected=if($case-eq'missing-module'){'module|Module'}elseif($case-eq'failed-import'){'fixture module unavailable'}else{'deadline partition'}
            $passed=$passed-and$probe.exitCode-eq1-and[string]$durable.status-ceq'BLOCKED'-and[string]$durable.primaryError-match$expected-and[string]$durable.primaryError-notmatch'fixture-private-value|ConvertTo-DevFleetDiagnosticSafeText'-and$calls.Count-eq0
        }
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$passed;childRuntime=$PSVersionTable.PSVersion.ToString();exitCode=$probe.exitCode;durablePresent=($null-ne$durable);primaryErrorPresent=($null-ne$durable-and-not[string]::IsNullOrWhiteSpace([string]$durable.primaryError));primaryError=if($durable){ConvertTo-DevFleetDiagnosticSafeText $durable.primaryError}else{''};nativeCalls=$calls.Count})
    }
} finally {
    $env:ProgramFiles=$originalPrograms;${env:ProgramFiles(x86)}=$originalProgramsX86;$env:ProgramData=$originalData
    $fence=[IO.Path]::GetFullPath('C:\Users\Public\DevFleet-E2E\')
    if(-not$fixtureParent.StartsWith($fence,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup escaped exact parent.'}
    if(Test-Path -LiteralPath $fixtureParent){Remove-Item -LiteralPath $fixtureParent -Recurse -Force}
}
$results|ConvertTo-Json -Depth 3
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Campaign E M1 actual-worker boundary regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) Campaign E M1 actual-worker boundary checks ($($PSVersionTable.PSVersion))"

```


## FILE: automation/release-e2e/tests/Test-CampaignEM2Controller.ps1

SHA256: f70b5a3f75c8ae53e8188abf55859f009271e7d1818ab7bf9b75cdb8f2e23d33 | Bytes: 14938 | Git mode: 100644

```
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

```


## FILE: automation/release-e2e/tests/Test-CampaignEM4Controller.ps1

SHA256: 562e1d41db54602f71f4320e1344bbe8effaef964daec918ce084e882c0e7a9e | Bytes: 13375 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$release=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $release 'modules/MultipassDiagnostic.psm1') -Force -DisableNameChecking
$prefix='astra-m4-parent-'+[guid]::NewGuid().ToString('N').Substring(0,8);$scratch=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) $prefix))
$owned=[Collections.Generic.List[string]]::new();$results=[Collections.Generic.List[object]]::new()
# Actual controller and real bounded lifecycle child job. Only VM/remoting,
# artifact inventory, and the external signed-product endpoint are fixtures.
$fixture=@'
$script:fixtureRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$script:case=(Get-Content (Join-Path $script:fixtureRoot 'case.txt') -Raw).Trim()
$script:vm=[pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';State=if($script:case-ceq'already-running'){'Running'}else{'Off'}}
$script:restores=0;$script:captures=0
function Record($Value){[IO.File]::AppendAllText((Join-Path $script:fixtureRoot 'calls.txt'),$Value+[Environment]::NewLine)}
function Get-VM {param($Id) $script:vm}
function Assert-DisposableOwnership {param($Vm,$ExpectedId)}
function Get-VMSnapshot {param($VM)[pscustomobject]@{Name='Fixture-Prerequisite';Id=[guid]'11111111-1111-1111-1111-111111111111';VMId=$script:vm.Id;ParentSnapshotId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'}}
function Get-CandidateFingerprint {param($WorkspaceRoot)[pscustomobject]@{gitCommit=('b'*40);shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64);tar=@{sha256=('a'*64)}}}
function git {'fixture-head'}
function Get-HostSafetySnapshot {param($Vm,$ExpectedVmStartCostGiB)[pscustomobject]@{startSafe=($script:case-cne'unsafe');availableMemoryGiB=30;projectedPostStartAvailableMemoryGiB=16}}
function Restore-ExactCheckpoint {param($Vm,$Name,[switch]$StartAfterRestore)$script:restores++;Record ('restore-'+$script:restores);$script:vm.State='Running';[pscustomobject]@{restored=$true;id='11111111-1111-1111-1111-111111111111'}}
function Stop-VM {param($VM,[switch]$Force,[switch]$Confirm)Record 'stop';$script:vm.State='Off'}
function Ensure-FullReleaseInteractiveDesktop {param($VmId)Record 'interactive';[pscustomobject]@{status='PASS';mode='fixture'}}
function Connect-DevFleetGuest {param($VmId)'fixture-session'}
function Remove-PSSession {param($Session)}
function Get-DevFleetNestedL2State {param($Session,$ExpectedName)[pscustomobject]@{status='ABSENT';inventoryCount=0}}
function Write-EvidenceJson {param($Path,$Value)$Value|ConvertTo-Json -Depth 24|Set-Content -LiteralPath $Path}
function Copy-DevFleetBoundedGuestFile {
    param($LocalPath,$Session,$RemotePath,$TimeoutSeconds)
    Copy-Item -LiteralPath $LocalPath -Destination $RemotePath
    if($script:case-ceq'collector-module-hash'){Add-Content $RemotePath '# fixture altered bytes'}
    if($script:case-ceq'collector-nonce'){$path=Join-Path (Split-Path -Parent $RemotePath) '.owner.json';$owner=Get-Content $path -Raw|ConvertFrom-Json;$owner.nonce='wrong-owner';$owner|ConvertTo-Json|Set-Content $path}
    [pscustomobject]@{status='PASS'}
}
function Invoke-DevFleetBoundedGuestProcess {
    param($Session,$FilePath,$ArgumentList,$OwnerDeadlineUtc)
    $script:captures++;Record ('snapshot-'+$script:captures)
    if($script:captures-eq2-and$script:case-ceq'terminal-transport'){throw 'fixture terminal transport unavailable'}
    $encoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]));$requestText=[regex]::Match($encoded,"\} '([A-Za-z0-9+/=]+)'$").Groups[1].Value
    $request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($requestText))|ConvertFrom-Json
    @{case=$script:case;capture=$script:captures}|ConvertTo-Json|Set-Content (Join-Path $request.path '.fixture.json')
    $json=@{filePath=$FilePath;arguments=@($ArgumentList);deadlineUnixMilliseconds=[DateTimeOffset]::new($OwnerDeadlineUtc).ToUnixTimeMilliseconds()}|ConvertTo-Json -Compress
    & (Get-DevFleetBoundedProcessScriptBlock) $json
}
function Invoke-DevFleetBoundedGuestCommand {
    param($Session,$TimeoutSeconds,$ScriptBlock,$ArgumentList)
    if($ScriptBlock.ToString()-match"ids=@"){
        Record 'final-backend';return [pscustomobject]@{status='COMPLETE';count=if($script:case-ceq'final-orphan'){1}else{0};ids=@()}
    }
    $prior=$env:ProgramData;try{$env:ProgramData=Join-Path $script:fixtureRoot 'isolated-data';&$ScriptBlock @ArgumentList}finally{$env:ProgramData=$prior}
}
Export-ModuleMember -Function *
'@
$collectorFixture=@'
function Get-DevFleetCampaignEBackendSnapshot {
    param($InstanceName,$SinceUtc,$OwnerDeadlineUtc,$TimeoutSeconds,[switch]$ProductContext,$ExpectedPayloadSha256)
    if($InstanceName-cne'devfleet-primary'-or-not$ProductContext-or$ExpectedPayloadSha256-cne('a'*64)){throw 'M4 collector product binding failed.'}
    $fixture=Get-Content (Join-Path $PSScriptRoot '.fixture.json') -Raw|ConvertFrom-Json
    $backend=if($fixture.capture-eq2-and$fixture.case-ceq'terminal-backend'){'UNVERIFIED'}else{'PASS'}
    [pscustomobject]@{status=if($fixture.case-ceq'baseline-partial'-or($fixture.capture-eq2-and$fixture.case-ceq'terminal-partial')){'PARTIAL'}else{'COMPLETE'};data=@{backend=@{status=$backend;foreignCount=if($fixture.capture-eq2-and$fixture.case-ceq'foreign-terminal'){1}else{0};owned=@()};product=@{status='TRANSACTION_OBSERVED'}}}
}
Export-ModuleMember -Function *
'@
$productFixture=@'
function Invoke-ProductFreshInstallLifecycle {
    param($Context,$Role)
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
    if($Context.phaseId-cne'CAMPAIGN-E-M4'-or$Role-cne'Primary / Desktop'-or$Context.vmId-cne'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'-or-not$Context.diagnosticOnly-or$Context.certificationEligible){throw 'M4 product context identity/diagnostic boundary failed.'}
    foreach($name in $Context.PSObject.Properties.Name){if($name-match'Provider|synthetic'){throw 'M4 supplied a forbidden product seam.'}}
    [IO.File]::AppendAllText((Join-Path $root 'calls.txt'),'actual-child-entry'+[Environment]::NewLine)
    $case=(Get-Content (Join-Path $root 'case.txt') -Raw).Trim()
    $result=[ordered]@{status=if($case-ceq'product-failure'){'TERMINAL_FAILURE'}else{'REAL E2E PASS'};completionVerified=($case-cne'product-failure');transactionId=('f'*32);payloadSha256=('a'*64);evidencePath='fixture-native-evidence.json'}
    if($case-ceq'product-failure'){$result.error='fixture launch failed token=private-fixture'}
    [pscustomobject]$result
}
Export-ModuleMember -Function Invoke-ProductFreshInstallLifecycle
'@
try{
    New-Item -ItemType Directory -Path $scratch|Out-Null
    foreach($case in @('success','product-failure','terminal-backend','terminal-transport','already-running','unsafe','final-orphan','preexisting-run','collector-module-hash','collector-executable-hash','collector-nonce','foreign-terminal','baseline-partial','terminal-partial')){
        $caseRoot=Join-Path $scratch $case;$run=$prefix+'-'+$case;$guest=[IO.Path]::GetFullPath("C:\Users\Public\DevFleet-E2E\$run");$owned.Add($guest)
        $modules=Join-Path $caseRoot 'automation/release-e2e/modules';New-Item -ItemType Directory -Path $modules,(Join-Path $modules 'executors'),(Join-Path $caseRoot 'evidence'),(Join-Path $caseRoot 'automation/release-e2e/config')|Out-Null
        [IO.File]::WriteAllText((Join-Path $caseRoot 'case.txt'),$case)
        foreach($name in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic','HarnessBudget')){
            $body=if($name-ceq'HarnessBudget'){[IO.File]::ReadAllText((Join-Path $release 'modules/HarnessBudget.psm1'))+[Environment]::NewLine+$fixture}elseif($name-ceq'MultipassDiagnostic'){[IO.File]::ReadAllText((Join-Path $release 'modules/MultipassDiagnostic.psm1'))+[Environment]::NewLine+$collectorFixture}else{'# Fixture only'}
            [IO.File]::WriteAllText((Join-Path $modules ($name+'.psm1')),$body,[Text.UTF8Encoding]::new($false))
        }
        [IO.File]::WriteAllText((Join-Path $modules 'executors/Invoke-RealProductPhase.psm1'),$productFixture,[Text.UTF8Encoding]::new($false))
        Copy-Item (Join-Path $release 'config/devfleet-e2e.defaults.json') (Join-Path $caseRoot 'automation/release-e2e/config/devfleet-e2e.defaults.json')
        @{candidateIsCurrent=$true;sourceChangedSinceCandidate=$false;rebuildRequired=$false;repositoryHead='fixture-head';shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64)}|ConvertTo-Json|Set-Content (Join-Path $caseRoot 'evidence/CURRENT-RELEASE-AUTHORITY.json')
        $checkpoint=Join-Path $caseRoot 'checkpoint.json';@{status='PASS_CHECKPOINT_READY';campaign='DF-STABLE-20260906-E';diagnosticCheckpoint=@{id='11111111-1111-1111-1111-111111111111';name='Fixture-Prerequisite';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';parentSnapshotId='19865b76-4c3a-44f7-ba39-841e9d3c40c9';payloadSha256=('a'*64);powershell=@{pathSha256=(Get-FileHash (Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe') -Algorithm SHA256).Hash.ToLowerInvariant()};l1State='OFF';l2Status='ABSENT'}}|ConvertTo-Json -Depth 5|Set-Content $checkpoint
        if($case-ceq'collector-executable-hash'){$record=Get-Content $checkpoint -Raw|ConvertFrom-Json;$record.diagnosticCheckpoint.powershell.pathSha256='0'*64;$record|ConvertTo-Json -Depth 5|Set-Content $checkpoint}
        $recordPath=Join-Path $caseRoot "audit/automation-harness/runs/$run/campaign-e-m4.json"
        if($case-ceq'preexisting-run'){New-Item -ItemType Directory -Path (Split-Path -Parent $recordPath)|Out-Null;[IO.File]::WriteAllText($recordPath,'{"preserved":true}');$priorHash=(Get-FileHash $recordPath -Algorithm SHA256).Hash}
        $probe=Invoke-DevFleetBoundedNativeProbe -Operation $case -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $release 'Invoke-CampaignEProductM4.ps1'),'-WorkspaceRoot',$caseRoot,'-RunId',$run,'-CheckpointEvidencePath',$checkpoint) -TimeoutSeconds 18 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(22)) -ForceLegacyArgumentString -MaxStdoutCharacters 32768
        $record=Get-Content $recordPath -Raw|ConvertFrom-Json;$calls=@(if(Test-Path (Join-Path $caseRoot 'calls.txt')){Get-Content (Join-Path $caseRoot 'calls.txt')})
        if($case-ceq'preexisting-run'){$pass=$probe.exitCode-eq1-and$calls.Count-eq0-and(Get-FileHash $recordPath -Algorithm SHA256).Hash-ceq$priorHash}
        elseif($case-cin@('already-running','unsafe')){$pass=$probe.exitCode-eq1-and$calls.Count-eq0-and-not$record.cleanup.acquired-and$record.finalL1.state-ceq$(if($case-ceq'already-running'){'Running'}else{'Off'})}
        elseif($case-like'collector-*'){
            $first=Get-Content (Join-Path (Split-Path -Parent $recordPath) 'snapshot-0001-before-product.json') -Raw|ConvertFrom-Json
            $pass=$probe.exitCode-eq1-and$calls-notcontains'actual-child-entry'-and$calls-notcontains'restore-2'-and$calls-contains'stop'-and$record.finalL1.state-ceq'Off'-and$first.status-ceq'UNAVAILABLE'-and$first.error-match'mismatch'-and(Test-Path (Join-Path $guest 'M4/.owner.json'))
        }
        elseif($case-ceq'baseline-partial'){$pass=$probe.exitCode-eq1-and$calls-notcontains'actual-child-entry'-and$calls-notcontains'restore-2'-and$record.finalL1.state-ceq'Off'}
        else{
            $pass=$record.experiment-ceq'M4'-and-not$record.proofCredit-and-not$record.certificationEligible-and$calls-contains'actual-child-entry'-and$calls-contains'stop'-and$record.finalL1.state-ceq'Off'
            if($case-cin@('terminal-backend','terminal-transport','foreign-terminal','terminal-partial')){$pass=$pass-and$probe.exitCode-eq1-and$calls-notcontains'restore-2'-and(Test-Path (Join-Path $guest 'M4/.owner.json'))}
            else{$pass=$pass-and$calls.IndexOf('snapshot-2')-lt$calls.IndexOf('restore-2')-and$calls-contains'final-backend';if($case-ceq'success'){$pass=$pass-and$probe.exitCode-eq0-and$record.status-ceq'PASS_DIAGNOSTIC'}else{$pass=$pass-and$probe.exitCode-eq1-and$record.status-ceq'BLOCKED'}}
            $pass=$pass-and($record|ConvertTo-Json -Depth 12)-notmatch'private-fixture'
            $first=Get-Content (Join-Path (Split-Path -Parent $recordPath) 'snapshot-0001-before-product.json') -Raw|ConvertFrom-Json
            $pass=$pass-and$first.delivery.persistentPolicyUnchanged-and$first.delivery.processOnlyExecutionPolicy-ceq'Bypass'-and$first.delivery.powerShellVersion-like'7.*'
        }
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;exitCode=$probe.exitCode;calls=$calls;error=if($record.PSObject.Properties['primaryError']){$record.primaryError}else{''};stderr=$probe.stderr})
    }
}finally{
    foreach($path in @($owned)+@($scratch)){if(($path-cne$scratch-and-not$path.StartsWith('C:\Users\Public\DevFleet-E2E\'+$prefix,[StringComparison]::Ordinal))-or[IO.Path]::GetFileName($path)-notlike($prefix+'*')){throw 'M4 fixture cleanup escaped exact ownership.'};if(Test-Path $path){Remove-Item -LiteralPath $path -Recurse -Force}}
}
$results|ConvertTo-Json -Depth 5
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Actual M4 controller regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) actual M4 controller checks"

```


## FILE: automation/release-e2e/tests/Test-CampaignEPrerequisiteCheckpoint.ps1

SHA256: e7b6a7464791af8b7a6a7e445d78ac75d115df1c1d5cd1eadadd6122678b91d7 | Bytes: 49199 | Git mode: 100644

```
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$modulePath=Join-Path $root 'automation\release-e2e\modules\MultipassDiagnostic.psm1'
Import-Module $modulePath -Force
$count=0
function Check([bool]$Condition,[string]$Message){if(-not$Condition){throw "FAIL: $Message"};$script:count++}
function Rejected([scriptblock]$Action,[string]$Message){$failed=$false;try{&$Action|Out-Null}catch{$failed=$true};Check $failed $Message}
function Clone($Value){$Value|ConvertTo-Json -Depth 24|ConvertFrom-Json}

$plan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot (Join-Path $root 'source') -Role Desktop
Check ([string]$plan.packageVersion-ceq'1.2.13') 'candidate package version was not selected'
Check (@($plan.dependencyIds).Count-eq2-and@($plan.dependencyIds)-ccontains'powershell7'-and@($plan.dependencyIds)-ccontains'multipass') 'plan did not remain scoped to PowerShell 7 and Multipass'
Check ([string]$plan.expectedBackend-ceq'hyperv'-and-not[bool]$plan.privilegedMounts) 'plan weakened the candidate backend/mount policy'
Check (@($plan.candidateInstanceNames).Count-eq3) 'plan did not preserve candidate product identities'
Check (@($plan.dependencies.powershell7.allowedSignerSubjectsExact).Count-eq1-and[string]$plan.dependencies.powershell7.allowedSignerSubjectsExact[0]-ceq'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US') 'plan did not preserve the candidate exact PowerShell signer policy'
$policyProjection=Get-DevFleetSystemExecutionPolicyProjection -PolicyProvider {param($scope)"policy-$s