# DevFleet source part 094

Full-source UTF-8 byte interval [4324500, 4371000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: dd564799056fd00750712129f395ab3bba4b384a2e5c24bca342d208239bce4e

<!-- BEGIN SOURCE SLICE -->
 source
    assert "python3 - \"$SECRETS_ENV_TMP\"" in source
    assert "target.replace('/etc/devfleet/secrets.env')" in source
    assert "DEVFLEET_ADMIN_PASSWORD=$ADMIN_PASSWORD" not in source


def test_compute_bootstrap_uses_structured_json_generation():
    source = (ROOT / "linux" / "bootstrap-compute.sh").read_text(encoding="utf-8")
    assert "jq -n" in source
    assert "--arg" in source
    assert "--argjson" in source
    assert 's|__PORT__|$PORT|g' in source
    assert 's|__WORKSPACES__|$WORKSPACES|g' in source
    assert 's|__QUARANTINE__|$QUARANTINE|g' in source


def test_bootstrap_entrypoints_bind_identity_and_install_cleanup_before_stdin_capture():
    for name in ("bootstrap-compute.sh", "bootstrap-vault.sh"):
        source = (ROOT / "linux" / name).read_text(encoding="utf-8")
        argument_parser = source[: source.index("done", source.index("while (($#))"))]
        assert "cat >" not in argument_parser
        assert "--package-version" in argument_parser
        assert "--node-role" in argument_parser
        capture = source.index("devfleet_capture_json_stdin")
        assert source.index("BOOTSTRAP_DEADLINE_EPOCH") < capture
        assert source.index("trap '") < capture
        assert source.index("begin_component secretsInput") < capture
        assert "SECRETS_INPUT_MAX_SECONDS=60" in source


def test_bootstrap_input_helper_is_deadline_bounded_and_never_logs_input():
    source = (ROOT / "linux" / "bootstrap-input.sh").read_text(encoding="utf-8")
    assert 'timeout --foreground --kill-after=5s "${remaining}s" cat >"$secret_path"' in source
    assert "rm -f -- \"$secret_path\"" in source
    assert "jq -e 'type == \"object\"'" in source
    assert "cat \"$secret_path\"" not in source

```


## FILE: source/tests/test_client_generation.py

SHA256: 493a64b3ce136bc267434b59f1afd5a134efec124cba7b736950b61bc56002f0 | Bytes: 547 | Git mode: 100644

```
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def test_ssh_safety():
 t=(ROOT/'client/ssh-config.example').read_text();assert 'Host CodexDevVM' in t and 'ForwardAgent no' in t and 'IdentitiesOnly yes' in t
def test_docker_context_uses_ssh_not_tcp():
 t=(ROOT/'client/Configure-DockerContext.ps1').read_text();assert 'ssh://devrunner@' in t and '2375' not in t
def test_vscode_exclusions():
 t=(ROOT/'client/vscode-settings.jsonc').read_text();assert 'node_modules' in t and '.ai-bridge/local-agent' in t and 'safetensors' in t

```


## FILE: source/tests/test_codexpro_hook.py

SHA256: 3c6790200f5f72039ea577a5398e1824a827686d394a6ef55882e05e789ad118 | Bytes: 1824 | Git mode: 100644

```
import shutil
import subprocess
import uuid
import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def project_root():
    if os.name == 'nt':
        pytest.skip('CodexPro shell-hook tests require a POSIX execution environment')
    base = Path(os.environ.get("DEVFLEET_TEST_WORKSPACES", "/workspaces"))
    base.mkdir(parents=True, exist_ok=True)
    project = base / f"devfleet-hook-test-{uuid.uuid4().hex[:12]}"
    project.mkdir(parents=True)
    try:
        yield project
    finally:
        shutil.rmtree(project, ignore_errors=True)


def materialize(project: Path):
    hook = project / ".devfleet/codexpro-bootstrap.sh"
    hook.parent.mkdir()
    hook.write_text((ROOT / "templates/generic/.devfleet/codexpro-bootstrap.sh").read_text())
    hook.chmod(0o755)
    return hook


def hook_env(project: Path):
    env = dict(os.environ)
    env.update(PATH="/usr/bin:/bin", DEVFLEET_WORKSPACES_ROOT=str(project.parent), DEVFLEET_CODEXPRO_HEALTH_URL="http://127.0.0.1:18787/healthz")
    return env
    return hook


def test_unavailable_state_is_actionable(project_root):
    hook = materialize(project_root)
    result = subprocess.run(
        [str(hook)],
        cwd=project_root,
        text=True,
        capture_output=True,
        env=hook_env(project_root),
    )
    assert result.returncode == 0
    assert "unavailable" in (project_root / ".devfleet/runtime/codexpro-status.json").read_text()


def test_hook_idempotent_unavailable(project_root):
    hook = materialize(project_root)
    subprocess.run([str(hook)], cwd=project_root, env=hook_env(project_root), check=True)
    subprocess.run([str(hook)], cwd=project_root, env=hook_env(project_root), check=True)
    assert (project_root / ".devfleet/runtime/codexpro-bootstrap.log").exists()

```


## FILE: source/tests/test_configuration.py

SHA256: 8fe09b0249911ea8b01eca683e82f01fe488eaa0b01084e404c1962705fde75c | Bytes: 1342 | Git mode: 100644

```
from devfleet.configuration import migrate_cluster_config,validate_cluster_config
def schema1(rootless=True):return {'SchemaVersion':1,'ClusterName':'custom','Primary':{'InstanceName':'p','Cpus':99},'Failover':{'InstanceName':'f'},'Vault':{'InstanceName':'v'},'Ollama':{'BaseUrl':'http://old/v1','Model':'m'},'Network':{'PortalPort':9999},'Backup':{},'Safety':{'RequireRootlessDocker':rootless,'AllowDockerTcp':False}}
def test_migration_preserves_values_and_names():
 out,changes=migrate_cluster_config(schema1());validate_cluster_config(out);assert out['Primary']['InstanceName']=='p' and out['Primary']['Cpus']==99;assert out['Development']['Profile']=='strict';assert out['Docker']['PrimaryMode']=='rootless';assert out['Primary']['FriendlyName']=='CodexDevVM';assert changes
def test_clean_install_balanced():assert migrate_cluster_config(schema1(),clean_install=True)[0]['Development']['Profile']=='balanced'
def test_custom_safety_preserved_without_store_switch():
 out,_=migrate_cluster_config(schema1(False));assert out['Safety']['RequireRootlessDocker'] is False;assert out['Docker']['PrimaryMode']=='rootless'
def test_docker_tcp_rejected():
 out,_=migrate_cluster_config(schema1());out['Safety']['AllowDockerTcp']=True
 try:validate_cluster_config(out)
 except ValueError:pass
 else:raise AssertionError('must reject Docker TCP')

```


## FILE: source/tests/test_csharp_host_agent_response_auth.py

SHA256: d5a00280ded660b836947e6921aa804fcfca33b524853a57a3473848fac185fb | Bytes: 1039 | Git mode: 100644

```
from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_csharp_maintenance_client_authenticates_success_and_error_responses_before_trust():
    source = (ROOT / "installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs").read_text(encoding="utf-8")
    assert source.count("VerifyResponseAuthentication(request, response, bodyBytes") >= 2
    assert source.index("VerifyResponseAuthentication(request, response, bodyBytes") < source.index("if (!response.IsSuccessStatusCode)")
    assert "CryptographicOperations.FixedTimeEquals" in source
    assert "response.StatusCode" in source
    assert "expectedHost" in source
    assert "request.RequestUri!.AbsolutePath" in source
    assert "X-DevFleet-Host-Response-Signature" in source


def test_host_agent_resets_auth_context_between_listener_requests():
    source = (ROOT / "source/windows/DevFleet-HostAgent.ps1").read_text(encoding="utf-8")
    assert "$context=$null;$auth=$null;$responseAuth=$null" in source
    assert "Send-AuthenticatedJsonResponse" in source

```


## FILE: source/tests/test_dashboard_v11.py

SHA256: ddf6ab6efb8d2ada422be5e1cb2fc897fe02d619baceec195d823e3d0045dbc0 | Bytes: 2659 | Git mode: 100644

```
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def test_long_operations_auto_refresh_and_show_log_timestamps():
 text=(ROOT/'app/templates/index.html').read_text(encoding='utf-8')
 assert 'http-equiv="refresh"' not in text
 assert 'operation-banner' in text
 assert 'operation.updated_at' in text and 'operation.log' in text

def test_sensitive_actions_have_explicit_acknowledgements():
 text=(ROOT/'app/templates/index.html').read_text(encoding='utf-8')
 for name in ('confirm_slug','confirm_phrase','DANGER ZONE','Move to another node'):
  assert name in text

def test_dashboard_exposes_requested_quick_commands_and_cache_status():
 text=(ROOT/'app/templates/index.html').read_text(encoding='utf-8')
 assert 'workspace_target(p)' in text and 'data-provider' in text
 assert 'Advanced details' in text and 'Last backup' in text

def test_v1_dashboard_repair_and_peer_control_are_preserved():
 main=(ROOT/'app/devfleet/main.py').read_text()
 html=(ROOT/'app/templates/index.html').read_text(encoding='utf-8')
 assert any(marker in main for marker in ("@app.post('/repair')", '@app.post("/repair")')) and any(marker in main for marker in ("@app.post('/peer/projects/{slug}/{action}')", '@app.post("/peer/projects/{slug}/{action}")'))
 assert 'Run non-destructive repair' in html and 'Move to another node' in html

def test_cluster_monitor_has_all_refresh_choices_and_manual_refresh():
 text=(ROOT/'app/templates/index.html').read_text(encoding='utf-8')
 js=(ROOT/'app/static/app.js').read_text()
 for value in ('value="0"','value="5"','value="10"','value="15"','value="30"'):
  assert value in text
 assert 'id="refresh-cluster"' in text and "setInterval(refreshCluster" in js
 assert "fetch('/cluster/status'" in js

def test_portainer_style_container_controls_are_present_and_confirm_removal():
 main=(ROOT/'app/devfleet/main.py').read_text()
 html=(ROOT/'app/templates/index.html').read_text(encoding='utf-8')
 js=(ROOT/'app/static/app.js').read_text()
 containers=(ROOT/'app/devfleet/containers.py').read_text()
 assert any(marker in main for marker in ("@app.get('/api/containers'", '@app.get("/api/containers"')) and any(marker in main for marker in ("@app.post('/containers/{container_ref}/{action}')", '@app.post("/containers/{container_ref}/{action}")'))
 assert 'container-inspect' in js and 'container-action' in js and 'container-table' in html
 assert 'confirm_remove' in main and '"docker", "stats"' in containers

def test_cluster_status_covers_failover_and_vault():
 status=(ROOT/'app/devfleet/status.py').read_text()
 assert 'def cluster_status' in status and "devfleet-failover" in status and "devfleet-vault" in status

```


## FILE: source/tests/test_dependency_advisories.py

SHA256: 4cdaf6f35cb09709b2df65afa97dbf56fccb76f517065254ad6d2b99c4eada2b | Bytes: 4652 | Git mode: 100644

```
from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools import check_dependency_advisories as gate


def _lock(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "requirements.txt"
    path.write_text(text, encoding="utf-8")
    return path


def test_exact_pin_and_canonical_name(tmp_path: Path):
    assert gate.lock_packages(_lock(tmp_path, "Fast_API[security]==1.2.3\n")) == [("fast-api", "1.2.3")]


def test_pip_compile_continuation_and_trailing_whitespace(tmp_path: Path):
    lock = _lock(
        tmp_path,
        """demo==1.2.3 \\
    --hash=sha256:abc \\
    # via test
next==2.0.0""" + "   \n" + """
""",
    )
    assert gate.lock_packages(lock) == [("demo", "1.2.3"), ("next", "2.0.0")]


def test_marker_continuation_and_extras(tmp_path: Path):
    lock = _lock(
        tmp_path,
        """demo[extra]==1.2.3 \\
    ; python_version < "3.13"
platform==2.0; sys_platform == "win32"
""",
    )
    assert gate.lock_requirements(lock) == [
        ("demo", "1.2.3", 'python_version < "3.13"'),
        ("platform", "2.0", 'sys_platform == "win32"'),
    ]


def test_inline_annotation_is_not_part_of_version(tmp_path: Path):
    assert gate.lock_packages(_lock(tmp_path, "demo==1.2.3 # generated annotation\n")) == [("demo", "1.2.3")]


def test_non_exact_pin_fails_closed(tmp_path: Path):
    with pytest.raises(ValueError, match="exact"):
        gate.lock_packages(_lock(tmp_path, "demo>=1.2\n"))


def test_cvss_v2_v3_and_v4_scores():
    assert gate._score({"severity": [{"type": "CVSS_V2", "score": "AV:N/AC:L/Au:N/C:P/I:P/A:P"}]}) == pytest.approx(7.5)
    assert gate._score({"severity": [{"type": "CVSS_V3", "score": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}]}) == pytest.approx(9.8)
    assert gate._score({"severity": [{"type": "CVSS_V4", "score": "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N"}]}) == pytest.approx(9.3)


def test_high_critical_and_unknown_severity_block():
    high = {"id": "HIGH", "severity": [{"type": "CVSS_V3", "score": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N"}]}
    critical = {"id": "CRIT", "severity": [{"type": "CVSS_V3", "score": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}]}
    malformed = {"id": "BAD", "severity": [{"type": "CVSS_V3", "score": "CVSS:9.9/not-a-vector"}]}
    assert gate._severity(high) == "HIGH"
    assert gate._severity(critical) == "CRITICAL"
    assert gate._severity(malformed) == "UNKNOWN"


def test_declared_affected_severity_is_considered():
    vulnerability = {"affected": [{"ecosystem_specific": {"severity": "HIGH"}}]}
    assert gate._severity(vulnerability) == "HIGH"


def test_run_sends_exact_query_and_allowlist(monkeypatch, tmp_path: Path):
    lock = _lock(
        tmp_path,
        """Demo_Package[extra]==1.2.3 ; sys_platform == "win32" \\
    --hash=sha256:abc
""",
    )
    allowlist = tmp_path / "allow.json"
    allowlist.write_text(json.dumps({"exceptions": [{"advisory_id": "OSV-1", "package": "demo-package", "affected_version": "1.2.3"}]}), encoding="utf-8")
    requests: list[tuple[str, str]] = []

    def fake_query(package: str, version: str) -> dict:
        requests.append((package, version))
        return {"vulns": [{"id": "OSV-1", "severity": [{"type": "CVSS_V3", "score": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}]}]}

    monkeypatch.setattr(gate, "query", fake_query)
    report = gate.run(lock, allowlist)
    assert requests == [("demo-package", "1.2.3")]
    assert report["packages"][0]["query"]["version"] == "1.2.3"
    assert report["status"] == "PASS"


def test_zero_advisories_pass_and_network_failure_blocks(monkeypatch, tmp_path: Path):
    lock = _lock(tmp_path, "demo==1.2.3\n")
    allowlist = tmp_path / "allow.json"
    allowlist.write_text('{"exceptions": []}', encoding="utf-8")
    monkeypatch.setattr(gate, "query", lambda *_: {"vulns": []})
    assert gate.run(lock, allowlist)["status"] == "PASS"
    monkeypatch.setattr(gate, "query", lambda *_: (_ for _ in ()).throw(OSError("offline")))
    report = gate.run(lock, allowlist)
    assert report["status"] == "BLOCKED"
    assert report["errors"]


def test_relevant_unknown_advisory_blocks(monkeypatch, tmp_path: Path):
    lock = _lock(tmp_path, "demo==1.2.3\n")
    allowlist = tmp_path / "allow.json"
    allowlist.write_text('{"exceptions": []}', encoding="utf-8")
    monkeypatch.setattr(gate, "query", lambda *_: {"vulns": [{"id": "OSV-BAD", "severity": [{"type": "CVSS_V3", "score": "not-supported"}]}]})
    report = gate.run(lock, allowlist)
    assert report["status"] == "BLOCKED"
    assert report["blocking_advisories"][0]["severity"] == "UNKNOWN"

```


## FILE: source/tests/test_destructive_ownership.py

SHA256: 79fa7f5ef8d85982f8650ed0d58b6716fd0e5327199a7c42f3f002b2e2d2e79d | Bytes: 2513 | Git mode: 100644

```
from __future__ import annotations

import json
from pathlib import Path

import pytest

from devfleet import projects


def _workspace(tmp_path: Path, slug: str = "owned-project", metadata: dict | None = None) -> Path:
    project = tmp_path / slug
    (project / ".devfleet").mkdir(parents=True)
    if metadata is not None:
        (project / ".devfleet" / "project.json").write_text(json.dumps(metadata), encoding="utf-8")
    return project


def _valid(slug: str = "owned-project") -> dict:
    return {
        "schema_version": 3,
        "managed_by": "devfleet",
        "project_id": "12345678-1234-1234-1234-123456789abc",
        "slug": slug,
        "runtime_provider": "docker-compose",
        "host_id": "test-node",
    }


@pytest.mark.parametrize(
    "metadata",
    [
        None,
        {"schema_version": 3, "managed_by": "devfleet", "slug": "owned-project"},
        {"schema_version": 3, "managed_by": "devfleet", "slug": "wrong", "project_id": "12345678-1234-1234-1234-123456789abc", "runtime_provider": "docker-compose", "host_id": "test-node"},
        {"schema_version": 3, "managed_by": "someone-else", "slug": "owned-project", "project_id": "12345678-1234-1234-1234-123456789abc", "runtime_provider": "docker-compose", "host_id": "test-node"},
        {"schema_version": 3, "managed_by": "devfleet", "slug": "owned-project", "project_id": "12345678-1234-1234-1234-123456789abc", "runtime_provider": "docker-compose"},
    ],
)
def test_ambiguous_project_identity_is_denied_for_mutation(tmp_path: Path, metadata):
    project = _workspace(tmp_path, metadata=metadata)
    with pytest.raises(ValueError, match="Mutation denied"):
        projects.load_authoritative_project_identity_for_mutation(project)


def test_malformed_metadata_is_denied_without_catalog_synthesis(tmp_path: Path):
    project = _workspace(tmp_path, metadata=None)
    metadata_file = project / ".devfleet" / "project.json"
    metadata_file.write_text("{not-json", encoding="utf-8")
    catalog = projects.load_project_for_catalog(project)
    assert catalog["slug"] == project.name
    with pytest.raises(ValueError, match="malformed"):
        projects.load_authoritative_project_identity_for_mutation(project)


def test_valid_legacy_migration_record_is_authoritative(tmp_path: Path):
    project = _workspace(tmp_path, metadata=_valid())
    identity = projects.load_authoritative_project_identity_for_mutation(project)
    assert identity["managed_by"] == "devfleet"
    assert identity["project_id"]

```


## FILE: source/tests/test_destructive_safety_transaction.py

SHA256: c64fb764b78450c811014b85c76fcfda076ef98cf3e22003b5767c7131109bd8 | Bytes: 3145 | Git mode: 100644

```
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from devfleet import projects
from devfleet.workspace_archives import create_workspace_archive


def _settings(tmp_path: Path):
    return SimpleNamespace(
        workspaces=tmp_path / "workspaces",
        runtime_root=tmp_path / "runtime",
        backup_before_rebuild=False,
        backup_before_quarantine=True,
        node_name="test-node",
        development_profile="strict",
        allow_permanent_delete=True,
    )


def _project(tmp_path: Path, slug: str = "active-writer") -> Path:
    project = tmp_path / "workspaces" / slug
    (project / ".devfleet").mkdir(parents=True)
    (project / ".devfleet" / "project.json").write_text(
        json.dumps({"schema_version": 3, "managed_by": "devfleet", "project_id": "12345678-1234-1234-1234-123456789012", "slug": slug, "runtime_provider": "docker-compose", "host_id": "test-node"}),
        encoding="utf-8",
    )
    (project / "README.md").write_text("stable\n", encoding="utf-8")
    return project


def test_safety_backup_binds_fresh_backup_and_source_fingerprint(tmp_path, monkeypatch):
    project = _project(tmp_path)
    settings = _settings(tmp_path)
    settings.workspaces.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(projects, "stop_project", lambda _slug: "stopped")
    monkeypatch.setattr(projects, "running", lambda _project: False)
    archive = tmp_path / "runtime" / "workspace-backups" / "fresh" / "active-writer.tar.gz"
    result = create_workspace_archive(project, "active-writer", archive)
    monkeypatch.setattr(
        projects,
        "backup_project",
        lambda _slug: json.dumps({
            "backup_status": "verified",
            "backup_id": "fresh-transaction",
            "backup_path": str(archive),
            "backup_sha256": result["archive_sha256"],
        }),
    )

    outcome = projects.safety_backup_project("active-writer")
    binding = outcome["binding"]
    assert binding["project_id"] == "12345678-1234-1234-1234-123456789012"
    assert binding["backup_id"] == "fresh-transaction"
    assert binding["backup_sha256"] == result["archive_sha256"]
    assert binding["transaction_id"].startswith("destroy-")


def test_writer_after_quiescence_fails_closed(tmp_path, monkeypatch):
    project = _project(tmp_path)
    settings = _settings(tmp_path)
    settings.workspaces.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(projects, "SETTINGS", settings)

    monkeypatch.setattr(projects, "stop_project", lambda _slug: "stopped")
    monkeypatch.setattr(projects, "running", lambda _project: False)

    def backup_with_active_writer(_slug):
        (project / "README.md").write_text("written during backup\n", encoding="utf-8")
        return json.dumps({"backup_status": "verified", "backup_id": "old", "backup_sha256": "a" * 64})

    monkeypatch.setattr(projects, "backup_project", backup_with_active_writer)
    with pytest.raises(RuntimeError, match="changed during the safety backup"):
        projects.safety_backup_project("active-writer")

```


## FILE: source/tests/test_docker_modes.py

SHA256: 5340bdf18fc9026bfca919acc59f908d4065dcfc756d1f5fe156d3b5cad85759 | Bytes: 1569 | Git mode: 100644

```
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def test_both_docker_stores_are_detected_and_reported():
 text=(ROOT/'linux/devfleet-docker-mode-report').read_text()
 assert 'Rootless store:' in text and 'Rootful store:' in text
 assert 'Stores are separate' in text

def test_switch_requires_rootful_ack_and_never_prunes():
 text=(ROOT/'linux/devfleet-switch-docker-mode').read_text()
 assert '--acknowledge-rootful' in text
 assert 'docker system prune' not in text
 assert 'Stores were not migrated or deleted' in text

def test_clean_installer_requires_rootful_acknowledgement():
 text=(ROOT/'Install-DevFleet.ps1').read_text()
 assert 'ENABLE ROOTFUL CODEXDEVVM' in text

def test_windows_mode_wrapper_snapshots_and_updates_authoritative_config():
 text=(ROOT/'windows/Set-DevFleetDockerMode.ps1').read_text()
 assert 'New-DevFleetSnapshotSafe' in text and 'Save-DevFleetConfig' in text
 assert '-AcknowledgeRootful' in text
 assert "@('delete'" not in text.lower() and 'multipass delete' not in text.lower()

def test_update_and_repair_follow_selected_docker_mode():
 for rel in ('linux/devfleet-safe-update','linux/devfleet-repair','linux/devfleet-user-repair'):
  text=(ROOT/rel).read_text()
  lower=text.lower()
  assert "docker_mode" in lower and 'rootless' in lower and 'rootful' in lower

def test_windows_maintenance_uses_stopped_state_snapshot_helper():
 for rel in ('windows/Update-DevFleet.ps1','windows/Repair-DevFleet.ps1','windows/03-Provision-Vault.ps1'):
  text=(ROOT/rel).read_text()
  assert 'New-DevFleetSnapshotSafe' in text

```


## FILE: source/tests/test_existing_runtime_assignment.py

SHA256: 3a7ca4b6a92618c2f753dad9d0e86b72253b9550bd61379fbd2301c1edd986bd | Bytes: 7902 | Git mode: 100644

```
import json
from pathlib import Path

import pytest

import devfleet.projects as projects
from devfleet.core import SETTINGS


def make_existing(slug: str, *, metadata: dict | None = None) -> tuple[Path, dict]:
    project = SETTINGS.workspaces / slug
    (project / ".devfleet").mkdir(parents=True, exist_ok=True)
    (project / "compose.yaml").write_text("services:\n  app:\n    image: ubuntu:24.04\n", encoding="utf-8")
    (project / "README.md").write_text("workspace-preserved\n", encoding="utf-8")
    record = metadata or {"schema_version": 3, "managed_by": "devfleet", "slug": slug, "display_name": "Legacy project", "project_id": "12345678-1234-1234-1234-123456789abc", "runtime_provider": "docker-compose", "host_id": "test-node"}
    (project / ".devfleet" / "project.json").write_text(json.dumps(record), encoding="utf-8")
    (project / ".devfleet" / "template.json").write_text(json.dumps({
        "start_command": "docker compose up -d --build",
        "stop_command": "docker compose down --remove-orphans",
        "restart_command": "docker compose restart",
        "rebuild_command": "docker compose build && docker compose up -d",
        "logs_command": "docker compose logs",
    }), encoding="utf-8")
    return project, record


def mark_healthy(slug: str) -> str:
    project = SETTINGS.workspaces / slug
    meta = projects.load_meta(project)
    meta.update({'health_status': 'healthy', 'health_scope': 'application-check'})
    projects.atomic_json(projects.metadata_path(project), meta)
    return 'healthy'


def test_legacy_project_is_detected_and_explicitly_assigned_to_container(monkeypatch: pytest.MonkeyPatch):
    slug = "legacy-container-adopt"
    project, _ = make_existing(slug)
    monkeypatch.setattr(projects, "running", lambda _project: False)
    monkeypatch.setattr(projects, "backup_project", lambda _slug: json.dumps({"backup_status": "verified", "backup_id": "test-backup", "backup_sha256": "a" * 64}))
    monkeypatch.setattr(projects, "start_project", lambda _slug: "started")
    monkeypatch.setattr(projects, "runtime_health", lambda _slug: {"ok": True, "healthy": True})
    monkeypatch.setattr(projects, "health_project", mark_healthy)

    result = projects.assign_project_runtime(slug, "container", "standard")

    saved = json.loads((project / ".devfleet" / "project.json").read_text())
    assert result["workspace_preserved"] is True
    assert saved["runtime_isolation"] == "container"
    assert saved["runtime_provider"] == "docker-compose"
    assert saved["resource_profile"] == "standard"
    assert (project / ".devfleet" / "runtime-resources.yaml").is_file()
    assert (project / "README.md").read_text() == "workspace-preserved\n"


def test_existing_project_vm_assignment_imports_workspace_and_persists_metadata(monkeypatch: pytest.MonkeyPatch):
    slug = "legacy-vm-adopt"
    project, _ = make_existing(slug)
    monkeypatch.setattr(projects, "running", lambda _project: False)
    monkeypatch.setattr(projects, "backup_project", lambda _slug: json.dumps({"backup_status": "verified", "backup_id": "test-backup", "backup_sha256": "a" * 64}))
    monkeypatch.setattr(projects, "get_host_capacity", lambda: {"capacity": {"allocatable_cpus": 8, "allocatable_memory_gb": 24, "allocatable_disk_gb": 300}})
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda _slug, _meta: {"runtime_id": "devfleet-project-legacy-vm-adopt", "address": "10.0.0.10", "state": "ready"}))
    monkeypatch.setattr(projects.VmRuntimeOperations, "stop", staticmethod(lambda _slug, _meta: {"state": "stopped"}))
    imported = {}

    def fake_import(import_slug, runtime_id, *, source_vm, project_id):
        imported.update(slug=import_slug, runtime_id=runtime_id, source_vm=source_vm, project_id=project_id)
        return {"archive_sha256": "a" * 64, "target_archive_sha256": "a" * 64, "workspace_preserved": True}

    monkeypatch.setattr(projects, "import_project_workspace", fake_import)
    monkeypatch.setattr(projects, "sync_project_vm_ssh_alias", lambda *_args, **_kwargs: {"validated": True})
    monkeypatch.setattr(projects, "start_project", lambda _slug: "started")
    monkeypatch.setattr(projects, "stop_project", lambda _slug: "stopped")
    monkeypatch.setattr(projects, "runtime_health", lambda _slug: {"ok": True, "healthy": True})
    monkeypatch.setattr(projects, "health_project", mark_healthy)

    result = projects.assign_project_runtime(slug, "vm", "small")

    saved = json.loads((project / ".devfleet" / "project.json").read_text())
    assert result["workspace_preserved"] is True
    assert saved["runtime_isolation"] == "vm"
    assert saved["runtime_provider"] == "multipass-host-agent"
    assert saved["runtime_id"] == "devfleet-project-legacy-vm-adopt"
    assert imported["source_vm"] == SETTINGS.node_name
    assert imported["project_id"] == saved["project_id"]
    assert (project / "README.md").read_text() == "workspace-preserved\n"


def test_vm_assignment_rolls_back_metadata_and_override_when_import_fails(monkeypatch: pytest.MonkeyPatch):
    slug = "legacy-vm-rollback"
    project, original = make_existing(slug)
    override = project / ".devfleet" / "runtime-resources.yaml"
    override.write_text("services:\n  app:\n    cpus: 1\n", encoding="utf-8")
    original_bytes = (project / ".devfleet" / "project.json").read_bytes()
    original_override = override.read_text()
    monkeypatch.setattr(projects, "running", lambda _project: False)
    monkeypatch.setattr(projects, "backup_project", lambda _slug: json.dumps({"backup_status": "verified", "backup_id": "test-backup", "backup_sha256": "a" * 64}))
    monkeypatch.setattr(projects, "get_host_capacity", lambda: {"capacity": {"allocatable_cpus": 8, "allocatable_memory_gb": 24, "allocatable_disk_gb": 300}})
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda _slug, _meta: {"runtime_id": "devfleet-project-legacy-vm-rollback", "address": "10.0.0.11", "state": "ready"}))
    monkeypatch.setattr(projects, "import_project_workspace", lambda *args, **kwargs: (_ for _ in ()).throw(RuntimeError("import failed")))
    destroyed = []
    monkeypatch.setattr(projects, "destroy_project_vm", lambda *args, **kwargs: destroyed.append(kwargs["runtime_id"]))

    with pytest.raises(RuntimeError, match="import failed"):
        projects.assign_project_runtime(slug, "vm", "small")

    assert (project / ".devfleet" / "project.json").read_bytes() == original_bytes
    assert override.read_text() == original_override
    assert destroyed == ["devfleet-project-legacy-vm-rollback"]


def test_vm_assignment_rejects_insufficient_capacity_before_mutation(monkeypatch: pytest.MonkeyPatch):
    slug = "legacy-capacity-reject"
    project, _ = make_existing(slug)
    original = (project / ".devfleet" / "project.json").read_bytes()
    monkeypatch.setattr(projects, "running", lambda _project: False)
    monkeypatch.setattr(projects, "get_host_capacity", lambda: {"capacity": {"allocatable_cpus": 1, "allocatable_memory_gb": 1, "allocatable_disk_gb": 10}})

    with pytest.raises(ValueError, match="capacity"):
        projects.assign_project_runtime(slug, "vm", "standard")

    assert (project / ".devfleet" / "project.json").read_bytes() == original


def test_malformed_metadata_is_not_silently_deleted(monkeypatch: pytest.MonkeyPatch):
    slug = "legacy-malformed-metadata"
    project = SETTINGS.workspaces / slug
    (project / ".devfleet").mkdir(parents=True, exist_ok=True)
    (project / "compose.yaml").write_text("services:\n  app:\n    image: ubuntu:24.04\n", encoding="utf-8")
    metadata_file = project / ".devfleet" / "project.json"
    metadata_file.write_text("{not-json", encoding="utf-8")

    with pytest.raises(ValueError, match="malformed"):
        projects.assign_project_runtime(slug, "container", "small")

    assert metadata_file.read_text() == "{not-json"

```


## FILE: source/tests/test_failover.py

SHA256: b69044da502f5c37cc4cd12d91091606a314ba90f0ff1157002439abb7ca5e6c | Bytes: 11565 | Git mode: 100644

```
from __future__ import annotations

from collections import deque

import pytest

from devfleet import failover
from devfleet.failover import guided_transfer


class C:
    def __init__(self):
        self.events = []

    def update(self, progress, message):
        self.events.append((progress, message))


def _receipt(operation_id: str) -> dict[str, object]:
    return {
        "ok": True,
        "accepted": True,
        "operation_id": operation_id,
        "operation_url": f"/api/operations/{operation_id}",
    }


def _record(operation_id: str, state: str, **extra: object) -> dict[str, object]:
    return {"operation_id": operation_id, "id": operation_id, "state": state, **extra}


TRANSFER = {
    "project_id": "12345678-1234-1234-1234-123456789abc",
    "deployment_id": "deployment-1234",
    "source_host_id": "devfleet-primary",
    "destination_host_id": "devfleet-failover",
}


def _run_transfer(peer, events, *, finalize_source=None):
    if finalize_source is None:
        finalize_source = lambda slug, project_id, destination_host_id: events.append(
            ("finalized", slug, project_id, destination_host_id)
        )
    return guided_transfer(
        "demo",
        C(),
        stop=lambda slug: events.append(("stop", slug)),
        backup=lambda slug: events.append(("backup", slug)),
        assert_quiesced=lambda slug, project_id: events.append(
            ("quiesced", slug, project_id)
        ),
        finalize_source=finalize_source,
        peer_call=peer,
        **TRANSFER,
    )


def test_guided_transfer_rejects_non_distinct_destination_before_stop():
    with pytest.raises(ValueError, match="distinct destination"):
        guided_transfer(
            "demo",
            C(),
            stop=lambda _: (_ for _ in ()).throw(RuntimeError("must not run")),
            backup=lambda _: (_ for _ in ()).throw(RuntimeError("must not run")),
            assert_quiesced=lambda *_: (_ for _ in ()).throw(
                RuntimeError("must not run")
            ),
            finalize_source=lambda *_: (_ for _ in ()).throw(
                RuntimeError("must not run")
            ),
            peer_call=lambda *_: (_ for _ in ()).throw(RuntimeError("must not run")),
            **{**TRANSFER, "destination_host_id": "DEVFLEET-PRIMARY"},
        )


def test_guided_transfer_receives_finalizes_then_activates_and_starts_atomically():
    events = []
    responses = {
        ("POST", "/api/transfers/receive"): deque([_receipt("receive-op")]),
        ("GET", "/api/operations/receive-op"): deque(
            [_record("receive-op", "running"), _record("receive-op", "completed")]
        ),
        ("POST", "/api/transfers/activate"): deque([_receipt("activate-op")]),
        ("GET", "/api/operations/activate-op"): deque(
            [_record("activate-op", "running"), _record("activate-op", "completed")]
        ),
    }

    def peer(method, path, payload, timeout):
        events.append(("peer", method, path, payload, timeout))
        return responses[(method, path)].popleft()

    _run_transfer(peer, events)

    sequence = [(event[1], event[2]) for event in events if event[0] == "peer"]
    assert sequence == [
        ("POST", "/api/transfers/receive"),
        ("GET", "/api/operations/receive-op"),
        ("GET", "/api/operations/receive-op"),
        ("POST", "/api/transfers/activate"),
        ("GET", "/api/operations/activate-op"),
        ("GET", "/api/operations/activate-op"),
    ]
    receive_request = next(
        event
        for event in events
        if event[:3] == ("peer", "POST", "/api/transfers/receive")
    )
    assert receive_request[3] == {
        "slug": "demo",
        **TRANSFER,
        "confirm_slug": "demo",
        "confirm_phrase": "RECEIVE TRANSFER demo",
    }
    activate_request = next(
        event
        for event in events
        if event[:3] == ("peer", "POST", "/api/transfers/activate")
    )
    assert activate_request[3] == {
        "slug": "demo",
        **TRANSFER,
        "confirm_slug": "demo",
        "confirm_phrase": "ACTIVATE TRANSFER demo",
    }
    assert [event[0] for event in events[:4]] == [
        "stop",
        "quiesced",
        "backup",
        "quiesced",
    ]
    assert all(event[4] > 0 for event in events if event[0] == "peer")
    finalize_index = next(
        index for index, event in enumerate(events) if event[0] == "finalized"
    )
    receive_completion_index = max(
        index
        for index, event in enumerate(events)
        if event[:3] == ("peer", "GET", "/api/operations/receive-op")
    )
    activate_index = next(
        index
        for index, event in enumerate(events)
        if event[:3] == ("peer", "POST", "/api/transfers/activate")
    )
    assert receive_completion_index < finalize_index < activate_index
    assert events[finalize_index] == (
        "finalized",
        "demo",
        TRANSFER["project_id"],
        TRANSFER["destination_host_id"],
    )


def test_guided_transfer_stops_when_source_is_not_quiesced():
    events = []

    def assert_quiesced(slug, project_id):
        events.append(("quiesced", slug, project_id))
        raise RuntimeError("source runtime remains active")

    with pytest.raises(RuntimeError, match="source runtime remains active"):
        guided_transfer(
            "demo",
            C(),
            stop=lambda slug: events.append(("stop", slug)),
            backup=lambda slug: events.append(("backup", slug)),
            assert_quiesced=assert_quiesced,
            finalize_source=lambda *_: pytest.fail("source must not finalize"),
            peer_call=lambda *_: pytest.fail(
                "peer must not receive an active source"
            ),
            **TRANSFER,
        )

    assert events == [
        ("stop", "demo"),
        ("quiesced", "demo", TRANSFER["project_id"]),
    ]


def test_guided_transfer_rechecks_quiescence_after_backup_before_peer_receive():
    events = []
    checks = {"count": 0}

    def assert_quiesced(slug, project_id):
        checks["count"] += 1
        events.append(("quiesced", slug, project_id))
        if checks["count"] == 2:
            raise RuntimeError("source became active during backup")

    with pytest.raises(RuntimeError, match="source became active during backup"):
        guided_transfer(
            "demo",
            C(),
            stop=lambda slug: events.append(("stop", slug)),
            backup=lambda slug: events.append(("backup", slug)),
            assert_quiesced=assert_quiesced,
            finalize_source=lambda *_: pytest.fail("source must not finalize"),
            peer_call=lambda *_: pytest.fail(
                "peer must not receive an active source"
            ),
            **TRANSFER,
        )

    assert events == [
        ("stop", "demo"),
        ("quiesced", "demo", TRANSFER["project_id"]),
        ("backup", "demo"),
        ("quiesced", "demo", TRANSFER["project_id"]),
    ]


def test_guided_transfer_does_not_start_after_failed_receive_operation():
    events = []

    def peer(method, path, payload, timeout):
        events.append((method, path))
        if method == "POST":
            return _receipt("receive-op")
        return _record("receive-op", "failed")

    with pytest.raises(RuntimeError, match="Peer receive transfer operation failed"):
        _run_transfer(peer, events)

    assert ("POST", "/api/transfers/activate") not in events
    assert not any(event[0] == "finalized" for event in events)


def test_guided_transfer_does_not_activate_when_source_finalization_fails():
    events = []
    responses = {
        ("POST", "/api/transfers/receive"): deque([_receipt("receive-op")]),
        ("GET", "/api/operations/receive-op"): deque(
            [_record("receive-op", "completed")]
        ),
    }

    def peer(method, path, payload, timeout):
        events.append(("peer", method, path))
        return responses[(method, path)].popleft()

    def finalize_source(slug, project_id, destination_host_id):
        events.append(("finalize", slug, project_id, destination_host_id))
        raise RuntimeError("sensitive source-finalization detail")

    with pytest.raises(RuntimeError, match="Source transfer finalization failed") as raised:
        _run_transfer(peer, events, finalize_source=finalize_source)

    assert "sensitive source-finalization detail" not in str(raised.value)
    assert ("peer", "POST", "/api/transfers/activate") not in events


@pytest.mark.parametrize("state", ["failed", "interrupted"])
def test_guided_transfer_ends_after_unsuccessful_atomic_activation(state):
    events = []
    responses = {
        ("POST", "/api/transfers/receive"): deque([_receipt("receive-op")]),
        ("GET", "/api/operations/receive-op"): deque(
            [_record("receive-op", "completed")]
        ),
        ("POST", "/api/transfers/activate"): deque([_receipt("activate-op")]),
        ("GET", "/api/operations/activate-op"): deque(
            [_record("activate-op", state, error="sensitive activation detail")]
        ),
    }

    def peer(method, path, payload, timeout):
        events.append(("peer", method, path))
        return responses[(method, path)].popleft()

    with pytest.raises(
        RuntimeError, match=fr"Peer activate transfer operation {state}"
    ) as raised:
        _run_transfer(peer, events)

    assert "sensitive activation detail" not in str(raised.value)
    assert any(event[0] == "finalized" for event in events)


def test_guided_transfer_does_not_activate_after_locked_receive_operation():
    events = []

    def peer(method, path, payload, timeout):
        events.append((method, path))
        if method == "POST":
            return _receipt("receive-op")
        return _record(
            "receive-op", "failed", current_step="locked", error="operation_locked"
        )

    with pytest.raises(RuntimeError, match="Peer receive transfer operation is locked"):
        _run_transfer(peer, events)

    assert ("POST", "/api/transfers/activate") not in events


def test_guided_transfer_times_out_before_activation(monkeypatch):
    now = {"value": 0.0}
    monkeypatch.setattr(failover, "PEER_OPERATION_TIMEOUT_SECONDS", 0.25)
    monkeypatch.setattr(failover, "PEER_OPERATION_POLL_INTERVAL_SECONDS", 0.25)
    monkeypatch.setattr(failover.time, "monotonic", lambda: now["value"])
    monkeypatch.setattr(
        failover.time,
        "sleep",
        lambda seconds: now.__setitem__("value", now["value"] + seconds),
    )
    events = []

    def peer(method, path, payload, timeout):
        events.append((method, path))
        if method == "POST":
            return _receipt("receive-op")
        return _record("receive-op", "running")

    with pytest.raises(RuntimeError, match="Peer receive transfer operation timed out"):
        _run_transfer(peer, events)

    assert ("POST", "/api/transfers/activate") not in events


def test_guided_transfer_rejects_malformed_operation_receipt_before_activation():
    events = []

    def peer(method, path, payload, timeout):
        events.append((method, path))
        return {
            "ok": True,
            "accepted": True,
            "operation_id": "receive-op",
            "operation_url": "/api/operations/other-op",
        }

    with pytest.raises(
        RuntimeError, match="Peer receive transfer operation response was malformed"
    ):
        _run_transfer(peer, events)

    assert ("POST", "/api/transfers/receive") in events
    assert ("POST", "/api/transfers/activate") not in events

```


## FILE: source/tests/test_hardening11_red_blue.py

SHA256: c0639e0edc66abb29fdac71605866a0f1a488de357df153d743f825a2898546e | Bytes: 13557 | Git mode: 100644

```
from __future__ import annotations

import json
import stat
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest

from devfleet import auth, containers, core
from devfleet.analyzer import analyze_project, has_blockers
from devfleet.core import SETTINGS


def _compose_project(tmp_path: Path, body: str) -> Path:
    project = tmp_path / "red-compose"
    project.mkdir()
    (project / "compose.yaml").write_text(body, encoding="utf-8")
    return project


@pytest.mark.parametrize("profile", ["strict", "balanced", "fast"])
@pytest.mark.parametrize(
    ("body", "code"),
    [
        ("services:\n  app:\n    privileged: true\n", "docker.privileged"),
        ("services:\n  app:\n    use_api_socket: true\n", "compose.use-api-socket"),
        ("services:\n  app:\n    volumes_from: [base]\n", "compose.volumes-from"),
        ("services:\n  app:\n    provider: {type: evil}\n", "compose.provider"),
        ("services:\n  app:\n    post_start: [{command: whoami, privileged: true}]\n", "compose.post-start"),
        ("services:\n  app:\n    future_execution_field: true\n", "compose.unknown-field"),
    ],
)
def test_compose_red_attack_corpus_blocks_every_profile(tmp_path: Path, profile: str, body: str, code: str) -> None:
    findings = analyze_project(_compose_project(tmp_path, body), profile, force=True)
    assert has_blockers(findings)
    assert code in {item["code"] for item in findings}


def test_compose_extends_nested_and_host_root_bind_are_not_effective_model_gaps(tmp_path: Path) -> None:
    project = _compose_project(
        tmp_path,
        """services:
  app:
    extends:
      file: middle.yml
      service: middle
""",
    )
    (project / "middle.yml").write_text(
        """services:
  middle:
    extends:
      file: evil.yml
      service: inherited
""",
        encoding="utf-8",
    )
    (project / "evil.yml").write_text(
        """services:
  inherited:
    privileged: true
    network_mode: host
    volumes: ["/:/host"]
""",
        encoding="utf-8",
    )
    findings = analyze_project(project, "strict", force=True)
    codes = {item["code"] for item in findings}
    assert has_blockers(findings)
    assert "compose.extends" in codes
    assert "docker.privileged" not in codes or "compose.extends" in codes


def test_compose_include_escape_and_symlink_escape_are_blocked(tmp_path: Path) -> None:
    project = _compose_project(tmp_path, "include:\n  - ../outside.yml\nservices: {}\n")
    findings = analyze_project(project, "strict", force=True)
    assert has_blockers(findings)
    assert "compose.include" in {item["code"] for item in findings}
    assert "compose.path-reference" in {item["code"] for item in findings}

    outside = tmp_path / "outside.yml"
    outside.write_text("services: {}\n", encoding="utf-8")
    link = project / "evil.yml"
    try:
        link.symlink_to(outside)
    except OSError:
        pytest.skip("symbolic-link creation unavailable")
    (project / "compose.yaml").write_text("""services:
  app:
    extends: {file: evil.yml, service: x}
""", encoding="utf-8")
    findings = analyze_project(project, "strict", force=True)
    assert {"compose.path-escape", "project.symlink-escape"} & {item["code"] for item in findings}


@pytest.mark.parametrize("argument", [
    "--privileged", "--network=host", "--network", "host", "--pid=host", "--pid", "host",
    "--ipc", "--uts", "--userns=host", "--volume=/:/host", "-v", "/:/host", "--mount", "type=bind,src=/,dst=/host",
    "--device=/dev/kvm", "--cap-add=SYS_ADMIN", "--security-opt", "seccomp=unconfined", "--env-file=/tmp/x",
])
@pytest.mark.parametrize("profile", ["strict", "balanced", "fast"])
def test_devcontainer_structured_runargs_attack_corpus_blocks(tmp_path: Path, argument: str, profile: str) -> None:
    project = tmp_path / "devcontainer"
    (project / ".devcontainer").mkdir(parents=True)
    (project / ".devcontainer/devcontainer.json").write_tex