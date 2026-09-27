[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
    [Parameter(Mandatory)][string]$CheckpointEvidencePath,
    [ValidateRange(900,3000)][int]$OwnerSeconds=1500,
    [switch]$ProductCapacity,
    [switch]$ProductLaunch
)
$ErrorActionPreference='Stop'
if($ProductLaunch){$ProductCapacity=$true}
if($ProductCapacity-and-not$PSBoundParameters.ContainsKey('OwnerSeconds')){$OwnerSeconds=2400}
$root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path;$checkpointEvidencePath=(Resolve-Path -LiteralPath $CheckpointEvidencePath).Path
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';$vmName='DevFleet-E2E-Win11-01';$cleanId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9';$l2Name='DevFleet-E2E-Linux-01'
$instanceName="DevFleet-E2E-E-M1-$RunId";$runDir=Join-Path $root "audit\automation-harness\runs\$RunId";$remoteRoot="C:\Users\Public\DevFleet-E2E\$RunId\M1";$nonce=[guid]::NewGuid();$owner=[datetime]::UtcNow.AddSeconds($OwnerSeconds);$operationDeadline=$owner.AddSeconds(-240)
foreach($module in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic')){Import-Module (Join-Path $root "automation\release-e2e\modules\$module.psm1") -Force}
$result=[ordered]@{schemaVersion=1;campaign='DF-STABLE-20260906-E';experiment='M1';status='RESERVED';certificationEligible=$false;proofCredit=$false;runId=$RunId;startedAtUtc=[datetime]::UtcNow.ToString('o');ownerDeadlineUtc=$owner.ToString('o');operationDeadlineUtc=$operationDeadline.ToString('o');exactL1=[ordered]@{name=$vmName;id=$vmId.ToString()};diagnosticInstanceName=$instanceName;cleanupOwner='Invoke-CampaignEMultipassM1.ps1';diagnosticDeviation=[ordered]@{cpus=2;memory='2G';disk='10G';cloudInit='NONE_PRODUCT';productLifecycle=$false}}
$session=$null;$restored=$false;$restoreAttempted=$false;$stagingOwned=$false;$m1=$null;$checkpoint=$null
$expectedResources=@{cpus=2;memory='2G';disk='10G'};$profile=$null;$rawCollected=-not$ProductCapacity;$workerDeadline=$owner
if(Test-Path -LiteralPath $runDir){throw 'Campaign E M1 refuses to reuse an existing evidence run directory.'}
if($ProductCapacity){
    $operationDeadline=$owner.AddSeconds(-480);$workerDeadline=$owner.AddSeconds(-180)
    if(($operationDeadline-[datetime]::UtcNow).TotalSeconds-lt1600){throw 'M2 owner cannot cover unchanged operation limits plus evidence and cleanup reserves.'}
    $result.experiment='M2';$result.operationDeadlineUtc=$operationDeadline.ToString('o');$result.workerDeadlineUtc=$workerDeadline.ToString('o')
    $result.diagnosticDeviation=[ordered]@{resources='PENDING_ACTUAL_CANDIDATE_PREFLIGHT';cloudInit='NONE_PRODUCT';productLifecycle=$false;workerRuntime='CHECKPOINT_WINDOWS_POWERSHELL_5_1'}
    if($ProductLaunch){
        $result.experiment='M3'
        $result.diagnosticDeviation.cloudInit='CANDIDATE_RENDERED_COMPUTE_TEMPLATE'
        $result.diagnosticDeviation.workerRuntime='CHECKPOINT_HASH_BOUND_POWERSHELL_7'
        $result.diagnosticDeviation.launchImplementation='CANDIDATE_COMMON_INVOKE_EXTERNAL'
        $result.diagnosticDeviation.captureMode=$true
        $result.diagnosticDeviation.context='QUIET_TRANSACTIONLESS_DIAGNOSTIC_WITH_RUN_OWNED_NAME'
        $result.diagnosticDeviation.cloudInitWaitMaximumSeconds=300
    }
}
try {
    New-Item -ItemType Directory -Path $runDir -Force|Out-Null;Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-m1.json') -Value $result
    $checkpointRecord=Get-Content -LiteralPath $checkpointEvidencePath -Raw|ConvertFrom-Json -ErrorAction Stop
    if([string]$checkpointRecord.status-cne'PASS_CHECKPOINT_READY'-or[string]$checkpointRecord.campaign-cne'DF-STABLE-20260906-E'){throw 'Campaign E M1 checkpoint evidence is not a passing E prerequisite record.'}
    $cp=$checkpointRecord.diagnosticCheckpoint;$checkpointId=[guid][string]$cp.id;$checkpointName=[string]$cp.name
    if([guid][string]$cp.vmId-ne$vmId-or[guid][string]$cp.parentSnapshotId-ne$cleanId-or[string]$cp.l1State-cne'OFF'-or[string]$cp.l2Status-cne'ABSENT'){throw 'Campaign E M1 checkpoint evidence identity/state is invalid.'}
    $vm=Get-VM -Id $vmId -ErrorAction Stop;if([string]$vm.Name-cne$vmName-or$vm.Id-ne$vmId){throw 'Campaign E M1 exact L1 identity mismatch.'};Assert-DisposableOwnership -Vm $vm -ExpectedId $vmId.ToString()|Out-Null
    if($vm.State-ne'Off'){throw 'Campaign E M1 will not acquire an already-running L1.'}
    $matches=@(Get-VMSnapshot -VM $vm -ErrorAction Stop|Where-Object{$_.Id-eq$checkpointId-and$_.Name-ceq$checkpointName-and$_.VMId-eq$vmId-and$_.ParentSnapshotId-eq$cleanId});if($matches.Count-ne1){throw 'Campaign E M1 live checkpoint name/GUID/parent binding failed.'};$checkpoint=$matches[0]
    $safety=Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB 14.38;$result.hostSafety=[ordered]@{status=if([bool]$safety.startSafe){'PASS'}else{'BLOCKED'};startSafe=[bool]$safety.startSafe;availableMemoryGiB=[double]$safety.availableMemoryGiB;projectedPostStartAvailableMemoryGiB=[double]$safety.projectedPostStartAvailableMemoryGiB;observedAtUtc=[datetime]::UtcNow.ToString('o')};if(-not[bool]$safety.startSafe){throw 'BLOCKED - HOST-SAFETY startSafe=false.'}
    $fingerprint=Get-CandidateFingerprint -WorkspaceRoot $root;$authority=Get-Content (Join-Path $root 'evidence\CURRENT-RELEASE-AUTHORITY.json') -Raw|ConvertFrom-Json;$head=(&git -C $root rev-parse HEAD).Trim()
    if(-not[bool]$authority.candidateIsCurrent-or[bool]$authority.sourceChangedSinceCandidate-or[bool]$authority.rebuildRequired-or[string]$authority.repositoryHead-cne$head-or[string]$fingerprint.tar.sha256-cne[string]$cp.payloadSha256){throw 'Campaign E M1 current candidate/checkpoint coherence failed.'}
    foreach($field in @('shippingInputIdentity','releaseFingerprintId','toolingFingerprintId')){if([string]$authority.$field-cne[string]$fingerprint.$field){throw 'Campaign E M1 native authority/fingerprint tuple mismatch.'}}
    $result.tuple=[ordered]@{repositoryHead=$head;candidateCommit=[string]$fingerprint.gitCommit;shippingInputIdentity=[string]$fingerprint.shippingInputIdentity;releaseFingerprintId=[string]$fingerprint.releaseFingerprintId;toolingFingerprintId=[string]$fingerprint.toolingFingerprintId;payloadSha256=[string]$fingerprint.tar.sha256}
    $result.sourceCheckpoint=[ordered]@{name=$checkpointName;id=$checkpointId.ToString();parentSnapshotId=$cleanId.ToString();evidencePath=$checkpointEvidencePath;evidenceSha256=(Get-FileHash $checkpointEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()}
    $restoreAttempted=$true;$result.restore=Restore-ExactCheckpoint -Vm $vm -Name $checkpointName -StartAfterRestore;$restored=$true;$session=Connect-DevFleetGuest -VmId $vmId
    $result.initialL2=Get-DevFleetNestedL2State -Session $session -ExpectedName $l2Name;if([string]$result.initialL2.status-cne'ABSENT'){throw 'Campaign E M1 initial product L2 is not positively absent.'}
    $ownerRecord=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 30 -ScriptBlock {param($Path,$Run,$Nonce)if($Path-notlike'C:\Users\Public\DevFleet-E2E\*\M1'){throw 'M1 staging escaped owned boundary.'};if(Test-Path $Path){throw 'M1 staging already exists.'};New-Item -ItemType Directory -Path $Path|Out-Null;$v=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_STAGING_OWNER';runId=$Run;nonce=$Nonce;createdAtUtc=[datetime]::UtcNow.ToString('o')};$v|ConvertTo-Json -Compress|Set-Content (Join-Path $Path '.owner.json') -Encoding UTF8;[pscustomobject]$v} -ArgumentList @($remoteRoot,$RunId,$nonce.ToString()))|Select-Object -Last 1
    Assert-DevFleetCampaignEStagingOwnership -Record $ownerRecord -ExpectedRunId $RunId -ExpectedNonce $nonce|Out-Null;$stagingOwned=$true;$result.stagingOwnership=$ownerRecord
    $localModule=Join-Path $root 'automation\release-e2e\modules\MultipassDiagnostic.psm1';$localWorker=Join-Path $root 'automation\release-e2e\Invoke-CampaignEMultipassM1Worker.ps1';$remoteModule=Join-Path $remoteRoot 'MultipassDiagnostic.psm1';$remoteWorker=Join-Path $remoteRoot 'Invoke-CampaignEMultipassM1Worker.ps1'
    $result.stage=[ordered]@{module=Copy-DevFleetBoundedGuestFile -LocalPath $localModule -Session $session -RemotePath $remoteModule -TimeoutSeconds 60;worker=Copy-DevFleetBoundedGuestFile -LocalPath $localWorker -Session $session -RemotePath $remoteWorker -TimeoutSeconds 60}
    $profileInputs=@();$profileSha=''
    if($ProductCapacity){
        $shipping=@((Get-Content (Join-Path $root 'outputs/release-fingerprint.json') -Raw|ConvertFrom-Json).shippingInputs)
        $profilePaths=@('windows/00-Preflight.ps1','windows/DevFleet.Common.psm1','config/devfleet.config.json');if($ProductLaunch){$profilePaths+='cloud-init/compute.yaml'}
        $profileInputs=@(foreach($relative in $profilePaths){
            $inputPath=Join-Path $root ('source/'+$relative);$hash=(Get-FileHash $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if(@($shipping|Where-Object{$_.root-ceq'source'-and$_.path-ceq$relative-and$_.sha256-ceq$hash}).Count-ne1){throw 'M2 preflight source differs from canonical shipping inventory.'}
            [ordered]@{path=$relative;sha256=$hash}
        })
        $null=Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {param($Path,$Launch)$paths=@((Join-Path $Path 'profile-package/windows'),(Join-Path $Path 'profile-package/config'));if($Launch){$paths+=Join-Path $Path 'profile-package/cloud-init'};New-Item -ItemType Directory -Path $paths|Out-Null} -ArgumentList @($remoteRoot,[bool]$ProductLaunch)
        foreach($entry in $profileInputs){$null=Copy-DevFleetBoundedGuestFile -LocalPath (Join-Path $root ('source/'+$entry.path)) -Session $session -RemotePath (Join-Path $remoteRoot ('profile-package/'+$entry.path)) -TimeoutSeconds 30}
        $profileWorker=Join-Path $remoteRoot 'Invoke-CampaignEProductProfile.ps1'
        $null=Copy-DevFleetBoundedGuestFile -LocalPath (Join-Path $root 'automation/release-e2e/Invoke-CampaignEProductProfile.ps1') -Session $session -RemotePath $profileWorker -TimeoutSeconds 30
        $pwsh=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {param($Hash)$p=Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe';if((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant()-cne$Hash){throw 'M2 profile PowerShell checkpoint hash mismatch.'};$p} -ArgumentList @([string]$cp.powershell.pathSha256))|Select-Object -Last 1
        $profileDeadline=[datetime]::UtcNow.AddSeconds(120);if($profileDeadline-gt$operationDeadline){throw 'M2 profile has no remaining bounded budget.'}
        $profileRequest=[ordered]@{runId=$RunId;vmId=$vmId.ToString();remoteRoot=$remoteRoot;stagingNonce=$nonce.ToString();payloadSha256=[string]$fingerprint.tar.sha256;inputs=$profileInputs;deadlineUnixMilliseconds=[DateTimeOffset]::new($profileDeadline).ToUnixTimeMilliseconds()}
        if($ProductLaunch){$profileRequest.productLaunch=$true;$profileRequest.instanceName=$instanceName}
        $profileBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($profileRequest|ConvertTo-Json -Depth 6 -Compress)))
        $profileProcess=Invoke-DevFleetBoundedGuestProcess -Session $session -FilePath ([string]$pwsh) -ArgumentList @('-NoProfile','-NonInteractive','-File',$profileWorker,'-RequestBase64',$profileBase64) -OwnerDeadlineUtc $profileDeadline
        $result.profileProcess=[ordered]@{outcome=[string]$profileProcess.outcome;exitCode=$profileProcess.exitCode;pid=$profileProcess.pid;startedAtUtc=$profileProcess.startedAtUtc;finishedAtUtc=$profileProcess.finishedAtUtc;error=ConvertTo-DevFleetDiagnosticSafeText $profileProcess.stderr 1024}
        $raw=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {param($Path)[pscustomobject]@{raw=Get-Content $Path -Raw;sha256=(Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()}} -ArgumentList @((Join-Path $remoteRoot 'product-profile.json')))|Select-Object -Last 1
        $profile=$raw.raw|ConvertFrom-Json;$profileSha=[string]$raw.sha256;$result.productProfile=$profile;$result.productProfileSha256=$profileSha
        if([string]$profileProcess.outcome-cne'PASS'){throw "M2 real preflight process failed: $(ConvertTo-DevFleetDiagnosticSafeText $profile.primaryError 512)"}
        Assert-DevFleetCampaignEProductProfile -Profile $profile -ExpectedRunId $RunId -ExpectedVmId $vmId -ExpectedPayloadSha256 ([string]$fingerprint.tar.sha256) -ExpectedInputs $profileInputs -DeadlineUtc $operationDeadline -ExpectedProductLaunch:$ProductLaunch|Out-Null
        if([string]$profile.ubuntuImage-cne[string]$checkpointRecord.plan.ubuntuImage){throw 'M2 profile/checkpoint image mismatch.'}
        $expectedResources=@{cpus=[int]$profile.resources.cpus;memory=[string]$profile.resources.memory;disk=[string]$profile.resources.disk};$result.diagnosticDeviation.resources=$expectedResources
        if(($operationDeadline-[datetime]::UtcNow).TotalSeconds-lt1600){throw 'M2 staging consumed the unchanged launch/readiness budget; no launch will start.'}
    }
    $request=[ordered]@{runId=$RunId;vmId=$vmId.ToString();remoteRoot=$remoteRoot;modulePath=$remoteModule;instanceName=$instanceName;ubuntuImage=[string]$checkpointRecord.plan.ubuntuImage;expectedMultipassSha256=[string]$cp.multipass.pathSha256;payloadSha256=[string]$fingerprint.tar.sha256;operationDeadlineUnixMilliseconds=[DateTimeOffset]::new($operationDeadline).ToUnixTimeMilliseconds();ownerDeadlineUnixMilliseconds=[DateTimeOffset]::new($workerDeadline).ToUnixTimeMilliseconds()};if($ProductCapacity){$request.productProfileSha256=$profileSha;$request.productProfileInputs=$profileInputs};if($ProductLaunch){$request.productLaunch=$true;$request.expectedWorkerSha256=[string]$cp.powershell.pathSha256};$request=$request|ConvertTo-Json -Depth 8 -Compress
    $base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request));$remotePowerShell=if($ProductLaunch){[string]$pwsh}else{@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {Join-Path $PSHOME 'powershell.exe'})|Select-Object -Last 1}
    $worker=Invoke-DevFleetBoundedGuestProcess -Session $session -FilePath ([string]$remotePowerShell) -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$remoteWorker,'-RequestBase64',$base64) -OwnerDeadlineUtc $workerDeadline;$result.worker=[ordered]@{outcome=[string]$worker.outcome;exitCode=$worker.exitCode;pid=$worker.pid;startedAtUtc=[string]$worker.startedAtUtc;finishedAtUtc=[string]$worker.finishedAtUtc;outputComplete=[bool]$worker.outputComplete}
    $durablePath=Join-Path $remoteRoot 'm1-worker-result.json';$collected=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {param($Path)if(-not(Test-Path $Path -PathType Leaf)){throw 'M1 durable result missing.'};[pscustomobject]@{raw=Get-Content $Path -Raw;sha256=(Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()}} -ArgumentList @($durablePath))|Select-Object -Last 1
    $resolved=Resolve-DevFleetCampaignEWorkerResult -ProcessStdout ([string]$worker.stdout) -DurableRaw ([string]$collected.raw);$m1=$resolved.value;$result.workerResultSource=$resolved.source;$result.workerProcessStdoutStatus=$resolved.processStdoutStatus;$result.workerResultSha256=$collected.sha256;$result.m1=$m1
    Assert-DevFleetCampaignEM1Result -Result $m1 -ExpectedRunId $RunId -ExpectedVmId $vmId -ExpectedInstanceName $instanceName -ExpectedPayloadSha256 ([string]$fingerprint.tar.sha256) -ExpectedResources $expectedResources|Out-Null
    if($ProductLaunch){
        $commonHash=[string]@($profileInputs|Where-Object{$_.path-ceq'windows/DevFleet.Common.psm1'})[0].sha256
        if([string]$m1.experiment-cne'M3'-or[version]$m1.executionContext.powerShellVersion-lt[version]'7.0'-or-not[bool]$m1.executionContext.is64BitProcess-or[string]$m1.executionContext.workerExeSha256-cne[string]$cp.powershell.pathSha256-or[string]$m1.executionContext.candidateCommonSha256-cne$commonHash-or[string]$m1.executionContext.launchImplementation-cne'CANDIDATE_COMMON_INVOKE_EXTERNAL'){throw 'M3 worker did not verify the actual candidate Common and checkpoint PowerShell7 context.'}
    }
    if($ProductCapacity-and([string]$m1.backendAfterCleanup.data.backend.status-cne'PASS'-or[int]$m1.backendAfterCleanup.data.backend.foreignCount-ne0-or@($m1.backendAfterCleanup.data.backend.owned).Count)){throw 'M2 worker final independent backend absence was not verified.'}
    if([string]$worker.outcome-cne'PASS'-or[string]$m1.status-cne'PASS_DIAGNOSTIC'){throw "Campaign E M1 worker did not pass: $(ConvertTo-DevFleetDiagnosticSafeText $m1.primaryError 512)"}
    $result.status='PASS_DIAGNOSTIC'
} catch {$result.status='BLOCKED';$result.primaryError=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 1024}
finally {
    if($session-and$stagingOwned-and$ProductCapacity){try{
        $artifacts=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 30 -ScriptBlock {
            param($Path,$Run,$Nonce,$Launch)
            $o=Get-Content (Join-Path $Path '.owner.json') -Raw|ConvertFrom-Json
            if([string]$o.runId-cne$Run-or[guid][string]$o.nonce-ne[guid]$Nonce){throw 'M2 raw collection ownership mismatch.'}
            $names=@('product-profile.json','m1-worker-result.json','backend-before.json','backend-before-cleanup.json','backend-after-cleanup.json')
            if($Launch){$names+='product-cloud-init.yaml'}
            foreach($op in @('launch','info-running','ssh-ready','cloud-init','info-final')){$names+=@(($op+'-start.json'),($op+'-end.json'))}
            foreach($name in $names){$file=Join-Path $Path $name;if(Test-Path -LiteralPath $file -PathType Leaf){$item=Get-Item -LiteralPath $file;if($item.Length-gt524288-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'M2 raw record exceeded safe collection boundary.'};[pscustomobject]@{name=$name;data=[Convert]::ToBase64String([IO.File]::ReadAllBytes($file));sha256=(Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant()}}}
        } -ArgumentList @($remoteRoot,$RunId,$nonce.ToString(),[bool]$ProductLaunch))
        $rawDirectory=Join-Path $runDir 'raw';New-Item -ItemType Directory -Path $rawDirectory -Force|Out-Null
        $result.rawEvidence=@(foreach($artifact in $artifacts){$path=Join-Path $rawDirectory ([string]$artifact.name);if([IO.Path]::GetFileName($path)-cne[string]$artifact.name-or(Test-Path $path)){throw 'M2 raw evidence destination is not fresh.'};[IO.File]::WriteAllBytes($path,[Convert]::FromBase64String([string]$artifact.data));$hash=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant();if($hash-cne[string]$artifact.sha256){throw 'M2 raw evidence transfer hash mismatch.'};[ordered]@{path='raw/'+[string]$artifact.name;sha256=$hash}})
        if($m1-and[string]$m1.status-ceq'PASS_DIAGNOSTIC'){
            $requiredRaw=@('raw/product-profile.json','raw/m1-worker-result.json','raw/backend-before.json','raw/backend-before-cleanup.json','raw/backend-after-cleanup.json')
            if($ProductLaunch){$requiredRaw+='raw/product-cloud-init.yaml';$cloudRecord=@($result.rawEvidence|Where-Object{$_.path-ceq'raw/product-cloud-init.yaml'});if($cloudRecord.Count-ne1-or[string]$cloudRecord[0].sha256-cne[string]$profile.productLaunch.cloudInitSha256){throw 'M3 collected cloud-init did not match its rendered profile hash.'}}
            foreach($operation in @($m1.sequence.observations)){foreach($edge in @('start','end')){$requiredRaw+=('raw/'+[string]$operation.operation+'-'+$edge+'.json')}}
            $collectedPaths=@($result.rawEvidence|ForEach-Object{[string]$_.path})
            if(@($requiredRaw|Where-Object{$collectedPaths-cnotcontains$_}).Count){throw 'M2 complete worker evidence omitted a required raw record; staging will be retained.'}
        }
        $rawCollected=$true
    }catch{$result.status='BLOCKED';$result.rawEvidenceError=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 1024;if(-not$result.Contains('primaryError')){$result.primaryError='M2 raw evidence transfer failed; guest staging was retained.'}}}
    if($session){try{$result.finalL2=Get-DevFleetNestedL2State -Session $session -ExpectedName $l2Name}catch{$result.finalL2=[ordered]@{status='UNVERIFIED';expectedName=$l2Name;verification=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message}};if($stagingOwned-and$rawCollected){try{$null=Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 30 -ScriptBlock {param($Path,$Run,$Nonce)$o=Get-Content (Join-Path $Path '.owner.json') -Raw|ConvertFrom-Json;if([string]$o.runId-cne$Run-or[guid][string]$o.nonce-ne[guid]$Nonce){throw 'M1 cleanup ownership mismatch.'};Remove-Item -LiteralPath $Path -Recurse -Force} -ArgumentList @($remoteRoot,$RunId,$nonce.ToString());$result.stagingCleanup='PASS'}catch{$result.stagingCleanup='UNVERIFIED'}};Remove-PSSession $session -ErrorAction SilentlyContinue;$session=$null}
    $result.acquisition=[ordered]@{restoreAttempted=$restoreAttempted};try{$vm=Get-VM -Id $vmId -ErrorAction Stop;if([string]$vm.Name-cne$vmName-or$vm.Id-ne$vmId){throw 'Campaign E M1 terminal exact L1 identity mismatch.'};if($restoreAttempted){Assert-DisposableOwnership -Vm $vm -ExpectedId $vmId.ToString()|Out-Null};if($restoreAttempted-and$vm.State-ne'Off'){Stop-VM -VM $vm -Force -Confirm:$false};$until=if($restoreAttempted){[datetime]::UtcNow.AddMinutes(2)}else{[datetime]::UtcNow};do{$vm=Get-VM -Id $vmId;if($vm.State-eq'Off'-or-not$restoreAttempted){break};Start-Sleep 2}while([datetime]::UtcNow-lt$until);if($vm.State-ne'Off'){throw 'M1 L1 stop failed.'};if($restored-and[string]$result.finalL2.status-ceq'ABSENT'-and[string]$result.stagingCleanup-ceq'PASS'-and$m1-and[string]$m1.cleanup.status-ceq'ABSENT_VERIFIED'){$result.checkpointRestore=Restore-ExactCheckpoint -Vm $vm -Name $checkpoint.Name;$vm=Get-VM -Id $vmId};$result.finalL1=[ordered]@{status=if($vm.State-eq'Off'){'OFF'}else{'UNVERIFIED'};name=$vm.Name;id=$vm.Id.ToString();observedAtUtc=[datetime]::UtcNow.ToString('o')}}catch{$result.finalL1=[ordered]@{status='UNVERIFIED';error=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message;observedAtUtc=[datetime]::UtcNow.ToString('o')}}
    if([string]$result.status-ceq'PASS_DIAGNOSTIC'-and([string]$result.finalL1.status-cne'OFF'-or[string]$result.finalL2.status-cne'ABSENT'-or-not$result.Contains('checkpointRestore'))){$result.status='BLOCKED';$result.primaryError='Campaign E M1 terminal cleanup/checkpoint restore was incomplete.'}
    $result.completedAtUtc=[datetime]::UtcNow.ToString('o');Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-m1.json') -Value $result
}
[pscustomobject]$result
if([string]$result.status-cne'PASS_DIAGNOSTIC'){exit 1}
