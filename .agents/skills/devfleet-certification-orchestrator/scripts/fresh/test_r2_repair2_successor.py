"""VM-free fail-closed admission for one new signed-candidate repair successor."""
import importlib.util
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

HERE = pathlib.Path(__file__).resolve().parent


class Repair2SuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.auth = [self.root / name for name in ('base-auth.md', 'r2-auth.md', 'repair1-auth.md', 'repair2-auth.md')]
        for index, path in enumerate(self.auth):
            path.write_text(f'distinct owner authorization {index}', encoding='utf-8')
        self.base, self.r2, self.r2_snapshot, self.repair1, self.repair1_snapshot, self.repair2 = [
            self.root / name for name in ('base.json', 'r2.json', 'r2-snapshot.json', 'repair1.json', 'repair1-snapshot.json', 'repair2.json')
        ]
        self.journal.initialize(self.base, self.auth[0], [])
        self.journal.initialize(self.r2, self.auth[1], [self.base], self.journal.POLICY_ID + '-R2')
        self.r2_snapshot.write_bytes(self.r2.read_bytes())
        self.journal.initialize(self.repair1, self.auth[2], [self.r2_snapshot, self.r2], self.journal.REPAIR_ID)

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': 'a' * 40}, 'entrypoint': 'native-test.ps1',
                'entrypointSha256': 'b' * 64, 'arguments': [],
                'changedCondition': 'new signed candidate after fail-closed permanent-delete block',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def terminal_repair1(self):
        for index, (operation, classification) in enumerate(self.journal.REPAIR_SEQUENCE):
            request = self.request(operation, f'repair1-{index}')
            self.journal.reserve(self.repair1, request)
            code = 2 if operation == 'fullrelease' else 0
            result = 'NATIVE_FULLRELEASE_BLOCKED' if code else classification
            self.journal.finish(self.repair1, request['runId'], request['owner'], code, result, [])
        self.repair1_snapshot.write_bytes(self.repair1.read_bytes())

    def test_terminal_predecessor_and_exact_allowance(self):
        self.terminal_repair1()
        prior = self.repair1.read_bytes()
        status = self.journal.initialize(self.repair2, self.auth[3],
                                         [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        self.assertEqual(self.repair1.read_bytes(), prior)
        self.assertEqual(self.repair1_snapshot.read_bytes(), prior)
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0, 'build-sign': 1})
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair2, self.request('standard-token', 'out-of-order'), dry_run=True)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair2, self.request('maintenance', 'disallowed'), dry_run=True)
        request = self.request('build-sign', 'new-build')
        self.journal.reserve(self.repair2, request)
        self.journal.finish(self.repair2, request['runId'], request['owner'], 0,
                            'PASS_NATIVE_BUILD_SIGN', [])
        self.assertEqual(self.journal.status(self.repair2)['remaining']['build-sign'], 0)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair2, self.request('build-sign', 'second-build'), dry_run=True)

    def test_predecessor_or_authorization_drift_fails_closed(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair2, self.auth[3], [self.repair1, self.repair1], self.journal.REPAIR2_ID)
        self.terminal_repair1()
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair2, self.auth[2], [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        self.repair1_snapshot.write_bytes(self.repair1_snapshot.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair2, self.auth[3], [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        self.repair1_snapshot.write_bytes(self.repair1.read_bytes())
        self.journal.initialize(self.repair2, self.auth[3], [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        self.repair1.write_bytes(self.repair1.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.repair2)

    def test_failed_build_sign_blocks_qualification(self):
        self.terminal_repair1()
        self.journal.initialize(self.repair2, self.auth[3], [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        request = self.request('build-sign', 'failed-build')
        self.journal.reserve(self.repair2, request)
        self.journal.finish(self.repair2, request['runId'], request['owner'], 2, 'BUILD_SIGN_BLOCKED', [])
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair2, self.request('standard-token', 'qualification'), dry_run=True)


if __name__ == '__main__':
    unittest.main()
