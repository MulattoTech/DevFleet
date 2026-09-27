param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$modulePath=Join-Path $WorkspaceRoot 'automation/release-e2e/modules/MaintenanceVault.psm1'
Import-Module $modulePath -Force
$module=Get-Module MaintenanceVault
$results=& $module {
    $script:steps=[Collections.Generic.List[string]]::new()
    $script:fixture=[pscustomobject]@{status='PASS';primaryName='devfleet-primary';primaryId='11111111-1111-1111-1111-111111111111';vaultName='devfleet-vault';vaultId='22222222-2222-2222-2222-222222222222';deploymentId='33333333-3333-3333-3333-333333333333';primaryRole='primary';configurationPresent=$true;authenticatedTransport=$true;proofCredit=$false;payloadSha256=('a'*64)}
    $script:existingVault=$false;$script:failStep='';$script:role='primary'
    # Only external product/VM operations are replaced; exercise the actual
    # prerequisite ordering and fail-closed result validation.
    function script:Invoke-MaintenanceVaultStep {
        param($Name,$Request,$State)
        $script:steps.Add($Name)
        if($Name-ceq$script:failStep){throw "ORIGINAL_$Name"}
        switch($Name){
            'identity' {return [pscustomobject]@{primaryRole=$script:role;existingVault=$script:existingVault;primaryId=$script:fixture.primaryId;deploymentId=$script:fixture.deploymentId}}
            'launch' {return [pscustomobject]@{vaultId=$script:fixture.vaultId}}
            'verify' {return $script:fixture}
        }
    }
    function Check($Value,$Message){if(-not$Value){throw $Message}}
    $request=[pscustomobject]@{runId='fullrelease-fixture-unit';payloadSha256=('a'*64);primaryName='devfleet-primary';vaultName='devfleet-vault';ownerDeadlineUtc=[datetime]::UtcNow.AddSeconds(60).ToString('o')}
    $actual=Invoke-MaintenanceVaultProvisioning -Request $request
    Check ($actual.status-ceq'PASS') 'configured Primary fixture was not accepted'
    Check (($script:steps -join ',')-ceq'identity,launch,bootstrap,configure,verify') 'configuration must precede verification and checkpoint publication'
    $script:steps.Clear();$script:existingVault=$true;$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'existing Vault' -and ($script:steps -join ',')-ceq'identity') 'preexisting Vault must never be adopted or refreshed'
    $script:existingVault=$false;$script:role='surrogate';$script:steps.Clear();$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'Primary' -and $script:steps.Count-eq1) 'Surrogate must not substitute for Primary'
    $script:role='primary';$script:failStep='bootstrap';$script:steps.Clear();$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-ceq'ORIGINAL_bootstrap' -and ($script:steps -join ',')-ceq'identity,launch,bootstrap') 'bootstrap failure must preserve the original error and forbid configure/credit'
    $script:failStep='';$script:fixture.configurationPresent=$false;$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'configuration') 'unconfigured fixture must not pass'
    $script:fixture.configurationPresent=$true;$script:fixture.payloadSha256=('b'*64);$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'payload') 'stale fixture must not pass'
    $script:fixture.payloadSha256=('a'*64);$script:fixture.proofCredit=$true;$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'credit') 'prerequisite must never award proof credit'
    $script:fixture.proofCredit=$false;$request.ownerDeadlineUtc=[datetime]::UtcNow.AddSeconds(-1).ToString('o');$script:steps.Clear();$caught=''
    try{Invoke-MaintenanceVaultProvisioning -Request $request|Out-Null}catch{$caught=$_.Exception.Message}
    Check ($caught-match'deadline' -and $script:steps.Count-eq0) 'expired owner must prevent any VM operation'
    [pscustomobject]@{status='PASS';cases=8;externalIoMocked=$true;vmMutation=$false;runtime=$PSVersionTable.PSVersion.ToString()}
}
$results|ConvertTo-Json -Depth 6
