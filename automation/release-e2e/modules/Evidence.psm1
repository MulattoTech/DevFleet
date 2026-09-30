Set-StrictMode -Version Latest

function New-RunEvidenceDirectory {
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunId)
    if($RunId.Length -gt 128 -or $RunId -cnotmatch '\A[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'){
        throw 'RunId must contain only non-empty ASCII alphanumeric segments separated by single hyphens.'
    }
    $runsRoot=[IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'audit\automation-harness\runs')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $path=[IO.Path]::GetFullPath((Join-Path $runsRoot $RunId))
    $ownedPrefix=$runsRoot+[IO.Path]::DirectorySeparatorChar
    if(-not $path.StartsWith($ownedPrefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -cne $RunId){
        throw 'Run evidence path escaped the canonical runs root.'
    }
    [void][IO.Directory]::CreateDirectory($path)
    $path
}

function Write-EvidenceJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Value)
    $json=$Value | ConvertTo-Json -Depth 32
    for($attempt=1;$attempt -le 4;$attempt++) {
        try {
            $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
            [IO.File]::WriteAllText($tmp,$json,(New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
            return
        } catch {
            if($attempt -eq 4){throw}
            Start-Sleep -Milliseconds (100*$attempt)
        } finally {
            if($tmp -and (Test-Path -LiteralPath $tmp)){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
        }
    }
}
function Write-EvidenceText { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string[]]$Lines); $Lines | Set-Content -LiteralPath $Path -Encoding utf8 }

function New-GateRecord {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][ValidateSet('PASS','IMPLEMENTED','UNIT/INTEGRATION TESTED','REAL E2E PASS','FAIL','BLOCKED','USER ACTION REQUIRED','SKIPPED','SKIP — platform prerequisite','NOT RUN','NOT APPLICABLE')][string]$Status,[string]$Details)
    [pscustomobject]@{ name=$Name; status=$Status; details=$Details; timestamp=(Get-Date).ToUniversalTime().ToString('o') }
}

Export-ModuleMember -Function New-RunEvidenceDirectory,Write-EvidenceJson,Write-EvidenceText,New-GateRecord
