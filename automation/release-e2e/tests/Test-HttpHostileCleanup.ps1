[CmdletBinding()]
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
$ErrorActionPreference='Stop'
$WorkspaceRoot=(Resolve-Path -LiteralPath $WorkspaceRoot).Path
$executor=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-HttpHostilePhase.ps1'
$tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
$fixture=[IO.Path]::GetFullPath((Join-Path $tempPrefix ('DevFleet-HttpHostile-Cleanup-'+[guid]::NewGuid().ToString('N'))))
if(-not $fixture.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($fixture) -cnotmatch '^DevFleet-HttpHostile-Cleanup-[0-9a-f]{32}$'){throw 'Fixture root is outside the intended temporary directory.'}

$global:HttpHostileFixture=@{targetExtract=$null;mockMode=$null;cleanupCalls=0;sleepCalls=0;heldHandle=$null}
function global:Remove-Item {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Path,[string]$LiteralPath,[switch]$Recurse,[switch]$Force)
    if($LiteralPath -and $LiteralPath.Equals([string]$global:HttpHostileFixture.targetExtract,[StringComparison]::OrdinalIgnoreCase)){
        $global:HttpHostileFixture.cleanupCalls++
        if($global:HttpHostileFixture.mockMode -eq 'persistent' -or ($global:HttpHostileFixture.mockMode -eq 'transient' -and $global:HttpHostileFixture.cleanupCalls -eq 1) -or ($global:HttpHostileFixture.mockMode -eq 'long-transient' -and $global:HttpHostileFixture.cleanupCalls -le 20)){
            throw [Runtime.InteropServices.Marshal]::GetExceptionForHR(-2147024864)
        }
        if($global:HttpHostileFixture.mockMode -eq 'phase-and-cleanup'){
            throw [Runtime.InteropServices.Marshal]::GetExceptionForHR(-2147024864)
        }
        if($global:HttpHostileFixture.mockMode -eq 'no-op'){return}
        if($global:HttpHostileFixture.mockMode -eq 'access-denied'){
            throw [UnauthorizedAccessException]::new('Fixture access denied')
        }
    }
    Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
}
function global:Start-Sleep {
    [CmdletBinding()]
    param([int]$Milliseconds)
    $global:HttpHostileFixture.sleepCalls++
    if($global:HttpHostileFixture.mockMode -eq 'real-lock' -and $global:HttpHostileFixture.heldHandle){
        $global:HttpHostileFixture.heldHandle.Dispose()
        $global:HttpHostileFixture.heldHandle=$null
    }
}

function Invoke-FixtureCase([string]$Mode,[string]$TarPath,[string]$TarSha,[int64]$TarBytes){
    $runDir=Join-Path $fixture $Mode
    New-Item -ItemType Directory -Path $runDir -Force|Out-Null
    $global:HttpHostileFixture.targetExtract=Join-Path $runDir 'HTTP-HOSTILE-extracted'
    $global:HttpHostileFixture.mockMode=$Mode
    $global:HttpHostileFixture.cleanupCalls=0
    $global:HttpHostileFixture.sleepCalls=0
    $global:HttpHostileFixture.heldHandle=$null
    if($Mode -eq 'real-lock'){
        New-Item -ItemType Directory -Path $global:HttpHostileFixture.targetExtract -Force|Out-Null
        $heldFile=Join-Path $global:HttpHostileFixture.targetExtract 'held.txt'
        [IO.File]::WriteAllText($heldFile,'held')
        $global:HttpHostileFixture.heldHandle=[IO.File]::Open($heldFile,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    }
    $context=[ordered]@{candidate=[ordered]@{tar=[ordered]@{path=$TarPath;sha256=$TarSha;bytes=$TarBytes}};runDir=$runDir}|ConvertTo-Json -Depth 5 -Compress
    $messages=[Collections.Generic.List[string]]::new()
    $failure=$null
    try { & $executor -ContextJson $context | ForEach-Object { $messages.Add([string]$_) } }
    catch { $failure=$_.Exception.Message }
    finally {
        if($global:HttpHostileFixture.heldHandle){
            $global:HttpHostileFixture.heldHandle.Dispose()
            $global:HttpHostileFixture.heldHandle=$null
        }
    }
    $cleanupPath=Join-Path $runDir 'HTTP-HOSTILE-cleanup.json'
    $cleanupRecord=if(Test-Path -LiteralPath $cleanupPath){Get-Content -LiteralPath $cleanupPath -Raw|ConvertFrom-Json}else{$null}
    [pscustomobject]@{mode=$Mode;failure=$failure;messages=@($messages);cleanupCalls=$global:HttpHostileFixture.cleanupCalls;sleepCalls=$global:HttpHostileFixture.sleepCalls;extractExists=(Test-Path -LiteralPath $global:HttpHostileFixture.targetExtract);cleanupRecord=$cleanupRecord}
}

try {
    $payload=Join-Path $fixture 'payload'
    $tests=Join-Path $payload 'tests'
    New-Item -ItemType Directory -Path $tests -Force|Out-Null
    @'
import pytest

@pytest.mark.parametrize("case", range(10))
def test_request_admission(case):
    assert case < 10
'@ | Set-Content -LiteralPath (Join-Path $tests 'test_request_admission.py') -Encoding utf8
    $tarPath=Join-Path $fixture 'candidate.tar.gz'
    & tar.exe -czf $tarPath -C $payload .
    if($LASTEXITCODE -ne 0){throw 'Fixture TAR creation failed.'}
    $tarSha=(Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $tarBytes=(Get-Item -LiteralPath $tarPath).Length

    $transient=Invoke-FixtureCase -Mode transient -TarPath $tarPath -TarSha $tarSha -TarBytes $tarBytes
    if($transient.failure -or $transient.cleanupCalls -lt 2 -or $transient.sleepCalls -lt 1 -or $transient.extractExists -or $transient.messages.Count -ne 1){throw "Transient sharing violation did not recover: $($transient|ConvertTo-Json -Compress)"}
    $passed=$transient.messages[0]|ConvertFrom-Json
    if($passed.status -cne 'PASS' -or $passed.tests.passed -ne 10){throw 'Recovered phase did not report the complete exact-candidate test PASS.'}

    $realLock=Invoke-FixtureCase -Mode real-lock -TarPath $tarPath -TarSha $tarSha -TarBytes $tarBytes
    if($realLock.failure -or $realLock.cleanupCalls -ne 2 -or $realLock.sleepCalls -ne 1 -or $realLock.extractExists -or $realLock.messages.Count -ne 1){throw "Real Windows handle lock did not recover: $($realLock|ConvertTo-Json -Compress)"}

    $longTransient=Invoke-FixtureCase -Mode long-transient -TarPath $tarPath -TarSha $tarSha -TarBytes $tarBytes
    if($longTransient.failure -or $longTransient.cleanupCalls -ne 21 -or $longTransient.sleepCalls -ne 20 -or $longTransient.extractExists -or $longTransient.messages.Count -ne 1){throw "Twenty bounded sharing violations did not recover: $($longTransient|ConvertTo-Json -Compress)"}

    $persistent=Invoke-FixtureCase -Mode persistent -TarPath $tarPath -TarSha $tarSha -TarBytes $tarBytes
    if(-not $persistent.failure -or $persistent.cleanupCalls -ne 30 -or $persistent.sleepCalls -ne 29 -or -not $persistent.extractExists -or $persistent.messages.Count -or $persistent.cleanupRecord.status -cne 'FAIL' -or $persistent.cleanupRecord.primaryFailurePresent -ne $false){throw "Persistent sharing violation did not fail closed with bounded retries: $($persistent|ConvertTo-Json -Compress)"}

    $denied=Invoke-FixtureCase -Mode access-denied -TarPath $tarPath -TarSha $tarSha -TarBytes $tarBytes
    if(-not $denied.failure -or $denied.cleanupCalls -ne 1 -or $denied.sleepCalls -ne 0 -or -not $denied.extractExists -or $denied.messages.Count -or $denied.cleanupRecord.status -cne 'FAIL' -or $denied.cleanupRecord.primaryFailurePresent -ne $false){throw "Non-sharing access denial was retried or promoted: $($denied|ConvertTo-Json -Compress)"}

    $noOp=Invoke-FixtureCase -Mode no-op -TarPath $tarPath -TarSha $tarSha -TarBytes $tarBytes
    if(-not $noOp.failure -or $noOp.cleanupCalls -ne 1 -or $noOp.sleepCalls -ne 0 -or -not $noOp.extractExists -or $noOp.messages.Count){throw "No-op cleanup was retried or promoted: $($noOp|ConvertTo-Json -Compress)"}

    $failingPayload=Join-Path $fixture 'failing-payload'
    $failingTests=Join-Path $failingPayload 'tests'
    New-Item -ItemType Directory -Path $failingTests -Force|Out-Null
    @'
import pytest

@pytest.mark.parametrize("case", range(10))
def test_request_admission(case):
    assert case < 9
'@ | Set-Content -LiteralPath (Join-Path $failingTests 'test_request_admission.py') -Encoding utf8
    $failingTar=Join-Path $fixture 'failing-candidate.tar.gz'
    & tar.exe -czf $failingTar -C $failingPayload .
    if($LASTEXITCODE -ne 0){throw 'Failing fixture TAR creation failed.'}
    $failingSha=(Get-FileHash -LiteralPath $failingTar -Algorithm SHA256).Hash.ToLowerInvariant()
    $failingBytes=(Get-Item -LiteralPath $failingTar).Length
    $combined=Invoke-FixtureCase -Mode phase-and-cleanup -TarPath $failingTar -TarSha $failingSha -TarBytes $failingBytes
    if($combined.failure -notlike 'HTTP-HOSTILE exact candidate regression failed*' -or $combined.cleanupCalls -ne 30 -or $combined.messages.Count -or $combined.cleanupRecord.status -cne 'FAIL' -or $combined.cleanupRecord.phase -cne 'HTTP-HOSTILE-CLEANUP' -or $combined.cleanupRecord.hresult -ne -2147024864 -or $combined.cleanupRecord.primaryFailurePresent -ne $true){throw "Phase failure was masked or cleanup evidence was lost: $($combined|ConvertTo-Json -Depth 5 -Compress)"}

    [ordered]@{status='PASS';scope='HTTP_HOSTILE_CLEANUP_VM_FREE';transientCalls=$transient.cleanupCalls;realLockCalls=$realLock.cleanupCalls;longTransientCalls=$longTransient.cleanupCalls;persistentCalls=$persistent.cleanupCalls;accessDeniedCalls=$denied.cleanupCalls;noOpCalls=$noOp.cleanupCalls;combinedFailureCalls=$combined.cleanupCalls;releaseCredit=$false}|ConvertTo-Json -Compress
} finally {
    if(Test-Path -LiteralPath $fixture){Microsoft.PowerShell.Management\Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction Stop}
    Microsoft.PowerShell.Management\Remove-Item Function:\Remove-Item,Function:\Start-Sleep -ErrorAction SilentlyContinue
    Remove-Variable -Name HttpHostileFixture -Scope Global -ErrorAction SilentlyContinue
}
