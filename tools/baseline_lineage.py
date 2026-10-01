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
    if pointer.get('generation') == 8:
        return _accepted_rebound_v8(root, pointer, current_tuple)
    if pointer.get('generation') == 7:
        return _accepted_rebound_v7(root, pointer, current_tuple)
    if pointer.get('generation') == 6:
        return _accepted_rebound_v6(root, pointer, current_tuple)
    if pointer.get('generation') == 5:
        return _accepted_rebound_v5(root, pointer, current_tuple)
    if pointer.get('generation') == 4:
        return _accepted_rebound_v4(root, pointer, current_tuple)
    if pointer.get('generation') == 3:
        return _accepted_rebound_v3(root, pointer, current_tuple)
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


def _accepted_rebound_v3(root, pointer, current_tuple=None):
    """Validate the entire generation-1 -> 2 -> 3 immutable chain."""
    state = _state(root)
    require(pointer.get('schemaVersion') == 3
            and pointer.get('contract') == 'devfleet-accepted-baseline-v3'
            and pointer.get('generation') == 3 and pointer.get('status') == 'ACCEPTED',
            'Generation-3 baseline pointer contract is invalid')
    filename = pointer.get('receiptFile')
    previous_hash = pointer.get('previousPointerSha256')
    require(isinstance(filename, str) and re.fullmatch(r'[0-9a-f]{32}\.json', filename)
            and isinstance(previous_hash, str) and HEX64.fullmatch(previous_hash),
            'Generation-3 lineage reference is invalid')
    history_path = state / 'history' / (previous_hash + '.json')
    require(digest(history_path) == previous_hash,
            'Generation-2 predecessor pointer hash differs')
    previous = read_json(history_path)
    require(previous.get('generation') == 2,
            'Generation-3 predecessor is not generation 2')
    receipt_path = state / 'receipts' / filename
    require(digest(receipt_path) == pointer.get('receiptSha256'),
            'Generation-3 receipt hash differs')
    receipt = read_json(receipt_path)
    old_tuple = exact_tuple(receipt.get('previousCandidate'))
    new_tuple = exact_tuple(receipt.get('candidate'))
    prior = _accepted_rebound_baseline(root, previous, old_tuple)
    require(receipt.get('schemaVersion') == 3
            and receipt.get('contract') == 'devfleet-baseline-rebind-receipt-v3'
            and receipt.get('status') == 'REBOUND'
            and receipt.get('certificationCredit') is False
            and receipt.get('secretValuesRecorded') is False
            and isinstance(receipt.get('receiptId'), str)
            and receipt['receiptId'] + '.json' == filename
            and receipt.get('previousPointerSha256') == previous_hash
            and receipt.get('previousReceiptSha256') == prior['receiptSha256']
            and receipt.get('replacement') == pointer.get('checkpoint')
            and receipt.get('replacement') == previous.get('checkpoint'),
            'Generation-3 receipt lineage differs')
    for key in ('candidateBuildCommit', 'shippingInputIdentity',
                'releaseFingerprintId', 'candidateSha256'):
        require(old_tuple[key] == new_tuple[key],
                'Generation-3 binding changed signed shipping identity: ' + key)
    require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
            and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
            'Generation-3 binding lacks exact HEAD/tooling transition')
    approval = receipt.get('approval') or {}
    require(approval.get('schemaVersion') == 2
            and approval.get('contract') == 'devfleet-baseline-rebind-approval-v2'
            and approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('candidate') == new_tuple
            and approval.get('replacement') == pointer['checkpoint']
            and approval.get('previousReceiptSha256') == prior['receiptSha256']
            and approval.get('sourceSha256') == receipt.get('approvalSha256')
            and isinstance(receipt.get('approvalSha256'), str)
            and HEX64.fullmatch(receipt['approvalSha256']),
            'Generation-3 owner approval differs')
    sources_dir = state / 'sources'
    ledger_sha = receipt.get('successorLedgerSha256')
    inventory_sha = receipt.get('nativeInventorySha256')
    require(receipt.get('finalL1') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
            and receipt.get('successorPolicyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-1'
            and isinstance(ledger_sha, str) and HEX64.fullmatch(ledger_sha)
            and isinstance(inventory_sha, str) and HEX64.fullmatch(inventory_sha),
            'Generation-3 terminal lab or successor lineage differs')
    ledger_source = sources_dir / (ledger_sha + '.json')
    inventory_source = sources_dir / (inventory_sha + '.json')
    require(ledger_source.is_file() and not ledger_source.is_symlink()
            and inventory_source.is_file() and not inventory_source.is_symlink()
            and digest(ledger_source) == ledger_sha
            and digest(inventory_source) == inventory_sha,
            'Generation-3 qualification or native inventory source differs')
    if current_tuple is not None:
        require(new_tuple == exact_tuple(current_tuple),
                'Generation-3 baseline is bound to another candidate/material tuple')
    return {**prior, 'receiptSha256': pointer['receiptSha256'],
            'receiptFile': filename, 'previousReceiptSha256': prior['receiptSha256'],
            'generation': 3}


def _accepted_rebound_v4(root, pointer, current_tuple=None):
    """Validate the immutable generation-1 through generation-4 candidate chain."""
    state = _state(root)
    require(pointer.get('schemaVersion') == 4
            and pointer.get('contract') == 'devfleet-accepted-baseline-v4'
            and pointer.get('generation') == 4 and pointer.get('status') == 'ACCEPTED',
            'Generation-4 baseline pointer contract is invalid')
    filename = pointer.get('receiptFile')
    previous_hash = pointer.get('previousPointerSha256')
    require(isinstance(filename, str) and re.fullmatch(r'[0-9a-f]{32}\.json', filename)
            and isinstance(previous_hash, str) and HEX64.fullmatch(previous_hash),
            'Generation-4 lineage reference is invalid')
    history_path = state / 'history' / (previous_hash + '.json')
    require(digest(history_path) == previous_hash,
            'Generation-3 predecessor pointer hash differs')
    previous = read_json(history_path)
    require(previous.get('generation') == 3, 'Generation-4 predecessor is not generation 3')
    receipt_path = state / 'receipts' / filename
    require(digest(receipt_path) == pointer.get('receiptSha256'),
            'Generation-4 receipt hash differs')
    receipt = read_json(receipt_path)
    old_tuple = exact_tuple(receipt.get('previousCandidate'))
    new_tuple = exact_tuple(receipt.get('candidate'))
    prior = _accepted_rebound_v3(root, previous, old_tuple)
    require(receipt.get('schemaVersion') == 4
            and receipt.get('contract') == 'devfleet-baseline-rebind-receipt-v4'
            and receipt.get('status') == 'REBOUND'
            and receipt.get('certificationCredit') is False
            and receipt.get('secretValuesRecorded') is False
            and isinstance(receipt.get('receiptId'), str)
            and receipt['receiptId'] + '.json' == filename
            and receipt.get('previousPointerSha256') == previous_hash
            and receipt.get('previousReceiptSha256') == prior['receiptSha256']
            and receipt.get('replacement') == pointer.get('checkpoint')
            and receipt.get('replacement') == previous.get('checkpoint'),
            'Generation-4 receipt lineage differs')
    for key in TUPLE_KEYS:
        require(old_tuple[key] != new_tuple[key],
                'Generation-4 binding lacks distinct signed candidate identity: ' + key)
    approval = receipt.get('approval') or {}
    require(approval.get('schemaVersion') == 3
            and approval.get('contract') == 'devfleet-baseline-rebind-approval-v3'
            and approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('shippingChangeApproved') is True
            and approval.get('previousCandidate') == old_tuple
            and approval.get('candidate') == new_tuple
            and approval.get('replacement') == pointer['checkpoint']
            and approval.get('previousReceiptSha256') == prior['receiptSha256']
            and approval.get('sourceSha256') == receipt.get('approvalSha256')
            and isinstance(receipt.get('approvalSha256'), str)
            and HEX64.fullmatch(receipt['approvalSha256']),
            'Generation-4 owner approval differs')
    ledger_sha = receipt.get('successorLedgerSha256')
    inventory_sha = receipt.get('nativeInventorySha256')
    require(receipt.get('finalL1') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
            and receipt.get('successorPolicyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-3'
            and isinstance(ledger_sha, str) and HEX64.fullmatch(ledger_sha)
            and isinstance(inventory_sha, str) and HEX64.fullmatch(inventory_sha),
            'Generation-4 terminal lab or successor lineage differs')
    sources = state / 'sources'
    for source_hash in (ledger_sha, inventory_sha):
        source = sources / (source_hash + '.json')
        require(source.is_file() and not source.is_symlink() and digest(source) == source_hash,
                'Generation-4 qualification or native inventory source differs')
    artifact_sha = receipt.get('artifactReceiptSha256')
    require(isinstance(artifact_sha, str) and HEX64.fullmatch(artifact_sha),
            'Generation-4 artifact receipt hash is missing or malformed')
    artifact_source = sources / (artifact_sha + '.json')
    require(artifact_source.is_file() and not artifact_source.is_symlink()
            and digest(artifact_source) == artifact_sha,
            'Generation-4 signed-output receipt source is absent or altered')
    ledger_source = read_json(sources / (ledger_sha + '.json'))
    require((ledger_source.get('artifactReceipt') or {}).get('sha256') == artifact_sha,
            'Generation-4 ledger artifact receipt binding differs')
    inspected = read_json(artifact_source)
    require(inspected.get('schemaVersion') == 1
            and inspected.get('contract') == 'devfleet-signed-build-output-inspection-v1'
            and inspected.get('status') == 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION'
            and inspected.get('certificationCredit') is False
            and inspected.get('repositoryHead') == new_tuple['candidateBuildCommit']
            and inspected.get('shippingInputIdentity') == new_tuple['shippingInputIdentity']
            and inspected.get('signatureStatus') == 'Valid'
            and inspected.get('publicPromotionAllowed') is False
            and inspected.get('publicPublisherTrust') is False,
            'Generation-4 signed-output receipt differs')
    artifact_rows = inspected.get('artifacts')
    require(isinstance(artifact_rows, list) and len(artifact_rows) == 4
            and {row.get('name') for row in artifact_rows} ==
                {'exe', 'tar', 'portable', 'installerSource'}
            and next(row for row in artifact_rows if row.get('name') == 'exe').get('sha256') ==
                new_tuple['candidateSha256'],
            'Generation-4 signed-output artifact set differs')
    if current_tuple is not None:
        require(new_tuple == exact_tuple(current_tuple),
                'Generation-4 baseline is bound to another candidate/material tuple')
    return {**prior, 'receiptSha256': pointer['receiptSha256'],
            'receiptFile': filename, 'previousReceiptSha256': prior['receiptSha256'],
            'generation': 4}


def _accepted_rebound_v5(root, pointer, current_tuple=None):
    """Validate a same-shipping tooling rebind on the complete gen1–gen4 chain."""
    state = _state(root)
    require(pointer.get('schemaVersion') == 5
            and pointer.get('contract') == 'devfleet-accepted-baseline-v5'
            and pointer.get('generation') == 5 and pointer.get('status') == 'ACCEPTED',
            'Generation-5 baseline pointer contract is invalid')
    filename = pointer.get('receiptFile')
    previous_hash = pointer.get('previousPointerSha256')
    require(isinstance(filename, str) and re.fullmatch(r'[0-9a-f]{32}\.json', filename)
            and isinstance(previous_hash, str) and HEX64.fullmatch(previous_hash),
            'Generation-5 lineage reference is invalid')
    history_path = state / 'history' / (previous_hash + '.json')
    require(digest(history_path) == previous_hash,
            'Generation-4 predecessor pointer hash differs')
    previous = read_json(history_path)
    require(previous.get('generation') == 4, 'Generation-5 predecessor is not generation 4')
    receipt_path = state / 'receipts' / filename
    require(digest(receipt_path) == pointer.get('receiptSha256'),
            'Generation-5 receipt hash differs')
    receipt = read_json(receipt_path)
    old_tuple = exact_tuple(receipt.get('previousCandidate'))
    new_tuple = exact_tuple(receipt.get('candidate'))
    prior = _accepted_rebound_v4(root, previous, old_tuple)
    require(receipt.get('schemaVersion') == 5
            and receipt.get('contract') == 'devfleet-baseline-rebind-receipt-v5'
            and receipt.get('status') == 'REBOUND'
            and receipt.get('certificationCredit') is False
            and receipt.get('secretValuesRecorded') is False
            and 'artifactReceiptSha256' not in receipt
            and isinstance(receipt.get('receiptId'), str)
            and receipt['receiptId'] + '.json' == filename
            and receipt.get('previousPointerSha256') == previous_hash
            and receipt.get('previousReceiptSha256') == prior['receiptSha256']
            and receipt.get('replacement') == pointer.get('checkpoint')
            and receipt.get('replacement') == previous.get('checkpoint'),
            'Generation-5 receipt lineage differs')
    for key in ('candidateBuildCommit', 'shippingInputIdentity',
                'releaseFingerprintId', 'candidateSha256'):
        require(old_tuple[key] == new_tuple[key],
                'Generation-5 binding changed signed shipping identity: ' + key)
    require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
            and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
            'Generation-5 binding lacks changed HEAD and tooling identity')
    approval = receipt.get('approval') or {}
    require(approval.get('schemaVersion') == 4
            and approval.get('contract') == 'devfleet-baseline-rebind-approval-v4'
            and approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('shippingChangeApproved') is False
            and approval.get('previousCandidate') == old_tuple
            and approval.get('candidate') == new_tuple
            and approval.get('replacement') == pointer['checkpoint']
            and approval.get('previousReceiptSha256') == prior['receiptSha256']
            and approval.get('sourceSha256') == receipt.get('approvalSha256')
            and isinstance(receipt.get('approvalSha256'), str)
            and HEX64.fullmatch(receipt['approvalSha256']),
            'Generation-5 owner approval differs')
    ledger_sha = receipt.get('successorLedgerSha256')
    inventory_sha = receipt.get('nativeInventorySha256')
    require(receipt.get('finalL1') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
            and receipt.get('successorPolicyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5'
            and isinstance(ledger_sha, str) and HEX64.fullmatch(ledger_sha)
            and isinstance(inventory_sha, str) and HEX64.fullmatch(inventory_sha),
            'Generation-5 terminal lab or successor lineage differs')
    sources = state / 'sources'
    for source_hash in (ledger_sha, inventory_sha):
        source = sources / (source_hash + '.json')
        require(source.is_file() and not source.is_symlink() and digest(source) == source_hash,
                'Generation-5 qualification or native inventory source differs')
    ledger = read_json(sources / (ledger_sha + '.json'))
    inventory = read_json(sources / (inventory_sha + '.json'))
    attempts = ledger.get('attempts') or []
    require(ledger.get('policyId') == receipt['successorPolicyId']
            and ledger.get('limits') == {'standard-token': 1, 'diagnostic': 1,
                                         'laptop-proof': 1, 'desktop-proof': 1,
                                         'fullrelease': 1, 'maintenance': 0,
                                         'build-sign': 0}
            and ledger.get('activeRunId') is None
            and isinstance(attempts, list) and len(attempts) == 1
            and attempts[0].get('operation') == 'standard-token'
            and attempts[0].get('state') == 'TERMINAL'
            and attempts[0].get('exitCode') == 0
            and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
            and attempts[0].get('tuple') == new_tuple
            and attempts[0].get('certificationCredit') is False
            and isinstance(attempts[0].get('evidence'), list)
            and bool(attempts[0]['evidence']),
            'Generation-5 qualification source lacks exact repair5 standard token')
    snapshots = inventory.get('snapshots')
    named = ([row for row in snapshots if isinstance(row, dict)
              and row.get('name') == NEW_NAME] if isinstance(snapshots, list) else [])
    require(inventory.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
            and inventory.get('vm') == receipt['finalL1']
            and len(named) == 1
            and named[0].get('id') == prior['id']
            and named[0].get('vmId') == VM_ID
            and named[0].get('parentSnapshotId') == OLD_ID,
            'Generation-5 inventory does not prove accepted checkpoint and L1 Off')
    if current_tuple is not None:
        require(new_tuple == exact_tuple(current_tuple),
                'Generation-5 baseline is bound to another candidate/material tuple')
    return {**prior, 'receiptSha256': pointer['receiptSha256'],
            'receiptFile': filename, 'previousReceiptSha256': prior['receiptSha256'],
            'generation': 5}


def rebind_gen5(root, tuple_path, approval_path, ledger_path, live_path):
    """Append one owner-approved same-shipping binding to accepted generation 4."""
    state = _state(root)
    with lock(state / '.adoption.lock'), lock(Path(str(ledger_path) + '.lock')):
        pointer_path = state / 'CURRENT.json'
        pointer = read_json(pointer_path)
        require(pointer.get('generation') == 4,
                'Generation-5 binding requires accepted generation 4')
        old_receipt = read_json(state / 'receipts' / pointer['receiptFile'])
        old_tuple = exact_tuple(old_receipt.get('candidate'))
        prior = _accepted_rebound_v4(root, pointer, old_tuple)
        tuple_sha_before = digest(tuple_path)
        new_tuple = exact_tuple(read_json(tuple_path))
        for key in ('candidateBuildCommit', 'shippingInputIdentity',
                    'releaseFingerprintId', 'candidateSha256'):
            require(old_tuple[key] == new_tuple[key],
                    'Generation-5 binding changed signed shipping identity: ' + key)
        require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
                and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
                'Generation-5 binding requires changed HEAD and tooling identity')
        approval_sha_before = digest(approval_path)
        approval = read_json(approval_path)
        require(approval.get('schemaVersion') == 4
                and approval.get('contract') == 'devfleet-baseline-rebind-approval-v4'
                and approval.get('decision') == 'APPROVE'
                and approval.get('approvedBy') == 'ACCOUNT_OWNER'
                and approval.get('shippingChangeApproved') is False
                and approval.get('previousCandidate') == old_tuple
                and approval.get('candidate') == new_tuple
                and approval.get('replacement') == pointer['checkpoint']
                and approval.get('previousReceiptSha256') == prior['receiptSha256'],
                'Exact generation-5 account-owner approval is absent')
        ledger_sha_before = digest(ledger_path)
        ledger = read_json(ledger_path)
        journal = Path(root).resolve(strict=True) / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Native fifth repair successor journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0, 'Native fifth repair successor journal rejected binding')
        journal_status = json.loads(checked.stdout)
        remaining = {'standard-token': 0, 'diagnostic': 1, 'laptop-proof': 1,
                     'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0,
                     'build-sign': 0}
        attempts = ledger.get('attempts') or []
        require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5'
                and journal_status.get('policyId') == ledger['policyId']
                and ledger.get('activeRunId') is None
                and journal_status.get('active') is None
                and journal_status.get('attemptCount') == 1
                and journal_status.get('remaining') == remaining
                and isinstance(attempts, list) and len(attempts) == 1
                and attempts[0].get('operation') == 'standard-token'
                and attempts[0].get('state') == 'TERMINAL'
                and attempts[0].get('exitCode') == 0
                and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
                and attempts[0].get('tuple') == new_tuple
                and attempts[0].get('certificationCredit') is False
                and isinstance(attempts[0].get('evidence'), list)
                and bool(attempts[0]['evidence']),
                'Native fifth repair successor lacks exact terminal Developer qualification')
        inventory_sha_before = digest(live_path)
        live = read_json(live_path)
        named = [x for x in live.get('snapshots', [])
                 if isinstance(x, dict) and x.get('name') == NEW_NAME]
        require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
                and timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc')) <= timedelta(minutes=2)
                and len(named) == 1 and named[0].get('id') == prior['id']
                and named[0].get('vmId') == VM_ID
                and named[0].get('parentSnapshotId') == OLD_ID,
                'Exact accepted checkpoint is not present with L1 Off')
        ledger_bytes = Path(ledger_path).read_bytes()
        inventory_bytes = Path(live_path).read_bytes()
        ledger_sha = hashlib.sha256(ledger_bytes).hexdigest()
        inventory_sha = hashlib.sha256(inventory_bytes).hexdigest()
        require(inventory_sha == inventory_sha_before,
                'Native inventory changed during generation-5 binding')
        require(digest(tuple_path) == tuple_sha_before,
                'Candidate tuple changed during generation-5 binding')
        require(digest(approval_path) == approval_sha_before,
                'Owner approval changed during generation-5 binding')
        require(ledger_sha == ledger_sha_before,
                'Successor ledger changed during generation-5 binding')
        sources = state / 'sources'
        sources.mkdir(parents=True, exist_ok=True)
        _write_exclusive(sources / (ledger_sha + '.json'), ledger_bytes)
        _write_exclusive(sources / (inventory_sha + '.json'), inventory_bytes)
        previous_hash = digest(pointer_path)
        history = state / 'history'
        history.mkdir(parents=True, exist_ok=True)
        _write_exclusive(history / (previous_hash + '.json'), pointer_path.read_bytes())
        receipt_id = uuid.uuid4().hex
        receipt = {'schemaVersion': 5, 'contract': 'devfleet-baseline-rebind-receipt-v5',
                   'receiptId': receipt_id, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': previous_hash,
                   'previousReceiptSha256': prior['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': pointer['checkpoint'],
                   'approval': {**approval, 'sourceSha256': approval_sha_before},
                   'approvalSha256': approval_sha_before,
                   'successorPolicyId': ledger['policyId'],
                   'successorLedgerSha256': ledger_sha,
                   'finalL1': live['vm'], 'nativeInventorySha256': inventory_sha}
        filename = receipt_id + '.json'
        receipt_path = state / 'receipts' / filename
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 5, 'contract': 'devfleet-accepted-baseline-v5',
                   'generation': 5, 'status': 'ACCEPTED',
                   'receiptFile': filename, 'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': pointer['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


def _accepted_rebound_v6(root, pointer, current_tuple=None):
    """Validate a same-shipping tooling rebind on the complete gen1–gen5 chain."""
    state = _state(root)
    require(pointer.get('schemaVersion') == 6
            and pointer.get('contract') == 'devfleet-accepted-baseline-v6'
            and pointer.get('generation') == 6 and pointer.get('status') == 'ACCEPTED',
            'Generation-6 baseline pointer contract is invalid')
    filename = pointer.get('receiptFile')
    previous_hash = pointer.get('previousPointerSha256')
    require(isinstance(filename, str) and re.fullmatch(r'[0-9a-f]{32}\.json', filename)
            and isinstance(previous_hash, str) and HEX64.fullmatch(previous_hash),
            'Generation-6 lineage reference is invalid')
    history_path = state / 'history' / (previous_hash + '.json')
    require(digest(history_path) == previous_hash,
            'Generation-5 predecessor pointer hash differs')
    previous = read_json(history_path)
    require(previous.get('generation') == 5, 'Generation-6 predecessor is not generation 5')
    receipt_path = state / 'receipts' / filename
    require(digest(receipt_path) == pointer.get('receiptSha256'),
            'Generation-6 receipt hash differs')
    receipt = read_json(receipt_path)
    old_tuple = exact_tuple(receipt.get('previousCandidate'))
    new_tuple = exact_tuple(receipt.get('candidate'))
    prior = _accepted_rebound_v5(root, previous, old_tuple)
    require(receipt.get('schemaVersion') == 6
            and receipt.get('contract') == 'devfleet-baseline-rebind-receipt-v6'
            and receipt.get('status') == 'REBOUND'
            and receipt.get('certificationCredit') is False
            and receipt.get('secretValuesRecorded') is False
            and 'artifactReceiptSha256' not in receipt
            and isinstance(receipt.get('receiptId'), str)
            and receipt['receiptId'] + '.json' == filename
            and receipt.get('previousPointerSha256') == previous_hash
            and receipt.get('previousReceiptSha256') == prior['receiptSha256']
            and receipt.get('replacement') == pointer.get('checkpoint')
            and receipt.get('replacement') == previous.get('checkpoint'),
            'Generation-6 receipt lineage differs')
    for key in ('candidateBuildCommit', 'shippingInputIdentity',
                'releaseFingerprintId', 'candidateSha256'):
        require(old_tuple[key] == new_tuple[key],
                'Generation-6 binding changed signed shipping identity: ' + key)
    require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
            and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
            'Generation-6 binding lacks changed HEAD and tooling identity')
    approval = receipt.get('approval') or {}
    require(approval.get('schemaVersion') == 5
            and approval.get('contract') == 'devfleet-baseline-rebind-approval-v5'
            and approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('shippingChangeApproved') is False
            and approval.get('previousCandidate') == old_tuple
            and approval.get('candidate') == new_tuple
            and approval.get('replacement') == pointer['checkpoint']
            and approval.get('previousReceiptSha256') == prior['receiptSha256']
            and approval.get('sourceSha256') == receipt.get('approvalSha256')
            and isinstance(receipt.get('approvalSha256'), str)
            and HEX64.fullmatch(receipt['approvalSha256']),
            'Generation-6 owner approval differs')
    ledger_sha = receipt.get('successorLedgerSha256')
    inventory_sha = receipt.get('nativeInventorySha256')
    require(receipt.get('finalL1') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
            and receipt.get('successorPolicyId') == 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1'
            and isinstance(ledger_sha, str) and HEX64.fullmatch(ledger_sha)
            and isinstance(inventory_sha, str) and HEX64.fullmatch(inventory_sha),
            'Generation-6 terminal lab or successor lineage differs')
    sources = state / 'sources'
    for source_hash in (ledger_sha, inventory_sha):
        source = sources / (source_hash + '.json')
        require(source.is_file() and not source.is_symlink() and digest(source) == source_hash,
                'Generation-6 qualification or native inventory source differs')
    ledger = read_json(sources / (ledger_sha + '.json'))
    inventory = read_json(sources / (inventory_sha + '.json'))
    attempts = ledger.get('attempts') or []
    require(ledger.get('policyId') == receipt['successorPolicyId']
            and ledger.get('limits') == {'standard-token': 1, 'diagnostic': 1,
                                         'laptop-proof': 1, 'desktop-proof': 1,
                                         'fullrelease': 1, 'maintenance': 0,
                                         'build-sign': 0}
            and ledger.get('activeRunId') is None
            and isinstance(attempts, list) and len(attempts) == 1
            and attempts[0].get('operation') == 'standard-token'
            and attempts[0].get('state') == 'TERMINAL'
            and attempts[0].get('exitCode') == 0
            and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
            and attempts[0].get('tuple') == new_tuple
            and attempts[0].get('certificationCredit') is False
            and isinstance(attempts[0].get('evidence'), list)
            and bool(attempts[0]['evidence']),
            'Generation-6 qualification source lacks exact causal standard token')
    snapshots = inventory.get('snapshots')
    named = ([row for row in snapshots if isinstance(row, dict)
              and row.get('name') == NEW_NAME] if isinstance(snapshots, list) else [])
    require(inventory.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
            and inventory.get('vm') == receipt['finalL1']
            and len(named) == 1
            and named[0].get('id') == prior['id']
            and named[0].get('vmId') == VM_ID
            and named[0].get('parentSnapshotId') == OLD_ID,
            'Generation-6 inventory does not prove accepted checkpoint and L1 Off')
    if current_tuple is not None:
        require(new_tuple == exact_tuple(current_tuple),
                'Generation-6 baseline is bound to another candidate/material tuple')
    return {**prior, 'receiptSha256': pointer['receiptSha256'],
            'receiptFile': filename, 'previousReceiptSha256': prior['receiptSha256'],
            'generation': 6}


def rebind_gen6(root, tuple_path, approval_path, ledger_path, live_path):
    """Append one owner-approved same-shipping binding to accepted generation 5."""
    state = _state(root)
    with lock(state / '.adoption.lock'), lock(Path(str(ledger_path) + '.lock')):
        pointer_path = state / 'CURRENT.json'
        pointer = read_json(pointer_path)
        require(pointer.get('generation') == 5,
                'Generation-6 binding requires accepted generation 5')
        old_receipt = read_json(state / 'receipts' / pointer['receiptFile'])
        old_tuple = exact_tuple(old_receipt.get('candidate'))
        prior = _accepted_rebound_v5(root, pointer, old_tuple)
        tuple_sha_before = digest(tuple_path)
        new_tuple = exact_tuple(read_json(tuple_path))
        for key in ('candidateBuildCommit', 'shippingInputIdentity',
                    'releaseFingerprintId', 'candidateSha256'):
            require(old_tuple[key] == new_tuple[key],
                    'Generation-6 binding changed signed shipping identity: ' + key)
        require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
                and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
                'Generation-6 binding requires changed HEAD and tooling identity')
        approval_sha_before = digest(approval_path)
        approval = read_json(approval_path)
        require(approval.get('schemaVersion') == 5
                and approval.get('contract') == 'devfleet-baseline-rebind-approval-v5'
                and approval.get('decision') == 'APPROVE'
                and approval.get('approvedBy') == 'ACCOUNT_OWNER'
                and approval.get('shippingChangeApproved') is False
                and approval.get('previousCandidate') == old_tuple
                and approval.get('candidate') == new_tuple
                and approval.get('replacement') == pointer['checkpoint']
                and approval.get('previousReceiptSha256') == prior['receiptSha256'],
                'Exact generation-6 account-owner approval is absent')
        ledger_sha_before = digest(ledger_path)
        ledger = read_json(ledger_path)
        journal = Path(root).resolve(strict=True) / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Native causal successor journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0, 'Native causal successor journal rejected binding')
        journal_status = json.loads(checked.stdout)
        remaining = {'standard-token': 0, 'diagnostic': 1, 'laptop-proof': 1,
                     'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0,
                     'build-sign': 0}
        attempts = ledger.get('attempts') or []
        require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1'
                and journal_status.get('policyId') == ledger['policyId']
                and ledger.get('activeRunId') is None
                and journal_status.get('active') is None
                and journal_status.get('attemptCount') == 1
                and journal_status.get('remaining') == remaining
                and isinstance(attempts, list) and len(attempts) == 1
                and attempts[0].get('operation') == 'standard-token'
                and attempts[0].get('state') == 'TERMINAL'
                and attempts[0].get('exitCode') == 0
                and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
                and attempts[0].get('tuple') == new_tuple
                and attempts[0].get('certificationCredit') is False
                and isinstance(attempts[0].get('evidence'), list)
                and bool(attempts[0]['evidence']),
                'Native causal successor lacks exact terminal Developer qualification')
        inventory_sha_before = digest(live_path)
        live = read_json(live_path)
        named = [x for x in live.get('snapshots', [])
                 if isinstance(x, dict) and x.get('name') == NEW_NAME]
        require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
                and timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc')) <= timedelta(minutes=2)
                and len(named) == 1 and named[0].get('id') == prior['id']
                and named[0].get('vmId') == VM_ID
                and named[0].get('parentSnapshotId') == OLD_ID,
                'Exact accepted checkpoint is not present with L1 Off')
        ledger_bytes = Path(ledger_path).read_bytes()
        inventory_bytes = Path(live_path).read_bytes()
        ledger_sha = hashlib.sha256(ledger_bytes).hexdigest()
        inventory_sha = hashlib.sha256(inventory_bytes).hexdigest()
        require(inventory_sha == inventory_sha_before,
                'Native inventory changed during generation-6 binding')
        require(digest(tuple_path) == tuple_sha_before,
                'Candidate tuple changed during generation-6 binding')
        require(digest(approval_path) == approval_sha_before,
                'Owner approval changed during generation-6 binding')
        require(ledger_sha == ledger_sha_before,
                'Successor ledger changed during generation-6 binding')
        sources = state / 'sources'
        sources.mkdir(parents=True, exist_ok=True)
        _write_exclusive(sources / (ledger_sha + '.json'), ledger_bytes)
        _write_exclusive(sources / (inventory_sha + '.json'), inventory_bytes)
        previous_hash = digest(pointer_path)
        history = state / 'history'
        history.mkdir(parents=True, exist_ok=True)
        _write_exclusive(history / (previous_hash + '.json'), pointer_path.read_bytes())
        receipt_id = uuid.uuid4().hex
        receipt = {'schemaVersion': 6, 'contract': 'devfleet-baseline-rebind-receipt-v6',
                   'receiptId': receipt_id, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': previous_hash,
                   'previousReceiptSha256': prior['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': pointer['checkpoint'],
                   'approval': {**approval, 'sourceSha256': approval_sha_before},
                   'approvalSha256': approval_sha_before,
                   'successorPolicyId': ledger['policyId'],
                   'successorLedgerSha256': ledger_sha,
                   'finalL1': live['vm'], 'nativeInventorySha256': inventory_sha}
        filename = receipt_id + '.json'
        receipt_path = state / 'receipts' / filename
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 6, 'contract': 'devfleet-accepted-baseline-v6',
                   'generation': 6, 'status': 'ACCEPTED',
                   'receiptFile': filename, 'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': pointer['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


COLLISION_POLICY = 'DF-FRESH-CERTIFICATION-20260930-COLLISION-1'
OWNER_AUTH_SHA256 = 'f9eec666193447810089ffbd1ad249aba8f8e8a7d13e5220d10ef5ac2c64af16'
COLLISION_PREDECESSOR_SHA256 = '6deb98ab9dd165798e31538772f01e23eceeb333b10e0067a066685952f680e1'
COLLISION_LEDGER_PATH = Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work\DevFleet-v1.2.13-development\audit\agent-memory\attempts\DF-FRESH-CERTIFICATION-20260930-COLLISION-1\ledger.json')
COLLISION_FIRST_ERROR = 'Cannot create a file when that file already exists.'
COLLISION_LIMITS = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                    'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0,
                    'build-sign': 0}
HTTP_CLEANUP_POLICY = 'DF-FRESH-CERTIFICATION-20261001-HTTP-CLEANUP-1'
HTTP_CLEANUP_PREDECESSOR_SHA256 = '2bede7d9944502898b919d4a29ed73f99c2009a819850349d5b08bfd6e8bb1c4'
HTTP_CLEANUP_LEDGER_PATH = Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work\DevFleet-v1.2.13-development\audit\agent-memory\attempts\DF-FRESH-CERTIFICATION-20261001-HTTP-CLEANUP-1\ledger.json')
HTTP_CLEANUP_LIMITS = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                       'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0,
                       'build-sign': 0}
TOKEN_CHECKS = {'pass', 'payloadExtraction', 'bootstrapEntrypoint',
                'parameterContract', 'embeddedTarCount', 'factoryResetBackupGate',
                'planSafety', 'devfleetVersion', 'installerVersion', 'payloadSha'}


def _gen7_source(state, source_hash, extension):
    require(isinstance(source_hash, str) and HEX64.fullmatch(source_hash),
            'Generation-7 source hash is malformed')
    path = state / 'sources' / (source_hash + extension)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4_000_000
            and digest(path) == source_hash, 'Generation-7 frozen source differs')
    return path


def _gen7_token(root, pointer_path, candidate, frozen=None, historical=False):
    """Validate exact current Developer evidence, then optionally frozen copies."""
    root = Path(root).resolve(strict=True)
    require(not Path(pointer_path).is_symlink(), 'Generation-7 token pointer is linked')
    pointer_path = Path(pointer_path).resolve(strict=True)
    require(pointer_path == root / 'evidence/CURRENT-STANDARD-TOKEN.json',
            'Generation-7 token pointer is not canonical')
    frozen_pointer_path = None
    if historical:
        require(isinstance(frozen, dict),
                'Generation-7 historical token receipt reference is absent')
        frozen_pointer_path = _gen7_source(_state(root), frozen.get('pointerSha256'), '.json')
        pointer = read_json(frozen_pointer_path)
    else:
        pointer = read_json(pointer_path)
    run_id = pointer.get('runId')
    require(isinstance(run_id, str) and re.fullmatch(r'standard-token-[A-Za-z0-9-]+', run_id),
            'Generation-7 token RunId is malformed')
    relative = 'evidence/standard-token/' + run_id
    canonical_path = root / relative / 'standard-token-evidence.json'
    raw_path = root / relative / 'installer-self-test-raw.txt'
    canonical = read_json(canonical_path)
    require(pointer == canonical, 'Generation-7 token pointer and canonical evidence differ')
    require(raw_path.is_file() and not raw_path.is_symlink()
            and raw_path.stat().st_size <= 4_000_000,
            'Generation-7 raw token evidence is absent, linked, or oversized')
    actual = {key: pointer.get(key) for key in TUPLE_KEYS if key != 'candidateSha256'}
    token = pointer.get('token') or {}
    checks = pointer.get('requiredChecks')
    require(pointer.get('schemaVersion') == 1 and pointer.get('status') == 'PASS'
            and pointer.get('standardNonAdministratorToken') is True
            and pointer.get('exitCode') == 0
            and pointer.get('residualSelfTestScratchCount') == 0
            and actual == {key: candidate[key] for key in TUPLE_KEYS if key != 'candidateSha256'}
            and pointer.get('runDirectory') == relative
            and pointer.get('rawReportPath') == relative + '/installer-self-test-raw.txt'
            and pointer.get('canonicalEvidencePath') == relative + '/standard-token-evidence.json'
            and isinstance(checks, dict) and set(checks) == TOKEN_CHECKS
            and all(value is True for value in checks.values())
            and isinstance(token, dict)
            and isinstance(token.get('userName'), str)
            and re.fullmatch(r'[^\\]+\\Developer', token['userName'], re.IGNORECASE)
            and token.get('standardNonAdministratorToken') is True
            and token.get('isAdministratorMember') is False
            and token.get('isAdministratorEnabled') is False
            and token.get('isElevated') is False
            and token.get('integrityLevel') == 'Medium',
            'Generation-7 token is not an exact Developer standard-token PASS')
    exe, tar = pointer.get('exe') or {}, pointer.get('tar') or {}
    require(exe.get('sha256') == candidate['candidateSha256']
            and isinstance(exe.get('bytes'), int) and exe['bytes'] > 0
            and isinstance(tar.get('sha256'), str) and HEX64.fullmatch(tar['sha256'])
            and isinstance(tar.get('bytes'), int) and tar['bytes'] > 0,
            'Generation-7 token signed artifacts differ')
    runner = pointer.get('runner') or {}
    runner_relative = 'automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1'
    runner_path = root / runner_relative
    require(runner.get('path') == runner_relative and runner_path.is_file()
            and not runner_path.is_symlink()
            and runner.get('sha256') == digest(runner_path),
            'Generation-7 standard-token runner source differs')
    raw = raw_path.read_text(encoding='utf-8-sig')
    require(pointer.get('reportSha256') == digest(raw_path)
            and re.search(r'(?m)^PASS\s*$', raw) is not None
            and 'payload=' + tar['sha256'] in raw,
            'Generation-7 raw report lacks exact PASS and payload')
    refs = {'runId': run_id,
            'pointerSha256': digest(frozen_pointer_path) if historical else digest(pointer_path),
            'canonicalSha256': digest(canonical_path),
            'rawReportSha256': digest(raw_path),
            'pointerPath': 'evidence/CURRENT-STANDARD-TOKEN.json',
            'canonicalPath': relative + '/standard-token-evidence.json',
            'rawReportPath': relative + '/installer-self-test-raw.txt'}
    if frozen is not None:
        require(refs == frozen, 'Generation-7 current token evidence differs from receipt')
        state = _state(root)
        for key, ext in (('pointerSha256', '.json'), ('canonicalSha256', '.json'),
                         ('rawReportSha256', '.txt')):
            source = _gen7_source(state, refs[key], ext)
            current = {'pointerSha256': pointer_path, 'canonicalSha256': canonical_path,
                       'rawReportSha256': raw_path}[key]
            if historical and key == 'pointerSha256':
                continue
            require(source.read_bytes() == current.read_bytes(),
                    'Generation-7 frozen token bytes differ from current')
    return refs, (pointer_path, canonical_path, raw_path)


def _gen7_validation(root, pointer, receipt, previous, prior, old_tuple, new_tuple,
                     historical=False):
    state = _state(root)
    approval = receipt.get('approval') or {}
    require(receipt.get('schemaVersion') == 7
            and receipt.get('contract') == 'devfleet-baseline-rebind-receipt-v7'
            and receipt.get('status') == 'REBOUND'
            and receipt.get('certificationCredit') is False
            and receipt.get('secretValuesRecorded') is False
            and 'artifactReceiptSha256' not in receipt
            and receipt.get('previousPointerSha256') == pointer['previousPointerSha256']
            and receipt.get('previousReceiptSha256') == prior['receiptSha256']
            and receipt.get('replacement') == previous['checkpoint'] == pointer['checkpoint']
            and receipt.get('successorPolicyId') == COLLISION_POLICY
            and receipt.get('finalL1') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
            and all(old_tuple[key] == new_tuple[key] for key in
                    ('candidateBuildCommit', 'shippingInputIdentity',
                     'releaseFingerprintId', 'candidateSha256'))
            and old_tuple['repositoryHead'] != new_tuple['repositoryHead']
            and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
            'Generation-7 receipt or signed shipping identity differs')
    require(approval.get('schemaVersion') == 7
            and approval.get('contract') == 'devfleet-baseline-rebind-approval-v7'
            and approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('shippingChangeApproved') is False
            and approval.get('previousCandidate') == old_tuple
            and approval.get('candidate') == new_tuple
            and approval.get('replacement') == pointer['checkpoint']
            and approval.get('previousReceiptSha256') == prior['receiptSha256']
            and approval.get('successorAuthorizationSha256') == receipt.get('successorAuthorizationSha256')
            and approval.get('sourceSha256') == receipt.get('approvalSha256')
            and isinstance(receipt.get('approvalSha256'), str)
            and HEX64.fullmatch(receipt['approvalSha256']),
            'Generation-7 account-owner approval differs')
    approval_source = read_json(_gen7_source(state, receipt['approvalSha256'], '.json'))
    require('sourceSha256' not in approval_source
            and {**approval_source, 'sourceSha256': receipt['approvalSha256']} == approval,
            'Generation-7 frozen account-owner approval source differs')
    hashes = {key: receipt.get(key) for key in
              ('successorLedgerSha256', 'nativeInventorySha256',
               'successorAuthorizationSha256', 'predecessorLedgerSha256')}
    sources = {key: read_json(_gen7_source(state, value, '.json'))
               for key, value in hashes.items()}
    failures = receipt.get('failureEvidenceSha256')
    require(isinstance(failures, dict) and set(failures) == {'wrapper', 'proofError', 'cleanup'},
            'Generation-7 collision failure source refs are incomplete')
    failure_records = {key: read_json(_gen7_source(state, value, '.json'))
                       for key, value in failures.items()}
    auth = sources['successorAuthorizationSha256']
    ledger = sources['successorLedgerSha256']
    predecessor = sources['predecessorLedgerSha256']
    live = sources['nativeInventorySha256']
    require(receipt.get('ownerAuthorizationSha256') == OWNER_AUTH_SHA256
            and (auth.get('ownerAuthorization') or {}).get('sha256') == OWNER_AUTH_SHA256,
            'Generation-7 exact owner authorization hash differs')
    _gen7_source(state, OWNER_AUTH_SHA256, '.txt')
    require(auth.get('schemaVersion') == 1
            and auth.get('kind') == 'DEVFLEET_POST_COLLISION_SUCCESSOR_AUTHORIZATION'
            and auth.get('policyId') == COLLISION_POLICY
            and auth.get('approved') is True
            and auth.get('approvedBy') == 'ACCOUNT_OWNER'
            and isinstance(auth.get('successorLedgerPath'), str)
            and Path(auth['successorLedgerPath']).resolve() == COLLISION_LEDGER_PATH.resolve()
            and auth.get('previousCandidate') == old_tuple
            and auth.get('candidate') == new_tuple
            and (auth.get('predecessorSha256') or {}).get('causal1') == COLLISION_PREDECESSOR_SHA256
            and hashes['predecessorLedgerSha256'] == COLLISION_PREDECESSOR_SHA256
            and (auth.get('generation6') or {}).get('receiptSha256') == prior['receiptSha256']
            and (auth.get('generation6') or {}).get('checkpoint') == pointer['checkpoint']
            and auth.get('limits') == COLLISION_LIMITS
            and all((auth.get('failureEvidence') or {}).get(key, {}).get('sha256') == value
                    for key, value in failures.items())
            and predecessor.get('policyId') == 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1',
            'Generation-7 collision authorization or predecessor differs')
    _gen7_collision_failure(predecessor, old_tuple, auth, failure_records)
    attempts = ledger.get('attempts')
    require(ledger.get('policyId') == COLLISION_POLICY
            and ledger.get('limits') == COLLISION_LIMITS
            and ledger.get('activeRunId') is None
            and (ledger.get('authorization') or {}).get('sha256') == hashes['successorAuthorizationSha256']
            and len(ledger.get('predecessors') or []) == 1
            and ledger['predecessors'][0].get('sha256') == hashes['predecessorLedgerSha256']
            and isinstance(attempts, list) and len(attempts) == 1
            and attempts[0].get('operation') == 'standard-token'
            and attempts[0].get('state') == 'TERMINAL'
            and attempts[0].get('exitCode') == 0
            and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
            and attempts[0].get('tuple') == new_tuple
            and attempts[0].get('certificationCredit') is False
            and isinstance(attempts[0].get('evidence'), list)
            and bool(attempts[0]['evidence']),
            'Generation-7 ledger lacks one exact terminal standard-token PASS')
    snapshots = live.get('snapshots')
    exact = [x for x in snapshots if isinstance(x, dict) and x.get('name') == NEW_NAME] if isinstance(snapshots, list) else []
    require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
            and live.get('vm') == receipt['finalL1']
            and len(exact) == 1 and exact[0].get('id') == prior['id']
            and exact[0].get('vmId') == VM_ID
            and exact[0].get('parentSnapshotId') == OLD_ID,
            'Generation-7 native inventory lacks accepted CLEAN-R2 with L1 Off')
    token_ref = receipt.get('standardTokenEvidence')
    require(isinstance(token_ref, dict), 'Generation-7 token receipt reference is absent')
    _gen7_token(root, Path(root) / 'evidence/CURRENT-STANDARD-TOKEN.json', new_tuple,
                token_ref, historical=historical)
    _gen7_outer_inner(attempts[0], Path(root), token_ref)


def _gen7_outer_inner(attempt, root, token_ref):
    """Join charged outer attempt to the immutable inner self-test record."""
    canonical = (root / token_ref['canonicalPath']).resolve(strict=True)
    evidence = attempt.get('evidence')
    require(attempt.get('runId') != token_ref.get('runId')
            and isinstance(evidence, list) and any(isinstance(item, str)
            and Path(item).resolve() == canonical for item in evidence),
            'Generation-7 charged attempt does not cite inner token evidence')
    token = read_json(canonical)
    require(token.get('runId') == token_ref['runId']
            and digest(canonical) == token_ref['canonicalSha256']
            and _gen7_journal_instant(attempt.get('reservedUtc')) <= instant(token.get('generatedAtUtc'))
            <= _gen7_journal_instant(attempt.get('terminalUtc')),
            'Generation-7 inner token is not within charged outer attempt')


def _gen7_journal_instant(value):
    require(isinstance(value, str) and value, 'Generation-7 journal timestamp is missing')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None, 'Generation-7 journal timestamp lacks timezone')
    return parsed.astimezone(timezone.utc)


def _gen7_collision_failure(predecessor, old_tuple, auth, failures):
    attempts = predecessor.get('attempts')
    sequence = (('standard-token', 0, 'PASS_NATIVE_STANDARD_TOKEN'),
                ('diagnostic', 0, 'PASS_READY_FOR_PROOF_RESERVATION'),
                ('laptop-proof', 2, 'NATIVE_LAPTOP_PROOF_BLOCKED'))
    require(predecessor.get('schemaVersion') == 1
            and predecessor.get('policyId') == 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1'
            and predecessor.get('certificationCredit') is False
            and predecessor.get('limits') == COLLISION_LIMITS
            and predecessor.get('activeRunId') is None
            and isinstance(attempts, list) and len(attempts) == 3
            and all(isinstance(row, dict) and row.get('operation') == operation
                    and row.get('state') == 'TERMINAL'
                    and row.get('exitCode') == exit_code
                    and row.get('classification') == classification
                    and row.get('tuple') == old_tuple
                    for row, (operation, exit_code, classification) in zip(attempts, sequence))
            and len({row.get('runId') for row in attempts}) == 3
            and auth.get('failedRunId') == attempts[-1]['runId'],
            'Generation-7 causal predecessor history differs')
    failed_run = auth['failedRunId']
    require(all(isinstance(failures[key], dict)
                and failures[key].get('runId') == failed_run
                and all(failures[key][field] == failed_run for field in
                        ('runId', 'attemptRunId', 'proofRunId') if field in failures[key])
                for key in ('wrapper', 'proofError', 'cleanup')),
            'Generation-7 collision records differ from failed RunId')
    wrapper, proof, cleanup = (failures[key] for key in
                               ('wrapper', 'proofError', 'cleanup'))
    l1, l2 = cleanup.get('l1') or {}, cleanup.get('l2') or {}
    require(wrapper.get('classification') == 'NATIVE_LAPTOP_PROOF_BLOCKED'
            and wrapper.get('exitCode') == 2
            and wrapper.get('firstTechnicalFailure') == COLLISION_FIRST_ERROR
            and wrapper.get('observerTerminal') != COLLISION_FIRST_ERROR
            and proof.get('status') == 'BLOCKED'
            and proof.get('error') == COLLISION_FIRST_ERROR
            and cleanup.get('status') == 'PASS'
            and cleanup.get('runOwnedOnly') is True
            and l1.get('name') == VM_NAME and l1.get('id') == VM_ID
            and l1.get('status') == 'OFF'
            and l2.get('expectedName') == L2_NAME
            and l2.get('status') == 'ABSENT'
            and l2.get('present') is False
            and l2.get('exactMatchCount') == 0
            and l2.get('inventoryCount') == 0
            and cleanup.get('l2Present') is False,
            'Generation-7 first failure, later observer, or cleanup differs')


def _accepted_rebound_v7(root, pointer, current_tuple=None, historical=False):
    state = _state(root)
    require(pointer.get('schemaVersion') == 7
            and pointer.get('contract') == 'devfleet-accepted-baseline-v7'
            and pointer.get('generation') == 7 and pointer.get('status') == 'ACCEPTED',
            'Generation-7 pointer contract differs')
    filename, previous_hash = pointer.get('receiptFile'), pointer.get('previousPointerSha256')
    require(isinstance(filename, str) and re.fullmatch(r'[0-9a-f]{32}\.json', filename)
            and isinstance(previous_hash, str) and HEX64.fullmatch(previous_hash),
            'Generation-7 lineage reference is malformed')
    previous_path = state / 'history' / (previous_hash + '.json')
    require(previous_path.is_file() and not previous_path.is_symlink() and digest(previous_path) == previous_hash,
            'Generation-7 predecessor pointer differs')
    previous = read_json(previous_path)
    require(previous.get('generation') == 6, 'Generation-7 predecessor must be accepted Gen6')
    receipt_path = state / 'receipts' / filename
    require(receipt_path.is_file() and not receipt_path.is_symlink()
            and digest(receipt_path) == pointer.get('receiptSha256'),
            'Generation-7 receipt hash differs')
    receipt = read_json(receipt_path)
    require(isinstance(receipt.get('receiptId'), str)
            and receipt['receiptId'] + '.json' == filename,
            'Generation-7 receipt filename differs')
    old_tuple = exact_tuple(receipt.get('previousCandidate'))
    new_tuple = exact_tuple(receipt.get('candidate'))
    prior = _accepted_rebound_v6(root, previous, old_tuple)
    _gen7_validation(root, pointer, receipt, previous, prior, old_tuple, new_tuple,
                     historical=_gen7_historical_token(root, new_tuple, historical))
    if current_tuple is not None:
        require(new_tuple == exact_tuple(current_tuple),
                'Generation-7 baseline is bound to another candidate/material tuple')
    return {**prior, 'receiptSha256': pointer['receiptSha256'], 'receiptFile': filename,
            'previousReceiptSha256': prior['receiptSha256'], 'generation': 7}


def _gen7_historical_token(root, candidate, explicitly_historical=False):
    """Keep Gen7 readable during a genuine same-shipping successor qualification."""
    if explicitly_historical:
        return True
    pointer_path = Path(root) / 'evidence/CURRENT-STANDARD-TOKEN.json'
    token = read_json(pointer_path)
    current_values = dict(candidate)
    current_values.update({key: token.get(key) for key in TUPLE_KEYS
                           if key != 'candidateSha256'})
    current = exact_tuple(current_values)
    if current == candidate:
        return False
    require(all(candidate[key] == current[key] for key in
                ('candidateBuildCommit', 'shippingInputIdentity',
                 'releaseFingerprintId', 'candidateSha256'))
            and candidate['repositoryHead'] != current['repositoryHead']
            and candidate['toolingFingerprintId'] != current['toolingFingerprintId'],
            'Generation-7 current token differs outside a same-shipping successor tuple')
    _gen7_token(root, pointer_path, current)
    return True


def _accepted_rebound_v8(root, pointer, current_tuple=None):
    """Validate the immutable Generation-8 append and its exact Gen-7 parent."""
    state = _state(root)
    require(set(pointer) == {'schemaVersion', 'contract', 'generation', 'status',
                             'receiptFile', 'receiptSha256', 'previousPointerSha256',
                             'checkpoint'}
            and pointer.get('schemaVersion') == 8
            and pointer.get('contract') == 'devfleet-accepted-baseline-v8'
            and pointer.get('generation') == 8 and pointer.get('status') == 'ACCEPTED',
            'Generation-8 pointer contract differs')
    filename, previous_hash = pointer.get('receiptFile'), pointer.get('previousPointerSha256')
    require(isinstance(filename, str) and re.fullmatch(r'[0-9a-f]{32}\.json', filename)
            and isinstance(previous_hash, str) and HEX64.fullmatch(previous_hash),
            'Generation-8 lineage reference is malformed')
    previous_path = state / 'history' / (previous_hash + '.json')
    require(previous_path.is_file() and not previous_path.is_symlink()
            and digest(previous_path) == previous_hash,
            'Generation-8 predecessor pointer is absent or changed')
    previous = read_json(previous_path)
    require(previous.get('generation') == 7,
            'Generation-8 predecessor must be the accepted Generation-7 pointer')
    prior = _accepted_rebound_v7(root, previous, historical=True)
    receipt_path = state / 'receipts' / filename
    require(receipt_path.is_file() and not receipt_path.is_symlink()
            and digest(receipt_path) == pointer.get('receiptSha256'),
            'Generation-8 receipt is absent or hash-mismatched')
    receipt = read_json(receipt_path)
    require(receipt.get('schemaVersion') == 8
            and receipt.get('contract') == 'devfleet-baseline-rebind-receipt-v8',
            'Generation-8 receipt contract differs')
    return _gen8_validate(root, pointer, receipt, previous, prior,
                          current_tuple)


def rebind_gen7(root, tuple_path, approval_path, ledger_path, live_path, token_pointer_path):
    """Append a hash-bound Gen7 after genuine Developer qualification, no proof credit."""
    state = _state(root)
    with lock(state / '.adoption.lock'), lock(Path(str(ledger_path) + '.lock')):
        pointer_path = state / 'CURRENT.json'
        previous = read_json(pointer_path)
        require(previous.get('generation') == 6, 'Generation-7 requires accepted Gen6')
        old_receipt = read_json(state / 'receipts' / previous['receiptFile'])
        old_tuple = exact_tuple(old_receipt.get('candidate'))
        prior = _accepted_rebound_v6(root, previous, old_tuple)
        tuple_sha, approval_sha, ledger_sha, live_sha = map(digest,
            (tuple_path, approval_path, ledger_path, live_path))
        new_tuple = exact_tuple(read_json(tuple_path))
        approval = read_json(approval_path)
        require('sourceSha256' not in approval,
                'Generation-7 owner approval may not predeclare a source hash')
        ledger = read_json(ledger_path)
        auth_path = Path((ledger.get('authorization') or {}).get('path', ''))
        require(auth_path.is_file() and not auth_path.is_symlink(),
                'Generation-7 owner authorization source is missing')
        auth_sha = digest(auth_path)
        auth = read_json(auth_path)
        owner_ref = auth.get('ownerAuthorization') or {}
        owner_path = Path(owner_ref.get('path', ''))
        require(owner_path.is_file() and not owner_path.is_symlink(),
                'Generation-7 owner authorization attachment is missing')
        owner_sha = digest(owner_path)
        predecessor_path = Path((ledger.get('predecessors') or [{}])[0].get('path', ''))
        require(predecessor_path.is_file() and not predecessor_path.is_symlink(),
                'Generation-7 causal predecessor source is missing')
        predecessor_sha = digest(predecessor_path)
        failure_paths = {key: Path((auth.get('failureEvidence') or {}).get(key, {}).get('path', ''))
                         for key in ('wrapper', 'proofError', 'cleanup')}
        failure_hashes = {key: digest(path) for key, path in failure_paths.items()}
        token_refs, token_paths = _gen7_token(root, token_pointer_path, new_tuple)
        journal = Path(root).resolve(strict=True) / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Native collision successor journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0, 'Native collision successor journal rejected binding')
        status = json.loads(checked.stdout)
        remaining = {**COLLISION_LIMITS, 'standard-token': 0}
        require(status.get('policyId') == COLLISION_POLICY and status.get('active') is None
                and status.get('attemptCount') == 1 and status.get('remaining') == remaining,
                'Native collision successor does not have one terminal qualification')
        live = read_json(live_path)
        require(timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc')) <= timedelta(minutes=2),
                'Generation-7 native inventory is not fresh')
        provisional = {'previousPointerSha256': digest(pointer_path),
                       'checkpoint': previous['checkpoint']}
        receipt = {'schemaVersion': 7, 'contract': 'devfleet-baseline-rebind-receipt-v7',
                   'receiptId': uuid.uuid4().hex, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': provisional['previousPointerSha256'],
                   'previousReceiptSha256': prior['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': previous['checkpoint'],
                   'approval': {**approval, 'sourceSha256': approval_sha},
                   'approvalSha256': approval_sha,
                   'successorPolicyId': COLLISION_POLICY,
                   'successorLedgerSha256': ledger_sha,
                   'successorAuthorizationSha256': auth_sha,
                   'ownerAuthorizationSha256': owner_sha,
                   'predecessorLedgerSha256': predecessor_sha,
                   'failureEvidenceSha256': failure_hashes,
                   'standardTokenEvidence': token_refs,
                   'finalL1': live['vm'], 'nativeInventorySha256': live_sha}
        # Validate the exact same semantics before any source or pointer write.
        sources = state / 'sources'
        require(all(Path(path).is_file() and not Path(path).is_symlink() for path in
                    (tuple_path, approval_path, ledger_path, live_path, auth_path,
                     predecessor_path, owner_path, *failure_paths.values(), *token_paths)),
                'Generation-7 source path changed before binding')
        require(all(digest(path) == expected for path, expected in
                    ((tuple_path, tuple_sha), (approval_path, approval_sha),
                     (ledger_path, ledger_sha), (live_path, live_sha),
                     (auth_path, auth_sha), (predecessor_path, predecessor_sha),
                     (owner_path, owner_sha),
                     *((failure_paths[key], failure_hashes[key]) for key in failure_paths),
                     *((token_paths[i], token_refs[key]) for i, key in enumerate(
                         ('pointerSha256', 'canonicalSha256', 'rawReportSha256'))))),
                'Generation-7 source changed during binding')
        _gen7_validate_prewrite(root, provisional, receipt, previous, prior,
                                old_tuple, new_tuple, ledger, auth, live,
                                predecessor_sha)
        sources.mkdir(parents=True, exist_ok=True)
        to_freeze = [(approval_path, approval_sha, '.json'),
                     (ledger_path, ledger_sha, '.json'), (live_path, live_sha, '.json'),
                     (auth_path, auth_sha, '.json'), (predecessor_path, predecessor_sha, '.json'),
                     (owner_path, owner_sha, '.txt')]
        to_freeze += [(failure_paths[key], failure_hashes[key], '.json') for key in failure_paths]
        to_freeze += [(token_paths[i], token_refs[key], '.json' if i < 2 else '.txt')
                      for i, key in enumerate(('pointerSha256', 'canonicalSha256', 'rawReportSha256'))]
        for path, sha, ext in to_freeze:
            destination = sources / (sha + ext)
            if destination.exists():
                require(digest(destination) == sha, 'Existing frozen source differs')
            else:
                _write_exclusive(destination, Path(path).read_bytes())
        history = state / 'history'
        history.mkdir(parents=True, exist_ok=True)
        _write_exclusive(history / (provisional['previousPointerSha256'] + '.json'), pointer_path.read_bytes())
        filename = receipt['receiptId'] + '.json'
        receipt_path = state / 'receipts' / filename
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 7, 'contract': 'devfleet-accepted-baseline-v7',
                   'generation': 7, 'status': 'ACCEPTED', 'receiptFile': filename,
                   'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': provisional['previousPointerSha256'],
                   'checkpoint': previous['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


def _gen7_validate_prewrite(root, pointer, receipt, previous, prior,
                            old_tuple, new_tuple, ledger, auth, live, predecessor_sha):
    """Preflight invariants also enforced by the immutable reader."""
    approval = receipt['approval']
    require(all(old_tuple[key] == new_tuple[key] for key in
                ('candidateBuildCommit', 'shippingInputIdentity',
                 'releaseFingerprintId', 'candidateSha256'))
            and old_tuple['repositoryHead'] != new_tuple['repositoryHead']
            and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
            'Generation-7 binding changed shipping or lacks tooling change')
    require(approval.get('schemaVersion') == 7
            and approval.get('contract') == 'devfleet-baseline-rebind-approval-v7'
            and approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('shippingChangeApproved') is False
            and approval.get('previousCandidate') == old_tuple
            and approval.get('candidate') == new_tuple
            and approval.get('replacement') == previous['checkpoint']
            and approval.get('previousReceiptSha256') == prior['receiptSha256']
            and approval.get('successorAuthorizationSha256') == receipt['successorAuthorizationSha256'],
            'Exact generation-7 account-owner approval is absent')
    require((ledger.get('authorization') or {}).get('sha256') == receipt['successorAuthorizationSha256']
            and (ledger.get('predecessors') or [{}])[0].get('sha256') == predecessor_sha
            and receipt['ownerAuthorizationSha256'] == OWNER_AUTH_SHA256
            and (auth.get('ownerAuthorization') or {}).get('sha256') == OWNER_AUTH_SHA256
            and auth.get('schemaVersion') == 1
            and auth.get('kind') == 'DEVFLEET_POST_COLLISION_SUCCESSOR_AUTHORIZATION'
            and auth.get('policyId') == COLLISION_POLICY
            and auth.get('approved') is True and auth.get('approvedBy') == 'ACCOUNT_OWNER'
            and isinstance(auth.get('successorLedgerPath'), str)
            and Path(auth['successorLedgerPath']).resolve() == COLLISION_LEDGER_PATH.resolve()
            and auth.get('previousCandidate') == old_tuple and auth.get('candidate') == new_tuple
            and (auth.get('predecessorSha256') or {}).get('causal1') == COLLISION_PREDECESSOR_SHA256
            and predecessor_sha == COLLISION_PREDECESSOR_SHA256
            and (auth.get('generation6') or {}).get('receiptSha256') == prior['receiptSha256']
            and (auth.get('generation6') or {}).get('checkpoint') == previous['checkpoint']
            and auth.get('limits') == COLLISION_LIMITS
            and all((auth.get('failureEvidence') or {}).get(key, {}).get('sha256') == value
                    for key, value in receipt['failureEvidenceSha256'].items()),
            'Generation-7 successor authorization or collision sources differ')
    predecessor = read_json((ledger.get('predecessors') or [{}])[0]['path'])
    failures = {key: read_json((auth.get('failureEvidence') or {})[key]['path'])
                for key in ('wrapper', 'proofError', 'cleanup')}
    _gen7_collision_failure(predecessor, old_tuple, auth, failures)
    attempts = ledger.get('attempts')
    require(ledger.get('policyId') == COLLISION_POLICY
            and ledger.get('limits') == COLLISION_LIMITS
            and ledger.get('activeRunId') is None
            and isinstance(attempts, list) and len(attempts) == 1
            and attempts[0].get('operation') == 'standard-token'
            and attempts[0].get('state') == 'TERMINAL'
            and attempts[0].get('exitCode') == 0
            and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
            and attempts[0].get('tuple') == new_tuple
            and attempts[0].get('certificationCredit') is False
            and isinstance(attempts[0].get('evidence'), list) and bool(attempts[0]['evidence'])
            and attempts[0].get('runId') != receipt['standardTokenEvidence']['runId'],
            'Generation-7 successor lacks one exact terminal standard token')
    _gen7_outer_inner(attempts[0], Path(root), receipt['standardTokenEvidence'])
    snapshots = live.get('snapshots')
    exact = [x for x in snapshots if isinstance(x, dict) and x.get('name') == NEW_NAME] if isinstance(snapshots, list) else []
    require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
            and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
            and len(exact) == 1 and exact[0].get('id') == prior['id']
            and exact[0].get('vmId') == VM_ID
            and exact[0].get('parentSnapshotId') == OLD_ID,
            'Generation-7 native inventory lacks exact CLEAN-R2 and L1 Off')


def _gen8_frozen_source(state, source_hash, extension):
    require(isinstance(source_hash, str) and HEX64.fullmatch(source_hash),
            'Generation-8 frozen source hash is malformed')
    path = state / 'sources' / (source_hash + extension)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4_000_000
            and digest(path) == source_hash, 'Generation-8 frozen source is missing or changed')
    return path


def _gen8_collect_closure(roots):
    """Hash-pin a bounded recursive closure of JSON path/hash references."""
    pending = [Path(path).absolute() for path in roots]
    queued_paths = set(pending)
    seen_paths, sources = set(), {}
    total_bytes = 0
    while pending:
        path = pending.pop().absolute()
        queued_paths.discard(path)
        require(path not in seen_paths, 'Generation-8 source closure contains a path alias')
        seen_paths.add(path)
        require(path.is_file() and not path.is_symlink() and path.resolve(strict=True) == path,
                'Generation-8 source closure contains an absent, linked or noncanonical file')
        size = path.stat().st_size
        require(size <= 4_000_000, 'Generation-8 source closure member exceeds size limit')
        total_bytes += size
        require(total_bytes <= 32_000_000 and len(seen_paths) <= 512,
                'Generation-8 source closure exceeds bounded size')
        source_hash, extension = digest(path), path.suffix.lower() or '.bin'
        key = (source_hash, extension)
        prior = sources.get(key)
        if prior is not None:
            require(prior.read_bytes() == path.read_bytes(),
                    'Generation-8 equal-hash source collision detected')
        else:
            sources[key] = path
        if extension != '.json':
            continue
        document = read_json(path)
        references = []
        def visit(value):
            if isinstance(value, dict):
                if (isinstance(value.get('path'), str)
                        and isinstance(value.get('sha256'), str)
                        and HEX64.fullmatch(value['sha256'])):
                    references.append((value['path'], value['sha256']))
                for nested in value.values():
                    visit(nested)
            elif isinstance(value, list):
                for nested in value:
                    visit(nested)
        visit(document)
        for raw_path, expected_hash in references:
            referenced = Path(raw_path).absolute()
            require(referenced.is_file() and not referenced.is_symlink()
                    and referenced.resolve(strict=True) == referenced
                    and digest(referenced) == expected_hash,
                    f'Generation-8 referenced source is absent, noncanonical or hash-mismatched: {raw_path}')
            if referenced in seen_paths or referenced in queued_paths:
                continue
            queued_paths.add(referenced)
            pending.append(referenced)
    return [{'sha256': source_hash, 'extension': extension}
            for source_hash, extension in sorted(sources)] , sources


def _gen8_close_frozen_sources(state, source_closure):
    require(isinstance(source_closure, list) and 1 <= len(source_closure) <= 512,
            'Generation-8 source closure manifest is malformed')
    sources = {}
    total_bytes = 0
    for row in source_closure:
        require(isinstance(row, dict) and set(row) == {'sha256', 'extension'}
                and isinstance(row.get('extension'), str)
                and re.fullmatch(r'\.[a-z0-9]{1,8}', row['extension'])
                and isinstance(row.get('sha256'), str) and HEX64.fullmatch(row['sha256']),
                'Generation-8 source closure entry is malformed')
        key = (row['sha256'], row['extension'])
        require(key not in sources, 'Generation-8 source closure repeats an entry')
        path = _gen8_frozen_source(state, row['sha256'], row['extension'])
        total_bytes += path.stat().st_size
        require(total_bytes <= 32_000_000, 'Generation-8 frozen closure exceeds bounded size')
        sources[key] = path
    require(len(sources) == len(source_closure), 'Generation-8 frozen closure is incomplete')
    return sources


def _gen8_validate_frozen_graph(state, source_closure, sources):
    """Require every frozen JSON path/hash reference to have frozen bytes."""
    visited = set()
    pending = [key for key in sources if key[1] == '.json']
    while pending:
        key = pending.pop()
        if key in visited:
            continue
        visited.add(key)
        document = read_json(sources[key])
        def visit(value):
            if isinstance(value, dict):
                if (isinstance(value.get('path'), str)
                        and isinstance(value.get('sha256'), str)
                        and HEX64.fullmatch(value['sha256'])):
                    matched = [source_key for source_key in sources
                               if source_key[0] == value['sha256']]
                    require(bool(matched),
                            'Generation-8 frozen JSON references an unfrozen source')
                    for source_key in matched:
                        if source_key[1] == '.json':
                            pending.append(source_key)
                for nested in value.values():
                    visit(nested)
            elif isinstance(value, list):
                for nested in value:
                    visit(nested)
        visit(document)
    return True


def _gen8_frozen_token(root, receipt, sources, new_tuple, outer_attempt):
    token_ref = receipt.get('standardTokenEvidence')
    require(isinstance(token_ref, dict)
            and set(token_ref) == {'runId', 'pointerSha256', 'canonicalSha256',
                                   'rawReportSha256', 'pointerPath', 'canonicalPath',
                                   'rawReportPath'},
            'Generation-8 frozen Developer token reference is malformed')
    def source(hash_value, extension):
        key = (hash_value, extension)
        require(key in sources, 'Generation-8 token source is not in frozen closure')
        return sources[key]
    pointer_path = source(token_ref['pointerSha256'], '.json')
    canonical_path = source(token_ref['canonicalSha256'], '.json')
    raw_path = source(token_ref['rawReportSha256'], '.txt')
    pointer, token = read_json(pointer_path), read_json(canonical_path)
    require(pointer == token,
            'Generation-8 frozen token pointer and canonical record differ')
    run_id = token_ref.get('runId')
    relative = 'evidence/standard-token/' + str(run_id)
    require(isinstance(run_id, str) and re.fullmatch(r'standard-token-[A-Za-z0-9-]+', run_id)
            and token_ref.get('pointerPath') == 'evidence/CURRENT-STANDARD-TOKEN.json'
            and token_ref.get('canonicalPath') == relative + '/standard-token-evidence.json'
            and token_ref.get('rawReportPath') == relative + '/installer-self-test-raw.txt',
            'Generation-8 frozen token paths or RunId differ')
    require(token.get('runDirectory') == relative
            and token.get('canonicalEvidencePath') == token_ref['canonicalPath']
            and token.get('rawReportPath') == token_ref['rawReportPath'],
            'Generation-8 frozen token document paths differ from its references')
    actual = {key: token.get(key) for key in TUPLE_KEYS if key != 'candidateSha256'}
    identity = token.get('token') or {}
    checks = token.get('requiredChecks')
    require(token.get('schemaVersion') == 1 and token.get('runId') == run_id
            and token.get('status') == 'PASS'
            and token.get('standardNonAdministratorToken') is True
            and token.get('exitCode') == 0 and token.get('residualSelfTestScratchCount') == 0
            and actual == {key: new_tuple[key] for key in TUPLE_KEYS if key != 'candidateSha256'}
            and isinstance(checks, dict) and set(checks) == TOKEN_CHECKS
            and all(value is True for value in checks.values())
            and isinstance(identity, dict)
            and isinstance(identity.get('userName'), str)
            and re.fullmatch(r'[^\\]+\\Developer', identity['userName'], re.IGNORECASE)
            and identity.get('standardNonAdministratorToken') is True
            and identity.get('isAdministratorMember') is False
            and identity.get('isAdministratorEnabled') is False
            and identity.get('isElevated') is False
            and identity.get('integrityLevel') == 'Medium',
            'Generation-8 frozen token is not an exact current-tuple Developer PASS')
    exe, tar = token.get('exe') or {}, token.get('tar') or {}
    require(exe.get('sha256') == new_tuple['candidateSha256']
            and type(exe.get('bytes')) is int and exe['bytes'] > 0
            and isinstance(tar.get('sha256'), str) and HEX64.fullmatch(tar['sha256'])
            and type(tar.get('bytes')) is int and tar['bytes'] > 0,
            'Generation-8 frozen token signed artifacts differ')
    runner = token.get('runner') or {}
    runner_key = (runner.get('sha256'), '.ps1')
    require(runner.get('path') == 'automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1'
            and runner_key in sources, 'Generation-8 token runner source is not frozen')
    raw = raw_path.read_text(encoding='utf-8-sig')
    require(token.get('reportSha256') == digest(raw_path)
            and re.search(r'(?m)^PASS\s*$', raw) is not None
            and 'payload=' + tar['sha256'] in raw,
            'Generation-8 frozen raw token report lacks exact PASS/payload')
    evidence = outer_attempt.get('evidence')
    require(outer_attempt.get('runId') != run_id
            and isinstance(evidence, list)
            and any(isinstance(item, str)
                    and item.replace('\\', '/').endswith(token_ref['canonicalPath'])
                    for item in evidence),
            'Generation-8 charged attempt does not cite its distinct inner token')
    token_instant = instant(token.get('generatedAtUtc'))
    require(_gen7_journal_instant(outer_attempt.get('reservedUtc')) <= token_instant
            <= _gen7_journal_instant(outer_attempt.get('terminalUtc')),
            'Generation-8 token is outside its charged outer attempt')
    return token_ref


def _gen8_validate(root, pointer, receipt, previous, prior, current_tuple=None):
    root, state = Path(root).resolve(strict=True), _state(root)
    require(pointer.get('schemaVersion') == 8
            and pointer.get('contract') == 'devfleet-accepted-baseline-v8'
            and pointer.get('generation') == 8 and pointer.get('status') == 'ACCEPTED'
            and receipt.get('schemaVersion') == 8
            and receipt.get('contract') == 'devfleet-baseline-rebind-receipt-v8'
            and receipt.get('status') == 'REBOUND'
            and receipt.get('certificationCredit') is False
            and receipt.get('secretValuesRecorded') is False,
            'Generation-8 pointer or receipt contract differs')
    require(receipt.get('receiptId') + '.json' == pointer.get('receiptFile')
            and receipt.get('previousPointerSha256') == pointer.get('previousPointerSha256')
            and receipt.get('previousReceiptSha256') == prior.get('receiptSha256')
            and receipt.get('replacement') == previous.get('checkpoint') == pointer.get('checkpoint')
            and receipt.get('successorPolicyId') == HTTP_CLEANUP_POLICY
            and receipt.get('predecessorLedgerSha256') == HTTP_CLEANUP_PREDECESSOR_SHA256
            and pointer.get('checkpoint', {}).get('name') == NEW_NAME
            and pointer.get('checkpoint', {}).get('id') == prior.get('id'),
            'Generation-8 lineage, checkpoint or successor predecessor differs')
    old_tuple = exact_tuple(receipt.get('previousCandidate'))
    new_tuple = exact_tuple(receipt.get('candidate'))
    if current_tuple is not None:
        require(new_tuple == exact_tuple(current_tuple),
                'Generation-8 baseline is bound to another candidate/material tuple')
    require(receipt.get('approvalSha256') == receipt.get('approval', {}).get('sourceSha256')
            and isinstance(receipt.get('approvalSha256'), str)
            and HEX64.fullmatch(receipt['approvalSha256']),
            'Generation-8 approval source link is malformed')
    sources = _gen8_close_frozen_sources(state, receipt.get('sourceClosure'))
    _gen8_validate_frozen_graph(state, receipt['sourceClosure'], sources)
    require((receipt['approvalSha256'], '.json') in sources,
            'Generation-8 frozen approval is absent from source closure')
    approval_source = _gen8_frozen_source(state, receipt['approvalSha256'], '.json')
    approval = read_json(approval_source)
    require('sourceSha256' not in approval
            and {**approval, 'sourceSha256': receipt['approvalSha256']} == receipt['approval'],
            'Generation-8 frozen owner approval differs')
    require(approval.get('schemaVersion') == 8
            and approval.get('contract') == 'devfleet-baseline-rebind-approval-v8'
            and approval.get('decision') == 'APPROVE'
            and approval.get('approvedBy') == 'ACCOUNT_OWNER'
            and approval.get('shippingChangeApproved') is False
            and approval.get('previousCandidate') == old_tuple
            and approval.get('candidate') == new_tuple
            and approval.get('replacement') == previous.get('checkpoint')
            and approval.get('previousReceiptSha256') == prior.get('receiptSha256')
            and approval.get('successorPolicyId') == HTTP_CLEANUP_POLICY
            and approval.get('successorLedgerSha256') == receipt.get('successorLedgerSha256')
            and approval.get('successorAuthorizationSha256') == receipt.get('successorAuthorizationSha256')
            and approval.get('ownerAuthorization', {}).get('sha256') == receipt.get('ownerAuthorizationSha256')
            and all(old_tuple[key] == new_tuple[key] for key in
                    ('candidateBuildCommit', 'shippingInputIdentity',
                     'releaseFingerprintId', 'candidateSha256'))
            and old_tuple['repositoryHead'] != new_tuple['repositoryHead']
            and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
            'Generation-8 owner approval or unchanged shipping tuple differs')
    def source(hash_value, extension='.json'):
        key = (hash_value, extension)
        require(key in sources, 'Generation-8 evidence is absent from frozen source closure')
        return sources[key]
    ledger_hash = receipt.get('successorLedgerSha256')
    auth_hash = receipt.get('successorAuthorizationSha256')
    owner_hash = receipt.get('ownerAuthorizationSha256')
    inventory_hash = receipt.get('nativeInventorySha256')
    require(approval.get('ownerAuthorization', {}).get('sha256') == owner_hash
            and approval.get('publicMainSha') == receipt.get('publicMainSha'),
            'Generation-8 approval public source or owner reference differs')
    ledger = read_json(source(ledger_hash))
    auth = read_json(source(auth_hash))
    owner_source = source(owner_hash, '.txt').read_text(encoding='utf-8-sig')
    live = read_json(source(inventory_hash))
    require(ledger.get('schemaVersion') == 1
            and ledger.get('policyId') == HTTP_CLEANUP_POLICY
            and ledger.get('limits') == HTTP_CLEANUP_LIMITS
            and ledger.get('activeRunId') is None
            and ledger.get('certificationCredit') is False
            and ledger.get('authorization', {}).get('sha256') == auth_hash
            and isinstance(ledger.get('attempts'), list) and len(ledger['attempts']) == 1,
            'Generation-8 frozen successor ledger differs')
    attempt = ledger['attempts'][0]
    require(attempt.get('operation') == 'standard-token'
            and attempt.get('state') == 'TERMINAL'
            and attempt.get('exitCode') == 0
            and attempt.get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
            and attempt.get('tuple') == new_tuple
            and attempt.get('certificationCredit') is False
            and isinstance(attempt.get('evidence'), list) and bool(attempt['evidence']),
            'Generation-8 frozen successor lacks exactly one terminal token PASS')
    require(auth.get('policyId') == HTTP_CLEANUP_POLICY
            and auth.get('approved') is True and auth.get('approvedBy') == 'ACCOUNT_OWNER'
            and auth.get('candidate') == new_tuple
            and auth.get('previousCandidate') == old_tuple
            and auth.get('limits') == HTTP_CLEANUP_LIMITS
            and auth.get('shippingChangeApproved') is False
            and auth.get('publicMainSha') == receipt.get('publicMainSha')
            and auth.get('predecessorSha256') == {'collision1': HTTP_CLEANUP_PREDECESSOR_SHA256}
            and auth.get('generation7', {}).get('receipt', {}).get('sha256') == prior.get('receiptSha256'),
            'Generation-8 frozen successor authorization differs')
    owner_requirements = [HTTP_CLEANUP_POLICY,
                          f'publicMainSha={receipt["publicMainSha"]}',
                          f'predecessorSha256={HTTP_CLEANUP_PREDECESSOR_SHA256}']
    require(all(text in owner_source for text in owner_requirements)
            and all(f'candidate.{key}={value}' in owner_source
                    for key, value in new_tuple.items()),
            'Generation-8 frozen owner source does not bind exact tuple and public main')
    predecessor_rows = ledger.get('predecessors')
    require(isinstance(predecessor_rows, list) and len(predecessor_rows) == 2
            and all(isinstance(row, dict) and row.get('sha256') == HTTP_CLEANUP_PREDECESSOR_SHA256
                    for row in predecessor_rows),
            'Generation-8 frozen successor predecessor references differ')
    require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
            and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
            and receipt.get('finalL1') == live['vm'],
            'Generation-8 frozen inventory does not prove exact L1 Off')
    snapshots = live.get('snapshots')
    exact = [row for row in snapshots if isinstance(row, dict) and row.get('name') == NEW_NAME] if isinstance(snapshots, list) else []
    require(len(exact) == 1 and exact[0].get('id') == prior.get('id')
            and exact[0].get('vmId') == VM_ID and exact[0].get('parentSnapshotId') == OLD_ID,
            'Generation-8 frozen inventory does not prove exact CLEAN-R2')
    token_refs = _gen8_frozen_token(root, receipt, sources, new_tuple, attempt)
    require(receipt.get('standardTokenEvidence') == token_refs,
            'Generation-8 token reference differs')
    return {**prior, 'receiptSha256': pointer['receiptSha256'],
            'receiptFile': pointer['receiptFile'],
            'previousReceiptSha256': prior['receiptSha256'], 'generation': 8,
            'candidate': new_tuple}


def rebind_gen8(root, tuple_path, approval_path, ledger_path, live_path,
                token_pointer_path):
    """Append Gen-8 from exact accepted Gen-7, freezing token and journal evidence."""
    root = Path(root).resolve(strict=True)
    state = _state(root)
    ledger_input = Path(ledger_path).absolute()
    require(not ledger_input.is_symlink()
            and ledger_input == HTTP_CLEANUP_LEDGER_PATH.absolute()
            and ledger_input.resolve(strict=True) == HTTP_CLEANUP_LEDGER_PATH.resolve(),
            'Generation-8 successor ledger path is not the canonical authorized ledger')
    with lock(state / '.adoption.lock'), lock(Path(str(ledger_path) + '.lock')):
        pointer_path = state / 'CURRENT.json'
        previous = read_json(pointer_path)
        require(previous.get('generation') == 7,
                'Generation-8 requires the exact currently accepted Generation-7 parent')
        prior = _accepted_rebound_v7(root, previous, historical=True)
        old_tuple = exact_tuple(read_json(state / 'receipts' / previous['receiptFile']).get('candidate'))
        tuple_sha, approval_sha, ledger_sha, live_sha = map(digest,
            (tuple_path, approval_path, ledger_path, live_path))
        new_tuple = exact_tuple(read_json(tuple_path))
        approval = read_json(approval_path)
        ledger = read_json(ledger_path)
        require('sourceSha256' not in approval,
                'Generation-8 owner approval may not predeclare its source hash')
        auth_path = Path((ledger.get('authorization') or {}).get('path', ''))
        require(auth_path.is_file() and not auth_path.is_symlink(),
                'Generation-8 successor authorization source is missing')
        auth_sha = digest(auth_path)
        auth = read_json(auth_path)
        owner_ref = auth.get('ownerAuthorization') or {}
        owner_path = Path(owner_ref.get('path', ''))
        require(owner_path.is_file() and not owner_path.is_symlink()
                and digest(owner_path) == owner_ref.get('sha256'),
                'Generation-8 successor owner authorization source is missing or changed')
        owner_sha = digest(owner_path)
        predecessor_rows = ledger.get('predecessors')
        require(isinstance(predecessor_rows, list) and len(predecessor_rows) == 2,
                'Generation-8 successor predecessor snapshot/live references are missing')
        predecessor_paths = [Path(row.get('path', '')) for row in predecessor_rows]
        require(all(path.is_file() and not path.is_symlink() for path in predecessor_paths),
                'Generation-8 exact COLLISION-1 snapshot/live sources are missing')
        predecessor_hashes = [digest(path) for path in predecessor_paths]
        require(predecessor_hashes == [HTTP_CLEANUP_PREDECESSOR_SHA256] * 2
                and predecessor_hashes[0] == predecessor_hashes[1],
                'Generation-8 successor is not bound to exact terminal COLLISION-1')
        token_refs, token_paths = _gen7_token(root, token_pointer_path, new_tuple)
        journal = root / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Generation-8 successor journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0,
                'HTTP-CLEANUP-1 journal rejected Generation-8 binding')
        journal_status = json.loads(checked.stdout)
        attempts = ledger.get('attempts')
        require(journal_status.get('policyId') == HTTP_CLEANUP_POLICY
                and journal_status.get('active') is None
                and journal_status.get('attemptCount') == 1
                and journal_status.get('remaining') ==
                    {**HTTP_CLEANUP_LIMITS, 'standard-token': 0}
                and ledger.get('activeRunId') is None
                and isinstance(attempts, list) and len(attempts) == 1
                and attempts[0].get('operation') == 'standard-token'
                and attempts[0].get('state') == 'TERMINAL'
                and attempts[0].get('exitCode') == 0
                and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
                and attempts[0].get('tuple') == new_tuple,
                'Generation-8 successor lacks one exact current-tuple token PASS')
        live = read_json(live_path)
        require(timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc'))
                <= timedelta(minutes=2),
                'Generation-8 exact L1 inventory is not fresh')
        require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'},
                'Generation-8 live inventory does not prove exact L1 Off')
        snapshots = live.get('snapshots')
        exact = [row for row in snapshots if isinstance(row, dict) and row.get('name') == NEW_NAME] if isinstance(snapshots, list) else []
        require(len(exact) == 1 and exact[0].get('id') == prior.get('id')
                and exact[0].get('vmId') == VM_ID and exact[0].get('parentSnapshotId') == OLD_ID,
                'Generation-8 live inventory does not prove exact CLEAN-R2')
        require(approval.get('schemaVersion') == 8
                and approval.get('contract') == 'devfleet-baseline-rebind-approval-v8'
                and approval.get('decision') == 'APPROVE'
                and approval.get('approvedBy') == 'ACCOUNT_OWNER'
                and approval.get('shippingChangeApproved') is False
                and approval.get('previousCandidate') == old_tuple
                and approval.get('candidate') == new_tuple
                and approval.get('replacement') == previous.get('checkpoint')
                and approval.get('previousReceiptSha256') == prior.get('receiptSha256')
                and approval.get('successorPolicyId') == HTTP_CLEANUP_POLICY
                and approval.get('successorLedgerPath') == str(Path(ledger_path).resolve())
                and approval.get('successorLedgerSha256') == ledger_sha
                and approval.get('successorAuthorizationSha256') == auth_sha
                and approval.get('ownerAuthorization') == {'path': str(owner_path), 'sha256': owner_sha}
                and approval.get('publicMainSha') == auth.get('publicMainSha'),
                'Exact Generation-8 account-owner approval is absent or mismatched')
        require(auth.get('policyId') == HTTP_CLEANUP_POLICY
                and auth.get('approved') is True and auth.get('approvedBy') == 'ACCOUNT_OWNER'
                and auth.get('candidate') == new_tuple and auth.get('previousCandidate') == old_tuple
                and auth.get('limits') == HTTP_CLEANUP_LIMITS
                and auth.get('shippingChangeApproved') is False
                and auth.get('generation7', {}).get('pointer', {}).get('sha256') == digest(pointer_path)
                and auth.get('generation7', {}).get('receipt', {}).get('sha256') == prior.get('receiptSha256'),
                'HTTP-CLEANUP-1 authorization differs from accepted Gen-7/current tuple')
        require(all(old_tuple[key] == new_tuple[key] for key in
                    ('candidateBuildCommit', 'shippingInputIdentity',
                     'releaseFingerprintId', 'candidateSha256'))
                and old_tuple['repositoryHead'] != new_tuple['repositoryHead']
                and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
                'Generation-8 binding changed signed shipping or lacks tuple changes')
        approval_owner_text = owner_path.read_text(encoding='utf-8-sig')
        require(all(f'candidate.{key}={value}' in approval_owner_text
                    for key, value in new_tuple.items())
                and f'publicMainSha={auth["publicMainSha"]}' in approval_owner_text,
                'Generation-8 owner authorization does not bind public main and exact tuple')
        provisional = {'previousPointerSha256': digest(pointer_path),
                       'checkpoint': previous['checkpoint']}
        closure_roots = [tuple_path, approval_path, ledger_path, live_path,
                         auth_path, owner_path, *predecessor_paths, *token_paths]
        source_closure, source_paths = _gen8_collect_closure(closure_roots)
        receipt = {'schemaVersion': 8, 'contract': 'devfleet-baseline-rebind-receipt-v8',
                   'receiptId': uuid.uuid4().hex, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': provisional['previousPointerSha256'],
                   'previousReceiptSha256': prior['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': previous['checkpoint'],
                   'approval': {**approval, 'sourceSha256': approval_sha},
                   'approvalSha256': approval_sha,
                   'successorPolicyId': HTTP_CLEANUP_POLICY,
                   'successorLedgerSha256': ledger_sha,
                   'successorAuthorizationSha256': auth_sha,
                   'ownerAuthorizationSha256': owner_sha,
                   'predecessorLedgerSha256': HTTP_CLEANUP_PREDECESSOR_SHA256,
                   'nativeInventorySha256': live_sha,
                   'finalL1': live['vm'], 'publicMainSha': auth['publicMainSha'],
                   'standardTokenEvidence': token_refs,
                   'sourceClosure': source_closure}
        # Recheck every input before the immutable sources or pointer are written.
        require(all(digest(path) == expected for path, expected in
                    ((tuple_path, tuple_sha), (approval_path, approval_sha),
                     (ledger_path, ledger_sha), (live_path, live_sha),
                     (auth_path, auth_sha), (owner_path, owner_sha),
                     *((path, expected) for path, expected in zip(predecessor_paths, predecessor_hashes)),
                     *((path, token_refs[key]) for path, key in zip(
                         token_paths, ('pointerSha256', 'canonicalSha256', 'rawReportSha256'))))),
                'Generation-8 source changed during binding')
        sources_dir = state / 'sources'
        sources_dir.mkdir(parents=True, exist_ok=True)
        for key, path in source_paths.items():
            destination = sources_dir / (key[0] + key[1])
            if destination.exists():
                require(digest(destination) == key[0],
                        'Existing Generation-8 frozen source differs')
            else:
                _write_exclusive(destination, path.read_bytes())
        _gen8_validate(root, {**provisional, 'schemaVersion': 8,
                              'contract': 'devfleet-accepted-baseline-v8',
                              'generation': 8, 'status': 'ACCEPTED',
                              'receiptFile': receipt['receiptId'] + '.json',
                              'receiptSha256': '0' * 64},
                       receipt, previous, prior)
        history = state / 'history'
        history.mkdir(parents=True, exist_ok=True)
        _write_exclusive(history / (provisional['previousPointerSha256'] + '.json'),
                         pointer_path.read_bytes())
        receipt_path = state / 'receipts' / (receipt['receiptId'] + '.json')
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 8, 'contract': 'devfleet-accepted-baseline-v8',
                   'generation': 8, 'status': 'ACCEPTED',
                   'receiptFile': receipt_path.name, 'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': provisional['previousPointerSha256'],
                   'checkpoint': previous['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


def _validate_v4_successor(ledger, new_tuple, journal_status):
    """Require the prospective repair-3 journal and immutable signed-output receipt."""
    remaining = {'standard-token': 0, 'diagnostic': 1, 'laptop-proof': 1,
                 'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0,
                 'build-sign': 0}
    attempts = ledger.get('attempts') or []
    require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-3'
            and journal_status.get('policyId') == ledger['policyId']
            and ledger.get('activeRunId') is None and journal_status.get('active') is None
            and journal_status.get('attemptCount') == 1
            and journal_status.get('remaining') == remaining
            and isinstance(attempts, list) and len(attempts) == 1
            and [a.get('operation') for a in attempts] == ['standard-token']
            and all(a.get('state') == 'TERMINAL' and a.get('exitCode') == 0
                    and a.get('certificationCredit') is False
                    and isinstance(a.get('evidence'), list) and a['evidence'] for a in attempts)
            and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
            and attempts[0].get('tuple') == new_tuple,
            'Native third repair successor lacks exact terminal Developer qualification')
    artifact = ledger.get('artifactReceipt') or {}
    require(set(artifact) == {'path', 'sha256'} and isinstance(artifact.get('path'), str)
            and HEX64.fullmatch(str(artifact.get('sha256', ''))),
            'Native third repair successor artifact receipt binding is missing')
    artifact_path = Path(artifact['path']).resolve(strict=True)
    require(digest(artifact_path) == artifact['sha256'],
            'Native third repair successor artifact receipt hash differs')
    inspected = read_json(artifact_path)
    require(inspected.get('schemaVersion') == 1
            and inspected.get('contract') == 'devfleet-signed-build-output-inspection-v1'
            and inspected.get('status') == 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION'
            and inspected.get('certificationCredit') is False
            and inspected.get('repositoryHead') == new_tuple['candidateBuildCommit']
            and inspected.get('shippingInputIdentity') == new_tuple['shippingInputIdentity']
            and inspected.get('signatureStatus') == 'Valid'
            and inspected.get('publicPromotionAllowed') is False
            and inspected.get('publicPublisherTrust') is False,
            'Native third repair successor artifact receipt differs')
    artifact_rows = inspected.get('artifacts')
    require(isinstance(artifact_rows, list) and len(artifact_rows) == 4
            and {row.get('name') for row in artifact_rows} ==
                {'exe', 'tar', 'portable', 'installerSource'}
            and next(row for row in artifact_rows if row.get('name') == 'exe').get('sha256') ==
                new_tuple['candidateSha256'],
            'Native third repair successor artifact set differs')
    return artifact


def rebind_gen4(root, tuple_path, approval_path, ledger_path, live_path):
    """Append one separately approved new-shipping binding to accepted generation 3."""
    state = _state(root)
    with lock(state / '.adoption.lock'), lock(Path(str(ledger_path) + '.lock')):
        pointer_path = state / 'CURRENT.json'
        pointer = read_json(pointer_path)
        require(pointer.get('generation') == 3,
                'Generation-4 binding requires accepted generation 3')
        old_receipt = read_json(state / 'receipts' / pointer['receiptFile'])
        old_tuple = exact_tuple(old_receipt.get('candidate'))
        prior = _accepted_rebound_v3(root, pointer, old_tuple)
        new_tuple = exact_tuple(read_json(tuple_path))
        for key in TUPLE_KEYS:
            require(old_tuple[key] != new_tuple[key],
                    'Generation-4 binding requires a distinct signed candidate: ' + key)
        approval = read_json(approval_path)
        require(approval.get('schemaVersion') == 3
                and approval.get('contract') == 'devfleet-baseline-rebind-approval-v3'
                and approval.get('decision') == 'APPROVE'
                and approval.get('approvedBy') == 'ACCOUNT_OWNER'
                and approval.get('shippingChangeApproved') is True
                and approval.get('previousCandidate') == old_tuple
                and approval.get('candidate') == new_tuple
                and approval.get('replacement') == pointer['checkpoint']
                and approval.get('previousReceiptSha256') == prior['receiptSha256'],
                'Exact generation-4 account-owner approval is absent')
        ledger = read_json(ledger_path)
        journal = Path(root).resolve(strict=True) / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Native second repair successor journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0, 'Native second repair successor journal rejected binding')
        journal_status = json.loads(checked.stdout)
        artifact = _validate_v4_successor(ledger, new_tuple, journal_status)
        inventory_sha_before = digest(live_path)
        live = read_json(live_path)
        named = [x for x in live.get('snapshots', [])
                 if isinstance(x, dict) and x.get('name') == NEW_NAME]
        require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
                and timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc')) <= timedelta(minutes=2)
                and len(named) == 1 and named[0].get('id') == prior['id']
                and named[0].get('vmId') == VM_ID
                and named[0].get('parentSnapshotId') == OLD_ID,
                'Exact accepted checkpoint is not present with L1 Off')
        ledger_bytes = Path(ledger_path).read_bytes()
        inventory_bytes = Path(live_path).read_bytes()
        ledger_sha = hashlib.sha256(ledger_bytes).hexdigest()
        inventory_sha = hashlib.sha256(inventory_bytes).hexdigest()
        require(inventory_sha == inventory_sha_before,
                'Native inventory changed during generation-4 binding')
        sources = state / 'sources'
        sources.mkdir(parents=True, exist_ok=True)
        _write_exclusive(sources / (ledger_sha + '.json'), ledger_bytes)
        _write_exclusive(sources / (inventory_sha + '.json'), inventory_bytes)
        _write_exclusive(sources / (artifact['sha256'] + '.json'), Path(artifact['path']).read_bytes())
        previous_hash = digest(pointer_path)
        history = state / 'history'
        history.mkdir(parents=True, exist_ok=True)
        _write_exclusive(history / (previous_hash + '.json'), pointer_path.read_bytes())
        receipt_id = uuid.uuid4().hex
        receipt = {'schemaVersion': 4, 'contract': 'devfleet-baseline-rebind-receipt-v4',
                   'receiptId': receipt_id, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': previous_hash,
                   'previousReceiptSha256': prior['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': pointer['checkpoint'],
                   'approval': {**approval, 'sourceSha256': digest(approval_path)},
                   'approvalSha256': digest(approval_path),
                   'successorPolicyId': ledger['policyId'],
                   'successorLedgerSha256': ledger_sha,
                   'artifactReceiptSha256': artifact['sha256'],
                   'finalL1': live['vm'], 'nativeInventorySha256': inventory_sha}
        filename = receipt_id + '.json'
        receipt_path = state / 'receipts' / filename
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 4, 'contract': 'devfleet-accepted-baseline-v4',
                   'generation': 4, 'status': 'ACCEPTED',
                   'receiptFile': filename, 'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': pointer['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


def rebind_gen3(root, tuple_path, approval_path, ledger_path, live_path):
    """Append one separately approved exact-tuple binding to accepted generation 2."""
    state = _state(root)
    # Journal writers take ledger.json.lock. Hold that same lock until the
    # immutable qualification snapshot and accepted pointer are committed.
    with lock(state / '.adoption.lock'), lock(Path(str(ledger_path) + '.lock')):
        pointer_path = state / 'CURRENT.json'
        pointer = read_json(pointer_path)
        require(pointer.get('generation') == 2,
                'Generation-3 binding requires accepted generation 2')
        old_receipt = read_json(state / 'receipts' / pointer['receiptFile'])
        old_tuple = exact_tuple(old_receipt.get('candidate'))
        prior = _accepted_rebound_baseline(root, pointer, old_tuple)
        new_tuple = exact_tuple(read_json(tuple_path))
        for key in ('candidateBuildCommit', 'shippingInputIdentity',
                    'releaseFingerprintId', 'candidateSha256'):
            require(old_tuple[key] == new_tuple[key],
                    'Generation-3 binding changed signed shipping identity: ' + key)
        require(old_tuple['repositoryHead'] != new_tuple['repositoryHead']
                and old_tuple['toolingFingerprintId'] != new_tuple['toolingFingerprintId'],
                'Generation-3 binding requires changed HEAD and tooling identity')
        approval = read_json(approval_path)
        require(approval.get('schemaVersion') == 2
                and approval.get('contract') == 'devfleet-baseline-rebind-approval-v2'
                and approval.get('decision') == 'APPROVE'
                and approval.get('approvedBy') == 'ACCOUNT_OWNER'
                and approval.get('candidate') == new_tuple
                and approval.get('replacement') == pointer['checkpoint']
                and approval.get('previousReceiptSha256') == prior['receiptSha256'],
                'Exact generation-3 account-owner approval is absent')
        ledger = read_json(ledger_path)
        journal = Path(root).resolve(strict=True) / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        require(journal.is_file(), 'Native repair successor journal is absent')
        checked = subprocess.run([sys.executable, str(journal), 'status', '--ledger',
                                  str(Path(ledger_path).resolve(strict=True))],
                                 text=True, capture_output=True, timeout=20)
        require(checked.returncode == 0, 'Native repair successor journal rejected binding')
        journal_status = json.loads(checked.stdout)
        required = {'standard-token': 0, 'diagnostic': 1, 'laptop-proof': 1,
                    'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0,
                    'build-sign': 0}
        attempts = ledger.get('attempts') or []
        require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-1'
                and journal_status.get('policyId') == ledger['policyId']
                and ledger.get('activeRunId') is None
                and journal_status.get('active') is None
                and journal_status.get('attemptCount') == 1
                and journal_status.get('remaining') == required
                and isinstance(attempts, list) and len(attempts) == 1
                and attempts[0].get('operation') == 'standard-token'
                and attempts[0].get('state') == 'TERMINAL'
                and attempts[0].get('exitCode') == 0
                and attempts[0].get('classification') == 'PASS_NATIVE_STANDARD_TOKEN'
                and attempts[0].get('tuple') == new_tuple
                and attempts[0].get('certificationCredit') is False
                and isinstance(attempts[0].get('evidence'), list)
                and len(attempts[0]['evidence']) >= 1,
                'Native repair successor lacks exact terminal Developer qualification')
        inventory_sha_before = digest(live_path)
        live = read_json(live_path)
        named = [x for x in live.get('snapshots', [])
                 if isinstance(x, dict) and x.get('name') == NEW_NAME]
        require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'}
                and timedelta(seconds=0) <= datetime.now(timezone.utc) - instant(live.get('observedUtc')) <= timedelta(minutes=2)
                and len(named) == 1 and named[0].get('id') == prior['id']
                and named[0].get('vmId') == VM_ID
                and named[0].get('parentSnapshotId') == OLD_ID,
                'Exact accepted checkpoint is not present with L1 Off')
        ledger_bytes = Path(ledger_path).read_bytes()
        inventory_bytes = Path(live_path).read_bytes()
        ledger_sha = hashlib.sha256(ledger_bytes).hexdigest()
        inventory_sha = hashlib.sha256(inventory_bytes).hexdigest()
        require(inventory_sha == inventory_sha_before,
                'Native inventory changed during generation-3 binding')
        sources_dir = state / 'sources'
        sources_dir.mkdir(parents=True, exist_ok=True)
        _write_exclusive(sources_dir / (ledger_sha + '.json'), ledger_bytes)
        _write_exclusive(sources_dir / (inventory_sha + '.json'), inventory_bytes)
        previous_hash = digest(pointer_path)
        history_dir = state / 'history'
        history_dir.mkdir(parents=True, exist_ok=True)
        _write_exclusive(history_dir / (previous_hash + '.json'), pointer_path.read_bytes())
        receipt_id = uuid.uuid4().hex
        receipt = {'schemaVersion': 3, 'contract': 'devfleet-baseline-rebind-receipt-v3',
                   'receiptId': receipt_id, 'status': 'REBOUND',
                   'reboundUtc': datetime.now(timezone.utc).isoformat(),
                   'certificationCredit': False, 'secretValuesRecorded': False,
                   'previousPointerSha256': previous_hash,
                   'previousReceiptSha256': prior['receiptSha256'],
                   'previousCandidate': old_tuple, 'candidate': new_tuple,
                   'replacement': pointer['checkpoint'],
                   'approval': {**approval, 'sourceSha256': digest(approval_path)},
                   'approvalSha256': digest(approval_path),
                   'successorPolicyId': ledger['policyId'],
                   'successorLedgerSha256': ledger_sha,
                   'finalL1': live['vm'], 'nativeInventorySha256': inventory_sha}
        filename = receipt_id + '.json'
        receipt_path = state / 'receipts' / filename
        _write_exclusive(receipt_path, _json_bytes(receipt))
        current = {'schemaVersion': 3, 'contract': 'devfleet-accepted-baseline-v3',
                   'generation': 3, 'status': 'ACCEPTED',
                   'receiptFile': filename, 'receiptSha256': digest(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': pointer['checkpoint']}
        _atomic_replace(pointer_path, _json_bytes(current))
        return accepted_baseline(root, new_tuple)


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
    binding3 = sub.add_parser('rebind-gen3')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding3.add_argument('--' + flag, required=True)
    binding4 = sub.add_parser('rebind-gen4')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding4.add_argument('--' + flag, required=True)
    binding5 = sub.add_parser('rebind-gen5')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding5.add_argument('--' + flag, required=True)
    binding6 = sub.add_parser('rebind-gen6')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding6.add_argument('--' + flag, required=True)
    binding7 = sub.add_parser('rebind-gen7')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live', 'token-pointer'):
        binding7.add_argument('--' + flag, required=True)
    binding8 = sub.add_parser('rebind-gen8')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live', 'token-pointer'):
        binding8.add_argument('--' + flag, required=True)
    args = parser.parse_args()
    if args.command == 'inspect':
        value = accepted_baseline(args.root, read_json(args.tuple) if args.tuple else None)
    elif args.command == 'adopt':
        value = adopt(args.root, args.proposal, args.approval, args.auth, args.live, args.tuple,
                      args.ledger)
    elif args.command == 'rebind':
        value = rebind(args.root, args.tuple, args.approval, args.ledger, args.live)
    elif args.command == 'rebind-gen4':
        value = rebind_gen4(args.root, args.tuple, args.approval, args.ledger, args.live)
    elif args.command == 'rebind-gen6':
        value = rebind_gen6(args.root, args.tuple, args.approval, args.ledger, args.live)
    elif args.command == 'rebind-gen7':
        value = rebind_gen7(args.root, args.tuple, args.approval, args.ledger,
                            args.live, args.token_pointer)
    elif args.command == 'rebind-gen8':
        value = rebind_gen8(args.root, args.tuple, args.approval, args.ledger,
                            args.live, args.token_pointer)
    elif args.command == 'rebind-gen5':
        value = rebind_gen5(args.root, args.tuple, args.approval, args.ledger, args.live)
    else:
        value = rebind_gen3(args.root, args.tuple, args.approval, args.ledger, args.live)
    print(json.dumps(value, indent=2))


if __name__ == '__main__': main()
