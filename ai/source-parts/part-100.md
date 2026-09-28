# DevFleet source part 100

Full-source UTF-8 byte interval [4603500, 4650000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: e8441a5271292de2bdf21029427b4267d7ac6a4fb98b3bbc00456522721e77bf

<!-- BEGIN SOURCE SLICE -->
project.json").write_text(
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
 