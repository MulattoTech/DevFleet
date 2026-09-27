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
