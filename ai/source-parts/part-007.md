# DevFleet source part 007

Full-source UTF-8 byte interval [279000, 325500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 364c1169d765efefe1b5af71c7dc0089471f182b30b1addadad38c2c1efc8bad

<!-- BEGIN SOURCE SLICE -->
rror('Proof lineage or role malformed')
    if final.get('runId')!=run_id or final.get('status')!='PASS' or final.get('outcome')!='PASS':raise ValueError('Proof is not terminal PASS')
    rows=binding.get('evidence');names=set();chosen=[]
    if not isinstance(rows,list) or not rows:raise ValueError('Bound native proof evidence missing')
    for row in rows:
        n=row.get('file','');h=row.get('sha256','')
        if n in names:raise ValueError('duplicate native evidence')
        names.add(n)
        if not re.fullmatch(r'product-lifecycle-(?:completion-authority|generation-[1-3])\.json',n) or not re.fullmatch(r'[0-9a-f]{64}',h):raise ValueError('Unexpected bound evidence')
        canonical=checked_path(rd,n);nested=checked_path(rd,f'lifecycle-{phase}-{lineage}/{n}')
        present=[p for p in (canonical,nested) if p.is_file()]
        if not present:raise ValueError('Missing exact lineage-bound native evidence: '+n)
        if any(digest(p)!=h for p in present):raise ValueError('Native evidence hash mismatch: '+n)
        chosen.append((present[0],n,h))
    if 'product-lifecycle-completion-authority.json' not in names:raise ValueError('Completion authority missing')
    destination.mkdir(parents=True,exist_ok=False)
    for n in ('proof-start.json','proof-final.json','cleanup-state.json'):
        shutil.copyfile(checked_path(rd,n),destination/n)
    for src,n,h in chosen:
        shutil.copyfile(src,destination/n)
        if digest(destination/n)!=h:raise ValueError('Evidence changed during copy')
    return [{'file':n,'source':p.relative_to(rd).as_posix(),'sha256':h} for p,n,h in chosen]

def select_suites(area):
    if area=='all':return [row for rows in SUITES.values() for row in rows]
    if area=='quick':return SUITES['clock']+[SUITES['observer'][1]]+SUITES['vault'][:2]+SUITES['acceptance'][:1]
    if area not in SUITES:raise ValueError('Unknown test area; no arbitrary command execution')
    return list(SUITES[area])

def source_snapshot(repo):
    rows={}
    for folder in ('source','installer-source','tools','automation'):
        base=repo/folder
        for p in sorted(base.rglob('*')):
            parts=p.relative_to(base).parts
            if any(x in ('.git','__pycache__','.pytest_cache','bin','obj','outputs','.test-runtime','Payload') or x.startswith('.venv') for x in parts):continue
            if p.is_file():
                rel=p.relative_to(repo).as_posix();checked_path(repo,rel);rows[rel]=digest(p)
    for n in ('CURRENT-CANDIDATE.json','evidence/CURRENT-RELEASE-AUTHORITY.json','evidence/CURRENT-STANDARD-TOKEN.json','finalization-state.json','outputs/final-artifact-hashes.json','audit/run-exact-candidate-proof.ps1'):
        p=checked_path(repo,n)
        if p.is_file():rows[n]=digest(p)
    return rows

def assert_authority(authority,expected):
    for k in ('repositoryHead',*TUPLE):
        if authority.get(k)!=expected.get(k):raise ValueError('Native authority tuple disagrees: '+k)
    for k,value in (('candidateIsCurrent',True),('sourceChangedSinceCandidate',False),('rebuildRequired',False)):
        if authority.get(k) is not value:raise ValueError('Native candidate flag is not current: '+k)

def native_inspection(repo):
    authority=read_json(checked_path(repo,'evidence/CURRENT-RELEASE-AUTHORITY.json'))
    before=source_snapshot(repo)
    sys.path.insert(0,str(repo/'tools'))
    try:
        spec=importlib.util.spec_from_file_location('fastlane_native_validator',checked_path(repo,'tools/validate_release_bundle.py'))
        v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
        state=v.read_json(repo/'finalization-state.json');expected=v._tuple_from_state(state);artifacts=v._artifact_map(repo)
        assert_authority(authority,expected)
        v._validate_workspace_candidate(repo,expected,artifacts)
        token=v._validate_standard_token(repo,expected,artifacts,'workspace')
        selected=authority.get('proofs',{}).get('runs',[])
        if len(selected)!=2 or len({r['runId'] for r in selected})!=2:raise ValueError('Current authority must select two independent proof RunIds')
        source_paths={
          'proofScriptSha256':'audit/run-exact-candidate-proof.ps1',
          'invokeRealProductPhaseSha256':'automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1',
          'invokeWpfUiAutomationSha256':'automation/release-e2e/modules/executors/Invoke-WpfUiAutomation.ps1',
          'wpfLaunchContractSha256':'automation/release-e2e/modules/executors/WpfLaunchContract.psm1'}
        sources={k:checked_path(repo,p) for k,p in source_paths.items()}
        pe={k:expected[k] for k in ('repositoryHead','candidateCommit','shippingInputIdentity')};pe.update(releaseFingerprint=expected['releaseFingerprintId'],toolingFingerprint=expected['toolingFingerprintId'])
        results=[]
        with tempfile.TemporaryDirectory(prefix='devfleet-readonly-revalidation-') as td:
            for row in selected:
                name=row['runId'];view=Path(td)/name;copies=proof_view(repo,name,view)
                tx,lineage,role=v.validate_native_proof(view,checked_path(repo,'source/config/devfleet.config.json'),sources,pe,{n:x['sha256'] for n,x in artifacts.items()})
                start=read_json(view/'proof-start.json');cleanup=read_json(view/'cleanup-state.json')
                results.append({'runId':name,'transactionId':tx,'lineageId':lineage,'role':role,'nativeValidation':'PASS','observedSecondsIncludingCleanup':elapsed(start.get('generatedAtUtc'),cleanup.get('completedAtUtc')),'cleanupSeconds':elapsed(cleanup.get('startedAtUtc'),cleanup.get('completedAtUtc')),'evidenceLayout':copies})
        v.validate_proof_independence([x['runId'] for x in results],[x['transactionId'] for x in results],[x['lineageId'] for x in results],[x['role'] for x in results])
        if before!=source_snapshot(repo):raise ValueError('Material/native inputs changed during revalidation')
        return {'status':'PASS','scope':'READ_ONLY_REVALIDATION','authorityId':authority['authorityId'],
          'candidate':{k:expected[k] for k in ('repositoryHead',*TUPLE)},'proofs':results,
          'standardTokenRunId':token.get('runId'),'proofIndependence':'PASS','sourceSnapshotSha256':hashlib.sha256(json.dumps(before,sort_keys=True).encode()).hexdigest(),
          'candidateRebuildRequired':authority.get('rebuildRequired'),'fullReleasePassed':authority.get('fullReleasePassed') is True,
          'newProofsProduced':0,'runtimeAuthorizationGranted':False,'next':'Fresh native host/ownership admission, then current FullRelease under existing explicit authorization. Do not rerun these proofs for a new chat.'}
    finally:sys.path.pop(0)

def standalone_python_command(python,path):
    # Embedded Windows Python ignores PYTHONPATH. Add only the trusted test's
    # directory in this child process; do not edit ._pth or global config.
    shim="import runpy,sys;from pathlib import Path;p=Path(sys.argv[1]).resolve();sys.path.insert(0,str(p.parent));sys.argv=[str(p)];runpy.run_path(str(p),run_name='__main__')"
    return [str(python),'-B','-c',shim,str(path)]

def tests(repo,area,out):
    pwsh=shutil.which('pwsh.exe') or shutil.which('pwsh')
    python=repo/'.venv-test/Scripts/python.exe'
    if not python.is_file():python=Path(sys.executable)
    before=source_snapshot(repo);results=[]
    env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1','PYTHONPATH':os.pathsep.join(str(x) for x in (repo,repo/'tools',repo/'source/app')),'PYTHONIOENCODING':'utf-8'}
    for label,kind,relative in select_suites(area):
        path=checked_path(ROOT if kind=='skill' else repo,relative)
        if kind=='pytest':cmd=[str(python),'-B','-m','pytest','-q','-p','no:cacheprovider',str(path)]
        elif kind=='python':cmd=standalone_python_command(python,path)
        else:
            if not pwsh:raise ValueError('PowerShell 7 is required; no installation attempted')
            cmd=[pwsh,'-NoLogo','-NoProfile','-NonInteractive','-File',str(path)]
            if kind=='skill':cmd+=['-Repository',str(repo)]
        t=time.monotonic();log=out/(label+'.log');source_hash=digest(path)
        with log.open('w',encoding='utf-8') as f:
            try:cp=subprocess.run(cmd,cwd=repo,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=180)
            except subprocess.TimeoutExpired:
                results.append({'suite':label,'status':'TIMEOUT','seconds':round(time.monotonic()-t,3),'log':str(log),'cleanupMustBeChecked':True});break
        results.append({'suite':label,'status':'PASS' if cp.returncode==0 else 'FAIL','exitCode':cp.returncode,'seconds':round(time.monotonic()-t,3),'log':str(log),'scriptSha256':source_hash})
        if cp.returncode!=0:break
    clean=before==source_snapshot(repo)
    return {'status':'PASS' if len(results)==len(select_suites(area)) and all(x['status']=='PASS' for x in results) and clean else 'FAIL',
            'scope':'VM_FREE_REGRESSION_ONLY','area':area,'suites':results,'materialAndNativeInputsUnchanged':clean,
            'certificationCredit':False,'vmOperations':0,'note':'Mocks/injected clocks test harness decisions; not a simulated VM certification.'}

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('command',choices=['inspect','test'])
    ap.add_argument('--repo',required=True,type=Path);ap.add_argument('--area',choices=['quick','all',*SUITES],default='quick')
    ap.add_argument('--out',type=Path,help='New diagnostic directory OUTSIDE the repository')
    a=ap.parse_args();repo=a.repo.resolve(strict=True)
    base=Path(os.environ.get('LOCALAPPDATA',tempfile.gettempdir()))/'DevFleet/Fastlane'
    out=(a.out or base/dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S-%fZ')).resolve()
    if out.is_relative_to(repo):ap.error('Diagnostic output must be outside the repository')
    out.mkdir(parents=True,exist_ok=False);start=time.monotonic()
    try:report=native_inspection(repo) if a.command=='inspect' else tests(repo,a.area,out)
    except Exception as exc:
        # Keep traceback locally, do not expose arbitrary file/credential contents.
        import traceback
        (out/'error.log').write_text(traceback.format_exc(),encoding='utf-8')
        report={'status':'FAIL','scope':'DIAGNOSTIC_ONLY','errorType':type(exc).__name__,'details':str(out/'error.log'),'certificationCredit':False,'runtimeAuthorizationGranted':False}
    report.update(observedUtc=utc(),elapsedSeconds=round(time.monotonic()-start,3),reportPath=str(out/'report.json'))
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,indent=2))
    return 0 if report['status']=='PASS' else 2
if __name__=='__main__':raise SystemExit(main())

```


## FILE: .agents/skills/devfleet-e2e-fastlane/tests/test_fastlane.py

SHA256: 3205f4695cf362414c5d97bada87326261c72e2315b628164367d5245c2e56c8 | Bytes: 8050 | Git mode: 100644

```
from __future__ import annotations
import json, hashlib, sys, importlib.util
from pathlib import Path
import pytest
ROOT=Path(__file__).resolve().parents[1]

def impl():
    p=ROOT/'scripts/fastlane.py'
    assert p.is_file(), 'Missing safe preflight/replay implementation'
    spec=importlib.util.spec_from_file_location('devfleet_fastlane',p)
    m=importlib.util.module_from_spec(spec);sys.modules[spec.name]=m;spec.loader.exec_module(m)
    return m

def put(p,obj):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(obj),encoding='utf-8');return p

def fixture(tmp_path):
    r=tmp_path/'repo';r.mkdir();name='e2e-exact-candidate-proof-fixture';rd=r/'audit/automation-harness/runs'/name
    lineage='a'*32
    names=['product-lifecycle-completion-authority.json','product-lifecycle-generation-1.json']
    rows=[]
    for n in names:
        p=put(rd/f'lifecycle-REBOOT-RESUME-{lineage}'/n,{'fixture':True,'name':n})
        rows.append({'file':n,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    put(rd/'proof-final.json',{'runId':name,'status':'PASS','outcome':'PASS','role':'Primary / Desktop','proofBinding':{'phaseId':'REBOOT-RESUME','checkpointLineageId':lineage,'evidence':rows}})
    put(rd/'proof-start.json',{'runId':name});put(rd/'cleanup-state.json',{'status':'PASS'})
    return r,name,rd,rows

@pytest.mark.parametrize('bad',['../x','/root/x','C:/x','a/../x','a\\..\\x','a//x','./x','a:x',''])
def test_path_escape_rejected(tmp_path,bad):
    m=impl()
    with pytest.raises(ValueError):m.checked_path(tmp_path,bad)

def test_symlink_refused(tmp_path):
    m=impl();p=tmp_path/'target';p.write_text('x');s=tmp_path/'link'
    try:s.symlink_to(p)
    except OSError:pytest.skip('symlink permission unavailable')
    with pytest.raises(ValueError):m.checked_path(tmp_path,'link')

def test_lineage_view_is_nonmutating(tmp_path):
    m=impl();r,n,rd,rows=fixture(tmp_path);before={str(p):p.read_bytes() for p in rd.rglob('*') if p.is_file()}
    view=tmp_path/'view'/n;m.proof_view(r,n,view)
    assert (view/rows[0]['file']).is_file()
    assert {str(p):p.read_bytes() for p in rd.rglob('*') if p.is_file()}==before
    assert not (rd/rows[0]['file']).exists()

def test_wrong_existing_canonical_not_silently_repaired(tmp_path):
    m=impl();r,n,rd,rows=fixture(tmp_path);put(rd/rows[0]['file'],{'tampered':True})
    with pytest.raises(ValueError,match='hash'):m.proof_view(r,n,tmp_path/'view'/n)

def test_foreign_lineage_cannot_satisfy_receipt(tmp_path):
    m=impl();r,n,rd,rows=fixture(tmp_path)
    (rd/('lifecycle-REBOOT-RESUME-'+'a'*32)).rename(rd/('lifecycle-REBOOT-RESUME-'+'b'*32))
    with pytest.raises((ValueError,FileNotFoundError)):m.proof_view(r,n,tmp_path/'view'/n)

def test_duplicate_bound_file_rejected(tmp_path):
    m=impl();r,n,rd,rows=fixture(tmp_path);f=json.loads((rd/'proof-final.json').read_text());f['proofBinding']['evidence'].append(rows[0]);put(rd/'proof-final.json',f)
    with pytest.raises(ValueError,match='duplicate'):m.proof_view(r,n,tmp_path/'view'/n)

def test_proof_destination_inside_evidence_denied(tmp_path):
    m=impl();r,n,rd,rows=fixture(tmp_path)
    with pytest.raises(ValueError):m.proof_view(r,n,rd/'view')

@pytest.mark.parametrize('kind',['true-string','stale','missing','wrong-id','missing-tuple'])
def test_checkpoint_cannot_gain_diagnostic_reuse_from_weak_identity(tmp_path,kind):
    m=impl();a={k:'a'*64 for k in m.TUPLE};a['candidateCommit']='b'*40
    manifest={'candidateTuple':dict(a),'l1Id':m.L1,'checkpointId':'c'*8+'-cccc-cccc-cccc-'+'c'*12,'configured':True,'phase':'MAINTENANCE-READY','sourceRunId':'fullrelease-fixture'}
    if kind=='true-string':manifest['configured']='true'
    if kind=='stale':manifest['candidateTuple']['toolingFingerprintId']='0'*64
    if kind=='missing':manifest.pop('configured')
    if kind=='wrong-id':manifest['l1Id']='not-the-lab'
    if kind=='missing-tuple':manifest['candidateTuple'].pop('shippingInputIdentity')
    out=m.checkpoint_assessment(a,manifest)
    assert out['diagnosticReusable'] is False and out['certificationCredit'] is False

def test_matching_checkpoint_is_diagnostic_only():
    m=impl();a={k:'a'*64 for k in m.TUPLE};a['candidateCommit']='b'*40
    z=m.checkpoint_assessment(a,{'candidateTuple':dict(a),'l1Id':m.L1,'checkpointId':'cccccccc-cccc-cccc-cccc-cccccccccccc','configured':True,'phase':'MAINTENANCE-READY','sourceRunId':'fullrelease-fixture'})
    assert z['diagnosticReusable'] and not z['certificationCredit'] and z['requiresFreshNativeIdentityCheck']

def test_timestamp_offsets_and_negative_span():
    m=impl();assert m.elapsed('2026-09-23T03:00:00-05:00','2026-09-23T08:14:25.5000000Z')==865.5
    assert m.elapsed('2026-09-23T08:00:00Z','2026-09-23T07:00:00Z') is None
    assert m.elapsed(None,'2026-09-23T08:00:00Z') is None
    assert m.elapsed('2026-09-23T08:00:00','2026-09-23T09:00:00Z') is None

def test_fail_closed_json(tmp_path):
    m=impl();p=tmp_path/'bad.json';p.write_text('{"a":true,"a":false}')
    with pytest.raises(ValueError):m.read_json(p)
    p.write_text('{"n":NaN}')
    with pytest.raises(ValueError):m.read_json(p)
    p.write_text('x'*100)
    with pytest.raises(ValueError):m.read_json(p,max_bytes=50)

def test_suite_allowlist_and_no_live_entrypoints():
    m=impl()
    assert m.select_suites('observer') and m.select_suites('vault')
    with pytest.raises(ValueError):m.select_suites('FullRelease')
    flat=' '.join(str(x) for x in m.select_suites('all'))
    for unsafe in ['run-exact-candidate-proof.ps1','Invoke-DevFleetReleaseE2E.ps1','Test-InstallerSelfTestStandardToken.ps1','Build-Release.ps1']:
        assert unsafe not in flat

def test_instruction_covers_pressure_scenarios():
    p=ROOT/'SKILL.md';assert p.exists(),'Missing discoverable skill'
    s=p.read_text();assert 'name: devfleet-e2e-fastlane' in s
    for word in ['ClockProvider','READ_ONLY_REVALIDATION','no release credit','same candidate','security scan','no raw','checkpoint']:
        assert word.lower() in s.lower(),word
    assert len(s.split())<650


def test_standalone_contract_scripts_are_not_false_pytest_passes():
    m=impl();rows={n:(kind,path) for n,kind,path in m.select_suites('all')}
    assert rows['release-validator'][0]=='python'
    assert rows['final-acceptance'][0]=='python'
    assert rows['proof-validator'][0]=='pytest'


@pytest.mark.parametrize('fault',['wrong-tuple','string-flag','missing-flag'])
def test_authority_disagreement_cannot_reuse_proofs(fault):
    m=impl();expected={k:'b'*64 for k in ('repositoryHead',*m.TUPLE)}
    a={**expected,'candidateIsCurrent':True,'sourceChangedSinceCandidate':False,'rebuildRequired':False}
    if fault=='wrong-tuple':a['toolingFingerprintId']='c'*64
    if fault=='string-flag':a['rebuildRequired']='false'
    if fault=='missing-flag':a.pop('candidateIsCurrent')
    with pytest.raises(ValueError):m.assert_authority(a,expected)


def test_standalone_script_can_import_trusted_neighbor_in_isolated_python(tmp_path):
    import subprocess
    m=impl();(tmp_path/'neighbor.py').write_text('VALUE=7\n')
    script=tmp_path/'entry.py';script.write_text('from neighbor import VALUE;assert VALUE==7;print("ISOLATED_OK")\n')
    cmd=m.standalone_python_command(Path(sys.executable),script)
    cp=subprocess.run(cmd[:1]+['-I']+cmd[1:],capture_output=True,text=True,timeout=10)
    assert cp.returncode==0,cp.stderr
    assert cp.stdout.strip()=='ISOLATED_OK'


def test_pytest_child_disables_bytecode_even_when_environment_ignored(tmp_path,monkeypatch):
    import subprocess
    m=impl();repo=tmp_path/'repo';repo.mkdir();(repo/'sample.py').write_text('pass\n');out=tmp_path/'out';out.mkdir();calls=[]
    monkeypatch.setattr(m,'select_suites',lambda area:[('sample','pytest','sample.py')])
    monkeypatch.setattr(m,'source_snapshot',lambda root:{})
    def invoke(cmd,**kwargs):
        calls.append(cmd);return subprocess.CompletedProcess(cmd,0)
    monkeypatch.setattr(m.subprocess,'run',invoke)
    assert m.tests(repo,'fixture',out)['status']=='PASS'
    assert '-B' in calls[0]

```


## FILE: .agents/skills/devfleet-evidence-triage/SKILL.md

SHA256: 2fb2928548a51f5bcdf43a3059a097db21d8ea2be7ad82e21e50a6874369a7bb | Bytes: 2091 | Git mode: 100644

```
---
name: devfleet-evidence-triage
description: Read and reconcile DevFleet release evidence without mutating the lab, candidate, or promotion state. Use for status checks, stale/conflicting summaries, blocker diagnosis, or deciding which evidence is authoritative.
metadata:
  short-description: Reconcile DevFleet release evidence read-only
---

# DevFleet evidence triage

This skill is read-only. Do not launch proof, rebuild, reserve attempts, clean labs, refresh
credentials, edit authority, or mutate release state.

Read the smallest set needed, preferring current native surfaces:
- `evidence/CURRENT-STATUS.json` for current high-level status and candidate binding.
- `evidence/CURRENT-GATES.json` for current gate detail.
- `evidence/FULLRELEASE-SUMMARY.json` for the active FullRelease run and phase.
- `evidence/CURRENT-RELEASE-AUTHORITY.json` when authority detail is needed.
- `finalization-state.json` only as a compatibility/closeout summary; compare timestamps
  and authority IDs before treating it as current.

Apply the precedence rules in
[references/evidence-precedence.md](references/evidence-precedence.md).

Report:
1. candidate/tooling identity coherence;
2. newest authority timestamp and ID;
3. proofs passed/required;
4. active FullRelease run, last completed phase, and current phase;
5. earliest incomplete/failed gate;
6. cleanup/HOST-SAFETY state when available;
7. whether any file is stale or contradictory;
8. the single next safe action.

Never promote a release from inference. If evidence disagrees, say which surface is newer,
which one is stale/secondary, and what must be refreshed or reconciled.

## Fast prior-proof revalidation

For exact proof files stored in a phase/lineage subdirectory or repeated candidate/token checks, use the `inspect` command in [devfleet-e2e-fastlane](../devfleet-e2e-fastlane/SKILL.md). It invokes unchanged native validators against a temporary, hash-bound view outside the checkout. It creates no proof or native authority and cannot start a VM. Do not invoke a mutating finalizer merely to repair a stale display.

```


## FILE: .agents/skills/devfleet-evidence-triage/agents/openai.yaml

SHA256: d68a754dd28794d3db78fea95785206b0312515c8874d1fa3a7d2b34e8e9548d | Bytes: 306 | Git mode: 100644

```
interface:
  display_name: "DevFleet Evidence Triage"
  short_description: "Read-only DevFleet authority reconciliation"
  default_prompt: "Use $devfleet-evidence-triage to reconcile the current DevFleet release status and identify the earliest truthful blocker."
policy:
  allow_implicit_invocation: true

```


## FILE: .agents/skills/devfleet-evidence-triage/references/evidence-precedence.md

SHA256: e2cb5d92a183d3398b69ffde70f4a01d48a72b2908bad7a593a892b50a0c2e27 | Bytes: 975 | Git mode: 100644

```
# Evidence precedence

Use matching `authorityId`, exact candidate tuple, and newest `generatedAtUtc` together;
do not choose a file by filename alone.

Preferred current surfaces:
1. current release authority and CURRENT-GATES for gate/promotion truth;
2. CURRENT-STATUS for concise current state;
3. FULLRELEASE-SUMMARY for active FullRelease phase/run detail;
4. native run evidence for a specific RunId;
5. finalization-state as a derived compatibility/closeout view;
6. Markdown handoffs/memory as navigation only;
7. historical audit bundles only for historical facts.

A newer file does not override a different candidate tuple. A matching tuple with an older
authority ID can still be stale. Diagnostic-only evidence never earns release proof.

When a derived summary conflicts with current authority, preserve both facts: identify the
derived summary as stale/secondary and use current native authority for the operative
status. Do not edit anything in triage mode.

```


## FILE: .agents/skills/devfleet-release-control/SKILL.md

SHA256: 29f649e50449bd3b631b3da41c4d9ae18e79d4d67b73afa994af28e45708ebc1 | Bytes: 3687 | Git mode: 100644

```
---
name: devfleet-release-control
description: Continue, repair, certify, pause, or hand off the DevFleet v1.2.13 release campaign using current native authority and evidence-preserving corrections. Use for DevFleet release execution; not for feature development or production deployment.
metadata:
  short-description: Operate DevFleet release certification safely
---

# DevFleet release control

Treat this as an execution skill for the existing DevFleet release system, not permission
to redesign the product or weaken certification. Start at
`docs/ai/devfleet-release/START-HERE.md` and reconcile current machine-readable authority
before acting.

At session entry:
1. Read the root `AGENTS.md`.
2. Read `START-HERE.md`, `SAFETY-AND-AUTHORITY.md`, `WORKFLOW.md`, and `DONE.md`.
3. Read `audit/agent-memory/CURRENT.md` only as an index.
4. Read live authority/evidence for the current candidate and identify the earliest
   incomplete truthful gate.
5. If campaign E is adopted, route through
   `docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/START.md`.

Use native machine-readable authority for candidate identity, gate state, reservations,
RunIds, cleanup, and promotion. Markdown summaries and historical evidence never promote
a release.

For immutable release truth and host-safety boundaries, read
[references/authority-and-safety.md](references/authority-and-safety.md).
For harness/gate-mechanics repairs and corrective attempts, read
[references/correction-and-attempts.md](references/correction-and-attempts.md).

For pause, handoff, memory, and final packaging, read
[references/closeout-and-memory.md](references/closeout-and-memory.md).

## Execution loop

Reconcile live authority → diagnose the earliest failed/incomplete gate read-only →
make the smallest causal mechanics correction when justified → run focused regression
tests → reserve one bounded attempt in native state → fresh preflight → execute →
terminalize/verify cleanup → reconcile native authority again.

Do not spend another VM/lab cycle on an unchanged cause. A passing diagnostic, launcher
probe, source test, or fixture is not installed-product proof. Prefer a qualifying real
lifecycle run when prerequisites are already satisfied.

The primary/root agent is the single authoritative writer and lab operator. Helpers may
perform independent read-only analysis, code tracing, and focused review within the live
delegation limits, but may not become competing owners of the lab or promotion state.

After a meaningful result, update durable memory and the next action in the same turn.
On a real pause, blocker, or success, follow `CLOSEOUT.md`. Never create final acceptance
or claim `PASS — INTERNAL RELEASE ELIGIBLE` unless current native authority itself says so.

When the user asks only for status, prefer the reusable `$release-live-monitor` skill or
the project evidence triage skill instead of mutating release state. For DevFleet's compact
live panel, run `.agents/skills/devfleet-release-control/scripts/Watch-ReleaseStatus.ps1`;
use `-Once` for a snapshot.

## Fast VM-free feedback before another lab attempt

For slow lifecycle/reboot debugging, evidence-layout mismatches or a proposed proof rerun, use [devfleet-e2e-fastlane](../devfleet-e2e-fastlane/SKILL.md). Revalidate the current signed candidate and existing proof/token binding first; do not repeat a valid proof for a new model, conversation or skill change. Select only the relevant mocked/injected-clock regression area. These tests grant no certification or live-start authorization. The current user-selected ROOT remains sole operator; historical model names are not a reason to switch it.

```


## FILE: .agents/skills/devfleet-release-control/agents/openai.yaml

SHA256: 49b526441ecd2a98daf42d28982fef0a193f25324757bf446d67f870807ef266 | Bytes: 315 | Git mode: 100644

```
interface:
  display_name: "DevFleet Release Control"
  short_description: "Run DevFleet certification from live authority"
  default_prompt: "Use $devfleet-release-control to continue the current DevFleet release certification from the earliest truthful incomplete gate."
policy:
  allow_implicit_invocation: true

```


## FILE: .agents/skills/devfleet-release-control/references/authority-and-safety.md

SHA256: 3c01ba6afa7fc2734a3157c3e90363b0e24dcaf79e5d60c164e66cde0b67c5ee | Bytes: 1487 | Git mode: 100644

```
# Authority and safety

Use current native machine-readable evidence as the source of truth. Reconcile the exact
candidate/shipping/tooling tuple before mutation and after every material correction.

Immutable release truth includes candidate identity, Authenticode/payload integrity,
HOST-SAFETY, protected-resource fencing, authentication, ownership, role coverage,
authenticated health, destructive-action scope, U01-U05 semantics, maintenance 5/5,
RECONCILE, certified CLEANUP, RELEASE-mode audit, and final internal-release authority.

Never lower, skip, relabel, synthesize, or satisfy those gates from diagnostic evidence.
UNKNOWN, timeout, NOT_OBSERVED, stale evidence, or an unavailable authority refresh must
remain non-PASS.

A material change to shipping inputs, candidate/tooling identity, proof/observer/harness
mechanics, acceptance schema, role mapping, or evidence semantics invalidates dependent
proof until native requalification binds the new tuple.

Before lab mutation require fresh ownership, exact candidate tuple, and HOST-SAFETY.
“Terminally clean” requires fresh native confirmation of exact L1 identity OFF, exact owned
L2 ABSENT, no campaign owner/process, canonical CLEAN intact/restored, and timestamped
HOST-SAFETY.

Never reboot MULATTOTECHBOX; never touch AMD/BIOS, the Surface/failover system, protected
resources, production, or F-005. Do not expose secrets, export signing keys, disable
security, or push externally unless separately authorized.

```


## FILE: .agents/skills/devfleet-release-control/references/closeout-and-memory.md

SHA256: 6fb9795be3ae6bb824660b21e3f7a6472967e367b6f19d3a29c8b32fe3b7074b | Bytes: 1293 | Git mode: 100644

```
# Closeout, handoff, and memory

After every meaningful result, keep the project’s durable memory aligned with native
evidence. Memory is a navigation aid, not release authority.

Update the appropriate attempt/incident/session memory and `audit/agent-memory/CURRENT.md`
with the verified boundary, exact RunId/tuple when relevant, what changed, focused tests,
terminal cleanup state, and the single next action. Avoid broad narrative duplication.

Before a pause or handoff:
- quiesce helpers before lab mutation boundaries;
- leave no ambiguous owner or background campaign process;
- verify terminal cleanup from native evidence;
- preserve the failed/passed RunIds and evidence lineage;
- identify the earliest truthful incomplete gate;
- package a fresh audit bundle when CLOSEOUT requires one.

At success, follow `DONE.md` literally and verify current native authority reports
`PASS — INTERNAL RELEASE ELIGIBLE`. Do not infer success from proof counts, an audit ZIP,
a locally passing validator, or a stale finalization summary.

At a blocker, report the smallest actionable boundary and whether it is engineering,
external-action, safety/ownership, credential, or promotion-scope related. Do not create a
new long audit when a precise existing artifact already proves the blocker.

```


## FILE: .agents/skills/devfleet-release-control/references/correction-and-attempts.md

SHA256: 8b37e510ef396a1f1b2be542ca2f042fffd3c6d138b9981f09782f746bacbfc5 | Bytes: 2007 | Git mode: 100644

```
# Corrections and bounded attempts

## Mutable mechanics

Mechanics may be changed only when a causal failure is demonstrated and the correction
improves observation/recovery without making acceptance easier. Examples include bounded
retry counts, timeouts, no-progress budgets, observer race handling, transport recovery,
staging/cleanup implementation, error classification, and phase ordering.

A mechanics change must not widen an effective acceptance window, alter required phase
dependencies, broaden evidence/role equivalence, suppress a terminal state, or turn
UNKNOWN/timeout/NOT_OBSERVED/diagnostic evidence into PASS.

For each correction record: observed boundary, falsifiable cause, changed files, focused
regression, preserved invariant, and why release truth is not weakened. Preserve the failed
RunId. Recompute/invalidate dependent evidence when the change is material.

## Corrective attempts

A continuation request authorizes bounded in-scope engineering work, not unlimited retries.
Reserve another attempt only when the prior run is terminally clean, a changed falsifiable
condition exists, focused checks pass, live authority/candidate/ownership/HOST-SAFETY are
fresh, and the native attempt ledger can atomically record the new attempt.

Each reservation needs a unique RunId, exact tuple, owner, budget, cleanup plan, stop
condition, policy/counter allocation, and tri-state productStarted field. Markdown may
mirror but never authorize it.

Do not reset or erase historical counters. Do not retry an unchanged cause. If the user
grants a finite number of tries, stay inside that envelope. Without an explicit number,
use no more than five attempts for one newly proven causal boundary or the smaller native
policy remainder.

Stop for genuinely external choices/actions, missing credentials, browser approval,
unsafe/unknown host state, protected-resource conflict, ambiguous ownership, invalid
candidate, human-only observation, or a product-requirement/promotion-scope decision.

```


## FILE: .agents/skills/devfleet-release-control/references/release-monitor.json

SHA256: 1e53026f4c1a8da5a698e434cc257ca464094ed8dab31080aa1b55c111f043db | Bytes: 2814 | Git mode: 100644

```
{
  "title": "DEVFLEET v1.2.13 RELEASE MONITOR  [read-only]",
  "sources": {
    "status": "evidence/CURRENT-STATUS.json",
    "full": "evidence/FULLRELEASE-SUMMARY.json",
    "final": "finalization-state.json"
  },
  "headline": {
    "label": "Overall",
    "source": "status",
    "path": "blockerClassification",
    "kind": "status"
  },
  "rows": [
    {
      "label": "Candidate current",
      "source": "status",
      "path": "candidateIsCurrent",
      "kind": "bool"
    },
    {
      "label": "Source unchanged",
      "source": "status",
      "path": "sourceChangedSinceCandidate",
      "kind": "bool",
      "trueMeansPass": false
    },
    {
      "label": "No rebuild required",
      "source": "status",
      "path": "rebuildRequired",
      "kind": "bool",
      "trueMeansPass": false
    },
    {
      "label": "Current proof",
      "source": "status",
      "path": "currentProofOutcome",
      "kind": "status"
    },
    {
      "label": "Proofs passed",
      "source": "status",
      "path": "proofsPassed",
      "kind": "text"
    },
    {
      "label": "Proofs required",
      "source": "status",
      "path": "proofsRequired",
      "kind": "text"
    },
    {
      "label": "FullRelease",
      "source": "full",
      "path": "status",
      "kind": "status"
    },
    {
      "label": "Last completed phase",
      "source": "full",
      "path": "lastCompletedPhase",
      "kind": "complete"
    },
    {
      "label": "Current phase",
      "source": "full",
      "path": "currentPhase",
      "kind": "phase"
    },
    {
      "label": "Finalizer blocker",
      "source": "final",
      "path": "finalizer_primary_blocker",
      "kind": "status"
    },
    {
      "label": "FullRelease passed",
      "source": "status",
      "path": "fullReleasePassed",
      "kind": "bool"
    },
    {
      "label": "Internal promotion",
      "source": "status",
      "path": "internalPromotionAllowed",
      "kind": "bool"
    },
    {
      "label": "Production unchanged",
      "source": "status",
      "path": "productionUnchanged",
      "kind": "bool"
    },
    {
      "label": "Surface untouched",
      "source": "status",
      "path": "mulattoTechSurfaceTouched",
      "kind": "bool",
      "trueMeansPass": false
    }
  ],
  "footerPaths": [
    {
      "label": "Proof RunId",
      "source": "status",
      "path": "currentProofRunId"
    },
    {
      "label": "FullRelease RunId",
      "source": "status",
      "path": "fullReleaseRunId"
    },
    {
      "label": "Next action",
      "source": "status",
      "path": "nextAction"
    },
    {
      "label": "Authority",
      "source": "status",
      "path": "authorityId"
    },
    {
      "label": "Updated UTC",
      "source": "status",
      "path": "generatedAtUtc"
    }
  ]
}
```


## FILE: .agents/skills/devfleet-release-control/scripts/Watch-ReleaseStatus.ps1

SHA256: d4a7b077c95c5ad3c35e68a5a174070b24f6c4eeb9f7276b7f9d1a55a9d94ed5 | Bytes: 652 | Git mode: 100644

```
#requires -Version 7.0
# Read-only observer adapter. Native release state remains the authority.
param(
 [string]$Root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path,
 [ValidateRange(1,300)][int]$IntervalSeconds=3,[switch]$Once,[switch]$Json
)
$ErrorActionPreference='Stop'
$observer='C:\Users\Dylan\AppData\Local\DevFleet\ReleaseContinuation\20260922\Watch-ReleaseStatus.ps1'
if(-not(Test-Path -LiteralPath $observer -PathType Leaf)){throw 'Continuation monitor missing. Restore the previous monitor using Restore-PreviousMonitor.ps1 in the support kit.'}
& $observer -Root $Root -IntervalSeconds $IntervalSeconds -Once:$Once -Json:$Json

```


## FILE: .gitattributes

SHA256: 54a39a8a0708df4e5f424b067a10d51476f2b53186463f8122adcabeda0fe221 | Bytes: 149 | Git mode: 100644

```
/.gitattributes text eol=lf
/automation/** text eol=lf
/source/** text eol=lf
/tools/** text eol=lf
/audit/run-exact-candidate-proof.ps1 text eol=lf

```


## FILE: .gitignore

SHA256: 1c0408e6b1dcbdc87c096f2d3c5cd9b5beb7dab136aa41522660491738ab3b89 | Bytes: 509 | Git mode: 100644

```
# Generated release and audit state
outputs/
audit/
windows-e2e/evidence/
windows-e2e/run-state/
*.run-state.json
run-state.json

# Local SDKs, environments, caches, and build output
.dotnet/
.venv-test/
**/.venv-test-*/
.venv/
__pycache__/
*.py[cod]
.pytest_cache/
**/.test-runtime/
bin/
obj/
build/
dist/
node_modules/
dependency-cache/
test-downloads/

# Local secrets and credentials
credentials/
secrets/
*.dpapi
*.secret
*.token
*.pem
*.key

# Temporary tooling artifacts
dotnet-install.ps1
*.tmp
*.log

```


## FILE: AGENTS.md

SHA256: c400e6d8bb435195c2004a12c8b13cd8027b5f74f07160afe114cfdd1cbeb447 | Bytes: 3840 | Git mode: 100644

```
<!-- BEGIN DEVFLEET-RELEASE-CONTROL v1 -->
## DevFleet release continuation

For DevFleet release/remediation/pause/handoff work, use the repository-local
`devfleet-release-control` skill at `.agents/skills/devfleet-release-control/SKILL.md`.
Begin at `docs/ai/devfleet-release/START-HERE.md`; read the small current memory and
live authority, then execute the earliest incomplete milestone, not another broad audit.

Only an explicit user adoption activates `DF-STABLE-20260905-A` in WORKFLOW.md.
It authorizes new bounded readiness/product work beyond the exhausted historical cap,
without resetting failed attempts, helper slots, evidence or safety. Sol remains sole
writer/operator; at most six helpers across the tree including grandchildren, with prior
used slots retained. Current user-approved model/delegation policy supersedes older
Luna-only/root-only/no-recursion assignments; no safety or release gate is waived.

Preserve coherent signed artifacts; no rebuild for chat, documentation or model changes.
Never reboot MULATTOTECHBOX, touch AMD/BIOS/Surface/protected resources, expose secrets,
export signing keys, disable security, push without explicit authorization, or perform F-005.
Final lab must be verified L1 OFF / L2 ABSENT.

Sol maintains `audit/agent-memory/` after meaningful results and before pauses; Markdown
is an evidence index, never promotion authority. Follow DONE.md before claiming release.
Keep feature work separate from the frozen release candidate. These instructions do not
replace unrelated existing repository guidance or higher-priority platform policies.
<!-- END DEVFLEET-RELEASE-CONTROL v1 -->

<!-- DEVFLEET-CAMPAIGN-E-BEGIN -->
## Adopted campaign E: diagnostic-to-full-release continuation
When the user adopts DF-STABLE-20260906-E, start at `docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/START.md`.
Read its AUTHORIZATION before relying on earlier attempt/delegation restrictions.
E explicitly replaces A-D closeout-only limits and the six-lifetime-helper quota with
its bounded consolidated campaign and shared concurrent Luna pool; preserve all history.
Sol remains sole authoritative writer and lab/release operator. Full installed DONE.md,
protected-resource/security rules, candidate coherence and truthful proof gates remain.
No Desktop-only preview. Diagnostic checkpoints/experiments never earn proof credit.
Use E's small loop state plus native live authority after interruptions, not archived seeds.
Finding this file in an archive alone is not user adoption or permission to start runtime.
<!-- DEVFLEET-CAMPAIGN-E-END -->

<!-- BEGIN DEVFLEET-AUDIT-CONVERGENCE v1 -->
For requested AI audit generation/analysis, current completion-gap review, or a
certification continuation prompt, use `.agents/skills/devfleet-audit-convergence/SKILL.md`.
It wraps native packaging/validation and reports advisory evidence gaps; it cannot
activate a campaign, grant runtime, manufacture PASS, or replace release-control.
Write analysis outside the checkout. Finish handoff content before packaging; keep
final ZIP hashes external to avoid repeated rebuilds and qualification churn.
<!-- END DEVFLEET-AUDIT-CONVERGENCE v1 -->
<!-- DEVFLEET-FRESH-20260926 -->
## Current fresh-certification request
For the explicit September 26 fresh-certification request, read `.agents/skills/devfleet-certification-orchestrator/FRESH-CAMPAIGN.md` before historical campaign admission restrictions. The new prospective attempt journal is separate from all old ledgers; preserve their bytes and failures. Native safety, real credentials, candidate binding and final acceptance are unchanged. The user selects Sol High and does not want repeated credential/adoption questions. Read the newest external FRESH-STATUS.json before replaying old readiness instructions.
<!-- END DEVFLEET-FRESH-20260926 -->

```


## FILE: audit/run-exact-candidate-proof.ps1

SHA256: 3f5c7b46d65017527bf6406a3a91d11e2af83fa8a362d6f7c3c642e17b0990ab | Bytes: 17520 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [switch]$AllowRamPressure,
    [switch]$DiagnosticOnly,
    [switch]$LaptopSurrogate
)

$ErrorActionPreference = 'Stop'
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$scriptRoot = Join-Path $WorkspaceRoot 'automation\release-e2e'
$vmId = [guid]'84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
$cleanId = [guid]::Empty
$cleanName = $null
$baseline = $null
$l2Name = 'DevFleet-E2E-Linux-01'
$candidatePath = Join-Path $WorkspaceRoot 'outputs\DevFleet-Setup-v1.2.13-win-x64.exe'
$evidenceModulePath=Join-Path $scriptRoot 'modules\Evidence.psm1'
Import-Module $evidenceModulePath -Force
$pythonRuntimeModulePath=Join-Path $WorkspaceRoot 'tools\PythonRuntime.psm1'
Import-Module $pythonRuntimeModulePath -Force
$python=Resolve-DevFleetPython -Workspace $WorkspaceRoot
$runDir = New-RunEvidenceDirectory -WorkspaceRoot $WorkspaceRoot -RunId $RunId
$vm = $null
$result = $null
$proofExitCode = 0
$cleanupAttempted = $false
$proofRole = if($LaptopSurrogate){'Laptop / Surrogate'}else{'Primary / Desktop'}
$proofPhase = if($LaptopSurrogate){'SURROGATE-DISPOSABLE'}else{'REBOOT-RESUME'}
function Set-CurrentProofPointer([string]$Outcome) {
    $statePath=Join-Path $WorkspaceRoot 'finalization-state.json'
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){return}
    $state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
    $state.current_proof_run_id=$RunId;$state.current_proof_outcome=$Outcome;$state.current_proof_updated_utc=(Get-Date).ToUniversalTime().ToString('o')
    if($DiagnosticOnly){$state.current_diagnostic_run_id=$RunId;$state.diagnostic_run_ids=@(@($state.diagnostic_run_ids)+$RunId|Where-Object{$_}|Select-Object -Unique)}
    else{$state.proof_run_ids=@(@($state.proof_run_ids)+$RunId|Where-Object{$_}|Select-Object -Unique)}
    $tmp="$statePath.$([guid]::NewGuid().ToString('N')).tmp"
    try{[IO.File]::WriteAllText($tmp,(($state|ConvertTo-Json -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $tmp -Destination $statePath -Force}
    finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
}

Import-Module (Join-Path $scriptRoot 'modules\Candidate.psm1') -Force
Import-Module $evidenceModulePath -Force
Import-Module (Join-Path $scriptRoot 'modules\Cleanup.psm1') -Force
Import-Module (Join-Path $scriptRoot 'modules\GuestSession.psm1') -Force
Import-Module (Join-Path $scriptRoot 'modules\executors\Invoke-RealProductPhase.psm1') -Force
Import-Module (Join-Path $scriptRoot 'modules\HostSafety.psm1') -Force
Import-Module (Join-Path $scriptRoot 'modules\Secrets.psm1') -Global -Force
Import-Module (Join-Path $scriptRoot 'modules\FullRelease.psm1') -Global -Force
Import-Module (Join-Path $scriptRoot 'modules\Evidence.psm1') -Global -Force
Import-Module (Join-Path $scriptRoot 'modules\HarnessBudget.psm1') -Global -Force

function Invoke-ExactProofCleanup([Parameter(Mandatory)][psobject]$Vm) {
    $cleanup=[ordered]@{runId=$RunId;status='INCOMPLETE';runOwnedOnly=$true;cleanupOwner='run-exact-candidate-proof.ps1';startedAtUtc=(Get-Date).ToUniversalTime().ToString('o');l2=$null;l2Present=$null;l1=$null}
    $cleanupSession=$null
    try {
        if(-not $baseline){throw 'Accepted baseline was not bound before proof cleanup.'}
        $current=Get-VM -Id $vmId -ErrorAction Stop
        if([string]$current.Name -cne 'DevFleet-E2E-Win11-01' -or $current.Id -ne $vmId){throw 'Exact L1 cleanup identity mismatch.'}
        $snapshot=Get-ExactCheckpoint -Vm $current -Name $cleanName
        if($snapshot.Id -ne $cleanId){throw 'Exact canonical CLEAN cleanup identity mismatch.'}
        $cleanup.restore=Restore-ExactCheckpoint -Vm $current -Name $cleanName -StartAfterRestore
        Import-Module (Join-Path $scriptRoot 'modules\GuestSession.psm1') -Global -Force
        $cleanupSession=GuestSession\Connect-DevFleetGuest -VmId $vmId
        $cleanup.l2=GuestSession\Get-DevFleetNestedL2State -Session $cleanupSession -ExpectedName $l2Name
        if([string]$cleanup.l2.status -ne 'ABSENT'){throw "Exact nested L2 cleanup state was not ABSENT: $([string]$cleanup.l2.status)"}
        $cleanup.l2Present=$false
        $cleanup.status='PASS'
    } catch {
        $cleanup.status='BLOCKED'
        $cleanup.error=$_.Exception.Message
    } finally {
        if($cleanupSession){Remove-PSSession $cleanupSession -ErrorAction SilentlyContinue}
        try {
            $finalVm=Get-VM -Id $vmId -ErrorAction Stop
            if([string]$finalVm.Name -cne 'DevFleet-E2E-Win11-01' -or $finalVm.Id -ne $vmId){throw 'Final L1 cleanup identity mismatch.'}
            if($finalVm.State -ne 'Off'){Stop-VM -VM $finalVm -Force -Confirm:$false -ErrorAction Stop}
            $deadline=(Get-Date).AddMinutes(2)
            do{Start-Sleep -Seconds 2