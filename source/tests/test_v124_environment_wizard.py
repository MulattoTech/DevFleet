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
