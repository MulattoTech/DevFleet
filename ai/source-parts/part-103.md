# DevFleet source part 103

Full-source UTF-8 byte interval [4743000, 4789500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 85b6d9fb9324996776ddb2f1116389f1d5d38e4aa4dae907c9c474ceeab9add7

<!-- BEGIN SOURCE SLICE -->
rement.marker) if requirement.marker else None
    # Constructing Marker validates the complete expression, and makes the
    # target-environment policy explicit even though all exact lock pins are
    # queried conservatively below.
    if marker:
        Marker(marker)
    return canonicalize_name(requirement.name), version, marker


def lock_requirements(lock: Path) -> list[tuple[str, str, str | None]]:
    parsed = [_requirement_expression(line) for line in _logical_requirement_lines(lock)]
    if not parsed:
        raise ValueError(f"lock contains no exact pinned requirements: {lock}")
    # A compiled lock is the certified dependency set.  Query every exact pin,
    # including platform-marked pins, rather than silently dropping a supported
    # target.  Duplicate name/version rows are queried once.
    unique: list[tuple[str, str, str | None]] = []
    seen: set[tuple[str, str]] = set()
    for package, version, marker in parsed:
        key = (package, version)
        if key not in seen:
            seen.add(key)
            unique.append((package, version, marker))
    return unique


def lock_packages(lock: Path) -> list[tuple[str, str]]:
    return [(package, version) for package, version, _marker in lock_requirements(lock)]


def _score(vulnerability: dict) -> float | None:
    scores: list[float] = []
    for item in vulnerability.get("severity", []) or []:
        raw = str(item.get("score", ""))
        if not raw:
            continue
        try:
            kind = str(item.get("type") or "").upper()
            if raw.startswith("CVSS:2.0/") or kind == "CVSS_V2":
                scores.append(float(CVSS2(raw).scores()[0]))
            elif raw.startswith(("CVSS:3.0/", "CVSS:3.1/")) or kind == "CVSS_V3":
                scores.append(float(CVSS3(raw).scores()[0]))
            elif raw.startswith("CVSS:4.0/") or kind == "CVSS_V4":
                scores.append(float(CVSS4(raw).scores()[0]))
            else:
                # OSV has historically emitted numeric scores for some records;
                # accept only a complete numeric value in the valid CVSS range.
                numeric = float(raw)
                if 0.0 <= numeric <= 10.0:
                    scores.append(numeric)
        except (TypeError, ValueError, IndexError, CVSSError):
            continue
    return max(scores) if scores else None


def _declared_severities(vulnerability: dict) -> list[str]:
    values: list[str] = []
    specific = vulnerability.get("database_specific") or {}
    for value in (specific.get("severity"),):
        if value is not None:
            values.append(str(value).upper())
    for affected in vulnerability.get("affected", []) or []:
        if not isinstance(affected, dict):
            continue
        ecosystem_specific = affected.get("ecosystem_specific") or {}
        if ecosystem_specific.get("severity") is not None:
            values.append(str(ecosystem_specific["severity"]).upper())
    return values


def _severity(vulnerability: dict) -> str:
    declared_values = _declared_severities(vulnerability)
    invalid_declared = [value for value in declared_values if value not in KNOWN_SEVERITIES]
    declared = max(
        (value for value in declared_values if value in KNOWN_SEVERITIES),
        key=lambda value: {"NONE": 0, "LOW": 1, "MEDIUM": 2, "MODERATE": 2, "HIGH": 3, "CRITICAL": 4}[value],
        default="",
    )
    score = _score(vulnerability)
    if score is not None:
        score_label = "CRITICAL" if score >= CRITICAL_SCORE else "HIGH" if score >= HIGH_SCORE else "MEDIUM" if score >= 4.0 else "LOW" if score > 0 else "NONE"
        rank = {"NONE": 0, "LOW": 1, "MEDIUM": 2, "MODERATE": 2, "HIGH": 3, "CRITICAL": 4}
        if rank[score_label] > rank.get(declared, -1):
            declared = score_label
    invalid_vectors = any(
        str(item.get("score") or "").upper().startswith("CVSS:") and _score({"severity": [item]}) is None
        for item in vulnerability.get("severity", []) or []
        if isinstance(item, dict)
    )
    if (invalid_declared or invalid_vectors) and declared not in {"HIGH", "CRITICAL"}:
        return "UNKNOWN"
    if score is not None and score >= CRITICAL_SCORE:
        return "CRITICAL"
    if score is not None and score >= HIGH_SCORE:
        return "HIGH"
    return declared or "UNKNOWN"


def query(package: str, version: str) -> dict:
    body = json.dumps({"package": {"name": package, "ecosystem": "PyPI"}, "version": version}).encode()
    request = urllib.request.Request(OSV_QUERY_URL, data=body, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.load(response)


def run(lock: Path, allowlist: Path) -> dict:
    checked_at = datetime.now(timezone.utc).isoformat()
    lock_bytes = lock.read_bytes()
    allowlist_bytes = allowlist.read_bytes() if allowlist.is_file() else b'{"exceptions": []}'
    allowed = json.loads(allowlist.read_text(encoding="utf-8")) if allowlist.is_file() else {"exceptions": []}
    exceptions = {
        (str(item.get("advisory_id")), str(item.get("package")).lower().replace("_", "-"), str(item.get("affected_version"))): item
        for item in allowed.get("exceptions", [])
        if isinstance(item, dict)
    }
    results: list[dict] = []
    blocking: list[dict] = []
    errors: list[str] = []
    for package, version, marker in lock_requirements(lock):
        try:
            response = query(package, version)
            vulnerabilities = response.get("vulns", []) or []
            advisories = []
            for vulnerability in vulnerabilities:
                advisory_id = str(vulnerability.get("id") or "unknown")
                severity = _severity(vulnerability)
                item = {"id": advisory_id, "severity": severity, "summary": str(vulnerability.get("summary") or "")[:500]}
                advisories.append(item)
                if severity in BLOCKING_SEVERITIES and (advisory_id, package, version) not in exceptions:
                    blocking.append({"package": package, "version": version, **item})
            results.append({"package": package, "version": version, "marker": marker, "query": {"package": {"name": package, "ecosystem": "PyPI"}, "version": version}, "advisories": advisories, "status": "PASS" if not advisories else "ADVISORIES_REVIEWED"})
        except (OSError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            errors.append(f"{package}=={version}: {type(exc).__name__}: {exc}")
            results.append({"package": package, "version": version, "status": "ERROR", "error": str(exc)[:500]})
    status = "BLOCKED" if blocking or errors else "PASS"
    return {
        "schema_version": 2,
        "checker": "DevFleet dependency advisory gate",
        "checker_version": "2.0.0",
        "status": status,
        "source": OSV_QUERY_URL,
        "checked_at": checked_at,
        "lock": str(lock),
        "lock_sha256": hashlib.sha256(lock_bytes).hexdigest(),
        "allowlist": str(allowlist),
        "allowlist_sha256": hashlib.sha256(allowlist_bytes).hexdigest(),
        "target_environment_policy": "query every exact pin in the compiled lock, including platform-marked pins; deduplicate only identical canonical package/version pairs",
        "packages": results,
        "blocking_advisories": blocking,
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--allowlist", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = run(args.lock, args.allowlist)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "packages": len(report["packages"]), "blocking": len(report["blocking_advisories"]), "errors": len(report["errors"])}))
    return 0 if report["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/tools/hook_modes.py

SHA256: 3010bf588f088c9e6d4e956c2127a06abfec78f4875eec3441475383b6e02e54 | Bytes: 5491 | Git mode: 100644

```
"""Single source of truth for executable template hook closure and modes."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
import sys

COMMAND_FIELDS = ("bootstrap_command", "health_command", "test_command", "codexpro_command")
LOCAL_HOOK_RE = re.compile(r"(?<![A-Za-z0-9_./-])(?:\./)?(?P<path>\.devfleet/[A-Za-z0-9._-]+\.sh)(?![A-Za-z0-9_./-])")
ABSOLUTE_HOOK_RE = re.compile(r"(?<![A-Za-z0-9_./-])/(?P<path>(?:[^\s\"']+/)*\.devfleet/[A-Za-z0-9._-]+\.sh)")
LOCALISH_HOOK_RE = re.compile(r"(?<![A-Za-z0-9_])(?P<path>(?:\./)?\.devfleet/[^\s\"'`()]+\.sh)")


@dataclass(frozen=True)
class HookClosure:
    """The complete, validated local executable-script closure for a template."""

    direct: frozenset[str]
    transitive: frozenset[str]

    @property
    def executable(self) -> frozenset[str]:
        return self.direct | self.transitive


def _local_references(text: str, *, origin: Path) -> set[str]:
    """Extract only local .devfleet script references and reject unsafe lookalikes."""
    absolute = ABSOLUTE_HOOK_RE.search(text)
    if absolute:
        raise ValueError(f"absolute external hook reference in {origin}: {absolute.group('path')}")
    for candidate in LOCALISH_HOOK_RE.finditer(text):
        path = candidate.group("path")
        if ".." in Path(path).parts or "/" in path.removeprefix("./.devfleet/"):
            raise ValueError(f"unsafe local hook reference in {origin}: {path}")
    return {match.group("path") for match in LOCAL_HOOK_RE.finditer(text)}


def _resolve_local(root: Path, template_dir: Path, relative: str, *, origin: Path) -> tuple[str, Path]:
    candidate = (template_dir / relative).resolve(strict=False)
    template_root = template_dir.resolve()
    try:
        candidate.relative_to(template_root)
    except ValueError as exc:
        raise ValueError(f"hook reference escapes template root in {origin}: {relative}") from exc
    if candidate.parent != (template_dir / ".devfleet").resolve():
        raise ValueError(f"hook reference is not a local .devfleet script in {origin}: {relative}")
    package_relative = candidate.relative_to(root.resolve()).as_posix()
    return package_relative, candidate


def executable_template_hook_closure(root: Path) -> dict[str, HookClosure]:
    """Discover and validate metadata plus transitive local-script references."""
    result: dict[str, HookClosure] = {}
    for metadata in sorted((root / "templates").glob("*/.devfleet/template.json")):
        data = json.loads(metadata.read_text(encoding="utf-8"))
        template_dir = metadata.parent.parent
        direct: set[str] = set()
        pending: list[tuple[str, Path]] = []
        for field in COMMAND_FIELDS:
            command = data.get(field)
            if not isinstance(command, str):
                continue
            for reference in _local_references(command, origin=metadata):
                package_relative, candidate = _resolve_local(root, template_dir, reference, origin=metadata)
                direct.add(package_relative)
                pending.append((package_relative, candidate))

        all_hooks = set(direct)
        while pending:
            package_relative, script = pending.pop()
            if not script.is_file() or script.is_symlink():
                raise ValueError(f"referenced hook is not a regular file: {package_relative}")
            for reference in _local_references(script.read_text(encoding="utf-8"), origin=script):
                child_relative, child = _resolve_local(root, template_dir, reference, origin=script)
                if child_relative not in all_hooks:
                    all_hooks.add(child_relative)
                    pending.append((child_relative, child))
        missing = [rel for rel in sorted(all_hooks) if not (root / rel).is_file()]
        if missing:
            raise ValueError(f"referenced hook does not exist: {missing[0]}")
        direct_set = frozenset(direct)
        result[template_dir.name] = HookClosure(direct_set, frozenset(all_hooks - direct_set))
    return result


def executable_template_hooks(root: Path) -> set[str]:
    """Return package-relative paths in the complete executable hook closure."""
    return set().union(*(closure.executable for closure in executable_template_hook_closure(root).values()))


def hook_mode_manifest(root: Path) -> dict[str, object]:
    closures = executable_template_hook_closure(root)
    hooks = sorted(set().union(*(closure.executable for closure in closures.values())))
    all_scripts = sorted(
        p.relative_to(root).as_posix()
        for p in (root / "templates").glob("*/.devfleet/*.sh")
        if p.is_file()
    )
    return {
        "executable_by_contract": hooks,
        "count": len(hooks),
        "classification": {
            rel: "executable-by-contract" if rel in hooks else "non-executable-source/helper"
            for rel in all_scripts
        },
        "templates": {
            name: {"direct": sorted(c.direct), "transitive": sorted(c.transitive)}
            for name, c in sorted(closures.items())
        },
    }


def is_executable_template_hook(root: Path, path: Path) -> bool:
    return path.relative_to(root).as_posix() in executable_template_hooks(root)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python hook_modes.py <source-root>")
    print(json.dumps(hook_mode_manifest(Path(sys.argv[1]).resolve()), sort_keys=True))

```


## FILE: source/tools/migrate_config.py

SHA256: 38e5b6be41be5d9a22039b047a5489ab476dce3ea02d9217e3737d3f07e4bdaa | Bytes: 763 | Git mode: 100644

```
#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app'))
from devfleet.configuration import migrate_cluster_config,validate_cluster_config
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--output',type=Path);p.add_argument('--clean-install',action='store_true');p.add_argument('--write',action='store_true');a=p.parse_args();data=json.loads(a.source.read_text());out,changes=migrate_cluster_config(data,clean_install=a.clean_install);validate_cluster_config(out);print(json.dumps({'changes':changes,'configuration':out},indent=2));
if a.write:(a.output or a.source).write_text(json.dumps(out,indent=2)+'\n')

```


## FILE: source/tools/release_fingerprint.py

SHA256: f5440bfaeafb54607fa71d284ec6d63e115fe15e2de6e72bc7f1de644363cf6b | Bytes: 5826 | Git mode: 100644

```
"""Build a deterministic fingerprint for the shipping packaging closure."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

try:
    from hook_modes import executable_template_hooks
except ModuleNotFoundError:  # imported as tools.release_fingerprint in tests
    from .hook_modes import executable_template_hooks


TRANSIENT_PARTS = {
    ".git",
    ".pytest_cache",
    ".test-runtime",
    "__pycache__",
    "bin",
    "obj",
    "outputs",
    "audit",
    "Payload",
}


def is_transient_part(part: str) -> bool:
    return part in TRANSIENT_PARTS or part.startswith(".venv")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _included(path: Path, root: Path) -> bool:
    relative = path.relative_to(root)
    return path.is_file() and not any(is_transient_part(part) for part in relative.parts)


def _entries(root: Path, label: str, *, executable_by_contract: set[str] | frozenset[str] = frozenset()) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for path in sorted(root.rglob("*")):
        if not _included(path, root):
            continue
        relative = path.relative_to(root).as_posix()
        result.append(
            {
                "root": label,
                "path": relative,
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
                # This is the mode written into the canonical TAR/portable
                # payload, never the incidental mode of the checkout host.
                "mode": "0755" if relative in executable_by_contract else "0644",
            }
        )
    return result


def _tooling_fingerprint(source_root: Path) -> dict[str, object]:
    """Fingerprint non-shipping release/audit tooling separately.

    The shipping release identity intentionally excludes repository-level tooling and
    automation so a review-bundle or harness change cannot silently invalidate a
    byte-identical application candidate.  Tooling still receives its own identity.
    """
    workspace = source_root.parent
    roots = [(workspace / "tools", "tools"), (workspace / "automation", "automation")]
    entries = [entry for root, label in roots if root.exists() for entry in _entries(root, label)]
    canonical = {"schemaVersion": 1, "toolingInputs": entries}
    serialized = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return {**canonical, "toolingFingerprintId": hashlib.sha256(serialized.encode("utf-8")).hexdigest()}


def build_fingerprint(
    source_root: Path,
    installer_root: Path,
    artifacts: dict[str, Path] | None = None,
    *,
    source_executable_paths: set[str] | None = None,
) -> dict[str, object]:
    source_root = source_root.resolve()
    installer_root = installer_root.resolve()
    version = (source_root / "VERSION").read_text(encoding="utf-8").strip()
    installer_version = (installer_root / "INSTALLER_VERSION").read_text(encoding="utf-8").strip()
    executable_paths = executable_template_hooks(source_root) if source_executable_paths is None else set(source_executable_paths)
    unknown_executables = sorted(executable_paths - {path.relative_to(source_root).as_posix() for path in source_root.rglob("*") if _included(path, source_root)})
    if unknown_executables:
        raise ValueError(f"shipping mode contract names a missing file: {unknown_executables[0]}")
    entries = _entries(source_root, "source", executable_by_contract=executable_paths) + _entries(installer_root, "installer-source")
    artifact_entries: list[dict[str, object]] = []
    for name, path in sorted((artifacts or {}).items()):
        if not path.exists():
            continue
        artifact_entries.append({"name": name, "bytes": path.stat().st_size, "sha256": sha256(path)})
    canonical = {
        "schemaVersion": 2,
        "devfleetVersion": version,
        "installerVersion": installer_version,
        "shippingModeContract": {
            "schemaVersion": 1,
            "defaultMode": "0644",
            "executableMode": "0755",
            "executableByContract": sorted(executable_paths),
        },
        "shippingInputs": entries,
        "artifacts": artifact_entries,
    }
    serialized = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return {
        **canonical,
        "releaseFingerprintId": hashlib.sha256(serialized.encode("utf-8")).hexdigest(),
        "toolingFingerprint": _tooling_fingerprint(source_root),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--installer-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--artifact", action="append", default=[], metavar="NAME=PATH")
    args = parser.parse_args()
    artifacts = {}
    for value in args.artifact:
        name, separator, raw_path = value.partition("=")
        if not separator or not name or not raw_path:
            parser.error(f"artifact must be NAME=PATH: {value}")
        artifacts[name] = Path(raw_path)
    output = build_fingerprint(args.source_root, args.installer_root, artifacts)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, args.output)
    print(output["releaseFingerprintId"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/tools/validate_ai_audit_bundle.py

SHA256: d9f46d511192d552013ce289ffe7547bb3befd1d9c65d40b61038e979e93a70c | Bytes: 26859 | Git mode: 100644

```
"""Validate the universal DevFleet AI audit bundle.

This validator is intentionally independent of the PowerShell packager.  It
extracts the ZIP into a temporary directory whose name contains spaces and
checks the archive's source closure, hashes, modes, candidate tuple, and
security exclusions.  It does not trust a completeness claim made by the
bundle manifest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any


REQUIRED = {
    "AUDIT-README.md",
    "AUDIT-MANIFEST.json",
    "CURRENT-CANDIDATE.json",
    "AUDIT-TREE.txt",
    "SHA256SUMS.txt",
    "SOURCE-MODES.json",
    "finalization-state.json",
    "outputs/final-artifact-hashes.json",
    "outputs/release-fingerprint.json",
    "outputs/tooling-fingerprint-current.json",
    "outputs/dependency-advisory-gate.json",
}
RELEASE_REQUIRED = REQUIRED | {"outputs/independent-osv-reconciliation.json"}
FORBIDDEN_PARTS = {
    ".git",
    ".venv",
    "node_modules",
    "bin",
    "obj",
    "__pycache__",
    ".pytest_cache",
    "build",
    "dist",
    "vhdx",
    "snapshots",
    "browser-profile",
}
ALLOWED_OUTPUT_METADATA = {
    "outputs/final-artifact-hashes.json",
    "outputs/release-fingerprint.json",
    "outputs/tooling-fingerprint-current.json",
    "outputs/dependency-advisory-gate.json",
    "outputs/independent-osv-reconciliation.json",
}
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\b(?:ghp|github_pat|tskey)-[A-Za-z0-9_:-]{20,}"),
    re.compile(r"(?i)\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~-]{24,}"),
)
FAILED_ATTEMPT_SNAPSHOT = "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
FAILED_ATTEMPT_BLOCKER = "REPLACEMENT_CANDIDATE_BINDING_MISMATCH"
FAILED_ATTEMPT_CURRENT_RECORDS = (
    "evidence/CURRENT-PROOF.json",
    "audit/attemptedReplacementCandidate.json",
    "audit/candidateBindingFailure.json",
)
FAILED_ATTEMPT_INVENTORY_FILES = ("EVIDENCE-MODES.json", "EVIDENCE-SHA256SUMS.txt")


def _json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _validate_failed_attempt_records(extracted: Path, names: set[str], manifest: dict[str, Any]) -> None:
    missing = sorted((set(FAILED_ATTEMPT_CURRENT_RECORDS) | set(FAILED_ATTEMPT_INVENTORY_FILES)) - names)
    if missing:
        raise ValueError(f"failed-attempt diagnostic blocker records are missing: {missing}")
    proof = _json(extracted / "evidence/CURRENT-PROOF.json")
    attempted = _json(extracted / "audit/attemptedReplacementCandidate.json")
    failure = _json(extracted / "audit/candidateBindingFailure.json")
    if str(proof.get("status") or "") != "NOT_OBSERVED" or str(proof.get("outcome") or "") != "NOT_OBSERVED" or str(proof.get("blockerCode") or "") != FAILED_ATTEMPT_BLOCKER:
        raise ValueError("failed-attempt CURRENT-PROOF is not the current NOT_OBSERVED blocker record")
    expected = {
        "attemptedCommit": "21752fc0e50978183322204c523b40947d073aa0",
        "commitShippingInputIdentity": "6e0bac4b4eebc83cdcd9eddda2008607ba15c8835e5c72a931792f5b83c653f4",
        "buildTimeShippingInputIdentity": "3a65fd54d70fe05565ac3a32f73100ca2c81a77a4008feb361f99f229f025f8a",
    }
    if attempted.get("snapshotPath") != FAILED_ATTEMPT_SNAPSHOT or attempted.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or any(attempted.get(key) != value for key, value in expected.items()):
        raise ValueError("attemptedReplacementCandidate does not bind the failed-attempt snapshot and identities")
    if attempted.get("artifactTupleValid") is not True or attempted.get("artifactTupleMatchesCandidate") is not False or attempted.get("buildInvocationCount") != 1 or attempted.get("signingInvocationCount") != 1:
        raise ValueError("attemptedReplacementCandidate one-shot/artifact state is contradictory")
    if failure.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or any(failure.get(key) != value for key, value in expected.items()) or failure.get("artifactTupleValid") is not True or failure.get("artifactTupleMatchesCandidate") is not False:
        raise ValueError("candidateBindingFailure contradicts attempted replacement evidence")
    if failure.get("currentProofOutcome") != "NOT_OBSERVED" or failure.get("fullReleasePassed") is not False or failure.get("releaseEligible") is not False:
        raise ValueError("candidateBindingFailure permits an unobserved proof or release")
    inventory = manifest.get("evidenceInventory")
    if not isinstance(inventory, list):
        raise ValueError("failed-attempt diagnostic manifest is missing evidenceInventory")
    inventory_by_path = {str(row.get("path")): row for row in inventory if isinstance(row, dict)}
    if set(inventory_by_path) != set(FAILED_ATTEMPT_CURRENT_RECORDS):
        raise ValueError("failed-attempt evidenceInventory does not contain exactly the required blocker records")
    for relative in FAILED_ATTEMPT_CURRENT_RECORDS:
        row = inventory_by_path[relative]
        path = extracted / Path(*relative.split("/"))
        if not path.is_file() or int(row.get("bytes", -1)) != path.stat().st_size or str(row.get("sha256") or "").lower() != _sha(path) or row.get("mode") != "0644":
            raise ValueError(f"failed-attempt evidenceInventory hash/mode mismatch: {relative}")
    modes = _json(extracted / "EVIDENCE-MODES.json")
    mode_by_path = {str(row.get("path")): row for row in modes if isinstance(row, dict)} if isinstance(modes, list) else {}
    if set(mode_by_path) != set(FAILED_ATTEMPT_CURRENT_RECORDS) or any(row.get("posixMode") != 420 or row.get("mode") != "0644" for row in mode_by_path.values()):
        raise ValueError("failed-attempt evidence mode inventory is missing or contradictory")
    hash_rows = {}
    for line in (extracted / "EVIDENCE-SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
        if line.strip():
            digest, relative = line.split("  ", 1)
            hash_rows[relative] = digest.lower()
    if set(hash_rows) != set(FAILED_ATTEMPT_CURRENT_RECORDS) or any(hash_rows[path] != inventory_by_path[path]["sha256"] for path in FAILED_ATTEMPT_CURRENT_RECORDS):
        raise ValueError("failed-attempt evidence hash inventory is missing or contradictory")


def _safe_name(name: str) -> str:
    normalized = name.replace("\\", "/")
    pure = PurePosixPath(normalized)
    if not normalized or pure.is_absolute() or ".." in pure.parts:
        raise ValueError(f"unsafe ZIP entry: {name}")
    if any(part.lower() in FORBIDDEN_PARTS for part in pure.parts):
        raise ValueError(f"transient or generated ZIP entry: {name}")
    if "outputs" in {part.lower() for part in pure.parts} and normalized not in ALLOWED_OUTPUT_METADATA:
        raise ValueError(f"non-metadata output ZIP entry: {name}")
    if pure.name.lower().endswith((".pyc", ".pyo")):
        raise ValueError(f"compiled Python ZIP entry: {name}")
    return str(pure)


def _extract(archive: Path, destination: Path) -> list[str]:
    names: list[str] = []
    with zipfile.ZipFile(archive) as bundle:
        for info in bundle.infolist():
            name = _safe_name(info.filename)
            if name in names:
                raise ValueError(f"duplicate ZIP entry: {name}")
            names.append(name)
            file_type = (info.external_attr >> 16) & stat.S_IFMT(0o170000)
            if file_type in (stat.S_IFLNK, stat.S_IFCHR, stat.S_IFBLK, stat.S_IFIFO):
                raise ValueError(f"unsupported special ZIP entry: {name}")
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if not info.is_dir():
                with bundle.open(info) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)
                mode = (info.external_attr >> 16) & 0o777
                if mode and os.name != "nt":
                    target.chmod(mode)
    return names


def _run_optional(command: list[str], cwd: Path, timeout: int = 120) -> dict[str, Any]:
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return {"status": "SKIPPED", "reason": f"tool unavailable: {command[0]}"}
    except subprocess.TimeoutExpired:
        return {"status": "FAIL", "reason": f"timeout: {' '.join(command)}"}
    if completed.returncode:
        return {
            "status": "FAIL",
            "reason": f"exit {completed.returncode}: {(completed.stderr or completed.stdout)[-2000:]}",
        }
    return {"status": "PASS", "command": command, "stdout": completed.stdout, "stderr": completed.stderr}


def _run_candidate_validator(command: list[str], cwd: Path, mode: str) -> dict[str, Any]:
    """Run and preserve the candidate-bound validator's structured result."""
    result = _run_optional(command, cwd)
    if result.get("status") != "PASS":
        return result
    output = str(result.pop("stdout", ""))
    result.pop("stderr", None)
    if not output.strip():
        raise ValueError("candidate coherence check returned no structured JSON")
    try:
        structured = json.loads(output)
    except json.JSONDecodeError as exc:
        raise ValueError("candidate coherence check returned malformed JSON") from exc
    if not isinstance(structured, dict) or set(structured) == set():
        raise ValueError("candidate coherence check returned a non-object JSON result")
    status = structured.get("status")
    if mode == "diagnostic":
        if status != "PASS_WITH_BLOCKER" or structured.get("releaseEligible") is not False or not isinstance(structured.get("blockerCode"), str) or not structured["blockerCode"]:
            raise ValueError("diagnostic candidate coherence result was downgraded or contradictory")
    elif status != "PASS" or structured.get("blockerCode"):
        raise ValueError("release candidate coherence result contains a blocker")
    return structured


def validate(archive: Path, report_path: Path | None = None, mode: str = "release") -> dict[str, Any]:
    if mode not in {"diagnostic", "release"}:
        raise ValueError("validator mode must be diagnostic or release")
    archive = archive.resolve()
    if not archive.is_file():
        raise FileNotFoundError(archive)
    temp_parent = Path(tempfile.mkdtemp(prefix="DevFleet AI Audit "))
    extracted = temp_parent / "bundle with spaces"
    extracted.mkdir()
    try:
        names = _extract(archive, extracted)
        name_set = set(names)
        required = RELEASE_REQUIRED if mode == "release" else REQUIRED
        missing = sorted(required - name_set)
        if missing:
            raise ValueError(f"required audit files are missing: {missing}")
        if "source" not in name_set and not any(name.startswith("source/") for name in names):
            raise ValueError("shipping source is missing")
        if "installer-source" not in name_set and not any(name.startswith("installer-source/") for name in names):
            raise ValueError("installer source is missing")
        # Load the manifest before any failed-attempt record consumer.  The
        # evidence inventory is part of the failed-attempt contract, so a
        # malformed or missing manifest must fail closed before validation.
        manifest = _json(extracted / "AUDIT-MANIFEST.json")
        failed_attempt = FAILED_ATTEMPT_SNAPSHOT in name_set
        if failed_attempt and mode == "release":
            raise ValueError("release mode rejects failed replacement-attempt evidence")
        if failed_attempt and mode == "diagnostic":
            _validate_failed_attempt_records(extracted, name_set, manifest)
        if not any(name.startswith("automation/release-e2e/") for name in names):
            raise ValueError("release-E2E automation source is missing")

        candidate = _json(extracted / "CURRENT-CANDIDATE.json")
        attempted_commit = str(candidate.get("candidateCommit") or candidate.get("candidateGitCommit") or "").lower()
        if mode == "diagnostic" and attempted_commit == "21752fc0e50978183322204c523b40947d073aa0" and not failed_attempt:
            raise ValueError("failed replacement-attempt snapshot is mandatory for this diagnostic candidate")
        required_tuple = (
            "devfleetVersion",
            "installerVersion",
            "gitCommit",
            "shippingInputIdentity",
            "candidateShippingInputIdentity",
            "candidateCommit",
            "releaseFingerprintId",
            "toolingFingerprintId",
            "exeSha256",
            "tarSha256",
            "portableSha256",
            "installerSourceSha256",
            "candidateIsCurrent",
            "sourceChangedSinceCandidate",
            "rebuildRequired",
        )
        for key in required_tuple:
            if key not in candidate:
                raise ValueError(f"current candidate is missing {key}")
        if candidate["devfleetVersion"] != manifest.get("devfleetVersion"):
            raise ValueError("manifest and current candidate disagree on DevFleet version")
        if candidate["installerVersion"] != manifest.get("installerVersion"):
            raise ValueError("manifest and current candidate disagree on installer version")
        if candidate["sourceChangedSinceCandidate"] and not candidate["rebuildRequired"]:
            raise ValueError("sourceChangedSinceCandidate requires rebuildRequired")
        if candidate["rebuildRequired"] and candidate["candidateIsCurrent"]:
            raise ValueError("rebuildRequired candidate cannot be current")
        for key in ("releaseFingerprintId", "toolingFingerprintId"):
            if not re.fullmatch(r"[0-9a-f]{64}", str(candidate[key])):
                raise ValueError(f"malformed {key}")
            if str(candidate[key]) == "0" * 64:
                raise ValueError(f"zero {key} is not a current identity")
        if not re.fullmatch(r"[0-9a-fA-F]{40}", str(candidate["candidateCommit"])) or str(candidate["candidateCommit"]).lower() == "0" * 40:
            raise ValueError("malformed candidateCommit")
        for key in ("shippingInputIdentity", "candidateShippingInputIdentity"):
            if not re.fullmatch(r"[0-9a-f]{64}", str(candidate[key])) or str(candidate[key]) == "0" * 64:
                raise ValueError(f"malformed {key}")
        for key in ("exeSha256", "tarSha256", "portableSha256", "installerSourceSha256"):
            if not re.fullmatch(r"[0-9a-f]{64}", str(candidate[key])):
                raise ValueError(f"malformed candidate artifact hash: {key}")
        artifact_names = {
            "exeSha256": {"exe", "installer", "installerexe"},
            "tarSha256": {"tar", "payload"},
            "portableSha256": {"portable"},
            "installerSourceSha256": {"installersource", "installer_source"},
        }
        artifact_manifest = _json(extracted / "outputs/final-artifact-hashes.json")
        artifact_rows = manifest.get("artifacts") or (artifact_manifest.get("artifacts") if isinstance(artifact_manifest, dict) else [])
        manifest_artifacts = {
            str(row.get("name") or "").lower().replace("-", "").replace("_", ""): row
            for row in artifact_rows
            if isinstance(row, dict)
        }
        for candidate_key, expected_names in artifact_names.items():
            row = next((manifest_artifacts[name.replace("-", "").replace("_", "")] for name in expected_names if name.replace("-", "").replace("_", "") in manifest_artifacts), None)
            if row is None or str(row.get("sha256") or "").lower() != str(candidate[candidate_key]).lower():
                raise ValueError(f"candidate artifact tuple does not match manifest: {candidate_key}")
            bytes_key = candidate_key[:-6] + "Bytes" if candidate_key.endswith("Sha256") else ""
            if bytes_key and bytes_key in candidate and int(row.get("bytes", -1)) != int(candidate[bytes_key]):
                raise ValueError(f"candidate artifact tuple byte count does not match manifest: {candidate_key}")

        coherence = _run_candidate_validator(
            [sys.executable, "source/tools/validate_audit_coherence.py", "--root", str(extracted), "--mode", mode],
            extracted,
            mode,
        )
        if coherence.get("status") not in ({"PASS_WITH_BLOCKER"} if mode == "diagnostic" else {"PASS"}):
            raise ValueError(f"candidate coherence check failed: {coherence.get('reason', '')}")
        if failed_attempt:
            if mode != "diagnostic" or coherence.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or coherence.get("releaseEligible") is not False:
                raise ValueError("failed replacement-attempt result was downgraded or made release eligible")
            if candidate.get("candidateIsCurrent") is not False or candidate.get("sourceChangedSinceCandidate") is not True or candidate.get("rebuildRequired") is not True or candidate.get("artifactTupleMatchesCandidate") is not False:
                raise ValueError("failed replacement-attempt candidate flags are not truthful")

        inventory = manifest.get("sourceInventory")
        if not isinstance(inventory, list) or not inventory:
            raise ValueError("sourceInventory is empty")
        inventory_paths = {str(item["path"]) for item in inventory}
        source_paths = {
            name
            for name in names
            if name.startswith(("source/", "installer-source/", "automation/release-e2e/", "release-tooling/"))
            and not name.endswith("/")
            and (extracted / name).is_file()
        }
        if inventory_paths != source_paths:
            raise ValueError(
                "source inventory mismatch: "
                f"missing={sorted(inventory_paths - source_paths)[:5]} "
                f"unexpected={sorted(source_paths - inventory_paths)[:5]}"
            )
        if int(manifest.get("expectedSourceCount", -1)) != len(source_paths):
            raise ValueError("expectedSourceCount does not match extracted source")
        hashes = {}
        for line in (extracted / "SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
            if not line.strip():
                continue
            digest, path = line.split("  ", 1)
            hashes[path] = digest.lower()
        if set(hashes) != source_paths:
            raise ValueError("SHA256SUMS.txt does not cover exactly the source closure")
        for path in sorted(source_paths):
            actual = _sha(extracted / path)
            if hashes[path] != actual:
                raise ValueError(f"source hash mismatch: {path}")

        modes = {str(item["path"]): int(item["posixMode"]) for item in _json(extracted / "SOURCE-MODES.json")}
        if set(modes) != source_paths:
            raise ValueError("SOURCE-MODES.json does not cover exactly the source closure")
        mode_mismatches = []
        with zipfile.ZipFile(archive) as bundle:
            for info in bundle.infolist():
                if info.filename in modes:
                    archived = (info.external_attr >> 16) & 0o777
                    if archived != modes[info.filename]:
                        mode_mismatches.append(info.filename)
        if mode_mismatches:
            raise ValueError(f"POSIX mode mismatch: {mode_mismatches[:5]}")

        secret_findings = []
        for path in sorted(source_paths):
            try:
                text = (extracted / path).read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            for pattern in SECRET_PATTERNS:
                if pattern.search(text):
                    secret_findings.append(path)
        if secret_findings:
            raise ValueError(f"secret-like material found in source: {sorted(set(secret_findings))[:5]}")

        checks: dict[str, Any] = {
            "pythonCompile": "SKIPPED",
            "javascriptSyntax": "SKIPPED",
            "bashSyntax": "SKIPPED",
            "powershellParse": "SKIPPED",
            "dotnetBuild": "SKIPPED",
            "dotnetTests": "SKIPPED",
        }
        py_files = [str(path) for path in (extracted / "source").rglob("*.py")]
        if py_files:
            checks["pythonCompile"] = _run_optional([sys.executable, "-m", "compileall", "-q", "source"], extracted)["status"]
            if checks["pythonCompile"] == "FAIL":
                raise ValueError("Python compile check failed")
        js_files = [path.relative_to(extracted).as_posix() for path in (extracted / "source").rglob("*.js")]
        node_available = shutil.which("node")
        if js_files and node_available:
            for path in js_files:
                result = _run_optional([node_available, "--check", path], extracted)
                if result["status"] == "FAIL":
                    raise ValueError(f"JavaScript syntax check failed: {path}")
            checks["javascriptSyntax"] = "PASS"
        elif js_files:
            checks["javascriptSyntax"] = "SKIPPED"
        sh_files = [path.relative_to(extracted).as_posix() for path in (extracted / "source").rglob("*.sh")]
        bash = shutil.which("bash")
        if sh_files and bash:
            probe = _run_optional([bash, "--version"], extracted)
            if probe["status"] == "PASS":
                for path in sh_files:
                    result = _run_optional([bash, "-n", path], extracted)
                    if result["status"] == "FAIL":
                        raise ValueError(f"Bash syntax check failed: {path}")
                checks["bashSyntax"] = "PASS"
            else:
                checks["bashSyntax"] = "SKIPPED"
        ps = shutil.which("pwsh") or shutil.which("powershell")
        if ps:
            scripts = [
                path.relative_to(extracted).as_posix()
                for root in (extracted / "source", extracted / "installer-source", extracted / "automation")
                if root.exists()
                for path in root.rglob("*")
                if path.suffix.lower() in {".ps1", ".psm1", ".psd1"}
            ]
            parse_script_path = extracted / "_audit_parse.ps1"
            parse_script_path.write_text(
                "param([Parameter(Mandatory)][string]$Path)\n"
                "$tokens=$null; $errors=$null\n"
                "[System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors) | Out-Null\n"
                "if($errors.Count){ $errors | ForEach-Object { Write-Error $_.Message }; exit 2 }\n",
                encoding="utf-8",
            )
            for path in scripts:
                result = _run_optional([ps, "-NoProfile", "-NonInteractive", "-File", "_audit_parse.ps1", "-Path", path], extracted)
                if result["status"] == "FAIL":
                    raise ValueError(f"PowerShell parse check failed: {path}")
            checks["powershellParse"] = "PASS"
        dotnet = shutil.which("dotnet")
        if dotnet and (extracted / "installer-source").exists():
            try:
                probe = subprocess.run([dotnet, "--list-sdks"], cwd=extracted, capture_output=True, text=True, timeout=20)
            except (FileNotFoundError, subprocess.TimeoutExpired):
                probe = None
            if probe is not None and probe.returncode == 0 and probe.stdout.strip():
                build = _run_optional([dotnet, "build", "DevFleet.Setup/DevFleet.Setup.csproj", "--no-restore", "-v:minimal"], extracted / "installer-source", timeout=180)
                if build["status"] == "FAIL":
                    raise ValueError(".NET installer build failed")
                checks["dotnetBuild"] = build["status"]
                tests = _run_optional([dotnet, "build", "DevFleet.Setup.Tests/DevFleet.Setup.Tests.csproj", "--no-restore", "-v:minimal"], extracted / "installer-source", timeout=180)
                if tests["status"] == "FAIL":
                    raise ValueError(".NET installer test project build failed")
                checks["dotnetTests"] = tests["status"]

        if mode == "release" and (not bool(candidate.get("candidateIsCurrent")) or bool(candidate.get("sourceChangedSinceCandidate")) or bool(candidate.get("rebuildRequired"))):
            raise ValueError("release mode rejects an invalidated or historical candidate")
        report = {
            "status": "PASS_WITH_BLOCKER" if mode == "diagnostic" else "COMPLETE_FOR_AI_AUDIT",
            "bundleMode": mode,
            "releaseEligible": mode == "release",
            "candidateIsCurrent": bool(candidate.get("candidateIsCurrent")),
            "sourceChangedSinceCandidate": bool(candidate.get("sourceChangedSinceCandidate")),
            "rebuildRequired": bool(candidate.get("rebuildRequired")),
            "archive": str(archive),
            "temporaryExtraction": str(extracted),
            "expectedSourceCount": len(source_paths),
            "includedSourceCount": len(source_paths),
            "releaseE2EToolingIncluded": True,
            "modeVerification": "PASS",
            "coherenceVerification": coherence["status"],
            "coherenceBlockerCode": coherence.get("blockerCode"),
            "secretScan": "