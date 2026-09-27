"""Prospective DevFleet attempt journal; never produces certification evidence.

Reservations are charged atomically before invocation. Crashes retain an active
record and cannot earn a free replay. This does not authenticate guests, override
native host safety, or replace the native proof/final-acceptance validators.
"""
from __future__ import annotations
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

POLICY_ID = 'DF-FRESH-CERTIFICATION-20260926'
ONE_DIAGNOSTIC_ID = POLICY_ID + '-R2-D1'
LIMITS = {'standard-token': 3, 'laptop-proof': 3, 'desktop-proof': 3,
          'fullrelease': 3, 'diagnostic': 6, 'maintenance': 3, 'build-sign': 3}
ONE_DIAGNOSTIC_LIMITS = {operation: (1 if operation == 'diagnostic' else 0)
                         for operation in LIMITS}


def limits_for(policy_id):
    if policy_id == ONE_DIAGNOSTIC_ID:
        return ONE_DIAGNOSTIC_LIMITS
    if policy_id in (POLICY_ID, POLICY_ID + '-R2'):
        return LIMITS
    raise ValueError('Unsupported explicitly authorized campaign')

def utc():
    return datetime.now(timezone.utc).isoformat()

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def safe_path(path):
    path = Path(path).absolute()
    for part in (path, *path.parents):
        if part.is_symlink() or (hasattr(part, 'is_junction') and part.is_junction()):
            raise ValueError('Reparse/symlink paths are not accepted')
    return path

def strict_json(path):
    path = safe_path(path)
    if path.stat().st_size > 4_000_000:
        raise ValueError('Journal exceeds bounded size')
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key] = value
        return result
    def invalid(_):
        raise ValueError('Nonfinite JSON value')
    return json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=pairs, parse_constant=invalid)

@contextmanager
def locked(path):
    path = safe_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(safe_path(str(path)+'.lock'), 'a+b') as stream:
        stream.seek(0); stream.write(b'0'); stream.flush(); stream.seek(0)
        if os.name == 'nt':
            import msvcrt
            try: msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError as exc: raise ValueError('Another journal writer owns the lock') from exc
        else:
            import fcntl
            try: fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as exc: raise ValueError('Another journal writer owns the lock') from exc
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == 'nt': msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else: fcntl.flock(stream, fcntl.LOCK_UN)

def atomic_write(path, value):
    path = safe_path(path)
    descriptor, temporary = tempfile.mkstemp(prefix=path.name+'.', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(descriptor,'w',encoding='utf-8',newline='\n') as stream:
            json.dump(value,stream,indent=2,ensure_ascii=False,allow_nan=False)
            stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary,path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)

def initialize(ledger, authorization, predecessors, policy_id=POLICY_ID):
    limits = limits_for(policy_id)
    if policy_id == ONE_DIAGNOSTIC_ID:
        parents = [load(p) for p in predecessors]
        if len(parents) != 1 or parents[0]['policyId'] != POLICY_ID + '-R2' or parents[0]['activeRunId'] is not None:
            raise ValueError('One-diagnostic successor requires one terminal R2 predecessor')
        if status(predecessors[0])['remaining']['diagnostic'] != 0:
            raise ValueError('One-diagnostic successor requires exhausted R2 diagnostics')
        if parents[0]['authorization']['sha256'] == digest(authorization):
            raise ValueError('One-diagnostic successor requires separate explicit authorization')
    elif policy_id != POLICY_ID:
        parents=[load(p) for p in predecessors]
        if len(parents)!=1 or parents[0]['policyId']!=POLICY_ID or parents[0]['activeRunId'] is not None:
            raise ValueError('Successor requires one terminal predecessor campaign')
        if parents[0]['authorization']['sha256']==digest(authorization):
            raise ValueError('Successor requires a new explicit user authorization source')
    ledger, authorization = safe_path(ledger), safe_path(authorization)
    if not authorization.is_file() or not authorization.read_text(encoding='utf-8').strip():
        raise ValueError('Explicit user authorization source is required')
    with locked(ledger):
        if ledger.exists(): raise ValueError('Existing campaign cannot be reset or reinitialized')
        data = {'schemaVersion':1,'policyId':policy_id,'createdUtc':utc(),
                'authorization':{'path':str(authorization),'sha256':digest(authorization)},
                'predecessors':[{'path':str(safe_path(p)),'sha256':digest(p)} for p in predecessors],
                'limits':dict(limits),'attempts':[],'activeRunId':None,'certificationCredit':False}
        atomic_write(ledger,data)
    return status(ledger)

def load(ledger):
    data = strict_json(ledger)
    if not isinstance(data,dict) or type(data.get('schemaVersion')) is not int or data['schemaVersion'] != 1 or data.get('policyId') not in (POLICY_ID, POLICY_ID+'-R2', ONE_DIAGNOSTIC_ID):
        raise ValueError('Unsupported campaign schema/identity')
    if data.get('certificationCredit') is not False:
        raise ValueError('Attempt accounting cannot grant certification credit')
    limits = data.get('limits')
    expected_limits = limits_for(data['policyId'])
    if not isinstance(limits,dict) or set(limits) != set(expected_limits) or any(type(limits[k]) is not int or limits[k] != expected_limits[k] for k in expected_limits):
        raise ValueError('Campaign ceilings were altered or malformed')
    auth = data.get('authorization',{})
    if digest(safe_path(auth['path'])) != auth.get('sha256'):
        raise ValueError('Authorization source changed')
    if data['policyId'] == ONE_DIAGNOSTIC_ID:
        predecessors = data.get('predecessors')
        if not isinstance(predecessors, list) or len(predecessors) != 1:
            raise ValueError('One-diagnostic predecessor is missing')
        predecessor = predecessors[0]
        predecessor_path = safe_path(predecessor['path'])
        if predecessor_path == safe_path(ledger):
            raise ValueError('One-diagnostic predecessor cannot be self')
        if digest(predecessor_path) != predecessor.get('sha256'):
            raise ValueError('One-diagnostic predecessor changed')
        parent = load(predecessor_path)
        if parent['policyId'] != POLICY_ID + '-R2' or parent['activeRunId'] is not None or status(predecessor_path)['remaining']['diagnostic'] != 0:
            raise ValueError('One-diagnostic predecessor is not terminal exhausted R2')
        r2_predecessors = parent.get('predecessors')
        if not isinstance(r2_predecessors, list) or len(r2_predecessors) != 1:
            raise ValueError('R2 predecessor lineage is missing')
        base_path = safe_path(r2_predecessors[0]['path'])
        if base_path in (safe_path(ledger), predecessor_path) or digest(base_path) != r2_predecessors[0].get('sha256'):
            raise ValueError('R2 predecessor lineage changed')
        base = load(base_path)
        if base['policyId'] != POLICY_ID or base['activeRunId'] is not None:
            raise ValueError('R2 predecessor is not terminal base campaign')
        if parent['authorization']['sha256'] == auth['sha256']:
            raise ValueError('One-diagnostic authorization repeats R2 source')
    attempts = data.get('attempts')
    if not isinstance(attempts,list): raise ValueError('Malformed attempts')
    seen=set(); active=[]
    for a in attempts:
        if not isinstance(a,dict) or a.get('operation') not in LIMITS or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,150}',str(a.get('runId',''))):
            raise ValueError('Malformed attempt')
        if a['runId'] in seen: raise ValueError('Duplicate RunId')
        seen.add(a['runId'])
        if a.get('state') == 'RESERVED_CHARGED': active.append(a['runId'])
        elif a.get('state') != 'TERMINAL': raise ValueError('Unknown attempt state')
    if active != ([] if data.get('activeRunId') is None else [data['activeRunId']]):
        raise ValueError('Ambiguous active attempt')
    if any(sum(a['operation']==op for a in attempts)>limit for op,limit in expected_limits.items()):
        raise ValueError('Campaign allowance exceeded')
    return data

def status(ledger):
    data=load(ledger)
    return {'policyId':data['policyId'],'remaining':{op:limit-sum(a['operation']==op for a in data['attempts']) for op,limit in limits_for(data['policyId']).items()},
            'active':next((a for a in data['attempts'] if a['runId']==data['activeRunId']),None),
            'attemptCount':len(data['attempts']),'certificationCredit':False}

def prepare(data, request):
    required={'runId','operation','owner','tuple','entrypoint','entrypointSha256','arguments','changedCondition','deadlineUtc'}
    if not isinstance(request,dict) or set(request)!=required: raise ValueError('Malformed reservation request')
    limits = limits_for(data['policyId'])
    if request['operation'] not in limits: raise ValueError('Unsupported operation')
    if not isinstance(request['runId'],str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,150}',request['runId']): raise ValueError('Invalid RunId')
    owner=request['owner']
    if not isinstance(owner,dict) or set(owner)!={'pid','startUtc'} or type(owner['pid']) is not int or owner['pid']<=0 or not isinstance(owner['startUtc'],str) or not owner['startUtc']:
        raise ValueError('Exact owner PID and start identity required')
    if not isinstance(request['tuple'],dict) or not re.fullmatch('[a-f0-9]{40}',str(request['tuple'].get('repositoryHead',''))): raise ValueError('Current repository identity required')
    if not isinstance(request['entrypoint'],str) or not request['entrypoint'].strip() or not re.fullmatch('[a-f0-9]{64}',str(request['entrypointSha256'])): raise ValueError('Reviewed entrypoint identity required')
    if not isinstance(request['arguments'],list) or any(not isinstance(s,str) for s in request['arguments']): raise ValueError('Arguments must be a string array')
    if not isinstance(request['changedCondition'],str) or not request['changedCondition'].strip(): raise ValueError('Actual changed condition must be recorded')
    deadline=datetime.fromisoformat(request['deadlineUtc'].replace('Z','+00:00'))
    if deadline.tzinfo is None or deadline<=datetime.now(timezone.utc): raise ValueError('Reservation deadline expired or lacks timezone')
    if data['activeRunId'] is not None: raise ValueError('Active attempt must be reconciled; crash is not a free replay')
    if any(a['runId']==request['runId'] for a in data['attempts']): raise ValueError('RunId has already been charged')
    if sum(a['operation']==request['operation'] for a in data['attempts'])>=limits[request['operation']]: raise ValueError('Operation allowance exhausted')
    result=json.loads(json.dumps(request,allow_nan=False))
    result.update(state='RESERVED_CHARGED',reservedUtc=utc(),certificationCredit=False)
    return result

def reserve(ledger, request, dry_run=False):
    if dry_run: return prepare(load(ledger),request)
    with locked(ledger):
        data=load(ledger); record=prepare(data,request)
        data['attempts'].append(record); data['activeRunId']=record['runId']
        atomic_write(ledger,data)
    return record

def finish(ledger, run_id, owner, exit_code, classification, evidence):
    if type(exit_code) is not int or not isinstance(classification,str) or not classification or not isinstance(evidence,list) or any(not isinstance(x,str) for x in evidence):
        raise ValueError('Explicit terminal result required')
    with locked(ledger):
        data=load(ledger)
        if data['activeRunId']!=run_id: raise ValueError('Wrong active RunId')
        record=next(a for a in data['attempts'] if a['runId']==run_id)
        if record['owner']!=owner: raise ValueError('Wrong owner; reconcile interrupted attempt explicitly')
        record.update(state='TERMINAL',terminalUtc=utc(),exitCode=exit_code,classification=classification,evidence=evidence)
        data['activeRunId']=None; atomic_write(ledger,data)
    return record

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['initialize','status','reserve','finish'])
    parser.add_argument('--ledger',required=True); parser.add_argument('--authorization'); parser.add_argument('--predecessor',action='append',default=[])
    parser.add_argument('--policy-id',choices=[POLICY_ID,POLICY_ID+'-R2',ONE_DIAGNOSTIC_ID],default=POLICY_ID)
    parser.add_argument('--request'); parser.add_argument('--dry-run',action='store_true')
    args=parser.parse_args()
    if args.command=='initialize': result=initialize(args.ledger,args.authorization,args.predecessor,args.policy_id)
    elif args.command=='status': result=status(args.ledger)
    elif args.command=='reserve': result=reserve(args.ledger,strict_json(args.request),args.dry_run)
    else:
        q=strict_json(args.request); result=finish(args.ledger,q['runId'],q['owner'],q['exitCode'],q['classification'],q['evidence'])
    print(json.dumps(result,indent=2,allow_nan=False))

if __name__=='__main__':
    try: main()
    except (ValueError,KeyError,TypeError,OSError) as error:
        raise SystemExit('ATTEMPT_JOURNAL_BLOCKED: '+str(error))
