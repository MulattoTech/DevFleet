[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$checks.Add([pscustomobject]@{name=$Name;pass=$Pass})}
$entry=Join-Path $WorkspaceRoot 'automation/release-e2e/Invoke-DevFleetReleaseE2E.ps1'
$text=Get-Content -LiteralPath $entry -Raw
$proofText=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'audit/run-exact-candidate-proof.ps1') -Raw
Check 'exact proof cleanup records its RunId for native terminal-summary validation' ($proofText.Contains('$cleanup=[ordered]@{runId=$RunId;status='))
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Production entrypoint does not parse'}
$importStart=$text.IndexOf('foreach($m in @(')
$importEnd=$text.IndexOf('$script:DevFleetFinalConvergencePrimaryBlocker')
if($importStart -lt 0 -or $importEnd -le $importStart){throw 'Cannot locate native import sequence'}
$pipeline=[powershell]::Create()
try {
    $code="param(`$scriptRoot) "+$text.Substring($importStart,$importEnd-$importStart)+"`n[bool](Get-Command Clear-DevFleetE2EInteractiveLogonState -ErrorAction SilentlyContinue)"
    $null=$pipeline.AddScript($code).AddArgument((Join-Path $WorkspaceRoot 'automation/release-e2e'))
    $visibility=@($pipeline.Invoke())
    Check 'cleanup API visible after actual entrypoint imports' (-not $pipeline.HadErrors -and $visibility.Count -gt 0 -and [bool]$visibility[-1])
} finally {$pipeline.Dispose()}
$catches=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.CatchClauseAst] -and $node.Body.Extent.Text.Contains('$failureCleanup=New-CleanupManifest')},$true))
if($catches.Count -ne 1){throw 'Native failure handler selection is ambiguous'}
$body=$catches[0].Body.Extent.Text
$handler=[scriptblock]::Create("try { throw 'PRIMARY_FIXTURE_FAILURE' } catch "+$body)
$root=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-cleanup-handler-'+[guid]::NewGuid().ToString('N'))
$global:DevFleetCleanupFixture=@{case='';logonCalls=0;stopCalls=0;terminalCalls=0;shown=''}
try {
    New-Item -ItemType Directory -Path (Join-Path $root 'tools') -Force|Out-Null
    Set-Content (Join-Path $root 'tools/Update-CurrentReleaseAuthority.ps1') 'param($Workspace,$FullReleaseRunId)' -Encoding utf8
    Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Evidence.psm1') -Force
    function New-CleanupManifest {param($Vm,$RunId) [pscustomobject]@{runId=$RunId}}
    function Get-AssertedDisposableVm {param($ExpectedVm) $ExpectedVm}
    function Clear-DevFleetE2EInteractiveLogonState {
        param([guid]$VmId)
        $global:DevFleetCleanupFixture.logonCalls++
        if($global:DevFleetCleanupFixture.case -eq 'logon-throws'){throw 'PRIVATE_FIXTURE_SECRET_SHOULD_NOT_BE_PERSISTED'}
        [pscustomobject]@{status='PASS';registryCleanupPersisted=($global:DevFleetCleanupFixture.case -ne 'not-durable');temporaryDefaultPasswordRemovalPersisted=$true;ordinaryDefaultPasswordPresent=$false}
    }
    function Stop-ManifestVm {param($Manifest) $global:DevFleetCleanupFixture.stopCalls++}
    function Write-TerminalVmEvidence {param($Vm,$RunDir,$L2Name) $global:DevFleetCleanupFixture.terminalCalls++}
    function Show-Result {param($label,$status,$detail) $global:DevFleetCleanupFixture.shown=$detail}
    foreach($case in @('running-durable','off','not-durable','logon-throws','keep-lab','no-target')){
        $global:DevFleetCleanupFixture.case=$case
        $global:DevFleetCleanupFixture.logonCalls=0;$global:DevFleetCleanupFixture.stopCalls=0;$global:DevFleetCleanupFixture.terminalCalls=0;$global:DevFleetCleanupFixture.shown=''
        $runId='failure-handler-fixture-'+$case
        $runDir=Join-Path $root $case
        New-Item -ItemType Directory -Path $runDir|Out-Null
        $vm=if($case -eq 'no-target'){$null}else{[pscustomobject]@{Name='DevFleet-E2E-fixture';Id=[guid]'11111111-1111-1111-1111-111111111111';State=if($case -eq 'off'){'Off'}else{'Running'}}}
        $config=[pscustomobject]@{NestedLinux=[pscustomobject]@{Name='DevFleet-E2E-fixture-L2'}}
        $KeepLab=($case -eq 'keep-lab')
        $WorkspaceRoot=$root
        $caught=$null
        try { & $handler 3>$null } catch {$caught=$_.Exception.Message}
        Check ($case+': primary failure preserved') ($caught -eq 'PRIMARY_FIXTURE_FAILURE' -and $global:DevFleetCleanupFixture.shown -eq 'PRIMARY_FIXTURE_FAILURE')
        $expectedStop=if($case -in @('running-durable','off')){1}else{0}
        Check ($case+': stop requires durable exact cleanup') ($global:DevFleetCleanupFixture.stopCalls -eq $expectedStop -and $global:DevFleetCleanupFixture.terminalCalls -eq $expectedStop)
        if($case -eq 'off'){Check 'already-Off guest never opened' ($global:DevFleetCleanupFixture.logonCalls -eq 0)}
        $path=Join-Path $runDir 'failure-cleanup.json'
        $exists=Test-Path $path
        Check ($case+': separate cleanup outcome persisted') $exists
        if($exists){
            $raw=Get-Content $path -Raw;$e=$raw|ConvertFrom-Json
            $expected=if($expectedStop){'COMPLETED'}elseif($KeepLab -or $case -eq 'no-target'){'NOT_RUN'}else{'FAIL'}
            Check ($case+': cleanup outcome truthful and non-certifying') ($e.status -eq $expected -and -not $e.certifiedReleaseCleanup -and $e.runId -eq $runId)
            Check ($case+': private exception omitted') ($raw -notmatch 'PRIVATE_FIXTURE_SECRET')
        }
    }
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force};Remove-Variable -Name DevFleetCleanupFixture -Scope Global -ErrorAction SilentlyContinue}
$failed=@($checks|Where-Object {-not $_.pass})
[ordered]@{scope='VM_FREE_NATIVE_FAILURE_HANDLER_REGRESSION';releaseCredit=$false;status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;checks=@($checks)}|ConvertTo-Json -Depth 6
if($failed.Count){exit 1}
