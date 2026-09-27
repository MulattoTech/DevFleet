# DevFleet source part 016

Full-source UTF-8 byte interval [697500, 744000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 48dcc2d6b29e984a6bd6eff183ac9b9672549aad1824f92d29a0673885de042f

<!-- BEGIN SOURCE SLICE -->
istryValueKind]::String)
            $key.SetValue('DefaultDomainName',[string]$env:COMPUTERNAME,[Microsoft.Win32.RegistryValueKind]::String)
            $key.SetValue('AutoAdminLogon','1',[Microsoft.Win32.RegistryValueKind]::String)
            # The only direct native Winlogon success on this exact disposable
            # guest used a generous internal allowance. The safety boundary is
            # the host-side one-reboot/deadline contract, never this count.
            $key.SetValue('AutoLogonCount',100,[Microsoft.Win32.RegistryValueKind]::DWord)
            $key.SetValue('DefaultPassword',$plain,[Microsoft.Win32.RegistryValueKind]::String)
            $check=[ordered]@{DefaultUserName=[string]$key.GetValue('DefaultUserName',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);DefaultDomainName=[string]$key.GetValue('DefaultDomainName',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);AutoAdminLogon=[string]$key.GetValue('AutoAdminLogon',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);AutoLogonCount=[int]$key.GetValue('AutoLogonCount',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);DefaultPasswordPresent=(@($key.GetValueNames()) -contains 'DefaultPassword')}
            if ([string]$check.DefaultUserName -cne 'E2EAdmin' -or [string]$check.DefaultDomainName -cne [string]$env:COMPUTERNAME -or [string]$check.AutoAdminLogon -cne '1' -or [int]$check.AutoLogonCount -ne 100 -or -not [bool]$check.DefaultPasswordPresent) { throw 'Native Winlogon bounded configuration did not verify.' }
            $key.Flush()
            [pscustomobject]@{status='PASS';mode='native-winlogon';user='E2EAdmin';domain=[string]$env:COMPUTERNAME;autoAdminLogon=1;autoLogonCount=100;defaultPasswordPresent=$true;ordinaryDefaultPasswordPresent=$true;passwordMatchesCredential=$true}
        } finally {
            if ($key) { $key.Dispose() }
            if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
            $plain=$null
        }
    } -ArgumentList $CredentialPassword
    $barrier=Invoke-DevFleetE2ERegistryPersistenceBarrier -Session $Session -PathLabel 'Winlogon'
    $durable=Get-DevFleetE2EWinlogonBaseline -Session $Session
    if([string]$durable.DefaultUserName -cne 'E2EAdmin' -or [string]$durable.DefaultDomainName -cne 'DEVFLEET-E2E-01' -or [string]$durable.AutoAdminLogon -cne '1' -or [int]$durable.AutoLogonCount -ne 100 -or -not [bool]$durable.OrdinaryDefaultPasswordPresent){throw 'Native Winlogon configuration did not survive the registry persistence barrier.'}
    [pscustomobject]@{status='PASS';mode='native-winlogon';user='E2EAdmin';domain='DEVFLEET-E2E-01';autoAdminLogon=1;autoLogonCount=100;defaultPasswordPresent=$true;ordinaryDefaultPasswordPresent=$true;passwordMatchesCredential=$true;registryArmVerified=$true;registryPersistenceBarrier=$barrier;registryPersistenceBarrierUtc=([string]$barrier.paths[0].timestampUtc)}
}

function Restore-DevFleetE2EWinlogonBaseline {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,[Parameter(Mandatory)][psobject]$Baseline)
    Invoke-Command -Session $Session -ScriptBlock {
        param($saved)
        $path='SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';$key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($path,$true)
        if($null -eq $key){throw 'Winlogon baseline restore could not open the allowlisted Winlogon key.'}
        try {
            foreach($name in @('AutoAdminLogon','AutoLogonCount','DefaultUserName','DefaultDomainName','IgnoreShiftOverride','ForceAutoLogon')) {
                $presenceProperty=$saved.PSObject.Properties["${name}Present"]
                $present=if($null -ne $presenceProperty){[bool]$presenceProperty.Value}else{$false}
                if(-not $present){$key.DeleteValue($name,$false);continue}
                $valueProperty=$saved.PSObject.Properties[$name]
                if($null -eq $valueProperty){throw "Captured Winlogon baseline value was missing for $name."}
                $value=$valueProperty.Value
                $kind=if($name -in @('AutoLogonCount','IgnoreShiftOverride')){[Microsoft.Win32.RegistryValueKind]::DWord}else{[Microsoft.Win32.RegistryValueKind]::String}
                $key.SetValue($name,$value,$kind)
            }
            $key.DeleteValue('DefaultPassword',$false)
            if(@($key.GetValueNames()) -contains 'DefaultPassword'){throw 'Ordinary Winlogon DefaultPassword remained after cleanup.'}
            $key.Flush()
            [pscustomobject]@{status='PASS';ordinaryDefaultPasswordPresent=$false;autologonStateCleared=$true}
        } finally {$key.Dispose()}
    } -ArgumentList $Baseline | Out-Null
    $barrier=Invoke-DevFleetE2ERegistryPersistenceBarrier -Session $Session -PathLabel 'Winlogon'
    $durable=Get-DevFleetE2EWinlogonBaseline -Session $Session
    foreach($name in @('AutoAdminLogon','AutoLogonCount','DefaultUserName','DefaultDomainName','IgnoreShiftOverride','ForceAutoLogon')){
        $expectedPresenceProperty=$Baseline.PSObject.Properties["${name}Present"]
        $actualPresenceProperty=$durable.PSObject.Properties["${name}Present"]
        $present=if($null -ne $expectedPresenceProperty){[bool]$expectedPresenceProperty.Value}else{$false}
        $actualPresent=if($null -ne $actualPresenceProperty){[bool]$actualPresenceProperty.Value}else{$false}
        if($present -ne $actualPresent){throw "Winlogon baseline persistence verification failed for $name."}
        if($present){
            $expectedValueProperty=$Baseline.PSObject.Properties[$name]
            $actualValueProperty=$durable.PSObject.Properties[$name]
            if($null -eq $expectedValueProperty -or $null -eq $actualValueProperty -or [string]$expectedValueProperty.Value -cne [string]$actualValueProperty.Value){throw "Winlogon baseline persistence verification failed for $name."}
        }
    }
    if([bool]$durable.OrdinaryDefaultPasswordPresent){throw 'Ordinary Winlogon DefaultPassword remained after durable cleanup.'}
    [pscustomobject]@{status='PASS';ordinaryDefaultPasswordPresent=$false;autologonStateCleared=$true;registryCleanupPersisted=$true;temporaryDefaultPasswordRemovalPersisted=$true;autologonBaselinePersistenceConfirmed=$true;registryPersistenceBarrier=$barrier}
}

function Get-DevFleetE2EInteractiveDesktopState {
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)
    Invoke-Command -Session $Session -ScriptBlock {
        $safe = { param($e) $message=([string]$e.Exception.Message -replace '\r?\n',' ');$message=([regex]::Replace($message,'(?i)(password|secret|token|credential)\s*[:=]\s*\S+','$1=<redacted>'));if($message.Length -gt 320){$message=$message.Substring(0,320)};[ordered]@{type=$e.Exception.GetType().FullName;message=$message} }
        $active=@(); $quserLines=@(); $quserError=$null
        try {$quserLines=@(& quser 2>&1);if($LASTEXITCODE -ne 0){$quserError=[ordered]@{type='QuserExitCode';message=(($quserLines -join ' ') -replace '\r?\n',' ')}}}catch{$quserError=&$safe $_}
        foreach($line in $quserLines){if(([string]$line) -match '^\s*>?\s*(\S+)\s+(\S*)\s+(\d+)\s+(Active)\s+'){$active+=[pscustomobject]@{user=$Matches[1];sessionName=$Matches[2];sessionId=[int]$Matches[3];state='Active'}}}
        $explorer=@();$explorerErrors=@()
        foreach($process in @(Get-Process explorer -ErrorAction SilentlyContinue)){
            try{$row=Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)" -ErrorAction Stop;$owner=Invoke-CimMethod -InputObject $row -MethodName GetOwner -ErrorAction Stop;$explorer+=[pscustomobject]@{pid=[int]$process.Id;sessionId=[int]$process.SessionId;user=[string]$owner.User;domain=[string]$owner.Domain;owner="$($owner.Domain)\$($owner.User)"}}catch{$explorerErrors+=&$safe $_}
        }
        # quser may normalize the display token's case; principal identity is
        # still bounded by the exact guest, non-zero session, session type, and
        # Explorer owner/domain checks below.
        $expectedActive=@($active|Where-Object{$_.user -ieq 'E2EAdmin' -and $_.sessionId -gt 0 -and ($_.sessionName -ieq 'console' -or $_.sessionName -like 'rdp-tcp*')})
        $bound=@($explorer|Where-Object{$_.user -ieq 'E2EAdmin' -and $_.domain -ieq 'DEVFLEET-E2E-01' -and $_.sessionId -gt 0 -and @($expectedActive.sessionId) -contains $_.sessionId})
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        [ordered]@{computer=$env:COMPUTERNAME;boot=$os.LastBootUpTime.ToUniversalTime().ToString('o');expectedComputer='DEVFLEET-E2E-01';expectedUser='E2EAdmin';expectedDomain='DEVFLEET-E2E-01';activeSessions=$active;activeInteractiveSessionName=if($expectedActive.Count -eq 1){[string]$expectedActive[0].sessionName}else{''};activeInteractiveSessionId=if($expectedActive.Count -eq 1){[int]$expectedActive[0].sessionId}else{-1};explorer=$explorer;explorerCollectionErrors=$explorerErrors;boundExplorer=$bound;windowStation='WinSta0\Default';quser=($quserLines -join "`n");quserError=$quserError}
    }
}

function Get-DevFleetE2EInteractiveDesktopSummary {
    param([Parameter(Mandatory)][psobject]$State)
    [ordered]@{computer=[string]$State.computer;boot=[string]$State.boot;activeSessions=@($State.activeSessions|ForEach-Object{[ordered]@{user=[string]$_.user;sessionName=[string]$_.sessionName;sessionId=[int]$_.sessionId;state=[string]$_.state}});activeInteractiveSessionName=[string]$State.activeInteractiveSessionName;activeInteractiveSessionId=[int]$State.activeInteractiveSessionId;explorer=@($State.explorer|ForEach-Object{[ordered]@{pid=[int]$_.pid;sessionId=[int]$_.sessionId;user=[string]$_.user;domain=[string]$_.domain;owner=[string]$_.owner}});explorerCollectionErrorCount=@($State.explorerCollectionErrors).Count;quser=[string]$State.quser;quserError=$State.quserError}
}

function Get-DevFleetE2EInteractiveDesktopFailureCategory {
    param([AllowNull()][psobject]$State,[ValidateSet('vm-state','pssession','guest-state','assertion')][string]$Stage)
    if($Stage -eq 'vm-state'){return 'vm-state-collection-failure'}
    if($Stage -eq 'pssession'){return 'pssession-unavailable'}
    if($Stage -eq 'guest-state'){return 'guest-state-collection-failure'}
    if($null -eq $State){return 'desktop-assertion-failure'}
    if([int]$State.activeInteractiveSessionId -le 0){return 'no-active-e2eadmin-session'}
    $explorer=@($State.explorer)
    if($explorer.Count -eq 0){return 'explorer-absent'}
    $exactUser=@($explorer|Where-Object{[string]$_.owner -ceq "$script:DevFleetE2EDomain\$script:DevFleetE2EUser"})
    if($exactUser.Count -eq 0){return 'wrong-explorer-user'}
    return 'wrong-noninteractive-session'
}

function Assert-DevFleetE2EInteractiveDesktop {
    param([Parameter(Mandatory)][psobject]$State)
    if([string]$State.computer -cne $script:DevFleetE2EGuestComputer){throw 'Interactive desktop rejected: guest computer identity mismatch.'}
    $sessionId=[int]$State.activeInteractiveSessionId
    if($sessionId -le 0){throw 'Interactive desktop rejected: no active non-zero E2EAdmin console session.'}
    if($State.PSObject.Properties['activeInteractiveSessionName']){if($script:InteractiveLogonMode -eq 'rdp-fallback'){if([string]$State.activeInteractiveSessionName -notlike 'rdp-tcp*'){throw 'RemoteInteractive desktop rejected: active session is not an RDP session.'}}elseif([string]$State.activeInteractiveSessionName -cne 'console'){throw 'Interactive desktop rejected: active session is not the console session.'}}
    $bound=@($State.boundExplorer|Where-Object{[string]$_.owner -ceq "$script:DevFleetE2EDomain\$script:DevFleetE2EUser" -and [int]$_.sessionId -eq $sessionId -and [int]$_.sessionId -ne 0})
    if($bound.Count -ne 1){throw 'Interactive desktop rejected: Explorer owner/session is not the exact E2EAdmin interactive desktop.'}
    [pscustomobject]@{status='PASS';computer=$State.computer;user=$script:DevFleetE2EUser;domain=$script:DevFleetE2EDomain;sessionId=$sessionId;explorerPid=[int]$bound[0].pid;windowStation='WinSta0\Default'}
}

function Arm-DevFleetE2EInteractiveLogon {
    [CmdletBinding()]
    param([Parameter(Mandatory)][guid]$VmId,[AllowNull()][psobject]$CredentialValidation=$null)
    $vm=Get-AssertedDevFleetE2EL1 -VmId $VmId
    $credential=Get-DevFleetE2ECredential
    $user=([string]$credential.UserName -split '\\')[-1]
    if($user -cne $script:DevFleetE2EUser){throw 'Canonical E2E credential username is not E2EAdmin.'}
    $session=$null;$baseline=$null;$lsaClearedBeforeArm=$false;$rdpBaseline=$null;$rdpEnabled=$false;$policyBaseline=$null;$policyMutationStarted=$false;$policySuppressed=$false
    try{
        $script:InteractiveLogonRestartRequested=$false
        $session=New-PSSession -VMId $vm.Id -Credential $credential -ErrorAction Stop
        $auth=Invoke-Command -Session $session -ScriptBlock { $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; [ordered]@{computer=$env:COMPUTERNAME;user=$env:USERNAME;authenticated=$true;boot=$os.LastBootUpTime.ToUniversalTime().ToString('o')} }
        if([string]$auth.computer -cne $script:DevFleetE2EGuestComputer -or [string]$auth.user -cne $script:DevFleetE2EUser){throw 'PowerShell Direct credential proof reached the wrong guest identity.'}
        $baseline=Get-DevFleetE2EWinlogonBaseline -Session $session
        $credentialRoundTrip=if($CredentialValidation){$CredentialValidation}else{Test-DevFleetE2EGuestCredential -Session $session -CredentialPassword $credential.Password}
        if($script:InteractiveLogonMode -eq 'rdp-fallback'){
            $rdpBaseline=Get-DevFleetE2ERdpBaseline -Session $session
            $rdp=Enable-DevFleetE2ERdp -Session $session -Baseline $rdpBaseline
            $rdpEnabled=$true
            $arm=[pscustomobject]@{status='ARMED';mode='rdp-fallback';requiredLogonType='RemoteInteractive';contract=$script:InteractiveLogonContract;vmName=$vm.Name;vmId=$vm.Id.ToString();user=$script:DevFleetE2EUser;domain=$script:DevFleetE2EDomain;rdpAddress=[string]$rdp.address;rdpBaseline=$rdpBaseline;baseline=$baseline;credentialRoundTripValidated=[bool]$credentialRoundTrip.success;credentialRoundTrip=$credentialRoundTrip;lsaStored=$false;lsaProof=[ordered]@{secretPresent=$false;secretMatchesCredential=$false};preBoot=[string]$auth.boot;ordinaryDefaultPasswordPresent=[bool]$baseline.OrdinaryDefaultPasswordPresent}
            $script:ActiveInteractiveLogonArm=$arm
            return $arm
        }
        if([bool]$baseline.OrdinaryDefaultPasswordPresent){throw 'Native Winlogon arm refused a pre-existing ordinary DefaultPassword on the exact L1.'}
        $policyBaseline=Get-DevFleetE2EPreLogonPolicyState -Session $session
        if([bool]$policyBaseline.caption.present -or [bool]$policyBaseline.text.present -or [bool]$policyBaseline.winlogonCaption.present -or [bool]$policyBaseline.winlogonText.present){$policyMutationStarted=$true;$removed=Remove-DevFleetE2EPreLogonPolicy -Session $session;if([bool]$removed.captionPresent -or [bool]$removed.textPresent -or [bool]$removed.winlogonCaptionPresent -or [bool]$removed.winlogonTextPresent){throw 'LOGON_BANNER_POLICY_REASSERTED: exact L1 reasserted a legal-notice value before native Winlogon arm.'};$policySuppressed=$true}
        $script:ActiveInteractiveLogonPolicyBaseline=$policyBaseline
        # The historical direct success used only ordinary Winlogon
        # DefaultPassword. Do not touch LSA state during the functional arm;
        # disarm/final cleanup remains responsible for clearing any residual.
        $lsaClearedBeforeArm=$false
        $config=Set-DevFleetE2EWinlogonAutologon -Session $session -CredentialPassword $credential.Password
        $arm=[pscustomobject]@{status='ARMED';mode='native-winlogon';contract=$script:InteractiveLogonContract;vmName=$vm.Name;vmId=$vm.Id.ToString();user=$script:DevFleetE2EUser;domain=$script:DevFleetE2EDomain;autoAdminLogon=1;autoLogonCount=[int]$config.autoLogonCount;defaultPasswordPresent=[bool]$config.defaultPasswordPresent;baseline=$baseline;preLogonPolicy=(Get-DevFleetE2EPreLogonPolicyStructure -State $policyBaseline);preLogonPolicySuppressed=$policySuppressed;preLogonPolicySuppressionPersisted=if($policyMutationStarted){[bool]$removed.preLogonPolicySuppressionPersisted}else{$false};preLogonPolicyReasserted=$false;credentialRoundTripValidated=[bool]$credentialRoundTrip.success;credentialRoundTrip=$credentialRoundTrip;registryArmVerified=[bool]$config.registryArmVerified;registryPersistenceBarrier=$config.registryPersistenceBarrier;registryPersistenceBarrierUtc=[string]$config.registryPersistenceBarrierUtc;lsaStored=$false;lsaClearedBeforeArm=$lsaClearedBeforeArm;lsaProof=[ordered]@{secretPresent=$false;secretMatchesCredential=$false};preBoot=[string]$auth.boot;ordinaryDefaultPasswordPresent=[bool]$config.ordinaryDefaultPasswordPresent}
        $script:ActiveInteractiveLogonArm=$arm
        $arm
    }catch{
        if($session -and $policyBaseline -and $policyMutationStarted){try{Restore-DevFleetE2EPreLogonPolicy -Session $session -Baseline $policyBaseline|Out-Null}catch{}}
        if($session -and $rdpEnabled -and $rdpBaseline){try{Restore-DevFleetE2ERdp -Session $session -Baseline $rdpBaseline|Out-Null}catch{}}
        if($session -and $baseline){try{Restore-DevFleetE2EWinlogonBaseline -Session $session -Baseline $baseline|Out-Null}catch{}}
        throw
    }finally{if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}}
}

function Restart-DevFleetE2EL1 {
    param([Parameter(Mandatory)][psobject]$ArmState)
    if([string]$ArmState.status -ne 'ARMED' -or [string]$ArmState.vmId -cne $script:DevFleetE2EL1Id.ToString()){throw 'Only an armed exact disposable L1 may be restarted for interactive autologon.'}
    if($script:InteractiveLogonRestartRequested){throw 'The exact interactive-logon arm already consumed its one authorized host reboot.'}
    $vm=Get-AssertedDevFleetE2EL1 -VmId $script:DevFleetE2EL1Id
    if([string]$vm.State -notin @('Running','Paused')){throw 'Exact disposable L1 is not in a restartable state.'}
    Restart-VM -VM $vm -Force -Confirm:$false -ErrorAction Stop
    $script:InteractiveLogonRestartRequested=$true
    $requestedAt=(Get-Date).ToUniversalTime().ToString('o')
    [pscustomobject]@{status='RESTART_REQUESTED';vmName=$vm.Name;vmId=$vm.Id.ToString();hostControlled=$true;productionTouched=$false;rebootCount=1;requestedAtUtc=$requestedAt;armDeadlineSeconds=120;quietSettleSeconds=60}
}

function Wait-DevFleetE2EInteractiveDesktop {
    param([Parameter(Mandatory)][guid]$VmId,[int]$TimeoutSeconds=120,[datetime]$RestartedAtUtc=[datetime]::MinValue,[int]$QuietSettleSeconds=60,[int]$PollIntervalSeconds=10)
    if($VmId -ne $script:DevFleetE2EL1Id){throw 'Interactive desktop wait refused a VM outside the authorized L1 GUID.'}
    $credential=Get-DevFleetE2ECredential;$rdpTarget=$null;$rdpAddress=$null;$rdpClient=$null
    if($script:InteractiveLogonMode -eq 'rdp-fallback' -and ($null -eq $script:ActiveInteractiveLogonArm -or [string]$script:ActiveInteractiveLogonArm.status -ne 'ARMED')){throw 'RDP fallback wait requires an armed exact disposable L1.'}
    $startUtc=if($RestartedAtUtc -ne [datetime]::MinValue){$RestartedAtUtc.ToUniversalTime()}else{(Get-Date).ToUniversalTime()}
    $deadlineUtc=$startUtc.AddSeconds([Math]::Max(1,$TimeoutSeconds));$quietUntilUtc=$startUtc.AddSeconds([Math]::Max(0,$QuietSettleSeconds));$progress=[System.Collections.Generic.List[object]]::new();$lastState=$null;$lastFailure=$null;$poll=0;$firstGuestConnectionAtUtc=$null
    # Keep the guest completely undisturbed until the historical successful
    # experiment's approximately 60-second quiet settle has elapsed. This is
    # host-side waiting only; no PSSession, quser, or Explorer poll occurs here.
    while((Get-Date).ToUniversalTime() -lt $quietUntilUtc -and (Get-Date).ToUniversalTime() -lt $deadlineUtc){$remaining=[int][Math]::Ceiling(($quietUntilUtc-(Get-Date).ToUniversalTime()).TotalSeconds);Start-Sleep -Seconds ([Math]::Min(5,[Math]::Max(1,$remaining)))}
    do{
        $session=$null;$vm=$null;$raw=$null;$entry=[ordered]@{poll=[int]$poll;timestamp=(Get-Date).ToUniversalTime().ToString('o');vmState=$null;powerShellDirect=[ordered]@{attempted=$false;connected=$false;failure=$null};rdpAddress=$null;guestBoot=$null;activeSessions=@();quser=$null;explorer=@();explorerCollectionErrors=@();assertionStage='not-started';failureCategory=$null;failure=$null;lastSuccessfullyCollectedState=$lastState}
        try {
            try{$vm=Get-AssertedDevFleetE2EL1 -VmId $VmId;$entry.vmState=[string]$vm.State}catch{$entry.failureCategory=Get-DevFleetE2EInteractiveDesktopFailureCategory -Stage vm-state;$entry.failure=Get-DevFleetSafeException -Exception $_.Exception;throw}
            if([string]$vm.State -ne 'Running'){$entry.failureCategory='vm-not-running';$entry.failure=[ordered]@{type='VmState';message="Exact L1 state is $($vm.State)."};throw [InvalidOperationException]::new("Exact L1 is not running ($($vm.State)).")}
            $entry.powerShellDirect.attempted=$true
            try{$session=New-PSSession -VMId $VmId -Credential $credential -ErrorAction Stop;$entry.powerShellDirect.connected=$true;if($null -eq $firstGuestConnectionAtUtc){$firstGuestConnectionAtUtc=(Get-Date).ToUniversalTime().ToString('o')}}catch{$entry.failureCategory=Get-DevFleetE2EInteractiveDesktopFailureCategory -Stage pssession;$entry.powerShellDirect.failure=Get-DevFleetSafeException -Exception $_.Exception;throw}
            if($script:InteractiveLogonMode -eq 'rdp-fallback' -and $null -eq $rdpClient){
                try {
                    $rdp=Enable-DevFleetE2ERdp -Session $session -Baseline $script:ActiveInteractiveLogonArm.rdpBaseline
                    $address=[string]$rdp.address
                    if([string]::IsNullOrWhiteSpace([string]$address)){throw 'Exact disposable guest returned an empty current IPv4 RDP address.'}
                    $rdpAddress=[string]$address
                    $rdpTarget="TERMSRV/$rdpAddress"
                    Set-DevFleetE2ERdpCredential -Target $rdpTarget -Credential $credential|Out-Null
                    $rdpClient=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\mstsc.exe') -ArgumentList @("/v:$rdpAddress") -PassThru -WindowStyle Hidden
                    $script:RdpClientProcessId=[int]$rdpClient.Id
                } catch {$entry.failureCategory=Get-DevFleetE2EInteractiveDesktopFailureCategory -Stage guest-state;$entry.failure=Get-DevFleetSafeException -Exception $_.Exception;throw}
            }
            $entry.rdpAddress=$rdpAddress
            try{$raw=Get-DevFleetE2EInteractiveDesktopState -Session $session;$lastState=Get-DevFleetE2EInteractiveDesktopSummary -State $raw;$entry.guestBoot=[string]$raw.boot;$entry.activeSessions=@($lastState.activeSessions);$entry.quser=[string]$raw.quser;$entry.explorer=@($lastState.explorer);$entry.explorerCollectionErrors=@($raw.explorerCollectionErrors);$entry.lastSuccessfullyCollectedState=$lastState;$entry.assertionStage='state-collected'}catch{$entry.failureCategory=Get-DevFleetE2EInteractiveDesktopFailureCategory -Stage guest-state;$entry.failure=Get-DevFleetSafeException -Exception $_.Exception;throw}
            try{$proof=Assert-DevFleetE2EInteractiveDesktop -State $raw;$entry.assertionStage='passed';$progress.Add([pscustomobject]$entry);return [pscustomobject]@{status='PASS';mode=$script:InteractiveLogonMode;contract=$script:InteractiveLogonContract;vmName=$vm.Name;vmId=$vm.Id.ToString();boot=[string]$raw.boot;desktop=$proof;raw=$raw;rdpTarget=$rdpTarget;rdpClientPid=if($rdpClient){[int]$rdpClient.Id}else{$null};pollProgress=@($progress)}}catch{$entry.assertionStage='failed';$entry.failureCategory=Get-DevFleetE2EInteractiveDesktopFailureCategory -State $raw -Stage assertion;$entry.failure=Get-DevFleetSafeException -Exception $_.Exception;throw}
        } catch {
            if([string]::IsNullOrWhiteSpace([string]$entry.failureCategory)){
                $entry.failureCategory=if([bool]$entry.powerShellDirect.connected){'guest-state-collection-failure'}else{'interactive-desktop-poll-failure'}
            }
            if($null -eq $entry.failure){
                $exception=$_.Exception
                $message=if($exception){([string]$exception.Message -replace '\r?\n',' ')}else{'controlled interactive desktop poll failure'}
                if($message.Length -gt 320){$message=$message.Substring(0,320)}
                $entry.failure=[ordered]@{type=if($exception){$exception.GetType().FullName}else{'UnknownException'};message=$message}
            }
            $lastFailure=[pscustomobject]@{category=[string]$entry.failureCategory;stage=[string]$entry.assertionStage;failure=$entry.failure};$progress.Add([pscustomobject]$entry)
        } finally {if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}}
        $poll++
        # If the first quiet-settle inspection does not prove the desktop, do
        # not keep opening guest runspaces: each one creates a Type-2 logon
        # transition of its own. The only second guest observation is the
        # bounded final capture at the arm deadline.
        if($poll -eq 1){$remaining=[int][Math]::Ceiling(($deadlineUtc-(Get-Date).ToUniversalTime()).TotalSeconds);if($remaining -gt 0){Start-Sleep -Seconds $remaining}}
    }while($poll -lt 2)
    $diagnostic=[ordered]@{status='BLOCKED';reason='interactive-desktop-timeout';mode=$script:InteractiveLogonMode;rebootCount=1;restartedAtUtc=$startUtc.ToString('o');quietSettleSeconds=$QuietSettleSeconds;armDeadlineSeconds=$TimeoutSeconds;firstGuestConnectionAtUtc=$firstGuestConnectionAtUtc;guestObservationCount=$poll;rdpTarget=$rdpTarget;rdpClientPid=if($rdpClient){[int]$rdpClient.Id}else{$null};finalFailure=$lastFailure;pollProgress=@($progress);lastSuccessfullyCollectedState=$lastState;uniqueFailureCategories=@($progress|Where-Object{$_.failureCategory}|ForEach-Object{$_.failureCategory}|Select-Object -Unique)}
    $lastCategory=if($lastFailure){[string]$lastFailure.category}else{'no-desktop-state-observed'}
    $exception=[InvalidOperationException]::new("Exact disposable L1 did not establish the required interactive E2EAdmin desktop before the bounded deadline ($lastCategory).")
    $exception.Data['interactiveDesktopDiagnostic']=$diagnostic
    throw $exception
}

function Disarm-DevFleetE2EInteractiveLogon {
    param([Parameter(Mandatory)][psobject]$ArmState)
    if([string]$ArmState.status -ne 'ARMED' -or [string]$ArmState.vmId -cne $script:DevFleetE2EL1Id.ToString()){throw 'Interactive autologon disarm refused a non-authorized arm state.'}
    $credential=Get-DevFleetE2ECredential;$session=$null;$policyRestored=$false;$policyState=$null;$policyWasCaptured=($null -ne $script:ActiveInteractiveLogonPolicyBaseline)
    try {
        $vm=Get-AssertedDevFleetE2EL1 -VmId $script:DevFleetE2EL1Id;$session=New-PSSession -VMId $vm.Id -Credential $credential -ErrorAction Stop
        if([string]$ArmState.mode -eq 'rdp-fallback'){
            Restore-DevFleetE2ERdp -Session $session -Baseline $ArmState.rdpBaseline|Out-Null
            return [pscustomobject]@{status='DISARMED';mode='rdp-fallback';vmName=$vm.Name;vmId=$vm.Id.ToString();lsaCleared=$true;lsaDefaultPasswordPresent=$false;temporaryGuestRdpRestored=$true;credentialManagerRetainedForSession=$true;ordinaryDefaultPasswordPresent=$false;autoLogonCountRestored=$true;preLogonPolicyRestored=$null;preLogonPolicyReasserted=$null}
        }
        $restored=Restore-DevFleetE2EWinlogonBaseline -Session $session -Baseline $ArmState.baseline
        $lsa=Invoke-DevFleetE2EGuestLsa -Session $session -Clear
        if($script:ActiveInteractiveLogonPolicyBaseline){$policyState=Restore-DevFleetE2EPreLogonPolicy -Session $session -Baseline $script:ActiveInteractiveLogonPolicyBaseline;$policyRestored=$true;$script:ActiveInteractiveLogonPolicyBaseline=$null}
        [pscustomobject]@{status='DISARMED';mode='native-winlogon';vmName=$vm.Name;vmId=$vm.Id.ToString();lsaCleared=[bool]$lsa.cleared;lsaDefaultPasswordPresent=$false;ordinaryDefaultPasswordPresent=$false;temporaryDefaultPasswordRemovalPersisted=[bool]$restored.registryCleanupPersisted;registryCleanupPersisted=[bool]$restored.registryCleanupPersisted;autologonBaselinePersistenceConfirmed=[bool]$restored.autologonBaselinePersistenceConfirmed;autoLogonCountRestored=$true;temporaryAutoLogonStateRestored=$true;preLogonPolicy=$(if($policyState){$policyState}else{$null});preLogonPolicyRestored=$(if($policyWasCaptured){$policyRestored}else{$null});preLogonPolicyRestorationPersisted=if($policyWasCaptured){[bool]$policyState.preLogonPolicyRestorationPersisted}else{$null};preLogonPolicyReasserted=$false}
    } finally {
        if($script:ActiveInteractiveLogonPolicyBaseline -and $session){try{Restore-DevFleetE2EPreLogonPolicy -Session $session -Baseline $script:ActiveInteractiveLogonPolicyBaseline|Out-Null;$script:ActiveInteractiveLogonPolicyBaseline=$null}catch{}}
        if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}
    }
}

function Clear-DevFleetE2EInteractiveLogonState {
    param([Parameter(Mandatory)][guid]$VmId)
    $credential=Get-DevFleetE2ECredential;$session=$null
    try {
        $vm=Get-AssertedDevFleetE2EL1 -VmId $VmId
        if([string]$vm.State -ne 'Running'){throw 'Final interactive cleanup requires the exact disposable L1 to be Running before registry durability is established.'}
        $session=New-PSSession -VMId $vm.Id -Credential $credential -ErrorAction Stop
        if($script:ActiveInteractiveLogonArm -and [string]$script:ActiveInteractiveLogonArm.mode -eq 'rdp-fallback' -and $script:ActiveInteractiveLogonArm.rdpBaseline){Restore-DevFleetE2ERdp -Session $session -Baseline $script:ActiveInteractiveLogonArm.rdpBaseline|Out-Null}
        $policyRestored=$false
        if($script:ActiveInteractiveLogonPolicyBaseline){Restore-DevFleetE2EPreLogonPolicy -Session $session -Baseline $script:ActiveInteractiveLogonPolicyBaseline|Out-Null;$policyRestored=$true;$script:ActiveInteractiveLogonPolicyBaseline=$null}
        Invoke-Command -Session $session -ScriptBlock {
            $path='SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';$key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($path,$true)
            if($null -eq $key){throw 'Final interactive cleanup could not open the allowlisted Winlogon key.'}
            try {
                foreach($name in @('AutoAdminLogon','AutoLogonCount','DefaultUserName','DefaultDomainName','IgnoreShiftOverride','ForceAutoLogon','DefaultPassword')){$key.DeleteValue($name,$false)}
                $names=@($key.GetValueNames())
                if($names -contains 'DefaultPassword'){throw 'Final interactive autologon registry cleanup was incomplete.'}
                if(@($names|Where-Object{$_ -in @('AutoAdminLogon','AutoLogonCount','DefaultUserName','DefaultDomainName')}).Count -gt 0){throw 'Final interactive autologon transient state remained after cleanup.'}
                $key.Flush()
            } finally {$key.Dispose()}
        }|Out-Null
        $barrier=Invoke-DevFleetE2ERegistryPersistenceBarrier -Session $session -PathLabel 'Winlogon'
        $durable=Get-DevFleetE2EWinlogonBaseline -Session $session
        if([bool]$durable.OrdinaryDefaultPasswordPresent -or [bool]$durable.AutoAdminLogonPresent -or [bool]$durable.AutoLogonCountPresent -or [bool]$durable.DefaultUserNamePresent -or [bool]$durable.DefaultDomainNamePresent){throw 'Final interactive autologon registry cleanup did not persist the cleared transient state.'}
        $lsa=Invoke-DevFleetE2EGuestLsa -Session $session -Clear
        Remove-DevFleetE2ERdpCredential -Target $script:RdpCredentialTarget|Out-Null
        if($script:RdpClientProcessId){$client=Get-Process -Id $script:RdpClientProcessId -ErrorAction SilentlyContinue;if($client -and $client.Path -ieq (Join-Path $env:SystemRoot 'System32\mstsc.exe')){Stop-Process -Id $client.Id -Force -ErrorAction SilentlyContinue};$script:RdpClientProcessId=$null}
        $script:ActiveInteractiveLogonArm=$null
        [pscustomobject]@{status='PASS';vmName=$vm.Name;vmId=$vm.Id.ToString();lsaCleared=[bool]$lsa.cleared;lsaDefaultPasswordPresent=$false;autologonStateCleared=$true;temporaryDefaultPasswordRemovalPersisted=$true;registryCleanupPersisted=$true;registryPersistenceBarrier=$barrier;temporaryGuestRdpRestored=$true;credentialManagerRemoved=$true;ordinaryDefaultPasswordPresent=$false;preLogonPolicyRestored=$policyRestored;preLogonPolicyRestorationPersisted=$policyRestored}
    } finally {
        if($script:ActiveInteractiveLogonPolicyBaseline -and $session){try{Restore-DevFleetE2EPreLogonPolicy -Session $session -Baseline $script:ActiveInteractiveLogonPolicyBaseline|Out-Null;$script:ActiveInteractiveLogonPolicyBaseline=$null}catch{}}
        if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}
    }
}

function Assert-DevFleetE2EInteractiveDesktopAfterDisarm {
    param([Parameter(Mandatory)][guid]$VmId)
    $credential=Get-DevFleetE2ECredential;$session=$null
    try{$vm=Get-AssertedDevFleetE2EL1 -VmId $VmId;$session=New-PSSession -VMId $VmId -Credential $credential -ErrorAction Stop;$raw=Get-DevFleetE2EInteractiveDesktopState -Session $session;$proof=Assert-DevFleetE2EInteractiveDesktop -State $raw;[pscustomobject]@{status='PASS';survivesDisarm=$true;desktop=$proof}}finally{if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}}
}

Export-ModuleMember -Function Get-DevFleetE2EInteractiveLogonTarget,Assert-DevFleetE2EL1Identity,Get-AssertedDevFleetE2EL1,Get-DevFleetE2EInteractiveDesktopState,Get-DevFleetE2EInteractiveDesktopFailureCategory,Get-DevFleetE2EPreLogonPolicyState,Get-DevFleetE2EPreLogonPolicyStructure,Remove-DevFleetE2EPreLogonPolicy,Restore-DevFleetE2EPreLogonPolicy,Invoke-DevFleetE2EGuestLsa,Test-DevFleetE2EGuestCredential,Arm-DevFleetE2EInteractiveLogon,Restart-DevFleetE2EL1,Wait-DevFleetE2EInteractiveDesktop,Disarm-DevFleetE2EInteractiveLogon,Clear-DevFleetE2EInteractiveLogonState,Assert-DevFleetE2EInteractiveDesktop,Assert-DevFleetE2EInteractiveDesktopAfterDisarm,Get-DevFleetE2ERdpBaseline,Enable-DevFleetE2ERdp,Restore-DevFleetE2ERdp,Set-DevFleetE2ERdpCredential,Remove-DevFleetE2ERdpCredential

```


## FILE: automation/release-e2e/modules/MaintenanceVault.psm1

SHA256: 681caa846c0ce047db23a8a6ec5b2caf6aa5ab316ebb24f20a2f83b76c188da1 | Bytes: 28353 | Git mode: 100644

```
Set-StrictMode -Version Latest

# Qualification fixture only. This does not impersonate a Laptop transaction,
# change the installed Primary role, or award proof credit. The ordinary product
# Vault cloud-init/bootstrap and client configurator remain the implementation.
function Assert-MaintenanceVaultResult {
    param($Result,$Request)
    if([string]$Result.status-cne'PASS'){throw 'Configured Primary Vault prerequisite did not pass.'}
    if([string]$Result.payloadSha256-cne[string]$Request.payloadSha256){throw 'Vault fixture payload identity differs.'}
    if([string]$Result.primaryRole-cne'primary'-or[string]$Result.primaryName-cne[string]$Request.primaryName-or[string]$Result.vaultName-cne[string]$Request.vaultName){throw 'Vault fixture Primary/instance identity differs.'}
    foreach($key in @('primaryId','vaultId','deploymentId')){$id=[guid]::Empty;if(-not[guid]::TryParse([string]$Result.$key,[ref]$id)-or$id-eq[guid]::Empty){throw "Vault fixture $key is missing or invalid."}}
    if($Result.configurationPresent-isnot[bool]-or-not$Result.configurationPresent-or$Result.authenticatedTransport-isnot[bool]-or-not$Result.authenticatedTransport){throw 'Vault fixture lacks authenticated configuration.'}
    if($Result.proofCredit-isnot[bool]-or$Result.proofCredit){throw 'Vault prerequisite cannot award proof credit.'}
}

function Get-MaintenanceVaultControlRoot {
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $resolved=(Resolve-Path -LiteralPath $WorkspaceRoot).Path.ToLowerInvariant()
    $sha=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($resolved))
    $key=([Convert]::ToHexString($sha).ToLowerInvariant()).Substring(0,16)
    return Join-Path $env:LOCALAPPDATA ("DevFleet\ReleaseRunner-v9\"+$key)
}

function Protect-MaintenanceVaultPrivateFailureBytes {
    param(
        [Parameter(Mandatory)][byte[]]$Plaintext,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][guid]$VmId,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$RunDir,
        [string]$ControlRoot=''
    )
    if($Plaintext.Length-le0){throw 'Private failure evidence is empty.'}
    if(-not$ControlRoot){$ControlRoot=Get-MaintenanceVaultControlRoot -WorkspaceRoot $WorkspaceRoot}
    Add-Type -AssemblyName System.Security
    $entropy=[Text.Encoding]::UTF8.GetBytes("DevFleet exact failure evidence $RunId")
    $encrypted=[Security.Cryptography.ProtectedData]::Protect($Plaintext,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $privateDir=Join-Path $ControlRoot ("private-evidence\"+$RunId)
    [IO.Directory]::CreateDirectory($privateDir)|Out-Null
    $encryptedPath=Join-Path $privateDir 'private-product-operations.log.dpapi'
    [IO.File]::WriteAllBytes($encryptedPath,$encrypted)
    $roundTrip=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try{
        $roundTripVerified=$roundTrip.Length-eq$Plaintext.Length
        if($roundTripVerified){
            for($i=0;$i-lt$Plaintext.Length;$i++){if($roundTrip[$i]-ne$Plaintext[$i]){$roundTripVerified=$false;break}}
        }
        if(-not$roundTripVerified){throw 'Private failure DPAPI round-trip verification failed.'}
        $metadata=[ordered]@{
            schemaVersion=1;runId=$RunId;classification='ENCRYPTED_PRIVATE_FAILURE_EVIDENCE_PRESERVATION'
            sourceVmId=$VmId.ToString();sourcePath=$SourcePath;sourceBytes=$Plaintext.Length
            encryptedLocalPath=$encryptedPath;encryptedSha256=(Get-FileHash -LiteralPath $encryptedPath -Algorithm SHA256).Hash.ToLowerInvariant()
            encryption='Windows DPAPI CurrentUser';entropyDerivation='UTF8: DevFleet exact failure evidence plus space plus RunId'
            roundTripVerified=$true;plaintextWrittenToHost=$false;plaintextIncludedInAudit=$false
            sourceReadOnly=$true;runtimeRestarted=$false;observedAtUtc=[datetime]::UtcNow.ToString('o')
        }
        $metadataPath=Join-Path $RunDir 'private-failure-preservation.json'
        [IO.File]::WriteAllText($metadataPath,(($metadata|ConvertTo-Json -Depth 6)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        return [pscustomobject]$metadata
    } finally {
        if($roundTrip){[Array]::Clear($roundTrip,0,$roundTrip.Length)}
        if($encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
        if($entropy){[Array]::Clear($entropy,0,$entropy.Length)}
    }
}

function Save-MaintenanceVaultPrivateFailureEvidence {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RemoteRoot,
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][guid]$VmId
    )
    $sourcePath=Join-Path $RemoteRoot 'private-product-operations.log'
    $record=Invoke-DevFleetBoundedGuestCommand -Session $Session -ScriptBlock {
        param($Path)
        if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return [pscustomobject]@{present=$false}}
        $bytes=[IO.File]::ReadAllBytes($Path)
        try{[pscustomobject]@{present=$true;length=$bytes.Length;base64=[Convert]::ToBase64String($bytes)}}finally{if($bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
    } -ArgumentList @($sourcePath) -TimeoutSeconds 30
    if(-not[bool]$record.present){throw 'Private failure log was not present at the owned failure boundary.'}
    $plain=[Convert]::FromBase64String([string]$record.base64)
    $record.base64=$null
    try{
        if($plain.Length-ne[int]$record.length){throw 'Private failure log length changed during read-only preservation.'}
        return Protect-MaintenanceVaultPrivateFailureBytes -Plaintext $plain -RunId $RunId -VmId $VmId -SourcePath $sourcePath -WorkspaceRoot $WorkspaceRoot -RunDir $RunDir
    } finally {if($plain){[Array]::Clear($plain,0,$plain.Length)}}
}

function Write-MaintenanceVaultWindowsTailscaleSnapshot {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ExpectedHostname,
        [Parameter(Mandatory)][string]$RunDir
    )
    $snapshot=$null
    try{
        $snapshot=Invoke-DevFleetBoundedGuestCommand -Session $Session -ScriptBlock {
            param($Expected)
            $command=Get-Command tailscale.exe,tailscale -ErrorAction SilentlyContinue|Select-Object -First 1
            if(-not$command){return [pscustomobject][ordered]@{schemaVersion=1;status='UNAVAILABLE';commandPresent=$false;expectedHostname=$Expected}}
            $raw=& $command.Source status --json 2>$null
            if($LASTEXITCODE-ne0-or-not$raw){return [pscustomobject][ordered]@{schemaVersion=1;status='UNAVAILABLE';commandPresent=$true;expectedHostname=$Expected}}
            $status=$raw|ConvertFrom-Json
            $self=$status.Self
            $selfHostname=[string]$self.HostName
            [pscustomobject][ordered]@{
                schemaVersion=1;status='OBSERVED';commandPresent=$true;backendState=[string]$status.BackendState
                selfOnline=[bool]$self.Online;selfHostName=$selfHostname;expectedHostname=$Expected
                hostnameMatches=($selfHostname-ceq$Expected);tailscaleIpCount=@($status.TailscaleIPs).Count
                healthCount=@($status.Health).Count;observedUtc=[datetime]::UtcNow.ToString('o')
            }
        } -ArgumentList @($ExpectedHostname) -TimeoutSeconds 30
    } catch {
        $snapshot=[pscustomobject][ordered]@{schemaVersion=1;status='UNAVAILABLE';commandPresent=$null;expectedHostname=$ExpectedHostname;reason='read-only Tailscale status probe failed';observedUtc=[datetime]::UtcNow.ToString('o')}
    }
    $path=Join-Path $RunDir 'maintenance-vault-windows-tailscale-preflight.json'
    [IO.File]::WriteAllText($path,(($snapshot|ConvertTo-Json -Depth 6)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    return $snapshot
}

function Invoke-MaintenanceVaultProvisioning {
    param([Parameter(Mandatory)]$Request)
    if([string]$Request.runId-cnotmatch '\Afullrelease-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'-or[string]$Request.payloadSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'Vault fixture run/payload binding is invalid.'}
    $state=[ordered]@{}
    foreach($step in @('identity','launch','bootstrap','configure','verify')){
        if([datetime]::UtcNow-ge([datetime]$Request.ownerDeadlineUtc).ToUniversalTime()){throw 'Vault prerequisite owner deadline expired.'}
        $value=Invoke-MaintenanceVaultStep -Name $step -Request $Request -State $state
        if($step-ceq'identity'){
            if([string]$value.primaryRole-cne'primary'){throw 'Vault prerequisite requires the installed Primary role.'}
            if($value.existingVault-isnot[bool]-or$value.existingVault){throw 'Refusing to adopt or refresh an existing Vault in the prerequisite.'}
            $state.identity=$value
        } elseif($step-ceq'launch'){$state.vault=$value}
        elseif($step-ceq'verify'){Assert-MaintenanceVaultResult -Result $value -Request $Request;return $value}
    }
}

function Invoke-MaintenanceVaultStep {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)]$Request,[Parameter(Mandatory)]$State)
    # This function runs only in an exact-L1, separately bounded PS7 process.
    if($env:COMPUTERNAME-cne'DEVFLEET-E2E-01'-or$PSVersionTable.PSVersion.Major-lt7){throw 'Vault fixture is restricted to the approved disposable L1 PS7 runtime.'}
    $package=[string]$Request.packageRoot
    Import-Module (Join-Path $package 'windows/DevFleet.Common.psm1') -Scope Local -DisableNameChecking
    $config=Get-DevFleetConfig;$mp=Get-MultipassExe
    if([string]$config.Primary.InstanceName-cne[string]$Request.primaryName-or[string]$config.Vault.InstanceName-cne[string]$Request.vaultName){throw 'Installed configuration changed the approved fixture targets.'}
    $deadline=([datetime]$Request.ownerDeadlineUtc).ToUniversalTime()
    Set-DevFleetDeadlineContext -TransactionDeadlineUtc $deadline -StageName 'vault' -StageBudgetSeconds ([int]$Request.budgetSeconds)|Out-Null
    switch($Name){
        'identity' {
            $identity=Get-Content -LiteralPath (Join-Path (Get-DevFleetStateRoot) 'node-identity.json') -Raw|ConvertFrom-Json
            $primary=@(Get-VM -Name ([string]$Request.primaryName) -ErrorAction Stop)
            if($primary.Count-ne1){throw 'Primary immutable VM identity is ambiguous.'}
            $inventory=Invoke-External $mp @('list','--format','json') -Capture -TimeoutSeconds 60 -DeadlineUtc $deadline|ConvertFrom-Json
            $unexpected=@($inventory.list|Where-Object{[string]$_.name-cne[string]$Request.primaryName})
            $existing=@(Get-VM -ErrorAction Stop|Where-Object{$_.Id-ne$primary[0].Id})
            if($unexpected.Count-gt0-or$existing.Count-gt0){throw 'Refusing an existing Vault or unexpected nested instance.'}
            if(@($inventory.list|Where-Object{[string]$_.name-ceq[string]$Request.primaryName}).Count-ne1){throw 'Primary Multipass inventory is missing or ambiguous.'}
            Assert-MultipassIsolation -InstanceNames @([string]$Request.primaryName)
            return [pscustomobject]@{primaryRole=[string]$identity.node_role;primaryId=$primary[0].Id.ToString();deploymentId=[string]$identity.deployment_id;existingVault=$false}
        }
        'launch' {
            $v=$config.Vault
            $dependencyPolicy=Get-Content -LiteralPath (Join-Path $package 'linux/dependency-policy.json') -Raw|ConvertFrom-Json
            $key=[string]$dependencyPolicy.tailscale.signingKeySha256Fingerprint
            if($key-cnotmatch'^[A-F0-9]{40}$'){throw 'Candidate Vault cloud-init signing-key identity is invalid.'}
            $cloud=Join-Path ([string]$Request.workRoot) 'vault-cloud-init.yaml'
            $rendered=(Get-Content -LiteralPath (Join-Path $package 'cloud-init/vault.yaml') -Raw).Replace('__NODE_