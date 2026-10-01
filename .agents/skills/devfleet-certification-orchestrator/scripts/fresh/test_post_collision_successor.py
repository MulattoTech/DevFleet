"""Synthetic post-collision accounting tests; no native proof or approval."""
import hashlib
import importlib.util
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
POLICY = 'DF-FRESH-CERTIFICATION-20260930-COLLISION-1'
OLD_POLICY = 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1'
LIMITS = {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
          'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}
KEYS = ('repositoryHead', 'candidateBuildCommit', 'shippingInputIdentity',
        'releaseFingerprintId', 'toolingFingerprintId', 'candidateSha256')
FIRST_ERROR = 'Cannot create a file when that file already exists.'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value), encoding='utf-8')


class PostCollisionSuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts_collision', HERE / 'fresh_attempts.py')
        self.j = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.j)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        # GetTempPath on hosted Windows can return an 8.3 alias; the source
        # validator intentionally rejects noncanonical evidence paths.
        self.root = Path(temp.name).resolve()
        self.ledger = self.root / 'successor.json'
        self.auth = self.root / 'owner.json'
        self.parent = self.root / 'causal-terminal.json'
        self.live_parent = self.root / 'causal-live.json'
        self.old_tuple = dict(zip(KEYS, ('a' * 40, 'b' * 40, 'c' * 64,
                                          'd' * 64, 'e' * 64, 'f' * 64)))
        self.new_tuple = dict(self.old_tuple, repositoryHead='1' * 40,
                              toolingFingerprintId='2' * 64)
        self.failed_run = 'collision-laptop-001'
        self.ancestors = [self.root / name for name in ('r5-snapshot.json', 'r5-live.json',
                                                        'd1-snapshot.json', 'd1-live.json')]
        self.grandparent = self.root / 'r4-ledger.json'
        write(self.grandparent, {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-4',
                                 'activeRunId': None,
                                 'attempts': [{'runId': 'historical-r4-001', 'state': 'TERMINAL'}]})
        r5 = {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5', 'activeRunId': None,
              'attempts': [{'runId': 'historical-r5-001', 'operation': 'laptop-proof', 'state': 'TERMINAL'}],
              'predecessors': [{'path': str(self.grandparent), 'sha256': sha(self.grandparent)}]}
        d1 = {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2-D1', 'activeRunId': None,
              'attempts': [{'runId': 'historical-d1-001', 'operation': 'diagnostic', 'state': 'TERMINAL'}]}
        for path, value in zip(self.ancestors, (r5, r5, d1, d1)):
            write(path, value)
        self.parent_data = {
            'schemaVersion': 1, 'policyId': OLD_POLICY, 'limits': LIMITS,
            'activeRunId': None, 'certificationCredit': False,
            'authorization': {'path': str(self.root / 'old-auth.json'), 'sha256': '3' * 64},
            'predecessors': [{'path': str(path), 'sha256': sha(path)} for path in self.ancestors],
            'attempts': [
                {'runId': 'old-token-001', 'operation': 'standard-token', 'state': 'TERMINAL',
                 'exitCode': 0, 'classification': 'PASS_NATIVE_STANDARD_TOKEN', 'tuple': self.old_tuple},
                {'runId': 'old-diagnostic-001', 'operation': 'diagnostic', 'state': 'TERMINAL',
                 'exitCode': 0, 'classification': 'PASS_READY_FOR_PROOF_RESERVATION', 'tuple': self.old_tuple},
                {'runId': self.failed_run, 'operation': 'laptop-proof', 'state': 'TERMINAL',
                 'exitCode': 2, 'classification': 'NATIVE_LAPTOP_PROOF_BLOCKED', 'tuple': self.old_tuple},
            ],
        }
        write(self.parent, self.parent_data)
        self.live_parent.write_bytes(self.parent.read_bytes())
        self.sha_patch = patch.object(self.j, 'COLLISION_PREDECESSOR_SHA256', sha(self.parent), create=True)
        self.sha_patch.start()
        self.addCleanup(self.sha_patch.stop)
        self.ledger_path_patch = patch.object(self.j, 'COLLISION_LEDGER_PATH', self.ledger, create=True)
        self.ledger_path_patch.start()
        self.addCleanup(self.ledger_path_patch.stop)
        self.live_path_patch = patch.object(self.j, 'COLLISION_LIVE_CAUSAL_PATH', self.live_parent, create=True)
        self.live_path_patch.start()
        self.addCleanup(self.live_path_patch.stop)
        self.receipt = self.root / 'gen6-receipt.json'
        self.owner_message = self.root / 'owner-message.txt'
        self.owner_message.write_text(
            'I explicitly authorize exactly one new post-collision prospective certification successor named '
            + POLICY + '\nstandard-token = 1\ndiagnostic/readiness = 1\nlaptop-proof = 1\n'
            'desktop-proof = 1\nfullrelease = 1\nmaintenance = 0\nbuild-sign = 0\n'
            'I do not authorize any refund, replay, reopening, deletion, modification or reclassification '
            'of CAUSAL-1 or any earlier attempt. This authorization approves no signed-shipping change.',
            encoding='utf-8')
        self.owner_sha_patch = patch.object(self.j, 'COLLISION_OWNER_AUTH_SHA256', sha(self.owner_message), create=True)
        self.owner_sha_patch.start()
        self.addCleanup(self.owner_sha_patch.stop)
        self.checkpoint = {'name': 'DevFleet-E2E-CLEAN-R2', 'id': 'checkpoint-id'}
        write(self.receipt, {'schemaVersion': 6, 'contract': 'devfleet-baseline-rebind-receipt-v6',
                             'status': 'REBOUND', 'certificationCredit': False,
                             'candidate': self.old_tuple, 'replacement': self.checkpoint})
        self.proposal = self.root / 'proposal.json'
        self.source = self.root / 'source.json'
        write(self.proposal, {'failedRunId': self.failed_run, 'previousCandidate': self.old_tuple,
                              'candidate': self.new_tuple})
        write(self.source, {'failedRunId': self.failed_run, 'previousCandidate': self.old_tuple,
                            'candidate': self.new_tuple})
        self.wrapper = self.root / 'wrapper.json'
        self.proof_error = self.root / 'proof-error.json'
        self.cleanup = self.root / 'cleanup.json'
        write(self.wrapper, {'runId': self.failed_run, 'classification': 'NATIVE_LAPTOP_PROOF_BLOCKED',
                             'exitCode': 2, 'firstTechnicalFailure': FIRST_ERROR,
                             'observerTerminal': 'NO_PROGRESS_TIMEOUT'})
        write(self.proof_error, {'runId': self.failed_run, 'status': 'BLOCKED', 'error': FIRST_ERROR})
        self.cleanup_data = {'runId': self.failed_run, 'status': 'PASS', 'runOwnedOnly': True,
                             'l1': {'name': 'DevFleet-E2E-Win11-01',
                                    'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2', 'status': 'OFF'},
                             'l2': {'expectedName': 'DevFleet-E2E-Linux-01', 'present': False,
                                    'exactMatchCount': 0, 'inventoryCount': 0, 'status': 'ABSENT'},
                             'l2Present': False}
        write(self.cleanup, self.cleanup_data)
        ref = lambda path: {'path': str(path), 'sha256': sha(path)}
        self.auth_data = {
            'schemaVersion': 1, 'kind': 'DEVFLEET_POST_COLLISION_SUCCESSOR_AUTHORIZATION',
            'policyId': POLICY, 'approved': True, 'approvedBy': 'ACCOUNT_OWNER',
            'successorLedgerPath': str(self.ledger),
            'predecessorSha256': {'causal1': sha(self.parent)},
            'failedRunId': self.failed_run, 'previousCandidate': self.old_tuple,
            'candidate': self.new_tuple,
            'generation6': {'receiptPath': str(self.receipt), 'receiptSha256': sha(self.receipt),
                            'checkpoint': self.checkpoint},
            'reviewedSources': {'proposal': ref(self.proposal), 'source': ref(self.source)},
            'failureEvidence': {'wrapper': ref(self.wrapper), 'proofError': ref(self.proof_error),
                                'cleanup': ref(self.cleanup)},
            'limits': LIMITS,
        }
        self.auth_data['ownerAuthorization'] = {'path': str(self.owner_message), 'sha256': sha(self.owner_message)}
        write(self.auth, self.auth_data)

    def initialize(self):
        return self.j.initialize(self.ledger, self.auth, [self.parent], POLICY)

    def request(self, operation='standard-token', run_id='new-token-001', candidate=None):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': candidate or self.new_tuple, 'entrypoint': 'synthetic-native-wrapper.ps1',
                'entrypointSha256': '4' * 64, 'arguments': [], 'changedCondition': 'reviewed collision correction',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat()}

    def test_positive_exact_authorization_and_finite_sequence(self):
        self.assertEqual(self.initialize()['remaining'], LIMITS)
        with self.assertRaises(ValueError):
            self.j.reserve(self.ledger, self.request('laptop-proof'), dry_run=True)
        sequence = [('standard-token', 'PASS_NATIVE_STANDARD_TOKEN'),
                    ('diagnostic', 'PASS_READY_FOR_PROOF_RESERVATION'),
                    ('laptop-proof', 'NATIVE_LAPTOP_PROOF_PASS'),
                    ('desktop-proof', 'NATIVE_DESKTOP_PROOF_PASS'),
                    ('fullrelease', 'NATIVE_FULLRELEASE_PASS')]
        for index, (op, classification) in enumerate(sequence):
            req = self.request(op, 'new-' + str(index))
            self.j.reserve(self.ledger, req)
            self.j.finish(self.ledger, req['runId'], req['owner'], 0, classification, ['synthetic-evidence'])
        self.assertEqual(self.j.status(self.ledger)['remaining'], {key: 0 for key in LIMITS})
        self.assertFalse(self.j.status(self.ledger)['certificationCredit'])

    def test_predecessor_wrong_hash_run_or_failed_phase_rejected(self):
        for mutate in (
            lambda: self.parent_data['attempts'][2].update(runId='other'),
            lambda: self.parent_data['attempts'][2].update(classification='NATIVE_LAPTOP_PROOF_PASS'),
            lambda: self.parent_data.update(activeRunId=self.failed_run),
        ):
            original = json.loads(json.dumps(self.parent_data))
            mutate()
            write(self.parent, self.parent_data)
            with patch.object(self.j, 'COLLISION_PREDECESSOR_SHA256', sha(self.parent)):
                with self.assertRaises(ValueError):
                    self.initialize()
            self.parent_data = original
            write(self.parent, original)

    def test_wrong_ledger_location_and_duplicate_source_rejected(self):
        self.auth_data['successorLedgerPath'] = str(self.root / 'other.json')
        write(self.auth, self.auth_data)
        with self.assertRaises(ValueError):
            self.initialize()
        self.auth_data['successorLedgerPath'] = str(self.ledger)
        self.auth_data['reviewedSources']['source'] = self.auth_data['reviewedSources']['proposal']
        write(self.auth, self.auth_data)
        with self.assertRaises(ValueError):
            self.initialize()

    def test_widened_limits_changed_shipping_or_unchanged_tooling_rejected(self):
        for change in ('limits', 'shipping', 'tooling'):
            original = json.loads(json.dumps(self.auth_data))
            if change == 'limits': self.auth_data['limits']['laptop-proof'] = 2
            if change == 'shipping': self.auth_data['candidate']['candidateSha256'] = '9' * 64
            if change == 'tooling': self.auth_data['candidate']['toolingFingerprintId'] = self.old_tuple['toolingFingerprintId']
            write(self.auth, self.auth_data)
            with self.assertRaises(ValueError):
                self.initialize()
            self.auth_data = original

    def test_mutated_evidence_and_auth_rejected_at_load(self):
        self.initialize()
        self.wrapper.write_bytes(self.wrapper.read_bytes() + b' ')
        with self.assertRaises(ValueError): self.j.status(self.ledger)
        self.wrapper.write_bytes(self.wrapper.read_bytes()[:-1])
        self.auth.write_bytes(self.auth.read_bytes() + b' ')
        with self.assertRaises(ValueError): self.j.status(self.ledger)

    def test_historical_run_id_and_tuple_drift_rejected(self):
        self.initialize()
        with self.assertRaises(ValueError):
            self.j.reserve(self.ledger, self.request(run_id=self.failed_run), dry_run=True)
        with self.assertRaises(ValueError):
            self.j.reserve(self.ledger, self.request(candidate=dict(self.new_tuple, repositoryHead='8' * 40)), dry_run=True)
        req = self.request()
        self.j.reserve(self.ledger, req)
        record = json.loads(self.ledger.read_text())
        record['attempts'][0]['tuple']['toolingFingerprintId'] = '8' * 64
        write(self.ledger, record)
        with self.assertRaises(ValueError): self.j.status(self.ledger)

    def test_failed_prerequisite_cannot_advance(self):
        self.initialize()
        req = self.request()
        self.j.reserve(self.ledger, req)
        self.j.finish(self.ledger, req['runId'], req['owner'], 2, 'NATIVE_STANDARD_TOKEN_BLOCKED', [])
        with self.assertRaises(ValueError):
            self.j.reserve(self.ledger, self.request('diagnostic', 'new-diagnostic'))

    def test_collision_evidence_must_keep_first_error_and_exact_cleanup(self):
        for path, replacement in (
            (self.wrapper, {'runId': self.failed_run, 'classification': 'NATIVE_LAPTOP_PROOF_BLOCKED',
                            'exitCode': 2, 'observerTerminal': 'NO_PROGRESS_TIMEOUT'}),
            (self.proof_error, {'runId': self.failed_run, 'status': 'BLOCKED'}),
            (self.cleanup, {'runId': self.failed_run, 'status': 'PASS', 'note': 'OFF ABSENT'}),
            (self.wrapper, {'classification': 'NATIVE_LAPTOP_PROOF_BLOCKED', 'exitCode': 2,
                            'firstTechnicalFailure': FIRST_ERROR, 'observerTerminal': 'NO_PROGRESS_TIMEOUT'}),
            (self.cleanup, dict(self.cleanup_data, runOwnedOnly=False)),
            (self.cleanup, dict(self.cleanup_data, l2=dict(self.cleanup_data['l2'], exactMatchCount=1))),
        ):
            original = path.read_bytes()
            write(path, replacement)
            key = {self.wrapper: 'wrapper', self.proof_error: 'proofError', self.cleanup: 'cleanup'}[path]
            self.auth_data['failureEvidence'][key]['sha256'] = sha(path)
            write(self.auth, self.auth_data)
            with self.assertRaises(ValueError): self.initialize()
            path.write_bytes(original)
            self.auth_data['failureEvidence'][key]['sha256'] = sha(path)

    def test_owner_or_generation6_receipt_mutation_blocks_existing_ledger(self):
        self.initialize()
        for source in (self.owner_message, self.receipt, self.proposal, self.source,
                       self.proof_error, self.cleanup, self.parent):
            source.write_bytes(source.read_bytes() + b' ')
            with self.assertRaises(ValueError): self.j.status(self.ledger)
            source.write_bytes(source.read_bytes()[:-1])

    def test_ancestor_run_ids_and_frozen_live_ancestor_drift_rejected(self):
        self.initialize()
        for run_id in ('historical-r5-001', 'historical-d1-001', 'historical-r4-001'):
            with self.assertRaises(ValueError):
                self.j.reserve(self.ledger, self.request(run_id=run_id), dry_run=True)
        self.ancestors[1].write_bytes(self.ancestors[1].read_bytes() + b' ')
        with self.assertRaises(ValueError): self.j.status(self.ledger)

    def test_authoritative_live_causal_drift_rejected_after_snapshot(self):
        self.initialize()
        self.live_parent.write_bytes(self.live_parent.read_bytes() + b' ')
        with self.assertRaises(ValueError): self.j.status(self.ledger)

    def test_second_authorization_cannot_target_another_ledger(self):
        second = self.root / 'second-ledger.json'
        second_auth = self.root / 'second-owner.json'
        altered = json.loads(json.dumps(self.auth_data))
        altered['successorLedgerPath'] = str(second)
        write(second_auth, altered)
        with self.assertRaises(ValueError):
            self.j.initialize(second, second_auth, [self.parent], POLICY)
        self.assertFalse(second.exists())


if __name__ == '__main__': unittest.main()
