#!/usr/bin/env python3
"""VM-free DevFleet diagnostics. No command here authorizes or launches a lab.

Native validators remain authoritative; fixture and replay results earn no credit.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
TUPLE = ('candidateCommit','shippingInputIdentity','releaseFingerprintId','toolingFingerprintId')
L1 = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
ROLES = {'Primary / Desktop':'REBOOT-RESUME','Laptop / Surrogate':'SURROGATE-DISPOSABLE'}
ROOT = Path(__file__).resolve().parents[1]
SUITES = {
 'clock': [('virtual-clock','skill','scripts/Test-VirtualClock.ps1')],
 'observer': [('lifecycle','ps','automation/release-e2e/tests/Test-LifecycleObserverBehavior.ps1'),
              ('wpf','ps','automation/release-e2e/tests/Test-WpfLaunchBoundaryBehavior.ps1'),
              ('launch-deferral','ps','automation/release-e2e/tests/Test-ProductLaunchObserverDeferral.ps1')],
 'vault': [('nested-readiness','ps','automation/release-e2e/tests/Test-NestedPrimaryReadiness.ps1'),
           ('vault-binding','ps','automation/release-e2e/tests/Test-MaintenanceVaultScenarioBinding.ps1'),
           ('vault-native-steps','ps','automation/release-e2e/tests/Test-MaintenanceVaultNativeSteps.ps1'),
           ('vault-scenarios','pytest','automation/release-e2e/tests/test_vault_scenario_contract.py')],
 'acceptance': [('proof-validator','pytest','tools/test_validate_native_proof.py'),
                ('release-validator','python','tools/test_validate_release_bundle.py'),
                ('final-acceptance','python','tools/test_final_acceptance_tools.py')]
}

def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()

def checked_path(root,relative):
    """Reject path aliases/streams/links instead of trusting evidence-provided paths."""
    if not isinstance(relative,str) or not relative or '\\' in relative or ':' in relative or '\x00' in relative:
        raise ValueError('Unsafe evidence path')
    rel=PurePosixPath(relative)
    if rel.is_absolute() or any(p in ('','.','..') for p in relative.split('/')):
        raise ValueError('Unsafe evidence path')
    root=Path(root).resolve(strict=True);p=root
    for part in rel.parts:
        p=p/part
        if p.exists() or p.is_symlink():
            s=p.lstat()
            if stat.S_ISLNK(s.st_mode) or getattr(s,'st_file_attributes',0)&0x400:
                raise ValueError('Reparse/symlink evidence refused')
    if not p.resolve(strict=False).is_relative_to(root):raise ValueError('Evidence escapes root')
    return p

def read_json(path,max_bytes=16*1024*1024):
    def pairs(rows):
        out={}
        for k,v in rows:
            if k in out:raise ValueError('Duplicate JSON key')
            out[k]=v
        return out
    def constant(_):raise ValueError('Nonfinite JSON value')
    p=Path(path)
    if p.stat().st_size>max_bytes:raise ValueError('JSON input exceeds diagnostic budget')
    with p.open('rb') as f:raw=f.read(max_bytes+1)
    if len(raw)>max_bytes:raise ValueError('JSON input grew beyond diagnostic budget')
    return json.loads(raw.decode('utf-8-sig'),object_pairs_hook=pairs,parse_constant=constant)

def elapsed(start,end):
    try:
        a,b=(dt.datetime.fromisoformat(x.replace('Z','+00:00')) for x in (start,end))
        if a.tzinfo is None or b.tzinfo is None:return None
        n=(b-a).total_seconds()
        return round(n,3) if n>=0 else None
    except (TypeError,ValueError,AttributeError):return None

def checkpoint_assessment(authority,record):
    """Offline manifest assessment, NEVER permission to restore a VM/checkpoint."""
    issues=[];t=record.get('candidateTuple',{})
    for key in TUPLE:
        value=authority.get(key)
        pattern=r'[0-9a-f]{40}' if key=='candidateCommit' else r'[0-9a-f]{64}'
        if not isinstance(value,str) or not re.fullmatch(pattern,value) or t.get(key)!=value:issues.append(key)
    if record.get('l1Id')!=L1:issues.append('exact L1 identity')
    if record.get('configured') is not True:issues.append('configured installation')
    if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',str(record.get('checkpointId',''))):issues.append('checkpoint identity')
    if record.get('phase')!='MAINTENANCE-READY' or not re.fullmatch(r'(?:e2e-)?fullrelease-[A-Za-z0-9-]+',str(record.get('sourceRunId',''))):issues.append('origin')
    return {'diagnosticReusable':not issues,'mismatches':issues,'certificationCredit':False,
            'requiresFreshNativeIdentityCheck':True,'runtimeAuthorizationGranted':False}

def proof_view(repo,run_id,destination):
    """Make a temporary validation view using exact bound lineage, never latest mtime."""
    repo=Path(repo).resolve();destination=Path(destination)
    if destination.resolve().is_relative_to(repo):raise ValueError('Proof view must be outside repository')
    if not re.fullmatch(r'e2e-(?:exact-candidate-)?proof-[A-Za-z0-9-]+',run_id):raise ValueError('Invalid proof RunId')
    rd=checked_path(repo,'audit/automation-harness/runs/'+run_id)
    final=read_json(checked_path(rd,'proof-final.json'));binding=final.get('proofBinding',{})
    phase=binding.get('phaseId');lineage=binding.get('checkpointLineageId')
    if ROLES.get(final.get('role'))!=phase or not re.fullmatch(r'[0-9a-f]{32}',str(lineage)):
        raise ValueError('Proof lineage or role malformed')
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
