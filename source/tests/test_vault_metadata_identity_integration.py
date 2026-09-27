import importlib.util
from importlib.machinery import SourceFileLoader
import pytest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _broker():
    pytest.importorskip("pwd", reason="Vault broker is POSIX-only")
    spec = importlib.util.spec_from_loader("vault_broker", SourceFileLoader("vault_broker", str(ROOT / "linux" / "devfleet-vault-broker")))
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_broker_delegates_descriptor_safe_identity_to_installed_helper(monkeypatch, tmp_path):
    broker = _broker()
    calls = []

    class Result:
        returncode = 0

    monkeypatch.setattr(broker.subprocess, "run", lambda command, **kwargs: calls.append((command, kwargs)) or Result())
    assert broker._restored_identity_matches(tmp_path, "demo", "12345678-1234-1234-1234-123456789012")
    command, kwargs = calls[-1]
    assert command == ["python3", "-I", "/opt/devfleet/devfleet/metadata_io.py", "--identity", str(tmp_path), "demo", "12345678-1234-1234-1234-123456789012"]
    assert kwargs["stdin"] is broker.subprocess.DEVNULL
    assert kwargs["stdout"] is broker.subprocess.DEVNULL
    assert kwargs["stderr"] is broker.subprocess.DEVNULL


def test_broker_binds_transfer_identity_arguments(monkeypatch, tmp_path):
    broker = _broker()
    seen = []
    monkeypatch.setattr(broker.subprocess, "run", lambda command, **kwargs: seen.append(command) or type("R", (), {"returncode": 0})())
    assert broker._restored_identity_matches(tmp_path, "demo", "12345678-1234-1234-1234-123456789012", "12345678-1234-1234-1234-123456789013", "failover")
    assert seen[0][-2:] == ["12345678-1234-1234-1234-123456789013", "failover"]


def test_broker_rejects_standalone_canonical_action(monkeypatch):
    broker = _broker()
    with pytest.raises(broker.ProtocolError):
        broker._parse_request({"action": "restore-canonical", "project": "demo", "project_id": "12345678-1234-1234-1234-123456789012"})
    assert "restore-canonical" not in (ROOT / "linux" / "devfleet-vault-request").read_text(encoding="utf-8")


def test_broker_attempts_quarantine_on_invalid_recovered_identity(monkeypatch, tmp_path):
    broker = _broker()
    broker.WORKSPACES = tmp_path
    # Supply the external configuration precondition; never read real credentials.
    monkeypatch.setattr(broker.os, "access", lambda path, mode: path == "/etc/devfleet/restic.env")
    target = tmp_path / "demo-recovered-20260916-123456-deadbeef"
    target.mkdir()
    monkeypatch.setattr(broker, "_run_child", lambda *_args, **_kwargs: type("R", (), {"returncode": 0, "stdout": str(target) + "\n"})())
    monkeypatch.setattr(broker, "_restored_identity_matches", lambda *_args: False)
    quarantined = []
    monkeypatch.setattr(broker, "_quarantine_invalid_copy", lambda path, project: quarantined.append((path, project)) or True)
    result = broker._run_fixed_operation("restore-copy", "demo", "12345678-1234-1234-1234-123456789012")
    assert result["ok"] is False and quarantined == [(target, "demo")]


def test_restore_shell_uses_metadata_io_identity_cli():
    script = (ROOT / "linux" / "devfleet-restore-project").read_text(encoding="utf-8")
    assert "python3 -I /opt/devfleet/devfleet/metadata_io.py --identity" in script
    assert "jq -e --arg slug" not in script


def test_restore_shell_quarantines_unmarked_recovered_target_after_move():
    script = (ROOT / "linux" / "devfleet-restore-project").read_text(encoding="utf-8")
    assert 'if [[ "$mode" != --canonical ]] && ! workspace_identity_matches "$target"' in script
    assert 'vault-recovery-invalid-$stamp-$project' in script
    assert 'Recovered workspace identity failed; the unmarked copy was quarantined.' in script
