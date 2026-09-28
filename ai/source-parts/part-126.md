# DevFleet source part 126

Full-source UTF-8 byte interval [5812500, 5859000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: d44f29a32bd4c74c8486da9a270f6f68cbe8084b569fad3cc2d1fc77b6a8c0cf

<!-- BEGIN SOURCE SLICE -->
rds for the native final-acceptance entrypoints."""
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require(text: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise AssertionError(f"{label} is missing fail-closed contract text: {missing}")


def main() -> None:
    complete = (ROOT / "tools/Complete-DevFleetInternalAcceptance.ps1").read_text(encoding="utf-8-sig")
    authority = (ROOT / "tools/Update-CurrentReleaseAuthority.ps1").read_text(encoding="utf-8-sig")
    builder = (ROOT / "tools/Build-AIAuditBundle.ps1").read_text(encoding="utf-8-sig")
    validator = (ROOT / "tools/validate_release_bundle.py").read_text(encoding="utf-8-sig")

    require(complete, (
        "--check pre-acceptance", "Test-PrivateAuthenticodeSignature",
        "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "DevFleet-E2E-Win11-01",
        "DevFleet-E2E-Linux-01", "FINAL-ACCEPTANCE.json",
        "--check final-acceptance --final-record $pendingFinalPath",
        "Move-Item -LiteralPath $pendingFinalPath -Destination $finalPath -Force",
        "status='BLOCKED'", "INTERNAL_ACCEPTANCE_BLOCKED",
        "validation_evidence_current' $false", "internal_promotion_allowed' $false",
        "public_promotion_allowed' $false",
    ), "completion tool")
    require(authority, (
        "--check final-acceptance", "$finalAcceptanceValid",
        "validationEvidenceCurrent = $finalAcceptanceValid",
        "internalPromotionAllowed = $finalAcceptanceValid",
        "$releaseEligible = $finalAcceptanceValid",
        "$mutableState.internal_promotion_allowed=$finalAcceptanceValid",
        "$mutableState.public_promotion_allowed=$false",
    ), "authority updater")
    require(builder, (
        "PreAcceptanceReleaseAudit", "--check release-evidence",
        "--mode $releaseValidationMode", "pre-acceptance",
        "release-audits", "CURRENT-RELEASE-AUDIT.json",
        "devfleet-pre-acceptance-release-audit-v1",
        "releaseEligible=$false", "internalPromotionAllowed=$false",
    ), "audit builder")
    require(validator, (
        '"pre-acceptance"', "validate_final_acceptance",
        "CURRENT-STANDARD-TOKEN.json", "FINAL-ACCEPTANCE.json",
        "REAL-USE-ACCEPTANCE", "U01", "U05",
        "pre-acceptance audit contains post-audit evidence (cycle)",
    ), "release-bundle validator")
    if authority.find("--check final-acceptance") > authority.find("$candidateFlags ="):
        raise AssertionError("authority reads candidate promotion flags before validating FINAL-ACCEPTANCE")
    staged = complete.find("Write-AtomicJson $pendingFinalPath $final")
    validated = complete.find("--check final-acceptance --final-record $pendingFinalPath")
    published = complete.find("Move-Item -LiteralPath $pendingFinalPath -Destination $finalPath -Force")
    if min(staged, validated, published) < 0 or not staged < validated < published:
        raise AssertionError("completion tool must stage, validate, then atomically publish FINAL")
    if "Write-AtomicJson $finalPath $final" in complete:
        raise AssertionError("completion tool publishes FINAL before independent validation")
    print(json.dumps({"status": "PASS", "checks": 4}, sort_keys=True))


if __name__ == "__main__":
    main()

```


## FILE: tools/test_release_tooling_corrections.py

SHA256: 9a823f6a74ca782ed6e7f2d3b8051bc9f79a0fa41557b61a494c4bf39c23f2f5 | Bytes: 7014 | Git mode: 100644

```
"""Focused regressions for the bounded release-tooling correction batch."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

import validate_audit_coherence as coherence
import validate_release_bundle as release_bundle


ROOT = Path(__file__).resolve().parents[1]


def _workspace_fixture(tmp_path: Path):
    root = tmp_path / "workspace"
    outputs = root / "outputs"
    outputs.mkdir(parents=True)
    head = "a" * 40
    candidate = "b" * 40
    shipping = "c" * 64
    release = "d" * 64
    tooling = "e" * 64
    rows = []
    for name in ("exe", "tar", "portable", "installerSource"):
        path = outputs / f"{name}.bin"
        path.write_bytes((name + "\n").encode())
        rows.append({
            "name": name,
            "path": f"outputs/{path.name}",
            "bytes": path.stat().st_size,
            "sha256": __import__("hashlib").sha256(path.read_bytes()).hexdigest(),
        })
    certificate = outputs / "certificate.cer"
    certificate.write_bytes(b"certificate\n")
    manifest = {
        "repositoryHead": head,
        "candidateGitCommit": candidate,
        "shippingInputIdentity": shipping,
        "releaseFingerprintId": release,
        "toolingFingerprintId": tooling,
        "artifacts": rows,
        "publicCertificate": {
            "path": "outputs/certificate.cer",
            "bytes": certificate.stat().st_size,
            "sha256": __import__("hashlib").sha256(certificate.read_bytes()).hexdigest(),
        },
    }
    (outputs / "final-artifact-hashes.json").write_text(json.dumps(manifest), encoding="utf-8")
    (outputs / "release-fingerprint.json").write_text(json.dumps({
        "releaseFingerprintId": release,
        "toolingFingerprint": {"toolingFingerprintId": tooling},
    }), encoding="utf-8")
    (outputs / "tooling-fingerprint-current.json").write_text(json.dumps({
        "repositoryHead": head,
        "candidateGitCommit": candidate,
        "shippingInputIdentity": shipping,
        "releaseFingerprintId": release,
        "toolingFingerprintId": tooling,
    }), encoding="utf-8")
    (outputs / "SIGNING-PROVIDER.json").write_text(json.dumps({
        "signatureStatus": "Valid",
        "signerThumbprint": "DE42CD7369A01E9357BDA13597C0173E5E703E9D",
        "signerSubject": "CN=DevFleet Private Personal Code Signing",
        "codeSigningEkuVerified": True,
        "rsaBits": 3072,
        "privateKeyExportable": False,
        "privateKeyExported": False,
        "publicPublisherTrust": False,
        "publicPromotionAllowed": False,
        "finalSignedExe": rows[0],
    }), encoding="utf-8")
    expected = {
        "repositoryHead": head,
        "candidateCommit": candidate,
        "shippingInputIdentity": shipping,
        "releaseFingerprintId": release,
        "toolingFingerprintId": tooling,
    }
    artifacts = {
        row["name"]: {key: row[key] for key in ("name", "bytes", "sha256")}
        for row in rows
    }
    return root, expected, artifacts


def test_workspace_validator_forwards_exact_artifact_tuple(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    root, expected, artifacts = _workspace_fixture(tmp_path)
    calls = []
    identity = {
        "liveShippingInputIdentity": expected["shippingInputIdentity"],
        "candidateShippingInputIdentity": expected["shippingInputIdentity"],
        "liveReleaseFingerprintId": expected["releaseFingerprintId"],
        "candidateReleaseFingerprintId": expected["releaseFingerprintId"],
        "liveToolingFingerprint": {"toolingFingerprintId": expected["toolingFingerprintId"]},
    }

    def fake_run(args, **kwargs):
        calls.append(list(args))
        if args[0] == "git":
            return SimpleNamespace(returncode=0, stdout=expected["repositoryHead"], stderr="")
        return SimpleNamespace(returncode=0, stdout=json.dumps(identity), stderr="")

    monkeypatch.setattr(release_bundle.subprocess, "run", fake_run)
    release_bundle._validate_workspace_candidate(root, expected, artifacts)
    identity_call = next(args for args in calls if "compute_shipping_input_identity.py" in args[1])
    forwarded = [identity_call[i + 1] for i, value in enumerate(identity_call[:-1]) if value == "--artifact"]
    assert sorted(forwarded) == sorted(
        f"{name}={root / 'outputs' / (name + '.bin')}" for name in artifacts
    )


def test_workspace_validator_rejects_wrong_head_before_identity(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    root, expected, artifacts = _workspace_fixture(tmp_path)

    def fake_run(args, **kwargs):
        return SimpleNamespace(returncode=0, stdout="f" * 40, stderr="")

    monkeypatch.setattr(release_bundle.subprocess, "run", fake_run)
    with pytest.raises(ValueError, match="live repository HEAD differs"):
        release_bundle._validate_workspace_candidate(root, expected, artifacts)


def test_current_tooling_snapshot_is_historical_after_authority_advances():
    state = json.loads((ROOT / "finalization-state.json").read_text(encoding="utf-8-sig"))
    result = coherence.validate_failed_attempt_authority(ROOT, state)
    assert result["historicalFailedAttempt"] is True
    assert result["releaseEligible"] is False


def test_finalize_writer_carries_repository_head_without_hashing_metadata():
    source = (ROOT / "tools/Finalize-CandidateEvidence.ps1").read_text(encoding="utf-8-sig")
    assert "repositoryHead=$head" in source
    fingerprint = (ROOT / "source/tools/release_fingerprint.py").read_text(encoding="utf-8-sig")
    assert 'canonical = {"schemaVersion": 1, "toolingInputs": entries}' in fingerprint
    acceptance = (ROOT / "tools/Complete-DevFleetInternalAcceptance.ps1").read_text(encoding="utf-8-sig")
    assert "@('--artifact'" in acceptance
    authority = (ROOT / "tools/Update-CurrentReleaseAuthority.ps1").read_text(encoding="utf-8-sig")
    assert "proofFinal=if($proofStartCurrent -and $proofFinalRecord)" in authority


def test_finalizer_does_not_treat_a_stale_native_exit_code_as_script_failure():
    source = (ROOT / "tools/Finalize-CandidateEvidence.ps1").read_text(encoding="utf-8-sig")
    invocation = "$authorityOutput = @(& (Join-Path $Workspace 'tools\\Update-CurrentReleaseAuthority.ps1') -Workspace $Workspace)"
    assert invocation in source
    tail = source[source.index(invocation):]
    assert "$authoritySucceeded = $?" in tail
    assert "if (-not $authoritySucceeded -or $authorityOutput.Count -eq 0)" in tail
    assert "if ($LASTEXITCODE -ne 0 -or $authorityOutput.Count -eq 0)" not in tail


def test_release_evidence_gate_requires_terminal_fullrelease_and_never_promotes_pending_state():
    source = (ROOT / "tools/validate_release_bundle.py").read_text(encoding="utf-8-sig")
    assert 'run_state.get("finalStatus") != "PASS"' in source
    assert 'raise ValueError("current FullRelease is not one coherent terminal PASS")' in source
    assert 'result["releaseEligible"] = False' not in source

```


## FILE: tools/test_repair3_validator.py

SHA256: 058ac7dac7ef6ce504a7103a110bf800d0d2aa7290b2d177ec0e9a2ae0e6148d | Bytes: 3911 | Git mode: 100644

```
import unittest
from pathlib import Path
import sys
import hashlib
import json
import tempfile

sys.path.insert(0, str(Path(__file__).parent))
from validate_release_bundle import (_load_packaged_repair3_receipt,
                                     _validate_repair3_attempts,
                                     _validate_repair3_receipt_hash_binding,
                                     _validate_repair3_signed_output_receipt)


class Repair3ReceiptValidatorTests(unittest.TestCase):
    def setUp(self):
        self.candidate = {
            'repositoryHead': 'a' * 40,
            'candidateBuildCommit': 'b' * 40,
            'shippingInputIdentity': 'c' * 64,
            'candidateSha256': 'd' * 64,
        }
        self.receipt = {
            'schemaVersion': 1,
            'contract': 'devfleet-signed-build-output-inspection-v1',
            'status': 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION',
            'certificationCredit': False,
            # The signed output is built at the frozen candidate commit;
            # repository HEAD may advance for tooling integration.
            'repositoryHead': self.candidate['candidateBuildCommit'],
            'shippingInputIdentity': self.candidate['shippingInputIdentity'],
            'signatureStatus': 'Valid',
            'publicPromotionAllowed': False,
            'publicPublisherTrust': False,
            'artifacts': [
                {'name': 'exe', 'path': 'candidate.exe', 'sha256': self.candidate['candidateSha256']},
                {'name': 'tar', 'path': 'candidate.tar.gz', 'sha256': '1' * 64},
                {'name': 'portable', 'path': 'candidate.zip', 'sha256': '2' * 64},
                {'name': 'installerSource', 'path': 'installer.zip', 'sha256': '3' * 64},
            ],
        }

    def test_changed_repository_head_same_candidate_build_is_accepted(self):
        _validate_repair3_signed_output_receipt(self.receipt, self.candidate)

    def test_missing_or_duplicate_artifact_is_rejected(self):
        self.receipt['artifacts'][-1] = dict(self.receipt['artifacts'][0])
        with self.assertRaisesRegex(ValueError, 'receipt contents'):
            _validate_repair3_signed_output_receipt(self.receipt, self.candidate)

    def test_packaged_receipt_required_even_when_absolute_path_is_available(self):
        with tempfile.TemporaryDirectory() as temp:
            sources = Path(temp) / 'sources'
            sources.mkdir()
            receipt_path = Path(temp) / 'host-receipt.json'
            receipt_path.write_text(json.dumps(self.receipt), encoding='utf-8')
            digest = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError, 'absent'):
                _load_packaged_repair3_receipt(sources, digest)
            (sources / f'{digest}.json').write_bytes(receipt_path.read_bytes())
            self.assertEqual(_load_packaged_repair3_receipt(sources, digest), self.receipt)

    def test_repair3_snapshot_has_exactly_one_terminal_standard_token(self):
        attempt = {'operation': 'standard-token', 'state': 'TERMINAL', 'exitCode': 0,
                   'classification': 'PASS_NATIVE_STANDARD_TOKEN', 'tuple': self.candidate,
                   'certificationCredit': False, 'evidence': ['standard-token.json']}
        _validate_repair3_attempts([attempt], self.candidate)
        with self.assertRaisesRegex(ValueError, 'standard token'):
            _validate_repair3_attempts([attempt, dict(attempt)], self.candidate)

    def test_baseline_receipt_hash_must_match_ledger_receipt_hash(self):
        digest = 'e' * 64
        _validate_repair3_receipt_hash_binding({'artifactReceiptSha256': digest}, digest)
        with self.assertRaisesRegex(ValueError, 'hashes differ'):
            _validate_repair3_receipt_hash_binding({'artifactReceiptSha256': 'f' * 64}, digest)


if __name__ == '__main__':
    unittest.main()

```


## FILE: tools/test_validate_native_proof.py

SHA256: a2b51951efa8b17a27486720e7ec25362b78b1dc4f2f6b1407073423ecda1b29 | Bytes: 10205 | Git mode: 100644

```
"""Isolated terminal-proof contract tests; no mutable audit archive or VM."""
import importlib.util
import json
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("release_validator", Path(__file__).with_name("validate_release_bundle.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def write(path, value):
    path.write_text(json.dumps(value), encoding="utf-8")


def fixture(root, laptop=True, *, index=1, config_bytes=None, expected=None, source_bytes=None, artifacts=None):
    run = root / f"e2e-proof{index}-synthetic"
    run.mkdir()
    config_path = root / "config.json"
    config = {key: {"InstanceName": name} for key, name in (("Primary", "devfleet-primary"), ("Failover", "devfleet-failover"), ("Vault", "devfleet-vault"))}
    if config_bytes is None:
        write(config_path, config)
    else:
        config_path.write_bytes(config_bytes)
        config = json.loads(config_bytes.decode("utf-8-sig"))
    sources = {}
    for key in ("proofScriptSha256", "invokeRealProductPhaseSha256", "invokeWpfUiAutomationSha256", "wpfLaunchContractSha256"):
        sources[key] = root / key
        sources[key].write_bytes(source_bytes[key] if source_bytes else key.encode())
    expected = expected or {"repositoryHead": "a" * 40, "candidateCommit": "a" * 40, "shippingInputIdentity": "c" * 64, "releaseFingerprint": "d" * 64, "toolingFingerprint": "e" * 64}
    artifacts = artifacts or {"exe": "a" * 64, "tar": "b" * 64, "portable": "c" * 64, "installerSource": "d" * 64}
    tx, lineage, payload = f"{index:032x}", f"{index + 100:032x}", artifacts["tar"]
    role, phase = ("Laptop / Surrogate", "SURROGATE-DISPOSABLE") if laptop else ("Primary / Desktop", "REBOOT-RESUME")
    targets = [{"instanceName": config["Failover"]["InstanceName"], "nodeRole": "surrogate"}, {"instanceName": config["Vault"]["InstanceName"], "nodeRole": "vault"}] if laptop else [{"instanceName": config["Primary"]["InstanceName"], "nodeRole": "primary"}]
    markers = [dict(target, marker={"transactionId": tx, "payloadSha256": payload, "nodeRole": target["nodeRole"], "component": "bootstrap", "state": "COMPLETED"}) for target in targets]
    role_evidence = {"configSha256": validator.sha(config_path), "requiredTargets": targets, "markers": markers}
    authority = {"status": "REAL E2E PASS", "contract": "product-lifecycle-completion-authority", "completionVerified": True, "authenticatedHealth": True, "transactionId": tx, "invocationId": lineage, "role": role, "payloadSha256": payload, "guest": {"completionVerified": True, "transactionId": tx, "role": role, "roleEvidence": role_evidence}}
    generation = {"generation": 1, "invocationId": lineage, "reboot": {"bootIdentityChanged": True, "checkpoint": {"transactionId": tx, "payloadSha256": payload, "role": role, "action": "FreshInstall"}}, "resume": {"status": "REAL E2E OBSERVER HANDOFF"}}
    write(run / "product-lifecycle-completion-authority.json", authority)
    write(run / "product-lifecycle-generation-1.json", generation)
    evidence = [{"file": name, "sha256": validator.sha(run / name)} for name in ("product-lifecycle-completion-authority.json", "product-lifecycle-generation-1.json")]
    provenance = dict(expected, **{key: validator.sha(path) for key, path in sources.items()}, diagnosticOnly=False, certificationEligible=True, role=role, phaseId=phase, cleanCheckpointId="19865b76-4c3a-44f7-ba39-841e9d3c40c9")
    candidate = {"tar": {"sha256": payload}, "repositoryHead": expected["repositoryHead"], "gitCommit": expected["candidateCommit"], "shippingInputIdentity": expected["shippingInputIdentity"], "releaseFingerprintId": expected["releaseFingerprint"], "toolingFingerprintId": expected["toolingFingerprint"]}
    candidate.update({field: {"sha256": artifacts[name]} for name, field in (("exe", "candidate"), ("portable", "portable"), ("installerSource", "installerSource"))})
    start = {"runId": run.name, "provenance": provenance, "candidate": candidate}
    write(run / "proof-start.json", start)
    binding = {"role": role, "phaseId": phase, "transactionId": tx, "checkpointLineageId": lineage, "payloadSha256": payload, "roleEvidence": role_evidence, "evidence": evidence}
    final = {"status": "PASS", "outcome": "PASS", "runId": run.name, "role": role, "candidate": candidate, "provenance": provenance, "proofStartSha256": validator.sha(run / "proof-start.json"), "diagnosticOnly": False, "certificationEligible": True, "transactionId": tx, "checkpointLineageId": lineage, "proofBinding": binding}
    write(run / "proof-final.json", final)
    return run, config_path, sources, expected, artifacts, start, final, authority, generation


@pytest.mark.parametrize("laptop", [False, True])
def test_native_nested_start_and_terminal_identity_are_accepted(tmp_path, laptop):
    run, config, sources, expected, artifacts, *_ = fixture(tmp_path, laptop)
    tx, lineage, role = validator.validate_native_proof(run, config, sources, expected, artifacts)
    assert tx != lineage
    assert role == ("Laptop / Surrogate" if laptop else "Primary / Desktop")


def test_adopted_clean_proof_requires_exact_receipt_and_checkpoint(tmp_path):
    run, config, sources, expected, artifacts, start, final, *_ = fixture(tmp_path)
    baseline = {"id": "11111111-2222-4333-8444-555555555555",
                "name": "DevFleet-E2E-CLEAN-R2", "receiptSha256": "f" * 64}
    start["provenance"].update(cleanCheckpointId=baseline["id"],
                               cleanCheckpointName=baseline["name"],
                               baselineReceiptSha256=baseline["receiptSha256"])
    final["cleanCheckpoint"] = {"id": baseline["id"], "name": baseline["name"]}
    write(run / "proof-start.json", start)
    final["proofStartSha256"] = validator.sha(run / "proof-start.json")
    write(run / "proof-final.json", final)
    validator.validate_native_proof(run, config, sources, expected, artifacts, baseline)
    baseline["receiptSha256"] = "0" * 64
    with pytest.raises(ValueError):
        validator.validate_native_proof(run, config, sources, expected, artifacts, baseline)


@pytest.mark.parametrize("field", [None, "run", "transaction", "lineage", "role"])
def test_two_role_proofs_require_independent_native_identities(field):
    runs, transactions, lineages, roles = ["run1", "run2"], ["1" * 32, "2" * 32], ["3" * 32, "4" * 32], ["Primary / Desktop", "Laptop / Surrogate"]
    if field is None:
        validator.validate_proof_independence(runs, transactions, lineages, roles)
    else:
        selected = {"run": runs, "transaction": transactions, "lineage": lineages, "role": roles}[field]
        selected[1] = selected[0]
        with pytest.raises(ValueError):
            validator.validate_proof_independence(runs, transactions, lineages, roles)


@pytest.mark.parametrize("case", ["run_id", "status_outcome", "diagnostic", "ineligible", "source_missing", "source_drift", "start_hash", "tuple", "terminal_tuple", "artifact", "candidate_tuple", "tx", "lineage", "role", "phase", "clean", "payload", "duplicate_file", "traversal", "file_hash", "config_hash", "missing_vault", "unfinished_vault", "foreign_marker", "changed_boot", "foreign_checkpoint", "resume_missing", "no_reboot"])
def test_invalid_native_proof_is_rejected(tmp_path, case):
    run, config, sources, expected, artifacts, start, final, authority, generation = fixture(tmp_path)
    binding = final["proofBinding"]
    if case == "run_id": final["runId"] = "different"
    elif case == "status_outcome": final["outcome"] = "NOT_OBSERVED"
    elif case == "diagnostic": final["diagnosticOnly"] = True
    elif case == "ineligible": final["certificationEligible"] = False
    elif case == "source_missing": del start["provenance"]["wpfLaunchContractSha256"]
    elif case == "source_drift": sources["proofScriptSha256"].write_text("changed")
    elif case == "start_hash": final["proofStartSha256"] = "0" * 64
    elif case == "tuple": start["provenance"]["candidateCommit"] = "0" * 40
    elif case == "terminal_tuple": final["provenance"] = dict(final["provenance"], repositoryHead="0" * 40)
    elif case == "artifact": final["candidate"]["candidate"]["sha256"] = "0" * 64
    elif case == "candidate_tuple": final["candidate"]["toolingFingerprintId"] = "0" * 64
    elif case == "tx": final["transactionId"] = "3" * 32
    elif case == "lineage": binding["checkpointLineageId"] = ""
    elif case == "role": final["role"] = "Primary / Desktop"
    elif case == "phase": binding["phaseId"] = "REBOOT-RESUME"
    elif case == "clean": start["provenance"]["cleanCheckpointId"] = "other"
    elif case == "payload": binding["payloadSha256"] = "0" * 64
    elif case == "duplicate_file": binding["evidence"].append(binding["evidence"][0])
    elif case == "traversal": binding["evidence"][1]["file"] = "../outside"
    elif case == "file_hash": binding["evidence"][1]["sha256"] = "0" * 64
    elif case == "config_hash": binding["roleEvidence"]["configSha256"] = "0" * 64
    elif case == "missing_vault": binding["roleEvidence"]["markers"].pop()
    elif case == "unfinished_vault": binding["roleEvidence"]["markers"][1]["marker"]["state"] = "STARTED"
    elif case == "foreign_marker": binding["roleEvidence"]["markers"][1]["marker"]["transactionId"] = "3" * 32
    elif case == "changed_boot": generation["reboot"]["bootIdentityChanged"] = False
    elif case == "foreign_checkpoint": generation["reboot"]["checkpoint"]["transactionId"] = "3" * 32
    elif case == "resume_missing": generation["resume"]["status"] = "PASS"
    elif case == "no_reboot": binding["evidence"].pop()
    write(run / "proof-start.json", start)
    if case != "start_hash": final["proofStartSha256"] = validator.sha(run / "proof-start.json")
    write(run / "product-lifecycle-completion-authority.json", authority)
    write(run / "product-lifecycle-generation-1.json", generation)
    if case not in {"file_hash", "traversal"}:
        for record in binding["evidence"]: record["sha256"] = validator.sha(run / record["file"])
    write(run / "proof-final.json", final)
    with pytest.raises(ValueError):
        validator.validate_native_proof(run, config, sources, expected, artifacts)

```


## FILE: tools/test_validate_release_bundle.py

SHA256: 7b51a6dc41a6487f4174f38a71155db86c04790e6475cf97e2447608f9acfd23 | Bytes: 40192 | Git mode: 100644

```
"""Behavioral negative tests for the release-tooling bundle gate."""
from __future__ import annotations

import copy
import hashlib
import json
import tempfile
import zipfile
from pathlib import Path

from validate_release_bundle import REQUIRED_FULLRELEASE_PHASES, _validate_nested_l2_terminal, validate, validate_historical_proof_sources
from test_validate_native_proof import fixture as native_proof_fixture

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "outputs" / "DevFleet-v1.2.13-AI-Audit-LATEST.zip"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(entries: dict[str, bytes], name: str) -> dict:
    return json.loads(entries[name].decode("utf-8-sig"))


def put(entries: dict[str, bytes], name: str, value: object) -> None:
    entries[name] = (json.dumps(value, indent=2) + "\n").encode()


def canonical_shipping_rows(rows: list[dict]) -> list[dict]:
    return sorted(rows, key=lambda row: (0 if row["root"] == "source" else 1, tuple(part.casefold() for part in row["path"].split("/"))))


def shipping_identity(rows: list[dict], mode: dict, version: str, installer: str) -> str:
    payload = {"schemaVersion": 1, "devfleetVersion": version, "installerVersion": installer, "shippingModeContract": mode, "shippingInputs": canonical_shipping_rows(rows)}
    return digest(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode())


def release_identity(release: dict) -> str:
    payload = {key: release.get(key) for key in ("schemaVersion", "devfleetVersion", "installerVersion", "shippingModeContract")}
    payload["shippingInputs"] = release.get("shippingInputs")
    payload["artifacts"] = release.get("artifacts", [])
    return digest(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode())


def final_entries() -> dict[str, bytes]:
    with zipfile.ZipFile(ARCHIVE) as archive:
        entries = {name: archive.read(name) for name in archive.namelist() if not name.endswith("/")}
    state = read_json(entries, "finalization-state.json")
    candidate = str(state["candidate_git_commit"])
    head = str(state["repository_head"])
    manifest = read_json(entries, "AUDIT-MANIFEST.json")
    shipping_rows = []
    for row in manifest["sourceInventory"]:
        path = str(row["path"]).replace("\\", "/")
        if path.startswith("source/"):
            root_name, relative = "source", path[len("source/"):]
        elif path.startswith("installer-source/"):
            root_name, relative = "installer-source", path[len("installer-source/"):]
        else:
            continue
        shipping_rows.append({"root": root_name, "path": relative, "bytes": int(row["bytes"]), "sha256": str(row["sha256"]).lower(), "mode": str(row["mode"])})
    mode = manifest["shippingModeContract"]
    shipping_rows = canonical_shipping_rows(shipping_rows)
    shipping = shipping_identity(shipping_rows, mode, str(manifest["devfleetVersion"]), str(manifest["installerVersion"]))
    release_record = read_json(entries, "outputs/release-fingerprint.json")
    release_record.update({"devfleetVersion": manifest["devfleetVersion"], "installerVersion": manifest["installerVersion"], "shippingModeContract": mode, "shippingInputs": shipping_rows})
    release = release_identity(release_record)
    release_record["releaseFingerprintId"] = release
    put(entries, "outputs/release-fingerprint.json", release_record)
    tooling_record = read_json(entries, "outputs/tooling-fingerprint-current.json")
    tooling_record.update({"repositoryHead": head, "gitCommit": head, "candidateGitCommit": head, "shippingInputIdentity": shipping, "candidateShippingInputIdentity": shipping, "releaseFingerprintId": release})
    put(entries, "outputs/tooling-fingerprint-current.json", tooling_record)
    tooling = str(state["toolingFingerprintId"])
    run_id = "FullRelease-synthetic-current"
    state["repository_head"] = head
    state["candidate_git_commit"] = head
    state["candidate_shipping_input_identity"] = shipping
    state["shipping_input_identity"] = shipping
    state["releaseFingerprintId"] = release
    state.update({"source_changed_since_candidate": False, "rebuild_required": False, "source_identity_matches_candidate": True, "artifact_tuple_matches_candidate": True, "candidate_build_current": True, "candidate_is_current": True, "validation_evidence_current": True, "full_release_passed": True, "internal_promotion_allowed": True, "public_promotion_allowed": False, "full_release_run_id": run_id, "full_release_current": True})
    state.update({"status": "PASS", "release_status": "PASS", "blocker": None})
    candidate_record = read_json(entries, "CURRENT-CANDIDATE.json")
    candidate_record.pop("historicalProvenance", None)
    candidate_record.update({"repositoryHead": head, "gitCommit": head, "candidateCommit": head, "candidateShippingInputs": shipping_rows, "candidateShippingModeContract": mode, "shippingModeContract": mode, "shippingInputIdentity": shipping, "candidateShippingInputIdentity": shipping, "releaseFingerprintId": release, "candidateIsCurrent": True, "sourceChangedSinceCandidate": False, "rebuildRequired": False})
    candidate_record["candidateTuple"] = {"candidateCommit": head, "shippingInputIdentity": shipping, "releaseFingerprintId": release, "toolingFingerprintId": tooling}
    manifest.pop("historicalProvenance", None)
    manifest.update({"repositoryHead": head, "gitCommit": head, "candidateGitCommit": head, "shippingInputIdentity": shipping, "candidateShippingInputIdentity": shipping, "releaseFingerprintId": release, "candidate": candidate_record, "candidateIsCurrent": True, "sourceChangedSinceCandidate": False, "rebuildRequired": False})
    put(entries, "CURRENT-CANDIDATE.json", candidate_record)
    put(entries, "AUDIT-MANIFEST.json", manifest)
    artifact_manifest = read_json(entries, "outputs/final-artifact-hashes.json")
    artifact_manifest.update({"repositoryHead": head, "gitCommit": head, "candidateGitCommit": head, "shippingInputIdentity": shipping, "releaseFingerprintId": release, "sourceChangedSinceCandidate": False, "rebuildRequired": False, "sourceIdentityMatchesCandidate": True, "candidateBuildCurrent": True, "candidateIsCurrent": True, "validationEvidenceCurrent": True, "fullReleasePassed": True, "internalPromotionAllowed": True, "publicPromotionAllowed": False})
    put(entries, "outputs/final-artifact-hashes.json", artifact_manifest)
    tuple_value = {"repositoryHead": head, "candidateCommit": candidate, "shippingInputIdentity": shipping, "releaseFingerprintId": release, "toolingFingerprintId": tooling}
    tuple_value["candidateCommit"] = head

    # The archive contains several current-authority documents whose nested
    # ``candidate`` records predate this synthetic current-candidate fixture.
    # Rebind those records together, so the release-tooling validator sees one
    # coherent tuple while preserving any separately marked historical data.
    def rebind_current_authority(value: object) -> None:
        if isinstance(value, dict):
            for key in ("repositoryHead", "repository_head", "gitCommit", "git_commit", "candidateGitCommit", "candidate_git_commit", "candidateCommit", "candidate_commit"):
                if key in value:
                    value[key] = head
            for key in ("shippingInputIdentity", "shipping_input_identity", "candidateShippingInputIdentity", "candidate_shipping_input_identity"):
                if key in value:
                    value[key] = shipping
            for key in ("releaseFingerprintId",):
                if key in value:
                    value[key] = release
            for key in ("toolingFingerprintId",):
                if key in value:
                    value[key] = tooling
            for key in ("candidateIsCurrent", "candidate_is_current", "sourceIdentityMatchesCandidate", "source_identity_matches_candidate", "candidateBuildCurrent", "candidate_build_current", "validationEvidenceCurrent", "validation_evidence_current", "fullReleasePassed", "full_release_passed", "internalPromotionAllowed", "internal_promotion_allowed"):
                if key in value:
                    value[key] = True
            for key in ("sourceChangedSinceCandidate", "source_changed_since_candidate", "rebuildRequired", "rebuild_required", "publicPromotionAllowed", "public_promotion_allowed"):
                if key in value:
                    value[key] = False
            for child in value.values():
                rebind_current_authority(child)
        elif isinstance(value, list):
            for child in value:
                rebind_current_authority(child)

    # The shipping coherence gate inspects every top-level audit JSON record.
    # This isolated final-state fixture must project those mutable handoffs to
    # its synthetic tuple as well; nested historical originals are untouched.
    authority_names = {"evidence/CURRENT-STATUS.json", "evidence/CURRENT-GATES.json", "evidence/CURRENT-PROOF.json", "evidence/FULLRELEASE-SUMMARY.json", "evidence/CURRENT-HANDOFF.json", "evidence/CURRENT-RELEASE-AUTHORITY.json"}
    authority_names.update(name for name in entries if name.startswith("audit/") and name.count("/") == 1 and name.endswith(".json"))
    for authority_name in sorted(authority_names):
        authority = read_json(entries, authority_name)
        rebind_current_authority(authority)
        put(entries, authority_name, authority)

    # A release-good fixture must never smuggle the historical candidate
    # provenance that is tested separately in diagnostic mode.
    assert "historicalProvenance" not in candidate_record
    assert "historicalProvenance" not in manifest
    # Current authority evidence must bind the same synthetic current tuple;
    # preserved historical records, if any, remain untouched in their own
    # historical namespaces.
    handoff = read_json(entries, "audit/CURRENT-HANDOFF.json")
    handoff.update({"repositoryHead": head, "candidateCommit": head, "shippingInputIdentity": shipping, "candidateShippingInputIdentity": shipping, "releaseFingerprintId": release, "toolingFingerprintId": tooling, "candidateIsCurrent": True, "sourceChangedSinceCandidate": False, "rebuildRequired": False})
    put(entries, "audit/CURRENT-HANDOFF.json", handoff)
    put(entries, "finalization-state.json", state)
    current = read_json(entries, "evidence/CURRENT-PROOF.json")
    current.update({"status": "PASS", "outcome": "PASS", "fullReleaseRunId": run_id, **tuple_value})
    put(entries, "evidence/CURRENT-PROOF.json", current)
    summary = read_json(entries, "evidence/FULLRELEASE-SUMMARY.json")
    summary.update({"status": "PASS", "diagnosticOnly": False, "historicalEvidenceOnly": False, "latestRunId": run_id, "candidateTuple": tuple_value})
    put(entries, "evidence/FULLRELEASE-SUMMARY.json", summary)
    l1_terminal = {"name": "DevFleet-E2E-Win11-01", "id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "state": "Off", "timestamp": "2026-08-30T00:00:02Z", "timestampUtc": "2026-08-30T00:00:02Z", "runId": run_id, "ownershipScope": "exact disposable"}
    put(entries, "evidence/l1-terminal-state.json", l1_terminal)
    nested_observation = {"schemaVersion": 1, "runId": run_id, "status": "ABSENT", "expectedName": "DevFleet-E2E-Linux-01", "present": False, "observedUtc": "2026-08-30T00:00:01Z", "verification": "Bounded Multipass JSON inventory inside exact L1", "exactMatchCount": 0, "inventoryCount": 0, "backendInventories": [], "candidate": tuple_value, "l1": {"name": "DevFleet-E2E-Win11-01", "id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2"}, "nestedScope": "inside the exact L1 guest session", "observer": "Get-DevFleetNestedL2State", "evidenceClass": "FullRelease run-bound nested observation"}
    put(entries, "evidence/current-fullrelease/nested-l2-terminal-observation.json", nested_observation)
    nested_hash = digest(entries["evidence/current-fullrelease/nested-l2-terminal-observation.json"])
    l2_terminal = {"schemaVersion": 2, "expectedName": "DevFleet-E2E-Linux-01", "status": "ABSENT", "present": False, "timestamp": "2026-08-30T00:00:01Z", "timestampUtc": "2026-08-30T00:00:01Z", "verificationMethod": nested_observation["verification"], "ownershipScope": "exact expected nested L2 name inside exact disposable L1", "nestedScope": nested_observation["nestedScope"], "backendInventories": [], "runId": run_id, "sourceRunId": run_id, "sourceEvidence": "nested-l2-terminal-observation.json", "sourceEvidenceSha256": nested_hash, "l1Name": "DevFleet-E2E-Win11-01", "l1Id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "candidate": tuple_value, "evidenceClass": nested_observation["evidenceClass"], "certifiedReleaseCleanup": False}
    put(entries, "evidence/l2-terminal-state.json", l2_terminal)
    cleanup = {"status": "PASS", "runId": run_id, "candidate": tuple_value, "l1": {"name": "DevFleet-E2E-Win11-01", "id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "state": "Off", "deleted": False}, "guest": {"runRootAbsent": True, "nestedAbsent": True, "foreignResourcesMutated": False}, "productionTouched": False, "physicalSurfaceTouched": False}
    put(entries, "evidence/current-fullrelease/final-cleanup.json", cleanup)
    cleanup_hash = digest(entries["evidence/current-fullrelease/final-cleanup.json"])
    l1_hash = digest(entries["evidence/l1-terminal-state.json"])
    l2_hash = digest(entries["evidence/l2-terminal-state.json"])
    entries["evidence/current-fullrelease/l1-terminal-state.json"] = entries["evidence/l1-terminal-state.json"]
    entries["evidence/current-fullrelease/l2-terminal-state.json"] = entries["evidence/l2-terminal-state.json"]
    l1_hash = digest(entries["evidence/current-fullrelease/l1-terminal-state.json"])
    l2_hash = digest(entries["evidence/current-fullrelease/l2-terminal-state.json"])
    put(entries, "evidence/current-fullrelease/post-cleanup-finalization.json", {"schemaVersion": 3, "status": "PASS", "runId": run_id, "cleanupConsumed": True, "reconcileAfterCleanup": True, "cleanupEvidenceHash": cleanup_hash, "terminalL1Hash": l1_hash, "terminalL2Hash": l2_hash, "nestedL2Observation": "nested-l2-terminal-observation.json", "nestedL2ObservationSha256": nested_hash, "terminalL1Timestamp": "2026-08-30T00:00:02Z", "terminalL2Timestamp": "2026-08-30T00:00:01Z", "expectedL2Name": "DevFleet-E2E-Linux-01", "candidate": tuple_value, "liveChecks": {"l1ExactOff": True, "l2ExactAbsent": True, "hostSameNameL2Absent": True, "foreignResourcesMutated": False}})
    full_hashes = {**tuple_value, **{row["name"]: row["sha256"] for row in release_record["artifacts"]}}
    put(entries, "evidence/current-fullrelease/run-state.json", {"runId": run_id, "mode": "FullRelease", "finalStatus": "PASS", "candidateHashes": full_hashes, "completedPhases": sorted(REQUIRED_FULLRELEASE_PHASES)})
    real_binding_name = "evidence/current-fullrelease/real-use-acceptance-binding.json"
    real_prepare_name = "evidence/current-fullrelease/real-use-acceptance-prepare.json"
    put(entries, real_binding_name, {"schemaVersion": 1, "contract": "devfleet-real-use-acceptance-v1", "runId": run_id, "phaseId": "REAL-USE-ACCEPTANCE", "precedingPhase": "SURROGATE-DISPOSABLE", "candidate": tuple_value})
    put(entries, real_prepare_name, {"schemaVersion": 1, "contract": "devfleet-real-use-acceptance-v1", "status": "PREPARED", "stage": "prepare", "phaseId": "REAL-USE-ACCEPTANCE", "runId": run_id, "candidate": tuple_value})
    real_binding_hash = digest(entries[real_binding_name])
    real_prepare_hash = digest(entries[real_prepare_name])
    real_report = {"schemaVersion": 1, "contract": "devfleet-real-use-acceptance-v1", "status": "PASS", "stage": "resume", "phaseId": "REAL-USE-ACCEPTANCE", "runId": run_id, "candidate": tuple_value, "journeys": [{"id": name, "status": "PASS", "assertions": {"real": True, "endToEnd": True}} for name in ("U01", "U02", "U03", "U04", "U05")], "cleanup": {"status": "PASS", "ownedOnly": True, "errors": []}, "failure": None, "cleanupFailure": None}
    put(entries, "evidence/current-fullrelease/real-use-acceptance-report.json", real_report)
    real_hash = digest(entries["evidence/current-fullrelease/real-use-acceptance-report.json"])
    put(entries, "evidence/current-fullrelease/real-use-acceptance-evidence.json", {"contract": "devfleet-real-use-acceptance-evidence-v1", "status": "PASS", "runId": run_id, "credentialsStoredInEvidence": False, "internalPromotionAllowed": False, "journeys": [{"id": name, "status": "PASS"} for name in ("U01", "U02", "U03", "U04", "U05")], "evidence": {"binding": {"sha256": real_binding_hash}, "prepare": {"sha256": real_prepare_hash}, "report": {"sha256": real_hash}}})
    records = [{"id": phase, "status": "PASS", "runId": run_id} for phase in sorted(REQUIRED_FULLRELEASE_PHASES)]
    for record in records:
        if record["id"] == "HOST-SAFETY":
            record["evidence"] = {"startSafe": True, "rawHostSafetyStartSafe": True, "effectiveE2EStartAuthorized": True, "ramPressureOverrideAuthorized": False}
        elif record["id"] == "REAL-USE-ACCEPTANCE":
            record["evidence"] = {"executor": {"status": "REAL E2E PASS", "phase": "REAL-USE-ACCEPTANCE", "contract": "devfleet-real-use-acceptance-phase-v1", "candidate": tuple_value, "credentialsStoredInEvidence": False, "internalPromotionAllowed": False, "evidence": {"bindingPath": "C:/fixture/real-use-acceptance-binding.json", "bindingSha256": real_binding_hash, "preparePath": "C:/fixture/real-use-acceptance-prepare.json", "prepareSha256": real_prepare_hash, "reportPath": "C:/fixture/real-use-acceptance-report.json", "reportSha256": real_hash}}}
        elif record["id"] == "RECONCILE":
            record["evidence"] = {"executor": {"status": "REAL E2E PASS", "phase": "RECONCILE", "maintenance": "5/5", "candidate": tuple_value}}
    put(entries, "evidence/current-fullrelease/fullrelease-phase-records.json", records)
    entries["evidence/current-proof/product-lifecycle-progress.jsonl"] = b'{"heartbeat":true}\n'
    source_files = {"proofScriptSha256": "run-exact-candidate-proof.ps1", "invokeRealProductPhaseSha256": "Invoke-RealProductPhase.psm1", "invokeWpfUiAutomationSha256": "Invoke-WpfUiAutomation.ps1", "wpfLaunchContractSha256": "WpfLaunchContract.psm1"}
    source_bytes = {key: entries[f"release-tooling/proof-entrypoints/{name}"] for key, name in source_files.items()}
    proof_tuple = {"repositoryHead": head, "candidateCommit": head, "shippingInputIdentity": shipping, "releaseFingerprint": release, "toolingFingerprint": tooling}
    artifact_hashes = {entry["name"]: entry["sha256"] for entry in read_json(entries, "outputs/release-fingerprint.json")["artifacts"]}
    # Replace only this temporary fixture's proof namespace; the archive and
    # its historical evidence remain immutable on disk.
    for name in list(entries):
        if name.startswith("evidence/proof-runs/"):
            del entries[name]
    proof_ids = []
    for index in (1, 2):
        with tempfile.TemporaryDirectory() as directory:
            run, *_ = native_proof_fixture(Path(directory), laptop=(index == 2), index=index, config_bytes=entries["source/config/devfleet.config.json"], expected=proof_tuple, source_bytes=source_bytes, artifacts=artifact_hashes)
            proof_ids.append(run.name)
            for path in run.iterdir():
                entries[f"evidence/proof-runs/{run.name}/{path.name}"] = path.read_bytes()

    authority = read_json(entries, "evidence/CURRENT-RELEASE-AUTHORITY.json")
    authority["proofs"] = {"passing": 2, "required": 2, "status": "2 / 2 PASS", "runs": [{"runId": run_id_value, "status": "PASS"} for run_id_value in proof_ids]}
    put(entries, "evidence/CURRENT-RELEASE-AUTHORITY.json", authority)

    standard_id = "standard-token-synthetic-current"
    raw_name = f"evidence/standard-token/{standard_id}/installer-self-test-raw.txt"
    canonical_name = f"evidence/standard-token/{standard_id}/standard-token-evidence.json"
    entries[raw_name] = f"PASS\npayload={artifact_hashes['tar']}\n".encode()
    standard = {"schemaVersion": 1, "runId": standard_id, "status": "PASS", "standardNonAdministratorToken": True, "runDirectory": f"evidence/standard-token/{standard_id}", "rawReportPath": raw_name, "canonicalEvidencePath": canonical_name, "generatedAtUtc": "2026-09-16T00:00:00Z", "candidateBuildCommit": head, **tuple_value, "exe": next(row for row in release_record["artifacts"] if row["name"] == "exe"), "tar": next(row for row in release_record["artifacts"] if row["name"] == "tar"), "runner": {"path": "automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1", "sha256": digest(entries["automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1"])}, "token": {"standardNonAdministratorToken": True, "isAdministratorMember": False, "isAdministratorEnabled": False, "isElevated": False, "integrityLevel": "Medium"}, "exitCode": 0, "reportSha256": digest(entries[raw_name]), "requiredChecks": {name: True for name in ("pass", "payloadExtraction", "bootstrapEntrypoint", "parameterContract", "embeddedTarCount", "factoryResetBackupGate", "planSafety", "devfleetVersion", "installerVersion", "payloadSha")}, "residualSelfTestScratchCount": 0}
    put(entries, canonical_name, standard)
    entries["evidence/CURRENT-STANDARD-TOKEN.json"] = entries[canonica