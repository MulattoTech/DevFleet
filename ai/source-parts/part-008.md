# DevFleet source part 008

Full-source UTF-8 byte interval [325500, 372000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 51c487148fd04f3dbf2487039860efaf9d7496e70ae5b47a71f28417e537c2e9

<!-- BEGIN SOURCE SLICE -->
h $runDir 'campaign-e-m1.json') -Value $result
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

```


## FILE: automation/release-e2e/Invoke-CampaignEMultipassM1Worker.ps1

SHA256: 9aa9008dbcd8c106f7c0bd43fe5770b7e88ea6675cdaccae327ef31ecd40dd94 | Bytes: 16873 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9+/=]+$')][string]$RequestBase64)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function ConvertTo-CampaignEM1FailureText {
    param([AllowNull()][object]$Value)
    # Reporting must survive request/deadline validation and a missing or failed
    # module import. Keep this boundary independent of module-provided commands.
    $text=[string]$Value
    $text=[regex]::Replace($text,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    $text=[regex]::Replace($text,'(?i)\bBearer\s+\S+','Bearer <redacted>')
    $text=$text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',''
    if($text.Length-gt1024){$text=$text.Substring($text.Length-1024)}
    return $text.Trim()
}

function Get-ProductBoundary {
    $root=Join-Path $env:ProgramData 'DevFleet'
    [ordered]@{activeTransactionPresent=Test-Path -LiteralPath (Join-Path $root 'active-transaction.json') -PathType Leaf;stageMarkerCount=@(Get-ChildItem -LiteralPath $root -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue).Count}
}
function Write-FreshAtomicJson([string]$Path,$Value){if(Test-Path -LiteralPath $Path){throw 'Campaign E M1 durable result already exists.'};$tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp";try{[IO.File]::WriteAllBytes($tmp,[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 24 -Compress)));[IO.File]::Move($tmp,$Path)}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}}
function Get-InventoryRows([string]$Json){
    $parsed=$Json|ConvertFrom-Json -ErrorAction Stop
    if($null-eq$parsed-or-not$parsed.PSObject.Properties['list']-or$parsed.list-isnot[array]){throw 'Multipass inventory requires an explicit list array.'}
    if($parsed.PSObject.Properties['errors']-and@($parsed.errors).Count){throw 'Multipass inventory contains errors.'}
    $names=@{}
    foreach($row in $parsed.list){
        if($null-eq$row-or-not$row.PSObject.Properties['name']-or$row.name-isnot[string]-or[string]::IsNullOrWhiteSpace($row.name)-or$names.ContainsKey($row.name)){throw 'Multipass inventory row identity is invalid.'}
        $names[$row.name]=$true
    }
    return @($parsed.list)
}
function Get-NativeSummary($Probe){[pscustomobject][ordered]@{operation=[string]$Probe.operation;outcome=[string]$Probe.outcome;exitCode=$Probe.exitCode;pid=$Probe.pid;startedAtUtc=[string]$Probe.startedAtUtc;finishedAtUtc=[string]$Probe.finishedAtUtc;deadlineUtc=[string]$Probe.deadlineUtc;outputComplete=[bool]$Probe.outputComplete;error=ConvertTo-DevFleetDiagnosticSafeText $Probe.stderr 512}}

$request=$null;$owner=[datetime]::MinValue;$operationDeadline=[datetime]::MinValue;$remoteRoot='';$resultPath='';$multipass='';$multipassSha='';$instanceName='';$payloadSha='';$runId='';$vmId='';$sequence=$null;$launchState=[pscustomobject]@{callStarted=$false};$preflight=$null;$cleanup=[ordered]@{status='UNVERIFIED';instanceName='';delete=$null;inventory=$null;finalInventoryCount=-1};$primaryError='';$boundaryBefore=$null;$boundaryAfter=$null
$profile=$null;$resources=@{cpus=2;memory='2G';disk='10G'};$backendBefore=$null;$backendAfter=$null;$backendFinal=$null;$observedSince=[datetime]::UtcNow
$productLaunch=$false;$cloudInitPath='';$candidateCommon=$null;$workerContext=$null
try {
    $request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))|ConvertFrom-Json -ErrorAction Stop
    $runId=[string]$request.runId;$vmId=[string]$request.vmId;$payloadSha=[string]$request.payloadSha256;$instanceName=[string]$request.instanceName
    if($runId-notmatch'^[A-Za-z0-9._-]+$'-or$instanceName-notmatch'^DevFleet-E2E-E-M1-[A-Za-z0-9._-]+$'-or$payloadSha-notmatch'^[0-9a-f]{64}$'){throw 'Campaign E M1 request identity is invalid.'}
    $remoteRoot=[IO.Path]::GetFullPath([string]$request.remoteRoot).TrimEnd('\');if($remoteRoot-notlike'C:\Users\Public\DevFleet-E2E\*\M1'){throw 'Campaign E M1 root is outside run-owned staging.'}
    $modulePath=[IO.Path]::GetFullPath([string]$request.modulePath);if(-not$modulePath.StartsWith($remoteRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Campaign E M1 module escaped run-owned staging.'}
    $resultPath=Join-Path $remoteRoot 'm1-worker-result.json'
    $owner=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.ownerDeadlineUnixMilliseconds).UtcDateTime;$operationDeadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.operationDeadlineUnixMilliseconds).UtcDateTime
    if($owner-le[datetime]::UtcNow-or$operationDeadline-le[datetime]::UtcNow-or$operationDeadline-ge$owner){throw 'Campaign E M1 deadline partition is invalid.'}
    Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
    $cleanup=New-DevFleetCampaignEM1CleanupState -InstanceName $instanceName
    $productLaunch=$request.PSObject.Properties['productLaunch']-and[bool]$request.productLaunch
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=[Security.Principal.WindowsPrincipal]::new($identity)
    $workerContext=[ordered]@{powerShellVersion=$PSVersionTable.PSVersion.ToString();is64BitProcess=[Environment]::Is64BitProcess;workerPid=$PID;principalKind=if($identity.IsSystem){'SYSTEM'}elseif($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){'ADMINISTRATOR'}else{'STANDARD_USER'};launchImplementation=if($productLaunch){'CANDIDATE_COMMON_INVOKE_EXTERNAL'}else{'DIAGNOSTIC_LEGACY_ARGUMENT_STRING'}}
    if($request.PSObject.Properties['productProfileSha256']){
        $profilePath=Join-Path $remoteRoot 'product-profile.json'
        if((Get-FileHash $profilePath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$request.productProfileSha256){throw 'M2 preflight profile hash mismatch.'}
        $profile=Get-Content $profilePath -Raw|ConvertFrom-Json
        Assert-DevFleetCampaignEProductProfile -Profile $profile -ExpectedRunId $runId -ExpectedVmId ([guid]$vmId) -ExpectedPayloadSha256 $payloadSha -ExpectedInputs @($request.productProfileInputs) -DeadlineUtc $operationDeadline -ExpectedProductLaunch:$productLaunch|Out-Null
        if([string]$profile.ubuntuImage-cne[string]$request.ubuntuImage){throw 'M2 preflight Ubuntu image mismatch.'}
        $resources=@{cpus=[int]$profile.resources.cpus;memory=[string]$profile.resources.memory;disk=[string]$profile.resources.disk}
    }
    if($productLaunch){
        if(-not$profile-or$PSVersionTable.PSVersion.Major-lt7){throw 'M3 requires its bound product profile and real PowerShell7 runtime.'}
        $workerExe=(Get-Process -Id $PID).Path
        if((Get-FileHash $workerExe -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$request.expectedWorkerSha256){throw 'M3 worker runtime hash differs from the checkpoint.'}
        $workerContext.workerExeSha256=[string]$request.expectedWorkerSha256
        $commonPath=Join-Path $remoteRoot 'profile-package/windows/DevFleet.Common.psm1'
        $commonInput=@($profile.inputs|Where-Object{$_.path-ceq'windows/DevFleet.Common.psm1'})
        if($commonInput.Count-ne1-or(Get-FileHash $commonPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$commonInput[0].sha256){throw 'M3 actual candidate Common input hash mismatch.'}
        $cloudInitPath=Join-Path $remoteRoot 'product-cloud-init.yaml'
        if((Get-Item -LiteralPath $cloudInitPath).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'M3 cloud-init output is a reparse point.'}
        if((Get-FileHash $cloudInitPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$profile.productLaunch.cloudInitSha256){throw 'M3 rendered cloud-init hash mismatch.'}
        $candidateCommon=Import-Module $commonPath -Force -PassThru -DisableNameChecking -ErrorAction Stop
        if([IO.Path]::GetFullPath($candidateCommon.Path)-ine[IO.Path]::GetFullPath($commonPath)){throw 'M3 imported a different candidate Common module.'}
        $workerContext.candidateCommonSha256=[string]$commonInput[0].sha256
    }
    $paths=@(Get-DevFleetExistingFilePathSet -CandidatePaths @((Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Multipass\bin\multipass.exe')))
    if($paths.Count-eq0){$command=Get-Command multipass.exe -ErrorAction SilentlyContinue;if(-not$command){$command=Get-Command multipass -ErrorAction SilentlyContinue};if($command){$paths=@([IO.Path]::GetFullPath([string]$command.Source))}}
    $paths=@($paths|Select-Object -Unique);if($paths.Count-ne1){throw 'Campaign E M1 requires exactly one Multipass executable.'};$multipass=$paths[0]
    $multipassSha=(Get-FileHash -LiteralPath $multipass -Algorithm SHA256).Hash.ToLowerInvariant()
    if($multipassSha-cne[string]$request.expectedMultipassSha256){$multipass='';throw 'Campaign E M1 Multipass executable hash differs from the checkpoint.'}
    $boundaryBefore=Get-ProductBoundary;if([bool]$boundaryBefore.activeTransactionPresent-or[int]$boundaryBefore.stageMarkerCount-ne0){throw 'Campaign E M1 requires a transactionless marker-free boundary.'}
    if($profile){
        $backendBefore=Get-DevFleetCampaignEBackendSnapshot -InstanceName $instanceName -SinceUtc $observedSince -OwnerDeadlineUtc $operationDeadline
        Write-FreshAtomicJson (Join-Path $remoteRoot 'backend-before.json') $backendBefore
        if([string]$backendBefore.status-cne'COMPLETE'-or[int]$backendBefore.data.backend.foreignCount-ne0-or@($backendBefore.data.backend.owned).Count){throw 'M2 requires a complete independent empty backend baseline.'}
    }
    $baseline=Invoke-DevFleetBoundedNativeProbe -Operation 'baseline-inventory' -FilePath $multipass -ArgumentList @('list','--format','json') -TimeoutSeconds 60 -OwnerDeadlineUtc $operationDeadline -ForceLegacyArgumentString
    $preflight=Get-NativeSummary $baseline;if([string]$baseline.outcome-cne'PASS'-or-not[bool]$baseline.outputComplete-or[bool]$baseline.stdoutTruncated){throw 'Campaign E M1 baseline inventory failed.'};$rows=@(Get-InventoryRows ([string]$baseline.stdout));if($rows.Count-ne0){throw 'Campaign E M1 diagnostic checkpoint inventory is not empty.'}
    $writeRecord=${function:Write-FreshAtomicJson};$summarize=${function:Get-NativeSummary}
    $provider={
        param($operation,$path,$arguments,$seconds,$deadline)
        if($profile){&$writeRecord (Join-Path $remoteRoot ($operation+'-start.json')) ([ordered]@{operation=$operation;startedAtUtc=[datetime]::UtcNow.ToString('o');ownerDeadlineUtc=$deadline.ToUniversalTime().ToString('o');maximumSeconds=$seconds;arguments=@($arguments)})}
        if($operation-ceq'launch'){$launchState.callStarted=$true}
        if($productLaunch-and$operation-ceq'launch'){
            $originalData=$env:ProgramData
            try{$env:ProgramData=Join-Path $remoteRoot 'profile-data';$raw=Invoke-DevFleetCampaignECandidateNativeLaunch -CandidateCommonModule $candidateCommon -FilePath $path -ArgumentList @($arguments) -MaximumSeconds $seconds -OwnerDeadlineUtc $deadline}finally{$env:ProgramData=$originalData}
        }else{$raw=Invoke-DevFleetBoundedNativeProbe -Operation $operation -FilePath $path -ArgumentList @($arguments) -TimeoutSeconds $seconds -OwnerDeadlineUtc $deadline -ForceLegacyArgumentString -MaxStdoutCharacters 32768 -MaxStderrCharacters 4096}
        if($profile){
            $endRecord=&$summarize $raw
            $endRecord|Add-Member -NotePropertyName stdout -NotePropertyValue (ConvertTo-DevFleetDiagnosticSafeText $raw.stdout 32768)
            $endRecord|Add-Member -NotePropertyName stderr -NotePropertyValue (ConvertTo-DevFleetDiagnosticSafeText $raw.stderr 4096)
            $endRecord|Add-Member -NotePropertyName stdoutTruncated -NotePropertyValue ([bool]$raw.stdoutTruncated)
            foreach($field in @('adapter','pidEvidence','nativeMaximumSeconds','captureMode')){if($raw.PSObject.Properties[$field]){$endRecord|Add-Member -NotePropertyName $field -NotePropertyValue $raw.$field}}
            &$writeRecord (Join-Path $remoteRoot ($operation+'-end.json')) $endRecord
        }
        $raw
    }.GetNewClosure()
    $sequence=Invoke-DevFleetCampaignEMultipassM1Sequence -RunId $runId -InstanceName $instanceName -UbuntuImage ([string]$request.ubuntuImage) -MultipassPath $multipass -OwnerDeadlineUtc $operationDeadline -NativeProbeProvider $provider -Resources $resources -CloudInitPath $cloudInitPath
    if([string]$sequence.status-cne'PASS'){$primaryError=[string]$sequence.primaryError}
} catch {$primaryError=ConvertTo-CampaignEM1FailureText $_.Exception.Message}
finally {
    if($profile-and$backendBefore){try{
        $backendAfter=Get-DevFleetCampaignEBackendSnapshot -InstanceName $instanceName -SinceUtc $observedSince -OwnerDeadlineUtc $owner
        Write-FreshAtomicJson (Join-Path $remoteRoot 'backend-before-cleanup.json') $backendAfter
        if([string]$backendAfter.status-cne'COMPLETE'-and-not$primaryError){$primaryError='M2 independent backend observation before cleanup was incomplete.'}
    }catch{if(-not$primaryError){$primaryError=ConvertTo-CampaignEM1FailureText $_.Exception.Message}}}
    if($multipass-and$instanceName){
        if($launchState.callStarted){try{$delete=Invoke-DevFleetBoundedNativeProbe -Operation 'delete-owned' -FilePath $multipass -ArgumentList @('delete','--purge',$instanceName) -TimeoutSeconds 120 -OwnerDeadlineUtc $owner -ForceLegacyArgumentString;$cleanup.delete=Get-NativeSummary $delete;if([string]$delete.outcome-cne'PASS'-or-not[bool]$delete.outputComplete){throw 'Owned delete did not complete successfully.'}}catch{$cleanup.delete=[ordered]@{outcome='UNVERIFIED';error=ConvertTo-CampaignEM1FailureText $_.Exception.Message};if(-not$primaryError){$primaryError=ConvertTo-CampaignEM1FailureText $_.Exception.Message}}}
        try{
            $inventory=Invoke-DevFleetBoundedNativeProbe -Operation 'final-inventory' -FilePath $multipass -ArgumentList @('list','--format','json') -TimeoutSeconds 60 -OwnerDeadlineUtc $owner -ForceLegacyArgumentString;$cleanup.inventory=Get-NativeSummary $inventory
            if([string]$inventory.outcome-cne'PASS'-or-not[bool]$inventory.outputComplete-or[bool]$inventory.stdoutTruncated){throw 'Final inventory command output is incomplete.'}
            $rows=@(Get-InventoryRows ([string]$inventory.stdout));$cleanup.finalInventoryCount=$rows.Count
            if($rows.Count-ne0){throw 'Final inventory contains an owned or foreign instance.'}
            $cleanup.status='ABSENT_VERIFIED'
        }catch{$cleanup.status='UNVERIFIED';if(-not$primaryError){$primaryError=ConvertTo-CampaignEM1FailureText $_.Exception.Message}}
    }
    if($profile-and$backendBefore){try{
        $backendFinal=Get-DevFleetCampaignEBackendSnapshot -InstanceName $instanceName -SinceUtc $observedSince -OwnerDeadlineUtc $owner
        Write-FreshAtomicJson (Join-Path $remoteRoot 'backend-after-cleanup.json') $backendFinal
        if(-not$backendFinal.PSObject.Properties['data']-or[string]$backendFinal.data.backend.status-cne'PASS'-or[int]$backendFinal.data.backend.foreignCount-ne0-or@($backendFinal.data.backend.owned).Count){throw 'M2 final independent backend did not prove empty inventory.'}
    }catch{$cleanup.status='UNVERIFIED';if(-not$primaryError){$primaryError=ConvertTo-CampaignEM1FailureText $_.Exception.Message}}}
    try{$boundaryAfter=Get-ProductBoundary}catch{$boundaryAfter=[ordered]@{activeTransactionPresent=$true;stageMarkerCount=-1};if(-not$primaryError){$primaryError='Campaign E M1 final product boundary was unavailable.'}}
    $status=if($sequence-and[string]$sequence.status-ceq'PASS'-and[string]$cleanup.status-ceq'ABSENT_VERIFIED'-and-not$primaryError-and-not[bool]$boundaryAfter.activeTransactionPresent-and[int]$boundaryAfter.stageMarkerCount-eq0){'PASS_DIAGNOSTIC'}else{'BLOCKED'}
    $result=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_M1_RESULT';status=$status;runId=$runId;vmId=$vmId;payloadSha256=$payloadSha;instanceName=$instanceName;ubuntuImage=if($request){[string]$request.ubuntuImage}else{''};ownerDeadlineUtc=if($owner-gt[datetime]::MinValue){$owner.ToString('o')}else{''};producedAtUtc=[datetime]::UtcNow.ToString('o');multipassSha256=$multipassSha;launchCallStarted=[bool]$launchState.callStarted;experiment=if($productLaunch){'M3'}elseif($profile){'M2'}else{'M1'};executionContext=$workerContext;productProfile=$profile;backendBefore=$backendBefore;backendBeforeCleanup=$backendAfter;backendAfterCleanup=$backendFinal;boundaryBefore=$boundaryBefore;preflight=$preflight;sequence=$sequence;cleanup=$cleanup;boundaryAfter=$boundaryAfter;primaryError=$primaryError;productLifecycleStarted=$false;productProgressClaimed=$false}
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
    $result.stage=[ordered]