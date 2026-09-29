# DevFleet source part 020

Full-source UTF-8 byte interval [883500, 930000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 139a7162afe2cafc8b9addf455a667bf074d14c9a2979c04c571283b7f01491c

<!-- BEGIN SOURCE SLICE -->
PASS'){$state.primaryError="M1 $Operation returned $([string]$raw.outcome).";return $null}
        if(-not[bool]$raw.outputComplete){$state.primaryError="M1 $Operation returned incomplete output.";return $null}
        return $raw
    }.GetNewClosure()
    $launchArguments=@('launch',$UbuntuImage,'--name',$InstanceName,'--cpus',[string]$Resources.cpus,'--memory',[string]$Resources.memory,'--disk',[string]$Resources.disk)
    if($CloudInitPath){$launchArguments+=@('--cloud-init',$CloudInitPath)}
    $launch=&$invoke 'launch' $launchArguments 900
    if($launch){$progress.launchAccepted=$true}
    $info=$null
    if($launch){$info=&$invoke 'info-running' @('info',$InstanceName,'--format','json') 60}
    if($info){
        try{$parsed=[string]$info.stdout|ConvertFrom-Json -ErrorAction Stop;$properties=@($parsed.info.PSObject.Properties|Where-Object{[string]$_.Name-ceq$InstanceName});if($properties.Count-ne1){throw 'exact instance key missing'};$row=$properties[0].Value;if([string]$row.state-cne'Running'){throw 'instance not Running'};$addresses=@($row.ipv4|Where-Object{[string]$_-match'^\d{1,3}(?:\.\d{1,3}){3}$'});if($addresses.Count-lt1){throw 'IPv4 absent'};$progress.instanceRunning=$true;$progress.ipObserved=$true}catch{$state.primaryError="M1 info-running response was malformed: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)"}
    }
    $ssh=$null;if($progress.instanceRunning){$ssh=&$invoke 'ssh-ready' @('exec',$InstanceName,'--','true') 120;if($ssh){$progress.sshReady=$true}}
    $cloud=$null;if($progress.sshReady){$cloud=&$invoke 'cloud-init' @('exec',$InstanceName,'--','cloud-init','status','--wait') 300;if($cloud){if([string]$cloud.stdout-notmatch'(?im)^status:\s*done\s*$'){$state.primaryError='M1 cloud-init did not report done.'}else{$progress.cloudInitDone=$true}}}
    $finalInfo=$null;if($progress.cloudInitDone){$finalInfo=&$invoke 'info-final' @('info',$InstanceName,'--format','json') 60;if($finalInfo){try{$parsed=[string]$finalInfo.stdout|ConvertFrom-Json -ErrorAction Stop;$properties=@($parsed.info.PSObject.Properties|Where-Object{[string]$_.Name-ceq$InstanceName});if($properties.Count-ne1-or[string]$properties[0].Value.state-cne'Running'){throw 'final exact Running state missing'}}catch{$state.primaryError="M1 final info response was malformed: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)"}}}
    $finished=&$now
    [pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_M1_SEQUENCE';status=if($progress.launchAccepted-and$progress.instanceRunning-and$progress.ipObserved-and$progress.sshReady-and$progress.cloudInitDone-and$finalInfo-and-not$state.primaryError){'PASS'}else{'BLOCKED'};runId=$RunId;instanceName=$InstanceName;ubuntuImage=$UbuntuImage;resources=[ordered]@{cpus=[int]$Resources.cpus;memory=[string]$Resources.memory;disk=[string]$Resources.disk;diagnosticDeviation=$true};startedAtUtc=$started.ToString('o');producedAtUtc=$finished.ToString('o');ownerDeadlineUtc=$owner.ToString('o');progress=$progress;observations=@($observations);primaryError=[string]$state.primaryError;productLifecycleStarted=$false;productProgressClaimed=$false}
}

function New-DevFleetCampaignEM1CleanupState {
    param([Parameter(Mandatory)][ValidatePattern('^DevFleet-E2E-E-M1-[A-Za-z0-9._-]+$')][string]$InstanceName)
    [ordered]@{status='UNVERIFIED';instanceName=$InstanceName;delete=$null;inventory=$null;finalInventoryCount=-1}
}

function Assert-DevFleetCampaignEM1Result {
    param([Parameter(Mandatory)][psobject]$Result,[Parameter(Mandatory)][string]$ExpectedRunId,[Parameter(Mandatory)][guid]$ExpectedVmId,[Parameter(Mandatory)][string]$ExpectedInstanceName,[Parameter(Mandatory)][string]$ExpectedPayloadSha256,[hashtable]$ExpectedResources=@{cpus=2;memory='2G';disk='10G'})
    if([int]$Result.schemaVersion-ne1-or[string]$Result.kind-cne'DEVFLEET_CAMPAIGN_E_M1_RESULT'-or[string]$Result.status-cnotin@('PASS_DIAGNOSTIC','BLOCKED')){throw 'Campaign E M1 result schema/status is invalid.'}
    if([string]$Result.runId-cne$ExpectedRunId-or[guid][string]$Result.vmId-ne$ExpectedVmId-or[string]$Result.instanceName-cne$ExpectedInstanceName-or[string]$Result.payloadSha256-cne$ExpectedPayloadSha256){throw 'Campaign E M1 result identity mismatch.'}
    $deadline=([datetime]$Result.ownerDeadlineUtc).ToUniversalTime();$produced=([datetime]$Result.producedAtUtc).ToUniversalTime();if($produced-gt$deadline){throw 'Campaign E M1 result was produced after cutoff.'}
    if([string]$Result.multipassSha256-notmatch'^[0-9a-f]{64}$'-or[bool]$Result.productLifecycleStarted-or[bool]$Result.productProgressClaimed-or[bool]$Result.boundaryBefore.activeTransactionPresent-or[int]$Result.boundaryBefore.stageMarkerCount-ne0-or[bool]$Result.boundaryAfter.activeTransactionPresent-or[int]$Result.boundaryAfter.stageMarkerCount-ne0){throw 'Campaign E M1 fabricated or crossed the product boundary.'}
    if([string]$Result.cleanup.status-cne'ABSENT_VERIFIED'-or[string]$Result.cleanup.instanceName-cne$ExpectedInstanceName-or[int]$Result.cleanup.finalInventoryCount-ne0){throw 'Campaign E M1 cleanup did not prove exact empty inventory.'}
    if([string]$Result.status-ceq'PASS_DIAGNOSTIC'){
        $sequence=$Result.sequence;$sequenceDeadline=([datetime]$sequence.ownerDeadlineUtc).ToUniversalTime();$sequenceStarted=([datetime]$sequence.startedAtUtc).ToUniversalTime();$sequenceProduced=([datetime]$sequence.producedAtUtc).ToUniversalTime()
        if([string]$sequence.status-cne'PASS'-or[string]$sequence.runId-cne$ExpectedRunId-or[string]$sequence.instanceName-cne$ExpectedInstanceName-or$sequenceStarted-gt$sequenceDeadline-or$sequenceProduced-lt$sequenceStarted-or$sequenceProduced-gt$sequenceDeadline-or$sequenceDeadline-gt$deadline-or[bool]$sequence.productLifecycleStarted-or[bool]$sequence.productProgressClaimed-or-not[bool]$sequence.resources.diagnosticDeviation-or[int]$sequence.resources.cpus-ne[int]$ExpectedResources.cpus-or[string]$sequence.resources.memory-cne[string]$ExpectedResources.memory-or[string]$sequence.resources.disk-cne[string]$ExpectedResources.disk-or-not[bool]$sequence.progress.launchAccepted-or-not[bool]$sequence.progress.instanceRunning-or-not[bool]$sequence.progress.ipObserved-or-not[bool]$sequence.progress.sshReady-or-not[bool]$sequence.progress.cloudInitDone){throw 'Campaign E M1 PASS lacks required identity/deadline/readiness evidence.'}
        $expected=@('launch','info-running','ssh-ready','cloud-init','info-final');$ops=@($sequence.observations);if($ops.Count-ne$expected.Count){throw 'Campaign E M1 PASS operation count is invalid.'};$previous=$sequenceStarted;for($i=0;$i-lt$expected.Count;$i++){$opStarted=([datetime]$ops[$i].startedAtUtc).ToUniversalTime();$opFinished=([datetime]$ops[$i].finishedAtUtc).ToUniversalTime();$opDeadline=([datetime]$ops[$i].deadlineUtc).ToUniversalTime();if([string]$ops[$i].operation-cne$expected[$i]-or[string]$ops[$i].outcome-cne'PASS'-or-not[bool]$ops[$i].outputComplete-or$opStarted-lt$previous-or$opFinished-lt$opStarted-or$opFinished-gt$sequenceProduced-or$opDeadline-gt$sequenceDeadline){throw 'Campaign E M1 PASS operation evidence is invalid.'};$previous=$opFinished}
    }
    $serialized=$Result|ConvertTo-Json -Depth 24 -Compress;if($serialized-match'(?i)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*(?!<redacted>|\\u003credacted\\u003e)[^,}\"]+'){throw 'Campaign E M1 result contains unredacted secret-shaped evidence.'}
    return $true
}

function Get-DevFleetCampaignEDeadlinePartition {
    param(
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [ValidateRange(60,900)][int]$ReservedTerminalizationSeconds=300,
        [scriptblock]$ClockProvider
    )
    $now=if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}
    $owner=$OwnerDeadlineUtc.ToUniversalTime()
    $child=$owner.AddSeconds(-$ReservedTerminalizationSeconds)
    if($child-le$now){throw 'Campaign E owner deadline cannot provide the required terminalization reserve.'}
    [pscustomobject][ordered]@{observedAtUtc=$now.ToString('o');childDeadlineUtc=$child.ToString('o');ownerDeadlineUtc=$owner.ToString('o');terminalizationDeadlineUtc=$owner.AddSeconds($ReservedTerminalizationSeconds).ToString('o');reservedTerminalizationSeconds=$ReservedTerminalizationSeconds;childRemainingSeconds=[int][math]::Floor(($child-$now).TotalSeconds);ownerRemainingSeconds=[int][math]::Floor(($owner-$now).TotalSeconds)}
}

function Assert-DevFleetCampaignEPrerequisiteResult {
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [Parameter(Mandatory)][string]$ExpectedRunId,
        [Parameter(Mandatory)][guid]$ExpectedVmId,
        [Parameter(Mandatory)][string]$ExpectedPayloadSha256,
        [Parameter(Mandatory)][psobject]$ExpectedPlan
    )
    if([int]$Result.schemaVersion-ne1-or[string]$Result.kind-cne'DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY'){throw 'Prerequisite result schema identity is invalid.'}
    if([string]$Result.runId-cne$ExpectedRunId-or[guid][string]$Result.vmId-ne$ExpectedVmId){throw 'Prerequisite result run/VM identity mismatch.'}
    if([string]$Result.payloadSha256-cne$ExpectedPayloadSha256){throw 'Prerequisite result payload identity mismatch.'}
    if([string]$Result.status-cne'PASS'){throw "Prerequisite result is not PASS: $([string]$Result.status)"}
    $deadline=([datetime]$Result.ownerDeadlineUtc).ToUniversalTime();$started=([datetime]$Result.startedAtUtc).ToUniversalTime();$produced=([datetime]$Result.producedAtUtc).ToUniversalTime()
    if($started-gt$deadline-or$produced-gt$deadline-or$produced-lt$started){throw 'Prerequisite result violates its immutable owner deadline.'}
    if([string]$Result.role-cne[string]$ExpectedPlan.role-or[string]$Result.packageVersion-cne[string]$ExpectedPlan.packageVersion){throw 'Prerequisite result candidate role/version mismatch.'}
    foreach($name in @('version','dependencies','config','bootstrap','install','common')){if([string]$Result.inputHashes.$name-cne[string]$ExpectedPlan.inputHashes.$name){throw "Prerequisite result candidate input hash mismatch: $name"}}
    if([bool]$Result.systemPolicyChanged-or[bool]$Result.productLifecycleStarted-or[bool]$Result.activeTransactionPresent-or[int]$Result.stageMarkerCount-ne0-or[int]$Result.activeInstallProcessCount-ne0){throw 'Prerequisite result crossed a forbidden product/security boundary.'}
    if([bool]$Result.pendingReboot){throw 'Prerequisite state requires a reboot and is not checkpoint-ready.'}
    $powerShellVersion=[Version][string]$Result.powershell.version
    if([string]$Result.powershell.status-cne'Compatible'-or$powerShellVersion-lt[Version][string]$ExpectedPlan.dependencies.powershell7.minimumSupportedVersion-or$powerShellVersion.Major-gt[int]$ExpectedPlan.dependencies.powershell7.maximumMajor-or[string]$Result.powershell.pathSha256-notmatch'^[0-9a-f]{64}$'){throw 'PowerShell did not reach the candidate compatibility policy.'}
    $acquisition=$Result.powershellAcquisition
    if($null-eq$acquisition-or[int]$acquisition.schemaVersion-ne1-or[string]$acquisition.kind-cne'DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION'-or[string]$acquisition.status-cne'PASS'){throw 'PowerShell acquisition evidence is missing or malformed.'}
    if([string]$acquisition.packageId-cne[string]$ExpectedPlan.dependencies.powershell7.wingetPackageId-or[bool]$acquisition.productLifecycleStarted-or[bool]$acquisition.stageMarkerWritten){throw 'PowerShell acquisition evidence violates the candidate/product boundary.'}
    $acquisitionStarted=([datetime]$acquisition.startedAtUtc).ToUniversalTime();$acquisitionFinished=([datetime]$acquisition.finishedAtUtc).ToUniversalTime();$acquisitionDeadline=([datetime]$acquisition.ownerDeadlineUtc).ToUniversalTime()
    if($acquisitionStarted-lt$started-or$acquisitionFinished-lt$acquisitionStarted-or$acquisitionFinished-gt$produced-or$acquisitionDeadline-ne$deadline){throw 'PowerShell acquisition evidence violates the prerequisite owner timeline.'}
    if([string]$acquisition.powershell.status-cne'Compatible'-or[string]$acquisition.powershell.version-cne[string]$Result.powershell.version-or[string]$acquisition.powershell.pathSha256-cne[string]$Result.powershell.pathSha256){throw 'PowerShell acquisition and final candidate compatibility evidence disagree.'}
    $acquisitionOperations=@($acquisition.operations)
    if([string]$acquisition.method-ceq'PRESERVED_CANDIDATE_COMPATIBLE'){
        if($acquisitionOperations.Count-ne0-or-not[string]::IsNullOrEmpty([string]$acquisition.wingetPathSha256)){throw 'Preserved PowerShell acquisition contains unexpected WinGet evidence.'}
    } elseif([string]$acquisition.method-ceq'WINGET_MANIFEST_APPROVED_DIAGNOSTIC'){
        if([string]$acquisition.wingetPathSha256-notmatch'^[0-9a-f]{64}$'-or$acquisitionOperations.Count-ne5){throw 'WinGet PowerShell acquisition identity/operation evidence is incomplete.'}
        $expectedOperations=@('winget-version','winget-source-list','winget-source-update','winget-powershell-search','winget-powershell-install');$previous=$acquisitionStarted
        for($index=0;$index-lt$expectedOperations.Count;$index++){
            $operation=$acquisitionOperations[$index];$operationStarted=([datetime]$operation.startedAtUtc).ToUniversalTime();$operationFinished=([datetime]$operation.finishedAtUtc).ToUniversalTime();$operationDeadline=([datetime]$operation.deadlineUtc).ToUniversalTime()
            if([string]$operation.operation-cne$expectedOperations[$index]-or$operationStarted-lt$previous-or$operationFinished-lt$operationStarted-or$operationFinished-gt$acquisitionFinished-or$operationDeadline-gt$deadline-or-not[bool]$operation.outputComplete){throw 'WinGet PowerShell acquisition operation sequence/deadline evidence is invalid.'}
            $accepted=[string]$operation.outcome-ceq'PASS'
            if($index-eq4-and[string]$operation.outcome-ceq'NONZERO'-and[int]$operation.exitCode-eq-1978335189){$accepted=$true}
            if(-not$accepted){throw 'WinGet PowerShell acquisition operation did not pass.'}
            $previous=$operationFinished
        }
        if(-not[bool]$acquisitionOperations[3].packageIdentityObserved){throw 'WinGet search did not record the exact candidate package identity.'}
    } elseif([string]$acquisition.method-ceq'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'){
        if(-not[string]::IsNullOrEmpty([string]$acquisition.wingetPathSha256)-or$acquisitionOperations.Count-ne1){throw 'Staged official PowerShell acquisition contains invalid operation evidence.'}
        $official=$acquisition.officialPayload
        if($null-eq$official-or[string]$official.releaseTag-notmatch'^v7\.\d+\.\d+$'-or[string]$official.assetName-notmatch'^PowerShell-7\.[0-9.]+-win-x64\.msi$'-or[string]$official.sha256-notmatch'^[0-9a-f]{64}$'-or[int64]$official.bytes-lt1-or-not(Test-DevFleetCampaignEExactSignerSubject -Actual ([string]$official.signerSubject) -Expected @($ExpectedPlan.dependencies.powershell7.allowedSignerSubjectsExact))){throw 'Staged official PowerShell payload evidence is incomplete.'}
        $operation=$acquisitionOperations[0];$operationStarted=([datetime]$operation.startedAtUtc).ToUniversalTime();$operationFinished=([datetime]$operation.finishedAtUtc).ToUniversalTime();$operationDeadline=([datetime]$operation.deadlineUtc).ToUniversalTime()
        $accepted=[string]$operation.outcome-ceq'PASS';if([string]$operation.outcome-ceq'NONZERO'-and[int]$operation.exitCode-eq3010){$accepted=$true}
        if([string]$operation.operation-cne'official-powershell-msi-install'-or-not$accepted-or-not[bool]$operation.outputComplete-or-not[bool]$operation.packageIdentityObserved-or$operationStarted-lt$acquisitionStarted-or$operationFinished-lt$operationStarted-or$operationFinished-gt$acquisitionFinished-or$operationDeadline-gt$deadline){throw 'Staged official PowerShell installation evidence is invalid.'}
    } else {throw 'PowerShell acquisition method is unsupported.'}
    if([string]$Result.multipass.status-cne'Compatible'-or[Version][string]$Result.multipass.version-lt[Version][string]$ExpectedPlan.dependencies.multipass.minimumSupportedVersion){throw 'Multipass did not reach the candidate compatibility policy.'}
    if([string]$Result.backend.driver-cne[string]$ExpectedPlan.expectedBackend-or[bool]$Result.backend.privilegedMounts-or[int]$Result.backend.inventoryCount-ne0){throw 'Prerequisite backend is not the required empty Hyper-V/no-mount baseline.'}
    if([string]$Result.l2Status-cne'ABSENT'){throw 'Prerequisite result does not positively establish L2 absence.'}
    $serialized=$Result|ConvertTo-Json -Depth 20 -Compress
    if($serialized-match'(?i)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*(?!<redacted>|\\u003credacted\\u003e)[^,}\"]+'){throw 'Prerequisite result contains unredacted secret-shaped evidence.'}
    return $true
}

function ConvertTo-DevFleetMultipassProbeObservation {
    param(
        [Parameter(Mandatory)][psobject]$Probe,
        [Parameter(Mandatory)][string]$UbuntuImage,
        [Parameter(Mandatory)][string[]]$CandidateInstanceNames,
        [Parameter(Mandatory)][string]$RunOwnedPrefix
    )
    $allowedOperations=@('version','driver','privileged-mounts','inventory','image')
    $operation=[string]$Probe.operation
    if($operation -notin $allowedOperations){throw "Diagnostic probe operation is not allowlisted: $operation"}
    $outcome=[string]$Probe.outcome
    $observation=[ordered]@{operation=$operation;outcome=$outcome;exitCode=$Probe.exitCode;pid=if($Probe.PSObject.Properties['pid']){$Probe.pid}else{$null};startedAtUtc=[string]$Probe.startedAtUtc;finishedAtUtc=[string]$Probe.finishedAtUtc;deadlineUtc=if($Probe.PSObject.Properties['deadlineUtc']){[string]$Probe.deadlineUtc}else{''};outputComplete=if($Probe.PSObject.Properties['outputComplete']){[bool]$Probe.outputComplete}else{$true};stdoutTruncated=if($Probe.PSObject.Properties['stdoutTruncated']){[bool]$Probe.stdoutTruncated}else{$false};stderrTruncated=if($Probe.PSObject.Properties['stderrTruncated']){[bool]$Probe.stderrTruncated}else{$false};data=$null;error=''}
    if($outcome -ne 'PASS'){$observation.error=ConvertTo-DevFleetDiagnosticSafeText $Probe.stderr;return [pscustomobject]$observation}
    $stdout=[string]$Probe.stdout
    try {
        switch($operation){
            'version' {
                $match=[regex]::Match($stdout,'(?i)\bmultipass\s+(?:version\s+)?v?(\d+\.\d+(?:\.\d+)?)')
                if(-not$match.Success){throw 'Multipass version output was malformed.'}
                $observation.data=[ordered]@{version=$match.Groups[1].Value}
            }
            'driver' {
                $value=$stdout.Trim().ToLowerInvariant()
                if($value -notin @('hyperv','virtualbox')){throw 'Multipass driver output was malformed or unsupported.'}
                $observation.data=[ordered]@{driver=$value}
            }
            'privileged-mounts' {
                $value=$stdout.Trim().ToLowerInvariant()
                if($value -notin @('true','false')){throw 'Multipass privileged-mount output was malformed.'}
                $observation.data=[ordered]@{enabled=($value -eq 'true')}
            }
            'inventory' {
                $parsed=$stdout|ConvertFrom-Json -ErrorAction Stop
                $instances=@(if($parsed.PSObject.Properties.Name -contains 'list'){$parsed.list}elseif($parsed -is [array]){$parsed}else{throw 'Multipass inventory omitted its list.'})
                $owned=@();$candidate=@();$foreign=0
                foreach($row in $instances){
                    $name=[string]$row.name
                    if($name -and $name.StartsWith($RunOwnedPrefix,[StringComparison]::Ordinal)){$owned+=$name}
                    elseif($CandidateInstanceNames -ccontains $name){$candidate+=$name}
                    else{$foreign++}
                }
                $observation.data=[ordered]@{count=$instances.Count;runOwnedNames=@($owned|Sort-Object -Unique);candidateNames=@($candidate|Sort-Object -Unique);foreignCount=$foreign}
            }
            'image' {
                if($stdout -notmatch [regex]::Escape($UbuntuImage)){throw 'Multipass image query did not identify the candidate-bound image.'}
                $observation.data=[ordered]@{image=$UbuntuImage;available=$true}
            }
        }
    } catch {
        $observation.outcome='MALFORMED'
        $observation.error=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message
        $observation.data=$null
    }
    return [pscustomobject]$observation
}

function Get-DevFleetMultipassM0Snapshot {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
        [Parameter(Mandatory)][string]$ExpectedVmName,
        [Parameter(Mandatory)][guid]$ExpectedVmId,
        [Parameter(Mandatory)][ValidatePattern('^[0-9]+\.[0-9]+$')][string]$UbuntuImage,
        [Parameter(Mandatory)][string[]]$CandidateInstanceNames,
        [Parameter(Mandatory)][ValidatePattern('^DevFleet-E2E-E-[A-Za-z0-9._-]+$')][string]$RunOwnedPrefix,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc,
        [scriptblock]$EnvironmentProvider,
        [scriptblock]$NativeProbeProvider,
        [scriptblock]$EventProvider,
        [scriptblock]$ClockProvider,
        [AllowNull()][string]$PrimaryError
    )
    $now={if($ClockProvider){([datetime](& $ClockProvider)).ToUniversalTime()}else{[datetime]::UtcNow}}
    $started=&$now;$ownerDeadline=$OwnerDeadlineUtc.ToUniversalTime()
    if($ownerDeadline -le $started){throw 'Campaign E M0 owner deadline is already expired.'}
    $errors=[Collections.Generic.List[string]]::new()
    $safePrimary=ConvertTo-DevFleetDiagnosticSafeText $PrimaryError
    $environment=$null
    try {
        if($EnvironmentProvider){$environment=&$EnvironmentProvider $ExpectedVmName $ExpectedVmId $CandidateInstanceNames $RunOwnedPrefix}
        else {
            $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=[Security.Principal.WindowsPrincipal]::new($identity)
            $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $systemDrive=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
            $processor=Get-CimInstance Win32_Processor -ErrorAction Stop|Select-Object -First 1
            $feature=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction Stop
            $paths=@(Get-DevFleetExistingFilePathSet -CandidatePaths @((Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Multipass\bin\multipass.exe')))
            if($paths.Count -eq 0){$command=Get-Command multipass.exe -ErrorAction SilentlyContinue;if(-not$command){$command=Get-Command multipass -ErrorAction SilentlyContinue};if($command){$paths=@([string]$command.Source)}}
            $paths=@($paths|Select-Object -Unique)
            $multipass=[ordered]@{executableStatus=if($paths.Count-eq 0){'ABSENT'}elseif($paths.Count-eq 1){'PRESENT'}else{'AMBIGUOUS'};executablePresent=($paths.Count-eq 1);executablePath=if($paths.Count-eq 1){$paths[0]}else{''};sha256=if($paths.Count-eq 1){(Get-FileHash -LiteralPath $paths[0] -Algorithm SHA256).Hash.ToLowerInvariant()}else{''};fileVersion=if($paths.Count-eq 1){[string](Get-Item -LiteralPath $paths[0]).VersionInfo.FileVersion}else{''}}
            $services=@(Get-CimInstance Win32_Service -ErrorAction Stop|Where-Object{[string]$_.Name -match '^(?i:multipass(?:d)?(?:\..*)?)$'}|ForEach-Object{[ordered]@{name=[string]$_.Name;state=[string]$_.State;startMode=[string]$_.StartMode;processId=[int]$_.ProcessId;accountKind=switch -Regex ([string]$_.StartName){'^(?i:LocalSystem|NT AUTHORITY\\SYSTEM)$'{'SYSTEM';break}'^(?i:NT AUTHORITY\\NetworkService)$'{'NETWORK_SERVICE';break}'^(?i:NT AUTHORITY\\LocalService)$'{'LOCAL_SERVICE';break}default{'OTHER'}}}})
            $hyperVNames=@();$hyperVForeign=0
            if([string]$feature.State -eq 'Enabled'){
                foreach($row in @(Get-CimInstance -Namespace 'root\virtualization\v2' -ClassName Msvm_ComputerSystem -ErrorAction Stop|Where-Object{[string]$_.Caption -eq 'Virtual Machine'})){
                    $name=[string]$row.ElementName
                    if($CandidateInstanceNames -ccontains $name -or $name.StartsWith($RunOwnedPrefix,[StringComparison]::Ordinal)){$hyperVNames+=$name}else{$hyperVForeign++}
                }
            }
            $activeTransaction=Test-Path -LiteralPath (Join-Path $env:ProgramData 'DevFleet\active-transaction.json') -PathType Leaf
            $activeInstallProcesses=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{[string]$_.Name -in @('DevFleet.Setup.exe','pwsh.exe','powershell.exe') -and [string]$_.CommandLine -match '(?i)Install-DevFleet|Bootstrap-Install|DevFleet.Setup'}).Count
            $dnsStatus='UNAVAILABLE';$dnsAddressCount=0
            try{$dnsTask=[Net.Dns]::GetHostAddressesAsync('cloud-images.ubuntu.com');if($dnsTask.Wait([TimeSpan]::FromSeconds(10))){$dnsStatus='PASS';$dnsAddressCount=@($dnsTask.GetAwaiter().GetResult()).Count}else{$dnsStatus='TIMEOUT'}}catch{$dnsStatus='ERROR'}
            $vboxExe=@((Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Oracle\VirtualBox\VBoxManage.exe'))|Where-Object{$_-and(Test-Path -LiteralPath $_ -PathType Leaf)}|Select-Object -First 1
            $vboxServices=@(Get-CimInstance Win32_Service -ErrorAction Stop|Where-Object{[string]$_.Name -match '^(?i:VBox)'}).Count
            $environment=[ordered]@{
                computerName=$env:COMPUTERNAME
                principal=[ordered]@{kind=if($identity.IsSystem){'SYSTEM'}elseif($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){'ADMINISTRATOR'}else{'STANDARD_USER'};isAdministrator=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
                capacity=[ordered]@{logicalProcessors=[Environment]::ProcessorCount;totalMemoryBytes=[int64]$os.TotalVisibleMemorySize*1KB;freeMemoryBytes=[int64]$os.FreePhysicalMemory*1KB;systemDriveFreeBytes=[int64]$systemDrive.FreeSpace}
                nestedVirtualization=[ordered]@{hyperVFeatureState=[string]$feature.State;vmMonitorModeExtensions=[bool]$processor.VMMonitorModeExtensions;secondLevelAddressTranslation=[bool]$processor.SecondLevelAddressTranslationExtensions;virtualizationFirmwareEnabled=[bool]$processor.VirtualizationFirmwareEnabled}
                multipass=$multipass
                services=$services
                backendInventory=[ordered]@{hyperV=[ordered]@{status=if([string]$feature.State-eq'Enabled'){'PASS'}else{'UNAVAILABLE'};boundNames=@($hyperVNames|Sort-Object -Unique);foreignCount=$hyperVForeign};virtualBox=[ordered]@{executablePresent=[bool]$vboxExe;serviceCount=[int]$vboxServices;registryPresent=((Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox')-or(Test-Path -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox'))}}
                network=[ordered]@{host='cloud-images.ubuntu.com';status=$dnsStatus;addressCount=[int]$dnsAddressCount}
                activeProduct=[ordered]@{activeTransactionPresent=[bool]$activeTransaction;activeInstallProcessCount=[int]$activeInstallProcesses}
            }
        }
    } catch {[void]$errors.Add("environment: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)")}
    $probes=[Collections.Generic.List[object]]::new()
    $multipassPath=if($environment-and$environment.multipass-and[bool]$environment.multipass.executablePresent){[string]$environment.multipass.executablePath}else{''}
    $definitions=@(
        [ordered]@{operation='version';arguments=@('version');seconds=20},
        [ordered]@{operation='driver';arguments=@('get','local.driver');seconds=20},
        [ordered]@{operation='privileged-mounts';arguments=@('get','local.privileged-mounts');seconds=20},
        [ordered]@{operation='inventory';arguments=@('list','--format','json');seconds=30},
        [ordered]@{operation='image';arguments=@('find',$UbuntuImage);seconds=60}
    )
    foreach($definition in $definitions){
        if(-not$multipassPath){
            [void]$probes.Add([pscustomobject]@{operation=$definition.operation;outcome='SKIPPED_NO_EXECUTABLE';exitCode=$null;pid=$null;startedAtUtc=(&$now).ToString('o');finishedAtUtc=(&$now).ToString('o');deadlineUtc=$ownerDeadline.ToString('o');outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false;data=$null;error=''})
            continue
        }
        $remaining=[int][math]::Floor(($ownerDeadline-(&$now)).TotalSeconds)
        if($remaining -le 0){[void]$probes.Add([pscustomobject]@{operation=$definition.operation;outcome='OWNER_EXPIRED';exitCode=$null;pid=$null;startedAtUtc=(&$now).ToString('o');finishedAtUtc=(&$now).ToString('o');deadlineUtc=$ownerDeadline.ToString('o');outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false;data=$null;error='Owning diagnostic deadline expired.'});continue}
        $raw=if($NativeProbeProvider){&$NativeProbeProvider $definition.operation $multipassPath @($definition.arguments) ([math]::Min([int]$definition.seconds,$remaining)) $ownerDeadline}else{Invoke-DevFleetBoundedNativeProbe -Operation $definition.operation -FilePath $multipassPath -ArgumentList @($definition.arguments) -TimeoutSeconds ([math]::Min([int]$definition.seconds,$remaining)) -OwnerDeadlineUtc $ownerDeadline}
        [void]$probes.Add((ConvertTo-DevFleetMultipassProbeObservation -Probe $raw -UbuntuImage $UbuntuImage -CandidateInstanceNames $CandidateInstanceNames -RunOwnedPrefix $RunOwnedPrefix))
    }
    $events=$null
    try {
        if($EventProvider){$events=&$EventProvider $ownerDeadline}
        else {
            $eventJob=Start-Job -ScriptBlock {
                $start=(Get-Date).AddHours(-4)
                @(Get-WinEvent -FilterHashtable @{LogName=@('System','Application');StartTime=$start} -MaxEvents 400 -ErrorAction SilentlyContinue|Where-Object{[string]$_.ProviderName -match '(?i)Multipass|Hyper-V|vmcompute|Host-Network-Service'}|Select-Object -First 80|ForEach-Object{
                    $message=[string]$_.Message
                    $category=if($message-match'(?i)timeout|timed out'){'TIMEOUT'}elseif($message-match'(?i)permission|denied|unauthor'){'PERMISSION'}elseif($message-match'(?i)memory|disk|space|resource'){'CAPACITY'}elseif($message-match'(?i)network|dns|connect'){'NETWORK'}elseif($message-match'(?i)image|download'){'IMAGE'}elseif($message-match'(?i)daemon|service'){'SERVICE'}else{'OTHER'}
                    [ordered]@{provider=[string]$_.ProviderName;eventId=[int]$_.Id;level=[string]$_.LevelDisplayName;timestampUtc=$_.TimeCreated.ToUniversalTime().ToString('o');category=$category}
                })
            }
            try {
                $remaining=[int][math]::Max(1,[math]::Min(15,[math]::Floor(($ownerDeadline-(&$now)).TotalSeconds)))
                if(-not(Wait-Job -Job $eventJob -Timeout $remaining)){$events=[ordered]@{status='TIMEOUT';records=@()}}
                else{$events=[ordered]@{status='PASS';records=@(Receive-Job -Job $eventJob -ErrorAction SilentlyContinue)}}
            } finally {if($eventJob){Stop-Job -Job $eventJob -ErrorAction SilentlyContinue;Remove-Job -Job $eventJob -Force -ErrorAction SilentlyContinue}}
        }
    } catch {[void]$errors.Add("events: $(ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message)");$events=[ordered]@{status='ERROR';records=@()}}
    $finished=&$now
    $status=if($null-eq$environment){'ERROR'}elseif($errors.Count -gt 0 -or @($probes|Where-Object{$_.outcome -in @('OWNER_EXPIRED','DRAIN_INCOMPLETE','START_FAILED')}).Count -gt 0){'PARTIAL'}else{'COMPLETE'}
    return [pscustomobject][ordered]@{
        schemaVersion=1;collector='DevFleet-Campaign-E-Multipass-M0';status=$status;runId=$RunId;expectedVmName=$ExpectedVmName;expectedVmId=$ExpectedVmId.ToString();runOwnedPrefix=$RunOwnedPrefix;ubuntuImage=$UbuntuImage;candidateInstanceNames=@($CandidateInstanceNames);ownerDeadlineUtc=$ownerDeadline.ToString('o');startedAtUtc=$started.ToString('o');producedAtUtc=$finished.ToString('o');primaryError=$safePrimary;environment=$environment;probes=@($probes);events=$events;errors=@($errors)
    }
}

function Assert-DevFleetMultipassM0Snapshot {
    param(
        [Parameter(Mandatory)][psobject]$Snapshot,
        [Parameter(Mandatory)][string]$ExpectedRunId,
        [Parameter(Mandatory)][string]$ExpectedVmName,
        [Parameter(Mandatory)][guid]$ExpectedVmId
    )
    if([int]$Snapshot.schemaVersion-ne1-or[string]$Snapshot.collector-cne'DevFleet-Campaign-E-Multipass-M0'){throw 'M0 collector schema identity is invalid.'}
    if([string]$Snapshot.runId-cne$ExpectedRunId){throw 'M0 collector run identity mismatch.'}
    if([string]$Snapshot.expectedVmName-cne$ExpectedVmName-or[guid][string]$Snapshot.expectedVmId-ne$ExpectedVmId){throw 'M0 collector VM identity mismatch.'}
    if([string]$Snapshot.status-notin@('COMPLETE','PARTIAL','ERROR')){throw 'M0 collector status is invalid.'}
    $deadline=([datetime]$Snapshot.ownerDeadlineUtc).ToUniversalTime();$started=([datetime]$Snapshot.startedAtUtc).ToUniversalTime();$produced=([datetime]$Snapshot.producedAtUtc).ToUniversalTime()
    if($started-gt$deadline-or$produced-gt$deadline){throw 'M0 collector was first produced after its immutable owner deadline.'}
    $expected=@('version','driver','privileged-mounts','inventory','image')
    foreach($operation in $expected){if(@($Snapshot.probes|Where-Object{[string]$_.operation-ceq$operation}).Count-ne1){throw "M0 collector did not contain exactly one '$operation' probe."}}
    $previousFinish=$null
    foreach($probe in @($Snapshot.probes)){
        if(([datetime]$probe.startedAtUtc).ToUniversalTime()-gt$deadline-or([datetime]$probe.finishedAtUtc).ToUniversalTime()-gt$deadline){throw "M0 '$([string]$probe.operation)' probe exceeded the immutable owner deadline."}
        if([string]::IsNullOrWhiteSpace([string]$probe.deadlineUtc)-or([datetime]$probe.deadlineUtc).ToUniversalTime()-gt$deadline){throw "M0 '$([string]$probe.operation)' probe did not inherit the immutable owner deadline."}
        $probeStart=([datetime]$probe.startedAtUtc).ToUniversalTime();$probeFinish=([datetime]$probe.finishedAtUtc).ToUniversalTime()
        if($probeFinish-lt$probeStart){throw "M0 '$([string]$probe.operation)' probe time ordering is malformed."}
        if($previousFinish-and$probeStart-lt$previousFinish){throw 'M0 Multipass probes overlapped; the required serialized CLI stream was not preserved.'}
        $previousFinish=$probeFinish
    }
    $serialized=$Snapshot|ConvertTo-Json -Depth 24 -Compress
    if($serialized-match'(?i)\b(password|secret|token|authorization|hmac)\b\s*[:=]\s*(?!<redacted>|\\u003credacted\\u003e)[^,}\"]+'){throw 'M0 collector contains unredacted secret-shaped evidence.'}
    return $true
}

function Invoke-DevFleetBoundedGuestCommand {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList=@(),
        [ValidateRange(1,3600)][int]$TimeoutSeconds=300
    )
    $pipeline=[powershell]::Create()
    try {
        $null=$pipeline.AddCommand('Invoke-Command').AddParameter('Session',$Session).AddParameter('ScriptBlock',$ScriptBlock).AddParameter('ArgumentList',@($ArgumentList)).AddParameter('ErrorAction','Stop')
        $async=$pipeline.BeginInvoke()
        if(-not$async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))){
            try{$pipeline.Stop()}catch{}
            throw "Bounded guest diagnostic command exceeded $TimeoutSeconds seconds."
        }
        $output=@($pipeline.EndInvoke($async))
        if($pipeline.HadErrors){throw ((@($pipeline.Streams.Error|ForEach-Object{ConvertTo-DevFleetDiagnosticSafeText $_})-join '; '))}
        return $output
    } finally {$pipeline.Dispose()}
}

function Get-DevFleetBoundedProcessScriptBlock {
    return {
        param([string]$RequestJson)
        $request=$RequestJson|ConvertFrom-Json -ErrorAction Stop
        $FilePath=[string]$request.filePath
        $Arguments=@($request.arguments|ForEach-Object{[string]$_})
        $deadline=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$request.deadlineUnixMilliseconds).UtcDateTime
        $started=[datetime]::UtcNow
        if($deadline-le$started){return [pscustomobject]@{outcome='OWNER_EXPIRED';exitCode=$null;pid=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=$started.ToString('o');stdout='';stderr='Owning deadline expired before worker start.';outputComplete=$true}}
        if(-not(Test-Path -LiteralPath $FilePath -PathType Leaf)){return [pscustomobject]@{outcome='START_FAILED';exitCode=$null;pid=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');stdout='';stderr='Exact worker executable is missing.';outputComplete=$true}}
        if(@($Arguments|Where-Object{[string]$_-match'[\s"]'}).Count){return [pscustomobject]@{outcome='START_FAILED';exitCode=$null;pid=$null;startedAtUtc=$started.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');stdout='';stderr='Worker arguments must use the validated whitespace-free diagnostic envelope.';outputComplete=$true}}
        $process=$null
        # Read incrementally: ReadToEndAsync cannot expose a flushed prefix while
        # a descendant still holds the pipe. Keep each captured stream bounded.
        function Receive-WorkerOutput($Streams) {
            $progress=$false
            foreach($stream in $Streams){
                if($stream.eof -or $stream.error -or -not $stream.task.IsCompleted){continue}
                $progress=$true
                try {
                    $read=$stream.task.GetAwaiter().GetResult()
                    if($read -eq 0){$stream.eof=$true;continue}
                    $take=[math]::Min($read,[math]::Max(0,65536-$stream.text.Length))
                    if($take -gt 0){[void]$stream.text.Append($stream.buffer,0,$take)}
                    if($take -lt $read){$stream.truncated=$true}
                    $stream.task=$stream.reader.ReadAsync($stream.buffer,0,$stream.buffer.Length)
                } catch {$stream.error=$true}
            }
            return $progress
        }
        try {
            $psi=[Diagnostics.ProcessStartInfo]::new()
            $psi.FileName=$FilePath
            $psi.Arguments=(@($Arguments|ForEach-Object{[string]$_})-join' ')
            $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
            $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
            if(-not$process.Start()){throw 'Diagnostic worker process start returned false.'}
            $streams=@(foreach($reader in @($process.StandardOutput,$process.StandardError)){
                [char[]]$buffer=New-Object char[] 4096
                [pscustomobject]@{reader=$reader;buffer=$buffer;task=$reader.ReadAsync($buffer,0,$buffer.Length);text=[Text.StringBuilder]::new();eof=$false;error=$false;truncated=$false}
            })
            while(-not$process.HasExited-and[datetime]::UtcNow-lt$deadline){
                if(-not(Receive-WorkerOutput $streams)){Start-Sleep -Milliseconds 20}
            }
            $timedOut=-not $process.HasExited
            $treeKillExitCode=$null
            if(-not$process.HasExited){
                $killer=$null
                try {
                    $killInfo=[Diagnostics.ProcessStartInfo]::new()
                    $killInfo.FileName=Join-Path $env:SystemRoot 'System32\taskkill.exe'
                    $killInfo.Arguments='/PID '+[string]$process.Id+' /T /F'
                    $killInfo.UseShellExecute=$false;$killInfo.CreateNoWindow=$true
                    $killInfo.RedirectStandardOutput=$true;$killInfo.RedirectStandardError=$true
                    $killer=[Diagnostics.Process]::Start($killInfo)
                    $killer.BeginOutputReadLine();$killer.BeginErrorReadLine()
                    if($killer.WaitForExit(2000)){$treeKillExitCode=$killer.ExitCode}else{$killer.Kill()}
                } catch {} finally {if($killer){$killer.Dispose()}}
                try{if(-not $process.HasExited){$process.Kill()};[void]$process.WaitForExit(1000)}catch{}
            }
            $drainDeadline=[datetime]::UtcNow.AddSeconds(5)
            while([datetime]::UtcNow -lt $drainDeadline){
                $progress=Receive-WorkerOutput $streams
                if(@($streams|Where-Object{-not $_.eof -and -not $_.error}).Count -eq 0){break}
                if(-not $progress){Start-Sleep -Milliseconds 20}
            }
            $drained=@($streams|Where-Object{-not $_.eof -or $_.error}).Count -eq 0
            $truncated=$streams[0].truncated -or $streams[1].truncated
            $terminated=$process.HasExited
            $supervisorError=if($timedOut){'Diagnostic worker exceeded its inherited finite deadline.'}elseif(-not $drained){'Diagnostic worker output did not drain inside the terminal margin.'}elseif($truncated){'Diagnostic worker output exceeded the bounded capture limit.'}else{''}
            return [pscustomobject]@{outcome=if($timedOut){'TIMEOUT'}elseif(-not$drained){'DRAIN_INCOMPLETE'}elseif($truncated){'OUTPUT_TRUNCATED'}elseif($process.ExitCode-eq0){'PASS'}else{'NONZERO'};exitCode=if($timedOut){$null}else{$process.ExitCode};pid=$process.Id;startedAtUtc=$started.ToString('o');deadlineUtc=$deadline.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');stdout=$streams[0].text.ToString();stderr=$streams[1].text.ToString();outputComplete=($drained-and-not$truncated);drainComplete=$drained;stdoutTruncated=$streams[0].truncated;stderrTruncated=$streams[1].truncated;supervisorError=$supervisorError;terminationVerified=$terminated;treeKillExitCode=$treeKillExitCode}
        } catch {
            return [pscustomobject]@{outcome='START_FAILED';exitCode=$null;pid=if($process-and-not$process.HasExited){$process.Id}else{$null};startedAtUtc=$started.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');stdout='';stderr=[string]$_.Exception.Message;outputComplete=$true}
        } finally {if($process){$process.Dispose()}}
    }
}

function Invoke-DevFleetBoundedGuestProcess {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][datetime]$OwnerDeadlineUtc
    )
    $remaining=[int][math]::Floor(($OwnerDeadlineUtc.ToUniversalTime()-[datetime]::UtcNow).TotalSeconds)
    if($remaining-le0){throw 'Guest diagnostic worker owner deadline expired before launch.'}
    $scriptBlock=Get-DevFleetBoundedProcessScriptBlock
    $deadlineUnixMilliseconds=[DateTimeOffset]::new($OwnerDeadlineUtc.ToUniversalTime()).ToUnixTimeMilliseconds()
    $requestJson=[ordered]@{filePath=$FilePath;arguments=@($ArgumentList);deadlineUnixMilliseconds=$deadlineUnixMilliseconds}|ConvertTo-Json -Depth 4 -Compress
    $output=@(Invoke-DevFleetBoundedGuestCommand -Session $Session -ScriptBlock $scriptBlock -ArgumentList @($requestJson) -TimeoutSeconds ([math]::Min(3600,$remaining+10)))
    if($output.Count-eq0){throw 'Guest diagnostic worker returned no process result.'}
    return $output[-1]
}

function Copy-DevFleetBoundedGuestFile {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$RemotePath,
        [ValidateRange(1,300)][int]$TimeoutSeconds=60
    )
    $pipeline=[powershell]::Create()
    try {
        $null=$pipeline.AddCommand('Copy-Item').AddParameter('LiteralPath',$LocalPath).AddParameter('Destination',$RemotePath).AddParameter('ToSession',$Session).AddParameter('Force',$true).AddParameter('ErrorAction','Stop')
        $async=$pipeline.BeginInvoke()
        if(-not$async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))){try{$pipeline.Stop()}catch{};throw "Bounded guest file staging exceeded $TimeoutSeconds seconds."}
        $null=@($pipeline.EndInvoke($async))
        if($pipeline.HadErrors){throw ((@($pipeline.Streams.Error|ForEach-Object{ConvertTo-DevFleetDiagnosticSafeText $_})-join '; '))}
    } finally {$pipeline.Dispose()}
    $localHash=(Get-FileHash -LiteralPath $LocalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $remoteHash=@(Invoke-DevFleetBoundedGuestCommand -Session $Session -TimeoutSeconds $TimeoutSeconds -ScriptBlock {param($Path)if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Staged diagnostic file is missing.'};(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()} -ArgumentList @($RemotePath))|Select-Object -Last 1
    if([string]$remoteHash-cne$localHash){throw 'Staged diagnostic file hash diverged.'}
    return [pscustomobject]@{localPath=$LocalPath;remotePath=$RemotePath;localSha256=$localHash;remoteSha256=[string]$remoteHash;equal=$true}
}

Export-ModuleMember -Function Invoke-DevFleetCampaignECandidateNativeLaunch,Get-DevFleetCampaignEBackendSnapshot,Assert-DevFleetCampaignEProductProfile,ConvertTo-DevFleetDiagnosticSafeText,ConvertTo-DevFleetWindowsProcessArgument,Get-DevFleetExistingFilePathSet,Invoke-DevFleetBoundedNativeProbe,ConvertTo-DevFleetMultipassProbeObservation,Get-DevFleetMultipassM0Snapshot,Assert-DevFleetMultipassM0Snapshot,Invoke-DevFleetBoundedGuestCommand,Get-DevFleetBoundedProcessScriptBlock,Invoke-DevFleetBoundedGuestProcess,Copy-DevFleetBoundedGuestFile,Assert-DevFleetCampaignEArchiveEntries,Get-DevFleetCampaignEPrerequisitePlan,Invoke-DevFleetCampaignEPowerShellAcquisition,Get-DevFleetCampaignEOfficialPowerShellPayload,Invoke-DevFleetCampaignEStagedPowerShellAcquisition,Get-DevFleetCampaignEBootstrapStubContent,Get-DevFleetSystemExecutionPolicyProjection,Assert-DevFleetCampaignEPrerequisiteFailure,Assert-DevFleetCampaignEStagingOwnership,Resolve-DevFleetCampaignEWorkerResult,Invoke-DevFleetCampaignEMultipassM1Sequence,New-DevFleetCampaignEM1CleanupState,Assert-DevFleetCampaignEM1Result,Get-DevFleetCampaignEDeadlinePartition,Assert-DevFleetCampaignEPrerequisiteResult

```


## FILE: automation/release-e2e/modules/RealUseAcceptance.psm1

SHA256: eb55dfbc1bb0e05213361eb8083072e5b8f215905df5ba93562c0ebd0112da53 | Bytes: 142359 | Git mode: 100644

```
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Evidence.psm1')
Im