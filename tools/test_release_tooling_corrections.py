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
