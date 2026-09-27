# DevFleet source part 122

Full-source UTF-8 byte interval [5626500, 5673000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 89bebc267e07db2845c4f794e6829625f690dd14c9e3ce91b5b61b6fed2f80b7

<!-- BEGIN SOURCE SLICE -->
ntory in inventories:
        require(inventory.get('status') == 'PASS'
                and isinstance(inventory.get('names'), list)
                and all(isinstance(n, str) and n.strip() and n != L2_NAME
                        for n in inventory['names'])
                and isinstance(inventory.get('verification'), str)
                and inventory['verification'].strip(),
                'Nested L2 backend inventory is incomplete or present')

    require(live.get('scope') == 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY'
            and live.get('vm') == {'name': VM_NAME, 'id': VM_ID, 'state': 'Off'},
            'Final native exact L1 Off identity is absent')
    live_time = instant(live.get('observedUtc'))
    require(auth_time <= instant(attempts[0].get('terminalUtc')) <= live_time,
            'Authenticated observation is outside its terminal diagnostic lineage')
    require(auth_time <= live_time <= datetime.now(timezone.utc)
            and (live_time - auth_time).total_seconds() <= 3600
            and live_time < expires and datetime.now(timezone.utc) < expires
            and (datetime.now(timezone.utc) - live_time).total_seconds() <= 3600,
            'Native checkpoint inventory is not fresh after authenticated guest evidence')
    snapshots = live.get('snapshots')
    require(isinstance(snapshots, list) and len(snapshots) >= 2
            and all(isinstance(s, dict) for s in snapshots),
            'Native snapshot inventory is incomplete')
    old_rows = [s for s in snapshots if s.get('id') == OLD_ID or s.get('name') == OLD_NAME]
    new_rows = [s for s in snapshots if s.get('id') == new_id or s.get('name') == NEW_NAME]
    require(len(old_rows) == 1 and old_rows[0].get('name') == OLD_NAME
            and old_rows[0].get('id') == OLD_ID and old_rows[0].get('vmId') == VM_ID,
            'Predecessor checkpoint is missing or ambiguous')
    require(len(new_rows) == 1 and new_rows[0].get('name') == NEW_NAME
            and new_rows[0].get('id') == new_id and new_rows[0].get('vmId') == VM_ID
            and new_rows[0].get('parentSnapshotId') == OLD_ID,
            'Replacement checkpoint is missing, ambiguous or name-only')
    return current_tuple, expires


def adopt(root, proposal_path, approval_path, auth_path, live_path, tuple_path, ledger_path,
          *, fault=None):
    """Atomically adopt one validated replacement; never touch checkpoints or old history."""
    state = _state(root)
    with lock(state / '.adoption.lock'):
        pointer = state / 'CURRENT.json'
        receipts = state / 'receipts'
        require(not pointer.exists(), 'An accepted replacement already exists; replay rejected')
        require(not receipts.exists() or not list(receipts.iterdir()),
                'Interrupted/orphan receipt exists; old baseline remains selected')
        proposal, approval = read_json(proposal_path), read_json(approval_path)
        auth, live, current_tuple = read_json(auth_path), read_json(live_path), read_json(tuple_path)
        ledger = read_json(ledger_path)
        predecessor_evidence = proposal.get('predecessorEvidence') or {}
        predecessor_path = Path(predecessor_evidence.get('path', ''))
        expected_source_root = Path(root).resolve(strict=True) / 'audit/agent-memory/attempts/DF-FRESH-CERTIFICATION-20260926-R2'
        require(predecessor_path.is_absolute() and predecessor_path.suffix.lower() == '.json'
                and predecessor_path.resolve(strict=True).is_relative_to(expected_source_root)
                and predecessor_evidence.get('sha256') == digest(predecessor_path),
                'Preserved predecessor evidence is absent, outside R2, or hash mismatched')
        predecessor_record = read_json(predecessor_path)
        require((predecessor_record.get('lab') or {}).get('l1Id') == VM_ID
                and (predecessor_record.get('lab') or {}).get('cleanId') == OLD_ID
                and (predecessor_record.get('liveGuestAuth') or {}).get('cleanRestored') is True
                and (predecessor_record.get('liveGuestAuth') or {}).get('finalL1State') == 'Off',
                'Predecessor source does not preserve the exact restored CLEAN identity')
        candidate, expires = _validate(proposal, approval, auth, live, current_tuple,
                                       ledger, auth_path)
        receipts.mkdir(parents=True, exist_ok=True)
        receipt_id = uuid.uuid4().hex
        receipt_file = receipt_id + '.json'
        receipt = {
            'schemaVersion': 1, 'contract': 'devfleet-baseline-adoption-receipt-v1',
            'receiptId': receipt_id, 'status': 'ADOPTED',
            'adoptedUtc': datetime.now(timezone.utc).isoformat(),
            'certificationCredit': False, 'secretValuesRecorded': False,
            'predecessor': proposal['predecessor'], 'replacement': proposal['replacement'],
            'candidate': candidate, 'runId': proposal['runId'],
            'passwordLastSetUtc': auth['guest']['passwordLastSetUtc'],
            'passwordExpiresUtc': auth['guest']['passwordExpiresUtc'],
            'protectedStoreUpdatedUtc': auth['credential']['protectedStoreUpdatedUtc'],
            'authenticatedGuest': {'computerName': auth['guest']['computerName'],
                                   'principal': auth['guest']['principal'],
                                   'accountEnabled': True,
                                   'sourceObservedUtc': auth['observedUtc']},
            'nestedL2': auth['nestedL2'],
            'finalL1': live['vm'],
            'liveCheckpointInventory': live['snapshots'],
            'adoptionAuthority': {'decision': approval['decision'],
                                  'approvedBy': approval['approvedBy'],
                                  'sourceSha256': digest(approval_path)},
            'sources': {'proposalSha256': digest(proposal_path),
                        'predecessorEvidenceSha256': digest(predecessor_path),
                        'approvalSha256': digest(approval_path),
                        'authenticatedGuestSha256': digest(auth_path),
                        'nativeInventorySha256': digest(live_path),
                        'currentTupleSha256': digest(tuple_path),
                        'r2LedgerSha256': digest(ledger_path)},
        }
        receipt_path = receipts / receipt_file
        _write_exclusive(receipt_path, _json_bytes(receipt))
        receipt_hash = digest(receipt_path)
        if fault == 'after_receipt':
            raise RuntimeError('Injected interruption after immutable receipt')
        pointer_value = {'schemaVersion': 1, 'contract': 'devfleet-accepted-baseline-v1',
                         'generation': 1, 'status': 'ACCEPTED',
                         'receiptFile': receipt_file, 'receiptSha256': receipt_hash,
                         'checkpoint': proposal['replacement']}
        _atomic_replace(pointer, _json_bytes(pointer_value))
        return {'receiptFile': receipt_file, 'receiptSha256': receipt_hash,
                'certificationCredit': False, 'passwordExpiresUtc': expires.isoformat()}


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    inspect = sub.add_parser('inspect')
    inspect.add_argument('--root', required=True)
    inspect.add_argument('--tuple')
    adoption = sub.add_parser('adopt')
    for flag in ('root', 'proposal', 'approval', 'auth', 'live', 'tuple', 'ledger'):
        adoption.add_argument('--' + flag, required=True)
    binding = sub.add_parser('rebind')
    for flag in ('root', 'tuple', 'approval', 'ledger', 'live'):
        binding.add_argument('--' + flag, required=True)
    args = parser.parse_args()
    if args.command == 'inspect':
        value = accepted_baseline(args.root, read_json(args.tuple) if args.tuple else None)
    elif args.command == 'adopt':
        value = adopt(args.root, args.proposal, args.approval, args.auth, args.live, args.tuple,
                      args.ledger)
    else:
        value = rebind(args.root, args.tuple, args.approval, args.ledger, args.live)
    print(json.dumps(value, indent=2))


if __name__ == '__main__': main()

```


## FILE: tools/compute_shipping_input_identity.py

SHA256: 124fb632ac98b18e48f3b163a1568b627381c1614e93f98effce4d13d254732b | Bytes: 9809 | Git mode: 100644

```
"""Compute live and candidate shipping-input rows from the release fingerprint contract.

This is release tooling: it imports the candidate-bound ``release_fingerprint``
implementation instead of maintaining a second inclusion/mode/hash policy.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


RELEASE_ARTIFACT_NAMES = frozenset({"exe", "tar", "portable", "installerSource"})


def _fingerprint(source: Path, installer: Path, artifacts: dict[str, Path] | None = None) -> dict[str, object]:
    tools = source / "tools"
    previous_modules = {name: sys.modules.get(name) for name in ("release_fingerprint", "hook_modes")}
    for name in previous_modules:
        sys.modules.pop(name, None)
    sys.path.insert(0, str(tools))
    try:
        from release_fingerprint import build_fingerprint  # type: ignore

        return build_fingerprint(source, installer, artifacts)
    finally:
        sys.path.pop(0)
        for name in previous_modules:
            sys.modules.pop(name, None)
        for name, module in previous_modules.items():
            if module is not None:
                sys.modules[name] = module


def _git_commit_exists(workspace: Path, commit: str) -> None:
    if not commit or len(commit) != 40 or any(ch not in "0123456789abcdefABCDEF" for ch in commit):
        raise ValueError("candidate commit must be an explicit 40-character Git object ID")
    try:
        subprocess.run(["git", "-C", str(workspace), "cat-file", "-e", f"{commit}^{{commit}}"], check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError(f"candidate commit does not resolve to a commit: {commit}") from exc


def _materialize_candidate(workspace: Path, commit: str, artifacts: dict[str, Path] | None = None) -> tuple[dict[str, object], Path]:
    """Materialize candidate shipping trees without changing the checkout."""
    _git_commit_exists(workspace, commit)
    try:
        archive = subprocess.check_output(["git", "-C", str(workspace), "-c", "core.autocrlf=false", "archive", "--format=tar", commit, "source", "installer-source"], stderr=subprocess.STDOUT)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError(f"candidate shipping tree could not be materialized: {commit}") from exc
    staging = Path(tempfile.mkdtemp(prefix="devfleet-candidate-"))
    try:
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
            stream.extractall(staging, filter="data")
        source, installer = staging / "source", staging / "installer-source"
        if not source.is_dir() or not installer.is_dir():
            raise ValueError("candidate commit has ambiguous or incomplete shipping roots")
        return _fingerprint(source, installer, artifacts), staging
    except Exception:
        import shutil
        shutil.rmtree(staging, ignore_errors=True)
        raise


def _shipping_identity(fingerprint: dict[str, object]) -> str:
    payload = {"schemaVersion": 1, "devfleetVersion": fingerprint["devfleetVersion"], "installerVersion": fingerprint["installerVersion"], "shippingModeContract": fingerprint["shippingModeContract"], "shippingInputs": fingerprint["shippingInputs"]}
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _materialization_comparison(
    live_source: Path,
    live_installer: Path,
    candidate_source: Path,
    candidate_installer: Path,
    live: dict[str, object],
    candidate: dict[str, object],
) -> dict[str, object]:
    """Classify checkout differences without weakening Git-object authority.

    Only insertion of CR before an LF in a live Windows checkout is accepted
    as a non-substantive materialization difference.  Missing files, mode
    contract changes, versions, bare CR changes, or any other byte change are
    substantive.
    """

    def rows(value: dict[str, object]) -> dict[str, dict[str, object]]:
        return {
            f"{row['root']}/{row['path']}": row
            for row in value["shippingInputs"]  # type: ignore[index]
        }

    live_rows, candidate_rows = rows(live), rows(candidate)
    changed = sorted(
        path
        for path in set(live_rows) | set(candidate_rows)
        if live_rows.get(path) != candidate_rows.get(path)
    )
    crlf_only_paths: list[str] = []
    crlf_only = bool(changed)
    for relative in changed:
        live_row, candidate_row = live_rows.get(relative), candidate_rows.get(relative)
        if live_row is None or candidate_row is None or live_row.get("mode") != candidate_row.get("mode"):
            crlf_only = False
            continue
        root_name, path = relative.split("/", 1)
        live_root = live_source if root_name == "source" else live_installer
        candidate_root = candidate_source if root_name == "source" else candidate_installer
        live_bytes = (live_root / path).read_bytes()
        candidate_bytes = (candidate_root / path).read_bytes()
        if live_bytes != candidate_bytes and live_bytes.replace(b"\r\n", b"\n") == candidate_bytes:
            crlf_only_paths.append(relative)
        else:
            crlf_only = False
    if (
        live["shippingModeContract"] != candidate["shippingModeContract"]
        or live["devfleetVersion"] != candidate["devfleetVersion"]
        or live["installerVersion"] != candidate["installerVersion"]
    ):
        crlf_only = False
    if crlf_only and len(crlf_only_paths) != len(changed):
        crlf_only = False
    return {
        "lineEndingComparison": "CRLF_ONLY" if crlf_only else ("BYTE_EXACT" if not changed else "SUBSTANTIVE"),
        "materializedChangedPaths": changed,
        "crlfOnlyPaths": crlf_only_paths if crlf_only else [],
        "crlfOnlyMaterialization": crlf_only,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--candidate-commit")
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--installer-root", type=Path)
    parser.add_argument("--artifact", action="append", default=[], metavar="NAME=PATH")
    args = parser.parse_args()
    artifacts: dict[str, Path] = {}
    for value in args.artifact:
        name, separator, raw_path = value.partition("=")
        if not separator or not name or not raw_path:
            parser.error(f"artifact must be NAME=PATH: {value}")
        if name in artifacts:
            parser.error(f"duplicate artifact name: {name}")
        artifacts[name] = Path(raw_path).resolve()
    if artifacts:
        missing = sorted(RELEASE_ARTIFACT_NAMES - set(artifacts))
        unexpected = sorted(set(artifacts) - RELEASE_ARTIFACT_NAMES)
        if missing or unexpected:
            parser.error(f"artifact tuple must be exactly {sorted(RELEASE_ARTIFACT_NAMES)}; missing={missing}; unexpected={unexpected}")
        absent = sorted(name for name, path in artifacts.items() if not path.is_file())
        if absent:
            parser.error(f"artifact paths must be existing files: {absent}")
    if args.source_root and args.installer_root:
        fingerprint = _fingerprint(args.source_root.resolve(), args.installer_root.resolve(), artifacts)
        print(json.dumps({"shippingInputIdentity": _shipping_identity(fingerprint), "releaseFingerprintId": fingerprint["releaseFingerprintId"], "artifacts": fingerprint["artifacts"], "toolingFingerprint": fingerprint["toolingFingerprint"]}, ensure_ascii=False, separators=(",", ":")))
        return 0
    if not args.workspace or not args.candidate_commit:
        parser.error("--workspace and --candidate-commit are required unless --source-root and --installer-root are supplied")
    workspace = args.workspace.resolve()
    live = _fingerprint(workspace / "source", workspace / "installer-source", artifacts)
    candidate, staging = _materialize_candidate(workspace, args.candidate_commit, artifacts)
    try:
        comparison = _materialization_comparison(
            workspace / "source",
            workspace / "installer-source",
            staging / "source",
            staging / "installer-source",
            live,
            candidate,
        )
        candidate_fingerprint = {
            key: value for key, value in candidate.items() if key != "toolingFingerprint"
        }
        payload = {
            "liveShippingInputs": live["shippingInputs"],
            "candidateShippingInputs": candidate["shippingInputs"],
            "liveShippingModeContract": live["shippingModeContract"],
            "candidateShippingModeContract": candidate["shippingModeContract"],
            "liveVersion": live["devfleetVersion"],
            "candidateVersion": candidate["devfleetVersion"],
            "liveInstallerVersion": live["installerVersion"],
            "candidateInstallerVersion": candidate["installerVersion"],
            "liveShippingInputIdentity": _shipping_identity(live),
            "candidateShippingInputIdentity": _shipping_identity(candidate),
            "liveReleaseFingerprintId": live["releaseFingerprintId"],
            "candidateReleaseFingerprintId": candidate["releaseFingerprintId"],
            "artifacts": candidate["artifacts"],
            "candidateFingerprint": candidate_fingerprint,
            "liveToolingFingerprint": live["toolingFingerprint"],
            **comparison,
        }
    finally:
        import shutil
        shutil.rmtree(staging, ignore_errors=True)
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: tools/reconcile_osv_scanner.py

SHA256: 6cb2abed1ebcf7784767c22714f398bd68935bb74ede1b4239c0b512794ab82b | Bytes: 5548 | Git mode: 100644

```
"""Reconcile the custom dependency gate with first-party OSV-Scanner output."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _scanner_packages(payload: dict[str, Any]) -> set[tuple[str, str]]:
    packages: set[tuple[str, str]] = set()
    for result in payload.get("results", []) or []:
        for item in result.get("packages", []) or []:
            package = item.get("package") or {}
            name, version = package.get("name"), package.get("version")
            if name and version:
                packages.add((str(name).lower().replace("_", "-"), str(version)))
    return packages


def _scanner_advisories(payload: dict[str, Any]) -> list[dict[str, str]]:
    found: list[dict[str, str]] = []
    for result in payload.get("results", []) or []:
        for item in result.get("packages", []) or []:
            package = item.get("package") or {}
            for vulnerability in item.get("vulnerabilities", []) or []:
                if isinstance(vulnerability, dict):
                    found.append({
                        "id": str(vulnerability.get("id") or vulnerability.get("aliases", ["unknown"])[0]),
                        "package": str(package.get("name") or ""),
                        "version": str(package.get("version") or ""),
                        "severity": str(vulnerability.get("severity") or "UNKNOWN"),
                    })
    return sorted(found, key=lambda item: (item["package"], item["version"], item["id"]))


def _scanner_version(scanner: Path) -> str:
    completed = subprocess.run([str(scanner), "--version"], capture_output=True, text=True, timeout=30, check=True)
    for line in completed.stdout.splitlines():
        if line.lower().startswith("osv-scanner version:"):
            return line.split(":", 1)[1].strip()
    raise RuntimeError("OSV-Scanner version output was not recognizable")


def reconcile(scanner: Path, lock: Path, custom_report: Path, output: Path) -> dict[str, Any]:
    custom = json.loads(custom_report.read_text(encoding="utf-8"))
    raw_path = output.with_name(output.name + ".scanner-raw.json")
    version = _scanner_version(scanner)
    command = [str(scanner), "scan", "source", "--lockfile", str(lock), "--format", "json", "--all-packages", "--output-file", str(raw_path), "--verbosity", "error"]
    try:
        completed = subprocess.run(command, capture_output=True, text=True, timeout=180)
        try:
            scanner_payload = json.loads(raw_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError) as exc:
            raise RuntimeError(f"OSV-Scanner returned no valid JSON (exit {completed.returncode}): {completed.stderr[-1000:]}") from exc
    finally:
        raw_path.unlink(missing_ok=True)
    custom_packages = {
        (str(item["package"]).lower().replace("_", "-"), str(item["version"]))
        for item in custom.get("packages", [])
    }
    scanner_packages = _scanner_packages(scanner_payload)
    advisories = _scanner_advisories(scanner_payload)
    errors: list[str] = []
    if completed.returncode != 0:
        errors.append(f"OSV-Scanner exit code {completed.returncode}: {completed.stderr[-1000:]}")
    if custom.get("status") != "PASS":
        errors.append(f"custom dependency gate status is {custom.get('status')!r}")
    if custom_packages != scanner_packages:
        errors.append(f"package inventory mismatch: custom_only={sorted(custom_packages - scanner_packages)} scanner_only={sorted(scanner_packages - custom_packages)}")
    if advisories:
        errors.append("independent OSV-Scanner found advisories")
    report = {
        "schema_version": 1,
        "status": "PASS" if not errors else "BLOCKED",
        "scanner": "OSV-Scanner",
        "scanner_version": version,
        "invocation": command,
        "input_lock": str(lock),
        "input_lock_sha256": _sha(lock),
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "package_count": len(scanner_packages),
        "custom_package_count": len(custom_packages),
        "advisories": advisories,
        "custom_blocking_advisories": custom.get("blocking_advisories", []),
        "allowlisted_advisories": [item for item in custom.get("packages", []) if item.get("advisories")],
        "errors": errors,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scanner", type=Path, required=True)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--custom-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = reconcile(args.scanner, args.lock, args.custom_report, args.output)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, RuntimeError) as exc:
        print(json.dumps({"status": "BLOCKED", "error": str(exc)}))
        return 2
    print(json.dumps({"status": report["status"], "packages": report["package_count"], "advisories": len(report["advisories"]), "errors": len(report["errors"])}))
    return 0 if report["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: tools/release-tooling-requirements.txt

SHA256: 78a660089f62dde9ed045e27020e6fd7973a0addfd638e2235d8064dcd083f60 | Bytes: 340 | Git mode: 100644

```
# Release-only dependencies for source/tools/check_dependency_advisories.py.
# These are intentionally not part of the DevFleet product runtime.
packaging==26.3 \
    --hash=sha256:d7193f7c8e4e93f444fde0262bf90af30e16fa0ad0ad44cb553c87339b23cd1c
cvss==3.6 \
    --hash=sha256:e342c6d9c7eb69d2eabbbc2768a03cabd57eb947c806e145de5b936219833ea

```


## FILE: tools/run_portable_audit_tests.py

SHA256: e65e234f040d84909033ce93152a27ba0ee6948c58892cf6bcf9fe6ccb0e90d9 | Bytes: 5249 | Git mode: 100644

```
"""Run the bounded, self-contained test corpus from a clean audit extraction."""
from __future__ import annotations

import argparse
import fnmatch
import importlib.util
import shutil
import json
import subprocess
import sys
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parent
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

from audit_bundle_paths import resolve_bundle_layout


def _classify(path: str, manifest: dict) -> str:
    for category, patterns in manifest.get("categories", {}).items():
        if any(fnmatch.fnmatch(path, pattern) for pattern in patterns):
            return category
    return "UNCLASSIFIED"


def run(root: Path) -> dict:
    root = root.resolve()
    layout = resolve_bundle_layout(root)
    if layout.bundle_root != root:
        raise RuntimeError(f"runner root is not the extracted bundle root: {root}")
    manifest_path = layout.release_tooling_root / "audit-test-manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"audit test manifest is missing: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    if manifest.get("entrypoint") != "release-tooling/run_portable_audit_tests.py":
        raise RuntimeError("audit test manifest entrypoint is not canonical")
    # The portable tests intentionally retain their repository-relative
    # authority imports (ROOT / tools/...).  A clean audit extraction maps
    # release tooling under release-tooling/, so stage only these two
    # non-shipping authority helpers into the temporary extraction root.
    compatibility_root = root / "tools"
    compatibility_root.mkdir(parents=True, exist_ok=True)
    for helper in ("compute_shipping_input_identity.py", "validate_release_bundle.py", "Build-AIAuditBundle.ps1"):
        source_helper = layout.release_tooling_root / helper
        if not source_helper.is_file():
            raise RuntimeError(f"portable authority helper is missing from extraction: {helper}")
        shutil.copy2(source_helper, compatibility_root / helper)
    classifications: dict[str, dict] = {}
    for path in sorted((root / "source/tests").glob("test_*.py")):
        relative = path.relative_to(root).as_posix()
        category = _classify(relative, manifest)
        classifications[relative] = {"category": category, "status": "NOT_RUN", "reason": "not selected by bounded portable corpus"}
    for path in manifest.get("portableTests", []):
        if path not in classifications:
            raise RuntimeError(f"manifest portable test is missing from extraction: {path}")
        classifications[path] = {"category": "portable", "status": "PENDING", "reason": "selected portable test"}
    unclassified = [path for path, record in classifications.items() if record["category"] == "UNCLASSIFIED"]
    if unclassified:
        raise RuntimeError(f"unclassified tests: {unclassified}")
    for path, record in classifications.items():
        if record["status"] == "NOT_RUN":
            record["status"] = "SKIPPED"
            record["reason"] = f"classified {record['category']}; required artifact/platform is not part of portable mode"
    pytest_available = importlib.util.find_spec("pytest") is not None
    if not pytest_available:
        raise RuntimeError("portable test runner requires pytest in the invoking interpreter; no original .venv-test path is used")
    selected = list(manifest["portableTests"])
    completed = subprocess.run([sys.executable, "-m", "pytest", "-q", *selected], cwd=root, capture_output=True, text=True, timeout=300)
    if completed.returncode:
        raise RuntimeError(f"portable pytest collection/test failure (exit {completed.returncode}): {(completed.stdout + completed.stderr)[-4000:]}")
    for path in selected:
        classifications[path]["status"] = "PASS"
        classifications[path]["reason"] = "portable test completed with the invoking interpreter"
    return {
        "schemaVersion": 1,
        "status": "PASS",
        "root": str(root),
        "python": sys.executable,
        "workingDirectory": str(root),
        "portableTests": selected,
        "tests": classifications,
        "unexpectedCollectionFailures": [],
        "explicitSkips": [record for record in classifications.values() if record["status"] == "SKIPPED"],
        "nestedReleaseArchiveAssumption": False,
        "canonicalReleaseToolingResolved": True,
        "originalRepositoryFallback": False,
        "pytestOutput": completed.stdout,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = run(args.root)
    except Exception as exc:  # noqa: BLE001 - structured CLI failure is required
        result = {"schemaVersion": 1, "status": "FAIL", "error": str(exc), "unexpectedCollectionFailures": [str(exc)]}
        print(json.dumps(result, indent=2))
        return 2
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: tools/test_baseline_lineage.py

SHA256: eca3e391c660e57a494a770c0c3b46d438fa631ba299c12d697b7b271b7fa8f6 | Bytes: 19983 | Git mode: 100644

```
"""VM-free transaction tests for exact DevFleet CLEAN baseline adoption."""
import copy
import importlib.util
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from baseline_lineage import adopt, accepted_baseline, rebind
from validate_release_bundle import load_accepted_baseline


VM = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
OLD = '19865b76-4c3a-44f7-ba39-841e9d3c40c9'
NEW = '11111111-2222-4333-8444-555555555555'
TUPLE = {'repositoryHead': '1' * 40, 'candidateBuildCommit': '2' * 40,
         'shippingInputIdentity': '3' * 64, 'releaseFingerprintId': '4' * 64,
         'toolingFingerprintId': '5' * 64, 'candidateSha256': '6' * 64}


class BaselineLineageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        predecessor = self.root / 'audit/agent-memory/attempts/DF-FRESH-CERTIFICATION-20260926-R2/readiness-predecessor.json'
        predecessor.parent.mkdir(parents=True, exist_ok=True)
        predecessor.write_text(json.dumps({'lab': {'l1Id': VM, 'cleanId': OLD},
                                           'liveGuestAuth': {'cleanRestored': True,
                                                             'finalL1State': 'Off'}}), encoding='utf-8')
        self.proposal = {'schemaVersion': 1, 'contract': 'devfleet-baseline-adoption-proposal-v1',
                         'runId': 'r2-owned-baseline-1',
                         'vm': {'name': 'DevFleet-E2E-Win11-01', 'id': VM},
                         'predecessor': {'name': 'DevFleet-E2E-CLEAN', 'id': OLD},
                         'replacement': {'name': 'DevFleet-E2E-CLEAN-R2', 'id': NEW,
                                         'vmId': VM, 'parentSnapshotId': OLD},
                         'predecessorEvidence': {'path': str(predecessor),
                                                 'sha256': hashlib.sha256(predecessor.read_bytes()).hexdigest()},
                         'candidate': copy.deepcopy(TUPLE)}
        self.approval = {'schemaVersion': 1, 'contract': 'devfleet-baseline-adoption-approval-v1',
                         'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                         'vmId': VM, 'predecessorId': OLD, 'replacementId': NEW,
                         'runId': 'r2-owned-baseline-1', 'candidate': copy.deepcopy(TUPLE)}
        self.auth = {'scope': 'CURRENT_RUNNING_GUEST_READ_ONLY',
                     'runId': 'r2-owned-baseline-1', 'connected': True,
                     'status': 'AUTHENTICATED_CURRENT_GUEST_NOT_CLEAN_PROOF',
                     'certificationCredit': False,
                     'observedUtc': '2026-09-27T03:00:00Z',
                     'guest': {'computerName': 'DEVFLEET-E2E-01',
                               'principal': 'DEVFLEET-E2E-01\\E2EAdmin',
                               'accountEnabled': True,
                               'passwordLastSetUtc': '2026-09-27T02:40:00Z',
                               'passwordExpiresUtc': '2026-10-27T02:40:00Z'},
                     'credential': {'storeUser': 'E2EAdmin',
                                    'protectedStoreUpdatedUtc': '2026-09-27T02:45:00Z',
                                    'secretValuesRecorded': False},
                     'nestedL2': {'status': 'ABSENT', 'present': False,
                                  'expectedName': 'DevFleet-E2E-Linux-01',
                                  'exactMatchCount': 0,
                                  'observedUtc': '2026-09-27T02:59:00Z',
                                  'backendInventories': [
                                      {'provider': 'Hyper-V', 'status': 'PASS', 'names': [], 'verification': 'read-only'},
                                      {'provider': 'VirtualBox', 'status': 'PASS', 'names': [], 'verification': 'read-only'}]}}
        self.live = {'scope': 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY',
                     'observedUtc': '2026-09-27T03:05:00Z',
                     'vm': {'name': 'DevFleet-E2E-Win11-01', 'id': VM, 'state': 'Off'},
                     'snapshots': [{'name': 'DevFleet-E2E-CLEAN', 'id': OLD, 'vmId': VM},
                                   {'name': 'DevFleet-E2E-CLEAN-R2', 'id': NEW,
                                    'vmId': VM, 'parentSnapshotId': OLD}]}
        now = datetime.now(timezone.utc)
        stamp = lambda value: value.isoformat()
        self.auth['observedUtc'] = stamp(now - timedelta(minutes=5))
        self.auth['guest']['passwordLastSetUtc'] = stamp(now - timedelta(minutes=20))
        self.auth['guest']['passwordExpiresUtc'] = stamp(now + timedelta(days=30))
        self.auth['credential']['protectedStoreUpdatedUtc'] = stamp(now - timedelta(minutes=10))
        self.auth['nestedL2']['observedUtc'] = stamp(now - timedelta(minutes=6))
        self.live['observedUtc'] = stamp(now - timedelta(minutes=1))
        self.auth['startedUtc'] = stamp(now - timedelta(minutes=7))
        self.auth['vm'] = {'name': 'DevFleet-E2E-Win11-01', 'id': VM}
        self.auth['candidate'] = copy.deepcopy(TUPLE)
        self.ledger = {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2',
                       'activeRunId': None,
                       'attempts': [{'runId': 'r2-owned-baseline-1', 'operation': 'diagnostic',
                                     'state': 'TERMINAL', 'certificationCredit': False,
                                     'tuple': copy.deepcopy(TUPLE), 'exitCode': 0,
                                     'reservedUtc': stamp(now - timedelta(minutes=8)),
                                     'deadlineUtc': stamp(now + timedelta(minutes=5)),
                                     'evidence': [str(self.root / 'auth.json')],
                                     'terminalUtc': stamp(now - timedelta(minutes=2))}]}

    def write(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding='utf-8')
        return path

    def one_diagnostic_ledger(self):
        source = Path(__file__).resolve().parents[1] / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        target = self.root / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        spec = importlib.util.spec_from_file_location('fixture_fresh_attempts', target)
        journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(journal)
        base_auth = self.root / 'base-authorization.md'
        r2_auth = self.root / 'r2-authorization.md'
        d1_auth = self.root / 'd1-authorization.md'
        for path, text in ((base_auth, 'base'), (r2_auth, 'R2'),
                           (d1_auth, 'one extra diagnostic')):
            path.write_text(text, encoding='utf-8')
        base = self.root / 'base-ledger.json'
        r2 = self.root / 'r2-ledger.json'
        successor = self.root / 'successor-ledger.json'
        journal.initialize(base, base_auth, [])
        journal.initialize(r2, r2_auth, [base], journal.POLICY_ID + '-R2')
        for number in range(6):
            request = {'runId': f'diagnostic-{number}', 'operation': 'diagnostic',
                       'owner': {'pid': 1234, 'startUtc': '2026-09-27T00:00:00Z'},
                       'tuple': {'repositoryHead': '1' * 40},
                       'entrypoint': 'readiness.ps1', 'entrypointSha256': '2' * 64,
                       'arguments': [], 'changedCondition': 'bounded fixture',
                       'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
            journal.reserve(r2, request)
            journal.finish(r2, request['runId'], request['owner'], 2, 'TEST_TERMINAL', [])
        journal.initialize(successor, d1_auth, [r2], journal.ONE_DIAGNOSTIC_ID)
        return successor

    def invoke(self, *, proposal=None, approval=None, auth=None, live=None,
               candidate=None, ledger=None, fault=None):
        return adopt(self.root,
                     self.write('proposal.json', self.proposal if proposal is None else proposal),
                     self.write('approval.json', self.approval if approval is None else approval),
                     self.write('auth.json', self.auth if auth is None else auth),
                     self.write('live.json', self.live if live is None else live),
                     self.write('candidate.json', TUPLE if candidate is None else candidate),
                     self.write('ledger.json', self.ledger if ledger is None else ledger),
                     fault=fault)

    def test_valid_transaction_preserves_predecessor_and_no_credit(self):
        self.assertEqual(accepted_baseline(self.root)['id'], OLD)
        receipt = self.invoke()
        selected = accepted_baseline(self.root, TUPLE)
        self.assertEqual(selected['id'], NEW)
        self.assertEqual(selected['predecessorId'], OLD)
        self.assertEqual(selected['receiptSha256'], receipt['receiptSha256'])
        self.assertFalse(receipt['certificationCredit'])
        receipt_path = self.root / 'evidence/baselines/receipts' / receipt['receiptFile']
        self.assertTrue(receipt_path.is_file())
        self.assertEqual(json.loads(receipt_path.read_text())['sources']['predecessorEvidenceSha256'],
                         self.proposal['predecessorEvidence']['sha256'])
        expected = {'repositoryHead': TUPLE['repositoryHead'],
                    'candidateCommit': TUPLE['candidateBuildCommit'],
                    'shippingInputIdentity': TUPLE['shippingInputIdentity'],
                    'releaseFingerprintId': TUPLE['releaseFingerprintId'],
                    'toolingFingerprintId': TUPLE['toolingFingerprintId']}
        self.assertEqual(load_accepted_baseline(self.root, expected,
                                                {'exe': TUPLE['candidateSha256']})['id'], NEW)

    def test_exact_owner_approved_rebind_preserves_v1_chain(self):
        first = self.invoke()
        new_tuple = {**TUPLE, 'repositoryHead': '7' * 40,
                     'toolingFingerprintId': '8' * 64}
        binding_approval = {'schemaVersion': 1,
                            'contract': 'devfleet-baseline-rebind-approval-v1',
                            'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                            'candidate': new_tuple,
                            'replacement': self.proposal['replacement'],
                            'previousReceiptSha256': first['receiptSha256']}
        successor = self.one_diagnostic_ledger()
        with self.assertRaises(ValueError):
            rebind(self.root,
                   self.write('bad-shipping-tuple.json', {**new_tuple, 'shippingInputIdentity': '9' * 64}),
                   self.write('rebind-approval.json', binding_approval), successor,
                   self.write('rebind-live.json', self.live))
        with self.assertRaises(ValueError):
            rebind(self.root, self.write('new-tuple.json', new_tuple),
                   self.write('bad-rebind-approval.json', {**binding_approval, 'decision': 'PENDING'}),
                   successor, self.root / 'rebind-live.json')
        with self.assertRaises(ValueError):
            rebind(self.root, self.root / 'new-tuple.json',
                   self.root / 'rebind-approval.json',
                   self.write('forged-successor.json', {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2-D1',
                                                        'activeRunId': None, 'limits': {'diagnostic': 1},
                                                        'attempts': []}),
                   self.root / 'rebind-live.json')
        rebound = rebind(self.root, self.write('new-tuple.json', new_tuple),
                         self.write('rebind-approval.json', binding_approval),
                         successor,
                         self.write('rebind-live.json', self.live))
        self.assertEqual(rebound['id'], NEW)
        self.assertEqual(rebound['generation'], 2)
        self.assertNotEqual(rebound['receiptSha256'], first['receiptSha256'])
        self.assertEqual(accepted_baseline(self.root, new_tuple)['receiptSha256'],
                         rebound['receiptSha256'])
        expected = {'repositoryHead': new_tuple['repositoryHead'],
                    'candidateCommit': new_tuple['candidateBuildCommit'],
                    'shippingInputIdentity': new_tuple['shippingInputIdentity'],
                    'releaseFingerprintId': new_tuple['releaseFingerprintId'],
                    'toolingFingerprintId': new_tuple['toolingFingerprintId']}
        self.assertEqual(load_accepted_baseline(self.root, expected,
                                                {'exe': new_tuple['candidateSha256']})['receiptSha256'],
                         rebound['receiptSha256'])
        with self.assertRaises(ValueError):
            rebind(self.root, self.root / 'new-tuple.json', self.root / 'rebind-approval.json',
                   successor, self.root / 'rebind-live.json')
        history = next((self.root / 'evidence/baselines/history').glob('*.json'))
        history.write_bytes(history.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            accepted_baseline(self.root, new_tuple)
        with self.assertRaises(ValueError):
            load_accepted_baseline(self.root, expected, {'exe': new_tuple['candidateSha256']})

    def test_independent_release_validator_rejects_rehashed_malformed_receipt(self):
        import hashlib
        receipt_info = self.invoke()
        path = self.root / 'evidence/baselines/receipts' / receipt_info['receiptFile']
        pointer_path = self.root / 'evidence/baselines/CURRENT.json'
        expected = {'repositoryHead': TUPLE['repositoryHead'],
                    'candidateCommit': TUPLE['candidateBuildCommit'],
                    'shippingInputIdentity': TUPLE['shippingInputIdentity'],
                    'releaseFingerprintId': TUPLE['releaseFingerprintId'],
                    'toolingFingerprintId': TUPLE['toolingFingerprintId']}
        original = json.loads(path.read_text())
        for kind in ('schema', 'guid', 'nested', 'secret'):
            with self.subTest(kind=kind):
                receipt = copy.deepcopy(original)
                if kind == 'schema': receipt['schemaVersion'] = 9
                if kind == 'guid': receipt['replacement']['id'] = 'not-a-guid'
                if kind == 'nested': receipt['nestedL2']['backendInventories'][0]['names'] = ['DevFleet-E2E-Linux-01']
                if kind == 'secret': receipt['secretValuesRecorded'] = True
                path.write_text(json.dumps(receipt), encoding='utf-8')
                pointer = json.loads(pointer_path.read_text())
                pointer['receiptSha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
                pointer['checkpoint'] = receipt['replacement']
                pointer_path.write_text(json.dumps(pointer), encoding='utf-8')
                with self.assertRaises(ValueError):
                    load_accepted_baseline(self.root, expected, {'exe': TUPLE['candidateSha256']})

    def test_wrong_missing_ambiguous_checkpoint_and_name_only_rejected(self):
        for kind in ('wrong_vm', 'missing_new', 'duplicate_new', 'name_only', 'wrong_parent'):
            with self.subTest(kind=kind):
                proposal, live = copy.deepcopy(self.proposal), copy.deepcopy(self.live)
                if kind == 'wrong_vm': live['vm']['id'] = '00000000-0000-0000-0000-000000000001'
                if kind == 'missing_new': live['snapshots'].pop()
                if kind == 'duplicate_new': live['snapshots'].append(copy.deepcopy(live['snapshots'][-1]))
                if kind == 'name_only': live['snapshots'][-1]['id'] = OLD
                if kind == 'wrong_parent': live['snapshots'][-1]['parentSnapshotId'] = NEW
                with self.assertRaises(ValueError): self.invoke(proposal=proposal, live=live)
                self.assertEqual(accepted_baseline(self.root)['id'], OLD)

    def test_approval_inventory_expiry_and_tuple_rejected(self):
        for kind in ('unapproved', 'approval_id', 'inventory_missing', 'inventory_present',
                     'expired', 'unknown_expiry', 'tuple', 'guest_identity'):
            with self.subTest(kind=kind):
                approval, auth, candidate = copy.deepcopy(s