# DevFleet source part 047

Full-source UTF-8 byte interval [2139000, 2185500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2830b1690ec00ce4145b420c8589ce120409f54a62504f42cbf69f8ea6b489fc

<!-- BEGIN SOURCE SLICE -->
 -eq 'control-plane-recovery-failure' -and $failure -cnotmatch 'controlled Multipass service recovery failure'){throw 'Control-plane recovery failure lost its primary cause'}
        if($case -eq 'wrong-host' -and $state.calls.Count){throw 'Readiness called transport on the physical host'}
        if($case -eq 'info-timeout-exhausted' -and ($state.mutations -join '|') -cne 'stop|start'){throw 'Timeout scenario did not retain exact nested VM recovery'}
        if($case -eq 'info-timeout-exhausted' -and $failure -cnotmatch 'READINESS_TRACE:.*inventory=PASS.*hyperVBefore=Running.*infoTimeouts=[1-9]'){throw 'Timeout failure did not retain sanitized readiness trace'}
        if($case -eq 'info-timeout-exhausted' -and $failure -cmatch 'Last info:|IPv4:|10\.0\.0\.2'){throw 'Timeout failure leaked raw nested info output'}
        $checks++;Write-Host "PASS $case"
    }
}finally{$env:COMPUTERNAME=$originalComputerName}
Write-Host "PASS $checks shared nested readiness cases; all VM/transport I/O mocked; no VM mutation"

```


## FILE: automation/release-e2e/tests/Test-NestedPrimaryReadinessFreshness.ps1

SHA256: 0412bd5863b8cafdedd17735f3b9f0db6cd55e2609b99b6678c5390fcde03d93 | Bytes: 4202 | Git mode: 100644

```
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

```


## FILE: automation/release-e2e/tests/Test-NestedProductScenarioArgumentBinding.ps1

SHA256: b356b9dd336a0eb408be0b54873c850da5da80ced35bdbc070258069ce4b8f07 | Bytes: 4200 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}else{$WorkspaceRoot=(Resolve-Path -LiteralPath $WorkspaceRoot).Path}

$executorPath=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1'
$tarPath=(Resolve-Path (Join-Path $WorkspaceRoot 'outputs\devfleet-v1.2.13.tar.gz')).Path
$tarHash=(Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()
$runDir=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-NestedArgumentBinding-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runDir)

$observed=$null
$errorText=$null
try {
    Import-Module $executorPath -Force -DisableNameChecking
    $executorModule=Get-Module Invoke-RealProductPhase | Select-Object -First 1
    $context=[pscustomobject]@{
        runId='e2e-fullrelease-current-candidate-20260917T055128Z'
        phaseId='PERMANENT-DELETE'
        candidate=[pscustomobject]@{tar=[pscustomobject]@{path=$tarPath;sha256=$tarHash}}
        vmName='DevFleet-E2E-Win11-01'
        vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
        runDir=$runDir
        workspaceRoot=$WorkspaceRoot
    }
    $probe=& $executorModule {
        param($Context)
        function Connect-DevFleetGuest { param([guid]$VmId) [pscustomobject]@{fake=$true} }
        function Remove-DevFleetGuestSession { param($Session) }
        function Get-StageIntegrity { param([string]$LocalPath,$Session,[string]$RemotePath) [pscustomobject]@{equal=$true} }
        function Assert-ExactCandidate { param($Context) $Context.candidate }
        function Copy-Item { param([string]$LiteralPath,[string]$Destination,[switch]$ToSession,[switch]$Force) }
        function Invoke-Command {
            param($Session,[scriptblock]$ScriptBlock,[object[]]$ArgumentList)
            if($ArgumentList.Count -eq 1){ return $null }
            $rows=@();$index=0
            foreach($value in $ArgumentList){
                $text=[string]$value
                $rows += [pscustomobject]@{
                    index=$index
                    type=if($null -eq $value){'NULL'}else{$value.GetType().FullName}
                    length=$text.Length
                    value=$text
                }
                $index++
            }
            throw ('NESTED_ARGUMENT_CAPTURE:' + ($rows|ConvertTo-Json -Compress))
        }
        try {
            [void](Invoke-NestedProductScenario -Context $Context -Scenario 'permanent-delete')
            [pscustomobject]@{error='expected the remote argument capture to stop the probe';observed=@()}
        } catch {
            $message=$_.Exception.Message
            $prefix='NESTED_ARGUMENT_CAPTURE:'
            $captureIndex=$message.IndexOf($prefix,[StringComparison]::Ordinal)
            if($captureIndex -lt 0){[pscustomobject]@{error=$message;observed=@()}}
            else {[pscustomobject]@{error=$null;observed=(($message.Substring($captureIndex+$prefix.Length))|ConvertFrom-Json)}}
        }
    } $context
    $observed=@($probe.observed)
    $errorText=[string]$probe.error
} finally {
    if([IO.Directory]::Exists($runDir)){Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue}
}

$runIdRow=$observed|Where-Object index -eq 4|Select-Object -First 1
$phaseRow=$observed|Where-Object index -eq 5|Select-Object -First 1
$scenarioRow=$observed|Where-Object index -eq 6|Select-Object -First 1
$expectedRunId=[string]$context.runId
$pass=([string]::IsNullOrEmpty($errorText) -and $runIdRow -and $phaseRow -and $scenarioRow -and
    [string]$runIdRow.value -ceq $expectedRunId -and [string]$phaseRow.value -ceq [string]$context.phaseId -and
    [string]$scenarioRow.value -ceq 'permanent-delete' -and [int]$runIdRow.length -le 128)
[pscustomobject]@{
    status=if($pass){'PASS'}else{'FAIL'}
    passed=if($pass){1}else{0}
    total=1
    checks=@([pscustomobject]@{name='remote nested scenario receives scalar validated identity arguments';pass=$pass;observed=$observed;error=$errorText})
    vmOperations=0
    candidateBytesChanged=$false
}|ConvertTo-Json -Depth 8
if(-not $pass){exit 1}

```


## FILE: automation/release-e2e/tests/Test-NestedProductScenarioContract.ps1

SHA256: 81149196fdcd62cf533f9bfa0e72d2fdc7bf6548eaabe677d542ecb417b33b09 | Bytes: 16399 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}else{$WorkspaceRoot=(Resolve-Path -LiteralPath $WorkspaceRoot).Path}

$executorPath=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1'
$driverPath=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-ProductLifecycleScenario.py'
$evidencePath=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\Evidence.psm1'
$proofPath=Join-Path $WorkspaceRoot 'audit\run-exact-candidate-proof.ps1'
Import-Module $executorPath -Force -DisableNameChecking
$executorModule=Get-Module Invoke-RealProductPhase
Import-Module $evidencePath -Force

$checks=[Collections.Generic.List[object]]::new()
function Add-Check([string]$Name,[bool]$Pass,[object]$Observed=$null){$checks.Add([pscustomobject]@{name=$Name;pass=$Pass;observed=$Observed})}

$valid=@(
    [pscustomobject]@{runId='fullrelease-current-candidate-readinessfix2-20260916T004745Z';phaseId='PERMANENT-DELETE';scenario='permanent-delete'},
    [pscustomobject]@{runId='e2e-20260916T004745Z-12345678';phaseId='DELETE-RESTORE';scenario='delete-restore'}
)
foreach($case in $valid){
    $identity=& $executorModule {param($RunId,$PhaseId,$Scenario)Resolve-DevFleetNestedScenarioIdentity -RunId $RunId -PhaseId $PhaseId -Scenario $Scenario} $case.runId $case.phaseId $case.scenario
    Add-Check "valid nested identity: $($case.runId)" ($identity.root -ceq "/tmp/devfleet-e2e/$($case.runId)/$($case.phaseId)") $identity.root
}

$invalidRunIds=@(
    '',
    'e2e-short/../escape',
    'e2e-short\escape',
    'e2e-short_escape',
    'e2e-short.escape',
    'e2e-short--collision',
    'e2e-short-',
    'E2E-short-segment',
    'other-short-segment',
    ('fullrelease-'+('a'*129)),
    "fullrelease-valid-segment`n"
)
foreach($runId in $invalidRunIds){
    $rejected=$false
    try{[void](& $executorModule {param($RunId)Resolve-DevFleetNestedScenarioIdentity -RunId $RunId -PhaseId 'PERMANENT-DELETE' -Scenario 'permanent-delete'} $runId)}catch{$rejected=$true}
    Add-Check "reject nested RunId: $runId" $rejected
}
foreach($phaseId in @('permanent-delete','PERMANENT-DELETE/..','PERMANENT_DELETE','DELETE-RESTORE','-PERMANENT-DELETE','PERMANENT--DELETE')){
    $rejected=$false
    try{[void](& $executorModule {param($PhaseId)Resolve-DevFleetNestedScenarioIdentity -RunId 'fullrelease-valid-segment' -PhaseId $PhaseId -Scenario 'permanent-delete'} $phaseId)}catch{$rejected=$true}
    Add-Check "reject mismatched phase: $phaseId" $rejected
}

$driverSource=Get-Content -LiteralPath $driverPath -Raw
$patternMatch=[regex]::Match($driverSource,'RELEASE_RUN_ID_PATTERN\s*=\s*re\.compile\(r"(?<pattern>[^"]+)"\)')
Add-Check 'Python driver exposes its canonical run identity pattern' $patternMatch.Success
if($patternMatch.Success){
    $driverPattern=[regex]::new(('\A(?:{0})\z' -f $patternMatch.Groups['pattern'].Value),[Text.RegularExpressions.RegexOptions]::CultureInvariant)
    foreach($case in $valid){Add-Check "Python accepts valid RunId: $($case.runId)" $driverPattern.IsMatch($case.runId)}
    foreach($runId in @($invalidRunIds|Where-Object{$_.Length -le 128})){Add-Check "Python rejects invalid RunId: $runId" (-not $driverPattern.IsMatch($runId))}
}
Add-Check 'Python applies length and full-match checks inside structured failure handling' ($driverSource -match 'try:\s*\r?\n\s*require\(len\(args\.run_id\) <= 128 and RELEASE_RUN_ID_PATTERN\.fullmatch\(args\.run_id\)')

$tokens=$null;$parseErrors=$null
$executorAst=[Management.Automation.Language.Parser]::ParseFile($executorPath,[ref]$tokens,[ref]$parseErrors)
Add-Check 'executor parses without PowerShell syntax errors' (@($parseErrors).Count -eq 0) (@($parseErrors|ForEach-Object{$_.Message}) -join '; ')
$wrapperNodes=@($executorAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-NestedMultipass'},$true))
Add-Check 'exactly one nested Multipass wrapper exists' ($wrapperNodes.Count -eq 1) $wrapperNodes.Count
if($wrapperNodes.Count -eq 1){
    $runner=[scriptblock]::Create("param(`$Executable,`$Command)`n`$mp=`$Executable`n$($wrapperNodes[0].Extent.Text)`nInvoke-NestedMultipass -Arguments @('-NoProfile','-NonInteractive','-Command',`$Command) -TimeoutSeconds 10")
    $hash='a'*64
    $probe=& $runner (Get-Process -Id $PID).Path "[Console]::Out.WriteLine('$hash');[Console]::Error.WriteLine('warning')"
    Add-Check 'wrapper removes terminal blank rows from stdout' (@($probe.stdout).Count -eq 1 -and [string]$probe.stdout[0] -ceq $hash) (@($probe.stdout) -join '|')
    Add-Check 'wrapper keeps stderr separate from parseable stdout' (@($probe.stderr).Count -eq 1 -and [string]$probe.stderr[0] -ceq 'warning' -and @($probe.output).Count -eq 2) (@($probe.output) -join '|')
    $failureProbe=& $runner (Get-Process -Id $PID).Path "[Console]::Error.WriteLine('failure');exit 7"
    Add-Check 'wrapper preserves nonzero exit and stderr-only output' ($failureProbe.exitCode -eq 7 -and @($failureProbe.stdout).Count -eq 0 -and @($failureProbe.stderr).Count -eq 1) $failureProbe.exitCode

    $windowsPowerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $pidMarker=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-NestedTimeout-'+[guid]::NewGuid().ToString('N')+'.pid')
    try{
        $markerLiteral=$pidMarker.Replace("'","''")
        $childCommand="[IO.File]::WriteAllText('$markerLiteral',[string]`$PID);Start-Sleep -Seconds 30"
        $childCommandLiteral=$childCommand.Replace("'","''")
        $ps5Literal=$windowsPowerShell.Replace("'","''")
        $ps5Body="`$ErrorActionPreference='Stop'`n`$mp='$ps5Literal'`n$($wrapperNodes[0].Extent.Text)`n`$timedOut=`$false`ntry{Invoke-NestedMultipass -Arguments @('-NoProfile','-NonInteractive','-Command','$childCommandLiteral') -TimeoutSeconds 1|Out-Null}catch{`$timedOut=`$_.Exception.Message -like 'Nested Multipass operation timed out*'}`n`$childPid=if(Test-Path -LiteralPath '$markerLiteral'){[int](Get-Content -LiteralPath '$markerLiteral' -Raw)}else{0}`nStart-Sleep -Milliseconds 250`n`$alive=`$false;if(`$childPid){try{`$null=Get-Process -Id `$childPid -ErrorAction Stop;`$alive=`$true}catch{}}`n[pscustomobject]@{timedOut=`$timedOut;childPid=`$childPid;alive=`$alive}|ConvertTo-Json -Compress"
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
     