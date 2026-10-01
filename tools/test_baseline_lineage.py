"""VM-free transaction tests for exact DevFleet CLEAN baseline adoption."""
import copy
import importlib.util
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from baseline_lineage import adopt, accepted_baseline, rebind
from validate_release_bundle import load_accepted_baseline


VM = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
OLD = '19865b76-4c3a-44f7-ba39-841e9d3c40c9'
NEW = '11111111-2222-4333-8444-555555555555'
TUPLE = {'repositoryHead': '1' * 40, 'candidateBuildCommit': '2' * 40,
         'shippingInputIdentity': '3' * 64, 'releaseFingerprintId': '4' * 64,
         'toolingFingerprintId': '5' * 64, 'candidateSha256': '6' * 64}


class BaselineLineageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        # Hosted Windows may expose the temp root through an 8.3 path alias;
        # evidence references must use the canonical filesystem path.
        self.root = Path(self.tmp.name).resolve()
        predecessor = self.root / 'audit/agent-memory/attempts/DF-FRESH-CERTIFICATION-20260926-R2/readiness-predecessor.json'
        predecessor.parent.mkdir(parents=True, exist_ok=True)
        predecessor.write_text(json.dumps({'lab': {'l1Id': VM, 'cleanId': OLD},
                                           'liveGuestAuth': {'cleanRestored': True,
                                                             'finalL1State': 'Off'}}), encoding='utf-8')
        self.proposal = {'schemaVersion': 1, 'contract': 'devfleet-baseline-adoption-proposal-v1',
                         'runId': 'r2-owned-baseline-1',
                         'vm': {'name': 'DevFleet-E2E-Win11-01', 'id': VM},
                         'predecessor': {'name': 'DevFleet-E2E-CLEAN', 'id': OLD},
                         'replacement': {'name': 'DevFleet-E2E-CLEAN-R2', 'id': NEW,
                                         'vmId': VM, 'parentSnapshotId': OLD},
                         'predecessorEvidence': {'path': str(predecessor),
                                                 'sha256': hashlib.sha256(predecessor.read_bytes()).hexdigest()},
                         'candidate': copy.deepcopy(TUPLE)}
        self.approval = {'schemaVersion': 1, 'contract': 'devfleet-baseline-adoption-approval-v1',
                         'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                         'vmId': VM, 'predecessorId': OLD, 'replacementId': NEW,
                         'runId': 'r2-owned-baseline-1', 'candidate': copy.deepcopy(TUPLE)}
        self.auth = {'scope': 'CURRENT_RUNNING_GUEST_READ_ONLY',
                     'runId': 'r2-owned-baseline-1', 'connected': True,
                     'status': 'AUTHENTICATED_CURRENT_GUEST_NOT_CLEAN_PROOF',
                     'certificationCredit': False,
                     'observedUtc': '2026-09-27T03:00:00Z',
                     'guest': {'computerName': 'DEVFLEET-E2E-01',
                               'principal': 'DEVFLEET-E2E-01\\E2EAdmin',
                               'accountEnabled': True,
                               'passwordLastSetUtc': '2026-09-27T02:40:00Z',
                               'passwordExpiresUtc': '2026-10-27T02:40:00Z'},
                     'credential': {'storeUser': 'E2EAdmin',
                                    'protectedStoreUpdatedUtc': '2026-09-27T02:45:00Z',
                                    'secretValuesRecorded': False},
                     'nestedL2': {'status': 'ABSENT', 'present': False,
                                  'expectedName': 'DevFleet-E2E-Linux-01',
                                  'exactMatchCount': 0,
                                  'observedUtc': '2026-09-27T02:59:00Z',
                                  'backendInventories': [
                                      {'provider': 'Hyper-V', 'status': 'PASS', 'names': [], 'verification': 'read-only'},
                                      {'provider': 'VirtualBox', 'status': 'PASS', 'names': [], 'verification': 'read-only'}]}}
        self.live = {'scope': 'NATIVE_EXACT_L1_CHECKPOINT_INVENTORY',
                     'observedUtc': '2026-09-27T03:05:00Z',
                     'vm': {'name': 'DevFleet-E2E-Win11-01', 'id': VM, 'state': 'Off'},
                     'snapshots': [{'name': 'DevFleet-E2E-CLEAN', 'id': OLD, 'vmId': VM},
                                   {'name': 'DevFleet-E2E-CLEAN-R2', 'id': NEW,
                                    'vmId': VM, 'parentSnapshotId': OLD}]}
        now = datetime.now(timezone.utc)
        stamp = lambda value: value.isoformat()
        self.auth['observedUtc'] = stamp(now - timedelta(minutes=5))
        self.auth['guest']['passwordLastSetUtc'] = stamp(now - timedelta(minutes=20))
        self.auth['guest']['passwordExpiresUtc'] = stamp(now + timedelta(days=30))
        self.auth['credential']['protectedStoreUpdatedUtc'] = stamp(now - timedelta(minutes=10))
        self.auth['nestedL2']['observedUtc'] = stamp(now - timedelta(minutes=6))
        self.live['observedUtc'] = stamp(now - timedelta(minutes=1))
        self.auth['startedUtc'] = stamp(now - timedelta(minutes=7))
        self.auth['vm'] = {'name': 'DevFleet-E2E-Win11-01', 'id': VM}
        self.auth['candidate'] = copy.deepcopy(TUPLE)
        self.ledger = {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2',
                       'activeRunId': None,
                       'attempts': [{'runId': 'r2-owned-baseline-1', 'operation': 'diagnostic',
                                     'state': 'TERMINAL', 'certificationCredit': False,
                                     'tuple': copy.deepcopy(TUPLE), 'exitCode': 0,
                                     'reservedUtc': stamp(now - timedelta(minutes=8)),
                                     'deadlineUtc': stamp(now + timedelta(minutes=5)),
                                     'evidence': [str((self.root / 'auth.json').resolve())],
                                     'terminalUtc': stamp(now - timedelta(minutes=2))}]}

    def write(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding='utf-8')
        return path

    def one_diagnostic_ledger(self):
        source = Path(__file__).resolve().parents[1] / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        target = self.root / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        spec = importlib.util.spec_from_file_location('fixture_fresh_attempts', target)
        journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(journal)
        base_auth = self.root / 'base-authorization.md'
        r2_auth = self.root / 'r2-authorization.md'
        d1_auth = self.root / 'd1-authorization.md'
        for path, text in ((base_auth, 'base'), (r2_auth, 'R2'),
                           (d1_auth, 'one extra diagnostic')):
            path.write_text(text, encoding='utf-8')
        base = self.root / 'base-ledger.json'
        r2 = self.root / 'r2-ledger.json'
        successor = self.root / 'successor-ledger.json'
        journal.initialize(base, base_auth, [])
        journal.initialize(r2, r2_auth, [base], journal.POLICY_ID + '-R2')
        for number in range(6):
            request = {'runId': f'diagnostic-{number}', 'operation': 'diagnostic',
                       'owner': {'pid': 1234, 'startUtc': '2026-09-27T00:00:00Z'},
                       'tuple': {'repositoryHead': '1' * 40},
                       'entrypoint': 'readiness.ps1', 'entrypointSha256': '2' * 64,
                       'arguments': [], 'changedCondition': 'bounded fixture',
                       'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
            journal.reserve(r2, request)
            journal.finish(r2, request['runId'], request['owner'], 2, 'TEST_TERMINAL', [])
        journal.initialize(successor, d1_auth, [r2], journal.ONE_DIAGNOSTIC_ID)
        return successor

    def invoke(self, *, proposal=None, approval=None, auth=None, live=None,
               candidate=None, ledger=None, fault=None):
        return adopt(self.root,
                     self.write('proposal.json', self.proposal if proposal is None else proposal),
                     self.write('approval.json', self.approval if approval is None else approval),
                     self.write('auth.json', self.auth if auth is None else auth),
                     self.write('live.json', self.live if live is None else live),
                     self.write('candidate.json', TUPLE if candidate is None else candidate),
                     self.write('ledger.json', self.ledger if ledger is None else ledger),
                     fault=fault)

    def test_valid_transaction_preserves_predecessor_and_no_credit(self):
        self.assertEqual(accepted_baseline(self.root)['id'], OLD)
        receipt = self.invoke()
        selected = accepted_baseline(self.root, TUPLE)
        self.assertEqual(selected['id'], NEW)
        self.assertEqual(selected['predecessorId'], OLD)
        self.assertEqual(selected['receiptSha256'], receipt['receiptSha256'])
        self.assertFalse(receipt['certificationCredit'])
        receipt_path = self.root / 'evidence/baselines/receipts' / receipt['receiptFile']
        self.assertTrue(receipt_path.is_file())
        self.assertEqual(json.loads(receipt_path.read_text())['sources']['predecessorEvidenceSha256'],
                         self.proposal['predecessorEvidence']['sha256'])
        expected = {'repositoryHead': TUPLE['repositoryHead'],
                    'candidateCommit': TUPLE['candidateBuildCommit'],
                    'shippingInputIdentity': TUPLE['shippingInputIdentity'],
                    'releaseFingerprintId': TUPLE['releaseFingerprintId'],
                    'toolingFingerprintId': TUPLE['toolingFingerprintId']}
        self.assertEqual(load_accepted_baseline(self.root, expected,
                                                {'exe': TUPLE['candidateSha256']})['id'], NEW)

    def test_exact_owner_approved_rebind_preserves_v1_chain(self):
        first = self.invoke()
        new_tuple = {**TUPLE, 'repositoryHead': '7' * 40,
                     'toolingFingerprintId': '8' * 64}
        binding_approval = {'schemaVersion': 1,
                            'contract': 'devfleet-baseline-rebind-approval-v1',
                            'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                            'candidate': new_tuple,
                            'replacement': self.proposal['replacement'],
                            'previousReceiptSha256': first['receiptSha256']}
        successor = self.one_diagnostic_ledger()
        with self.assertRaises(ValueError):
            rebind(self.root,
                   self.write('bad-shipping-tuple.json', {**new_tuple, 'shippingInputIdentity': '9' * 64}),
                   self.write('rebind-approval.json', binding_approval), successor,
                   self.write('rebind-live.json', self.live))
        with self.assertRaises(ValueError):
            rebind(self.root, self.write('new-tuple.json', new_tuple),
                   self.write('bad-rebind-approval.json', {**binding_approval, 'decision': 'PENDING'}),
                   successor, self.root / 'rebind-live.json')
        with self.assertRaises(ValueError):
            rebind(self.root, self.root / 'new-tuple.json',
                   self.root / 'rebind-approval.json',
                   self.write('forged-successor.json', {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2-D1',
                                                        'activeRunId': None, 'limits': {'diagnostic': 1},
                                                        'attempts': []}),
                   self.root / 'rebind-live.json')
        rebound = rebind(self.root, self.write('new-tuple.json', new_tuple),
                         self.write('rebind-approval.json', binding_approval),
                         successor,
                         self.write('rebind-live.json', self.live))
        self.assertEqual(rebound['id'], NEW)
        self.assertEqual(rebound['generation'], 2)
        self.assertNotEqual(rebound['receiptSha256'], first['receiptSha256'])
        self.assertEqual(accepted_baseline(self.root, new_tuple)['receiptSha256'],
                         rebound['receiptSha256'])
        expected = {'repositoryHead': new_tuple['repositoryHead'],
                    'candidateCommit': new_tuple['candidateBuildCommit'],
                    'shippingInputIdentity': new_tuple['shippingInputIdentity'],
                    'releaseFingerprintId': new_tuple['releaseFingerprintId'],
                    'toolingFingerprintId': new_tuple['toolingFingerprintId']}
        self.assertEqual(load_accepted_baseline(self.root, expected,
                                                {'exe': new_tuple['candidateSha256']})['receiptSha256'],
                         rebound['receiptSha256'])
        with self.assertRaises(ValueError):
            rebind(self.root, self.root / 'new-tuple.json', self.root / 'rebind-approval.json',
                   successor, self.root / 'rebind-live.json')
        history = next((self.root / 'evidence/baselines/history').glob('*.json'))
        history.write_bytes(history.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            accepted_baseline(self.root, new_tuple)
        with self.assertRaises(ValueError):
            load_accepted_baseline(self.root, expected, {'exe': new_tuple['candidateSha256']})

    def test_independent_release_validator_rejects_rehashed_malformed_receipt(self):
        import hashlib
        receipt_info = self.invoke()
        path = self.root / 'evidence/baselines/receipts' / receipt_info['receiptFile']
        pointer_path = self.root / 'evidence/baselines/CURRENT.json'
        expected = {'repositoryHead': TUPLE['repositoryHead'],
                    'candidateCommit': TUPLE['candidateBuildCommit'],
                    'shippingInputIdentity': TUPLE['shippingInputIdentity'],
                    'releaseFingerprintId': TUPLE['releaseFingerprintId'],
                    'toolingFingerprintId': TUPLE['toolingFingerprintId']}
        original = json.loads(path.read_text())
        for kind in ('schema', 'guid', 'nested', 'secret'):
            with self.subTest(kind=kind):
                receipt = copy.deepcopy(original)
                if kind == 'schema': receipt['schemaVersion'] = 9
                if kind == 'guid': receipt['replacement']['id'] = 'not-a-guid'
                if kind == 'nested': receipt['nestedL2']['backendInventories'][0]['names'] = ['DevFleet-E2E-Linux-01']
                if kind == 'secret': receipt['secretValuesRecorded'] = True
                path.write_text(json.dumps(receipt), encoding='utf-8')
                pointer = json.loads(pointer_path.read_text())
                pointer['receiptSha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
                pointer['checkpoint'] = receipt['replacement']
                pointer_path.write_text(json.dumps(pointer), encoding='utf-8')
                with self.assertRaises(ValueError):
                    load_accepted_baseline(self.root, expected, {'exe': TUPLE['candidateSha256']})

    def test_wrong_missing_ambiguous_checkpoint_and_name_only_rejected(self):
        for kind in ('wrong_vm', 'missing_new', 'duplicate_new', 'name_only', 'wrong_parent'):
            with self.subTest(kind=kind):
                proposal, live = copy.deepcopy(self.proposal), copy.deepcopy(self.live)
                if kind == 'wrong_vm': live['vm']['id'] = '00000000-0000-0000-0000-000000000001'
                if kind == 'missing_new': live['snapshots'].pop()
                if kind == 'duplicate_new': live['snapshots'].append(copy.deepcopy(live['snapshots'][-1]))
                if kind == 'name_only': live['snapshots'][-1]['id'] = OLD
                if kind == 'wrong_parent': live['snapshots'][-1]['parentSnapshotId'] = NEW
                with self.assertRaises(ValueError): self.invoke(proposal=proposal, live=live)
                self.assertEqual(accepted_baseline(self.root)['id'], OLD)

    def test_approval_inventory_expiry_and_tuple_rejected(self):
        for kind in ('unapproved', 'approval_id', 'inventory_missing', 'inventory_present',
                     'expired', 'unknown_expiry', 'tuple', 'guest_identity'):
            with self.subTest(kind=kind):
                approval, auth, candidate = copy.deepcopy(self.approval), copy.deepcopy(self.auth), copy.deepcopy(TUPLE)
                if kind == 'unapproved': approval['decision'] = 'PENDING'
                if kind == 'approval_id': approval['replacementId'] = OLD
                if kind == 'inventory_missing': auth['nestedL2']['backendInventories'].pop()
                if kind == 'inventory_present': auth['nestedL2']['backendInventories'][0]['names'] = ['DevFleet-E2E-Linux-01']
                if kind == 'expired': auth['guest']['passwordExpiresUtc'] = (datetime.now(timezone.utc)-timedelta(days=1)).isoformat()
                if kind == 'unknown_expiry': auth['guest']['passwordExpiresUtc'] = None
                if kind == 'tuple': candidate['toolingFingerprintId'] = '9' * 64
                if kind == 'guest_identity': auth['guest']['principal'] = 'OTHER\\E2EAdmin'
                with self.assertRaises(ValueError): self.invoke(approval=approval, auth=auth, candidate=candidate)
                self.assertEqual(accepted_baseline(self.root)['id'], OLD)

    def test_replay_and_interrupted_receipt_keep_prior_pointer(self):
        self.invoke()
        with self.assertRaises(ValueError): self.invoke()
        self.assertEqual(accepted_baseline(self.root, TUPLE)['id'], NEW)
        second = tempfile.TemporaryDirectory()
        self.addCleanup(second.cleanup)
        other = Path(second.name)
        # The same fixture evidence remains external to the transaction state.
        other_predecessor = other / 'audit/agent-memory/attempts/DF-FRESH-CERTIFICATION-20260926-R2/readiness-predecessor.json'
        other_predecessor.parent.mkdir(parents=True, exist_ok=True)
        other_predecessor.write_bytes(Path(self.proposal['predecessorEvidence']['path']).read_bytes())
        other_proposal = copy.deepcopy(self.proposal)
        other_proposal['predecessorEvidence']['path'] = str(other_predecessor)
        other_proposal_path = other / 'proposal.json'
        other_proposal_path.write_text(json.dumps(other_proposal), encoding='utf-8')
        with self.assertRaises(RuntimeError):
            adopt(other, other_proposal_path, self.root/'approval.json',
                  self.root/'auth.json', self.root/'live.json', self.root/'candidate.json',
                  self.root/'ledger.json',
                  fault='after_receipt')
        self.assertEqual(accepted_baseline(other)['id'], OLD)
        with self.assertRaises(ValueError):
            adopt(other, other_proposal_path, self.root/'approval.json',
                  self.root/'auth.json', self.root/'live.json', self.root/'candidate.json',
                  self.root/'ledger.json')
        self.assertEqual(accepted_baseline(other)['id'], OLD)

    def test_unreserved_or_active_auth_evidence_rejected(self):
        for kind in ('missing', 'active', 'wrong_class', 'unbound_evidence'):
            with self.subTest(kind=kind):
                ledger = copy.deepcopy(self.ledger)
                if kind == 'missing': ledger['attempts'] = []
                if kind == 'active': ledger['attempts'][0]['state'] = 'ACTIVE'
                if kind == 'wrong_class': ledger['attempts'][0]['operation'] = 'laptop-proof'
                if kind == 'unbound_evidence': ledger['attempts'][0]['evidence'] = []
                with self.assertRaises(ValueError): self.invoke(ledger=ledger)
                self.assertEqual(accepted_baseline(self.root)['id'], OLD)


if __name__ == '__main__': unittest.main()
