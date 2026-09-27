[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
    [Parameter(Mandatory)][string]$CheckpointEvidencePath
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$checkpointPath=(Resolve-Path -LiteralPath $CheckpointEvidencePath).Path
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';$vmName='DevFleet-E2E-Win11-01';$cleanId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'
$runDir=Join-Path $root "audit/automation-harness/runs/$RunId";$remoteRoot="C:\Users\Public\DevFleet-E2E\$RunId\M4";$nonce=[guid]::NewGuid().ToString()
foreach($module in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic','HarnessBudget')){Import-Module (Join-Path $root "automation/release-e2e/modules/$module.psm1") -Force -DisableNameChecking}
$config=Get-Content (Join-Path $root 'automation/release-e2e/config/devfleet-e2e.defaults.json') -Raw|ConvertFrom-Json
$policy=Get-HarnessBudgetPolicy -Config $config;Assert-HarnessBudgetPolicy $policy|Out-Null
$owner=[datetime]::UtcNow.AddSeconds([int]$policy.exactProofOuterWatchdogSeconds)
$result=[ordered]@{schemaVersion=1;campaign='DF-STABLE-20260906-E';experiment='M4';runId=$RunId;status='RESERVED';proofCredit=$false;certificationEligible=$false;startedAtUtc=[datetime]::UtcNow.ToString('o');ownerDeadlineUtc=$owner.ToString('o');baseline='EXACT_DIAGNOSTIC_PREREQUISITE';productRole='Primary / Desktop';productionObserverEnabled=$true;syntheticReboot=$false;providerSeamsUsed=$false;cleanupOwner='Invoke-CampaignEProductM4.ps1';observations=@()}
$session=$null;$job=$null;$acquired=$false;$stagingOwned=$false;$lifecycleForcedStop=$false;$moduleHash='';$payload='';$snapshotIndex=0;$since=[datetime]::UtcNow;$terminalSnapshot=$null;$checkpoint=$null
if(Test-Path -LiteralPath $runDir){throw 'M4 refuses to reuse an existing run directory.'}
function Save-M4Snapshot([string]$Edge){
    $observation=$null;$captureSession=$null;$observedStart=[datetime]::UtcNow
    try{
        $captureSession=Connect-DevFleetGuest -VmId $vmId
        $cutoff=[datetime]::UtcNow.AddSeconds(40);if($cutoff-gt$owner){$cutoff=$owner}
        $collector = {
            param($RequestBase64)
            $ErrorActionPreference='Stop';$request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64))|ConvertFrom-Json
            $Path=[string]$request.path;$Run=[string]$request.run;$Nonce=[string]$request.nonce;$Hash=[string]$request.hash
            if($Run-notmatch'^[A-Za-z0-9._-]+$'-or$Path-cne("C:\Users\Public\DevFleet-E2E\"+$Run+'\M4')){throw 'M4 collector path escaped exact run ownership.'}
            $o=Get-Content (Join-Path $Path '.owner.json') -Raw|ConvertFrom-Json
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
