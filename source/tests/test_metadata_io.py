from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

from devfleet import metadata_io


POSIX_ONLY = pytest.mark.skipif(
    not metadata_io.POSIX_FD_HARDENING,
    reason="descriptor-relative no-follow primitives are unavailable",
)
PROJECT_ID = "12345678-1234-1234-1234-123456789abc"


@pytest.fixture
def workspace(tmp_path):
    project = tmp_path / "metadata-project"
    (project / ".devfleet").mkdir(parents=True)
    value = {
        "schema_version": 5,
        "managed_by": "devfleet",
        "slug": project.name,
        "identity": project.name,
        "project_id": PROJECT_ID,
        "deployment_id": "deployment-one",
        "host_id": "host-one",
    }
    (project / ".devfleet/project.json").write_bytes(
        (json.dumps(value, indent=1) + "\n\n").encode("utf-8")
    )
    return project


def test_read_write_and_exact_byte_rollback(workspace):
    original = metadata_io.read_project_metadata(workspace)
    assert original.value["project_id"] == PROJECT_ID
    assert original.raw.endswith(b"\n\n")
    assert original.binding.posix is metadata_io.POSIX_FD_HARDENING
    changed = {**original.value, "lifecycle_status": "stopped"}
    updated = metadata_io.write_project_metadata(workspace, changed, expected=original.binding)
    assert updated.same_directory_lineage(original.binding)
    assert updated.file_identity != original.binding.file_identity
    assert metadata_io.read_project_metadata(workspace).value == changed
    rolled_back = metadata_io.write_project_metadata_bytes(workspace, original.raw, expected=updated)
    assert rolled_back.same_directory_lineage(original.binding)
    assert metadata_io.read_project_metadata(workspace).raw == original.raw
    assert list((workspace / ".devfleet").glob(".project.json.*.tmp")) == []


def test_initial_create_and_sequential_updates_require_fresh_bindings(tmp_path):
    project = tmp_path / "new-project"
    project.mkdir()
    binding = metadata_io.write_project_metadata(project, {"version": 1}, create=True)
    newer = metadata_io.write_project_metadata(project, {"version": 2}, expected=binding)
    with pytest.raises(metadata_io.MetadataSafetyError):
        metadata_io.write_project_metadata(project, {"version": 3}, expected=binding)
    metadata_io.write_project_metadata(project, {"version": 3}, expected=newer)
    assert metadata_io.read_project_metadata(project).value == {"version": 3}


def test_existing_metadata_requires_a_prior_binding(workspace):
    before = (workspace / ".devfleet/project.json").read_bytes()
    for kwargs in ({}, {"create": True}):
        with pytest.raises(metadata_io.MetadataSafetyError):
            metadata_io.write_project_metadata(workspace, {"unobserved": True}, **kwargs)
    assert (workspace / ".devfleet/project.json").read_bytes() == before


def test_initial_create_does_not_overwrite_a_racing_entry(tmp_path, monkeypatch):
    project = tmp_path / "new-project"
    project.mkdir()
    operation = "link" if metadata_io.POSIX_FD_HARDENING else "rename"
    original_operation = getattr(metadata_io.os, operation)
    foreign = b'{"foreign": true}\n'
    raced = False

    def raced_commit(source, target, **kwargs):
        nonlocal raced
        (project / ".devfleet/project.json").write_bytes(foreign)
        raced = True
        return original_operation(source, target, **kwargs)

    monkeypatch.setattr(metadata_io.os, operation, raced_commit)
    with pytest.raises(FileExistsError):
        metadata_io.write_project_metadata(project, {"created": True}, create=True)
    assert raced
    assert (project / ".devfleet/project.json").read_bytes() == foreign
    assert list((project / ".devfleet").glob(".project.json.*.tmp")) == []


@pytest.mark.skipif(os.name != "nt", reason="Windows directory-sharing primitives are unavailable")
def test_windows_parent_handles_block_rename_during_replacement(workspace, tmp_path, monkeypatch):
    original = metadata_io.read_project_metadata(workspace)
    original_replace = metadata_io.os.replace
    attempted = False

    def raced_replace(source, target, **kwargs):
        nonlocal attempted
        with pytest.raises(PermissionError):
            (workspace / ".devfleet").rename(tmp_path / "detached")
        attempted = True
        return original_replace(source, target, **kwargs)

    monkeypatch.setattr(metadata_io.os, "replace", raced_replace)
    metadata_io.write_project_metadata(workspace, {"changed": True}, expected=original.binding)
    assert attempted
    assert metadata_io.read_project_metadata(workspace).value == {"changed": True}


def test_writer_rejects_a_binding_from_another_workspace(workspace, tmp_path):
    original = metadata_io.read_project_metadata(workspace)
    other = tmp_path / "other-project"
    shutil.copytree(workspace, other)
    with pytest.raises(metadata_io.MetadataSafetyError):
        metadata_io.write_project_metadata(other, original.value, expected=original.binding)


def test_writer_rejects_in_place_changes_since_the_read(workspace):
    original = metadata_io.read_project_metadata(workspace)
    metadata = workspace / ".devfleet/project.json"
    metadata.write_bytes(original.raw + b" ")
    with pytest.raises(metadata_io.MetadataSafetyError):
        metadata_io.write_project_metadata(workspace, original.value, expected=original.binding)
    assert metadata.read_bytes() == original.raw + b" "


@pytest.mark.parametrize("raw", [b"{", b"\xff", b"[1,2]"])
def test_json_and_unicode_validation_is_explicit(workspace, raw):
    (workspace / ".devfleet/project.json").write_bytes(raw)
    if raw.startswith(b"["):
        record = metadata_io.read_project_metadata(workspace)
        assert record.value == [1, 2]
        assert not metadata_io.metadata_identity_matches(record.value, workspace.name, PROJECT_ID)
    else:
        with pytest.raises((json.JSONDecodeError, UnicodeError)):
            metadata_io.read_project_metadata(workspace)


def test_nonregular_metadata_is_rejected(workspace):
    metadata = workspace / ".devfleet/project.json"
    metadata.unlink()
    metadata.mkdir()
    with pytest.raises(metadata_io.MetadataSafetyError):
        metadata_io.read_project_metadata(workspace)


def test_cli_binds_optional_deployment_and_host_and_is_silent(workspace):
    command = [sys.executable, "-I", str(Path(metadata_io.__file__)),
               "--identity", str(workspace), workspace.name, PROJECT_ID]
    for extra, expected in (([], 0), (["deployment-one"], 0),
                            (["deployment-one", "host-one"], 0),
                            (["wrong-deployment"], 1),
                            (["deployment-one", "wrong-host"], 1)):
        result = subprocess.run(command + extra, capture_output=True, text=True,
                                timeout=10, check=False)
        assert result.returncode == expected, result.stderr
        assert result.stdout == result.stderr == ""
    assert metadata_io.main(["--write", str(workspace)]) == 2


@pytest.mark.parametrize("field,value", [
    ("schema_version", 2), ("schema_version", True), ("managed_by", "foreign"),
    ("slug", "foreign-project"), ("identity", "foreign-project"),
    ("project_id", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
])
def test_identity_validation_fails_closed(workspace, field, value):
    original = metadata_io.read_project_metadata(workspace).value
    assert metadata_io.metadata_identity_matches(original, workspace.name, PROJECT_ID)
    original[field] = value
    assert not metadata_io.metadata_identity_matches(original, workspace.name, PROJECT_ID)


def _prepare_substitution(workspace, tmp_path, component, kind):
    victim = {"workspace": workspace, "directory": workspace / ".devfleet",
              "file": workspace / ".devfleet/project.json"}[component]
    replacement = tmp_path / "replacement"
    if victim.is_dir():
        shutil.copytree(victim, replacement)
    else:
        replacement.write_bytes(victim.read_bytes())
    sentinel = (replacement / ".devfleet/project.json" if component == "workspace"
                else replacement / "project.json" if component == "directory" else replacement)
    sentinel_bytes = sentinel.read_bytes()
    retained = tmp_path / "retained"

    def substitute():
        victim.rename(retained)
        if kind == "symlink":
            victim.symlink_to(replacement, target_is_directory=component != "file")
        else:
            replacement.rename(victim)

    def assert_replacement_unchanged():
        current = sentinel if kind == "symlink" else (
            victim / ".devfleet/project.json" if component == "workspace"
            else victim / "project.json" if component == "directory" else victim
        )
        assert current.read_bytes() == sentinel_bytes

    return victim, retained, substitute, assert_replacement_unchanged


@POSIX_ONLY
@pytest.mark.parametrize("component", ["workspace", "directory", "file"])
@pytest.mark.parametrize("kind", ["symlink", "inode"])
def test_read_rejects_substitution_between_stat_and_open(
    workspace, tmp_path, monkeypatch, component, kind,
):
    victim, _retained, substitute, assert_unchanged = _prepare_substitution(
        workspace, tmp_path, component, kind
    )
    original_open = metadata_io.os.open
    swapped = False

    def raced_open(path, flags, mode=0o777, *, dir_fd=None):
        nonlocal swapped
        if not swapped and dir_fd is not None and os.fspath(path) == victim.name:
            substitute()
            swapped = True
        return original_open(path, flags, mode, dir_fd=dir_fd)

    monkeypatch.setattr(metadata_io.os, "open", raced_open)
    with pytest.raises((metadata_io.MetadataSafetyError, OSError)):
        metadata_io.read_project_metadata(workspace)
    assert swapped
    assert_unchanged()


@POSIX_ONLY
@pytest.mark.parametrize("component", ["workspace", "directory", "file"])
@pytest.mark.parametrize("kind", ["symlink", "inode"])
def test_read_rechecks_binding_after_held_fd_parsing(
    workspace, tmp_path, monkeypatch, component, kind,
):
    _victim, _retained, substitute, assert_unchanged = _prepare_substitution(
        workspace, tmp_path, component, kind
    )
    original_loads = metadata_io.json.loads

    def raced_loads(raw, *args, **kwargs):
        value = original_loads(raw, *args, **kwargs)
        substitute()
        return value

    monkeypatch.setattr(metadata_io.json, "loads", raced_loads)
    with pytest.raises((metadata_io.MetadataSafetyError, OSError)):
        metadata_io.read_project_metadata(workspace)
    assert_unchanged()


@POSIX_ONLY
@pytest.mark.parametrize("component", ["workspace", "directory", "file"])
@pytest.mark.parametrize("kind", ["symlink", "inode"])
def test_writer_rejects_post_read_substitution(
    workspace, tmp_path, component, kind,
):
    original = metadata_io.read_project_metadata(workspace)
    _victim, _retained, substitute, assert_unchanged = _prepare_substitution(
        workspace, tmp_path, component, kind
    )
    substitute()
    with pytest.raises((metadata_io.MetadataSafetyError, OSError)):
        metadata_io.write_project_metadata(workspace, {"changed": True}, expected=original.binding)
    assert_unchanged()


@POSIX_ONLY
@pytest.mark.parametrize("kind", ["symlink", "inode"])
def test_atomic_writer_cannot_redirect_to_a_swapped_parent(
    workspace, tmp_path, monkeypatch, kind,
):
    original = metadata_io.read_project_metadata(workspace)
    _victim, retained, substitute, assert_unchanged = _prepare_substitution(
        workspace, tmp_path, "directory", kind
    )
    original_replace = metadata_io.os.replace
    swapped = False

    def raced_replace(source, target, *, src_dir_fd=None, dst_dir_fd=None):
        nonlocal swapped
        assert src_dir_fd is not None and src_dir_fd == dst_dir_fd
        substitute()
        swapped = True
        return original_replace(source, target, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)

    monkeypatch.setattr(metadata_io.os, "replace", raced_replace)
    with pytest.raises((metadata_io.MetadataSafetyError, OSError)):
        metadata_io.write_project_metadata(workspace, {"changed": True}, expected=original.binding)
    assert swapped
    assert_unchanged()
    assert json.loads((retained / "project.json").read_bytes()) == {"changed": True}
    assert list(retained.glob(".project.json.*.tmp")) == []


@POSIX_ONLY
@pytest.mark.parametrize("kind", ["symlink", "inode"])
def test_writer_aborts_before_commit_when_parent_changes_during_temp_creation(
    workspace, tmp_path, monkeypatch, kind,
):
    original = metadata_io.read_project_metadata(workspace)
    _victim, retained, substitute, assert_unchanged = _prepare_substitution(
        workspace, tmp_path, "directory", kind
    )
    original_open = metadata_io.os.open
    swapped = False

    def raced_open(path, flags, mode=0o777, *, dir_fd=None):
        nonlocal swapped
        if not swapped and dir_fd is not None and os.fspath(path).startswith(".project.json."):
            substitute()
            swapped = True
        return original_open(path, flags, mode, dir_fd=dir_fd)

    monkeypatch.setattr(metadata_io.os, "open", raced_open)
    with pytest.raises((metadata_io.MetadataSafetyError, OSError)):
        metadata_io.write_project_metadata(workspace, {"changed": True}, expected=original.binding)
    assert swapped
    assert_unchanged()
    assert (retained / "project.json").read_bytes() == original.raw
    assert list(retained.glob(".project.json.*.tmp")) == []


@POSIX_ONLY
def test_raced_fifo_open_is_nonblocking_and_rejected(workspace, tmp_path, monkeypatch):
    if not hasattr(os, "mkfifo"):
        pytest.skip("FIFO creation primitive is unavailable")
    original_open = metadata_io.os.open
    victim = workspace / ".devfleet/project.json"
    swapped = False

    def raced_open(path, flags, mode=0o777, *, dir_fd=None):
        nonlocal swapped
        if not swapped and dir_fd is not None and path == "project.json":
            # Assert before calling open so a regression fails instead of hanging pytest.
            assert flags & os.O_NONBLOCK
            victim.rename(tmp_path / "retained")
            os.mkfifo(victim)
            swapped = True
        return original_open(path, flags, mode, dir_fd=dir_fd)

    monkeypatch.setattr(metadata_io.os, "open", raced_open)
    with pytest.raises(metadata_io.MetadataSafetyError):
        metadata_io.read_project_metadata(workspace)
    assert swapped


@POSIX_ONLY
def test_hardlinked_metadata_is_rejected(workspace, tmp_path):
    os.link(workspace / ".devfleet/project.json", tmp_path / "metadata-alias")
    with pytest.raises(metadata_io.MetadataSafetyError, match="hard-link"):
        metadata_io.read_project_metadata(workspace)


@POSIX_ONLY
def test_ancestor_descriptors_preserve_traverse_only_access(workspace, monkeypatch):
    if not hasattr(os, "O_PATH"):
        pytest.skip("traverse-only O_PATH directory descriptors are unavailable")
    original_open = metadata_io.os.open
    seen = False

    def traversal_only_open(path, flags, mode=0o777, *, dir_fd=None):
        nonlocal seen
        if dir_fd is not None and path == workspace.name:
            # Enforce the backup account's traverse-only ancestor contract even
            # when this regression is run by a privileged Linux test account.
            assert flags & os.O_PATH
            seen = True
        return original_open(path, flags, mode, dir_fd=dir_fd)

    monkeypatch.setattr(metadata_io.os, "open", traversal_only_open)
    assert metadata_io.read_project_metadata(workspace).value["project_id"] == PROJECT_ID
    assert seen


@POSIX_ONLY
def test_temp_hardlink_is_rejected_before_replacing_metadata(workspace, tmp_path, monkeypatch):
    original = metadata_io.read_project_metadata(workspace)
    original_stat = metadata_io.os.stat
    raced = False

    def raced_stat(path, *, dir_fd=None, follow_symlinks=True):
        nonlocal raced
        if not raced and dir_fd is not None and os.fspath(path).startswith(".project.json."):
            os.link(path, tmp_path / "temporary-alias", src_dir_fd=dir_fd,
                    follow_symlinks=False)
            raced = True
        return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

    monkeypatch.setattr(metadata_io.os, "stat", raced_stat)
    with pytest.raises(metadata_io.MetadataSafetyError, match="hard-link"):
        metadata_io.write_project_metadata(workspace, {"changed": True}, expected=original.binding)
    assert raced
    assert (workspace / ".devfleet/project.json").read_bytes() == original.raw
    assert list((workspace / ".devfleet").glob(".project.json.*.tmp")) == []
