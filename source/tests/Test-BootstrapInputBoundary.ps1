$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$helperPath = Join-Path $sourceRoot 'linux\bootstrap-input.sh'
$computePath = Join-Path $sourceRoot 'linux\bootstrap-compute.sh'
$vaultPath = Join-Path $sourceRoot 'linux\bootstrap-vault.sh'
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) { throw 'Repository-local shell regression requires the existing Git for Windows bash runtime.' }

$failed = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{[void]$script:failed.Add($Name)}}
function ConvertTo-MsysPath([string]$Path){$full=[IO.Path]::GetFullPath($Path).Replace('\','/');if($full -match '^([A-Za-z]):/(.*)$'){return ('/'+$Matches[1].ToLowerInvariant()+'/'+$Matches[2])};return $full}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-bootstrap-input-' + [guid]::NewGuid().ToString('N'))
try {
    $bin = Join-Path $fixtureRoot 'bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    $jqPath = Join-Path $bin 'jq'
    $jqStub = @'
#!/usr/bin/env bash
last=''
for argument in "$@"; do last=$argument; done
content=$(cat -- "$last")
[[ "$content" =~ ^\{.*\}$ ]]
'@
    [IO.File]::WriteAllText($jqPath,$jqStub.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
    $fixtureUnix=ConvertTo-MsysPath $fixtureRoot
    $helperUnix=ConvertTo-MsysPath $helperPath
    $probeScript=@'
chmod +x "$1/bin/jq"
export PATH="$1/bin:$PATH"
source "$2"
deadline=$(($(date +%s)+${DEVFLEET_TEST_INPUT_SECONDS:-3}))
secret_path=$(devfleet_capture_json_stdin "$1/secret.XXXXXX" "$deadline")
rc=$?
size=0
if [[ -n "$secret_path" && -f "$secret_path" ]]; then size=$(wc -c <"$secret_path"); rm -f -- "$secret_path"; fi
count=$(find "$1" -maxdepth 1 -type f -name 'secret.*' | wc -l)
printf 'RC=%s;SIZE=%s;COUNT=%s' "$rc" "$size" "$count"
exit 0
'@
    function Invoke-InputProbe {
        param([AllowEmptyString()][string]$InputText,[switch]$Withhold,[int]$InputSeconds=3,[int]$OuterSeconds=7)
        $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$bash;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.Environment['DEVFLEET_TEST_INPUT_SECONDS']=[string]$InputSeconds
        foreach($argument in @('--noprofile','--norc','-c',$probeScript,'--',$fixtureUnix,$helperUnix)){[void]$psi.ArgumentList.Add($argument)}
        $process=[Diagnostics.Process]::Start($psi);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$timer=[Diagnostics.Stopwatch]::StartNew()
        try {
            if(-not $Withhold){$process.StandardInput.Write($InputText);$process.StandardInput.Close()}
            $finished=$process.WaitForExit($OuterSeconds*1000)
            if(-not $finished){try{$process.Kill($true)}catch{};[void]$process.WaitForExit(3000)}
            $timer.Stop();[void]([Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout,$stderr)).Wait([TimeSpan]::FromSeconds(3)))
            [pscustomobject]@{finished=$finished;elapsed=$timer.Elapsed.TotalSeconds;stdout=if($stdout.IsCompletedSuccessfully){$stdout.Result}else{''};stderr=if($stderr.IsCompletedSuccessfully){$stderr.Result}else{''}}
        } finally {if(-not $process.HasExited){try{$process.Kill($true)}catch{}};$process.Dispose()}
    }

    foreach($scriptPath in @($helperPath,$computePath,$vaultPath)){
        & $bash --noprofile --norc -n (ConvertTo-MsysPath $scriptPath)
        Check ($LASTEXITCODE -eq 0) "shell syntax is valid for $([IO.Path]::GetFileName($scriptPath))"
    }
    function Invoke-InvalidIdentityEntrypoint {
        param([string]$ScriptPath,[string]$PackageVersion,[string]$NodeRole)
        $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$bash;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        foreach($argument in @('--noprofile','--norc',(ConvertTo-MsysPath $ScriptPath),'/nonexistent-devfleet-test-payload','--secrets-stdin','--transaction-id','invalid','--payload-sha256',('b'*64),'--bootstrap-max-seconds','30','--package-version',$PackageVersion,'--node-role',$NodeRole)){[void]$psi.ArgumentList.Add($argument)}
        $process=[Diagnostics.Process]::Start($psi);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$timer=[Diagnostics.Stopwatch]::StartNew()
        try{$finished=$process.WaitForExit(3000);$timer.Stop();if(-not$finished){try{$process.Kill($true)}catch{}};[pscustomobject]@{finished=$finished;exitCode=if($finished){$process.ExitCode}else{$null};elapsed=$timer.Elapsed.TotalSeconds}}
        finally{if(-not$process.HasExited){try{$process.Kill($true)}catch{}};$process.Dispose()}
    }
    $computeIdentity=Invoke-InvalidIdentityEntrypoint -ScriptPath $computePath -PackageVersion '1.2.13' -NodeRole 'primary'
    $vaultIdentity=Invoke-InvalidIdentityEntrypoint -ScriptPath $vaultPath -PackageVersion 'vault' -NodeRole 'vault'
    Check ($computeIdentity.finished -and $computeIdentity.exitCode -eq 64 -and $computeIdentity.elapsed -lt 2) 'compute entrypoint rejects invalid identity before waiting on withheld stdin'
    Check ($vaultIdentity.finished -and $vaultIdentity.exitCode -eq 64 -and $vaultIdentity.elapsed -lt 2) 'Vault entrypoint rejects invalid identity before waiting on withheld stdin'
    $valid=Invoke-InputProbe -InputText '{"kind":"dummy"}'
    Check ($valid.finished -and $valid.stdout -match 'RC=0;SIZE=16;COUNT=0') 'valid dummy JSON and EOF are captured once and caller cleanup removes the secret file'
    $empty=Invoke-InputProbe -InputText ''
    Check ($empty.finished -and $empty.stdout -match 'RC=65;SIZE=0;COUNT=0') 'empty stdin fails distinctly and removes its temporary secret file'
    $invalid=Invoke-InputProbe -InputText 'not-json'
    Check ($invalid.finished -and $invalid.stdout -match 'RC=65;SIZE=0;COUNT=0') 'invalid JSON fails distinctly and removes its temporary secret file'
    $truncated=Invoke-InputProbe -InputText '{"kind":'
    Check ($truncated.finished -and $truncated.stdout -match 'RC=65;SIZE=0;COUNT=0') 'truncated JSON fails distinctly and removes its temporary secret file'
    $withheld=Invoke-InputProbe -InputText '' -Withhold -InputSeconds 2 -OuterSeconds 6
    Check ($withheld.finished -and $withheld.stdout -match 'RC=124;SIZE=0;COUNT=0' -and $withheld.elapsed -lt 4.5) 'withheld stdin is terminated by the same finite input deadline and removes its temporary file'
} finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failed);observed=[ordered]@{valid=$valid.stdout;empty=$empty.stdout;invalid=$invalid.stdout;truncated=$truncated.stdout;withheld=$withheld.stdout}}|ConvertTo-Json -Depth 4
if($failed.Count){exit 1}
