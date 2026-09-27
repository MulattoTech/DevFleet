[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
    [ValidateRange(300,900)][int]$OwnerSeconds=600
)

$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$vmName='DevFleet-E2E-Win11-01'
$cleanId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'
$cleanName='DevFleet-E2E-CLEAN'
$l2Name='DevFleet-E2E-Linux-01'
$runOwnedPrefix="DevFleet-E2E-E-$RunId"
$runDir=Join-Path $root "audit\automation-harness\runs\$RunId"
$ownerDeadline=[datetime]::UtcNow.AddSeconds($OwnerSeconds)

foreach($module in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic')){Import-Module (Join-Path $root "automation\release-e2e\modules\$module.psm1") -Force}

$result=[ordered]@{
    schemaVersion=1
    campaign='DF-STABLE-20260906-E'
    experiment='M0'
    status='INCOMPLETE'
    certificationEligible=$false
    proofCredit=$false
    runId=$RunId
    startedAtUtc=[datetime]::UtcNow.ToString('o')
    ownerDeadlineUtc=$ownerDeadline.ToString('o')
    exactL1=[ordered]@{name=$vmName;id=$vmId.ToString()}
    sourceCheckpoint=[ordered]@{name=$cleanName;id=$cleanId.ToString()}
    runOwnedPrefix=$runOwnedPrefix
    cleanupOwner='Invoke-CampaignEMultipassM0.ps1'
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    moduleSha256=(Get-FileHash -LiteralPath (Join-Path $root 'automation\release-e2e\modules\MultipassDiagnostic.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
    workerSha256=(Get-FileHash -LiteralPath (Join-Path $root 'automation\release-e2e\Invoke-CampaignEMultipassM0Worker.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
}
$session=$null
$restored=$false
try {
    New-Item -ItemType Directory -Path $runDir -Force|Out-Null
    $vm=Get-VM -Id $vmId -ErrorAction Stop
    if([string]$vm.Name-cne$vmName-or$vm.Id-ne$vmId){throw 'Campaign E M0 exact L1 identity mismatch.'}
    Assert-DisposableOwnership -Vm $vm -ExpectedId $vmId.ToString()|Out-Null
    $clean=@(Get-VMSnapshot -VM $vm -ErrorAction Stop|Where-Object{$_.Name-ceq$cleanName-and$_.Id-eq$cleanId})
    if($clean.Count-ne1){throw 'Campaign E M0 canonical CLEAN name/GUID binding failed.'}
    $safety=Get-HostSafetySnapshot -Vm $vm -ExpectedVmStartCostGiB 14.38
    $result.hostSafety=[ordered]@{status=if([bool]$safety.startSafe){'PASS'}else{'BLOCKED'};startSafe=[bool]$safety.startSafe;resourceExhaustion=[bool]$safety.resourceExhaustion;availableMemoryGiB=[double]$safety.availableMemoryGiB;projectedPostStartAvailableMemoryGiB=[double]$safety.projectedPostStartAvailableMemoryGiB;observedAtUtc=[datetime]::UtcNow.ToString('o')}
    if(-not[bool]$safety.startSafe){throw 'BLOCKED - HOST-SAFETY startSafe=false.'}
    $fingerprint=Get-CandidateFingerprint -WorkspaceRoot $root
    $result.tuple=[ordered]@{repositoryHead=(&git -C $root rev-parse HEAD).Trim();candidateCommit=[string]$fingerprint.gitCommit;shippingInputIdentity=[string]$fingerprint.shippingInputIdentity;releaseFingerprintId=[string]$fingerprint.releaseFingerprintId;toolingFingerprintId=[string]$fingerprint.toolingFingerprintId;candidateSha256=[string]$fingerprint.candidate.sha256;payloadSha256=[string]$fingerprint.tar.sha256}
    $result.restore=Restore-ExactCheckpoint -Vm $vm -Name $cleanName -StartAfterRestore
    $restored=$true
    $session=Connect-DevFleetGuest -VmId $vmId
    $initialL2=Get-DevFleetNestedL2State -Session $session -ExpectedName $l2Name
    $result.initialL2=$initialL2
    if([string]$initialL2.status-cne'ABSENT'){throw "Campaign E M0 requires exact initial L2 absence; observed $([string]$initialL2.status)."}
    $remoteRoot="C:\Users\Public\DevFleet-E2E\$RunId\M0"
    $null=Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 30 -ScriptBlock {param($Path)if($Path-notlike'C:\Users\Public\DevFleet-E2E\*\M0'){throw 'Remote M0 staging path is outside the run-owned boundary.'};New-Item -ItemType Directory -Path $Path -Force|Out-Null} -ArgumentList @($remoteRoot)
    $localModule=Join-Path $root 'automation\release-e2e\modules\MultipassDiagnostic.psm1'
    $remoteModule=Join-Path $remoteRoot 'MultipassDiagnostic.psm1'
    $localWorker=Join-Path $root 'automation\release-e2e\Invoke-CampaignEMultipassM0Worker.ps1'
    $remoteWorker=Join-Path $remoteRoot 'Invoke-CampaignEMultipassM0Worker.ps1'
    $result.stage=[ordered]@{
        module=Copy-DevFleetBoundedGuestFile -LocalPath $localModule -Session $session -RemotePath $remoteModule -TimeoutSeconds 60
        worker=Copy-DevFleetBoundedGuestFile -LocalPath $localWorker -Session $session -RemotePath $remoteWorker -TimeoutSeconds 60
    }
    $candidateConfig=Get-Content -LiteralPath (Join-Path $root 'source\config\devfleet.config.json') -Raw|ConvertFrom-Json -ErrorAction Stop
    $candidateNames=@([string]$candidateConfig.Primary.InstanceName,[string]$candidateConfig.Failover.InstanceName,[string]$candidateConfig.Vault.InstanceName)
    if($candidateNames.Count-ne3-or@($candidateNames|Where-Object{$_-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'}).Count){throw 'Candidate-bound product instance names are invalid.'}
    $ubuntuImage=[string]$candidateConfig.Primary.UbuntuImage
    $collectorRequest=[ordered]@{
        modulePath=$remoteModule
        runId=$RunId
        vmName=$vmName
        vmId=$vmId.ToString()
        ubuntuImage=$ubuntuImage
        candidateNames=$candidateNames
        runPrefix=$runOwnedPrefix
        ownerDeadlineUnixMilliseconds=[DateTimeOffset]::new($ownerDeadline.ToUniversalTime()).ToUnixTimeMilliseconds()
    }|ConvertTo-Json -Depth 4 -Compress
    $requestBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($collectorRequest))
    $remotePowerShell=@(Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 20 -ScriptBlock {$path=Join-Path $PSHOME 'powershell.exe';if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Windows PowerShell runtime is missing.'};$path})|Select-Object -Last 1
    if(-not$remotePowerShell-or[IO.Path]::GetFileName([string]$remotePowerShell)-ine'powershell.exe'){throw 'Exact in-L1 Windows PowerShell worker runtime is unavailable.'}
    $workerResult=Invoke-DevFleetBoundedGuestProcess -Session $session -FilePath ([string]$remotePowerShell) -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$remoteWorker,'-RequestBase64',$requestBase64) -OwnerDeadlineUtc $ownerDeadline
    $result.worker=[ordered]@{outcome=[string]$workerResult.outcome;exitCode=$workerResult.exitCode;pid=$workerResult.pid;runtime='WindowsPowerShell';startedAtUtc=[string]$workerResult.startedAtUtc;finishedAtUtc=[string]$workerResult.finishedAtUtc;outputComplete=[bool]$workerResult.outputComplete;executionPolicyScope='PROCESS_ONLY';systemPolicyChanged=$false}
    if([string]$workerResult.outcome-cne'PASS'){throw "Campaign E M0 worker failed: $(ConvertTo-DevFleetDiagnosticSafeText $workerResult.stderr 1024)"}
    try{$snapshot=[string]$workerResult.stdout|ConvertFrom-Json -ErrorAction Stop}catch{throw "Campaign E M0 worker returned malformed JSON: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)"}
    Assert-DevFleetMultipassM0Snapshot -Snapshot $snapshot -ExpectedRunId $RunId -ExpectedVmName $vmName -ExpectedVmId $vmId|Out-Null
    $result.collector=$snapshot
    $result.status=if([string]$snapshot.status-ceq'COMPLETE'){'PASS_DIAGNOSTIC'}else{'INCONCLUSIVE'}
} catch {
    $result.status='BLOCKED'
    $result.primaryError=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 1024
} finally {
    if($session){
        try{$result.finalL2=Get-DevFleetNestedL2State -Session $session -ExpectedName $l2Name}catch{$result.finalL2=[ordered]@{status='UNVERIFIED';expectedName=$l2Name;verification=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)}}
        try{$null=Invoke-DevFleetBoundedGuestCommand -Session $session -TimeoutSeconds 30 -ScriptBlock {param($Path)if($Path-notlike'C:\Users\Public\DevFleet-E2E\*\M0'){throw 'Remote M0 cleanup path is outside the run-owned boundary.'};if(Test-Path -LiteralPath $Path){Remove-Item -LiteralPath $Path -Recurse -Force}} -ArgumentList @("C:\Users\Public\DevFleet-E2E\$RunId\M0");$result.stagingCleanup='PASS'}catch{$result.stagingCleanup='UNVERIFIED'}
        Remove-PSSession $session -ErrorAction SilentlyContinue;$session=$null
    } elseif($restored) {$result.finalL2=[ordered]@{status='UNVERIFIED';expectedName=$l2Name;verification='No bounded in-L1 inventory was available before final stop.'}}
    try {
        $finalVm=Get-VM -Id $vmId -ErrorAction Stop
        if([string]$finalVm.Name-cne$vmName-or$finalVm.Id-ne$vmId){throw 'Campaign E M0 final L1 identity mismatch.'}
        if($finalVm.State-ne'Off'){Stop-VM -VM $finalVm -Force -Confirm:$false -ErrorAction Stop}
        $stopDeadline=[datetime]::UtcNow.AddMinutes(2)
        do{$finalVm=Get-VM -Id $vmId -ErrorAction Stop;if($finalVm.State-eq'Off'){break};Start-Sleep -Seconds 2}while([datetime]::UtcNow-lt$stopDeadline)
        $result.finalL1=[ordered]@{status=if($finalVm.State-eq'Off'){'OFF'}else{'UNVERIFIED'};name=$finalVm.Name;id=$finalVm.Id.ToString();observedAtUtc=[datetime]::UtcNow.ToString('o')}
    } catch {$result.finalL1=[ordered]@{status='UNVERIFIED';error=(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message);observedAtUtc=[datetime]::UtcNow.ToString('o')}}
    if($restored-and([string]$result.finalL1.status-cne'OFF'-or[string]$result.finalL2.status-cne'ABSENT')){$result.status='BLOCKED'}
    $result.completedAtUtc=[datetime]::UtcNow.ToString('o')
    Write-EvidenceJson -Path (Join-Path $runDir 'campaign-e-m0.json') -Value $result
}

[pscustomobject]$result
if([string]$result.status-cne'PASS_DIAGNOSTIC'){exit 1}
