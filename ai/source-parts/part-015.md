# DevFleet source part 015

Full-source UTF-8 byte interval [651000, 697500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 7e3c1ac939848e45a541a584a330e036056724390680be3245df9cba9998e2e6

<!-- BEGIN SOURCE SLICE -->
@{selfTest=$SelfTest;hostAuthenticode=[ordered]@{profile=$Fingerprint.privateSigningProfile;thumbprint=$Fingerprint.privateSigningCertificateThumbprint;publicPublisherTrust=$Fingerprint.publicPublisherTrust;publicPromotionAllowed=$Fingerprint.publicPromotionAllowed}}
            } elseif ($phase.id -eq 'MAINTENANCE-READY') {
                $maintenance=Ensure-MaintenanceReadyFixture -Vm $Vm -Fingerprint $Fingerprint -Config $Config -WorkspaceRoot $WorkspaceRoot -RunId ([string]$State.runId) -RunDir $RunDir
                $context.maintenanceVault=$maintenance.vault
                $record.status='PASS';$record.evidence=$maintenance
            } elseif ($phase.id -eq 'RESTORE-CLEAN') {
                $checkpoint=Restore-ExactCheckpoint -Vm $Vm -Name $phase.checkpoint -StartAfterRestore
                $State.checkpointIds=@($State.checkpointIds)+@($checkpoint.id)
                $postStart=$null
                if ($phase.id -eq 'RESTORE-CLEAN') {
                    $postStart=Confirm-PostStartHostMemorySafety -InitialSnapshot $HostSnapshot -SampleSeconds 60 -IntervalSeconds 5
                    if ($postStart.status -ne 'PASS' -and -not [bool]$HostSnapshot.ramPressureOverrideAuthorized) { throw 'USER ACTION REQUIRED — HOST MEMORY PRESSURE AFTER E2E VM START' }
                    if ([bool]$HostSnapshot.ramPressureOverrideAuthorized) { $postStart.rawStatus=$postStart.status; $postStart.status='PASS — USER-AUTHORIZED RAM PRESSURE'; $postStart.overrideAuthorized=$true }
                }
                $record.status='PASS';$record.evidence=$checkpoint
                if ($postStart) { $record.evidence=[ordered]@{ checkpoint=$checkpoint; postStartMemory=$postStart } }
            } elseif ($phase.id -eq 'ESTABLISH-SESSION') {
                $checkpoint=Restore-ExactCheckpoint -Vm $Vm -Name $phase.checkpoint -StartAfterRestore
                $State.checkpointIds=@($State.checkpointIds)+@($checkpoint.id)
                $privateVerifier=Invoke-DisposablePrivateSignatureVerification -Fingerprint $Fingerprint -Vm $Vm -RunId ([string]$State.runId) -RunDir $RunDir
                $desktop=Ensure-FullReleaseInteractiveDesktop -VmId ([guid][string]$Vm.Id)
                $record.status='PASS';$record.evidence=[ordered]@{checkpoint=$checkpoint;interactiveDesktop=$desktop;privateAuthenticodeVerifier=$privateVerifier}
            } elseif ($phase.id -eq 'CLEANUP') {
                $record.status='PASS';$record.evidence=Invoke-FullReleaseCleanup -Vm $Vm -Fingerprint $Fingerprint -Config $Config -RunId ([string]$State.runId) -RunDir $RunDir
            } else {
                $checkpointEvidence=$null
                if ($phase.checkpoint) {
                    if ([string]$phase.checkpoint -ceq 'DevFleet-E2E-MAINTENANCE-READY') {
                        $checkpointEvidence=Restore-MaintenanceReadyCheckpoint -Vm $Vm -Fingerprint $Fingerprint -WorkspaceRoot $WorkspaceRoot
                        $State.checkpointIds=@($State.checkpointIds)+@($checkpointEvidence.checkpoint.id)
                    } else {
                        $checkpointEvidence=Restore-ExactCheckpoint -Vm $Vm -Name $phase.checkpoint -StartAfterRestore
                        $State.checkpointIds=@($State.checkpointIds)+@($checkpointEvidence.id)
                    }
                }
                $executor=Get-ExecutorPath -Config $Config -PhaseId $phase.id -WorkspaceRoot $WorkspaceRoot
                if (-not $executor) { throw "No real product executor is configured for FullRelease phase $($phase.id); refusing to convert a plan into a PASS." }
                $clusterJoin = $null
                if ([string]$phase.id -ceq 'REAL-USE-ACCEPTANCE') {
                    if (-not $realUsePairingCapture -or -not $realUsePairingPrivateState -or -not $realUseSurrogateEvidence) { throw 'REAL-USE-ACCEPTANCE lacks the retained genuine Primary pairing prerequisite.' }
                    $joinError=$null;$privateCleanupError=$null
                    try {
                        $clusterJoin=Complete-RealUseAcceptanceClusterJoin -Context ([pscustomobject]$context) -Capture $realUsePairingCapture -PrivateState $realUsePairingPrivateState -SurrogateEvidence $realUseSurrogateEvidence
                    } catch { $joinError=$_.Exception } finally {
                        try { Remove-RealUseAcceptancePrivateState -PrivateState $realUsePairingPrivateState -RunId ([string]$State.runId) | Out-Null } catch { $privateCleanupError=$_.Exception }
                        $realUsePairingPrivateState=$null
                    }
                    if($joinError){if($privateCleanupError){throw "$($joinError.Message); REAL-USE-ACCEPTANCE private pairing cleanup failed."};throw $joinError}
                    if($privateCleanupError){throw $privateCleanupError}
                    $context.realUseClusterJoin=[pscustomobject][ordered]@{evidence=$clusterJoin.evidence;evidencePath=$clusterJoin.evidencePath;evidenceSha256=$clusterJoin.evidenceSha256}
                }
                $evidence=Invoke-ConfiguredExecutor -Path $executor -Context ([pscustomobject]$context)
                if ([string]$evidence.status -notin @('PASS','REAL E2E PASS')) { throw "Executor did not return PASS for $($phase.id)." }
                if ([string]$phase.id -ceq 'FRESH-INSTALL-WPF') {
                    $realUsePairingCapture=New-RealUseAcceptancePrimaryPairingCapture -Context ([pscustomobject]$context) -FreshInstallEvidence $evidence
                    $realUsePairingPrivateState=$realUsePairingCapture.privateState
                }
                if ([string]$phase.id -ceq 'SURROGATE-DISPOSABLE') { $realUseSurrogateEvidence=$evidence }
                if ([string]$phase.id -ceq 'REAL-USE-ACCEPTANCE') { Assert-RealUseAcceptancePhaseEvidence -PhaseResult $evidence -Context ([pscustomobject]$context) | Out-Null }
                $record.status='PASS';$record.evidence=[ordered]@{ checkpoint=$checkpointEvidence; executor=$evidence }
                if ([string]$phase.id -ceq 'FRESH-INSTALL-WPF') { $record.evidence['primaryPairing']=[ordered]@{evidence=$realUsePairingCapture.evidence;evidencePath=$realUsePairingCapture.evidencePath;evidenceSha256=$realUsePairingCapture.evidenceSha256} }
                if ([string]$phase.id -ceq 'REAL-USE-ACCEPTANCE') { $record.evidence['clusterJoin']=[ordered]@{evidence=$clusterJoin.evidence;evidencePath=$clusterJoin.evidencePath;evidenceSha256=$clusterJoin.evidenceSha256} }
            }
        } catch {
            $phaseError=$_.Exception
            $privateCleanupError=$null
            if($realUsePairingPrivateState){try{Remove-RealUseAcceptancePrivateState -PrivateState $realUsePairingPrivateState -RunId ([string]$State.runId)|Out-Null}catch{$privateCleanupError=$_.Exception};$realUsePairingPrivateState=$null}
            $record.status='BLOCKED';$record.error=$phaseError.Message
            if($privateCleanupError){$record.error="$($phaseError.Message); REAL-USE-ACCEPTANCE private pairing cleanup failed."}
            $record.finishedAt=(Get-Date).ToUniversalTime().ToString('o')
            $records.Add([pscustomobject]$record)
            $remainingPhaseIds=@($phases.id);$currentIndex=[Array]::IndexOf($remainingPhaseIds,[string]$phase.id)
            foreach($remaining in @($phases | Select-Object -Skip ($currentIndex+1))){$records.Add([pscustomobject][ordered]@{id=$remaining.id;label=$remaining.label;checkpoint=$remaining.checkpoint;destructive=[bool]$remaining.destructive;status='NOT RUN';evidence=$null;startedAt=$null;finishedAt=$null})}
            $State.errors=@($State.errors)+@($record.error);$State.finalStatus='BLOCKED — FullRelease evidence incomplete';Save-RunState -State $State -Path $StatePath
            Write-EvidenceJson -Path (Join-Path $RunDir 'fullrelease-phase-records.json') -Value $records
            if($privateCleanupError){throw $record.error}
            throw $phaseError
        }
        $record.finishedAt=(Get-Date).ToUniversalTime().ToString('o');$records.Add([pscustomobject]$record)
        $State.completedPhases=@($State.completedPhases)+@($phase.id);Save-RunState -State $State -Path $StatePath
        Write-EvidenceJson -Path (Join-Path $RunDir 'fullrelease-phase-records.json') -Value $records
    }
    $postCleanup=Write-PostCleanupFinalization -State $State -Vm $Vm -Config $Config -RunDir $RunDir -Records @($records) -WorkspaceRoot $WorkspaceRoot
    $State.currentPhase='COMMITTED';$State.finalStatus='PASS';Save-RunState -State $State -Path $StatePath
    return [pscustomobject]@{ status='PASS'; runId=$State.runId; candidate=$Fingerprint; phases=$records; postCleanupFinalization=$postCleanup }
}

Export-ModuleMember -Function Set-DevFleetBaselineBinding,Get-FullReleasePhasePlan,Get-AssertedDisposableVm,Get-ExactCheckpoint,Restore-ExactCheckpoint,Ensure-FullReleaseInteractiveDesktop,Assert-MaintenanceReadyProvenance,Invoke-MaintenanceReadyGuestValidation,Invoke-MaintenanceReadyProductLifecycle,Ensure-MaintenanceReadyFixture,Restore-MaintenanceReadyCheckpoint,Invoke-FullReleaseRun,Set-FullReleasePassState,Invoke-DisposablePrivateSignatureVerification,Invoke-FullReleaseCleanup

```


## FILE: automation/release-e2e/modules/GuestSession.psm1

SHA256: c9235fabe43a9abc28a993db5e6d34e9f454458f6dbf0e419358c65ab0ce7b68 | Bytes: 21961 | Git mode: 100644

```
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Secrets.psm1') -Force

# A Hyper-V PSSession created by a nested PowerShell pipeline remains backed by
# that pipeline's runspace.  Keep completed opener pipelines alive until the
# returned session closes; callers close it with Remove-DevFleetGuestSession.
$script:GuestSessionPipelines = @{}

function New-BoundedVmPSSession {
    param([guid]$VmId,[string]$VmName,[Parameter(Mandatory)][pscredential]$Credential)
    $pipeline=[powershell]::Create()
    $session=$null
    try {
        $null=$pipeline.AddCommand('New-PSSession').AddParameter('Credential',$Credential).AddParameter('ErrorAction','Stop')
        if($VmId -ne [guid]::Empty){$null=$pipeline.AddParameter('VMId',$VmId)}else{$null=$pipeline.AddParameter('VMName',$VmName)}
        $async=$pipeline.BeginInvoke()
        if(-not $async.AsyncWaitHandle.WaitOne(60000)){
            try{$pipeline.Stop()}catch{}
            throw 'Guest session establishment exceeded its finite 60-second open deadline.'
        }
        $output=@($pipeline.EndInvoke($async))
        if($pipeline.HadErrors){if($pipeline.Streams.Error.Count){throw $pipeline.Streams.Error[0]};throw 'Guest session failed without a native error record.'}
        # New-PSSession returns the live session directly from the local
        # pipeline.  Do not assume every pipeline item exposes the remoting
        # wrapper's BaseObject adapter; strict mode correctly rejects that
        # assumption for a native PSSession instance.
        $session=@($output|Where-Object{$_})|Select-Object -First 1
        if(-not $session){throw 'Guest session establishment returned no session.'}
        $script:GuestSessionPipelines[[string]$session.InstanceId] = $pipeline
        return $session
    } catch {
        # EndInvoke can wrap the actual error. Retain its native record until sanitization.
        if($pipeline.Streams.Error.Count){throw $pipeline.Streams.Error[0]}
        throw
    } finally {
        # Disposing the opener here closes the live remoting session before a
        # reboot-resume caller can use it.  Failed openers have no session to
        # preserve and can be disposed immediately.
        if (-not $session) { $pipeline.Dispose() }
    }
}

function Remove-DevFleetGuestSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)
    $key=[string]$Session.InstanceId
    try { Remove-PSSession -Session $Session -ErrorAction Stop }
    catch { $PSCmdlet.WriteError($_) }
    finally {
        # Never dispose an opener while its session is still usable. Removal
        # can fail, so a closed native session is the cleanup authority.
        if([string]$Session.State -ceq 'Closed' -and $script:GuestSessionPipelines.ContainsKey($key)){
            try {
                $script:GuestSessionPipelines[$key].Dispose()
                $script:GuestSessionPipelines.Remove($key)
            } catch { $PSCmdlet.WriteError($_) }
        }
    }
}

function New-DevFleetGuestSessionFailure {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$Failure,[ValidateRange(1,3)][int]$AttemptCount)
    # Native error text is inspected only in memory, never copied into public evidence.
    # Access denial does not establish which layer rejected access or a stale password.
    $denied=$false;$rejected=$false;$timedOut=$false;$transport='';$authText=$false;$nativeCode=$null
    $exception=$Failure.Exception
    for($depth=0;$null -ne $exception -and $depth -lt 8;$depth++){
        $message=[string]$exception.Message
        if($exception -is [ComponentModel.Win32Exception]){
            $nativeCode=[int]$exception.NativeErrorCode
            if($nativeCode -eq 1326){$rejected=$true}
            if($nativeCode -eq 5){$denied=$true}
        }
        if($exception -is [UnauthorizedAccessException] -or $exception.HResult -eq -2147024891 -or $message -match '(?i)\baccess is denied\b'){$denied=$true}
        if($message -match '(?i)^\s*The credential is invalid\.?\s*$'){$rejected=$true}
        if($message -match '(?i)credential|logon|authentication|access is denied'){$authText=$true}
        if($message -ceq 'Guest session establishment exceeded its finite 60-second open deadline.'){$timedOut=$true}
        # Preserve only the existing lifecycle transport discriminators and retry policy.
        foreach($known in @('Hyper-V socket target process has ended','background process reported an error with the following message','An error has occurred which PowerShell cannot handle. A remote session might have ended.')){
            if($message -match [regex]::Escape($known)){$transport=$known}
        }
        $exception=$exception.InnerException
    }
    $code='LAB_SESSION_OPEN_FAILED';$detail='Guest session could not be established; cause is unverified.';$authentication='UNVERIFIED'
    if($rejected){$code='LAB_GUEST_AUTHENTICATION_REJECTED';$detail='Guest authentication was rejected; credential freshness and account readiness remain unverified.';$authentication='REJECTED'}
    elseif($denied){$code='LAB_SESSION_ACCESS_DENIED';$detail='Access is denied at an unverified session layer; host authorization and guest authentication must be distinguished.'}
    elseif($timedOut){$code='LAB_SESSION_OPEN_TIMEOUT';$detail='Guest session establishment exceeded its finite 60-second open deadline.'}
    elseif($transport -and -not $authText){$code='LAB_SESSION_TRANSPORT_FAILED';$detail=$transport+'.'}
    $safe=[InvalidOperationException]::new(('{0}: {1} Bounded attempts: {2}.' -f $code,$detail,$AttemptCount))
    $safe.Data['failureCode']=$code;$safe.Data['attemptCount']=$AttemptCount
    $safe.Data['authenticationOutcome']=$authentication;$safe.Data['credentialFreshness']='UNVERIFIED'
    if($null -ne $nativeCode){$safe.Data['nativeErrorCode']=$nativeCode}
    return $safe
}

function Connect-DevFleetGuest {
    [CmdletBinding(DefaultParameterSetName='ById')]
    param(
        [Parameter(Mandatory,ParameterSetName='ById')][guid]$VmId,
        [Parameter(Mandatory,ParameterSetName='ByName')][string]$VmName
    )
    $credential = Get-DevFleetE2ECredential
    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $target = Get-VM -Id $VmId -ErrorAction Stop
        if ($target.Name -notlike 'DevFleet-E2E-*') { throw 'Guest session refused a non-disposable VM identity.' }
        $lastError=$null
        for($attempt=1;$attempt -le 3;$attempt++){
            try { return New-BoundedVmPSSession -VmId $VmId -Credential $credential }
            catch {
                if($attempt -lt 3){Start-Sleep -Seconds 5;continue}
                throw (New-DevFleetGuestSessionFailure -Failure $_ -AttemptCount $attempt)
            }
        }
    } else {
        $target = Get-VM -Name $VmName -ErrorAction Stop
        if ($target.Name -notlike 'DevFleet-E2E-*') { throw 'Guest session refused a non-disposable VM identity.' }
        $lastError=$null
        for($attempt=1;$attempt -le 3;$attempt++){
            try { return New-BoundedVmPSSession -VmName $VmName -Credential $credential }
            catch {
                if($attempt -lt 3){Start-Sleep -Seconds 5;continue}
                throw (New-DevFleetGuestSessionFailure -Failure $_ -AttemptCount $attempt)
            }
        }
    }
}

function Get-InteractiveGuestState {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)
    Invoke-Command -Session $Session -ScriptBlock { [pscustomobject]@{ computer=$env:COMPUTERNAME; quser=(@(quser 2>&1) -join "`n"); explorer=@(Get-Process explorer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SessionId) } }
}

function Get-StageIntegrity {
    param([Parameter(Mandatory)][string]$LocalPath,[Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][string]$RemotePath)
    $localHash=(Get-FileHash -LiteralPath $LocalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath $LocalPath -Destination $RemotePath -ToSession $Session -Force
    $remoteHash=Invoke-Command -Session $Session -ScriptBlock { param($p) (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() } -ArgumentList $RemotePath
    [pscustomobject]@{ localPath=$LocalPath; remotePath=$RemotePath; localSha256=$localHash; remoteSha256=$remoteHash; equal=($localHash -eq $remoteHash) }
}

function Resolve-DevFleetNestedL2Inventory {
    param(
        [Parameter(Mandatory)][string]$ExpectedName,
        [bool]$ExecutablePresent,
        [AllowNull()][string]$InventoryJson,
        [int]$ExitCode = 0,
        [AllowNull()][string]$CaptureError,
        [AllowNull()][object[]]$BackendInventories
    )
    if(-not [string]::IsNullOrWhiteSpace($CaptureError)){
        return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification=$CaptureError}
    }
    if([string]::IsNullOrWhiteSpace($ExpectedName)){
        return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification='Expected nested L2 name is empty'}
    }
    if(-not $ExecutablePresent){
        $required=@('Hyper-V','VirtualBox')
        $rows=@($BackendInventories)
        if($rows.Count -ne $required.Count){return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification='Multipass executable absent and the complete supported in-L1 backend inventory set was not supplied';backendInventories=$rows}}
        $normalized=[Collections.Generic.List[object]]::new()
        foreach($provider in $required){
            $matches=@($rows|Where-Object{if($null -eq $_){$false}elseif($_ -is [System.Collections.IDictionary]){[string]$_['provider'] -ceq $provider}else{[string]$_.provider -ceq $provider}})
            if($matches.Count -ne 1){return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification="Multipass executable absent and $provider backend inventory was not uniquely available";backendInventories=$rows}}
            $row=$matches[0]
            $providerValue=if($row -is [System.Collections.IDictionary]){[string]$row['provider']}else{[string]$row.provider}
            $rowStatus=if($row -is [System.Collections.IDictionary]){[string]$row['status']}else{[string]$row.status}
            $namesHolder=[pscustomobject]@{value=$null}
            if($row -is [System.Collections.IDictionary]){$namesProperty=$row.Contains('names');if($namesProperty){$namesHolder.value=$row['names']};$verification=[string]$row['verification']}
            else{$namesProperty=$null -ne $row.PSObject.Properties['names'];if($namesProperty){$namesHolder.value=$row.PSObject.Properties['names'].Value};$verification=[string]$row.verification}
            $namesValue=$namesHolder.value
            $namesAreCollection=$null -ne $namesValue -and $namesValue -is [System.Collections.IEnumerable] -and $namesValue -isnot [string] -and $namesValue -isnot [System.Collections.IDictionary]
            if($providerValue -cne $provider -or $rowStatus -cne 'PASS' -or -not $namesProperty -or -not $namesAreCollection -or [string]::IsNullOrWhiteSpace($verification)){
                return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification="$provider backend inventory was incomplete or malformed";backendInventories=$rows}
            }
            $names=[Collections.Generic.List[string]]::new()
            foreach($name in @($namesValue)){
                if($name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$name)){
                    return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification="$provider backend inventory contains a malformed instance name";backendInventories=$rows}
                }
                if($names.Contains([string]$name)){
                    return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification="$provider backend inventory contains a duplicate instance name";backendInventories=$rows}
                }
                $names.Add([string]$name)
            }
            $normalized.Add([pscustomobject]@{provider=$provider;status='PASS';names=@($names.ToArray());verification=$verification})
        }
        $exactCount=0;$inventoryCount=0
        foreach($backend in $normalized){$inventoryCount+=@($backend.names).Count;$exactCount+=@($backend.names|Where-Object{$_ -ceq $ExpectedName}).Count}
        return [pscustomobject]@{status=if($exactCount){'PRESENT'}else{'ABSENT'};expectedName=$ExpectedName;present=($exactCount -gt 0);exactMatchCount=$exactCount;inventoryCount=$inventoryCount;verification='Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend';backendInventories=@($normalized.ToArray())}
    }
    if($ExitCode -ne 0){
        return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification="Bounded Multipass inventory exited $ExitCode"}
    }
    try{$inventory=$InventoryJson|ConvertFrom-Json -ErrorAction Stop}catch{
        return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification='Bounded Multipass inventory was not valid JSON'}
    }
    if($inventory -is [array]){$instances=$inventory}
    else{
        $hasList=$null -ne $inventory -and $null -ne $inventory.PSObject.Properties['list']
        if(-not $hasList){return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification='Multipass JSON did not contain the required list inventory'}}
        $instances=$inventory.list
        if($instances -isnot [array]){return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification='Multipass list inventory was not an array'}}
    }
    $names=[Collections.Generic.List[string]]::new()
    foreach($instance in $instances){
        $hasName=if($null -eq $instance){$false}elseif($instance -is [System.Collections.IDictionary]){$instance.Contains('name')}else{$null -ne $instance.PSObject.Properties['name']}
        $name=if($null -eq $instance){$null}elseif($instance -is [System.Collections.IDictionary]){$instance['name']}else{$instance.name}
        if(-not $hasName -or $name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$name)){
            return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification='Multipass inventory contains an incomplete instance record'}
        }
        if($names.Contains([string]$name)){
            return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification='Multipass inventory contains a duplicate instance name'}
        }
        $names.Add([string]$name)
    }
    $exactCount=@($names|Where-Object{$_ -ceq $ExpectedName}).Count;$inventoryCount=$names.Count
    return [pscustomobject]@{status=if($exactCount){'PRESENT'}else{'ABSENT'};expectedName=$ExpectedName;present=($exactCount -gt 0);exactMatchCount=$exactCount;inventoryCount=$inventoryCount;verification='Bounded Multipass JSON inventory inside exact L1'}
}

function Get-DevFleetNestedL2State {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$ExpectedName
    )
    try {
        $capture=Invoke-Command -Session $Session -ScriptBlock {
            $multipass=@(
                (Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'Multipass\bin\multipass.exe')
            )|Where-Object{$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)}|Select-Object -First 1
            if(-not $multipass){$command=Get-Command multipass.exe -ErrorAction SilentlyContinue;if(-not $command){$command=Get-Command multipass -ErrorAction SilentlyContinue};if($command){$multipass=$command.Source}}
            if(-not $multipass){
                $multipassService=@(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue|Where-Object{[string]$_.Name -match '^(?i:multipass)'})
                $multipassRegistry=Test-Path -LiteralPath 'HKLM:\SOFTWARE\Canonical\Multipass'
                if($multipassService.Count -gt 0 -or $multipassRegistry){return [pscustomobject]@{executablePresent=$false;inventoryJson='';exitCode=-1;captureError='Multipass control-plane indicators exist but its bounded inventory executable is unavailable';backendInventories=@()}}
                $backends=[System.Collections.Generic.List[object]]::new()
                try {
                    $feature=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction Stop
                    if([string]$feature.State -eq 'Enabled'){
                        $rows=@(Get-CimInstance -Namespace 'root\virtualization\v2' -ClassName Msvm_ComputerSystem -ErrorAction Stop|Where-Object{[string]$_.Caption -eq 'Virtual Machine'})
                        [void]$backends.Add([pscustomobject]@{provider='Hyper-V';status='PASS';names=@($rows|ForEach-Object{[string]$_.ElementName});verification='Get-WindowsOptionalFeature plus bounded Msvm_ComputerSystem inventory inside exact L1'})
                    }else{[void]$backends.Add([pscustomobject]@{provider='Hyper-V';status='PASS';names=@();verification="Hyper-V feature state $([string]$feature.State) inside exact L1; provider unavailable"})}
                }catch{[void]$backends.Add([pscustomobject]@{provider='Hyper-V';status='UNVERIFIED';names=@();verification=$_.Exception.Message})}
                $vbox=@((Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Oracle\VirtualBox\VBoxManage.exe'))|Where-Object{$_ -and(Test-Path -LiteralPath $_ -PathType Leaf)}|Select-Object -First 1
                if($vbox){
                    $vboxJob=Start-Job -ScriptBlock {param($Path)$output=@(& $Path list vms 2>&1);[pscustomobject]@{output=@($output);exitCode=$LASTEXITCODE}} -ArgumentList $vbox
                    try{
                        if(-not(Wait-Job -Job $vboxJob -Timeout 30)){[void]$backends.Add([pscustomobject]@{provider='VirtualBox';status='UNVERIFIED';names=@();verification='Bounded VBoxManage inventory timed out'})}
                        else{$vboxResult=@(Receive-Job -Job $vboxJob -ErrorAction SilentlyContinue)|Select-Object -Last 1;if(-not$vboxResult-or[int]$vboxResult.exitCode-ne0){[void]$backends.Add([pscustomobject]@{provider='VirtualBox';status='UNVERIFIED';names=@();verification='Bounded VBoxManage inventory failed'})}else{$names=@($vboxResult.output|ForEach-Object{if([string]$_ -match '^"([^"]+)"\s+\{[0-9A-Fa-f-]+\}$'){$Matches[1]}}|Where-Object{$_});[void]$backends.Add([pscustomobject]@{provider='VirtualBox';status='PASS';names=$names;verification='Bounded VBoxManage list vms inventory inside exact L1'})}}
                    }
                    finally{if($vboxJob){Stop-Job -Job $vboxJob -ErrorAction SilentlyContinue;Remove-Job -Job $vboxJob -Force -ErrorAction SilentlyContinue}}
                }else{
                    $vboxService=@(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue|Where-Object{[string]$_.Name -match '^(?i:VBox)'})
                    $vboxRegistry=(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox') -or (Test-Path -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')
                    if($vboxService.Count -eq 0 -and -not $vboxRegistry){[void]$backends.Add([pscustomobject]@{provider='VirtualBox';status='PASS';names=@();verification='VBoxManage, Oracle registry, and VBox services absent inside exact L1; backend unavailable'})}
                    else{[void]$backends.Add([pscustomobject]@{provider='VirtualBox';status='UNVERIFIED';names=@();verification='VirtualBox backend indicators exist but VBoxManage inventory is unavailable'})}
                }
                return [pscustomobject]@{executablePresent=$false;inventoryJson='';exitCode=0;captureError='';backendInventories=@($backends)}
            }
            $job=Start-Job -ScriptBlock {param($Path)$output=@(& $Path list --format json 2>&1);[pscustomobject]@{inventoryJson=($output-join "`n");exitCode=$LASTEXITCODE}} -ArgumentList $multipass
            try {
                if(-not(Wait-Job -Job $job -Timeout 30)){return [pscustomobject]@{executablePresent=$true;inventoryJson='';exitCode=-1;captureError='Bounded Multipass inventory timed out'}}
                $jobResult=@(Receive-Job -Job $job -ErrorAction SilentlyContinue)|Select-Object -Last 1
                if(-not $jobResult){return [pscustomobject]@{executablePresent=$true;inventoryJson='';exitCode=-1;captureError='Bounded Multipass inventory returned no result'}}
                return [pscustomobject]@{executablePresent=$true;inventoryJson=[string]$jobResult.inventoryJson;exitCode=[int]$jobResult.exitCode;captureError=''}
            } finally {Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
        }
        $backendInventories=if($capture.PSObject.Properties['backendInventories']){@($capture.backendInventories)}else{@()}
        $resolved=Resolve-DevFleetNestedL2Inventory -ExpectedName $ExpectedName -ExecutablePresent ([bool]$capture.executablePresent) -InventoryJson ([string]$capture.inventoryJson) -ExitCode ([int]$capture.exitCode) -CaptureError ([string]$capture.captureError) -BackendInventories $backendInventories
    } catch {
        $resolved=[pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;verification=$_.Exception.Message}
    }
    $resolved|Add-Member -NotePropertyName observedUtc -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force
    return $resolved
}

Export-ModuleMember -Function Connect-DevFleetGuest,Remove-DevFleetGuestSession,Get-InteractiveGuestState,Get-StageIntegrity,Resolve-DevFleetNestedL2Inventory,Get-DevFleetNestedL2State

```


## FILE: automation/release-e2e/modules/HarnessBudget.psm1

SHA256: 72b1ec59ae9fceb180e00fa205fb830fdaaca5617baa5eb9301f72889fa22897 | Bytes: 14437 | Git mode: 100644

```
$ErrorActionPreference = 'Stop'

# One finite, composable deadline policy shared by the lifecycle observer,
# FullRelease, and the exact-proof driver.  Values are operation maxima; the
# enclosing budgets are sums of the operations they own, not replacements for
# them.  A child may consume less than its maximum, but never more than the
# remaining deadline of its owner.
$script:DeadlinePolicyVersion = '1.0.0'

function Get-HarnessBudgetPolicy {
    [CmdletBinding()]
    param([psobject]$Config)

    $configured = if ($Config -and $Config.PSObject.Properties['DeadlinePolicy']) { $Config.DeadlinePolicy } else { $null }
    # The guest bootstrap is one bounded operation at the Windows boundary,
    # but its maximum is itself derived from the finite stages in the current
    # script: package prerequisites, signed repositories, runtime setup, and
    # service/firewall finalization.  This prevents a bootstrap timeout from
    # being a second un-derived magic number.
    $guestBootstrapComponents = [ordered]@{
        packagePrerequisites = 900
        dockerRepositoryAndInstall = 1200
        tailscaleRepositoryAndInstall = 1200
        rootlessRuntime = 600
        nodeToolchain = 600
        pythonRuntime = 1200
        serviceAndFirewallFinalization = 600
    }
    if ($configured -and $configured.PSObject.Properties['GuestBootstrapComponentsSeconds']) {
        foreach ($property in $configured.GuestBootstrapComponentsSeconds.PSObject.Properties) {
            $key = [string]$property.Name
            if ($guestBootstrapComponents.Contains($key)) { $guestBootstrapComponents[$key] = [int]$property.Value }
        }
    }
    foreach ($entry in $guestBootstrapComponents.GetEnumerator()) {
        if ([int]$entry.Value -le 0) { throw "Guest bootstrap component '$($entry.Key)' must be positive." }
    }
    # The component maxima cover only guest work.  Reserve a bounded owner
    # margin for argument validation, marker terminalization, cleanup, and
    # failure reporting so the Windows owner never recreates parent == child.
    $guestBootstrapTerminalizationMargin = 300
    $derivedGuestBootstrap = [int](($guestBootstrapComponents.Values | Measure-Object -Sum).Sum) + $guestBootstrapTerminalizationMargin
    $operationDependencyProbe = 60
    $operationDependencyHealth = 180
    $operationDependencyInstall = 1800
    $operationDependencyVerification = 60
    $operationWindowsCapability = 900
    $operationWindowsFeature = 900
    $operationMultipassConfiguration = 600
    $operationVsCodeExtensions = 300
    $operation = [ordered]@{
        bootstrap = 240
        preflight = 120
        dependencyProbe = $operationDependencyProbe
        dependencyHealth = $operationDependencyHealth
        dependencyInstall = $operationDependencyInstall
        dependencyVerification = $operationDependencyVerification
        windowsCapability = $operationWindowsCapability
        windowsFeature = $operationWindowsFeature
        multipassConfiguration = $operationMultipassConfiguration
        vscodeExtension = $operationVsCodeExtensions
        prerequisites = (6 * ($operationDependencyProbe + $operationDependencyHealth + $operationDependencyInstall + $operationDependencyVerification)) + $operationWindowsCapability + $operationWindowsFeature + (4 * $operationMultipassConfiguration) + (3 * $operationVsCodeExtensions)
        windowsTailscale = 900
        hostAgent = 300
        multipassLaunch = 900
        multipassReadiness = 1200
        payloadTransfer = 900
        guestBootstrap = $derivedGuestBootstrap
        vaultBootstrap = 3900
        sshAndMarker = 300
        vaultSnapshot = 300
        tailscale = 900
        vaultClient = 300
        shortcuts = 180
        export = 300
        verification = 300
    }
    if ($configured -and $configured.PSObject.Properties['OperationMaximumsSeconds']) {
        foreach ($property in $configured.OperationMaximumsSeconds.PSObject.Properties) {
            $key = [string]$property.Name
            if ($operation.Contains($key) -and $key -ne 'guestBootstrap') { $operation[$key] = [int]$property.Value }
            elseif ($key -eq 'guestBootstrap' -and [int]$property.Value -ne $derivedGuestBootstrap) { throw "guestBootstrap must equal the sum of GuestBootstrapComponentsSeconds ($derivedGuestBootstrap); refusing an un-derived timeout override." }
        }
    }
    $derivedPrerequisites = (6 * ([int]$operation.dependencyProbe + [int]$operation.dependencyHealth + [int]$operation.dependencyInstall + [int]$operation.dependencyVerification)) + [int]$operation.windowsCapability + [int]$operation.windowsFeature + (4 * [int]$operation.multipassConfiguration) + (3 * [int]$operation.vscodeExtension)
    if ($configured -and $configured.OperationMaximumsSeconds -and $configured.OperationMaximumsSeconds.PSObject.Properties['prerequisites'] -and [int]$configured.OperationMaximumsSeconds.prerequisites -ne $derivedPrerequisites) { throw "prerequisites must equal the sum of its finite operation maxima ($derivedPrerequisites); refusing an un-derived timeout override." }
    $operation.prerequisites = $derivedPrerequisites
    foreach ($entry in $operation.GetEnumerator()) {
        if ([int]$entry.Value -le 0) { throw "Deadline policy operation maximum '$($entry.Key)' must be positive." }
    }

    $stage = [ordered]@{
        compute = [int]$operation.multipassLaunch + [int]$operation.multipassReadiness + [int]$operation.payloadTransfer + [int]$operation.guestBootstrap + [int]$operation.sshAndMarker
        vault = [int]$operation.vaultSnapshot + [int]$operation.multipassLaunch + [int]$operation.multipassReadiness + [int]$operation.payloadTransfer + [int]$operation.vaultBootstrap + [int]$operation.sshAndMarker
    }
    $desktop = [int]$operation.bootstrap + [int]$operation.preflight + [int]$operation.prerequisites + [int]$operation.windowsTailscale + [int]$operation.hostAgent + $stage.compute + [int]$operation.tailscale + [int]$operation.shortcuts + [int]$operation.export + [int]$operation.verification
    $laptop = [int]$operation.bootstrap + [int]$operation.preflight + [int]$operation.prerequisites + [int]$operation.windowsTailscale + [int]$operation.hostAgent + $stage.compute + $stage.vault + ([int]$operation.tailscale * 2) + [int]$operation.vaultClient + [int]$operation.shortcuts + [int]$operation.export + [int]$operation.verification
    $transactionMargin = 600
    $observerMargin = 600
    $fullReleaseMargin = 600
    $exactProofMargin = 600
    $maxRebootBoundaries = 3
    $observerNoProgress = 1800
    if ($configured) {
        foreach ($name in @('TransactionTerminalizationMarginSeconds','ObserverTerminalizationMarginSeconds','FullReleaseTerminalizationMarginSeconds','ExactProofTerminalizationMarginSeconds','MaxRebootBoundaries','ObserverNoProgressBudgetSeconds')) {
            if ($configured.PSObject.Properties[$name]) {
                $value = [int]$configured.$name
                if ($value -le 0 -and $name -ne 'MaxRebootBoundaries') { throw "Deadline policy '$name' must be positive." }
                if ($name -eq 'TransactionTerminalizationMarginSeconds') { $transactionMargin = $value }
                elseif ($name -eq 'ObserverTerminalizationMarginSeconds') { $observerMargin = $value }
                elseif ($name -eq 'FullReleaseTerminalizationMarginSeconds') { $fullReleaseMargin = $value }
                elseif ($name -eq 'ExactProofTerminalizationMarginSeconds') { $exactProofMargin = $value }
                elseif ($name -eq 'MaxRebootBoundaries') { $maxRebootBoundaries = $value }
                elseif ($name -eq 'ObserverNoProgressBudgetSeconds') { $observerNoProgress = $value }
            }
        }
    }
    if ($maxRebootBoundaries -lt 1) { throw 'Deadline policy must permit at least one bounded reboot boundary.' }
    $transaction = [ordered]@{ Desktop = $desktop + $transactionMargin; Laptop = $laptop + $transactionMargin }
    $observerAbsoluteByRole = [ordered]@{
        Desktop = [int]$transaction.Desktop + $observerMargin
        Laptop = [int]$transaction.Laptop + $observerMargin
    }
    # Keep legacy scalar consumers conservative: the scalar is the largest
    # role budget, while lifecycle callers select the exact role value.
    $productTransaction = [int]($transaction.Values | Measure-Object -Maximum).Maximum
    $observerAbsolute = [int]($observerAbsoluteByRole.Values | Measure-Object -Maximum).Maximum
    $wpfAction = 600
    $rebootBoundary = 420
    $servicingSettlement = 180
    $interactiveDesktop = 300
    $checkpointPolling = 900
    $lifecycleInner = $wpfAction + (($maxRebootBoundaries + 1) * $observerAbsolute) + ($maxRebootBoundaries * ($wpfAction + $rebootBoundary + $servicingSettlement + $interactiveDesktop)) + $checkpointPolling + $transactionMargin
    $fullReleaseInner = $lifecycleInner
    $fullReleaseWatchdog = $fullReleaseInner + $fullReleaseMargin
    $exactProofInner = 300 + $fullReleaseInner
    $exactProofOuter = $exactProofInner + $exactProofMargin
    $maximumOuter = 90000
    if ($configured -and $configured.PSObject.Properties['MaximumExactProofOuterWatchdogSeconds']) { $maximumOuter = [int]$configured.MaximumExactProofOuterWatchdogSeconds }
    $policy = [pscustomobject][ordered]@{
        version = $script:DeadlinePolicyVersion
        operationMaximumsSeconds = [pscustomobject]$operation
        guestBootstrapComponentsSeconds = [pscustomobject]$guestBootstrapComponents
        stageBudgetsSeconds = [pscustomobject]$stage
        transactionBudgetsSeconds = [pscustomobject]$transaction
        transactionTerminalizationMarginSeconds = $transactionMargin
        observerTerminalizationMarginSeconds = $observerMargin
        fullReleaseTerminalizationMarginSeconds = $fullReleaseMargin
        exactProofTerminalizationMarginSeconds = $exactProofMargin
        observerNoProgressBudgetSeconds = $observerNoProgress
        observerAbsoluteBudgetSeconds = $observerAbsolute
        observerAbsoluteBudgetsSeconds = [pscustomobject]$observerAbsoluteByRole
        productTransactionAbsoluteBudgetSeconds = $productTransaction
        productLifecycleInnerBoundSeconds = $lifecycleInner
        fullReleaseInnerBoundSeconds = $fullReleaseInner
        fullReleaseWatchdogSeconds = $fullReleaseWatchdog
        exactProofInnerBoundSeconds = $exactProofInner
        exactProofOuterWatchdogSeconds = $exactProofOuter
        maximumExactProofOuterWatchdogSeconds = $maximumOuter
        maxRebootBoundaries = $maxRebootBoundaries
        inequalities = [ordered]@{
            stageDominatesOperations = ([int]$stage.compute -gt ([int]$operation.guestBootstrap + [int]$operation.sshAndMarker))
            stageDominatesComputeOperations = ([int]$stage.compute -gt ([int]$operation.guestBootstrap + [int]$operation.sshAndMarker))
            stageDominatesVaultOperations = ([int]$stage.vault -gt ([int]$operation.vaultBootstrap + [int]$operation.sshAndMarker))
            observerDominatesDesktopTransaction = ([int]$observerAbsoluteByRole.Desktop -gt [int]$transaction.Desktop)
            observerDominatesLaptopTransaction = ([int]$observerAbsoluteByRole.Laptop -gt [int]$transaction.Laptop)
            observerDominatesTransaction = (($observerAbsoluteByRole.Values | Where-Object { $_ -gt 0 }).Count -eq 2 -and [int]$observerAbsoluteByRole.Desktop -gt [int]$transaction.Desktop -and [int]$observerAbsoluteByRole.Laptop -gt [int]$transaction.Laptop)
            fullReleaseDominatesObserver = ($fullReleaseWatchdog -gt $observerAbsolute)
            exactProofDominatesInner = ($exactProofOuter -gt $exactProofInner)
        }
    }
    Assert-HarnessBudgetPolicy -Policy $policy | Out-Null
    return $policy
}

function Assert-HarnessBudgetPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Policy)
    foreach ($name in @('productTransactionAbsoluteBudgetSeconds','observerAbsoluteBudgetSeconds','fullReleaseWatchdogSeconds','exactProofInnerBoundSeconds','exactProofOuterWatchdogSeconds')) {
        if (-not $Policy.PSObject.Properties[$name] -or [int]$Policy.$name -le 0) { throw "Deadline policy is missing a finite positive '$name'." }
    }
    foreach ($role in @('Desktop','Laptop')) {
        if (-not $Policy.observerAbsoluteBudgetsSeconds.PSObject.Properties[$role]) { throw "Deadline policy is missing observer absolute budget for $role." }
        if ([int]$Policy.observerAbsoluteBudgetsSeconds.$role -le [int]$Policy.transactionBudgetsSeconds.$role) { throw "Invalid deadline hierarchy: observer absolute must strictly exceed $role transaction." }
    }
    if ([int]$Policy.observerAbsoluteBudgetSeconds -lt [int]$Policy.observerAbsoluteBudgetsSeconds.Laptop) { throw 'Legacy observer absolute scalar must conservatively cover Laptop.' }
    if ([int]$Policy.fullReleaseWatchdogSeconds -le [int]$Policy.observerAbsoluteBudgetSeconds) { throw 'Invalid deadline hierarchy: FullRelease watchdog must strictly exceed observer absolute.' }
    if ([int]$Policy.exactProofOuterWatchdogSeconds -le [int]$Policy.exactProofInnerBoundSeconds) { throw 'Invalid deadline hierarchy: exact-proof outer watchdog must strictly exceed its calculated inner bound.' }
    if ([int]$Policy.exactProofOuterWatchdogSeconds -gt [int]$Policy.maximumExactProofOuterWatchdogSeconds) { throw "Deadline policy requires exact-proof outer watchdog $($Policy.exactProofOuterWatchdogSeconds)s, exceeding configured maximum $($Policy.maximumExactProofOuterWatchdogSeconds)s; refusing to truncate." }
    return $true
}

function Get-DeadlineRemainingSeconds {
    param([Parameter(Mandatory)][datetime]$DeadlineUtc, [datetime]$NowUtc = ([datetime]::UtcNow))
    [int][math]::Floor(($DeadlineUtc.ToUniversalTime() - $NowUtc.ToUniversalTime()).TotalSeconds)
}

function Get-EffectiveDeadlineTimeoutSeconds {
    param([Parameter(Mandatory)][int]$OperationMaximumSeconds, [Parameter(Mandatory)][datetime]$DeadlineUtc, [datetime]$NowUtc = ([datetime]::UtcNow))
    if ($OperationMaximumSeconds -le 0) { throw 'Operation maximum must be positive.' }
    $remaining = Get-DeadlineRemainingSeconds -DeadlineUtc $DeadlineUtc -NowUtc $NowUtc
    if ($remaining -le 0) { throw 'Owning deadline has expired; refusing to start another child operation.' }
    [math]::Min($OperationMaximumSeconds, $remaining)
}

Export-ModuleMember -Function Get-HarnessBudgetPolicy,Assert-HarnessBudgetPolicy,Get-DeadlineRemainingSeconds,Get-EffectiveDeadlineTimeoutSeconds

```


## FILE: automation/release-e2e/modules/HostSafety.psm1

SHA256: 9dcbac957f5aa060f0441eb8d372e39a190aab54cbf9af718a05368e567cb6c1 | Bytes: 8910 | Git mode: 100644

```
Set-StrictMode -Version Latest

function Get-DisposableVm {
    param([string]$VmName,[string]$Pattern = 'DevFleet-E2E-*')
    if ($VmName) { $vms = @(Get-VM -Name $VmName -ErrorAction Stop) } else { $vms = @(Get-VM | Where-Object { $_.Name -like $Pattern }) }
    if ($vms.Count -eq 0) { throw 'No ownership-scoped disposable DevFleet-E2E VM was found.' }
    if ($vms.Count -gt 1 -and -not $VmName) { throw "Dis