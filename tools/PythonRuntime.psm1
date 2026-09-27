Set-StrictMode -Version Latest

function Resolve-DevFleetPython {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace)
    $root = (Resolve-Path -LiteralPath $Workspace).Path
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in @('.venv-test\Scripts\python.exe','source\.venv-test\Scripts\python.exe','source\.venv-test-win\Scripts\python.exe')) {
        [void]$candidates.Add((Join-Path $root $relative))
    }
    foreach ($name in @('python.exe','python')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command -and $command.Source) { [void]$candidates.Add([string]$command.Source) }
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $version = @(& $candidate --version 2>&1)
            if ($LASTEXITCODE -eq 0 -and ($version -join ' ') -match '^Python 3\.') { return (Resolve-Path -LiteralPath $candidate).Path }
        } catch { }
    }
    throw 'No working repository-local or PATH Python 3 runtime is available.'
}

Export-ModuleMember -Function Resolve-DevFleetPython
