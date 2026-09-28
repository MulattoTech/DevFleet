# DevFleet source part 105

Full-source UTF-8 byte interval [4836000, 4882500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 6bf6ed8514b43b6a8c0f03e4fef98e91bfc0a7fe96a777388f3f7b8a392c90be

<!-- BEGIN SOURCE SLICE -->
leetVersion") or ""), str(state.get("installer_version") or candidate.get("installerVersion") or ""))
    computed_live = _shipping_identity(inventory, live_mode, live_version, live_installer)
    if candidate_shipping != computed_candidate or live_shipping != computed_live:
        raise ValueError(
            "declared shipping-input identity does not match recomputed canonical rows: "
            f"candidate={candidate_shipping}/{computed_candidate}, live={live_shipping}/{computed_live}"
        )
    differing: list[tuple[str, str]] = []
    if candidate_rows and inventory:
        # The release fingerprint's own schema-v2 digest is verified below by
        # _validate_fingerprint_files.  The bundle validator independently
        # verifies each live inventory byte against SHA256SUMS.  Keep the
        # PowerShell Sort-Object/culture serialization out of this Python
        # validator; compare the resulting deterministic rows and declared IDs
        # instead of silently inventing a second canonicalization contract.
        differing = sorted({*candidate_rows, *inventory} - {key for key in candidate_rows if candidate_rows.get(key) == inventory.get(key)})
        if differing:
            authority = state.get("authorized_correction")
            allowed = {
                str(path).replace("\\", "/").lstrip("/")
                for path in (authority.get("shipping_paths", []) if isinstance(authority, dict) else [])
            }
            differing_paths = {f"{root_name}/{path}" for root_name, path in differing}
            # Generic invalidated-candidate diagnostics must bind the complete
            # substantive delta, not a stale release-specific allowlist.  The
            # historical 2739 diagnostic retains its exact seven-path contract
            # in _historical_provenance above.  Every newer diagnostic is
            # fail-closed unless the declared paths equal (not merely contain)
            # the independently recomputed candidate/live row differences.
            if not allowed or allowed != differing_paths:
                unexpected = sorted(differing_paths - allowed)
                stale = sorted(allowed - differing_paths)
                detail = unexpected[0] if unexpected else stale[0] if stale else "empty authorization"
                raise ValueError(f"unknown or unclassified shipping change: {detail}")
            if not bool(state.get("source_changed_since_candidate", manifest.get("sourceChangedSinceCandidate", False))) or not bool(state.get("rebuild_required", manifest.get("rebuildRequired", False))):
                raise ValueError("classified shipping change requires sourceChangedSinceCandidate and rebuildRequired")
        elif candidate_shipping != live_shipping:
            raise ValueError("shipping-input identity differs despite identical deterministic rows")
    elif candidate_shipping != live_shipping:
        raise ValueError("shipping-input identity cannot be validated without deterministic shipping rows")
    source_changed = bool(state.get("source_changed_since_candidate", manifest.get("sourceChangedSinceCandidate", False)))
    source_identity = state.get("source_identity_matches_candidate")
    if source_identity is not None and not isinstance(source_identity, bool):
        raise ValueError("sourceIdentityMatchesCandidate must be a JSON boolean")
    rows_differ = bool(differing)
    identity_differ = rows_differ or candidate_shipping != live_shipping
    if source_identity is not None and source_identity != (not identity_differ):
        raise ValueError("source identity authority contradicts deterministic shipping rows")
    if source_changed != identity_differ:
        raise ValueError("sourceChangedSinceCandidate contradicts shipping-input identity")
    return {"candidateShippingInputIdentity": candidate_shipping, "liveShippingInputIdentity": live_shipping, "shippingRowsDiffer": identity_differ}


def _canonical(state: dict[str, Any], manifest: dict[str, Any], root: Path) -> dict[str, Any]:
    release = str(state.get("releaseFingerprintId") or manifest.get("releaseFingerprintId") or "")
    tooling = str(state.get("toolingFingerprintId") or manifest.get("toolingFingerprintId") or "")
    version = str(state.get("release_version") or manifest.get("releaseVersion") or "")
    installer = str(state.get("installer_version") or manifest.get("installerVersion") or "")
    repository_head = str(state.get("repository_head") or manifest.get("repositoryHead") or state.get("git_commit") or manifest.get("gitCommit") or "")
    candidate_commit = str(state.get("candidate_git_commit") or manifest.get("candidateGitCommit") or "")
    if not release or not tooling or not version or not installer or not repository_head or not candidate_commit:
        raise ValueError("Canonical finalization state is missing version or fingerprint identity")
    if any(not re.fullmatch(r"[0-9a-fA-F]{64}", value) or value.lower() == "0" * 64 for value in (release, tooling)):
        raise ValueError("Canonical release/tooling fingerprint identity is malformed")
    if state.get("repository_head") and str(state["repository_head"]) != repository_head:
        raise ValueError("finalization-state.json.repository_head disagrees with repository HEAD identity")
    if state.get("git_commit") and str(state["git_commit"]) != repository_head:
        raise ValueError("finalization-state.json.git_commit disagrees with repository HEAD identity")
    if state.get("candidate_git_commit") and str(state["candidate_git_commit"]) != candidate_commit:
        raise ValueError("finalization-state.json.candidate_git_commit disagrees with candidate identity")
    if manifest.get("repositoryHead") and str(manifest["repositoryHead"]) != repository_head:
        raise ValueError("final-artifact-hashes.json.repositoryHead disagrees with repository HEAD identity")
    if manifest.get("gitCommit") and str(manifest["gitCommit"]) != repository_head:
        raise ValueError("final-artifact-hashes.json.gitCommit disagrees with repository HEAD identity")
    if manifest.get("candidateGitCommit") and str(manifest["candidateGitCommit"]) != candidate_commit:
        raise ValueError("final-artifact-hashes.json.candidateGitCommit disagrees with candidate identity")
    if release != str(manifest.get("releaseFingerprintId") or ""):
        raise ValueError("finalization-state.json and final-artifact-hashes.json disagree on releaseFingerprintId")
    if tooling != str(manifest.get("toolingFingerprintId") or ""):
        raise ValueError("finalization-state.json and final-artifact-hashes.json disagree on toolingFingerprintId")
    source_identity = state.get("source_identity_matches_candidate")
    artifact_identity = state.get("artifact_tuple_matches_candidate")
    build_current = state.get("candidate_build_current")
    if source_identity is None:
        source_identity = not bool(state.get("source_changed_since_candidate", manifest.get("sourceChangedSinceCandidate", False)))
    if artifact_identity is None:
        artifact_identity = bool(state.get("candidate_is_current", manifest.get("candidateIsCurrent", False)))
    if build_current is None:
        build_current = bool(state.get("candidate_is_current", manifest.get("candidateIsCurrent", False)))
    required = {
        "sourceChangedSinceCandidate": state.get("source_changed_since_candidate"),
        "rebuildRequired": state.get("rebuild_required"),
        "candidateIsCurrent": state.get("candidate_is_current"),
        "sourceIdentityMatchesCandidate": source_identity,
        "artifactTupleMatchesCandidate": artifact_identity,
        "candidateBuildCurrent": build_current,
        "validationEvidenceCurrent": state.get("validation_evidence_current", manifest.get("validationEvidenceCurrent", False)),
        "fullReleasePassed": state.get("full_release_passed", manifest.get("fullReleasePassed", False)),
        "physicalSurrogateCertificationCurrent": state.get("physical_surrogate_certification_current", manifest.get("physicalSurrogateCertificationCurrent", False)),
        "internalPromotionAllowed": state.get("internal_promotion_allowed", manifest.get("internalPromotionAllowed", False)),
        "publicPromotionAllowed": state.get("public_promotion_allowed", manifest.get("publicPromotionAllowed", False)),
    }
    for name, value in required.items():
        if value is None:
            value = manifest.get(name)
        _bool(value, name, "canonical")
        required[name] = value
    if required["rebuildRequired"] and required["candidateBuildCurrent"]:
        raise ValueError("Canonical state cannot require a rebuild while candidateBuildCurrent is true")
    if required["candidateIsCurrent"] != (required["sourceIdentityMatchesCandidate"] and required["artifactTupleMatchesCandidate"]):
        raise ValueError("candidateIsCurrent must be derived from source and artifact identity")
    if required["fullReleasePassed"] and not required["validationEvidenceCurrent"]:
        raise ValueError("fullReleasePassed requires current validation evidence")
    if required["internalPromotionAllowed"] and not required["fullReleasePassed"]:
        raise ValueError("internalPromotionAllowed requires a passing FullRelease")
    if required["publicPromotionAllowed"] and (not required["internalPromotionAllowed"] or str(state.get("signing_state", manifest.get("signingState", ""))).upper().startswith("NOT SIGNED")):
        raise ValueError("publicPromotionAllowed requires internal promotion and signing")
    production = state.get("production_safety")
    if not isinstance(production, dict):
        raise ValueError("Canonical finalization state is missing production_safety")
    production_unchanged = production.get("production_unchanged")
    _bool(production_unchanged, "production_unchanged", "canonical.production_safety")
    touched = production.get("mulattotechsurface_touched", False)
    _bool(touched, "mulattotechsurface_touched", "canonical.production_safety")
    gates = state.get("gates")
    if not isinstance(gates, dict):
        raise ValueError("Canonical finalization state is missing gates")
    artifact_rows = _artifact_rows(state, manifest)
    expected_artifacts: dict[str, dict[str, Any]] = {}
    for canonical_name, aliases in ARTIFACT_ALIASES.items():
        row = next((artifact_rows[a] for a in aliases if a in artifact_rows), None)
        if not row or not str(row.get("sha256") or ""):
            raise ValueError(f"Canonical artifact hash is missing: {canonical_name}")
        state_row = next((state.get("candidate", {}).get(alias) for alias in aliases if isinstance(state.get("candidate"), dict) and isinstance(state["candidate"].get(alias), dict)), None)
        manifest_row = next((item for item in manifest.get("artifacts", []) if isinstance(item, dict) and str(item.get("name") or "").lower().replace("-", "_") in {alias.lower().replace("-", "_") for alias in aliases}), None)
        if isinstance(state_row, dict) and isinstance(manifest_row, dict):
            if str(state_row.get("sha256") or "").lower() != str(manifest_row.get("sha256") or "").lower() or int(state_row.get("bytes", -1)) != int(manifest_row.get("bytes", -2)):
                raise ValueError(f"state and artifact manifest disagree on {canonical_name} tuple")
        expected_artifacts[canonical_name] = row
        artifact_path = root / str(row.get("path") or "")
        if artifact_path.is_file():
            actual = _sha256(artifact_path)
            if actual.lower() != str(row["sha256"]).lower():
                raise ValueError(f"Canonical artifact hash does not match bytes: {artifact_path}")
    return {
        "releaseFingerprintId": release,
        "toolingFingerprintId": tooling,
        "releaseVersion": version,
        "installerVersion": installer,
        "repositoryHead": repository_head,
        "candidateGitCommit": candidate_commit,
        "gitCommit": repository_head,
        **required,
        "signingState": state.get("signing_state", manifest.get("signingState", "")),
        "releaseStatus": state.get("release_status", manifest.get("releaseStatus", "BLOCKED")),
        "productionUnchanged": production_unchanged,
        "mulattotechsurfaceTouched": touched,
        "gates": gates,
        "artifacts": expected_artifacts,
    }


def _artifact_name(key: str) -> str | None:
    lower = key.lower().replace("-", "_")
    for canonical, aliases in ARTIFACT_ALIASES.items():
        if lower in {a.lower().replace("-", "_") for a in aliases}:
            return canonical
    return None


def _validate_fingerprint_files(root: Path, expected: dict[str, Any]) -> list[Path]:
    """Validate current schema-v2 identity files and their exact artifact tuple.

    Schema 1 remains parseable as historical audit evidence, but a file named as
    the current release/tooling identity may never silently promote it.
    """
    checked: list[Path] = []
    release_path = root / "outputs" / "release-fingerprint.json"
    if release_path.is_file():
        release = _load(release_path)
        if not isinstance(release, dict) or release.get("schemaVersion") not in (1, 2):
            raise ValueError("Current release fingerprint has an unsupported schema")
        if release.get("schemaVersion") != 2:
            raise ValueError("Current release fingerprint must use schemaVersion 2; schema 1 is historical only")
        if str(release.get("releaseFingerprintId") or "") != expected["releaseFingerprintId"]:
            raise ValueError("outputs/release-fingerprint.json is stale")
        if _release_id(release) != str(release.get("releaseFingerprintId") or "").lower():
            raise ValueError("outputs/release-fingerprint.json releaseFingerprintId does not match canonical rows")
        tooling = release.get("toolingFingerprint")
        if not isinstance(tooling, dict) or str(tooling.get("toolingFingerprintId") or "") != expected["toolingFingerprintId"]:
            raise ValueError("outputs/release-fingerprint.json has a stale tooling fingerprint")
        rows = release.get("artifacts")
        if not isinstance(rows, list):
            raise ValueError("Current release fingerprint is missing its artifact tuple")
        by_name = {_artifact_name(str(row.get("name") or "")): row for row in rows if isinstance(row, dict)}
        for name, canonical in expected["artifacts"].items():
            row = by_name.get(name)
            if not row or str(row.get("sha256") or "").lower() != str(canonical["sha256"]).lower() or int(row.get("bytes", -1)) != int(canonical.get("bytes", -2)):
                raise ValueError(f"outputs/release-fingerprint.json has a stale {name} artifact tuple")
        shipping = _shipping_rows(release.get("shippingInputs"))
        _validate_row_shape(shipping, "outputs/release-fingerprint.json shipping rows")
        release_shipping_identity = _shipping_identity(
            shipping,
            release.get("shippingModeContract") or {},
            str(release.get("devfleetVersion") or ""),
            str(release.get("installerVersion") or ""),
        )
        if release_shipping_identity not in {
            str(expected.get("liveShippingInputIdentity") or "").lower(),
            str(expected.get("candidateShippingInputIdentity") or "").lower(),
        }:
            raise ValueError("outputs/release-fingerprint.json shipping identity is not bound to the current tuple")
        for (root_name, relative), row in shipping.items():
            path = root / root_name / relative
            if not path.is_file() or path.stat().st_size != row["bytes"] or _sha256(path) != row["sha256"]:
                raise ValueError(f"outputs/release-fingerprint.json shipping row does not match bytes: {root_name}/{relative}")
        checked.append(release_path)

    tooling_path = root / "outputs" / "tooling-fingerprint-current.json"
    if tooling_path.is_file():
        tooling = _load(tooling_path)
        if not isinstance(tooling, dict) or tooling.get("schemaVersion") != 2:
            raise ValueError("tooling-fingerprint-current.json must use current-record schemaVersion 2")
        if tooling.get("releaseFingerprintSchemaVersion") != 2:
            raise ValueError("tooling-fingerprint-current.json is not bound to release fingerprint schema 2")
        if str(tooling.get("releaseFingerprintId") or "") != expected["releaseFingerprintId"] or str(tooling.get("toolingFingerprintId") or "") != expected["toolingFingerprintId"]:
            raise ValueError("tooling-fingerprint-current.json is stale")
        rows = tooling.get("artifacts")
        if not isinstance(rows, list):
            raise ValueError("tooling-fingerprint-current.json is missing its current artifact tuple")
        by_name = {_artifact_name(str(row.get("name") or "")): row for row in rows if isinstance(row, dict)}
        for name, canonical in expected["artifacts"].items():
            row = by_name.get(name)
            if not row or str(row.get("sha256") or "").lower() != str(canonical["sha256"]).lower() or int(row.get("bytes", -1)) != int(canonical.get("bytes", -2)):
                raise ValueError(f"tooling-fingerprint-current.json has a stale {name} artifact tuple")
        checked.append(tooling_path)
    return checked


def _validate_record(location: str, record: dict[str, Any], expected: dict[str, Any]) -> None:
    if record.get("historical") is True:
        return
    candidate_markers = {
        "releaseFingerprintId",
        "toolingFingerprintId",
        "candidateFingerprint",
        "candidateIsCurrent",
        "sourceIdentityMatchesCandidate",
        "artifactTupleMatchesCandidate",
        "candidateBuildCurrent",
        "validationEvidenceCurrent",
        "fullReleasePassed",
        "physicalSurrogateCertificationCurrent",
        "internalPromotionAllowed",
        "publicPromotionAllowed",
        "sourceChangedSinceCandidate",
        "rebuildRequired",
        "productionUnchanged",
        "production_unchanged",
        "mulattotechsurfaceTouched",
        "mulattotechsurface_touched",
        "candidateVersion",
        "releaseVersion",
        "installerVersion",
        "artifacts",
        "candidate",
        "gates",
        "currentCandidateGates",
    }
    if not candidate_markers.intersection(record):
        return
    for key in ("releaseFingerprintId", "candidateFingerprint"):
        if key in record and str(record[key]) != expected["releaseFingerprintId"]:
            raise ValueError(f"{location}.{key} is stale: {record[key]}")
    candidate_context = ".candidate" in location or location.endswith("CURRENT-CANDIDATE.json")
    for key in ("gitCommit", "git_commit"):
        if key in record and str(record[key]) != (expected["candidateGitCommit"] if candidate_context else expected["repositoryHead"]):
            raise ValueError(f"{location}.{key} is stale")
    for key in ("candidateGitCommit", "candidate_git_commit", "candidateCommit", "candidate_commit"):
        if key in record and str(record[key]) != expected["candidateGitCommit"]:
            raise ValueError(f"{location}.{key} is stale")
    if "toolingFingerprintId" in record and str(record["toolingFingerprintId"]) != expected["toolingFingerprintId"]:
        raise ValueError(f"{location}.toolingFingerprintId is stale")
    for key in ("repositoryHead", "repository_head"):
        if key in record and str(record[key]) != expected["repositoryHead"]:
            raise ValueError(f"{location}.{key} is stale")
    for key in ("shippingInputIdentity", "shipping_input_identity"):
        if key in record:
            expected_shipping = expected.get("liveShippingInputIdentity", expected.get("candidateShippingInputIdentity"))
            if str(record[key]).lower() not in {str(expected_shipping).lower(), str(expected.get("candidateShippingInputIdentity")).lower()}:
                raise ValueError(f"{location}.{key} is stale")
    if "candidateShippingInputIdentity" in record and str(record["candidateShippingInputIdentity"]).lower() != str(expected["candidateShippingInputIdentity"]).lower():
        raise ValueError(f"{location}.candidateShippingInputIdentity is stale")
    for key, expected_key in (("candidateVersion", "releaseVersion"), ("releaseVersion", "releaseVersion"), ("installerVersion", "installerVersion")):
        if key in record and str(record[key]) != expected[expected_key]:
            raise ValueError(f"{location}.{key} disagrees with current candidate")
    for key, expected_key in (("candidateIsCurrent", "candidateIsCurrent"), ("sourceChangedSinceCandidate", "sourceChangedSinceCandidate"), ("rebuildRequired", "rebuildRequired")):
        if key in record and _bool(record[key], key, location) != expected[expected_key]:
            raise ValueError(f"{location}.{key} disagrees with current candidate")
    for key in ("sourceIdentityMatchesCandidate", "artifactTupleMatchesCandidate", "candidateBuildCurrent", "validationEvidenceCurrent", "fullReleasePassed", "physicalSurrogateCertificationCurrent", "internalPromotionAllowed", "publicPromotionAllowed"):
        if key in record and _bool(record[key], key, location) != expected[key]:
            raise ValueError(f"{location}.{key} disagrees with current candidate")
    for key in ("productionUnchanged", "production_unchanged"):
        if key in record and _bool(record[key], key, location) != expected["productionUnchanged"]:
            raise ValueError(f"{location}.{key} disagrees with production safety state")
    for key in ("mulattotechsurfaceTouched", "mulattotechsurface_touched"):
        if key in record and _bool(record[key], key, location) != expected["mulattotechsurfaceTouched"]:
            raise ValueError(f"{location}.{key} disagrees with MulattoTechSurface safety state")
    for container_key in ("artifacts", "candidate"):
        container = record.get(container_key)
        if not isinstance(container, dict):
            continue
        for key, row in container.items():
            if not isinstance(row, dict) or "sha256" not in row:
                continue
            name = _artifact_name(str(key))
            if name and str(row["sha256"]).lower() != str(expected["artifacts"][name]["sha256"]).lower():
                raise ValueError(f"{location}.{container_key}.{key}.sha256 is stale")
    for key in ("currentCandidateGates", "gates"):
        gates = record.get(key)
        if not isinstance(gates, dict):
            continue
        for gate, value in gates.items():
            if gate in expected["gates"] and str(value) != str(expected["gates"][gate]):
                raise ValueError(f"{location}.{key}.{gate} disagrees with current gate status")


def validate_root(root: Path, mode: str = "release") -> dict[str, Any]:
    if mode not in {"diagnostic", "release"}:
        raise ValueError("validator mode must be diagnostic or release")
    root = root.resolve()
    state_path = root / "finalization-state.json"
    manifest_path = root / "outputs" / "final-artifact-hashes.json"
    if not state_path.is_file() or not manifest_path.is_file():
        raise ValueError("Bundle is missing finalization-state.json or outputs/final-artifact-hashes.json")
    state = _load(state_path)
    manifest = _load(manifest_path)
    if not isinstance(state, dict) or not isinstance(manifest, dict):
        raise ValueError("Canonical state and artifact manifest must be JSON objects")
    candidate_path = root / "CURRENT-CANDIDATE.json"
    candidate = _load(candidate_path) if candidate_path.is_file() else {}
    if not isinstance(candidate, dict):
        raise ValueError("CURRENT-CANDIDATE.json must be a JSON object")
    audit_manifest = root / "AUDIT-MANIFEST.json"
    bundle_manifest = _load(audit_manifest) if audit_manifest.is_file() else manifest
    if not isinstance(bundle_manifest, dict):
        raise ValueError("AUDIT-MANIFEST.json must be a JSON object")
    failed_snapshot_path = root / Path(*FAILED_ATTEMPT_SNAPSHOT.split("/"))
    if failed_snapshot_path.is_file() and mode == "release":
        raise ValueError("release mode rejects failed replacement-attempt evidence")
    if mode == "diagnostic":
        if failed_snapshot_path.is_file():
            failed = _validate_failed_attempt_freeze(root, state, bundle_manifest, candidate)
            return {"status": "PASS_WITH_BLOCKER", "bundleMode": "diagnostic", "blockerCode": FAILED_ATTEMPT_BLOCKER, "releaseEligible": False, "candidateIsCurrent": False, "sourceChangedSinceCandidate": True, "rebuildRequired": True, **failed}
        candidate_id = str(state.get("candidate_git_commit") or state.get("candidateGitCommit") or candidate.get("candidateCommit") or "").lower()
        if candidate_id == FAILED_ATTEMPT_COMMIT:
            raise ValueError("failed replacement-attempt snapshot is mandatory for this diagnostic candidate")
        if candidate_id == HISTORICAL_CANDIDATE:
            historical = _historical_provenance(root, state, bundle_manifest, candidate)
            flags = {"candidateIsCurrent": False, "sourceChangedSinceCandidate": True, "rebuildRequired": True}
        else:
            # A future coherent candidate may be reviewed diagnostically while
            # expensive proof is still pending.  It must still pass every
            # current identity/authority check, but diagnostic output can
            # never become a promotion decision.
            expected = _canonical(state, manifest, root)
            expected.update(_validate_split_identity(root, state, bundle_manifest, candidate))
            historical = {"candidateShippingInputIdentity": expected["candidateShippingInputIdentity"], "provenanceCommit": candidate_id}
            flags = {key: expected[key] for key in ("candidateIsCurrent", "sourceChangedSinceCandidate", "rebuildRequired")}
        # Diagnostic validation is deliberately a terminal, non-release
        # result.  Do not run the current-candidate authority walk here: those
        # fields describe the invalidated candidate and are expected to be
        # stale relative to the live worktree.  The historical verifier above
        # has independently checked every identity it is allowed to accept.
        return {"status": "PASS_WITH_BLOCKER", "bundleMode": "diagnostic", "blockerCode": "HISTORICAL_CANDIDATE_REBUILD_REQUIRED" if candidate_id == HISTORICAL_CANDIDATE else "DIAGNOSTIC_PROOF_PENDING", "releaseEligible": False, **flags, **historical}
    if str(candidate.get("historicalProvenance", {}).get("candidateCommit") if isinstance(candidate.get("historicalProvenance"), dict) else "").lower() == HISTORICAL_CANDIDATE:
        raise ValueError("release mode rejects historical 2739/f334 diagnostic provenance")
    expected = _canonical(state, manifest, root)
    expected.update(_validate_split_identity(root, state, bundle_manifest, candidate))
    files = [state_path, manifest_path]
    if candidate_path.is_file():
        files.append(candidate_path)
    if audit_manifest.is_file():
        files.append(audit_manifest)
    files.extend(_validate_fingerprint_files(root, expected))
    audit = root / "audit"
    if audit.is_dir():
        # The review bundle includes the audit directory's direct evidence
        # files.  Durable per-run evidence is independently scoped and is not
        # silently promoted into a bundle by this validator.
        files.extend(sorted(audit.glob("*.json")))
    for path in files:
        value = _load(path)
        if isinstance(value, dict) and (value.get("historical") is True or str(value.get("schema") or "").startswith("devfleet.pre-")):
            continue
        for location, record in _walk(value, path.relative_to(root).as_posix()):
            _validate_record(location, record, expected)
    return {"status": "PASS", "filesChecked": len(files), "currentReleaseFingerprintId": expected["releaseFingerprintId"], "currentToolingFingerprintId": expected["toolingFingerprintId"]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--mode", choices=("diagnostic", "release"), default="release")
    args = parser.parse_args()
    try:
        result = validate_root(args.root, args.mode)
    except ValueError as exc:
        print(f"AUDIT COHERENCE FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/tools/verify_package.py

SHA256: 24d74c58ed2d13099032cbc4a2ef46a03c819da82b7505762ff2068ed8a1ea9b | Bytes: 21852 | Git mode: 100644

```
#!/usr/bin/env python3
"""Offline, read-only verification for a DevFleet package or release archive."""
from __future__ import annotations

import hashlib
import json
import os
import py_compile
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import zipfile
from pathlib import Path, PurePosixPath

import jinja2
import yaml
from hook_modes import executable_template_hook_closure, executable_template_hooks, hook_mode_manifest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
TRANSIENT_DIRS = {".git", ".pytest_cache", ".test-runtime", "__pycache__", "runtime-migrations"}


def is_transient_part(part: str) -> bool:
    return part in TRANSIENT_DIRS or part.startswith(".venv")
CHECKSUM_MANIFEST = "CHECKSUMS.sha256"
REQUIRED = [
    "VERSION", "README-FIRST.md", "Upgrade-DevFleet.ps1",
    "DevFleet-v1.1.0-MIGRATION.md", "DevFleet-v1.1.0-VALIDATION.md",
    "DevFleet-v1.1.0-FILE-CHANGES.md", "BASELINE-v1.0.0-FILES.txt",
    "config/devfleet.config.json", "config/ollama-profiles.json",
    "client/Configure-SSH.ps1", "client/Configure-DockerContext.ps1",
    "client/Configure-VSCode.ps1", "windows/Migrate-Config.ps1",
    "windows/Configure-Ollama.ps1", "windows/Set-DevFleetDockerMode.ps1",
    "windows/Test-Ollama.ps1", "linux/bootstrap-compute.sh",
    "linux/devfleet-switch-docker-mode", "app/devfleet/main.py",
    "app/devfleet/analyzer.py", "docs/08-DEVELOPMENT-PROFILES.md",
    "docs/09-LANGUAGE-SELECTION.md", "docs/10-OLLAMA-AND-GPU.md",
    "docs/11-REMOTE-VSCODE.md", "docs/12-UPGRADING-FROM-1.0.0.md",
    "docs/13-PERFORMANCE-TUNING.md",
]
CORE = {"generic", "python", "python-fastapi", "node", "typescript-node",
        "typescript-next", "go-service", "dotnet-service", "java-spring", "rust-service"}


DEFAULT_EXTERNAL_TIMEOUT_SECONDS = 120
DEFAULT_EXTERNAL_OUTPUT_LIMIT = 2 * 1024 * 1024


def _terminate_process_tree(process: subprocess.Popen[bytes]) -> None:
    """Terminate one external hook and descendants without relying on shell quoting."""
    if process.poll() is not None:
        return
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=10,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass
    else:
        try:
            import signal

            os.killpg(process.pid, signal.SIGKILL)
        except (OSError, ProcessLookupError):
            pass
    try:
        process.kill()
    except OSError:
        pass


def run_bounded(
    args: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    timeout: float = DEFAULT_EXTERNAL_TIMEOUT_SECONDS,
    output_limit: int = DEFAULT_EXTERNAL_OUTPUT_LIMIT,
    label: str = "external hook",
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    """Run a package hook with a deadline, process-tree kill, and bounded output."""
    if output_limit <= 0 or timeout <= 0:
        raise ValueError("run_bounded limits must be positive")
    creationflags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0) if os.name == "nt" else 0
    process = subprocess.Popen(
        args,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=os.name != "nt",
        creationflags=creationflags,
    )
    captured: dict[str, bytearray] = {"stdout": bytearray(), "stderr": bytearray()}
    overflow = threading.Event()

    def drain(name: str, stream: object) -> None:
        assert hasattr(stream, "read")
        reader = stream  # type: ignore[assignment]
        while True:
            chunk = reader.read(65536)
            if not chunk:
                return
            remaining = output_limit - len(captured[name])
            if len(chunk) > remaining:
                if remaining > 0:
                    captured[name].extend(chunk[:remaining])
                overflow.set()
                return
            captured[name].extend(chunk)

    threads = [
        threading.Thread(target=drain, args=(name, stream), daemon=True)
        for name, stream in (("stdout", process.stdout), ("stderr", process.stderr))
    ]
    for thread in threads:
        thread.start()
    deadline = time.monotonic() + timeout
    timed_out = False
    while process.poll() is None:
        if overflow.is_set():
            _terminate_process_tree(process)
            break
        if time.monotonic() >= deadline:
            timed_out = True
            _terminate_process_tree(process)
            break
        time.sleep(0.02)
    if timed_out:
        reason = f"{label} exceeded {timeout:g}s timeout"
    elif overflow.is_set():
        reason = f"{label} exceeded {output_limit} byte output limit"
    else:
        reason = ""
    if reason:
        process.wait(timeout=10)
    for thread in threads:
        thread.join(timeout=10)
    result = subprocess.CompletedProcess(
        args,
        process.returncode,
        captured["stdout"].decode(errors="replace"),
        captured["stderr"].decode(errors="replace"),
    )
    if reason:
        raise RuntimeError(f"{reason}; stdout/stderr excerpt: {result.stdout[-1000:]} {result.stderr[-1000:]}")
    if check and result.returncode:
        raise subprocess.CalledProcessError(result.returncode, args, result.stdout, result.stderr)
    return result


def is_transient(path: Path, root: Path = ROOT) -> bool:
    """Return whether a path belongs to generated/test state excluded from a package."""
    return any(is_transient_part(part) for part in path.relative_to(root).parts)


def package_files(root: Path = ROOT) -> set[str]:
    return {
        p.relative_to(root).as_posix()
        for p in root.rglob("*")
        if p.is_file() and not is_transient(p, root)
    }


def require_files(root: Path = ROOT) -> None:
    for rel in REQUIRED:
        assert (root / rel).is_file(), f"missing {rel}"


def parse_data(root: Path = ROOT) -> None:
    for rel in package_files(root):
        p = root / rel
        if p.suffix == ".json":
            json.loads(p.read_text(encoding="utf-8"))
    vscode = root / "client/vscode-settings.jsonc"
    json.loads(re.sub(r"(?m)^\s*//.*$", "", vscode.read_text(encoding="utf-8")))
    for p in list((root / "cloud-init").glob("*.yaml")) + list((root / "templates").glob("*/compose.yaml")):
        assert isinstance(yaml.safe_load(p.read_text(encoding="utf-8")), dict), f"YAML root is not mapping: {p}"


def compile_python_jinja(root: Path = ROOT) -> None:
    with tempfile.TemporaryDirectory() as td:
        cache = Path(td)
        for rel in package_files(root):
            p = root / rel
            if p.suffix == ".py":
                py_compile.compile(str(p), cfile=str(cache / (hashlib.sha256(rel.encode()).hexdigest() + ".pyc")), doraise=True)
    jinja2.Environment().parse((root / "app/templates/index.html").read_text(encoding="utf-8"))


def bash_available() -> bool:
    try:
        return shutil.which("bash") is not None and run_bounded(["bash", "-c", "exit 0"], timeout=5, label="bash probe", check=False).returncode == 0
    except (OSError, RuntimeError):
        return False


def bash_syntax(root: Path = ROOT) -> None:
    if not bash_available():
        return
    for rel in package_files(root):
        p = root / rel
        if p.suffix == ".sh" or (p.parts and p.parts[-1] == "devfleet-switch-docker-mode"):
            run_bounded(["bash", "-n", str(p)], label=f"bash syntax check {p}")


def linux_executable_hooks(root: Path = ROOT) -> None:
    """Require every command-referenced template hook to be exactly 0755."""
    hooks = executable_template_hooks(root)
    assert hooks, "no executable template hooks were derived from metadata"
    for rel in sorted(hooks):
        p = root / rel
        assert p.is_file(), f"trusted hook is not a regular file: {p}"
        if os.name != "nt":
            assert p.stat().st_mode & 0o777 == 0o755, f"template hook mode is not 0755: {p}"
        first = p.read_text(encoding="utf-8").splitlines()[0] if p.stat().st_size else ""
        assert first == "#!/usr/bin/env bash", f"trusted hook has invalid shebang: {p}"


def powershell_lexical(root: Path = ROOT) -> None:
    pairs = {"(": ")", "[": "]", "{": "}"}
    for rel in package_files(root):
        p = root / rel
        if p.suffix not in {".ps1", ".psm1"}:
            continue
        t = p.read_text(encoding="utf-8-sig")
        stack: list[str] = []
        quote = here = None
        i = 0
        line = True
        while i < len(t):
            if here:
                end = "'@" if here == "'" else '"@'
                if line and t.startswith(end, i):
                    here = None; i += 2; line = False; continue
                line = t[i] == "\n"; i += 1; continue
            c = t[i]
            if quote:
                if c == "`": i += 2; continue
                if c == quote:
                    if quote == "'" and i + 1 < len(t) and t[i + 1] == "'": i += 2; continue
                    quote = None
                line = c == "\n"; i += 1; continue
            if line and t.startswith("@'", i): here = "'"; i += 2; line = False; continue
            if line and t.startswith('@"', i): here = '"'; i += 2; line = False; continue
            if c == "#":
                while i < len(t) and t[i] != "\n": i += 1
                line = True; continue
            if c in "'\"": quote = c
            elif c in pairs: stack.append(c)
            elif c in pairs.values(): assert stack and pairs[stack.pop()] == c, f"unbalanced {c} in {p}"
            line = c == "\n"; i += 1
        assert not stack and quote is None and here is None, f"unbalanced PowerShell structure: {p}"


def template_smoke(root: Path = ROOT) -> None:
    if not bash_available():
        return
    for source in (root / "templates").glob("*"):
        if not source.is_dir() or is_transient(source, root):
            continue
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "demo"; shutil.copytree(source, dest)
            for p in dest.rglob("*"):
                if p.is_file() and not p.is_symlink():
                    try:
                        p.write_text(p.read_text().replace("__PROJECT_SLUG__", "demo-project").replace("__PROJECT_NAME__", "Demo Project").replace("__PROJECT_PROFILE__", "balanced").replace("__PROJECT_LANGUAGE__", "test").replace("__PROJECT_FRAMEWORK__", "test").replace("__OLLAMA_BASE_URL__", "http://127.0.0.1:11434/v1").replace("__OLLAMA_MODEL__", "test-model"))
                    except UnicodeDecodeError:
                        pass
            meta = json.loads((dest / ".devfleet/template.json").read_text())
            smoke = ".devfleet/smoke-test.sh"
            if (dest / smoke).is_file():
                run_bounded(["bash", str(dest / smoke)], cwd=dest, label=f"template smoke {source.name}")
            if source.name in CORE:
                for key in ("bootstrap_command", "format_command", "lint_command", "test_command", "health_command"):
                    assert meta.get(key), f"{source.name} missing {key}"


def codexpro_guard_tests(root: Path = ROOT) -> None:
    """Exercise the production /workspaces guard without running CodexPro."""
    if not bash_available():
        print("CodexPro guard tests skipped: POSIX bash is unavailable.")
        return
    hook = root / "templates/generic/.devfleet/codexpro-bootstrap.sh"
    with tempfile.TemporaryDirectory() as outside:
        refused = run_bounded(["bash", str(hook)], cwd=Path(outside), label="CodexPro guard refusal", check=False)
        assert refused.returncode == 2, "CodexPro hook must refuse a non-/workspaces project root"
        assert "must be under /workspaces" in refused.stderr
    workspaces = Path("/workspaces")
    try:
        workspaces.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=workspaces) as valid:
            accepted = run_bounded(["bash", str(hook)], cwd=Path(valid), label="CodexPro guard success", check=False)
            assert accepted.returncode == 0, accepted.stderr
    except (OSError, PermissionError):
        print("CodexPro success-path test skipped: /workspaces is unavailable.")


def fastapi_smoke(root: Path = ROOT) -> None:
    try:
        import fastapi  # noqa: F401
    except ModuleNotFoundError as exc:
        print(f"FastAPI smoke skipped: verification environment does not provide runtime dependency {exc.name}.")
        return
    except SystemError as exc:
        if "pydantic-core version" in str(exc):
            print("FastAPI smoke skipped: local Python dependency set has an existing pydantic/pydantic-core mismatch.")
            return
        raise
    with tempfile.TemporaryDirectory() as td:
        b = Path(td); [(b / d).mkdir() for d in ("workspaces", "quarantine", "runtime", "cache")]
        cfg = {"node_name": "verify", "node_role": "primary", "friendly_name": "CodexDevVM", "portal_port": 8787, "workspaces": str(b / "workspaces"), "quarantine": str(b / "quarantine"), "peer_file": str(b / "peer.json"), "runtime_root": str(b / "runtime"), "cache_root": str(b / "cache"), "development_profile": "balanced", "docker_mode": "rootless", "ollama_base_url": "", "ollama_model": "", "ollama_profile": "stable-interactive", "require_tailscale": False, "public_binding_allowed": True}
        (b / "config.json").write_text(json.dumps(cfg)); (b / "peer.json").write_text("{}")
        env = os.environ.copy(); env.update({"PYTHONPATH": str(root / "app"), "DEVFLEET_CONFIG_PATH": str(b / "config.json"), "DEVFLEET_STATIC_DIR": str(root / "app/static"), "DEVFLEET_TEMPLATE_DIR": str(root / "app/templates"), "DEVFLEET_ADMIN_USER": "x", "DEVFLEET_ADMIN_PASSWORD": "y", "DEVFLEET_API_TOKEN": "z"})
        code = 'from fastapi.testclient import TestClient;from devfleet.main import app;r=TestClient(app).get("/healthz");assert r.status_code==200 and r.json()["agent_version"]=="' + PACKAGE_VERSION + '"'
        run_bounded([sys.executable, "-c", code], env=env, label="FastAPI smoke")


def verify_checksums(root: Path = ROOT) -> None:
    p = root / CHECKSUM_MANIFEST
    assert p.is_file(), "missing checksum manifest"
    entries: dict[str, str] = {}
    for line in p.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        parts = line.split("  ", 1)
        assert len(parts) == 2 and re.fullmatch(r"[0-9a-fA-F]{64}", parts[0]), f"malformed checksum line: {line}"
        expected, rel = parts; rel = rel.replace("\\", "/")
        assert rel != CHECKSUM_MANIFEST and not is_transient(root / rel, root), f"invalid checksum target: {rel}"
        assert rel not in entries, f"duplicate checksum entry: {rel}"
        target = root / rel
        try:
            target.resolve().relative_to(root.resolve())
        except ValueError:
            raise AssertionError(f"checksum target escapes package root: {rel}")
        assert target.is_file(), f"missing checksum target {rel}"
        actual = hashlib.sha256(target.read_bytes()).hexdigest().lower()
        if actual != expected.lower() and target.is_file():
            # Windows may materialize committed LF text as CRLF. Accept only
            # the exact LF-normalized bytes; content changes still fail.
            raw = target.read_bytes()
            if b"\r" in raw.replace(b"\r\n", b""):
                normalized = None
            else:
                normalized = raw.replace(b"\r\n", b"\n")
            if normalized is not None:
                actual = hashlib.sha256(normalized).hexdigest().lower()
        assert actual == expected.lower(), f"checksum mismatch {rel}"
        entries[rel] = expected.lower()
    eligible = package_files(root) - {CHECKSUM_MANIFEST}
    assert set(entries) == eligible, f"checksum manifest coverage mismatch: missing={sorted(eligible-set(entries))[:10]} extra={sorted(set(entries)-eligible)[:10]}"


def no_empty(root: Path = ROOT) -> None:
    assert not [rel for rel in package_files(root) if (root / rel).stat().st_size == 0 and Path(rel).name != "__init__.py"]


def baseline_preserved(root: Path = ROOT) -> None:
    for rel in (root / "BASELINE-v1.0.0-FILES.txt").read_text(encoding="utf-8").splitlines():
        if rel.strip(): assert (root / rel).exists(), f"v1 baseline path removed: {rel}"


def _safe_member(name: str) -> str:
    normalized = name.replace("\\", "/")
    pure = PurePosixPath(normalized)
    assert normalized and not pure.is_absolute() and ".." not in pure.parts, f"unsafe archive member: {name}"
    assert not any(is_transient_part(part) for part in pure.parts), f"transient archive member: {name}"
    return str(pure)


def _safe_target(dest: Path, name: str) -> Path:
    target = dest / name
    try:
        target.resolve().relative_to(dest.resolve())
    except ValueError:
        raise AssertionError(f"archive member escapes extraction root: {name}")
    return target


def _extract_regular_zip_member(archive: zipfile.ZipFile, info: zipfile.ZipInfo, dest: Path, name: str) -> None:
    target = _safe_target(dest, name)
    target.parent.mkdir(parents=True, exist_ok=True)
    mode = (info.external_attr >> 16) & 0o170000
    assert mode not in (stat.S_IFLNK, stat.S_IFDIR), f"unsupported ZIP entry type: {name}"
    with archive.open(info, "r") as source, target.open("xb") as output:
        shutil.copyfileobj(source, output)
    archived_mode = (info.external_attr >> 16) & 0o777
    if archived_mode and os.name != "nt":
        target