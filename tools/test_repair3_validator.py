import unittest
from pathlib import Path
import sys
import hashlib
import json
import tempfile

sys.path.insert(0, str(Path(__file__).parent))
from validate_release_bundle import (_load_packaged_repair3_receipt,
                                     _validate_repair3_attempts,
                                     _validate_repair3_receipt_hash_binding,
                                     _validate_repair3_signed_output_receipt)


class Repair3ReceiptValidatorTests(unittest.TestCase):
    def setUp(self):
        self.candidate = {
            'repositoryHead': 'a' * 40,
            'candidateBuildCommit': 'b' * 40,
            'shippingInputIdentity': 'c' * 64,
            'candidateSha256': 'd' * 64,
        }
        self.receipt = {
            'schemaVersion': 1,
            'contract': 'devfleet-signed-build-output-inspection-v1',
            'status': 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION',
            'certificationCredit': False,
            # The signed output is built at the frozen candidate commit;
            # repository HEAD may advance for tooling integration.
            'repositoryHead': self.candidate['candidateBuildCommit'],
            'shippingInputIdentity': self.candidate['shippingInputIdentity'],
            'signatureStatus': 'Valid',
            'publicPromotionAllowed': False,
            'publicPublisherTrust': False,
            'artifacts': [
                {'name': 'exe', 'path': 'candidate.exe', 'sha256': self.candidate['candidateSha256']},
                {'name': 'tar', 'path': 'candidate.tar.gz', 'sha256': '1' * 64},
                {'name': 'portable', 'path': 'candidate.zip', 'sha256': '2' * 64},
                {'name': 'installerSource', 'path': 'installer.zip', 'sha256': '3' * 64},
            ],
        }

    def test_changed_repository_head_same_candidate_build_is_accepted(self):
        _validate_repair3_signed_output_receipt(self.receipt, self.candidate)

    def test_missing_or_duplicate_artifact_is_rejected(self):
        self.receipt['artifacts'][-1] = dict(self.receipt['artifacts'][0])
        with self.assertRaisesRegex(ValueError, 'receipt contents'):
            _validate_repair3_signed_output_receipt(self.receipt, self.candidate)

    def test_packaged_receipt_required_even_when_absolute_path_is_available(self):
        with tempfile.TemporaryDirectory() as temp:
            sources = Path(temp) / 'sources'
            sources.mkdir()
            receipt_path = Path(temp) / 'host-receipt.json'
            receipt_path.write_text(json.dumps(self.receipt), encoding='utf-8')
            digest = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError, 'absent'):
                _load_packaged_repair3_receipt(sources, digest)
            (sources / f'{digest}.json').write_bytes(receipt_path.read_bytes())
            self.assertEqual(_load_packaged_repair3_receipt(sources, digest), self.receipt)

    def test_repair3_snapshot_has_exactly_one_terminal_standard_token(self):
        attempt = {'operation': 'standard-token', 'state': 'TERMINAL', 'exitCode': 0,
                   'classification': 'PASS_NATIVE_STANDARD_TOKEN', 'tuple': self.candidate,
                   'certificationCredit': False, 'evidence': ['standard-token.json']}
        _validate_repair3_attempts([attempt], self.candidate)
        with self.assertRaisesRegex(ValueError, 'standard token'):
            _validate_repair3_attempts([attempt, dict(attempt)], self.candidate)

    def test_baseline_receipt_hash_must_match_ledger_receipt_hash(self):
        digest = 'e' * 64
        _validate_repair3_receipt_hash_binding({'artifactReceiptSha256': digest}, digest)
        with self.assertRaisesRegex(ValueError, 'hashes differ'):
            _validate_repair3_receipt_hash_binding({'artifactReceiptSha256': 'f' * 64}, digest)


if __name__ == '__main__':
    unittest.main()
