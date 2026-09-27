[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [switch]$FullLocalSweep
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
Set-Location -LiteralPath $WorkspaceRoot
if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
    $env:COMPUTERNAME = [Environment]::MachineName
}
if ([string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
    ${env:ProgramFiles(x86)} = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
}
$env:PYTHONDONTWRITEBYTECODE = '1'
$runId = 'preflight-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$outRoot = Join-Path $env:LOCALAPPDATA ('DevFleet\CertificationPreflight\' + $runId)
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$python = Join-Path $WorkspaceRoot '.venv-test\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Repository Python runtime is missing.' }
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\Candidate.psm1') -Force
$candidatePath = Join-Path $WorkspaceRoot 'outputs\DevFleet-Setup-v1.2.13-win-x64.exe'
$before = Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath $candidatePath
function Invoke-Captured {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][scriptblock]$Action)
    $log = Join-Path $outRoot ($Name + '.log')
    $global:LASTEXITCODE = 0
    $savedErrorActionPreference = $ErrorActionPreference
    $lines = @()
    $threw = $false
    try {
        $ErrorActionPreference = 'Continue'
        $lines = & $Action 2>&1
    } catch {
        $lines = @($_)
        $threw = $true
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    $code = if ($null -eq $global:LASTEXITCODE) { 0 } else { [int]$global:LASTEXITCODE }
    if ($threw -or @($lines | Where-Object {
        $_ -is [System.Management.Automation.ErrorRecord] -and
        [string]$_.FullyQualifiedErrorId -cne 'NativeCommandError'
    }).Count -gt 0) {
        if ($code -eq 0) { $code = 1 }
    }
    @($lines) | ForEach-Object { [string]$_ } | Set-Content -LiteralPath $log -Encoding utf8
    [pscustomobject]@{
        name = $Name
        exitCode = $code
        status = if ($code -eq 0) { 'PASS' } else { 'FAIL' }
        log = $log
        tail = @(@($lines) | Select-Object -Last 8 | ForEach-Object { [string]$_ })
    }
}
$checks = [System.Collections.Generic.List[object]]::new()
$readinessScript = Join-Path $WorkspaceRoot '.agents\skills\devfleet-certification-orchestrator\scripts\Test-DevFleetCertificationReadiness.ps1'
try {
    $readinessLines = & $readinessScript -WorkspaceRoot $WorkspaceRoot
    $readiness = (@($readinessLines) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
} catch {
    # Static readiness may be denied host inventory access in a lower-privilege
    # terminal. Keep that admission failure distinct and continue VM-free tests.
    $readinessBlocker = if ([string]$_.Exception.Message -match 'required permission|access denied|authorization policy') {
        'READINESS_HOST_AUTHORIZATION_DENIED'
    } else {
        'READINESS_CHECK_ERROR'
    }
    $readiness = [pscustomobject]@{ status = 'BLOCKED'; blockers = @($readinessBlocker) }
}
$checks.Add([pscustomobject]@{
    name='readiness'
    exitCode=if($readiness.status -like 'PASS*'){0}else{2}
    status=[string]$readiness.status
    log=$null
    tail=@($readiness.blockers)
})
$fastlane = Join-Path $WorkspaceRoot '.agents\skills\devfleet-e2e-fastlane\scripts\fastlane.py'
$checks.Add((Invoke-Captured -Name 'fastlane-quick' -Action {
    & $python -B $fastlane test --repo $WorkspaceRoot --area quick
}))
$toolTests = @(
    '.\tools\test_compute_shipping_input_identity.py',
    '.\tools\test_failed_attempt_freeze.py',
    '.\tools\test_final_acceptance_tools.py',
    '.\tools\test_release_tooling_corrections.py',
    '.\tools\test_validate_native_proof.py',
    '.\tools\test_validate_release_bundle.py'
)
$checks.Add((Invoke-Captured -Name 'release-tooling-pytest' -Action {
    & $python -B -m pytest -q -p no:cacheprovider @toolTests
}))
$checks.Add((Invoke-Captured -Name 'release-harness' -Action {
    & pwsh -NoLogo -NoProfile -File '.\automation\release-e2e\tests\Invoke-HarnessTests.ps1'
}))
$checks.Add((Invoke-Captured -Name 'audit-coherence' -Action {
    & $python -B '.\tools\validate_audit_coherence.py' --root $WorkspaceRoot
}))
$checks.Add((Invoke-Captured -Name 'git-diff-check' -Action {
    & git -C $WorkspaceRoot diff --check
}))
if ($FullLocalSweep) {
    $oldPythonPath = $env:PYTHONPATH
    try {
        $env:PYTHONPATH = Join-Path $WorkspaceRoot 'source\app'
        $checks.Add((Invoke-Captured -Name 'shipping-python-tests' -Action {
            & $python -B -m pytest -q -p no:cacheprovider '.\source\tests'
        }))
    } finally {
        $env:PYTHONPATH = $oldPythonPath
    }
    $dotnet = Join-Path $WorkspaceRoot '.dotnet\dotnet.exe'
    $checks.Add((Invoke-Captured -Name 'installer-tests' -Action {
        & $dotnet run --project '.\installer-source\DevFleet.Setup.Tests\DevFleet.Setup.Tests.csproj' -c Release --no-restore
    }))
}
$after = Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath $candidatePath
$tupleUnchanged =
    [string]$before.repositoryHead -ceq [string]$after.repositoryHead -and
    [string]$before.gitCommit -ceq [string]$after.gitCommit -and
    [string]$before.shippingInputIdentity -ceq [string]$after.shippingInputIdentity -and
    [string]$before.releaseFingerprintId -ceq [string]$after.releaseFingerprintId -and
    [string]$before.toolingFingerprintId -ceq [string]$after.toolingFingerprintId -and
    [string]$before.candidate.sha256 -ceq [string]$after.candidate.sha256
$failed = @($checks | Where-Object { [int]$_.exitCode -ne 0 })
$result = [ordered]@{
    schemaVersion = 1
    runId = $runId
    observedUtc = (Get-Date).ToUniversalTime().ToString('o')
    scope = 'VM_FREE_PRECERTIFICATION'
    liveGuestAuthRequested = $false
    fullLocalSweep = [bool]$FullLocalSweep
    certificationCredit = $false
    candidate = [ordered]@{
        repositoryHead = [string]$after.repositoryHead
        candidateBuildCommit = [string]$after.gitCommit
        shippingInputIdentity = [string]$after.shippingInputIdentity
        releaseFingerprintId = [string]$after.releaseFingerprintId
        toolingFingerprintId = [string]$after.toolingFingerprintId
        candidateSha256 = [string]$after.candidate.sha256
        unchangedDuringPreflight = [bool]$tupleUnchanged
    }
    checks = @($checks)
    status = if ($failed.Count -eq 0 -and $tupleUnchanged) { 'PASS' } else { 'BLOCKED' }
    blockers = @($failed | ForEach-Object { $_.name + ':' + $_.status })
    outputRoot = $outRoot
}
$result | ConvertTo-Json -Depth 12
if ($result.status -ne 'PASS') { exit 2 }
