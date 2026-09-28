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
