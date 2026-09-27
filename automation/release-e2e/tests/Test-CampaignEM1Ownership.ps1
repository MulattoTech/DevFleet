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
