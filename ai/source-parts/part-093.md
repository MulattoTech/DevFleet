# DevFleet source part 093

Full-source UTF-8 byte interval [4278000, 4324500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: fe9feb5ab2cd6be3f7112d7cb7e18d7f5e8886afad043f621a03a50bd9121fa7

<!-- BEGIN SOURCE SLICE -->
ublic','docker.devices'} <= {x['code'] for x in findings}


def test_loopback_port_allowed():
    findings=analyze('''services:\n  dev:\n    image: ubuntu:24.04\n    ports: [\"127.0.0.1:3000:3000\"]\n    security_opt: [\"no-new-privileges:true\"]\n    healthcheck: {test: [\"CMD\", \"true\"]}\n''')
    assert not has_blockers(findings), findings

def test_symlink_bind_source_outside_project_is_blocked(tmp_path: Path):
    outside=tmp_path/'outside'
    outside.mkdir()
    project=tmp_path/'project'
    project.mkdir()
    try:
        (project/'escape').symlink_to(outside, target_is_directory=True)
    except OSError:
        pytest.skip('Windows test host does not grant symbolic-link creation privilege')
    (project/'compose.yaml').write_text('''services:\n  app:\n    image: alpine:3.20\n    security_opt: [no-new-privileges:true]\n    volumes:\n      - ./escape:/data\n    ports:\n      - 127.0.0.1:8080:80\n''')
    findings=analyze_project(project)
    assert has_blockers(findings)
    assert any(x['code']=='docker.mount-resolution' for x in findings)


def test_rebuild_context_symlink_outside_project_is_blocked(tmp_path: Path):
    outside=tmp_path/'outside-build'
    outside.mkdir()
    project=tmp_path/'project'
    project.mkdir()
    try:
        (project/'escape-build').symlink_to(outside, target_is_directory=True)
    except OSError:
        pytest.skip('Windows test host does not grant symbolic-link creation privilege')
    (project/'compose.yaml').write_text('''services:\n  app:\n    build: ./escape-build\n    security_opt: [no-new-privileges:true]\n    ports:\n      - 127.0.0.1:8080:80\n''')
    findings=analyze_project(project)
    assert has_blockers(findings)
    assert any(x['code']=='docker.build-context' for x in findings)

```


## FILE: source/tests/test_analyzer_v11.py

SHA256: 11738fb7c631b7c0d2de4d70956ce3e458f5b0aed5d302702ff7bb60ee484ccb | Bytes: 4024 | Git mode: 100644

```
from pathlib import Path
import pytest
from devfleet.analyzer import analyze_project,has_blockers
def project(tmp_path,text):
 p=tmp_path/'demo';p.mkdir();(p/'compose.yaml').write_text(text);return p
def test_windows_mount_blocked(tmp_path):assert has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    volumes: ["C:\\\\Users:/host"]\n'),'balanced',True))
def test_parent_mount_blocked(tmp_path):assert has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    volumes: ["../:/host"]\n'),'fast',True))
def test_docker_socket_blocked_in_fast(tmp_path):assert has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    volumes: ["/var/run/docker.sock:/var/run/docker.sock"]\n'),'fast',True))
def test_loopback_port_allowed_balanced(tmp_path):assert not has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    ports: ["127.0.0.1:3000:3000"]\n    healthcheck: {test: ["CMD","true"]}\n    security_opt: ["no-new-privileges:true"]\n'),'balanced',True))
def test_tailnet_allowed_balanced(tmp_path):assert not has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    ports: ["100.64.1.2:3000:3000"]\n    healthcheck: {test: ["CMD","true"]}\n    security_opt: ["no-new-privileges:true"]\n'),'balanced',True))
def test_public_port_blocked(tmp_path):assert has_blockers(analyze_project(project(tmp_path,'services:\n  x:\n    image: x:1\n    ports: ["3000:3000"]\n'),'fast',True))
def test_symlink_escape_blocked(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    image: x:1\n')
 try:(p/'escape').symlink_to(tmp_path)
 except OSError:pytest.skip('Windows test host does not grant symbolic-link creation privilege')
 assert has_blockers(analyze_project(p,'balanced',True))
def test_cache_invalidates(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    image: x:1\n    ports: ["127.0.0.1:3000:3000"]\n');a=analyze_project(p,'balanced');(p/'compose.yaml').write_text('services:\n  x:\n    image: x:1\n    ports: ["3000:3000"]\n');b=analyze_project(p,'balanced');assert a!=b and has_blockers(b)

def test_balanced_hardening_items_are_warnings(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    build: .\n    ports: ["127.0.0.1:3000:3000"]\n');(p/'Dockerfile').write_text('FROM alpine:3.20\nRUN true\n')
 findings=analyze_project(p,'balanced',True)
 by_code={x['code']:x['severity'] for x in findings}
 assert by_code['docker.healthcheck']=='warning'
 assert by_code['docker.no-new-privileges']=='warning'
 assert by_code['docker.non-root-user']=='warning'
 assert not has_blockers(findings)

def test_strict_hardening_items_block(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    build: .\n');(p/'Dockerfile').write_text('FROM alpine:3.20\n')
 assert has_blockers(analyze_project(p,'strict',True))

def test_fast_device_requires_project_acknowledgement(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    image: alpine:3.20\n    devices: ["/dev/kvm:/dev/kvm"]\n    ports: ["127.0.0.1:3000:3000"]\n    healthcheck: {test: ["CMD","true"]}\n    security_opt: ["no-new-privileges:true"]\n')
 (p/'.devfleet').mkdir();(p/'.devfleet/project.json').write_text('{"profile":"fast","allow_devices":false}')
 assert has_blockers(analyze_project(p,'fast',True))
 (p/'.devfleet/project.json').write_text('{"profile":"fast","allow_devices":true}')
 assert not has_blockers(analyze_project(p,'fast',True))

def test_cache_invalidates_when_referenced_environment_file_changes(tmp_path):
 p=project(tmp_path,'services:\n  x:\n    image: alpine:3.20\n    env_file: config/runtime-settings\n    ports: ["127.0.0.1:3000:3000"]\n    healthcheck: {test: ["CMD","true"]}\n    security_opt: ["no-new-privileges:true"]\n')
 (p/'config').mkdir();env=p/'config/runtime-settings';env.write_text('MODE=one\n')
 analyze_project(p,'balanced');cache=p/'.devfleet/runtime/analyzer-cache.json';first=cache.read_text()
 env.write_text('MODE=two-with-different-size\n')
 analyze_project(p,'balanced');assert cache.read_text()!=first

```


## FILE: source/tests/test_audit5_destructive.py

SHA256: 3ce81d650d6d41c7d18b76194d7eefe01feeb1231d80f772051ef845003f0ec1 | Bytes: 5863 | Git mode: 100644

```
from __future__ import annotations

import hashlib
import os
import tarfile
from pathlib import Path

import pytest
from types import SimpleNamespace

from devfleet import projects
from devfleet.workspace_archives import (
    create_workspace_archive,
    restore_workspace_archive,
    write_backup_manifest,
)


def _hash_tree(root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        result[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def _metadata(source: Path) -> None:
    metadata = source / ".devfleet" / "project.json"
    metadata.parent.mkdir(parents=True, exist_ok=True)
    metadata.write_text('{"schema_version":3,"managed_by":"devfleet","project_id":"12345678-1234-1234-1234-123456789012","slug":"demo","runtime_provider":"docker-compose","host_id":"test-node"}', encoding="utf-8")


def test_destructive_backup_preserves_generated_looking_user_files(tmp_path: Path):
    source = tmp_path / "source"
    _metadata(source)
    for relative, data in {
        "build/irreplaceable.bin": b"build-user-data",
        "dist/manual-output.dat": b"dist-user-data",
        "node_modules/user-preserved-test.txt": b"node-user-data",
        ".next/notes.txt": b"next-user-data",
        "arbitrary/nested-generated-looking/file.txt": b"nested-user-data",
    }.items():
        path = source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    archive = tmp_path / "backup.tar.gz"
    result = create_workspace_archive(source, "demo", archive, include_generated=True, consistency_level="quiesced")
    assert result["omitted_paths"] == []
    assert result["included_file_count"] == 6
    restored = tmp_path / "restored"
    restore_workspace_archive(archive, restored, "demo")
    assert _hash_tree(source) == _hash_tree(restored)


def test_routine_backup_keeps_documented_generated_directory_omission(tmp_path: Path):
    source = tmp_path / "source"
    _metadata(source)
    (source / "build").mkdir(parents=True)
    (source / "build" / "cache.bin").write_bytes(b"cache")
    archive = tmp_path / "routine.tar.gz"
    result = create_workspace_archive(source, "demo", archive)
    assert "build" in result["omitted_paths"]
    with tarfile.open(archive, "r:gz") as bundle:
        assert "demo/build/cache.bin" not in bundle.getnames()


@pytest.mark.skipif(os.name != "posix", reason="POSIX permission fidelity is unavailable on Windows")
def test_restore_preserves_safe_modes_and_strips_special_bits(tmp_path: Path):
    source = tmp_path / "source"
    source.mkdir()
    _metadata(source)
    executable = source / "hook.sh"
    private = source / "private.key"
    executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    private.write_text("secret", encoding="utf-8")
    os.chmod(executable, 0o755)
    os.chmod(private, 0o600)
    archive = tmp_path / "modes.tar.gz"
    create_workspace_archive(source, "demo", archive, include_generated=True)

    # Make the archive metadata hostile.  Restore must mask privilege-bearing
    # special bits while retaining ordinary permissions.
    rewritten = tmp_path / "hostile.tar.gz"
    with tarfile.open(archive, "r:gz") as original, tarfile.open(rewritten, "w:gz") as target:
        for member in original.getmembers():
            member.mode |= 0o6000
            if member.name.endswith("hook.sh"):
                member.mode = 0o6755
            source_file = original.extractfile(member) if member.isfile() else None
            target.addfile(member, source_file)
            if source_file is not None:
                source_file.close()

    restored = tmp_path / "restored"
    restore_workspace_archive(rewritten, restored, "demo")
    assert (restored / "hook.sh").stat().st_mode & 0o777 == 0o755
    assert (restored / "private.key").stat().st_mode & 0o777 == 0o600


def test_restore_deleted_project_uses_tombstone_and_exact_identity(tmp_path: Path, monkeypatch):
    workspaces = tmp_path / "workspaces"
    runtime = tmp_path / "runtime"
    settings = SimpleNamespace(workspaces=workspaces, runtime_root=runtime, host_id="test-node")
    monkeypatch.setattr(projects, "SETTINGS", settings)
    source = tmp_path / "source"
    _metadata(source)
    (source / "build").mkdir()
    (source / "build" / "irreplaceable.bin").write_bytes(b"keep")
    backup_dir = runtime / "workspace-backups" / "demo-backup"
    archive = backup_dir / "demo.tar.gz"
    result = create_workspace_archive(source, "demo", archive, include_generated=True, consistency_level="quiesced")
    write_backup_manifest(
        backup_dir,
        slug="demo",
        project_id="12345678-1234-1234-1234-123456789012",
        runtime={"provider": "docker-compose", "runtime_id": ""},
        archive=result,
        consistency_level="quiesced",
    )
    tombstone = {
        "project_id": "12345678-1234-1234-1234-123456789012",
        "slug": "demo",
        "runtime_provider": "docker-compose",
        "backup_id": "demo-backup",
        "backup_sha256": result["archive_sha256"],
    }
    tombstone_path = projects._recovery_tombstone_path("demo", tombstone["project_id"])
    tombstone_path.parent.mkdir(parents=True, exist_ok=True)
    tombstone_path.write_text(__import__("json").dumps(tombstone), encoding="utf-8")
    recovered = projects.restore_deleted_project(
        "demo", "demo-backup", project_id=tombstone["project_id"], confirm_restore=True
    )
    assert recovered["ok"] is True
    assert (workspaces / "demo" / "build" / "irreplaceable.bin").read_bytes() == b"keep"
    with pytest.raises(ValueError, match="absent destination"):
        projects.restore_deleted_project(
            "demo", "demo-backup", project_id=tombstone["project_id"], confirm_restore=True
        )

```


## FILE: source/tests/test_audit_coherence.py

SHA256: 58d8a589d22f1d4ff33419dbee2864b9a56fe5a9b4a6ffcf4fdc6d1079156e57 | Bytes: 36369 | Git mode: 100644

```
from __future__ import annotations

import copy
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from types import SimpleNamespace

import pytest
import importlib.util

_VALIDATOR_PATH = Path(__file__).parents[1] / "tools" / "validate_audit_coherence.py"
_SPEC = importlib.util.spec_from_file_location("validate_audit_coherence", _VALIDATOR_PATH)
assert _SPEC and _SPEC.loader
_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MODULE)
validate_root = _MODULE.validate_root

_AI_VALIDATOR_PATH = Path(__file__).parents[1] / "tools" / "validate_ai_audit_bundle.py"
_AI_SPEC = importlib.util.spec_from_file_location("validate_ai_audit_bundle", _AI_VALIDATOR_PATH)
assert _AI_SPEC and _AI_SPEC.loader
_AI_MODULE = importlib.util.module_from_spec(_AI_SPEC)
_AI_SPEC.loader.exec_module(_AI_MODULE)

ROOT = Path(__file__).parents[2]

_COMPUTE_SPEC = importlib.util.spec_from_file_location("compute_shipping_input_identity", ROOT / "tools/compute_shipping_input_identity.py")
assert _COMPUTE_SPEC and _COMPUTE_SPEC.loader
_COMPUTE_MODULE = importlib.util.module_from_spec(_COMPUTE_SPEC)
_COMPUTE_SPEC.loader.exec_module(_COMPUTE_MODULE)

_RELEASE_BUNDLE_SPEC = importlib.util.spec_from_file_location("validate_release_bundle", ROOT / "tools/validate_release_bundle.py")
assert _RELEASE_BUNDLE_SPEC and _RELEASE_BUNDLE_SPEC.loader
_RELEASE_BUNDLE_MODULE = importlib.util.module_from_spec(_RELEASE_BUNDLE_SPEC)
_RELEASE_BUNDLE_SPEC.loader.exec_module(_RELEASE_BUNDLE_MODULE)

def _fixture(tmp_path: Path) -> Path:
    root = tmp_path / "bundle"
    (root / "outputs").mkdir(parents=True)
    (root / "audit").mkdir()
    (root / "source" / "tools").mkdir(parents=True)
    # The validator recomputes release identities from the canonical helper.
    # Keep synthetic extracted fixtures self-contained just like the real
    # bundle; omitting this authority turns valid fixtures into import errors.
    shutil.copy2(ROOT / "source/tools/release_fingerprint.py", root / "source/tools/release_fingerprint.py")
    shutil.copy2(ROOT / "source/tools/hook_modes.py", root / "source/tools/hook_modes.py")
    (root / "installer-source").mkdir(parents=True)
    (root / "source" / "VERSION").write_text("1.2.13", encoding="utf-8")
    (root / "installer-source" / "INSTALLER_VERSION").write_text("1.4.1", encoding="utf-8")
    mode = {"schemaVersion": 1, "defaultMode": "0644", "executableMode": "0755", "executableByContract": []}
    rows = _fixture_shipping_rows(root)
    rows.sort(key=lambda row: (row["root"], row["path"]))
    shipping_identity = _MODULE._shipping_identity(
        {(row["root"], row["path"]): row for row in rows}, mode, "1.2.13", "1.4.1"
    )
    artifacts = {
        "exe": {"name": "exe", "path": "outputs/a.exe", "bytes": 1, "sha256": "a" * 64},
        "tar": {"name": "tar", "path": "outputs/a.tar.gz", "bytes": 2, "sha256": "b" * 64},
        "portable": {"name": "portable", "path": "outputs/a.zip", "bytes": 3, "sha256": "c" * 64},
        "installerSource": {"name": "installerSource", "path": "outputs/a-source.zip", "bytes": 4, "sha256": "d" * 64},
    }
    state = {
        "release_version": "1.2.13",
        "installer_version": "1.4.1",
        "git_commit": "1" * 40,
        "candidate_git_commit": "1" * 40,
        "releaseFingerprintId": "f" * 64,
        "toolingFingerprintId": "e" * 64,
        "shipping_input_identity": shipping_identity,
        "candidate_shipping_input_identity": shipping_identity,
        "source_changed_since_candidate": False,
        "rebuild_required": False,
        "candidate_is_current": True,
        "candidate_build_current": True,
        "validation_evidence_current": True,
        "full_release_passed": False,
        "physical_surrogate_certification_current": False,
        "internal_promotion_allowed": False,
        "public_promotion_allowed": False,
        "production_safety": {"production_unchanged": True, "mulattotechsurface_touched": False},
        "candidate": copy.deepcopy(artifacts),
        "gates": {"dependency_matrix": "UNVERIFIED"},
    }
    manifest = {
        "releaseVersion": "1.2.13",
        "installerVersion": "1.4.1",
        "gitCommit": state["git_commit"],
        "candidateGitCommit": state["git_commit"],
        "releaseFingerprintId": state["releaseFingerprintId"],
        "toolingFingerprintId": state["toolingFingerprintId"],
        "sourceChangedSinceCandidate": False,
        "rebuildRequired": False,
        "candidateIsCurrent": True,
        "artifacts": list(artifacts.values()),
        "shippingInputIdentity": shipping_identity,
        "candidateShippingInputIdentity": shipping_identity,
        "shippingModeContract": mode,
        "sourceInventory": [
            {"path": f"{row['root']}/{row['path']}", "bytes": row["bytes"], "sha256": row["sha256"], "mode": row["mode"]}
            for row in rows
        ],
        "expectedSourceCount": len(rows),
    }
    candidate_record = {
        "schemaVersion": 1,
        "candidateCommit": "1" * 40,
        "candidateShippingInputIdentity": shipping_identity,
        "shippingInputIdentity": shipping_identity,
        "candidateShippingInputs": rows,
        "candidateShippingModeContract": mode,
        "shippingModeContract": mode,
        "devfleetVersion": "1.2.13",
        "installerVersion": "1.4.1",
        "releaseFingerprintId": state["releaseFingerprintId"],
        "toolingFingerprintId": state["toolingFingerprintId"],
    }
    state["releaseFingerprintId"] = "f" * 64
    manifest["releaseFingerprintId"] = state["releaseFingerprintId"]
    (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (root / "outputs" / "final-artifact-hashes.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "CURRENT-CANDIDATE.json").write_text(json.dumps(candidate_record), encoding="utf-8")
    return root


def _fixture_shipping_rows(root: Path) -> list[dict]:
    rows = []
    for shipping_root in (root / "source", root / "installer-source"):
        label = shipping_root.name
        for path in sorted(p for p in shipping_root.rglob("*") if p.is_file()):
            relative = path.relative_to(shipping_root).as_posix()
            rows.append({
                "root": label,
                "path": relative,
                "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "mode": "0644",
            })
    rows.sort(key=lambda row: (row["root"], row["path"]))
    return rows


def _write_audit(root: Path, value: dict) -> None:
    (root / "audit" / "record.json").write_text(json.dumps(value), encoding="utf-8")


def _split_identity_fixture(tmp_path: Path, *, differing_head: bool = False) -> Path:
    root = _fixture(tmp_path)
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "outputs/final-artifact-hashes.json").read_text(encoding="utf-8"))
    candidate_record = json.loads((root / "CURRENT-CANDIDATE.json").read_text(encoding="utf-8"))
    candidate = "1" * 40
    head = "2" * 40 if differing_head else candidate
    rows = _fixture_shipping_rows(root)
    mode = {"schemaVersion": 1, "defaultMode": "0644", "executableMode": "0755", "executableByContract": []}
    identity = _MODULE._shipping_identity({(r["root"], r["path"]): r for r in rows}, mode, "1.2.13", "1.4.1")
    state.update({"git_commit": head, "repository_head": head, "candidate_git_commit": candidate, "shipping_input_identity": identity, "candidate_shipping_input_identity": identity, "source_identity_matches_candidate": True, "artifact_tuple_matches_candidate": True, "candidate_build_current": True, "candidate_is_current": True})
    manifest.update({"gitCommit": head, "repositoryHead": head, "candidateGitCommit": candidate, "shippingInputIdentity": identity, "candidateShippingInputIdentity": identity, "shippingModeContract": mode})
    candidate_record.update({"candidateCommit": candidate, "candidateShippingInputIdentity": identity, "shippingInputIdentity": identity, "candidateShippingInputs": rows, "candidateShippingModeContract": mode, "shippingModeContract": mode})
    release = {"schemaVersion": 2, "devfleetVersion": "1.2.13", "installerVersion": "1.4.1", "releaseFingerprintId": state["releaseFingerprintId"], "toolingFingerprint": {"toolingFingerprintId": state["toolingFingerprintId"]}, "shippingModeContract": mode, "shippingInputs": rows, "artifacts": list(manifest["artifacts"])}
    release["releaseFingerprintId"] = _MODULE._release_id(release)
    state["releaseFingerprintId"] = release["releaseFingerprintId"]
    manifest["releaseFingerprintId"] = release["releaseFingerprintId"]
    candidate_record["releaseFingerprintId"] = release["releaseFingerprintId"]
    (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (root / "outputs/final-artifact-hashes.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "CURRENT-CANDIDATE.json").write_text(json.dumps(candidate_record), encoding="utf-8")
    (root / "outputs/release-fingerprint.json").write_text(json.dumps(release), encoding="utf-8")
    manifest["sourceInventory"] = [{"path": f"{row['root']}/{row['path']}", "bytes": row["bytes"], "sha256": row["sha256"], "mode": row["mode"]} for row in rows]
    manifest["expectedSourceCount"] = len(rows)
    # Keep the staged inventory in AUDIT-MANIFEST separate from the artifact
    # manifest, as the real bundle does.
    (root / "AUDIT-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
    return root


def test_coherent_bundle_passes(tmp_path: Path):
    assert validate_root(_fixture(tmp_path))["status"] == "PASS"


def test_split_identity_equal_head_passes(tmp_path: Path):
    assert validate_root(_split_identity_fixture(tmp_path))["status"] == "PASS"


def test_split_identity_tooling_only_head_advance_passes(tmp_path: Path):
    assert validate_root(_split_identity_fixture(tmp_path, differing_head=True))["status"] == "PASS"


def test_shipping_inventory_requires_explicit_canonical_mode(tmp_path: Path):
    root = _split_identity_fixture(tmp_path)
    manifest_path = root / "AUDIT-MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["sourceInventory"][0].pop("mode")
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="missing its canonical mode"):
        validate_root(root)


def test_shipping_inventory_mode_tamper_invalidates_identity(tmp_path: Path):
    root = _split_identity_fixture(tmp_path)
    manifest_path = root / "AUDIT-MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["sourceInventory"][0]["mode"] = "0755"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="sourceInventory disagrees|declared shipping-input identity does not match"):
        validate_root(root)


def test_split_identity_shipping_byte_change_fails(tmp_path: Path):
    root = _split_identity_fixture(tmp_path, differing_head=True)
    manifest = json.loads((root / "AUDIT-MANIFEST.json").read_text(encoding="utf-8"))
    manifest["sourceInventory"][0]["sha256"] = "c" * 64
    manifest["shippingInputIdentity"] = "c" * 64
    (root / "AUDIT-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="unknown or unclassified|source identity|declarations disagree"):
        validate_root(root)


def test_split_identity_unknown_shipping_path_fails_closed(tmp_path: Path):
    root = _split_identity_fixture(tmp_path, differing_head=True)
    manifest = json.loads((root / "AUDIT-MANIFEST.json").read_text(encoding="utf-8"))
    manifest["sourceInventory"].append({"path": "source/unknown.txt", "bytes": 1, "sha256": "c" * 64, "mode": "0644"})
    changed_rows = [
        {"root": "installer-source", "path": "INSTALLER_VERSION", "bytes": 5, "sha256": hashlib.sha256(b"1.4.1").hexdigest(), "mode": "0644"},
        {"root": "source", "path": "VERSION", "bytes": 6, "sha256": hashlib.sha256(b"1.2.13").hexdigest(), "mode": "0644"},
        {"root": "source", "path": "unknown.txt", "bytes": 1, "sha256": "c" * 64, "mode": "0644"},
    ]
    manifest["shippingInputIdentity"] = _MODULE._shipping_identity(
        {(r["root"], r["path"]): r for r in changed_rows}, manifest["shippingModeContract"], "1.2.13", "1.4.1"
    )
    candidate = json.loads((root / "CURRENT-CANDIDATE.json").read_text(encoding="utf-8"))
    candidate["shippingInputIdentity"] = manifest["shippingInputIdentity"]
    (root / "CURRENT-CANDIDATE.json").write_text(json.dumps(candidate), encoding="utf-8")
    (root / "AUDIT-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="sourceInventory disagrees|unknown or unclassified"):
        validate_root(root)


def test_split_identity_artifact_tuple_mismatch_fails(tmp_path: Path):
    root = _split_identity_fixture(tmp_path)
    manifest = json.loads((root / "outputs/final-artifact-hashes.json").read_text(encoding="utf-8"))
    manifest["artifacts"][0]["sha256"] = "0" * 64
    (root / "outputs/final-artifact-hashes.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="artifact manifest"):
        validate_root(root)


def test_split_identity_current_authority_contradiction_fails(tmp_path: Path):
    root = _split_identity_fixture(tmp_path, differing_head=True)
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    state["source_identity_matches_candidate"] = False
    (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    with pytest.raises(ValueError, match="source identity authority|candidateIsCurrent"):
        validate_root(root)


@pytest.mark.parametrize(
    "mutation",
    [
        lambda x: x.update(releaseFingerprintId="0" * 64),
        lambda x: x.update(artifacts={"tar": {"sha256": "0" * 64}}),
        lambda x: x.update(gates={"dependency_matrix": "PASS"}),
        lambda x: x.update(productionUnchanged=False),
        lambda x: x.update(releaseFingerprintId="0" * 64),
    ],
)
def test_current_record_drift_fails(tmp_path: Path, mutation):
    root = _fixture(tmp_path)
    record = {"releaseFingerprintId": "f" * 64, "candidateVersion": "1.2.13", "productionUnchanged": True}
    mutation(record)
    _write_audit(root, record)
    with pytest.raises(ValueError):
        validate_root(root)


def test_historical_record_must_be_explicitly_marked(tmp_path: Path):
    root = _fixture(tmp_path)
    _write_audit(root, {"releaseFingerprintId": "0" * 64, "status": "old evidence"})
    with pytest.raises(ValueError):
        validate_root(root)
    (root / "audit" / "record.json").write_text(json.dumps({"historical": True, "releaseFingerprintId": "0" * 64}), encoding="utf-8")
    assert validate_root(root)["status"] == "PASS"


def test_generated_windows_bom_json_is_accepted(tmp_path: Path):
    root = _fixture(tmp_path)
    (root / "outputs" / "final-artifact-hashes.json").write_bytes(b"\xef\xbb\xbf" + (root / "outputs" / "final-artifact-hashes.json").read_bytes())
    assert validate_root(root)["status"] == "PASS"


def test_canonical_release_state_rejects_contradictory_build_and_rebuild(tmp_path: Path):
    root = _fixture(tmp_path)
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    state.update({"rebuild_required": True, "candidate_build_current": True})
    (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    with pytest.raises(ValueError, match="rebuild"):
        validate_root(root)


def test_canonical_release_state_derives_candidate_identity(tmp_path: Path):
    root = _fixture(tmp_path)
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    state.update({"source_identity_matches_candidate": True, "artifact_tuple_matches_candidate": False, "candidate_is_current": True})
    (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    with pytest.raises(ValueError, match="derived"):
        validate_root(root)


def _write_current_fingerprints(root: Path, *, release_schema: int = 2) -> None:
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    candidate = json.loads((root / "CURRENT-CANDIDATE.json").read_text(encoding="utf-8"))
    artifacts = [{"name": row.get("name", name), **row} for name, row in state["candidate"].items()]
    release = {
        "schemaVersion": release_schema,
        "devfleetVersion": state["release_version"],
        "installerVersion": state["installer_version"],
        "releaseFingerprintId": state["releaseFingerprintId"],
        "toolingFingerprint": {"schemaVersion": 1, "toolingFingerprintId": state["toolingFingerprintId"], "toolingInputs": []},
        "shippingModeContract": candidate["candidateShippingModeContract"],
        "shippingInputs": candidate["candidateShippingInputs"],
        "artifacts": artifacts,
    }
    if release_schema == 2:
        release["releaseFingerprintId"] = _MODULE._release_id(release)
        state["releaseFingerprintId"] = release["releaseFingerprintId"]
        manifest = json.loads((root / "outputs/final-artifact-hashes.json").read_text(encoding="utf-8"))
        manifest["releaseFingerprintId"] = release["releaseFingerprintId"]
        (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
        (root / "outputs/final-artifact-hashes.json").write_text(json.dumps(manifest), encoding="utf-8")
        candidate["releaseFingerprintId"] = release["releaseFingerprintId"]
        (root / "CURRENT-CANDIDATE.json").write_text(json.dumps(candidate), encoding="utf-8")
    tooling = {
        "schemaVersion": 2,
        "releaseFingerprintSchemaVersion": 2,
        "releaseFingerprintId": release["releaseFingerprintId"],
        "toolingFingerprintId": state["toolingFingerprintId"],
        "toolingInputs": [],
        "artifacts": artifacts,
    }
    (root / "outputs/release-fingerprint.json").write_text(json.dumps(release), encoding="utf-8")
    (root / "outputs/tooling-fingerprint-current.json").write_text(json.dumps(tooling), encoding="utf-8")


def test_current_schema_v2_fingerprint_and_tooling_tuple_pass(tmp_path: Path):
    root = _fixture(tmp_path)
    _write_current_fingerprints(root)
    assert validate_root(root)["status"] == "PASS"


def test_schema_v1_is_accepted_only_as_explicit_historical_evidence(tmp_path: Path):
    root = _fixture(tmp_path)
    _write_current_fingerprints(root, release_schema=1)
    with pytest.raises(ValueError, match="historical only"):
        validate_root(root)
    (root / "outputs/release-fingerprint.json").unlink()
    _write_audit(root, {"historical": True, "schemaVersion": 1, "releaseFingerprintId": "0" * 64})
    assert validate_root(root)["status"] == "PASS"


def test_current_tooling_fingerprint_rejects_release_or_artifact_drift(tmp_path: Path):
    root = _fixture(tmp_path)
    _write_current_fingerprints(root)
    path = root / "outputs/tooling-fingerprint-current.json"
    tooling = json.loads(path.read_text(encoding="utf-8"))
    tooling["artifacts"][0]["sha256"] = "0" * 64
    path.write_text(json.dumps(tooling), encoding="utf-8")
    with pytest.raises(ValueError, match="stale"):
        validate_root(root)


def test_all_zero_shipping_declarations_fail_after_recomputation(tmp_path: Path):
    root = _split_identity_fixture(tmp_path)
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "AUDIT-MANIFEST.json").read_text(encoding="utf-8"))
    candidate = json.loads((root / "CURRENT-CANDIDATE.json").read_text(encoding="utf-8"))
    state["shipping_input_identity"] = state["candidate_shipping_input_identity"] = "0" * 64
    manifest["shippingInputIdentity"] = manifest["candidateShippingInputIdentity"] = "0" * 64
    candidate["shippingInputIdentity"] = candidate["candidateShippingInputIdentity"] = "0" * 64
    for path, value in ((root / "finalization-state.json", state), (root / "AUDIT-MANIFEST.json", manifest), (root / "CURRENT-CANDIDATE.json", candidate)):
        path.write_text(json.dumps(value), encoding="utf-8")
    with pytest.raises(ValueError, match="does not match recomputed|malformed"):
        validate_root(root)


def test_missing_shipping_identity_fails_closed(tmp_path: Path):
    root = _split_identity_fixture(tmp_path)
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "AUDIT-MANIFEST.json").read_text(encoding="utf-8"))
    candidate = json.loads((root / "CURRENT-CANDIDATE.json").read_text(encoding="utf-8"))
    state.pop("shipping_input_identity", None)
    state.pop("candidate_shipping_input_identity", None)
    manifest.pop("shippingInputIdentity", None)
    manifest.pop("candidateShippingInputIdentity", None)
    candidate.pop("shippingInputIdentity", None)
    candidate.pop("candidateShippingInputIdentity", None)
    for path, value in ((root / "finalization-state.json", state), (root / "AUDIT-MANIFEST.json", manifest), (root / "CURRENT-CANDIDATE.json", candidate)):
        path.write_text(json.dumps(value), encoding="utf-8")
    with pytest.raises(ValueError, match="identities are required"):
        validate_root(root)


def test_tampered_shipping_row_sha_fails_without_declaration_trust(tmp_path: Path):
    root = _split_identity_fixture(tmp_path)
    candidate = json.loads((root / "CURRENT-CANDIDATE.json").read_text(encoding="utf-8"))
    candidate["candidateShippingInputs"][0]["sha256"] = "0" * 64
    (root / "CURRENT-CANDIDATE.json").write_text(json.dumps(candidate), encoding="utf-8")
    with pytest.raises(ValueError, match="does not match recomputed"):
        validate_root(root)


def test_tampered_release_row_or_fingerprint_fails(tmp_path: Path):
    root = _split_identity_fixture(tmp_path)
    release = json.loads((root / "outputs/release-fingerprint.json").read_text(encoding="utf-8"))
    release["shippingInputs"][0]["sha256"] = "0" * 64
    (root / "outputs/release-fingerprint.json").write_text(json.dumps(release), encoding="utf-8")
    with pytest.raises(ValueError, match="releaseFingerprintId does not match canonical rows"):
        validate_root(root)


@pytest.mark.parametrize("candidate_commit", ["0" * 40, "not-a-commit"])
def test_wrong_candidate_commit_fails_closed(tmp_path: Path, candidate_commit: str):
    root = _split_identity_fixture(tmp_path)
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "outputs/final-artifact-hashes.json").read_text(encoding="utf-8"))
    candidate = json.loads((root / "CURRENT-CANDIDATE.json").read_text(encoding="utf-8"))
    state["candidate_git_commit"] = candidate_commit
    manifest["candidateGitCommit"] = candidate_commit
    candidate["candidateCommit"] = candidate_commit
    (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (root / "outputs/final-artifact-hashes.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "CURRENT-CANDIDATE.json").write_text(json.dumps(candidate), encoding="utf-8")
    with pytest.raises(ValueError, match="candidate commit"):
        validate_root(root)


def test_candidate_identity_tool_uses_commit_tree_not_mutable_release_output(tmp_path: Path):
    workspace = tmp_path / "workspace"
    (workspace / "source/tools").mkdir(parents=True)
    (workspace / "installer-source").mkdir()
    shutil.copy2(ROOT / "source/tools/release_fingerprint.py", workspace / "source/tools/release_fingerprint.py")
    shutil.copy2(ROOT / "source/tools/hook_modes.py", workspace / "source/tools/hook_modes.py")
    (workspace / "source/VERSION").write_text("1.0.0", encoding="utf-8")
    (workspace / "installer-source/INSTALLER_VERSION").write_text("1.0.0", encoding="utf-8")
    subprocess.run(["git", "-C", str(workspace), "init", "-q"], check=True)
    subprocess.run(["git", "-C", str(workspace), "config", "user.email", "test@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(workspace), "config", "user.name", "Test"], check=True)
    subprocess.run(["git", "-C", str(workspace), "add", "source", "installer-source"], check=True)
    subprocess.run(["git", "-C", str(workspace), "commit", "-qm", "candidate"], check=True)
    commit = subprocess.check_output(["git", "-C", str(workspace), "rev-parse", "HEAD"], text=True).strip()
    (workspace / "outputs").mkdir()
    (workspace / "outputs/release-fingerprint.json").write_text(json.dumps({"devfleetVersion": "99.99.99", "shippingInputs": []}), encoding="utf-8")
    result = subprocess.run([sys.executable, str(ROOT / "tools/compute_shipping_input_identity.py"), "--workspace", str(workspace), "--candidate-commit", commit], capture_output=True, text=True, check=True)
    payload = json.loads(result.stdout)
    assert payload["candidateVersion"] == "1.0.0"
    assert payload["candidateShippingInputs"]
    assert all(row["path"] != "outputs/release-fingerprint.json" for row in payload["candidateShippingInputs"])


def _packaged_split_fixture(tmp_path: Path) -> Path:
    """Create a small, complete audit ZIP exercising the extracted validator."""
    root = _split_identity_fixture(tmp_path)
    package_validator = root / "source/tools/validate_audit_coherence.py"
    shutil.copy2(_VALIDATOR_PATH, package_validator)
    package_ai = root / "source/tools/validate_ai_audit_bundle.py"
    shutil.copy2(ROOT / "source/tools/validate_ai_audit_bundle.py", package_ai)
    automation = root / "automation/release-e2e"
    automation.mkdir(parents=True)
    (automation / "runner.ps1").write_text("# packaged test runner\n", encoding="utf-8")

    # Rebuild the complete shipping row set after adding the packaged tools.
    rows = []
    for shipping_root in (root / "source", root / "installer-source"):
        label = shipping_root.name
        for path in sorted(p for p in shipping_root.rglob("*") if p.is_file()):
            relative = path.relative_to(shipping_root).as_posix()
            rows.append({"root": label, "path": relative, "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "mode": "0644"})
    rows.sort(key=lambda row: (row["root"], row["path"]))
    mode = {"schemaVersion": 1, "defaultMode": "0644", "executableMode": "0755", "executableByContract": []}
    identity = _MODULE._shipping_identity({(r["root"], r["path"]): r for r in rows}, mode, "1.2.13", "1.4.1")
    state = json.loads((root / "finalization-state.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "outputs/final-artifact-hashes.json").read_text(encoding="utf-8"))
    candidate = json.loads((root / "CURRENT-CANDIDATE.json").read_text(encoding="utf-8"))
    state.update({"shipping_input_identity": identity, "candidate_shipping_input_identity": identity})
    manifest.update({"devfleetVersion": "1.2.13", "shippingInputIdentity": identity, "candidateShippingInputIdentity": identity, "shippingModeContract": mode, "sourceInventory": [{"path": f"{r['root']}/{r['path']}", "bytes": r["bytes"], "sha256": r["sha256"], "mode": r["mode"]} for r in rows], "expectedSourceCount": len(rows), "compiledArtifactsEmbedded": False})
    candidate.update({"shippingInputIdentity": identity, "candidateShippingInputIdentity": identity, "candidateShippingInputs": rows, "candidateShippingModeContract": mode, "shippingModeContract": mode, "gitCommit": "1" * 40, "repositoryHead": "1" * 40, "candidateIsCurrent": True, "sourceChangedSinceCandidate": False, "rebuildRequired": False})
    candidate.update({"exeSha256": "a" * 64, "tarSha256": "b" * 64, "portableSha256": "c" * 64, "installerSourceSha256": "d" * 64})
    release = {"schemaVersion": 2, "devfleetVersion": "1.2.13", "installerVersion": "1.4.1", "releaseFingerprintId": "", "toolingFingerprint": {"schemaVersion": 1, "toolingFingerprintId": state["toolingFingerprintId"], "toolingInputs": []}, "shippingModeContract": mode, "shippingInputs": rows, "artifacts": manifest["artifacts"]}
    release["releaseFingerprintId"] = _MODULE._release_id(release)
    state["releaseFingerprintId"] = manifest["releaseFingerprintId"] = candidate["releaseFingerprintId"] = release["releaseFingerprintId"]
    tooling = {"schemaVersion": 2, "releaseFingerprintSchemaVersion": 2, "releaseFingerprintId": release["releaseFingerprintId"], "toolingFingerprintId": state["toolingFingerprintId"], "toolingInputs": [], "artifacts": manifest["artifacts"]}
    (root / "finalization-state.json").write_text(json.dumps(state), encoding="utf-8")
    (root / "outputs/final-artifact-hashes.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "CURRENT-CANDIDATE.json").write_text(json.dumps(candidate), encoding="utf-8")
    (root / "outputs/release-fingerprint.json").write_text(json.dumps(release), encoding="utf-8")
    (root / "outputs/tooling-fingerprint-current.json").write_text(json.dumps(tooling), encoding="utf-8")
    (root / "outputs/dependency-advisory-gate.json").write_text("{}", encoding="utf-8")
    (root / "outputs/independent-osv-reconciliation.json").write_text("{}", encoding="utf-8")
    source_paths = sorted([p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and (p.parts[len(root.parts)] in {"source", "installer-source", "automation"}) and p.relative_to(root).parts[0] != "outputs"])
    inventory = []
    for relative in source_paths:
        path = root / relative
        inventory.append({"path": relative, "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "mode": "0644"})
    manifest["sourceInventory"] = inventory
    manifest["expectedSourceCount"] = len(inventory)
    (root / "AUDIT-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "AUDIT-README.md").write_text("packaged validator regression\n", encoding="utf-8")
    (root / "AUDIT-TREE.txt").write_text("\n".join(source_paths) + "\n", encoding="utf-8")
    (root / "SHA256SUMS.txt").write_text("\n".join(f"{row['sha256']}  {row['path']}" for row in inventory) + "\n", encoding="utf-8")
    (root / "SOURCE-MODES.json").write_text(json.dumps([{"path": row["path"], "posixMode": 420} for row in inventory]), encoding="utf-8")
    archive = tmp_path / "fresh-diagnostic.zip"
    with zipfile.ZipFile(archive, "w") as bundle:
        for path in sorted(p for p in root.rglob("*") if p.is_file()):
            relative = path.relative_to(root).as_posix()
            info = zipfile.ZipInfo(relative)
            info.external_attr = 0o644 << 16
            bundle.writestr(info, path.read_bytes())
    return archive


def test_packaged_validator_round_trip_and_tampered_extraction_fail(tmp_path: Path):
    archive = _packaged_split_fixture(tmp_path)
    command = [sys.executable, str(ROOT / "source/tools/validate_ai_audit_bundle.py"), "--archive", str(archive)]
    valid = subprocess.run(command, capture_output=True, text=True)
    assert valid.returncode == 0, valid.stdout + valid.stderr
    assert "COMPLETE_FOR_AI_AUDIT" in valid.stdout

    tampered = tmp_path / "tampered.zip"
    with zipfile.ZipFile(archive) as source, zipfile.ZipFile(tampered, "w") as destination:
        for info in source.infolist():
            data = source.read(info.filename)
            if info.filename == "source/tools/validate_audit_coherence.py":
                data += b"\n# tampered\n"
            destination.writestr(info, data)
    rejected = subprocess.run([*command[:-1], str(tampered)], capture_output=True, text=True)
    assert rejected.returncode != 0


def test_generated_authority_binds_exact_recomputed_substantive_paths():
    state = json.loads((ROOT / "finalization-state.json").read_text(encoding="utf-8"))
    expected = state["authorized_correction"]["shipping_paths"]
    assert expected
    assert expected == sorted(set(expected))
    assert all(path.startswith(("source/", "installer-source/")) for path in expected)
    builder = (ROOT / "tools/Build-AIAuditBundle.ps1").read_text(encoding="utf-8")
    candidate_validator = (ROOT / "source/tools/validate_audit_coherence.py").read_text(encoding="utf-8")
    assert "$substantiveShippingChangedPaths" in builder
    assert "stagedState.authorized_correction.shipping_paths" in builder
    assert "authorized_correction" in candidate_validator
    assert "shipping_paths" in candidate_validator
    assert "allowed != differing_paths" in candidate_validator
    assert "$canonicalMode = if ($mode -eq 493) { '0755' } else { '0644' }" in builder
    assert "sha256=(Get-Hash $file.FullName);mode=$canonicalMode" in builder


def test_candidate_bound_rows_preserve_executable_mode():
    row = {"root": "source", "path": "hooks/run.sh", "bytes": 1, "sha256": "a" * 64, "mode": "0755"}
    rows = _MODULE._shipping_rows([row])
    assert rows[("source", "hooks/run.sh")]["mode"] == "0755"


def test_shipping_identity_ordering_matches_all_three_validators():
    rows = [
        {"root": "source", "path": "templates/python-fastapi/.devfleet/template.json", "bytes": 1, "sha256": "a" * 64, "mode": "0644"},
        {"root": "source", "path": "templates/python/.ai-bridge/chatgpt-memory.md", "bytes": 2, "sha256": "b" * 64, "mode": "0644"},
        {"root": "installer-source", "path": "Setup.csproj", "bytes": 3, "sha256": "c" * 64, "mode": "0644"},
    ]
    mode = {"schemaVersion": 1, "defaultMode": "0644", "executableMode": "0755", "executableByContract": []}
    source_identity = _MODULE._shipping_identity({(row["root"], row["path"]): row for row in rows}, mode, "1.2.13", "1.4.1")
    canonical = _RELEASE_BUNDLE_MODULE._canonical_shipping_rows(rows)
    compute_identity = _COMPUTE_MODULE._shipping_identity({"devfleetVersion": "1.2.13", "installerVersion": "1.4.1", "shippingModeContract": mode, "shippingInputs": canonical})
    release_identity = _RELEASE_BUNDLE_MODULE._candidate_shipping_identity(rows, "1.2.13", "1.4.1", mode)
    assert source_identity == compute_identity == release_identity
    flat = sorted(rows, key=lambda row: