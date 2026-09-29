# DevFleet source part 096

Full-source UTF-8 byte interval [4417500, 4464000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 58d707fee5089c1c621553bf12d901f8d2ba8e7590c53e339ab07cfecbde4653

<!-- BEGIN SOURCE SLICE -->
path)
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


def test_rekey_helpers_bind_identity_verify_and_preserve_rollback_state():
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
    source = (R