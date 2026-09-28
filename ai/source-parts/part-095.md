# DevFleet source part 095

Full-source UTF-8 byte interval [4371000, 4417500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 3c5c0ae4be8641f3018c207620c58c3af08479f9e12cca893321cd16fa4be2b1

<!-- BEGIN SOURCE SLICE -->
t(json.dumps({"image": "alpine:3.20", "runArgs": [argument]}), encoding="utf-8")
    findings = analyze_project(project, profile, force=True)
    assert has_blockers(findings)
    assert "devcontainer.run-args" in {item["code"] for item in findings} or "devcontainer.run-args-dangerous" in {item["code"] for item in findings}


def test_devcontainer_jsonc_known_good_and_features_fail_closed(tmp_path: Path) -> None:
    project = tmp_path / "devcontainer"
    (project / ".devcontainer").mkdir(parents=True)
    config = """{
      // JSONC comments are part of the Dev Container format.
      "name": "safe",
      "image": "alpine:3.20",
      "remoteUser": "nobody",
    }
    """
    path = project / ".devcontainer/devcontainer.json"
    path.write_text(config, encoding="utf-8")
    findings = analyze_project(project, "strict", force=True)
    assert "devcontainer.json.invalid" not in {item["code"] for item in findings}
    assert not has_blockers(findings)
    path.write_text('{"image":"alpine:3.20","features":{"ghcr.io/devcontainers/features/node:1":{}}}', encoding="utf-8")
    findings = analyze_project(project, "strict", force=True)
    assert "devcontainer.features-unsupported" in {item["code"] for item in findings}


def test_analyzer_cache_invalidates_when_only_transitive_compose_file_changes(tmp_path: Path) -> None:
    project = _compose_project(tmp_path, """services:
  app:
    extends: {file: evil.yml, service: inherited}
""")
    inherited = project / "evil.yml"
    inherited.write_text("services:\n  inherited:\n    image: alpine:3.20\n", encoding="utf-8")
    analyze_project(project, "strict", force=True)
    cache = project / ".devfleet/runtime/analyzer-cache.json"
    first = cache.read_text(encoding="utf-8")
    inherited.write_text("services:\n  inherited:\n    privileged: true\n", encoding="utf-8")
    analyze_project(project, "strict")
    second = cache.read_text(encoding="utf-8")
    assert first != second


CONTAINER_ID = "a" * 64
FOREIGN_ID = "b" * 64
PROJECT_ID = "12345678-1234-1234-1234-123456789abc"


def _owned_project(tmp_path: Path) -> None:
    project = tmp_path / "owned-app"
    (project / ".devfleet").mkdir(parents=True)
    (project / ".devfleet/project.json").write_text(json.dumps({
        "managed_by": "devfleet", "project_id": PROJECT_ID, "slug": "owned-app", "runtime_provider": "docker-compose",
        "runtime_id": "df_owned_app", "deployment_id": "deployment-123", "host_id": "test-node",
    }), encoding="utf-8")


def _owned_labels() -> dict[str, str]:
    return {
        "io.devfleet.managed-by": "devfleet", "io.devfleet.project-id": PROJECT_ID, "io.devfleet.project-slug": "owned-app",
        "io.devfleet.runtime-id": "df_owned_app", "io.devfleet.deployment-id": "deployment-123", "io.devfleet.host-id": "test-node",
        "com.docker.compose.project": "df_owned_app", "com.docker.compose.service": "app",
    }


def _inspect(container_id: str, labels: dict[str, str], name: str) -> dict:
    return {"Id": container_id, "Name": f"/{name}", "Config": {"Labels": labels}, "Secret": "only-for-authorized-read"}


def test_container_reads_filter_foreign_and_authorize_inspect_logs(monkeypatch, tmp_path: Path) -> None:
    _owned_project(tmp_path)
    monkeypatch.setattr(containers, "SETTINGS", replace(SETTINGS, workspaces=tmp_path, node_name="test-node", deployment_id="deployment-123"))
    owned = _inspect(CONTAINER_ID, _owned_labels(), "owned-app")
    foreign = _inspect(FOREIGN_ID, {"io.devfleet.managed-by": "other"}, "foreign")
    calls: list[list[str]] = []

    def fake_run(args, **_kwargs):
        calls.append(list(args))
        if args[:2] == ["docker", "ps"]:
            return SimpleNamespace(returncode=0, stdout="\n".join(json.dumps(x) for x in [
                {"ID": CONTAINER_ID, "Names": "owned-app", "Image": "safe", "State": "running"},
                {"ID": FOREIGN_ID, "Names": "foreign", "Image": "evil", "State": "running"},
            ]), stderr="")
        if args[:2] == ["docker", "stats"]:
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if args[:2] == ["docker", "inspect"]:
            value = owned if args[-1] in {CONTAINER_ID, "owned-app"} else foreign
            return SimpleNamespace(returncode=0, stdout=json.dumps([value]), stderr="")
        if args[:2] == ["docker", "logs"]:
            return SimpleNamespace(returncode=0, stdout="owned log", stderr="")
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(containers, "run", fake_run)
    listed = containers.list_containers()
    assert [item["id"] for item in listed] == [CONTAINER_ID]
    assert containers.inspect_container("owned-app")["Id"] == CONTAINER_ID
    assert containers.container_logs("owned-app") == "owned log"
    with pytest.raises(ValueError, match="ownership"):
        containers.inspect_container("foreign")
    with pytest.raises(ValueError, match="ownership"):
        containers.container_logs("foreign")
    assert not any(call[:2] == ["docker", "logs"] and call[-1] == FOREIGN_ID for call in calls)


def test_container_same_name_replacement_and_partial_labels_fail_closed(monkeypatch, tmp_path: Path) -> None:
    _owned_project(tmp_path)
    monkeypatch.setattr(containers, "SETTINGS", replace(SETTINGS, workspaces=tmp_path, node_name="test-node", deployment_id="deployment-123"))
    calls = {"inspect": 0}

    def fake_run(args, **_kwargs):
        if args[:2] == ["docker", "inspect"]:
            calls["inspect"] += 1
            value = _inspect(CONTAINER_ID, _owned_labels(), "same-name") if calls["inspect"] == 1 else _inspect(FOREIGN_ID, {"io.devfleet.managed-by": "other"}, "same-name")
            return SimpleNamespace(returncode=0, stdout=json.dumps([value]), stderr="")
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(containers, "run", fake_run)
    with pytest.raises(ValueError, match="ownership"):
        containers.inspect_container("same-name")


def test_rootless_endpoint_preserves_explicit_two_user_socket(monkeypatch) -> None:
    settings = replace(SETTINGS, docker_mode="rootless", docker_host="unix:///run/user/1000/docker.sock", docker_owner_uid=1000)
    monkeypatch.setattr(core, "SETTINGS", settings)
    monkeypatch.setattr(core.os, "lstat", lambda _path: SimpleNamespace(st_mode=stat.S_IFSOCK, st_uid=1000))
    captured = {}

    def fake_subprocess(_cmd, **kwargs):
        captured.update(kwargs)
        return SimpleNamespace(returncode=0, stdout="ok", stderr="")

    monkeypatch.setattr(core.subprocess, "run", fake_subprocess)
    monkeypatch.setenv("DOCKER_HOST", "unix:///run/user/1000/docker.sock")
    core.run(["docker", "info"], check=False)
    assert captured["env"]["DOCKER_HOST"] == "unix:///run/user/1000/docker.sock"


@pytest.mark.parametrize("host", ["unix:///run/user/4242/docker.sock", "tcp://127.0.0.1:2375", "", "unix:///run/user/1000/not-docker.sock"])
def test_rootless_endpoint_rejects_wrong_identity_or_shape(monkeypatch, host: str) -> None:
    settings = replace(SETTINGS, docker_mode="rootless", docker_host=host, docker_owner_uid=1000)
    monkeypatch.setattr(core, "SETTINGS", settings)
    monkeypatch.setattr(core.os, "lstat", lambda _path: SimpleNamespace(st_mode=stat.S_IFSOCK, st_uid=1000))
    with pytest.raises(RuntimeError):
        core._validate_rootless_docker_host(host)


def test_rootless_deployment_contract_is_explicit() -> None:
    unit = Path("source/app/systemd/devfleet.service").read_text(encoding="utf-8")
    core_text = Path("source/app/devfleet/core.py").read_text(encoding="utf-8")
    assert "SupplementaryGroups=devrunner" in unit
    assert "Environment=DOCKER_HOST=unix:///run/user/__DEVRUNNER_UID__/docker.sock" in unit
    assert "os.getuid" not in core_text
    assert "_validate_rootless_docker_host" in core_text


def test_rootless_docker_acl_is_reapplied_after_each_service_start() -> None:
    bootstrap = Path("source/linux/bootstrap-compute.sh").read_text(encoding="utf-8")
    drop_in = "/home/devrunner/.config/systemd/user/docker.service.d/devfleet-control-acl.conf"
    daemon_reload = (
        "sudo -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user daemon-reload"
    )
    enable_docker = (
        "sudo -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user enable --now docker"
    )

    assert drop_in in bootstrap
    assert "ExecStartPost=/usr/bin/setfacl -m u:devfleet-control:rx %t" in bootstrap
    assert "ExecStartPost=/usr/bin/setfacl -m u:devfleet-control:rw %t/docker.sock" in bootstrap
    assert daemon_reload in bootstrap
    assert bootstrap.index(daemon_reload) < bootstrap.index(enable_docker)


def test_credential_comparison_count_is_constant(monkeypatch) -> None:
    monkeypatch.setattr(auth, "SETTINGS", replace(SETTINGS, admin_user="alice", admin_password="secret"))
    original = auth.hmac.compare_digest
    counts: list[int] = []
    calls = []

    def counted(left, right):
        calls.append((left, right))
        return original(left, right)

    monkeypatch.setattr(auth.hmac, "compare_digest", counted)
    for user, password in [("wrong", "wrong"), ("alice", "wrong"), ("wrong", "secret"), ("alice", "secret"), ("", "")]:
        calls.clear()
        auth.valid_credentials(user, password, source="red-blue-test")
        counts.append(len(calls))
    assert counts == [2, 2, 2, 2, 2]

```


## FILE: source/tests/test_hardening7_boundaries.py

SHA256: c76ba7108747796dc74b7ff6c4d026d5be2672dd2b4e99d14fc6f0f49bcbd8bb | Bytes: 8255 | Git mode: 100644

```
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json
import re

import yaml


ROOT = Path(__file__).parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_linux_bootstrap_has_stdin_only_secret_transport_and_separated_identities():
    bootstrap = read("linux/bootstrap-compute.sh")
    input_helper = read("linux/bootstrap-input.sh")
    service = read("app/systemd/devfleet.service")
    backup = read("app/systemd/devfleet-backup.service")
    assert "--secrets-stdin)" in bootstrap
    assert "devfleet_capture_json_stdin" in bootstrap
    assert "timeout --foreground --kill-after=5s" in input_helper
    assert "Refusing legacy plaintext node-secrets.json input" in bootstrap
    assert 'SECRETS_SOURCE="${PAYLOAD}/node-secrets.json"' not in bootstrap
    assert "User=devfleet-control" in service
    assert "Group=devfleet-control" in service
    assert "User=devfleet-backup" in backup
    assert "Group=devfleet-backup" in backup
    assert "chown root:devfleet-control /etc/devfleet/secrets.env" in bootstrap
    assert "chmod 0640 /etc/devfleet/secrets.env" in bootstrap
    assert "NOPASSWD:ALL" not in bootstrap
    assert "sudoers.d/devfleet-devrunner" in bootstrap


def test_windows_provisioning_never_writes_node_secret_file_or_passes_secret_argv():
    provision = read("windows/02-Provision-ComputeNode.ps1")
    common = read("windows/DevFleet.Common.psm1")
    assert "node-secrets.json" not in provision
    assert "New-DevFleetBootstrapBoundary" in provision
    assert "--secrets-stdin" in common
    assert ".extractionCommand" in provision
    assert ".bootstrapCommand" in provision
    assert "-StandardInputText" in provision
    assert "RedirectStandardInput" in common
    assert "-p$password" not in common
    assert "DFENV001" in common
    assert "AesGcm" in common


def test_live_vm_identity_is_guest_bound_and_stopped_operations_fail_closed():
    agent = read("windows/DevFleet-HostAgent.ps1")
    assert "project-runtime.json" in agent
    for field in ("managed_by", "project_id", "slug", "runtime_id", "host_id", "provisioning_attempt_id"):
        assert f"runtimeMeta.{field}" in agent
    assert "AllowStoppedTransition" in agent
    assert "Operation -eq 'start'" in agent
    assert "groups: [docker, sudo]" not in read("cloud-init/compute.yaml")
    assert "NOPASSWD:ALL" not in agent


def test_cleanup_is_postcondition_and_transaction_bound():
    lifecycle = read("../installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs")
    services = read("../installer-source/DevFleet.Setup/Services/InstallerServices.cs")
    assert "InstallationGeneration" in lifecycle
    assert "PayloadFingerprint" in lifecycle
    assert "Owned registry entry remains after cleanup" in lifecycle
    assert "Owned shortcut remains after cleanup" in lifecycle
    assert "Owned file remains after cleanup" in services
    assert "Owned scheduled task remains after cleanup" in lifecycle
    assert "cleanup-history" in lifecycle


def test_uac_does_not_stage_before_elevation_and_vscode_is_trusted():
    main = read("../installer-source/DevFleet.Setup/MainWindow.xaml.cs")
    app = read("../installer-source/DevFleet.Setup/App.xaml.cs")
    lifecycle = read("../installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs")
    assert "elevation-check" not in main
    assert "TrustedExecutableResolver.VsCodePath()" in app
    assert "UseShellExecute = false" in app
    assert "ArgumentList.Add" in app
    assert "Microsoft VS Code" in lifecycle


def test_safety_policy_restore_journal_compose_reanalysis_and_frontend_terminal_states():
    projects = read("app/devfleet/projects.py")
    restore = read("app/devfleet/workspace_archives.py")
    operations = read("app/devfleet/operations.py")
    frontend = read("app/static/app.js")
    assert "FINGERPRINT_POLICY_VERSION" in projects
    assert "fingerprint_policy" in projects
    assert "_assert_current_compose_safety" in projects
    assert "force=True" in projects
    for phase in ("PREPARED", "OLD_MOVED_TO_ROLLBACK", "NEW_PROMOTED", "POSTCHECK_PASSED", "COMMITTED"):
        assert phase in restore
    assert "BoundedSemaphore" in operations
    assert "queued_deadline_at" in operations
    for state in ("completed", "failed", "cancelled", "interrupted"):
        assert state in frontend


def test_yaml_generation_uses_rejecting_scalar_encoders():
    common = read("windows/DevFleet.Common.psm1")
    provision = read("windows/02-Provision-ComputeNode.ps1")
    vault = read("windows/03-Provision-Vault.ps1")
    assert "ConvertTo-YamlSingleQuotedScalar" in common
    assert "ConvertTo-ShellSingleQuotedScalar" in common
    assert "ConvertTo-YamlSingleQuotedScalar" in provision
    assert "ConvertTo-ShellSingleQuotedScalar" in provision
    assert "ConvertTo-YamlSingleQuotedScalar" in vault


def test_fresh_multipass_launch_has_one_bounded_exact_readiness_recovery():
    common = read("windows/DevFleet.Common.psm1")
    compute = read("windows/02-Provision-ComputeNode.ps1")
    vault = read("windows/03-Provision-Vault.ps1")
    assert "function Invoke-MultipassLaunchWithReadinessRecovery" in common
    assert "--timeout" in common
    assert "Fresh Multipass launch recovery refused existing instance" in common
    assert "multipass-stop-start" in common
    assert "Wait-MultipassReady -Name $InstanceName" in common
    for provisioner in (compute, vault):
        assert "Invoke-MultipassLaunchWithReadinessRecovery" in provisioner
        assert "-OnInstanceEstablished" in provisioner
        assert "-DeadlineUtc" in provisioner
        assert "$launchDeadline=[datetime]::MinValue" in provisioner
        assert "-DeadlineUtc $launchDeadline" in provisioner
        assert not re.search(r"-DeadlineUtc\s+\(if\s*\(", provisioner)


def test_fresh_multipass_launch_retries_inventory_with_the_existing_deadline():
    common = read("windows/DevFleet.Common.psm1")
    assert "function Invoke-MultipassInventoryWithBoundedRetry" in common
    assert "Invoke-MultipassInventoryWithBoundedRetry -InventoryScript $inventory" in common
    assert "DeadlineUtc" in common
    assert "inventory retry exhausted" in common
    assert "$after = @(&$inventory 60" not in common


def test_cloud_init_write_file_permissions_are_explicit_schema_strings():
    expected_0644_counts = {"cloud-init/compute.yaml": 3, "cloud-init/vault.yaml": 2}
    expected_total_counts = {"cloud-init/compute.yaml": 3, "cloud-init/vault.yaml": 3}
    for relative, expected_0644_count in expected_0644_counts.items():
        source = read(relative)
        assert source.count("permissions: !!str 0644") == expected_0644_count
        assert not re.search(r"(?m)^\s+permissions:\s+(?!!!str\b)\S+", source)

        document = yaml.safe_load(source)
        permissions = [entry["permissions"] for entry in document["write_files"]]
        assert len(permissions) == expected_total_counts[relative]
        assert all(isinstance(mode, str) and re.fullmatch(r"0[0-7]{3}", mode) for mode in permissions)


def test_project_metadata_transaction_preserves_concurrent_fields(tmp_path):
    from devfleet.projects import project_metadata_transaction

    project = tmp_path / "transaction-project"
    (project / ".devfleet").mkdir(parents=True)
    metadata = {
        "schema_version": 3,
        "managed_by": "devfleet",
        "slug": project.name,
        "identity": project.name,
        "project_id": "12345678-1234-1234-1234-123456789012",
        "runtime_provider": "docker-compose",
        "runtime_id": "",
        "host_id": "test-node",
        "health_status": "unknown",
        "lifecycle_status": "ready",
    }
    (project / ".devfleet/project.json").write_text(json.dumps(metadata), encoding="utf-8")

    def write_field(name, value):
        with project_metadata_transaction(project) as current:
            current[name] = value

    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda item: write_field(*item), (("field_a", "a"), ("field_b", "b"))))
    result = json.loads((project / ".devfleet/project.json").read_text(encoding="utf-8"))
    assert result["field_a"] == "a"
    assert result["field_b"] == "b"

```


## FILE: source/tests/test_hardening8_api_serialization.py

SHA256: 6af8731cc3e3d84adf2d355de336e1adf60780f5072dee5ac7b998124532ec29 | Bytes: 7410 | Git mode: 100644

```
import json
import threading
import time
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient

from devfleet import main, operations


def _project(tmp_path, slug="demo"):
    project = tmp_path / slug
    project.mkdir()
    return project


def _route_state(monkeypatch, tmp_path):
    project = _project(tmp_path)
    monkeypatch.setattr(main, "SETTINGS", replace(main.SETTINGS, workspaces=tmp_path))
    metadata = {
        "schema_version": 3,
        "managed_by": "devfleet",
        "project_id": "12345678-1234-1234-1234-123456789abc",
        "slug": "demo",
        "runtime_id": "df_demo",
        "host_id": "test-node",
        "runtime_provider": "docker-compose",
    }
    (project / ".devfleet").mkdir()
    (project / ".devfleet/project.json").write_text(
        json.dumps(metadata), encoding="utf-8"
    )
    monkeypatch.setattr(main, "load_meta", lambda _project: metadata)
    monkeypatch.setattr(main, "project_capabilities", lambda *_args: {"can_run_runtime_action": True, "status_reason": ""})
    return metadata


def test_api_mutator_is_accepted_by_durable_serializer_and_never_runs_inline(monkeypatch, tmp_path):
    metadata = _route_state(monkeypatch, tmp_path)
    submissions = []
    monkeypatch.setattr(main, "stop_project", lambda *_: pytest.fail("API mutator ran inline"))
    monkeypatch.setattr(main, "submit_operation", lambda *args, **kwargs: submissions.append((args, kwargs)) or "stop-op-1")

    response = TestClient(main.app).post(
        "/api/projects/demo/stop",
        headers={"X-DevFleet-Token": "test-token", "X-Idempotency-Key": "client-request-1"},
        json={},
    )

    assert response.status_code == 202
    assert response.json() == {
        "ok": True,
        "accepted": True,
        "operation_id": "stop-op-1",
        "operation_url": "/api/operations/stop-op-1",
    }
    args, kwargs = submissions[0]
    assert args[:2] == ("stop", "demo")
    assert kwargs["project_id"] == metadata["project_id"]
    assert kwargs["runtime_id"] == metadata["runtime_id"]
    assert kwargs["idempotency_key"].endswith(":client-request-1")


def test_read_only_api_actions_remain_synchronous(monkeypatch, tmp_path):
    _route_state(monkeypatch, tmp_path)
    monkeypatch.setattr(main, "inspect_runtime", lambda slug: {"slug": slug, "read_only": True})
    monkeypatch.setattr(main, "submit_operation", lambda *_args, **_kwargs: pytest.fail("read-only action was queued"))

    response = TestClient(main.app).post(
        "/api/projects/demo/inspect",
        headers={"X-DevFleet-Token": "test-token"},
        json={},
    )

    assert response.status_code == 200
    assert response.json() == {"ok": True, "output": {"slug": "demo", "read_only": True}}


def test_api_project_creation_uses_the_same_durable_admission(monkeypatch):
    submissions = []
    monkeypatch.setattr(main, "create_project", lambda **_kwargs: pytest.fail("API create ran inline"))
    monkeypatch.setattr(main, "submit_operation", lambda *args, **kwargs: submissions.append((args, kwargs)) or "create-op-1")

    response = TestClient(main.app).post(
        "/api/projects/create",
        headers={"X-DevFleet-Token": "test-token"},
        json={"slug": "new-app", "idempotency_key": "create-request-1"},
    )

    assert response.status_code == 202
    assert response.json()["operation_id"] == "create-op-1"
    assert submissions[0][0][:2] == ("create", "new-app")
    assert submissions[0][1]["idempotency_key"] == "project-create:new-app:create-request-1"


def test_action_classification_is_explicit_and_closed():
    assert main.PROJECT_READ_ONLY_ACTIONS == {"inspect", "runtime-health", "logs"}
    assert {
        "start", "stop", "restart", "rebuild", "backup", "bootstrap", "health", "test",
        "codexpro", "quarantine", "destroy", "restore-vault", "restore-backup",
        "analyze-force", "reconcile-failed-migration",
    } == main.PROJECT_MUTATING_ACTIONS
    assert main.PROJECT_ACTIONS == main.PROJECT_READ_ONLY_ACTIONS | main.PROJECT_MUTATING_ACTIONS


def _wait_terminal(operation_id, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        record = operations.get_operation(operation_id)
        if record["state"] in {"completed", "failed", "cancelled", "interrupted"}:
            return record
        time.sleep(0.01)
    raise AssertionError(f"operation {operation_id} did not become terminal")


@pytest.mark.parametrize(
    ("first_kind", "second_kind"),
    [("api-start", "api-stop"), ("api-destroy", "ui-start"), ("api-backup", "ui-start"), ("api-rebuild", "api-stop")],
)
def test_same_project_mutators_have_maximum_concurrency_one(monkeypatch, tmp_path, first_kind, second_kind):
    monkeypatch.setattr(operations, "SETTINGS", replace(operations.SETTINGS, runtime_root=tmp_path))
    started = threading.Event()
    release = threading.Event()
    active = 0
    maximum = 0
    guard = threading.Lock()

    def first(_ctx):
        nonlocal active, maximum
        with guard:
            active += 1
            maximum = max(maximum, active)
        started.set()
        release.wait(2)
        with guard:
            active -= 1
        return "first"

    def second(_ctx):
        nonlocal active, maximum
        with guard:
            active += 1
            maximum = max(maximum, active)
            active -= 1
        return "second"

    first_id = operations.submit_operation(first_kind, "demo", first)
    assert started.wait(1)
    second_id = operations.submit_operation(second_kind, "demo", second)
    release.set()
    assert _wait_terminal(first_id)["state"] == "completed"
    assert _wait_terminal(second_id)["state"] in {"completed", "failed"}
    assert maximum == 1


def test_cancelled_queued_operation_never_executes(monkeypatch, tmp_path):
    monkeypatch.setattr(operations, "SETTINGS", replace(operations.SETTINGS, runtime_root=tmp_path))
    queued = []

    class DeferredExecutor:
        def submit(self, callback):
            queued.append(callback)

    monkeypatch.setattr(operations, "_EXECUTOR", DeferredExecutor())
    ran = []
    operation_id = operations.submit_operation("api-start", "demo", lambda _ctx: ran.append(True))
    operations.update_operation(operation_id, state="cancelled", completed_at=operations.now_iso())

    queued[0]()

    assert ran == []
    assert operations.get_operation(operation_id)["state"] == "cancelled"


def test_operation_admission_backpressure_fails_closed(monkeypatch, tmp_path):
    monkeypatch.setattr(operations, "SETTINGS", replace(operations.SETTINGS, runtime_root=tmp_path))
    monkeypatch.setattr(operations, "_ADMISSION", threading.BoundedSemaphore(1))
    queued = []

    class DeferredExecutor:
        def submit(self, callback):
            queued.append(callback)

    monkeypatch.setattr(operations, "_EXECUTOR", DeferredExecutor())
    first = operations.submit_operation("api-start", "first", lambda _ctx: "held")
    second = operations.submit_operation("api-start", "second", lambda _ctx: pytest.fail("backpressured work ran"))

    assert operations.get_operation(first)["state"] == "queued"
    blocked = operations.get_operation(second)
    assert blocked["state"] == "failed"
    assert blocked["error"] == "operation_capacity"
    operations.update_operation(first, state="cancelled", completed_at=operations.now_iso())
    queued[0]()

```


## FILE: source/tests/test_hardening8_container_ownership.py

SHA256: a69ff2930191b209eff2bc8d772d2bcc824fa314f8fb54b464b4b7de975a9af2 | Bytes: 8949 | Git mode: 100644

```
import json
import contextlib
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from devfleet import containers, projects
from devfleet.core import SETTINGS


CONTAINER_ID = "a" * 64
PROJECT_ID = "12345678-1234-1234-1234-123456789abc"


def _project(tmp_path: Path, *, slug: str = "owned-app") -> dict:
    project = tmp_path / slug
    (project / ".devfleet").mkdir(parents=True)
    metadata = {
        "schema_version": 5,
        "managed_by": "devfleet",
        "project_id": PROJECT_ID,
        "slug": slug,
        "runtime_provider": "docker-compose",
        "runtime_id": "df_owned_app",
        "deployment_id": "deployment-123",
        "host_id": "test-node",
    }
    (project / ".devfleet/project.json").write_text(json.dumps(metadata), encoding="utf-8")
    return metadata


def _labels(**changes) -> dict[str, str]:
    labels = {
        "io.devfleet.managed-by": "devfleet",
        "io.devfleet.project-id": PROJECT_ID,
        "io.devfleet.project-slug": "owned-app",
        "io.devfleet.runtime-id": "df_owned_app",
        "io.devfleet.deployment-id": "deployment-123",
        "io.devfleet.host-id": "test-node",
        "com.docker.compose.project": "df_owned_app",
        "com.docker.compose.service": "app",
    }
    labels.update(changes)
    return labels


def _inspect(container_id: str = CONTAINER_ID, labels: dict | None = None, name: str = "/renamed-app") -> dict:
    return {"Id": container_id, "Name": name, "Config": {"Labels": labels if labels is not None else _labels()}}


def _runner(first: dict, second: dict | None = None):
    calls: list[list[str]] = []

    def fake_run(args, **_kwargs):
        calls.append(list(args))
        if args[:2] == ["docker", "inspect"]:
            value = first if len([c for c in calls if c[:2] == ["docker", "inspect"]]) == 1 else second
            if value is None:
                return SimpleNamespace(returncode=1, stdout="", stderr="No such container")
            return SimpleNamespace(returncode=0, stdout=json.dumps([value]), stderr="")
        return SimpleNamespace(returncode=0, stdout=args[-1], stderr="")

    return fake_run, calls


def _configure(monkeypatch, tmp_path):
    _project(tmp_path)
    settings = replace(
        SETTINGS,
        workspaces=tmp_path,
        runtime_root=tmp_path / "runtime",
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(containers, "SETTINGS", settings)
    monkeypatch.setattr(projects, "SETTINGS", settings)


def _write_pending_marker(tmp_path: Path) -> None:
    project = tmp_path / "owned-app"
    marker = projects._transfer_pending_marker_path(project)
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "workspace_path": str(project.absolute()),
                "workspace_name": "owned-app",
                "project_id": PROJECT_ID,
                "deployment_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                "source_host_id": "devfleet-primary",
                "destination_host_id": "test-node",
                "state": "pending-source-finalization",
                "created_at": "2026-09-16T00:00:00Z",
            }
        ),
        encoding="utf-8",
    )


@pytest.mark.parametrize(
    "labels",
    [
        {},
        {"io.devfleet.managed-by": "devfleet"},
        _labels(**{"io.devfleet.project-id": "22345678-1234-1234-1234-123456789abc"}),
        _labels(**{"io.devfleet.deployment-id": "other-deployment"}),
        _labels(**{"com.docker.compose.project": "foreign-compose"}),
    ],
)
def test_foreign_partial_and_mismatched_containers_are_preserved(monkeypatch, tmp_path, labels):
    _configure(monkeypatch, tmp_path)
    fake_run, calls = _runner(_inspect(labels=labels))
    monkeypatch.setattr(containers, "run", fake_run)

    with pytest.raises(ValueError, match="ownership"):
        containers.container_action("foreign-db", "remove")

    assert not any(call[:2] == ["docker", "rm"] for call in calls)


@pytest.mark.parametrize(
    ("action", "docker_command"),
    [("start", "start"), ("stop", "stop"), ("restart", "restart"), ("pause", "pause"), ("unpause", "unpause"), ("remove", "rm")],
)
def test_every_legitimate_action_mutates_verified_immutable_id(monkeypatch, tmp_path, action, docker_command):
    _configure(monkeypatch, tmp_path)
    inspected = _inspect(name="/renamed-current-container")
    fake_run, calls = _runner(inspected, inspected)
    monkeypatch.setattr(containers, "run", fake_run)

    containers.container_action("old-visible-name", action)

    assert calls[-1] == ["docker", docker_command, CONTAINER_ID]
    assert not any(call[-1:] == ["old-visible-name"] and call[:2] != ["docker", "inspect"] for call in calls)


def test_deleted_recreated_same_name_fails_closed_before_mutation(monkeypatch, tmp_path):
    _configure(monkeypatch, tmp_path)
    fake_run, calls = _runner(_inspect(), None)
    monkeypatch.setattr(containers, "run", fake_run)

    with pytest.raises(ValueError, match="disappeared"):
        containers.container_action("owned-app-1", "stop")

    assert not any(call[:2] == ["docker", "stop"] for call in calls)


def test_id_name_substitution_fails_closed_before_mutation(monkeypatch, tmp_path):
    _configure(monkeypatch, tmp_path)
    fake_run, calls = _runner(_inspect(), _inspect(container_id="b" * 64))
    monkeypatch.setattr(containers, "run", fake_run)

    with pytest.raises(ValueError, match="identity changed"):
        containers.container_action("owned-app-1", "pause")

    assert not any(call[:2] == ["docker", "pause"] for call in calls)


def test_pending_transfer_marker_blocks_mutation_but_not_read(monkeypatch, tmp_path):
    _configure(monkeypatch, tmp_path)
    _write_pending_marker(tmp_path)
    inspected = _inspect()
    fake_run, calls = _runner(inspected, inspected)
    monkeypatch.setattr(containers, "run", fake_run)

    assert containers.inspect_container("owned-app")["Id"] == CONTAINER_ID
    with pytest.raises(ValueError, match="awaits source finalization"):
        containers.container_action("owned-app", "start")

    assert not any(call[:2] == ["docker", "start"] for call in calls)


@pytest.mark.parametrize(
    ("pending_field", "pending_value"),
    [
        ("transfer_state", "pending-source-finalization"),
        ("lifecycle_status", "ownership-transfer-pending"),
    ],
)
def test_persisted_pending_transfer_blocks_mutation_when_marker_is_deleted(
    monkeypatch, tmp_path, pending_field, pending_value
):
    _configure(monkeypatch, tmp_path)
    metadata_path = tmp_path / "owned-app/.devfleet/project.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata[pending_field] = pending_value
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    _write_pending_marker(tmp_path)
    marker_path = projects._transfer_pending_marker_path(tmp_path / "owned-app")
    marker_path.unlink()
    assert not marker_path.exists()
    inspected = _inspect()
    fake_run, calls = _runner(inspected, inspected)
    monkeypatch.setattr(containers, "run", fake_run)

    with pytest.raises(ValueError, match="awaits source finalization"):
        containers.container_action("owned-app", "restart")

    assert not any(call[:2] == ["docker", "restart"] for call in calls)


def test_container_mutation_rechecks_pending_marker_after_shared_lock(
    monkeypatch, tmp_path
):
    _configure(monkeypatch, tmp_path)
    inspected = _inspect()
    fake_run, calls = _runner(inspected, inspected)
    monkeypatch.setattr(containers, "run", fake_run)

    @contextlib.contextmanager
    def receive_wins_lock(_slug):
        _write_pending_marker(tmp_path)
        yield

    monkeypatch.setattr(projects, "project_transfer_lock", receive_wins_lock)
    with pytest.raises(ValueError, match="awaits source finalization"):
        containers.container_action("owned-app", "restart")

    assert not any(call[:2] == ["docker", "restart"] for call in calls)


def test_compose_override_binds_every_service_to_complete_current_identity(tmp_path):
    metadata = _project(tmp_path)
    project = tmp_path / "owned-app"
    compose = project / "compose.yaml"
    compose.write_text("services:\n  app:\n    image: example/app\n  db:\n    image: example/db\n", encoding="utf-8")

    override = projects._write_current_compose_ownership(project, compose, metadata)
    document = yaml.safe_load(override.read_text(encoding="utf-8"))

    expected = _labels()
    expected.pop("com.docker.compose.project")
    expected.pop("com.docker.compose.service")
    assert document == {"services": {"app": {"labels": expected}, "db": {"labels": expected}}}
    args = projects.compose_args(project, compose)
    assert str(override) in args
    assert args[-2:] == ["-p", "df_owned_app"]

```


## FILE: source/tests/test_hardening8_manifest_version.py

SHA256: 1573d8d8d6573200b2e6be1d2ae0532d37d5dfdc14fc28e830a4f3c9d1a744d8 | Bytes: 1545 | Git mode: 100644

```
import re
from pathlib import Path

from _bundle_layout import resolve_bundle_layout


ROOT = Path(__file__).parents[2]
LAYOUT = resolve_bundle_layout(Path(__file__))


def test_application_manifest_tracks_canonical_installer_four_part_version():
    installer_version = (ROOT / "installer-source/INSTALLER_VERSION").read_text(encoding="utf-8").strip()
    assert re.fullmatch(r"\d+\.\d+\.\d+", installer_version)
    manifest = (ROOT / "installer-source/DevFleet.Setup/app.manifest").read_text(encoding="utf-8")
    identity = re.search(r'<assemblyIdentity\s+version="([^"]+)"\s+name="MTechLabs\.DevFleet\.Setup"', manifest)
    assert identity
    assert identity.group(1) == f"{installer_version}.0"


def test_release_builder_derives_and_verifies_manifest_identity():
    build = (ROOT / "installer-source/Build-Release.ps1").read_text(encoding="utf-8")
    assert '$assemblyVersion="$installerVersion.0"' in build
    assert "Windows application manifest identity is not synchronized" in build


def test_ai_bundle_requires_current_schema_v2_identity_closure():
    builder = (LAYOUT.release_tooling_root / "Build-AIAuditBundle.ps1").read_text(encoding="utf-8")
    validator = (ROOT / "source/tools/validate_ai_audit_bundle.py").read_text(encoding="utf-8")
    for name in ("release-fingerprint.json", "tooling-fingerprint-current.json", "final-artifact-hashes.json"):
        assert name in builder
        assert name in validator
    assert "validate_audit_coherence.py" in builder
    assert "validate_audit_coherence.py" in validator

```


## FILE: source/tests/test_hardening8_restore_journal.py

SHA256: 91a4d0d581078bc37003de7e0002f40151be9b141155fd587b8dfd7991720917 | Bytes: 8866 | Git mode: 100644

```
import json
import os
import stat
from pathlib import Path

import pytest

from devfleet import workspace_archives
from devfleet.workspace_archives import reconcile_restore_transaction


ROLLBACK_TOKEN = "0123456789abcdef0123456789abcdef"


def _paths(tmp_path: Path, slug: str = "demo") -> tuple[Path, Path, Path, Path]:
    destination = tmp_path / slug
    transaction_root = tmp_path / workspace_archives.TRANSACTION_ROOT_NAME
    staging = transaction_root / f".{slug}-restore-ABC12345" if workspace_archives.POSIX_FD_HARDENING else tmp_path / f".{slug}-restore-ABC12345"
    rollback = tmp_path / f".{slug}.rollback-{ROLLBACK_TOKEN}"
    journal = tmp_path / f".{slug}.restore-transaction.json"
    return destination, staging, rollback, journal


def _record(destination: Path, staging: Path, rollback: Path, phase: str = "PREPARED") -> dict:
    if workspace_archives.POSIX_FD_HARDENING:
        def identity(path: Path):
            result = path.lstat()
            return {
                "st_dev": int(result.st_dev),
                "st_ino": int(result.st_ino),
                "st_type": int(stat.S_IFMT(result.st_mode)),
            }

        destination_identity = identity(destination) if destination.exists() else None
        rollback_identity = identity(rollback) if rollback.exists() else None
        restored_identity = destination_identity if phase in {"NEW_PROMOTED", "POSTCHECK_PASSED", "COMMITTED"} else None
        return {
            "schema_version": workspace_archives.POSIX_RESTORE_JOURNAL_SCHEMA_VERSION,
            "slug": destination.name,
            "destination": str(destination.absolute()),
            "transaction_root": str(destination.parent / workspace_archives.TRANSACTION_ROOT_NAME),
            "staging_root": str(staging.absolute()),
            "rollback": str(rollback.absolute()),
            "destination_identity": destination_identity if phase != "OLD_MOVED_TO_ROLLBACK" else rollback_identity,
            "staging_identity": identity(staging) if staging.exists() else None,
            "rollback_identity": rollback_identity,
            "restored_identity": restored_identity,
            "phase": phase,
        }
    return {
        "schema_version": 1,
        "slug": destination.name,
        "destination": str(destination),
        "staging_root": str(staging),
        "rollback": str(rollback),
        "phase": phase,
    }


def _write_record(journal: Path, record: dict) -> None:
    journal.write_text(json.dumps(record), encoding="utf-8")


def _assert_refused_without_mutation(tmp_path: Path, record: dict) -> None:
    destination, staging, rollback, journal = _paths(tmp_path)
    if workspace_archives.POSIX_FD_HARDENING:
        staging.parent.mkdir(exist_ok=True)
    destination.mkdir(exist_ok=True)
    staging.mkdir(exist_ok=True)
    rollback.mkdir(exist_ok=True)
    for path in (destination, staging, rollback):
        (path / "SENTINEL").write_text(path.name, encoding="utf-8")
    _write_record(journal, record)

    with pytest.raises(RuntimeError, match="manual recovery required"):
        reconcile_restore_transaction(destination)

    assert journal.exists()
    assert (tmp_path / ".demo.restore-manual-recovery.json").is_file()
    for path in (destination, staging, rollback):
        assert (path / "SENTINEL").read_text(encoding="utf-8") == path.name


@pytest.mark.parametrize(
    ("field", "unsafe"),
    [
        ("staging_root", ""),
        ("staging_root", None),
        ("staging_root", "."),
        ("staging_root", ".."),
        ("staging_root", "../outside"),
        ("rollback", ""),
        ("rollback", None),
        ("rollback", "."),
        ("rollback", ".."),
        ("rollback", "../outside"),
    ],
)
def test_restore_journal_rejects_empty_and_relative_paths_without_mutation(tmp_path, field, unsafe):
    destination, staging, rollback, _ = _paths(tmp_path)
    record = _record(destination, staging, rollback)
    record[field] = unsafe
    _assert_refused_without_mutation(tmp_path, record)


@pytest.mark.parametrize("field", ["staging_root", "rollback"])
def test_restore_journal_rejects_absolute_outside_paths_and_preserves_sentinel(tmp_path, field):
    destination, staging, rollback, _ = _paths(tmp_path)
    outside = tmp_path.parent / f"outside-{field}-{tmp_path.name}"
    outside.mkdir()
    try:
        sentinel = outside / "UNRELATED-SENTINEL"
        sentinel.write_text("keep", encoding="utf-8")
        record = _record(destination, staging, rollback)
        record[field] = str(outside)
        _assert_refused_without_mutation(tmp_path, record)
        assert sentinel.read_text(encoding="utf-8") == "keep"
    finally:
        for child in outside.iterdir():
            child.unlink()
        outside.rmdir()


@pytest.mark.parametrize(
    "mutation",
    [
        {"schema_version": 2},
        {"schema_version": "1"},
        {"slug": "wrong-slug"},
        {"destination": None},
        {"destination": "."},
        {"phase": "UNKNOWN"},
    ],
)
def test_restore_journal_rejects_wrong_schema_slug_destination_and_phase(tmp_path, mutation):
    destination, staging, rollback, _ = _paths(tmp_path)
    record = _record(destination, staging, rollback)
    record.update(mutation)
    if mutation.get("destination") is None and "destination" not in mutation:
        record["destination"] = str(tmp_path / "wrong")
    _assert_refused_without_mutation(tmp_path, record)


def test_restore_journal_rejects_wrong_absolute_destination(tmp_path):
    destination, staging, rollback, _ = _paths(tmp_path)
    record = _record(destination, staging, rollback)
    record["destination"] = str(tmp_path / "other")
    _assert_refused_without_mutation(tmp_path, record)


def test_restore_journal_rejects_swapped_stage_and_rollback(tmp_path):
    destination, staging, rollback, _ = _paths(tmp_path)
    record = _record(destination, staging, rollback)
    record["staging_root"], record["rollback"] = record["rollback"], record["staging_root"]
    _assert_refused_without_mutation(tmp_path, record)


@pytest.mark.parametrize("field", ["staging_root", "rollback"])
def test_restore_journal_rejects_symlinked_transaction_paths(tmp_path, field):
    destination, staging, rollback, _ = _paths(tmp_path)
    target = tmp_path / "foreign-target"
    target.mkdir()
    path = staging if field == "staging_root" else rollback
    if workspace_archives.POSIX_FD_HARDENING:
        path.parent.mkdir(exist_ok=True)
    try:
        os.symlink(target, path, target_is_directory=True)
    except (OSError, NotImplementedError) as exc:
        pytest.skip(f"directory symlink creation unavailable: {exc}")
    other = rollback if field == "staging_root" else staging
    if workspace_archives.POSIX_FD_HARDENING:
        other.parent.mkdir(exist_ok=True)
    other.mkdir()
    destination.mkdir()
    for candidate in (destination, target, other):
        (candidate / "SENTINEL").write_text(candidate.name, encoding="utf-8")
    record = _record(destination, staging, rollback)
    journal = tmp_path / ".demo.restore-transaction.json"
    _write_record(journal, record)

    with pytest.raises(RuntimeError, match="manual recovery required"):
        reconcile_restore_transaction(destination)

    assert (target / "SENTINEL").read_text(encoding="utf-8") == target.name
    assert (other / "SENTINEL").read_text(encoding="utf-8") == other.name
    assert journal.exists()


@pytest.mark.parametrize(
    "phase",
    ["PREPARED", "OLD_MOVED_TO_ROLLBACK", "NEW_PROMOTED", "POSTCHECK_PASSED", "COMMITTED"],
)
def test_restore_journal_reconciles_every_legitimate_phase_and_is_idempotent(tmp_path, phase):
    destination, staging, rollback, journal = _paths(tmp_path)
    if workspace_archives.POSIX_FD_HARDENING:
        staging.parent.mkdir(exist_ok=True)
    staging.mkdir()
    (staging / "temporary").write_text("discard", encoding="utf-8")
    if phase == "OLD_MOVED_TO_ROLLBACK":
        destination.mkdir()
        (destination / "known-good").write_text("old", encoding="utf-8")
        destination.rename(rollback)
    elif phase in {"NEW_PROMOTED", "POSTCHECK_PASSED", "COMMITTED"}:
        destination.mkdir()
        (destination / "canonical").write_text("current", encoding="utf-8")
        rollback.mkdir()
        (rollback / "known-good").write_text("old", encoding="utf-8")
    else:
        destination.mkdir()
        (destination / "canonical").write_text("current", encoding="utf-8")
    _write_record(journal, _record(destination, staging, rollback, phase))

    result = reconcile_restore_transaction(destination)

    assert result == {"recovered": True, "phase": phase, "destination": str(destination)}
    assert destination.is_dir()
    assert not staging.exists()
    assert not rollback.exists()
    assert not journal.exists()
    assert reconcile_restore_transaction(destination) is None

```


## FILE: source/tests/test_hardening8_secret_recovery.py

SHA256: 6eee62b71d85f1f9971a38c129cc7fe010f4499084ef6ca02dd87e4b4e70d4e5 | Bytes: 2501 | Git mode: 100644

```
from pathlib import Path


ROOT = Path(__file__).parents[1]


def test_rekey_is_explicit_transactional_and_commits_last():
    script = (ROOT / "windows/Repair-DevFleetHostSecrets.ps1").read_text(encoding="utf-8")
    assert "ValidateSet('REKEY DEVFLEET HOST SECRETS')" in script
    assert "New-DevFleetSnapshotSafe" in script
    assert "Get-ExactGuestIdentity" in script
    assert "Assert-DevFleetTaskBinding" in script
    assert "-StandardInputText" in script
    assert "host-secrets.before.json" in script
    assert "rollback" in script
    assert "plaintextSecretsLogged=$false" in script
    assert script.index("$evidence.hostAgent.verified = $true") < script.index("Write-AtomicUtf8 -Path $secretPath")
    assert script.index("Write-AtomicUtf8 -Path $secretPath") < script.index("$committed = $true")


def test_rek