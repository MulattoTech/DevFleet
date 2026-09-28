# DevFleet source part 032

Full-source UTF-8 byte interval [1441500, 1488000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: abc39804838a70384b5ced1ac97d68f9fff9a92e5699929152493fe77b7c6f12

<!-- BEGIN SOURCE SLICE -->
ng]$service.State -ne 'Running'){throw "Multipass service did not return to Running before the readiness deadline; state=$([string]$service.State)."}
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
        if(-not $infoReady -or [string]$instances[0].state -ceq 'Stopped'){
            $primaryVm=Get-ExactNestedPrimaryVm -ExpectedName $primary
            $primaryReadiness.hyperVStateBefore=$primaryVm.State.ToString()
            $readinessTrace.hyperVBefore=$primaryVm.State.ToString()
            if($primaryVm.State -ne 'Off'){& $VmStopProvider $primaryVm}
            & $VmStartProvider (& $VmLookupProvider -Id ([guid]$primaryVm.Id))|Out-Null
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

```


## FILE: automation/release-e2e/modules/executors/Invoke-RealUseAcceptance.py

SHA256: 80d79b63d6f5eb5f69d7ebb5cdf4d00c8c30f33084d3b7cbc480019bed45e31a | Bytes: 6345