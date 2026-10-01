[CmdletBinding()]
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
$ErrorActionPreference = 'Stop'
$context = $ContextJson | ConvertFrom-Json -ErrorAction Stop
$tarPath = [string]$context.candidate.tar.path
$tarItem = Get-Item -LiteralPath $tarPath -ErrorAction Stop
$tarHash = (Get-FileHash -LiteralPath $tarItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($tarHash -ne [string]$context.candidate.tar.sha256 -or [int64]$tarItem.Length -ne [int64]$context.candidate.tar.bytes) { throw 'HTTP-HOSTILE exact candidate TAR identity changed.' }

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$python = if (Test-Path -LiteralPath (Join-Path $workspace '.venv-test\Scripts\python.exe')) { Join-Path $workspace '.venv-test\Scripts\python.exe' } else { (Get-Command python.exe -ErrorAction Stop).Source }
$extractRoot = Join-Path ([string]$context.runDir) 'HTTP-HOSTILE-extracted'
$outputPath = Join-Path ([string]$context.runDir) 'HTTP-HOSTILE-pytest.txt'
function Remove-HttpHostileExtract {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $maximumAttempts = 30
    for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        } catch [IO.IOException] {
            # Windows may briefly hold a just-extracted file after pytest exits.
            # Retry only ERROR_SHARING_VIOLATION; every other error fails immediately.
            if ($_.Exception.HResult -ne -2147024864 -or $attempt -eq $maximumAttempts) { throw }
            Start-Sleep -Milliseconds 1000
            continue
        }
        if (-not (Test-Path -LiteralPath $Path)) { return }
        throw 'HTTP-HOSTILE extracted cleanup remained incomplete.'
    }
}
$result = $null
$phaseError = $null
$cleanupError = $null
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
    $phaseError = $_
} finally {
    try {
        Remove-HttpHostileExtract -Path $extractRoot
    } catch {
        $cleanupError = $_
        $cleanupRecord = [ordered]@{
            status = 'FAIL'
            phase = 'HTTP-HOSTILE-CLEANUP'
            errorClass = $_.Exception.GetType().FullName
            hresult = [int]$_.Exception.HResult
            primaryFailurePresent = ($null -ne $phaseError)
        }
        try {
            $cleanupRecord | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path ([string]$context.runDir) 'HTTP-HOSTILE-cleanup.json') -Encoding utf8 -ErrorAction Stop
        } catch {
            Write-Warning 'HTTP-HOSTILE cleanup evidence could not be written.'
        }
    }
}
if ($null -ne $phaseError) { throw $phaseError }
if ($null -ne $cleanupError) { throw $cleanupError }
$result | ConvertTo-Json -Depth 8 -Compress
