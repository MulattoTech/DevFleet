"""VM-free Command Center snapshots from synthetic native/public trees."""
import importlib.util
import json
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


MODULE_PATH = Path(__file__).with_name('certification_command_center.py')
spec = importlib.util.spec_from_file_location('certification_command_center', MODULE_PATH)
center = importlib.util.module_from_spec(spec)
spec.loader.exec_module(center)
LEDGER = 'audit/agent-memory/attempts/DF-TEST/ledger.json'
RUN = 'laptop-test-1'
TUPLE = dict(repositoryHead='', candidateCommit='b' * 40,
             shippingInputIdentity='c' * 64, releaseFingerprintId='d' * 64,
             toolingFingerprintId='e' * 64)


class CommandCenterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.native, self.public = base / 'native', base / 'public'
        self.native.mkdir()
        self.public.mkdir()
        self.native_head = self.git_init(self.native, 'native')
        self.public_head = self.git_init(self.public, 'public')
        self.now = datetime.now(timezone.utc).replace(microsecond=0)
        self.stamp = self.now.isoformat().replace('+00:00', 'Z')
        self.tuple = {**TUPLE, 'repositoryHead': self.native_head}
        self.authority_id = 'a' * 64
        self.authority = {**self.tuple, 'authorityId': self.authority_id,
                          'generatedAtUtc': self.stamp, 'status': 'BLOCKED',
                          'blockerClassification': 'EXACT_PROOF_NOT_OBSERVED',
                          'blocker': 'Laptop proof blocked', 'proofs': {'passing': 0, 'required': 2, 'runs': []},
                          'fullRelease': {'status': 'NOT_RUN_FOR_CURRENT_CANDIDATE'},
                          'validationEvidenceCurrent': False, 'fullReleasePassed': False,
                          'internalPromotionAllowed': False, 'publicPromotionAllowed': False,
                          'currentProofRunId': RUN}
        self.write('evidence/CURRENT-RELEASE-AUTHORITY.json', self.authority)
        self.write('evidence/CURRENT-STATUS.json', {**self.tuple, 'authorityId': self.authority_id,
                    'generatedAtUtc': self.stamp, 'status': 'BLOCKED', 'proofsPassed': 0,
                    'proofsRequired': 2, 'fullReleasePassed': False, 'internalPromotionAllowed': False})
        self.write('evidence/CURRENT-GATES.json', {**self.tuple, 'authorityId': self.authority_id,
                    'generatedAtUtc': self.stamp, 'status': 'BLOCKED'})
        self.write('evidence/FULLRELEASE-SUMMARY.json', {**self.tuple, 'candidateGitCommit': self.tuple['candidateCommit'],
                    'authorityId': self.authority_id, 'generatedAtUtc': self.stamp,
                    'status': 'NOT_RUN_FOR_CURRENT_CANDIDATE', 'fullReleasePassed': False})
        self.write('evidence/CURRENT-PROOF.json', {**self.tuple, 'authorityId': self.authority_id,
                    'authorityGeneratedAtUtc': self.stamp, 'runId': RUN, 'status': 'BLOCKED',
                    'progress': {'terminalReason': 'COMPLETED', 'lastMeaningfulProgressUtc': self.stamp},
                    'cleanup': {'runId': RUN, 'status': 'PASS', 'l1': {'status': 'OFF', 'observedUtc': self.stamp},
                                'l2': {'status': 'ABSENT', 'observedUtc': self.stamp}},
                    'terminalError': 'Cannot create a file when that file already exists.'})
        self.write(LEDGER, {'policyId': 'DF-TEST', 'activeRunId': None,
                    'limits': {'standard-token': 1, 'diagnostic': 1, 'laptop-proof': 1,
                               'desktop-proof': 1, 'fullrelease': 1},
                    'attempts': [
                        {'runId': 'standard-test-1', 'operation': 'standard-token', 'state': 'TERMINAL',
                         'exitCode': 0, 'classification': 'PASS_NATIVE_STANDARD_TOKEN'},
                        {'runId': 'diagnostic-test-1', 'operation': 'diagnostic', 'state': 'TERMINAL',
                         'exitCode': 0, 'classification': 'PASS_READY_FOR_PROOF_RESERVATION'},
                        {'runId': RUN, 'operation': 'laptop-proof', 'state': 'TERMINAL',
                         'exitCode': 2, 'classification': 'NATIVE_LAPTOP_PROOF_BLOCKED'}]})
        self.write('audit/agent-memory/attempts/DF-TEST/results/standard-test-1-standard-token-result.json',
                   {'runId': 'standard-test-1', 'candidateHead': self.native_head,
                    'classification': 'PASS_NATIVE_STANDARD_TOKEN', 'exitCode': 0, 'resultUtc': self.stamp})
        self.write(f'audit/agent-memory/attempts/DF-TEST/results/{RUN}-laptop-proof-host-safety.json',
                   {'observedUtc': self.stamp, 'startSafe': True, 'commitLimitGiB': 80,
                    'committedGiB': 40, 'expectedVmStartCostGiB': 16,
                    'projectedCommitHeadroomGiB': 24, 'commitHeadroomFloorGiB': 16})
        self.write(f'audit/agent-memory/attempts/DF-TEST/results/{RUN}-laptop-proof-session.json',
                   {'runId': RUN, 'firstTechnicalFailure': 'Cannot create a file when that file already exists.',
                    'observerTerminal': None, 'finishedUtc': self.stamp})

    def git_init(self, root, label):
        def git(*args):
            return subprocess.run(['git', '-C', str(root), *args], check=True,
                                  capture_output=True, text=True).stdout.strip()
        git('init', '-b', 'main')
        git('config', 'user.name', 'Fixture')
        git('config', 'user.email', 'fixture@example.invalid')
        (root / 'README.md').write_text(label + '\n', encoding='utf-8')
        git('add', 'README.md')
        git('commit', '-m', label)
        return git('rev-parse', 'HEAD')

    def write(self, relative, value):
        path = self.native / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding='utf-8')
        return path

    def snapshot(self):
        return center.build_snapshot(self.native, LEDGER, self.public,
                                     now=self.now, max_age=timedelta(minutes=30))

    def test_matching_current_sources_remain_non_promoting(self):
        result = self.snapshot()
        self.assertEqual(result['observerState'], 'CURRENT')
        self.assertEqual(result['native']['recordedStatus'], 'BLOCKED')
        self.assertEqual(result['native']['roles']['passed'], 0)
        self.assertEqual(result['native']['roles']['required'], 2)
        self.assertEqual(result['native']['charges']['laptop-proof']['remaining'], 0)
        self.assertEqual(result['native']['charges']['desktop-proof']['remaining'], 1)
        self.assertEqual(result['native']['qualification']['state'], 'RECORDED_PASS')
        self.assertEqual(result['native']['proof']['firstTechnicalFailure'],
                         'Cannot create a file when that file already exists.')
        self.assertEqual(result['native']['proof']['observerTerminal'], 'COMPLETED')
        self.assertEqual(result['native']['lab']['l2']['lastObserved'], 'ABSENT')
        self.assertNotEqual(result['nativeGit']['head'], result['publicGit']['head'])
        self.assertFalse(result['certificationCredit'])
        self.assertFalse(result['releaseEligibleClaim'])

    def test_missing_required_files_are_unknown(self):
        for name in ('CURRENT-STATUS.json', 'CURRENT-GATES.json', 'FULLRELEASE-SUMMARY.json'):
            (self.native / 'evidence' / name).unlink()
        result = self.snapshot()
        self.assertEqual(result['observerState'], 'UNKNOWN')
        self.assertEqual(result['sources']['status']['state'], 'UNKNOWN')
        self.assertEqual(result['native']['recordedStatus'], 'BLOCKED')
        self.assertFalse(result['releaseEligibleClaim'])

    def test_stale_generated_time_is_not_current(self):
        old = (self.now - timedelta(hours=2)).isoformat().replace('+00:00', 'Z')
        for name in ('CURRENT-RELEASE-AUTHORITY.json', 'CURRENT-STATUS.json',
                     'CURRENT-GATES.json', 'FULLRELEASE-SUMMARY.json'):
            path = self.native / 'evidence' / name
            value = json.loads(path.read_text())
            value['generatedAtUtc'] = old
            self.write('evidence/' + name, value)
        path = self.native / 'evidence/CURRENT-PROOF.json'
        value = json.loads(path.read_text())
        value['authorityGeneratedAtUtc'] = old
        self.write('evidence/CURRENT-PROOF.json', value)
        result = self.snapshot()
        self.assertEqual(result['observerState'], 'STALE')
        self.assertFalse(result['releaseEligibleClaim'])

    def test_conflicting_identity_and_timestamp_never_green(self):
        path = self.native / 'evidence/CURRENT-STATUS.json'
        value = json.loads(path.read_text())
        value['authorityId'] = 'f' * 64
        value['generatedAtUtc'] = (self.now + timedelta(minutes=10)).isoformat().replace('+00:00', 'Z')
        self.write('evidence/CURRENT-STATUS.json', value)
        result = self.snapshot()
        self.assertEqual(result['observerState'], 'CONFLICT')
        self.assertIn('status', result['conflicts'])
        self.assertFalse(result['releaseEligibleClaim'])

    def test_ledger_active_mismatch_is_conflict(self):
        value = json.loads((self.native / LEDGER).read_text())
        value['activeRunId'] = 'not-reserved'
        self.write(LEDGER, value)
        result = self.snapshot()
        self.assertEqual(result['observerState'], 'CONFLICT')
        self.assertEqual(result['sources']['ledger']['state'], 'CONFLICT')

    def test_malformed_attempt_id_is_conflict_not_a_crash(self):
        value = json.loads((self.native / LEDGER).read_text())
        value['attempts'][0]['runId'] = ['invalid']
        self.write(LEDGER, value)
        result = self.snapshot()
        self.assertEqual(result['observerState'], 'CONFLICT')
        self.assertEqual(result['sources']['ledger']['state'], 'CONFLICT')

    def test_unknown_attempt_operation_cannot_disappear_from_counters(self):
        value = json.loads((self.native / LEDGER).read_text())
        value['attempts'][0]['operation'] = 'unlisted-charge'
        self.write(LEDGER, value)
        result = self.snapshot()
        self.assertEqual(result['observerState'], 'CONFLICT')
        self.assertEqual(result['sources']['ledger']['state'], 'CONFLICT')

    def test_receipt_staleness_is_visible_in_qualification(self):
        path = self.native / 'audit/agent-memory/attempts/DF-TEST/results/standard-test-1-standard-token-result.json'
        value = json.loads(path.read_text())
        value['resultUtc'] = (self.now - timedelta(hours=2)).isoformat().replace('+00:00', 'Z')
        self.write(str(path.relative_to(self.native)), value)
        result = self.snapshot()
        self.assertEqual(result['native']['qualification']['state'], 'STALE')
        self.assertEqual(result['native']['qualification']['recordedClassification'], 'PASS_NATIVE_STANDARD_TOKEN')

    def test_mismatched_session_cannot_supply_first_failure(self):
        path = self.native / f'audit/agent-memory/attempts/DF-TEST/results/{RUN}-laptop-proof-session.json'
        value = json.loads(path.read_text())
        value['runId'] = 'other-run'
        value['firstTechnicalFailure'] = 'wrong run'
        self.write(str(path.relative_to(self.native)), value)
        result = self.snapshot()
        self.assertEqual(result['sources']['proofSession']['state'], 'CONFLICT')
        self.assertEqual(result['native']['proof']['firstTechnicalFailure'], 'UNKNOWN')
        self.assertEqual(result['native']['proof']['proofTerminalError'],
                         'Cannot create a file when that file already exists.')

    def test_proof_session_uses_bound_operation(self):
        ledger = json.loads((self.native / LEDGER).read_text())
        ledger['attempts'][-1]['operation'] = 'desktop-proof'
        self.write(LEDGER, ledger)
        old_path = self.native / f'audit/agent-memory/attempts/DF-TEST/results/{RUN}-laptop-proof-session.json'
        old_path.rename(old_path.with_name(f'{RUN}-desktop-proof-session.json'))
        result = self.snapshot()
        self.assertEqual(result['native']['proof']['firstTechnicalFailure'],
                         'Cannot create a file when that file already exists.')

    def test_authority_proof_run_must_match_ledger(self):
        self.authority['currentProofRunId'] = 'not-in-ledger'
        self.write('evidence/CURRENT-RELEASE-AUTHORITY.json', self.authority)
        result = self.snapshot()
        self.assertEqual(result['observerState'], 'CONFLICT')
        self.assertIn('proofRun', result['conflicts'])

    def test_outside_ledger_path_fails_closed(self):
        outside = self.native.parent / 'outside' / 'results'
        outside.mkdir(parents=True)
        (outside / 'outside-host-safety.json').write_text('{}', encoding='utf-8')
        result = center.build_snapshot(self.native, '../outside/ledger.json', self.public,
                                       now=self.now, max_age=timedelta(minutes=30))
        self.assertEqual(result['observerState'], 'CONFLICT')
        self.assertEqual(result['sources']['ledger']['state'], 'CONFLICT')

    def test_untimed_host_sample_and_missing_operator_are_unknown(self):
        path = self.native / f'audit/agent-memory/attempts/DF-TEST/results/{RUN}-laptop-proof-host-safety.json'
        value = json.loads(path.read_text())
        value.pop('observedUtc')
        self.write(str(path.relative_to(self.native)), value)
        result = self.snapshot()
        self.assertEqual(result['native']['hostSafety']['state'], 'UNKNOWN')
        self.assertEqual(result['native']['hostSafety']['timestampSource'], 'FILE_MTIME_ONLY')
        self.assertEqual(result['native']['operator']['model'], 'UNKNOWN')
        self.assertEqual(result['native']['operator']['root'], 'UNKNOWN')

    def test_snapshot_does_not_change_any_source_bytes(self):
        before = {p.relative_to(self.native): p.read_bytes() for p in self.native.rglob('*') if p.is_file()}
        self.snapshot()
        after = {p.relative_to(self.native): p.read_bytes() for p in self.native.rglob('*') if p.is_file()}
        self.assertEqual(before, after)

    def test_html_escapes_native_text(self):
        snapshot = self.snapshot()
        snapshot['native']['blocker'] = '<script>bad()</script>'
        page = center.render_html(snapshot)
        self.assertNotIn('<script>bad()</script>', page)
        self.assertIn('&lt;script&gt;', page)


if __name__ == '__main__':
    unittest.main()
