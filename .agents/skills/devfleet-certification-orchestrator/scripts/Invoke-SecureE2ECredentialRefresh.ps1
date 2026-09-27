[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference = 'Stop'
$expectedWorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = $expectedWorkspaceRoot
}
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
if (-not [string]::Equals($WorkspaceRoot, $expectedWorkspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Secure credential refresh must use the checkout containing this script.'
}
if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
    $env:COMPUTERNAME = [Environment]::MachineName
}

$current = [Security.Principal.WindowsIdentity]::GetCurrent()
if ([string]$current.Name -cne 'MULATTOTECHBOX\Dylan') {
    throw "Secure E2E credential refresh must run as MULATTOTECHBOX\Dylan, not $($current.Name)."
}
$principal = [Security.Principal.WindowsPrincipal]::new($current)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Secure E2E credential refresh requires the elevated Dylan token.'
}

$vm = Get-VM -ComputerName localhost -Id ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ErrorAction Stop
if ([string]$vm.Name -cne 'DevFleet-E2E-Win11-01') {
    throw 'Exact disposable L1 GUID/name identity mismatch.'
}
if ([string]$vm.State -cne 'Off') {
    throw "Exact disposable L1 must be Off before credential refresh; observed $($vm.State)."
}
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\Candidate.psm1') -Force
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\BaselineLineage.psm1') -Force
$fingerprint = Get-CandidateFingerprint -WorkspaceRoot $WorkspaceRoot -CandidatePath (Join-Path $WorkspaceRoot 'outputs\DevFleet-Setup-v1.2.13-win-x64.exe')
$baseline = Get-DevFleetAcceptedBaseline -WorkspaceRoot $WorkspaceRoot -Fingerprint $fingerprint
$checkpoints = @(Get-VMSnapshot -ComputerName localhost -VMName 'DevFleet-E2E-Win11-01' -Name ([string]$baseline.name) -ErrorAction Stop)
if ($checkpoints.Count -ne 1 -or $checkpoints[0].Id -ne [guid][string]$baseline.id -or $checkpoints[0].VMId -ne $vm.Id -or (-not $baseline.legacyOriginal -and $checkpoints[0].ParentSnapshotId -ne [guid][string]$baseline.predecessorId)) {
    throw 'Accepted CLEAN checkpoint GUID/name/parent identity mismatch.'
}

$initializer = Join-Path $WorkspaceRoot 'automation\release-e2e\Initialize-DevFleetE2ESecrets.ps1'
if (-not (Test-Path -LiteralPath $initializer -PathType Leaf)) {
    throw 'Repository-native secure initializer is missing.'
}

Write-Host ''
Write-Host 'SECURE LOCAL INPUT REQUIRED'
Write-Host 'Username must be exactly: E2EAdmin'
Write-Host 'Enter the disposable-lab password only at the local SecureString prompt.'
Write-Host 'Do not paste the password into ChatGPT, Codex, a subagent, a command line, or a file.'
Write-Host ''
& (Get-Command pwsh.exe -ErrorAction Stop).Source -NoProfile -File $initializer
if ($LASTEXITCODE -ne 0) {
    throw "Repository-native secure initializer exited with code $LASTEXITCODE."
}
Write-Host ''
Write-Host 'Credential store updated. This does NOT prove the password is correct.'
Write-Host 'Run Test-DevFleetCertificationReadiness.ps1 -LiveGuestAuth before reserving a proof.'
