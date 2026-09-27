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
