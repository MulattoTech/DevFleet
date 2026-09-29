# DevFleet source part 125

Full-source UTF-8 byte interval [5766000, 5812500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: f8f6f8ee0dd773112db3051fa2cbbea6f80392bc8002f687db342cfc68b4ab05

<!-- BEGIN SOURCE SLICE -->
est()


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


## FILE: tools/test_baseline_generation3.py

SHA256: 801f0d7885ad41b73112c0025aee5f789d9ec3e4cbb52f650a267bca0af5a2f1 | Bytes: 11201 | Git mode: 100644

```
"""VM-free generation-3 binding tests; no proof or release credit."""
import importlib.util
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import subprocess
import unittest

from baseline_lineage import accepted_baseline, rebind, rebind_gen3
from validate_release_bundle import load_accepted_baseline
from test_baseline_lineage import BaselineLineageTests, TUPLE


class Generation3Tests(unittest.TestCase):
    def setUp(self):
        self.case = BaselineLineageTests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        first = self.case.invoke()
        self.v2_tuple = {**TUPLE, 'repositoryHead': '7' * 40,
                         'toolingFingerprintId': '8' * 64}
        v2_approval = {'schemaVersion': 1, 'contract': 'devfleet-baseline-rebind-approval-v1',
                       'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                       'candidate': self.v2_tuple, 'replacement': self.case.proposal['replacement'],
                       'previousReceiptSha256': first['receiptSha256']}
        d1 = self.case.one_diagnostic_ledger()
        self.v2 = rebind(self.root, self.case.write('v2-tuple.json', self.v2_tuple),
                         self.case.write('v2-approval.json', v2_approval), d1,
                         self.case.write('v2-live.json', self.case.live))
        journal_path = self.root / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        spec = importlib.util.spec_from_file_location('fixture_fresh_attempts', journal_path)
        journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(journal)
        self.journal = journal
        r2 = self.root / 'r2-ledger.json'
        snapshot = self.root / 'repair-r2-snapshot.json'
        snapshot.write_bytes(r2.read_bytes())
        repair_auth = self.root / 'repair-authorization.md'
        repair_auth.write_text('separate owner-approved bounded repair successor', encoding='utf-8')
        self.repair = self.root / 'repair-ledger.json'
        journal.initialize(self.repair, repair_auth, [snapshot, r2], journal.REPAIR_ID)
        self.v3_tuple = {**self.v2_tuple, 'repositoryHead': '9' * 40,
                         'toolingFingerprintId': 'a' * 64}
        owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
        request = {'runId': 'repair-standard-token', 'operation': 'standard-token',
                   'owner': owner, 'tuple': self.v3_tuple, 'entrypoint': 'qualification.ps1',
                   'entrypointSha256': 'c' * 64, 'arguments': [],
                   'changedCondition': 'fixture qualification for exact new tuple',
                   'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
        journal.reserve(self.repair, request)
        qualification = self.case.write('repair-standard-token-result.json',
                                         {'status': 'PASS_NATIVE_STANDARD_TOKEN'})
        journal.finish(self.repair, request['runId'], owner, 0,
                       'PASS_NATIVE_STANDARD_TOKEN', [str(qualification)])
        self.approval = {'schemaVersion': 2, 'contract': 'devfleet-baseline-rebind-approval-v2',
                         'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                         'candidate': self.v3_tuple, 'replacement': self.case.proposal['replacement'],
                         'previousReceiptSha256': self.v2['receiptSha256']}
        self.tuple_path = self.case.write('v3-tuple.json', self.v3_tuple)
        self.approval_path = self.case.write('v3-approval.json', self.approval)
        self.live_path = self.case.write('v3-live.json', self.case.live)

    def bind(self):
        return rebind_gen3(self.root, self.tuple_path, self.approval_path,
                           self.repair, self.live_path)

    def test_exact_approved_generation3_is_independently_accepted(self):
        before = (self.root / 'evidence/baselines/CURRENT.json').read_bytes()
        result = self.bind()
        self.assertEqual(result['generation'], 3)
        self.assertEqual(result['id'], self.case.proposal['replacement']['id'])
        self.assertNotEqual(before, (self.root / 'evidence/baselines/CURRENT.json').read_bytes())
        self.assertEqual(accepted_baseline(self.root, self.v3_tuple)['receiptSha256'],
                         result['receiptSha256'])
        expected = {'repositoryHead': self.v3_tuple['repositoryHead'],
                    'candidateCommit': self.v3_tuple['candidateBuildCommit'],
                    'shippingInputIdentity': self.v3_tuple['shippingInputIdentity'],
                    'releaseFingerprintId': self.v3_tuple['releaseFingerprintId'],
                    'toolingFingerprintId': self.v3_tuple['toolingFingerprintId']}
        self.assertEqual(load_accepted_baseline(self.root, expected,
                                                {'exe': self.v3_tuple['candidateSha256']})['receiptSha256'],
                         result['receiptSha256'])
        with self.assertRaises(ValueError):
            self.bind()

    def test_wrong_approval_or_shipping_change_cannot_update_pointer(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        original = pointer.read_bytes()
        self.approval_path.write_text(json.dumps({**self.approval, 'decision': 'PENDING'}))
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), original)
        self.approval_path.write_text(json.dumps(self.approval))
        self.tuple_path.write_text(json.dumps({**self.v3_tuple, 'shippingInputIdentity': 'b' * 64}))
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), original)

    def test_used_successor_cannot_bind_or_rebind(self):
        journal = self.journal
        request = {'runId': 'repair-used', 'operation': 'diagnostic',
                   'owner': {'pid': 123, 'startUtc': '2026-09-28T00:00:00Z'},
                   'tuple': {'repositoryHead': 'a' * 40}, 'entrypoint': 'native-test.ps1',
                   'entrypointSha256': 'c' * 64, 'arguments': [],
                   'changedCondition': 'fixture', 'deadlineUtc': '2099-01-01T00:00:00Z'}
        journal.reserve(self.repair, request)
        with self.assertRaises(ValueError):
            self.bind()

    def test_failed_developer_qualification_cannot_bind(self):
        ledger = json.loads(self.repair.read_text(encoding='utf-8'))
        ledger['attempts'][0]['classification'] = 'STANDARD_TOKEN_BLOCKED'
        ledger['attempts'][0]['exitCode'] = 2
        self.repair.write_text(json.dumps(ledger), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.bind()

    def test_journal_writer_lock_excludes_concurrent_binding(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        before = pointer.read_bytes()
        with self.journal.locked(self.repair):
            with self.assertRaises(ValueError):
                self.bind()
        self.assertEqual(pointer.read_bytes(), before)

    def test_immutable_qualification_and_inventory_sources_are_required(self):
        self.bind()
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        receipt = json.loads((self.root / 'evidence/baselines/receipts' /
                              pointer['receiptFile']).read_text())
        expected = {'repositoryHead': self.v3_tuple['repositoryHead'],
                    'candidateCommit': self.v3_tuple['candidateBuildCommit'],
                    'shippingInputIdentity': self.v3_tuple['shippingInputIdentity'],
                    'releaseFingerprintId': self.v3_tuple['releaseFingerprintId'],
                    'toolingFingerprintId': self.v3_tuple['toolingFingerprintId']}
        for key in ('successorLedgerSha256', 'nativeInventorySha256'):
            source = self.root / 'evidence/baselines/sources' / (receipt[key] + '.json')
            original = source.read_bytes()
            source.unlink()
            with self.assertRaises(ValueError):
                accepted_baseline(self.root, self.v3_tuple)
            with self.assertRaises(ValueError):
                load_accepted_baseline(self.root, expected,
                                       {'exe': self.v3_tuple['candidateSha256']})
            source.write_bytes(original + b' ')
            with self.assertRaises(ValueError):
                load_accepted_baseline(self.root, expected,
                                       {'exe': self.v3_tuple['candidateSha256']})
            source.write_bytes(original)

    def test_tampered_v2_chain_is_rejected(self):
        self.bind()
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        predecessor = self.root / 'evidence/baselines/history' / (pointer['previousPointerSha256'] + '.json')
        predecessor.write_bytes(predecessor.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            accepted_baseline(self.root, self.v3_tuple)

    def test_powershell_native_reader_accepts_only_exact_v3_tuple(self):
        if not shutil.which('pwsh'):
            self.skipTest('PowerShell 7 is unavailable')
        self.bind()
        tools = self.root / 'tools'
        tools.mkdir(exist_ok=True)
        shutil.copyfile(Path(__file__).with_name('baseline_lineage.py'),
                        tools / 'baseline_lineage.py')
        module = Path(__file__).resolve().parents[1] / 'automation/release-e2e/modules/BaselineLineage.psm1'
        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"
        script = self.root / 'probe-v3.ps1'
        script.write_text(
            "$ErrorActionPreference='Stop'\n"
            f"Import-Module {quote(module)} -Force\n"
            f"$f=Get-Content -Raw -LiteralPath {quote(self.tuple_path)}|ConvertFrom-Json\n"
            "$fp=[pscustomobject]@{repositoryHead=$f.repositoryHead;gitCommit=$f.candidateBuildCommit;"
            "shippingInputIdentity=$f.shippingInputIdentity;releaseFingerprintId=$f.releaseFingerprintId;"
            "toolingFingerprintId=$f.toolingFingerprintId;candidate=[pscustomobject]@{sha256=$f.candidateSha256}}\n"
            f"Get-DevFleetAcceptedBaseline -WorkspaceRoot {quote(self.root)} -Fingerprint $fp|ConvertTo-Json -Depth 6\n",
            encoding='utf-8')
        result = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['generation'], 3)
        wrong = {**self.v3_tuple, 'toolingFingerprintId': 'f' * 64}
        self.tuple_path.write_text(json.dumps(wrong), encoding='utf-8')
        rejected = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)],
                                  capture_output=True, text=True, timeout=20)
        self.assertNotEqual(rejected.returncode, 0)


if __name__ == '__main__':
    unittest.main()

```


## FILE: tools/test_baseline_generation4.py

SHA256: 5fda914ef2dc9fd8978149fe13b2d24d05fbe322a67e6563347908314aa4e72c | Bytes: 14749 | Git mode: 100644

```
"""VM-free generation-4 binding for a distinct signed shipping candidate."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import subprocess
import unittest

from baseline_lineage import accepted_baseline, rebind_gen4
import test_baseline_generation3 as generation3
from validate_release_bundle import load_accepted_baseline


class Generation4Tests(unittest.TestCase):
    def setUp(self):
        self.case = generation3.Generation3Tests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        self.v3 = self.case.bind()
        journal = self.case.journal
        self.journal = journal
        repair1 = self.case.repair
        for index, (operation, classification) in enumerate(journal.REPAIR_SEQUENCE[1:], 1):
            owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
            request = {'runId': f'repair1-{index}', 'operation': operation,
                       'owner': owner, 'tuple': self.case.v3_tuple,
                       'entrypoint': 'fixture.ps1', 'entrypointSha256': 'c' * 64,
                       'arguments': [], 'changedCondition': 'fixture terminal first repair',
                       'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
            journal.reserve(repair1, request)
            blocked = operation == 'fullrelease'
            journal.finish(repair1, request['runId'], owner, 2 if blocked else 0,
                           'NATIVE_FULLRELEASE_BLOCKED' if blocked else classification, [])
        snapshot = self.root / 'repair1-terminal-snapshot.json'
        snapshot.write_bytes(repair1.read_bytes())
        auth = self.root / 'repair2-authorization.md'
        auth.write_text('owner-approved failed build-sign successor', encoding='utf-8')
        repair2 = self.root / 'repair2-ledger.json'
        journal.initialize(repair2, auth, [snapshot, repair1], journal.REPAIR2_ID)
        owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
        request = {'runId': 'repair2-build-sign', 'operation': 'build-sign',
                   'owner': owner, 'tuple': self.case.v3_tuple,
                   'entrypoint': 'fixture.ps1', 'entrypointSha256': 'c' * 64,
                   'arguments': [], 'changedCondition': 'fixture blocked build-sign',
                   'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
        journal.reserve(repair2, request)
        journal.finish(repair2, request['runId'], owner, 2, 'BUILD_SIGN_BLOCKED', [])
        repair2_snapshot = self.root / 'repair2-terminal-snapshot.json'
        repair2_snapshot.write_bytes(repair2.read_bytes())
        self.repair2 = self.root / 'repair3-ledger.json'
        auth3 = self.root / 'repair3-authorization.md'
        auth3.write_text('owner-approved prospective repair3 successor', encoding='utf-8')
        self.v4_tuple = {**self.case.v3_tuple,
                         'repositoryHead': 'b' * 40,
                         'candidateBuildCommit': journal.REPAIR3_CANDIDATE_COMMIT,
                         'shippingInputIdentity': journal.REPAIR3_SHIPPING_SHA256,
                         'releaseFingerprintId': 'd' * 64,
                         'toolingFingerprintId': 'f' * 64,
                         'candidateSha256': journal.REPAIR3_SIGNED_EXE_SHA256}
        self.artifact_receipt = self.root / 'signed-output-inspection.json'
        self.artifact_receipt.write_text(json.dumps({
            'schemaVersion': 1, 'contract': 'devfleet-signed-build-output-inspection-v1',
            'status': 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION',
            'certificationCredit': False, 'repositoryHead': self.v4_tuple['candidateBuildCommit'],
            'failedAttemptLedgerSha256': journal.digest(repair2),
            'shippingInputIdentity': self.v4_tuple['shippingInputIdentity'],
            'artifacts': [
                {'name': 'exe', 'path': 'candidate.exe', 'sha256': self.v4_tuple['candidateSha256']},
                {'name': 'tar', 'path': 'candidate.tar.gz', 'sha256': '2' * 64},
                {'name': 'portable', 'path': 'candidate.zip', 'sha256': '3' * 64},
                {'name': 'installerSource', 'path': 'installer.zip', 'sha256': '4' * 64}],
            'signatureStatus': 'Valid', 'publicPromotionAllowed': False,
            'publicPublisherTrust': False}), encoding='utf-8')
        # The native journal pins the production receipt bytes. This isolated
        # fixture substitutes its own deterministic receipt hash.
        journal.REPAIR3_FAILED_LEDGER_SHA256 = journal.digest(repair2)
        journal.REPAIR3_RECEIPT_SHA256 = journal.digest(self.artifact_receipt)
        native_journal = self.root / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        native_journal.parent.mkdir(parents=True, exist_ok=True)
        source = Path(__file__).resolve().parents[1] / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        native_text = source.read_text(encoding='utf-8')
        native_text = native_text.replace(
            "REPAIR3_FAILED_LEDGER_SHA256 = 'dffe7810cc2f1833ed73a9514a8a49e4d65eed67eac0bf936bf81a1c8d6521ff'",
            f"REPAIR3_FAILED_LEDGER_SHA256 = '{journal.REPAIR3_FAILED_LEDGER_SHA256}'")
        native_text = native_text.replace(
            "REPAIR3_RECEIPT_SHA256 = 'b071752cc2042b3405c05856780f74bbecdc11d0c647c8b602404c73829034b6'",
            f"REPAIR3_RECEIPT_SHA256 = '{journal.REPAIR3_RECEIPT_SHA256}'")
        native_journal.write_text(native_text, encoding='utf-8')
        journal.initialize(self.repair2, auth3, [repair2_snapshot, repair2], journal.REPAIR3_ID,
                           self.artifact_receipt)
        for index, (operation, classification) in enumerate(journal.REPAIR3_SEQUENCE[:1]):
            owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
            request = {'runId': f'repair2-{index}', 'operation': operation,
                       'owner': owner, 'tuple': self.v4_tuple,
                       'entrypoint': 'fixture.ps1', 'entrypointSha256': 'c' * 64,
                       'arguments': [], 'changedCondition': 'fixture new signed candidate',
                       'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
            journal.reserve(self.repair2, request)
            journal.finish(self.repair2, request['runId'], owner, 0, classification,
                           [str(self.case.case.write(f'repair3-{index}-result.json', {'status': 'PASS'}))])
        self.approval = {'schemaVersion': 3, 'contract': 'devfleet-baseline-rebind-approval-v3',
                         'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                         'previousCandidate': self.case.v3_tuple, 'candidate': self.v4_tuple,
                         'shippingChangeApproved': True,
                         'replacement': self.case.case.proposal['replacement'],
                         'previousReceiptSha256': self.v3['receiptSha256']}
        self.tuple_path = self.case.case.write('v4-tuple.json', self.v4_tuple)
        self.approval_path = self.case.case.write('v4-approval.json', self.approval)
        self.live_path = self.case.case.write(
            'v4-live.json', {**self.case.case.live,
                             'observedUtc': datetime.now(timezone.utc).isoformat()})

    def bind(self):
        return rebind_gen4(self.root, self.tuple_path, self.approval_path,
                           self.repair2, self.live_path)

    def validator(self):
        expected = {'repositoryHead': self.v4_tuple['repositoryHead'],
                    'candidateCommit': self.v4_tuple['candidateBuildCommit'],
                    'shippingInputIdentity': self.v4_tuple['shippingInputIdentity'],
                    'releaseFingerprintId': self.v4_tuple['releaseFingerprintId'],
                    'toolingFingerprintId': self.v4_tuple['toolingFingerprintId']}
        return load_accepted_baseline(self.root, expected,
                                      {'exe': self.v4_tuple['candidateSha256']})

    def test_exact_approved_shipping_transition_is_accepted(self):
        result = self.bind()
        self.assertEqual(result['generation'], 4)
        self.assertEqual(result['id'], self.case.case.proposal['replacement']['id'])
        self.assertEqual(accepted_baseline(self.root, self.v4_tuple)['receiptSha256'],
                         result['receiptSha256'])
        self.assertEqual(self.validator()['receiptSha256'], result['receiptSha256'])
        with self.assertRaises(ValueError):
            self.bind()

    def test_missing_approval_and_unchanged_shipping_fail_closed(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        original = pointer.read_bytes()
        self.approval_path.write_text(json.dumps({**self.approval, 'shippingChangeApproved': False}))
        with self.assertRaises(ValueError):
            self.bind()
        self.approval_path.write_text(json.dumps(self.approval))
        self.tuple_path.write_text(json.dumps({**self.v4_tuple,
                                               'shippingInputIdentity': self.case.v3_tuple['shippingInputIdentity']}))
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), original)

    def test_immutable_source_and_predecessor_tamper_rejected(self):
        self.bind()
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        receipt = json.loads((self.root / 'evidence/baselines/receipts' / pointer['receiptFile']).read_text())
        source = self.root / 'evidence/baselines/sources' / (receipt['successorLedgerSha256'] + '.json')
        source.write_bytes(source.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            accepted_baseline(self.root, self.v4_tuple)
        with self.assertRaises(ValueError):
            self.validator()

    def test_packaged_artifact_source_missing_or_tampered_rejected(self):
        self.bind()
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        receipt = json.loads((self.root / 'evidence/baselines/receipts' /
                              pointer['receiptFile']).read_text())
        artifact = self.root / 'evidence/baselines/sources' / (receipt['artifactReceiptSha256'] + '.json')
        original = artifact.read_bytes()
        artifact.unlink()
        with self.assertRaises(ValueError):
            accepted_baseline(self.root, self.v4_tuple)
        artifact.write_bytes(original + b' ')
        with self.assertRaises(ValueError):
            accepted_baseline(self.root, self.v4_tuple)

    def test_tampered_artifact_receipt_and_old_repair2_policy_rejected(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        before = pointer.read_bytes()
        self.artifact_receipt.write_text(self.artifact_receipt.read_text(encoding='utf-8') + ' ',
                                         encoding='utf-8')
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), before)
        self.artifact_receipt.write_text(self.artifact_receipt.read_text(encoding='utf-8').rstrip(),
                                         encoding='utf-8')
        ledger = json.loads(self.repair2.read_text(encoding='utf-8'))
        ledger['policyId'] = self.journal.REPAIR2_ID
        self.repair2.write_text(json.dumps(ledger), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), before)

    def test_extra_native_phase_before_rebind_is_rejected(self):
        owner = {'pid': 321, 'startUtc': datetime.now(timezone.utc).isoformat()}
        request = {'runId': 'repair3-diagnostic-extra', 'operation': 'diagnostic',
                   'owner': owner, 'tuple': self.v4_tuple, 'entrypoint': 'fixture.ps1',
                   'entrypointSha256': 'c' * 64, 'arguments': [],
                   'changedCondition': 'fixture premature extra phase',
                   'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
        self.journal.reserve(self.repair2, request)
        with self.assertRaises(ValueError):
            self.bind()
        self.journal.finish(self.repair2, request['runId'], owner, 0,
                            'PASS_READY_FOR_PROOF_RESERVATION',
                            [str(self.case.case.write('repair3-extra-result.json', {'status': 'PASS'}))])
        with self.assertRaises(ValueError):
            self.bind()

    def test_powershell_reader_requires_exact_new_candidate(self):
        if not shutil.which('pwsh'):
            self.skipTest('PowerShell 7 is unavailable')
        self.bind()
        tools = self.root / 'tools'
        tools.mkdir(exist_ok=True)
        shutil.copyfile(Path(__file__).with_name('baseline_lineage.py'),
                        tools / 'baseline_lineage.py')
        module = Path(__file__).resolve().parents[1] / 'automation/release-e2e/modules/BaselineLineage.psm1'
        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"
        script = self.root / 'probe-v4.ps1'
        script.write_text(
            "$ErrorActionPreference='Stop'\n"
            f"Import-Module {quote(module)} -Force\n"
            f"$f=Get-Content -Raw -LiteralPath {quote(self.tuple_path)}|ConvertFrom-Json\n"
            "$fp=[pscustomobject]@{repositoryHead=$f.repositoryHead;gitCommit=$f.candidateBuildCommit;"
            "shippingInputIdentity=$f.shippingInputIdentity;releaseFingerprintId=$f.releaseFingerprintId;"
            "toolingFingerprintId=$f.toolingFingerprintId;candidate=[pscustomobject]@{sha256=$f.candidateSha256}}\n"
            f"Get-DevFleetAcceptedBaseline -WorkspaceRoot {quote(self.root)} -Fingerprint $fp|ConvertTo-Json -Depth 6\n",
            encoding='utf-8')
        result = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['generation'], 4)
        self.tuple_path.write_text(json.dumps({**self.v4_tuple, 'candidateSha256': 'a' * 64}), encoding='utf-8')
        rejected = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)],
                                  capture_output=True, text=True, timeout=20)
        self.assertNotEqual(rejected.returncode, 0)


if __name__ == '__main__':
    unittest.main()

```


## FILE: tools/test_baseline_generation5.py

SHA256: 597d502646fbbf71f3973c5733683208728e3a915b3bdbdbad48928cb741be5d | Bytes: 8957 | Git mode: 100644

```
"""VM-free generation-5 baseline binding after unchanged-shipping tooling repair."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import subprocess
import unittest

import baseline_lineage
import test_baseline_generation4 as generation4


class Generation5Tests(unittest.TestCase):
    def setUp(self):
        self.case = generation4.Generation4Tests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        self.v4 = self.case.bind()
        self.journal = self.case.journal
        self.v4_tuple = self.case.v4_tuple
        self.v5_tuple = {**self.v4_tuple,
                         'repositoryHead': '9' * 40,
                         'toolingFingerprintId': '8' * 64}
        self._finish_repair3()
        repair3_snapshot = self.root / 'repair3-terminal-snapshot.json'
        repair3_snapshot.write_bytes(self.case.repair2.read_bytes())
        auth4 = self.root / 'repair4-authorization.md'
        auth4.write_text('distinct owner approval for fourth repair', encoding='utf-8')
        repair4 = self.root / 'repair4-ledger.json'
        self.journal.initialize(repair4, auth4,
                                [repair3_snapshot, self.case.repair2], self.journal.REPAIR4_ID)
        self._pass(repair4, 'standard-token', self.v4_tuple, 'repair4-standard-token')
        repair4_snapshot = self.root / 'repair4-terminal-snapshot.json'
        repair4_snapshot.write_bytes(repair4.read_bytes())
        # The production journal pins the exact native predecessor bytes.
        # This isolated fixture substitutes its own deterministic terminal hash.
        self.journal.REPAIR5_PREDECESSOR_SHA256 = self.journal.digest(repair4)
        native_journal = self.root / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        native_text = native_journal.read_text(encoding='utf-8')
        native_text = native_text.replace(
            "REPAIR5_PREDECESSOR_SHA256 = 'bc9401e921754628b95f1f5ceff6308bc3607ae790690cfca786222eadf71ee4'",
            f"REPAIR5_PREDECESSOR_SHA256 = '{self.journal.REPAIR5_PREDECESSOR_SHA256}'")
        native_journal.write_text(native_text, encoding='utf-8')
        auth5 = self.root / 'repair5-authorization.md'
        auth5.write_text('separate owner approval for fifth repair', encoding='utf-8')
        self.repair5 = self.root / 'repair5-ledger.json'
        self.journal.initialize(self.repair5, auth5,
                                [repair4_snapshot, repair4], self.journal.REPAIR5_ID)
        self._pass(self.repair5, 'standard-token', self.v5_tuple, 'repair5-standard-token')
        self.approval = {'schemaVersion': 4, 'contract': 'devfleet-baseline-rebind-approval-v4',
                         'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                         'shippingChangeApproved': False,
                         'previousCandidate': self.v4_tuple, 'candidate': self.v5_tuple,
                         'replacement': self.case.case.case.proposal['replacement'],
                         'previousReceiptSha256': self.v4['receiptSha256']}
        self.tuple_path = self.root / 'generation5-tuple.json'
        self.tuple_path.write_text(json.dumps(self.v5_tuple), encoding='utf-8')
        self.approval_path = self.root / 'generation5-approval.json'
        self.approval_path.write_text(json.dumps(self.approval), encoding='utf-8')
        self.live_path = self.root / 'generation5-native-inventory.json'
        self.live_path.write_text(json.dumps({**self.case.case.case.live,
                                              'observedUtc': datetime.now(timezone.utc).isoformat()}),
                                  encoding='utf-8')

    def _pass(self, ledger, operation, tuple_value, run_id, blocked=False):
        owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
        request = {'runId': run_id, 'operation': operation, 'owner': owner,
                   'tuple': tuple_value, 'entrypoint': 'fixture.ps1',
                   'entrypointSha256': 'c' * 64, 'arguments': [],
                   'changedCondition': 'VM-free lineage fixture',
                   'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
        self.journal.reserve(ledger, request)
        evidence = [str(self.root / (run_id + '-evidence.json'))]
        Path(evidence[0]).write_text('{"status":"PASS"}', encoding='utf-8')
        self.journal.finish(ledger, run_id, owner, 2 if blocked else 0,
                            'NATIVE_FULLRELEASE_BLOCKED' if blocked else
                            dict(self.journal.REPAIR3_SEQUENCE)[operation], evidence)

    def _finish_repair3(self):
        for index, (operation, _) in enumerate(self.journal.REPAIR3_SEQUENCE[1:], 1):
            self._pass(self.case.repair2, operation, self.v4_tuple,
                       f'repair3-{index}', blocked=(operation == 'fullrelease'))

    def bind(self):
        return baseline_lineage.rebind_gen5(self.root, self.tuple_path,
                                            self.approval_path, self.repair5, self.live_path)

    def test_exact_unchanged_shipping_binding_and_hash_chain(self):
        result = self.bind()
        self.assertEqual(result['generation'], 5)
        self.assertEqual(result['id'], self.case.case.case.proposal['replacement']['id'])
        self.assertEqual(baseline_lineage.accepted_baseline(self.root, self.v5_tuple)['receiptSha256'],
                         result['receiptSha256'])
        with self.assertRaises(ValueError):
            self.bind()

    def test_shipping_change_and_missing_approval_fail_closed(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        prior = pointer.read_bytes()
        self.tuple_path.write_text(json.dumps({**self.v5_tuple,
                                               'shippingInputIdentity': '7' * 64}), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.bind()
        self.tuple_path.write_text(json.dumps(self.v5_tuple), encoding='utf-8')
        self.approval_path.write_text(json.dumps({**self.approval, 'decision': 'PENDING'}),
                                      encoding='utf-8')
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), prior)

    def test_immutable_qualification_and_inventory_sources(self):
        self.bind()
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        receipt = json.loads((self.root / 'evidence/baselines/receipts' / pointer['receiptFile']).read_text())
        source = self.root / 'evidence/baselines/sources' / (receipt['successorLedgerSha256'] + '.json')
        source.write_bytes(source.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            baseline_lineage.accepted_baseline(self.root, self.v5_tuple)

    def test_powershell_reader_requires_exact_generation5_tuple(self):
        if not shutil.which('pwsh'):
            self.skipTest('PowerShell 7 is unavailable')
        self.bind()
        tools = self.root / 'tools'
        tools.mkdir(exist_ok=True)
        shutil.copyfile(Path(baseline_lineage.__file__), tools / 'baseline_lineage.py')
        module = Path(__file__).resolve().parents[1] / 'automation/release-e2e/modules/BaselineLineage.psm1'
        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"
        script = self.root / 'probe-v5.ps1'
        script.write_text(
            "$ErrorActionPreference='Stop'\n"
            f"Import-Module {quote(module)} -Force\n"
            f"$f=Get-Content -Raw -LiteralPath {quote(self.tuple_path)}|ConvertFrom-Json\n"
            "$fp=[pscustomobject]@{repositoryHead=$f.repositoryHead;gitCommit=$f.candidateBuildCommit;"
            "shippingInputIdentity=$f.shippingInputIdentity;releaseFingerprintId=$f.releaseFingerprintId;"
            "toolingFingerprintId=$f.toolingFingerprintId;candidate=[pscustomobject]@{sha256=$f.candidateSha256}}\n"
            f"Get-DevFleetAcceptedBaseline -WorkspaceRoot {quote(self.root)} -Fingerprint $fp|ConvertTo-Json -Depth 6\n",
            encoding='utf-8')
        result = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['generation'], 5)
        self.tuple_path.write_text(json.dumps({**self.v5_tuple,
                                               'candidateSha256': 'a' * 64}), encoding='utf-8')
        rejected = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)],
                                  capture_output=True, text=True, timeout=20)
        self.assertNotEqual(rejected.returncode, 0)


if __name__ == '__main__':
    