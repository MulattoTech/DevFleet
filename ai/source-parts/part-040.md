# DevFleet source part 040

Full-source UTF-8 byte interval [1813500, 1860000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 28b52db3b70f303ed5c2003b44ce9b1d1e967be35c376f1f849fdba475157345

<!-- BEGIN SOURCE SLICE -->
res++;Record ('snapshot-'+$script:captures)
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
$policyProjection=Get-DevFleetSystemExecutionPolicyProjection -PolicyProvider {param($scope)"policy-$scope"}
Check ([string]$policyProjection.MachinePolicy-ceq'policy-MachinePolicy'-and[string]$policyProjection.CurrentUser-ceq'policy-CurrentUser') 'execution-policy evidence read array-shaped policy output incorrectly'
$owner=[datetime]'2026-09-06T20:40:00Z';$clock=[datetime]'2026-09-06T20:00:00Z'
$partition=Get-DevFleetCampaignEDeadlinePartition -OwnerDeadlineUtc $owner -ReservedTerminalizationSeconds 300 -ClockProvider {$clock}
Check ((([datetime]$partition.childDeadlineUtc).ToUniversalTime()-eq$owner.ToUniversalTime().AddSeconds(-300))-and([int]$partition.childRemainingSeconds-eq2100)) 'deadline partition did not reserve terminalization from the immutable owner'
Rejected {Get-DevFleetCampaignEDeadlinePartition -OwnerDeadlineUtc $owner -ReservedTerminalizationSeconds 300 -ClockProvider {$owner.AddSeconds(-299)}} 'deadline partition granted a fresh child allowance after terminalization reserve exhaustion'
$ownerRecord=[pscustomobject]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_STAGING_OWNER';runId='unit-prereq';nonce='11111111-1111-1111-1111-111111111111'}
Check (Assert-DevFleetCampaignEStagingOwnership -Record $ownerRecord -ExpectedRunId 'unit-prereq' -ExpectedNonce ([guid]'11111111-1111-1111-1111-111111111111')) 'valid staging ownership record was rejected'
$wrongOwner=Clone $ownerRecord;$wrongOwner.nonce='22222222-2222-2222-2222-222222222222'
Rejected {Assert-DevFleetCampaignEStagingOwnership -Record $wrongOwner -ExpectedRunId 'unit-prereq' -ExpectedNonce ([guid]'11111111-1111-1111-1111-111111111111')} 'wrong staging ownership nonce was accepted'
$durableWorker=[ordered]@{kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY';runId='unit-prereq';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);status='PASS'}|ConvertTo-Json -Compress
$resolvedNoisy=Resolve-DevFleetCampaignEWorkerResult -ProcessStdout "diagnostic-noise`n$durableWorker" -DurableRaw $durableWorker
Check ([string]$resolvedNoisy.source-ceq'DURABLE'-and[string]$resolvedNoisy.processStdoutStatus-ceq'MALFORMED'-and[string]$resolvedNoisy.value.runId-ceq'unit-prereq') 'durable worker result did not survive malformed process stdout'
$resolvedMatching=Resolve-DevFleetCampaignEWorkerResult -ProcessStdout $durableWorker -DurableRaw $durableWorker
Check ([string]$resolvedMatching.source-ceq'DURABLE_AND_PROCESS_MATCH'-and[string]$resolvedMatching.processStdoutStatus-ceq'VALID') 'matching process/durable worker results were not recognized'
Rejected {Resolve-DevFleetCampaignEWorkerResult -ProcessStdout '' -DurableRaw '{malformed'} 'malformed durable worker result was accepted'
$differentWorker=($durableWorker|ConvertFrom-Json);$differentWorker.status='BLOCKED';$differentRaw=$differentWorker|ConvertTo-Json -Compress
Rejected {Resolve-DevFleetCampaignEWorkerResult -ProcessStdout $differentRaw -DurableRaw $durableWorker} 'disagreeing process/durable worker results were accepted'
$wrongKindWorker=($durableWorker|ConvertFrom-Json);$wrongKindWorker.kind='ARBITRARY';$wrongKindRaw=$wrongKindWorker|ConvertTo-Json -Compress
Rejected {Resolve-DevFleetCampaignEWorkerResult -ProcessStdout '' -DurableRaw $wrongKindRaw} 'unsupported durable worker result kind was accepted'

$candidateTar=Join-Path $root 'outputs\devfleet-v1.2.13.tar.gz'
$entries=@(& tar.exe -tf $candidateTar)
if($LASTEXITCODE-ne0){throw 'Unable to list the candidate TAR for the production-plan regression.'}
Check (Assert-DevFleetCampaignEArchiveEntries -Entries $entries) 'actual candidate archive was rejected'
$extractRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-e-prereq-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $extractRoot|Out-Null
    & tar.exe -xf $candidateTar -C $extractRoot
    if($LASTEXITCODE-ne0){throw 'Unable to extract the candidate TAR for the production-plan regression.'}
    $extractedPlan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot $extractRoot -Role Desktop
    foreach($name in @('version','dependencies','config','bootstrap','install','common')){Check ([string]$extractedPlan.inputHashes.$name-ceq[string]$plan.inputHashes.$name) "candidate TAR/source prerequisite hash mismatch: $name"}
} finally {if(Test-Path -LiteralPath $extractRoot){Remove-Item -LiteralPath $extractRoot -Recurse -Force}}
Rejected {Assert-DevFleetCampaignEArchiveEntries -Entries @('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json','windows/DevFleet.Common.psm1','../escape')} 'archive traversal was accepted'
Rejected {Assert-DevFleetCampaignEArchiveEntries -Entries @('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json','windows/DevFleet.Common.psm1','C:\escape')} 'rooted archive entry was accepted'
Rejected {Assert-DevFleetCampaignEArchiveEntries -Entries @('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json','windows/DevFleet.Common.psm1','VERSION')} 'duplicate archive entry was accepted'
Rejected {Assert-DevFleetCampaignEArchiveEntries -Entries @('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json')} 'missing candidate common module was accepted'

$acquisitionFixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-e-acquire-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $acquisitionFixtureRoot|Out-Null
    $fixtureWinget=Join-Path $acquisitionFixtureRoot 'winget.exe'
    Copy-Item -LiteralPath (Get-Process -Id $PID).Path -Destination $fixtureWinget
    $powershellDependency=@((Get-Content -LiteralPath (Join-Path $root 'source\dependencies.json') -Raw|ConvertFrom-Json).dependencies|Where-Object{[string]$_.id-ceq'powershell7'})[0]
    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z'
    $script:compatibilityCalls=0
    $script:nativeCalls=[Collections.Generic.List[object]]::new()
    $clockProvider={$script:acquisitionNow}
    $candidateProvider={param($dependency)[pscustomobject]@{path=$fixtureWinget;root=$acquisitionFixtureRoot;trustValidated=$true}}
    $compatibilityProvider={
        param($dependency,$deadline)
        $script:compatibilityCalls++
        if($script:compatibilityCalls-eq1){return [pscustomobject]@{status='Missing';version='';pathSha256='';detail='fixture absent'}}
        return [pscustomobject]@{status='Compatible';version='7.4.2';pathSha256=('b'*64);detail='fixture compatible'}
    }
    $nativeProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        $start=$script:acquisitionNow;$script:acquisitionNow=$script:acquisitionNow.AddSeconds(10)
        [void]$script:nativeCalls.Add([pscustomobject]@{operation=$operation;filePath=$filePath;arguments=@($arguments);timeoutSeconds=$timeoutSeconds;ownerDeadlineUtc=([datetime]$deadline).ToUniversalTime().ToString('o')})
        $stdout=if($operation-eq'winget-version'){'v1.8.1911'}elseif($operation-eq'winget-powershell-search'){'PowerShell Microsoft.PowerShell 7.4.2'}else{'fixture output'}
        [pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:acquisitionNow.ToString('o');deadlineUtc=$start.AddSeconds($timeoutSeconds).ToString('o');stdout=$stdout;stderr='';outputComplete=$true}
    }
    $acquisition=Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $nativeProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider
    Check ([string]$acquisition.method-ceq'WINGET_MANIFEST_APPROVED_DIAGNOSTIC'-and[string]$acquisition.packageId-ceq'Microsoft.PowerShell'-and@($acquisition.operations).Count-eq5) 'production acquisition function did not preserve the candidate manifest identity and five bounded operations'
    $sourceUpdateCall=@($script:nativeCalls|Where-Object{$_.operation-ceq'winget-source-update'})[0]
    Check ((@($sourceUpdateCall.arguments)-join' ')-ceq'source update --name winget --disable-interactivity') 'production acquisition function did not construct the exact bounded WinGet source-update arguments'
    $installCall=@($script:nativeCalls|Where-Object{$_.operation-ceq'winget-powershell-install'})[0]
    Check ((@($installCall.arguments)-join' ')-ceq'install --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity') 'production acquisition function did not construct the exact candidate-approved WinGet install arguments'
    Check ([int]$installCall.timeoutSeconds-eq80-and@($script:nativeCalls|Where-Object{$_.ownerDeadlineUtc-cne'2026-09-06T20:02:00.0000000Z'}).Count-eq0) 'production acquisition function granted a fresh child allowance or changed the immutable owner deadline'
    Check (-not[bool]$acquisition.productLifecycleStarted-and-not[bool]$acquisition.stageMarkerWritten-and($acquisition|ConvertTo-Json -Depth 12)-notmatch'fixture output') 'PowerShell acquisition fabricated product progress or retained raw native output'

    $script:compatibilityCalls=0;$script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z'
    $alreadySatisfiedProvider={param($dependency,$deadline)[pscustomobject]@{status='Compatible';version='7.4.2';pathSha256=('c'*64);detail='fixture compatible'}}
    $unexpectedNative={throw 'WinGet must not run when candidate-compatible PowerShell is already present.'}
    $preserved=Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider {throw 'WinGet candidate discovery must not run.'} -NativeProbeProvider $unexpectedNative -PowerShellCompatibilityProvider $alreadySatisfiedProvider -ClockProvider $clockProvider
    Check ([string]$preserved.method-ceq'PRESERVED_CANDIDATE_COMPATIBLE'-and@($preserved.operations).Count-eq0) 'production acquisition did not preserve an already compatible candidate-trusted PowerShell executable'
    $script:lateCompatibilityClockCalls=0
    $lateCompatibilityClock={
        $script:lateCompatibilityClockCalls++
        if($script:lateCompatibilityClockCalls-eq1){return [datetime]'2026-09-06T20:00:00Z'}
        return [datetime]'2026-09-06T20:02:01Z'
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider {throw 'WinGet candidate discovery must not run.'} -NativeProbeProvider $unexpectedNative -PowerShellCompatibilityProvider $alreadySatisfiedProvider -ClockProvider $lateCompatibilityClock} 'production acquisition revived a compatible observation completed after cutoff'

    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency ([pscustomobject]@{id='powershell7';minimumSupportedVersion='7.4.0';maximumMajor=7;wingetPackageId='Arbitrary.PowerShell'}) -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $nativeProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted a non-candidate package identity'
    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider {param($d)@([pscustomobject]@{path=$fixtureWinget;root=$acquisitionFixtureRoot;trustValidated=$true},[pscustomobject]@{path=$fixtureWinget;root=$acquisitionFixtureRoot;trustValidated=$true})} -NativeProbeProvider $nativeProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted ambiguous WinGet identity'
    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider {param($d)[pscustomobject]@{path=$fixtureWinget;root=$acquisitionFixtureRoot;trustValidated=$false}} -NativeProbeProvider $nativeProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted unvalidated WinGet identity'

    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    $badSearchProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        $start=$script:acquisitionNow;$script:acquisitionNow=$script:acquisitionNow.AddSeconds(1)
        $stdout=if($operation-eq'winget-version'){'v1.8.1911'}elseif($operation-eq'winget-powershell-search'){'unrelated package'}else{''}
        [pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:acquisitionNow.ToString('o');deadlineUtc=$start.AddSeconds($timeoutSeconds).ToString('o');stdout=$stdout;stderr='';outputComplete=$true}
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $badSearchProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted a search response without the exact manifest package'

    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    $timeoutProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        $start=$script:acquisitionNow;$script:acquisitionNow=$script:acquisitionNow.AddSeconds(1)
        [pscustomobject]@{operation=$operation;outcome='TIMEOUT';exitCode=$null;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:acquisitionNow.ToString('o');deadlineUtc=$start.AddSeconds($timeoutSeconds).ToString('o');stdout='';stderr='bounded timeout';outputComplete=$true}
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $timeoutProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition treated a bounded native timeout as prerequisite progress'

    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    $lateProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        [pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;startedAtUtc='2026-09-06T20:00:00Z';finishedAtUtc='2026-09-06T20:02:01Z';deadlineUtc='2026-09-06T20:02:00Z';stdout='v1.8.1911';stderr='';outputComplete=$true}
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $lateProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition retroactively accepted an operation first completed after cutoff'
    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0;$script:nonmonotonicCalls=0
    $nonmonotonicProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        $script:nonmonotonicCalls++
        if($script:nonmonotonicCalls-eq1){$start=[datetime]'2026-09-06T20:00:00Z';$finish=[datetime]'2026-09-06T20:00:10Z';$script:acquisitionNow=$finish}
        else{$start=[datetime]'2026-09-06T20:00:05Z';$finish=[datetime]'2026-09-06T20:00:06Z'}
        $stdout=if($operation-eq'winget-version'){'v1.8.1911'}else{'Microsoft.PowerShell'}
        [pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;startedAtUtc=$start.ToString('o');finishedAtUtc=$finish.ToString('o');deadlineUtc='2026-09-06T20:01:00Z';stdout=$stdout;stderr='';outputComplete=$true}
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $nonmonotonicProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted nonmonotonic native observations'
} finally {if(Test-Path -LiteralPath $acquisitionFixtureRoot){Remove-Item -LiteralPath $acquisitionFixtureRoot -Recurse -Force}}

$officialFixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-e-official-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $officialFixtureRoot|Out-Null
    $script:officialDependency=@((Get-Content -LiteralPath (Join-Path $root 'source\dependencies.json') -Raw|ConvertFrom-Json).dependencies|Where-Object{[string]$_.id-ceq'powershell7'})[0]
    $script:officialFixtureRoot=$officialFixtureRoot;$script:officialBase=[datetime]'2026-09-06T20:00:00Z';$script:officialOwner=$script:officialBase.AddMinutes(5)
    $copySource=[IO.MemoryStream]::new([byte[]](1,2,3));$copyTarget=[IO.MemoryStream]::new()
    try {$unsuppressedCopyOutput=@($copySource.CopyToAsync($copyTarget,81920,[Threading.CancellationToken]::None).GetAwaiter().GetResult());Check ($unsuppressedCopyOutput.Count-eq0-or($unsuppressedCopyOutput.Count-eq1-and$unsuppressedCopyOutput[0].GetType().FullName-ceq'System.Threading.Tasks.VoidTaskResult')) 'async stream-copy runtime behavior was neither silent nor the proven PowerShell 7 task-result emission'} finally {$copySource.Dispose();$copyTarget.Dispose()}
    $copySource=[IO.MemoryStream]::new([byte[]](1,2,3));$copyTarget=[IO.MemoryStream]::new()
    try {$suppressedCopyOutput=@(&{[void]$copySource.CopyToAsync($copyTarget,81920,[Threading.CancellationToken]::None).GetAwaiter().GetResult();[pscustomobject]@{outcome='PASS';bytes=$copyTarget.Length}});Check ($suppressedCopyOutput.Count-eq1-and[string]$suppressedCopyOutput[0].outcome-ceq'PASS'-and[int64]$suppressedCopyOutput[0].bytes-eq3) 'bounded stream copy leaked an incidental task result into the download evidence stream'} finally {$copySource.Dispose();$copyTarget.Dispose()}
    $script:officialMetadata=[pscustomobject]@{tag_name='v7.4.2';draft=$false;prerelease=$false;html_url='https://github.com/PowerShell/PowerShell/releases/tag/v7.4.2';assets=@([pscustomobject]@{name='PowerShell-7.4.2-win-x64.msi';browser_download_url='https://github.com/PowerShell/PowerShell/releases/download/v7.4.2/PowerShell-7.4.2-win-x64.msi'})}
    function Invoke-OfficialPayloadFixture {
        param([psobject]$MetadataValue=$script:officialMetadata,[string]$SignerSubject='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US',[switch]$BadHash,[switch]$LateDownload,[switch]$ExistingDestination)
        $destination=Join-Path $script:officialFixtureRoot ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $destination|Out-Null
        if($ExistingDestination){Set-Content -LiteralPath (Join-Path $destination 'PowerShell-7.4.2-win-x64.msi') -Value 'foreign' -NoNewline -Encoding Ascii}
        $fixtureBase=$script:officialBase;$fixtureOwner=$script:officialOwner
        $clockState=[pscustomobject]@{Now=$fixtureBase}
        $metadataProvider={param($uri,$timeout,$deadline)$clockState.Now=$fixtureBase.AddSeconds(1);$MetadataValue}.GetNewClosure()
        $downloadProvider={
            param($uri,$hosts,$path,$deadline)
            $started=$fixtureBase.AddSeconds(1);$finished=if($LateDownload){$fixtureOwner.AddSeconds(1)}else{$fixtureBase.AddSeconds(2)}
            Set-Content -LiteralPath $path -Value 'fixture-official-msi' -NoNewline -Encoding Ascii
            $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();if($BadHash){$hash='a'*64}
            $clockState.Now=$finished
            [pscustomobject]@{outcome='PASS';startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$fixtureOwner.ToString('o');finalHost='github.com';redirectHosts=@('github.com');bytes=(Get-Item -LiteralPath $path).Length;sha256=$hash}
        }.GetNewClosure()
        $authenticityProvider={param($path,$policy)$clockState.Now=$clockState.Now.AddSeconds(1);[pscustomobject]@{status='Valid';signerSubject=$SignerSubject}}.GetNewClosure()
        $clockProvider={$clockState.Now}.GetNewClosure()
        Get-DevFleetCampaignEOfficialPowerShellPayload -Dependency $script:officialDependency -DestinationDirectory $destination -OwnerDeadlineUtc $script:officialOwner -MetadataProvider $metadataProvider -DownloadProvider $downloadProvider -AuthenticityProvider $authenticityProvider -ClockProvider $clockProvider
    }
    $official=Invoke-OfficialPayloadFixture
    Check ([string]$official.kind-ceq'DEVFLEET_CAMPAIGN_E_OFFICIAL_POWERSHELL_PAYLOAD'-and[string]$official.method-ceq'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'-and[string]$official.packageId-ceq'Microsoft.PowerShell') 'official payload resolver lost the exact candidate package/repository identity'
    Check ([string]$official.releaseTag-ceq'v7.4.2'-and[string]$official.assetName-ceq'PowerShell-7.4.2-win-x64.msi'-and[string]$official.sha256-match'^[0-9a-f]{64}$'-and[int64]$official.bytes-gt0) 'official payload resolver did not publish a non-secret hash-bound MSI identity'
    Check (-not[bool]$official.productLifecycleStarted-and-not[bool]$official.stageMarkerWritten-and@($official.redirectHosts).Count-eq1) 'official payload resolution fabricated product progress or lost redirect provenance'

    $wrongRepository=Clone $script:officialMetadata;$wrongRepository.html_url='https://github.com/Other/PowerShell/releases/tag/v7.4.2'
    Rejected {Invoke-OfficialPayloadFixture -MetadataValue $wrongRepository} 'official payload resolver accepted the wrong release repository'
    $draft=Clone $script:officialMetadata;$draft.draft=$true
    Rejected {Invoke-OfficialPayloadFixture -MetadataValue $draft} 'official payload resolver accepted a draft release'
    $ambiguous=Clone $script:officialMetadata;$ambiguous.assets=@($ambiguous.assets[0],$ambiguous.assets[0])
    Rejected {Invoke-OfficialPayloadFixture -MetadataValue $ambiguous} 'official payload resolver accepted ambiguous matching MSI assets'
    $wrongAsset=Clone $script:officialMetadata;$wrongAsset.assets[0].browser_download_url='https://github.com/Other/PowerShell/releases/download/v7.4.2/PowerShell-7.4.2-win-x64.msi'
    Rejected {Invoke-OfficialPayloadFixture -MetadataValue $wrongAsset} 'official payload resolver accepted a wrong-repository asset URL'
    Rejected {Invoke-OfficialPayloadFixture -SignerSubject 'CN=Untrusted Fixture'} 'official payload resolver accepted the wrong signer identity'
    Rejected {Invoke-OfficialPayloadFixture -BadHash} 'official payload resolver accepted download evidence that disagreed with the staged bytes'
    Rejected {Invoke-OfficialPayloadFixture -LateDownload} 'official payload resolver revived a download completed after the immutable owner cutoff'
    Rejected {Invoke-OfficialPayloadFixture -ExistingDestination} 'official payload resolver overwrote a preexisting destination'

    $powershellDependency=$script:officialDependency;$officialBase=$script:officialBase
    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0;$script:stagedInstallerCalls=[Collections.Generic.List[object]]::new()
    $stagedClock={$script:stagedNow}
    $stagedCompatibility={param($dependency,$deadline)$script:stagedCompatibilityCalls++;if($script:stagedCompatibilityCalls-eq1){[pscustomobject]@{status='Missing';version='';pathSha256='';detail='fixture missing'}}else{[pscustomobject]@{status='Compatible';version='7.4.2';pathSha256=('b'*64);detail='fixture compatible'}}}
    $stagedAuthenticity={param($path,$policy)[pscustomobject]@{status='Valid';signerSubject='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'}}
    $stagedInstaller={
        param($path,$arguments,$timeout,$deadline)
        $start=$script:stagedNow;$script:stagedNow=$script:stagedNow.AddSeconds(10)
        [void]$script:stagedInstallerCalls.Add([pscustomobject]@{path=$path;arguments=@($arguments);timeout=$timeout;deadline=([datetime]$deadline).ToUniversalTime().ToString('o')})
        [pscustomobject]@{outcome='PASS';exitCode=0;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:stagedNow.ToString('o');deadlineUtc=([datetime]$deadline).ToUniversalTime().ToString('o');outputComplete=$true;stdout='must-not-survive';stderr=''}
    }
    $staged=Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $stagedInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock
    Check ([string]$staged.method-ceq'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'-and@($staged.operations).Count-eq1-and[string]$staged.operations[0].operation-ceq'official-powershell-msi-install') 'staged official acquisition did not publish the exact bounded installer operation'
    Check ((@($script:stagedInstallerCalls[0].arguments)-join'|')-ceq("/i|$([string]$official.localPath)|/qn|/norestart")-and[string]$script:stagedInstallerCalls[0].deadline-ceq'2026-09-06T20:04:00.0000000Z') 'staged official acquisition changed the candidate silent-install arguments or immutable owner deadline'
    Check (-not[bool]$staged.productLifecycleStarted-and-not[bool]$staged.stageMarkerWritten-and($staged|ConvertTo-Json -Depth 12)-notmatch'must-not-survive') 'staged official acquisition fabricated product progress or retained raw native output'

    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0
    $timeoutInstaller={param($p,$a,$t,$d)[pscustomobject]@{outcome='TIMEOUT';exitCode=$null;startedAtUtc=$officialBase.AddSeconds(4).ToString('o');finishedAtUtc=$officialBase.AddSeconds(10).ToString('o');deadlineUtc=([datetime]$d).ToUniversalTime().ToString('o');outputComplete=$true}}
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $timeoutInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock} 'staged official acquisition treated installer timeout as progress'
    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0
    $lateInstaller={param($p,$a,$t,$d)[pscustomobject]@{outcome='PASS';exitCode=0;startedAtUtc=$officialBase.AddSeconds(4).ToString('o');finishedAtUtc=$officialBase.AddMinutes(5).ToString('o');deadlineUtc=([datetime]$d).ToUniversalTime().ToString('o');outputComplete=$true}}
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $lateInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock} 'staged official acquisition retroactively accepted an installer completed after cutoff'
    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0
    $badExitInstaller={param($p,$a,$t,$d)[pscustomobject]@{outcome='NONZERO';exitCode=1603;startedAtUtc=$officialBase.AddSeconds(4).ToString('o');finishedAtUtc=$officialBase.AddSeconds(10).ToString('o');deadlineUtc=([datetime]$d).ToUniversalTime().ToString('o');outputComplete=$true}}
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $badExitInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock} 'staged official acquisition accepted an unapproved MSI exit code'
    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider {param($p,$policy)[pscustomobject]@{status='Valid';signerSubject='CN=Untrusted Fixture'}} -InstallerProvider $stagedInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock} 'staged official acquisition accepted a wrong signer at the guest boundary'
    $script:stagedNow=$officialBase.AddSeconds(4)
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $stagedInstaller -PowerShellCompatibilityProvider {param($d,$deadline)[pscustomobject]@{status='Compatible';version='8.0.0';pathSha256=('b'*64)}} -ClockProvider $stagedClock} 'staged official acquisition preserved a PowerShell version outside the candidate major policy'
} finally {if(Test-Path -LiteralPath $officialFixtureRoot){Remove-Item -LiteralPath $officialFixtureRoot -Recurse -Force}}

$workerFixtureId='campaign-e-inner-'+[guid]::NewGuid().ToString('N')
$workerFixtureRoot=Join-Path (Join-Path 'C:\Users\Public\DevFleet-E2E' $workerFixtureId) 'Prerequisite'
$oldProgramData=$env:ProgramData;$oldFixtureExe=$env:DEVFLEET_E_FIXTURE_EXE
try {
    $fixturePackage=Join-Path $workerFixtureRoot 'candidate-package'
    New-Item -ItemType Directory -Path (Join-Path $fixturePackage 'windows') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixturePackage 'config') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $workerFixtureRoot 'program-data') -Force|Out-Null
    foreach($name in @('VERSION','dependencies.json','Bootstrap-Install.ps1','Install-DevFleet.ps1')){Copy-Item -LiteralPath (Join-Path $root "source\$name") -Destination (Join-Path $fixturePackage $name)}
    Copy-Item -LiteralPath (Join-Path $root 'source\config\devfleet.config.json') -Destination (Join-Path $fixturePackage 'config\devfleet.config.json')
    $fakeCommon=@'
function Assert-PowerShell7 {}
function Assert-Administrator {}
function Set-DevFleetDeadlineContext { param($TransactionDeadlineUtc,$StageName,$StageBudgetSeconds) [pscustomobject]@{StageDeadlineUtc=$TransactionDeadlineUtc} }
function Get-CanonicalDependencyManifest { param($PackageRoot) Get-Content -LiteralPath (Join-Path $PackageRoot 'dependencies.json') -Raw|ConvertFrom-Json }
function Get-DependencyStatus { param($Dependency) if([string]$Dependency.id -eq 'powershell7'){[pscustomobject]@{Status='Compatible';Version='7.4.0';Path=$env:DEVFLEET_E_FIXTURE_EXE;Detail='fixture'}}else{[pscustomobject]@{Status='Compatible';Version='1.15.1';Path=$env:DEVFLEET_E_FIXTURE_EXE;Detail='fixture'}} }
function Get-WingetHealth { [pscustomobject]@{Status='Healthy';Path=$env:DEVFLEET_E_FIXTURE_EXE} }
function Install-WingetPackage { throw 'fixture must preserve compatible dependency' }
function Install-OfficialDependency { throw 'fixture must preserve compatible dependency' }
function Get-ComputerInfo { param($Property) [pscustomobject]@{WindowsProductName='Windows 11 Pro'} }
function Get-WindowsOptionalFeature { param([switch]$Online,$FeatureName) [pscustomobject]@{State='Enabled'} }
function Get-MultipassExe { $env:DEVFLEET_E_FIXTURE_EXE }
function Get-DevFleetOperationMaximumSeconds { param($Name) 30 }
function Invoke-External { param($FilePath,$ArgumentList,$TimeoutSeconds,$DeadlineUtc,[switch]$Capture) $joined=@($ArgumentList)-join' ';if($joined -eq 'get local.driver'){return 'hyperv'};if($joined -eq 'get local.privileged-mounts'){return 'false'};if($joined -eq 'list --format json'){return '{"list":[]}'};if($joined -match '^set '){return ''};throw "unexpected fixture operation: $joined" }
function Get-CimInstance { param($ClassName) @() }
function Get-DevFleetPendingRebootSnapshot { [pscustomobject]@{CbsPending=$false;WindowsUpdatePending=$false;PendingPairs=@()} }
Export-ModuleMember -Function *
'@
    $fakeCommon|Set-Content -LiteralPath (Join-Path $fixturePackage 'windows\DevFleet.Common.psm1') -Encoding UTF8
    $fixtureModule=Join-Path $workerFixtureRoot 'MultipassDiagnostic.psm1';Copy-Item -LiteralPath $modulePath -Destination $fixtureModule
    $fixturePlan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot $fixturePackage -Role Desktop
    $fixtureResult=Join-Path $workerFixtureRoot 'prerequisite-result.json'
    $env:ProgramData=Join-Path $workerFixtureRoot 'program-data'
    $env:DEVFLEET_E_FIXTURE_EXE=(Get-Process -Id $PID).Path
    $request=[ordered]@{runId='unit-inner';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';remoteRoot=$workerFixtureRoot;packageRoot=$fixturePackage;diagnosticModulePath=$fixtureModule;resultPath=$fixtureResult;role='Desktop';payloadSha256=('a'*64);inputHashes=$fixturePlan.inputHashes;ownerDeadlineUnixMilliseconds=[DateTimeOffset]::UtcNow.AddMinutes(2).ToUnixTimeMilliseconds();pendingRebootBaseline=[ordered]@{CbsPending=$false;WindowsUpdatePending=$false;PendingPairs=@()}}|ConvertTo-Json -Depth 8 -Compress
    $requestBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))
    & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'automation\release-e2e\Invoke-CampaignEPrerequisitePwshWorker.ps1') -RequestBase64 $requestBase64
    Check ($LASTEXITCODE-eq0-and(Test-Path -LiteralPath $fixtureResult -PathType Leaf)) 'actual PowerShell prerequisite worker did not complete the safe compatible-dependency fixture'
    $fixtureValue=Get-Content -LiteralPath $fixtureResult -Raw|ConvertFrom-Json
    Check ([string]$fixtureValue.kind-ceq'DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY'-and-not[bool]$fixtureValue.productLifecycleStarted-and[int]$fixtureValue.stageMarkerCount-eq0-and[int]$fixtureValue.backend.inventoryCount-eq0) 'actual PowerShell prerequisite work