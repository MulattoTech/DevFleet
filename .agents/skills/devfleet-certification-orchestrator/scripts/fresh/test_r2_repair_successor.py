"""Fail-closed accounting for one proposed R2 repair successor; no lab access."""
import importlib.util
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

HERE = pathlib.Path(__file__).resolve().parent


class RepairSuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.base_auth = self.root / 'base-authorization.md'
        self.r2_auth = self.root / 'r2-authorization.md'
        self.repair_auth = self.root / 'repair-authorization.md'
        for path, content in ((self.base_auth, 'base owner authorization'),
                              (self.r2_auth, 'R2 owner authorization'),
                              (self.repair_auth, 'separate bounded repair authorization')):
            path.write_text(content, encoding='utf-8')
        self.base = self.root / 'base.json'
        self.r2 = self.root / 'r2.json'
        self.snapshot = self.root / 'r2-terminal-snapshot.json'
        self.repair = self.root / 'r2-repair.json'
        self.journal.initialize(self.base, self.base_auth, [])
        self.journal.initialize(self.r2, self.r2_auth, [self.base], self.journal.POLICY_ID + '-R2')

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': 'a' * 40}, 'entrypoint': 'native-test.ps1',
                'entrypointSha256': 'b' * 64, 'arguments': [],
                'changedCondition': 'bounded repair successor behavioral test',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def initialize(self):
        self.snapshot.write_bytes(self.r2.read_bytes())
        return self.journal.initialize(self.repair, self.repair_auth,
                                       [self.snapshot, self.r2], self.journal.REPAIR_ID)

    def succeed(self, operation, number):
        request = self.request(operation, f'repair-{number}')
        self.journal.reserve(self.repair, request)
        expected = dict(self.journal.REPAIR_SEQUENCE)[operation]
        self.journal.finish(self.repair, request['runId'], request['owner'], 0,
                            expected, [])

    def test_exact_finite_limits_preserve_r2(self):
        before = self.r2.read_bytes()
        status = self.initialize()
        self.assertEqual(self.r2.read_bytes(), before)
        self.assertEqual(self.snapshot.read_bytes(), before)
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0,
                                               'build-sign': 0})
        for operation in ('maintenance', 'build-sign'):
            with self.assertRaises(ValueError):
                self.journal.reserve(self.repair, self.request(operation, operation), dry_run=True)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair, self.request('diagnostic', 'out-of-order'), dry_run=True)
        self.succeed('standard-token', 1)
        self.journal.reserve(self.repair, self.request('diagnostic', 'repair-diagnostic'))
        self.assertEqual(self.journal.status(self.repair)['remaining']['diagnostic'], 0)
        self.assertIsNone(self.journal.status(self.r2)['active'])

    def test_missing_or_reused_authorization_or_wrong_predecessors_rejected(self):
        self.snapshot.write_bytes(self.r2.read_bytes())
        for predecessors, authorization in (([self.snapshot], self.repair_auth),
                                            ([self.r2, self.r2], self.repair_auth),
                                            ([self.snapshot, self.r2], self.r2_auth)):
            with self.assertRaises(ValueError):
                self.journal.initialize(self.repair, authorization,
                                        predecessors, self.journal.REPAIR_ID)

    def test_snapshot_and_live_r2_must_match_and_remain_pinned(self):
        self.snapshot.write_bytes(self.r2.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair, self.repair_auth,
                                    [self.snapshot, self.r2], self.journal.REPAIR_ID)
        self.initialize()
        self.r2.write_bytes(self.r2.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.repair)

    def test_existing_successor_cannot_reset_or_refund(self):
        self.initialize()
        for number, operation in enumerate(('standard-token', 'diagnostic',
                                            'laptop-proof', 'desktop-proof')):
            self.succeed(operation, number)
        request = self.request('fullrelease', 'repair-fullrelease')
        self.journal.reserve(self.repair, request)
        self.journal.finish(self.repair, request['runId'], request['owner'], 2,
                            'BLOCKED', [])
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair, self.repair_auth,
                                    [self.snapshot, self.r2], self.journal.REPAIR_ID)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair,
                                 self.request('fullrelease', 'repair-second'), dry_run=True)

    def test_failed_qualification_blocks_later_phases(self):
        self.initialize()
        request = self.request('standard-token', 'repair-standard-failed')
        self.journal.reserve(self.repair, request)
        self.journal.finish(self.repair, request['runId'], request['owner'], 2,
                            'STANDARD_TOKEN_BLOCKED', [])
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair,
                                 self.request('diagnostic', 'repair-next'), dry_run=True)


if __name__ == '__main__':
    unittest.main()
