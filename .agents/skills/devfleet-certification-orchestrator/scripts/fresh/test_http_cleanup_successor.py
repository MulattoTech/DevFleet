"""HTTP-cleanup successor policy admission tests; no native execution."""
import importlib.util
import hashlib
import json
from pathlib import Path
from unittest.mock import patch
import unittest

HERE = Path(__file__).resolve().parent
POLICY = 'DF-FRESH-CERTIFICATION-20261001-HTTP-CLEANUP-1'
EXPECTED_LIMITS = {
    'standard-token': 1,
    'diagnostic': 1,
    'laptop-proof': 1,
    'desktop-proof': 1,
    'fullrelease': 1,
    'maintenance': 0,
    'build-sign': 0,
}
EXPECTED_SEQUENCE = (
    ('standard-token', 'PASS_NATIVE_STANDARD_TOKEN'),
    ('diagnostic', 'PASS_READY_FOR_PROOF_RESERVATION'),
    ('laptop-proof', 'NATIVE_LAPTOP_PROOF_PASS'),
    ('desktop-proof', 'NATIVE_DESKTOP_PROOF_PASS'),
    ('fullrelease', 'NATIVE_FULLRELEASE_PASS'),
)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    Path(path).write_text(json.dumps(value), encoding='utf-8')


class HttpCleanupSuccessorPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location(
            'fresh_attempts_http_cleanup', HERE / 'fresh_attempts.py')
        cls.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.journal)

    def test_registered_policy_admits_only_exact_ordered_finite_limits(self):
        self.assertEqual(self.journal.limits_for(POLICY), EXPECTED_LIMITS)
        self.assertEqual(self.journal.sequence_for(POLICY), EXPECTED_SEQUENCE)


class HttpCleanupAdmissionFixture:
    """Synthetic terminal COLLISION-1 and hash-bound successor inputs."""
    def __init__(self, test, *, successor_tuple=None, generation7=None,
                 public_main_sha=None):
        # Load the legacy fixture at runtime so pytest does not collect its
        # TestCase methods again in this module. Its tests mutate a shared
        # module-level LIMITS dictionary, so re-collection contaminates setup.
        legacy_spec = importlib.util.spec_from_file_location(
            'legacy_post_collision_fixture', HERE / 'test_post_collision_successor.py')
        legacy_module = importlib.util.module_from_spec(legacy_spec)
        legacy_spec.loader.exec_module(legacy_module)
        self.base = legacy_module.PostCollisionSuccessorTests()
        self.base.setUp()
        test.addCleanup(self.base.doCleanups)
        self.journal = self.base.j
        self.root = self.base.root
        if generation7 is not None:
            # Make the synthetic COLLISION-1 terminal tuple equal the exact
            # accepted Gen-7 tuple that the successor must preserve.
            self.base.old_tuple = dict(generation7.new, repositoryHead='2' * 40,
                                       toolingFingerprintId='3' * 64)
            self.base.new_tuple = dict(generation7.new)
            for attempt in self.base.parent_data['attempts']:
                attempt['tuple'] = self.base.old_tuple
            write(self.base.parent, self.base.parent_data)
            self.base.live_parent.write_bytes(self.base.parent.read_bytes())
            write(self.base.receipt, {
                'schemaVersion': 6,
                'contract': 'devfleet-baseline-rebind-receipt-v6',
                'status': 'REBOUND', 'certificationCredit': False,
                'candidate': self.base.old_tuple,
                'replacement': self.base.checkpoint})
            self.base.auth_data['previousCandidate'] = self.base.old_tuple
            self.base.auth_data['candidate'] = self.base.new_tuple
            self.base.auth_data['predecessorSha256'] = {
                'causal1': sha(self.base.parent)}
            self.base.auth_data['generation6']['receiptSha256'] = sha(self.base.receipt)
            old_sha_patch = self.base.sha_patch
            old_sha_patch.stop()
            self.base.sha_patch = patch.object(
                self.base.j, 'COLLISION_PREDECESSOR_SHA256', sha(self.base.parent), create=True)
            self.base.sha_patch.start()
            self.base.addCleanup(self.base.sha_patch.stop)
            for path in (self.base.proposal, self.base.source):
                reviewed = json.loads(path.read_text(encoding='utf-8'))
                reviewed['previousCandidate'] = self.base.old_tuple
                reviewed['candidate'] = self.base.new_tuple
                write(path, reviewed)
            self.base.auth_data['reviewedSources'] = {
                'proposal': {'path': str(self.base.proposal), 'sha256': sha(self.base.proposal)},
                'source': {'path': str(self.base.source), 'sha256': sha(self.base.source)},
            }
            write(self.base.auth, self.base.auth_data)
            # The Gen8 archive walks the full path/hash lineage reachable from
            # COLLISION-1. Make this inherited synthetic auth reference real
            # and hash-correct so the fixture tests closure behavior rather
            # than a deliberately dangling path from the older unit fixture.
            old_auth = self.base.root / 'old-auth.json'
            write(old_auth, {'synthetic': 'historical predecessor authorization'})
            self.base.parent_data['authorization'] = {
                'path': str(old_auth), 'sha256': sha(old_auth)}
            write(self.base.parent, self.base.parent_data)
            self.base.live_parent.write_bytes(self.base.parent.read_bytes())
            self.base.auth_data['predecessorSha256'] = {
                'causal1': sha(self.base.parent)}
            write(self.base.auth, self.base.auth_data)
            self.base.sha_patch.stop()
            self.base.sha_patch = patch.object(
                self.base.j, 'COLLISION_PREDECESSOR_SHA256',
                sha(self.base.parent), create=True)
            self.base.sha_patch.start()
            self.base.addCleanup(self.base.sha_patch.stop)
        self.ledger = self.root / 'DF-FRESH-CERTIFICATION-20261001-HTTP-CLEANUP-1' / 'ledger.json'
        self.ledger.parent.mkdir(parents=True)
        self.snapshot = self.ledger.parent / 'predecessors' / 'COLLISION-1-ledger.json'
        self.snapshot.parent.mkdir(parents=True)
        self.live_predecessor = self.base.ledger

        self.base.initialize()
        predecessor_sequence = (
            ('standard-token', 'PASS_NATIVE_STANDARD_TOKEN', 0),
            ('diagnostic', 'PASS_READY_FOR_PROOF_RESERVATION', 0),
            ('laptop-proof', 'NATIVE_LAPTOP_PROOF_PASS', 0),
            ('desktop-proof', 'NATIVE_DESKTOP_PROOF_PASS', 0),
            ('fullrelease', 'NATIVE_FULLRELEASE_BLOCKED', 2),
        )
        for index, (operation, classification, exit_code) in enumerate(predecessor_sequence):
            request = self.base.request(operation, f'collision-terminal-{index}')
            self.journal.reserve(self.live_predecessor, request)
            self.journal.finish(self.live_predecessor, request['runId'], request['owner'],
                                exit_code, classification, ['synthetic-terminal-evidence'])
        self.snapshot.write_bytes(self.live_predecessor.read_bytes())
        self.predecessor_sha256 = sha(self.live_predecessor)
        self.predecessor_bytes = self.live_predecessor.read_bytes()

        self.old_tuple = dict(self.base.new_tuple)
        self.new_tuple = successor_tuple or dict(self.old_tuple, repositoryHead='8' * 40,
                                                 toolingFingerprintId='9' * 64)
        self.owner_source = self.root / 'owner-authorization.txt'
        self.public_main_sha = public_main_sha or 'a' * 40
        self.owner_source.write_text(
            'I explicitly authorize exactly one future prospective successor\n'
            + POLICY + '\nstandard-token = 1\ndiagnostic/readiness = 1\n'
            'laptop-proof = 1\ndesktop-proof = 1\nfullrelease = 1\n'
            'maintenance = 0\nbuild-sign = 0\nNo signed-shipping change is authorized.\n'
            + f'publicMainSha={self.public_main_sha}\n'
            + f'predecessorSha256={self.predecessor_sha256}\n'
            + ''.join(f'previousCandidate.{key}={value}\n'
                      for key, value in self.old_tuple.items())
            + ''.join(f'candidate.{key}={value}\n'
                      for key, value in self.new_tuple.items()),
            encoding='utf-8')

        self.executor = self.root / 'Invoke-HttpHostilePhase.ps1'
        self.regression = self.root / 'Test-HttpHostileCleanup.ps1'
        self.executor.write_text('reviewed HTTP-HOSTILE sharing-violation cleanup correction', encoding='utf-8')
        self.regression.write_text('reviewed HTTP-HOSTILE real-handle cleanup regression', encoding='utf-8')

        failed_run = self.journal.load(self.live_predecessor)['attempts'][-1]['runId']
        self.wrapper = self.root / 'fullrelease-wrapper.json'
        self.run_state = self.root / 'fullrelease-run-state.json'
        self.error = self.root / 'fullrelease-error.txt'
        self.failure_cleanup = self.root / 'fullrelease-failure-cleanup.json'
        self.request_admission = self.root / 'http-hostile-request-admission.json'
        first_failure = 'Windows sharing violation at templates/ruby-rails'
        write(self.wrapper, {'runId': failed_run, 'classification': 'NATIVE_FULLRELEASE_BLOCKED',
                             'exitCode': 2, 'currentPhase': 'HTTP-HOSTILE',
                             'firstTechnicalFailure': first_failure,
                             'observerTerminal': 'NO_PROGRESS_TIMEOUT'})
        write(self.run_state, {'runId': failed_run, 'currentPhase': 'HTTP-HOSTILE'})
        self.error.write_text(f'{failed_run}: {first_failure}', encoding='utf-8')
        write(self.failure_cleanup, {'runId': failed_run,
                                     'l1': {'state': 'Off'},
                                     'l2': {'status': 'UNVERIFIED'}})
        write(self.request_admission, {'runId': failed_run, 'phase': 'HTTP-HOSTILE',
                                       'classification': 'PASS_HTTP_HOSTILE_REQUEST_ADMISSION',
                                       'passedTests': 10, 'failedTests': 0})

        if generation7 is not None:
            self.gen7_receipt = generation7.root / 'evidence' / 'baselines' / 'receipts' / generation7.pointer['receiptFile']
            # Freeze the exact Gen-7 parent pointer beside this successor ledger.
            # CURRENT.json advances to Gen-8 during append and must not rewrite
            # the successor's authorization reference to its predecessor.
            self.gen7_pointer = self.ledger.parent / 'predecessors' / 'GENERATION-7-CURRENT.json'
            self.gen7_pointer.parent.mkdir(parents=True, exist_ok=True)
            self.gen7_pointer.write_bytes(
                (generation7.root / 'evidence' / 'baselines' / 'CURRENT.json').read_bytes())
            self.checkpoint = generation7.pointer['checkpoint']
        else:
            self.checkpoint = {'name': 'DevFleet-E2E-CLEAN-R2',
                               'id': '1e84fdaf-45f9-417e-a93c-354d05b4c766'}
            baseline_state = self.root / 'evidence' / 'baselines'
            receipt_dir = baseline_state / 'receipts'
            receipt_dir.mkdir(parents=True)
            self.gen7_receipt = receipt_dir / '000feeb05be149088e8e07954282e80f.json'
            write(self.gen7_receipt, {'schemaVersion': 7,
                                      'contract': 'devfleet-baseline-rebind-receipt-v7',
                                      'status': 'REBOUND', 'candidate': self.old_tuple,
                                      'replacement': self.checkpoint})
            self.gen7_pointer = baseline_state / 'CURRENT.json'
            write(self.gen7_pointer, {'schemaVersion': 7,
                                      'contract': 'devfleet-accepted-baseline-v7',
                                      'generation': 7, 'status': 'ACCEPTED',
                                      'receiptFile': self.gen7_receipt.name,
                                      'receiptSha256': sha(self.gen7_receipt),
                                      'checkpoint': self.checkpoint})

        self.auth = self.root / 'successor-authorization.json'
        ref = lambda path: {'path': str(path), 'sha256': sha(path)}
        self.auth_data = {
            'schemaVersion': 1,
            'kind': 'DEVFLEET_HTTP_CLEANUP_SUCCESSOR_AUTHORIZATION',
            'policyId': POLICY,
            'approved': True,
            'approvedBy': 'ACCOUNT_OWNER',
            'ownerAuthorization': ref(self.owner_source),
            'successorLedgerPath': str(self.ledger),
            'predecessorSha256': {'collision1': self.predecessor_sha256},
            'previousCandidate': self.old_tuple,
            'candidate': self.new_tuple,
            'limits': EXPECTED_LIMITS,
            'shippingChangeApproved': False,
            'publicMainSha': self.public_main_sha,
            'reviewedSources': {'httpHostileExecutor': ref(self.executor),
                                'httpHostileRegression': ref(self.regression)},
            'failureEvidence': {'fullReleaseWrapper': ref(self.wrapper),
                                'runState': ref(self.run_state),
                                'error': ref(self.error),
                                'failureCleanup': ref(self.failure_cleanup),
                                'requestAdmission': ref(self.request_admission)},
            'generation7': {'pointer': ref(self.gen7_pointer),
                            'receipt': ref(self.gen7_receipt),
                            'checkpoint': self.checkpoint},
        }
        write(self.auth, self.auth_data)
        self._patch('HTTP_CLEANUP_PREDECESSOR_SHA256', self.predecessor_sha256)
        self._patch('HTTP_CLEANUP_LIVE_PREDECESSOR_PATH', self.live_predecessor)
        self._patch('HTTP_CLEANUP_LEDGER_PATH', self.ledger)
        self._patch('HTTP_CLEANUP_GEN7_POINTER_SHA256', sha(self.gen7_pointer))
        self._patch('HTTP_CLEANUP_GEN7_RECEIPT_SHA256', sha(self.gen7_receipt))
        self._patch('HTTP_CLEANUP_GEN7_RECEIPT_FILE', self.gen7_receipt.name)
        self._patch('HTTP_CLEANUP_CLEAN_R2_ID', self.checkpoint['id'])

    def _patch(self, name, value):
        context = patch.object(self.journal, name, value, create=True)
        context.start()
        self.base.addCleanup(context.stop)

    def initialize(self, ledger=None, predecessors=None):
        return self.journal.initialize(
            ledger or self.ledger, self.auth,
            predecessors or [self.snapshot, self.live_predecessor], POLICY)

    def request(self, operation, run_id='successor-run-001', candidate=None):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 4321, 'startUtc': '2026-10-01T08:00:00Z'},
                'tuple': candidate or self.new_tuple,
                'entrypoint': 'synthetic-native-wrapper.ps1',
                'entrypointSha256': 'b' * 64, 'arguments': [],
                'changedCondition': 'reviewed HTTP-HOSTILE cleanup correction',
                'deadlineUtc': '2099-01-01T00:00:00Z'}


class HttpCleanupSuccessorAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.fixture = HttpCleanupAdmissionFixture(self)

    def test_exact_terminal_predecessor_initializes_without_credit_or_history_mutation(self):
        before = self.fixture.live_predecessor.read_bytes()
        state = self.fixture.initialize()
        self.assertEqual(state['remaining'], EXPECTED_LIMITS)
        self.assertEqual(state['attemptCount'], 0)
        self.assertIsNone(state['active'])
        self.assertFalse(state['certificationCredit'])
        self.assertEqual(self.fixture.live_predecessor.read_bytes(), before)

    def assert_policy_rejected(self, *, ledger=None, predecessors=None):
        with self.assertRaisesRegex(ValueError, 'HTTP-CLEANUP-1'):
            self.fixture.initialize(ledger=ledger, predecessors=predecessors)

    def test_wrong_predecessor_count_and_second_live_alias_are_rejected(self):
        self.assert_policy_rejected(predecessors=[self.fixture.snapshot])
        self.assert_policy_rejected(predecessors=[self.fixture.snapshot,
                                                  self.fixture.snapshot])
        alternate = self.fixture.root / 'second-live-collision-ledger.json'
        alternate.write_bytes(self.fixture.live_predecessor.read_bytes())
        self.assert_policy_rejected(predecessors=[self.fixture.snapshot, alternate])
        self.assert_policy_rejected(predecessors=[self.fixture.snapshot,
                                                  self.fixture.gen7_pointer])
        self.assert_policy_rejected(ledger=self.fixture.snapshot)

    def test_modified_snapshot_and_live_predecessor_are_rejected(self):
        self.fixture.snapshot.write_bytes(self.fixture.snapshot.read_bytes() + b' ')
        self.assert_policy_rejected()

    def test_active_predecessor_is_rejected_even_when_snapshot_matches(self):
        predecessor = json.loads(self.fixture.live_predecessor.read_text())
        predecessor['activeRunId'] = 'unexpected-active-owner'
        write(self.fixture.live_predecessor, predecessor)
        self.fixture.snapshot.write_bytes(self.fixture.live_predecessor.read_bytes())
        changed_hash = sha(self.fixture.live_predecessor)
        self.fixture.auth_data['predecessorSha256'] = {'collision1': changed_hash}
        write(self.fixture.auth, self.fixture.auth_data)
        self.fixture._patch('HTTP_CLEANUP_PREDECESSOR_SHA256', changed_hash)
        with self.assertRaises(ValueError):
            self.fixture.initialize()

    def test_widened_and_noninteger_limits_are_rejected(self):
        original = self.fixture.auth_data['limits'].copy()
        for invalid in (dict(original, **{'laptop-proof': 2}),
                        dict(original, **{'diagnostic': True}),
                        dict(original, extra=0)):
            self.fixture.auth_data['limits'] = invalid
            write(self.fixture.auth, self.fixture.auth_data)
            self.assert_policy_rejected()
        self.fixture.auth_data['limits'] = original

    def test_tuple_and_shipping_drift_are_rejected(self):
        original = json.loads(json.dumps(self.fixture.auth_data))
        for key, value in (('repositoryHead', self.fixture.old_tuple['repositoryHead']),
                           ('toolingFingerprintId', self.fixture.old_tuple['toolingFingerprintId']),
                           ('candidateSha256', '0' * 64)):
            self.fixture.auth_data = json.loads(json.dumps(original))
            self.fixture.auth_data['candidate'][key] = value
            write(self.fixture.auth, self.fixture.auth_data)
            self.assert_policy_rejected()

    def test_authorization_and_reviewed_source_drift_are_rejected(self):
        self.fixture.owner_source.write_bytes(self.fixture.owner_source.read_bytes() + b' ')
        self.assert_policy_rejected()

    def test_owner_authorization_must_bind_public_main_and_both_tuples(self):
        text = self.fixture.owner_source.read_text(encoding='utf-8')
        text = text.replace(f'publicMainSha={self.fixture.public_main_sha}\n', '')
        self.fixture.owner_source.write_text(text, encoding='utf-8')
        self.fixture.auth_data['ownerAuthorization']['sha256'] = sha(self.fixture.owner_source)
        write(self.fixture.auth, self.fixture.auth_data)
        self.assert_policy_rejected()

    def test_fullrelease_blocker_binds_ten_request_admission_passes(self):
        state = self.fixture.initialize()
        self.assertEqual(state['attemptCount'], 0)

    def test_fullrelease_blocker_rejects_incomplete_request_admission(self):
        admission = {'runId': self.fixture.journal.load(self.fixture.live_predecessor)
                     ['attempts'][-1]['runId'],
                     'phase': 'HTTP-HOSTILE',
                     'classification': 'PASS_HTTP_HOSTILE_REQUEST_ADMISSION',
                     'passedTests': 9, 'failedTests': 0}
        write(self.fixture.request_admission, admission)
        self.fixture.auth_data['failureEvidence']['requestAdmission']['sha256'] = \
            sha(self.fixture.request_admission)
        write(self.fixture.auth, self.fixture.auth_data)
        self.assert_policy_rejected()

    def test_replayed_ancestor_run_id_and_reservation_tuple_drift_are_rejected(self):
        self.fixture.initialize()
        historical = self.fixture.journal.load(self.fixture.live_predecessor)['attempts'][0]['runId']
        with self.assertRaisesRegex(ValueError, 'historical RunId'):
            self.fixture.journal.reserve(
                self.fixture.ledger,
                self.fixture.request('standard-token', historical), dry_run=True)
        drifted = dict(self.fixture.new_tuple, toolingFingerprintId='7' * 64)
        with self.assertRaisesRegex(ValueError, 'reservation tuple'):
            self.fixture.journal.reserve(
                self.fixture.ledger,
                self.fixture.request('standard-token', 'fresh-run-tuple-drift', drifted),
                dry_run=True)

    def test_out_of_order_and_failed_prerequisite_cannot_advance(self):
        self.fixture.initialize()
        with self.assertRaisesRegex(ValueError, 'phase order'):
            self.fixture.journal.reserve(
                self.fixture.ledger,
                self.fixture.request('laptop-proof', 'out-of-order-laptop'), dry_run=True)
        request = self.fixture.request('standard-token', 'failed-token')
        self.fixture.journal.reserve(self.fixture.ledger, request)
        self.fixture.journal.finish(self.fixture.ledger, request['runId'], request['owner'],
                                    2, 'NATIVE_STANDARD_TOKEN_BLOCKED', [])
        with self.assertRaisesRegex(ValueError, 'phase order or prerequisite'):
            self.fixture.journal.reserve(
                self.fixture.ledger,
                self.fixture.request('diagnostic', 'after-failed-token'), dry_run=True)

    def test_exact_order_can_exhaust_only_successor_allowances_without_credit(self):
        predecessor_before = self.fixture.live_predecessor.read_bytes()
        self.fixture.initialize()
        sequence = EXPECTED_SEQUENCE
        for index, (operation, classification) in enumerate(sequence):
            request = self.fixture.request(operation, f'http-successor-{index}')
            self.fixture.journal.reserve(self.fixture.ledger, request)
            self.fixture.journal.finish(self.fixture.ledger, request['runId'], request['owner'],
                                        0, classification, ['synthetic-terminal-evidence'])
        status = self.fixture.journal.status(self.fixture.ledger)
        self.assertEqual(status['remaining'], {key: 0 for key in EXPECTED_LIMITS})
        self.assertFalse(status['certificationCredit'])
        self.assertEqual(self.fixture.live_predecessor.read_bytes(), predecessor_before)

    def test_hash_bound_reviewed_source_drift_rejects_existing_successor(self):
        self.fixture.initialize()
        source = self.fixture.regression
        source.write_bytes(source.read_bytes() + b' tamper')
        with self.assertRaisesRegex(ValueError, 'HTTP-CLEANUP-1 reviewed source reference'):
            self.fixture.journal.status(self.fixture.ledger)

    def test_authorization_drift_rejects_existing_successor(self):
        self.fixture.initialize()
        self.fixture.auth.write_bytes(self.fixture.auth.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'Authorization source changed'):
            self.fixture.journal.status(self.fixture.ledger)

    def test_existing_successor_cannot_be_reinitialized(self):
        self.fixture.initialize()
        before = self.fixture.ledger.read_bytes()
        with self.assertRaisesRegex(ValueError, 'Existing campaign'):
            self.fixture.initialize()
        self.assertEqual(self.fixture.ledger.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
