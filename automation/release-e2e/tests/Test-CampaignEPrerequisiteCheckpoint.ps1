$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$modulePath=Join-Path $root 'automation\release-e2e\modules\MultipassDiagnostic.psm1'
Import-Module $modulePath -Force
$count=0
function Check([bool]$Condition,[string]$Message){if(-not$Condition){throw "FAIL: $Message"};$script:count++}
function Rejected([scriptblock]$Action,[string]$Message){$failed=$false;try{&$Action|Out-Null}catch{$failed=$true};Check $failed $Message}
function Clone($Value){$Value|ConvertTo-Json -Depth 24|ConvertFrom-Json}

$plan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot (Join-Path $root 'source') -Role Desktop
Check ([string]$plan.packageVersion-ceq'1.2.13') 'candidate package version was not selected'
Check (@($plan.dependencyIds).Count-eq2-and@($plan.dependencyIds)-ccontains'powershell7'-and@($plan.dependencyIds)-ccontains'multipass') 'plan did not remain scoped to PowerShell 7 and Multipass'
Check ([string]$plan.expectedBackend-ceq'hyperv'-and-not[bool]$plan.privilegedMounts) 'plan weakened the candidate backend/mount policy'
Check (@($plan.candidateInstanceNames).Count-eq3) 'plan did not preserve candidate product identities'
Check (@($plan.dependencies.powershell7.allowedSignerSubjectsExact).Count-eq1-and[string]$plan.dependencies.powershell7.allowedSignerSubjectsExact[0]-ceq'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US') 'plan did not preserve the candidate exact PowerShell signer policy'
$policyProjection=Get-DevFleetSystemExecutionPolicyProjection -PolicyProvider {param($scope)"policy-$scope"}
Check ([string]$policyProjection.MachinePolicy-ceq'policy-MachinePolicy'-and[string]$policyProjection.CurrentUser-ceq'policy-CurrentUser') 'execution-policy evidence read array-shaped policy output incorrectly'
$owner=[datetime]'2026-09-06T20:40:00Z';$clock=[datetime]'2026-09-06T20:00:00Z'
$partition=Get-DevFleetCampaignEDeadlinePartition -OwnerDeadlineUtc $owner -ReservedTerminalizationSeconds 300 -ClockProvider {$clock}
Check ((([datetime]$partition.childDeadlineUtc).ToUniversalTime()-eq$owner.ToUniversalTime().AddSeconds(-300))-and([int]$partition.childRemainingSeconds-eq2100)) 'deadline partition did not reserve terminalization from the immutable owner'
Rejected {Get-DevFleetCampaignEDeadlinePartition -OwnerDeadlineUtc $owner -ReservedTerminalizationSeconds 300 -ClockProvider {$owner.AddSeconds(-299)}} 'deadline partition granted a fresh child allowance after terminalization reserve exhaustion'
$ownerRecord=[pscustomobject]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_STAGING_OWNER';runId='unit-prereq';nonce='11111111-1111-1111-1111-111111111111'}
Check (Assert-DevFleetCampaignEStagingOwnership -Record $ownerRecord -ExpectedRunId 'unit-prereq' -ExpectedNonce ([guid]'11111111-1111-1111-1111-111111111111')) 'valid staging ownership record was rejected'
$wrongOwner=Clone $ownerRecord;$wrongOwner.nonce='22222222-2222-2222-2222-222222222222'
Rejected {Assert-DevFleetCampaignEStagingOwnership -Record $wrongOwner -ExpectedRunId 'unit-prereq' -ExpectedNonce ([guid]'11111111-1111-1111-1111-111111111111')} 'wrong staging ownership nonce was accepted'
$durableWorker=[ordered]@{kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY';runId='unit-prereq';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);status='PASS'}|ConvertTo-Json -Compress
$resolvedNoisy=Resolve-DevFleetCampaignEWorkerResult -ProcessStdout "diagnostic-noise`n$durableWorker" -DurableRaw $durableWorker
Check ([string]$resolvedNoisy.source-ceq'DURABLE'-and[string]$resolvedNoisy.processStdoutStatus-ceq'MALFORMED'-and[string]$resolvedNoisy.value.runId-ceq'unit-prereq') 'durable worker result did not survive malformed process stdout'
$resolvedMatching=Resolve-DevFleetCampaignEWorkerResult -ProcessStdout $durableWorker -DurableRaw $durableWorker
Check ([string]$resolvedMatching.source-ceq'DURABLE_AND_PROCESS_MATCH'-and[string]$resolvedMatching.processStdoutStatus-ceq'VALID') 'matching process/durable worker results were not recognized'
Rejected {Resolve-DevFleetCampaignEWorkerResult -ProcessStdout '' -DurableRaw '{malformed'} 'malformed durable worker result was accepted'
$differentWorker=($durableWorker|ConvertFrom-Json);$differentWorker.status='BLOCKED';$differentRaw=$differentWorker|ConvertTo-Json -Compress
Rejected {Resolve-DevFleetCampaignEWorkerResult -ProcessStdout $differentRaw -DurableRaw $durableWorker} 'disagreeing process/durable worker results were accepted'
$wrongKindWorker=($durableWorker|ConvertFrom-Json);$wrongKindWorker.kind='ARBITRARY';$wrongKindRaw=$wrongKindWorker|ConvertTo-Json -Compress
Rejected {Resolve-DevFleetCampaignEWorkerResult -ProcessStdout '' -DurableRaw $wrongKindRaw} 'unsupported durable worker result kind was accepted'

$candidateTar=Join-Path $root 'outputs\devfleet-v1.2.13.tar.gz'
$entries=@(& tar.exe -tf $candidateTar)
if($LASTEXITCODE-ne0){throw 'Unable to list the candidate TAR for the production-plan regression.'}
Check (Assert-DevFleetCampaignEArchiveEntries -Entries $entries) 'actual candidate archive was rejected'
$extractRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-e-prereq-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $extractRoot|Out-Null
    & tar.exe -xf $candidateTar -C $extractRoot
    if($LASTEXITCODE-ne0){throw 'Unable to extract the candidate TAR for the production-plan regression.'}
    $extractedPlan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot $extractRoot -Role Desktop
    foreach($name in @('version','dependencies','config','bootstrap','install','common')){Check ([string]$extractedPlan.inputHashes.$name-ceq[string]$plan.inputHashes.$name) "candidate TAR/source prerequisite hash mismatch: $name"}
} finally {if(Test-Path -LiteralPath $extractRoot){Remove-Item -LiteralPath $extractRoot -Recurse -Force}}
Rejected {Assert-DevFleetCampaignEArchiveEntries -Entries @('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json','windows/DevFleet.Common.psm1','../escape')} 'archive traversal was accepted'
Rejected {Assert-DevFleetCampaignEArchiveEntries -Entries @('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json','windows/DevFleet.Common.psm1','C:\escape')} 'rooted archive entry was accepted'
Rejected {Assert-DevFleetCampaignEArchiveEntries -Entries @('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json','windows/DevFleet.Common.psm1','VERSION')} 'duplicate archive entry was accepted'
Rejected {Assert-DevFleetCampaignEArchiveEntries -Entries @('Bootstrap-Install.ps1','Install-DevFleet.ps1','VERSION','dependencies.json','config/devfleet.config.json')} 'missing candidate common module was accepted'

$acquisitionFixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-e-acquire-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $acquisitionFixtureRoot|Out-Null
    $fixtureWinget=Join-Path $acquisitionFixtureRoot 'winget.exe'
    Copy-Item -LiteralPath (Get-Process -Id $PID).Path -Destination $fixtureWinget
    $powershellDependency=@((Get-Content -LiteralPath (Join-Path $root 'source\dependencies.json') -Raw|ConvertFrom-Json).dependencies|Where-Object{[string]$_.id-ceq'powershell7'})[0]
    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z'
    $script:compatibilityCalls=0
    $script:nativeCalls=[Collections.Generic.List[object]]::new()
    $clockProvider={$script:acquisitionNow}
    $candidateProvider={param($dependency)[pscustomobject]@{path=$fixtureWinget;root=$acquisitionFixtureRoot;trustValidated=$true}}
    $compatibilityProvider={
        param($dependency,$deadline)
        $script:compatibilityCalls++
        if($script:compatibilityCalls-eq1){return [pscustomobject]@{status='Missing';version='';pathSha256='';detail='fixture absent'}}
        return [pscustomobject]@{status='Compatible';version='7.4.2';pathSha256=('b'*64);detail='fixture compatible'}
    }
    $nativeProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        $start=$script:acquisitionNow;$script:acquisitionNow=$script:acquisitionNow.AddSeconds(10)
        [void]$script:nativeCalls.Add([pscustomobject]@{operation=$operation;filePath=$filePath;arguments=@($arguments);timeoutSeconds=$timeoutSeconds;ownerDeadlineUtc=([datetime]$deadline).ToUniversalTime().ToString('o')})
        $stdout=if($operation-eq'winget-version'){'v1.8.1911'}elseif($operation-eq'winget-powershell-search'){'PowerShell Microsoft.PowerShell 7.4.2'}else{'fixture output'}
        [pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:acquisitionNow.ToString('o');deadlineUtc=$start.AddSeconds($timeoutSeconds).ToString('o');stdout=$stdout;stderr='';outputComplete=$true}
    }
    $acquisition=Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $nativeProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider
    Check ([string]$acquisition.method-ceq'WINGET_MANIFEST_APPROVED_DIAGNOSTIC'-and[string]$acquisition.packageId-ceq'Microsoft.PowerShell'-and@($acquisition.operations).Count-eq5) 'production acquisition function did not preserve the candidate manifest identity and five bounded operations'
    $sourceUpdateCall=@($script:nativeCalls|Where-Object{$_.operation-ceq'winget-source-update'})[0]
    Check ((@($sourceUpdateCall.arguments)-join' ')-ceq'source update --name winget --disable-interactivity') 'production acquisition function did not construct the exact bounded WinGet source-update arguments'
    $installCall=@($script:nativeCalls|Where-Object{$_.operation-ceq'winget-powershell-install'})[0]
    Check ((@($installCall.arguments)-join' ')-ceq'install --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity') 'production acquisition function did not construct the exact candidate-approved WinGet install arguments'
    Check ([int]$installCall.timeoutSeconds-eq80-and@($script:nativeCalls|Where-Object{$_.ownerDeadlineUtc-cne'2026-09-06T20:02:00.0000000Z'}).Count-eq0) 'production acquisition function granted a fresh child allowance or changed the immutable owner deadline'
    Check (-not[bool]$acquisition.productLifecycleStarted-and-not[bool]$acquisition.stageMarkerWritten-and($acquisition|ConvertTo-Json -Depth 12)-notmatch'fixture output') 'PowerShell acquisition fabricated product progress or retained raw native output'

    $script:compatibilityCalls=0;$script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z'
    $alreadySatisfiedProvider={param($dependency,$deadline)[pscustomobject]@{status='Compatible';version='7.4.2';pathSha256=('c'*64);detail='fixture compatible'}}
    $unexpectedNative={throw 'WinGet must not run when candidate-compatible PowerShell is already present.'}
    $preserved=Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider {throw 'WinGet candidate discovery must not run.'} -NativeProbeProvider $unexpectedNative -PowerShellCompatibilityProvider $alreadySatisfiedProvider -ClockProvider $clockProvider
    Check ([string]$preserved.method-ceq'PRESERVED_CANDIDATE_COMPATIBLE'-and@($preserved.operations).Count-eq0) 'production acquisition did not preserve an already compatible candidate-trusted PowerShell executable'
    $script:lateCompatibilityClockCalls=0
    $lateCompatibilityClock={
        $script:lateCompatibilityClockCalls++
        if($script:lateCompatibilityClockCalls-eq1){return [datetime]'2026-09-06T20:00:00Z'}
        return [datetime]'2026-09-06T20:02:01Z'
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider {throw 'WinGet candidate discovery must not run.'} -NativeProbeProvider $unexpectedNative -PowerShellCompatibilityProvider $alreadySatisfiedProvider -ClockProvider $lateCompatibilityClock} 'production acquisition revived a compatible observation completed after cutoff'

    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency ([pscustomobject]@{id='powershell7';minimumSupportedVersion='7.4.0';maximumMajor=7;wingetPackageId='Arbitrary.PowerShell'}) -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $nativeProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted a non-candidate package identity'
    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider {param($d)@([pscustomobject]@{path=$fixtureWinget;root=$acquisitionFixtureRoot;trustValidated=$true},[pscustomobject]@{path=$fixtureWinget;root=$acquisitionFixtureRoot;trustValidated=$true})} -NativeProbeProvider $nativeProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted ambiguous WinGet identity'
    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider {param($d)[pscustomobject]@{path=$fixtureWinget;root=$acquisitionFixtureRoot;trustValidated=$false}} -NativeProbeProvider $nativeProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted unvalidated WinGet identity'

    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    $badSearchProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        $start=$script:acquisitionNow;$script:acquisitionNow=$script:acquisitionNow.AddSeconds(1)
        $stdout=if($operation-eq'winget-version'){'v1.8.1911'}elseif($operation-eq'winget-powershell-search'){'unrelated package'}else{''}
        [pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:acquisitionNow.ToString('o');deadlineUtc=$start.AddSeconds($timeoutSeconds).ToString('o');stdout=$stdout;stderr='';outputComplete=$true}
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $badSearchProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted a search response without the exact manifest package'

    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    $timeoutProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        $start=$script:acquisitionNow;$script:acquisitionNow=$script:acquisitionNow.AddSeconds(1)
        [pscustomobject]@{operation=$operation;outcome='TIMEOUT';exitCode=$null;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:acquisitionNow.ToString('o');deadlineUtc=$start.AddSeconds($timeoutSeconds).ToString('o');stdout='';stderr='bounded timeout';outputComplete=$true}
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $timeoutProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition treated a bounded native timeout as prerequisite progress'

    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0
    $lateProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        [pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;startedAtUtc='2026-09-06T20:00:00Z';finishedAtUtc='2026-09-06T20:02:01Z';deadlineUtc='2026-09-06T20:02:00Z';stdout='v1.8.1911';stderr='';outputComplete=$true}
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $lateProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition retroactively accepted an operation first completed after cutoff'
    $script:acquisitionNow=[datetime]'2026-09-06T20:00:00Z';$script:compatibilityCalls=0;$script:nonmonotonicCalls=0
    $nonmonotonicProvider={
        param($operation,$filePath,$arguments,$timeoutSeconds,$deadline)
        $script:nonmonotonicCalls++
        if($script:nonmonotonicCalls-eq1){$start=[datetime]'2026-09-06T20:00:00Z';$finish=[datetime]'2026-09-06T20:00:10Z';$script:acquisitionNow=$finish}
        else{$start=[datetime]'2026-09-06T20:00:05Z';$finish=[datetime]'2026-09-06T20:00:06Z'}
        $stdout=if($operation-eq'winget-version'){'v1.8.1911'}else{'Microsoft.PowerShell'}
        [pscustomobject]@{operation=$operation;outcome='PASS';exitCode=0;startedAtUtc=$start.ToString('o');finishedAtUtc=$finish.ToString('o');deadlineUtc='2026-09-06T20:01:00Z';stdout=$stdout;stderr='';outputComplete=$true}
    }
    Rejected {Invoke-DevFleetCampaignEPowerShellAcquisition -Dependency $powershellDependency -OwnerDeadlineUtc ([datetime]'2026-09-06T20:02:00Z') -TrustedWingetCandidateProvider $candidateProvider -NativeProbeProvider $nonmonotonicProvider -PowerShellCompatibilityProvider $compatibilityProvider -ClockProvider $clockProvider} 'production acquisition accepted nonmonotonic native observations'
} finally {if(Test-Path -LiteralPath $acquisitionFixtureRoot){Remove-Item -LiteralPath $acquisitionFixtureRoot -Recurse -Force}}

$officialFixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-e-official-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $officialFixtureRoot|Out-Null
    $script:officialDependency=@((Get-Content -LiteralPath (Join-Path $root 'source\dependencies.json') -Raw|ConvertFrom-Json).dependencies|Where-Object{[string]$_.id-ceq'powershell7'})[0]
    $script:officialFixtureRoot=$officialFixtureRoot;$script:officialBase=[datetime]'2026-09-06T20:00:00Z';$script:officialOwner=$script:officialBase.AddMinutes(5)
    $copySource=[IO.MemoryStream]::new([byte[]](1,2,3));$copyTarget=[IO.MemoryStream]::new()
    try {$unsuppressedCopyOutput=@($copySource.CopyToAsync($copyTarget,81920,[Threading.CancellationToken]::None).GetAwaiter().GetResult());Check ($unsuppressedCopyOutput.Count-eq0-or($unsuppressedCopyOutput.Count-eq1-and$unsuppressedCopyOutput[0].GetType().FullName-ceq'System.Threading.Tasks.VoidTaskResult')) 'async stream-copy runtime behavior was neither silent nor the proven PowerShell 7 task-result emission'} finally {$copySource.Dispose();$copyTarget.Dispose()}
    $copySource=[IO.MemoryStream]::new([byte[]](1,2,3));$copyTarget=[IO.MemoryStream]::new()
    try {$suppressedCopyOutput=@(&{[void]$copySource.CopyToAsync($copyTarget,81920,[Threading.CancellationToken]::None).GetAwaiter().GetResult();[pscustomobject]@{outcome='PASS';bytes=$copyTarget.Length}});Check ($suppressedCopyOutput.Count-eq1-and[string]$suppressedCopyOutput[0].outcome-ceq'PASS'-and[int64]$suppressedCopyOutput[0].bytes-eq3) 'bounded stream copy leaked an incidental task result into the download evidence stream'} finally {$copySource.Dispose();$copyTarget.Dispose()}
    $script:officialMetadata=[pscustomobject]@{tag_name='v7.4.2';draft=$false;prerelease=$false;html_url='https://github.com/PowerShell/PowerShell/releases/tag/v7.4.2';assets=@([pscustomobject]@{name='PowerShell-7.4.2-win-x64.msi';browser_download_url='https://github.com/PowerShell/PowerShell/releases/download/v7.4.2/PowerShell-7.4.2-win-x64.msi'})}
    function Invoke-OfficialPayloadFixture {
        param([psobject]$MetadataValue=$script:officialMetadata,[string]$SignerSubject='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US',[switch]$BadHash,[switch]$LateDownload,[switch]$ExistingDestination)
        $destination=Join-Path $script:officialFixtureRoot ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $destination|Out-Null
        if($ExistingDestination){Set-Content -LiteralPath (Join-Path $destination 'PowerShell-7.4.2-win-x64.msi') -Value 'foreign' -NoNewline -Encoding Ascii}
        $fixtureBase=$script:officialBase;$fixtureOwner=$script:officialOwner
        $clockState=[pscustomobject]@{Now=$fixtureBase}
        $metadataProvider={param($uri,$timeout,$deadline)$clockState.Now=$fixtureBase.AddSeconds(1);$MetadataValue}.GetNewClosure()
        $downloadProvider={
            param($uri,$hosts,$path,$deadline)
            $started=$fixtureBase.AddSeconds(1);$finished=if($LateDownload){$fixtureOwner.AddSeconds(1)}else{$fixtureBase.AddSeconds(2)}
            Set-Content -LiteralPath $path -Value 'fixture-official-msi' -NoNewline -Encoding Ascii
            $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();if($BadHash){$hash='a'*64}
            $clockState.Now=$finished
            [pscustomobject]@{outcome='PASS';startedAtUtc=$started.ToString('o');finishedAtUtc=$finished.ToString('o');deadlineUtc=$fixtureOwner.ToString('o');finalHost='github.com';redirectHosts=@('github.com');bytes=(Get-Item -LiteralPath $path).Length;sha256=$hash}
        }.GetNewClosure()
        $authenticityProvider={param($path,$policy)$clockState.Now=$clockState.Now.AddSeconds(1);[pscustomobject]@{status='Valid';signerSubject=$SignerSubject}}.GetNewClosure()
        $clockProvider={$clockState.Now}.GetNewClosure()
        Get-DevFleetCampaignEOfficialPowerShellPayload -Dependency $script:officialDependency -DestinationDirectory $destination -OwnerDeadlineUtc $script:officialOwner -MetadataProvider $metadataProvider -DownloadProvider $downloadProvider -AuthenticityProvider $authenticityProvider -ClockProvider $clockProvider
    }
    $official=Invoke-OfficialPayloadFixture
    Check ([string]$official.kind-ceq'DEVFLEET_CAMPAIGN_E_OFFICIAL_POWERSHELL_PAYLOAD'-and[string]$official.method-ceq'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'-and[string]$official.packageId-ceq'Microsoft.PowerShell') 'official payload resolver lost the exact candidate package/repository identity'
    Check ([string]$official.releaseTag-ceq'v7.4.2'-and[string]$official.assetName-ceq'PowerShell-7.4.2-win-x64.msi'-and[string]$official.sha256-match'^[0-9a-f]{64}$'-and[int64]$official.bytes-gt0) 'official payload resolver did not publish a non-secret hash-bound MSI identity'
    Check (-not[bool]$official.productLifecycleStarted-and-not[bool]$official.stageMarkerWritten-and@($official.redirectHosts).Count-eq1) 'official payload resolution fabricated product progress or lost redirect provenance'

    $wrongRepository=Clone $script:officialMetadata;$wrongRepository.html_url='https://github.com/Other/PowerShell/releases/tag/v7.4.2'
    Rejected {Invoke-OfficialPayloadFixture -MetadataValue $wrongRepository} 'official payload resolver accepted the wrong release repository'
    $draft=Clone $script:officialMetadata;$draft.draft=$true
    Rejected {Invoke-OfficialPayloadFixture -MetadataValue $draft} 'official payload resolver accepted a draft release'
    $ambiguous=Clone $script:officialMetadata;$ambiguous.assets=@($ambiguous.assets[0],$ambiguous.assets[0])
    Rejected {Invoke-OfficialPayloadFixture -MetadataValue $ambiguous} 'official payload resolver accepted ambiguous matching MSI assets'
    $wrongAsset=Clone $script:officialMetadata;$wrongAsset.assets[0].browser_download_url='https://github.com/Other/PowerShell/releases/download/v7.4.2/PowerShell-7.4.2-win-x64.msi'
    Rejected {Invoke-OfficialPayloadFixture -MetadataValue $wrongAsset} 'official payload resolver accepted a wrong-repository asset URL'
    Rejected {Invoke-OfficialPayloadFixture -SignerSubject 'CN=Untrusted Fixture'} 'official payload resolver accepted the wrong signer identity'
    Rejected {Invoke-OfficialPayloadFixture -BadHash} 'official payload resolver accepted download evidence that disagreed with the staged bytes'
    Rejected {Invoke-OfficialPayloadFixture -LateDownload} 'official payload resolver revived a download completed after the immutable owner cutoff'
    Rejected {Invoke-OfficialPayloadFixture -ExistingDestination} 'official payload resolver overwrote a preexisting destination'

    $powershellDependency=$script:officialDependency;$officialBase=$script:officialBase
    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0;$script:stagedInstallerCalls=[Collections.Generic.List[object]]::new()
    $stagedClock={$script:stagedNow}
    $stagedCompatibility={param($dependency,$deadline)$script:stagedCompatibilityCalls++;if($script:stagedCompatibilityCalls-eq1){[pscustomobject]@{status='Missing';version='';pathSha256='';detail='fixture missing'}}else{[pscustomobject]@{status='Compatible';version='7.4.2';pathSha256=('b'*64);detail='fixture compatible'}}}
    $stagedAuthenticity={param($path,$policy)[pscustomobject]@{status='Valid';signerSubject='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'}}
    $stagedInstaller={
        param($path,$arguments,$timeout,$deadline)
        $start=$script:stagedNow;$script:stagedNow=$script:stagedNow.AddSeconds(10)
        [void]$script:stagedInstallerCalls.Add([pscustomobject]@{path=$path;arguments=@($arguments);timeout=$timeout;deadline=([datetime]$deadline).ToUniversalTime().ToString('o')})
        [pscustomobject]@{outcome='PASS';exitCode=0;startedAtUtc=$start.ToString('o');finishedAtUtc=$script:stagedNow.ToString('o');deadlineUtc=([datetime]$deadline).ToUniversalTime().ToString('o');outputComplete=$true;stdout='must-not-survive';stderr=''}
    }
    $staged=Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $stagedInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock
    Check ([string]$staged.method-ceq'STAGED_OFFICIAL_GITHUB_DIAGNOSTIC'-and@($staged.operations).Count-eq1-and[string]$staged.operations[0].operation-ceq'official-powershell-msi-install') 'staged official acquisition did not publish the exact bounded installer operation'
    Check ((@($script:stagedInstallerCalls[0].arguments)-join'|')-ceq("/i|$([string]$official.localPath)|/qn|/norestart")-and[string]$script:stagedInstallerCalls[0].deadline-ceq'2026-09-06T20:04:00.0000000Z') 'staged official acquisition changed the candidate silent-install arguments or immutable owner deadline'
    Check (-not[bool]$staged.productLifecycleStarted-and-not[bool]$staged.stageMarkerWritten-and($staged|ConvertTo-Json -Depth 12)-notmatch'must-not-survive') 'staged official acquisition fabricated product progress or retained raw native output'

    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0
    $timeoutInstaller={param($p,$a,$t,$d)[pscustomobject]@{outcome='TIMEOUT';exitCode=$null;startedAtUtc=$officialBase.AddSeconds(4).ToString('o');finishedAtUtc=$officialBase.AddSeconds(10).ToString('o');deadlineUtc=([datetime]$d).ToUniversalTime().ToString('o');outputComplete=$true}}
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $timeoutInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock} 'staged official acquisition treated installer timeout as progress'
    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0
    $lateInstaller={param($p,$a,$t,$d)[pscustomobject]@{outcome='PASS';exitCode=0;startedAtUtc=$officialBase.AddSeconds(4).ToString('o');finishedAtUtc=$officialBase.AddMinutes(5).ToString('o');deadlineUtc=([datetime]$d).ToUniversalTime().ToString('o');outputComplete=$true}}
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $lateInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock} 'staged official acquisition retroactively accepted an installer completed after cutoff'
    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0
    $badExitInstaller={param($p,$a,$t,$d)[pscustomobject]@{outcome='NONZERO';exitCode=1603;startedAtUtc=$officialBase.AddSeconds(4).ToString('o');finishedAtUtc=$officialBase.AddSeconds(10).ToString('o');deadlineUtc=([datetime]$d).ToUniversalTime().ToString('o');outputComplete=$true}}
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $badExitInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock} 'staged official acquisition accepted an unapproved MSI exit code'
    $script:stagedNow=$officialBase.AddSeconds(4);$script:stagedCompatibilityCalls=0
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider {param($p,$policy)[pscustomobject]@{status='Valid';signerSubject='CN=Untrusted Fixture'}} -InstallerProvider $stagedInstaller -PowerShellCompatibilityProvider $stagedCompatibility -ClockProvider $stagedClock} 'staged official acquisition accepted a wrong signer at the guest boundary'
    $script:stagedNow=$officialBase.AddSeconds(4)
    Rejected {Invoke-DevFleetCampaignEStagedPowerShellAcquisition -Dependency $powershellDependency -PayloadEvidence $official -PayloadPath ([string]$official.localPath) -OwnerDeadlineUtc $officialBase.AddMinutes(4) -AuthenticityProvider $stagedAuthenticity -InstallerProvider $stagedInstaller -PowerShellCompatibilityProvider {param($d,$deadline)[pscustomobject]@{status='Compatible';version='8.0.0';pathSha256=('b'*64)}} -ClockProvider $stagedClock} 'staged official acquisition preserved a PowerShell version outside the candidate major policy'
} finally {if(Test-Path -LiteralPath $officialFixtureRoot){Remove-Item -LiteralPath $officialFixtureRoot -Recurse -Force}}

$workerFixtureId='campaign-e-inner-'+[guid]::NewGuid().ToString('N')
$workerFixtureRoot=Join-Path (Join-Path 'C:\Users\Public\DevFleet-E2E' $workerFixtureId) 'Prerequisite'
$oldProgramData=$env:ProgramData;$oldFixtureExe=$env:DEVFLEET_E_FIXTURE_EXE
try {
    $fixturePackage=Join-Path $workerFixtureRoot 'candidate-package'
    New-Item -ItemType Directory -Path (Join-Path $fixturePackage 'windows') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixturePackage 'config') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $workerFixtureRoot 'program-data') -Force|Out-Null
    foreach($name in @('VERSION','dependencies.json','Bootstrap-Install.ps1','Install-DevFleet.ps1')){Copy-Item -LiteralPath (Join-Path $root "source\$name") -Destination (Join-Path $fixturePackage $name)}
    Copy-Item -LiteralPath (Join-Path $root 'source\config\devfleet.config.json') -Destination (Join-Path $fixturePackage 'config\devfleet.config.json')
    $fakeCommon=@'
function Assert-PowerShell7 {}
function Assert-Administrator {}
function Set-DevFleetDeadlineContext { param($TransactionDeadlineUtc,$StageName,$StageBudgetSeconds) [pscustomobject]@{StageDeadlineUtc=$TransactionDeadlineUtc} }
function Get-CanonicalDependencyManifest { param($PackageRoot) Get-Content -LiteralPath (Join-Path $PackageRoot 'dependencies.json') -Raw|ConvertFrom-Json }
function Get-DependencyStatus { param($Dependency) if([string]$Dependency.id -eq 'powershell7'){[pscustomobject]@{Status='Compatible';Version='7.4.0';Path=$env:DEVFLEET_E_FIXTURE_EXE;Detail='fixture'}}else{[pscustomobject]@{Status='Compatible';Version='1.15.1';Path=$env:DEVFLEET_E_FIXTURE_EXE;Detail='fixture'}} }
function Get-WingetHealth { [pscustomobject]@{Status='Healthy';Path=$env:DEVFLEET_E_FIXTURE_EXE} }
function Install-WingetPackage { throw 'fixture must preserve compatible dependency' }
function Install-OfficialDependency { throw 'fixture must preserve compatible dependency' }
function Get-ComputerInfo { param($Property) [pscustomobject]@{WindowsProductName='Windows 11 Pro'} }
function Get-WindowsOptionalFeature { param([switch]$Online,$FeatureName) [pscustomobject]@{State='Enabled'} }
function Get-MultipassExe { $env:DEVFLEET_E_FIXTURE_EXE }
function Get-DevFleetOperationMaximumSeconds { param($Name) 30 }
function Invoke-External { param($FilePath,$ArgumentList,$TimeoutSeconds,$DeadlineUtc,[switch]$Capture) $joined=@($ArgumentList)-join' ';if($joined -eq 'get local.driver'){return 'hyperv'};if($joined -eq 'get local.privileged-mounts'){return 'false'};if($joined -eq 'list --format json'){return '{"list":[]}'};if($joined -match '^set '){return ''};throw "unexpected fixture operation: $joined" }
function Get-CimInstance { param($ClassName) @() }
function Get-DevFleetPendingRebootSnapshot { [pscustomobject]@{CbsPending=$false;WindowsUpdatePending=$false;PendingPairs=@()} }
Export-ModuleMember -Function *
'@
    $fakeCommon|Set-Content -LiteralPath (Join-Path $fixturePackage 'windows\DevFleet.Common.psm1') -Encoding UTF8
    $fixtureModule=Join-Path $workerFixtureRoot 'MultipassDiagnostic.psm1';Copy-Item -LiteralPath $modulePath -Destination $fixtureModule
    $fixturePlan=Get-DevFleetCampaignEPrerequisitePlan -PackageRoot $fixturePackage -Role Desktop
    $fixtureResult=Join-Path $workerFixtureRoot 'prerequisite-result.json'
    $env:ProgramData=Join-Path $workerFixtureRoot 'program-data'
    $env:DEVFLEET_E_FIXTURE_EXE=(Get-Process -Id $PID).Path
    $request=[ordered]@{runId='unit-inner';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';remoteRoot=$workerFixtureRoot;packageRoot=$fixturePackage;diagnosticModulePath=$fixtureModule;resultPath=$fixtureResult;role='Desktop';payloadSha256=('a'*64);inputHashes=$fixturePlan.inputHashes;ownerDeadlineUnixMilliseconds=[DateTimeOffset]::UtcNow.AddMinutes(2).ToUnixTimeMilliseconds();pendingRebootBaseline=[ordered]@{CbsPending=$false;WindowsUpdatePending=$false;PendingPairs=@()}}|ConvertTo-Json -Depth 8 -Compress
    $requestBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))
    & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'automation\release-e2e\Invoke-CampaignEPrerequisitePwshWorker.ps1') -RequestBase64 $requestBase64
    Check ($LASTEXITCODE-eq0-and(Test-Path -LiteralPath $fixtureResult -PathType Leaf)) 'actual PowerShell prerequisite worker did not complete the safe compatible-dependency fixture'
    $fixtureValue=Get-Content -LiteralPath $fixtureResult -Raw|ConvertFrom-Json
    Check ([string]$fixtureValue.kind-ceq'DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY'-and-not[bool]$fixtureValue.productLifecycleStarted-and[int]$fixtureValue.stageMarkerCount-eq0-and[int]$fixtureValue.backend.inventoryCount-eq0) 'actual PowerShell prerequisite worker fabricated product state or lost the empty backend contract'
} finally {
    $env:ProgramData=$oldProgramData;$env:DEVFLEET_E_FIXTURE_EXE=$oldFixtureExe
    $workerFixtureParent=Split-Path -Parent $workerFixtureRoot
    if(Test-Path -LiteralPath $workerFixtureParent){Remove-Item -LiteralPath $workerFixtureParent -Recurse -Force}
}

$fixtureId='campaign-e-prereq-'+[guid]::NewGuid().ToString('N')
$fixtureRoot=Join-Path 'C:\Users\Public\DevFleet-E2E' $fixtureId
$fixturePrereq=Join-Path $fixtureRoot 'Prerequisite'
try {
    New-Item -ItemType Directory -Path $fixturePrereq -Force|Out-Null
    $stubPath=Join-Path $fixturePrereq 'Install-DevFleet.ps1'
    Get-DevFleetCampaignEBootstrapStubContent|Set-Content -LiteralPath $stubPath -Encoding UTF8
    $ack=Join-Path $fixturePrereq 'bootstrap-ack.json'
    $oldAck=$env:DEVFLEET_E_BOOTSTRAP_ACK;$oldRun=$env:DEVFLEET_E_RUN_ID
    $env:DEVFLEET_E_BOOTSTRAP_ACK=$ack;$env:DEVFLEET_E_RUN_ID='unit-prereq'
    try {& $stubPath -Role Desktop -InstallationMode Connected -PackageRoot 'C:\candidate' -NonInteractive -SkipWindowsUpdates -DeferNetworkPairing -AcknowledgeRootfulDocker -TransactionDeadlineUtc ([datetime]::UtcNow.AddMinutes(1).ToString('o'))} finally {$env:DEVFLEET_E_BOOTSTRAP_ACK=$oldAck;$env:DEVFLEET_E_RUN_ID=$oldRun}
    $ackValue=Get-Content -LiteralPath $ack -Raw|ConvertFrom-Json
    Check ([string]$ackValue.kind-ceq'CAMPAIGN_E_POWERSHELL_BOOTSTRAP_ONLY'-and-not[bool]$ackValue.productLifecycleStarted-and-not[bool]$ackValue.stageMarkerWritten) 'bootstrap-only acknowledgement fabricated product lifecycle state'
    $env:DEVFLEET_E_BOOTSTRAP_ACK=$ack;$env:DEVFLEET_E_RUN_ID='unit-prereq'
    $transactionRejected=$false
    try {& $stubPath -Role Desktop -InstallationMode Connected -PackageRoot 'C:\candidate' -TransactionId ('a'*32)} catch {$transactionRejected=$_.Exception.Message-match'transactionless'} finally {$env:DEVFLEET_E_BOOTSTRAP_ACK=$oldAck;$env:DEVFLEET_E_RUN_ID=$oldRun}
    Check $transactionRejected 'bootstrap-only shim accepted a product transaction or rejected it for the wrong boundary'
} finally {
    if(Test-Path -LiteralPath $fixtureRoot){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force}
}

$base=[datetime]'2026-09-06T20:00:00Z'
$valid=[pscustomobject][ordered]@{
    schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_READY';status='PASS';runId='unit-prereq';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64)
    role='Desktop';packageVersion='1.2.13';ownerDeadlineUtc=$base.AddMinutes(10).ToString('o');startedAtUtc=$base.ToString('o');producedAtUtc=$base.AddMinutes(5).ToString('o');inputHashes=$plan.inputHashes
    systemPolicyChanged=$false;productLifecycleStarted=$false;activeTransactionPresent=$false;stageMarkerCount=0;activeInstallProcessCount=0;pendingReboot=$false
    powershell=[ordered]@{status='Compatible';version='7.4.0';pathSha256=('b'*64)};multipass=[ordered]@{status='Compatible';version='1.15.1';pathSha256=('c'*64);preexisting=$false}
    powershellAcquisition=[ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='PRESERVED_CANDIDATE_COMPATIBLE';packageId='Microsoft.PowerShell';startedAtUtc=$base.ToString('o');finishedAtUtc=$base.AddMinutes(1).ToString('o');ownerDeadlineUtc=$base.AddMinutes(10).ToString('o');wingetPathSha256='';operations=@();powershell=[ordered]@{status='Compatible';version='7.4.0';pathSha256=('b'*64)};productLifecycleStarted=$false;stageMarkerWritten=$false}
    backend=[ordered]@{driver='hyperv';privilegedMounts=$false;inventoryCount=0};l2Status='ABSENT'
}
Check (Assert-DevFleetCampaignEPrerequisiteResult -Result $valid -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan) 'valid prerequisite result was rejected'
$stagedValid=Clone $valid
$stagedValid.powershellAcquisition=[pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_POWERSHELL_ACQUISITION';status='PASS';method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId='Microsoft.PowerShell';startedAtUtc=$base.AddSeconds(5).ToString('o');finishedAtUtc=$base.AddMinutes(1).ToString('o');ownerDeadlineUtc=$base.AddMinutes(10).ToString('o');wingetPathSha256='';officialPayload=[ordered]@{releaseTag='v7.4.2';assetName='PowerShell-7.4.2-win-x64.msi';sha256=('e'*64);bytes=42;signerSubject='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'};operations=@([ordered]@{operation='official-powershell-msi-install';outcome='PASS';exitCode=0;startedAtUtc=$base.AddSeconds(10).ToString('o');finishedAtUtc=$base.AddSeconds(20).ToString('o');deadlineUtc=$base.AddMinutes(10).ToString('o');outputComplete=$true;packageIdentityObserved=$true});powershell=[ordered]@{status='Compatible';version='7.4.0';pathSha256=('b'*64)};productLifecycleStarted=$false;stageMarkerWritten=$false}
Check (Assert-DevFleetCampaignEPrerequisiteResult -Result $stagedValid -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan) 'valid staged-official prerequisite result was rejected'
$stagedWrongSigner=Clone $stagedValid;$stagedWrongSigner.powershellAcquisition.officialPayload.signerSubject='CN=Untrusted Fixture'
Rejected {Assert-DevFleetCampaignEPrerequisiteResult -Result $stagedWrongSigner -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan} 'staged-official result validator accepted the wrong signer'
$stagedWrongOperation=Clone $stagedValid;$stagedWrongOperation.powershellAcquisition.operations[0].operation='arbitrary-install'
Rejected {Assert-DevFleetCampaignEPrerequisiteResult -Result $stagedWrongOperation -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan} 'staged-official result validator accepted the wrong operation identity'

$failureOperations=[Collections.Generic.List[object]]::new()
for($index=0;$index-lt4;$index++){
    $operationName=@('winget-version','winget-source-list','winget-source-update','winget-powershell-search')[$index]
    [void]$failureOperations.Add([pscustomobject][ordered]@{operation=$operationName;outcome=if($index-eq3){'NONZERO'}else{'PASS'};exitCode=if($index-eq3){-1978335217}else{0};pid=100+$index;startedAtUtc=$base.AddSeconds($index*10).ToString('o');finishedAtUtc=$base.AddSeconds(($index+1)*10).ToString('o');deadlineUtc=$base.AddMinutes(2).ToString('o');outputComplete=$true})
}
$validFailure=[pscustomobject][ordered]@{schemaVersion=1;kind='DEVFLEET_CAMPAIGN_E_PREREQUISITE_FAILURE';status='BLOCKED';runId='unit-prereq';vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);producedAtUtc=$base.AddMinutes(1).ToString('o');ownerDeadlineUtc=$base.AddMinutes(10).ToString('o');primaryError='WinGet source data missing.';powershellAcquisition=[ordered]@{status='BLOCKED';identity=[ordered]@{method='WINGET_MANIFEST_APPROVED_DIAGNOSTIC';packageId='Microsoft.PowerShell';wingetPathSha256=('d'*64);ownerDeadlineUtc=$base.AddMinutes(10).ToString('o')};operations=@($failureOperations);productLifecycleStarted=$false;stageMarkerWritten=$false}}
Check (Assert-DevFleetCampaignEPrerequisiteFailure -Failure $validFailure -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64)) 'valid run-bound prerequisite failure was rejected'
$stagedFailure=Clone $validFailure
$stagedFailure.primaryError='Official PowerShell MSI failed.'
$stagedFailure.powershellAcquisition.identity=[pscustomobject][ordered]@{method='STAGED_OFFICIAL_GITHUB_DIAGNOSTIC';packageId='Microsoft.PowerShell';payloadSha256=('e'*64);assetName='PowerShell-7.4.2-win-x64.msi';ownerDeadlineUtc=$base.AddMinutes(10).ToString('o')}
$stagedFailure.powershellAcquisition.operations=@([pscustomobject][ordered]@{operation='official-powershell-msi-install';outcome='NONZERO';exitCode=1603;pid=200;startedAtUtc=$base.AddSeconds(10).ToString('o');finishedAtUtc=$base.AddSeconds(20).ToString('o');deadlineUtc=$base.AddMinutes(2).ToString('o');outputComplete=$true})
Check (Assert-DevFleetCampaignEPrerequisiteFailure -Failure $stagedFailure -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64)) 'valid staged-official failure evidence was rejected'
$stagedFailureWrongAsset=Clone $stagedFailure;$stagedFailureWrongAsset.powershellAcquisition.identity.assetName='arbitrary.msi'
Rejected {Assert-DevFleetCampaignEPrerequisiteFailure -Failure $stagedFailureWrongAsset -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64)} 'staged-official failure validator accepted an arbitrary payload identity'
foreach($case in @(
    @{name='failure wrong run';edit={param($v)$v.runId='wrong'}},
    @{name='failure late publication';edit={param($v)$v.producedAtUtc=$base.AddMinutes(11).ToString('o')}},
    @{name='failure product progress';edit={param($v)$v.powershellAcquisition.productLifecycleStarted=$true}},
    @{name='failure wrong operation sequence';edit={param($v)$v.powershellAcquisition.operations[2].operation='winget-powershell-search'}},
    @{name='failure wrong package identity';edit={param($v)$v.powershellAcquisition.identity.packageId='Arbitrary.PowerShell'}},
    @{name='failure missing executable hash';edit={param($v)$v.powershellAcquisition.identity.wingetPathSha256=''}}
)){
    $badFailure=Clone $validFailure;&$case.edit $badFailure
    Rejected {Assert-DevFleetCampaignEPrerequisiteFailure -Failure $badFailure -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64)} "$($case.name) was accepted"
}

foreach($case in @(
    @{name='late result';edit={param($v)$v.producedAtUtc=$base.AddMinutes(11).ToString('o')}},
    @{name='wrong run';edit={param($v)$v.runId='wrong'}},
    @{name='wrong VM';edit={param($v)$v.vmId=[guid]::NewGuid().ToString()}},
    @{name='wrong payload';edit={param($v)$v.payloadSha256=('d'*64)}},
    @{name='wrong candidate hash';edit={param($v)$v.inputHashes.config=('e'*64)}},
    @{name='system policy mutation';edit={param($v)$v.systemPolicyChanged=$true}},
    @{name='product lifecycle start';edit={param($v)$v.productLifecycleStarted=$true}},
    @{name='active transaction';edit={param($v)$v.activeTransactionPresent=$true}},
    @{name='stage marker';edit={param($v)$v.stageMarkerCount=1}},
    @{name='active installer';edit={param($v)$v.activeInstallProcessCount=1}},
    @{name='pending reboot';edit={param($v)$v.pendingReboot=$true}},
    @{name='incompatible PowerShell';edit={param($v)$v.powershell.status='Outdated'}},
    @{name='missing PowerShell acquisition';edit={param($v)$v.powershellAcquisition=$null}},
    @{name='mismatched PowerShell acquisition';edit={param($v)$v.powershellAcquisition.powershell.pathSha256=('d'*64)}},
    @{name='late PowerShell acquisition';edit={param($v)$v.powershellAcquisition.finishedAtUtc=$base.AddMinutes(11).ToString('o')}},
    @{name='unsupported PowerShell acquisition';edit={param($v)$v.powershellAcquisition.method='DIRECT_UNVERIFIED'}},
    @{name='incompatible Multipass';edit={param($v)$v.multipass.version='1.12.9'}},
    @{name='wrong backend';edit={param($v)$v.backend.driver='virtualbox'}},
    @{name='privileged mounts';edit={param($v)$v.backend.privilegedMounts=$true}},
    @{name='nonempty inventory';edit={param($v)$v.backend.inventoryCount=1}},
    @{name='unverified L2';edit={param($v)$v.l2Status='UNVERIFIED'}}
)){
    $bad=Clone $valid;&$case.edit $bad
    Rejected {Assert-DevFleetCampaignEPrerequisiteResult -Result $bad -ExpectedRunId 'unit-prereq' -ExpectedVmId ([guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2') -ExpectedPayloadSha256 ('a'*64) -ExpectedPlan $plan} "$($case.name) was accepted"
}

$shell=(Get-Process -Id $PID).Path
$probe=Invoke-DevFleetBoundedNativeProbe -Operation 'large-output-fixture' -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-Command',"[Console]::Out.Write(('x'*5000))") -TimeoutSeconds 10 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(15)) -MaxStdoutCharacters 600
Check ([string]$probe.outcome-ceq'PASS'-and[bool]$probe.stdoutTruncated-and[string]$probe.stdout.Length-eq600) 'bounded native collector did not honor the explicit diagnostic output cap'

foreach($script in @('Invoke-CampaignEPrerequisiteWorker.ps1','Invoke-CampaignEPrerequisitePwshWorker.ps1','Invoke-CampaignEPrerequisiteCheckpoint.ps1')){
    $errors=$null;$tokens=$null
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $root "automation\release-e2e\$script"),[ref]$tokens,[ref]$errors)|Out-Null
    Check ($errors.Count-eq0) "$script has parser errors"
}

Write-Host "PASS $count Campaign E prerequisite/checkpoint behavioral checks"
