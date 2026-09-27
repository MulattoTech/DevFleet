[CmdletBinding()]
param([string]$ReportPath,[ValidatePattern('^[0-9a-f]{40}$')][string]$BaselineCommit)
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/MultipassDiagnostic.psm1') -Force
$runner=Get-DevFleetBoundedProcessScriptBlock
if($BaselineCommit){
    $workspace=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $baseline=(& git -C $workspace show ($BaselineCommit+':automation/release-e2e/modules/MultipassDiagnostic.psm1')) -join "`n"
    if($LASTEXITCODE -ne 0){throw 'Immutable baseline source is unavailable'}
    $parseErrors=$null;$tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($baseline,[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'Immutable baseline source did not parse'}
    $factory=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-DevFleetBoundedProcessScriptBlock'},$false))
    if($factory.Count -ne 1){throw 'Immutable baseline runner is ambiguous'}
    $body=$factory[0].Body.Extent.Text
    $runner=& ([scriptblock]::Create($body.Substring(1,$body.Length-2)))
}
$engine=(Get-Process -Id $PID).Path
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-BoundedOutput-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch|Out-Null
$receipt=Join-Path $scratch 'held-child.json'
$marker='COLLECTOR_ENTER:e2e-vault-diagnostic-c-local'
$prefix="[Console]::Out.WriteLine('$marker');[Console]::Out.Flush();[Console]::Error.WriteLine('NATIVE_STDERR_MARKER');[Console]::Error.Flush();"
$heldCode="[Console]::Out.WriteLine('HELD_PIPE_CHILD');[Console]::Out.Flush();Start-Sleep -Seconds 30"
$heldEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($heldCode))
$heldParent=$prefix+@"
`$psi=[Diagnostics.ProcessStartInfo]::new();`$psi.FileName='$($engine.Replace("'","''"))';`$psi.Arguments='-NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $heldEncoded';`$psi.UseShellExecute=`$false;`$psi.CreateNoWindow=`$true
`$child=[Diagnostics.Process]::Start(`$psi)
[IO.File]::WriteAllText('$($receipt.Replace("'","''"))',((@{pid=`$child.Id;startedFileTimeUtc=`$child.StartTime.ToUniversalTime().ToFileTimeUtc()}|ConvertTo-Json -Compress)))
[Environment]::Exit(0)
"@
$cases=@(
    @{name='timeout-markers';code=$prefix+'Start-Sleep -Seconds 30';deadline=3;outcome='TIMEOUT';markers=$true;complete=$true},
    @{name='timeout-no-output';code='Start-Sleep -Seconds 30';deadline=3;outcome='TIMEOUT';markers=$false;complete=$true},
    @{name='timeout-tree';code=$heldParent.Replace('[Environment]::Exit(0)','Start-Sleep -Seconds 30');deadline=3;outcome='TIMEOUT';markers=$true;complete=$true},
    @{name='held-pipe';code=$heldParent;deadline=10;outcome='DRAIN_INCOMPLETE';markers=$true;complete=$false},
    @{name='bounded-output';code=$prefix+"[Console]::Out.Write(('x'*100000));[Console]::Out.Flush();Start-Sleep -Seconds 30";deadline=3;outcome='TIMEOUT';markers=$true;complete=$false},
    @{name='success';code=$prefix;deadline=10;outcome='PASS';markers=$true;complete=$true},
    @{name='large-success';code=$prefix+"[Console]::Out.WriteLine(('x'*40000)+'FINAL_FRAME_END');[Console]::Out.Flush()";deadline=10;outcome='PASS';markers=$true;complete=$true},
    @{name='nonzero';code=$prefix+'exit 7';deadline=10;outcome='NONZERO';markers=$true;complete=$true}
)
$results=[Collections.Generic.List[object]]::new()
try {
    foreach($case in $cases){
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($case.code))
        $request=@{filePath=$engine;arguments=@('-NoProfile','-NonInteractive','-OutputFormat','Text','-EncodedCommand',$encoded);deadlineUnixMilliseconds=[DateTimeOffset]::new([datetime]::UtcNow.AddSeconds($case.deadline)).ToUnixTimeMilliseconds()}|ConvertTo-Json -Compress
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $result=& $runner $request
        $clock.Stop()
        $failures=[Collections.Generic.List[string]]::new()
        if($result.outcome -cne $case.outcome){$failures.Add('outcome changed: '+$result.outcome)}
        if($clock.Elapsed.TotalSeconds -ge ($case.deadline+9)){$failures.Add('terminal deadline exceeded')}
        if($case.markers -and ([string]$result.stdout -notmatch [regex]::Escape($marker))){$failures.Add('flushed collector-entry/stdout marker lost')}
        if($case.markers -and ([string]$result.stderr -notmatch 'NATIVE_STDERR_MARKER')){$failures.Add('native stderr marker lost')}
        if([bool]$result.outputComplete -ne $case.complete){$failures.Add('output completeness is not truthful')}
        if($case.name -eq 'timeout-no-output' -and $result.stdout){$failures.Add('invented stdout for silent child')}
        # A killed Windows PowerShell 5.1 encoded-command host may emit its
        # otherwise empty CLIXML stream header. It is native output, not a
        # supervisor diagnostic; preserve it rather than sanitizing it away.
        if($case.name -eq 'timeout-no-output' -and [string]$result.stderr -cnotin @('',"#< CLIXML`r`n")){$failures.Add('supervisor text replaced native stderr')}
        if($case.name -eq 'bounded-output' -and ([string]$result.stdout).Length -gt 65536){$failures.Add('stdout exceeded bounded capture')}
        if($case.name -eq 'nonzero' -and $result.exitCode -ne 7){$failures.Add('original child exit code lost')}
        if($case.name -eq 'large-success' -and [string]$result.stdout -notmatch ('x{40000}FINAL_FRAME_END\r?\n$')){$failures.Add('complete long terminal frame was not captured')}
        if($result.pid -and (Get-Process -Id $result.pid -ErrorAction SilentlyContinue)){$failures.Add('exact owning child still alive')}
        if($case.name -eq 'timeout-tree'){
            if(-not(Test-Path -LiteralPath $receipt)){$failures.Add('test descendant did not start')}
            else{$treeChild=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json;if(Get-Process -Id $treeChild.pid -ErrorAction SilentlyContinue){$failures.Add('exact owned descendant still alive after timeout')}}
        }
        $row=[ordered]@{case=$case.name;status=if($failures.Count){'FAIL'}else{'PASS'};failures=@($failures);elapsedSeconds=$clock.Elapsed.TotalSeconds;result=$result}
        $results.Add($row)
        Write-Host "$($row.status) $($case.name): $($failures -join '; ')"
        if(Test-Path -LiteralPath $receipt){
            $owned=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
            $child=Get-Process -Id $owned.pid -ErrorAction SilentlyContinue
            if($child){if($child.StartTime.ToUniversalTime().ToFileTimeUtc() -ne $owned.startedFileTimeUtc){throw 'Held-pipe test child identity changed'};Stop-Process -Id $child.Id -Force;[void]$child.WaitForExit(3000)}
            Remove-Item -LiteralPath $receipt
        }
    }
} finally {
    if(Test-Path -LiteralPath $receipt){
        $owned=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
        $child=Get-Process -Id $owned.pid -ErrorAction SilentlyContinue
        if($child -and $child.StartTime.ToUniversalTime().ToFileTimeUtc() -eq $owned.startedFileTimeUtc){Stop-Process -Id $child.Id -Force;[void]$child.WaitForExit(3000)}
    }
    $expectedPrefix=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'DevFleet-BoundedOutput-'))
    if([IO.Path]::GetFullPath($scratch).StartsWith($expectedPrefix,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
$report=[ordered]@{engine=$PSVersionTable.PSVersion.ToString();baselineCommit=$BaselineCommit;vmMutation=$false;runnerMocked=$false;status=if(@($results|Where-Object status -eq 'FAIL').Count){'FAIL'}else{'PASS'};cases=@($results)}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
if($report.status -ne 'PASS'){throw 'Bounded process output behavioral regression failed.'}
