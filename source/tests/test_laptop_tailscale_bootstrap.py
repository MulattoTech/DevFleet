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
