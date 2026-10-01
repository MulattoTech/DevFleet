[CmdletBinding()]
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
$ErrorActionPreference = 'Stop'

function Test-DevFleetHttpHostileSharingViolation {
    param([System.Exception]$Exception)
    $cursor = $Exception
    while ($cursor) {
        if ($cursor -is [System.IO.IOException] -and [int]$cursor.HResult -eq -2147024864) {
            return $true
        }
        $cursor = $cursor.InnerException
    }
    return $false
}

function Remove-DevFleetHttpHostileExtraction {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 30)][int]$MaxAttempts = 30,
        [ValidateRange(1, 1000)][int]$DelayMilliseconds = 100
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        } catch {
            if (-not (Test-DevFleetHttpHostileSharingViolation -Exception $_.Exception) -or $attempt -ge $MaxAttempts) {
                throw
            }
            Start-Sleep -Milliseconds $DelayMilliseconds
            continue
        }
        if (Test-Path -LiteralPath $Path) {
            throw "HTTP-HOSTILE cleanup returned without removing extraction root: $Path"
        }
        return
    }
    if (Test-Path -LiteralPath $Path) {
        throw "HTTP-HOSTILE extraction cleanup exceeded its finite retry limit: $Path"
    }
}

$context = $ContextJson | ConvertFrom-Json -ErrorAction Stop
$tarPath = [string]$context.candidate.tar.path
$tarItem = Get-Item -LiteralPath $tarPath -ErrorAction Stop
$tarHash = (Get-FileHash -LiteralPath $tarItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($tarHash -ne [string]$context.candidate.tar.sha256 -or [int64]$tarItem.Length -ne [int64]$context.candidate.tar.bytes) { throw 'HTTP-HOSTILE exact candidate TAR identity changed.' }

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$python = if (Test-Path -LiteralPath (Join-Path $workspace '.venv-test\Scripts\python.exe')) { Join-Path $workspace '.venv-test\Scripts\python.exe' } else { (Get-Command python.exe -ErrorAction Stop).Source }
$extractRoot = Join-Path ([string]$context.runDir) 'HTTP-HOSTILE-extracted'
$outputPath = Join-Path ([string]$context.runDir) 'HTTP-HOSTILE-pytest.txt'
$cleanupErrorPath = Join-Path ([string]$context.runDir) 'HTTP-HOSTILE-cleanup-error.json'
$phaseFailure = $null
$cleanupFailure = $null
$result = $null

try {
    try {
        New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
        & tar.exe -xzf $tarItem.FullName -C $extractRoot
        if ($LASTEXITCODE -ne 0) { throw 'HTTP-HOSTILE exact candidate TAR extraction failed.' }
        $testPath = Join-Path $extractRoot 'tests\test_request_admission.py'
        if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) { throw 'HTTP-HOSTILE request-admission suite is absent from the exact candidate TAR.' }
        $priorPythonPath = $env:PYTHONPATH
        $priorPluginState = $env:PYTEST_DISABLE_PLUGIN_AUTOLOAD
        try {
            $env:PYTHONPATH = "$extractRoot;$extractRoot\app"
            $env:PYTEST_DISABLE_PLUGIN_AUTOLOAD = '1'
            $output = @(& $python -m pytest -q $testPath -rs 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            if ($null -eq $priorPythonPath) { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue } else { $env:PYTHONPATH = $priorPythonPath }
            if ($null -eq $priorPluginState) { Remove-Item Env:PYTEST_DISABLE_PLUGIN_AUTOLOAD -ErrorAction SilentlyContinue } else { $env:PYTEST_DISABLE_PLUGIN_AUTOLOAD = $priorPluginState }
        }
        $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        $text | Set-Content -LiteralPath $outputPath -Encoding utf8
        if ($exitCode -ne 0) { throw "HTTP-HOSTILE exact candidate regression failed; evidence=$outputPath" }
        $match = [regex]::Match($text, '(?m)(\d+) passed')
        if (-not $match.Success -or [int]$match.Groups[1].Value -lt 10) { throw 'HTTP-HOSTILE did not report the complete request-admission regression count.' }
        $result = [ordered]@{status='PASS';phase='HTTP-HOSTILE';contract='exact-candidate-asgi-request-admission-regression';tar=[ordered]@{path=$tarItem.FullName;bytes=[int64]$tarItem.Length;sha256=$tarHash};tests=[ordered]@{passed=[int]$match.Groups[1].Value;failed=0;outputPath=$outputPath};networkBeforeBody=$true;invalidTokenZeroConsumption=$true;declaredAndChunkedLimits=$true}
    } catch {
        $phaseFailure = $_
    }

    try {
        Remove-DevFleetHttpHostileExtraction -Path $extractRoot
    } catch {
        $cleanupFailure = $_
        [ordered]@{
            schemaVersion = 1
            phase = 'HTTP-HOSTILE'
            cleanupStatus = 'FAILED'
            primaryPhaseFailure = if ($phaseFailure) { [string]$phaseFailure.Exception.Message } else { $null }
            cleanupFailure = [string]$cleanupFailure.Exception.Message
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $cleanupErrorPath -Encoding utf8
    }

    if ($phaseFailure) { throw $phaseFailure }
    if ($cleanupFailure) { throw $cleanupFailure }
    if (Test-Path -LiteralPath $extractRoot) { throw 'HTTP-HOSTILE extraction root remains after successful cleanup.' }

    $result | ConvertTo-Json -Depth 8 -Compress
} finally {
    # Cleanup is intentionally handled before PASS publication above. Do not add
    # an unbounded or unconditional Remove-Item here; that would hide the
    # primary phase failure or recreate the Windows sharing-violation defect.
}
