# DevFleet source part 096

Full-source UTF-8 byte interval [4417500, 4464000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 6d8f0fe2c5e5c284e5c9b21f52c3d4828573d3542aa4357483389a4b863a8c87

<!-- BEGIN SOURCE SLICE -->
mponent, kind):
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

```


## FILE: source/tests/test_migration_integration.py

SHA256: 1d6a93dd189f54371d54ac9b3639a415b9b29995c95e1a3f2ae422f8a1fc12b7 | Bytes: 4241 | Git mode: 100644

```
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).parents[1]
MIGRATE = ROOT / "windows" / "Migrate-Config.ps1"
PWSH = shutil.which("pwsh")
PWSH_REQUIRED = os.environ.get("DEVFLEET_REQUIRE_PWSH_TESTS") == "1"
if PWSH_REQUIRED and PWSH is None:
    raise RuntimeError(
        "BLOCKED — required PowerShell release-test prerequisite pwsh is unavailable"
    )
requires_pwsh = pytest.mark.skipif(
    PWSH is None,
    reason="SKIP — platform prerequisite: pwsh is unavailable",
)


def _run(config: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(PWSH), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(MIGRATE), "-ConfigPath", str(config), "-OutputPath", str(config), *extra],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def _legacy_config() -> dict:
    return {
        "SchemaVersion": 1,
        "PackageVersion": "1.0.0",
        "Primary": {"InstanceName": "DevFleet-E2E-primary"},
        "Failover": {"InstanceName": "DevFleet-E2E-failover"},
        "Vault": {"InstanceName": "DevFleet-E2E-vault"},
        "Development": {"Profile": "balanced"},
        "Docker": {"PrimaryMode": "rootful", "FailoverMode": "rootful"},
    }


def test_shipped_fresh_install_uses_supported_unprivileged_modes():
    defaults = json.loads((ROOT / "config" / "devfleet.config.json").read_text(encoding="utf-8"))
    assert defaults["Docker"]["PrimaryMode"] == "rootless"
    assert defaults["Docker"]["FailoverMode"] == "rootless"
    assert defaults["Docker"]["RootfulModeAcknowledged"] is False


@requires_pwsh
def test_schema2_migration_preserves_explicit_docker_modes(tmp_path: Path):
    existing = _legacy_config()
    existing["SchemaVersion"] = 2
    existing["Docker"]["RootfulModeAcknowledged"] = True
    config = tmp_path / "devfleet.config.json"
    config.write_text(json.dumps(existing), encoding="utf-8")
    result = _run(config, "-Confirm:$false")
    assert result.returncode == 0, result.stderr
    migrated = json.loads(config.read_text(encoding="utf-8"))
    assert migrated["Docker"]["PrimaryMode"] == "rootful"
    assert migrated["Docker"]["FailoverMode"] == "rootful"
    assert migrated["Docker"]["RootfulModeAcknowledged"] is True


@requires_pwsh
def test_supported_schema_migrates_in_place_and_preserves_identity(tmp_path: Path):
    config = tmp_path / "devfleet.config.json"
    config.write_text(json.dumps(_legacy_config()), encoding="utf-8")
    result = _run(config, "-Confirm:$false")
    assert result.returncode == 0, result.stderr
    migrated = json.loads(config.read_text(encoding="utf-8"))
    assert migrated["SchemaVersion"] == 2
    assert migrated["PackageVersion"] == "1.1.0"
    assert migrated["Primary"]["InstanceName"] == "DevFleet-E2E-primary"
    assert migrated["Failover"]["InstanceName"] == "DevFleet-E2E-failover"
    assert migrated["Vault"]["InstanceName"] == "DevFleet-E2E-vault"
    assert migrated["Development"]["Profile"] == "strict"
    assert migrated["Docker"]["PrimaryMode"] == "rootless"


@requires_pwsh
def test_preview_and_malformed_migration_are_non_destructive(tmp_path: Path):
    config = tmp_path / "devfleet.config.json"
    original = json.dumps(_legacy_config(), indent=2)
    config.write_text(original, encoding="utf-8")
    preview = _run(config, "-PreviewOnly")
    assert preview.returncode == 0, preview.stderr
    assert config.read_text(encoding="utf-8") == original
    assert list(tmp_path.glob("devfleet-v1.1.0-migration-preview-*.json"))

    config.write_text("{not-json", encoding="utf-8")
    failed = _run(config, "-Confirm:$false")
    assert failed.returncode != 0
    assert config.read_text(encoding="utf-8") == "{not-json"


def test_upgrade_script_orders_backup_and_snapshot_before_provisioning():
    upgrade = (ROOT / "Upgrade-DevFleet.ps1").read_text(encoding="utf-8")
    assert upgrade.index("upgrade-backups") < upgrade.index("New-DevFleetSnapshotSafe")
    assert upgrade.index("New-DevFleetSnapshotSafe") < upgrade.index("02-Provision-ComputeNode.ps1")
    assert "Protect-DevFleetStateAcl" in upgrade

```


## FILE: source/tests/test_network_policy.py

SHA256: ae80d2cdaa7f48f283367ab50a4f96c4939a540f098929bee2d69bd0cc4ff836 | Bytes: 1349 | Git mode: 100644

```
from types import SimpleNamespace

import pytest

from devfleet import core, main


def test_tailscale_network_policy_allows_loopback_and_tailnet_only(monkeypatch):
    settings = SimpleNamespace(require_tailscale=True, public_binding_allowed=False, tailnet_cidr="100.64.0.0/10")
    monkeypatch.setattr(core, "SETTINGS", settings)
    assert core.client_allowed_by_network("127.0.0.1") is True
    assert core.client_allowed_by_network("100.100.20.4") is True
    assert core.client_allowed_by_network("192.168.1.25") is False
    assert core.client_allowed_by_network("10.0.0.2") is False
    assert core.client_allowed_by_network("not-an-ip") is False


def test_public_binding_policy_is_explicit_opt_in(monkeypatch):
    settings = SimpleNamespace(require_tailscale=True, public_binding_allowed=True, tailnet_cidr="100.64.0.0/10")
    monkeypatch.setattr(core, "SETTINGS", settings)
    assert core.client_allowed_by_network("192.168.1.25") is True


def test_login_csrf_generation_requires_request():
    with pytest.raises(ValueError, match="request-bound session"):
        main.ui_csrf_token()


def test_login_csrf_cookie_is_http_only_and_server_rendered():
    source = (main.__file__ and __import__("pathlib").Path(main.__file__).read_text(encoding="utf-8"))
    assert "httponly=True" in source
    assert "httponly=False" not in source

```


## FILE: source/tests/test_node_registry.py

SHA256: 20b6f1d35bec5b55649482f1fdd28fba68f2a2a5a7a33b6cc4a68aabfd3f695f | Bytes: 1980 | Git mode: 100644

```
from __future__ import annotations

import pytest

from devfleet.node_registry import NodeRegistry


def test_primary_and_multiple_surrogates_share_deployment_but_keep_unique_ids(tmp_path):
    registry = NodeRegistry(tmp_path / "nodes.json")
    primary = registry.ensure_local(node_name="primary", node_role="primary", capabilities=("primary-control",))
    first = registry.ensure_local(node_name="surface-a", node_role="surrogate", deployment_id=primary["deployment_id"], coordinator_node_id=primary["node_id"], capabilities=("failover", "vault"))
    second = registry.ensure_local(node_name="surface-b", node_role="surrogate", deployment_id=primary["deployment_id"], coordinator_node_id=primary["node_id"], capabilities=("compute",))
    assert primary["deployment_id"] == first["deployment_id"] == second["deployment_id"]
    assert len({primary["node_id"], first["node_id"], second["node_id"]}) == 3
    assert first["node_role"] == second["node_role"] == "surrogate"


def test_surrogate_requires_coordinator_and_does_not_create_second_deployment(tmp_path):
    registry = NodeRegistry(tmp_path / "nodes.json")
    with pytest.raises(ValueError, match="coordinator"):
        registry.ensure_local(node_name="surface", node_role="surrogate")
    primary = registry.ensure_local(node_name="primary", node_role="primary")
    with pytest.raises(ValueError, match="Deployment identity mismatch"):
        registry.ensure_local(node_name="surface", node_role="surrogate", deployment_id="different", coordinator_node_id=primary["node_id"])


def test_duplicate_registration_is_idempotent_and_conflict_fails_closed(tmp_path):
    registry = NodeRegistry(tmp_path / "nodes.json")
    primary = registry.ensure_local(node_name="primary", node_role="primary")
    again = registry.register(primary)
    assert again["node_id"] == primary["node_id"]
    with pytest.raises(ValueError, match="conflicting identity"):
        registry.register({**primary, "node_role": "surrogate"})

```


## FILE: source/tests/test_ollama.py

SHA256: ca9a7739053062da4e2085d89055277aacce1b1763debf0efacc5926c01f531b | Bytes: 1331 | Git mode: 100644

```
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def test_profiles_and_scripts():
 p=json.loads((ROOT/'config/ollama-profiles.json').read_text());assert set(p)=={'stable-interactive','large-context','parallel-agents'};assert 'OLLAMA_NUM_PARALLEL' in p['parallel-agents']['Environment']
def test_no_invented_gpu_variables():
 t=(ROOT/'windows/Configure-Ollama.ps1').read_text();assert 'ROCM' not in t and 'HIP_' not in t and 'VULKAN' not in t
def test_shipping_config_does_not_hardcode_a_developer_ollama_host():assert '192.168.1.243:11434/v1' not in (ROOT/'config/devfleet.config.json').read_text()

def test_health_check_uses_openai_compatible_models_endpoint(monkeypatch):
 from devfleet import ollama
 class Response:
  status_code=200
  def raise_for_status(self):pass
  def json(self):return {'data':[{'id':'test-model'}]}
 seen=[]
 monkeypatch.setattr(ollama.httpx,'get',lambda url,timeout:(seen.append(url) or Response()))
 result=ollama.ollama_health()
 assert result['ok'] and result['model_available'] and seen[0].endswith('/v1/models')

def test_windows_configuration_prefers_magicdns_and_tailnet_scoped_firewall():
 t=(ROOT/'windows/Configure-Ollama.ps1').read_text()
 assert 'Self.DNSName' in t and '100.64.0.0/10' in t
 assert '0.0.0.0' in t and 'Wildcard Ollama binding is refused' in t

```


## FILE: source/tests/test_operations_leases.py

SHA256: e4d54f47f0354e6f314c5f7c0515249aba022b743192ba8e82ba0e378542a8d0 | Bytes: 1446 | Git mode: 100644

```
import time
from pathlib import Path
from devfleet import operations
from devfleet.operations import submit_operation,get_operation
from devfleet.leases import update_lease
def test_operation_progress():
 op=submit_operation('x','demo',lambda ctx:(ctx.update(50,'half'),'ok')[1])
 for _ in range(50):
  data=get_operation(op)
  if data['state'] in {'completed','failed'}:break
  time.sleep(.02)
 assert data['state']=='completed' and data['progress']==100
def test_lease_fields(tmp_path,monkeypatch):
 p=tmp_path/'demo';(p/'.devfleet').mkdir(parents=True);(p/'.devfleet/project.json').write_text('{"identity":"demo"}');monkeypatch.setattr('devfleet.leases._git',lambda p:('abc',True));d=update_lease(p,active=True);assert d['project_identity']=='demo' and d['active'] and d['git_commit']=='abc' and d['working_tree_dirty']


def test_background_heartbeat_keeps_long_operation_owned(monkeypatch):
 monkeypatch.setattr(operations, '_LEASE_SECONDS', 0.12)
 monkeypatch.setattr(operations, '_HEARTBEAT_INTERVAL_SECONDS', 0.03)
 def slow(_ctx):
  time.sleep(0.24)
  return 'done'
 op=submit_operation('heartbeat-test','heartbeat-demo',slow)
 time.sleep(0.17)
 mid=get_operation(op)
 assert mid['state']=='running'
 assert mid.get('heartbeat_at')
 assert not operations._lease_expired(mid.get('lease_expires_at'))
 for _ in range(50):
  data=get_operation(op)
  if data['state']=='completed': break
  time.sleep(.02)
 assert data['state']=='completed'

```


## FILE: source/tests/test_package_structure.py

SHA256: e1b5312e7c28c0c54ccdf1a7d4b23c700f65bb15c436ccf0f0ef82258fcf17a0 | Bytes: 663 | Git mode: 100644

```
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def test_schema_and_names():
 c=json.loads((ROOT/'config/devfleet.config.json').read_text());assert c['SchemaVersion']==2 and c['Primary']['InstanceName']=='devfleet-primary' and c['Primary']['FriendlyName']=='CodexDevVM'
def test_required_docs():
 for n in range(14):assert list((ROOT/'docs').glob(f'{n:02d}-*.md'))
def test_original_ids_preserved():assert all((ROOT/'templates'/x).is_dir() for x in ('generic','python','node'))
def test_no_baseline_file_removed():
 baseline=(ROOT/'BASELINE-v1.0.0-FILES.txt').read_text().splitlines();assert all((ROOT/x).exists() for x in baseline)

```


## FILE: source/tests/test_packaging_hygiene.py

SHA256: 69352da5f3ec0cfdf73a8a6deff2c6afc7a3068a01cdb1bd1aff0b8327e73af0 | Bytes: 903 | Git mode: 100644

```
from pathlib import Path
import re


ROOT = Path(__file__).parents[1]


def test_current_operational_docs_do_not_use_stale_release_examples():
    current_docs = [
        ROOT / "README-FIRST.md",
        ROOT.parent / "installer-source/BUILD-INSTRUCTIONS.md",
        ROOT.parent / "installer-source/BUILDING.md",
        ROOT.parent / "installer-source/CLEAN-ROOM-INSTALL.md",
        ROOT.parent / "installer-source/RELEASING.md",
    ]
    stale = (r"(?<![0-9])v?1\.2\.1(?![0-9])", r"(?<![0-9])v?1\.2\.9(?![0-9])", r"(?<![0-9])v?1\.2\.12(?![0-9])")
    for path in current_docs:
        text = path.read_text(encoding="utf-8").lower()
        assert not any(re.search(value, text) for value in stale), path


def test_installer_source_packaging_excludes_pytest_cache():
    builder = (ROOT / "tools/Build-InstallerSourceZip.ps1").read_text(encoding="utf-8")
    assert "\\.pytest_cache" in builder

```


## FILE: source/tests/test_pairing_passphrase_contract.py

SHA256: f7fda6b02b77ac84c8ad43838a34c13b75820b7130daa55411d7c2816cd24306 | Bytes: 3233 | Git mode: 100644

```
"""The unattended pairing seam must never turn a passphrase into transport text."""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
COMMON = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")


def bundle_function(name):
    start = COMMON.index(f"function {name} {{")
    end = COMMON.index("\nfunction ", start + 1)
    return COMMON[start:end]


def test_bundle_helpers_accept_securestring_without_a_plaintext_transport():
    for name in ("New-EncryptedBundle", "Expand-EncryptedBundle"):
        body = bundle_function(name)
        assert "[Security.SecureString]$Passphrase" in body
        assert "$null -eq $Passphrase" in body
        assert "Read-Host" in body and "-AsSecureString" in body
        assert "else { $Passphrase }" in body
        assert "$env:" not in body
        assert not re.search(r"(?:ArgumentList|Arguments|StandardInput).*\$(?:password|Passphrase)", body, re.I)
        assert not re.search(r"(?:Write-Host|Write-Output|Write-Warning|Set-Content|WriteAllText).*\$(?:password|Passphrase)", body, re.I)
        assert "$password=$null" in body


def test_desktop_export_forwards_securestring_and_retains_unconfigured_deferral():
    source = (ROOT / "windows" / "10-Export-Desktop-Pairing.ps1").read_text(encoding="utf-8")
    assert "[Security.SecureString]$BundlePassphrase" in source
    assert re.search(r"if\s*\(\$NonInteractive\s+-and\s+\$null\s+-eq\s+\$BundlePassphrase\)", source)
    assert "New-EncryptedBundle -SourceDirectory $dir -OutputPath $out -Passphrase $BundlePassphrase" in source
    assert "finally{Remove-Item $dir" in source
    assert "Convert-SecureStringToBundlePassword" not in source


def test_complete_cluster_forwards_securestring_inside_existing_cleanup_scope():
    source = (ROOT / "windows" / "Complete-Cluster.ps1").read_text(encoding="utf-8")
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
        "asgi": {"version": "3.0", "spec_version": "2.