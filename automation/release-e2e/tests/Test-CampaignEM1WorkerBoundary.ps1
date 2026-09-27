[CmdletBinding()]
param([string]$WorkerPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$releaseRoot=Split-Path -Parent $PSScriptRoot
$modulePath=Join-Path $releaseRoot 'modules\MultipassDiagnostic.psm1'
if(-not$WorkerPath){$workerPath=Join-Path $releaseRoot 'Invoke-CampaignEMultipassM1Worker.ps1'}
Import-Module $modulePath -Force -DisableNameChecking
$engine=(Get-Process -Id $PID).Path
$run="astra-worker-$PID-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$fixtureParent=[IO.Path]::GetFullPath("C:\Users\Public\DevFleet-E2E\$run")
$originalPrograms=$env:ProgramFiles;$originalProgramsX86=${env:ProgramFiles(x86)};$originalData=$env:ProgramData
$results=[Collections.Generic.List[object]]::new()
# The actual child script, request validation, sequence and cleanup run unchanged.
# Only native I/O is replaced in a copied module; no VM/daemon or product is invoked.
$nativeFixture=@'
function Invoke-DevFleetBoundedNativeProbe {
    param($Operation,$FilePath,$ArgumentList,$TimeoutSeconds,$OwnerDeadlineUtc,[switch]$ForceLegacyArgumentString,$MaxStdoutCharacters,$MaxStderrCharacters)
    $now=[datetime]::UtcNow
    $caseRoot=Split-Path -Parent $PSScriptRoot
    [IO.File]::AppendAllText((Join-Path $caseRoot 'native-calls.txt'),$Operation+[Environment]::NewLine)
    [IO.File]::WriteAllText((Join-Path $caseRoot 'runtime.txt'),$PSVersionTable.PSVersion.ToString())
    $output='';$code=0
    switch($Operation){
        'baseline-inventory' {$output='{"list":[]}'}
        'final-inventory' {
            $output='{"list":[]}'
            $custom=Join-Path $caseRoot 'final-response.txt';if(Test-Path $custom){$output=Get-Content $custom -Raw}
            if(Test-Path (Join-Path $caseRoot 'throw-inventory')){throw 'fixture inventory provider failed'}
        }
        'delete-owned' {if(Test-Path (Join-Path $caseRoot 'throw-delete')){throw 'fixture delete provider failed'}}
        'info-running' {$output=(@{info=@{([string]$ArgumentList[1])=@{state='Running';ipv4=@('10.0.0.2');image_hash=('a'*64);image_release='24.04'}};errors=@()}|ConvertTo-Json -Depth 5 -Compress)}
        'info-final' {$output=(@{info=@{([string]$ArgumentList[1])=@{state='Running';ipv4=@('10.0.0.2');image_hash=('a'*64);image_release='24.04'}};errors=@()}|ConvertTo-Json -Depth 5 -Compress)}
        'cloud-init' {$output='status: done'}
        'launch' {[IO.File]::WriteAllText((Join-Path $caseRoot 'launch-arguments.json'),($ArgumentList|ConvertTo-Json -Compress));if(Test-Path (Join-Path $caseRoot 'fail-launch')){$code=7}}
    }
    [pscustomobject]@{operation=$Operation;outcome=if($code-eq0){'PASS'}else{'NONZERO'};exitCode=$code;pid=$PID;startedAtUtc=$now.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');deadlineUtc=$OwnerDeadlineUtc.ToUniversalTime().ToString('o');stdout=$output;stderr=if($code){'fixture native failure'}else{''};outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false}
}
Export-ModuleMember -Function Invoke-DevFleetBoundedNativeProbe
function Get-DevFleetCampaignEBackendSnapshot {
    param($InstanceName,$SinceUtc,$OwnerDeadlineUtc)
    $caseRoot=Split-Path -Parent $PSScriptRoot
    [IO.File]::AppendAllText((Join-Path $caseRoot 'backend-calls.txt'),'backend'+[Environment]::NewLine)
    $owned=@();if((Test-Path (Join-Path $caseRoot 'orphan-backend'))-and@(Get-Content (Join-Path $caseRoot 'backend-calls.txt')).Count-ge3){$owned=@(@{name=$InstanceName;state='Running'})}
    [pscustomobject]@{status=if(Test-Path (Join-Path $caseRoot 'fail-backend')){'UNVERIFIED'}else{'COMPLETE'};instanceName=$InstanceName;startedAtUtc=[datetime]::UtcNow.ToString('o');producedAtUtc=[datetime]::UtcNow.ToString('o');data=@{backend=@{status='PASS';foreignCount=0;owned=$owned};events=@()}}
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
