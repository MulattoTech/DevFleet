# DevFleet source part 099

Full-source UTF-8 byte interval [4557000, 4603500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: a8e016ee46686b79d44355e9e23f9674612507e9dbc1593bc02c8aa88614791e

<!-- BEGIN SOURCE SLICE -->
 "Invoke-MultipassConfigurationProbe $mp @('get','local.privileged-mounts')"
    assert driver_probe in prereqs
    assert mount_probe in prereqs
    assert "if($selectedDriver -ne $desiredDriver)" in prereqs
    assert "if($selectedPrivilegedMounts -ne 'false')" in prereqs
    driver_write = 'Invoke-External $mp @(' + "'set',\"local.driver=$desiredDriver\"" + ')'
    mount_write = "Invoke-External $mp @('set','local.privileged-mounts=false')"
    assert prereqs.index("if($selectedDriver -ne $desiredDriver)") < prereqs.index(driver_write)
    assert prereqs.index("if($selectedPrivilegedMounts -ne 'false')") < prereqs.index(mount_write)


def test_connected_dependency_probes_and_official_downloads_have_network_deadlines():
    common = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "ArgumentList @('--version') -TimeoutSeconds 60" in common
    assert "ArgumentList @('source','list','--disable-interactivity') -TimeoutSeconds 60" in common
    assert "ArgumentList @('search','--id','Microsoft.PowerShell','--exact','--source','winget','--disable-interactivity') -TimeoutSeconds 60" in common
    assert "Invoke-RestMethod -UseBasicParsing -TimeoutSec 60" in common
    assert "Invoke-WebRequest -UseBasicParsing -TimeoutSec 60" in common
    assert "$client.Timeout=[TimeSpan]::FromSeconds(60)" in common


def test_install_defers_node_identity_until_after_reboot_gate():
    install = (ROOT / "Install-DevFleet.ps1").read_text(encoding="utf-8")
    identity = "$nodeIdentity = Get-OrCreateNodeIdentity -Role $Role"
    secrets = "Get-OrCreateSecrets | Out-Null"
    assert install.count(identity) == 1
    assert install.count(secrets) == 1
    assert install.index(secrets) < install.index(identity)
    assert install.index("if (Test-PendingReboot)") < install.index(identity)


def test_install_rechecks_new_pending_reboot_after_windows_tailscale_stage():
    install = (ROOT / "Install-DevFleet.ps1").read_text(encoding="utf-8")
    marker = "Write-StageMarker 'windows-tailscale'"
    next_stage = "if(-not (Test-StageMarker 'host-agent'))"
    marker_end = install.index(marker) + len(marker)
    stage_boundary = install[marker_end:install.index(next_stage, marker_end)]
    assert "Test-PendingReboot" in stage_boundary
    assert "after the Windows Tailscale stage" in stage_boundary
    assert "exit 3010" in stage_boundary

```


## FILE: source/tests/test_v1211_stopped_capabilities.py

SHA256: 1ceffa011ec0d19a052a4d3551879ee1dfd089d9ee07f21be3b05cd7cb40ab84 | Bytes: 5347 | Git mode: 100644

```
from __future__ import annotations

import json
from dataclasses import replace
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from devfleet import main, projects


def _project(root: Path, slug: str, state: str, *, isolation: str = "vm") -> Path:
    project = root / slug
    (project / ".devfleet").mkdir(parents=True)
    metadata = {
        "schema_version": 3,
        "managed_by": "devfleet",
        "project_id": "12345678-1234-1234-1234-123456789abc",
        "slug": slug,
        "identity": slug,
        "display_name": "Stopped Project",
        "runtime_isolation": isolation,
        "runtime_type": isolation,
        "runtime_provider": "multipass-host-agent" if isolation == "vm" else "docker-compose",
        "lifecycle_status": state,
        "runtime_status": state,
        "runtime_id": f"devfleet-project-{slug}",
        "host_id": "test-node",
        "runtime_address": "172.30.1.20" if state == "running" else "",
        "ssh_alias": f"devfleet-project-{slug}",
        "ssh_host_key_pinned": state == "running",
        "ssh_authenticated": state == "running",
        "ssh_validation_passed": state == "running",
        "workspace_provisioned": True,
        "resource_profile": "large",
        "resource_limits": {"cpus": 4, "memory": "8G", "memory_gb": 8, "disk_gb": 80},
    }
    (project / ".devfleet" / "project.json").write_text(json.dumps(metadata), encoding="utf-8")
    return project


@pytest.mark.parametrize(
    ("state", "can_start", "can_stop", "live", "transitioning"),
    [
        ("stopped", True, False, False, False),
        ("starting", False, True, False, True),
        ("running", False, True, True, False),
        ("stopping", False, False, False, True),
        ("unreachable", True, False, False, False),
    ],
)
def test_vm_capability_state_matrix(tmp_path, monkeypatch, state, can_start, can_stop, live, transitioning):
    monkeypatch.setattr(projects, "SETTINGS", replace(projects.SETTINGS, workspaces=tmp_path))
    _project(tmp_path, state, state)
    caps = projects.project_capabilities(state)
    assert caps["can_start"] is can_start
    assert caps["can_stop"] is can_stop
    assert caps["runtime_transitioning"] is transitioning
    assert caps["can_query_live_metrics"] is live
    assert caps["can_query_application_health"] is live
    assert caps["can_query_logs"] is live


def test_stopped_runtime_endpoint_makes_zero_live_calls(tmp_path, monkeypatch):
    settings = replace(projects.SETTINGS, workspaces=tmp_path)
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(main, "SETTINGS", settings)
    _project(tmp_path, "demo", "stopped")
    monkeypatch.setattr(main, "inspect_runtime", lambda *_: pytest.fail("inspect must not run"))
    monkeypatch.setattr(main, "runtime_health", lambda *_: pytest.fail("health must not run"))
    result = main.api_project_runtime("demo")
    assert result["runtime"]["live_metrics"] == "unavailable"
    assert result["health"]["status"] == "not-checked"


def test_stopped_logs_endpoints_make_zero_guest_calls(tmp_path, monkeypatch):
    settings = replace(projects.SETTINGS, workspaces=tmp_path)
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(main, "SETTINGS", settings)
    _project(tmp_path, "demo", "stopped")
    monkeypatch.setattr(main, "project_logs", lambda *_args, **_kwargs: pytest.fail("logs must not run"))
    monkeypatch.setattr(main, "ui", lambda *_args, **_kwargs: None)
    request = type("Request", (), {})()
    response = main.ui_project_logs(request, "demo")
    assert response.status_code == 409
    with pytest.raises(Exception) as exc:
        main.api_project_logs("demo")
    assert getattr(exc.value, "status_code", None) == 409


def test_stopped_project_html_is_terminal_and_keeps_resources(tmp_path, monkeypatch):
    settings = replace(projects.SETTINGS, workspaces=tmp_path)
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(main, "SETTINGS", settings)
    _project(tmp_path, "demo", "stopped")
    catalog = projects.list_project_catalog()
    assert catalog[0]["resource_limits"] == {"cpus": 4, "memory": "8G", "memory_gb": 8, "disk_gb": 80}
    template = (Path(__file__).parents[1] / "app" / "templates" / "index.html").read_text(encoding="utf-8")
    js = (Path(__file__).parents[1] / "app" / "static" / "app.js").read_text(encoding="utf-8")
    assert "Project is stopped" in template
    assert "Start the project to view live logs" in template
    assert "caps.can_query_logs" in template
    assert "fetchWithTimeout" in js and "AbortController" in js


def test_container_workspace_nonregression_when_application_stopped(tmp_path, monkeypatch):
    monkeypatch.setattr(projects, "SETTINGS", replace(projects.SETTINGS, workspaces=tmp_path))
    _project(tmp_path, "container-demo", "stopped", isolation="container")
    meta = projects.load_meta(tmp_path / "container-demo")
    meta.update({"workspace_host": "devfleet-primary", "ssh_alias": "devfleet-primary", "workspace_accessible": True})
    ready = projects.workspace_readiness("container-demo", meta)
    caps = projects.project_capabilities("container-demo", meta)
    assert ready["ready"] is True
    assert caps["can_open_workspace"] is True
    assert caps["can_query_logs"] is False

```


## FILE: source/tests/test_v121_auth_performance.py

SHA256: a88a21055e555d85b2ebfa0ba63a18372c49dbb16a2f0c517efd71b3485fff98 | Bytes: 5903 | Git mode: 100644

```
"""Regression coverage for the v1.2.1 session and dashboard contracts.

These tests intentionally exercise the ASGI app in-process.  They never start a
service and the performance test uses a mocked five-second peer instead of a
real network endpoint.
"""

import re
import time

import pytest


try:
    from fastapi.testclient import TestClient
    from devfleet import main
    from devfleet import status as status_module
except Exception as exc:  # pragma: no cover - depends on the host test image
    pytest.skip(
        f"FastAPI application tests unavailable in this environment: {exc}",
        allow_module_level=True,
    )


def _no_redirect(client, method, url, **kwargs):
    """Support both Starlette/TestClient keyword spellings across versions."""
    try:
        return getattr(client, method)(url, follow_redirects=False, **kwargs)
    except TypeError:
        return getattr(client, method)(url, allow_redirects=False, **kwargs)


def _client():
    try:
        return TestClient(main.app)
    except Exception as exc:  # pragma: no cover - dependency-version specific
        pytest.skip(f"TestClient unavailable in this environment: {exc}")


def _csrf(html):
    match = re.search(r'name="csrf_token" value="([^"]+)"', html)
    assert match, "expected a rendered CSRF form token"
    return match.group(1)


def _signed_in_client():
    client = _client()
    login_page = client.get("/login")
    assert login_page.status_code == 200
    token = _csrf(login_page.text)
    response = _no_redirect(
        client,
        "post",
        "/login",
        data={
            "username": "test",
            "password": "test-password",
            "next": "/",
            "csrf_token": token,
        },
    )
    assert response.status_code == 303
    assert response.headers["location"] == "/"
    assert "devfleet_session" in client.cookies
    return client


def test_session_login_logout_and_csrf_contract():
    client = _client()

    login_page = client.get("/login")
    assert login_page.status_code == 200
    login_csrf = _csrf(login_page.text)
    assert "devfleet_login_csrf" in client.cookies

    rejected = _no_redirect(
        client,
        "post",
        "/login",
        data={
            "username": "test",
            "password": "test-password",
            "next": "/",
            "csrf_token": "wrong-token",
        },
    )
    assert rejected.status_code == 401
    assert "devfleet_session" not in client.cookies

    signed_in = _no_redirect(
        client,
        "post",
        "/login",
        data={
            "username": "test",
            "password": "test-password",
            "next": "/",
            "csrf_token": login_csrf,
        },
    )
    assert signed_in.status_code == 303
    assert signed_in.headers["location"] == "/"
    assert client.cookies.get("devfleet_session")

    index = client.get("/")
    assert index.status_code == 200
    session_csrf = _csrf(index.text)

    missing_csrf = _no_redirect(client, "post", "/logout", data={})
    assert missing_csrf.status_code == 403
    assert client.get("/").status_code == 200

    logged_out = _no_redirect(
        client, "post", "/logout", headers={"Sec-Fetch-Site": "same-origin"}, data={"csrf_token": session_csrf}
    )
    assert logged_out.status_code == 303
    assert logged_out.headers["location"].startswith("/login")
    assert _no_redirect(client, "get", "/").status_code == 303


def test_api_token_contract():
    client = _client()

    assert client.get("/api/status").status_code == 401
    assert client.get("/api/status", headers={"X-DevFleet-Token": "wrong"}).status_code == 401

    response = client.get("/api/status", headers={"X-DevFleet-Token": "test-token"})
    assert response.status_code == 200
    assert response.json()["node"] == "test-node"


def test_index_uses_catalog_and_snapshots_without_waiting_for_a_slow_peer(monkeypatch):
    client = _signed_in_client()
    catalog_calls = []
    snapshot_calls = []
    slow_peer_calls = []

    def catalog():
        catalog_calls.append(True)
        return [{"slug": "catalog-only", "display_name": "Catalog project"}]

    def live_projects_must_not_run():
        raise AssertionError("normal index rendering used live project inspection")

    def slow_peer():
        slow_peer_calls.append(True)
        time.sleep(5.0)
        return {"configured": True, "ok": True}

    def snapshot():
        snapshot_calls.append(True)
        return {
            "updated_at": "2026-08-10T00:00:00Z",
            "nodes": [],
            "containers": [],
            "snapshot": {"stale": False, "refreshing": False},
        }

    monkeypatch.setattr(status_module, "list_project_catalog", catalog)
    monkeypatch.setattr(status_module, "list_projects", live_projects_must_not_run)
    monkeypatch.setattr(status_module, "runtime_snapshot", lambda: status_module._cheap_runtime())
    monkeypatch.setattr(status_module, "peer_node_status", slow_peer)
    monkeypatch.setattr(main, "cluster_snapshot", snapshot)
    monkeypatch.setattr(main, "peer_call", lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("peer_call used")))
    monkeypatch.setattr(main, "get_host_capacity", lambda: (_ for _ in ()).throw(AssertionError("host probe used")))
    monkeypatch.setattr(main, "get_provider_status", lambda: (_ for _ in ()).throw(AssertionError("provider probe used")))
    monkeypatch.setattr(main, "analyze_project", lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("analyzer used")))

    started = time.perf_counter()
    response = client.get("/")
    elapsed = time.perf_counter() - started

    assert response.status_code == 200
    assert "catalog-only" in response.text
    assert catalog_calls == [True]
    assert snapshot_calls == [True]
    assert slow_peer_calls == []
    assert elapsed < 2.0, f"index rendering took {elapsed:.2f}s"

```


## FILE: source/tests/test_v122_auth_snapshot_package.py

SHA256: e8537161bda817b8cd7539ce4c40a078b8cef1d0a88477c3e8cf33910056f285 | Bytes: 3617 | Git mode: 100644

```
import os
import stat
import tarfile
from pathlib import Path

import pytest

from devfleet import auth, status

ROOT = Path(__file__).resolve().parents[1]


def test_v122_ttls_and_nonempty_secret_guards():
    assert auth.SESSION_TTL == 12 * 60 * 60
    assert auth.REMEMBERED_TTL == 7 * 24 * 60 * 60
    assert not auth.valid_credentials("", "anything")
    assert not auth.valid_credentials("test", "")
    assert auth.session_cookie_options()["samesite"] == "strict"


def test_session_csrf_and_credential_generation_invalidation(tmp_path, monkeypatch):
    monkeypatch.setattr(auth, "_session_path", lambda: tmp_path / "sessions.json")
    token, ttl, csrf = auth.issue_session("test")
    assert ttl == auth.SESSION_TTL
    assert auth.validate_session(token) == "test"
    record = auth._load_sessions()[token]
    assert auth.validate_session_csrf(_request_with_cookie(token), csrf)
    original_password = auth.SETTINGS.admin_password
    try:
        object.__setattr__(auth.SETTINGS, "admin_password", "rotated-password")
        assert auth.validate_session(token) is None
        assert record["credential_generation"] != auth._credential_generation()
    finally:
        object.__setattr__(auth.SETTINGS, "admin_password", original_password)


class _Request:
    def __init__(self, token):
        self.cookies = {auth.SESSION_COOKIE: token}


def _request_with_cookie(token):
    return _Request(token)


def test_login_backoff_is_bounded_and_source_scoped(monkeypatch):
    auth._LOGIN_FAILURES.clear()
    for _ in range(20):
        auth._record_login_failure("bad-user", "source-a", now=100.0)
    delay = auth.login_backoff_seconds("bad-user", "source-a", now=100.0)
    assert 0 < delay <= auth._BACKOFF_MAX
    assert auth.login_backoff_seconds("bad-user", "source-b", now=100.0) == 0


def test_snapshot_schedule_reserves_before_submit(monkeypatch):
    status._SNAPSHOTS["runtime"].update({"refreshing": False, "value": None, "updated_at": 0.0})
    submitted = []
    class Executor:
        def submit(self, fn, name):
            submitted.append((fn, name))
    monkeypatch.setattr(status, "_SNAPSHOT_EXECUTOR", Executor())
    status._schedule_snapshot("runtime")
    status._schedule_snapshot("runtime")
    assert len(submitted) == 1
    status._SNAPSHOTS["runtime"]["refreshing"] = False


def test_peer_failure_enters_backoff_without_retries(monkeypatch):
    status._PEER_STATE.update({"failures": 0, "retry_after": 0.0, "circuit_until": 0.0, "value": None})
    monkeypatch.setattr(status, "load_peer", lambda: {"Url": "http://peer", "Token": "token"})
    calls = []
    def fail(*args, **kwargs):
        calls.append(args[0])
        raise OSError("offline")
    monkeypatch.setattr(status.httpx, "get", fail)
    first = status.peer_node_status()
    second = status.peer_node_status()
    assert first["ok"] is False and second["status"] in {"unreachable", "backoff"}
    assert calls == ["http://peer/api/node/status"]


def test_verifier_is_pinned_to_v122_and_checks_hooks():
    verifier = (ROOT / "tools/verify_package.py").read_text(encoding="utf-8")
    assert 're.fullmatch(r"\\d+\\.\\d+\\.\\d+", PACKAGE_VERSION)' in verifier
    assert "linux_executable_hooks" in verifier
    assert "Basic" not in (ROOT / "app/devfleet/auth.py").read_text(encoding="utf-8")


def test_all_trusted_hooks_are_executable_on_posix():
    if os.name == "nt":
        pytest.skip("Windows does not expose POSIX execute bits")
    hooks = list((ROOT / "templates").glob("*/.devfleet/codexpro-bootstrap.sh"))
    assert hooks
    assert all(p.stat().st_mode & stat.S_IXUSR for p in hooks)

```


## FILE: source/tests/test_v122_lifecycle_archive.py

SHA256: acd775b9253d3b6cf0a22d984731107e49253d632b05d000a28129d41875eb30 | Bytes: 2925 | Git mode: 100644

```
import json
from pathlib import Path

import pytest

from devfleet.resource_profiles import custom_resource_metadata, write_resource_override
from devfleet.workspace_archives import create_workspace_archive, inspect_workspace


ROOT = Path(__file__).resolve().parents[1]


def test_custom_limits_are_bounded_and_host_pid_is_rejected():
    limits = custom_resource_metadata({'cpus': 3, 'memory_gb': 6, 'disk_gb': 60, 'pids': 2048})
    assert limits['cpus'] == 3.0 and limits['memory_gb'] == 6.0 and limits['pids'] == 2048
    with pytest.raises(ValueError, match='Host PID namespace'):
        custom_resource_metadata({'cpus': 2, 'memory_gb': 4, 'disk_gb': 40, 'pids': 512, 'pid_mode': 'host'})


def test_compose_override_uses_custom_limits(tmp_path: Path):
    project = tmp_path / 'demo'
    (project / '.devfleet').mkdir(parents=True)
    compose = project / 'compose.yaml'
    compose.write_text('services:\n  app:\n    image: alpine\n', encoding='utf-8')
    override = write_resource_override(project, compose, {'cpus': 2, 'memory_gb': 4, 'disk_gb': 40, 'pids': 512})
    assert override is not None
    assert 'cpus: 2.0' in override.read_text(encoding='utf-8')
    assert 'mem_limit: 4g' in override.read_text(encoding='utf-8')


def test_archive_reports_exclusions_and_estimate(tmp_path: Path):
    workspace = tmp_path / 'demo'
    (workspace / '.devfleet').mkdir(parents=True)
    (workspace / '.devfleet' / 'project.json').write_text('{"project_id":"p"}\n', encoding='utf-8')
    (workspace / 'src').mkdir()
    (workspace / 'src' / 'main.py').write_text('print(1)\n', encoding='utf-8')
    (workspace / 'node_modules').mkdir()
    (workspace / 'node_modules' / 'generated.bin').write_bytes(b'x' * 10)
    inspected = inspect_workspace(workspace)
    assert inspected['generated_dirs'] == ['node_modules']
    assert inspected['generated_bytes'] == 10
    assert inspected['estimated_archive_bytes'] >= inspected['bytes']
    result = create_workspace_archive(workspace, 'demo', tmp_path / 'demo.tar.gz')
    assert result['verified'] is True
    assert result['generated_details'][0]['path'] == 'node_modules'


def test_host_agent_command_contract_is_explicit():
    text = (ROOT / 'windows' / 'DevFleet-HostAgent.ps1').read_text(encoding='utf-8')
    assert "docker compose build && docker compose up -d" in text
    assert "^\\./\\.devfleet/(bootstrap|health-check|smoke-test|codexpro-bootstrap)\\.sh$" in text
    assert "docker\\s+(run|exec)" in text
    assert 'docker compose version' in text


def test_every_template_contains_lifecycle_commands():
    required = {'start_command', 'stop_command', 'restart_command', 'rebuild_command', 'logs_command', 'codexpro_command'}
    files = list((ROOT / 'templates').glob('*/.devfleet/template.json'))
    assert len(files) == 20
    for path in files:
        data = json.loads(path.read_text(encoding='utf-8'))
        assert required <= data.keys(), path

```


## FILE: source/tests/test_v122_main_endpoints.py

SHA256: 2c5ca92e1e82ad5b08d479de308347045410861c60df9abafd86dc7f3303e420 | Bytes: 5260 | Git mode: 100644

```
"""Focused v1.2.2 backend UI endpoint contracts."""

import json
import re
from dataclasses import replace

import pytest

try:
    from fastapi.testclient import TestClient
    from devfleet import main
except Exception as exc:  # pragma: no cover - dependency-version specific
    pytest.skip(f'FastAPI application tests unavailable in this environment: {exc}', allow_module_level=True)


def _no_redirect(client, method, url, **kwargs):
    try:
        return getattr(client, method)(url, follow_redirects=False, **kwargs)
    except TypeError:
        return getattr(client, method)(url, allow_redirects=False, **kwargs)


def _signed_in():
    client = TestClient(main.app)
    login = client.get('/login')
    login_csrf = re.search(r'name="csrf_token" value="([^"]+)"', login.text).group(1)
    response = _no_redirect(client, 'post', '/login', data={
        'username': 'test', 'password': 'test-password', 'next': '/',
        'csrf_token': login_csrf,
    })
    assert response.status_code == 303
    index = client.get('/')
    session_csrf = re.search(r'name="csrf_token" value="([^"]+)"', index.text).group(1)
    return client, session_csrf


def _owned_project(root, slug='demo', *, provider='docker-compose', **overrides):
    project = root / slug
    (project / '.devfleet').mkdir(parents=True)
    (project / '.devfleet/project.json').write_text(json.dumps({
        'schema_version': 3,
        'managed_by': 'devfleet',
        'project_id': '12345678-1234-1234-1234-123456789abc',
        'slug': slug,
        'identity': slug,
        'runtime_provider': provider,
        'runtime_id': 'df_' + slug.replace('-', '_'),
        'host_id': 'test-node',
        **overrides,
    }), encoding='utf-8')
    return project


def test_ui_logs_are_session_authenticated_bounded_and_provider_aware(tmp_path, monkeypatch):
    client, _csrf = _signed_in()
    _owned_project(
        tmp_path,
        provider='multipass-host-agent',
        runtime_isolation='vm',
        lifecycle_status='running',
        runtime_address='172.30.1.20',
    )
    monkeypatch.setattr(main, 'SETTINGS', replace(main.SETTINGS, workspaces=tmp_path))
    monkeypatch.setattr(main, 'project_logs', lambda slug, tail: f'{slug}:{tail}')

    assert client.get('/ui/projects/demo/logs?tail=9999').json() == {
        'ok': True, 'slug': 'demo', 'tail': 500,
        'provider': 'multipass-host-agent', 'logs': 'demo:500',
    }
    assert _no_redirect(TestClient(main.app), 'get', '/ui/projects/demo/logs').status_code == 303
    assert client.get('/api/projects/demo/logs?tail=9999').status_code == 401


def test_operation_ui_and_api_unknown_ids_are_intentional_404s():
    client, _csrf = _signed_in()
    assert client.get('/ui/operations/not-real').status_code == 404
    assert client.get('/operations/not-real').status_code == 404
    assert client.get('/api/operations/not-real').status_code == 401
    assert client.get('/api/operations/not-real', headers={'X-DevFleet-Token': 'test-token'}).status_code == 404


def test_project_action_returns_json_202_or_legacy_redirect_and_requires_csrf(tmp_path, monkeypatch):
    monkeypatch.setattr(main, 'SETTINGS', replace(main.SETTINGS, workspaces=tmp_path))
    _owned_project(tmp_path)
    client, csrf = _signed_in()
    monkeypatch.setattr(main, 'submit_operation', lambda *args, **kwargs: 'start-test-op')

    missing_csrf = _no_redirect(client, 'post', '/projects/demo/start', headers={'Accept': 'application/json'}, data={})
    assert missing_csrf.status_code == 403

    json_response = _no_redirect(client, 'post', '/projects/demo/start', headers={'Accept': 'application/json', 'Sec-Fetch-Site': 'same-origin'}, data={'csrf_token': csrf})
    assert json_response.status_code == 202
    assert json_response.json() == {'ok': True, 'operation_id': 'start-test-op'}

    ui_response = _no_redirect(client, 'post', '/projects/demo/start', headers={'X-DevFleet-UI': '1', 'Sec-Fetch-Site': 'same-origin'}, data={'csrf_token': csrf})
    assert ui_response.status_code == 202
    redirect_response = _no_redirect(client, 'post', '/projects/demo/start', headers={'Sec-Fetch-Site': 'same-origin'}, data={'csrf_token': csrf})
    assert redirect_response.status_code == 303
    assert redirect_response.headers['location'] == '/?operation=start-test-op'


def test_project_action_safety_checks_are_synchronous_and_action_set_is_closed(tmp_path, monkeypatch):
    monkeypatch.setattr(main, 'SETTINGS', replace(main.SETTINGS, workspaces=tmp_path))
    _owned_project(tmp_path)
    client, csrf = _signed_in()
    headers = {'Sec-Fetch-Site': 'same-origin'}
    assert _no_redirect(client, 'post', '/projects/demo/quarantine', headers=headers, data={'csrf_token': csrf}).status_code == 400
    assert _no_redirect(client, 'post', '/projects/demo/destroy', headers=headers, data={'csrf_token': csrf}).status_code == 400
    assert _no_redirect(client, 'post', '/projects/demo/not-an-action', headers=headers, data={'csrf_token': csrf}).status_code == 404
    assert 'logs' in main.PROJECT_ACTIONS
    assert {'start', 'stop', 'restart', 'inspect', 'runtime-health', 'rebuild', 'backup', 'bootstrap', 'health', 'test', 'codexpro', 'quarantine', 'destroy', 'restore-vault', 'analyze-force'} <= main.PROJECT_ACTIONS

```


## FILE: source/tests/test_v122_ui.py

SHA256: 2d3f276abc1105aa61a069eb5669c3775a0bf472929779b9722834f1ad0f366a | Bytes: 1794 | Git mode: 100644

```
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "app/templates/index.html").read_text(encoding="utf-8")
JS = (ROOT / "app/static/app.js").read_text(encoding="utf-8")
CSS = (ROOT / "app/static/style.css").read_text(encoding="utf-8")


def test_environment_wizard_has_reviewable_custom_resource_and_pid_controls():
    for field in ("custom_cpus", "custom_ram_gb", "custom_disk_gb", "pid_mode", "pid_limit"):
        assert f'name="{field}"' in HTML
    assert 'data-environment-wizard' in HTML
    assert 'data-review-summary' in HTML and 'Review before provisioning' in HTML
    assert 'initEnvironmentWizard' in JS


def test_workspace_display_uses_provider_metadata_and_not_a_global_codexdevvm_target():
    assert 'provider_label(p)' in HTML
    assert 'workspace_target(p)' in HTML
    assert 'data-provider' in HTML and 'data-workspace-target' in HTML
    assert 'Open workspace' in HTML
    assert 'ssh CodexDevVM' not in HTML


def test_project_action_sections_are_reachable():
    for tab in ('logs', 'backups', 'safety', 'isolate', 'settings'):
        assert f'?tab={tab}' in HTML
    assert 'Advanced' in HTML and 'confirm_quarantine' in HTML


def test_operation_progress_uses_same_origin_session_endpoint_with_fallback():
    assert 'data-operation-id' in HTML
    assert 'initOperationProgress' in JS
    assert 'fetch(`/operations/${encodeURIComponent(id)}`' in JS
    assert 'credentials: \'same-origin\'' in JS
    assert 'The UI endpoint is optional' in JS
    assert 'X-DevFleet-Token' not in JS
    assert '/ui/projects/${encodeURIComponent(slug)}/logs' in JS
    assert 'Refresh / API' not in HTML


def test_ui_styles_cover_review_and_custom_controls():
    assert '.custom-resource-controls' in CSS
    assert '.wizard-review' in CSS

```


## FILE: source/tests/test_v123_contracts.py

SHA256: 0012c02123620453c6a2731dced0ea6ea1aa72603fa31fe79c9afb4ffd7f411c | Bytes: 6810 | Git mode: 100644

```
import ast
import threading
import time
from pathlib import Path

from devfleet import status


ROOT = Path(__file__).resolve().parents[1]


def _function(path: Path, name: str):
    tree = ast.parse(path.read_text(encoding='utf-8'))
    return next(node for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name)


def test_project_action_submission_is_route_level_not_nested_task():
    node = _function(ROOT / 'app/devfleet/main.py', 'project_action')
    nested = next(child for child in node.body if isinstance(child, ast.FunctionDef) and child.name == 'task')
    assert any(isinstance(child, ast.Return) and isinstance(child.value, ast.Call) and getattr(getattr(child.value, 'func', None), 'id', '') == 'redirect' for child in node.body)
    assert not any('submit_operation' in ast.unparse(child) for child in nested.body)


def test_version_and_ui_contract_are_v123():
    assert (ROOT / 'VERSION').read_text(encoding='utf-8').strip() == '1.2.13'
    template = (ROOT / 'app/templates/index.html').read_text(encoding='utf-8')
    script = (ROOT / 'app/static/app.js').read_text(encoding='utf-8')
    assert 'data-existing-environment-wizard' in template
    assert all(label in template for label in ('1. Environment', '2. Resources', '3. Review', '4. Confirm'))
    assert 'initProjectActions' in script and 'X-DevFleet-UI' in script
    assert "operation.state || operation.status" in script
    assert "reconciliation-required" not in script or "interrupted" in script


def test_peer_probe_is_single_flight(monkeypatch):
    status._PEER_STATE.update({'failures': 0, 'last_failure': 0.0, 'retry_after': 0.0, 'circuit_until': 0.0, 'value': None, 'inflight': False})
    monkeypatch.setattr(status, 'load_peer', lambda: {'Url': 'http://peer', 'Token': 'token'})
    calls = []
    started = threading.Event()
    release = threading.Event()

    class Response:
        status_code = 200
        def raise_for_status(self): pass
        def json(self): return {'node': 'peer'}

    def probe(*args, **kwargs):
        if args[0] == 'http://peer/api/node/status':
            calls.append(args[0]); started.set(); release.wait(2)
        return Response()

    monkeypatch.setattr(status.httpx, 'get', probe)
    results = []
    workers = [threading.Thread(target=lambda: results.append(status.peer_node_status())) for _ in range(5)]
    workers[0].start(); assert started.wait(1)
    for worker in workers[1:]: worker.start()
    time.sleep(.05); release.set()
    for worker in workers: worker.join(2)
    assert calls == ['http://peer/api/node/status']
    assert any(result.get('status') == 'refreshing' for result in results)
    assert any(result.get('ok') is True for result in results)


def test_snapshot_failure_sets_retry_deadline(monkeypatch):
    state = status._SNAPSHOTS['runtime']
    state.update({'value': None, 'updated_at': 0.0, 'refreshing': False, 'retry_after': 0.0, 'failures': 0})
    monkeypatch.setattr(status, 'runtime_status', lambda: (_ for _ in ()).throw(RuntimeError('offline')))
    status._refresh_snapshot('runtime')
    assert state['error'] == 'offline'
    assert state['retry_after'] > time.monotonic()
    assert state['failures'] == 1


def test_laptop_surrogate_resource_policy_has_single_safe_default_and_floor():
    import json

    config = json.loads((ROOT / 'config' / 'devfleet.config.json').read_text(encoding='utf-8'))
    profile = config['RoleProfiles']['LaptopSurrogate']
    assert profile['Recommended'] == {'FailoverMemory': '5G', 'VaultMemory': '2G'}
    assert profile['MinimumTested'] == {'FailoverMemory': '4G', 'VaultMemory': '2G'}
    preflight = (ROOT / 'windows' / '00-Preflight.ps1').read_text(encoding='utf-8')
    assert '$config.RoleProfiles.LaptopSurrogate' in preflight
    assert '$minimumFailMem' in preflight and '$minimumVaultMem' in preflight


def test_vault_backup_script_rejects_plaintext_deferred_transport():
    script = (ROOT / 'linux' / 'devfleet-configure-backup').read_text(encoding='utf-8')
    assert "pairing_mode" in script
    assert "plaintext deferred-local transport is disabled" in script
    assert "RFC1918 private IPv4" not in script


def test_vault_backup_service_can_traverse_private_config_directory():
    script = (ROOT / 'linux' / 'devfleet-configure-backup').read_text(encoding='utf-8')
    assert 'chown root:devfleet-backup /etc/devfleet/restic.env' in script
    assert 'chmod 0640 /etc/devfleet/restic.env' in script
    assert 'setfacl -m u:devfleet-backup:--x /etc/devfleet' in script


def test_vault_backup_service_uses_provisioned_status_directory_acl():
    configure = (ROOT / 'linux' / 'devfleet-configure-backup').read_text(encoding='utf-8')
    backup = (ROOT / 'linux' / 'devfleet-backup').read_text(encoding='utf-8')
    assert 'setfacl -m u:devfleet-backup:--x /var/lib/devfleet' in configure
    assert 'setfacl -m u:devfleet-backup:--x /home/devrunner' in configure
    assert 'setfacl -m u:devfleet-backup:rwx /var/lib/devfleet/backup-status' in configure
    assert 'RESTIC_CACHE_DIR=/var/lib/devfleet/backup-status/restic-cache' in configure
    assert 'install -d -o devfleet-backup -g devfleet-backup -m 0700 /var/lib/devfleet/backup-status/restic-cache' in configure
    assert '[[ -d /var/lib/devfleet/backup-status && -w /var/lib/devfleet/backup-status ]]' in backup
    assert '[[ -d "${RESTIC_CACHE_DIR:-}" && -w "${RESTIC_CACHE_DIR:-}" ]]' in backup
    assert 'install -d -o devfleet-backup -g devfleet-backup -m 0750 /var/lib/devfleet/backup-status' not in backup


def test_vault_backup_excludes_protected_transaction_journal():
    backup = (ROOT / 'linux' / 'devfleet-backup').read_text(encoding='utf-8')
    assert '/home/devrunner/workspaces/.devfleet-transactions' in backup


def test_join_deployment_updates_config_and_restarts_only_devfleet_service():
    script = (ROOT / 'linux' / 'devfleet-join-deployment').read_text(encoding='utf-8')
    assert 'config=/etc/devfleet/config.json' in script
    assert 'Joined-surrogate inputs are incomplete.' in script
    assert '.deployment_id=$d|.coordinator_node_id=$c|.registration_state="joined"' in script
    assert 'install -o root -g devfleet-control -m 0640 "$tmpdir/config" "$tmpdir/config.ready"' in script
    assert 'mv -f -- "$tmpdir/config.ready" "$config"' in script
    assert 'ROLLBACK_FAILED' in script and 'node registry' in script
    assert 'systemctl restart devfleet.service' in script
    assert 'systemctl restart devfleet-vault' not in script


def test_session_store_publishes_restrictive_file_and_parent_permissions():
    auth = (ROOT / 'app' / 'devfleet' / 'auth.py').read_text(encoding='utf-8')
    assert 'os.fchmod(fd, 0o600)' in auth
    assert 'parent.chmod(0o700)' in auth
    assert 'os.replace(temp_name, path)' in auth

```


## FILE: source/tests/test_v123_durable_operations.py

SHA256: b2b93383246e28effa2efc2c2313b2406adf7603ca57fee9926a3090119a4263 | Bytes: 2250 | Git mode: 100644

```
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from devfleet import operations


def test_orphaned_running_operation_becomes_reconciliation_required():
    operation_id = "orphaned-recovery-test"
    path = operations._path(operation_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    operations.atomic_json(
        path,
        {
            "id": operation_id,
            "operation_id": operation_id,
            "state": "running",
            "idempotency_key": "orphan-key",
            "worker_instance_id": "previous-process",
            "lease_expires_at": (datetime.now(timezone.utc) - timedelta(minutes=2)).isoformat(),
        },
    )
    try:
        assert operation_id in operations.reconcile_operations()
        record = operations.get_operation(operation_id)
        assert record["state"] == "interrupted"
        assert record["recovery_required"] is True
        assert operations._find_idempotent("orphan-key") is None
    finally:
        path.unlink(missing_ok=True)


def test_live_foreign_worker_lease_is_not_interrupted():
    operation_id = "foreign-live-lease"
    operations.atomic_json(
        operations._path(operation_id),
        {
            "id": operation_id,
            "state": "running",
            "worker_instance_id": "different-worker",
            "lease_expires_at": (datetime.now(timezone.utc) + timedelta(minutes=2)).isoformat(),
        },
    )
    assert operations.reconcile_operations() == []
    assert operations.get_operation(operation_id)["state"] == "running"
    operations._path(operation_id).unlink(missing_ok=True)


def test_operation_context_refreshes_worker_lease():
    operation_id = "lease-refresh-test"
    path = operations._path(operation_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    operations.atomic_json(path, {"id": operation_id, "state": "running"})
    try:
        context = operations.OperationContext(operation_id)
        context.update(25, "still working", "test")
        record = operations.get_operation(operation_id)
        assert record["last_progress_at"]
        assert record["lease_expires_at"]
        assert record["progress"] == 25
    finally:
        path.unlink(missing_ok=True)

```


## FILE: source/tests/test_v123_vault_broker.py

SHA256: 6f4d0f458c1569459e509821d2d0e7ea3927b7dd4361caa13e627e921761cc24 | Bytes: 78343 | Git mode: 100644

```
from dataclasses import replace
import configparser
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import re
import signal
import socket
import struct
import subprocess
import sys
from types import SimpleNamespace

from devfleet import projects
from devfleet import main
from devfleet import status as devfleet_status
from fastapi.testclient import TestClient
import pytest


ROOT = Path(__file__).resolve().parents[1]


def broker_writable_namespace(existing_paths):
    """Local unit-contract model of systemd's missing-path rule, not a VM proof.

    The real broker below still parses and answers real framed socket traffic.
    Linux mount setup is the external boundary on this Windows test host.
    """
    unit = configparser.ConfigParser(interpolation=None)
    unit.read(ROOT / "app/systemd/devfleet-vault-broker@.service", encoding="utf-8")
    service = unit["Service"]
    assert service["ProtectSystem"] == "strict"
    writable = set()
    for value in service["ReadWritePaths"].split():
        optional = value.startswith("-")
        path = value.removeprefix("-").replace("__WORKSPACES__", "/home/devrunner/workspaces").replace("__QUARANTINE__", "/home/devrunner/.devfleet-quarantine")
        if path not in existing_paths:
            if optional:
                continue
            raise FileNotFoundError(f"226/NAMESPACE: {path}")
        writable.add(path)
    return writable


def test_unconfigured_packaged_broker_reaches_structured_refusal(monkeypatch):
    # The exact paths observed in C: canonical roots exist; backup-status does not.
    paths = {"/run/lock", "/home/devrunner/workspaces", "/home/devrunner/.devfleet-quarantine"}
    assert broker_writable_namespace(paths) == paths
    broker = load_broker_module(monkeypatch)
    monkeypatch.setattr(broker.os, "access", lambda *_: False)
    monkeypatch.setattr(broker, "_run_child", lambda *_: pytest.fail("Unconfigured broker launched backup"))
    server, client = socket.socketpair()
    try:
        body = b'{"action":"backup"}'
        client.sendall(struct.pack("!I", len(body)) + body)
        client.shutdown(socket.SHUT_WR)
        action = broker._parse_request(broker._receive_frame(server))
        result = broker._run_fixed_operation(*action)
        broker._send_frame(server, result)
        client.settimeout(2)
        length = struct.unpack("!I", client.recv(4))[0]
        response = json.loads(client.recv(length))
        assert response == {"ok": False, "error": "Vault backup is not configured.", "exit_code": 3}
    finally:
        server.close()
        client.close()


def test_configured_broker_retains_exact_writable_scope():
    paths = {"/run/lock", "/home/devrunner/workspaces", "/home/devrunner/.devfleet-quarantine", "/var/lib/devfleet/backup-status"}
    assert broker_writable_namespace(paths) == paths
    with pytest.raises(FileNotFoundError, match="/home/devrunner/workspaces"):
        broker_writable_namespace(paths - {"/home/devrunner/workspaces"})


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def load_broker_module(monkeypatch):
    monkeypatch.setitem(
        sys.modules,
        "pwd",
        SimpleNamespace(getpwnam=lambda _name: SimpleNamespace(pw_uid=1234)),
    )
    path = ROOT / "linux/devfleet-vault-broker"
    loader = importlib.machinery.SourceFileLoader("devfleet_vault_broker_test", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def load_request_module():
    path = ROOT / "linux/devfleet-vault-request"
    loader = importlib.machinery.SourceFileLoader("devfleet_vault_request_test", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def test_request_client_preserves_safe_broker_failure_classification(monkeypatch, capsys):
    client = load_request_module()
    response = json.dumps(
        {
            "ok": False,
            "error": "Vault operation failed.",
            "error_code": "vault-operation-failed",
            "exit_code": 17,
            "private_detail": "sensitive child output must not escape",
        },
        separators=(",", ":"),
    ).encode("utf-8")

    class BrokerConnection:
        def __init__(self):
            self.response = bytearray(struct.pack("!I", len(response)) + response)

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def settimeout(self, _seconds):
            pass

        def connect(self, _path):
            pass

        def sendall(self, _request):
            pass

        def shutdown(self, _direction):
            pass

        def recv(self, count):
            if not self.response:
                return b""
            chunk = bytes(self.response[:count])
            del self.response[:count]
            return chunk

    monkeypatch.setattr(client.socket, "AF_UNIX", 1, raising=False)
    monkeypatch.setattr(client.socket, "socket", lambda *_args, **_kwargs: BrokerConnection())

    assert client.main(["backup"]) == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err == "Vault operation failed. [error_code=vault-operation-failed; exit_code=17]\n"


def test_dashboard_vault_operations_use_the_separated_broker():
    projects = read("app/devfleet/projects.py")
    backup = projects[projects.index("def backup_project("):projects.index("def safety_backup_project(")]
    restore = projects[projects.index("def restore_from_vault("):]

    assert "/usr/local/bin/devfleet-vault-request" in projects
    assert '_vault_request("backup", timeout=1860)' in backup
    assert "/usr/local/bin/devfleet-backup" not in projects
    assert "_vault_request(action, slug, project_id, timeout=3720)" in restore
    assert "/usr/local/bin/devfleet-restore-project" not in projects
    assert "restore-copy" in restore
    assert "Standalone canonical Vault restore is disabled" in restore
    assert "restore-canonical" not in restore


def test_broker_socket_and_service_preserve_the_backup_identity_boundary():
    socket_unit = read("app/systemd/devfleet-vault-broker.socket")
    service_unit = read("app/systemd/devfleet-vault-broker@.service")
    control_unit = read("app/systemd/devfleet.service")

    for contract in (
        "ListenStream=/run/devfleet-vault-broker.sock",
        "SocketUser=root",
        "SocketGroup=devfleet-control",
        "SocketMode=0660",
        "Accept=yes",
        "MaxConnections=1",
    ):
        assert contract in socket_unit
    for contract in (
        "User=devfleet-backup",
        "Group=devfleet-backup",
        "ExecStart=/usr/local/bin/devfleet-vault-broker",
        "StandardInput=socket",
        "StandardOutput=socket",
        "NoNewPrivileges=true",
        "PrivateTmp=true",
        "ProtectSystem=strict",
        "ProtectHome=read-only",
        "ReadWritePaths=/run/lock -/var/lib/devfleet/backup-status __WORKSPACES__ __QUARANTINE__",
        "RuntimeMaxSec=3660",
        "TimeoutStopSec=10",
    ):
        assert contract in service_unit
    assert "SupplementaryGroups=devrunner" in control_unit
    assert "devfleet-backup" not in control_unit
    assert "/run/lock" not in next(
        line for line in control_unit.splitlines() if line.startswith("ReadWritePaths=")
    )


def test_broker_protocol_is_fixed_bounded_and_peer_authenticated():
    broker = read("linux/devfleet-vault-broker")
    client = read("linux/devfleet-vault-request")

    for contract in (
        "SO_PEERCRED",
        "devfleet-control",
        "MAX_REQUEST_BYTES",
        "MAX_RESPONSE_BYTES",
        '"backup"',
        '"restore-copy"',
        "/usr/local/bin/devfleet-backup",
        "/usr/local/bin/devfleet-restore-project",
    ):
        assert contract in broker
    assert "shell=True" not in broker
    assert "AF_UNIX" in client
    assert "/run/devfleet-vault-broker.sock" in client
    assert "MAX_RESPONSE_BYTES" in client
    assert "--canonical" not in client
    assert "restore-canonical" not in client
    assert "restore-canonical" not in broker


def test_bootstrap_installs_and_enables_only_the_bounded_broker_surface():
    bootstrap = read("linux/bootstrap-compute.sh")

    assert "devfleet-user-repair devfleet-docker-mode-report devfleet-vault-request" in bootstrap
    assert 'install -o root -g devfleet-backup -m 0750 "$PAYLOAD/linux/devfleet-vau