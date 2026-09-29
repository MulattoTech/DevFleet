# DevFleet source part 010

Full-source UTF-8 byte interval [418500, 465000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 6e1def3de84d9d8b4553e0aca76f635b1e6d5f53ca498ac91dc831e5006c65fe

<!-- BEGIN SOURCE SLICE -->
er-gt[datetime]::MinValue){$owner.ToString('o')}else{''};producedAtUtc=[datetime]::UtcNow.ToString('o');multipassSha256=$multipassSha;launchCallStarted=[bool]$launchState.callStarted;experiment=if($productLaunch){'M3'}elseif($profile){'M2'}else{'M1'};executionContext=$workerContext;productProfile=$profile;backendBefore=$backendBefore;backendBeforeCleanup=$backendAfter;backendAfterCleanup=$backendFinal;boundaryBefore=$boundaryBefore;preflight=$preflight;sequence=$sequence;cleanup=$cleanup;boundaryAfter=$boundaryAfter;primaryError=$primaryError;productLifecycleStarted=$false;productProgressClaimed=$false}
    if($resultPath-and(Test-Path -LiteralPath $remoteRoot -PathType Container)){try{Write-FreshAtomicJson -Path $resultPath -Value $result}catch{}}
    [Console]::Out.Write(($result|ConvertTo-Json -Depth 24 -Compress))
}
if([string]$result.status-cne'PASS_DIAGNOSTIC'){exit 1}

```


## FILE: automation/release-e2e/Invoke-CampaignEPrerequisiteCheckpoint.ps1

SHA256: 2015812621faeada41d077fbd7cc67390b6c62aef05aaf46f274c9c0ec56add5 | Bytes: 24650 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
    [ValidateRange(1800,3600)][int]$OwnerSeconds=2400
)

$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$vmName='DevFleet-E2E-Win11-01'
$cleanId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'
$cleanName='DevFleet-E2E-CLEAN'
$l2Name='DevFleet-E2E-Linux-01'
$runDir=Join-Path $root "audit\automation-harness\runs\$RunId"
$remoteRoot="C:\Users\Public\DevFleet-E2E\$RunId\Prerequisite"
$checkpointName="DevFleet-E2E-E-PREREQ-$($RunId.ToUpperInvariant())"
$ownerDeadline=[datetime]::UtcNow.AddSeconds($OwnerSeconds)
$deadlinePartition=$null
$terminalizationDeadline=$ownerDeadline.AddSeconds(300)
$stagingNonce=[guid]::NewGuid()
$powerShellPayloadTempRoot=$null
$powerShellPayloadTempOwned=$false

foreach($module in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic')){Import-Module (Join-Path $root "automation\release-e2e\modules\$module.psm1") -Force}

$result=[ordered]@{
    schemaVersion=1;campaign='DF-STABLE-20260906-E';experiment='PREREQUISITE_CHECKPOINT_PREP';status='RESERVED';certificationEligible=$false;proofCredit=$false;runId=$RunId
    startedAtUtc=[datetime]::UtcNow.ToString('o');ownerDeadlineUtc=$ownerDeadline.ToString('o');exactL1=[ordered]@{name=$vmName;id=$vmId.ToString()};sourceCheckpoint=[ordered]@{name=$cleanName;id=$cleanId.ToString()}
    requestedCheckpointName=$checkpointName;cleanupOwner='Invoke-CampaignEPrerequisiteCheckpoint.ps1';diagnosticDeviation='Stages an allowlisted official PowerShell MSI selected by the exact candidate GitHub resolver and Microsoft signer policy, installs candidate-required Multipass through candidate dependency policy, configures Hyper-V/no privileged mounts, and never starts a product transaction or writes a product stage marker.'
}
$session=$null;$restored=$false;$checkpoint=$null;$workerPassed=$false;$stagingOwned=$false;$initialVmState=$null
try {
    New-Item -ItemType Directory -Path $runDir -Force|Out-Null
    Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-prerequisite-checkpoint.json') -Value $result
    $vm=Get-VM -Id $vmId -ErrorAction Stop
    if([string]$vm.Name-cne$vmName-or$vm.Id-ne$vmId){throw 'Campaign E prerequisite exact L1 identity mismatch.'}
    Assert-DisposableOwnership -Vm $vm -ExpectedId $vmId.ToString()|Out-Null
    $initialVmState=[string]$vm.State
    if($initialVmState-cne'Off'){throw "Campaign E prerequisite preparation will not acquire an already-running L1; observed state $initialVmState."}
    $clean=@(Get-VMSnapshot -VM $vm -ErrorAction Stop|Where-Object{$_.Name-ceq$cleanName-and$_.Id-eq$cleanId})
    if($clean.Count-ne1){throw 'Campaign E prerequisite canonical CLEAN name/GUID binding failed.'}
    if(@(Get-VMSnapshot -VM $vm -ErrorAction Stop|Where-Object{$_.Name-ceq$checkpointName}).Count){throw 'Campaign E prerequisite checkpoint name already exists.'}
    $safety=Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB 14.38
    $result.hostSafety=[ordered]@{status=if([bool]$safety.startSafe){'PASS'}else{'BLOCKED'};startSafe=[bool]$safety.startSafe;resourceExhaustion=[bool]$safety.resourceExhaustion;availableMemoryGiB=[double]$safety.availableMemoryGiB;projectedPostStartAvailableMemoryGiB=[double]$safety.projectedPostStartAvailableMemoryGiB;observedAtUtc=[datetime]::UtcNow.ToString('o')}
    if(-not[bool]$safety.startSafe){throw 'BLOCKED - HOST-SAFETY startSafe=false.'}
    $fingerprint=Get-CandidateFingerprint -WorkspaceRoot $root
    $authority=Get-Content -LiteralPath (Join-Path $root 'evidence\CURRENT-RELEASE-AUTHORITY.json') -Raw|ConvertFrom-Json -ErrorAction Stop
    if(-not[bool]$authority.candidateIsCurrent-or[bool]$authority.sourceChangedSinceCandidate-or[bool]$authority.rebuildRequired){throw 'Campaign E prerequisite preparation requires a coherent current candidate.'}
    $repositoryHead=(&git -C $root rev-parse HEAD).Trim()
    if([string]$authority.repositoryHead-cne$repositoryHead-or[string]$authority.candidateCommit-cne[string]$fingerprint.gitCommit-or[string]$authority.shippingInputIdentity-cne[string]$fingerprint.shippingInputIdentity-or[string]$authority.releaseFingerprintId-cne[string]$fingerprint.releaseFingerprintId-or[string]$authority.toolingFingerprintId-cne[string]$fingerprint.toolingFingerprintId){throw 'Campaign E prerequisite current authority/fingerprint tuple mismatch.'}
    $plan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot (Join-Path $root 'source') -Role Desktop
    $manifest=Get-Content -LiteralPath (Join-Path $root 'source\dependencies.json') -Raw|ConvertFrom-Json -ErrorAction Stop
    $powerShellDependencies=@($manifest.dependencies|Where-Object{[string]$_.id-ceq'powershell7'})
    if($powerShellDependencies.Count-ne1){throw 'Campaign E host payload preparation requires one PowerShell dependency.'}
    $powerShellPayloadTempRoot=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-e-powershell-$RunId-$($stagingNonce.ToString('N'))")
    if(Test-Path -LiteralPath $powerShellPayloadTempRoot){throw 'Campaign E host payload staging path already exists.'}
    New-Item -ItemType Directory -Path $powerShellPayloadTempRoot|Out-Null
    $hostPayloadOwner=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_HOST_PAYLOAD_OWNER';runId=$RunId;nonce=$stagingNonce.ToString();createdAtUtc=[datetime]::UtcNow.ToString('o')}
    $hostPayloadOwner|ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $powerShellPayloadTempRoot '.owner.json') -Encoding UTF8
    $powerShellPayloadTempOwned=$true
    $powerShellPayload=Get-DevFleetCampaignEOfficialPowerShellPayload -Dependency $powerShellDependencies[0] -DestinationDirectory $powerShellPayloadTempRoot -OwnerDeadlineUtc $ownerDeadline
    $result.powerShellPayload=[ordered]@{schemaVersion=[int]$powerShellPayload.schemaVersion;kind=[string]$powerShellPayload.kind;status=[string]$powerShellPayload.status;method=[string]$powerShellPayload.method;packageId=[string]$powerShellPayload.packageId;releaseTag=[string]$powerShellPayload.releaseTag;assetName=[string]$powerShellPayload.assetName;metadataHost=[string]$powerShellPayload.metadataHost;assetHost=[string]$powerShellPayload.assetHost;redirectHosts=@($powerShellPayload.redirectHosts);sha256=[string]$powerShellPayload.sha256;bytes=[int64]$powerShellPayload.bytes;signerSubject=[string]$powerShellPayload.signerSubject;startedAtUtc=[string]$powerShellPayload.startedAtUtc;finishedAtUtc=[string]$powerShellPayload.finishedAtUtc;ownerDeadlineUtc=[string]$powerShellPayload.ownerDeadlineUtc;productLifecycleStarted=$false;stageMarkerWritten=$false}
    $deadlinePartition=Get-DevFleetCampaignEDeadlinePartition -OwnerDeadlineUtc $ownerDeadline -ReservedTerminalizationSeconds 300
    $childDeadline=([datetime]$deadlinePartition.childDeadlineUtc).ToUniversalTime()
    $terminalizationDeadline=([datetime]$deadlinePartition.terminalizationDeadlineUtc).ToUniversalTime()
    $result.deadlinePartition=$deadlinePartition
    $result.tuple=[ordered]@{repositoryHead=$repositoryHead;candidateCommit=[string]$fingerprint.gitCommit;shippingInputIdentity=[string]$fingerprint.shippingInputIdentity;releaseFingerprintId=[string]$fingerprint.releaseFingerprintId;toolingFingerprintId=[string]$fingerprint.toolingFingerprintId;candidateSha256=[string]$fingerprint.candidate.sha256;payloadSha256=[string]$fingerprint.tar.sha256}
    $result.plan=$plan
    $result.status='STARTING'
    Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-prerequisite-checkpoint.json') -Value $result
    $result.restore=Restore-ExactCheckpoint -Vm $vm -Name $cleanName -StartAfterRestore
    $restored=$true
    $session=Connect-DevFleetGuest -VmId $vmId
    $initialL2=Get-DevFleetNestedL2State -Session $session -ExpectedName $l2Name
    $result.initialL2=$initialL2
    if([string]$initialL2.status-cne'ABSENT'){throw "Campaign E prerequisite state requires exact initial L2 absence; observed $([string]$initialL2.status)."}
    $ownership=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 30 -ScriptBlock {param($Path,$RunId,$Nonce)if($Path-notlike'C:\Users\Public\DevFleet-E2E\*\Prerequisite'){throw 'Remote prerequisite staging path is outside the run-owned boundary.'};if(Test-Path -LiteralPath $Path){throw 'Remote prerequisite staging path already exists and will not be adopted or deleted.'};New-Item -ItemType Directory -Path $Path|Out-Null;$record=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_STAGING_OWNER';runId=$RunId;nonce=$Nonce;createdAtUtc=[datetime]::UtcNow.ToString('o')};$record|ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $Path '.owner.json') -Encoding UTF8;[pscustomobject]$record} -ArgumentList @($remoteRoot,$RunId,$stagingNonce.ToString()))|Select-Object -Last 1
    Assert-DevFleetCampaignEStagingOwnership -Record $ownership -ExpectedRunId $RunId -ExpectedNonce $stagingNonce|Out-Null
    $stagingOwned=$true
    $result.stagingOwnership=$ownership
    $files=[ordered]@{
        module=Join-Path $root 'automation\release-e2e\modules\MultipassDiagnostic.psm1'
        worker=Join-Path $root 'automation\release-e2e\Invoke-CampaignEPrerequisiteWorker.ps1'
        innerWorker=Join-Path $root 'automation\release-e2e\Invoke-CampaignEPrerequisitePwshWorker.ps1'
        candidateTar=[string]$fingerprint.tar.path
        powerShellPayload=[string]$powerShellPayload.localPath
    }
    $remote=[ordered]@{module=Join-Path $remoteRoot 'MultipassDiagnostic.psm1';worker=Join-Path $remoteRoot 'Invoke-CampaignEPrerequisiteWorker.ps1';innerWorker=Join-Path $remoteRoot 'Invoke-CampaignEPrerequisitePwshWorker.ps1';candidateTar=Join-Path $remoteRoot 'devfleet-v1.2.13.tar.gz';powerShellPayload=Join-Path $remoteRoot ([string]$powerShellPayload.assetName)}
    $result.stage=[ordered]@{}
    foreach($name in @('module','worker','innerWorker','candidateTar','powerShellPayload')){$result.stage[$name]=Copy-DevFleetBoundedGuestFile -LocalPath ([string]$files[$name]) -Session $session -RemotePath ([string]$remote[$name]) -TimeoutSeconds 120}
    $hostPayloadOwner=Get-Content -LiteralPath (Join-Path $powerShellPayloadTempRoot '.owner.json') -Raw|ConvertFrom-Json -ErrorAction Stop
    if([string]$hostPayloadOwner.kind-cne'DEVFLEET_CAMPAIGN_E_HOST_PAYLOAD_OWNER'-or[string]$hostPayloadOwner.runId-cne$RunId-or[guid][string]$hostPayloadOwner.nonce-ne$stagingNonce){throw 'Campaign E host payload cleanup ownership identity mismatch.'}
    Remove-Item -LiteralPath $powerShellPayloadTempRoot -Recurse -Force -ErrorAction Stop
    $powerShellPayloadTempOwned=$false;$result.hostPayloadCleanup='PASS'
    $request=[ordered]@{runId=$RunId;vmId=$vmId.ToString();remoteRoot=$remoteRoot;candidateTarPath=$remote.candidateTar;diagnosticModulePath=$remote.module;innerWorkerPath=$remote.innerWorker;powerShellPayloadPath=$remote.powerShellPayload;powerShellPayload=$result.powerShellPayload;role='Desktop';payloadSha256=[string]$fingerprint.tar.sha256;inputHashes=$plan.inputHashes;ownerDeadlineUnixMilliseconds=[DateTimeOffset]::new($childDeadline).ToUnixTimeMilliseconds()}|ConvertTo-Json -Depth 12 -Compress
    $requestBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))
    $remotePowerShell=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {$path=Join-Path $PSHOME 'powershell.exe';if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Windows PowerShell runtime is missing.'};$path})|Select-Object -Last 1
    $worker=Invoke-DevFleetBoundedGuestProcess -Session $session -FilePath ([string]$remotePowerShell) -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$remote.worker,'-RequestBase64',$requestBase64) -OwnerDeadlineUtc $childDeadline
    $result.worker=[ordered]@{outcome=[string]$worker.outcome;exitCode=$worker.exitCode;pid=$worker.pid;startedAtUtc=[string]$worker.startedAtUtc;finishedAtUtc=[string]$worker.finishedAtUtc;outputComplete=[bool]$worker.outputComplete;executionPolicyScope='PROCESS_ONLY';systemPolicyChanged=$false}
    $workerResult=$null
    if([string]$worker.outcome-ceq'PASS'){
        $durableResultPath=Join-Path $remoteRoot 'prerequisite-worker-result.json'
        $durableCollected=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {param($Path)if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Durable prerequisite worker result is missing.'};$raw=Get-Content -LiteralPath $Path -Raw;[pscustomobject]@{raw=$raw;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}} -ArgumentList @($durableResultPath))|Select-Object -Last 1
        $resolvedWorker=Resolve-DevFleetCampaignEWorkerResult -ProcessStdout ([string]$worker.stdout) -DurableRaw ([string]$durableCollected.raw)
        $workerResult=$resolvedWorker.value;$result.workerResultSource=[string]$resolvedWorker.source;$result.workerProcessStdoutStatus=[string]$resolvedWorker.processStdoutStatus;$result.workerResultSha256=[string]$durableCollected.sha256
    } elseif(-not[string]::IsNullOrWhiteSpace([string]$worker.stdout)){try{$workerResult=[string]$worker.stdout|ConvertFrom-Json -ErrorAction Stop}catch{}}
    if($workerResult-and[string]$workerResult.kind-ceq'DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY'){$result.prerequisite=$workerResult}
    elseif($workerResult-and[string]$workerResult.kind-ceq'DEVFLEET_CAMPAIGN_E_PREREQUISITE_FAILURE'){Assert-DevFleetCampaignEPrerequisiteFailure -Failure $workerResult -ExpectedRunId $RunId -ExpectedVmId $vmId -ExpectedPayloadSha256 ([string]$fingerprint.tar.sha256)|Out-Null;$result.prerequisiteFailure=$workerResult}
    if([string]$worker.outcome-cne'PASS'){
        try {
            $failurePath=Join-Path $remoteRoot 'prerequisite-failure.json'
            $collected=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {param($Path)if(Test-Path -LiteralPath $Path -PathType Leaf){$raw=Get-Content -LiteralPath $Path -Raw;[pscustomobject]@{raw=$raw;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}}} -ArgumentList @($failurePath))|Select-Object -Last 1
            if($collected-and-not[string]::IsNullOrWhiteSpace([string]$collected.raw)){
                $failure=[string]$collected.raw|ConvertFrom-Json -ErrorAction Stop
                Assert-DevFleetCampaignEPrerequisiteFailure -Failure $failure -ExpectedRunId $RunId -ExpectedVmId $vmId -ExpectedPayloadSha256 ([string]$fingerprint.tar.sha256)|Out-Null
                $result.prerequisiteFailure=$failure;$result.prerequisiteFailureSha256=[string]$collected.sha256
            } elseif(-not$result.Contains('prerequisiteFailure')){throw 'Run-bound prerequisite failure record was not available.'}
        } catch {$result.prerequisiteFailureCollectionError=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 512}
        throw "Campaign E prerequisite worker failed: $(ConvertTo-DevFleetDiagnosticSafeText $worker.stderr 1024)"
    }
    if(-not$workerResult){throw 'Campaign E prerequisite worker returned malformed or empty JSON.'}
    $finalL2=Get-DevFleetNestedL2State -Session $session -ExpectedName $l2Name
    $result.finalL2=$finalL2
    $workerResult.l2Status=[string]$finalL2.status
    Assert-DevFleetCampaignEPrerequisiteResult -Result $workerResult -ExpectedRunId $RunId -ExpectedVmId $vmId -ExpectedPayloadSha256 ([string]$fingerprint.tar.sha256) -ExpectedPlan $plan|Out-Null
    $boundary=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 30 -ScriptBlock {
        $root=Join-Path $env:ProgramData 'DevFleet'
        [pscustomobject]@{activeTransactionPresent=Test-Path -LiteralPath (Join-Path $root 'active-transaction.json') -PathType Leaf;stageMarkerCount=@(Get-ChildItem -LiteralPath $root -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue).Count;activeInstallProcessCount=@(Get-CimInstance Win32_Process|Where-Object{[string]$_.Name-in@('DevFleet.Setup.exe','pwsh.exe','powershell.exe','winget.exe','msiexec.exe')-and[string]$_.CommandLine-match'(?i)DevFleet|Canonical.Multipass|Microsoft.PowerShell'}).Count}
    })|Select-Object -Last 1
    $result.quiescence=$boundary
    if([bool]$boundary.activeTransactionPresent-or[int]$boundary.stageMarkerCount-ne0-or[int]$boundary.activeInstallProcessCount-ne0){throw 'Campaign E prerequisite preparation did not reach quiescence.'}
    $workerPassed=$true
    $result.status='PREREQUISITES_READY'
} catch {
    $result.status='BLOCKED'
    $result.primaryError=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 1024
} finally {
    if($session){
        if(-not$result.Contains('finalL2')){try{$result.finalL2=Get-DevFleetNestedL2State -Session $session -ExpectedName $l2Name}catch{$result.finalL2=[ordered]@{status='UNVERIFIED';expectedName=$l2Name;verification=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)}}}
        if($stagingOwned){try{$cleanupSeconds=[int][math]::Max(1,[math]::Min(60,[math]::Floor(($terminalizationDeadline-[datetime]::UtcNow).TotalSeconds)));$null=Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds $cleanupSeconds -ScriptBlock {param($Path,$RunId,$Nonce)if($Path-notlike'C:\Users\Public\DevFleet-E2E\*\Prerequisite'){throw 'Remote prerequisite cleanup path is outside the run-owned boundary.'};$ownerPath=Join-Path $Path '.owner.json';if(-not(Test-Path -LiteralPath $ownerPath -PathType Leaf)){throw 'Remote prerequisite cleanup ownership record is missing.'};$owner=Get-Content -LiteralPath $ownerPath -Raw|ConvertFrom-Json;if([string]$owner.runId-cne$RunId-or[guid][string]$owner.nonce-ne[guid]$Nonce){throw 'Remote prerequisite cleanup ownership identity mismatch.'};Remove-Item -LiteralPath $Path -Recurse -Force} -ArgumentList @($remoteRoot,$RunId,$stagingNonce.ToString());$result.stagingCleanup='PASS'}catch{$result.stagingCleanup='UNVERIFIED'}}else{$result.stagingCleanup='NOT_OWNED_NOT_TOUCHED'}
        Remove-PSSession $session -ErrorAction SilentlyContinue;$session=$null
    } elseif($restored) {$result.finalL2=[ordered]@{status='UNVERIFIED';expectedName=$l2Name;verification='No bounded in-L1 backend inventory was available before final stop.'}}
    if(-not$restored){
        try{$observed=Get-VM -Id $vmId -ErrorAction Stop;$result.finalL1=[ordered]@{status=[string]$observed.State;name=$observed.Name;id=$observed.Id.ToString();preservedInitialState=([string]$observed.State-ceq$initialVmState);observedAtUtc=[datetime]::UtcNow.ToString('o')}}catch{$result.finalL1=[ordered]@{status='UNVERIFIED';error=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message);observedAtUtc=[datetime]::UtcNow.ToString('o')}}
    } else { try {
        $finalVm=Get-VM -Id $vmId -ErrorAction Stop
        if([string]$finalVm.Name-cne$vmName-or$finalVm.Id-ne$vmId){throw 'Campaign E prerequisite final L1 identity mismatch.'}
        if($finalVm.State-ne'Off'){Stop-VM -VM $finalVm -Force -Confirm:$false -ErrorAction Stop}
        $stopDeadline=(@([datetime]::UtcNow.AddMinutes(2),$terminalizationDeadline)|Measure-Object -Minimum).Minimum
        do{$finalVm=Get-VM -Id $vmId -ErrorAction Stop;if($finalVm.State-eq'Off'){break};Start-Sleep -Seconds 2}while([datetime]::UtcNow-lt$stopDeadline)
        if($finalVm.State-ne'Off'){throw 'Exact L1 did not reach OFF before prerequisite checkpoint decision.'}
        if($workerPassed-and[string]$result.finalL2.status-ceq'ABSENT'-and[string]$result.stagingCleanup-ceq'PASS'-and[string]$result.hostPayloadCleanup-ceq'PASS'){
            $checkpointRemaining=[int][math]::Floor(($ownerDeadline-[datetime]::UtcNow).TotalSeconds)
            if($checkpointRemaining-lt120){throw 'Campaign E prerequisite owner deadline cannot provide a safe checkpoint-creation window.'}
            Checkpoint-VM -VM $finalVm -SnapshotName $checkpointName -ErrorAction Stop|Out-Null
            if([datetime]::UtcNow-ge$ownerDeadline){throw 'Campaign E prerequisite checkpoint operation crossed the immutable owner deadline.'}
            $checkpointDeadline=(@([datetime]::UtcNow.AddMinutes(3),$ownerDeadline)|Measure-Object -Minimum).Minimum
            do{$matches=@(Get-VMSnapshot -VM $finalVm -ErrorAction Stop|Where-Object{$_.Name-ceq$checkpointName});if($matches.Count-eq1){$checkpoint=$matches[0];break};Start-Sleep -Seconds 2}while([datetime]::UtcNow-lt$checkpointDeadline)
            if(-not$checkpoint-or$checkpoint.Id-eq$cleanId-or$checkpoint.VMId-ne$vmId-or$checkpoint.ParentSnapshotId-ne$cleanId){throw 'Campaign E prerequisite checkpoint identity/parent binding failed.'}
            $result.diagnosticCheckpoint=[ordered]@{name=$checkpoint.Name;id=$checkpoint.Id.ToString();vmId=$checkpoint.VMId.ToString();parentSnapshotId=$checkpoint.ParentSnapshotId.ToString();sourceCleanName=$cleanName;sourceCleanId=$cleanId.ToString();createdAtUtc=([datetime]$checkpoint.CreationTime).ToUniversalTime().ToString('o');l1State='OFF';l2Status='ABSENT';payloadSha256=[string]$result.tuple.payloadSha256;inputHashes=$result.plan.inputHashes;officialPowerShellPayload=$result.powerShellPayload;powershellAcquisition=$result.prerequisite.powershellAcquisition;powershell=$result.prerequisite.powershell;multipass=$result.prerequisite.multipass;backend=$result.prerequisite.backend}
            $result.status='PASS_CHECKPOINT_READY'
        } elseif($restored) {
            $restore=Restore-ExactCheckpoint -Vm $finalVm -Name $cleanName
            $result.failureRestore=[ordered]@{status='PASS';checkpoint=$restore;note='Canonical CLEAN restored after unsuccessful prerequisite preparation.'}
        }
        $observed=Get-VM -Id $vmId -ErrorAction Stop
        $result.finalL1=[ordered]@{status=if($observed.State-eq'Off'){'OFF'}else{'UNVERIFIED'};name=$observed.Name;id=$observed.Id.ToString();observedAtUtc=[datetime]::UtcNow.ToString('o')}
    } catch {
        if(-not$checkpoint){$created=@(Get-VMSnapshot -VM $finalVm -ErrorAction SilentlyContinue|Where-Object{$_.Name-ceq$checkpointName});if($created.Count-eq1){$checkpoint=$created[0]}}
        if($checkpoint){try{Remove-VMSnapshot -VMSnapshot $checkpoint -Confirm:$false -ErrorAction Stop;$result.failedCheckpointRemoval='PASS'}catch{$result.failedCheckpointRemoval='UNVERIFIED'}}
        try{$current=Get-VM -Id $vmId -ErrorAction Stop;if($current.State-ne'Off'){Stop-VM -VM $current -Force -Confirm:$false -ErrorAction Stop};$restore=Restore-ExactCheckpoint -Vm $current -Name $cleanName;$result.failureRestore=[ordered]@{status='PASS';checkpoint=$restore;note='Canonical CLEAN restored after unsuccessful checkpoint terminalization.'}}catch{$result.failureRestore=[ordered]@{status='UNVERIFIED';error=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)}}
        $result.status='BLOCKED';if(-not$result.Contains('primaryError')){$result.primaryError=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 1024}
        try{$observed=Get-VM -Id $vmId -ErrorAction Stop;$result.finalL1=[ordered]@{status=if($observed.State-eq'Off'){'OFF'}else{'UNVERIFIED'};name=$observed.Name;id=$observed.Id.ToString();observedAtUtc=[datetime]::UtcNow.ToString('o')}}catch{$result.finalL1=[ordered]@{status='UNVERIFIED';error=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message);observedAtUtc=[datetime]::UtcNow.ToString('o')}}
    }}
    if([string]$result.status-ceq'PASS_CHECKPOINT_READY'-and([string]$result.finalL1.status-cne'OFF'-or[string]$result.finalL2.status-cne'ABSENT')){$result.status='BLOCKED'}
    $result.completedAtUtc=[datetime]::UtcNow.ToString('o')
    $result.terminalizationExceeded=([datetime]::UtcNow-gt$terminalizationDeadline)
    if($powerShellPayloadTempOwned-and$powerShellPayloadTempRoot-and(Test-Path -LiteralPath $powerShellPayloadTempRoot)){
        try{$owner=Get-Content -LiteralPath (Join-Path $powerShellPayloadTempRoot '.owner.json') -Raw|ConvertFrom-Json -ErrorAction Stop;if([string]$owner.kind-cne'DEVFLEET_CAMPAIGN_E_HOST_PAYLOAD_OWNER'-or[string]$owner.runId-cne$RunId-or[guid][string]$owner.nonce-ne$stagingNonce){throw 'Campaign E host payload cleanup ownership identity mismatch.'};Remove-Item -LiteralPath $powerShellPayloadTempRoot -Recurse -Force -ErrorAction Stop;$result.hostPayloadCleanup='PASS'}catch{$result.hostPayloadCleanup='UNVERIFIED'}
    } elseif(-not$result.Contains('hostPayloadCleanup')) {$result.hostPayloadCleanup='NOT_OWNED_NOT_TOUCHED'}
    Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-prerequisite-checkpoint.json') -Value $result
}

[pscustomobject]$result
if([string]$result.status-cne'PASS_CHECKPOINT_READY'){exit 1}

```


## FILE: automation/release-e2e/Invoke-CampaignEPrerequisitePwshWorker.ps1

SHA256: dcd16eb713aef8bdd6b428bc8cac82081ec1b976e6aa8a286f546a51fd2e9b6c | Bytes: 11582 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9+/=]+$')][string]$RequestBase64
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Write-AtomicJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 16 -Compress))
        [IO.File]::WriteAllBytes($temporary,$bytes)
        [IO.File]::Move($temporary,$Path,$true)
    } finally {Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
}

function Get-ActiveBoundary {
    $root=Join-Path $env:ProgramData 'DevFleet'
    [ordered]@{
        activeTransactionPresent=Test-Path -LiteralPath (Join-Path $root 'active-transaction.json') -PathType Leaf
        stageMarkerCount=@(Get-ChildItem -LiteralPath $root -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue).Count
        activeInstallProcessCount=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{[string]$_.Name-in@('DevFleet.Setup.exe','pwsh.exe','powershell.exe')-and[string]$_.CommandLine-match'(?i)Install-DevFleet|Bootstrap-Install|DevFleet.Setup'}).Count
    }
}

try {
    $requestJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))
    $request=$requestJson|ConvertFrom-Json -ErrorAction Stop
    if([string]$request.runId-notmatch'^[A-Za-z0-9._-]+$'){throw 'Campaign E prerequisite run identity is invalid.'}
    $remoteRoot=[IO.Path]::GetFullPath([string]$request.remoteRoot).TrimEnd('\')
    if($remoteRoot-notlike'C:\Users\Public\DevFleet-E2E\*\Prerequisite'){throw 'Campaign E prerequisite root is outside the run-owned boundary.'}
    $packageRoot=[IO.Path]::GetFullPath([string]$request.packageRoot).TrimEnd('\')
    $resultPath=[IO.Path]::GetFullPath([string]$request.resultPath)
    if(-not$packageRoot.StartsWith($remoteRoot+'\',[StringComparison]::OrdinalIgnoreCase)-or-not$resultPath.StartsWith($remoteRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Campaign E prerequisite worker path escaped the run-owned root.'}
    $ownerDeadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.ownerDeadlineUnixMilliseconds).UtcDateTime
    $started=[datetime]::UtcNow
    if($ownerDeadline-le$started){throw 'Campaign E prerequisite owner deadline expired before the PowerShell worker.'}
    $commonPath=Join-Path $packageRoot 'windows\DevFleet.Common.psm1'
    $diagnosticModule=[IO.Path]::GetFullPath([string]$request.diagnosticModulePath)
    if(-not$diagnosticModule.StartsWith($remoteRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Campaign E diagnostic module path escaped the run-owned root.'}
    Import-Module $commonPath -Force -ErrorAction Stop
    Import-Module $diagnosticModule -Force -ErrorAction Stop
    Assert-PowerShell7
    Assert-Administrator
    $plan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot $packageRoot -Role ([string]$request.role)
    foreach($name in @('version','dependencies','config','bootstrap','install','common')){if([string]$plan.inputHashes.$name-cne[string]$request.inputHashes.$name){throw "Extracted candidate prerequisite hash mismatch: $name"}}
    $before=Get-ActiveBoundary
    if([bool]$before.activeTransactionPresent-or[int]$before.stageMarkerCount-ne0-or[int]$before.activeInstallProcessCount-ne0){throw 'Campaign E prerequisite worker requires a transactionless, marker-free, quiescent product boundary.'}
    $remaining=[int][math]::Floor(($ownerDeadline-[datetime]::UtcNow).TotalSeconds)
    if($remaining-le0){throw 'Campaign E prerequisite owner deadline expired before dependency evaluation.'}
    Set-DevFleetDeadlineContext -TransactionDeadlineUtc $ownerDeadline -StageName 'campaign-e-prerequisite-only' -StageBudgetSeconds $remaining|Out-Null
    $manifest=Get-CanonicalDependencyManifest -PackageRoot $packageRoot
    $powerShellDependency=@($manifest.dependencies|Where-Object{[string]$_.id-ceq'powershell7'})
    $multipassDependency=@($manifest.dependencies|Where-Object{[string]$_.id-ceq'multipass'})
    if($powerShellDependency.Count-ne1-or$multipassDependency.Count-ne1){throw 'Candidate prerequisite dependency identity is not unique.'}
    $powerShellStatus=Get-DependencyStatus -Dependency $powerShellDependency[0]
    if([string]$powerShellStatus.Status-cne'Compatible'){throw "PowerShell bootstrap did not reach compatible state: $([string]$powerShellStatus.Status)"}
    $beforeMultipass=Get-DependencyStatus -Dependency $multipassDependency[0]
    if([string]$beforeMultipass.Status-cne'Compatible'){
        if([string]$beforeMultipass.Status-ceq'Unsupported-Major'){throw "Multipass major version is outside the candidate policy: $([string]$beforeMultipass.Version)"}
        $health=Get-WingetHealth
        if([string]$health.Status-ceq'Healthy'-and[string]$multipassDependency[0].wingetPackageId){
            try {Install-WingetPackage -Id ([string]$multipassDependency[0].wingetPackageId) -Upgrade:([string]$beforeMultipass.Status-ceq'Outdated')}
            catch {
                if($_.Exception.Message-notmatch'(?i)External command timed out'-or-not$multipassDependency[0].directOfficialVendorResolver){throw}
                Install-OfficialDependency -Dependency $multipassDependency[0]
            }
        } else {Install-OfficialDependency -Dependency $multipassDependency[0]}
    }
    $afterMultipass=Get-DependencyStatus -Dependency $multipassDependency[0]
    if([string]$afterMultipass.Status-cne'Compatible'){throw "Multipass did not reach compatible state: $([string]$afterMultipass.Status)"}
    $edition=[string](Get-ComputerInfo -Property WindowsProductName).WindowsProductName
    if($edition-notmatch'Pro|Enterprise|Education'){throw "Campaign E prerequisite state requires the candidate Hyper-V mapping; observed edition: $edition"}
    $feature=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
    if([string]$feature.State-cne'Enabled'){throw 'Campaign E prerequisite state will not enable Hyper-V; the exact CLEAN baseline must already provide it.'}
    $multipass=Get-MultipassExe
    if(-not$multipass){throw 'Compatible Multipass was reported but its trusted executable could not be resolved.'}

    function Invoke-ConfigurationProbe {
        param([string[]]$Arguments,[string]$Failure)
        $operationDeadline=[datetime]::UtcNow.AddSeconds((Get-DevFleetOperationMaximumSeconds 'multipassConfiguration'))
        if($operationDeadline-gt$ownerDeadline){$operationDeadline=$ownerDeadline}
        do {
            $operationRemaining=[int][math]::Floor(($operationDeadline-[datetime]::UtcNow).TotalSeconds)
            if($operationRemaining-le0){break}
            try{return Invoke-External -FilePath $multipass -ArgumentList $Arguments -Capture -TimeoutSeconds ([math]::Min(60,$operationRemaining)) -DeadlineUtc $operationDeadline}catch{if([datetime]::UtcNow.AddSeconds(1)-ge$operationDeadline){break};Start-Sleep -Seconds 1}
        } while($true)
        throw $Failure
    }

    $null=Invoke-ConfigurationProbe -Arguments @('set','local.driver=hyperv') -Failure 'Multipass Hyper-V driver selection did not complete inside its finite candidate operation budget.'
    $driver=(Invoke-ConfigurationProbe -Arguments @('get','local.driver') -Failure 'Multipass Hyper-V driver verification did not complete inside its finite candidate operation budget.').Trim().ToLowerInvariant()
    if($driver-cne'hyperv'){throw "Multipass driver verification returned an unsupported value: $driver"}
    $null=Invoke-ConfigurationProbe -Arguments @('set','local.privileged-mounts=false') -Failure 'Multipass mount hardening did not complete inside its finite candidate operation budget.'
    $mountText=(Invoke-ConfigurationProbe -Arguments @('get','local.privileged-mounts') -Failure 'Multipass mount hardening verification did not complete inside its finite candidate operation budget.').Trim().ToLowerInvariant()
    if($mountText-notin@('true','false')){throw 'Multipass privileged-mount output was malformed.'}
    if($mountText-cne'false'){throw 'Multipass privileged mounts remained enabled.'}
    $inventoryText=Invoke-ConfigurationProbe -Arguments @('list','--format','json') -Failure 'Multipass empty-inventory verification did not complete inside its finite candidate operation budget.'
    $inventory=$inventoryText|ConvertFrom-Json -ErrorAction Stop
    $instances=@(if($inventory.PSObject.Properties.Name-contains'list'){$inventory.list}elseif($inventory-is[array]){$inventory}else{throw 'Multipass inventory omitted its list.'})
    if($instances.Count-ne0){throw 'Campaign E prerequisite state requires an empty Multipass inventory.'}
    $finalBoundary=Get-ActiveBoundary
    if([bool]$finalBoundary.activeTransactionPresent-or[int]$finalBoundary.stageMarkerCount-ne0-or[int]$finalBoundary.activeInstallProcessCount-ne0){throw 'Campaign E prerequisite worker ended with forbidden product activity.'}
    $currentReboot=Get-DevFleetPendingRebootSnapshot
    $baseline=$request.pendingRebootBaseline
    $newPending=[bool](([bool]$currentReboot.CbsPending-and-not[bool]$baseline.CbsPending)-or([bool]$currentReboot.WindowsUpdatePending-and-not[bool]$baseline.WindowsUpdatePending)-or@($currentReboot.PendingPairs|Where-Object{@($baseline.PendingPairs)-notcontains$_}).Count-gt0)
    $result=[ordered]@{
        schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY';status='PASS';runId=[string]$request.runId;vmId=[string]$request.vmId;payloadSha256=[string]$request.payloadSha256
        role=[string]$request.role;packageVersion=[string]$plan.packageVersion;ownerDeadlineUtc=$ownerDeadline.ToString('o');startedAtUtc=$started.ToString('o');producedAtUtc=[datetime]::UtcNow.ToString('o')
        inputHashes=$plan.inputHashes;systemPolicyChanged=$false;productLifecycleStarted=$false;activeTransactionPresent=[bool]$finalBoundary.activeTransactionPresent;stageMarkerCount=[int]$finalBoundary.stageMarkerCount;activeInstallProcessCount=[int]$finalBoundary.activeInstallProcessCount
        pendingReboot=$newPending;pendingRebootEvidence=[ordered]@{baselineCbs=[bool]$baseline.CbsPending;currentCbs=[bool]$currentReboot.CbsPending;baselineWindowsUpdate=[bool]$baseline.WindowsUpdatePending;currentWindowsUpdate=[bool]$currentReboot.WindowsUpdatePending;newPendingPairCount=@($currentReboot.PendingPairs|Where-Object{@($baseline.PendingPairs)-notcontains$_}).Count}
        powershell=[ordered]@{status=[string]$powerShellStatus.Status;version=[string]$powerShellStatus.Version;pathSha256=(Get-FileHash -LiteralPath ([string]$powerShellStatus.Path) -Algorithm SHA256).Hash.ToLowerInvariant()}
        multipass=[ordered]@{status=[string]$afterMultipass.Status;version=[string]$afterMultipass.Version;pathSha256=(Get-FileHash -LiteralPath ([string]$afterMultipass.Path) -Algorithm SHA256).Hash.ToLowerInvariant();preexisting=([string]$beforeMultipass.Status-ceq'Compatible')}
        backend=[ordered]@{driver=$driver;privilegedMounts=$false;inventoryCount=0;windowsEditionClass='PRO_ENTERPRISE_EDUCATION'}
        l2Status='PENDING_CONTROLLER_VERIFICATION'
    }
    Write-AtomicJson -Path $resultPath -Value $result
    if($newPending){throw 'Prerequisite installation introduced a pending reboot; checkpoint creation is not allowed before exact L1 restart handling.'}
} catch {
    $message=[regex]::Replace([string]$_.Exception.Message,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    [Console]::Error.Write($message)
    exit 1
}

```


## FILE: automation/release-e2e/Invoke-CampaignEPrerequisiteWorker.ps1

SHA256: e2c7f91a9a95821c85821bd81e81e4abce1c1ef71f3b54d51a671cf79bace1f7 | Bytes: 16847 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9+/=]+$')][string]$RequestBase64
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Get-PendingRebootProjection {
    $cbs=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $wu=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $value=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    $raw=@();if($null-ne$value){$raw=@($value.PendingFileRenameOperations)}
    $pairs=[Collections.Generic.List[string]]::new()
    for($index=0;$index-lt$raw.Count;$index+=2){$source=[string]$raw[$index];$destination=if($index+1-lt$raw.Count){[string]$raw[$index+1]}else{''};if($source-or$destination){[void]$pairs.Add("$source`n$destination")}}
    [ordered]@{CbsPending=[bool]$cbs;WindowsUpdatePending=[bool]$wu;PendingPairs=[string[]]$pairs}
}

function Get-ProductBoundary {
    $root=Join-Path $env:ProgramData 'DevFleet'
    [ordered]@{
        activeTransactionPresent=Test-Path -LiteralPath (Join-Path $root 'active-transaction.json') -PathType Leaf
        stageMarkerCount=@(Get-ChildItem -LiteralPath $root -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue).Count
        activeInstallProcessCount=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{[string]$_.Name-in@('DevFleet.Setup.exe','pwsh.exe','powershell.exe')-and[uint32]$_.ProcessId-ne[uint32]$PID-and[string]$_.CommandLine-match'(?i)Install-DevFleet|Bootstrap-Install|DevFleet.Setup'}).Count
    }
}

function Write-FreshAtomicJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    if(Test-Path -LiteralPath $Path){throw 'Campaign E final worker result path already exists.'}
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try{[IO.File]::WriteAllBytes($temporary,[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 24 -Compress)));[IO.File]::Move($temporary,$Path)}finally{Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
}

$request=$null
$ownerDeadline=[datetime]::MinValue
$validatedRemoteRoot=''
$campaignEAcquisitionState=[pscustomobject]@{pwshPath='';nativeTrace=[Collections.Generic.List[object]]::new();identity=$null}
try {
    $requestJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))
    $request=$requestJson|ConvertFrom-Json -ErrorAction Stop
    if([string]$request.runId-notmatch'^[A-Za-z0-9._-]+$'){throw 'Campaign E prerequisite run identity is invalid.'}
    $remoteRoot=[IO.Path]::GetFullPath([string]$request.remoteRoot).TrimEnd('\')
    if($remoteRoot-notlike'C:\Users\Public\DevFleet-E2E\*\Prerequisite'){throw 'Campaign E prerequisite root is outside the run-owned boundary.'}
    $validatedRemoteRoot=$remoteRoot
    foreach($property in @('candidateTarPath','diagnosticModulePath','innerWorkerPath','powerShellPayloadPath')){
        $resolved=[IO.Path]::GetFullPath([string]$request.$property)
        if(-not$resolved.StartsWith($remoteRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Campaign E prerequisite input escaped the run-owned root: $property"}
    }
    $ownerDeadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.ownerDeadlineUnixMilliseconds).UtcDateTime
    $started=[datetime]::UtcNow
    if($ownerDeadline-le$started){throw 'Campaign E prerequisite owner deadline expired before worker start.'}
    Import-Module ([string]$request.diagnosticModulePath) -Force -ErrorAction Stop
    $policyBefore=Get-DevFleetSystemExecutionPolicyProjection
    $boundaryBefore=Get-ProductBoundary
    if([bool]$boundaryBefore.activeTransactionPresent-or[int]$boundaryBefore.stageMarkerCount-ne0-or[int]$boundaryBefore.activeInstallProcessCount-ne0){throw 'Campaign E prerequisite preparation requires a transactionless, marker-free, quiescent product boundary.'}
    $tarPath=[string]$request.candidateTarPath
    if(-not(Test-Path -LiteralPath $tarPath -PathType Leaf)-or(Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$request.payloadSha256){throw 'Staged candidate TAR payload identity mismatch.'}
    $tarExe=Join-Path $env:SystemRoot 'System32\tar.exe'
    if(-not(Test-Path -LiteralPath $tarExe -PathType Leaf)){throw 'In-box tar.exe is unavailable.'}
    $listProbe=Invoke-DevFleetBoundedNativeProbe -Operation 'candidate-archive-list' -FilePath $tarExe -ArgumentList @('-tf',$tarPath) -TimeoutSeconds 120 -OwnerDeadlineUtc $ownerDeadline -ForceLegacyArgumentString -MaxStdoutCharacters 262144
    if([string]$listProbe.outcome-cne'PASS'-or[bool]$listProbe.stdoutTruncated){throw "Candidate archive listing failed: $(ConvertTo-DevFleetDiagnosticSafeText $listProbe.stderr)"}
    $entries=@([string]$listProbe.stdout-split"`r?`n"|Where-Object{$_})
    Assert-DevFleetCampaignEArchiveEntries -Entries $entries|Out-Null
    $packageRoot=Join-Path $remoteRoot 'candidate-package'
    if(Test-Path -LiteralPath $packageRoot){throw 'Campaign E candidate extraction path already exists.'}
    New-Item -ItemType Directory -Path $packageRoot|Out-Null
    $extractProbe=Invoke-DevFleetBoundedNativeProbe -Operation 'candidate-archive-extract' -FilePath $tarExe -ArgumentList @('-xf',$tarPath,'-C',$packageRoot) -TimeoutSeconds 180 -OwnerDeadlineUtc $ownerDeadline -ForceLegacyArgumentString
    if([string]$extractProbe.outcome-cne'PASS'){throw "Candidate archive extraction failed: $(ConvertTo-DevFleetDiagnosticSafeText $extractProbe.stderr)"}
    $plan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot $packageRoot -Role ([string]$request.role)
    foreach($name in @('version','dependencies','config','bootstrap','install','common')){if([string]$plan.inputHashes.$name-cne[string]$request.inputHashes.$name){throw "Extracted candidate prerequisite hash mismatch: $name"}}
    $pendingBaseline=Get-PendingRebootProjection
    $candidateCommon=Join-Path $packageRoot 'windows\DevFleet.Common.psm1'
    Import-Module $candidateCommon -Force -Global -ErrorAction Stop
    $manifest=Get-Content -LiteralPath (Join-Path $packageRoot 'dependencies.json') -Raw|ConvertFrom-Json -ErrorAction Stop
    $powerShellDependencies=@($manifest.dependencies|Where-Object{[string]$_.id-ceq'powershell7'})
    if($powerShellDependencies.Count-ne1){throw 'Candidate PowerShell dependency identity is not unique.'}
    $powerShellDependency=$powerShellDependencies[0]
    $powerShellPayload=$request.powerShellPayload
    $powerShellPayloadPath=[IO.Path]::GetFullPath([string]$request.powerShellPayloadPath)
    if($null-eq$powerShellPayload-or[string]$powerShellPayload.kind-cne'DEVFLEET_CAMPAIGN_E_OFFICIAL_POWERSHELL_PAYLOAD'-or[string]$powerShellPayload.status-cne'PASS'-or[string]$powerShellPayload.method-cne'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'-or[string]$powerShellPayload.packageId-cne'Microsoft.PowerShell'-or[bool]$powerShellPayload.productLifecycleStarted-or[bool]$powerShellPayload.stageMarkerWritten){throw 'Staged official PowerShell payload evidence is missing or malformed.'}
    if(-not(Test-Path -LiteralPath $powerShellPayloadPath -PathType Leaf)-or[IO.Path]::GetFileName($powerShellPayloadPath)-cne[string]$powerShellPayload.assetName-or(Get-FileHash -LiteralPath $powerShellPayloadPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$powerShellPayload.sha256){throw 'Staged official PowerShell payload identity mismatch.'}
    $script:campaignEPwshPath=''
    $compatibilityProvider={
        param($dependency,$deadline)
        $first=$null
        foreach($path in @(Get-TrustedDependencyCandidates $dependency)){
            $remaining=[int][math]::Floor((([datetime]$deadline).ToUniversalTime()-[datetime]::UtcNow).TotalSeconds)
            if($remaining-le0){return [pscustomobject]@{status='Broken';version='';pathSha256='';detail='Owner deadline expired before PowerShell compatibility probe.'}}
            $probe=Invoke-DevFleetBoundedNativeProbe -Operation 'powershell-version' -FilePath ([string]$path) -ArgumentList @($dependency.versionProbe.arguments) -TimeoutSeconds ([math]::Min(60,$remaining)) -OwnerDeadlineUtc ([datetime]$deadline) -ForceLegacyArgumentString
            if([string]$probe.outcome-cne'PASS'){$first=[pscustomobject]@{status='Broken';version='';pathSha256='';detail='Trusted PowerShell version probe failed.'};continue}
            $match=[regex]::Match([string]$probe.stdout,[string]$dependency.versionProbe.regex)
            if(-not$match.Success){$first=[pscustomobject]@{status='Broken';version='';pathSha256='';detail='Trusted PowerShell version response was malformed.'};continue}
            $version=[Version]$match.Groups[1].Value
            $s