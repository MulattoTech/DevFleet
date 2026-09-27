# DevFleet source part 009

Full-source UTF-8 byte interval [372000, 418500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: e0f7d6d4ca074918989c540601e5416da623f2d73ea045f0bbf867148f3835d6

<!-- BEGIN SOURCE SLICE -->
@{}
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
            $status=if($version-lt[Version][string]$dependency.minimumSupportedVersion){'Outdated'}elseif($null-ne$dependency.maximumMajor-and$version.Major-gt[int]$dependency.maximumMajor){'Unsupported-Major'}else{'Compatible'}
            $value=[pscustomobject]@{status=$status;version=$version.ToString();pathSha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();detail='Candidate-trusted executable and bounded version probe.'}
            if($status-ceq'Compatible'){$campaignEAcquisitionState.pwshPath=[string]$path;return $value}
            if($null-eq$first){$first=$value}
        }
        if($null-ne$first){return $first}
        return [pscustomobject]@{status='Missing';version='';pathSha256='';detail='No candidate-trusted PowerShell executable was found.'}
    }.GetNewClosure()
    $authenticityProvider={
        param($payloadPath,$policy)
        Test-OfficialSigner -Path $payloadPath -Policy $policy
        $signature=Get-AuthenticodeSignature -LiteralPath $payloadPath
        [pscustomobject]@{status=$signature.Status.ToString();signerSubject=if($signature.SignerCertificate){[string]$signature.SignerCertificate.Subject}else{''}}
    }.GetNewClosure()
    $installerProvider={
        param($payloadPath,$arguments,$timeoutSeconds,$deadline)
        $msiexec=Join-Path $env:SystemRoot 'System32\msiexec.exe'
        if(-not(Test-TrustedExecutableCandidate -Path $msiexec)){throw 'Candidate-trusted system msiexec.exe is unavailable.'}
        if($null-eq$campaignEAcquisitionState.identity){$campaignEAcquisitionState.identity=[pscustomobject]@{method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId=[string]$powerShellDependency.wingetPackageId;payloadSha256=[string]$powerShellPayload.sha256;assetName=[string]$powerShellPayload.assetName;ownerDeadlineUtc=([datetime]$deadline).ToUniversalTime().ToString('o')}}
        $observation=Invoke-DevFleetBoundedNativeProbe -Operation 'official-powershell-msi-install' -FilePath $msiexec -ArgumentList @($arguments) -TimeoutSeconds $timeoutSeconds -OwnerDeadlineUtc $deadline -ForceLegacyArgumentString -MaxStdoutCharacters 32768 -MaxStderrCharacters 8192
        [void]$campaignEAcquisitionState.nativeTrace.Add([pscustomobject][ordered]@{operation=[string]$observation.operation;outcome=[string]$observation.outcome;exitCode=$observation.exitCode;pid=$observation.pid;startedAtUtc=[string]$observation.startedAtUtc;finishedAtUtc=[string]$observation.finishedAtUtc;deadlineUtc=[string]$observation.deadlineUtc;outputComplete=[bool]$observation.outputComplete})
        return $observation
    }.GetNewClosure()
    $campaignEAcquisitionState.identity=[pscustomobject]@{method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId=[string]$powerShellDependency.wingetPackageId;payloadSha256=[string]$powerShellPayload.sha256;assetName=[string]$powerShellPayload.assetName;ownerDeadlineUtc=$ownerDeadline.ToString('o')}
    $acquisition=Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powerShellDependency -PayloadEvidence $powerShellPayload -PayloadPath $powerShellPayloadPath -OwnerDeadlineUtc $ownerDeadline -AuthenticityProvider $authenticityProvider -InstallerProvider $installerProvider -PowerShellCompatibilityProvider $compatibilityProvider
    if([string]$acquisition.status-cne'PASS'-or[bool]$acquisition.productLifecycleStarted-or[bool]$acquisition.stageMarkerWritten){throw 'Campaign E PowerShell acquisition failed or crossed the product boundary.'}
    if([string]::IsNullOrWhiteSpace([string]$campaignEAcquisitionState.pwshPath)-or-not(Test-Path -LiteralPath ([string]$campaignEAcquisitionState.pwshPath) -PathType Leaf)){throw 'Campaign E PowerShell acquisition did not leave one candidate-compatible trusted pwsh.exe path.'}
    $innerResultPath=Join-Path $remoteRoot 'prerequisite-result.json'
    $innerRequest=[ordered]@{runId=[string]$request.runId;vmId=[string]$request.vmId;remoteRoot=$remoteRoot;packageRoot=$packageRoot;diagnosticModulePath=[string]$request.diagnosticModulePath;resultPath=$innerResultPath;role=[string]$request.role;payloadSha256=[string]$request.payloadSha256;inputHashes=$plan.inputHashes;ownerDeadlineUnixMilliseconds=[DateTimeOffset]::new($ownerDeadline).ToUnixTimeMilliseconds();pendingRebootBaseline=$pendingBaseline}|ConvertTo-Json -Depth 8 -Compress
    $innerBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($innerRequest))
    $innerArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',[string]$request.innerWorkerPath,'-RequestBase64',$innerBase64)
    $innerSeconds=[int][math]::Min(1200,[math]::Max(1,[math]::Floor(($ownerDeadline-[datetime]::UtcNow).TotalSeconds)))
    $innerProbe=Invoke-DevFleetBoundedNativeProbe -Operation 'candidate-multipass-prerequisite' -FilePath ([string]$campaignEAcquisitionState.pwshPath) -ArgumentList $innerArgs -TimeoutSeconds $innerSeconds -OwnerDeadlineUtc $ownerDeadline -ForceLegacyArgumentString -MaxStdoutCharacters 32768 -MaxStderrCharacters 8192
    if(-not(Test-Path -LiteralPath $innerResultPath -PathType Leaf)){throw "Candidate Multipass prerequisite worker did not publish a result: $(ConvertTo-DevFleetDiagnosticSafeText $innerProbe.stderr 1024)"}
    $result=Get-Content -LiteralPath $innerResultPath -Raw|ConvertFrom-Json -ErrorAction Stop
    $policyAfter=Get-DevFleetSystemExecutionPolicyProjection
    $systemChanged=($policyBefore|ConvertTo-Json -Compress)-cne($policyAfter|ConvertTo-Json -Compress)
    $result.systemPolicyChanged=[bool]$systemChanged
    $result|Add-Member -NotePropertyName powershellAcquisition -NotePropertyValue $acquisition -Force
    $result|Add-Member -NotePropertyName worker -NotePropertyValue ([pscustomobject][ordered]@{outcome=[string]$innerProbe.outcome;pid=$innerProbe.pid;startedAtUtc=[string]$innerProbe.startedAtUtc;finishedAtUtc=[string]$innerProbe.finishedAtUtc;outputComplete=[bool]$innerProbe.outputComplete}) -Force
    $result.startedAtUtc=$started.ToString('o')
    $result.producedAtUtc=[datetime]::UtcNow.ToString('o')
    if(([datetime]$result.producedAtUtc).ToUniversalTime()-gt$ownerDeadline){throw 'Campaign E prerequisite result publication crossed the immutable owner deadline.'}
    Write-FreshAtomicJson -Path (Join-Path $remoteRoot 'prerequisite-worker-result.json') -Value $result
    if([datetime]::UtcNow-gt$ownerDeadline){throw 'Campaign E durable prerequisite result completed after the immutable owner deadline.'}
    [Console]::Out.Write(($result|ConvertTo-Json -Depth 20 -Compress))
    if([string]$innerProbe.outcome-cne'PASS'-or$systemChanged){exit 1}
} catch {
    $message=[regex]::Replace([string]$_.Exception.Message,'(?im)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*\S+','$1=<redacted>')
    if($null-ne$request-and$validatedRemoteRoot-and(Test-Path -LiteralPath $validatedRemoteRoot -PathType Container)){
        $primaryError=if($message.Length-gt1024){$message.Substring($message.Length-1024)}else{$message}
        $failure=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_FAILURE';status='BLOCKED';runId=[string]$request.runId;vmId=[string]$request.vmId;payloadSha256=[string]$request.payloadSha256;producedAtUtc=[datetime]::UtcNow.ToString('o');ownerDeadlineUtc=if($ownerDeadline-gt[datetime]::MinValue){$ownerDeadline.ToUniversalTime().ToString('o')}else{''};primaryError=$primaryError;powershellAcquisition=[ordered]@{status='BLOCKED';identity=$campaignEAcquisitionState.identity;operations=@($campaignEAcquisitionState.nativeTrace);productLifecycleStarted=$false;stageMarkerWritten=$false}}
        $failurePath=Join-Path $validatedRemoteRoot 'prerequisite-failure.json';$failureTmp="$failurePath.$([guid]::NewGuid().ToString('N')).tmp"
        try{$failure|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $failureTmp -Encoding UTF8;[IO.File]::Move($failureTmp,$failurePath)}catch{Remove-Item -LiteralPath $failureTmp -Force -ErrorAction SilentlyContinue}
        [Console]::Out.Write(($failure|ConvertTo-Json -Depth 12 -Compress))
    }
    [Console]::Error.Write($message)
    exit 1
}

```


## FILE: automation/release-e2e/Invoke-CampaignEProductM4.ps1

SHA256: ebbb7e1ba24c19b6c61e07433f744ba6381c01b6193c6e451a9f8ef058929d30 | Bytes: 16973 | Git mode: 100644

```
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
            $o=Get-Content (Join-Path $Path '.owner.json') -Raw|