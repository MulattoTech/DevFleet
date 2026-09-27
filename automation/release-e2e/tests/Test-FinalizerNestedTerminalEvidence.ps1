[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$source = Join-Path $WorkspaceRoot 'tools\Invoke-DevFleetFinalConvergence.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count) { throw 'Native finalizer source does not parse.' }
$cleanupSource=Join-Path $WorkspaceRoot 'automation/release-e2e/modules/Cleanup.psm1'
$cleanupTokens=$null;$cleanupErrors=$null
$cleanupAst=[Management.Automation.Language.Parser]::ParseFile($cleanupSource,[ref]$cleanupTokens,[ref]$cleanupErrors)
if(@($cleanupErrors).Count){throw 'Native cleanup module does not parse.'}
$hostGuardAst=@($cleanupAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-DevFleetHostNameExclusion'},$true))
if($hostGuardAst.Count -ne 1){throw 'Expected the exact production host exclusion function.'}
. ([scriptblock]::Create($hostGuardAst[0].Extent.Text))
foreach ($name in @('Add-SecondaryError', 'Get-SafeError', 'Get-CurrentNestedL2ReleaseEvidence', 'Merge-FinalizerTerminalOutcome', 'Invoke-ExactTerminalCleanup')) {
    $functionAst = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
    if ($functionAst.Count -ne 1) { throw "Expected one production $name function." }
    . ([scriptblock]::Create($functionAst[0].Extent.Text))
}

$L1Id = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$L1Name = 'DevFleet-E2E-Win11-01'
$L2Name = 'DevFleet-E2E-Linux-01'
$Workspace = $WorkspaceRoot
$evidence = Join-Path $WorkspaceRoot 'evidence'
$RunId = $null
$RunDirectory = $null
$SkipLiveCleanup = $false
$L1Touched = $false
$secondaryErrors = [Collections.Generic.List[string]]::new()

function Get-VM {
    [CmdletBinding()]
    param([guid]$Id, [string]$Name)
    if ($PSBoundParameters.ContainsKey('Id')) {
        return [pscustomobject]@{ Name=$script:L1Name; Id=$script:L1Id; State='Off' }
    }
    $script:hostQueries++
    if ($script:case -eq 'denied-host-query') { Write-Error 'Mock host inventory unavailable'; return }
    if ($script:case -eq 'present-host-name') { return [pscustomobject]@{ Name=$script:L2Name; Id=[guid]::NewGuid(); State='Off' } }
    if ($script:case -eq 'native-host-name-absence') {
        $message='Hyper-V was unable to find a virtual machine with name "'+$script:L2Name+'".'
        $record=[Management.Automation.ErrorRecord]::new([ArgumentException]::new($message),'InvalidParameter,Microsoft.HyperV.PowerShell.Commands.GetVM',[Management.Automation.ErrorCategory]::InvalidArgument,$script:L2Name)
        throw $record
    }
}

function Stop-VM { throw 'Unexpected VM mutation in VM-free terminal evidence test.' }

$cases = @('empty-host-inventory', 'denied-host-query', 'present-host-name', 'native-host-name-absence')
$rows = [Collections.Generic.List[object]]::new()
foreach ($script:case in $cases) {
    $script:hostQueries = 0
    $actual = Invoke-ExactTerminalCleanup
    $safe = ([string]$actual.status -cne 'PASS' -and [string]$actual.l2State -cne 'ABSENT' -and $actual.l2ExactAbsent -ne $true)
    $rows.Add([ordered]@{
        case=$script:case
        status=[string]$actual.status
        l2State=[string]$actual.l2State
        l2ExactAbsent=$actual.l2ExactAbsent
        hostQueries=$script:hostQueries
        nestedQueries=0
        safeWithoutNestedEvidence=$safe
        hostL2Excluded=$actual.hostL2Excluded
        hostAbsenceDidNotClaimNestedAbsent=([string]$actual.status -ceq 'BLOCKED' -and [string]$actual.l2State -ceq 'UNVERIFIED' -and $actual.l2ExactAbsent -ne $true)
        nativeHostAbsenceClassified=($script:case -ne 'native-host-name-absence' -or ($actual.hostL2Excluded -eq $true -and [string]$actual.l2Error -notmatch 'unable to find a virtual machine'))
    })
}
$blockedMerge=Merge-FinalizerTerminalOutcome -CurrentStatus 'PASS' -PrimaryBlocker '' -PrimaryBlockerClassification '' -SecondaryErrors @() -Terminal ([pscustomobject]@{status='BLOCKED';l2Error='nested proof unavailable'})
$rows.Add([ordered]@{case='outer-finalizer-propagates-terminal-block';status=$blockedMerge.status;l2State='UNVERIFIED';safeWithoutNestedEvidence=([string]$blockedMerge.status -ceq 'BLOCKED' -and [string]$blockedMerge.primaryBlocker -ceq 'nested proof unavailable')})
$preservedMerge=Merge-FinalizerTerminalOutcome -CurrentStatus 'PASS' -PrimaryBlocker 'original stage failure' -PrimaryBlockerClassification 'BLOCKED — PRODUCT' -SecondaryErrors @() -Terminal ([pscustomobject]@{status='BLOCKED';l2Error='nested cleanup failed'})
$rows.Add([ordered]@{case='outer-finalizer-preserves-primary-failure';status=$preservedMerge.status;l2State='UNVERIFIED';safeWithoutNestedEvidence=([string]$preservedMerge.status -ceq 'BLOCKED' -and [string]$preservedMerge.primaryBlocker -ceq 'original stage failure' -and @($preservedMerge.secondaryErrors).Count -eq 1)})

$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-finalizer-nested-proof-'+[guid]::NewGuid().ToString('N'))
$fixtureRunId='fullrelease-fixture-run'
$fixtureRun=Join-Path $fixtureRoot (Join-Path 'audit/automation-harness/runs' $fixtureRunId)
New-Item -ItemType Directory -Path $fixtureRun -Force|Out-Null
function Write-FixtureJson([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))}
function Get-FixtureHash([string]$Path){([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path)))).ToLowerInvariant()}
function Invoke-FixtureNestedValidation([string]$Root,[string]$RunId){
    $script:Workspace=$Root
    $script:RunDirectory=Join-Path $Root (Join-Path 'audit/automation-harness/runs' $RunId)
    Get-CurrentNestedL2ReleaseEvidence -ExpectedRunId $RunId -RunDirectory $script:RunDirectory
}
try{
    $tuple=[ordered]@{repositoryHead=('a'*40);candidateCommit=('b'*40);shippingInputIdentity=('c'*64);releaseFingerprintId=('d'*64);toolingFingerprintId=('e'*64)}
    $observed='2026-09-24T00:00:01Z';$l1Observed='2026-09-24T00:00:02Z'
    $nestedFixture=[ordered]@{schemaVersion=1;runId=$fixtureRunId;status='ABSENT';expectedName=$L2Name;present=$false;observedUtc=$observed;verification='Bounded Multipass JSON inventory inside exact L1';exactMatchCount=0;inventoryCount=0;backendInventories=@();candidate=$tuple;l1=[ordered]@{name=$L1Name;id=$L1Id.ToString()};nestedScope='inside the exact L1 guest session';observer='Get-DevFleetNestedL2State';evidenceClass='FullRelease run-bound nested observation'}
    $nestedPath=Join-Path $fixtureRun 'nested-l2-terminal-observation.json';Write-FixtureJson $nestedPath $nestedFixture;$nestedHash=Get-FixtureHash $nestedPath
    $cleanupFixture=[ordered]@{schemaVersion=1;status='PASS';runId=$fixtureRunId;candidate=$tuple;l1=[ordered]@{state='Off'};guest=[ordered]@{runRootAbsent=$true;nestedAbsent=$true;foreignResourcesMutated=$false}}
    $cleanupPath=Join-Path $fixtureRun 'final-cleanup.json';Write-FixtureJson $cleanupPath $cleanupFixture
    $l1Fixture=[ordered]@{name=$L1Name;id=$L1Id.ToString();state='Off';timestampUtc=$l1Observed;runId=$fixtureRunId}
    $l1Path=Join-Path $fixtureRun 'l1-terminal-state.json';Write-FixtureJson $l1Path $l1Fixture
    $l2Fixture=[ordered]@{schemaVersion=2;expectedName=$L2Name;status='ABSENT';present=$false;timestampUtc=$observed;verificationMethod=$nestedFixture.verification;nestedScope=$nestedFixture.nestedScope;backendInventories=@();runId=$fixtureRunId;sourceRunId=$fixtureRunId;sourceEvidence='nested-l2-terminal-observation.json';sourceEvidenceSha256=$nestedHash;l1Name=$L1Name;l1Id=$L1Id.ToString();candidate=$tuple;evidenceClass='FullRelease run-bound nested observation'}
    $l2Path=Join-Path $fixtureRun 'l2-terminal-state.json';Write-FixtureJson $l2Path $l2Fixture
    $phasePath=Join-Path $fixtureRun 'fullrelease-phase-records.json';Write-FixtureJson $phasePath @([ordered]@{id='CLEANUP';status='PASS'})
    $stateFixture=[ordered]@{runId=$fixtureRunId;mode='FullRelease';finalStatus='PASS';candidateHashes=$tuple};$statePath=Join-Path $fixtureRun 'run-state.json';Write-FixtureJson $statePath $stateFixture
    $postFixture=[ordered]@{status='PASS';runId=$fixtureRunId;cleanupConsumed=$true;candidate=$tuple;liveChecks=[ordered]@{l1ExactOff=$true;l2ExactAbsent=$true;hostSameNameL2Absent=$true;foreignResourcesMutated=$false};cleanupEvidenceHash=(Get-FixtureHash $cleanupPath);terminalL1='l1-terminal-state.json';terminalL1Hash=(Get-FixtureHash $l1Path);terminalL2='l2-terminal-state.json';terminalL2Hash=(Get-FixtureHash $l2Path);nestedL2Observation='nested-l2-terminal-observation.json';nestedL2ObservationSha256=$nestedHash}
    $postPath=Join-Path $fixtureRun 'post-cleanup-finalization.json';Write-FixtureJson $postPath $postFixture
    $accepted=Invoke-FixtureNestedValidation -Root $fixtureRoot -RunId $fixtureRunId
    $rows.Add([ordered]@{case='complete-current-run-nested-provenance-accepted';status='PASS';l2State=[string]$accepted.terminalL2.status;safeWithoutNestedEvidence=([string]$accepted.terminalL2.status -ceq 'ABSENT' -and [string]$accepted.runId -ceq $fixtureRunId -and [string]$accepted.sourceEvidenceSha256 -ceq $nestedHash)})

    $nestedFixture.candidate=[ordered]@{};$l2Fixture.candidate=[ordered]@{};$cleanupFixture.candidate=[ordered]@{};$postFixture.candidate=[ordered]@{};$stateFixture.candidateHashes=[ordered]@{}
    Write-FixtureJson $nestedPath $nestedFixture;$nestedHash=Get-FixtureHash $nestedPath
    $l2Fixture.sourceEvidenceSha256=$nestedHash;Write-FixtureJson $l2Path $l2Fixture
    Write-FixtureJson $cleanupPath $cleanupFixture;Write-FixtureJson $statePath $stateFixture
    $postFixture.cleanupEvidenceHash=Get-FixtureHash $cleanupPath;$postFixture.terminalL1Hash=Get-FixtureHash $l1Path;$postFixture.terminalL2Hash=Get-FixtureHash $l2Path;$postFixture.nestedL2ObservationSha256=$nestedHash
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
