# VM-free regression: pre-restart readiness cannot qualify post-restart state.
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
$readyBlock=Get-DevFleetNestedPrimaryReadinessScriptBlock
$originalComputerName=$env:COMPUTERNAME
$failures=[Collections.Generic.List[string]]::new()
try {
    $env:COMPUTERNAME='DEVFLEET-E2E-UNIT'
    foreach($case in @('stopped-stale-info','deadline-before-cycle','deadline-after-stop','late-info-ready')){
        $state=@{case=$case;clock=[datetime]'2026-09-29T00:00:00Z';infoCount=0;mutations=[Collections.Generic.List[string]]::new()}
        $probe={param($Arguments,$TimeoutSeconds)
            if($Arguments[0] -eq 'list'){
                if($state.case -eq 'deadline-before-cycle'){$state.clock=$state.clock.AddSeconds(30)}
                $text=if($state.case -eq 'stopped-stale-info'){'{"list":[{"name":"devfleet-primary","state":"Stopped"}]}'}else{'{"list":[{"name":"devfleet-primary","state":"Running"}]}'}
            }elseif($Arguments[0] -eq 'info'){
                $state.infoCount++
                if($state.case -eq 'deadline-before-cycle'){$state.clock=$state.clock.AddSeconds([int]$TimeoutSeconds)}
                if($state.case -eq 'late-info-ready'){$state.clock=$state.clock.AddSeconds(180)}
                $text=if($state.case -eq 'late-info-ready' -or ($state.case -eq 'stopped-stale-info' -and $state.infoCount -eq 1)){'IPv4: 10.0.0.2'}else{'IPv4: --'}
            }else{throw 'Unexpected transport operation in mocked test'}
            [pscustomobject]@{exitCode=0;stdout=@($text);stderr=@();output=@($text)}
        }.GetNewClosure()
        $lookup={param($Name,$Id)
            if($Name -and $state.case -eq 'deadline-before-cycle'){$state.clock=$state.clock.AddSeconds(60)}
            [pscustomobject]@{Name='devfleet-primary';Id=[guid]'11111111-1111-1111-1111-111111111111';State='Running'}
        }.GetNewClosure()
        $stop={param($Vm)$state.mutations.Add('stop');if($state.case -eq 'deadline-after-stop'){$state.clock=$state.clock.AddSeconds(180)}}.GetNewClosure()
        $start={param($Vm)$state.mutations.Add('start')}.GetNewClosure()
        $clock={$state.clock}.GetNewClosure()
        $sleep={param($Milliseconds)$state.clock=$state.clock.AddMilliseconds([int]$Milliseconds)}.GetNewClosure()
        $result=$null;$errorText=$null
        try {
            $result=& $readyBlock -Primary 'devfleet-primary' -MultipassPath 'C:\Program Files\Multipass\bin\multipass.exe' -NativeProbeProvider $probe -ControlPlaneRecoveryProvider {throw 'Unexpected recovery in mocked test'} -VmLookupProvider $lookup -VmStopProvider $stop -VmStartProvider $start -ClockProvider $clock -SleepProvider $sleep
        }catch{$errorText=$_.Exception.Message}
        $problem=$null
        if($case -eq 'stopped-stale-info'){
            if($result -and $result.ready){$problem='Pre-restart info was accepted as post-restart readiness'}
            elseif(-not $errorText -or $state.infoCount -lt 2){$problem='Post-restart readiness was not re-observed'}
            elseif(($state.mutations -join '|') -cne 'stop|start'){$problem='Exact recovery sequence changed'}
        }elseif($case -eq 'deadline-after-stop'){
            if(($state.mutations -join '|') -cne 'stop'){$problem='Nested VM restarted after stop consumed the owner deadline'}
            elseif(-not $errorText){$problem='Expired owner deadline after stop was not rejected'}
        }else{
            if($result -and $result.ready){$problem='Info first observed at the cutoff was accepted as ready'}
            elseif($state.mutations.Count){$problem='Nested VM mutated after the fixed readiness deadline'}
            elseif(-not $errorText){$problem='Expired owner deadline was not rejected'}
        }
        if($problem){$failures.Add($case+': '+$problem);Write-Host ('FAIL '+$case+': '+$problem)}
        else{Write-Host ('PASS '+$case)}
    }
}finally{$env:COMPUTERNAME=$originalComputerName}
if($failures.Count){throw ($failures -join '; ')}
Write-Host 'PASS 4 readiness freshness/deadline cases; all VM/transport I/O mocked; no native credit'
