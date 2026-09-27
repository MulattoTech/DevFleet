"""Evidence-backed advisory planning. This program NEVER grants release/runtime credit."""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
# Some native Python installations use isolated _pth resolution. Add only this
# reviewed script's own directory, not the working directory or archive contents.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_io import AuditInputError, Snapshot, hash_file, safe_output_dir, save_report

KEYS=('repositoryHead','candidateCommit','shippingInputIdentity','releaseFingerprintId','toolingFingerprintId')
ALIASES={'candidateCommit':('candidateCommit','candidateGitCommit','candidateBuildCommit')}
MAINTENANCE=('REPAIR','CLEAN-REINSTALL','UNINSTALL','FACTORY-RESET','REBOOT-RESUME')

def obj(value,label):
    if value is None:return {}
    if not isinstance(value,dict):raise AuditInputError(label+' must be a JSON object')
    return value


def identity(value):
    value=obj(value,'Identity');out={}
    for k in KEYS:
        names=ALIASES.get(k,(k,));values=[value[n] for n in names if value.get(n) is not None]
        if len(set(str(v) for v in values))>1:raise AuditInputError('Conflicting identity aliases: '+k)
        out[k]=values[0] if values else None
    return out


def mismatch(expected,actual):
    return [k for k in KEYS if expected.get(k) is None or actual.get(k) is None or expected[k]!=actual[k]]


def native_phases(text):
    if not text:raise AuditInputError('Native FullRelease phase-plan source missing')
    match=re.search(r'\$script:FullReleasePhases\s*=\s*@\((.*?)^\s*\)\s*$',text,re.M|re.S)
    if not match:raise AuditInputError('Native phase-plan syntax is unsupported; do not substitute a hardcoded plan')
    ids=re.findall(r"^\s*\[pscustomobject\]\s*@\{\s*id\s*=\s*'([A-Z0-9-]+)'",match.group(1),re.M)
    if not ids or len(set(ids))!=len(ids):raise AuditInputError('Empty/duplicate native FullRelease phase plan')
    return ids


def summarize(s: Snapshot):
    a=obj(s.json('evidence/CURRENT-RELEASE-AUTHORITY.json',True),'Authority')
    c=obj(s.json('CURRENT-CANDIDATE.json',True),'Candidate')
    g=obj(s.json('evidence/CURRENT-GATES.json',True),'Gates')
    f=obj(s.json('evidence/FULLRELEASE-SUMMARY.json',True),'FullRelease summary')
    token=obj(s.json('evidence/CURRENT-STANDARD-TOKEN.json',True),'Standard-token pointer')
    expected=identity(c);blocks=[];warnings=[]
    if not a:blocks.append('AUTHORITY_MISSING')
    if any(not isinstance(expected[k],str) or not re.fullmatch('[0-9a-f]{'+str(40 if k in KEYS[:2] else 64)+'}',expected[k]) for k in KEYS):blocks.append('CANDIDATE_IDENTITY_MALFORMED')
    if not(c.get('candidateIsCurrent') is True and c.get('sourceChangedSinceCandidate') is False and c.get('rebuildRequired') is False):blocks.append('CANDIDATE_FLAGS_NOT_CURRENT')
    if mismatch(expected,identity(a)):blocks.append('AUTHORITY_TUPLE_CONFLICT')
    if g and (mismatch(expected,identity(g)) or (a.get('authorityId') and g.get('authorityId')!=a.get('authorityId'))):blocks.append('GATES_AUTHORITY_CONFLICT')
    tokdiff=mismatch(expected,identity(token))
    token_state='MISSING' if not token else ('STALE' if tokdiff else ('RECORDED_CURRENT_UNVALIDATED' if token.get('status')=='PASS' and token.get('standardNonAdministratorToken') is True else 'UNVERIFIED'))
    if token_state!='RECORDED_CURRENT_UNVALIDATED':blocks.append('STANDARD_TOKEN_'+token_state)
    p=obj(a.get('proofs'),'Selected proofs');runs=p.get('runs',[])
    if not isinstance(runs,list):raise AuditInputError('Selected proof runs must be a list')
    runids=[r.get('runId') for r in runs if isinstance(r,dict)]
    proof_pair=p.get('passing')==2 and p.get('required')==2 and len(runs)==2 and len(runids)==2 and all(isinstance(x,str) and x for x in runids) and len(set(runids))==2
    if not proof_pair:blocks.append('CURRENT_PROOF_PAIR_MISSING_OR_INCONSISTENT')
    phases=native_phases(s.text('automation/release-e2e/modules/FullRelease.psm1'))
    fr=f.get('latestRunId');full_binding=not mismatch(expected,identity(f))
    current_run=isinstance(fr,str) and re.fullmatch(r'(?:e2e-)?fullrelease-[A-Za-z0-9-]+',fr,re.I) and full_binding and f.get('historicalEvidenceOnly') is False
    root=('evidence/current-fullrelease' if s.archive else f'audit/automation-harness/runs/{fr}') if current_run else None
    by_id={};run_ok=False
    if root:
        state=obj(s.json(root+'/run-state.json',True),'FullRelease run-state')
        if state.get('runId')!=fr or mismatch(expected,identity(state.get('candidateHashes'))):blocks.append('FULLRELEASE_RUN_TUPLE_CONFLICT')
        else:
            run_ok=True;records=s.json(root+'/fullrelease-phase-records.json',True)
            if records is not None and not isinstance(records,list):raise AuditInputError('FullRelease phase records must be a list')
            for row in records or []:
                if not isinstance(row,dict) or not isinstance(row.get('id'),str):raise AuditInputError('Invalid FullRelease phase record')
                if row['id'] in by_id:raise AuditInputError('Duplicate FullRelease phase result')
                if row.get('runId') and row['runId']!=fr:
                    blocks.append('SPLICED_PHASE_RUN_ID');continue
                by_id[row['id']]=row
    elif fr:blocks.append('FULLRELEASE_SUMMARY_NOT_CURRENT')
    fallback='NOT_RUN' if f.get('status')=='NOT_RUN_FOR_CURRENT_CANDIDATE' and full_binding and fr is None else 'UNVERIFIED'
    matrix=[]
    for index,name in enumerate(phases,1):
        recorded=by_id.get(name,{}).get('status') if run_ok else None
        status='RECORDED_PASS' if recorded=='PASS' else (recorded if recorded in ('FAIL','BLOCKED','NOT_RUN','UNVERIFIED','IN_PROGRESS','RUNNING') else fallback)
        matrix.append({'number':index,'id':name,'state':status,'runId':fr if run_ok else None,
                       'evidencePath':root+'/fullrelease-phase-records.json' if run_ok else 'evidence/FULLRELEASE-SUMMARY.json'})
    phasecounts=dict(Counter(row['state'] for row in matrix));byphase={r['id']:r['state'] for r in matrix}
    if f.get('status')!='PASS' or f.get('fullReleasePassed') is not True or not run_ok:blocks.append('FULLRELEASE_NOT_VALIDATED')
    real=obj(s.json(root+'/real-use-acceptance-evidence.json',True),'Real use') if root and run_ok else {}
    journeys=[]
    for uid in ('U01','U02','U03','U04','U05'):
        matches=[r for r in real.get('journeys',[]) if isinstance(r,dict) and r.get('id')==uid] if isinstance(real.get('journeys'),list) else []
        st='RECORDED_PASS' if real.get('runId')==fr and len(matches)==1 and matches[0].get('status')=='PASS' else 'UNVERIFIED'
        journeys.append({'id':uid,'state':st})
    if any(x['state']!='RECORDED_PASS' for x in journeys):blocks.append('REAL_USE_U01_U05_UNVERIFIED')
    maintenance=[{'id':name,'state':byphase.get(name,'UNVERIFIED')} for name in MAINTENANCE]
    if any(x['state']!='RECORDED_PASS' for x in maintenance):blocks.append('MAINTENANCE_5_OF_5_UNVERIFIED')
    final=obj(s.json('evidence/FINAL-ACCEPTANCE.json',True),'Final acceptance')
    if not final:blocks.append('FINAL_ACCEPTANCE_MISSING')
    elif mismatch(expected,identity(final.get('candidateTuple') or final.get('candidate'))):blocks.append('FINAL_ACCEPTANCE_TUPLE_UNVERIFIED')
    l1=obj(s.json('evidence/l1-terminal-state.json',True),'L1 terminal');l2=obj(s.json('evidence/l2-terminal-state.json',True),'L2 terminal')
    ledgers=[]
    for name in s.json_files('evidence/campaigns'):
        if not name.endswith('ledger.json'):continue
        if len(ledgers)>=100:raise AuditInputError('Ledger observation limit exceeded')
        try:
            row=obj(s.json(name),'Ledger')
            ledgers.append({'path':name,'parseStatus':'PARSED','authorizationInterpretation':'NOT_INFERRED_FROM_SNAPSHOT','policyId':row.get('policyId'),'status':row.get('status'),
                'executionClosed':row.get('executionClosed'),'activeReservationPresent':row.get('activeReservation') is not None,
                'fullReleaseConsumed':row.get('fullReleaseConsumed'),'fullReleaseMaximum':row.get('fullReleaseMaximum')})
        except AuditInputError as exc:
            # Campaign ledgers are advisory observations here. Preserve strict
            # parsing and disclose ambiguous historical bytes without assigning
            # them an authorization meaning or hiding other readable evidence.
            raw=s.read(name)
            parse_error='DUPLICATE_JSON_PROPERTY' if 'Duplicate JSON property' in str(exc) else 'INVALID_OR_UNREADABLE_LEDGER_JSON'
            ledgers.append({'path':name,'bytes':len(raw),'sha256':s.records[name]['sha256'],'parseStatus':'MALFORMED','parseError':parse_error,'authorizationInterpretation':'UNKNOWN'})
            warnings.append('Malformed campaign ledger retained with UNKNOWN authorization interpretation: '+name)
    # A snapshot cannot establish which user instruction actually adopted a policy.
    blocks.append('RUNTIME_AUTHORIZATION_MUST_BE_RECONCILED_WITH_USER_INSTRUCTION')
    blocks.append('NATIVE_VALIDATION_REQUIRED')
    if s.archive:warnings.append('An archive is a dated snapshot; it cannot establish live ownership, token, HostSafety, or latest applicable runtime authorization.')
    if a.get('currentProofRunId') and a.get('currentProofRunId') not in runids:warnings.append('The legacy currentProofRunId is not one of the selected current passing proof RunIds.')
    if token_state=='STALE':warnings.append('A PASS token title is historical when its repository/tooling identity differs.')
    actions=[{'id':'OWNERSHIP_ACCESS_AUTHORIZATION','action':'Reconcile the actual root owner, filesystem/Hyper-V/token capabilities, explicit adopted policy and remaining allowance; preserve closed historical ledgers.'}]
    if any(x in blocks for x in ('AUTHORITY_MISSING','CANDIDATE_IDENTITY_MALFORMED','CANDIDATE_FLAGS_NOT_CURRENT','AUTHORITY_TUPLE_CONFLICT','GATES_AUTHORITY_CONFLICT')):
        actions.append({'id':'RECONCILE_CANDIDATE','action':'Resolve current source/tooling/authority identity through native mechanisms. Freeze necessary tested changes before qualification; do not hand-edit evidence.'})
    if token_state!='RECORDED_CURRENT_UNVALIDATED':actions.append({'id':'CURRENT_STANDARD_TOKEN','action':'Obtain a genuine current non-administrator qualification through the native runner under explicit allowance; never edit or redate the historical receipt.'})
    if not proof_pair:actions.append({'id':'INDEPENDENT_ROLE_PROOFS','action':'After fresh safety and reservations, obtain independent Laptop/Surrogate and Primary/Desktop proofs for the final coherent tuple; validate natively.'})
    if 'FULLRELEASE_NOT_VALIDATED' in blocks:actions.append({'id':'COHERENT_FULLRELEASE','action':f'Run the native FullRelease sequence ({len(phases)} currently declared phases), including all real-use, maintenance, reconcile and cleanup obligations. No historical phase stitching.'})
    actions.append({'id':'FINALIZE_RELEASE','action':'Validate native release evidence, build the pre-acceptance audit, complete native final acceptance, build Auto RELEASE audit, and independently validate final bytes with both native validators and external SHA-256 sidecar.'})
    return {'schemaVersion':1,'scope':'ADVISORY_SNAPSHOT_ANALYSIS','observedUtc':datetime.now(timezone.utc).isoformat(),
        'certificationCredit':False,'runtimeAuthorizationGranted':False,'source':str(s.path),'archive':s.archive,
        'candidateTuple':expected,'authorityId':a.get('authorityId'),'authorityGeneratedAtUtc':a.get('generatedAtUtc'),
        'nativeReportedClassification':a.get('blockerClassification') or a.get('status'),
        'reportedInternalPromotionAllowed':a.get('internalPromotionAllowed'),'nativeValidation':'NOT_PERFORMED',
        'candidateFlags':{k:c.get(k) for k in ('candidateIsCurrent','sourceChangedSinceCandidate','rebuildRequired')},
        'standardToken':{'state':token_state,'runId':token.get('runId'),'mismatches':tokdiff,'evidencePath':'evidence/CURRENT-STANDARD-TOKEN.json'},
        'proofs':{'reportedPassing':p.get('passing'),'required':p.get('required'),'selectedRunIds':runids,'independenceValidation':'NOT_PERFORMED'},
        'fullRelease':{'reportedStatus':f.get('status'),'runId':fr,'runTupleMatches':bool(run_ok)},
        'phases':matrix,'phaseCounts':phasecounts,'maintenance':maintenance,'realUse':journeys,
        'finalAcceptance':{'present':bool(final),'validation':'NOT_PERFORMED'},
        'terminal':{'l1':{k:l1.get(k) for k in ('name','id','state','timestampUtc')},'l2':{k:l2.get(k) for k in ('status','present','timestampUtc','verificationMethod','runId')},'nestedProofValidation':'NOT_PERFORMED'},
        'ledgerObservations':ledgers,'blockerCodes':list(dict.fromkeys(blocks)),'warnings':warnings,'nextActions':actions,
        'limitations':['No archive-supplied code was executed.','Recorded PASS is not native revalidation.','Missing fields remain unknown; no global completion percentage is computed.','This is not an exhaustive security audit or a guarantee of bug-free software.'],
        'evidenceFiles':list(s.records.values())}


def markdown(r):
    esc=lambda x:str(x if x is not None else 'UNKNOWN').replace('|','\\|').replace('\n',' ')
    out=['# DevFleet audit convergence analysis','', '**Scope: advisory analysis; no certification or runtime authorization granted.**','',
         'Native reported verdict: **'+esc(r['nativeReportedClassification'])+'**','',
         '## Current identity','', '| Field | Value |','|---|---|']
    out += ['| '+k+' | `'+esc(v)+'` |' for k,v in r['candidateTuple'].items()]
    out += ['', '## Qualification and remaining work','',
            '- Standard token: '+esc(r['standardToken']['state'])+'; mismatches: '+', '.join(r['standardToken']['mismatches']),
            '- Selected current proofs: '+esc(r['proofs']['reportedPassing'])+' / '+esc(r['proofs']['required'])+' (not independently revalidated here).',
            '- FullRelease: '+esc(r['fullRelease']['reportedStatus'])+'; RunId: '+esc(r['fullRelease']['runId']),
            '- Native final acceptance present: '+str(r['finalAcceptance']['present'])+' (not validated here).',
            '', '## Native FullRelease phase matrix','', '| # | Native phase | Observed record state |','|---:|---|---|']
    out += [f"| {x['number']} | {x['id']} | {x['state']} |" for x in r['phases']]
    out += ['', 'Counts: '+json.dumps(r['phaseCounts'])+'. These are phase-record counts, not a percentage of the whole project.',
            '', '## Real use and maintenance','', '| Obligation | Record state |','|---|---|']
    out += ['| '+x['id']+' | '+x['state']+' |' for x in r['realUse']+r['maintenance']]
    out += ['', '## Evidence gaps / blockers','']+['- `'+x+'`' for x in r['blockerCodes']]
    out += ['', '## Next actions','']+[str(i)+'. '+x['action'] for i,x in enumerate(r['nextActions'],1)]
    out += ['', '## Interpretation warnings','']+['- '+x for x in r['warnings']+r['limitations']]
    if 'archiveIntegrity' in r:out += ['', '## Archive inventory verification','', '```json',json.dumps(r['archiveIntegrity'],indent=2),'```']
    if 'comparison' in r:out += ['', '## Archive versus live repository','', '```json',json.dumps(r['comparison'],indent=2),'```']
    out += ['', '## Source provenance','', 'Input: `'+esc(r['source'])+'`', 'Observation: `'+r['observedUtc']+'`',
            'Exact evidence paths and SHA-256 values are retained in the accompanying analysis.json.', '']
    return '\n'.join(out)


def analyze(path,output,repo=None,expected_sha=None):
    path=Path(path).resolve(strict=True);repo=Path(repo).resolve(strict=True) if repo else None
    out=safe_output_dir(output,repo or (path if path.is_dir() else None))
    if expected_sha and (not re.fullmatch('[0-9a-f]{64}',expected_sha) or not path.is_file() or hash_file(path)!=expected_sha):raise AuditInputError('Archive SHA-256 differs from explicitly expected bytes')
    with Snapshot(path) as s:
        integrity=s.verify_inventory() if s.archive else None
        r=summarize(s)
        if integrity:r['archiveIntegrity']=integrity;r['archiveSha256']=hash_file(path)
        if integrity and integrity['status']!='PASS':r['blockerCodes'].insert(0,'ARCHIVE_INTEGRITY_FAIL')
        if repo and s.archive:
            with Snapshot(repo) as live:
                lc=obj(live.json('CURRENT-CANDIDATE.json'),'Live candidate')
                la=obj(live.json('evidence/CURRENT-RELEASE-AUTHORITY.json'),'Live authority')
                r['comparison']={'tupleMismatches':mismatch(r['candidateTuple'],identity(lc)),
                    'liveCandidateTuple':identity(lc),'archiveAuthorityId':r['authorityId'],'liveAuthorityId':la.get('authorityId'),
                    'files':[],'note':'Differences are reported, not overwritten or reconciled by choosing a newer timestamp.'}
                for name in ('CURRENT-CANDIDATE.json','evidence/CURRENT-RELEASE-AUTHORITY.json','evidence/CURRENT-GATES.json','evidence/FULLRELEASE-SUMMARY.json','evidence/CURRENT-STANDARD-TOKEN.json'):
                    left=s.read(name,True);right=live.read(name,True)
                    r['comparison']['files'].append({'path':name,'sameBytes':left is not None and right is not None and left==right})
        if not s.archive:
            try:
                p=subprocess.run(['git','-C',str(path),'rev-parse','HEAD'],capture_output=True,text=True,timeout=15)
                r['liveGitHead']=p.stdout.strip() if p.returncode==0 else None
                if r['liveGitHead']!=r['candidateTuple']['repositoryHead']:r['blockerCodes'].insert(0,'LIVE_HEAD_NOT_BOUND')
            except (OSError,subprocess.TimeoutExpired):r['warnings'].append('Live Git HEAD could not be read; it remains unverified.')
        r['evidenceFiles']=list(s.records.values())
    save_report(out,r,markdown(r));return r


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    q=sub.add_parser('inspect');q.add_argument('--repo',required=True);q.add_argument('--output',required=True)
    q=sub.add_parser('analyze');q.add_argument('--archive',required=True);q.add_argument('--repo');q.add_argument('--output',required=True);q.add_argument('--sha256')
    for name in ('build','verify'):
        q=sub.add_parser(name);q.add_argument('--repo',required=True);q.add_argument('--output',required=True);q.add_argument('--execute',action='store_true');q.add_argument('--expected-head')
        if name=='verify':q.add_argument('--archive',required=True);q.add_argument('--mode',required=True,choices=['diagnostic','pre-acceptance','release'])
    args=p.parse_args(argv)
    try:
        if args.command in ('inspect','analyze'):
            r=analyze(args.repo if args.command=='inspect' else args.archive,args.output,args.repo, getattr(args,'sha256',None))
            print(json.dumps({'analysis':str(Path(args.output).resolve()/'analysis.md'),'reportedVerdict':r['nativeReportedClassification'],
                'standardToken':r['standardToken']['state'],'phaseCounts':r['phaseCounts'],'certificationCredit':False,'blockerCodes':r['blockerCodes']},indent=2))
            return 2 if r.get('archiveIntegrity',{}).get('status')=='FAIL' else 0
        from native_runner import run
        return run(args)
    except (AuditInputError,OSError,zipfile_error(),ValueError) as e:
        # No arbitrary evidence contents or credential values are printed.
        print(json.dumps({'status':'ERROR','error':str(e)[:500],'certificationCredit':False}),file=sys.stderr);return 2


def zipfile_error():
    import zipfile
    return zipfile.BadZipFile

if __name__=='__main__':raise SystemExit(main())
