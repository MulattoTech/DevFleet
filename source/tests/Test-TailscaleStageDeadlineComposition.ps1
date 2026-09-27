[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference = 'Stop'
$commonPath = Join-Path $WorkspaceRoot 'source/windows/DevFleet.Common.psm1'
Import-Module $commonPath -Force -DisableNameChecking

$windowsBudget = [int](Get-DevFleetStageBudgetSeconds 'windowsTailscale')
$guestBudget = [int](Get-DevFleetStageBudgetSeconds 'tailscale')

# The Windows stage owns service startup, browser handoff, and a real human
# approval. The exact Laptop run showed that 180 seconds could be consumed
# before the browser handoff became usable. Reuse the existing bounded guest
# pairing budget instead of introducing a second timeout policy.
if ($windowsBudget -ne 900) {
    throw "windowsTailscale stage budget must be 900 seconds for the bounded human pairing flow; observed $windowsBudget."
}
if ($windowsBudget -ne $guestBudget) {
    throw "Windows and guest Tailscale pairing budgets diverged: windows=$windowsBudget guest=$guestBudget."
}

[ordered]@{
    status = 'PASS'
    windowsTailscaleSeconds = $windowsBudget
    tailscaleSeconds = $guestBudget
    boundedHumanPairingBudgetAligned = $true
} | ConvertTo-Json -Compress
