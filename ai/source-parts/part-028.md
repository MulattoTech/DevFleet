# DevFleet source part 028

Full-source UTF-8 byte interval [1255500, 1302000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 909fb8e63fe97c54078b5cc1af40c9ca88d2ffb6d5db4f25debc4fc9f4c701e7

<!-- BEGIN SOURCE SLICE -->
);tail=(@(Get-Content -LiteralPath $log.FullName -Tail 80)-join "`n");lineLimit=80;tailOnly=$true}
                }
            })
            [pscustomobject]@{records=$records}
        }
        $job=Invoke-Command -Session $Session -ScriptBlock $collector -ArgumentList $TransactionId,$PayloadSha256,$since -AsJob
        if(-not(Wait-Job -Job $job -Timeout ([math]::Min(20,$TimeoutSeconds)))){throw 'Failure-log collection exceeded its bounded observation time.'}
        $values=@(Receive-Job -Job $job -ErrorAction Stop)
        if($values.Count -ne 1){throw 'Failure-log collection returned an ambiguous record.'}
        $result.records=@(foreach($record in $values[0].records){
            # Redact entire potentially sensitive lines before the shared bounded
            # sanitizer. This also covers quoted/multiword secret assignments.
            $lines=@([string]$record.tail -split "`r?`n"|ForEach-Object{if($_ -match '(?i)password|secret|token|authorization|hmac|bearer|tskey-|auth.?key|api.?key|dpapi|login\.tailscale\.com'){ '[sensitive log line redacted]' }else{$_}})
            $lineLimit=if($record.PSObject.Properties.Name -contains 'lineLimit'){[int]$record.lineLimit}else{80}
            $tailOnly=if($record.PSObject.Properties.Name -contains 'tailOnly'){[bool]$record.tailOnly}else{$true}
            $maxDiagnosticChars=32768;if($tailOnly){$maxDiagnosticChars=16384}
            [pscustomobject]@{name=[string]$record.name;bytes=[long]$record.bytes;lastWriteUtc=[string]$record.lastWriteUtc;tail=ConvertTo-DevFleetDiagnosticSafeText ($lines -join "`n") $maxDiagnosticChars;lineLimit=$lineLimit;headLineLimit=if($record.PSObject.Properties.Name -contains 'headLineLimit'){[int]$record.headLineLimit}else{$null};tailLineLimit=if($record.PSObject.Properties.Name -contains 'tailLineLimit'){[int]$record.tailLineLimit}else{$null};tailOnly=$tailOnly;sanitized=$true}
        })
        $result.status=if($result.records.Count){'OBSERVED'}else{'NO_RECENT_LOG'}
    } catch {
        $result.records=@();$result.error=ConvertTo-DevFleetDiagnosticSafeText $_.Exception.Message 512
    } finally {
        if($job){Stop-Job -Job $job -ErrorAction SilentlyContinue;Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
    }
    return [pscustomobject]$result
}

function Test-GuestProgressMarkerTransition {
    param([AllowNull()][object]$Previous,[AllowNull()][object]$Current,[string]$TransactionId,[string]$PayloadSha256)
    if(-not $Current){return $false}
    $get={param($o,$n)$f=$false;Get-LifecycleProperty $o $n ([ref]$f)}
    $tx=[string](&$get $Current 'transactionId');$payload=[string](&$get $Current 'payloadSha256');$state=[string](&$get $Current 'state');$component=[string](&$get $Current 'component');$sequenceText=[string](&$get $Current 'sequence')
    if($TransactionId -and $tx -cne $TransactionId){return $false};if($PayloadSha256 -and $payload -cne $PayloadSha256){return $false}
    if($tx -notmatch '^[0-9a-fA-F]{32}$' -or $payload -notmatch '^[0-9a-fA-F]{64}$' -or $state -notin @('STARTED','COMPLETED','FAILED','TIMED_OUT')){return $false}
    $sequence=0;if(-not [int]::TryParse($sequenceText,[ref]$sequence)-or$sequence -lt 1){return $false}
    $nodeRole=[string](&$get $Current 'nodeRole')
    $order=if($nodeRole -ieq 'vault'){@('secretsInput','packagePrerequisites','tailscaleChecks','restServer','serviceConfiguration','firewallFinalization','bootstrap')}else{@('secretsInput','packagePrerequisites','dockerRepositoryAndInstall','tailscaleRepositoryAndInstall','rootlessRuntime','nodeToolchain','pythonRuntime','serviceAndFirewallFinalization','bootstrap')}
    if($component -notin $order){return $false}
    if($Previous){
        $previousSequence=0;$previousSequenceText=[string](&$get $Previous 'sequence');if(-not [int]::TryParse($previousSequenceText,[ref]$previousSequence)-or$sequence -le $previousSequence){return $false}
        $previousTx=[string](&$get $Previous 'transactionId');$previousPayload=[string](&$get $Previous 'payloadSha256');$previousComponent=[string](&$get $Previous 'component');$previousState=[string](&$get $Previous 'state');if($previousTx -cne $tx -or $previousPayload -cne $payload){return $false}
        $oldIndex=[array]::IndexOf($order,$previousComponent);$newIndex=[array]::IndexOf($order,$component)
        if($newIndex -lt $oldIndex -or ($newIndex -eq $oldIndex -and $previousState -ne 'STARTED')){return $false}
        if($newIndex -eq $oldIndex -and $state -eq 'STARTED'){return $false}
    }
    return $true
}

function Test-ProductMeaningfulProgress {
    param([AllowNull()][psobject]$Previous,[Parameter(Mandatory)][psobject]$Current,[double]$CpuDeltaThreshold=1.0,[string]$TransactionId,[string]$PayloadSha256)
    if(-not $Previous){return $true}
    $found=$false;$a=Get-LifecycleProperty $Previous 'progress' ([ref]$found);$found=$false;$b=Get-LifecycleProperty $Current 'progress' ([ref]$found)
    if(-not $a -or -not $b){return $false}
    $currentMarkersFound=$false;$currentMarkers=@(Get-LifecycleProperty $b 'guestProgressMarkers' ([ref]$currentMarkersFound));$previousMarkersFound=$false;$previousMarkers=@(Get-LifecycleProperty $a 'guestProgressMarkers' ([ref]$previousMarkersFound))
    if($currentMarkersFound){foreach($record in $currentMarkers){$instanceFound=$false;$instance=[string](Get-LifecycleProperty $record 'instanceName' ([ref]$instanceFound));$markerRecordFound=$false;$currentRoleMarker=Get-LifecycleProperty $record 'marker' ([ref]$markerRecordFound);if(-not $instanceFound -or -not $markerRecordFound -or -not $currentRoleMarker){continue};$previousRoleMarker=$null;if($previousMarkersFound){$priorRecord=@($previousMarkers|Where-Object{$priorNameFound=$false;$priorName=[string](Get-LifecycleProperty $_ 'instanceName' ([ref]$priorNameFound));$priorNameFound -and $priorName -ceq $instance}|Select-Object -First 1);if($priorRecord){$priorMarkerFound=$false;$previousRoleMarker=Get-LifecycleProperty $priorRecord[0] 'marker' ([ref]$priorMarkerFound);if(-not $priorMarkerFound){$previousRoleMarker=$null}}};if(Test-GuestProgressMarkerTransition -Previous $previousRoleMarker -Current $currentRoleMarker -TransactionId $TransactionId -PayloadSha256 $PayloadSha256){return $true}}}
    $markerFound=$false;$currentMarker=Get-LifecycleProperty $b 'guestProgressMarker' ([ref]$markerFound);$previousMarkerFound=$false;$previousMarker=Get-LifecycleProperty $a 'guestProgressMarker' ([ref]$previousMarkerFound)
    if($markerFound -and $currentMarker -and (Test-GuestProgressMarkerTransition -Previous $(if($previousMarkerFound){$previousMarker}else{$null}) -Current $currentMarker -TransactionId $TransactionId -PayloadSha256 $PayloadSha256)){return $true}
    foreach($name in @('checkpointGeneration','checkpointState','resumeStage','activeTransactionSha256','stageMarkerSet','installStateSha256','ownershipSha256','receiptMatch','health')){$afound=$false;$av=Get-LifecycleProperty $a $name ([ref]$afound);$bfound=$false;$bv=Get-LifecycleProperty $b $name ([ref]$bfound);if([string]$av-cne[string]$bv){return $true}}
    $afound=$false;$ac=Get-LifecycleProperty $a 'completedStages' ([ref]$afound);if(-not $afound){$ac=@()};$bfound=$false;$bc=Get-LifecycleProperty $b 'completedStages' ([ref]$bfound);if(-not $bfound){$bc=@()};return (($ac|ConvertTo-Json -Compress -Depth 8)-cne($bc|ConvertTo-Json -Compress -Depth 8))
}

function Test-ProductActivity {
    param([AllowNull()][psobject]$Previous,[Parameter(Mandatory)][psobject]$Current)
    if(-not $Previous){return $false};$a=$Previous.progress;$b=$Current.progress;if(-not $a -or -not $b){return $false}
    foreach($name in @('productChildInstances','cpuSeconds','candidateProcessPresent','candidateResponsive','stages')){$af=$false;$av=Get-LifecycleProperty $a $name ([ref]$af);$bf=$false;$bv=Get-LifecycleProperty $b $name ([ref]$bf);if(($av|ConvertTo-Json -Compress -Depth 12)-cne($bv|ConvertTo-Json -Compress -Depth 12)){return $true}}
    return $false
}

function ConvertTo-NormalizedLifecycleObservation {
    <# Providers and remote calls are untrusted boundaries.  Always return a
       complete shape so strict mode cannot turn a timeout or stale provider
       payload into an unrecorded exception. #>
    param([AllowNull()][object]$Observation,[string]$Failure='')
    $now=(Get-Date).ToUniversalTime().ToString('o')
     $progress=[ordered]@{checkpointState='';completedStages=@();resumeStage='';stages=@();productChildInstances=@();cpuSeconds=0.0;candidateProcessPresent=$false;candidateResponsive=$false;activeTransactionSha256=$null;stageMarkerSet='';servicingState='';installStateSha256=$null;ownershipSha256=$null;receiptMatch=$false;health=$false;hostAgentTaskState='';listener=$false;guestProgressMarker=$null;guestProgressMarkers=@();guestProgressMarkerOutcomes=@();guestProgressMarkerStatus='';guestProgressMarkerError=''}
    $normalized=[ordered]@{status='';checkpointPresent=$false;checkpoint=$null;checkpointReadRaceRecovered=$false;receipt=$null;matchingConsumedReceipt=$false;installStateValid=$false;installLedger=$null;installStateError='';canonicalOwnershipValid=$false;ownershipLedger=$null;ownershipStateError='';authenticatedHealthOk=$false;authenticatedHealthError='';productRoleIdentityValid=$null;terminalFailure=$false;failure='';error='';terminalReason='';observerCallTimedOut=$false;observerCallFailed=$false;candidateProcessExited=$false;candidateProcess=$null;processTree=@();bootstrap=@();activeTransaction=$null;stageMarkers=@();stageMarkerErrors=@();servicing=$null;hostAgentTaskState='ABSENT';hostAgentListener=$false;progress=$progress;progressMarker='';rawActiveLifecycleSignals=@();rawActiveLifecycleSignalCount=0;timestampUtc=$now}
    $normalized.failureLogSnapshot=$null
    $normalized.authenticatedHealthEvidence=$null
    if($Observation -is [array]){if($Observation.Count -eq 1){$Observation=$Observation[0]}else{$Failure=if($Failure){$Failure}else{'observation provider returned an ambiguous result set'}}}
    # Force array context around the conditional itself. PowerShell otherwise
    # unwraps a one-item result, which breaks strict-mode evidence handling.
    $rawSignals=@(if($Observation){Get-RawActiveLifecycleSignals -Value $Observation}else{@()});$normalized.rawActiveLifecycleSignals=$rawSignals;$normalized.rawActiveLifecycleSignalCount=$rawSignals.Count
    if($Observation){if($Observation -is [System.Collections.IDictionary]){foreach($key in $Observation.Keys){if($normalized.Contains([string]$key)){$normalized[[string]$key]=$Observation[$key]}}}else{foreach($property in $Observation.PSObject.Properties){if($normalized.Contains($property.Name)){$normalized[$property.Name]=$property.Value}}}}elseif(-not $Failure){$Failure='observation provider returned no result'}
    if($Failure){$normalized.terminalFailure=$true;$normalized.status='TERMINAL_FAILURE';$normalized.failure=$Failure;$normalized.error=$Failure;$normalized.terminalReason=$Failure}
    $explicitFailure=[string]$normalized.failure
    $explicitTerminalClaim=([bool]$normalized.terminalFailure -or -not [string]::IsNullOrWhiteSpace($explicitFailure) -or -not [string]::IsNullOrWhiteSpace([string]$normalized.error) -or [string]$normalized.status -match '^(?i:TERMINAL_FAILURE|TERMINAL|ERROR)$')
    $unsafeSignal=$rawSignals|Where-Object{($_.kind -eq 'generation' -and [string]$_.path -notmatch '^checkpoint\.') -or ($_.kind -eq 'checkpointgeneration' -and -not (Test-BenignLifecycleCheckpointGenerationSignal $_) -and [string]$_.path -notmatch '^(progress|checkpoint)\.') -or ($_.kind -eq 'checkpoint' -and [string]$_.path -notmatch '^checkpoint$') -or [string]$_.path -match '(^|\.)observation\.' -or ($_.kind -eq 'waiting-for-reboot' -and [string]$_.path -notmatch '^checkpoint\.state$') -or $_.kind -in @('depth-cutoff','cycle') -or ((-not $explicitTerminalClaim) -and $_.kind -in @('terminalFailure','failure','error','terminalReason','terminal-status'))}|Select-Object -First 1
    if($unsafeSignal){$normalized.terminalFailure=$true;$normalized.status='TERMINAL_FAILURE';if([string]::IsNullOrWhiteSpace($explicitFailure)){$normalized.failure="unsafe lifecycle signal at $([string]$unsafeSignal.path)"};$normalized.error=$normalized.failure;$normalized.terminalReason=$normalized.failure}
    if([string]::IsNullOrWhiteSpace([string]$normalized.timestampUtc)){$normalized.timestampUtc=$now}
    if(-not $normalized.progress){$normalized.progress=$progress}
    foreach($property in $progress.Keys){if(-not (Test-LifecycleProperty -Value $normalized.progress -Name $property)){if($normalized.progress -is [System.Collections.IDictionary]){$normalized.progress[$property]=$progress[$property]}else{$normalized.progress|Add-Member -NotePropertyName $property -NotePropertyValue $progress[$property]}}}
    $actualCheckpointPresent=($null -ne $normalized.checkpoint);$flaggedCheckpointPresent=[bool]$normalized.checkpointPresent
    if($flaggedCheckpointPresent -ne $actualCheckpointPresent){$normalized.terminalFailure=$true;$normalized.failure='checkpoint presence flag disagrees with checkpoint object';$normalized.error=$normalized.failure}
    $normalized.checkpointPresent=$actualCheckpointPresent
    if($actualCheckpointPresent){
        if(-not $normalized.checkpoint){$normalized.terminalFailure=$true;$normalized.failure='checkpointPresent was asserted without a checkpoint payload';$normalized.error=$normalized.failure}
        else {$canonicalCheckpoint=ConvertTo-CanonicalLifecycleCheckpoint $normalized.checkpoint;if(-not $canonicalCheckpoint){$normalized.terminalFailure=$true;$normalized.failure='checkpoint generation is missing, malformed, or inconsistent';$normalized.error=$normalized.failure}else{$normalized.checkpoint=$canonicalCheckpoint}}
    }
    if([bool]$normalized.terminalFailure){if([string]::IsNullOrWhiteSpace([string]$normalized.failure)){$normalized.failure='normalized lifecycle observation reported terminal failure'};$normalized.status='TERMINAL_FAILURE';if([string]::IsNullOrWhiteSpace([string]$normalized.error)){$normalized.error=$normalized.failure};if([string]::IsNullOrWhiteSpace([string]$normalized.terminalReason)){$normalized.terminalReason=$normalized.failure}}
    if([string]::IsNullOrWhiteSpace([string]$normalized.progressMarker)){$normalized.progressMarker=($normalized.progress|ConvertTo-Json -Compress -Depth 16)}
    return [pscustomobject]$normalized
}

function Wait-DevFleetProductLifecycleTransition {
    <#
      One bounded observer for the product-owned durable lifecycle.  It never
      writes a checkpoint and never treats a merely existing process/file as
      progress.  The caller owns the reboot operation after NEXT_REBOOT.
    #>
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TransactionId,
        [Parameter(Mandatory)][string]$PayloadSha256,
        [Parameter(Mandatory)][string]$Role,
        [string]$Action = 'FreshInstall',
        [int]$PriorGeneration = 0,
        [int]$MaxGeneration = 3,
        [int]$BudgetSeconds = 1800,
        [int]$PollSeconds = 5,
        [int]$CandidateProcessId = 0,
        [string]$EvidencePath,
        [scriptblock]$ObservationProvider,
        [scriptblock]$ClockProvider,
        [scriptblock]$SleepProvider,
        [double]$CpuDeltaThreshold=1.0,
        [int]$NoProgressBudgetSeconds=0,
        [int]$AbsoluteBudgetSeconds=0,
        [string]$ExpectedDevFleetVersion,
        [string]$ExpectedInstallerVersion,
        [int]$ObservationTimeoutSeconds=0,
        [string]$InvocationStartUtc,
        [string]$AbsoluteDeadlineUtc,
        [string]$ExpectedComputeInstanceName,
        [string]$ExpectedVaultInstanceName,
        [string]$ExpectedNestedLinuxName,
        [object]$ObservationProviderContext,
        [scriptblock]$SessionProvider,
        [scriptblock]$RemoteObservationProvider,
        [scriptblock]$GuestMarkerReadProvider,
        [object]$ObservationAdapterContext
    )
    if($BudgetSeconds -le 0){throw 'Lifecycle budget must be finite and positive.'}
    if([string]::IsNullOrWhiteSpace($ExpectedDevFleetVersion)-or$ExpectedDevFleetVersion -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$'){throw 'TERMINAL_FAILURE: expected DevFleet version is missing or malformed.'}
    if([string]::IsNullOrWhiteSpace($ExpectedInstallerVersion)-or$ExpectedInstallerVersion -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$'){throw 'TERMINAL_FAILURE: expected installer version is missing or malformed.'}
    $noProgressBudget=if($NoProgressBudgetSeconds -gt 0){[int]$NoProgressBudgetSeconds}else{[int]$BudgetSeconds}
    $absoluteBudget=if($AbsoluteBudgetSeconds -gt 0){[int]$AbsoluteBudgetSeconds}else{[int]$BudgetSeconds}
    if($noProgressBudget -le 0 -or $absoluteBudget -le 0){throw 'Lifecycle no-progress and absolute budgets must be finite and positive.'}
    $NoProgressBudgetSeconds=$noProgressBudget;$AbsoluteBudgetSeconds=$absoluteBudget
    if($ObservationTimeoutSeconds -le 0){$ObservationTimeoutSeconds=[Math]::Min([Math]::Max($PollSeconds+2,5),60)}else{$ObservationTimeoutSeconds=[Math]::Min([Math]::Max($ObservationTimeoutSeconds,2),60)}
    $now={if($ClockProvider){&$ClockProvider}else{Get-Date}}
    $utcNow={ConvertTo-WpfUtcInstant (&$now)}
    $sleep={param($seconds)if($SleepProvider){&$SleepProvider $seconds}else{Start-Sleep -Seconds $seconds}}
    $start=&$utcNow;if(-not $InvocationStartUtc){$InvocationStartUtc=$start.ToString('o')};$inheritedDeadlineText=[string]$AbsoluteDeadlineUtc;$requestedAbsoluteDeadline=$start.AddSeconds($AbsoluteBudgetSeconds);$absoluteDeadline=$requestedAbsoluteDeadline
    if($inheritedDeadlineText){$inheritedDeadline=ConvertTo-WpfUtcInstant $inheritedDeadlineText;if($inheritedDeadline -lt $absoluteDeadline){$absoluteDeadline=$inheritedDeadline}}
    $effectiveAbsoluteBudgetSeconds=[Math]::Max(0,[int][Math]::Floor(($absoluteDeadline-$start).TotalSeconds));$noProgressDeadline=$start.AddSeconds($NoProgressBudgetSeconds)
    $lastProgressAt=$start;$previous=$null
    $lastObserved = $null;$providerIndex=0
    $progressSamples = [System.Collections.Generic.List[object]]::new()
    # A Hyper-V/PowerShell transport can terminate independently of the
    # product transaction.  Recover only this narrowly identified transport
    # class, with a finite retry count and a delay charged to both immutable
    # deadlines.  Semantic product failures and arbitrary provider errors
    # remain fail-closed on the first observation.
    $transportRecoveryAttempts = [System.Collections.Generic.List[object]]::new()
    $transportRecoveryLimit = 3
    $transportRecoveryDelaySeconds = 5
    $isRecoverableTransportError = {
        param([string]$Message)
        if($Message -match '(?i)LAB_CREDENTIAL_STALE|credential|logon|authentication|access is denied'){return $false}
        return $Message -match '(?i)Hyper-V socket target process has ended|background process reported an error with the following message|An error has occurred which PowerShell cannot handle\.\s*A remote session might have ended\.'
    }
    # WinRM sessions can become broken during a legitimately long product
    # transaction.  A broken observer transport is not a product result and
    # must not terminate the lifecycle while the candidate is still within its
    # immutable absolute deadline.  The caller may provide an authenticated,
    # exact-VM session factory; those short-lived sessions are disposed after
    # each observation so a stale transport cannot poison the whole lifecycle.
    $observeSession = $Session
    $getRemoteObservation = {
        $sessionForObservation = $observeSession
        $created = $false
        try {
            if ($SessionProvider) { $sessionForObservation = & $SessionProvider; $created = $true }
            return Get-ProductLifecycleObservation -Session $sessionForObservation -TransactionId $TransactionId -PayloadSha256 $PayloadSha256 -Action $Action -Role $Role -PriorGeneration $PriorGeneration -MaxGeneration $MaxGeneration -CandidateProcessId $CandidateProcessId -ExpectedDevFleetVersion $ExpectedDevFleetVersion -ExpectedInstallerVersion $ExpectedInstallerVersion -ObservationTimeoutSeconds $ObservationTimeoutSeconds -InvocationStartUtc $InvocationStartUtc -ExpectedComputeInstanceName $ExpectedComputeInstanceName -ExpectedVaultInstanceName $ExpectedVaultInstanceName -ExpectedNestedLinuxName $ExpectedNestedLinuxName -RemoteObservationProvider $RemoteObservationProvider -GuestMarkerReadProvider $GuestMarkerReadProvider -ObservationAdapterContext $ObservationAdapterContext
        } finally {
            if ($created -and $sessionForObservation) { Remove-DevFleetGuestSession $sessionForObservation -ErrorAction SilentlyContinue }
        }
    }
    $journalPath=if($EvidencePath){Join-Path (Split-Path -Parent $EvidencePath) 'product-lifecycle-progress.jsonl'}else{$null}
    $currentPath=if($EvidencePath){Join-Path (Split-Path -Parent $EvidencePath) 'product-lifecycle-progress-current.json'}else{$null}
    if($journalPath){
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $journalPath)|Out-Null
        $initialEntry=[ordered]@{event='START';startUtc=$start.ToUniversalTime().ToString('o');lastMeaningfulProgressUtc=$start.ToUniversalTime().ToString('o');noMeaningfulProgressDeadlineUtc=$noProgressDeadline.ToUniversalTime().ToString('o');absoluteLifecycleDeadlineUtc=$absoluteDeadline.ToUniversalTime().ToString('o');requestedBudgetSeconds=[int]$BudgetSeconds;effectiveNoProgressBudgetSeconds=[int]$NoProgressBudgetSeconds;effectiveAbsoluteBudgetSeconds=$effectiveAbsoluteBudgetSeconds;candidateProcessId=$CandidateProcessId;transactionId=$TransactionId;payloadSha256=$PayloadSha256;action=$Action;role=$Role;observationTimeoutSeconds=$ObservationTimeoutSeconds}
        Add-Content -LiteralPath $journalPath -Value (($initialEntry|ConvertTo-Json -Compress -Depth 12)) -Encoding UTF8;Write-EvidenceJson -Path $currentPath -Value $initialEntry
    }
    $writeSample={param($sample,$event)
        $entry=[ordered]@{event=$event;observedUtc=[string]$sample.timestampUtc;startUtc=$start.ToUniversalTime().ToString('o');lastMeaningfulProgressUtc=$lastProgressAt.ToUniversalTime().ToString('o');noMeaningfulProgressDeadlineUtc=$noProgressDeadline.ToUniversalTime().ToString('o');absoluteLifecycleDeadlineUtc=$absoluteDeadline.ToUniversalTime().ToString('o');requestedBudgetSeconds=[int]$BudgetSeconds;effectiveNoProgressBudgetSeconds=[int]$NoProgressBudgetSeconds;effectiveAbsoluteBudgetSeconds=$effectiveAbsoluteBudgetSeconds;candidateProcessId=$CandidateProcessId;transactionId=$TransactionId;payloadSha256=$PayloadSha256;action=$Action;role=$Role;observation=$sample}
        if($journalPath){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $journalPath)|Out-Null;Add-Content -LiteralPath $journalPath -Value (($entry|ConvertTo-Json -Compress -Depth 24)) -Encoding UTF8
            # Keep interruption evidence bounded while retaining the most
            # recent semantic transitions and heartbeats.
            $journalLines=@(Get-Content -LiteralPath $journalPath -ErrorAction SilentlyContinue);if($journalLines.Count -gt 512){@($journalLines[0])+@($journalLines | Select-Object -Last 511) | Set-Content -LiteralPath $journalPath -Encoding UTF8}
            Write-EvidenceJson -Path $currentPath -Value $entry}
    }
    function Complete-ObserverResult([object]$Result) {
        $Result.progressSamples=@($progressSamples);$Result.progressSampleCount=$progressSamples.Count
        $Result.requestedBudgetSeconds=[int]$BudgetSeconds;$Result.effectiveNoProgressBudgetSeconds=[int]$NoProgressBudgetSeconds;$Result.effectiveAbsoluteBudgetSeconds=$effectiveAbsoluteBudgetSeconds;$Result.inheritedAbsoluteDeadlineUtc=$inheritedDeadlineText;$Result.budgetSeconds=[int]$NoProgressBudgetSeconds
        $Result.transportRecoveryAttempts=@($transportRecoveryAttempts)
        $Result.startUtc=$start.ToUniversalTime().ToString('o');$Result.lastMeaningfulProgressUtc=$lastProgressAt.ToUniversalTime().ToString('o');$Result.noMeaningfulProgressDeadlineUtc=$noProgressDeadline.ToUniversalTime().ToString('o');$Result.absoluteLifecycleDeadlineUtc=$absoluteDeadline.ToUniversalTime().ToString('o')
        if($EvidencePath){
            # The terminal record is journaled after the final observation so
            # an interrupted/failed provider leaves one unambiguous last event
            # in addition to the terminal result and current snapshot.
            $resultReasonFound=$false;$resultReason=Get-LifecycleProperty $Result 'terminalReason' ([ref]$resultReasonFound);$terminalEntry=[ordered]@{event='TERMINAL';terminalReason=[string]$Result.outcome;terminalDetail=[string]$resultReason;startUtc=$Result.startUtc;lastMeaningfulProgressUtc=$lastProgressAt.ToUniversalTime().ToString('o');noMeaningfulProgressDeadlineUtc=$noProgressDeadline.ToUniversalTime().ToString('o');absoluteLifecycleDeadlineUtc=$absoluteDeadline.ToUniversalTime().ToString('o');requestedBudgetSeconds=$Result.requestedBudgetSeconds;effectiveNoProgressBudgetSeconds=$Result.effectiveNoProgressBudgetSeconds;effectiveAbsoluteBudgetSeconds=$Result.effectiveAbsoluteBudgetSeconds;transactionId=$TransactionId;payloadSha256=$PayloadSha256;action=$Action;role=$Role}
            if($journalPath){Add-Content -LiteralPath $journalPath -Value (($terminalEntry|ConvertTo-Json -Compress -Depth 24)) -Encoding UTF8;$journalLines=@(Get-Content -LiteralPath $journalPath -ErrorAction SilentlyContinue);if($journalLines.Count -gt 512){@($journalLines[0])+@($journalLines | Select-Object -Last 511) | Set-Content -LiteralPath $journalPath -Encoding UTF8}}
            Write-EvidenceJson -Path $EvidencePath -Value $Result; if($currentPath){Write-EvidenceJson -Path $currentPath -Value $terminalEntry}
        }
        return $Result
    }
    do {
        if((&$utcNow) -ge $absoluteDeadline){return Complete-ObserverResult ([ordered]@{outcome='ABSOLUTE_TIMEOUT';terminalReason='absolute deadline reached before next observation';observation=$lastObserved})}
        $observation=$null;$transportFailure='';$recovered=$false
        for($transportAttempt=0;$transportAttempt -le $transportRecoveryLimit;$transportAttempt++){
            $transportFailure='';$observation=$null
            try {
                if($ObservationProvider){
                    if(-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)){throw 'no bounded ObservationProvider execution primitive is available'}
                    $providerState=[pscustomobject]@{transactionId=$TransactionId;payloadSha256=$PayloadSha256;action=$Action;role=$Role;priorGeneration=$PriorGeneration;maxGeneration=$MaxGeneration;candidateProcessId=$CandidateProcessId;invocationStartUtc=$InvocationStartUtc;observationIndex=$providerIndex;providerContext=$ObservationProviderContext}
                    $providerIndex++
                    $providerJob=Start-ThreadJob -ScriptBlock {param($provider,$state)&$provider $state} -ArgumentList $ObservationProvider,$providerState
                    if(-not (Wait-Job -Job $providerJob -Timeout $ObservationTimeoutSeconds)){
                        Stop-Job -Job $providerJob -ErrorAction SilentlyContinue;Wait-Job -Job $providerJob -Timeout 2 -ErrorAction SilentlyContinue|Out-Null;Remove-Job -Job $providerJob -Force -ErrorAction SilentlyContinue
                        $observation=ConvertTo-NormalizedLifecycleObservation $null 'observer provider timeout';$observation|Add-Member -NotePropertyName observerCallTimedOut -NotePropertyValue $true -Force
                    }else{
                        try{$observation=Receive-Job -Job $providerJob -ErrorAction Stop}catch{$transportFailure=$_.Exception.Message}finally{Remove-Job -Job $providerJob -Force -ErrorAction SilentlyContinue}
                    }
                }else{$observation=&$getRemoteObservation}
            }catch{$transportFailure=$_.Exception.Message}
            $providerFailedFound=$false;$providerFailed=if($observation){Get-LifecycleProperty $observation 'observerCallFailed' ([ref]$providerFailedFound)}else{$null}
            if(-not $transportFailure -and $observation -and $providerFailedFound -and [bool]$providerFailed){$failureFound=$false;$transportFailure=[string](Get-LifecycleProperty $observation 'failure' ([ref]$failureFound));if([string]::IsNullOrWhiteSpace($transportFailure)){$errorFound=$false;$transportFailure=[string](Get-LifecycleProperty $observation 'error' ([ref]$errorFound))}}
            if(-not $transportFailure){$recovered=$true;break}
            if(-not (&$isRecoverableTransportError $transportFailure) -or $transportAttempt -ge $transportRecoveryLimit){break}
            $recoveryNow=&$utcNow;$remainingAbsolute=($absoluteDeadline-$recoveryNow).TotalSeconds;$remainingNoProgress=($noProgressDeadline-$recoveryNow).TotalSeconds;$remainingRecovery=[math]::Min($remainingAbsolute,$remainingNoProgress)
            if($remainingRecovery -le 0){break}
            $delay=[int][math]::Min($transportRecoveryDelaySeconds,[math]::Floor($remainingRecovery));if($delay -le 0){break}
            [void]$transportRecoveryAttempts.Add([ordered]@{attempt=$transportAttempt+1;error=$transportFailure;delaySeconds=$delay;observedUtc=$recoveryNow.ToUniversalTime().ToString('o')})
            &$sleep $delay
        }
        if($transportFailure -and -not $recovered){$observation=ConvertTo-NormalizedLifecycleObservation $null ('observer call failed: '+$transportFailure);$observation|Add-Member -NotePropertyName observerCallFailed -NotePropertyValue $true -Force}
        $observation=ConvertTo-NormalizedLifecycleObservation $observation
        # A provider may return just as the immutable lifecycle deadline is
        # reached. Do not accept its semantic progress or terminal decision;
        # preserve the observation and fail closed as ABSOLUTE_TIMEOUT.
        if((&$utcNow) -ge $absoluteDeadline){return Complete-ObserverResult ([ordered]@{outcome='ABSOLUTE_TIMEOUT';terminalReason='absolute deadline reached after observation';observation=$observation})}
        $lastObserved=$observation
        [void]$progressSamples.Add($observation)
        if($progressSamples.Count -gt 512){$progressSamples.RemoveAt(0)}
        $checkpoint=$observation.checkpoint
        # The transaction identifier is deliberately unknown before the first
        # product-owned checkpoint, consumed receipt, or current stage marker
        # exists.  Adopt it only from an observation that is already bound to
        # the exact payload, action, role, invocation time, and bounded
        # generation.  This lets the full progress observer run from
        # generation zero instead of waiting blindly for a checkpoint while
        # the real installer child executes.
        if($PriorGeneration -eq 0 -and [string]::IsNullOrWhiteSpace($TransactionId)){
            $observedTransaction=''
            if($checkpoint){
                $checkpointTxFound=$false;$checkpointTx=Get-LifecycleProperty $checkpoint 'transactionId' ([ref]$checkpointTxFound)
                $checkpointPayloadFound=$false;$checkpointPayload=Get-LifecycleProperty $checkpoint 'payloadSha256' ([ref]$checkpointPayloadFound)
                $checkpointActionFound=$false;$checkpointAction=Get-LifecycleProperty $checkpoint 'action' ([ref]$checkpointActionFound)
                $checkpointRoleFound=$false;$checkpointRole=Get-LifecycleProperty $checkpoint 'role' ([ref]$checkpointRoleFound)
                if($checkpointTxFound -and $checkpointPayloadFound -and $checkpointActionFound -and $checkpointRoleFound -and
                    [string]$checkpointPayload -ceq $PayloadSha256 -and [string]$checkpointAction -ceq $Action -and [string]$checkpointRole -ceq $Role){
                    $observedTransaction=[string]$checkpointTx
                }
            }elseif($observation.matchingConsumedReceipt -and $observation.receipt){
                $receiptTxFound=$false;$receiptTx=Get-LifecycleProperty $observation.receipt 'transactionId' ([ref]$receiptTxFound)
                if($receiptTxFound){$observedTransaction=[string]$receiptTx}
            }
            if(-not $observedTransaction -and -not $checkpoint){
                # Get-ProductLifecycleObservation already rejects stale,
                # malformed, foreign, and non-allowlisted markers. Recheck
                # the binding at this trust boundary because injected/adapted
                # observations use the same wait loop.
                $stageMarkersFound=$false
                $stageMarkersValue=Get-LifecycleProperty $observation 'stageMarkers' ([ref]$stageMarkersFound)
                $expectedStageRole=Get-DevFleetLifecycleRoleKind -Role $Role
                $invocationStart=[datetime]::MinValue
                $invocationStartValid=[datetime]::TryParse([string]$InvocationStartUtc,[ref]$invocationStart)
                $stageTransactions=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
                if($stageMarkersFound -and $null -ne $stageMarkersValue -and $invocationStartValid){
                    foreach($marker in @($stageMarkersValue)){
                        $markerNameFound=$false;$markerName=[string](Get-LifecycleProperty $marker 'name' ([ref]$markerNameFound))
                        $markerTxFound=$false;$markerTx=[string](Get-LifecycleProperty $marker 'transactionId' ([ref]$markerTxFound))
                        $markerPayloadFound=$false;$markerPayload=[string](Get-LifecycleProperty $marker 'payloadSha256' ([ref]$markerPayloadFound))
                        $markerActionFound=$false;$markerAction=[string](Get-LifecycleProperty $marker 'action' ([ref]$markerActionFound))
                        $markerRoleFound=$false;$markerRole=[string](Get-LifecycleProperty $marker 'role' ([ref]$markerRoleFound))
                        $markerCompletedFound=$false;$markerCompletedText=[string](Get-LifecycleProperty $marker 'completedUtc' ([ref]$markerCompletedFound));$markerCompleted=[datetime]::MinValue
                        $markerFresh=($markerCompletedFound -and [datetime]::TryParse($markerCompletedText,[ref]$markerCompleted) -and $markerCompleted.ToUniversalTime() -ge $invocationStart.ToUniversalTime())
                        if($markerNameFound -and (Test-DevFleetLifecycleStageMarkerName -Name $markerName -ExpectedComputeInstanceName $ExpectedComputeInstanceName -ExpectedVaultInstanceName $ExpectedVaultInstanceName) -and
                            $markerTxFound -and $markerTx -match '^[0-9a-fA-F]{32}$' -and $markerPayloadFound -and $markerPayload -ceq $PayloadSha256 -and
                            $markerActionFound -and $markerAction -ceq $Action -and $markerRoleFound -and $markerRole -ceq $expectedStageRole -and $markerFresh){
                            if(-not $stageTransactions.ContainsKey($markerTx)){$stageTransactions[$markerTx]=$markerTx}
                        }
                    }
                }
                if($stageTransactions.Count -eq 1){$observedTransaction=@($stageTransactions.Values)[0]}
                elseif($stageTransactions.Count -gt 1){$observation.terminalFailure=$true;$observation.failure='multiple current candidate-bound stage-marker transaction identities';$observation.error=$observation.failure}
            }
            if($observedTransaction){
                if($observedTransaction -notmatch '^[0-9a-fA-F]{32}$'){
                    $observation.terminalFailure=$true;$observation.failure='observed lifecycle transaction identity is malformed';$observation.error=$observation.failure
                }else{$TransactionId=$observedTransaction}
            }
        }
        $prior = [pscustomobject]@{checkpointGeneration=$PriorGeneration;transactionId=$TransactionId;payloadSha256=$PayloadSha256;action=$Action;role=$Role;state='waiting-for-reboot'}
        $observationTerminalFound=$false;$observationTerminal=Get-LifecycleProperty $observation 'terminalFailure' ([ref]$observationTerminalFound);$classification=if($observationTerminalFound -and [bool]$observationTerminal){'TERMINAL_FAILURE'}else{Get-DurableProgressClassification -Observation $observation -PriorCheckpoint $prior -MaxGeneration $MaxGeneration}
         $semanticProgress=Test-ProductMeaningfulProgress -Previous $previous -Current $observation -CpuDeltaThreshold $CpuDeltaThreshold -TransactionId $TransactionId -PayloadSha256 $PayloadSha256
         if($semanticProgress){$lastProgressAt=&$utcNow;$noProgressDeadline=$lastProgressAt.AddSeconds($NoProgressBudgetSeconds);$event='SEMANTIC_PROGRESS'}elseif(Test-ProductActivity -Previous $previous -Current $observation){$event='ACTIVITY'}else{$event='HEARTBEAT'}
        &$writeSample $observation $event;$previous=$observation
        if($classification -eq 'COMPLETED'){$completionReason='';if(-not (Test-LifecycleCompletionInput -Value $observation -Reason ([ref]$completionReason))){$classification='TERMINAL_FAILURE';$observation.terminalFailure=$true;$observation.failure="COMPLETED observation rejected: $completionReason";$observation.error=$observation.failure;$observation.terminalReason=$observation.failure;$observation.status='TERMINAL_FAILURE'}}
        if($classification -eq 'TERMINAL_FAILURE'){ return Complete-ObserverResult ([ordered]@{outcome='TERMINAL_FAILURE';observation=$observation;terminalReason=$observation.failure}) }
        if($classification -eq 'NEXT_REBOOT'){ return Complete-ObserverResult ([ordered]@{outcome='NEXT_REBOOT';checkpointPresent=$true;observation=$observation;checkpoint=$checkpoint}) }
        if($classification -eq 'COMPLETED'){ return Complete-ObserverResult ([ordered]@{outcome='COMPLETED';observation=$observation}) }
        &$sleep $PollSeconds
    } while((&$utcNow) -lt $noProgressDeadline -and (&$utcNow) -lt $absoluteDeadline)
    # Machine-readable terminal vocabulary: outcome='NO_PROGRESS_TIMEOUT' or
    # outcome='ABSOLUTE_TIMEOUT' (the proof runner's outer outcome is
    # outcome='HARNESS_WATCHDOG_EXPIRED').
    $terminal=if((&$utcNow) -ge $absoluteDeadline){'ABSOLUTE_TIMEOUT'}else{'NO_PROGRESS_TIMEOUT'} # outcome='ABSOLUTE_TIMEOUT'
    $result=[ordered]@{outcome=$terminal;observation=$lastObserved;requestedBudgetSeconds=[int]$BudgetSeconds;effectiveNoProgressBudgetSeconds=[int]$NoProgressBudgetSeconds;effectiveAbsoluteBudgetSeconds=[int]$AbsoluteBudgetSeconds;budgetSeconds=[int]$NoProgressBudgetSeconds;progressSamples=@($progressSamples);progressSampleCount=$progressSamples.Count;terminalReason=$terminal}
    # Preserve causal evidence even when a still-open WPF window emits no
    # terminal product flag. This is one diagnostic collection, not progress
    # or proof credit; it cannot move either recorded lifecycle deadline.
    if($terminal -eq 'NO_PROGRESS_TIMEOUT' -and -not $ObservationProvider -and -not $RemoteObservationProvider -and $lastObserved){
        $captureSeconds=[math]::Min(20,[math]::Floor(($absoluteDeadline-(&$utcNow)).TotalSeconds)-1)
        if($captureSeconds -gt 0){
            $snapshot=Get-ProductFailureLogSnapshot -Session $observeSession -TransactionId $TransactionId -PayloadSha256 $PayloadSha256 -InvocationStartUtc $InvocationStartUtc -TimeoutSeconds $captureSeconds
            if($lastObserved -is [System.Collections.IDictionary]){$lastObserved['failureLogSnapshot']=$snapshot}else{$lastObserved|Add-Member -NotePropertyName failureLogSnapshot -NotePropertyValue $snapshot -Force}
        }
    }
    return Complete-ObserverResult $result
}

function Get-PhaseAwareBudgetSeconds {
    param([psobject]$Context,[int]$DefaultSeconds = 0)
    $configFound=$false;$config=Get-LifecycleProperty $Context 'config' ([ref]$configFound)
    $policy=Get-HarnessBudgetPolicy -Config $(if($configFound){$config}else{$null})
    $roleFound=$false;$role=Get-LifecycleProperty $Context 'role' ([ref]$roleFound)
    if(-not $roleFound){$role='Primary / Desktop'}
    if([string]$role -match '(?i)Laptop'){return [int]$policy.transactionBudgetsSeconds.Laptop}
    return [int]$policy.transactionBudgetsSeconds.Desktop
}

function ConvertTo-ProductServicingSample {
    param([AllowNull()][object]$Sample)
    if($null -eq $Sample){return $null}
    $values=[ordered]@{}
    foreach($name in @('cbs','windowsUpdate','pendingCount')){
        $found=$false;$value=Get-LifecycleProperty -Value $Sample -Name $name -Found ([ref]$found)
        if(-not $found){return $null}
        $values[$name]=$value
    }
    $pendingCount=0
    if(-not [int]::TryParse([string]$values.pendingCount,[ref]$pendingCount) -or $pendingCount -lt 0){return $null}
    return [pscustomobject][ordered]@{cbs=[bool]$values.cbs;windowsUpdate=[bool]$values.windowsUpdate;pendingCount=$pendingCount}
}

function Test-ProductServicingSamplesMatch {
    param([AllowNull()][object]$First,[AllowNull()][object]$Second)
    $left=ConvertTo-ProductServicingSample $First
    $right=ConvertTo-ProductServicingSample $Second
    if($null -eq $left -or $null -eq $right){return $false}
    return ($left.cbs -eq $right.cbs -and $left.windowsUpdate -eq $right.windowsUpdate -and $left.pendingCount -eq $right.pendingCount)
}

function Get-ExactProductCheckpoint {
    param([Parameter(Mandatory)][guid]$VmId,[string]$TransactionId,[Parameter(Mandatory)][string]$PayloadSha256,[Parameter(Mandatory)][string]$Action,[Parameter(Mandatory)][string]$Role,[int]$MinimumGeneration=1,[int]$MaxGeneration=3,[string]$InvocationStartUtc)
    $session=$null
    try {
        $session=Connect-DevFleetGuest -VmId $VmId
        return Invoke-Command -Session $session -ScriptBlock {
            param($tx,$payload,$expectedAction,$expectedRole,$min,$max,$invocationStart)
            $path='C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-checkpoint.json'
            if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
            $value=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
            if($invocationStart){$created=[datetime]::MinValue;if(-not [datetime]::TryParse([string]$value.createdUtc,[ref]$created)){throw 'Product checkpoint lacks createdUtc provenance.'};if($created.ToUniversalTime() -lt ([datetime]$invocationStart).ToUniversalTime()){throw 'Product checkpoint predates this lifecycle invocation.'}}
            if($tx -and [string]$value.transactionId -cne [string]$tx){throw 'Product checkpoint binding mismatch: transactionId.'}
            foreach($pair in @(@('payloadSha256',$payload),@('action',$expectedAction),@('role',$expectedRole))){if([string]$value.($pair[0]) -cne [string]$pair[1]){throw "Product checkpoint binding mismatch: $($pair[0])."}}
            $generation=[int]$value.checkpointGeneration
            if([string]$value.state -ne 'waiting-for-reboot' -or $generation -lt $min -or $generation -gt $max){throw 'Product checkpoint is not an exact bounded waiting-for-reboot boundary.'}
            [ordered]@{path=$path;transactionId=[string]$value.transactionId;payloadSha256=[string]$value.payloadSha256;action=[string]$value.action;role=[string]$value.role;state=[string]$value.state;generation=$generation;checkpointGeneration=$generation;completedStages=@($value.completedStages);resumeStage=[string]$value.resumeStage;lastWriteUtc=(Get-Item -LiteralPath $path).LastWriteTimeUtc.ToString('o')}
        } -ArgumentList $TransactionId,$PayloadSha256,$Action,$Role,$MinimumGeneration,$MaxGeneration,$InvocationStartUtc
    }finally{if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}}
}

function Invoke-ProductRebootBoundary {
    param([Parameter(Mandatory)][psobject]$Context,[Parameter(Mandatory)][psobject]$Checkpoint,[Parameter(Mandatory)][int]$PriorGeneration)
    if([int]$Checkpoint.generation -ne ($PriorGeneration+1)){throw 'Product reboot boundary did not advance exactly one generation.'}
    # Product truth authorizes this boundary; the harness may only automate the
    # existing exact disposable L1 and only once for this generation.
    $arm=$null;$disarm=$null
    try {
        $arm=Arm-DevFleetE2EInteractiveLogon -VmId ([guid][string]$Context.vmId)
        $restart=Restart-DevFleetE2EL1 -ArmState $arm
        $desktop=Wait-DevFleetE2EInteractiveDesktop -VmId ([guid][string]$Context.vmId) -TimeoutSeconds 300
        $disarm=Disarm-DevFleetE2EInteractiveLogon -ArmState $arm
        $survival=Assert-DevFleetE2EInteractiveDesktopAfterDisarm -VmId ([guid][string]$Context.vmId)
    } finally {
        if($arm -and -not $disarm){try{Disarm-DevFleetE2EInteractiveLogon -ArmState $arm|Out-Null}catch{}}
    }
    $post=[ordered]@{computer=$desktop.desktop.computer;boot=[string]$desktop.boot;sessionId=[int]$desktop.desktop.sessionId;explorerPid=[int]$desktop.desktop.explorerPid}
    $bootChanged=$false
    try{$bootChanged=([datetime]$post.boot -gt [datetime]$arm.preBoot)}catch{throw 'Product reboot boundary did not return comparable pre/post boot identities.'}
    if(-not $bootChanged){throw 'Product reboot boundary did not prove a changed boot identity.'}
    # Servicing is observed and allowed to settle, but it is never a product
    # generation or authorization to reboot. Require two identical samples.
    $settleSession=$null;$servicingSettlement=$null;$servicingStable=$false;$servicingDeadline=(Get-Date).AddMinutes(3)
    do {
        try {
            $settleSession=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
            $first=ConvertTo-ProductServicingSample (Invoke-Command -Session $settleSession -ScriptBlock {$pfr=@((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations);$m=@($pfr|Where-Object{-not [string]::IsNullOrWhiteSpace([string]$_)});[ordered]@{cbs=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending');windowsUpdate=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired');pendingCount=$m.Count}})
            Remove-DevFleetGuestSession $settleSession -ErrorAction SilentlyContinue;$settleSession=$null
            Start-Sleep -Seconds 3
            $settleSession=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
            $second=ConvertTo-ProductServicingSample (Invoke-Command -Session $settleSession -ScriptBlock {$pfr=@((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations);$m=@($pfr|Where-Object{-no