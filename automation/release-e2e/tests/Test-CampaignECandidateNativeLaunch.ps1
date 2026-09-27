[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSVersion.Major-lt7){throw 'This regression must exercise the actual PowerShell7 native implementation.'}
$release=Split-Path -Parent $PSScriptRoot;$repo=Split-Path -Parent (Split-Path -Parent $release)
Import-Module (Join-Path $release 'modules/MultipassDiagnostic.psm1') -Force -DisableNameChecking
$common=Import-Module (Join-Path $repo 'source/windows/DevFleet.Common.psm1') -Force -PassThru -DisableNameChecking
$engine=(Get-Process -Id $PID).Path
$scratch=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('astra-native-'+[guid]::NewGuid().ToString('N'))));$priorData=$env:ProgramData
$results=[Collections.Generic.List[object]]::new()
try{
    New-Item -ItemType Directory -Path $scratch|Out-Null;$env:ProgramData=$scratch
    $probePath=Join-Path $scratch 'argument probe.ps1'
    @'
param([string]$Case,[string]$Value,[string]$PidPath)
if($PidPath){[IO.File]::WriteAllText($PidPath,[string]$PID)}
switch($Case){
    success {[Console]::Out.Write($Value)}
    nonzero {[Console]::Error.Write('controlled-native-failure');exit 7}
    timeout {Start-Sleep -Seconds 20}
}
'@|Set-Content -LiteralPath $probePath -Encoding utf8
    foreach($case in @('success','nonzero','timeout','owner-expired')){
        $pidPath=Join-Path $scratch ($case+'.pid');$value='two words "quoted" C:\path with spaces\'
        $deadline=if($case-ceq'owner-expired'){[datetime]::UtcNow.AddSeconds(-1)}else{[datetime]::UtcNow.AddSeconds(10)}
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $record=Invoke-DevFleetCampaignECandidateNativeLaunch -CandidateCommonModule $common -FilePath $engine -ArgumentList @('-NoProfile','-NonInteractive','-File',$probePath,'-Case',$case,'-Value',$value,'-PidPath',$pidPath) -MaximumSeconds 3 -OwnerDeadlineUtc $deadline
        $timer.Stop();$pass=$record.adapter-ceq'CANDIDATE_COMMON_INVOKE_EXTERNAL'-and$null-eq$record.pid-and$record.nativeMaximumSeconds-eq3-and([datetime]$record.deadlineUtc).ToUniversalTime()-le$deadline
        switch($case){
            success {$pass=$pass-and$record.outcome-ceq'PASS'-and$record.exitCode-eq0-and$record.outputComplete-and$record.stdout-ceq$value}
            nonzero {$pass=$pass-and$record.outcome-ceq'COMMAND_FAILED'-and$record.exitCode-eq7-and$record.outputComplete-and$record.stderr-match'controlled-native-failure'}
            timeout {$pass=$pass-and$record.outcome-ceq'TIMEOUT'-and$null-eq$record.exitCode-and$timer.Elapsed.TotalSeconds-lt8-and(Test-Path $pidPath);if(Test-Path $pidPath){$childId=[int](Get-Content $pidPath -Raw);$pass=$pass-and-not(Get-Process -Id $childId -ErrorAction SilentlyContinue)}}
            owner-expired {$pass=$pass-and$record.outcome-ceq'TIMEOUT'-and-not(Test-Path $pidPath)}
        }
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;outcome=$record.outcome;exitCode=$record.exitCode;elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,2);error=$record.stderr})
    }
}finally{
    $env:ProgramData=$priorData
    if([IO.Path]::GetDirectoryName($scratch)-ine[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')-or[IO.Path]::GetFileName($scratch)-notlike'astra-native-*'){throw 'Native regression cleanup escaped exact owned path.'}
    if(Test-Path $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
$results|ConvertTo-Json -Depth 3
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Actual candidate native launch regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) actual candidate Common native launch checks"
