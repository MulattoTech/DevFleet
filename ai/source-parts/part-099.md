# DevFleet source part 099

Full-source UTF-8 byte interval [4557000, 4603500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: c39168bc5629dc516e355c27c7a976dcd44547985376c72143b011b19e4a4f43

<!-- BEGIN SOURCE SLICE -->
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
        response = client.get(f"/projects/{recovered_slug}")

    assert response.status_code == 200
    assert "RECOVERY ARTIFACT" in response.text
    assert "This restored copy is intentionally inert" in response.text
    assert f'action="/projects/{recovered_slug}/' not in response.text
    assert f'href="/projects/{recovered_slug}?tab=' not in response.text


DEPLOYMENT_ID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
PROJECT_ID = "12345678-1234-4234-9234-123456789abc"


def _canonical_project(monkeypatch, tmp_path, slug="canonical-transfer"):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path / "workspaces",
        quarantine=tmp_path / "quarantine",
        runtime_root=tmp_path / "runtime",
        node_name="devfleet-failover",
        deployment_id=DEPLOYMENT_ID,
    )
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(main, "SETTINGS", settings)
    project = settings.workspaces / slug
    (project / ".devfleet").mkdir(parents=True)
    (project / "compose.yaml").write_text(
        "services:\n  app:\n    image: ubuntu:24.04\n", encoding="utf-8"
    )
    (project / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": slug,
                "identity": slug,
                "project_id": PROJECT_ID,
                "deployment_id": DEPLOYMENT_ID,
                "host_id": "devfleet-primary",
                "runtime_provider": "docker-compose",
                "runtime_isolation": "container",
                "runtime_id": projects.compose_name(slug),
                "lifecycle_status": "stopped",
                "runtime_status": "stopped",
            }
        ),
        encoding="utf-8",
    )
    (project / ".devfleet/ownership-lease.json").write_text(
        json.dumps(
            {
                "project_identity": slug,
                "project_id": PROJECT_ID,
                "active": False,
                "active_node": "devfleet-primary",
                "last_clean_shutdown": "2026-09-16T12:34:56Z",
            }
        ),
        encoding="utf-8",
    )
    return settings, project


@pytest.mark.parametrize(
    ("lease_change", "docker_result", "message"),
    [
        ({"active": True}, (0, ""), "inactive ownership lease"),
        ({"active": 0}, (0, ""), "inactive ownership lease"),
        ({"project_id": "ffffffff-ffff-4fff-8fff-ffffffffffff"}, (0, ""), "inactive ownership lease"),
        ({"last_clean_shutdown": "not-a-time"}, (0, ""), "verified clean shutdown"),
        ({}, (1, ""), "Docker quiescence probe failed"),
        ({}, (0, "container-id\n"), "runtime is still running"),
    ],
)
def test_canonical_restore_quiescence_fails_closed_before_broker(
    monkeypatch, tmp_path, lease_change, docker_result, message
):
    _, project = _canonical_project(monkeypatch, tmp_path)
    lease_path = project / ".devfleet/ownership-lease.json"
    lease = json.loads(lease_path.read_text(encoding="utf-8"))
    lease.update(lease_change)
    lease_path.write_text(json.dumps(lease), encoding="utf-8")
    monkeypatch.setattr(
        projects,
        "run",
        lambda *_args, **_kwargs: subprocess.CompletedProcess(
            _args[0] if _args else [], docker_result[0], docker_result[1], "probe-error"
        ),
    )
    monkeypatch.setattr(
        projects,
        "_vault_request",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("unsafe canonical restore reached Vault broker")
        ),
    )

    with pytest.raises((ValueError, RuntimeError), match=message):
        projects._assert_canonical_restore_quiesced(
            project.name, expected_project_id=PROJECT_ID
        )


def test_vm_canonical_restore_is_blocked_without_runtime_or_broker_probe(
    monkeypatch, tmp_path
):
    _, project = _canonical_project(monkeypatch, tmp_path)
    metadata_path = project / ".devfleet/project.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata.update(
        {
            "runtime_provider": "multipass-host-agent",
            "runtime_isolation": "vm",
            "runtime_id": "devfleet-project-canonical-transfer",
        }
    )
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    forbidden = lambda *_args, **_kwargs: (_ for _ in ()).throw(
        AssertionError("VM canonical restore probed a runtime or Vault broker")
    )
    monkeypatch.setattr(projects, "run", forbidden)
    monkeypatch.setattr(projects, "_vault_request", forbidden)

    with pytest.raises(ValueError, match="stopped-VM attestation"):
        projects._assert_canonical_restore_quiesced(
            project.name, expected_project_id=PROJECT_ID
        )


def _restore_transfer_fixture(
    project: Path, source_slug: str, *, source_host="devfleet-primary"
):
    (project / ".devfleet").mkdir(parents=True, exist_ok=True)
    (project / "compose.yaml").write_text(
        "services:\n  app:\n    image: ubuntu:24.04\n", encoding="utf-8"
    )
    (project / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": source_slug,
                "identity": source_slug,
                "project_id": PROJECT_ID,
                "deployment_id": DEPLOYMENT_ID,
                "host_id": source_host,
                "runtime_provider": "docker-compose",
                "runtime_isolation": "container",
                "runtime_id": projects.compose_name(source_slug),
                "lifecycle_status": "stopped",
                "runtime_status": "stopped",
            }
        ),
        encoding="utf-8",
    )
    (project / ".devfleet/ownership-lease.json").write_text(
        json.dumps(
            {
                "project_identity": source_slug,
                "project_id": PROJECT_ID,
                "active": False,
                "active_node": source_host,
                "last_clean_shutdown": "2026-09-16T12:34:56Z",
            }
        ),
        encoding="utf-8",
    )


def _received_pending_transfer_fixture(monkeypatch, tmp_path, slug):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path / "workspaces",
        runtime_root=tmp_path / "runtime",
        quarantine=tmp_path / "quarantine",
        node_name="devfleet-failover",
        deployment_id=DEPLOYMENT_ID,
    )
    settings.workspaces.mkdir()
    monkeypatch.setattr(projects, "SETTINGS", settings)
    project = settings.workspaces / slug
    staging = settings.workspaces / f"{slug}-recovered-20260916-123456-deadbeef"
    control = {"fail_start": False, "fail_hook": False, "calls": []}

    def runner(args, **_kwargs):
        command = list(args)
        control["calls"].append(command)
        if control["fail_start"] and "up" in command:
            raise RuntimeError("injected destination start failure")
        return subprocess.CompletedProcess(command, 0, "", "")

    def restore(*_args, **_kwargs):
        _restore_transfer_fixture(staging, slug)
        return {
            "ok": True,
            "action": "restore-transfer",
            "project": slug,
            "project_id": PROJECT_ID,
            "deployment_id": DEPLOYMENT_ID,
            "source_host_id": "devfleet-primary",
            "target": str(staging),
        }

    def hook(*_args):
        if control["fail_hook"]:
            raise RuntimeError("injected destination hook failure")
        return ""

    monkeypatch.setattr(projects, "run", runner)
    monkeypatch.setattr(projects, "_vault_request", restore)
    monkeypatch.setattr(projects, "_assert_current_compose_safety", lambda *_args: None)
    monkeypatch.setattr(projects, "_hook", hook)
    projects.receive_transferred_project(
        slug,
        PROJECT_ID,
        DEPLOYMENT_ID,
        "devfleet-primary",
        "devfleet-failover",
    )
    return project, control


def _assert_pending_transfer_state(project):
    metadata = json.loads(
        (project / ".devfleet/project.json").read_text(encoding="utf-8")
    )
    lease = json.loads(
        (project / ".devfleet/ownership-lease.json").read_text(encoding="utf-8")
    )
    assert metadata["transfer_state"] == "pending-source-finalization"
    assert metadata["lifecycle_status"] == "ownership-transfer-pending"
    assert metadata["runtime_status"] == "stopped"
    assert lease["project_id"] == PROJECT_ID
    assert lease["active"] is False
    assert lease["active_node"] == "devfleet-failover"
    assert projects._transfer_pending_marker_path(project).is_file()
    with pytest.raises(ValueError, match="awaits source finalization"):
        projects.load_authoritative_project_identity_for_mutation(project)


def test_receive_transfer_restores_absent_project_and_rebinds_destination(
    monkeypatch, tmp_path
):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path / "workspaces",
        runtime_root=tmp_path / "runtime",
        node_name="devfleet-failover",
        deployment_id=DEPLOYMENT_ID,
    )
    settings.workspaces.mkdir()
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(
        projects,
        "run",
        lambda args, **_kwargs: subprocess.CompletedProcess(args, 0, "", ""),
    )
    slug = "received-project"
    project = settings.workspaces / slug
    staging = settings.workspaces / f"{slug}-recovered-20260916-123456-deadbeef"

    def restore(
        action,
        received_slug,
        received_id,
        *,
        timeout,
        deployment_id,
        source_host_id,
    ):
        assert (action, received_slug, received_id, deployment_id, source_host_id) == (
            "restore-transfer",
            slug,
            PROJECT_ID,
            DEPLOYMENT_ID,
            "devfleet-primary",
        )
        _restore_transfer_fixture(staging, slug)
        return {
            "ok": True,
            "action": action,
            "project": slug,
            "project_id": PROJECT_ID,
            "deployment_id": DEPLOYMENT_ID,
            "source_host_id": "devfleet-primary",
            "target": str(staging),
        }

    monkeypatch.setattr(projects, "_vault_request", restore)

    result = projects.receive_transferred_project(
        slug,
        PROJECT_ID,
        DEPLOYMENT_ID,
        "devfleet-primary",
        "devfleet-failover",
    )

    metadata = json.loads((project / ".devfleet/project.json").read_text())
    lease = json.loads((project / ".devfleet/ownership-lease.json").read_text())
    ownership = projects.ownership_override_path(project).read_text(encoding="utf-8")
    assert result["state"] == "handoff-pending"
    assert metadata["host_id"] == "devfleet-failover"
    assert metadata["runtime_id"] == projects.compose_name(slug)
    assert metadata["transfer_state"] == "pending-source-finalization"
    assert metadata["lifecycle_status"] == "ownership-transfer-pending"
    assert lease["active"] is False and lease["active_node"] == "devfleet-failover"
    assert "devfleet-failover" in ownership and "devfleet-primary" not in ownership
    assert projects._transfer_pending_marker_path(project).is_file()
    with pytest.raises(ValueError, match="awaits source finalization"):
        projects.start_project(slug, override_failover=True)

    monkeypatch.setattr(projects, "_assert_current_compose_safety", lambda *_args: None)
    monkeypatch.setattr(projects, "_hook", lambda *_args: "")
    activated = projects.activate_transferred_project(
        slug,
        PROJECT_ID,
        DEPLOYMENT_ID,
        "devfleet-primary",
        "devfleet-failover",
    )
    metadata = json.loads((project / ".devfleet/project.json").read_text())
    lease = json.loads((project / ".devfleet/ownership-lease.json").read_text())
    assert activated["state"] == "activated-running"
    assert metadata["transfer_state"] == "completed"
    assert metadata["lifecycle_status"] == "running"
    assert lease["active"] is True and lease["active_node"] == "devfleet-failover"
    assert not projects._transfer_pending_marker_path(project).exists()


@pytest.mark.parametrize(
    ("failure_key", "failure_message"),
    [
        ("fail_start", "injected destination start failure"),
        ("fail_hook", "injected destination hook failure"),
    ],
)
def test_activation_startup_failure_retains_pending_authority_and_is_retryable(
    monkeypatch, tmp_path, failure_key, failure_message
):
    project, control = _received_pending_transfer_fixture(
        monkeypatch, tmp_path, f"{failure_key.replace('_', '-')}-transfer"
    )
    control[failure_key] = True

    with pytest.raises(RuntimeError, match=failure_message):
        projects.activate_transferred_project(
            project.name,
            PROJECT_ID,
            DEPLOYMENT_ID,
            "devfleet-primary",
            "devfleet-failover",
        )

    _assert_pending_transfer_state(project)
    assert any(command[-2:] == ["down", "--remove-orphans"] for command in control["calls"])

    control[failure_key] = False
    activated = projects.activate_transferred_project(
        project.name,
        PROJECT_ID,
        DEPLOYMENT_ID,
        "devfleet-primary",
        "devfleet-failover",
    )
    assert activated["state"] == "activated-running"
    assert not projects._transfer_pending_marker_path(project).exists()


def test_post_start_commit_failure_restores_pending_authority_and_is_retryable(
    monkeypatch, tmp_path
):
    project, control = _received_pending_transfer_fixture(
        monkeypatch, tmp_path, "commit-failure-transfer"
    )
    remove_pending = projects._remove_transfer_pending
    failure = {"armed": True}

    def fail_after_marker_removal(current_project, expected):
        remove_pending(current_project, expected)
        if failure["armed"]:
            failure["armed"] = False
            raise RuntimeError("injected post-start activation commit failure")

    monkeypatch.setattr(projects, "_remove_transfer_pending", fail_after_marker_removal)

    with pytest.raises(RuntimeError, match="injected post-start activation commit failure"):
        projects.activate_transferred_project(
            project.name,
            PROJECT_ID,
            DEPLOYMENT_ID,
            "devfleet-primary",
            "devfleet-failover",
        )

    _assert_pending_transfer_state(project)
    assert any(command[-2:] == ["down", "--remove-orphans"] for command in control["calls"])

    activated = projects.activate_transferred_project(
        project.name,
        PROJECT_ID,
        DEPLOYMENT_ID,
        "devfleet-primary",
        "devfleet-failover",
    )
    assert activated["state"] == "activated-running"
    assert not projects._transfer_pending_marker_path(project).exists()


@pytest.mark.parametrize(
    ("pending_field", "pending_value"),
    [
        ("transfer_state", "pending-source-finalization"),
        ("lifecycle_status", "ownership-transfer-pending"),
    ],
)
def test_pending_transfer_metadata_denies_mutation_when_marker_is_deleted(
    monkeypatch, tmp_path, pending_field, pending_value
):
    settings, project = _canonical_project(
        monkeypatch, tmp_path, slug=f"markerless-{pending_field.replace('_', '-')}"
    )
    metadata_path = project / ".devfleet/project.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata[pending_field] = pending_value
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    projects._record_transfer_pending(
        project,
        project_id=PROJECT_ID,
        deployment_id=DEPLOYMENT_ID,
        source_host_id="devfleet-primary",
        destination_host_id="devfleet-failover",
    )
    marker_path = projects._transfer_pending_marker_path(project)
    marker_path.unlink()
    assert not marker_path.exists()
    monkeypatch.setattr(
        projects,
        "run",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("markerless pending transfer reached runtime mutation")
        ),
    )

    with pytest.raises(ValueError, match="awaits source finalization"):
        projects.load_authoritative_project_identity_for_mutation(project)
    with pytest.raises(ValueError, match="awaits source finalization"):
        projects.start_project(project.name, override_failover=True)


def test_receive_transfer_rejects_conflicting_existing_project_before_restore(
    monkeypatch, tmp_path
):
    _, project = _canonical_project(monkeypatch, tmp_path, slug="conflict-project")
    metadata_path = project / ".devfleet/project.json"
    metadata = json.loads(metadata_path.read_text())
    metadata["project_id"] = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    forbidden = lambda *_args, **_kwargs: (_ for _ in ()).throw(
        AssertionError("conflicting destination reached restore")
    )
    monkeypatch.setattr(projects, "_vault_request", forbidden)

    with pytest.raises(ValueError, match="project identity does not match"):
        projects.receive_transferred_project(
            project.name,
            PROJECT_ID,
            DEPLOYMENT_ID,
            "devfleet-primary",
            "devfleet-failover",
        )


def test_receive_transfer_replaces_matching_stopped_destination_transactionally(
    monkeypatch, tmp_path
):
    settings, project = _canonical_project(
        monkeypatch, tmp_path, slug="replace-project"
    )
    settings = replace(settings, quarantine=tmp_path / "quarantine")
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(main, "SETTINGS", settings)
    (project / "prior-sentinel.txt").write_text("prior", encoding="utf-8")
    staging = (
        settings.workspaces
        / "replace-project-recovered-20260916-123456-deadbeef"
    )
    monkeypatch.setattr(
        projects,
        "run",
        lambda args, **_kwargs: subprocess.CompletedProcess(args, 0, "", ""),
    )

    def restore(*_args, **_kwargs):
        _restore_transfer_fixture(staging, "replace-project")
        return {"ok": True, "target": str(staging)}

    monkeypatch.setattr(projects, "_vault_request", restore)
    result = projects.receive_transferred_project(
        "replace-project",
        PROJECT_ID,
        DEPLOYMENT_ID,
        "devfleet-primary",
        "devfleet-failover",
    )

    prior = Path(result["prior_destination_quarantine"])
    assert result["state"] == "handoff-pending"
    assert prior.is_dir() and (prior / "prior-sentinel.txt").read_text() == "prior"
    assert project.is_dir() and not (project / "prior-sentinel.txt").exists()
    metadata = json.loads((project / ".devfleet/project.json").read_text())
    assert metadata["transfer_state"] == "pending-source-finalization"
    assert projects._transfer_pending_marker_path(project).is_file()


def test_receive_transfer_adoption_failure_rolls_back_source_bound_records(
    monkeypatch, tmp_path
):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path / "workspaces",
        runtime_root=tmp_path / "runtime",
        node_name="devfleet-failover",
        deployment_id=DEPLOYMENT_ID,
    )
    settings.workspaces.mkdir()
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(
        projects,
        "run",
        lambda args, **_kwargs: subprocess.CompletedProcess(args, 0, "", ""),
    )
    slug = "rollback-transfer"
    project = settings.workspaces / slug
    staging = settings.workspaces / f"{slug}-recovered-20260916-123456-deadbeef"

    def restore(*_args, **_kwargs):
        _restore_transfer_fixture(staging, slug)
        return {"ok": True, "target": str(staging)}

    monkeypatch.setattr(projects, "_vault_request", restore)
    monkeypatch.setattr(
        projects,
        "write_ownership_override",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            RuntimeError("ownership override failed")
        ),
    )

    with pytest.raises(RuntimeError, match="ownership override failed"):
        projects.receive_transferred_project(
            slug,
            PROJECT_ID,
            DEPLOYMENT_ID,
            "devfleet-primary",
            "devfleet-failover",
        )

    assert not project.exists()
    assert staging.is_dir()
    metadata = json.loads((staging / ".devfleet/project.json").read_text())
    lease = json.loads((staging / ".devfleet/ownership-lease.json").read_text())
    assert metadata["host_id"] == "devfleet-primary"
    assert lease["active_node"] == "devfleet-primary"
    assert not projects.ownership_override_path(staging).exists()


def test_receive_transfer_api_validates_confirmation_and_queues_exact_task(
    monkeypatch, tmp_path
):
    settings = replace(
        main.SETTINGS,
        workspaces=tmp_path / "workspaces",
        runtime_root=tmp_path / "runtime",
        node_name="devfleet-failover",
        deployment_id=DEPLOYMENT_ID,
    )
    monkeypatch.setattr(main, "SETTINGS", settings)
    queued = []

    def submit(*args, **kwargs):
        queued.append((args, kwargs))
        return "receive-operation"

    monkeypatch.setattr(main, "submit_operation", submit)
    payload = {
        "slug": "received-project",
        "project_id": PROJECT_ID,
        "deployment_id": DEPLOYMENT_ID,
        "source_host_id": "devfleet-primary",
        "destination_host_id": "devfleet-failover",
        "confirm_slug": "received-project",
        "confirm_phrase": "RECEIVE TRANSFER received-project",
    }
    with TestClient(main.app) as client:
        rejected = client.post(
            "/api/transfers/receive",
            headers={"X-DevFleet-Token": "test-token"},
            json={**payload, "confirm_phrase": "RECEIVE TRANSFER wrong"},
        )
        accepted = client.post(
            "/api/transfers/receive",
            headers={"X-DevFleet-Token": "test-token"},
            json=payload,
        )
        activate_rejected = client.post(
            "/api/transfers/activate",
            headers={"X-DevFleet-Token": "test-token"},
            json={**payload, "confirm_phrase": "ACTIVATE TRANSFER wrong"},
        )
        activate_accepted = client.post(
            "/api/transfers/activate",
            headers={"X-DevFleet-Token": "test-token"},
            json={
                **payload,
                "confirm_phrase": "ACTIVATE TRANSFER received-project",
            },
        )

    assert rejected.status_code == 400
    assert accepted.status_code == 202
    assert activate_rejected.status_code == 400
    assert activate_accepted.status_code == 202
    assert len(queued) == 2
    receive_args, receive_kwargs = queued[0]
    activate_args, activate_kwargs = queued[1]
    assert receive_args[:2] == ("receive-transfer", "received-project")
    assert receive_kwargs["project_id"] == PROJECT_ID
    assert activate_args[:2] == ("activate-transfer", "received-project")
    assert activate_kwargs["idempotency_key"].endswith(
        ":devfleet-primary:devfleet-failover"
    )

```


## FILE: source/tests/test_v123_vault_restore_transaction.py

SHA256: d13055a62902cdfe9b0ff6ab24dc8e0e3dab1e3fd79b0a21cda26cc01ee84633 | Bytes: 5814 | Git mode: 100644

```
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
WINDOWS_GIT_BASH = Path(r"C:\Program Files\Git\bin\bash.exe")
BASH = WINDOWS_GIT_BASH if WINDOWS_GIT_BASH.is_file() else Path(shutil.which("bash") or "")


def unix(path: Path) -> str:
    value = path.resolve().as_posix()
    return "/" + value[0].lower() + value[2:] if value[1:3] == ":/" else value


def executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")
    path.chmod(0o755)


@pytest.mark.parametrize("rollback_collision", [False, True])
def test_canonical_promotion_failure_preserves_the_prior_workspace(
    tmp_path: Path, rollback_collision: bool
):
    assert BASH.is_file(), "A Bash runtime is required for the shipped restore transaction test."
    lab = tmp_path / "lab"
    bin_dir = lab / "bin"
    workspaces = lab / "workspaces"
    quarantine = lab / "quarantine"
    for directory in (bin_dir, workspaces, quarantine, lab / "etc", lab / "run"):
        directory.mkdir(parents=True)
    project = "vault-source"
    project_id = "12345678-1234-1234-1234-123456789abc"
    canonical = workspaces / project
    (canonical / ".devfleet").mkdir(parents=True)
    (canonical / "original.txt").write_text("prior-canonical\n", encoding="utf-8")
    (canonical / ".devfleet/project.json").write_text(
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
    (lab / "etc/restic.env").write_text("RESTIC_REPOSITORY=test\n", encoding="utf-8")
    (lab / "uuid").write_text("deadbeef-1111-2222-3333-444444444444\n", encoding="utf-8")

    script_text = (ROOT / "linux/devfleet-restore-project").read_text(encoding="utf-8")
    script_text = script_text.replace(
        "set -Eeuo pipefail",
        'set -Eeuo pipefail\nPATH="$DEVFLEET_TEST_BIN:/usr/bin:/bin"',
        1,
    )
    for source, replacement in (
        ("/home/devrunner/.devfleet-quarantine", "${DEVFLEET_TEST_ROOT}/quarantine"),
        ("/home/devrunner/workspaces", "${DEVFLEET_TEST_ROOT}/workspaces"),
        ("/etc/devfleet/restic.env", "${DEVFLEET_TEST_ROOT}/etc/restic.env"),
        ("/run/lock/devfleet-vault-operation.lock", "${DEVFLEET_TEST_ROOT}/run/vault.lock"),
        ("/proc/sys/kernel/random/uuid", "${DEVFLEET_TEST_ROOT}/uuid"),
    ):
        script_text = script_text.replace(source, replacement)
    script = lab / "restore-under-test"
    executable(script, script_text)

    executable(bin_dir / "flock", "#!/usr/bin/env bash\nexit 0\n")
    executable(bin_dir / "python3", "#!/usr/bin/env bash\nexit 0\n")
    executable(
        bin_dir / "jq",
        """#!/usr/bin/env bash
if [[ "$*" == *"--arg slug"* ]]; then
  exit 0
fi
cat >/dev/null
printf 'snap-1\\n'
""",
    )
    executable(
        bin_dir / "restic",
        """#!/usr/bin/env bash
if [[ "${1:-}" == snapshots ]]; then
  printf '[{"id":"snap-1","time":"2026-09-16T00:00:00Z"}]\\n'
  exit 0
fi
target=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --target ]]; then target=$2; shift 2; continue; fi
  shift
done
source_dir="$targe