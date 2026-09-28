# DevFleet source part 096

Full-source UTF-8 byte interval [4417500, 4464000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: a3f6d908ed6ef9d99cf27cf0d035483deb299119d578dd7ae0f70a92b9257eb4

<!-- BEGIN SOURCE SLICE -->
ey_helpers_bind_identity_verify_and_preserve_rollback_state():
    compute = (ROOT / "linux/devfleet-rotate-compute-secrets").read_text(encoding="utf-8")
    vault = (ROOT / "linux/devfleet-rotate-vault-secrets").read_text(encoding="utf-8")
    assert "/etc/devfleet/node-identity.json" in compute
    assert "deployment_id" in compute and "node_id" in compute
    assert "X-DevFleet-Token" in compute and "/api/status" in compute
    assert 'MODE == rollback' in compute
    assert "/etc/devfleet-vault-identity.json" in vault
    assert "deployment_id" in vault and "node_id" in vault
    assert "htpasswd -iv" in vault
    assert 'MODE == rollback' in vault
    assert "rest_password" not in " ".join(line for line in vault.splitlines() if line.startswith("printf '{"))


def test_missing_or_corrupt_existing_secrets_never_silently_regenerate():
    common = (ROOT / "windows/DevFleet.Common.psm1").read_text(encoding="utf-8")
    missing_guard = "if (Test-ExistingDeploymentState) { throw 'SECRET RECOVERY REQUIRED: host secrets are missing"
    corrupt_guard = "if (Test-ExistingDeploymentState) { throw 'SECRET RECOVERY REQUIRED: host secrets are corrupt"
    assert missing_guard in common
    assert corrupt_guard in common
    assert "Test-DevFleetSecretRecord" in common


def test_cluster_join_persists_deployment_binding_for_future_rekey():
    complete = (ROOT / "windows/Complete-Cluster.ps1").read_text(encoding="utf-8")
    assert "$hostIdentity.deployment_id=[string]$primaryNode.deployment_id" in complete
    assert "$vaultIdentity.deployment_id=[string]$primaryNode.deployment_id" in complete
    assert "/etc/devfleet-vault-identity.json" in complete

```


## FILE: source/tests/test_hardening8_systemd_contract.py

SHA256: 785ff9fe6ec7a77292fe410d5a25dc9eb500c1c19288f35449fd4118d3986fdc | Bytes: 2282 | Git mode: 100644

```
import json
from pathlib import Path


ROOT = Path(__file__).parents[1]


def test_control_service_writable_paths_derive_from_canonical_contract():
    contract = json.loads((ROOT / "app/systemd/mutable-paths.json").read_text(encoding="utf-8"))
    service = (ROOT / "app/systemd/devfleet.service").read_text(encoding="utf-8")
    backup_service = (ROOT / "app/systemd/devfleet-backup.service").read_text(encoding="utf-8")
    bootstrap = (ROOT / "linux/bootstrap-compute.sh").read_text(encoding="utf-8")

    assert contract == {
        "schema_version": 1,
        "workspace": "/home/devrunner/workspaces",
        "quarantine": "/home/devrunner/.devfleet-quarantine",
        "transaction_root": "/home/devrunner/workspaces/.devfleet-transactions",
    }
    assert "ProtectSystem=strict" in service
    assert "ProtectHome=read-only" in service
    assert "User=devfleet-control" in service
    assert "Group=devfleet-control" in service
    assert "ReadWritePaths=__WORKSPACES__ __QUARANTINE__ __TRANSACTION_ROOT__ /var/lib/devfleet /var/cache/devfleet" in service
    assert "/home/devrunner" not in service.replace("__WORKSPACES__", "").replace("__QUARANTINE__", "")
    assert "ReadOnlyPaths=__WORKSPACES__ __QUARANTINE__" in backup_service
    assert 'MUTABLE_PATH_CONTRACT="$PAYLOAD/app/systemd/mutable-paths.json"' in bootstrap
    assert 'WORKSPACES=$(jq -er ".workspace" "$MUTABLE_PATH_CONTRACT")' in bootstrap
    assert 'QUARANTINE=$(jq -er ".quarantine" "$MUTABLE_PATH_CONTRACT")' in bootstrap
    assert 'TRANSACTION_ROOT=$(jq -er ".transaction_root" "$MUTABLE_PATH_CONTRACT")' in bootstrap
    assert '[[ $TRANSACTION_ROOT == "$WORKSPACES/.devfleet-transactions" ]]' in bootstrap
    assert 'install -d -o root -g devfleet-control -m 0750 "$WORKSPACES" "$QUARANTINE"' in bootstrap
    assert 'install -d -o devfleet-control -g devfleet-control -m 0700 "$TRANSACTION_ROOT"' in bootstrap
    assert 'chown -R devrunner:devrunner /home/devrunner/.config "$WORKSPACES"' not in bootstrap
    assert '--arg workspaces "$WORKSPACES" --arg quarantine "$QUARANTINE"' in bootstrap
    assert "__WORKSPACES__" in bootstrap and "__QUARANTINE__" in bootstrap
    assert "/etc/devfleet" not in next(line for line in service.splitlines() if line.startswith("ReadWritePaths="))

```


## FILE: source/tests/test_hardening8_windows_integrations.py

SHA256: 4d7f62f7b1950263e5a069faca8fdedb2fec42afc45e7125c13f49dc1e0fb522 | Bytes: 2763 | Git mode: 100644

```
from pathlib import Path


ROOT = Path(__file__).parents[1]
REPO = ROOT.parent


def test_host_agent_install_has_ledger_bound_exact_windows_integrations():
    install = (ROOT / "windows/Install-DevFleet-HostAgent.ps1").read_text(encoding="utf-8")
    removal = (ROOT / "windows/Remove-DevFleet-OwnedIntegrations.ps1").read_text(encoding="utf-8")
    ownership = (ROOT / "windows/DevFleet-WindowsIntegrationOwnership.psm1").read_text(encoding="utf-8")

    assert "DevFleet Host Agent 8790*" not in install
    assert "Get-NetFirewallRule -DisplayName 'DevFleet Host Agent" not in install
    assert "-AdoptLegacyDevFleetIntegrations" in install
    assert "WINDOWS INTEGRATION OWNERSHIP CONFLICT" in install
    assert "InstallationGeneration" in install
    assert "ScheduledTasks=@($taskBinding)" in install
    assert "FirewallRules=@($firewallBindings)" in install
    assert "Services=@()" in install
    assert "Assert-DevFleetTaskBinding" in install
    assert "Assert-DevFleetFirewallBinding" in install
    assert "Remove-NetFirewallRule -DisplayName" not in removal
    assert "Get-NetFirewallRule -Name" in removal
    assert "Assert-DevFleetServiceBinding" in removal
    assert "Stop-Service -Name" in removal and "Stop-Service -Name ([string]$binding.Name) -Force" not in removal
    assert "Assert-DevFleetExactFields" in ownership


def test_installer_cleanup_requires_extended_ownership_ledger():
    services = (REPO / "installer-source/DevFleet.Setup/Services/InstallerServices.cs").read_text(encoding="utf-8")
    lifecycle = (REPO / "installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs").read_text(encoding="utf-8")

    assert "List<OwnedWindowsIntegration> WindowsIntegrations" in services
    assert "WindowsIntegrationOwnershipPath" in services
    assert "InstallationGeneration" in services
    assert "same-name foreign resources were preserved" in lifecycle
    assert "Remove-DevFleet-OwnedIntegrations.ps1" in lifecycle
    assert "Get-ScheduledTask -TaskName 'DevFleet Host Agent'" not in lifecycle
    assert "Remove-NetFirewallRule -DisplayName" not in lifecycle
    assert "sc.exe delete DevFleetHostAgent" not in lifecycle


def test_authenticated_protocol_accepts_empty_get_and_response_bodies_without_relaxing_auth():
    protocol = (ROOT / "windows/DevFleet-HostAgentProtocol.psm1").read_text(encoding="utf-8")
    assert "[AllowEmptyCollection()][byte[]]$Body" in protocol
    assert "New-HostAgentRequestAuthentication $Method $path $bodyBytes $Key $ExpectedHost" in protocol
    assert "Test-HostAgentResponseAuthentication $Method $path $status $responseBody $Key $ExpectedHost" in protocol
    assert "X-DevFleet-Host-Expected" in protocol
    assert "CryptographicOperations]::FixedTimeEquals" in protocol

```


## FILE: source/tests/test_hardening9_filesystem_identity.py

SHA256: 9d3a2b7a6fb5c0172eff50e8b184e7a1c03cc55f084841d71652ef9d9f02e5b3 | Bytes: 6850 | Git mode: 100644

```
import json
import os
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

from devfleet import workspace_archives
sys.path.insert(0, str(Path(__file__).parents[1] / "tools"))
from build_release import portable_metadata


ROOT = Path(__file__).parents[1]


def test_compute_venv_isolated_and_hash_bound():
    source = (ROOT / "linux/bootstrap-compute.sh").read_text(encoding="utf-8")
    assert "python3 -m venv --system-site-packages" not in source
    assert "python3 -m venv /opt/devfleet/venv" in source
    assert "--require-hashes" in source
    assert "runtime package origin is outside the DevFleet venv" in source


def test_portable_metadata_rebuilds_release_identity_without_heuristic_replacement(tmp_path: Path):
    source = tmp_path / "source"
    source.mkdir()
    (source / "VERSION").write_text("1.2.13\n", encoding="utf-8")
    (source / "payload.txt").write_text("payload\n", encoding="utf-8")
    nested = tmp_path / "devfleet-v1.2.13.tar.gz"
    nested.write_bytes(b"tar")
    entries = [
        ("README.md", b"old v1.2.1"),
        ("CLEAN-ROOM-VERIFICATION.md", b"python tools/verify_package.py --archive devfleet-v1.2.9.tar.gz"),
        ("historical-note.txt", b"historical v1.2.9 reference"),
    ]
    rebuilt = dict(portable_metadata(entries, "1.2.13", nested, source))
    assert b"DevFleet Safe Remote Development v1.2.13" in rebuilt["README.md"]
    assert b"python source/tools/verify_package.py --archive devfleet-v1.2.13.tar.gz" in rebuilt["CLEAN-ROOM-VERIFICATION.md"]
    assert rebuilt["historical-note.txt"] == b"historical v1.2.9 reference"


@pytest.mark.skipif(os.name != "posix", reason="descriptor-relative regression requires Linux/POSIX")
def test_archive_regular_to_symlink_substitution_fails_closed(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / ".devfleet").mkdir()
    (workspace / ".devfleet" / "project.json").write_text("{}", encoding="utf-8")
    victim = workspace / "payload.txt"
    victim.write_text("authorized", encoding="utf-8")
    outside = tmp_path / "outside-secret.txt"
    outside.write_text("OUTSIDE-SECRET", encoding="utf-8")
    original_open = workspace_archives.os.open
    swapped = False

    def swap_before_open(path, flags, mode=0o777, *, dir_fd=None):
        nonlocal swapped
        if not swapped and path == "payload.txt" and dir_fd is not None:
            victim.unlink()
            os.symlink(outside, victim)
            swapped = True
        return original_open(path, flags, mode, dir_fd=dir_fd)

    monkeypatch.setattr(workspace_archives.os, "open", swap_before_open)
    with pytest.raises(ValueError):
        workspace_archives.create_workspace_archive(workspace, "demo", tmp_path / "backup.tar.gz")
    assert outside.read_text(encoding="utf-8") == "OUTSIDE-SECRET"
    assert not (tmp_path / "backup.tar.gz").exists()


@pytest.mark.skipif(os.name != "posix", reason="descriptor-relative regression requires Linux/POSIX")
def test_archive_regular_to_different_inode_fails_closed(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / ".devfleet").mkdir()
    (workspace / ".devfleet" / "project.json").write_text("{}", encoding="utf-8")
    victim = workspace / "payload.txt"
    victim.write_text("authorized", encoding="utf-8")
    replacement = tmp_path / "replacement.txt"
    replacement.write_text("replacement", encoding="utf-8")
    original_open = workspace_archives.os.open
    swapped = False

    def swap_before_open(path, flags, mode=0o777, *, dir_fd=None):
        nonlocal swapped
        if not swapped and path == "payload.txt" and dir_fd is not None:
            victim.unlink()
            replacement.rename(victim)
            swapped = True
        return original_open(path, flags, mode, dir_fd=dir_fd)

    monkeypatch.setattr(workspace_archives.os, "open", swap_before_open)
    with pytest.raises(ValueError):
        workspace_archives.create_workspace_archive(workspace, "demo", tmp_path / "backup.tar.gz")


@pytest.mark.skipif(os.name != "posix", reason="descriptor-relative regression requires Linux/POSIX")
def test_restore_staging_substitution_never_touches_outside_sentinel(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    source = tmp_path / "source"
    source.mkdir()
    (source / ".devfleet").mkdir()
    (source / ".devfleet" / "project.json").write_text("{}", encoding="utf-8")
    archive = tmp_path / "backup.tar.gz"
    workspace_archives.create_workspace_archive(source, "demo", archive)
    destination = tmp_path / "demo"
    destination.mkdir()
    (destination / "old.txt").write_text("old", encoding="utf-8")
    outside = tmp_path / "outside"
    outside.mkdir()
    sentinel = outside / "SENTINEL"
    sentinel.write_text("keep", encoding="utf-8")
    original_atomic_json = workspace_archives.atomic_json
    swapped = False

    def journal_then_swap(path: Path, value: dict):
        nonlocal swapped
        original_atomic_json(path, value)
        if not swapped and value.get("phase") == "PREPARED":
            staging = Path(value["staging_root"])
            staging.rename(tmp_path / "detached-stage")
            os.symlink(outside, staging, target_is_directory=True)
            swapped = True

    monkeypatch.setattr(workspace_archives, "atomic_json", journal_then_swap)
    with pytest.raises((RuntimeError, ValueError)):
        workspace_archives.restore_workspace_archive(archive, destination, "demo")
    assert sentinel.read_text(encoding="utf-8") == "keep"


@pytest.mark.skipif(os.name != "posix", reason="standard unzip mode test requires POSIX")
def test_standard_unzip_restores_contract_modes(tmp_path: Path):
    unzip = shutil.which("unzip")
    if not unzip:
        pytest.skip("standard unzip is unavailable")
    source = tmp_path / "source"
    source.mkdir()
    (source / "VERSION").write_text("1.2.13\n", encoding="utf-8")
    nested = tmp_path / "devfleet-v1.2.13.tar.gz"
    nested.write_bytes(b"tar")
    data = dict(portable_metadata([], "1.2.13", nested, source))
    archive = tmp_path / "portable.zip"
    with zipfile.ZipFile(archive, "w") as handle:
        for name, content in data.items():
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            mode = 0o755 if name == "source/VERSION" else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            handle.writestr(info, content)
    extracted = tmp_path / "extracted"
    extracted.mkdir()
    subprocess.run([unzip, "-q", str(archive), "-d", str(extracted)], check=True)
    assert stat.S_IMODE((extracted / "source/VERSION").stat().st_mode) == 0o755
    assert stat.S_IMODE((extracted / "README.md").stat().st_mode) == 0o644

```


## FILE: source/tests/test_host_agent_idle_polling.py

SHA256: bb42499c40a9c1fb9567090f96312700047ce6c5208440df86557d349137205a | Bytes: 338 | Git mode: 100644

```
from pathlib import Path


ROOT = Path(__file__).parents[1]


def test_host_agent_uses_adaptive_idle_polling():
    source = (ROOT / "windows/DevFleet-HostAgent.ps1").read_text(encoding="utf-8")
    assert "$pollMilliseconds=if($jobs.Count -gt 0){20}else{200}" in source
    assert "Start-Sleep -Milliseconds $pollMilliseconds" in source

```


## FILE: source/tests/test_host_agent_integration.py

SHA256: 83eba1dc0ef71d3db5def5f1dd72969b96dbd6c763819fedb60e9432ac4eb9af | Bytes: 3987 | Git mode: 100644

```
from __future__ import annotations

import hmac
import json
import threading
from dataclasses import replace
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from devfleet import host_control
from devfleet.host_control import build_request_auth, build_response_auth


KEY = "integration-only-host-agent-key"
HOST = "DISPOSABLE-HOST"


class _HostAgentHandler(BaseHTTPRequestHandler):
    server_version = "DevFleetTestHostAgent/1.0"

    def log_message(self, *_args):
        return

    def _body(self) -> bytes:
        size = int(self.headers.get("Content-Length", "0"))
        return self.rfile.read(size) if size else b""

    def _send_json(self, status: int, payload: dict[str, object], *, signed: bool = True) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        if signed:
            signature = build_response_auth(
                self.command,
                self.path,
                status,
                body,
                KEY,
                HOST,
                timestamp=self.headers["X-DevFleet-Host-Timestamp"],
                nonce=self.headers["X-DevFleet-Host-Nonce"],
            )
            self.send_header("X-DevFleet-Host-Response-Signature", signature)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check_request(self, body: bytes) -> bool:
        provided = self.headers.get("X-DevFleet-Host-Signature", "")
        expected = build_request_auth(
            self.command,
            self.path,
            body,
            KEY,
            HOST,
            timestamp=int(self.headers.get("X-DevFleet-Host-Timestamp", "0")),
            nonce=self.headers.get("X-DevFleet-Host-Nonce", ""),
        )["X-DevFleet-Host-Signature"]
        return bool(self.headers.get("X-DevFleet-Host-Expected") == HOST and hmac.compare_digest(provided, expected))

    def _dispatch(self) -> None:
        body = self._body()
        if not self._check_request(body):
            self._send_json(401, {"ok": False, "error": "request authentication failed"}, signed=False)
            return
        if self.path == "/healthz":
            self._send_json(200, {"ok": True, "host_name": HOST, "agent_version": "1.2.13"})
        elif self.path == "/v1/host/capacity":
            self._send_json(200, {"ok": True, "host_name": HOST, "capacity": {"allocatable_cpus": 8}})
        elif self.path.endswith("/project-health"):
            self._send_json(500, {"ok": False, "error": "disposable worker failure"})
        else:
            self._send_json(404, {"ok": False, "error": "not found"})

    def do_GET(self):  # noqa: N802
        self._dispatch()

    def do_POST(self):  # noqa: N802
        self._dispatch()


@pytest.fixture
def disposable_host_agent(monkeypatch):
    server = ThreadingHTTPServer(("127.0.0.1", 0), _HostAgentHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    original = host_control.SETTINGS
    monkeypatch.setattr(
        host_control,
        "SETTINGS",
        replace(
            original,
            host_control_enabled=True,
            host_control_url=f"http://127.0.0.1:{server.server_port}",
            host_control_token=KEY,
            expected_host_name=HOST,
        ),
    )
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_python_client_exercises_real_local_host_agent_contract(disposable_host_agent):
    assert host_control.host_control_status()["status"] == "healthy"
    assert host_control.get_host_capacity()["capacity"]["allocatable_cpus"] == 8
    with pytest.raises(RuntimeError, match="500"):
        host_control.host_control_request("project-health", {"slug": "demo"}, runtime_id="runtime-demo")

```


## FILE: source/tests/test_host_safe_architecture.py

SHA256: bed644c01d6b81ece6eaf76db5199df20b9e1892c026b7b6fee0e98b2f8c6a7f | Bytes: 7239 | Git mode: 100644

```
from pathlib import Path
from types import SimpleNamespace
import threading
import time

from devfleet import core, host_control, operations
from devfleet.resource_profiles import (
    HostResourcePolicy,
    adaptive_host_thresholds,
    capacity_allows,
    evaluate_host_memory_admission,
    get_resource_profile,
    validate_resource_limits,
)
from devfleet.runtime import ProjectRuntimeProvider, VM_PROVIDER, runtime_metadata


def test_vm_profiles_are_bounded_and_gpu_free():
    policy = HostResourcePolicy()
    for name in ("small", "standard", "large", "xlarge"):
        profile = get_resource_profile(name)
        limits = validate_resource_limits(profile.limits("vm"), runtime_type="vm", policy=policy)
        assert limits["cpus"] <= policy.max_project_cpus
        assert limits["memory_gb"] <= policy.max_project_memory_gb
        assert limits["disk_gb"] <= policy.max_project_disk_gb
        assert runtime_metadata(VM_PROVIDER, status="ready")["gpu_enabled"] is False


def test_capacity_gate_fails_closed_when_any_required_dimension_is_short():
    allowed, _ = capacity_allows({"allocatable_cpus": 2, "allocatable_memory_gb": 4, "allocatable_disk_gb": 40}, {"cpus": 2, "memory_gb": 4, "disk_gb": 40})
    blocked, reason = capacity_allows({"allocatable_cpus": 1, "allocatable_memory_gb": 4, "allocatable_disk_gb": 40}, {"cpus": 2, "memory_gb": 4, "disk_gb": 40})
    assert allowed is True
    assert blocked is False
    assert "CPU" in reason


def test_adaptive_memory_policy_uses_physical_and_commit_headroom():
    assert adaptive_host_thresholds(16, 64).physical_floor_gb == 8
    assert adaptive_host_thresholds(128, 128).physical_floor_gb == 12.8
    result = evaluate_host_memory_admission(
        usable_physical_gb=64,
        available_physical_gb=24,
        commit_limit_gb=64,
        committed_gb=36,
        projected_allocation_gb=4,
    )
    assert result["start_safe"] is True
    assert result["physical_floor_gb"] == 8
    assert result["commit_headroom_floor_gb"] == 16
    blocked = evaluate_host_memory_admission(
        usable_physical_gb=64,
        available_physical_gb=24,
        commit_limit_gb=64,
        committed_gb=50,
        projected_allocation_gb=4,
    )
    assert blocked["start_safe"] is False
    assert blocked["projected_commit_headroom_gb"] < blocked["commit_headroom_floor_gb"]


def test_adaptive_memory_policy_matrix_covers_representative_host_sizes_and_pressure():
    expected_floors = {16: 8.0, 32: 8.0, 64: 8.0, 128: 12.8}
    for installed, floor in expected_floors.items():
        assert adaptive_host_thresholds(installed, installed * 1.25).physical_floor_gb == floor

    cases = [
        ("high available low commit", dict(usable_physical_gb=64, available_physical_gb=40, commit_limit_gb=80, committed_gb=20, projected_allocation_gb=8), True),
        ("low available high commit", dict(usable_physical_gb=64, available_physical_gb=9, commit_limit_gb=80, committed_gb=65, projected_allocation_gb=8), False),
        ("adequate physical inadequate commit", dict(usable_physical_gb=64, available_physical_gb=30, commit_limit_gb=80, committed_gb=67, projected_allocation_gb=1), False),
        ("VM heavy host", dict(usable_physical_gb=32, available_physical_gb=12, commit_limit_gb=40, committed_gb=25, projected_allocation_gb=2), False),
        ("desktop heavy host", dict(usable_physical_gb=128, available_physical_gb=20, commit_limit_gb=160, committed_gb=40, projected_allocation_gb=4), True),
        ("resource exhaustion event", dict(usable_physical_gb=64, available_physical_gb=40, commit_limit_gb=80, committed_gb=20, projected_allocation_gb=4, resource_exhaustion=True), False),
    ]
    for _name, values, expected in cases:
        assert evaluate_host_memory_admission(**values)["start_safe"] is expected


def test_vm_request_is_gpu_free_and_uses_project_identity(monkeypatch):
    captured = {}

    def fake_request(operation, payload):
        captured["operation"] = operation
        captured["payload"] = payload
        return {"ok": True}

    monkeypatch.setattr(host_control, "host_control_request", fake_request)
    result = host_control.ensure_project_vm("example-project", {"cpus": 1, "memory_gb": 2, "disk_gb": 20, "pids": 512}, project_id="12345678-1234-1234-1234-123456789012")
    assert result["ok"] is True
    assert captured["operation"] == "ensure"
    assert captured["payload"]["gpu"] is False
    assert captured["payload"]["gpu_passthrough"] is False
    assert captured["payload"]["slug"] == "example-project"


def test_operation_idempotency_returns_existing_queued_operation(tmp_path, monkeypatch):
    fake_settings = SimpleNamespace(operations=tmp_path / "operations", host_id="MULATTOTECHBOX")
    monkeypatch.setattr(operations, "SETTINGS", fake_settings)
    gate = threading.Event()
    def work(ctx):
        gate.wait(2)
        return "ok"
    first = operations.submit_operation("create", "example-project", work, idempotency_key="create:example-project:v1")
    second = operations.submit_operation("create", "example-project", lambda ctx: "should-not-run", idempotency_key="create:example-project:v1")
    assert first == second
    gate.set()
    deadline = time.time() + 2
    while time.time() < deadline and operations.get_operation(first)["state"] not in {"completed", "failed"}:
        time.sleep(0.01)
    assert operations.get_operation(first)["state"] == "completed"


def test_atomic_text_retries_transient_windows_replace_denial(tmp_path, monkeypatch):
    target = tmp_path / "atomic.txt"
    original_replace = core.os.replace
    attempts = 0

    class TransientWindowsSharingError(PermissionError):
        winerror = 5

    def transient_replace(source, destination):
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            raise TransientWindowsSharingError("transient sharing denial")
        original_replace(source, destination)

    monkeypatch.setattr(core.os, "replace", transient_replace)
    core.atomic_text(target, "complete\n")
    assert attempts == 3
    assert target.read_text(encoding="utf-8") == "complete\n"


def test_host_agent_has_narrow_authenticated_gpu_free_boundary():
    root = Path(__file__).resolve().parents[1]
    script = (root / "windows" / "DevFleet-HostAgent.ps1").read_text(encoding="utf-8")
    assert "X-DevFleet-Host-Signature" in script
    assert "SeenRequestNonces" in script
    assert "X-DevFleet-Host-Token" not in script
    assert "Global\\DevFleetHostAgent-Provisioning" in script
    assert "gpu_enabled=$false" in script
    assert "gpu_passthrough=$false" in script.lower()
    assert "Invoke-Expression" not in script
    assert "Start-Process" not in script
    assert "Restart-Computer" not in script


def test_installer_host_agent_client_uses_request_mac_not_bearer_token():
    root = Path(__file__).resolve().parents[2]
    source = (root / "installer-source" / "DevFleet.Setup" / "Services" / "InstallerLifecycle.cs").read_text(encoding="utf-8")
    assert "X-DevFleet-Host-Token" not in source
    assert "X-DevFleet-Host-Signature" in source
    assert "X-DevFleet-Host-Nonce" in source
    assert "X-DevFleet-Host-Timestamp" in source
    assert "AddRequestAuthentication" in source

```


## FILE: source/tests/test_host_transport.py

SHA256: 1afeb36061b7f8dc92233be15f77b8f6269d00177aa0511665c1d6132b0d0f36 | Bytes: 3548 | Git mode: 100644

```
from __future__ import annotations

import pytest

from devfleet.host_control import build_request_auth, build_response_auth, validate_backup_reference, verify_response_auth


def test_host_transport_mac_binds_method_path_body_host_and_nonce():
    first = build_request_auth("POST", "/v1/project-vms/x/start", b'{"x":1}', "key-a", "HOST-A", timestamp=1_700_000_000, nonce="nonce-a")
    same = build_request_auth("POST", "/v1/project-vms/x/start", b'{"x":1}', "key-a", "HOST-A", timestamp=1_700_000_000, nonce="nonce-a")
    assert first == same
    assert first["X-DevFleet-Host-Signature"] != build_request_auth("POST", "/v1/project-vms/x/start", b'{"x":2}', "key-a", "HOST-A", timestamp=1_700_000_000, nonce="nonce-a")["X-DevFleet-Host-Signature"]
    assert first["X-DevFleet-Host-Signature"] != build_request_auth("POST", "/v1/project-vms/x/start", b'{"x":1}', "key-b", "HOST-A", timestamp=1_700_000_000, nonce="nonce-a")["X-DevFleet-Host-Signature"]
    assert first["X-DevFleet-Host-Signature"] != build_request_auth("POST", "/v1/project-vms/x/start", b'{"x":1}', "key-a", "HOST-B", timestamp=1_700_000_000, nonce="nonce-a")["X-DevFleet-Host-Signature"]


def test_host_transport_response_mac_is_bound_to_request_and_body():
    body = b'{"ok":true,"runtime_id":"runtime-a"}'
    signature = build_response_auth(
        "POST", "/v1/project-vms/runtime-a/inspect", 200, body, "key-a", "HOST-A",
        timestamp="1700000000", nonce="nonce-a",
    )
    verify_response_auth(
        "POST", "/v1/project-vms/runtime-a/inspect", 200, body, "key-a", "HOST-A",
        timestamp="1700000000", nonce="nonce-a", provided=signature,
    )
    with pytest.raises(RuntimeError, match="response authentication"):
        verify_response_auth(
            "POST", "/v1/project-vms/runtime-a/inspect", 200,
            b'{"ok":false,"runtime_id":"attacker"}', "key-a", "HOST-A",
            timestamp="1700000000", nonce="nonce-a", provided=signature,
        )
    with pytest.raises(RuntimeError, match="response authentication"):
        verify_response_auth(
            "POST", "/v1/project-vms/runtime-a/inspect", 200, body, "key-a", "HOST-A",
            timestamp="1700000000", nonce="nonce-b", provided=signature,
        )


def test_hostagent_backup_reference_is_opaque_and_identity_bound():
    reference = {
        "provider": "multipass-host-agent",
        "backup_id": "demo-20260818-abc123",
        "project_id": "11111111-1111-1111-1111-111111111111",
        "slug": "demo",
        "runtime_id": "devfleet-project-demo",
        "host_id": "MULATTOTECHBOX",
        "archive_sha256": "a" * 64,
        "archive_bytes": 42,
        "manifest_sha256": "b" * 64,
        "created_at": "2026-08-18T00:00:00Z",
        "consistency_level": "quiesced",
    }
    checked = validate_backup_reference(reference, project_id=reference["project_id"], slug="demo", runtime_id=reference["runtime_id"], host_id=reference["host_id"])
    assert "archive_path" not in checked
    old_provider = {**reference, "backup_path": r"C:\ProgramData\DevFleetHostAgent\backups\demo.tar.gz"}
    with pytest.raises(RuntimeError, match="provider-local backup path"):
        validate_backup_reference(old_provider, project_id=reference["project_id"], slug="demo", runtime_id=reference["runtime_id"], host_id=reference["host_id"])
    with pytest.raises(RuntimeError, match="does not match"):
        validate_backup_reference(reference, project_id=reference["project_id"], slug="foreign", runtime_id=reference["runtime_id"], host_id=reference["host_id"])

```


## FILE: source/tests/test_installed_dependency_authenticity.py

SHA256: a096005c7bb6023e7242ea56517338137f4e8a516ab901bd37786afeffee1bf5 | Bytes: 4606 | Git mode: 100644

```
from pathlib import Path
import json


ROOT = Path(__file__).resolve().parents[1]


def test_powershell_dependency_probe_authenticates_before_version_execution():
    source = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "Get-AuthenticodeSignature" in source
    assert "while($cursor)" in source
    assert "ReparsePoint" in source
    assert "allowedSignerSubjectsExact" in source
    assert "Legacy substring signer policy is rejected" in source
    assert "Get-TrustedDependencyCandidates $Dependency" in source
    assert "if($signature.Status -ne 'Valid' -and -not $allowUnsignedInstalled)" in source
    assert "Get-Acl -LiteralPath $full" in source
    assert "if(@($exact).Count -gt 0" in source
    assert "$policy=if($null -ne $Dependency){$Dependency.installerAuthenticityPolicy}else{$null}" in source
    assert "PSObject.Properties['installedExecutableTrust']" in source


def test_canonical_dependency_policies_do_not_use_substring_signer_authority():
    for relative in ("dependencies.json",):
        for path in (ROOT / relative, ROOT.parent / "installer-source" / "DevFleet.Setup" / relative):
            manifest = json.loads(path.read_text(encoding="utf-8"))
            policies = [item["installerAuthenticityPolicy"] for item in manifest["dependencies"]]
            assert all("allowedSignerPatterns" not in policy for policy in policies)
            assert all(policy.get("strategy") == "VendorReleaseSha256" or policy.get("allowedSignerSubjectsExact") for policy in policies)
            multipass = next(item for item in manifest["dependencies"] if item["id"] == "multipass")
            assert multipass["installerAuthenticityPolicy"]["installedExecutableTrust"] == "signed-installer-locked-path"


def test_multipass_runtime_resolution_reuses_canonical_dependency_policy():
    source = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    start = source.index("function Get-MultipassExe")
    end = source.index("function Assert-MultipassIsolation", start)
    resolver = source[start:end]
    assert "Get-CanonicalDependencyManifest -PackageRoot $packageRoot" in resolver
    assert "Where-Object id -eq 'multipass'" in resolver
    assert "Wait-DevFleetDependencyStatus -Dependency $dependency" in resolver
    assert "Test-TrustedExecutableCandidate ([string]$cached.Path) -Dependency $dependency" in resolver
    assert "Get-FileHash -LiteralPath ([string]$cached.Path) -Algorithm SHA256" in resolver
    assert "Status -eq 'Compatible'" in resolver
    # The resolver must never fall back to the generic no-policy trust check.
    assert "Test-TrustedExecutableCandidate $candidate" not in resolver


def test_csharp_dependency_probe_authenticates_before_reading_version():
    source = (ROOT.parent / "installer-source" / "DevFleet.Setup" / "Services" / "InstallerLifecycle.cs").read_text(encoding="utf-8")
    assert "IsTrustedInstalledDependency(candidate, dependency)" in source
    assert "ReadAuthenticodeSubject" in source
    assert "AllowedSignerSubjectsExact" in source
    assert "Legacy substring signer policy is rejected" in source
    assert source.index("IsTrustedInstalledDependency(candidate, dependency)") < source.index("ReadVersion(candidate, dependency)")
    assert "DirectoryInfo(Path.GetDirectoryName(full)!)" in source
    assert "InstalledExecutableTrust" in source
    assert "signed-installer-locked-path" in source
    assert "Microsoft.DesktopAppInstaller" in source
    assert "8wekyb3d8bbwe" in source


def test_secret_bearing_archive_arguments_are_not_created():
    source = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "-p$password" not in source
    assert "New-EncryptedBundle" in source
    assert "Expand-EncryptedBundle" in source
    assert "DFENV001" in source
    assert "AesGcm" in source


def test_external_process_wrapper_has_timeout_tree_kill_and_bounded_diagnostics():
    source = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "TimeoutSeconds" in source
    assert "$process.Kill($true)" in source
    assert "MaxDiagnosticChars" in source
    assert "EvidenceLogPath" in source


def test_windows_powershell_common_module_has_no_powershell_7_null_coalescing_operator():
    source = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "??" not in source
    assert "Add-Type -AssemblyName System.Net.Http" in source
    assert "[System.Net.Http.HttpClientHandler]::new()" in source
    assert "[System.Net.Http.HttpClient]::new($handler)" in source

```


## FILE: source/tests/test_installer_self_cleanup.py

SHA256: 966731a830d6a62ca9fa6d366ae88252a4c8d60f28fbe645221e35dc6a10ce25 | Bytes: 648 | Git mode: 100644

```
from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_installer_self_cleanup_uses_argument_bound_helper_without_cmd_shell():
    source = (ROOT / "installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs").read_text(encoding="utf-8")
    method = source[source.index("private static void ScheduleSelfRemoval"):source.index("private static void RemoveExactRegistryEntry")]
    assert ".cmd" not in method
    assert "cmd.exe" not in method
    assert "ArgumentList.Add" in method
    assert "-LiteralPath $Target" in method
    assert "ProcessWindowStyle.Hidden" in method
    assert "Start-Sleep -Milliseconds 500" in method

```


## FILE: source/tests/test_language_templates.py

SHA256: bf6448bdd5f7ee48208912fee44e08c99614c72f7ec036c9e4301a91d6cc60d7 | Bytes: 2062 | Git mode: 100644

```
import json
from pathlib import Path
from devfleet.language_policy import TEMPLATES,recommend_template
from devfleet import analyzer, projects
import yaml
ROOT=Path(__file__).resolve().parents[1]
CORE={'generic','python','python-fastapi','node','typescript-node','typescript-next','go-service','dotnet-service','java-spring','rust-service'}
def test_legacy_and_new_templates_exist():
 assert {'generic','python','node'}<=set(TEMPLATES);assert len(TEMPLATES)==20
 for name in TEMPLATES:
  d=ROOT/'templates'/name;assert (d/'compose.yaml').is_file();assert (d/'.devcontainer/devcontainer.json').is_file();assert (d/'.devfleet/codexpro-bootstrap.sh').is_file();assert (d/'README.md').is_file();assert (d/'docs/architecture.md').is_file()
def test_core_metadata_commands():
 for name in CORE:
  data=json.loads((ROOT/'templates'/name/'.devfleet/template.json').read_text())
  for key in ('bootstrap_command','format_command','lint_command','test_command','health_command'):assert data[key]
def test_recommendations():assert recommend_template('python','fastapi')=='python-fastapi' and recommend_template('go')=='go-service'
def test_language_metadata_documented():
 for name in CORE:
  assert 'Language:' in (ROOT/'templates'/name/'README.md').read_text();assert 'Rationale:' in (ROOT/'templates'/name/'docs/architecture.md').read_text()

def test_generated_templates_satisfy_strict_security_contract(tmp_path,monkeypatch):
 monkeypatch.setattr(projects,'TEMPLATE_ROOT',ROOT/'templates')
 for name in TEMPLATES:
  project=tmp_path/name
  project.mkdir()
  projects._copy_template(project,name)
  compose=yaml.safe_load((project/'compose.yaml').read_text())
  services=compose['services']
  assert services
  for service in services.values():
   assert 'ALL' in [str(value).upper() for value in (service.get('cap_drop') or [])]
   assert any('no-new-privileges:true' in str(value).lower() for value in (service.get('security_opt') or []))
  findings=analyzer.analyze_project(project,'strict',force=True)
  assert not analyzer.has_blockers(findings), (name, findings)

```


## FILE: source/tests/test_laptop_profile.py

SHA256: a255b83381a5753c49b6029fdd6308ba0ac14d6a2a3774d0aa0dd2eaef0bcd3a | Bytes: 473 | Git mode: 100644

```
import pytest

from devfleet.resource_profiles import LAPTOP_PROFILE_DEFAULT, laptop_surrogate_profile


def test_laptop_default_is_conservative_5g_2g():
    assert laptop_surrogate_profile() == LAPTOP_PROFILE_DEFAULT


def test_laptop_lower_bound_fails_closed():
    with pytest.raises(ValueError, match="below"):
        laptop_surrogate_profile(failover_memory_gb=3)
    with pytest.raises(ValueError, match="below"):
        laptop_surrogate_profile(vault_memory_gb=1)

```


## FILE: source/tests/test_laptop_tailscale_bootstrap.py

SHA256: 499afe9442a2d9944d4fe7fc1c363c3f28880c8702472d5c9d45c610aa1c509b | Bytes: 6219 | Git mode: 100644

```
"""Execute shipped shell boundaries with external services replaced by fixtures."""
import json
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
BASH = Path(r'C:\Program Files\Git\bin\bash.exe')


def unix(path):
    value = path.resolve().as_posix()
    return '/' + value[0].lower() + value[2:] if value[1:3] == ':/' else value


def cloud_client():
    yaml = (ROOT / 'cloud-init/vault.yaml').read_text(encoding='utf-8-sig')
    start = yaml.index('  - path: /usr/local/sbin/devfleet-install-vault-tailscale')
    content = yaml.index('    content: |\n', start) + len('    content: |\n')
    lines = []
    for line in yaml[content:].splitlines():
        if not line.startswith('      '):
            break
        lines.append(line[6:])
    assert lines and lines[0] == '#!/usr/bin/env bash'
    return '\n'.join(lines) + '\n'


@pytest.mark.parametrize('case,expected', [('valid', 0), ('wrong-key', 4), ('extra-public-key', 4), ('download-failure', 22), ('apt-failure', 42), ('service-failure', 44)])
def test_vault_client_installs_only_after_pinned_key_verification(tmp_path, case, expected):
    assert BASH.is_file(), 'Use the existing Git for Windows Bash test runtime.'
    fingerprint = json.loads((ROOT / 'linux/dependency-policy.json').read_text())['tailscale']['signingKeySha256Fingerprint']
    assert re.fullmatch('[A-F0-9]{40}', fingerprint)
    body = cloud_client().replace('__TAILSCALE_SIGNING_FINGERPRINT__', fingerprint)
    paths = ['/etc/os-release', '/usr/share/keyrings/tailscale-archive-keyring.gpg', '/etc/apt/sources.list.d/tailscale.list']
    for index, path in enumerate(paths):
        body = body.replace(path, unix(tmp_path / str(index)))
    (tmp_path / '0').write_text('ID=ubuntu\nVERSION_CODENAME=noble\n')
    (tmp_path / 'tmp').mkdir()
    preamble = r'''
set -Eeuo pipefail
cd "$1"
export TMPDIR="$PWD/tmp"
case_name="$2"
fingerprint="$3"
curl() { [[ "$case_name" != download-failure ]] || return 22; printf 'fixture public key' > "${@: -1}"; }
gpg() { printf 'pub:::::::::\n'; if [[ "$case_name" == wrong-key ]]; then printf 'fpr:::::::::0000000000000000000000000000000000000000:\n'; else printf 'fpr:::::::::%s:\n' "$fingerprint"; fi; printf 'sub:::::::::\nfpr:::::::::1111111111111111111111111111111111111111:\n'; if [[ "$case_name" == extra-public-key ]]; then printf 'pub:::::::::\nfpr:::::::::2222222222222222222222222222222222222222:\n'; fi; }
install() { printf 'verified-key-install\n' >> calls; cp -- "$3" "$4"; }
apt-get() { printf 'apt %s\n' "$*" >> calls; [[ "$case_name" != apt-failure ]] || return 42; }
systemctl() { printf 'service %s\n' "$*" >> calls; [[ "$case_name" != service-failure ]] || return 44; }
'''
    script = tmp_path / 'test.sh'
    script.write_text(preamble + body, encoding='utf-8', newline='\n')
    result = subprocess.run([str(BASH), '--noprofile', '--norc', unix(script), unix(tmp_path), case, fingerprint], capture_output=True, text=True, timeout=15)
    assert result.returncode == expected, (result.returncode, result.stderr)
    assert not list((tmp_path / 'tmp').iterdir()), 'Owned public-key temporary file was not cleaned.'
    calls = (tmp_path / 'calls').read_text() if (tmp_path / 'calls').exists() else ''
    if expected in (4, 22):
        assert not calls and not (tmp_path / '1').exists() and not (tmp_path / '2').exists()
    else:
        assert calls.startswith('verified-key-install\napt update\n')
    if expected == 0:
        assert 'apt install -y tailscale\nservice enable --now tailscaled\n' in calls
        assert 'signed-by=' in (tmp_path / '2').read_text()


@pytest.mark.parametrize('address,authenticated', [('', False), ('100.64.1.2', True), ('100.127.255.255', True), ('100.1.1.2', False), ('100.128.1.2', False), ('100.64.256.1', False), ('192.168.1.2', False)])
def test_vault_checks_start_daemon_before_authenticated_ip(tmp_path, address, authenticated):
    text = (ROOT / 'linux/bootstrap-vault.sh').read_text()
    start = text.index('begin_component tailscaleChecks ')
    end = text.index('\ncomplete_component', start) + len('\ncomplete_component')
    block = text[start:end]
    preamble = r'''
set -Eeuo pipefail
cd "$1"
address="$2"
begin_component() { :; }
complete_component() { printf completed > complete; }
systemctl() { [[ "$*" == 'enable --now tailscaled' ]] || return 8; touch daemon; }
run_bounded() { printf '%s\n' "$*" > bounded; "$@"; }
tailscale() { test -f daemon || return 9; [[ -n "$address" ]] || return 1; printf '%s\n' "$address"; }
'''
    script = tmp_path / 'check.sh'
    script.write_text(preamble + block + '\n', encoding='utf-8', newline='\n')
    result = subprocess.run([str(BASH), '--noprofile', '--norc', unix(script), unix(tmp_path), address], capture_output=True, text=True, timeout=10)
    assert (result.returncode == 0) == authenticated
    assert (tmp_path / 'complete').exists() == authenticated
    assert (tmp_path / 'daemon').exists()
    assert (tmp_path / 'bounded').read_text().strip() == 'tailscale ip -4'


def test_compute_and_vault_apply_the_same_single_primary_key_policy():
    compute = (ROOT / 'linux/bootstrap-compute.sh').read_text()
    pattern = r"awk -F: '(\$1==\"pub\"[^']+)'"
    assert re.findall(pattern, compute) == re.findall(pattern, cloud_client())


def test_cloud_init_and_provisioner_deliver_auth_before_vault_secret_bootstrap():
    cloud = (ROOT / 'cloud-init/vault.yaml').read_text()
    provisioner = (ROOT / 'windows/03-Provision-Vault.ps1').read_text()
    assert '  - gnupg\n' in cloud
    assert '[timeout, --signal=TERM, --kill-after=10s, 900s, /usr/local/sbin/devfleet-install-vault-tailscale]' in cloud
    assert ".Replace('__TAILSCALE_SIGNING_FINGERPRINT__',$tailscaleFingerprint)" in provisioner
    assert provisioner.index("'04-Connect-Tailscale.ps1'") < provisioner.index('$vaultSecrets=') < provisioner.index('Invoke-MultipassWithStandardInput')


def test_deferred_laptop_rejects_before_loading_modules_or_initializing_state():
    text = (ROOT / 'Install-DevFleet.ps1').read_text()
    guard = text.index("if($Role-eq'Laptop'-and$DeferNetworkPairing)")
    assert guard < text.index('Import-Module') < text.index('Initialize-DevFleetState')

```


## FILE: source/tests/test_metadata_io.py

SHA256: f1bdba4aa4c2d6501bd193ed8d1a4f1ac9d3ea1988d57df5e7f55a0e69f626f9 | Bytes: 16739 | Git mode: 100644

```
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
    rolled_back = metad