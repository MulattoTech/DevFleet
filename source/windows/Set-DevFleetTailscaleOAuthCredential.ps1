[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Tailscale.psm1') -Force
Assert-PowerShell7
Assert-Administrator

Write-Host 'DevFleet Tailscale OAuth setup' -ForegroundColor Cyan
Write-Host 'Paste the OAuth client secret only into the local secure prompt. It is never sent to Codex, printed, or placed in a command argument.' -ForegroundColor DarkGray
$secret = Read-Host 'Tailscale OAuth client secret' -AsSecureString
try {
    $path = Set-DevFleetTailscaleOAuthClientSecret -Secret $secret
    [pscustomobject]@{
        status = 'PASS'
        provider = 'OAuthClientSecret'
        storage = 'DevFleet protected local state ACL'
        path = $path
        secretPrinted = $false
        secretInEvidence = $false
    } | ConvertTo-Json -Compress
} finally {
    $secret = $null
}
