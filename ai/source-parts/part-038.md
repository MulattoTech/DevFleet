# DevFleet source part 038

Full-source UTF-8 byte interval [1720500, 1767000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: a6fa498beff17c5f5923eca5efc243804029ed720af8821a0f59a66380622d3d

<!-- BEGIN SOURCE SLICE -->
 'bundle identity preserves HEAD/candidate separation and proof source bytes'
    Assert-That ($authorityValidator -match 'filesChecked.*len' -and $authorityValidator -match 'CURRENT-PROOF' -and $authorityValidator -match 'candidate.*commit') 'current authority validator checks semantic authorities and real file count'
    Assert-That ($dependencyProject -match '\.\./\.\./\.\./\.\./installer-source/DevFleet\.Setup/DevFleet\.Setup\.csproj' -and $dependencyProject -match 'SelfContained>true') 'dependency runner references the real installer project with explicit local SDK RID'
    Assert-That ($dependencyProgram -match 'SendAsync' -and $dependencyProgram -match 'Valid-Nonstandard-Path' -and $dependencyProgram -match 'Outdated-Prerequisites' -and $dependencyProgram -match 'actualConditionProven') 'dependency runner has executable branch evidence and async HTTP seam'
    Assert-That (Test-Path -LiteralPath (Join-Path $WorkspaceRoot 'tools\validate_release_bundle.py') -PathType Leaf) 'strict post-cleanup bundle validator exists outside shipping source'
    Assert-That ($finalConvergence -match 'try\s*\{' -and $finalConvergence -match 'finally\s*\{' -and $finalConvergence -match 'AUDIT_BUNDLE_FINALIZATION_FAILURE' -and $finalConvergence -match 'FINALIZER-PRIMARY-BLOCKER' -and $finalConvergence -match 'Get-VM -Id' -and $finalConvergence -match 'Get-DevFleetHostNameExclusion' -and $finalConvergence -match 'host Hyper-V exact-name exclusion only' -and $finalConvergence -match 'Clear-DevFleetE2EInteractiveLogonState' -and $finalConvergence -match 'git -C \$Workspace diff --check') 'mandatory finalizer preserves primary blocker and performs exact cleanup/authority/audit work'
    Assert-That ($finalConvergence -match 'sidecar' -and $bundleBuilder -match 'outer sidecar is the final filesystem write' -and $bundleBuilder -notmatch 'Set-Content -LiteralPath \$sidecarPath[\s\S]{0,300}Write-Json \$manifestPath') 'audit sidecar is written after ZIP and manifest validation'

    [pscustomobject]@{status=if($failures.Count -eq 0){'PASS'}else{'FAIL'};passed=$passed;total=$total;failures=@($failures);temporaryFilesRemoved=$true} | ConvertTo-Json -Depth 6
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }

```


## FILE: automation/release-e2e/tests/Test-AstraCausalPackaging.ps1

SHA256: 10e49a7a2553ad36b8bb7fc3b4c00f91adf82c9fe322a8735083ea06f109a115 | Bytes: 3776 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $WorkspaceRoot 'tools/Build-AIAuditBundle.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Native packager has parse errors.'}
foreach($name in @('Get-Hash','Add-CompactFile','Add-AstraCausalEvidence')){
 $definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name)
 if($definition.Count -ne 1){throw "Native packaging function is ambiguous: $name"}
 . ([scriptblock]::Create($definition[0].Extent.Text))
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-astra-package-'+[guid]::NewGuid().ToString('N'))
$checks=[Collections.Generic.List[object]]::new()
try {
 foreach($case in @('exact-copy','missing-source','hash-drift','source-traversal','destination-traversal','destination-collision','excluded-destination','missing-manifest','empty-manifest')){
  $root=Join-Path $testRoot $case;$destination=Join-Path $root 'evidence'
  $sourceRelative='audit/automation-harness/runs/e2e-astra-fixture/raw.json'
  $source=Join-Path $root $sourceRelative
  New-Item -ItemType Directory -Path (Split-Path -Parent $source),(Join-Path $root 'tools') -Force|Out-Null
  [IO.File]::WriteAllText($source,'{"status":"BLOCKED","proofCredit":0}',[Text.UTF8Encoding]::new($false))
  $row=[ordered]@{source=$sourceRelative;destination='e2e-astra-fixture/raw.json';sha256=Get-Hash $source}
  $manifest=[ordered]@{schemaVersion=1;records=@($row)}
  switch($case){
   'missing-source' {$row.source='audit/automation-harness/runs/e2e-astra-fixture/missing.json'}
   'hash-drift' {$row.sha256='0'*64}
   'source-traversal' {$row.source='audit/automation-harness/../raw.json'}
   'destination-traversal' {$row.destination='e2e-astra-fixture/../raw.json'}
   'destination-collision' {$manifest.records+=,$row}
   'excluded-destination' {$row.destination='e2e-astra-fixture/snapshots/raw.json'}
   'empty-manifest' {$manifest.records=@()}
  }
  $manifestPath=Join-Path $root 'tools/astra-causal-evidence.json'
  if($case -ne 'missing-manifest'){$manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM}
  $threw=$false;$count=0
  try{$count=Add-AstraCausalEvidence $root $destination}catch{$threw=$true}
  $pass=if($case -eq 'exact-copy'){-not $threw -and $count -eq 1 -and (Get-Hash (Join-Path $destination 'astra-causal/e2e-astra-fixture/raw.json')) -ceq $row.sha256 -and (Get-Hash (Join-Path $destination 'astra-causal/allowlist.json')) -ceq (Get-Hash $manifestPath)}else{$threw}
  $checks.Add([ordered]@{case=$case;pass=[bool]$pass})
 }
 # Exercise the complete frozen real allowlist through the same native function.
 $realDestination=Join-Path $testRoot 'real-evidence'
 $realCount=Add-AstraCausalEvidence $WorkspaceRoot $realDestination
 $checks.Add([ordered]@{case='real-causal-allowlist';pass=($realCount -gt 0);records=$realCount})
} finally {
 $resolved=[IO.Path]::GetFullPath($testRoot);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^devfleet-astra-package-[0-9a-f]{32}$'){throw 'Fixture cleanup escaped its exact temporary root.'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
$failed=@($checks|Where-Object{-not $_.pass})
[ordered]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=$checks.Count-$failed.Count;total=$checks.Count;checks=@($checks);vmOperations=0}|ConvertTo-Json -Depth 6
if($failed.Count){exit 1}

```


## FILE: automation/release-e2e/tests/Test-AuthorityTimestampRoundTrip.ps1

SHA256: 45a57bfc53e1ac6d18d5a5cacdbc619fa7216a74afdea59b36d46e8a51f3d45d | Bytes: 913 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'tools\AuthorityTime.psm1') -Force
$raw='{"candidate_binding_utc":"2026-09-05T14:25:53.8477037Z"}'|ConvertFrom-Json
$converted=ConvertTo-AuthorityUtcInstant $raw.candidate_binding_utc
$stringConverted=ConvertTo-AuthorityUtcInstant '2026-09-05T14:25:53.8477037Z'
$pass=$converted.ToString('o') -ceq '2026-09-05T14:25:53.8477037Z' -and $stringConverted.ToString('o') -ceq '2026-09-05T14:25:53.8477037Z'
[pscustomobject]@{status=if($pass){'PASS'}else{'FAIL'};dateTimeType=$raw.candidate_binding_utc.GetType().FullName;dateTimeKind=[string]$raw.candidate_binding_utc.Kind;roundTrip=$converted.ToString('o');stringRoundTrip=$stringConverted.ToString('o')}|ConvertTo-Json -Depth 4
if(-not $pass){exit 1}

```


## FILE: automation/release-e2e/tests/Test-BaselineLineage.ps1

SHA256: e3aa70cfba3004c82f91b9a4d4de66bed23da6b8ab4340b6754bafba74259d8b | Bytes: 8951 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$modulePath=Join-Path $PSScriptRoot '..\modules\BaselineLineage.psm1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-baseline-test-'+[guid]::NewGuid().ToString('N'))
$count=0
function Assert-True([bool]$ok,[string]$message){if(-not $ok){throw $message};$script:count++}
function Assert-Rejected([scriptblock]$action,[string]$message){
    $failed=$false
    try{&$action|Out-Null}catch{$failed=$true}
    Assert-True $failed $message
}
try{
    New-Item -ItemType Directory -Force -Path $root|Out-Null
    Import-Module $modulePath -Force
    $original=Get-DevFleetAcceptedBaseline -WorkspaceRoot $root
    Assert-True ($original.id -ceq '19865b76-4c3a-44f7-ba39-841e9d3c40c9') 'Original baseline was not selected.'
    $state=Join-Path $root 'evidence\baselines';$receipts=Join-Path $state 'receipts'
    New-Item -ItemType Directory -Force -Path $receipts|Out-Null
    $fingerprint=[pscustomobject]@{repositoryHead=('1'*40);gitCommit=('2'*40);shippingInputIdentity=('3'*64);releaseFingerprintId=('4'*64);toolingFingerprintId=('5'*64);candidate=[pscustomobject]@{sha256=('6'*64)}}
    $old=[ordered]@{name='DevFleet-E2E-CLEAN';id='19865b76-4c3a-44f7-ba39-841e9d3c40c9'}
    $new=[ordered]@{name='DevFleet-E2E-CLEAN-R2';id='11111111-2222-4333-8444-555555555555';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';parentSnapshotId=$old.id}
    $tuple=[ordered]@{repositoryHead=$fingerprint.repositoryHead;candidateBuildCommit=$fingerprint.gitCommit;shippingInputIdentity=$fingerprint.shippingInputIdentity;releaseFingerprintId=$fingerprint.releaseFingerprintId;toolingFingerprintId=$fingerprint.toolingFingerprintId;candidateSha256=$fingerprint.candidate.sha256}
    $id='a'*32;$receiptFile="$id.json"
    $receipt=[ordered]@{schemaVersion=1;contract='devfleet-baseline-adoption-receipt-v1';receiptId=$id;status='ADOPTED';certificationCredit=$false;secretValuesRecorded=$false;predecessor=$old;replacement=$new;candidate=$tuple;passwordLastSetUtc=(Get-Date).ToUniversalTime().AddMinutes(-20).ToString('o');protectedStoreUpdatedUtc=(Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o');passwordExpiresUtc=(Get-Date).ToUniversalTime().AddDays(30).ToString('o');adoptionAuthority=[ordered]@{decision='APPROVE';approvedBy='ACCOUNT_OWNER';sourceSha256=('f'*64)};authenticatedGuest=[ordered]@{computerName='DEVFLEET-E2E-01';principal='DEVFLEET-E2E-01\E2EAdmin';accountEnabled=$true;sourceObservedUtc=(Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o')};nestedL2=[ordered]@{status='ABSENT';present=$false;expectedName='DevFleet-E2E-Linux-01';exactMatchCount=0;backendInventories=@([ordered]@{provider='Hyper-V';status='PASS';names=@();verification='read-only'},[ordered]@{provider='VirtualBox';status='PASS';names=@();verification='read-only'})};finalL1=[ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';state='Off'};sources=[ordered]@{proposalSha256=('a'*64);predecessorEvidenceSha256=('b'*64);approvalSha256=('f'*64);authenticatedGuestSha256=('c'*64);nativeInventorySha256=('d'*64);currentTupleSha256=('e'*64);r2LedgerSha256=('1'*64)}}
    $receiptPath=Join-Path $receipts $receiptFile
    [IO.File]::WriteAllText($receiptPath,($receipt|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $hash=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $pointer=[ordered]@{schemaVersion=1;contract='devfleet-accepted-baseline-v1';generation=1;status='ACCEPTED';receiptFile=$receiptFile;receiptSha256=$hash;checkpoint=$new}
    $pointerPath=Join-Path $state 'CURRENT.json'
    [IO.File]::WriteAllText($pointerPath,($pointer|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $adopted=Get-DevFleetAcceptedBaseline -WorkspaceRoot $root -Fingerprint $fingerprint
    Assert-True ($adopted.id -ceq $new.id -and $adopted.name -ceq $new.name) 'Adopted baseline was not selected by exact identity.'
    Import-Module (Join-Path $PSScriptRoot '..\modules\FullRelease.psm1') -Force -WarningAction SilentlyContinue
    $script:vmFixture=[pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';State='Off'}
    $script:snapshotFixture=[pscustomobject]@{Name=$new.name;Id=[guid]$new.id;VMId=[guid]$new.vmId;ParentSnapshotId=[guid]$old.id}
    function global:Get-VM { $script:vmFixture }
    function global:Get-VMSnapshot { $script:snapshotFixture }
    [void](Set-DevFleetBaselineBinding -WorkspaceRoot $root -Fingerprint $fingerprint)
    Assert-Rejected {Get-ExactCheckpoint -Vm $script:vmFixture -Name 'DevFleet-E2E-CLEAN'} 'FullRelease aliased the predecessor name to the adopted replacement.'
    $selected=Get-ExactCheckpoint -Vm $script:vmFixture -Name $new.name
    Assert-True ([string]$selected.Id -ceq $new.id) 'FullRelease did not resolve the accepted checkpoint by exact name.'
    $phase=@(Get-FullReleasePhasePlan|Where-Object{$_.id -ceq 'RESTORE-CLEAN'})[0]
    Assert-True ($phase.checkpoint -ceq $new.name) 'FullRelease phase plan retained the predecessor checkpoint name.'
    $script:snapshotFixture.Id=[guid]::NewGuid()
    Assert-Rejected {Get-ExactCheckpoint -Vm $script:vmFixture -Name $new.name} 'FullRelease accepted a name-only checkpoint substitution.'
    $wrong=$fingerprint.PSObject.Copy();$wrong.toolingFingerprintId='9'*64
    Assert-Rejected {Get-DevFleetAcceptedBaseline -WorkspaceRoot $root -Fingerprint $wrong} 'Stale material tuple was accepted.'
    $toolsDir=Join-Path $root 'tools';New-Item -ItemType Directory -Force -Path $toolsDir|Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\..\..\tools\baseline_lineage.py') -Destination (Join-Path $toolsDir 'baseline_lineage.py') -ErrorAction Stop
    $historyDir=Join-Path $state 'history';New-Item -ItemType Directory -Force -Path $historyDir|Out-Null
    $oldPointerHash=(Get-FileHash -LiteralPath $pointerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath $pointerPath -Destination (Join-Path $historyDir "$oldPointerHash.json") -ErrorAction Stop
    $newFingerprint=$fingerprint.PSObject.Copy();$newFingerprint.repositoryHead='7'*40;$newFingerprint.toolingFingerprintId='8'*64
    $newTuple=[ordered]@{repositoryHead=$newFingerprint.repositoryHead;candidateBuildCommit=$tuple.candidateBuildCommit;shippingInputIdentity=$tuple.shippingInputIdentity;releaseFingerprintId=$tuple.releaseFingerprintId;toolingFingerprintId=$newFingerprint.toolingFingerprintId;candidateSha256=$tuple.candidateSha256}
    $newReceiptId='b'*32;$newReceiptFile="$newReceiptId.json"
    $newReceipt=[ordered]@{schemaVersion=2;contract='devfleet-baseline-rebind-receipt-v2';receiptId=$newReceiptId;status='REBOUND';certificationCredit=$false;secretValuesRecorded=$false;previousPointerSha256=$oldPointerHash;previousReceiptSha256=$hash;previousCandidate=$tuple;candidate=$newTuple;replacement=$new;approval=[ordered]@{decision='APPROVE';approvedBy='ACCOUNT_OWNER';candidate=$newTuple;replacement=$new;previousReceiptSha256=$hash;sourceSha256=('e'*64)};approvalSha256=('e'*64);successorPolicyId='DF-FRESH-CERTIFICATION-20260926-R2-D1';successorLedgerSha256=('f'*64);finalL1=[ordered]@{name='DevFleet-E2E-Win11-01';id='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';state='Off'}}
    $newReceiptPath=Join-Path $receipts $newReceiptFile
    [IO.File]::WriteAllText($newReceiptPath,($newReceipt|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
    $newHash=(Get-FileHash -LiteralPath $newReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $reboundPointer=[ordered]@{schemaVersion=2;contract='devfleet-accepted-baseline-v2';generation=2;status='ACCEPTED';receiptFile=$newReceiptFile;receiptSha256=$newHash;previousPointerSha256=$oldPointerHash;checkpoint=$new}
    [IO.File]::WriteAllText($pointerPath,($reboundPointer|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    Import-Module $modulePath -Force
    $rebound=Get-DevFleetAcceptedBaseline -WorkspaceRoot $root -Fingerprint $newFingerprint
    Assert-True ($rebound.id -ceq $new.id -and $rebound.receiptSha256 -ceq $newHash) 'Rebound baseline was not selected by exact identity.'
    Assert-Rejected {Get-DevFleetAcceptedBaseline -WorkspaceRoot $root -Fingerprint $fingerprint} 'Rebound baseline accepted the predecessor tuple.'
    $reboundPointer.receiptSha256='0'*64
    [IO.File]::WriteAllText($pointerPath,($reboundPointer|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    Assert-Rejected {Get-DevFleetAcceptedBaseline -WorkspaceRoot $root -Fingerprint $newFingerprint} 'Tampered rebound receipt pointer was accepted.'
    "PASS $count baseline lineage PowerShell assertions"
}finally{
    Remove-Item Function:\Get-VM,Function:\Get-VMSnapshot -ErrorAction SilentlyContinue
    Remove-Module FullRelease -ErrorAction SilentlyContinue
    Remove-Module BaselineLineage -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: automation/release-e2e/tests/Test-BoundedProcessOutput.ps1

SHA256: 4860ddb3799b916ef9e48d3b3d5dcdb7ba09a785ec78d953115b4d517533244c | Bytes: 7930 | Git mode: 100644

```
[CmdletBinding()]
param([string]$ReportPath,[ValidatePattern('^[0-9a-f]{40}$')][string]$BaselineCommit)
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/MultipassDiagnostic.psm1') -Force
$runner=Get-DevFleetBoundedProcessScriptBlock
if($BaselineCommit){
    $workspace=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $baseline=(& git -C $workspace show ($BaselineCommit+':automation/release-e2e/modules/MultipassDiagnostic.psm1')) -join "`n"
    if($LASTEXITCODE -ne 0){throw 'Immutable baseline source is unavailable'}
    $parseErrors=$null;$tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($baseline,[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'Immutable baseline source did not parse'}
    $factory=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-DevFleetBoundedProcessScriptBlock'},$false))
    if($factory.Count -ne 1){throw 'Immutable baseline runner is ambiguous'}
    $body=$factory[0].Body.Extent.Text
    $runner=& ([scriptblock]::Create($body.Substring(1,$body.Length-2)))
}
$engine=(Get-Process -Id $PID).Path
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-BoundedOutput-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch|Out-Null
$receipt=Join-Path $scratch 'held-child.json'
$marker='COLLECTOR_ENTER:e2e-vault-diagnostic-c-local'
$prefix="[Console]::Out.WriteLine('$marker');[Console]::Out.Flush();[Console]::Error.WriteLine('NATIVE_STDERR_MARKER');[Console]::Error.Flush();"
$heldCode="[Console]::Out.WriteLine('HELD_PIPE_CHILD');[Console]::Out.Flush();Start-Sleep -Seconds 30"
$heldEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($heldCode))
$heldParent=$prefix+@"
`$psi=[Diagnostics.ProcessStartInfo]::new();`$psi.FileName='$($engine.Replace("'","''"))';`$psi.Arguments='-NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $heldEncoded';`$psi.UseShellExecute=`$false;`$psi.CreateNoWindow=`$true
`$child=[Diagnostics.Process]::Start(`$psi)
[IO.File]::WriteAllText('$($receipt.Replace("'","''"))',((@{pid=`$child.Id;startedFileTimeUtc=`$child.StartTime.ToUniversalTime().ToFileTimeUtc()}|ConvertTo-Json -Compress)))
[Environment]::Exit(0)
"@
$cases=@(
    @{name='timeout-markers';code=$prefix+'Start-Sleep -Seconds 30';deadline=3;outcome='TIMEOUT';markers=$true;complete=$true},
    @{name='timeout-no-output';code='Start-Sleep -Seconds 30';deadline=3;outcome='TIMEOUT';markers=$false;complete=$true},
    @{name='timeout-tree';code=$heldParent.Replace('[Environment]::Exit(0)','Start-Sleep -Seconds 30');deadline=3;outcome='TIMEOUT';markers=$true;complete=$true},
    @{name='held-pipe';code=$heldParent;deadline=10;outcome='DRAIN_INCOMPLETE';markers=$true;complete=$false},
    @{name='bounded-output';code=$prefix+"[Console]::Out.Write(('x'*100000));[Console]::Out.Flush();Start-Sleep -Seconds 30";deadline=3;outcome='TIMEOUT';markers=$true;complete=$false},
    @{name='success';code=$prefix;deadline=10;outcome='PASS';markers=$true;complete=$true},
    @{name='large-success';code=$prefix+"[Console]::Out.WriteLine(('x'*40000)+'FINAL_FRAME_END');[Console]::Out.Flush()";deadline=10;outcome='PASS';markers=$true;complete=$true},
    @{name='nonzero';code=$prefix+'exit 7';deadline=10;outcome='NONZERO';markers=$true;complete=$true}
)
$results=[Collections.Generic.List[object]]::new()
try {
    foreach($case in $cases){
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($case.code))
        $request=@{filePath=$engine;arguments=@('-NoProfile','-NonInteractive','-OutputFormat','Text','-EncodedCommand',$encoded);deadlineUnixMilliseconds=[DateTimeOffset]::new([datetime]::UtcNow.AddSeconds($case.deadline)).ToUnixTimeMilliseconds()}|ConvertTo-Json -Compress
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $result=& $runner $request
        $clock.Stop()
        $failures=[Collections.Generic.List[string]]::new()
        if($result.outcome -cne $case.outcome){$failures.Add('outcome changed: '+$result.outcome)}
        if($clock.Elapsed.TotalSeconds -ge ($case.deadline+9)){$failures.Add('terminal deadline exceeded')}
        if($case.markers -and ([string]$result.stdout -notmatch [regex]::Escape($marker))){$failures.Add('flushed collector-entry/stdout marker lost')}
        if($case.markers -and ([string]$result.stderr -notmatch 'NATIVE_STDERR_MARKER')){$failures.Add('native stderr marker lost')}
        if([bool]$result.outputComplete -ne $case.complete){$failures.Add('output completeness is not truthful')}
        if($case.name -eq 'timeout-no-output' -and $result.stdout){$failures.Add('invented stdout for silent child')}
        # A killed Windows PowerShell 5.1 encoded-command host may emit its
        # otherwise empty CLIXML stream header. It is native output, not a
        # supervisor diagnostic; preserve it rather than sanitizing it away.
        if($case.name -eq 'timeout-no-output' -and [string]$result.stderr -cnotin @('',"#< CLIXML`r`n")){$failures.Add('supervisor text replaced native stderr')}
        if($case.name -eq 'bounded-output' -and ([string]$result.stdout).Length -gt 65536){$failures.Add('stdout exceeded bounded capture')}
        if($case.name -eq 'nonzero' -and $result.exitCode -ne 7){$failures.Add('original child exit code lost')}
        if($case.name -eq 'large-success' -and [string]$result.stdout -notmatch ('x{40000}FINAL_FRAME_END\r?\n$')){$failures.Add('complete long terminal frame was not captured')}
        if($result.pid -and (Get-Process -Id $result.pid -ErrorAction SilentlyContinue)){$failures.Add('exact owning child still alive')}
        if($case.name -eq 'timeout-tree'){
            if(-not(Test-Path -LiteralPath $receipt)){$failures.Add('test descendant did not start')}
            else{$treeChild=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json;if(Get-Process -Id $treeChild.pid -ErrorAction SilentlyContinue){$failures.Add('exact owned descendant still alive after timeout')}}
        }
        $row=[ordered]@{case=$case.name;status=if($failures.Count){'FAIL'}else{'PASS'};failures=@($failures);elapsedSeconds=$clock.Elapsed.TotalSeconds;result=$result}
        $results.Add($row)
        Write-Host "$($row.status) $($case.name): $($failures -join '; ')"
        if(Test-Path -LiteralPath $receipt){
            $owned=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
            $child=Get-Process -Id $owned.pid -ErrorAction SilentlyContinue
            if($child){if($child.StartTime.ToUniversalTime().ToFileTimeUtc() -ne $owned.startedFileTimeUtc){throw 'Held-pipe test child identity changed'};Stop-Process -Id $child.Id -Force;[void]$child.WaitForExit(3000)}
            Remove-Item -LiteralPath $receipt
        }
    }
} finally {
    if(Test-Path -LiteralPath $receipt){
        $owned=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
        $child=Get-Process -Id $owned.pid -ErrorAction SilentlyContinue
        if($child -and $child.StartTime.ToUniversalTime().ToFileTimeUtc() -eq $owned.startedFileTimeUtc){Stop-Process -Id $child.Id -Force;[void]$child.WaitForExit(3000)}
    }
    $expectedPrefix=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'DevFleet-BoundedOutput-'))
    if([IO.Path]::GetFullPath($scratch).StartsWith($expectedPrefix,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
$report=[ordered]@{engine=$PSVersionTable.PSVersion.ToString();baselineCommit=$BaselineCommit;vmMutation=$false;runnerMocked=$false;status=if(@($results|Where-Object status -eq 'FAIL').Count){'FAIL'}else{'PASS'};cases=@($results)}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
if($report.status -ne 'PASS'){throw 'Bounded process output behavioral regression failed.'}

```


## FILE: automation/release-e2e/tests/Test-CampaignEBackendObserver.ps1

SHA256: 34152ef5960feca200774e344d2c45effd557edff585edcb9639e706d6dc55eb | Bytes: 8333 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/MultipassDiagnostic.psm1'
$scratch=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('devfleet-backend-fixture-'+[guid]::NewGuid().ToString('N'))))
$results=[Collections.Generic.List[object]]::new()
$io=@'
            $script:backendName=$Name
            if($ObserveProduct){$env:ProgramData=$env:DEVFLEET_BACKEND_ROOT}
            function Get-CimInstance {
                param($ClassName,$OperationTimeoutSec)
                if($env:DEVFLEET_BACKEND_FIXTURE-ceq'timeout'){Start-Sleep 20}
                if($env:DEVFLEET_BACKEND_FIXTURE-ceq'partial'){throw 'fixture provider failure token=private-value'}
                if($ClassName-ceq'Win32_Service'){[pscustomobject]@{Name='Multipass';State='Running';ProcessId=42;ExitCode=0;StartMode='Auto';StartName='LocalSystem'}}
                else {
                    @([pscustomobject]@{Name='multipassd.exe';ProcessId=42;ParentProcessId=1;CreationDate=[datetime]::UtcNow},[pscustomobject]@{Name='powershell.exe';ProcessId=43;ParentProcessId=42;CreationDate=[datetime]::UtcNow})
                    if($ObserveProduct){
                        $exe=Join-Path $env:ProgramFiles 'Multipass\bin\multipass.exe';$cloud=Join-Path $env:ProgramData 'DevFleet\tmp\cloud-devfleet-primary.yaml'
                        $command='"'+$exe+'" launch 24.04 --name devfleet-primary --cpus 4 --memory 9G --disk 220G --cloud-init "'+$cloud+'"'
                        if($env:DEVFLEET_BACKEND_FIXTURE-ceq'product-unknown-args'){$command+=' --token private-value'}
                        [pscustomobject]@{Name='multipass.exe';ProcessId=50;ParentProcessId=60;CreationDate=[datetime]::UtcNow;SessionId=1;CommandLine=$command}
                    }
                }
            }
            function Invoke-CimMethod {param($InputObject,$MethodName)[pscustomobject]@{ReturnValue=0;Sid='S-1-5-21-123-456-789-1000'}}
            function Get-VM {[pscustomobject]@{Name=$script:backendName;Id=[guid]'11111111-1111-1111-1111-111111111111';State='Running';Status='Operating normally';Generation=2;ProcessorCount=4;MemoryStartup=9GB;MemoryAssigned=9GB;Uptime=[timespan]::FromSeconds(5)}}
            function Get-VMHardDiskDrive {param($VM)[pscustomobject]@{Path='fixture.vhdx'}}
            function Get-VHD {param($Path)[pscustomobject]@{Size=220GB;FileSize=3GB;VhdType='Dynamic';Attached=$true}}
            function Get-VMNetworkAdapter {param($VM)[pscustomobject]@{SwitchName='Default Switch';Status=@('Ok');IPAddresses=@('172.20.0.5')}}
            function Get-WinEvent {
                param($ListLog,$FilterHashtable,$MaxEvents)
                if($ListLog){[pscustomobject]@{IsEnabled=$true}}
                else {
                    # Windows event filtering interprets the supplied wall time as
                    # local even when DateTime.Kind is UTC. M4 recovered events
                    # only when the same instant was explicitly converted locally.
                    if($FilterHashtable.StartTime.Kind-ne[DateTimeKind]::Local-or$FilterHashtable.StartTime.ToUniversalTime()-ne$Since.ToUniversalTime()){throw 'Event filter did not preserve the requested instant as local wall time.'}
                    [pscustomobject]@{ProviderName='Microsoft-Windows-Hyper-V-VMMS';Id=100;RecordId=200;TimeCreated=[datetime]::UtcNow;Message='fixture boot event token=private-value'}
                }
            }
'@
try{
    New-Item -ItemType Directory -Path $scratch|Out-Null
    $text=[IO.File]::ReadAllText($source);$needle='param($Name,$Since,$ObserveProduct,$Payload)'
    if(([regex]::Matches($text,[regex]::Escape($needle))).Count-ne1){throw 'Actual backend I/O fixture boundary is ambiguous.'}
    $fixtureModule=Join-Path $scratch 'MultipassDiagnostic.psm1';[IO.File]::WriteAllText($fixtureModule,$text.Replace($needle,$needle+[Environment]::NewLine+$io),[Text.UTF8Encoding]::new($false))
    Import-Module $fixtureModule -Force -DisableNameChecking
    foreach($case in @('complete','partial','timeout','product-success','product-wrong-payload','product-bad-config','product-unknown-args')){
        $env:DEVFLEET_BACKEND_FIXTURE=$case;$timer=[Diagnostics.Stopwatch]::StartNew()
        $parameters=@{InstanceName='DevFleet-E2E-E-M1-fixture';SinceUtc=[datetime]::UtcNow.AddMinutes(-1);OwnerDeadlineUtc=[datetime]::UtcNow.AddSeconds(25);TimeoutSeconds=if($case-ceq'timeout'){1}else{15}}
        if($case-like'product-*'){
            $dataRoot=Join-Path $scratch $case;$env:DEVFLEET_BACKEND_ROOT=$dataRoot;New-Item -ItemType Directory -Path (Join-Path $dataRoot 'DevFleet/tmp'),(Join-Path $dataRoot 'M-TechLabs/DevFleet/Logs')|Out-Null
            @{Primary=@{InstanceName='devfleet-primary';Cpus=4;Memory=if($case-ceq'product-bad-config'){'token=private-value'}else{'9G'};Disk='220G';UbuntuImage='24.04'};Token='private-value'}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $dataRoot 'DevFleet/devfleet.config.json')
            @{transactionId=('b'*32);payloadSha256=if($case-ceq'product-wrong-payload'){'f'*64}else{'a'*64};secret='private-value'}|ConvertTo-Json|Set-Content (Join-Path $dataRoot 'DevFleet/active-transaction.json')
            '#cloud-config'|Set-Content (Join-Path $dataRoot 'DevFleet/tmp/cloud-devfleet-primary.yaml')
            'state=failed error=native failed token=private-value Bearer private-value'|Set-Content (Join-Path $dataRoot 'M-TechLabs/DevFleet/Logs/setup-fixture.log')
            $parameters.InstanceName='devfleet-primary';$parameters.ProductContext=$true;$parameters.ExpectedPayloadSha256='a'*64
        }
        $snapshot=Get-DevFleetCampaignEBackendSnapshot @parameters
        $timer.Stop();$pass=$true
        if($case-ceq'complete'){$pass=$snapshot.status-ceq'COMPLETE'-and@($snapshot.data.processes).Count-eq2-and@($snapshot.data.backend.owned).Count-eq1-and$snapshot.data.backend.owned[0].disks[0].virtualBytes-eq220GB-and@($snapshot.data.events).Count-eq2}
        elseif($case-ceq'partial'){$pass=$snapshot.status-ceq'PARTIAL'-and@($snapshot.errors).Count-eq1-and$snapshot.data.backend.status-ceq'PASS'}
        elseif($case-ceq'timeout'){$pass=$snapshot.status-ceq'UNVERIFIED'-and$timer.Elapsed.TotalSeconds-lt10}
        elseif($case-cin@('product-wrong-payload','product-bad-config')){$pass=$snapshot.status-ceq'PARTIAL'-and$snapshot.data.product.status-ceq'UNVERIFIED'}
        else{
            $pass=$snapshot.status-ceq'COMPLETE'-and$snapshot.data.product.status-ceq'TRANSACTION_OBSERVED'-and$snapshot.data.product.effectivePrimary.cpus-eq4-and$snapshot.data.product.cloudInit.sha256-match'^[a-f0-9]{64}$'-and$snapshot.data.product.failureRecords[0].tail-match'native failed'-and@($snapshot.data.events).Count-eq3-and$snapshot.data.services[0].startMode-ceq'Auto'-and$snapshot.data.backend.owned[0].networkAdapters[0].ipAddresses[0]-ceq'172.20.0.5'
            if($case-ceq'product-success'){$pass=$pass-and$snapshot.data.launches.Count-eq1-and$snapshot.data.launches[0].sessionId-eq1-and$snapshot.data.launches[0].principalStatus-ceq'OBSERVED'-and$snapshot.data.launches[0].principalSidSha256-match'^[a-f0-9]{64}$'-and-not$snapshot.data.launches[0].rawCommandLineCaptured}else{$pass=$pass-and$snapshot.data.launches.Count-eq0}
        }
        $pass=$pass-and($snapshot|ConvertTo-Json -Depth 12)-notmatch'private-value'
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;status=$snapshot.status;elapsed=[math]::Round($timer.Elapsed.TotalSeconds,2);detail=if(-not$pass){$snapshot}else{$null}})
    }
}finally{
    Remove-Item Env:\DEVFLEET_BACKEND_FIXTURE -ErrorAction SilentlyContinue
    Remove-Item Env:\DEVFLEET_BACKEND_ROOT -ErrorAction SilentlyContinue
    if(-not$scratch.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($scratch)-notlike'devfleet-backend-fixture-*'){throw 'Backend fixture cleanup escaped its boundary.'}
    if(Test-Path $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
$results|ConvertTo-Json -Depth 12
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Actual bounded backend observer regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) bounded backend observer checks ($($PSVersionTable.PSVersion))"

```


## FILE: automation/release-e2e/tests/Test-CampaignECandidateNativeLaunch.ps1

SHA256: f151b65c93277d6b15a206630141a57fb90f7fbd88ba03043a4e1ec2edfb8a31 | Bytes: 3614 | Git mode: 100644

```
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSVersion.Major-lt7){throw 'This regression must exercise the actual PowerShell7 native implementation.'}
$release=Split-Path -Parent $PSScriptRoot;$repo=Split-Path -Parent (Split-Path -Parent $release)
Import-Module (Join-Path $release 'modules/MultipassDiagnostic.psm1') -Force -DisableNameChecking
$common=Import-Module (Join-Path $repo 'source/windows/DevFleet.Common.psm1') -Force -PassThru -DisableNameChecking
$engine=(Get-Process -Id $PID).Path
$scratch=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('astra-native-'+[guid]::NewGuid().ToString('N'))));$priorData=$env:ProgramData
$results=[Collections.Generic.List[object]]::new()
try{
    New-Item -ItemType Directory -Path $scratch|Out-Null;$env:ProgramData=$scratch
    $probePath=Join-Path $scratch 'argument probe.ps1'
    @'
param([string]$Case,[string]$Value,[string]$PidPath)
if($PidPath){[IO.File]::WriteAllText($PidPath,[string]$PID)}
switch($Case){
    success {[Console]::Out.Write($Value)}
    nonzero {[Console]::Error.Write('controlled-native-failure');exit 7}
    timeout {Start-Sleep -Seconds 20}
}
'@|Set-Content -LiteralPath $probePath -Encoding utf8
    foreach($case in @('success','nonzero','timeout','owner-expired')){
        $pidPath=Join-Path $scratch ($case+'.pid');$value='two words "quoted" C:\path with spaces\'
        $deadline=if($case-ceq'owner-expired'){[datetime]::UtcNow.AddSeconds(-1)}else{[datetime]::UtcNow.AddSeconds(10)}
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $record=Invoke-DevFleetCampaignECandidateNativeLaunch -CandidateCommonModule $common -FilePath $engine -ArgumentList @('-NoProfile','-NonInteractive','-File',$probePath,'-Case',$case,'-Value',$value,'-PidPath',$pidPath) -MaximumSeconds 3 -OwnerDeadlineUtc $deadline
        $timer.Stop();$pass=$record.adapter-ceq'CANDIDATE_COMMON_INVOKE_EXTERNAL'-and$null-eq$record.pid-and$record.nativeMaximumSeconds-eq3-and([datetime]$record.deadlineUtc).ToUniversalTime()-le$deadline
        switch($case){
            success {$pass=$pass-and$record.outcome-ceq'PASS'-and$record.exitCode-eq0-and$record.outputComplete-and$record.stdout-ceq$value}
            nonzero {$pass=$pass-and$record.outcome-ceq'COMMAND_FAILED'-and$record.exitCode-eq7-and$record.outputComplete-and$record.stderr-match'controlled-native-failure'}
            timeout {$pass=$pass-and$record.outcome-ceq'TIMEOUT'-and$null-eq$record.exitCode-and$timer.Elapsed.TotalSeconds-lt8-and(Test-Path $pidPath);if(Test-Path $pidPath){$childId=[int](Get-Content $pidPath -Raw);$pass=$pass-and-not(Get-Process -Id $childId -ErrorAction SilentlyContinue)}}
            owner-expired {$pass=$pass-and$record.outcome-ceq'TIMEOUT'-and-not(Test-Path $pidPath)}
        }
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;outcome=$record.outcome;exitCode=$record.exitCode;elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,2);error=$record.stderr})
    }
}finally{
    $env:ProgramData=$priorData
    if([IO.Path]::GetDirectoryName($scratch)-ine[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')-or[IO.Path]::GetFileName($scratch)-notlike'astra-native-*'){throw 'Native regression cleanup escaped exact owned path.'}
    if(Test-Path $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
$results|ConvertTo-Json -Depth 3
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Actual candidate native launch regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) actual candidate Common native launch checks"

```


## FILE: automation/release-e2e/tests/Test-CampaignEM1Ownership.ps1

SHA256: 2f098c01706ba97fe249a69d1b4cd81571b325a9cb7017f9e39f11f18355bc18 | Bytes: 5564 | Git mode: 100644

```
[CmdletBinding()]
param([string]$ControllerPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$releaseRoot=Split-Path -Parent $PSScriptRoot
if(-not$ControllerPath){$ControllerPath=Join-Path $releaseRoot 'Invoke-CampaignEMultipassM1.ps1'}
Import-Module (Join-Path $releaseRoot 'modules/MultipassDiagnostic.psm1') -Force -DisableNameChecking
$fixture=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('devfleet-m1-ownership-'+[guid]::NewGuid().ToString('N'))))
$results=[Collections.Generic.List[object]]::new()
$stub=@'
$script:fixtureRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$script:case=Get-Content (Join-Path $script:fixtureRoot 'case.txt') -Raw
$script:vm=[pscustomobject]@{Name=if($script:case-ceq'wrong-name'){'Unexpected-L1'}else{'DevFleet-E2E-Win11-01'};Id=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';State=if($script:case-cin@('running','wrong-name','ownership-rejected')){'Running'}else{'Off'}}
function Record-Call($Value){[IO.File]::AppendAllText((Join-Path $script:fixtureRoot 'calls.txt'),$Value+[Environment]::NewLine)}
function Get-VM {param($Id) $script:vm}
function Assert-DisposableOwnership {param($Vm,$ExpectedId)if($script:case-ceq'ownership-rejected'){throw 'Fixture ownership rejected.'}}
function Get-VMSnapshot {param($VM)[pscustomobject]@{Name='Fixture-Checkpoint';Id=[guid]'11111111-1111-1111-1111-111111111111';VMId=$script:vm.Id;ParentSnapshotId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'}}
function Get-HostSafetySnapshot {param($Vm,$ExpectedVmStartCostGiB)[pscustomobject]@{startSafe=$true;availableMemoryGiB=30;projectedPostStartAvailableMemoryGiB=16}}
function Get-CandidateFingerprint {param($WorkspaceRoot)[pscustomobject]@{gitCommit=('b'*40);shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64);tar=[pscustomobject]@{sha256=('a'*64)}}}
function git {'fixture-head'}
function Restore-ExactCheckpoint {param($Vm,$Name,[switch]$StartAfterRestore)Record-Call 'restore';$script:vm.State='Running';throw 'Fixture restore changed state before throwing.'}
function Stop-VM {param($VM,[switch]$Force,[switch]$Confirm)Record-Call 'stop';$script:vm.State='Off'}
function ConvertTo-DevFleetDiagnosticSafeText {param($Value,$MaximumLength) [string]$Value}
function Write-EvidenceJson {param($Path,$Value)$Value|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $Path}
Export-ModuleMember -Function *
'@
try {
    New-Item -ItemType Directory -Path $fixture|Out-Null
    foreach($case in @('running','wrong-name','ownership-rejected','partial-restore')){
        $caseRoot=Join-Path $fixture $case;$modules=Join-Path $caseRoot 'automation/release-e2e/modules'
        New-Item -ItemType Directory -Path $modules|Out-Null
        [IO.File]::WriteAllText((Join-Path $caseRoot 'case.txt'),$case)
        foreach($name in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic')){
            [IO.File]::WriteAllText((Join-Path $modules ($name+'.psm1')),$(if($name-ceq'MultipassDiagnostic'){$stub}else{'# No external access in this controller fixture.'}),[Text.UTF8Encoding]::new($false))
        }
        New-Item -ItemType Directory -Path (Join-Path $caseRoot 'evidence')|Out-Null
        @{candidateIsCurrent=$true;sourceChangedSinceCandidate=$false;rebuildRequired=$false;repositoryHead='fixture-head';shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64)}|ConvertTo-Json|Set-Content (Join-Path $caseRoot 'evidence/CURRENT-RELEASE-AUTHORITY.json')
        $checkpoint=Join-Path $caseRoot 'checkpoint.json'
        @{status='PASS_CHECKPOINT_READY';campaign='DF-STABLE-20260906-E';diagnosticCheckpoint=@{id='11111111-1111-1111-1111-111111111111';name='Fixture-Checkpoint';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';parentSnapshotId='19865b76-4c3a-44f7-ba39-841e9d3c40c9';l1State='OFF';l2Status='ABSENT';payloadSha256=('a'*64)}}|ConvertTo-Json -Depth 4|Set-Content $checkpoint
        $probe=Invoke-DevFleetBoundedNativeProbe -Operation "ownership-$case" -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-NonInteractive','-File',$ControllerPath,'-WorkspaceRoot',$caseRoot,'-RunId','fixture','-CheckpointEvidencePath',$checkpoint) -TimeoutSeconds 15 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(20)) -ForceLegacyArgumentString
        $record=Get-Content (Join-Path $caseRoot 'audit/automation-harness/runs/fixture/campaign-e-m1.json') -Raw|ConvertFrom-Json
        $callPath=Join-Path $caseRoot 'calls.txt';$calls=@(if(Test-Path $callPath){Get-Content $callPath})
        $expected=if($case-ceq'partial-restore'){'restore|stop'}else{''}
        $passed=$probe.exitCode-eq1-and[string]$record.status-ceq'BLOCKED'-and($calls-join'|')-ceq$expected
        $results.Add([pscustomobject]@{case=$case;pass=$passed;calls=($calls-join'|');exitCode=$probe.exitCode;error=[string]$record.primaryError})
    }
} finally {
    $fence=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not$fixture.StartsWith($fence,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($fixture)-notlike'devfleet-m1-ownership-*'){throw 'Ownership fixture cleanup escaped its boundary.'}
    if(Test-Path $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
$results|ConvertTo-Json -Depth 3
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Campaign E M1 controller ownership regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) Campaign E M1 controller ownership checks ($($PSVersionTable.PSVersion))"

```


## FILE: automation/release-e2e/tests/Test-CampaignEM1WorkerBoundary.ps1

SHA256: 3e877d7af1f603449ca25b942300610e55cf078c45eac2d59dbcb974e01b9ef8 | Bytes: 19638 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkerPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$releaseRoot=Split-Path -Parent $PSScriptRoot
$modulePath=Join-Path $releaseRoot 'modules\MultipassDiagnostic.psm1'
if(-not$WorkerPath){$workerPath=Join-Path $releaseRoot 'Invoke-CampaignEMultipassM1Worker.ps1'}
Import-Module $modulePath -Force -DisableNameChecking
$engine=(Get-Process -Id $PID).Path
$run="astra-worker-$PID-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$fixtureParent=[IO.Path]::GetFullPath("C:\Users\Public\DevFleet-E2E\$run")
$originalPrograms=$env:ProgramFiles;$originalProgramsX86=${env:ProgramFiles(x86)};$originalData=$env:ProgramData
$results=[Collections.Generic.List[object]]::new()
# The actual child script, request validation, sequence and cleanup run unchanged.
# Only native I/O is replaced in a copied module; no VM/daemon or product is invoked.
$nativeFixture=@'
function Invoke-DevFleetBoundedNativeProbe {
    param($Operation,$FilePath,$ArgumentList,$TimeoutSeconds,$OwnerDeadlineUtc,[switch]$ForceLegacyArgumentString,$MaxStdoutCharacters,$MaxStderrCharacters)
    $now=[datetime]::UtcNow
    $caseRoot=Split-Path -Parent $PSScriptRoot
    [IO.File]::AppendAllText((Join-Path $caseRoot 'native-calls.txt'),$Operation+[Environment]::NewLine)
    [IO.File]::WriteAllText((Join-Path $caseRoot 'runtime.txt'),$PSVersionTable.PSVersion.ToString())
    $output='';$code=0
    switch($Operation){
        'baseline-inventory' {$output='{"list":[]}'}
        'final-inventory' {
            $output='{"list":[]}'
            $custom=Join-Path $caseRoot 'final-response.txt';if(Test-Path $custom){$output=Get-Content $custom -Raw}
            if(Test-Path (Join-Path $caseRoot 'throw-inventory')){throw 'fixture inventory provider failed'}
        }
        'delete-owned' {if(Test-Path (Join-Path $caseRoot 'throw-delete')){throw 'fixture delete provider failed'}}
        'info-running' {$output=(@{info=@{([string]$ArgumentList[1])=@{state='Running';ipv4=@('10.0.0.2');image_hash=('a'*64);image_release='24.04'}};errors=@()}|ConvertTo-Json -Depth 5 -Compress)}
        'info-final' {$output=(@{info=@{([string]$ArgumentList[1])=@{state='Running';ipv4=@('10.0.0.2');image_hash=('a'*64);image_release='24.04'}};errors=@()}|ConvertTo-Json -Depth 5 -Compress)}
        'cloud-init' {$output='status: done'}
        'launch' {[IO.File]::WriteAllText((Join-Path $caseRoot 'launch-arguments.json'),($ArgumentList|ConvertTo-Json -Compress));if(Test-Path (Join-Path $caseRoot 'fail-launch')){$code=7}}
    }
    [pscustomobject]@{operation=$Operation;outcome=if($code-eq0){'PASS'}else{'NONZERO'};exitCode=$code;pid=$PID;startedAtUtc=$now.ToString('o');finishedAtUtc=[datetime]::UtcNow.ToString('o');deadlineUtc=$OwnerDeadlineUtc.ToUniversalTime().ToString('o');stdout=$output;stderr=if($code){'fixture native failure'}else{''};outputComplete=$true;stdoutTruncated=$false;stderrTruncated=$false}
}
Export-ModuleMember -Function Invoke-DevFleetBoundedNativeProbe
function Get-DevFleetCampaignEBackendSnapshot {
    param($InstanceName,$SinceUtc,$OwnerDeadlineUtc)
    $caseRoot=Split-Path -Parent $PSScriptRoot
    [IO.File]::AppendAllText((Join-Path $caseRoot 'backend-calls.txt'),'backend'+[Environment]::NewLine)
    $owned=@();if((Test-Path (Join-Path $caseRoot 'orphan-backend'))-and@(Get-Content (Join-Path $caseRoot 'backend-calls.txt')).Count-ge3){$owned=@(@{name=$InstanceName;state='Running'})}
    [pscustomobject]@{status=if(Test-Path (Join-Path $caseRoot 'fail-backend')){'UNVERIFIED'}else{'COMPLETE'};instanceName=$InstanceName;startedAtUtc=[datetime]::UtcNow.ToString('o');producedAtUtc=[date