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
