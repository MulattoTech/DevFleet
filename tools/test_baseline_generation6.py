"""VM-free same-shipping binding; synthetic fixtures never grant native credit."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import subprocess
import unittest

import baseline_lineage
import test_baseline_generation5 as generation5
from validate_release_bundle import load_accepted_baseline


class Generation6Tests(unittest.TestCase):
    def setUp(self):
        self.case = generation5.Generation5Tests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        self.v5 = self.case.bind()
        self.j = self.case.journal
        self.new_tuple = {**self.case.v5_tuple, 'repositoryHead': '6' * 40,
                          'toolingFingerprintId': '5' * 64}
        self.pass_attempt(self.case.repair5, 'diagnostic', 'old-readiness',
                          self.case.v5_tuple, 0, 'PASS_READY_FOR_PROOF_RESERVATION')
        self.pass_attempt(self.case.repair5, 'laptop-proof', 'old-laptop',
                          self.case.v5_tuple, 2, 'NATIVE_LAPTOP_PROOF_BLOCKED')
        d1 = self.root / 'successor-ledger.json'
        self.pass_attempt(d1, 'diagnostic', 'old-image-d1', self.case.v5_tuple, 0,
                          'DIAGNOSTIC_IMAGE_REMOTE_FAILURE_NOT_REPRODUCED')
        r5_snapshot = self.root / 'r5-reviewed-snapshot.json'
        d1_snapshot = self.root / 'd1-reviewed-snapshot.json'
        r5_snapshot.write_bytes(self.case.repair5.read_bytes())
        d1_snapshot.write_bytes(d1.read_bytes())
        auth = self.root / 'causal-owner.json'
        auth.write_text(json.dumps({'schemaVersion': 1,
                                   'kind': 'DEVFLEET_CAUSAL_SUCCESSOR_AUTHORIZATION',
                                   'policyId': 'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1',
                                   'approved': True,
                                   'limits': {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                                              'desktop-proof': 1, 'fullrelease': 1, 'maintenance': 0, 'build-sign': 0},
                                   'predecessorSha256': {'r5': self.j.digest(r5_snapshot),
                                                         'imageD1': self.j.digest(d1_snapshot)}}), encoding='utf-8')
        self.ledger = self.root / 'causal-ledger.json'
        self.j.initialize(self.ledger, auth, [r5_snapshot, self.case.repair5, d1_snapshot, d1],
                          'DF-FRESH-CERTIFICATION-20260929-CAUSAL-1')
        self.pass_attempt(self.ledger, 'standard-token', 'new-standard-token', self.new_tuple,
                          0, 'PASS_NATIVE_STANDARD_TOKEN')
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        self.approval = {'schemaVersion': 5, 'contract': 'devfleet-baseline-rebind-approval-v5',
                         'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                         'shippingChangeApproved': False, 'previousCandidate': self.case.v5_tuple,
                         'candidate': self.new_tuple, 'replacement': pointer['checkpoint'],
                         'previousReceiptSha256': self.v5['receiptSha256']}
        self.tuple_path = self.write('generation6-tuple.json', self.new_tuple)
        self.approval_path = self.write('generation6-approval.json', self.approval)
        live = json.loads(self.case.live_path.read_text())
        self.live_path = self.write('generation6-live.json', {**live, 'observedUtc': datetime.now(timezone.utc).isoformat()})

    def write(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding='utf-8')
        return path

    def pass_attempt(self, ledger, op, run, tuple_value, code, result):
        owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
        q = {'runId': run, 'operation': op, 'owner': owner, 'tuple': tuple_value,
             'entrypoint': 'synthetic.ps1', 'entrypointSha256': 'a' * 64, 'arguments': [],
             'changedCondition': 'Synthetic lineage fixture only',
             'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat()}
        self.j.reserve(ledger, q)
        evidence = self.write(run + '-fixture.json', {'status': result, 'certificationCredit': False})
        self.j.finish(ledger, run, owner, code, result, [str(evidence)])

    def bind(self):
        return baseline_lineage.rebind_gen6(self.root, self.tuple_path, self.approval_path, self.ledger, self.live_path)

    def test_append_preserves_generation5_and_exact_shipping(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        prior_pointer = pointer.read_bytes()
        prior_receipt = self.root / 'evidence/baselines/receipts' / self.v5['receiptFile']
        prior_bytes = prior_receipt.read_bytes()
        result = self.bind()
        self.assertEqual(result['generation'], 6)
        self.assertEqual(result['id'], self.v5['id'])
        self.assertEqual(prior_receipt.read_bytes(), prior_bytes)
        self.assertEqual((self.root / 'evidence/baselines/history' /
                          (baseline_lineage.hashlib.sha256(prior_pointer).hexdigest() + '.json')).read_bytes(), prior_pointer)
        self.assertEqual(baseline_lineage.accepted_baseline(self.root, self.new_tuple)['receiptSha256'], result['receiptSha256'])
        with self.assertRaises(ValueError):
            self.bind()

    def test_shipping_change_or_missing_owner_approval_cannot_bind(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        before = pointer.read_bytes()
        self.write(self.tuple_path.name, {**self.new_tuple, 'candidateSha256': '7' * 64})
        with self.assertRaises(ValueError):
            self.bind()
        self.write(self.tuple_path.name, self.new_tuple)
        self.write(self.approval_path.name, {**self.approval, 'decision': 'PENDING'})
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), before)

    def test_stale_inventory_and_wrong_qualification_reject(self):
        live = json.loads(self.live_path.read_text())
        self.write(self.live_path.name, {**live, 'observedUtc': (datetime.now(timezone.utc) - timedelta(minutes=3)).isoformat()})
        with self.assertRaises(ValueError):
            self.bind()
        self.write(self.live_path.name, live)
        data = json.loads(self.ledger.read_text())
        data['attempts'][0]['tuple'] = {**self.new_tuple, 'repositoryHead': '8' * 40}
        self.write(self.ledger.name, data)
        with self.assertRaises(ValueError):
            self.bind()

    def test_immutable_source_drift_and_current_tuple_mismatch_reject(self):
        self.bind()
        with self.assertRaises(ValueError):
            baseline_lineage.accepted_baseline(self.root, {**self.new_tuple, 'toolingFingerprintId': '9' * 64})
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        receipt = json.loads((self.root / 'evidence/baselines/receipts' / pointer['receiptFile']).read_text())
        source = self.root / 'evidence/baselines/sources' / (receipt['successorLedgerSha256'] + '.json')
        source.write_bytes(source.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            baseline_lineage.accepted_baseline(self.root, self.new_tuple)

    def test_strict_release_reader_requires_generation6_and_immutable_source(self):
        result = self.bind()
        expected = {**self.new_tuple, 'candidateCommit': self.new_tuple['candidateBuildCommit']}
        self.assertEqual(load_accepted_baseline(self.root, expected, {'exe': self.new_tuple['candidateSha256']})['receiptSha256'], result['receiptSha256'])
        with self.assertRaises(ValueError):
            load_accepted_baseline(self.root, {**expected, 'toolingFingerprintId': '9' * 64}, {'exe': self.new_tuple['candidateSha256']})
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        receipt = json.loads((self.root / 'evidence/baselines/receipts' / pointer['receiptFile']).read_text())
        source = self.root / 'evidence/baselines/sources' / (receipt['successorLedgerSha256'] + '.json')
        source.write_bytes(source.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            load_accepted_baseline(self.root, expected, {'exe': self.new_tuple['candidateSha256']})

    def test_powershell_reader_requires_exact_generation6_tuple(self):
        if not shutil.which('pwsh'):
            self.skipTest('PowerShell 7 is unavailable')
        self.bind()
        tools = self.root / 'tools'
        tools.mkdir(exist_ok=True)
        shutil.copyfile(Path(baseline_lineage.__file__), tools / 'baseline_lineage.py')
        module = Path(__file__).resolve().parents[1] / 'automation/release-e2e/modules/BaselineLineage.psm1'
        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"
        script = self.root / 'probe-v6.ps1'
        script.write_text(
            "$ErrorActionPreference='Stop'\n"
            f"Import-Module {quote(module)} -Force\n"
            f"$f=Get-Content -Raw -LiteralPath {quote(self.tuple_path)}|ConvertFrom-Json\n"
            "$fp=[pscustomobject]@{repositoryHead=$f.repositoryHead;gitCommit=$f.candidateBuildCommit;"
            "shippingInputIdentity=$f.shippingInputIdentity;releaseFingerprintId=$f.releaseFingerprintId;"
            "toolingFingerprintId=$f.toolingFingerprintId;candidate=[pscustomobject]@{sha256=$f.candidateSha256}}\n"
            f"Get-DevFleetAcceptedBaseline -WorkspaceRoot {quote(self.root)} -Fingerprint $fp|ConvertTo-Json -Depth 6\n",
            encoding='utf-8')
        result = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['generation'], 6)
        self.write(self.tuple_path.name, {**self.new_tuple, 'candidateSha256': 'a' * 64})
        rejected = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)], capture_output=True, text=True, timeout=20)
        self.assertNotEqual(rejected.returncode, 0)

    def test_strict_release_reader_rejects_rehashed_wrong_approval_and_charges(self):
        self.bind()
        pointer_path = self.root / 'evidence/baselines/CURRENT.json'
        pointer = json.loads(pointer_path.read_text())
        receipt_path = self.root / 'evidence/baselines/receipts' / pointer['receiptFile']
        receipt = json.loads(receipt_path.read_text())
        expected = {**self.new_tuple, 'candidateCommit': self.new_tuple['candidateBuildCommit']}
        def reject_binding(value):
            receipt_path.write_text(json.dumps(value), encoding='utf-8')
            pointer_path.write_text(json.dumps({**pointer, 'receiptSha256': self.j.digest(receipt_path)}), encoding='utf-8')
            with self.assertRaises(ValueError):
                load_accepted_baseline(self.root, expected, {'exe': self.new_tuple['candidateSha256']})
        for approval_change in ({'schemaVersion': 4}, {'decision': 'PENDING'}, {'shippingChangeApproved': True}):
            with self.subTest(approval=approval_change):
                reject_binding({**receipt, 'approval': {**receipt['approval'], **approval_change}})
        reject_binding({**receipt, 'successorPolicyId': 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-5'})
        ledger_path = self.root / 'evidence/baselines/sources' / (receipt['successorLedgerSha256'] + '.json')
        ledger = json.loads(ledger_path.read_text())
        mutations = [
            {**ledger, 'attempts': ledger['attempts'] * 2},
            {**ledger, 'attempts': [{**ledger['attempts'][0], 'exitCode': 2}]},
            {**ledger, 'attempts': [{**ledger['attempts'][0], 'tuple': self.case.v5_tuple}]},
            {**ledger, 'limits': {**ledger['limits'], 'build-sign': 1}},
        ]
        for altered in mutations:
            with self.subTest(ledger=altered):
                source = self.write('altered-ledger.json', altered)
                source_hash = self.j.digest(source)
                shutil.copyfile(source, self.root / 'evidence/baselines/sources' / (source_hash + '.json'))
                reject_binding({**receipt, 'successorLedgerSha256': source_hash})


if __name__ == '__main__':
    unittest.main()
