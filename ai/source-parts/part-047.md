# DevFleet source part 047

Full-source UTF-8 byte interval [2139000, 2185500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 4eaf0f00cd1afa2b6374b02c79ee606792d17b6ccffbd778ad08bdc3c6b597ea

<!-- BEGIN SOURCE SLICE -->
false;if(`$childPid){try{`$null=Get-Process -Id `$childPid -ErrorAction Stop;`$alive=`$true}catch{}}`n[pscustomobject]@{timedOut=`$timedOut;childPid=`$childPid;alive=`$alive}|ConvertTo-Json -Compress"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps5Body))
        $ps5Raw=@(& $windowsPowerShell -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1|ForEach-Object{[string]$_})
        $ps5Json=@($ps5Raw|Where-Object{$_.TrimStart().StartsWith('{')}|Select-Object -Last 1)
        $ps5Result=if($ps5Json.Count -eq 1){$ps5Json[0]|ConvertFrom-Json}else{$null}
        Add-Check 'Windows PowerShell 5.1 timeout terminates its exact sleeping child' ($ps5Result -and [bool]$ps5Result.timedOut -and [int]$ps5Result.childPid -gt 0 -and -not [bool]$ps5Result.alive) (@($ps5Raw|Select-Object -Last 8) -join '|')
    }finally{
        if(Test-Path -LiteralPath $pidMarker -PathType Leaf){
            $childPid=[int](Get-Content -LiteralPath $pidMarker -Raw)
            if($childPid -gt 0){Stop-Process -Id $childPid -Force -ErrorAction SilentlyContinue}
            Remove-Item -LiteralPath $pidMarker -Force -ErrorAction SilentlyContinue
        }
    }
}

$executorSource=Get-Content -LiteralPath $executorPath -Raw
$nestedStart=$executorSource.IndexOf('function Invoke-NestedProductScenario')
$nestedEnd=$executorSource.IndexOf('function Invoke-DisposableSyntheticRebootProbe',$nestedStart)
$nestedSource=if($nestedStart -ge 0 -and $nestedEnd -gt $nestedStart){$executorSource.Substring($nestedStart,$nestedEnd-$nestedStart)}else{''}
$readinessNodes=@($executorAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-DevFleetNestedPrimaryReadinessScriptBlock'},$true))
$readinessSource=if($readinessNodes.Count -eq 1){$readinessNodes[0].Extent.Text}else{''}
Add-Check 'FullRelease executes the shared restored-nested readiness route' ($readinessNodes.Count -eq 1 -and $nestedSource -match '\$readinessSource=\(Get-DevFleetNestedPrimaryReadinessScriptBlock\)\.ToString\(\)' -and $nestedSource -match '\$primaryReadiness=\. \(\[scriptblock\]::Create\(\$readinessSource\)\) -Primary \$primary -MultipassPath \$mp')
Add-Check 'nested identity is validated before guest connection and staging' ($nestedSource.IndexOf('Resolve-DevFleetNestedScenarioIdentity') -ge 0 -and $nestedSource.IndexOf('Resolve-DevFleetNestedScenarioIdentity') -lt $nestedSource.IndexOf('Connect-DevFleetGuest'))
$remoteIdentityStart=$nestedSource.IndexOf('param($tar,$expectedTarHash,$driver,$expectedDriverHash,$runId,$phaseId,$scenario')
$remoteIdentityEnd=$nestedSource.IndexOf('$l2Tar=', $remoteIdentityStart)
$remoteIdentitySource=if($remoteIdentityStart -ge 0 -and $remoteIdentityEnd -gt $remoteIdentityStart){$nestedSource.Substring($remoteIdentityStart,$remoteIdentityEnd-$remoteIdentityStart)}else{''}
Add-Check 'remote nested identity derives the owned L2 root from validated components instead of accepting a marshalled path' ($remoteIdentitySource -match 'param\(\$tar,\$expectedTarHash,\$driver,\$expectedDriverHash,\$runId,\$phaseId,\$scenario,\$readinessSource,\$vaultFixtureJson\)' -and $remoteIdentitySource -notmatch '\$ownedL2Root' -and $remoteIdentitySource -match '\$l2Root\s*=\s*\$expectedRoot')
Add-Check 'remote nested identity preserves strict RunId, scenario/phase, and canonical-root validation' ($remoteIdentitySource -match '\$runId\s*-cnotmatch' -and $remoteIdentitySource -match '\$phaseId\s*-cne\s*\$expectedPhase' -and $remoteIdentitySource -match '\$expectedRoot\s*-cnotmatch')
Add-Check 'nested Hyper-V recovery captures and revalidates immutable VM identity before mutation' ($readinessSource -match 'Get-VM\s+-Id' -and $readinessSource -match 'Stop-VM\s+-VM\s+\$Vm' -and $readinessSource -match '\$byId\.Name -cne \$ExpectedName -or \[guid\]\$byId\.Id -ne \$immutableId' -and $readinessSource -match '& \$VmStopProvider \$primaryVm' -and $readinessSource -notmatch 'Start-VM\s+-VM\s+\(Get-VM\s+-Name\s+\$primary')
$rootCreation="'install','-d','-o','root','-g','root','-m','0755'"
$incomingCreation="'install','-d','-o','ubuntu','-g','ubuntu','-m','0700',"+'$incoming'
Add-Check 'owned root stays root-owned while incoming staging is ubuntu-only' ($nestedSource.Contains($rootCreation) -and $nestedSource.Contains($incomingCreation))
Add-Check 'transfers target only the scoped incoming directory' ($nestedSource.Contains('"$primary`:$incomingTar"') -and $nestedSource.Contains('"$primary`:$incomingDriver"') -and -not $nestedSource.Contains('"$primary`:$l2Tar"') -and -not $nestedSource.Contains('"$primary`:$l2Driver"'))
$incomingLock="'chown','-R','root:root','--',"+'$incoming'
Add-Check 'incoming files are locked, promoted root-owned, and removed before execution' ($nestedSource.Contains($incomingLock) -and @([regex]::Matches($nestedSource,"'install','-T','-o','root','-g','root','-m','0644'")).Count -eq 2 -and $nestedSource.IndexOf("'rm','-rf','--',`$incoming") -lt $nestedSource.IndexOf("'--run-id',`$runId"))
Add-Check 'TAR and driver hashes parse strict stdout only' ($nestedSource -match '\$hashLines=@\(\$hashResult\.stdout\)' -and $nestedSource -match '\$driverHashLines=@\(\$driverHashResult\.stdout\)' -and $nestedSource -notmatch '\$hashResult\.output.*Select-Object -Last 1' -and $nestedSource -notmatch '\$driverHashResult\.output.*Select-Object -Last 1')
Add-Check 'scenario JSON and identity parse stdout only' ($nestedSource -match '\$raw=@\(\$scenarioResultRaw\.stdout\)' -and $nestedSource -match '\$guestIdentityRaw=@\(\$guestIdentityResult\.stdout\)')
Add-Check 'readiness parses stdout while retaining merged diagnostics' ($readinessSource -match '\$lastInfo=@\(\$infoResult\.output\)' -and $readinessSource -match '\$infoStdout=@\(\$infoResult\.stdout\)' -and $readinessSource -match '\[regex\]::Match\(\$infoStdout')
Add-Check 'successful scenarios fail closed when exact owned-root cleanup fails' ($nestedSource -match '\$scenarioCompleted=\$true' -and $nestedSource -match '\$cleanupResult\.exitCode -ne 0' -and $nestedSource -match 'if\(\$scenarioCompleted -and \$cleanupFailure\)\{throw "Nested scenario completed but its exact owned-root cleanup failed:')
Add-Check 'nested timeout has PowerShell 5.1 taskkill and exact-process fallback' ($readinessSource -match '\$process\.Kill\(\$true\)' -and $readinessSource -match "System32\\taskkill\.exe" -and $readinessSource -match "'/PID'.*'/T'.*'/F'" -and $readinessSource -match '\$process\.Kill\(\)' -and $readinessSource -match '\$process\.WaitForExit\(5000\)')

$tempWorkspace=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-RunIdContract-'+[guid]::NewGuid().ToString('N'))
try{
    [void][IO.Directory]::CreateDirectory($tempWorkspace)
    $validEvidenceId='focused-maintenance-20260916T004745Z-12345678'
    $validEvidencePath=New-RunEvidenceDirectory -WorkspaceRoot $tempWorkspace -RunId $validEvidenceId
    $expectedEvidencePath=[IO.Path]::GetFullPath((Join-Path $tempWorkspace "audit\automation-harness\runs\$validEvidenceId"))
    Add-Check 'generic evidence RunId resolves to its exact canonical leaf' ($validEvidencePath -ceq $expectedEvidencePath -and [IO.Directory]::Exists($expectedEvidencePath)) $validEvidencePath
    foreach($runId in @('escape/child','escape\child','escape_child','escape.child','escape--child','escape-',"escape`nchild","escape-valid`n","escape-valid`r`n",('a'*129))){
        $rejected=$false
        try{[void](New-RunEvidenceDirectory -WorkspaceRoot $tempWorkspace -RunId $runId)}catch{$rejected=$true}
        Add-Check "generic evidence rejects unsafe RunId: $runId" $rejected
    }
    $created=@(Get-ChildItem -LiteralPath (Join-Path $tempWorkspace 'audit\automation-harness\runs') -Directory)
    Add-Check 'rejected evidence identities create no sibling paths' ($created.Count -eq 1 -and $created[0].Name -ceq $validEvidenceId) (@($created.Name) -join '|')
}finally{
    if([IO.Directory]::Exists($tempWorkspace)){Remove-Item -LiteralPath $tempWorkspace -Recurse -Force}
}

$proofSource=Get-Content -LiteralPath $proofPath -Raw
Add-Check 'exact-proof entrypoint uses the canonical evidence path validator' ($proofSource -match '\$runDir\s*=\s*New-RunEvidenceDirectory' -and $proofSource -notmatch '\$runDir\s*=\s*Join-Path\s+\$WorkspaceRoot\s+\(Join-Path\s+''audit\\automation-harness\\runs''')
Add-Check 'exact-proof entrypoint rejects live tooling materialization drift before VM mutation' ($proofSource -match 'compute_shipping_input_identity\.py' -and $proofSource -match 'liveTooling\.toolingFingerprint\.toolingFingerprintId' -and $proofSource -match 'refused a tooling materialization that differs from current candidate authority')

$attributesPath=Join-Path $WorkspaceRoot '.gitattributes'
$attributes=if(Test-Path -LiteralPath $attributesPath -PathType Leaf){Get-Content -LiteralPath $attributesPath -Raw}else{''}
Add-Check 'repository pins release tooling and proof entrypoint to LF materialization' ($attributes -match '(?m)^/automation/\*\* text eol=lf$' -and $attributes -match '(?m)^/tools/\*\* text eol=lf$' -and $attributes -match '(?m)^/audit/run-exact-candidate-proof\.ps1 text eol=lf$')
$trackedTooling=@(& git -C $WorkspaceRoot ls-files tools automation)
$crlfPaths=[Collections.Generic.List[string]]::new()
foreach($relative in @($trackedTooling)+@('audit/run-exact-candidate-proof.ps1',$PSCommandPath)){
    $path=if([IO.Path]::IsPathRooted([string]$relative)){[string]$relative}else{Join-Path $WorkspaceRoot ([string]$relative)}
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){continue}
    $bytes=[IO.File]::ReadAllBytes($path)
    for($index=0;$index -lt ($bytes.Length-1);$index++){if($bytes[$index] -eq 13 -and $bytes[$index+1] -eq 10){$crlfPaths.Add([string]$relative);break}}
}
Add-Check 'live release tooling and proof entrypoint contain no CRLF materialization drift' ($crlfPaths.Count -eq 0) (@($crlfPaths|Select-Object -Unique) -join '|')

$failed=@($checks|Where-Object{-not $_.pass})
[pscustomobject]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;failed=$failed;vmOperations=0;candidateBytesChanged=$false}|ConvertTo-Json -Depth 6
if($failed.Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-ProductAuthenticatedHealth.ps1

SHA256: ef9b09d08092a078a3a94916dacf8e70ff3dbed481d42f435890c00d9f58e58c | Bytes: 15024 | Git mode: 100644

```
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

```


## FILE: automation/release-e2e/tests/Test-ProductFailureLogCapture.ps1

SHA256: 9406c6be99d4a9f0b2729580924d9aea26075b0d3b662eff4ff49915b3f8011e | Bytes: 10139 | Git mode: 100644

```
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

```


## FILE: automation/release-e2e/tests/Test-ProductLaunchObserverDeferral.ps1

SHA256: 8543a7358c2932c66808e4b95e285784a32e5e3f2f11351e19c6a5fd6cf20634 | Bytes: 7096 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force
$module=Get-Module Invoke-RealProductPhase
$checks=[Collections.Generic.List[object]]::new()
$remote={param($s)$s.context.observation}
$guest={
    param($s)
    $s.context.probeCalls++
    $reads=@(foreach($target in $s.targets){
        $marker=@{schemaVersion=1;transactionId=$s.transactionId;payloadSha256=$s.payloadSha256;sequence=9;component='bootstrap';state='COMPLETED';updatedUtc='2026-01-01T00:00:06Z';packageVersion=if($target.nodeRole-ceq'vault'){'vault'}else{'1.2.13'};nodeRole=$target.nodeRole}
        [pscustomobject]@{instanceName=$target.instanceName;text=($marker|ConvertTo-Json -Compress);exitCode=0;timedOut=$false}
    })
    [pscustomobject]@{status='READS_COLLECTED';error='';inventoryExitCode=0;probedInstances=@($s.targets.instanceName);markerReads=$reads}
}
foreach($case in @('desktop-launch','laptop-compute-launch','laptop-vault-launch','started','launched','ready','payload-transferred','payload-extracted','complete','no-native-child','foreign-parent','stale-child','unbound-transaction','wrong-payload','wrong-stage-role','wrong-instance-stage','duplicate-pid','foreign-native-path','parent-cycle','stale-transaction','existing-terminal')){
    $role=if($case-like'laptop-*'){'Laptop / Surrogate'}else{'Primary / Desktop'}
    $kind=if($case-like'laptop-*'){'Laptop'}else{'Desktop'}
    $compute=if($kind-ceq'Laptop'){'devfleet-failover'}else{'devfleet-primary'}
    $prefix=if($case-ceq'laptop-vault-launch'){'stage-vault'}else{"stage-compute-$compute"}
    $stage=[pscustomobject]@{name="$prefix-instance-absent.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-absent";completedUtc='2026-01-01T00:00:04Z'}
    $candidate=[pscustomobject]@{pid=100;parentPid=99;name='DevFleet-Setup.exe';commandClass='DevFleet-Setup';startTimeUtc='2026-01-01T00:00:01Z'}
    $bootstrap=[pscustomobject]@{pid=101;parentPid=100;name='pwsh.exe';commandClass='Bootstrap-Install';startTimeUtc='2026-01-01T00:00:02Z'}
    $installer=[pscustomobject]@{pid=102;parentPid=101;name='pwsh.exe';commandClass='Install-DevFleet';startTimeUtc='2026-01-01T00:00:03Z'}
    $native=[pscustomobject]@{pid=103;parentPid=102;name='multipass.exe';path='C:\Program Files\Multipass\bin\multipass.exe';commandClass='multipass';startTimeUtc='2026-01-01T00:00:05Z'}
    $observation=[pscustomobject]@{candidateProcess=$candidate;activeTransaction=[pscustomobject]@{transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;preparedUtc='2026-01-01T00:00:02Z'};stageMarkers=@($stage);stageMarkerErrors=@();terminalFailure=$false;progress=[pscustomobject]@{productChildInstances=@($candidate,$bootstrap,$installer,$native);guestProgressMarkerStatus='DEFERRED'}}
    switch($case){
        'started' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-instance-started.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-started";completedUtc='2026-01-01T00:00:06Z'}}
        'launched' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-instance-launched.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-launched";completedUtc='2026-01-01T00:00:06Z'}}
        'ready' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-instance-ready.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-instance-ready";completedUtc='2026-01-01T00:00:06Z'}}
        'payload-transferred' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-payload-transferred.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-payload-transferred";completedUtc='2026-01-01T00:00:06Z'}}
        'payload-extracted' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix-payload-extracted.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage="$prefix-payload-extracted";completedUtc='2026-01-01T00:00:06Z'}}
        'complete' {$observation.stageMarkers+=,[pscustomobject]@{name="$prefix.complete";transactionId=('a'*32);payloadSha256=('b'*64);action='FreshInstall';role=$kind;stage=$prefix;completedUtc='2026-01-01T00:00:06Z'}}
        'no-native-child' {$observation.progress.productChildInstances=@($candidate,$bootstrap,$installer)}
        'foreign-parent' {$native.parentPid=900}
        'stale-child' {$native.startTimeUtc='2025-12-31T23:59:59Z'}
        'unbound-transaction' {$observation.activeTransaction.transactionId='c'*32}
        'wrong-payload' {$stage.payloadSha256='c'*64}
        'wrong-stage-role' {$stage.role='Laptop'}
        'wrong-instance-stage' {$stage.name='stage-compute-foreign-instance-absent.complete';$stage.stage='stage-compute-foreign-instance-absent'}
        'duplicate-pid' {$observation.progress.productChildInstances+=,$native}
        'foreign-native-path' {$native.path='C:\unrelated\multipass.exe'}
        'parent-cycle' {$installer.parentPid=103}
        'stale-transaction' {$observation.activeTransaction.preparedUtc='2025-12-31T23:59:59Z'}
        'existing-terminal' {$observation.terminalFailure=$true}
    }
    $context=[pscustomobject]@{observation=$observation;probeCalls=0}
    $parameters=@{Session=[pscustomobject]@{};TransactionId=('a'*32);PayloadSha256=('b'*64);Action='FreshInstall';Role=$role;PriorGeneration=1;MaxGeneration=3;CandidateProcessId=100;ExpectedDevFleetVersion='1.2.13';ExpectedInstallerVersion='1.4.1';ObservationTimeoutSeconds=10;InvocationStartUtc='2026-01-01T00:00:00Z';ExpectedComputeInstanceName=$compute;RemoteObservationProvider=$remote;GuestMarkerReadProvider=$guest;ObservationAdapterContext=$context}
    if($kind-ceq'Laptop'){$parameters.ExpectedVaultInstanceName='devfleet-vault'}
    $result=& $module {param($p)Get-ProductLifecycleObservation @p} $parameters
    $expectDeferred=$case-in@('desktop-launch','laptop-compute-launch','laptop-vault-launch')
    $pass=if($expectDeferred){$context.probeCalls-eq0-and$result.progress.guestProgressMarkerStatus-ceq'DEFERRED_PRODUCT_LAUNCH'-and-not$result.productRoleIdentityValid}else{$context.probeCalls-eq1-and$result.progress.guestProgressMarkerStatus-ceq'VALID'}
    if($case-in@('wrong-payload','wrong-stage-role','wrong-instance-stage')){$pass=$pass-and@($result.stageMarkerErrors).Count-eq1}
    $checks.Add([pscustomobject]@{case=$case;pass=[bool]$pass;probeCalls=$context.probeCalls;status=$result.progress.guestProgressMarkerStatus})
}
[pscustomobject]@{status=if(@($checks|Where-Object{-not$_.pass}).Count){'FAIL'}else{'PASS'};passed=@($checks|Where-Object{$_.pass}).Count;total=$checks.Count;checks=@($checks);vmOperations=0}|ConvertTo-Json -Depth 5
if(@($checks|Where-Object{-not$_.pass}).Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-RealUseAcceptancePhase.ps1

SHA256: 7d005da688720961d3a40d7182dee22ea146080d382043a726c6eab6cec04c7c | Bytes: 29495 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $WorkspaceRoot 'automation/release-e2e/modules/RealUseAcceptance.psm1'
Import-Module $modulePath -Force -DisableNameChecking
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Evidence.psm1') -Force -DisableNameChecking
$checks = [Collections.Generic.List[object]]::new()

function Check([string]$Name, [bool]$Pass) { $checks.Add([pscustomobject]@{name=$Name;pass=$Pass}) }
function Rejects([scriptblock]$Action) { try { & $Action; return $false } catch { return $true } }
function CaptureError([scriptblock]$Action) { try { & $Action | Out-Null; return '' } catch { return [string]$_.Exception.Message } }
function Clone($Value) { return ($Value | ConvertTo-Json -Depth 32 | ConvertFrom-Json) }

$temp = Join-Path $env:TEMP "DevFleet-RealUse-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $runId = 'fullrelease-real-use-fixture-20260916T000000Z'
    $runDir = Join-Path $temp 'run'; New-Item -ItemType Directory -Path $runDir | Out-Null
    $candidatePath = Join-Path $temp 'candidate.exe'; [IO.File]::WriteAllText($candidatePath,'candidate',[Text.UTF8Encoding]::new($false))
    $runnerDir = Join-Path $temp 'automation/release-e2e/modules/executors'; New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
    $runnerPath = Join-Path $runnerDir 'Invoke-RealUseAcceptance.py'; [IO.File]::WriteAllText($runnerPath,"#!/usr/bin/env python3`n",[Text.UTF8Encoding]::new($false))
    $exeHash = (Get-FileHash $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $tarHash = '2' * 64; $releaseHash = '3' * 64; $toolingHash = '4' * 64; $shippingHash = '5' * 64
    $repositoryHead = '6' * 40; $candidateCommit = '7' * 40; $transaction = '8' * 32; $invocation = '9' * 32
    $candidate = [pscustomobject][ordered]@{
        repositoryHead=$repositoryHead;gitCommit=$candidateCommit;shippingInputIdentity=$shippingHash;releaseFingerprintId=$releaseHash;toolingFingerprintId=$toolingHash
        candidate=[pscustomobject]@{path=$candidatePath;sha256=$exeHash;bytes=(Get-Item $candidatePath).Length}
        tar=[pscustomobject]@{path=(Join-Path $temp 'candidate.tar.gz');sha256=$tarHash;bytes=1}
    }
    $targets = @(
        [pscustomobject]@{instanceName='devfleet-failover';nodeRole='surrogate';kind='compute'},
        [pscustomobject]@{instanceName='devfleet-vault';nodeRole='vault';kind='vault'}
    )
    $lifeDir = Join-Path $runDir "lifecycle-SURROGATE-DISPOSABLE-$invocation"; New-Item -ItemType Directory -Path $lifeDir | Out-Null
    $authorityPath = Join-Path $lifeDir 'product-lifecycle-completion-authority.json'
    $authority = [ordered]@{status='REAL E2E PASS';contract='product-lifecycle-completion-authority';transactionId=$transaction;invocationId=$invocation;payloadSha256=$tarHash;role='Laptop / Surrogate';completionVerified=$true;authenticatedHealth=$true;guest=[ordered]@{roleEvidence=[ordered]@{requiredTargets=$targets}}}
    Write-EvidenceJson -Path $authorityPath -Value $authority
    $product = [pscustomobject][ordered]@{status='REAL E2E PASS';phase='SURROGATE-DISPOSABLE';contract='product-lifecycle