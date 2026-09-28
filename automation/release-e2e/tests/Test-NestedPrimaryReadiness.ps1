$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
$readyBlock=Get-DevFleetNestedPrimaryReadinessScriptBlock
$originalComputerName=$env:COMPUTERNAME
$checks=0
try {
    $env:COMPUTERNAME='DEVFLEET-E2E-UNIT'
    foreach($case in @('ready','inventory-timeout','inventory-timeout-forced','inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid','control-plane-recovery-failure','info-unready','info-timeout-exhausted','wrong-instance','malformed-inventory','wrong-immutable-id','wrong-host')){
        $multipassPath=Join-Path $env:ProgramFiles 'Multipass/bin/multipass.exe'
        $multipassDaemon=Join-Path (Split-Path -Parent $multipassPath) 'multipassd.exe'
        $state=@{case=$case;calls=[Collections.Generic.List[string]]::new();probes=[Collections.Generic.List[object]]::new();mutations=[Collections.Generic.List[string]]::new();serviceControls=[Collections.Generic.List[string]]::new();daemonStops=[Collections.Generic.List[int]]::new();serviceState='Running';servicePid=42;clock=[datetime]'2026-09-22T14:18:29Z';infoCount=0;listCount=0}
        $probe={param($Arguments,$TimeoutSeconds)
            $operation=[string]$Arguments[0];$state.calls.Add($operation);$state.probes.Add([pscustomobject]@{operation=$operation;timeoutSeconds=[int]$TimeoutSeconds})
            if($operation -eq 'list'){
                $state.listCount++
                if($state.case -in @('inventory-timeout','inventory-timeout-forced','inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid','control-plane-recovery-failure','wrong-immutable-id') -and $state.listCount -eq 1){throw 'native inventory TIMEOUT'}
                $stdout=if($state.case -eq 'malformed-inventory'){'not-json'}elseif($state.case -eq 'wrong-instance'){'{"list":[{"name":"foreign","state":"Running"}]}'}else{'{"list":[{"name":"devfleet-primary","state":"Running"}]}'}
            }elseif($operation -eq 'info'){
                $state.infoCount++
                if($state.case -eq 'info-timeout-exhausted' -and $state.infoCount -gt 1){$state.clock=$state.clock.AddSeconds([int]$TimeoutSeconds);throw "Nested Multipass operation timed out after $TimeoutSeconds seconds: info devfleet-primary"}
                $stdout=if($state.case -in @('info-unready','wrong-immutable-id') -and $state.infoCount -eq 1){'IPv4: --'}else{'IPv4: 10.0.0.2'}
                if($state.case -eq 'info-timeout-exhausted'){$stdout='IPv4: --'}
            }else{throw 'Readiness attempted an unexpected operation'}
            [pscustomobject]@{exitCode=0;stdout=@($stdout);stderr=@();output=@($stdout)}
        }.GetNewClosure()
        $lookup={param($Name,$Id)
            [pscustomobject]@{Name='devfleet-primary';Id=if($Id -and $state.case -eq 'wrong-immutable-id'){[guid]'22222222-2222-2222-2222-222222222222'}else{[guid]'11111111-1111-1111-1111-111111111111'};State='Running'}
        }.GetNewClosure()
        $stop={param($Vm)if($Vm.Id -ne [guid]'11111111-1111-1111-1111-111111111111'){throw 'Wrong exact stop target'};$state.mutations.Add('stop')}.GetNewClosure()
        $start={param($Vm)if($Vm.Id -ne [guid]'11111111-1111-1111-1111-111111111111'){throw 'Wrong exact start target'};$state.mutations.Add('start')}.GetNewClosure()
        $serviceLookup={
            if($state.case -eq 'control-plane-recovery-failure'){throw 'controlled Multipass service recovery failure'}
            [pscustomobject]@{Name='Multipass';State=$state.serviceState;ProcessId=$state.servicePid;PathName="`"$multipassDaemon`"";StartName='LocalSystem'}
        }.GetNewClosure()
        $serviceControl={param($Action)
            $state.serviceControls.Add([string]$Action)
            if($Action -eq 'stop'){$state.serviceState=if($state.case -in @('inventory-timeout-forced','inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid')){'Stop Pending'}else{'Stopped'}}
            elseif($Action -eq 'start'){$state.serviceState='Running'}else{throw 'Unexpected service control action'}
        }.GetNewClosure()
        $daemonLookup={param($Id)if($Id -ne 42 -and -not($Id -eq 43 -and $state.case -in @('inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path'))){throw 'Wrong daemon PID'};[pscustomobject]@{ProcessName='multipassd';Path=if($Id -eq 43 -and $state.case -eq 'inventory-timeout-auto-restart-wrong-path'){'C:\Untrusted\multipassd.exe'}else{$multipassDaemon}}}.GetNewClosure()
        $daemonStop={param($Id)if($Id -ne 42){throw 'Wrong daemon stop PID'};$state.daemonStops.Add([int]$Id);$state.serviceState=if($state.case -in @('inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid')){'Running'}else{'Stopped'};if($state.case -in @('inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path')){$state.servicePid=43}}.GetNewClosure()
        $clock={$state.clock}.GetNewClosure()
        $sleep={param($Milliseconds)$state.clock=$state.clock.AddMilliseconds([int]$Milliseconds)}.GetNewClosure()
        $recoverArgs=@{
            ServiceLookupProvider=$serviceLookup;ServiceControlProvider=$serviceControl;DaemonLookupProvider=$daemonLookup;DaemonStopProvider=$daemonStop;ClockProvider=$clock;SleepProvider=$sleep
        }
        if($case -eq 'wrong-host'){$env:COMPUTERNAME=$originalComputerName}
        $failure=$null;$result=$null
        try{$result=& $readyBlock -Primary 'devfleet-primary' -MultipassPath $multipassPath -NativeProbeProvider $probe -VmLookupProvider $lookup -VmStopProvider $stop -VmStartProvider $start @recoverArgs}catch{$failure=$_.Exception.Message}
        $expectedFailure=$case -in @('inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid','control-plane-recovery-failure','info-timeout-exhausted','wrong-instance','malformed-inventory','wrong-immutable-id','wrong-host')
        if($expectedFailure){
            if(-not $failure -or ($case -ne 'info-timeout-exhausted' -and $state.mutations.Count)){throw "Readiness did not fail closed without mutation: $case"}
        }else{
            if($failure -or -not $result.ready -or $state.listCount -lt 1 -or $state.infoCount -lt 1){throw "Readiness bypassed inventory/info: $case / $failure"}
            $expectedMutations=if($case -eq 'info-unready'){'stop|start'}else{''}
            if(($state.mutations -join '|') -cne $expectedMutations){throw "Exact recovery sequence changed: $case"}
        }
        $expectedServiceControls=if($case -in @('inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid')){'stop'}elseif($case -in @('inventory-timeout','inventory-timeout-forced','wrong-immutable-id')){'stop|start'}else{''}
        if(($state.serviceControls -join '|') -cne $expectedServiceControls){throw "Control-plane recovery cardinality changed: $case"}
        $expectedDaemonStops=if($case -in @('inventory-timeout-forced','inventory-timeout-auto-restart','inventory-timeout-auto-restart-wrong-path','inventory-timeout-reused-pid')){1}else{0}
        if($state.daemonStops.Count -ne $expectedDaemonStops){throw "Forced daemon recovery changed: $case"}
        if($case -in @('inventory-timeout','inventory-timeout-forced','inventory-timeout-auto-restart') -and ([string]$result.controlPlaneRecovery.status -cne 'PASS' -or $state.listCount -ne 2 -or [bool]$result.controlPlaneRecovery.forcedDaemonTermination -ne ($case -ne 'inventory-timeout'))){throw 'Inventory timeout did not recover the real control-plane path and re-probe inventory before guest mutation'}
        if($case -eq 'inventory-timeout-reused-pid' -and $failure -cnotmatch 'exact daemon PID'){throw 'Recovery accepted a Running service without a new exact daemon PID'}
        if($case -eq 'inventory-timeout-auto-restart-wrong-path' -and $failure -cnotmatch 'trusted daemon identity'){throw 'Recovery accepted a daemon outside the trusted installation'}
        if(@($state.probes|Where-Object{$_.operation -eq 'list' -and $_.timeoutSeconds -gt 30}).Count){throw "Inventory probe escaped its 30-second child bound: $case"}
        if($result -and $result.controlPlaneRecovery -and [datetime]$result.controlPlaneRecovery.ownerDeadlineUtc -ne [datetime]'2026-09-22T14:21:29Z'){throw "Control-plane recovery widened or replaced the 180-second owner deadline: $case"}
        if($state.clock -gt [datetime]'2026-09-22T14:21:29Z'){throw "Readiness exceeded the 180-second owner deadline: $case"}
        if($case -eq 'control-plane-recovery-failure' -and $failure -cnotmatch 'controlled Multipass service recovery failure'){throw 'Control-plane recovery failure lost its primary cause'}
        if($case -eq 'wrong-host' -and $state.calls.Count){throw 'Readiness called transport on the physical host'}
        if($case -eq 'info-timeout-exhausted' -and ($state.mutations -join '|') -cne 'stop|start'){throw 'Timeout scenario did not retain exact nested VM recovery'}
        if($case -eq 'info-timeout-exhausted' -and $failure -cnotmatch 'READINESS_TRACE:.*inventory=PASS.*hyperVBefore=Running.*infoTimeouts=[1-9]'){throw 'Timeout failure did not retain sanitized readiness trace'}
        if($case -eq 'info-timeout-exhausted' -and $failure -cmatch 'Last info:|IPv4:|10\.0\.0\.2'){throw 'Timeout failure leaked raw nested info output'}
        $checks++;Write-Host "PASS $case"
    }
}finally{$env:COMPUTERNAME=$originalComputerName}
Write-Host "PASS $checks shared nested readiness cases; all VM/transport I/O mocked; no VM mutation"
