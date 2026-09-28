# DevFleet source part 104

Full-source UTF-8 byte interval [4789500, 4836000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ff5a3213bc0404cb6fc404d67d0ecca6a20402b9057d2f328ee232ea66c864ef

<!-- BEGIN SOURCE SLICE -->
PASS",
            "checks": checks,
        }
        if failed_attempt:
            report.update({"status": "PASS_WITH_BLOCKER", "blockerCode": FAILED_ATTEMPT_BLOCKER, "releaseEligible": False, "candidateIsCurrent": False, "sourceChangedSinceCandidate": True, "rebuildRequired": True, "failedAttemptSnapshot": FAILED_ATTEMPT_SNAPSHOT})
        if report_path:
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        return report
    finally:
        shutil.rmtree(temp_parent, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--mode", choices=("diagnostic", "release"), default="release")
    args = parser.parse_args()
    try:
        report = validate(args.archive, args.report, args.mode)
    except Exception as exc:  # noqa: BLE001 - CLI must return a useful deterministic failure.
        print(json.dumps({"status": "INCOMPLETE_FOR_AI_AUDIT", "error": str(exc)}))
        return 2
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/tools/validate_audit_coherence.py

SHA256: 9c5f6b489571f076a332da9128767ccc44d72882445b72029e5f2c07cafed651 | Bytes: 73537 | Git mode: 100644

```
"""Validate that a review bundle has one coherent current candidate.

Historical records are useful evidence, but they must opt in explicitly with
``historical: true``.  Everything else that names a candidate is treated as a
current record and is compared with finalization-state.json.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import io
import re
import subprocess
import sys
import tarfile
import tempfile
import shutil
from pathlib import Path
from typing import Any, Iterable


ARTIFACT_ALIASES = {
    "exe": ("exe", "EXE", "installer", "installerExe"),
    "tar": ("tar", "TAR", "payload"),
    "portable": ("portable", "PORTABLE"),
    "installer_source": ("installerSource", "installer_source", "INSTALLER_SOURCE"),
}

# The previous signed candidate is retained as evidence only.  This narrow
# allow-list is deliberately not a general historical bypass: diagnostic mode
# must prove this exact candidate/provenance pair and release mode never
# accepts it.
HISTORICAL_CANDIDATE = "2739e0366d070285e44b4fc764ef9247d40b2f94"
HISTORICAL_PROVENANCE = "f334a6eff999287b170fdbd9b6a31c3ef24a6119"
HISTORICAL_SHIPPING_IDENTITY = "daa30ef9f521a47fedb4bacce91e3440c20e1a8f05543b4d5e823e5c3541e64e"
HISTORICAL_RAW_GIT_SHIPPING_IDENTITY = "cdabf0791016282b1dc116c2e0d407718e7d7249d93935f90cc681afd737e92e"
HISTORICAL_RELEASE_FINGERPRINT = "80c8b88c2f2ec828f5ab0f9713d63fa3f4cc4cbad7c382aa2f154f3196c3de84"
HISTORICAL_PRESERVED_CANONICAL_PREFIX = "454edc"
HISTORICAL_RAW_GIT_PREFIX = "cdab"
HISTORICAL_RAW_RELEASE_PREFIX = "eba40"
FAILED_ATTEMPT_SNAPSHOT = "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
FAILED_ATTEMPT_SNAPSHOT_SHA256 = "ac37997945b6fa5ae9326b083ee730494b2c0c2e60d4809e7b49fc9707c0caac"
FAILED_ATTEMPT_COMMIT = "21752fc0e50978183322204c523b40947d073aa0"
FAILED_ATTEMPT_GIT_SHIPPING_IDENTITY = "6e0bac4b4eebc83cdcd9eddda2008607ba15c8835e5c72a931792f5b83c653f4"
FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY = "3a65fd54d70fe05565ac3a32f73100ca2c81a77a4008feb361f99f229f025f8a"
FAILED_ATTEMPT_BLOCKER = "REPLACEMENT_CANDIDATE_BINDING_MISMATCH"
FAILED_ATTEMPT_GENERATED_ROWS = frozenset({
    "source/CHECKSUMS.sha256",
    "installer-source/DevFleet.Setup/PayloadManifest.cs",
    "installer-source/INSTALLER-BUILD-MANIFEST.json",
})
HISTORICAL_ARTIFACTS = {
    "exe": (72078576, "e31e566cd8f9845cbaf5c85d972dceeeacbcaa6d55101868b8a71026cbde1c57"),
    "tar": (385200, "1b267c632f2219f4b49839a3b4eff064915d5d0acda83727e0a69fb49bd82985"),
    "portable": (2501018, "668e07dce12d7df8d61936b21e6b52ad2c3685dd7069a13cbfb7a1752c463dec"),
    "installersource": (702352, "e645019106b7e26080d8accf6c1da7f94be51150c19e347da35f8c047240abdc"),
}
AUTHORIZED_SHIPPING_PATHS = frozenset({
    "installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs",
    "installer-source/DevFleet.Setup/Services/InstallerServices.cs",
    "installer-source/DevFleet.Setup.Tests/Program.cs",
    "source/tools/validate_audit_coherence.py",
    "source/tools/validate_ai_audit_bundle.py",
    "source/tests/test_audit_coherence.py",
    "source/windows/DevFleet.Common.psm1",
})


def _load(path: Path) -> Any:
    try:
        # Windows PowerShell 5 may emit a UTF-8 BOM when it writes generated
        # audit manifests.  Accept that transport encoding while still
        # requiring strict JSON content.
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"Invalid JSON: {path}: {exc}") from exc


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _walk(value: Any, path: str = "$") -> Iterable[tuple[str, dict[str, Any]]]:
    if isinstance(value, dict):
        yield path, value
        for key, child in value.items():
            yield from _walk(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk(child, f"{path}[{index}]")


def _bool(value: Any, name: str, location: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{location}.{name} must be a JSON boolean")
    return value


def _artifact_rows(state: dict[str, Any], manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for source in (state.get("candidate"),):
        if isinstance(source, dict):
            for key, value in source.items():
                if isinstance(value, dict) and value.get("sha256"):
                    rows[key] = value
    for value in (manifest.get("artifacts"),):
        if isinstance(value, list):
            for row in value:
                if isinstance(row, dict) and row.get("sha256"):
                    name = str(row.get("name") or "")
                    rows[name] = row
    return rows


def _shipping_rows(value: Any) -> dict[tuple[str, str], dict[str, Any]]:
    """Normalize a release-fingerprint or bundle inventory to shipping rows."""
    rows: dict[tuple[str, str], dict[str, Any]] = {}
    if not isinstance(value, list):
        return rows
    for item in value:
        if not isinstance(item, dict):
            continue
        raw_path = str(item.get("path") or "").replace("\\", "/").lstrip("/")
        if raw_path.startswith("source/"):
            root, path = "source", raw_path[len("source/"):]
        elif raw_path.startswith("installer-source/"):
            root, path = "installer-source", raw_path[len("installer-source/"):]
        elif str(item.get("root") or "") in {"source", "installer-source"}:
            root, path = str(item["root"]), raw_path
        else:
            # A source inventory is allowed to contain non-shipping audit
            # tooling (automation/release-tooling), but a row that purports to
            # be shipping and cannot be classified is an ambiguity, never a
            # row to silently discard.
            non_shipping = raw_path.startswith(("automation/", "release-tooling/")) or str(item.get("root") or "") in {"automation", "release-tooling"}
            if not non_shipping:
                raise ValueError(f"unclassified shipping row: {raw_path or item.get('root')}")
            continue
        key = (root, path)
        if key in rows:
            raise ValueError(f"duplicate shipping row: {root}/{path}")
        if "mode" not in item:
            raise ValueError(f"{raw_path or item.get('root')} shipping row is missing its canonical mode")
        mode = str(item.get("mode") or "")
        if mode not in {"0644", "0755"}:
            raise ValueError(f"{raw_path or item.get('root')} shipping row has an invalid canonical mode")
        rows[key] = {
            "root": root,
            "path": path,
            "bytes": int(item.get("bytes", -1)),
            "sha256": str(item.get("sha256") or "").lower(),
            "mode": mode,
        }
    return rows


def _shipping_identity(rows: dict[tuple[str, str], dict[str, Any]], mode: dict[str, Any], version: str, installer: str) -> str:
    # Match release_fingerprint.py exactly: Path.rglob is sorted separately
    # for each root, with Windows path components compared case-insensitively.
    # Compare components (rather than the joined string) so a directory named
    # ``python`` sorts before its sibling ``python-fastapi`` just as Path does.
    # The release contract concatenates source rows before installer rows.
    root_order = {"source": 0, "installer-source": 1}
    ordered_keys = sorted(
        rows,
        key=lambda key: (
            root_order.get(key[0], 2),
            tuple(component.casefold() for component in key[1].split("/")),
        ),
    )
    ordered = [rows[key] for key in ordered_keys]
    payload = {"schemaVersion": 1, "devfleetVersion": version, "installerVersion": installer, "shippingModeContract": mode, "shippingInputs": ordered}
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _release_id(record: dict[str, Any]) -> str:
    payload = {
        "schemaVersion": record.get("schemaVersion"),
        "devfleetVersion": record.get("devfleetVersion"),
        "installerVersion": record.get("installerVersion"),
        "shippingModeContract": record.get("shippingModeContract"),
        "shippingInputs": record.get("shippingInputs"),
        "artifacts": record.get("artifacts", []),
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _candidate_fingerprint_from_git(root: Path, commit: str) -> tuple[dict[str, Any], Path]:
    if not (root / ".git").exists():
        raise ValueError("candidate shipping rows are not embedded in the bundle")
    if len(commit) != 40 or any(ch not in "0123456789abcdefABCDEF" for ch in commit):
        raise ValueError("candidate commit must be an explicit 40-character Git object ID")
    try:
        subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{commit}^{{commit}}"], check=True, capture_output=True, text=True)
        archive = subprocess.check_output(["git", "-C", str(root), "-c", "core.autocrlf=false", "archive", "--format=tar", commit, "source", "installer-source"], stderr=subprocess.STDOUT)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError(f"candidate commit cannot be materialized: {commit}") from exc
    staging = Path(tempfile.mkdtemp(prefix="devfleet-validator-candidate-"))
    try:
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
            stream.extractall(staging, filter="data")
        source, installer = staging / "source", staging / "installer-source"
        if not source.is_dir() or not installer.is_dir():
            raise ValueError("candidate shipping roots are missing or ambiguous")
        tools_dir = source / "tools"
        sys.path.insert(0, str(tools_dir))
        try:
            from release_fingerprint import build_fingerprint  # type: ignore
            return build_fingerprint(source, installer), staging
        finally:
            sys.path.remove(str(tools_dir))
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def _validate_row_shape(rows: dict[tuple[str, str], dict[str, Any]], location: str) -> None:
    if not rows:
        raise ValueError(f"{location} has no deterministic shipping rows")
    for key, row in rows.items():
        if row["bytes"] < 0 or len(row["sha256"]) != 64 or any(ch not in "0123456789abcdef" for ch in row["sha256"]):
            raise ValueError(f"{location} contains malformed shipping row: {key[0]}/{key[1]}")


def _validate_crlf_partition(root: Path, state: dict[str, Any], manifest: dict[str, Any], candidate: dict[str, Any], record: dict[str, Any]) -> None:
    live = _shipping_rows(manifest.get("sourceInventory"))
    candidate_rows = _shipping_rows(candidate.get("candidateShippingInputs"))
    _validate_row_shape(live, "diagnostic live shipping rows")
    changed = sorted(f"{key[0]}/{key[1]}" for key in set(live) | set(candidate_rows) if live.get(key) != candidate_rows.get(key))
    authorization = state.get("authorized_correction") if isinstance(state.get("authorized_correction"), dict) else {}
    authorized = {str(path).replace("\\", "/") for path in authorization.get("shipping_paths", []) if str(path)}
    historical = sorted(path for path in changed if path not in authorized)
    unknown = sorted(path for path in historical if not path.startswith(("source/", "installer-source/")))
    recorded = sorted(str(path).replace("\\", "/") for path in record.get("crlfOnlyHistoricalPaths", []) if str(path))
    if unknown or sorted(recorded) != historical or int(record.get("crlfOnlyHistoricalPathCount", -1)) != len(historical):
        raise ValueError("diagnostic historical CRLF/current-change partition is incomplete or contains unknown paths")
    if str(record.get("lineEndingComparison") or "").upper() not in {"CRLF_ONLY", "CRLF-ONLY"}:
        raise ValueError("diagnostic historical path partition is not marked CRLF-only")
    # In a live workspace the candidate bytes are available from Git and the
    # current bytes from the checkout, allowing an actual normalized-content
    # proof.  A bundle has no .git and must carry the signed row partition;
    # accepting a missing partition there would be an unsafe downgrade.
    if (root / ".git").exists():
        _, staging = _candidate_fingerprint_from_git(root, HISTORICAL_CANDIDATE)
        try:
            for path in historical:
                current_path = root / Path(*path.split("/"))
                candidate_path = staging / Path(*path.split("/"))
                if not current_path.is_file() or not candidate_path.is_file():
                    raise ValueError(f"historical CRLF proof path is missing: {path}")
                current_bytes = current_path.read_bytes()
                candidate_bytes = candidate_path.read_bytes()
                normalize = lambda value: value.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
                if normalize(current_bytes) != normalize(candidate_bytes) or current_bytes == candidate_bytes:
                    raise ValueError(f"historical path is not a CRLF-only materialization difference: {path}")
        finally:
            shutil.rmtree(staging, ignore_errors=True)
    else:
        # An extracted diagnostic bundle has no Git object database.  It must
        # therefore carry the exact candidate bytes for every recorded path;
        # accepting row hashes alone would not prove that the difference is
        # limited to line endings.
        materialization = str(record.get("historicalMaterializationRoot") or "").replace("\\", "/").strip("/")
        if not materialization.startswith("release-tooling/historical-candidate-") or ".." in materialization.split("/"):
            raise ValueError("diagnostic historical candidate byte materialization is missing or outside release-tooling")
        bundle_root = root.resolve()
        for path in historical:
            current_path = root / Path(*path.split("/"))
            candidate_path = root / Path(*materialization.split("/")) / Path(*path.split("/"))
            if not current_path.is_file() or not candidate_path.is_file() or not current_path.resolve().is_relative_to(bundle_root) or not candidate_path.resolve().is_relative_to(bundle_root):
                raise ValueError(f"historical CRLF proof materialization is missing: {path}")
            current_bytes = current_path.read_bytes()
            candidate_bytes = candidate_path.read_bytes()
            normalize = lambda value: value.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
            if normalize(current_bytes) != normalize(candidate_bytes) or current_bytes == candidate_bytes:
                raise ValueError(f"historical path is not a CRLF-only materialization difference: {path}")


def _validate_failed_attempt_freeze(root: Path, state: dict[str, Any], manifest: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    """Validate the immutable failed replacement attempt before any report.

    This is a diagnostic evidence contract, not a promotion path.  Every
    asserted identity is recomputed from the frozen tables and the snapshot
    itself is hash-bound; declarations in current authority files cannot make
    an attempted candidate current.
    """
    path = root / Path(*FAILED_ATTEMPT_SNAPSHOT.split("/"))
    if not path.is_file() or _sha256(path) != FAILED_ATTEMPT_SNAPSHOT_SHA256:
        raise ValueError("failed replacement-attempt snapshot is missing or hash-mismatched")
    snapshot = _load(path)
    if snapshot.get("immutableSnapshot") is not True or snapshot.get("freezeType") != "LUNA_HIGH_FAILED_ATTEMPT_EVIDENCE_FREEZE":
        raise ValueError("failed replacement-attempt snapshot is not immutable evidence")
    repository = snapshot.get("repository") if isinstance(snapshot.get("repository"), dict) else {}
    if str(repository.get("head") or "").lower() != FAILED_ATTEMPT_COMMIT or str(repository.get("expectedFrozenHead") or "").lower() != FAILED_ATTEMPT_COMMIT:
        raise ValueError("failed replacement-attempt snapshot commit identity is invalid")
    shipping = snapshot.get("shippingIdentity") if isinstance(snapshot.get("shippingIdentity"), dict) else {}
    archive = shipping.get("gitArchive") if isinstance(shipping.get("gitArchive"), dict) else {}
    live = shipping.get("buildTimeLive") if isinstance(shipping.get("buildTimeLive"), dict) else {}
    if str(archive.get("identity") or "").lower() != FAILED_ATTEMPT_GIT_SHIPPING_IDENTITY or str(live.get("identity") or "").lower() != FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY:
        raise ValueError("failed replacement-attempt shipping identities do not match frozen evidence")
    archive_rows = _shipping_rows(archive.get("rows"))
    live_rows = _shipping_rows(live.get("rows"))
    for rows_value, location in ((archive_rows, "failed-attempt Git archive rows"), (live_rows, "failed-attempt build-time rows")):
        _validate_row_shape(rows_value, location)
    archive_mode = archive.get("modeContract") if isinstance(archive.get("modeContract"), dict) else {}
    live_mode = live.get("modeContract") if isinstance(live.get("modeContract"), dict) else {}
    if archive.get("rowCount") != 730 or live.get("rowCount") != 730 or len(archive_rows) != 730 or len(live_rows) != 730 or shipping.get("releaseFingerprintRowsMatchBuildTimeLive") is not True or _shipping_identity(archive_rows, archive_mode, str(archive.get("version") or ""), str(archive.get("installerVersion") or "")) != FAILED_ATTEMPT_GIT_SHIPPING_IDENTITY or _shipping_identity(live_rows, live_mode, str(live.get("version") or ""), str(live.get("installerVersion") or "")) != FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY:
        raise ValueError("failed replacement-attempt shipping row counts or release-row binding are invalid")
    actual_row_diffs = {key for key in set(archive_rows) | set(live_rows) if archive_rows.get(key) != live_rows.get(key)}
    normalized = shipping.get("normalizedRowDiff") if isinstance(shipping.get("normalizedRowDiff"), dict) else {}
    rows = normalized.get("rows")
    if not isinstance(rows, list) or normalized.get("rowCount") != 28 or normalized.get("crlfOnlyRows") != 25 or normalized.get("exactChangedRows") != 3 or len(rows) != 28:
        raise ValueError("failed replacement-attempt normalized shipping table must contain exactly 28 rows")
    seen: set[str] = set()
    crlf_count = 0
    generated: set[str] = set()
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("gitArchive"), dict) or not isinstance(row.get("buildTimeLive"), dict):
            raise ValueError("failed replacement-attempt row is malformed")
        key = f"{row['root']}/{row['path']}"
        if key in seen:
            raise ValueError("failed replacement-attempt row table contains duplicates")
        seen.add(key)
        if (row.get("root"), row.get("path")) not in actual_row_diffs:
            raise ValueError("failed replacement-attempt normalized row is not an actual shipping-row difference")
        comparison = str(row.get("comparison") or "")
        if comparison == "CRLF_ONLY_NORMALIZED_EQUAL":
            if row.get("normalizedEqual") is not True:
                raise ValueError("failed replacement-attempt CRLF row is not normalized-equal")
            crlf_count += 1
        elif comparison == "CONTENT_OR_GENERATED_CHANGE":
            if row.get("normalizedEqual") is not False or key not in FAILED_ATTEMPT_GENERATED_ROWS:
                raise ValueError("failed replacement-attempt generated row is not exact")
            generated.add(key)
        else:
            raise ValueError("failed replacement-attempt row has an unclassified comparison")
    if actual_row_diffs != {(key.split("/", 1)[0], key.split("/", 1)[1]) for key in seen} or crlf_count != 25 or generated != set(FAILED_ATTEMPT_GENERATED_ROWS) or any("Payload/devfleet-v1.2.13.tar.gz" in key for key in seen):
        raise ValueError("failed replacement-attempt 25/3 shipping partition is invalid")
    artifact_hashes = snapshot.get("artifactPathHashes")
    if not isinstance(artifact_hashes, list) or not any(isinstance(row, dict) and row.get("path") == "installer-source/DevFleet.Setup/Payload/devfleet-v1.2.13.tar.gz" for row in artifact_hashes):
        raise ValueError("tracked Payload TAR must remain separately recorded outside shipping-input rows")
    signing = snapshot.get("signing") if isinstance(snapshot.get("signing"), dict) else {}
    if signing.get("operationCount") != 1 or signing.get("rebuildInvocationCount") != 1:
        raise ValueError("failed replacement-attempt build/sign operation count is not exactly one")
    attempt = state.get("failed_replacement_attempt")
    if not isinstance(attempt, dict):
        raise ValueError("current authority is missing failed replacement-attempt binding")
    required_attempt = {
        "snapshotPath": FAILED_ATTEMPT_SNAPSHOT,
        "snapshotSha256": FAILED_ATTEMPT_SNAPSHOT_SHA256,
        "attemptedCommit": FAILED_ATTEMPT_COMMIT,
        "commitShippingInputIdentity": FAILED_ATTEMPT_GIT_SHIPPING_IDENTITY,
        "buildTimeShippingInputIdentity": FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY,
        "artifactTupleValid": True,
        "artifactTupleMatchesCandidate": False,
        "blockerCode": FAILED_ATTEMPT_BLOCKER,
    }
    for key, expected in required_attempt.items():
        if attempt.get(key) != expected:
            raise ValueError(f"failed replacement-attempt authority contradicts frozen evidence: {key}")
    historical = state.get("historical_candidate")
    if not isinstance(historical, dict) or str(historical.get("candidateCommit") or "").lower() != HISTORICAL_CANDIDATE or str(historical.get("shippingInputIdentity") or "").lower() != HISTORICAL_SHIPPING_IDENTITY or str(historical.get("releaseFingerprintId") or "").lower() != HISTORICAL_RELEASE_FINGERPRINT:
        raise ValueError("preserved historical candidate tuple is missing or mutated")
    historical_artifacts = historical.get("artifacts")
    historical_by_name = {
        str(key).lower().replace("-", "").replace("_", ""): value
        for key, value in (historical_artifacts.items() if isinstance(historical_artifacts, dict) else [])
    }
    for name, (expected_bytes, expected_sha) in HISTORICAL_ARTIFACTS.items():
        observed = historical_by_name.get(name)
        if not isinstance(observed, dict) or int(observed.get("bytes", -1)) != expected_bytes or str(observed.get("sha256") or "").lower() != expected_sha:
            raise ValueError(f"preserved historical artifact tuple is mutated: {name}")
    if str(state.get("candidate_git_commit") or "").lower() != FAILED_ATTEMPT_COMMIT or str(state.get("shipping_input_identity") or "").lower() != FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY or str(state.get("candidate_shipping_input_identity") or "").lower() != FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY:
        raise ValueError("failed replacement-attempt current tuple is not bound to build-time identity")
    attempted_artifacts = snapshot.get("candidate", {}).get("newArtifactTuple", {}).get("artifacts", []) if isinstance(snapshot.get("candidate"), dict) else []
    state_artifacts = state.get("candidate") if isinstance(state.get("candidate"), dict) else {}
    state_by_name = {str(value.get("name") or key).lower().replace("-", "").replace("_", ""): value for key, value in state_artifacts.items() if isinstance(value, dict)}
    for row in attempted_artifacts:
        if not isinstance(row, dict):
            raise ValueError("failed replacement-attempt artifact row is malformed")
        key = str(row.get("name") or "").lower().replace("-", "").replace("_", "")
        observed = state_by_name.get(key)
        if not observed or int(observed.get("bytes", -1)) != int(row.get("bytes", -2)) or str(observed.get("sha256") or "").lower() != str(row.get("sha256") or "").lower():
            raise ValueError(f"failed replacement-attempt artifact tuple mismatch: {key}")
    post = attempt.get("postFailureEvidenceTooling")
    if not isinstance(post, dict) or post.get("classification") != "POST_FAILURE_EVIDENCE_TOOLING" or not isinstance(post.get("paths"), list) or not post["paths"]:
        raise ValueError("post-failure validator edits are not separately bound")
    post_paths = {str(item.get("path") or "").replace("\\", "/") for item in post["paths"] if isinstance(item, dict)}
    if post_paths != {"source/tools/validate_audit_coherence.py", "source/tools/validate_ai_audit_bundle.py"} or len(post["paths"]) != 2:
        raise ValueError("post-failure tooling path binding is not the exact separate validator set")
    for item in post["paths"]:
        if not isinstance(item, dict) or not str(item.get("path") or "").startswith("source/") or len(str(item.get("sha256") or "")) != 64:
            raise ValueError("post-failure tooling path binding is malformed")
        current = root / Path(*str(item["path"]).replace("\\", "/").split("/"))
        if not current.is_file() or _sha256(current) != str(item["sha256"]).lower():
            raise ValueError(f"post-failure tooling path hash mismatch: {item.get('path')}")
    terminal = attempt.get("terminalEvidence")
    if not isinstance(terminal, dict) or not isinstance(terminal.get("l1"), dict) or not isinstance(terminal.get("l2"), dict):
        raise ValueError("failed replacement-attempt terminal L1/L2 evidence fields are missing")
    for name in ("l1", "l2"):
        if str(terminal[name].get("state") or "") not in {"UNVERIFIED", "Off", "OFF", "Absent", "ABSENT"}:
            raise ValueError(f"failed replacement-attempt terminal {name} state is invalid")
    flags = (state.get("candidate_is_current"), state.get("source_changed_since_candidate"), state.get("rebuild_required"), state.get("artifact_tuple_matches_candidate"), state.get("full_release_passed"), state.get("internal_promotion_allowed"), state.get("public_promotion_allowed"))
    if flags != (False, True, True, False, False, False, False):
        raise ValueError("failed replacement-attempt authority flags are not truthful")
    if str(state.get("status") or "") != "BLOCKED — USER ACTION REQUIRED" or str(state.get("blocker_code") or "") != FAILED_ATTEMPT_BLOCKER:
        raise ValueError("failed replacement-attempt terminal status or blocker code is missing")
    for label, view in (("manifest", manifest), ("candidate", candidate)):
        if not isinstance(view, dict) or not view:
            continue
        if str(view.get("candidateGitCommit") or view.get("candidateCommit") or "").lower() not in {"", FAILED_ATTEMPT_COMMIT}:
            raise ValueError(f"failed replacement-attempt {label} commit identity contradicts frozen evidence")
        for key in ("candidateIsCurrent", "sourceChangedSinceCandidate", "rebuildRequired", "artifactTupleMatchesCandidate"):
            if key in view and view[key] is not {"candidateIsCurrent": False, "sourceChangedSinceCandidate": True, "rebuildRequired": True, "artifactTupleMatchesCandidate": False}[key]:
                raise ValueError(f"failed replacement-attempt {label} flag contradicts frozen evidence: {key}")
    return {"snapshotSha256": FAILED_ATTEMPT_SNAPSHOT_SHA256, "attemptedCommit": FAILED_ATTEMPT_COMMIT, "commitShippingInputIdentity": FAILED_ATTEMPT_GIT_SHIPPING_IDENTITY, "buildTimeShippingInputIdentity": FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY, "shippingRows": 730, "changedRows": 28, "crlfOnlyRows": 25, "generatedShippingOutputRows": 3}


def _historical_provenance(root: Path, state: dict[str, Any], manifest: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    """Validate the one permitted historical diagnostic provenance record.

    Historical evidence is accepted only as a recomputed, non-promotable
    report.  In particular, a declaration of ``historical`` or a copied hash
    is not evidence.  Candidate rows are recomputed from the immutable Git
    object (or checked against the embedded offline rows), and the release
    fingerprint/artifact closure is recomputed from the supplied rows.
    """
    records = [value for value in (candidate.get("historicalProvenance"), manifest.get("historicalProvenance"), state.get("historical_provenance")) if isinstance(value, dict)]
    record = records[0] if records else None
    if record is None:
        raise ValueError("diagnostic mode requires a structured historicalProvenance record")
    if any(value != record for value in records[1:]):
        raise ValueError("diagnostic historical provenance declarations disagree")
    if str(record.get("candidateCommit") or "").lower() != HISTORICAL_CANDIDATE:
        raise ValueError("diagnostic historical candidate is not the preserved 2739 object")
    if str(record.get("provenanceCommit") or record.get("sourceCommit") or "").lower() != HISTORICAL_PROVENANCE:
        raise ValueError("diagnostic historical provenance is not the preserved f334 object")
    if str(record.get("materialization") or "") != "git-archive" or record.get("coreAutocrlf") is not False:
        raise ValueError("historical provenance must use deterministic git-archive materialization with core.autocrlf=false")
    if str(record.get("lineEndingComparison") or "").upper() not in {"CRLF_ONLY", "CRLF-ONLY"}:
        raise ValueError("historical provenance must identify a CRLF-only comparison")
    if str(record.get("historicalShippingInputIdentity") or "").lower() != HISTORICAL_SHIPPING_IDENTITY:
        raise ValueError("diagnostic historical shipping identity is not the preserved identity")
    if str(record.get("historicalReleaseFingerprintId") or "").lower() != HISTORICAL_RELEASE_FINGERPRINT:
        raise ValueError("diagnostic historical release fingerprint is not the preserved fingerprint")
    labels = record.get("identityLabels") if isinstance(record.get("identityLabels"), dict) else {}
    if not str(labels.get("preservedCanonicalShippingInputIdentity") or "").lower().startswith(HISTORICAL_PRESERVED_CANONICAL_PREFIX) or not str(labels.get("rawGitShippingInputIdentity") or "").lower().startswith(HISTORICAL_RAW_GIT_PREFIX) or not str(labels.get("rawGitReleaseFingerprintId") or "").lower().startswith(HISTORICAL_RAW_RELEASE_PREFIX):
        raise ValueError("diagnostic historical identity labels are incomplete")
    authorization = state.get("authorized_correction") if isinstance(state.get("authorized_correction"), dict) else {}
    expected_paths = sorted(str(path).replace("\\", "/") for path in authorization.get("shipping_paths", []) if str(path))
    if set(expected_paths) != AUTHORIZED_SHIPPING_PATHS or len(expected_paths) != len(AUTHORIZED_SHIPPING_PATHS):
        raise ValueError("diagnostic authorization must contain exactly the seven reviewed shipping paths")
    recorded_paths = sorted(str(path).replace("\\", "/") for path in record.get("authorizedCurrentShippingPaths", []) if str(path))
    if not expected_paths or recorded_paths != expected_paths:
        raise ValueError("diagnostic historical provenance does not bind the exact authorized shipping paths")

    rows = _shipping_rows(candidate.get("candidateShippingInputs"))
    if not rows:
        raise ValueError("diagnostic historical candidate rows are mandatory and offline")
    _validate_row_shape(rows, "diagnostic candidate shipping rows")
    mode = candidate.get("candidateShippingModeContract") or record.get("shippingModeContract") or {}
    version = str(candidate.get("devfleetVersion") or manifest.get("devfleetVersion") or "")
    installer = str(candidate.get("installerVersion") or manifest.get("installerVersion") or "")
    if version != "1.2.13" or installer != "1.4.1":
        raise ValueError("diagnostic historical candidate version tuple is not the exact 1.2.13/1.4.1 tuple")
    if not isinstance(mode, dict) or set(mode) != {"schemaVersion", "defaultMode", "executableMode", "executableByContract"} or mode.get("schemaVersion") != 1 or mode.get("defaultMode") != "0644" or mode.get("executableMode") != "0755" or not isinstance(mode.get("executableByContract"), list) or mode["executableByContract"] != sorted(str(path) for path in mode["executableByContract"]):
        raise ValueError("diagnostic historical candidate mode contract is incomplete or non-canonical")
    recomputed = _shipping_identity(rows, mode, version, installer)
    declared_recomputed = str(record.get("recomputedCandidateShippingInputIdentity") or "").lower()
    if declared_recomputed != recomputed or recomputed != HISTORICAL_RAW_GIT_SHIPPING_IDENTITY:
        raise ValueError("diagnostic candidate shipping identity was not recomputed from embedded rows")
    # When validating in the repository, independently materialize the
    # candidate object with core.autocrlf disabled.  Bundles intentionally have
    # no .git directory, so their signed-off offline rows are the required
    # source of truth there.
    if (root / ".git").exists():
        fingerprint, staging = _candidate_fingerprint_from_git(root, HISTORICAL_CANDIDATE)
        try:
            materialized = _shipping_rows(fingerprint.get("shippingInputs"))
            if materialized != rows:
                raise ValueError("diagnostic embedded candidate rows differ from deterministic Git materialization")
        finally:
            shutil.rmtree(staging, ignore_errors=True)
    _validate_crlf_partition(root, state, manifest, candidate, record)

    # A release row set is required even in diagnostic mode.  This prevents a
    # historical marker from making a stale artifact tuple look coherent.
    release = _load(root / "outputs" / "release-fingerprint.json") if (root / "outputs" / "release-fingerprint.json").is_file() else {}
    if not isinstance(release, dict):
        raise ValueError("diagnostic release fingerprint is missing")
    raw_release_rows = release.get("shippingInputs")
    release_rows = _shipping_rows(raw_release_rows)
    _validate_row_shape(release_rows, "diagnostic release shipping rows")
    release_payload = {
        "schemaVersion": release.get("schemaVersion"),
        "devfleetVersion": release.get("devfleetVersion"),
        "installerVersion": release.get("installerVersion"),
        "shippingModeContract": release.get("shippingModeContract"),
        # release_fingerprint.py preserves source-root then installer-root
        # enumeration order; identity rows are not lexicographically sorted
        # across roots for this schema.
        "shippingInputs": raw_release_rows,
        "artifacts": release.get("artifacts", []),
    }
    recomputed_release = hashlib.sha256(json.dumps(release_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    if recomputed_release != HISTORICAL_RELEASE_FINGERPRINT or str(release.get("releaseFingerprintId") or "").lower() != recomputed_release:
        raise ValueError("diagnostic release fingerprint rows do not recompute to the preserved fingerprint")
    declared_historical_release = str(record.get("recomputedHistoricalReleaseFingerprintId") or "").lower()
    if not declared_historical_release or declared_historical_release != recomputed_release:
        raise ValueError("diagnostic historical release fingerprint closure is not recomputed")
    artifacts = release.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) < 4 or any(not isinstance(row, dict) or len(str(row.get("sha256") or "")) != 64 or int(row.get("bytes", -1)) < 1 for row in artifacts):
        raise ValueError("diagnostic historical artifact tuple is incomplete")
    def artifact_key(value: Any) -> str:
        return str(value or "").lower().replace("-", "").replace("_", "")
    release_artifacts = {artifact_key(row.get("name")): row for row in artifacts if isinstance(row, dict)}
    state_artifacts = {}
    if isinstance(state.get("candidate"), dict):
        state_artifacts = {artifact_key(value.get("name") or key): value for key, value in state["candidate"].items() if isinstance(value, dict)}
    if not state_artifacts:
        raise ValueError("diagnostic historical candidate artifact tuple is missing")
    for key in ("exe", "tar", "portable", "installersource"):
        expected = next((row for name, row in release_artifacts.items() if key in name), None)
        observed = next((row for name, row in state_artifacts.items() if key in name), None)
        if expected is None or observed is None or str(expected.get("sha256") or "").lower() != str(observed.get("sha256") or "").lower() or int(expected.get("bytes", -1)) != int(observed.get("bytes", -2)):
            raise ValueError(f"diagnostic artifact closure mismatch: {key}")
    flags = {
        "candidateIsCurrent": state.get("candidate_is_current"),
        "sourceChangedSinceCandidate": state.get("source_changed_since_candidate"),
        "rebuildRequired": state.get("rebuild_required"),
        "fullReleasePassed": state.get("full_release_passed"),
        "internalPromotionAllowed": state.get("internal_promotion_allowed"),
        "publicPromotionAllowed": state.get("public_promotion_allowed"),
    }
    if flags != {"candidateIsCurrent": False, "sourceChangedSinceCandidate": True, "rebuildRequired": True, "fullReleasePassed": False, "internalPromotionAllowed": False, "publicPromotionAllowed": False}:
        raise ValueError("diagnostic historical authority flags are not truthful")
    if record.get("releaseEligible") is not False or record.get("promotionAllowed") is not False:
        raise ValueError("historical diagnostic provenance cannot be release eligible or promotable")
    return {"candidateShippingInputIdentity": recomputed, "historicalReleaseFingerprintId": recomputed_release, "provenanceCommit": HISTORICAL_PROVENANCE}


def _validate_split_identity(root: Path, state: dict[str, Any], manifest: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    """Validate the candidate/repository split without allowing unknown drift.

    A tooling-only HEAD may advance while the candidate remains byte-identical.
    If shipping rows differ, the candidate is permitted to remain historical only
    when the current authority explicitly records the narrow authorized paths;
    otherwise the validator fails closed on an unclassified shipping change.
    """
    candidate_commit = str(state.get("candidate_git_commit") or manifest.get("candidateGitCommit") or candidate.get("candidateCommit") or "")
    if len(candidate_commit) != 40 or any(ch not in "0123456789abcdefABCDEF" for ch in candidate_commit) or candidate_commit.lower() == "0" * 40:
        raise ValueError("candidate commit must be explicit for split-identity validation")
    candidate_declarations = [str(value).lower() for value in (
        state.get("candidate_shipping_input_identity"), state.get("shipping_input_identity"),
        manifest.get("candidateShippingInputIdentity"), candidate.get("candidateShippingInputIdentity")) if value]
    live_declarations = [str(value).lower() for value in (manifest.get("shippingInputIdentity"), candidate.get("shippingInputIdentity")) if value]
    if not candidate_declarations or not live_declarations:
        raise ValueError("current candidate and live shipping-input identities are required")
    if len(set(candidate_declarations)) != 1 or len(set(live_declarations)) != 1:
        raise ValueError("candidate or live shipping-input identity declarations disagree")
    candidate_shipping, live_shipping = candidate_declarations[0], live_declarations[0]
    if any(not re.fullmatch(r"[0-9a-f]{64}", value) or value == "0" * 64 for value in (candidate_shipping, live_shipping)):
        raise ValueError("candidate and live shipping-input identities are malformed")

    release = _load(root / "outputs" / "release-fingerprint.json") if (root / "outputs" / "release-fingerprint.json").is_file() else {}
    embedded_candidate_rows = _shipping_rows(candidate.get("candidateShippingInputs"))
    candidate_fingerprint = None
    if embedded_candidate_rows:
        candidate_rows = embedded_candidate_rows
        candidate_mode = candidate.get("candidateShippingModeContract") or {}
    else:
        candidate_fingerprint, staging = _candidate_fingerprint_from_git(root, candidate_commit)
        try:
            candidate_rows = _shipping_rows(candidate_fingerprint.get("shippingInputs"))
            candidate_mode = candidate_fingerprint.get("shippingModeContract") or {}
        finally:
            shutil.rmtree(staging, ignore_errors=True)
    _validate_row_shape(candidate_rows, "candidate shipping rows")
    inventory = _shipping_rows(manifest.get("sourceInventory"))
    if not inventory:
        # A workspace invocation has no staged AUDIT-MANIFEST.  Recompute the
        # live deterministic rows from the actual shipping trees; a bundle
        # invocation uses its manifest inventory above.
        try:
            tools_dir = root / "source" / "tools"
            sys.path.insert(0, str(tools_dir))
            from release_fingerprint import build_fingerprint  # type: ignore
            live_fingerprint = build_fingerprint(root / "source", root / "installer-source")
            inventory = _shipping_rows(live_fingerprint.get("shippingInputs"))
            live_mode = live_fingerprint.get("shippingModeContract") or {}
            live_version = str(live_fingerprint.get("devfleetVersion") or "")
            live_installer = str(live_fingerprint.get("installerVersion") or "")
        except (ImportError, OSError, ValueError):
            inventory = {}
        finally:
            if str(tools_dir) in sys.path:
                sys.path.remove(str(tools_dir))
    else:
        live_mode = manifest.get("shippingModeContract") or candidate.get("shippingModeContract") or candidate_mode
        live_version = str(manifest.get("devfleetVersion") or state.get("release_version") or "")
        live_installer = str(manifest.get("installerVersion") or state.get("installer_version") or "")
    if not inventory:
        raise ValueError("live shipping rows are required")
    _validate_row_shape(inventory, "live shipping rows")
    if not candidate_mode or not live_mode:
        raise ValueError("candidate and live shipping mode contracts are required")
    # AUDIT-MANIFEST sourceInventory rows carry byte identity, while the
    # executable mode contract is transported separately in SOURCE-MODES.
    # Apply that contract before hashing the live rows so the validator uses
    # exactly the same canonical mode values as release_fingerprint.py.
    modes_path = root / "SOURCE-MODES.json"
    if inventory and modes_path.is_file():
        modes = _load(modes_path)
        if isinstance(modes, list):
            for item in modes:
                if not isinstance(item, dict):
                    continue
                raw_path = str(item.get("path") or "").replace("\\", "/")
                if raw_path.startswith("source/"):
                    key = ("source", raw_path[len("source/"):])
                elif raw_path.startswith("installer-source/"):
                    key = ("installer-source", raw_path[len("installer-source/"):])
                else:
                    continue
                if key in inventory:
                    canonical_mode = "0755" if int(item.get("posixMode", 420)) == 493 else "0644"
                    if inventory[key].get("mode") != canonical_mode:
                        raise ValueError(f"shipping row mode disagrees with SOURCE-MODES.json: {key[0]}/{key[1]}")
                    inventory[key]["mode"] = canonical_mode
    # Independently walk the extracted shipping trees as well as validating
    # the manifest inventory.  A builder omission/addition must be diagnosed
    # as a concrete row mismatch instead of surfacing only as an opaque digest
    # disagreement.
    tools_dir = root / "source" / "tools"
    sys.path.insert(0, str(tools_dir))
    try:
        from release_fingerprint import build_fingerprint  # type: ignore

        direct_fingerprint = build_fingerprint(root / "source", root / "installer-source")
    finally:
        if str(tools_dir) in sys.path:
            sys.path.remove(str(tools_dir))
    direct_rows = _shipping_rows(direct_fingerprint.get("shippingInputs"))
    if direct_rows != inventory:
        differing_keys = sorted(set(direct_rows) | set(inventory), key=lambda key: (key[0], key[1].casefold()))
        first = next(key for key in differing_keys if direct_rows.get(key) != inventory.get(key))
        raise ValueError(f"sourceInventory disagrees with extracted shipping bytes: {first[0]}/{first[1]}")
    computed_candidate = _shipping_identity(candidate_rows, candidate_mode, str(state.get("release_version") or candidate.get("devf