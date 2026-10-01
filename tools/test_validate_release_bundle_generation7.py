"""Independent archive-reader checks for synthetic Generation-7 lineage."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import baseline_lineage
from test_baseline_generation7 import Generation7Tests as _Generation7Fixture
import validate_release_bundle as bundle


class Generation7ReleaseReaderTests(unittest.TestCase):
    def setUp(self):
        self.fixture = _Generation7Fixture(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.bound = self.fixture.bind()
        self.pointer_path = self.root / 'evidence/baselines/CURRENT.json'
        self.pointer = json.loads(self.pointer_path.read_text(encoding='utf-8'))
        self.receipt_path = self.root / 'evidence/baselines/receipts' / self.pointer['receiptFile']
        self.receipt = json.loads(self.receipt_path.read_text(encoding='utf-8'))
        self.expected = {**self.fixture.new,
                         'candidateCommit': self.fixture.new['candidateBuildCommit']}

    def read(self):
        with (patch.object(bundle, 'COLLISION_PREDECESSOR_SHA256',
                           self.receipt['predecessorLedgerSha256']),
              patch.object(bundle, 'COLLISION_OWNER_AUTH_SHA256',
                           self.receipt['ownerAuthorizationSha256']),
              patch.object(bundle, 'COLLISION_LEDGER_PATH',
                           str(self.fixture.ledger))):
            return bundle.load_accepted_baseline(self.root, self.expected,
                                                 {'exe': self.fixture.new['candidateSha256']})

    def replace_receipt(self, receipt):
        self.receipt_path.write_text(json.dumps(receipt), encoding='utf-8')
        self.pointer_path.write_text(json.dumps({**self.pointer,
            'receiptSha256': baseline_lineage.digest(self.receipt_path)}), encoding='utf-8')

    def test_accepts_complete_generation_seven_chain(self):
        self.assertEqual(self.read()['receiptSha256'], self.bound['receiptSha256'])

    def test_accepts_equivalent_canonical_path_separator_spelling(self):
        with (patch.object(bundle, 'COLLISION_PREDECESSOR_SHA256',
                           self.receipt['predecessorLedgerSha256']),
              patch.object(bundle, 'COLLISION_OWNER_AUTH_SHA256',
                           self.receipt['ownerAuthorizationSha256']),
              patch.object(bundle, 'COLLISION_LEDGER_PATH',
                           self.fixture.ledger.as_posix())):
            result = bundle.load_accepted_baseline(
                self.root, self.expected,
                {'exe': self.fixture.new['candidateSha256']})
        self.assertEqual(result['receiptSha256'], self.bound['receiptSha256'])

    def test_clean_extracted_chain_accepts(self):
        with tempfile.TemporaryDirectory(prefix='devfleet-gen7-archive-') as scratch:
            zip_path = Path(scratch) / 'synthetic-gen7.zip'
            extracted = Path(scratch) / 'extracted'
            extracted.mkdir()
            with zipfile.ZipFile(zip_path, 'w') as archive:
                for path in self.root.rglob('*'):
                    if path.is_file():
                        archive.write(path, path.relative_to(self.root).as_posix())
            with zipfile.ZipFile(zip_path) as archive:
                bundle._safe_extract(archive, extracted)
            with (patch.object(bundle, 'COLLISION_PREDECESSOR_SHA256',
                               self.receipt['predecessorLedgerSha256']),
                  patch.object(bundle, 'COLLISION_OWNER_AUTH_SHA256',
                               self.receipt['ownerAuthorizationSha256']),
                  patch.object(bundle, 'COLLISION_LEDGER_PATH',
                               str(self.fixture.ledger))):
                result = bundle.load_accepted_baseline(
                    extracted, self.expected,
                    {'exe': self.fixture.new['candidateSha256']})
            self.assertEqual(result['receiptSha256'], self.bound['receiptSha256'])

    def test_canonical_staging_clean_extraction_accepts(self):
        if not shutil.which('pwsh'):
            self.skipTest('canonical PowerShell staging needs PowerShell 7')
        with tempfile.TemporaryDirectory(prefix='devfleet-gen7-canonical-') as scratch:
            stage = Path(scratch) / 'stage'
            evidence = stage / 'evidence'
            evidence.mkdir(parents=True)
            module = Path(__file__).resolve().parent / 'BaselineArchiveClosure.psm1'
            script = Path(scratch) / 'stage.ps1'
            quoted = str(module).replace("'", "''")
            script.write_text(
                'param([string]$WorkspaceRoot,[string]$EvidenceStage)\n'
                "$ErrorActionPreference='Stop'\n"
                f"Import-Module '{quoted}' -Force\n"
                'Copy-DevFleetBaselineArchiveClosure -WorkspaceRoot $WorkspaceRoot '
                '-EvidenceStage $EvidenceStage\n', encoding='utf-8')
            result = subprocess.run(['pwsh', '-NoProfile', '-File', str(script),
                                     str(self.root), str(evidence)],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            shutil.copy2(self.fixture.token_pointer, evidence / 'CURRENT-STANDARD-TOKEN.json')
            shutil.copytree(self.fixture.token_dir,
                            evidence / 'standard-token' / self.fixture.run_id)
            runner = Path('automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1')
            (stage / runner).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.root / runner, stage / runner)
            archive_path = Path(scratch) / 'canonical-staged.zip'
            extracted = Path(scratch) / 'extracted'
            extracted.mkdir()
            with zipfile.ZipFile(archive_path, 'w') as archive:
                for path in stage.rglob('*'):
                    if path.is_file():
                        archive.write(path, path.relative_to(stage).as_posix())
            with zipfile.ZipFile(archive_path) as archive:
                bundle._safe_extract(archive, extracted)
            with (patch.object(bundle, 'COLLISION_PREDECESSOR_SHA256',
                               self.receipt['predecessorLedgerSha256']),
                  patch.object(bundle, 'COLLISION_OWNER_AUTH_SHA256',
                               self.receipt['ownerAuthorizationSha256']),
                  patch.object(bundle, 'COLLISION_LEDGER_PATH',
                               str(self.fixture.ledger))):
                result = bundle.load_accepted_baseline(
                    extracted, self.expected,
                    {'exe': self.fixture.new['candidateSha256']})
            self.assertEqual(result['receiptSha256'], self.bound['receiptSha256'])

    def test_rejects_missing_predecessor_pointer(self):
        old = self.root / 'evidence/baselines/history' / (self.pointer['previousPointerSha256'] + '.json')
        old.unlink()
        with self.assertRaises(ValueError):
            self.read()

    def test_rejects_missing_predecessor_receipt_and_generation_four_artifact(self):
        pointer = self.pointer
        history = self.root / 'evidence/baselines/history'
        receipts = self.root / 'evidence/baselines/receipts'
        while pointer['generation'] > 4:
            pointer = json.loads((history / (pointer['previousPointerSha256'] + '.json')).read_text())
            if pointer['generation'] == 6:
                gen6_receipt = receipts / pointer['receiptFile']
        original = gen6_receipt.read_bytes()
        gen6_receipt.unlink()
        with self.assertRaises(ValueError): self.read()
        gen6_receipt.write_bytes(original)
        gen4_receipt = json.loads((receipts / pointer['receiptFile']).read_text())
        artifact = self.root / 'evidence/baselines/sources' / (
            gen4_receipt['artifactReceiptSha256'] + '.json')
        artifact.unlink()
        with self.assertRaises(ValueError): self.read()

    def test_rejects_missing_frozen_owner_approval(self):
        source = self.root / 'evidence/baselines/sources' / (
            self.receipt['approvalSha256'] + '.json')
        source.unlink()
        with self.assertRaises(ValueError):
            self.read()

    def test_rejects_rehashed_wrong_predecessor_generation(self):
        old = self.root / 'evidence/baselines/history' / (self.pointer['previousPointerSha256'] + '.json')
        altered = json.loads(old.read_text(encoding='utf-8'))
        altered['generation'] = 5
        new = self.root / 'evidence/baselines/history' / ('f' * 64 + '.json')
        new.write_text(json.dumps(altered), encoding='utf-8')
        new_hash = baseline_lineage.digest(new)
        new.rename(new.with_name(new_hash + '.json'))
        self.pointer_path.write_text(json.dumps({**self.pointer,
            'previousPointerSha256': new_hash}), encoding='utf-8')
        with self.assertRaises(ValueError):
            self.read()

    def test_rejects_rehashed_widened_limit(self):
        receipt = dict(self.receipt)
        source = self.root / 'evidence/baselines/sources' / (receipt['successorLedgerSha256'] + '.json')
        ledger = json.loads(source.read_text(encoding='utf-8'))
        ledger['limits']['laptop-proof'] = 2
        altered = self.root / 'altered-ledger.json'
        altered.write_text(json.dumps(ledger), encoding='utf-8')
        new_hash = baseline_lineage.digest(altered)
        (self.root / 'evidence/baselines/sources' / (new_hash + '.json')).write_bytes(altered.read_bytes())
        receipt['successorLedgerSha256'] = new_hash
        self.replace_receipt(receipt)
        with self.assertRaises(ValueError):
            self.read()

    def test_rejects_rehashed_non_developer_token(self):
        receipt = dict(self.receipt)
        token = dict(receipt['standardTokenEvidence'])
        source = self.root / 'evidence/baselines/sources' / (token['canonicalSha256'] + '.json')
        canonical = json.loads(source.read_text(encoding='utf-8'))
        canonical['token']['isElevated'] = True
        altered = self.root / 'altered-token.json'
        altered.write_text(json.dumps(canonical), encoding='utf-8')
        new_hash = baseline_lineage.digest(altered)
        (self.root / 'evidence/baselines/sources' / (new_hash + '.json')).write_bytes(altered.read_bytes())
        token['canonicalSha256'] = new_hash
        receipt['standardTokenEvidence'] = token
        self.replace_receipt(receipt)
        with self.assertRaises(ValueError):
            self.read()

    def test_rejects_current_token_pointer_drift(self):
        pointer = self.root / 'evidence/CURRENT-STANDARD-TOKEN.json'
        pointer.write_bytes(pointer.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.read()

    def test_native_and_archive_readers_reject_reused_inner_run_id(self):
        reference = self.receipt['standardTokenEvidence']
        attempt = json.loads(self.fixture.ledger.read_text())['attempts'][0]
        attempt['runId'] = reference['runId']
        with self.assertRaises(ValueError):
            baseline_lineage._gen7_outer_inner(attempt, self.root, reference)
        with self.assertRaises(ValueError):
            bundle._validate_generation7_token(
                self.root, self.fixture.new, reference, attempt,
                lambda path: json.loads(path.read_text(encoding='utf-8-sig')))

    def test_native_and_archive_readers_reject_noncanonical_campaign_location(self):
        wrong = self.root / 'another-collision-ledger.json'
        with patch.object(baseline_lineage, 'COLLISION_LEDGER_PATH', wrong):
            with self.assertRaises(ValueError):
                baseline_lineage.accepted_baseline(self.root, self.fixture.new)
        with (patch.object(bundle, 'COLLISION_PREDECESSOR_SHA256',
                           self.receipt['predecessorLedgerSha256']),
              patch.object(bundle, 'COLLISION_OWNER_AUTH_SHA256',
                           self.receipt['ownerAuthorizationSha256']),
              patch.object(bundle, 'COLLISION_LEDGER_PATH', str(wrong))):
            with self.assertRaises(ValueError):
                bundle.load_accepted_baseline(
                    self.root, self.expected,
                    {'exe': self.fixture.new['candidateSha256']})


if __name__ == '__main__':
    unittest.main()
