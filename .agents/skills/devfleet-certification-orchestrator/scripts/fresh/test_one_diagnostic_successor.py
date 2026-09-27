import importlib.util
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone


HERE = pathlib.Path(__file__).parent


class OneDiagnosticSuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.base_auth = self.root / 'base-auth.md'
        self.r2_auth = self.root / 'r2-auth.md'
        self.d1_auth = self.root / 'one-diagnostic-auth.md'
        for path, value in ((self.base_auth, 'base'), (self.r2_auth, 'r2'),
                            (self.d1_auth, 'one additional diagnostic only')):
            path.write_text(value, encoding='utf-8')
        self.base = self.root / 'base.json'
        self.r2 = self.root / 'r2.json'
        self.d1 = self.root / 'r2-d1.json'
        self.journal.initialize(self.base, self.base_auth, [])
        self.journal.initialize(self.r2, self.r2_auth, [self.base], self.journal.POLICY_ID + '-R2')

    def request(self, number, operation='diagnostic'):
        return {'runId': f'diagnostic-{number}', 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': '2026-09-27T00:00:00Z'},
                'tuple': {'repositoryHead': 'a' * 40}, 'entrypoint': 'readiness.ps1',
                'entrypointSha256': 'b' * 64, 'arguments': [],
                'changedCondition': 'independent bounded test',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def exhaust_r2(self):
        for number in range(6):
            request = self.request(number)
            self.journal.reserve(self.r2, request)
            self.journal.finish(self.r2, request['runId'], request['owner'], 2, 'TEST_TERMINAL', [])

    def test_only_one_diagnostic_and_no_other_operations(self):
        self.exhaust_r2()
        original = self.r2.read_bytes()
        self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.assertEqual(self.r2.read_bytes(), original)
        remaining = self.journal.status(self.d1)['remaining']
        self.assertEqual(remaining['diagnostic'], 1)
        self.assertTrue(all(value == 0 for key, value in remaining.items() if key != 'diagnostic'))
        with self.assertRaises(ValueError):
            self.journal.reserve(self.d1, self.request(11, 'laptop-proof'), dry_run=True)
        first = self.request(12)
        self.journal.reserve(self.d1, first)
        self.journal.finish(self.d1, first['runId'], first['owner'], 2, 'TEST_TERMINAL', [])
        self.assertEqual(self.journal.status(self.d1)['remaining']['diagnostic'], 0)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.d1, self.request(13), dry_run=True)

    def test_requires_exhausted_terminal_r2_and_separate_authorization(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.exhaust_r2()
        with self.assertRaises(ValueError):
            self.journal.initialize(self.d1, self.r2_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        with self.assertRaises(ValueError):
            self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)

    def test_predecessor_bytes_are_pinned(self):
        self.exhaust_r2()
        self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.r2.write_bytes(self.r2.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.d1)


if __name__ == '__main__':
    unittest.main()
