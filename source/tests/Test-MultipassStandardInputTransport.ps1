[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$sourceRoot=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $sourceRoot 'windows/DevFleet.Common.psm1') -Force -DisableNameChecking
$module=Get-Module DevFleet.Common
$bash='C:\Program Files\Git\bin\bash.exe'
$python=(Get-Command python.exe -ErrorAction Stop).Source
if(-not(Test-Path $bash)){throw 'Existing Git Bash is required for the local shell boundary tests.'}
function UnixPath([string]$Path){$p=[IO.Path]::GetFullPath($Path).Replace('\','/');if($p-match'^([A-Za-z]):/(.*)$'){return '/'+$Matches[1].ToLowerInvariant()+'/'+$Matches[2]};$p}
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ("devfleet-input transport O'Hara "+[guid]::NewGuid().ToString('N'))
$checks=[Collections.Generic.List[object]]::new()
$priorContext=Get-DevFleetDeadlineContext
try {
    New-Item -ItemType Directory -Path $fixtureRoot|Out-Null
    $bin=Join-Path $fixtureRoot 'bin';New-Item -ItemType Directory -Path $bin|Out-Null
    # jq is an external dependency. Use a real JSON parser for this local
    # fixture, while executing the production Bash input helper unchanged.
    $jq=@'
#!/usr/bin/env bash
"$DEVFLEET_TEST_PYTHON" -c 'import json,sys; value=json.load(open(sys.argv[-1],encoding="utf-8")); sys.exit(0 if isinstance(value,dict) else 1)' "$(cygpath -w "${@: -1}")"
'@
    [IO.File]::WriteAllText((Join-Path $bin 'jq'),$jq.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
    & $bash --noprofile --norc -c ('chmod +x -- '+(ConvertTo-ShellSingleQuotedScalar (UnixPath (Join-Path $bin 'jq'))))
    if($LASTEXITCODE-ne0){throw 'Local JSON parser fixture could not be made executable.'}
    $originalExternal=& $module {(Get-Command Invoke-External).ScriptBlock}
    $parserProbe=Join-Path $fixtureRoot 'parser-probe.json'
    [IO.File]::WriteAllText($parserProbe,'{"kind":"dummy"}',[Text.UTF8Encoding]::new($false))
    $parserCommand='export DEVFLEET_TEST_PYTHON='+(ConvertTo-ShellSingleQuotedScalar (UnixPath $python))+'; '+(ConvertTo-ShellSingleQuotedScalar (UnixPath (Join-Path $bin 'jq')))+' -e '+(ConvertTo-ShellSingleQuotedScalar 'type == "object"')+' '+(ConvertTo-ShellSingleQuotedScalar (UnixPath $parserProbe))
    & $originalExternal $bash @('--noprofile','--norc','-c',$parserCommand) -TimeoutSeconds 10
    & $module {param($original)$script:TransportOriginalExternal=$original} $originalExternal
    & $module {
        function script:Invoke-External {
            param($FilePath,[string[]]$ArgumentList,[int]$TimeoutSeconds,[datetime]$DeadlineUtc,[string]$StandardInputText,[switch]$Capture)
            $s=$script:TransportFixture;$index=$s.calls.Count+1
            $s.calls.Add([pscustomobject]@{index=$index;verb=$ArgumentList[0];hasInput=([bool]$StandardInputText);argumentContainsDummy=([bool](($ArgumentList-join' ').Contains($s.dummy)));deadline=$DeadlineUtc;timeout=$TimeoutSeconds})
            if($ArgumentList[0]-ceq'transfer'){
                if($ArgumentList[1]-cne'-'-or$ArgumentList[2]-notmatch'^[A-Za-z0-9._-]+:/run/devfleet-input-[0-9a-f]{32}/input$'){throw 'Unexpected transfer framing.'}
                $program='import pathlib,sys; p=pathlib.Path(sys.argv[1]); assert p.is_file(); data=sys.stdin.buffer.read(); p.write_bytes(data); sys.exit(int(sys.argv[2]))'
                $exitCode=if($s.mode-in@('transfer-failure','combined-failure')){77}else{0}
                & $script:TransportOriginalExternal $s.python @('-c',$program,$s.localInput,[string]$exitCode) -StandardInputText $StandardInputText -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $DeadlineUtc
                $s.transferredSha256=(Get-FileHash -LiteralPath $s.localInput -Algorithm SHA256).Hash.ToLowerInvariant()
                $s.transferredBytes=(Get-Item -LiteralPath $s.localInput).Length
                if($s.mode-ceq'bad-file-mode'){& $script:TransportOriginalExternal $s.bash @('--noprofile','--norc','-c',('chmod 0644 -- '+(ConvertTo-ShellSingleQuotedScalar $s.unixInput))) -TimeoutSeconds 5}
                return
            }
            if($ArgumentList[0]-cne'exec'-or$ArgumentList[2]-cne'--'-or$ArgumentList[3]-cne'bash'-or$ArgumentList[4]-cne'-lc'-or$StandardInputText){throw 'Unexpected exec or secret bytes on exec.'}
            if(($s.mode-ceq'cleanup-failure'-and$index-eq4)-or($s.mode-ceq'combined-failure'-and$index-eq3)){throw 'fixture cleanup unavailable'}
            $command=[string]$ArgumentList[5]
            $match=[regex]::Match($command,'/run/devfleet-input-[0-9a-f]{32}')
            if(-not$match.Success){throw 'No exact private input path.'}
            $remoteDirectory=$match.Value
            $command=$command.Replace((ConvertTo-ShellSingleQuotedScalar ($remoteDirectory+'/input')),(ConvertTo-ShellSingleQuotedScalar $s.unixInput)).Replace((ConvertTo-ShellSingleQuotedScalar $remoteDirectory),(ConvertTo-ShellSingleQuotedScalar $s.unixDirectory))
            if($s.mode-ceq'prepare-collision'-and$index-eq1){New-Item -ItemType Directory -Path $s.localDirectory|Out-Null;[IO.File]::WriteAllText((Join-Path $s.localDirectory 'foreign-marker'),'keep')}
            # Git Bash cannot enforce Linux mkdir modes on the inherited
            # Windows ACL. Map sudo/mode observations as external OS I/O;
            # keep real creation, collision, content, redirection and unlink.
            $modeFailure=if($s.mode-ceq'bad-file-mode'-and$index-ge3){'1'}else{'0'}
            $prepareFailure=if($s.mode-ceq'prepare-partial-failure'){'1'}else{'0'}
            $prefix='sudo(){ if [[ "$1" == mkdir ]]; then command mkdir -- "${@: -1}"; elif [[ "$1" == chown && "$DEVFLEET_TEST_PREPARE_FAILURE" == 1 ]]; then return 42; else "$@"; fi; }; stat(){ if [[ "$2" == "%a:%u" ]]; then if [[ "${@: -1}" == */input ]]; then if [[ "$DEVFLEET_TEST_BAD_MODE" == 1 ]]; then printf "644:%s\n" "$(id -u)"; else printf "600:%s\n" "$(id -u)"; fi; else printf "700:%s\n" "$(id -u)"; fi; else command stat "$@"; fi; }; export -f sudo stat; export DEVFLEET_TEST_PREPARE_FAILURE='+$prepareFailure+'; export DEVFLEET_TEST_BAD_MODE='+$modeFailure+'; export PATH='+(ConvertTo-ShellSingleQuotedScalar $s.unixBin)+':"$PATH"; export DEVFLEET_TEST_PYTHON='+(ConvertTo-ShellSingleQuotedScalar $s.unixPython)+'; export DEVFLEET_TEST_STAGE_DIR='+(ConvertTo-ShellSingleQuotedScalar $s.unixDirectory)+'; '
            & $script:TransportOriginalExternal $s.bash @('--noprofile','--norc','-c',($prefix+$command)) -TimeoutSeconds $TimeoutSeconds -DeadlineUtc $DeadlineUtc -Capture:$Capture
        }
    }
    foreach($mode in @('success','unicode','transfer-failure','consumer-failure','bad-file-mode','prepare-collision','prepare-partial-failure','cleanup-failure','combined-failure','expired-owner','short-stage','bad-identity','bad-command','empty-input')){
        $caseRoot=Join-Path $fixtureRoot $mode;New-Item -ItemType Directory -Path $caseRoot|Out-Null
        $dummy=if($mode-ceq'unicode'){'{"kind":"dummy café","value":"quote\" and escaped\nline"}'}else{'{"kind":"dummy"}'}
        if($mode-ceq'empty-input'){$dummy=''}
        $state=[pscustomobject]@{mode=$mode;dummy=$dummy;calls=[Collections.Generic.List[object]]::new();transferredSha256='';transferredBytes=0;bash=$bash;python=$python;localDirectory=(Join-Path $caseRoot 'stage');localInput=(Join-Path $caseRoot 'stage/input');unixDirectory=(UnixPath (Join-Path $caseRoot 'stage'));unixInput=(UnixPath (Join-Path $caseRoot 'stage/input'));unixBin=(UnixPath $bin);unixPython=(UnixPath $python)}
        & $module {param($state)$script:TransportFixture=$state} $state
        $global:DevFleetDeadlineContext=$null
        $helper=ConvertTo-ShellSingleQuotedScalar (UnixPath (Join-Path $sourceRoot 'linux/bootstrap-input.sh'))
        $consumer='set -Eeuo pipefail; test ! -e "$DEVFLEET_TEST_STAGE_DIR"; source '+$helper+'; captured=$(devfleet_capture_json_stdin "$1/captured.XXXXXX" $(($(date +%s)+3))); trap ''rm -f -- "$captured"'' EXIT; sha256sum "$captured" | cut -d " " -f 1'
        if($mode-ceq'consumer-failure'){$consumer='exit 23'}
        if($mode-ceq'bad-command'){$consumer="echo invalid`ncommand"}
        $deadline=[datetime]::UtcNow.AddSeconds(45)
        if($mode-ceq'expired-owner'){$deadline=[datetime]::UtcNow.AddSeconds(5)}
        if($mode-ceq'short-stage'){Set-DevFleetDeadlineContext -TransactionDeadlineUtc ([datetime]::UtcNow.AddSeconds(5)) -StageName 'test' -StageBudgetSeconds 5|Out-Null}
        $name=if($mode-ceq'bad-identity'){'foreign;command'}else{'devfleet-primary'}
        $output='';$errorText='';$timer=[Diagnostics.Stopwatch]::StartNew()
        try{$output=Invoke-MultipassWithStandardInput -FilePath 'fixture-multipass.exe' -InstanceName $name -CommandArgumentList @('bash','-c',$consumer,'--',(UnixPath $caseRoot)) -StandardInputText $dummy -TimeoutSeconds 45 -DeadlineUtc $deadline -Capture}catch{$errorText=$_.Exception.Message}
        $timer.Stop()
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($dummy))).ToLowerInvariant()
        $exists=Test-Path $state.localDirectory
        $secretOnlyOnTransfer=@($state.calls|Where-Object{$_.hasInput-and$_.verb-cne'transfer'}).Count-eq0
        $noSecretArgs=@($state.calls|Where-Object argumentContainsDummy).Count-eq0
        $bounded=@($state.calls|Where-Object{$_.deadline-gt$deadline.AddSeconds(-5)}).Count-eq0
        if($state.calls.Count-ge2){$bounded=$bounded-and($state.calls[0].deadline-le$deadline.AddSeconds(-15))-and($state.calls[1].deadline-le$deadline.AddSeconds(-15))}
        $pass=switch($mode){
            {$_-in@('success','unicode')} {$output.Trim()-ceq$hash-and-not$errorText-and-not$exists-and$state.calls.Count-eq4;break}
            'transfer-failure' {$errorText-match'exit code 77'-and-not$exists-and$state.calls.Count-eq3;break}
            'consumer-failure' {$errorText-match'exit code 23'-and-not$exists-and$state.calls.Count-eq4;break}
            'bad-file-mode' {$errorText-match'exit code 1'-and-not$exists-and$state.calls.Count-eq4;break}
            'prepare-collision' {$errorText-match'exit code 1'-and(Test-Path (Join-Path $state.localDirectory 'foreign-marker'))-and$state.calls.Count-eq1;break}
            'prepare-partial-failure' {$errorText-match'exit code 42'-and-not$exists-and$state.calls.Count-eq1;break}
            'cleanup-failure' {$errorText-match'cleanup unavailable'-and-not$exists-and$state.calls.Count-eq4;break}
            'combined-failure' {$errorText-match'exit code 77'-and$errorText-match'Guest input cleanup failed'-and$errorText-match'cleanup unavailable'-and$exists-and$state.calls.Count-eq3;break}
            default {$errorText-and$state.calls.Count-eq0-and-not$exists}
        }
        $checks.Add([pscustomobject]@{case=$mode;pass=[bool]($pass-and$secretOnlyOnTransfer-and$noSecretArgs-and$bounded-and(-not$dummy-or-not$errorText.Contains($dummy)));calls=$state.calls.Count;elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3);stagingRemains=$exists;transferredBytes=$state.transferredBytes;expectedBytes=[Text.Encoding]::UTF8.GetByteCount($dummy);transferredHashMatches=($state.transferredSha256-ceq$hash);error=if($pass){''}else{$errorText}})
    }
} finally {
    $global:DevFleetDeadlineContext=$priorContext
    $resolved=[IO.Path]::GetFullPath($fixtureRoot);$tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not$resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup escaped the temporary directory.'}
    if(Test-Path $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
[pscustomobject]@{status=if(@($checks|Where-Object{-not$_.pass}).Count){'FAIL'}else{'PASS'};passed=@($checks|Where-Object pass).Count;total=$checks.Count;checks=@($checks);vmOperations=0;realMultipassOperations=0;fixtureBoundary='Multipass external I/O, remote filesystem root/sudo and Linux mode observations are fixtures. Production orchestration, shell parsing, collision rejection, input helper, JSON parser, native stdin writer, file content/EOF and unlink execute locally. Linux ACL enforcement requires the actual guest gate.'}|ConvertTo-Json -Depth 5
if(@($checks|Where-Object{-not$_.pass}).Count){exit 1}
