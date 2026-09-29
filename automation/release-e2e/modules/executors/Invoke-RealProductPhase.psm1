Set-StrictMode -Version Latest
Import-Module ThreadJob -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot '..\GuestSession.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\HostSafety.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Evidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\FullRelease.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\InteractiveLogon.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\TailscaleE2E.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\HarnessBudget.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\MultipassDiagnostic.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\RealUseAcceptance.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WpfLaunchContract.psm1') -Force

$script:CanonicalIntegrationOwnershipPath = 'C:\ProgramData\DevFleetHostAgent\integration-ownership.json'

function Resolve-DevFleetNestedScenarioIdentity {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$PhaseId,
        [Parameter(Mandatory)][ValidateSet('permanent-delete','delete-restore','stopped-project','host-concurrency','operation-recovery','ownership','vault')][string]$Scenario
    )
    if($RunId.Length -gt 128 -or $RunId -cnotmatch '\A(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'){
        throw 'Nested scenario RunId failed ownership validation.'
    }
    $expectedPhase=$Scenario.ToUpperInvariant()
    if($PhaseId -cne $expectedPhase){throw 'Nested scenario phase does not match its destructive scenario identity.'}
    $root="/tmp/devfleet-e2e/$RunId/$PhaseId"
    if($root -cnotmatch '\A/tmp/devfleet-e2e/(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*/[A-Z0-9]+(?:-[A-Z0-9]+)*\z'){
        throw 'Nested scenario root failed ownership validation.'
    }
    [pscustomobject]@{runId=$RunId;phaseId=$PhaseId;scenario=$Scenario;root=$root}
}

# Provider payloads cross JSON/ remoting boundaries as PSCustomObject,
# Hashtable, or OrderedDictionary. Keep lifecycle decisions independent of
# that representation and use these helpers at every trust boundary.
function Get-LifecycleProperty {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][string]$Name,[ref]$Found)
    $Found.Value=$false
    if($null -eq $Value){return $null}
    if($Value -is [System.Collections.IDictionary]){
        foreach($key in $Value.Keys){if([string]$key -ieq $Name){$Found.Value=$true;return $Value[$key]}}
        return $null
    }
    foreach($property in @($Value.PSObject.Properties)){if([string]$property.Name -ieq $Name){$Found.Value=$true;return $property.Value}}
    return $null
}
function Get-LifecyclePropertyNames {
    param([AllowNull()][object]$Value)
    if($null -eq $Value){return @()}
    if($Value -is [System.Collections.IDictionary]){return @($Value.Keys|ForEach-Object{[string]$_})}
    return @($Value.PSObject.Properties|ForEach-Object{[string]$_.Name})
}
function Test-LifecycleProperty {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][string]$Name)
    $found=$false;[void](Get-LifecycleProperty -Value $Value -Name $Name -Found ([ref]$found));return $found
}

function Get-DevFleetLifecycleRoleKind {
    param([Parameter(Mandatory)][string]$Role)
    switch -CaseSensitive ($Role) {
        'Primary / Desktop' { return 'Desktop' }
        'Laptop / Surrogate' { return 'Laptop' }
        default { throw "TERMINAL_FAILURE: unsupported product lifecycle role '$Role'." }
    }
}

function Get-DevFleetLifecycleStageMarkerPattern {
    param([string]$ExpectedComputeInstanceName,[string]$ExpectedVaultInstanceName)
    $substeps='multipass-resolved|isolation-verified|instance-present|instance-absent|instance-started|instance-launched|instance-ready|payload-transferred|payload-extracted'
    $alternatives=[Collections.Generic.List[string]]::new()
    $alternatives.Add('prereqs-(?:Desktop|Laptop)');$alternatives.Add('host-agent');$alternatives.Add('windows-tailscale')
    if($ExpectedComputeInstanceName -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){$alternatives.Add(('compute-{0}(?:-(?:{1}))?' -f [regex]::Escape($ExpectedComputeInstanceName),$substeps))}
    if($ExpectedVaultInstanceName -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){$alternatives.Add(('vault(?:-(?:{0}))?' -f $substeps))}
    return '^stage-(?:'+($alternatives -join '|')+')\.complete$'
}
function Test-DevFleetLifecycleStageMarkerName {
    param([Parameter(Mandatory)][string]$Name,[string]$ExpectedComputeInstanceName,[string]$ExpectedVaultInstanceName)
    return $Name -match (Get-DevFleetLifecycleStageMarkerPattern -ExpectedComputeInstanceName $ExpectedComputeInstanceName -ExpectedVaultInstanceName $ExpectedVaultInstanceName)
}

function Get-DevFleetProductObservationIdentity {
    param([Parameter(Mandatory)][object]$Context,[Parameter(Mandatory)][string]$Role)
    $roleKind=Get-DevFleetLifecycleRoleKind -Role $Role
    $workspaceFound=$false;$workspace=Get-LifecycleProperty $Context 'workspaceRoot' ([ref]$workspaceFound)
    if(-not $workspaceFound -or [string]::IsNullOrWhiteSpace([string]$workspace)){
        $runDirFound=$false;$runDir=Get-LifecycleProperty $Context 'runDir' ([ref]$runDirFound)
        if(-not $runDirFound -or [string]::IsNullOrWhiteSpace([string]$runDir)){throw 'TERMINAL_FAILURE: product compute identity has no workspace or run evidence root.'}
        $workspace=(Resolve-Path -LiteralPath (Join-Path ([string]$runDir) '..\..\..\..')).Path
    }else{$workspace=(Resolve-Path -LiteralPath ([string]$workspace)).Path}
    $configPath=Join-Path $workspace 'source\config\devfleet.config.json'
    $candidatePath=Join-Path $workspace 'CURRENT-CANDIDATE.json'
    if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw 'TERMINAL_FAILURE: exact candidate product configuration is missing.'}
    if(-not(Test-Path -LiteralPath $candidatePath -PathType Leaf)){throw 'TERMINAL_FAILURE: current candidate binding is missing.'}
    try{$candidate=Get-Content -LiteralPath $candidatePath -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'TERMINAL_FAILURE: current candidate binding is unreadable.'}
    if(-not [bool]$candidate.candidateIsCurrent -or [bool]$candidate.sourceChangedSinceCandidate -or [bool]$candidate.rebuildRequired -or [string]$candidate.shippingInputIdentity -cne [string]$candidate.candidateShippingInputIdentity){throw 'TERMINAL_FAILURE: current candidate binding does not authorize the product configuration.'}
    $configEntries=@($candidate.candidateShippingInputs|Where-Object{[string]$_.root -ceq 'source' -and ([string]$_.path -replace '\\','/') -ceq 'config/devfleet.config.json'})
    if($configEntries.Count -ne 1 -or [string]$configEntries[0].sha256 -notmatch '^[0-9a-f]{64}$'){throw 'TERMINAL_FAILURE: candidate product configuration inventory binding is missing or ambiguous.'}
    $configSha256=(Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($configSha256 -cne [string]$configEntries[0].sha256){throw 'TERMINAL_FAILURE: product configuration does not match the current candidate inventory.'}
    try{$config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'TERMINAL_FAILURE: exact candidate product configuration is unreadable.'}
    $primary=[string]$config.Primary.InstanceName;$failover=[string]$config.Failover.InstanceName;$vault=[string]$config.Vault.InstanceName
    foreach($entry in @([ordered]@{kind='Primary';name=$primary},[ordered]@{kind='Failover';name=$failover},[ordered]@{kind='Vault';name=$vault})){if([string]$entry.name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'){throw "TERMINAL_FAILURE: exact candidate $([string]$entry.kind) instance identity is missing or malformed."}}
    if(@(@($primary,$failover,$vault)|Select-Object -Unique).Count -ne 3){throw 'TERMINAL_FAILURE: candidate product instance identities are not unique.'}
    $contextConfigFound=$false;$contextConfig=Get-LifecycleProperty $Context 'config' ([ref]$contextConfigFound);$cleanupName=''
    if($contextConfigFound -and $contextConfig){$nestedFound=$false;$nested=Get-LifecycleProperty $contextConfig 'NestedLinux' ([ref]$nestedFound);if($nestedFound -and $nested){$cleanupFound=$false;$cleanupName=[string](Get-LifecycleProperty $nested 'Name' ([ref]$cleanupFound))}}
    if($cleanupName -and $cleanupName -in @($primary,$failover,$vault)){throw 'TERMINAL_FAILURE: product instance identity overlaps the harness cleanup identity.'}
    $compute=if($roleKind -ceq 'Desktop'){$primary}else{$failover};$vaultForRole=if($roleKind -ceq 'Laptop'){$vault}else{''}
    $targets=[Collections.Generic.List[object]]::new();$targets.Add([pscustomobject][ordered]@{instanceName=$compute;nodeRole=if($roleKind -ceq 'Desktop'){'primary'}else{'surrogate'};kind='compute'})
    if($vaultForRole){$targets.Add([pscustomobject][ordered]@{instanceName=$vaultForRole;nodeRole='vault';kind='vault'})}
    return [pscustomobject][ordered]@{role=$Role;roleKind=$roleKind;computeInstanceName=$compute;vaultInstanceName=$vaultForRole;targets=@($targets);candidateCommit=[string]$candidate.candidateGitCommit;shippingInputIdentity=[string]$candidate.shippingInputIdentity;configPath=$configPath;configSha256=$configSha256;cleanupInstanceName=$cleanupName}
}

function Get-DevFleetProductComputeInstanceName {
    param([Parameter(Mandatory)][object]$Context,[string]$Role='Primary / Desktop')
    return [string](Get-DevFleetProductObservationIdentity -Context $Context -Role $Role).computeInstanceName
}

function Resolve-DevFleetLifecycleStageMarkerObservation {
    param(
        [Parameter(Mandatory)][object]$Observation,
        [Parameter(Mandatory)][string]$AllowedPattern,
        [Parameter(Mandatory)][string]$ExpectedStageRole,
        [AllowEmptyString()][string]$TransactionId,
        [Parameter(Mandatory)][string]$PayloadSha256,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$InvocationStartUtc
    )
    $markersFound=$false;$markers=@(Get-LifecycleProperty $Observation 'stageMarkers' ([ref]$markersFound));if(-not $markersFound){$markers=@()}
    $errorsFound=$false;$existingErrors=@(Get-LifecycleProperty $Observation 'stageMarkerErrors' ([ref]$errorsFound));if(-not $errorsFound){$existingErrors=@()}
    $accepted=[Collections.Generic.List[object]]::new();$rejected=[Collections.Generic.List[object]]::new()
    foreach($existing in $existingErrors){$nameFound=$false;$name=[string](Get-LifecycleProperty $existing 'name' ([ref]$nameFound));$errorFound=$false;$detail=[string](Get-LifecycleProperty $existing 'error' ([ref]$errorFound));$rejected.Add([pscustomobject][ordered]@{name=if($nameFound){$name}else{''};error=if($errorFound -and $detail){$detail}else{'stage marker was rejected by the collector'}})}
    $start=[datetime]::MinValue;if(-not [datetime]::TryParse($InvocationStartUtc,[ref]$start)){throw 'TERMINAL_FAILURE: lifecycle invocation start is malformed.'};$start=$start.ToUniversalTime()
    foreach($marker in $markers){
        $nameFound=$false;$name=[string](Get-LifecycleProperty $marker 'name' ([ref]$nameFound));$reason=''
        if(-not $nameFound -or $name -notmatch $AllowedPattern){$reason='stage marker name is not allowlisted'}
        $values=[ordered]@{};foreach($field in @('transactionId','payloadSha256','action','role','stage','completedUtc')){$found=$false;$values[$field]=Get-LifecycleProperty $marker $field ([ref]$found);if(-not $found -and -not $reason){$reason='stage marker is malformed'}}
        $completed=[datetime]::MinValue;if(-not $reason -and (-not [datetime]::TryParse([string]$values.completedUtc,[ref]$completed) -or $completed.ToUniversalTime() -lt $start)){$reason='stage marker is stale, malformed, or not bound to the current lifecycle'}
        if(-not $reason -and (([string]$values.transactionId) -notmatch '^[0-9a-fA-F]{32}$' -or ([string]$values.payloadSha256) -cne $PayloadSha256 -or ([string]$values.action) -cne $Action -or ([string]$values.role) -cne $ExpectedStageRole -or ($TransactionId -and ([string]$values.transactionId) -cne $TransactionId) -or (([string]$values.stage)+'.complete') -cne $name)){$reason='stage marker is stale, malformed, or not bound to the current lifecycle'}
        if($reason){$rejected.Add([pscustomobject][ordered]@{name=$name;error=$reason});continue}
        $pathFound=$false;$path=[string](Get-LifecycleProperty $marker 'path' ([ref]$pathFound));$shaFound=$false;$sha=[string](Get-LifecycleProperty $marker 'sha256' ([ref]$shaFound));$lastWriteFound=$false;$lastWrite=[string](Get-LifecycleProperty $marker 'lastWriteUtc' ([ref]$lastWriteFound))
        $accepted.Add([pscustomobject][ordered]@{name=$name;path=if($pathFound){$path}else{''};transactionId=[string]$values.transactionId;payloadSha256=[string]$values.payloadSha256;action=[string]$values.action;role=[string]$values.role;stage=[string]$values.stage;completedUtc=$completed.ToUniversalTime().ToString('o');lastWriteUtc=if($lastWriteFound){$lastWrite}else{''};sha256=if($shaFound){$sha}else{''}})
    }
    $set={param($target,$name,$value)if($target -is [System.Collections.IDictionary]){$target[$name]=$value}else{$target|Add-Member -NotePropertyName $name -NotePropertyValue $value -Force}}
    &$set $Observation 'stageMarkers' @($accepted);&$set $Observation 'stageMarkerErrors' @($rejected)
    return $Observation
}

function Get-WpfFailureDescriptor {
    param([Parameter(Mandatory)][object]$Report)
    $errorFound=$false;$errorValue=Get-LifecycleProperty $Report 'error' ([ref]$errorFound)
    $classFound=$false;$classValue=Get-LifecycleProperty $Report 'failureClass' ([ref]$classFound)
    [pscustomobject]@{
        failureClass=if($classFound -and [string]$classValue){[string]$classValue}else{'UNCLASSIFIED_PRODUCT_FAILURE'}
        error=if($errorFound -and [string]$errorValue){[string]$errorValue}else{'WPF boundary returned no primary error.'}
    }
}

function Test-RebootBoundaryIdentity {
    param(
        [Parameter(Mandatory)][psobject]$PriorCheckpoint,
        [AllowNull()][psobject]$CurrentCheckpoint,
        [int]$MaxGeneration = 3
    )
    if (-not $CurrentCheckpoint) { return $false }
    foreach($required in @('checkpointGeneration','transactionId','action','role','payloadSha256','state')){if(-not (Test-LifecycleProperty -Value $CurrentCheckpoint -Name $required)){return $false}}
    # Exactly one product generation is allowed to authorize one reboot.  A
    # jump (for example 1 -> 3) is an ambiguous/foreign lifecycle and must
    # never be treated as a valid boundary.
    $found=$false;$currentGeneration=Get-LifecycleProperty $CurrentCheckpoint 'checkpointGeneration' ([ref]$found);if(-not $found){return $false};$found=$false;$priorGenerationValue=Get-LifecycleProperty $PriorCheckpoint 'checkpointGeneration' ([ref]$found);if(-not $found){return $false};$generation=0;$priorGeneration=0;if(-not [int]::TryParse([string]$currentGeneration,[ref]$generation)-or-not [int]::TryParse([string]$priorGenerationValue,[ref]$priorGeneration)){return $false}
    # checkpointGeneration -ne PriorCheckpoint.checkpointGeneration + 1 is
    # the fail-closed rule (expressed with parsed numeric values below).
    if ($generation -ne ($priorGeneration + 1)) { return $false }
    if ($generation -gt $MaxGeneration) { return $false }
    foreach ($name in @('transactionId','action','role','payloadSha256')) {
        $currentFound=$false;$currentValue=Get-LifecycleProperty $CurrentCheckpoint $name ([ref]$currentFound);$priorFound=$false;$priorValue=Get-LifecycleProperty $PriorCheckpoint $name ([ref]$priorFound);if(-not $currentFound -or -not $priorFound -or [string]$currentValue -cne [string]$priorValue) { return $false }
    }
    $found=$false;$state=Get-LifecycleProperty $CurrentCheckpoint 'state' ([ref]$found);return ($found -and [string]$state -eq 'waiting-for-reboot')
}

function ConvertTo-CanonicalLifecycleCheckpoint {
    param([AllowNull()][object]$Checkpoint)
    if(-not $Checkpoint){return $null}
    $hasCheckpointGeneration=Test-LifecycleProperty -Value $Checkpoint -Name 'checkpointGeneration'
    $hasGeneration=Test-LifecycleProperty -Value $Checkpoint -Name 'generation'
    if(-not $hasCheckpointGeneration -and -not $hasGeneration){return $null}
    $checkpointGeneration=0;$generation=0
    $found=$false;$checkpointGenerationValue=Get-LifecycleProperty $Checkpoint 'checkpointGeneration' ([ref]$found);if($hasCheckpointGeneration -and -not [int]::TryParse([string]$checkpointGenerationValue,[ref]$checkpointGeneration)){return $null}
    $found=$false;$generationValue=Get-LifecycleProperty $Checkpoint 'generation' ([ref]$found);if($hasGeneration -and -not [int]::TryParse([string]$generationValue,[ref]$generation)){return $null}
    if(-not $hasCheckpointGeneration){$checkpointGeneration=$generation}
    if(-not $hasGeneration){$generation=$checkpointGeneration}
    if($generation -ne $checkpointGeneration){return $null}
    $copy=[ordered]@{}
    if($Checkpoint -is [System.Collections.IDictionary]){foreach($key in $Checkpoint.Keys){$copy[[string]$key]=$Checkpoint[$key]}}else{foreach($property in $Checkpoint.PSObject.Properties){$copy[$property.Name]=$property.Value}}
    $copy.generation=$generation
    $copy.checkpointGeneration=$checkpointGeneration
    return [pscustomobject]$copy
}

function Test-NoActiveProductCheckpoint {
    param([AllowNull()][object]$Value,[int]$Depth=0,[System.Collections.Generic.HashSet[int]]$Seen,[string]$Path='root')
    if($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive -or $Value -is [datetime] -or $Value -is [guid]){return $true}
    if($Depth -gt 12){return $false}
    if(-not $Seen){$Seen=[System.Collections.Generic.HashSet[int]]::new()};$identity=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Value);if(-not $Seen.Add($identity)){return $false}
    # IDictionary (including [ordered] test/projection payloads) is enumerable,
    # but its entries are lifecycle fields rather than a signal-free list. Walk
    # entries by key so generation/checkpoint fields cannot be hidden, while
    # avoiding the false cycle reports caused by enumerating dictionary views.
    if($Value -is [System.Collections.IDictionary]){
        foreach($entry in $Value.GetEnumerator()){
            $lower=([string]$entry.Key).ToLowerInvariant();$item=$entry.Value;$childPath=if($Path -eq 'root'){([string]$entry.Key)}else{"$Path.$([string]$entry.Key)"}
            if($lower -eq 'rawactivelifecyclesignals' -and $item -and @($item).Count -gt 0){foreach($signal in @($item)){$kindFound=$false;$kind=Get-LifecycleProperty $signal 'kind' ([ref]$kindFound);$pathFound=$false;$signalPath=Get-LifecycleProperty $signal 'path' ([ref]$pathFound);$valueFound=$false;$signalValue=Get-LifecycleProperty $signal 'value' ([ref]$valueFound);$zero=0;$benign=($kindFound -and [string]$kind -ieq 'checkpointgeneration' -and $pathFound -and [string]$signalPath -eq 'progress.checkpointGeneration' -and [int]::TryParse([string]$signalValue,[ref]$zero) -and $zero -eq 0 -and [string]$signalValue -match '^0$');if(-not $benign){return $false}}}
            if($lower -eq 'checkpoint' -and $null -ne $item){return $false}
            if($lower -eq 'checkpointpresent' -and [bool]$item){return $false}
            if($lower -in @('checkpointgeneration','generation')){$zeroValue=0;$zeroAllowed=($lower -eq 'checkpointgeneration' -and ($Path -eq 'progress' -or $Path -match '\.progress$') -and [int]::TryParse([string]$item,[ref]$zeroValue) -and $zeroValue -eq 0 -and [string]$item -match '^0$');if(-not $zeroAllowed){return $false}}
            if($lower -eq 'state' -and [string]$item -ieq 'waiting-for-reboot'){return $false}
            if($lower -in @('installledger','ownershipledger','installstate','ownership','receipt')){continue}
            $childSeen=[System.Collections.Generic.HashSet[int]]::new($Seen);if(-not (Test-NoActiveProductCheckpoint -Value $item -Depth ($Depth+1) -Seen $childSeen -Path $childPath)){return $false}
        }
        return $true
    }
    if($Value -is [System.Collections.IEnumerable]){foreach($item in $Value){$childSeen=[System.Collections.Generic.HashSet[int]]::new($Seen);if(-not (Test-NoActiveProductCheckpoint -Value $item -Depth ($Depth+1) -Seen $childSeen -Path ($Path+'[]'))){return $false}};return $true}
    foreach($property in @($Value.PSObject.Properties)){
        $name=[string]$property.Name;$item=$property.Value;$lower=$name.ToLowerInvariant()
        if($lower -eq 'rawactivelifecyclesignals' -and $item -and @($item).Count -gt 0){foreach($signal in @($item)){$kindFound=$false;$kind=Get-LifecycleProperty $signal 'kind' ([ref]$kindFound);$pathFound=$false;$signalPath=Get-LifecycleProperty $signal 'path' ([ref]$pathFound);$valueFound=$false;$signalValue=Get-LifecycleProperty $signal 'value' ([ref]$valueFound);$zero=0;$benign=($kindFound -and [string]$kind -ieq 'checkpointgeneration' -and $pathFound -and [string]$signalPath -eq 'progress.checkpointGeneration' -and [int]::TryParse([string]$signalValue,[ref]$zero) -and $zero -eq 0 -and [string]$signalValue -match '^0$');if(-not $benign){return $false}}}
        if($lower -eq 'checkpoint' -and $null -ne $item){return $false}
        if($lower -eq 'checkpointpresent' -and [bool]$item){return $false}
        if($lower -in @('checkpointgeneration','generation')){
            $zeroValue=0;$zeroAllowed=($lower -eq 'checkpointgeneration' -and ($Path -eq 'progress' -or $Path -match '\.progress$') -and [int]::TryParse([string]$item,[ref]$zeroValue) -and $zeroValue -eq 0 -and [string]$item -match '^0$');if(-not $zeroAllowed){return $false}
        }
        if($lower -eq 'state' -and [string]$item -ieq 'waiting-for-reboot'){return $false}
        if($lower -in @('installledger','ownershipledger','installstate','ownership','receipt')){continue}
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
                    [pscustomobject]@{name=$log.Name;bytes=$log.Length;lastWriteUtc=$log.LastWriteTimeUtc.ToString('o');tail=(@(Get-Content -LiteralPath $log.FullName -Tail 80)-join "`n");lineLimit=80;tailOnly=$true}
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
        $checkpoint=$generation.reboot.checkpoint
        if([int]$generation.generation -ne $number -or [string]$generation.invocationId -cne $lineage -or [string]$checkpoint.transactionId -cne $tx -or [string]$checkpoint.payloadSha256 -cne $payload -or [string]$checkpoint.role -cne $ExpectedRole -or [string]$checkpoint.action -cne 'FreshInstall' -or -not [bool]$generation.reboot.bootIdentityChanged -or [string]$generation.resume.status -cne 'REAL E2E OBSERVER HANDOFF'){throw 'Exact proof reboot evidence lacks the bound transaction, changed boot, or resumed WPF handoff.'}
        $records.Add([ordered]@{file=$file;sha256=[string]$reference.sha256})
    }
    for($number=1;$number -le $seen.Count;$number++){if(-not $seen.Contains($number)){throw 'Exact proof checkpoint generations are not contiguous.'}}
    return [ordered]@{schemaVersion=1;role=$ExpectedRole;phaseId=$expectedPhase;transactionId=$tx;checkpointLineageId=$lineage;payloadSha256=$payload;roleEvidence=$roleEvidence;evidence=@($records)}
}

function Write-ProductLifecycleTerminalEvidence {
    param(
        [Parameter(Mandatory)][string]$InvocationDir,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$InvocationId,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$LastStableStep,
        [Parameter(Mandatory)][string]$ErrorMessage,
        [string]$TransactionId,
        [string]$PayloadSha256,
        [string]$Action='FreshInstall',
        [string]$Role='Primary / Desktop',
        [string]$Outcome='TERMINAL_FAILURE',
        [object]$Detail,
        [System.Collections.IDictionary]$SafeFailure
    )
    $now=(Get-Date).ToUniversalTime().ToString('o')
    $journalPath=Join-Path $InvocationDir 'product-lifecycle-progress.jsonl'
    $currentPath=Join-Path $InvocationDir 'product-lifecycle-progress-current.json'
    $terminalPath=Join-Path $InvocationDir 'product-lifecycle-terminal.json'
    $providerPath=Join-Path $InvocationDir 'product-lifecycle-provider-failure.json'
    $entry=[ordered]@{event='TERMINAL';terminalReason=$Outcome;status=$Outcome;completionVerified=$false;phase=$Phase;invocationId=$InvocationId;provider=$Provider;lastStableStep=$LastStableStep;error=$ErrorMessage;timestampUtc=$now;transactionId=$TransactionId;payloadSha256=$PayloadSha256;action=$Action;role=$Role}
    if($Detail){$entry.detail=$Detail}
    if($SafeFailure){$entry.safeFailure=$SafeFailure}
    New-Item -ItemType Directory -Path $InvocationDir -Force|Out-Null
    Add-Content -LiteralPath $journalPath -Value ($entry|ConvertTo-Json -Compress -Depth 24) -Encoding UTF8
    Write-EvidenceJson -Path $currentPath -Value $entry
    Write-EvidenceJson -Path $terminalPath -Value $entry
    $providerEntry=[ordered]@{status=$Outcome;contract='product-lifecycle-provider-failure';phase=$Phase;invocationId=$InvocationId;provider=$Provider;lastStableStep=$LastStableStep;error=$ErrorMessage;evidencePath=$terminalPath;terminalEvidencePath=$terminalPath;providerFailurePath=$providerPath;progressJournalPath=$journalPath;progressCurrentPath=$currentPath;timestampUtc=$now}
    if($Detail){$providerEntry.detail=$Detail}
    if($SafeFailure){$providerEntry.safeFailure=$SafeFailure}
    Write-EvidenceJson -Path $providerPath -Value $providerEntry
    return [pscustomobject]$providerEntry
}

function Get-SafeGuestSessionFailureMetadata {
    param([AllowNull()][System.Exception]$Exception)
    $allowedCodes=@('LAB_GUEST_AUTHENTICATION_REJECTED','LAB_SESSION_ACCESS_DENIED','LAB_SESSION_OPEN_TIMEOUT','LAB_SESSION_TRANSPORT_FAILED','LAB_SESSION_OPEN_FAILED')
    $current=$Exception;$depth=0
    while($null -ne $current -and $depth -lt 8){
        $candidate=$current;$current=$current.InnerException;$depth++
        if($null -eq $candidate.Data -or -not $candidate.Data.Contains('failureCode')){continue}
        $code=[string]$candidate.Data['failureCode'];$attempt=0
        if($code -notin $allowedCodes -or -not [int]::TryParse([string]$candidate.Data['attemptCount'],[ref]$attempt) -or $attempt -lt 1 -or $attempt -gt 3){continue}
        $auth=[string]$candidate.Data['authenticationOutcome'];if($auth -notin @('UNVERIFIED','REJECTED')){continue}
        if([string]$candidate.Data['credentialFreshness'] -cne 'UNVERIFIED'){continue}
        $safe=[ordered]@{failureCode=$code;attemptCount=$attempt;authenticationOutcome=$auth;credentialFreshness='UNVERIFIED'}
        $nativeCode=0
        if([int]::TryParse([string]$candidate.Data['nativeErrorCode'],[ref]$nativeCode) -and $nativeCode -ge 0 -and $nativeCode -le 65535){$safe.nativeErrorCode=$nativeCode}
        return $safe
    }
    return $null
}

function Invoke-ProductFreshInstallLifecycle {
    <# One product-owned loop. Synthetic reboot state is intentionally absent.
       MaxRebootBoundaries limits product reboots, not the final observation
       after the last WPF resume. Provider seams are test-only and retain all
       production binding/ordering checks around their results. #>
    param(
        [Parameter(Mandatory)][psobject]$Context,
        [string]$Role='Primary / Desktop',
        [psobject]$InitialResult,
        [scriptblock]$WpfProvider,
        [scriptblock]$TransitionProvider,
        [scriptblock]$RebootProvider,
        [scriptblock]$SettleProvider,
        [scriptblock]$RemoteObservationProvider,
        [scriptblock]$GuestMarkerReadProvider,
        [object]$ObservationAdapterContext,
        [scriptblock]$OAuthCredentialCleanupProvider
    )
    if(-not $WpfProvider -and (Test-LifecycleProperty -Value $Context -Name 'lifecycleWpfProvider')){$found=$false;$WpfProvider=Get-LifecycleProperty $Context 'lifecycleWpfProvider' ([ref]$found)};if(-not $TransitionProvider -and (Test-LifecycleProperty -Value $Context -Name 'lifecycleTransitionProvider')){$found=$false;$TransitionProvider=Get-LifecycleProperty $Context 'lifecycleTransitionProvider' ([ref]$found)};if(-not $RebootProvider -and (Test-LifecycleProperty -Value $Context -Name 'lifecycleRebootProvider')){$found=$false;$RebootProvider=Get-LifecycleProperty $Context 'lifecycleRebootProvider' ([ref]$found)};if(-not $SettleProvider -and (Test-LifecycleProperty -Value $Context -Name 'lifecycleSettleProvider')){$found=$false;$SettleProvider=Get-LifecycleProperty $Context 'lifecycleSettleProvider' ([ref]$found)}
    $candidate=Assert-ExactCandidate $Context
    $expectedPayload=[string]$Context.candidate.tar.sha256
    $expectedVersion=[string]$Context.candidate.releaseVersion
    $expectedInstaller=[string]$Context.candidate.installerVersion
    if($expectedPayload -notmatch '^[0-9a-fA-F]{64}$'){throw 'TERMINAL_FAILURE: lifecycle payload identity is missing.'}
    if($expectedVersion -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$' -or $expectedInstaller -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$'){throw 'TERMINAL_FAILURE: lifecycle version identity is missing or malformed.'}
    $invocationStart=(Get-Date).ToUniversalTime().ToString('o')
    # Provider-driven behavioral tests never cross the real observation
    # boundary. Production owns the identity lookup and fails closed before
    # the first authenticated observation if the exact candidate config is
    # unavailable or malformed.
    $productIdentity=if($TransitionProvider){$null}else{Get-DevFleetProductObservationIdentity -Context $Context -Role $Role}
    $expectedComputeInstanceName=if($productIdentity){[string]$productIdentity.computeInstanceName}else{''};$expectedVaultInstanceName=if($productIdentity){[string]$productIdentity.vaultInstanceName}else{''}
    $contextPhaseFound=$false;$contextPhaseValue=Get-LifecycleProperty $Context 'phaseId' ([ref]$contextPhaseFound);$rawPhase=if($contextPhaseFound){[string]$contextPhaseValue}else{'PRODUCT-LIFECYCLE'}
    $logicalPhase=$rawPhase
    $safePhase=($rawPhase -replace '[^A-Za-z0-9_.-]','_').Trim('_');if(-not $safePhase){$safePhase='PRODUCT-LIFECYCLE'}
    $invocationId=[guid]::NewGuid().ToString('N')
    $invocationDir=Join-Path ([string]$Context.runDir) ("lifecycle-{0}-{1}" -f $safePhase,$invocationId)
    New-Item -ItemType Directory -Path $invocationDir -Force|Out-Null
    $contextConfigFound=$false;$contextConfig=Get-LifecycleProperty $Context 'config' ([ref]$contextConfigFound);$contextBudgetFound=$false;$contextBudget=Get-LifecycleProperty $Context 'phaseBudgetSeconds' ([ref]$contextBudgetFound)
    $lifeContext=[ordered]@{logicalPhaseId=$logicalPhase;phaseId=("{0}-{1}" -f $safePhase,$invocationId);lifecycleInvocationId=$invocationId;runDir=$invocationDir;vmId=$Context.vmId;vmName=$Context.vmName;candidate=$Context.candidate;config=$contextConfig;phaseBudgetSeconds=$contextBudget;invocationStartUtc=$invocationStart;expectedProductComputeInstanceName=$expectedComputeInstanceName;expectedProductVaultInstanceName=$expectedVaultInstanceName;expectedProductTargets=if($productIdentity){@($productIdentity.targets)}else{@()};productConfigSha256=if($productIdentity){[string]$productIdentity.configSha256}else{''}}
    if($Context -is [System.Collections.IDictionary]){foreach($key in $Context.Keys){if(-not $lifeContext.Contains([string]$key)){$lifeContext[[string]$key]=$Context[$key]}}}else{foreach($prop in @($Context.PSObject.Properties)){if(-not $lifeContext.Contains($prop.Name)){$lifeContext[$prop.Name]=$prop.Value}}}
    $lifeContext=[pscustomobject]$lifeContext
    $transactionId=''
    $providerFailure={param($kind,$message,$step,$detail,$safeFailure)$failure=Write-ProductLifecycleTerminalEvidence -InvocationDir ([string]$lifeContext.runDir) -Phase $logicalPhase -InvocationId $invocationId -Provider $kind -LastStableStep $step -ErrorMessage $message -TransactionId $transactionId -PayloadSha256 $expectedPayload -Action 'FreshInstall' -Role $Role -Detail $detail -SafeFailure $safeFailure;$failure|Add-Member -NotePropertyName completionVerified -NotePropertyValue $false -Force;$failure|Add-Member -NotePropertyName evidencePath -NotePropertyValue (Join-Path ([string]$lifeContext.runDir) 'product-lifecycle-terminal.json') -Force;return $failure}
    $callProvider={param($provider,$state,$kind,$required)$value=$null;try{$value=&$provider $state;if(-not $value){throw "$kind returned null"};if($required -and -not (Test-LifecycleProperty -Value $value -Name $required)){throw "$kind result lacks $required"};[ordered]@{ok=$true;value=$value}}catch{[ordered]@{ok=$false;error=$_.Exception.Message}}}
    try {
    if($InitialResult){$current=$InitialResult}elseif($WpfProvider){$wpfCall=&$callProvider $WpfProvider ([pscustomobject]@{context=$lifeContext;role=$Role;action='FreshInstall';generation=0;invocationId=$invocationId}) 'WpfProvider' 'status';if(-not $wpfCall.ok){return &$providerFailure 'WpfProvider' $wpfCall.error 'initial-WPF'};$current=$wpfCall.value}else{try{$current=Invoke-ActualWpfAction -Context $lifeContext -Action 'FreshInstall' -Role $Role -EvidenceLabel 'initial-FreshInstall' -LaunchMode 'initial' -AllowMutation -AllowRebootRequired -UseDurableCompletionFallback -DeferDurableCompletionFallback -DeferOAuthCredentialCleanup -ElevatedResume:$false}catch{return &$providerFailure 'WpfProvider' $_.Exception.Message 'initial-WPF'}}
    if($current -is [System.Collections.IDictionary]){$current=[pscustomobject]$current}
    if(-not $current){return &$providerFailure 'WpfProvider' 'WPF result was null' 'initial-WPF'}
    $currentProperties=Get-LifecyclePropertyNames $current;$found=$false;$currentStatus=Get-LifecycleProperty $current 'status' ([ref]$found);if(-not $found){return &$providerFailure 'WpfProvider' 'WPF result lacks status' 'initial-WPF'}
    if([string]$currentStatus -notin @('REAL E2E PASS','REAL E2E REBOOT REQUIRED','REAL E2E OBSERVER HANDOFF')){return &$providerFailure 'WpfProvider' "WPF result returned unsupported status $([string]$currentStatus)" 'initial-WPF'}
    $legs=[System.Collections.Generic.List[object]]::new();$max=3;$priorGeneration=0;$transactionId='';$rebootCount=0;$checkpoint=$null
    while($true) {
        [void]$legs.Add($current)
        $found=$false;$currentGuest=Get-LifecycleProperty $current 'guest' ([ref]$found);$guestFound=$false;$guestCompleted=Get-LifecycleProperty $currentGuest 'completionVerified' ([ref]$guestFound);$currentCompleted=($currentGuest -and $guestFound -and [bool]$guestCompleted)
        $found=$false;$currentStatus=Get-LifecycleProperty $current 'status' ([ref]$found)
        if([string]$currentStatus -eq 'REAL E2E PASS' -and $currentCompleted){
            $completionReason='';if(-not (Test-LifecycleCompletionInput -Value $current -Reason ([ref]$completionReason))){return &$providerFailure 'WpfProvider' "immediate WPF PASS rejected: $completionReason" ("generation-{0}" -f $priorGeneration)}
            try{$verifySession=$null;try{$verifySession=Connect-DevFleetGuest -VmId ([guid][string]$lifeContext.vmId);$verification=Get-ProductLifecycleObservation -Session $verifySession -TransactionId $transactionId -PayloadSha256 $expectedPayload -Action 'FreshInstall' -Role $Role -ExpectedDevFleetVersion $expectedVersion -ExpectedInstallerVersion $expectedInstaller -ObservationTimeoutSeconds 30 -InvocationStartUtc $invocationStart -ExpectedComputeInstanceName ([string]$lifeContext.expectedProductComputeInstanceName) -ExpectedVaultInstanceName ([string]$lifeContext.expectedProductVaultInstanceName) -ExpectedNestedLinuxName ([string]$lifeContext.config.NestedLinux.Name)}finally{if($verifySession){Remove-DevFleetGuestSession $verifySession -ErrorAction SilentlyContinue}}
                if(-not $verification.installStateValid -or -not $verification.canonicalOwnershipValid -or -not $verification.authenticatedHealthOk -or -not $verification.matchingConsumedReceipt){throw 'immediate WPF PASS could not be bound to current installer/receipt/ownership/health ledgers.'}
                if(-not $transactionId -and $verification.receipt){$transactionId=[string]$verification.receipt.transactionId};if($transactionId -notmatch '^[0-9a-fA-F]{32}$'){throw 'immediate WPF PASS has no exact consumed transaction receipt.'}
                $authority=New-ProductLifecycleCompletionAuthority -Context $lifeContext -Candidate $Context.candidate -Role $Role -TransactionId $transactionId -PayloadSha256 $expectedPayload -Observation $verification -Legs @($legs);Write-EvidenceJson -Path $authority.evidencePath -Value $authority;return $authority
            }catch{return &$providerFailure 'CompletionVerification' $_.Exception.Message ("generation-{0}" -f $priorGeneration)}
        }
        if([string]$currentStatus -notin @('REAL E2E REBOOT REQUIRED','REAL E2E OBSERVER HANDOFF')){return &$providerFailure 'WpfProvider' "WPF result returned unsupported status $([string]$currentStatus)" ("generation-{0}" -f $priorGeneration)}
        $tx=$transactionId;if($tx -and $tx -notmatch '^[0-9a-fA-F]{32}$'){return &$providerFailure 'TransitionProvider' 'product transaction identity is malformed' ("generation-{0}" -f $priorGeneration)}
        $observer=$null
        if($TransitionProvider){
            $transitionCall=&$callProvider $TransitionProvider ([pscustomobject]@{context=$lifeContext;transactionId=$tx;payloadSha256=$expectedPayload;action='FreshInstall';role=$Role;priorGeneration=$priorGeneration;maxGeneration=$max;generation=$priorGeneration;invocationId=$invocationId}) 'TransitionProvider' 'outcome';if(-not $transitionCall.ok){return &$providerFailure 'TransitionProvider' $transitionCall.error ("WPF-generation-{0}" -f $priorGeneration)};$transition=$transitionCall.value
            if($transition -is [System.Collections.IDictionary]){$transition=[pscustomobject]$transition}
            if(-not (Test-LifecycleProperty -Value $transition -Name 'outcome')){return &$providerFailure 'TransitionProvider' 'transition provider result lacks outcome' ("WPF-generation-{0}" -f $priorGeneration)}
            $found=$false;$outcomeValue=Get-LifecycleProperty $transition 'outcome' ([ref]$found);$outcome=[string]$outcomeValue
            if($outcome -notin @('COMPLETED','NEXT_REBOOT','TERMINAL_FAILURE','NO_PROGRESS_TIMEOUT','ABSOLUTE_TIMEOUT')){return &$providerFailure 'TransitionProvider' 'transition provider returned an unknown outcome' ("WPF-generation-{0}" -f $priorGeneration)}
            if($outcome -eq 'NEXT_REBOOT' -and -not (Test-LifecycleProperty -Value $transition -Name 'checkpoint')){return &$providerFailure 'TransitionProvider' 'NEXT_REBOOT result lacks checkpoint' ("WPF-generation-{0}" -f $priorGeneration)}
            if($outcome -in @('COMPLETED','TERMINAL_FAILURE','NO_PROGRESS_TIMEOUT','ABSOLUTE_TIMEOUT') -and -not (Test-LifecycleProperty -Value $transition -Name 'observation')){$transition|Add-Member -NotePropertyName observation -NotePropertyValue ([pscustomobject]@{}) -Force}
            $found=$false;$transitionCheckpoint=Get-LifecycleProperty $transition 'checkpoint' ([ref]$found);$checkpoint=if($found){ConvertTo-CanonicalLifecycleCheckpoint $transitionCheckpoint}else{$null}
            $topCheckpointFound=$false;$topCheckpointValue=Get-LifecycleProperty $transition 'checkpoint' ([ref]$topCheckpointFound);$topFlagFound=$false;$topFlagValue=Get-LifecycleProperty $transition 'checkpointPresent' ([ref]$topFlagFound);$topActualPresent=($topCheckpointFound -and $null -ne $topCheckpointValue);if($topFlagFound -and ([bool]$topFlagValue) -ne $topActualPresent){return &$providerFailure 'TransitionProvider' 'transition checkpointPresent flag disagrees with top-level checkpoint object' ("WPF-generation-{0}" -f $priorGeneration)};if($topActualPresent -and -not $topFlagFound){return &$providerFailure 'TransitionProvider' 'transition checkpoint object has no checkpointPresent flag' ("WPF-generation-{0}" -f $priorGeneration)};if($outcome -eq 'NEXT_REBOOT' -and (-not $topFlagFound -or -not [bool]$topFlagValue)){return &$providerFailure 'TransitionProvider' 'NEXT_REBOOT transition lacks an affirmative top-level checkpointPresent binding' ("WPF-generation-{0}" -f $priorGeneration)}
            if($outcome -eq 'NEXT_REBOOT' -and -not $checkpoint){return &$providerFailure 'TransitionProvider' 'transition provider returned a malformed checkpoint schema' ("WPF-generation-{0}" -f $priorGeneration)}
            if($checkpoint -and -not $tx){$tx=[string]$checkpoint.transactionId}
            if($tx -and $tx -notmatch '^[0-9a-fA-F]{32}$'){return &$providerFailure 'TransitionProvider' 'product transaction identity is malformed' ("WPF-generation-{0}" -f $priorGeneration)}
            if($checkpoint -and -not (Test-RebootBoundaryIdentity -PriorCheckpoint ([pscustomobject]@{checkpointGeneration=$priorGeneration;transactionId=$tx;payloadSha256=$expectedPayload;action='FreshInstall';role=$Role;state='waiting-for-reboot'}) -CurrentCheckpoint $checkpoint -MaxGeneration $max)){return &$providerFailure 'TransitionProvider' ("transition provider returned an inexact checkpoint boundary: checkpoint=$($checkpoint|ConvertTo-Json -Compress -Depth 8); tx=$tx; expectedPayload=$expectedPayload; prior=$priorGeneration") ("WPF-generation-{0}" -f $priorGeneration)}
            $transitionObservationFound=$false;$transitionObservation=Get-LifecycleProperty $transition 'observation' ([ref]$transitionObservationFound);if($transitionObservationFound){$bindingReason='';if(-not (Test-LifecycleTransitionObservationBinding -Observation $transitionObservation -Checkpoint $checkpoint -Reason ([ref]$bindingReason))){return &$providerFailure 'TransitionProvider' $bindingReason ("WPF-generation-{0}" -f $priorGeneration)}}
            if($checkpoint){$transition.checkpoint=$checkpoint}
            if($outcome -eq 'COMPLETED'){$completionReason='';if(-not (Test-LifecycleCompletionInput -Value $transition -Reason ([ref]$completionReason))){return &$providerFailure 'TransitionProvider' "COMPLETED transition rejected: $completionReason" ("WPF-generation-{0}" -f $priorGeneration)}}
            $observer=$transition
        }else{
            # Observe from generation zero.  The earlier checkpoint-only poll
            # hid the exact child lifetime, CPU/stage movement, servicing
            # state, and normal-completion path for up to 30 minutes.  The
            # bounded observer can safely begin with an unknown transaction;
            # it adopts the transaction only from a fully candidate-bound
            # checkpoint or consumed receipt.
            $checkpoint=[pscustomobject]@{generation=$priorGeneration;checkpointGeneration=$priorGeneration;transactionId=$tx;payloadSha256=$expectedPayload;action='FreshInstall';role=$Role;state='waiting-for-reboot'}
            try {
                $observerSession=$null;$usingObservationAdapters=[bool]($RemoteObservationProvider -or $GuestMarkerReadProvider)
                try {
                    $observerSession=if($usingObservationAdapters){[pscustomobject]@{fixture=$true}}else{Connect-DevFleetGuest -VmId ([guid][string]$lifeContext.vmId)}
                    $guestFound=$false;$guestProcessId=Get-LifecycleProperty $currentGuest 'processId' ([ref]$guestFound);if(-not $guestFound){$guestProcessId=Get-LifecycleProperty $current 'processId' ([ref]$guestFound)};$candidateProcessId=if($guestFound){[int]$guestProcessId}else{0}
                    $policy=Get-HarnessBudgetPolicy -Config $lifeContext.config;$transactionBudget=if($Role -ceq 'Laptop / Surrogate'){[int]$policy.transactionBudgetsSeconds.Laptop}else{[int]$policy.transactionBudgetsSeconds.Desktop};$observerAbsoluteBudget=if($Role -ceq 'Laptop / Surrogate'){[int]$policy.observerAbsoluteBudgetsSeconds.Laptop}else{[int]$policy.observerAbsoluteBudgetsSeconds.Desktop};$observerOwnerDeadline=(ConvertTo-WpfUtcInstant $invocationStart).AddSeconds($observerAbsoluteBudget)
                    $sessionProvider=if($usingObservationAdapters){$null}else{{Connect-DevFleetGuest -VmId ([guid][string]$lifeContext.vmId)}}
                    $observer=Wait-DevFleetProductLifecycleTransition -Session $observerSession -SessionProvider $sessionProvider -TransactionId $tx -PayloadSha256 $expectedPayload -Action 'FreshInstall' -Role $Role -PriorGeneration $priorGeneration -MaxGeneration $max -BudgetSeconds $transactionBudget -NoProgressBudgetSeconds ([int]$policy.observerNoProgressBudgetSeconds) -AbsoluteBudgetSeconds $observerAbsoluteBudget -AbsoluteDeadlineUtc $observerOwnerDeadline.ToString('o') -CandidateProcessId $candidateProcessId -ExpectedDevFleetVersion $expectedVersion -ExpectedInstallerVersion $expectedInstaller -ObservationTimeoutSeconds 30 -EvidencePath (Join-Path ([string]$lifeContext.runDir) ("product-lifecycle-observer-generation-{0}.json" -f $priorGeneration)) -InvocationStartUtc $invocationStart -ExpectedComputeInstanceName ([string]$lifeContext.expectedProductComputeInstanceName) -ExpectedVaultInstanceName ([string]$lifeContext.expectedProductVaultInstanceName) -ExpectedNestedLinuxName ([string]$lifeContext.config.NestedLinux.Name) -RemoteObservationProvider $RemoteObservationProvider -GuestMarkerReadProvider $GuestMarkerReadProvider -ObservationAdapterContext $ObservationAdapterContext
                } finally {if(-not $usingObservationAdapters -and $observerSession){Remove-DevFleetGuestSession $observerSession -ErrorAction SilentlyContinue}}
            } catch {$caught=$_.Exception;$safeFailure=Get-SafeGuestSessionFailureMetadata -Exception $caught;return &$providerFailure 'TransitionObserver' $caught.Message ("generation-{0}" -f $priorGeneration) $null $safeFailure}
            $observerCheckpointFound=$false;$observerCheckpoint=Get-LifecycleProperty $observer 'checkpoint' ([ref]$observerCheckpointFound);if($observerCheckpointFound -and $observerCheckpoint){$checkpoint=$observerCheckpoint}
            if(-not $tx){
                if($checkpoint -and [int]$checkpoint.checkpointGeneration -gt 0){$tx=[string]$checkpoint.transactionId}
                else{$observerObservationFound=$false;$observerObservation=Get-LifecycleProperty $observer 'observation' ([ref]$observerObservationFound);if($observerObservationFound -and $observerObservation -and $observerObservation.matchingConsumedReceipt -and $observerObservation.receipt){$tx=[string]$observerObservation.receipt.transactionId}}
                if($tx -and $tx -notmatch '^[0-9a-fA-F]{32}$'){return &$providerFailure 'TransitionObserver' 'observer returned a malformed product transaction identity' ("generation-{0}" -f $priorGeneration)}
            }
        }
        $observerEvidenceGeneration=if($checkpoint){[int]$checkpoint.generation}else{$priorGeneration};$observerSummaryPath=Join-Path ([string]$lifeContext.runDir) ("product-lifecycle-observer-generation-{0}.json" -f $observerEvidenceGeneration);if($TransitionProvider){Write-EvidenceJson -Path $observerSummaryPath -Value $observer}
        $transactionId=$tx
        $lifeContext | Add-Member -NotePropertyName lifecycleTransactionId -NotePropertyValue $transactionId -Force
        $found=$false;$observerOutcome=Get-LifecycleProperty $observer 'outcome' ([ref]$found);if([string]$observerOutcome -eq 'COMPLETED'){try{$found=$false;$observerObservation=Get-LifecycleProperty $observer 'observation' ([ref]$found);$authority=New-ProductLifecycleCompletionAuthority -Context $lifeContext -Candidate $Context.candidate -Role $Role -TransactionId $tx -PayloadSha256 $expectedPayload -Observation $observerObservation -Legs @($legs);Write-EvidenceJson -Path $authority.evidencePath -Value $authority;return $authority}catch{return &$providerFailure 'TransitionProvider' $_.Exception.Message ("generation-{0}" -f $priorGeneration)}}
        if([string]$observerOutcome -notin @('NEXT_REBOOT')){return &$providerFailure 'TransitionProvider' "$([string]$observerOutcome): product lifecycle observer stopped at generation $priorGeneration." ("generation-{0}" -f $priorGeneration)}
        if(-not $checkpoint -or [int]$checkpoint.generation -gt $max){return &$providerFailure 'TransitionProvider' 'generation 4 product reboot requested; MaxRebootBoundaries is 3' ("generation-{0}" -f $priorGeneration)}
        if($RebootProvider){$rebootCall=&$callProvider $RebootProvider ([pscustomobject]@{context=$lifeContext;checkpoint=$checkpoint;priorGeneration=$priorGeneration;generation=[int]$checkpoint.generation;invocationId=$invocationId}) 'RebootProvider' 'bootIdentityChanged';if(-not $rebootCall.ok){return &$providerFailure 'RebootProvider' $rebootCall.error ("NEXT_REBOOT-generation-{0}" -f [int]$checkpoint.generation)};$reboot=$rebootCall.value;$bootChangedFound=$false;$bootChanged=Get-LifecycleProperty $reboot 'bootIdentityChanged' ([ref]$bootChangedFound);if(-not $bootChangedFound -or -not [bool]$bootChanged){return &$providerFailure 'RebootProvider' 'reboot provider did not prove a changed boot identity' ("NEXT_REBOOT-generation-{0}" -f [int]$checkpoint.generation)};if($SettleProvider){$settleCall=&$callProvider $SettleProvider ([pscustomobject]@{context=$lifeContext;checkpoint=$checkpoint;reboot=$reboot;priorGeneration=$priorGeneration;generation=[int]$checkpoint.generation;invocationId=$invocationId}) 'SettlementProvider' 'stable';if(-not $settleCall.ok){return &$providerFailure 'SettlementProvider' $settleCall.error ("reboot-generation-{0}" -f [int]$checkpoint.generation)};$settlement=$settleCall.value;$stableFound=$false;$stable=Get-LifecycleProperty $settlement 'stable' ([ref]$stableFound);if(-not $stableFound -or -not [bool]$stable){return &$providerFailure 'SettlementProvider' 'servicing settlement provider did not establish a stable boundary' ("reboot-generation-{0}" -f [int]$checkpoint.generation)};$reboot=[ordered]@{reboot=$reboot;servicingSettlement=$settlement}}}else{try{$reboot=Invoke-ProductRebootBoundary -Context $lifeContext -Checkpoint $checkpoint -PriorGeneration $priorGeneration}catch{return &$providerFailure 'RebootProvider' $_.Exception.Message ("NEXT_REBOOT-generation-{0}" -f [int]$checkpoint.generation)}}
        $priorGeneration=[int]$checkpoint.generation;$rebootCount++
        if($WpfProvider){$wpfCall=&$callProvider $WpfProvider ([pscustomobject]@{context=$lifeContext;role=$Role;action='FreshInstall';generation=$priorGeneration;priorGeneration=$priorGeneration;invocationId=$invocationId;resume=$true}) 'WpfProvider' 'status';if(-not $wpfCall.ok){return &$providerFailure 'WpfProvider' $wpfCall.error ("reboot-generation-{0}" -f $priorGeneration)};$current=$wpfCall.value}else{try{$current=Invoke-ActualWpfAction -Context $lifeContext -Action 'FreshInstall' -Role $Role -EvidenceLabel ("resume-generation-{0}" -f $priorGeneration) -LaunchMode 'resume' -AllowMutation -AllowRebootRequired -UseDurableCompletionFallback -DeferDurableCompletionFallback -DeferOAuthCredentialCleanup -ElevatedResume:$true}catch{return &$providerFailure 'WpfProvider' $_.Exception.Message ("reboot-generation-{0}" -f $priorGeneration)}}
        if($current -is [System.Collections.IDictionary]){$current=[pscustomobject]$current}
        if(-not $current){return &$providerFailure 'WpfProvider' 'WPF result was null' ("reboot-generation-{0}" -f $priorGeneration)}
        $currentProperties=Get-LifecyclePropertyNames $current;$found=$false;$currentStatus=Get-LifecycleProperty $current 'status' ([ref]$found);if(-not $found){return &$providerFailure 'WpfProvider' 'WPF result lacks status' ("reboot-generation-{0}" -f $priorGeneration)}
        if([string]$currentStatus -notin @('REAL E2E PASS','REAL E2E REBOOT REQUIRED','REAL E2E OBSERVER HANDOFF')){return &$providerFailure 'WpfProvider' "WPF result returned unsupported status $([string]$currentStatus)" ("reboot-generation-{0}" -f $priorGeneration)}
        $record=[ordered]@{generation=$priorGeneration;reboot=$reboot;observer=$observer;resume=$current;invocationId=$invocationId;observerEvidencePath=$observerSummaryPath;generationEvidencePath=(Join-Path ([string]$lifeContext.runDir) ("product-lifecycle-generation-{0}.json" -f $priorGeneration))};Write-EvidenceJson -Path (Join-Path ([string]$lifeContext.runDir) ("product-lifecycle-generation-{0}.json" -f $priorGeneration)) -Value $record
    }
    }
    finally {
        $cleanupRequiredFound=$false
        $cleanupRequired=Get-LifecycleProperty -Value $lifeContext -Name 'oauthCredentialCleanupRequired' -Found ([ref]$cleanupRequiredFound)
        if($cleanupRequiredFound -and [bool]$cleanupRequired){
            if($OAuthCredentialCleanupProvider){&$OAuthCredentialCleanupProvider $lifeContext|Out-Null}else{Invoke-DevFleetTailscaleOAuthCredentialCleanup -Context $lifeContext|Out-Null}
            $lifeContext|Add-Member -NotePropertyName oauthCredentialCleanupRequired -NotePropertyValue $false -Force
        }
    }
}

function Invoke-SupportedFreshInstallLifecycle {
    <# Shared release-tooling contract. Product checkpoints and receipts remain authoritative. #>
    param(
        [Parameter(Mandatory)][psobject]$Context,
        [string]$Role = 'Primary / Desktop',
        [switch]$CompleteLifecycle
    )
    if (-not $CompleteLifecycle) { return Invoke-ActualWpfAction -Context $Context -Action 'FreshInstall' -Role $Role -EvidenceLabel 'initial-FreshInstall' -LaunchMode 'initial' -AllowMutation -AllowRebootRequired -UseDurableCompletionFallback:$false -DeferDurableCompletionFallback -ElevatedResume:$false }
    return Invoke-ProductFreshInstallLifecycle -Context $Context -Role $Role
}

function Read-PhaseContext {
    param([Parameter(Mandatory)][string]$ContextJson)
    $context = $ContextJson | ConvertFrom-Json -ErrorAction Stop
    if (-not $context.candidate.candidate.path -or -not $context.vmName -or -not $context.runDir) { throw 'FullRelease phase context is missing exact candidate, disposable VM, or evidence identity.' }
    return $context
}

function Assert-ExactCandidate {
    param([Parameter(Mandatory)][psobject]$Context)
    $item = Get-Item -LiteralPath ([string]$Context.candidate.candidate.path) -ErrorAction Stop
    $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne [string]$Context.candidate.candidate.sha256 -or [int64]$item.Length -ne [int64]$Context.candidate.candidate.bytes) { throw "Exact candidate changed before phase $($Context.phaseId)." }
    return [ordered]@{ path=$item.FullName; bytes=[int64]$item.Length; sha256=$hash; releaseFingerprintId=[string]$Context.candidate.releaseFingerprintId; toolingFingerprintId=[string]$Context.candidate.toolingFingerprintId }
}

function New-GuestForeignSentinels {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$PhaseId)
    Invoke-Command -Session $Session -ScriptBlock {
        param($runId,$phaseId)
        $sha256=[Security.Cryptography.SHA256]::Create()
        try{$suffix=($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes("${runId}:${phaseId}"))|ForEach-Object{$_.ToString('x2')}) -join ''}finally{$sha256.Dispose()}
        $suffix=$suffix.Substring(0,12)
        $taskName="DevFleet-E2E-Foreign-$suffix"
        $serviceName="DevFleetE2EForeign$suffix"
        $firewallName="DevFleet-E2E-Foreign-Firewall-$suffix"
        $registryPath="HKLM:\SOFTWARE\DevFleet-E2E\ForeignSentinels\$suffix"
        $filePath="C:\Users\Public\DevFleet-E2E\Sentinels\$suffix.txt"
        $value="foreign-sentinel-${runId}-${phaseId}"
        if(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){throw 'Foreign scheduled-task sentinel already exists.'}
        $existingService=Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        $serviceCommand='"'+(Join-Path $env:SystemRoot 'System32\cmd.exe')+'" /d /c exit 0'
        $reuseExactService=$false
        if($existingService){
            $normalizeServiceCommand={param([string]$v)(($v -replace '"','' -replace '\s+',' ').Trim()).ToLowerInvariant()}
            $existingServiceCommand=&$normalizeServiceCommand ([string]$existingService.PathName)
            $expectedServiceCommand=&$normalizeServiceCommand $serviceCommand
            if([string]$existingService.StartMode -ne 'Disabled' -or $existingServiceCommand -cne $expectedServiceCommand){throw 'Foreign service sentinel already exists.'}
            # The exact run/phase-derived service can survive a product reboot
            # while the other run-owned sentinel objects are torn down. Reuse
            # it only when its immutable definition is exactly our sentinel;
            # any mismatched service remains a fail-closed collision.
            $reuseExactService=$true
        }
        $existingFirewall=@(Get-NetFirewallRule -Name $firewallName -ErrorAction SilentlyContinue)
        $reuseExactFirewall=$false
        if($existingFirewall.Count -gt 0){
            $existingPortFilters=@(Get-NetFirewallPortFilter -AssociatedNetFirewallRule $existingFirewall[0] -ErrorAction SilentlyContinue)
            $profileText=[string]$existingFirewall[0].Profile
            $protocolText=if($existingPortFilters.Count -eq 1){[string]$existingPortFilters[0].Protocol}else{''}
            $localPortText=if($existingPortFilters.Count -eq 1){[string]$existingPortFilters[0].LocalPort}else{''}
            $profileMatches=$profileText -in @('Any','32767')
            $protocolMatches=$protocolText -ieq 'TCP' -or $protocolText -eq '6'
            $firewallMatches=($existingFirewall.Count -eq 1 -and [string]$existingFirewall[0].DisplayName -ceq $firewallName -and [string]$existingFirewall[0].Group -ceq 'DevFleet E2E Foreign Sentinels' -and [string]$existingFirewall[0].Direction -ieq 'Inbound' -and [string]$existingFirewall[0].Action -ieq 'Block' -and [string]$existingFirewall[0].Enabled -ieq 'True' -and $profileMatches -and $existingPortFilters.Count -eq 1 -and $protocolMatches -and $localPortText -eq '65535')
            if(-not $firewallMatches){throw 'Foreign firewall sentinel already exists.'}
            # The exact run/phase-derived firewall can survive a product reboot
            # while the other run-owned sentinel objects are torn down. Reuse
            # it only when its immutable definition is exactly our sentinel;
            # any mismatched rule remains a fail-closed collision.
            $reuseExactFirewall=$true
        }
        $taskAction=New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\cmd.exe') -Argument '/d /c exit 0'
        $taskSettings=New-ScheduledTaskSettingsSet -Disable
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Settings $taskSettings -User 'SYSTEM' -RunLevel Highest -Force|Out-Null
        if(-not $reuseExactService){& (Join-Path $env:SystemRoot 'System32\sc.exe') create $serviceName 'binPath=' $serviceCommand 'start=' 'disabled' 'DisplayName=' "DevFleet E2E Foreign Sentinel $suffix"|Out-Null;if($LASTEXITCODE -ne 0){throw 'Foreign service sentinel creation failed.'}}
        if(-not $reuseExactFirewall){New-NetFirewallRule -Name $firewallName -DisplayName $firewallName -Group 'DevFleet E2E Foreign Sentinels' -Direction Inbound -Action Block -Protocol TCP -LocalPort 65535 -Profile Any|Out-Null}
        New-Item -ItemType Directory -Path (Split-Path -Parent $filePath) -Force|Out-Null
        New-Item -Path $registryPath -Force|Out-Null
        New-ItemProperty -Path $registryPath -Name Value -Value $value -PropertyType String -Force|Out-Null
        [IO.File]::WriteAllText($filePath,$value,[Text.UTF8Encoding]::new($false))
        $sha256=[Security.Cryptography.SHA256]::Create()
        try{$valueSha256=($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))|ForEach-Object{$_.ToString('x2')})-join ''}finally{$sha256.Dispose()}
        return [ordered]@{task=$taskName;service=$serviceName;firewall=$firewallName;registry=$registryPath;file=$filePath;valueSha256=$valueSha256;fileSha256=(Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant();serviceReused=$reuseExactService;firewallReused=$reuseExactFirewall}
    } -ArgumentList $RunId,$PhaseId
}

function Test-GuestForeignSentinels {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][psobject]$Sentinels)
    Invoke-Command -Session $Session -ScriptBlock {
        param($sentinels)
        $task=@(Get-ScheduledTask -TaskName ([string]$sentinels.task) -ErrorAction SilentlyContinue)
        $service=@(Get-CimInstance Win32_Service -Filter "Name='$([string]$sentinels.service)'" -ErrorAction SilentlyContinue)
        $firewall=@(Get-NetFirewallRule -Name ([string]$sentinels.firewall) -ErrorAction SilentlyContinue)
        $value=[string](Get-ItemProperty -Path ([string]$sentinels.registry) -Name Value -ErrorAction Stop).Value
        $sha256=[Security.Cryptography.SHA256]::Create()
        try{$valueSha=($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))|ForEach-Object{$_.ToString('x2')})-join ''}finally{$sha256.Dispose()}
        $fileSha=if(Test-Path -LiteralPath ([string]$sentinels.file) -PathType Leaf){(Get-FileHash -LiteralPath ([string]$sentinels.file) -Algorithm SHA256).Hash.ToLowerInvariant()}else{''}
        $checks=[ordered]@{scheduledTask=($task.Count -eq 1);service=($service.Count -eq 1 -and [string]$service[0].StartMode -eq 'Disabled');firewall=($firewall.Count -eq 1 -and [string]$firewall[0].Action -eq 'Block');registry=($valueSha -eq [string]$sentinels.valueSha256);file=($fileSha -eq [string]$sentinels.fileSha256)}
        if(@($checks.GetEnumerator()|Where-Object{-not [bool]$_.Value}).Count){throw 'One or more unrelated Windows sentinels changed during the lifecycle action.'}
        return [ordered]@{status='PASS';checks=$checks;unchanged=$true}
    } -ArgumentList $Sentinels
}

function Remove-GuestForeignSentinels {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][psobject]$Sentinels)
    Invoke-Command -Session $Session -ScriptBlock {
        param($sentinels)
        Unregister-ScheduledTask -TaskName ([string]$sentinels.task) -Confirm:$false -ErrorAction SilentlyContinue
        if(Get-CimInstance Win32_Service -Filter "Name='$([string]$sentinels.service)'" -ErrorAction SilentlyContinue){& (Join-Path $env:SystemRoot 'System32\sc.exe') delete ([string]$sentinels.service)|Out-Null;$serviceDeadline=(Get-Date).AddSeconds(15);do{$serviceStillPresent=$null -ne (Get-CimInstance Win32_Service -Filter "Name='$([string]$sentinels.service)'" -ErrorAction SilentlyContinue);if($serviceStillPresent){Start-Sleep -Milliseconds 250}}while($serviceStillPresent -and (Get-Date)-lt $serviceDeadline)}
        Get-NetFirewallRule -Name ([string]$sentinels.firewall) -ErrorAction SilentlyContinue|Remove-NetFirewallRule -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ([string]$sentinels.registry) -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ([string]$sentinels.file) -Force -ErrorAction SilentlyContinue
        $remaining=[ordered]@{task=[bool](Get-ScheduledTask -TaskName ([string]$sentinels.task) -ErrorAction SilentlyContinue);service=[bool](Get-CimInstance Win32_Service -Filter "Name='$([string]$sentinels.service)'" -ErrorAction SilentlyContinue);firewall=[bool](Get-NetFirewallRule -Name ([string]$sentinels.firewall) -ErrorAction SilentlyContinue);registry=(Test-Path -LiteralPath ([string]$sentinels.registry));file=(Test-Path -LiteralPath ([string]$sentinels.file))}
        if(@($remaining.GetEnumerator()|Where-Object{[bool]$_.Value}).Count){throw 'Run-owned Windows sentinel cleanup was incomplete.'}
        return [ordered]@{status='PASS';absent=$true}
    } -ArgumentList $Sentinels
}

function Invoke-RebootResumeWpfFallback {
    param(
        [Parameter(Mandatory)][psobject]$Context,
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][psobject]$DriverReport
    )
    $expectedPayload = [string]$Context.candidate.tar.sha256
    $expectedCandidatePath = Join-Path "C:\Users\Public\DevFleet-E2E\$($Context.runId)\$($Context.phaseId)" (Split-Path -Leaf ([string]$Context.candidate.candidate.path))
    $candidatePid = 0
    $candidateSessionId = -1
    $driverProcessFound=$false;$driverProcess=Get-LifecycleProperty $DriverReport 'processId' ([ref]$driverProcessFound);if($driverProcessFound){$candidatePid=[int]$driverProcess}
    $driverSessionFound=$false;$driverSession=Get-LifecycleProperty $DriverReport 'sessionId' ([ref]$driverSessionFound);if($driverSessionFound){$candidateSessionId=[int]$driverSession}
    $observationSeconds = 180
    $diagnosticSecondsFound=$false;$diagnosticSeconds=Get-LifecycleProperty $Context 'diagnosticObservationSeconds' ([ref]$diagnosticSecondsFound);if ($diagnosticSecondsFound) {
        $requestedSeconds = 0
        if ([int]::TryParse([string]$diagnosticSeconds, [ref]$requestedSeconds) -and $requestedSeconds -gt 180) {
            $observationSeconds = [Math]::Min($requestedSeconds, 1800)
        }
    }
    $observationPath = Join-Path ([string]$Context.runDir) 'durable-observation-samples.json'
    $observationSamples = [System.Collections.Generic.List[object]]::new()
    $deadline = (Get-Date).AddSeconds($observationSeconds)
    $lastError = 'durable completion not yet observable'
    do {
        try {
            $sample = Invoke-Command -Session $Session -ScriptBlock {
                param($processId,$sessionId,$expectedPath)
                # Preserve the bounded read-error record when completion removes
                # the product checkpoint between the existence check and the
                # file read; do not leak a remoting non-terminating error into
                # the lifecycle observer.
                $ErrorActionPreference='Stop'
                $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
                $ids = [System.Collections.Generic.HashSet[int]]::new()
                if ($processId -gt 0) { [void]$ids.Add($processId) }
                do {
                    $before = $ids.Count
                    foreach ($row in $all) { if ($ids.Contains([int]$row.ParentProcessId)) { [void]$ids.Add([int]$row.ProcessId) } }
                } while ($ids.Count -gt $before)
                $root = $all | Where-Object { [int]$_.ProcessId -eq $processId } | Select-Object -First 1
                $processMeta = $null
                try {
                    $p = Get-Process -Id $processId -ErrorAction Stop
                    $processMeta = [ordered]@{hasExited=$false;responding=[bool]$p.Responding;mainWindowHandle=[int64]$p.MainWindowHandle;cpuSeconds=[double]$p.TotalProcessorTime.TotalSeconds;workingSetBytes=[int64]$p.WorkingSet64;threadCount=[int]$p.Threads.Count;handleCount=[int]$p.HandleCount;startTime=$p.StartTime.ToUniversalTime().ToString('o')}
                } catch { $processMeta = [ordered]@{hasExited=$true} }
                $checkpointPath = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-checkpoint.json'
                $checkpoint = $null
                if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) {
                    try { $v = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json; $checkpoint = [ordered]@{state=$v.state;action=$v.action;transactionId=$v.transactionId;payloadSha256=$v.payloadSha256;checkpointGeneration=$v.checkpointGeneration;completedStages=$v.completedStages;resumeStage=$v.resumeStage;createdUtc=$v.createdUtc;lastWriteUtc=(Get-Item -LiteralPath $checkpointPath).LastWriteTimeUtc.ToString('o')} } catch { $checkpoint = [ordered]@{readError=$_.Exception.Message} }
                }
                $consumedRoot = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-consumed'
                $receipts = @()
                if (Test-Path -LiteralPath $consumedRoot) { $receipts = @(Get-ChildItem -LiteralPath $consumedRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTimeUtc) }
                $installPath = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\install-state.json'
                $ownershipPath = 'C:\ProgramData\DevFleetHostAgent\integration-ownership.json'
                [ordered]@{timestampUtc=(Get-Date).ToUniversalTime().ToString('o');candidate=$processMeta;candidateRow=if($root){[ordered]@{processId=$root.ProcessId;parentProcessId=$root.ParentProcessId;executablePath=$root.ExecutablePath;commandLine=$root.CommandLine;sessionId=$root.SessionId}}else{$null};processTree=@($all | Where-Object { $ids.Contains([int]$_.ProcessId) } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,SessionId);checkpoint=$checkpoint;checkpointPresent=(Test-Path -LiteralPath $checkpointPath -PathType Leaf);receiptFiles=$receipts;installStatePresent=(Test-Path -LiteralPath $installPath -PathType Leaf);installStateLastWriteUtc=if(Test-Path -LiteralPath $installPath){(Get-Item -LiteralPath $installPath).LastWriteTimeUtc.ToString('o')}else{$null};ownershipPresent=(Test-Path -LiteralPath $ownershipPath -PathType Leaf);nodeIdentityPresent=(Test-Path -LiteralPath 'C:\ProgramData\DevFleet\node-identity.json' -PathType Leaf);hostAgentPresent=(Test-Path -LiteralPath 'C:\ProgramData\DevFleetHostAgent' -PathType Container);hostAgentTaskPresent=[bool](Get-ScheduledTask -TaskName 'DevFleet Host Agent' -ErrorAction SilentlyContinue);listenerPresent=[bool](Get-NetTCPConnection -LocalPort 8790 -State Listen -ErrorAction SilentlyContinue);pendingCbs=(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending');pendingWindowsUpdate=(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')}
            } -ArgumentList $candidatePid,$candidateSessionId,$expectedCandidatePath
            [void]$observationSamples.Add($sample)
            Write-EvidenceJson -Path $observationPath -Value @($observationSamples)
        } catch {
            [void]$observationSamples.Add([ordered]@{timestampUtc=(Get-Date).ToUniversalTime().ToString('o');sampleError=$_.Exception.Message})
            Write-EvidenceJson -Path $observationPath -Value @($observationSamples)
        }
        try {
            $durable = Invoke-MaintenanceReadyGuestValidation -VmId ([guid][string]$Context.vmId) -Fingerprint $Context.candidate -Session $Session -OwnerDeadlineUtc $deadline.ToUniversalTime()
            $receiptSeconds=[int][math]::Floor(($deadline-(Get-Date)).TotalSeconds)
            if($receiptSeconds-le0){throw 'Reboot receipt observation owner deadline is exhausted.'}
            $health = Invoke-DevFleetBoundedGuestCommand -Session $Session -TimeoutSeconds ([math]::Min(10,$receiptSeconds)) -ScriptBlock {
                param($payload)
                $checkpoint = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-checkpoint.json'
                if (Test-Path -LiteralPath $checkpoint -PathType Leaf) { throw 'Reboot checkpoint remains present; completion is not verified.' }
                $consumedRoot = 'C:\ProgramData\M-TechLabs\DevFleet\Installer\resume-consumed'
                $receipt = @(Get-ChildItem -LiteralPath $consumedRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try { $value = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json; if ([string]$value.payloadSha256 -ceq $payload) { $_ } } catch { }
                } | Select-Object -Last 1)
                if (-not $receipt) { throw 'No consumed reboot receipt matched the exact candidate payload.' }
                [ordered]@{status='PASS';receiptPath=$receipt.FullName}
            } -ArgumentList @($expectedPayload)
            if([string]$durable.status-cne'PASS'-or$durable.hostAgentHealth.authenticated-isnot[bool]-or-not$durable.hostAgentHealth.authenticated-or$durable.hostAgentHealth.ok-isnot[bool]-or-not$durable.hostAgentHealth.ok-or(Get-Date)-ge$deadline){throw 'Bounded maintenance validation did not establish current authenticated health.'}
            if([string]$health.status-cne'PASS'){throw 'Reboot checkpoint/receipt validation did not pass.'}
            $health=[ordered]@{status='PASS';receiptPath=[string]$health.receiptPath;hostName=[string]$durable.hostAgentHealth.hostName;hostId=[string]$durable.hostAgentHealth.hostId}
            return [ordered]@{status='PASS';mode='DURABLE_REBOOT_RESUME_FALLBACK';driver=$DriverReport;guest=$durable;health=$health;authenticatedHealth=$true;checkpointConsumed=$true}
        } catch { $lastError = $_.Exception.Message }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    $processEvidence = $null
    $cleanupEvidence = $null
    if ($candidatePid -gt 0 -and $candidateSessionId -ge 0) {
        try {
            $processEvidence = Invoke-Command -Session $Session -ScriptBlock {
                param($processId,$sessionId,$expectedPath)
                $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
                $ids = [System.Collections.Generic.HashSet[int]]::new()
                [void]$ids.Add($processId)
                do {
                    $before = $ids.Count
                    foreach ($row in $all) { if ($ids.Contains([int]$row.ParentProcessId)) { [void]$ids.Add([int]$row.ProcessId) } }
                } while ($ids.Count -gt $before)
                $target = @($all | Where-Object { $ids.Contains([int]$_.ProcessId) } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,SessionId)
                $root = $all | Where-Object { [int]$_.ProcessId -eq $processId } | Select-Object -First 1
                $sessionMatch = $false
                try { $sessionMatch = [int](Get-Process -Id $processId -ErrorAction Stop).SessionId -eq $sessionId } catch { }
                $pathMatch = $null -ne $root -and -not [string]::IsNullOrWhiteSpace($expectedPath) -and [string]$root.ExecutablePath -ieq $expectedPath
                [ordered]@{candidatePid=$processId;expectedSessionId=$sessionId;expectedPath=$expectedPath;candidatePresent=($null -ne $root);sessionMatch=$sessionMatch;pathMatch=$pathMatch;processTree=$target}
            } -ArgumentList $candidatePid,$candidateSessionId,$expectedCandidatePath
        } catch { $processEvidence = [ordered]@{captureError=$_.Exception.Message} }
        try {
            $cleanupEvidence = Invoke-Command -Session $Session -ScriptBlock {
                param($processId,$sessionId,$expectedPath)
                $row = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
                $sessionMatch = $false
                try { $sessionMatch = [int](Get-Process -Id $processId -ErrorAction Stop).SessionId -eq $sessionId } catch { }
                $pathMatch = $null -ne $row -and -not [string]::IsNullOrWhiteSpace($expectedPath) -and [string]$row.ExecutablePath -ieq $expectedPath
                if ($row -and $sessionMatch -and $pathMatch) { Stop-Process -Id $processId -Force -ErrorAction Stop; [ordered]@{attempted=$true;stopped=$true;pid=$processId;sessionMatch=$sessionMatch;pathMatch=$pathMatch} }
                else { [ordered]@{attempted=$false;stopped=$false;pid=$processId;present=($null -ne $row);sessionMatch=$sessionMatch;pathMatch=$pathMatch} }
            } -ArgumentList $candidatePid,$candidateSessionId,$expectedCandidatePath
        } catch { $cleanupEvidence = [ordered]@{cleanupError=$_.Exception.Message} }
    } else {
        $cleanupEvidence = [ordered]@{attempted=$false;reason='No exact candidate PID and session identity was present in the driver report.'}
    }
    $details = [ordered]@{lastError=$lastError;observationSeconds=$observationSeconds;observationPath=$observationPath;observationSamples=@($observationSamples);processEvidence=$processEvidence;cleanupEvidence=$cleanupEvidence} | ConvertTo-Json -Depth 12 -Compress
    throw "WPF window disappeared and durable reboot-resume completion did not become verifiable within the bounded fallback window: $details"
}

function Invoke-DevFleetTailscaleOAuthCredentialCleanup {
    param([Parameter(Mandatory)][psobject]$Context,[AllowNull()][System.Management.Automation.Runspaces.PSSession]$Session)
    $cleanupSession=$Session
    $ownsCleanupSession=$false
    try {
        if(-not $cleanupSession -or [string]$cleanupSession.State -ceq 'Closed'){$cleanupSession=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId);$ownsCleanupSession=$true}
        if(-not $cleanupSession){throw 'No exact E2E session was available for OAuth credential cleanup.'}
        $cleanupResult=Remove-StagedTailscaleOAuthCredential -Session $cleanupSession
        if([string]$cleanupResult.status -cne 'PASS'){throw 'Remote OAuth credential cleanup returned a non-PASS result.'}
    } catch {
        if([string]$_.Exception.Message -match '^TAILSCALE_CREDENTIAL_CLEANUP_FAILED:'){throw}
        throw "TAILSCALE_CREDENTIAL_CLEANUP_FAILED: $($_.Exception.Message)"
    } finally {
        if($ownsCleanupSession -and $cleanupSession){Remove-DevFleetGuestSession $cleanupSession -ErrorAction SilentlyContinue}
    }
}

function Invoke-ActualWpfAction {
    param([Parameter(Mandatory)][psobject]$Context,[Parameter(Mandatory)][string]$Action,[string]$Role='Primary / Desktop',[string]$EvidenceLabel,[ValidateSet('direct','initial','resume','fallback')][string]$LaunchMode='direct',[switch]$AllowMutation,[switch]$AllowRebootRequired,[switch]$UseDurableCompletionFallback,[switch]$DeferDurableCompletionFallback,[switch]$DeferOAuthCredentialCleanup,[switch]$ElevatedResume)
    $candidate=Assert-ExactCandidate $Context
    $session=$null;$sentinels=$null;$sentinelVerification=$null;$sentinelCleanup=$null;$oauthStage=$null;$oauthStageAttempted=$false
    try {
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        try{$interactiveState=Get-DevFleetE2EInteractiveDesktopState -Session $session;$interactiveProof=Assert-DevFleetE2EInteractiveDesktop -State $interactiveState}
        catch{Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue;$session=$null;Ensure-FullReleaseInteractiveDesktop -VmId ([guid][string]$Context.vmId)|Out-Null;$session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId);$interactiveState=Get-DevFleetE2EInteractiveDesktopState -Session $session;$interactiveProof=Assert-DevFleetE2EInteractiveDesktop -State $interactiveState}
        if($AllowMutation -and $Context.config -and $Context.config.PSObject.Properties['Tailscale'] -and $Context.config.Tailscale.Authentication -and [string]$Context.config.Tailscale.Authentication.Provider -in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){
            $oauthStageAttempted=$true
            $Context|Add-Member -NotePropertyName oauthCredentialCleanupRequired -NotePropertyValue $true -Force
            $workspaceFound=$false;$workspaceValue=Get-LifecycleProperty $Context 'workspaceRoot' ([ref]$workspaceFound);$workspacePath=if($workspaceFound -and $workspaceValue){(Resolve-Path -LiteralPath ([string]$workspaceValue)).Path}else{(Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path}
            $productConfigPath=Join-Path $workspacePath 'source\config\devfleet.config.json'
            if(-not(Test-Path -LiteralPath $productConfigPath -PathType Leaf)){throw 'TAILSCALE_CREDENTIAL_INVALID: product configuration is unavailable for deterministic E2E enrollment identities.'}
            try{$productConfig=Get-Content -LiteralPath $productConfigPath -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'TAILSCALE_CREDENTIAL_INVALID: product configuration is unreadable for deterministic E2E enrollment identities.'}
            $oauthStage=Stage-TailscaleOAuthCredential -Session $session -RunId ([string]$Context.runId) -Config $Context.config.Tailscale -ProductConfig $productConfig
            if([string]$oauthStage.status -cne 'PASS' -or -not[bool]$oauthStage.staged){throw 'TAILSCALE_CREDENTIAL_INVALID: E2E OAuth credential staging did not complete.'}
        }
        $remoteRoot="C:\Users\Public\DevFleet-E2E\$($Context.runId)\$($Context.phaseId)"
        $remoteExe=Join-Path $remoteRoot (Split-Path -Leaf $candidate.path)
        $remoteDriver=Join-Path $remoteRoot 'Invoke-WpfUiAutomation.ps1'
        $remoteContract=Join-Path $remoteRoot 'WpfLaunchContract.psm1'
        $launchId=[guid]::NewGuid().ToString('N')
        $remoteReport=Join-Path $remoteRoot "wpf-$launchId-terminal.json"
        $remoteStarted=Join-Path $remoteRoot "wpf-$launchId-driver-bound.json"
        $remoteCheckpoint=Join-Path $remoteRoot "wpf-$launchId-checkpoint.json"
        $remoteWorkerResult=Join-Path $remoteRoot "wpf-$launchId-worker-terminal.json"
        $remoteLaunchRequest=Join-Path $remoteRoot "wpf-$launchId-launch-request.json"
        $safeEvidenceLabel=if([string]::IsNullOrWhiteSpace($EvidenceLabel)){"$($Context.phaseId)-$Action-$launchId"}else{$EvidenceLabel}
        $safeEvidenceLabel=($safeEvidenceLabel -replace '[^A-Za-z0-9._-]','-')
        $localEvidence=Join-Path ([string]$Context.runDir) ("$safeEvidenceLabel-wpf-evidence.json")
        New-Item -ItemType Directory -Force -Path ([string]$Context.runDir)|Out-Null
        Invoke-Command -Session $session -ScriptBlock {param($root)New-Item -ItemType Directory -Force -Path $root|Out-Null} -ArgumentList $remoteRoot
        if($AllowMutation){$sentinels=New-GuestForeignSentinels -Session $session -RunId ([string]$Context.runId) -PhaseId ([string]$Context.phaseId)}
        $stage=Get-StageIntegrity -LocalPath $candidate.path -Session $session -RemotePath $remoteExe
        if(-not $stage.equal){throw 'Candidate stage hash differed on disposable guest.'}
        $driverLocal=Join-Path $PSScriptRoot 'Invoke-WpfUiAutomation.ps1';$contractLocal=Join-Path $PSScriptRoot 'WpfLaunchContract.psm1'
        $driverStage=Get-StageIntegrity -LocalPath $driverLocal -Session $session -RemotePath $remoteDriver
        $contractStage=Get-StageIntegrity -LocalPath $contractLocal -Session $session -RemotePath $remoteContract
        if(-not $driverStage.equal -or -not $contractStage.equal){throw 'WPF driver/contract stage hash differed on disposable guest.'}

        $policy=Get-HarnessBudgetPolicy -Config $Context.config
        $ownerSeconds=if($Role -match '(?i)Laptop'){[int]$policy.observerAbsoluteBudgetsSeconds.Laptop}else{[int]$policy.observerAbsoluteBudgetsSeconds.Desktop}
        $ownerStart=(Get-Date).ToUniversalTime();$invocationStartFound=$false;$invocationStart=Get-LifecycleProperty $Context 'invocationStartUtc' ([ref]$invocationStartFound)
        if($invocationStartFound -and $invocationStart){$ownerStart=ConvertTo-WpfUtcInstant $invocationStart}
        $ownerDeadline=$ownerStart.AddSeconds($ownerSeconds)
        $transactionFound=$false;$transactionValue=Get-LifecycleProperty $Context 'lifecycleTransactionId' ([ref]$transactionFound);$transactionId=if($transactionFound){[string]$transactionValue}else{''}
        $launchSpec=New-WpfLaunchSpecification -DriverPath $remoteDriver -ExePath $remoteExe -Action $Action -Role $Role -OutputPath $remoteReport -StartedPath $remoteStarted -CheckpointPath $remoteCheckpoint -WorkerResultPath $remoteWorkerResult -LaunchRequestPath $remoteLaunchRequest -RunId ([string]$Context.runId) -LaunchId $launchId -TransactionId $transactionId -PayloadSha256 ([string]$Context.candidate.tar.sha256) -LaunchMode $LaunchMode -ExpectedInteractiveSessionId ([int]$interactiveProof.sessionId) -AllowMutation:$AllowMutation -AllowRebootRequired:$AllowRebootRequired -UseDurableCompletionFallback:$UseDurableCompletionFallback -ElevatedResume:$ElevatedResume -OwnerDeadlineUtc $ownerDeadline -SemanticNoProgressSeconds ([int]$policy.observerNoProgressBudgetSeconds) -DriverSha256 ([string]$driverStage.localSha256) -CandidateSha256 ([string]$candidate.sha256) -TaskExecutable 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -SkipPathValidation
        $launchSpec | Add-Member -NotePropertyName contractModulePath -NotePropertyValue $remoteContract -Force
        $launchSpec | Add-Member -NotePropertyName contractModuleSha256 -NotePropertyValue ([string]$contractStage.localSha256) -Force
        $launchSpecJson=$launchSpec|ConvertTo-Json -Depth 24 -Compress
        try {
            $report=Invoke-Command -Session $session -ScriptBlock {
                param($serializedSpec)
                $spec=$serializedSpec|ConvertFrom-Json
                function Get-Sha([string]$Path){$stream=[IO.File]::OpenRead($Path);try{$sha=[Security.Cryptography.SHA256]::Create();try{return([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}finally{$stream.Dispose()}}
                function Get-TextSha([string]$Value){$sha=[Security.Cryptography.SHA256]::Create();try{return([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
                function Read-AtomicJson([string]$Path){return([IO.File]::ReadAllText($Path)|ConvertFrom-Json -ErrorAction Stop)}
                function Resolve-TaskSid([string]$Account){$candidates=if($Account-notmatch'[\\@]'-and$env:COMPUTERNAME){@("$env:COMPUTERNAME\$Account",$Account)}else{@($Account)};foreach($candidateName in $candidates){try{return([Security.Principal.NTAccount]::new($candidateName)).Translate([Security.Principal.SecurityIdentifier]).Value}catch{}};throw "Scheduled-task principal did not resolve to a SID: $Account"}
                function Write-Atomic([string]$Path,[object]$Value){$tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp";try{[IO.File]::WriteAllText($tmp,(($Value|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $tmp -Destination $Path -Force}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}}
                foreach($binding in @(@{path=[string]$spec.driverPath;hash=[string]$spec.driverSha256;name='driver'},@{path=[string]$spec.contractModulePath;hash=[string]$spec.contractModuleSha256;name='contract module'},@{path=[string]$spec.exePath;hash=[string]$spec.candidateSha256;name='candidate'})){if(-not(Test-Path -LiteralPath $binding.path -PathType Leaf)-or(Get-Sha $binding.path)-cne $binding.hash){throw "Remote WPF $($binding.name) binding failed before task registration."}}
                Write-Atomic -Path ([string]$spec.launchRequestPath) -Value $spec
                $taskName="DevFleet-E2E-UIA-$([string]$spec.launchId)";$taskStarted=$false
                try {
                    if($env:USERNAME -cne 'E2EAdmin'){throw 'WPF driver launch reached a non-E2EAdmin PowerShell Direct identity.'}
                    $taskAction=New-ScheduledTaskAction -Execute ([string]$spec.taskExecutable) -Argument ([string]$spec.taskArguments)
                    $taskPrincipal=New-ScheduledTaskPrincipal -UserId ([string]$spec.taskPrincipalUserId) -LogonType Interactive -RunLevel Highest
                    $remaining=[Math]::Max(120,[int]([datetimeoffset]::Parse([string]$spec.boundaryDeadlineUtc).UtcDateTime-(Get-Date).ToUniversalTime()).TotalSeconds+60)
                    $taskSettings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds $remaining) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Principal $taskPrincipal -Settings $taskSettings -Force|Out-Null
                    $registered=Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                    $actualActions=@($registered.Actions)
                    $taskBindingReason='';$expectedSid='';$requestedSid='';$actualSid=''
                    try{$expectedSid=Resolve-TaskSid ([string]$spec.taskPrincipalUserId);$requestedSid=Resolve-TaskSid ([string]$taskPrincipal.UserId);$actualSid=Resolve-TaskSid ([string]$registered.Principal.UserId)}catch{$taskBindingReason="principal SID resolution failed: $($_.Exception.Message)"}
                    $requestedLogonType=-1;$actualLogonType=-1;$requestedRunLevel=-1;$actualRunLevel=-1
                    try{$requestedLogonType=[Convert]::ToInt32($taskPrincipal.LogonType,[Globalization.CultureInfo]::InvariantCulture)}catch{};try{$actualLogonType=[Convert]::ToInt32($registered.Principal.LogonType,[Globalization.CultureInfo]::InvariantCulture)}catch{};try{$requestedRunLevel=[Convert]::ToInt32($taskPrincipal.RunLevel,[Globalization.CultureInfo]::InvariantCulture)}catch{};try{$actualRunLevel=[Convert]::ToInt32($registered.Principal.RunLevel,[Globalization.CultureInfo]::InvariantCulture)}catch{}
                    $expectedExecute=[Environment]::ExpandEnvironmentVariables([string]$spec.taskExecutable);$actualExecute=if($actualActions.Count-eq 1){[Environment]::ExpandEnvironmentVariables([string]$actualActions[0].Execute)}else{''}
                    $taskBindingEvidence=[ordered]@{actionCount=$actualActions.Count;requestedExecute=$expectedExecute;registeredExecute=$actualExecute;argumentsMatched=($actualActions.Count-eq 1-and[string]::Equals([string]$actualActions[0].Arguments,[string]$spec.taskArguments,[StringComparison]::Ordinal));expectedUserId=[string]$spec.taskPrincipalUserId;requestedUserId=[string]$taskPrincipal.UserId;registeredUserId=[string]$registered.Principal.UserId;principalSidSha256=if($actualSid){Get-TextSha $actualSid}else{''};requestedLogonTypeValue=$requestedLogonType;registeredLogonTypeValue=$actualLogonType;requestedRunLevelValue=$requestedRunLevel;registeredRunLevelValue=$actualRunLevel;verifiedBeforeStart=$false}
                    if(-not$taskBindingReason){if($actualActions.Count-ne 1){$taskBindingReason='registered task action count diverged'}else{try{$expectedExecute=[IO.Path]::GetFullPath($expectedExecute);$actualExecute=[IO.Path]::GetFullPath($actualExecute)}catch{$taskBindingReason='registered task executable path was malformed'}}}
                    if(-not$taskBindingReason-and-not[string]::Equals($actualExecute,$expectedExecute,[StringComparison]::OrdinalIgnoreCase)){$taskBindingReason='registered task executable identity diverged'}
                    if(-not$taskBindingReason-and-not[string]::Equals([string]$actualActions[0].Arguments,[string]$spec.taskArguments,[StringComparison]::Ordinal)){$taskBindingReason='registered task arguments diverged'}
                    if(-not$taskBindingReason-and($expectedSid-cne$requestedSid-or$expectedSid-cne$actualSid)){$taskBindingReason='registered task principal SID diverged'}
                    if(-not$taskBindingReason-and($requestedLogonType-ne[int]$spec.taskLogonTypeValue-or$actualLogonType-ne[int]$spec.taskLogonTypeValue)){$taskBindingReason='registered task logon type diverged'}
                    if(-not$taskBindingReason-and($requestedRunLevel-ne[int]$spec.taskRunLevelValue-or$actualRunLevel-ne[int]$spec.taskRunLevelValue)){$taskBindingReason='registered task run level diverged'}
                    if($taskBindingReason){
                        $failure=[ordered]@{schemaVersion=2;contract='devfleet-wpf-terminal-v2';status='OBSERVER_FAILURE';terminal=$true;completionVerified=$false;failureClass='REGISTERED_TASK_BINDING_MISMATCH';error="Registered WPF task diverged from the immutable launch request before product mutation: $taskBindingReason";runId=[string]$spec.runId;launchId=[string]$spec.launchId;transactionId=[string]$spec.transactionId;payloadSha256=[string]$spec.payloadSha256;candidateSha256=[string]$spec.candidateSha256;sequence=1;phase='TASK_BINDING_VALIDATION';lastDurableStep='LAUNCH_REQUESTED';deadlineUtc=[string]$spec.boundaryDeadlineUtc;cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER';taskBinding=$taskBindingEvidence;timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
                        Write-Atomic -Path ([string]$spec.outputPath) -Value $failure
                        throw $failure.error
                    }
                    $taskBindingEvidence.verifiedBeforeStart=$true
                    Start-ScheduledTask -TaskName $taskName;$taskStarted=$true
                    $deadline=[datetimeoffset]::Parse([string]$spec.boundaryDeadlineUtc).UtcDateTime
                    while(-not(Test-Path -LiteralPath $spec.outputPath -PathType Leaf)-and(Get-Date).ToUniversalTime()-lt $deadline){Start-Sleep -Seconds 1}
                    if(-not(Test-Path -LiteralPath $spec.outputPath -PathType Leaf)){
                        $last=$null;try{if(Test-Path -LiteralPath $spec.checkpointPath -PathType Leaf){$last=Read-AtomicJson $spec.checkpointPath}}catch{}
                        $seq=1;if($last -and $last.sequence){$seq=[int]$last.sequence+1}
                        $failure=[ordered]@{schemaVersion=2;contract='devfleet-wpf-terminal-v2';status='OBSERVER_FAILURE';terminal=$true;completionVerified=$false;failureClass='SUPERVISOR_REPORT_DEADLINE';error='Scheduled WPF supervisor did not publish a terminal report within the finite inherited boundary.';runId=[string]$spec.runId;launchId=[string]$spec.launchId;transactionId=[string]$spec.transactionId;payloadSha256=[string]$spec.payloadSha256;candidateSha256=[string]$spec.candidateSha256;sequence=$seq;phase='REMOTE_TASK_SUPERVISOR';lastDurableStep=if($last){[string]$last.phase}else{'LAUNCH_REQUESTED'};deadlineUtc=[string]$spec.boundaryDeadlineUtc;cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER';timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
                        Write-Atomic -Path ([string]$spec.outputPath) -Value $failure
                        if($taskStarted){Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue}
                    }
                    $result=Read-AtomicJson $spec.outputPath
                    $result|Add-Member -NotePropertyName taskPrincipal -NotePropertyValue ([string]$spec.taskPrincipalUserId) -Force
                    $result|Add-Member -NotePropertyName taskBinding -NotePropertyValue $taskBindingEvidence -Force
                    $result|Add-Member -NotePropertyName registeredTaskAction -NotePropertyValue ([ordered]@{execute=[string]$actualActions[0].Execute;arguments=[string]$actualActions[0].Arguments;verifiedBeforeStart=$true}) -Force
                    try {
                        $operatingSystem=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                        $result|Add-Member -NotePropertyName bootIdentity -NotePropertyValue ([ordered]@{status='PASS';computerName=[string]$env:COMPUTERNAME;lastBootUpTimeUtc=$operatingSystem.LastBootUpTime.ToUniversalTime().ToString('o');observedUtc=(Get-Date).ToUniversalTime().ToString('o')}) -Force
                    } catch {
                        $result|Add-Member -NotePropertyName bootIdentity -NotePropertyValue ([ordered]@{status='OBSERVATION_FAILED';error=$_.Exception.Message;observedUtc=(Get-Date).ToUniversalTime().ToString('o')}) -Force
                    }
                    return $result
                } finally {
                    if($taskStarted){$settleDeadline=(Get-Date).AddSeconds(15);do{$task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue;if(-not $task -or [string]$task.State -ne 'Running'){break};Start-Sleep -Milliseconds 500}while((Get-Date)-lt $settleDeadline)}
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                }
            } -ArgumentList $launchSpecJson
        } catch {
            foreach($remotePath in @($remoteReport,$remoteStarted,$remoteCheckpoint,$remoteWorkerResult,$remoteLaunchRequest)){try{Copy-Item -FromSession $session -LiteralPath $remotePath -Destination (Join-Path ([string]$Context.runDir) (Split-Path -Leaf $remotePath)) -Force -ErrorAction Stop}catch{}}
            throw "Remote WPF action $Action failed at the identity-bound task boundary: $($_.Exception.Message); evidenceLocal=$localEvidence"
        }
        if(-not $report){throw "Remote WPF action $Action returned no result; evidenceLocal=$localEvidence"}
        foreach($remotePath in @($remoteReport,$remoteStarted,$remoteCheckpoint,$remoteWorkerResult,$remoteLaunchRequest)){try{Copy-Item -FromSession $session -LiteralPath $remotePath -Destination (Join-Path ([string]$Context.runDir) (Split-Path -Leaf $remotePath)) -Force -ErrorAction Stop}catch{}}
        $bindingReason='';if(-not(Test-WpfTerminalReport -Report $report -Specification $launchSpec -Reason ([ref]$bindingReason))){
            $sequenceFound=$false;$rejectedSequenceValue=Get-LifecycleProperty $report 'sequence' ([ref]$sequenceFound);$rejectedSequence=0;if($sequenceFound){[void][int]::TryParse([string]$rejectedSequenceValue,[ref]$rejectedSequence)}
            $lastStepFound=$false;$rejectedLastStep=Get-LifecycleProperty $report 'lastDurableStep' ([ref]$lastStepFound)
            $parentFailure=[ordered]@{schemaVersion=2;contract='devfleet-wpf-terminal-v2';status='OBSERVER_FAILURE';terminal=$true;completionVerified=$false;failureClass='PARENT_REPORT_VALIDATION_FAILURE';error="Remote WPF report failed launch identity validation: $bindingReason";runId=[string]$launchSpec.runId;launchId=[string]$launchSpec.launchId;transactionId=[string]$launchSpec.transactionId;payloadSha256=[string]$launchSpec.payloadSha256;candidateSha256=[string]$launchSpec.candidateSha256;sequence=([Math]::Max(0,$rejectedSequence)+1);phase='PARENT_REPORT_VALIDATION';lastDurableStep=if($lastStepFound -and $rejectedLastStep){[string]$rejectedLastStep}else{'REMOTE_REPORT_RECEIVED'};deadlineUtc=[string]$launchSpec.boundaryDeadlineUtc;cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER';rejectedReportFile=(Split-Path -Leaf $remoteReport);timestampUtc=(Get-Date).ToUniversalTime().ToString('o')}
            [IO.File]::WriteAllText($localEvidence,(($parentFailure|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
            throw "$($parentFailure.error); evidenceLocal=$localEvidence"
        }
        $report|Add-Member -NotePropertyName evidenceLabel -NotePropertyValue $safeEvidenceLabel -Force
        $report|Add-Member -NotePropertyName phaseId -NotePropertyValue ([string]$Context.phaseId) -Force
        $report|Add-Member -NotePropertyName candidatePath -NotePropertyValue ([string]$candidate.path) -Force
        $report|Add-Member -NotePropertyName interactiveSessionId -NotePropertyValue ([int]$interactiveProof.sessionId) -Force
        $report|Add-Member -NotePropertyName evidenceProvenance -NotePropertyValue 'identity-bound WPF launch request / isolated UIA worker / terminal supervisor' -Force
        [IO.File]::WriteAllText($localEvidence,(($report|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        $reportStatus=[string]$report.status
        if($reportStatus -in @('PASS','REBOOT_REQUIRED','DURABLE_PENDING','OBSERVER_HANDOFF')){
            foreach($identity in @($report.driverIdentity,$report.candidateIdentity)){if(-not $identity -or -not $identity.present -or [string]$identity.domain -cne 'DEVFLEET-E2E-01' -or [string]$identity.user -cne 'E2EAdmin' -or [int]$identity.sessionId -ne [int]$interactiveProof.sessionId -or [int]$identity.sessionId -eq 0){throw 'WPF launch acknowledgement did not preserve exact E2EAdmin interactive identity.'}}
            if(-not [string]$report.processStartTime){throw 'WPF launch acknowledgement did not preserve the exact candidate process start time.'}
            if(-not $report.bootIdentity -or [string]$report.bootIdentity.status -ne 'PASS' -or -not [string]$report.bootIdentity.lastBootUpTimeUtc){throw 'WPF launch acknowledgement did not preserve the exact guest boot identity.'}
        }
        if(-not $DeferDurableCompletionFallback -and $reportStatus -eq 'OBSERVER_HANDOFF'){$fallback=Invoke-RebootResumeWpfFallback -Context $Context -Session $session -DriverReport $report;$report=[pscustomobject]@{status='PASS';action=$Action;role=$Role;candidateSha256=[string]$candidate.sha256;processId=$report.processId;completionVerified=$true;mutationInvoked=$true;fallback=$fallback};$reportStatus='PASS'}
        $accepted=@('PASS');if($AllowRebootRequired){$accepted+='REBOOT_REQUIRED'};if($DeferDurableCompletionFallback){$accepted+='OBSERVER_HANDOFF'}
        if($reportStatus -notin $accepted){$failure=Get-WpfFailureDescriptor -Report $report;throw "Real WPF action did not pass for ${Action}: status=$reportStatus; class=$([string]$failure.failureClass); error=$([string]$failure.error); evidenceLocal=$localEvidence"}
        if($sentinels){$sentinelVerification=Test-GuestForeignSentinels -Session $session -Sentinels $sentinels}
        $overallStatus=switch($reportStatus){'REBOOT_REQUIRED'{'REAL E2E REBOOT REQUIRED';break}'OBSERVER_HANDOFF'{'REAL E2E OBSERVER HANDOFF';break}default{'REAL E2E PASS'}}
        return [ordered]@{status=$overallStatus;phase=$Context.phaseId;action=$Action;role=$Role;candidate=$candidate;stage=$stage;driverStage=$driverStage;contractStage=$contractStage;guest=$report;evidencePath=$localEvidence;remoteEvidencePath=$remoteReport;evidenceLabel=$safeEvidenceLabel;mutationAllowed=[bool]$AllowMutation;foreignSentinels=$sentinelVerification;launchId=$launchId;oauthStaging=$oauthStage}
    } finally {
        if($oauthStageAttempted -and -not $DeferOAuthCredentialCleanup){Invoke-DevFleetTailscaleOAuthCredentialCleanup -Context $Context -Session $session|Out-Null}
        if($session -and $sentinels){$sentinelCleanup=Remove-GuestForeignSentinels -Session $session -Sentinels $sentinels};if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}
    }
}

function Invoke-PrimaryRolePhase {
    param([Parameter(Mandatory)][string]$ContextJson)
    $context = Read-PhaseContext $ContextJson
    $result = Invoke-ActualWpfAction -Context $context -Action 'Diagnostics' -Role 'Primary / Desktop' -AllowMutation:$false
    if ([string]$result.guest.role -ne 'Primary / Desktop') { throw 'Primary phase did not verify the exact Primary / Desktop role.' }
    if ([bool]$result.guest.mutationInvoked) { throw 'Primary phase diagnostics unexpectedly invoked a mutation.' }
    return [ordered]@{ status='REAL E2E PASS'; phase=$context.phaseId; contract='primary-role-diagnostics'; candidate=$result.candidate; role=$result.role; guest=$result.guest; evidencePath=$result.evidencePath }
}

function Invoke-SurrogateDisposablePhase {
    param([Parameter(Mandatory)][psobject]$Context)
    $result = Invoke-SupportedFreshInstallLifecycle -Context $Context -Role 'Laptop / Surrogate' -CompleteLifecycle
    if ([string]$result.guest.role -ne 'Laptop / Surrogate') { throw 'Disposable surrogate phase did not verify the Laptop / Surrogate role.' }
    if (-not [bool]$result.guest.mutationInvoked) { throw 'Disposable surrogate phase did not invoke the real mutation.' }
    if ([string]$result.status -ne 'REAL E2E PASS' -or -not [bool]$result.guest.completionVerified) {
        throw "SURROGATE-DISPOSABLE requires genuine final lifecycle PASS; observed $($result.status)."
    }
    return [ordered]@{status='REAL E2E PASS';phase='SURROGATE-DISPOSABLE';contract='disposable-laptop-surrogate-real-wpf-install';product=$result;candidate=$result.candidate;role=$result.role;guest=$result.guest;evidencePath=$result.evidencePath;physicalSurfaceTouched=$false;testKitEligibility='EVIDENCE INPUT ONLY - RECONCILE DECIDES'}
}

function Invoke-TailscalePolicyPhase {
    param([Parameter(Mandatory)][psobject]$Context)
    $candidate=Assert-ExactCandidate $Context
    $configuredMode=[string]$Context.config.Tailscale.Mode
    if([string]$Context.phaseId -eq 'TAILSCALE-AUTH') {
        $session=$null
        try {
            $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
            $tailscaleConfig=$Context.config.Tailscale|ConvertTo-Json -Depth 16|ConvertFrom-Json
            $authConfig=$tailscaleConfig.Authentication
            $provider=if($authConfig.PSObject.Properties['Provider']){[string]$authConfig.Provider}else{''}
            if($provider-in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){
                $authConfig|Add-Member -NotePropertyName Hostname -NotePropertyValue (Get-TailscaleE2EHostname -RunId ([string]$Context.runId) -Role 'windows') -Force
            }
            $tailscaleWaitSeconds=if($tailscaleConfig.PSObject.Properties['PollTimeoutSeconds'] -and [int]$tailscaleConfig.PollTimeoutSeconds -gt 0){[int]$tailscaleConfig.PollTimeoutSeconds}else{120}
            $tailscaleOwnerDeadline=[datetime]::UtcNow.AddSeconds($tailscaleWaitSeconds+30)
            $auth=Invoke-TailscaleAuthentication -Session $session -Config $tailscaleConfig -OwnerDeadlineUtc $tailscaleOwnerDeadline
            if(-not [bool]$auth.authenticationAttempted -and [bool]$auth.userActionRequired) { Write-TailscaleOAuthActionRequired; throw "USER ACTION REQUIRED - TAILSCALE-AUTH: $([string]$auth.reason)." }
            Assert-TailscaleAuthenticationResult -Result $auth | Out-Null
            $productConfigPath=Join-Path ((Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path) 'source\config\devfleet.config.json'
            if(-not(Test-Path -LiteralPath $productConfigPath -PathType Leaf)){throw 'TAILSCALE_CONTROL_PLANE_OFFLINE: product configuration is unavailable for readiness endpoint discovery.'}
            $productConfig=Get-Content -LiteralPath $productConfigPath -Raw|ConvertFrom-Json -ErrorAction Stop
            $expectedPeer=Get-TailscaleE2EHostname -RunId ([string]$Context.runId) -Role 'primary'
            $servicePort=[int]$productConfig.Network.PortalPort
            $servicePath='/healthz'
            $expectedNode=if($provider-in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){Get-TailscaleE2EHostname -RunId ([string]$Context.runId) -Role 'windows'}else{[string]$Context.config.Tailscale.ExpectedGuestNodePattern}
            $expectedTag=if($authConfig.PSObject.Properties['Tag']){[string]$authConfig.Tag}else{''}
            $readiness=Get-TailscaleReadiness -Session $session -ExpectedNodePattern $expectedNode -ExpectedTag $expectedTag -ExpectedPeer $expectedPeer -ServicePort $servicePort -ServicePath $servicePath -OwnerDeadlineUtc $tailscaleOwnerDeadline
            if(-not [bool]$readiness.ready){throw "$([string]$readiness.failureClass): TAILSCALE-AUTH structured readiness did not pass."}
            return [ordered]@{status='REAL E2E PASS';phase=[string]$Context.phaseId;contract=if($provider-in @('OAuthClientSecretStore','OAuthAutomation','OAuthClientSecretDpapi')){'oauth-client-secret-provider-with-layered-readiness'}else{'auth-key-fallback-provider-with-layered-readiness'};configuredMode=$configuredMode;candidate=$candidate;guest=$readiness.layer2;readiness=$readiness;authenticationAttempted=[bool]$auth.authenticationAttempted;authenticationSucceeded=[bool]$auth.authenticationSucceeded;authProvider=$provider;expectedPeer=$expectedPeer;servicePort=$servicePort;servicePath=$servicePath;credentialsStoredInEvidence=$false;userActionRequired=$false}
        }finally{if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}}
    }
    if($configuredMode -ne 'Deferred'){throw 'USER ACTION REQUIRED - configured Tailscale policy requires the official interactive authentication boundary.'}
    $session=$null
    try{
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        $status=Get-TailscaleGuestStatus -Session $session -ExpectedNodePattern ([string]$Context.config.Tailscale.ExpectedGuestNodePattern)
        if([bool]$status.online -or -not[bool]$status.needsLogin){throw 'Deferred Tailscale policy expected an installed but unauthenticated guest.'}
        if([string]::IsNullOrWhiteSpace([string]$status.version) -or [string]$status.version -match 'not recognized|not found'){throw 'Deferred Tailscale policy could not verify the installed Tailscale client.'}
        return [ordered]@{status='REAL E2E PASS';phase=[string]$Context.phaseId;contract=if([string]$Context.phaseId -eq 'TAILSCALE-DEFERRED'){'installed-client-deferred-no-auth'}else{'authentication-explicitly-not-run-by-supported-deferred-policy'};configuredMode=$configuredMode;candidate=$candidate;guest=$status;authenticationAttempted=$false;credentialsStoredInEvidence=$false;userActionRequired=$false}
    }finally{if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}}
}

function ConvertTo-LfShellText([string]$Text) {
    if ($null -eq $Text) { return '' }
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Invoke-LinuxBootstrapPhase {
    param([Parameter(Mandatory)][string]$ContextJson)
    $context = Read-PhaseContext $ContextJson
    $candidate = Assert-ExactCandidate $context
    $tarPath = [string]$context.candidate.tar.path
    if (-not (Test-Path -LiteralPath $tarPath -PathType Leaf)) { throw "Linux phase TAR is missing: $tarPath" }
    $tarHash = (Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($tarHash -ne [string]$context.candidate.tar.sha256) { throw 'Linux phase TAR hash differs from the exact candidate tuple.' }
    $aiBundle = $null
    $aiBundleFound=$false;$aiBundleValue=Get-LifecycleProperty $context 'aiAuditZip' ([ref]$aiBundleFound);if ($aiBundleFound -and $aiBundleValue) {
        $aiPathFound=$false;$aiPathValue=Get-LifecycleProperty $aiBundleValue 'path' ([ref]$aiPathFound);$aiHashFound=$false;$aiHashValue=Get-LifecycleProperty $aiBundleValue 'sha256' ([ref]$aiHashFound);$aiBundlePath = [string]$aiPathValue
        $expectedAiBundleHash = ([string]$aiHashValue).ToLowerInvariant()
        if (-not (Test-Path -LiteralPath $aiBundlePath -PathType Leaf)) { throw "Focused Linux AI audit bundle is missing: $aiBundlePath" }
        if ($expectedAiBundleHash -notmatch '^[0-9a-f]{64}$') { throw 'Focused Linux AI audit bundle is missing an exact SHA-256 identity.' }
        $actualAiBundleHash = (Get-FileHash -LiteralPath $aiBundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualAiBundleHash -ne $expectedAiBundleHash) { throw 'Focused Linux AI audit bundle hash differs from the supplied exact identity.' }
        $aiBundle = [ordered]@{path=(Resolve-Path -LiteralPath $aiBundlePath).Path;sha256=$actualAiBundleHash;bytes=(Get-Item -LiteralPath $aiBundlePath).Length}
    }
    if ([string]$context.vmName -notlike 'DevFleet-E2E-*') { throw 'LINUX phase requires an ownership-scoped disposable L1.' }
    if ($env:COMPUTERNAME -notmatch '^MULATTOTechBOX$|^MULATTOTECHBOX$' -or $env:COMPUTERNAME -match 'SURFACE') { throw 'LINUX phase is not running on the approved MULATTOTECHBOX host.' }
    $l1 = Get-VM -Id ([guid][string]$context.vmId) -ErrorAction Stop
    if ($l1.Name -cne [string]$context.vmName) { throw 'LINUX phase disposable L1 identity/name mismatch.' }
    $vmProcessor = Get-VMProcessor -VM $l1 -ErrorAction Stop
    if (-not [bool]$vmProcessor.ExposeVirtualizationExtensions) { throw 'Disposable L1 does not expose nested virtualization.' }
    $nested = $context.config.NestedLinux
    if (-not $nested) { throw 'E2E config is missing the NestedLinux resource policy.' }
    $l2Name = [string]$nested.Name
    $l2Image = [string]$nested.UbuntuImage
    $l2Cpus = [int]$nested.Cpus
    $l2Memory = [string]$nested.Memory
    $l2Disk = [string]$nested.Disk
    $budgetPolicy = Get-HarnessBudgetPolicy -Config $context.config
    $l2BootstrapTimeout = [int]$budgetPolicy.operationMaximumsSeconds.guestBootstrap
    if ($l2Name -notlike 'DevFleet-E2E-*' -or $l2Name -eq ([string]$context.vmName)) { throw 'Nested Linux identity is outside the disposable E2E namespace.' }
    if ($l2Cpus -lt 1 -or $l2BootstrapTimeout -lt 1) { throw 'Nested Linux resource policy contains an invalid positive integer.' }
    # Each FullRelease phase restores its declared checkpoint independently.
    # The clean checkpoint intentionally has no product prerequisites, so the
    # Linux phase must exercise the candidate's real install path in this same
    # phase before asking the installed L1 to provide Multipass.
    $productInstall = Invoke-SupportedFreshInstallLifecycle -Context $context -Role 'Primary / Desktop' -CompleteLifecycle
    if ([string]$productInstall.status -ne 'REAL E2E PASS' -or -not [bool]$productInstall.guest.completionVerified) {
        throw "LINUX requires a genuine supported FreshInstall lifecycle PASS before Multipass; observed $($productInstall.status)."
    }
    $bootstrapTransactionId = [string]$productInstall.transactionId
    $bootstrapPayloadSha256 = [string]$context.candidate.tar.sha256
    $bootstrapPackageVersion = [string]$context.candidate.releaseVersion
    $bootstrapNodeRole = 'surrogate'
    if ($bootstrapTransactionId -notmatch '^[0-9a-fA-F]{32}$' -or
        $bootstrapPayloadSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $bootstrapPackageVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw 'LINUX product lifecycle did not return an exact bootstrap transaction, payload, or package identity.'
    }
    # The supported Desktop lifecycle leaves its exact product Multipass child
    # running after completion. A fixed 16 GiB nested L1 cannot safely allocate
    # that product child and the independent 4 GiB Linux L2 at the same time.
    # Quiesce only the candidate-bound product identity after its completion
    # authority has passed; never infer ownership from the harness L2 name.
    $productComputeName = Get-DevFleetProductComputeInstanceName -Context $context -Role 'Primary / Desktop'
    if ($productComputeName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$' -or $productComputeName -eq $l2Name -or $productComputeName -like 'DevFleet-E2E-*') {
        throw 'LINUX product compute identity is malformed or overlaps the disposable L2 namespace.'
    }
    $session = $null
    try {
        $session = Connect-DevFleetGuest -VmId ([guid][string]$context.vmId)
        $remoteRoot = "C:\Users\Public\DevFleet-E2E\$($context.runId)\$($context.phaseId)"
        $remoteTar = Join-Path $remoteRoot (Split-Path -Leaf $tarPath)
        Invoke-Command -Session $session -ScriptBlock { param($root) New-Item -ItemType Directory -Force -Path $root | Out-Null } -ArgumentList $remoteRoot
        $stage = Get-StageIntegrity -LocalPath $tarPath -Session $session -RemotePath $remoteTar
        if (-not $stage.equal) { throw 'Exact candidate TAR did not survive host-to-L1 staging.' }
        $remoteAiBundle = $null
        $aiBundleStage = $null
        if ($aiBundle) {
            $remoteAiBundle = Join-Path $remoteRoot (Split-Path -Leaf ([string]$aiBundle.path))
            $aiBundleStage = Get-StageIntegrity -LocalPath ([string]$aiBundle.path) -Session $session -RemotePath $remoteAiBundle
            if (-not $aiBundleStage.equal -or ([string]$aiBundleStage.remoteSha256).ToLowerInvariant() -ne [string]$aiBundle.sha256) { throw 'Exact AI audit ZIP did not survive host-to-L1 staging.' }
        }
        $secretJson = [ordered]@{
            NodeName=$l2Name; NodeRole='surrogate'; FriendlyName='DevFleet E2E Linux'; PortalPort=8787
            DeploymentId=("e2e-$($context.runId)"); NodeId=([guid]::NewGuid().ToString()); CoordinatorNodeId=''
            ProtocolVersion=1; AdminUser='e2e-admin'; AdminPassword=('E2E-' + [guid]::NewGuid().ToString('N')); ApiToken=('e2e-token-' + [guid]::NewGuid().ToString('N'))
            GitName='DevFleet E2E'; GitEmail='e2e@example.invalid'; OllamaBaseUrl=''; OllamaModel='e2e-disabled'; OllamaProfile='stable-interactive'
            DevelopmentProfile='strict'; DockerMode='rootless'; EnableSharedCaches=$false; EnableAnalyzerCache=$true; AutoStartCodexPro=$false
            AllowTailnetPorts=$false; BackupBeforeRebuild=$false; BackupBeforeQuarantine=$true; BackupIntervalMinutes=15; PackageVersion=$context.candidate.releaseVersion
        } | ConvertTo-Json -Compress
        $linuxResult = Invoke-Command -Session $session -ScriptBlock {
            param($remoteTarPath,$expectedTarHash,$runId,$phaseId,$l2,$productCompute,$image,$cpus,$memory,$disk,$secret,$timeoutSeconds,$remoteAiBundlePath,$expectedAiBundleHash,$bootstrapTransactionId,$bootstrapPayloadSha256,$bootstrapPackageVersion,$bootstrapNodeRole)
            $ErrorActionPreference='Stop'
            function ConvertTo-LfShellText([string]$Text) {
                if ($null -eq $Text) { return '' }
                return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
            }
            # Resolve the same trusted machine locations used by the shipping
            # product. PATH/App Execution Alias discovery is not sufficient for
            # a freshly-installed guest and can race the vendor service setup.
            $mpCandidates=@(
                (Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'Multipass\bin\multipass.exe')
            ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
            $mp=$mpCandidates | Select-Object -First 1
            if (-not $mp) {
                $mpCommand=Get-Command multipass.exe -ErrorAction SilentlyContinue
                if (-not $mpCommand) { $mpCommand=Get-Command multipass -ErrorAction SilentlyContinue }
                if ($mpCommand) { $mp=$mpCommand.Source }
            }
            if (-not $mp) { throw 'The real Desktop candidate path did not provide Multipass inside disposable L1.' }
            $started=$false; $marker="/etc/devfleet-e2e-run-$runId"; $lastOperation='initialization'; $lastMpResult=$null; $cloudInitPath=$null; $nestedDeadline=[DateTime]::UtcNow.AddSeconds($timeoutSeconds)
            $result=[ordered]@{status='FAIL';runId=$runId;phase=$phaseId;l1TarSha256=$null;l2TarSha256=$null;l2Name=$l2;productComputeInstanceName=$productCompute;productQuiescence=[ordered]@{status='PENDING';instanceName=$productCompute;initialState=$null;finalState=$null;stopInvoked=$false};ubuntu=$null;multipassVersion=$null;cloudInitSource='exact-candidate-tar:cloud-init/compute.yaml';cloudInitRenderedSha256=$null;cloudInitStatus=$null;devrunnerIdentityPreBootstrap=$false;bootstrapExitCode=$null;bootstrapLogExcerpt=@();postconditions=@{};aiAuditBundle=if($remoteAiBundlePath){[ordered]@{status='PENDING';expectedSha256=$expectedAiBundleHash}}else{[ordered]@{status='NOT REQUESTED'}};failureOperation=$null;lastMultipassCommand=$null;cleanup=$null}
            function Invoke-Mp([string[]]$Arguments,[switch]$DoNotRecord) {
                $remaining=[int][math]::Floor(($nestedDeadline-[DateTime]::UtcNow).TotalSeconds)
                if($remaining -le 0){throw 'Nested Multipass owning deadline expired before starting the next operation.'}
                $effective=[math]::Min(900,$remaining)
                $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$mp;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
                if($psi.PSObject.Properties.Name -contains 'ArgumentList' -and $null -ne $psi.ArgumentList){
                    foreach($argument in $Arguments){[void]$psi.ArgumentList.Add([string]$argument)}
                } else {
                    $quotedArguments=@($Arguments|ForEach-Object{
                        $value=[string]$_
                        if($value.Length -gt 0 -and $value -notmatch '[\s"]'){ $value; return }
                        $builder=[Text.StringBuilder]::new();[void]$builder.Append([char]34);$slashes=0
                        foreach($character in $value.ToCharArray()){
                            if([int]$character -eq 92){$slashes++;continue}
                            if([int]$character -eq 34){for($i=0;$i -lt ($slashes*2+1);$i++){[void]$builder.Append([char]92)};[void]$builder.Append([char]34);$slashes=0;continue}
                            for($i=0;$i -lt $slashes;$i++){[void]$builder.Append([char]92)}
                            $slashes=0;[void]$builder.Append($character)
                        }
                        for($i=0;$i -lt ($slashes*2);$i++){[void]$builder.Append([char]92)}
                        [void]$builder.Append([char]34);$builder.ToString()
                    })
                    $psi.Arguments=$quotedArguments -join ' '
                }
                $process=[Diagnostics.Process]::new();$process.StartInfo=$psi;$out=@();$code=-1
                try{
                    if(-not $process.Start()){throw 'Unable to start Multipass operation.'}
                    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
                    if(-not $process.WaitForExit($effective*1000)){try{$process.Kill($true)}catch{};try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5)))}catch{};throw "Multipass operation timed out after $effective seconds."}
                    try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
                    $out=@($(if($stdout.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stdout.GetAwaiter().GetResult()})+$(if($stderr.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderr.GetAwaiter().GetResult()}) -split "`r?`n" | ForEach-Object {[string]$_})
                    $code=[int]$process.ExitCode
                } finally {$process.Dispose()}
                $record=[pscustomobject]@{arguments=@($Arguments);output=@($out);exitCode=$code}
                if(-not $DoNotRecord){Set-Variable -Scope 1 -Name lastMpResult -Value $record}
                return $record
            }
            try {
                $l1Hash=(Get-FileHash -LiteralPath $remoteTarPath -Algorithm SHA256).Hash.ToLowerInvariant(); $result.l1TarSha256=$l1Hash
                if ($l1Hash -ne $expectedTarHash) { throw 'L1 TAR hash differs from exact candidate TAR.' }
                $lastOperation='product-quiescence-inventory';$productInventory=Invoke-Mp @('list','--format','json');if($productInventory.exitCode -ne 0){throw "Product Multipass inventory failed: $($productInventory.output -join ' ')"};try{$productInventoryJson=($productInventory.output -join "`n")|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Product Multipass inventory was not valid JSON.'};$productRows=@($productInventoryJson.list|Where-Object{[string]$_.name-ceq$productCompute});if($productRows.Count-ne1){throw "Candidate-bound product compute instance '$productCompute' was not uniquely present after lifecycle completion."};$productInitialState=[string]$productRows[0].state;$stopInvoked=$false;if($productInitialState-ceq'Running'){$lastOperation='product-quiescence-stop';$stopProduct=Invoke-Mp @('stop',$productCompute);if($stopProduct.exitCode-ne0){throw "Candidate-bound product compute stop failed: $($stopProduct.output -join ' ')"};$stopInvoked=$true}elseif($productInitialState-cne'Stopped'){throw "Candidate-bound product compute instance '$productCompute' was in unsupported state '$productInitialState'."};$lastOperation='product-quiescence-verify';$productAfter=Invoke-Mp @('list','--format','json');if($productAfter.exitCode-ne0){throw "Product Multipass post-quiescence inventory failed: $($productAfter.output -join ' ')"};try{$productAfterJson=($productAfter.output -join "`n")|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Product Multipass post-quiescence inventory was not valid JSON.'};$productAfterRows=@($productAfterJson.list|Where-Object{[string]$_.name-ceq$productCompute});if($productAfterRows.Count-ne1){throw "Candidate-bound product compute instance '$productCompute' disappeared during quiescence verification."};$productFinalState=[string]$productAfterRows[0].state;if($productFinalState-cne'Stopped'){throw "Candidate-bound product compute instance '$productCompute' did not reach Stopped state; observed '$productFinalState'."};$result.productQuiescence=[ordered]@{status='PASS';instanceName=$productCompute;initialState=$productInitialState;finalState=$productFinalState;stopInvoked=$stopInvoked};$lastOperation='inventory';$existing=$productAfter.output -join "`n"
                if ($existing -match ('"name"\s*:\s*"' + [regex]::Escape($l2) + '"')) { throw "Nested VM identity already exists; refusing to adopt or mutate $l2." }
                $version=$null
                for($attempt=1;$attempt -le 30;$attempt++) {
                    $lastOperation='version-probe'
                    $version=Invoke-Mp @('version')
                    if($version.exitCode -eq 0){break}
                    if($attempt -lt 30){Start-Sleep -Seconds 2}
                }
                if($null -eq $version -or $version.exitCode -ne 0){throw "Multipass version probe failed after bounded retry: $($version.output -join ' ')"}
                $result.multipassVersion=($version.output -join ' ')
                # The shipping product creates the restricted devrunner account
                # through the exact candidate cloud-init template before invoking
                # bootstrap-compute.sh.  Exercise that same prerequisite here;
                # running the bootstrap against a raw Ubuntu image is not the
                # production provisioning contract.
                $lastOperation='cloud-init-template'
                $tarCommand=Get-Command tar.exe -ErrorAction SilentlyContinue
                if(-not $tarCommand){$tarCommand=Get-Command tar -ErrorAction SilentlyContinue}
                if(-not $tarCommand){throw 'Windows tar is unavailable for exact candidate cloud-init extraction.'}
                $previousErrorActionPreference=$ErrorActionPreference
                try{
                    $ErrorActionPreference='Continue'
                    $cloudTemplateOutput=@(& $tarCommand.Source -xOf $remoteTarPath 'cloud-init/compute.yaml' 2>&1|ForEach-Object{[string]$_})
                    $cloudTemplateExit=[int]$LASTEXITCODE
                }finally{$ErrorActionPreference=$previousErrorActionPreference}
                if($cloudTemplateExit -ne 0){throw "Exact candidate cloud-init extraction failed: $($cloudTemplateOutput -join ' ')"}
                $cloudTemplate=$cloudTemplateOutput -join "`n"
                if([string]::IsNullOrWhiteSpace($cloudTemplate)){throw 'Exact candidate cloud-init template is empty.'}
                $yamlNode="'"+$l2.Replace("'","''")+"'"
                $renderedCloudInit=$cloudTemplate.Replace('__NODE_NAME__',$yamlNode).Replace('__NODE_ROLE__',"'surrogate'").Replace('__GIT_NAME_SHELL__',"'DevFleet E2E'").Replace('__GIT_EMAIL_SHELL__',"'e2e@example.invalid'")
                if($renderedCloudInit -match '__[A-Z0-9_]+__'){throw 'Exact candidate cloud-init has unresolved placeholders.'}
                $cloudInitPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-cloud-init.yaml"
                [IO.File]::WriteAllText($cloudInitPath,$renderedCloudInit,[Text.UTF8Encoding]::new($false))
                $result.cloudInitRenderedSha256=(Get-FileHash -LiteralPath $cloudInitPath -Algorithm SHA256).Hash.ToLowerInvariant()
                $lastOperation='launch'
                $launch=(Invoke-Mp @('launch',$image,'--name',$l2,'--cpus',[string]$cpus,'--memory',[string]$memory,'--disk',[string]$disk,'--cloud-init',$cloudInitPath)); if($launch.exitCode -ne 0){throw "Multipass launch failed: $($launch.output -join ' ')"}; $started=$true
                $lastOperation='run-marker'
                $mark=(Invoke-Mp @('exec',$l2,'--','bash','-lc',"echo '$runId' | sudo tee '$marker' >/dev/null")); if($mark.exitCode -ne 0){throw 'Unable to bind nested L2 to this E2E run.'}
                $lastOperation='cloud-init-ready'
                $cloudInitDeadline=(Get-Date).AddSeconds([math]::Min($timeoutSeconds,1200))
                $cloudInitDone=$false
                do{
                    $cloudProbe=Invoke-Mp @('exec',$l2,'--','bash','-lc','cloud-init status --format=json 2>&1 || cloud-init status 2>&1')
                    $cloudText=($cloudProbe.output -join "`n")
                    if($cloudProbe.exitCode -eq 0 -and $cloudText -match '(?im)("status"\s*:\s*"done"|^\s*status:\s*done\s*$)'){$cloudInitDone=$true;break}
                    if($cloudText -match '(?im)("status"\s*:\s*"(error|degraded|failed)"|^\s*status:\s*(error|degraded|failed)\s*$)'){throw "Exact candidate cloud-init failed: $cloudText"}
                    if((Get-Date)-lt $cloudInitDeadline){Start-Sleep -Seconds 5}
                }while((Get-Date)-lt $cloudInitDeadline)
                if(-not $cloudInitDone){throw "Exact candidate cloud-init did not finish before the bounded deadline: $cloudText"}
                $result.cloudInitStatus='done'
                $lastOperation='cloud-init-identity-contract'
                $identityProbe=Invoke-Mp @('exec',$l2,'--','bash','-lc','id -u devrunner >/dev/null && getent group devrunner >/dev/null')
                if($identityProbe.exitCode -ne 0){throw "Exact candidate cloud-init did not create the restricted devrunner identity: $($identityProbe.output -join ' ')"}
                $result.devrunnerIdentityPreBootstrap=$true
                $lastOperation='tar-transfer'
                $transfer=(Invoke-Mp @('transfer',$remoteTarPath,"${l2}:/tmp/devfleet-e2e-candidate.tar.gz")); if($transfer.exitCode -ne 0){throw "L1-to-L2 TAR transfer failed: $($transfer.output -join ' ')"}
                $lastOperation='tar-hash'
                $l2HashProbe=(Invoke-Mp @('exec',$l2,'--','sha256sum','/tmp/devfleet-e2e-candidate.tar.gz')); if($l2HashProbe.exitCode -ne 0){throw 'L2 TAR hash probe failed.'}; $l2Hash=((($l2HashProbe.output -join '').Trim() -split '\s+')[0]).ToLowerInvariant(); $result.l2TarSha256=$l2Hash
                if($l2Hash -ne $expectedTarHash){throw 'L2 TAR hash differs from exact candidate TAR.'}
                $lastOperation='payload-reset'
                $removePayload=(Invoke-Mp @('exec',$l2,'--','rm','-rf','/tmp/devfleet-e2e-payload')); if($removePayload.exitCode -ne 0){throw 'Unable to reset the exact candidate extraction directory in L2.'}
                $makePayload=(Invoke-Mp @('exec',$l2,'--','mkdir','-m','0755','/tmp/devfleet-e2e-payload')); if($makePayload.exitCode -ne 0){throw 'Unable to create the exact candidate extraction directory in L2.'}
                $lastOperation='payload-extraction'
                $extractArchive=(Invoke-Mp @('exec',$l2,'--','tar','-xzf','/tmp/devfleet-e2e-candidate.tar.gz','-C','/tmp/devfleet-e2e-payload')); if($extractArchive.exitCode -ne 0){throw 'Exact candidate extraction failed in L2.'}
                $lastOperation='entrypoint-probe'
                $entrypointProbe=(Invoke-Mp @('exec',$l2,'--','test','-f','/tmp/devfleet-e2e-payload/linux/bootstrap-compute.sh')); if($entrypointProbe.exitCode -ne 0){throw 'Exact candidate bootstrap entrypoint check failed in L2.'}
                $secretPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-secrets.json"; [IO.File]::WriteAllText($secretPath,$secret,[Text.UTF8Encoding]::new($false))
                try {
                    $lastOperation='secret-transfer'
                    $secretTransfer=(Invoke-Mp @('transfer',$secretPath,"${l2}:/tmp/devfleet-e2e-secrets.json")); if($secretTransfer.exitCode -ne 0){throw 'Ephemeral synthetic secret transfer failed.'}
                    $bootstrapScriptPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-bootstrap.sh"
                    $bootstrapScript=@'
#!/usr/bin/env bash
set +e
sudo chmod 600 /tmp/devfleet-e2e-secrets.json
timeout __TIMEOUT__ sudo bash /tmp/devfleet-e2e-payload/linux/bootstrap-compute.sh /tmp/devfleet-e2e-payload --secrets-stdin --transaction-id '__TRANSACTION_ID__' --payload-sha256 '__PAYLOAD_SHA256__' --bootstrap-max-seconds '__BOOTSTRAP_MAX_SECONDS__' --package-version '__PACKAGE_VERSION__' --node-role '__NODE_ROLE__' < /tmp/devfleet-e2e-secrets.json
code=$?
sudo rm -f /tmp/devfleet-e2e-secrets.json
exit "$code"
'@
                    $bootstrapScript=$bootstrapScript.Replace('__TIMEOUT__',[string]$timeoutSeconds).Replace('__TRANSACTION_ID__',[string]$bootstrapTransactionId).Replace('__PAYLOAD_SHA256__',[string]$bootstrapPayloadSha256).Replace('__BOOTSTRAP_MAX_SECONDS__',[string]$timeoutSeconds).Replace('__PACKAGE_VERSION__',[string]$bootstrapPackageVersion).Replace('__NODE_ROLE__',[string]$bootstrapNodeRole)
                    [IO.File]::WriteAllText($bootstrapScriptPath,(ConvertTo-LfShellText $bootstrapScript),[Text.UTF8Encoding]::new($false))
                    $lastOperation='bootstrap-wrapper-transfer'
                    $bootstrapTransfer=(Invoke-Mp @('transfer',$bootstrapScriptPath,"${l2}:/tmp/devfleet-e2e-bootstrap.sh")); if($bootstrapTransfer.exitCode -ne 0){throw 'Ephemeral Linux bootstrap wrapper transfer failed.'}
                    $lastOperation='bootstrap'
                    $boot=Invoke-Mp @('exec',$l2,'--','bash','/tmp/devfleet-e2e-bootstrap.sh');$bootOutput=@($boot.output);$result.bootstrapExitCode=[int]$boot.exitCode; $result.bootstrapLogExcerpt=@($bootOutput | ForEach-Object {[string]$_} | Select-Object -Last 120 | ForEach-Object { if($_.Length -gt 400){$_.Substring(0,400)}else{$_} })
                    if($result.bootstrapExitCode -ne 0){throw 'Real Linux bootstrap returned a non-zero exit code.'}
                } finally { Remove-Item -LiteralPath $secretPath -Force -ErrorAction SilentlyContinue; if($bootstrapScriptPath){Remove-Item -LiteralPath $bootstrapScriptPath -Force -ErrorAction SilentlyContinue}; [void](Invoke-Mp -Arguments @('exec',$l2,'--','rm','-f','/tmp/devfleet-e2e-bootstrap.sh','/tmp/devfleet-e2e-secrets.json') -DoNotRecord) }
                $checkScriptPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-postconditions.sh"
                $checkScript=@'
#!/usr/bin/env bash
set +e
overall=0
if (. /etc/os-release && test "$VERSION_ID" = "24.04"); then echo 'ubuntu=PASS'; else echo 'ubuntu=FAIL'; overall=1; fi
if test "$(ps -p 1 -o comm=)" = systemd; then echo 'systemd=PASS'; else echo 'systemd=FAIL'; overall=1; fi
if systemctl is-active --quiet devfleet.service; then echo 'service=PASS'; else echo 'service=FAIL'; overall=1; fi
if sudo -n -u devfleet-control -- test -s /etc/devfleet/config.json && sudo -n -u devfleet-control -- jq -e . /etc/devfleet/config.json >/dev/null; then echo 'config=PASS'; else echo 'config=FAIL'; overall=1; fi
uid=$(id -u devrunner)
if sudo -n -u devrunner test -S /run/user/$uid/docker.sock && sudo -n -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid DOCKER_HOST=unix:///run/user/$uid/docker.sock docker info --format '{{json .SecurityOptions}}' | grep -q rootless; then echo 'rootless=PASS'; else echo 'rootless=FAIL'; overall=1; fi
if sudo -n -u devfleet-control env DOCKER_HOST=unix:///run/user/$uid/docker.sock docker info >/dev/null; then echo 'controlSocket=PASS'; else echo 'controlSocket=FAIL'; overall=1; fi
if sudo -n -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid DOCKER_HOST=unix:///run/user/$uid/docker.sock docker run --rm hello-world >/dev/null; then echo 'container=PASS'; else echo 'container=FAIL'; overall=1; fi
if curl --fail --silent --show-error --connect-timeout 5 http://127.0.0.1:8787/healthz >/dev/null; then echo 'health=PASS'; else echo 'health=FAIL'; overall=1; fi
if test "$(sudo -n -u devfleet-control -- stat -c %U:%G:%a /etc/devfleet/config.json)" = root:devfleet-control:640 && test "$(sudo -n -u devfleet-control -- stat -c %U:%G:%a /etc/devfleet/secrets.env)" = root:devfleet-control:640; then echo 'ownership=PASS'; else echo 'ownership=FAIL'; overall=1; fi
if ! journalctl -k -b --no-pager 2>/dev/null | grep -Eiq 'out of memory|oom-killer|killed process'; then echo 'oom=PASS'; else echo 'oom=FAIL'; overall=1; fi
exit "$overall"
'@
                [IO.File]::WriteAllText($checkScriptPath,(ConvertTo-LfShellText $checkScript),[Text.UTF8Encoding]::new($false))
                try {
                    $lastOperation='postcondition-transfer'
                    $checkTransfer=(Invoke-Mp @('transfer',$checkScriptPath,"${l2}:/tmp/devfleet-e2e-postconditions.sh")); if($checkTransfer.exitCode -ne 0){throw 'Linux postcondition script transfer failed.'}
                    $lastOperation='postconditions'
                    $check=Invoke-Mp @('exec',$l2,'--','bash','/tmp/devfleet-e2e-postconditions.sh');$checkOutput=@($check.output);$checkExit=[int]$check.exitCode
                    foreach($name in @('ubuntu','systemd','service','config','rootless','controlSocket','container','health','ownership','oom')) { $line=@($checkOutput | ForEach-Object {[string]$_} | Where-Object {$_ -match ('^'+[regex]::Escape($name)+'=(PASS|FAIL)$')} | Select-Object -Last 1); $pass=($line.Count -eq 1 -and [string]$line[0] -eq ($name+'=PASS')); $result.postconditions[$name]=[ordered]@{pass=[bool]$pass;output=$line}; if(-not $pass){throw "Linux postcondition failed: $name"} }
                    if($checkExit -ne 0){throw 'One or more Linux postconditions failed.'}
                } finally { Remove-Item -LiteralPath $checkScriptPath -Force -ErrorAction SilentlyContinue; [void](Invoke-Mp -Arguments @('exec',$l2,'--','rm','-f','/tmp/devfleet-e2e-postconditions.sh') -DoNotRecord) }
                if($remoteAiBundlePath){
                    $lastOperation='ai-bundle-transfer'
                    $aiTransfer=Invoke-Mp @('transfer',$remoteAiBundlePath,"${l2}:/tmp/devfleet-e2e-ai-audit.zip")
                    if($aiTransfer.exitCode -ne 0){throw "L1-to-L2 AI audit ZIP transfer failed: $($aiTransfer.output -join ' ')"}
                    $aiValidationScriptPath=Join-Path $env:TEMP "DevFleet-E2E-$runId-ai-bundle.sh"
                    $aiValidationScript=@'
#!/usr/bin/env bash
set -euo pipefail
expected_hash="$1"
archive=/tmp/devfleet-e2e-ai-audit.zip
extract_root="/tmp/devfleet e2e ai audit"
actual_hash="$(sha256sum "$archive" | awk '{print $1}')"
test "$actual_hash" = "$expected_hash"
rm -rf "$extract_root"
mkdir -m 0755 "$extract_root"
unzip -q "$archive" -d "$extract_root"
python3 - "$extract_root" <<'PY'
import json
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
records = json.loads((root / "SOURCE-MODES.json").read_text(encoding="utf-8"))
failures = []
executable = 0
for record in records:
    path = root / record["path"]
    expected = int(record["posixMode"])
    if not path.is_file():
        failures.append(f"missing:{record['path']}")
        continue
    actual = stat.S_IMODE(path.stat().st_mode)
    if actual != expected:
        failures.append(f"mode:{record['path']}:{actual:04o}!={expected:04o}")
    executable += int(bool(record["executable"]))
if failures:
    raise SystemExit(";".join(failures[:20]))
print(json.dumps({"status":"PASS","modeRecords":len(records),"executableRecords":executable}, sort_keys=True))
PY
python3 "$extract_root/source/tools/validate_audit_coherence.py" --root "$extract_root"
python3 -m compileall -q "$extract_root/source" "$extract_root/automation"
while IFS= read -r -d '' script; do bash -n "$script"; done < <(find "$extract_root/source" "$extract_root/automation" -type f -name '*.sh' -print0)
printf 'aiBundle=PASS\n'
'@
                    [IO.File]::WriteAllText($aiValidationScriptPath,(ConvertTo-LfShellText $aiValidationScript),[Text.UTF8Encoding]::new($false))
                    try{
                        $lastOperation='ai-bundle-validator-transfer'
                        $aiValidatorTransfer=Invoke-Mp @('transfer',$aiValidationScriptPath,"${l2}:/tmp/devfleet-e2e-ai-bundle.sh")
                        if($aiValidatorTransfer.exitCode -ne 0){throw 'AI audit Linux validator transfer failed.'}
                        $lastOperation='ai-bundle-linux-roundtrip'
                        $aiCheck=Invoke-Mp @('exec',$l2,'--','bash','/tmp/devfleet-e2e-ai-bundle.sh',$expectedAiBundleHash)
                        $aiOutput=@($aiCheck.output|ForEach-Object{[string]$_})
                        if($aiCheck.exitCode -ne 0 -or $aiOutput -notcontains 'aiBundle=PASS'){throw "AI audit Linux unzip/mode validation failed: $($aiOutput -join ' ')"}
                        $modeJson=@($aiOutput|Where-Object{$_ -match '^\{"executableRecords"'}|Select-Object -Last 1)
                        $coherenceJson=@($aiOutput|Where-Object{$_ -match '^\{"currentReleaseFingerprintId"'}|Select-Object -Last 1)
                        $result.aiAuditBundle=[ordered]@{status='PASS';sha256=$expectedAiBundleHash;standardUnzip=$true;pathWithSpaces=$true;modeInventory=if($modeJson){$modeJson|ConvertFrom-Json}else{$null};coherence=if($coherenceJson){$coherenceJson|ConvertFrom-Json}else{$null};pythonCompile=$true;bashSyntax=$true;output=@($aiOutput|Select-Object -Last 40)}
                    }finally{
                        Remove-Item -LiteralPath $aiValidationScriptPath -Force -ErrorAction SilentlyContinue
                        [void](Invoke-Mp -Arguments @('exec',$l2,'--','rm','-f','/tmp/devfleet-e2e-ai-bundle.sh','/tmp/devfleet-e2e-ai-audit.zip') -DoNotRecord)
                    }
                }
                $result.status='REAL E2E PASS'
            } catch {
                $errorMessage=[string]$_.Exception.Message
                $errorRecord=([string]($_ | Out-String)).Trim()
                if([string]::IsNullOrWhiteSpace($errorMessage)){$errorMessage=$errorRecord}
                if([string]::IsNullOrWhiteSpace($errorMessage) -and $lastMpResult){$errorMessage=(@($lastMpResult.output)-join ' ').Trim()}
                if([string]::IsNullOrWhiteSpace($errorMessage)){$errorMessage='Unknown nested Linux harness failure.'}
                $result.failureOperation=$lastOperation
                if($lastMpResult){$result.lastMultipassCommand=[ordered]@{arguments=@($lastMpResult.arguments);exitCode=[int]$lastMpResult.exitCode;output=@($lastMpResult.output|Select-Object -Last 40)}}
                $result.error="${lastOperation}: $errorMessage"
            }
            finally {
                if($cloudInitPath){Remove-Item -LiteralPath $cloudInitPath -Force -ErrorAction SilentlyContinue}
                if($started){
                    $boundFile=(Invoke-Mp @('exec',$l2,'--','test','-f',$marker))
                    $boundValue=(Invoke-Mp @('exec',$l2,'--','cat',$marker))
                    $bound=($boundFile.exitCode -eq 0 -and $boundValue.exitCode -eq 0 -and (($boundValue.output -join '').Trim() -eq $runId))
                    if($bound){ $deleted=(Invoke-Mp @('delete','--purge',$l2)); $gone=(Invoke-Mp @('list','--format','json')).output -join "`n"; $result.cleanup=[ordered]@{boundToRun=$true;deleteExitCode=$deleted.exitCode;absent=($gone -notmatch ('"name"\s*:\s*"' + [regex]::Escape($l2) + '"'));deleteOutput=(($deleted.output -join ' ') | Select-Object -Last 20)} }
                    else { $result.cleanup=[ordered]@{boundToRun=$false;absent=$false;error='L2 run marker was not positively verified; resource retained for manual cleanup.'} }
                } else { $result.cleanup=[ordered]@{boundToRun=$false;absent=$true;notCreated=$true} }
            }
            $result
        } -ArgumentList $remoteTar,$tarHash,$context.runId,$context.phaseId,$l2Name,$productComputeName,$l2Image,$l2Cpus,$l2Memory,$l2Disk,$secretJson,$l2BootstrapTimeout,$remoteAiBundle,$(if($aiBundle){[string]$aiBundle.sha256}else{$null}),$bootstrapTransactionId,$bootstrapPayloadSha256,$bootstrapPackageVersion,$bootstrapNodeRole
        $evidencePath = Join-Path ([string]$context.runDir) 'linux-l2-evidence.json'
        ($linuxResult | ConvertTo-Json -Depth 32) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        if ([string]$linuxResult.status -ne 'REAL E2E PASS') { throw "Real nested Linux E2E failed: $([string]$linuxResult.error); evidence=$evidencePath" }
        if (-not [bool]$linuxResult.cleanup.absent) { throw "Nested Linux cleanup was not positively verified; evidence=$evidencePath" }
        return [ordered]@{status='REAL E2E PASS';phase='LINUX';contract='nested-multipass-ubuntu-bootstrap-after-real-wpf-install';candidate=$candidate;productInstall=$productInstall;productComputeInstanceName=$productComputeName;productQuiescence=$linuxResult.productQuiescence;hostToL1=$stage;aiBundleHostToL1=$aiBundleStage;l1=$linuxResult.l1TarSha256;l2=$linuxResult;linuxEvidencePath=$evidencePath}
    } finally { if ($session) { Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue } }
}

function Invoke-DependencyMatrix {
    param([Parameter(Mandatory)][psobject]$Context)
    $scenarios = @('Healthy-WinGet','Outdated-Prerequisites','WinGet-Missing','WinGet-Broken','WinGet-Source-Broken','Official-Direct-Fallback','Valid-Nonstandard-Path')
    $records = [System.Collections.Generic.List[object]]::new()
    $healthy = Invoke-SupportedFreshInstallLifecycle -Context $Context -Role 'Primary / Desktop' -CompleteLifecycle
    # A failed product lifecycle returns terminal evidence rather than a
    # completion-shaped candidate/guest object. Read every field through the
    # representation-neutral helper so a dependency-matrix wrapper cannot
    # replace the earliest product failure with a StrictMode property error.
    $healthyStatusFound=$false;$healthyStatusValue=Get-LifecycleProperty -Value $healthy -Name 'status' -Found ([ref]$healthyStatusFound)
    $healthyStatus=if($healthyStatusFound){[string]$healthyStatusValue}else{'UNAVAILABLE'}
    $healthyCandidateFound=$false;$healthyCandidate=Get-LifecycleProperty -Value $healthy -Name 'candidate' -Found ([ref]$healthyCandidateFound)
    $healthyGuestFound=$false;$healthyGuest=Get-LifecycleProperty -Value $healthy -Name 'guest' -Found ([ref]$healthyGuestFound)
    $healthyCompletionFound=$false;$healthyCompletion=Get-LifecycleProperty -Value $healthyGuest -Name 'completionVerified' -Found ([ref]$healthyCompletionFound)
    $healthyErrorFound=$false;$healthyErrorValue=Get-LifecycleProperty -Value $healthy -Name 'error' -Found ([ref]$healthyErrorFound)
    $healthyEvidenceFound=$false;$healthyEvidenceValue=Get-LifecycleProperty -Value $healthy -Name 'evidencePath' -Found ([ref]$healthyEvidenceFound)
    $healthyCompleted=($healthyGuestFound -and $healthyCompletionFound -and [bool]$healthyCompletion)
    [void]$records.Add([ordered]@{scenario='Healthy-WinGet';evidenceClass='REAL_DISPOSABLE_L1';status=$healthyStatus;candidate=$healthyCandidate;guest=$healthyGuest;condition='current trusted WinGet/dependency inventory';actualConditionProven=$healthyCompleted;error=if($healthyErrorFound){[string]$healthyErrorValue}else{''};evidencePath=if($healthyEvidenceFound){[string]$healthyEvidenceValue}else{''}})
    if($healthyStatus -ne 'REAL E2E PASS' -or -not $healthyCompleted){
        $detail=if($healthyErrorFound -and -not [string]::IsNullOrWhiteSpace([string]$healthyErrorValue)){[string]$healthyErrorValue}else{'lifecycle completionVerified was not proven'}
        $evidence=if($healthyEvidenceFound -and -not [string]::IsNullOrWhiteSpace([string]$healthyEvidenceValue)){"; evidence=$([string]$healthyEvidenceValue)"}else{''}
        throw "Healthy-WinGet did not complete the supported exact-candidate lifecycle: status=$healthyStatus; $detail$evidence"
    }
    $workspace = if($Context.workspaceRoot){[string]$Context.workspaceRoot}else{(Resolve-Path (Join-Path $Context.runDir '..\..\..\..')).Path}
    $dotnet = Join-Path $workspace '.dotnet\dotnet.exe'
    if(-not(Test-Path -LiteralPath $dotnet -PathType Leaf)){throw "Explicit repository-local .NET SDK is missing: $dotnet"}
    $sdkVersion = (& $dotnet --version 2>&1 | Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $sdkVersion -ne '8.0.424'){throw "Dependency runner requires repository-local .NET SDK 8.0.424; observed '$sdkVersion'."}
    $sdkHash=(Get-FileHash -LiteralPath $dotnet -Algorithm SHA256).Hash.ToLowerInvariant()
    $sdkEvidence=[ordered]@{schemaVersion=1;contract='explicit-repository-local-dotnet-sdk';path=(Resolve-Path -LiteralPath $dotnet).Path;version=$sdkVersion;sha256=$sdkHash;source='repository-local .dotnet SDK';globalPathMutated=$false;capturedUtc=(Get-Date).ToUniversalTime().ToString('o')}
    Write-EvidenceJson -Path (Join-Path ([string]$Context.runDir) 'dotnet-sdk-evidence.json') -Value $sdkEvidence
    $runnerProject=Join-Path $workspace 'automation\release-e2e\tests\DependencyPolicyRunner\DependencyPolicyRunner.csproj'
    if(-not(Test-Path -LiteralPath $runnerProject -PathType Leaf)){throw 'Tooling-only dependency policy runner is missing.'}
    $steps=[ordered]@{}
    function Invoke-SdkStep([string]$Name,[string[]]$Arguments,[string]$Cwd) {
        $lines=@(& $dotnet @Arguments 2>&1 | ForEach-Object {[string]$_});$exit=[int]$LASTEXITCODE
        $steps[$Name]=[ordered]@{command=@($dotnet)+$Arguments;workingDirectory=$Cwd;exitCode=$exit;stdoutStderr=$lines}
        if($exit -ne 0){
            # Persist the failed step before throwing so a bounded tooling
            # blocker retains stdout/stderr and the exact command contract.
            Write-EvidenceJson -Path (Join-Path ([string]$Context.runDir) 'dependency-policy-runner.json') -Value ([ordered]@{schemaVersion=1;contract='restore-build-run-explicit-local-sdk';status='FAIL';failedStep=$Name;sdk=$sdkEvidence;project=$runnerProject;steps=$steps})
            throw "Dependency policy runner $Name failed with exit code $exit."
        }
        return $lines
    }
    $projectDir=Split-Path -Parent $runnerProject
    [void](Invoke-SdkStep 'restore' @('restore',$runnerProject,'--nologo') $workspace)
    [void](Invoke-SdkStep 'build' @('build',$runnerProject,'--configuration','Release','--nologo','-v:minimal') $workspace)
    $json=Invoke-SdkStep 'run' @('run','--project',$runnerProject,'--configuration','Release','--nologo') $workspace
    Write-EvidenceJson -Path (Join-Path ([string]$Context.runDir) 'dependency-policy-runner.json') -Value ([ordered]@{schemaVersion=1;contract='restore-build-run-explicit-local-sdk';sdk=$sdkEvidence;project=$runnerProject;steps=$steps})
    try{$adversarial=@(($json -join "`n")|ConvertFrom-Json)}catch{throw "Dependency policy runner returned invalid JSON: $($_.Exception.Message)"}
    $scenarioIds=@('WinGet-Missing','WinGet-Broken','WinGet-Source-Broken','Official-Direct-Fallback','Valid-Nonstandard-Path','Outdated-Prerequisites')
    if(@($adversarial.scenario|Sort-Object -Unique).Count -ne $scenarioIds.Count -or @($adversarial).Count -ne $scenarioIds.Count -or (@($adversarial.scenario|Sort-Object -Unique) -join '|') -ne (@($scenarioIds|Sort-Object) -join '|')){throw 'Dependency policy runner returned duplicate, missing, or unexpected scenario IDs.'}
    foreach($row in $adversarial){
        if([string]$row.status -ne 'PASS' -or [string]$row.evidenceClass -ne 'ADVERSARIAL_PRODUCT_POLICY' -or -not [bool]$row.actualConditionProven){throw "Dependency policy scenario did not prove its intended branch: $($row.scenario)."}
        [void]$records.Add($row)
    }
    if(@($records).Count -ne $scenarios.Count){throw 'Dependency matrix did not execute every required policy condition.'}
    return [ordered]@{status='PASS';phase=$Context.phaseId;scenarios=$scenarios;evidence=@($records);contract='one-real-healthy-L1-plus-adversarial-resolver-policy';runner=$runnerProject}
}

function Get-DevFleetNestedPrimaryReadinessScriptBlock {
    # One shared restored-nested readiness route for FullRelease and diagnostics.
    # Providers isolate VM/transport I/O in local tests; live callers omit them.
    return {
        param(
            [Parameter(Mandatory)][string]$Primary,
            [Parameter(Mandatory)][string]$MultipassPath,
            [scriptblock]$NativeProbeProvider=$null,
            [scriptblock]$ControlPlaneRecoveryProvider=$null,
            [scriptblock]$ServiceLookupProvider={Get-CimInstance Win32_Service -Filter "Name='Multipass'" -ErrorAction Stop},
            [scriptblock]$ServiceControlProvider={param($Action)$sc=Join-Path $env:SystemRoot 'System32\sc.exe';if(-not(Test-Path -LiteralPath $sc -PathType Leaf)){throw 'Trusted Windows service controller is missing.'};& $sc $Action Multipass 2>&1|Out-Null},
            [scriptblock]$DaemonLookupProvider={param($Id)Get-Process -Id $Id -ErrorAction Stop},
            [scriptblock]$DaemonStopProvider={param($Id)Stop-Process -Id $Id -Force -ErrorAction Stop},
            [scriptblock]$ClockProvider={[DateTime]::UtcNow},
            [scriptblock]$SleepProvider={param($Milliseconds)Start-Sleep -Milliseconds $Milliseconds},
            [scriptblock]$VmLookupProvider={param($Name,$Id)if($Id){Get-VM -Id ([guid]$Id) -ErrorAction Stop}else{Get-VM -Name $Name -ErrorAction Stop}},
            [scriptblock]$VmStopProvider={param($Vm)Stop-VM -VM $Vm -TurnOff -Confirm:$false -ErrorAction Stop},
            [scriptblock]$VmStartProvider={param($Vm)Start-VM -VM $Vm -Confirm:$false -ErrorAction Stop}
        )
        if($env:COMPUTERNAME -cnotlike 'DEVFLEET-E2E-*'){throw 'Nested readiness is restricted to the disposable L1 guest.'}
        if($Primary -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'){throw 'Configured nested Primary name is invalid.'}
        $mp=$MultipassPath
        function Invoke-NestedMultipass {
            param([Parameter(Mandatory)][string[]]$Arguments,[int]$TimeoutSeconds=300)
            # A restored L1 checkpoint can leave a nested Hyper-V VM running
            # while the Multipass management IP/SSH state is stale.  Every
            # nested call is therefore bounded and owned by this disposable
            # scenario; never reuse this recovery contract for host VMs.
            $effective=[Math]::Max(1,[Math]::Min(900,$TimeoutSeconds))
            $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$mp;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
            if($psi.PSObject.Properties.Name -contains 'ArgumentList' -and $null -ne $psi.ArgumentList){
                foreach($argument in $Arguments){[void]$psi.ArgumentList.Add([string]$argument)}
            } else {
                $quotedArguments=@($Arguments|ForEach-Object{
                    $value=[string]$_
                    if($value.Length -gt 0 -and $value -notmatch '[\s"]'){ $value; return }
                    $builder=[Text.StringBuilder]::new();[void]$builder.Append([char]34);$slashes=0
                    foreach($character in $value.ToCharArray()){
                        if([int]$character -eq 92){$slashes++;continue}
                        if([int]$character -eq 34){for($i=0;$i -lt ($slashes*2+1);$i++){[void]$builder.Append([char]92)};[void]$builder.Append([char]34);$slashes=0;continue}
                        for($i=0;$i -lt $slashes;$i++){[void]$builder.Append([char]92)}
                        $slashes=0;[void]$builder.Append($character)
                    }
                    for($i=0;$i -lt ($slashes*2);$i++){[void]$builder.Append([char]92)}
                    [void]$builder.Append([char]34);$builder.ToString()
                })
                $psi.Arguments=$quotedArguments -join ' '
            }
            $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
            try{
                if(-not $process.Start()){throw 'Unable to start nested Multipass operation.'}
                $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
                if(-not $process.WaitForExit($effective*1000)){
                    try{$process.Kill($true)}catch{
                        $taskkill=Join-Path $env:SystemRoot 'System32\taskkill.exe'
                        if(Test-Path -LiteralPath $taskkill -PathType Leaf){try{& $taskkill '/PID' ([string]$process.Id) '/T' '/F' 2>&1|Out-Null}catch{}}
                    }
                    try{if(-not $process.WaitForExit(5000)){try{$process.Kill()}catch{};[void]$process.WaitForExit(5000)}}catch{}
                    try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
                    $stillRunning=$false;try{$stillRunning=-not $process.HasExited}catch{}
                    if($stillRunning){throw "Nested Multipass operation timed out after $effective seconds and its exact child process could not be terminated: $($Arguments -join ' ')"}
                    throw "Nested Multipass operation timed out after $effective seconds: $($Arguments -join ' ')"
                }
                try{[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(5)))}catch{}
                $stdoutLines=@();$stderrLines=@()
                if($stdout.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stdoutLines=@(([string]$stdout.GetAwaiter().GetResult() -split "`r?`n")|Where-Object{$_.Length -gt 0}|ForEach-Object{[string]$_})}
                if($stderr.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$stderrLines=@(([string]$stderr.GetAwaiter().GetResult() -split "`r?`n")|Where-Object{$_.Length -gt 0}|ForEach-Object{[string]$_})}
                return [pscustomobject]@{exitCode=[int]$process.ExitCode;stdout=$stdoutLines;stderr=$stderrLines;output=@($stdoutLines)+@($stderrLines)}
            } finally {$process.Dispose()}
        }
        function Invoke-NestedMultipassControlPlaneRecovery {
            param([Parameter(Mandatory)][string]$Reason,[Parameter(Mandatory)][datetime]$OwnerDeadlineUtc)
            $service=@(& $ServiceLookupProvider)
            if($service.Count -ne 1){throw "Expected exactly one Multipass service; found $($service.Count)."}
            $service=$service[0]
            $expectedDaemon=Join-Path (Split-Path -Parent $mp) 'multipassd.exe'
            $serviceCommand=[Environment]::ExpandEnvironmentVariables([string]$service.PathName)
            if($serviceCommand -notmatch [regex]::Escape($expectedDaemon)){throw 'Multipass service executable does not match the trusted installation.'}
            if([string]$service.StartName -notin @('LocalSystem','NT AUTHORITY\SYSTEM')){throw 'Multipass service identity is not LocalSystem.'}
            $before=[string]$service.State;$initialPid=[int]$service.ProcessId;$forced=$false;$autoRestarted=$false
            if($before -ne 'Stopped'){& $ServiceControlProvider 'stop'}
            $stopDeadline=([datetime](& $ClockProvider)).AddSeconds(20);if($OwnerDeadlineUtc -lt $stopDeadline){$stopDeadline=$OwnerDeadlineUtc}
            do{$service=@(& $ServiceLookupProvider);if($service.Count -ne 1){throw "Expected exactly one Multipass service during stop; found $($service.Count)."};$service=$service[0];if([string]$service.State -eq 'Stopped'){break};& $SleepProvider 250}while([datetime](& $ClockProvider) -lt $stopDeadline)
            if([string]$service.State -ne 'Stopped'){
                $daemonPid=[int]$service.ProcessId;if($daemonPid -le 0){$daemonPid=$initialPid}
                if($daemonPid -le 0){throw "Multipass service remained $([string]$service.State) without an exact daemon PID."}
                $daemon=& $DaemonLookupProvider $daemonPid
                if([string]$daemon.ProcessName -cne 'multipassd'){throw 'Multipass service PID did not identify the exact multipassd process.'}
                $daemonPath='';try{$daemonPath=[string]$daemon.Path}catch{}
                if(-not [string]::IsNullOrWhiteSpace($daemonPath) -and [IO.Path]::GetFullPath($daemonPath) -cne [IO.Path]::GetFullPath($expectedDaemon)){throw 'Multipass daemon PID resolved outside the trusted installation.'}
                & $DaemonStopProvider $daemonPid;$forced=$true
                $forcedDeadline=([datetime](& $ClockProvider)).AddSeconds(10);if($OwnerDeadlineUtc -lt $forcedDeadline){$forcedDeadline=$OwnerDeadlineUtc}
                do{& $SleepProvider 250;$service=@(& $ServiceLookupProvider);if($service.Count -ne 1){throw "Expected exactly one Multipass service after daemon termination; found $($service.Count)."};$service=$service[0]}while([string]$service.State -ne 'Stopped' -and [datetime](& $ClockProvider) -lt $forcedDeadline)
                if([string]$service.State -eq 'Running'){
                    # SCM may restart the service immediately after its exact daemon exits.
                    # Accept only a distinct trusted daemon; the caller must still re-probe
                    # Multipass JSON inventory and the configured Primary's SSH readiness.
                    $replacementPid=[int]$service.ProcessId
                    if($replacementPid -le 0 -or $replacementPid -eq $daemonPid){throw 'Multipass service is Running without a new exact daemon PID after termination.'}
                    $replacement=& $DaemonLookupProvider $replacementPid
                    $replacementPath='';try{$replacementPath=[string]$replacement.Path}catch{}
                    if([string]$replacement.ProcessName -cne 'multipassd' -or [string]::IsNullOrWhiteSpace($replacementPath) -or [IO.Path]::GetFullPath($replacementPath) -cne [IO.Path]::GetFullPath($expectedDaemon)){throw 'Multipass service auto-restarted outside the trusted daemon identity.'}
                    $autoRestarted=$true
                }elseif([string]$service.State -ne 'Stopped'){throw "Multipass service did not reach Stopped after exact daemon termination; state=$([string]$service.State)."}
            }
            if([datetime](& $ClockProvider) -ge $OwnerDeadlineUtc){throw 'Multipass control-plane recovery exhausted the readiness deadline before restart.'}
            if(-not $autoRestarted){& $ServiceControlProvider 'start'}
            $startDeadline=([datetime](& $ClockProvider)).AddSeconds(45);if($OwnerDeadlineUtc -lt $startDeadline){$startDeadline=$OwnerDeadlineUtc}
            do{$service=@(& $ServiceLookupProvider);if($service.Count -ne 1){throw "Expected exactly one Multipass service during start; found $($service.Count)."};$service=$service[0];if([string]$service.State -eq 'Running'){break};& $SleepProvider 250}while([datetime](& $ClockProvider) -lt $startDeadline)
            if([string]$service.State -ne 'Running'){throw "Multipass service did not return to Running before the readiness deadline; state=$([string]$service.State)."}
            [pscustomobject]@{status='PASS';service='Multipass';reason=$Reason;stateBefore=$before;stateAfter=[string]$service.State;forcedDaemonTermination=$forced;trustedDaemonPath=$expectedDaemon;autoRestarted=$autoRestarted;ownerDeadlineUtc=$OwnerDeadlineUtc.ToUniversalTime().ToString('o')}
        }
        function Get-ExactNestedPrimaryVm {
            param([Parameter(Mandatory)][string]$ExpectedName)
            $byName=@(& $VmLookupProvider -Name $ExpectedName)
            if($byName.Count -ne 1){throw "Expected exactly one nested Hyper-V Primary named $ExpectedName; found $($byName.Count)."}
            $selected=$byName[0]
            $immutableId=[guid]$selected.Id
            if($immutableId -eq [guid]::Empty){throw 'Nested Hyper-V Primary did not expose a valid immutable identity.'}
            $byId=& $VmLookupProvider -Id $immutableId
            if($byId.Name -cne $ExpectedName -or [guid]$byId.Id -ne $immutableId){throw 'Nested Hyper-V Primary immutable identity did not revalidate against the configured name.'}
            return $byId
        }
        $probeInvoker=if($NativeProbeProvider){$NativeProbeProvider}else{${function:Invoke-NestedMultipass}}
        $controlPlaneRecoveryInvoker=if($ControlPlaneRecoveryProvider){$ControlPlaneRecoveryProvider}else{${function:Invoke-NestedMultipassControlPlaneRecovery}}
        $readinessDeadline=([datetime](& $ClockProvider)).AddSeconds(180)
        function Assert-NestedReadinessDeadline {
            if([datetime](& $ClockProvider) -ge $readinessDeadline){
                throw 'Nested readiness deadline exhausted; no further VM mutation or readiness acceptance is allowed.'
            }
        }
        # A restored L1 can expose a running nested Hyper-V Primary before
        # its Multipass daemon has a usable management channel. Treat only
        # this bounded transport timeout/nonzero inventory as a recovery
        # condition; identity, readiness, and the final JSON inventory
        # remain mandatory below. The recovery is confined to the exact
        # product Primary inside this disposable L1.
        $primaryReadiness=$null;$controlPlaneRecovery=$null;$inventoryResult=$null;$inventoryError=''
        # Retain only categorical readiness telemetry on failure. Raw guest output,
        # service command lines, addresses, and credentials do not belong here.
        $readinessTrace=[ordered]@{inventory='UNVERIFIED';controlPlane='NONE';hyperVBefore='UNVERIFIED';hyperVCycle='NONE';infoAttempts=0;infoTimeouts=0;lastInfoClass='NOT_RUN'}
        try{$inventoryResult=& $probeInvoker @('list','--format','json') 30}catch{$inventoryError=$_.Exception.Message}
        if($inventoryError -or $inventoryResult.exitCode -ne 0){
            $failureClass=if($inventoryError){'TIMEOUT_OR_TRANSPORT_ERROR'}else{"NONZERO_EXIT_$([int]$inventoryResult.exitCode)"}
            try{$controlPlaneRecovery=& $controlPlaneRecoveryInvoker $failureClass $readinessDeadline;$readinessTrace.controlPlane='RECOVERED'}catch{throw "MULTIPASS_CONTROL_PLANE_RECOVERY_FAILED: $($_.Exception.Message)"}
            $remaining=[int][Math]::Floor(($readinessDeadline-[datetime](& $ClockProvider)).TotalSeconds)
            if($remaining -le 0){throw 'MULTIPASS_CONTROL_PLANE_RECOVERY_FAILED: recovery exhausted the 180-second readiness deadline.'}
            $inventoryResult=$null;$inventoryError=''
            try{$inventoryResult=& $probeInvoker @('list','--format','json') ([Math]::Min(30,$remaining))}catch{$inventoryError=$_.Exception.Message}
            if($inventoryError -or -not $inventoryResult -or $inventoryResult.exitCode -ne 0){$detail=if($inventoryError){$inventoryError}else{@($inventoryResult.output)-join ' '};throw "MULTIPASS_CONTROL_PLANE_UNAVAILABLE_AFTER_RECOVERY: $detail"}
        }
        if($inventoryResult.exitCode -ne 0){throw "Multipass inventory failed inside L1: $($inventoryResult.output -join ' ')"}
        $inventoryRaw=@($inventoryResult.stdout)
        $inventory=($inventoryRaw -join "`n")|ConvertFrom-Json
        $instances=@($inventory.list|Where-Object name -ceq $primary)
        if($instances.Count -ne 1){throw "Expected exactly one configured Primary instance inside L1; found $($instances.Count)."}
        $readinessTrace.inventory='PASS'
        if(-not $primaryReadiness){$primaryReadiness=[ordered]@{initialMultipassState=[string]$instances[0].state;initialInfoExitCode=$null;recovery=if($controlPlaneRecovery){'bounded-Multipass-control-plane-recovery'}else{'none'};controlPlaneRecovery=$controlPlaneRecovery;hyperVStateBefore=$null;ipv4=$null;ready=$false}}else{$primaryReadiness.initialMultipassState=[string]$instances[0].state}
        $infoResult=$null;$infoError=''
        $remaining=[int][Math]::Floor(($readinessDeadline-[datetime](& $ClockProvider)).TotalSeconds)
        if($remaining -gt 0){$readinessTrace.infoAttempts++;try{$infoResult=& $probeInvoker @('info',$primary) ([Math]::Min(90,$remaining))}catch{$infoError=$_.Exception.Message;if($infoError -like 'Nested Multipass operation timed out*'){$readinessTrace.infoTimeouts++}}}else{$infoError='readiness deadline exhausted before initial info probe'}
        $primaryReadiness.initialInfoExitCode=if($infoResult){$infoResult.exitCode}else{$null}
        $infoText=if($infoResult){@($infoResult.stdout)-join "`n"}else{$infoError}
        $ipv4Match=[regex]::Match($infoText,'(?im)^\s*IPv4:\s*(?<ip>\S+)\s*$')
        $infoReady=($infoResult -and $infoResult.exitCode -eq 0 -and $ipv4Match.Success -and $ipv4Match.Groups['ip'].Value -notmatch '^(--|-)$')
        $readinessTrace.lastInfoClass=if($infoReady){'READY'}elseif($infoResult -and $infoResult.exitCode -ne 0){'NONZERO'}elseif($infoResult){'NO_IPV4'}elseif($infoError -like 'Nested Multipass operation timed out*'){'TIMEOUT'}else{'TRANSPORT_ERROR'}
        # Checkpoint restore may preserve Hyper-V Running state without a
        # usable Multipass management address.  Reset only the nested VM in
        # this disposable L1, then wait for Multipass to report IPv4/SSH.
        Assert-NestedReadinessDeadline
        if(-not $infoReady -or [string]$instances[0].state -ceq 'Stopped'){
            $primaryVm=Get-ExactNestedPrimaryVm -ExpectedName $primary
            Assert-NestedReadinessDeadline
            $primaryReadiness.hyperVStateBefore=$primaryVm.State.ToString()
            $readinessTrace.hyperVBefore=$primaryVm.State.ToString()
            if($primaryVm.State -ne 'Off'){& $VmStopProvider $primaryVm}
            Assert-NestedReadinessDeadline
            $restartVm=& $VmLookupProvider -Id ([guid]$primaryVm.Id)
            Assert-NestedReadinessDeadline
            & $VmStartProvider $restartVm|Out-Null
            # A pre-restart info response cannot qualify the restarted instance.
            $infoReady=$false
            $readinessTrace.hyperVCycle='PASS'
            $primaryReadiness.recovery='bounded-disposable-nested-HyperV-powercycle'
        }
        $ready=$infoReady;$lastInfo=$infoText
        if($infoReady){$primaryReadiness.ipv4=$ipv4Match.Groups['ip'].Value}
        while(-not $ready -and [datetime](& $ClockProvider) -lt $readinessDeadline){
            $remaining=[int][Math]::Floor(($readinessDeadline-[datetime](& $ClockProvider)).TotalSeconds);if($remaining -le 0){break}
            $infoResult=$null
            $readinessTrace.infoAttempts++
            try{$infoResult=& $probeInvoker @('info',$primary) ([Math]::Min(30,$remaining));$lastInfo=@($infoResult.output)-join "`n"}catch{$lastInfo=$_.Exception.Message;if($lastInfo -like 'Nested Multipass operation timed out*'){$readinessTrace.infoTimeouts++}}
            if($infoResult){$infoStdout=@($infoResult.stdout)-join "`n";$ipv4Match=[regex]::Match($infoStdout,'(?im)^\s*IPv4:\s*(?<ip>\S+)\s*$')}else{$ipv4Match=$null}
            $readinessTrace.lastInfoClass=if(-not $infoResult){if($lastInfo -like 'Nested Multipass operation timed out*'){'TIMEOUT'}else{'TRANSPORT_ERROR'}}elseif($infoResult.exitCode -ne 0){'NONZERO'}elseif(-not $ipv4Match.Success -or $ipv4Match.Groups['ip'].Value -match '^(--|-)$'){'NO_IPV4'}else{'READY'}
            if($infoResult -and $infoResult.exitCode -eq 0 -and $ipv4Match.Success -and $ipv4Match.Groups['ip'].Value -notmatch '^(--|-)$'){
                $ready=$true;$primaryReadiness.ipv4=$ipv4Match.Groups['ip'].Value;break
            }
            $remaining=[int][Math]::Floor(($readinessDeadline-[datetime](& $ClockProvider)).TotalSeconds);if($remaining -gt 0){& $SleepProvider ([Math]::Min(5000,$remaining*1000))}
        }
        if(-not $ready){$traceText=@($readinessTrace.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join ';';throw "Configured Primary did not become Multipass/SSH-ready within 180 seconds. READINESS_TRACE: $traceText"}
        Assert-NestedReadinessDeadline
        $primaryReadiness.ready=$true
        return $primaryReadiness
    }
}

function Invoke-NestedProductScenario {
    param([Parameter(Mandatory)][psobject]$Context,[Parameter(Mandatory)][string]$Scenario)
    $nestedIdentity=Resolve-DevFleetNestedScenarioIdentity -RunId ([string]$Context.runId) -PhaseId ([string]$Context.phaseId) -Scenario $Scenario
    # Materialize the already-validated identity properties before building a
    # remoting ArgumentList.  PowerShell parses a member access preceded by a
    # type literal differently inside that array expression and can otherwise
    # send the literal text `[string]@{...}.runId` across the boundary.
    $validatedRunId=[string]$nestedIdentity.runId
    $validatedPhaseId=[string]$nestedIdentity.phaseId
    $validatedScenario=[string]$nestedIdentity.scenario
    $candidate=Assert-ExactCandidate $Context
    $tarPath=[string]$Context.candidate.tar.path
    $tarHash=(Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($tarHash -ne [string]$Context.candidate.tar.sha256){throw "Exact candidate TAR changed before $($Context.phaseId)."}
    if([string]$Context.vmName -notlike 'DevFleet-E2E-*'){throw "$($Context.phaseId) requires an ownership-scoped disposable L1."}
    $localDriver=Join-Path $PSScriptRoot 'Invoke-ProductLifecycleScenario.py'
    if(-not(Test-Path -LiteralPath $localDriver -PathType Leaf)){throw 'Product lifecycle scenario driver is missing.'}
    $session=$null
    try{
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        $remoteRoot="C:\Users\Public\DevFleet-E2E\$validatedRunId\$validatedPhaseId"
        $remoteTar=Join-Path $remoteRoot (Split-Path -Leaf $tarPath)
        $remoteDriver=Join-Path $remoteRoot 'Invoke-ProductLifecycleScenario.py'
        Invoke-Command -Session $session -ScriptBlock {param($path) New-Item -ItemType Directory -Path $path -Force|Out-Null} -ArgumentList $remoteRoot
        $stage=Get-StageIntegrity -LocalPath $tarPath -Session $session -RemotePath $remoteTar
        if(-not $stage.equal){throw 'Exact candidate TAR changed while staging to the disposable L1.'}
        Copy-Item -LiteralPath $localDriver -Destination $remoteDriver -ToSession $session -Force
        $driverHash=(Get-FileHash -LiteralPath $localDriver -Algorithm SHA256).Hash.ToLowerInvariant()
        $readinessSource=(Get-DevFleetNestedPrimaryReadinessScriptBlock).ToString()
        $vaultFixtureJson=if($Context.PSObject.Properties['maintenanceVault']){$Context.maintenanceVault|ConvertTo-Json -Depth 8 -Compress}else{''}
        $guestResult=Invoke-Command -Session $session -ScriptBlock {
            param($tar,$expectedTarHash,$driver,$expectedDriverHash,$runId,$phaseId,$scenario,$readinessSource,$vaultFixtureJson)
            $ErrorActionPreference='Stop'
            if($env:COMPUTERNAME -notlike 'DEVFLEET-E2E-*'){throw 'Product scenario is not running inside the disposable L1.'}
            if((Get-FileHash -LiteralPath $tar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedTarHash){throw 'L1 candidate TAR hash mismatch.'}
            if((Get-FileHash -LiteralPath $driver -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedDriverHash){throw 'L1 scenario driver hash mismatch.'}
            $configPath='C:\ProgramData\DevFleet\devfleet.config.json'
            $identityPath='C:\ProgramData\DevFleet\node-identity.json'
            if(-not(Test-Path -LiteralPath $configPath -PathType Leaf) -or -not(Test-Path -LiteralPath $identityPath -PathType Leaf)){throw 'Installed DevFleet L1 configuration or deployment identity is missing.'}
            $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
            $hostIdentity=Get-Content -LiteralPath $identityPath -Raw|ConvertFrom-Json
            $primary=[string]$config.Primary.InstanceName
            if($primary -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$' -or -not [string]$hostIdentity.deployment_id){throw 'Installed Primary/deployment identity is invalid.'}
            $expectedMultipass=Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'
            $multipass=@(Get-Command multipass.exe -All -ErrorAction Stop|Where-Object{$_.Source -ceq $expectedMultipass})
            if($multipass.Count -ne 1){throw 'Trusted machine Multipass resolution is ambiguous or missing inside L1.'}
            $mp=$multipass[0].Source
            $primaryReadiness=. ([scriptblock]::Create($readinessSource)) -Primary $primary -MultipassPath $mp
            if($scenario-in@('permanent-delete','delete-restore','vault')){
                if(-not$vaultFixtureJson){throw 'Positive Vault scenario lacks its configured checkpoint prerequisite.'}
                $fixture=$vaultFixtureJson|ConvertFrom-Json -ErrorAction Stop
                if([string]$fixture.status-cne'PASS'-or[string]$fixture.payloadSha256-cne$expectedTarHash-or[string]$fixture.primaryRole-cne'primary'-or[string]$fixture.primaryName-cne$primary-or[string]$fixture.deploymentId-cne[string]$hostIdentity.deployment_id-or[string]$fixture.vaultName-cne[string]$config.Vault.InstanceName-or$fixture.configurationPresent-isnot[bool]-or-not$fixture.configurationPresent-or$fixture.proofCredit-isnot[bool]-or$fixture.proofCredit){throw 'Configured Vault prerequisite identity/configuration differs.'}
                foreach($entry in @(@{name=$primary;id=$fixture.primaryId},@{name=[string]$fixture.vaultName;id=$fixture.vaultId})){
                    $owned=Get-VM -Id ([guid][string]$entry.id) -ErrorAction Stop
                    if($owned.Name-cne[string]$entry.name){throw 'Configured Vault prerequisite nested immutable identity differs.'}
                }
                # Reuse the existing exact-ID restored-nested readiness route;
                # a checkpoint's VM presence is not an SSH readiness receipt.
                $vaultReadiness=& ([scriptblock]::Create($readinessSource)) -Primary ([string]$fixture.vaultName) -MultipassPath $mp
            }
            $runId=[string]$runId;$phaseId=[string]$phaseId;$scenario=[string]$scenario
            if($runId.Length -gt 128 -or $runId -cnotmatch '\A(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'){
                throw "Nested scenario RunId failed remote ownership validation: length=$($runId.Length)."
            }
            $expectedPhase=switch($scenario){
                'permanent-delete' {'PERMANENT-DELETE'}
                'delete-restore' {'DELETE-RESTORE'}
                'stopped-project' {'STOPPED-PROJECT'}
                'host-concurrency' {'HOST-CONCURRENCY'}
                'operation-recovery' {'OPERATION-RECOVERY'}
                'ownership' {'OWNERSHIP'}
                'vault' {'VAULT'}
                default {throw "Nested scenario identity was not recognized: scenarioLength=$($scenario.Length)."}
            }
            if($phaseId -cne $expectedPhase){throw "Nested scenario phase does not match its destructive scenario identity: phaseLength=$($phaseId.Length)."}
            $expectedRoot="/tmp/devfleet-e2e/$runId/$phaseId"
            if($expectedRoot -cnotmatch '\A/tmp/devfleet-e2e/(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*/[A-Z0-9]+(?:-[A-Z0-9]+)*\z'){
                throw "Nested scenario root failed remote ownership validation: runIdLength=$($runId.Length); phaseIdLength=$($phaseId.Length)."
            }
            $l2Root=$expectedRoot
            $l2Tar="$l2Root/candidate.tar.gz";$l2Driver="$l2Root/Invoke-ProductLifecycleScenario.py"
            $incoming="$l2Root/.incoming";$incomingTar="$incoming/candidate.tar.gz";$incomingDriver="$incoming/Invoke-ProductLifecycleScenario.py"
            $scenarioCompleted=$false
            try{
                $cleanupRoot=Invoke-NestedMultipass @('exec',$primary,'--','sudo','rm','-rf','--',$l2Root)
                if($cleanupRoot.exitCode -ne 0){throw "Nested scenario root cleanup failed: $($cleanupRoot.output -join ' ')"}
                $makeRoot=Invoke-NestedMultipass @('exec',$primary,'--','sudo','install','-d','-o','root','-g','root','-m','0755',$l2Root,"$l2Root/source")
                if($makeRoot.exitCode -ne 0){throw "Nested scenario root could not be created: $($makeRoot.output -join ' ')"}
                $makeIncoming=Invoke-NestedMultipass @('exec',$primary,'--','sudo','install','-d','-o','ubuntu','-g','ubuntu','-m','0700',$incoming)
                if($makeIncoming.exitCode -ne 0){throw "Nested scenario transfer staging could not be created: $($makeIncoming.output -join ' ')"}
                $tarTransfer=Invoke-NestedMultipass @('transfer',$tar,"$primary`:$incomingTar")
                if($tarTransfer.exitCode -ne 0){throw "Candidate TAR transfer from L1 to Primary failed: $($tarTransfer.output -join ' ')"}
                $driverTransfer=Invoke-NestedMultipass @('transfer',$driver,"$primary`:$incomingDriver")
                if($driverTransfer.exitCode -ne 0){throw "Scenario driver transfer from L1 to Primary failed: $($driverTransfer.output -join ' ')"}
                $lockIncoming=Invoke-NestedMultipass @('exec',$primary,'--','sudo','chown','-R','root:root','--',$incoming)
                if($lockIncoming.exitCode -ne 0){throw "Nested scenario transfer staging could not be locked: $($lockIncoming.output -join ' ')"}
                $promoteTar=Invoke-NestedMultipass @('exec',$primary,'--','sudo','install','-T','-o','root','-g','root','-m','0644',$incomingTar,$l2Tar)
                if($promoteTar.exitCode -ne 0){throw "Candidate TAR could not be promoted into the owned root: $($promoteTar.output -join ' ')"}
                $promoteDriver=Invoke-NestedMultipass @('exec',$primary,'--','sudo','install','-T','-o','root','-g','root','-m','0644',$incomingDriver,$l2Driver)
                if($promoteDriver.exitCode -ne 0){throw "Scenario driver could not be promoted into the owned root: $($promoteDriver.output -join ' ')"}
                $removeIncoming=Invoke-NestedMultipass @('exec',$primary,'--','sudo','rm','-rf','--',$incoming)
                if($removeIncoming.exitCode -ne 0){throw "Nested scenario transfer staging cleanup failed: $($removeIncoming.output -join ' ')"}
                $hashResult=Invoke-NestedMultipass @('exec',$primary,'--','sha256sum',$l2Tar)
                $hashLines=@($hashResult.stdout);$l2Hash=if($hashLines.Count -eq 1){([string]$hashLines[0]).Split(' ',[StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant()}else{''}
                if($hashResult.exitCode -ne 0 -or $hashLines.Count -ne 1 -or $l2Hash -ne $expectedTarHash){throw 'L2 candidate TAR hash differs from host/L1 identity.'}
                $driverHashResult=Invoke-NestedMultipass @('exec',$primary,'--','sha256sum',$l2Driver)
                $driverHashLines=@($driverHashResult.stdout);$l2DriverHash=if($driverHashLines.Count -eq 1){([string]$driverHashLines[0]).Split(' ',[StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant()}else{''}
                if($driverHashResult.exitCode -ne 0 -or $driverHashLines.Count -ne 1 -or $l2DriverHash -ne $expectedDriverHash){throw 'L2 scenario driver hash differs from the exact L1 driver.'}
                $extractResult=Invoke-NestedMultipass @('exec',$primary,'--','sudo','tar','-xzf',$l2Tar,'-C',"$l2Root/source")
                if($extractResult.exitCode -ne 0){throw "Exact candidate extraction failed in Primary: $($extractResult.output -join ' ')"}
                $sourceRoot="$l2Root/source"
                $sourceCheck=Invoke-NestedMultipass @('exec',$primary,'--','test','-f',"$sourceRoot/VERSION")
                if($sourceCheck.exitCode -ne 0){throw 'Exact candidate extraction did not produce the canonical source root.'}
                $pythonResult=Invoke-NestedMultipass @('exec',$primary,'--','bash','-lc','for p in /opt/devfleet/venv/bin/python /opt/devfleet/venv/bin/python3; do test -x "$p" && echo "$p" && exit 0; done; exit 1')
                $pythonLines=@($pythonResult.stdout);$python=if($pythonLines.Count -eq 1){[string]$pythonLines[0]}else{''}
                if($pythonResult.exitCode -ne 0 -or $pythonLines.Count -ne 1 -or -not $python.StartsWith('/opt/devfleet/venv/bin/python')){throw 'Installed DevFleet Python runtime is unavailable in Primary.'}
                $scenarioResultRaw=Invoke-NestedMultipass @('exec',$primary,'--','sudo','-u','devfleet-control','env','HOME=/nonexistent',$python,$l2Driver,'--source-root',$sourceRoot,'--run-id',$runId,'--scenario',$scenario)
                $raw=@($scenarioResultRaw.stdout)
                $exit=$scenarioResultRaw.exitCode
                $jsonLine=@($raw|ForEach-Object{[string]$_}|Where-Object{$_.TrimStart().StartsWith('{')}|Select-Object -Last 1)
                if($jsonLine.Count -ne 1){throw "Product scenario returned no structured result: $((@($scenarioResultRaw.output)|Select-Object -Last 8)-join ' | ')"}
                $scenarioResult=$jsonLine[0]|ConvertFrom-Json
                if($exit -ne 0 -or [string]$scenarioResult.status -ne 'PASS'){throw "Product scenario failed: $([string]$scenarioResult.error)"}
                $guestIdentityResult=Invoke-NestedMultipass @('exec',$primary,'--','sudo','cat','/etc/devfleet/node-identity.json')
                $guestIdentityRaw=@($guestIdentityResult.stdout);if($guestIdentityResult.exitCode -ne 0){throw 'Primary node identity could not be read.'}
                $guestIdentity=($guestIdentityRaw -join "`n")|ConvertFrom-Json
                if([string]$guestIdentity.deployment_id -ne [string]$hostIdentity.deployment_id){throw 'Primary deployment identity differs from the owning L1 deployment.'}
                $result=[ordered]@{status='PASS';scenario=$scenario;multipassReadiness=$primaryReadiness;l1=[ordered]@{computer=$env:COMPUTERNAME;deploymentId=[string]$hostIdentity.deployment_id};primary=[ordered]@{name=$primary;deploymentId=[string]$guestIdentity.deployment_id;nodeId=[string]$guestIdentity.node_id};tarSha256=[ordered]@{l1=$expectedTarHash;l2=$l2Hash};product=$scenarioResult;secretsInEvidence=$false}
                $scenarioCompleted=$true
                return $result
            }finally{
                $cleanupFailure=$null
                try{$cleanupResult=Invoke-NestedMultipass @('exec',$primary,'--','sudo','rm','-rf','--',$l2Root);if($cleanupResult.exitCode -ne 0){throw "exit $($cleanupResult.exitCode): $($cleanupResult.output -join ' ')"}}catch{$cleanupFailure=$_.Exception.Message}
                Remove-Item -LiteralPath (Split-Path -Parent $tar) -Recurse -Force -ErrorAction SilentlyContinue
                if($scenarioCompleted -and $cleanupFailure){throw "Nested scenario completed but its exact owned-root cleanup failed: $cleanupFailure"}
            }
        } -ArgumentList $remoteTar,$tarHash,$remoteDriver,$driverHash,$validatedRunId,$validatedPhaseId,$validatedScenario,$readinessSource,$vaultFixtureJson
        $evidencePath=Join-Path ([string]$Context.runDir) ("$($Context.phaseId.ToLowerInvariant())-product-evidence.json")
        [IO.File]::WriteAllText($evidencePath,(($guestResult|ConvertTo-Json -Depth 32)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        return [ordered]@{status='REAL E2E PASS';phase=[string]$Context.phaseId;contract='exact-candidate-product-lifecycle-in-owned-primary';candidate=$candidate;scenario=$Scenario;guest=$guestResult;evidencePath=$evidencePath}
    }finally{if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}}
}

function Invoke-DisposableSyntheticRebootProbe {
    <# Independent harness probe. It owns only a run-scoped PFRO trigger and
       never reads, creates, or advances a product lifecycle checkpoint. #>
    param([Parameter(Mandatory)][psobject]$Context)
    if([string]$Context.vmName -notlike 'DevFleet-E2E-*'){throw 'Synthetic reboot probe requires an ownership-scoped disposable L1.'}
    $session=$null
    try {
        $session=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId)
        $baseline=Invoke-Command -Session $session -ScriptBlock {
            $pfr=@((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
            $meaningful=@($pfr|Where-Object{-not [string]::IsNullOrWhiteSpace([string]$_)});$pairs=@();for($i=0;$i -lt $pfr.Count;$i+=2){$pairs+=[ordered]@{source=[string]$pfr[$i];destination=if($i+1 -lt $pfr.Count){[string]$pfr[$i+1]}else{''}}}
            [ordered]@{boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o');pendingCount=$meaningful.Count;pendingFileRenameOperationsPresent=($meaningful.Count -gt 0);pairs=$pairs}
        }
        $pre=Invoke-Command -Session $session -ScriptBlock {
            param($runId,$phaseId)
            $safeRun=$runId -replace '[^A-Za-z0-9-]','';$safePhase=$phaseId -replace '[^A-Za-z0-9-]',''
            $root="C:\Users\Public\DevFleet-E2E\$safeRun\$safePhase\synthetic-reboot";$source=Join-Path $root 'source.bin';$destination=Join-Path $root 'destination.bin'
            New-Item -ItemType Directory -Force -Path $root|Out-Null;[IO.File]::WriteAllText($source,'DevFleet synthetic reboot probe')
            if(-not ('DevFleetE2EMoveFile' -as [type])){Add-Type @'
using System.Runtime.InteropServices;
public static class DevFleetE2EMoveFile { [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool MoveFileEx(string a,string b,int f); }
'@}
            if(-not [DevFleetE2EMoveFile]::MoveFileEx($source,$destination,4)){throw 'MoveFileEx synthetic trigger failed.'}
            $os=Get-CimInstance Win32_OperatingSystem;[ordered]@{source=$source;destination=$destination;boot=$os.LastBootUpTime.ToUniversalTime().ToString('o');queued=$true}
        } -ArgumentList ([string]$Context.runId),([string]$Context.phaseId)
        try{Invoke-Command -Session $session -ScriptBlock {Restart-Computer -Force} -ErrorAction Stop|Out-Null}catch{}
    }finally{if($session){Remove-DevFleetGuestSession $session -ErrorAction SilentlyContinue}}
    Start-Sleep -Seconds 10;$post=$null;$lastError='';$deadline=(Get-Date).AddMinutes(5)
    do {$probe=$null;try{$probe=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId);$post=Invoke-Command -Session $probe -ScriptBlock {$os=Get-CimInstance Win32_OperatingSystem;[ordered]@{boot=$os.LastBootUpTime.ToUniversalTime().ToString('o')}};if([datetime]$post.boot -le [datetime]$pre.boot){$post=$null}}catch{$lastError=$_.Exception.Message}finally{if($probe){Remove-DevFleetGuestSession $probe -ErrorAction SilentlyContinue}};if(-not $post){Start-Sleep -Seconds 5}}while(-not $post -and (Get-Date)-lt $deadline)
    if(-not $post){throw "Synthetic reboot probe did not observe a changed boot identity: $lastError"}
    $settlementSession=$null;$settled=$null
    try{$settlementSession=Connect-DevFleetGuest -VmId ([guid][string]$Context.vmId);$settled=Invoke-Command -Session $settlementSession -ScriptBlock {param($source,$destination,$baselinePairs)$pfr=@((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations);$meaningful=@($pfr|Where-Object{-not [string]::IsNullOrWhiteSpace([string]$_)});$pairs=@();for($i=0;$i -lt $pfr.Count;$i+=2){$pairs+=[ordered]@{source=[string]$pfr[$i];destination=if($i+1 -lt $pfr.Count){[string]$pfr[$i+1]}else{''}}};$keys=@($pairs|ForEach-Object{"$($_.source)`n$($_.destination)"});$baseKeys=@($baselinePairs|ForEach-Object{"$($_.source)`n$($_.destination)"});[ordered]@{sourceExists=(Test-Path -LiteralPath $source -PathType Leaf);destinationExists=(Test-Path -LiteralPath $destination -PathType Leaf);pendingCount=$meaningful.Count;pendingFileRenameOperationsMeaningfulCount=$meaningful.Count;unrelatedEntriesPreserved=(@($baseKeys|Where-Object{$keys -contains $_}).Count -eq $baseKeys.Count);pairs=$pairs}} -ArgumentList ([string]$pre.source),([string]$pre.destination),@($baseline.pairs)}finally{if($settlementSession){Remove-DevFleetGuestSession $settlementSession -ErrorAction SilentlyContinue}}
    if([bool]$settled.sourceExists -or -not [bool]$settled.destinationExists){throw 'Synthetic reboot run-owned delayed operation did not settle.'}
    # Windows may legitimately consume unrelated pending operations while the
    # owned operation settles. Never delete or rewrite foreign state; retain a
    # before/after comparison for audit and make the ownership-specific verdict
    # the gate.
    $settled.unrelatedStateChangedByHarness=$false
    $settled.unrelatedStatePreserved=[bool]$settled.unrelatedEntriesPreserved
    $settled.ownershipSpecificVerdict='PASS'
    $evidence=[ordered]@{status='PASS';phase='SYNTHETIC-REBOOT-PROBE';contract='run-owned-PFRO-only';baseline=$baseline;preBoot=$pre;postBoot=$post;settlement=$settled;bootIdentityChanged=$true;interactiveDesktop=[ordered]@{status='NOT_APPLICABLE';reason='Synthetic probe does not launch product UI.'};productLifecycleTouched=$false}
    $path=Join-Path ([string]$Context.runDir) 'synthetic-reboot-probe.json';Write-EvidenceJson -Path $path -Value $evidence;$evidence.evidencePath=$path;return $evidence
}

function Invoke-RebootResumePhase {
    param([Parameter(Mandatory)][psobject]$Context,[psobject]$InitialResult,[scriptblock]$WpfProvider,[scriptblock]$TransitionProvider,[scriptblock]$RebootProvider,[scriptblock]$SettleProvider)
    $synthetic=$null
    $skipFound=$false;$skipSynthetic=Get-LifecycleProperty $Context 'skipSyntheticReboot' ([ref]$skipFound);if(-not ($skipFound -and [bool]$skipSynthetic)){
        $syntheticProviderFound=$false;$syntheticProvider=Get-LifecycleProperty $Context 'syntheticRebootProvider' ([ref]$syntheticProviderFound);if($syntheticProviderFound){$synthetic=&$syntheticProvider ([pscustomobject]@{context=$Context;phaseId=(Get-LifecycleProperty $Context 'phaseId' ([ref]$skipFound))})}else{$synthetic=Invoke-DisposableSyntheticRebootProbe -Context $Context}
        $syntheticStatusFound=$false;$syntheticStatus=Get-LifecycleProperty $synthetic 'status' ([ref]$syntheticStatusFound);if(-not $syntheticStatusFound -or [string]$syntheticStatus -ne 'PASS'){throw 'Synthetic reboot probe did not pass.'}
    }
    # The synthetic boundary and product lifecycle are independent proofs. The
    # product loop gets a new WPF process and owns every product generation.
    $product=Invoke-ProductFreshInstallLifecycle -Context $Context -Role 'Primary / Desktop' -WpfProvider $WpfProvider -TransitionProvider $TransitionProvider -RebootProvider $RebootProvider -SettleProvider $SettleProvider
    $productCandidate = if($product.PSObject.Properties['candidate']){$product.candidate}else{$Context.candidate}
    $productGuest = if($product.PSObject.Properties['guest']){$product.guest}else{$null}
    $productEvidence = if($product.PSObject.Properties['evidencePath']){$product.evidencePath}else{$null}
    $completionFound = $false
    $completionValue = Get-LifecycleProperty $product 'completionVerified' ([ref]$completionFound)
    $productCompletionVerified = $completionFound -and [bool]$completionValue
    $statusFound = $false
    $statusValue = Get-LifecycleProperty $product 'status' ([ref]$statusFound)
    $productStatus = if($statusFound){[string]$statusValue}elseif($productCompletionVerified){'REAL E2E PASS'}else{'TERMINAL_FAILURE'}
    if($productStatus -ne 'REAL E2E PASS' -or -not $productCompletionVerified){ return [ordered]@{status='TERMINAL_FAILURE';phase=[string]$Context.phaseId;contract='pure-product-lifecycle';completionVerified=$false;synthetic=$synthetic;product=$product;candidate=$productCandidate;guest=$productGuest;evidencePath=$productEvidence} }
    return [ordered]@{status='REAL E2E PASS';phase=[string]$Context.phaseId;contract=if($synthetic){'synthetic-probe-then-pure-product-lifecycle'}else{'pure-product-lifecycle'};synthetic=$synthetic;product=$product;candidate=$productCandidate;guest=$productGuest;evidencePath=$productEvidence}
}

function Invoke-ProductLifecycleConsumer {
    <# Actual phase dispatch seam used by focused tests and by consumers that
       need only the supported product lifecycle. #>
    param([Parameter(Mandatory)][psobject]$Context)
    $wpfProvider = if ($Context.PSObject.Properties['lifecycleWpfProvider']) { $Context.lifecycleWpfProvider } else { $null }
    $transitionProvider = if ($Context.PSObject.Properties['lifecycleTransitionProvider']) { $Context.lifecycleTransitionProvider } else { $null }
    $rebootProvider = if ($Context.PSObject.Properties['lifecycleRebootProvider']) { $Context.lifecycleRebootProvider } else { $null }
    $settleProvider = if ($Context.PSObject.Properties['lifecycleSettleProvider']) { $Context.lifecycleSettleProvider } else { $null }
    if((Get-ProductLifecycleConsumerMode -PhaseId ([string]$Context.phaseId)) -eq 'SYNTHETIC_THEN_PRODUCT'){
        return Invoke-RebootResumePhase -Context $Context -WpfProvider $wpfProvider -TransitionProvider $transitionProvider -RebootProvider $rebootProvider -SettleProvider $settleProvider
    }
    if((Get-ProductLifecycleConsumerMode -PhaseId ([string]$Context.phaseId)) -eq 'PRODUCT_ONLY'){
        return Invoke-ProductFreshInstallLifecycle -Context $Context -Role 'Primary / Desktop' -WpfProvider $wpfProvider -TransitionProvider $transitionProvider -RebootProvider $rebootProvider -SettleProvider $settleProvider
    }
    throw "No product lifecycle consumer dispatch exists for $($Context.phaseId)."
}

function Get-ProductLifecycleConsumerMode {
    param([Parameter(Mandatory)][string]$PhaseId)
    if($PhaseId -eq 'REBOOT-RESUME'){return 'SYNTHETIC_THEN_PRODUCT'}
    if($PhaseId -in @('LINUX','SURROGATE-DISPOSABLE','MAINTENANCE-READY-PROVISION','DEPENDENCY-MATRIX')){return 'PRODUCT_ONLY'}
    return 'NOT_APPLICABLE'
}

function Invoke-WindowsSentinelPhase {
    param([Parameter(Mandatory)][psobject]$Context)
    $result=Invoke-ActualWpfAction -Context $Context -Action 'Uninstall' -AllowMutation
    if([string]$result.foreignSentinels.status -ne 'PASS' -or -not [bool]$result.foreignSentinels.unchanged){throw 'Windows foreign sentinels did not survive the exact candidate destructive lifecycle.'}
    return [ordered]@{status='REAL E2E PASS';phase='WINDOWS-SENTINELS';contract='foreign-task-service-firewall-registry-file-survive-real-uninstall';candidate=$result.candidate;guest=$result.guest;sentinels=$result.foreignSentinels;evidencePath=$result.evidencePath}
}

function Invoke-AiBundlePhase {
    param([Parameter(Mandatory)][psobject]$Context)
    $candidate = Assert-ExactCandidate $Context
    $workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $builder = Join-Path $workspace 'tools\Build-AIAuditBundle.ps1'
    $archive = Join-Path $workspace ('outputs\DevFleet-v{0}-AI-Audit-LATEST.zip' -f $Context.candidate.releaseVersion)
    if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw 'Canonical AI audit builder is missing.' }
    $buildOutput = @(& (Get-Command pwsh.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $builder -Workspace $workspace 2>&1)
    $buildExit = $LASTEXITCODE
    $buildRawPath = Join-Path ([string]$Context.runDir) 'ai-bundle-build-output.txt'
    $buildOutput | ForEach-Object { [string]$_ } | Set-Content -LiteralPath $buildRawPath -Encoding UTF8
    if ($buildExit -ne 0 -or -not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Canonical AI audit builder failed; evidence=$buildRawPath" }
    $report = Join-Path ([string]$Context.runDir) 'ai-audit-bundle-self-test.json'
    $builderReport = Join-Path $workspace 'audit\ai-audit-bundle-self-test.json'
    if (-not (Test-Path -LiteralPath $builderReport -PathType Leaf)) { throw 'Canonical builder validator report is missing.' }
    $validated = Get-Content -LiteralPath $builderReport -Raw | ConvertFrom-Json
    $manifest = "$archive.manifest.json"
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'Canonical AI audit sidecar manifest is missing.' }
    $bundleManifest = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ([string]$bundleManifest.selfTest -ne 'PASS' -or [int]$bundleManifest.expectedSourceCount -ne [int]$bundleManifest.includedSourceCount) { throw 'Canonical AI audit source inventory is incomplete.' }
    # The builder chooses its mode from truthful native state and has already
    # clean-extracted this archive. Bind reuse to its exact completed bytes.
    $archiveHash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$bundleManifest.sha256 -cne $archiveHash -or [long]$bundleManifest.bytes -ne [long](Get-Item -LiteralPath $archive).Length -or [string]$bundleManifest.path -cne [IO.Path]::GetFullPath($archive) -or [string]$validated.archive -cne [IO.Path]::GetFullPath($archive)) { throw 'Canonical builder validation archive binding mismatch.' }
    $validMode=([string]$validated.bundleMode -ceq 'diagnostic' -and [string]$validated.status -ceq 'PASS_WITH_BLOCKER' -and $validated.releaseEligible -eq $false) -or ([string]$validated.bundleMode -ceq 'release' -and [string]$validated.status -ceq 'COMPLETE_FOR_AI_AUDIT' -and $validated.releaseEligible -eq $true)
    if (-not $validMode -or [string]$validated.secretScan -cne 'PASS' -or [string]$validated.modeVerification -cne 'PASS' -or [int]$validated.includedSourceCount -ne [int]$bundleManifest.includedSourceCount) { throw 'Canonical builder validation report is not a successful matching round-trip.' }
    Copy-Item -LiteralPath $builderReport -Destination $report -Force
    $tarList = @(& tar.exe -tzf ([string]$Context.candidate.tar.path) 2>&1)
    if ($LASTEXITCODE -ne 0 -or @($tarList | Where-Object { $_ -match '(^|/)linux/bootstrap-compute\.sh$' }).Count -ne 1) { throw 'Standard TAR extraction cannot locate the exact Linux bootstrap entrypoint.' }
    return [ordered]@{status='REAL E2E PASS';phase='AI-BUNDLE';contract='current-candidate-audit-builder-validator';candidate=$candidate;archive=[ordered]@{path=$archive;bytes=[int64](Get-Item $archive).Length;sha256=(Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant();sourceCount=[int]$bundleManifest.includedSourceCount;validatorReport=$report};buildOutput=$buildRawPath;standardTarListing='PASS' }
}

function Invoke-ReconcilePhase {
    param([Parameter(Mandatory)][psobject]$Context)
    $candidate = Assert-ExactCandidate $Context
    $workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $head = (& git -C $workspace rev-parse HEAD).Trim()
    $manifest = Get-Content -LiteralPath (Join-Path $workspace 'outputs\final-artifact-hashes.json') -Raw | ConvertFrom-Json
    $state = Get-Content -LiteralPath (Join-Path $workspace 'finalization-state.json') -Raw | ConvertFrom-Json
    $release = Get-Content -LiteralPath (Join-Path $workspace 'outputs\release-fingerprint.json') -Raw | ConvertFrom-Json
    $tooling = Get-Content -LiteralPath (Join-Path $workspace 'outputs\tooling-fingerprint-current.json') -Raw | ConvertFrom-Json
    $currentShippingIdentity = [string]$state.shipping_input_identity
    if (-not $currentShippingIdentity -or [string]$state.candidate_git_commit -ne [string]$Context.candidate.gitCommit) { throw 'RECONCILE is missing independent repository-head/candidate identity.' }
    if ([string]$manifest.shippingInputIdentity -and [string]$manifest.shippingInputIdentity -ne $currentShippingIdentity) { throw 'RECONCILE shipping-input identity mismatch.' }
    foreach($pair in @(@('releaseFingerprintId',$Context.candidate.releaseFingerprintId,$manifest.releaseFingerprintId,$release.releaseFingerprintId,$tooling.releaseFingerprintId),@('toolingFingerprintId',$Context.candidate.toolingFingerprintId,$manifest.toolingFingerprintId,$release.toolingFingerprint.toolingFingerprintId,$tooling.toolingFingerprintId))){ if(@($pair[1..4] | ForEach-Object {[string]$_} | Select-Object -Unique).Count -ne 1){throw "RECONCILE identity mismatch: $($pair[0])"} }
    if (-not [bool]$state.candidate_is_current -or [bool]$state.source_changed_since_candidate -or [bool]$state.rebuild_required) { throw 'RECONCILE found a stale candidate state or rebuild requirement.' }
    $rows = @()
    $recordsPath = Join-Path ([string]$Context.runDir) 'fullrelease-phase-records.json'
    if (Test-Path -LiteralPath $recordsPath) { $rows = @(Get-Content -LiteralPath $recordsPath -Raw | ConvertFrom-Json) }
    $required = @('HOST-SAFETY','CANDIDATE-VERIFY','RESTORE-CLEAN','ESTABLISH-SESSION','DEPENDENCY-MATRIX','SECURITY-POISON','FRESH-INSTALL-WPF','PRIMARY','LINUX','HTTP-HOSTILE','MAINTENANCE-READY','WINDOWS-SENTINELS','REPAIR','CLEAN-REINSTALL','UNINSTALL','FACTORY-RESET','REBOOT-RESUME','PERMANENT-DELETE','DELETE-RESTORE','STOPPED-PROJECT','HOST-CONCURRENCY','OPERATION-RECOVERY','OWNERSHIP','VAULT','SURROGATE-DISPOSABLE','REAL-USE-ACCEPTANCE','TAILSCALE-DEFERRED','TAILSCALE-AUTH','AI-BUNDLE')
    $missing=@($required | Where-Object { $row=$rows | Where-Object id -eq $_ | Select-Object -Last 1; -not $row -or [string]$row.status -ne 'PASS' })
    if($missing.Count){throw "RECONCILE found mandatory phases missing or not PASS: $($missing -join ', ')"}
    $realUseRecord = @($rows | Where-Object { [string]$_.id -ceq 'REAL-USE-ACCEPTANCE' }) | Select-Object -Last 1
    Assert-RealUseAcceptancePhaseEvidence -PhaseResult $realUseRecord.evidence.executor -Context $Context | Out-Null
    $maintenance=@('REPAIR','CLEAN-REINSTALL','UNINSTALL','FACTORY-RESET','REBOOT-RESUME') | ForEach-Object { $rows | Where-Object id -eq $_ | Select-Object -Last 1 }
    if(@($maintenance).Count -ne 5){throw 'RECONCILE maintenance count is not 5/5.'}
    return [ordered]@{status='REAL E2E PASS';phase='RECONCILE';contract='exact-candidate-final-state-reconciliation';candidate=$candidate;repositoryHead=$head;candidateCommit=[string]$state.candidate_git_commit;shippingInputIdentity=$currentShippingIdentity;identities=[ordered]@{releaseFingerprintId=$release.releaseFingerprintId;toolingFingerprintId=$tooling.toolingFingerprintId};candidateState=[ordered]@{candidateIsCurrent=$state.candidate_is_current;sourceChangedSinceCandidate=$state.source_changed_since_candidate;rebuildRequired=$state.rebuild_required};mandatoryPhaseCount=$required.Count;maintenance='5/5';recordsPath=$recordsPath }
}

function Invoke-RealProductPhase {
    param([Parameter(Mandatory)][string]$ContextJson)
    $context = Read-PhaseContext $ContextJson
    # Generic Diagnostics is not a contract proof for named lifecycle phases; every such phase below dispatches scenario-specific evidence.
    switch ([string]$context.phaseId) {
        'DEPENDENCY-MATRIX' { return Invoke-DependencyMatrix $context }
        'SECURITY-POISON' { return Invoke-ActualWpfAction $context 'Diagnostics' -AllowMutation }
        'FRESH-INSTALL-WPF' {
            $ui=Invoke-SupportedFreshInstallLifecycle -Context $context -Role 'Primary / Desktop' -CompleteLifecycle
            if([string]$ui.status -ne 'REAL E2E PASS' -or -not [bool]$ui.completionVerified){throw "FRESH-INSTALL-WPF requires verified lifecycle completion; observed $([string]$ui.status)."}
            return $ui
        }
        'PRIMARY' { throw 'PRIMARY must be dispatched by Invoke-PrimaryPhase.ps1, not the generic product driver.' }
        'LINUX' { throw 'LINUX must be dispatched by Invoke-LinuxPhase.ps1, not the generic product driver.' }
        'HTTP-HOSTILE' { throw 'HTTP-HOSTILE must be dispatched by Invoke-HttpHostilePhase.ps1, not the generic product driver.' }
        'REPAIR' { return Invoke-ActualWpfAction $context 'Repair' -AllowMutation }
        'CLEAN-REINSTALL' { return Invoke-ActualWpfAction $context 'CleanReinstall' -AllowMutation }
        'UNINSTALL' { return Invoke-ActualWpfAction $context 'Uninstall' -AllowMutation }
        'FACTORY-RESET' { return Invoke-ActualWpfAction $context 'FactoryReset' -AllowMutation }
        'REBOOT-RESUME' { return Invoke-RebootResumePhase $context }
        'MAINTENANCE-READY-PROVISION' { return Invoke-ProductLifecycleConsumer -Context $context }
        'PERMANENT-DELETE' { return Invoke-NestedProductScenario $context 'permanent-delete' }
        'DELETE-RESTORE' { return Invoke-NestedProductScenario $context 'delete-restore' }
        'STOPPED-PROJECT' { return Invoke-NestedProductScenario $context 'stopped-project' }
        'HOST-CONCURRENCY' { return Invoke-NestedProductScenario $context 'host-concurrency' }
        'OPERATION-RECOVERY' { return Invoke-NestedProductScenario $context 'operation-recovery' }
        'OWNERSHIP' { return Invoke-NestedProductScenario $context 'ownership' }
        'WINDOWS-SENTINELS' { return Invoke-WindowsSentinelPhase $context }
        'VAULT' { return Invoke-NestedProductScenario $context 'vault' }
        'SURROGATE-DISPOSABLE' { return Invoke-SurrogateDisposablePhase $context }
        'REAL-USE-ACCEPTANCE' { return Invoke-RealUseAcceptancePhase -Context $context }
        'TAILSCALE-DEFERRED' { return Invoke-TailscalePolicyPhase $context }
        'TAILSCALE-AUTH' { return Invoke-TailscalePolicyPhase $context }
        'AI-BUNDLE' { return Invoke-AiBundlePhase $context }
        'RECONCILE' { return Invoke-ReconcilePhase $context }
        default { throw "No phase-specific product driver exists for $($context.phaseId)." }
    }
}

Export-ModuleMember -Function Get-DevFleetNestedPrimaryReadinessScriptBlock,New-DevFleetExactProofBinding,Invoke-RealProductPhase,Invoke-PrimaryRolePhase,Invoke-LinuxBootstrapPhase,Invoke-SupportedFreshInstallLifecycle,Invoke-ProductFreshInstallLifecycle,Invoke-DisposableSyntheticRebootProbe,Invoke-RebootResumePhase,Invoke-ProductLifecycleConsumer,Get-ProductLifecycleConsumerMode,Get-ProductLifecycleObservation,Wait-DevFleetProductLifecycleTransition,Test-ProductMeaningfulProgress,Test-RebootBoundaryIdentity,Get-DurableProgressClassification,Get-PhaseAwareBudgetSeconds,Resolve-GuestProgressMarkerRead,Add-GuestProgressMarkerObservation
