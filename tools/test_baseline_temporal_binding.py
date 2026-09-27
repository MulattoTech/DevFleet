"""Reject stale, future or wrong-reservation adoption evidence without VM access."""
import copy
from datetime import datetime, timedelta, timezone
import unittest
import test_baseline_lineage as fixtures


class BaselineTemporalBindingTests(unittest.TestCase):
    def setUp(self):
        self.case = fixtures.BaselineLineageTests(methodName='runTest')
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)

    def reject(self, **kwargs):
        with self.assertRaises(ValueError):
            self.case.invoke(**kwargs)
        self.assertFalse((self.case.root / 'evidence/baselines/CURRENT.json').exists())

    def test_matching_terminal_native_provenance_is_accepted(self):
        result = self.case.invoke()
        self.assertFalse(result['certificationCredit'])

    def test_failed_diagnostic_cannot_supply_successful_adoption(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['exitCode'] = 2
        self.reject(ledger=ledger)

    def test_missing_diagnostic_exit_code_is_not_success(self):
        ledger = copy.deepcopy(self.case.ledger)
        del ledger['attempts'][0]['exitCode']
        self.reject(ledger=ledger)

    def test_diagnostic_reserved_for_old_tooling_is_rejected(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['tuple']['toolingFingerprintId'] = '9' * 64
        self.reject(ledger=ledger)

    def test_collector_wrong_vm_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['vm']['id'] = fixtures.NEW
        self.reject(auth=auth)

    def test_collector_wrong_candidate_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['candidate']['candidateSha256'] = '9' * 64
        self.reject(auth=auth)

    def test_collection_before_reservation_is_rejected(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['reservedUtc'] = self.case.auth['observedUtc']
        self.reject(ledger=ledger)

    def test_collection_past_owner_deadline_is_rejected(self):
        ledger = copy.deepcopy(self.case.ledger)
        ledger['attempts'][0]['deadlineUtc'] = self.case.auth['startedUtc']
        self.reject(ledger=ledger)

    def test_nested_inventory_before_collection_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['nestedL2']['observedUtc'] = auth['guest']['passwordLastSetUtc']
        self.reject(auth=auth)

    def test_future_native_inventory_is_rejected(self):
        live = copy.deepcopy(self.case.live)
        live['observedUtc'] = (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()
        self.reject(live=live)

    def test_missing_collection_start_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        del auth['startedUtc']
        self.reject(auth=auth)

    def test_reversed_collection_window_is_rejected(self):
        auth = copy.deepcopy(self.case.auth)
        auth['startedUtc'] = self.case.live['observedUtc']
        self.reject(auth=auth)


if __name__ == '__main__':
    unittest.main()
