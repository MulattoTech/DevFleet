"""Independent workspace/archive reader checks for synthetic Generation-8 lineage."""
import json
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from unittest.mock import patch

import baseline_lineage
import validate_release_bundle as bundle


class Generation8ReleaseReaderTests(unittest.TestCase):
    def setUp(self):
        fixture_path = Path(__file__).resolve().parent / 'test_baseline_generation8.py'
        spec = importlib.util.spec_from_file_location(
            'generation8_fixture_for_release_reader', fixture_path)
        fixture_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixture_module)
        self.fixture = fixture_module.Generation8AppendTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.gen7.root
        self.bound = self.fixture.bind()
        self.pointer_path = self.root / 'evidence/baselines/CURRENT.json'
        self.pointer = json.loads(self.pointer_path.read_text(encoding='utf-8'))
        self.receipt_path = self.root / 'evidence/baselines/receipts' / self.pointer['receiptFile']
        self.receipt = json.loads(self.receipt_path.read_text(encoding='utf-8'))
        self.expected = {**self.fixture.new,
                         'candidateCommit': self.fixture.new['candidateBuildCommit']}
        self.patches = [
            patch.object(bundle, 'COLLISION_PREDECESSOR_SHA256',
                         baseline_lineage.digest(self.fixture.gen7.predecessor)),
            patch.object(bundle, 'COLLISION_OWNER_AUTH_SHA256',
                         self.fixture.gen7.owner_hash),
            patch.object(bundle, 'COLLISION_LEDGER_PATH',
                         str(self.fixture.gen7.ledger)),
            patch.object(bundle, 'HTTP_CLEANUP_POLICY',
                         baseline_lineage.HTTP_CLEANUP_POLICY, create=True),
            patch.object(bundle, 'HTTP_CLEANUP_PREDECESSOR_SHA256',
                         self.fixture.http.predecessor_sha256, create=True),
            patch.object(bundle, 'HTTP_CLEANUP_LEDGER_PATH',
                         str(self.fixture.ledger_path), create=True),
            patch.object(bundle, 'HTTP_CLEANUP_LIMITS',
                         baseline_lineage.HTTP_CLEANUP_LIMITS, create=True),
        ]
        for context in self.patches:
            context.start()
            self.addCleanup(context.stop)

    def read(self, root=None):
        return bundle.load_accepted_baseline(
            root or self.root, self.expected,
            {'exe': self.fixture.new['candidateSha256']})

    def test_accepts_complete_generation_eight_workspace_chain(self):
        self.assertEqual(self.read()['receiptSha256'], self.bound['receiptSha256'])

    def test_accepts_clean_extracted_generation_eight_chain(self):
        with tempfile.TemporaryDirectory(prefix='devfleet-gen8-archive-') as scratch:
            archive_path = Path(scratch) / 'synthetic-gen8.zip'
            extracted = Path(scratch) / 'extracted'
            extracted.mkdir()
            with zipfile.ZipFile(archive_path, 'w') as archive:
                for path in self.root.rglob('*'):
                    if path.is_file():
                        archive.write(path, path.relative_to(self.root).as_posix())
            with zipfile.ZipFile(archive_path) as archive:
                bundle._safe_extract(archive, extracted)
            self.assertEqual(self.read(extracted)['receiptSha256'],
                             self.bound['receiptSha256'])

    def test_rejects_tampered_generation_eight_frozen_source(self):
        row = next(row for row in self.receipt['sourceClosure']
                   if row['sha256'] == self.receipt['approvalSha256'])
        source = self.root / 'evidence/baselines/sources' / (
            row['sha256'] + row['extension'])
        source.write_bytes(source.read_bytes() + b'tamper')
        with self.assertRaisesRegex(ValueError, 'generation-8'):
            self.read()

    def test_canonical_archive_closure_stages_every_generation_eight_source(self):
        if not shutil.which('pwsh'):
            self.skipTest('canonical PowerShell staging requires PowerShell 7')
        with tempfile.TemporaryDirectory(prefix='devfleet-gen8-stage-') as scratch:
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
            for row in self.receipt['sourceClosure']:
                staged = evidence / 'baselines/sources' / (row['sha256'] + row['extension'])
                self.assertTrue(staged.is_file(), str(staged))
            runner = Path('automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1')
            (stage / runner).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.root / runner, stage / runner)
            self.assertEqual(self.read(stage)['receiptSha256'],
                             self.bound['receiptSha256'])

    def test_canonical_archive_closure_rejects_source_over_4mb(self):
        if not shutil.which('pwsh'):
            self.skipTest('canonical PowerShell staging requires PowerShell 7')
        state = self.root / 'evidence/baselines'
        source = state / 'sources' / ('d' * 64 + '.bin')
        source.write_bytes(b'x' * 4_000_001)
        self.receipt['sourceClosure'].append({'sha256': 'd' * 64, 'extension': '.bin'})
        self.receipt_path.write_text(json.dumps(self.receipt), encoding='utf-8')
        self.pointer['receiptSha256'] = baseline_lineage.digest(self.receipt_path)
        self.pointer_path.write_text(json.dumps(self.pointer), encoding='utf-8')
        with tempfile.TemporaryDirectory(prefix='devfleet-gen8-large-source-') as scratch:
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
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('exceeds 4 MB', result.stderr)


if __name__ == '__main__':
    unittest.main()
