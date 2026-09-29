# DevFleet source part 123

Full-source UTF-8 byte interval [5673000, 5719500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: aaf412fa3cc3fd9dc3ce86e918d0fd72854dda9f1e8c61d0ea4dba73f6e15ec2

<!-- BEGIN SOURCE SLICE -->
ce5cfb5a361966a8eeb4ea8d6f2035d96816162edd89",
      "bytes": 731,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/proof4-fallback-qualified.log",
      "destination": "astra-m6-local-20260907/proof4-fallback-qualified.log",
      "sha256": "7921597163373bb9c5c83ddb0d2c0a911bfcbeee2622699e20a42100d5cce78a",
      "bytes": 1197,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/proof4-fallback-ps51.json",
      "destination": "astra-m6-local-20260907/proof4-fallback-ps51.json",
      "sha256": "571636c2f860a92c8a79181eafd16e7ce4a690b1c847c67b1c2fb709224632d9",
      "bytes": 1323,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/proof4-fallback-ps51.log",
      "destination": "astra-m6-local-20260907/proof4-fallback-ps51.log",
      "sha256": "63cb82b29bedd078c2269e3a89150d33e90e1ed013bba1453388d35280b20823",
      "bytes": 48,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/proof4-observer-final.log",
      "destination": "astra-m6-local-20260907/proof4-observer-final.log",
      "sha256": "0402345cc61c9c97a741366cf4e5e00f8b58969b34a149e47ef3c24119242362",
      "bytes": 2936,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/proof4-harness-frozen.log",
      "destination": "astra-m6-local-20260907/proof4-harness-frozen.log",
      "sha256": "1952d06f06c049bb4a62690ec1a4b24c0f57b01942758567c352ba251e836272",
      "bytes": 973,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/proof4-integrity-final.log",
      "destination": "astra-m6-local-20260907/proof4-integrity-final.log",
      "sha256": "05f60387e5348038a7801b108b88a931f6a186da4986154281dbc958029d35b3",
      "bytes": 61,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/qualify-proof4-corrections.py",
      "destination": "astra-m6-local-20260907/qualify-proof4-corrections.py",
      "sha256": "bf2e5bff4917ad0ec3754187592d5df6d9f4aa664a5e0769d6704b3fd2322f34",
      "bytes": 6026,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/proof4-corrections-qualification.json",
      "destination": "astra-m6-local-20260907/proof4-corrections-qualification.json",
      "sha256": "ec1d0408a925190ac66d8437ee2f1a2a0f4a23091a3ad1210a06b699835e78c1",
      "bytes": 3419,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/before-proof4-closeout-YOLO-RESUME-HANDOFF.json",
      "destination": "astra-m6-local-20260907/before-proof4-closeout-YOLO-RESUME-HANDOFF.json",
      "sha256": "8dd1340a6e43a2d829ae89efc4d2e6f7286511b55f5aefc31fa98baf98d77499",
      "bytes": 5973,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/before-proof4-closeout-YOLO-RESUME-HANDOFF.md",
      "destination": "astra-m6-local-20260907/before-proof4-closeout-YOLO-RESUME-HANDOFF.md",
      "sha256": "7e7294d6cce8a378203baffdad0b85504f578ed5061d303629234b040bb9cc0a",
      "bytes": 2959,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    },
    {
      "source": "audit/automation-harness/astra-m6-local-20260907/before-proof4-closeout-SOL-HELPER-ALLOCATION-LEDGER.json",
      "destination": "astra-m6-local-20260907/before-proof4-closeout-SOL-HELPER-ALLOCATION-LEDGER.json",
      "sha256": "135b4a557d385fd779e4e729e2965f4f8248d6a357a8e93a1494a339bb04c7b5",
      "bytes": 6135,
      "kind": "causal-failure-or-local-qualification-no-proof-credit"
    }
  ]
}

```


## FILE: tools/audit-test-manifest.json

SHA256: d4541110787db1c96ce03696393a5eb202d8c85ac6a076b2c855bf31ef594f5f | Bytes: 1306 | Git mode: 100644

```
{
  "schemaVersion": 1,
  "entrypoint": "release-tooling/run_portable_audit_tests.py",
  "pathAuthority": "release-tooling/audit_bundle_paths.py",
  "portableTests": [
    "source/tests/test_dependency_advisories.py",
    "source/tests/test_release_fingerprint.py",
    "source/tests/test_posix_zip_writer.py",
    "source/tests/test_audit_coherence.py"
  ],
  "categories": {
    "requiresHistoricalEvidence": ["**/test_failed_attempt_freeze.py"],
    "requiresReleaseBinary": ["source/tests/test_installer_self_cleanup.py", "source/tests/test_verify_package_watchdog.py"],
    "requiresPowerShell": ["source/tests/test_hardening8_windows_integrations.py", "source/tests/test_migration_integration.py"],
    "windowsOnly": ["source/tests/test_host_agent_integration.py", "source/tests/test_v122_lifecycle_archive.py"],
    "portable": ["source/tests/test_*.py"]
  },
  "excludedArtifacts": [
    "historical failed-attempt evidence",
    "compiled release binaries",
    "nested release archives",
    "original repository virtual-environment paths",
    "VM images and credentials"
  ],
  "policy": {
    "pythonInterpreter": "sys.executable",
    "workingDirectory": "extracted bundle root",
    "unknownClassification": "FAIL",
    "excludedArtifactHandling": "SKIP with machine-readable reason"
  }
}

```


## FILE: tools/audit_bundle_paths.py

SHA256: c1c886fba4c84706dd0e624e08e71d398af92298e48398f1851f84179a0b77d8 | Bytes: 1179 | Git mode: 100644

```
"""Canonical repository versus extracted-audit-bundle path resolution."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BundleLayout:
    bundle_root: Path
    source_root: Path
    installer_source_root: Path
    release_tooling_root: Path
    release_e2e_root: Path


def resolve_bundle_layout(anchor: Path) -> BundleLayout:
    anchor = anchor.resolve()
    for candidate in (anchor, *anchor.parents):
        source_root = candidate / "source"
        installer_source_root = candidate / "installer-source"
        release_tooling_root = candidate / "release-tooling"
        if not release_tooling_root.is_dir():
            release_tooling_root = candidate / "tools"
        release_e2e_root = candidate / "automation" / "release-e2e"
        if source_root.is_dir() and installer_source_root.is_dir() and release_tooling_root.is_dir() and release_e2e_root.is_dir():
            return BundleLayout(candidate, source_root, installer_source_root, release_tooling_root, release_e2e_root)
    raise AssertionError(f"Could not identify a repository or canonical audit bundle root from {anchor}")

```


## FILE: tools/baseline_lineage.py

SHA256: b936559c05356ebc51e0cb797d697e015043b0aed169a6c3a8e4565482a4b0bc | Bytes: 75315 | Git mode: 100644

```
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


def _validate_v4_successor(ledger, new_tuple, journal_status):
    """Require the prospective repair-3 journal and immutable signed-output receipt."""
    re