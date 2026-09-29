"""VM-free generation-5 validator checks for the immutable gen4 chain."""
import copy
import json
import unittest

from test_baseline_generation4 import Generation4Tests
from validate_release_bundle import load_accepted_baseline, sha


class Generation5ValidatorTests(unittest.TestCase):
    def setUp(self):
        self.case = Generation4Tests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        self.case.bind()
        pointer_path = self.root / 'evidence/baselines/CURRENT.json'
        self.previous_pointer = json.loads(pointer_path.read_text(encoding='utf-8'))
        previous_bytes = pointer_path.read_bytes()
        previous_hash = sha(pointer_path)
        (self.root / 'evidence/baselines/history' / (previous_hash + '.json')).write_bytes(previous_bytes)
        self.old = self.case.v4_tuple
        self.new = {**self.old, 'repositoryHead': 'e' * 40,
                    'toolingFingerprintId': '1' * 64}
        sources = self.root / 'evidence/baselines/sources'
        old_receipt = json.loads(
            (self.root / 'evidence/baselines/receipts' /
             self.previous_pointer['receiptFile']).read_text(encoding='utf-8'))
        old_ledger_path = sources / (old_receipt['successorLedgerSha256'] + '.json')
        ledger = json.loads(old_ledger_path.read_text(encoding='utf-8'))
        ledger['policyId'] = 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5'
        ledger['attempts'] = [{**ledger['attempts'][0], 'tuple': self.new,
                              'operation': 'standard-token', 'state': 'TERMINAL',
                              'exitCode': 0, 'classification': 'PASS_NATIVE_STANDARD_TOKEN',
                              'certificationCredit': False, 'evidence': ['gen5-proof.json']}]
        ledger_path = self.root / 'gen5-ledger.json'
        ledger_path.write_text(json.dumps(ledger), encoding='utf-8')
        inventory_path = sources / (old_receipt['nativeInventorySha256'] + '.json')
        ledger_hash = sha(ledger_path)
        inventory_hash = sha(inventory_path)
        sources.joinpath(ledger_hash + '.json').write_bytes(ledger_path.read_bytes())
        receipt_id = '5' * 32
        receipt = {
            'schemaVersion': 5, 'contract': 'devfleet-baseline-rebind-receipt-v5',
            'receiptId': receipt_id, 'status': 'REBOUND',
            'certificationCredit': False, 'secretValuesRecorded': False,
            'previousPointerSha256': previous_hash,
            'previousReceiptSha256': self.previous_pointer['receiptSha256'],
            'replacement': self.previous_pointer['checkpoint'],
            'previousCandidate': self.old, 'candidate': self.new,
            'approvalSha256': 'a' * 64,
            'approval': {
                'schemaVersion': 4, 'contract': 'devfleet-baseline-rebind-approval-v4',
                'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                'shippingChangeApproved': False, 'previousCandidate': self.old,
                'candidate': self.new, 'replacement': self.previous_pointer['checkpoint'],
                'previousReceiptSha256': self.previous_pointer['receiptSha256'],
                'sourceSha256': 'a' * 64},
            'finalL1': {'name': 'DevFleet-E2E-Win11-01',
                        'id': '84b7d8b8-ee6c-4085-aa29-4b0adc316de2', 'state': 'Off'},
            'successorPolicyId': 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5',
            'successorLedgerSha256': ledger_hash,
            'nativeInventorySha256': inventory_hash,
        }
        receipt_path = self.root / 'evidence/baselines/receipts' / (receipt_id + '.json')
        receipt_path.write_text(json.dumps(receipt), encoding='utf-8')
        pointer = {'schemaVersion': 5, 'contract': 'devfleet-accepted-baseline-v5',
                   'generation': 5, 'status': 'ACCEPTED',
                   'receiptFile': receipt_id + '.json', 'receiptSha256': sha(receipt_path),
                   'previousPointerSha256': previous_hash,
                   'checkpoint': self.previous_pointer['checkpoint']}
        pointer_path.write_text(json.dumps(pointer), encoding='utf-8')

    def validate(self):
        expected = {'repositoryHead': self.new['repositoryHead'],
                    'candidateCommit': self.new['candidateBuildCommit'],
                    'shippingInputIdentity': self.new['shippingInputIdentity'],
                    'releaseFingerprintId': self.new['releaseFingerprintId'],
                    'toolingFingerprintId': self.new['toolingFingerprintId']}
        return load_accepted_baseline(self.root, expected, {'exe': self.new['candidateSha256']})

    def test_exact_gen5_chain_is_accepted(self):
        result = self.validate()
        self.assertTrue(result['receiptSha256'])
        self.assertEqual(result['name'], 'DevFleet-E2E-CLEAN-R2')

    def test_gen5_requires_owner_schema_and_single_terminal_attempt(self):
        receipt_path = self.root / 'evidence/baselines/receipts' / ('5' * 32 + '.json')
        receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
        receipt['approval']['schemaVersion'] = 2
        receipt_path.write_text(json.dumps(receipt), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.validate()
        receipt['approval']['schemaVersion'] = 4
        receipt_path.write_text(json.dumps(receipt), encoding='utf-8')
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text(encoding='utf-8'))
        pointer['receiptSha256'] = sha(receipt_path)
        (self.root / 'evidence/baselines/CURRENT.json').write_text(json.dumps(pointer), encoding='utf-8')
        source_hash = receipt['successorLedgerSha256']
        source = self.root / 'evidence/baselines/sources' / (source_hash + '.json')
        ledger = json.loads(source.read_text(encoding='utf-8'))
        ledger['attempts'].append(copy.deepcopy(ledger['attempts'][0]))
        source.write_text(json.dumps(ledger), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.validate()


if __name__ == '__main__':
    unittest.main()
