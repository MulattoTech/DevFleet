# DevFleet source part 125

Full-source UTF-8 byte interval [5766000, 5812500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 53b54ad45c0366f942b12de9de9916cdd04cf59a85d09185443343468d613230

<!-- BEGIN SOURCE SLICE -->
st = load(state_path), load(manifest_path)
    if not isinstance(state, dict) or not isinstance(manifest, dict):
        raise ValueError("Current state and artifact manifest must be JSON objects")
    failed_result = validate_failed_attempt_authority(root, state)
    live_head = git_head(root)
    expected_head = live_head or str(state.get("repository_head") or manifest.get("repositoryHead") or "")
    candidate = str(state.get("candidate_git_commit") or state.get("candidateGitCommit") or manifest.get("candidateGitCommit") or "")
    release = str(state.get("releaseFingerprintId") or manifest.get("releaseFingerprintId") or "")
    tooling = str(state.get("toolingFingerprintId") or manifest.get("toolingFingerprintId") or "")
    candidate_shipping = str(state.get("shipping_input_identity") or state.get("shippingInputIdentity") or manifest.get("shippingInputIdentity") or "")
    # A bundle may expose both the immutable candidate shipping identity in
    # current state/artifact metadata and the freshly hashed live identity in
    # AUDIT-MANIFEST.  Accept exactly this two-value split; every other value
    # remains a fail-closed contradiction.
    audit_manifest_path = root / "AUDIT-MANIFEST.json"
    audit_manifest = load(audit_manifest_path) if audit_manifest_path.is_file() else {}
    live_shipping = str(audit_manifest.get("shippingInputIdentity") or candidate_shipping)
    working_shipping = str(state.get("working_tree_shipping_input_identity") or "")
    working_tooling = str(state.get("working_tree_tooling_fingerprint_id") or "")
    if len(expected_head) != 40 or len(candidate) != 40:
        raise ValueError("Current repository HEAD or signed candidate commit is missing/malformed")
    if any(len(value) != 64 for value in (release, tooling, candidate_shipping, live_shipping)):
        raise ValueError("Current release/tooling/shipping identity tuple is incomplete")
    if bool(working_shipping) != bool(working_tooling) or any(len(value) != 64 for value in (working_shipping, working_tooling) if value):
        raise ValueError("Working-tree shipping/tooling identity tuple is incomplete")

    def check_working_tree(value: dict[str, Any], location: str) -> None:
        if not working_shipping:
            return
        observed_shipping = str(value.get("shippingInputIdentity") or value.get("shipping_input_identity") or "")
        observed_tooling = str(value.get("toolingFingerprintId") or value.get("tooling_fingerprint_id") or "")
        canonicalized = str(value.get("canonicalizedShippingInputIdentity") or "")
        if observed_shipping and observed_shipping != working_shipping:
            raise ValueError(f"{location}.shippingInputIdentity disagrees with the working-tree tuple")
        if observed_tooling and observed_tooling != working_tooling:
            raise ValueError(f"{location}.toolingFingerprintId disagrees with the working-tree tuple")
        if canonicalized and canonicalized != live_shipping:
            raise ValueError(f"{location}.canonicalizedShippingInputIdentity disagrees with the bundled live identity")

    def check_identity(value: dict[str, Any], location: str, candidate_context: bool = False) -> None:
        for key in ("repositoryHead", "repository_head", "gitCommit", "git_commit"):
            if key in value:
                expected = candidate if candidate_context and key in ("gitCommit", "git_commit") else expected_head
                if str(value[key]) != expected:
                    raise ValueError(f"{location}.{key} disagrees with its bound Git identity")
        for key in ("candidateGitCommit", "candidate_git_commit", "candidateCommit", "candidate_commit"):
            if key in value and str(value[key]) != candidate:
                raise ValueError(f"{location}.{key} disagrees with signed candidate commit")
        for key in ("releaseFingerprintId", "toolingFingerprintId"):
            expected = release if key == "releaseFingerprintId" else tooling
            if key in value and str(value[key]) != expected:
                raise ValueError(f"{location}.{key} disagrees with current identity tuple")
        for key in ("shippingInputIdentity", "shipping_input_identity"):
            if key in value and str(value[key]) not in {candidate_shipping, live_shipping}:
                raise ValueError(f"{location}.{key} disagrees with current shipping identity")

    check_identity(state, "finalization-state.json")
    check_identity(manifest, "outputs/final-artifact-hashes.json")
    if str(state.get("repository_head") or "") != expected_head:
        raise ValueError("finalization-state.json.repository_head is required")
    if str(manifest.get("repositoryHead") or "") != expected_head:
        raise ValueError("final-artifact-hashes.json.repositoryHead is required")
    if str(manifest.get("candidateGitCommit") or "") != candidate:
        raise ValueError("final-artifact-hashes.json.candidateGitCommit is required")

    checked: list[Path] = [state_path, manifest_path]
    for relative in CURRENT_AUTHORITIES:
        path = root / relative
        if not path.is_file() or path.resolve() in {p.resolve() for p in checked}:
            continue
        value = load(path)
        # A preserved interrupted proof/old FullRelease record is useful
        # diagnostic evidence, but it is not a current authority.  The
        # builder marks these records diagnosticOnly so they cannot poison the
        # current identity tuple or masquerade as a release result.
        if isinstance(value, dict) and (value.get("historical") is True or value.get("diagnosticOnly") is True or value.get("historicalEvidenceOnly") is True):
            continue
        if not isinstance(value, dict):
            raise ValueError(f"{relative} must be a JSON object")
        check_identity(value, relative, candidate_context=(relative == "CURRENT-CANDIDATE.json"))
        for location, record in walk(value, relative):
            if ".workingTree" in location or ".working_tree" in location:
                check_working_tree(record, location)
                continue
            if not (record.get("historical") is True or record.get("diagnosticOnly") is True or record.get("historicalEvidenceOnly") is True):
                check_identity(record, location, candidate_context=(".candidate" in location or location.endswith("CURRENT-CANDIDATE.json")))
        checked.append(path)

    for relative in ("outputs/release-fingerprint.json", "outputs/tooling-fingerprint-current.json"):
        path = root / relative
        if path.is_file():
            check_identity(load(path), relative)
            checked.append(path)
    artifacts = {str(row.get("name", "")).lower().replace("_", "").replace("-", ""): row for row in manifest.get("artifacts", []) if isinstance(row, dict)}
    if not {"exe", "tar", "portable", "installersource"}.issubset(artifacts):
        raise ValueError("Current artifact manifest is missing a required artifact row")
    for name, row in artifacts.items():
        path, digest = root / str(row.get("path") or ""), str(row.get("sha256") or "").lower()
        # Universal audit bundles intentionally exclude compiled binaries; in
        # that mode the artifact manifest is an evidence-only tuple and the
        # live workspace validator remains responsible for byte verification.
        bundle_manifest_path = root / "AUDIT-MANIFEST.json"
        embedded = True
        if bundle_manifest_path.is_file():
            try:
                embedded = bool(load(bundle_manifest_path).get("compiledArtifactsEmbedded", True))
            except (OSError, ValueError, json.JSONDecodeError):
                embedded = True
        if not path.is_file() and not embedded and len(digest) == 64 and int(row.get("bytes") or 0) > 0:
            continue
        if not path.is_file() or len(digest) != 64 or sha256(path) != digest:
            raise ValueError(f"Current artifact bytes/hash mismatch: {name}")

    passed = bool_value(state.get("full_release_passed", False), "finalization-state.json.full_release_passed")
    if not passed:
        # The current blocked state must still describe the one latest proof;
        # it is intentionally not required to contain final-release evidence.
        current_proof_path = root / "evidence/CURRENT-PROOF.json"
        if current_proof_path.is_file():
            current_proof = load(current_proof_path)
            if not isinstance(current_proof, dict):
                raise ValueError("evidence/CURRENT-PROOF.json must be a JSON object")
            outcome = str(current_proof.get("outcome") or "")
            if outcome == "PASS":
                # A natural exact proof can complete before FullRelease. Keep
                # its outcome truthful without granting any release promotion.
                final = current_proof.get("proofFinal")
                run_id = str(current_proof.get("runId") or "")
                if (not run_id or current_proof.get("status") != "PASS"
                        or current_proof.get("proofStartCurrent") is not True
                        or current_proof.get("certificationEligible") is not True
                        or current_proof.get("diagnosticOnly") is not False
                        or not isinstance(final, dict)
                        or final.get("status") != "PASS"
                        or final.get("runId") != run_id
                        or final.get("certificationEligible") is not True
                        or final.get("diagnosticOnly") is not False
                        or not isinstance(final.get("cleanup"), dict)
                        or final["cleanup"].get("status") != "PASS"):
                    raise ValueError("Intermediate PASS lacks a current qualifying natural proof and completed safety cleanup")
                if any(state.get(key) is not False for key in (
                        "validation_evidence_current", "internal_promotion_allowed",
                        "public_promotion_allowed")):
                    raise ValueError("Incomplete FullRelease cannot carry release promotion")
            elif outcome != "NOT_OBSERVED":
                raise ValueError("Incomplete current proof outcome is not fail-closed")
            elif str(current_proof.get("status") or "") not in {"BLOCKED", "NOT_OBSERVED"}:
                raise ValueError("Blocked current proof status is not fail-closed")
    if passed:
        missing = [relative for relative in CURRENT_AUTHORITIES if not (root / relative).is_file()]
        if missing or not (root / REQUIRED_SOURCE_PROOF).is_file():
            raise ValueError(f"Final authority/source evidence missing: {missing or [REQUIRED_SOURCE_PROOF]}")
        proof = load(root / "evidence/CURRENT-PROOF.json")
        if str(proof.get("outcome") or "") not in {"PASS", "REAL E2E PASS", "COMPLETED"}:
            raise ValueError("Final current proof is not PASS")
        for relative in ("evidence/l1-terminal-state.json", "evidence/l2-terminal-state.json"):
            if not (root / relative).is_file():
                raise ValueError(f"Final terminal evidence missing: {relative}")
    result = {"status": "PASS", "filesChecked": len({p.resolve() for p in checked}), "currentRepositoryHead": expected_head, "candidateCommit": candidate, "shippingInputIdentity": live_shipping, "candidateShippingInputIdentity": candidate_shipping, "currentReleaseFingerprintId": release, "currentToolingFingerprintId": tooling}
    if failed_result:
        result.update(failed_result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.root), sort_keys=True))
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"AUDIT COHERENCE FAIL: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: tools/validate_release_bundle.py

SHA256: 3bef9437795a08669e9fc2584f1ad1bf3d353d35b6416bd46d4a659206f7e4f7 | Bytes: 110347 | Git mode: 100644

```
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
                raise ValueError("FullRelease nested backe