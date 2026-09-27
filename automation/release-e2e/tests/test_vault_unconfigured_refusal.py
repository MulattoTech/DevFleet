"""Negative destructive fixture stays distinct from configured Vault success."""
from dataclasses import replace
import importlib.util
from pathlib import Path
import runpy

import pytest

ROOT = Path(__file__).resolve().parents[3]
runpy.run_path(str(ROOT / "source/tests/conftest.py"))
from devfleet import projects

spec = importlib.util.spec_from_file_location("vault_broker_test_helpers", ROOT / "source/tests/test_v123_vault_broker.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)


def test_unconfigured_broker_refuses_without_starting_backup(monkeypatch):
    broker = helpers.load_broker_module(monkeypatch)
    monkeypatch.setattr(broker.os, "access", lambda *args: False)
    monkeypatch.setattr(broker, "_run_child", lambda *args, **kwargs: pytest.fail("Unconfigured broker started backup"))
    result = broker._run_fixed_operation("backup", "", "")
    assert result["ok"] is False
    assert result["exit_code"] == 3


def test_actual_unconfigured_delete_preserves_workspace_and_sentinel(monkeypatch, tmp_path):
    settings = replace(projects.SETTINGS, workspaces=tmp_path / "workspaces", runtime_root=tmp_path / "runtime",
                       node_name="test-node", deployment_id="deployment-123", allow_permanent_delete=True)
    settings.workspaces.mkdir()
    monkeypatch.setattr(projects, "SETTINGS", settings)
    project = helpers._owned_container_project(settings.workspaces, "unconfigured-delete")
    sentinel = project / "release-sentinel.txt"
    sentinel.write_bytes(b"must remain recoverable\n")
    identity = projects.load_authoritative_project_identity_for_mutation(project)["project_id"]
    # Only the external container/CLI boundary is replaced. The real destroy,
    # safety backup, archive, metadata and authenticated-request path execute.
    monkeypatch.setattr(projects, "stop_project", lambda slug: "stopped")
    monkeypatch.setattr(projects, "running", lambda path: False)
    calls = []
    def absent_configuration(command, **kwargs):
        calls.append(command)
        assert command == ["/usr/local/bin/devfleet-vault-request", "backup"]
        raise RuntimeError("Vault backup configuration is not readable.")
    monkeypatch.setattr(projects, "run", absent_configuration)
    with pytest.raises(RuntimeError, match="Vault backup configuration is not readable"):
        projects.destroy_project("unconfigured-delete", "unconfigured-delete", "DESTROY unconfigured-delete")
    assert len(calls) == 1
    assert sentinel.read_bytes() == b"must remain recoverable\n"
    assert projects.load_authoritative_project_identity_for_mutation(project)["project_id"] == identity
    assert not list((settings.runtime_root / "recovery-tombstones").glob("*.json"))
