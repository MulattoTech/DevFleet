"""VM-free prospective admission tests for the R2 repair-3 policy."""
import importlib.util
import json
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

HERE = pathlib.Path(__file__).resolve().parent


class Repair3SuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.auth = [self.root / name for name in ('base.md', 'r2.md', 'r3.md')]
        for i, path in enumerate(self.auth):
            path.write_text(f'distinct authorization {i}', encoding='utf-8')
        self.base, historical, historical_snapshot, repair1, repair1_snapshot, self.r2, self.r2_snapshot, self.r3, self.receipt = [
            self.root / name for name in ('base.json', 'historical.json', 'historical-snapshot.json',
                                          'repair1.json', 'repair1-snapshot.json', 'r2.json',
                                          'r2-snapshot.json', 'r3.json', 'inspection.json')]
        self.journal.initialize(self.base, self.auth[0], [])
        self.journal.initialize(historical, self.auth[1], [self.base], self.journal.POLICY_ID + '-R2')
        historical_snapshot.write_bytes(historical.read_bytes())
        self.journal.initialize(repair1, self.auth[2], [historical_snapshot, historical], self.journal.REPAIR_ID)
        for index, (operation, classification) in enumerate(self.journal.REPAIR_SEQUENCE):
            request = self.request(operation, f'repair1-{index}')
            self.journal.reserve(repair1, request)
            code = 2 if operation == 'fullrelease' else 0
            self.journal.finish(repair1, request['runId'], request['owner'], code,
                                'NATIVE_FULLRELEASE_BLOCKED' if code else classification, [])
        repair1_snapshot.write_bytes(repair1.read_bytes())
        self.journal.initialize(self.r2, self.auth[1], [repair1_snapshot, repair1], self.journal.REPAIR2_ID)
        self._terminal_repair2()
        self.r2_snapshot.write_bytes(self.r2.read_bytes())
        self.receipt.write_text(json.dumps({
            'schemaVersion': 1,
            'contract': 'devfleet-signed-build-output-inspection-v1',
            'status': 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION',
            'certificationCredit': False,
            'repositoryHead': self.journal.REPAIR3_CANDIDATE_COMMIT,
            'failedAttemptLedgerSha256': self.journal.REPAIR3_FAILED_LEDGER_SHA256,
            'shippingInputIdentity': self.journal.REPAIR3_SHIPPING_SHA256,
            'artifacts': [
                {'name': 'exe', 'path': 'candidate.exe', 'sha256': self.journal.REPAIR3_SIGNED_EXE_SHA256},
                {'name': 'tar', 'path': 'candidate.tar.gz', 'sha256': '2' * 64},
                {'name': 'portable', 'path': 'candidate.zip', 'sha256': '3' * 64},
                {'name': 'installerSource', 'path': 'installer.zip', 'sha256': '4' * 64},
            ],
            'signatureStatus': 'Valid', 'publicPromotionAllowed': False,
            'publicPublisherTrust': False,
        }), encoding='utf-8')
        actual_dir = pathlib.Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work\DevFleet-v1.2.13-development\audit\agent-memory\attempts\DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-2')
        actual_ledger = actual_dir / 'ledger.json'
        actual_receipt = actual_dir / 'signed-build-output-inspection.json'
        self.r2.write_bytes(actual_ledger.read_bytes())
        self.r2_snapshot.write_bytes(actual_ledger.read_bytes())
        self.receipt = actual_receipt

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': self.journal.REPAIR3_CANDIDATE_COMMIT},
                'entrypoint': 'native-test.ps1', 'entrypointSha256': 'b' * 64,
                'arguments': [], 'changedCondition': 'wrapper numeric signatureStatus admission correction',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def _terminal_repair2(self):
        request = self.request('build-sign', 'repair2-build-sign')
        self.journal.reserve(self.r2, request)
        self.journal.finish(self.r2, request['runId'], request['owner'], 2, 'BUILD_SIGN_BLOCKED', [])

    def initialize(self):
        return self.journal.initialize(self.r3, self.auth[2],
                                       [self.r2_snapshot, self.r2], self.journal.REPAIR3_ID,
                                       self.receipt)

    def test_exact_allowance_and_strict_sequence(self):
        status = self.initialize()
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0,
                                               'build-sign': 0})
        with self.assertRaises(ValueError):
            self.journal.reserve(self.r3, self.request('build-sign', 'rebuild'), dry_run=True)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.r3, self.request('diagnostic', 'out-of-order'), dry_run=True)
        for index, (operation, classification) in enumerate(self.journal.REPAIR3_SEQUENCE):
            request = self.request(operation, f'repair3-{index}')
            self.journal.reserve(self.r3, request)
            self.journal.finish(self.r3, request['runId'], request['owner'], 0, classification, [])
        self.assertEqual(self.journal.status(self.r3)['attemptCount'], 5)

    def test_rejects_wrong_predecessor_or_reused_authorization(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.r3, self.auth[2], [self.r2, self.r2], self.journal.REPAIR3_ID, self.receipt)
        with self.assertRaises(ValueError):
            reused = self.journal.load(self.r2)['authorization']['path']
            self.journal.initialize(self.r3, reused, [self.r2_snapshot, self.r2], self.journal.REPAIR3_ID, self.receipt)

    def test_receipt_is_required_and_immutable(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.r3, self.auth[2], [self.r2_snapshot, self.r2], self.journal.REPAIR3_ID)
        tampered = self.root / 'tampered-inspection.json'
        tampered.write_bytes(self.receipt.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'source identity differs'):
            self.journal.initialize(self.r3, self.auth[2],
                                    [self.r2_snapshot, self.r2], self.journal.REPAIR3_ID, tampered)

    def test_substitute_predecessor_is_rejected(self):
        self.initialize()
        self.r2_snapshot.write_bytes(self.r2.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.r3)


if __name__ == '__main__':
    unittest.main()
