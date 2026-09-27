$ErrorActionPreference='Stop'
$sourceRoot=Split-Path -Parent $PSScriptRoot
$bash='C:\Program Files\Git\bin\bash.exe'
if(-not(Test-Path -LiteralPath $bash -PathType Leaf)){throw 'Existing Git for Windows bash is required.'}
$passed=0;$failed=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{[void]$script:failed.Add($Name)}}
function UnixPath([string]$Path){$full=[IO.Path]::GetFullPath($Path).Replace('\','/');if($full -match '^([A-Za-z]):/(.*)$'){return '/'+$Matches[1].ToLowerInvariant()+'/'+$Matches[2]};return $full}
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-bootstrap-terminal-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $fixtureRoot|Out-Null
    foreach($entrypoint in @('bootstrap-compute.sh','bootstrap-vault.sh')){
        $component=if($entrypoint -eq 'bootstrap-compute.sh'){'rootlessRuntime'}else{'restServer'}
        $source=Get-Content -LiteralPath (Join-Path $sourceRoot "linux/$entrypoint") -Raw
        # Execute the production exit/error handlers; replace only their external
        # progress sink and temporary paths. No bootstrap provisioning is run.
        $handler=[regex]::Match($source,'(?ms)^(?:finish_bootstrap\(\).*?^\}|trap [^\r\n]+ EXIT)\r?\ntrap [^\r\n]+(?:\r?\ntrap [^\r\n]+)?').Value
        if(-not $handler){throw "No production terminal handler found in $entrypoint"}
        $cases=@(
            @{name='explicit rejection';body='exit 5';rc=5;markers='rootlessRuntime FAILED'},
            @{name='command failure';body='false';rc=1;markers='rootlessRuntime FAILED'},
            @{name='already timed out';body='write_progress "$CURRENT_COMPONENT" TIMED_OUT; COMPONENT_TERMINALIZED=1; exit 124';rc=124;markers='rootlessRuntime TIMED_OUT'},
            @{name='already failed';body='write_progress "$CURRENT_COMPONENT" FAILED; COMPONENT_TERMINALIZED=1; exit 4';rc=4;markers='rootlessRuntime FAILED'},
            @{name='success';body='CURRENT_COMPONENT=""; exit 0';rc=0;markers=''},
            @{name='failed progress sink';body='write_progress() { return 17; }; exit 5';rc=5;markers=''},
            @{name='cleanup failure after completion';body='CURRENT_COMPONENT=""; rm() { command rm "$@"; return 23; }; exit 0';rc=23;markers='bootstrap FAILED'},
            @{name='cleanup preserves primary failure';body='rm() { command rm "$@"; return 23; }; exit 5';rc=5;markers='rootlessRuntime FAILED'}
        )
        foreach($case in $cases){
            $caseRoot=Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $caseRoot|Out-Null
            $preamble=@'
set -Eeuo pipefail
cd "$1"
CURRENT_COMPONENT=__COMPONENT__
COMPONENT_TERMINALIZED=0
SECRETS_SOURCE="$PWD/secrets"
SECRETS_ENV_TMP="$PWD/secrets-env-temp"
DOCKER_KEY="$PWD/docker-key"
TAILSCALE_KEY="$PWD/tailscale-key"
NPM_TMP="$PWD/npm-temp"
touch "$SECRETS_SOURCE" "$DOCKER_KEY" "$TAILSCALE_KEY"
if [[ __COMPONENT__ == rootlessRuntime ]]; then printf 'fixture secret' > "$SECRETS_ENV_TMP"; fi
mkdir "$NPM_TMP"
write_progress() { printf '%s %s\n' "$1" "$2" >> "$PWD/markers"; }
'@
            $scriptPath=Join-Path $caseRoot 'probe.sh'
            [IO.File]::WriteAllText($scriptPath,($preamble.Replace('__COMPONENT__',$component)+"`n"+$handler+"`n"+$case.body+"`n").Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
            $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$bash;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
            foreach($arg in @('--noprofile','--norc',(UnixPath $scriptPath),(UnixPath $caseRoot))){[void]$psi.ArgumentList.Add($arg)}
            $process=[Diagnostics.Process]::Start($psi);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
            try{
                if(-not $process.WaitForExit(10000)){ $process.Kill($true);throw "Terminal handler timed out: $entrypoint/$($case.name)" }
                [void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait(3000))
                $markers=if(Test-Path -LiteralPath (Join-Path $caseRoot 'markers')){(Get-Content -LiteralPath (Join-Path $caseRoot 'markers') -Raw).Trim()}else{''}
                Check ($process.ExitCode -eq $case.rc -and $markers -ceq $case.markers.Replace('rootlessRuntime',$component)) "$entrypoint $($case.name) preserves original status and one terminal marker"
                $clean=-not(Test-Path -LiteralPath (Join-Path $caseRoot 'secrets'))
                if($entrypoint -eq 'bootstrap-compute.sh'){foreach($name in @('secrets-env-temp','docker-key','tailscale-key','npm-temp')){$clean=$clean -and -not(Test-Path -LiteralPath (Join-Path $caseRoot $name))}}
                Check $clean "$entrypoint $($case.name) cleans owned temporary inputs"
            }finally{if(-not $process.HasExited){$process.Kill($true)};$process.Dispose()}
        }
    }
    [ordered]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failed)}|ConvertTo-Json
    if($failed.Count){exit 1}
}finally{
    $resolved=[IO.Path]::GetFullPath($fixtureRoot);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'devfleet-bootstrap-terminal-*'){throw 'Fixture cleanup path rejected.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
