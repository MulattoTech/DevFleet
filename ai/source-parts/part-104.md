# DevFleet source part 104

Full-source UTF-8 byte interval [4789500, 4836000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2f87c227864b00e2d34902b9ed99b054bca1961afdb5eb9bae8d3762f6f40d46

<!-- BEGIN SOURCE SLICE -->
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
        target.chmod(archived_mode)


def _extract_regular_tar_member(archive: tarfile.TarFile, info: tarfile.TarInfo, dest: Path, name: str) -> None:
    assert info.isfile(), f"unsupported TAR entry type: {name}"
    target = _safe_target(dest, name)
    target.parent.mkdir(parents=True, exist_ok=True)
    source = archive.extractfile(info)
    assert source is not None, f"TAR member could not be read: {name}"
    with source, target.open("xb") as output:
        shutil.copyfileobj(source, output)
    if os.name != "nt":
        target.chmod(info.mode & 0o777)


def verify_archive(path: Path) -> None:
    """Validate and clean-extract a zip/tar release archive without running it."""
    assert path.is_file(), f"archive not found: {path}"
    with tempfile.TemporaryDirectory() as td:
        dest = Path(td); names: set[str] = set(); modes: dict[str, int] = {}
        if zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as archive:
                for info in archive.infolist():
                    name = _safe_member(info.filename)
                    if name.endswith("/"): continue
                    assert name not in names, f"duplicate archive member: {name}"; names.add(name)
                    modes[name] = (info.external_attr >> 16) & 0o777
                    _extract_regular_zip_member(archive, info, dest, name)
        else:
            with tarfile.open(path, "r:*") as archive:
                for info in archive.getmembers():
                    name = _safe_member(info.name)
                    if info.isdir(): continue
                    assert name not in names, f"duplicate archive member: {name}"; names.add(name); modes[name] = info.mode & 0o777
                    assert info.isfile(), f"unsupported TAR entry type: {name}"
                    _extract_regular_tar_member(archive, info, dest, name)
        assert set(REQUIRED).issubset(names), f"archive missing required files: {sorted(set(REQUIRED)-names)[:10]}"
        hooks = [name for name in names if name in executable_template_hooks(dest)]
        assert hooks, "archive contains no trusted template hooks"
        for name in hooks:
            assert modes.get(name, 0) == 0o755, f"template hook does not have 0755 mode in archive: {name}"
            # Windows extraction APIs do not expose POSIX execute bits. The
            # archive mode is still checked above; on POSIX, also verify the
            # mode survived the actual clean extraction.
            if os.name != "nt":
                assert (dest / name).stat().st_mode & 0o111, f"trusted template hook lost executable mode after extraction: {name}"
        assert CHECKSUM_MANIFEST in names, "archive missing checksum manifest"


def archive_structural_checks(root: Path = ROOT) -> None:
    """Round-trip a clean tar archive to exercise release structure and modes."""
    with tempfile.TemporaryDirectory() as td:
        archive = Path(td) / "package.tar.gz"
        hooks = executable_template_hooks(root)
        with tarfile.open(archive, "w:gz") as out:
            for rel in sorted(package_files(root)):
                source = root / rel; info = out.gettarinfo(str(source), arcname=rel)
                if rel in hooks: info.mode = 0o755
                with source.open("rb") as stream: out.addfile(info, stream)
        verify_archive(archive)


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(); parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    assert re.fullmatch(r"\d+\.\d+\.\d+", PACKAGE_VERSION), PACKAGE_VERSION
    require_files(); parse_data(); compile_python_jinja(); bash_syntax(); linux_executable_hooks(); powershell_lexical(); template_smoke(); codexpro_guard_tests(); fastapi_smoke(); no_empty(); baseline_preserved(); verify_checksums(); archive_structural_checks()
    if args.archive: verify_archive(args.archive)
    print(f"DevFleet v{PACKAGE_VERSION} offline package verification passed.")


if __name__ == "__main__":
    main()

```


## FILE: source/tools/write_posix_zip.py

SHA256: 10088dbe4b07289b6f3df8811a75a2c58a2ad65b0b44f728f448c7cbc2129cda | Bytes: 1706 | Git mode: 100644

```
"""Write a deterministic ZIP whose entries advertise Unix file modes."""
from __future__ import annotations

import argparse
import json
import stat
import zipfile
from pathlib import Path


def _mode_map(path: Path) -> dict[str, int]:
    values = json.loads(path.read_text(encoding="utf-8-sig"))
    return {str(item["path"]): int(item["posixMode"]) for item in values}


def write_zip(stage: Path, output: Path, modes_path: Path) -> None:
    modes = _mode_map(modes_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        paths = sorted(stage.rglob("*"), key=lambda item: item.relative_to(stage).as_posix())
        for path in paths:
            name = path.relative_to(stage).as_posix()
            if path.is_dir():
                continue
            if not path.is_file():
                continue
            mode = modes.get(name, 0o644)
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | (mode & 0o7777)) << 16
            with path.open("rb") as handle:
                archive.writestr(info, handle.read(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--modes", type=Path, required=True)
    args = parser.parse_args()
    write_zip(args.stage, args.output, args.modes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/windows/00-Preflight.ps1

SHA256: e9a3edb41802e9a01d76641f133430d683c84d37cf43604a492ebf106827c731 | Bytes: 4118 | Git mode: 100644

```
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Role,[ValidateSet('Offline','Connected')][string]$InstallationMode='Offline')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DevFleet.Common.psm1') -Force
Assert-PowerShell7; Assert-Administrator
$config=Get-DevFleetConfig

Write-Host "`nPreflight for $Role on $env:COMPUTERNAME ($InstallationMode)" -ForegroundColor Cyan
$os=Get-CimInstance Win32_OperatingSystem
$cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$sys=Get-CimInstance Win32_ComputerSystem
$drive=Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
$virtFirmware=$cpu.VirtualizationFirmwareEnabled
$slat=$cpu.SecondLevelAddressTranslationExtensions
$nestedHyperVOperational=$false
if (-not $slat) {
  try { Get-VMHost -ErrorAction Stop | Out-Null; $nestedHyperVOperational=$true } catch { }
}

[pscustomobject]@{
  Windows=$os.Caption
  Version=$os.Version
  CPU=$cpu.Name
  LogicalProcessors=$sys.NumberOfLogicalProcessors
  RAMGB=[math]::Round($sys.TotalPhysicalMemory/1GB,1)
  SystemDriveFreeGB=[math]::Round($drive.Free/1GB,1)
  VirtualizationFirmwareEnabled=$virtFirmware
  SLAT=$slat
  OperationalHyperVHost=$nestedHyperVOperational
} | Format-List

if (-not $virtFirmware) { throw 'Hardware virtualization is disabled in UEFI/BIOS.' }
if (-not $slat -and -not $nestedHyperVOperational) { throw 'Second Level Address Translation is required.' }
# Conservatively adapt defaults to this machine instead of overcommitting RAM/CPU.
$ramGB=[math]::Floor($sys.TotalPhysicalMemory/1GB);$logical=[int]$sys.NumberOfLogicalProcessors;$changed=$false
if($Role -eq 'Desktop'){
  $mem=[math]::Max(8,[math]::Min(32,[math]::Floor($ramGB*0.60)));$cpus=[math]::Max(2,[math]::Min(12,$logical-2))
  if($config.Primary.Memory -ne "${mem}G"){$config.Primary.Memory="${mem}G";$changed=$true}
  if([int]$config.Primary.Cpus -ne $cpus){$config.Primary.Cpus=$cpus;$changed=$true}
}else{
  $profile=$config.RoleProfiles.LaptopSurrogate
  if(-not $profile -or -not $profile.Recommended -or -not $profile.MinimumTested){throw 'Laptop/Surrogate resource policy is missing from the canonical configuration.'}
  $failMem=[int]([string]$profile.Recommended.FailoverMemory -replace '[^0-9.]','')
  $vaultMem=[int]([string]$profile.Recommended.VaultMemory -replace '[^0-9.]','')
  $minimumFailMem=[int]([string]$profile.MinimumTested.FailoverMemory -replace '[^0-9.]','')
  $minimumVaultMem=[int]([string]$profile.MinimumTested.VaultMemory -replace '[^0-9.]','')
  if($failMem -lt $minimumFailMem -or $vaultMem -lt $minimumVaultMem){throw 'Canonical Laptop/Surrogate resource policy is below the tested minimum.'}
  $failCpu=[math]::Max(2,[math]::Min(4,$logical-2));$vaultCpu=[math]::Max(1,[math]::Min(2,[math]::Floor($logical/4)))
  if($config.Failover.Memory -ne "${failMem}G"){$config.Failover.Memory="${failMem}G";$changed=$true}
  if($config.Vault.Memory -ne "${vaultMem}G"){$config.Vault.Memory="${vaultMem}G";$changed=$true}
  if([int]$config.Failover.Cpus -ne $failCpu){$config.Failover.Cpus=$failCpu;$changed=$true}
  if([int]$config.Vault.Cpus -ne $vaultCpu){$config.Vault.Cpus=$vaultCpu;$changed=$true}
}
if($changed){Save-DevFleetConfig $config;Write-Host 'VM CPU/RAM defaults were adjusted conservatively for this computer.' -ForegroundColor Yellow}
$requiredFree = if ($Role -eq 'Desktop') { 120 } else { 100 }
if (($drive.Free/1GB) -lt $requiredFree) { throw "At least $requiredFree GB free is required with current defaults. Reduce VM disk sizes in the config or free space." }

$edition=(Get-ComputerInfo -Property WindowsProductName).WindowsProductName
$hyperVCapable=$edition -match 'Pro|Enterprise|Education'
if (-not $hyperVCapable) { Write-Warning 'Hyper-V is not included in this Windows edition. Multipass will require VirtualBox.' }

$conflicts=Get-Process -Name 'MuMuPlayer','NemuHeadless','VBoxHeadless','vmware' -ErrorAction SilentlyContinue
if ($conflicts) { Write-Warning 'A virtualization/emulator process is running. Close it before installing or changing a hypervisor.' }
Write-Host 'Preflight passed.' -ForegroundColor Green

```


## FILE: source/windows/01-Install-Prerequisites.ps1

SHA256: bc4d60449c0633509984438a3a41a8d5077222e66ca57e79f20f621fe076f81b | Bytes: 12943 | Git mode: 100644

```
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Laptop','Desktop')][string]$Rol