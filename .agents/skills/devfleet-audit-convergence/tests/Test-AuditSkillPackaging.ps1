[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$sourcePath=Join-Path $WorkspaceRoot 'tools/Build-AIAuditBundle.ps1'
$source=[IO.File]::ReadAllText($sourcePath)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($sourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Native builder has parse errors'}
foreach($name in @('Is-Excluded','Add-Tree','Add-CompactFile','Get-Hash','Add-AuthorizationLedgerClosure')){
    $nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
    if($nodes.Count -ne 1){throw "Expected one native function: $name"}
    . ([scriptblock]::Create($nodes[0].Extent.Text))
}
function Read-Json([string]$Path){Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}
function Write-Json([string]$Path,$Value){$Value|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $Path -Encoding UTF8}
$block=[regex]::Match($source,'(?s)# Carry the installed release-control contract.*?(?=\s+if \(\$historicalDiagnosticTuple\))')
if(-not $block.Success){throw 'Cannot locate real native release-control staging block'}
$required=@('SKILL.md','agents/openai.yaml','scripts/audit_io.py','scripts/audit_convergence.py','scripts/native_runner.py','references/completion-contract.md','tests/test_audit_convergence.py','tests/Test-AuditSkillPackaging.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('DevFleet-audit-skill-test-'+[guid]::NewGuid().ToString('N'))
$results=@()
try{
    foreach($case in @('complete','absent','missing-runner')){
        $Workspace=Join-Path $temp ($case+'/repo');$stage=Join-Path $temp ($case+'/stage');$auditStage=Join-Path $stage 'audit'
        $docs=Join-Path $Workspace 'docs/ai/devfleet-release';New-Item -ItemType Directory -Path $docs -Force|Out-Null
        [IO.File]::WriteAllText((Join-Path $docs 'DONE.md'),'fixture only; no certification')
        $skill=Join-Path $Workspace '.agents/skills/devfleet-audit-convergence'
        if($case -ne 'absent'){
            foreach($relative in $required){
                if($case -eq 'missing-runner' -and $relative -eq 'scripts/native_runner.py'){continue}
                $path=Join-Path $skill $relative;New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force|Out-Null
                [IO.File]::WriteAllText($path,('fixture '+$relative))
            }
            [IO.File]::WriteAllText((Join-Path $skill 'unexpected-private.txt'),'not authorized for inclusion')
        }
        $caught=$false;try{. ([scriptblock]::Create($block.Value))}catch{$caught=$true}
        $dest=Join-Path $stage 'release-control/audit-convergence-skill'
        if($case -eq 'complete'){
            foreach($relative in $required){$file=Join-Path $dest $relative;$ok=(Test-Path -LiteralPath $file -PathType Leaf) -and ((Get-Hash $file) -ceq (Get-Hash (Join-Path $skill $relative)));$results+=@{case=$case;check=$relative;pass=$ok}}
            $results+=@{case=$case;check='no unrelated files included';pass=(-not(Test-Path (Join-Path $dest 'unexpected-private.txt')))}
        }elseif($case -eq 'missing-runner'){$results+=@{case=$case;check='incomplete installed skill blocks packaging';pass=$caught}}
        else{$results+=@{case=$case;check='older checkout without skill remains supported';pass=(-not $caught)}}
    }
    $closureCases=@('valid','missing-selected','wrong-policy','tampered-stage','secret-field','safe-path')
    foreach($case in $closureCases){
        $Repository=Join-Path $temp ('closure-'+$case+'/repo');$EvidenceRoot=Join-Path $temp ('closure-'+$case+'/stage/evidence');$campaign=Join-Path $Repository 'evidence/campaigns';New-Item -ItemType Directory -Path $campaign -Force|Out-Null
        $historicalPath=Join-Path $campaign 'df-tailscale-peer-convergence-20260921-a-ledger.json';$historicalText='{"policyId":"HISTORICAL","lastCompletedReservation":null,"lastCompletedReservation":{}}';[IO.File]::WriteAllText($historicalPath,$historicalText,[Text.UTF8Encoding]::new($false));$historicalHash=Get-Hash $historicalPath
        $aPath=Join-Path $campaign 'df-audit-convergence-20260924-a-ledger.json';$a=[ordered]@{policyId='DF-AUDIT-CONVERGENCE-20260924-A';status='BLOCKED_CREDENTIAL_STALE_RECURRED_AFTER_REFRESH_STOP_RUNTIME_FOR_CAUSE';authorization=[ordered]@{adoptedAtUtc='2026-09-24T00:00:00Z';token=[ordered]@{isElevated=$false}};continuation=[ordered]@{preservedLedgerFiles=@([ordered]@{path='evidence/campaigns/df-tailscale-peer-convergence-20260921-a-ledger.json';sha256=$historicalHash;observedParseStatus='INVALID_DUPLICATE_JSON_PROPERTY:lastCompletedReservation'})};baseline=[ordered]@{standardTokenQualification=[ordered]@{maximum=1;consumed=1}};counters=[ordered]@{baselineConsumed=2;correctiveConsumed=3;topLevelConsumed=5;standardTokenConsumed=2;laptopProofConsumed=2};maximumTopLevelInvocations=9;sharedCorrectivePool=[ordered]@{maximum=5;consumed=3};activeReservation=$null};Write-Json $aPath $a;$aHash=Get-Hash $aPath
        $bPath=Join-Path $campaign 'df-rdc-certification-continuation-20260924-b-ledger.json';$b=[ordered]@{policyId=if($case -eq 'wrong-policy'){'WRONG-POLICY'}else{'DF-RDC-CERTIFICATION-CONTINUATION-20260924-B'};status='ADOPTED_PREPARATION_RUNTIME_NOT_RESERVED';authorization=[ordered]@{adoptedAtUtc='2026-09-24T00:00:00Z'};continuation=[ordered]@{predecessor=[ordered]@{path='evidence/campaigns/df-audit-convergence-20260924-a-ledger.json';sha256=$aHash}};baseline=[ordered]@{standardTokenQualification=[ordered]@{maximum=1;consumed=0}};counters=[ordered]@{baselineConsumed=0;correctiveConsumed=0;topLevelConsumed=0};maximumTopLevelInvocations=9;sharedCorrectivePool=[ordered]@{maximum=4;consumed=0};activeReservation=$null};if($case -eq 'secret-field'){$b.authorization.secret='FIXTURE_ONLY_SECRET'};Write-Json $bPath $b
        if($case -eq 'missing-selected'){Remove-Item -LiteralPath $bPath}
        if($case -eq 'safe-path'){$outside=Join-Path $temp 'closure-safe-path/outside';Move-Item -LiteralPath $campaign -Destination $outside;New-Item -ItemType Junction -Path $campaign -Target $outside|Out-Null}
        $caught=$false;$result=$null
        if($case -eq 'tampered-stage'){
            $original=(Get-Command Add-CompactFile).ScriptBlock
            $script:originalAddCompactFile=$original
            Set-Item Function:Add-CompactFile -Value {param([string]$Source,[string]$Destination);$ok=& $script:originalAddCompactFile $Source $Destination;if($ok){Add-Content -LiteralPath $Destination -Value 'tampered'};return $ok}
            # The injected test copy wrapper is local to this isolated script and has no VM/native side effects.
            try{$result=Add-AuthorizationLedgerClosure -Repository $Repository -EvidenceRoot $EvidenceRoot}catch{$caught=$true}finally{Set-Item Function:Add-CompactFile -Value $original;$script:originalAddCompactFile=$null}
        }else{try{$result=Add-AuthorizationLedgerClosure -Repository $Repository -EvidenceRoot $EvidenceRoot}catch{$caught=$true;if($case -eq 'valid'){Write-Output "authorization closure fixture error: $($_.Exception.Message)"}}}
        if($case -eq 'valid'){
            $closurePath=Join-Path $EvidenceRoot 'campaigns/authorization-ledger-closure.json';$closure=if(Test-Path $closurePath){Get-Content -Raw $closurePath|ConvertFrom-Json}else{$null}
            $results+=@{case=$case;check='A to B predecessor and source/staged hash closure';pass=(-not $caught -and $null -ne $closure -and $closure.runtimeAuthorizationGranted -eq $false -and $closure.ledgers.Count -eq 2 -and $closure.ledgers[1].sourceSha256 -eq $closure.ledgers[1].stagedSha256)}
            $results+=@{case=$case;check='malformed historic ledger disclosed UNKNOWN with matching hash';pass=($null -ne $closure -and $closure.malformedHistoricalLedger.authorizationInterpretation -eq 'UNKNOWN' -and $closure.malformedHistoricalLedger.sourceHashMatchesRecorded -eq $true)}
            $results+=@{case=$case;check='projection excludes credential and token metadata';pass=((Get-Content -Raw $closurePath) -notmatch '(?i)"(password|secret|token|hmac|dpapi|privateKey)"\s*:')}
        }elseif($case -in @('missing-selected','wrong-policy','tampered-stage')){$results+=@{case=$case;check='missing, substituted or changed ledger bytes fail closed';pass=$caught}}
        elseif($case -eq 'safe-path'){$results+=@{case=$case;check='reparse-point path components fail closed';pass=$caught}}
        else{$results+=@{case=$case;check='secret-bearing input values are excluded from projection';pass=(-not $caught -and (Get-Content -Raw (Join-Path $EvidenceRoot 'campaigns/authorization-ledger-closure.json')) -notmatch 'FIXTURE_ONLY_SECRET')}}
    }
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
$failed=@($results|Where-Object{-not $_.pass})
[ordered]@{scope='VM_FREE_NATIVE_STAGING_BEHAVIOR';status=if($failed.Count){'FAIL'}else{'PASS'};passed=($results.Count-$failed.Count);total=$results.Count;checks=$results;certificationCredit=$false;temporaryFilesRemoved=(-not(Test-Path -LiteralPath $temp))}|ConvertTo-Json -Depth 5
if($failed.Count){exit 1}
