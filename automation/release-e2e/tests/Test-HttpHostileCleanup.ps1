[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Host 'SKIP Windows HTTP-HOSTILE cleanup sharing-violation fixture'
    return
}

$executorPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/executors/Invoke-HttpHostilePhase.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($executorPath,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'HTTP-HOSTILE executor has PowerShell parse errors.' }

$functionNames = @('Test-DevFleetHttpHostileSharingViolation','Remove-DevFleetHttpHostileExtraction')
foreach ($name in $functionNames) {
    $matches = @($ast.FindAll({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
    },$true))
    if ($matches.Count -ne 1) { throw "Expected exactly one production helper named $name." }
    . ([scriptblock]::Create($matches[0].Extent.Text))
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-http-cleanup-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
try {
    # 1. Real Windows sharing violation: another process retries until the held
    # handle is released, then removes the extraction root.
    $realLockRoot = Join-Path $scratch 'real-lock'
    [void][IO.Directory]::CreateDirectory($realLockRoot)
    $heldPath = Join-Path $realLockRoot 'held.txt'
    [IO.File]::WriteAllText($heldPath,'held')
    $held = [IO.File]::Open($heldPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $helperText = (@($ast.FindAll({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in @('Test-DevFleetHttpHostileSharingViolation','Remove-DevFleetHttpHostileExtraction')
    },$true)) | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine
    $job = Start-Job -ScriptBlock {
        param($text,$path)
        . ([scriptblock]::Create($text))
        Remove-DevFleetHttpHostileExtraction -Path $path -MaxAttempts 30 -DelayMilliseconds 50
        [pscustomobject]@{status='RETURNED';exists=(Test-Path -LiteralPath $path)}
    } -ArgumentList $helperText,$realLockRoot
    Start-Sleep -Milliseconds 250
    if ($job.State -eq 'Completed') {
        $early = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        throw "Sharing-violation cleanup returned before the held handle was released: $($early | ConvertTo-Json -Compress)"
    }
    $held.Dispose()
    $held = $null
    if (-not (Wait-Job -Job $job -Timeout 10)) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        throw 'Sharing-violation cleanup exceeded its finite test deadline.'
    }
    $jobOutput = @(Receive-Job -Job $job -ErrorAction Stop)
    if ($jobOutput.Count -ne 1 -or $jobOutput[0].status -cne 'RETURNED' -or $jobOutput[0].exists) {
        throw 'Sharing-violation cleanup did not remove the extraction root after handle release.'
    }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    $job = $null

    # 2. Non-sharing failures must fail immediately rather than being retried.
    $nonSharingRoot = Join-Path $scratch 'non-sharing'
    [void][IO.Directory]::CreateDirectory($nonSharingRoot)
    $script:nonSharingCalls = 0
    $nonSharingThrew = $false
    & {
        function Remove-Item {
            param([string]$LiteralPath,[switch]$Recurse,[switch]$Force,[object]$ErrorAction)
            $script:nonSharingCalls++
            throw [System.InvalidOperationException]::new('synthetic non-sharing cleanup failure')
        }
        try {
            Remove-DevFleetHttpHostileExtraction -Path $nonSharingRoot -MaxAttempts 30 -DelayMilliseconds 1
        } catch {
            $script:nonSharingThrew = $true
        }
    }
    if (-not $script:nonSharingThrew -or $script:nonSharingCalls -ne 1) {
        throw 'Non-sharing cleanup failure was retried or escaped detection.'
    }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $nonSharingRoot -Recurse -Force

    # 3. A cleanup call that returns without deleting the directory must fail
    # closed immediately; it is not a retryable sharing violation.
    $leftBehindRoot = Join-Path $scratch 'left-behind'
    [void][IO.Directory]::CreateDirectory($leftBehindRoot)
    $script:leftBehindCalls = 0
    $leftBehindThrew = $false
    & {
        function Remove-Item {
            param([string]$LiteralPath,[switch]$Recurse,[switch]$Force,[object]$ErrorAction)
            $script:leftBehindCalls++
        }
        try {
            Remove-DevFleetHttpHostileExtraction -Path $leftBehindRoot -MaxAttempts 30 -DelayMilliseconds 1
        } catch {
            $script:leftBehindThrew = $true
        }
    }
    if (-not $script:leftBehindThrew -or $script:leftBehindCalls -ne 1) {
        throw 'Cleanup that left the extraction root behind did not fail immediately.'
    }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $leftBehindRoot -Recurse -Force

    # 4. Guard the top-level contract: PASS serialization must occur only after
    # cleanup, and a phase failure must be rethrown before a cleanup failure.
    $source = [IO.File]::ReadAllText($executorPath)
    $cleanupCall = $source.LastIndexOf('Remove-DevFleetHttpHostileExtraction -Path $extractRoot',[StringComparison]::Ordinal)
    $phaseThrow = $source.LastIndexOf('if ($phaseFailure) { throw $phaseFailure }',[StringComparison]::Ordinal)
    $cleanupThrow = $source.LastIndexOf('if ($cleanupFailure) { throw $cleanupFailure }',[StringComparison]::Ordinal)
    $passOutput = $source.LastIndexOf('$result | ConvertTo-Json -Depth 8 -Compress',[StringComparison]::Ordinal)
    if ($cleanupCall -lt 0 -or $phaseThrow -le $cleanupCall -or $cleanupThrow -le $phaseThrow -or $passOutput -le $cleanupThrow) {
        throw 'HTTP-HOSTILE PASS/error ordering no longer preserves cleanup and primary-failure semantics.'
    }
    if ($source -notmatch 'HTTP-HOSTILE-cleanup-error\.json') {
        throw 'HTTP-HOSTILE executor no longer records a separate cleanup failure envelope.'
    }

    Write-Host 'PASS HTTP-HOSTILE cleanup retries sharing violations, fails closed otherwise, and publishes PASS only after cleanup'
} finally {
    if ($job) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
    if ($held) { $held.Dispose() }
    $resolved = [IO.Path]::GetFullPath($scratch)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^devfleet-http-cleanup-[a-f0-9]{32}$') {
        throw 'HTTP-HOSTILE cleanup fixture path rejected.'
    }
    if (Test-Path -LiteralPath $resolved) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
