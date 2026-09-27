[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$skillRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$readinessScript = Join-Path $skillRoot 'scripts\Test-DevFleetCertificationReadiness.ps1'
$preflightScript = Join-Path $skillRoot 'scripts\Invoke-DevFleetCertificationPreflight.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('devfleet-cert-orchestrator-' + [guid]::NewGuid().ToString('N'))
$oldLocalAppData = $env:LOCALAPPDATA
$passes = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passes++
}
try {
    $moduleRoot = Join-Path $fixture 'automation\release-e2e\modules'
    $storeParent = Join-Path $fixture 'DevFleet\E2E'
    $tokenParent = Join-Path $fixture 'evidence'
    New-Item -ItemType Directory -Force -Path $moduleRoot,$storeParent,$tokenParent | Out-Null
    $env:LOCALAPPDATA = $fixture
    Set-Content -LiteralPath (Join-Path $storeParent 'secrets.json') -Value 'fixture metadata only' -NoNewline
    @'
function Get-CandidateFingerprint {
    [pscustomobject]@{
        repositoryHead='head'; gitCommit='build'; shippingInputIdentity='shipping'
        releaseFingerprintId='release'; toolingFingerprintId='tooling'
        candidate=[pscustomobject]@{sha256='exe'}
    }
}
Export-ModuleMember -Function Get-CandidateFingerprint
'@ | Set-Content -LiteralPath (Join-Path $moduleRoot 'Candidate.psm1')
    @'
function Get-HostSafetySnapshot {
    [pscustomobject]@{startSafe=$true; availableMemoryGiB=32; projectedPostStartAvailableMemoryGiB=24}
}
Export-ModuleMember -Function Get-HostSafetySnapshot
'@ | Set-Content -LiteralPath (Join-Path $moduleRoot 'HostSafety.psm1')
    'Export-ModuleMember -Function @()' | Set-Content -LiteralPath (Join-Path $moduleRoot 'GuestSession.psm1')
    Copy-Item -LiteralPath (Join-Path $skillRoot '..\..\..\automation\release-e2e\modules\BaselineLineage.psm1') -Destination (Join-Path $moduleRoot 'BaselineLineage.psm1')
    '{"runId":"fixture-token","status":"PASS","standardNonAdministratorToken":true,"repositoryHead":"head","candidateBuildCommit":"build","shippingInputIdentity":"shipping","releaseFingerprintId":"release","toolingFingerprintId":"tooling","exe":{"sha256":"exe"}}' |
        Set-Content -LiteralPath (Join-Path $tokenParent 'CURRENT-STANDARD-TOKEN.json')

    $script:mutations = 0
    $global:fixtureVmId = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
    $global:fixtureCleanId = [guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'
    function Get-VM { [pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=$global:fixtureVmId;State='Off'} }
    function Get-VMSnapshot { [pscustomobject]@{Name='DevFleet-E2E-CLEAN';Id=$global:fixtureCleanId;VMId=$global:fixtureVmId;ParentSnapshotId=[guid]::Empty} }
    function Restore-VMSnapshot { $script:mutations++; throw 'Fixture must never restore a VM.' }
    function Start-VM { $script:mutations++; throw 'Fixture must never start a VM.' }
    function Get-DevFleetE2ECredential { throw 'Fixture must never load a protected credential.' }

    $static = (& $readinessScript -WorkspaceRoot $fixture | ConvertFrom-Json)
    Assert-True ($static.status -ceq 'PASS_STATIC_REQUIRES_LIVE_GUEST_AUTH') 'Static readiness status was wrong.'
    Assert-True ($static.staticPrerequisitesPass -eq $true) 'Static prerequisites did not pass.'
    Assert-True ($static.credential.storePresent -eq $true -and $null -eq $static.credential.exactUser) 'Static readiness claimed credential contents.'
    Assert-True ($static.credential.available -eq $false) 'Static readiness claimed to have loaded a credential.'
    Assert-True ($script:mutations -eq 0) 'Static readiness mutated the lab.'

    $live = (& $readinessScript -WorkspaceRoot $fixture -LiveGuestAuth | ConvertFrom-Json)
    Assert-True ($live.status -ceq 'BLOCKED') 'Live readiness without diagnostic admission did not block.'
    Assert-True ($live.blockers -contains 'NATIVE_DIAGNOSTIC_ADMISSION_UNVERIFIED') 'Diagnostic admission blocker was missing.'
    Assert-True ($live.staticPrerequisitesPass -eq $true) 'Live admission blocker incorrectly changed static prerequisite status.'
    Assert-True ($script:mutations -eq 0) 'Unadmitted live readiness mutated the lab.'

    $invalidFresh = (& $readinessScript -WorkspaceRoot $fixture -LiveGuestAuth -FreshLedgerPath (Join-Path $fixture 'missing-ledger.json') -FreshRunId 'fixture-new' | ConvertFrom-Json)
    Assert-True ($invalidFresh.blockers -contains 'FRESH_DIAGNOSTIC_ADMISSION_INVALID') 'Invalid fresh journal was admitted.'
    Assert-True ($script:mutations -eq 0 -and $invalidFresh.credential.available -eq $false) 'Invalid fresh admission contacted the lab or loaded a credential.'

    $global:fixtureVmId = [guid]::NewGuid()
    $wrongVm = (& $readinessScript -WorkspaceRoot $fixture | ConvertFrom-Json)
    Assert-True ($wrongVm.blockers -contains 'EXACT_LAB_IDENTITY_MISMATCH') 'Wrong L1 GUID was accepted.'
    Assert-True ($wrongVm.status -ceq 'BLOCKED' -and $script:mutations -eq 0) 'Wrong L1 GUID reached mutation.'
    $global:fixtureVmId = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
    $global:fixtureCleanId = [guid]::NewGuid()
    $wrongClean = (& $readinessScript -WorkspaceRoot $fixture | ConvertFrom-Json)
    Assert-True ($wrongClean.blockers -contains 'EXACT_LAB_IDENTITY_MISMATCH') 'Wrong CLEAN GUID was accepted.'
    Assert-True ($wrongClean.status -ceq 'BLOCKED' -and $script:mutations -eq 0) 'Wrong CLEAN GUID reached mutation.'

    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($preflightScript,[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) 'Preflight script has a parser error.'
    $capture = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-Captured'},$true)
    Assert-True ($null -ne $capture) 'Preflight capture function is missing.'
    . ([scriptblock]::Create($capture.Extent.Text))
    $captureRoot = Join-Path $fixture 'capture'
    New-Item -ItemType Directory -Force -Path $captureRoot | Out-Null
    $outRoot = $captureRoot
    $nonterminating = Invoke-Captured -Name 'nonterminating' -Action { Write-Error 'synthetic fixture failure' }
    Assert-True ($nonterminating.status -ceq 'FAIL' -and $nonterminating.exitCode -ne 0) 'Nonterminating PowerShell error was masked.'
    $clean = Invoke-Captured -Name 'clean' -Action { 'fixture success' }
    Assert-True ($clean.status -ceq 'PASS' -and $clean.exitCode -eq 0) 'Clean PowerShell action was rejected.'
    $terminating = Invoke-Captured -Name 'terminating' -Action { throw 'synthetic terminating failure' }
    Assert-True ($terminating.status -ceq 'FAIL' -and $terminating.exitCode -ne 0) 'Terminating PowerShell error was masked.'
    $native = Invoke-Captured -Name 'native-exit' -Action { & $PSHOME\pwsh.exe -NoProfile -Command 'exit 7' }
    Assert-True ($native.status -ceq 'FAIL' -and $native.exitCode -eq 7) 'Native nonzero exit was masked.'
    $nativeWarning = Invoke-Captured -Name 'native-warning' -Action { & $PSHOME\pwsh.exe -NoProfile -Command '[Console]::Error.WriteLine("fixture warning"); exit 0' }
    Assert-True ($nativeWarning.status -ceq 'PASS' -and $nativeWarning.exitCode -eq 0) 'Successful native stderr was mistaken for a PowerShell error.'
    "PASS $passes VM-free orchestrator assertions"
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    Remove-Variable fixtureVmId,fixtureCleanId -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
