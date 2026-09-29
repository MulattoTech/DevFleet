# DevFleet source part 042

Full-source UTF-8 byte interval [1906500, 1953000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 3b39b3996a6ed537a7f1de8279501f4761e8ba88c09ac08e0d9c4c35db50e57c

<!-- BEGIN SOURCE SLICE -->
ixture.terminalL1Hash=Get-FixtureHash $l1Path;$postFixture.terminalL2Hash=Get-FixtureHash $l2Path;$postFixture.nestedL2ObservationSha256=$nestedHash
    Write-FixtureJson $postPath $postFixture
    $incompleteTupleRejected=$false;$incompleteTupleError=''
    try{Invoke-FixtureNestedValidation -Root $fixtureRoot -RunId $fixtureRunId|Out-Null}catch{$incompleteTupleRejected=$true;$incompleteTupleError=$_.Exception.Message}
    $rows.Add([ordered]@{case='incomplete-candidate-tuple-rejected';status=if($incompleteTupleRejected){'BLOCKED'}else{'PASS'};l2State='UNVERIFIED';safeWithoutNestedEvidence=($incompleteTupleRejected -and $incompleteTupleError -match 'candidate tuple is malformed or incomplete')})

    $nestedFixture.candidate=$tuple;$l2Fixture.candidate=$tuple;$cleanupFixture.candidate=$tuple;$postFixture.candidate=$tuple;$stateFixture.candidateHashes=$tuple
    Write-FixtureJson $nestedPath $nestedFixture;$nestedHash=Get-FixtureHash $nestedPath
    $l2Fixture.sourceEvidenceSha256=$nestedHash;Write-FixtureJson $l2Path $l2Fixture
    Write-FixtureJson $cleanupPath $cleanupFixture;Write-FixtureJson $statePath $stateFixture
    $postFixture.cleanupEvidenceHash=Get-FixtureHash $cleanupPath;$postFixture.terminalL1Hash=Get-FixtureHash $l1Path;$postFixture.terminalL2Hash=Get-FixtureHash $l2Path;$postFixture.nestedL2ObservationSha256=$nestedHash
    Write-FixtureJson $postPath $postFixture
    $backendVerification='Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend'
    $nestedFixture.verification=$backendVerification;$nestedFixture.inventoryCount=2
    $nestedFixture.backendInventories=@([ordered]@{provider='Hyper-V';status='PASS';names=@('foreign-instance','foreign-instance');verification='bounded Hyper-V inventory'},[ordered]@{provider='VirtualBox';status='PASS';names=@();verification='bounded VirtualBox inventory'})
    $l2Fixture.verificationMethod=$backendVerification;$l2Fixture.backendInventories=$nestedFixture.backendInventories
    Write-FixtureJson $nestedPath $nestedFixture;$nestedHash=Get-FixtureHash $nestedPath
    $l2Fixture.sourceEvidenceSha256=$nestedHash;Write-FixtureJson $l2Path $l2Fixture
    $postFixture.terminalL2Hash=Get-FixtureHash $l2Path;$postFixture.nestedL2ObservationSha256=$nestedHash
    Write-FixtureJson $postPath $postFixture
    $malformedBackendRejected=$false;$malformedBackendError=''
    try{Invoke-FixtureNestedValidation -Root $fixtureRoot -RunId $fixtureRunId|Out-Null}catch{$malformedBackendRejected=$true;$malformedBackendError=$_.Exception.Message}
    $rows.Add([ordered]@{case='duplicate-backend-instance-name-rejected';status=if($malformedBackendRejected){'BLOCKED'}else{'PASS'};l2State='UNVERIFIED';safeWithoutNestedEvidence=($malformedBackendRejected -and $malformedBackendError -match 'duplicate instance name')})

    $nestedFixture.verification='Bounded Multipass JSON inventory inside exact L1';$nestedFixture.inventoryCount=0;$nestedFixture.backendInventories=@()
    $l2Fixture.verificationMethod=$nestedFixture.verification;$l2Fixture.backendInventories=@()
    Write-FixtureJson $nestedPath $nestedFixture;$nestedHash=Get-FixtureHash $nestedPath
    $l2Fixture.sourceEvidenceSha256=$nestedHash;Write-FixtureJson $l2Path $l2Fixture
    $postFixture.terminalL2Hash=Get-FixtureHash $l2Path;$postFixture.nestedL2ObservationSha256=$nestedHash
    Write-FixtureJson $postPath $postFixture
    [IO.File]::AppendAllText($nestedPath,"`n",[Text.UTF8Encoding]::new($false))
    $hashRejected=$false;$hashError=''
    try{Invoke-FixtureNestedValidation -Root $fixtureRoot -RunId $fixtureRunId|Out-Null}catch{$hashRejected=$true;$hashError=$_.Exception.Message}
    $rows.Add([ordered]@{case='changed-source-bytes-rejected-after-binding';status=if($hashRejected){'BLOCKED'}else{'PASS'};l2State='UNVERIFIED';safeWithoutNestedEvidence=($hashRejected -and $hashError -match 'hash bindings do not match')})
}finally{if(Test-Path -LiteralPath $fixtureRoot){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force}}

$hostCases=@('empty-host-inventory','denied-host-query','present-host-name','native-host-name-absence')
$failed = @($rows | Where-Object { -not [bool]$_.safeWithoutNestedEvidence -or ($_.case -in $hostCases -and (-not [bool]$_.hostAbsenceDidNotClaimNestedAbsent -or -not [bool]$_.nativeHostAbsenceClassified)) })
$result = [ordered]@{
    scope='VM_FREE_PRODUCTION_FUNCTION_REGRESSION'
    productionSource='tools/Invoke-DevFleetFinalConvergence.ps1::Invoke-ExactTerminalCleanup'
    productionSourceSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    certificationCredit=$false
    vmOperations=0
    passed=($rows.Count - $failed.Count)
    total=$rows.Count
    cases=@($rows)
    status=if ($failed.Count) { 'FAIL' } else { 'PASS' }
    failures=@($failed | ForEach-Object { $_.case })
}
$result | ConvertTo-Json -Depth 8
if ($failed.Count) { exit 1 }

```


## FILE: automation/release-e2e/tests/Test-FinalizerProcessExitBoundary.ps1

SHA256: 74f494d7d0b41f3bd657a9ac110302014229ca36b0119776f8f83a862d488207 | Bytes: 2539 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
$entry=Join-Path $WorkspaceRoot 'automation\release-e2e\Invoke-DevFleetReleaseE2E.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'Release entrypoint failed PowerShell parser validation.'}
$function=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-RequiredReleaseFinalizer'},$true))
if($function.Count -ne 1){throw 'Expected one production finalizer process-boundary function.'}
$functionText=$function[0].Extent.Text
. ([scriptblock]::Create($functionText))
$pwsh=(Get-Command pwsh.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
$temp=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-finalizer-exit-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
$checks=[Collections.Generic.List[object]]::new()
try{
    $success=Join-Path $temp 'success.ps1';$failure=Join-Path $temp 'failure.ps1'
    [IO.File]::WriteAllText($success,"Write-Output 'safe completion'`nexit 0`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($failure,"Write-Output 'bounded child output'`nexit 17`n",[Text.UTF8Encoding]::new($false))
    $successOutput=@(Invoke-RequiredReleaseFinalizer -PowerShellPath $pwsh -FinalizerPath $success)
    $checks.Add([pscustomobject]@{name='successful finalizer child remains successful';pass=($LASTEXITCODE -eq 0 -and ($successOutput -join "`n") -match 'safe completion');detail="childOutput=$($successOutput -join ' ')"})
    $failed=$false;$failureMessage=''
    try{Invoke-RequiredReleaseFinalizer -PowerShellPath $pwsh -FinalizerPath $failure|Out-Null}catch{$failed=$true;$failureMessage=$_.Exception.Message}
    $checks.Add([pscustomobject]@{name='nonzero finalizer child blocks the release caller';pass=($failed -and $failureMessage -match 'code 17');detail="blocked=$failed message=$failureMessage"})
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
$bad=@($checks|Where-Object{-not $_.pass})
[ordered]@{scope='VM_FREE_PRODUCTION_FINALIZER_PROCESS_EXIT_REGRESSION';certificationCredit=$false;status=if($bad.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$bad.Count;total=$checks.Count;checks=@($checks)}|ConvertTo-Json -Depth 8
if($bad.Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-FullReleaseFailureCleanup.ps1

SHA256: f37f4d49ab794c36eb7298442b7dacb3c53a4e8bef0ae5a0c7b0822bc4f3f7a5 | Bytes: 5999 | Git mode: 100644

```
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

```


## FILE: automation/release-e2e/tests/Test-FullReleasePromotionContract.ps1

SHA256: 9fd4f72b6c481e77aa30e5406fddc41959cda99d6a32adaa92abcb981b0cc457 | Bytes: 3918 | Git mode: 100644

```
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $WorkspaceRoot 'automation/release-e2e/modules/FullRelease.psm1'
Import-Module $modulePath -Force -DisableNameChecking
$checks = [Collections.Generic.List[object]]::new()

function Check([string]$Name, [bool]$Pass) {
    $checks.Add([pscustomobject]@{ name = $Name; pass = $Pass })
}

$runId = 'FullRelease-fixture-current'
$validResult = [pscustomobject]@{
    status = 'PASS'
    runId = $runId
    postCleanupFinalization = [pscustomobject]@{
        status = 'PASS'
        cleanupConsumed = $true
        reconcileAfterCleanup = $true
        liveChecks = [pscustomobject]@{ l1ExactOff = $true; l2ExactAbsent = $true }
    }
}

$state = @{
    full_release_run_id = $null
    full_release_current = $false
    full_release_passed = $false
    validation_evidence_current = $false
    internal_promotion_allowed = $false
    public_promotion_allowed = $false
    public_publisher_trust = $false
    status = 'IN_PROGRESS'
    release_status = 'IN_PROGRESS'
}
$promoted = $null
$promotionError = $null
try { $promoted = Set-FullReleasePassState -FinalizationState $state -Result $validResult -ExpectedRunId $runId } catch { $promotionError = $_.Exception.Message }
Check 'valid completed FullRelease promotes only its current evidence flags' (
    -not $promotionError -and
    [bool]$promoted.full_release_current -and
    [bool]$promoted.full_release_passed -and
    [bool]$promoted.validation_evidence_current -and
    -not [bool]$promoted.internal_promotion_allowed -and
    -not [bool]$promoted.public_promotion_allowed -and
    -not [bool]$promoted.public_publisher_trust -and
    [string]$promoted.full_release_run_id -ceq $runId
)

$rejectedState = @{
    full_release_run_id = $null
    full_release_current = $false
    full_release_passed = $false
    validation_evidence_current = $false
    internal_promotion_allowed = $false
    public_promotion_allowed = $false
    public_publisher_trust = $false
}
$blockedResult = [pscustomobject]@{
    status = 'BLOCKED'
    runId = $runId
    postCleanupFinalization = $validResult.postCleanupFinalization
}
$blockedError = $null
try { Set-FullReleasePassState -FinalizationState $rejectedState -Result $blockedResult -ExpectedRunId $runId | Out-Null } catch { $blockedError = $_.Exception.Message }
Check 'blocked FullRelease cannot promote any flag' (
    $blockedError -and
    -not [bool]$rejectedState.full_release_current -and
    -not [bool]$rejectedState.full_release_passed -and
    -not [bool]$rejectedState.validation_evidence_current
)

$mismatchState = @{
    full_release_run_id = $null
    full_release_current = $false
    full_release_passed = $false
    validation_evidence_current = $false
    internal_promotion_allowed = $false
    public_promotion_allowed = $false
    public_publisher_trust = $false
}
$mismatchError = $null
try { Set-FullReleasePassState -FinalizationState $mismatchState -Result $validResult -ExpectedRunId 'FullRelease-other-run' | Out-Null } catch { $mismatchError = $_.Exception.Message }
Check 'mismatched FullRelease RunId cannot promote any flag' (
    $mismatchError -and
    -not [bool]$mismatchState.full_release_current -and
    -not [bool]$mismatchState.full_release_passed -and
    -not [bool]$mismatchState.validation_evidence_current
)

$result = [ordered]@{
    status = if (@($checks | Where-Object { -not $_.pass }).Count) { 'FAIL' } else { 'PASS' }
    scope = 'LOCAL_FULLRELEASE_POSTCLEANUP_PROMOTION_BOUNDARY'
    passed = @($checks | Where-Object pass).Count
    total = $checks.Count
    checks = @($checks)
}
$result | ConvertTo-Json -Depth 8
if ($result.status -ne 'PASS') { exit 1 }
Write-Host "PASS $($result.passed)/$($result.total) FullRelease promotion checks; no VM, checkpoint, runtime, or auth operation performed."

```


## FILE: automation/release-e2e/tests/Test-GuestSessionCredentialRetryBoundary.ps1

SHA256: 46bfe5205671bf500bacdffb549ddc4553f601c57f3c445aa9b9a7a529fe5f1e | Bytes: 7247 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/GuestSession.psm1') -Force
$module=Get-Module GuestSession
$passed=0;$failures=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{$script:failures.Add($Name)}}
$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$vmName='DevFleet-E2E-Win11-01'
# All credentials and VM/session operations below are isolated fixtures.
& $module {
    $script:FixtureCredential=[pscredential]::new('fixture-user',(ConvertTo-SecureString 'fixture-only-not-a-password' -AsPlainText -Force))
    $script:FixtureTargetName='DevFleet-E2E-Win11-01'
    function script:Get-DevFleetE2ECredential { $script:FixtureCredential }
    function script:Get-VM { param($Id,$Name,$ErrorAction) [pscustomobject]@{Name=$script:FixtureTargetName} }
    function script:Start-Sleep { param($Seconds) $script:FixtureSleepSeconds += $Seconds }
    $script:OriginalOpener=(Get-Command New-BoundedVmPSSession).ScriptBlock.ToString()
    function script:New-BoundedVmPSSession {
        param($VmId,$VmName,$Credential)
        if(-not [object]::ReferenceEquals($Credential,$script:FixtureCredential)){throw 'Fixture credential identity mismatch'}
        $index=$script:FixtureAttempts;$script:FixtureAttempts++
        $value=$script:FixtureErrors[[Math]::Min($index,$script:FixtureErrors.Count-1)]
        if($null -ne $value){throw $value}
        return [pscustomobject]@{fixtureSession=$true}
    }
}
function Set-Case([object[]]$Errors){
    & $module {param($row)$script:FixtureErrors=$row.errors;$script:FixtureAttempts=0;$script:FixtureSleepSeconds=0} ([pscustomobject]@{errors=$Errors})
}
function Invoke-Case([string]$Mode){if($Mode -eq 'ById'){Connect-DevFleetGuest -VmId $vmId}else{Connect-DevFleetGuest -VmName $vmName}}
try {
    $cases=@(
        @{name='generic denial';error='Access is denied.';code='LAB_SESSION_ACCESS_DENIED';auth='UNVERIFIED'},
        @{name='typed denial';error=[UnauthorizedAccessException]::new('DEMO_SECRET_DO_NOT_RETURN');code='LAB_SESSION_ACCESS_DENIED';auth='UNVERIFIED'},
        @{name='invalid response';error='The credential is invalid.';code='LAB_GUEST_AUTHENTICATION_REJECTED';auth='REJECTED'},
        @{name='typed logon rejection';error=[ComponentModel.Win32Exception]::new(1326);code='LAB_GUEST_AUTHENTICATION_REJECTED';auth='REJECTED'},
        @{name='nested native denial';error=[InvalidOperationException]::new('outer DEMO_SECRET_DO_NOT_RETURN',[UnauthorizedAccessException]::new('inner DEMO_SECRET_DO_NOT_RETURN'));code='LAB_SESSION_ACCESS_DENIED';auth='UNVERIFIED'},
        @{name='unrelated credential text';error='Credential parameter conversion failed DEMO_SECRET_DO_NOT_RETURN';code='LAB_SESSION_OPEN_FAILED';auth='UNVERIFIED'},
        @{name='unknown failure';error='unclassified DEMO_SECRET_DO_NOT_RETURN';code='LAB_SESSION_OPEN_FAILED';auth='UNVERIFIED'},
        @{name='bounded timeout';error='Guest session establishment exceeded its finite 60-second open deadline.';code='LAB_SESSION_OPEN_TIMEOUT';auth='UNVERIFIED'},
        @{name='known socket transport';error='Hyper-V socket target process has ended.';code='LAB_SESSION_TRANSPORT_FAILED';auth='UNVERIFIED'}
    )
    foreach($mode in @('ById','ByName')){
        Set-Case @('The running command stopped because a remote session might have ended.',$null)
        $session=Invoke-Case $mode
        Check ($session.fixtureSession -and (& $module {$script:FixtureAttempts}) -eq 2) "$mode transient then success uses two attempts"
        Check ((& $module {$script:FixtureSleepSeconds}) -eq 5) "$mode success preserves bounded backoff"
        foreach($case in $cases){
            Set-Case @($case.error);$failure=$null
            try {Invoke-Case $mode|Out-Null}catch{$failure=$_.Exception}
            Check ($null -ne $failure -and $failure.Message.StartsWith($case.code+':')) "$mode $($case.name) truthful failure classification"
            Check ((& $module {$script:FixtureAttempts}) -eq 3 -and (& $module {$script:FixtureSleepSeconds}) -eq 10) "$mode $($case.name) original attempt cap and waits"
            Check ($null -ne $failure -and $failure.Data['authenticationOutcome'] -eq $case.auth -and $failure.Data['attemptCount'] -eq 3) "$mode $($case.name) safe structured diagnostics"
            Check ($null -ne $failure -and $failure.ToString() -notmatch 'DEMO_SECRET_DO_NOT_RETURN|LAB_CREDENTIAL_STALE') "$mode $($case.name) no arbitrary error text or stale-password claim"
            if($case.code -eq 'LAB_SESSION_TRANSPORT_FAILED'){
                Check ($failure.Message -match 'Hyper-V socket target process has ended') "$mode known transport retains existing recovery discriminator"
            }
        }
        & $module {$script:FixtureTargetName='protected-production'};Set-Case @($null)
        $rejected=$false;try{Invoke-Case $mode|Out-Null}catch{$rejected=$true}
        Check ($rejected -and (& $module {$script:FixtureAttempts}) -eq 0) "$mode rejects foreign target before opening a session"
        & $module {$script:FixtureTargetName='DevFleet-E2E-Win11-01'}
    }
    # Real local PowerShell pipeline, with only New-PSSession replaced by dummy I/O.
    # This verifies EndInvoke error handling without Hyper-V, WinRM or real secrets.
    & $module {
        function script:New-FixtureOpenerPipeline {
            $pipeline=[powershell]::Create()
            $null=$pipeline.AddScript('function New-PSSession { param($Credential,$VMId,$VMName,$ErrorAction) throw [ComponentModel.Win32Exception]::new(1326) }').Invoke()
            $pipeline.Commands.Clear()
            return $pipeline
        }
        $body=$script:OriginalOpener.Replace('$pipeline=[powershell]::Create()','$pipeline=New-FixtureOpenerPipeline')
        if($body -ceq $script:OriginalOpener){throw 'Expected opener I/O factory not found'}
        Set-Item Function:script:New-BoundedVmPSSession -Value ([scriptblock]::Create($body))
    }
    $nativeFailure=$null
    try{Connect-DevFleetGuest -VmId $vmId|Out-Null}catch{$nativeFailure=$_.Exception}
    Check ($null -ne $nativeFailure -and $nativeFailure.Message.StartsWith('LAB_GUEST_AUTHENTICATION_REJECTED:')) 'real opener propagates native authentication rejection into safe classification'
    Check ($null -ne $nativeFailure -and $nativeFailure.Data['nativeErrorCode'] -eq 1326) 'real opener preserves native error code rather than flattening to text'
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 0) 'failed native openers retain no live session pipelines'
} finally {
    & $module {
        foreach($name in @('New-BoundedVmPSSession','New-FixtureOpenerPipeline','Get-DevFleetE2ECredential','Get-VM','Start-Sleep')){Remove-Item "Function:$name" -ErrorAction SilentlyContinue}
        $script:FixtureCredential=$null
    }
    Remove-Module GuestSession -Force
}
[pscustomobject]@{status=if($failures.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failures);vmOperations=0;realCredentialReads=0}|ConvertTo-Json -Depth 4
if($failures.Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-GuestSessionLifetime.ps1

SHA256: 6174a017eb71991983d877da9b4101f5bb99e4d365a545f2e34f5065a6be8625 | Bytes: 4463 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/GuestSession.psm1') -Force
$module=Get-Module GuestSession
$passed=0;$failures=[Collections.Generic.List[string]]::new();$owned=[Collections.Generic.List[object]]::new()
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{$script:failures.Add($Name)}}
function New-LocalFixtureSession {
    # Exercise native PowerShell session/pipeline lifetime on the local host.
    # This named-pipe session needs no VM, credentials, network or service change.
    $pipeline=[powershell]::Create()
    $row=[pscustomobject]@{pipeline=$pipeline;session=$null};$script:owned.Add($row)
    $null=$pipeline.AddCommand('New-PSSession').AddParameter('UseWindowsPowerShell').AddParameter('ErrorAction','Stop')
    $async=$pipeline.BeginInvoke()
    if(-not $async.AsyncWaitHandle.WaitOne(15000)){$pipeline.Stop();throw 'Local session fixture exceeded15s.'}
    $session=@($pipeline.EndInvoke($async))|Select-Object -First 1
    if(-not $session){throw 'Local fixture returned no native session.'}
    $row.session=$session
    & $module {param($s,$p)$script:GuestSessionPipelines[[string]$s.InstanceId]=$p} $session $pipeline
    return $row
}
try {
    foreach($i in 1..3){
        $row=New-LocalFixtureSession
        Check ((Invoke-Command -Session $row.session -ScriptBlock {'alive'}) -ceq 'alive') "native session $i stays usable while opener is retained"
        Remove-DevFleetGuestSession -Session $row.session
        Check ([string]$row.session.State -ceq 'Closed' -and (& $module {$script:GuestSessionPipelines.Count}) -eq 0) "native close $i removes its registry entry"
        $disposed=$false;try{$null=$row.pipeline.Invoke()}catch{$disposed=$_.Exception.ToString() -match 'ObjectDisposedException|disposed'}
        Check $disposed "native close $i disposes the completed opener"
    }
    $first=New-LocalFixtureSession;$second=New-LocalFixtureSession
    Remove-DevFleetGuestSession -Session $first.session
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 1 -and (Invoke-Command -Session $second.session -ScriptBlock {'other-alive'}) -ceq 'other-alive') 'closing one session preserves the other live session and opener'
    Remove-DevFleetGuestSession -Session $first.session
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 1) 'closing an already closed session cannot remove another owner'
    Remove-DevFleetGuestSession -Session $second.session
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 0) 'last native close leaves no retained opener'
    $retained=New-LocalFixtureSession
    & $module {function script:Remove-PSSession {param($Session,$ErrorAction)throw 'controlled native removal failure'}}
    try {
        $failedClose=$false;try{Remove-DevFleetGuestSession -Session $retained.session}catch{$failedClose=$true}
        Check ($failedClose -and [string]$retained.session.State -ceq 'Opened' -and (& $module {$script:GuestSessionPipelines.Count}) -eq 1) 'failed native removal preserves the live session opener'
        Check ((Invoke-Command -Session $retained.session -ScriptBlock {'still-alive'}) -ceq 'still-alive') 'failed removal does not invalidate the still open native session'
        $quietCloseReturned=$false;try{Remove-DevFleetGuestSession -Session $retained.session -ErrorAction SilentlyContinue;$quietCloseReturned=$true}catch{}
        Check ($quietCloseReturned -and (& $module {$script:GuestSessionPipelines.Count}) -eq 1) 'caller-selected quiet cleanup preserves the primary error and live opener'
    } finally {& $module {Remove-Item Function:Remove-PSSession -ErrorAction SilentlyContinue}}
    Remove-DevFleetGuestSession -Session $retained.session
    Check ((& $module {$script:GuestSessionPipelines.Count}) -eq 0) 'subsequent successful close disposes the retained opener'
} finally {
    foreach($row in $owned){if($row.session){Remove-PSSession -Session $row.session -ErrorAction SilentlyContinue};$row.pipeline.Dispose()}
    & $module {$script:GuestSessionPipelines.Clear()}
}
[pscustomobject]@{status=if($failures.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failures);nativeTransport='local UseWindowsPowerShell';vmOperations=0}|ConvertTo-Json -Depth 4
if($failures.Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1

SHA256: 98203d79c9986c2f0b52f29513b3a027441d0355d605bb1ed18ad318dd9755ff | Bytes: 5243 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot,[string]$CandidatePath)
$ErrorActionPreference='Stop';if([string]::IsNullOrWhiteSpace($WorkspaceRoot)){$WorkspaceRoot=Join-Path $PSScriptRoot '..\..\..'};$workspace=(Resolve-Path -LiteralPath $WorkspaceRoot -ErrorAction Stop).Path
Import-Module (Join-Path $workspace 'automation\release-e2e\modules\Candidate.psm1') -Force
$token=Get-WindowsTokenEvidence
if(-not[bool]$token.standardNonAdministratorToken){throw 'Standard-token self-test requires a genuinely non-administrator, non-elevated medium-integrity caller.'}
$fingerprint=Get-CandidateFingerprint -WorkspaceRoot $workspace -CandidatePath $CandidatePath
if([string]$fingerprint.privateSigningProfile -ne 'PRIVATE_SELF_SIGNED'-or-not $fingerprint.authenticode-or[string]$fingerprint.authenticode.status -ne 'PASS'){throw 'Standard-token evidence requires the exact signed candidate and valid private Authenticode evidence.'}
foreach($tuple in @([string]$fingerprint.gitCommit,[string]$fingerprint.shippingInputIdentity,[string]$fingerprint.releaseFingerprintId,[string]$fingerprint.toolingFingerprintId)){if($tuple -notmatch '^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$'){throw 'Candidate tuple is incomplete or malformed.'}}
$runId='standard-token-'+(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8);$runRelative="evidence/standard-token/$runId";$runDir=Join-Path $workspace ($runRelative.Replace('/','\'))
if(Test-Path -LiteralPath $runDir){throw "Standard-token evidence run already exists: $runId"};New-Item -ItemType Directory -Path $runDir -Force|Out-Null
$rawReport=Join-Path $runDir 'installer-self-test-raw.txt';$canonical=Join-Path $runDir 'standard-token-evidence.json'
$before=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'DevFleet-Setup-SelfTest-*' -ErrorAction SilentlyContinue|ForEach-Object FullName)
$result=Invoke-CandidateSelfTest -Fingerprint $fingerprint -ReportPath $rawReport
$after=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'DevFleet-Setup-SelfTest-*' -ErrorAction SilentlyContinue|ForEach-Object FullName);$residual=@($after|Where-Object{$_-notin$before});$failed=@($result.requiredChecks.GetEnumerator()|Where-Object{-not[bool]$_.Value})
if($result.exitCode-ne 0-or[string]$result.result-ne 'PASS'-or$failed.Count-ne 0-or$residual.Count-ne 0){throw "Signed candidate standard-token self-test failed: exit=$($result.exitCode); result=$($result.result); failedChecks=$(@($failed.Name)-join ','); residualScratch=$($residual.Count)."}
if(-not[bool]$result.token.standardNonAdministratorToken){throw 'Candidate self-test token evidence was not a standard non-administrator token.'}
function Write-AtomicJson([string]$Path,[object]$Value){$tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp";try{[IO.File]::WriteAllText($tmp,(($Value|ConvertTo-Json -Depth 20)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $tmp -Destination $Path -Force}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}}
$runnerRelative='automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1';$runnerPath=Join-Path $workspace ($runnerRelative.Replace('/','\'))
$required=[ordered]@{pass=([string]$result.result-eq'PASS');payloadExtraction=[bool]$result.requiredChecks.extraction;bootstrapEntrypoint=[bool]$result.requiredChecks.bootstrap;parameterContract=[bool]$result.requiredChecks.parameterContract;embeddedTarCount=[bool]$result.requiredChecks.embeddedTarCount;factoryResetBackupGate=[bool]$result.requiredChecks.factoryResetBackupGate;planSafety=[bool]$result.requiredChecks.planSafety;devfleetVersion=[bool]$result.requiredChecks.devfleet;installerVersion=[bool]$result.requiredChecks.installer;payloadSha=[bool]$result.requiredChecks.payloadSha}
$evidence=[ordered]@{schemaVersion=1;runId=$runId;status='PASS';standardNonAdministratorToken=$true;runDirectory=$runRelative;rawReportPath="$runRelative/installer-self-test-raw.txt";canonicalEvidencePath="$runRelative/standard-token-evidence.json";generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o');candidateBuildCommit=[string]$fingerprint.gitCommit;repositoryHead=[string]$fingerprint.repositoryHead;shippingInputIdentity=[string]$fingerprint.shippingInputIdentity;releaseFingerprintId=[string]$fingerprint.releaseFingerprintId;toolingFingerprintId=[string]$fingerprint.toolingFingerprintId;exe=[ordered]@{sha256=[string]$fingerprint.candidate.sha256;bytes=[int64]$fingerprint.candidate.bytes};tar=[ordered]@{sha256=[string]$fingerprint.tar.sha256;bytes=[int64]$fingerprint.tar.bytes};runner=[ordered]@{path=$runnerRelative;sha256=(Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash.ToLowerInvariant()};token=$result.token;exitCode=[int]$result.exitCode;reportSha256=[string]$result.reportSha256;requiredChecks=$required;residualSelfTestScratchCount=$residual.Count}
Write-AtomicJson $canonical $evidence
$pointer=Join-Path $workspace 'evidence\CURRENT-STANDARD-TOKEN.json';Write-AtomicJson $pointer $evidence
Set-ItemProperty -LiteralPath $rawReport -Name IsReadOnly -Value $true;Set-ItemProperty -LiteralPath $canonical -Name IsReadOnly -Value $true
$evidence|ConvertTo-Json -Depth 20

```


## FILE: automation/release-e2e/tests/Test-InteractiveLogonContracts.ps1

SHA256: 0be399f64a28eaa682abe10da2ea592af918741c3015b0f6727b9bddac1f26bb | Bytes: 17232 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$modulePath=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\InteractiveLogon.psm1'
$source=Get-Content -LiteralPath $modulePath -Raw
Import-Module $modulePath -Force
$total=0;$passed=0;$failures=[System.Collections.Generic.List[string]]::new()
function Assert-That([bool]$Condition,[string]$Name){$script:total++;if($Condition){$script:passed++}else{$script:failures.Add($Name)}}
function Throws([scriptblock]$Action){try{&$Action|Out-Null;return $false}catch{return $true}}

$target=Get-DevFleetE2EInteractiveLogonTarget
Assert-That ($target.name -ceq 'DevFleet-E2E-Win11-01' -and $target.id -eq [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') 'exact authorized L1 identity is immutable'
Assert-That ($target.user -ceq 'E2EAdmin' -and $target.domain -ceq 'DEVFLEET-E2E-01') 'exact E2EAdmin account contract'
Assert-That (Assert-DevFleetE2EL1Identity -Vm ([pscustomobject]@{Name=$target.name;Id=$target.id})) 'exact L1 GUID and name accepted'
Assert-That (Throws { Assert-DevFleetE2EL1Identity -Vm ([pscustomobject]@{Name='DevFleet-E2E-Win11-02';Id=$target.id}) }) 'wrong L1 name rejected'
Assert-That (Throws { Assert-DevFleetE2EL1Identity -Vm ([pscustomobject]@{Name=$target.name.ToLowerInvariant();Id=$target.id}) }) 'case-mismatched exact L1 name rejected'
Assert-That (Throws { Assert-DevFleetE2EL1Identity -Vm ([pscustomobject]@{Name=$target.name;Id=[guid]::NewGuid()}) }) 'wrong L1 GUID rejected'

$good=[pscustomobject]@{computer='DEVFLEET-E2E-01';activeInteractiveSessionId=1;boundExplorer=@([pscustomobject]@{pid=4242;owner='DEVFLEET-E2E-01\E2EAdmin';sessionId=1})}
$proof=Assert-DevFleetE2EInteractiveDesktop -State $good
Assert-That ($proof.status -eq 'PASS' -and $proof.sessionId -eq 1 -and $proof.explorerPid -eq 4242) 'exact E2EAdmin Explorer session accepted'
Assert-That (Throws { Assert-DevFleetE2EInteractiveDesktop -State ($good|Select-Object * -ExcludeProperty activeInteractiveSessionId|Add-Member -NotePropertyName activeInteractiveSessionId -NotePropertyValue 0 -PassThru) }) 'Session 0 rejected'
Assert-That (Throws { Assert-DevFleetE2EInteractiveDesktop -State ($good|Select-Object * -ExcludeProperty boundExplorer|Add-Member -NotePropertyName boundExplorer -NotePropertyValue @() -PassThru) }) 'missing Explorer rejected'
$wrongUser=$good|ConvertTo-Json -Depth 5|ConvertFrom-Json;$wrongUser.boundExplorer[0].owner='DEVFLEET-E2E-01\OtherUser'
Assert-That (Throws { Assert-DevFleetE2EInteractiveDesktop -State $wrongUser }) 'wrong-user Explorer rejected'
$wrongSession=$good|ConvertTo-Json -Depth 5|ConvertFrom-Json;$wrongSession.boundExplorer[0].sessionId=2
Assert-That (Throws { Assert-DevFleetE2EInteractiveDesktop -State $wrongSession }) 'wrong Explorer SessionId rejected'
Assert-That ((Get-DevFleetE2EInteractiveDesktopFailureCategory -Stage pssession) -eq 'pssession-unavailable') 'PowerShell Direct failure remains distinct'
Assert-That ((Get-DevFleetE2EInteractiveDesktopFailureCategory -Stage guest-state) -eq 'guest-state-collection-failure') 'guest state failure remains distinct'
Assert-That ((Get-DevFleetE2EInteractiveDesktopFailureCategory -State ([pscustomobject]@{activeInteractiveSessionId=0;explorer=@()}) -Stage assertion) -eq 'no-active-e2eadmin-session') 'no active E2EAdmin session remains distinct'
Assert-That ((Get-DevFleetE2EInteractiveDesktopFailureCategory -State ([pscustomobject]@{activeInteractiveSessionId=1;explorer=@()}) -Stage assertion) -eq 'explorer-absent') 'Explorer absent remains distinct'
Assert-That ((Get-DevFleetE2EInteractiveDesktopFailureCategory -State ([pscustomobject]@{activeInteractiveSessionId=1;explorer=@([pscustomobject]@{owner='DEVFLEET-E2E-01\OtherUser'})}) -Stage assertion) -eq 'wrong-explorer-user') 'wrong Explorer user remains distinct'
Assert-That ((Get-DevFleetE2EInteractiveDesktopFailureCategory -State ([pscustomobject]@{activeInteractiveSessionId=1;explorer=@([pscustomobject]@{owner='DEVFLEET-E2E-01\E2EAdmin'})}) -Stage assertion) -eq 'wrong-noninteractive-session') 'wrong or noninteractive session remains distinct'
Assert-That ($source -match '\$expectedActive=.*\$_.user -ieq ''E2EAdmin''' -and $source -match '\$bound=.*\$_.domain -ieq ''DEVFLEET-E2E-01''') 'quser case normalization does not reject the exact interactive principal'
Assert-That ($source -match 'owner="\$\(\$owner\.Domain\)\\\$\(\$owner\.User\)"') 'Explorer owner identity preserves the CIM domain and user fields'

Assert-That ($source -match 'Get-DevFleetE2ECredential' -and $source -match 'secrets.json' -or $source -match 'Secrets\.psm1') 'canonical DPAPI credential authority is used'
Assert-That ($source -match 'LsaOpenPolicy' -and $source -match 'LsaStorePrivateData' -and $source -match 'LsaClose' -and $source -match 'LsaNtStatusToWinError') 'LSA protected DefaultPassword implementation exists'
Assert-That ($source -match 'LsaStorePrivateData\(policy, ref key, IntPtr\.Zero\)' -and $source -match 'ClearAndProbe\(' -and $source -match '0x4' -and $source -match '\$clearAndProbeError -notin @\(0,2,1168\)' -and $source -match 'ZeroFreeGlobalAllocUnicode' -and $source -match 'ZeroFreeBSTR') 'LSA clear independently verifies absence and unmanaged secret zeroing are bounded'
Assert-That ($source -match "InteractiveLogonMode = 'native-winlogon'" -and $source -match "SetValue\('AutoLogonCount',100" -and $source -notmatch 'AutoLogonCount -Value 1\b' -and $source -notmatch 'AutoLogonCount -Value 2\b') 'native Winlogon mode uses the historically successful bounded allowance'
$nativeArmStart=$source.IndexOf('function Set-DevFleetE2EWinlogonAutologon');$nativeArmEnd=$source.IndexOf('function Restore-DevFleetE2EWinlogonBaseline',$nativeArmStart);$nativeArm=$source.Substring($nativeArmStart,$nativeArmEnd-$nativeArmStart)
Assert-That ($nativeArm -match 'param\(\[securestring\]\$securePassword\)' -and $nativeArm -match 'SecureStringToBSTR' -and $nativeArm -match 'PtrToStringBSTR' -and $nativeArm -match 'ZeroFreeBSTR' -and $nativeArm -match 'SetValue\(''DefaultPassword'',\$plain') 'ordinary DefaultPassword write is confined to the bounded guest-only SecureString conversion helper'
Assert-That ($nativeArm -match 'COMPUTERNAME.*DEVFLEET-E2E-01' -and $nativeArm -match 'SetValue\(''DefaultDomainName'',\[string\]\$env:COMPUTERNAME' -and $nativeArm -match 'SetValue\(''AutoLogonCount'',100') 'native helper asserts exact guest and uses exact local computer domain'
Assert-That ($nativeArm -match 'OpenSubKey\(\$path,\$true\)' -and $nativeArm -match 'Flush\(\)' -and $nativeArm -notmatch 'Set-ItemProperty') 'native Winlogon mutation uses one direct guest RegistryKey handle and explicit flush'
Assert-That ($nativeArm -notmatch 'ForceAutoLogon|IgnoreShiftOverride' -and $nativeArm -match 'defaultPasswordPresent=\$true') 'native helper adds no experimental Winlogon behavior and returns non-secret verification only'
Assert-That ($source -match 'Get-AssertedDevFleetE2EL1' -and $source -match 'Get-DevFleetE2ECredential' -and $source -match 'pre-existing ordinary DefaultPassword') 'helper requires exact L1 identity and canonical DPAPI credential authority'
Assert-That ($source -match 'MaximumLength = \(ushort\)\(key.Length \+ 2\)' -and $source -match 'MaximumLength = \(ushort\)\(privateData.Length \+ 2\)') 'LSA strings include terminating WCHAR capacity'
Assert-That ($source -match 'Compare\(' -and $source -match 'secretMatchesCredential' -and $source -match 'secretPresent') 'LSA arm compares protected secret to canonical credential inside the guest without revealing it'
Assert-That ($source -match 'attributes.Length = 0') 'LSA reserved object attributes remain zero initialized'
Assert-That ($source -match 'IgnoreShiftOverridePresent' -and $source -match 'IgnoreShiftOverride=if' -and $nativeArm -notmatch 'IgnoreShiftOverride -Value') 'Winlogon shift bypass is baseline tracked and never forced by native mode'
Assert-That ($source -match 'ForceAutoLogonPresent' -and $source -match 'ForceAutoLogon=if' -and $nativeArm -notmatch 'ForceAutoLogon -Value') 'Winlogon forced autologon is baseline tracked and never forced by native mode'
Assert-That ($source -match 'DeleteValue\(''DefaultPassword'',\$false\)' -and $source -match 'ordinaryDefaultPasswordPresent=\$false') 'ordinary DefaultPassword is removed during cleanup'
Assert-That ($source -match 'function Restore-DevFleetE2EWinlogonBaseline[\s\S]*Invoke-Command[\s\S]*-ArgumentList \$Baseline \| Out-Null') 'Winlogon baseline restore returns one authoritative result object'
Assert-That ($source -match 'Restart-VM -VM' -and $source -match 'Remove-PSSession' -and $source -match 'QuietSettleSeconds' -and $source -match 'armDeadlineSeconds=120' -and $source -match 'rebootCount=1') 'host-controlled one-reboot quiet-settle and hard deadline are explicit'
Assert-That ($source -match 'function Disarm-DevFleetE2EInteractiveLogon' -and $source -match 'function Assert-DevFleetE2EInteractiveDesktopAfterDisarm' -and $source -match 'survivesDisarm') 'disarm and active-session survival proof exist'
Assert-That ($source -match 'function Clear-DevFleetE2EInteractiveLogonState' -and $source -match 'autologonStateCleared=\$true') 'final cleanup removes all autologon state'
Assert-That ($source -match 'lsaClearedBeforeArm' -and $source -match 'lsaDefaultPasswordPresent=\$false' -and $source -match 'ordinaryDefaultPasswordPresent=\$false') 'native arm clears residual LSA state and disarm proves both credential authorities absent'
Assert-That ($source -match 'DevFleetE2EGuestComputer' -and $source -match "expectedComputer='DEVFLEET-E2E-01'") 'guest identity is distinct from the Hyper-V host VM identity'
Assert-That ($source -match 'pollProgress' -and $source -match 'pssession-unavailable' -and $source -match 'guest-state-collection-failure' -and $source -match 'wrong-explorer-user' -and $source -match 'lastSuccessfullyCollectedState' -and $source -match 'guestObservationCount') 'desktop wait preserves concise categorized progression and bounded final failure'
Assert-That ($source -notmatch 'Write-Host[^\r\n]*(?:Secret|Password|credential)' -and $source -notmatch 'ConvertTo-Json[^\r\n]*(?:plain|secureSecret)') 'credential material is not written to logs or evidence'
Assert-That ($source -match 'function Get-DevFleetE2EPreLogonPolicyState' -and $source -match 'LegalNoticeCaption' -and $source -match 'LegalNoticeText' -and $source -match 'utf16leSha256') 'pre-logon banner policy captures structural UTF-16 evidence'
Assert-That ($source -match 'function Remove-DevFleetE2EPreLogonPolicy' -and $source -match 'function Restore-DevFleetE2EPreLogonPolicy' -and $source -match 'RegistryValueKind' -and $source -match 'LOGON_BANNER_POLICY_REASSERTED') 'banner suppression is bounded and restores exact disposable-lab policy'
$policy