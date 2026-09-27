param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$modulePath=Join-Path $WorkspaceRoot 'automation/release-e2e/modules/MaintenanceVault.psm1'
Import-Module $modulePath -Force -DisableNameChecking
$module=Get-Module MaintenanceVault
$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-private-preservation-'+[guid]::NewGuid().ToString('N'))
$runDir=Join-Path $temp 'run'
$controlRoot=Join-Path $temp 'control'
[IO.Directory]::CreateDirectory($runDir)|Out-Null
[IO.Directory]::CreateDirectory($controlRoot)|Out-Null
$plain=[Text.Encoding]::UTF8.GetBytes("PRIVATE_TEST_EXCEPTION``nPRIVATE_STREAM_WARNING``n")
$runId='fullrelease-private-preservation-unit'
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$sourcePath='C:\ProgramData\DevFleet\tmp\maintenance-vault-unit\private-product-operations.log'
try{
    $metadata=& $module {
        param($bytes,$runId,$vmId,$sourcePath,$workspace,$runDir,$controlRoot)
        Protect-MaintenanceVaultPrivateFailureBytes -Plaintext $bytes -RunId $runId -VmId $vmId -SourcePath $sourcePath -WorkspaceRoot $workspace -RunDir $runDir -ControlRoot $controlRoot
    } $plain $runId $vmId $sourcePath $WorkspaceRoot $runDir $controlRoot
    if(-not$metadata.roundTripVerified-or$metadata.plaintextWrittenToHost-or$metadata.plaintextIncludedInAudit){throw 'DPAPI preservation metadata is not fail-closed.'}
    if([string]$metadata.encryption-cne'Windows DPAPI CurrentUser'){throw 'Unexpected private evidence encryption contract.'}
    $encryptedPath=[string]$metadata.encryptedLocalPath
    if(-not(Test-Path -LiteralPath $encryptedPath -PathType Leaf)){throw 'Encrypted private evidence file was not created.'}
    $encrypted=[IO.File]::ReadAllBytes($encryptedPath)
    if([Text.Encoding]::UTF8.GetString($encrypted)-match'PRIVATE_TEST_EXCEPTION'){throw 'Encrypted evidence contains plaintext marker.'}
    Add-Type -AssemblyName System.Security
    $entropy=[Text.Encoding]::UTF8.GetBytes("DevFleet exact failure evidence $runId")
    $round=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try{
        if([Text.Encoding]::UTF8.GetString($round)-cne[Text.Encoding]::UTF8.GetString($plain)){throw 'Independent DPAPI round-trip differs.'}
    } finally {if($round){[Array]::Clear($round,0,$round.Length)};if($entropy){[Array]::Clear($entropy,0,$entropy.Length)};if($encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}}
    $metadataPath=Join-Path $runDir 'private-failure-preservation.json'
    $persisted=Get-Content -LiteralPath $metadataPath -Raw|ConvertFrom-Json
    if(-not[bool]$persisted.roundTripVerified-or[string]$persisted.sourceVmId-cne$vmId.ToString()){throw 'Persisted preservation metadata is incomplete.'}
    if(Test-Path -LiteralPath (Join-Path $runDir 'private-product-operations.log')){throw 'Plaintext private log was written into run evidence.'}
    $source=Get-Content -LiteralPath $modulePath -Raw
    $call=$source.IndexOf('Save-MaintenanceVaultPrivateFailureEvidence -Session $session')
    $throw=$source.IndexOf("throw 'Configured Primary Vault bounded worker failed; see maintenance-vault-process.json.'",$call)
    if($call-lt0-or$throw-le$call){throw 'Failure branch does not preserve private evidence before public failure.'}
    if($source.IndexOf('maintenance-vault-windows-tailscale-preflight.json')-lt0){throw 'Sanitized Windows Tailscale pre-Vault telemetry is missing.'}
    [ordered]@{status='PASS';cases=7;dpapiRoundTrip=$true;plaintextHostFile=$false;preserveBeforeThrow=$true;tailscaleTelemetry=$true;vmMutation=$false}|ConvertTo-Json -Depth 4
} finally {
    if($plain){[Array]::Clear($plain,0,$plain.Length)}
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
