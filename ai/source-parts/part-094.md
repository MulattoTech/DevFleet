# DevFleet source part 094

Full-source UTF-8 byte interval [4324500, 4371000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8e9c2f95a1f7254fe35b04b67c80367a10665673e7ba7cabf371884da463f1be

<!-- BEGIN SOURCE SLICE -->
 (row["root"], row["path"]))
    assert flat != canonical


def test_packaged_wrapper_preserves_diagnostic_candidate_status(monkeypatch, tmp_path: Path):
    payload = {"status": "PASS_WITH_BLOCKER", "blockerCode": "HISTORICAL_CANDIDATE_REBUILD_REQUIRED", "releaseEligible": False}
    monkeypatch.setattr(_AI_MODULE.subprocess, "run", lambda *args, **kwargs: SimpleNamespace(returncode=0, stdout=json.dumps(payload), stderr=""))
    result = _AI_MODULE._run_candidate_validator([sys.executable, "candidate-validator"], tmp_path, "diagnostic")
    assert result == payload


@pytest.mark.parametrize("output", ["not-json", "{}\n{}"])
def test_packaged_wrapper_rejects_malformed_or_multiple_candidate_json(monkeypatch, tmp_path: Path, output: str):
    monkeypatch.setattr(_AI_MODULE.subprocess, "run", lambda *args, **kwargs: SimpleNamespace(returncode=0, stdout=output, stderr=""))
    with pytest.raises(ValueError, match="structured JSON|malformed JSON|non-object"):
        _AI_MODULE._run_candidate_validator([sys.executable, "candidate-validator"], tmp_path, "diagnostic")


def test_packaged_wrapper_rejects_diagnostic_plain_pass_downgrade(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(_AI_MODULE.subprocess, "run", lambda *args, **kwargs: SimpleNamespace(returncode=0, stdout=json.dumps({"status": "PASS"}), stderr=""))
    with pytest.raises(ValueError, match="downgraded or contradictory"):
        _AI_MODULE._run_candidate_validator([sys.executable, "candidate-validator"], tmp_path, "diagnostic")


def test_packaged_wrapper_rejects_release_blocker(monkeypatch, tmp_path: Path):
    payload = {"status": "PASS_WITH_BLOCKER", "blockerCode": "PROOF_PENDING", "releaseEligible": False}
    monkeypatch.setattr(_AI_MODULE.subprocess, "run", lambda *args, **kwargs: SimpleNamespace(returncode=0, stdout=json.dumps(payload), stderr=""))
    with pytest.raises(ValueError, match="contains a blocker"):
        _AI_MODULE._run_candidate_validator([sys.executable, "candidate-validator"], tmp_path, "release")

```


## FILE: source/tests/test_auth_multiprocess.py

SHA256: 5b678aec7d5e3adc3205a598f950a73b3102166c0495c9e52bb8076bb031bcaa | Bytes: 845 | Git mode: 100644

```
import json
import multiprocessing

from devfleet import auth


def _issue_session_in_process(queue):
    from devfleet.auth import issue_session
    queue.put(issue_session("test")[0])


def test_sessions_json_is_safe_for_separate_worker_processes():
    path = auth._session_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("{}\n", encoding="utf-8")
    ctx = multiprocessing.get_context("spawn")
    queue = ctx.Queue()
    workers = [ctx.Process(target=_issue_session_in_process, args=(queue,)) for _ in range(4)]
    for worker in workers:
        worker.start()
    for worker in workers:
        worker.join(20)
    assert all(worker.exitcode == 0 for worker in workers)
    records = json.loads(path.read_text(encoding="utf-8"))
    assert len(records) == 4
    for worker in workers:
        worker.close()

```


## FILE: source/tests/test_backup_exit_status.py

SHA256: 3f7fa30cf012e8451beba327ca3fb255a4b30152c72d30aeb15ea844587b3ba7 | Bytes: 1900 | Git mode: 100644

```
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

```


## FILE: source/tests/test_backup_metadata_acl.py

SHA256: eff0c7cc0f43496e74c46f1be348b76a8bedd536389e5f30b6d2521069964e78 | Bytes: 7834 | Git mode: 100644

```
"""Real Linux ACL regression: atomic metadata remains readable only by its backup identity."""
from __future__ import annotations
import errno
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
from types import SimpleNamespace

import pytest
from devfleet import core, metadata_io

BACKUP_UID = 60002
OTHER_UID = 60003
ACL_ACCESS = 'system.posix_acl_access'
ACL_DEFAULT = 'system.posix_acl_default'


def pack_acl(entries):
    return struct.pack('<I', 2) + b''.join(struct.pack('<HHI', *entry) for entry in entries)


def entries(raw):
    assert struct.unpack('<I', raw[:4]) == (2,)
    return list(struct.iter_unpack('<HHI', raw[4:]))


@pytest.fixture
def acl_workspace(monkeypatch):
    if sys.platform != 'linux' or not hasattr(os, 'geteuid') or os.geteuid() != 0:
        pytest.skip('Real different-UID ACL checks require Linux root in the isolated test environment')
    import pwd
    real_lookup = pwd.getpwnam
    monkeypatch.setattr(pwd, 'getpwnam', lambda name: SimpleNamespace(pw_uid=BACKUP_UID)
                        if name == 'devfleet-backup' else real_lookup(name))
    with tempfile.TemporaryDirectory(prefix='devfleet-acl-test-') as root:
        parent = Path(root)
        parent.chmod(0o755)
        workspace = parent / 'demo'
        workspace.mkdir()
        policy = pack_acl([(1,7,0xFFFFFFFF),(2,7,BACKUP_UID),(2,7,OTHER_UID),
                           (4,0,0xFFFFFFFF),(16,7,0xFFFFFFFF),(32,0,0xFFFFFFFF)])
        try:
            os.setxattr(workspace, ACL_ACCESS, policy)
            os.setxattr(workspace, ACL_DEFAULT, policy)
        except OSError as exc:
            if exc.errno in (errno.ENOTSUP, errno.EOPNOTSUPP):
                pytest.skip('Test filesystem does not support POSIX ACLs')
            raise
        yield workspace


def access_as(path, *, uid=BACKUP_UID, write=False):
    code = ('from pathlib import Path; import sys; '
            "p=Path(sys.argv[1]); " +
            ("f=p.open('ab'); f.close()" if write else 'p.read_bytes()'))
    result = subprocess.run([sys.executable, '-I', '-c', code, str(path)],
                            user=uid, group=uid, extra_groups=[], capture_output=True,
                            timeout=10, text=True)
    return result.returncode == 0


def assert_backup_only(path):
    assert access_as(path), 'The configured backup identity cannot read newly published metadata'
    assert not access_as(path, write=True), 'The backup identity must not write authoritative metadata'
    assert not access_as(path, uid=OTHER_UID), 'Enabling backup read must not unmask another inherited principal'
    assert path.stat().st_mode & 0o007 == 0, 'Metadata must not become world-accessible'


def test_metadata_create_and_replace_keep_backup_read_access(acl_workspace):
    p = acl_workspace
    binding = metadata_io.write_project_metadata(p, {'test': 'initial'}, create=True)
    assert_backup_only(p / '.devfleet/project.json')
    binding = metadata_io.write_project_metadata(p, {'test': 'replacement'}, expected=binding)
    assert_backup_only(p / '.devfleet/project.json')
    assert metadata_io.read_project_metadata(p).value == {'test': 'replacement'}


@pytest.mark.parametrize('writer,value', [(core.atomic_text, 'lease'), (core.atomic_bytes, b'lease'),
                                         (core.atomic_json, {'lease': 'closed'})])
def test_atomic_workspace_writes_keep_backup_read_access(acl_workspace, writer, value):
    path = acl_workspace / 'ownership-lease.json'
    writer(path, value)
    assert_backup_only(path)
    writer(path, value)
    assert_backup_only(path)


def test_paths_without_backup_acl_remain_private(tmp_path):
    path = tmp_path / 'private.json'
    core.atomic_json(path, {'private': True})
    if os.name == 'posix':
        assert path.stat().st_mode & 0o077 == 0


def test_metadata_replacement_does_not_reintroduce_a_removed_acl(acl_workspace):
    p = acl_workspace
    binding = metadata_io.write_project_metadata(p, {'test': 'initial'}, create=True)
    directory = p / '.devfleet'
    os.removexattr(directory, ACL_DEFAULT)
    binding = metadata_io.write_project_metadata(p, {'test': 'replacement'}, expected=binding)
    assert not access_as(directory / 'project.json')
    assert (directory / 'project.json').stat().st_mode & 0o077 == 0


def test_default_acl_mask_denial_is_not_overridden(acl_workspace):
    p = acl_workspace
    acl = entries(os.getxattr(p, ACL_DEFAULT))
    os.setxattr(p, ACL_DEFAULT, pack_acl([(t, 0 if t == 16 else v, u) for t,v,u in acl]))
    target = p / 'denied-by-parent.json'
    core.atomic_json(target, {'private': True})
    assert not access_as(target), 'An explicitly masked parent backup grant is not permission to read'
    assert target.stat().st_mode & 0o077 == 0


def test_failed_acl_application_does_not_replace_committed_metadata(acl_workspace, monkeypatch):
    p = acl_workspace
    binding = metadata_io.write_project_metadata(p, {'original': True}, create=True)
    previous = (p / '.devfleet/project.json').read_bytes()
    def deny(*args, **kwargs):
        raise OSError(errno.EACCES, 'synthetic ACL write refusal')
    monkeypatch.setattr(metadata_io.os, 'setxattr', deny)
    with pytest.raises(OSError):
        metadata_io.write_project_metadata(p, {'replacement': True}, expected=binding)
    assert (p / '.devfleet/project.json').read_bytes() == previous
    assert not list((p / '.devfleet').glob('.project.json.*.tmp'))


@pytest.mark.parametrize("publisher_default, expected_read, expected_write", [(7, True, True), (5, True, False), (0, False, False)])
def test_inherited_publisher_acl_survives_restore_owner_change(acl_workspace, publisher_default, expected_read, expected_write):
    """Restoration by an unprivileged backup UID cannot retain source ownership.

    Exercise the actual ACL publication, then the ownership transition on this
    disposable inode tree. This is not a restic/network certification test.
    """
    publisher_uid = 60004
    p = acl_workspace
    for attr in (ACL_ACCESS, ACL_DEFAULT):
        policy = entries(os.getxattr(p, attr))
        policy.insert(3, (2, 7 if attr == ACL_ACCESS else publisher_default, publisher_uid))
        policy.sort(key=lambda row: (row[0], row[2]))
        os.setxattr(p, attr, pack_acl(policy))
    code = (
        'import sys, pwd; from pathlib import Path; from types import SimpleNamespace; '
        f'sys.path.insert(0, {str(Path(metadata_io.__file__).parents[1])!r}); '
        'real = pwd.getpwnam; '
        f'pwd.getpwnam = lambda n: SimpleNamespace(pw_uid={BACKUP_UID}) '
        'if n == "devfleet-backup" else real(n); '
        'from devfleet.metadata_io import write_project_metadata; '
        'write_project_metadata(Path(sys.argv[1]), {"publisher": True}, create=True)'
    )
    created = subprocess.run([sys.executable, '-I', '-c', code, str(p)],
                             user=publisher_uid, group=publisher_uid, extra_groups=[],
                             capture_output=True, text=True, timeout=10)
    assert created.returncode == 0, created.stderr
    metadata = p / '.devfleet/project.json'
    assert access_as(metadata, uid=publisher_uid)
    assert_backup_only(metadata)
    # Restore returns inode ownership to the restoring identity. The original
    # publisher's *named* ACL must retain its formerly effective owner rights.
    os.chown(metadata, BACKUP_UID, BACKUP_UID)
    os.chown(metadata.parent, BACKUP_UID, BACKUP_UID)
    assert access_as(metadata, uid=publisher_uid) == expected_read, 'Restore changed the inherited publisher read policy'
    assert access_as(metadata, uid=publisher_uid, write=True) == expected_write, 'Restore changed the inherited publisher write policy'
    assert not access_as(metadata, uid=OTHER_UID), 'Restore must not revive an unrelated principal'

```


## FILE: source/tests/test_bootstrap_input_safety.py

SHA256: 6416e46165662fcc0e31c37f78c79e89d89991b71fbe6dd8c53786d84dda7be2 | Bytes: 4713 | Git mode: 100644

```
from pathlib import Path
import json
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]


def python_heredocs(name):
    lines = (ROOT / "linux" / name).read_text(encoding="utf-8").splitlines()
    blocks = []
    for index, line in enumerate(lines):
        if "<<'PY'" in line:
            end = lines.index("PY", index + 1)
            blocks.append((index + 2, "\n".join(lines[index + 1 : end]) + "\n"))
    assert blocks, f"No embedded Python found in {name}"
    return blocks


@pytest.mark.parametrize("name", ["bootstrap-compute.sh", "bootstrap-vault.sh"])
def test_bootstrap_embedded_python_compiles(name):
    # bash -n cannot parse embedded Python; compile the exact production bodies.
    for line, body in python_heredocs(name):
        compile(body, f"{name}:heredoc-at-line-{line}", "exec")


@pytest.mark.parametrize("forbidden", [None, "\x00", "\r", "\n"])
def test_compute_secret_writer_executes_atomically_and_rejects_controls(tmp_path, monkeypatch, forbidden):
    bodies = [body for _, body in python_heredocs("bootstrap-compute.sh") if "target.replace('/etc/devfleet/secrets.env')" in body]
    assert len(bodies) == 1
    body = compile(bodies[0], "bootstrap-compute.sh:secret-writer", "exec")
    source, temporary, destination = (tmp_path / name for name in ("input.json", "temporary.env", "secrets.env"))
    password = 'fixture-\\$`"' + (forbidden or "")
    source.write_text(json.dumps({"AdminUser": "fixture-user", "AdminPassword": password, "ApiToken": "fixture-token"}), encoding="utf-8")
    temporary.touch()
    destination.write_text("original fixture\n", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", ["-", str(temporary), str(source)])
    original_replace = Path.replace

    def redirected_replace(path, target):
        assert path == temporary and target == "/etc/devfleet/secrets.env"
        return original_replace(path, destination)

    monkeypatch.setattr(Path, "replace", redirected_replace)
    if forbidden:
        with pytest.raises(SystemExit, match="forbidden control character"):
            exec(body, {})
        assert destination.read_text(encoding="utf-8") == "original fixture\n"
        assert temporary.read_bytes() == b""
    else:
        exec(body, {})
        encoded = password.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
        expected = 'DEVFLEET_ADMIN_USER="fixture-user"\nDEVFLEET_ADMIN_PASSWORD="' + encoded + '"\nDEVFLEET_API_TOKEN="fixture-token"\n'
        assert destination.read_bytes() == expected.encode("utf-8")
        assert not temporary.exists()
    assert source.exists()


def test_compute_bootstrap_validates_numeric_and_secret_boundaries_before_templates():
    source = (ROOT / "linux" / "bootstrap-compute.sh").read_text(encoding="utf-8")
    assert "PORT =~ ^[0-9]+$" in source
    assert "BACKUP_INTERVAL =~ ^[0-9]+$" in source
    assert "value != *$'\\r'*" in source
    assert "value != *$'\\n'*" in source
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
    (project / "compose.ya