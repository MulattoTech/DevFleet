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
