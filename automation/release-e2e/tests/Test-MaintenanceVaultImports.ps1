param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$root=Join-Path $WorkspaceRoot 'automation/release-e2e/modules'
Import-Module (Join-Path $root 'FullRelease.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'executors/Invoke-RealProductPhase.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'MaintenanceVault.psm1') -DisableNameChecking
& (Get-Module MaintenanceVault) {
    param($root,$common)
    foreach($name in @('GuestSession','HarnessBudget','HostSafety','MultipassDiagnostic','TailscaleE2E')){Import-Module (Join-Path $root ($name+'.psm1')) -Scope Local -DisableNameChecking}
    $required=@{'Connect-DevFleetGuest'=@('VmId');'Remove-DevFleetGuestSession'=@('Session');'Copy-DevFleetBoundedGuestFile'=@('LocalPath','RemotePath','Session','TimeoutSeconds');'Get-DevFleetBoundedProcessScriptBlock'=@();'Stage-TailscaleOAuthCredential'=@('Session','RunId','Config','ProductConfig');'Remove-StagedTailscaleOAuthCredential'=@('Session');'Get-HarnessBudgetPolicy'=@('Config');'Get-HostSafetySnapshot'=@('Vm')}
    foreach($name in $required.Keys){$command=Get-Command $name -ErrorAction Stop;foreach($parameter in $required[$name]){if(-not$command.Parameters.ContainsKey($parameter)){throw "$name is missing $parameter after the complete nested imports."}}}
    Import-Module $common -Scope Local -DisableNameChecking
    # Exact nested -Force import boundary used by both shipping 04/05 scripts;
    # no product body, host state, VM, network, or credential I/O is executed.
    & {Import-Module $common -Force -DisableNameChecking}
    Import-Module $common -Scope Local -DisableNameChecking
    foreach($name in @('Get-DevFleetConfig','Get-OrCreateSecrets','Get-OrCreateVaultIdentity','New-DevFleetBootstrapBoundary','Invoke-MultipassWithStandardInput','Invoke-External','Get-DevFleetOperationMaximumSeconds','Set-DevFleetDeadlineContext')){Get-Command $name -ErrorAction Stop|Out-Null}
    foreach($name in $required.Keys){Get-Command $name -ErrorAction Stop|Out-Null}
    [ordered]@{status='PASS';hostCommands=$required.Count;productCommands=8;runtime=$PSVersionTable.PSVersion.ToString();vmMutation=$false}|ConvertTo-Json
} $root (Join-Path $WorkspaceRoot 'source/windows/DevFleet.Common.psm1')
