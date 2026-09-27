# DevFleet source part 123

Full-source UTF-8 byte interval [5673000, 5719500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 7d355f51221a7fa17d2d1d6826d6d27b5c17bb82b5cb75a0299ad01cd34ecca1

<!-- BEGIN SOURCE SLICE -->
elf.approval), copy.deepcopy(self.auth), copy.deepcopy(TUPLE)
                if kind == 'unapproved': approval['decision'] = 'PENDING'
                if kind == 'approval_id': approval['replacementId'] = OLD
                if kind == 'inventory_missing': auth['nestedL2']['backendInventories'].pop()
                if kind == 'inventory_present': auth['nestedL2']['backendInventories'][0]['names'] = ['DevFleet-E2E-Linux-01']
                if kind == 'expired': auth['guest']['passwordExpiresUtc'] = (datetime.now(timezone.utc)-timedelta(days=1)).isoformat()
                if kind == 'unknown_expiry': auth['guest']['passwordExpiresUtc'] = None
                if kind == 'tuple': candidate['toolingFingerprintId'] = '9' * 64
                if kind == 'guest_identity': auth['guest']['principal'] = 'OTHER\\E2EAdmin'
                with self.assertRaises(ValueError): self.invoke(approval=approval, auth=auth, candidate=candidate)
                self.assertEqual(accepted_baseline(self.root)['id'], OLD)

    def test_replay_and_interrupted_receipt_keep_prior_pointer(self):
        self.invoke()
        with self.assertRaises(ValueError): self.invoke()
        self.assertEqual(accepted_baseline(self.root, TUPLE)['id'], NEW)
        second = tempfile.TemporaryDirectory()
        self.addCleanup(second.cleanup)
        other = Path(second.name)
        # The same fixture evidence remains external to the transaction state.
        other_predecessor = other / 'audit/agent-memory/attempts/DF-FRESH-CERTIFICATION-20260926-R2/readiness-predecessor.json'
        other_predecessor.parent.mkdir(parents=True, exist_ok=True)
        other_predecessor.write_bytes(Path(self.proposal['predecessorEvidence']['path']).read_bytes())
        other_proposal = copy.deepcopy(self.proposal)
        other_proposal['predecessorEvidence']['path'] = str(other_predecessor)
        other_proposal_path = other / 'proposal.json'
        other_proposal_path.write_text(json.dumps(other_proposal), encoding='utf-8')
        with self.assertRaises(RuntimeError):
            adopt(other, other_proposal_path, self.root/'approval.json',
                  self.root/'auth.json', self.root/'live.json', self.root/'candidate.json',
                  self.root/'ledger.json',
                  fault='after_receipt')
        self.assertEqual(accepted_baseline(other)['id'], OLD)
        with self.assertRaises(ValueError):
            adopt(other, other_proposal_path, self.root/'approval.json',
                  self.root/'auth.json', self.root/'live.json', self.root/'candidate.json',
                  self.root/'ledger.json')
        self.assertEqual(accepted_baseline(other)['id'], OLD)

    def test_unreserved_or_active_auth_evidence_rejected(self):
        for kind in ('missing', 'active', 'wrong_class', 'unbound_evidence'):
            with self.subTest(kind=kind):
                ledger = copy.deepcopy(self.ledger)
                if kind == 'missing': ledger['attempts'] = []
                if kind == 'active': ledger['attempts'][0]['state'] = 'ACTIVE'
                if kind == 'wrong_class': ledger['attempts'][0]['operation'] = 'laptop-proof'
                if kind == 'unbound_evidence': ledger['attempts'][0]['evidence'] = []
                with self.assertRaises(ValueError): self.invoke(ledger=ledger)
                self.assertEqual(accepted_baseline(self.root)['id'], OLD)


if __name__ == '__main__': unittest.main()

```


## FILE: tools/test_baseline_temporal_binding.py

SHA256: 525c83dc2f0787a4c94a8d126f62c50ce383448c2c81e57be2c3e902923e8cab | Bytes: 3083 | Git mode: 100644

```
"""Reject stale, future or wrong-reservation adoption evidence without VM access."""
import copy
from datetime import datetime, timedelta, timezone
import unittest
import test_baseline_lineage as fixtures


class BaselineTemporalBindingTests(unittest.TestCase):
    def setUp(self):
        self.case = fixtures.BaselineLineageTests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)

    def reject(self, **kwargs):
        with self.assertRaises(ValueError):
            self.case.invoke(**kwargs)
        self.assertFalse((self.case.root / 'evidence/baselines/CURRENT.json').exists())

    def test_matching_terminal_native_provenance_is_accepted(self):
        result = self.case.invoke()
        self.assertFalse(result['certificationCredit'])

    def test_failed_diagnostic_cannot_supply_successful_adoption(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['exitCode'] = 2
        self.reject(ledger=ledger)

    def test_missing_diagnostic_exit_code_is_not_success(self):
        ledger = copy.deepcopy(self.case.ledger)
        del ledger['attempts'][0]['exitCode']
        self.reject(ledger=ledger)

    def test_diagnostic_reserved_for_old_tooling_is_rejected(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['tuple']['toolingFingerprintId'] = '9' * 64
        self.reject(ledger=ledger)

    def test_collector_wrong_vm_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['vm']['id'] = fixtures.NEW
        self.reject(auth=auth)

    def test_collector_wrong_candidate_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['candidate']['candidateSha256'] = '9' * 64
        self.reject(auth=auth)

    def test_collection_before_reservation_is_rejected(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['reservedUtc'] = self.case.auth['observedUtc']
        self.reject(ledger=ledger)

    def test_collection_past_owner_deadline_is_rejected(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['deadlineUtc'] = self.case.auth['startedUtc']
        self.reject(ledger=ledger)

    def test_nested_inventory_before_collection_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['nestedL2']['observedUtc'] = auth['guest']['passwordLastSetUtc']
        self.reject(auth=auth)

    def test_future_native_inventory_is_rejected(self):
        live = copy.deepcopy(self.case.live)
        live['observedUtc'] = (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()
        self.reject(live=live)

    def test_missing_collection_start_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        del auth['startedUtc']
        self.reject(auth=auth)

    def test_reversed_collection_window_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['startedUtc'] = self.case.live['observedUtc']
        self.reject(auth=auth)


if __name__ == '__main__':
    unittest.main()

```


## FILE: tools/test_compute_shipping_input_identity.py

SHA256: b9c3721b1ca80a5c911da31f18ae4493714c3b356798f9ecac0ac49573de4c50 | Bytes: 4626 | Git mode: 100644

```
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "compute_shipping_input_identity.py"


def _git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def _fixture(tmp_path: Path) -> tuple[Path, str, dict[str, Path]]:
    repo = tmp_path / "repo"
    (repo / "source" / "tools").mkdir(parents=True)
    (repo / "installer-source").mkdir()
    (repo / "tools").mkdir()
    (repo / "automation").mkdir()
    (repo / "outputs").mkdir()
    shutil.copy2(ROOT / "source" / "tools" / "release_fingerprint.py", repo / "source" / "tools" / "release_fingerprint.py")
    shutil.copy2(ROOT / "source" / "tools" / "hook_modes.py", repo / "source" / "tools" / "hook_modes.py")
    (repo / "source" / "VERSION").write_bytes(b"1.2.13\n")
    (repo / "source" / "payload.txt").write_bytes(b"alpha\nbeta\n")
    (repo / "installer-source" / "INSTALLER_VERSION").write_bytes(b"1.4.1\n")
    (repo / "installer-source" / "payload.ps1").write_bytes(b"Write-Output ok\n")
    (repo / "tools" / "release-tool.txt").write_text("one\n", encoding="utf-8")
    (repo / "automation" / "runner.txt").write_text("one\n", encoding="utf-8")
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    _git(repo, "config", "user.email", "devfleet-test@example.invalid")
    _git(repo, "config", "user.name", "DevFleet Test")
    _git(repo, "config", "core.autocrlf", "false")
    _git(repo, "add", ".")
    _git(repo, "commit", "-q", "-m", "candidate")
    commit = _git(repo, "rev-parse", "HEAD")
    artifacts = {
        "exe": repo / "outputs" / "candidate.exe",
        "tar": repo / "outputs" / "candidate.tar.gz",
        "portable": repo / "outputs" / "candidate-portable.zip",
        "installerSource": repo / "outputs" / "candidate-installer.zip",
    }
    for index, path in enumerate(artifacts.values(), 1):
        path.write_bytes((f"artifact-{index}\n").encode())
    return repo, commit, artifacts


def _run(repo: Path, commit: str, artifacts: dict[str, Path]) -> dict[str, object]:
    command = [sys.executable, str(SCRIPT), "--workspace", str(repo), "--candidate-commit", commit]
    for name, path in artifacts.items():
        command.extend(["--artifact", f"{name}={path}"])
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def test_candidate_rows_ignore_crlf_checkout_and_tooling_moves(tmp_path: Path) -> None:
    repo, commit, artifacts = _fixture(tmp_path)
    baseline = _run(repo, commit, artifacts)
    (repo / "source" / "payload.txt").write_bytes(b"alpha\r\nbeta\r\n")
    (repo / "tools" / "release-tool.txt").write_text("two\n", encoding="utf-8")
    changed = _run(repo, commit, artifacts)

    assert changed["candidateShippingInputIdentity"] == baseline["candidateShippingInputIdentity"]
    assert changed["candidateReleaseFingerprintId"] == baseline["candidateReleaseFingerprintId"]
    assert changed["liveShippingInputIdentity"] != changed["candidateShippingInputIdentity"]
    assert changed["lineEndingComparison"] == "CRLF_ONLY"
    assert changed["crlfOnlyPaths"] == ["source/payload.txt"]
    assert changed["candidateFingerprint"]["shippingInputs"] == baseline["candidateFingerprint"]["shippingInputs"]
    assert changed["liveToolingFingerprint"]["toolingFingerprintId"] != baseline["liveToolingFingerprint"]["toolingFingerprintId"]
    assert "toolingFingerprint" not in changed["candidateFingerprint"]


def test_candidate_release_fingerprint_binds_exact_artifact_tuple(tmp_path: Path) -> None:
    repo, commit, artifacts = _fixture(tmp_path)
    baseline = _run(repo, commit, artifacts)
    artifacts["exe"].write_bytes(b"changed-exe\n")
    changed = _run(repo, commit, artifacts)
    assert changed["candidateShippingInputIdentity"] == baseline["candidateShippingInputIdentity"]
    assert changed["candidateReleaseFingerprintId"] != baseline["candidateReleaseFingerprintId"]
    assert changed["candidateFingerprint"]["artifacts"] != baseline["candidateFingerprint"]["artifacts"]


def test_partial_artifact_tuple_fails_closed(tmp_path: Path) -> None:
    repo, commit, artifacts = _fixture(tmp_path)
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--workspace", str(repo), "--candidate-commit", commit, "--artifact", f"exe={artifacts['exe']}"],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "artifact tuple must be exactly" in result.stderr

```


## FILE: tools/test_failed_attempt_freeze.py

SHA256: e7e1e0c43435ce7ba04c67ba47d5e43aae7f767ac99b976388459a77731b722e | Bytes: 13077 | Git mode: 100644

```
"""Executable regression checks for the failed replacement-attempt contract."""
from __future__ import annotations

import copy
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

import pytest

import importlib.util

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("candidate_validator", ROOT / "source/tools/validate_audit_coherence.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)
AI_SPEC = importlib.util.spec_from_file_location("ai_bundle_validator", ROOT / "source/tools/validate_ai_audit_bundle.py")
AI_MODULE = importlib.util.module_from_spec(AI_SPEC)
assert AI_SPEC.loader is not None
AI_SPEC.loader.exec_module(AI_MODULE)
RELEASE_SPEC = importlib.util.spec_from_file_location("release_bundle_validator", ROOT / "tools/validate_release_bundle.py")
RELEASE_MODULE = importlib.util.module_from_spec(RELEASE_SPEC)
assert RELEASE_SPEC.loader is not None
RELEASE_SPEC.loader.exec_module(RELEASE_MODULE)


def _state() -> dict:
    snapshot = json.loads((ROOT / AI_MODULE.FAILED_ATTEMPT_SNAPSHOT).read_text(encoding="utf-8-sig"))
    attempted = json.loads((ROOT / "audit/attemptedReplacementCandidate.json").read_text(encoding="utf-8-sig"))
    artifact_rows = snapshot["candidate"]["newArtifactTuple"]["artifacts"]
    candidate = {str(row["name"]): copy.deepcopy(row) for row in artifact_rows}
    historical_artifacts = {
        name: {"bytes": expected[0], "sha256": expected[1]}
        for name, expected in MODULE.HISTORICAL_ARTIFACTS.items()
    }
    post_paths = []
    for relative in ("source/tools/validate_audit_coherence.py", "source/tools/validate_ai_audit_bundle.py"):
        post_paths.append({"path": relative, "sha256": hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()})
    return {
        "status": "BLOCKED — USER ACTION REQUIRED",
        "blocker_code": MODULE.FAILED_ATTEMPT_BLOCKER,
        "candidate_git_commit": MODULE.FAILED_ATTEMPT_COMMIT,
        "shipping_input_identity": MODULE.FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY,
        "candidate_shipping_input_identity": MODULE.FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY,
        "candidate_is_current": False,
        "source_changed_since_candidate": True,
        "rebuild_required": True,
        "artifact_tuple_matches_candidate": False,
        "full_release_passed": False,
        "internal_promotion_allowed": False,
        "public_promotion_allowed": False,
        "candidate": candidate,
        "historical_candidate": {
            "candidateCommit": MODULE.HISTORICAL_CANDIDATE,
            "shippingInputIdentity": MODULE.HISTORICAL_SHIPPING_IDENTITY,
            "releaseFingerprintId": MODULE.HISTORICAL_RELEASE_FINGERPRINT,
            "artifacts": historical_artifacts,
        },
        "failed_replacement_attempt": {
            "snapshotPath": AI_MODULE.FAILED_ATTEMPT_SNAPSHOT,
            "snapshotSha256": MODULE.FAILED_ATTEMPT_SNAPSHOT_SHA256,
            "attemptedCommit": MODULE.FAILED_ATTEMPT_COMMIT,
            "commitShippingInputIdentity": MODULE.FAILED_ATTEMPT_GIT_SHIPPING_IDENTITY,
            "buildTimeShippingInputIdentity": MODULE.FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY,
            "artifactTupleValid": True,
            "artifactTupleMatchesCandidate": False,
            "blockerCode": MODULE.FAILED_ATTEMPT_BLOCKER,
            "postFailureEvidenceTooling": {"classification": "POST_FAILURE_EVIDENCE_TOOLING", "paths": post_paths},
            "terminalEvidence": attempted["terminalEvidence"],
        },
    }


def test_failed_attempt_snapshot_is_recomputed_and_blocked():
    state = _state()
    result = MODULE._validate_failed_attempt_freeze(ROOT, state, {}, {})
    assert result["snapshotSha256"] == "ac37997945b6fa5ae9326b083ee730494b2c0c2e60d4809e7b49fc9707c0caac"
    assert result["shippingRows"] == 730
    assert result["changedRows"] == 28
    assert result["crlfOnlyRows"] == 25
    assert result["generatedShippingOutputRows"] == 3


@pytest.mark.parametrize("field,value", [
    ("candidate_is_current", True),
    ("source_changed_since_candidate", False),
    ("rebuild_required", False),
    ("artifact_tuple_matches_candidate", True),
    ("blocker_code", ""),
])
def test_failed_attempt_flags_and_blocker_fail_closed(field: str, value: object):
    state = _state()
    state[field] = value
    with pytest.raises(ValueError):
        MODULE._validate_failed_attempt_freeze(ROOT, state, {}, {})


def test_historical_tuple_remains_separate_from_attempt():
    state = _state()
    historical = state["historical_candidate"]
    assert historical["candidateCommit"] == "2739e0366d070285e44b4fc764ef9247d40b2f94"
    assert state["failed_replacement_attempt"]["attemptedCommit"] == "21752fc0e50978183322204c523b40947d073aa0"
    assert historical["releaseFingerprintId"] == "80c8b88c2f2ec828f5ab0f9713d63fa3f4cc4cbad7c382aa2f154f3196c3de84"


def test_snapshot_tamper_is_rejected(tmp_path: Path):
    source = ROOT / "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
    tampered = tmp_path / source.name
    tampered.write_bytes(source.read_bytes() + b"\n")
    state = _state()
    original = MODULE._sha256
    MODULE._sha256 = lambda path: original(tampered) if path == ROOT / "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json" else original(path)
    try:
        with pytest.raises(ValueError, match="hash-mismatched"):
            MODULE._validate_failed_attempt_freeze(ROOT, state, {}, {})
    finally:
        MODULE._sha256 = original


def _blocker_record_fixture(tmp_path: Path) -> tuple[set[str], dict]:
    records = list(AI_MODULE.FAILED_ATTEMPT_CURRENT_RECORDS)
    for relative in records:
        target = tmp_path / Path(*relative.split("/"))
        target.parent.mkdir(parents=True, exist_ok=True)
        if relative == "evidence/CURRENT-PROOF.json":
            target.write_text(json.dumps({"status": "NOT_OBSERVED", "outcome": "NOT_OBSERVED", "blockerCode": MODULE.FAILED_ATTEMPT_BLOCKER}), encoding="utf-8")
        else:
            shutil.copy2(ROOT / relative, target)
    inventory = []
    for relative in records:
        target = tmp_path / Path(*relative.split("/"))
        inventory.append({"path": relative, "bytes": target.stat().st_size, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "mode": "0644"})
    (tmp_path / "EVIDENCE-MODES.json").write_text(json.dumps([{"path": relative, "posixMode": 420, "mode": "0644", "executable": False} for relative in records]), encoding="utf-8")
    (tmp_path / "EVIDENCE-SHA256SUMS.txt").write_text("\n".join(f"{row['sha256']}  {row['path']}" for row in inventory), encoding="utf-8")
    return set(records) | {AI_MODULE.FAILED_ATTEMPT_SNAPSHOT, "EVIDENCE-MODES.json", "EVIDENCE-SHA256SUMS.txt"}, {"evidenceInventory": inventory}


def test_failed_attempt_blocker_records_are_present_and_cross_bound(tmp_path: Path):
    names, manifest = _blocker_record_fixture(tmp_path)
    AI_MODULE._validate_failed_attempt_records(tmp_path, names, manifest)


@pytest.mark.parametrize("missing", AI_MODULE.FAILED_ATTEMPT_CURRENT_RECORDS)
def test_failed_attempt_blocker_record_missing_fails_closed(tmp_path: Path, missing: str):
    names, manifest = _blocker_record_fixture(tmp_path)
    (tmp_path / Path(*missing.split("/"))).unlink()
    names.remove(missing)
    with pytest.raises(ValueError, match="missing"):
        AI_MODULE._validate_failed_attempt_records(tmp_path, names, manifest)


def test_failed_attempt_blocker_record_tamper_fails_closed(tmp_path: Path):
    names, manifest = _blocker_record_fixture(tmp_path)
    target = tmp_path / Path(*"audit/candidateBindingFailure.json".split("/"))
    target.write_text(target.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="evidenceInventory hash/mode mismatch"):
        AI_MODULE._validate_failed_attempt_records(tmp_path, names, manifest)


def test_release_bundle_failed_attempt_records_are_cross_bound(tmp_path: Path):
    names, manifest = _blocker_record_fixture(tmp_path)
    state = _state()
    (tmp_path / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (tmp_path / "CURRENT-CANDIDATE.json").write_text("{}", encoding="utf-8")
    (tmp_path / "AUDIT-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
    result = RELEASE_MODULE._validate_diagnostic(tmp_path, names | {"finalization-state.json", "CURRENT-CANDIDATE.json", "AUDIT-MANIFEST.json"})
    assert result["status"] == "PASS_WITH_BLOCKER"


@pytest.mark.parametrize("missing", ["audit/attemptedReplacementCandidate.json", "audit/candidateBindingFailure.json"])
def test_release_bundle_missing_failed_attempt_record_fails_closed(tmp_path: Path, missing: str):
    names, manifest = _blocker_record_fixture(tmp_path)
    state = _state()
    (tmp_path / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (tmp_path / "CURRENT-CANDIDATE.json").write_text("{}", encoding="utf-8")
    (tmp_path / "AUDIT-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
    names |= {"finalization-state.json", "CURRENT-CANDIDATE.json", "AUDIT-MANIFEST.json"}
    names.remove(missing)
    with pytest.raises(ValueError, match="missing"):
        RELEASE_MODULE._validate_diagnostic(tmp_path, names)


def test_ai_diagnostic_full_path_loads_manifest_before_blocker_records(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    snapshot = "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
    records = list(AI_MODULE.FAILED_ATTEMPT_CURRENT_RECORDS)
    inventory = []
    injected: dict[str, bytes] = {snapshot: (ROOT / snapshot).read_bytes()}
    for relative in records:
        data = (ROOT / relative).read_bytes()
        injected[relative] = data
        inventory.append({"path": relative, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "mode": "0644"})
    injected["EVIDENCE-MODES.json"] = json.dumps([{"path": row["path"], "posixMode": 420, "mode": "0644", "executable": False} for row in inventory]).encode()
    injected["EVIDENCE-SHA256SUMS.txt"] = "\n".join(f"{row['sha256']}  {row['path']}" for row in inventory).encode()
    observed: dict[str, object] = {}
    original_extract = AI_MODULE._extract
    def fake_extract(archive: Path, extracted: Path) -> set[str]:
        names = set(original_extract(archive, extracted))
        for relative, data in injected.items():
            target = extracted / Path(*relative.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            names.add(relative)
        manifest_path = extracted / "AUDIT-MANIFEST.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        manifest["evidenceInventory"] = inventory
        manifest_path.write_text(json.dumps(manifest) + "\n", encoding="utf-8")
        candidate_path = extracted / "CURRENT-CANDIDATE.json"
        candidate = json.loads(candidate_path.read_text(encoding="utf-8-sig"))
        # This fixture models a failed replacement, not whatever candidate
        # flags happen to be present in the latest diagnostic archive.
        candidate["candidateIsCurrent"] = False
        candidate["sourceChangedSinceCandidate"] = True
        candidate["rebuildRequired"] = True
        candidate["artifactTupleMatchesCandidate"] = False
        candidate_path.write_text(json.dumps(candidate) + "\n", encoding="utf-8")
        return names
    monkeypatch.setattr(AI_MODULE, "_extract", fake_extract)
    def fake_records(extracted: Path, names: set[str], loaded_manifest: dict) -> None:
        observed["manifest"] = loaded_manifest
    monkeypatch.setattr(AI_MODULE, "_validate_failed_attempt_records", fake_records)
    monkeypatch.setattr(AI_MODULE, "_run_candidate_validator", lambda command, cwd, mode: {"status": "PASS_WITH_BLOCKER", "blockerCode": "REPLACEMENT_CANDIDATE_BINDING_MISMATCH", "releaseEligible": False})
    result = AI_MODULE.validate(ROOT / "outputs/DevFleet-v1.2.13-AI-Audit-LATEST.zip", mode="diagnostic")
    assert result["status"] == "PASS_WITH_BLOCKER"
    assert isinstance(observed.get("manifest"), dict)


@pytest.mark.parametrize("manifest_bytes", [b"", b"not-json"])
def test_ai_diagnostic_malformed_or_missing_manifest_fails_closed(tmp_path: Path, manifest_bytes: bytes):
    entries: dict[str, bytes] = {}
    with zipfile.ZipFile(ROOT / "outputs/DevFleet-v1.2.13-AI-Audit-LATEST.zip") as archive:
        entries = {name: archive.read(name) for name in archive.namelist() if not name.endswith("/")}
    if manifest_bytes:
        entries["AUDIT-MANIFEST.json"] = manifest_bytes
    else:
        entries.pop("AUDIT-MANIFEST.json", None)
    archive_path = tmp_path / "malformed.zip"
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    with pytest.raises(Exception):
        AI_MODULE.validate(archive_path, mode="diagnostic")

```


## FILE: tools/test_final_acceptance_tools.py

SHA256: caa0b34b7f7a797a2efbfacb5a191411923aecc6ba23849b6cb0c8724f9bc9a4 | Bytes: 3415 | Git mode: 100644

```
"""Focused static contract guards for the native final-acceptance entrypoints."""
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
ARCHIVE = ROOT