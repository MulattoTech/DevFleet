"""Strict post-cleanup release-bundle gate (release tooling only).

The candidate-bound source validator intentionally remains byte-identified.
This validator adds current proof, terminal-state, and post-cleanup authority
requirements without changing shipping inputs.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile
import stat
from pathlib import Path, PurePosixPath

HISTORICAL_CANDIDATE = "2739e0366d070285e44b4fc764ef9247d40b2f94"
HISTORICAL_PROVENANCE = "f334a6eff999287b170fdbd9b6a31c3ef24a6119"
HISTORICAL_SHIPPING_IDENTITY = "daa30ef9f521a47fedb4bacce91e3440c20e1a8f05543b4d5e823e5c3541e64e"
HISTORICAL_RAW_GIT_SHIPPING_IDENTITY = "cdabf0791016282b1dc116c2e0d407718e7d7249d93935f90cc681afd737e92e"
HISTORICAL_RELEASE_FINGERPRINT = "80c8b88c2f2ec828f5ab0f9713d63fa3f4cc4cbad7c382aa2f154f3196c3de84"
FAILED_ATTEMPT_SNAPSHOT = "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
FAILED_ATTEMPT_BLOCKER = "REPLACEMENT_CANDIDATE_BINDING_MISMATCH"
FAILED_ATTEMPT_CURRENT_RECORDS = {
    "evidence/CURRENT-PROOF.json",
    "audit/attemptedReplacementCandidate.json",
    "audit/candidateBindingFailure.json",
}
FAILED_ATTEMPT_INVENTORY_FILES = {"EVIDENCE-MODES.json", "EVIDENCE-SHA256SUMS.txt"}
AUTHORIZED_SHIPPING_PATHS = {
    "installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs",
    "installer-source/DevFleet.Setup/Services/InstallerServices.cs",
    "installer-source/DevFleet.Setup.Tests/Program.cs",
    "source/tools/validate_audit_coherence.py",
    "source/tools/validate_ai_audit_bundle.py",
    "source/tests/test_audit_coherence.py",
    "source/windows/DevFleet.Common.psm1",
}

REQUIRED = {
    "AUDIT-MANIFEST.json", "CURRENT-CANDIDATE.json", "finalization-state.json",
    "outputs/final-artifact-hashes.json", "evidence/CURRENT-STATUS.json",
    "outputs/dependency-advisory-gate.json", "outputs/independent-osv-reconciliation.json",
    "evidence/CURRENT-GATES.json", "evidence/CURRENT-PROOF.json",
    "evidence/FULLRELEASE-SUMMARY.json", "audit/CURRENT-HANDOFF.json",
    "evidence/l1-terminal-state.json", "evidence/l2-terminal-state.json",
    "evidence/current-fullrelease/run-state.json",
    "evidence/current-fullrelease/fullrelease-phase-records.json",
    "evidence/current-fullrelease/final-cleanup.json",
    "evidence/current-fullrelease/post-cleanup-finalization.json",
    "evidence/current-fullrelease/real-use-acceptance-binding.json",
    "evidence/current-fullrelease/real-use-acceptance-prepare.json",
    "evidence/current-fullrelease/real-use-acceptance-report.json",
    "evidence/current-fullrelease/real-use-acceptance-evidence.json",
    "evidence/FINAL-ACCEPTANCE.json",
    "evidence/CURRENT-STANDARD-TOKEN.json",
    "evidence/CURRENT-RELEASE-AUDIT.json",
    "release-tooling/proof-entrypoints/run-exact-candidate-proof.ps1",
    "release-tooling/proof-entrypoints/Invoke-RealProductPhase.psm1",
    "release-tooling/proof-entrypoints/Invoke-WpfUiAutomation.ps1",
    "release-tooling/proof-entrypoints/WpfLaunchContract.psm1",
}

PRE_ACCEPTANCE_REQUIRED = (REQUIRED - {
    "evidence/FINAL-ACCEPTANCE.json",
    "evidence/CURRENT-RELEASE-AUDIT.json",
})

STANDARD_TOKEN_CHECKS = {
    "pass", "payloadExtraction", "bootstrapEntrypoint", "parameterContract",
    "embeddedTarCount", "factoryResetBackupGate", "planSafety",
    "devfleetVersion", "installerVersion", "payloadSha",
}

COLLISION_POLICY = 'DF-FRESH-CERTIFICATION-20260930-COLLISION-1'
COLLISION_PREDECESSOR_SHA256 = '6deb98ab9dd165798e31538772f01e23eceeb333b10e0067a066685952f680e1'
COLLISION_OWNER_AUTH_SHA256 = 'f9eec666193447810089ffbd1ad249aba8f8e8a7d13e5220d10ef5ac2c64af16'
COLLISION_LEDGER_PATH = (r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work'
                         r'\DevFleet-v1.2.13-development\audit\agent-memory\attempts'
                         r'\DF-FRESH-CERTIFICATION-20260930-COLLISION-1\ledger.json')
COLLISION_LIMITS = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                    'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0,
                    'build-sign': 0}
BASELINE_TUPLE_KEYS = ('repositoryHead', 'candidateBuildCommit', 'shippingInputIdentity',
                       'releaseFingerprintId', 'toolingFingerprintId', 'candidateSha256')

MAINTENANCE_PHASES = {"REPAIR", "CLEAN-REINSTALL", "UNINSTALL", "FACTORY-RESET", "REBOOT-RESUME"}
REQUIRED_FULLRELEASE_PHASES = {
    "HOST-SAFETY", "CANDIDATE-VERIFY", "RESTORE-CLEAN", "ESTABLISH-SESSION",
    "DEPENDENCY-MATRIX", "SECURITY-POISON", "FRESH-INSTALL-WPF", "PRIMARY",
    "LINUX", "HTTP-HOSTILE", "MAINTENANCE-READY", "WINDOWS-SENTINELS",
    "REPAIR", "CLEAN-REINSTALL", "UNINSTALL", "FACTORY-RESET", "REBOOT-RESUME",
    "PERMANENT-DELETE", "DELETE-RESTORE", "STOPPED-PROJECT", "HOST-CONCURRENCY",
    "OPERATION-RECOVERY", "OWNERSHIP", "VAULT", "SURROGATE-DISPOSABLE",
    "REAL-USE-ACCEPTANCE", "TAILSCALE-DEFERRED", "TAILSCALE-AUTH", "AI-BUNDLE",
    "RECONCILE", "CLEANUP",
}

DIAGNOSTIC_REQUIRED = {
    "AUDIT-MANIFEST.json", "CURRENT-CANDIDATE.json", "finalization-state.json",
    "outputs/final-artifact-hashes.json", "evidence/CURRENT-STATUS.json",
    "outputs/dependency-advisory-gate.json", "outputs/independent-osv-reconciliation.json",
    "evidence/CURRENT-GATES.json", "evidence/CURRENT-PROOF.json",
    "evidence/FULLRELEASE-SUMMARY.json", "audit/CURRENT-HANDOFF.json",
    "release-tooling/proof-entrypoints/run-exact-candidate-proof.ps1",
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _safe_extract(bundle: zipfile.ZipFile, destination: Path) -> set[str]:
    names: set[str] = set()
    for info in bundle.infolist():
        normalized = PurePosixPath(info.filename.replace("\\", "/"))
        if normalized.is_absolute() or ".." in normalized.parts:
            raise ValueError(f"unsafe archive member: {info.filename}")
        name = normalized.as_posix()
        if name in names:
            raise ValueError(f"duplicate archive member: {name}")
        file_type = (info.external_attr >> 16) & stat.S_IFMT(0o170000)
        if file_type in (stat.S_IFLNK, stat.S_IFCHR, stat.S_IFBLK, stat.S_IFIFO):
            raise ValueError(f"unsupported special archive member: {name}")
        names.add(name)
        target = (destination / Path(*normalized.parts)).resolve()
        if destination.resolve() not in target.parents and target != destination.resolve():
            raise ValueError(f"archive member escapes extraction root: {info.filename}")
        if info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(info, "r") as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
    return names


def _proof_identity(value: object, *keys: str) -> str:
    if isinstance(value, dict):
        for key in keys:
            if value.get(key):
                return str(value[key])
        for child in value.values():
            found = _proof_identity(child, *keys)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _proof_identity(child, *keys)
            if found:
                return found
    return ""


def _validate_repair3_signed_output_receipt(receipt: dict, candidate: dict) -> None:
    """Check the non-certifying signed-output receipt bound to REPAIR-3."""
    rows = receipt.get('artifacts')
    names = [row.get('name') for row in rows or [] if isinstance(row, dict)]
    exe_rows = [row for row in rows or []
                if isinstance(row, dict) and row.get('name') == 'exe']
    if (receipt.get('schemaVersion') != 1
            or receipt.get('contract') != 'devfleet-signed-build-output-inspection-v1'
            or receipt.get('status') != 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION'
            or receipt.get('certificationCredit') is not False
            or receipt.get('repositoryHead') != candidate['candidateBuildCommit']
            or receipt.get('shippingInputIdentity') != candidate['shippingInputIdentity']
            or receipt.get('signatureStatus') != 'Valid'
            or receipt.get('publicPromotionAllowed') is not False
            or receipt.get('publicPublisherTrust') is not False
            or len(names) != 4
            or set(names) != {'exe', 'tar', 'portable', 'installerSource'}
            or any(not re.fullmatch(r'[0-9a-f]{64}', str(row.get('sha256', '')).lower())
                   for row in rows or [] if isinstance(row, dict)
                   )
            or len(exe_rows) != 1
            or exe_rows[0].get('sha256') != candidate['candidateSha256']):
        raise ValueError('generation-4 signed-output receipt contents are invalid')


def _load_packaged_repair3_receipt(sources: Path, artifact_hash: str) -> dict:
    """Load REPAIR-3 receipt only from the packaged hash-addressed source."""
    if not re.fullmatch(r'[0-9a-f]{64}', artifact_hash):
        raise ValueError('generation-4 signed-output receipt is absent or unbound')
    path = sources / (artifact_hash + '.json')
    if (not path.is_file() or path.is_symlink() or sha(path) != artifact_hash):
        raise ValueError('generation-4 signed-output receipt is absent or hash-mismatched')
    return json.loads(path.read_text(encoding='utf-8-sig'))


def _validate_repair3_receipt_hash_binding(binding: dict, artifact_hash: str) -> None:
    if binding.get('artifactReceiptSha256') != artifact_hash:
        raise ValueError('generation-4 baseline and signed-output receipt hashes differ')


def _validate_repair3_attempts(attempts: object, candidate: dict) -> None:
    if (not isinstance(attempts, list) or len(attempts) != 1
            or len([a for a in attempts if a.get('operation') == 'build-sign']) != 0
            or len({a.get('operation') for a in attempts}) != len(attempts)
            or attempts[0].get('operation') != 'standard-token'
            or attempts[0].get('state') != 'TERMINAL'
            or attempts[0].get('exitCode') != 0
            or attempts[0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
            or attempts[0].get('tuple') != candidate
            or attempts[0].get('certificationCredit') is not False
            or not isinstance(attempts[0].get('evidence'), list)
            or not attempts[0]['evidence']):
        raise ValueError('generation-4 qualification source lacks exact REPAIR-3 standard token')


def _load_generation7_source(root: Path, source_hash: object, extension: str,
                             strict_json=None):
    if not isinstance(source_hash, str) or not re.fullmatch(r'[0-9a-f]{64}', source_hash):
        raise ValueError('generation-7 frozen source hash is invalid')
    path = root / 'evidence/baselines/sources' / (source_hash + extension)
    if (not path.is_file() or path.is_symlink() or path.stat().st_size > 4_000_000
            or sha(path) != source_hash):
        raise ValueError('generation-7 frozen source is absent or hash mismatched')
    return strict_json(path) if strict_json else path


def _validate_generation7_token(root: Path, candidate: dict, reference: object,
                                attempt: dict, strict_json) -> None:
    if not isinstance(reference, dict) or set(reference) != {
            'runId', 'pointerSha256', 'canonicalSha256', 'rawReportSha256',
            'pointerPath', 'canonicalPath', 'rawReportPath'}:
        raise ValueError('generation-7 token reference is incomplete')
    run_id = reference['runId']
    if not isinstance(run_id, str) or not re.fullmatch(r'standard-token-[A-Za-z0-9-]+', run_id):
        raise ValueError('generation-7 token RunId is invalid')
    token_dir = f'evidence/standard-token/{run_id}'
    relative = {'pointerPath': 'evidence/CURRENT-STANDARD-TOKEN.json',
                'canonicalPath': token_dir + '/standard-token-evidence.json',
                'rawReportPath': token_dir + '/installer-self-test-raw.txt'}
    if any(reference.get(key) != value for key, value in relative.items()):
        raise ValueError('generation-7 token paths are not canonical')
    pointer_path, canonical_path, raw_path = (root / relative[key] for key in
        ('pointerPath', 'canonicalPath', 'rawReportPath'))
    for path, key in ((pointer_path, 'pointerSha256'),
                      (canonical_path, 'canonicalSha256'),
                      (raw_path, 'rawReportSha256')):
        if (not path.is_file() or path.is_symlink() or path.stat().st_size > 4_000_000
                or sha(path) != reference[key]):
            raise ValueError('generation-7 current token evidence differs')
        frozen = _load_generation7_source(root, reference[key],
                                           '.txt' if key == 'rawReportSha256' else '.json')
        if frozen.read_bytes() != path.read_bytes():
            raise ValueError('generation-7 token source differs from current evidence')
    token = strict_json(pointer_path)
    if token != strict_json(canonical_path) or token != _load_generation7_source(
            root, reference['canonicalSha256'], '.json', strict_json):
        raise ValueError('generation-7 token pointer, canonical and frozen copy differ')
    fields = {key: token.get(key) for key in BASELINE_TUPLE_KEYS if key != 'candidateSha256'}
    exact = {key: candidate[key] for key in BASELINE_TUPLE_KEYS if key != 'candidateSha256'}
    identity = token.get('token')
    checks = token.get('requiredChecks')
    exe, tar = token.get('exe'), token.get('tar')
    if (token.get('schemaVersion') != 1 or token.get('runId') != run_id
            or token.get('status') != 'PASS' or token.get('exitCode') != 0
            or token.get('standardNonAdministratorToken') is not True
            or token.get('residualSelfTestScratchCount') != 0 or fields != exact
            or token.get('runDirectory') != token_dir
            or token.get('canonicalEvidencePath') != relative['canonicalPath']
            or token.get('rawReportPath') != relative['rawReportPath']
            or not isinstance(identity, dict)
            or not re.fullmatch(r'[^\\]+\\Developer', str(identity.get('userName', '')), re.I)
            or identity.get('standardNonAdministratorToken') is not True
            or identity.get('isAdministratorMember') is not False
            or identity.get('isAdministratorEnabled') is not False
            or identity.get('isElevated') is not False
            or identity.get('integrityLevel') != 'Medium'
            or not isinstance(checks, dict) or set(checks) != STANDARD_TOKEN_CHECKS
            or any(value is not True for value in checks.values())
            or not isinstance(exe, dict) or exe.get('sha256') != candidate['candidateSha256']
            or not isinstance(exe.get('bytes'), int) or exe['bytes'] <= 0
            or not isinstance(tar, dict) or not re.fullmatch(r'[0-9a-f]{64}', str(tar.get('sha256')))
            or not isinstance(tar.get('bytes'), int) or tar['bytes'] <= 0
            or token.get('reportSha256') != reference['rawReportSha256']):
        raise ValueError('generation-7 current Developer token is not a genuine exact PASS')
    raw = raw_path.read_text(encoding='utf-8-sig')
    if not re.search(r'(?m)^PASS\s*$', raw) or f"payload={tar['sha256']}" not in raw:
        raise ValueError('generation-7 raw token report lacks exact PASS and payload')
    runner_relative = 'automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1'
    runner = root / runner_relative
    runner_ref = token.get('runner')
    if (not isinstance(runner_ref, dict) or runner_ref.get('path') != runner_relative
            or not runner.is_file() or runner.is_symlink()
            or sha(runner) != runner_ref.get('sha256')):
        raise ValueError('generation-7 standard-token runner bytes differ')
    evidence = attempt.get('evidence')
    suffix = '/' + relative['canonicalPath'].lower()
    if (not isinstance(evidence, list) or not any(isinstance(item, str)
            and item.replace('\\', '/').lower().endswith(suffix) for item in evidence)
            or attempt.get('runId') == run_id):
        raise ValueError('generation-7 charged outer attempt lacks distinct inner token evidence')
    def instant(value):
        if not isinstance(value, str):
            raise ValueError('generation-7 token chronology is absent')
        return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc)
    if not instant(attempt.get('reservedUtc')) <= instant(token.get('generatedAtUtc')) <= instant(attempt.get('terminalUtc')):
        raise ValueError('generation-7 token is outside charged outer attempt')


def _validate_generation7_predecessor(predecessor: dict, failed_run_id: object,
                                      failures: dict) -> None:
    attempts = predecessor.get('attempts')
    expected = [('standard-token', 'PASS_NATIVE_STANDARD_TOKEN', 0),
                ('diagnostic', 'PASS_READY_FOR_PROOF_RESERVATION', 0),
                ('laptop-proof', 'NATIVE_LAPTOP_PROOF_BLOCKED', 2)]
    if (predecessor.get('policyId') != 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1'
            or predecessor.get('activeRunId') is not None
            or not isinstance(attempts, list) or len(attempts) != 3
            or any(a.get('operation') != op or a.get('classification') != result
                   or a.get('exitCode') != code or a.get('state') != 'TERMINAL'
                   for a, (op, result, code) in zip(attempts, expected))
            or attempts[2].get('runId') != failed_run_id):
        raise ValueError('generation-7 predecessor is not exact terminal CAUSAL-1')
    wrapper, error, cleanup = (failures[key] for key in ('wrapper', 'proofError', 'cleanup'))
    first = 'Cannot create a file when that file already exists.'
    l1 = cleanup.get('l1') or {}
    l2 = cleanup.get('l2') or {}
    if (wrapper.get('runId') != failed_run_id
            or wrapper.get('classification') != 'NATIVE_LAPTOP_PROOF_BLOCKED'
            or wrapper.get('exitCode') != 2
            or wrapper.get('firstTechnicalFailure') != first
            or error.get('runId') != failed_run_id or error.get('status') != 'BLOCKED'
            or error.get('error') != first
            or cleanup.get('runId') != failed_run_id or cleanup.get('status') != 'PASS'
            or cleanup.get('runOwnedOnly') is not True
            or l1.get('name') != 'DevFleet-E2E-Win11-01'
            or l1.get('id') != '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
            or l1.get('status') != 'OFF'
            or l2.get('expectedName') != 'DevFleet-E2E-Linux-01'
            or l2.get('status') != 'ABSENT' or l2.get('present') is not False
            or l2.get('exactMatchCount') != 0 or l2.get('inventoryCount') != 0
            or cleanup.get('l2Present') is not False):
        raise ValueError('generation-7 collision failure and cleanup evidence differs')


def load_accepted_baseline(root: Path, expected: dict[str, str], artifacts: dict[str, str],
                           _pointer: dict | None = None) -> dict[str, str | None]:
    """Resolve only the original CLEAN or a packaged, immutable adoption receipt."""
    def strict_baseline_json(path: Path) -> dict:
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 4_000_000:
            raise ValueError("accepted baseline evidence is absent, linked, or oversized")
        def pairs(items):
            result = {}
            for key, value in items:
                if key in result:
                    raise ValueError("accepted baseline JSON has duplicate keys")
                result[key] = value
            return result
        value = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite baseline JSON")))
        if not isinstance(value, dict):
            raise ValueError("accepted baseline JSON root is invalid")
        return value
    old_id = "19865b76-4c3a-44f7-ba39-841e9d3c40c9"
    pointer_path = root / "evidence/baselines/CURRENT.json"
    if not pointer_path.exists():
        return {"id": old_id, "name": "DevFleet-E2E-CLEAN", "receiptSha256": None}
    pointer = _pointer if _pointer is not None else strict_baseline_json(pointer_path)
    if pointer.get('generation') == 7:
        if (pointer.get('schemaVersion') != 7
                or pointer.get('contract') != 'devfleet-accepted-baseline-v7'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('generation-7 baseline pointer contract is invalid')
        old_hash, name = pointer.get('previousPointerSha256'), pointer.get('receiptFile')
        if (not isinstance(old_hash, str) or not re.fullmatch(r'[0-9a-f]{64}', old_hash)
                or not isinstance(name, str) or not re.fullmatch(r'[0-9a-f]{32}\.json', name)):
            raise ValueError('generation-7 baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or history_path.is_symlink() or sha(history_path) != old_hash
                or not receipt_path.is_file() or receipt_path.is_symlink()
                or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('generation-7 baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 6:
            raise ValueError('generation-7 predecessor is not generation 6')
        binding = strict_baseline_json(receipt_path)
        old_tuple, new_tuple = binding.get('previousCandidate'), binding.get('candidate')
        if (not isinstance(old_tuple, dict) or not isinstance(new_tuple, dict)
                or set(old_tuple) != set(BASELINE_TUPLE_KEYS)
                or set(new_tuple) != set(BASELINE_TUPLE_KEYS)):
            raise ValueError('generation-7 candidate tuple is incomplete')
        prior_expected = {key: old_tuple[key] for key in
                          ('repositoryHead', 'shippingInputIdentity',
                           'releaseFingerprintId', 'toolingFingerprintId')}
        prior_expected['candidateCommit'] = old_tuple['candidateBuildCommit']
        prior = load_accepted_baseline(root, prior_expected,
                                       {'exe': old_tuple['candidateSha256']}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        final_l1 = {'name': 'DevFleet-E2E-Win11-01',
                    'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2', 'state': 'Off'}
        if (binding.get('schemaVersion') != 7
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v7'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or 'artifactReceiptSha256' in binding
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != prior['receiptSha256']
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')
                or binding.get('finalL1') != final_l1
                or binding.get('successorPolicyId') != COLLISION_POLICY
                or old_tuple['repositoryHead'] == new_tuple['repositoryHead']
                or old_tuple['toolingFingerprintId'] == new_tuple['toolingFingerprintId']
                or any(old_tuple[key] != new_tuple[key] for key in
                       ('candidateBuildCommit', 'shippingInputIdentity',
                        'releaseFingerprintId', 'candidateSha256'))
                or new_tuple != actual):
            raise ValueError('generation-7 receipt or signed shipping tuple differs')
        approval = binding.get('approval')
        if (not isinstance(approval, dict)
                or approval.get('schemaVersion') != 7
                or approval.get('contract') != 'devfleet-baseline-rebind-approval-v7'
                or approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('shippingChangeApproved') is not False
                or approval.get('previousCandidate') != old_tuple
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('successorAuthorizationSha256') != binding.get('successorAuthorizationSha256')
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('approvalSha256', '')))):
            raise ValueError('generation-7 account-owner approval differs')
        frozen_approval = _load_generation7_source(root, binding['approvalSha256'],
                                                    '.json', strict_baseline_json)
        if approval != {**frozen_approval, 'sourceSha256': binding['approvalSha256']}:
            raise ValueError('generation-7 owner approval source differs from receipt')
        hashes = {key: binding.get(key) for key in
                  ('successorLedgerSha256', 'nativeInventorySha256',
                   'successorAuthorizationSha256', 'predecessorLedgerSha256')}
        sources = {key: _load_generation7_source(root, value, '.json', strict_baseline_json)
                   for key, value in hashes.items()}
        failures = binding.get('failureEvidenceSha256')
        if not isinstance(failures, dict) or set(failures) != {'wrapper', 'proofError', 'cleanup'}:
            raise ValueError('generation-7 collision failure references are incomplete')
        failure_records = {key: _load_generation7_source(root, value, '.json', strict_baseline_json)
                           for key, value in failures.items()}
        auth = sources['successorAuthorizationSha256']
        ledger = sources['successorLedgerSha256']
        predecessor = sources['predecessorLedgerSha256']
        inventory = sources['nativeInventorySha256']
        if (hashes['predecessorLedgerSha256'] != COLLISION_PREDECESSOR_SHA256
                or binding.get('ownerAuthorizationSha256') != COLLISION_OWNER_AUTH_SHA256
                or (auth.get('ownerAuthorization') or {}).get('sha256') != COLLISION_OWNER_AUTH_SHA256):
            raise ValueError('generation-7 pinned predecessor or owner authorization differs')
        _load_generation7_source(root, COLLISION_OWNER_AUTH_SHA256, '.txt')
        if (auth.get('schemaVersion') != 1
                or auth.get('kind') != 'DEVFLEET_POST_COLLISION_SUCCESSOR_AUTHORIZATION'
                or auth.get('policyId') != COLLISION_POLICY
                or auth.get('approved') is not True
                or auth.get('approvedBy') != 'ACCOUNT_OWNER'
                or str(auth.get('successorLedgerPath', '')).replace('/', '\\').casefold()
                   != str(COLLISION_LEDGER_PATH).replace('/', '\\').casefold()
                or auth.get('previousCandidate') != old_tuple
                or auth.get('candidate') != new_tuple
                or (auth.get('predecessorSha256') or {}).get('causal1') != hashes['predecessorLedgerSha256']
                or (auth.get('generation6') or {}).get('receiptSha256') != prior['receiptSha256']
                or (auth.get('generation6') or {}).get('checkpoint') != pointer['checkpoint']
                or auth.get('limits') != COLLISION_LIMITS
                or any((auth.get('failureEvidence') or {}).get(key, {}).get('sha256') != value
                       for key, value in failures.items())):
            raise ValueError('generation-7 collision authorization differs')
        _validate_generation7_predecessor(predecessor, auth.get('failedRunId'), failure_records)
        attempts = ledger.get('attempts')
        if (ledger.get('policyId') != COLLISION_POLICY
                or ledger.get('limits') != COLLISION_LIMITS
                or ledger.get('activeRunId') is not None
                or (ledger.get('authorization') or {}).get('sha256') != hashes['successorAuthorizationSha256']
                or len(ledger.get('predecessors') or []) != 1
                or ledger['predecessors'][0].get('sha256') != hashes['predecessorLedgerSha256']
                or not isinstance(attempts, list) or len(attempts) != 1
                or attempts[0].get('operation') != 'standard-token'
                or attempts[0].get('state') != 'TERMINAL'
                or attempts[0].get('exitCode') != 0
                or attempts[0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
                or attempts[0].get('tuple') != new_tuple
                or attempts[0].get('certificationCredit') is not False):
            raise ValueError('generation-7 successor lacks one exact token qualification')
        snapshots = inventory.get('snapshots')
        exact = [row for row in snapshots if isinstance(row, dict)
                 and row.get('name') == 'DevFleet-E2E-CLEAN-R2'] if isinstance(snapshots, list) else []
        if (inventory.get('scope') != 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                or inventory.get('vm') != final_l1
                or len(exact) != 1 or exact[0].get('id') != pointer['checkpoint']['id']
                or exact[0].get('vmId') != final_l1['id']
                or exact[0].get('parentSnapshotId') != old_id):
            raise ValueError('generation-7 inventory does not prove CLEAN-R2 and L1 Off')
        _validate_generation7_token(root, new_tuple, binding.get('standardTokenEvidence'),
                                    attempts[0], strict_baseline_json)
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    if pointer.get('generation') == 6:
        if (pointer.get('schemaVersion') != 6
                or pointer.get('contract') != 'devfleet-accepted-baseline-v6'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('generation-6 baseline pointer contract is invalid')
        old_hash, name = pointer.get('previousPointerSha256', ''), pointer.get('receiptFile', '')
        if not re.fullmatch(r'[0-9a-f]{64}', old_hash) or not re.fullmatch(r'[0-9a-f]{32}\.json', name):
            raise ValueError('generation-6 baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or history_path.is_symlink() or sha(history_path) != old_hash
                or not receipt_path.is_file() or receipt_path.is_symlink()
                or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('generation-6 baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 5:
            raise ValueError('generation-6 predecessor is not generation 5')
        binding = strict_baseline_json(receipt_path)
        old_tuple = binding.get('previousCandidate') or {}
        new_tuple = binding.get('candidate') or {}
        prior_expected = {'repositoryHead': old_tuple.get('repositoryHead'),
                          'candidateCommit': old_tuple.get('candidateBuildCommit'),
                          'shippingInputIdentity': old_tuple.get('shippingInputIdentity'),
                          'releaseFingerprintId': old_tuple.get('releaseFingerprintId'),
                          'toolingFingerprintId': old_tuple.get('toolingFingerprintId')}
        prior = load_accepted_baseline(root, prior_expected,
                                       {'exe': old_tuple.get('candidateSha256')}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        if (binding.get('schemaVersion') != 6
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v6'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or 'artifactReceiptSha256' in binding
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != prior['receiptSha256']
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')
                or new_tuple != actual
                or old_tuple.get('repositoryHead') == new_tuple.get('repositoryHead')
                or old_tuple.get('toolingFingerprintId') == new_tuple.get('toolingFingerprintId')
                or any(old_tuple.get(key) != new_tuple.get(key) for key in
                       ('candidateBuildCommit', 'shippingInputIdentity',
                        'releaseFingerprintId', 'candidateSha256'))):
            raise ValueError('generation-6 receipt or signed material tuple differs')
        approval = binding.get('approval') or {}
        final_l1 = {'name': 'DevFleet-E2E-Win11-01',
                    'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2', 'state': 'Off'}
        if (approval.get('schemaVersion') != 5
                or approval.get('contract') != 'devfleet-baseline-rebind-approval-v5'
                or approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('shippingChangeApproved') is not False
                or approval.get('previousCandidate') != old_tuple
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('approvalSha256', '')))
                or binding.get('finalL1') != final_l1
                or binding.get('successorPolicyId') != 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1'
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('successorLedgerSha256', '')))
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('nativeInventorySha256', '')))):
            raise ValueError('generation-6 authorization or terminal lab differs')
        sources = root / 'evidence/baselines/sources'
        ledger_hash, inventory_hash = binding['successorLedgerSha256'], binding['nativeInventorySha256']
        ledger_path, inventory_path = sources / (ledger_hash + '.json'), sources / (inventory_hash + '.json')
        if (not ledger_path.is_file() or ledger_path.is_symlink() or sha(ledger_path) != ledger_hash
                or not inventory_path.is_file() or inventory_path.is_symlink()
                or sha(inventory_path) != inventory_hash):
            raise ValueError('generation-6 qualification or inventory source is absent or altered')
        ledger, inventory = strict_baseline_json(ledger_path), strict_baseline_json(inventory_path)
        attempts = ledger.get('attempts')
        limits = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                  'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
        if (ledger.get('policyId') != binding['successorPolicyId']
                or ledger.get('limits') != limits
                or ledger.get('activeRunId') is not None
                or not isinstance(attempts, list) or len(attempts) != 1
                or attempts[0].get('operation') != 'standard-token'
                or attempts[0].get('state') != 'TERMINAL'
                or attempts[0].get('exitCode') != 0
                or attempts[0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
                or attempts[0].get('tuple') != new_tuple
                or attempts[0].get('certificationCredit') is not False
                or not isinstance(attempts[0].get('evidence'), list)
                or not attempts[0]['evidence']):
            raise ValueError('generation-6 qualification source lacks exact standard token')
        snapshots = inventory.get('snapshots')
        exact = [row for row in snapshots if isinstance(row, dict)
                 and row.get('name') == 'DevFleet-E2E-CLEAN-R2'] if isinstance(snapshots, list) else []
        if (inventory.get('scope') != 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                or inventory.get('vm') != final_l1
                or len(exact) != 1 or exact[0].get('id') != pointer['checkpoint']['id']
                or exact[0].get('vmId') != final_l1['id']
                or exact[0].get('parentSnapshotId') != '19865b76-4c3a-44f7-ba39-841e9d3c40c9'):
            raise ValueError('generation-6 inventory does not prove accepted checkpoint and L1 Off')
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    if pointer.get('generation') == 5:
        if (pointer.get('schemaVersion') != 5
                or pointer.get('contract') != 'devfleet-accepted-baseline-v5'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('generation-5 baseline pointer contract is invalid')
        old_hash, name = pointer.get('previousPointerSha256', ''), pointer.get('receiptFile', '')
        if not re.fullmatch(r'[0-9a-f]{64}', old_hash) or not re.fullmatch(r'[0-9a-f]{32}\.json', name):
            raise ValueError('generation-5 baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or history_path.is_symlink() or sha(history_path) != old_hash
                or not receipt_path.is_file() or receipt_path.is_symlink()
                or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('generation-5 baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 4:
            raise ValueError('generation-5 predecessor is not generation 4')
        binding = strict_baseline_json(receipt_path)
        old_tuple = binding.get('previousCandidate') or {}
        new_tuple = binding.get('candidate') or {}
        prior_expected = {'repositoryHead': old_tuple.get('repositoryHead'),
                          'candidateCommit': old_tuple.get('candidateBuildCommit'),
                          'shippingInputIdentity': old_tuple.get('shippingInputIdentity'),
                          'releaseFingerprintId': old_tuple.get('releaseFingerprintId'),
                          'toolingFingerprintId': old_tuple.get('toolingFingerprintId')}
        prior = load_accepted_baseline(root, prior_expected,
                                       {'exe': old_tuple.get('candidateSha256')}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        if (binding.get('schemaVersion') != 5
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v5'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or 'artifactReceiptSha256' in binding
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != prior['receiptSha256']
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')
                or new_tuple != actual
                or old_tuple.get('repositoryHead') == new_tuple.get('repositoryHead')
                or old_tuple.get('toolingFingerprintId') == new_tuple.get('toolingFingerprintId')
                or any(old_tuple.get(key) != new_tuple.get(key) for key in
                       ('candidateBuildCommit', 'shippingInputIdentity',
                        'releaseFingerprintId', 'candidateSha256'))):
            raise ValueError('generation-5 receipt or signed material tuple differs')
        approval = binding.get('approval') or {}
        final_l1 = {'name': 'DevFleet-E2E-Win11-01',
                    'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2', 'state': 'Off'}
        if (approval.get('schemaVersion') != 4
                or approval.get('contract') != 'devfleet-baseline-rebind-approval-v4'
                or approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('shippingChangeApproved') is not False
                or approval.get('previousCandidate') != old_tuple
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('approvalSha256', '')))
                or binding.get('finalL1') != final_l1
                or binding.get('successorPolicyId') != 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5'
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('successorLedgerSha256', '')))
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('nativeInventorySha256', '')))):
            raise ValueError('generation-5 authorization or terminal lab differs')
        sources = root / 'evidence/baselines/sources'
        ledger_hash, inventory_hash = binding['successorLedgerSha256'], binding['nativeInventorySha256']
        ledger_path, inventory_path = sources / (ledger_hash + '.json'), sources / (inventory_hash + '.json')
        if (not ledger_path.is_file() or ledger_path.is_symlink() or sha(ledger_path) != ledger_hash
                or not inventory_path.is_file() or inventory_path.is_symlink()
                or sha(inventory_path) != inventory_hash):
            raise ValueError('generation-5 qualification or inventory source is absent or altered')
        ledger, inventory = strict_baseline_json(ledger_path), strict_baseline_json(inventory_path)
        attempts = ledger.get('attempts')
        limits = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                  'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
        if (ledger.get('policyId') != binding['successorPolicyId']
                or ledger.get('limits') != limits
                or ledger.get('activeRunId') is not None
                or not isinstance(attempts, list) or len(attempts) != 1
                or attempts[0].get('operation') != 'standard-token'
                or attempts[0].get('state') != 'TERMINAL'
                or attempts[0].get('exitCode') != 0
                or attempts[0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
                or attempts[0].get('tuple') != new_tuple
                or attempts[0].get('certificationCredit') is not False
                or not isinstance(attempts[0].get('evidence'), list)
                or not attempts[0]['evidence']):
            raise ValueError('generation-5 qualification source lacks exact standard token')
        snapshots = inventory.get('snapshots')
        exact = [row for row in snapshots if isinstance(row, dict)
                 and row.get('name') == 'DevFleet-E2E-CLEAN-R2'] if isinstance(snapshots, list) else []
        if (inventory.get('scope') != 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                or inventory.get('vm') != final_l1
                or len(exact) != 1 or exact[0].get('id') != pointer['checkpoint']['id']
                or exact[0].get('vmId') != final_l1['id']
                or exact[0].get('parentSnapshotId') != '19865b76-4c3a-44f7-ba39-841e9d3c40c9'):
            raise ValueError('generation-5 inventory does not prove accepted checkpoint and L1 Off')
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    if pointer.get('generation') == 4:
        if (pointer.get('schemaVersion') != 4
                or pointer.get('contract') != 'devfleet-accepted-baseline-v4'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('generation-4 baseline pointer contract is invalid')
        old_hash, name = pointer.get('previousPointerSha256', ''), pointer.get('receiptFile', '')
        if not re.fullmatch(r'[0-9a-f]{64}', old_hash) or not re.fullmatch(r'[0-9a-f]{32}\.json', name):
            raise ValueError('generation-4 baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or history_path.is_symlink() or sha(history_path) != old_hash
                or not receipt_path.is_file() or receipt_path.is_symlink()
                or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('generation-4 baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 3:
            raise ValueError('generation-4 predecessor is not generation 3')
        binding = strict_baseline_json(receipt_path)
        old_tuple = binding.get('previousCandidate') or {}
        new_tuple = binding.get('candidate') or {}
        prior_expected = {'repositoryHead': old_tuple.get('repositoryHead'),
                          'candidateCommit': old_tuple.get('candidateBuildCommit'),
                          'shippingInputIdentity': old_tuple.get('shippingInputIdentity'),
                          'releaseFingerprintId': old_tuple.get('releaseFingerprintId'),
                          'toolingFingerprintId': old_tuple.get('toolingFingerprintId')}
        prior = load_accepted_baseline(root, prior_expected,
                                       {'exe': old_tuple.get('candidateSha256')}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        tuple_keys = ('repositoryHead', 'candidateBuildCommit', 'shippingInputIdentity',
                      'releaseFingerprintId', 'toolingFingerprintId', 'candidateSha256')
        if (binding.get('schemaVersion') != 4
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v4'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != prior['receiptSha256']
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')
                or new_tuple != actual
                or any(old_tuple.get(key) == new_tuple.get(key) for key in tuple_keys)):
            raise ValueError('generation-4 receipt or signed material tuple differs')
        approval = binding.get('approval') or {}
        final_l1 = {'name': 'DevFleet-E2E-Win11-01',
                    'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2', 'state': 'Off'}
        if (approval.get('schemaVersion') != 3
                or approval.get('contract') != 'devfleet-baseline-rebind-approval-v3'
                or approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('shippingChangeApproved') is not True
                or approval.get('previousCandidate') != old_tuple
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('approvalSha256', '')))
                or binding.get('finalL1') != final_l1
                or binding.get('successorPolicyId') != 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-3'
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('successorLedgerSha256', '')))
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('nativeInventorySha256', '')))):
            raise ValueError('generation-4 authorization or terminal lab differs')
        sources = root / 'evidence/baselines/sources'
        ledger_hash, inventory_hash = binding['successorLedgerSha256'], binding['nativeInventorySha256']
        ledger_path, inventory_path = sources / (ledger_hash + '.json'), sources / (inventory_hash + '.json')
        if (not ledger_path.is_file() or ledger_path.is_symlink() or sha(ledger_path) != ledger_hash
                or not inventory_path.is_file() or inventory_path.is_symlink()
                or sha(inventory_path) != inventory_hash):
            raise ValueError('generation-4 qualification or inventory source is absent or altered')
        ledger, inventory = strict_baseline_json(ledger_path), strict_baseline_json(inventory_path)
        attempts = ledger.get('attempts')
        limits = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                  'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
        artifact_binding = ledger.get('artifactReceipt') or {}
        artifact_hash = str(artifact_binding.get('sha256', '')).lower()
        _validate_repair3_receipt_hash_binding(binding, artifact_hash)
        artifact_receipt = _load_packaged_repair3_receipt(sources, artifact_hash)
        _validate_repair3_signed_output_receipt(artifact_receipt, new_tuple)
        if (ledger.get('policyId') != binding['successorPolicyId']
                or ledger.get('limits') != limits
                or ledger.get('activeRunId') is not None):
            raise ValueError('generation-4 qualification source lacks exact REPAIR-3 standard token')
        _validate_repair3_attempts(attempts, new_tuple)
        snapshots = inventory.get('snapshots')
        exact = [row for row in snapshots if isinstance(row, dict)
                 and row.get('name') == 'DevFleet-E2E-CLEAN-R2'] if isinstance(snapshots, list) else []
        if (inventory.get('scope') != 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                or inventory.get('vm') != final_l1
                or len(exact) != 1 or exact[0].get('id') != pointer['checkpoint']['id']
                or exact[0].get('vmId') != final_l1['id']
                or exact[0].get('parentSnapshotId') != '19865b76-4c3a-44f7-ba39-841e9d3c40c9'):
            raise ValueError('generation-4 inventory does not prove accepted checkpoint and L1 Off')
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    if pointer.get('generation') == 3:
        if (pointer.get('schemaVersion') != 3
                or pointer.get('contract') != 'devfleet-accepted-baseline-v3'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('generation-3 baseline pointer contract is invalid')
        old_hash = pointer.get('previousPointerSha256', '')
        name = pointer.get('receiptFile', '')
        if not re.fullmatch(r'[0-9a-f]{64}', old_hash) or not re.fullmatch(r'[0-9a-f]{32}\.json', name):
            raise ValueError('generation-3 baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or sha(history_path) != old_hash
                or not receipt_path.is_file() or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('generation-3 baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 2:
            raise ValueError('generation-3 predecessor is not generation 2')
        binding = strict_baseline_json(receipt_path)
        old_tuple = binding.get('previousCandidate') or {}
        new_tuple = binding.get('candidate') or {}
        old_expected = {'repositoryHead': old_tuple.get('repositoryHead'),
                        'candidateCommit': old_tuple.get('candidateBuildCommit'),
                        'shippingInputIdentity': old_tuple.get('shippingInputIdentity'),
                        'releaseFingerprintId': old_tuple.get('releaseFingerprintId'),
                        'toolingFingerprintId': old_tuple.get('toolingFingerprintId')}
        prior = load_accepted_baseline(root, old_expected,
                                       {'exe': old_tuple.get('candidateSha256')}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        if (binding.get('schemaVersion') != 3
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v3'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != prior['receiptSha256']
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')
                or new_tuple != actual
                or old_tuple.get('repositoryHead') == new_tuple.get('repositoryHead')
                or old_tuple.get('toolingFingerprintId') == new_tuple.get('toolingFingerprintId')
                or any(old_tuple.get(key) != new_tuple.get(key) for key in
                       ('candidateBuildCommit', 'shippingInputIdentity',
                        'releaseFingerprintId', 'candidateSha256'))):
            raise ValueError('generation-3 receipt or material tuple differs')
        approval = binding.get('approval') or {}
        if (approval.get('schemaVersion') != 2
                or approval.get('contract') != 'devfleet-baseline-rebind-approval-v2'
                or approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not isinstance(binding.get('approvalSha256'), str)
                or not re.fullmatch(r'[0-9a-f]{64}', binding['approvalSha256'])
                or binding.get('finalL1') != {'name': 'DevFleet-E2E-Win11-01',
                                             'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2',
                                             'state': 'Off'}
                or binding.get('successorPolicyId') != 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-1'
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('successorLedgerSha256', '')))
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('nativeInventorySha256', '')))):
            raise ValueError('generation-3 authorization or terminal lab differs')
        source_dir = root / 'evidence/baselines/sources'
        ledger_hash = binding['successorLedgerSha256']
        inventory_hash = binding['nativeInventorySha256']
        ledger_path = source_dir / (ledger_hash + '.json')
        inventory_path = source_dir / (inventory_hash + '.json')
        if (not ledger_path.is_file() or ledger_path.is_symlink()
                or not inventory_path.is_file() or inventory_path.is_symlink()
                or sha(ledger_path) != ledger_hash or sha(inventory_path) != inventory_hash):
            raise ValueError('generation-3 qualification or inventory source is absent or altered')
        ledger = strict_baseline_json(ledger_path)
        inventory = strict_baseline_json(inventory_path)
        attempts = ledger.get('attempts')
        required_remaining = {'standard-token': 1, 'diagnostic': 1,
                              'laptop-proof': 1, 'desktop-proof': 1,
                              'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
        if (ledger.get('policyId') != binding['successorPolicyId']
                or ledger.get('limits') != required_remaining
                or ledger.get('activeRunId') is not None
                or not isinstance(attempts, list) or len(attempts) != 1
                or attempts[0].get('operation') != 'standard-token'
                or attempts[0].get('state') != 'TERMINAL'
                or attempts[0].get('exitCode') != 0
                or attempts[0].get('classification') != 'PASS_NATIVE_STANDARD_TOKEN'
                or attempts[0].get('tuple') != new_tuple
                or attempts[0].get('certificationCredit') is not False
                or not isinstance(attempts[0].get('evidence'), list)
                or not attempts[0]['evidence']):
            raise ValueError('generation-3 qualification source does not prove terminal standard token')
        snapshots = inventory.get('snapshots')
        exact = [row for row in snapshots if isinstance(row, dict)
                 and row.get('name') == 'DevFleet-E2E-CLEAN-R2'] if isinstance(snapshots, list) else []
        if (inventory.get('scope') != 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
                or inventory.get('vm') != binding['finalL1']
                or len(exact) != 1 or exact[0].get('id') != pointer['checkpoint']['id']
                or exact[0].get('vmId') != binding['finalL1']['id']
                or exact[0].get('parentSnapshotId') != '19865b76-4c3a-44f7-ba39-841e9d3c40c9'):
            raise ValueError('generation-3 inventory source does not prove accepted checkpoint and L1 Off')
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    if pointer.get('generation') == 2:
        if (pointer.get('schemaVersion') != 2
                or pointer.get('contract') != 'devfleet-accepted-baseline-v2'
                or pointer.get('status') != 'ACCEPTED'):
            raise ValueError('rebound baseline pointer contract is invalid')
        old_hash = pointer.get('previousPointerSha256', '')
        name = pointer.get('receiptFile', '')
        if not re.fullmatch(r'[0-9a-f]{64}', old_hash) or not re.fullmatch(r'[0-9a-f]{32}\.json', name):
            raise ValueError('rebound baseline lineage reference is invalid')
        history_path = root / 'evidence/baselines/history' / (old_hash + '.json')
        receipt_path = root / 'evidence/baselines/receipts' / name
        if (not history_path.is_file() or sha(history_path) != old_hash
                or not receipt_path.is_file() or sha(receipt_path) != pointer.get('receiptSha256')):
            raise ValueError('rebound baseline chain is absent or hash mismatched')
        previous = strict_baseline_json(history_path)
        if previous.get('generation') != 1:
            raise ValueError('rebound baseline predecessor is not generation 1')
        binding = strict_baseline_json(receipt_path)
        old_tuple = binding.get('previousCandidate') or {}
        new_tuple = binding.get('candidate') or {}
        if (binding.get('schemaVersion') != 2
                or binding.get('contract') != 'devfleet-baseline-rebind-receipt-v2'
                or binding.get('status') != 'REBOUND'
                or binding.get('certificationCredit') is not False
                or binding.get('secretValuesRecorded') is not False
                or not isinstance(binding.get('receiptId'), str)
                or binding['receiptId'] + '.json' != name
                or binding.get('previousPointerSha256') != old_hash
                or binding.get('previousReceiptSha256') != previous.get('receiptSha256')
                or binding.get('replacement') != pointer.get('checkpoint')
                or binding.get('replacement') != previous.get('checkpoint')):
            raise ValueError('rebound baseline receipt lineage is invalid')
        old_expected = {'repositoryHead': old_tuple.get('repositoryHead'),
                        'candidateCommit': old_tuple.get('candidateBuildCommit'),
                        'shippingInputIdentity': old_tuple.get('shippingInputIdentity'),
                        'releaseFingerprintId': old_tuple.get('releaseFingerprintId'),
                        'toolingFingerprintId': old_tuple.get('toolingFingerprintId')}
        prior = load_accepted_baseline(root, old_expected,
                                       {'exe': old_tuple.get('candidateSha256')}, previous)
        actual = {'repositoryHead': expected['repositoryHead'],
                  'candidateBuildCommit': expected['candidateCommit'],
                  'shippingInputIdentity': expected['shippingInputIdentity'],
                  'releaseFingerprintId': expected['releaseFingerprintId'],
                  'toolingFingerprintId': expected['toolingFingerprintId'],
                  'candidateSha256': artifacts['exe']}
        if (new_tuple != actual or binding['previousReceiptSha256'] != prior['receiptSha256']
                or old_tuple.get('repositoryHead') == new_tuple.get('repositoryHead')
                or old_tuple.get('toolingFingerprintId') == new_tuple.get('toolingFingerprintId')
                or any(old_tuple.get(k) != new_tuple.get(k) for k in
                       ('candidateBuildCommit', 'shippingInputIdentity',
                        'releaseFingerprintId', 'candidateSha256'))):
            raise ValueError('rebound baseline tuple differs')
        approval = binding.get('approval') or {}
        if (approval.get('decision') != 'APPROVE'
                or approval.get('approvedBy') != 'ACCOUNT_OWNER'
                or approval.get('candidate') != new_tuple
                or approval.get('replacement') != pointer['checkpoint']
                or approval.get('previousReceiptSha256') != prior['receiptSha256']
                or approval.get('sourceSha256') != binding.get('approvalSha256')
                or not isinstance(binding.get('approvalSha256'), str)
                or not re.fullmatch(r'[0-9a-f]{64}', binding['approvalSha256'])
                or binding.get('finalL1') != {'name': 'DevFleet-E2E-Win11-01',
                                             'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2',
                                             'state': 'Off'}
                or binding.get('successorPolicyId') != 'DF-FRESH-CERTIFICATION-20260926-R2-D1'
                or not re.fullmatch(r'[0-9a-f]{64}', str(binding.get('successorLedgerSha256', '')))):
            raise ValueError('rebound baseline authorization or terminal lab differs')
        return {'id': prior['id'], 'name': prior['name'],
                'receiptSha256': pointer['receiptSha256']}
    name = pointer.get("receiptFile", "")
    if (pointer.get("schemaVersion") != 1
            or pointer.get("contract") != "devfleet-accepted-baseline-v1" or pointer.get("generation") != 1
            or pointer.get("status") != "ACCEPTED" or not re.fullmatch(r"[0-9a-f]{32}\.json", name)):
        raise ValueError("accepted baseline pointer contract is invalid")
    receipt_path = root / "evidence/baselines/receipts" / name
    if not receipt_path.is_file() or pointer.get("receiptSha256") != sha(receipt_path):
        raise ValueError("accepted baseline receipt is missing or hash mismatched")
    receipt = strict_baseline_json(receipt_path)
    new = receipt.get("replacement", {})
    old = receipt.get("predecessor", {})
    if (receipt.get("schemaVersion") != 1
            or receipt.get("contract") != "devfleet-baseline-adoption-receipt-v1"
            or receipt.get("status") != "ADOPTED" or receipt.get("certificationCredit") is not False
            or receipt.get("secretValuesRecorded") is not False
            or not isinstance(receipt.get("receiptId"), str)
            or receipt["receiptId"] + ".json" != name
            or old != {"name": "DevFleet-E2E-CLEAN", "id": old_id}
            or new.get("name") != "DevFleet-E2E-CLEAN-R2"
            or new.get("vmId") != "84b7d8b8-ee6c-4085-aa29-4b0adc316de2"
            or new.get("parentSnapshotId") != old_id or new.get("id") == old_id
            or pointer.get("checkpoint") != new):
        raise ValueError("accepted baseline receipt lineage is invalid")
    try:
        if str(uuid.UUID(new["id"])) != new["id"]:
            raise ValueError("replacement GUID is not canonical")
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError("replacement GUID is invalid") from exc
    tuple_expected = {"repositoryHead": expected["repositoryHead"],
                      "candidateBuildCommit": expected["candidateCommit"],
                      "shippingInputIdentity": expected["shippingInputIdentity"],
                      "releaseFingerprintId": expected["releaseFingerprintId"],
                      "toolingFingerprintId": expected["toolingFingerprintId"],
                      "candidateSha256": artifacts["exe"]}
    if receipt.get("candidate") != tuple_expected:
        raise ValueError("accepted baseline material tuple differs")
    def utc_baseline(value):
        moment = datetime.fromisoformat(str(value or "").replace("Z", "+00:00"))
        if moment.tzinfo is None or moment.utcoffset().total_seconds() != 0:
            raise ValueError("accepted baseline credential instant is not UTC")
        return moment
    expiry = utc_baseline(receipt.get("passwordExpiresUtc"))
    last_set = utc_baseline(receipt.get("passwordLastSetUtc"))
    store_updated = utc_baseline(receipt.get("protectedStoreUpdatedUtc"))
    auth_observed = utc_baseline(receipt.get("authenticatedGuest", {}).get("sourceObservedUtc"))
    if expiry <= datetime.now(timezone.utc) or not last_set <= store_updated <= auth_observed < expiry:
        raise ValueError("accepted baseline account expiry is unknown or elapsed")
    nested = receipt.get("nestedL2", {})
    inventories = nested.get("backendInventories")
    sources = receipt.get("sources") or {}
    if (receipt.get("adoptionAuthority", {}).get("decision") != "APPROVE"
            or receipt.get("adoptionAuthority", {}).get("approvedBy") != "ACCOUNT_OWNER"
            or receipt.get("adoptionAuthority", {}).get("sourceSha256") != sources.get("approvalSha256")
            or receipt.get("authenticatedGuest", {}).get("computerName") != "DEVFLEET-E2E-01"
            or receipt.get("authenticatedGuest", {}).get("principal") != "DEVFLEET-E2E-01\\E2EAdmin"
            or receipt.get("authenticatedGuest", {}).get("accountEnabled") is not True
            or nested.get("status") != "ABSENT" or nested.get("present") is not False
            or nested.get("expectedName") != "DevFleet-E2E-Linux-01"
            or type(nested.get("exactMatchCount")) is not int or nested.get("exactMatchCount") != 0
            or not isinstance(inventories, list) or len(inventories) != 2
            or not all(isinstance(row, dict) for row in inventories)
            or {row.get("provider") for row in inventories} != {"Hyper-V", "VirtualBox"}
            or any(row.get("status") != "PASS" or not isinstance(row.get("names"), list)
                   or any(not isinstance(n, str) or not n.strip() or n == "DevFleet-E2E-Linux-01"
                          for n in row["names"])
                   or not isinstance(row.get("verification"), str)
                   or not row["verification"].strip() for row in inventories)
            or receipt.get("finalL1") != {"name": "DevFleet-E2E-Win11-01",
                                           "id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2",
                                           "state": "Off"}):
        raise ValueError("accepted baseline guest, nested inventory, approval, or L1 terminal state is invalid")
    for key in ("proposalSha256", "predecessorEvidenceSha256", "approvalSha256",
                "authenticatedGuestSha256", "nativeInventorySha256",
                "currentTupleSha256", "r2LedgerSha256"):
        if not isinstance(sources.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", sources[key]):
            raise ValueError(f"accepted baseline source hash missing: {key}")
    return {"id": new["id"], "name": new["name"], "receiptSha256": pointer["receiptSha256"]}


def validate_native_proof(run: Path, config_path: Path, sources: dict[str, Path], expected: dict[str, str], artifacts: dict[str, str], baseline: dict[str, str | None] | None = None) -> tuple[str, str, str]:
    """Validate immutable start provenance against terminal native product evidence."""
    start, final = read_json(run / "proof-start.json"), read_json(run / "proof-final.json")
    provenance = start.get("provenance", {})
    if start.get("runId") != run.name or final.get("runId") != run.name:
        raise ValueError("proof RunId disagreement")
    if final.get("status") != "PASS" or final.get("outcome") != "PASS":
        raise ValueError("proof terminal status/outcome disagreement")
    if provenance.get("diagnosticOnly") is not False or provenance.get("certificationEligible") is not True or final.get("diagnosticOnly") is not False or final.get("certificationEligible") is not True:
        raise ValueError("diagnostic or ineligible proof cannot receive release credit")
    if final.get("proofStartSha256") != sha(run / "proof-start.json") or final.get("provenance") != provenance:
        raise ValueError("proof terminal provenance does not bind its immutable start")
    for key, value in expected.items():
        if provenance.get(key) != value:
            raise ValueError(f"proof tuple mismatch: {key}")
    for key, source in sources.items():
        if provenance.get(key) != sha(source):
            raise ValueError(f"proof source hash missing or mismatched: {key}")
    if final.get("candidate") != start.get("candidate"):
        raise ValueError("proof start/final artifact tuple disagreement")
    for name, field in (("exe", "candidate"), ("tar", "tar"), ("portable", "portable"), ("installerSource", "installerSource")):
        if not re.fullmatch(r"[0-9a-f]{64}", artifacts.get(name, "")) or final.get("candidate", {}).get(field, {}).get("sha256") != artifacts[name]:
            raise ValueError(f"proof artifact differs from current candidate: {name}")
    for key, field in (("repositoryHead", "repositoryHead"), ("candidateCommit", "gitCommit"), ("shippingInputIdentity", "shippingInputIdentity"), ("releaseFingerprint", "releaseFingerprintId"), ("toolingFingerprint", "toolingFingerprintId")):
        if final.get("candidate", {}).get(field) != expected[key]:
            raise ValueError(f"proof terminal candidate tuple mismatch: {field}")
    binding = final.get("proofBinding", {})
    tx, lineage, role = binding.get("transactionId", ""), binding.get("checkpointLineageId", ""), binding.get("role", "")
    if not re.fullmatch(r"[0-9a-f]{32}", tx) or not re.fullmatch(r"[0-9a-f]{32}", lineage):
        raise ValueError("proof lacks native transaction or invocation lineage")
    if final.get("transactionId") != tx or final.get("checkpointLineageId") != lineage or final.get("role") != role or provenance.get("role") != role:
        raise ValueError("proof terminal identity disagreement")
    phases = {"Primary / Desktop": "REBOOT-RESUME", "Laptop / Surrogate": "SURROGATE-DISPOSABLE"}
    if role not in phases or binding.get("phaseId") != phases[role] or provenance.get("phaseId") != phases[role]:
        raise ValueError("proof role/phase disagreement")
    if baseline is None:
        baseline = {"id": "19865b76-4c3a-44f7-ba39-841e9d3c40c9", "name": "DevFleet-E2E-CLEAN", "receiptSha256": None}
    if provenance.get("cleanCheckpointId") != baseline["id"]:
        raise ValueError("proof does not bind accepted CLEAN checkpoint identity")
    if baseline["receiptSha256"] is not None:
        if (provenance.get("cleanCheckpointName") != baseline["name"]
                or provenance.get("baselineReceiptSha256") != baseline["receiptSha256"]
                or final.get("cleanCheckpoint", {}).get("id") != baseline["id"]
                or final.get("cleanCheckpoint", {}).get("name") != baseline["name"]):
            raise ValueError("proof does not bind the immutable accepted baseline receipt")
    elif provenance.get("baselineReceiptSha256") not in (None, ""):
        raise ValueError("original CLEAN proof cannot claim an adoption receipt")
    payload = start["candidate"]["tar"]["sha256"]
    if binding.get("payloadSha256") != payload:
        raise ValueError("proof payload differs from the signed candidate")
    records = binding.get("evidence", [])
    files = [record.get("file", "") for record in records]
    if len(files) != len(set(files)) or files.count("product-lifecycle-completion-authority.json") != 1:
        raise ValueError("proof native evidence missing or duplicated")
    for record in records:
        name = record.get("file", "")
        if not re.fullmatch(r"product-lifecycle-(?:completion-authority|generation-[1-3])\.json", name) or record.get("sha256") != sha(run / name):
            raise ValueError("proof native evidence path/hash mismatch")
    authority = read_json(run / "product-lifecycle-completion-authority.json")
    if authority.get("status") != "REAL E2E PASS" or authority.get("contract") != "product-lifecycle-completion-authority" or authority.get("completionVerified") is not True or authority.get("authenticatedHealth") is not True:
        raise ValueError("proof native completion authority is incomplete")
    if (authority.get("transactionId"), authority.get("invocationId"), authority.get("role"), authority.get("payloadSha256")) != (tx, lineage, role, payload):
        raise ValueError("proof native completion identity disagreement")
    guest = authority.get("guest", {})
    if guest.get("completionVerified") is not True or guest.get("transactionId") != tx or guest.get("role") != role:
        raise ValueError("proof native guest completion disagreement")
    role_evidence = guest.get("roleEvidence", {})
    if role_evidence != binding.get("roleEvidence") or role_evidence.get("configSha256") != sha(config_path):
        raise ValueError("proof role evidence is not candidate-config bound")
    config = read_json(config_path)
    targets = [(config["Primary"]["InstanceName"], "primary")] if role == "Primary / Desktop" else [(config["Failover"]["InstanceName"], "surrogate"), (config["Vault"]["InstanceName"], "vault")]
    required = [(entry.get("instanceName"), entry.get("nodeRole")) for entry in role_evidence.get("requiredTargets", [])]
    markers = role_evidence.get("markers", [])
    observed = [(entry.get("instanceName"), entry.get("nodeRole")) for entry in markers]
    if sorted(required) != sorted(targets) or sorted(observed) != sorted(targets):
        raise ValueError("proof lacks exact role target coverage")
    for entry in markers:
        marker = entry.get("marker", {})
        if (marker.get("transactionId"), marker.get("payloadSha256"), marker.get("nodeRole"), marker.get("component"), marker.get("state")) != (tx, payload, entry["nodeRole"], "bootstrap", "COMPLETED"):
            raise ValueError("proof target bootstrap has not completed")
    generation_files = sorted(name for name in files if name.startswith("product-lifecycle-generation-"))
    if not generation_files or generation_files != [f"product-lifecycle-generation-{i}.json" for i in range(1, len(generation_files) + 1)]:
        raise ValueError("proof reboot generations are missing or noncontiguous")
    for number, name in enumerate(generation_files, 1):
        generation = read_json(run / name)
        reboot = generation.get("reboot", {})
        checkpoint = reboot.get("checkpoint", {})
        if generation.get("generation") != number or generation.get("invocationId") != lineage or reboot.get("bootIdentityChanged") is not True or generation.get("resume", {}).get("status") != "REAL E2E OBSERVER HANDOFF":
            raise ValueError("proof lacks changed boot and resumed WPF evidence")
        if (checkpoint.get("transactionId"), checkpoint.get("payloadSha256"), checkpoint.get("role"), checkpoint.get("action")) != (tx, payload, role, "FreshInstall"):
            raise ValueError("proof reboot checkpoint identity disagreement")
    return tx, lineage, role


def validate_proof_independence(run_ids, transactions, lineages, roles):
    if len(run_ids) != 2 or len(set(run_ids)) != 2:
        raise ValueError("release bundle does not contain two independent passing proof runs")
    if len(transactions) != 2 or len(set(transactions)) != 2:
        raise ValueError("proof runs reuse a transaction identity")
    if len(lineages) != 2 or len(set(lineages)) != 2:
        raise ValueError("proof runs reuse checkpoint lineage")
    if set(roles) != {"Primary / Desktop", "Laptop / Surrogate"}:
        raise ValueError("release proofs lack Desktop and Laptop/Surrogate role coverage")


def _safe_relative(value: object, label: str) -> str:
    relative = str(value or "").replace("\\", "/")
    path = PurePosixPath(relative)
    if not relative or path.is_absolute() or ".." in path.parts or "." in path.parts or "//" in relative:
        raise ValueError(f"{label} is not a safe relative path")
    return path.as_posix()


def _checked_file(root: Path, relative: object, expected_hash: object, label: str, expected_bytes: object | None = None) -> Path:
    normalized = _safe_relative(relative, label)
    path = root / Path(*PurePosixPath(normalized).parts)
    digest = str(expected_hash or "").lower()
    if not path.is_file() or not re.fullmatch(r"[0-9a-f]{64}", digest) or sha(path) != digest:
        raise ValueError(f"{label} is missing or hash-mismatched")
    if expected_bytes is not None and int(expected_bytes) != path.stat().st_size:
        raise ValueError(f"{label} byte count disagrees")
    return path


def _parse_utc(value: object, label: str) -> datetime:
    text = str(value or "")
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{label} is not a valid ISO-8601 timestamp") from exc
    if parsed.tzinfo is None or parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        raise ValueError(f"{label} is not explicitly UTC")
    return parsed.astimezone(timezone.utc)


def _validate_nested_l2_terminal(
    full_root: Path,
    l2: dict[str, object],
    l1: dict[str, object],
    expected: dict[str, str],
    run_id: str,
) -> None:
    """Require exact current FullRelease evidence captured inside the bound L1."""
    if (l2.get("expectedName") != "DevFleet-E2E-Linux-01" or l2.get("status") != "ABSENT"
            or l2.get("present") is not False or l2.get("runId") != run_id
            or l2.get("sourceRunId") != run_id or l2.get("nestedScope") != "inside the exact L1 guest session"
            or l2.get("l1Name") != "DevFleet-E2E-Win11-01"
            or str(l2.get("l1Id") or "") != "84b7d8b8-ee6c-4085-aa29-4b0adc316de2"
            or l2.get("evidenceClass") != "FullRelease run-bound nested observation"):
        raise ValueError("FullRelease terminal L2 lacks exact current nested scope, L1, and RunId provenance")
    _assert_tuple(l2.get("candidate"), expected, "FullRelease terminal L2")
    source_relative = _safe_relative(l2.get("sourceEvidence"), "nested L2 source evidence")
    if source_relative != "nested-l2-terminal-observation.json":
        raise ValueError("FullRelease nested L2 source is outside its exact run root")
    source_path = full_root / source_relative
    if not source_path.is_file():
        raise ValueError("FullRelease nested L2 source evidence is missing")
    try:
        full_root_absolute = Path(os.path.abspath(full_root))
        source_absolute = Path(os.path.abspath(source_path))
        full_root_resolved = full_root.resolve(strict=True)
        source_resolved = source_path.resolve(strict=True)
    except OSError as exc:
        raise ValueError("FullRelease nested L2 source path cannot be resolved safely") from exc
    if (os.path.normcase(str(full_root_absolute)) != os.path.normcase(str(full_root_resolved))
            or os.path.normcase(str(source_absolute)) != os.path.normcase(str(source_resolved))):
        raise ValueError("FullRelease nested L2 source path contains a reparse or symlink escape")
    raw = source_path.read_bytes()
    source_hash = hashlib.sha256(raw).hexdigest()
    if not re.fullmatch(r"[0-9a-f]{64}", str(l2.get("sourceEvidenceSha256") or "").lower()) or source_hash != str(l2.get("sourceEvidenceSha256")).lower():
        raise ValueError("FullRelease nested L2 source evidence hash mismatch")
    try:
        nested = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("FullRelease nested L2 source evidence is malformed") from exc
    if not isinstance(nested, dict):
        raise ValueError("FullRelease nested L2 source evidence is not an object")
    if (nested.get("runId") != run_id or nested.get("status") != "ABSENT" or nested.get("present") is not False
            or nested.get("expectedName") != "DevFleet-E2E-Linux-01"
            or nested.get("nestedScope") != "inside the exact L1 guest session"
            or nested.get("observer") != "Get-DevFleetNestedL2State"
            or nested.get("evidenceClass") != "FullRelease run-bound nested observation"
            or not isinstance(nested.get("l1"), dict)
            or nested["l1"].get("name") != "DevFleet-E2E-Win11-01"
            or str(nested["l1"].get("id") or "") != "84b7d8b8-ee6c-4085-aa29-4b0adc316de2"):
        raise ValueError("FullRelease nested L2 source record does not support exact absence")
    _assert_tuple(nested.get("candidate"), expected, "nested L2 source")
    if str(l2.get("verificationMethod") or "") != str(nested.get("verification") or ""):
        raise ValueError("FullRelease terminal L2 verification method changed from its source")
    exact_match_count = nested.get("exactMatchCount")
    if isinstance(exact_match_count, bool) or not isinstance(exact_match_count, int) or exact_match_count != 0:
        raise ValueError("FullRelease nested L2 inventory did not record zero exact matches")
    verification = str(nested.get("verification") or "")
    if verification == "Bounded Multipass JSON inventory inside exact L1":
        count = nested.get("inventoryCount")
        if isinstance(count, bool) or not isinstance(count, int) or count < 0:
            raise ValueError("FullRelease Multipass inventory completeness is missing")
    elif verification == "Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend":
        inventories = nested.get("backendInventories")
        if not isinstance(inventories, list) or len(inventories) != 2:
            raise ValueError("FullRelease nested inventory does not contain the complete supported backend set")
        providers: set[str] = set()
        for row in inventories:
            if not isinstance(row, dict):
                raise ValueError("FullRelease nested backend inventory row is malformed")
            provider = str(row.get("provider") or "")
            if provider not in {"Hyper-V", "VirtualBox"} or provider in providers or row.get("status") != "PASS" or not isinstance(row.get("names"), list) or not str(row.get("verification") or ""):
                raise ValueError("FullRelease nested backend inventory is incomplete or ambiguous")
            if any(not isinstance(name, str) or not name for name in row["names"]):
                raise ValueError("FullRelease nested backend inventory contains an invalid instance name")
            if len(set(row["names"])) != len(row["names"]):
                raise ValueError("FullRelease nested backend inventory contains a duplicate instance name")
            if "DevFleet-E2E-Linux-01" in row["names"]:
                raise ValueError("FullRelease nested backend inventory still contains the expected L2")
            providers.add(provider)
        if providers != {"Hyper-V", "VirtualBox"}:
            raise ValueError("FullRelease nested backend inventory omitted a supported provider")
    else:
        raise ValueError("FullRelease nested L2 observation method is not a supported complete inventory")
    nested_time = _parse_utc(nested.get("observedUtc"), "nested L2 observation time")
    if str(l2.get("timestampUtc") or l2.get("timestamp") or "") != str(nested.get("observedUtc") or ""):
        raise ValueError("FullRelease terminal L2 timestamp was rewritten after the nested observation")
    l1_time = _parse_utc(l1.get("timestampUtc") or l1.get("timestamp"), "L1 terminal observation time")
    if nested_time > l1_time:
        raise ValueError("FullRelease nested L2 observation occurred after L1 shutdown")


def _tuple_from_state(state: dict[str, object]) -> dict[str, str]:
    result = {
        "repositoryHead": str(state.get("repository_head") or state.get("repositoryHead") or ""),
        "candidateCommit": str(state.get("candidate_git_commit") or state.get("candidateGitCommit") or ""),
        "shippingInputIdentity": str(state.get("shipping_input_identity") or state.get("shippingInputIdentity") or ""),
        "releaseFingerprintId": str(state.get("releaseFingerprintId") or ""),
        "toolingFingerprintId": str(state.get("toolingFingerprintId") or ""),
    }
    for name, value in result.items():
        size = 40 if name in {"repositoryHead", "candidateCommit"} else 64
        if not re.fullmatch(rf"[0-9a-f]{{{size}}}", value):
            raise ValueError(f"current authority tuple is malformed: {name}")
    return result


def _artifact_map(root: Path) -> dict[str, dict[str, object]]:
    release = read_json(root / "outputs/release-fingerprint.json")
    rows = release.get("artifacts") if isinstance(release, dict) else None
    if not isinstance(rows, list):
        raise ValueError("release fingerprint artifact rows are missing")
    result = {str(row.get("name")): row for row in rows if isinstance(row, dict)}
    if set(result) != {"exe", "tar", "portable", "installerSource"}:
        raise ValueError("release fingerprint does not contain the exact artifact tuple")
    for name, row in result.items():
        if not re.fullmatch(r"[0-9a-f]{64}", str(row.get("sha256") or "")) or int(row.get("bytes", 0)) <= 0:
            raise ValueError(f"release artifact identity is malformed: {name}")
    return result


def _assert_tuple(record: object, expected: dict[str, str], label: str, *, proof_names: bool = False) -> None:
    if not isinstance(record, dict):
        raise ValueError(f"{label} tuple is missing")
    aliases = {
        "repositoryHead": ("repositoryHead", "repository_head"),
        "candidateCommit": ("candidateCommit", "candidateGitCommit", "candidateBuildCommit", "candidate_git_commit", "gitCommit"),
        "shippingInputIdentity": ("shippingInputIdentity", "shipping_input_identity"),
        "releaseFingerprintId": (("releaseFingerprint", "releaseFingerprintId") if proof_names else ("releaseFingerprintId", "releaseFingerprint")),
        "toolingFingerprintId": (("toolingFingerprint", "toolingFingerprintId") if proof_names else ("toolingFingerprintId", "toolingFingerprint")),
    }
    for canonical, names in aliases.items():
        observed = next((str(record.get(name)) for name in names if record.get(name)), "")
        if observed != expected[canonical]:
            raise ValueError(f"{label} tuple mismatch: {canonical}")


def _layout_path(layout: str, workspace_path: str, bundle_path: str) -> str:
    return workspace_path if layout == "workspace" else bundle_path


def _validate_standard_token(root: Path, expected: dict[str, str], artifacts: dict[str, dict[str, object]], layout: str) -> dict[str, object]:
    pointer_path = root / "evidence/CURRENT-STANDARD-TOKEN.json"
    if not pointer_path.is_file():
        raise ValueError("CURRENT-STANDARD-TOKEN.json is missing")
    pointer = read_json(pointer_path)
    run_id = str(pointer.get("runId") or "")
    if not re.fullmatch(r"standard-token-[A-Za-z0-9-]+", run_id):
        raise ValueError("standard-token RunId is malformed")
    workspace_root = f"evidence/standard-token/{run_id}"
    bundle_root = f"evidence/standard-token/{run_id}"
    raw_relative = _layout_path(layout, f"{workspace_root}/installer-self-test-raw.txt", f"{bundle_root}/installer-self-test-raw.txt")
    canonical_relative = _layout_path(layout, f"{workspace_root}/standard-token-evidence.json", f"{bundle_root}/standard-token-evidence.json")
    raw = root / raw_relative
    canonical_path = root / canonical_relative
    if not raw.is_file() or not canonical_path.is_file():
        raise ValueError("immutable standard-token raw/canonical evidence is missing")
    canonical = read_json(canonical_path)
    if pointer != canonical:
        raise ValueError("CURRENT-STANDARD-TOKEN does not exactly match its immutable canonical evidence")
    if pointer.get("schemaVersion") != 1 or pointer.get("status") != "PASS" or pointer.get("standardNonAdministratorToken") is not True or pointer.get("exitCode") != 0 or pointer.get("residualSelfTestScratchCount") != 0:
        raise ValueError("standard-token result is not a genuine clean PASS")
    _assert_tuple(pointer, expected, "standard-token")
    if pointer.get("candidateBuildCommit") != expected["candidateCommit"]:
        raise ValueError("standard-token candidate build commit is stale")
    if pointer.get("runDirectory") != workspace_root or pointer.get("rawReportPath") != f"{workspace_root}/installer-self-test-raw.txt" or pointer.get("canonicalEvidencePath") != f"{workspace_root}/standard-token-evidence.json":
        raise ValueError("standard-token immutable paths are not canonical")
    required = pointer.get("requiredChecks")
    if not isinstance(required, dict) or set(required) != STANDARD_TOKEN_CHECKS or any(value is not True for value in required.values()):
        raise ValueError("standard-token required checks are missing, renamed, or false")
    token = pointer.get("token")
    if (not isinstance(token, dict) or token.get("standardNonAdministratorToken") is not True
            or token.get("isAdministratorMember") is not False or token.get("isAdministratorEnabled") is not False
            or token.get("isElevated") is not False or token.get("integrityLevel") not in {"Medium", "MediumPlus"}):
        raise ValueError("standard-token native token evidence is not a medium non-administrator token")
    if str(pointer.get("reportSha256") or "").lower() != sha(raw):
        raise ValueError("standard-token raw report hash mismatch")
    text = raw.read_text(encoding="utf-8-sig")
    if not re.search(r"(?m)^PASS\s*$", text) or f"payload={artifacts['tar']['sha256']}" not in text:
        raise ValueError("standard-token raw report does not bind PASS and the exact payload")
    for name in ("exe", "tar"):
        row = pointer.get(name)
        if not isinstance(row, dict) or str(row.get("sha256")) != str(artifacts[name]["sha256"]) or int(row.get("bytes", -1)) != int(artifacts[name]["bytes"]):
            raise ValueError(f"standard-token artifact mismatch: {name}")
    runner = pointer.get("runner")
    runner_relative = "automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1"
    if not isinstance(runner, dict) or runner.get("path") != runner_relative or str(runner.get("sha256") or "").lower() != sha(root / runner_relative):
        raise ValueError("standard-token runner bytes are missing or changed")
    return {
        "runId": run_id,
        "pointerSha256": sha(pointer_path),
        "canonicalSha256": sha(canonical_path),
        "rawReportSha256": sha(raw),
        "pointerPath": "evidence/CURRENT-STANDARD-TOKEN.json",
        "canonicalPath": canonical_relative,
        "rawReportPath": raw_relative,
    }


def _validate_real_use(record: dict[str, object], binding_path: Path, prepare_path: Path, report_path: Path, expected: dict[str, str], run_id: str) -> dict[str, object]:
    evidence = record.get("evidence") if isinstance(record, dict) else None
    executor = evidence.get("executor") if isinstance(evidence, dict) else None
    if not isinstance(executor, dict) or executor.get("status") != "REAL E2E PASS" or executor.get("phase") != "REAL-USE-ACCEPTANCE" or executor.get("contract") != "devfleet-real-use-acceptance-phase-v1":
        raise ValueError("FullRelease REAL-USE-ACCEPTANCE is not an explicit REAL E2E PASS")
    _assert_tuple(executor.get("candidate"), expected, "REAL-USE-ACCEPTANCE")
    binding = read_json(binding_path)
    if binding.get("schemaVersion") != 1 or binding.get("contract") != "devfleet-real-use-acceptance-v1" or binding.get("runId") != run_id or binding.get("phaseId") != "REAL-USE-ACCEPTANCE" or binding.get("precedingPhase") != "SURROGATE-DISPOSABLE":
        raise ValueError("REAL-USE-ACCEPTANCE durable binding contract is invalid")
    _assert_tuple(binding.get("candidate"), expected, "REAL-USE-ACCEPTANCE binding")
    prepare = read_json(prepare_path)
    if prepare.get("schemaVersion") != 1 or prepare.get("contract") != "devfleet-real-use-acceptance-v1" or prepare.get("status") != "PREPARED" or prepare.get("stage") != "prepare" or prepare.get("runId") != run_id or prepare.get("phaseId") != "REAL-USE-ACCEPTANCE":
        raise ValueError("REAL-USE-ACCEPTANCE durable prepare report is invalid")
    _assert_tuple(prepare.get("candidate"), expected, "REAL-USE-ACCEPTANCE prepare")
    report = read_json(report_path)
    if report.get("schemaVersion") != 1 or report.get("contract") != "devfleet-real-use-acceptance-v1" or report.get("status") != "PASS" or report.get("stage") != "resume" or report.get("phaseId") != "REAL-USE-ACCEPTANCE" or report.get("runId") != run_id:
        raise ValueError("REAL-USE-ACCEPTANCE report contract/status/RunId is invalid")
    _assert_tuple(report.get("candidate"), expected, "REAL-USE-ACCEPTANCE report")
    journeys = report.get("journeys")
    if not isinstance(journeys, list) or [row.get("id") for row in journeys if isinstance(row, dict)] != ["U01", "U02", "U03", "U04", "U05"] or any(row.get("status") != "PASS" for row in journeys if isinstance(row, dict)):
        raise ValueError("REAL-USE-ACCEPTANCE report does not contain ordered U01-U05 PASS")
    for row in journeys:
        assertions = row.get("assertions") if isinstance(row, dict) else None
        if not isinstance(assertions, dict) or not assertions or any(value is not True for value in assertions.values()):
            raise ValueError("REAL-USE-ACCEPTANCE journey contains an unproven assertion")
    cleanup = report.get("cleanup")
    if not isinstance(cleanup, dict) or cleanup.get("status") != "PASS" or cleanup.get("ownedOnly") is not True or cleanup.get("errors") not in ([], None) or report.get("failure") is not None or report.get("cleanupFailure") is not None:
        raise ValueError("REAL-USE-ACCEPTANCE cleanup is not a clean owned-only PASS")
    evidence_binding = executor.get("evidence")
    expected_files = {
        "binding": (binding_path, "bindingPath", "bindingSha256"),
        "prepare": (prepare_path, "preparePath", "prepareSha256"),
        "report": (report_path, "reportPath", "reportSha256"),
    }
    if not isinstance(evidence_binding, dict):
        raise ValueError("REAL-USE-ACCEPTANCE phase evidence bindings are missing")
    for label, (path, path_key, hash_key) in expected_files.items():
        if Path(str(evidence_binding.get(path_key) or "")).name != path.name or str(evidence_binding.get(hash_key) or "").lower() != sha(path):
            raise ValueError(f"REAL-USE-ACCEPTANCE phase does not bind durable {label} bytes")
    if executor.get("credentialsStoredInEvidence") is not False or executor.get("internalPromotionAllowed") is not False:
        raise ValueError("REAL-USE-ACCEPTANCE phase is not secret-safe/non-promoting")
    return {"bindingSha256": sha(binding_path), "prepareSha256": sha(prepare_path), "reportSha256": sha(report_path), "journeys": [row["id"] for row in journeys]}


def _canonical_shipping_rows(rows: list[object]) -> list[dict[str, object]]:
    """Normalize and order rows exactly like the candidate-bound validator."""
    normalized: list[dict[str, object]] = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("candidate shipping row is not an object")
        mode = str(row.get("mode") or "")
        if mode not in {"0644", "0755"}:
            raise ValueError("candidate shipping row has a missing or invalid mode")
        root = str(row.get("root") or "").replace("\\", "/").strip("/")
        path = str(row.get("path") or "").replace("\\", "/").lstrip("/")
        if root not in {"source", "installer-source"} or not path or ".." in PurePosixPath(path).parts:
            raise ValueError("candidate shipping row has an invalid path")
        normalized.append({"root": root, "path": path, "bytes": int(row.get("bytes", -1)), "sha256": str(row.get("sha256") or "").lower(), "mode": mode})
    return sorted(normalized, key=lambda row: (0 if row["root"] == "source" else 1, tuple(part.casefold() for part in str(row["path"]).split("/"))))


def _candidate_shipping_identity(rows: list[object], version: object, installer: object, mode: object) -> str:
    payload = {"schemaVersion": 1, "devfleetVersion": version, "installerVersion": installer, "shippingModeContract": mode, "shippingInputs": _canonical_shipping_rows(rows)}
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def _validate_candidate_bound(root: Path, mode: str) -> dict[str, object]:
    script = root / "source/tools/validate_audit_coherence.py"
    if not script.is_file():
        raise ValueError("candidate-bound validator is missing from the bundle")
    try:
        completed = subprocess.run([sys.executable, str(script), "--root", str(root), "--mode", mode], capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ValueError("candidate-bound validator could not be executed") from exc
    if completed.returncode != 0:
        raise ValueError(f"candidate-bound validator failed: {(completed.stderr or completed.stdout)[-2000:]}")
    try:
        result = json.loads(completed.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError) as exc:
        raise ValueError("candidate-bound validator did not return JSON") from exc
    expected = "PASS_WITH_BLOCKER" if mode == "diagnostic" else "PASS"
    if result.get("status") != expected:
        raise ValueError(f"candidate-bound validator returned {result.get('status')!r}, expected {expected!r}")
    if mode == "diagnostic" and result.get("releaseEligible") is not False:
        raise ValueError("candidate-bound diagnostic result is release eligible")
    return result


def _current_release_paths(root: Path, layout: str, state: dict[str, object]) -> tuple[Path, Path]:
    if layout == "bundle":
        return root / "evidence/current-fullrelease", root / "evidence/proof-runs"
    run_id = str(state.get("full_release_run_id") or "")
    if not run_id or not re.fullmatch(r"(?:e2e-)?fullrelease-[A-Za-z0-9-]+", run_id, re.IGNORECASE):
        raise ValueError("current FullRelease RunId is missing or malformed")
    return root / "audit/automation-harness/runs" / run_id, root / "audit/automation-harness/runs"


def _validate_workspace_candidate(root: Path, expected: dict[str, str], artifacts: dict[str, dict[str, object]]) -> None:
    head = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=30)
    if head.returncode != 0 or head.stdout.strip() != expected["repositoryHead"]:
        raise ValueError("live repository HEAD differs from the accepted tuple")
    manifest = read_json(root / "outputs/final-artifact-hashes.json")
    _assert_tuple(manifest, expected, "final artifact manifest")
    release_record = read_json(root / "outputs/release-fingerprint.json")
    tooling_record = read_json(root / "outputs/tooling-fingerprint-current.json")
    if release_record.get("releaseFingerprintId") != expected["releaseFingerprintId"] or not isinstance(release_record.get("toolingFingerprint"), dict) or release_record["toolingFingerprint"].get("toolingFingerprintId") != expected["toolingFingerprintId"]:
        raise ValueError("release fingerprint record disagrees with the accepted tuple")
    _assert_tuple(tooling_record, expected, "current tooling fingerprint")
    rows = manifest.get("artifacts")
    if not isinstance(rows, list) or {str(row.get("name")) for row in rows if isinstance(row, dict)} != set(artifacts):
        raise ValueError("final artifact manifest does not contain the exact artifact tuple")
    for row in rows:
        name = str(row["name"])
        expected_row = artifacts[name]
        if str(row.get("sha256") or "") != str(expected_row["sha256"]) or int(row.get("bytes", -1)) != int(expected_row["bytes"]):
            raise ValueError(f"final artifact manifest disagrees with release fingerprint: {name}")
        _checked_file(root, row.get("path"), row.get("sha256"), f"signed candidate artifact {name}", row.get("bytes"))
    certificate = manifest.get("publicCertificate")
    if not isinstance(certificate, dict):
        raise ValueError("public signing certificate identity is missing")
    _checked_file(root, certificate.get("path"), certificate.get("sha256"), "public signing certificate", certificate.get("bytes"))
    signing = read_json(root / "outputs/SIGNING-PROVIDER.json")
    final_exe = signing.get("finalSignedExe") if isinstance(signing, dict) else None
    if (signing.get("signatureStatus") != "Valid" or signing.get("signerThumbprint") != "DE42CD7369A01E9357BDA13597C0173E5E703E9D"
            or signing.get("signerSubject") != "CN=DevFleet Private Personal Code Signing"
            or signing.get("codeSigningEkuVerified") is not True or signing.get("rsaBits") != 3072
            or signing.get("privateKeyExportable") is not False or signing.get("privateKeyExported") is not False
            or signing.get("publicPublisherTrust") is not False or signing.get("publicPromotionAllowed") is not False
            or not isinstance(final_exe, dict) or final_exe.get("sha256") != artifacts["exe"]["sha256"] or int(final_exe.get("bytes", -1)) != int(artifacts["exe"]["bytes"])):
        raise ValueError("signing provider record is incomplete or disagrees with the signed EXE")
    identity_tool = root / "tools/compute_shipping_input_identity.py"
    manifest_artifact_paths: dict[str, Path] = {}
    for row in rows:
        name = str(row["name"])
        manifest_artifact_paths[name] = _checked_file(
            root, row.get("path"), row.get("sha256"),
            f"signed candidate artifact {name}", row.get("bytes"),
        )
    identity_arguments = [
        sys.executable, str(identity_tool),
        "--workspace", str(root), "--candidate-commit", expected["candidateCommit"],
    ]
    for name in sorted(artifacts):
        identity_arguments.extend(["--artifact", f"{name}={manifest_artifact_paths[name]}"])
    completed = subprocess.run(
        identity_arguments,
        capture_output=True, text=True, timeout=180,
    )
    if completed.returncode != 0:
        raise ValueError(f"live candidate identity recomputation failed: {(completed.stderr or completed.stdout)[-1000:]}")
    try:
        identity = json.loads(completed.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError) as exc:
        raise ValueError("live candidate identity recomputation did not return JSON") from exc
    exact = identity.get("liveShippingInputIdentity") == expected["shippingInputIdentity"]
    eol_only = identity.get("crlfOnlyMaterialization") is True and identity.get("candidateShippingInputIdentity") == expected["shippingInputIdentity"]
    if not exact and not eol_only:
        raise ValueError("live shipping inputs differ from the signed candidate")
    observed_release = identity.get("liveReleaseFingerprintId") if exact else identity.get("candidateReleaseFingerprintId")
    if observed_release != expected["releaseFingerprintId"]:
        raise ValueError("live/canonical release fingerprint differs from the accepted tuple")
    live_tooling = identity.get("liveToolingFingerprint")
    if not isinstance(live_tooling, dict) or live_tooling.get("toolingFingerprintId") != expected["toolingFingerprintId"]:
        raise ValueError("live tooling fingerprint differs from the accepted tuple")


def _validate_current_release_evidence(root: Path, layout: str) -> dict[str, object]:
    state = read_json(root / "finalization-state.json")
    expected = _tuple_from_state(state)
    artifacts = _artifact_map(root)
    if layout == "workspace":
        _validate_workspace_candidate(root, expected, artifacts)
    full_root, proof_root = _current_release_paths(root, layout, state)
    run_state_path = full_root / "run-state.json"
    records_path = full_root / "fullrelease-phase-records.json"
    if not run_state_path.is_file() or not records_path.is_file():
        raise ValueError("current FullRelease run-state or phase records are missing")
    run_state = read_json(run_state_path)
    run_id = str(run_state.get("runId") or "")
    if run_id != str(state.get("full_release_run_id") or run_id) or run_state.get("mode") != "FullRelease" or run_state.get("finalStatus") != "PASS":
        raise ValueError("current FullRelease is not one coherent terminal PASS")
    _assert_tuple(run_state.get("candidateHashes"), expected, "FullRelease run-state")
    full_summary = read_json(root / "evidence/FULLRELEASE-SUMMARY.json")
    if (full_summary.get("latestRunId") != run_id or full_summary.get("status") != "PASS" or full_summary.get("historicalEvidenceOnly") is not False):
        raise ValueError("FULLRELEASE-SUMMARY is not the current terminal PASS")
    _assert_tuple(full_summary.get("candidateTuple"), expected, "FULLRELEASE-SUMMARY")
    full_hashes = run_state.get("candidateHashes")
    for name in ("exe", "tar", "portable", "installerSource"):
        if not isinstance(full_hashes, dict) or str(full_hashes.get(name) or "") != str(artifacts[name]["sha256"]):
            raise ValueError(f"FullRelease artifact tuple mismatch: {name}")
    records = read_json(records_path)
    if not isinstance(records, list):
        raise ValueError("FullRelease phase records are not a list")
    by_id: dict[str, dict[str, object]] = {}
    record_ids: list[str] = []
    for row in records:
        if isinstance(row, dict) and row.get("id"):
            phase_id = str(row["id"])
            record_ids.append(phase_id)
            by_id[phase_id] = row
            if row.get("runId") and row.get("runId") != run_id:
                raise ValueError(f"FullRelease phase record is spliced to another RunId: {phase_id}")
    if len(record_ids) != len(set(record_ids)):
        raise ValueError("FullRelease phase records contain duplicate phase IDs")
    missing = sorted(REQUIRED_FULLRELEASE_PHASES - set(by_id))
    failed = sorted(phase for phase in REQUIRED_FULLRELEASE_PHASES if phase in by_id and by_id[phase].get("status") != "PASS")
    if missing or failed:
        raise ValueError(f"FullRelease mandatory phase closure is incomplete; missing={missing}; notPass={failed}")
    completed = set(str(value) for value in run_state.get("completedPhases", []) if value)
    if not REQUIRED_FULLRELEASE_PHASES.issubset(completed):
        raise ValueError("FullRelease run-state does not record every mandatory phase as completed")
    host = by_id["HOST-SAFETY"].get("evidence")
    if (not isinstance(host, dict) or host.get("startSafe") is not True
            or host.get("rawHostSafetyStartSafe") is not True
            or host.get("effectiveE2EStartAuthorized") is not True
            or host.get("ramPressureOverrideAuthorized") is not False):
        raise ValueError("FullRelease HOST-SAFETY is not a native no-override PASS")
    maintenance = [by_id[name] for name in sorted(MAINTENANCE_PHASES)]
    if len(maintenance) != 5 or any(row.get("status") != "PASS" for row in maintenance):
        raise ValueError("FullRelease maintenance is not 5/5 PASS")
    real_binding_path = full_root / "real-use-acceptance-binding.json"
    real_prepare_path = full_root / "real-use-acceptance-prepare.json"
    real_report_path = full_root / "real-use-acceptance-report.json"
    real_summary_path = full_root / "real-use-acceptance-evidence.json"
    if not all(path.is_file() for path in (real_binding_path, real_prepare_path, real_report_path, real_summary_path)):
        raise ValueError("FullRelease durable REAL-USE-ACCEPTANCE binding/prepare/report/summary is missing")
    real_use = _validate_real_use(by_id["REAL-USE-ACCEPTANCE"], real_binding_path, real_prepare_path, real_report_path, expected, run_id)
    real_summary = read_json(real_summary_path)
    if real_summary.get("contract") != "devfleet-real-use-acceptance-evidence-v1" or real_summary.get("status") != "PASS" or real_summary.get("runId") != run_id or real_summary.get("credentialsStoredInEvidence") is not False or real_summary.get("internalPromotionAllowed") is not False or [row.get("id") for row in real_summary.get("journeys", [])] != ["U01", "U02", "U03", "U04", "U05"] or any(row.get("status") != "PASS" for row in real_summary.get("journeys", [])):
        raise ValueError("REAL-USE-ACCEPTANCE durable summary is incomplete")
    summary_evidence = real_summary.get("evidence")
    if not isinstance(summary_evidence, dict):
        raise ValueError("REAL-USE-ACCEPTANCE summary evidence bindings are missing")
    for label in ("binding", "prepare", "report"):
        ref = summary_evidence.get(label)
        if not isinstance(ref, dict) or str(ref.get("sha256") or "").lower() != real_use[f"{label}Sha256"]:
            raise ValueError(f"REAL-USE-ACCEPTANCE summary does not bind durable {label} bytes")
    reconcile = by_id["RECONCILE"].get("evidence")
    reconcile_executor = reconcile.get("executor") if isinstance(reconcile, dict) else None
    if not isinstance(reconcile_executor, dict) or reconcile_executor.get("status") != "REAL E2E PASS" or reconcile_executor.get("phase") != "RECONCILE" or reconcile_executor.get("maintenance") != "5/5":
        raise ValueError("RECONCILE is not a current 5/5 REAL E2E PASS")
    _assert_tuple(reconcile_executor.get("candidate"), expected, "RECONCILE")
    cleanup = read_json(full_root / "final-cleanup.json")
    cleanup_l1 = cleanup.get("l1") if isinstance(cleanup.get("l1"), dict) else {}
    if (cleanup.get("status") != "PASS" or cleanup.get("runId") != run_id or cleanup.get("guest", {}).get("nestedAbsent") is not True or cleanup_l1.get("name") != "DevFleet-E2E-Win11-01"
            or str(cleanup_l1.get("id") or "") != "84b7d8b8-ee6c-4085-aa29-4b0adc316de2"
            or cleanup_l1.get("state") != "Off" or cleanup_l1.get("deleted") is not False
            or cleanup.get("productionTouched") is not False or cleanup.get("physicalSurfaceTouched") is not False
            or cleanup.get("guest", {}).get("runRootAbsent") is not True or cleanup.get("guest", {}).get("foreignResourcesMutated") is not False):
        raise ValueError("certified FullRelease CLEANUP is incomplete or unsafe")
    post_cleanup = read_json(full_root / "post-cleanup-finalization.json")
    if post_cleanup.get("status") != "PASS" or post_cleanup.get("runId") != run_id or post_cleanup.get("cleanupConsumed") is not True or post_cleanup.get("reconcileAfterCleanup") is not True:
        raise ValueError("post-cleanup finalization did not consume current RECONCILE/CLEANUP")
    live_checks = post_cleanup.get("liveChecks")
    if not isinstance(live_checks, dict) or live_checks.get("l1ExactOff") is not True or live_checks.get("l2ExactAbsent") is not True or live_checks.get("hostSameNameL2Absent") is not True or live_checks.get("foreignResourcesMutated") is not False:
        raise ValueError("post-cleanup exact live state is not L1 OFF / L2 ABSENT")
    _assert_tuple(post_cleanup.get("candidate"), expected, "post-cleanup finalization")
    cleanup_hash = str(post_cleanup.get("cleanupEvidenceHash") or "").lower()
    if cleanup_hash != sha(full_root / "final-cleanup.json"):
        raise ValueError("post-cleanup finalization does not bind final-cleanup.json")
    terminal_paths = {
        "terminalL1Hash": full_root / "l1-terminal-state.json",
        "terminalL2Hash": full_root / "l2-terminal-state.json",
    }
    for key, path in terminal_paths.items():
        if str(post_cleanup.get(key) or "").lower() != sha(path):
            raise ValueError(f"post-cleanup finalization does not bind {path.name}")
    l1, l2 = read_json(terminal_paths["terminalL1Hash"]), read_json(terminal_paths["terminalL2Hash"])
    if ((l1.get("name"), str(l1.get("id") or l1.get("vmId")), str(l1.get("state"))) != ("DevFleet-E2E-Win11-01", "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "Off")
            or not (l1.get("timestamp") or l1.get("timestampUtc")) or not l1.get("ownershipScope")):
        raise ValueError("FullRelease terminal L1 is not the exact disposable VM OFF")
    _validate_nested_l2_terminal(full_root, l2, l1, expected, run_id)
    nested_source_path = full_root / "nested-l2-terminal-observation.json"
    if str(post_cleanup.get("nestedL2Observation") or "") != "nested-l2-terminal-observation.json" or str(post_cleanup.get("nestedL2ObservationSha256") or "").lower() != sha(nested_source_path):
        raise ValueError("post-cleanup finalization does not bind the nested L2 source observation")
    if layout == "bundle":
        if sha(root / "evidence/l1-terminal-state.json") != sha(terminal_paths["terminalL1Hash"]) or sha(root / "evidence/l2-terminal-state.json") != sha(terminal_paths["terminalL2Hash"]):
            raise ValueError("bundle root terminal state disagrees with the current FullRelease")
    standard = _validate_standard_token(root, expected, artifacts, layout)

    authority = read_json(root / "evidence/CURRENT-RELEASE-AUTHORITY.json")
    _assert_tuple(authority, expected, "CURRENT-RELEASE-AUTHORITY")
    proof_rows = authority.get("proofs", {}).get("runs") if isinstance(authority.get("proofs"), dict) else None
    if not isinstance(proof_rows, list) or len(proof_rows) != 2:
        raise ValueError("current authority does not select exactly two passing proofs")
    run_ids = [str(row.get("runId") or "") for row in proof_rows if isinstance(row, dict)]
    transactions: list[str] = []
    lineages: list[str] = []
    roles: list[str] = []
    sources = {
        "proofScriptSha256": root / ("audit/run-exact-candidate-proof.ps1" if layout == "workspace" else "release-tooling/proof-entrypoints/run-exact-candidate-proof.ps1"),
        "invokeRealProductPhaseSha256": root / ("automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1" if layout == "workspace" else "release-tooling/proof-entrypoints/Invoke-RealProductPhase.psm1"),
        "invokeWpfUiAutomationSha256": root / ("automation/release-e2e/modules/executors/Invoke-WpfUiAutomation.ps1" if layout == "workspace" else "release-tooling/proof-entrypoints/Invoke-WpfUiAutomation.ps1"),
        "wpfLaunchContractSha256": root / ("automation/release-e2e/modules/executors/WpfLaunchContract.psm1" if layout == "workspace" else "release-tooling/proof-entrypoints/WpfLaunchContract.psm1"),
    }
    config_path = root / "source/config/devfleet.config.json"
    proof_expected = {"repositoryHead": expected["repositoryHead"], "candidateCommit": expected["candidateCommit"], "shippingInputIdentity": expected["shippingInputIdentity"], "releaseFingerprint": expected["releaseFingerprintId"], "toolingFingerprint": expected["toolingFingerprintId"]}
    artifact_hashes = {name: str(row["sha256"]) for name, row in artifacts.items()}
    baseline = load_accepted_baseline(root, expected, artifact_hashes)
    for run_id_value in run_ids:
        run = proof_root / run_id_value
        if layout == "workspace" and not (run / "proof-start.json").is_file():
            raise ValueError(f"current proof run is missing: {run_id_value}")
        tx, lineage, role = validate_native_proof(run, config_path, sources, proof_expected, artifact_hashes, baseline)
        transactions.append(tx); lineages.append(lineage); roles.append(role)
    validate_proof_independence(run_ids, transactions, lineages, roles)
    return {
        "candidateTuple": expected,
        "artifacts": artifacts,
        "fullReleaseRunId": run_id,
        "fullRelease": {
            "runStateSha256": sha(run_state_path), "phaseRecordsSha256": sha(records_path),
            "realUseBindingSha256": real_use["bindingSha256"], "realUsePrepareSha256": real_use["prepareSha256"],
            "realUseReportSha256": real_use["reportSha256"], "realUseSummarySha256": sha(real_summary_path),
            "cleanupSha256": sha(full_root / "final-cleanup.json"), "postCleanupSha256": sha(full_root / "post-cleanup-finalization.json"),
            "l1Sha256": sha(full_root / "l1-terminal-state.json"), "l2Sha256": sha(full_root / "l2-terminal-state.json"),
        },
        "standardToken": standard,
        "proofRunIds": run_ids,
        "proofTransactions": transactions,
        "proofLineages": lineages,
        "proofRoles": roles,
    }


def _validate_release_audit(root: Path, expected: dict[str, str], full_release_run_id: str, layout: str, *, require_archive: bool, closure: dict[str, object] | None = None) -> dict[str, object]:
    pointer_path = root / "evidence/CURRENT-RELEASE-AUDIT.json"
    if not pointer_path.is_file():
        raise ValueError("CURRENT-RELEASE-AUDIT.json is missing")
    pointer = read_json(pointer_path)
    if (pointer.get("schemaVersion") != 1 or pointer.get("contract") != "devfleet-pre-acceptance-release-audit-v1"
            or pointer.get("status") != "PASS" or pointer.get("bundleMode") != "release"
            or pointer.get("releaseEligible") is not False or pointer.get("internalPromotionAllowed") is not False
            or pointer.get("publicPromotionAllowed") is not False or pointer.get("publicPublisherTrust") is not False):
        raise ValueError("pre-acceptance RELEASE audit pointer is not a fail-closed PASS")
    _assert_tuple(pointer.get("candidate"), expected, "pre-acceptance RELEASE audit")
    if pointer.get("fullReleaseRunId") != full_release_run_id:
        raise ValueError("pre-acceptance RELEASE audit is spliced to another FullRelease")
    if closure is not None and (pointer.get("standardTokenRunId") != closure["standardToken"]["runId"] or pointer.get("proofRunIds") != closure["proofRunIds"]):
        raise ValueError("pre-acceptance RELEASE audit standard-token/proof lineage is stale or spliced")
    audit_id = str(pointer.get("runId") or "")
    if not re.fullmatch(r"release-audit-[A-Za-z0-9-]+", audit_id):
        raise ValueError("pre-acceptance RELEASE audit RunId is malformed")
    evidence = pointer.get("evidence")
    if not isinstance(evidence, dict) or set(evidence) != {"archive", "report", "manifest", "releaseValidation"}:
        raise ValueError("pre-acceptance RELEASE audit evidence bindings are missing")
    checked: dict[str, Path] = {}
    for key in ("report", "manifest", "releaseValidation"):
        ref = evidence.get(key)
        if not isinstance(ref, dict):
            raise ValueError(f"pre-acceptance RELEASE audit binding is missing: {key}")
        relative = _layout_path(layout, str(ref.get("workspacePath") or ""), str(ref.get("bundlePath") or ""))
        checked[key] = _checked_file(root, relative, ref.get("sha256"), f"pre-acceptance RELEASE audit {key}", ref.get("bytes"))
    archive_ref = evidence.get("archive")
    if not isinstance(archive_ref, dict) or not re.fullmatch(r"[0-9a-f]{64}", str(archive_ref.get("sha256") or "")) or int(archive_ref.get("bytes", 0)) <= 0:
        raise ValueError("pre-acceptance RELEASE audit archive identity is malformed")
    archive_path: Path | None = None
    if require_archive:
        archive_relative = _layout_path(layout, str(archive_ref.get("workspacePath") or ""), str(archive_ref.get("bundlePath") or ""))
        archive_path = _checked_file(root, archive_relative, archive_ref.get("sha256"), "pre-acceptance RELEASE audit archive", archive_ref.get("bytes"))
    report = read_json(checked["report"])
    if (report.get("status") != "COMPLETE_FOR_AI_AUDIT" or report.get("bundleMode") != "release"
            or report.get("releaseEligible") is not True or report.get("modeVerification") != "PASS"
            or report.get("coherenceVerification") != "PASS" or report.get("secretScan") != "PASS"
            or report.get("internalPromotionAllowed") is not False or report.get("publicPromotionAllowed") is not False
            or report.get("publicPublisherTrust") is not False
            or int(report.get("expectedSourceCount", -1)) <= 0
            or int(report.get("expectedSourceCount", -1)) != int(report.get("includedSourceCount", -2))):
        raise ValueError("pre-acceptance RELEASE audit clean-extraction report is not PASS")
    if str(report.get("archiveSha256") or "").lower() != str(archive_ref.get("sha256") or "").lower() or int(report.get("archiveBytes", -1)) != int(archive_ref.get("bytes", -2)):
        raise ValueError("pre-acceptance RELEASE audit report does not bind its immutable archive")
    _assert_tuple(report.get("candidateTuple"), expected, "pre-acceptance RELEASE audit report")
    if report.get("fullReleaseRunId") != full_release_run_id or report.get("standardTokenRunId") != pointer.get("standardTokenRunId") or report.get("proofRunIds") != pointer.get("proofRunIds"):
        raise ValueError("pre-acceptance RELEASE audit report lineage is stale or spliced")
    checks = report.get("checks")
    if not isinstance(checks, dict) or any(value not in {"PASS", "SKIPPED"} for value in checks.values()) or checks.get("pythonCompile") != "PASS" or checks.get("powershellParse") != "PASS":
        raise ValueError("pre-acceptance RELEASE audit checks are incomplete")
    manifest = read_json(checked["manifest"])
    if (str(manifest.get("sha256") or "").lower() != str(archive_ref.get("sha256") or "").lower()
            or int(manifest.get("bytes", -1)) != int(archive_ref.get("bytes", -2))
            or manifest.get("selfTest") != "PASS"
            or int(manifest.get("expectedSourceCount", -1)) != int(manifest.get("includedSourceCount", -2))):
        raise ValueError("pre-acceptance RELEASE audit manifest does not bind the immutable archive")
    validation = read_json(checked["releaseValidation"])
    if (validation.get("status") != "PASS" or validation.get("bundleMode") != "pre-acceptance" or validation.get("releaseEligible") is not False
            or validation.get("fullReleaseRunId") != full_release_run_id
            or validation.get("standardTokenRunId") != pointer.get("standardTokenRunId")):
        raise ValueError("pre-acceptance release-bundle validation is not a non-promoting PASS")
    validation_tuple = validation.get("candidateTuple")
    _assert_tuple(validation_tuple, expected, "pre-acceptance release-bundle validation")
    if validation.get("proofRunIds") != pointer.get("proofRunIds"):
        raise ValueError("pre-acceptance release audit proof lineage is spliced")
    checks_summary = pointer.get("checks")
    required_checks = {"cleanExtraction": "PASS", "secrets": "PASS", "coherence": "PASS", "sourceCount": "PASS", "releaseValidation": "PASS"}
    if not isinstance(checks_summary, dict) or set(checks_summary) != set(required_checks) or any(checks_summary.get(key) != value for key, value in required_checks.items()):
        raise ValueError("pre-acceptance RELEASE audit check summary is incomplete")
    inputs = pointer.get("inputs")
    if not isinstance(inputs, dict) or inputs.get("proofRunIds") != pointer.get("proofRunIds"):
        raise ValueError("pre-acceptance RELEASE audit input bindings are missing")
    input_hash_keys = {"fullReleaseRunStateSha256", "fullReleasePhaseRecordsSha256", "realUseBindingSha256", "realUsePrepareSha256", "realUseReportSha256", "realUseSummarySha256", "cleanupSha256", "postCleanupSha256", "terminalL1Sha256", "terminalL2Sha256", "standardTokenPointerSha256"}
    if set(inputs) != input_hash_keys | {"proofRunIds"}:
        raise ValueError("pre-acceptance RELEASE audit input binding set is not exact")
    for key in input_hash_keys:
        if not re.fullmatch(r"[0-9a-f]{64}", str(inputs.get(key) or "")):
            raise ValueError(f"pre-acceptance RELEASE audit input hash is malformed: {key}")
    if closure is not None:
        expected_inputs = {
            "fullReleaseRunStateSha256": closure["fullRelease"]["runStateSha256"],
            "fullReleasePhaseRecordsSha256": closure["fullRelease"]["phaseRecordsSha256"],
            "realUseBindingSha256": closure["fullRelease"]["realUseBindingSha256"],
            "realUsePrepareSha256": closure["fullRelease"]["realUsePrepareSha256"],
            "realUseReportSha256": closure["fullRelease"]["realUseReportSha256"],
            "realUseSummarySha256": closure["fullRelease"]["realUseSummarySha256"],
            "cleanupSha256": closure["fullRelease"]["cleanupSha256"],
            "postCleanupSha256": closure["fullRelease"]["postCleanupSha256"],
            "terminalL1Sha256": closure["fullRelease"]["l1Sha256"],
            "terminalL2Sha256": closure["fullRelease"]["l2Sha256"],
            "standardTokenPointerSha256": closure["standardToken"]["pointerSha256"],
        }
        if any(str(inputs.get(key) or "").lower() != str(value).lower() for key, value in expected_inputs.items()):
            raise ValueError("pre-acceptance RELEASE audit input hashes do not match current evidence")
    if archive_path is not None:
        # Re-run the independent clean-extraction validator over the exact
        # immutable archive. The stored prevalidation JSON is evidence, not a
        # substitute for validating the bytes again at acceptance time.
        live_validation = validate(archive_path, "pre-acceptance")
        for key in ("status", "bundleMode", "releaseEligible", "fullReleaseRunId", "standardTokenRunId", "proofRunIds"):
            if live_validation.get(key) != validation.get(key):
                raise ValueError(f"immutable RELEASE audit revalidation disagrees with stored result: {key}")
        _assert_tuple(live_validation.get("candidateTuple"), expected, "revalidated immutable RELEASE audit")
    gates = pointer.get("gates")
    required_gates = {"candidate": "PASS", "proofs": "2/2 PASS", "fullRelease": "PASS", "realUseAcceptance": "U01-U05 PASS", "maintenance": "5/5 PASS", "standardToken": "PASS", "reconcile": "PASS", "cleanup": "PASS", "l1": "OFF", "l2": "ABSENT", "releaseAudit": "PASS"}
    if not isinstance(gates, dict) or set(gates) != set(required_gates) or any(gates.get(key) != value for key, value in required_gates.items()):
        raise ValueError("pre-acceptance RELEASE audit gate summary is incomplete")
    return {"runId": audit_id, "pointerSha256": sha(pointer_path), "archiveSha256": str(archive_ref["sha256"]), "reportSha256": sha(checked["report"]), "manifestSha256": sha(checked["manifest"]), "releaseValidationSha256": sha(checked["releaseValidation"])}


def validate_final_acceptance(root: Path, layout: str = "workspace", final_path: Path | None = None) -> dict[str, object]:
    if layout not in {"workspace", "bundle"}:
        raise ValueError("final acceptance layout must be workspace or bundle")
    final_path = final_path.resolve() if final_path is not None else root / "evidence/FINAL-ACCEPTANCE.json"
    if layout != "workspace" and final_path != root / "evidence/FINAL-ACCEPTANCE.json":
        raise ValueError("a FINAL-ACCEPTANCE override is valid only for workspace pre-publication checks")
    if not final_path.is_file():
        raise ValueError("FINAL-ACCEPTANCE.json is missing")
    final = read_json(final_path)
    if (final.get("schemaVersion") != 1 or final.get("contract") != "devfleet-internal-final-acceptance-v1"
            or final.get("status") != "PASS" or final.get("releaseEligible") is not True
            or final.get("internalPromotionAllowed") is not True
            or final.get("publicPromotionAllowed") is not False or final.get("publicPublisherTrust") is not False):
        raise ValueError("FINAL-ACCEPTANCE does not assert the exact internal-only PASS contract")
    closure = _validate_current_release_evidence(root, layout)
    expected = closure["candidateTuple"]
    _assert_tuple(final.get("candidate"), expected, "FINAL-ACCEPTANCE")
    artifacts = final.get("candidate", {}).get("artifacts") if isinstance(final.get("candidate"), dict) else None
    if not isinstance(artifacts, dict) or set(artifacts) != {"exe", "tar", "portable", "installerSource"}:
        raise ValueError("FINAL-ACCEPTANCE artifact tuple is missing")
    for name, observed in artifacts.items():
        expected_row = closure["artifacts"][name]
        if not isinstance(observed, dict) or str(observed.get("sha256") or "") != str(expected_row["sha256"]) or int(observed.get("bytes", -1)) != int(expected_row["bytes"]):
            raise ValueError(f"FINAL-ACCEPTANCE artifact tuple mismatch: {name}")
    signing = final.get("candidate", {}).get("authenticode") if isinstance(final.get("candidate"), dict) else None
    if (not isinstance(signing, dict) or signing.get("status") != "PASS" or signing.get("signatureStatus") != "Valid"
            or signing.get("signerThumbprint") != "DE42CD7369A01E9357BDA13597C0173E5E703E9D"
            or signing.get("signerSubject") != "CN=DevFleet Private Personal Code Signing"
            or signing.get("codeSigningEkuVerified") is not True or signing.get("rsaBits") != 3072
            or signing.get("exactCertificateMatch") is not True or signing.get("privateKeyExported") is not False):
        raise ValueError("FINAL-ACCEPTANCE Authenticode identity is incomplete")
    if final.get("proofRunIds") != closure["proofRunIds"] or final.get("fullReleaseRunId") != closure["fullReleaseRunId"] or final.get("standardTokenRunId") != closure["standardToken"]["runId"]:
        raise ValueError("FINAL-ACCEPTANCE proof/FullRelease/standard-token lineage is stale or spliced")
    release_audit = _validate_release_audit(root, expected, str(closure["fullReleaseRunId"]), layout, require_archive=(layout == "workspace"), closure=closure)
    if final.get("releaseAuditRunId") != release_audit["runId"]:
        raise ValueError("FINAL-ACCEPTANCE release-audit lineage is stale or spliced")
    bindings = final.get("bindings")
    if not isinstance(bindings, dict):
        raise ValueError("FINAL-ACCEPTANCE evidence bindings are missing")
    expected_hashes = {
        "standardTokenPointerSha256": closure["standardToken"]["pointerSha256"],
        "standardTokenCanonicalSha256": closure["standardToken"]["canonicalSha256"],
        "standardTokenRawReportSha256": closure["standardToken"]["rawReportSha256"],
        "fullReleaseRunStateSha256": closure["fullRelease"]["runStateSha256"],
        "fullReleasePhaseRecordsSha256": closure["fullRelease"]["phaseRecordsSha256"],
        "realUseBindingSha256": closure["fullRelease"]["realUseBindingSha256"],
        "realUsePrepareSha256": closure["fullRelease"]["realUsePrepareSha256"],
        "realUseReportSha256": closure["fullRelease"]["realUseReportSha256"],
        "realUseSummarySha256": closure["fullRelease"]["realUseSummarySha256"],
        "cleanupSha256": closure["fullRelease"]["cleanupSha256"],
        "postCleanupSha256": closure["fullRelease"]["postCleanupSha256"],
        "terminalL1Sha256": closure["fullRelease"]["l1Sha256"],
        "terminalL2Sha256": closure["fullRelease"]["l2Sha256"],
        "releaseAuditPointerSha256": release_audit["pointerSha256"],
        "releaseAuditArchiveSha256": release_audit["archiveSha256"],
        "releaseAuditReportSha256": release_audit["reportSha256"],
        "releaseAuditManifestSha256": release_audit["manifestSha256"],
        "releaseAuditValidationSha256": release_audit["releaseValidationSha256"],
    }
    if set(bindings) != set(expected_hashes) or any(str(bindings.get(key) or "").lower() != str(value).lower() for key, value in expected_hashes.items()):
        raise ValueError("FINAL-ACCEPTANCE evidence hash closure is incomplete or changed")
    safety = final.get("safety")
    required_false = ("f005Attempted", "formatterOnlyAuditCleanupPerformed", "f005StructuralRefactoringPerformed", "protectedProductionMutated", "hostRebooted", "amdRadeonTouched", "biosUefiTouched", "mulattoTechSurfaceTouched", "githubPushed", "privateSigningKeyExported", "ramPressureOverrideUsed")
    if not isinstance(safety, dict) or any(safety.get(key) is not False for key in required_false) or safety.get("productionUnchanged") is not True or safety.get("disposableLabOnly") is not True:
        raise ValueError("FINAL-ACCEPTANCE safety/F-005 assertions are missing or unsafe")
    gates = final.get("gates")
    required_gates = {"candidate": "PASS", "proofs": "2/2 PASS", "fullRelease": "PASS", "realUseAcceptance": "U01-U05 PASS", "maintenance": "5/5 PASS", "standardToken": "PASS", "reconcile": "PASS", "cleanup": "PASS", "l1": "OFF", "l2": "ABSENT", "releaseAudit": "PASS"}
    if not isinstance(gates, dict) or set(gates) != set(required_gates) or any(gates.get(key) != value for key, value in required_gates.items()):
        raise ValueError("FINAL-ACCEPTANCE gate closure is incomplete")
    return {"status": "PASS", "releaseEligible": True, "internalPromotionAllowed": True, "publicPromotionAllowed": False, "candidateTuple": expected, "proofRunIds": closure["proofRunIds"], "fullReleaseRunId": closure["fullReleaseRunId"], "standardTokenRunId": closure["standardToken"]["runId"], "releaseAuditRunId": release_audit["runId"], "finalAcceptanceSha256": sha(final_path)}


def validate_historical_proof_sources(root: Path, current: dict) -> None:
    historical_start = str(current.get("proofStartHistoricalPath") or "")
    parts = PurePosixPath(historical_start.replace("\\", "/"))
    if len(parts.parts) != 4 or parts.parts[:2] != ("release-tooling", "historical") or parts.name != "proof-start.json" or parts.is_absolute() or ".." in parts.parts or not (root / historical_start).is_file():
        raise ValueError("diagnostic bundle is missing the exact historical proof-start archive path")
    start = read_json(root / historical_start)
    provenance = start.get("provenance") if isinstance(start.get("provenance"), dict) else {}
    historical_root = (root / historical_start).parent
    historical_sources = {
        "proofScriptSha256": historical_root / "run-exact-candidate-proof.ps1",
        "invokeRealProductPhaseSha256": historical_root / "Invoke-RealProductPhase.psm1",
        "invokeWpfUiAutomationSha256": historical_root / "Invoke-WpfUiAutomation.ps1",
    }
    for key, path in historical_sources.items():
        expected = str(provenance.get(key) or "").lower()
        if not re.fullmatch(r"[0-9a-f]{64}", expected) or not path.is_file() or sha(path) != expected:
            raise ValueError(f"historical proof-start source cannot be verified: {key}")


def _validate_diagnostic(root: Path, names: set[str]) -> dict[str, object]:
    candidate_record = read_json(root / "CURRENT-CANDIDATE.json")
    manifest = read_json(root / "AUDIT-MANIFEST.json")
    if FAILED_ATTEMPT_SNAPSHOT in names:
        missing = sorted((FAILED_ATTEMPT_CURRENT_RECORDS | FAILED_ATTEMPT_INVENTORY_FILES) - names)
        if missing:
            raise ValueError(f"failed-attempt diagnostic blocker records are missing: {missing}")
        state = read_json(root / "finalization-state.json")
        if (state.get("status"), state.get("blocker_code"), state.get("candidate_is_current"), state.get("source_changed_since_candidate"), state.get("rebuild_required"), state.get("artifact_tuple_matches_candidate"), state.get("full_release_passed"), state.get("internal_promotion_allowed"), state.get("public_promotion_allowed")) != ("BLOCKED — USER ACTION REQUIRED", FAILED_ATTEMPT_BLOCKER, False, True, True, False, False, False, False):
            raise ValueError("failed replacement-attempt authority flags are not truthful")
        attempt = state.get("failed_replacement_attempt")
        if not isinstance(attempt, dict) or attempt.get("snapshotPath") != FAILED_ATTEMPT_SNAPSHOT or attempt.get("blockerCode") != FAILED_ATTEMPT_BLOCKER:
            raise ValueError("failed replacement-attempt authority binding is missing")
        terminal = attempt.get("terminalEvidence")
        if not isinstance(terminal, dict) or not isinstance(terminal.get("l1"), dict) or not isinstance(terminal.get("l2"), dict):
            raise ValueError("failed replacement-attempt terminal L1/L2 evidence is missing")
        proof = read_json(root / "evidence/CURRENT-PROOF.json")
        attempted = read_json(root / "audit/attemptedReplacementCandidate.json")
        failure = read_json(root / "audit/candidateBindingFailure.json")
        expected = {
            "attemptedCommit": "21752fc0e50978183322204c523b40947d073aa0",
            "commitShippingInputIdentity": "6e0bac4b4eebc83cdcd9eddda2008607ba15c8835e5c72a931792f5b83c653f4",
            "buildTimeShippingInputIdentity": "3a65fd54d70fe05565ac3a32f73100ca2c81a77a4008feb361f99f229f025f8a",
        }
        if proof.get("status") != "NOT_OBSERVED" or proof.get("outcome") != "NOT_OBSERVED" or proof.get("blockerCode") != FAILED_ATTEMPT_BLOCKER:
            raise ValueError("failed-attempt CURRENT-PROOF contradicts the blocker authority")
        if attempted.get("snapshotPath") != FAILED_ATTEMPT_SNAPSHOT or attempted.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or any(attempted.get(key) != value for key, value in expected.items()):
            raise ValueError("attemptedReplacementCandidate contradicts the failed-attempt authority")
        if attempted.get("artifactTupleValid") is not True or attempted.get("artifactTupleMatchesCandidate") is not False or attempted.get("buildInvocationCount") != 1 or attempted.get("signingInvocationCount") != 1:
            raise ValueError("attemptedReplacementCandidate one-shot/artifact state is invalid")
        if failure.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or any(failure.get(key) != value for key, value in expected.items()) or failure.get("artifactTupleValid") is not True or failure.get("artifactTupleMatchesCandidate") is not False or failure.get("currentProofOutcome") != "NOT_OBSERVED":
            raise ValueError("candidateBindingFailure contradicts the failed-attempt authority")
        manifest = read_json(root / "AUDIT-MANIFEST.json")
        inventory = manifest.get("evidenceInventory")
        if not isinstance(inventory, list) or {str(row.get("path")) for row in inventory if isinstance(row, dict)} != FAILED_ATTEMPT_CURRENT_RECORDS:
            raise ValueError("failed-attempt evidenceInventory is missing or incomplete")
        for row in inventory:
            relative = str(row.get("path"))
            path = root / Path(*relative.split("/"))
            if relative in FAILED_ATTEMPT_CURRENT_RECORDS and (not path.is_file() or int(row.get("bytes", -1)) != path.stat().st_size or str(row.get("sha256") or "").lower() != sha(path) or row.get("mode") != "0644"):
                raise ValueError(f"failed-attempt evidenceInventory hash/mode mismatch: {relative}")
        modes = read_json(root / "EVIDENCE-MODES.json")
        mode_by_path = {str(row.get("path")): row for row in modes if isinstance(row, dict)} if isinstance(modes, list) else {}
        if set(mode_by_path) != FAILED_ATTEMPT_CURRENT_RECORDS or any(row.get("posixMode") != 420 or row.get("mode") != "0644" for row in mode_by_path.values()):
            raise ValueError("failed-attempt evidence mode inventory is missing or contradictory")
        hash_rows = {}
        for line in (root / "EVIDENCE-SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
            if line.strip():
                digest, relative = line.split("  ", 1)
                hash_rows[relative] = digest.lower()
        if set(hash_rows) != FAILED_ATTEMPT_CURRENT_RECORDS or any(hash_rows[path] != next(row["sha256"] for row in inventory if row.get("path") == path) for path in FAILED_ATTEMPT_CURRENT_RECORDS):
            raise ValueError("failed-attempt evidence hash inventory is missing or contradictory")
        return {"status": "PASS_WITH_BLOCKER", "bundleMode": "diagnostic", "diagnostic": True, "blockerCode": FAILED_ATTEMPT_BLOCKER, "releaseEligible": False, "candidateIsCurrent": False, "sourceChangedSinceCandidate": True, "rebuildRequired": True, "proofOutcome": "NOT_OBSERVED", "filesChecked": len(names)}
    candidate_commit = str(candidate_record.get("candidateCommit") or candidate_record.get("candidateGitCommit") or "").lower()
    if candidate_commit != HISTORICAL_CANDIDATE:
        state = read_json(root / "finalization-state.json")
        flags = (state.get("candidate_is_current"), state.get("source_changed_since_candidate"), state.get("rebuild_required"), state.get("full_release_passed"), state.get("internal_promotion_allowed"), state.get("public_promotion_allowed"))
        current_pending = (True, False, False, False, False, False)
        invalidated_pending = (False, True, True, False, False, False)
        if flags not in {current_pending, invalidated_pending}:
            raise ValueError("generic diagnostic candidate authority flags are not truthful")
        current = read_json(root / "evidence/CURRENT-PROOF.json")
        summary = read_json(root / "evidence/FULLRELEASE-SUMMARY.json")
        if not summary.get("diagnosticOnly") and not summary.get("historicalEvidenceOnly"):
            raise ValueError("generic diagnostic summary must be marked diagnosticOnly or historicalEvidenceOnly")
        proof_outcome = str(current.get("outcome") or "")
        if proof_outcome == "NOT_OBSERVED":
            if str(current.get("status")) not in {"BLOCKED", "NOT_OBSERVED"}:
                raise ValueError("generic diagnostic NOT_OBSERVED proof status is not fail-closed")
        elif proof_outcome == "PASS":
            # A current exact-candidate proof may have passed before a later
            # FullRelease attempt was blocked. Preserve that truthful proof in
            # a diagnostic bundle while requiring its complete native proof
            # closure and keeping every release-promotion flag false.
            final = current.get("proofFinal")
            if (current.get("status") != "PASS"
                    or current.get("proofStartCurrent") is not True
                    or current.get("certificationEligible") is not True
                    or current.get("diagnosticOnly") is not False
                    or not isinstance(final, dict)
                    or final.get("status") != "PASS"
                    or final.get("runId") != current.get("runId")
                    or final.get("certificationEligible") is not True
                    or final.get("diagnosticOnly") is not False
                    or not isinstance(final.get("cleanup"), dict)
                    or final["cleanup"].get("status") != "PASS"):
                raise ValueError("generic diagnostic PASS proof lacks its current qualifying native closure")
            if summary.get("fullReleasePassed") is not False:
                raise ValueError("generic diagnostic PASS proof is paired with a contradictory FullRelease status")
        else:
            raise ValueError("generic diagnostic current proof outcome is not fail-closed")
        invalidated = flags == invalidated_pending
        if invalidated:
            authorization = state.get("authorized_correction")
            paths = authorization.get("shipping_paths") if isinstance(authorization, dict) else None
            working = candidate_record.get("workingTreeTuple")
            if not isinstance(paths, list) or not paths or not isinstance(working, dict):
                raise ValueError("invalidated diagnostic is missing its exact correction or working-tree tuple")
            for key in ("shippingInputIdentity", "canonicalizedShippingInputIdentity", "toolingFingerprintId"):
                value = str(working.get(key) or "")
                if len(value) != 64 or any(ch not in "0123456789abcdefABCDEF" for ch in value):
                    raise ValueError(f"invalidated diagnostic working-tree tuple is malformed: {key}")
        return {"status": "PASS_WITH_BLOCKER", "bundleMode": "diagnostic", "diagnostic": True, "blockerCode": "CANDIDATE_INVALIDATED_REBUILD_REQUIRED" if invalidated else "DIAGNOSTIC_PROOF_PENDING", "releaseEligible": False, "candidateIsCurrent": not invalidated, "sourceChangedSinceCandidate": invalidated, "rebuildRequired": invalidated, "proofOutcome": proof_outcome, "filesChecked": len(names)}
    provenance_values = [value for value in (candidate_record.get("historicalProvenance"), manifest.get("historicalProvenance") if isinstance(manifest, dict) else None) if isinstance(value, dict)]
    provenance = provenance_values[0] if provenance_values else None
    if not isinstance(provenance, dict):
        raise ValueError("diagnostic bundle requires structured historicalProvenance")
    if any(value != provenance for value in provenance_values[1:]):
        raise ValueError("diagnostic historical provenance declarations disagree")
    if str(provenance.get("candidateCommit") or "").lower() != HISTORICAL_CANDIDATE:
        raise ValueError("diagnostic candidate is not the preserved 2739 object")
    if str(provenance.get("provenanceCommit") or provenance.get("sourceCommit") or "").lower() != HISTORICAL_PROVENANCE:
        raise ValueError("diagnostic provenance is not the preserved f334 object")
    if str(provenance.get("materialization") or "") != "git-archive" or provenance.get("coreAutocrlf") is not False:
        raise ValueError("diagnostic provenance is not deterministic core.autocrlf=false materialization")
    if str(provenance.get("lineEndingComparison") or "").upper() not in {"CRLF_ONLY", "CRLF-ONLY"}:
        raise ValueError("diagnostic provenance is not a proven CRLF-only comparison")
    if str(provenance.get("historicalShippingInputIdentity") or "").lower() != HISTORICAL_SHIPPING_IDENTITY:
        raise ValueError("diagnostic historical shipping identity is not the preserved value")
    if str(provenance.get("historicalReleaseFingerprintId") or "").lower() != HISTORICAL_RELEASE_FINGERPRINT:
        raise ValueError("diagnostic historical release fingerprint is not the preserved value")
    if str(candidate_record.get("devfleetVersion") or "") != "1.2.13" or str(candidate_record.get("installerVersion") or "") != "1.4.1":
        raise ValueError("diagnostic historical candidate version tuple is not the exact 1.2.13/1.4.1 tuple")
    mode = candidate_record.get("candidateShippingModeContract")
    if not isinstance(mode, dict) or set(mode) != {"schemaVersion", "defaultMode", "executableMode", "executableByContract"} or mode.get("schemaVersion") != 1 or mode.get("defaultMode") != "0644" or mode.get("executableMode") != "0755" or not isinstance(mode.get("executableByContract"), list) or mode["executableByContract"] != sorted(str(path) for path in mode["executableByContract"]):
        raise ValueError("diagnostic historical candidate mode contract is incomplete or non-canonical")
    labels = provenance.get("identityLabels") if isinstance(provenance.get("identityLabels"), dict) else {}
    if not str(labels.get("preservedCanonicalShippingInputIdentity") or "").lower().startswith("454edc") or not str(labels.get("rawGitShippingInputIdentity") or "").lower().startswith("cdab") or not str(labels.get("rawGitReleaseFingerprintId") or "").lower().startswith("eba40"):
        raise ValueError("diagnostic historical identity labels are incomplete")
    recorded_paths = {str(path).replace("\\", "/") for path in provenance.get("authorizedCurrentShippingPaths", []) if str(path)}
    if recorded_paths != AUTHORIZED_SHIPPING_PATHS:
        raise ValueError("diagnostic historical provenance does not bind exactly the seven authorized shipping paths")
    rows = candidate_record.get("candidateShippingInputs")
    if not isinstance(rows, list) or not rows:
        raise ValueError("diagnostic candidate shipping rows are mandatory offline evidence")
    recomputed_identity = _candidate_shipping_identity(rows, candidate_record.get("devfleetVersion"), candidate_record.get("installerVersion"), candidate_record.get("candidateShippingModeContract") or {})
    if str(provenance.get("recomputedCandidateShippingInputIdentity") or "").lower() != recomputed_identity or recomputed_identity != HISTORICAL_RAW_GIT_SHIPPING_IDENTITY:
        raise ValueError("diagnostic candidate shipping identity was not recomputed from embedded rows")
    release_file = root / "outputs/release-fingerprint.json"
    release = read_json(release_file) if release_file.is_file() else {}
    release_rows = release.get("shippingInputs")
    if not isinstance(release_rows, list) or not release_rows:
        raise ValueError("diagnostic release rows are missing")
    release_payload = {key: release.get(key) for key in ("schemaVersion", "devfleetVersion", "installerVersion", "shippingModeContract")}
    # release_fingerprint.py canonicalizes each root independently (source
    # first, installer-source second); preserve that authoritative order.
    release_payload["shippingInputs"] = release_rows
    release_payload["artifacts"] = release.get("artifacts", [])
    recomputed_release = hashlib.sha256(json.dumps(release_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    if recomputed_release != HISTORICAL_RELEASE_FINGERPRINT or str(release.get("releaseFingerprintId") or "").lower() != recomputed_release:
        raise ValueError("diagnostic release rows do not recompute to the preserved fingerprint")
    declared_recomputed_release = str(provenance.get("recomputedHistoricalReleaseFingerprintId") or "").lower()
    if not declared_recomputed_release or declared_recomputed_release != recomputed_release:
        raise ValueError("diagnostic historical release fingerprint closure is not recomputed")
    state = read_json(root / "finalization-state.json")
    release_artifacts = {str(row.get("name") or "").lower().replace("-", "").replace("_", ""): row for row in release.get("artifacts", []) if isinstance(row, dict)}
    state_candidate = state.get("candidate") if isinstance(state, dict) else None
    if not isinstance(state_candidate, dict):
        raise ValueError("diagnostic candidate artifact tuple is missing")
    candidate_artifacts = {str(value.get("name") or key).lower().replace("-", "").replace("_", ""): value for key, value in state_candidate.items() if isinstance(value, dict)}
    for key in ("exe", "tar", "portable", "installersource"):
        expected = next((row for name, row in release_artifacts.items() if key in name), None)
        observed = next((row for name, row in candidate_artifacts.items() if key in name), None)
        if expected is None or observed is None or str(expected.get("sha256") or "").lower() != str(observed.get("sha256") or "").lower() or int(expected.get("bytes", -1)) != int(observed.get("bytes", -2)):
            raise ValueError(f"diagnostic artifact closure mismatch: {key}")
    state_flags = (state.get("candidate_is_current"), state.get("source_changed_since_candidate"), state.get("rebuild_required"), state.get("full_release_passed"), state.get("internal_promotion_allowed"), state.get("public_promotion_allowed"))
    if state_flags != (False, True, True, False, False, False):
        raise ValueError("diagnostic authority flags are not truthful")
    if provenance.get("releaseEligible") is not False or provenance.get("promotionAllowed") is not False:
        raise ValueError("diagnostic historical provenance cannot be promoted")
    current = read_json(root / "evidence/CURRENT-PROOF.json")
    if str(current.get("outcome")) != "NOT_OBSERVED" or str(current.get("status")) not in {"BLOCKED", "NOT_OBSERVED"}:
        raise ValueError("diagnostic bundle must preserve a blocked NOT_OBSERVED current proof")
    handoff = read_json(root / "audit/CURRENT-HANDOFF.json")
    classification = str(current.get("blockerClassification") or handoff.get("blockerClassification") or "")
    if "RELEASE HARNESS" not in classification or ("EVIDENCE TOOLING" not in classification and "/ TOOLING" not in classification):
        raise ValueError("diagnostic bundle blocker classification is not release harness/evidence tooling")
    validate_historical_proof_sources(root, current)
    summary = read_json(root / "evidence/FULLRELEASE-SUMMARY.json")
    if not summary.get("diagnosticOnly") and not summary.get("historicalEvidenceOnly"):
        raise ValueError("blocked FullRelease summary must be marked diagnosticOnly or historicalEvidenceOnly")
    if bool(state.get("full_release_passed")) or bool(state.get("internal_promotion_allowed")) or bool(state.get("public_promotion_allowed")):
        raise ValueError("diagnostic bundle cannot claim promotion or FullRelease PASS")
    return {"status": "PASS_WITH_BLOCKER", "bundleMode": "diagnostic", "diagnostic": True, "releaseEligible": False, "candidateIsCurrent": False, "sourceChangedSinceCandidate": True, "rebuildRequired": True, "proofOutcome": "NOT_OBSERVED", "filesChecked": len(names)}


def validate_release_evidence(root: Path, *, require_release_audit: bool = False) -> dict[str, object]:
    """Validate the current workspace through cleanup, without granting promotion.

    This is deliberately separate from FINAL-ACCEPTANCE.  The immutable release
    audit is produced only after this closure passes, and FINAL-ACCEPTANCE is
    produced only after the immutable audit has also been revalidated.
    """
    root = root.resolve()
    closure = _validate_current_release_evidence(root, "workspace")
    result: dict[str, object] = {
        "status": "PASS",
        "bundleMode": "pre-acceptance",
        "releaseEligible": False,
        "internalPromotionAllowed": False,
        "publicPromotionAllowed": False,
        **closure,
        "standardTokenRunId": closure["standardToken"]["runId"],
    }
    if require_release_audit:
        result["releaseAudit"] = _validate_release_audit(
            root,
            closure["candidateTuple"],
            str(closure["fullReleaseRunId"]),
            "workspace",
            require_archive=True,
            closure=closure,
        )
        result["releaseAuditRunId"] = result["releaseAudit"]["runId"]
    return result


def validate(archive: Path, mode: str = "final") -> dict[str, object]:
    if mode == "final":
        mode = "release"
    if mode not in {"diagnostic", "pre-acceptance", "release"}:
        raise ValueError("bundle mode must be diagnostic, pre-acceptance, or release")
    if not archive.is_file():
        raise ValueError(f"bundle is missing: {archive}")
    temp = Path(tempfile.mkdtemp(prefix="DevFleet release bundle "))
    try:
        with zipfile.ZipFile(archive) as bundle:
            names = {PurePosixPath(info.filename.replace("\\", "/")).as_posix() for info in bundle.infolist()}
            required = (DIAGNOSTIC_REQUIRED if mode == "diagnostic"
                        else PRE_ACCEPTANCE_REQUIRED if mode == "pre-acceptance"
                        else REQUIRED)
            missing = sorted(required - names)
            if missing:
                raise ValueError(f"current release evidence missing: {missing}")
            names = _safe_extract(bundle, temp)
        root = temp
        candidate_result = _validate_candidate_bound(root, "diagnostic" if mode == "diagnostic" else "release")
        sys.path.insert(0, str(root / "release-tooling"))
        from validate_audit_coherence import validate as validate_coherence  # type: ignore
        validate_coherence(root)
        authority_state = read_json(root / "finalization-state.json")
        expected_head = str(authority_state.get("repository_head") or authority_state.get("repositoryHead") or "")
        candidate = str(authority_state.get("candidate_git_commit") or authority_state.get("candidateGitCommit") or "")
        shipping = str(authority_state.get("shipping_input_identity") or authority_state.get("shippingInputIdentity") or "")
        release = str(authority_state.get("releaseFingerprintId") or "")
        tooling = str(authority_state.get("toolingFingerprintId") or "")
        if mode == "diagnostic":
            result = _validate_diagnostic(root, names)
            result["candidateBoundVerification"] = candidate_result
            return result
        if mode == "pre-acceptance":
            forbidden = {name for name in names if name == "evidence/FINAL-ACCEPTANCE.json" or name.startswith("evidence/release-audits/") or name == "evidence/CURRENT-RELEASE-AUDIT.json"}
            if forbidden:
                raise ValueError(f"pre-acceptance audit contains post-audit evidence (cycle): {sorted(forbidden)}")
            closure = _validate_current_release_evidence(root, "bundle")
            return {
                "status": "PASS", "bundleMode": "pre-acceptance",
                "releaseEligible": False, "internalPromotionAllowed": False,
                "publicPromotionAllowed": False, "filesChecked": len(names),
                "candidateBoundVerification": candidate_result,
                "candidateTuple": closure["candidateTuple"],
                "fullReleaseRunId": closure["fullReleaseRunId"],
                "standardTokenRunId": closure["standardToken"]["runId"],
                "proofRunIds": closure["proofRunIds"],
            }
        final = validate_final_acceptance(root, "bundle")
        return {**final, "bundleMode": "release", "filesChecked": len(names), "candidateBoundVerification": candidate_result}
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--archive", type=Path)
    source.add_argument("--workspace-root", type=Path)
    parser.add_argument("--mode", choices=("diagnostic", "pre-acceptance", "release"), default="release")
    parser.add_argument("--check", choices=("release-evidence", "pre-acceptance", "final-acceptance"))
    parser.add_argument("--final-record", type=Path, help="candidate FINAL-ACCEPTANCE path for workspace pre-publication validation")
    args = parser.parse_args()
    try:
        if args.archive:
            if args.check or args.final_record:
                raise ValueError("--check/--final-record are only valid with --workspace-root")
            result = validate(args.archive.resolve(), args.mode)
        else:
            if not args.check:
                raise ValueError("--workspace-root requires --check")
            if args.mode != "release":
                raise ValueError("--mode is only valid with --archive")
            if args.final_record and args.check != "final-acceptance":
                raise ValueError("--final-record requires --check final-acceptance")
            if args.check == "final-acceptance":
                result = validate_final_acceptance(args.workspace_root.resolve(), "workspace", args.final_record)
            else:
                result = validate_release_evidence(args.workspace_root, require_release_audit=(args.check == "pre-acceptance"))
        print(json.dumps(result, sort_keys=True))
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"RELEASE BUNDLE FAIL: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
