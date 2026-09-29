# DevFleet source part 098

Full-source UTF-8 byte interval [4510500, 4557000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 1fb0fb95204472d614c9560632c6878c24e83515dd14bdd7a246c24e0f495b4d

<!-- BEGIN SOURCE SLICE -->
encoding="utf-8")
    assert "[Security.SecureString]$BundlePassphrase" in source
    assert re.search(r"try\s*\{\s*Expand-EncryptedBundle .* -Passphrase \$BundlePassphrase", source)
    assert "Primary invitation metadata is incomplete." in source
    assert "Vault legacy adoption identity does not match the exact local cluster/credential binding." in source
    assert "finally {\n Remove-Item $dest" in source
    assert "Convert-SecureStringToBundlePassword" not in source


def test_authenticated_bundle_format_and_rejection_guards_are_unchanged():
    create = bundle_function("New-EncryptedBundle")
    expand = bundle_function("Expand-EncryptedBundle")
    assert "$iterations = 600000" in create and "DFENV001" in create
    assert "$aes.Encrypt($nonce, $plain, $cipher, $tag, $header)" in create
    for message in (
        "Encrypted bundle is truncated.",
        "Unsupported encrypted bundle format.",
        "Encrypted bundle KDF parameters are invalid.",
        "Encrypted bundle ciphertext length is invalid.",
    ):
        assert message in expand
    assert "$aes.Decrypt($nonce,$cipher,$tag,$plain,$header)" in expand
    assert expand.index("$aes.Decrypt(") < expand.index("ExtractToDirectory")
    assert "Remove-Item $zipPath -Force -ErrorAction SilentlyContinue" in create
    assert "Remove-Item $zipPath -Force -ErrorAction SilentlyContinue" in expand

```


## FILE: source/tests/test_posix_zip_writer.py

SHA256: 6462892dce04a296322461f1046aa5e87ed72923caff2fad024f04cbdb42fff2 | Bytes: 1182 | Git mode: 100644

```
import json
import zipfile

from source.tools.write_posix_zip import write_zip


def test_zip_writer_marks_unix_origin_and_preserves_contract_modes(tmp_path):
    stage = tmp_path / "stage"
    (stage / "source" / "bin").mkdir(parents=True)
    (stage / "source" / "bin" / "run.sh").write_text("#!/bin/sh\n", encoding="utf-8")
    (stage / "source" / "README.md").write_text("readme\n", encoding="utf-8")
    modes = stage / "SOURCE-MODES.json"
    modes.write_text(
        json.dumps(
            [
                {"path": "source/README.md", "posixMode": 420},
                {"path": "source/bin/run.sh", "posixMode": 493},
            ]
        ),
        encoding="utf-8",
    )
    output = tmp_path / "audit.zip"
    write_zip(stage, output, modes)

    with zipfile.ZipFile(output) as archive:
        entries = {item.filename: item for item in archive.infolist()}
    assert entries["source/README.md"].create_system == 3
    assert entries["source/README.md"].external_attr >> 16 & 0o777 == 0o644
    assert entries["source/bin/run.sh"].create_system == 3
    assert entries["source/bin/run.sh"].external_attr >> 16 & 0o777 == 0o755
    assert "source/" not in entries

```


## FILE: source/tests/test_profiles.py

SHA256: c2b6c38df7c926f5b7e7151be4f2089786a023849ffd9a0a5d5cc0de2e42156c | Bytes: 195 | Git mode: 100644

```
from devfleet.profiles import get_profile
def test_profiles():
 assert get_profile('strict').block_hardening;assert get_profile('balanced').allow_tailnet;assert get_profile('fast').allow_devices

```


## FILE: source/tests/test_project_safety.py

SHA256: eaa01b1294d8f5a0e4b4b4debc59a7cf540305716a90b71dbdfeb9e08fa41187 | Bytes: 673 | Git mode: 100644

```
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def test_backup_before_quarantine_code_order():
 t=(ROOT/'app/devfleet/projects.py').read_text();section=t[t.index('def quarantine_project'):t.index('def list_quarantine')];assert section.index('backup_project')<section.index('project.rename')
def test_restore_canonical_quarantines_old_copy():
 t=(ROOT/'linux/devfleet-restore-project').read_text();assert 'transfer-replaced-' in t and '--canonical' in t
def test_docker_switch_never_migrates_or_deletes_store():
 t=(ROOT/'linux/devfleet-switch-docker-mode').read_text();assert 'Stores were not migrated or deleted' in t and 'docker system prune' not in t

```


## FILE: source/tests/test_release_fingerprint.py

SHA256: c828417c604b08df30002a8af2a26a1070fbdf112b1e7e80dfd8635c883c6dd3 | Bytes: 6392 | Git mode: 100644

```
import json
import os
from pathlib import Path
import shutil

from tools.release_fingerprint import build_fingerprint


def test_shipping_fingerprint_changes_for_shipping_mutation(tmp_path: Path):
    source = tmp_path / "source"
    installer = tmp_path / "installer"
    source.mkdir()
    installer.mkdir()
    (source / "VERSION").write_text("1.2.13\n", encoding="utf-8")
    (source / "payload.sh").write_text("echo one\n", encoding="utf-8")
    (installer / "INSTALLER_VERSION").write_text("1.4.1\n", encoding="utf-8")
    first = build_fingerprint(source, installer)
    (source / "payload.sh").write_text("echo two\n", encoding="utf-8")
    second = build_fingerprint(source, installer)
    assert first["releaseFingerprintId"] != second["releaseFingerprintId"]


def test_nonshipping_harness_is_outside_shipping_fingerprint(tmp_path: Path):
    source = tmp_path / "source"
    installer = tmp_path / "installer"
    automation = tmp_path / "automation"
    source.mkdir()
    installer.mkdir()
    automation.mkdir()
    (source / "VERSION").write_text("1.2.13\n", encoding="utf-8")
    (installer / "INSTALLER_VERSION").write_text("1.4.1\n", encoding="utf-8")
    first = build_fingerprint(source, installer)
    (automation / "harness.ps1").write_text("Write-Output pass\n", encoding="utf-8")
    second = build_fingerprint(source, installer)
    assert first["releaseFingerprintId"] == second["releaseFingerprintId"]
    assert first["toolingFingerprint"]["toolingFingerprintId"] != second["toolingFingerprint"]["toolingFingerprintId"]


def test_fingerprint_json_is_machine_readable(tmp_path: Path):
    source = tmp_path / "source"
    installer = tmp_path / "installer"
    source.mkdir()
    installer.mkdir()
    (source / "VERSION").write_text("1.2.13\n", encoding="utf-8")
    (installer / "INSTALLER_VERSION").write_text("1.4.1\n", encoding="utf-8")
    result = build_fingerprint(source, installer)
    assert result["schemaVersion"] == 2
    assert len(result["releaseFingerprintId"]) == 64
    assert json.loads(json.dumps(result))["devfleetVersion"] == "1.2.13"


def _tree(root: Path) -> tuple[Path, Path, Path]:
    source = root / "source"
    installer = root / "installer"
    outputs = root / "outputs"
    (source / "templates/demo/.devfleet").mkdir(parents=True)
    installer.mkdir()
    outputs.mkdir()
    (source / "VERSION").write_text("1.2.13\n", encoding="utf-8")
    (source / "payload.txt").write_text("same bytes\n", encoding="utf-8")
    (source / "templates/demo/.devfleet/template.json").write_text('{"bootstrap_command":"./.devfleet/run.sh"}\n', encoding="utf-8")
    (source / "templates/demo/.devfleet/run.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (installer / "INSTALLER_VERSION").write_text("1.4.1\n", encoding="utf-8")
    artifact = outputs / "candidate.bin"
    artifact.write_bytes(b"candidate")
    return source, installer, artifact


def test_schema_v2_is_relocation_invariant_and_has_no_absolute_artifact_path(tmp_path: Path):
    source_a, installer_a, artifact_a = _tree(tmp_path / "checkout-a")
    shutil.copytree(tmp_path / "checkout-a", tmp_path / "different absolute checkout")
    source_b = tmp_path / "different absolute checkout/source"
    installer_b = tmp_path / "different absolute checkout/installer"
    artifact_b = tmp_path / "different absolute checkout/outputs/candidate.bin"
    first = build_fingerprint(source_a, installer_a, {"exe": artifact_a})
    second = build_fingerprint(source_b, installer_b, {"exe": artifact_b})
    assert first["releaseFingerprintId"] == second["releaseFingerprintId"]
    assert first["artifacts"] == [{"name": "exe", "bytes": 9, "sha256": first["artifacts"][0]["sha256"]}]
    assert "path" not in first["artifacts"][0]


def test_checkout_mode_noise_does_not_change_canonical_shipping_identity(tmp_path: Path):
    source, installer, artifact = _tree(tmp_path / "checkout")
    first = build_fingerprint(source, installer, {"tar": artifact})
    for path in (source / "payload.txt", source / "templates/demo/.devfleet/run.sh"):
        os.chmod(path, 0o755 if not (path.stat().st_mode & 0o111) else 0o644)
    second = build_fingerprint(source, installer, {"tar": artifact})
    assert first["releaseFingerprintId"] == second["releaseFingerprintId"]


def test_executable_contract_change_is_detected_but_non_executable_mode_noise_is_not(tmp_path: Path):
    source, installer, _ = _tree(tmp_path / "checkout")
    run = "templates/demo/.devfleet/run.sh"
    contracted = build_fingerprint(source, installer, source_executable_paths={run})
    non_executable = build_fingerprint(source, installer, source_executable_paths=set())
    assert contracted["releaseFingerprintId"] != non_executable["releaseFingerprintId"]
    run_entry = next(item for item in contracted["shippingInputs"] if item["root"] == "source" and item["path"] == run)
    assert run_entry["mode"] == "0755"


def test_artifact_byte_mutation_changes_release_id(tmp_path: Path):
    source, installer, artifact = _tree(tmp_path / "checkout")
    first = build_fingerprint(source, installer, {"exe": artifact})
    artifact.write_bytes(b"changed candidate")
    second = build_fingerprint(source, installer, {"exe": artifact})
    assert first["releaseFingerprintId"] != second["releaseFingerprintId"]


def test_release_pipeline_atomically_emits_current_tooling_schema_v2():
    script = (Path(__file__).parents[2] / "installer-source/Build-Release.ps1").read_text(encoding="utf-8")
    assert "releaseFingerprintSchemaVersion=2" in script
    assert "tooling-fingerprint-current.json" in script
    assert "Move-Item -LiteralPath $currentToolingTemporary" in script
    assert "toolingInputs=$fingerprintObject.toolingFingerprint.toolingInputs" in script
    assert "artifacts=$artifactRows" in script


def test_release_pipeline_binds_shipping_identity_into_authority_metadata():
    script = (Path(__file__).parents[2] / "installer-source/Build-Release.ps1").read_text(encoding="utf-8")
    assert "shippingInputIdentity=$candidateIdentity.candidateShippingInputIdentity" in script
    assert "candidateShippingInputIdentity=$candidateIdentity.candidateShippingInputIdentity" in script
    assert "shipping_input_identity=$candidateIdentity.candidateShippingInputIdentity" in script
    assert "candidate_shipping_input_identity=$candidateIdentity.candidateShippingInputIdentity" in script

```


## FILE: source/tests/test_release_reproducibility.py

SHA256: f4af5c9897f923c4579ad5b5ede734d64067968ff58622b1bd25be24dccef66c | Bytes: 3256 | Git mode: 100644

```
from __future__ import annotations

import hashlib
import stat
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).parents[1]
BUILDER = ROOT / "tools" / "build_release.py"
sys.path.insert(0, str(ROOT / "tools"))
from build_release import files


FIXTURE_FILES = {
    "VERSION": b"1.2.13\n",
    "Zeta.txt": b"upper\n",
    "alpha.txt": b"lower\n",
    "app/Cafe.txt": b"ascii\n",
    "app/caf\u00e9.txt": b"unicode\n",
}


def _source(root: Path, names: list[str]) -> Path:
    root.mkdir()
    for name in names:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(FIXTURE_FILES[name])
    return root


def _build(source: Path, old_portable: Path, output: Path, cwd: Path) -> tuple[Path, Path]:
    output.mkdir()
    subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--source",
            str(source),
            "--old-portable",
            str(old_portable),
            "--output-dir",
            str(output),
        ],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    )
    return (
        output / "devfleet-v1.2.13.tar.gz",
        output / "DevFleet-v1.2.13-Portable-Codebase-Verified-r1.zip",
    )


def test_files_use_canonical_utf8_posix_order_independent_of_creation_order(tmp_path: Path):
    names = list(FIXTURE_FILES)
    first = _source(tmp_path / "first", names)
    second = _source(tmp_path / "second", list(reversed(names)))
    expected = sorted(names, key=lambda name: name.encode("utf-8"))
    assert [path.relative_to(first).as_posix() for path in files(first)] == expected
    assert [path.relative_to(second).as_posix() for path in files(second)] == expected


def test_two_clean_room_builds_are_byte_identical_with_normalized_metadata(tmp_path: Path):
    names = list(FIXTURE_FILES)
    first = _source(tmp_path / "source-one", names)
    second = _source(tmp_path / "source-two", list(reversed(names)))
    old_portable = tmp_path / "old-portable.zip"
    with zipfile.ZipFile(old_portable, "w") as archive:
        archive.writestr("historical-note.txt", b"preserved\n")

    first_tar, first_zip = _build(first, old_portable, tmp_path / "output-one", tmp_path)
    second_tar, second_zip = _build(second, old_portable, tmp_path / "output-two", tmp_path / "source-two")
    assert first_tar.read_bytes() == second_tar.read_bytes()
    assert first_zip.read_bytes() == second_zip.read_bytes()
    assert hashlib.sha256(first_tar.read_bytes()).digest() == hashlib.sha256(second_tar.read_bytes()).digest()
    assert hashlib.sha256(first_zip.read_bytes()).digest() == hashlib.sha256(second_zip.read_bytes()).digest()

    with tarfile.open(first_tar, "r:gz") as archive:
        for member in archive.getmembers():
            assert member.mtime == 0
            assert member.uid == member.gid == 0
            assert member.mode in {0o644, 0o755}
    with zipfile.ZipFile(first_zip) as archive:
        for member in archive.infolist():
            assert member.date_time == (1980, 1, 1, 0, 0, 0)
            assert member.create_system == 3
            assert stat.S_IMODE(member.external_attr >> 16) in {0o644, 0o755}

```


## FILE: source/tests/test_remediation_contract.py

SHA256: de0445f35b1c084cd557e7edede914adf0282aa5931dc47fc6dcf86fc00bcdad | Bytes: 6905 | Git mode: 100644

```
from pathlib import Path
from types import SimpleNamespace

import pytest

from devfleet.runtime import CONTAINER_PROVIDER, VM_PROVIDER, provider_for
from devfleet import host_control, workspace_archives
from devfleet.version import __version__
from devfleet.workspace_archives import create_workspace_archive, inspect_workspace, validate_archive, write_backup_manifest, restore_workspace_archive


def test_version_and_provider_contract():
    root = Path(__file__).resolve().parents[1]
    expected = (root / "VERSION").read_text(encoding="utf-8").strip()
    assert expected == "1.2.13"
    assert __version__ == expected
    assert provider_for({}) == CONTAINER_PROVIDER
    assert provider_for({"runtime_provider": "multipass"}) == VM_PROVIDER
    assert provider_for({"runtime_isolation": "vm", "runtime_provider": "docker-compose"}) == VM_PROVIDER


def test_workspace_archive_is_reopenable_and_identity_bound(tmp_path: Path):
    workspace = tmp_path / "demo-project"
    (workspace / ".devfleet").mkdir(parents=True)
    (workspace / ".devfleet" / "project.json").write_text('{"project_id":"123"}\n', encoding="utf-8")
    (workspace / "README.md").write_text("hello\n", encoding="utf-8")
    inspection = inspect_workspace(workspace)
    assert inspection["safe_for_archive"] is True
    archive = tmp_path / "backups" / "demo-project.tar.gz"
    result = create_workspace_archive(workspace, "demo-project", archive)
    assert result["verified"] is True
    assert validate_archive(archive, "demo-project")["archive_sha256"] == result["archive_sha256"]
    manifest = write_backup_manifest(tmp_path / "backups" / "demo-project-1", slug="demo-project", project_id="123", runtime={"provider": "docker-compose"}, archive=result)
    assert manifest["verification"]["status"] == "verified"


def test_workspace_archive_rejects_symbolic_links_when_supported(tmp_path: Path):
    workspace = tmp_path / "demo-project"
    (workspace / ".devfleet").mkdir(parents=True)
    (workspace / ".devfleet" / "project.json").write_text("{}\n", encoding="utf-8")
    link = workspace / "link"
    try:
        link.symlink_to(workspace / ".devfleet" / "project.json")
    except (OSError, NotImplementedError):
        return
    assert inspect_workspace(workspace)["safe_for_archive"] is False


def test_workspace_restore_refuses_cross_filesystem_promotion(tmp_path: Path, monkeypatch):
    workspace = tmp_path / "demo-project"
    (workspace / ".devfleet").mkdir(parents=True)
    (workspace / ".devfleet" / "project.json").write_text("{}\n", encoding="utf-8")
    archive = tmp_path / "demo-project.tar.gz"
    create_workspace_archive(workspace, "demo-project", archive)
    if workspace_archives.POSIX_FD_HARDENING:
        original_open = workspace_archives._open_verified_child

        def different_filesystem(parent_fd, name, expected_type):
            fd, result = original_open(parent_fd, name, expected_type)
            if name == "demo-project":
                result = SimpleNamespace(st_dev=int(result.st_dev) + 1, st_ino=result.st_ino, st_mode=result.st_mode)
            return fd, result

        monkeypatch.setattr(workspace_archives, "_open_verified_child", different_filesystem)
    else:
        monkeypatch.setattr("devfleet.workspace_archives._assert_same_filesystem", lambda *_: (_ for _ in ()).throw(ValueError("different filesystems")))
    with pytest.raises(ValueError, match="different filesystems"):
        restore_workspace_archive(archive, tmp_path / "destination", "demo-project")


def test_workspace_archive_excludes_generated_directories(tmp_path: Path):
    workspace = tmp_path / "demo-project"
    (workspace / ".devfleet").mkdir(parents=True)
    (workspace / ".devfleet" / "project.json").write_text("{}\n", encoding="utf-8")
    (workspace / "node_modules" / "package").mkdir(parents=True)
    (workspace / "node_modules" / "package" / "generated.js").write_text("generated\n", encoding="utf-8")
    (workspace / "README.md").write_text("kept\n", encoding="utf-8")
    inspection = inspect_workspace(workspace)
    assert inspection["generated_dirs"] == ["node_modules"]
    archive = tmp_path / "backups" / "demo-project.tar.gz"
    create_workspace_archive(workspace, "demo-project", archive)
    import tarfile
    with tarfile.open(archive, "r:gz") as handle:
        names = handle.getnames()
    assert "demo-project/README.md" in names
    assert not any(name.startswith("demo-project/node_modules/") for name in names)


def test_host_agent_contract_has_verified_archive_and_fixed_project_commands():
    root = Path(__file__).resolve().parents[1]
    script = (root / "windows" / "DevFleet-HostAgent.ps1").read_text(encoding="utf-8")
    assert "$script:AgentVersion = '2.5.0'" in script
    assert "function Export-ProjectWorkspaceToSource" in script
    assert "archive_sha256" in script
    assert "manifestPath" in script
    assert "Invoke-ProjectCommand" in script
    assert "Invoke-Expression" not in script


def test_project_vm_operations_use_fixed_routes_and_bound_log_tail(monkeypatch):
    captured = {}

    def fake_request(operation, payload, *, runtime_id=""):
        captured.update(operation=operation, payload=payload, runtime_id=runtime_id)
        return {"ok": True, "host_name": "MULATTOTECHBOX"}

    monkeypatch.setattr(host_control, "host_control_request", fake_request)
    result = host_control.project_vm_operation(
        "demo-project",
        "project-logs",
        runtime_id="devfleet-project-demo-project",
        project_id="12345678-1234-1234-1234-123456789012",
        tail=9999,
    )
    assert result["ok"] is True
    assert captured["operation"] == "project-logs"
    assert captured["runtime_id"] == "devfleet-project-demo-project"
    assert captured["payload"]["tail"] == 500


def test_permanent_vm_destroy_requires_artifact_identity():
    with pytest.raises(ValueError, match="identified, hashed"):
        host_control.destroy_project_vm(
            "demo-project",
            "demo-project",
            "DESTROY demo-project",
            runtime_id="devfleet-project-demo-project",
            project_id="12345678-1234-1234-1234-123456789012",
        )


def test_dashboard_has_bounded_logs_and_read_only_preflight_routes():
    root = Path(__file__).resolve().parents[1]
    main = (root / "app" / "devfleet" / "main.py").read_text(encoding="utf-8")
    assert any(marker in main for marker in ("@app.get('/api/projects/{slug}/logs'", '@app.get("/api/projects/{slug}/logs"'))
    assert any(marker in main for marker in ("max(1,min(int(tail),500))", "max(1, min(int(tail), 500))"))
    assert any(marker in main for marker in ("@app.get('/api/projects/{slug}/preflight'", '@app.get("/api/projects/{slug}/preflight"'))
    assert any(marker in main for marker in ("'migration_would_be_performed':False", "'migration_would_be_performed': False", '"migration_would_be_performed": False'))

```


## FILE: source/tests/test_request_admission.py

SHA256: 084475db61c654d14637f96eaec248355c9f4c7d1c7e9c160835f622d62a66fc | Bytes: 6459 | Git mode: 100644

```
import asyncio
import dataclasses
import json

import httpx
from fastapi.testclient import TestClient

from devfleet import core, main
from devfleet.request_guards import API_BODY_LIMIT


async def _asgi_post(
    path,
    chunks,
    *,
    token=None,
    content_length=None,
    peer="100.64.0.5",
    slow=False,
):
    headers = [(b"content-type", b"application/json")]
    if token is not None:
        headers.append((b"x-devfleet-token", token.encode("ascii")))
    if content_length is not None:
        headers.append((b"content-length", str(content_length).encode("ascii")))
    messages = [
        {"type": "http.request", "body": chunk, "more_body": index < len(chunks) - 1}
        for index, chunk in enumerate(chunks)
    ]
    sent = []
    consumed = 0

    async def receive():
        nonlocal consumed
        if slow:
            await asyncio.sleep(0)
        if messages:
            message = messages.pop(0)
            consumed += len(message.get("body", b""))
            return message
        return {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    scope = {
        "type": "http",
        "asgi": {"version": "3.0", "spec_version": "2.3"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "http",
        "path": path,
        "raw_path": path.encode("ascii"),
        "query_string": b"",
        "root_path": "",
        "headers": headers,
        "client": (peer, 31337),
        "server": ("testserver", 80),
        "state": {},
    }
    await main.app(scope, receive, send)
    status = next(
        message["status"]
        for message in sent
        if message.get("type") == "http.response.start"
    )
    return status, consumed


def test_normal_login_and_static_requests_remain_available():
    client = TestClient(main.app)
    assert client.get("/static/app.js").status_code == 200
    assert client.head("/static/app.js").status_code == 200
    response = client.post("/login", data={"username": "bad", "password": "bad", "csrf_token": "bad"})
    assert response.status_code in {401, 403}


def test_declared_and_range_limits_reject_before_expensive_processing():
    client = TestClient(main.app)
    oversized = client.post(
        "/login",
        content=b"x" * (64 * 1024 + 1),
        headers={"content-type": "application/x-www-form-urlencoded"},
    )
    assert oversized.status_code == 413
    assert client.get("/static/app.js", headers={"Range": "bytes=" + ",".join(["1-2"] * 9)}).status_code == 416
    assert client.get("/static/app.js", headers={"Range": "items=0-1"}).status_code == 416


def test_chunked_oversized_login_is_rejected_before_form_parsing():
    async def body():
        yield b"x" * 40_000
        yield b"y" * 40_000

    async def run():
        transport = httpx.ASGITransport(app=main.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.post(
                "/login",
                content=body(),
                headers={"content-type": "application/x-www-form-urlencoded"},
            )

    response = asyncio.run(run())
    assert response.status_code == 413


def test_missing_and_wrong_api_tokens_reject_declared_body_without_consumption():
    body = b"x" * (API_BODY_LIMIT + 1)
    for token in (None, "wrong-token"):
        status, consumed = asyncio.run(
            _asgi_post(
                "/api/projects/create",
                [body],
                token=token,
                content_length=len(body),
            )
        )
        assert status == 401
        assert consumed == 0


def test_missing_and_wrong_api_tokens_reject_chunked_body_without_consumption():
    chunks = [b"x" * 64_000 for _ in range(8)]
    for token in (None, "wrong-token"):
        status, consumed = asyncio.run(
            _asgi_post("/api/projects/create", chunks, token=token)
        )
        assert status == 401
        assert consumed == 0


def test_valid_api_token_allows_small_missing_length_body(monkeypatch):
    monkeypatch.setattr(main, "submit_operation", lambda *args, **kwargs: "op-test")
    body = json.dumps({"slug": "admission-test"}).encode("utf-8")
    status, consumed = asyncio.run(
        _asgi_post("/api/projects/create", [body], token="test-token")
    )
    assert status == 202
    assert consumed == len(body)


def test_valid_api_token_rejects_declared_and_chunked_over_limit_bodies():
    declared = API_BODY_LIMIT + 1
    status, consumed = asyncio.run(
        _asgi_post(
            "/api/projects/create",
            [b"x" * declared],
            token="test-token",
            content_length=declared,
        )
    )
    assert status == 413
    assert consumed == 0

    chunks = [b"x" * 65_536 for _ in range(8)]
    status, consumed = asyncio.run(
        _asgi_post("/api/projects/create", chunks, token="test-token")
    )
    assert status == 413
    assert API_BODY_LIMIT < consumed <= API_BODY_LIMIT + len(chunks[0])
    assert consumed < sum(map(len, chunks))


def test_valid_api_token_rejects_malformed_content_length_without_consumption():
    for content_length in ("not-a-number", "-1"):
        status, consumed = asyncio.run(
            _asgi_post(
                "/api/projects/create",
                [b"{}"],
                token="test-token",
                content_length=content_length,
            )
        )
        assert status == 400
        assert consumed == 0


def test_slow_many_chunk_api_body_stops_at_the_limit():
    chunks = [b"x" * 1024 for _ in range(300)]
    status, consumed = asyncio.run(
        _asgi_post(
            "/api/projects/create",
            chunks,
            token="test-token",
            slow=True,
        )
    )
    assert status == 413
    assert API_BODY_LIMIT < consumed <= API_BODY_LIMIT + len(chunks[0])
    assert consumed < sum(map(len, chunks))


def test_disallowed_network_peer_still_rejects_before_body_or_token_processing(monkeypatch):
    restricted = dataclasses.replace(
        core.SETTINGS,
        public_binding_allowed=False,
        require_tailscale=True,
    )
    monkeypatch.setattr(core, "SETTINGS", restricted)
    body = b"x" * (API_BODY_LIMIT + 1)
    status, consumed = asyncio.run(
        _asgi_post(
            "/api/projects/create",
            [body],
            peer="203.0.113.5",
        )
    )
    assert status == 403
    assert consumed == 0

```


## FILE: source/tests/test_runtime_architecture.py

SHA256: 7fb003753a830ba6f20ece02678ff9a96016cc5b35b6a4a84e04a275d7145b1c | Bytes: 1916 | Git mode: 100644

```
from pathlib import Path

from devfleet.resource_profiles import RESOURCE_PROFILES, recommend_resource_profile, recommend_runtime_isolation, write_resource_override
from devfleet.runtime import CONTAINER_PROVIDER, VM_PROVIDER, provider_for


def test_resource_profiles_are_central_and_include_vm_disk():
    assert set(RESOURCE_PROFILES) == {'small', 'standard', 'large', 'xlarge'}
    assert RESOURCE_PROFILES['standard'].disk_gb == 40
    assert RESOURCE_PROFILES['xlarge'].cpus == 6
    assert recommend_resource_profile(scale='large', intent='production').name == 'large'
    assert recommend_runtime_isolation(scale='large', intent='production') == 'vm'


def test_container_resource_override_is_generated(tmp_path: Path):
    project = tmp_path / 'project'
    project.mkdir()
    compose = project / 'compose.yaml'
    compose.write_text('services:\n  dev:\n    image: ubuntu:24.04\n')
    override = write_resource_override(project, compose, 'standard')
    assert override and override.is_file()
    text = override.read_text()
    assert 'cpus: 2.0' in text
    assert 'mem_limit: 4g' in text
    assert 'pids_limit: 768' in text


def test_runtime_provider_migrates_old_projects_to_container():
    assert provider_for({}) == CONTAINER_PROVIDER
    assert provider_for({'runtime_isolation': 'vm'}) == VM_PROVIDER
    assert provider_for({'runtime_type': 'container'}) == CONTAINER_PROVIDER


def test_host_agent_exposes_only_structured_runtime_operations():
    root = Path(__file__).resolve().parents[1]
    script = (root / 'windows' / 'DevFleet-HostAgent.ps1').read_text()
    assert "'ensure'" in script
    assert "'destroy'" in script
    assert "'capacity'" in script
    assert 'Invoke-Expression' not in script
    assert 'Start-Process' not in script
    assert 'X-DevFleet-Host-Signature' in script
    assert 'X-DevFleet-Host-Token' not in script
    assert 'devfleet-project-$Slug' in script

```


## FILE: source/tests/test_safety_backup_lease_drift.py

SHA256: fb7ee1c2c975d37447ddb4ef91ccb7673adfe7a84f7ba446f7ee6db9c39d2a2a | Bytes: 4109 | Git mode: 100644

```
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

```


## FILE: source/tests/test_security_config.py

SHA256: e372fd0f3ddc6f2c90c244295828ad648abbcca689465ca29f7125d8e86ef6d5 | Bytes: 1020 | Git mode: 100644

```
from __future__ import annotations

import json
from pathlib import Path

import pytest


def test_security_config_malformed_does_not_fall_back_to_defaults(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    from devfleet import core

    path = tmp_path / "config.json"
    path.write_text("{malformed", encoding="utf-8")
    monkeypatch.setattr(core, "CONFIG_PATH", path)
    with pytest.raises(ValueError, match="refusing fail-open defaults"):
        core.load_settings()


def test_security_config_valid_policy_is_loaded_without_mutation(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    from devfleet import core

    path = tmp_path / "config.json"
    path.write_text(json.dumps({"node_name": "test", "require_tailscale": True, "public_binding_allowed": False}), encoding="utf-8")
    monkeypatch.setattr(core, "CONFIG_PATH", path)
    settings = core.load_settings()
    assert settings.node_name == "test"
    assert settings.require_tailscale is True
    assert settings.public_binding_allowed is False

```


## FILE: source/tests/test_security_poison_harness.py

SHA256: 3b38b5f668c5cf6e9868778a365f16a7b105f95b38e861a1165d8797d3e32744 | Bytes: 1636 | Git mode: 100644

```
import json
from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_security_poison_has_a_dedicated_phase_executor_and_schema():
    config = json.loads((ROOT / "automation/release-e2e/config/devfleet-e2e.defaults.json").read_text(encoding="utf-8"))
    executor = config["FullReleaseExecutors"]["SECURITY-POISON"]
    assert config["HarnessVersion"] == "1.5.0"
    assert executor.endswith("Invoke-SecurityPoisonPhase.ps1")
    assert "Invoke-HostAgentPhase" not in executor
    source = (ROOT / executor).read_text(encoding="utf-8")
    for scenario in (
        "DEPENDENCY-TRUST",
        "PROVISIONING-OWNERSHIP",
        "HOST-AGENT-PROTOCOL",
        "PROJECT-MUTATION-AUTHORITY",
        "SSH-READINESS",
        "SECURITY-CONFIGURATION",
        "PACKAGE-WATCHDOG",
    ):
        assert scenario in source
    assert "REAL E2E PASS" in source
    assert "Invoke-ActualWpfAction" not in source


def test_primary_and_linux_do_not_alias_generic_wpf_fresh_install():
    config = json.loads((ROOT / "automation/release-e2e/config/devfleet-e2e.defaults.json").read_text(encoding="utf-8"))
    assert config["FullReleaseExecutors"]["PRIMARY"].endswith("Invoke-PrimaryPhase.ps1")
    assert config["FullReleaseExecutors"]["LINUX"].endswith("Invoke-LinuxPhase.ps1")
    primary = (ROOT / config["FullReleaseExecutors"]["PRIMARY"]).read_text(encoding="utf-8")
    linux = (ROOT / config["FullReleaseExecutors"]["LINUX"]).read_text(encoding="utf-8")
    assert "Invoke-PrimaryRolePhase" in primary
    assert "Invoke-ActualWpfAction $context 'FreshInstall'" not in linux
    assert "Invoke-LinuxBootstrapPhase" in linux

```


## FILE: source/tests/test_transitive_hook_closure.py

SHA256: e1284a9228410bb613bd8f942caf99d554e69d34d90f5e85e06a38f156531590 | Bytes: 1660 | Git mode: 100644

```
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from hook_modes import executable_template_hook_closure, hook_mode_manifest


def test_executable_hook_closure_includes_transitive_health_dependencies() -> None:
    closures = executable_template_hook_closure(ROOT)
    assert len(set().union(*(item.executable for item in closures.values()))) == 78
    assert all(item.transitive for item in closures.values() if item.direct and item.transitive)
    assert "templates/node/.devfleet/smoke-test.sh" in set().union(*(item.executable for item in closures.values()))


def test_hook_manifest_classifies_every_template_script() -> None:
    manifest = hook_mode_manifest(ROOT)
    scripts = list((ROOT / "templates").glob("*/.devfleet/*.sh"))
    assert len(manifest["classification"]) == len(scripts)
    assert set(manifest["classification"].values()) <= {
        "executable-by-contract",
        "non-executable-source/helper",
    }
    assert manifest["count"] == 78


def test_hook_closure_rejects_unsafe_local_reference(tmp_path: Path) -> None:
    template = tmp_path / "templates" / "fixture" / ".devfleet"
    template.mkdir(parents=True)
    (template / "template.json").write_text(
        json.dumps({"health_command": "./.devfleet/health-check.sh"}), encoding="utf-8"
    )
    (template / "health-check.sh").write_text("#!/usr/bin/env bash\n./.devfleet/../outside.sh\n", encoding="utf-8")
    with pytest.raises(ValueError, match="unsafe local hook reference"):
        executable_template_hook_closure(tmp_path)

```


## FILE: source/tests/test_upgrade_preservation.py

SHA256: bc0b93eb5559346b2781139dbcaf21b98e1d7628e677630402f78b40e1e67763 | Bytes: 1058 | Git mode: 100644

```
from pathlib import Path
from devfleet.configuration import migrate_cluster_config
def test_config_migration_does_not_touch_data(tmp_path):
 p=tmp_path/'projects/demo';v=tmp_path/'vault/repo';p.mkdir(parents=True);v.mkdir(parents=True);(p/'x').write_text('project');(v/'pack').write_text('vault');migrate_cluster_config({'SchemaVersion':1,'Primary':{'InstanceName':'p'},'Failover':{'InstanceName':'f'},'Vault':{'InstanceName':'v'},'Safety':{'RequireRootlessDocker':True,'AllowDockerTcp':False}});assert (p/'x').read_text()=='project' and (v/'pack').read_text()=='vault'
def test_snapshot_before_provision_and_rerunnable():
 t=(Path(__file__).resolve().parents[1]/'Upgrade-DevFleet.ps1').read_text();assert t.index('New-DevFleetSnapshotSafe')<t.index('02-Provision-ComputeNode.ps1');assert '$isV11=' in t;assert 'Protect-DevFleetStateAcl' in t
def test_no_destructive_instance_commands():
 t=(Path(__file__).resolve().parents[1]/'Upgrade-DevFleet.ps1').read_text().lower();assert 'multipass delete' not in t and "@('delete'" not in t and "@('purge'" not in t

```


## FILE: source/tests/test_v1211_release_contract.py

SHA256: b338d6aafbeededad000f91c837375a3886c8461daf71e9f59b52ec2be8d4514 | Bytes: 8674 | Git mode: 100644

```
from pathlib import Path


ROOT = Path(__file__).parents[1]


def test_connected_bootstrap_parameter_contract_matches_installer():
    bootstrap = (ROOT / "Bootstrap-Install.ps1").read_text(encoding="utf-8")
    install = (ROOT / "Install-DevFleet.ps1").read_text(encoding="utf-8")
    for parameter in ("Role", "BootstrapBundlePath", "PackageRoot", "InstallationMode", "NonInteractive", "SkipWindowsUpdates", "DeferNetworkPairing"):
        assert f"${parameter}" in bootstrap
        assert f"${parameter}" in install
    assert "-InstallationMode',$InstallationMode" in bootstrap
    assert "-PackageRoot',$packageRoot" in bootstrap
    assert "'Connected'" in bootstrap


def test_clean_pc_bootstrap_uses_official_signed_powershell_release():
    bootstrap = (ROOT / "Bootstrap-Install.ps1").read_text(encoding="utf-8")
    manifest = (ROOT / "dependencies.json").read_text(encoding="utf-8")
    assert "dependencies.json" in bootstrap
    assert "api.github.com/repos/PowerShell/PowerShell/releases/latest" in manifest
    assert "Save-AllowlistedHttpsDownload" in bootstrap
    assert "Test-OfficialSigner" in bootstrap
    assert "curl.exe -L" not in bootstrap
    assert "SignerCertificate.Subject -notmatch" not in bootstrap
    assert "DevFleet.Common.psm1" in bootstrap
    assert "winget" not in bootstrap.lower()


def test_bootstrap_validates_power_shell_asset_filename_not_full_url_path():
    bootstrap = (ROOT / "Bootstrap-Install.ps1").read_text(encoding="utf-8")
    assert "$assetName=[IO.Path]::GetFileName($assetUri.AbsolutePath)" in bootstrap
    assert "$assetName -ne [string]$asset.name" in bootstrap


def test_version_source_propagates_to_linux_metadata_without_stale_fallback():
    assert (ROOT / "VERSION").read_text(encoding="utf-8").strip() == "1.2.13"
    linux = (ROOT / "linux" / "bootstrap-compute.sh").read_text(encoding="utf-8")
    provision = (ROOT / "windows" / "02-Provision-ComputeNode.ps1").read_text(encoding="utf-8")
    assert "PackageVersion" in provision
    assert "PACKAGE_VERSION=$(JQ .PackageVersion)" in linux
    # Metadata is serialized with jq rather than raw shell interpolation so
    # quotes, newlines, and shell-like values cannot alter the JSON structure.
    assert "jq -n" in linux
    assert '--arg version "$PACKAGE_VERSION"' in linux
    assert 'package_version:$version' in linux
    assert '"package_version":"1.1.0"' not in linux
    assert '"package_version":"1.2.6"' not in linux


def test_dependency_manifest_has_one_canonical_source_and_generated_installer_copy():
    assert not (ROOT.parent / "installer-source" / "dependencies.json").exists()
    prepare = (ROOT.parent / "installer-source" / "Prepare-ReleaseInputs.ps1").read_text(encoding="utf-8")
    assert "$sourceDependencies = Join-Path $Source 'dependencies.json'" in prepare
    assert "Copy-Item -LiteralPath $sourceDependencies -Destination $installerDependencies -Force" in prepare
    assert "Installer dependency manifest is not byte-identical" in prepare


def test_release_input_idempotence_snapshot_tracks_generated_dependency_copy():
    prepare = (ROOT.parent / "installer-source" / "Prepare-ReleaseInputs.ps1").read_text(encoding="utf-8")
    snapshot = prepare[prepare.index("function Get-Snapshot"):prepare.index("function Assert-SameSnapshot")]
    copy_contract = prepare[
        prepare.index("function Copy-PreparedShippingInputs"):prepare.index("function Assert-ReleaseStagePath")
    ]
    relative_path = "DevFleet.Setup/dependencies.json"
    copy_relative_path = relative_path.replace("/", "\\")
    assert f"'installer-source/{relative_path}'" in snapshot
    assert f"Join-Path $Installer '{copy_relative_path}'" in copy_contract
    assert "'installer-source/dependencies.json'" not in snapshot


def test_as_invoker_self_test_registers_its_exact_temp_root_before_staging():
    manifest = (ROOT.parent / "installer-source" / "DevFleet.Setup" / "app.manifest").read_text(encoding="utf-8")
    app = (ROOT.parent / "installer-source" / "DevFleet.Setup" / "App.xaml.cs").read_text(encoding="utf-8")
    services = (ROOT.parent / "installer-source" / "DevFleet.Setup" / "Services" / "InstallerServices.cs").read_text(encoding="utf-8")
    enable = "TestEnvironment.EnableForSelfTest(scratch);"
    stage = 'PayloadService.StageVerifiedPayload("self-test")'
    assert 'requestedExecutionLevel level="asInvoker"' in manifest
    assert enable in app and stage in app
    assert app.index(enable) < app.index(stage)
    assert 'Guid.TryParseExact(leaf[prefix.Length..], "N", out _)' in services
    assert "TestEnvironment.IsAuthorizedSelfTestPath(path)" in services
    assert "WindowsIdentity.GetCurrent().User" in services
    assert 'new FileSystemAccessRule("BUILTIN\\\\Users"' not in services
    assert 'new FileSystemAccessRule("NT AUTHORITY\\\\Authenticated Users"' not in services
    assert 'new FileSystemAccessRule("Everyone"' not in services


def test_multipass_readiness_uses_structured_status_and_one_absolute_deadline():
    common = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "cloud-init status --format=json" in common
    assert "ConvertFrom-Json" in common
    assert "[DateTime]::UtcNow" in common
    assert "Start-Sleep -Milliseconds" in common
    assert "cloud-init status --wait" not in common
    assert "x1B" in common


def test_connected_dependency_installers_are_bounded_and_fail_over_to_official_source():
    common = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    prereqs = (ROOT / "windows" / "01-Install-Prerequisites.ps1").read_text(encoding="utf-8")
    assert "Invoke-External -FilePath $health.Path" in common
    assert "-TimeoutSeconds 600" in common
    assert "-AllowedExitCodes @(0,-1978335189)" in common
    assert "Invoke-External -FilePath $msiexec" in common
    assert "Invoke-External -FilePath $path" in common
    assert "External command timed out" in prereqs
    assert "Install-OfficialDependency -Dependency $dependency" in prereqs


def test_multipass_configuration_preserves_matching_restored_settings():
    prereqs = (ROOT / "windows" / "01-Install-Prerequisites.ps1").read_text(encoding="utf-8")
    driver_probe = "Invoke-MultipassConfigurationProbe $mp @('get','local.driver')"
    mount_probe =