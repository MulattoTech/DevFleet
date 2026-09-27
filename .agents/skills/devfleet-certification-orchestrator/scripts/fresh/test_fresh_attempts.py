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
