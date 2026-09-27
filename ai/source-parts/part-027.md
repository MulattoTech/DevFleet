# DevFleet source part 027

Full-source UTF-8 byte interval [1209000, 1255500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: db250c2d5a26217e3a7fe8f929f4773f73995b737a8bbc9cd3f497b96aa8b6f7

<!-- BEGIN SOURCE SLICE -->
ool]$normalized.terminalFailure -or -not [string]::IsNullOrWhiteSpace($explicitFailure) -or -not [string]::IsNullOrWhiteSpace([string]$normalized.error) -or [string]$normalized.status -match '^(?i:TERMINAL_FAILURE|TERMINAL|ERROR)$')
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
            $second=ConvertTo-ProductServicingSample (Invoke-Command -Session $settleSession -ScriptBlock {$pfr=@((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations);$m=@($pfr|Where-Object{-not [string]::IsNullOrWhiteSpace([string]$_)});[ordered]@{cbs=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending');windowsUpdate=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired');pendingCount=$m.Count}})
            $servicingStable=Test-ProductServicingSamplesMatch -First $first -Second $second
            $servicingSettlement=[ordered]@{first=$first;second=$second;stable=$servicingStable;observedUtc=(Get-Date).ToUniversalTime().ToString('o')}
        } catch {$servicingSettlement=[ordered]@{stable=$false;error='servicing observation failed'}} finally {if($settleSession){Remove-DevFleetGuestSession $settleSession -ErrorAction SilentlyContinue}}
        if(-not $servicingStable){Start-Sleep -Seconds 3}
    }while(-not $servicingStable -and (Get-Date)-lt $servicingDeadline)
    if(-not $servicingStable){throw 'Product reboot servicing state did not reach a stable settlement observation before the bounded deadline.'}
    return [ordered]@{checkpoint=$Checkpoint;priorGeneration=$PriorGeneration;postGeneration=[int]$Checkpoint.generation;preBoot=[ordered]@{boot=[string]$arm.preBoot};postBoot=$post;bootIdentityChanged=$bootChanged;servicingSettlement=$servicingSettlement;interactiveDesktop=[ordered]@{status='PASS';desktop=$desktop.desktop;disarm=$disarm;survivesDisarm=$survival}}
}
function New-ProductLifecycleCompletionAuthority {
    param([Parameter(Mandatory)][psobject]$Context,[Parameter(Mandatory)][psobject]$Candidate,[Parameter(Mandatory)][string]$Role,[Parameter(Mandatory)][string]$TransactionId,[Parameter(Mandatory)][string]$PayloadSha256,[Parameter(Mandatory)][psobject]$Observation,[object[]]$Legs)
    $reason='';if(-not (Test-LifecycleCompletionInput -Value $Observation -Reason ([ref]$reason))){throw "TERMINAL_FAILURE: completion authority observation rejected: $reason"};if(-not (Test-LifecycleCompletionInput -Value $Legs -Reason ([ref]$reason))){throw "TERMINAL_FAILURE: completion authority lifecycle legs rejected: $reason"}
    $found=$false;$install=Get-LifecycleProperty $Observation 'installStateValid' ([ref]$found);$installOk=($found -and [bool]$install);$found=$false;$ownership=Get-LifecycleProperty $Observation 'canonicalOwnershipValid' ([ref]$found);$ownershipOk=($found -and [bool]$ownership);$found=$false;$health=Get-LifecycleProperty $Observation 'authenticatedHealthOk' ([ref]$found);$healthOk=($found -and [bool]$health);$found=$false;$receipt=Get-LifecycleProperty $Observation 'matchingConsumedReceipt' ([ref]$found);$receiptOk=($found -and [bool]$receipt);if(-not $installOk -or -not $ownershipOk -or -not $healthOk -or -not $receiptOk){throw 'TERMINAL_FAILURE: completion authority lacks exact receipt, installer ledger, ownership, or authenticated health evidence.'}
    $targetsFound=$false;$requiredTargets=@(Get-LifecycleProperty $Context 'expectedProductTargets' ([ref]$targetsFound));if($targetsFound -and $requiredTargets.Count -gt 0){$identityFound=$false;$identityValid=Get-LifecycleProperty $Observation 'productRoleIdentityValid' ([ref]$identityFound);if(-not $identityFound -or -not [bool]$identityValid){throw 'TERMINAL_FAILURE: completion authority lacks valid role-bound guest progress for every required product instance.'}}
    $found=$false;$installLedger=Get-LifecycleProperty $Observation 'installLedger' ([ref]$found);if(-not $found -or $null -eq $installLedger){throw 'TERMINAL_FAILURE: completion authority is missing the installer ledger.'};foreach($required in @('DevFleetVersion','InstallerVersion','PackageSha256','InstallationGeneration','WindowsIntegrationOwnershipPath')){if(-not (Test-LifecycleProperty -Value $installLedger -Name $required)){throw "TERMINAL_FAILURE: installer ledger lacks required property $required."}}
    $found=$false;$ownershipLedger=Get-LifecycleProperty $Observation 'ownershipLedger' ([ref]$found);if(-not $found -or $null -eq $ownershipLedger){throw 'TERMINAL_FAILURE: completion authority is missing the ownership ledger.'};foreach($required in @('SchemaVersion','InstallationGeneration','ScheduledTasks','FirewallRules','Services')){if(-not (Test-LifecycleProperty -Value $ownershipLedger -Name $required)){throw "TERMINAL_FAILURE: ownership ledger lacks required property $required."}}
    $progressFound=$false;$progress=Get-LifecycleProperty $Observation 'progress' ([ref]$progressFound)
    $markersFound=$false;$roleMarkers=@(Get-LifecycleProperty $progress 'guestProgressMarkers' ([ref]$markersFound))
    $configFound=$false;$configHash=[string](Get-LifecycleProperty $Context 'productConfigSha256' ([ref]$configFound))
    $roleEvidence=[ordered]@{requiredTargets=@($requiredTargets);configSha256=$configHash;markers=@($roleMarkers)}
    $guest=[ordered]@{role=$Role;action='FreshInstall';completionVerified=$true;mutationInvoked=$true;transactionId=$TransactionId;payloadSha256=$PayloadSha256;installState=$installLedger;ownership=$ownershipLedger;authenticatedHealth=$healthOk;roleEvidence=$roleEvidence}
    $found=$false;$logicalPhase=Get-LifecycleProperty $Context 'logicalPhaseId' ([ref]$found);$phase=if($found){[string]$logicalPhase}else{[string](Get-LifecycleProperty $Context 'phaseId' ([ref]$found))}
    $evidenceReferences=@();foreach($pattern in @('product-lifecycle-observer-generation-*.json','product-lifecycle-generation-*.json')){foreach($file in @(Get-ChildItem -LiteralPath ([string]$Context.runDir) -Filter $pattern -File -ErrorAction SilentlyContinue)){ $evidenceReferences+=[ordered]@{kind=if($pattern -like '*observer*'){'observer-summary'}else{'lifecycle-generation'};path=$file.FullName;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} }}
    $found=$false;$lifecycleInvocationId=Get-LifecycleProperty $Context 'lifecycleInvocationId' ([ref]$found);return [ordered]@{status='REAL E2E PASS';phase=$phase;invocationId=if($found){[string]$lifecycleInvocationId}else{''};contract='product-lifecycle-completion-authority';completionVerified=$true;candidate=$Candidate;role=$Role;transactionId=$TransactionId;payloadSha256=$PayloadSha256;installState=$installLedger;ownership=$ownershipLedger;authenticatedHealth=$true;guest=$guest;legs=@($Legs);evidenceReferences=$evidenceReferences;evidencePath=(Join-Path ([string]$Context.runDir) 'product-lifecycle-completion-authority.json')}
}

function New-DevFleetExactProofBinding {
    param([Parameter(Mandatory)][psobject]$Context,[Parameter(Mandatory)][object]$PhaseResult,[Parameter(Mandatory)][ValidateSet('Primary / Desktop','Laptop / Surrogate')][string]$ExpectedRole)
    $expectedPhase=if($ExpectedRole -ceq 'Laptop / Surrogate'){'SURROGATE-DISPOSABLE'}else{'REBOOT-RESUME'}
    if([string]$PhaseResult.status -cne 'REAL E2E PASS' -or [string]$PhaseResult.phase -cne $expectedPhase){throw 'Exact proof phase/role did not complete.'}
    $product=$PhaseResult.product
    if(-not $product -or [string]$product.contract -cne 'product-lifecycle-completion-authority' -or -not [bool]$product.completionVerified){throw 'Exact proof lacks native product completion authority.'}
    $tx=[string]$product.transactionId;$lineage=[string]$product.invocationId;$payload=[string]$Context.candidate.tar.sha256
    if($tx -cnotmatch '^[0-9a-f]{32}$' -or $lineage -cnotmatch '^[0-9a-f]{32}$' -or [string]$product.payloadSha256 -cne $payload -or [string]$product.role -cne $ExpectedRole){throw 'Exact proof completion identity is invalid.'}
    $identity=Get-DevFleetProductObservationIdentity -Context $Context -Role $ExpectedRole
    $runRoot=[IO.Path]::GetFullPath([string]$Context.runDir)
    $lifecycleRoot=Join-Path $runRoot ("lifecycle-{0}-{1}" -f $expectedPhase,$lineage)
    $authorityPath=Join-Path $lifecycleRoot 'product-lifecycle-completion-authority.json'
    if([IO.Path]::GetFullPath([string]$product.evidencePath) -cne $authorityPath){throw 'Exact proof completion authority is outside its native lifecycle.'}
    $authority=Get-Content -LiteralPath $authorityPath -Raw|ConvertFrom-Json -ErrorAction Stop
    foreach($field in @('status','contract','transactionId','invocationId','payloadSha256','role')){if([string]$authority.$field -cne [string]$product.$field){throw "Exact proof durable authority disagrees on $field."}}
    if([string]$authority.status -cne 'REAL E2E PASS' -or -not [bool]$authority.completionVerified -or -not [bool]$authority.authenticatedHealth -or -not [bool]$authority.guest.completionVerified -or [string]$authority.guest.transactionId -cne $tx -or [string]$authority.guest.role -cne $ExpectedRole){throw 'Exact proof durable completion is incomplete.'}
    $roleEvidence=$authority.guest.roleEvidence
    if([string]$roleEvidence.configSha256 -cne [string]$identity.configSha256 -or @($roleEvidence.requiredTargets).Count -ne @($identity.targets).Count -or @($roleEvidence.markers).Count -ne @($identity.targets).Count){throw 'Exact proof role evidence lacks the candidate-bound target set.'}
    foreach($target in $identity.targets){
        $required=@($roleEvidence.requiredTargets|Where-Object{[string]$_.instanceName -ceq [string]$target.instanceName -and [string]$_.nodeRole -ceq [string]$target.nodeRole})
        $markers=@($roleEvidence.markers|Where-Object{[string]$_.instanceName -ceq [string]$target.instanceName -and [string]$_.nodeRole -ceq [string]$target.nodeRole})
        if($required.Count -ne 1 -or $markers.Count -ne 1){throw 'Exact proof has missing, duplicate or foreign role targets.'}
        $marker=$markers[0].marker
        if([string]$marker.transactionId -cne $tx -or [string]$marker.payloadSha256 -cne $payload -or [string]$marker.nodeRole -cne [string]$target.nodeRole -or [string]$marker.component -cne 'bootstrap' -or [string]$marker.state -cne 'COMPLETED'){throw 'Exact proof target lacks bound bootstrap completion.'}
    }
    $records=[Collections.Generic.List[object]]::new()
    $records.Add([ordered]@{file='product-lifecycle-completion-authority.json';sha256=(Get-FileHash -LiteralPath $authorityPath).Hash.ToLowerInvariant()})
    $generations=@($authority.evidenceReferences|Where-Object{[string]$_.kind -ceq 'lifecycle-generation'})
    if($generations.Count -lt 1 -or $generations.Count -gt 3){throw 'Exact proof requires one to three real reboot boundaries.'}
    $seen=[Collections.Generic.HashSet[int]]::new()
    foreach($reference in $generations){
        $path=[IO.Path]::GetFullPath([string]$reference.path);$file=Split-Path -Leaf $path
        if((Split-Path -Parent $path) -cne $lifecycleRoot -or $file -cnotmatch '^product-lifecycle-generation-([1-3])\.json$'){throw 'Exact proof generation path is outside its native lifecycle.'}
        $number=[int]$Matches[1]
        if(-not $seen.Add($number) -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne [string]$reference.sha256){throw 'Exact proof generation evidence is duplicated or changed.'}
        $generation=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -ErrorAction Stop
        $chec