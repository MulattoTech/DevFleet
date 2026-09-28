# DevFleet source part 050

Full-source UTF-8 byte interval [2278500, 2325000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 76c7616b7cc186d5e23e9802d895767a3322cd484384b9d35793541a56842b14

<!-- BEGIN SOURCE SLICE -->
339ac25a | Bytes: 21398 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot,[switch]$Baseline)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Pass, [string]$Detail='') { $checks.Add([pscustomobject]@{ name=$Name; pass=$Pass; detail=$Detail }) }

function Import-ProductionFunction([string]$Path, [string]$Name, [switch]$Baseline) {
    $tokens = $null; $errors = $null
    if($Baseline){
        $relative=$Path.Substring($WorkspaceRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Replace([string][IO.Path]::DirectorySeparatorChar,'/')
        $sourceText=@(& git -C $WorkspaceRoot show ("HEAD:"+$relative) 2>$null)-join [Environment]::NewLine
        if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sourceText)){throw "Could not load baseline source for $relative"}
        $ast=[Management.Automation.Language.Parser]::ParseInput($sourceText,[ref]$tokens,[ref]$errors)
    }else{$ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)}
    if (@($errors).Count) { throw "Production source does not parse: $Path" }
    $found = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name }, $true))
    if ($found.Count -ne 1) { throw "Expected exactly one production function $Name in $Path" }
    $bodyText=$found[0].Body.Extent.Text.Trim()
    $bodyText=$bodyText.Substring(1,$bodyText.Length-2)
    $functionBody=if($found[0].ParamBlock){$found[0].ParamBlock.Extent.Text+[Environment]::NewLine+$bodyText}else{$bodyText}
    Set-Item -Path ("Function:\script:{0}" -f $Name) -Value ([scriptblock]::Create($functionBody))
}

Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Evidence.psm1') -Force
Import-ProductionFunction (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Cleanup.psm1') 'Write-TerminalVmEvidence' -Baseline:$Baseline
Import-ProductionFunction (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Cleanup.psm1') 'Get-DevFleetHostNameExclusion'
Import-ProductionFunction (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/FullRelease.psm1') 'Invoke-FullReleaseCleanup' -Baseline:$Baseline
Import-ProductionFunction (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/FullRelease.psm1') 'Write-PostCleanupFinalization' -Baseline:$Baseline

$script:fixture = $null
function Get-VM {
    [CmdletBinding()]
    param([guid]$Id, [string]$Name)
    if ($PSBoundParameters.ContainsKey('Id')) { return $script:fixture.vm }
    $script:fixture.hostL2Queries++
    if ($script:fixture.hostQueryDenied) { throw 'Mock host inventory denied.' }
    if ($script:fixture.hostNotFoundNative) {
        $message='Hyper-V was unable to find a virtual machine with name "'+$Name+'".'
        $target=if($script:fixture.hostNotFoundTarget){$script:fixture.hostNotFoundTarget}else{$Name}
        $record=[Management.Automation.ErrorRecord]::new([ArgumentException]::new($message),'InvalidParameter,Microsoft.HyperV.PowerShell.Commands.GetVM',[Management.Automation.ErrorCategory]::InvalidArgument,$target)
        throw $record
    }
    if ($script:fixture.hostL2Present) { return [pscustomobject]@{Name=$script:fixture.l2Name;Id=[guid]::NewGuid();State='Off'} }
    return @()
}
function New-CleanupManifest { param($Vm,$RunId) [pscustomobject]@{ runId=$RunId; resources=@() } }
function Test-CleanupManifest { param($Manifest) return $true }
function Get-AssertedDisposableVm { param($ExpectedVm) return $ExpectedVm }
function Start-VM { param($VM) $script:fixture.startCalls++;$script:fixture.vm.State='Running' }
function Stop-ManifestVm { param($Manifest) $script:fixture.stopCalls++;$script:fixture.vm.State='Off' }
function Connect-DevFleetGuest { param([guid]$VmId) return [pscustomobject]@{Id='mock-session'} }
function Clear-DevFleetE2EInteractiveLogonState { param([guid]$VmId) return [pscustomobject]@{status='PASS';registryCleanupPersisted=$true;temporaryDefaultPasswordRemovalPersisted=$true;ordinaryDefaultPasswordPresent=$false} }
function Invoke-Command { param($Session,$ScriptBlock,$ArgumentList) $script:fixture.remoteCalls++;return [pscustomobject]@{status='PASS';computer='L1';runRootAbsent=$true;uiaTasksAbsent=$true;nestedName=$script:fixture.l2Name;nestedAbsent=$true;foreignResourcesMutated=$false} }
function Remove-PSSession { param($Session) }
function Get-DevFleetNestedL2State { param($Session,$ExpectedName) $script:fixture.nestedCalls++;return [pscustomobject]@{status='UNVERIFIED';expectedName=$ExpectedName;present=$null;observedUtc='2026-09-24T00:00:00Z';verification='controlled missing or incomplete inventory'} }
function Get-FileHash {
    [CmdletBinding()]
    param([string]$LiteralPath,[string]$Algorithm)
    $hash=[Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($LiteralPath))
    [pscustomobject]@{Hash=([Convert]::ToHexString($hash))}
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-terminal-boundary-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $script:fixture = @{vm=[pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';State='Running'};l2Name='DevFleet-E2E-Linux-01';hostL2Queries=0;hostQueryDenied=$false;hostNotFoundNative=$false;hostNotFoundTarget=$null;hostL2Present=$false;startCalls=0;stopCalls=0;remoteCalls=0;nestedCalls=0}
    $script:fixture.hostNotFoundNative=$true
    $script:fixture.hostL2Queries=0
    $hostAbsent=Get-DevFleetHostNameExclusion -Name $script:fixture.l2Name
    Check 'exact Hyper-V missing-name signature means host exclusion only' ([string]$hostAbsent.status -ceq 'ABSENT' -and $hostAbsent.present -eq $false -and [string]$hostAbsent.inventoryScope -ceq 'host Hyper-V exact-name exclusion only' -and $script:fixture.hostL2Queries -eq 1) ("status=$($hostAbsent.status) scope=$($hostAbsent.inventoryScope)")
    $script:fixture.hostQueryDenied=$true
    $deniedClassificationRejected=$false
    try { Get-DevFleetHostNameExclusion -Name $script:fixture.l2Name | Out-Null } catch { $deniedClassificationRejected=$true }
    Check 'denied host inventory is not classified as absent' $deniedClassificationRejected "rejected=$deniedClassificationRejected"
    $script:fixture.hostQueryDenied=$false;$script:fixture.hostNotFoundTarget='DevFleet-E2E-Foreign'
    $wrongTargetRejected=$false
    try { Get-DevFleetHostNameExclusion -Name $script:fixture.l2Name | Out-Null } catch { $wrongTargetRejected=$true }
    Check 'missing-name signature with a different target is rejected' $wrongTargetRejected "rejected=$wrongTargetRejected"
    $script:fixture.hostNotFoundTarget=$null
    $script:fixture.hostQueryDenied=$false;$script:fixture.hostNotFoundNative=$false;$script:fixture.hostL2Present=$true
    $hostPresent=Get-DevFleetHostNameExclusion -Name $script:fixture.l2Name
    Check 'same-name host resource remains a distinct present conflict' ([string]$hostPresent.status -ceq 'PRESENT' -and $hostPresent.present -eq $true -and @($hostPresent.resources).Count -eq 1) ("status=$($hostPresent.status) rows=$(@($hostPresent.resources).Count)")
    $script:fixture.hostL2Present=$false;$script:fixture.hostNotFoundNative=$false
    $writerRun = Join-Path $tempRoot 'writer-run'; New-Item -ItemType Directory -Path $writerRun | Out-Null
    $script:fixture.hostL2Queries=0
    $writerOutput = @(Write-TerminalVmEvidence -Vm $script:fixture.vm -RunDir $writerRun -L2Name $script:fixture.l2Name)
    $written = $writerOutput[-1]
    Check 'terminal evidence writer does not infer nested absence from host lookup' ($null -eq $written.l2.present -and [string]$written.l2.status -eq 'UNVERIFIED' -and $script:fixture.hostL2Queries -eq 0) ("l2="+($written.l2|ConvertTo-Json -Compress -Depth 5)+" hostQueries=$($script:fixture.hostL2Queries)")

    $candidateTuple=[pscustomobject]@{repositoryHead=('a'*40);gitCommit=('b'*40);candidateCommit=('b'*40);shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64)}
    $writerFingerprint=[pscustomobject]@{repositoryHead=$candidateTuple.repositoryHead;gitCommit=$candidateTuple.candidateCommit;shippingInputIdentity=$candidateTuple.shippingInputIdentity;releaseFingerprintId=$candidateTuple.releaseFingerprintId;toolingFingerprintId=$candidateTuple.toolingFingerprintId}
    $script:fixture.vm.State='Off'
    $nestedWriterObservation=[pscustomobject]@{status='ABSENT';expectedName=$script:fixture.l2Name;present=$false;observedUtc='2026-09-24T00:00:01Z';verification='Bounded Multipass JSON inventory inside exact L1';exactMatchCount=0;inventoryCount=0;backendInventories=@()}
    $writerValidRun=Join-Path $tempRoot 'writer-valid-run';New-Item -ItemType Directory -Path $writerValidRun|Out-Null
    $writerValid=Write-TerminalVmEvidence -Vm $script:fixture.vm -RunDir $writerValidRun -L2Name $script:fixture.l2Name -RunId 'writer-valid-run' -NestedL2Observation $nestedWriterObservation -Candidate $writerFingerprint -EvidenceClass 'FullRelease run-bound nested observation'
    Check 'terminal writer preserves complete nested observation and source hash' ([string]$writerValid.l2.status -ceq 'ABSENT' -and $writerValid.l2.present -eq $false -and (Test-Path -LiteralPath (Join-Path $writerValidRun 'nested-l2-terminal-observation.json')) -and -not [string]::IsNullOrWhiteSpace([string]$writerValid.l2.sourceEvidenceSha256)) ("status=$($writerValid.l2.status) runId=$($writerValid.l2.runId) sourceHash=$($writerValid.l2.sourceEvidenceSha256)")
    $hostOnlyObservation=[pscustomobject]@{status='ABSENT';expectedName=$script:fixture.l2Name;present=$false;observedUtc='2026-09-24T00:00:01Z';verification='Get-VM -Name exact returned no VM';exactMatchCount=0;inventoryCount=0;backendInventories=@()}
    $hostOnlyWriterRejected=$false;try{Write-TerminalVmEvidence -Vm $script:fixture.vm -RunDir (Join-Path $tempRoot 'writer-host-only') -L2Name $script:fixture.l2Name -RunId 'writer-host-only' -NestedL2Observation $hostOnlyObservation -Candidate $writerFingerprint -EvidenceClass 'FullRelease run-bound nested observation'|Out-Null}catch{$hostOnlyWriterRejected=$true}
    Check 'terminal writer rejects host-only absence even when passed as nested input' $hostOnlyWriterRejected "rejected=$hostOnlyWriterRejected"

    $script:fixture.vm.State='Running';$script:fixture.startCalls=0;$script:fixture.stopCalls=0;$script:fixture.remoteCalls=0;$script:fixture.nestedCalls=0
    $cleanupRun = Join-Path $tempRoot 'cleanup-running'; New-Item -ItemType Directory -Path $cleanupRun | Out-Null
    $cleanupBlocked=$false
    $cleanupArgs=@{Vm=$script:fixture.vm;Config=([pscustomobject]@{NestedLinux=[pscustomobject]@{Name=$script:fixture.l2Name}});RunId='cleanup-running';RunDir=$cleanupRun}
    if((Get-Command Invoke-FullReleaseCleanup).Parameters.ContainsKey('Fingerprint')){$cleanupArgs.Fingerprint=$candidateTuple}
    try { Invoke-FullReleaseCleanup @cleanupArgs | Out-Null }
    catch { $cleanupBlocked=$true;$cleanupError=$_.Exception.Message }
    Check 'FullRelease cleanup rejects an unverified nested inventory' ($cleanupBlocked -and $script:fixture.nestedCalls -gt 0) ("blocked=$cleanupBlocked nestedCalls=$($script:fixture.nestedCalls) error=$cleanupError")

    $script:fixture.vm.State='Off';$script:fixture.startCalls=0;$script:fixture.stopCalls=0;$script:fixture.nestedCalls=0
    $offRun = Join-Path $tempRoot 'cleanup-off'; New-Item -ItemType Directory -Path $offRun | Out-Null
    $offBlocked=$false
    $offArgs=@{Vm=$script:fixture.vm;Config=([pscustomobject]@{NestedLinux=[pscustomobject]@{Name=$script:fixture.l2Name}});RunId='cleanup-off';RunDir=$offRun}
    if((Get-Command Invoke-FullReleaseCleanup).Parameters.ContainsKey('Fingerprint')){$offArgs.Fingerprint=$candidateTuple}
    try { Invoke-FullReleaseCleanup @offArgs | Out-Null }
    catch { $offBlocked=$true;$offError=$_.Exception.Message }
    Check 'FullRelease cleanup does not restart an already-Off L1 to refresh metadata' ($offBlocked -and $script:fixture.startCalls -eq 0) ("blocked=$offBlocked starts=$($script:fixture.startCalls) error=$offError")

    $postRun = Join-Path $tempRoot 'audit/automation-harness/runs/post-run'; New-Item -ItemType Directory -Path $postRun -Force | Out-Null
    $cleanup = [ordered]@{status='PASS';runId='post-run';candidate=$candidateTuple;l1=[ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';state='Off';deleted=$false};guest=[ordered]@{runRootAbsent=$true;nestedAbsent=$true;foreignResourcesMutated=$false}}
    $l1 = [ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';state='Off';timestampUtc='2026-09-24T00:00:02Z';runId='post-run';ownershipScope='exact disposable'}
    $nested=[ordered]@{schemaVersion=1;runId='post-run';status='ABSENT';expectedName=$script:fixture.l2Name;present=$false;observedUtc='2026-09-24T00:00:01Z';verification='Bounded Multipass JSON inventory inside exact L1';exactMatchCount=0;inventoryCount=0;backendInventories=@();candidate=$candidateTuple;l1=[ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2'};nestedScope='inside the exact L1 guest session';observer='Get-DevFleetNestedL2State';evidenceClass='FullRelease run-bound nested observation'}
    $nestedPath=Join-Path $postRun 'nested-l2-terminal-observation.json';Write-EvidenceJson -Path $nestedPath -Value $nested;$nestedHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $l2=[ordered]@{schemaVersion=2;expectedName=$script:fixture.l2Name;status='ABSENT';present=$false;timestampUtc=$nested.observedUtc;verificationMethod=$nested.verification;nestedScope=$nested.nestedScope;backendInventories=@();runId='post-run';sourceRunId='post-run';sourceEvidence='nested-l2-terminal-observation.json';sourceEvidenceSha256=$nestedHash;l1Name='DevFleet-E2E-Win11-01';l1Id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';candidate=$candidateTuple;evidenceClass='FullRelease run-bound nested observation'}
    Write-EvidenceJson -Path (Join-Path $postRun 'final-cleanup.json') -Value $cleanup
    Write-EvidenceJson -Path (Join-Path $postRun 'l1-terminal-state.json') -Value $l1
    $l2Path=Join-Path $postRun 'l2-terminal-state.json'
    $hostOnlyNested=[ordered]@{schemaVersion=1;runId='post-run';status='ABSENT';expectedName=$script:fixture.l2Name;present=$false;observedUtc='2026-09-24T00:00:01Z';verification='Get-VM -Name exact returned no VM';exactMatchCount=0;inventoryCount=0;backendInventories=@();candidate=$candidateTuple;l1=[ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2'};nestedScope='inside the exact L1 guest session';observer='Get-DevFleetNestedL2State';evidenceClass='FullRelease run-bound nested observation'}
    Write-EvidenceJson -Path $nestedPath -Value $hostOnlyNested;$hostOnlyHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $hostOnlyL2=[ordered]@{};foreach($key in $l2.Keys){$hostOnlyL2[$key]=$l2[$key]};$hostOnlyL2.verificationMethod=$hostOnlyNested.verification;$hostOnlyL2.sourceEvidenceSha256=$hostOnlyHash
    Write-EvidenceJson -Path $l2Path -Value $hostOnlyL2
    $script:fixture.hostL2Queries=0;$script:fixture.hostL2Present=$false;$script:fixture.hostQueryDenied=$false
    $postRejected=$false
    $postState=[pscustomobject]@{runId='post-run';candidateHashes=$candidateTuple}
    $postArgs=@{State=$postState;Vm=([pscustomobject]@{Name=$l1.name;Id=[guid]$l1.id;State='Off'});Config=([pscustomobject]@{NestedLinux=[pscustomobject]@{Name=$script:fixture.l2Name}});RunDir=$postRun;Records=@([pscustomobject]@{id='CLEANUP';status='PASS';evidence=@{status='PASS'}})}
    if((Get-Command Write-PostCleanupFinalization).Parameters.ContainsKey('WorkspaceRoot')){$postArgs.WorkspaceRoot=$tempRoot}
    try { Write-PostCleanupFinalization @postArgs | Out-Null }
    catch { $postRejected=$true;$postError=$_.Exception.Message }
    Check 'post-cleanup finalizer rejects host-only L2 absence evidence' ($postRejected -and $postError -match 'unsupported inventory method' -and $script:fixture.hostL2Queries -eq 0) ("rejected=$postRejected hostQueries=$($script:fixture.hostL2Queries) error=$postError")

    Write-EvidenceJson -Path $nestedPath -Value $nested;$validNestedHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant();$l2.sourceEvidenceSha256=$validNestedHash
    Write-EvidenceJson -Path $l2Path -Value $l2
    $script:fixture.hostL2Queries=0;$script:fixture.hostQueryDenied=$true
    $hostDeniedRejected=$false
    try { Write-PostCleanupFinalization @postArgs | Out-Null }
    catch { $hostDeniedRejected=$true;$hostDeniedError=$_.Exception.Message }
    Check 'post-cleanup host conflict check fails closed on access denial' ($hostDeniedRejected -and $script:fixture.hostL2Queries -eq 1) ("rejected=$hostDeniedRejected hostQueries=$($script:fixture.hostL2Queries) error=$hostDeniedError")

    $script:fixture.hostL2Queries=0;$script:fixture.hostQueryDenied=$false;$script:fixture.hostNotFoundNative=$true
    $hostAbsentPost=$null;$hostAbsentPostError=$null
    try { $hostAbsentPost=Write-PostCleanupFinalization @postArgs } catch { $hostAbsentPostError=$_.Exception.Message }
    Check 'post-cleanup accepts exact host absence while retaining nested proof requirement' ($hostAbsentPost -and [string]$hostAbsentPost.status -ceq 'PASS' -and $hostAbsentPost.liveChecks.hostSameNameL2Absent -eq $true -and $hostAbsentPost.liveChecks.l2ExactAbsent -eq $true -and $script:fixture.hostL2Queries -eq 1) ("status=$($hostAbsentPost.status) hostQueries=$($script:fixture.hostL2Queries) error=$hostAbsentPostError")

    $script:fixture.hostL2Queries=0;$script:fixture.hostNotFoundNative=$false;$script:fixture.hostL2Present=$true
    $hostConflictPostRejected=$false
    try { Write-PostCleanupFinalization @postArgs | Out-Null } catch { $hostConflictPostRejected=$true }
    Check 'post-cleanup preserves same-name host resource and blocks promotion' ($hostConflictPostRejected -and $script:fixture.hostL2Queries -eq 1) "rejected=$hostConflictPostRejected"

    $script:fixture.hostL2Queries=0;$script:fixture.hostL2Present=$false;$script:fixture.hostNotFoundNative=$true;$script:fixture.hostQueryDenied=$false
    $nested.verification='Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend'
    $nested.inventoryCount=2
    $nested.backendInventories=@([ordered]@{provider='Hyper-V';status='PASS';names=@('foreign-instance','foreign-instance');verification='bounded Hyper-V inventory'},[ordered]@{provider='VirtualBox';status='PASS';names=@();verification='bounded VirtualBox inventory'})
    Write-EvidenceJson -Path $nestedPath -Value $nested;$nestedHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $l2.verificationMethod=$nested.verification;$l2.backendInventories=$nested.backendInventories;$l2.sourceEvidenceSha256=$nestedHash
    Write-EvidenceJson -Path $l2Path -Value $l2
    $malformedBackendPostRejected=$false
    try { Write-PostCleanupFinalization @postArgs | Out-Null } catch { $malformedBackendPostRejected=$true;$malformedBackendPostError=$_.Exception.Message }
    Check 'post-cleanup consumer rejects duplicate nested backend instance names' ($malformedBackendPostRejected -and $malformedBackendPostError -match 'duplicate instance name') "rejected=$malformedBackendPostRejected error=$malformedBackendPostError"

    $nested.verification='Bounded Multipass JSON inventory inside exact L1';$nested.inventoryCount=0;$nested.backendInventories=@();$nested.candidate=[ordered]@{}
    $l2.verificationMethod=$nested.verification;$l2.backendInventories=@();$l2.candidate=[ordered]@{}
    $cleanup.candidate=[ordered]@{};$postArgs.State.candidateHashes=[ordered]@{}
    Write-EvidenceJson -Path $nestedPath -Value $nested;$nestedHash=(Get-FileHash -LiteralPath $nestedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $l2.sourceEvidenceSha256=$nestedHash;Write-EvidenceJson -Path $l2Path -Value $l2
    Write-EvidenceJson -Path (Join-Path $postRun 'final-cleanup.json') -Value $cleanup
    $emptyTuplePostRejected=$false
    try { Write-PostCleanupFinalization @postArgs | Out-Null } catch { $emptyTuplePostRejected=$true;$emptyTuplePostError=$_.Exception.Message }
    Check 'post-cleanup consumer rejects a missing candidate tuple' ($emptyTuplePostRejected -and $emptyTuplePostError -match 'candidate tuple is malformed or incomplete') "rejected=$emptyTuplePostRejected error=$emptyTuplePostError"
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

$failed = @($checks | Where-Object { -not $_.pass })
[ordered]@{scope='VM_FREE_PRODUCTION_TERMINAL_BOUNDARY_REGRESSION';certificationCredit=$false;status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;checks=@($checks);productionSources=@('Cleanup.psm1::Write-TerminalVmEvidence','Cleanup.psm1::Get-DevFleetHostNameExclusion','FullRelease.psm1::Invoke-FullReleaseCleanup','FullRelease.psm1::Write-PostCleanupFinalization')} | ConvertTo-Json -Depth 8
if ($failed.Count) { exit 1 }

```


## FILE: automation/release-e2e/tests/Test-ToolRuntimeResolution.ps1

SHA256: e5829ce5758969d6a5251f41f3c2005181b4955e438e18cef868229f0e9f0ed5 | Bytes: 902 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
Import-Module (Join-Path $WorkspaceRoot 'tools\PythonRuntime.psm1') -Force
$python = Resolve-DevFleetPython -Workspace $WorkspaceRoot
$version = @(& $python --version 2>&1)
$insideWorkspace = [IO.Path]::GetFullPath($python).StartsWith(([IO.Path]::GetFullPath($WorkspaceRoot) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)
$status = if($LASTEXITCODE -eq 0 -and ($version -join ' ') -match '^Python 3\.' -and (Test-Path -LiteralPath $python -PathType Leaf) -and $insideWorkspace){'PASS'}else{'FAIL'}
[pscustomobject]@{status=$status;runtime=[IO.Path]::GetFileName($python);version=($version -join ' ');repositoryLocal=$insideWorkspace}|ConvertTo-Json -Depth 4
if($status -ne 'PASS'){exit 1}

```


## FILE: automation/release-e2e/tests/Test-WpfLaunchBoundaryBehavior.ps1

SHA256: 77560263503899607a2157a4905704dcaf7713095af2887ca7358cecf5f44e9a | Bytes: 41033 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)

$ErrorActionPreference = 'Stop'
if (-not $WorkspaceRoot) { $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }

$modulePath = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\WpfLaunchContract.psm1'
$driverPath = Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-WpfUiAutomation.ps1'
$passed = 0
$failures = [System.Collections.Generic.List[string]]::new()
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("devfleet-wpf-boundary-test-{0}" -f [guid]::NewGuid().ToString('N'))

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++ } else { [void]$script:failures.Add($Name) }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Import-Module $modulePath -Force

    $driverTokens = $null
    $driverParseErrors = $null
    $driverAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $driverPath).Path,
        [ref]$driverTokens,
        [ref]$driverParseErrors
    )
    $readObservedAst = $driverAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'Read-ObservedJsonFile'
    }, $true)
    Check (@($driverParseErrors).Count -eq 0 -and $null -ne $readObservedAst) 'WPF driver observation helper remains parseable and discoverable'
    if ($null -ne $readObservedAst) {
        $readObservedText = [string]$readObservedAst.Extent.Text
        $inaccessibleObservation = & {
            function Test-Path { throw [System.UnauthorizedAccessException]::new('Access is denied') }
            Invoke-Expression $readObservedText
            Read-ObservedJsonFile -Path 'C:\blocked-observation' -Kind TERMINAL
        }
        Check ($null -eq $inaccessibleObservation) 'inaccessible observation files are treated as absent so the bounded WPF watchdog can retry'
        $observedJsonPath=Join-Path $scratch 'observed-terminal.json'
        [IO.File]::WriteAllText($observedJsonPath,'{"status":"PASS"}'+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
        $observedWithoutContentProvider=& {
            function Get-Content { throw [InvalidOperationException]::new('Get-Content must not own atomic WPF observation reads') }
            Invoke-Expression $readObservedText
            Read-ObservedJsonFile -Path $observedJsonPath -Kind TERMINAL
        }
        Check ([string]$observedWithoutContentProvider.value.status -ceq 'PASS') 'atomic WPF terminal/progress observation reads do not depend on the stalled PowerShell content provider'
    }

    $readBootstrapAst = $driverAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'Read-BootstrapLaunchSpecification'
    }, $true)
    Check ($null -ne $readBootstrapAst) 'WPF bootstrap request reader remains parseable and discoverable'
    if ($null -ne $readBootstrapAst) {
        $readBootstrapText = [string]$readBootstrapAst.Extent.Text
        $bootstrapRequestPath = Join-Path $scratch 'bootstrap-read-request.json'
        [IO.File]::WriteAllText($bootstrapRequestPath, '{"candidateSha256":"' + ('a' * 64) + '"}' + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        $bootstrapRead = & {
            function Get-Content { throw [InvalidOperationException]::new('Get-Content must not be used for task-context bootstrap reads') }
            Invoke-Expression $readBootstrapText
            Read-BootstrapLaunchSpecification -Path $bootstrapRequestPath -DeadlineUtc ([DateTime]::UtcNow.AddMinutes(1).ToString('o'))
        }
        Check ([string]$bootstrapRead.candidateSha256 -ceq ('a' * 64)) 'task-context bootstrap request reader uses bounded .NET file I/O rather than the hanging PowerShell content provider'
        $absentRequestFailure='';try{& {Invoke-Expression $readBootstrapText;Read-BootstrapLaunchSpecification -Path (Join-Path $scratch 'absent-request.json') -DeadlineUtc ([DateTimeOffset]::UtcNow.AddMilliseconds(900).ToString('o'))}|Out-Null}catch{$absentRequestFailure=$_.Exception.Message}
        Check ($absentRequestFailure -match 'did not become visible before the bounded bootstrap deadline') 'absent launch request fails within its inherited bootstrap deadline'
        $corruptRequestPath=Join-Path $scratch 'corrupt-request.json';[IO.File]::WriteAllText($corruptRequestPath,'{"schemaVersion":',[Text.UTF8Encoding]::new($false))
        $corruptRequestFailure='';try{& {Invoke-Expression $readBootstrapText;Read-BootstrapLaunchSpecification -Path $corruptRequestPath -DeadlineUtc ([DateTimeOffset]::UtcNow.AddSeconds(2).ToString('o'))}|Out-Null}catch{$corruptRequestFailure=$_.Exception.Message}
        Check ($corruptRequestFailure -match 'was not readable before the bounded bootstrap deadline') 'corrupt launch request fails within its inherited bootstrap deadline'
    }

    foreach($role in @('Primary / Desktop','Laptop / Surrogate')){
        foreach($mode in @('initial','direct','resume')){
            $arguments=Get-WpfCandidateArguments -LaunchMode $mode -Action FreshInstall -Role $role -ElevatedResume:($mode-eq'resume')
            Check (($arguments-contains'--defer-network-pairing')-eq($role-eq'Primary / Desktop')) "$role $mode honors supported network-pairing choice"
            Check ($arguments[$arguments.IndexOf('--role')+1]-ceq$role) "$role $mode preserves exact reviewed role"
        }
    }

    $now = [datetime]'2026-09-05T20:00:00Z'
    $ownerDeadline = $now.AddSeconds(480)
    $common = @{
        DriverPath = $driverPath
        ExePath = (Get-Command powershell.exe).Source
        Action = 'FreshInstall'
        Role = 'Primary / Desktop'
        OutputPath = (Join-Path $scratch 'final.json')
        StartedPath = (Join-Path $scratch 'started.json')
        CheckpointPath = (Join-Path $scratch 'checkpoint.json')
        WorkerResultPath = (Join-Path $scratch 'worker.json')
        LaunchRequestPath = (Join-Path $scratch 'request.json')
        RunId = 'wpf-boundary-regression'
        LaunchId = ('1' * 32)
        TransactionId = ('2' * 32)
        PayloadSha256 = ('3' * 64)
        ExpectedInteractiveSessionId = 1
        AllowMutation = $true
        AllowRebootRequired = $true
        OwnerDeadlineUtc = $ownerDeadline
        ClockProvider = { $now }
    }

    $resume = New-WpfLaunchSpecification @common -LaunchMode resume -ElevatedResume
    Check ($resume.taskArguments -match '(?:^| )-ElevatedResume(?: |$)' -and $resume.taskArguments -match '-LaunchMode (?:"resume"|resume)') 'resume mode reaches the actual driver task arguments'
    Check (@($resume.candidateArguments)[0] -eq '--elevated-resume') 'resume mode reaches the actual candidate argument vector'
    Check ([datetime]$resume.boundaryDeadlineUtc -eq $ownerDeadline -and [datetime]$resume.driverDeadlineUtc -lt $ownerDeadline) 'child and terminalization deadlines consume the finite remaining owner budget'
    $actualBinding=@{ExePath=$resume.exePath;Action=$resume.action;Role=$resume.role;OutputPath=$resume.outputPath;StartedPath=$resume.startedPath;CheckpointPath=$resume.checkpointPath;WorkerResultPath=$resume.workerResultPath;LaunchRequestPath=$resume.launchRequestPath;RunId=$resume.runId;LaunchId=$resume.launchId;TransactionId=$resume.transactionId;PayloadSha256=$resume.payloadSha256;LaunchMode=$resume.launchMode;ObserverDeadlineUtc=$resume.driverDeadlineUtc;ExpectedInteractiveSessionId=$resume.expectedInteractiveSessionId;AllowMutation=$resume.allowMutation;AllowRebootRequired=$resume.allowRebootRequired;UseDurableCompletionFallback=$resume.useDurableCompletionFallback;ElevatedResume=$resume.elevatedResume;ContractProbe=$resume.contractProbe;ContractModulePath=''}
    $wrongRunBinding=@{}+$actualBinding;$wrongRunBinding.RunId='wrong-run';$wrongRunRejected=$false;try{Assert-WpfDriverBinding -Specification $resume -Actual $wrongRunBinding|Out-Null}catch{$wrongRunRejected=$_.Exception.Message -match 'runId'}
    Check $wrongRunRejected 'launch request with a wrong run identity is rejected before product start'
    $wrongHashSpec=$resume|Select-Object *;$wrongHashSpec.candidateSha256='f'*64;$wrongHashRejected=$false;try{Assert-WpfDriverBinding -Specification $wrongHashSpec -Actual $actualBinding|Out-Null}catch{$wrongHashRejected=$_.Exception.Message -match 'candidate hash'}
    Check $wrongHashRejected 'launch request with a wrong candidate hash is rejected before product start'

    $handoffCommon = @{} + $common
    $handoffCommon.LaunchId = ('d' * 32)
    $handoffCommon.OutputPath = Join-Path $scratch 'handoff-final.json'
    $handoffCommon.StartedPath = Join-Path $scratch 'handoff-started.json'
    $handoffCommon.CheckpointPath = Join-Path $scratch 'handoff-checkpoint.json'
    $handoffCommon.WorkerResultPath = Join-Path $scratch 'handoff-worker.json'
    $handoffCommon.LaunchRequestPath = Join-Path $scratch 'handoff-request.json'
    $handoffSpec = New-WpfLaunchSpecification @handoffCommon -LaunchMode resume -ElevatedResume -UseDurableCompletionFallback -ContractProbe
    Write-WpfAtomicJson -Path $handoffSpec.launchRequestPath -Value $handoffSpec
    $handoffProbe = Start-Process -FilePath $handoffSpec.taskExecutable -ArgumentList ([string]$handoffSpec.taskArguments) -PassThru -Wait
    $handoffProbeReport = Get-Content -LiteralPath $handoffSpec.outputPath -Raw | ConvertFrom-Json
    Check ($handoffProbe.ExitCode -eq 0 -and [string]$handoffProbeReport.status -eq 'CONTRACT_PROBE_PASS') 'resume product-observer handoff survives actual task argument construction and driver parsing'
    $pageSeparator=[char]0x00B7
    Check ((Get-WpfNavigationDisposition -LaunchMode initial -ElevatedResume $false -WindowOwnerMatches $true -PageKicker "STEP 1 OF 8 $pageSeparator WELCOME" -OperationStatus '' -NextEnabled $true -ExecutePresent $false -ExecuteEnabled $false) -eq 'NAVIGATE') 'initial launch navigates only when the exact owned window exposes Next'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $true -PageKicker "STEP 1 OF 8 $pageSeparator WELCOME" -OperationStatus '' -NextEnabled $true -ExecutePresent $false -ExecuteEnabled $false) -eq 'WAIT') 'elevated resume ignores a transient pre-auto-execution Next control'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $true -PageKicker "STEP 7 OF 8 $pageSeparator EXECUTE" -OperationStatus 'Invoking actual installer lifecycle' -NextEnabled $false -ExecutePresent $true -ExecuteEnabled $false) -eq 'OBSERVE_EXISTING') 'elevated resume observes the exact owned in-flight auto-execution page'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $true -PageKicker "STEP 7 OF 8 $pageSeparator EXECUTE" -OperationStatus 'Reboot required; checkpoint preserved' -NextEnabled $false -ExecutePresent $true -ExecuteEnabled $true) -eq 'OBSERVE_EXISTING') 'elevated resume observes terminal reboot state even after Execute is re-enabled'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $true -PageKicker "STEP 8 OF 8 $pageSeparator FINISH" -OperationStatus 'Completed and verified' -NextEnabled $false -ExecutePresent $false -ExecuteEnabled $false) -eq 'OBSERVE_EXISTING') 'elevated resume observes an already-completed Finish page'
    Check ((Get-WpfNavigationDisposition -LaunchMode resume -ElevatedResume $true -WindowOwnerMatches $false -PageKicker "STEP 7 OF 8 $pageSeparator EXECUTE" -OperationStatus 'Completed and verified' -NextEnabled $false -ExecutePresent $true -ExecuteEnabled $true) -eq 'REJECT_OWNER_MISMATCH') 'post-launch window ownership divergence is rejected immediately'

    $longOwnerCommon = @{} + $common
    $longOwnerCommon.OwnerDeadlineUtc = $now.AddSeconds(2400)
    $longOwnerCommon.LaunchId = ('c' * 32)
    $longOwner = New-WpfLaunchSpecification @longOwnerCommon -LaunchMode resume -ElevatedResume -SemanticNoProgressSeconds 1800
    Check ([datetime]$longOwner.driverDeadlineUtc -eq ([datetime]$longOwner.ownerDeadlineUtc).AddSeconds(-60) -and [int]$longOwner.semanticNoProgressSeconds -eq 1800) 'WPF launch inherits the owner deadline and configured semantic no-progress budget without a hidden clamp'

    $bootstrapRoot = Join-Path $scratch 'bootstrap-failure'
    New-Item -ItemType Directory -Path $bootstrapRoot -Force | Out-Null
    $bootstrapDriver = Join-Path $bootstrapRoot 'Invoke-WpfUiAutomation.ps1'
    Copy-Item -LiteralPath $driverPath -Destination $bootstrapDriver -Force
    $bootstrapCommon = @{} + $common
    $bootstrapCommon.DriverPath = $bootstrapDriver
    $bootstrapCommon.OutputPath = Join-Path $bootstrapRoot 'terminal.json'
    $bootstrapCommon.StartedPath = Join-Path $bootstrapRoot 'started.json'
    $bootstrapCommon.CheckpointPath = Join-Path $bootstrapRoot 'checkpoint.json'
    $bootstrapCommon.WorkerResultPath = Join-Path $bootstrapRoot 'worker.json'
    $bootstrapCommon.LaunchRequestPath = Join-Path $bootstrapRoot 'request.json'
    $bootstrapCommon.LaunchId = ('b' * 32)
    $bootstrapSpec = New-WpfLaunchSpecification @bootstrapCommon -LaunchMode initial -ContractProbe
    Write-WpfAtomicJson -Path $bootstrapSpec.launchRequestPath -Value $bootstrapSpec
    $bootstrapProcess = Start-Process -FilePath $bootstrapSpec.taskExecutable -ArgumentList ([string]$bootstrapSpec.taskArguments) -PassThru -Wait
    $bootstrapReport = Get-Content -LiteralPath $bootstrapSpec.outputPath -Raw | ConvertFrom-Json
    Check ($bootstrapProcess.ExitCode -eq 2 -and [string]$bootstrapReport.status -eq 'OBSERVER_FAILURE' -and [string]$bootstrapReport.failureClass -eq 'DRIVER_BOOTSTRAP_FAILURE' -and [bool]$bootstrapReport.terminal -and -not [bool]$bootstrapReport.completionVerified -and [string]$bootstrapReport.runId -ceq $bootstrapSpec.runId -and [string]$bootstrapReport.launchId -ceq $bootstrapSpec.launchId -and [string]$bootstrapReport.payloadSha256 -ceq $bootstrapSpec.payloadSha256 -and [string]$bootstrapReport.candidateSha256 -ceq $bootstrapSpec.candidateSha256 -and $bootstrapReport.productStarted -eq $false -and -not [bool]$bootstrapReport.mutationInvoked -and -not (Test-Path -LiteralPath $bootstrapSpec.startedPath)) 'actual driver publishes an identity-bound terminal with productStarted=false before candidate launch when contract bootstrap fails'

    $delayedRoot = Join-Path $scratch 'delayed-launch-request'
    New-Item -ItemType Directory -Path $delayedRoot -Force | Out-Null
    $delayedDriver = Join-Path $delayedRoot 'Invoke-WpfUiAutomation.ps1'
    Copy-Item -LiteralPath $driverPath -Destination $delayedDriver -Force
    Copy-Item -LiteralPath $modulePath -Destination (Join-Path $delayedRoot 'WpfLaunchContract.psm1') -Force
    $delayedCommon = @{} + $common
    $delayedCommon.DriverPath = $delayedDriver
    $delayedCommon.OutputPath = Join-Path $delayedRoot 'terminal.json'
    $delayedCommon.StartedPath = Join-Path $delayedRoot 'started.json'
    $delayedCommon.CheckpointPath = Join-Path $delayedRoot 'checkpoint.json'
    $delayedCommon.WorkerResultPath = Join-Path $delayedRoot 'worker.json'
    $delayedCommon.LaunchRequestPath = Join-Path $delayedRoot 'request.json'
    $delayedCommon.LaunchId = ('8' * 32)
    $delayedCommon.ClockProvider = { (Get-Date).ToUniversalTime() }
    $delayedCommon.OwnerDeadlineUtc = (Get-Date).ToUniversalTime().AddMinutes(5)
    $delayedSpec = New-WpfLaunchSpecification @delayedCommon -LaunchMode initial -ContractProbe
    $delayedProbe = Start-Process -FilePath $delayedSpec.taskExecutable -ArgumentList ([string]$delayedSpec.taskArguments) -PassThru
    Start-Sleep -Milliseconds 500
    Write-WpfAtomicJson -Path $delayedSpec.launchRequestPath -Value $delayedSpec
    $delayedProbe.WaitForExit()
    $delayedReport = Get-Content -LiteralPath $delayedSpec.outputPath -Raw | ConvertFrom-Json
    Check ($delayedProbe.ExitCode -eq 0 -and [string]$delayedReport.status -eq 'CONTRACT_PROBE_PASS' -and [string]$delayedReport.candidateSha256 -ceq $delayedSpec.candidateSha256) 'driver waits for the exact launch request when task startup races remote file visibility'

    $sidResolver = { param($account) if ($account -in @('DEVFLEET-E2E-01\E2EAdmin','E2EAdmin')) { 'S-1-5-21-100-200-300-1001' } else { 'S-1-5-21-100-200-300-9999' } }
    $requestedPrincipal = [pscustomobject]@{UserId='DEVFLEET-E2E-01\E2EAdmin';LogonType=3;RunLevel=1}
    $registered = [pscustomobject]@{Actions=@([pscustomobject]@{Execute=$resume.taskExecutable.ToUpperInvariant();Arguments=$resume.taskArguments});Principal=[pscustomobject]@{UserId='E2EAdmin';LogonType=3;RunLevel=1}}
    $taskReason='';$taskEvidence=$null
    Check ((Test-WpfRegisteredTaskBinding -Specification $resume -RegisteredTask $registered -RequestedPrincipal $requestedPrincipal -Reason ([ref]$taskReason) -Evidence ([ref]$taskEvidence) -SidResolver $sidResolver) -and $taskEvidence.verifiedBeforeStart -and $taskEvidence.principalSidSha256 -match '^[0-9a-f]{64}$') 'registered task accepts normalized account text only when the principal SID, enums, executable, and arguments are exact'
    $wrongPrincipal = [pscustomobject]@{Actions=$registered.Actions;Principal=[pscustomobject]@{UserId='OtherUser';LogonType=3;RunLevel=1}}
    $taskReason='';$taskEvidence=$null
    Check (-not (Test-WpfRegisteredTaskBinding -Specification $resume -RegisteredTask $wrongPrincipal -RequestedPrincipal $requestedPrincipal -Reason ([ref]$taskReason) -Evidence ([ref]$taskEvidence) -SidResolver $sidResolver) -and $taskReason -eq 'registered task principal SID diverged') 'registered task rejects a different principal identity before start'
    $wrongArguments = [pscustomobject]@{Actions=@([pscustomobject]@{Execute=$resume.taskExecutable;Arguments=($resume.taskArguments+' -ElevatedResume')});Principal=$registered.Principal}
    $taskReason='';$taskEvidence=$null
    Check (-not (Test-WpfRegisteredTaskBinding -Specification $resume -RegisteredTask $wrongArguments -RequestedPrincipal $requestedPrincipal -Reason ([ref]$taskReason) -Evidence ([ref]$taskEvidence) -SidResolver $sidResolver) -and $taskReason -eq 'registered task arguments diverged') 'registered task rejects post-registration argument divergence before start'
    $realPhaseSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'automation\release-e2e\modules\executors\Invoke-RealProductPhase.psm1') -Raw
    Check ($realPhaseSource -notmatch 'Import-Module \(\[string\]\$spec\.contractModulePath\)' -and $realPhaseSource -match 'Resolve-TaskSid' -and $realPhaseSource -match 'REGISTERED_TASK_BINDING_MISMATCH') 'restricted PowerShell Direct pre-start validation does not import a staged script module'

    $initialCommon = @{} + $common
    $initialCommon.LaunchId = ('4' * 32)
    $initialCommon.OutputPath = Join-Path $scratch 'initial-final.json'
    $initialCommon.StartedPath = Join-Path $scratch 'initial-started.json'
    $initialCommon.CheckpointPath = Join-Path $scratch 'initial-checkpoint.json'
    $initialCommon.WorkerResultPath = Join-Path $scratch 'initial-worker.json'
    $initialCommon.LaunchRequestPath = Join-Path $scratch 'initial-request.json'
    $initial = New-WpfLaunchSpecification @initialCommon -LaunchMode initial
    Check ($initial.taskArguments -notmatch '(?:^| )-ElevatedResume(?: |$)' -and @($initial.candidateArguments) -notcontains '--elevated-resume') 'initial mode cannot silently inherit resume arguments'

    $initialProbeSpec = Copy-WpfLaunchSpecification -Specification $initial -ContractProbe
    Write-WpfAtomicJson -Path $initialProbeSpec.launchRequestPath -Value $initialProbeSpec
    $initialProbe = Start-Process -FilePath $initialProbeSpec.taskExecutable -ArgumentList ([string]$initialProbeSpec.taskArguments) -PassThru -Wait
    $initialProbeReport = Get-Content -LiteralPath $initialProbeSpec.outputPath -Raw | ConvertFrom-Json
    Check ($initialProbe.ExitCode -eq 0 -and [string]$initialProbeReport.status -eq 'CONTRACT_PROBE_PASS') 'Windows PowerShell parser binds the exact generated initial task action'
    Check ([string]$initialProbeReport.launchMode -eq 'initial' -and -not [bool]$initialProbeReport.elevatedResume -and (@($initialProbeReport.candidateArguments) -join [char]0) -ceq (@($initial.candidateArguments) -join [char]0) -and @($initialProbeReport.candidateArguments) -notcontains '--elevated-resume') 'driver parser acknowledgement keeps initial mode free of resume candidate arguments'

    Write-WpfAtomicJson -Path $resume.launchRequestPath -Value $resume
    $probeSpec = Copy-WpfLaunchSpecification -Specification $resume -ContractProbe
    Write-WpfAtomicJson -Path $probeSpec.launchRequestPath -Value $probeSpec
    $probe = Start-Process -FilePath $probeSpec.taskExecutable -ArgumentList ([string]$probeSpec.taskArguments) -PassThru -Wait
    $probeReport = Get-Content -LiteralPath $probeSpec.outputPath -Raw | ConvertFrom-Json
    Check ($probe.ExitCode -eq 0 -and [string]$probeReport.status -eq 'CONTRACT_PROBE_PASS') 'Windows PowerShell parser binds the exact generated resume task action'
    Check ([string]$probeReport.launchMode -eq 'resume' -and [bool]$probeReport.elevatedResume -and @($probeReport.candidateArguments)[0] -eq '--elevated-resume') 'driver parser acknowledgement matches requested mode and candidate arguments'

    $expected = [pscustomobject]$resume
    $complete = [pscustomobject]@{schemaVersion=2;contract='devfleet-wpf-terminal-v2';status='PASS';terminal=$true;completionVerified=$true;runId=$resume.runId;launchId=$resume.launchId;transactionId=$resume.transactionId;payloadSha256=$resume.payloadSha256;candidateSha256=$resume.candidateSha256;sequence=8;cleanupDisposition='CLEANUP_EXACT_CANDIDATE';deadlineUtc=$resume.driverDeadlineUtc}
    $reason = ''
    Check (Test-WpfTerminalReport -Report $complete -Specification $expected -Reason ([ref]$reason)) 'completed report with exact launch identity is accepted'
    $incomplete = $complete | Select-Object *
    $incomplete.completionVerified = $false
    $reason = ''
    Check (-not (Test-WpfTerminalReport -Report $incomplete -Specification $expected -Reason ([ref]$reason))) 'completed-lifecycle PASS with completionVerified false is rejected'
    $stale = $complete | Select-Object *
    $stale.launchId = ('9' * 32)
    $reason = ''
    Check (-not (Test-WpfTerminalReport -Report $stale -Specification $expected -Reason ([ref]$reason))) 'stale or wrong-launch report is rejected'
    $wrongPayload = $complete | Select-Object *
    $wrongPayload.payloadSha256 = ('a' * 64)
    $reason = ''
    Check (-not (Test-WpfTerminalReport -Report $wrongPayload -Specification $expected -Reason ([ref]$reason))) 'wrong-payload report is rejected'
    foreach($mismatchName in @('runId','transactionId','candidateSha256')){
        $mismatched=$complete|Select-Object *;$mismatched.$mismatchName=if($mismatchName-eq'candidateSha256'){('b'*64)}elseif($mismatchName-eq'transactionId'){('c'*32)}else{'another-run'};$reason=''
        Check (-not(Test-WpfTerminalReport -Report $mismatched -Specification $expected -Reason ([ref]$reason))) "wrong-$mismatchName report is rejected"
    }
    $reason=''
    Check (-not(Test-WpfTerminalReport -Report $complete -Specification $expected -Reason ([ref]$reason) -MinimumSequenceExclusive 8)) 'duplicate or regressed terminal sequence is rejected against prior accepted evidence'
    $unverifiedPending = $complete | Select-Object *
    $unverifiedPending.status = 'DURABLE_PENDING'
    $unverifiedPending.completionVerified = $false
    $reason = ''
    Check (-not (Test-WpfTerminalReport -Report $unverifiedPending -Specification $expected -Reason ([ref]$reason))) 'pending