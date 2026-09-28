# DevFleet source part 042

Full-source UTF-8 byte interval [1906500, 1953000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 08c9d82f4fde3d3a50052b775a2be31458ae0251f03dfd82e30fc669c7af06b6

<!-- BEGIN SOURCE SLICE -->
'11111111-1111-1111-1111-111111111111';State=if($case -eq 'off'){'Off'}else{'Running'}}}
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
$policyFixture=[ordered]@{caption=[ordered]@{present=$true;registryValueKind='String';utf16CodeUnitCount=1;stringLength=1;isZeroLength=$false;isOnlyNulCharacters=$false;isOnlyWhitespace=$false;utf16leSha256='fixture';rawValue='not-durable'};text=[ordered]@{present=$true;registryValueKind='String';utf16CodeUnitCount=1;stringLength=1;isZeroLength=$false;isOnlyNulCharacters=$false;isOnlyWhitespace=$false;utf16leSha256='fixture';rawValue='not-durable'};source='unknown';sourceEvidence=[ordered]@{localPolicyRegistryPath=$true;domainPolicyRegistryPath=$false;policyManagerPath=$false}}
$policyStructure=Get-DevFleetE2EPreLogonPolicyStructure -State $policyFixture
Assert-That ($source -match 'rawValue' -and $source -match 'function Get-PolicyStructure' -and $source -match 'preLogonPolicyRestored' -and -not ($policyStructure.caption.Keys -contains 'rawValue') -and -not ($policyStructure.text.Keys -contains 'rawValue')) 'banner contents remain transient and cleanup truth is exposed without durable plaintext'
$armOrder=@($nativeArm.IndexOf('SetValue'),$nativeArm.IndexOf('GetValueNames'),$nativeArm.IndexOf('Invoke-DevFleetE2ERegistryPersistenceBarrier'),$nativeArm.IndexOf('Get-DevFleetE2EWinlogonBaseline'))
Assert-That (($armOrder|Where-Object{$_ -ge 0}).Count -eq 4 -and $armOrder[0] -lt $armOrder[1] -and $armOrder[1] -lt $armOrder[2] -and $armOrder[2] -lt $armOrder[3]) 'Winlogon arm orders writes, readback, persistence barrier, and post-flush readback'
$armFunction=$source.Substring($source.IndexOf('function Arm-DevFleetE2EInteractiveLogon'),$source.IndexOf('function Restart-DevFleetE2EL1')-$source.IndexOf('function Arm-DevFleetE2EInteractiveLogon'))
Assert-That ($armFunction.IndexOf('registryPersistenceBarrier') -ge 0 -and $armFunction.IndexOf('Remove-PSSession') -gt $armFunction.IndexOf('registryPersistenceBarrier')) 'Winlogon persistence completes before arm session removal and host restart path'
$policyRemove=$source.Substring($source.IndexOf('function Remove-DevFleetE2EPreLogonPolicy'),$source.IndexOf('function Restore-DevFleetE2EPreLogonPolicy')-$source.IndexOf('function Remove-DevFleetE2EPreLogonPolicy'))
Assert-That ($policyRemove.IndexOf('DeleteValue') -lt $policyRemove.IndexOf('Invoke-DevFleetE2ERegistryPersistenceBarrier') -and $policyRemove.IndexOf('Invoke-DevFleetE2ERegistryPersistenceBarrier') -lt $policyRemove.IndexOf('Get-DevFleetE2EPreLogonPolicyState') -and $policyRemove -match 'preLogonPolicySuppressionPersisted') 'pre-logon suppression orders mutation, barrier, and verification with truthful persistence'
$policyRestore=$source.Substring($source.IndexOf('function Restore-DevFleetE2EPreLogonPolicy'),$source.IndexOf('function Set-DevFleetE2EWinlogonAutologon')-$source.IndexOf('function Restore-DevFleetE2EPreLogonPolicy'))
Assert-That ($policyRestore.IndexOf('SetValue') -lt $policyRestore.IndexOf('Invoke-DevFleetE2ERegistryPersistenceBarrier') -and $policyRestore.IndexOf('Invoke-DevFleetE2ERegistryPersistenceBarrier') -lt $policyRestore.IndexOf('Get-DevFleetE2EPreLogonPolicyState') -and $policyRestore -match 'preLogonPolicyRestorationPersisted') 'pre-logon restoration orders mutation, barrier, reread, and persistence evidence'
$disarmFunction=$source.Substring($source.IndexOf('function Disarm-DevFleetE2EInteractiveLogon'),$source.IndexOf('function Clear-DevFleetE2EInteractiveLogonState')-$source.IndexOf('function Disarm-DevFleetE2EInteractiveLogon'))
Assert-That ($disarmFunction.IndexOf('Restore-DevFleetE2EWinlogonBaseline') -lt $disarmFunction.IndexOf('Invoke-DevFleetE2EGuestLsa -Session $session -Clear') -and $disarmFunction.IndexOf('Invoke-DevFleetE2EGuestLsa -Session $session -Clear') -lt $disarmFunction.IndexOf('registryCleanupPersisted') -and $disarmFunction -match 'autologonBaselinePersistenceConfirmed' -and $disarmFunction -match 'preLogonPolicyRestorationPersisted') 'disarm removes ordinary registry state before durable LSA clear and PASS evidence'
$clearFunction=$source.Substring($source.IndexOf('function Clear-DevFleetE2EInteractiveLogonState'),$source.IndexOf('function Assert-DevFleetE2EInteractiveDesktopAfterDisarm')-$source.IndexOf('function Clear-DevFleetE2EInteractiveLogonState'))
Assert-That ($clearFunction.IndexOf('DeleteValue') -lt $clearFunction.IndexOf('Invoke-DevFleetE2ERegistryPersistenceBarrier') -and $clearFunction.IndexOf('Invoke-DevFleetE2ERegistryPersistenceBarrier') -lt $clearFunction.IndexOf('Get-DevFleetE2EWinlogonBaseline') -and $clearFunction -match 'temporaryDefaultPasswordRemovalPersisted') 'final clear orders transient removal, persistence barrier, reread, and force-stop evidence'

$realPhase=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1') -Raw
$wpfDriver=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-WpfUiAutomation.ps1') -Raw
Assert-That ($realPhase -match 'Arm-DevFleetE2EInteractiveLogon' -and $realPhase -match 'Restart-DevFleetE2EL1' -and $realPhase -match 'Wait-DevFleetE2EInteractiveDesktop' -and $realPhase -match 'Disarm-DevFleetE2EInteractiveLogon') 'legitimate product reboot re-arms one-shot autologon'
Assert-That ($realPhase -match 'New-ScheduledTaskPrincipal -UserId \(\[string\]\$spec\.taskPrincipalUserId\)' -and $realPhase -match 'Resolve-TaskSid' -and $realPhase -match 'principalSidSha256' -and $realPhase -match 'driverIdentity' -and $realPhase -match 'candidateIdentity' -and $realPhase -match 'interactiveProof\.sessionId') 'driver and candidate share exact interactive Explorer session'
Assert-That ($wpfDriver -match '\$driverPid\s*=\s*\[int\]\$PID' -and $wpfDriver -match 'driverSessionId' -and $wpfDriver -match 'processId=\[int\]\$process\.Id' -and $wpfDriver -match 'sessionId=\[int\]\$process\.SessionId') 'WPF driver records its own PID/session separately from candidate'
$rebootStart=$realPhase.IndexOf('function Invoke-ProductRebootBoundary {');$rebootEnd=$realPhase.IndexOf('function New-ProductLifecycleCompletionAuthority {',$rebootStart);$rebootPath=$realPhase.Substring($rebootStart,$rebootEnd-$rebootStart)
Assert-That ($rebootPath -notmatch 'Restart-Computer -Force' -and $rebootPath -notmatch 'AutoLogonCount.*100') 'product reboot path has no guest self-reboot or synthetic autologon retry'

[pscustomobject]@{status=if($failures.Count -eq 0){'PASS'}else{'FAIL'};passed=$passed;total=$total;failures=@($failures)}|ConvertTo-Json -Depth 6

```


## FILE: automation/release-e2e/tests/Test-LifecycleObserverBehavior.ps1

SHA256: 06eba1d0d13ede6fe3f63ff246d31b5bc725ef6901a430521e9641c2b4cb52f0 | Bytes: 99553 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
$module=Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1'
Import-Module $module -Force
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\HarnessBudget.psm1') -Force
Import-Module (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\GuestSession.psm1') -Force
$passed=0;$failed=[System.Collections.Generic.List[string]]::new();$script:testEvidenceDirs=[System.Collections.Generic.List[string]]::new();$lifeRoot=$null
try {
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++}else{[void]$script:failed.Add($Name)}}
$prior=[pscustomobject]@{checkpointGeneration=1;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}
function Obs([hashtable]$Values){$base=[ordered]@{checkpointPresent=$false;checkpoint=$null;matchingConsumedReceipt=$false;installStateValid=$false;canonicalOwnershipValid=$false;authenticatedHealthOk=$false;terminalFailure=$false};foreach($k in $Values.Keys){$base[$k]=$Values[$k]};[pscustomobject]$base}
$next=Obs @{checkpointPresent=$true;checkpoint=[pscustomobject]@{checkpointGeneration=2;transactionId='a'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}}
Check ((Get-DurableProgressClassification -Observation $next -PriorCheckpoint $prior -MaxGeneration 3) -eq 'NEXT_REBOOT') 'generation advancement returns NEXT_REBOOT'
$gen1=Obs @{checkpointPresent=$true;checkpoint=$prior}
Check ((Get-DurableProgressClassification -Observation $gen1 -PriorCheckpoint $prior -MaxGeneration 3) -eq 'NO_PROGRESS') 'generation 1 persistence is not another reboot'
$complete=Obs @{matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true}
Check ((Get-DurableProgressClassification -Observation $complete -PriorCheckpoint $prior) -eq 'COMPLETED') 'matching receipt/install/ownership/authenticated health returns COMPLETED'
$mismatch=Obs @{checkpointPresent=$true;checkpoint=[pscustomobject]@{checkpointGeneration=2;transactionId='c'*32;payloadSha256='b'*64;action='FreshInstall';role='Primary / Desktop';state='waiting-for-reboot'}}
$mismatch.terminalFailure=$true
Check ((Get-DurableProgressClassification -Observation $mismatch -PriorCheckpoint $prior) -eq 'TERMINAL_FAILURE') 'binding mismatch returns TERMINAL_FAILURE'
$completedCheckpoint=Obs @{checkpointPresent=$true;checkpoint=$next.checkpoint;matchingConsumedReceipt=$true;installStateValid=$true;canonicalOwnershipValid=$true;authenticatedHealthOk=$true;status='COMPLETED'}
Check ((Get-DurableProgressClassification -Observation $completedCheckpoint -PriorCheckpoint $prior -MaxGeneration 3) -eq 'TERMINAL_FAILURE') 'COMPLETED carrying an active checkpoint fails closed'
$hiddenForeignCheckpoint=Obs @{checkpointPresent=$false;checkpoint=$mismatch.checkpoint}
Check ((Get-DurableProgressClassification -Observation $hiddenForeignCheckpoint -PriorCheckpoint $prior -MaxGeneration 3) -eq 'TERMINAL_FAILURE') 'checkpointPresent false cannot hide a foreign checkpoint'
$flagWithoutCheckpoint=Obs @{checkpointPresent=$true;checkpoint=$null}
Check ((Get-DurableProgressClassification -Observation $flagWithoutCheckpoint -PriorCheckpoint $prior -MaxGeneration 3) -eq 'TERMINAL_FAILURE') 'checkpointPresent true with null checkpoint fails closed'
$pending=Obs @{}
Check ((Get-DurableProgressClassification -Observation $pending -PriorCheckpoint $prior) -ne 'NO_PROGRESS_TIMEOUT') 'DURABLE_PENDING is an intermediate observation, never timeout'
Check ((Get-Command Wait-DevFleetProductLifecycleTransition).Name -eq 'Wait-DevFleetProductLifecycleTransition') 'observer is callable at runtime'
$realPhaseModule=Get-Module Invoke-RealProductPhase
# A source test must remain runnable while shipping edits await a new signed
# candidate. Bind a temporary fixture inventory to an exact copy of this config;
# never modify the live CURRENT-CANDIDATE authority to run a unit regression.
$identityFixture=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-observer-identity-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $identityFixture 'source/config') -Force|Out-Null
[void]$script:testEvidenceDirs.Add($identityFixture)
$identityConfig=Join-Path $identityFixture 'source/config/devfleet.config.json'
Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'source/config/devfleet.config.json') -Destination $identityConfig
$identityHash=(Get-FileHash -LiteralPath $identityConfig).Hash.ToLowerInvariant()
[ordered]@{candidateIsCurrent=$true;sourceChangedSinceCandidate=$false;rebuildRequired=$false;shippingInputIdentity=('c'*64);candidateShippingInputIdentity=('c'*64);candidateGitCommit=('d'*40);candidateShippingInputs=@([ordered]@{root='source';path='config/devfleet.config.json';sha256=$identityHash})}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $identityFixture 'CURRENT-CANDIDATE.json') -Encoding utf8NoBOM
$productionContext=[pscustomobject]@{workspaceRoot=$identityFixture;r