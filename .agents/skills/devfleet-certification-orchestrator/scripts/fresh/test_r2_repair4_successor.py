"""VM-free admission checks for a proposed fourth repair successor.

This test copies the terminal native predecessor; it never reserves a live RunId.
"""
import importlib.util
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone


HERE = pathlib.Path(__file__).resolve().parent
NATIVE_REPAIR3 = (HERE.parents[4] / 'audit' / 'agent-memory' / 'attempts'
                  / 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-3' / 'ledger.json')


class Repair4SuccessorTests(unittest.TestCase):
    def setUp(self):
        if not NATIVE_REPAIR3.is_file():
            self.skipTest('Original native repair-3 ledger is unavailable')
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.live = self.root / 'repair3-live.json'
        self.snapshot = self.root / 'repair3-terminal-snapshot.json'
        self.live.write_bytes(NATIVE_REPAIR3.read_bytes())
        self.snapshot.write_bytes(self.live.read_bytes())
        self.authorization = self.root / 'distinct-owner-approval.md'
        self.authorization.write_text('distinct proposed fourth repair authorization', encoding='utf-8')
        self.successor = self.root / 'repair4.json'

    def initialize(self):
        return self.journal.initialize(self.successor, self.authorization,
                                       [self.snapshot, self.live], self.journal.REPAIR4_ID)

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': 'a' * 40},
                'entrypoint': 'reviewed-native-test.ps1', 'entrypointSha256': 'b' * 64,
                'arguments': [], 'changedCondition': 'focused nested Primary readiness diagnosis',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def test_exact_allowance_order_and_no_refund(self):
        status = self.initialize()
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0,
                                               'build-sign': 0})
        with self.assertRaises(ValueError):
            self.journal.reserve(self.successor, self.request('diagnostic', 'out-of-order'), dry_run=True)
        for index, (operation, result) in enumerate(self.journal.REPAIR4_SEQUENCE):
            request = self.request(operation, f'repair4-{index}')
            self.journal.reserve(self.successor, request)
            self.journal.finish(self.successor, request['runId'], request['owner'], 0, result, [])
        self.assertEqual(self.journal.status(self.successor)['attemptCount'], 5)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.successor, self.request('fullrelease', 'extra'), dry_run=True)

    def test_rejects_reused_authorization_and_changed_predecessor(self):
        old_auth = self.journal.load(self.live)['authorization']['path']
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, old_auth,
                                    [self.snapshot, self.live], self.journal.REPAIR4_ID)
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, self.snapshot,
                                    [self.snapshot, self.live], self.journal.REPAIR4_ID)
        self.initialize()
        self.snapshot.write_bytes(self.snapshot.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.successor)

    def test_rejects_wrong_parent_and_distinct_snapshot(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, self.authorization,
                                    [self.live, self.live], self.journal.REPAIR4_ID)
        self.snapshot.write_bytes(self.live.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.initialize()


if __name__ == '__main__':
    unittest.main()
