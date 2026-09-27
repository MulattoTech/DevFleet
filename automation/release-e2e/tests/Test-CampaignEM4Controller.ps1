[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$release=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $release 'modules/MultipassDiagnostic.psm1') -Force -DisableNameChecking
$prefix='astra-m4-parent-'+[guid]::NewGuid().ToString('N').Substring(0,8);$scratch=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) $prefix))
$owned=[Collections.Generic.List[string]]::new();$results=[Collections.Generic.List[object]]::new()
# Actual controller and real bounded lifecycle child job. Only VM/remoting,
# artifact inventory, and the external signed-product endpoint are fixtures.
$fixture=@'
$script:fixtureRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$script:case=(Get-Content (Join-Path $script:fixtureRoot 'case.txt') -Raw).Trim()
$script:vm=[pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2';State=if($script:case-ceq'already-running'){'Running'}else{'Off'}}
$script:restores=0;$script:captures=0
function Record($Value){[IO.File]::AppendAllText((Join-Path $script:fixtureRoot 'calls.txt'),$Value+[Environment]::NewLine)}
function Get-VM {param($Id) $script:vm}
function Assert-DisposableOwnership {param($Vm,$ExpectedId)}
function Get-VMSnapshot {param($VM)[pscustomobject]@{Name='Fixture-Prerequisite';Id=[guid]'11111111-1111-1111-1111-111111111111';VMId=$script:vm.Id;ParentSnapshotId=[guid]'19865b76-4c3a-44f7-ba39-841e9d3c40c9'}}
function Get-CandidateFingerprint {param($WorkspaceRoot)[pscustomobject]@{gitCommit=('b'*40);shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64);tar=@{sha256=('a'*64)}}}
function git {'fixture-head'}
function Get-HostSafetySnapshot {param($Vm,$ExpectedVmStartCostGiB)[pscustomobject]@{startSafe=($script:case-cne'unsafe');availableMemoryGiB=30;projectedPostStartAvailableMemoryGiB=16}}
function Restore-ExactCheckpoint {param($Vm,$Name,[switch]$StartAfterRestore)$script:restores++;Record ('restore-'+$script:restores);$script:vm.State='Running';[pscustomobject]@{restored=$true;id='11111111-1111-1111-1111-111111111111'}}
function Stop-VM {param($VM,[switch]$Force,[switch]$Confirm)Record 'stop';$script:vm.State='Off'}
function Ensure-FullReleaseInteractiveDesktop {param($VmId)Record 'interactive';[pscustomobject]@{status='PASS';mode='fixture'}}
function Connect-DevFleetGuest {param($VmId)'fixture-session'}
function Remove-PSSession {param($Session)}
function Get-DevFleetNestedL2State {param($Session,$ExpectedName)[pscustomobject]@{status='ABSENT';inventoryCount=0}}
function Write-EvidenceJson {param($Path,$Value)$Value|ConvertTo-Json -Depth 24|Set-Content -LiteralPath $Path}
function Copy-DevFleetBoundedGuestFile {
    param($LocalPath,$Session,$RemotePath,$TimeoutSeconds)
    Copy-Item -LiteralPath $LocalPath -Destination $RemotePath
    if($script:case-ceq'collector-module-hash'){Add-Content $RemotePath '# fixture altered bytes'}
    if($script:case-ceq'collector-nonce'){$path=Join-Path (Split-Path -Parent $RemotePath) '.owner.json';$owner=Get-Content $path -Raw|ConvertFrom-Json;$owner.nonce='wrong-owner';$owner|ConvertTo-Json|Set-Content $path}
    [pscustomobject]@{status='PASS'}
}
function Invoke-DevFleetBoundedGuestProcess {
    param($Session,$FilePath,$ArgumentList,$OwnerDeadlineUtc)
    $script:captures++;Record ('snapshot-'+$script:captures)
    if($script:captures-eq2-and$script:case-ceq'terminal-transport'){throw 'fixture terminal transport unavailable'}
    $encoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]));$requestText=[regex]::Match($encoded,"\} '([A-Za-z0-9+/=]+)'$").Groups[1].Value
    $request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($requestText))|ConvertFrom-Json
    @{case=$script:case;capture=$script:captures}|ConvertTo-Json|Set-Content (Join-Path $request.path '.fixture.json')
    $json=@{filePath=$FilePath;arguments=@($ArgumentList);deadlineUnixMilliseconds=[DateTimeOffset]::new($OwnerDeadlineUtc).ToUnixTimeMilliseconds()}|ConvertTo-Json -Compress
    & (Get-DevFleetBoundedProcessScriptBlock) $json
}
function Invoke-DevFleetBoundedGuestCommand {
    param($Session,$TimeoutSeconds,$ScriptBlock,$ArgumentList)
    if($ScriptBlock.ToString()-match"ids=@"){
        Record 'final-backend';return [pscustomobject]@{status='COMPLETE';count=if($script:case-ceq'final-orphan'){1}else{0};ids=@()}
    }
    $prior=$env:ProgramData;try{$env:ProgramData=Join-Path $script:fixtureRoot 'isolated-data';&$ScriptBlock @ArgumentList}finally{$env:ProgramData=$prior}
}
Export-ModuleMember -Function *
'@
$collectorFixture=@'
function Get-DevFleetCampaignEBackendSnapshot {
    param($InstanceName,$SinceUtc,$OwnerDeadlineUtc,$TimeoutSeconds,[switch]$ProductContext,$ExpectedPayloadSha256)
    if($InstanceName-cne'devfleet-primary'-or-not$ProductContext-or$ExpectedPayloadSha256-cne('a'*64)){throw 'M4 collector product binding failed.'}
    $fixture=Get-Content (Join-Path $PSScriptRoot '.fixture.json') -Raw|ConvertFrom-Json
    $backend=if($fixture.capture-eq2-and$fixture.case-ceq'terminal-backend'){'UNVERIFIED'}else{'PASS'}
    [pscustomobject]@{status=if($fixture.case-ceq'baseline-partial'-or($fixture.capture-eq2-and$fixture.case-ceq'terminal-partial')){'PARTIAL'}else{'COMPLETE'};data=@{backend=@{status=$backend;foreignCount=if($fixture.capture-eq2-and$fixture.case-ceq'foreign-terminal'){1}else{0};owned=@()};product=@{status='TRANSACTION_OBSERVED'}}}
}
Export-ModuleMember -Function *
'@
$productFixture=@'
function Invoke-ProductFreshInstallLifecycle {
    param($Context,$Role)
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
    if($Context.phaseId-cne'CAMPAIGN-E-M4'-or$Role-cne'Primary / Desktop'-or$Context.vmId-cne'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'-or-not$Context.diagnosticOnly-or$Context.certificationEligible){throw 'M4 product context identity/diagnostic boundary failed.'}
    foreach($name in $Context.PSObject.Properties.Name){if($name-match'Provider|synthetic'){throw 'M4 supplied a forbidden product seam.'}}
    [IO.File]::AppendAllText((Join-Path $root 'calls.txt'),'actual-child-entry'+[Environment]::NewLine)
    $case=(Get-Content (Join-Path $root 'case.txt') -Raw).Trim()
    $result=[ordered]@{status=if($case-ceq'product-failure'){'TERMINAL_FAILURE'}else{'REAL E2E PASS'};completionVerified=($case-cne'product-failure');transactionId=('f'*32);payloadSha256=('a'*64);evidencePath='fixture-native-evidence.json'}
    if($case-ceq'product-failure'){$result.error='fixture launch failed token=private-fixture'}
    [pscustomobject]$result
}
Export-ModuleMember -Function Invoke-ProductFreshInstallLifecycle
'@
try{
    New-Item -ItemType Directory -Path $scratch|Out-Null
    foreach($case in @('success','product-failure','terminal-backend','terminal-transport','already-running','unsafe','final-orphan','preexisting-run','collector-module-hash','collector-executable-hash','collector-nonce','foreign-terminal','baseline-partial','terminal-partial')){
        $caseRoot=Join-Path $scratch $case;$run=$prefix+'-'+$case;$guest=[IO.Path]::GetFullPath("C:\Users\Public\DevFleet-E2E\$run");$owned.Add($guest)
        $modules=Join-Path $caseRoot 'automation/release-e2e/modules';New-Item -ItemType Directory -Path $modules,(Join-Path $modules 'executors'),(Join-Path $caseRoot 'evidence'),(Join-Path $caseRoot 'automation/release-e2e/config')|Out-Null
        [IO.File]::WriteAllText((Join-Path $caseRoot 'case.txt'),$case)
        foreach($name in @('Candidate','HostSafety','FullRelease','GuestSession','Evidence','MultipassDiagnostic','HarnessBudget')){
            $body=if($name-ceq'HarnessBudget'){[IO.File]::ReadAllText((Join-Path $release 'modules/HarnessBudget.psm1'))+[Environment]::NewLine+$fixture}elseif($name-ceq'MultipassDiagnostic'){[IO.File]::ReadAllText((Join-Path $release 'modules/MultipassDiagnostic.psm1'))+[Environment]::NewLine+$collectorFixture}else{'# Fixture only'}
            [IO.File]::WriteAllText((Join-Path $modules ($name+'.psm1')),$body,[Text.UTF8Encoding]::new($false))
        }
        [IO.File]::WriteAllText((Join-Path $modules 'executors/Invoke-RealProductPhase.psm1'),$productFixture,[Text.UTF8Encoding]::new($false))
        Copy-Item (Join-Path $release 'config/devfleet-e2e.defaults.json') (Join-Path $caseRoot 'automation/release-e2e/config/devfleet-e2e.defaults.json')
        @{candidateIsCurrent=$true;sourceChangedSinceCandidate=$false;rebuildRequired=$false;repositoryHead='fixture-head';shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64)}|ConvertTo-Json|Set-Content (Join-Path $caseRoot 'evidence/CURRENT-RELEASE-AUTHORITY.json')
        $checkpoint=Join-Path $caseRoot 'checkpoint.json';@{status='PASS_CHECKPOINT_READY';campaign='DF-STABLE-20260906-E';diagnosticCheckpoint=@{id='11111111-1111-1111-1111-111111111111';name='Fixture-Prerequisite';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';parentSnapshotId='19865b76-4c3a-44f7-ba39-841e9d3c40c9';payloadSha256=('a'*64);powershell=@{pathSha256=(Get-FileHash (Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe') -Algorithm SHA256).Hash.ToLowerInvariant()};l1State='OFF';l2Status='ABSENT'}}|ConvertTo-Json -Depth 5|Set-Content $checkpoint
        if($case-ceq'collector-executable-hash'){$record=Get-Content $checkpoint -Raw|ConvertFrom-Json;$record.diagnosticCheckpoint.powershell.pathSha256='0'*64;$record|ConvertTo-Json -Depth 5|Set-Content $checkpoint}
        $recordPath=Join-Path $caseRoot "audit/automation-harness/runs/$run/campaign-e-m4.json"
        if($case-ceq'preexisting-run'){New-Item -ItemType Directory -Path (Split-Path -Parent $recordPath)|Out-Null;[IO.File]::WriteAllText($recordPath,'{"preserved":true}');$priorHash=(Get-FileHash $recordPath -Algorithm SHA256).Hash}
        $probe=Invoke-DevFleetBoundedNativeProbe -Operation $case -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $release 'Invoke-CampaignEProductM4.ps1'),'-WorkspaceRoot',$caseRoot,'-RunId',$run,'-CheckpointEvidencePath',$checkpoint) -TimeoutSeconds 18 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(22)) -ForceLegacyArgumentString -MaxStdoutCharacters 32768
        $record=Get-Content $recordPath -Raw|ConvertFrom-Json;$calls=@(if(Test-Path (Join-Path $caseRoot 'calls.txt')){Get-Content (Join-Path $caseRoot 'calls.txt')})
        if($case-ceq'preexisting-run'){$pass=$probe.exitCode-eq1-and$calls.Count-eq0-and(Get-FileHash $recordPath -Algorithm SHA256).Hash-ceq$priorHash}
        elseif($case-cin@('already-running','unsafe')){$pass=$probe.exitCode-eq1-and$calls.Count-eq0-and-not$record.cleanup.acquired-and$record.finalL1.state-ceq$(if($case-ceq'already-running'){'Running'}else{'Off'})}
        elseif($case-like'collector-*'){
            $first=Get-Content (Join-Path (Split-Path -Parent $recordPath) 'snapshot-0001-before-product.json') -Raw|ConvertFrom-Json
            $pass=$probe.exitCode-eq1-and$calls-notcontains'actual-child-entry'-and$calls-notcontains'restore-2'-and$calls-contains'stop'-and$record.finalL1.state-ceq'Off'-and$first.status-ceq'UNAVAILABLE'-and$first.error-match'mismatch'-and(Test-Path (Join-Path $guest 'M4/.owner.json'))
        }
        elseif($case-ceq'baseline-partial'){$pass=$probe.exitCode-eq1-and$calls-notcontains'actual-child-entry'-and$calls-notcontains'restore-2'-and$record.finalL1.state-ceq'Off'}
        else{
            $pass=$record.experiment-ceq'M4'-and-not$record.proofCredit-and-not$record.certificationEligible-and$calls-contains'actual-child-entry'-and$calls-contains'stop'-and$record.finalL1.state-ceq'Off'
            if($case-cin@('terminal-backend','terminal-transport','foreign-terminal','terminal-partial')){$pass=$pass-and$probe.exitCode-eq1-and$calls-notcontains'restore-2'-and(Test-Path (Join-Path $guest 'M4/.owner.json'))}
            else{$pass=$pass-and$calls.IndexOf('snapshot-2')-lt$calls.IndexOf('restore-2')-and$calls-contains'final-backend';if($case-ceq'success'){$pass=$pass-and$probe.exitCode-eq0-and$record.status-ceq'PASS_DIAGNOSTIC'}else{$pass=$pass-and$probe.exitCode-eq1-and$record.status-ceq'BLOCKED'}}
            $pass=$pass-and($record|ConvertTo-Json -Depth 12)-notmatch'private-fixture'
            $first=Get-Content (Join-Path (Split-Path -Parent $recordPath) 'snapshot-0001-before-product.json') -Raw|ConvertFrom-Json
            $pass=$pass-and$first.delivery.persistentPolicyUnchanged-and$first.delivery.processOnlyExecutionPolicy-ceq'Bypass'-and$first.delivery.powerShellVersion-like'7.*'
        }
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;exitCode=$probe.exitCode;calls=$calls;error=if($record.PSObject.Properties['primaryError']){$record.primaryError}else{''};stderr=$probe.stderr})
    }
}finally{
    foreach($path in @($owned)+@($scratch)){if(($path-cne$scratch-and-not$path.StartsWith('C:\Users\Public\DevFleet-E2E\'+$prefix,[StringComparison]::Ordinal))-or[IO.Path]::GetFileName($path)-notlike($prefix+'*')){throw 'M4 fixture cleanup escaped exact ownership.'};if(Test-Path $path){Remove-Item -LiteralPath $path -Recurse -Force}}
}
$results|ConvertTo-Json -Depth 5
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Actual M4 controller regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) actual M4 controller checks"
