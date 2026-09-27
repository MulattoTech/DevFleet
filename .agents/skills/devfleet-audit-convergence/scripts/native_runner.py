"""Explicit wrappers for trusted live DevFleet entrypoints, never archive-supplied code."""
from __future__ import annotations
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from audit_io import AuditInputError, Snapshot, hash_file, safe_output_dir


def make_plan(repo: Path, action: str, mode='diagnostic', archive: Path|None=None):
    if mode not in ('diagnostic','pre-acceptance','release'):raise AuditInputError('Unsupported native validation mode')
    repo=Path(repo).resolve();commands=[]
    if action=='build':
        commands.append({'kind':'build','argv':[shutil.which('pwsh') or 'pwsh','-NoProfile','-File',str(repo/'tools/Build-AIAuditBundle.ps1'),'-Workspace',str(repo)]})
    elif action=='verify':
        if archive is None:raise AuditInputError('An archive is required for verification')
        archive=Path(archive).resolve()
        commands=[{'kind':'release-validator','argv':[sys.executable,str(repo/'tools/validate_release_bundle.py'),'--archive',str(archive),'--mode',mode]},
                  {'kind':'ai-validator','argv':[sys.executable,str(repo/'source/tools/validate_ai_audit_bundle.py'),'--archive',str(archive),'--mode','release' if mode=='pre-acceptance' else mode]}]
    else:raise AuditInputError('Unsupported native operation')
    return {'executed':False,'action':action,'mode':mode,'repo':str(repo),'commands':commands,
        'note':'Execution requires --execute and an exact --expected-head. These commands cannot grant runtime allowance or manufacture certification.'}


def _write_new(path,data):
    with Path(path).open('x',encoding='utf-8',newline='\n') as f:f.write(json.dumps(data,indent=2)+'\n')


def _check_repo(repo,expected_head):
    if not expected_head or not re.fullmatch('[0-9a-f]{40}',expected_head):raise AuditInputError('Explicit --expected-head with 40 lowercase hexadecimal characters is required')
    for name in ('AGENTS.md','CURRENT-CANDIDATE.json','tools/Build-AIAuditBundle.ps1','tools/validate_release_bundle.py','source/tools/validate_ai_audit_bundle.py'):
        with Snapshot(repo) as s:
            if not s.exists(name):raise AuditInputError('Expected trusted live repository file is missing: '+name)
    p=subprocess.run(['git','-C',str(repo),'rev-parse','HEAD'],capture_output=True,text=True,timeout=20)
    if p.returncode or p.stdout.strip()!=expected_head:raise AuditInputError('Live Git HEAD differs from the explicitly reviewed execution boundary')
    dirty=subprocess.run(['git','-C',str(repo),'status','--porcelain=v1','--untracked-files=all','--','AGENTS.md','.agents','tools','automation','source','installer-source'],capture_output=True,text=True,timeout=30)
    if dirty.returncode or dirty.stdout.strip():raise AuditInputError('Material source/skill tree is not clean; review and freeze it before executing native verification/build')


def _execute(command,repo,out,timeout=900):
    stdout=out/(command['kind']+'.stdout.log');stderr=out/(command['kind']+'.stderr.log')
    env=os.environ.copy();env['PYTHONDONTWRITEBYTECODE']='1'
    # Native child logs remain local. They are not pasted into prompts or audits by this wrapper.
    with stdout.open('xb') as o,stderr.open('xb') as e:
        start=time.monotonic();p=subprocess.Popen(command['argv'],cwd=repo,env=env,stdout=o,stderr=e)
        try:exitcode=p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            p.kill();p.wait(timeout=20)
            result={'kind':command['kind'],'pid':p.pid,'status':'TIMEOUT','exitCode':None,
                    'descendantCleanupVerified':False,'note':'Owned direct child stopped. Verify any descendants before another operation.'}
            _write_new(out/(command['kind']+'.timeout.json'),result)
            raise AuditInputError('Native child timeout; inspect the local timeout record and descendants before continuing')
    result={'kind':command['kind'],'pid':p.pid,'exitCode':exitcode,'seconds':round(time.monotonic()-start,3),
            'stdoutPath':str(stdout),'stderrPath':str(stderr),'stdoutSha256':hash_file(stdout),'stderrSha256':hash_file(stderr)}
    if command['kind']!='build':
        try:result['nativeResult']=json.loads(stdout.read_text(encoding='utf-8-sig'))
        except (UnicodeDecodeError,json.JSONDecodeError):result['nativeResult']=None
    return result


def check_archive_code_trust(repo, archive):
    """Native validators execute extracted Python/MSBuild inputs: compare these first.

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
