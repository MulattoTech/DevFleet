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
REPAIR_ID = POLICY_ID + '-R2-REPAIR-1'
REPAIR2_ID = POLICY_ID + '-R2-REPAIR-2'
REPAIR3_ID = POLICY_ID + '-R2-REPAIR-3'
REPAIR4_ID = POLICY_ID + '-R2-REPAIR-4'
REPAIR5_ID = POLICY_ID + '-R2-REPAIR-5'
CAUSAL_ID = 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1'
COLLISION_ID = 'DF-FRESH-CERTIFICATION-20260930-COLLISION-1'
HTTP_CLEANUP_ID = 'DF-FRESH-CERTIFICATION-20261001-HTTP-CLEANUP-1'
COLLISION_PREDECESSOR_SHA256 = '6deb98ab9dd165798e31538772f01e23eceeb333b10e0067a066685952f680e1'
COLLISION_OWNER_AUTH_SHA256 = 'f9eec666193447810089ffbd1ad249aba8f8e8a7d13e5220d10ef5ac2c64af16'
COLLISION_FIRST_ERROR = 'Cannot create a file when that file already exists.'
COLLISION_LEDGER_PATH = Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work\DevFleet-v1.2.13-development\audit\agent-memory\attempts\DF-FRESH-CERTIFICATION-20260930-COLLISION-1\ledger.json')
COLLISION_LIVE_CAUSAL_PATH = Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work\DevFleet-v1.2.13-development\audit\agent-memory\attempts\DF-FRESH-CERTIFICATION-20260929-CAUSAL-1\ledger.json')
HTTP_CLEANUP_PREDECESSOR_SHA256 = '2bede7d9944502898b919d4a29ed73f99c2009a819850349d5b08bfd6e8bb1c4'
HTTP_CLEANUP_LIVE_PREDECESSOR_PATH = Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work\DevFleet-v1.2.13-development\audit\agent-memory\attempts\DF-FRESH-CERTIFICATION-20260930-COLLISION-1\ledger.json')
HTTP_CLEANUP_LEDGER_PATH = Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work\DevFleet-v1.2.13-development\audit\agent-memory\attempts\DF-FRESH-CERTIFICATION-20261001-HTTP-CLEANUP-1\ledger.json')
HTTP_CLEANUP_GEN7_POINTER_SHA256 = '2fdd83acea55f9acc5ee2755de85d9144d026e365640f9ba36e8f7310979888d'
HTTP_CLEANUP_GEN7_RECEIPT_SHA256 = 'c10e200f68f6392aaa8c963f730e67aafc74e252af47a12facd7ef9bfcbcbd34'
HTTP_CLEANUP_GEN7_RECEIPT_FILE = '000feeb05be149088e8e07954282e80f.json'
HTTP_CLEANUP_CLEAN_R2_ID = '1e84fdaf-45f9-417e-a93c-354d05b4c766'
TUPLE_KEYS = ('repositoryHead', 'candidateBuildCommit', 'shippingInputIdentity',
              'releaseFingerprintId', 'toolingFingerprintId', 'candidateSha256')
REPAIR3_CANDIDATE_COMMIT = 'be0f1473838b4c2255d22efd99b25a58fd588a78'
REPAIR3_SHIPPING_SHA256 = '4d7d2dcfd486adb622e413ed9abe894df6d105457e91aa0f96779d776a5e4b44'
REPAIR3_SIGNED_EXE_SHA256 = '1ee8059ea9ae253ab358b9aec5241aae1019676cb54544b5f352080cdf132908'
REPAIR3_FAILED_LEDGER_SHA256 = 'dffe7810cc2f1833ed73a9514a8a49e4d65eed67eac0bf936bf81a1c8d6521ff'
REPAIR3_RECEIPT_SHA256 = 'b071752cc2042b3405c05856780f74bbecdc11d0c647c8b602404c73829034b6'
REPAIR5_PREDECESSOR_SHA256 = 'bc9401e921754628b95f1f5ceff6308bc3607ae790690cfca786222eadf71ee4'
LIMITS = {'standard-token': 3, 'laptop-proof': 3, 'desktop-proof': 3,
          'fullrelease': 3, 'diagnostic': 6, 'maintenance': 3, 'build-sign': 3}
ONE_DIAGNOSTIC_LIMITS = {operation: (1 if operation == 'diagnostic' else 0)
                         for operation in LIMITS}
REPAIR_LIMITS = {operation: (1 if operation in ('standard-token', 'diagnostic',
                                               'laptop-proof', 'desktop-proof',
                                               'fullrelease') else 0)
                 for operation in LIMITS}
REPAIR_SEQUENCE = (('standard-token', 'PASS_NATIVE_STANDARD_TOKEN'),
                   ('diagnostic', 'PASS_READY_FOR_PROOF_RESERVATION'),
                   ('laptop-proof', 'NATIVE_LAPTOP_PROOF_PASS'),
                   ('desktop-proof', 'NATIVE_DESKTOP_PROOF_PASS'),
                   ('fullrelease', 'NATIVE_FULLRELEASE_PASS'))
REPAIR2_LIMITS = {operation: (1 if operation in ('build-sign', 'standard-token',
                                                'diagnostic', 'laptop-proof',
                                                'desktop-proof', 'fullrelease') else 0)
                  for operation in LIMITS}
REPAIR2_SEQUENCE = (('build-sign', 'PASS_NATIVE_BUILD_SIGN'),) + REPAIR_SEQUENCE
REPAIR3_LIMITS = {operation: (1 if operation in ('standard-token', 'diagnostic',
                                                'laptop-proof', 'desktop-proof',
                                                'fullrelease') else 0)
                  for operation in LIMITS}
REPAIR3_SEQUENCE = REPAIR_SEQUENCE
REPAIR4_LIMITS = dict(REPAIR3_LIMITS)
REPAIR4_SEQUENCE = REPAIR_SEQUENCE
REPAIR5_LIMITS = dict(REPAIR4_LIMITS)
REPAIR5_SEQUENCE = REPAIR_SEQUENCE
COLLISION_LIMITS = dict(REPAIR5_LIMITS)
HTTP_CLEANUP_LIMITS = {'standard-token': 1, 'diagnostic': 1,
                       'laptop-proof': 1, 'desktop-proof': 1,
                       'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
HTTP_CLEANUP_SEQUENCE = REPAIR_SEQUENCE


def sequence_for(policy_id):
    if policy_id == REPAIR2_ID:
        return REPAIR2_SEQUENCE
    if policy_id == REPAIR3_ID:
        return REPAIR3_SEQUENCE
    if policy_id == REPAIR4_ID:
        return REPAIR4_SEQUENCE
    if policy_id in (REPAIR5_ID, COLLISION_ID):
        return REPAIR5_SEQUENCE
    if policy_id == HTTP_CLEANUP_ID:
        return HTTP_CLEANUP_SEQUENCE
    return REPAIR_SEQUENCE


def limits_for(policy_id):
    if policy_id == ONE_DIAGNOSTIC_ID:
        return ONE_DIAGNOSTIC_LIMITS
    if policy_id == REPAIR_ID:
        return REPAIR_LIMITS
    if policy_id == REPAIR2_ID:
        return REPAIR2_LIMITS
    if policy_id == REPAIR3_ID:
        return REPAIR3_LIMITS
    if policy_id == REPAIR4_ID:
        return REPAIR4_LIMITS
    if policy_id == REPAIR5_ID:
        return REPAIR5_LIMITS
    if policy_id == COLLISION_ID:
        return COLLISION_LIMITS
    if policy_id == HTTP_CLEANUP_ID:
        return HTTP_CLEANUP_LIMITS
    if policy_id == CAUSAL_ID:
        return REPAIR5_LIMITS
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

def _load_repair3_receipt(path):
    if not path:
        raise ValueError('Repair3 immutable artifact receipt is required')
    path = safe_path(path)
    if not path.is_file():
        raise ValueError('Repair3 immutable artifact receipt is required')
    receipt = strict_json(path)
    if digest(path) != REPAIR3_RECEIPT_SHA256:
        raise ValueError('Repair3 artifact receipt source identity differs')
    required = {'schemaVersion', 'contract', 'status', 'certificationCredit',
                'repositoryHead', 'failedAttemptLedgerSha256',
                'shippingInputIdentity', 'artifacts', 'signatureStatus',
                'publicPromotionAllowed', 'publicPublisherTrust'}
    if not isinstance(receipt, dict) or not required.issubset(receipt):
        raise ValueError('Repair3 artifact receipt is malformed')
    if receipt['schemaVersion'] != 1 or receipt['contract'] != 'devfleet-signed-build-output-inspection-v1':
        raise ValueError('Repair3 artifact receipt schema is unsupported')
    if receipt['status'] != 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION' or receipt['certificationCredit'] is not False:
        raise ValueError('Repair3 artifact receipt is not non-certifying verified output')
    if receipt['repositoryHead'] != REPAIR3_CANDIDATE_COMMIT:
        raise ValueError('Repair3 artifact receipt candidate binding differs')
    if receipt['failedAttemptLedgerSha256'] != REPAIR3_FAILED_LEDGER_SHA256:
        raise ValueError('Repair3 artifact receipt failed ledger binding differs')
    if receipt['shippingInputIdentity'] != REPAIR3_SHIPPING_SHA256:
        raise ValueError('Repair3 artifact receipt shipping binding differs')
    if receipt['signatureStatus'] != 'Valid' or receipt['publicPromotionAllowed'] is not False or receipt['publicPublisherTrust'] is not False:
        raise ValueError('Repair3 artifact receipt signature/trust boundary differs')
    artifacts = receipt['artifacts']
    if not isinstance(artifacts, list) or len(artifacts) != 4:
        raise ValueError('Repair3 artifact receipt must bind four artifacts')
    names = set()
    for artifact in artifacts:
        if (not isinstance(artifact, dict)
                or not {'name', 'path', 'sha256'}.issubset(artifact)
                or not isinstance(artifact['name'], str) or not artifact['name']
                or not isinstance(artifact['path'], str) or not artifact['path']
                or not re.fullmatch(r'[a-f0-9]{64}', str(artifact['sha256']))):
            raise ValueError('Repair3 artifact receipt contains malformed artifact')
        if artifact['name'] in names:
            raise ValueError('Repair3 artifact receipt contains duplicate artifact')
        names.add(artifact['name'])
    if names != {'exe', 'tar', 'portable', 'installerSource'}:
        raise ValueError('Repair3 artifact receipt does not bind the exact four artifacts')
    exe = next(artifact for artifact in artifacts if artifact['name'] == 'exe')
    if exe['sha256'] != REPAIR3_SIGNED_EXE_SHA256:
        raise ValueError('Repair3 artifact receipt signed executable binding differs')
    return path


def _validate_causal_sources(ledger, authorization, predecessors):
    """Preserve both owner-reviewed terminal histories; never carry slots forward."""
    paths = [safe_path(p) for p in predecessors]
    ledger, authorization = safe_path(ledger), safe_path(authorization)
    if len(paths) != 4 or len(set(paths)) != 4 or ledger in paths or authorization in (*paths, ledger):
        raise ValueError('Causal successor requires distinct R5/D1 snapshot, live and authorization paths')
    approval = strict_json(authorization)
    if (approval.get('schemaVersion') != 1
            or approval.get('kind') != 'DEVFLEET_CAUSAL_SUCCESSOR_AUTHORIZATION'
            or approval.get('policyId') != CAUSAL_ID or approval.get('approved') is not True):
        raise ValueError('Explicit causal successor owner approval is required')
    limits = approval.get('limits')
    if (not isinstance(limits, dict) or set(limits) != set(REPAIR5_LIMITS)
            or any(type(limits[k]) is not int or limits[k] != REPAIR5_LIMITS[k] for k in REPAIR5_LIMITS)):
        raise ValueError('Causal successor approval cannot widen the finite sequence')
    hashes = approval.get('predecessorSha256')
    if (not isinstance(hashes, dict) or set(hashes) != {'r5', 'imageD1'}
            or any(not isinstance(v, str) or not re.fullmatch('[a-f0-9]{64}', v) for v in hashes.values())):
        raise ValueError('Owner-reviewed R5 and D1 hashes are required')
    for first, expected in ((0, hashes['r5']), (2, hashes['imageD1'])):
        if digest(paths[first]) != expected or digest(paths[first + 1]) != expected:
            raise ValueError('Causal predecessor snapshot/live bytes differ from owner review')
    expected_policies = (REPAIR5_ID, REPAIR5_ID, ONE_DIAGNOSTIC_ID, ONE_DIAGNOSTIC_ID)
    if any(strict_json(path).get('policyId') != policy for path, policy in zip(paths, expected_policies)):
        raise ValueError('Causal predecessor policy is not the reviewed R5/D1 history')
    parents = [load(path) for path in paths]
    if any(parent.get('activeRunId') is not None for parent in parents):
        raise ValueError('Causal successor cannot replace active owned execution')
    r5_results = (('standard-token', 0, 'PASS_NATIVE_STANDARD_TOKEN'),
                  ('diagnostic', 0, 'PASS_READY_FOR_PROOF_RESERVATION'),
                  ('laptop-proof', 2, 'NATIVE_LAPTOP_PROOF_BLOCKED'))
    for parent in parents[:2]:
        attempts = parent.get('attempts', [])
        if len(attempts) != 3 or any(
                a.get('state') != 'TERMINAL' or a.get('operation') != op
                or a.get('exitCode') != code or a.get('classification') != result
                for a, (op, code, result) in zip(attempts, r5_results)):
            raise ValueError('Causal predecessor must preserve the charged blocked R5 Laptop')
    for parent in parents[2:]:
        attempts = parent.get('attempts', [])
        if (len(attempts) != 1 or attempts[0].get('state') != 'TERMINAL'
                or attempts[0].get('operation') != 'diagnostic' or attempts[0].get('exitCode') != 0
                or attempts[0].get('classification') != 'DIAGNOSTIC_IMAGE_REMOTE_FAILURE_NOT_REPRODUCED'):
            raise ValueError('Causal predecessor must preserve the exhausted IMAGE-D1 diagnostic')
    if any(parent['authorization']['sha256'] == digest(authorization) for parent in parents):
        raise ValueError('Causal successor requires a new explicit owner authorization source')


def _collision_tuple(value):
    if not isinstance(value, dict) or set(value) != set(TUPLE_KEYS):
        raise ValueError('Post-collision candidate tuple must contain six exact fields')
    for key in TUPLE_KEYS:
        width = 40 if key in ('repositoryHead', 'candidateBuildCommit') else 64
        if not isinstance(value[key], str) or not re.fullmatch(f'[a-f0-9]{{{width}}}', value[key]):
            raise ValueError('Post-collision candidate tuple is malformed: ' + key)
    return value


def _collision_path(value, *, existing=True):
    if not isinstance(value, str) or not value or not Path(value).is_absolute():
        raise ValueError('Post-collision source path must be canonical and absolute')
    path = safe_path(value)
    resolved = path.resolve(strict=existing)
    if path != resolved or (existing and not path.is_file()):
        raise ValueError('Post-collision source path is not canonical or is absent')
    return path


def _collision_ref(value):
    if not isinstance(value, dict) or set(value) != {'path', 'sha256'}:
        raise ValueError('Post-collision source reference is malformed')
    path = _collision_path(value['path'])
    if not isinstance(value['sha256'], str) or not re.fullmatch(r'[a-f0-9]{64}', value['sha256']):
        raise ValueError('Post-collision source hash is malformed')
    if digest(path) != value['sha256']:
        raise ValueError('Post-collision source bytes changed')
    return path


def _collision_record_run(record, expected, *, required=False):
    """Check fields when a native record exposes them; hash still binds every byte."""
    if not isinstance(record, dict):
        raise ValueError('Post-collision evidence must be a JSON object')
    keys = ('runId', 'attemptRunId', 'proofRunId')
    if required and not any(key in record for key in keys):
        raise ValueError('Post-collision evidence lacks a failed RunId')
    for key in keys:
        if key in record and record[key] != expected:
            raise ValueError('Post-collision evidence belongs to another RunId')


def _collision_ancestor_run_ids(root, protected):
    """Hash-check every referenced ancestor, including both historical snapshot/live copies."""
    seen = set()
    run_ids = set()
    pending = [root]
    while pending:
        current = pending.pop()
        references = current.get('predecessors', [])
        if not isinstance(references, list):
            raise ValueError('Post-collision ancestor lineage is malformed')
        for reference in references:
            path = _collision_ref(reference)
            if path in protected:
                raise ValueError('Post-collision ancestor location collides with successor source')
            if path in seen:
                continue
            seen.add(path)
            if len(seen) > 128:
                raise ValueError('Post-collision ancestor lineage exceeds bounded size')
            ancestor = strict_json(path)
            if not isinstance(ancestor, dict) or ancestor.get('activeRunId') is not None:
                raise ValueError('Post-collision ancestor is malformed or active')
            attempts = ancestor.get('attempts', [])
            if not isinstance(attempts, list):
                raise ValueError('Post-collision ancestor attempts are malformed')
            for attempt in attempts:
                if (not isinstance(attempt, dict) or attempt.get('state') != 'TERMINAL'
                        or not isinstance(attempt.get('runId'), str) or not attempt['runId']):
                    raise ValueError('Post-collision ancestor has an unterminalized RunId')
                run_ids.add(attempt['runId'])
            pending.append(ancestor)
    return run_ids


def _validate_collision_sources(ledger, authorization, predecessors):
    """Bind exact terminal CAUSAL-1, owner words, correction and failure evidence."""
    if not isinstance(predecessors, list) or len(predecessors) != 1:
        raise ValueError('Post-collision successor requires one terminal CAUSAL-1 predecessor')
    ledger = _collision_path(str(ledger), existing=False)
    authorization = _collision_path(str(authorization))
    predecessor = _collision_path(str(predecessors[0]))
    live_causal = _collision_path(str(COLLISION_LIVE_CAUSAL_PATH))
    if (ledger != _collision_path(str(COLLISION_LEDGER_PATH), existing=False)
            or len({ledger, authorization, predecessor, live_causal}) != 4):
        raise ValueError('Post-collision ledger, approval and predecessor must be distinct')
    approval = strict_json(authorization)
    required = {'schemaVersion', 'kind', 'policyId', 'approved', 'approvedBy',
                'ownerAuthorization', 'successorLedgerPath', 'predecessorSha256',
                'failedRunId', 'previousCandidate', 'candidate', 'generation6',
                'reviewedSources', 'failureEvidence', 'limits'}
    if (not isinstance(approval, dict) or set(approval) != required
            or type(approval['schemaVersion']) is not int or approval['schemaVersion'] != 1
            or approval['kind'] != 'DEVFLEET_POST_COLLISION_SUCCESSOR_AUTHORIZATION'
            or approval['policyId'] != COLLISION_ID or approval['approved'] is not True
            or approval['approvedBy'] != 'ACCOUNT_OWNER'
            or _collision_path(approval['successorLedgerPath'], existing=False) != ledger):
        raise ValueError('Exact post-collision owner authorization is required')
    limits = approval['limits']
    if (not isinstance(limits, dict) or set(limits) != set(COLLISION_LIMITS)
            or any(type(limits[key]) is not int or limits[key] != value
                   for key, value in COLLISION_LIMITS.items())):
        raise ValueError('Post-collision finite limits were widened or malformed')
    old_tuple = _collision_tuple(approval['previousCandidate'])
    new_tuple = _collision_tuple(approval['candidate'])
    for key in ('candidateBuildCommit', 'shippingInputIdentity',
                'releaseFingerprintId', 'candidateSha256'):
        if old_tuple[key] != new_tuple[key]:
            raise ValueError('Post-collision shipping identity changed: ' + key)
    if (old_tuple['repositoryHead'] == new_tuple['repositoryHead']
            or old_tuple['toolingFingerprintId'] == new_tuple['toolingFingerprintId']):
        raise ValueError('Post-collision successor requires changed HEAD and tooling')
    owner_source = _collision_ref(approval['ownerAuthorization'])
    if digest(owner_source) != COLLISION_OWNER_AUTH_SHA256:
        raise ValueError('Post-collision owner message differs from exact authorization')
    owner_words = owner_source.read_text(encoding='utf-8-sig')
    if (COLLISION_ID not in owner_words
            or any(f'{label} = {value}' not in owner_words for label, value in
                   [('standard-token', 1), ('diagnostic/readiness', 1), ('laptop-proof', 1),
                    ('desktop-proof', 1), ('fullrelease', 1), ('maintenance', 0), ('build-sign', 0)])
            or 'no signed-shipping change' not in owner_words):
        raise ValueError('Post-collision owner message does not authorize this exact scope')
    if (not isinstance(approval['predecessorSha256'], dict) or approval['predecessorSha256'] != {
            'causal1': COLLISION_PREDECESSOR_SHA256} or digest(predecessor) != COLLISION_PREDECESSOR_SHA256
            or digest(live_causal) != COLLISION_PREDECESSOR_SHA256):
        raise ValueError('Exact terminal CAUSAL-1 predecessor changed')
    prior = strict_json(predecessor)
    attempts = prior.get('attempts') if isinstance(prior, dict) else None
    expected = (('standard-token', 0, 'PASS_NATIVE_STANDARD_TOKEN'),
                ('diagnostic', 0, 'PASS_READY_FOR_PROOF_RESERVATION'),
                ('laptop-proof', 2, 'NATIVE_LAPTOP_PROOF_BLOCKED'))
    if (prior.get('schemaVersion') != 1 or prior.get('policyId') != CAUSAL_ID
            or prior.get('certificationCredit') is not False
            or prior.get('limits') != REPAIR5_LIMITS or prior.get('activeRunId') is not None
            or not isinstance(attempts, list) or len(attempts) != 3
            or any(not isinstance(a, dict) or a.get('operation') != op
                   or a.get('state') != 'TERMINAL' or a.get('exitCode') != code
                   or a.get('classification') != result or a.get('tuple') != old_tuple
                   for a, (op, code, result) in zip(attempts, expected))):
        raise ValueError('CAUSAL-1 predecessor is not the exact terminal three-attempt history')
    old_run_ids = [a.get('runId') for a in attempts]
    if (any(not isinstance(run, str) or not run for run in old_run_ids)
            or len(set(old_run_ids)) != 3 or approval['failedRunId'] != old_run_ids[-1]):
        raise ValueError('Post-collision failed RunId does not bind CAUSAL-1 history')
    direct = prior.get('predecessors')
    if (not isinstance(direct, list) or len(direct) != 4
            or any(not isinstance(row, dict) or set(row) != {'path', 'sha256'} for row in direct)
            or direct[0]['sha256'] != direct[1]['sha256']
            or direct[2]['sha256'] != direct[3]['sha256']):
        raise ValueError('Post-collision CAUSAL-1 R5/D1 ancestor references differ')
    ancestor_run_ids = _collision_ancestor_run_ids(
        prior, {ledger, authorization, predecessor, live_causal, owner_source})
    for index, expected_policy in enumerate((REPAIR5_ID, REPAIR5_ID,
                                              ONE_DIAGNOSTIC_ID, ONE_DIAGNOSTIC_ID)):
        if strict_json(direct[index]['path']).get('policyId') != expected_policy:
            raise ValueError('Post-collision CAUSAL-1 ancestor policy differs')
    if (not isinstance(prior.get('authorization'), dict)
            or prior['authorization'].get('sha256') == digest(authorization)):
        raise ValueError('Post-collision authorization repeats predecessor source')
    generation6 = approval['generation6']
    if not isinstance(generation6, dict) or set(generation6) != {'receiptPath', 'receiptSha256', 'checkpoint'}:
        raise ValueError('Generation-6 lineage reference is malformed')
    receipt_path = _collision_ref({'path': generation6['receiptPath'], 'sha256': generation6['receiptSha256']})
    receipt = strict_json(receipt_path)
    if (receipt.get('schemaVersion') != 6
            or receipt.get('contract') != 'devfleet-baseline-rebind-receipt-v6'
            or receipt.get('status') != 'REBOUND' or receipt.get('certificationCredit') is not False
            or receipt.get('candidate') != old_tuple
            or receipt.get('replacement') != generation6['checkpoint']
            or not isinstance(generation6['checkpoint'], dict)
            or not generation6['checkpoint'].get('id')):
        raise ValueError('Generation-6 receipt/checkpoint differs from predecessor tuple')
    refs = approval['reviewedSources']
    evidence = approval['failureEvidence']
    if (not isinstance(refs, dict) or set(refs) != {'proposal', 'source'}
            or not isinstance(evidence, dict) or set(evidence) != {'wrapper', 'proofError', 'cleanup'}):
        raise ValueError('Reviewed proposal/source or collision evidence is incomplete')
    paths = [ledger, authorization, predecessor, live_causal, owner_source, receipt_path]
    for group, names in ((refs, ('proposal', 'source')),
                         (evidence, ('wrapper', 'proofError', 'cleanup'))):
        paths.extend(_collision_ref(group[name]) for name in names)
    if len(paths) != len(set(paths)):
        raise ValueError('Post-collision evidence locations must be distinct')
    for name in ('proposal', 'source'):
        path = _collision_path(refs[name]['path'])
        if path.suffix.lower() == '.json':
            reviewed = strict_json(path)
            _collision_record_run(reviewed, approval['failedRunId'])
            if 'previousCandidate' in reviewed and reviewed['previousCandidate'] != old_tuple:
                raise ValueError('Reviewed source predecessor tuple differs')
            if 'candidate' in reviewed and reviewed['candidate'] != new_tuple:
                raise ValueError('Reviewed source candidate tuple differs')
    wrapper = strict_json(evidence['wrapper']['path'])
    proof_error = strict_json(evidence['proofError']['path'])
    cleanup = strict_json(evidence['cleanup']['path'])
    for record in (wrapper, proof_error, cleanup):
        _collision_record_run(record, approval['failedRunId'], required=True)
    l1, l2 = cleanup.get('l1'), cleanup.get('l2')
    if (wrapper.get('classification') != 'NATIVE_LAPTOP_PROOF_BLOCKED'
            or wrapper.get('exitCode') != 2
            or wrapper.get('firstTechnicalFailure') != COLLISION_FIRST_ERROR
            or proof_error.get('status') != 'BLOCKED'
            or proof_error.get('error') != COLLISION_FIRST_ERROR
            or cleanup.get('status') != 'PASS'
            or cleanup.get('runOwnedOnly') is not True
            or not isinstance(l1, dict)
            or l1.get('name') != 'DevFleet-E2E-Win11-01'
            or l1.get('id') != '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
            or l1.get('status') != 'OFF'
            or not isinstance(l2, dict)
            or l2.get('expectedName') != 'DevFleet-E2E-Linux-01'
            or l2.get('present') is not False
            or type(l2.get('exactMatchCount')) is not int or l2['exactMatchCount'] != 0
            or type(l2.get('inventoryCount')) is not int or l2['inventoryCount'] != 0
            or l2.get('status') != 'ABSENT'
            or cleanup.get('l2Present') is not False):
        raise ValueError('Collision failure/cleanup evidence contradicts terminal predecessor')
    if wrapper.get('observerTerminal') == COLLISION_FIRST_ERROR:
        raise ValueError('Collision first failure is absent or conflated with observer terminal')
    return approval, set(old_run_ids) | ancestor_run_ids


def _validate_http_cleanup_sources(ledger, authorization, predecessors):
    """Validate exact terminal COLLISION-1 and the owner-reviewed HTTP successor."""
    def require(condition, message):
        if not condition:
            raise ValueError('HTTP-CLEANUP-1 ' + message)

    def source_ref(value, label):
        try:
            return _collision_ref(value)
        except (ValueError, KeyError, TypeError, OSError) as exc:
            raise ValueError('HTTP-CLEANUP-1 ' + label + ' reference is invalid') from exc

    ledger = Path(ledger).absolute()
    authorization = _collision_path(str(authorization))
    require(ledger == safe_path(HTTP_CLEANUP_LEDGER_PATH),
            'ledger path differs from its canonical owner-bound path')
    require(isinstance(predecessors, list) and len(predecessors) == 2,
            'requires exactly one immutable snapshot and one live predecessor')
    snapshot = _collision_path(str(predecessors[0]))
    live = _collision_path(str(predecessors[1]))
    expected_live = _collision_path(str(HTTP_CLEANUP_LIVE_PREDECESSOR_PATH))
    expected_snapshot = _collision_path(str(ledger.parent / 'predecessors' / 'COLLISION-1-ledger.json'))
    require(snapshot == expected_snapshot and live == expected_live and snapshot != live,
            'predecessor paths are missing, aliased, or noncanonical')
    require(len({ledger, authorization, snapshot, live}) == 4,
            'ledger, authorization, snapshot, and live predecessor must be distinct')
    expected_hash = HTTP_CLEANUP_PREDECESSOR_SHA256
    require(re.fullmatch(r'[a-f0-9]{64}', expected_hash) is not None,
            'configured predecessor hash is malformed')
    require(digest(snapshot) == expected_hash and digest(live) == expected_hash
            and digest(snapshot) == digest(live),
            'immutable snapshot and exact live predecessor differ')

    approval = strict_json(authorization)
    required = {'schemaVersion', 'kind', 'policyId', 'approved', 'approvedBy',
                'ownerAuthorization', 'successorLedgerPath', 'predecessorSha256',
                'previousCandidate', 'candidate', 'limits', 'shippingChangeApproved',
                'publicMainSha', 'reviewedSources', 'failureEvidence', 'generation7'}
    require(isinstance(approval, dict) and set(approval) == required
            and type(approval.get('schemaVersion')) is int and approval['schemaVersion'] == 1
            and approval.get('kind') == 'DEVFLEET_HTTP_CLEANUP_SUCCESSOR_AUTHORIZATION'
            and approval.get('policyId') == HTTP_CLEANUP_ID
            and approval.get('approved') is True
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('shippingChangeApproved') is False,
            'exact account-owner authorization schema is required')
    require(_collision_path(approval.get('successorLedgerPath'), existing=False) == ledger,
            'authorization names another successor ledger')
    limits = approval.get('limits')
    require(isinstance(limits, dict) and set(limits) == set(HTTP_CLEANUP_LIMITS)
            and all(type(limits.get(key)) is int and limits[key] == value
                    for key, value in HTTP_CLEANUP_LIMITS.items()),
            'finite limits are widened, noninteger, missing, or extra')
    require(approval.get('predecessorSha256') == {'collision1': expected_hash},
            'authorization predecessor hash differs')
    require(isinstance(approval.get('publicMainSha'), str)
            and re.fullmatch(r'[a-f0-9]{40}', approval['publicMainSha']) is not None,
            'reviewed public main commit is malformed')

    old_tuple = _collision_tuple(approval.get('previousCandidate'))
    new_tuple = _collision_tuple(approval.get('candidate'))
    for key in ('candidateBuildCommit', 'shippingInputIdentity',
                'releaseFingerprintId', 'candidateSha256'):
        require(old_tuple[key] == new_tuple[key], 'signed shipping changed: ' + key)
    require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
            and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
            'repository HEAD and tooling fingerprint must both change')

    owner = source_ref(approval.get('ownerAuthorization'), 'owner authorization')
    require(owner not in {ledger, authorization, snapshot, live},
            'owner authorization source aliases another bound source')
    owner_text = owner.read_text(encoding='utf-8-sig')
    owner_requirements = [HTTP_CLEANUP_ID,
                          'standard-token = 1', 'diagnostic/readiness = 1',
                          'laptop-proof = 1', 'desktop-proof = 1', 'fullrelease = 1',
                          'maintenance = 0', 'build-sign = 0',
                          'No signed-shipping change is authorized.',
                          f'publicMainSha={approval["publicMainSha"]}',
                          f'predecessorSha256={expected_hash}']
    require(all(value in owner_text for value in owner_requirements)
            and all(f'previousCandidate.{key}={value}' in owner_text
                    for key, value in old_tuple.items())
            and all(f'candidate.{key}={value}' in owner_text
                    for key, value in new_tuple.items()),
            'owner source does not approve the exact tuple and finite scope')

    gen7 = approval.get('generation7')
    require(isinstance(gen7, dict) and set(gen7) == {'pointer', 'receipt', 'checkpoint'},
            'Generation-7 lineage references are incomplete')
    pointer_path = source_ref(gen7.get('pointer'), 'Generation-7 pointer')
    receipt_path = source_ref(gen7.get('receipt'), 'Generation-7 receipt')
    require(digest(pointer_path) == HTTP_CLEANUP_GEN7_POINTER_SHA256
            and digest(receipt_path) == HTTP_CLEANUP_GEN7_RECEIPT_SHA256
            and receipt_path.name == HTTP_CLEANUP_GEN7_RECEIPT_FILE,
            'Generation-7 pointer or receipt differs from the accepted baseline')
    pointer = strict_json(pointer_path)
    receipt = strict_json(receipt_path)
    checkpoint = gen7.get('checkpoint')
    require(isinstance(checkpoint, dict)
            and checkpoint.get('name') == 'DevFleet-E2E-CLEAN-R2'
            and checkpoint.get('id') == HTTP_CLEANUP_CLEAN_R2_ID,
            'Generation-7 CLEAN-R2 checkpoint identity is absent')
    require(pointer.get('schemaVersion') == 7
            and pointer.get('contract') == 'devfleet-accepted-baseline-v7'
            and pointer.get('generation') == 7 and pointer.get('status') == 'ACCEPTED'
            and pointer.get('receiptFile') == receipt_path.name
            and pointer.get('receiptSha256') == gen7['receipt']['sha256']
            and pointer.get('checkpoint') == checkpoint,
            'accepted Generation-7 pointer or receipt link differs')
    require(receipt.get('schemaVersion') == 7
            and receipt.get('contract') == 'devfleet-baseline-rebind-receipt-v7'
            and receipt.get('status') == 'REBOUND'
            and receipt.get('candidate') == old_tuple
            and receipt.get('replacement') == checkpoint,
            'Generation-7 receipt does not bind the predecessor tuple and checkpoint')

    refs = approval.get('reviewedSources')
    failure = approval.get('failureEvidence')
    require(isinstance(refs, dict) and set(refs) == {'httpHostileExecutor', 'httpHostileRegression'}
            and isinstance(failure, dict)
            and set(failure) == {'fullReleaseWrapper', 'runState', 'error',
                                 'failureCleanup', 'requestAdmission'},
            'reviewed HTTP correction or FullRelease blocker evidence is incomplete')
    source_paths = [source_ref(refs[key], 'reviewed source')
                    for key in ('httpHostileExecutor', 'httpHostileRegression')]
    failure_paths = [source_ref(failure[key], 'FullRelease failure evidence') for key in
                     ('fullReleaseWrapper', 'runState', 'error', 'failureCleanup',
                      'requestAdmission')]
    all_paths = [ledger, authorization, snapshot, live, owner, pointer_path,
                 receipt_path, *source_paths, *failure_paths]
    require(len(all_paths) == len(set(all_paths)),
            'bound paths contain aliases or a second live ledger')
    require(source_paths[0].suffix.lower() == '.ps1'
            and source_paths[1].suffix.lower() == '.ps1',
            'reviewed executor and regression must be pinned source files')

    # Load only the canonical live ledger as COLLISION-1. The snapshot is a
    # byte-identical immutable copy, not a second campaign ledger to dispatch.
    predecessor = load(live)
    attempts = predecessor.get('attempts')
    expected_sequence = (('standard-token', 0, 'PASS_NATIVE_STANDARD_TOKEN'),
                         ('diagnostic', 0, 'PASS_READY_FOR_PROOF_RESERVATION'),
                         ('laptop-proof', 0, 'NATIVE_LAPTOP_PROOF_PASS'),
                         ('desktop-proof', 0, 'NATIVE_DESKTOP_PROOF_PASS'),
                         ('fullrelease', 2, 'NATIVE_FULLRELEASE_BLOCKED'))
    require(predecessor.get('policyId') == COLLISION_ID
            and predecessor.get('activeRunId') is None
            and predecessor.get('certificationCredit') is False
            and predecessor.get('limits') == COLLISION_LIMITS
            and isinstance(attempts, list) and len(attempts) == len(expected_sequence),
            'predecessor is not exact inactive exhausted COLLISION-1')
    require(all(isinstance(attempt, dict) and attempt.get('state') == 'TERMINAL'
                and attempt.get('operation') == operation
                and attempt.get('exitCode') == exit_code
                and attempt.get('classification') == classification
                and attempt.get('tuple') == old_tuple
                for attempt, (operation, exit_code, classification)
                in zip(attempts, expected_sequence)),
            'predecessor terminal history differs from exact five-attempt sequence')
    run_ids = [attempt.get('runId') for attempt in attempts]
    require(all(isinstance(run_id, str) and run_id for run_id in run_ids)
            and len(set(run_ids)) == len(run_ids),
            'predecessor RunIds are missing or duplicated')
    fullrelease_run = run_ids[-1]
    wrapper = strict_json(failure['fullReleaseWrapper']['path'])
    run_state = strict_json(failure['runState']['path'])
    cleanup = strict_json(failure['failureCleanup']['path'])
    admission = strict_json(failure['requestAdmission']['path'])
    error_text = failure_paths[2].read_text(encoding='utf-8-sig')
    require(wrapper.get('runId') == fullrelease_run
            and wrapper.get('classification') == 'NATIVE_FULLRELEASE_BLOCKED'
            and wrapper.get('exitCode') == 2
            and wrapper.get('currentPhase') == 'HTTP-HOSTILE'
            and isinstance(wrapper.get('firstTechnicalFailure'), str)
            and wrapper['firstTechnicalFailure'] in error_text
            and wrapper.get('observerTerminal') != wrapper.get('firstTechnicalFailure')
            and run_state.get('runId') == fullrelease_run
            and run_state.get('currentPhase') == 'HTTP-HOSTILE'
            and fullrelease_run in error_text
            and 'sharing violation' in error_text.lower()
            and 'ruby-rails' in error_text.lower(),
            'FullRelease blocker evidence does not bind the HTTP-HOSTILE cleanup failure')
    require(admission.get('runId') == fullrelease_run
            and admission.get('phase') == 'HTTP-HOSTILE'
            and admission.get('classification') == 'PASS_HTTP_HOSTILE_REQUEST_ADMISSION'
            and type(admission.get('passedTests')) is int and admission['passedTests'] == 10
            and type(admission.get('failedTests')) is int and admission['failedTests'] == 0,
            'HTTP-HOSTILE request-admission evidence is not an exact ten-test PASS')
    l1, l2 = cleanup.get('l1'), cleanup.get('l2')
    require(cleanup.get('runId') == fullrelease_run
            and isinstance(l1, dict) and l1.get('state') == 'Off'
            and isinstance(l2, dict) and l2.get('status') == 'UNVERIFIED',
            'failure cleanup must preserve L1 Off and L2 UNVERIFIED')

    protected = {ledger, authorization, snapshot, live, owner, pointer_path,
                 receipt_path, *source_paths, *failure_paths}
    historical_run_ids = set(run_ids)
    historical_run_ids.update(_collision_ancestor_run_ids(predecessor, protected))
    return approval, historical_run_ids


def initialize(ledger, authorization, predecessors, policy_id=POLICY_ID, artifact_receipt=None):
    limits = limits_for(policy_id)
    if policy_id == HTTP_CLEANUP_ID:
        _validate_http_cleanup_sources(ledger, authorization, predecessors)
    elif policy_id == COLLISION_ID:
        _validate_collision_sources(ledger, authorization, predecessors)
    elif policy_id == CAUSAL_ID:
        _validate_causal_sources(ledger, authorization, predecessors)
    elif policy_id == REPAIR5_ID:
        if len(predecessors) != 2 or safe_path(predecessors[0]) == safe_path(predecessors[1]):
            raise ValueError('Fifth repair successor requires distinct terminal snapshot and live repair4 predecessor')
        if safe_path(authorization) in (safe_path(predecessors[0]), safe_path(predecessors[1]), safe_path(ledger)):
            raise ValueError('Fifth repair authorization must be a distinct source')
        if digest(predecessors[0]) != digest(predecessors[1]):
            raise ValueError('Fifth repair predecessor snapshot differs from live repair4 ledger')
        if digest(predecessors[0]) != REPAIR5_PREDECESSOR_SHA256:
            raise ValueError('Fifth repair predecessor differs from the exact owner-reviewed terminal repair4 bytes')
        parents = [load(p) for p in predecessors]
        if any(p['policyId'] != REPAIR4_ID or p['activeRunId'] is not None
               or len(p['attempts']) != 1
               or p['attempts'][0].get('state') != 'TERMINAL'
               or p['attempts'][0].get('operation') != 'standard-token'
               or p['attempts'][0].get('exitCode') != 0
               or p['attempts'][0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
               for p in parents):
            raise ValueError('Fifth repair successor requires terminal one-qualification repair4 predecessor')
        if parents[0]['authorization']['sha256'] == digest(authorization):
            raise ValueError('Fifth repair successor requires separate explicit authorization')
    elif policy_id == REPAIR4_ID:
        if len(predecessors) != 2 or safe_path(predecessors[0]) == safe_path(predecessors[1]):
            raise ValueError('Fourth repair successor requires distinct terminal snapshot and live repair3 predecessor')
        if safe_path(authorization) in (safe_path(predecessors[0]), safe_path(predecessors[1]), safe_path(ledger)):
            raise ValueError('Fourth repair authorization must be a distinct source')
        if digest(predecessors[0]) != digest(predecessors[1]):
            raise ValueError('Fourth repair predecessor snapshot differs from live repair3 ledger')
        parents = [load(p) for p in predecessors]
        if any(p['policyId'] != REPAIR3_ID or p['activeRunId'] is not None
               or len(p['attempts']) != len(REPAIR3_SEQUENCE)
               or p['attempts'][-1].get('state') != 'TERMINAL'
               or p['attempts'][-1].get('operation') != 'fullrelease'
               or p['attempts'][-1].get('exitCode') != 2
               or p['attempts'][-1].get('classification') != 'NATIVE_FULLRELEASE_BLOCKED'
               for p in parents):
            raise ValueError('Fourth repair successor requires terminal blocked repair3 FullRelease predecessor')
        if parents[0]['authorization']['sha256'] == digest(authorization):
            raise ValueError('Fourth repair successor requires separate explicit authorization')
    elif policy_id == REPAIR3_ID:
        if len(predecessors) != 2 or safe_path(predecessors[0]) == safe_path(predecessors[1]):
            raise ValueError('Third repair successor requires distinct terminal snapshot and live repair2 predecessor')
        if digest(predecessors[0]) != digest(predecessors[1]):
            raise ValueError('Third repair predecessor snapshot differs from live repair2 ledger')
        parents = [load(p) for p in predecessors]
        if any(p['policyId'] != REPAIR2_ID or p['activeRunId'] is not None
               or len(p['attempts']) != 1
               or p['attempts'][-1].get('state') != 'TERMINAL'
               or p['attempts'][-1].get('operation') != 'build-sign'
               or p['attempts'][-1].get('exitCode') != 2
               or p['attempts'][-1].get('classification') != 'BUILD_SIGN_BLOCKED'
               for p in parents):
            raise ValueError('Third repair successor requires terminal failed repair2 build-sign predecessor')
        if parents[0]['authorization']['sha256'] == digest(authorization):
            raise ValueError('Third repair successor requires separate explicit authorization')
        artifact_receipt = _load_repair3_receipt(artifact_receipt)
        receipt_data = strict_json(artifact_receipt)
        if digest(predecessors[0]) != receipt_data['failedAttemptLedgerSha256']:
            raise ValueError('Third repair predecessor does not match verified failed ledger')
    elif policy_id == REPAIR2_ID:
        if len(predecessors) != 2 or safe_path(predecessors[0]) == safe_path(predecessors[1]):
            raise ValueError('Second repair successor requires distinct terminal snapshot and live repair predecessor')
        if digest(predecessors[0]) != digest(predecessors[1]):
            raise ValueError('Second repair predecessor snapshot differs from live repair ledger')
        parents = [load(p) for p in predecessors]
        if any(p['policyId'] != REPAIR_ID or p['activeRunId'] is not None
               or len(p['attempts']) != len(REPAIR_SEQUENCE)
               or p['attempts'][-1].get('state') != 'TERMINAL'
               or p['attempts'][-1].get('operation') != 'fullrelease'
               or p['attempts'][-1].get('exitCode') != 2
               or p['attempts'][-1].get('classification') != 'NATIVE_FULLRELEASE_BLOCKED'
               for p in parents):
            raise ValueError('Second repair successor requires terminal failed FullRelease predecessor')
        if parents[0]['authorization']['sha256'] == digest(authorization):
            raise ValueError('Second repair successor requires separate explicit authorization')
    elif policy_id == REPAIR_ID:
        if len(predecessors) != 2 or safe_path(predecessors[0]) == safe_path(predecessors[1]):
            raise ValueError('Repair successor requires distinct terminal snapshot and live R2 predecessor')
        if digest(predecessors[0]) != digest(predecessors[1]):
            raise ValueError('Repair predecessor snapshot differs from live R2')
        parents = [load(p) for p in predecessors]
        if any(p['policyId'] != POLICY_ID + '-R2' or p['activeRunId'] is not None for p in parents):
            raise ValueError('Repair successor requires inactive R2 predecessor')
        if parents[0]['authorization']['sha256'] == digest(authorization):
            raise ValueError('Repair successor requires separate explicit authorization')
    elif policy_id == ONE_DIAGNOSTIC_ID:
        parents = [load(p) for p in predecessors]
        if len(parents) != 1 or parents[0]['policyId'] != POLICY_ID + '-R2' or parents[0]['activeRunId'] is not None:
            raise ValueError('One-diagnostic successor requires one terminal R2 predecessor')
        if status(predecessors[0])['remaining']['diagnostic'] != 0:
            raise ValueError('One-diagnostic successor requires exhausted R2 diagnostics')
        if parents[0]['authorization']['sha256'] == digest(authorization):
            raise ValueError('One-diagnostic successor requires separate explicit authorization')
    elif policy_id not in (POLICY_ID, HTTP_CLEANUP_ID):
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
        if policy_id == REPAIR3_ID:
            data['artifactReceipt'] = {'path': str(artifact_receipt),
                                       'sha256': digest(artifact_receipt)}
        atomic_write(ledger,data)
    return status(ledger)

def load(ledger):
    data = strict_json(ledger)
    if not isinstance(data,dict) or type(data.get('schemaVersion')) is not int or data['schemaVersion'] != 1 or data.get('policyId') not in (POLICY_ID, POLICY_ID+'-R2', ONE_DIAGNOSTIC_ID, REPAIR_ID, REPAIR2_ID, REPAIR3_ID, REPAIR4_ID, REPAIR5_ID, CAUSAL_ID, COLLISION_ID, HTTP_CLEANUP_ID):
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
    if data['policyId'] == CAUSAL_ID:
        predecessors = data.get('predecessors')
        if not isinstance(predecessors, list) or len(predecessors) != 4:
            raise ValueError('Causal predecessors are missing')
        if any(digest(safe_path(p['path'])) != p.get('sha256') for p in predecessors):
            raise ValueError('Causal predecessor changed')
        _validate_causal_sources(ledger, auth['path'], [p['path'] for p in predecessors])
    if data['policyId'] == COLLISION_ID:
        predecessors = data.get('predecessors')
        if (not isinstance(predecessors, list) or len(predecessors) != 1
                or not isinstance(predecessors[0], dict)
                or set(predecessors[0]) != {'path', 'sha256'}
                or predecessors[0]['sha256'] != COLLISION_PREDECESSOR_SHA256):
            raise ValueError('Post-collision predecessor ledger binding is missing')
        approval, historical_run_ids = _validate_collision_sources(
            ledger, auth['path'], [predecessors[0]['path']])
    elif data['policyId'] == HTTP_CLEANUP_ID:
        predecessors = data.get('predecessors')
        if (safe_path(ledger) != safe_path(HTTP_CLEANUP_LEDGER_PATH)
                or not isinstance(predecessors, list) or len(predecessors) != 2
                or any(not isinstance(row, dict) or set(row) != {'path', 'sha256'}
                       for row in predecessors)):
            raise ValueError('HTTP-CLEANUP-1 canonical ledger or predecessor references are malformed')
        paths = [_collision_path(row['path']) for row in predecessors]
        if any(digest(path) != row['sha256'] for path, row in zip(paths, predecessors)):
            raise ValueError('HTTP-CLEANUP-1 predecessor source hash changed')
        approval, historical_run_ids = _validate_http_cleanup_sources(
            ledger, auth['path'], [str(path) for path in paths])
        if digest(safe_path(auth['path'])) != auth['sha256']:
            raise ValueError('HTTP-CLEANUP-1 authorization source changed')
    if data['policyId'] == REPAIR3_ID:
        receipt = data.get('artifactReceipt')
        if not isinstance(receipt, dict) or set(receipt) != {'path', 'sha256'}:
            raise ValueError('Repair3 artifact receipt binding is missing')
        receipt_path = _load_repair3_receipt(receipt['path'])
        if digest(receipt_path) != receipt.get('sha256'):
            raise ValueError('Repair3 artifact receipt changed')
        if receipt_path == safe_path(ledger):
            raise ValueError('Repair3 artifact receipt cannot be the ledger')
    if data['policyId'] == REPAIR_ID:
        predecessors = data.get('predecessors')
        if not isinstance(predecessors, list) or len(predecessors) != 2:
            raise ValueError('Repair predecessors are missing')
        paths = [safe_path(p['path']) for p in predecessors]
        if paths[0] in (paths[1], safe_path(ledger)) or paths[1] == safe_path(ledger):
            raise ValueError('Repair predecessors are not distinct from successor')
        if any(digest(path) != row.get('sha256') for path, row in zip(paths, predecessors)):
            raise ValueError('Repair predecessor changed')
        if digest(paths[0]) != digest(paths[1]):
            raise ValueError('Repair snapshot and live R2 diverged')
        parents = [load(path) for path in paths]
        if any(parent['policyId'] != POLICY_ID + '-R2' or parent['activeRunId'] is not None
               for parent in parents):
            raise ValueError('Repair predecessor is not inactive R2')
        r2_predecessors = parents[0].get('predecessors')
        if not isinstance(r2_predecessors, list) or len(r2_predecessors) != 1:
            raise ValueError('R2 predecessor lineage is missing')
        base_path = safe_path(r2_predecessors[0]['path'])
        if base_path in (*paths, safe_path(ledger)) or digest(base_path) != r2_predecessors[0].get('sha256'):
            raise ValueError('R2 predecessor lineage changed')
        base = load(base_path)
        if base['policyId'] != POLICY_ID or base['activeRunId'] is not None:
            raise ValueError('R2 predecessor is not inactive base campaign')
        if parents[0]['authorization']['sha256'] == auth['sha256']:
            raise ValueError('Repair successor authorization repeats R2 source')
    if data['policyId'] == REPAIR2_ID:
        predecessors = data.get('predecessors')
        if not isinstance(predecessors, list) or len(predecessors) != 2:
            raise ValueError('Second repair predecessors are missing')
        paths = [safe_path(p['path']) for p in predecessors]
        if paths[0] in (paths[1], safe_path(ledger)) or paths[1] == safe_path(ledger):
            raise ValueError('Second repair predecessors are not distinct from successor')
        if any(digest(path) != row.get('sha256') for path, row in zip(paths, predecessors)):
            raise ValueError('Second repair predecessor changed')
        if digest(paths[0]) != digest(paths[1]):
            raise ValueError('Second repair snapshot and live predecessor diverged')
        parents = [load(path) for path in paths]
        if any(parent['policyId'] != REPAIR_ID or parent['activeRunId'] is not None
               or len(parent['attempts']) != len(REPAIR_SEQUENCE)
               or parent['attempts'][-1].get('state') != 'TERMINAL'
               or parent['attempts'][-1].get('operation') != 'fullrelease'
               or parent['attempts'][-1].get('exitCode') != 2
               or parent['attempts'][-1].get('classification') != 'NATIVE_FULLRELEASE_BLOCKED'
               for parent in parents):
            raise ValueError('Second repair predecessor is not the terminal blocked first repair')
        if parents[0]['authorization']['sha256'] == auth['sha256']:
            raise ValueError('Second repair authorization repeats first repair source')
    if data['policyId'] == REPAIR3_ID:
        predecessors = data.get('predecessors')
        if not isinstance(predecessors, list) or len(predecessors) != 2:
            raise ValueError('Third repair predecessors are missing')
        paths = [safe_path(p['path']) for p in predecessors]
        if paths[0] in (paths[1], safe_path(ledger)) or paths[1] == safe_path(ledger):
            raise ValueError('Third repair predecessors are not distinct from successor')
        if any(digest(path) != row.get('sha256') for path, row in zip(paths, predecessors)):
            raise ValueError('Third repair predecessor changed')
        if digest(paths[0]) != digest(paths[1]):
            raise ValueError('Third repair snapshot and live predecessor diverged')
        parents = [load(path) for path in paths]
        if any(parent['policyId'] != REPAIR2_ID or parent['activeRunId'] is not None
               or len(parent['attempts']) != 1
               or parent['attempts'][-1].get('state') != 'TERMINAL'
               or parent['attempts'][-1].get('operation') != 'build-sign'
               or parent['attempts'][-1].get('exitCode') != 2
               or parent['attempts'][-1].get('classification') != 'BUILD_SIGN_BLOCKED'
               for parent in parents):
            raise ValueError('Third repair predecessor is not the terminal blocked repair2 build-sign')
        receipt_data = strict_json(receipt['path'])
        if digest(paths[0]) != receipt_data['failedAttemptLedgerSha256']:
            raise ValueError('Third repair predecessor does not match verified failed ledger')
        if parents[0]['authorization']['sha256'] == auth['sha256']:
            raise ValueError('Third repair authorization repeats repair2 source')
    if data['policyId'] == REPAIR4_ID:
        predecessors = data.get('predecessors')
        if not isinstance(predecessors, list) or len(predecessors) != 2:
            raise ValueError('Fourth repair predecessors are missing')
        paths = [safe_path(p['path']) for p in predecessors]
        if paths[0] in (paths[1], safe_path(ledger)) or paths[1] == safe_path(ledger):
            raise ValueError('Fourth repair predecessors are not distinct from successor')
        if safe_path(auth['path']) in (*paths, safe_path(ledger)):
            raise ValueError('Fourth repair authorization is not a distinct source')
        if any(digest(path) != row.get('sha256') for path, row in zip(paths, predecessors)):
            raise ValueError('Fourth repair predecessor changed')
        if digest(paths[0]) != digest(paths[1]):
            raise ValueError('Fourth repair snapshot and live predecessor diverged')
        parents = [load(path) for path in paths]
        if any(parent['policyId'] != REPAIR3_ID or parent['activeRunId'] is not None
               or len(parent['attempts']) != len(REPAIR3_SEQUENCE)
               or parent['attempts'][-1].get('state') != 'TERMINAL'
               or parent['attempts'][-1].get('operation') != 'fullrelease'
               or parent['attempts'][-1].get('exitCode') != 2
               or parent['attempts'][-1].get('classification') != 'NATIVE_FULLRELEASE_BLOCKED'
               for parent in parents):
            raise ValueError('Fourth repair predecessor is not the terminal blocked repair3 FullRelease')
        if parents[0]['authorization']['sha256'] == auth['sha256']:
            raise ValueError('Fourth repair authorization repeats repair3 source')
    if data['policyId'] == REPAIR5_ID:
        predecessors = data.get('predecessors')
        if not isinstance(predecessors, list) or len(predecessors) != 2:
            raise ValueError('Fifth repair predecessors are missing')
        paths = [safe_path(p['path']) for p in predecessors]
        if paths[0] in (paths[1], safe_path(ledger)) or paths[1] == safe_path(ledger):
            raise ValueError('Fifth repair predecessors are not distinct from successor')
        if safe_path(auth['path']) in (*paths, safe_path(ledger)):
            raise ValueError('Fifth repair authorization is not a distinct source')
        if any(digest(path) != row.get('sha256') for path, row in zip(paths, predecessors)):
            raise ValueError('Fifth repair predecessor changed')
        if digest(paths[0]) != digest(paths[1]):
            raise ValueError('Fifth repair snapshot and live predecessor diverged')
        if digest(paths[0]) != REPAIR5_PREDECESSOR_SHA256:
            raise ValueError('Fifth repair predecessor differs from exact terminal repair4 bytes')
        parents = [load(path) for path in paths]
        if any(parent['policyId'] != REPAIR4_ID or parent['activeRunId'] is not None
               or len(parent['attempts']) != 1
               or parent['attempts'][0].get('state') != 'TERMINAL'
               or parent['attempts'][0].get('operation') != 'standard-token'
               or parent['attempts'][0].get('exitCode') != 0
               or parent['attempts'][0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
               for parent in parents):
            raise ValueError('Fifth repair predecessor is not terminal one-qualification repair4')
        if parents[0]['authorization']['sha256'] == auth['sha256']:
            raise ValueError('Fifth repair authorization repeats repair4 source')
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
    if data['policyId'] in (COLLISION_ID, HTTP_CLEANUP_ID):
        if any(a['runId'] in historical_run_ids or a.get('tuple') != approval['candidate']
               for a in attempts):
            raise ValueError('Successor RunId replay or candidate tuple drift')
    if data['policyId'] in (REPAIR_ID, REPAIR2_ID, REPAIR3_ID, REPAIR4_ID,
                            REPAIR5_ID, CAUSAL_ID, COLLISION_ID, HTTP_CLEANUP_ID):
        sequence = sequence_for(data['policyId'])
        if len(attempts) > len(sequence):
            raise ValueError('Repair successor has too many phases')
        for index, attempt in enumerate(attempts):
            if attempt['operation'] != sequence[index][0]:
                raise ValueError('Repair successor phase order changed')
            if index < len(attempts) - 1 and (attempt.get('state') != 'TERMINAL'
                    or attempt.get('exitCode') != 0
                    or attempt.get('classification') != sequence[index][1]):
                raise ValueError('Repair successor advanced past an unpassed prerequisite')
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
    if data['policyId'] == COLLISION_ID:
        approval_path = data['authorization']['path']
        declared_ledger = strict_json(approval_path)['successorLedgerPath']
        approval, historical_run_ids = _validate_collision_sources(
            declared_ledger, approval_path,
            [row['path'] for row in data['predecessors']])
        if request['runId'] in historical_run_ids:
            raise ValueError('Historical CAUSAL-1 RunId cannot be replayed')
        if _collision_tuple(request['tuple']) != approval['candidate']:
            raise ValueError('Post-collision reservation tuple differs from owner authorization')
    if data['policyId'] == HTTP_CLEANUP_ID:
        auth_path = data['authorization']['path']
        predecessor_paths = [row['path'] for row in data['predecessors']]
        approval, historical_run_ids = _validate_http_cleanup_sources(
            HTTP_CLEANUP_LEDGER_PATH, auth_path, predecessor_paths)
        if request['runId'] in historical_run_ids:
            raise ValueError('HTTP-CLEANUP-1 historical RunId cannot be replayed')
        if _collision_tuple(request['tuple']) != approval['candidate']:
            raise ValueError('HTTP-CLEANUP-1 reservation tuple differs from owner authorization')
    if not isinstance(request['entrypoint'],str) or not request['entrypoint'].strip() or not re.fullmatch('[a-f0-9]{64}',str(request['entrypointSha256'])): raise ValueError('Reviewed entrypoint identity required')
    if not isinstance(request['arguments'],list) or any(not isinstance(s,str) for s in request['arguments']): raise ValueError('Arguments must be a string array')
    if not isinstance(request['changedCondition'],str) or not request['changedCondition'].strip(): raise ValueError('Actual changed condition must be recorded')
    deadline=datetime.fromisoformat(request['deadlineUtc'].replace('Z','+00:00'))
    if deadline.tzinfo is None or deadline<=datetime.now(timezone.utc): raise ValueError('Reservation deadline expired or lacks timezone')
    if data['activeRunId'] is not None: raise ValueError('Active attempt must be reconciled; crash is not a free replay')
    if any(a['runId']==request['runId'] for a in data['attempts']): raise ValueError('RunId has already been charged')
    if sum(a['operation']==request['operation'] for a in data['attempts'])>=limits[request['operation']]: raise ValueError('Operation allowance exhausted')
    if data['policyId'] in (REPAIR_ID, REPAIR2_ID, REPAIR3_ID, REPAIR4_ID,
                            REPAIR5_ID, CAUSAL_ID, COLLISION_ID, HTTP_CLEANUP_ID):
        sequence = sequence_for(data['policyId'])
        prior = data['attempts']
        if (len(prior) >= len(sequence)
                or request['operation'] != sequence[len(prior)][0]
                or any(a['operation'] != expected_operation
                       or a.get('state') != 'TERMINAL'
                       or a.get('exitCode') != 0
                       or a.get('classification') != expected_result
                       for a, (expected_operation, expected_result) in zip(prior, sequence))):
            raise ValueError('Repair successor phase order or prerequisite result is invalid')
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
    parser.add_argument('--policy-id',choices=[POLICY_ID,POLICY_ID+'-R2',ONE_DIAGNOSTIC_ID,REPAIR_ID,REPAIR2_ID,REPAIR3_ID,REPAIR4_ID,REPAIR5_ID,CAUSAL_ID,COLLISION_ID,HTTP_CLEANUP_ID],default=POLICY_ID)
    parser.add_argument('--artifact-receipt')
    parser.add_argument('--request'); parser.add_argument('--dry-run',action='store_true')
    args=parser.parse_args()
    if args.command=='initialize': result=initialize(args.ledger,args.authorization,args.predecessor,args.policy_id,args.artifact_receipt)
    elif args.command=='status': result=status(args.ledger)
    elif args.command=='reserve': result=reserve(args.ledger,strict_json(args.request),args.dry_run)
    else:
        q=strict_json(args.request); result=finish(args.ledger,q['runId'],q['owner'],q['exitCode'],q['classification'],q['evidence'])
    print(json.dumps(result,indent=2,allow_nan=False))

if __name__=='__main__':
    try: main()
    except (ValueError,KeyError,TypeError,OSError) as error:
        raise SystemExit('ATTEMPT_JOURNAL_BLOCKED: '+str(error))
