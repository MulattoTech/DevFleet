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
