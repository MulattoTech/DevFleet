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
    $reboundPointer.schemaVersion=7;$reboundPointer.contract='devfleet-accepted-baseline-v7';$reboundPointer.generation=7
    [IO.File]::WriteAllText($pointerPath,($reboundPointer|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    Assert-Rejected {Get-DevFleetAcceptedBaseline -WorkspaceRoot $root -Fingerprint $newFingerprint} 'Generation 7 accepted a non-generation-6 predecessor or stale receipt.'
    $reboundPointer.schemaVersion=8;$reboundPointer.contract='devfleet-accepted-baseline-v8';$reboundPointer.generation=8
    [IO.File]::WriteAllText($pointerPath,($reboundPointer|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $gen8Failure=$null
    try {Get-DevFleetAcceptedBaseline -WorkspaceRoot $root -Fingerprint $newFingerprint|Out-Null}
    catch {$gen8Failure=$_.Exception.Message}
    Assert-True ($gen8Failure -ceq 'Native rebound baseline lineage rejected.') 'Generation 8 did not dispatch through the strict Python lineage reader.'
    "PASS $count baseline lineage PowerShell assertions"
}finally{
    Remove-Item Function:\Get-VM,Function:\Get-VMSnapshot -ErrorAction SilentlyContinue
    Remove-Module FullRelease -ErrorAction SilentlyContinue
    Remove-Module BaselineLineage -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
