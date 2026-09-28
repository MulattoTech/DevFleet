# DevFleet source part 002

Full-source UTF-8 byte interval [46500, 93000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 9b784d6854068ed66b6d8b952c7b1abe3006039a5de96aa582cb508770a48298

<!-- BEGIN SOURCE SLICE -->
 validators execute extracted Python/MSBuild inputs: compare these first.

    A self-consistent attacker-controlled manifest does not make code trusted. Analysis
    remains available for historical/foreign archives that cannot meet this boundary.
    """
    count=0
    with Snapshot(archive) as snap, Snapshot(repo) as live:
        if not snap.exists('source/tools/validate_audit_coherence.py'):
            raise AuditInputError('Native verification requires the reviewed coherence implementation')
        for name in snap.members:
            # Python import search and MSBuild can consume unindexed sibling inputs.
            # Compare all bytes in their execution trees, not just manifest code rows.
            if name.startswith(('source/','installer-source/')):
                expected=live.read(name,optional=True)
                actual=snap.read(name)
                if expected is None or actual.replace(b'\r\n',b'\n') != expected.replace(b'\r\n',b'\n'):
                    raise AuditInputError('Archive executable-input trust mismatch: '+name)
                count+=1
            elif '/' not in name and (Path(name).suffix.lower() in ('.py','.pyc','.pyd','.dll','.props','.targets') or name.casefold() in ('global.json','nuget.config')):
                raise AuditInputError('Unreviewed root execution input in archive: '+name)
    return {'status':'MATCHED_REVIEWED_LIVE_SOURCES','filesCompared':count,
            'comparison':'exact bytes or CRLF-only normalization','certificationCredit':False}


def verify(repo,archive,mode,out):
    # Use a private copy: another canonical ZIP writer must not swap bytes between
    # structural checks and a native validator opening its archive argument.
    before=hash_file(archive)
    snapshot=out/'validated-input.zip'
    with Path(archive).open('rb') as src, snapshot.open('xb') as dst:
        shutil.copyfileobj(src,dst,1024*1024)
    if hash_file(snapshot)!=before:raise AuditInputError('Archive changed while preparing the validation snapshot')
    with Snapshot(snapshot) as snap:
        integrity=snap.verify_inventory()
        if integrity['status']!='PASS':raise AuditInputError('Archive inventory is damaged; refusing native validation')
    trust=check_archive_code_trust(repo,snapshot)
    results=[]
    for command in make_plan(repo,'verify',mode,snapshot)['commands']:
        if hash_file(snapshot)!=before:raise AuditInputError('Validated snapshot changed before native execution')
        result=_execute(command,repo,out);results.append(result)
        expected=('PASS_WITH_BLOCKER' if mode=='diagnostic' else ('PASS' if command['kind']=='release-validator' else 'COMPLETE_FOR_AI_AUDIT'))
        native=result.get('nativeResult')
        valid=result['exitCode']==0 and isinstance(native,dict) and native.get('status')==expected
        if valid and mode=='diagnostic':valid=native.get('releaseEligible') is False
        if valid and mode=='release':valid=native.get('releaseEligible') is True
        if not valid:
            _write_new(out/'native-verification.json',{'status':'FAIL','archiveSha256':before,'mode':mode,'codeTrust':trust,'results':results})
            raise AuditInputError('Native validation failed or returned an unexpected status; see native-verification.json')
    after=hash_file(archive);unchanged=after==before and hash_file(snapshot)==before
    record={'status':'PASS' if unchanged else 'FAIL','mode':mode,'archive':str(archive),'archiveSha256':after,
            'sameBytesThroughout':unchanged,'validatedSnapshot':str(snapshot),'codeTrust':trust,
            'results':results,'authority':'Native validators, not the advisory analyzer'}
    _write_new(out/'native-verification.json',record)
    if not unchanged:raise AuditInputError('Archive changed during native validation')
    return record


def check_sidecar(archive):
    digest=hash_file(archive);sidecar=Path(str(archive)+'.sha256.txt')
    if not sidecar.is_file():raise AuditInputError('Native ZIP checksum sidecar missing')
    text=sidecar.read_text(encoding='utf-8-sig')
    if not re.search(r'(?im)^SHA-256:\s*'+digest+r'\s*$',text):raise AuditInputError('Native checksum sidecar digest mismatch')
    if not re.search(r'(?im)^BYTES:\s*'+str(archive.stat().st_size)+r'\s*$',text):raise AuditInputError('Native checksum sidecar byte count mismatch')
    return {'path':str(sidecar),'sha256':digest,'bytes':archive.stat().st_size,'verified':True}


def run(args):
    repo=Path(args.repo).resolve(strict=True);out=safe_output_dir(args.output,repo);out.mkdir(parents=True,exist_ok=True)
    if any(out.iterdir()):raise AuditInputError('Use an empty, unique external output directory for a native operation')
    archive=Path(args.archive).resolve(strict=True) if args.command=='verify' else None
    mode=getattr(args,'mode','diagnostic');plan=make_plan(repo,args.command,mode,archive)
    _write_new(out/'command-plan.json',plan)
    if not args.execute:
        print(json.dumps(plan,indent=2));return 0
    _check_repo(repo,args.expected_head)
    if args.command=='verify':result=verify(repo,archive,mode,out)
    else:
        version=(repo/'source/VERSION').read_text(encoding='utf-8-sig').strip()
        if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9]+)*',version):raise AuditInputError('Release version is not a safe artifact identifier')
        archive=repo/'outputs'/f'DevFleet-v{version}-AI-Audit-LATEST.zip'
        if archive.exists():
            prior=out/'prior-audit.zip';shutil.copy2(archive,prior)
            if hash_file(prior)!=hash_file(archive):raise AuditInputError('Previous canonical audit preservation failed')
        result=_execute(plan['commands'][0],repo,out)
        _write_new(out/'build-process.json',result)
        if result['exitCode']!=0:raise AuditInputError('Native builder failed; a pre-existing LATEST ZIP is not a new successful output')
        if not archive.is_file():raise AuditInputError('Native builder produced no canonical archive')
        sidecar=check_sidecar(archive)
        with Snapshot(archive) as s:
            validation=s.json('release-tooling/candidate-bound-validator-result.json')
            mode=validation.get('bundleMode') if isinstance(validation,dict) else None
        if mode not in ('diagnostic','release'):raise AuditInputError('Generated archive has no unambiguous native mode')
        result=verify(repo,archive,mode,out);result['sidecar']=sidecar
        _write_new(out/'build-result.json',result)
        # The exact finalized bytes are analyzed once; no source/handoff write triggers another build.
        from audit_convergence import analyze
        analyze(archive,out/'analysis',repo)
    _check_repo(repo,args.expected_head)
    print(json.dumps({'status':result['status'],'mode':result['mode'],'archive':str(archive),
        'archiveSha256':result['archiveSha256'],'verificationReport':str(out/'native-verification.json')},indent=2))
    return 0

```


## FILE: .agents/skills/devfleet-audit-convergence/tests/Test-AuditSkillPackaging.ps1

SHA256: 24e27db8b946891e025d736bc7820cee19de3591a6de85aa8c8faac90624522a | Bytes: 9144 | Git mode: 100644

```
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

```


## FILE: .agents/skills/devfleet-audit-convergence/tests/test_audit_convergence.py

SHA256: c5710d8a1decea587d288aff68e44fe7550efcb416b64cbb131d2570a122342c | Bytes: 22815 | Git mode: 100644

```
"""Behavioral regression tests for the advisory audit-convergence workflow."""
from pathlib import Path
import unittest

class CommandAvailability(unittest.TestCase):
    def test_analyzer_command_is_available(self):
        entry = Path(__file__).resolve().parents[1] / 'scripts' / 'audit_convergence.py'
        self.assertTrue(entry.is_file(), 'Requested audit-convergence command is not implemented')


# Imports occur inside the tests so the initial missing-command failure is explicit.
import copy
import hashlib
import json
import os
import stat
import sys
import tempfile
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))

PHASES = 'HOST-SAFETY CANDIDATE-VERIFY RESTORE-CLEAN ESTABLISH-SESSION DEPENDENCY-MATRIX SECURITY-POISON FRESH-INSTALL-WPF PRIMARY LINUX HTTP-HOSTILE MAINTENANCE-READY WINDOWS-SENTINELS REPAIR CLEAN-REINSTALL UNINSTALL FACTORY-RESET REBOOT-RESUME PERMANENT-DELETE DELETE-RESTORE STOPPED-PROJECT HOST-CONCURRENCY OPERATION-RECOVERY OWNERSHIP VAULT SURROGATE-DISPOSABLE REAL-USE-ACCEPTANCE TAILSCALE-DEFERRED TAILSCALE-AUTH AI-BUNDLE RECONCILE CLEANUP'.split()
IDENTITY = dict(repositoryHead='a'*40, candidateCommit='b'*40, shippingInputIdentity='c'*64,
                releaseFingerprintId='d'*64, toolingFingerprintId='e'*64)

def data():
    authority = dict(IDENTITY, authorityId='f'*64, generatedAtUtc='2026-09-24T10:00:00Z',
                     status='BLOCKED', blockerClassification='BLOCKED - EXACT PROOF NOT OBSERVED',
                     candidateIsCurrent=True, sourceChangedSinceCandidate=False, rebuildRequired=False,
                     validationEvidenceCurrent=False, fullReleasePassed=False, internalPromotionAllowed=False,
                     publicPromotionAllowed=False, publicPublisherTrust=False,
                     proofs={'passing':0,'required':2,'runs':[]})
    return {
      'CURRENT-CANDIDATE.json':dict(IDENTITY, candidateIsCurrent=True, sourceChangedSinceCandidate=False, rebuildRequired=False, artifacts=[]),
      'evidence/CURRENT-RELEASE-AUTHORITY.json':authority,
      'evidence/CURRENT-GATES.json':dict(IDENTITY, authorityId='f'*64, gates={'maintenance':'UNVERIFIED - 0/5'}, currentPhase='PRE-EXACT-PROOF'),
      'evidence/FULLRELEASE-SUMMARY.json':dict(IDENTITY, latestRunId=None, status='NOT_RUN_FOR_CURRENT_CANDIDATE', historicalEvidenceOnly=True, diagnosticOnly=True),
      'evidence/CURRENT-STANDARD-TOKEN.json':dict(IDENTITY, repositoryHead='0'*40, runId='standard-token-old', status='PASS', standardNonAdministratorToken=True),
      'evidence/l1-terminal-state.json':{'state':'Off','timestampUtc':'2026-09-24T07:00:00Z'},
      'evidence/l2-terminal-state.json':{'status':'UNVERIFIED','present':None,'verificationMethod':'No current nested observation'},
      'automation/release-e2e/modules/FullRelease.psm1':"$script:FullReleasePhases = @(\n"+'\n'.join("[pscustomobject]@{ id='%s'; label='%s' },"%(p,p) for p in PHASES)+"\n)\n",
      'evidence/campaigns/closed-ledger.json':{'policyId':'CLOSED','executionClosed':True,'fullReleaseMaximum':1,'fullReleaseConsumed':1,'activeReservation':None},
    }

def write_tree(root, records):
    for name, value in records.items():
        p = root/name; p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(value if isinstance(value,str) else json.dumps(value), encoding='utf-8')

def write_zip(path, records):
    content = {n:(v if isinstance(v,str) else json.dumps(v)).encode() for n,v in records.items()}
    rows = [{'path':n,'bytes':len(v),'sha256':hashlib.sha256(v).hexdigest()} for n,v in content.items()]
    m = dict(IDENTITY, status='BLOCKED',sourceInventory=rows,evidenceInventory=[],expectedSourceCount=len(rows),includedSourceCount=len(rows))
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
        for n,v in content.items(): z.writestr(n,v)
        z.writestr('AUDIT-MANIFEST.json',json.dumps(m))

class AdvisoryStateTests(unittest.TestCase):
    def setUp(self):
        from audit_convergence import summarize
        from audit_io import Snapshot
        self.summarize, self.Snapshot = summarize, Snapshot
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)/'repo';self.root.mkdir()
        self.records=data()
    def run_report(self):
        write_tree(self.root,self.records)
        with self.Snapshot(self.root) as s:return self.summarize(s)
    def test_pending_phases_are_not_failures(self):
        r=self.run_report();self.assertEqual(len(r['phases']),31)
        self.assertEqual(r['phaseCounts'],{'NOT_RUN':31})
    def test_stale_pass_token_does_not_become_current(self):
        r=self.run_report();self.assertEqual(r['standardToken']['state'],'STALE')
        self.assertIn('repositoryHead',r['standardToken']['mismatches'])
    def test_closed_ledger_never_authorizes_runtime(self):
        r=self.run_report();self.assertFalse(r['runtimeAuthorizationGranted'])
        self.assertEqual(r['ledgerObservations'][0]['executionClosed'],True)
    def test_malformed_historical_ledger_is_disclosed_and_other_ledgers_continue(self):
        self.records['evidence/campaigns/malformed-ledger.json']='{"policyId":"BROKEN","lastCompletedReservation":null,"lastCompletedReservation":{}}'
        self.records['evidence/campaigns/readable-ledger.json']={'policyId':'READABLE','status':'CLOSED','activeReservation':None}
        r=self.run_report();rows={x['path']:x for x in r['ledgerObservations']}
        broken=rows['evidence/campaigns/malformed-ledger.json']
        self.assertEqual(broken['parseStatus'],'MALFORMED');self.assertEqual(broken['parseError'],'DUPLICATE_JSON_PROPERTY')
        self.assertEqual(broken['authorizationInterpretation'],'UNKNOWN');self.assertEqual(len(broken['sha256']),64)
        self.assertEqual(rows['evidence/campaigns/readable-ledger.json']['policyId'],'READABLE')
        self.assertFalse(r['runtimeAuthorizationGranted'])
    def test_malformed_selected_authority_still_fails_closed(self):
        self.records['evidence/CURRENT-RELEASE-AUTHORITY.json']='{"status":"BLOCKED","status":"PASS"}'
        from audit_io import AuditInputError
        with self.assertRaises(AuditInputError):self.run_report()
    def test_missing_token_is_missing_not_failed_product(self):
        del self.records['evidence/CURRENT-STANDARD-TOKEN.json']
        self.assertEqual(self.run_report()['standardToken']['state'],'MISSING')
    def test_string_true_is_not_candidate_true(self):
        self.records['CURRENT-CANDIDATE.json']['candidateIsCurrent']='true'
        self.assertIn('CANDIDATE_FLAGS_NOT_CURRENT',self.run_report()['blockerCodes'])
    def test_missing_authority_never_reports_release(self):
        del self.records['evidence/CURRENT-RELEASE-AUTHORITY.json']
        r=self.run_report();self.assertIn('AUTHORITY_MISSING',r['blockerCodes'])
        self.assertFalse(r['certificationCredit'])
    def test_unknown_nested_inventory_is_not_absent(self):
        r=self.run_report();self.assertEqual(r['terminal']['l2']['status'],'UNVERIFIED')
    def test_unproven_absence_stays_recorded_only(self):
        self.records['evidence/l2-terminal-state.json']={'status':'ABSENT','present':False,'verificationMethod':'host Get-VM'}
        r=self.run_report();self.assertEqual(r['terminal']['nestedProofValidation'],'NOT_PERFORMED')
        self.assertFalse(r['certificationCredit'])
    def test_new_native_phase_is_discovered(self):
        self.records['automation/release-e2e/modules/FullRelease.psm1']=self.records['automation/release-e2e/modules/FullRelease.psm1'].replace('\n)\n',"\n[pscustomobject]@{id='NEW-GATE';label='new'}\n)\n")
        self.assertEqual(len(self.run_report()['phases']),32)
    def test_duplicate_phase_definition_is_rejected(self):
        self.records['automation/release-e2e/modules/FullRelease.psm1']=self.records['automation/release-e2e/modules/FullRelease.psm1'].replace("id='LINUX'","id='PRIMARY'")
        from audit_io import AuditInputError
        with self.assertRaises(AuditInputError): self.run_report()
    def test_authority_identity_conflict_blocks(self):
        self.records['evidence/CURRENT-RELEASE-AUTHORITY.json']['toolingFingerprintId']='0'*64
        self.assertIn('AUTHORITY_TUPLE_CONFLICT',self.run_report()['blockerCodes'])
    def test_current_token_requires_native_validation(self):
        self.records['evidence/CURRENT-STANDARD-TOKEN.json']=dict(IDENTITY,runId='standard-token-current',status='PASS',standardNonAdministratorToken=True)
        self.assertEqual(self.run_report()['standardToken']['state'],'RECORDED_CURRENT_UNVALIDATED')
    def test_fake_green_all_booleans_never_certifies(self):
        a=self.records['evidence/CURRENT-RELEASE-AUTHORITY.json']
        a.update(status='PASS',validationEvidenceCurrent=True,fullReleasePassed=True,internalPromotionAllowed=True)
        self.records['evidence/FINAL-ACCEPTANCE.json']={'status':'PASS'}
        r=self.run_report();self.assertFalse(r['certificationCredit']);self.assertIn('NATIVE_VALIDATION_REQUIRED',r['blockerCodes'])
    def test_historical_phase_record_not_counted(self):
        f=self.records['evidence/FULLRELEASE-SUMMARY.json'];f.update(latestRunId='fullrelease-test',status='BLOCKED',historicalEvidenceOnly=False)
        self.records['audit/automation-harness/runs/fullrelease-test/run-state.json']={'runId':'fullrelease-test','candidateHashes':dict(IDENTITY,toolingFingerprintId='0'*64)}
        self.records['audit/automation-harness/runs/fullrelease-test/fullrelease-phase-records.json']=[{'id':p,'status':'PASS','runId':'fullrelease-test'} for p in PHASES]
        r=self.run_report();self.assertNotIn('PASS',r['phaseCounts']);self.assertIn('FULLRELEASE_RUN_TUPLE_CONFLICT',r['blockerCodes'])
    def test_matching_run_displays_recorded_phases_not_certification(self):
        f=self.records['evidence/FULLRELEASE-SUMMARY.json'];f.update(latestRunId='fullrelease-test',status='BLOCKED',historicalEvidenceOnly=False)
        self.records['audit/automation-harness/runs/fullrelease-test/run-state.json']={'runId':'fullrelease-test','candidateHashes':IDENTITY}
        self.records['audit/automation-harness/runs/fullrelease-test/fullrelease-phase-records.json']=[{'id':'HOST-SAFETY','status':'PASS','runId':'fullrelease-test'}]
        r=self.run_report();self.assertEqual(r['phases'][0]['state'],'RECORDED_PASS');self.assertFalse(r['certificationCredit'])
    def test_wrong_run_phase_is_not_selected(self):
        f=self.records['evidence/FULLRELEASE-SUMMARY.json'];f.update(latestRunId='fullrelease-test',status='BLOCKED',historicalEvidenceOnly=False)
        self.records['audit/automation-harness/runs/fullrelease-test/run-state.json']={'runId':'fullrelease-test','candidateHashes':IDENTITY}
        self.records['audit/automation-harness/runs/fullrelease-test/fullrelease-phase-records.json']=[{'id':'HOST-SAFETY','status':'PASS','runId':'another-run'}]
        self.assertNotEqual(self.run_report()['phases'][0]['state'],'RECORDED_PASS')
    def test_snapshot_json_is_not_modified(self):
        write_tree(self.root,self.records);before={p.relative_to(self.root):p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.run_report();after={p.relative_to(self.root):p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(before,after)

class ArchiveInputTests(unittest.TestCase):
    def setUp(self):
        from audit_io import Snapshot, AuditInputError
        self.Snapshot,self.Error=Snapshot,AuditInputError
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
    def archive(self,name='a.zip'): return self.root/name
    def test_valid_archive_inventory_hashes(self):
        p=self.archive();write_zip(p,data())
        with self.Snapshot(p) as s:
            r=s.verify_inventory();self.assertEqual(r['status'],'PASS');self.assertGreater(r['verifiedFiles'],8)
    def test_tampered_member_is_detected(self):
        p=self.archive();write_zip(p,data());q=self.archive('tamper.zip')
        with zipfile.ZipFile(p) as src, zipfile.ZipFile(q,'w') as dst:
            for i in src.infolist():dst.writestr(i.filename,b'{}' if i.filename=='CURRENT-CANDIDATE.json' else src.read(i))
        with self.Snapshot(q) as s:self.assertEqual(s.verify_inventory()['status'],'FAIL')
    def test_path_traversal_rejected_before_read(self):
        p=self.archive()
        with zipfile.ZipFile(p,'w') as z:z.writestr('../escape.txt','bad')
        with self.assertRaises(self.Error):self.Snapshot(p)
    def test_backslash_path_rejected(self):
        p=self.archive()
        with zipfile.ZipFile(p,'w') as z:z.writestr('..\\escape.txt','bad')
        with self.assertRaises(self.Error):self.Snapshot(p)
    def test_case_alias_duplicate_rejected(self):
        p=self.archive()
        with zipfile.ZipFile(p,'w') as z:z.writestr('EVIDENCE/A.json','{}');z.writestr('evidence/a.json','{}')
        with self.assertRaises(self.Error):self.Snapshot(p)
    def test_symlink_member_rejected(self):
        p=self.archive();i=zipfile.ZipInfo('link');i.create_system=3;i.external_attr=(stat.S_IFLNK|0o777)<<16
        with zipfile.ZipFile(p,'w') as z:z.writestr(i,'/outside')
        with self.assertRaises(self.Error):self.Snapshot(p)
    def test_member_size_limit(self):
        p=self.archive()
        with zipfile.ZipFile(p,'w') as z:z.writestr('data.json','x'*2048)
        with self.assertRaises(self.Error):self.Snapshot(p,max_member_bytes=1024)
    def test_ads_and_windows_reserved_paths_rejected(self):
        from audit_io import safe_relative
        for s in ['C:/a','/a','a:file','CON.txt','a/../b','a//b','a.','a /b','a\x00b']:
            with self.subTest(s=s),self.assertRaises(self.Error):safe_relative(s)
    def test_duplicate_json_keys_rejected(self):
        p=self.root/'repo';p.mkdir();(p/'a.json').write_text('{"status":"PASS","status":"FAIL"}')
        with self.Snapshot(p) as s:
            with self.assertRaises(self.Error):s.json('a.json')
    def test_output_directory_inside_repository_rejected(self):
        from audit_io import safe_output_dir
        with self.assertRaises(self.Error):safe_output_dir(self.root/'outputs',self.root)
    def test_output_does_not_overwrite_existing_report(self):
        from audit_io import save_report
        out=self.root/'report';out.mkdir();(out/'analysis.json').write_text('preserve')
        with self.assertRaises(self.Error):save_report(out,{},'# report')
        self.assertEqual((out/'analysis.json').read_text(),'preserve')
    def test_workspace_link_escape_rejected(self):
        p=self.root/'repo';p.mkdir();outside=self.root/'secret';outside.write_text('secret')
        try:(p/'link').symlink_to(outside)
        except OSError:self.skipTest('OS does not allow creating test symlink')
        with self.Snapshot(p) as s:
            with self.assertRaises(self.Error):s.read('link')

class NativePlanTests(unittest.TestCase):
    def test_plan_does_not_run_native_commands(self):
        from native_runner import make_plan
        with tempfile.TemporaryDirectory() as t:
            r=make_plan(Path(t),'build','diagnostic')
            self.assertFalse(r['executed']);self.assertEqual(r['commands'][0]['kind'],'build')
            self.assertNotIn('AllowRamPressure',json.dumps(r))
    def test_verify_never_uses_script_from_archive(self):
        from native_runner import make_plan
        with tempfile.TemporaryDirectory() as t:
            r=make_plan(Path(t),'verify','diagnostic',Path(t)/'a.zip')
            self.assertEqual(len(r['commands']),2)
            self.assertTrue(all('release-tooling' not in ' '.join(x['argv']) for x in r['commands']))
    def test_native_mode_must_be_explicit_valid_value(self):
        from native_runner import make_plan
        from audit_io import AuditInputError
        with self.assertRaises(AuditInputError):make_plan(Path('.'),'verify','fake',Path('a.zip'))

class NativeExecutionBoundaryTests(unittest.TestCase):
    def setUp(self):
        from audit_io import AuditInputError
        self.Error=AuditInputError
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.repo=self.root/'repo';self.repo.mkdir()
        self.out=self.root/'out';self.out.mkdir();self.archive=self.root/'audit.zip'
        self.records={'source/tools/validate_audit_coherence.py':'print("reviewed")\n',
                      'source/VERSION':'1.2.13\n',
                      'installer-source/App.csproj':'<Project/>\n'}
        write_tree(self.repo,self.records)
    def native(self,command,repo,out):
        return {'exitCode':0,'kind':command['kind'],'nativeResult':{'status':'PASS_WITH_BLOCKER','releaseEligible':False}}
    def test_native_verification_rejects_changed_archive_code_before_execution(self):
        from unittest.mock import patch
        from native_runner import verify
        changed=dict(self.records);changed['source/tools/validate_audit_coherence.py']='print("not reviewed")\n'
        write_zip(self.archive,changed)
        with patch('native_runner._execute',side_effect=self.native) as child:
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
            self.assertEqual(child.call_count,0)
    def test_native_verification_rejects_unreviewed_msbuild_file(self):
        from unittest.mock import patch
        from native_runner import verify
        changed=dict(self.records);changed['Directory.Build.targets']='<Project><Target Name="x"/></Project>'
        write_zip(self.archive,changed)
        with patch('native_runner._execute',side_effect=self.native) as child:
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
            self.assertEqual(child.call_count,0)
    def test_native_verification_requires_source_code_guard_file(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,{'source/VERSION':'1.2.13\n'})
        with patch('native_runner._execute',side_effect=self.native) as child:
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
            self.assertEqual(child.call_count,0)
    def test_native_verify_accepts_reviewed_bytes_and_uses_private_snapshot(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,self.records)
        def execute(command,repo,out):
            path=Path(command['argv'][command['argv'].index('--archive')+1])
            self.assertNotEqual(path,self.archive)
            self.assertEqual(path.read_bytes(),self.archive.read_bytes())
            return self.native(command,repo,out)
        with patch('native_runner._execute',side_effect=execute):
            result=verify(self.repo,self.archive,'diagnostic',self.out)
        self.assertEqual(result['status'],'PASS')
        self.assertEqual(result['codeTrust']['status'],'MATCHED_REVIEWED_LIVE_SOURCES')
    def test_native_verify_accepts_crlf_only_change(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,{k:v.replace('\n','\r\n') for k,v in self.records.items()})
        with patch('native_runner._execute',side_effect=self.native):
            self.assertEqual(verify(self.repo,self.archive,'diagnostic',self.out)['status'],'PASS')
    def test_success_text_cannot_override_nonzero_native_exit(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,self.records)
        def failed(*args):
            r=self.native(*args);r['exitCode']=1;return r
        with patch('native_runner._execute',side_effect=failed) as child:
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
            self.assertEqual(child.call_count,1)
        self.assertEqual(json.loads((self.out/'native-verification.json').read_text())['status'],'FAIL')
    def test_diagnostic_native_result_cannot_claim_release(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,self.records)
        def wrong(*args):
            r=self.native(*args);r['nativeResult']['releaseEligible']=True;return r
        with patch('native_runner._execute',side_effect=wrong):
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
    def test_sidecar_verifies_hash_and_length_not_only_success_label(self):
        from native_runner import check_sidecar
        write_zip(self.archive,self.records)
        sha=hashlib.sha256(self.archive.read_bytes()).hexdigest()
        side=Path(str(self.archive)+'.sha256.txt')
        side.write_text(f'SHA-256: {sha}\nBYTES: {self.archive.stat().st_size}\n')
        self.assertTrue(check_sidecar(self.archive)['verified'])
        side.write_text(f'SHA-256: {sha}\nBYTES: 0\n')
        with self.assertRaises(self.Error):check_sidecar(self.archive)
    def test_windows_ambiguous_names_rejected(self):
        from audit_io import safe_relative
        for name in ['a?.py','a*.json','a|b','a<b','a>b','a"b']:
            with self.subTest(name=name),self.assertRaises(self.Error):safe_relative(name)

class ReviewedCheckoutTests(unittest.TestCase):
    def test_changed_tracked_or_untracked_material_rejects_native_execution(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        from native_runner import _check_repo
        from audit_io import AuditInputError
        with tempfile.TemporaryDirectory() as t:
            repo=Path(t)
            for name in ('AGENTS.md','CURRENT-CANDIDATE.json','tools/Build-AIAuditBundle.ps1','tools/validate_release_bundle.py','source/tools/validate_ai_audit_bundle.py'):
                p=repo/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('fixture')
            responses=[SimpleNamespace(returncode=0,stdout='a'*40+'\n'),SimpleNamespace(returncode=0,stdout=' M tools/validate_release_bundle.py\n')]
            with patch('native_runner.subprocess.run',side_effect=responses):
                with self.assertRaises(AuditInputError):_check_repo(repo,'a'*40)

class IsolatedPythonTests(unittest.TestCase):
    def test_cli_resolves_its_reviewed_siblings_under_isolated_python(self):
        import subprocess
        entry=Path(__file__).resolve().parents[1]/'scripts/audit_convergence.py'
        result=subprocess.run([sys.executable,'-I',str(entry),'--help'],capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('inspect',result.stdout)

if __name__ == '__main__':
    unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/FRESH-CAMPAIGN.md

SHA256: b17a1390b6b2aa5f949a85012763f9f5c20add30a22421a2d7f6c19fa771ca2c | Bytes: 6339 | Git mode: 100644

```
# Fresh certification campaign — September 26, 2026

Policy: `DF-FRESH-CERTIFICATION-20260926-R2`. The user directly requested a completely refreshed attempt and correction of current blockers. Source: `audit/agent-memory/attempts/DF-FRESH-CERTIFICATION-20260926-R2/USER-AUTHORIZATION.md`. This is a new prospective campaign, not a refund, reopening, or rewrite of B or earlier campaigns. Their historical consumption and missing reservations remain evidence. Do not ask the user to adopt B again or supply a nonexistent external reservation command.

Use the existing native product, proof, FullRelease and final-acceptance validators. This document and the attempt journal grant no PASS, cleanup, signature, guest-authentication, or public-publishing credit. No new product features or Command Center rewrite is on the certification path.

## Attempt accounting
The implementation uses finite fresh ceilings selected within the user's broad authorization: standard-token 3; laptop-proof 3; desktop-proof 3; fullrelease 3; diagnostic/readiness 6; separate maintenance 3; conditional build/sign 3. Read actual remaining counts from `audit/agent-memory/attempts/DF-FRESH-CERTIFICATION-20260926-R2/ledger.json`; do not copy these maxima as remaining counts.

The journal implementation is `scripts/fresh/fresh_attempts.py`. Use `status`, `reserve --request <json> --dry-run`, `reserve`, and `finish --request <json>` with `--ledger`. The R2 launch ledger is initialized once after preparation. Read CURRENT-CAMPAIGN.json; never initialize an existing ledger again. The original campaign contains preparation consumption and is preserved byte-for-byte. R2 exists because the user explicitly renewed the full allowance, not because a model, date, or session changed. A reservation is charged before invocation, even when the invocation does not start or fails early. It is not refunded. A crash retains its active reservation; reconcile its exact process and terminal evidence rather than deleting it. No concurrent lab mutators. Each reservation records owner PID/start identity, actual current tuple, unique RunId, exact entrypoint hash and arguments, material changed condition, and finite native-compatible deadline. Historical failed attempts remain unchanged. Each replay needs a corrected cause or discriminating instrumentation, not a new model or date.

## Credentials and readiness
The owner already reported a known-correct E2EAdmin refresh on September 26. Its native Dylan DPAPI store was modified at 16:47:04Z and the protected credential handle loads with the exact username. These are not authenticated guest proof. Use the native getter in elevated Dylan context without displaying or exporting password, DPAPI data, OAuth credentials, signing keys, or tokens. Do not ask for the same refresh merely because the older handoff says invalid. Do not guess, extract, reset, or weaken authentication.

`Test-CurrentGuestAccess.ps1` is an admitted read-only diagnostic for the existing Running guest. It does not stop, restore or start the VM, and cannot establish an exact CLEAN proof. `Test-DevFleetCertificationReadiness.ps1 -LiveGuestAuth -FreshLedgerPath <ledger> -FreshRunId <reserved-run>` now accepts a valid fresh diagnostic reservation; legacy unadmitted execution still fails closed. Run it only when exact L1 is Off, raw HostSafety and current qualification pass, and sole ownership is established. Successful readiness still requires authenticated exact guest identity, positive in-L1 nested L2 ABSENT and final L1 Off.

## Execution order
Finish the scoped tooling batch and regressions, freeze it, classify actual shipping/tooling impact, make one explicit-path commit, and use the supported native binder only when required. Preserve signed shipping bytes unless a demonstrated shipping defect requires a native rebuild/sign. A new HEAD can stale the standard-token receipt; requalify it honestly through the existing logged-on Developer non-admin mechanism, without changing account memberships or faking a token. Then perform independent Laptop/Surrogate and Desktop/Primary proofs, one coherent FullRelease with all existing real-use and maintenance requirements, RECONCILE, certified cleanup, native final acceptance and final RELEASE audit. Do not stitch historical phases into a new passing run.

The current user selects Sol High as root. Start with zero helpers on an executable serial gate; use a few bounded readers only for independent causal work. Astra MAX/ULTRA is optional targeted review, not a completion guarantee. Preserve AFK history and the final oracle. Record this new campaign in its queue/events instead of resetting acceptance. Use the existing read-only monitor; green means native validated current evidence, not an administrative status edit.

## Unchanged safety boundary
Only the exact disposable L1 `DevFleet-E2E-Win11-01` / `84b7d8b8-ee6c-4085-aa29-4b0adc316de2`, canonical CLEAN `19865b76-4c3a-44f7-ba39-841e9d3c40c9`, and positively owned nested `DevFleet-E2E-Linux-01` are in scope. Inspect an unexplained Running VM non-destructively before any shutdown/restore; an idle-looking PID alone is not proof of ownership. Never reboot the host, change security/trust/firewall/BIOS/GPU settings, mutate production/Surface/foreign resources, erase dirty evidence, or publish. Final acceptance must remain native, with internal promotion true only after validation and public promotion/publisher trust false.

## Verified credential history and current boundary
The August 26 recovery record shows an agent-generated random guest password saved only through the native Secrets module. The user was not expected to memorize it. On September 26 the refreshed protected store loaded successfully, but the exact currently running guest rejected it. Read-only guest Security event 4625 record 14530 at 17:59:55Z reports status 0xC000006D/substatus 0xC000006A (password mismatch); this is not a proven expiry or lockout. The guest was preserved in recovery checkpoint 5377ffb4-bb7f-446d-b1c0-20df767214c6 and then verified Off. The latest store has not yet been tested after a new canonical CLEAN restore. Do not ask for the generated password or blindly repeat authentication. Prefer legitimate native protected-store/baseline recovery; keep all security and checkpoint-identity boundaries.

```


## FILE: .agents/skills/devfleet-certification-orchestrator/SKILL.md

SHA256: ffda625a8d306d493dce3fdd6dbd668c4149f3e94e89a53f927331c58282b4ba | Bytes: 13054 | Git mode: 100644

```
---
name: devfleet-certification-orchestrator
description: Use when the user-selected Sol root owns DevFleet release certification and orchestrates Luna workers, preflight, exact proofs, FullRelease, remediation, evidence convergence, and final release acceptance.
metadata:
  short-description: Orchestrate DevFleet certification with Sol and Luna
---

# DevFleet Certification Orchestrator

## Current user-authorized fresh campaign — September 26, 2026
Read