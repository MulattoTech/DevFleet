"""VM-free generation-4 binding for a distinct signed shipping candidate."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import subprocess
import unittest

from baseline_lineage import accepted_baseline, rebind_gen4
import test_baseline_generation3 as generation3
from validate_release_bundle import load_accepted_baseline


class Generation4Tests(unittest.TestCase):
    def setUp(self):
        self.case = generation3.Generation3Tests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        self.v3 = self.case.bind()
        journal = self.case.journal
        self.journal = journal
        repair1 = self.case.repair
        for index, (operation, classification) in enumerate(journal.REPAIR_SEQUENCE[1:], 1):
            owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
            request = {'runId': f'repair1-{index}', 'operation': operation,
                       'owner': owner, 'tuple': self.case.v3_tuple,
                       'entrypoint': 'fixture.ps1', 'entrypointSha256': 'c' * 64,
                       'arguments': [], 'changedCondition': 'fixture terminal first repair',
                       'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
            journal.reserve(repair1, request)
            blocked = operation == 'fullrelease'
            journal.finish(repair1, request['runId'], owner, 2 if blocked else 0,
                           'NATIVE_FULLRELEASE_BLOCKED' if blocked else classification, [])
        snapshot = self.root / 'repair1-terminal-snapshot.json'
        snapshot.write_bytes(repair1.read_bytes())
        auth = self.root / 'repair2-authorization.md'
        auth.write_text('owner-approved failed build-sign successor', encoding='utf-8')
        repair2 = self.root / 'repair2-ledger.json'
        journal.initialize(repair2, auth, [snapshot, repair1], journal.REPAIR2_ID)
        owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
        request = {'runId': 'repair2-build-sign', 'operation': 'build-sign',
                   'owner': owner, 'tuple': self.case.v3_tuple,
                   'entrypoint': 'fixture.ps1', 'entrypointSha256': 'c' * 64,
                   'arguments': [], 'changedCondition': 'fixture blocked build-sign',
                   'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
        journal.reserve(repair2, request)
        journal.finish(repair2, request['runId'], owner, 2, 'BUILD_SIGN_BLOCKED', [])
        repair2_snapshot = self.root / 'repair2-terminal-snapshot.json'
        repair2_snapshot.write_bytes(repair2.read_bytes())
        self.repair2 = self.root / 'repair3-ledger.json'
        auth3 = self.root / 'repair3-authorization.md'
        auth3.write_text('owner-approved prospective repair3 successor', encoding='utf-8')
        self.v4_tuple = {**self.case.v3_tuple,
                         'repositoryHead': 'b' * 40,
                         'candidateBuildCommit': journal.REPAIR3_CANDIDATE_COMMIT,
                         'shippingInputIdentity': journal.REPAIR3_SHIPPING_SHA256,
                         'releaseFingerprintId': 'd' * 64,
                         'toolingFingerprintId': 'f' * 64,
                         'candidateSha256': journal.REPAIR3_SIGNED_EXE_SHA256}
        self.artifact_receipt = self.root / 'signed-output-inspection.json'
        self.artifact_receipt.write_text(json.dumps({
            'schemaVersion': 1, 'contract': 'devfleet-signed-build-output-inspection-v1',
            'status': 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION',
            'certificationCredit': False, 'repositoryHead': self.v4_tuple['candidateBuildCommit'],
            'failedAttemptLedgerSha256': journal.digest(repair2),
            'shippingInputIdentity': self.v4_tuple['shippingInputIdentity'],
            'artifacts': [
                {'name': 'exe', 'path': 'candidate.exe', 'sha256': self.v4_tuple['candidateSha256']},
                {'name': 'tar', 'path': 'candidate.tar.gz', 'sha256': '2' * 64},
                {'name': 'portable', 'path': 'candidate.zip', 'sha256': '3' * 64},
                {'name': 'installerSource', 'path': 'installer.zip', 'sha256': '4' * 64}],
            'signatureStatus': 'Valid', 'publicPromotionAllowed': False,
            'publicPublisherTrust': False}), encoding='utf-8')
        # The native journal pins the production receipt bytes. This isolated
        # fixture substitutes its own deterministic receipt hash.
        journal.REPAIR3_FAILED_LEDGER_SHA256 = journal.digest(repair2)
        journal.REPAIR3_RECEIPT_SHA256 = journal.digest(self.artifact_receipt)
        native_journal = self.root / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        native_journal.parent.mkdir(parents=True, exist_ok=True)
        source = Path(__file__).resolve().parents[1] / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        native_text = source.read_text(encoding='utf-8')
        native_text = native_text.replace(
            "REPAIR3_FAILED_LEDGER_SHA256 = 'dffe7810cc2f1833ed73a9514a8a49e4d65eed67eac0bf936bf81a1c8d6521ff'",
            f"REPAIR3_FAILED_LEDGER_SHA256 = '{journal.REPAIR3_FAILED_LEDGER_SHA256}'")
        native_text = native_text.replace(
            "REPAIR3_RECEIPT_SHA256 = 'b071752cc2042b3405c05856780f74bbecdc11d0c647c8b602404c73829034b6'",
            f"REPAIR3_RECEIPT_SHA256 = '{journal.REPAIR3_RECEIPT_SHA256}'")
        native_journal.write_text(native_text, encoding='utf-8')
        journal.initialize(self.repair2, auth3, [repair2_snapshot, repair2], journal.REPAIR3_ID,
                           self.artifact_receipt)
        for index, (operation, classification) in enumerate(journal.REPAIR3_SEQUENCE[:1]):
            owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
            request = {'runId': f'repair2-{index}', 'operation': operation,
                       'owner': owner, 'tuple': self.v4_tuple,
                       'entrypoint': 'fixture.ps1', 'entrypointSha256': 'c' * 64,
                       'arguments': [], 'changedCondition': 'fixture new signed candidate',
                       'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
            journal.reserve(self.repair2, request)
            journal.finish(self.repair2, request['runId'], owner, 0, classification,
                           [str(self.case.case.write(f'repair3-{index}-result.json', {'status': 'PASS'}))])
        self.approval = {'schemaVersion': 3, 'contract': 'devfleet-baseline-rebind-approval-v3',
                         'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                         'previousCandidate': self.case.v3_tuple, 'candidate': self.v4_tuple,
                         'shippingChangeApproved': True,
                         'replacement': self.case.case.proposal['replacement'],
                         'previousReceiptSha256': self.v3['receiptSha256']}
        self.tuple_path = self.case.case.write('v4-tuple.json', self.v4_tuple)
        self.approval_path = self.case.case.write('v4-approval.json', self.approval)
        self.live_path = self.case.case.write(
            'v4-live.json', {**self.case.case.live,
                             'observedUtc': datetime.now(timezone.utc).isoformat()})

    def bind(self):
        return rebind_gen4(self.root, self.tuple_path, self.approval_path,
                           self.repair2, self.live_path)

    def validator(self):
        expected = {'repositoryHead': self.v4_tuple['repositoryHead'],
                    'candidateCommit': self.v4_tuple['candidateBuildCommit'],
                    'shippingInputIdentity': self.v4_tuple['shippingInputIdentity'],
                    'releaseFingerprintId': self.v4_tuple['releaseFingerprintId'],
                    'toolingFingerprintId': self.v4_tuple['toolingFingerprintId']}
        return load_accepted_baseline(self.root, expected,
                                      {'exe': self.v4_tuple['candidateSha256']})

    def test_exact_approved_shipping_transition_is_accepted(self):
        result = self.bind()
        self.assertEqual(result['generation'], 4)
        self.assertEqual(result['id'], self.case.case.proposal['replacement']['id'])
        self.assertEqual(accepted_baseline(self.root, self.v4_tuple)['receiptSha256'],
                         result['receiptSha256'])
        self.assertEqual(self.validator()['receiptSha256'], result['receiptSha256'])
        with self.assertRaises(ValueError):
            self.bind()

    def test_missing_approval_and_unchanged_shipping_fail_closed(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        original = pointer.read_bytes()
        self.approval_path.write_text(json.dumps({**self.approval, 'shippingChangeApproved': False}))
        with self.assertRaises(ValueError):
            self.bind()
        self.approval_path.write_text(json.dumps(self.approval))
        self.tuple_path.write_text(json.dumps({**self.v4_tuple,
                                               'shippingInputIdentity': self.case.v3_tuple['shippingInputIdentity']}))
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), original)

    def test_immutable_source_and_predecessor_tamper_rejected(self):
        self.bind()
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        receipt = json.loads((self.root / 'evidence/baselines/receipts' / pointer['receiptFile']).read_text())
        source = self.root / 'evidence/baselines/sources' / (receipt['successorLedgerSha256'] + '.json')
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
