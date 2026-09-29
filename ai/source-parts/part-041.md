# DevFleet source part 041

Full-source UTF-8 byte interval [1860000, 1906500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: dc6e342fbf72da6e97ad42ba93fc8645a8046136bcd79657476118b4ee90a5e6

<!-- BEGIN SOURCE SLICE -->
er fabricated product state or lost the empty backend contract'
} finally {
    $env:ProgramData=$oldProgramData;$env:DEVFLEET_E_FIXTURE_EXE=$oldFixtureExe
    $workerFixtureParent=Split-Path -Parent $workerFixtureRoot
    if(Test-Path -LiteralPath $workerFixtureParent){Remove-Item -LiteralPath $workerFixtureParent -Recurse -Force}
}

$fixtureId='campaign-e-prereq-'+[guid]::NewGuid().ToString('N')
$fixtureRoot=Join-Path 'C:\Users\Public\DevFleet-E2E' $fixtureId
$fixturePrereq=Join-Path $fixtureRoot 'Prerequisite'
try {
    New-Item -ItemType Directory -Path $fixturePrereq -Force|Out-Null
    $stubPath=Join-Path $fixturePrereq 'Install-DevFleet.ps1'
    Get-DevFleetCampaignEBootstrapStubContent|Set-Content -LiteralPath $stubPath -Encoding UTF8
    $ack=Join-Path $fixturePrereq 'bootstrap-ack.json'
    $oldAck=$env:DEVFLEET_E_BOOTSTRAP_ACK;$oldRun=$env:DEVFLEET_E_RUN_ID
    $env:DEVFLEET_E_BOOTSTRAP_ACK=$ack;$env:DEVFLEET_E_RUN_ID='unit-prereq'
    try {& $stubPath -Role Desktop -InstallationMode Connected -PackageRoot 'C:\candidate' -NonInteractive -SkipWindowsUpdates -DeferNetworkPairing -AcknowledgeRootfulDocker -TransactionDeadlineUtc ([datetime]::UtcNow.AddMinutes(1).ToString('o'))} finally {$env:DEVFLEET_E_BOOTSTRAP_ACK=$oldAck;$env:DEVFLEET_E_RUN_ID=$oldRun}
    $ackValue=Get-Content -LiteralPath $ack -Raw|ConvertFrom-Json
    Check ([string]$ackValue.kind-ceq'CAMPAIGN_E_POWERSHELL_BOOTSTRAP_ONLY'-and-not[bool]$ackValue.productLifecycleStarted-and-not[bool]$ackValue.stageMarkerWritten) 'bootstrap-only acknowledgement fabricated product lifecycle state'
    $env:DEVFLEET_E_BOOTSTRAP_ACK=$ack;$env:DEVFLEET_E_RUN_ID='unit-prereq'
    $transactionRejected=$false
    try {& $stubPath -Role Desktop -InstallationMode Connected -PackageRoot 'C:\candidate' -TransactionId ('a'*32)} catch {$transactionRejected=$_.Exception.Message-match'transactionless'} finally {$env:DEVFLEET_E_BOOTSTRAP_ACK=$oldAck;$env:DEVFLEET_E_RUN_ID=$oldRun}
    Check $transactionRejected 'bootstrap-only shim accepted a product transaction or rejected it for the wrong boundary'
} finally {
    if(Test-Path -LiteralPath $fixtureRoot){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force}
}

$base=[datetime]'2026-09-06T20:00:00Z'
$valid=[pscustomobject][ordered]@{
    schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY';status='PASS';runId='unit-prereq';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64)
    role='Desktop';packageVersion='1.2.13';ownerDeadlineUtc=$base.AddMinutes(10).ToString('o');startedAtUtc=$base.ToString('o');producedAtUtc=$base.AddMinutes(5).ToString('o');inputHashes=$plan.inputHashes
    systemPolicyChanged=$false;productLifecycleStarted=$false;activeTransactionPresent=$false;stageMarkerCount=0;activeInstallProcessCount=0;pendingReboot=$false
    powershell=[ordered]@{status='Compatible';version='7.4.0';pathSha256=('b'*64)};multipass=[ordered]@{status='Compatible';version='1.15.1';pathSha256=('c'*64);preexisting=$false}
    powershellAcquisition=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='PRESERVED_CANDIDATE_COMPATIBLE';packageId='Microsoft.PowerShell';startedAtUtc=$base.ToString('o');finishedAtUtc=$base.AddMinutes(1).ToString('o');ownerDeadlineUtc=$base.AddMinutes(10).ToString('o');wingetPathSha256='';operations=@();powershell=[ordered]@{status='Compatible';version='7.4.0';pathSha256=('b'*64)};productLifecycleStarted=$false;stageMarkerWritten=$false}
    backend=[ordered]@{driver='hyperv';privilegedMounts=$false;inventoryCount=0};l2Status='ABSENT'
}
Check (Assert-DevFleetCampaignEPrerequisiteResult -Result $valid -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan) 'valid prerequisite result was rejected'
$stagedValid=Clone $valid
$stagedValid.powershellAcquisition=[pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId='Microsoft.PowerShell';startedAtUtc=$base.AddSeconds(5).ToString('o');finishedAtUtc=$base.AddMinutes(1).ToString('o');ownerDeadlineUtc=$base.AddMinutes(10).ToString('o');wingetPathSha256='';officialPayload=[ordered]@{releaseTag='v7.4.2';assetName='PowerShell-7.4.2-win-x64.msi';sha256=('e'*64);bytes=42;signerSubject='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'};operations=@([ordered]@{operation='official-powershell-msi-install';outcome='PASS';exitCode=0;startedAtUtc=$base.AddSeconds(10).ToString('o');finishedAtUtc=$base.AddSeconds(20).ToString('o');deadlineUtc=$base.AddMinutes(10).ToString('o');outputComplete=$true;packageIdentityObserved=$true});powershell=[ordered]@{status='Compatible';version='7.4.0';pathSha256=('b'*64)};productLifecycleStarted=$false;stageMarkerWritten=$false}
Check (Assert-DevFleetCampaignEPrerequisiteResult -Result $stagedValid -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan) 'valid staged-official prerequisite result was rejected'
$stagedWrongSigner=Clone $stagedValid;$stagedWrongSigner.powershellAcquisition.officialPayload.signerSubject='CN=Untrusted Fixture'
Rejected {Assert-DevFleetCampaignEPrerequisiteResult -Result $stagedWrongSigner -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan} 'staged-official result validator accepted the wrong signer'
$stagedWrongOperation=Clone $stagedValid;$stagedWrongOperation.powershellAcquisition.operations[0].operation='arbitrary-install'
Rejected {Assert-DevFleetCampaignEPrerequisiteResult -Result $stagedWrongOperation -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan} 'staged-official result validator accepted the wrong operation identity'

$failureOperations=[Collections.Generic.List[object]]::new()
for($index=0;$index-lt4;$index++){
    $operationName=@('winget-version','winget-source-list','winget-source-update','winget-powershell-search')[$index]
    [void]$failureOperations.Add([pscustomobject][ordered]@{operation=$operationName;outcome=if($index-eq3){'NONZERO'}else{'PASS'};exitCode=if($index-eq3){-1978335217}else{0};pid=100+$index;startedAtUtc=$base.AddSeconds($index*10).ToString('o');finishedAtUtc=$base.AddSeconds(($index+1)*10).ToString('o');deadlineUtc=$base.AddMinutes(2).ToString('o');outputComplete=$true})
}
$validFailure=[pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_FAILURE';status='BLOCKED';runId='unit-prereq';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);producedAtUtc=$base.AddMinutes(1).ToString('o');ownerDeadlineUtc=$base.AddMinutes(10).ToString('o');primaryError='WinGet source data missing.';powershellAcquisition=[ordered]@{status='BLOCKED';identity=[ordered]@{method='WINGET_MANIFEST_APPROVED_DIAGNOSTIC';packageId='Microsoft.PowerShell';wingetPathSha256=('d'*64);ownerDeadlineUtc=$base.AddMinutes(10).ToString('o')};operations=@($failureOperations);productLifecycleStarted=$false;stageMarkerWritten=$false}}
Check (Assert-DevFleetCampaignEPrerequisiteFailure -Failure $validFailure -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64)) 'valid run-bound prerequisite failure was rejected'
$stagedFailure=Clone $validFailure
$stagedFailure.primaryError='Official PowerShell MSI failed.'
$stagedFailure.powershellAcquisition.identity=[pscustomobject][ordered]@{method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId='Microsoft.PowerShell';payloadSha256=('e'*64);assetName='PowerShell-7.4.2-win-x64.msi';ownerDeadlineUtc=$base.AddMinutes(10).ToString('o')}
$stagedFailure.powershellAcquisition.operations=@([pscustomobject][ordered]@{operation='official-powershell-msi-install';outcome='NONZERO';exitCode=1603;pid=200;startedAtUtc=$base.AddSeconds(10).ToString('o');finishedAtUtc=$base.AddSeconds(20).ToString('o');deadlineUtc=$base.AddMinutes(2).ToString('o');outputComplete=$true})
Check (Assert-DevFleetCampaignEPrerequisiteFailure -Failure $stagedFailure -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64)) 'valid staged-official failure evidence was rejected'
$stagedFailureWrongAsset=Clone $stagedFailure;$stagedFailureWrongAsset.powershellAcquisition.identity.assetName='arbitrary.msi'
Rejected {Assert-DevFleetCampaignEPrerequisiteFailure -Failure $stagedFailureWrongAsset -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64)} 'staged-official failure validator accepted an arbitrary payload identity'
foreach($case in @(
    @{name='failure wrong run';edit={param($v)$v.runId='wrong'}},
    @{name='failure late publication';edit={param($v)$v.producedAtUtc=$base.AddMinutes(11).ToString('o')}},
    @{name='failure product progress';edit={param($v)$v.powershellAcquisition.productLifecycleStarted=$true}},
    @{name='failure wrong operation sequence';edit={param($v)$v.powershellAcquisition.operations[2].operation='winget-powershell-search'}},
    @{name='failure wrong package identity';edit={param($v)$v.powershellAcquisition.identity.packageId='Arbitrary.PowerShell'}},
    @{name='failure missing executable hash';edit={param($v)$v.powershellAcquisition.identity.wingetPathSha256=''}}
)){
    $badFailure=Clone $validFailure;&$case.edit $badFailure
    Rejected {Assert-DevFleetCampaignEPrerequisiteFailure -Failure $badFailure -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64)} "$($case.name) was accepted"
}

foreach($case in @(
    @{name='late result';edit={param($v)$v.producedAtUtc=$base.AddMinutes(11).ToString('o')}},
    @{name='wrong run';edit={param($v)$v.runId='wrong'}},
    @{name='wrong VM';edit={param($v)$v.vmId=[guid]::NewGuid().ToString()}},
    @{name='wrong payload';edit={param($v)$v.payloadSha256=('d'*64)}},
    @{name='wrong candidate hash';edit={param($v)$v.inputHashes.config=('e'*64)}},
    @{name='system policy mutation';edit={param($v)$v.systemPolicyChanged=$true}},
    @{name='product lifecycle start';edit={param($v)$v.productLifecycleStarted=$true}},
    @{name='active transaction';edit={param($v)$v.activeTransactionPresent=$true}},
    @{name='stage marker';edit={param($v)$v.stageMarkerCount=1}},
    @{name='active installer';edit={param($v)$v.activeInstallProcessCount=1}},
    @{name='pending reboot';edit={param($v)$v.pendingReboot=$true}},
    @{name='incompatible PowerShell';edit={param($v)$v.powershell.status='Outdated'}},
    @{name='missing PowerShell acquisition';edit={param($v)$v.powershellAcquisition=$null}},
    @{name='mismatched PowerShell acquisition';edit={param($v)$v.powershellAcquisition.powershell.pathSha256=('d'*64)}},
    @{name='late PowerShell acquisition';edit={param($v)$v.powershellAcquisition.finishedAtUtc=$base.AddMinutes(11).ToString('o')}},
    @{name='unsupported PowerShell acquisition';edit={param($v)$v.powershellAcquisition.method='DIRECT_UNVERIFIED'}},
    @{name='incompatible Multipass';edit={param($v)$v.multipass.version='1.12.9'}},
    @{name='wrong backend';edit={param($v)$v.backend.driver='virtualbox'}},
    @{name='privileged mounts';edit={param($v)$v.backend.privilegedMounts=$true}},
    @{name='nonempty inventory';edit={param($v)$v.backend.inventoryCount=1}},
    @{name='unverified L2';edit={param($v)$v.l2Status='UNVERIFIED'}}
)){
    $bad=Clone $valid;&$case.edit $bad
    Rejected {Assert-DevFleetCampaignEPrerequisiteResult -Result $bad -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan} "$($case.name) was accepted"
}

$shell=(Get-Process -Id $PID).Path
$probe=Invoke-DevFleetBoundedNativeProbe -Operation 'large-output-fixture' -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command',"[Console]::Out.Write(('x'*5000))") -TimeoutSeconds 10 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(15)) -MaxStdoutCharacters 600
Check ([string]$probe.outcome-ceq'PASS'-and[bool]$probe.stdoutTruncated-and[string]$probe.stdout.Length-eq600) 'bounded native collector did not honor the explicit diagnostic output cap'

foreach($script in @('Invoke-CampaignEPrerequisiteWorker.ps1','Invoke-CampaignEPrerequisitePwshWorker.ps1','Invoke-CampaignEPrerequisiteCheckpoint.ps1')){
    $errors=$null;$tokens=$null
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $root "automation\release-e2e\$script"),[ref]$tokens,[ref]$errors)|Out-Null
    Check ($errors.Count-eq0) "$script has parser errors"
}

Write-Host "PASS $count Campaign E prerequisite/checkpoint behavioral checks"

```


## FILE: automation/release-e2e/tests/Test-CampaignEProductProfile.ps1

SHA256: df72d5f35319333dff8ff684b1345f105e5ccb0aefb878cde1299753389cb9f0 | Bytes: 7566 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$releaseRoot=Split-Path -Parent $PSScriptRoot;$root=Split-Path -Parent (Split-Path -Parent $releaseRoot)
Import-Module (Join-Path $releaseRoot 'modules/MultipassDiagnostic.psm1') -Force -DisableNameChecking
$worker=Join-Path $releaseRoot 'Invoke-CampaignEProductProfile.ps1';$engine=(Get-Process -Id $PID).Path
$runPrefix='astra-profile-'+[guid]::NewGuid().ToString('N');$owned=[Collections.Generic.List[string]]::new();$results=[Collections.Generic.List[object]]::new()
# Actual candidate preflight and config logic; only machine I/O/admin assertions
# are fixtures in the copied Common module and child entry, never in shipping.
$machine=@'
function Get-CimInstance {
    param($ClassName,$OperationTimeoutSec)
    switch($ClassName){
        Win32_ComputerSystem {[pscustomobject]@{TotalPhysicalMemory=16GB;NumberOfLogicalProcessors=6}}
        Win32_OperatingSystem {[pscustomobject]@{Caption='Fixture Windows 11 Pro';Version='10.0'}}
        Win32_Processor {[pscustomobject]@{Name='Fixture CPU';VirtualizationFirmwareEnabled=$true;SecondLevelAddressTranslationExtensions=$true}}
        default {throw 'Unexpected machine query.'}
    }
}
function Get-PSDrive {param($Name)[pscustomobject]@{Free=if($env:DEVFLEET_PROFILE_FIXTURE-ceq'low-disk'){1GB}else{200GB}}}
function Get-ComputerInfo {param($Property)[pscustomobject]@{WindowsProductName='Windows 11 Pro'}}
function Get-Process {param($Name) @()}
function Assert-Administrator {}
'@
try {
    foreach($case in @('success','bad-input-hash','bad-owner','active-transaction','low-disk','expired-owner','m3-success','m3-bad-template','m3-bad-name')){
        $run=$runPrefix+'-'+$case;$parent=[IO.Path]::GetFullPath("C:\Users\Public\DevFleet-E2E\$run");$remote=Join-Path $parent 'M1';$owned.Add($parent)
        New-Item -ItemType Directory -Path (Join-Path $remote 'profile-package/windows'),(Join-Path $remote 'profile-package/config'),(Join-Path $parent 'real-data/DevFleet')|Out-Null
        $nonce=[guid]::NewGuid();@{kind='DEVFLEET_CAMPAIGN_E_STAGING_OWNER';runId=$run;nonce=$nonce.ToString()}|ConvertTo-Json|Set-Content (Join-Path $remote '.owner.json')
        Copy-Item (Join-Path $root 'source/windows/00-Preflight.ps1') (Join-Path $remote 'profile-package/windows/00-Preflight.ps1')
        Copy-Item (Join-Path $root 'source/config/devfleet.config.json') (Join-Path $remote 'profile-package/config/devfleet.config.json')
        [IO.File]::WriteAllText((Join-Path $remote 'profile-package/windows/DevFleet.Common.psm1'),([IO.File]::ReadAllText((Join-Path $root 'source/windows/DevFleet.Common.psm1'))+[Environment]::NewLine+$machine+[Environment]::NewLine+'Export-ModuleMember -Function *'),[Text.UTF8Encoding]::new($false))
        $inputs=@(foreach($relative in @('windows/00-Preflight.ps1','windows/DevFleet.Common.psm1','config/devfleet.config.json')){@{path=$relative;sha256=(Get-FileHash (Join-Path $remote ('profile-package/'+$relative)) -Algorithm SHA256).Hash.ToLowerInvariant()}})
        $productLaunch=$case-like'm3-*'
        if($productLaunch){
            New-Item -ItemType Directory -Path (Join-Path $remote 'profile-package/cloud-init')|Out-Null
            Copy-Item (Join-Path $root 'source/cloud-init/compute.yaml') (Join-Path $remote 'profile-package/cloud-init/compute.yaml')
            $inputs+=@{path='cloud-init/compute.yaml';sha256=if($case-ceq'm3-bad-template'){'f'*64}else{(Get-FileHash (Join-Path $remote 'profile-package/cloud-init/compute.yaml') -Algorithm SHA256).Hash.ToLowerInvariant()}}
        }
        $deadline=[datetime]::UtcNow.AddSeconds(20);if($case-ceq'expired-owner'){$deadline=[datetime]::UtcNow.AddSeconds(-1)}
        if($case-ceq'bad-input-hash'){$inputs[0].sha256='f'*64}
        if($case-ceq'active-transaction'){'{}'|Set-Content (Join-Path $parent 'real-data/DevFleet/active-transaction.json')}
        $request=@{runId=$run;vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);remoteRoot=$remote;inputs=$inputs;stagingNonce=if($case-ceq'bad-owner'){[guid]::NewGuid().ToString()}else{$nonce.ToString()};deadlineUnixMilliseconds=[DateTimeOffset]::new($deadline).ToUnixTimeMilliseconds()}
        if($productLaunch){$request.productLaunch=$true;$request.instanceName=if($case-ceq'm3-bad-name'){'devfleet-primary'}else{"DevFleet-E2E-E-M1-$run"}}
        $entry=Join-Path $parent 'entry.ps1';$entryBody=@'
param($Worker,$Request,$Data,$Case)
$env:ProgramData=$Data;$env:DEVFLEET_PROFILE_FIXTURE=$Case
'@
        [IO.File]::WriteAllText($entry,($entryBody+[Environment]::NewLine+$machine+[Environment]::NewLine+'& $Worker -RequestBase64 $Request; exit $LASTEXITCODE'),[Text.UTF8Encoding]::new($false))
        $base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json -Depth 5 -Compress)))
        $probe=Invoke-DevFleetBoundedNativeProbe -Operation "profile-$case" -FilePath $engine -ArgumentList @('-NoProfile','-File',$entry,'-Worker',$worker,'-Request',$base64,'-Data',(Join-Path $parent 'real-data'),'-Case',$case) -TimeoutSeconds 15 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(20)) -ForceLegacyArgumentString -MaxStdoutCharacters 32768
        $path=Join-Path $remote 'product-profile.json';$profile=if(Test-Path $path){Get-Content $path -Raw|ConvertFrom-Json}else{$probe.stdout|ConvertFrom-Json}
        $pass=$true
        if($case-cin@('success','m3-success')){
            $pass=$probe.exitCode-eq0-and$profile.status-ceq'PASS_PROFILE_ONLY'-and[int]$profile.resources.cpus-eq4-and$profile.resources.memory-ceq'9G'-and$profile.resources.disk-ceq'220G'-and$profile.ubuntuImage-ceq'24.04'
            Assert-DevFleetCampaignEProductProfile -Profile $profile -ExpectedRunId $run -ExpectedVmId ([guid]$request.vmId) -ExpectedPayloadSha256 $request.payloadSha256 -ExpectedInputs $inputs -DeadlineUtc $deadline -ExpectedProductLaunch:$productLaunch|Out-Null
            if($productLaunch){
                $cloud=Join-Path $remote 'product-cloud-init.yaml';$rendered=Get-Content $cloud -Raw
                $pass=$pass-and(Get-FileHash $cloud -Algorithm SHA256).Hash.ToLowerInvariant()-ceq$profile.productLaunch.cloudInitSha256-and$rendered-match([regex]::Escape($request.instanceName))-and$rendered-notmatch'__(NODE|GIT)_'-and$rendered-match'package_update: true'
                $plainRejected=$false;try{Assert-DevFleetCampaignEProductProfile -Profile $profile -ExpectedRunId $run -ExpectedVmId ([guid]$request.vmId) -ExpectedPayloadSha256 $request.payloadSha256 -ExpectedInputs $inputs -DeadlineUtc $deadline|Out-Null}catch{$plainRejected=$true};$pass=$pass-and$plainRejected
            }
        }else{$pass=$probe.exitCode-eq1-and$profile.status-ceq'BLOCKED'-and-not[string]::IsNullOrWhiteSpace([string]$profile.primaryError)}
        $pass=$pass-and-not(Test-Path (Join-Path $parent 'real-data/DevFleet/devfleet.config.json'))-and-not[bool]$profile.productLifecycleStarted
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;exitCode=$probe.exitCode;error=$profile.primaryError})
    }
}finally{
    foreach($path in $owned){if(-not$path.StartsWith('C:\Users\Public\DevFleet-E2E\'+$runPrefix,[StringComparison]::Ordinal)){throw 'Profile fixture cleanup escaped ownership.'};if(Test-Path $path){Remove-Item -LiteralPath $path -Recurse -Force}}
}
$results|ConvertTo-Json -Depth 3
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Actual candidate preflight profile regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) actual candidate preflight profile checks"

```


## FILE: automation/release-e2e/tests/Test-CorrectionInventoryOrdering.ps1

SHA256: 6e08106c7206116380d5d0250571542c07dca5bf7cd50ec001808273ecf65067 | Bytes: 985 | Git mode: 100644

```
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $WorkspaceRoot 'installer-source/Build-Release.ps1') -Raw
$start=$source.IndexOf('  [string[]]$authorizedPaths=@(')
$end=$source.IndexOf('  foreach($authorizedPath', $start)
if($start-lt0-or$end-le$start){throw 'Native correction path construction was not found.'}
$priorState=[pscustomobject]@{authorized_correction=[pscustomobject]@{shipping_paths=@('source/app/z.py','source/CHECKSUMS.sha256','installer-source/Build-Release.ps1','source/app/z.py')}}
. ([scriptblock]::Create($source.Substring($start,$end-$start)))
if(($authorizedPaths-join ',')-cne'installer-source/Build-Release.ps1,source/CHECKSUMS.sha256,source/app/z.py'){throw 'Native correction inventory is not unique and ordinal-sorted.'}
[ordered]@{status='PASS';realNativeConstruction=$true;buildInvoked=$false;runtime=$PSVersionTable.PSVersion.ToString()}|ConvertTo-Json

```


## FILE: automation/release-e2e/tests/Test-CurrentGuestEvidenceChronology.ps1

SHA256: 84413a82f99a4bb017e4e43e2a074845f5fe14f676e78bb02b0e0f806605a0f0 | Bytes: 4796 | Git mode: 100644

```
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
# Exercise the unchanged production evidence-building body, replacing only OS/guest I/O.
# Host identity/admission checks are covered elsewhere; this is never lab admission.
$workspace=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$path=Join-Path $workspace '.agents/skills/devfleet-certification-orchestrator/scripts/Test-CurrentGuestAccess.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Production collector parse failure'}
$statements=@($ast.EndBlock.Statements)
$start=@($statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -ceq '$result'})[0]
$finish=@($statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[-1]
if(-not $start -or -not $finish){throw 'Production evidence-body boundary missing'}
$body=[scriptblock]::Create(($statements|Where-Object {$_.Extent.StartOffset -ge $start.Extent.StartOffset -and $_.Extent.EndOffset -le $finish.Extent.EndOffset}|ForEach-Object {$_.Extent.Text}) -join "`n")
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-guest-evidence-'+[guid]::NewGuid().ToString('N'))
$oldAppData=$env:LOCALAPPDATA
$passes=0
function Assert-That([bool]$ok,[string]$message){if(-not $ok){throw $message};$script:passes++}
try {
 New-Item -ItemType Directory -Path (Join-Path $fixture 'DevFleet/E2E') -Force|Out-Null
 $env:LOCALAPPDATA=$fixture
 [IO.File]::WriteAllText((Join-Path $fixture 'DevFleet/E2E/secrets.json'),'TEST METADATA ONLY - NOT A CREDENTIAL')
 $mockSecrets=New-Module -Name Secrets -ScriptBlock {function Get-DevFleetE2ECredential {[pscustomobject]@{UserName='E2EAdmin'}};Export-ModuleMember -Function Get-DevFleetE2ECredential}
 Import-Module $mockSecrets -Force
 $RunId='r2-fixture-chronology';$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
 $vm=[pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=$vmId}
 $fingerprint=[pscustomobject]@{repositoryHead=('1'*40);gitCommit=('2'*40);shippingInputIdentity=('3'*64);releaseFingerprintId=('4'*64);toolingFingerprintId=('5'*64);candidate=[pscustomobject]@{sha256=('6'*64)}}
 $script:removed=0;$script:failOpen=$false
 function New-PSSession {param($VMId,$Credential,$ErrorAction) if($script:failOpen){throw 'Synthetic guest transport failure'};[pscustomobject]@{InstanceId='fixture'}}
 function Remove-PSSession {param($Session,$ErrorAction) $script:removed++}
 function Invoke-Command {param($Session,$ScriptBlock) [pscustomobject]@{computerName='DEVFLEET-E2E-01';principal='DEVFLEET-E2E-01\E2EAdmin';accountEnabled=$true;passwordLastSetUtc=[datetimeoffset]::UtcNow.AddMinutes(-20).ToString('o');passwordExpiresUtc=[datetimeoffset]::UtcNow.AddDays(30).ToString('o')}}
 function Get-DevFleetNestedL2State {param($Session,$ExpectedName)
  Start-Sleep -Milliseconds 30
  [pscustomobject]@{status='ABSENT';present=$false;expectedName=$ExpectedName;verification='SYNTHETIC TEST ONLY';observedUtc=[datetimeoffset]::UtcNow.ToString('o');exactMatchCount=0;backendInventories=@([pscustomobject]@{provider='Hyper-V';status='PASS';names=@();verification='SYNTHETIC'},[pscustomobject]@{provider='VirtualBox';status='PASS';names=@();verification='SYNTHETIC'})}
 }
 . $body
 Assert-That ($result.status -ceq 'AUTHENTICATED_CURRENT_GUEST_NOT_CLEAN_PROOF') 'Fixture failed before chronology assertion'
 if($OutputPath){[IO.File]::WriteAllText($OutputPath,($result|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
 Assert-That ([datetimeoffset]$result.observedUtc -ge [datetimeoffset]$result.nestedL2.observedUtc) 'Report observedUtc precedes collected nested inventory: adoption will reject it'
 Assert-That ($script:removed -eq 1) 'Collector did not close its fixture session'
 Assert-That ($result.certificationCredit -eq $false -and $result.vmMutationPerformed -eq $false) 'Diagnostic claimed certification/mutation'
 $script:failOpen=$true
 . $body
 Assert-That ($result.status -ceq 'BLOCKED' -and -not $result.connected) 'Transport failure did not stay blocked'
 Assert-That ($null -eq $result.nestedL2 -and $null -eq $result.guest) 'Failure invented guest evidence'
 Assert-That (-not [string]::IsNullOrWhiteSpace($result.observedUtc)) 'Failure lost observation timestamp'
 Assert-That ($script:removed -eq 1) 'Failure tried to close a nonexistent session'
 [pscustomobject]@{status='PASS';assertions=$passes;vmOperations=0;realCredentialReads=0;scope='PRODUCTION_EVIDENCE_BODY_WITH_MOCKED_OS_IO'}|ConvertTo-Json -Compress
} finally {
 $env:LOCALAPPDATA=$oldAppData
 if($mockSecrets){Remove-Module $mockSecrets -ErrorAction SilentlyContinue}
 Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: automation/release-e2e/tests/Test-ExactProofBinding.ps1

SHA256: 8b6a0d30dd1c1c81a7b50e47f9e731bb82e3505c796e4e2c89e7facbe9944aa4 | Bytes: 6294 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-proof-binding-'+[guid]::NewGuid().ToString('N'))
$passed=0;$failed=[Collections.Generic.List[string]]::new()
function Check([bool]$Value,[string]$Name){if($Value){$script:passed++}else{[void]$script:failed.Add($Name)}}
function WriteJson($Path,$Value){$Value|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path -Encoding utf8NoBOM}
try{
    New-Item -ItemType Directory -Path (Join-Path $root 'source/config') -Force|Out-Null
    $configPath=Join-Path $root 'source/config/devfleet.config.json'
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'source/config/devfleet.config.json') -Destination $configPath
    $configHash=(Get-FileHash -LiteralPath $configPath).Hash.ToLowerInvariant()
    WriteJson (Join-Path $root 'CURRENT-CANDIDATE.json') ([ordered]@{candidateIsCurrent=$true;sourceChangedSinceCandidate=$false;rebuildRequired=$false;shippingInputIdentity=('c'*64);candidateShippingInputIdentity=('c'*64);candidateGitCommit=('d'*40);candidateShippingInputs=@(@{root='source';path='config/devfleet.config.json';sha256=$configHash})})
    function NewFixture([string]$Role){
        $phase=if($Role -ceq 'Laptop / Surrogate'){'SURROGATE-DISPOSABLE'}else{'REBOOT-RESUME'}
        $run=Join-Path $root ([guid]::NewGuid().ToString('N'));$tx=[guid]::NewGuid().ToString('N');$lineage=[guid]::NewGuid().ToString('N');$payload='b'*64
        $life=Join-Path $run "lifecycle-$phase-$lineage";New-Item -ItemType Directory -Path $life -Force|Out-Null
        $targets=if($Role -ceq 'Laptop / Surrogate'){@(@{instanceName='devfleet-failover';nodeRole='surrogate';kind='compute'},@{instanceName='devfleet-vault';nodeRole='vault';kind='vault'})}else{@(@{instanceName='devfleet-primary';nodeRole='primary';kind='compute'})}
        $markers=@(foreach($target in $targets){@{instanceName=$target.instanceName;nodeRole=$target.nodeRole;marker=@{transactionId=$tx;payloadSha256=$payload;nodeRole=$target.nodeRole;component='bootstrap';state='COMPLETED'}}})
        $generation=@{generation=1;invocationId=$lineage;reboot=@{checkpoint=@{transactionId=$tx;payloadSha256=$payload;role=$Role;action='FreshInstall'};bootIdentityChanged=$true};resume=@{status='REAL E2E OBSERVER HANDOFF'}}
        $generationPath=Join-Path $life 'product-lifecycle-generation-1.json';WriteJson $generationPath $generation
        $authorityPath=Join-Path $life 'product-lifecycle-completion-authority.json'
        $authority=@{status='REAL E2E PASS';contract='product-lifecycle-completion-authority';completionVerified=$true;authenticatedHealth=$true;role=$Role;transactionId=$tx;invocationId=$lineage;payloadSha256=$payload;evidencePath=$authorityPath;guest=@{completionVerified=$true;transactionId=$tx;role=$Role;roleEvidence=@{requiredTargets=$targets;configSha256=$configHash;markers=$markers}};evidenceReferences=@(@{kind='lifecycle-generation';path=$generationPath;sha256=(Get-FileHash -LiteralPath $generationPath).Hash.ToLowerInvariant()})}
        WriteJson $authorityPath $authority
        return @{context=[pscustomobject]@{workspaceRoot=$root;runDir=$run;candidate=@{tar=@{sha256=$payload}}};phase=@{status='REAL E2E PASS';phase=$phase;product=$authority};authority=$authority;generation=$generation;generationPath=$generationPath;role=$Role}
    }
    foreach($role in @('Primary / Desktop','Laptop / Surrogate')){
        $fixture=NewFixture $role
        $binding=New-DevFleetExactProofBinding -Context $fixture.context -PhaseResult $fixture.phase -ExpectedRole $role
        Check ($binding.transactionId -ceq $fixture.authority.transactionId -and $binding.checkpointLineageId -ceq $fixture.authority.invocationId -and $binding.evidence.Count -eq 2) "$role uses durable product transaction, lineage and reboot records"
    }
    $cases=@{
        'missing Vault'={param($f)$f.authority.guest.roleEvidence.markers=@($f.authority.guest.roleEvidence.markers[0])}
        'foreign marker transaction'={param($f)$f.authority.guest.roleEvidence.markers[1].marker.transactionId='e'*32}
        'unfinished Vault'={param($f)$f.authority.guest.roleEvidence.markers[1].marker.state='STARTED'}
        'duplicate target'={param($f)$f.authority.guest.roleEvidence.requiredTargets[1]=$f.authority.guest.roleEvidence.requiredTargets[0]}
        'wrong role'={param($f)$f.authority.role='Primary / Desktop'}
        'wrong payload'={param($f)$f.authority.payloadSha256='e'*64}
        'missing reboot'={param($f)$f.authority.evidenceReferences=@()}
        'unchanged boot'={param($f)$f.generation.reboot.bootIdentityChanged=$false;WriteJson $f.generationPath $f.generation;$f.authority.evidenceReferences[0].sha256=(Get-FileHash -LiteralPath $f.generationPath).Hash.ToLowerInvariant()}
        'foreign checkpoint'={param($f)$f.generation.reboot.checkpoint.transactionId='e'*32;WriteJson $f.generationPath $f.generation;$f.authority.evidenceReferences[0].sha256=(Get-FileHash -LiteralPath $f.generationPath).Hash.ToLowerInvariant()}
        'generation hash drift'={param($f)$f.authority.evidenceReferences[0].sha256='e'*64}
    }
    foreach($case in $cases.GetEnumerator()){
        $fixture=NewFixture 'Laptop / Surrogate';& $case.Value $fixture;WriteJson $fixture.authority.evidencePath $fixture.authority
        $rejected=$false;try{New-DevFleetExactProofBinding -Context $fixture.context -PhaseResult $fixture.phase -ExpectedRole $fixture.role|Out-Null}catch{$rejected=$true}
        Check $rejected "rejects $($case.Key)"
    }
    [ordered]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failed)}|ConvertTo-Json
    if($failed.Count){exit 1}
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^devfleet-proof-binding-[a-f0-9]{32}$'){throw 'Proof fixture cleanup path rejected.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: automation/release-e2e/tests/Test-FinalConvergenceContracts.ps1

SHA256: 557e3f91c90bec1382730eeb603afccb0b77bbaf97478fa9d5afa44bf24801a5 | Bytes: 2859 | Git mode: 100644

```
[CmdletBinding()]
param([string]$Workspace = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
$finalizer = Get-Content -LiteralPath (Join-Path $Workspace 'tools\Invoke-DevFleetFinalConvergence.ps1') -Raw
$builder = Get-Content -LiteralPath (Join-Path $Workspace 'tools\Build-AIAuditBundle.ps1') -Raw
$entrypoint = Get-Content -LiteralPath (Join-Path $Workspace 'automation\release-e2e\Invoke-DevFleetReleaseE2E.ps1') -Raw
$checks = [ordered]@{
    proofExceptionHasFinally = ($finalizer -match 'StageScript' -and $finalizer -match 'finally\s*\{')
    fullReleaseExceptionCanBeWrapped = ($finalizer -match 'StageArgumentList' -and $entrypoint -match 'FullRelease')
    hostSafetyIsDiagnostic = ($finalizer -match 'TerminalMode' -and $finalizer -match 'BLOCKED')
    originalBlockerPreserved = ($finalizer -match 'primaryBlocker' -and $finalizer -match 'secondaryBlockers')
    idempotentTerminalChecks = ($finalizer -match 'Get-VM -Id' -and $finalizer -match 'Get-DevFleetHostNameExclusion' -and $finalizer -match 'exact L1')
    hostL2CheckRemainsHostScoped = ($finalizer -match 'host Hyper-V exact-name exclusion only' -and $finalizer -match 'Get-CurrentNestedL2ReleaseEvidence' -and $finalizer -match 'No validated current RunId-bound nested L1 inventory')
    preservesCurrentCandidateBinding = ($finalizer -match 'function Test-CandidateEvidenceRefreshRequired' -and $finalizer -match 'Test-CandidateEvidenceRefreshRequired\s+-State\s+\$stateBeforeRefresh')
    noCredentials = ($finalizer -match 'credentialValuesIncluded\s*=\s*\$false' -and $finalizer -match 'hostAgentSecretsIncluded\s*=\s*\$false' -and $finalizer -match 'REDACTED')
    exactL1Only = ($finalizer -match '84b7d8b8-ee6c-4085-aa29-4b0adc316de2' -and $finalizer -match 'DevFleet-E2E-Win11-01' -and $finalizer -match 'L1Touched')
    protectedNamesRejected = ($finalizer -match 'L2Name' -and $finalizer -match 'no deletion or adoption')
    l2AbsenceRecorded = ($finalizer -match 'l2ExactAbsent' -and $finalizer -match 'FINALIZER-TERMINAL-STATE')
    passVsDiagnosticMode = ($finalizer -match "'PASS','BLOCKED'" -and $finalizer -match "'diagnostic'" -and $finalizer -match "'release'")
    sidecarLast = ($builder -match 'outer sidecar is the final filesystem write' -and $builder -notmatch 'Set-Content -LiteralPath \$sidecarPath[\s\S]{0,300}Write-Json \$manifestPath')
    zipNotMutatedAfterSidecar = ($finalizer -match 'No ZIP write occurs after this point' -and $builder -match 'ZIP is never modified after this point')
}
$failed = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value } | ForEach-Object Key)
$result = [ordered]@{status=if($failed.Count -eq 0){'PASS'}else{'FAIL'};passed=($checks.Count-$failed.Count);total=$checks.Count;checks=$checks;failures=$failed}
$result | ConvertTo-Json -Depth 8
if ($failed.Count) { exit 1 }

```


## FILE: automation/release-e2e/tests/Test-FinalizerNestedTerminalEvidence.ps1

SHA256: a78208e93eef8365812a0e7979ab60eae65ad4fc23c44c871ddddc67af813f74 | Bytes: 14844 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$source = Join-Path $WorkspaceRoot 'tools\Invoke-DevFleetFinalConvergence.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count) { throw 'Native finalizer source does not parse.' }
$cleanupSource=Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Cleanup.psm1'
$cleanupTokens=$null;$cleanupErrors=$null
$cleanupAst=[Management.Automation.Language.Parser]::ParseFile($cleanupSource,[ref]$cleanupTokens,[ref]$cleanupErrors)
if(@($cleanupErrors).Count){throw 'Native cleanup module does not parse.'}
$hostGuardAst=@($cleanupAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-DevFleetHostNameExclusion'},$true))
if($hostGuardAst.Count -ne 1){throw 'Expected the exact production host exclusion function.'}
. ([scriptblock]::Create($hostGuardAst[0].Extent.Text))
foreach ($name in @('Add-SecondaryError', 'Get-SafeError', 'Get-CurrentNestedL2ReleaseEvidence', 'Merge-FinalizerTerminalOutcome', 'Invoke-ExactTerminalCleanup')) {
    $functionAst = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
    if ($functionAst.Count -ne 1) { throw "Expected one production $name function." }
    . ([scriptblock]::Create($functionAst[0].Extent.Text))
}

$L1Id = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$L1Name = 'DevFleet-E2E-Win11-01'
$L2Name = 'DevFleet-E2E-Linux-01'
$Workspace = $WorkspaceRoot
$evidence = Join-Path $WorkspaceRoot 'evidence'
$RunId = $null
$RunDirectory = $null
$SkipLiveCleanup = $false
$L1Touched = $false
$secondaryErrors = [Collections.Generic.List[string]]::new()

function Get-VM {
    [CmdletBinding()]
    param([guid]$Id, [string]$Name)
    if ($PSBoundParameters.ContainsKey('Id')) {
        return [pscustomobject]@{ Name=$script:L1Name; Id=$script:L1Id; State='Off' }
    }
    $script:hostQueries++
    if ($script:case -eq 'denied-host-query') { Write-Error 'Mock host inventory unavailable'; return }
    if ($script:case -eq 'present-host-name') { return [pscustomobject]@{ Name=$script:L2Name; Id=[guid]::NewGuid(); State='Off' } }
    if ($script:case -eq 'native-host-name-absence') {
        $message='Hyper-V was unable to find a virtual machine with name "'+$script:L2Name+'".'
        $record=[Management.Automation.ErrorRecord]::new([ArgumentException]::new($message),'InvalidParameter,Microsoft.HyperV.PowerShell.Commands.GetVM',[Management.Automation.ErrorCategory]::InvalidArgument,$script:L2Name)
        throw $record
    }
}

function Stop-VM { throw 'Unexpected VM mutation in VM-free terminal evidence test.' }

$cases = @('empty-host-inventory', 'denied-host-query', 'present-host-name', 'native-host-name-absence')
$rows = [Collections.Generic.List[object]]::new()
foreach ($script:case in $cases) {
    $script:hostQueries = 0
    $actual = Invoke-ExactTerminalCleanup
    $safe = ([string]$actual.status -cne 'PASS' -and [string]$actual.l2State -cne 'ABSENT' -and $actual.l2ExactAbsent -ne $true)
    $rows.Add([ordered]@{
        case=$script:case
        status=[string]$actual.status
        l2State=[string]$actual.l2State
        l2ExactAbsent=$actual.l2ExactAbsent
        hostQueries=$script:hostQueries
        nestedQueries=0
        safeWithoutNestedEvidence=$safe
        hostL2Excluded=$actual.hostL2Excluded
        hostAbsenceDidNotClaimNestedAbsent=([string]$actual.status -ceq 'BLOCKED' -and [string]$actual.l2State -ceq 'UNVERIFIED' -and $actual.l2ExactAbsent -ne $true)
        nativeHostAbsenceClassified=($script:case -ne 'native-host-name-absence' -or ($actual.hostL2Excluded -eq $true -and [string]$actual.l2Error -notmatch 'unable to find a virtual machine'))
    })
}
$blockedMerge=Merge-FinalizerTerminalOutcome -CurrentStatus 'PASS' -PrimaryBlocker '' -PrimaryBlockerClassification '' -SecondaryErrors @() -Terminal ([pscustomobject]@{status='BLOCKED';l2Error='nested proof unavailable'})
$rows.Add([ordered]@{case='outer-finalizer-propagates-terminal-block';status=$blockedMerge.status;l2State='UNVERIFIED';safeWithoutNestedEvidence=([string]$blockedMerge.status -ceq 'BLOCKED' -and [string]$blockedMerge.primaryBlocker -ceq 'nested proof unavailable')})
$preservedMerge=Merge-FinalizerTerminalOutcome -CurrentStatus 'PASS' -PrimaryBlocker 'original stage failure' -PrimaryBlockerClassification 'BLOCKED — PRODUCT' -SecondaryErrors @() -Terminal ([pscustomobject]@{status='BLOCKED';l2Error='nested cleanup failed'})
$rows.Add([ordered]@{case='outer-finalizer-preserves-primary-failure';status=$preservedMerge.status;l2State='UNVERIFIED';safeWithoutNestedEvidence=([string]$preservedMerge.status -ceq 'BLOCKED' -and [string]$preservedMerge.primaryBlocker -ceq 'original stage failure' -and @($preservedMerge.secondaryErrors).Count -eq 1)})

$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-finalizer-nested-proof-'+[guid]::NewGuid().ToString('N'))
$fixtureRunId='fullrelease-fixture-run'
$fixtureRun=Join-Path $fixtureRoot (Join-Path 'audit/automation-harness/runs' $fixtureRunId)
New-Item -ItemType Directory -Path $fixtureRun -Force|Out-Null
function Write-FixtureJson([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))}
function Get-FixtureHash([string]$Path){([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path)))).ToLowerInvariant()}
function Invoke-FixtureNestedValidation([string]$Root,[string]$RunId){
    $script:Workspace=$Root
    $script:RunDirectory=Join-Path $Root (Join-Path 'audit/automation-harness/runs' $RunId)
    Get-CurrentNestedL2ReleaseEvidence -ExpectedRunId $RunId -RunDirectory $script:RunDirectory
}
try{
    $tuple=[ordered]@{repositoryHead=('a'*40);candidateCommit=('b'*40);shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64)}
    $observed='2026-09-24T00:00:01Z';$l1Observed='2026-09-24T00:00:02Z'
    $nestedFixture=[ordered]@{schemaVersion=1;runId=$fixtureRunId;status='ABSENT';expectedName=$L2Name;present=$false;observedUtc=$observed;verification='Bounded Multipass JSON inventory inside exact L1';exactMatchCount=0;inventoryCount=0;backendInventories=@();candidate=$tuple;l1=[ordered]@{name=$L1Name;id=$L1Id.ToString()};nestedScope='inside the exact L1 guest session';observer='Get-DevFleetNestedL2State';evidenceClass='FullRelease run-bound nested observation'}
    $nestedPath=Join-Path $fixtureRun 'nested-l2-terminal-observation.json';Write-FixtureJson $nestedPath $nestedFixture;$nestedHash=Get-FixtureHash $nestedPath
    $cleanupFixture=[ordered]@{schemaVersion=1;status='PASS';runId=$fixtureRunId;candidate=$tuple;l1=[ordered]@{state='Off'};guest=[ordered]@{runRootAbsent=$true;nestedAbsent=$true;foreignResourcesMutated=$false}}
    $cleanupPath=Join-Path $fixtureRun 'final-cleanup.json';Write-FixtureJson $cleanupPath $cleanupFixture
    $l1Fixture=[ordered]@{name=$L1Name;id=$L1Id.ToString();state='Off';timestampUtc=$l1Observed;runId=$fixtureRunId}
    $l1Path=Join-Path $fixtureRun 'l1-terminal-state.json';Write-FixtureJson $l1Path $l1Fixture
    $l2Fixture=[ordered]@{schemaVersion=2;expectedName=$L2Name;status='ABSENT';present=$false;timestampUtc=$observed;verificationMethod=$nestedFixture.verification;nestedScope=$nestedFixture.nestedScope;backendInventories=@();runId=$fixtureRunId;sourceRunId=$fixtureRunId;sourceEvidence='nested-l2-terminal-observation.json';sourceEvidenceSha256=$nestedHash;l1Name=$L1Name;l1Id=$L1Id.ToString();candidate=$tuple;evidenceClass='FullRelease run-bound nested observation'}
    $l2Path=Join-Path $fixtureRun 'l2-terminal-state.json';Write-FixtureJson $l2Path $l2Fixture
    $phasePath=Join-Path $fixtureRun 'fullrelease-phase-records.json';Write-FixtureJson $phasePath @([ordered]@{id='CLEANUP';status='PASS'})
    $stateFixture=[ordered]@{runId=$fixtureRunId;mode='FullRelease';finalStatus='PASS';candidateHashes=$tuple};$statePath=Join-Path $fixtureRun 'run-state.json';Write-FixtureJson $statePath $stateFixture
    $postFixture=[ordered]@{status='PASS';runId=$fixtureRunId;cleanupConsumed=$true;candidate=$tuple;liveChecks=[ordered]@{l1ExactOff=$true;l2ExactAbsent=$true;hostSameNameL2Absent=$true;foreignResourcesMutated=$false};cleanupEvidenceHash=(Get-FixtureHash $cleanupPath);terminalL1='l1-terminal-state.json';terminalL1Hash=(Get-FixtureHash $l1Path);terminalL2='l2-terminal-state.json';terminalL2Hash=(Get-FixtureHash $l2Path);nestedL2Observation='nested-l2-terminal-observation.json';nestedL2ObservationSha256=$nestedHash}
    $postPath=Join-Path $fixtureRun 'post-cleanup-finalization.json';Write-FixtureJson $postPath $postFixture
    $accepted=Invoke-FixtureNestedValidation -Root $fixtureRoot -RunId $fixtureRunId
    $rows.Add([ordered]@{case='complete-current-run-nested-provenance-accepted';status='PASS';l2State=[string]$accepted.terminalL2.status;safeWithoutNestedEvidence=([string]$accepted.terminalL2.status -ceq 'ABSENT' -and [string]$accepted.runId -ceq $fixtureRunId -and [string]$accepted.sourceEvidenceSha256 -ceq $nestedHash)})

    $nestedFixture.candidate=[ordered]@{};$l2Fixture.candidate=[ordered]@{};$cleanupFixture.candidate=[ordered]@{};$postFixture.candidate=[ordered]@{};$stateFixture.candidateHashes=[ordered]@{}
    Write-FixtureJson $nestedPath $nestedFixture;$nestedHash=Get-FixtureHash $nestedPath
    $l2Fixture.sourceEvidenceSha256=$nestedHash;Write-FixtureJson $l2Path $l2Fixture
    Write-FixtureJson $cleanupPath $cleanupFixture;Write-FixtureJson $statePath $stateFixture
    $postFixture.cleanupEvidenceHash=Get-FixtureHash $cleanupPath;$postF