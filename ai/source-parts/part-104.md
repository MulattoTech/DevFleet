# DevFleet source part 104

Full-source UTF-8 byte interval [4789500, 4836000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 3ecab63c85a9fac451c93196732a4c5a6eccfcab66acf0100344fd5c4af83132

<!-- BEGIN SOURCE SLICE -->
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
            "secretScan": "PASS",
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
    if any(value != record for value 