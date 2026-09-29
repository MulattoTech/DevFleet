"""VM-free admission checks for a separately authorized fifth repair successor."""
import importlib.util
import json
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone


HERE = pathlib.Path(__file__).resolve().parent
NATIVE_REPAIR4 = (pathlib.Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work'
                               r'\DevFleet-v1.2.13-development') / 'audit' / 'agent-memory'
                  / 'attempts' / 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-4' / 'ledger.json')


class Repair5SuccessorTests(unittest.TestCase):
    def setUp(self):
        if not NATIVE_REPAIR4.is_file():
            self.skipTest('Original native repair-4 ledger is unavailable')
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.live = self.root / 'repair4-live.json'
        self.snapshot = self.root / 'repair4-terminal-snapshot.json'
        self.live.write_bytes(NATIVE_REPAIR4.read_bytes())
        self.snapshot.write_bytes(self.live.read_bytes())
        self.authorization = self.root / 'new-owner-approval.md'
        self.authorization.write_text('distinct prospective fifth repair authorization', encoding='utf-8')
        self.successor = self.root / 'repair5.json'

    def initialize(self):
        return self.journal.initialize(self.successor, self.authorization,
                                       [self.snapshot, self.live], self.journal.REPAIR5_ID)

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': 'a' * 40},
                'entrypoint': 'reviewed-native-test.ps1', 'entrypointSha256': 'b' * 64,
                'arguments': [], 'changedCondition': 'complete generation-5 native binding before qualification',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def test_exact_allowance_and_order(self):
        status = self.initialize()
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0,
                                               'build-sign': 0})
        with self.assertRaises(ValueError):
            self.journal.reserve(self.successor, self.request('diagnostic', 'out-of-order'), dry_run=True)
        for index, (operation, result) in enumerate(self.journal.REPAIR5_SEQUENCE):
            request = self.request(operation, f'repair5-{index}')
            self.journal.reserve(self.successor, request)
            self.journal.finish(self.successor, request['runId'], request['owner'], 0, result, [])
        self.assertEqual(self.journal.status(self.successor)['attemptCount'], 5)

    def test_parent_and_authorization_are_distinct_immutable_sources(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, self.snapshot,
                                    [self.snapshot, self.live], self.journal.REPAIR5_ID)
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, self.authorization,
                                    [self.live, self.live], self.journal.REPAIR5_ID)
        self.initialize()
        self.snapshot.write_bytes(self.snapshot.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.successor)

    def test_no_extra_repair4_attempt_can_be_laundered(self):
        data = self.journal.strict_json(self.live)
        data['attempts'].append(dict(data['attempts'][0], runId='extra-standard-token'))
        self.live.write_text(json.dumps(data), encoding='utf-8')
        self.snapshot.write_bytes(self.live.read_bytes())
        with self.assertRaises(ValueError):
            self.initialize()

    def test_unrelated_qualified_tuple_cannot_replace_exact_repair4(self):
        data = self.journal.strict_json(self.live)
        data['attempts'][0]['tuple']['repositoryHead'] = 'f' * 40
        self.live.write_text(json.dumps(data), encoding='utf-8')
        self.snapshot.write_bytes(self.live.read_bytes())
        with self.assertRaises(ValueError):
            self.initialize()


if __name__ == '__main__':
    unittest.main()
