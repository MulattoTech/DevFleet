[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

$modulePath = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\WpfLaunchContract.psm1'
$passed = 0
$failures = New-Object 'System.Collections.Generic.List[string]'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-wpf-ps51-provider-' + [guid]::NewGuid().ToString('N'))

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

function New-TestSpecification([string]$LaunchId) {
    [pscustomobject]@{
        runId = 'wpf-ps51-provider-regression'
        launchId = $LaunchId
        transactionId = ('2' * 32)
        payloadSha256 = ('3' * 64)
        candidateSha256 = ('4' * 64)
        driverDeadlineUtc = [datetime]::UtcNow.AddMinutes(5).ToString('o')
        semanticNoProgressSeconds = 120
    }
}

function New-CapturedTerminal([object]$Specification, [string]$Capture) {
    [pscustomobject]@{
        schemaVersion = 2
        contract = 'devfleet-wpf-terminal-v2'
        status = 'PASS'
        terminal = $true
        completionVerified = $true
        runId = [string]$Specification.runId
        launchId = [string]$Specification.launchId
        transactionId = [string]$Specification.transactionId
        payloadSha256 = [string]$Specification.payloadSha256
        candidateSha256 = [string]$Specification.candidateSha256
        sequence = 8
        cleanupDisposition = 'CLEANUP_EXACT_CANDIDATE'
        deadlineUtc = [string]$Specification.driverDeadlineUtc
        capture = $Capture
    }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Import-Module $modulePath -Force

    Check ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1) 'regression executes under actual Windows PowerShell 5.1 semantics'

    $capturedValue = 'captured-through-provider-closure'
    $script:successStopped = $false
    $script:successTerminalWrites = 0
    $successSpec = New-TestSpecification -LaunchId ('5' * 32)
    $success = Wait-WpfBoundReport -Specification $successSpec `
        -ReportProvider { New-CapturedTerminal -Specification $successSpec -Capture $capturedValue } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:successStopped = $true } `
        -ProviderCallTimeoutSeconds 2 `
        -TerminalWriter { param($value) $script:successTerminalWrites++; $value }
    Check ([string]$success.status -eq 'PASS' -and [string]$success.capture -ceq $capturedValue -and -not $script:successStopped -and $script:successTerminalWrites -eq 0) 'PowerShell 5.1 provider execution preserves captured variables and caller helper functions'

    $script:throwingStopped = $false
    $script:throwingTerminalWrites = 0
    $throwingSpec = New-TestSpecification -LaunchId ('6' * 32)
    $throwing = Wait-WpfBoundReport -Specification $throwingSpec `
        -ReportProvider { throw 'controlled PS51 original provider error' } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:throwingStopped = $true } `
        -ProviderCallTimeoutSeconds 2 `
        -TerminalWriter { param($value) $script:throwingTerminalWrites++; $value }
    Check ([string]$throwing.failureClass -eq 'REPORT_PROVIDER_FAILURE' -and [string]$throwing.error -match 'controlled PS51 original provider error' -and $throwing.productStarted -eq $true -and $script:throwingStopped -and $script:throwingTerminalWrites -eq 1) 'PowerShell 5.1 provider failure preserves the original error and terminalizes once'

    $cancelledPath = Join-Path $scratch 'never-provider-cancelled.txt'
    $script:neverStopped = $false
    $script:neverTerminalWrites = 0
    $neverSpec = New-TestSpecification -LaunchId ('7' * 32)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $never = Wait-WpfBoundReport -Specification $neverSpec `
        -ReportProvider { try { while ($true) { Start-Sleep -Milliseconds 100 } } finally { [IO.File]::WriteAllText($cancelledPath, 'cancelled') } } `
        -WorkerStateProvider { 'Running' } `
        -StopWorker { $script:neverStopped = $true } `
        -ProviderCallTimeoutSeconds 1 `
        -TerminalWriter { param($value) $script:neverTerminalWrites++; $value }
    $timer.Stop()
    $cancelDeadline = [datetime]::UtcNow.AddSeconds(2)
    while (-not (Test-Path -LiteralPath $cancelledPath -PathType Leaf) -and [datetime]::UtcNow -lt $cancelDeadline) { Start-Sleep -Milliseconds 50 }
    Check ([string]$never.failureClass -eq 'REPORT_PROVIDER_TIMEOUT' -and $never.productStarted -eq $true -and $script:neverStopped -and $script:neverTerminalWrites -eq 1 -and $timer.Elapsed.TotalMilliseconds -ge 800 -and $timer.Elapsed.TotalSeconds -lt 6) 'PowerShell 5.1 never-returning provider cannot defeat the bounded supervisor deadline'
    Check (Test-Path -LiteralPath $cancelledPath -PathType Leaf) 'PowerShell 5.1 never-returning provider is actively cancelled before terminalization completes'

    $summary = [pscustomobject]@{
        status = if ($failures.Count) { 'FAIL' } else { 'PASS' }
        engine = $PSVersionTable.PSVersion.ToString()
        startThreadJobAvailable = [bool](Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
        passed = $passed
        total = $passed + $failures.Count
        failures = @($failures)
    }
    $summary | ConvertTo-Json -Depth 6
    if ($failures.Count) { exit 1 }
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
