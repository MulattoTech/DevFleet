# DevFleet source part 100

Full-source UTF-8 byte interval [4603500, 4650000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 1dffba7e3fed60620b34a31197b7a0fbd5e74f4ead471e6f7d53b0f04567fba0

<!-- BEGIN SOURCE SLICE -->
lt-broker"' in bootstrap
    assert "devfleet-vault-broker.socket" in bootstrap
    assert "devfleet-vault-broker@.service" in bootstrap
    assert "enable --now devfleet.service devfleet-backup.timer devfleet-vault-broker.socket" in bootstrap
    assert "usermod --append --groups devfleet-backup devfleet-control" not in bootstrap
    assert "NOPASSWD:ALL" not in bootstrap


def test_rebootstrap_preserves_backup_only_restic_credentials():
    bootstrap = read("linux/bootstrap-compute.sh")
    update = read("windows/Update-DevFleet.ps1")
    provision = read("windows/02-Provision-ComputeNode.ps1")

    assert "02-Provision-ComputeNode.ps1" in update
    assert "updating the DevFleet payload in place" in provision
    assert "bootstrapBoundary.bootstrapCommand" in provision
    assert "chown root:devfleet-control /etc/devfleet/*" not in bootstrap
    assert "chmod 0640 /etc/devfleet/*" not in bootstrap
    assert '[[ "$config_file" == "/etc/devfleet/restic.env" ]] && continue' in bootstrap
    assert "chown root:devfleet-backup /etc/devfleet/restic.env" in bootstrap
    assert "chmod 0640 /etc/devfleet/restic.env" in bootstrap
    assert "setfacl -m u:devfleet-backup:--x /etc/devfleet" in bootstrap
    assert "setfacl -m u:devfleet-backup:rwx /home/devrunner/.devfleet" not in bootstrap
    assert "setfacl -x u:devfleet-backup /home/devrunner/.devfleet" in bootstrap
    assert "setfacl -x d:u:devfleet-backup /home/devrunner/.devfleet" in bootstrap


def test_vault_credentials_remain_readable_only_by_the_backup_identity():
    configure = read("linux/devfleet-configure-backup")

    assert "chown root:devfleet-backup /etc/devfleet/restic.env" in configure
    assert "chmod 0640 /etc/devfleet/restic.env" in configure
    assert "install -d -o devfleet-backup -g devfleet-backup -m 0700" in configure
    assert "u:devfleet-control" not in configure


def test_backup_and_restore_share_a_truthful_nonblocking_operation_lock():
    backup = read("linux/devfleet-backup")
    restore = read("linux/devfleet-restore-project")

    lock = "/run/lock/devfleet-vault-operation.lock"
    assert lock in backup
    assert lock in restore
    assert "exit 75" in backup
    assert "exit 75" in restore


def test_restore_copy_fails_closed_on_preexisting_or_racing_target():
    restore = read("linux/devfleet-restore-project")

    assert '[[ ! -e "$target" && ! -L "$target" ]]' in restore
    assert 'mv -T --no-clobber -- "$source_dir" "$target"' in restore
    assert '[[ ! -e "$source_dir" && -d "$target" && ! -L "$target" ]]' in restore


def test_dashboard_exposes_only_restore_copy_from_vault():
    template = read("app/templates/index.html")

    assert "project_action(p.slug,'restore-vault','Restore copy from vault','ghost')" in template
    assert "preserves the original workspace" in template


def test_broker_success_is_bound_to_the_fixed_child_exit_not_mutable_telemetry(monkeypatch):
    broker = load_broker_module(monkeypatch)
    monkeypatch.setattr(broker.os, "access", lambda *_args: True)
    monkeypatch.setattr(
        broker,
        "_run_child",
        lambda *_args, **_kwargs: subprocess.CompletedProcess(
            ["/usr/local/bin/devfleet-backup"], 0, "", ""
        ),
    )

    assert broker._run_fixed_operation("backup", "", "") == {
        "ok": True,
        "action": "backup",
        "local_backup_status": "verified",
        "vault_upload_status": "verified",
        "durability_level": "vault",
    }


def test_broker_restore_uses_only_identity_bound_fixed_argv(monkeypatch, tmp_path):
    broker = load_broker_module(monkeypatch)
    project = "vault-source"
    project_id = "12345678-1234-1234-1234-123456789abc"
    target = tmp_path / "vault-source-recovered-20260916-123456-deadbeef"
    (target / ".devfleet").mkdir(parents=True)
    (target / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": project,
                "project_id": project_id,
            }
        ),
        encoding="utf-8",
    )
    calls = []
    monkeypatch.setattr(broker, "WORKSPACES", tmp_path)
    monkeypatch.setattr(broker.os, "access", lambda *_args: True)

    returned_target = [target]

    def run_child(command, timeout):
        calls.append((command, timeout))
        return subprocess.CompletedProcess(command, 0, str(returned_target[0]) + "\n", "")

    monkeypatch.setattr(broker, "_run_child", run_child)
    monkeypatch.setattr(broker, "_restored_identity_matches", lambda *_args: True)
    receipt = broker._run_fixed_operation("restore-copy", project, project_id)

    assert calls == [
        (
            ["/usr/local/bin/devfleet-restore-project", project, project_id],
            3600,
        )
    ]
    assert receipt == {
        "ok": True,
        "action": "restore-copy",
        "project": project,
        "project_id": project_id,
        "target": str(target),
    }

    with pytest.raises(broker.ProtocolError):
        broker._parse_request({"action": "restore-canonical", "project": project, "project_id": project_id})


@pytest.mark.parametrize("action", ["restore-copy"])
def test_broker_rejects_restored_metadata_parent_symlink(
    monkeypatch, tmp_path, action
):
    broker = load_broker_module(monkeypatch)
    project = "vault-source"
    project_id = "12345678-1234-1234-1234-123456789abc"
    target = tmp_path / "vault-source-recovered-20260916-123456-deadbeef"
    target.mkdir()
    external = tmp_path / f"external-{action}"
    external.mkdir()
    (external / "project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": project,
                "identity": project,
                "project_id": project_id,
            }
        ),
        encoding="utf-8",
    )
    try:
        (target / ".devfleet").symlink_to(external, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"symlink creation unavailable: {exc}")
    monkeypatch.setattr(broker, "WORKSPACES", tmp_path)
    monkeypatch.setattr(broker.os, "access", lambda *_args: True)
    monkeypatch.setattr(
        broker,
        "_run_child",
        lambda command, timeout: subprocess.CompletedProcess(
            command, 0, str(target) + "\n", ""
        ),
    )

    receipt = broker._run_fixed_operation(action, project, project_id)

    assert receipt == {
        "ok": False,
        "error": "Vault restore target is invalid.",
        "exit_code": 5,
    }


def test_broker_rejects_extra_fields_and_wrong_project_id(monkeypatch):
    broker = load_broker_module(monkeypatch)
    with pytest.raises(broker.ProtocolError, match="not allowed"):
        broker._parse_request(
            {
                "action": "restore-copy",
                "project": "vault-source",
                "project_id": "12345678-1234-1234-1234-123456789abc",
                "path": "/attacker-controlled",
            }
        )
    with pytest.raises(broker.ProtocolError, match="Project ID"):
        broker._parse_request(
            {
                "action": "restore-copy",
                "project": "vault-source",
                "project_id": "wrong-id",
            }
        )


def test_broker_rejects_oversized_and_second_frames(monkeypatch):
    broker = load_broker_module(monkeypatch)
    left, right = socket.socketpair()
    try:
        right.sendall(struct.pack("!I", broker.MAX_REQUEST_BYTES + 1))
        right.shutdown(socket.SHUT_WR)
        with pytest.raises(broker.ProtocolError, match="length"):
            broker._receive_frame(left)
    finally:
        left.close()
        right.close()

    left, right = socket.socketpair()
    try:
        body = b'{"action":"backup"}'
        right.sendall(struct.pack("!I", len(body)) + body + b"x")
        right.shutdown(socket.SHUT_WR)
        with pytest.raises(broker.ProtocolError, match="one request"):
            broker._receive_frame(left)
    finally:
        left.close()
        right.close()


def test_broker_rejects_non_control_peer_before_parsing(monkeypatch):
    broker = load_broker_module(monkeypatch)
    monkeypatch.setattr(broker.socket, "SO_PEERCRED", 17, raising=False)

    class ForeignPeer:
        def getsockopt(self, *_args):
            return struct.pack("3i", 99, 4321, 4321)

    with pytest.raises(broker.ProtocolError, match="not authorized"):
        broker._assert_peer(ForeignPeer())


def test_broker_timeout_terminates_and_waits_for_the_owned_process_group(monkeypatch):
    broker = load_broker_module(monkeypatch)
    kills = []

    class FakeProcess:
        pid = 4242
        returncode = None

        def __init__(self):
            self.calls = 0

        def communicate(self, timeout=None):
            self.calls += 1
            if self.calls == 1:
                raise subprocess.TimeoutExpired(["fixed-child"], timeout)
            self.returncode = -signal.SIGTERM
            return "", ""

    process = FakeProcess()
    monkeypatch.setattr(broker.subprocess, "Popen", lambda *_args, **_kwargs: process)
    monkeypatch.setattr(
        broker.os,
        "killpg",
        lambda pid, requested_signal: kills.append((pid, requested_signal)),
        raising=False,
    )

    completed = broker._run_child(["fixed-child"], 1)

    assert completed.returncode == 124
    assert process.calls == 2
    assert kills == [(4242, signal.SIGTERM)]


def test_timeout_ownership_deadlines_are_strictly_nested():
    service = read("app/systemd/devfleet-vault-broker@.service")
    client = read("linux/devfleet-vault-request")
    projects_source = read("app/devfleet/projects.py")
    assert "timeout = 3600" in read("linux/devfleet-vault-broker")
    assert "RuntimeMaxSec=3660" in service
    assert "TimeoutStopSec=10" in service
    assert "connection.settimeout(3690)" in client
    assert "timeout=3720" in projects_source
    assert 3600 < 3660 < 3660 + 10 < 3690 < 3720


def test_broker_exposes_only_safe_failure_classes(monkeypatch):
    broker = load_broker_module(monkeypatch)
    monkeypatch.setattr(broker.os, "access", lambda *_args: True)
    monkeypatch.setattr(
        broker,
        "_run_child",
        lambda command, timeout: subprocess.CompletedProcess(
            command, 75, "sensitive child stdout", "sensitive child stderr"
        ),
    )

    receipt = broker._run_fixed_operation("backup", "", "")

    assert receipt == {
        "ok": False,
        "error": "Another Vault operation is already in progress.",
        "error_code": "vault-operation-busy",
        "exit_code": 75,
    }


def test_restore_copy_preserves_source_identity_and_is_not_implicitly_adopted(monkeypatch, tmp_path):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path,
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    source_slug = "vault-source"
    recovered_slug = "vault-source-recovered-20260916-123456-deadbeef"
    source = tmp_path / source_slug
    recovered = tmp_path / recovered_slug
    source_meta = {
        "schema_version": 5,
        "managed_by": "devfleet",
        "project_id": "12345678-1234-1234-1234-123456789abc",
        "slug": source_slug,
        "identity": source_slug,
        "display_name": "Vault source",
        "runtime_provider": "docker-compose",
        "runtime_isolation": "container",
        "runtime_type": "container",
        "runtime_id": projects.compose_name(source_slug),
        "runtime_address": "stale-address",
        "host_id": "test-node",
        "deployment_id": "deployment-123",
        "workspace_location": str(source),
        "workspace_path": f"/home/devrunner/workspaces/{source_slug}",
        "lifecycle_status": "running",
        "runtime_status": "running",
        "provisioning_status": "ready",
        "health_status": "healthy",
        "backup_status": "verified",
        "backup_id": "source-backup",
        "backup_sha256": "a" * 64,
        "destructive_backup_binding": {"project_id": "stale"},
    }
    for project in (source, recovered):
        (project / ".devfleet").mkdir(parents=True)
        (project / ".devfleet/project.json").write_text(
            json.dumps(source_meta), encoding="utf-8"
        )
        (project / "compose.yaml").write_text(
            "services:\n  app:\n    image: ubuntu:24.04\n", encoding="utf-8"
        )
        (project / "fixture.txt").write_text("vault-fixture\n", encoding="utf-8")
    (recovered / ".devfleet/ownership-lease.json").write_text(
        json.dumps({"project_identity": source_slug, "active": True, "active_node": "test-node"}),
        encoding="utf-8",
    )
    (recovered / ".devfleet/runtime-ownership.yaml").write_text(
        f"services:\n  app:\n    labels:\n      io.devfleet.project-slug: {source_slug}\n",
        encoding="utf-8",
    )
    original_metadata = (source / ".devfleet/project.json").read_bytes()
    monkeypatch.setattr(
        projects,
        "_vault_request",
        lambda action, slug, project_id, timeout: {
            "ok": True,
            "action": action,
            "project": slug,
            "project_id": project_id,
            "target": str(recovered),
        },
    )

    result = projects.restore_from_vault(source_slug)

    assert result == str(recovered)
    saved = json.loads((recovered / ".devfleet/project.json").read_text())
    assert saved["slug"] == source_slug
    assert saved["project_id"] == source_meta["project_id"]
    with pytest.raises(ValueError, match="slug does not bind"):
        projects.load_authoritative_project_identity_for_mutation(recovered)
    assert (source / ".devfleet/project.json").read_bytes() == original_metadata
    assert (source / "fixture.txt").read_text(encoding="utf-8") == "vault-fixture\n"


@pytest.mark.parametrize(
    "action", ["start", "stop", "rebuild", "bootstrap", "health", "test", "codexpro"]
)
def test_recovered_copy_mutations_are_rejected_before_operation_submission(
    monkeypatch, tmp_path, action
):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path,
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(main, "SETTINGS", settings)
    source_slug = "vault-source"
    recovered_slug = "vault-source-recovered-20260916-123456-deadbeef"
    recovered = tmp_path / recovered_slug
    (recovered / ".devfleet").mkdir(parents=True)
    (recovered / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "project_id": "12345678-1234-1234-1234-123456789abc",
                "slug": source_slug,
                "identity": source_slug,
                "runtime_provider": "docker-compose",
                "runtime_id": projects.compose_name(source_slug),
                "host_id": "test-node",
                "deployment_id": "deployment-123",
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        main,
        "submit_operation",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("recovered copy reached operation submission")
        ),
    )

    with TestClient(main.app) as client:
        response = client.post(
            f"/api/projects/{recovered_slug}/{action}",
            headers={"X-DevFleet-Token": "test-token"},
            json={},
        )

    assert response.status_code == 409
    assert "slug does not bind" in response.json()["detail"]


def _recovered_vm_copy(monkeypatch, tmp_path):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path,
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(main, "SETTINGS", settings)
    recovered_slug = "vault-source-recovered-20260916-123456-deadbeef"
    recovered = tmp_path / recovered_slug
    (recovered / ".devfleet").mkdir(parents=True)
    (recovered / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "project_id": "12345678-1234-1234-1234-123456789abc",
                "slug": "vault-source",
                "identity": "vault-source",
                "runtime_provider": "multipass-host-agent",
                "runtime_id": "devfleet-project-vault-source",
                "host_id": "test-node",
                "deployment_id": "deployment-123",
                "lifecycle_status": "running",
                "runtime_status": "running",
            }
        ),
        encoding="utf-8",
    )
    return recovered_slug, recovered


@pytest.mark.parametrize(
    "runtime_access",
    [
        lambda slug: projects.inspect_runtime(slug),
        lambda slug: projects.runtime_health(slug),
        lambda slug: projects.open_workspace(slug),
        lambda slug: projects.list_backups(slug),
        lambda slug: projects.project_logs(slug),
    ],
)
def test_recovered_copy_runtime_access_fails_before_provider_probe(
    monkeypatch, tmp_path, runtime_access
):
    recovered_slug, recovered = _recovered_vm_copy(monkeypatch, tmp_path)
    original = (recovered / ".devfleet/project.json").read_bytes()
    forbidden = lambda *_args, **_kwargs: (_ for _ in ()).throw(
        AssertionError("recovered copy reached a runtime provider or metadata write")
    )
    monkeypatch.setattr(projects.VmRuntimeOperations, "inspect", staticmethod(forbidden))
    monkeypatch.setattr(projects.VmRuntimeOperations, "refresh", staticmethod(forbidden))
    monkeypatch.setattr(projects.VmRuntimeOperations, "health", staticmethod(forbidden))
    monkeypatch.setattr(projects, "atomic_json", forbidden)

    with pytest.raises(ValueError, match="slug does not bind"):
        runtime_access(recovered_slug)

    assert (recovered / ".devfleet/project.json").read_bytes() == original


@pytest.mark.parametrize(
    "path",
    [
        "/api/projects/{slug}/workspace",
        "/api/projects/{slug}/runtime",
        "/api/projects/{slug}/logs",
        "/api/projects/{slug}/backups",
        "/api/projects/{slug}/capabilities",
    ],
)
def test_recovered_copy_read_routes_return_409_without_runtime_probe(
    monkeypatch, tmp_path, path
):
    recovered_slug, recovered = _recovered_vm_copy(monkeypatch, tmp_path)
    original = (recovered / ".devfleet/project.json").read_bytes()
    forbidden = lambda *_args, **_kwargs: (_ for _ in ()).throw(
        AssertionError("recovered copy reached a runtime provider")
    )
    monkeypatch.setattr(projects.VmRuntimeOperations, "inspect", staticmethod(forbidden))
    monkeypatch.setattr(projects.VmRuntimeOperations, "refresh", staticmethod(forbidden))
    monkeypatch.setattr(projects.VmRuntimeOperations, "health", staticmethod(forbidden))

    with TestClient(main.app) as client:
        response = client.get(
            path.format(slug=recovered_slug),
            headers={"X-DevFleet-Token": "test-token"},
        )

    assert response.status_code == 409
    assert "slug does not bind" in response.json()["detail"]
    assert (recovered / ".devfleet/project.json").read_bytes() == original


def test_recovered_copy_is_recovery_only_in_live_and_cached_catalogs(
    monkeypatch, tmp_path
):
    recovered_slug, recovered = _recovered_vm_copy(monkeypatch, tmp_path)
    forbidden = lambda *_args, **_kwargs: (_ for _ in ()).throw(
        AssertionError("recovery-only copy reached a live project probe")
    )
    for name in (
        "analyze_project",
        "running",
        "heartbeat_lease",
        "git_summary",
        "codexpro_status",
        "provider_for",
    ):
        monkeypatch.setattr(projects, name, forbidden)
    monkeypatch.setattr(devfleet_status, "runtime_status", lambda: {})
    monkeypatch.setattr(devfleet_status, "list_operations", lambda *_args: [])

    live = devfleet_status.local_status(live=True)["projects"]
    cached = projects.list_project_catalog()

    for records in (live, cached):
        record = next(item for item in records if item["slug"] == recovered_slug)
        assert record["recovery_only"] is True
        assert record["running"] is False
        assert record["lifecycle_state"] == "recovery-only"
        assert all(
            value is False
            for key, value in record["capabilities"].items()
            if key.startswith("can_") or key.endswith("_available")
        )
    assert not (recovered / ".devfleet/runtime/analyzer-cache.json").exists()
    assert not (recovered / ".devfleet/ownership-lease.json").exists()


def test_recovered_copy_environment_assignment_is_rejected_before_preflight_or_queue(
    monkeypatch, tmp_path
):
    recovered_slug, _ = _recovered_vm_copy(monkeypatch, tmp_path)
    forbidden = lambda *_args, **_kwargs: (_ for _ in ()).throw(
        AssertionError("recovered copy reached preflight or operation submission")
    )
    monkeypatch.setattr(main, "_preflight", forbidden)
    monkeypatch.setattr(main, "submit_operation", forbidden)

    with TestClient(main.app) as client:
        response = client.post(
            f"/api/projects/{recovered_slug}/environment",
            headers={"X-DevFleet-Token": "test-token"},
            json={"wizard_confirmed": True, "runtime_isolation": "container"},
        )

    assert response.status_code == 409
    assert "slug does not bind" in response.json()["detail"]


def test_recovered_copy_environment_reads_fail_before_workspace_or_runtime_probes(
    monkeypatch, tmp_path
):
    recovered_slug, recovered = _recovered_vm_copy(monkeypatch, tmp_path)
    original = (recovered / ".devfleet/project.json").read_bytes()
    forbidden = lambda *_args, **_kwargs: (_ for _ in ()).throw(
        AssertionError("recovered copy reached an environment or workspace probe")
    )
    for name in (
        "detect_runtime",
        "inspect_workspace",
        "get_host_capacity",
        "project_command_readiness",
        "cluster_status",
    ):
        monkeypatch.setattr(main, name, forbidden)

    with TestClient(main.app) as client:
        for path in (
            f"/api/projects/{recovered_slug}/environment",
            f"/api/projects/{recovered_slug}/preflight",
        ):
            response = client.get(path, headers={"X-DevFleet-Token": "test-token"})
            assert response.status_code == 409
            assert "slug does not bind" in response.json()["detail"]
        login = client.get("/login")
        login_csrf = re.search(
            r'name="csrf_token" value="([^"]+)"', login.text
        ).group(1)
        signed_in = client.post(
            "/login",
            data={
                "username": "test",
                "password": "test-password",
                "next": "/",
                "csrf_token": login_csrf,
            },
            follow_redirects=False,
        )
        assert signed_in.status_code == 303
        response = client.get(f"/ui/projects/{recovered_slug}/preflight")
        assert response.status_code == 409
        assert "slug does not bind" in response.json()["detail"]

    assert (recovered / ".devfleet/project.json").read_bytes() == original


def test_catalog_does_not_follow_recovery_metadata_symlinks(monkeypatch, tmp_path):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path,
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    recovered = tmp_path / "vault-recovered"
    recovered.mkdir()
    external = tmp_path / "external-metadata"
    external.mkdir()
    (external / "project.json").write_text(
        json.dumps({"sentinel_secret": "must-not-leak", "display_name": "external"}),
        encoding="utf-8",
    )
    try:
        (recovered / ".devfleet").symlink_to(external, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"symlink creation unavailable: {exc}")

    with pytest.raises(ValueError, match="metadata is missing"):
        projects.load_authoritative_project_identity_for_mutation(recovered)
    for records in (projects.list_projects(), projects.list_project_catalog()):
        record = next(item for item in records if item["slug"] == recovered.name)
        assert record["recovery_only"] is True
        assert "sentinel_secret" not in record
        assert record["display_name"] == recovered.name


def test_app_rejects_recovered_copy_with_metadata_parent_symlink(monkeypatch, tmp_path):
    source_slug = "vault-source"
    source_id = "12345678-1234-1234-1234-123456789abc"
    settings = replace(projects.SETTINGS, workspaces=tmp_path)
    monkeypatch.setattr(projects, "SETTINGS", settings)
    recovered = tmp_path / "vault-source-recovered-20260916-123456-deadbeef"
    recovered.mkdir()
    external = tmp_path / "external-recovered-metadata"
    external.mkdir()
    (external / "project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": source_slug,
                "identity": source_slug,
                "project_id": source_id,
            }
        ),
        encoding="utf-8",
    )
    try:
        (recovered / ".devfleet").symlink_to(external, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"symlink creation unavailable: {exc}")

    with pytest.raises(RuntimeError, match="no authoritative project metadata"):
        projects._validate_recovered_vault_copy(
            source_slug,
            {"project_id": source_id},
            str(recovered),
        )


@pytest.mark.parametrize("action", sorted(main.PROJECT_MUTATING_ACTIONS))
def test_recovered_copy_with_fully_rewritten_identity_remains_recovery_only(
    monkeypatch, tmp_path, action
):
    recovered_slug, recovered = _recovered_vm_copy(monkeypatch, tmp_path)
    metadata_path = recovered / ".devfleet/project.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["slug"] = recovered_slug
    metadata["identity"] = recovered_slug
    metadata["runtime_id"] = projects.compose_name(recovered_slug)
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    projects._record_vault_recovery_copy(
        recovered,
        source_slug="vault-source",
        source_project_id=metadata["project_id"],
    )
    monkeypatch.setattr(
        main,
        "submit_operation",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("inconsistent recovered identity reached operation submission")
        ),
    )

    with pytest.raises(ValueError, match="require explicit adoption"):
        projects.load_authoritative_project_identity_for_mutation(recovered)
    catalog = projects.list_project_catalog()
    record = next(item for item in catalog if item["slug"] == recovered_slug)
    assert record["recovery_only"] is True

    with TestClient(main.app) as client:
        response = client.post(
            f"/api/projects/{recovered_slug}/{action}",
            headers={"X-DevFleet-Token": "test-token"},
            json={},
        )

    assert response.status_code == 409
    assert "require explicit adoption" in response.json()["detail"]


def test_failed_recovered_identity_validation_still_records_recovery_authority(
    monkeypatch, tmp_path
):
    source_slug = "vault-source"
    source_id = "12345678-1234-1234-1234-123456789abc"
    workspaces = tmp_path / "workspaces"
    workspaces.mkdir()
    settings = replace(
        projects.SETTINGS,
        workspaces=workspaces,
        runtime_root=tmp_path / "runtime",
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    recovered_slug = "vault-source-recovered-20260916-123456-deadbeef"
    recovered = workspaces / recovered_slug
    (recovered / ".devfleet").mkdir(parents=True)
    (recovered / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "project_id": source_id,
                "slug": recovered_slug,
                "identity": recovered_slug,
                "runtime_provider": "docker-compose",
                "runtime_id": projects.compose_name(recovered_slug),
                "host_id": "test-node",
                "deployment_id": "deployment-123",
                "lifecycle_status": "stopped",
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(RuntimeError, match="does not match the requested source"):
        projects._validate_recovered_vault_copy(
            source_slug,
            {"project_id": source_id},
            str(recovered),
        )

    assert projects._vault_recovery_marker_path(recovered).is_file()
    with pytest.raises(ValueError, match="require explicit adoption"):
        projects.load_authoritative_project_identity_for_mutation(recovered)
    record = next(
        item
        for item in projects.list_project_catalog()
        if item["slug"] == recovered_slug
    )
    assert record["recovery_only"] is True


def test_recovery_marker_stays_bound_to_lexical_workspace_during_symlink_swap(
    monkeypatch, tmp_path
):
    source_slug = "vault-source"
    source_id = "12345678-1234-1234-1234-123456789abc"
    workspaces = tmp_path / "workspaces"
    workspaces.mkdir()
    settings = replace(
        projects.SETTINGS,
        workspaces=workspaces,
        runtime_root=tmp_path / "runtime",
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    recovered_slug = "vault-source-recovered-20260916-123456-deadbeef"
    recovered = workspaces / recovered_slug
    recovered.mkdir()
    retained = workspaces / "retained-copy"
    external = tmp_path / "external-workspace"
    external.mkdir()
    expected_marker = projects._vault_recovery_marker_path(recovered)
    recovered.rename(retained)
    try:
        recovered.symlink_to(external, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"symlink creation unavailable: {exc}")

    projects._record_vault_recovery_copy(
        recovered,
        source_slug=source_slug,
        source_project_id=source_id,
    )

    marker = json.loads(expected_marker.read_text(encoding="utf-8"))
    assert marker["workspace_path"] == str(recovered.absolute())
    assert expected_marker != projects._vault_recovery_marker_path(external)

    recovered.unlink()
    (recovered / ".devfleet").mkdir(parents=True)
    (recovered / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "project_id": source_id,
                "slug": recovered_slug,
                "identity": recovered_slug,
                "runtime_provider": "docker-compose",
                "runtime_id": projects.compose_name(recovered_slug),
                "host_id": "test-node",
                "deployment_id": "deployment-123",
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="require explicit adoption"):
        projects.load_authoritative_project_identity_for_mutation(recovered)


def test_markerless_owned_project_in_generated_recovery_namespace_is_recovery_only(
    monkeypatch, tmp_path
):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path,
        runtime_root=tmp_path / "runtime",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    slug = "vault-source-recovered-20260916-123456-deadbeef"
    project = tmp_path / slug
    (project / ".devfleet").mkdir(parents=True)
    (project / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "project_id": "12345678-1234-1234-1234-123456789abc",
                "slug": slug,
                "identity": slug,
                "runtime_provider": "docker-compose",
                "runtime_id": projects.compose_name(slug),
                "host_id": "test-node",
                "deployment_id": "deployment-123",
                "lifecycle_status": "stopped",
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="reserved Vault recovery namespace"):
        projects.load_authoritative_project_identity_for_mutation(project)
    record = next(
        item for item in projects.list_project_catalog() if item["slug"] == slug
    )
    assert record["recovery_only"] is True


def test_non_generated_recovery_like_project_name_remains_authoritative(
    monkeypatch, tmp_path
):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path,
        runtime_root=tmp_path / "runtime",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    slug = "x-recovered-20260916-123456-deadbeef"
    project = tmp_path / slug
    (project / ".devfleet").mkdir(parents=True)
    (project / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "project_id": "12345678-1234-1234-1234-123456789abc",
                "slug": slug,
                "identity": slug,
                "runtime_provider": "docker-compose",
                "runtime_id": projects.compose_name(slug),
                "host_id": "test-node",
                "deployment_id": "deployment-123",
                "lifecycle_status": "stopped",
            }
        ),
        encoding="utf-8",
    )

    authoritative = projects.load_authoritative_project_identity_for_mutation(project)
    assert authoritative["slug"] == slug


def test_failed_broker_quarantine_leaves_generated_copy_recovery_only(
    monkeypatch, tmp_path
):
    broker = load_broker_module(monkeypatch)
    source_slug = "vault-source"
    project_id = "12345678-1234-1234-1234-123456789abc"
    workspaces = tmp_path / "workspaces"
    workspaces.mkdir()
    recovered_slug = "vault-source-recovered-20260916-123456-deadbeef"
    recovered = workspaces / recovered_slug
    (recovered / ".devfleet").mkdir(parents=True)
    (recovered / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "project_id": project_id,
                "slug": recovered_slug,
                "identity": recovered_slug,
                "runtime_provider": "docker-compose",
                "runtime_id": projects.compose_name(recovered_slug),
                "host_id": "test-node",
                "deployment_id": "deployment-123",
                "lifecycle_status": "stopped",
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(broker, "WORKSPACES", workspaces)
    monkeypatch.setattr(broker.os, "access", lambda *_args: True)
    monkeypatch.setattr(
        broker,
        "_run_child",
        lambda command, _timeout: subprocess.CompletedProcess(
            command, 0, str(recovered) + "\n", ""
        ),
    )
    monkeypatch.setattr(broker, "_restored_identity_matches", lambda *_args: False)
    monkeypatch.setattr(broker, "_quarantine_invalid_copy", lambda *_args: False)

    receipt = broker._run_fixed_operation("restore-copy", source_slug, project_id)

    assert receipt["ok"] is False
    assert recovered.is_dir()
    settings = replace(
        projects.SETTINGS,
        workspaces=workspaces,
        runtime_root=tmp_path / "runtime",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    with pytest.raises(ValueError, match="reserved Vault recovery namespace"):
        projects.load_authoritative_project_identity_for_mutation(recovered)
    record = next(
        item
        for item in projects.list_project_catalog()
        if item["slug"] == recovered_slug
    )
    assert record["recovery_only"] is True


def test_canonical_vault_restore_requires_exact_confirmation_before_queue(
    monkeypatch, tmp_path
):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path,
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(main, "SETTINGS", settings)
    slug = "canonical-source"
    project = tmp_path / slug
    (project / ".devfleet").mkdir(parents=True)
    (project / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": slug,
                "identity": slug,
                "project_id": "12345678-1234-1234-1234-123456789abc",
                "runtime_provider": "docker-compose",
                "runtime_id": projects.compose_name(slug),
                "host_id": "test-node",
                "deployment_id": "deployment-123",
                "lifecycle_status": "stopped",
            }
        ),
        encoding="utf-8",
    )
    queued = []

    def submit(*args, **kwargs):
        queued.append((args, kwargs))
        return "operation-1"

    monkeypatch.setattr(main, "submit_operation", submit)
    with TestClient(main.app) as client:
        for payload in (
            {"canonical": True},
            {
                "canonical": True,
                "confirm_slug": slug,
                "confirm_phrase": "RESTORE CANONICAL wrong-source",
            },
        ):
            response = client.post(
                f"/api/projects/{slug}/restore-vault",
                headers={"X-DevFleet-Token": "test-token"},
                json=payload,
            )
            assert response.status_code == 400
        assert queued == []

        for invalid_canonical in ("false", 1, {}, []):
            response = client.post(
                f"/api/projects/{slug}/restore-vault",
                headers={"X-DevFleet-Token": "test-token"},
                json={"canonical": invalid_canonical},
            )
            assert response.status_code == 400
            assert "must be a JSON boolean" in response.json()["detail"]
        assert queued == []

        copy_response = client.post(
            f"/api/projects/{slug}/restore-vault",
            headers={"X-DevFleet-Token": "test-token"},
            json={},
        )
        assert copy_response.status_code == 202
        canonical_response = client.post(
            f"/api/projects/{slug}/restore-vault",
            headers={"X-DevFleet-Token": "test-token"},
            json={
                "canonical": True,
                "confirm_slug": slug,
                "confirm_phrase": f"RESTORE CANONICAL {slug}",
            },
        )
        assert canonical_response.status_code == 409
        assert "disabled" in canonical_response.json()["detail"]

    assert len(queued) == 1


def _owned_container_project(root: Path, slug: str) -> Path:
    project = root / slug
    (project / ".devfleet").mkdir(parents=True)
    (project / "compose.yaml").write_text("services: {}\n", encoding="utf-8")
    (project / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": slug,
                "identity": slug,
                "project_id": "12345678-1234-1234-1234-123456789abc",
                "runtime_provider": "docker-compose",
                "runtime_id": projects.compose_name(slug),
                "host_id": "test-node",
                "deployment_id": "deployment-123",
                "lifecycle_status": "stopped",
            }
        ),
        encoding="utf-8",
    )
    return project


def test_identity_bound_commit_rejects_workspace_symlink_swap(monkeypatch, tmp_path):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path,
        runtime_root=tmp_path / "runtime",
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    project = _owned_container_project(tmp_path, "commit-source")
    replacement = _owned_container_project(tmp_path, "commit-replacement")
    candidate = projects.load_authoritative_project_identity_for_mutation(project)
    candidate["profile"] = "strict"
    replacement_metadata = (replacement / ".devfleet/project.json").read_bytes()
    retained = tmp_path / "commit-source-retained"
    project.rename(retained)
    try:
        project.symlink_to(replacement, target_is_directory=True)
    except OSError as exc:
        retained.rename(project)
        pytest.skip(f"symlink creation unavailable: {exc}")

    with pytest.raises(ValueError, match="real project workspace"):
        projects.commit_project_metadata(project, candidate)

    assert (replacement / ".devfleet/project.json").read_bytes() == replacement_metadata
    assert json.loads((retained / ".devfleet/project.json").read_text()).get("profile") is None


def test_quarantine_restore_round_trip_uses_embedded_owned_slug(monkeypatch, tmp_path):
    workspaces = tmp_path / "workspaces"
    quarantine = tmp_path / "quarantine"
    workspaces.mkdir()
    settings = replace(
        projects.SETTINGS,
        workspaces=workspaces,
        quarantine=quarantine,
        backup_before_quarantine=False,
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(projects, "stop_project", lambda _slug: "stopped")
    slug = "u04-round-trip"
    original = _owned_container_project(workspaces, slug)
    original_metadata = (original / ".devfleet/project.json").read_bytes()

    quarantined = Path(projects.quarantine_project(slug))
    assert not original.exists()
    assert re.fullmatch(r"[0-9]{8}-[0-9]{6}-" + re.escape(slug), quarantined.name)
    restored = Path(projects.restore_quarantine(quarantined.name))

    assert restored == original
    assert restored.is_dir() and not restored.is_symlink()
    assert not quarantined.exists()
    assert (restored / ".devfleet/project.json").read_bytes() == original_metadata
    assert projects.load_authoritative_project_identity_for_mutation(restored)["slug"] == slug


def test_quarantine_restore_collision_preserves_quarantined_source(monkeypatch, tmp_path):
    workspaces = tmp_path / "workspaces"
    quarantine = tmp_path / "quarantine"
    workspaces.mkdir()
    quarantine.mkdir()
    settings = replace(projects.SETTINGS, workspaces=workspaces, quarantine=quarantine)
    monkeypatch.setattr(projects, "SETTINGS", settings)
    slug = "u04-collision"
    source = quarantine / f"20260916-123456-{slug}"
    _owned_container_project(quarantine, source.name)
    metadata_path = source / ".devfleet/project.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata.update({"slug": slug, "identity": slug, "runtime_id": projects.compose_name(slug)})
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    collision = workspaces / slug
    collision.mkdir()

    with pytest.raises(ValueError, match="already exists"):
        projects.restore_quarantine(source.name)

    assert source.is_dir() and (source / ".devfleet/project.json").is_file()
    assert collision.is_dir()


def test_quarantine_restore_rejects_symlink_source(monkeypatch, tmp_path):
    workspaces = tmp_path / "workspaces"
    quarantine = tmp_path / "quarantine"
    workspaces.mkdir()
    quarantine.mkdir()
    settings = replace(projects.SETTINGS, workspaces=workspaces, quarantine=quarantine)
    monkeypatch.setattr(projects, "SETTINGS", settings)
    slug = "u04-symlink"
    name = f"20260916-123456-{slug}"
    external = tmp_path / "external-quarantine"
    _owned_container_project(tmp_path, external.name)
    metadata_path = external / ".devfleet/project.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata.update({"slug": slug, "identity": slug, "runtime_id": projects.compose_name(slug)})
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    try:
        (quarantine / name).symlink_to(external, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"symlink creation unavailable: {exc}")

    with pytest.raises(FileNotFoundError):
        projects.restore_quarantine(name)

    assert external.is_dir()
    assert not (workspaces / slug).exists()
    assert name not in {item["name"] for item in projects.list_quarantine()}


def test_quarantine_restore_rejects_impossible_timestamp(monkeypatch, tmp_path):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path / "workspaces",
        quarantine=tmp_path / "quarantine",
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    with pytest.raises(ValueError, match="timestamp"):
        projects.restore_quarantine("20261399-256199-demo")


def test_recovered_copy_dashboard_renders_inert_recovery_panel(monkeypatch, tmp_path):
    recovered_slug, _ = _recovered_vm_copy(monkeypatch, tmp_path)
    record = projects.list_project_catalog()[0]
    monkeypatch.setattr(main, "ui", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(main, "ui_csrf_token", lambda *_args, **_kwargs: "test-csrf")
    monkeypatch.setattr(
        main,
        "local_status",
        lambda: {
            "friendly_name": "Test node",
            "node": "test-node",
            "role": "surrogate",
            "projects": [record],
            "operations": [],
        },
    )
    monkeypatch.setattr(main, "cluster_snapshot", lambda: {"nodes": []})

    with TestClient(main.app) as client:
        login = client.get("/login")
        login_csrf = re.search(
            r'name="csrf_token" value="([^"]+)"', login.text
        ).group(1)
        signed_in = client.post(
            "/login",
            data={
                "username": "test",
                "password": "test-password",
                "next": "/",
                "csrf_token": login_csrf,
            },
            follow_redirects=False,
        )
        assert signed_in.status_code == 303
    