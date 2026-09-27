"""Behavioral regression tests for the advisory audit-convergence workflow."""
from pathlib import Path
import unittest

class CommandAvailability(unittest.TestCase):
    def test_analyzer_command_is_available(self):
        entry = Path(__file__).resolve().parents[1] / 'scripts' / 'audit_convergence.py'
        self.assertTrue(entry.is_file(), 'Requested audit-convergence command is not implemented')


# Imports occur inside the tests so the initial missing-command failure is explicit.
import copy
import hashlib
import json
import os
import stat
import sys
import tempfile
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))

PHASES = 'HOST-SAFETY CANDIDATE-VERIFY RESTORE-CLEAN ESTABLISH-SESSION DEPENDENCY-MATRIX SECURITY-POISON FRESH-INSTALL-WPF PRIMARY LINUX HTTP-HOSTILE MAINTENANCE-READY WINDOWS-SENTINELS REPAIR CLEAN-REINSTALL UNINSTALL FACTORY-RESET REBOOT-RESUME PERMANENT-DELETE DELETE-RESTORE STOPPED-PROJECT HOST-CONCURRENCY OPERATION-RECOVERY OWNERSHIP VAULT SURROGATE-DISPOSABLE REAL-USE-ACCEPTANCE TAILSCALE-DEFERRED TAILSCALE-AUTH AI-BUNDLE RECONCILE CLEANUP'.split()
IDENTITY = dict(repositoryHead='a'*40, candidateCommit='b'*40, shippingInputIdentity='c'*64,
                releaseFingerprintId='d'*64, toolingFingerprintId='e'*64)

def data():
    authority = dict(IDENTITY, authorityId='f'*64, generatedAtUtc='2026-09-24T10:00:00Z',
                     status='BLOCKED', blockerClassification='BLOCKED - EXACT PROOF NOT OBSERVED',
                     candidateIsCurrent=True, sourceChangedSinceCandidate=False, rebuildRequired=False,
                     validationEvidenceCurrent=False, fullReleasePassed=False, internalPromotionAllowed=False,
                     publicPromotionAllowed=False, publicPublisherTrust=False,
                     proofs={'passing':0,'required':2,'runs':[]})
    return {
      'CURRENT-CANDIDATE.json':dict(IDENTITY, candidateIsCurrent=True, sourceChangedSinceCandidate=False, rebuildRequired=False, artifacts=[]),
      'evidence/CURRENT-RELEASE-AUTHORITY.json':authority,
      'evidence/CURRENT-GATES.json':dict(IDENTITY, authorityId='f'*64, gates={'maintenance':'UNVERIFIED - 0/5'}, currentPhase='PRE-EXACT-PROOF'),
      'evidence/FULLRELEASE-SUMMARY.json':dict(IDENTITY, latestRunId=None, status='NOT_RUN_FOR_CURRENT_CANDIDATE', historicalEvidenceOnly=True, diagnosticOnly=True),
      'evidence/CURRENT-STANDARD-TOKEN.json':dict(IDENTITY, repositoryHead='0'*40, runId='standard-token-old', status='PASS', standardNonAdministratorToken=True),
      'evidence/l1-terminal-state.json':{'state':'Off','timestampUtc':'2026-09-24T07:00:00Z'},
      'evidence/l2-terminal-state.json':{'status':'UNVERIFIED','present':None,'verificationMethod':'No current nested observation'},
      'automation/release-e2e/modules/FullRelease.psm1':"$script:FullReleasePhases = @(\n"+'\n'.join("[pscustomobject]@{ id='%s'; label='%s' },"%(p,p) for p in PHASES)+"\n)\n",
      'evidence/campaigns/closed-ledger.json':{'policyId':'CLOSED','executionClosed':True,'fullReleaseMaximum':1,'fullReleaseConsumed':1,'activeReservation':None},
    }

def write_tree(root, records):
    for name, value in records.items():
        p = root/name; p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(value if isinstance(value,str) else json.dumps(value), encoding='utf-8')

def write_zip(path, records):
    content = {n:(v if isinstance(v,str) else json.dumps(v)).encode() for n,v in records.items()}
    rows = [{'path':n,'bytes':len(v),'sha256':hashlib.sha256(v).hexdigest()} for n,v in content.items()]
    m = dict(IDENTITY, status='BLOCKED',sourceInventory=rows,evidenceInventory=[],expectedSourceCount=len(rows),includedSourceCount=len(rows))
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
        for n,v in content.items(): z.writestr(n,v)
        z.writestr('AUDIT-MANIFEST.json',json.dumps(m))

class AdvisoryStateTests(unittest.TestCase):
    def setUp(self):
        from audit_convergence import summarize
        from audit_io import Snapshot
        self.summarize, self.Snapshot = summarize, Snapshot
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)/'repo';self.root.mkdir()
        self.records=data()
    def run_report(self):
        write_tree(self.root,self.records)
        with self.Snapshot(self.root) as s:return self.summarize(s)
    def test_pending_phases_are_not_failures(self):
        r=self.run_report();self.assertEqual(len(r['phases']),31)
        self.assertEqual(r['phaseCounts'],{'NOT_RUN':31})
    def test_stale_pass_token_does_not_become_current(self):
        r=self.run_report();self.assertEqual(r['standardToken']['state'],'STALE')
        self.assertIn('repositoryHead',r['standardToken']['mismatches'])
    def test_closed_ledger_never_authorizes_runtime(self):
        r=self.run_report();self.assertFalse(r['runtimeAuthorizationGranted'])
        self.assertEqual(r['ledgerObservations'][0]['executionClosed'],True)
    def test_malformed_historical_ledger_is_disclosed_and_other_ledgers_continue(self):
        self.records['evidence/campaigns/malformed-ledger.json']='{"policyId":"BROKEN","lastCompletedReservation":null,"lastCompletedReservation":{}}'
        self.records['evidence/campaigns/readable-ledger.json']={'policyId':'READABLE','status':'CLOSED','activeReservation':None}
        r=self.run_report();rows={x['path']:x for x in r['ledgerObservations']}
        broken=rows['evidence/campaigns/malformed-ledger.json']
        self.assertEqual(broken['parseStatus'],'MALFORMED');self.assertEqual(broken['parseError'],'DUPLICATE_JSON_PROPERTY')
        self.assertEqual(broken['authorizationInterpretation'],'UNKNOWN');self.assertEqual(len(broken['sha256']),64)
        self.assertEqual(rows['evidence/campaigns/readable-ledger.json']['policyId'],'READABLE')
        self.assertFalse(r['runtimeAuthorizationGranted'])
    def test_malformed_selected_authority_still_fails_closed(self):
        self.records['evidence/CURRENT-RELEASE-AUTHORITY.json']='{"status":"BLOCKED","status":"PASS"}'
        from audit_io import AuditInputError
        with self.assertRaises(AuditInputError):self.run_report()
    def test_missing_token_is_missing_not_failed_product(self):
        del self.records['evidence/CURRENT-STANDARD-TOKEN.json']
        self.assertEqual(self.run_report()['standardToken']['state'],'MISSING')
    def test_string_true_is_not_candidate_true(self):
        self.records['CURRENT-CANDIDATE.json']['candidateIsCurrent']='true'
        self.assertIn('CANDIDATE_FLAGS_NOT_CURRENT',self.run_report()['blockerCodes'])
    def test_missing_authority_never_reports_release(self):
        del self.records['evidence/CURRENT-RELEASE-AUTHORITY.json']
        r=self.run_report();self.assertIn('AUTHORITY_MISSING',r['blockerCodes'])
        self.assertFalse(r['certificationCredit'])
    def test_unknown_nested_inventory_is_not_absent(self):
        r=self.run_report();self.assertEqual(r['terminal']['l2']['status'],'UNVERIFIED')
    def test_unproven_absence_stays_recorded_only(self):
        self.records['evidence/l2-terminal-state.json']={'status':'ABSENT','present':False,'verificationMethod':'host Get-VM'}
        r=self.run_report();self.assertEqual(r['terminal']['nestedProofValidation'],'NOT_PERFORMED')
        self.assertFalse(r['certificationCredit'])
    def test_new_native_phase_is_discovered(self):
        self.records['automation/release-e2e/modules/FullRelease.psm1']=self.records['automation/release-e2e/modules/FullRelease.psm1'].replace('\n)\n',"\n[pscustomobject]@{id='NEW-GATE';label='new'}\n)\n")
        self.assertEqual(len(self.run_report()['phases']),32)
    def test_duplicate_phase_definition_is_rejected(self):
        self.records['automation/release-e2e/modules/FullRelease.psm1']=self.records['automation/release-e2e/modules/FullRelease.psm1'].replace("id='LINUX'","id='PRIMARY'")
        from audit_io import AuditInputError
        with self.assertRaises(AuditInputError): self.run_report()
    def test_authority_identity_conflict_blocks(self):
        self.records['evidence/CURRENT-RELEASE-AUTHORITY.json']['toolingFingerprintId']='0'*64
        self.assertIn('AUTHORITY_TUPLE_CONFLICT',self.run_report()['blockerCodes'])
    def test_current_token_requires_native_validation(self):
        self.records['evidence/CURRENT-STANDARD-TOKEN.json']=dict(IDENTITY,runId='standard-token-current',status='PASS',standardNonAdministratorToken=True)
        self.assertEqual(self.run_report()['standardToken']['state'],'RECORDED_CURRENT_UNVALIDATED')
    def test_fake_green_all_booleans_never_certifies(self):
        a=self.records['evidence/CURRENT-RELEASE-AUTHORITY.json']
        a.update(status='PASS',validationEvidenceCurrent=True,fullReleasePassed=True,internalPromotionAllowed=True)
        self.records['evidence/FINAL-ACCEPTANCE.json']={'status':'PASS'}
        r=self.run_report();self.assertFalse(r['certificationCredit']);self.assertIn('NATIVE_VALIDATION_REQUIRED',r['blockerCodes'])
    def test_historical_phase_record_not_counted(self):
        f=self.records['evidence/FULLRELEASE-SUMMARY.json'];f.update(latestRunId='fullrelease-test',status='BLOCKED',historicalEvidenceOnly=False)
        self.records['audit/automation-harness/runs/fullrelease-test/run-state.json']={'runId':'fullrelease-test','candidateHashes':dict(IDENTITY,toolingFingerprintId='0'*64)}
        self.records['audit/automation-harness/runs/fullrelease-test/fullrelease-phase-records.json']=[{'id':p,'status':'PASS','runId':'fullrelease-test'} for p in PHASES]
        r=self.run_report();self.assertNotIn('PASS',r['phaseCounts']);self.assertIn('FULLRELEASE_RUN_TUPLE_CONFLICT',r['blockerCodes'])
    def test_matching_run_displays_recorded_phases_not_certification(self):
        f=self.records['evidence/FULLRELEASE-SUMMARY.json'];f.update(latestRunId='fullrelease-test',status='BLOCKED',historicalEvidenceOnly=False)
        self.records['audit/automation-harness/runs/fullrelease-test/run-state.json']={'runId':'fullrelease-test','candidateHashes':IDENTITY}
        self.records['audit/automation-harness/runs/fullrelease-test/fullrelease-phase-records.json']=[{'id':'HOST-SAFETY','status':'PASS','runId':'fullrelease-test'}]
        r=self.run_report();self.assertEqual(r['phases'][0]['state'],'RECORDED_PASS');self.assertFalse(r['certificationCredit'])
    def test_wrong_run_phase_is_not_selected(self):
        f=self.records['evidence/FULLRELEASE-SUMMARY.json'];f.update(latestRunId='fullrelease-test',status='BLOCKED',historicalEvidenceOnly=False)
        self.records['audit/automation-harness/runs/fullrelease-test/run-state.json']={'runId':'fullrelease-test','candidateHashes':IDENTITY}
        self.records['audit/automation-harness/runs/fullrelease-test/fullrelease-phase-records.json']=[{'id':'HOST-SAFETY','status':'PASS','runId':'another-run'}]
        self.assertNotEqual(self.run_report()['phases'][0]['state'],'RECORDED_PASS')
    def test_snapshot_json_is_not_modified(self):
        write_tree(self.root,self.records);before={p.relative_to(self.root):p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.run_report();after={p.relative_to(self.root):p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(before,after)

class ArchiveInputTests(unittest.TestCase):
    def setUp(self):
        from audit_io import Snapshot, AuditInputError
        self.Snapshot,self.Error=Snapshot,AuditInputError
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
    def archive(self,name='a.zip'): return self.root/name
    def test_valid_archive_inventory_hashes(self):
        p=self.archive();write_zip(p,data())
        with self.Snapshot(p) as s:
            r=s.verify_inventory();self.assertEqual(r['status'],'PASS');self.assertGreater(r['verifiedFiles'],8)
    def test_tampered_member_is_detected(self):
        p=self.archive();write_zip(p,data());q=self.archive('tamper.zip')
        with zipfile.ZipFile(p) as src, zipfile.ZipFile(q,'w') as dst:
            for i in src.infolist():dst.writestr(i.filename,b'{}' if i.filename=='CURRENT-CANDIDATE.json' else src.read(i))
        with self.Snapshot(q) as s:self.assertEqual(s.verify_inventory()['status'],'FAIL')
    def test_path_traversal_rejected_before_read(self):
        p=self.archive()
        with zipfile.ZipFile(p,'w') as z:z.writestr('../escape.txt','bad')
        with self.assertRaises(self.Error):self.Snapshot(p)
    def test_backslash_path_rejected(self):
        p=self.archive()
        with zipfile.ZipFile(p,'w') as z:z.writestr('..\\escape.txt','bad')
        with self.assertRaises(self.Error):self.Snapshot(p)
    def test_case_alias_duplicate_rejected(self):
        p=self.archive()
        with zipfile.ZipFile(p,'w') as z:z.writestr('EVIDENCE/A.json','{}');z.writestr('evidence/a.json','{}')
        with self.assertRaises(self.Error):self.Snapshot(p)
    def test_symlink_member_rejected(self):
        p=self.archive();i=zipfile.ZipInfo('link');i.create_system=3;i.external_attr=(stat.S_IFLNK|0o777)<<16
        with zipfile.ZipFile(p,'w') as z:z.writestr(i,'/outside')
        with self.assertRaises(self.Error):self.Snapshot(p)
    def test_member_size_limit(self):
        p=self.archive()
        with zipfile.ZipFile(p,'w') as z:z.writestr('data.json','x'*2048)
        with self.assertRaises(self.Error):self.Snapshot(p,max_member_bytes=1024)
    def test_ads_and_windows_reserved_paths_rejected(self):
        from audit_io import safe_relative
        for s in ['C:/a','/a','a:file','CON.txt','a/../b','a//b','a.','a /b','a\x00b']:
            with self.subTest(s=s),self.assertRaises(self.Error):safe_relative(s)
    def test_duplicate_json_keys_rejected(self):
        p=self.root/'repo';p.mkdir();(p/'a.json').write_text('{"status":"PASS","status":"FAIL"}')
        with self.Snapshot(p) as s:
            with self.assertRaises(self.Error):s.json('a.json')
    def test_output_directory_inside_repository_rejected(self):
        from audit_io import safe_output_dir
        with self.assertRaises(self.Error):safe_output_dir(self.root/'outputs',self.root)
    def test_output_does_not_overwrite_existing_report(self):
        from audit_io import save_report
        out=self.root/'report';out.mkdir();(out/'analysis.json').write_text('preserve')
        with self.assertRaises(self.Error):save_report(out,{},'# report')
        self.assertEqual((out/'analysis.json').read_text(),'preserve')
    def test_workspace_link_escape_rejected(self):
        p=self.root/'repo';p.mkdir();outside=self.root/'secret';outside.write_text('secret')
        try:(p/'link').symlink_to(outside)
        except OSError:self.skipTest('OS does not allow creating test symlink')
        with self.Snapshot(p) as s:
            with self.assertRaises(self.Error):s.read('link')

class NativePlanTests(unittest.TestCase):
    def test_plan_does_not_run_native_commands(self):
        from native_runner import make_plan
        with tempfile.TemporaryDirectory() as t:
            r=make_plan(Path(t),'build','diagnostic')
            self.assertFalse(r['executed']);self.assertEqual(r['commands'][0]['kind'],'build')
            self.assertNotIn('AllowRamPressure',json.dumps(r))
    def test_verify_never_uses_script_from_archive(self):
        from native_runner import make_plan
        with tempfile.TemporaryDirectory() as t:
            r=make_plan(Path(t),'verify','diagnostic',Path(t)/'a.zip')
            self.assertEqual(len(r['commands']),2)
            self.assertTrue(all('release-tooling' not in ' '.join(x['argv']) for x in r['commands']))
    def test_native_mode_must_be_explicit_valid_value(self):
        from native_runner import make_plan
        from audit_io import AuditInputError
        with self.assertRaises(AuditInputError):make_plan(Path('.'),'verify','fake',Path('a.zip'))

class NativeExecutionBoundaryTests(unittest.TestCase):
    def setUp(self):
        from audit_io import AuditInputError
        self.Error=AuditInputError
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.repo=self.root/'repo';self.repo.mkdir()
        self.out=self.root/'out';self.out.mkdir();self.archive=self.root/'audit.zip'
        self.records={'source/tools/validate_audit_coherence.py':'print("reviewed")\n',
                      'source/VERSION':'1.2.13\n',
                      'installer-source/App.csproj':'<Project/>\n'}
        write_tree(self.repo,self.records)
    def native(self,command,repo,out):
        return {'exitCode':0,'kind':command['kind'],'nativeResult':{'status':'PASS_WITH_BLOCKER','releaseEligible':False}}
    def test_native_verification_rejects_changed_archive_code_before_execution(self):
        from unittest.mock import patch
        from native_runner import verify
        changed=dict(self.records);changed['source/tools/validate_audit_coherence.py']='print("not reviewed")\n'
        write_zip(self.archive,changed)
        with patch('native_runner._execute',side_effect=self.native) as child:
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
            self.assertEqual(child.call_count,0)
    def test_native_verification_rejects_unreviewed_msbuild_file(self):
        from unittest.mock import patch
        from native_runner import verify
        changed=dict(self.records);changed['Directory.Build.targets']='<Project><Target Name="x"/></Project>'
        write_zip(self.archive,changed)
        with patch('native_runner._execute',side_effect=self.native) as child:
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
            self.assertEqual(child.call_count,0)
    def test_native_verification_requires_source_code_guard_file(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,{'source/VERSION':'1.2.13\n'})
        with patch('native_runner._execute',side_effect=self.native) as child:
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
            self.assertEqual(child.call_count,0)
    def test_native_verify_accepts_reviewed_bytes_and_uses_private_snapshot(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,self.records)
        def execute(command,repo,out):
            path=Path(command['argv'][command['argv'].index('--archive')+1])
            self.assertNotEqual(path,self.archive)
            self.assertEqual(path.read_bytes(),self.archive.read_bytes())
            return self.native(command,repo,out)
        with patch('native_runner._execute',side_effect=execute):
            result=verify(self.repo,self.archive,'diagnostic',self.out)
        self.assertEqual(result['status'],'PASS')
        self.assertEqual(result['codeTrust']['status'],'MATCHED_REVIEWED_LIVE_SOURCES')
    def test_native_verify_accepts_crlf_only_change(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,{k:v.replace('\n','\r\n') for k,v in self.records.items()})
        with patch('native_runner._execute',side_effect=self.native):
            self.assertEqual(verify(self.repo,self.archive,'diagnostic',self.out)['status'],'PASS')
    def test_success_text_cannot_override_nonzero_native_exit(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,self.records)
        def failed(*args):
            r=self.native(*args);r['exitCode']=1;return r
        with patch('native_runner._execute',side_effect=failed) as child:
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
            self.assertEqual(child.call_count,1)
        self.assertEqual(json.loads((self.out/'native-verification.json').read_text())['status'],'FAIL')
    def test_diagnostic_native_result_cannot_claim_release(self):
        from unittest.mock import patch
        from native_runner import verify
        write_zip(self.archive,self.records)
        def wrong(*args):
            r=self.native(*args);r['nativeResult']['releaseEligible']=True;return r
        with patch('native_runner._execute',side_effect=wrong):
            with self.assertRaises(self.Error):verify(self.repo,self.archive,'diagnostic',self.out)
    def test_sidecar_verifies_hash_and_length_not_only_success_label(self):
        from native_runner import check_sidecar
        write_zip(self.archive,self.records)
        sha=hashlib.sha256(self.archive.read_bytes()).hexdigest()
        side=Path(str(self.archive)+'.sha256.txt')
        side.write_text(f'SHA-256: {sha}\nBYTES: {self.archive.stat().st_size}\n')
        self.assertTrue(check_sidecar(self.archive)['verified'])
        side.write_text(f'SHA-256: {sha}\nBYTES: 0\n')
        with self.assertRaises(self.Error):check_sidecar(self.archive)
    def test_windows_ambiguous_names_rejected(self):
        from audit_io import safe_relative
        for name in ['a?.py','a*.json','a|b','a<b','a>b','a"b']:
            with self.subTest(name=name),self.assertRaises(self.Error):safe_relative(name)

class ReviewedCheckoutTests(unittest.TestCase):
    def test_changed_tracked_or_untracked_material_rejects_native_execution(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        from native_runner import _check_repo
        from audit_io import AuditInputError
        with tempfile.TemporaryDirectory() as t:
            repo=Path(t)
            for name in ('AGENTS.md','CURRENT-CANDIDATE.json','tools/Build-AIAuditBundle.ps1','tools/validate_release_bundle.py','source/tools/validate_ai_audit_bundle.py'):
                p=repo/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('fixture')
            responses=[SimpleNamespace(returncode=0,stdout='a'*40+'\n'),SimpleNamespace(returncode=0,stdout=' M tools/validate_release_bundle.py\n')]
            with patch('native_runner.subprocess.run',side_effect=responses):
                with self.assertRaises(AuditInputError):_check_repo(repo,'a'*40)

class IsolatedPythonTests(unittest.TestCase):
    def test_cli_resolves_its_reviewed_siblings_under_isolated_python(self):
        import subprocess
        entry=Path(__file__).resolve().parents[1]/'scripts/audit_convergence.py'
        result=subprocess.run([sys.executable,'-I',str(entry),'--help'],capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('inspect',result.stdout)

if __name__ == '__main__':
    unittest.main()
