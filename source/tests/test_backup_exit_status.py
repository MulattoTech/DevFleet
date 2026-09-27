"""Execute the shipping Bash wrapper with only the external restic command substituted."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.skipif(sys.platform != 'linux' or not shutil.which('bash'), reason='Shipping backup wrapper runs on Linux')
@pytest.mark.parametrize('restic_exit', [0, 1, 3, 10, 11, 12, 75, 124])
def test_backup_preserves_restic_failure_and_never_promotes_incomplete_snapshot(tmp_path, restic_exit):
    status = tmp_path / 'status'; status.mkdir()
    cache = status / 'cache'; cache.mkdir()
    config = tmp_path / 'restic.env'
    config.write_text(f'RESTIC_CACHE_DIR="{cache}"\n')
    tools = tmp_path / 'bin'; tools.mkdir()
    restic = tools / 'restic'
    restic.write_text('#!/bin/sh\nexit '+str(restic_exit)+'\n'); restic.chmod(0o755)
    # Relocate fixed paths into this disposable test directory; keep control flow intact.
    text = (ROOT / 'linux/devfleet-backup').read_text()
    for old, new in [('/etc/devfleet/restic.env', config),
                     ('/var/lib/devfleet/backup-status', status),
                     ('/run/lock/devfleet-vault-operation.lock', tmp_path / 'operation.lock')]:
        text = text.replace(old, str(new))
    wrapper = tmp_path / 'backup'; wrapper.write_text(text)
    result = subprocess.run(['bash', str(wrapper)], env={**os.environ, 'PATH':str(tools)+os.pathsep+os.environ['PATH']},
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == restic_exit, 'The backup wrapper must retain the actual restic failure code'
    telemetry = json.loads((status / 'latest.json').read_text())
    assert telemetry['vault_upload_status'] == ('verified' if restic_exit == 0 else 'failed')
    assert telemetry['durability_level'] == ('vault' if restic_exit == 0 else 'none')
