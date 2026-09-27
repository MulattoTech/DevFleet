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
