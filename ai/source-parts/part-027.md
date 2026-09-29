# DevFleet source part 027

Full-source UTF-8 byte interval [1209000, 1255500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 7555e8e9c33fe761164c5fbbe2b57a69ee32cb0e8ce18c2bab796bb52fc65555

<!-- BEGIN SOURCE SLICE -->
sion.Major-lt7){throw 'Unsupported health client runtime.'}
            $root=Join-Path $env:ProgramData 'DevFleetHostAgent'
            $protocol=Join-Path $root 'DevFleet-HostAgentProtocol.psm1';$tokenPath=Join-Path $root 'token.txt'
            foreach($path in @($env:ProgramData,$root,$protocol,$tokenPath)){
                if((Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Health client input is a reparse point.'}
            }
            $result.protocolSha256=(Get-FileHash -LiteralPath $protocol -Algorithm SHA256).Hash.ToLowerInvariant()
            if($result.protocolSha256-cne$ProtocolSha256){throw 'Installed health client protocol differs from the exact shipping input.'}
            Import-Module $protocol -Force
            $key=(Get-Content -LiteralPath $tokenPath -Raw).Trim()
            if(-not$key){throw 'Health client token is empty.'}
            $result.requestAttempted=$true
            $health=Invoke-HostAgentAuthenticatedJson -Uri 'http://127.0.0.1:8790/healthz' -Method GET -Key $key -ExpectedHost $env:COMPUTERNAME
            $result.responseAuthenticated=$true
            if($health.ok -isnot [bool] -or -not $health.ok){throw 'Authenticated health response is not healthy.'}
            $result.ok=$true;$result.reasonCode='AUTHENTICATED_HEALTH_OK'
        } catch {
            # Return only error identifiers, never key material, headers or bodies.
            $result.reasonCode='AUTHENTICATED_HEALTH_UNAVAILABLE'
            $result.failureType=$_.Exception.GetType().FullName
            $result.failureId=([string]$_.FullyQualifiedErrorId -replace '[^A-Za-z0-9_. ,:-]','').Substring(0,[math]::Min(160,([string]$_.FullyQualifiedErrorId -replace '[^A-Za-z0-9_. ,:-]','').Length))
        } finally {$key=$null}
        $result|ConvertTo-Json -Compress
    }
}

function Invoke-ProductAuthenticatedHealthProbe {
    param([object]$Session,[string]$ProtocolSha256,[datetime]$OwnerDeadlineUtc,[scriptblock]$ProcessProvider)
    $result=[ordered]@{ok=$false;reasonCode='AUTHENTICATED_HEALTH_UNAVAILABLE';runtimeVersion='';protocolSha256=$ProtocolSha256;requestAttempted=$false;responseAuthenticated=$false}
    try {
        if($ProtocolSha256-notmatch'^[0-9a-f]{64}$'){throw 'Health protocol identity is invalid.'}
        if($OwnerDeadlineUtc-le[datetime]::UtcNow){throw 'Health observation deadline is already exhausted.'}
        $body=(Get-ProductAuthenticatedHealthScript).ToString()
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(('& {'+$body+"} '"+$ProtocolSha256+"'")))
        $request=[pscustomobject]@{filePath='C:\Program Files\PowerShell\7\pwsh.exe';arguments=@('-NoProfile','-NonInteractive','-EncodedCommand',$encoded);ownerDeadlineUtc=$OwnerDeadlineUtc}
        $process=if($ProcessProvider){&$ProcessProvider $request}else{Invoke-DevFleetBoundedGuestProcess -Session $Session -FilePath $request.filePath -ArgumentList $request.arguments -OwnerDeadlineUtc $OwnerDeadlineUtc}
        if([datetime]::UtcNow-gt$OwnerDeadlineUtc){throw 'Health result arrived after its owner deadline.'}
        if([string]$process.outcome-cne'PASS'-or$process.outputComplete -isnot [bool]-or-not$process.outputComplete){throw 'Bounded health client did not produce a complete successful result.'}
        $value=[string]$process.stdout|ConvertFrom-Json -ErrorAction Stop
        foreach($field in @('ok','requestAttempted','responseAuthenticated')){if($value.$field -isnot [bool]){throw 'Health result contains a malformed boolean.'}}
        # A pre-request filesystem failure has no measured protocol identity.
        # Preserve only its bounded error identifiers, never health credit or
        # an unverified child hash. Success still requires all checks below.
        if(-not$value.ok-and-not$value.requestAttempted-and-not$value.responseAuthenticated-and[string]$value.reasonCode-ceq'AUTHENTICATED_HEALTH_UNAVAILABLE'){
            foreach($field in @('failureType','failureId')){
                if($value.PSObject.Properties[$field]){
                    $safe=([string]$value.$field-replace'[^A-Za-z0-9_. ,:-]','')
                    $result[$field]=$safe.Substring(0,[math]::Min(160,$safe.Length))
                }
            }
            if($result.Contains('failureId')-and$result.failureId){return [pscustomobject]$result}
        }
        if($value.protocolSha256-cne$ProtocolSha256){throw 'Health result protocol identity mismatch.'}
        $version=$null
        if(-not[version]::TryParse([string]$value.runtimeVersion,[ref]$version)-or$version.Major-lt7){throw 'Health result lacks the supported runtime identity.'}
        if([bool]$value.ok-and(-not[bool]$value.requestAttempted-or-not[bool]$value.responseAuthenticated-or[string]$value.reasonCode-cne'AUTHENTICATED_HEALTH_OK')){throw 'Health success lacks authenticated request/response evidence.'}
        foreach($field in @('ok','reasonCode','runtimeVersion','protocolSha256','requestAttempted','responseAuthenticated')){$result[$field]=$value.$field}
        foreach($field in @('failureType','failureId')){if($value.PSObject.Properties[$field]){$result[$field]=[string]$value.$field}}
        return [pscustomobject]$result
    } catch {$result.failureType=$_.Exception.GetType().FullName;$result.failureId=([string]$_.FullyQualifiedErrorId -replace '[^A-Za-z0-9_. ,:-]','').Substring(0,[math]::Min(160,([string]$_.FullyQualifiedErrorId -replace '[^A-Za-z0-9_. ,:-]','').Length))}
    return [pscustomobject]$result
}


function Add-ProductAuthenticatedHealthObservation {
    param([object]$Observation,[object]$Session,[int]$RemainingSeconds)
    $get={param($name)$found=$false;Get-LifecycleProperty $Observation $name ([ref]$found)}
    $set={param($value,$name,$data)if($value-is[System.Collections.IDictionary]){$value[$name]=$data}else{$value|Add-Member -NotePropertyName $name -NotePropertyValue $data -Force}}
    # Ledger/receipt/role evidence must be current before this private client
    # reads the installed key. The health response never substitutes for it.
    if(-not $Observation -or [bool](&$get 'terminalFailure') -or [bool](&$get 'checkpointPresent')){return $Observation}
    foreach($field in @('installStateValid','canonicalOwnershipValid','matchingConsumedReceipt','productRoleIdentityValid')){
        $value=&$get $field
        if($value -isnot [bool] -or -not $value){return $Observation}
    }
    $health=[pscustomobject]@{ok=$false;reasonCode='AUTHENTICATED_HEALTH_DEADLINE_UNAVAILABLE';runtimeVersion='';protocolSha256='';requestAttempted=$false;responseAuthenticated=$false}
    # The existing bounded guest adapter owns process termination and stream
    # drain. Reserve its ten-second remoting/drain margin inside this sample.
    $clientSeconds=[math]::Min(8,$RemainingSeconds-10)
    if($clientSeconds-gt0){
        try {
            $protocol=Join-Path $PSScriptRoot '../../../../source/windows/DevFleet-HostAgentProtocol.psm1'
            $sha=(Get-FileHash -LiteralPath $protocol -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            $health=Invoke-ProductAuthenticatedHealthProbe -Session $Session -ProtocolSha256 $sha -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds($clientSeconds))
        } catch {$health.reasonCode='AUTHENTICATED_HEALTH_CLIENT_UNAVAILABLE'}
    }
    &$set $Observation 'authenticatedHealthEvidence' $health
    &$set $Observation 'authenticatedHealthOk' ([bool]$health.ok)
    &$set $Observation 'authenticatedHealthError' $(if($health.ok){''}else{[string]$health.reasonCode})
    $progress=&$get 'progress'
    if($progress){&$set $progress 'health' ([bool]$health.ok);&$set $Observation 'progressMarker' ($progress|ConvertTo-Json -Compress -Depth 20)}
    return $Observation
}

function Get-ProductLifecycleObservation {
    <#
      Reads one guest observation.  ObservationProvider is deliberately a
      seam is exposed by Wait-DevFleetProductLifecycleTransition; direct
      observation calls remain authenticated PSSession-only.
    #>
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TransactionId,
        [Parameter(Mandatory)][string]$PayloadSha256,
        [Parameter(Mandatory)][string]$Role,
        [string]$Action='FreshInstall',
        [int]$PriorGeneration=0,
        [int]$MaxGeneration=3,
        [int]$CandidateProcessId=0,
        [scriptblock]$ObservationProvider,
        [string]$ExpectedDevFleetVersion,
        [string]$ExpectedInstallerVersion,
        [int]$ObservationTimeoutSeconds=0,
        [string]$InvocationStartUtc,
        [string]$ExpectedComputeInstanceName,
        [string]$ExpectedVaultInstanceName,
        [string]$ExpectedNestedLinuxName,
        [scriptblock]$RemoteObservationProvider,
        [scriptblock]$GuestMarkerReadProvider,
        [object]$ObservationAdapterContext
    )
    if([string]::IsNullOrWhiteSpace($ExpectedDevFleetVersion)-or$ExpectedDevFleetVersion -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$'){throw 'TERMINAL_FAILURE: expected DevFleet version is missing or malformed.'}
    if([string]::IsNullOrWhiteSpace($ExpectedInstallerVersion)-or$ExpectedInstallerVersion -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$'){throw 'TERMINAL_FAILURE: expected installer version is missing or malformed.'}
    if($ObservationProvider){throw 'TERMINAL_FAILURE: ObservationProvider is only permitted through the bounded lifecycle wait seam.'}
    $observationDeadlineUtc=if($ObservationTimeoutSeconds -gt 0){[datetime]::UtcNow.AddSeconds($ObservationTimeoutSeconds)}else{[datetime]::MinValue}
    $remainingObservationSeconds={
        if($observationDeadlineUtc -le [datetime]::MinValue){return 20}
        return [int][math]::Floor(($observationDeadlineUtc-[datetime]::UtcNow).TotalSeconds)
    }
    $roleKind=Get-DevFleetLifecycleRoleKind -Role $Role
    if($ExpectedComputeInstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'){throw 'TERMINAL_FAILURE: expected product compute instance identity is missing or malformed.'}
    if($roleKind -ceq 'Desktop' -and $ExpectedVaultInstanceName){throw 'TERMINAL_FAILURE: Desktop product observation cannot authorize a Vault target.'}
    if($roleKind -ceq 'Laptop' -and $ExpectedVaultInstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'){throw 'TERMINAL_FAILURE: Laptop product observation requires the exact Vault identity.'}
    $targets=@([pscustomobject][ordered]@{instanceName=$ExpectedComputeInstanceName;nodeRole=if($roleKind -ceq 'Desktop'){'primary'}else{'surrogate'};kind='compute'})
    if($ExpectedVaultInstanceName){$targets+=,[pscustomobject][ordered]@{instanceName=$ExpectedVaultInstanceName;nodeRole='vault';kind='vault'}}
    if($ExpectedNestedLinuxName -and $ExpectedNestedLinuxName -in @($targets.instanceName)){throw 'TERMINAL_FAILURE: product observation target overlaps the harness cleanup identity.'}
    $stageMarkerPattern=Get-DevFleetLifecycleStageMarkerPattern -ExpectedComputeInstanceName $ExpectedComputeInstanceName -ExpectedVaultInstanceName $ExpectedVaultInstanceName
    $remoteScript = {
        param($tx,$payload,$expectedAction,$expectedRole,$prior,$max,$candidatePid,$expectedVersion,$expectedInstaller,$invocationStart,$expectedNestedLinux,$allowedStageMarkerPattern,$expectedStageRole)
        # A completion race can remove the checkpoint after Test-Path but before
        # Get-Content/Get-Item. Make those reads terminating so the narrow race
        # handler below can convert only that proven disappearance into an
        # absent checkpoint observation. Other malformed/readable checkpoint
        # failures remain terminal.
        $ErrorActionPreference='Stop'
        $checkpointPath='C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-checkpoint.json'
        $checkpoint=$null;$checkpointReadRace=$false
        if(Test-Path -LiteralPath $checkpointPath -PathType Leaf){
            try {
                $value=Get-Content -LiteralPath $checkpointPath -Raw|ConvertFrom-Json
                if($invocationStart){$created=[datetime]::MinValue;if(-not [datetime]::TryParse([string]$value.createdUtc,[ref]$created)){throw 'checkpoint lacks a trustworthy createdUtc provenance'};if($created.ToUniversalTime() -lt ([datetime]$invocationStart).ToUniversalTime()){throw 'checkpoint predates this lifecycle invocation'}}
                $checkpointGeneration=0;if(-not [int]::TryParse([string]$value.checkpointGeneration,[ref]$checkpointGeneration)){throw 'checkpoint generation is not numeric'}
                $checkpoint=[ordered]@{transactionId=[string]$value.transactionId;payloadSha256=[string]$value.payloadSha256;action=[string]$value.action;role=[string]$value.role;state=[string]$value.state;generation=$checkpointGeneration;checkpointGeneration=$checkpointGeneration;completedStages=@($value.completedStages);resumeStage=[string]$value.resumeStage;lastWriteUtc=(Get-Item -LiteralPath $checkpointPath).LastWriteTimeUtc.ToString('o')}
                if([int]$value.checkpointGeneration -lt 1 -or [int]$value.checkpointGeneration -gt $max){return [ordered]@{terminalFailure=$true;failure='invalid checkpoint generation';checkpoint=$checkpoint;checkpointPresent=$true}}
            } catch {
                # Completion or reboot-resume can remove the checkpoint between
                # the existence check and Get-Content/Get-Item. Treat only that
                # proven disappearance as an absent checkpoint and let the same
                # observation validate receipt, install, ownership, and process
                # state. A readable-but-invalid checkpoint remains terminal.
                if(-not (Test-Path -LiteralPath $checkpointPath -PathType Leaf)){$checkpoint=$null;$checkpointReadRace=$true}else{return [ordered]@{terminalFailure=$true;failure=$_.Exception.Message;checkpointPresent=$true}}
            }
        }
        $receiptPath="C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-consumed\$tx.json"
        $receipt=$null
        if(Test-Path -LiteralPath $receiptPath -PathType Leaf){try{$receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json}catch{return [ordered]@{terminalFailure=$true;failure='invalid consumed receipt'}}}
        if(-not $tx -and (Test-Path -LiteralPath (Split-Path -Parent $receiptPath) -PathType Container)){$receiptCandidates=@(Get-ChildItem -LiteralPath (Split-Path -Parent $receiptPath) -Filter '*.json' -File -ErrorAction SilentlyContinue|ForEach-Object{try{$r=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json;$consumed=[datetime]::MinValue;if(-not [datetime]::TryParse([string]$r.consumedUtc,[ref]$consumed)){return};if($invocationStart -and $consumed.ToUniversalTime() -lt ([datetime]$invocationStart).ToUniversalTime()){return};if([string]$r.payloadSha256 -ceq $payload -and [string]$r.action -ceq $expectedAction -and [string]$r.role -ceq $expectedRole){$r}}catch{}});if($receiptCandidates.Count -gt 1){return [ordered]@{terminalFailure=$true;failure='multiple current consumed receipts match the lifecycle payload/action/role';checkpointPresent=[bool]$checkpoint}}elseif($receiptCandidates.Count -eq 1){$receipt=$receiptCandidates[0];$tx=[string]$receipt.transactionId}}
        # AppPaths.LedgerPath is the installer-owned ledger, not the Host
        # Agent integration ledger. Validate JSON content and its canonical
        # ownership binding before advertising completion.
        $installPath='C:\ProgramData\M-TechLabs\DevFleet\Installer\install-state.json';$ownershipPath='C:\ProgramData\DevFleetHostAgent\integration-ownership.json'
        $installLedger=$null;$installValid=$false;$installError=''
        if(Test-Path -LiteralPath $installPath -PathType Leaf){try{$installLedger=Get-Content -LiteralPath $installPath -Raw|ConvertFrom-Json;$canonicalInstallRoot='C:\Program Files\M-TechLabs\DevFleet';$filesValid=$true;foreach($file in @($installLedger.FilesInstalled|Where-Object{$_})){if(-not [IO.Path]::GetFullPath([string]$file).StartsWith($canonicalInstallRoot+'\',[StringComparison]::OrdinalIgnoreCase)){$filesValid=$false}};if([string]::IsNullOrWhiteSpace($expectedVersion)-or([string]$installLedger.DevFleetVersion -ceq $expectedVersion -and [string]$installLedger.InstallerVersion -ceq $expectedInstaller -and [string]$installLedger.PackageSha256 -ceq $payload -and [guid]::Parse([string]$installLedger.InstallationGeneration) -ne [guid]::Empty -and [string]$installLedger.WindowsIntegrationOwnershipPath -ieq $ownershipPath -and $filesValid)){$installValid=$true}else{$installError='installer ledger identity/schema/path mismatch'}}catch{$installError='installer ledger is unreadable'}}else{$installError='installer ledger is absent'}
        $ownershipLedger=$null;$ownershipValid=$false;$ownershipError=''
        if(Test-Path -LiteralPath $ownershipPath -PathType Leaf){try{$ownershipLedger=Get-Content -LiteralPath $ownershipPath -Raw|ConvertFrom-Json;$bindings=@($ownershipLedger.ScheduledTasks)+@($ownershipLedger.FirewallRules)+@($ownershipLedger.Services);$ownershipValid=([int]$ownershipLedger.SchemaVersion -eq 1 -and [string]$ownershipLedger.InstallationGeneration -and $installLedger -and [string]$ownershipLedger.InstallationGeneration -ceq [string]$installLedger.InstallationGeneration -and (@($bindings|Where-Object{[string]$_.Generation -and [string]$_.Generation -cne [string]$ownershipLedger.InstallationGeneration -or [string]$_.Name -match '[*?]'}).Count -eq 0))}catch{$ownershipError='ownership ledger is unreadable'}}else{$ownershipError='ownership ledger is absent'}
        $fileHash={param($path)if(Test-Path -LiteralPath $path -PathType Leaf){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null}}
        $installHash=& $fileHash $installPath;$ownershipHash=& $fileHash $ownershipPath
        # PSDirect defaults to Windows PowerShell 5.1. The authenticated client
        # runs later in an owned, bounded PowerShell 7 child after identity checks.
        $healthOk=$false;$healthError='AUTHENTICATED_HEALTH_NOT_OBSERVED'
        $all=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
        $root=if($candidatePid -gt 0){$all|Where-Object{[int]$_.ProcessId -eq $candidatePid}|Select-Object -First 1}else{$null}
        $commandClass={param($row)
            $line=[string]$row.CommandLine
            if($line -match '(?i)Bootstrap-Install'){return 'Bootstrap-Install'}
            if($line -match '(?i)Install-DevFleet'){return 'Install-DevFleet'}
            if([string]$row.Name -match '(?i)^winget'){return 'winget'}
            if([string]$row.Name -match '(?i)^msiexec'){return 'msiexec'}
            if([string]$row.Name -match '(?i)^multipass'){return 'multipass'}
            if([int]$row.ProcessId -eq $candidatePid){return 'DevFleet-Setup'}
            return 'candidate-child'
        }
        $compactProcess={param($row)
            if(-not $row){return $null}
            $runtime=$null;try{$runtime=Get-Process -Id ([int]$row.ProcessId) -ErrorAction Stop}catch{}
            $class=&$commandClass $row
            [ordered]@{
                pid=[int]$row.ProcessId;parentPid=[int]$row.ParentProcessId;name=[string]$row.Name;path=[string]$row.ExecutablePath;sessionId=[int]$row.SessionId
                commandLineRedacted=("{0} {1} <arguments redacted>" -f [string]$row.Name,$class).Trim()
                commandClass=$class
                startTimeUtc=if($runtime){try{$runtime.StartTime.ToUniversalTime().ToString('o')}catch{''}}else{''}
                cpuSeconds=if($runtime){try{[math]::Round([double]$runtime.TotalProcessorTime.TotalSeconds,3)}catch{0.0}}else{0.0}
                responding=if($runtime){try{[bool]$runtime.Responding}catch{$false}}else{$false}
            }
        }
        $interesting=@($all|Where-Object{[string]$_.Name -match '(?i)DevFleet|msiexec|winget|multipass|powershell|pwsh' -or [string]$_.CommandLine -match '(?i)Bootstrap-Install|Install-DevFleet'}|Sort-Object ProcessId|Select-Object -First 80|ForEach-Object{&$compactProcess $_})
        $candidateTreeIds=[System.Collections.Generic.HashSet[int]]::new();if($candidatePid -gt 0){[void]$candidateTreeIds.Add($candidatePid)}
        do{$added=$false;foreach($row in $all){if($candidateTreeIds.Contains([int]$row.ParentProcessId)-and $candidateTreeIds.Add([int]$row.ProcessId)){$added=$true}}}while($added)
        # V2SocketServerMode is a CommandLine marker on powershell.exe, not a
        # process name.  Also exclude remoting/WMI helper command lines from
        # candidate descendants before calculating semantic process activity.
        $observerPattern='(?i)V2SocketServerMode|ServerRemoteHost|WSMan|WinRM|CimCmdlets|Get-CimInstance|Invoke-Command|Enter-PSSession'
        $progressProcesses=@($all|Where-Object{
            $isObserver=[string]$_.CommandLine -match $observerPattern
            $isCandidate=$candidateTreeIds.Contains([int]$_.ProcessId)
            $isBootstrap=([string]$_.CommandLine -match '(?i)Bootstrap-Install|Install-DevFleet') -and [string]$_.CommandLine -notmatch $observerPattern
            ($isCandidate -or $isBootstrap) -and -not $isObserver
        }|Sort-Object Name,ExecutablePath|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,SessionId)
        $cpu=0.0;foreach($row in $progressProcesses){try{$cpu += [double](Get-Process -Id ([int]$row.ProcessId) -ErrorAction Stop).TotalProcessorTime.TotalSeconds}catch{}}
        $stages=@($progressProcesses|ForEach-Object{[ordered]@{name=[string]$_.Name;path=[string]$_.ExecutablePath;commandClass=(&$commandClass $_)}})
        $instances=@($progressProcesses|ForEach-Object{&$compactProcess $_})
        $bootstrap=@('C:\ProgramData\M-TechLabs\DevFleet\Installer\Bootstrap-Install.ps1','C:\ProgramData\M-TechLabs\DevFleet\Installer\Install-DevFleet.ps1')|ForEach-Object{[ordered]@{path=$_;present=(Test-Path -LiteralPath $_ -PathType Leaf)}}
        $activePath='C:\ProgramData\DevFleet\active-transaction.json';$activeTransaction=$null;$activeHash=$null
        if(Test-Path -LiteralPath $activePath -PathType Leaf){
            try{$raw=Get-Content -LiteralPath $activePath -Raw;$activeValue=$raw|ConvertFrom-Json;$activeTransaction=[ordered]@{path=$activePath;transactionId=[string]$activeValue.transactionId;payloadSha256=[string]$activeValue.payloadSha256;action=[string]$activeValue.action;role=[string]$activeValue.role;preparedUtc=[string]$activeValue.preparedUtc;lastWriteUtc=(Get-Item -LiteralPath $activePath).LastWriteTimeUtc.ToString('o')};$activeHash=(Get-FileHash -LiteralPath $activePath -Algorithm SHA256).Hash.ToLowerInvariant()}catch{$activeTransaction=[ordered]@{path=$activePath;error='active transaction record is unreadable'}}
        }
        $stageMarkers=@();$stageMarkerErrors=@()
         foreach($stateRoot in @('C:\ProgramData\DevFleet','C:\ProgramData\M-TechLabs\DevFleet\Installer')){
            if(-not(Test-Path -LiteralPath $stateRoot -PathType Container)){continue}
            foreach($marker in @(Get-ChildItem -LiteralPath $stateRoot -Filter 'stage-*.complete' -File -ErrorAction SilentlyContinue)){
                try {
                    if(([string]$marker.Name) -notmatch $allowedStageMarkerPattern){$stageMarkerErrors+=[ordered]@{name=$marker.Name;error='stage marker name is not allowlisted'};continue}
                    $markerValue=Get-Content -LiteralPath $marker.FullName -Raw|ConvertFrom-Json -ErrorAction Stop
                    $completed=[datetime]::MinValue;$fresh=[datetime]::TryParse([string]$markerValue.completedUtc,[ref]$completed);if($fresh -and $invocationStart){$fresh=$completed.ToUniversalTime() -ge ([datetime]$invocationStart).ToUniversalTime()}
                    $bound=($fresh -and ([string]$markerValue.transactionId) -match '^[0-9a-fA-F]{32}$' -and ([string]$markerValue.payloadSha256) -ceq $payload -and ([string]$markerValue.action) -ceq $expectedAction -and ([string]$markerValue.role) -ceq $expectedStageRole -and (-not $tx -or ([string]$markerValue.transactionId) -ceq $tx))
                    if(-not $bound){$stageMarkerErrors+=[ordered]@{name=$marker.Name;error='stage marker is stale, malformed, or not bound to the current lifecycle'};continue}
                    $stageMarkers+=[ordered]@{name=$marker.Name;path=$marker.FullName;transactionId=[string]$markerValue.transactionId;payloadSha256=[string]$markerValue.payloadSha256;action=[string]$markerValue.action;role=[string]$markerValue.role;stage=[string]$markerValue.stage;completedUtc=$completed.ToUniversalTime().ToString('o');lastWriteUtc=$marker.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $marker.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
                } catch {$stageMarkerErrors+=[ordered]@{name=$marker.Name;error='stage marker is unreadable'}}
             }
         }
         # The nested compute guest is owned by host Multipass, not by the
         # disposable Windows observer VM.  Keep the remote observation
         # authenticated to L1 and attach the bounded host-side guest read
         # after this script block returns.
         $progressGuestMarker=$null;$progressGuestMarkerStatus='DEFERRED';$progressGuestMarkerError='host-side nested guest probe is deferred'
        $pfr=@((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
        $pfrPairs=@();for($i=0;$i -lt $pfr.Count;$i+=2){$src=[string]$pfr[$i];$dst=if($i+1 -lt $pfr.Count){[string]$pfr[$i+1]}else{''};if($src -or $dst){$pfrPairs+=[ordered]@{source=$src;destination=$dst}}}
        $ownedPfr=@($pfrPairs|Where-Object{[string]$_.source -match '(?i)DevFleet|M-TechLabs' -or [string]$_.destination -match '(?i)DevFleet|M-TechLabs'})
        $servicing=[ordered]@{cbsRebootPending=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending');windowsUpdateRebootRequired=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired');pendingFileRenamePairCount=$pfrPairs.Count;ownedPendingFileRenamePairs=$ownedPfr;foreignPendingFileRenamePairCount=[Math]::Max(0,$pfrPairs.Count-$ownedPfr.Count)}
        $task=$null;try{$task=Get-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue}catch{}
        $listener=$false;try{$listener=@(Get-NetTCPConnection -LocalPort 8790 -State Listen -ErrorAction SilentlyContinue).Count -gt 0}catch{}
        $receiptFresh=$false;if($receipt){$consumed=[datetime]::MinValue;$receiptFresh=[datetime]::TryParse([string]$receipt.consumedUtc,[ref]$consumed);if($receiptFresh -and $invocationStart){$receiptFresh=$consumed.ToUniversalTime() -ge ([datetime]$invocationStart).ToUniversalTime()}};$receiptMatch=([bool]$receipt-and$receiptFresh-and(-not $tx -or [string]$receipt.transactionId-eq$tx)-and[string]$receipt.payloadSha256-eq$payload-and[string]$receipt.action-eq$expectedAction-and[string]$receipt.role-eq$expectedRole)
        $processExited=($candidatePid -gt 0 -and -not $root)
        $terminalFailure=$false;$failure='';if($processExited-and-not$checkpoint-and-not$receiptMatch-and-not$installValid){$terminalFailure=$true;$failure='candidate process exited before a durable checkpoint or completion state'}
        $candidateCompact=&$compactProcess $root
         # File hashes and LastWriteTime are not semantic: rewriting a
         # timestamp on the same bound stage marker must not extend the wait.
         $markerSet=(@($stageMarkers|ForEach-Object{"$($_.name):$($_.transactionId):$($_.payloadSha256):$($_.action):$($_.role):$($_.stage)"}|Sort-Object)-join '|')
        $servicingState=($servicing|ConvertTo-Json -Compress -Depth 8)
          $progress=[ordered]@{checkpointState=if($checkpoint){[string]$checkpoint.state}else{''};completedStages=if($checkpoint){@($checkpoint.completedStages)}else{@()};resumeStage=if($checkpoint){[string]$checkpoint.resumeStage}else{''};stages=$stages;productChildInstances=$instances;cpuSeconds=[math]::Round($cpu,3);candidateProcessPresent=[bool]$root;candidateResponsive=if($candidateCompact){[bool]$candidateCompact.responding}else{$false};activeTransactionSha256=$activeHash;stageMarkerSet=$markerSet;servicingState=$servicingState;installStateSha256=$installHash;ownershipSha256=$ownershipHash;receiptMatch=$receiptMatch;health=$healthOk;checkpointReadRaceRecovered=$checkpointReadRace;hostAgentTaskState=if($task){[string]$task.State}else{'ABSENT'};listener=$listener;guestProgressMarker=$progressGuestMarker;guestProgressMarkerStatus=$progressGuestMarkerStatus;guestProgressMarkerError=$progressGuestMarkerError};if($checkpoint){$progress.checkpointGeneration=[int]$checkpoint.checkpointGeneration}
         [ordered]@{checkpointPresent=[bool]$checkpoint;checkpoint=$checkpoint;checkpointReadRaceRecovered=$checkpointReadRace;receipt=$receipt;matchingConsumedReceipt=$receiptMatch;installStateValid=$installValid;installLedger=$installLedger;installStateError=$installError;canonicalOwnershipValid=$ownershipValid;ownershipLedger=$ownershipLedger;ownershipStateError=$ownershipError;authenticatedHealthOk=$healthOk;authenticatedHealthError=$healthError;terminalFailure=$terminalFailure;failure=$failure;candidateProcessExited=$processExited;candidateProcess=$candidateCompact;processTree=$interesting;bootstrap=$bootstrap;activeTransaction=$activeTransaction;stageMarkers=$stageMarkers;stageMarkerErrors=$stageMarkerErrors;servicing=$servicing;hostAgentTaskState=if($task){[string]$task.State}else{'ABSENT'};hostAgentListener=$listener;progress=$progress;progressMarker=($progress|ConvertTo-Json -Compress -Depth 20);timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
    }
    $readGuestMarker = {
        param(
            [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$GuestSession,
            [Parameter(Mandatory)][object[]]$ProductTargets,
            [Parameter(Mandatory)][int]$ReadTimeoutSeconds
        )
        try {
            # The compute guest is nested inside the disposable Windows L1.
            # Querying the root host's Multipass daemon can only see unrelated
            # root-host instances and turns a topology miss into a false
            # "guest marker is absent" result. Keep both discovery and the
            # bounded reads authenticated to the exact L1 session used for the
            # Windows observation. Only the role-bound product identities
            # supplied by the candidate-bound resolver are observation targets.
            # The disposable E2E cleanup name is never a product fallback.
            $remoteJob=Invoke-Command -Session $GuestSession -ScriptBlock {
                param([string[]]$ProductInstanceNames)
                $remote=[ordered]@{status='UNVERIFIED';error='';inventoryExitCode=$null;probedInstances=@();markerReads=@()}
                $mpCandidates=@(
                    (Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'),
                    (Join-Path ${env:ProgramFiles(x86)} 'Multipass\bin\multipass.exe')
                ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
                $mp=$mpCandidates | Select-Object -First 1
                if(-not $mp){$command=Get-Command multipass.exe -ErrorAction SilentlyContinue;if(-not $command){$command=Get-Command multipass -ErrorAction SilentlyContinue};if($command){$mp=$command.Source}}
                if(-not $mp){$remote.status='INVENTORY_UNAVAILABLE';$remote.error='multipass executable unavailable inside disposable L1';return [pscustomobject]$remote}
                $candidateInstances=@($ProductInstanceNames|Where-Object{$_ -and $_ -match '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'}|Select-Object -Unique)
                if($candidateInstances.Count -ne @($ProductInstanceNames).Count -or $candidateInstances.Count -lt 1 -or $candidateInstances.Count -gt 2){$remote.status='TARGET_INVALID';$remote.error='role-bound product target set is malformed';return [pscustomobject]$remote}
                $inventoryJob=Start-Job -ScriptBlock {param($Path)$output=@(& $Path list --format json 2>&1);[pscustomobject]@{text=($output|Out-String).Trim();exitCode=$LASTEXITCODE}} -ArgumentList $mp
                try {
                    if(-not (Wait-Job -Job $inventoryJob -Timeout 4)){Stop-Job -Job $inventoryJob -ErrorAction SilentlyContinue;$remote.status='INVENTORY_TIMEOUT';$remote.error='multipass inventory read timed out';return [pscustomobject]$remote}
                    $inventoryResult=Receive-Job -Job $inventoryJob -ErrorAction SilentlyContinue|Select-Object -Last 1
                } finally {Remove-Job -Job $inventoryJob -Force -ErrorAction SilentlyContinue}
                if($null -eq $inventoryResult -or $null -eq $inventoryResult.exitCode){$remote.status='INVENTORY_FAILURE';$remote.error='multipass inventory returned no native exit status';return [pscustomobject]$remote}
                $remote.inventoryExitCode=[int]$inventoryResult.exitCode
                if([int]$inventoryResult.exitCode -ne 0){$remote.status='INVENTORY_FAILURE';$remote.error="multipass inventory failed with native exit code $([int]$inventoryResult.exitCode)";return [pscustomobject]$remote}
                $inventoryText=[string]$inventoryResult.text
                $inventory=$null
                try {$inventory=$inventoryText|ConvertFrom-Json -ErrorAction Stop} catch {$remote.status='INVENTORY_MALFORMED';$remote.error='multipass inventory was unreadable inside disposable L1';return [pscustomobject]$remote}
                $hasListProperty=($null -ne $inventory -and $null -ne $inventory.PSObject.Properties['list'])
                $records=if($hasListProperty){@($inventory.list)}elseif($inventory -is [System.Array]){@($inventory)}else{$remote.status='INVENTORY_MALFORMED';$remote.error='multipass inventory did not contain a list';return [pscustomobject]$remote}
                $available=@($records|ForEach-Object{[string]$_.name}|Where-Object{$_})
                $toProbe=@($candidateInstances|Where-Object{$available -contains $_})
                $remote.probedInstances=@($toProbe)
                if(-not $toProbe){$remote.status='INSTANCE_ABSENT';$remote.error='no configured Multipass instance is present inside disposable L1';return [pscustomobject]$remote}
                foreach($instance in $toProbe){
                    $markerJob=Start-Job -ScriptBlock {param($Path,$Name)$probe="if [ ! -e /var/lib/devfleet/bootstrap-progress.json ]; then exit 44; fi; if [ ! -f /var/lib/devfleet/bootstrap-progress.json ]; then exit 45; fi; cat -- /var/lib/devfleet/bootstrap-progress.json";$output=@(& $Path exec $Name -- sudo sh -c $probe 2>&1);[pscustomobject]@{instanceName=$Name;text=($output|Out-String).Trim();exitCode=$LASTEXITCODE;timedOut=$false}} -ArgumentList $mp,$instance
                    try {
                        if(Wait-Job -Job $markerJob -Timeout 4){$read=Receive-Job -Job $markerJob -ErrorAction SilentlyContinue|Select-Object -Last 1;if($read){$remote.markerReads+=,$read}else{$remote.markerReads+=,[pscustomobject]@{instanceName=$instance;text='';exitCode=$null;timedOut=$false}}}
                        else {Stop-Job -Job $markerJob -ErrorAction SilentlyContinue;$remote.markerReads+=,[pscustomobject]@{instanceName=$instance;text='';exitCode=$null;timedOut=$true}}
                    } finally {Remove-Job -Job $markerJob -Force -ErrorAction SilentlyContinue}
                }
                $remote.status='READS_COLLECTED'
                return [pscustomobject]$remote
            } -ArgumentList (,([string[]]@($ProductTargets.instanceName))) -AsJob -ErrorAction Stop
            try {
                if($ReadTimeoutSeconds -le 0 -or -not(Wait-Job -Job $remoteJob -Timeout $ReadTimeoutSeconds)){Stop-Job -Job $remoteJob -ErrorAction SilentlyContinue;return [pscustomobject]@{status='TIMEOUT';error='guest marker observation exceeded the immutable observation deadline';inventoryExitCode=$null;probedInstances=@();markerReads=@()}}
                $remoteResult=Receive-Job -Job $remoteJob -ErrorAction Stop
            } finally {Remove-Job -Job $remoteJob -Force -ErrorAction SilentlyContinue}
            if($remoteResult){return Resolve-DevFleetRoleBoundGuestMarkerReads -RemoteResult $remoteResult -Targets $ProductTargets -TransactionId $TransactionId -PayloadSha256 $PayloadSha256}
        } catch {return [pscustomobject]@{status='TRANSPORT_FAILURE';marker=$null;markers=@();requiredMarkersValid=$false;error='guest marker observation transport failed';exitCode=$null;instanceName='';probedInstances=@();readResults=@();rejectedReadNames=@()}}
        return [pscustomobject]@{status='UNVERIFIED';marker=$null;markers=@();requiredMarkersValid=$false;error='guest marker observation returned no result';exitCode=$null;instanceName='';probedInstances=@();readResults=@();rejectedReadNames=@()}
    }
    $attachGuestMarker = {
        param([object]$Observation)
        if(-not $Observation){return $Observation}
        $readRemaining=&$remainingObservationSeconds
        if($GuestMarkerReadProvider){
            $rawGuest=&$GuestMarkerReadProvider ([pscustomobject][ordered]@{targets=$targets;transactionId=$TransactionId;payloadSha256=$PayloadSha256;role=$Role;timeoutSeconds=$readRemaining;context=$ObservationAdapterContext})
            $guest=Resolve-DevFleetRoleBoundGuestMarkerReads -RemoteResult $rawGuest -Targets $targets -TransactionId $TransactionId -PayloadSha256 $PayloadSha256
        }else{$guest=&$readGuestMarker $Session $targets $readRemaining}
        if($Observation -is [System.Collections.IDictionary]){$progress=$Observation.progress}else{$progress=$Observation.progress}
        if(-not $progress){return $Observation}
        return (Add-GuestProgressMarkerObservation -Observation $Observation -ReadResult ([pscustomobject]$guest))
    }
    if($RemoteObservationProvider){
        $observationRemaining=&$remainingObservationSeconds
        if($observationRemaining -le 0){return [ordered]@{terminalFailure=$true;failure='observer fixture call timeout';observerCallTimedOut=$true;timestampUtc=(Get-Date).ToUniversalTime().ToString('o');progress=[ordered]@{}}}
        $providerState=[pscustomobject][ordered]@{transactionId=$TransactionId;payloadSha256=$PayloadSha256;action=$Action;role=$Role;roleKind=$roleKind;priorGeneration=$PriorGeneration;maxGeneration=$MaxGeneration;candidateProcessId=$CandidateProcessId;expectedDevFleetVersion=$ExpectedDevFleetVersion;expectedInstallerVersion=$ExpectedInstallerVersion;invocationStartUtc=$InvocationStartUtc;expectedComputeInstanceName=$ExpectedComputeInstanceName;expectedVaultInstanceName=$ExpectedVaultInstanceName;expectedCleanupInstanceName=$ExpectedNestedLinuxName;targets=$targets;allowedStageMarkerPattern=$stageMarkerPattern;context=$ObservationAdapterContext}
        $providerJob=Start-ThreadJob -ScriptBlock {param($provider,$state)&$provider $state} -ArgumentList $RemoteObservationProvider,$providerState
        if(-not (Wait-Job -Job $providerJob -Timeout $observationRemaining)){Stop-Job -Job $providerJob -ErrorAction SilentlyContinue;Remove-Job -Job $providerJob -Force -ErrorAction SilentlyContinue;return [ordered]@{terminalFailure=$true;failure='observer fixture call timeout';observerCallTimedOut=$true;timestampUtc=(Get-Date).ToUniversalTime().ToString('o');progress=[ordered]@{}}}
        try{$observation=Receive-Job -Job $providerJob -ErrorAction Stop}finally{Remove-Job -Job $providerJob -Force -ErrorAction SilentlyContinue}
    }elseif($ObservationTimeoutSeconds -gt 0){
        $observationRemaining=&$remainingObservationSeconds
        if($observationRemaining -le 0){return [ordered]@{terminalFailure=$true;failure='observer remote call timeout';observerCallTimedOut=$true;timestampUtc=(Get-Date).ToUniversalTime().ToString('o');progress=[ordered]@{}}}
        $job=Invoke-Command -Session $Session -ScriptBlock $remoteScript -ArgumentList $TransactionId,$PayloadSha256,$Action,$Role,$PriorGeneration,$MaxGeneration,$CandidateProcessId,$ExpectedDevFleetVersion,$ExpectedInstallerVersion,$InvocationStartUtc,$ExpectedNestedLinuxName,$stageMarkerPattern,$roleKind -AsJob
        if(-not (Wait-Job -Job $job -Timeout $observationRemaining)){Stop-Job -Job $job -ErrorAction SilentlyContinue;Remove-Job -Job $job -Force -ErrorAction SilentlyContinue;return [ordered]@{terminalFailure=$true;failure='observer remote call timeout';observerCallTimedOut=$true;timestampUtc=(Get-Date).ToUniversalTime().ToString('o');progress=[ordered]@{}}}
        try{$observation=Receive-Job -Job $job -ErrorAction Stop}finally{Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
    }else{$observation=Invoke-Command -Session $Session -ScriptBlock $remoteScript -ArgumentList $TransactionId,$PayloadSha256,$Action,$Role,$PriorGeneration,$MaxGeneration,$CandidateProcessId,$ExpectedDevFleetVersion,$ExpectedInstallerVersion,$InvocationStartUtc,$ExpectedNestedLinuxName,$stageMarkerPattern,$roleKind}
    $observation=Resolve-DevFleetLifecycleStageMarkerObservation -Observation $observation -AllowedPattern $stageMarkerPattern -ExpectedStageRole $roleKind -TransactionId $TransactionId -PayloadSha256 $PayloadSha256 -Action $Action -InvocationStartUtc $InvocationStartUtc
    $deferral=Get-DevFleetProductLaunchProbeDeferral -Observation $observation -Targets $targets -TransactionId $TransactionId -PayloadSha256 $PayloadSha256 -Action $Action -RoleKind $roleKind -CandidateProcessId $CandidateProcessId -InvocationStartUtc $InvocationStartUtc
    if($deferral){
        $detail="Guest probes deferred while bound product Multipass child $($deferral.nativeProcessId) is active after $($deferral.stage)."
        $reads=@(foreach($target in $targets){[pscustomobject]@{instanceName=$target.instanceName;status='DEFERRED_PRODUCT_LAUNCH';error=$detail;exitCode=$null}})
        $deferred=[pscustomobject]@{status='DEFERRED_PRODUCT_LAUNCH';marker=$null;markers=@();requiredMarkersValid=$false;error=$detail;exitCode=$null;probedInstances=@();readResults=$reads}
        return (Add-GuestProgressMarkerObservation -Observation $observation -ReadResult $deferred)
    }
    $observation=&$attachGuestMarker $observation
    if(-not $RemoteObservationProvider){$observation=Add-ProductAuthenticatedHealthObservation -Observation $observation -Session $Session -RemainingSeconds (&$remainingObservationSeconds)}
    $failureFound=$false;$failed=Get-LifecycleProperty $observation 'terminalFailure' ([ref]$failureFound)
    if($failureFound -and $failed){
        $snapshot=Get-ProductFailureLogSnapshot -Session $Session -TransactionId $TransactionId -PayloadSha256 $PayloadSha256 -InvocationStartUtc $InvocationStartUtc -TimeoutSeconds (&$remainingObservationSeconds)
        if($observation -is [System.Collections.IDictionary]){$observation['failureLogSnapshot']=$snapshot}else{$observation|Add-Member -NotePropertyName failureLogSnapshot -NotePropertyValue $snapshot -Force}
    }
    return $observation
}

function Get-ProductFailureLogSnapshot {
    param([object]$Session,[string]$TransactionId,[string]$PayloadSha256,[string]$InvocationStartUtc,[int]$TimeoutSeconds)
    $result=[ordered]@{status='UNAVAILABLE';transactionId=$TransactionId;payloadSha256=$PayloadSha256;records=@();capturedAtUtc=[datetime]::UtcNow.ToString('o');error=''}
    $job=$null
    try {
        if(-not $Session -or $TimeoutSeconds -le 0){throw 'No live session or observation time remains for failure-log collection.'}
        if($TransactionId -notmatch '^[0-9a-f]{32}$' -or $PayloadSha256 -notmatch '^[0-9a-f]{64}$'){throw 'Failure-log request identity is invalid.'}
        $since=[datetime]::Parse($InvocationStartUtc).ToUniversalTime()
        $collector={
            param($tx,$payload,$since)
            $ErrorActionPreference='Stop'
            # Read only the current transaction and recent setup logs inside L1.
            # Do not call Multipass or inspect secret/configuration files.
            $activePath=Join-Path $env:ProgramData 'DevFleet/active-transaction.json'
            $logRoot=Join-Path $env:ProgramData 'M-TechLabs/DevFleet/Logs'
            foreach($path in @($env:ProgramData,(Join-Path $env:ProgramData 'DevFleet'),$activePath,(Join-Path $env:ProgramData 'M-TechLabs'),(Join-Path $env:ProgramData 'M-TechLabs/DevFleet'),$logRoot)){
                if((Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Failure-log source contains a reparse point.'}
            }
            $active=Get-Content -LiteralPath $activePath -Raw|ConvertFrom-Json
            if([string]$active.transactionId -cne $tx -or [string]$active.payloadSha256 -cne $payload){throw 'Failure-log active transaction mismatch.'}
            $logs=@(Get-ChildItem -LiteralPath $logRoot -Filter 'setup-*.log' -File|Where-Object{$_.LastWriteTimeUtc -ge $since}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 2)
            $records=@(foreach($log in $logs){
                if($log.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Failure-log file is a reparse point.'}
                $pairingLog=$log.Name -like 'setup-tailscale-pairing-*.log'
                if($pairingLog){
                    $headLines=[Collections.Generic.List[string]]::new();$tailLines=[Collections.Generic.Queue[string]]::new();$smallLines=[Collections.Generic.List[string]]::new();$lineCount=0
                    foreach($line in [IO.File]::ReadLines($log.FullName)){
                        $lineCount++
                        if($headLines.Count -lt 32){[void]$headLines.Add([string]$line)}
                        if($smallLines.Count -lt 113){[void]$smallLines.Add([string]$line)}
                        if($tailLines.Count -ge 80){[void]$tailLines.Dequeue()}
                        [void]$tailLines.Enqueue([string]$line)
                    }
                    $capturedLines=$null
                    if($lineCount -le 113){$capturedLines=@($smallLines.ToArray())}else{$capturedLines=@($headLines.ToArray())+@('[... middle omitted ...]')+@($tailLines.ToArray())}
                    [pscustomobject]@{name=$log.Name;bytes=$log.Length;lastWriteUtc=$log.LastWriteTimeUtc.ToString('o');tail=($capturedLines-join "`n");lineLimit=$capturedLines.Count;headLineLimit=32;tailLineLimit=80;tailOnly=$false}
                }else{
                    [pscustomobject]@{name=$log.Name;bytes=$log.Length;lastWriteUtc=$log.LastWriteTimeUtc.ToString('o'