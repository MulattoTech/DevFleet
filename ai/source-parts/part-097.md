# DevFleet source part 097

Full-source UTF-8 byte interval [4464000, 4510500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 7f546be50508279a24f49223e6c042904ddd117f18d8e611023fc76ddb3eb78f

<!-- BEGIN SOURCE SLICE -->
OOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "Get-AuthenticodeSignature" in source
    assert "while($cursor)" in source
    assert "ReparsePoint" in source
    assert "allowedSignerSubjectsExact" in source
    assert "Legacy substring signer policy is rejected" in source
    assert "Get-TrustedDependencyCandidates $Dependency" in source
    assert "if($signature.Status -ne 'Valid' -and -not $allowUnsignedInstalled)" in source
    assert "Get-Acl -LiteralPath $full" in source
    assert "if(@($exact).Count -gt 0" in source
    assert "$policy=if($null -ne $Dependency){$Dependency.installerAuthenticityPolicy}else{$null}" in source
    assert "PSObject.Properties['installedExecutableTrust']" in source


def test_canonical_dependency_policies_do_not_use_substring_signer_authority():
    for relative in ("dependencies.json",):
        for path in (ROOT / relative, ROOT.parent / "installer-source" / "DevFleet.Setup" / relative):
            manifest = json.loads(path.read_text(encoding="utf-8"))
            policies = [item["installerAuthenticityPolicy"] for item in manifest["dependencies"]]
            assert all("allowedSignerPatterns" not in policy for policy in policies)
            assert all(policy.get("strategy") == "VendorReleaseSha256" or policy.get("allowedSignerSubjectsExact") for policy in policies)
            multipass = next(item for item in manifest["dependencies"] if item["id"] == "multipass")
            assert multipass["installerAuthenticityPolicy"]["installedExecutableTrust"] == "signed-installer-locked-path"


def test_multipass_runtime_resolution_reuses_canonical_dependency_policy():
    source = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    start = source.index("function Get-MultipassExe")
    end = source.index("function Assert-MultipassIsolation", start)
    resolver = source[start:end]
    assert "Get-CanonicalDependencyManifest -PackageRoot $packageRoot" in resolver
    assert "Where-Object id -eq 'multipass'" in resolver
    assert "Wait-DevFleetDependencyStatus -Dependency $dependency" in resolver
    assert "Test-TrustedExecutableCandidate ([string]$cached.Path) -Dependency $dependency" in resolver
    assert "Get-FileHash -LiteralPath ([string]$cached.Path) -Algorithm SHA256" in resolver
    assert "Status -eq 'Compatible'" in resolver
    # The resolver must never fall back to the generic no-policy trust check.
    assert "Test-TrustedExecutableCandidate $candidate" not in resolver


def test_csharp_dependency_probe_authenticates_before_reading_version():
    source = (ROOT.parent / "installer-source" / "DevFleet.Setup" / "Services" / "InstallerLifecycle.cs").read_text(encoding="utf-8")
    assert "IsTrustedInstalledDependency(candidate, dependency)" in source
    assert "ReadAuthenticodeSubject" in source
    assert "AllowedSignerSubjectsExact" in source
    assert "Legacy substring signer policy is rejected" in source
    assert source.index("IsTrustedInstalledDependency(candidate, dependency)") < source.index("ReadVersion(candidate, dependency)")
    assert "DirectoryInfo(Path.GetDirectoryName(full)!)" in source
    assert "InstalledExecutableTrust" in source
    assert "signed-installer-locked-path" in source
    assert "Microsoft.DesktopAppInstaller" in source
    assert "8wekyb3d8bbwe" in source


def test_secret_bearing_archive_arguments_are_not_created():
    source = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "-p$password" not in source
    assert "New-EncryptedBundle" in source
    assert "Expand-EncryptedBundle" in source
    assert "DFENV001" in source
    assert "AesGcm" in source


def test_external_process_wrapper_has_timeout_tree_kill_and_bounded_diagnostics():
    source = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "TimeoutSeconds" in source
    assert "$process.Kill($true)" in source
    assert "MaxDiagnosticChars" in source
    assert "EvidenceLogPath" in source


def test_windows_powershell_common_module_has_no_powershell_7_null_coalescing_operator():
    source = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")
    assert "??" not in source
    assert "Add-Type -AssemblyName System.Net.Http" in source
    assert "[System.Net.Http.HttpClientHandler]::new()" in source
    assert "[System.Net.Http.HttpClient]::new($handler)" in source

```


## FILE: source/tests/test_installer_self_cleanup.py

SHA256: 966731a830d6a62ca9fa6d366ae88252a4c8d60f28fbe645221e35dc6a10ce25 | Bytes: 648 | Git mode: 100644

```
from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_installer_self_cleanup_uses_argument_bound_helper_without_cmd_shell():
    source = (ROOT / "installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs").read_text(encoding="utf-8")
    method = source[source.index("private static void ScheduleSelfRemoval"):source.index("private static void RemoveExactRegistryEntry")]
    assert ".cmd" not in method
    assert "cmd.exe" not in method
    assert "ArgumentList.Add" in method
    assert "-LiteralPath $Target" in method
    assert "ProcessWindowStyle.Hidden" in method
    assert "Start-Sleep -Milliseconds 500" in method

```


## FILE: source/tests/test_language_templates.py

SHA256: bf6448bdd5f7ee48208912fee44e08c99614c72f7ec036c9e4301a91d6cc60d7 | Bytes: 2062 | Git mode: 100644

```
import json
from pathlib import Path
from devfleet.language_policy import TEMPLATES,recommend_template
from devfleet import analyzer, projects
import yaml
ROOT=Path(__file__).resolve().parents[1]
CORE={'generic','python','python-fastapi','node','typescript-node','typescript-next','go-service','dotnet-service','java-spring','rust-service'}
def test_legacy_and_new_templates_exist():
 assert {'generic','python','node'}<=set(TEMPLATES);assert len(TEMPLATES)==20
 for name in TEMPLATES:
  d=ROOT/'templates'/name;assert (d/'compose.yaml').is_file();assert (d/'.devcontainer/devcontainer.json').is_file();assert (d/'.devfleet/codexpro-bootstrap.sh').is_file();assert (d/'README.md').is_file();assert (d/'docs/architecture.md').is_file()
def test_core_metadata_commands():
 for name in CORE:
  data=json.loads((ROOT/'templates'/name/'.devfleet/template.json').read_text())
  for key in ('bootstrap_command','format_command','lint_command','test_command','health_command'):assert data[key]
def test_recommendations():assert recommend_template('python','fastapi')=='python-fastapi' and recommend_template('go')=='go-service'
def test_language_metadata_documented():
 for name in CORE:
  assert 'Language:' in (ROOT/'templates'/name/'README.md').read_text();assert 'Rationale:' in (ROOT/'templates'/name/'docs/architecture.md').read_text()

def test_generated_templates_satisfy_strict_security_contract(tmp_path,monkeypatch):
 monkeypatch.setattr(projects,'TEMPLATE_ROOT',ROOT/'templates')
 for name in TEMPLATES:
  project=tmp_path/name
  project.mkdir()
  projects._copy_template(project,name)
  compose=yaml.safe_load((project/'compose.yaml').read_text())
  services=compose['services']
  assert services
  for service in services.values():
   assert 'ALL' in [str(value).upper() for value in (service.get('cap_drop') or [])]
   assert any('no-new-privileges:true' in str(value).lower() for value in (service.get('security_opt') or []))
  findings=analyzer.analyze_project(project,'strict',force=True)
  assert not analyzer.has_blockers(findings), (name, findings)

```


## FILE: source/tests/test_laptop_profile.py

SHA256: a255b83381a5753c49b6029fdd6308ba0ac14d6a2a3774d0aa0dd2eaef0bcd3a | Bytes: 473 | Git mode: 100644

```
import pytest

from devfleet.resource_profiles import LAPTOP_PROFILE_DEFAULT, laptop_surrogate_profile


def test_laptop_default_is_conservative_5g_2g():
    assert laptop_surrogate_profile() == LAPTOP_PROFILE_DEFAULT


def test_laptop_lower_bound_fails_closed():
    with pytest.raises(ValueError, match="below"):
        laptop_surrogate_profile(failover_memory_gb=3)
    with pytest.raises(ValueError, match="below"):
        laptop_surrogate_profile(vault_memory_gb=1)

```


## FILE: source/tests/test_laptop_tailscale_bootstrap.py

SHA256: 499afe9442a2d9944d4fe7fc1c363c3f28880c8702472d5c9d45c610aa1c509b | Bytes: 6219 | Git mode: 100644

```
"""Execute shipped shell boundaries with external services replaced by fixtures."""
import json
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
BASH = Path(r'C:\Program Files\Git\bin\bash.exe')


def unix(path):
    value = path.resolve().as_posix()
    return '/' + value[0].lower() + value[2:] if value[1:3] == ':/' else value


def cloud_client():
    yaml = (ROOT / 'cloud-init/vault.yaml').read_text(encoding='utf-8-sig')
    start = yaml.index('  - path: /usr/local/sbin/devfleet-install-vault-tailscale')
    content = yaml.index('    content: |\n', start) + len('    content: |\n')
    lines = []
    for line in yaml[content:].splitlines():
        if not line.startswith('      '):
            break
        lines.append(line[6:])
    assert lines and lines[0] == '#!/usr/bin/env bash'
    return '\n'.join(lines) + '\n'


@pytest.mark.parametrize('case,expected', [('valid', 0), ('wrong-key', 4), ('extra-public-key', 4), ('download-failure', 22), ('apt-failure', 42), ('service-failure', 44)])
def test_vault_client_installs_only_after_pinned_key_verification(tmp_path, case, expected):
    assert BASH.is_file(), 'Use the existing Git for Windows Bash test runtime.'
    fingerprint = json.loads((ROOT / 'linux/dependency-policy.json').read_text())['tailscale']['signingKeySha256Fingerprint']
    assert re.fullmatch('[A-F0-9]{40}', fingerprint)
    body = cloud_client().replace('__TAILSCALE_SIGNING_FINGERPRINT__', fingerprint)
    paths = ['/etc/os-release', '/usr/share/keyrings/tailscale-archive-keyring.gpg', '/etc/apt/sources.list.d/tailscale.list']
    for index, path in enumerate(paths):
        body = body.replace(path, unix(tmp_path / str(index)))
    (tmp_path / '0').write_text('ID=ubuntu\nVERSION_CODENAME=noble\n')
    (tmp_path / 'tmp').mkdir()
    preamble = r'''
set -Eeuo pipefail
cd "$1"
export TMPDIR="$PWD/tmp"
case_name="$2"
fingerprint="$3"
curl() { [[ "$case_name" != download-failure ]] || return 22; printf 'fixture public key' > "${@: -1}"; }
gpg() { printf 'pub:::::::::\n'; if [[ "$case_name" == wrong-key ]]; then printf 'fpr:::::::::0000000000000000000000000000000000000000:\n'; else printf 'fpr:::::::::%s:\n' "$fingerprint"; fi; printf 'sub:::::::::\nfpr:::::::::1111111111111111111111111111111111111111:\n'; if [[ "$case_name" == extra-public-key ]]; then printf 'pub:::::::::\nfpr:::::::::2222222222222222222222222222222222222222:\n'; fi; }
install() { printf 'verified-key-install\n' >> calls; cp -- "$3" "$4"; }
apt-get() { printf 'apt %s\n' "$*" >> calls; [[ "$case_name" != apt-failure ]] || return 42; }
systemctl() { printf 'service %s\n' "$*" >> calls; [[ "$case_name" != service-failure ]] || return 44; }
'''
    script = tmp_path / 'test.sh'
    script.write_text(preamble + body, encoding='utf-8', newline='\n')
    result = subprocess.run([str(BASH), '--noprofile', '--norc', unix(script), unix(tmp_path), case, fingerprint], capture_output=True, text=True, timeout=15)
    assert result.returncode == expected, (result.returncode, result.stderr)
    assert not list((tmp_path / 'tmp').iterdir()), 'Owned public-key temporary file was not cleaned.'
    calls = (tmp_path / 'calls').read_text() if (tmp_path / 'calls').exists() else ''
    if expected in (4, 22):
        assert not calls and not (tmp_path / '1').exists() and not (tmp_path / '2').exists()
    else:
        assert calls.startswith('verified-key-install\napt update\n')
    if expected == 0:
        assert 'apt install -y tailscale\nservice enable --now tailscaled\n' in calls
        assert 'signed-by=' in (tmp_path / '2').read_text()


@pytest.mark.parametrize('address,authenticated', [('', False), ('100.64.1.2', True), ('100.127.255.255', True), ('100.1.1.2', False), ('100.128.1.2', False), ('100.64.256.1', False), ('192.168.1.2', False)])
def test_vault_checks_start_daemon_before_authenticated_ip(tmp_path, address, authenticated):
    text = (ROOT / 'linux/bootstrap-vault.sh').read_text()
    start = text.index('begin_component tailscaleChecks ')
    end = text.index('\ncomplete_component', start) + len('\ncomplete_component')
    block = text[start:end]
    preamble = r'''
set -Eeuo pipefail
cd "$1"
address="$2"
begin_component() { :; }
complete_component() { printf completed > complete; }
systemctl() { [[ "$*" == 'enable --now tailscaled' ]] || return 8; touch daemon; }
run_bounded() { printf '%s\n' "$*" > bounded; "$@"; }
tailscale() { test -f daemon || return 9; [[ -n "$address" ]] || return 1; printf '%s\n' "$address"; }
'''
    script = tmp_path / 'check.sh'
    script.write_text(preamble + block + '\n', encoding='utf-8', newline='\n')
    result = subprocess.run([str(BASH), '--noprofile', '--norc', unix(script), unix(tmp_path), address], capture_output=True, text=True, timeout=10)
    assert (result.returncode == 0) == authenticated
    assert (tmp_path / 'complete').exists() == authenticated
    assert (tmp_path / 'daemon').exists()
    assert (tmp_path / 'bounded').read_text().strip() == 'tailscale ip -4'


def test_compute_and_vault_apply_the_same_single_primary_key_policy():
    compute = (ROOT / 'linux/bootstrap-compute.sh').read_text()
    pattern = r"awk -F: '(\$1==\"pub\"[^']+)'"
    assert re.findall(pattern, compute) == re.findall(pattern, cloud_client())


def test_cloud_init_and_provisioner_deliver_auth_before_vault_secret_bootstrap():
    cloud = (ROOT / 'cloud-init/vault.yaml').read_text()
    provisioner = (ROOT / 'windows/03-Provision-Vault.ps1').read_text()
    assert '  - gnupg\n' in cloud
    assert '[timeout, --signal=TERM, --kill-after=10s, 900s, /usr/local/sbin/devfleet-install-vault-tailscale]' in cloud
    assert ".Replace('__TAILSCALE_SIGNING_FINGERPRINT__',$tailscaleFingerprint)" in provisioner
    assert provisioner.index("'04-Connect-Tailscale.ps1'") < provisioner.index('$vaultSecrets=') < provisioner.index('Invoke-MultipassWithStandardInput')


def test_deferred_laptop_rejects_before_loading_modules_or_initializing_state():
    text = (ROOT / 'Install-DevFleet.ps1').read_text()
    guard = text.index("if($Role-eq'Laptop'-and$DeferNetworkPairing)")
    assert guard < text.index('Import-Module') < text.index('Initialize-DevFleetState')

```


## FILE: source/tests/test_metadata_io.py

SHA256: f1bdba4aa4c2d6501bd193ed8d1a4f1ac9d3ea1988d57df5e7f55a0e69f626f9 | Bytes: 16739 | Git mode: 100644

```
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

from devfleet import metadata_io


POSIX_ONLY = pytest.mark.skipif(
    not metadata_io.POSIX_FD_HARDENING,
    reason="descriptor-relative no-follow primitives are unavailable",
)
PROJECT_ID = "12345678-1234-1234-1234-123456789abc"


@pytest.fixture
def workspace(tmp_path):
    project = tmp_path / "metadata-project"
    (project / ".devfleet").mkdir(parents=True)
    value = {
        "schema_version": 5,
        "managed_by": "devfleet",
        "slug": project.name,
        "identity": project.name,
        "project_id": PROJECT_ID,
        "deployment_id": "deployment-one",
        "host_id": "host-one",
    }
    (project / ".devfleet/project.json").write_bytes(
        (json.dumps(value, indent=1) + "\n\n").encode("utf-8")
    )
    return project


def test_read_write_and_exact_byte_rollback(workspace):
    original = metadata_io.read_project_metadata(workspace)
    assert original.value["project_id"] == PROJECT_ID
    assert original.raw.endswith(b"\n\n")
    assert original.binding.posix is metadata_io.POSIX_FD_HARDENING
    changed = {**original.value, "lifecycle_status": "stopped"}
    updated = metadata_io.write_project_metadata(workspace, changed, expected=original.binding)
    assert updated.same_directory_lineage(original.binding)
    assert updated.file_identity != original.binding.file_identity
    assert metadata_io.read_project_metadata(workspace).value == changed
    rolled_back = metadata_io.write_project_metadata_bytes(workspace, original.raw, expected=updated)
    assert rolled_back.same_directory_lineage(original.binding)
    assert metadata_io.read_project_metadata(workspace).raw == original.raw
    assert list((workspace / ".devfleet").glob(".project.json.*.tmp")) == []


def test_initial_create_and_sequential_updates_require_fresh_bindings(tmp_path):
    project = tmp_path / "new-project"
    project.mkdir()
    binding = metadata_io.write_project_metadata(project, {"version": 1}, create=True)
    newer = metadata_io.write_project_metadata(project, {"version": 2}, expected=binding)
    with pytest.raises(metadata_io.MetadataSafetyError):
        metadata_io.write_project_metadata(project, {"version": 3}, expected=binding)
    metadata_io.write_project_metadata(project, {"version": 3}, expected=newer)
    assert metadata_io.read_project_metadata(project).value == {"version": 3}


def test_existing_metadata_requires_a_prior_binding(workspace):
    before = (workspace / ".devfleet/project.json").read_bytes()
    for kwargs in ({}, {"create": True}):
        with pytest.raises(metadata_io.MetadataSafetyError):
            metadata_io.write_project_metadata(workspace, {"unobserved": True}, **kwargs)
    assert (workspace / ".devfleet/project.json").read_bytes() == before


def test_initial_create_does_not_overwrite_a_racing_entry(tmp_path, monkeypatch):
    project = tmp_path / "new-project"
    project.mkdir()
    operation = "link" if metadata_io.POSIX_FD_HARDENING else "rename"
    original_operation = getattr(metadata_io.os, operation)
    foreign = b'{"foreign": true}\n'
    raced = False

    def raced_commit(source, target, **kwargs):
        nonlocal raced
        (project / ".devfleet/project.json").write_bytes(foreign)
        raced = True
        return original_operation(source, target, **kwargs)

    monkeypatch.setattr(metadata_io.os, operation, raced_commit)
    with pytest.raises(FileExistsError):
        metadata_io.write_project_metadata(project, {"created": True}, create=True)
    assert raced
    assert (project / ".devfleet/project.json").read_bytes() == foreign
    assert list((project / ".devfleet").glob(".project.json.*.tmp")) == []


@pytest.mark.skipif(os.name != "nt", reason="Windows directory-sharing primitives are unavailable")
def test_windows_parent_handles_block_rename_during_replacement(workspace, tmp_path, monkeypatch):
    original = metadata_io.read_project_metadata(workspace)
    original_replace = metadata_io.os.replace
    attempted = False

    def raced_replace(source, target, **kwargs):
        nonlocal attempted
        with pytest.raises(PermissionError):
            (workspace / ".devfleet").rename(tmp_path / "detached")
        attempted = True
        return original_replace(source, target, **kwargs)

    monkeypatch.setattr(metadata_io.os, "replace", raced_replace)
    metadata_io.write_project_metadata(workspace, {"changed": True}, expected=original.binding)
    assert attempted
    assert metadata_io.read_project_metadata(workspace).value == {"changed": True}


def test_writer_rejects_a_binding_from_another_workspace(workspace, tmp_path):
    original = metadata_io.read_project_metadata(workspace)
    other = tmp_path / "other-project"
    shutil.copytree(workspace, other)
    with pytest.raises(metadata_io.MetadataSafetyError):
        metadata_io.write_project_metadata(other, original.value, expected=original.binding)


def test_writer_rejects_in_place_changes_since_the_read(workspace):
    original = metadata_io.read_project_metadata(workspace)
    metadata = workspace / ".devfleet/project.json"
    metadata.write_bytes(original.raw + b" ")
    with pytest.raises(metadata_io.MetadataSafetyError):
        metadata_io.write_project_metadata(workspace, original.value, expected=original.binding)
    assert metadata.read_bytes() == original.raw + b" "


@pytest.mark.parametrize("raw", [b"{", b"\xff", b"[1,2]"])
def test_json_and_unicode_validation_is_explicit(workspace, raw):
    (workspace / ".devfleet/project.json").write_bytes(raw)
    if raw.startswith(b"["):
        record = metadata_io.read_project_metadata(workspace)
        assert record.value == [1, 2]
        assert not metadata_io.metadata_identity_matches(record.value, workspace.name, PROJECT_ID)
    else:
        with pytest.raises((json.JSONDecodeError, UnicodeError)):
            metadata_io.read_project_metadata(workspace)


def test_nonregular_metadata_is_rejected(workspace):
    metadata = workspace / ".devfleet/project.json"
    metadata.unlink()
    metadata.mkdir()
    with pytest.raises(metadata_io.MetadataSafetyError):
        metadata_io.read_project_metadata(workspace)


def test_cli_binds_optional_deployment_and_host_and_is_silent(workspace):
    command = [sys.executable, "-I", str(Path(metadata_io.__file__)),
               "--identity", str(workspace), workspace.name, PROJECT_ID]
    for extra, expected in (([], 0), (["deployment-one"], 0),
                            (["deployment-one", "host-one"], 0),
                            (["wrong-deployment"], 1),
                            (["deployment-one", "wrong-host"], 1)):
        result = subprocess.run(command + extra, capture_output=True, text=True,
                                timeout=10, check=False)
        assert result.returncode == expected, result.stderr
        assert result.stdout == result.stderr == ""
    assert metadata_io.main(["--write", str(workspace)]) == 2


@pytest.mark.parametrize("field,value", [
    ("schema_version", 2), ("schema_version", True), ("managed_by", "foreign"),
    ("slug", "foreign-project"), ("identity", "foreign-project"),
    ("project_id", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
])
def test_identity_validation_fails_closed(workspace, field, value):
    original = metadata_io.read_project_metadata(workspace).value
    assert metadata_io.metadata_identity_matches(original, workspace.name, PROJECT_ID)
    original[field] = value
    assert not metadata_io.metadata_identity_matches(original, workspace.name, PROJECT_ID)


def _prepare_substitution(workspace, tmp_path, component, kind):
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
    source = (ROOT / "windows" / "Complete-Cluster.ps1").read_text(