"""Focused append-only Generation-8 lineage tests; all fixtures are synthetic."""
import json
import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import baseline_lineage as lineage


HERE = Path(__file__).resolve().parent
FRESH_TESTS = HERE.parent / '.agents' / 'skills' / 'devfleet-certification-orchestrator' / 'scripts' / 'fresh'


def sha(path):
    return lineage.digest(path)


def write_json(path, value):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(value), encoding='utf-8')


def load_test_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Generation8DispatchTests(unittest.TestCase):
    def test_generation8_pointer_uses_strict_generation8_reader(self):
        with tempfile.TemporaryDirectory(prefix='devfleet-gen8-dispatch-') as scratch:
            root = Path(scratch)
            state = root / 'evidence' / 'baselines'
            state.mkdir(parents=True)
            pointer = {
                'schemaVersion': 8,
                'contract': 'devfleet-accepted-baseline-v8',
                'generation': 8,
                'status': 'ACCEPTED',
                'receiptFile': 'a' * 32 + '.json',
                'receiptSha256': 'b' * 64,
                'previousPointerSha256': 'c' * 64,
                'checkpoint': {'name': 'DevFleet-E2E-CLEAN-R2',
                               'id': '1e84fdaf-45f9-417e-a93c-354d05b4c766'},
            }
            (state / 'CURRENT.json').write_text(json.dumps(pointer), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Generation-8'):
                lineage.accepted_baseline(root)


class Generation8AppendTests(unittest.TestCase):
    def setUp(self):
        gen7_module = load_test_module('generation7_fixture_for_gen8',
                                       HERE / 'test_baseline_generation7.py')
        self.gen7 = gen7_module.Generation7Tests(methodName='runTest')
        self.gen7.setUp()
        self.addCleanup(self.gen7.doCleanups)
        self.old = dict(self.gen7.new)
        self.new = dict(self.old, repositoryHead='f' * 40,
                        toolingFingerprintId='a' * 64)
        self.gen7_result = self.gen7.bind()
        self.pointer_path = self.gen7.root / 'evidence/baselines/CURRENT.json'
        self.prior_pointer = self.pointer_path.read_bytes()
        self.gen7.pointer = json.loads(self.prior_pointer)
        fresh_module = load_test_module(
            'http_cleanup_fixture_for_gen8',
            FRESH_TESTS / 'test_http_cleanup_successor.py')
        self.http = fresh_module.HttpCleanupAdmissionFixture(
            self, successor_tuple=self.new, generation7=self.gen7,
            public_main_sha='c' * 40)
        self.addCleanup(self.http.base.doCleanups)
        predecessor_pin = patch.object(
            lineage, 'HTTP_CLEANUP_PREDECESSOR_SHA256',
            self.http.predecessor_sha256)
        predecessor_pin.start()
        self.addCleanup(predecessor_pin.stop)
        ledger_pin = patch.object(lineage, 'HTTP_CLEANUP_LEDGER_PATH', self.http.ledger)
        ledger_pin.start()
        self.addCleanup(ledger_pin.stop)
        self.http.initialize()
        self.ledger_path = self.http.ledger
        self.live_path = self.gen7.live_path
        self.token_pointer = self._make_current_token()
        self._charge_token()
        self.tuple_path = self.http.root / 'gen8-tuple.json'
        write_json(self.tuple_path, self.new)
        self.owner_path = self.http.owner_source
        self.approval_path = self.http.root / 'gen8-approval.json'
        self.approval = {
            'schemaVersion': 8,
            'contract': 'devfleet-baseline-rebind-approval-v8',
            'decision': 'APPROVE',
            'approvedBy': 'ACCOUNT_OWNER',
            'shippingChangeApproved': False,
            'previousCandidate': self.old,
            'candidate': self.new,
            'replacement': self.gen7.pointer['checkpoint'],
            'previousReceiptSha256': self.gen7_result['receiptSha256'],
            'successorPolicyId': 'DF-FRESH-CERTIFICATION-20261001-HTTP-CLEANUP-1',
            'successorLedgerPath': str(self.ledger_path),
            'successorLedgerSha256': sha(self.ledger_path),
            'successorAuthorizationSha256': sha(self.http.auth),
            'ownerAuthorization': {'path': str(self.owner_path), 'sha256': sha(self.owner_path)},
            'publicMainSha': self.http.public_main_sha,
        }
        write_json(self.approval_path, self.approval)

    def _make_current_token(self):
        run_id = 'standard-token-gen8-inner-001'
        relative = f'evidence/standard-token/{run_id}'
        token_dir = self.gen7.root / relative
        token_dir.mkdir(parents=True)
        raw = token_dir / 'installer-self-test-raw.txt'
        raw.write_text('PASS\npayload=' + self.gen7.token['tar']['sha256'] + '\n',
                       encoding='utf-8')
        token = dict(self.gen7.token)
        token.update({key: value for key, value in self.new.items()
                      if key != 'candidateSha256'})
        token.update({
            'runId': run_id,
            'runDirectory': relative,
            'rawReportPath': relative + '/installer-self-test-raw.txt',
            'canonicalEvidencePath': relative + '/standard-token-evidence.json',
            'generatedAtUtc': datetime.now(timezone.utc).isoformat(),
            'reportSha256': sha(raw),
        })
        token_path = token_dir / 'standard-token-evidence.json'
        write_json(token_path, token)
        pointer = self.gen7.root / 'evidence/CURRENT-STANDARD-TOKEN.json'
        pointer.write_bytes(token_path.read_bytes())
        return pointer

    def _charge_token(self):
        request = self.http.request('standard-token', 'gen8-standard-token-outer', self.new)
        self.http.journal.reserve(self.ledger_path, request)
        token_path = self.gen7.root / 'evidence/standard-token/standard-token-gen8-inner-001/standard-token-evidence.json'
        token = json.loads(token_path.read_text(encoding='utf-8'))
        token['generatedAtUtc'] = datetime.now(timezone.utc).isoformat()
        write_json(token_path, token)
        self.token_pointer.write_bytes(token_path.read_bytes())
        token_run = self.gen7.root / 'evidence/standard-token/standard-token-gen8-inner-001/standard-token-evidence.json'
        evidence = token_run.relative_to(self.gen7.root)
        self.http.journal.finish(self.ledger_path, request['runId'], request['owner'], 0,
                                 'PASS_NATIVE_STANDARD_TOKEN', [str(evidence)])

    def bind(self):
        with patch.object(lineage.subprocess, 'run') as run:
            run.return_value.returncode = 0
            run.return_value.stdout = json.dumps({
                'policyId': 'DF-FRESH-CERTIFICATION-20261001-HTTP-CLEANUP-1',
                'active': None, 'attemptCount': 1,
                'remaining': {'standard-token': 0, 'diagnostic': 1,
                              'laptop-proof': 1, 'desktop-proof': 1,
                              'fullrelease': 1, 'maintenance': 0, 'build-sign': 0}})
            return lineage.rebind_gen8(self.gen7.root, self.tuple_path,
                                       self.approval_path, self.ledger_path,
                                       self.live_path, self.token_pointer)

    def test_rebind_appends_from_exact_gen7_and_preserves_shipping(self):
        result = self.bind()
        self.assertEqual(result['generation'], 8)
        self.assertEqual(result['id'], self.gen7_result['id'])
        self.assertEqual(result['candidate'], self.new)
        self.assertEqual(self.pointer_path.read_bytes() != self.prior_pointer, True)
        receipt = json.loads((self.gen7.root / 'evidence/baselines/receipts' /
                              result['receiptFile']).read_text())
        self.assertEqual(receipt['previousReceiptSha256'], self.gen7_result['receiptSha256'])
        for field in ('candidateBuildCommit', 'shippingInputIdentity',
                      'releaseFingerprintId', 'candidateSha256'):
            self.assertEqual(self.old[field], self.new[field])

    def test_reader_rejects_tuple_mismatch_and_duplicate_append_preserves_pointer(self):
        self.bind()
        with self.assertRaisesRegex(ValueError, 'another candidate/material tuple'):
            lineage.accepted_baseline(
                self.gen7.root, dict(self.new, repositoryHead='e' * 40))
        before = self.pointer_path.read_bytes()
        with self.assertRaisesRegex(ValueError, 'requires the exact currently accepted Generation-7'):
            self.bind()
        self.assertEqual(self.pointer_path.read_bytes(), before)

    def test_reader_rejects_tampered_frozen_approval_source(self):
        result = self.bind()
        receipt = json.loads((self.gen7.root / 'evidence/baselines/receipts' /
                              result['receiptFile']).read_text())
        frozen_approval = (self.gen7.root / 'evidence/baselines/sources' /
                           (receipt['approvalSha256'] + '.json'))
        frozen_approval.write_text('{}', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'frozen source is missing or changed'):
            lineage.accepted_baseline(self.gen7.root, self.new)

    def _rewrite_current_receipt(self, result, receipt):
        state = self.gen7.root / 'evidence/baselines'
        receipt_path = state / 'receipts' / result['receiptFile']
        write_json(receipt_path, receipt)
        pointer = json.loads(self.pointer_path.read_text(encoding='utf-8'))
        pointer['receiptSha256'] = sha(receipt_path)
        write_json(self.pointer_path, pointer)

    def test_reader_rejects_approval_omitted_from_source_closure(self):
        result = self.bind()
        receipt_path = (self.gen7.root / 'evidence/baselines/receipts' /
                        result['receiptFile'])
        receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
        receipt['sourceClosure'] = [
            row for row in receipt['sourceClosure']
            if not (row['sha256'] == receipt['approvalSha256']
                    and row['extension'] == '.json')]
        self._rewrite_current_receipt(result, receipt)
        with self.assertRaisesRegex(ValueError, 'approval is absent from source closure'):
            lineage.accepted_baseline(self.gen7.root, self.new)

    def test_reader_rejects_frozen_token_document_path_mismatch(self):
        result = self.bind()
        state = self.gen7.root / 'evidence/baselines'
        receipt_path = state / 'receipts' / result['receiptFile']
        receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
        token_ref = receipt['standardTokenEvidence']
        old_hash = token_ref['canonicalSha256']
        token_path = state / 'sources' / (old_hash + '.json')
        token = json.loads(token_path.read_text(encoding='utf-8'))
        token['runDirectory'] = 'evidence/standard-token/forged'
        replacement = state / 'sources' / 'forged-token.json'
        write_json(replacement, token)
        new_hash = sha(replacement)
        canonical_bytes = replacement.read_bytes()
        replacement.unlink()
        (state / 'sources' / (new_hash + '.json')).write_bytes(canonical_bytes)
        receipt['sourceClosure'] = [
            row for row in receipt['sourceClosure']
            if not (row['sha256'] == old_hash and row['extension'] == '.json')]
        receipt['sourceClosure'].append({'sha256': new_hash, 'extension': '.json'})
        token_ref['pointerSha256'] = new_hash
        token_ref['canonicalSha256'] = new_hash
        self._rewrite_current_receipt(result, receipt)
        with self.assertRaisesRegex(ValueError, 'token document paths differ'):
            lineage.accepted_baseline(self.gen7.root, self.new)

    def test_reader_rejects_non_gen7_predecessor_pointer(self):
        self.bind()
        current = json.loads(self.pointer_path.read_text(encoding='utf-8'))
        state = self.gen7.root / 'evidence/baselines'
        wrong_parent = dict(self.gen7.pointer, generation=6)
        wrong_parent_tmp = state / 'history' / 'wrong-parent.tmp'
        write_json(wrong_parent_tmp, wrong_parent)
        wrong_parent_hash = sha(wrong_parent_tmp)
        wrong_parent_path = state / 'history' / (wrong_parent_hash + '.json')
        wrong_parent_tmp.replace(wrong_parent_path)
        current['previousPointerSha256'] = wrong_parent_hash
        write_json(self.pointer_path, current)
        with self.assertRaisesRegex(ValueError, 'predecessor must be the accepted Generation-7'):
            lineage.accepted_baseline(self.gen7.root, self.new)

    def test_interrupted_append_leaves_gen7_current_and_rejects_retry(self):
        before = self.pointer_path.read_bytes()
        with patch.object(lineage, '_atomic_replace', side_effect=OSError('simulated interruption')):
            with self.assertRaisesRegex(OSError, 'simulated interruption'):
                self.bind()
        self.assertEqual(self.pointer_path.read_bytes(), before)
        self.assertEqual(lineage.accepted_baseline(self.gen7.root, self.old)['generation'], 7)
        with self.assertRaises(FileExistsError):
            self.bind()
        self.assertEqual(self.pointer_path.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
