# DevFleet source part 029

Full-source UTF-8 byte interval [1302000, 1348500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 759ac54c287f8ca81827c56b28ec4349e1e8ad36d43f0756eaade06539dc6aeb

<!-- BEGIN SOURCE SLICE -->
t [string]::IsNullOrWhiteSpace([string]$_)});[ordered]@{cbs=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending');windowsUpdate=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired');pendingCount=$m.Count}})
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
            $firewallMatches=($existingFirewall.Count -eq 1 -and [string]$existingFirewall[0].DisplayName -ceq $firewallName -and [string]$existingFirewall[0].Group -ceq 'DevFleet E2E Foreign Sentinels' -and [string]$existingFirewall[0].Direction -ieq 'Inbound' -and [string]$existingFirewall[0].Action -ieq 'Blo