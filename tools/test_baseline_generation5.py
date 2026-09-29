"""VM-free generation-5 baseline binding after unchanged-shipping tooling repair."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import subprocess
import unittest

import baseline_lineage
import test_baseline_generation4 as generation4


class Generation5Tests(unittest.TestCase):
    def setUp(self):
        self.case = generation4.Generation4Tests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        self.v4 = self.case.bind()
        self.journal = self.case.journal
        self.v4_tuple = self.case.v4_tuple
        self.v5_tuple = {**self.v4_tuple,
                         'repositoryHead': '9' * 40,
                         'toolingFingerprintId': '8' * 64}
        self._finish_repair3()
        repair3_snapshot = self.root / 'repair3-terminal-snapshot.json'
        repair3_snapshot.write_bytes(self.case.repair2.read_bytes())
        auth4 = self.root / 'repair4-authorization.md'
        auth4.write_text('distinct owner approval for fourth repair', encoding='utf-8')
        repair4 = self.root / 'repair4-ledger.json'
        self.journal.initialize(repair4, auth4,
                                [repair3_snapshot, self.case.repair2], self.journal.REPAIR4_ID)
        self._pass(repair4, 'standard-token', self.v4_tuple, 'repair4-standard-token')
        repair4_snapshot = self.root / 'repair4-terminal-snapshot.json'
        repair4_snapshot.write_bytes(repair4.read_bytes())
        # The production journal pins the exact native predecessor bytes.
        # This isolated fixture substitutes its own deterministic terminal hash.
        self.journal.REPAIR5_PREDECESSOR_SHA256 = self.journal.digest(repair4)
        native_journal = self.root / '.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py'
        native_text = native_journal.read_text(encoding='utf-8')
        native_text = native_text.replace(
            "REPAIR5_PREDECESSOR_SHA256 = 'bc9401e921754628b95f1f5ceff6308bc3607ae790690cfca786222eadf71ee4'",
            f"REPAIR5_PREDECESSOR_SHA256 = '{self.journal.REPAIR5_PREDECESSOR_SHA256}'")
        native_journal.write_text(native_text, encoding='utf-8')
        auth5 = self.root / 'repair5-authorization.md'
        auth5.write_text('separate owner approval for fifth repair', encoding='utf-8')
        self.repair5 = self.root / 'repair5-ledger.json'
        self.journal.initialize(self.repair5, auth5,
                                [repair4_snapshot, repair4], self.journal.REPAIR5_ID)
        self._pass(self.repair5, 'standard-token', self.v5_tuple, 'repair5-standard-token')
        self.approval = {'schemaVersion': 4, 'contract': 'devfleet-baseline-rebind-approval-v4',
                         'decision': 'APPROVE', 'approvedBy': 'ACCOUNT_OWNER',
                         'shippingChangeApproved': False,
                         'previousCandidate': self.v4_tuple, 'candidate': self.v5_tuple,
                         'replacement': self.case.case.case.proposal['replacement'],
                         'previousReceiptSha256': self.v4['receiptSha256']}
        self.tuple_path = self.root / 'generation5-tuple.json'
        self.tuple_path.write_text(json.dumps(self.v5_tuple), encoding='utf-8')
        self.approval_path = self.root / 'generation5-approval.json'
        self.approval_path.write_text(json.dumps(self.approval), encoding='utf-8')
        self.live_path = self.root / 'generation5-native-inventory.json'
        self.live_path.write_text(json.dumps({**self.case.case.case.live,
                                              'observedUtc': datetime.now(timezone.utc).isoformat()}),
                                  encoding='utf-8')

    def _pass(self, ledger, operation, tuple_value, run_id, blocked=False):
        owner = {'pid': 123, 'startUtc': datetime.now(timezone.utc).isoformat()}
        request = {'runId': run_id, 'operation': operation, 'owner': owner,
                   'tuple': tuple_value, 'entrypoint': 'fixture.ps1',
                   'entrypointSha256': 'c' * 64, 'arguments': [],
                   'changedCondition': 'VM-free lineage fixture',
                   'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
        self.journal.reserve(ledger, request)
        evidence = [str(self.root / (run_id + '-evidence.json'))]
        Path(evidence[0]).write_text('{"status":"PASS"}', encoding='utf-8')
        self.journal.finish(ledger, run_id, owner, 2 if blocked else 0,
                            'NATIVE_FULLRELEASE_BLOCKED' if blocked else
                            dict(self.journal.REPAIR3_SEQUENCE)[operation], evidence)

    def _finish_repair3(self):
        for index, (operation, _) in enumerate(self.journal.REPAIR3_SEQUENCE[1:], 1):
            self._pass(self.case.repair2, operation, self.v4_tuple,
                       f'repair3-{index}', blocked=(operation == 'fullrelease'))

    def bind(self):
        return baseline_lineage.rebind_gen5(self.root, self.tuple_path,
                                            self.approval_path, self.repair5, self.live_path)

    def test_exact_unchanged_shipping_binding_and_hash_chain(self):
        result = self.bind()
        self.assertEqual(result['generation'], 5)
        self.assertEqual(result['id'], self.case.case.case.proposal['replacement']['id'])
        self.assertEqual(baseline_lineage.accepted_baseline(self.root, self.v5_tuple)['receiptSha256'],
                         result['receiptSha256'])
        with self.assertRaises(ValueError):
            self.bind()

    def test_shipping_change_and_missing_approval_fail_closed(self):
        pointer = self.root / 'evidence/baselines/CURRENT.json'
        prior = pointer.read_bytes()
        self.tuple_path.write_text(json.dumps({**self.v5_tuple,
                                               'shippingInputIdentity': '7' * 64}), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.bind()
        self.tuple_path.write_text(json.dumps(self.v5_tuple), encoding='utf-8')
        self.approval_path.write_text(json.dumps({**self.approval, 'decision': 'PENDING'}),
                                      encoding='utf-8')
        with self.assertRaises(ValueError):
            self.bind()
        self.assertEqual(pointer.read_bytes(), prior)

    def test_immutable_qualification_and_inventory_sources(self):
        self.bind()
        pointer = json.loads((self.root / 'evidence/baselines/CURRENT.json').read_text())
        receipt = json.loads((self.root / 'evidence/baselines/receipts' / pointer['receiptFile']).read_text())
        source = self.root / 'evidence/baselines/sources' / (receipt['successorLedgerSha256'] + '.json')
        source.write_bytes(source.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            baseline_lineage.accepted_baseline(self.root, self.v5_tuple)

    def test_powershell_reader_requires_exact_generation5_tuple(self):
        if not shutil.which('pwsh'):
            self.skipTest('PowerShell 7 is unavailable')
        self.bind()
        tools = self.root / 'tools'
        tools.mkdir(exist_ok=True)
        shutil.copyfile(Path(baseline_lineage.__file__), tools / 'baseline_lineage.py')
        module = Path(__file__).resolve().parents[1] / 'automation/release-e2e/modules/BaselineLineage.psm1'
        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"
        script = self.root / 'probe-v5.ps1'
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
        self.assertEqual(json.loads(result.stdout)['generation'], 5)
        self.tuple_path.write_text(json.dumps({**self.v5_tuple,
                                               'candidateSha256': 'a' * 64}), encoding='utf-8')
        rejected = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)],
                                  capture_output=True, text=True, timeout=20)
        self.assertNotEqual(rejected.returncode, 0)


if __name__ == '__main__':
    unittest.main()
