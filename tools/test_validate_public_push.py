"""VM-free outgoing-public-push guard fixtures."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name('validate_public_push.py')


class PublicPushTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.commit('README.md', 'initial\n')
        self.base = self.git('rev-parse', 'HEAD').stdout.strip()

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.root), *args],
                              check=True, capture_output=True, text=True)

    def commit(self, name, content):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding='utf-8')
        self.git('add', '--', name)
        self.git('commit', '-m', f'fixture {name}')

    def check(self):
        return subprocess.run([sys.executable, str(SCRIPT), '--repo', str(self.root),
                               '--base', self.base, '--head', 'HEAD'],
                              capture_output=True, text=True)

    def test_public_source_and_tracked_audit_script_pass(self):
        self.commit('source/app/example.py', 'print("safe")\n')
        self.commit('audit/run-exact-candidate-proof.ps1', 'Write-Host safe\n')
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('2 outgoing commits', result.stdout)

    def test_private_history_is_rejected_even_after_later_deletion(self):
        self.commit('audit/runs/private.json', '{}\n')
        self.git('rm', '--', 'audit/runs/private.json')
        self.git('commit', '-m', 'remove private evidence')
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('audit/runs/private.json', result.stderr)
        self.assertEqual(self.git('status', '--porcelain').stdout, '')

    def test_generated_state_and_signing_material_are_rejected(self):
        self.commit('source/.test-runtime/config.json', '{}\n')
        self.commit('source/cert.pfx', 'not a real cert\n')
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('.test-runtime', result.stderr)
        self.assertIn('.pfx', result.stderr)

    def test_credential_content_is_rejected_without_echoing_value(self):
        fake = 'github_pat_' + 'A' * 32
        self.commit('README.md', 'temporary fixture ' + fake + '\n')
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SECRET_PATTERN', result.stderr)
        self.assertNotIn(fake, result.stderr + result.stdout)

    def test_quoted_password_assignment_is_rejected(self):
        field = 'pass' + 'word'
        fake = 'FixtureValue1234567890'
        self.commit('source/settings.py', field + ' = "' + fake + '"\n')
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SECRET_PATTERN', result.stderr)
        self.assertNotIn(fake, result.stderr + result.stdout)

    def test_private_key_content_is_rejected(self):
        marker = '-----BEGIN ' + 'PRIVATE KEY-----'
        self.commit('source/example.txt', marker + '\nfixture\n')
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SECRET_PATTERN', result.stderr)
        self.assertNotIn(marker, result.stderr + result.stdout)

    def test_opt_in_hook_rejects_outgoing_evidence(self):
        remote = self.root.parent / (self.root.name + '-remote.git')
        self.addCleanup(lambda: shutil.rmtree(remote, ignore_errors=True))
        subprocess.run(['git', 'init', '--bare', '-b', 'main', str(remote)],
                       check=True, capture_output=True)
        self.git('remote', 'add', 'origin', str(remote))
        self.git('push', '-u', 'origin', 'main')
        (self.root / 'tools').mkdir()
        (self.root / '.githooks').mkdir()
        shutil.copyfile(SCRIPT, self.root / 'tools/validate_public_push.py')
        hook = self.root / '.githooks/pre-push'
        shutil.copyfile(SCRIPT.parents[1] / '.githooks/pre-push', hook)
        os.chmod(hook, 0o755)
        self.git('config', 'core.hooksPath', '.githooks')
        self.commit('audit/run-state.json', '{}\n')
        result = subprocess.run(['git', '-C', str(self.root), 'push', 'origin', 'main'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('PUBLIC_PUSH_BLOCKED', result.stderr)
        self.assertNotEqual(self.git('rev-parse', 'HEAD').stdout.strip(), self.base)
        self.assertEqual(subprocess.run(['git', '--git-dir', str(remote), 'rev-parse', 'main'],
                                        check=True, capture_output=True, text=True).stdout.strip(), self.base)

if __name__ == '__main__':
    unittest.main()
