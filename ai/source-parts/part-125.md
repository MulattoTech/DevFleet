# DevFleet source part 125

Full-source UTF-8 byte interval [5766000, 5812500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 4b4607b09f334a4a29003c011fde0773a9109dea8192ec0e5f75beb2ed812a7d

<!-- BEGIN SOURCE SLICE -->
     source.write_bytes(source.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            accepted_baseline(self.root, self.v4_tuple)
        with self.assertRaises(ValueError):
            self.validator()

    def test_packaged_artifact_source_missing_or_tampered_rejected(self):
        self.bind()
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        receipt = json.loads((self.root / 'evidence/baselines/receipts' /
                              pointer['receiptFile']).read_text())
        artifact = self.root / 'evidence/baselines/sources' / (receipt['artifactReceiptSha256'] + '.json')
        original = artifact.read_bytes()
        artifact.unlink()
        with self.assertRaises(ValueError):
            accepted_baseline(self.root, self.v4_tuple)
        artifact.write_bytes(original + b' ')
        with self.assertRaises(ValueError):
            accepted_baseline(self.root, self.v4_tuple)

    def test_tampered_artifact_receipt_and_old_repair2_policy_rejected(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        before = pointer.read_bytes()
        self.artifact_receipt.write_text(self.artifact_receipt.read_text(encoding='utf-8') + ' ',
                                         encoding='utf-8')
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), before)
        self.artifact_receipt.write_text(self.artifact_receipt.read_text(encoding='utf-8').rstrip(),
                                         encoding='utf-8')
        ledger = json.loads(self.repair2.read_text(encoding='utf-8'))
        ledger['policyId'] = self.journal.REPAIR2_ID
        self.repair2.write_text(json.dumps(ledger), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), before)

    def test_extra_native_phase_before_rebind_is_rejected(self):
        owner = {'pid': 321, 'startUtc': datetime.now(timezone.utc).isoformat()}
        request = {'runId': 'repair3-diagnostic-extra', 'operation': 'diagnostic',
                   'owner': owner, 'tuple': self.v4_tuple, 'entrypoint': 'fixture.ps1',
                   'entrypointSha256': 'c' * 64, 'arguments': [],
                   'changedCondition': 'fixture premature extra phase',
                   'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
        self.journal.reserve(self.repair2, request)
        with self.assertRaises(ValueError):
            self.bind()
        self.journal.finish(self.repair2, request['runId'], owner, 0,
                            'PASS_READY_FOR_PROOF_RESERVATION',
                            [str(self.case.case.write('repair3-extra-result.json', {'status': 'PASS'}))])
        with self.assertRaises(ValueError):
            self.bind()

    def test_powershell_reader_requires_exact_new_candidate(self):
        if not shutil.which('pwsh'):
            self.skipTest('PowerShell 7 is unavailable')
        self.bind()
        tools = self.root / 'tools'
        tools.mkdir(exist_ok=True)
        shutil.copyfile(Path(__file__).with_name('baseline_lineage.py'),
                        tools / 'baseline_lineage.py')
        module = Path(__file__).resolve().parents[1] / 'automation/release-e2e/modules/BaselineLineage.psm1'
        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"
        script = self.root / 'probe-v4.ps1'
        script.write_text(
            "$ErrorActionPreference='Stop'\n"
            f"Import-Module {quote(module)} -Force\n"
            f"$f=Get-Content -Raw -LiteralPath {quote(self.tuple_path)}|ConvertFrom-Json\n"
            "$fp=[pscustomobject]@{repositoryHead=$f.repositoryHead;gitCommit=$f.candidateBuildCommit;"
            "shippingInputIdentity=$f.shippingInputIdentity;releaseFingerprintId=$f.releaseFingerprintId;"
            "toolingFingerprintId=$f.toolingFingerprintId;candidate=[pscustomobject]@{sha256=$f.candidateSha256}}\n"
            f"Get-DevFleetAcceptedBaseline -WorkspaceRoot {quote(self.root)} -Fingerprint $fp|ConvertTo-Json -Depth 6\n",
            encoding='utf-8')
        result = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['generation'], 4)
        self.tuple_path.write_text(json.dumps({**self.v4_tuple, 'candidateSha256': 'a' * 64}), encoding='utf-8')
        rejected = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)],
                                  capture_output=True, text=True, timeout=20)
        self.assertNotEqual(rejected.returncode, 0)


if __name__ == '__main__':
    unittest.main()

```


## FILE: tools/test_baseline_lineage.py

SHA256: eca3e391c660e57a494a770c0c3b46d438fa631ba299c12d697b7b271b7fa8f6 | Bytes: 19983 | Git mode: 100644

```
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
        self.root = Path(self.tmp.name)
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
                                     'evidence': [str(self.root / 'auth.json')],
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

```


## FILE: tools/test_baseline_temporal_binding.py

SHA256: 525c83dc2f0787a4c94a8d126f62c50ce383448c2c81e57be2c3e902923e8cab | Bytes: 3083 | Git mode: 100644

```
"""Reject stale, future or wrong-reservation adoption evidence without VM access."""
import copy
from datetime import datetime, timedelta, timezone
import unittest
import test_baseline_lineage as fixtures


class BaselineTemporalBindingTests(unittest.TestCase):
    def setUp(self):
        self.case = fixtures.BaselineLineageTests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)

    def reject(self, **kwargs):
        with self.assertRaises(ValueError):
            self.case.invoke(**kwargs)
        self.assertFalse((self.case.root / 'evidence/baselines/CURRENT.json').exists())

    def test_matching_terminal_native_provenance_is_accepted(self):
        result = self.case.invoke()
        self.assertFalse(result['certificationCredit'])

    def test_failed_diagnostic_cannot_supply_successful_adoption(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['exitCode'] = 2
        self.reject(ledger=ledger)

    def test_missing_diagnostic_exit_code_is_not_success(self):
        ledger = copy.deepcopy(self.case.ledger)
        del ledger['attempts'][0]['exitCode']
        self.reject(ledger=ledger)

    def test_diagnostic_reserved_for_old_tooling_is_rejected(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['tuple']['toolingFingerprintId'] = '9' * 64
        self.reject(ledger=ledger)

    def test_collector_wrong_vm_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['vm']['id'] = fixtures.NEW
        self.reject(auth=auth)

    def test_collector_wrong_candidate_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['candidate']['candidateSha256'] = '9' * 64
        self.reject(auth=auth)

    def test_collection_before_reservation_is_rejected(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['reservedUtc'] = self.case.auth['observedUtc']
        self.reject(ledger=ledger)

    def test_collection_past_owner_deadline_is_rejected(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['deadlineUtc'] = self.case.auth['startedUtc']
        self.reject(ledger=ledger)

    def test_nested_inventory_before_collection_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['nestedL2']['observedUtc'] = auth['guest']['passwordLastSetUtc']
        self.reject(auth=auth)

    def test_future_native_inventory_is_rejected(self):
        live = copy.deepcopy(self.case.live)
        live['observedUtc'] = (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()
        self.reject(live=live)

    def test_missing_collection_start_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        del auth['startedUtc']
        self.reject(auth=auth)

    def test_reversed_collection_window_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['startedUtc'] = self.case.live['observedUtc']
        self.reject(auth=auth)


if __name__ == '__main__':
    unittest.main()

```


## FILE: tools/test_compute_shipping_input_identity.py

SHA256: b9c3721b1ca80a5c911da31f18ae4493714c3b356798f9ecac0ac49573de4c50 | Bytes: 4626 | Git mode: 100644

```
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "compute_shipping_input_identity.py"


def _git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def _fixture(tmp_path: Path) -> tuple[Path, str, dict[str, Path]]:
    repo = tmp_path / "repo"
    (repo / "source" / "tools").mkdir(parents=True)
    (repo / "installer-source").mkdir()
    (repo / "tools").mkdir()
    (repo / "automation").mkdir()
    (repo / "outputs").mkdir()
    shutil.copy2(ROOT / "source" / "tools" / "release_fingerprint.py", repo / "source" / "tools" / "release_fingerprint.py")
    shutil.copy2(ROOT / "source" / "tools" / "hook_modes.py", repo / "source" / "tools" / "hook_modes.py")
    (repo / "source" / "VERSION").write_bytes(b"1.2.13\n")
    (repo / "source" / "payload.txt").write_bytes(b"alpha\nbeta\n")
    (repo / "installer-source" / "INSTALLER_VERSION").write_bytes(b"1.4.1\n")
    (repo / "installer-source" / "payload.ps1").write_bytes(b"Write-Output ok\n")
    (repo / "tools" / "release-tool.txt").write_text("one\n", encoding="utf-8")
    (repo / "automation" / "runner.txt").write_text("one\n", encoding="utf-8")
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    _git(repo, "config", "user.email", "devfleet-test@example.invalid")
    _git(repo, "config", "user.name", "DevFleet Test")
    _git(repo, "config", "core.autocrlf", "false")
    _git(repo, "add", ".")
    _git(repo, "commit", "-q", "-m", "candidate")
    commit = _git(repo, "rev-parse", "HEAD")
    artifacts = {
        "exe": repo / "outputs" / "candidate.exe",
        "tar": repo / "outputs" / "candidate.tar.gz",
        "portable": repo / "outputs" / "candidate-portable.zip",
        "installerSource": repo / "outputs" / "candidate-installer.zip",
    }
    for index, path in enumerate(artifacts.values(), 1):
        path.write_bytes((f"artifact-{index}\n").encode())
    return repo, commit, artifacts


def _run(repo: Path, commit: str, artifacts: dict[str, Path]) -> dict[str, object]:
    command = [sys.executable, str(SCRIPT), "--workspace", str(repo), "--candidate-commit", commit]
    for name, path in artifacts.items():
        command.extend(["--artifact", f"{name}={path}"])
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def test_candidate_rows_ignore_crlf_checkout_and_tooling_moves(tmp_path: Path) -> None:
    repo, commit, artifacts = _fixture(tmp_path)
    baseline = _run(repo, commit, artifacts)
    (repo / "source" / "payload.txt").write_bytes(b"alpha\r\nbeta\r\n")
    (repo / "tools" / "release-tool.txt").write_text("two\n", encoding="utf-8")
    changed = _run(repo, commit, artifacts)

    assert changed["candidateShippingInputIdentity"] == baseline["candidateShippingInputIdentity"]
    assert changed["candidateReleaseFingerprintId"] == baseline["candidateReleaseFingerprintId"]
    assert changed["liveShippingInputIdentity"] != changed["candidateShippingInputIdentity"]
    assert changed["lineEndingComparison"] == "CRLF_ONLY"
    assert changed["crlfOnlyPaths"] == ["source/payload.txt"]
    assert changed["candidateFingerprint"]["shippingInputs"] == baseline["candidateFingerprint"]["shippingInputs"]
    assert changed["liveToolingFingerprint"]["toolingFingerprintId"] != baseline["liveToolingFingerprint"]["toolingFingerprintId"]
    assert "toolingFingerprint" not in changed["candidateFingerprint"]


def test_candidate_release_fingerprint_binds_exact_artifact_tuple(tmp_path: Path) -> None:
    repo, commit, artifacts = _fixture(tmp_path)
    baseline = _run(repo, commit, artifacts)
    artifacts["exe"].write_bytes(b"changed-exe\n")
    changed = _run(repo, commit, artifacts)
    assert changed["candidateShippingInputIdentity"] == baseline["candidateShippingInputIdentity"]
    assert changed["candidateReleaseFingerprintId"] != baseline["candidateReleaseFingerprintId"]
    assert changed["candidateFingerprint"]["artifacts"] != baseline["candidateFingerprint"]["artifacts"]


def test_partial_artifact_tuple_fails_closed(tmp_path: Path) -> None:
    repo, commit, artifacts = _fixture(tmp_path)
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--workspace", str(repo), "--candidate-commit", commit, "--artifact", f"exe={artifacts['exe']}"],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "artifact tuple must be exactly" in result.stderr

```


## FILE: tools/test_failed_attempt_freeze.py

SHA256: e7e1e0c43435ce7ba04c67ba47d5e43aae7f767ac99b976388459a77731b722e | Bytes: 13077 | Git mode: 100644

```
"""Executable regression checks for the failed replacement-attempt contract."""
from __future__ import annotations

import copy
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

import pytest

import importlib.util

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("candidate_validator", ROOT / "source/tools/validate_audit_coherence.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)
AI_SPEC = importlib.util.spec_from_file_location("ai_bundle_validator", ROOT / "source/tools/validate_ai_audit_bundle.py")
AI_MODULE = importlib.util.module_from_spec(AI_SPEC)
assert AI_SPEC.loader is not None
AI_SPEC.loader.exec_module(AI_MODULE)
RELEASE_SPEC = importlib.util.spec_from_file_location("release_bundle_validator", ROOT / "tools/validate_release_bundle.py")
RELEASE_MODULE = importlib.util.module_from_spec(RELEASE_SPEC)
assert RELEASE_SPEC.loader is not None
RELEASE_SPEC.loader.exec_module(RELEASE_MODULE)


def _state() -> dict:
    snapshot = json.loads((ROOT / AI_MODULE.FAILED_ATTEMPT_SNAPSHOT).read_text(encoding="utf-8-sig"))
    attempted = json.loads((ROOT / "audit/attemptedReplacementCandidate.json").read_text(encoding="utf-8-sig"))
    artifact_rows = snapshot["candidate"]["newArtifactTuple"]["artifacts"]
    candidate = {str(row["name"]): copy.deepcopy(row) for row in artifact_rows}
    historical_artifacts = {
        name: {"bytes": expected[0], "sha256": expected[1]}
        for name, expected in MODULE.HISTORICAL_ARTIFACTS.items()
    }
    post_paths = []
    for relative in ("source/tools/validate_audit_coherence.py", "source/tools/validate_ai_audit_bundle.py"):
        post_paths.append({"path": relative, "sha256": hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()})
    return {
        "status": "BLOCKED — USER ACTION REQUIRED",
        "blocker_code": MODULE.FAILED_ATTEMPT_BLOCKER,
        "candidate_git_commit": MODULE.FAILED_ATTEMPT_COMMIT,
        "shipping_input_identity": MODULE.FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY,
        "candidate_shipping_input_identity": MODULE.FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY,
        "candidate_is_current": False,
        "source_changed_since_candidate": True,
        "rebuild_required": True,
        "artifact_tuple_matches_candidate": False,
        "full_release_passed": False,
        "internal_promotion_allowed": False,
        "public_promotion_allowed": False,
        "candidate": candidate,
        "historical_candidate": {
            "candidateCommit": MODULE.HISTORICAL_CANDIDATE,
            "shippingInputIdentity": MODULE.HISTORICAL_SHIPPING_IDENTITY,
            "releaseFingerprintId": MODULE.HISTORICAL_RELEASE_FINGERPRINT,
            "artifacts": historical_artifacts,
        },
        "failed_replacement_attempt": {
            "snapshotPath": AI_MODULE.FAILED_ATTEMPT_SNAPSHOT,
            "snapshotSha256": MODULE.FAILED_ATTEMPT_SNAPSHOT_SHA256,
            "attemptedCommit": MODULE.FAILED_ATTEMPT_COMMIT,
            "commitShippingInputIdentity": MODULE.FAILED_ATTEMPT_GIT_SHIPPING_IDENTITY,
            "buildTimeShippingInputIdentity": MODULE.FAILED_ATTEMPT_BUILD_SHIPPING_IDENTITY,
            "artifactTupleValid": True,
            "artifactTupleMatchesCandidate": False,
            "blockerCode": MODULE.FAILED_ATTEMPT_BLOCKER,
            "postFailureEvidenceTooling": {"classification": "POST_FAILURE_EVIDENCE_TOOLING", "paths": post_paths},
            "terminalEvidence": attempted["terminalEvidence"],
        },
    }


def test_failed_attempt_snapshot_is_recomputed_and_blocked():
    state = _state()
    result = MODULE._validate_failed_attempt_freeze(ROOT, state, {}, {})
    assert result["snapshotSha256"] == "ac37997945b6fa5ae9326b083ee730494b2c0c2e60d4809e7b49fc9707c0caac"
    assert result["shippingRows"] == 730
    assert result["changedRows"] == 28
    assert result["crlfOnlyRows"] == 25
    assert result["generatedShippingOutputRows"] == 3


@pytest.mark.parametrize("field,value", [
    ("candidate_is_current", True),
    ("source_changed_since_candidate", False),
    ("rebuild_required", False),
    ("artifact_tuple_matches_candidate", True),
    ("blocker_code", ""),
])
def test_failed_attempt_flags_and_blocker_fail_closed(field: str, value: object):
    state = _state()
    state[field] = value
    with pytest.raises(ValueError):
        MODULE._validate_failed_attempt_freeze(ROOT, state, {}, {})


def test_historical_tuple_remains_separate_from_attempt():
    state = _state()
    historical = state["historical_candidate"]
    assert historical["candidateCommit"] == "2739e0366d070285e44b4fc764ef9247d40b2f94"
    assert state["failed_replacement_attempt"]["attemptedCommit"] == "21752fc0e50978183322204c523b40947d073aa0"
    assert historical["releaseFingerprintId"] == "80c8b88c2f2ec828f5ab0f9713d63fa3f4cc4cbad7c382aa2f154f3196c3de84"


def test_snapshot_tamper_is_rejected(tmp_path: Path):
    source = ROOT / "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
    tampered = tmp_path / source.name
    tampered.write_bytes(source.read_bytes() + b"\n")
    state = _state()
    original = MODULE._sha256
    MODULE._sha256 = lambda path: original(tampered) if path == ROOT / "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json" else original(path)
    try:
        with pytest.raises(ValueError, match="hash-mismatched"):
            MODULE._validate_failed_attempt_freeze(ROOT, state, {}, {})
    finally:
        MODULE._sha256 = original


def _blocker_record_fixture(tmp_path: Path) -> tuple[set[str], dict]:
    records = list(AI_MODULE.FAILED_ATTEMPT_CURRENT_RECORDS)
    for relative in records:
        target = tmp_path / Path(*relative.split("/"))
        target.parent.mkdir(parents=True, exist_ok=True)
        if relative == "evidence/CURRENT-PROOF.json":
            target.write_text(json.dumps({"status": "NOT_OBSERVED", "outcome": "NOT_OBSERVED", "blockerCode": MODULE.FAILED_ATTEMPT_BLOCKER}), encoding="utf-8")
        else:
            shutil.copy2(ROOT / relative, target)
    inventory = []
    for relative in records:
        target = tmp_path / Path(*relative.split("/"))
        inventory.append({"path": relative, "bytes": target.stat().st_size, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "mode": "0644"})
    (tmp_path / "EVIDENCE-MODES.json").write_text(json.dumps([{"path": relative, "posixMode": 420, "mode": "0644", "executable": False} for relative in records]), encoding="utf-8")
    (tmp_path / "EVIDENCE-SHA256SUMS.txt").write_text("\n".join(f"{row['sha256']}  {row['path']}" for row in inventory), encoding="utf-8")
    return set(records) | {AI_MODULE.FAILED_ATTEMPT_SNAPSHOT, "EVIDENCE-MODES.json", "EVIDENCE-SHA256SUMS.txt"}, {"evidenceInventory": inventory}


def test_failed_attempt_blocker_records_are_present_and_cross_bound(tmp_path: Path):
    names, manifest = _blocker_record_fixture(tmp_path)
    AI_MODULE._validate_failed_attempt_records(tmp_path, names, manifest)


@pytest.mark.parametrize("missing", AI_MODULE.FAILED_ATTEMPT_CURRENT_RECORDS)
def test_failed_attempt_blocker_record_missing_fails_closed(tmp_path: Path, missing: str):
    names, manifest = _blocker_record_fixture(tmp_path)
    (tmp_path / Path(*missing.split("/"))).unlink()
    names.remove(missing)
    with pytest.raises(ValueError, match="missing"):
        AI_MODULE._validate_failed_attempt_records(tmp_path, names, manifest)


def test_failed_attempt_blocker_record_tamper_fails_closed(tmp_path: Path):
    names, manifest = _blocker_record_fixture(tmp_path)
    target = tmp_path / Path(*"audit/candidateBindingFailure.json".split("/"))
    target.write_text(target.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="evidenceInventory hash/mode mismatch"):
        AI_MODULE._validate_failed_attempt_records(tmp_path, names, manifest)


def test_release_bundle_failed_attempt_records_are_cross_bound(tmp_path: Path):
    names, manifest = _blocker_record_fixture(tmp_path)
    state = _state()
    (tmp_path / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (tmp_path / "CURRENT-CANDIDATE.json").write_text("{}", encoding="utf-8")
    (tmp_path / "AUDIT-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
    result = RELEASE_MODULE._validate_diagnostic(tmp_path, names | {"finalization-state.json", "CURRENT-CANDIDATE.json", "AUDIT-MANIFEST.json"})
    assert result["status"] == "PASS_WITH_BLOCKER"


@pytest.mark.parametrize("missing", ["audit/attemptedReplacementCandidate.json", "audit/candidateBindingFailure.json"])
def test_release_bundle_missing_failed_attempt_record_fails_closed(tmp_path: Path, missing: str):
    names, manifest = _blocker_record_fixture(tmp_path)
    state = _state()
    (tmp_path / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (tmp_path / "CURRENT-CANDIDATE.json").write_text("{}", encoding="utf-8")
    (tmp_path / "AUDIT-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
    names |= {"finalization-state.json", "CURRENT-CANDIDATE.json", "AUDIT-MANIFEST.json"}
    names.remove(missing)
    with pytest.raises(ValueError, match="missing"):
        RELEASE_MODULE._validate_diagnostic(tmp_path, names)


def test_ai_diagnostic_full_path_loads_manifest_before_blocker_records(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    snapshot = "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
    records = list(AI_MODULE.FAILED_ATTEMPT_CURRENT_RECORDS)
    inventory = []
    injected: dict[str, bytes] = {snapshot: (ROOT / snapshot).read_bytes()}
    for relative in records:
        data = (ROOT / relative).read_bytes()
        injected[relative] = data
        inventory.append({"path": relative, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "mode": "0644"})
    injected["EVIDENCE-MODES.json"] = json.dumps([{"path": row["path"], "posixMode": 420, "mode": "0644", "executable": False} for row in inventory]).encode()
    injected["EVIDENCE-SHA256SUMS.txt"] = "\n".join(f"{row['sha256']}  {row['path']}" for row in inventory).encode()
    observed: dict[str, object] = {}
    original_extract = AI_MODULE._extract
    def fake_extract(archive: Path, extracted: Path) -> set[str]:
        names = set(original_extract(archive, extracted))
        for relative, data in injected.items():
            target = extracted / Path(*relative.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            names.add(relative)
        manifest_path = extracted / "AUDIT-MANIFEST.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        manifest["evidenceInventory"] = inventory
        manifest_path.write_text(json.dumps(manifest) + "\n", encoding="utf-8")
        candidate_path = extracted / "CURRENT-CANDIDATE.json"
        candidate = json.loads(candidate_path.read_text(encoding="utf-8-sig"))
        # This fixture models a failed replacement, not whatever candidate
        # flags happen to be present in the latest diagnostic archive.
        candidate["candidateIsCurrent"] = False
        candidate["sourceChangedSinceCandidate"] = True
        candidate["rebuildRequired"] = True
        candidate["artifactTupleMatchesCandidate"] = False
        candidate_path.write_text(json.dumps(candidate) + "\n", encoding="utf-8")
        return names
    monkeypatch.setattr(AI_MODULE, "_extract", fake_extract)
    def fake_records(extracted: Path, names: set[str], loaded_manifest: dict) -> None:
        observed["manifest"] = loaded_manifest
    monkeypatch.setattr(AI_MODULE, "_validate_failed_attempt_records", fake_records)
    monkeypatch.setattr(AI_MODULE, "_run_candidate_validator", lambda command, cwd, mode: {"status": "PASS_WITH_BLOCKER", "blockerCode": "REPLACEMENT_CANDIDATE_BINDING_MISMATCH", "releaseEligible": False})
    result = AI_MODULE.validate(ROOT / "outputs/DevFleet-v1.2.13-AI-Audit-LATEST.zip", mode="diagnostic")
    assert result["status"] == "PASS_WITH_BLOCKER"
    assert isinstance(observed.get("manifest"), dict)


@pytest.mark.parametrize("manifest_bytes", [b"", b"not-json"])
def test_ai_diagnostic_malformed_or_missing_manifest_fails_closed(tmp_path: Path, manifest_bytes: bytes):
    entries: dict[str, bytes] = {}
    with zipfile.ZipFile(ROOT / "outputs/DevFleet-v1.2.13-AI-Audit-LATEST.zip") as archive:
        entries = {name: archive.read(name) for name in archive.namelist() if not name.endswith("/")}
    if manifest_bytes:
        entries["AUDIT-MANIFEST.json"] = manifest_bytes
    else:
        entries.pop("AUDIT-MANIFEST.json", None)
    archive_path = tmp_path / "malformed.zip"
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    with pytest.raises(Exception):
        AI_MODULE.validate(archive_path, mode="diagnostic")

```


## FILE: tools/test_final_acceptance_tools.py

SHA256: caa0b34b7f7a797a2efbfacb5a191411923aecc6ba23849b6cb0c8724f9bc9a4 | Bytes: 3415 | Git mode: 100644

```
"""Focused static contract gua