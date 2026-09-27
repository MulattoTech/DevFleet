[CmdletBinding()]
param(
    [string]$ClientId = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\Secrets.psm1') -Force
if (-not $ClientId) { $ClientId = Read-Host 'Tailscale OAuth client ID (optional; direct client-secret enrollment does not require it)' }
$secret = Read-Host 'Tailscale OAuth client secret' -AsSecureString
try {
    $path = Save-DevFleetTailscaleOAuthCredential -ClientId $ClientId -ClientSecret $secret
    [pscustomobject]@{ status='PASS';provider='OAuthClientSecretStore';path=$path;secretPrinted=$false;secretInEvidence=$false } | ConvertTo-Json -Compress
} finally { $secret=$null }
