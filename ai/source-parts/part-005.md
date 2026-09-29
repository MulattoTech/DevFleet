# DevFleet source part 005

Full-source UTF-8 byte interval [186000, 232500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 63c92e9189bd7a8f9042d5887a0760246715f15c36533624ee5613aee93a81e6

<!-- BEGIN SOURCE SLICE -->
            'Report is not bound to exact L1 and predecessor CLEAN')
    for key in ('diskReadOnlyVerified', 'dismounted', 'diskFileSizeUnchanged',
                'diskWriteTimeUnchanged', 'ledgerUnchanged'):
        require(report.get(key) is True, 'Unverified read-only source chain: ' + key)
    require(report.get('guestAuthenticationAttempted') is False and report.get('vmStarted') is False,
            'Report is not a read-only offline inspection')
    require(report.get('securityLogSha256') == expected_log_sha256.lower(),
            'Guest Security log hash is not independently pinned')

    require(ledger.get('policyId') == 'DF-FRESH-CERTIFICATION-20260926-R2',
            'Wrong R2 journal')
    attempts = [a for a in ledger.get('attempts', []) if isinstance(a, dict)
                and a.get('runId') == run_id]
    require(len(attempts) == 1 and ledger.get('activeRunId') is None,
            'Run is missing, ambiguous, or still active')
    attempt = attempts[0]
    require(attempt.get('operation') == 'diagnostic' and attempt.get('state') == 'TERMINAL'
            and attempt.get('certificationCredit') is False
            and attempt.get('classification') == 'E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN',
            'Run is not the terminal historical-source diagnostic')
    start, end = instant(attempt.get('reservedUtc')), instant(attempt.get('terminalUtc'))
    require(start < end, 'Invalid terminal window')

    lab = readiness.get('lab') or {}
    auth = readiness.get('liveGuestAuth') or {}
    admission = readiness.get('admission') or {}
    require(lab.get('l1Id') == EXACT_VM and lab.get('cleanId') == EXACT_CLEAN,
            'Readiness lab identity differs')
    require(admission.get('runId') == run_id and admission.get('operation') == 'diagnostic',
            'Readiness admission differs')
    require(auth.get('attempted') is True and auth.get('cleanRestored') is True
            and auth.get('connected') is False and auth.get('finalL1State') == 'Off'
            and auth.get('failureClass') == 'System.Management.Automation.Remoting.PSDirectException'
            and 'E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN' in readiness.get('blockers', [])
            and readiness.get('certificationCredit') is False,
            'Readiness did not record the exact generic authentication rejection')

    matching = []
    events = report.get('events')
    require(isinstance(events, list) and events, 'Missing guest failure events')
    record_ids = set()
    for event in events:
        require(isinstance(event, dict) and type(event.get('recordId')) is int
                and event['recordId'] > 0 and event['recordId'] not in record_ids,
                'Malformed or duplicate event record identity')
        record_ids.add(event['recordId'])
        require(event.get('eventId') == 4625 and STATUS.fullmatch(str(event.get('status', '')))
                and STATUS.fullmatch(str(event.get('subStatus', ''))),
                'Malformed guest failure event')
        event_time = instant(event.get('timeUtc'))
        if start <= event_time <= end and event.get('targetUser') == EXACT_ACCOUNT \
                and event.get('computer', '').lower() == EXACT_COMPUTER.lower():
            matching.append(event)
    require(len(matching) == 1, 'Missing or conflicting exact account failures in run window')
    event = matching[0]
    status, substatus = event['status'].lower(), event['subStatus'].lower()
    return {
        'schemaVersion': 1, 'scope': 'SUPPLEMENTARY_HISTORICAL_DIAGNOSIS',
        'runId': run_id, 'classification': CLASSIFICATIONS.get((status, substatus),
                                                               'UNKNOWN_AUTH_FAILURE'),
        'historicalLedgerClassification': attempt['classification'],
        'guestAuthenticated': False, 'certificationCredit': False,
        'reportSha256': actual_hash, 'securityLogSha256': expected_log_sha256.lower(),
        'vmId': EXACT_VM, 'parentCheckpointId': EXACT_CLEAN,
        'event': {'recordId': event['recordId'], 'eventId': 4625,
                  'timeUtc': event['timeUtc'], 'computer': event['computer'],
                  'targetUser': event['targetUser'], 'status': status, 'subStatus': substatus},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True)
    parser.add_argument('--report-sha256', required=True)
    parser.add_argument('--security-log-sha256', required=True)
    parser.add_argument('--ledger', required=True)
    parser.add_argument('--readiness', required=True)
    parser.add_argument('--run-id', required=True)
    args = parser.parse_args()
    require(args.report_sha256.lower() == PINNED_RDC_REPORT_SHA256
            and args.security_log_sha256.lower() == PINNED_RDC_SECURITY_LOG_SHA256,
            'RDC source hashes are not the independently pinned values')
    print(json.dumps(diagnose(args.report, args.report_sha256, args.security_log_sha256,
                              args.ledger, args.readiness, args.run_id), indent=2))


if __name__ == '__main__':
    main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_campaign_successor.py

SHA256: ebd01d69eaaafc709e8a1d5351dcd541a0db0f6f7a8bdb98a1731082bae39c3f | Bytes: 1854 | Git mode: 100644

```
import importlib.util, json, pathlib, tempfile, unittest
HERE=pathlib.Path(__file__).parent
class SuccessorTests(unittest.TestCase):
 def setUp(self):
  spec=importlib.util.spec_from_file_location('journal',HERE/'fresh_attempts.py');self.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.m)
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=pathlib.Path(self.temp.name)
  self.auth=self.root/'old-auth.md';self.auth.write_text('Original user request')
  self.old=self.root/'old.json';self.m.initialize(self.old,self.auth,[])
  self.auth2=self.root/'new-auth.md';self.auth2.write_text('New user explicitly requests full new allowance')
  self.new=self.root/'new.json';self.policy='DF-FRESH-CERTIFICATION-20260926-R2'
 def test_successor_starts_full_preserving_parent_bytes(self):
  before=self.old.read_bytes();self.m.initialize(self.new,self.auth2,[self.old],policy_id=self.policy)
  self.assertEqual(self.old.read_bytes(),before);self.assertEqual(self.m.status(self.new)['remaining'],self.m.LIMITS)
  self.assertEqual(self.m.status(self.new)['policyId'],self.policy)
 def test_successor_requires_parent(self):
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth2,[],policy_id=self.policy)
 def test_successor_cannot_reuse_old_authorization(self):
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth,[self.old],policy_id=self.policy)
 def test_unknown_policy_rejected(self):
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth2,[self.old],policy_id='unknown')
 def test_existing_successor_cannot_reset(self):
  self.m.initialize(self.new,self.auth2,[self.old],policy_id=self.policy)
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth2,[self.old],policy_id=self.policy)
if __name__=='__main__':unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_fresh_attempts.py

SHA256: ddd5e4619228c6f0cf99a54faab744b81725c53f7b95ee14b6bdbdda29a4f10e | Bytes: 7148 | Git mode: 100644

```
"""Behavioral tests for prospective attempt accounting (never certification)."""
import importlib.util
import json
import pathlib
import tempfile
import unittest
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent

class FreshAttemptTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue((HERE/'fresh_attempts.py').exists(), 'Fresh attempt journal implementation is missing')
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE/'fresh_attempts.py')
        self.m = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.m)
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.auth = self.root/'authorization.txt'; self.auth.write_text('Explicit fresh campaign requested; keep history.')
        self.old = self.root/'old.json'; self.old.write_text('{"used":9,"historical":true}')
        self.ledger = self.root/'fresh.json'
        self.m.initialize(self.ledger, self.auth, [self.old])
        self.request = dict(runId='fresh-test-1', operation='diagnostic', owner={'pid':123,'startUtc':'2026-09-26T17:00:00Z'}, tuple={'repositoryHead':'a'*40}, entrypoint='native-test.ps1', entrypointSha256='b'*64, arguments=['-RunId','fresh-test-1'], changedCondition='owner-reported correction', deadlineUtc='2099-01-01T00:00:00Z')
    def test_new_campaign_preserves_old(self):
        self.assertEqual(self.old.read_text(),'{"used":9,"historical":true}')
        self.assertEqual(self.m.status(self.ledger)['remaining']['diagnostic'],6)
    def test_reinitialize_cannot_reset(self):
        self.m.reserve(self.ledger,self.request)
        with self.assertRaises(ValueError): self.m.initialize(self.ledger,self.auth,[self.old])
        self.assertEqual(self.m.status(self.ledger)['remaining']['diagnostic'],5)
    def test_reservation_charged_before_action(self):
        self.m.reserve(self.ledger,self.request)
        self.assertEqual(self.m.status(self.ledger)['active']['runId'],'fresh-test-1')
        self.assertEqual(self.m.status(self.ledger)['remaining']['diagnostic'],5)
    def test_second_owner_cannot_overlap(self):
        self.m.reserve(self.ledger,self.request)
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,runId='second'))
    def test_finish_keeps_consumption_and_no_release_credit(self):
        self.m.reserve(self.ledger,self.request)
        self.m.finish(self.ledger,'fresh-test-1',self.request['owner'],2,'AUTH_REJECTED',[])
        s=self.m.status(self.ledger); self.assertIsNone(s['active']); self.assertEqual(s['remaining']['diagnostic'],5)
        self.assertFalse(s['certificationCredit'])
    def test_finish_wrong_owner_rejected(self):
        self.m.reserve(self.ledger,self.request)
        with self.assertRaises(ValueError): self.m.finish(self.ledger,'fresh-test-1',{'pid':124,'startUtc':'other'},0,'EXIT',[])
    def test_duplicate_run_id_rejected(self):
        self.m.reserve(self.ledger,self.request); self.m.finish(self.ledger,'fresh-test-1',self.request['owner'],0,'EXIT',[])
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,self.request)
    def test_dry_run_is_zero_write(self):
        before={p.name:p.read_bytes() for p in self.root.iterdir()}
        self.m.reserve(self.ledger,self.request,dry_run=True)
        self.assertEqual(before,{p.name:p.read_bytes() for p in self.root.iterdir()})
    def test_expired_deadline_rejected(self):
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,deadlineUtc='2000-01-01T00:00:00Z'))
    def test_missing_changed_condition_rejected(self):
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,changedCondition=''))
    def test_duplicate_json_key_rejected(self):
        self.ledger.write_text('{"schemaVersion":1,"schemaVersion":2}')
        with self.assertRaises(ValueError): self.m.status(self.ledger)
    def test_boolean_limit_rejected(self):
        d=json.loads(self.ledger.read_text()); d['limits']['diagnostic']=True; self.ledger.write_text(json.dumps(d))
        with self.assertRaises(ValueError): self.m.status(self.ledger)
    def test_nonfinite_rejected(self):
        self.ledger.write_text('{"number":NaN}')
        with self.assertRaises(ValueError): self.m.status(self.ledger)
    def test_changed_authorization_rejected(self):
        self.auth.write_text('replaced')
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,self.request)
    def test_exhaustion_has_no_refund(self):
        for i in range(6):
            q=dict(self.request,runId=f'fresh-{i}'); self.m.reserve(self.ledger,q); self.m.finish(self.ledger,q['runId'],q['owner'],1,'FAIL',[])
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,runId='seventh'))
    def test_negative_exit_is_not_silently_success(self):
        self.m.reserve(self.ledger,self.request); self.m.finish(self.ledger,'fresh-test-1',self.request['owner'],-1,'INTERRUPTED',[])
        self.assertEqual(json.loads(self.ledger.read_text())['attempts'][0]['exitCode'],-1)
    def test_bad_run_id_cannot_traverse(self):
        with self.assertRaises(ValueError): self.m.reserve(self.ledger,dict(self.request,runId='../escape'))
    def test_interrupted_atomic_write_retains_previous_record(self):
        before=self.ledger.read_bytes(); original=self.m.os.replace
        def fail(*a,**kw): raise OSError('simulated interrupted commit')
        self.m.os.replace=fail
        try:
            with self.assertRaises(OSError): self.m.reserve(self.ledger,self.request)
        finally: self.m.os.replace=original
        self.assertEqual(before,self.ledger.read_bytes())

    def test_held_os_lock_rejects_other_process_without_charge(self):
        q=self.root/'request.json'; q.write_text(json.dumps(self.request))
        cmd=[sys.executable,str(HERE/'fresh_attempts.py'),'reserve','--ledger',str(self.ledger),'--request',str(q)]
        with self.m.locked(self.ledger):
            denied=subprocess.run(cmd,capture_output=True,text=True,timeout=15)
        self.assertNotEqual(denied.returncode,0)
        self.assertEqual(self.m.status(self.ledger)['attemptCount'],0)
        accepted=subprocess.run(cmd,capture_output=True,text=True,timeout=15)
        self.assertEqual(accepted.returncode,0,accepted.stderr)
        self.assertEqual(self.m.status(self.ledger)['attemptCount'],1)
    def test_two_process_reservations_have_one_winner(self):
        workers=[]
        for i in range(2):
            q=self.root/f'request-{i}.json'; q.write_text(json.dumps(dict(self.request,runId=f'race-{i}')))
            workers.append(subprocess.Popen([sys.executable,str(HERE/'fresh_attempts.py'),'reserve','--ledger',str(self.ledger),'--request',str(q)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True))
        for worker in workers: worker.communicate(timeout=15)
        self.assertEqual(sum(w.returncode==0 for w in workers),1)
        self.assertEqual(self.m.status(self.ledger)['attemptCount'],1)

if __name__=='__main__': unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_guest_auth_diagnosis.py

SHA256: 22465e9161d47219513c96fd5647cacb2010c85fb19ec2fa14a2fde4057cf190 | Bytes: 6653 | Git mode: 100644

```
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

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_one_diagnostic_successor.py

SHA256: 6f4bc5f5dcbf14324c13889e4066b3b5560f9a7e86df086a7e28ec6f7bd2a777 | Bytes: 4055 | Git mode: 100644

```
import importlib.util
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone


HERE = pathlib.Path(__file__).parent


class OneDiagnosticSuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.base_auth = self.root / 'base-auth.md'
        self.r2_auth = self.root / 'r2-auth.md'
        self.d1_auth = self.root / 'one-diagnostic-auth.md'
        for path, value in ((self.base_auth, 'base'), (self.r2_auth, 'r2'),
                            (self.d1_auth, 'one additional diagnostic only')):
            path.write_text(value, encoding='utf-8')
        self.base = self.root / 'base.json'
        self.r2 = self.root / 'r2.json'
        self.d1 = self.root / 'r2-d1.json'
        self.journal.initialize(self.base, self.base_auth, [])
        self.journal.initialize(self.r2, self.r2_auth, [self.base], self.journal.POLICY_ID + '-R2')

    def request(self, number, operation='diagnostic'):
        return {'runId': f'diagnostic-{number}', 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': '2026-09-27T00:00:00Z'},
                'tuple': {'repositoryHead': 'a' * 40}, 'entrypoint': 'readiness.ps1',
                'entrypointSha256': 'b' * 64, 'arguments': [],
                'changedCondition': 'independent bounded test',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def exhaust_r2(self):
        for number in range(6):
            request = self.request(number)
            self.journal.reserve(self.r2, request)
            self.journal.finish(self.r2, request['runId'], request['owner'], 2, 'TEST_TERMINAL', [])

    def test_only_one_diagnostic_and_no_other_operations(self):
        self.exhaust_r2()
        original = self.r2.read_bytes()
        self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.assertEqual(self.r2.read_bytes(), original)
        remaining = self.journal.status(self.d1)['remaining']
        self.assertEqual(remaining['diagnostic'], 1)
        self.assertTrue(all(value == 0 for key, value in remaining.items() if key != 'diagnostic'))
        with self.assertRaises(ValueError):
            self.journal.reserve(self.d1, self.request(11, 'laptop-proof'), dry_run=True)
        first = self.request(12)
        self.journal.reserve(self.d1, first)
        self.journal.finish(self.d1, first['runId'], first['owner'], 2, 'TEST_TERMINAL', [])
        self.assertEqual(self.journal.status(self.d1)['remaining']['diagnostic'], 0)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.d1, self.request(13), dry_run=True)

    def test_requires_exhausted_terminal_r2_and_separate_authorization(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.exhaust_r2()
        with self.assertRaises(ValueError):
            self.journal.initialize(self.d1, self.r2_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        with self.assertRaises(ValueError):
            self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)

    def test_predecessor_bytes_are_pinned(self):
        self.exhaust_r2()
        self.journal.initialize(self.d1, self.d1_auth, [self.r2], self.journal.ONE_DIAGNOSTIC_ID)
        self.r2.write_bytes(self.r2.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.d1)


if __name__ == '__main__':
    unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_r2_repair2_successor.py

SHA256: c6dfe26882762f28038aa79fdb05727efe86312f3d981d3ed361c96567e05b9e | Bytes: 5798 | Git mode: 100644

```
"""VM-free fail-closed admission for one new signed-candidate repair successor."""
import importlib.util
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

HERE = pathlib.Path(__file__).resolve().parent


class Repair2SuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.auth = [self.root / name for name in ('base-auth.md', 'r2-auth.md', 'repair1-auth.md', 'repair2-auth.md')]
        for index, path in enumerate(self.auth):
            path.write_text(f'distinct owner authorization {index}', encoding='utf-8')
        self.base, self.r2, self.r2_snapshot, self.repair1, self.repair1_snapshot, self.repair2 = [
            self.root / name for name in ('base.json', 'r2.json', 'r2-snapshot.json', 'repair1.json', 'repair1-snapshot.json', 'repair2.json')
        ]
        self.journal.initialize(self.base, self.auth[0], [])
        self.journal.initialize(self.r2, self.auth[1], [self.base], self.journal.POLICY_ID + '-R2')
        self.r2_snapshot.write_bytes(self.r2.read_bytes())
        self.journal.initialize(self.repair1, self.auth[2], [self.r2_snapshot, self.r2], self.journal.REPAIR_ID)

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': 'a' * 40}, 'entrypoint': 'native-test.ps1',
                'entrypointSha256': 'b' * 64, 'arguments': [],
                'changedCondition': 'new signed candidate after fail-closed permanent-delete block',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def terminal_repair1(self):
        for index, (operation, classification) in enumerate(self.journal.REPAIR_SEQUENCE):
            request = self.request(operation, f'repair1-{index}')
            self.journal.reserve(self.repair1, request)
            code = 2 if operation == 'fullrelease' else 0
            result = 'NATIVE_FULLRELEASE_BLOCKED' if code else classification
            self.journal.finish(self.repair1, request['runId'], request['owner'], code, result, [])
        self.repair1_snapshot.write_bytes(self.repair1.read_bytes())

    def test_terminal_predecessor_and_exact_allowance(self):
        self.terminal_repair1()
        prior = self.repair1.read_bytes()
        status = self.journal.initialize(self.repair2, self.auth[3],
                                         [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        self.assertEqual(self.repair1.read_bytes(), prior)
        self.assertEqual(self.repair1_snapshot.read_bytes(), prior)
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0, 'build-sign': 1})
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair2, self.request('standard-token', 'out-of-order'), dry_run=True)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair2, self.request('maintenance', 'disallowed'), dry_run=True)
        request = self.request('build-sign', 'new-build')
        self.journal.reserve(self.repair2, request)
        self.journal.finish(self.repair2, request['runId'], request['owner'], 0,
                            'PASS_NATIVE_BUILD_SIGN', [])
        self.assertEqual(self.journal.status(self.repair2)['remaining']['build-sign'], 0)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair2, self.request('build-sign', 'second-build'), dry_run=True)

    def test_predecessor_or_authorization_drift_fails_closed(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair2, self.auth[3], [self.repair1, self.repair1], self.journal.REPAIR2_ID)
        self.terminal_repair1()
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair2, self.auth[2], [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        self.repair1_snapshot.write_bytes(self.repair1_snapshot.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.journal.initialize(self.repair2, self.auth[3], [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        self.repair1_snapshot.write_bytes(self.repair1.read_bytes())
        self.journal.initialize(self.repair2, self.auth[3], [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        self.repair1.write_bytes(self.repair1.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.repair2)

    def test_failed_build_sign_blocks_qualification(self):
        self.terminal_repair1()
        self.journal.initialize(self.repair2, self.auth[3], [self.repair1_snapshot, self.repair1], self.journal.REPAIR2_ID)
        request = self.request('build-sign', 'failed-build')
        self.journal.reserve(self.repair2, request)
        self.journal.finish(self.repair2, request['runId'], request['owner'], 2, 'BUILD_SIGN_BLOCKED', [])
        with self.assertRaises(ValueError):
            self.journal.reserve(self.repair2, self.request('standard-token', 'qualification'), dry_run=True)


if __name__ == '__main__':
    unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_r2_repair3_successor.py

SHA256: af9eb3ad99073405be07e0c73eb9f4fe676ee0efdebd931c05b4bbc8a8f9b8e4 | Bytes: 7316 | Git mode: 100644

```
"""VM-free prospective admission tests for the R2 repair-3 policy."""
import importlib.util
import json
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

HERE = pathlib.Path(__file__).resolve().parent


class Repair3SuccessorTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.auth = [self.root / name for name in ('base.md', 'r2.md', 'r3.md')]
        for i, path in enumerate(self.auth):
            path.write_text(f'distinct authorization {i}', encoding='utf-8')
        self.base, historical, historical_snapshot, repair1, repair1_snapshot, self.r2, self.r2_snapshot, self.r3, self.receipt = [
            self.root / name for name in ('base.json', 'historical.json', 'historical-snapshot.json',
                                          'repair1.json', 'repair1-snapshot.json', 'r2.json',
                                          'r2-snapshot.json', 'r3.json', 'inspection.json')]
        self.journal.initialize(self.base, self.auth[0], [])
        self.journal.initialize(historical, self.auth[1], [self.base], self.journal.POLICY_ID + '-R2')
        historical_snapshot.write_bytes(historical.read_bytes())
        self.journal.initialize(repair1, self.auth[2], [historical_snapshot, historical], self.journal.REPAIR_ID)
        for index, (operation, classification) in enumerate(self.journal.REPAIR_SEQUENCE):
            request = self.request(operation, f'repair1-{index}')
            self.journal.reserve(repair1, request)
            code = 2 if operation == 'fullrelease' else 0
            self.journal.finish(repair1, request['runId'], request['owner'], code,
                                'NATIVE_FULLRELEASE_BLOCKED' if code else classification, [])
        repair1_snapshot.write_bytes(repair1.read_bytes())
        self.journal.initialize(self.r2, self.auth[1], [repair1_snapshot, repair1], self.journal.REPAIR2_ID)
        self._terminal_repair2()
        self.r2_snapshot.write_bytes(self.r2.read_bytes())
        self.receipt.write_text(json.dumps({
            'schemaVersion': 1,
            'contract': 'devfleet-signed-build-output-inspection-v1',
            'status': 'PASS_VERIFIED_SIGNED_OUTPUT_WITH_FAILED_ADMISSION',
            'certificationCredit': False,
            'repositoryHead': self.journal.REPAIR3_CANDIDATE_COMMIT,
            'failedAttemptLedgerSha256': self.journal.REPAIR3_FAILED_LEDGER_SHA256,
            'shippingInputIdentity': self.journal.REPAIR3_SHIPPING_SHA256,
            'artifacts': [
                {'name': 'exe', 'path': 'candidate.exe', 'sha256': self.journal.REPAIR3_SIGNED_EXE_SHA256},
                {'name': 'tar', 'path': 'candidate.tar.gz', 'sha256': '2' * 64},
                {'name': 'portable', 'path': 'candidate.zip', 'sha256': '3' * 64},
                {'name': 'installerSource', 'path': 'installer.zip', 'sha256': '4' * 64},
            ],
            'signatureStatus': 'Valid', 'publicPromotionAllowed': False,
            'publicPublisherTrust': False,
        }), encoding='utf-8')
        actual_dir = pathlib.Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work\DevFleet-v1.2.13-development\audit\agent-memory\attempts\DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-2')
        actual_ledger = actual_dir / 'ledger.json'
        actual_receipt = actual_dir / 'signed-build-output-inspection.json'
        self.r2.write_bytes(actual_ledger.read_bytes())
        self.r2_snapshot.write_bytes(actual_ledger.read_bytes())
        self.receipt = actual_receipt

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': self.journal.REPAIR3_CANDIDATE_COMMIT},
                'entrypoint': 'native-test.ps1', 'entrypointSha256': 'b' * 64,
                'arguments': [], 'changedCondition': 'wrapper numeric signatureStatus admission correction',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def _terminal_repair2(self):
        request = self.request('build-sign', 'repair2-build-sign')
        self.journal.reserve(self.r2, request)
        self.journal.finish(self.r2, request['runId'], request['owner'], 2, 'BUILD_SIGN_BLOCKED', [])

    def initialize(self):
        return self.journal.initialize(self.r3, self.auth[2],
                                       [self.r2_snapshot, self.r2], self.journal.REPAIR3_ID,
                                       self.receipt)

    def test_exact_allowance_and_strict_sequence(self):
        status = self.initialize()
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0,
                                               'build-sign': 0})
        with self.assertRaises(ValueError):
            self.journal.reserve(self.r3, self.request('build-sign', 'rebuild'), dry_run=True)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.r3, self.request('diagnostic', 'out-of-order'), dry_run=True)
        for index, (operation, classification) in enumerate(self.journal.REPAIR3_SEQUENCE):
            request = self.request(operation, f'repair3-{index}')
            self.journal.reserve(self.r3, request)
            self.journal.finish(self.r3, request['runId'], request['owner'], 0, classification, [])
        self.assertEqual(self.journal.status(self.r3)['attemptCount'], 5)

    def test_rejects_wrong_predecessor_or_reused_authorization(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.r3, self.auth[2], [self.r2, self.r2], self.journal.REPAIR3_ID, self.receipt)
        with self.assertRaises(ValueError):
            reused = self.journal.load(self.r2)['authorization']['path']
            self.journal.initialize(self.r3, reused, [self.r2_snapshot, self.r2], self.journal.REPAIR3_ID, self.receipt)

    def test_receipt_is_required_and_immutable(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.r3, self.auth[2], [self.r2_snapshot, self.r2], self.journal.REPAIR3_ID)
        tampered = self.root / 'tampered-inspection.json'
        tampered.write_bytes(self.receipt.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'source identity differs'):
            self.journal.initialize(self.r3, self.auth[2],
                                    [self.r2_snapshot, self.r2], self.journal.REPAIR3_ID, tampered)

    def test_substitute_predecessor_is_rejected(self):
        self.initialize()
        self.r2_snapshot.write_bytes(self.r2.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.r3)


if __name__ == '__main__':
    unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_r2_repair4_successor.py

SHA256: 90c8d331205d7756b0d52d59df02c30767c813c897dd95422f1cce4c9191a2be | Bytes: 4498 | Git mode: 100644

```
"""VM-free admission checks for a proposed fourth repair successor.

This test copies the terminal native predecessor; it never reserves a live RunId.
"""
import importlib.util
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone


HERE = pathlib.Path(__file__).resolve().parent
NATIVE_REPAIR3 = (HERE.parents[4] / 'audit' / 'agent-memory' / 'attempts'
                  / 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-3' / 'ledger.json')


class Repair4SuccessorTests(unittest.TestCase):
    def setUp(self):
        if not NATIVE_REPAIR3.is_file():
            self.skipTest('Original native repair-3 ledger is unavailable')
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.live = self.root / 'repair3-live.json'
        self.snapshot = self.root / 'repair3-terminal-snapshot.json'
        self.live.write_bytes(NATIVE_REPAIR3.read_bytes())
        self.snapshot.write_bytes(self.live.read_bytes())
        self.authorization = self.root / 'distinct-owner-approval.md'
        self.authorization.write_text('distinct proposed fourth repair authorization', encoding='utf-8')
        self.successor = self.root / 'repair4.json'

    def initialize(self):
        return self.journal.initialize(self.successor, self.authorization,
                                       [self.snapshot, self.live], self.journal.REPAIR4_ID)

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': 'a' * 40},
                'entrypoint': 'reviewed-native-test.ps1', 'entrypointSha256': 'b' * 64,
                'arguments': [], 'changedCondition': 'focused nested Primary readiness diagnosis',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def test_exact_allowance_order_and_no_refund(self):
        status = self.initialize()
        self.assertEqual(status['remaining'], {'standard-token': 1, 'laptop-proof': 1,
                                               'desktop-proof': 1, 'fullrelease': 1,
                                               'diagnostic': 1, 'maintenance': 0,
                                               'build-sign': 0})
        with self.assertRaises(ValueError):
            self.journal.reserve(self.successor, self.request('diagnostic', 'out-of-order'), dry_run=True)
        for index, (operation, result) in enumerate(self.journal.REPAIR4_SEQUENCE):
            request = self.request(operation, f'repair4-{index}')
            self.journal.reserve(self.successor, request)
            self.journal.finish(self.successor, request['runId'], request['owner'], 0, result, [])
        self.assertEqual(self.journal.status(self.successor)['attemptCount'], 5)
        with self.assertRaises(ValueError):
            self.journal.reserve(self.successor, self.request('fullrelease', 'extra'), dry_run=True)

    def test_rejects_reused_authorization_and_changed_predecessor(self):
        old_auth = self.journal.load(self.live)['authorization']['path']
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, old_auth,
                                    [self.snapshot, self.live], self.journal.REPAIR4_ID)
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, self.snapshot,
                                    [self.snapshot, self.live], self.journal.REPAIR4_ID)
        self.initialize()
        self.snapshot.write_bytes(self.snapshot.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'predecessor changed'):
            self.journal.status(self.successor)

    def test_rejects_wrong_parent_and_distinct_snapshot(self):
        with self.assertRaises(ValueError):
            self.journal.initialize(self.successor, self.authorization,
                                    [self.live, self.live], self.journal.REPAIR4_ID)
        self.snapshot.write_bytes(self.live.read_bytes() + b' ')
        with self.assertRaises(ValueError):
            self.initialize()


if __name__ == '__main__':
    unittest.main()

```


## FILE: .agents/skills/devfleet-certification-orchestrator/scripts/fresh/test_r2_repair5_successor.py

SHA256: a37284a6cac41353a88de659b7c6f0f61bda3b0f1c2f2413a4c5c066e313df58 | Bytes: 4734 | Git mode: 100644

```
"""VM-free admission checks for a separately authorized fifth repair successor."""
import importlib.util
import json
import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone


HERE = pathlib.Path(__file__).resolve().parent
NATIVE_REPAIR4 = (pathlib.Path(r'C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work'
                               r'\DevFleet-v1.2.13-development') / 'audit' / 'agent-memory'
                  / 'attempts' / 'DF-FRESH-CERTIFICATION-20260926-R2-REPAIR-4' / 'ledger.json')


class Repair5SuccessorTests(unittest.TestCase):
    def setUp(self):
        if not NATIVE_REPAIR4.is_file():
            self.skipTest('Original native repair-4 ledger is unavailable')
        spec = importlib.util.spec_from_file_location('fresh_attempts', HERE / 'fresh_attempts.py')
        self.journal = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.journal)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.live = self.root / 'repair4-live.json'
        self.snapshot = self.root / 'repair4-terminal-snapshot.json'
        self.live.write_bytes(NATIVE_REPAIR4.read_bytes())
        self.snapshot.write_bytes(self.live.read_bytes())
        self.authorization = self.root / 'new-owner-approval.md'
        self.authorization.write_text('distinct prospective fifth repair authorization', encoding='utf-8')
        self.successor = self.root / 'repair5.json'

    def initialize(self):
        return self.journal.initialize(self.successor, self.authorization,
                                       [self.snapshot, self.live], self.journal.REPAIR5_ID)

    def request(self, operation, run_id):
        return {'runId': run_id, 'operation': operation,
                'owner': {'pid': 1234, 'startUtc': datetime.now(timezone.utc).isoformat()},
                'tuple': {'repositoryHead': 'a' * 40},
                'entrypoint': 'reviewed-native-test.ps1', 'entrypointSha256': 'b' * 64,
                'arguments': [], 'changedCondition': 'complete generation-5 native binding before qualification',
                'deadlineUtc': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}

    def test_exact_allowance_and