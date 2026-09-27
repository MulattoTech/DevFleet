"""Exact-L1 baseline adoption contract and atomic, non-promoting receipt.

The operator must provide independently collected native Hyper-V and admitted
authenticated-guest evidence plus a separate explicit account-owner approval.
This module cannot create a checkpoint, change a credential, or award proof.
"""
from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid


VM_NAME = 'DevFleet-E2E-Win11-01'
VM_ID = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
OLD_NAME = 'DevFleet-E2E-CLEAN'
OLD_ID = '19865b76-4c3a-44f7-ba39-841e9d3c40c9'
NEW_NAME = 'DevFleet-E2E-CLEAN-R2'
L2_NAME = 'DevFleet-E2E-Linux-01'
TUPLE_KEYS = ('repositoryHead', 'candidateBuildCommit', 'shippingInputIdentity',
              'releaseFingerprintId', 'toolingFingerprintId', 'candidateSha256')
HEX64 = re.compile(r'[0-9a-f]{64}\Z')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4_000_000,
            'Baseline input is absent, linked, or oversized')
    def pairs(items):
        data = {}
        for key, value in items:
            require(key not in data, 'Duplicate JSON key')
            data[key] = value
        return data
    def invalid(_):
        raise ValueError('Nonfinite JSON number')
    value = json.loads(path.read_text(encoding='utf-8-sig'),
                       object_pairs_hook=pairs, parse_constant=invalid)
    require(isinstance(value, dict), 'Baseline input is not a JSON object')
    return value


def instant(value):
    require(isinstance(value, str) and value, 'Missing UTC instant')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None and parsed.utcoffset().total_seconds() == 0,
            'Baseline evidence instant is not UTC')
    return parsed.astimezone(timezone.utc)


def exact_tuple(value):
    require(isinstance(value, dict) and set(value) == set(TUPLE_KEYS),
            'Candidate tuple is missing or contains unexpected fields')
    for key in TUPLE_KEYS:
        size = 40 if key in ('repositoryHead', 'candidateBuildCommit') else 64
        require(isinstance(value[key], str) and re.fullmatch(f'[0-9a-f]{{{size}}}', value[key]),
                'Candidate tuple field is malformed: ' + key)
    return {key: value[key] for key in TUPLE_KEYS}


@contextmanager
def lock(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'a+b') as stream:
        stream.seek(0); stream.write(b'0'); stream.flush(); stream.seek(0)
        if os.name == 'nt':
            import msvcrt
            try: msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError as exc: raise ValueError('Baseline adoption already has an owner') from exc
        else:
            import fcntl
            try: fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as exc: raise ValueError('Baseline adoption already has an owner') from exc
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == 'nt': msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else: fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def _json_bytes(value):
    return (json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n').encode('utf-8')


def _write_exclusive(path, payload):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(payload)
        stream.flush(); os.fsync(stream.fileno())


def _atomic_replace(path, payload):
    fd, tmp = tempfile.mkstemp(prefix=path.name + '.', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(payload); stream.flush(); os.fsync(stream.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)


def _state(root):
    root = Path(root).resolve(strict=True)
    return root / 'evidence' / 'baselines'


def accepted_baseline(root, current_tuple=None):
    """Resolve only the original CLEAN or a hash-bound adopted receipt."""
    state = _state(root)
    pointer_path = state / 'CURRENT.json'
    if not pointer_path.exists():
        return {'name': OLD_NAME, 'id': OLD_ID, 'vmName': VM_NAME, 'vmId': VM_ID,
                'predecessorId': None, 'receiptSha256': None, 'legacyOriginal': True}
    pointer = read_json(pointer_path)
    if pointer.get('generation') == 2:
        return _accepted_rebound_baseline(root, pointer, current_tuple)
    return _accepted_v1_baseline(root, pointer, current_tuple)


def _accepted_v1_baseline(root, pointer, current_tuple=None):
    state = _state(root)
    require(pointer.get('schemaVersion') == 1 and pointer.get('contract') == 'devfleet-accepted-baseline-v1'
            and pointer.get('generation') == 1 and pointer.get('status') == 'ACCEPTED',
            'Accepted baseline pointer is malformed')
    filename = pointer.get('receiptFile')
    require(isinstance(filename, str) and re.fullmatch(r'[0-9a-f]{32}\.json', filename),
            'Accepted baseline receipt path is invalid')
    receipt_path = state / 'receipts' / filename
    receipt = read_json(receipt_path)
    require(pointer.get('receiptSha256') == digest(receipt_path),
            'Accepted baseline receipt hash differs')
    require(receipt.get('contract') == 'devfleet-baseline-adoption-receipt-v1'
            and receipt.get('status') == 'ADOPTED' and receipt.get('certificationCredit') is False
            and receipt.get('secretValuesRecorded') is False
            and receipt.get('receiptId') + '.json' == filename,
            'Accepted baseline receipt is malformed')
    old, new = receipt.get('predecessor') or {}, receipt.get('replacement') or {}
    require(old == {'name': OLD_NAME, 'id': OLD_ID}
            and new.get('name') == NEW_NAME and new.get('vmId') == VM_ID
            and new.get('parentSnapshotId') == OLD_ID and new.get('id') != OLD_ID,
            'Accepted baseline lineage differs')
    require(pointer.get('checkpoint') == new, 'Pointer and immutable receipt disagree')
    try: new_id = str(uuid.UUID(new.get('id', '')))
    except (ValueError, TypeError, AttributeError) as exc: raise ValueError('Accepted replacement GUID is invalid') from exc
    require(new_id == new['id'], 'Accepted replacement GUID is not canonical')
    authority = receipt.get('adoptionAuthority') or {}
    guest = receipt.get('authenticatedGuest') or {}
    nested = receipt.get('nestedL2') or {}
    sources = receipt.get('sources') or {}
    require(authority.get('decision') == 'APPROVE' and authority.get('approvedBy') == 'ACCOUNT_OWNER'
            and guest.get('computerName') == 'DEVFLEET-E2E-01'
            and guest.get('principal') == 'DEVFLEET-E2E-01\\E2EAdmin'
            and guest.get('accountEnabled') is True
            and nested.get('status') == 'ABSENT' and nested.get('present') is False
            and nested.get('expectedName') == L2_NAME
            and nested.get('exactMatchCount') == 0
            and receipt.get('finalL1') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'},
            'Accepted baseline approval, authenticated identity, or terminal lab state differs')
    inventories = nested.get('backendInventories')
    require(isinstance(inventories, list) and len(inventories) == 2
            and {row.get('provider') for row in inventories if isinstance(row, dict)} == {'Hyper-V', 'VirtualBox'}
            and all(row.get('status') == 'PASS' and isinstance(row.get('names'), list)
                    and L2_NAME not in row['names'] for row in inventories),
            'Accepted baseline nested backend inventories are incomplete')
    for source_key in ('proposalSha256', 'predecessorEvidenceSha256', 'approvalSha256',
                       'authenticatedGuestSha256', 'nativeInventorySha256',
                       'currentTupleSha256', 'r2LedgerSha256'):
        require(isinstance(sources.get(source_key), str)
                and HEX64.fullmatch(sources[source_key]),
                'Accepted baseline source hash is missing: ' + source_key)
    require(authority.get('sourceSha256') == sources['approvalSha256'],
            'Accepted baseline approval source hash differs')
    require(instant(receipt.get('passwordLastSetUtc')) <=
            instant(receipt.get('protectedStoreUpdatedUtc')) <=
            instant(guest.get('sourceObservedUtc')) <
            instant(receipt.get('passwordExpiresUtc')),
            'Accepted baseline credential freshness metadata differs')
    if current_tuple is not None:
        require(receipt.get('candidate') == exact_tuple(current_tuple),
                'Accepted baseline is bound to another candidate/material tuple')
    require(instant(receipt.get('passwordExpiresUtc')) > datetime.now(timezone.utc),
            'Accepted baseline credential expiry is no longer current')
    return {'name': new['name'], 'id': new['id'], 'vmName': VM_NAME, 'vmId': VM_ID,
            'predecessorId': OLD_ID, 'receiptSha256': pointer['receiptSha256'],
            'receiptFile': filename, 'legacyOriginal': False}


def _accepted_rebound_baseline(root, pointer, current_tuple=None):
    state = _state(root)
    require(pointer.get('schemaVersion') == 2
            and pointer.get('contract') == 'devfleet-accepted-baseline-v2'
            and pointer.get('status') == 'ACCEPTED',
            'Rebound baseline pointer contract is invalid')
    filename = pointer.get('receiptFile')
    old_hash = pointer.get('previousPointerSha256')
    require(isinstance(filename, str) and re.fullmatch(r'[0-9a-f]{32}\.json', filename)
            and isinstance(old_hash, str) and HEX64.fullmatch(old_hash),
            'Rebound baseline chain filename or hash is invalid')
    history_path = state / 'history' / (old_hash + '.json')
    require(digest(history_path) == old_hash, 'Previous baseline pointer hash differs')
    previous = read_json(history_path)
    receipt_path = state / 'receipts' / filename
    require(digest(receipt_path) == pointer.get('receiptSha256'),
            'Rebound baseline receipt hash differs')
    receipt = read_json(receipt_path)
    require(receipt.get('schemaVersion') == 2
            and receipt.get('contract') == 'devfleet-baseline-rebind-receipt-v2'
            and receipt.get('status') == 'REBOUND'
            and receipt.get('certificationCredit') is False
            and receipt.get('secretValuesRecorded') is False
            and isinstance(receipt.get('receiptId'), str)
            and receipt['receiptId'] + '.json' == filename
            and receipt.get('previousPointerSha256') == old_hash
            and receipt.get('previousReceiptSha256') == previous.get('receiptSha256')
            and receipt.get('replacement') == pointer.get('checkpoint')
            and receipt.get('replacement') == previous.get('checkpoint'),
            'Rebound baseline lineage differs')
    old_tuple = exact_tuple(receipt.get('previousCandidate'))
    new_tuple = exact_tuple(receipt.get('candidate'))
    old = _accepted_v1_baseline(root, previous, old_tuple)
    require(old['receiptSha256'] == receipt['previousReceiptSha256'],
            'Rebound predecessor receipt differs')
    for key in ('candidateBuildCommit', 'shippingInputIdentity',
                'releaseFingerprintId', 'candidateSha256'):
        require(old_tuple[key] == new_tuple[key],
                'Rebound baseline changed signed shipping identity: ' + key)
    require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
            and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
            'Rebound baseline lacks exact HEAD/tooling transition')
    approval = receipt.get('approval') or {}
    require(approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('candidate') == new_tuple
            and approval.get('replacement') == pointer['checkpoint']
            and approval.get('previousReceiptSha256') == old['receiptSha256']
            and approval.get('sourceSha256') == receipt.get('approvalSha256')
            and isinstance(approval.get('sourceSha256'), str)
            and HEX64.fullmatch(approval['sourceSha256']),
            'Rebound baseline owner approval differs')
    require(receipt.get('finalL1') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
            and receipt.get('successorPolicyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-D1'
            and isinstance(receipt.get('successorLedgerSha256'), str)
            and HEX64.fullmatch(receipt['successorLedgerSha256']),
            'Rebound baseline lab or successor lineage differs')
    if current_tuple is not None:
        require(new_tuple == exact_tuple(current_tuple),
                'Rebound baseline is bound to another candidate/material tuple')
    return {**old, 'receiptSha256': pointer['receiptSha256'],
            'receiptFile': filename, 'previousReceiptSha256': old['receiptSha256'],
            'generation': 2}


def rebind(root, tuple_path, approval_path, ledger_path, live_path):
    """Append one exact-tuple binding for an already owner-approved checkpoint."""
    state = _state(root)
    with lock(state / '.adoption.lock'):
        pointer_path = state / 'CURRENT.json'
        pointer = read_json(pointer_path)
        require(pointer.get('generation') == 1, 'Rebind requires one accepted generation-1 baseline')
        old_receipt = read_json(state / 'receipts' / pointer['receiptFile'])
        old_tuple = exact_tuple(old_receipt.get('candidate'))
        old = _accepted_v1_baseline(root, pointer, old_tuple)
        new_tuple = exact_tuple(read_json(tuple_path))
        for key in ('candidateBuildCommit', 'shippingInputIdentity',
                    'releaseFingerprintId', 'candidateSha256'):
            require(old_tuple[key] == new_tuple[key],
                    'Rebind changed signed shipping identity: ' + key)
        require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
                and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
                'Rebind requires a changed HEAD and tooling identity')
        approval = read_json(approval_path)
        require(approval.get('schemaVersion') == 1
                and approval.get('contract') == 'devfleet-baseline-rebind-approval-v1'
                and approval.get('decision') == 'APPROVE'
                and approval.get('approvedBy') == 'ACCOUNT_OWNER'
                and approval.get('candidate') == new_tuple
                and approval.get('replacement') == pointer['checkpoint']
                and approval.get('previousReceiptSha256') == old['receiptSha256'],
                'Exact account-owner rebind approval is absent')
        ledger = read_json(ledger_path)
        journal = Path(root).resolve(strict=True) / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Native one-diagnostic journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0, 'Native one-diagnostic journal rejected successor')
        journal_status = json.loads(checked.stdout)
        require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-D1'
                and journal_status.get('policyId') == ledger['policyId']
                and ledger.get('activeRunId') is None
                and journal_status.get('active') is None
                and journal_status.get('attemptCount') == 0
                and journal_status.get('remaining', {}).get('diagnostic') == 1
                and all(value == 0 for key, value in journal_status['remaining'].items()
                        if key != 'diagnostic'),
                'Native one-diagnostic successor is not unused and exact')
        live = read_json(live_path)
        named = [x for x in live.get('snapshots', [])
                 if isinstance(x, dict) and x.get('name') == NEW_NAME]
        require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
                and timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc')) <= timedelta(minutes=2)
                and len(named) == 1 and named[0].get('id') == old['id']
                and named[0].get('vmId') == VM_ID
                and named[0].get('parentSnapshotId') == OLD_ID,
                'Exact accepted checkpoint is not present with L1 Off')
        previous_hash = digest(pointer_path)
        history_dir = state / 'history'
        history_dir.mkdir(parents=True, exist_ok=True)
        history_path = history_dir / (previous_hash + '.json')
        _write_exclusive(history_path, pointer_path.read_bytes())
        receipt_id = uuid.uuid4().hex
        receipt = {'schemaVersion': 2, 'contract': 'devfleet-baseline-rebind-receipt-v2',
                   'receiptId': receipt_id, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': previous_hash,
                   'previousReceiptSha256': old['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': pointer['checkpoint'],
                   'approval': {**approval, 'sourceSha256': digest(approval_path)},
                   'approvalSha256': digest(approval_path),
                   'successorPolicyId': ledger['policyId'],
                   'successorLedgerSha256': digest(ledger_path),
                   'finalL1': live['vm'], 'nativeInventorySha256': digest(live_path)}
        receipt_file = receipt_id + '.json'
        receipt_path = state / 'receipts' / receipt_file
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 2, 'contract': 'devfleet-accepted-baseline-v2',
                   'generation': 2, 'status': 'ACCEPTED',
                   'receiptFile': receipt_file, 'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': pointer['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


def _validate(proposal, approval, auth, live, current_tuple, ledger, auth_path):
    current_tuple = exact_tuple(current_tuple)
    require(proposal.get('schemaVersion') == 1
            and proposal.get('contract') == 'devfleet-baseline-adoption-proposal-v1',
            'Unsupported baseline proposal')
    run_id = proposal.get('runId')
    require(isinstance(run_id, str) and run_id.startswith('r2-') and len(run_id) <= 120,
            'Baseline proposal lacks an R2 run identity')
    require(proposal.get('vm') == {'name': VM_NAME, 'id': VM_ID}
            and proposal.get('predecessor') == {'name': OLD_NAME, 'id': OLD_ID},
            'Baseline proposal widens VM or predecessor scope')
    replacement = proposal.get('replacement') or {}
    try: new_id = str(uuid.UUID(replacement.get('id', '')))
    except (ValueError, TypeError, AttributeError) as exc: raise ValueError('Replacement GUID is invalid') from exc
    require(replacement == {'name': NEW_NAME, 'id': new_id, 'vmId': VM_ID,
                            'parentSnapshotId': OLD_ID} and new_id != OLD_ID,
            'Replacement must have a new exact GUID, name, VM and parent')
    require(proposal.get('candidate') == current_tuple,
            'Proposal candidate/material tuple is stale')
    require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2'
            and ledger.get('activeRunId') is None,
            'The authenticated guest source is not from a terminal R2 campaign')
    attempts = [a for a in ledger.get('attempts', []) if isinstance(a, dict)
                and a.get('runId') == run_id]
    require(len(attempts) == 1 and attempts[0].get('operation') == 'diagnostic'
            and attempts[0].get('state') == 'TERMINAL'
            and attempts[0].get('certificationCredit') is False,
            'Authenticated guest source lacks one charged terminal R2 diagnostic')
    attempt = attempts[0]
    require(type(attempt.get('exitCode')) is int and attempt['exitCode'] == 0,
            'Authenticated guest source diagnostic did not exit successfully')
    attempted_tuple = attempt.get('tuple')
    require(isinstance(attempted_tuple, dict)
            and {key: attempted_tuple.get(key) for key in TUPLE_KEYS} == current_tuple,
            'Authenticated diagnostic reservation has a different candidate/material tuple')
    require(auth.get('vm') == {'name': VM_NAME, 'id': VM_ID}
            and auth.get('candidate') == current_tuple,
            'Authenticated collector VM or candidate/material tuple differs')
    evidence_paths = attempts[0].get('evidence')
    require(isinstance(evidence_paths, list)
            and str(Path(auth_path).resolve(strict=True)) in evidence_paths,
            'Authenticated guest evidence is not retained by its terminal R2 attempt')

    require(approval.get('schemaVersion') == 1
            and approval.get('contract') == 'devfleet-baseline-adoption-approval-v1'
            and approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('vmId') == VM_ID
            and approval.get('predecessorId') == OLD_ID
            and approval.get('replacementId') == new_id
            and approval.get('runId') == run_id
            and approval.get('candidate') == current_tuple,
            'Explicit account-owner adoption approval is absent or mismatched')

    require(auth.get('scope') == 'CURRENT_RUNNING_GUEST_READ_ONLY'
            and auth.get('runId') == run_id and auth.get('connected') is True
            and auth.get('status') == 'AUTHENTICATED_CURRENT_GUEST_NOT_CLEAN_PROOF'
            and auth.get('certificationCredit') is False,
            'Authenticated current-guest evidence is absent or wrong-run')
    guest, credential, nested = (auth.get('guest') or {}, auth.get('credential') or {},
                                  auth.get('nestedL2') or {})
    require(guest.get('computerName') == 'DEVFLEET-E2E-01'
            and guest.get('principal') == 'DEVFLEET-E2E-01\\E2EAdmin'
            and guest.get('accountEnabled') is True,
            'Authenticated guest/account identity is not exact')
    auth_time = instant(auth.get('observedUtc'))
    started = instant(auth.get('startedUtc'))
    reserved = instant(attempt.get('reservedUtc'))
    terminal = instant(attempt.get('terminalUtc'))
    deadline = instant(attempt.get('deadlineUtc'))
    require(reserved <= started <= auth_time <= terminal <= deadline,
            'Authenticated collection is outside its charged diagnostic time window')
    last_set = instant(guest.get('passwordLastSetUtc'))
    expires = instant(guest.get('passwordExpiresUtc'))
    store_time = instant(credential.get('protectedStoreUpdatedUtc'))
    require(last_set <= store_time <= auth_time < expires
            and credential.get('storeUser') == 'E2EAdmin'
            and credential.get('secretValuesRecorded') is False,
            'Credential freshness or expiry metadata is incomplete/stale')
    require(nested.get('status') == 'ABSENT' and nested.get('present') is False
            and nested.get('expectedName') == L2_NAME
            and type(nested.get('exactMatchCount')) is int and nested['exactMatchCount'] == 0
            and started <= instant(nested.get('observedUtc')) <= auth_time,
            'Nested L2 absence is not positively proven')
    inventories = nested.get('backendInventories')
    require(isinstance(inventories, list) and len(inventories) == 2
            and {x.get('provider') for x in inventories if isinstance(x, dict)} == {'Hyper-V', 'VirtualBox'},
            'Complete supported in-L1 backend inventories are missing')
    for inventory in inventories:
        require(inventory.get('status') == 'PASS'
                and isinstance(inventory.get('names'), list)
                and all(isinstance(n, str) and n.strip() and n != L2_NAME
                        for n in inventory['names'])
                and isinstance(inventory.get('verification'), str)
                and inventory['verification'].strip(),
                'Nested L2 backend inventory is incomplete or present')

    require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
            and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'},
            'Final native exact L1 Off identity is absent')
    live_time = instant(live.get('observedUtc'))
    require(auth_time <= instant(attempts[0].get('terminalUtc')) <= live_time,
            'Authenticated observation is outside its terminal diagnostic lineage')
    require(auth_time <= live_time <= datetime.now(timezone.utc)
            and (live_time - auth_time).total_seconds() <= 3600
            and live_time < expires and datetime.now(timezone.utc) < expires
            and (datetime.now(timezone.utc) - live_time).total_seconds() <= 3600,
            'Native checkpoint inventory is not fresh after authenticated guest evidence')
    snapshots = live.get('snapshots')
    require(isinstance(snapshots, list) and len(snapshots) >= 2
            and all(isinstance(s, dict) for s in snapshots),
            'Native snapshot inventory is incomplete')
    old_rows = [s for s in snapshots if s.get('id') == OLD_ID or s.get('name') == OLD_NAME]
    new_rows = [s for s in snapshots if s.get('id') == new_id or s.get('name') == NEW_NAME]
    require(len(old_rows) == 1 and old_rows[0].get('name') == OLD_NAME
            and old_rows[0].get('id') == OLD_ID and old_rows[0].get('vmId') == VM_ID,
            'Predecessor checkpoint is missing or ambiguous')
    require(len(new_rows) == 1 and new_rows[0].get('name') == NEW_NAME
            and new_rows[0].get('id') == new_id and new_rows[0].get('vmId') == VM_ID
            and new_rows[0].get('parentSnapshotId') == OLD_ID,
            'Replacement checkpoint is missing, ambiguous or name-only')
    return current_tuple, expires


def adopt(root, proposal_path, approval_path, auth_path, live_path, tuple_path, ledger_path,
          *, fault=None):
    """Atomically adopt one validated replacement; never touch checkpoints or old history."""
    state = _state(root)
    with lock(state / '.adoption.lock'):
        pointer = state / 'CURRENT.json'
        receipts = state / 'receipts'
        require(not pointer.exists(), 'An accepted replacement already exists; replay rejected')
        require(not receipts.exists() or not list(receipts.iterdir()),
                'Interrupted/orphan receipt exists; old baseline remains selected')
        proposal, approval = read_json(proposal_path), read_json(approval_path)
        auth, live, current_tuple = read_json(auth_path), read_json(live_path), read_json(tuple_path)
        ledger = read_json(ledger_path)
        predecessor_evidence = proposal.get('predecessorEvidence') or {}
        predecessor_path = Path(predecessor_evidence.get('path', ''))
        expected_source_root = Path(root).resolve(strict=True) / 'audit/agent-memory/attempts/DF-FRESH-CERTIFICATION-20260926-R2'
        require(predecessor_path.is_absolute() and predecessor_path.suffix.lower() == '.json'
                and predecessor_path.resolve(strict=True).is_relative_to(expected_source_root)
                and predecessor_evidence.get('sha256') == digest(predecessor_path),
                'Preserved predecessor evidence is absent, outside R2, or hash mismatched')
        predecessor_record = read_json(predecessor_path)
        require((predecessor_record.get('lab') or {}).get('l1Id') == VM_ID
                and (predecessor_record.get('lab') or {}).get('cleanId') == OLD_ID
                and (predecessor_record.get('liveGuestAuth') or {}).get('cleanRestored') is True
                and (predecessor_record.get('liveGuestAuth') or {}).get('finalL1State') == 'Off',
                'Predecessor source does not preserve the exact restored CLEAN identity')
        candidate, expires = _validate(proposal, approval, auth, live, current_tuple,
                                       ledger, auth_path)
        receipts.mkdir(parents=True, exist_ok=True)
        receipt_id = uuid.uuid4().hex
        receipt_file = receipt_id + '.json'
        receipt = {
            'schemaVersion': 1, 'contract': 'devfleet-baseline-adoption-receipt-v1',
            'receiptId': receipt_id, 'status': 'ADOPTED',
            'adoptedUtc': datetime.now(timezone.utc).isoformat(),
            'certificationCredit': False, 'secretValuesRecorded': False,
            'predecessor': proposal['predecessor'], 'replacement': proposal['replacement'],
            'candidate': candidate, 'runId': proposal['runId'],
            'passwordLastSetUtc': auth['guest']['passwordLastSetUtc'],
            'passwordExpiresUtc': auth['guest']['passwordExpiresUtc'],
            'protectedStoreUpdatedUtc': auth['credential']['protectedStoreUpdatedUtc'],
            'authenticatedGuest': {'computerName': auth['guest']['computerName'],
                                   'principal': auth['guest']['principal'],
                                   'accountEnabled': True,
                                   'sourceObservedUtc': auth['observedUtc']},
            'nestedL2': auth['nestedL2'],
            'finalL1': live['vm'],
            'liveCheckpointInventory': live['snapshots'],
            'adoptionAuthority': {'decision': approval['decision'],
                                  'approvedBy': approval['approvedBy'],
                                  'sourceSha256': digest(approval_path)},
            'sources': {'proposalSha256': digest(proposal_path),
                        'predecessorEvidenceSha256': digest(predecessor_path),
                        'approvalSha256': digest(approval_path),
                        'authenticatedGuestSha256': digest(auth_path),
                        'nativeInventorySha256': digest(live_path),
                        'currentTupleSha256': digest(tuple_path),
                        'r2LedgerSha256': digest(ledger_path)},
        }
        receipt_path = receipts / receipt_file
        _write_exclusive(receipt_path, _json_bytes(receipt))
        receipt_hash = digest(receipt_path)
        if fault == 'after_receipt':
            raise RuntimeError('Injected interruption after immutable receipt')
        pointer_value = {'schemaVersion': 1, 'contract': 'devfleet-accepted-baseline-v1',
                         'generation': 1, 'status': 'ACCEPTED',
                         'receiptFile': receipt_file, 'receiptSha256': receipt_hash,
                         'checkpoint': proposal['replacement']}
        _atomic_replace(pointer, _json_bytes(pointer_value))
        return {'receiptFile': receipt_file, 'receiptSha256': receipt_hash,
                'certificationCredit': False, 'passwordExpiresUtc': expires.isoformat()}


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    inspect = sub.add_parser('inspect')
    inspect.add_argument('--root', required=True)
    inspect.add_argument('--tuple')
    adoption = sub.add_parser('adopt')
    for flag in ('root', 'proposal', 'approval', 'auth', 'live', 'tuple', 'ledger'):
        adoption.add_argument('--' + flag, required=True)
    binding = sub.add_parser('rebind')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding.add_argument('--' + flag, required=True)
    args = parser.parse_args()
    if args.command == 'inspect':
        value = accepted_baseline(args.root, read_json(args.tuple) if args.tuple else None)
    elif args.command == 'adopt':
        value = adopt(args.root, args.proposal, args.approval, args.auth, args.live, args.tuple,
                      args.ledger)
    else:
        value = rebind(args.root, args.tuple, args.approval, args.ledger, args.live)
    print(json.dumps(value, indent=2))


if __name__ == '__main__': main()
