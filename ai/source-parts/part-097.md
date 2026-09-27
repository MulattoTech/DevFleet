# DevFleet source part 097

Full-source UTF-8 byte interval [4464000, 4510500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: bb572f74b29731e7c109d91b25dde91df452c57395640b18fac1d19589bc4e71

<!-- BEGIN SOURCE SLICE -->
3"},
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
    mount_probe = "Invoke-MultipassConfigurationProbe $mp @('get','local.privileged-mounts')"
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
JS = (ROOT / "app/static/app.js").read_text(encoding=