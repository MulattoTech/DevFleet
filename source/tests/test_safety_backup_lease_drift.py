import json
from types import SimpleNamespace

import pytest

from devfleet import projects


def test_safety_backup_allows_its_own_lease_update_but_binds_later_lease_drift(tmp_path, monkeypatch):
    slug = "lease-race"
    project = tmp_path / "workspaces" / slug
    metadata = project / ".devfleet"
    metadata.mkdir(parents=True)
    (metadata / "project.json").write_text("{}", encoding="utf-8")
    lease = metadata / "ownership-lease.json"
    lease.write_text('{"last_backup":"old"}', encoding="utf-8")
    (project / "README.md").write_text("stable", encoding="utf-8")
    backup = tmp_path / "backup.tar.gz"
    backup.write_bytes(b"verified archive")
    sha = "a" * 64
    identity = {
        "project_id": "12345678-1234-1234-1234-123456789012",
        "runtime_provider": "docker-compose",
        "slug": slug,
    }
    monkeypatch.setattr(projects, "SETTINGS", SimpleNamespace(workspaces=tmp_path / "workspaces"))
    monkeypatch.setattr(projects, "load_authoritative_project_identity_for_mutation", lambda _path: dict(identity))
    monkeypatch.setattr(projects, "_write_project_metadata", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(projects, "load_meta", lambda _path: dict(identity))
    monkeypatch.setattr(projects, "stop_project", lambda _slug: "stopped")
    monkeypatch.setattr(projects, "running", lambda _path: False)
    monkeypatch.setattr(projects, "validate_archive", lambda *_args: {"archive_sha256": sha})
    stable_source = projects._source_state_fingerprint(
        project, include_generated=True, exclude_ownership_lease=True
    )

    def backup_project(_slug, *, consistency_level, destructive):
        assert consistency_level == "quiesced" and destructive
        lease.write_text('{"last_backup":"new"}', encoding="utf-8")
        return json.dumps({"backup_status": "verified", "backup_id": "fresh", "backup_path": str(backup), "backup_sha256": sha})

    monkeypatch.setattr(projects, "backup_project", backup_project)
    binding = projects.safety_backup_project(slug, _lock_held=True)["binding"]
    excluded, full = projects._source_state_fingerprint(
        project,
        include_generated=True,
        exclude_ownership_lease=True,
        return_full_lease_variant=True,
    )
    assert excluded == stable_source
    assert full == projects._source_state_fingerprint(project, include_generated=True)
    assert binding["source_state_fingerprint"] == full
    projects._assert_safety_binding_current(project, binding)

    lease.write_text('{"last_backup":"tampered"}', encoding="utf-8")
    with pytest.raises(RuntimeError, match="workspace changed after the safety backup"):
        projects._assert_safety_binding_current(project, binding)


def test_safety_backup_still_blocks_external_workspace_change(tmp_path, monkeypatch):
    project = tmp_path / "workspaces" / "lease-race"
    (project / ".devfleet").mkdir(parents=True)
    (project / ".devfleet" / "project.json").write_text("{}", encoding="utf-8")
    readme = project / "README.md"
    readme.write_text("stable", encoding="utf-8")
    identity = {"project_id": "12345678-1234-1234-1234-123456789012", "runtime_provider": "docker-compose", "slug": "lease-race"}
    monkeypatch.setattr(projects, "SETTINGS", SimpleNamespace(workspaces=tmp_path / "workspaces"))
    monkeypatch.setattr(projects, "load_authoritative_project_identity_for_mutation", lambda _path: dict(identity))
    monkeypatch.setattr(projects, "_write_project_metadata", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(projects, "stop_project", lambda _slug: "stopped")
    monkeypatch.setattr(projects, "running", lambda _path: False)

    def backup_project(_slug, *, consistency_level, destructive):
        readme.write_text("changed", encoding="utf-8")
        return json.dumps({"backup_status": "verified", "backup_id": "fresh", "backup_sha256": "a" * 64})

    monkeypatch.setattr(projects, "backup_project", backup_project)
    with pytest.raises(RuntimeError, match="workspace changed during the safety backup"):
        projects.safety_backup_project("lease-race", _lock_held=True)
