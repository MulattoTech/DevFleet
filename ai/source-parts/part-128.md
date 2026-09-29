# DevFleet source part 128

Full-source UTF-8 byte interval [5905500, 5952000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 52ba1a5be61022efd4c54143cae769933cb3bfd69f6de85ad22b2d1cbd67c38f

<!-- BEGIN SOURCE SLICE -->
dardTokenRunId": standard_id, "proofRunIds": proof_ids})
    audit_pointer = {"schemaVersion": 1, "contract": "devfleet-pre-acceptance-release-audit-v1", "runId": audit_id, "status": "PASS", "bundleMode": "release", "releaseEligible": False, "internalPromotionAllowed": False, "publicPromotionAllowed": False, "publicPublisherTrust": False, "candidate": tuple_value, "fullReleaseRunId": run_id, "standardTokenRunId": standard_id, "proofRunIds": proof_ids, "inputs": {"fullReleaseRunStateSha256": full_bindings["runStateSha256"], "fullReleasePhaseRecordsSha256": full_bindings["phaseRecordsSha256"], "realUseBindingSha256": real_binding_hash, "realUsePrepareSha256": real_prepare_hash, "realUseReportSha256": real_hash, "realUseSummarySha256": full_bindings["realUseSummarySha256"], "cleanupSha256": full_bindings["cleanupSha256"], "postCleanupSha256": full_bindings["postCleanupSha256"], "terminalL1Sha256": l1_hash, "terminalL2Sha256": l2_hash, "standardTokenPointerSha256": digest(entries["evidence/CURRENT-STANDARD-TOKEN.json"]), "proofRunIds": proof_ids}, "evidence": {"archive": {"workspacePath": f"audit/release-audits/{audit_id}/release-audit.zip", "bundlePath": None, "bytes": 1234, "sha256": synthetic_archive_hash}, "report": {"workspacePath": f"audit/release-audits/{audit_id}/ai-audit-bundle-self-test.json", "bundlePath": report_name, "bytes": len(entries[report_name]), "sha256": digest(entries[report_name])}, "manifest": {"workspacePath": f"audit/release-audits/{audit_id}/release-audit.manifest.json", "bundlePath": audit_manifest_name, "bytes": len(entries[audit_manifest_name]), "sha256": digest(entries[audit_manifest_name])}, "releaseValidation": {"workspacePath": f"audit/release-audits/{audit_id}/pre-acceptance-validation.json", "bundlePath": audit_validation_name, "bytes": len(entries[audit_validation_name]), "sha256": digest(entries[audit_validation_name])}}, "checks": {"cleanExtraction": "PASS", "secrets": "PASS", "coherence": "PASS", "sourceCount": "PASS", "releaseValidation": "PASS"}, "gates": {"candidate": "PASS", "proofs": "2/2 PASS", "fullRelease": "PASS", "realUseAcceptance": "U01-U05 PASS", "maintenance": "5/5 PASS", "standardToken": "PASS", "reconcile": "PASS", "cleanup": "PASS", "l1": "OFF", "l2": "ABSENT", "releaseAudit": "PASS"}}
    put(entries, "evidence/CURRENT-RELEASE-AUDIT.json", audit_pointer)

    binding_values = {"standardTokenPointerSha256": digest(entries["evidence/CURRENT-STANDARD-TOKEN.json"]), "standardTokenCanonicalSha256": digest(entries[canonical_name]), "standardTokenRawReportSha256": digest(entries[raw_name]), "fullReleaseRunStateSha256": full_bindings["runStateSha256"], "fullReleasePhaseRecordsSha256": full_bindings["phaseRecordsSha256"], "realUseBindingSha256": real_binding_hash, "realUsePrepareSha256": real_prepare_hash, "realUseReportSha256": real_hash, "realUseSummarySha256": full_bindings["realUseSummarySha256"], "cleanupSha256": full_bindings["cleanupSha256"], "postCleanupSha256": full_bindings["postCleanupSha256"], "terminalL1Sha256": l1_hash, "terminalL2Sha256": l2_hash, "releaseAuditPointerSha256": digest(entries["evidence/CURRENT-RELEASE-AUDIT.json"]), "releaseAuditArchiveSha256": synthetic_archive_hash, "releaseAuditReportSha256": digest(entries[report_name]), "releaseAuditManifestSha256": digest(entries[audit_manifest_name]), "releaseAuditValidationSha256": digest(entries[audit_validation_name])}
    final = {"schemaVersion": 1, "contract": "devfleet-internal-final-acceptance-v1", "status": "PASS", "releaseEligible": True, "internalPromotionAllowed": True, "publicPromotionAllowed": False, "publicPublisherTrust": False, "candidate": {**tuple_value, "artifacts": {row["name"]: {"sha256": row["sha256"], "bytes": row["bytes"]} for row in release_record["artifacts"]}, "authenticode": {"status": "PASS", "signatureStatus": "Valid", "signerThumbprint": "DE42CD7369A01E9357BDA13597C0173E5E703E9D", "signerSubject": "CN=DevFleet Private Personal Code Signing", "codeSigningEkuVerified": True, "rsaBits": 3072, "exactCertificateMatch": True, "privateKeyExported": False}}, "proofRunIds": proof_ids, "fullReleaseRunId": run_id, "standardTokenRunId": standard_id, "releaseAuditRunId": audit_id, "bindings": binding_values, "gates": audit_pointer["gates"], "safety": {"f005Attempted": False, "formatterOnlyAuditCleanupPerformed": False, "f005StructuralRefactoringPerformed": False, "protectedProductionMutated": False, "hostRebooted": False, "amdRadeonTouched": False, "biosUefiTouched": False, "mulattoTechSurfaceTouched": False, "githubPushed": False, "privateSigningKeyExported": False, "ramPressureOverrideUsed": False, "productionUnchanged": True, "disposableLabOnly": True}}
    put(entries, "evidence/FINAL-ACCEPTANCE.json", final)
    return entries


def write_archive(entries: dict[str, bytes], path: Path) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)


def must_fail(entries: dict[str, bytes], mutate, label: str, mode: str = "final") -> None:
    changed = copy.deepcopy(entries)
    mutate(changed)
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "synthetic.zip"
        write_archive(changed, path)
        try:
            validate(path, mode)
        except ValueError:
            return
    raise AssertionError(f"negative bundle was accepted: {label}")


def main() -> None:
    # LATEST is the generic current-candidate diagnostic baseline. Historical
    # source checks have a separate deterministic fixture, independent of the
    # archive's optional historical pointer and old hard-coded candidate ID.
    diagnostic_result = validate(ARCHIVE, "diagnostic")
    assert diagnostic_result.get("status") == "PASS_WITH_BLOCKER"
    assert diagnostic_result.get("releaseEligible") is False
    # A pending diagnostic may truthfully have no current proof after rebind.
    # Compare with its actual pointer; final-mode acceptance remains strict.
    with zipfile.ZipFile(ARCHIVE) as archive:
        diagnostic_proof = json.loads(archive.read("evidence/CURRENT-PROOF.json").decode("utf-8-sig"))
    assert diagnostic_proof.get("outcome") in {"PASS", "NOT_OBSERVED"}
    assert diagnostic_result.get("proofOutcome") == diagnostic_proof["outcome"]
    assert diagnostic_result.get("candidateIsCurrent") is True
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        relative = "release-tooling/historical/fixture-proof/proof-start.json"
        historical_root = (root / relative).parent
        historical_root.mkdir(parents=True)
        source_map = {"proofScriptSha256": "run-exact-candidate-proof.ps1", "invokeRealProductPhaseSha256": "Invoke-RealProductPhase.psm1", "invokeWpfUiAutomationSha256": "Invoke-WpfUiAutomation.ps1"}
        provenance = {}
        for key, name in source_map.items():
            content = name.encode()
            (historical_root / name).write_bytes(content)
            provenance[key] = digest(content)
        (root / relative).write_text(json.dumps({"provenance": provenance}), encoding="utf-8")
        current = {"proofStartHistoricalPath": relative}
        validate_historical_proof_sources(root, current)
        source_path = historical_root / "run-exact-candidate-proof.ps1"
        original = source_path.read_bytes()
        for mutation in ("missing", "wrong"):
            if mutation == "missing":
                source_path.unlink()
            else:
                source_path.write_bytes(b"wrong historical bytes")
            try:
                validate_historical_proof_sources(root, current)
            except ValueError:
                pass
            else:
                raise AssertionError(f"{mutation} historical source was accepted")
            source_path.write_bytes(original)
    entries = final_entries()
    full_state = read_json(entries, "evidence/current-fullrelease/run-state.json")
    full_run_id = str(full_state["runId"])
    terminal_l1 = read_json(entries, "evidence/current-fullrelease/l1-terminal-state.json")
    terminal_l2 = read_json(entries, "evidence/current-fullrelease/l2-terminal-state.json")
    candidate_tuple = {key: str(full_state["candidateHashes"][key]) for key in ("repositoryHead", "candidateCommit", "shippingInputIdentity", "releaseFingerprintId", "toolingFingerprintId")}
    nested_validation_cases = 3
    nested_symlink_skipped = []
    with tempfile.TemporaryDirectory() as nested_directory:
        nested_root = Path(nested_directory)
        for name in ("nested-l2-terminal-observation.json",):
            (nested_root / name).write_bytes(entries[f"evidence/current-fullrelease/{name}"])
        _validate_nested_l2_terminal(nested_root, terminal_l2, terminal_l1, candidate_tuple, full_run_id)
        legacy_l2 = {"expectedName": "DevFleet-E2E-Linux-01", "status": "ABSENT", "present": False, "timestampUtc": "2026-08-30T00:00:01Z", "verificationMethod": "Get-VM -Name exact returned no VM"}
        try:
            _validate_nested_l2_terminal(nested_root, legacy_l2, terminal_l1, candidate_tuple, full_run_id)
        except ValueError:
            pass
        else:
            raise AssertionError("host-only L2 absence passed the nested terminal validator")
        nested_path = nested_root / "nested-l2-terminal-observation.json"
        valid_nested_bytes = nested_path.read_bytes()
        valid_nested = json.loads(valid_nested_bytes)
        for label, field, bad_value, message in (
            ("boolean exact-match count", "exactMatchCount", False, "zero exact matches"),
            ("boolean inventory count", "inventoryCount", True, "inventory completeness"),
        ):
            bad_nested = {**valid_nested, field: bad_value}
            bad_bytes = json.dumps(bad_nested).encode()
            nested_path.write_bytes(bad_bytes)
            bad_terminal = {**terminal_l2, "sourceEvidenceSha256": digest(bad_bytes)}
            try:
                _validate_nested_l2_terminal(nested_root, bad_terminal, terminal_l1, candidate_tuple, full_run_id)
            except ValueError as exc:
                if message not in str(exc):
                    raise AssertionError(f"{label} rejected for the wrong reason: {exc}") from exc
            else:
                raise AssertionError(f"{label} was accepted as exact nested terminal evidence")
        backend_verification = "Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend"
        duplicate_backend = {
            **valid_nested,
            "verification": backend_verification,
            "inventoryCount": 2,
            "backendInventories": [
                {"provider": "Hyper-V", "status": "PASS", "names": ["foreign-instance", "foreign-instance"], "verification": "bounded Hyper-V inventory"},
                {"provider": "VirtualBox", "status": "PASS", "names": [], "verification": "bounded VirtualBox inventory"},
            ],
        }
        duplicate_bytes = json.dumps(duplicate_backend).encode()
        nested_path.write_bytes(duplicate_bytes)
        duplicate_terminal = {**terminal_l2, "verificationMethod": backend_verification, "sourceEvidenceSha256": digest(duplicate_bytes)}
        try:
            _validate_nested_l2_terminal(nested_root, duplicate_terminal, terminal_l1, candidate_tuple, full_run_id)
        except ValueError as exc:
            if "duplicate instance name" not in str(exc):
                raise AssertionError(f"duplicate backend names were rejected for the wrong reason: {exc}") from exc
        else:
            raise AssertionError("duplicate nested backend names were accepted as complete absence evidence")
        nested_validation_cases += 1
        nested_path.write_bytes(valid_nested_bytes)
        with tempfile.TemporaryDirectory() as external_directory:
            outside = Path(external_directory) / "outside-nested-evidence.json"
            outside.write_bytes(valid_nested_bytes)
            nested_path.unlink()
            try:
                nested_path.symlink_to(outside)
            except (OSError, NotImplementedError) as exc:
                nested_path.write_bytes(valid_nested_bytes)
                nested_symlink_skipped.append(f"source symlink rejection ({type(exc).__name__})")
            else:
                try:
                    try:
                        _validate_nested_l2_terminal(nested_root, terminal_l2, terminal_l1, candidate_tuple, full_run_id)
                    except ValueError as exc:
                        if "reparse or symlink escape" not in str(exc):
                            raise AssertionError(f"source symlink rejected for the wrong reason: {exc}") from exc
                    else:
                        raise AssertionError("nested source symlink outside the FullRelease run root was accepted")
                    nested_validation_cases += 1
                finally:
                    nested_path.unlink(missing_ok=True)
                    nested_path.write_bytes(valid_nested_bytes)
    with tempfile.TemporaryDirectory() as directory:
        good = Path(directory) / "good.zip"
        write_archive(entries, good)
        validate(good, "final")
    must_fail(
        entries,
        lambda e: put(
            e,
            "evidence/current-fullrelease/run-state.json",
            {**read_json(e, "evidence/current-fullrelease/run-state.json"), "finalStatus": "BLOCKED"},
        ),
        "incomplete FullRelease remains pending and cannot validate",
    )
    must_fail(entries, lambda e: [e.update({f"evidence/proof-runs/e2e-proof2-synthetic/proof-start.json": json.dumps({**read_json(e, "evidence/proof-runs/e2e-proof2-synthetic/proof-start.json"), "provenance": {**read_json(e, "evidence/proof-runs/e2e-proof2-synthetic/proof-start.json")["provenance"], "transactionId": "transaction-1", "checkpointLineageId": "lineage-1"}}).encode()})], "reused transaction/lineage")
    must_fail(entries, lambda e: [e.update({"evidence/proof-runs/e2e-proof2-synthetic/proof-final.json": json.dumps({"runId": "wrong-run", "status": "PASS"}).encode()})], "mixed RunId")
    must_fail(entries, lambda e: [e.update({"evidence/current-fullrelease/post-cleanup-finalization.json": json.dumps({"status": "PASS", "runId": "FullRelease-synthetic-current", "cleanupConsumed": True, "reconcileAfterCleanup": True}).encode()})], "absent liveChecks")
    must_fail(entries, lambda e: [e.update({"evidence/current-fullrelease/post-cleanup-finalization.json": json.dumps({**read_json(e, "evidence/current-fullrelease/post-cleanup-finalization.json"), "liveChecks": {"l1ExactOff": False, "l2ExactAbsent": True}}).encode()})], "false liveChecks")
    must_fail(entries, lambda e: [e.update({"evidence/current-fullrelease/final-cleanup.json": b"{\"status\":\"tampered\"}"})], "cleanup hash mismatch")
    must_fail(entries, lambda e: [e.update({"evidence/l1-terminal-state.json": b"{\"state\":\"Running\"}"})], "terminal hash mismatch")
    must_fail(entries, lambda e: e.pop("evidence/FINAL-ACCEPTANCE.json"), "omitted FINAL-ACCEPTANCE")
    raw_path = read_json(entries, "evidence/CURRENT-STANDARD-TOKEN.json")["rawReportPath"]
    must_fail(entries, lambda e: e.update({raw_path: e[raw_path] + b"tamper\n"}), "tampered immutable standard-token raw report")
    must_fail(entries, lambda e: put(e, "evidence/FINAL-ACCEPTANCE.json", {**read_json(e, "evidence/FINAL-ACCEPTANCE.json"), "fullReleaseRunId": "FullRelease-stale"}), "stale FINAL-ACCEPTANCE tuple/lineage")
    audit_report_path = read_json(entries, "evidence/CURRENT-RELEASE-AUDIT.json")["evidence"]["report"]["bundlePath"]
    must_fail(entries, lambda e: e.update({audit_report_path: e[audit_report_path] + b"\n"}), "tampered immutable release-audit report")
    pre_entries = copy.deepcopy(entries)
    pre_entries.pop("evidence/FINAL-ACCEPTANCE.json")
    pre_entries.pop("evidence/CURRENT-RELEASE-AUDIT.json")
    for name in list(pre_entries):
        if name.startswith("evidence/release-audits/"):
            del pre_entries[name]
    with tempfile.TemporaryDirectory() as directory:
        pre_good = Path(directory) / "pre-good.zip"
        write_archive(pre_entries, pre_good)
        pre_result = validate(pre_good, "pre-acceptance")
        assert pre_result["status"] == "PASS" and pre_result["releaseEligible"] is False
    must_fail(pre_entries, lambda e: e.update({"evidence/FINAL-ACCEPTANCE.json": entries["evidence/FINAL-ACCEPTANCE.json"]}), "pre-acceptance FINAL cycle", "pre-acceptance")
    print(json.dumps({"status": "PASS", "cases": 13 + nested_validation_cases, "skipped": nested_symlink_skipped}))


if __name__ == "__main__":
    main()

```


## FILE: tools/test_validate_release_bundle_generation5.py

SHA256: b3cc6cd0a57807586655b7dc13de0ae9a0d98d72a433a96352634461f1fb9471 | Bytes: 6130 | Git mode: 100644

```
"""VM-free generation-5 validator checks for the immutable gen4 chain."""
import copy
import json
import unittest

from test_baseline_generation4 import Generation4Tests
from validate_release_bundle import load_accepted_baseline, sha


class Generation5ValidatorTests(unittest.TestCase):
    def setUp(self):
        self.case = Generation4Tests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        self.case.bind()
        pointer_path = self.root / 'evidence/baselines/CURRENT.json'
        self.previous_pointer = json.loads(pointer_path.read_text(encoding='utf-8'))
        previous_bytes = pointer_path.read_bytes()
        previous_hash = sha(pointer_path)
        (self.root / 'evidence/baselines/history' / (previous_hash + '.json')).write_bytes(previous_bytes)
        self.old = self.case.v4_tuple
        self.new = {**self.old, 'repositoryHead': 'e' * 40,
                    'toolingFingerprintId': '1' * 64}
        sources = self.root / 'evidence/baselines/sources'
        old_receipt = json.loads(
            (self.root / 'evidence/baselines/receipts' /
             self.previous_pointer['receiptFile']).read_text(encoding='utf-8'))
        old_ledger_path = sources / (old_receipt['successorLedgerSha256'] + '.json')
        ledger = json.loads(old_ledger_path.read_text(encoding='utf-8'))
        ledger['policyId'] = 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5'
        ledger['attempts'] = [{**ledger['attempts'][0], 'tuple': self.new,
                              'operation': 'standard-token', 'state': 'TERMINAL',
                              'exitCode': 0, 'classification': 'PASS_NATIVE_STANDARD_TOKEN',
                              'certificationCredit': False, 'evidence': ['gen5-proof.json']}]
        ledger_path = self.root / 'gen5-ledger.json'
        ledger_path.write_text(json.dumps(ledger), encoding='utf-8')
        inventory_path = sources / (old_receipt['nativeInventorySha256'] + '.json')
        ledger_hash = sha(ledger_path)
        inventory_hash = sha(inventory_path)
        sources.joinpath(ledger_hash + '.json').write_bytes(ledger_path.read_bytes())
        receipt_id = '5' * 32
        receipt = {
            'schemaVersion': 5, 'contract': 'devfleet-baseline-rebind-receipt-v5',
            'receiptId': receipt_id, 'status': 'REBOUND',
            'certificationCredit': False, 'secretValuesRecorded': False,
            'previousPointerSha256': previous_hash,
            'previousReceiptSha256': self.previous_pointer['receiptSha256'],
            'replacement': self.previous_pointer['checkpoint'],
            'previousCandidate': self.old, 'candidate': self.new,
            'approvalSha256': 'a' * 64,
            'approval': {
                'schemaVersion': 4, 'contract': 'devfleet-baseline-rebind-approval-v4',
                'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                'shippingChangeApproved': False, 'previousCandidate': self.old,
                'candidate': self.new, 'replacement': self.previous_pointer['checkpoint'],
                'previousReceiptSha256': self.previous_pointer['receiptSha256'],
                'sourceSha256': 'a' * 64},
            'finalL1': {'name': 'DevFleet-E2E-Win11-01',
                        'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2', 'state': 'Off'},
            'successorPolicyId': 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5',
            'successorLedgerSha256': ledger_hash,
            'nativeInventorySha256': inventory_hash,
        }
        receipt_path = self.root / 'evidence/baselines/receipts' / (receipt_id + '.json')
        receipt_path.write_text(json.dumps(receipt), encoding='utf-8')
        pointer = {'schemaVersion': 5, 'contract': 'devfleet-accepted-baseline-v5',
                   'generation': 5, 'status': 'ACCEPTED',
                   'receiptFile': receipt_id + '.json', 'receiptSha256': sha(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': self.previous_pointer['checkpoint']}
        pointer_path.write_text(json.dumps(pointer), encoding='utf-8')

    def validate(self):
        expected = {'repositoryHead': self.new['repositoryHead'],
                    'candidateCommit': self.new['candidateBuildCommit'],
                    'shippingInputIdentity': self.new['shippingInputIdentity'],
                    'releaseFingerprintId': self.new['releaseFingerprintId'],
                    'toolingFingerprintId': self.new['toolingFingerprintId']}
        return load_accepted_baseline(self.root, expected, {'exe': self.new['candidateSha256']})

    def test_exact_gen5_chain_is_accepted(self):
        result = self.validate()
        self.assertTrue(result['receiptSha256'])
        self.assertEqual(result['name'], 'DevFleet-E2E-CLEAN-R2')

    def test_gen5_requires_owner_schema_and_single_terminal_attempt(self):
        receipt_path = self.root / 'evidence/baselines/receipts' / ('5' * 32 + '.json')
        receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
        receipt['approval']['schemaVersion'] = 2
        receipt_path.write_text(json.dumps(receipt), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.validate()
        receipt['approval']['schemaVersion'] = 4
        receipt_path.write_text(json.dumps(receipt), encoding='utf-8')
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text(encoding='utf-8'))
        pointer['receiptSha256'] = sha(receipt_path)
        (self.root / 'evidence/baselines/CURRENT.json').write_text(json.dumps(pointer), encoding='utf-8')
        source_hash = receipt['successorLedgerSha256']
        source = self.root / 'evidence/baselines/sources' / (source_hash + '.json')
        ledger = json.loads(source.read_text(encoding='utf-8'))
        ledger['attempts'].append(copy.deepcopy(ledger['attempts'][0]))
        source.write_text(json.dumps(ledger), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.validate()


if __name__ == '__main__':
    unittest.main()

```


## FILE: tools/validate_audit_coherence.py

SHA256: 13f4bfa1db5cedd99da67b211c0d18e3330d19e1291e8e027aa4152aff812b90 | Bytes: 18596 | Git mode: 100644

```
"""Validate current release-tooling authorities without rewriting identity."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any, Iterable

CURRENT_AUTHORITIES = (
    "AUDIT-MANIFEST.json", "CURRENT-CANDIDATE.json", "finalization-state.json",
    "outputs/final-artifact-hashes.json", "evidence/CURRENT-STATUS.json",
    "evidence/CURRENT-GATES.json", "evidence/CURRENT-PROOF.json",
    "evidence/FULLRELEASE-SUMMARY.json", "audit/CURRENT-HANDOFF.json",
    "evidence/CURRENT-HANDOFF.json",
)
REQUIRED_SOURCE_PROOF = "release-tooling/proof-entrypoints/run-exact-candidate-proof.ps1"
FAILED_ATTEMPT_SNAPSHOT = "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
FAILED_ATTEMPT_SNAPSHOT_SHA256 = "ac37997945b6fa5ae9326b083ee730494b2c0c2e60d4809e7b49fc9707c0caac"
FAILED_ATTEMPT_BLOCKER = "REPLACEMENT_CANDIDATE_BINDING_MISMATCH"


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def walk(value: Any, location: str) -> Iterable[tuple[str, dict[str, Any]]]:
    if isinstance(value, dict):
        yield location, value
        for key, child in value.items():
            yield from walk(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk(child, f"{location}[{index}]")


def bool_value(value: Any, location: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{location} must be a JSON boolean")
    return value


def git_head(root: Path) -> str:
    try:
        return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def validate_failed_attempt_authority(root: Path, state: dict[str, Any]) -> dict[str, Any] | None:
    snapshot_path = root / Path(*FAILED_ATTEMPT_SNAPSHOT.split("/"))
    if not snapshot_path.is_file():
        return None
    if sha256(snapshot_path) != FAILED_ATTEMPT_SNAPSHOT_SHA256:
        raise ValueError("failed replacement-attempt snapshot is missing or hash-mismatched")
    snapshot = load(snapshot_path)
    if snapshot.get("immutableSnapshot") is not True or snapshot.get("freezeType") != "LUNA_HIGH_FAILED_ATTEMPT_EVIDENCE_FREEZE":
        raise ValueError("failed replacement-attempt snapshot is not immutable evidence")
    shipping = snapshot.get("shippingIdentity") if isinstance(snapshot.get("shippingIdentity"), dict) else {}
    archive = shipping.get("gitArchive") if isinstance(shipping.get("gitArchive"), dict) else {}
    live = shipping.get("buildTimeLive") if isinstance(shipping.get("buildTimeLive"), dict) else {}
    if archive.get("rowCount") != 730 or live.get("rowCount") != 730 or archive.get("identity") != "6e0bac4b4eebc83cdcd9eddda2008607ba15c8835e5c72a931792f5b83c653f4" or live.get("identity") != "3a65fd54d70fe05565ac3a32f73100ca2c81a77a4008feb361f99f229f025f8a":
        raise ValueError("failed replacement-attempt snapshot shipping identity is invalid")
    diff = shipping.get("normalizedRowDiff") if isinstance(shipping.get("normalizedRowDiff"), dict) else {}
    rows = diff.get("rows")
    if diff.get("rowCount") != 28 or diff.get("crlfOnlyRows") != 25 or diff.get("exactChangedRows") != 3 or not isinstance(rows, list) or len(rows) != 28:
        raise ValueError("failed replacement-attempt snapshot row partition is invalid")
    generated = {"source/CHECKSUMS.sha256", "installer-source/DevFleet.Setup/PayloadManifest.cs", "installer-source/INSTALLER-BUILD-MANIFEST.json"}
    if {f"{r.get('root')}/{r.get('path')}" for r in rows if isinstance(r, dict) and r.get("comparison") == "CONTENT_OR_GENERATED_CHANGE"} != generated or sum(1 for r in rows if isinstance(r, dict) and r.get("comparison") == "CRLF_ONLY_NORMALIZED_EQUAL") != 25:
        raise ValueError("failed replacement-attempt snapshot generated/CRLF partition is invalid")
    candidate_commit = str(
        state.get("candidate_git_commit")
        or state.get("candidateGitCommit")
        or state.get("candidateCommit")
        or ""
    ).lower()
    failed_attempt_bound = (
        candidate_commit == "21752fc0e50978183322204c523b40947d073aa0"
        or str(state.get("blocker_code") or "") == FAILED_ATTEMPT_BLOCKER
    )
    if not failed_attempt_bound:
        # The immutable failed-attempt snapshot is retained for historical
        # review.  Once current authority has advanced to another candidate,
        # it must not force the current state back to the old blocked tuple.
        return {
            "historicalFailedAttempt": True,
            "historicalFailedAttemptPath": FAILED_ATTEMPT_SNAPSHOT,
            "releaseEligible": False,
        }
    attempt = state.get("failed_replacement_attempt")
    if not isinstance(attempt, dict) or attempt.get("snapshotPath") != FAILED_ATTEMPT_SNAPSHOT or attempt.get("snapshotSha256") != FAILED_ATTEMPT_SNAPSHOT_SHA256 or attempt.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or attempt.get("artifactTupleValid") is not True or attempt.get("artifactTupleMatchesCandidate") is not False:
        raise ValueError("current authority does not bind the failed replacement attempt")
    if (state.get("candidate_is_current"), state.get("source_changed_since_candidate"), state.get("rebuild_required"), state.get("artifact_tuple_matches_candidate"), state.get("full_release_passed"), state.get("internal_promotion_allowed"), state.get("public_promotion_allowed")) != (False, True, True, False, False, False, False):
        raise ValueError("failed replacement-attempt authority flags are not truthful")
    if state.get("status") != "BLOCKED — USER ACTION REQUIRED" or state.get("blocker_code") != FAILED_ATTEMPT_BLOCKER:
        raise ValueError("failed replacement-attempt status is not user-action blocked")
    return {"status": "PASS_WITH_BLOCKER", "blockerCode": FAILED_ATTEMPT_BLOCKER, "releaseEligible": False}


def validate(root: Path) -> dict[str, Any]:
    root = root.resolve()
    state_path = root / "finalization-state.json"
    manifest_path = root / "outputs" / "final-artifact-hashes.json"
    if not state_path.is_file() or not manifest_path.is_file():
        raise ValueError("Current finalization state and artifact manifest are required")
    state, manifest = load(state_path), load(manifest_path)
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

SHA256: 1228d4de2428f2c9adbaadabed05ac581c14f5b7f48ec99613f16fe8dafdca8a | Bytes: 136303 | Git mode: 100644

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
    "evidence/CURRENT-GATES.json", "evidence/CURR