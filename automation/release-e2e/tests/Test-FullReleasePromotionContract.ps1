[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $WorkspaceRoot 'automation/release-e2e/modules/FullRelease.psm1'
Import-Module $modulePath -Force -DisableNameChecking
$checks = [Collections.Generic.List[object]]::new()

function Check([string]$Name, [bool]$Pass) {
    $checks.Add([pscustomobject]@{ name = $Name; pass = $Pass })
}

$runId = 'FullRelease-fixture-current'
$validResult = [pscustomobject]@{
    status = 'PASS'
    runId = $runId
    postCleanupFinalization = [pscustomobject]@{
        status = 'PASS'
        cleanupConsumed = $true
        reconcileAfterCleanup = $true
        liveChecks = [pscustomobject]@{ l1ExactOff = $true; l2ExactAbsent = $true }
    }
}

$state = @{
    full_release_run_id = $null
    full_release_current = $false
    full_release_passed = $false
    validation_evidence_current = $false
    internal_promotion_allowed = $false
    public_promotion_allowed = $false
    public_publisher_trust = $false
    status = 'IN_PROGRESS'
    release_status = 'IN_PROGRESS'
}
$promoted = $null
$promotionError = $null
try { $promoted = Set-FullReleasePassState -FinalizationState $state -Result $validResult -ExpectedRunId $runId } catch { $promotionError = $_.Exception.Message }
Check 'valid completed FullRelease promotes only its current evidence flags' (
    -not $promotionError -and
    [bool]$promoted.full_release_current -and
    [bool]$promoted.full_release_passed -and
    [bool]$promoted.validation_evidence_current -and
    -not [bool]$promoted.internal_promotion_allowed -and
    -not [bool]$promoted.public_promotion_allowed -and
    -not [bool]$promoted.public_publisher_trust -and
    [string]$promoted.full_release_run_id -ceq $runId
)

$rejectedState = @{
    full_release_run_id = $null
    full_release_current = $false
    full_release_passed = $false
    validation_evidence_current = $false
    internal_promotion_allowed = $false
    public_promotion_allowed = $false
    public_publisher_trust = $false
}
$blockedResult = [pscustomobject]@{
    status = 'BLOCKED'
    runId = $runId
    postCleanupFinalization = $validResult.postCleanupFinalization
}
$blockedError = $null
try { Set-FullReleasePassState -FinalizationState $rejectedState -Result $blockedResult -ExpectedRunId $runId | Out-Null } catch { $blockedError = $_.Exception.Message }
Check 'blocked FullRelease cannot promote any flag' (
    $blockedError -and
    -not [bool]$rejectedState.full_release_current -and
    -not [bool]$rejectedState.full_release_passed -and
    -not [bool]$rejectedState.validation_evidence_current
)

$mismatchState = @{
    full_release_run_id = $null
    full_release_current = $false
    full_release_passed = $false
    validation_evidence_current = $false
    internal_promotion_allowed = $false
    public_promotion_allowed = $false
    public_publisher_trust = $false
}
$mismatchError = $null
try { Set-FullReleasePassState -FinalizationState $mismatchState -Result $validResult -ExpectedRunId 'FullRelease-other-run' | Out-Null } catch { $mismatchError = $_.Exception.Message }
Check 'mismatched FullRelease RunId cannot promote any flag' (
    $mismatchError -and
    -not [bool]$mismatchState.full_release_current -and
    -not [bool]$mismatchState.full_release_passed -and
    -not [bool]$mismatchState.validation_evidence_current
)

$result = [ordered]@{
    status = if (@($checks | Where-Object { -not $_.pass }).Count) { 'FAIL' } else { 'PASS' }
    scope = 'LOCAL_FULLRELEASE_POSTCLEANUP_PROMOTION_BOUNDARY'
    passed = @($checks | Where-Object pass).Count
    total = $checks.Count
    checks = @($checks)
}
$result | ConvertTo-Json -Depth 8
if ($result.status -ne 'PASS') { exit 1 }
Write-Host "PASS $($result.passed)/$($result.total) FullRelease promotion checks; no VM, checkpoint, runtime, or auth operation performed."
