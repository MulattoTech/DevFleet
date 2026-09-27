# DevFleet source part 040

Full-source UTF-8 byte interval [1813500, 1860000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ada0c0e9a3b04d8a9db391b551771a38a84896dfa7c5d9ccb998a8a75dfb9ac5

<!-- BEGIN SOURCE SLICE -->
reEnabled=$true;SecondLevelAddressTranslationExtensions=$true}}
        default {throw 'Unexpected machine query.'}
    }
}
function Get-PSDrive {param($Name)[pscustomobject]@{Free=if($env:DEVFLEET_PROFILE_FIXTURE-ceq'low-disk'){1GB}else{200GB}}}
function Get-ComputerInfo {param($Property)[pscustomobject]@{WindowsProductName='Windows 11 Pro'}}
function Get-Process {param($Name) @()}
function Assert-Administrator {}
'@
try {
    foreach($case in @('success','bad-input-hash','bad-owner','active-transaction','low-disk','expired-owner','m3-success','m3-bad-template','m3-bad-name')){
        $run=$runPrefix+'-'+$case;$parent=[IO.Path]::GetFullPath("C:\Users\Public\DevFleet-E2E\$run");$remote=Join-Path $parent 'M1';$owned.Add($parent)
        New-Item -ItemType Directory -Path (Join-Path $remote 'profile-package/windows'),(Join-Path $remote 'profile-package/config'),(Join-Path $parent 'real-data/DevFleet')|Out-Null
        $nonce=[guid]::NewGuid();@{kind='DEVFLEET_CAMPAIGN_E_STAGING_OWNER';runId=$run;nonce=$nonce.ToString()}|ConvertTo-Json|Set-Content (Join-Path $remote '.owner.json')
        Copy-Item (Join-Path $root 'source/windows/00-Preflight.ps1') (Join-Path $remote 'profile-package/windows/00-Preflight.ps1')
        Copy-Item (Join-Path $root 'source/config/devfleet.config.json') (Join-Path $remote 'profile-package/config/devfleet.config.json')
        [IO.File]::WriteAllText((Join-Path $remote 'profile-package/windows/DevFleet.Common.psm1'),([IO.File]::ReadAllText((Join-Path $root 'source/windows/DevFleet.Common.psm1'))+[Environment]::NewLine+$machine+[Environment]::NewLine+'Export-ModuleMember -Function *'),[Text.UTF8Encoding]::new($false))
        $inputs=@(foreach($relative in @('windows/00-Preflight.ps1','windows/DevFleet.Common.psm1','config/devfleet.config.json')){@{path=$relative;sha256=(Get-FileHash (Join-Path $remote ('profile-package/'+$relative)) -Algorithm SHA256).Hash.ToLowerInvariant()}})
        $productLaunch=$case-like'm3-*'
        if($productLaunch){
            New-Item -ItemType Directory -Path (Join-Path $remote 'profile-package/cloud-init')|Out-Null
            Copy-Item (Join-Path $root 'source/cloud-init/compute.yaml') (Join-Path $remote 'profile-package/cloud-init/compute.yaml')
            $inputs+=@{path='cloud-init/compute.yaml';sha256=if($case-ceq'm3-bad-template'){'f'*64}else{(Get-FileHash (Join-Path $remote 'profile-package/cloud-init/compute.yaml') -Algorithm SHA256).Hash.ToLowerInvariant()}}
        }
        $deadline=[datetime]::UtcNow.AddSeconds(20);if($case-ceq'expired-owner'){$deadline=[datetime]::UtcNow.AddSeconds(-1)}
        if($case-ceq'bad-input-hash'){$inputs[0].sha256='f'*64}
        if($case-ceq'active-transaction'){'{}'|Set-Content (Join-Path $parent 'real-data/DevFleet/active-transaction.json')}
        $request=@{runId=$run;vmId='84b7d8b8-ee6c-4085-aa29-4b0adc316de2';payloadSha256=('a'*64);remoteRoot=$remote;inputs=$inputs;stagingNonce=if($case-ceq'bad-owner'){[guid]::NewGuid().ToString()}else{$nonce.ToString()};deadlineUnixMilliseconds=[DateTimeOffset]::new($deadline).ToUnixTimeMilliseconds()}
        if($productLaunch){$request.productLaunch=$true;$request.instanceName=if($case-ceq'm3-bad-name'){'devfleet-primary'}else{"DevFleet-E2E-E-M1-$run"}}
        $entry=Join-Path $parent 'entry.ps1';$entryBody=@'
param($Worker,$Request,$Data,$Case)
$env:ProgramData=$Data;$env:DEVFLEET_PROFILE_FIXTURE=$Case
'@
        [IO.File]::WriteAllText($entry,($entryBody+[Environment]::NewLine+$machine+[Environment]::NewLine+'& $Worker -RequestBase64 $Request; exit $LASTEXITCODE'),[Text.UTF8Encoding]::new($false))
        $base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json -Depth 5 -Compress)))
        $probe=Invoke-DevFleetBoundedNativeProbe -Operation "profile-$case" -FilePath $engine -ArgumentList @('-NoProfile','-File',$entry,'-Worker',$worker,'-Request',$base64,'-Data',(Join-Path $parent 'real-data'),'-Case',$case) -TimeoutSeconds 15 -OwnerDeadlineUtc ([datetime]::UtcNow.AddSeconds(20)) -ForceLegacyArgumentString -MaxStdoutCharacters 32768
        $path=Join-Path $remote 'product-profile.json';$profile=if(Test-Path $path){Get-Content $path -Raw|ConvertFrom-Json}else{$probe.stdout|ConvertFrom-Json}
        $pass=$true
        if($case-cin@('success','m3-success')){
            $pass=$probe.exitCode-eq0-and$profile.status-ceq'PASS_PROFILE_ONLY'-and[int]$profile.resources.cpus-eq4-and$profile.resources.memory-ceq'9G'-and$profile.resources.disk-ceq'220G'-and$profile.ubuntuImage-ceq'24.04'
            Assert-DevFleetCampaignEProductProfile -Profile $profile -ExpectedRunId $run -ExpectedVmId ([guid]$request.vmId) -ExpectedPayloadSha256 $request.payloadSha256 -ExpectedInputs $inputs -DeadlineUtc $deadline -ExpectedProductLaunch:$productLaunch|Out-Null
            if($productLaunch){
                $cloud=Join-Path $remote 'product-cloud-init.yaml';$rendered=Get-Content $cloud -Raw
                $pass=$pass-and(Get-FileHash $cloud -Algorithm SHA256).Hash.ToLowerInvariant()-ceq$profile.productLaunch.cloudInitSha256-and$rendered-match([regex]::Escape($request.instanceName))-and$rendered-notmatch'__(NODE|GIT)_'-and$rendered-match'package_update: true'
                $plainRejected=$false;try{Assert-DevFleetCampaignEProductProfile -Profile $profile -ExpectedRunId $run -ExpectedVmId ([guid]$request.vmId) -ExpectedPayloadSha256 $request.payloadSha256 -ExpectedInputs $inputs -DeadlineUtc $deadline|Out-Null}catch{$plainRejected=$true};$pass=$pass-and$plainRejected
            }
        }else{$pass=$probe.exitCode-eq1-and$profile.status-ceq'BLOCKED'-and-not[string]::IsNullOrWhiteSpace([string]$profile.primaryError)}
        $pass=$pass-and-not(Test-Path (Join-Path $parent 'real-data/DevFleet/devfleet.config.json'))-and-not[bool]$profile.productLifecycleStarted
        $results.Add([pscustomobject]@{case=$case;pass=[bool]$pass;exitCode=$probe.exitCode;error=$profile.primaryError})
    }
}finally{
    foreach($path in $owned){if(-not$path.StartsWith('C:\Users\Public\DevFleet-E2E\'+$runPrefix,[StringComparison]::Ordinal)){throw 'Profile fixture cleanup escaped ownership.'};if(Test-Path $path){Remove-Item -LiteralPath $path -Recurse -Force}}
}
$results|ConvertTo-Json -Depth 3
if(@($results|Where-Object{-not$_.pass}).Count){throw 'Actual candidate preflight profile regression failed.'}
Write-Host "PASS $($results.Count)/$($results.Count) actual candidate preflight profile checks"

```


## FILE: automation/release-e2e/tests/Test-CorrectionInventoryOrdering.ps1

SHA256: 6e08106c7206116380d5d0250571542c07dca5bf7cd50ec001808273ecf65067 | Bytes: 985 | Git mode: 100644

```
param([string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $WorkspaceRoot 'installer-source/Build-Release.ps1') -Raw
$start=$source.IndexOf('  [string[]]$authorizedPaths=@(')
$end=$source.IndexOf('  foreach($authorizedPath', $start)
if($start-lt0-or$end-le$start){throw 'Native correction path construction was not found.'}
$priorState=[pscustomobject]@{authorized_correction=[pscustomobject]@{shipping_paths=@('source/app/z.py','source/CHECKSUMS.sha256','installer-source/Build-Release.ps1','source/app/z.py')}}
. ([scriptblock]::Create($source.Substring($start,$end-$start)))
if(($authorizedPaths-join ',')-cne'installer-source/Build-Release.ps1,source/CHECKSUMS.sha256,source/app/z.py'){throw 'Native correction inventory is not unique and ordinal-sorted.'}
[ordered]@{status='PASS';realNativeConstruction=$true;buildInvoked=$false;runtime=$PSVersionTable.PSVersion.ToString()}|ConvertTo-Json

```


## FILE: automation/release-e2e/tests/Test-CurrentGuestEvidenceChronology.ps1

SHA256: 84413a82f99a4bb017e4e43e2a074845f5fe14f676e78bb02b0e0f806605a0f0 | Bytes: 4796 | Git mode: 100644

```
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
# Exercise the unchanged production evidence-building body, replacing only OS/guest I/O.
# Host identity/admission checks are covered elsewhere; this is never lab admission.
$workspace=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$path=Join-Path $workspace '.agents/skills/devfleet-certification-orchestrator/scripts/Test-CurrentGuestAccess.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Production collector parse failure'}
$statements=@($ast.EndBlock.Statements)
$start=@($statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -ceq '$result'})[0]
$finish=@($statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[-1]
if(-not $start -or -not $finish){throw 'Production evidence-body boundary missing'}
$body=[scriptblock]::Create(($statements|Where-Object {$_.Extent.StartOffset -ge $start.Extent.StartOffset -and $_.Extent.EndOffset -le $finish.Extent.EndOffset}|ForEach-Object {$_.Extent.Text}) -join "`n")
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-guest-evidence-'+[guid]::NewGuid().ToString('N'))
$oldAppData=$env:LOCALAPPDATA
$passes=0
function Assert-That([bool]$ok,[string]$message){if(-not $ok){throw $message};$script:passes++}
try {
 New-Item -ItemType Directory -Path (Join-Path $fixture 'DevFleet/E2E') -Force|Out-Null
 $env:LOCALAPPDATA=$fixture
 [IO.File]::WriteAllText((Join-Path $fixture 'DevFleet/E2E/secrets.json'),'TEST METADATA ONLY - NOT A CREDENTIAL')
 $mockSecrets=New-Module -Name Secrets -ScriptBlock {function Get-DevFleetE2ECredential {[pscustomobject]@{UserName='E2EAdmin'}};Export-ModuleMember -Function Get-DevFleetE2ECredential}
 Import-Module $mockSecrets -Force
 $RunId='r2-fixture-chronology';$vmId=[guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
 $vm=[pscustomobject]@{Name='DevFleet-E2E-Win11-01';Id=$vmId}
 $fingerprint=[pscustomobject]@{repositoryHead=('1'*40);gitCommit=('2'*40);shippingInputIdentity=('3'*64);releaseFingerprintId=('4'*64);toolingFingerprintId=('5'*64);candidate=[pscustomobject]@{sha256=('6'*64)}}
 $script:removed=0;$script:failOpen=$false
 function New-PSSession {param($VMId,$Credential,$ErrorAction) if($script:failOpen){throw 'Synthetic guest transport failure'};[pscustomobject]@{InstanceId='fixture'}}
 function Remove-PSSession {param($Session,$ErrorAction) $script:removed++}
 function Invoke-Command {param($Session,$ScriptBlock) [pscustomobject]@{computerName='DEVFLEET-E2E-01';principal='DEVFLEET-E2E-01\E2EAdmin';accountEnabled=$true;passwordLastSetUtc=[datetimeoffset]::UtcNow.AddMinutes(-20).ToString('o');passwordExpiresUtc=[datetimeoffset]::UtcNow.AddDays(30).ToString('o')}}
 function Get-DevFleetNestedL2State {param($Session,$ExpectedName)
  Start-Sleep -Milliseconds 30
  [pscustomobject]@{status='ABSENT';present=$false;expectedName=$ExpectedName;verification='SYNTHETIC TEST ONLY';observedUtc=[datetimeoffset]::UtcNow.ToString('o');exactMatchCount=0;backendInventories=@([pscustomobject]@{provider='Hyper-V';status='PASS';names=@();verification='SYNTHETIC'},[pscustomobject]@{provider='VirtualBox';status='PASS';names=@();verification='SYNTHETIC'})}
 }
 . $body
 Assert-That ($result.status -ceq 'AUTHENTICATED_CURRENT_GUEST_NOT_CLEAN_PROOF') 'Fixture failed before chronology assertion'
 if($OutputPath){[IO.File]::WriteAllText($OutputPath,($result|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
 Assert-That ([datetimeoffset]$result.observedUtc -ge [datetimeoffset]$result.nestedL2.observedUtc) 'Report observedUtc precedes collected nested inventory: adoption will reject it'
 Assert-That ($script:removed -eq 1) 'Collector did not close its fixture session'
 Assert-That ($result.certificationCredit -eq $false -and $result.vmMutationPerformed -eq $false) 'Diagnostic claimed certification/mutation'
 $script:failOpen=$true
 . $body
 Assert-That ($result.status -ceq 'BLOCKED' -and -not $result.connected) 'Transport failure did not stay blocked'
 Assert-That ($null -eq $result.nestedL2 -and $null -eq $result.guest) 'Failure invented guest evidence'
 Assert-That (-not [string]::IsNullOrWhiteSpace($result.observedUtc)) 'Failure lost observation timestamp'
 Assert-That ($script:removed -eq 1) 'Failure tried to close a nonexistent session'
 [pscustomobject]@{status='PASS';assertions=$passes;vmOperations=0;realCredentialReads=0;scope='PRODUCTION_EVIDENCE_BODY_WITH_MOCKED_OS_IO'}|ConvertTo-Json -Compress
} finally {
 $env:LOCALAPPDATA=$oldAppData
 if($mockSecrets){Remove-Module $mockSecrets -ErrorAction SilentlyContinue}
 Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: automation/release-e2e/tests/Test-ExactProofBinding.ps1

SHA256: 8b6a0d30dd1c1c81a7b50e47f9e731bb82e3505c796e4e2c89e7facbe9944aa4 | Bytes: 6294 | Git mode: 100644

```
[CmdletBinding()]
param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if(-not $WorkspaceRoot){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
Import-Module (Join-Path $WorkspaceRoot 'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('devfleet-proof-binding-'+[guid]::NewGuid().ToString('N'))
$passed=0;$failed=[Collections.Generic.List[string]]::new()
function Check([bool]$Value,[string]$Name){if($Value){$script:passed++}else{[void]$script:failed.Add($Name)}}
function WriteJson($Path,$Value){$Value|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path -Encoding utf8NoBOM}
try{
    New-Item -ItemType Directory -Path (Join-Path $root 'source/config') -Force|Out-Null
    $configPath=Join-Path $root 'source/config/devfleet.config.json'
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'source/config/devfleet.config.json') -Destination $configPath
    $configHash=(Get-FileHash -LiteralPath $configPath).Hash.ToLowerInvariant()
    WriteJson (Join-Path $root 'CURRENT-CANDIDATE.json') ([ordered]@{candidateIsCurrent=$true;sourceChangedSinceCandidate=$false;rebuildRequired=$false;shippingInputIdentity=('c'*64);candidateShippingInputIdentity=('c'*64);candidateGitCommit=('d'*40);candidateShippingInputs=@(@{root='source';path='config/devfleet.config.json';sha256=$configHash})})
    function NewFixture([string]$Role){
        $phase=if($Role -ceq 'Laptop / Surrogate'){'SURROGATE-DISPOSABLE'}else{'REBOOT-RESUME'}
        $run=Join-Path $root ([guid]::NewGuid().ToString('N'));$tx=[guid]::NewGuid().ToString('N');$lineage=[guid]::NewGuid().ToString('N');$payload='b'*64
        $life=Join-Path $run "lifecycle-$phase-$lineage";New-Item -ItemType Directory -Path $life -Force|Out-Null
        $targets=if($Role -ceq 'Laptop / Surrogate'){@(@{instanceName='devfleet-failover';nodeRole='surrogate';kind='compute'},@{instanceName='devfleet-vault';nodeRole='vault';kind='vault'})}else{@(@{instanceName='devfleet-primary';nodeRole='primary';kind='compute'})}
        $markers=@(foreach($target in $targets){@{instanceName=$target.instanceName;nodeRole=$target.nodeRole;marker=@{transactionId=$tx;payloadSha256=$payload;nodeRole=$target.nodeRole;component='bootstrap';state='COMPLETED'}}})
        $generation=@{generation=1;invocationId=$lineage;reboot=@{checkpoint=@{transactionId=$tx;payloadSha256=$payload;role=$Role;action='FreshInstall'};bootIdentityChanged=$true};resume=@{status='REAL E2E OBSERVER HANDOFF'}}
        $generationPath=Join-Path $life 'product-lifecycle-generation-1.json';WriteJson $generationPath $generation
        $authorityPath=Join-Path $life 'product-lifecycle-completion-authority.json'
        $authority=@{status='REAL E2E PASS';contract='product-lifecycle-completion-authority';completionVerified=$true;authenticatedHealth=$true;role=$Role;transactionId=$tx;invocationId=$lineage;payloadSha256=$payload;evidencePath=$authorityPath;guest=@{completionVerified=$true;transactionId=$tx;role=$Role;roleEvidence=@{requiredTargets=$targets;configSha256=$configHash;markers=$markers}};evidenceReferences=@(@{kind='lifecycle-generation';path=$generationPath;sha256=(Get-FileHash -LiteralPath $generationPath).Hash.ToLowerInvariant()})}
        WriteJson $authorityPath $authority
        return @{context=[pscustomobject]@{workspaceRoot=$root;runDir=$run;candidate=@{tar=@{sha256=$payload}}};phase=@{status='REAL E2E PASS';phase=$phase;product=$authority};authority=$authority;generation=$generation;generationPath=$generationPath;role=$Role}
    }
    foreach($role in @('Primary / Desktop','Laptop / Surrogate')){
        $fixture=NewFixture $role
        $binding=New-DevFleetExactProofBinding -Context $fixture.context -PhaseResult $fixture.phase -ExpectedRole $role
        Check ($binding.transactionId -ceq $fixture.authority.transactionId -and $binding.checkpointLineageId -ceq $fixture.authority.invocationId -and $binding.evidence.Count -eq 2) "$role uses durable product transaction, lineage and reboot records"
    }
    $cases=@{
        'missing Vault'={param($f)$f.authority.guest.roleEvidence.markers=@($f.authority.guest.roleEvidence.markers[0])}
        'foreign marker transaction'={param($f)$f.authority.guest.roleEvidence.markers[1].marker.transactionId='e'*32}
        'unfinished Vault'={param($f)$f.authority.guest.roleEvidence.markers[1].marker.state='STARTED'}
        'duplicate target'={param($f)$f.authority.guest.roleEvidence.requiredTargets[1]=$f.authority.guest.roleEvidence.requiredTargets[0]}
        'wrong role'={param($f)$f.authority.role='Primary / Desktop'}
        'wrong payload'={param($f)$f.authority.payloadSha256='e'*64}
        'missing reboot'={param($f)$f.authority.evidenceReferences=@()}
        'unchanged boot'={param($f)$f.generation.reboot.bootIdentityChanged=$false;WriteJson $f.generationPath $f.generation;$f.authority.evidenceReferences[0].sha256=(Get-FileHash -LiteralPath $f.generationPath).Hash.ToLowerInvariant()}
        'foreign checkpoint'={param($f)$f.generation.reboot.checkpoint.transactionId='e'*32;WriteJson $f.generationPath $f.generation;$f.authority.evidenceReferences[0].sha256=(Get-FileHash -LiteralPath $f.generationPath).Hash.ToLowerInvariant()}
        'generation hash drift'={param($f)$f.authority.evidenceReferences[0].sha256='e'*64}
    }
    foreach($case in $cases.GetEnumerator()){
        $fixture=NewFixture 'Laptop / Surrogate';& $case.Value $fixture;WriteJson $fixture.authority.evidencePath $fixture.authority
        $rejected=$false;try{New-DevFleetExactProofBinding -Context $fixture.context -PhaseResult $fixture.phase -ExpectedRole $fixture.role|Out-Null}catch{$rejected=$true}
        Check $rejected "rejects $($case.Key)"
    }
    [ordered]@{status=if($failed.Count){'FAIL'}else{'PASS'};passed=$passed;failures=@($failed)}|ConvertTo-Json
    if($failed.Count){exit 1}
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^devfleet-proof-binding-[a-f0-9]{32}$'){throw 'Proof fixture cleanup path rejected.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}

```


## FILE: automation/release-e2e/tests/Test-FinalConvergenceContracts.ps1

SHA256: 557e3f91c90bec1382730eeb603afccb0b77bbaf97478fa9d5afa44bf24801a5 | Bytes: 2859 | Git mode: 100644

```
[CmdletBinding()]
param([string]$Workspace = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
$finalizer = Get-Content -LiteralPath (Join-Path $Workspace 'tools\Invoke-DevFleetFinalConvergence.ps1') -Raw
$builder = Get-Content -LiteralPath (Join-Path $Workspace 'tools\Build-AIAuditBundle.ps1') -Raw
$entrypoint = Get-Content -LiteralPath (Join-Path $Workspace 'automation\release-e2e\Invoke-DevFleetReleaseE2E.ps1') -Raw
$checks = [ordered]@{
    proofExceptionHasFinally = ($finalizer -match 'StageScript' -and $finalizer -match 'finally\s*\{')
    fullReleaseExceptionCanBeWrapped = ($finalizer -match 'StageArgumentList' -and $entrypoint -match 'FullRelease')
    hostSafetyIsDiagnostic = ($finalizer -match 'TerminalMode' -and $finalizer -match 'BLOCKED')
    originalBlockerPreserved = ($finalizer -match 'primaryBlocker' -and $finalizer -match 'secondaryBlockers')
    idempotentTerminalChecks = ($finalizer -match 'Get-VM -Id' -and $finalizer -match 'Get-DevFleetHostNameExclusion' -and $finalizer -match 'exact L1')
    hostL2CheckRemainsHostScoped = ($finalizer -match 'host Hyper-V exact-name exclusion only' -and $finalizer -match 'Get-CurrentNestedL2ReleaseEvidence' -and $finalizer -match 'No validated current RunId-bound nested L1 inventory')
    preservesCurrentCandidateBinding = ($finalizer -match 'function Test-CandidateEvidenceRefreshRequired' -and $finalizer -match 'Test-CandidateEvidenceRefreshRequired\s+-State\s+\$stateBeforeRefresh')
    noCredentials = ($finalizer -match 'credentialValuesIncluded\s*=\s*\$false' -and $finalizer -match 'hostAgentSecretsIncluded\s*=\s*\$false' -and $finalizer -match 'REDACTED')
    exactL1Only = ($finalizer -match '84b7d8b8-ee6c-4085-aa29-4b0adc316de2' -and $finalizer -match 'DevFleet-E2E-Win11-01' -and $finalizer -match 'L1Touched')
    protectedNamesRejected = ($finalizer -match 'L2Name' -and $finalizer -match 'no deletion or adoption')
    l2AbsenceRecorded = ($finalizer -match 'l2ExactAbsent' -and $finalizer -match 'FINALIZER-TERMINAL-STATE')
    passVsDiagnosticMode = ($finalizer -match "'PASS','BLOCKED'" -and $finalizer -match "'diagnostic'" -and $finalizer -match "'release'")
    sidecarLast = ($builder -match 'outer sidecar is the final filesystem write' -and $builder -notmatch 'Set-Content -LiteralPath \$sidecarPath[\s\S]{0,300}Write-Json \$manifestPath')
    zipNotMutatedAfterSidecar = ($finalizer -match 'No ZIP write occurs after this point' -and $builder -match 'ZIP is never modified after this point')
}
$failed = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value } | ForEach-Object Key)
$result = [ordered]@{status=if($failed.Count -eq 0){'PASS'}else{'FAIL'};passed=($checks.Count-$failed.Count);total=$checks.Count;checks=$checks;failures=$failed}
$result | ConvertTo-Json -Depth 8
if ($failed.Count) { exit 1 }

```


## FILE: automation/release-e2e/tests/Test-FinalizerNestedTerminalEvidence.ps1

SHA256: a78208e93eef8365812a0e7979ab60eae65ad4fc23c44c871ddddc67af813f74 | Bytes: 14844 | Git mode: 100644

```
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
$modulePath = Join-Path $Workspac