"""VM-free Gen7 collision successor binding and frozen source rejection."""
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import unittest
from unittest.mock import patch

import baseline_lineage as lineage
import test_baseline_generation6 as generation6


class Generation7Tests(unittest.TestCase):
    def setUp(self):
        self.case = generation6.Generation6Tests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        self.gen6 = self.case.bind()
        self.old = self.case.new_tuple
        self.new = {**self.old, 'repositoryHead': 'd' * 40,
                    'toolingFingerprintId': 'e' * 64}
        self.tuple_path = self.write('gen7-tuple.json', self.new)
        self.pointer_path = self.root / 'evidence/baselines/CURRENT.json'
        self.approval = {'schemaVersion': 7,
                         'contract': 'devfleet-baseline-rebind-approval-v7',
                         'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                         'shippingChangeApproved': False,
                         'previousCandidate': self.old, 'candidate': self.new,
                         'replacement': json.loads(self.pointer_path.read_text())['checkpoint'],
                         'previousReceiptSha256': self.gen6['receiptSha256']}
        self.approval_path = self.write('gen7-approval.json', self.approval)
        self.case.pass_attempt(self.case.ledger, 'diagnostic', 'causal-ready', self.old,
                               0, 'PASS_READY_FOR_PROOF_RESERVATION')
        self.case.pass_attempt(self.case.ledger, 'laptop-proof', 'causal-failed-laptop',
                               self.old, 2, 'NATIVE_LAPTOP_PROOF_BLOCKED')
        self.predecessor = self.root / 'causal-terminal-snapshot.json'
        self.predecessor.write_bytes(self.case.ledger.read_bytes())
        old_predecessor_hash = lineage.COLLISION_PREDECESSOR_SHA256
        lineage.COLLISION_PREDECESSOR_SHA256 = lineage.digest(self.predecessor)
        self.addCleanup(setattr, lineage, 'COLLISION_PREDECESSOR_SHA256', old_predecessor_hash)
        self.failures = {
            'wrapper': self.write('collision-wrapper.json', {
                'runId': 'causal-failed-laptop', 'classification': 'NATIVE_LAPTOP_PROOF_BLOCKED',
                'exitCode': 2, 'firstTechnicalFailure': lineage.COLLISION_FIRST_ERROR,
                'observerTerminal': 'NO_PROGRESS_TIMEOUT'}),
            'proofError': self.write('collision-proof-error.json', {
                'runId': 'causal-failed-laptop', 'status': 'BLOCKED',
                'error': lineage.COLLISION_FIRST_ERROR}),
            'cleanup': self.write('collision-cleanup.json', {
                'runId': 'causal-failed-laptop', 'status': 'PASS',
                'runOwnedOnly': True,
                'l1': {'name': lineage.VM_NAME, 'id': lineage.VM_ID, 'status': 'OFF'},
                'l2': {'expectedName': lineage.L2_NAME, 'status': 'ABSENT',
                       'present': False, 'exactMatchCount': 0, 'inventoryCount': 0},
                'l2Present': False})}
        self.owner_path = self.root / 'owner-authorization.txt'
        self.owner_path.write_text('synthetic owner authorization only', encoding='utf-8')
        self.owner_hash = lineage.digest(self.owner_path)
        old_owner_hash = lineage.OWNER_AUTH_SHA256
        lineage.OWNER_AUTH_SHA256 = self.owner_hash
        self.addCleanup(setattr, lineage, 'OWNER_AUTH_SHA256', old_owner_hash)
        self.auth_path = self.write('collision-auth.json', {
            'schemaVersion': 1, 'kind': 'DEVFLEET_POST_COLLISION_SUCCESSOR_AUTHORIZATION',
            'policyId': 'DF-FRESH-CERTIFICATION-20260930-COLLISION-1',
            'approved': True, 'approvedBy': 'ACCOUNT_OWNER',
            'ownerAuthorization': {'path': str(self.owner_path), 'sha256': self.owner_hash},
            'successorLedgerPath': str(self.root / 'collision-ledger.json'),
            'predecessorSha256': {'causal1': lineage.digest(self.predecessor)},
            'failedRunId': 'causal-failed-laptop',
            'previousCandidate': self.old, 'candidate': self.new,
            'generation6': {'receiptPath': str(self.root / 'evidence/baselines/receipts' / self.gen6['receiptFile']),
                            'receiptSha256': self.gen6['receiptSha256'],
                            'checkpoint': self.approval['replacement']},
            'reviewedSources': {'proposal': {'path': str(self.predecessor), 'sha256': lineage.digest(self.predecessor)},
                                'source': {'path': str(self.predecessor), 'sha256': lineage.digest(self.predecessor)}},
            'failureEvidence': {key: {'path': str(path), 'sha256': lineage.digest(path)}
                                for key, path in self.failures.items()},
            'limits': {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                       'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}})
        self.approval['successorAuthorizationSha256'] = lineage.digest(self.auth_path)
        self.approval_path = self.write('gen7-approval.json', self.approval)
        self.outer_run_id = 'standard-token-collision-outer'
        self.ledger = self.write('collision-ledger.json', {
            **json.loads(self.case.ledger.read_text()),
            'policyId': 'DF-FRESH-CERTIFICATION-20260930-COLLISION-1',
            'authorization': {'path': str(self.auth_path), 'sha256': lineage.digest(self.auth_path)},
            'predecessors': [{'path': str(self.predecessor), 'sha256': lineage.digest(self.predecessor)}],
            'attempts': [{**json.loads(self.case.ledger.read_text())['attempts'][0],
                          'tuple': self.new, 'runId': self.outer_run_id}]})
        old_ledger_path = lineage.COLLISION_LEDGER_PATH
        lineage.COLLISION_LEDGER_PATH = self.ledger
        self.addCleanup(setattr, lineage, 'COLLISION_LEDGER_PATH', old_ledger_path)
        live = json.loads(self.case.live_path.read_text())
        self.live_path = self.write('collision-live.json', {**live, 'observedUtc': datetime.now(timezone.utc).isoformat()})
        self.run_id = 'standard-token-collision-inner'
        self.token_dir = self.root / 'evidence/standard-token' / self.run_id
        self.token_dir.mkdir(parents=True)
        self.raw = self.token_dir / 'installer-self-test-raw.txt'
        self.raw.write_text('PASS\npayload=' + 'b' * 64 + '\n', encoding='utf-8')
        self.canonical = self.token_dir / 'standard-token-evidence.json'
        runner_relative = 'automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1'
        runner = self.root / runner_relative
        runner.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(Path(__file__).resolve().parents[1] / runner_relative, runner)
        token_rel = f'evidence/standard-token/{self.run_id}'
        self.token = {'schemaVersion': 1, 'runId': self.run_id, 'status': 'PASS',
                      'standardNonAdministratorToken': True, 'exitCode': 0,
                      'residualSelfTestScratchCount': 0,
                      'runDirectory': token_rel,
                      'rawReportPath': token_rel + '/installer-self-test-raw.txt',
                      'canonicalEvidencePath': token_rel + '/standard-token-evidence.json',
                      'generatedAtUtc': datetime.now(timezone.utc).isoformat(),
                      **{key: value for key, value in self.new.items() if key != 'candidateSha256'},
                      'exe': {'sha256': self.new['candidateSha256'], 'bytes': 123},
                      'tar': {'sha256': 'b' * 64, 'bytes': 456},
                      'runner': {'path': runner_relative, 'sha256': lineage.digest(runner)},
                      'reportSha256': lineage.digest(self.raw),
                      'requiredChecks': {name: True for name in
                         ('pass', 'payloadExtraction', 'bootstrapEntrypoint', 'parameterContract',
                          'embeddedTarCount', 'factoryResetBackupGate', 'planSafety',
                          'devfleetVersion', 'installerVersion', 'payloadSha')},
                      'token': {'userName': 'MULATTOTECHBOX\\Developer',
                                'standardNonAdministratorToken': True,
                                'isAdministratorMember': False,
                                'isAdministratorEnabled': False,
                                'isElevated': False, 'integrityLevel': 'Medium'}}
        self.canonical.write_text(json.dumps(self.token), encoding='utf-8')
        self.token_pointer = self.root / 'evidence/CURRENT-STANDARD-TOKEN.json'
        self.token_pointer.write_bytes(self.canonical.read_bytes())
        ledger = json.loads(self.ledger.read_text())
        ledger['attempts'][0]['reservedUtc'] = '2026-01-01T00:00:00-05:00'
        ledger['attempts'][0]['terminalUtc'] = '2099-01-01T00:00:00-05:00'
        ledger['attempts'][0]['evidence'] = [str(self.canonical)]
        self.write('collision-ledger.json', ledger)

    def write(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding='utf-8')
        return path

    def bind(self):
        with patch.object(lineage.subprocess, 'run') as run:
            run.return_value.returncode = 0
            run.return_value.stdout = json.dumps({'policyId': 'DF-FRESH-CERTIFICATION-20260930-COLLISION-1',
                'active': None, 'attemptCount': 1,
                'remaining': {'standard-token': 0, 'diagnostic': 1, 'laptop-proof': 1,
                              'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}})
            return lineage.rebind_gen7(self.root, self.tuple_path, self.approval_path,
                                       self.ledger, self.live_path, self.token_pointer)

    def test_bind_freezes_full_chain_and_token_sources(self):
        old_pointer = self.pointer_path.read_bytes()
        result = self.bind()
        self.assertEqual(result['generation'], 7)
        self.assertEqual((self.root / 'evidence/baselines/history' / (lineage.hashlib.sha256(old_pointer).hexdigest() + '.json')).read_bytes(), old_pointer)
        receipt = json.loads((self.root / 'evidence/baselines/receipts' / result['receiptFile']).read_text())
        self.assertEqual(receipt['standardTokenEvidence']['runId'], self.run_id)
        self.assertEqual(receipt['standardTokenEvidence']['pointerSha256'], lineage.digest(self.token_pointer))
        self.assertEqual(receipt['failureEvidenceSha256']['wrapper'], lineage.digest(self.failures['wrapper']))
        with self.assertRaises(ValueError): self.bind()

    def test_invalid_token_and_approval_fail_before_pointer_change(self):
        before = self.pointer_path.read_bytes()
        self.token['token']['isElevated'] = True
        self.canonical.write_text(json.dumps(self.token), encoding='utf-8')
        self.token_pointer.write_bytes(self.canonical.read_bytes())
        with self.assertRaises(ValueError): self.bind()
        self.assertEqual(self.pointer_path.read_bytes(), before)

    def test_wrong_predecessor_shipping_and_live_inventory_reject_before_append(self):
        before = self.pointer_path.read_bytes()
        pointer = json.loads(before)
        self.pointer_path.write_text(json.dumps({**pointer, 'generation': 5}), encoding='utf-8')
        with self.assertRaises(ValueError): self.bind()
        self.pointer_path.write_bytes(before)
        self.write('gen7-tuple.json', {**self.new, 'candidateSha256': 'f' * 64})
        with self.assertRaises(ValueError): self.bind()
        self.write('gen7-tuple.json', self.new)
        live = json.loads(self.live_path.read_text())
        self.write('collision-live.json', {**live, 'observedUtc': '2000-01-01T00:00:00Z'})
        with self.assertRaises(ValueError): self.bind()
        self.write('collision-live.json', {**live, 'vm': {**live['vm'], 'state': 'Running'}})
        with self.assertRaises(ValueError): self.bind()
        self.assertEqual(self.pointer_path.read_bytes(), before)

    def test_interrupted_append_preserves_old_pointer_and_refuses_duplicate_history(self):
        before = self.pointer_path.read_bytes()
        original = lineage._atomic_replace
        def fail_pointer(path, content):
            target = Path(path)
            if target.name.lower() == 'current.json' and target.parent.name.lower() == 'baselines':
                raise OSError('synthetic pointer publish interruption')
            return original(path, content)
        with patch.object(lineage, '_atomic_replace', side_effect=fail_pointer):
            with self.assertRaises(OSError): self.bind()
        self.assertEqual(self.pointer_path.read_bytes(), before)
        with self.assertRaises((OSError, ValueError)): self.bind()
        self.assertEqual(self.pointer_path.read_bytes(), before)

    def test_owner_collision_and_outer_inner_gates_fail_closed(self):
        before = self.pointer_path.read_bytes()
        self.write('gen7-approval.json', {**self.approval, 'decision': 'PENDING'})
        with self.assertRaises(ValueError): self.bind()
        self.write('gen7-approval.json', self.approval)
        wrapper = json.loads(self.failures['wrapper'].read_text())
        self.write('collision-wrapper.json', {**wrapper, 'firstTechnicalFailure': 'later observer timeout'})
        with self.assertRaises(ValueError): self.bind()
        self.write('collision-wrapper.json', wrapper)
        ledger = json.loads(self.ledger.read_text())
        ledger['attempts'][0]['evidence'] = ['outer-result.json']
        self.write('collision-ledger.json', ledger)
        with self.assertRaises(ValueError): self.bind()
        self.assertEqual(self.pointer_path.read_bytes(), before)

    def test_reader_rejects_frozen_source_and_live_pointer_drift(self):
        result = self.bind()
        source = self.root / 'evidence/baselines/sources' / (lineage.digest(self.raw) + '.txt')
        source.write_bytes(source.read_bytes() + b'tamper')
        with self.assertRaises(ValueError): lineage.accepted_baseline(self.root, self.new)
        source.write_bytes(self.raw.read_bytes())
        self.token_pointer.write_bytes(self.token_pointer.read_bytes() + b' ')
        with self.assertRaises(ValueError): lineage.accepted_baseline(self.root, self.new)

    def test_reader_requires_exact_frozen_owner_approval_source(self):
        result = self.bind()
        receipt = json.loads((self.root / 'evidence/baselines/receipts' /
                              result['receiptFile']).read_text())
        source = self.root / 'evidence/baselines/sources' / (receipt['approvalSha256'] + '.json')
        self.assertTrue(source.is_file(), 'Gen7 binder did not freeze owner approval bytes')
        original = source.read_bytes()
        source.unlink()
        with self.assertRaises(ValueError): lineage.accepted_baseline(self.root, self.new)
        source.write_bytes(original + b' ')
        with self.assertRaises(ValueError): lineage.accepted_baseline(self.root, self.new)
        source.write_bytes(original)
        altered = {**json.loads(original), 'reviewNote': 'unapproved addition'}
        altered_path = self.root / 'altered-owner-approval.json'
        altered_path.write_text(json.dumps(altered), encoding='utf-8')
        altered_sha = lineage.digest(altered_path)
        (source.parent / (altered_sha + '.json')).write_bytes(altered_path.read_bytes())
        receipt['approvalSha256'] = altered_sha
        receipt['approval']['sourceSha256'] = altered_sha
        receipt_path = self.root / 'evidence/baselines/receipts' / result['receiptFile']
        receipt_path.write_text(json.dumps(receipt), encoding='utf-8')
        pointer = json.loads(self.pointer_path.read_text())
        pointer['receiptSha256'] = lineage.digest(receipt_path)
        self.pointer_path.write_text(json.dumps(pointer), encoding='utf-8')
        with self.assertRaises(ValueError): lineage.accepted_baseline(self.root, self.new)


if __name__ == '__main__':
    unittest.main()
