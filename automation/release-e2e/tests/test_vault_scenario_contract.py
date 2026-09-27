"""Offline regression of the real release scenario against current candidate inputs."""
import importlib.util
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
EXECUTOR = ROOT / "automation/release-e2e/modules/executors/Invoke-ProductLifecycleScenario.py"
spec = importlib.util.spec_from_file_location("vault_scenario_contract", EXECUTOR)
scenario_module = importlib.util.module_from_spec(spec)
if sys.platform == "win32":
    # Import compatibility only, scoped to this POSIX scenario module. Leaving a
    # fake pwd in sys.modules breaks tarfile's later platform detection.
    with patch.dict(sys.modules, {"pwd": types.ModuleType("pwd")}):
        spec.loader.exec_module(scenario_module)
else:
    spec.loader.exec_module(scenario_module)


class ProjectStorageBoundary:
    """Only the external installed project/Vault boundary; scenario code is real."""
    def __init__(self, workspaces):
        self.SETTINGS = types.SimpleNamespace(workspaces=workspaces, runtime_root=workspaces.parent / 'runtime')
        self.snapshot = None
        self.backup_error = None
        self.restore_bytes = None

    def create_project(self, *, slug, **options):
        (self.SETTINGS.workspaces / slug).mkdir()
        return {"managed_by": "devfleet", "slug": slug, "project_id": "80e78b55-7ab6-457e-98c9-341b08164592"}

    def backup_project(self, slug):
        if self.backup_error:
            raise RuntimeError(self.backup_error)
        self.snapshot = (self.SETTINGS.workspaces / slug / "release-sentinel.txt").read_bytes()
        return json.dumps({"ok": True, "vault_upload_status": "verified", "durability_level": "vault"})

    def restore_from_vault(self, slug):
        target = self.SETTINGS.workspaces / (slug + "-recovered")
        target.mkdir()
        (target / "release-sentinel.txt").write_bytes(self.snapshot if self.restore_bytes is None else self.restore_bytes)
        return str(target)

    def start_project(self, slug):
        pass

    def inspect_runtime(self, slug):
        return {"running": True}

    def destroy_project(self, slug, confirm_slug, confirm_phrase):
        if self.backup_error:
            raise RuntimeError(self.backup_error)
        self.backup_project(slug)
        tombstones = self.SETTINGS.runtime_root / "recovery-tombstones"
        tombstones.mkdir(parents=True)
        (self.SETTINGS.runtime_root / "workspace-backups" / "test-backup").mkdir(parents=True)
        (tombstones / (slug + "-test.json")).write_text(json.dumps({"backup_id": "test-backup", "backup_sha256": "a" * 64}), encoding="utf-8")
        shutil.rmtree(self.SETTINGS.workspaces / slug)
        return "deleted with verified safety backup"

    def _vault_request(self, action, slug, project_id, *, timeout):
        if action != "restore-copy":
            raise AssertionError("Unexpected Vault operation")
        return {"ok": True, "action": action, "project": slug, "project_id": project_id, "target": self.restore_from_vault(slug)}

    def _validate_recovered_vault_copy(self, slug, identity, target):
        return target


class VaultScenarioContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="devfleet-vault-contract-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.installed = root / "bin"
        self.installed.mkdir()
        for name in ("devfleet-backup", "devfleet-restore-project", "devfleet-vault-request"):
            shutil.copyfile(ROOT / "source/linux" / name, self.installed / name)
        self.config = root / "config.json"
        self.config.write_text(json.dumps({"repository": "rest:http://100.64.0.4:8000/test-primary"}), encoding="utf-8")
        for name, value in (("VAULT_INSTALLED_BIN", self.installed), ("VAULT_STATUS_CONFIG", self.config)):
            replacement = patch.object(scenario_module, name, value, create=True)
            replacement.start()
            self.addCleanup(replacement.stop)
        self.scenario = scenario_module.Scenario.__new__(scenario_module.Scenario)
        self.scenario.source_root = ROOT / "source"
        self.scenario.run_id = "e2e-vault-contract-local"
        self.scenario.suffix = "local-contract"
        self.scenario.root = root
        self.scenario.slugs = []
        workspaces = root / "workspaces"
        workspaces.mkdir()
        self.scenario.projects = ProjectStorageBoundary(workspaces)
        # This scenario must never substitute a local restic repository for the
        # installed authenticated broker/product path.
        direct = patch.object(scenario_module.subprocess, "run", side_effect=AssertionError("unrelated direct restic invocation"))
        direct.start()
        self.addCleanup(direct.stop)

    def test_shipped_sourced_entrypoint_reaches_authenticated_backup_restore(self):
        evidence = self.scenario.vault()
        expected = hashlib.sha256(b"vault-e2e-vault-contract-local\n").hexdigest()
        self.assertEqual(evidence["sentinelSha256"], expected)
        self.assertEqual(evidence["liveRemoteVault"], "PASS")
        self.assertEqual(evidence["resticBackup"], "PASS")
        self.assertEqual(evidence["resticRestore"], "PASS")

    def test_installed_entrypoint_mismatch_refuses_before_backup(self):
        (self.installed / "devfleet-backup").write_text("exit 0\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "entrypoint differs"):
            self.scenario.vault()
        self.assertIsNone(self.scenario.projects.snapshot)

    def test_unconfigured_positive_fixture_refuses_before_project_creation(self):
        self.config.unlink()
        with self.assertRaisesRegex(RuntimeError, "configured authenticated Vault"):
            self.scenario.vault()
        self.assertEqual(list(self.scenario.projects.SETTINGS.workspaces.iterdir()), [])

    def test_non_tailnet_repository_is_not_a_positive_fixture(self):
        self.config.write_text(json.dumps({"repository": "rest:http://192.168.1.8:8000/test"}), encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "Tailscale"):
            self.scenario.vault()

    def test_unrelated_or_empty_successful_restore_is_rejected(self):
        self.scenario.projects.restore_bytes = b""
        with self.assertRaisesRegex(RuntimeError, "sentinel"):
            self.scenario.vault()

    def test_authentication_failure_is_not_relabelled_as_deferred_pass(self):
        self.scenario.projects.backup_error = "authenticated Vault backup refused"
        with self.assertRaisesRegex(RuntimeError, "authenticated Vault backup refused"):
            self.scenario.vault()

    def test_positive_configuration_uses_actual_backup_roots_and_identity(self):
        installed = {"workspaces": "/home/devrunner/workspaces", "quarantine": "/home/devrunner/.devfleet-quarantine", "node_name": "devfleet-primary", "deployment_id": "80e78b55-7ab6-457e-98c9-341b08164592"}
        config = scenario_module.scenario_configuration(installed, self.scenario.root, "test", "permanent-delete")
        self.assertEqual(config["workspaces"], "/home/devrunner/workspaces")
        self.assertEqual(config["quarantine"], "/home/devrunner/.devfleet-quarantine")
        self.assertEqual(config["deployment_id"], installed["deployment_id"])

    def test_uncovered_positive_configuration_is_rejected(self):
        installed = {"workspaces": "/tmp/uncovered", "quarantine": "/home/devrunner/.devfleet-quarantine"}
        with self.assertRaisesRegex(RuntimeError, "backup roots"):
            scenario_module.scenario_configuration(installed, self.scenario.root, "test", "permanent-delete")

    def test_permanent_delete_requires_actual_sentinel_recovery_from_vault(self):
        self.scenario.projects.restore_bytes = b"unrelated data"
        with self.assertRaisesRegex(RuntimeError, "sentinel"):
            self.scenario.permanent_delete()


if __name__ == "__main__":
    unittest.main()


def test_scenario_import_does_not_leak_incomplete_pwd_module():
    loaded=sys.modules.get("pwd")
    assert loaded is None or callable(getattr(loaded,"getpwuid",None)), "Scenario import leaked a fake pwd module into unrelated tarfile tests"
