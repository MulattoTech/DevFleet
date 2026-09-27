[CmdletBinding()]
param(
    [string]$WindowsRoot = (Join-Path $PSScriptRoot '../../../source/windows'),
    [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$WindowsRoot = (Resolve-Path -LiteralPath $WindowsRoot).Path
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'The installed caller requires PowerShell 7.' }
$results = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Pass) {
    $results.Add([pscustomobject]@{name=$Name;pass=$Pass})
}

# This is the actual dependency import order used by both shipping pairing scripts.
Import-Module (Join-Path $WindowsRoot 'DevFleet.Common.psm1') -Force -DisableNameChecking
$adminBefore = Get-Command Assert-Administrator -ErrorAction Stop
$commonExports = @((Get-Module DevFleet.Common).ExportedFunctions.Keys)
Import-Module (Join-Path $WindowsRoot 'DevFleet.Tailscale.psm1') -Force -DisableNameChecking
$adminAfter = Get-Command Assert-Administrator -ErrorAction SilentlyContinue
$pairingModule = Get-Module DevFleet.Tailscale
$nestedAdmin = & $pairingModule { Get-Command Assert-Administrator -ErrorAction SilentlyContinue }
Check 'Common administrator guard is visible before dependency import' ($null -ne $adminBefore)
Check 'Dependency import preserves caller administrator guard' ($null -ne $adminAfter)
Check 'Dependency retains its own Common command visibility' ($null -ne $nestedAdmin)
$expectedExports=@('Invoke-DevFleetTailscaleBrowserPairing','Invoke-DevFleetTailscaleOAuthPairing','Get-DevFleetTailscaleReadiness','Get-DevFleetTailscaleEnrollmentProfile','Get-DevFleetTailscaleOAuthSecretPath','Set-DevFleetTailscaleOAuthClientSecret')
$actualExports=@($pairingModule.ExportedFunctions.Keys)
Check 'Tailscale exports only the reviewed public pairing/readiness/credential entrypoints' ($actualExports.Count -eq $expectedExports.Count -and @($expectedExports|Where-Object{$actualExports -notcontains $_}).Count -eq 0 -and @($actualExports|Where-Object{$expectedExports -notcontains $_}).Count -eq 0)
$missingExports = @($commonExports | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
Check 'All normal caller Common exports remain visible' ($missingExports.Count -eq 0)

# Invoke the actual shipping script. The real administrator check runs unchanged;
# a caller-scope mock stops execution at the first external service boundary.
# No service, Tailscale CLI, browser, credential store or VM operation may run.
function Get-Service { throw 'LOCAL_FIXTURE_SERVICE_BOUNDARY_AFTER_REAL_ADMIN_GUARD' }
$scriptError = ''
try { & (Join-Path $WindowsRoot '04a-Connect-WindowsTailscale.ps1') }
catch { $scriptError = $_.Exception.Message }
Check 'Production Windows pairing script reaches external boundary after real guard' ($scriptError -eq 'LOCAL_FIXTURE_SERVICE_BOUNDARY_AFTER_REAL_ADMIN_GUARD')
Check 'Nested pairing caller can still resolve its Common helpers' ([bool](Get-Command Get-MultipassExe -ErrorAction SilentlyContinue) -and [bool](Get-Command Get-DevFleetStageBudgetSeconds -ErrorAction SilentlyContinue))

# Repeated stage imports are part of the same durable installer process.
Import-Module (Join-Path $WindowsRoot 'DevFleet.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $WindowsRoot 'DevFleet.Tailscale.psm1') -Force -DisableNameChecking
Check 'Repeated production import order preserves caller guard' ([bool](Get-Command Assert-Administrator -ErrorAction SilentlyContinue))
$privateHelpers = & (Get-Module DevFleet.Tailscale) {
    [bool](Get-Command Get-DevFleetDeadlineContext -ErrorAction SilentlyContinue) -and
    [bool](Get-Command Invoke-External -ErrorAction SilentlyContinue)
}
Check 'Repeated dependency load preserves internal deadline and process helpers' ([bool]$privateHelpers)

$report = [ordered]@{
    status = if (@($results | Where-Object { -not $_.pass }).Count) {'FAIL'} else {'PASS'}
    runtime = $PSVersionTable.PSVersion.ToString()
    scope = 'LOCAL_PRODUCTION_IMPORT_AND_SCRIPT_EXTERNAL_BOUNDARY_NO_RUNTIME_PROOF'
    actualScriptError = $scriptError
    callerCommonExportCount = $commonExports.Count
    missingCallerExports = $missingExports
    inputHashes = @(foreach ($name in @('DevFleet.Common.psm1','DevFleet.Tailscale.psm1','04a-Connect-WindowsTailscale.ps1')) {
        [ordered]@{name=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $WindowsRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    results = @($results)
    passed = @($results | Where-Object pass).Count
    total = $results.Count
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding utf8
[pscustomobject]@{status=$report.status;passed=$report.passed;total=$report.total;actualScriptError=$scriptError;missingCallerExportCount=$missingExports.Count} | ConvertTo-Json -Compress
if ($report.status -ne 'PASS') { exit 1 }
