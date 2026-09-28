# DevFleet source part 026

Full-source UTF-8 byte interval [1162500, 1209000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: d4ac6d05e2d484319537d48c075c9c94a6cce8a5a5fe7dffb26d22f5ee0c2b10

<!-- BEGIN SOURCE SLICE -->
,'ownershipledger','installstate','ownership','receipt')){continue}
        $childPath=if($Path -eq 'root'){$name}else{"$Path.$name"};$childSeen=[System.Collections.Generic.HashSet[int]]::new($Seen);if(-not (Test-NoActiveProductCheckpoint -Value $item -Depth ($Depth+1) -Seen $childSeen -Path $childPath)){return $false}
    }
    return $true
}

function Test-BenignLifecycleCheckpointGenerationSignal {
    param([AllowNull()][object]$Signal)
    $kindFound=$false;$kind=Get-LifecycleProperty $Signal 'kind' ([ref]$kindFound)
    $pathFound=$false;$path=Get-LifecycleProperty $Signal 'path' ([ref]$pathFound)
    $valueFound=$false;$value=Get-LifecycleProperty $Signal 'value' ([ref]$valueFound)
    $parsed=0
    return ($kindFound -and [string]$kind -ieq 'checkpointgeneration' -and $pathFound -and [string]$path -match '(^|\.)progress\.checkpointGeneration$' -and $valueFound -and [int]::TryParse([string]$value,[ref]$parsed) -and $parsed -eq 0 -and [string]$value -ceq '0')
}

function Test-LifecycleCompletionInput {
    param([AllowNull()][object]$Value,[ref]$Reason)
    $Reason.Value=''
    if(-not (Test-NoActiveProductCheckpoint -Value $Value)){$Reason.Value='active checkpoint, generation, or waiting-for-reboot signal';return $false}
    $found=$false;$terminal=Get-LifecycleProperty $Value 'terminalFailure' ([ref]$found);if($found -and [bool]$terminal){$Reason.Value='terminalFailure claim';return $false}
    foreach($name in @('failure','error')){$found=$false;$claim=Get-LifecycleProperty $Value $name ([ref]$found);if($found -and -not [string]::IsNullOrWhiteSpace([string]$claim)){$Reason.Value="$name claim";return $false}}
    foreach($name in @('status','outcome')){$found=$false;$claim=Get-LifecycleProperty $Value $name ([ref]$found);if($found -and [string]$claim -match '^(?i:TERMINAL_FAILURE|TERMINAL|ERROR|WAITING_FOR_REBOOT)$'){$Reason.Value="$name=$claim";return $false}}
    $signals=@(Get-RawActiveLifecycleSignals -Value $Value);$unsafe=$signals|Where-Object{$_.kind -in @('terminalFailure','failure','error','terminalReason','terminal-status','depth-cutoff','cycle') -or ($_.kind -eq 'waiting-for-reboot' -and [string]$_.path -notmatch '^checkpoint\.state$') -or ($_.kind -eq 'checkpoint' -and [string]$_.path -notmatch '^checkpoint$') -or ($_.kind -eq 'generation' -and [string]$_.path -notmatch '^checkpoint\.') -or ($_.kind -eq 'checkpointgeneration' -and -not (Test-BenignLifecycleCheckpointGenerationSignal $_) -and [string]$_.path -notmatch '^(progress|checkpoint)\.') }|Select-Object -First 1
    if($unsafe){$Reason.Value="unsafe lifecycle signal at $([string]$unsafe.path)";return $false}
    return $true
}

function Test-LifecycleTransitionObservationBinding {
    param([AllowNull()][object]$Observation,[AllowNull()][object]$Checkpoint,[ref]$Reason)
    $Reason.Value=''
    if($null -eq $Observation){return $true}
    $found=$false;$rawCheckpoint=Get-LifecycleProperty $Observation 'checkpoint' ([ref]$found);$hasRawCheckpoint=$found -and $null -ne $rawCheckpoint;$flagFound=$false;$flagValue=Get-LifecycleProperty $Observation 'checkpointPresent' ([ref]$flagFound);if($flagFound -and ([bool]$flagValue) -ne $hasRawCheckpoint){$Reason.Value='transition observation checkpoint presence flag disagrees with object';return $false}
    if($hasRawCheckpoint){if(-not $flagFound){$Reason.Value='transition observation checkpointPresent flag is missing';return $false};if($null -eq $Checkpoint){$Reason.Value='transition observation supplied a checkpoint for a non-reboot outcome';return $false};$canonical=ConvertTo-CanonicalLifecycleCheckpoint $rawCheckpoint;if(-not $canonical){$Reason.Value='transition observation checkpoint is malformed';return $false};foreach($name in @('generation','checkpointGeneration','transactionId','payloadSha256','action','role','state')){$expectedFound=$false;$expectedValue=Get-LifecycleProperty $Checkpoint $name ([ref]$expectedFound);$actualFound=$false;$actualValue=Get-LifecycleProperty $canonical $name ([ref]$actualFound);if(-not $expectedFound -or -not $actualFound -or [string]$expectedValue -cne [string]$actualValue){$Reason.Value="transition observation checkpoint binding mismatch: $name";return $false}}}
    $signals=@(Get-RawActiveLifecycleSignals -Value $Observation);$unsafe=$signals|Where-Object{($_.kind -eq 'generation' -and [string]$_.path -notmatch '^checkpoint\.') -or ($_.kind -eq 'checkpointgeneration' -and -not (Test-BenignLifecycleCheckpointGenerationSignal $_) -and [string]$_.path -notmatch '^(progress|checkpoint)\.') -or ($_.kind -eq 'checkpoint' -and [string]$_.path -notmatch '^checkpoint$') -or [string]$_.path -match '(^|\.)observation\.' -or ($_.kind -eq 'waiting-for-reboot' -and [string]$_.path -notmatch '^checkpoint\.state$') -or $_.kind -in @('terminalFailure','failure','error','terminalReason','terminal-status','depth-cutoff','cycle')}|Select-Object -First 1;if($unsafe){$Reason.Value="transition observation active signal at $([string]$unsafe.path)";return $false}
    return $true
}

function Get-RawActiveLifecycleSignals {
    param([AllowNull()][object]$Value,[string]$Path='root',[int]$Depth=0,[System.Collections.Generic.HashSet[int]]$Seen)
    $signals=@();if($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive -or $Value -is [datetime] -or $Value -is [guid]){return @()}
    if($Depth -gt 12){return @([pscustomobject]@{path=$Path;kind='depth-cutoff';value='unsafe'})}
    if(-not $Seen){$Seen=[System.Collections.Generic.HashSet[int]]::new()};$identity=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Value);if(-not $Seen.Add($identity)){return @([pscustomobject]@{path=$Path;kind='cycle';value='unsafe'})}
    if($Value -is [System.Collections.IDictionary]){
        foreach($entry in $Value.GetEnumerator()){
            $name=[string]$entry.Key;$item=$entry.Value;$lower=$name.ToLowerInvariant();$childPath=if($Path -eq 'root'){$name}else{"$Path.$name"}
            $ignoredLedger=($lower -in @('installledger','ownershipledger','installstate','ownership','receipt'))
            if(-not $ignoredLedger){
                if($lower -in @('generation','checkpointgeneration')){$signals+=[pscustomobject]@{path=$childPath;kind=$lower;value=[string]$item}}
                elseif($lower -eq 'checkpoint' -and $null -ne $item){$signals+=[pscustomobject]@{path=$childPath;kind='checkpoint';value='present'}}
                elseif($lower -eq 'checkpointpresent' -and [bool]$item){$signals+=[pscustomobject]@{path=$childPath;kind='checkpointPresent';value='true'}}
                elseif($lower -eq 'state' -and [string]$item -ieq 'waiting-for-reboot'){$signals+=[pscustomobject]@{path=$childPath;kind='waiting-for-reboot';value='true'}}
                elseif($lower -eq 'terminalfailure' -and [bool]$item){$signals+=[pscustomobject]@{path=$childPath;kind='terminalFailure';value='true'}}
                elseif($lower -in @('failure','error','terminalreason') -and -not [string]::IsNullOrWhiteSpace([string]$item)){$signals+=[pscustomobject]@{path=$childPath;kind=$lower;value=[string]$item}}
                elseif($lower -eq 'status' -and [string]$item -match '^(?i:TERMINAL_FAILURE|TERMINAL|ERROR|WAITING_FOR_REBOOT)$'){$signals+=[pscustomobject]@{path=$childPath;kind='terminal-status';value=[string]$item}}
                $childSeen=[System.Collections.Generic.HashSet[int]]::new($Seen);$signals+=@(Get-RawActiveLifecycleSignals -Value $item -Path $childPath -Depth ($Depth+1) -Seen $childSeen)
            }
        }
        return $signals
    }
    if($Value -is [System.Collections.IEnumerable]){foreach($item in $Value){$childSeen=[System.Collections.Generic.HashSet[int]]::new($Seen);$signals+=@(Get-RawActiveLifecycleSignals -Value $item -Path ($Path+'[]') -Depth ($Depth+1) -Seen $childSeen)};return $signals}
    foreach($property in @($Value.PSObject.Properties)){
        $name=[string]$property.Name;$item=$property.Value;$lower=$name.ToLowerInvariant();$childPath=if($Path -eq 'root'){$name}else{"$Path.$name"}
        $ignoredLedger=($lower -in @('installledger','ownershipledger','installstate','ownership','receipt'))
        if(-not $ignoredLedger){
            if($lower -in @('generation','checkpointgeneration')){$signals+=[pscustomobject]@{path=$childPath;kind=$lower;value=[string]$item}}
            elseif($lower -eq 'checkpoint' -and $null -ne $item){$signals+=[pscustomobject]@{path=$childPath;kind='checkpoint';value='present'}}
            elseif($lower -eq 'checkpointpresent' -and [bool]$item){$signals+=[pscustomobject]@{path=$childPath;kind='checkpointPresent';value='true'}}
            elseif($lower -eq 'state' -and [string]$item -ieq 'waiting-for-reboot'){$signals+=[pscustomobject]@{path=$childPath;kind='waiting-for-reboot';value='true'}}
            elseif($lower -eq 'terminalfailure' -and [bool]$item){$signals+=[pscustomobject]@{path=$childPath;kind='terminalFailure';value='true'}}
            elseif($lower -in @('failure','error','terminalreason') -and -not [string]::IsNullOrWhiteSpace([string]$item)){$signals+=[pscustomobject]@{path=$childPath;kind=$lower;value=[string]$item}}
            elseif($lower -eq 'status' -and [string]$item -match '^(?i:TERMINAL_FAILURE|TERMINAL|ERROR|WAITING_FOR_REBOOT)$'){$signals+=[pscustomobject]@{path=$childPath;kind='terminal-status';value=[string]$item}}
        $childSeen=[System.Collections.Generic.HashSet[int]]::new($Seen);$signals+=@(Get-RawActiveLifecycleSignals -Value $item -Path $childPath -Depth ($Depth+1) -Seen $childSeen)
        }
    }
    return $signals
}

function Get-DurableProgressClassification {
    param(
        [Parameter(Mandatory)][psobject]$Observation,
        [Parameter(Mandatory)][psobject]$PriorCheckpoint,
        [int]$MaxGeneration = 3
    )
    $observationProperties=Get-LifecyclePropertyNames $Observation
    $hasCheckpointProperty=Test-LifecycleProperty -Value $Observation -Name 'checkpoint'
    $found=$false;$observationCheckpoint=Get-LifecycleProperty $Observation 'checkpoint' ([ref]$found)
    $actualCheckpointPresent=($null -ne $observationCheckpoint)
    $hasPresenceFlag=Test-LifecycleProperty -Value $Observation -Name 'checkpointPresent';$found=$false;$checkpointPresentValue=Get-LifecycleProperty $Observation 'checkpointPresent' ([ref]$found)
    $flaggedCheckpointPresent=($hasPresenceFlag -and [bool]$checkpointPresentValue)
    if($hasPresenceFlag -and $flaggedCheckpointPresent -ne $actualCheckpointPresent){return 'TERMINAL_FAILURE'}
    $observationCheckpointPresent=$actualCheckpointPresent
    # Apply the same fail-closed raw-signal precedence as the normalized wait
    # seam. Direct classifier callers must not be able to hide an active or
    # contradictory lifecycle signal in an unknown/nested property.
    $rawSignals=@(Get-RawActiveLifecycleSignals -Value $Observation)
    $unsafeSignal=$rawSignals|Where-Object{($_.kind -eq 'generation' -and [string]$_.path -notmatch '^checkpoint\.') -or ($_.kind -eq 'checkpointgeneration' -and -not (Test-BenignLifecycleCheckpointGenerationSignal $_) -and [string]$_.path -notmatch '^(progress|checkpoint)\.') -or ($_.kind -eq 'checkpoint' -and [string]$_.path -notmatch '^checkpoint$') -or [string]$_.path -match '(^|\.)observation\.' -or ($_.kind -eq 'waiting-for-reboot' -and [string]$_.path -notmatch '^checkpoint\.state$') -or $_.kind -in @('terminalFailure','failure','error','terminalReason','terminal-status','depth-cutoff','cycle')}|Select-Object -First 1
    if($unsafeSignal){return 'TERMINAL_FAILURE'}
    if($observationCheckpointPresent){$canonicalObservationCheckpoint=ConvertTo-CanonicalLifecycleCheckpoint $observationCheckpoint;if(-not $canonicalObservationCheckpoint){return 'TERMINAL_FAILURE'};$observationCheckpoint=$canonicalObservationCheckpoint}
    $found=$false;$terminalFlag=Get-LifecycleProperty $Observation 'terminalFailure' ([ref]$found);$terminalClaim=($found -and [bool]$terminalFlag);$found=$false;$failureValue=Get-LifecycleProperty $Observation 'failure' ([ref]$found);$failureClaim=($found -and -not [string]::IsNullOrWhiteSpace([string]$failureValue));$found=$false;$errorValue=Get-LifecycleProperty $Observation 'error' ([ref]$found);$errorClaim=($found -and -not [string]::IsNullOrWhiteSpace([string]$errorValue));$found=$false;$statusValue=Get-LifecycleProperty $Observation 'status' ([ref]$found);$statusClaim=($found -and [string]$statusValue -match '^(?i:TERMINAL_FAILURE|TERMINAL|ERROR)$');if($terminalClaim -or $failureClaim -or $errorClaim -or $statusClaim){return 'TERMINAL_FAILURE'}
    $statusClaimsCompleted=($found -and [string]$statusValue -eq 'COMPLETED');$allCompletionFields=$true
    foreach($completionField in @('matchingConsumedReceipt','installStateValid','canonicalOwnershipValid','authenticatedHealthOk')){$fieldFound=$false;$fieldValue=Get-LifecycleProperty $Observation $completionField ([ref]$fieldFound);if(-not ($fieldFound -and [bool]$fieldValue)){$allCompletionFields=$false}}
    $claimsCompleted=$statusClaimsCompleted -or $allCompletionFields
    $roleIdentityFound=$false;$roleIdentityValid=Get-LifecycleProperty $Observation 'productRoleIdentityValid' ([ref]$roleIdentityFound);if($claimsCompleted -and $roleIdentityFound -and $null -ne $roleIdentityValid -and -not [bool]$roleIdentityValid){return 'TERMINAL_FAILURE'}
    if($actualCheckpointPresent -and $claimsCompleted){return 'TERMINAL_FAILURE'}
    if ($observationCheckpoint -and $observationCheckpointPresent) {
        foreach($required in @('checkpointGeneration','transactionId','payloadSha256','action','role','state')){if(-not (Test-LifecycleProperty -Value $observationCheckpoint -Name $required)){return 'TERMINAL_FAILURE'}}
        $found=$false;$currentCheckpointGeneration=Get-LifecycleProperty $observationCheckpoint 'checkpointGeneration' ([ref]$found);if(-not $found){return 'TERMINAL_FAILURE'};$found=$false;$priorCheckpointGeneration=Get-LifecycleProperty $PriorCheckpoint 'checkpointGeneration' ([ref]$found);if(-not $found){return 'TERMINAL_FAILURE'};$generation=0;$priorGeneration=0;if(-not [int]::TryParse([string]$currentCheckpointGeneration,[ref]$generation)-or-not [int]::TryParse([string]$priorCheckpointGeneration,[ref]$priorGeneration)){return 'TERMINAL_FAILURE'}
        $bindingMatches=$true
        foreach($name in @('transactionId','payloadSha256','action','role')) {
            $currentFound=$false;$currentValue=Get-LifecycleProperty $observationCheckpoint $name ([ref]$currentFound);$priorFound=$false;$priorValue=Get-LifecycleProperty $PriorCheckpoint $name ([ref]$priorFound);if(-not $currentFound -or -not $priorFound -or [string]$currentValue -cne [string]$priorValue){$bindingMatches=$false;break}
        }
        $found=$false;$checkpointState=Get-LifecycleProperty $observationCheckpoint 'state' ([ref]$found);if(-not $bindingMatches -or -not $found -or [string]$checkpointState -ne 'waiting-for-reboot' -or $generation -lt 1 -or $generation -gt $MaxGeneration -or $generation -gt ($priorGeneration + 1) -or $generation -lt $priorGeneration) { return 'TERMINAL_FAILURE' }
    }
    if (Test-RebootBoundaryIdentity -PriorCheckpoint $PriorCheckpoint -CurrentCheckpoint $observationCheckpoint -MaxGeneration $MaxGeneration) {
        return 'NEXT_REBOOT'
    }
    $receiptFound=$false;$receiptValue=Get-LifecycleProperty $Observation 'matchingConsumedReceipt' ([ref]$receiptFound);$receiptOk=($receiptFound -and [bool]$receiptValue);$installFound=$false;$installValue=Get-LifecycleProperty $Observation 'installStateValid' ([ref]$installFound);$installOk=($installFound -and [bool]$installValue);$ownershipFound=$false;$ownershipValue=Get-LifecycleProperty $Observation 'canonicalOwnershipValid' ([ref]$ownershipFound);$ownershipOk=($ownershipFound -and [bool]$ownershipValue);$healthFound=$false;$healthValue=Get-LifecycleProperty $Observation 'authenticatedHealthOk' ([ref]$healthFound);$healthOk=($healthFound -and [bool]$healthValue)
    $progressGeneration=0
    $progressFound=$false;$progressValue=Get-LifecycleProperty $Observation 'progress' ([ref]$progressFound);if($progressFound -and $progressValue -and (Test-LifecycleProperty -Value $progressValue -Name 'checkpointGeneration')){
        $progressFieldFound=$false;$progressGenerationValue=Get-LifecycleProperty $progressValue 'checkpointGeneration' ([ref]$progressFieldFound);if(-not [int]::TryParse([string]$progressGenerationValue,[ref]$progressGeneration)-or$progressGeneration -lt 0){return 'TERMINAL_FAILURE'}
    }
    if (-not $observationCheckpointPresent -and $progressGeneration -eq 0 -and $receiptOk -and $installOk -and $ownershipOk -and $healthOk) {
        return 'COMPLETED'
    }
    if ($terminalClaim) { return 'TERMINAL_FAILURE' }
    return 'NO_PROGRESS'
}

function Resolve-GuestProgressMarkerRead {
    param(
        [AllowEmptyString()][string]$Text = '',
        [AllowNull()][Nullable[int]]$ExitCode,
        [switch]$TimedOut,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExpectedTransactionId,
        [Parameter(Mandatory)][string]$ExpectedPayloadSha256,
        [string]$InstanceName = '',
        [ValidateSet('','primary','surrogate','vault')][string]$ExpectedNodeRole = ''
    )
    $prefix=if($InstanceName){"guest marker read for $InstanceName"}else{'guest marker read'}
    if($TimedOut){return [pscustomobject]@{status='TIMEOUT';marker=$null;error="$prefix timed out";exitCode=$null;instanceName=$InstanceName}}
    if($null -eq $ExitCode){return [pscustomobject]@{status='TRANSPORT_FAILURE';marker=$null;error="$prefix returned no native exit status";exitCode=$null;instanceName=$InstanceName}}
    if([int]$ExitCode -eq 44){return [pscustomobject]@{status='ABSENT';marker=$null;error="$prefix positively verified the marker path absent";exitCode=44;instanceName=$InstanceName}}
    if([int]$ExitCode -ne 0){return [pscustomobject]@{status='NATIVE_FAILURE';marker=$null;error="$prefix failed with native exit code $ExitCode";exitCode=[int]$ExitCode;instanceName=$InstanceName}}
    if([string]::IsNullOrWhiteSpace($Text)){return [pscustomobject]@{status='MALFORMED';marker=$null;error="$prefix returned empty content for an existing marker";exitCode=0;instanceName=$InstanceName}}
    try {$marker=$Text|ConvertFrom-Json -ErrorAction Stop} catch {return [pscustomobject]@{status='MALFORMED';marker=$null;error="$prefix returned invalid JSON";exitCode=0;instanceName=$InstanceName}}
    $values=[ordered]@{};$shapeComplete=$true
    foreach($name in @('schemaVersion','transactionId','payloadSha256','sequence','component','state','updatedUtc','packageVersion','nodeRole')){$found=$false;$values[$name]=Get-LifecycleProperty $marker $name ([ref]$found);if(-not $found){$shapeComplete=$false}}
    $sequence=0;$schema=0;$updated=[datetime]::MinValue
    $computeComponents=@('secretsInput','packagePrerequisites','dockerRepositoryAndInstall','tailscaleRepositoryAndInstall','rootlessRuntime','nodeToolchain','pythonRuntime','serviceAndFirewallFinalization','bootstrap')
    $vaultComponents=@('secretsInput','packagePrerequisites','restServer','tailscaleChecks','serviceConfiguration','firewallFinalization','bootstrap')
    $roleShape=((([string]$values.nodeRole) -in @('primary','surrogate') -and ([string]$values.packageVersion) -match '^\d+\.\d+\.\d+$' -and ([string]$values.component) -in $computeComponents) -or (([string]$values.nodeRole) -ceq 'vault' -and ([string]$values.packageVersion) -ceq 'vault' -and ([string]$values.component) -in $vaultComponents))
    $validShape=($shapeComplete -and [int]::TryParse([string]$values.schemaVersion,[ref]$schema) -and $schema -eq 1 -and
        [int]::TryParse([string]$values.sequence,[ref]$sequence) -and $sequence -ge 1 -and
        [datetime]::TryParse([string]$values.updatedUtc,[ref]$updated) -and $Text -match '"updatedUtc"\s*:\s*"[^"]*Z"' -and
        ([string]$values.transactionId) -match '^[0-9a-fA-F]{32}$' -and
        ([string]$values.payloadSha256) -match '^[0-9a-fA-F]{64}$' -and
        $roleShape -and
        ([string]$values.nodeRole) -in @('primary','surrogate','vault') -and
        ([string]$values.component) -in @('secretsInput','packagePrerequisites','dockerRepositoryAndInstall','tailscaleRepositoryAndInstall','rootlessRuntime','nodeToolchain','pythonRuntime','serviceAndFirewallFinalization','restServer','tailscaleChecks','serviceConfiguration','firewallFinalization','bootstrap') -and
        ([string]$values.state) -in @('STARTED','COMPLETED','FAILED','TIMED_OUT'))
    if(-not $validShape){return [pscustomobject]@{status='MALFORMED';marker=$null;error="$prefix failed the marker schema";exitCode=0;instanceName=$InstanceName}}
    if(-not $ExpectedTransactionId){return [pscustomobject]@{status='TRANSACTION_UNBOUND';marker=$null;error="$prefix cannot be trusted before the product transaction is bound";exitCode=0;instanceName=$InstanceName}}
    if(([string]$values.transactionId) -cne $ExpectedTransactionId -or ([string]$values.payloadSha256) -cne $ExpectedPayloadSha256){return [pscustomobject]@{status='IDENTITY_MISMATCH';marker=$null;error="$prefix did not match the current transaction and payload";exitCode=0;instanceName=$InstanceName}}
    if($ExpectedNodeRole -and ([string]$values.nodeRole) -cne $ExpectedNodeRole){return [pscustomobject]@{status='ROLE_MISMATCH';marker=$null;error="$prefix did not match the expected product role";exitCode=0;instanceName=$InstanceName}}
    return [pscustomobject]@{status='VALID';marker=$marker;error='';exitCode=0;instanceName=$InstanceName;nodeRole=[string]$values.nodeRole}
}

function Resolve-DevFleetRoleBoundGuestMarkerReads {
    param(
        [Parameter(Mandatory)][object]$RemoteResult,
        [Parameter(Mandatory)][object[]]$Targets,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TransactionId,
        [Parameter(Mandatory)][string]$PayloadSha256
    )
    $result=[ordered]@{status='UNVERIFIED';marker=$null;markers=@();requiredMarkersValid=$false;error='';exitCode=$null;instanceName='';probedInstances=@();readResults=@();rejectedReadNames=@()}
    $targetMap=[ordered]@{}
    foreach($target in $Targets){$nameFound=$false;$name=[string](Get-LifecycleProperty $target 'instanceName' ([ref]$nameFound));$roleFound=$false;$nodeRole=[string](Get-LifecycleProperty $target 'nodeRole' ([ref]$roleFound));if(-not $nameFound -or $name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$' -or -not $roleFound -or $nodeRole -notin @('primary','surrogate','vault') -or $targetMap.Contains($name)){throw 'TERMINAL_FAILURE: role-bound guest marker target is missing, malformed, or duplicated.'};$targetMap[$name]=$nodeRole}
    if($targetMap.Count -lt 1 -or $targetMap.Count -gt 2){throw 'TERMINAL_FAILURE: role-bound guest marker target count is invalid.'}
    $remoteStatusFound=$false;$remoteStatus=[string](Get-LifecycleProperty $RemoteResult 'status' ([ref]$remoteStatusFound));$remoteErrorFound=$false;$remoteError=[string](Get-LifecycleProperty $RemoteResult 'error' ([ref]$remoteErrorFound));$inventoryExitFound=$false;$inventoryExit=Get-LifecycleProperty $RemoteResult 'inventoryExitCode' ([ref]$inventoryExitFound);$probedFound=$false;$result.probedInstances=@(Get-LifecycleProperty $RemoteResult 'probedInstances' ([ref]$probedFound));if(-not $probedFound){$result.probedInstances=@()}
    if(-not $remoteStatusFound -or $remoteStatus -cne 'READS_COLLECTED'){$result.status=if($remoteStatusFound -and $remoteStatus){$remoteStatus}else{'UNVERIFIED'};$result.error=if($remoteErrorFound -and $remoteError){$remoteError}else{'guest marker collector produced no classifiable result'};$result.exitCode=if($inventoryExitFound){$inventoryExit}else{$null};return [pscustomobject]$result}
    $readsFound=$false;$reads=@(Get-LifecycleProperty $RemoteResult 'markerReads' ([ref]$readsFound));if(-not $readsFound){$reads=@()}
    $valid=[Collections.Generic.List[object]]::new()
    foreach($read in $reads){$nameFound=$false;$name=[string](Get-LifecycleProperty $read 'instanceName' ([ref]$nameFound));if(-not $nameFound -or -not $targetMap.Contains($name)){$result.rejectedReadNames+=if($nameFound){$name}else{''};continue};$duplicates=@($result.readResults|Where-Object{[string]$_.instanceName -ceq $name});if($duplicates.Count -gt 0){$resolved=[pscustomobject]@{status='MALFORMED';marker=$null;error="guest marker collector returned duplicate reads for $name";exitCode=$null;instanceName=$name}}else{$textFound=$false;$text=[string](Get-LifecycleProperty $read 'text' ([ref]$textFound));$exitFound=$false;$exit=Get-LifecycleProperty $read 'exitCode' ([ref]$exitFound);$timedFound=$false;$timed=[bool](Get-LifecycleProperty $read 'timedOut' ([ref]$timedFound));$resolved=Resolve-GuestProgressMarkerRead -Text $(if($textFound){$text}else{''}) -ExitCode $(if($exitFound){$exit}else{$null}) -TimedOut:$timed -ExpectedTransactionId $TransactionId -ExpectedPayloadSha256 $PayloadSha256 -InstanceName $name -ExpectedNodeRole ([string]$targetMap[$name])};$result.readResults+=,$resolved;if([string]$resolved.status -eq 'VALID'){$valid.Add([pscustomobject][ordered]@{instanceName=$name;nodeRole=[string]$targetMap[$name];marker=$resolved.marker})}}
    foreach($name in $targetMap.Keys){if(@($result.readResults|Where-Object{[string]$_.instanceName -ceq [string]$name}).Count -eq 0){$result.readResults+=,[pscustomobject]@{status='INSTANCE_ABSENT';marker=$null;error="required product instance $name is not currently present";exitCode=$null;instanceName=[string]$name}}}
    $result.markers=@($valid);$result.requiredMarkersValid=($valid.Count -eq $targetMap.Count -and $result.rejectedReadNames.Count -eq 0)
    if($valid.Count -gt 0){$selected=$valid[$valid.Count-1];$result.marker=$selected.marker;$result.instanceName=[string]$selected.instanceName;$result.exitCode=0;$result.status=if($result.requiredMarkersValid){'VALID'}else{'PARTIAL_VALID'};$failures=@($result.readResults|Where-Object{[string]$_.status -ne 'VALID'});$result.error=if($failures){(@($failures|ForEach-Object{[string]$_.error}|Where-Object{$_}) -join '; ')}else{''};return [pscustomobject]$result}
    $priority=@('TIMEOUT','TRANSPORT_FAILURE','NATIVE_FAILURE','MALFORMED','ROLE_MISMATCH','IDENTITY_MISMATCH','TRANSACTION_UNBOUND','INSTANCE_ABSENT','ABSENT');$selectedFailure=$null;foreach($status in $priority){$selectedFailure=@($result.readResults|Where-Object{[string]$_.status -eq $status}|Select-Object -First 1);if($selectedFailure){break}};if($selectedFailure){$result.status=[string]$selectedFailure.status;$result.error=[string]$selectedFailure.error;$result.exitCode=$selectedFailure.exitCode;$result.instanceName=[string]$selectedFailure.instanceName}else{$result.status='UNVERIFIED';$result.error='guest marker read produced no classifiable result'}
    return [pscustomobject]$result
}

function Add-GuestProgressMarkerObservation {
    param([Parameter(Mandatory)][object]$Observation,[Parameter(Mandatory)][object]$ReadResult)
    $progressFound=$false;$progress=Get-LifecycleProperty $Observation 'progress' ([ref]$progressFound)
    if(-not $progressFound -or -not $progress){return $Observation}
    $set={param($target,$name,$value)if($target -is [System.Collections.IDictionary]){$target[$name]=$value}else{$target|Add-Member -NotePropertyName $name -NotePropertyValue $value -Force}}
    $statusFound=$false;$status=[string](Get-LifecycleProperty $ReadResult 'status' ([ref]$statusFound));$markerFound=$false;$readMarker=Get-LifecycleProperty $ReadResult 'marker' ([ref]$markerFound);$markersFound=$false;$boundMarkers=@(Get-LifecycleProperty $ReadResult 'markers' ([ref]$markersFound));if(-not $markersFound -and $markerFound -and $readMarker){$instanceFound=$false;$instance=[string](Get-LifecycleProperty $ReadResult 'instanceName' ([ref]$instanceFound));$boundMarkers=@([pscustomobject]@{instanceName=$instance;nodeRole=[string]$readMarker.nodeRole;marker=$readMarker})};$readsFound=$false;$readOutcomes=@(Get-LifecycleProperty $ReadResult 'readResults' ([ref]$readsFound));if(-not $readsFound){$readOutcomes=@($ReadResult)};$requiredFound=$false;$requiredValid=Get-LifecycleProperty $ReadResult 'requiredMarkersValid' ([ref]$requiredFound);if(-not $requiredFound){$requiredValid=($markerFound -and $null -ne $readMarker)};$errorFound=$false;$readError=[string](Get-LifecycleProperty $ReadResult 'error' ([ref]$errorFound))
    &$set $progress 'guestProgressMarkerStatus' $status
    &$set $progress 'guestProgressMarkers' $boundMarkers
    &$set $progress 'guestProgressMarkerOutcomes' @($readOutcomes|ForEach-Object{$instanceFound=$false;$instance=[string](Get-LifecycleProperty $_ 'instanceName' ([ref]$instanceFound));$outcomeFound=$false;$outcome=[string](Get-LifecycleProperty $_ 'status' ([ref]$outcomeFound));$detailFound=$false;$detail=[string](Get-LifecycleProperty $_ 'error' ([ref]$detailFound));$exitFound=$false;$exit=Get-LifecycleProperty $_ 'exitCode' ([ref]$exitFound);[pscustomobject][ordered]@{instanceName=if($instanceFound){$instance}else{''};status=if($outcomeFound){$outcome}else{'UNVERIFIED'};detail=if($detailFound){$detail}else{''};exitCode=if($exitFound){$exit}else{$null}}})
    &$set $Observation 'productRoleIdentityValid' ([bool]$requiredValid)
    if($markerFound -and $readMarker){
        $marker=[ordered]@{schemaVersion=[int]$readMarker.schemaVersion;transactionId=[string]$readMarker.transactionId;payloadSha256=[string]$readMarker.payloadSha256;sequence=[int]$readMarker.sequence;component=[string]$readMarker.component;state=[string]$readMarker.state;updatedUtc=([datetime]$readMarker.updatedUtc).ToUniversalTime().ToString('o');packageVersion=[string]$readMarker.packageVersion;nodeRole=[string]$readMarker.nodeRole}
        &$set $progress 'guestProgressMarker' $marker
        &$set $progress 'guestProgressMarkerError' $(if($errorFound){$readError}else{''})
        $failedBoundMarker=@($boundMarkers|Where-Object{([string]$_.marker.state) -in @('FAILED','TIMED_OUT')}|Select-Object -First 1)
        if($failedBoundMarker){
            $failure="guest bootstrap component $([string]$failedBoundMarker.marker.component) reported $([string]$failedBoundMarker.marker.state) on $([string]$failedBoundMarker.instanceName)"
            &$set $Observation 'terminalFailure' $true
            &$set $Observation 'failure' $failure
            &$set $Observation 'error' $failure
            &$set $Observation 'terminalReason' $failure
            &$set $Observation 'status' 'TERMINAL_FAILURE'
        }
    }else{
        &$set $progress 'guestProgressMarker' $null
        &$set $progress 'guestProgressMarkerError' $(if($errorFound){$readError}else{'guest marker read produced no detail'})
    }
    # The L1 observation serialized progress before the nested guest read.
    # Publish the attached result in both representations of this sample.
    &$set $Observation 'progressMarker' ($progress|ConvertTo-Json -Compress -Depth 20)
    return $Observation
}

function Get-DevFleetProductLaunchProbeDeferral {
    param([object]$Observation,[object[]]$Targets,[string]$TransactionId,[string]$PayloadSha256,[string]$Action,[string]$RoleKind,[int]$CandidateProcessId,[string]$InvocationStartUtc)
    $get={param($value,$name)$found=$false;Get-LifecycleProperty $value $name ([ref]$found)}
    if($Action-cne'FreshInstall'-or$RoleKind-notin@('Desktop','Laptop')-or$TransactionId-notmatch'^[0-9a-fA-F]{32}$'-or$CandidateProcessId-le0){return $null}
    if([bool](&$get $Observation 'terminalFailure')-or@((&$get $Observation 'stageMarkerErrors')|Where-Object{$_}).Count){return $null}
    $active=&$get $Observation 'activeTransaction';$candidate=&$get $Observation 'candidateProcess'
    if(-not$active-or-not$candidate-or[int](&$get $candidate 'pid')-ne$CandidateProcessId-or[string](&$get $candidate 'commandClass')-cne'DevFleet-Setup'){return $null}
    if([string](&$get $active 'transactionId')-cne$TransactionId-or[string](&$get $active 'payloadSha256')-cne$PayloadSha256-or[string](&$get $active 'action')-cne$Action-or[string](&$get $active 'role')-cne$RoleKind){return $null}
    $start=[datetime]::MinValue;$prepared=[datetime]::MinValue
    if(-not[datetime]::TryParse($InvocationStartUtc,[ref]$start)-or-not[datetime]::TryParse([string](&$get $active 'preparedUtc'),[ref]$prepared)-or$prepared.ToUniversalTime()-lt$start.ToUniversalTime()){return $null}
    # These markers have already passed the current role/transaction/payload,
    # freshness and stage-name validator. Between absent and launched, the
    # shipping provisioning script's only native Multipass call is launch.
    $markers=@((&$get $Observation 'stageMarkers')|Where-Object{$_})
    $pending=@(foreach($target in $Targets){
        $prefix=if($target.kind-ceq'compute'){"stage-compute-$($target.instanceName)"}elseif($target.kind-ceq'vault'-and$RoleKind-ceq'Laptop'){'stage-vault'}else{continue}
        $absent=@($markers|Where-Object{[string]$_.name-ceq"$prefix-instance-absent.complete"})
        $finished=@($markers|Where-Object{[string]$_.name-in@("$prefix-instance-started.complete","$prefix-instance-launched.complete","$prefix-instance-ready.complete","$prefix-payload-transferred.complete","$prefix-payload-extracted.complete","$prefix.complete")})
        if($absent.Count-eq1-and$finished.Count-eq0){[pscustomobject]@{target=$target;marker=$absent[0]}}
    })
    if($pending.Count-ne1){return $null}
    $progress=&$get $Observation 'progress';$processes=@((&$get $progress 'productChildInstances')|Where-Object{$_});$byId=@{}
    foreach($process in $processes){
        $processId=0;$parentId=0
        if(-not[int]::TryParse([string](&$get $process 'pid'),[ref]$processId)-or$processId-le0-or-not[int]::TryParse([string](&$get $process 'parentPid'),[ref]$parentId)-or$parentId-lt0-or$byId.ContainsKey($processId)){return $null}
        $byId[$processId]=$process
    }
    if(-not$byId.ContainsKey($CandidateProcessId)){return $null}
    $native=@($processes|Where-Object{[string](&$get $_ 'name')-ieq'multipass.exe'-and[string](&$get $_ 'commandClass')-ceq'multipass'-and[string](&$get $_ 'path')-match'^[A-Za-z]:\\Program Files(?: \(x86\))?\\Multipass\\bin\\multipass\.exe$'})
    if($native.Count-ne1){return $null}
    $nativeStart=[datetime]::MinValue;$absentAt=[datetime]::MinValue
    if(-not[datetime]::TryParse([string](&$get $native[0] 'startTimeUtc'),[ref]$nativeStart)-or-not[datetime]::TryParse([string]$pending[0].marker.completedUtc,[ref]$absentAt)-or$nativeStart.ToUniversalTime()-lt$absentAt.ToUniversalTime()){return $null}
    $current=[int](&$get $native[0] 'pid');$seen=[Collections.Generic.HashSet[int]]::new()
    while($current-ne$CandidateProcessId){
        if($seen.Count-ge64-or-not$seen.Add($current)-or-not$byId.ContainsKey($current)){return $null}
        $current=[int](&$get $byId[$current] 'parentPid')
    }
    return [pscustomobject]@{instanceName=[string]$pending[0].target.instanceName;nativeProcessId=[int](&$get $native[0] 'pid');stage=[string]$pending[0].marker.name}
}

function Get-ProductAuthenticatedHealthScript {
    return {
        param($ProtocolSha256)
        $ErrorActionPreference='Stop'
        $result=[ordered]@{ok=$false;reasonCode='AUTHENTICATED_HEALTH_UNAVAILABLE';runtimeVersion=$PSVersionTable.PSVersion.ToString();protocolSha256='';requestAttempted=$false;responseAuthenticated=$false}
        try {
            if($PSVersionTable.PSEdition-ne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'Unsupported health client runtime.'}
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
        param($tx,$payload,$expectedAction,$expectedRole,$prior,$max,$candidatePid,$expectedVersion,$expecte