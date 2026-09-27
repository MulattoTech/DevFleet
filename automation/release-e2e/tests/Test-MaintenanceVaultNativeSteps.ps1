param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $WorkspaceRoot 'source/windows/DevFleet.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/MaintenanceVault.psm1') -Force -DisableNameChecking
$temp=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-vault-native-test-'+[guid]::NewGuid().ToString('N'))
foreach($leaf in @('windows','linux','cloud-init','work')){[IO.Directory]::CreateDirectory((Join-Path $temp $leaf))|Out-Null}
Copy-Item (Join-Path $WorkspaceRoot 'source/linux/dependency-policy.json') (Join-Path $temp 'linux/dependency-policy.json')
Copy-Item (Join-Path $WorkspaceRoot 'source/cloud-init/vault.yaml') (Join-Path $temp 'cloud-init/vault.yaml')
$tracePath=Join-Path $temp 'tailscale-order.txt'
$windowsHostScript='if(-not$env:DEVFLEET_MAINTENANCE_TEST_TRACE){throw "Missing ordering trace"};Add-Content -LiteralPath $env:DEVFLEET_MAINTENANCE_TEST_TRACE -Value "windows-host"'
$guestScript='param([string]$InstanceName);if($InstanceName-cne"devfleet-vault"){throw "Unexpected guest pairing target"};Add-Content -LiteralPath $env:DEVFLEET_MAINTENANCE_TEST_TRACE -Value ("guest:"+$InstanceName)'
$clientScript='param([string]$InstanceName);if($InstanceName-cne"devfleet-primary"){throw "Unexpected local client target"};Add-Content -LiteralPath $env:DEVFLEET_MAINTENANCE_TEST_TRACE -Value ("client:"+$InstanceName)'
[IO.File]::WriteAllText((Join-Path $temp 'windows/04a-Connect-WindowsTailscale.ps1'),$windowsHostScript,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $temp 'windows/04-Connect-Tailscale.ps1'),$guestScript,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $temp 'windows/05-Configure-LocalVaultClient.ps1'),$clientScript,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $temp 'node-identity.json'),'{"node_role":"primary","deployment_id":"33333333-3333-3333-3333-333333333333"}',[Text.UTF8Encoding]::new($false))
$oldComputer=$env:COMPUTERNAME
$oldTrace=$env:DEVFLEET_MAINTENANCE_TEST_TRACE
try{
    $env:COMPUTERNAME='DEVFLEET-E2E-01' # Test-process environment only; restored below.
    $env:DEVFLEET_MAINTENANCE_TEST_TRACE=$tracePath
    & (Get-Module MaintenanceVault) {
        param($temp,$workspace)
        $script:testRoot=$temp;$script:created=$false;$script:stdinDelivered=$false
        $script:steps=[Collections.Generic.List[string]]::new()
        $script:testConfig=[pscustomobject]@{Primary=[pscustomobject]@{InstanceName='devfleet-primary'};Vault=[pscustomobject]@{InstanceName='devfleet-vault';UbuntuImage='24.04';Cpus=2;Memory='3G';Disk='80G'};Network=[pscustomobject]@{VaultPort=8000};ClusterName='unit-fixture'}
        # External filesystem-root discovery, VM, transport and credential I/O
        # only. The real fixture steps, payload zip, cloud-init rendering, and
        # production New-DevFleetBootstrapBoundary execute without mocks.
        function script:Import-Module {param($Name,$Scope,[switch]$DisableNameChecking)}
        function script:Get-DevFleetConfig {return $script:testConfig}
        function script:Get-DevFleetStateRoot {return $script:testRoot}
        function script:Get-MultipassExe {return 'unit-only-multipass'}
        function script:Set-DevFleetDeadlineContext {param($TransactionDeadlineUtc,$StageName,$StageBudgetSeconds)}
        function script:Get-DevFleetOperationMaximumSeconds {param($Name) return 60}
        function script:Assert-MultipassIsolation {param($InstanceNames) if(($InstanceNames-join ',')-cne'devfleet-primary'){throw 'Wrong isolation target'}}
        function script:Get-VM {
            param($Name,[guid]$Id,$ErrorAction)
            $primary=[pscustomobject]@{Name='devfleet-primary';Id=[guid]'11111111-1111-1111-1111-111111111111'}
            $vault=[pscustomobject]@{Name='devfleet-vault';Id=[guid]'22222222-2222-2222-2222-222222222222'}
            if($Name-eq'devfleet-primary'-or$Id-eq$primary.Id){return $primary}
            if($Name-eq'devfleet-vault'-or$Id-eq$vault.Id){if(-not$script:created){throw 'Vault is absent'};return $vault}
            return $primary
        }
        function script:Invoke-External {
            param($FilePath,$ArgumentList,[switch]$Capture,$TimeoutSeconds,$DeadlineUtc)
            if($FilePath-cne'unit-only-multipass'){throw 'Unexpected executable'}
            $script:steps.Add([string]$ArgumentList[0])
            if($ArgumentList[0]-eq'list'){return '{"list":[{"name":"devfleet-primary","state":"Running"}]}'}
            if($ArgumentList[0]-eq'transfer'-and-not(Test-Path -LiteralPath $ArgumentList[1] -PathType Leaf)){throw 'Payload zip was not created'}
            if($ArgumentList[0]-eq'exec'-and$ArgumentList[1]-notin@('devfleet-vault','devfleet-primary')){throw 'Unexpected command target'}
        }
        function script:Invoke-MultipassLaunchWithReadinessRecovery {
            param($InstanceName,$LaunchArguments,$ReadinessTimeoutSeconds,$LaunchTimeoutSeconds,$DeadlineUtc)
            if($InstanceName-cne'devfleet-vault'-or$ReadinessTimeoutSeconds-le0-or$DeadlineUtc-le[datetime]::UtcNow){throw 'Invalid bounded fresh launch'}
            $cloud=Get-Content -LiteralPath $LaunchArguments[-1] -Raw
            if($cloud-match'__[A-Z0-9_]+__'-or$cloud-notmatch"hostname: 'devfleet-vault'"){throw 'Actual cloud-init rendering is incomplete'}
            $script:created=$true
        }
        function script:Get-OrCreateSecrets {return [pscustomobject]@{VaultRestUser='unit';VaultRestPassword='unit-only-fake';ResticPassword='unit-only-fake'}}
        function script:Get-OrCreateVaultIdentity {return [pscustomobject]@{deployment_id='33333333-3333-3333-3333-333333333333';node_id='44444444-4444-4444-4444-444444444444';node_name='devfleet-vault'}}
        function script:Invoke-MultipassWithStandardInput {
            param($FilePath,$InstanceName,$CommandArgumentList,$TimeoutSeconds,$DeadlineUtc,$StandardInputText)
            $value=$StandardInputText|ConvertFrom-Json
            if($value.DeploymentId-cne'33333333-3333-3333-3333-333333333333'-or$InstanceName-cne'devfleet-vault'-or$TimeoutSeconds-le0-or$DeadlineUtc-le[datetime]::UtcNow){throw 'Bootstrap binding/deadline is invalid'}
            if(($CommandArgumentList-join ' ')-match'unit-only-fake'-or($CommandArgumentList-join ' ')-notmatch'--secrets-stdin'){throw 'Secrets must use bounded stdin only'}
            $script:stdinDelivered=$true
        }
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $workspace 'automation/release-e2e/modules/MaintenanceVault.psm1'),[ref]$tokens,[ref]$errors)
        $initializer=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$request'-and$n.Right.Extent.Text-match'inputHashes=\[ordered\]'},$true))
        if($initializer.Count-ne1){throw 'Native host request construction is ambiguous'}
        $Context=[pscustomobject]@{runId='fullrelease-fixture-unit';candidate=[pscustomobject]@{tar=[pscustomobject]@{sha256=('a'*64)}}};$config=$script:testConfig;$deadline=[datetime]::UtcNow.AddSeconds(60);$budget=60
        . ([scriptblock]::Create($initializer[0].Extent.Text))
        $request.packageRoot=$temp;$request.workRoot=Join-Path $temp 'work'
        $result=Invoke-MaintenanceVaultProvisioning -Request ([pscustomobject]$request)
        if($result.status-cne'PASS'-or-not$script:stdinDelivered-or($script:steps-join ',')-cne'list,transfer,exec,exec'){throw 'Native fixture steps did not complete the exact setup path'}
        $pairingOrder=@(Get-Content -LiteralPath $env:DEVFLEET_MAINTENANCE_TEST_TRACE)
        if(($pairingOrder-join ',')-cne'windows-host,guest:devfleet-vault,client:devfleet-primary'){throw ('Maintenance Vault pairing order is unsafe: '+($pairingOrder-join ','))}
        [ordered]@{status='PASS';realStepBodies=$true;realHostRequest=$true;realProductBootstrapBoundary=$true;externalIoMocked=$true;vmMutation=$false;steps=@($script:steps)}|ConvertTo-Json
    } $temp $WorkspaceRoot
} finally {$env:COMPUTERNAME=$oldComputer;$env:DEVFLEET_MAINTENANCE_TEST_TRACE=$oldTrace}
