"""Synthetic accounting fixtures only; never native owner approval or proof."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

POLICY = 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1'
LIMITS = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
          'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
SEQUENCE = [('standard-token', 'PASS_NATIVE_STANDARD_TOKEN'),
            ('diagnostic', 'PASS_READY_FOR_PROOF_RESERVATION'),
            ('laptop-proof', 'NATIVE_LAPTOP_PROOF_PASS'),
            ('desktop-proof', 'NATIVE_DESKTOP_PROOF_PASS'),
            ('fullrelease', 'NATIVE_FULLRELEASE_PASS')]


class CausalSuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('causal_journal', Path(__file__).with_name('fresh_attempts.py'))
        self.j = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.j)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.ledger = self.root / 'new-ledger.json'
        self.auth = self.root / 'owner.json'
        self.parents = [self.root / name for name in ('r5-snapshot.json', 'r5-live.json', 'd1-snapshot.json', 'd1-live.json')]
        prior = {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5',
                 'activeRunId': None, 'authorization': {'sha256': 'e' * 64},
                 'attempts': [{'operation': op, 'state': 'TERMINAL', 'exitCode': code, 'classification': result}
                              for op, code, result in [('standard-token', 0, 'PASS_NATIVE_STANDARD_TOKEN'),
                                                      ('diagnostic', 0, 'PASS_READY_FOR_PROOF_RESERVATION'),
                                                      ('laptop-proof', 2, 'NATIVE_LAPTOP_PROOF_BLOCKED')]]}
        diag = {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2-D1', 'activeRunId': None,
                'authorization': {'sha256': 'f' * 64},
                'attempts': [{'operation': 'diagnostic', 'state': 'TERMINAL', 'exitCode': 0,
                              'classification': 'DIAGNOSTIC_IMAGE_REMOTE_FAILURE_NOT_REPRODUCED'}]}
        for p, value in zip(self.parents, (prior, prior, diag, diag)):
            p.write_text(json.dumps(value), encoding='utf-8')
        self.auth_data = {'schemaVersion': 1, 'kind': 'DEVFLEET_CAUSAL_SUCCESSOR_AUTHORIZATION',
                          'policyId': POLICY, 'approved': True, 'limits': LIMITS,
                          'predecessorSha256': {'r5': self.sha(self.parents[0]), 'imageD1': self.sha(self.parents[2])}}
        self.write_auth()
        # Old-ledger recursive lineage is a separately tested boundary. This
        # portable fixture substitutes only that boundary; new accounting,
        # authorization/hash checks, reservation and finalization remain real.
        real_load = self.j.load
        def parent_boundary(path):
            if Path(path).absolute() in self.parents:
                return json.loads(Path(path).read_text(encoding='utf-8'))
            return real_load(path)
        self.addCleanup(patch.stopall)
        patch.object(self.j, 'load', side_effect=parent_boundary).start()

    @staticmethod
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def write_auth(self):
        self.auth.write_text(json.dumps(self.auth_data), encoding='utf-8')

    def initialize(self):
        return self.j.initialize(self.ledger, self.auth, self.parents, POLICY)

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': 'a' * 40}, 'entrypoint': 'synthetic-native-wrapper.ps1',
                'entrypointSha256': 'b' * 64, 'arguments': [],
                'changedCondition': 'Approved passive cold-launch coverage; synthetic fixture only',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat()}

    def test_ordered_finite_sequence_and_no_extra_capacity(self):
        self.assertEqual(self.initialize()['remaining'], LIMITS)
        for op in ('laptop-proof', 'desktop-proof', 'fullrelease', 'build-sign', 'maintenance'):
            with self.assertRaises(ValueError):
                self.j.reserve(self.ledger, self.request(op, 'denied-' + op), dry_run=True)
        for index, (op, result) in enumerate(SEQUENCE):
            request = self.request(op, 'causal-' + str(index))
            self.j.reserve(self.ledger, request)
            self.j.finish(self.ledger, request['runId'], request['owner'], 0, result, [])
        self.assertEqual(self.j.status(self.ledger)['remaining'], {op: 0 for op in LIMITS})
        with self.assertRaises(ValueError):
            self.j.reserve(self.ledger, self.request('laptop-proof', 'replay'))

    def test_unapproved_or_widened_authorization_cannot_create_ledger(self):
        for field, value in [('approved', False), ('limits', dict(LIMITS, diagnostic=2)), ('policyId', 'unrelated')]:
            original = self.auth_data[field]
            self.auth_data[field] = value
            self.write_auth()
            with self.assertRaises(ValueError):
                self.initialize()
            self.assertFalse(self.ledger.exists())
            self.auth_data[field] = original

    def test_snapshot_drift_and_wrong_predecessor_reject(self):
        self.parents[0].write_bytes(self.parents[0].read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.initialize()
        self.parents[0].write_bytes(self.parents[1].read_bytes())
        data = json.loads(self.parents[2].read_text())
        data['activeRunId'] = 'owned-active-diagnostic'
        for p in self.parents[2:]:
            p.write_text(json.dumps(data), encoding='utf-8')
        self.auth_data['predecessorSha256']['imageD1'] = self.sha(self.parents[2])
        self.write_auth()
        with self.assertRaises(ValueError):
            self.initialize()

    def test_owner_authorization_and_predecessors_remain_immutable(self):
        self.initialize()
        self.auth.write_bytes(self.auth.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.j.status(self.ledger)
        self.write_auth()
        self.parents[3].write_bytes(self.parents[3].read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.j.status(self.ledger)

    def test_failed_or_active_attempt_cannot_advance_or_refund(self):
        self.initialize()
        request = self.request('standard-token', 'first')
        self.j.reserve(self.ledger, request)
        with self.assertRaises(ValueError):
            self.j.reserve(self.ledger, self.request('diagnostic', 'overlap'))
        self.j.finish(self.ledger, 'first', request['owner'], 2, 'NATIVE_STANDARD_TOKEN_BLOCKED', [])
        for op in ('standard-token', 'diagnostic'):
            with self.assertRaises(ValueError):
                self.j.reserve(self.ledger, self.request(op, 'after-failure-' + op))

    def test_duplicate_parent_or_authorization_alias_reject(self):
        with self.assertRaises(ValueError):
            self.j.initialize(self.ledger, self.auth, [self.parents[0]] * 4, POLICY)
        with self.assertRaises(ValueError):
            self.j.initialize(self.ledger, self.parents[0], self.parents, POLICY)


if __name__ == '__main__':
    unittest.main()
