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
