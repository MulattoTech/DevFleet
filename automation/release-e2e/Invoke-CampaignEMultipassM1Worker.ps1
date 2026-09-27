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
