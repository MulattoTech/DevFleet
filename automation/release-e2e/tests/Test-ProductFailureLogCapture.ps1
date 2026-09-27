[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
Import-Module (Join-Path $repo 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
$module=Get-Module Invoke-RealProductPhase
$tempParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$root=Join-Path $tempParent ('devfleet-failure-logs-'+[guid]::NewGuid().ToString('N'))
$results=[Collections.Generic.List[object]]::new()
try {
    New-Item -ItemType Directory -Path (Join-Path $root 'DevFleet'),(Join-Path $root 'M-TechLabs/DevFleet/Logs')|Out-Null
    & $module {
        param($FixtureRoot)
        $script:FailureLogFixtureRoot=$FixtureRoot
        # Replace only the remoting boundary; execute the production collector
        # in a real bounded child against an isolated filesystem fixture.
        function script:Invoke-Command {
            param($Session,$ScriptBlock,$ArgumentList,[switch]$AsJob)
            if(-not $AsJob){throw 'Fixture expected a bounded asynchronous collector.'}
            Start-Job -ScriptBlock {
                param($Root,$Body,$Arguments,$Delay)
                $env:ProgramData=$Root
                if($Delay){Start-Sleep -Seconds 8}
                & ([scriptblock]::Create($Body)) @Arguments
            } -ArgumentList $script:FailureLogFixtureRoot,$ScriptBlock.ToString(),$ArgumentList,([string]$Session -eq 'timeout')
        }
    } $root
    $active = Join-Path $root 'DevFleet/active-transaction.json'
    $log = Join-Path $root 'M-TechLabs/DevFleet/Logs/setup-fixture.log'
    $pairingLog = Join-Path $root ("M-TechLabs/DevFleet/Logs/setup-tailscale-pairing-$('a' * 32).log")
    $since=[datetime]::UtcNow.AddMinutes(-1).ToString('o')
    $requestTransactionId = 'a' * 32
    $requestPayloadSha256 = 'b' * 64
    foreach($case in @('sanitized','wrong-transaction','wrong-payload','stale','timeout','no-time')) {
        $activeTransactionId = if ($case -eq 'wrong-transaction') { 'c' * 32 } else { $requestTransactionId }
        $activePayloadSha256 = if ($case -eq 'wrong-payload') { 'd' * 64 } else { $requestPayloadSha256 }
        [ordered]@{ transactionId = $activeTransactionId; payloadSha256 = $activePayloadSha256 } | ConvertTo-Json | Set-Content -LiteralPath $active
        @('old fixture detail',('x' * 20000),'IndentationError: unexpected indent','AdminPassword="private multiword value"','Bearer private-token','final ordinary failure') | Set-Content -LiteralPath $log
        $pairingLines = @(
            '{"schemaVersion":1,"eventSequence":1,"eventClass":"PAIRING_STARTED","authenticatedState":"NOT_OBSERVED"}',
            '{"schemaVersion":1,"eventSequence":2,"eventClass":"URI_VALIDATED","uriValidated":true,"authenticatedState":"NOT_AUTHENTICATED"}',
            '{"schemaVersion":1,"eventSequence":3,"eventClass":"BROWSER_LAUNCH_REQUESTED","browserLaunchRequested":true,"authenticatedState":"NOT_AUTHENTICATED"}',
            '{"schemaVersion":1,"eventSequence":4,"eventClass":"BROWSER_LAUNCH_ACCEPTED","browserLaunchApiAccepted":true,"browserProcessObserved":true,"browserProcessSessionId":1,"browserSessionMatchesOwner":true}',
            '{"schemaVersion":1,"eventSequence":5,"eventClass":"PAIRING_WAIT_ENTERED","authenticatedState":"WAITING_FOR_AUTHENTICATION"}',
            '{"schemaVersion":1,"eventSequence":6,"eventClass":"PAIRING_FAILED","failureClass":"OWNER_DEADLINE_EXPIRED","authenticatedState":"NOT_AUTHENTICATED"}'
        )
        $pairingLines | Set-Content -LiteralPath $pairingLog
        if ($case -eq 'stale') {
            $oldTime = [datetime]::UtcNow.AddHours(-1)
            (Get-Item -LiteralPath $log).LastWriteTimeUtc = $oldTime
            (Get-Item -LiteralPath $pairingLog).LastWriteTimeUtc = $oldTime
        }
        $timeoutSeconds = if ($case -eq 'timeout') { 1 } elseif ($case -eq 'no-time') { 0 } else { 10 }
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $snapshot = & $module {
            param($s, $start, $budget, $tx, $payload)
            Get-ProductFailureLogSnapshot -Session $s -TransactionId $tx -PayloadSha256 $payload -InvocationStartUtc $start -TimeoutSeconds $budget
        } $case $since $timeoutSeconds $requestTransactionId $requestPayloadSha256
        $watch.Stop()
        $ordinaryRecord = @($snapshot.records | Where-Object { $_.name -eq 'setup-fixture.log' } | Select-Object -First 1)
        $pairingRecord = @($snapshot.records | Where-Object { $_.name -eq [IO.Path]::GetFileName($pairingLog) } | Select-Object -First 1)
        if ($case -eq 'sanitized') {
            $serialized = $snapshot | ConvertTo-Json -Depth 8
            $pass = $snapshot.status -eq 'OBSERVED' -and $ordinaryRecord.Count -eq 1 -and $ordinaryRecord[0].tail -match 'IndentationError' -and $ordinaryRecord[0].tail.Length -le 16384 -and $pairingRecord.Count -eq 1 -and $pairingRecord[0].tail -match 'PAIRING_STARTED' -and $pairingRecord[0].tail -match 'BROWSER_LAUNCH_ACCEPTED' -and $pairingRecord[0].tail -match 'PAIRING_FAILED' -and $pairingRecord[0].tailOnly -eq $false -and $pairingRecord[0].headLineLimit -eq 32 -and $serialized -notmatch 'private multiword|private-token'
        } elseif ($case -eq 'stale') {
            $pass = $snapshot.status -eq 'NO_RECENT_LOG' -and $snapshot.records.Count -eq 0
        } else {
            $pass = $snapshot.status -eq 'UNAVAILABLE' -and $snapshot.records.Count -eq 0
        }
        if ($case -eq 'timeout') { $pass = $pass -and $watch.Elapsed.TotalSeconds -lt 7 }
        $results.Add(@{ case = $case; pass = [bool]$pass; status = $snapshot.status; elapsedSeconds = [math]::Round($watch.Elapsed.TotalSeconds, 2) })
    }
    @{transactionId=('a'*32);payloadSha256=('b'*64)}|ConvertTo-Json|Set-Content -LiteralPath $active
    'IndentationError: unexpected indent'|Set-Content -LiteralPath $log
    $remote={param($s) [pscustomobject]@{terminalFailure=$false;stageMarkers=@();stageMarkerErrors=@();progress=@{checkpointState='';productChildInstances=@()};timestampUtc=[datetime]::UtcNow.ToString('o')}}
    $marker={param($s)
        $reads=@(foreach($target in $s.targets){
            $value=@{schemaVersion=1;transactionId=$s.transactionId;payloadSha256=$s.payloadSha256;sequence=16;component=if($target.kind-eq'vault'){'serviceConfiguration'}else{'serviceAndFirewallFinalization'};state='FAILED';updatedUtc=[datetime]::UtcNow.ToString('o');packageVersion=if($target.kind-eq'vault'){'vault'}else{'1.2.13'};nodeRole=$target.nodeRole}
            [pscustomobject]@{instanceName=$target.instanceName;text=($value|ConvertTo-Json -Compress);exitCode=0;timedOut=$false}
        })
        [pscustomobject]@{status='READS_COLLECTED';error='';inventoryExitCode=0;probedInstances=@($s.targets.instanceName);markerReads=$reads}
    }
    foreach($entry in @(@{role='Primary / Desktop';capture='OBSERVED'},@{role='Laptop / Surrogate';capture='OBSERVED'},@{role='Primary / Desktop';capture='UNAVAILABLE'})){
        $role=$entry.role
        if($entry.capture-eq'UNAVAILABLE'){@{transactionId=('c'*32);payloadSha256=('b'*64)}|ConvertTo-Json|Set-Content -LiteralPath $active}
        $observation=& $module {
            param($Role,$Remote,$Marker,$Since)
            $p=@{Session='fixture';TransactionId=('a'*32);PayloadSha256=('b'*64);Role=$Role;ExpectedDevFleetVersion='1.2.13';ExpectedInstallerVersion='1.4.1';InvocationStartUtc=$Since;ObservationTimeoutSeconds=20;ExpectedNestedLinuxName='DevFleet-E2E-Linux-01';RemoteObservationProvider=$Remote;GuestMarkerReadProvider=$Marker}
            $p.ExpectedComputeInstanceName=if($Role-eq'Primary / Desktop'){'devfleet-primary'}else{'devfleet-failover'}
            if($Role-eq'Laptop / Surrogate'){$p.ExpectedVaultInstanceName='devfleet-vault'}
            Get-ProductLifecycleObservation @p
        } $role $remote $marker $since
        $pass=$observation.terminalFailure-and$observation.terminalReason-match'reported FAILED'-and$observation.failureLogSnapshot.status-eq$entry.capture
        if($entry.capture-eq'OBSERVED'){$pass=$pass-and$observation.failureLogSnapshot.records[0].tail-match'IndentationError'}else{$pass=$pass-and$observation.failureLogSnapshot.records.Count-eq0}
        $results.Add(@{case=$role+' terminal observer capture '+$entry.capture;pass=[bool]$pass;status=$observation.failureLogSnapshot.status})
        $summaryPath=Join-Path $root ('wait-'+$results.Count+'/observer.json')
        $waited=& $module {
            param($Observation,$Role,$Evidence,$Since)
            Wait-DevFleetProductLifecycleTransition -Session 'fixture' -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role $Role -BudgetSeconds 15 -PollSeconds 1 -ObservationTimeoutSeconds 10 -InvocationStartUtc $Since -EvidencePath $Evidence -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ObservationProvider {param($s) $s.providerContext} -ObservationProviderContext $Observation
        } $observation $role $summaryPath $since
        $saved=Get-Content -LiteralPath $summaryPath -Raw|ConvertFrom-Json
        $journal=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $summaryPath) 'product-lifecycle-progress.jsonl') -Raw
        $pass=$waited.outcome-eq'TERMINAL_FAILURE'-and$saved.observation.failureLogSnapshot.status-eq$entry.capture-and$journal-match'failureLogSnapshot'
        $results.Add(@{case=$role+' wait journal retains '+$entry.capture;pass=[bool]$pass;status=$waited.outcome})
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if([IO.Path]::GetDirectoryName($resolved)-cne$tempParent-or[IO.Path]::GetFileName($resolved)-notmatch'^devfleet-failure-logs-[0-9a-f]{32}$'){throw 'Fixture cleanup escaped its owner boundary.'}
    if(Test-Path -LiteralPath $resolved){if((Get-Item -LiteralPath $resolved).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Fixture root is a reparse point.'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}
$results|ConvertTo-Json -Depth 4
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Product failure-log capture qualification failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) native failure-log capture checks"
