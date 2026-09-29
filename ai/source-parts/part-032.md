# DevFleet source part 032

Full-source UTF-8 byte interval [1441500, 1488000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: f5b08713aa08583ff1b40d4dfbb8d8622524ac092fd2d096548b59abfcbbcbec

<!-- BEGIN SOURCE SLICE -->
w "Dependency policy scenario did not prove its intended branch: $($row.scenario)."}
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
    return [ordered]@{status='REAL E2E PASS';phase='WINDOWS-SENTINELS';contract='foreign-task-service-firewall-registry-file-surviv