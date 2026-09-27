param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Raw
$start=$source.IndexOf("            if(`$scenario-in@('permanent-delete','delete-restore','vault')){")
$end=$source.IndexOf('            $runId=[string]$runId;', $start)
if($start-lt0-or$end-le$start){throw 'Real configured-scenario guard was not found.'}
$guard=[scriptblock]::Create($source.Substring($start,$end-$start))
$scenario='permanent-delete';$primary='devfleet-primary';$mp='mock-external-multipass';$expectedTarHash='a'*64
$config=[pscustomobject]@{Vault=[pscustomobject]@{InstanceName='devfleet-vault'}}
$hostIdentity=[pscustomobject]@{deployment_id='33333333-3333-3333-3333-333333333333'}
$script:readinessCalls=[Collections.Generic.List[string]]::new();$script:wrongId=$false
$readinessSource='param($Primary,$MultipassPath);$script:readinessCalls.Add($Primary);[pscustomobject]@{status="PASS"}'
function Get-VM {param([guid]$Id,$ErrorAction) [pscustomobject]@{Id=$Id;Name=if($script:wrongId){'foreign'}elseif($Id.ToString()-eq'11111111-1111-1111-1111-111111111111'){'devfleet-primary'}else{'devfleet-vault'}}}
$fixture=[ordered]@{status='PASS';payloadSha256=$expectedTarHash;primaryRole='primary';primaryName=$primary;primaryId='11111111-1111-1111-1111-111111111111';vaultName='devfleet-vault';vaultId='22222222-2222-2222-2222-222222222222';deploymentId=$hostIdentity.deployment_id;configurationPresent=$true;proofCredit=$false}
$vaultFixtureJson=$fixture|ConvertTo-Json -Compress
. $guard
if($primary-cne'devfleet-primary'-or($script:readinessCalls-join ',')-cne'devfleet-vault'){throw 'Vault readiness changed the Primary scenario target.'}
$script:wrongId=$true;$caught='';$script:readinessCalls.Clear()
try{. $guard}catch{$caught=$_.Exception.Message}
if($caught-notmatch'immutable identity'-or$script:readinessCalls.Count-ne0){throw 'Changed VM identity must be rejected before readiness mutation.'}
$script:wrongId=$false;$vaultFixtureJson='';$caught=''
try{. $guard}catch{$caught=$_.Exception.Message}
if($caught-notmatch'configured checkpoint'){throw 'Unconfigured positive scenario did not refuse.'}
[ordered]@{status='PASS';cases=3;actualScenarioGuard=$true;externalIoMocked=$true;vmMutation=$false}|ConvertTo-Json
