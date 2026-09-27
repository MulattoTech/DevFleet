# DevFleet source part 010

Full-source UTF-8 byte interval [418500, 465000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 57b7d4308928d6bfcabf4c43f6647bea4f51e0c6c265bc69ab2da1e75042fef3

<!-- BEGIN SOURCE SLICE -->
ConvertFrom-Json
            if([string]$o.runId-cne$Run-or[string]$o.nonce-cne$Nonce){throw 'M4 collector staging ownership mismatch.'}
            $self=(Get-Process -Id $PID).Path;if((Get-FileHash $self -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$request.powerShellHash){throw 'M4 collector PowerShell checkpoint hash mismatch.'}
            $policyBefore=@{};foreach($scope in @('MachinePolicy','UserPolicy','LocalMachine','CurrentUser')){$policyBefore[$scope]=[string](Get-ExecutionPolicy -Scope $scope)}
            $module=Join-Path $Path 'MultipassDiagnostic.psm1';if((Get-FileHash $module -Algorithm SHA256).Hash.ToLowerInvariant()-cne$Hash){throw 'M4 collector module hash mismatch.'}
            Import-Module $module -Force -DisableNameChecking
            $snapshot=Get-DevFleetCampaignEBackendSnapshot -InstanceName 'devfleet-primary' -SinceUtc ([DateTimeOffset]::FromUnixTimeMilliseconds([long]$request.since).UtcDateTime) -OwnerDeadlineUtc ([DateTimeOffset]::FromUnixTimeMilliseconds([long]$request.cutoff).UtcDateTime) -TimeoutSeconds 30 -ProductContext -ExpectedPayloadSha256 ([string]$request.payload)
            foreach($scope in $policyBefore.Keys){if([string](Get-ExecutionPolicy -Scope $scope)-cne$policyBefore[$scope]){throw 'M4 persistent execution policy changed during observation.'}}
            $snapshot|Add-Member -NotePropertyName delivery -NotePropertyValue @{powerShellVersion=$PSVersionTable.PSVersion.ToString();powerShellHash=[string]$request.powerShellHash;workerPid=$PID;persistentPolicyUnchanged=$true;persistentPolicyBefore=$policyBefore;processOnlyExecutionPolicy=[string](Get-ExecutionPolicy -Scope Process)}
            $snapshot|ConvertTo-Json -Depth 24 -Compress
        }
        $powerShell=@(Invoke-DevFleetBoundedGuestCommand -Session $captureSession -TimeoutSeconds 10 -ScriptBlock {param($Hash)$path=Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe';if((Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()-cne$Hash){throw 'M4 collector executable hash mismatch.'};$path} -ArgumentList @([string]$cp.powershell.pathSha256))|Select-Object -Last 1
        $request=@{path=$remoteRoot;run=$RunId;nonce=$nonce;hash=$moduleHash;payload=$payload;powerShellHash=[string]$cp.powershell.pathSha256;since=[DateTimeOffset]::new($since).ToUnixTimeMilliseconds();cutoff=[DateTimeOffset]::new($cutoff).ToUnixTimeMilliseconds()}|ConvertTo-Json -Compress
        $requestBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(('& {'+$collector.ToString()+"} '"+$requestBase64+"'")))
        $process=Invoke-DevFleetBoundedGuestProcess -Session $captureSession -FilePath ([string]$powerShell) -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -OwnerDeadlineUtc $cutoff
        if([string]$process.outcome-cne'PASS'-or-not[bool]$process.outputComplete){throw "M4 collector process failed: $([string]$process.outcome) $(ConvertTo-DevFleetDiagnosticSafeText $process.stderr 1024)"}
        $observation=[string]$process.stdout|ConvertFrom-Json -ErrorAction Stop
        if(-not$observation){throw 'M4 collector returned no snapshot.'}
    }catch{$observation=[pscustomobject]@{status='UNAVAILABLE';startedAtUtc=$observedStart.ToString('o');producedAtUtc=[datetime]::UtcNow.ToString('o');error=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 1024}}
    finally{if($captureSession){Remove-PSSession $captureSession -ErrorAction SilentlyContinue}}
    $script:snapshotIndex++;$name=('snapshot-{0:d4}-{1}.json'-f$snapshotIndex,$Edge);$path=Join-Path $runDir $name
    if(Test-Path $path){throw 'M4 snapshot path is not fresh.'};Write-EvidenceJson -Path $path -Value $observation
    $result.observations+=@{path=$name;sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant();status=$observation.status;edge=$Edge}
    $script:since=$observedStart.AddSeconds(-2)
    Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-m4.json') -Value $result
    return $observation
}
try{
    New-Item -ItemType Directory -Path $runDir|Out-Null;Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-m4.json') -Value $result
    $cpRecord=Get-Content $checkpointPath -Raw|ConvertFrom-Json;$cp=$cpRecord.diagnosticCheckpoint
    if([string]$cpRecord.status-cne'PASS_CHECKPOINT_READY'-or[string]$cpRecord.campaign-cne'DF-STABLE-20260906-E'-or[guid]$cp.vmId-ne$vmId-or[guid]$cp.parentSnapshotId-ne$cleanId-or[string]$cp.l1State-cne'OFF'-or[string]$cp.l2Status-cne'ABSENT'){throw 'M4 prerequisite identity/state is invalid.'}
    $vm=Get-VM -Id $vmId -ErrorAction Stop;if($vm.Name-cne$vmName-or$vm.Id-ne$vmId-or$vm.State-ne'Off'){throw 'M4 requires the exact idle L1.'};Assert-DisposableOwnership -Vm $vm -ExpectedId $vmId.ToString()|Out-Null
    $matches=@(Get-VMSnapshot -VM $vm|Where-Object{$_.Id-eq[guid]$cp.id-and$_.Name-ceq[string]$cp.name-and$_.VMId-eq$vmId-and$_.ParentSnapshotId-eq$cleanId});if($matches.Count-ne1){throw 'M4 live prerequisite binding failed.'};$checkpoint=$matches[0]
    $fingerprint=Get-CandidateFingerprint -WorkspaceRoot $root;$payload=[string]$fingerprint.tar.sha256
    $authority=Get-Content (Join-Path $root 'evidence/CURRENT-RELEASE-AUTHORITY.json') -Raw|ConvertFrom-Json;$head=(&git -C $root rev-parse HEAD).Trim()
    if(-not$authority.candidateIsCurrent-or$authority.sourceChangedSinceCandidate-or$authority.rebuildRequired-or[string]$authority.repositoryHead-cne$head-or$payload-cne[string]$cp.payloadSha256){throw 'M4 current candidate/checkpoint coherence failed.'}
    foreach($field in @('shippingInputIdentity','releaseFingerprintId','toolingFingerprintId')){if([string]$authority.$field-cne[string]$fingerprint.$field){throw 'M4 native authority tuple mismatch.'}}
    $result.tuple=[ordered]@{repositoryHead=$head;candidateCommit=$fingerprint.gitCommit;shippingInputIdentity=$fingerprint.shippingInputIdentity;releaseFingerprintId=$fingerprint.releaseFingerprintId;toolingFingerprintId=$fingerprint.toolingFingerprintId;payloadSha256=$payload}
    $result.sourceCheckpoint=@{name=$checkpoint.Name;id=$checkpoint.Id.ToString();parentSnapshotId=$cleanId.ToString();evidenceSha256=(Get-FileHash $checkpointPath -Algorithm SHA256).Hash.ToLowerInvariant()}
    $safety=Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB 14.38;$result.hostSafety=@{startSafe=[bool]$safety.startSafe;availableMemoryGiB=$safety.availableMemoryGiB;projectedPostStartAvailableMemoryGiB=$safety.projectedPostStartAvailableMemoryGiB};if(-not$safety.startSafe){throw 'M4 HOST-SAFETY failed.'}
    $acquired=$true;$result.restore=Restore-ExactCheckpoint -Vm $vm -Name $checkpoint.Name -StartAfterRestore
    $result.interactiveDesktop=Ensure-FullReleaseInteractiveDesktop -VmId $vmId
    $session=Connect-DevFleetGuest -VmId $vmId;$result.initialL2=Get-DevFleetNestedL2State -Session $session -ExpectedName ([string]$config.NestedLinux.Name)
    if([string]$result.initialL2.status-cne'ABSENT'){throw 'M4 initial L2 is not positively absent.'}
    $null=Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {
        param($Path,$Run,$Nonce)
        if($Path-cne("C:\Users\Public\DevFleet-E2E\"+$Run+'\M4')-or(Test-Path $Path)){throw 'M4 staging is not a fresh run-owned path.'}
        $state=Join-Path $env:ProgramData 'DevFleet';if((Test-Path (Join-Path $state 'active-transaction.json'))-or@(Get-ChildItem $state -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue).Count){throw 'M4 baseline has product state.'}
        New-Item -ItemType Directory -Path $Path|Out-Null;@{runId=$Run;nonce=$Nonce}|ConvertTo-Json|Set-Content (Join-Path $Path '.owner.json') -Encoding utf8
    } -ArgumentList @($remoteRoot,$RunId,$nonce);$stagingOwned=$true
    $localModule=Join-Path $root 'automation/release-e2e/modules/MultipassDiagnostic.psm1';$moduleHash=(Get-FileHash $localModule -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.collectorStage=Copy-DevFleetBoundedGuestFile -LocalPath $localModule -Session $session -RemotePath (Join-Path $remoteRoot 'MultipassDiagnostic.psm1') -TimeoutSeconds 60
    Remove-PSSession $session;$session=$null
    $baseline=Save-M4Snapshot 'before-product'
    if([string]$baseline.status-cne'COMPLETE'-or[string]$baseline.data.backend.status-cne'PASS'-or[int]$baseline.data.backend.foreignCount-ne0-or@($baseline.data.backend.owned).Count){throw 'M4 independent initial observation is incomplete or the backend is not empty.'}
    $context=[ordered]@{runId=$RunId;phaseId='CAMPAIGN-E-M4';workspaceRoot=$root;runDir=$runDir;vmId=$vmId.ToString();vmName=$vmName;candidate=$fingerprint;config=$config;deadlinePolicy=$policy;role='Primary / Desktop';diagnosticOnly=$true;certificationEligible=$false}
    $phaseModule=Join-Path $root 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1'
    $job=Start-Job -ScriptBlock {param($Module,$ContextJson)Import-Module $Module -Force;Invoke-ProductFreshInstallLifecycle -Context ($ContextJson|ConvertFrom-Json) -Role 'Primary / Desktop'} -ArgumentList @($phaseModule,($context|ConvertTo-Json -Depth 32 -Compress))
    $result.status='RUNNING';$result.lifecycleJobId=$job.Id
    Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-m4.json') -Value $result
    do{
        $finished=Wait-Job -Job $job -Timeout 30
        if([datetime]::UtcNow-ge$owner){throw 'M4 immutable outer owner deadline expired.'}
        if($finished){break}
        $null=Save-M4Snapshot 'during-product'
    }while($true)
    $values=@(Receive-Job -Job $job -ErrorAction Stop);if(-not$values.Count){throw 'M4 product lifecycle returned no terminal evidence.'}
    if([datetime]::UtcNow-ge$owner){throw 'M4 product terminal arrived after the immutable outer deadline.'}
    $product=$values[-1];$productError=if($product-is[Collections.IDictionary]){[string]$product['error']}elseif($product.PSObject.Properties['error']){[string]$product.error}else{''}
    $result.product=[ordered]@{status=[string]$product.status;completionVerified=[bool]$product.completionVerified;transactionId=[string]$product.transactionId;payloadSha256=[string]$product.payloadSha256;evidencePath=[string]$product.evidencePath;error=ConvertTo-DevFleetDiagnosticSafeText $productError 2048}
    if([string]$product.status-cne'REAL E2E PASS'-or-not[bool]$product.completionVerified){throw "M4 real product lifecycle did not verify completion: $([string]$result.product.error)"}
    $result.status='PASS_DIAGNOSTIC'
}catch{$result.status='BLOCKED';$result.primaryError=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 2048}
finally{
    if($job){if($job.State-in@('Running','NotStarted')){$lifecycleForcedStop=$true;Stop-Job -Job $job -ErrorAction SilentlyContinue};Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
    if($session){Remove-PSSession $session -ErrorAction SilentlyContinue;$session=$null}
    if($acquired-and$stagingOwned){try{$terminalSnapshot=Save-M4Snapshot 'before-cleanup'}catch{$result.preCleanupEvidenceError=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 1024;$terminalSnapshot=$null}}
    $result.cleanup=[ordered]@{status='UNVERIFIED';acquired=$acquired;evidenceBeforeRestore=$false;lifecycleForcedStop=$lifecycleForcedStop}
    try{
        if($acquired){
            $vm=Get-VM -Id $vmId -ErrorAction Stop;if($vm.Name-cne$vmName-or$vm.Id-ne$vmId){throw 'M4 cleanup exact L1 identity mismatch.'};Assert-DisposableOwnership -Vm $vm -ExpectedId $vmId.ToString()|Out-Null
            # A failed collector cannot silently erase the state we needed to diagnose.
            if($lifecycleForcedStop){throw 'M4 lifecycle was forcibly stopped; checkpoint restore withheld for causal inspection.'}
            if($stagingOwned-and(-not$terminalSnapshot-or[string]$terminalSnapshot.status-cne'COMPLETE'-or[string]$terminalSnapshot.data.backend.status-cne'PASS'-or[int]$terminalSnapshot.data.backend.foreignCount-ne0)){throw 'M4 pre-cleanup evidence is incomplete or contains a foreign instance; checkpoint restore withheld.'}
            $result.cleanup.evidenceBeforeRestore=$stagingOwned
            $result.cleanup.restore=Restore-ExactCheckpoint -Vm $vm -Name $checkpoint.Name -StartAfterRestore
            $session=Connect-DevFleetGuest -VmId $vmId;$result.finalL2=Get-DevFleetNestedL2State -Session $session -ExpectedName ([string]$config.NestedLinux.Name)
            $independent=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 25 -ScriptBlock { $vms=@(Get-VM -ErrorAction Stop);[pscustomobject]@{status='COMPLETE';count=$vms.Count;ids=@($vms|ForEach-Object{$_.Id.ToString()})}})|Select-Object -Last 1
            $result.cleanup.independentFinalBackend=$independent
            if([string]$result.finalL2.status-cne'ABSENT'-or[string]$independent.status-cne'COMPLETE'-or[int]$independent.count-ne0){throw 'M4 final CLI/backend absence is unverified.'}
            $result.cleanup.status='PASS'
        }
    }catch{$result.cleanup.error=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 1024;$result.status='BLOCKED'}
    finally{
        if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}
        try{$vm=Get-VM -Id $vmId -ErrorAction Stop;if($vm.Name-cne$vmName-or$vm.Id-ne$vmId){throw 'M4 final identity mismatch.'};if($acquired-and$vm.State-ne'Off'){Stop-VM -VM $vm -Force -Confirm:$false};$stopDeadline=[datetime]::UtcNow.AddSeconds(60);do{$vm=Get-VM -Id $vmId -ErrorAction Stop;if($vm.State-eq'Off'-or-not$acquired){break};Start-Sleep 2}while([datetime]::UtcNow-lt$stopDeadline);$result.finalL1=@{state=$vm.State.ToString();id=$vm.Id.ToString();name=$vm.Name;observedAtUtc=[datetime]::UtcNow.ToString('o')}}catch{$result.finalL1=@{state='UNVERIFIED';error=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message}}
    }
    if([string]$result.finalL1.state-cne'Off'-or($acquired-and[string]$result.cleanup.status-cne'PASS')){$result.status='BLOCKED'}
    $result.completedAtUtc=[datetime]::UtcNow.ToString('o');Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-m4.json') -Value $result
}
[pscustomobject]$result
if([string]$result.status-cne'PASS_DIAGNOSTIC'){exit 1}

```


## FILE: automation/release-e2e/Invoke-CampaignEProductProfile.ps1

SHA256: c847254fa8dee61846823091bc7944f4ee0ae95e832fa47cab2b02bacf4ff2cb | Bytes: 8275 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9+/=]+$')][string]$RequestBase64)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$originalData=$env:ProgramData;$resultPath='';$request=$null
$result=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PRODUCT_PROFILE';status='BLOCKED';startedAtUtc=[datetime]::UtcNow.ToString('o');productLifecycleStarted=$false;primaryError=''}
try {
    $request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))|ConvertFrom-Json -ErrorAction Stop
    $run=[string]$request.runId;$vm=[guid][string]$request.vmId;$payload=[string]$request.payloadSha256
    if($run-notmatch'^[A-Za-z0-9._-]+$'-or$vm-ne[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'-or$payload-notmatch'^[0-9a-f]{64}$'){throw 'Product profile identity is invalid.'}
    $remoteRoot=[IO.Path]::GetFullPath([string]$request.remoteRoot).TrimEnd('\')
    if($remoteRoot-cne"C:\Users\Public\DevFleet-E2E\$run\M1"){throw 'Product profile escaped the exact run staging path.'}
    $ancestor=$remoteRoot
    while($ancestor.Length-ge'C:\Users\Public\DevFleet-E2E'.Length){if((Get-Item -LiteralPath $ancestor).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Product profile staging ancestry is a reparse point.'};$ancestor=Split-Path -Parent $ancestor}
    $ownership=Get-Content (Join-Path $remoteRoot '.owner.json') -Raw|ConvertFrom-Json
    if([string]$ownership.kind-cne'DEVFLEET_CAMPAIGN_E_STAGING_OWNER'-or[string]$ownership.runId-cne$run-or[guid][string]$ownership.nonce-ne[guid][string]$request.stagingNonce){throw 'Product profile staging ownership mismatch.'}
    $resultPath=Join-Path $remoteRoot 'product-profile.json'
    $deadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.deadlineUnixMilliseconds).UtcDateTime
    if($deadline-le[datetime]::UtcNow){throw 'Product profile owner expired.'}
    $result.runId=$run;$result.vmId=$vm.ToString();$result.payloadSha256=$payload;$result.ownerDeadlineUtc=$deadline.ToString('o')
    $required=@('windows/00-Preflight.ps1','windows/DevFleet.Common.psm1','config/devfleet.config.json')
    $productLaunch=$request.PSObject.Properties['productLaunch']-and[bool]$request.productLaunch
    if($productLaunch){$required+='cloud-init/compute.yaml'}
    $inputs=@($request.inputs)
    if($inputs.Count-ne$required.Count){throw 'Product profile input count is invalid.'}
    $package=Join-Path $remoteRoot 'profile-package'
    foreach($directory in @($package,(Join-Path $package 'windows'),(Join-Path $package 'config'))){if((Get-Item -LiteralPath $directory).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Product profile package directory is a reparse point.'}}
    if($productLaunch-and((Get-Item -LiteralPath (Join-Path $package 'cloud-init')).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Product cloud-init directory is a reparse point.'}
    foreach($relative in $required){
        $entry=@($inputs|Where-Object{[string]$_.path-ceq$relative})
        if($entry.Count-ne1-or[string]$entry[0].sha256-notmatch'^[0-9a-f]{64}$'){throw 'Product profile exact input binding is missing.'}
        $path=Join-Path $package $relative
        if((Get-Item -LiteralPath $path).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Product profile input is a reparse point.'}
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$entry[0].sha256){throw 'Product profile candidate input hash mismatch.'}
    }
    $realState=Join-Path $originalData 'DevFleet'
    if((Test-Path (Join-Path $realState 'active-transaction.json'))-or@(Get-ChildItem $realState -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue).Count){throw 'Product profile requires a transactionless marker-free diagnostic baseline.'}
    $data=Join-Path $remoteRoot 'profile-data'
    if(Test-Path $data){throw 'Product profile isolated state already exists.'}
    New-Item -ItemType Directory -Path (Join-Path $data 'DevFleet') | Out-Null
    Copy-Item -LiteralPath (Join-Path $package 'config/devfleet.config.json') -Destination (Join-Path $data 'DevFleet/devfleet.config.json')
    $configInput=@($inputs|Where-Object{$_.path-ceq'config/devfleet.config.json'})[0]
    if((Get-FileHash (Join-Path $data 'DevFleet/devfleet.config.json') -Algorithm SHA256).Hash.ToLowerInvariant()-cne[string]$configInput.sha256){throw 'Product profile copied configuration hash mismatch.'}
    $system=Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop
    $result.measured=[ordered]@{totalPhysicalMemoryBytes=[int64]$system.TotalPhysicalMemory;logicalProcessors=[int]$system.NumberOfLogicalProcessors}
    # Run the actual candidate preflight. Only its config destination is isolated;
    # CPU/RAM/virtualization/disk observations are the real disposable Windows guest.
    $env:ProgramData=$data
    & (Join-Path $package 'windows/00-Preflight.ps1') -Role Desktop -InstallationMode Connected | Out-Null
    $effective=Get-Content (Join-Path $data 'DevFleet/devfleet.config.json') -Raw|ConvertFrom-Json
    $node=$effective.Primary
    if([int]$node.Cpus-lt2-or[string]$node.Memory-notmatch'^\d+G$'-or[string]$node.Disk-notmatch'^\d+G$'-or[string]$node.UbuntuImage-notmatch'^\d+\.\d+$'){throw 'Actual preflight produced an unsupported launch profile.'}
    if([datetime]::UtcNow-gt$deadline){throw 'Product profile finished after its immutable owner deadline.'}
    $result.resources=[ordered]@{cpus=[int]$node.Cpus;memory=[string]$node.Memory;disk=[string]$node.Disk}
    if($productLaunch){
        $name=[string]$request.instanceName
        if($name-cne"DevFleet-E2E-E-M1-$run"){throw 'Product cloud-init requires the exact run-owned instance name.'}
        # Same candidate template and scalar helpers as 02-Provision-ComputeNode.
        # Only the diagnostic hostname and isolated output destination differ.
        $cloud=Join-Path $remoteRoot 'product-cloud-init.yaml'
        if(Test-Path $cloud){throw 'Product cloud-init output already exists.'}
        $template=Get-Content (Join-Path $package 'cloud-init/compute.yaml') -Raw
        $template=$template.Replace('__NODE_NAME__',(ConvertTo-YamlSingleQuotedScalar $name)).Replace('__NODE_ROLE__',(ConvertTo-YamlSingleQuotedScalar 'primary')).Replace('__GIT_NAME_SHELL__',(ConvertTo-ShellSingleQuotedScalar $effective.Git.UserName)).Replace('__GIT_EMAIL_SHELL__',(ConvertTo-ShellSingleQuotedScalar $effective.Git.Email))
        Set-Content -LiteralPath $cloud -Value $template -Encoding utf8
        $result.productLaunch=[ordered]@{mode='CANDIDATE_CLOUD_INIT_AND_INVOKE_EXTERNAL';cloudInitFileName='product-cloud-init.yaml';cloudInitSha256=(Get-FileHash $cloud -Algorithm SHA256).Hash.ToLowerInvariant();instanceName=$name;nodeRole='primary';productTransactionStarted=$false;stageMarkerWritten=$false}
    }
    if([datetime]::UtcNow-gt$deadline){throw 'Product profile/render finished after its immutable owner deadline.'}
    $result.ubuntuImage=[string]$node.UbuntuImage;$result.productInstanceName=[string]$node.InstanceName
    $result.inputs=$inputs;$result.preflightConfigSha256=(Get-FileHash (Join-Path $data 'DevFleet/devfleet.config.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.childRuntime=$PSVersionTable.PSVersion.ToString();$result.status='PASS_PROFILE_ONLY'
} catch {
    $message=[regex]::Replace([string]$_.Exception.Message,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    $result.primaryError=if($message.Length-gt1024){$message.Substring($message.Length-1024)}else{$message}
} finally {
    $env:ProgramData=$originalData
    $result.producedAtUtc=[datetime]::UtcNow.ToString('o')
    if($resultPath){
        if(Test-Path -LiteralPath $resultPath){throw 'Product profile refuses to overwrite a durable result.'}
        $tmp=$resultPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try{[IO.File]::WriteAllText($tmp,($result|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false));[IO.File]::Move($tmp,$resultPath)}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
    }
    [Console]::Out.Write(($result|ConvertTo-Json -Depth 10 -Compress))
}
if([string]$result.status-cne'PASS_PROFILE_ONLY'){exit 1}

```


## FILE: automation/release-e2e/Invoke-DevFleetReleaseE2E.ps1

SHA256: 2e8aa82516205b5470d433f428f7548ea72b1527e3738fc838dc2e0c424910f2 | Bytes: 19523 | Git mode: 100644

```
[CmdletBinding()]
param(
    [ValidateSet('Preflight','Quick','FullRelease','Resume','Closeout','PlanOnly','LaptopPreflight','LaptopPlanOnly','LaptopInstallAndSmoke','LaptopResume','LaptopEvidence')][string]$Mode='Preflight',
    [string]$Candidate,
    [string]$WorkspaceRoot,
    [string]$ConfigPath,
    [string]$VmName,
    [Nullable[int]]$MinAvailableMemoryGiB,
    [double]$ExpectedVmStartCostGiB,
    [string]$RunId,
    [string]$RunStatePath,
    [switch]$ResumeLast,
    [switch]$SyntheticResume,
    [switch]$ConfirmDisposableLab,
    [switch]$ExecuteExpensive,
    [switch]$Cleanup,
    [switch]$KeepLab,
    [switch]$AllowRamPressure
)
$ErrorActionPreference='Stop'
$scriptRoot=$PSScriptRoot
if (-not $WorkspaceRoot) { $WorkspaceRoot=(Resolve-Path (Join-Path $scriptRoot '..\..')).Path }
else { $WorkspaceRoot=(Resolve-Path $WorkspaceRoot).Path }
if (-not $ConfigPath) { $ConfigPath=Join-Path $scriptRoot 'config\devfleet-e2e.defaults.json' }
$config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$budgetModule=Join-Path $scriptRoot 'modules\HarnessBudget.psm1'
Import-Module $budgetModule -Force
$budgetPolicy=Get-HarnessBudgetPolicy -Config $config
Assert-HarnessBudgetPolicy -Policy $budgetPolicy | Out-Null
if (-not $PSBoundParameters.ContainsKey('ExpectedVmStartCostGiB')) { $ExpectedVmStartCostGiB=[double]$config.ExpectedVmStartCostGiB }
foreach($m in @('Candidate','HostSafety','ResumeState','Evidence','Cleanup','GuestSession','TailscaleE2E','FullRelease')) { Import-Module (Join-Path $scriptRoot "modules\$m.psm1") -Force }

# FullRelease imports this module privately; expose its cleanup API to this caller.
Import-Module (Join-Path $scriptRoot 'modules\InteractiveLogon.psm1')

function Invoke-RequiredReleaseFinalizer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PowerShellPath,[Parameter(Mandatory)][string]$FinalizerPath,[string[]]$ArgumentList=@())
    $output=@(& $PowerShellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FinalizerPath @ArgumentList 2>&1)
    $childExitCode=$LASTEXITCODE
    if($childExitCode -ne 0){throw "Mandatory finalizer process exited with code $childExitCode."}
    return $output
}

$script:DevFleetFinalConvergencePrimaryBlocker = $null
try {

function Save-State([psobject]$State,[string]$Path) { Save-RunState -State $State -Path $Path }
function Gate([string]$Name,[string]$Status,[string]$Details) { New-GateRecord -Name $Name -Status $Status -Details $Details }
function Show-Result([string]$label,[string]$status,[string]$detail) { Write-Host "[$status] $label - $detail" }

if (($Mode -eq 'Resume' -or $ResumeLast) -and -not $RunStatePath) {
    $latest=Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'audit\automation-harness\runs') -Filter run-state.json -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No durable harness run-state exists to resume.' }
    $RunStatePath=$latest.FullName
}

$fingerprint=Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath $Candidate
$runId=if($RunId){$RunId}else{New-HarnessRunId}
$runDir=New-RunEvidenceDirectory -WorkspaceRoot $WorkspaceRoot -RunId $runId
$statePath=if($RunStatePath){$RunStatePath}else{Join-Path $runDir 'run-state.json'}
$vm=$null; $hostSnapshot=$null
$isLaptopMode=$Mode -like 'Laptop*'
if(-not $isLaptopMode){
    try { $vm=Get-DisposableVm -VmName $VmName -Pattern ([string]$config.DisposableVmNamePattern); Assert-DisposableOwnership -Vm $vm | Out-Null; $hostSnapshot=Apply-RamPressureOverride -Snapshot (Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB $ExpectedVmStartCostGiB) -AllowRamPressure:$AllowRamPressure } catch { if($Mode -ne 'PlanOnly' -and $Mode -ne 'Resume' -and -not $SyntheticResume){ throw }; $hostSnapshot=[pscustomobject]@{status='UNAVAILABLE_IN_SYNTHETIC_OR_PLAN_CONTEXT';error=$_.Exception.Message} }
} else {
    $hostSnapshot=[ordered]@{status='READ_ONLY_LAPTOP_MODE';computerName=$env:COMPUTERNAME;availableMemoryGiB=[math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB,2);productionMutation=$false}
}

$state=[ordered]@{
    schemaVersion=1; harnessVersion=$config.HarnessVersion; runId=$runId; startedAt=(Get-Date).ToUniversalTime().ToString('o'); mode=$Mode
    candidatePath=$fingerprint.candidate.path; candidateVersion=$fingerprint.releaseVersion; installerVersion=$fingerprint.installerVersion
    candidateHashes=[ordered]@{ repositoryHead=$fingerprint.repositoryHead; candidateCommit=$fingerprint.gitCommit; shippingInputIdentity=$fingerprint.shippingInputIdentity; releaseFingerprintId=$fingerprint.releaseFingerprintId; toolingFingerprintId=$fingerprint.toolingFingerprintId; exe=$fingerprint.candidate.sha256; tar=$fingerprint.tar.sha256; portable=$fingerprint.portable.sha256; installerSource=$fingerprint.installerSource.sha256 }
    currentPhase='Preflight'; completedPhases=@(); currentTransaction=$null
    vmName=if($vm){$vm.Name}else{$null}; vmId=if($vm){$vm.Id.ToString()}else{$null}; checkpointIds=@(); projectIds=@(); backupIds=@(); expectedRebootState=$null; userActionState=$null
    evidencePaths=@(); cleanupManifestPath=$null; errors=@(); finalStatus='IN_PROGRESS'; synthetic=[bool]$SyntheticResume
}

if ($Mode -eq 'Resume' -or $ResumeLast) {
    $existing=Read-StrictJson -Path $statePath
    if ($SyntheticResume -and -not $existing.synthetic) { throw 'Synthetic resume refused a non-synthetic state.' }
    if ($existing.vmName -and -not $vm) { $vm=Get-DisposableVm -VmName $existing.vmName -Pattern ([string]$config.DisposableVmNamePattern) }
    Assert-ResumeIdentity -State $existing -Fingerprint $fingerprint -Vm $vm | Out-Null
    $existing.currentPhase='ResumeVerified'; $existing.completedPhases=@($existing.completedPhases)+@('ResumeVerified'); if($existing.PSObject.Properties['finalStatus']){$existing.finalStatus='PASS - resume mechanics verified'}else{$existing | Add-Member -NotePropertyName finalStatus -NotePropertyValue 'PASS - resume mechanics verified'}
    Save-State $existing $statePath
    Write-EvidenceJson -Path (Join-Path $runDir 'resume-verification.json') -Value ([ordered]@{ status='PASS'; candidateHashes=$existing.candidateHashes; vmName=$existing.vmName; vmId=$existing.vmId; synthetic=[bool]$existing.synthetic; statePath=$statePath })
    Show-Result 'Resume identity' 'PASS' 'candidate and recorded disposable identity verified'
    return
}

Save-State $state $statePath
Write-EvidenceJson -Path (Join-Path $runDir 'artifact-hashes.json') -Value $fingerprint
Write-EvidenceJson -Path (Join-Path $runDir 'host-safety.json') -Value $hostSnapshot
$state.evidencePaths=@('artifact-hashes.json','host-safety.json','run-state.json')

if ($Mode -eq 'PlanOnly') {
    $plan=[ordered]@{ status='PASS'; mode='PlanOnly'; candidate=$fingerprint; disposableVm=if($vm){[ordered]@{name=$vm.Name;id=$vm.Id.ToString()}}else{$null}; hostSafety=$hostSnapshot; productionDenyList=@($config.ProductionNameDenyList); phases=@('candidate self-test','clean checkpoint restore','interactive E2EAdmin desktop','dependency matrix','WPF UIA','Primary','independent maintenance checkpoints','stopped project','Tailscale Deferred or OAuthClientSecretStore','reconcile','audit bundles','ownership-proven cleanup'); destructiveActionsPerformed=$false }
    Write-EvidenceJson -Path (Join-Path $runDir 'plan.json') -Value $plan
    $state.currentPhase='PlanOnly'; $state.completedPhases=@('PlanOnly'); $state.finalStatus='PASS - plan generated; no destructive action performed'; Save-State $state $statePath
    Show-Result 'PlanOnly' 'PASS' "candidate $($fingerprint.releaseVersion), no destructive action performed"
    return
}

if($isLaptopMode){
    $laptopEvidence=[ordered]@{status='PASS';mode=$Mode;candidate=$fingerprint;host=$hostSnapshot;role='Laptop / Surrogate';mutationPerformed=$false;productionMutation=$false;actions=@('read-only preflight','verify candidate fingerprint','preserve existing projects and unrelated resources','require explicit coordinator/deployment pairing before install')}
    if($Mode -eq 'LaptopInstallAndSmoke'){$laptopEvidence.status='BLOCKED';$laptopEvidence.reason='Laptop mutation is intentionally not executable from the development/reference host; run this mode on MulattoTechSurface after LaptopPreflight and LaptopPlanOnly.'}
    if($Mode -eq 'LaptopResume'){$laptopEvidence.status='UNVERIFIED';$laptopEvidence.reason='No durable laptop run-state was supplied.'}
    Write-EvidenceJson -Path (Join-Path $runDir 'laptop-mode.json') -Value $laptopEvidence
    $state.currentPhase=$Mode; $state.completedPhases=@($state.completedPhases)+@($Mode); $state.finalStatus=$laptopEvidence.status; Save-State $state $statePath
    $laptopDetail = if($laptopEvidence.reason){ [string]$laptopEvidence.reason } else { 'read-only laptop/surrogate harness validation complete' }
    Show-Result $Mode $laptopEvidence.status $laptopDetail
    return
}

if ($Mode -in @('Quick','Closeout','FullRelease')) {
    $selfTest=Invoke-CandidateSelfTest -Fingerprint $fingerprint
    Write-EvidenceJson -Path (Join-Path $runDir 'self-test.json') -Value $selfTest
    $badChecks=@($selfTest.requiredChecks.GetEnumerator() | Where-Object { $_.Value -ne $true })
    if (($selfTest.result -ne 'PASS') -or ($badChecks.Count -gt 0)) { throw 'Candidate self-test did not satisfy the required contract.' }
    $state.completedPhases=@($state.completedPhases)+@('CandidateVerified'); $state.currentPhase='CandidateVerified'; Save-State $state $statePath
    Show-Result 'Candidate self-test' 'PASS' 'version, payload, extraction, bootstrap, contract, reset gate, and plan safety verified'
}

if ($Mode -eq 'Preflight') {
    $status=if($hostSnapshot.startSafe){'PASS'}else{'USER ACTION'}
    Write-EvidenceJson -Path (Join-Path $runDir 'preflight.json') -Value ([ordered]@{status=$status;candidate=$fingerprint;hostSafety=$hostSnapshot;vmOwnership=if($vm){[ordered]@{name=$vm.Name;id=$vm.Id.ToString();disposable=$true}}else{$null};productionMutation=$false})
    $state.currentPhase='Preflight'; $state.completedPhases=@('Preflight'); $state.finalStatus=$status; Save-State $state $statePath
    Show-Result 'Preflight' $status 'read-only host, candidate, and ownership checks complete'
    return
}

if ($Mode -eq 'Quick') {
    $state.currentPhase='Quick'; $state.completedPhases=@($state.completedPhases)+@('Quick'); $state.finalStatus='PASS'; Save-State $state $statePath
    Show-Result 'Quick' 'PASS' 'candidate and self-test checks complete'; return
}

if ($Mode -eq 'FullRelease') {
    if (-not $ConfirmDisposableLab -or -not $ExecuteExpensive) { throw 'FullRelease is destructive and requires -ConfirmDisposableLab -ExecuteExpensive; use PlanOnly for a non-mutating preview.' }
    if (-not $vm) { throw 'FullRelease requires an ownership-verified disposable VM.' }
    # Bind the current FullRelease RunId before any phase starts.  This is a
    # durable identity pointer, not a PASS claim; promotion remains false
    # until post-cleanup reconciliation consumes the completed evidence.
    try {
        $finalPath=Join-Path $WorkspaceRoot 'finalization-state.json'
        $finalCurrent=(Read-StrictJson -Path $finalPath | ConvertTo-Json -Depth 24 | ConvertFrom-Json -AsHashtable)
        $finalCurrent.full_release_run_id=$runId;$finalCurrent.full_release_current=$true;$finalCurrent.full_release_passed=$false;$finalCurrent.validation_evidence_current=$false;$finalCurrent.internal_promotion_allowed=$false
        $tmp="$finalPath.$([guid]::NewGuid().ToString('N')).tmp";[IO.File]::WriteAllText($tmp,(($finalCurrent|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $tmp -Destination $finalPath -Force
        & (Join-Path $WorkspaceRoot 'tools\Update-CurrentReleaseAuthority.ps1') -Workspace $WorkspaceRoot -FullReleaseRunId $runId | Out-Null
    } catch { throw "Could not bind current FullRelease RunId '$runId' into finalization authority: $($_.Exception.Message)" }
    try {
        $result=Invoke-FullReleaseRun -State $state -Fingerprint $fingerprint -Vm $vm -Config $config -WorkspaceRoot $WorkspaceRoot -RunDir $runDir -StatePath $statePath -HostSnapshot $hostSnapshot -SelfTest $selfTest
        $finalPath=Join-Path $WorkspaceRoot 'finalization-state.json'
        $finalCurrent=(Read-StrictJson -Path $finalPath | ConvertTo-Json -Depth 24 | ConvertFrom-Json -AsHashtable)
        $finalCurrent=Set-FullReleasePassState -FinalizationState $finalCurrent -Result $result -ExpectedRunId $runId
        $tmp="$finalPath.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            [IO.File]::WriteAllText($tmp,(($finalCurrent|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $tmp -Destination $finalPath -Force
        } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        & (Join-Path $WorkspaceRoot 'tools\Update-CurrentReleaseAuthority.ps1') -Workspace $WorkspaceRoot -FullReleaseRunId $runId | Out-Null
        Show-Result 'FullRelease' 'PASS' 'all configured real product phases completed with durable evidence'
        return
    } catch {
        $primaryFailure=$_
        $failureCleanupRecord=[ordered]@{schemaVersion=1;runId=$runId;status='NOT_RUN';scope='failure-handler-only';certifiedReleaseCleanup=$false;primaryFailurePreserved=$true;boundary='policy';startedAt=(Get-Date).ToUniversalTime().ToString('o')}
        if (-not $KeepLab -and $vm) {
            try {
                $failureCleanupRecord.boundary='manifest'
                $failureCleanup=New-CleanupManifest -Vm $vm -RunId $runId
                $failureCleanupRecord.boundary='exact-identity'
                $failureVm=Get-AssertedDisposableVm -ExpectedVm $vm
                $durable=$false
                if([string]$failureVm.State -eq 'Off'){$durable=$true}else{
                    $failureCleanupRecord.boundary='interactive-logon'
                    $failureLogon=Clear-DevFleetE2EInteractiveLogonState -VmId ([guid][string]$vm.Id)
                    $durable=([string]$failureLogon.status -eq 'PASS' -and [bool]$failureLogon.registryCleanupPersisted -and [bool]$failureLogon.temporaryDefaultPasswordRemovalPersisted -and -not [bool]$failureLogon.ordinaryDefaultPasswordPresent)
                }
                if(-not $durable){throw 'FullRelease failure cleanup did not establish durable interactive-login cleanup.'}
                $failureCleanupRecord.boundary='stop-exact-vm'
                Stop-ManifestVm -Manifest $failureCleanup
                $failureCleanupRecord.boundary='terminal-evidence'
                Write-TerminalVmEvidence -Vm $vm -RunDir $runDir -L2Name ([string]$config.NestedLinux.Name) | Out-Null
                $failureCleanupRecord.status='COMPLETED'
            } catch {
                $failureCleanupRecord.status='FAIL'
                # Exception messages can contain guest credentials; retain the typed boundary only.
                $failureCleanupRecord.errorType=$_.Exception.GetType().FullName
                Write-Warning "Failure cleanup did not complete at $($failureCleanupRecord.boundary); the primary FullRelease failure is preserved."
            }
        }
        $failureCleanupRecord.completedAt=(Get-Date).ToUniversalTime().ToString('o')
        try { Write-EvidenceJson -Path (Join-Path $runDir 'failure-cleanup.json') -Value $failureCleanupRecord }
        catch { Write-Warning 'Could not persist failure-cleanup evidence; the primary FullRelease failure is preserved.' }
        try { & (Join-Path $WorkspaceRoot 'tools\Update-CurrentReleaseAuthority.ps1') -Workspace $WorkspaceRoot -FullReleaseRunId $runId | Out-Null }
        catch { Write-Warning 'Could not refresh failed FullRelease authority; the primary failure is preserved.' }
        Show-Result 'FullRelease' 'BLOCKED' $primaryFailure.Exception.Message
        throw $primaryFailure
    }
}

if ($Mode -eq 'Closeout') {
    $finalStatePath=Join-Path $WorkspaceRoot 'finalization-state.json'
    $finalState=Read-StrictJson -Path $finalStatePath
    $tailStatus=$null; $guestState=$null; $session=$null
    try {
        $session=Connect-DevFleetGuest -VmId $vm.Id
        $guestState=Get-InteractiveGuestState -Session $session
        $tailStatus=Get-TailscaleGuestStatus -Session $session -ExpectedNodePattern ([string]$config.Tailscale.ExpectedGuestNodePattern)
    } catch { $tailStatus=[pscustomobject]@{status='UNVERIFIED';error=$_.Exception.Message;credentialsStoredInEvidence=$false} }
    finally { if($session){Remove-PSSession $session} }
    $cleanupManifest=New-CleanupManifest -Vm $vm -RunId $runId
    $cleanupPath=Join-Path $runDir 'cleanup-manifest.json'; Write-EvidenceJson -Path $cleanupPath -Value $cleanupManifest
    $tailGate = 'FAIL'
    if($tailStatus -and (Test-TailscaleConnected $tailStatus)) { $tailGate = 'REAL E2E PASS' }
    $cleanupGate = 'FAIL'
    if(Test-CleanupManifest $cleanupManifest) { $cleanupGate = 'UNIT/INTEGRATION TESTED' }
    $gateRecords=@(
        (Gate 'candidate' 'REAL E2E PASS' $fingerprint.candidate.sha256),
        (Gate 'accepted-final-state' 'REAL E2E PASS' ([string]$finalState.status)),
        (Gate 'tailscale-connected-state' $tailGate 'read-only guest status plus bounded WPF state was independently verified'),
        (Gate 'cleanup-manifest' $cleanupGate 'exact disposable VM identity; production deny list; no fuzzy deletion')
    )
    $closeout=[ordered]@{status=if(@($gateRecords|Where-Object status -eq 'FAIL').Count -eq 0){'PASS'}else{'FAIL'};candidate=$fingerprint;acceptedGates=$finalState.gates;guest=$guestState;tailscale=$tailStatus;gates=$gateRecords;cleanupManifest=$cleanupPath;destructiveActionsPerformed=$false}
    Write-EvidenceJson -Path (Join-Path $runDir 'closeout.json') -Value $closeout
    $state.currentPhase='Closeout'; $state.completedPhases=@($state.completedPhases)+@('Closeout'); $state.cleanupManifestPath=$cleanupPath; $state.finalStatus=$closeout.status; Save-State $state $statePath
    Show-Result 'Closeout smoke' $closeout.status 'current candidate, accepted evidence, Tailscale state, and cleanup safety verified'
}
} catch {
    $script:DevFleetFinalConvergencePrimaryBlocker = $_.Exception.Message
    throw
} finally {
    # Every controlled entrypoint outcome, including early HOST-SAFETY and
    # FullRelease failures, goes through the same fail-safe audit finalizer.
    $finalizerFailure=$null
    try {
        $finalizer = Join-Path $WorkspaceRoot 'tools\Invoke-DevFleetFinalConvergence.ps1'
        $finalizerArgs = @('-Workspace',$WorkspaceRoot,'-RunId',$runId,'-RunDirectory',$runDir)
        if ($script:DevFleetFinalConvergencePrimaryBlocker) {
            $finalizerArgs += @('-PrimaryBlocker',$script:DevFleetFinalConvergencePrimaryBlocker,'-PrimaryBlockerClassification','BLOCKED — RELEASE HARNESS / PLATFORM')
        }
        Invoke-RequiredReleaseFinalizer -PowerShellPath (Get-Command pwsh.exe -ErrorAction Stop).Source -FinalizerPath $finalizer -ArgumentList $finalizerArgs | Write-Output
    } catch {
        $finalizerFailure=$_.Exception.Message
    }
    if($finalizerFailure){
        if($script:DevFleetFinalConvergencePrimaryBlocker){Write-Warning "Mandatory finalizer invocation failed after the primary release failure; original blocker remains primary. Finalizer: $finalizerFailure"}
        else{throw "Mandatory finalizer invocation failed: $finalizerFailure"}
    }
}

```


## FILE: automation/release-e2e/Invoke-FocusedMaintenanceSentinels.ps1

SHA256: 3ddd160b47a2c2e25b86f42f6b280fed370ab78261730e113b5194f5bdff2227 | Bytes: 4953 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$Candidate,
    [string]$ConfigPath,
    [string]$RunId,
    [switch]$AllowRamPressure
)
$ErrorActionPreference='Stop'
$scriptRoot=$PSScriptRoot
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $scriptRoot '..\..')).Path}else{$WorkspaceRoot=(Resolve-Path $WorkspaceRoot).Path}
if(-not $ConfigPath){$ConfigPath=Join-Path $scriptRoot 'config\devfleet-e2e.defaults.json'}
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
foreach($m in @('Candidate','HostSafety','ResumeState','Evidence','Cleanup','GuestSession','FullRelease')){Import-Module (Join-Path $scriptRoot "modules\$m.psm1") -Force}
$script:evidenceModulePath=Join-Path $scriptRoot 'modules\Evidence.psm1'
# The product lifecycle imports modules in nested scopes and can unload the
# repository module by name. Rebind it by full path for every wrapper write.
function Write-FocusedMaintenanceEvidence {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Value)
    $module=Import-Module $script:evidenceModulePath -Force -PassThru
    $command=$module.ExportedCommands['Write-EvidenceJson']
    if(-not $command){throw 'Focused maintenance evidence writer export is unavailable.'}
    & $command -Path $Path -Value $Value
}
$fingerprint=Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath $Candidate
$runId=if($RunId){$RunId}else{"focused-maintenance-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))-$([guid]::NewGuid().ToString('N').Substring(0,8))"}
$runDir=New-RunEvidenceDirectory -WorkspaceRoot $WorkspaceRoot -RunId $runId
$vm=$null;$evidence=[ordered]@{status='BLOCKED';runId=$runId;phase='MAINTENANCE-READY/WINDOWS-SENTINELS';candidate=$fingerprint;runDir=$runDir;cleanup=$null}
try{
    $vm=Get-DisposableVm -Pattern ([string]$config.DisposableVmNamePattern);Assert-DisposableOwnership -Vm $vm|Out-Null
    $hostSafety=Apply-RamPressureOverride -Snapshot (Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB ([double]$config.ExpectedVmStartCostGiB)) -AllowRamPressure:$AllowRamPressure
    Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'focused-host-safety.json') -Value $hostSafety
    if(-not[bool]$hostSafety.effectiveE2EStartAuthorized){throw 'USER ACTION REQUIRED — fresh HOST-SAFETY startSafe=false.'}
    $fixture=Ensure-MaintenanceReadyFixture -Vm $vm -Fingerprint $fingerprint -Config $config -WorkspaceRoot $WorkspaceRoot -RunId $runId -RunDir $runDir
    Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'maintenance-ready-provenance-evidence.json') -Value $fixture
    $restored=Restore-MaintenanceReadyCheckpoint -Vm $vm -Fingerprint $fingerprint -WorkspaceRoot $WorkspaceRoot
    $context=[ordered]@{runId=$runId;phaseId='WINDOWS-SENTINELS';label='WINDOWS FOREIGN SENTINELS';checkpoint='DevFleet-E2E-MAINTENANCE-READY';destructive=$true;candidate=$fingerprint;vmName=$vm.Name;vmId=$vm.Id.ToString();runDir=$runDir;config=$config}
    $executor=Get-ExecutorPath -Config $config -PhaseId 'WINDOWS-SENTINELS' -WorkspaceRoot $WorkspaceRoot
    if(-not $executor){throw 'WINDOWS-SENTINELS executor is not configured.'}
    $sentinelEvidence=Invoke-ConfiguredExecutor -Path $executor -Context ([pscustomobject]$context)
    if([string]$sentinelEvidence.status -notin @('PASS','REAL E2E PASS') -or [string]$sentinelEvidence.sentinels.status -ne 'PASS' -or -not[bool]$sentinelEvidence.sentinels.unchanged){throw 'WINDOWS-SENTINELS did not prove foreign resources survived.'}
    Write-FocusedMaintenanceEvidence -Path (Join-Path $runDir 'windows-sentinels-focused-evidence.json') -Value ([ordered]@{status='PASS';runId=$runId;hostSafety=$hostSafety;fixture=$fixture;independentRestore=$restored;windowsSentinels=$sentinelEvidence;foreignResourcesMutated=$false})
    $evidence.status='PASS';$evidence.hostSafety=$hostSafety;$evidence.fixture=$fixture;$evidence.independentRestore=$restored