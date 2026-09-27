# DevFleet source part 101

Full-source UTF-8 byte interval [4650000, 4696500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 226bd1e645a69861e5241351e5fc4ed7f2cfcef4eac9522986ea1196bfa43d16

<!-- BEGIN SOURCE SLICE -->
e, **kwargs)


def _signed_in():
    from fastapi.testclient import TestClient

    client = TestClient(main.app)
    login = client.get('/login')
    login_csrf = re.search(r'name="csrf_token" value="([^"]+)"', login.text).group(1)
    assert _no_redirect(client, 'post', '/login', data={
        'username': 'test', 'password': 'test-password', 'next': '/', 'csrf_token': login_csrf,
    }).status_code == 303
    index = client.get('/')
    return client, re.search(r'name="csrf_token" value="([^"]+)"', index.text).group(1)


def test_vm_readiness_requires_running_and_all_connection_proofs():
    meta = {
        'slug': 'demo', 'runtime_isolation': 'vm', 'runtime_provider': 'multipass-host-agent',
        'lifecycle_status': 'stopped', 'runtime_address': '172.30.9.35', 'ssh_alias': 'devfleet-project-demo',
        'ssh_host_key_pinned': True, 'ssh_authenticated': True, 'ssh_validation_passed': True,
        'workspace_provisioned': True,
    }
    stopped = workspace_readiness('demo', meta)
    assert stopped['ready'] is False and 'stopped' in stopped['reason']
    meta['lifecycle_status'] = 'running'
    running = workspace_readiness('demo', meta)
    assert running['ready'] is True and running['status'] == 'ready'
    meta['ssh_authenticated'] = False
    assert workspace_readiness('demo', meta)['ready'] is False


def test_project_action_requires_exact_origin_port_and_uses_lifecycle_idempotency(tmp_path, monkeypatch):
    monkeypatch.setattr(main, 'SETTINGS', replace(main.SETTINGS, workspaces=tmp_path))
    project = tmp_path / 'demo'
    (project / '.devfleet').mkdir(parents=True)
    (project / '.devfleet' / 'project.json').write_text(json.dumps({
        'schema_version': 3, 'managed_by': 'devfleet', 'project_id': '12345678-1234-1234-1234-123456789abc',
        'slug': 'demo', 'identity': 'demo', 'runtime_provider': 'multipass-host-agent',
        'runtime_id': 'devfleet-project-demo', 'host_id': 'devfleet-primary',
    }), encoding='utf-8')
    client, csrf = _signed_in()
    calls = []
    monkeypatch.setattr(main, 'submit_operation', lambda *args, **kwargs: calls.append(kwargs) or 'start-test-op')
    response = _no_redirect(client, 'post', '/projects/demo/start', headers={
        'Host': 'testserver:8787', 'Origin': 'http://testserver:80', 'Sec-Fetch-Site': 'same-origin',
    }, data={'csrf_token': csrf})
    assert response.status_code == 403
    response = _no_redirect(client, 'post', '/projects/demo/start', headers={
        'Host': 'testserver:8787', 'Origin': 'http://testserver:8787', 'Accept': 'application/json',
    }, data={'csrf_token': csrf})
    assert response.status_code == 202
    assert calls[-1]['idempotency_key'] == 'project-action:demo:start'


def test_migrated_vm_host_identity_is_local_without_disabling_failover_guard(tmp_path, monkeypatch):
    project = tmp_path / 'demo'
    (project / '.devfleet').mkdir(parents=True)
    (project / '.devfleet' / 'project.json').write_text(json.dumps({
        'schema_version': 3, 'managed_by': 'devfleet', 'project_id': '12345678-1234-1234-1234-123456789abc',
        'slug': 'demo', 'identity': 'demo', 'runtime_provider': 'multipass-host-agent',
        'runtime_id': 'devfleet-project-demo', 'host_id': 'MULATTOTECHBOX',
    }), encoding='utf-8')
    monkeypatch.setattr(main, 'SETTINGS', replace(
        main.SETTINGS, workspaces=tmp_path, node_name='devfleet-primary',
        expected_host_name='MULATTOTECHBOX',
    ))
    monkeypatch.setattr(main, 'safe_child', lambda _root, _slug: project)
    monkeypatch.setattr(main, 'peer_status', lambda: (_ for _ in ()).throw(
        AssertionError('local migrated VM must not require peer reachability'),
    ))
    main.require_safe_start('demo', False)


def test_spa_action_delegation_and_resource_contracts():
    root = Path(__file__).resolve().parents[1]
    js = (root / 'app/static/app.js').read_text(encoding='utf-8')
    html = (root / 'app/templates/index.html').read_text(encoding='utf-8')
    assert 'window.__devfleetProjectActionsBound' in js
    assert 'event.preventDefault();' in js and "'Idempotency-Key'" in js
    assert 'initializeView();' in js and 'nodeFilter?.addEventListener' in js
    assert 'resource_allocation(p)' in html and 'Not applicable — VM isolation' in html
    assert 'Workspace readiness has not been verified' in html


def test_vscode_helper_is_scoped_atomic_and_malformed_safe():
    root = Path(__file__).resolve().parents[1]
    helper = (root / 'windows/DevFleet-VSCode.ps1').read_text(encoding='utf-8')
    agent = (root / 'windows/DevFleet-HostAgent.ps1').read_text(encoding='utf-8')
    installer = (root / 'windows/Install-DevFleet-HostAgent.ps1').read_text(encoding='utf-8')
    assert 'remote.SSH.remotePlatform' in helper
    assert 'Copy($Path, $backup, $false)' in helper
    assert 'Move-Item -LiteralPath $tmp -Destination $Path -Force' in helper
    assert 'ConvertFrom-DevFleetJsonc' in helper and 'malformed user settings' in helper.lower() and 'replacement is written' in helper.lower()
    assert 'Sync-DevFleetVsCodeRemotePlatform' in agent and 'VsCodeSettingsPaths' in installer
    assert '[switch]$SkipFirewall' in installer and 'if (-not $SkipFirewall)' in installer

```


## FILE: source/tests/test_v128_container_workspace.py

SHA256: f947532feee6305c049ffa245545e60dc389ae6507b44552914471ebabbf4ae9 | Bytes: 4527 | Git mode: 100644

```
import json
from dataclasses import replace
from pathlib import Path

import devfleet.projects as projects
from devfleet.core import SETTINGS


def _project(tmp_path: Path, slug: str, metadata: dict) -> Path:
    project = tmp_path / slug
    (project / '.devfleet').mkdir(parents=True)
    persisted = {
        'schema_version': 3,
        'managed_by': 'devfleet',
        'project_id': '12345678-1234-1234-1234-123456789abc',
        'slug': slug,
        'identity': slug,
        'runtime_provider': 'docker-compose',
        'runtime_id': 'df_' + slug.replace('-', '_'),
        'host_id': 'devfleet-primary',
        **metadata,
    }
    (project / '.devfleet' / 'project.json').write_text(json.dumps(persisted), encoding='utf-8')
    return project


def test_container_workspace_opens_when_application_containers_are_stopped(monkeypatch, tmp_path):
    _project(tmp_path, 'container-stopped', {
        'slug': 'container-stopped',
        'runtime_isolation': 'container',
        'runtime_type': 'container',
        'runtime_provider': 'docker-compose',
        'lifecycle_status': 'stopped',
        'runtime_status': 'stopped',
        'workspace_host': 'devfleet-primary',
        'ssh_alias': 'devfleet-primary',
        'workspace_path': '/home/devrunner/workspaces/container-stopped',
        'workspace_provisioned': True,
        'workspace_accessible': True,
    })
    monkeypatch.setattr(projects, 'SETTINGS', replace(SETTINGS, workspaces=tmp_path, node_name='devfleet-primary'))
    monkeypatch.setattr(projects, 'running', lambda *_: False)

    result = projects.open_workspace('container-stopped')

    assert result['ok'] is True
    assert result['readiness']['ready'] is True
    assert result['readiness']['application_running'] is False
    assert result['ssh_alias'] == 'devfleet-primary'
    assert 'ssh-remote+devfleet-primary' in result['launcher_uri']


def test_container_workspace_blocks_when_primary_workspace_is_unavailable(monkeypatch, tmp_path):
    _project(tmp_path, 'container-unavailable', {
        'slug': 'container-unavailable',
        'runtime_isolation': 'container',
        'runtime_type': 'container',
        'lifecycle_status': 'stopped',
        'workspace_accessible': False,
    })
    monkeypatch.setattr(projects, 'SETTINGS', replace(SETTINGS, workspaces=tmp_path, node_name='devfleet-primary'))

    result = projects.open_workspace('container-unavailable')

    assert result['ok'] is False
    assert 'not accessible' in result['error']


def test_starting_dedicated_vm_cannot_open(monkeypatch, tmp_path):
    _project(tmp_path, 'vm-starting', {
        'slug': 'vm-starting',
        'runtime_isolation': 'vm',
        'runtime_type': 'vm',
        'runtime_provider': 'multipass-host-agent',
        'lifecycle_status': 'starting',
        'runtime_id': 'devfleet-project-vm-starting',
        'ssh_alias': 'devfleet-project-vm-starting',
    })
    monkeypatch.setattr(projects, 'SETTINGS', replace(SETTINGS, workspaces=tmp_path))
    monkeypatch.setattr(projects.VmRuntimeOperations, 'inspect', staticmethod(lambda *_: {'info': {'state': 'Starting'}}))
    monkeypatch.setattr(projects.VmRuntimeOperations, 'refresh', staticmethod(lambda *_: (_ for _ in ()).throw(AssertionError('refresh must wait for running state'))))

    result = projects.open_workspace('vm-starting')

    assert result['ok'] is False
    assert result['state'] == 'starting'
    assert 'starting' in result['error'].lower()


def test_running_ssh_ready_dedicated_vm_opens(monkeypatch, tmp_path):
    _project(tmp_path, 'vm-ready', {
        'slug': 'vm-ready',
        'runtime_isolation': 'vm',
        'runtime_type': 'vm',
        'runtime_provider': 'multipass-host-agent',
        'lifecycle_status': 'running',
        'runtime_id': 'devfleet-project-vm-ready',
        'runtime_address': '172.30.9.35',
        'ssh_alias': 'devfleet-project-vm-ready',
        'ssh_host_key_pinned': True,
        'ssh_authenticated': True,
        'ssh_validation_passed': True,
        'workspace_provisioned': True,
    })
    monkeypatch.setattr(projects, 'SETTINGS', replace(SETTINGS, workspaces=tmp_path))
    monkeypatch.setattr(projects.VmRuntimeOperations, 'inspect', staticmethod(lambda *_: {'info': {'state': 'Running'}}))
    monkeypatch.setattr(projects, 'running', lambda *_: True)

    result = projects.open_workspace('vm-ready')

    assert result['ok'] is True
    assert result['readiness']['ready'] is True
    assert result['ssh_alias'] == 'devfleet-project-vm-ready'

```


## FILE: source/tests/test_vault_metadata_identity_integration.py

SHA256: f5340252c6b2410b726c4529c51ecef9ec9aab60b41c5ca3cef989573668b9d3 | Bytes: 3801 | Git mode: 100644

```
import importlib.util
from importlib.machinery import SourceFileLoader
import pytest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _broker():
    pytest.importorskip("pwd", reason="Vault broker is POSIX-only")
    spec = importlib.util.spec_from_loader("vault_broker", SourceFileLoader("vault_broker", str(ROOT / "linux" / "devfleet-vault-broker")))
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_broker_delegates_descriptor_safe_identity_to_installed_helper(monkeypatch, tmp_path):
    broker = _broker()
    calls = []

    class Result:
        returncode = 0

    monkeypatch.setattr(broker.subprocess, "run", lambda command, **kwargs: calls.append((command, kwargs)) or Result())
    assert broker._restored_identity_matches(tmp_path, "demo", "12345678-1234-1234-1234-123456789012")
    command, kwargs = calls[-1]
    assert command == ["python3", "-I", "/opt/devfleet/devfleet/metadata_io.py", "--identity", str(tmp_path), "demo", "12345678-1234-1234-1234-123456789012"]
    assert kwargs["stdin"] is broker.subprocess.DEVNULL
    assert kwargs["stdout"] is broker.subprocess.DEVNULL
    assert kwargs["stderr"] is broker.subprocess.DEVNULL


def test_broker_binds_transfer_identity_arguments(monkeypatch, tmp_path):
    broker = _broker()
    seen = []
    monkeypatch.setattr(broker.subprocess, "run", lambda command, **kwargs: seen.append(command) or type("R", (), {"returncode": 0})())
    assert broker._restored_identity_matches(tmp_path, "demo", "12345678-1234-1234-1234-123456789012", "12345678-1234-1234-1234-123456789013", "failover")
    assert seen[0][-2:] == ["12345678-1234-1234-1234-123456789013", "failover"]


def test_broker_rejects_standalone_canonical_action(monkeypatch):
    broker = _broker()
    with pytest.raises(broker.ProtocolError):
        broker._parse_request({"action": "restore-canonical", "project": "demo", "project_id": "12345678-1234-1234-1234-123456789012"})
    assert "restore-canonical" not in (ROOT / "linux" / "devfleet-vault-request").read_text(encoding="utf-8")


def test_broker_attempts_quarantine_on_invalid_recovered_identity(monkeypatch, tmp_path):
    broker = _broker()
    broker.WORKSPACES = tmp_path
    # Supply the external configuration precondition; never read real credentials.
    monkeypatch.setattr(broker.os, "access", lambda path, mode: path == "/etc/devfleet/restic.env")
    target = tmp_path / "demo-recovered-20260916-123456-deadbeef"
    target.mkdir()
    monkeypatch.setattr(broker, "_run_child", lambda *_args, **_kwargs: type("R", (), {"returncode": 0, "stdout": str(target) + "\n"})())
    monkeypatch.setattr(broker, "_restored_identity_matches", lambda *_args: False)
    quarantined = []
    monkeypatch.setattr(broker, "_quarantine_invalid_copy", lambda path, project: quarantined.append((path, project)) or True)
    result = broker._run_fixed_operation("restore-copy", "demo", "12345678-1234-1234-1234-123456789012")
    assert result["ok"] is False and quarantined == [(target, "demo")]


def test_restore_shell_uses_metadata_io_identity_cli():
    script = (ROOT / "linux" / "devfleet-restore-project").read_text(encoding="utf-8")
    assert "python3 -I /opt/devfleet/devfleet/metadata_io.py --identity" in script
    assert "jq -e --arg slug" not in script


def test_restore_shell_quarantines_unmarked_recovered_target_after_move():
    script = (ROOT / "linux" / "devfleet-restore-project").read_text(encoding="utf-8")
    assert 'if [[ "$mode" != --canonical ]] && ! workspace_identity_matches "$target"' in script
    assert 'vault-recovery-invalid-$stamp-$project' in script
    assert 'Recovered workspace identity failed; the unmarked copy was quarantined.' in script

```


## FILE: source/tests/test_verify_package_watchdog.py

SHA256: 51cb998ef256cd58f3c6f63c63d23aa330566f0f4030c7f7237eb962967c3d4c | Bytes: 974 | Git mode: 100644

```
import sys
from pathlib import Path

import pytest


TOOLS = Path(__file__).parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
from verify_package import run_bounded  # noqa: E402


def test_verify_package_watchdog_allows_normal_success():
    result = run_bounded([sys.executable, "-c", "print('ok')"], timeout=5, label="normal test")
    assert result.returncode == 0
    assert result.stdout.strip() == "ok"


def test_verify_package_watchdog_reports_timeout():
    with pytest.raises(RuntimeError, match="timeout"):
        run_bounded([sys.executable, "-c", "import time; time.sleep(30)"], timeout=0.2, label="sleeping hook")


def test_verify_package_watchdog_reports_output_flood():
    with pytest.raises(RuntimeError, match="output limit"):
        run_bounded(
            [sys.executable, "-c", "import sys; sys.stdout.write('x' * 1000000); sys.stdout.flush()"],
            timeout=5,
            output_limit=4096,
            label="flooding hook",
        )

```


## FILE: source/tests/test_worktrees_and_v1_restore.py

SHA256: 7cf54e4291b6c4df1063afb2ab5113bf35b78498c8f035ac1633d3c41d7c3b2f | Bytes: 3037 | Git mode: 100644

```
import json,shutil,subprocess,uuid
from pathlib import Path
from devfleet import projects, workspace_archives
from devfleet.core import SETTINGS

ROOT=Path(__file__).resolve().parents[1]

def git(cwd,*args):
 return subprocess.run(['git',*args],cwd=cwd,text=True,capture_output=True,check=True)

def test_git_worktree_project_creation(monkeypatch):
 source=SETTINGS.workspaces/f'source-{uuid.uuid4().hex[:8]}'
 dest_slug=f'worktree-{uuid.uuid4().hex[:8]}'
 dest=SETTINGS.workspaces/dest_slug
 source.mkdir(parents=True)
 try:
  git(source,'init');git(source,'config','user.name','DevFleet Test');git(source,'config','user.email','devfleet@example.invalid')
  (source/'seed.txt').write_text('seed');git(source,'add','.');git(source,'commit','-m','seed');git(source,'branch','feature')
  monkeypatch.setattr(projects,'TEMPLATE_ROOT',ROOT/'templates')
  meta=projects.create_project(dest_slug,template='generic',worktree_source=source.name,worktree_branch='feature',use_ollama=False)
  assert meta['worktree'] and (dest/'.git').is_file() and json.loads((dest/'.devfleet/project.json').read_text())['identity']==dest_slug
 finally:
  if dest.exists():subprocess.run(['git','worktree','remove','--force',str(dest)],cwd=source,check=False)
  shutil.rmtree(source,ignore_errors=True);shutil.rmtree(dest,ignore_errors=True)

def test_v1_project_without_schema2_metadata_remains_discoverable(tmp_path):
 project=tmp_path/'legacy-project';project.mkdir()
 meta=projects.load_meta(project)
 assert meta['slug']=='legacy-project' and meta['template']=='existing'
 assert meta['runtime_provider']=='docker-compose' and meta['resource_profile']=='standard'
 assert meta['resource_limits']['memory_gb']==4.0 and meta['resource_limits']['cpus']==2.0

def test_canonical_vault_restore_quarantines_existing_v1_copy():
 text=(ROOT/'linux/devfleet-restore-project').read_text()
 assert 'transfer-replaced-' in text and 'mv -T --no-clobber -- "$target" "$quarantine"' in text
 assert 'Canonical restore could not quarantine the existing workspace.' in text

def test_workspace_restore_failure_restores_previous_canonical(tmp_path,monkeypatch):
 slug='rollback-fixture'
 source=tmp_path/slug;source.mkdir();(source/'old.txt').write_text('old');(source/'.devfleet').mkdir();(source/'.devfleet/project.json').write_text(json.dumps({'slug':slug,'schema_version':2}))
 archive=tmp_path/'backup.tar.gz'
 workspace_archives.create_workspace_archive(source,slug,archive)
 (source/'old.txt').write_text('original-must-survive')
 original=workspace_archives.inspect_workspace
 calls={'count':0}
 def fail_after_promotion(path):
  calls['count']+=1
  if calls['count'] == 1:
   raise RuntimeError('injected post-promotion failure')
  return original(path)
 monkeypatch.setattr(workspace_archives,'inspect_workspace',fail_after_promotion)
 try:
  workspace_archives.restore_workspace_archive(archive,source,slug)
 except RuntimeError:
  pass
 else:
  raise AssertionError('fault injection did not fail')
 assert (source/'old.txt').read_text() == 'original-must-survive'

```


## FILE: source/tools/Build-InstallerSourceZip.ps1

SHA256: 8b654e01e2be6f4faa42628be4168e9c349348a8dac29fa8cbf5d24bf86badcf | Bytes: 2625 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$InstallerRoot,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$sourceRootResolved = (Resolve-Path -LiteralPath $SourceRoot).Path
$sourceCandidate = Join-Path $sourceRootResolved 'source'
$source = if (Test-Path -LiteralPath (Join-Path $sourceCandidate 'VERSION')) { (Resolve-Path -LiteralPath $sourceCandidate).Path } else { $sourceRootResolved }
$installer = (Resolve-Path -LiteralPath $InstallerRoot).Path
$output = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($output)) | Out-Null
if ([IO.File]::Exists($output)) { [IO.File]::Delete($output) }

$excluded = @(
    '\.git([\\/]|$)',
    '(^|[\\/])(bin|obj|node_modules|__pycache__|\.pytest_cache|\.test-runtime|\.venv[^\\/]*|test-images|outputs|audit|dotnet-sdk)([\\/]|$)',
    '(^|[\\/])DevFleet\.Setup([\\/])Payload([\\/]).*\.(tar\.gz|exe)$',
    '\.(vhd|vhdx|avhdx|iso|exe)$'
)
$seen = @{}
$zip = [IO.Compression.ZipFile]::Open($output, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($root in @($source, $installer)) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName) {
            $relative = ([Uri]::new(($root.TrimEnd('\') + '\')).MakeRelativeUri([Uri]::new($file.FullName)).ToString()).Replace('/','/')
            if ($excluded | Where-Object { $relative -match $_ }) { continue }
            $entryName = $relative
            if ($seen.ContainsKey($entryName)) {
                if ($root -eq $installer -and $entryName -eq 'dependencies.json') { continue }
                $existingHash = $seen[$entryName]
                $currentHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                if ($existingHash -ne $currentHash) { throw "Source archive collision with different contents: $entryName" }
                continue
            }
            $entry = $zip.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
            $input = [IO.File]::OpenRead($file.FullName); $outputStream = $entry.Open()
            try { $input.CopyTo($outputStream) } finally { $outputStream.Dispose(); $input.Dispose() }
            $seen[$entryName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
} finally { $zip.Dispose() }
$result = Get-Item -LiteralPath $output
Write-Host "Installer source archive generated: $output ($($result.Length) bytes)"

```


## FILE: source/tools/Verify-Package.ps1

SHA256: 823ed5d1f17bf4b46a0f8f306ff73833df46ab50221734ff5116a8cac7e84cec | Bytes: 3453 | Git mode: 100644

```
[CmdletBinding()]
param([switch]$SkipChecksums)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$required=@('VERSION','README-FIRST.md','Upgrade-DevFleet.ps1','DevFleet-v1.1.0-MIGRATION.md','DevFleet-v1.1.0-VALIDATION.md','DevFleet-v1.1.0-FILE-CHANGES.md','config\devfleet.config.json','config\ollama-profiles.json','client\Configure-SSH.ps1','client\Configure-DockerContext.ps1','windows\Migrate-Config.ps1','windows\Configure-Ollama.ps1','windows\Set-DevFleetDockerMode.ps1','linux\devfleet-switch-docker-mode','app\devfleet\main.py','docs\13-PERFORMANCE-TUNING.md')
foreach($r in $required){if(-not(Test-Path(Join-Path $root $r))){throw "Missing $r"}}
$errors=@();Get-ChildItem $root -Recurse -File|Where-Object Extension -in @('.ps1','.psm1')|ForEach-Object{$tokens=$null;$parse=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$parse);foreach($e in $parse){$errors+="$($_.FullName):$($e.Extent.StartLineNumber): $($e.Message)"}};if($errors){throw "PowerShell parsing failed:`n$($errors -join "`n")"}
$jsonErrors=@();Get-ChildItem $root -Recurse -File -Filter *.json|Where-Object{$_.FullName -notmatch '[\\/](\.git|\.pytest_cache|\.test-runtime|__pycache__|runtime-migrations)[\\/]'}|ForEach-Object{try{[void](Get-Content $_.FullName -Raw|ConvertFrom-Json)}catch{$jsonErrors+="$($_.FullName): $($_.Exception.Message)"}};if($jsonErrors){throw "JSON parsing failed:`n$($jsonErrors -join "`n")"}
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim();$cfg=Get-Content (Join-Path $root 'config\devfleet.config.json') -Raw|ConvertFrom-Json;if([int]$cfg.SchemaVersion -ne 2 -or [string]$cfg.PackageVersion -ne $version){throw "Default configuration is not schema 2 / v$version."}
$transientPackageParts=@('.git','.pytest_cache','.test-runtime','__pycache__','runtime-migrations','outputs','audit-extract');$bad=Get-ChildItem $root -Recurse -File|Where-Object{$relative=$_.FullName.Substring($root.Length).TrimStart([char]92,[char]47).Replace([char]92,[char]47);$parts=$relative.Split('/');$generated=($parts|Where-Object{$_ -eq '.venv' -or $_ -like '.venv-*' -or $transientPackageParts -contains $_}).Count -gt 0;(-not $generated) -and $_.Length -eq 0 -and $_.Name -ne '__init__.py'};if($bad){throw "Unexpected empty files: $($bad.FullName -join ', ')"}
if(-not $SkipChecksums){$manifest=Join-Path $root 'CHECKSUMS.sha256';foreach($line in Get-Content $manifest){if($line -notmatch '^([0-9a-f]{64})  (.+)$'){continue};$expected=$Matches[1];$rel=$Matches[2].Replace('/','\');$path=Join-Path $root $rel;if(-not(Test-Path $path)){throw "Missing checksum target $rel"};$actual=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant();if($actual -ne $expected){$bytes=[IO.File]::ReadAllBytes($path);$hasLoneCr=$false;for($i=0;$i -lt $bytes.Length;$i++){if($bytes[$i] -eq 13 -and ($i+1 -ge $bytes.Length -or $bytes[$i+1] -ne 10)){$hasLoneCr=$true;break}};if(-not $hasLoneCr -and ($bytes -contains 13)){$normalized=[Text.Encoding]::UTF8.GetBytes(([Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n"));$sha=[Security.Cryptography.SHA256]::Create();try{$actual=([BitConverter]::ToString($sha.ComputeHash($normalized))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}};if($actual -ne $expected){throw "Checksum mismatch $rel"}}}
Write-Host 'Package structure, PowerShell AST syntax, JSON/schema, and checksums verified.' -ForegroundColor Green

```


## FILE: source/tools/build_release.py

SHA256: 59e38747a1c410ea7710b522c5bb2dab73adb841e892503c87114aed97dc5712 | Bytes: 8017 | Git mode: 100644

```
"""Reproducible DevFleet TAR and portable bundle builder."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import stat
import tarfile
import zipfile
from pathlib import Path

from hook_modes import executable_template_hooks, hook_mode_manifest

TRANSIENT = {".git", ".pytest_cache", ".test-runtime", "__pycache__", "runtime-migrations"}


def is_transient_part(part: str) -> bool:
    return part in TRANSIENT or part.startswith(".venv")


def files(root: Path) -> list[Path]:
    candidates = (
        p
        for p in root.rglob("*")
        if p.is_file()
        and not any(is_transient_part(part) for part in p.relative_to(root).parts)
    )
    return sorted(
        candidates,
        key=lambda path: path.relative_to(root).as_posix().encode("utf-8"),
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_checksums(root: Path) -> None:
    manifest = root / "CHECKSUMS.sha256"
    lines = [f"{sha256(path)}  {path.relative_to(root).as_posix()}" for path in files(root) if path != manifest]
    # Keep the tracked manifest byte-identical to a Git archive on Windows;
    # newline translation here would make a frozen commit unreproducible.
    manifest.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def build_tar(root: Path, output: Path) -> set[str]:
    hooks = executable_template_hooks(root)
    with output.open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed, tarfile.open(fileobj=compressed, mode="w") as archive:
        for path in files(root):
            rel = path.relative_to(root).as_posix()
            info = archive.gettarinfo(str(path), arcname=rel)
            info.mode = 0o755 if rel in hooks else 0o644
            info.mtime = 0; info.uid = 0; info.gid = 0; info.uname = "root"; info.gname = "root"
            with path.open("rb") as stream:
                archive.addfile(info, stream)
    return hooks


def portable_metadata(entries: list[tuple[str, bytes]], version: str, nested_tar: Path, root: Path) -> list[tuple[str, bytes]]:
    nested_tar_name = nested_tar.name
    current_source = [("source/" + path.relative_to(root).as_posix(), path.read_bytes()) for path in files(root)]
    source_names = [name for name, _ in current_source]
    source_hashes = [{"path": name, "sha256": sha256_bytes(data)} for name, data in current_source]
    manifest = {"version": version, "file_count": len(source_names), "files": source_hashes}
    canonical_docs = {
        "README.md": (
            f"# DevFleet Safe Remote Development v{version}\n\n"
            f"This is the clean-room v{version} portable bundle. The TAR is the authoritative POSIX-mode artifact.\n\n"
            f"Verify `CHECKSUMS.sha256`, then run `python source/tools/verify_package.py --archive {nested_tar_name}` from the extracted bundle root.\n"
        ).encode(),
        "CLEAN-ROOM-VERIFICATION.md": (
            f"# DevFleet {version} clean-room verification\n\n"
            "Extract this ZIP into a fresh directory. From the extracted bundle root, run:\n\n"
            f"`python source/tools/verify_package.py --archive {nested_tar_name}`\n\n"
            "The command must complete successfully before the portable package is accepted.\n"
        ).encode(),
        "DIRECTORY-LAYOUT.md": (
            f"# DevFleet {version} portable layout\n\n"
            f"`source/` contains the complete canonical source. `{nested_tar_name}` preserves the release source and trusted POSIX hook modes.\n"
        ).encode(),
    }
    rebuilt: list[tuple[str, bytes]] = []
    for name, data in entries:
        if name.startswith("devfleet-v1.2.") and name.endswith(".tar.gz"):
            continue
        if name.startswith("source/"):
            continue
        if name in {"portable-codebase-manifest.json", "portable-codebase-sha256.txt", "source-tree-manifest.json", "source-tree-sha256.txt"}:
            continue
        if name in canonical_docs:
            continue
        rebuilt.append((name, data))
    rebuilt.extend(canonical_docs.items())
    rebuilt.append((nested_tar_name, nested_tar.read_bytes()))
    rebuilt.extend(current_source)
    rebuilt.append(("portable-codebase-manifest.json", json.dumps(manifest, indent=2).encode()))
    rebuilt.append(("source-tree-manifest.json", json.dumps({"version": version, "file_count": len(source_names), "files": source_hashes}, indent=2).encode()))
    rebuilt.append(("source-tree-sha256.txt", ("\n".join(f"{item['sha256']}  {item['path']}" for item in source_hashes) + "\n").encode()))
    rebuilt.append(("portable-codebase-sha256.txt", ("\n".join(f"{sha256_bytes(data)}  {name}" for name, data in sorted(rebuilt, key=lambda item: item[0].encode("utf-8")) if name not in {"portable-codebase-sha256.txt"}) + "\n").encode()))
    _assert_portable_instruction_identity(rebuilt, version, nested_tar_name)
    return rebuilt


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _assert_portable_instruction_identity(entries: list[tuple[str, bytes]], version: str, nested_tar_name: str) -> None:
    instruction_names = {"README.md", "CLEAN-ROOM-VERIFICATION.md", "DIRECTORY-LAYOUT.md"}
    stale_version = re.compile(r"(?:DevFleet\s+v|devfleet-v)(\d+\.\d+\.\d+)")
    for name, data in entries:
        if name not in instruction_names:
            continue
        text = data.decode("utf-8", errors="strict")
        for match in stale_version.finditer(text):
            context = text[max(0, match.start() - 80):match.end() + 80].lower()
            if match.group(1) != version and "historical" not in context:
                raise ValueError(f"Portable release instruction {name} contains an unapproved prior release identity.")
        if name == "CLEAN-ROOM-VERIFICATION.md" and nested_tar_name not in text:
            raise ValueError(f"Portable clean-room instructions do not name {nested_tar_name}.")


def main() -> None:
    global args, root
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--old-portable", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    root = args.source.resolve()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (root / "CHECKSUMS.sha256").unlink(missing_ok=True)
    write_checksums(root)
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    tar = args.output_dir / f"devfleet-v{version}.tar.gz"
    hooks = build_tar(root, tar)
    with zipfile.ZipFile(args.old_portable) as source_zip:
        entries = [(item.filename, source_zip.read(item.filename)) for item in source_zip.infolist() if not item.is_dir()]
    portable = args.output_dir / f"DevFleet-v{version}-Portable-Codebase-Verified-r1.zip"
    rebuilt = portable_metadata(entries, version, tar, root)
    with zipfile.ZipFile(portable, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as out:
        for name, data in sorted(rebuilt, key=lambda item: item[0].encode("utf-8")):
            info = zipfile.ZipInfo(name)
            mode = 0o755 if name.removeprefix("source/") in hooks else 0o644
            info.create_system = 3  # Unix origin; required for standard unzip mode restoration.
            info.external_attr = (stat.S_IFREG | mode) << 16
            out.writestr(info, data)
    manifest = hook_mode_manifest(root); manifest.update({"version": version, "mode": "0755"})
    (args.output_dir / "hook-mode-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"tar": str(tar), "portable": str(portable), "hook_count": len(hooks), "tar_sha256": sha256(tar), "portable_sha256": sha256(portable)}, indent=2))


if __name__ == "__main__":
    main()

```


## FILE: source/tools/check_dependency_advisories.py

SHA256: 8901ed5ad3d19846030f2c6b8af5f03274277ef76b641b540a127d9994906185 | Bytes: 11275 | Git mode: 100644

```
"""Reproducible OSV freshness gate for the exact DevFleet dependency lock."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from packaging.markers import Marker
from packaging.requirements import InvalidRequirement, Requirement
from packaging.utils import canonicalize_name

try:
    from cvss import CVSS2, CVSS3, CVSS4
    from cvss.exceptions import CVSSError
except ImportError as exc:  # pragma: no cover - exercised by release preflight
    raise RuntimeError(
        "release dependency gate requires the pinned 'cvss' release-tool dependency"
    ) from exc


OSV_QUERY_URL = "https://api.osv.dev/v1/query"
TIMEOUT_SECONDS = 8
HIGH_SCORE = 7.0
CRITICAL_SCORE = 9.0
KNOWN_SEVERITIES = {"NONE", "LOW", "MEDIUM", "MODERATE", "HIGH", "CRITICAL"}
BLOCKING_SEVERITIES = {"HIGH", "CRITICAL", "UNKNOWN"}


def _logical_requirement_lines(lock: Path) -> list[str]:
    """Return requirement expressions from a pip-compile style lock.

    Hashes and pip-compile annotations are deliberately ignored.  A continued
    marker expression is retained, while a continued requirement is finalized
    before the next top-level package line.
    """
    expressions: list[str] = []
    pending: str | None = None
    for physical in lock.read_text(encoding="utf-8").splitlines():
        line = physical.strip()
        if not line or line.startswith("#") or line.startswith("--hash="):
            continue
        # pip-compile may emit other option continuations; none are part of the
        # PEP 508 requirement we need to query.
        if line.startswith("--"):
            continue
        if " #" in line:
            line = line.split(" #", 1)[0].rstrip()
        if not line:
            continue
        if pending is not None:
            if line.startswith(";") or line.startswith(","):
                pending = f"{pending} {line}"
                if pending.endswith("\\"):
                    pending = pending[:-1].rstrip()
                continue
            expressions.append(pending)
            pending = None
        if line.endswith("\\"):
            pending = line[:-1].rstrip()
        else:
            expressions.append(line)
    if pending is not None:
        expressions.append(pending)
    return expressions


def _requirement_expression(line: str) -> tuple[str, str, str | None]:
    try:
        requirement = Requirement(line)
    except InvalidRequirement as exc:
        raise ValueError(f"unsupported lock requirement: {line!r}") from exc
    specifiers = list(requirement.specifier)
    if len(specifiers) != 1 or specifiers[0].operator != "==" or specifiers[0].version.endswith(".*"):
        raise ValueError(f"lock requirement is not an exact == pin: {line!r}")
    version = specifiers[0].version.strip()
    if not version or any(ch.isspace() for ch in version) or ";" in version:
        raise ValueError(f"lock requirement has an invalid pinned version: {line!r}")
    marker = str(requirement.marker) if requirement.marker else None
    # Constructing Marker validates the complete expression, and makes the
    # target-environment policy explicit even though all exact lock pins are
    # queried conservatively below.
    if marker:
        Marker(marker)
    return canonicalize_name(requirement.name), version, marker


def lock_requirements(lock: Path) -> list[tuple[str, str, str | None]]:
    parsed = [_requirement_expression(line) for line in _logical_requirement_lines(lock)]
    if not parsed:
        raise ValueError(f"lock contains no exact pinned requirements: {lock}")
    # A compiled lock is the certified dependency set.  Query every exact pin,
    # including platform-marked pins, rather than silently dropping a supported
    # target.  Duplicate name/version rows are queried once.
    unique: list[tuple[str, str, str | None]] = []
    seen: set[tuple[str, str]] = set()
    for package, version, marker in parsed:
        key = (package, version)
        if key not in seen:
            seen.add(key)
            unique.append((package, version, marker))
    return unique


def lock_packages(lock: Path) -> list[tuple[str, str]]:
    return [(package, version) for package, version, _marker in lock_requirements(lock)]


def _score(vulnerability: dict) -> float | None:
    scores: list[float] = []
    for item in vulnerability.get("severity", []) or []:
        raw = str(item.get("score", ""))
        if not raw:
            continue
        try:
            kind = str(item.get("type") or "").upper()
            if raw.startswith("CVSS:2.0/") or kind == "CVSS_V2":
                scores.append(float(CVSS2(raw).scores()[0]))
            elif raw.startswith(("CVSS:3.0/", "CVSS:3.1/")) or kind == "CVSS_V3":
                scores.append(float(CVSS3(raw).scores()[0]))
            elif raw.startswith("CVSS:4.0/") or kind == "CVSS_V4":
                scores.append(float(CVSS4(raw).scores()[0]))
            else:
                # OSV has historically emitted numeric scores for some records;
                # accept only a complete numeric value in the valid CVSS range.
                numeric = float(raw)
                if 0.0 <= numeric <= 10.0:
                    scores.append(numeric)
        except (TypeError, ValueError, IndexError, CVSSError):
            continue
    return max(scores) if scores else None


def _declared_severities(vulnerability: dict) -> list[str]:
    values: list[str] = []
    specific = vulnerability.get("database_specific") or {}
    for value in (specific.get("severity"),):
        if value is not None:
            values.append(str(value).upper())
    for affected in vulnerability.get("affected", []) or []:
        if not isinstance(affected, dict):
            continue
        ecosystem_specific = affected.get("ecosystem_specific") or {}
        if ecosystem_specific.get("severity") is not None:
            values.append(str(ecosystem_specific["severity"]).upper())
    return values


def _severity(vulnerability: dict) -> str:
    declared_values = _declared_severities(vulnerability)
    invalid_declared = [value for value in declared_values if value not in KNOWN_SEVERITIES]
    declared = max(
        (value for value in declared_values if value in KNOWN_SEVERITIES),
        key=lambda value: {"NONE": 0, "LOW": 1, "MEDIUM": 2, "MODERATE": 2, "HIGH": 3, "CRITICAL": 4}[value],
        default="",
    )
    score = _score(vulnerability)
    if score is not None:
        score_label = "CRITICAL" if score >= CRITICAL_SCORE else "HIGH" if score >= HIGH_SCORE else "MEDIUM" if score >= 4.0 else "LOW" if score > 0 else "NONE"
        rank = {"NONE": 0, "LOW": 1, "MEDIUM": 2, "MODERATE": 2, "HIGH": 3, "CRITICAL": 4}
        if rank[score_label] > rank.get(declared, -1):
            declared = score_label
    invalid_vectors = any(
        str(item.get("score") or "").upper().startswith("CVSS:") and _score({"severity": [item]}) is None
        for item in vulnerability.get("severity", []) or []
        if isinstance(item, dict)
    )
    if (invalid_declared or invalid_vectors) and declared not in {"HIGH", "CRITICAL"}:
        return "UNKNOWN"
    if score is not None and score >= CRITICAL_SCORE:
        return "CRITICAL"
    if score is not None and score >= HIGH_SCORE:
        return "HIGH"
    return declared or "UNKNOWN"


def query(package: str, version: str) -> dict:
    body = json.dumps({"package": {"name": package, "ecosystem": "PyPI"}, "version": version}).encode()
    request = urllib.request.Request(OSV_QUERY_URL, data=body, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.load(response)


def run(lock: Path, allowlist: Path) -> dict:
    checked_at = datetime.now(timezone.utc).isoformat()
    lock_bytes = lock.read_bytes()
    allowlist_bytes = allowlist.read_bytes() if allowlist.is_file() else b'{"exceptions": []}'
    allowed = json.loads(allowlist.read_text(encoding="utf-8")) if allowlist.is_file() else {"exceptions": []}
    exceptions = {
        (str(item.get("advisory_id")), str(item.get("package")).lower().replace("_", "-"), str(item.get("affected_version"))): item
        for item in allowed.get("exceptions", [])
        if isinstance(item, dict)
    }
    results: list[dict] = []
    blocking: list[dict] = []
    errors: list[str] = []
    for package, version, marker in lock_requirements(lock):
        try:
            response = query(package, version)
            vulnerabilities = response.get("vulns", []) or []
            advisories = []
            for vulnerability in vulnerabilities:
                advisory_id = str(vulnerability.get("id") or "unknown")
                severity = _severity(vulnerability)
                item = {"id": advisory_id, "severity": severity, "summary": str(vulnerability.get("summary") or "")[:500]}
                advisories.append(item)
                if severity in BLOCKING_SEVERITIES and (advisory_id, package, version) not in exceptions:
                    blocking.append({"package": package, "version": version, **item})
            results.append({"package": package, "version": version, "marker": marker, "query": {"package": {"name": package, "ecosystem": "PyPI"}, "version": version}, "advisories": advisories, "status": "PASS" if not advisories else "ADVISORIES_REVIEWED"})
        except (OSError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            errors.append(f"{package}=={version}: {type(exc).__name__}: {exc}")
            results.append({"package": package, "version": version, "status": "ERROR", "error": str(exc)[:500]})
    status = "BLOCKED" if blocking or errors else "PASS"
    return {
        "schema_version": 2,
        "checker": "DevFleet dependency advisory gate",
        "checker_version": "2.0.0",
        "status": status,
        "source": OSV_QUERY_URL,
        "checked_at": checked_at,
        "lock": str(lock),
        "lock_sha256": hashlib.sha256(lock_bytes).hexdigest(),
        "allowlist": str(allowlist),
        "allowlist_sha256": hashlib.sha256(allowlist_bytes).hexdigest(),
        "target_environment_policy": "query every exact pin in the compiled lock, including platform-marked pins; deduplicate only identical canonical package/version pairs",
        "packages": results,
        "blocking_advisories": blocking,
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--allowlist", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = run(args.lock, args.allowlist)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "packages": len(report["packages"]), "blocking": len(report["blocking_advisories"]), "errors": len(report["errors"])}))
    return 0 if report["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/tools/hook_modes.py

SHA256: 3010bf588f088c9e6d4e956c2127a06abfec78f4875eec3441475383b6e02e54 | Bytes: 5491 | Git mode: 100644

```
"""Single source of truth for executable template hook closure and modes."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
import sys

COMMAND_FIELDS = ("bootstrap_command", "health_command", "test_command", "codexpro_command")
LOCAL_HOOK_RE = re.compile(r"(?<![A-Za-z0-9_./-])(?:\./)?(?P<path>\.devfleet/[A-Za-z0-9._-]+\.sh)(?![A-Za-z0-9_./-])")
ABSOLUTE_HOOK_RE = re.compile(r"(?<![A-Za-z0-9_./-])/(?P<path>(?:[^\s\"']+/)*\.devfleet/[A-Za-z0-9._-]+\.sh)")
LOCALISH_HOOK_RE = re.compile(r"(?<![A-Za-z0-9_])(?P<path>(?:\./)?\.devfleet/[^\s\"'`()]+\.sh)")


@dataclass(frozen=True)
class HookClosure:
    """The complete, validated local executable-script closure for a template."""

    direct: frozenset[str]
    transitive: frozenset[str]

    @property
    def executable(self) -> frozenset[str]:
        return self.direct | self.transitive


def _local_references(text: str, *, origin: Path) -> set[str]:
    """Extract only local .devfleet script references and reject unsafe lookalikes."""
    absolute = ABSOLUTE_HOOK_RE.search(text)
    if absolute:
        raise ValueError(f"absolute external hook reference in {origin}: {absolute.group('path')}")
    for candidate in LOCALISH_HOOK_RE.finditer(text):
        path = candidate.group("path")
        if ".." in Path(path).parts or "/" in path.removeprefix("./.devfleet/"):
            raise ValueError(f"unsafe local hook reference in {origin}: {path}")
    return {match.group("path") for match in LOCAL_HOOK_RE.finditer(text)}


def _resolve_local(root: Path, template_dir: Path, relative: str, *, origin: Path) -> tuple[str, Path]:
    candidate = (template_dir / relative).resolve(strict=False)
    template_root = template_dir.resolve()
    try:
        candidate.relative_to(template_root)
    except ValueError as exc:
        raise ValueError(f"hook reference escapes template root in {origin}: {relative}") from exc
    if candidate.parent != (template_dir / ".devfleet").resolve():
        raise ValueError(f"hook refere