# DevFleet source part 004

Full-source UTF-8 byte interval [139500, 186000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 0d748aeddc1a2817280fa194d160f071b0476e3a3040bfbdfd993d77ff836157

<!-- BEGIN SOURCE SLICE -->
[ordered]@{
            status = [string]$nested.status
            present = $nested.present
            verification = [string]$nested.verification
            exactMatchCount = $nested.exactMatchCount
            inventoryCount = $nested.inventoryCount
            observedUtc = [string]$nested.observedUtc
        }
        if ([string]$nested.status -eq 'UNVERIFIED') { [void]$result.blockers.Add('NESTED_L2_INVENTORY_UNVERIFIED') }
        elseif ([string]$nested.status -eq 'PRESENT') { [void]$result.blockers.Add('NESTED_L2_PRESENT_BEFORE_PROOF') }
        elseif ([string]$nested.status -cne 'ABSENT' -or $nested.present -isnot [bool] -or
            $nested.present -ne $false -or [string]$nested.expectedName -cne $expectedL2Name -or
            [int]$nested.exactMatchCount -ne 0 -or [string]::IsNullOrWhiteSpace([string]$nested.verification)) {
            [void]$result.blockers.Add('NESTED_L2_NOT_PROVEN_ABSENT_BEFORE_PROOF')
        }
    } catch {
        $result.liveGuestAuth.failureClass = $_.Exception.GetType().FullName
        $message = [string]$_.Exception.Message
        if ($message -match 'credential is invalid|user name or password|logon failure') {
            $result.liveGuestAuth.failureMessage = 'EXACT_CLEAN_GUEST_AUTH_REJECTED'
            [void]$result.blockers.Add('E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN')
        } elseif (-not $result.blockers.Contains('EXACT_LAB_IDENTITY_OR_STATE_CHANGED_AFTER_RESTORE') -and
            -not $result.blockers.Contains('HOST_SAFETY_NOT_START_SAFE_AFTER_RESTORE')) {
            $result.liveGuestAuth.failureMessage = 'EXACT_CLEAN_GUEST_SESSION_FAILED'
            [void]$result.blockers.Add('EXACT_CLEAN_GUEST_SESSION_FAILED')
        }
    } finally {
        if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
        $live = Get-VM -ComputerName localhost -Id $expectedL1Id -ErrorAction SilentlyContinue
        if ($live -and [string]$live.State -ne 'Off') {
            Stop-VM -VM $live -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        $stopDeadline = (Get-Date).AddSeconds(45)
        do {
            $live = Get-VM -ComputerName localhost -Id $expectedL1Id -ErrorAction SilentlyContinue
            if ($live -and [string]$live.State -eq 'Off') { break }
            Start-Sleep -Seconds 1
        } while ((Get-Date) -lt $stopDeadline)
        $result.liveGuestAuth.finalL1State = if ($live) { [string]$live.State } else { 'UNAVAILABLE' }
        if ([string]$result.liveGuestAuth.finalL1State -cne 'Off') {
            [void]$result.blockers.Add('L1_NOT_OFF_AFTER_LIVE_PREFLIGHT')
        }
    }
} elseif ($LiveGuestAuth) {
    [void]$result.blockers.Add('LIVE_GUEST_AUTH_SKIPPED_DUE_TO_STATIC_BLOCKER')
}

$result.blockers = @($result.blockers | Select-Object -Unique)
$result.staticPrerequisitesPass = [bool]$staticPrerequisitesPass
$result.readyForProofReservation =
    [bool]$LiveGuestAuth -and
    $result.blockers.Count -eq 0 -and
    [bool]$result.liveGuestAuth.connected -and
    [string]$result.liveGuestAuth.nestedL2.status -ceq 'ABSENT' -and
    $result.liveGuestAuth.nestedL2.present -is [bool] -and
    $result.liveGuestAuth.nestedL2.present -eq $false
$result.status = if ($result.readyForProofReservation) {
    'PASS_READY_FOR_PROOF_RESERVATION'
} elseif (-not $LiveGuestAuth -and $result.staticPrerequisitesPass) {
    'PASS_STATIC_REQUIRES_LIVE_GUEST_AUTH'
} else {
    'BLOCKED'
}
$result | ConvertTo-Json -Depth 15
if ($LiveGuestAuth -and -not $result.readyForProofReservation) { exit 2 }
if (-not $LiveGuestAuth -and -not $result.staticPrerequisitesPass) { exit 2 }

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py

SHA256: 390aaf940dbce71efe84c37a4100214ee0d86e2d5f3389127f153db18f7e45a4 | Bytes: 14012 | Git mode: 100644

```
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

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/guest_auth_diagnosis.py

SHA256: 8c29e1c005de5cb76f3834b6b7f257697fcc4b8171b324e414fe42a16405839a | Bytes: 8386 | Git mode: 100644

```
"""Interpret a pinned, read-only guest Security event for one terminal R2 diagnostic.

This is supplementary VM-free evidence. It never changes the historical result,
admits a lab attempt, or grants authentication/certification credit.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re


EXACT_VM = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
EXACT_CLEAN = '19865b76-4c3a-44f7-ba39-841e9d3c40c9'
EXACT_ACCOUNT = 'E2EAdmin'
EXACT_COMPUTER = 'DevFleet-E2E-01'
PINNED_RDC_REPORT_SHA256 = '351d49ffe6038ea4183f26b871a5bbbfdd8a3394eff830c68972ee5037915704'
PINNED_RDC_SECURITY_LOG_SHA256 = 'bb824fb0a8001a91295b9f63e986a992584692d726d9e3517e071fa21114afa6'
HEX64 = re.compile(r'[0-9a-fA-F]{64}\Z')
STATUS = re.compile(r'0x[0-9a-fA-F]{8}\Z')
CLASSIFICATIONS = {
    ('0xc000006e', '0xc0000071'): 'PASSWORD_EXPIRED',
    ('0xc000006d', '0xc000006a'): 'WRONG_PASSWORD',
    ('0xc000006e', '0xc0000072'): 'ACCOUNT_DISABLED',
    ('0xc0000072', '0xc0000072'): 'ACCOUNT_DISABLED',
    ('0xc0000234', '0xc0000234'): 'ACCOUNT_LOCKED',
}


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def read_json(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4_000_000,
            'Evidence file missing, linked, or oversized')
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    def invalid(_):
        raise ValueError('Nonfinite JSON number')
    value = json.loads(path.read_text(encoding='utf-8-sig'),
                       object_pairs_hook=pairs, parse_constant=invalid)
    require(isinstance(value, dict), 'Evidence root is not an object')
    return value


def instant(value):
    require(isinstance(value, str) and value.strip(), 'Missing UTC instant')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None and parsed.utcoffset().total_seconds() == 0,
            'Event and reservation instants must be UTC')
    return parsed.astimezone(timezone.utc)


def diagnose(report_path, expected_report_sha256, expected_log_sha256,
             ledger_path, readiness_path, run_id):
    require(isinstance(run_id, str) and run_id.strip(), 'Missing exact RunId')
    require(isinstance(expected_report_sha256, str) and HEX64.fullmatch(expected_report_sha256),
            'Missing trusted report hash')
    require(isinstance(expected_log_sha256, str) and HEX64.fullmatch(expected_log_sha256),
            'Missing trusted guest Security log hash')
    report_path = Path(report_path)
    actual_hash = hashlib.sha256(report_path.read_bytes()).hexdigest()
    require(actual_hash == expected_report_sha256.lower(), 'Report hash is not the pinned source')
    report = read_json(report_path)
    ledger = read_json(ledger_path)
    readiness = read_json(readiness_path)

    require(report.get('scope') == 'OFFLINE_READ_ONLY_GUEST_EVENT_INSPECTION',
            'Report has wrong inspection scope')
    require(report.get('vmId') == EXACT_VM and report.get('parentCheckpointId') == EXACT_CLEAN,
            'Report is not bound to exact L1 and predecessor CLEAN')
    for key in ('diskReadOnlyVerified', 'dismounted', 'diskFileSizeUnchanged',
                'diskWriteTimeUnchanged', 'ledgerUnchanged'):
        require(report.get(key) is True, 'Unverified read-only source chain: ' + key)
    require(report.get('guestAuthenticationAttempted') is False and report.get('vmStarted') is False,
            'Report is not a read-only offline inspection')
    require(report.get('securityLogSha256') == expected_log_sha256.lower(),
            'Guest Security log hash is not independently pinned')

    require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2',
            'Wrong R2 journal')
    attempts = [a for a in ledger.get('attempts', []) if isinstance(a, dict)
                and a.get('runId') == run_id]
    require(len(attempts) == 1 and ledger.get('activeRunId') is None,
            'Run is missing, ambiguous, or still active')
    attempt = attempts[0]
    require(attempt.get('operation') == 'diagnostic' and attempt.get('state') == 'TERMINAL'
            and attempt.get('certificationCredit') is False
            and attempt.get('classification') == 'E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN',
            'Run is not the terminal historical-source diagnostic')
    start, end = instant(attempt.get('reservedUtc')), instant(attempt.get('terminalUtc'))
    require(start < end, 'Invalid terminal window')

    lab = readiness.get('lab') or {}
    auth = readiness.get('liveGuestAuth') or {}
    admission = readiness.get('admission') or {}
    require(lab.get('l1Id') == EXACT_VM and lab.get('cleanId') == EXACT_CLEAN,
            'Readiness lab identity differs')
    require(admission.get('runId') == run_id and admission.get('operation') == 'diagnostic',
            'Readiness admission differs')
    require(auth.get('attempted') is True and auth.get('cleanRestored') is True
            and auth.get('connected') is False and auth.get('finalL1State') == 'Off'
            and auth.get('failureClass') == 'System.Management.Automation.Remoting.PSDirectException'
            and 'E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN' in readiness.get('blockers', [])
            and readiness.get('certificationCredit') is False,
            'Readiness did not record the exact generic authentication rejection')

    matching = []
    events = report.get('events')
    require(isinstance(events, list) and events, 'Missing guest failure events')
    record_ids = set()
    for event in events:
        require(isinstance(event, dict) and type(event.get('recordId')) is int
                and event['recordId'] > 0 and event['recordId'] not in record_ids,
                'Malformed or duplicate event record identity')
        record_ids.add(event['recordId'])
        require(event.get('eventId') == 4625 and STATUS.fullmatch(str(event.get('status', '')))
                and STATUS.fullmatch(str(event.get('subStatus', ''))),
                'Malformed guest failure event')
        event_time = instant(event.get('timeUtc'))
        if start <= event_time <= end and event.get('targetUser') == EXACT_ACCOUNT \
                and event.get('computer', '').lower() == EXACT_COMPUTER.lower():
            matching.append(event)
    require(len(matching) == 1, 'Missing or conflicting exact account failures in run window')
    event = matching[0]
    status, substatus = event['status'].lower(), event['subStatus'].lower()
    return {
        'schemaVersion': 1, 'scope': 'SUPPLEMENTARY_HISTORICAL_DIAGNOSIS',
        'runId': run_id, 'classification': CLASSIFICATIONS.get((status, substatus),
                                                               'UNKNOWN_AUTH_FAILURE'),
        'historicalLedgerClassification': attempt['classification'],
        'guestAuthenticated': False, 'certificationCredit': False,
        'reportSha256': actual_hash, 'securityLogSha256': expected_log_sha256.lower(),
        'vmId': EXACT_VM, 'parentCheckpointId': EXACT_CLEAN,
        'event': {'recordId': event['recordId'], 'eventId': 4625,
                  'timeUtc': event['timeUtc'], 'computer': event['computer'],
                  'targetUser': event['targetUser'], 'status': status, 'subStatus': substatus},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True)
    parser.add_argument('--report-sha256', required=True)
    parser.add_argument('--security-log-sha256', required=True)
    parser.add_argument('--ledger', required=True)
    parser.add_argument('--readiness', required=True)
    parser.add_argument('--run-id', required=True)
    args = parser.parse_args()
    require(args.report_sha256.lower() == PINNED_RDC_REPORT_SHA256
            and args.security_log_sha256.lower() == PINNED_RDC_SECURITY_LOG_SHA256,
            'RDC source hashes are not the independently pinned values')
    print(json.dumps(diagnose(args.report, args.report_sha256, args.security_log_sha256,
                              args.ledger, args.readiness, args.run_id), indent=2))


if __name__ == '__main__':
    main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_campaign_successor.py

SHA256: ebd01d69eaaafc709e8a1d5351dcd541a0db0f6f7a8bdb98a1731082bae39c3f | Bytes: 1854 | Git mode: 100644

```
import importlib.util, json, pathlib, tempfile, unittest
HERE=pathlib.Path(__file__).parent
class SuccessorTests(unittest.TestCase):
 def setUp(self):
  spec=importlib.util.spec_from_file_location('journal',HERE/'fresh_attempts.py');self.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.m)
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=pathlib.Path(self.temp.name)
  self.auth=self.root/'old-auth.md';self.auth.write_text('Original user request')
  self.old=self.root/'old.json';self.m.initialize(self.old,self.auth,[])
  self.auth2=self.root/'new-auth.md';self.auth2.write_text('New user explicitly requests full new allowance')
  self.new=self.root/'new.json';self.policy='DF-FRESH-CERTIFICATION-20260926-R2'
 def test_successor_starts_full_preserving_parent_bytes(self):
  before=self.old.read_bytes();self.m.initialize(self.new,self.auth2,[self.old],policy_id=self.policy)
  self.assertEqual(self.old.read_bytes(),before);self.assertEqual(self.m.status(self.new)['remaining'],self.m.LIMITS)
  self.assertEqual(self.m.status(self.new)['policyId'],self.policy)
 def test_successor_requires_parent(self):
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth2,[],policy_id=self.policy)
 def test_successor_cannot_reuse_old_authorization(self):
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth,[self.old],policy_id=self.policy)
 def test_unknown_policy_rejected(self):
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth2,[self.old],policy_id='unknown')
 def test_existing_successor_cannot_reset(self):
  self.m.initialize(self.new,self.auth2,[self.old],policy_id=self.policy)
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth2,[self.old],policy_id=self.policy)
if __name__=='__main__':unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_fresh_attempts.py

SHA256: ddd5e4619228c6f0cf99a54faab744b81725c53f7b95ee14b6bdbdda29a4f10e | Bytes: 7148 | Git mode: 100644

```
"""Behavioral tests for prospective attempt accounting (never certification)."""
import importlib.util
import json
import pathlib
import tempfile
import unittest
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent

class FreshAttemptTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue((HERE/'fresh_attempts.py').exists(), 'Fresh attempt journal implementation is missing')
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE/'fresh_attempts.py')
        self.m = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.m)
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.auth = self.root/'authorization.txt'; self.auth.write_text('Explicit fresh campaign requested; keep history.')
        self.old = self.root/'old.json'; self.old.write_text('{"used":9,"historical":true}')
        self.ledger = self.root/'fresh.json'
        self.m.initialize(self.ledger, self.auth, [self.old])
        self.request = dict(runId='fresh-test-1', operation='diagnostic', owner={'pid':123,'startUtc':'2026-09-26T17:00:00Z'}, tuple={'repositoryHead':'a'*40}, entrypoint='native-test.ps1', entrypointSha256='b'*64, arguments=['-RunId','fresh-test-1'], changedCondition='owner-reported correction', deadlineUtc='2099-01-01T00:00:00Z')
    def test_new_campaign_preserves_old(self):
        self.assertEqual(self.old.read_text(),'{"used":9,"historical":true}')
        self.assertEqual(self.m.status(self.ledger)['remaining']['diagnostic'],6)
    def test_reinitialize_cannot_reset(self):
        self.m.reserve(self.ledger,self.request)
        with self.assertRaises(ValueError): self.m.initialize(self.ledger,self.auth,[self.old])
        self.assertEqual(self.m.status(self.ledger)['remaining']['diagnostic'],5)
    def test_reservation_charged_before_action(self):
        self.m.reserve(self.ledger,self.request)
        self.assertEqual(self.m.status(self.ledger)['active']['runId'],'fresh-test-1')
        self.assertEqual(self.m.status(self.ledger)['remaining']['diagnostic'],5)
    def test_second_owner_cannot_overlap(self):
        self.m.reserve(self.ledger,self.request)
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,runId='second'))
    def test_finish_keeps_consumption_and_no_release_credit(self):
        self.m.reserve(self.ledger,self.request)
        self.m.finish(self.ledger,'fresh-test-1',self.request['owner'],2,'AUTH_REJECTED',[])
        s=self.m.status(self.ledger); self.assertIsNone(s['active']); self.assertEqual(s['remaining']['diagnostic'],5)
        self.assertFalse(s['certificationCredit'])
    def test_finish_wrong_owner_rejected(self):
        self.m.reserve(self.ledger,self.request)
        with self.assertRaises(ValueError): self.m.finish(self.ledger,'fresh-test-1',{'pid':124,'startUtc':'other'},0,'EXIT',[])
    def test_duplicate_run_id_rejected(self):
        self.m.reserve(self.ledger,self.request); self.m.finish(self.ledger,'fresh-test-1',self.request['owner'],0,'EXIT',[])
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,self.request)
    def test_dry_run_is_zero_write(self):
        before={p.name:p.read_bytes() for p in self.root.iterdir()}
        self.m.reserve(self.ledger,self.request,dry_run=True)
        self.assertEqual(before,{p.name:p.read_bytes() for p in self.root.iterdir()})
    def test_expired_deadline_rejected(self):
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,deadlineUtc='2000-01-01T00:00:00Z'))
    def test_missing_changed_condition_rejected(self):
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,changedCondition=''))
    def test_duplicate_json_key_rejected(self):
        self.ledger.write_text('{"schemaVersion":1,"schemaVersion":2}')
        with self.assertRaises(ValueError): self.m.status(self.ledger)
    def test_boolean_limit_rejected(self):
        d=json.loads(self.ledger.read_text()); d['limits']['diagnostic']=True; self.ledger.write_text(json.dumps(d))
        with self.assertRaises(ValueError): self.m.status(self.ledger)
    def test_nonfinite_rejected(self):
        self.ledger.write_text('{"number":NaN}')
        with self.assertRaises(ValueError): self.m.status(self.ledger)
    def test_changed_authorization_rejected(self):
        self.auth.write_text('replaced')
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,self.request)
    def test_exhaustion_has_no_refund(self):
        for i in range(6):
            q=dict(self.request,runId=f'fresh-{i}'); self.m.reserve(self.ledger,q); self.m.finish(self.ledger,q['runId'],q['owner'],1,'FAIL',[])
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,runId='seventh'))
    def test_negative_exit_is_not_silently_success(self):
        self.m.reserve(self.ledger,self.request); self.m.finish(self.ledger,'fresh-test-1',self.request['owner'],-1,'INTERRUPTED',[])
        self.assertEqual(json.loads(self.ledger.read_text())['attempts'][0]['exitCode'],-1)
    def test_bad_run_id_cannot_traverse(self):
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,runId='../escape'))
    def test_interrupted_atomic_write_retains_previous_record(self):
        before=self.ledger.read_bytes(); original=self.m.os.replace
        def fail(*a,**kw): raise OSError('simulated interrupted commit')
        self.m.os.replace=fail
        try:
            with self.assertRaises(OSError): self.m.reserve(self.ledger,self.request)
        finally: self.m.os.replace=original
        self.assertEqual(before,self.ledger.read_bytes())

    def test_held_os_lock_rejects_other_process_without_charge(self):
        q=self.root/'request.json'; q.write_text(json.dumps(self.request))
        cmd=[sys.executable,str(HERE/'fresh_attempts.py'),'reserve','--ledger',str(self.ledger),'--request',str(q)]
        with self.m.locked(self.ledger):
            denied=subprocess.run(cmd,capture_output=True,text=True,timeout=15)
        self.assertNotEqual(denied.returncode,0)
        self.assertEqual(self.m.status(self.ledger)['attemptCount'],0)
        accepted=subprocess.run(cmd,capture_output=True,text=True,timeout=15)
        self.assertEqual(accepted.returncode,0,accepted.stderr)
        self.assertEqual(self.m.status(self.ledger)['attemptCount'],1)
    def test_two_process_reservations_have_one_winner(self):
        workers=[]
        for i in range(2):
            q=self.root/f'request-{i}.json'; q.write_text(json.dumps(dict(self.request,runId=f'race-{i}')))
            workers.append(subprocess.Popen([sys.executable,str(HERE/'fresh_attempts.py'),'reserve','--ledger',str(self.ledger),'--request',str(q)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True))
        for worker in workers: worker.communicate(timeout=15)
        self.assertEqual(sum(w.returncode==0 for w in workers),1)
        self.assertEqual(self.m.status(self.ledger)['attemptCount'],1)

if __name__=='__main__': unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_guest_auth_diagnosis.py

SHA256: 22465e9161d47219513c96fd5647cacb2010c85fb19ec2fa14a2fde4057cf190 | Bytes: 6653 | Git mode: 100644

```
"""VM-free regressions for supplementary guest-auth event interpretation."""
import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from guest_auth_diagnosis import diagnose


RUN_ID = 'r2-historical-credential-20260927T011933Z-36149a48'
VM_ID = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
CLEAN_ID = '19865b76-4c3a-44f7-ba39-841e9d3c40c9'
LOG_HASH = 'b' * 64


class GuestAuthDiagnosisTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.report = {
            'scope': 'OFFLINE_READ_ONLY_GUEST_EVENT_INSPECTION',
            'vmId': VM_ID, 'parentCheckpointId': CLEAN_ID,
            'diskReadOnlyVerified': True, 'dismounted': True,
            'diskFileSizeUnchanged': True, 'diskWriteTimeUnchanged': True,
            'ledgerUnchanged': True, 'guestAuthenticationAttempted': False,
            'vmStarted': False, 'securityLogSha256': LOG_HASH,
            'events': [{
                'recordId': 3263, 'eventId': 4625,
                'timeUtc': '2026-09-27T01:20:06.9086047Z',
                'computer': 'DevFleet-E2E-01', 'targetUser': 'E2EAdmin',
                'status': '0xc000006e', 'subStatus': '0xc0000071',
            }],
        }
        self.ledger = {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2',
                       'activeRunId': None, 'attempts': [{
                           'runId': RUN_ID, 'operation': 'diagnostic',
                           'state': 'TERMINAL', 'certificationCredit': False,
                           'reservedUtc': '2026-09-27T01:19:33.266233+00:00',
                           'terminalUtc': '2026-09-27T01:20:09.640373+00:00',
                           'classification': 'E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN',
                       }]}
        self.readiness = {'certificationCredit': False,
                          'lab': {'l1Id': VM_ID, 'cleanId': CLEAN_ID},
                          'liveGuestAuth': {'attempted': True, 'cleanRestored': True,
                                            'connected': False, 'finalL1State': 'Off',
                                            'failureClass': 'System.Management.Automation.Remoting.PSDirectException'},
                          'admission': {'runId': RUN_ID, 'operation': 'diagnostic'},
                          'blockers': ['E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN']}

    def check(self, *, report=None, ledger=None, readiness=None,
              expected_report_hash=None, expected_log_hash=LOG_HASH):
        report = self.report if report is None else report
        ledger = self.ledger if ledger is None else ledger
        readiness = self.readiness if readiness is None else readiness
        def write(name, value):
            path = self.root / name
            path.write_text(json.dumps(value), encoding='utf-8')
            return path
        report_path = write('report.json', report)
        ledger_path = write('ledger.json', ledger)
        readiness_path = write('readiness.json', readiness)
        report_hash = expected_report_hash or hashlib.sha256(report_path.read_bytes()).hexdigest()
        return diagnose(report_path, report_hash, expected_log_hash,
                        ledger_path, readiness_path, RUN_ID)

    def test_exact_expiry_is_supplementary_only(self):
        result = self.check()
        self.assertEqual(result['classification'], 'PASSWORD_EXPIRED')
        self.assertEqual(result['event']['recordId'], 3263)
        self.assertEqual(result['event']['status'], '0xc000006e')
        self.assertEqual(result['event']['subStatus'], '0xc0000071')
        self.assertFalse(result['certificationCredit'])
        self.assertFalse(result['guestAuthenticated'])

    def test_wrong_password_disabled_lockout_and_unknown_are_distinct(self):
        cases = [('0xc000006d', '0xc000006a', 'WRONG_PASSWORD'),
                 ('0xc000006e', '0xc0000072', 'ACCOUNT_DISABLED'),
                 ('0xc0000234', '0xc0000234', 'ACCOUNT_LOCKED'),
                 ('0xdeadbeef', '0xdeadbeef', 'UNKNOWN_AUTH_FAILURE')]
        for status, substatus, expected in cases:
            with self.subTest(expected=expected):
                report = copy.deepcopy(self.report)
                report['events'][0].update(status=status, subStatus=substatus)
                self.assertEqual(self.check(report=report)['classification'], expected)

    def test_wrong_vm_account_time_and_conflicts_rejected(self):
        for edit in ('vm', 'account', 'time', 'conflict'):
            with self.subTest(edit=edit):
                report = copy.deepcopy(self.report)
                if edit == 'vm': report['vmId'] = '00000000-0000-0000-0000-000000000001'
                if edit == 'account': report['events'][0]['targetUser'] = 'SomeoneElse'
                if edit == 'time': report['events'][0]['timeUtc'] = '2026-09-27T01:30:06Z'
                if edit == 'conflict':
                    other = dict(report['events'][0], recordId=3264,
                                 status='0xc000006d', subStatus='0xc000006a')
                    report['events'].append(other)
                with self.assertRaises(ValueError): self.check(report=report)

    def test_missing_malformed_and_unverified_source_rejected(self):
        for edit in ('missing_event', 'missing_hash', 'not_read_only', 'bad_log_hash',
                     'wrong_report_hash', 'not_dismounted'):
            with self.subTest(edit=edit):
                report = copy.deepcopy(self.report)
                options = {}
                if edit == 'missing_event': report['events'] = []
                if edit == 'missing_hash': report.pop('securityLogSha256')
                if edit == 'not_read_only': report['diskReadOnlyVerified'] = False
                if edit == 'bad_log_hash': options['expected_log_hash'] = 'a' * 64
                if edit == 'wrong_report_hash': options['expected_report_hash'] = 'a' * 64
                if edit == 'not_dismounted': report['dismounted'] = False
                with self.assertRaises(ValueError): self.check(report=report, **options)

    def test_unverified_run_and_transport_cannot_be_expiry(self):
        ledger = copy.deepcopy(self.ledger)
        ledger['attempts'][0]['state'] = 'ACTIVE'
        with self.assertRaises(ValueError): self.check(ledger=ledger)
        readiness = copy.deepcopy(self.readiness)
        readiness['liveGuestAuth']['failureClass'] = 'System.TimeoutException'
        with self.assertRaises(ValueError): self.check(readiness=readiness)


if __name__ == '__main__': unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_one_diagnostic_successor.py

SHA256: 6f4bc5f5dcbf14324c13889e4066b3b5560f9a7e86df086a7e28ec6f7bd2a777 | Bytes: 4055 | Git mode: 100644

```
import importlib.util
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone


HERE = pathlib.Path(__file__).parent


class OneDiagnosticSuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.base_auth = self.root / 'base-auth.md'
        self.r2_auth = self.root / 'r2-auth.md'
        self.d1_auth = self.root / 'one-diagnostic-auth.md'
        for path, value in ((self.base_auth, 'base'), (self.r2_auth, 'r2'),
                            (self.d1_auth, 'one additional diagnostic only')):
            path.write_text(value, encoding='utf-8')
        self.base = self.root / 'base.json'
        self.r2 = self.root / 'r2.json'
        self.d1 = self.root / 'r2-d1.json'
        self.journal.initialize(self.base, self.base_auth, [])
        self.journal.initialize(self.r2, self.r2_auth, [self.base], self.journal.POLICY_ID + '-R2')

    def request(self, number, operation='diagnostic'):
        return {'runId': f'diagnostic-{number}', 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': '2026-09-27T00:00:00Z'},
                'tuple': {'repositoryHead': 'a' * 40}, 'entrypoint': 'readiness.ps1',
                'entrypointSha256': 'b' * 64, 'arguments': [],
                'changedCondition': 'independent bounded test',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def exhaust_r2(self):
        for number in range(6):
            request = self.request(number)
            self.journal.reserve(self.r2, request)
            self.journal.finish(self.r2, request['runId'], request['owner'], 2, 'TEST_TERMINAL', [])

    def test_only_one_diagnostic_and_no_other_operations(self):
        self.exhaust_r2()
        original = self.r2.read_bytes()
        self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.assertEqual(self.r2.read_bytes(), original)
        remaining = self.journal.status(self.d1)['remaining']
        self.assertEqual(remaining['diagnostic'], 1)
        self.assertTrue(all(value == 0 for key, value in remaining.items() if key != 'diagnostic'))
        with self.assertRaises(ValueError):
            self.journal.reserve(self.d1, self.request(11, 'laptop-proof'), dry_run=True)
        first = self.request(12)
        self.journal.reserve(self.d1, first)
        self.journal.finish(self.d1, first['runId'], first['owner'], 2, 'TEST_TERMINAL', [])
        self.assertEqual(self.journal.status(self.d1)['remaining']['diagnostic'], 0)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.d1, self.request(13), dry_run=True)

    def test_requires_exhausted_terminal_r2_and_separate_authorization(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.exhaust_r2()
        with self.assertRaises(ValueError):
            self.journal.initialize(self.d1, self.r2_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.jo