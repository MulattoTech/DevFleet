[CmdletBinding()]
param([string]$PythonPath='python.exe',[string]$FixtureRoot,[string]$ReportPath)
$ErrorActionPreference='Stop'
$WarningPreference='SilentlyContinue'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if(-not $FixtureRoot){
    $tempParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $root=Join-Path $tempParent ('devfleet-health-test-'+[guid]::NewGuid().ToString('N'))
    $server=$null
    try {
        New-Item -ItemType Directory -Path (Join-Path $root 'DevFleetHostAgent')|Out-Null
        # Windows ProgramData is hidden. Preserve that real filesystem behavior
        # in the fixture instead of testing only a visible temporary directory.
        [IO.File]::SetAttributes($root,([IO.File]::GetAttributes($root)-bor[IO.FileAttributes]::Hidden))
        Copy-Item -LiteralPath (Join-Path $repo 'source/windows/DevFleet-HostAgentProtocol.psm1') -Destination (Join-Path $root 'DevFleetHostAgent/DevFleet-HostAgentProtocol.psm1')
        [IO.File]::WriteAllText((Join-Path $root 'DevFleetHostAgent/token.txt'),('x'*48))
        [IO.File]::WriteAllText((Join-Path $root 'case.txt'),'healthy')
        $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=(Get-Command $PythonPath -ErrorAction Stop).Source;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
        foreach($arg in @((Join-Path $PSScriptRoot 'fixtures/host-health-server.py'),$root)){[void]$psi.ArgumentList.Add($arg)}
        $server=[Diagnostics.Process]::Start($psi)
        $until=[datetime]::UtcNow.AddSeconds(10)
        while(-not(Test-Path -LiteralPath (Join-Path $root 'port.txt'))-and[datetime]::UtcNow-lt$until-and-not$server.HasExited){Start-Sleep -Milliseconds 100}
        if(-not(Test-Path -LiteralPath (Join-Path $root 'port.txt'))){throw 'Owned fixture server did not become ready.'}
        $reports=@()
        foreach($engine in @('powershell.exe','pwsh.exe')){
            $output=Join-Path $root ($engine+'.json')
            & $engine -NoProfile -File $PSCommandPath -FixtureRoot $root -ReportPath $output
            if($LASTEXITCODE-ne0){throw "Native authenticated health tests failed under $engine."}
            $reports+=Get-Content -Raw -LiteralPath $output|ConvertFrom-Json
        }
        if($ReportPath){$reports|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $ReportPath}
        Write-Host "PASS $(($reports|Measure-Object passed -Sum).Sum)/$(($reports|Measure-Object total -Sum).Sum) native authenticated health checks"
    } finally {
        if($server){if(-not$server.HasExited){$server.Kill();[void]$server.WaitForExit(5000)};$server.Dispose()}
        $resolved=[IO.Path]::GetFullPath($root)
        if([IO.Path]::GetDirectoryName($resolved)-cne$tempParent-or[IO.Path]::GetFileName($resolved)-notmatch'^devfleet-health-test-[0-9a-f]{32}$'){throw 'Fixture cleanup escaped its owner.'}
        if(Test-Path -LiteralPath $resolved){if((Get-Item -LiteralPath $resolved -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Fixture cleanup root is a reparse point.'};Remove-Item -LiteralPath $resolved -Recurse -Force}
    }
    return
}
Import-Module (Join-Path $repo 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
$module=Get-Module Invoke-RealProductPhase
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$results.Add([pscustomobject]@{case=$Name;pass=$Pass})}
& $module {
    param($Root)
    $script:HealthFixtureRoot=$Root;$script:HealthFixturePort=[int](Get-Content (Join-Path $Root 'port.txt'))
    $script:HealthFixtureHash=(Get-FileHash (Join-Path $Root 'DevFleetHostAgent/DevFleet-HostAgentProtocol.psm1')).Hash.ToLowerInvariant()
    $script:HealthFixtureCalls=0;$script:HealthFixtureMalformed=''
    # Replace the remoting/process boundary only. The real production helper,
    # bounded child process, installed protocol and authentication all execute.
    function script:Invoke-DevFleetBoundedGuestProcess {
        param($Session,$FilePath,$ArgumentList,$OwnerDeadlineUtc)
        $script:HealthFixtureCalls++;$script:HealthFixtureLastBudget=($OwnerDeadlineUtc-[datetime]::UtcNow).TotalSeconds
        if($script:HealthFixtureMalformed){
            $v=@{ok=$true;reasonCode='AUTHENTICATED_HEALTH_OK';runtimeVersion='7.6.5';protocolSha256=$script:HealthFixtureHash;requestAttempted=$true;responseAuthenticated=$true}
            switch($script:HealthFixtureMalformed){
                'string-boolean' {$v.ok='false'}
                'unauthenticated-success' {$v.responseAuthenticated=$false}
                'foreign-protocol' {$v.protocolSha256='0'*64}
                'old-runtime' {$v.runtimeVersion='5.1'}
            }
            return [pscustomobject]@{outcome='PASS';outputComplete=if($script:HealthFixtureMalformed-eq'string-completeness'){'false'}else{$script:HealthFixtureMalformed-ne'truncated-process'};stdout=($v|ConvertTo-Json -Compress)}
        }
        if($FilePath-cne'C:\Program Files\PowerShell\7\pwsh.exe'-or$ArgumentList.Count-ne4-or$ArgumentList[0]-cne'-NoProfile'-or$ArgumentList[1]-cne'-NonInteractive'-or$ArgumentList[2]-cne'-EncodedCommand'){throw 'Production health client launch contract changed.'}
        $body=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[3]))
        if($body.Contains('x'*48)){throw 'Synthetic secret escaped into process arguments.'}
        $body=$body.Replace('http://127.0.0.1:8790/healthz',('http://127.0.0.1:'+$script:HealthFixturePort+'/healthz'))
        $body='$env:ProgramData='''+$script:HealthFixtureRoot.Replace("'","''")+''';'+$body
        $args=@('-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body)))
        $json=@{filePath=$FilePath;arguments=$args;deadlineUnixMilliseconds=([DateTimeOffset]$OwnerDeadlineUtc).ToUnixTimeMilliseconds()}|ConvertTo-Json -Compress
        & (Get-DevFleetBoundedProcessScriptBlock) $json
    }
} $FixtureRoot
foreach($case in @('healthy','bad-signature','wrong-host','unauthorized','not-ok','string-health','timeout','process-deadline','protocol-mismatch','expired-deadline')){
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'case.txt'),$(if($case-eq'process-deadline'){'timeout'}else{$case}))
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $v=& $module {param($Case)
        $hash=if($Case-eq'protocol-mismatch'){'0'*64}else{$script:HealthFixtureHash}
        $deadline=[datetime]::UtcNow.AddSeconds($(if($Case-eq'expired-deadline'){-1}elseif($Case-eq'process-deadline'){1}else{8}))
        Invoke-ProductAuthenticatedHealthProbe -Session 'local-fixture' -ProtocolSha256 $hash -OwnerDeadlineUtc $deadline
    } $case
    $watch.Stop()
    $pass=if($case-eq'healthy'){$v.ok-and$v.responseAuthenticated-and$v.runtimeVersion-like'7.*'}else{-not$v.ok}
    if($case-in@('protocol-mismatch','expired-deadline')){$pass=$pass-and-not$v.requestAttempted}
    if($case-in@('not-ok','string-health')){$pass=$pass-and$v.responseAuthenticated}
    Check $case ($pass-and$watch.Elapsed.TotalSeconds-lt9-and($v|ConvertTo-Json)-notmatch('x'*48))
}
$late=& $module {
    Invoke-ProductAuthenticatedHealthProbe -Session 'fixture' -ProtocolSha256 $script:HealthFixtureHash -OwnerDeadlineUtc ([datetime]::UtcNow.AddMilliseconds(100)) -ProcessProvider {
        param($request)
        Start-Sleep -Milliseconds 150
        [pscustomobject]@{outcome='PASS';outputComplete=$true;stdout=(@{ok=$true;reasonCode='AUTHENTICATED_HEALTH_OK';runtimeVersion='7.6.5';protocolSha256=$script:HealthFixtureHash;requestAttempted=$true;responseAuthenticated=$true}|ConvertTo-Json -Compress)}
    }
}
Check 'late complete envelope cannot earn health success' (-not$late.ok)
foreach($reportedHash in @('',('f'*64))){
    $failure=& $module {
        param($ReportedHash)
        $script:HealthFixtureFailureHash=$ReportedHash
        Invoke-ProductAuthenticatedHealthProbe -Session 'fixture' -ProtocolSha256 $script:HealthFixtureHash -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(5)) -ProcessProvider {
            [pscustomobject]@{outcome='PASS';outputComplete=$true;stdout=(@{ok=$false;reasonCode='AUTHENTICATED_HEALTH_UNAVAILABLE';runtimeVersion='7.6.5';protocolSha256=$script:HealthFixtureFailureHash;requestAttempted=$false;responseAuthenticated=$false;failureType='System.IO.IOException';failureId=('ItemNotFound,Microsoft.PowerShell.Commands.GetItemCommand'+[char]10+'<script>'+('x'*200))}|ConvertTo-Json -Compress)}
        }
    } $reportedHash
    Check ('pre-request error survives unverified hash '+$(if($reportedHash){'foreign'}else{'empty'})) (-not$failure.ok-and-not$failure.requestAttempted-and-not$failure.responseAuthenticated-and$failure.protocolSha256-ceq(&$module{$script:HealthFixtureHash})-and$failure.failureId.StartsWith('ItemNotFound,Microsoft.PowerShell.Commands.GetItemCommand')-and$failure.failureId.Length-eq160-and$failure.failureId-notmatch'[<>\r\n]')
}
foreach($case in @('string-boolean','unauthenticated-success','foreign-protocol','old-runtime','truncated-process','string-completeness')){
    $v=& $module {param($Case)$script:HealthFixtureMalformed=$Case;Invoke-ProductAuthenticatedHealthProbe -Session 'fixture' -ProtocolSha256 $script:HealthFixtureHash -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(5))} $case
    Check $case (-not$v.ok)
}
& $module {$script:HealthFixtureMalformed=''}
[IO.File]::WriteAllText((Join-Path $FixtureRoot 'case.txt'),'healthy')
foreach($case in @('complete','no-time','missing-receipt','wrong-role','terminal','checkpoint')){
    $v=& $module {
        param($Case)
        $o=[ordered]@{terminalFailure=($Case-eq'terminal');checkpointPresent=($Case-eq'checkpoint');installStateValid=$true;canonicalOwnershipValid=$true;matchingConsumedReceipt=($Case-ne'missing-receipt');productRoleIdentityValid=($Case-ne'wrong-role');authenticatedHealthOk=$false;progress=@{health=$false}}
        $before=$script:HealthFixtureCalls
        $result=Add-ProductAuthenticatedHealthObservation -Observation $o -Session 'fixture' -RemainingSeconds $(if($Case-eq'no-time'){10}else{25})
        [pscustomobject]@{observation=$result;calls=($script:HealthFixtureCalls-$before);budget=$script:HealthFixtureLastBudget}
    } $case
    $pass=if($case-eq'complete'){$v.calls-eq1-and$v.observation.authenticatedHealthOk-and$v.observation.progress.health-and($v.observation.progressMarker|ConvertFrom-Json).health-and$v.budget-le8}else{$v.calls-eq0-and-not$v.observation.authenticatedHealthOk}
    Check ('identity/deadline '+$case) $pass
}
# Exercise the real Get-ProductLifecycleObservation call site, including marker
# attachment, rather than only calling the health helper in isolation.
& $module {
    function script:Invoke-Command {
        param($Session,$ScriptBlock,$ArgumentList,[switch]$AsJob)
        if(-not$AsJob-or$ScriptBlock.ToString().Contains('Invoke-HostAgentAuthenticatedJson')){throw 'Observation attempted the PS5.1 health call or an unbounded remote read.'}
        Start-Job -ScriptBlock {
            [ordered]@{checkpointPresent=$false;checkpoint=$null;terminalFailure=$false;installStateValid=$true;canonicalOwnershipValid=$true;matchingConsumedReceipt=$true;authenticatedHealthOk=$false;stageMarkers=@();stageMarkerErrors=@();progress=@{health=$false;productChildInstances=@()};timestampUtc=[datetime]::UtcNow.ToString('o')}
        }
    }
}
$marker={param($s)
    $reads=@(foreach($target in $s.targets){
        $value=@{schemaVersion=1;transactionId=$s.transactionId;payloadSha256=$s.payloadSha256;sequence=17;component='bootstrap';state='COMPLETED';updatedUtc=[datetime]::UtcNow.ToString('o');packageVersion=if($target.kind-eq'vault'){'vault'}else{'1.2.13'};nodeRole=$target.nodeRole}
        [pscustomobject]@{instanceName=$target.instanceName;text=($value|ConvertTo-Json -Compress);exitCode=0;timedOut=$false}
    })
    [pscustomobject]@{status='READS_COLLECTED';error='';inventoryExitCode=0;probedInstances=@($s.targets.instanceName);markerReads=$reads}
}
foreach($role in @('Primary / Desktop','Laptop / Surrogate')){
    $observed=& $module {
        param($Role,$Marker)
        $p=@{Session='fixture';TransactionId=('a'*32);PayloadSha256=('b'*64);Role=$Role;ExpectedDevFleetVersion='1.2.13';ExpectedInstallerVersion='1.4.1';InvocationStartUtc=[datetime]::UtcNow.AddMinutes(-1).ToString('o');ObservationTimeoutSeconds=30;ExpectedNestedLinuxName='DevFleet-E2E-Linux-01';GuestMarkerReadProvider=$Marker}
        $p.ExpectedComputeInstanceName=if($Role-eq'Primary / Desktop'){'devfleet-primary'}else{'devfleet-failover'}
        if($Role-eq'Laptop / Surrogate'){$p.ExpectedVaultInstanceName='devfleet-vault'}
        Get-ProductLifecycleObservation @p
    } $role $marker
    Check ($role+' native call site') ($observed.authenticatedHealthOk-and$observed.productRoleIdentityValid-and$observed.authenticatedHealthEvidence.responseAuthenticated)
    $normalized=& $module {param($o) ConvertTo-NormalizedLifecycleObservation $o} $observed
    $prior=[pscustomobject]@{checkpointGeneration=1;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role=$role;state='waiting-for-reboot'}
    Check ($role+' normalized completion') ((Get-DurableProgressClassification -Observation $normalized -PriorCheckpoint $prior)-eq'COMPLETED'-and$normalized.authenticatedHealthEvidence.responseAuthenticated)
    Check ($role+' repeated health is not new progress') (-not(Test-ProductMeaningfulProgress -Previous $normalized -Current $normalized))
    # The native bounded wait/evidence path runs under the host's supported PS7.
    if($PSVersionTable.PSVersion.Major-ge7){
        $evidence=Join-Path $FixtureRoot ('wait-'+[guid]::NewGuid().ToString('N')+'/observer.json')
        $waited=Wait-DevFleetProductLifecycleTransition -Session 'fixture' -TransactionId ('a'*32) -PayloadSha256 ('b'*64) -Role $role -PriorGeneration 1 -BudgetSeconds 15 -PollSeconds 1 -ObservationTimeoutSeconds 10 -EvidencePath $evidence -ExpectedDevFleetVersion '1.2.13' -ExpectedInstallerVersion '1.4.1' -ObservationProvider {param($s)$s.providerContext} -ObservationProviderContext $normalized
        $saved=Get-Content -Raw -LiteralPath $evidence|ConvertFrom-Json
        $journal=Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $evidence) 'product-lifecycle-progress.jsonl')
        Check ($role+' wait/journal retains authenticated evidence') ($waited.outcome-eq'COMPLETED'-and$saved.observation.authenticatedHealthEvidence.responseAuthenticated-and$journal-match'authenticatedHealthEvidence')
    }
}
$report=[ordered]@{parentPowerShellVersion=$PSVersionTable.PSVersion.ToString();actualSecretUsed=$false;vmOperations=0;cases=@($results);passed=@($results|Where-Object{$_.pass}).Count;total=$results.Count}
$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $ReportPath
Write-Host "PS $($report.parentPowerShellVersion): $($report.passed)/$($report.total) authenticated health checks"
if($report.passed-ne$report.total){$results|Where-Object{-not$_.pass}|Format-Table;exit 1}
