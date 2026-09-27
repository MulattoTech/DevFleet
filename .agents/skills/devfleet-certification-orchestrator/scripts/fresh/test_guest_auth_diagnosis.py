"""VM-free regressions for supplementary guest-auth event interpretation."""
import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from guest_auth_diagnosis import diagnose


RUN_ID = 'r2-historical-credential-20260927T011933Z-36149a48'
VM_ID = '84b7d8b8-ee6c-4085-aa29-4b0adc316de2'
CLEAN_ID = '19865b76-4c3a-44f7-ba39-841e9d3c40c9'
LOG_HASH = 'b' * 64


class GuestAuthDiagnosisTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.report = {
            'scope': 'OFFLINE_READ_ONLY_GUEST_EVENT_INSPECTION',
            'vmId': VM_ID, 'parentCheckpointId': CLEAN_ID,
            'diskReadOnlyVerified': True, 'dismounted': True,
            'diskFileSizeUnchanged': True, 'diskWriteTimeUnchanged': True,
            'ledgerUnchanged': True, 'guestAuthenticationAttempted': False,
            'vmStarted': False, 'securityLogSha256': LOG_HASH,
            'events': [{
                'recordId': 3263, 'eventId': 4625,
                'timeUtc': '2026-09-27T01:20:06.9086047Z',
                'computer': 'DevFleet-E2E-01', 'targetUser': 'E2EAdmin',
                'status': '0xc000006e', 'subStatus': '0xc0000071',
            }],
        }
        self.ledger = {'policyId': 'DF-FRESH-CERTIFICATION-20260926-R2',
                       'activeRunId': None, 'attempts': [{
                           'runId': RUN_ID, 'operation': 'diagnostic',
                           'state': 'TERMINAL', 'certificationCredit': False,
                           'reservedUtc': '2026-09-27T01:19:33.266233+00:00',
                           'terminalUtc': '2026-09-27T01:20:09.640373+00:00',
                           'classification': 'E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN',
                       }]}
        self.readiness = {'certificationCredit': False,
                          'lab': {'l1Id': VM_ID, 'cleanId': CLEAN_ID},
                          'liveGuestAuth': {'attempted': True, 'cleanRestored': True,
                                            'connected': False, 'finalL1State': 'Off',
                                            'failureClass': 'System.Management.Automation.Remoting.PSDirectException'},
                          'admission': {'runId': RUN_ID, 'operation': 'diagnostic'},
                          'blockers': ['E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN']}

    def check(self, *, report=None, ledger=None, readiness=None,
              expected_report_hash=None, expected_log_hash=LOG_HASH):
        report = self.report if report is None else report
        ledger = self.ledger if ledger is None else ledger
        readiness = self.readiness if readiness is None else readiness
        def write(name, value):
            path = self.root / name
            path.write_text(json.dumps(value), encoding='utf-8')
            return path
        report_path = write('report.json', report)
        ledger_path = write('ledger.json', ledger)
        readiness_path = write('readiness.json', readiness)
        report_hash = expected_report_hash or hashlib.sha256(report_path.read_bytes()).hexdigest()
        return diagnose(report_path, report_hash, expected_log_hash,
                        ledger_path, readiness_path, RUN_ID)

    def test_exact_expiry_is_supplementary_only(self):
        result = self.check()
        self.assertEqual(result['classification'], 'PASSWORD_EXPIRED')
        self.assertEqual(result['event']['recordId'], 3263)
        self.assertEqual(result['event']['status'], '0xc000006e')
        self.assertEqual(result['event']['subStatus'], '0xc0000071')
        self.assertFalse(result['certificationCredit'])
        self.assertFalse(result['guestAuthenticated'])

    def test_wrong_password_disabled_lockout_and_unknown_are_distinct(self):
        cases = [('0xc000006d', '0xc000006a', 'WRONG_PASSWORD'),
                 ('0xc000006e', '0xc0000072', 'ACCOUNT_DISABLED'),
                 ('0xc0000234', '0xc0000234', 'ACCOUNT_LOCKED'),
                 ('0xdeadbeef', '0xdeadbeef', 'UNKNOWN_AUTH_FAILURE')]
        for status, substatus, expected in cases:
            with self.subTest(expected=expected):
                report = copy.deepcopy(self.report)
                report['events'][0].update(status=status, subStatus=substatus)
                self.assertEqual(self.check(report=report)['classification'], expected)

    def test_wrong_vm_account_time_and_conflicts_rejected(self):
        for edit in ('vm', 'account', 'time', 'conflict'):
            with self.subTest(edit=edit):
                report = copy.deepcopy(self.report)
                if edit == 'vm': report['vmId'] = '00000000-0000-0000-0000-000000000001'
                if edit == 'account': report['events'][0]['targetUser'] = 'SomeoneElse'
                if edit == 'time': report['events'][0]['timeUtc'] = '2026-09-27T01:30:06Z'
                if edit == 'conflict':
                    other = dict(report['events'][0], recordId=3264,
                                 status='0xc000006d', subStatus='0xc000006a')
                    report['events'].append(other)
                with self.assertRaises(ValueError): self.check(report=report)

    def test_missing_malformed_and_unverified_source_rejected(self):
        for edit in ('missing_event', 'missing_hash', 'not_read_only', 'bad_log_hash',
                     'wrong_report_hash', 'not_dismounted'):
            with self.subTest(edit=edit):
                report = copy.deepcopy(self.report)
                options = {}
                if edit == 'missing_event': report['events'] = []
                if edit == 'missing_hash': report.pop('securityLogSha256')
                if edit == 'not_read_only': report['diskReadOnlyVerified'] = False
                if edit == 'bad_log_hash': options['expected_log_hash'] = 'a' * 64
                if edit == 'wrong_report_hash': options['expected_report_hash'] = 'a' * 64
                if edit == 'not_dismounted': report['dismounted'] = False
                with self.assertRaises(ValueError): self.check(report=report, **options)

    def test_unverified_run_and_transport_cannot_be_expiry(self):
        ledger = copy.deepcopy(self.ledger)
        ledger['attempts'][0]['state'] = 'ACTIVE'
        with self.assertRaises(ValueError): self.check(ledger=ledger)
        readiness = copy.deepcopy(self.readiness)
        readiness['liveGuestAuth']['failureClass'] = 'System.TimeoutException'
        with self.assertRaises(ValueError): self.check(readiness=readiness)


if __name__ == '__main__': unittest.main()
