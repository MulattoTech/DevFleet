param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/FullRelease.psm1') -Force -DisableNameChecking
$module=Get-Module FullRelease
$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-fixture-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $temp 'audit/automation-harness'))|Out-Null
& $module {
    param($temp)
    $script:trace=[Collections.Generic.List[string]]::new();$script:created=$false
    $script:testVm=[pscustomobject]@{Name='DevFleet-E2E-Unit';Id=[guid]::NewGuid();State='Off'}
    $script:snapshot=[pscustomobject]@{Name='DevFleet-E2E-MAINTENANCE-READY';Id=[guid]::NewGuid()}
    function script:Get-AssertedDisposableVm {param($ExpectedVm) return $script:testVm}
    function script:Get-VMSnapshot {param($VM,$ErrorAction) if($script:created){$script:snapshot}}
    function script:Get-ExactCheckpoint {param($Vm,$Name) return $script:snapshot}
    function script:Restore-ExactCheckpoint {param($Vm,$Name,[switch]$StartAfterRestore) return [pscustomobject]@{id=$script:snapshot.Id;name=$Name}}
    function script:Invoke-MaintenanceReadyProductLifecycle {param($WorkspaceRoot,$Context) $script:trace.Add('provision-primary');return [pscustomobject]@{status='PASS'}}
    function script:Initialize-MaintenanceVaultFixture {param($Context) $script:trace.Add('configure-vault');return [pscustomobject]@{status='PASS';configurationPresent=$true;authenticatedTransport=$true;proofCredit=$false;primaryRole='primary';payloadSha256=('a'*64);primaryId='11111111-1111-1111-1111-111111111111';vaultId='22222222-2222-2222-2222-222222222222';deploymentId='33333333-3333-3333-3333-333333333333'}}
    function script:Invoke-MaintenanceReadyGuestValidation {param($VmId,$Fingerprint) return [pscustomobject]@{status='PASS';installationGeneration='unit-generation';devFleetVersion='1.2.13';installerVersion='1.2.13';packageSha256=('a'*64);installLedgerSha256=('b'*64);ownershipSchemaVersion=1;ownershipLedgerSha256=('c'*64);bindingCount=1}}
    function script:Checkpoint-VM {param($VM,$SnapshotName,$ErrorAction) $script:trace.Add('checkpoint');$script:created=$true}
    function script:Start-Sleep {param($Seconds)}
    $fingerprint=[pscustomobject]@{gitCommit=('d'*40);releaseVersion='1.2.13';installerVersion='1.2.13';releaseFingerprintId=('e'*64);toolingFingerprintId=('f'*64);tar=[pscustomobject]@{sha256=('a'*64)}}
    $result=Ensure-MaintenanceReadyFixture -Vm $script:testVm -Fingerprint $fingerprint -Config ([pscustomobject]@{}) -WorkspaceRoot $temp -RunId 'fullrelease-fixture-unit' -RunDir $temp
    if(($script:trace-join ',')-cne'provision-primary,configure-vault,checkpoint'){throw ('REAL FIXTURE MISSING CONFIGURED VAULT: '+($script:trace-join ','))}
    if(-not$result.vault.configurationPresent){throw 'Fixture configuration result was not preserved.'}
    $saved=Get-Content (Join-Path $temp 'audit/automation-harness/maintenance-ready-provenance.json') -Raw|ConvertFrom-Json
    if(-not$saved.vault.configurationPresent){throw 'Checkpoint provenance omitted its configured Vault.'}
    [ordered]@{status='PASS';realFixtureEntryPoint=$true;externalIoMocked=$true;vmMutation=$false;trace=@($script:trace)}|ConvertTo-Json
} $temp
