"""VM-free generation-5 input races; never reads or mutates native lab state."""
import json
import unittest
from unittest import mock

import baseline_lineage
import test_baseline_generation5 as generation5
from validate_release_bundle import load_accepted_baseline


class Generation5InputIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.case = generation5.Generation5Tests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)

    def assert_input_race_rejected(self, name):
        path = getattr(self.case, name)
        pointer = self.case.root / 'evidence/baselines/CURRENT.json'
        before = pointer.read_bytes()
        real_run = baseline_lineage.subprocess.run

        def race(*args, **kwargs):
            result = real_run(*args, **kwargs)
            if name == 'approval_path':
                data = json.loads(path.read_text(encoding='utf-8'))
                data['decision'] = 'PENDING'
                path.write_text(json.dumps(data), encoding='utf-8')
            else:
                path.write_bytes(path.read_bytes() + b' ')
            return result

        with mock.patch.object(baseline_lineage.subprocess, 'run', side_effect=race):
            with self.assertRaisesRegex(ValueError, 'changed during generation-5 binding'):
                self.case.bind()
        self.assertEqual(pointer.read_bytes(), before)

    def test_approval_change_after_validation_is_rejected_before_promotion(self):
        self.assert_input_race_rejected('approval_path')

    def test_tuple_bytes_change_after_validation_is_rejected_before_promotion(self):
        self.assert_input_race_rejected('tuple_path')

    def test_ledger_bytes_change_after_validation_is_rejected_before_promotion(self):
        self.assert_input_race_rejected('repair5')

    def test_native_writer_roundtrips_through_independent_bundle_reader(self):
        native = self.case.bind()
        value = self.case.v5_tuple
        expected = {'repositoryHead': value['repositoryHead'],
                    'candidateCommit': value['candidateBuildCommit'],
                    'shippingInputIdentity': value['shippingInputIdentity'],
                    'releaseFingerprintId': value['releaseFingerprintId'],
                    'toolingFingerprintId': value['toolingFingerprintId']}
        bundle = load_accepted_baseline(self.case.root, expected, {'exe': value['candidateSha256']})
        self.assertEqual(bundle['receiptSha256'], native['receiptSha256'])
