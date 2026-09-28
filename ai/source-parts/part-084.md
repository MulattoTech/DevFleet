# DevFleet source part 084

Full-source UTF-8 byte interval [3859500, 3906000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 9a9ab96d3168433b6857a3fd0e7e79c53a78e84ffb55531405c62bb3a2721229

<!-- BEGIN SOURCE SLICE -->
ce/linux/devfleet-purge-quarantine

SHA256: cf80700961b1878e3de64867c67b293c44832cb0b70e59510081cbe7bfc487a1 | Bytes: 426 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
days=${1:-30}
[[ "$days" =~ ^[0-9]+$ ]] || exit 2
base=/home/devrunner/.devfleet-quarantine
[[ -d "$base" && "$(realpath "$base")" == '/home/devrunner/.devfleet-quarantine' ]] || exit 3
find "$base" -mindepth 1 -maxdepth 1 -type d -mtime "+$days" -print0 | while IFS= read -r -d '' item; do
  [[ "$(realpath "$item")" == "$base"/* ]] || exit 4
  rm -rf --one-file-system -- "$item"
done

```


## FILE: source/linux/devfleet-register-node

SHA256: 2d46e7a6e2797b33eb61c8c7aa516cad8f735a65725ff4819ce6abd5516d9b13 | Bytes: 1251 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
src=${1:?surrogate node metadata required}
jq -e '.deployment_id and .node_id and .node_role == "surrogate" and .coordinator_node_id' "$src" >/dev/null
install -d -o devfleet-control -g devfleet-control -m 0750 /var/lib/devfleet/runtime
registry=/var/lib/devfleet/runtime/node-registry.json
deployment=$(jq -r .deployment_id "$src")
node=$(jq -r .node_id "$src")
coordinator=$(jq -r .coordinator_node_id "$src")
if [[ -f "$registry" ]]; then
  jq -e --arg deployment "$deployment" '.deployment_id == $deployment' "$registry" >/dev/null || { echo 'Deployment identity mismatch; refusing a second deployment.' >&2; exit 3; }
else
  printf '{"schema_version":1,"deployment_id":"%s","nodes":[]}' "$deployment" >"$registry"
fi
tmp=$(mktemp)
jq --arg deployment "$deployment" --arg node "$node" --arg coordinator "$coordinator" --arg name "$(jq -r .node_name "$src")" '.nodes = ([.nodes[] | select(.node_id != $node)] + [{deployment_id:$deployment,node_id:$node,node_name:$name,node_role:"surrogate",coordinator_node_id:$coordinator,protocol_version:1,registration_state:"registered",connectivity:"online"}])' "$registry" >"$tmp"
install -o devfleet-control -g devfleet-control -m 0640 "$tmp" "$registry"
rm -f "$tmp"

```


## FILE: source/linux/devfleet-repair

SHA256: 0a3bc23dcf346c88d89fcc37bea30033b7d94b2f5649df6ab23e9721aefe32f5 | Bytes: 783 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
# Non-destructive repair only. No prune, project removal, volume deletion, or VM operations.
mode=$(jq -r '.docker_mode // "rootless"' /etc/devfleet/config.json)
if [[ $mode == rootless ]]; then
  uid=$(id -u devrunner)
  systemctl restart "user@$uid.service" || true
  sudo -u devrunner XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user restart docker
else
  # rootful Docker inside the disposable VM
  systemctl restart containerd docker
fi
if [[ "${1:-}" != "--skip-portal" ]]; then systemctl restart devfleet; fi
systemctl restart devfleet-backup.timer
systemctl restart tailscaled
journalctl --vacuum-time=30d >/dev/null 2>&1 || true
sudo -u devrunner /usr/local/bin/devfleet-health

```


## FILE: source/linux/devfleet-restore-project

SHA256: 426640f394e023de9d6f9be723b58d1ac2a42c83c528e0221a7c1a7018f13c23 | Bytes: 5555 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail

project=${1:?project slug required}
expected_project_id=${2:?project ID required}
mode=${3:-copy}
expected_deployment_id=${4:-}
expected_source_host_id=${5:-}
[[ "$project" =~ ^[a-z0-9][a-z0-9._-]{1,62}$ ]] || { echo 'invalid project' >&2; exit 2; }
[[ "$expected_project_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { echo 'invalid project ID' >&2; exit 2; }
[[ "$mode" == copy || "$mode" == --canonical || "$mode" == transfer-copy ]] || { echo 'mode must be copy, transfer-copy, or --canonical' >&2; exit 2; }
if [[ "$mode" == transfer-copy ]]; then
  [[ "$expected_deployment_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { echo 'invalid deployment ID' >&2; exit 2; }
  [[ "$expected_source_host_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$ ]] || { echo 'invalid source host identity' >&2; exit 2; }
fi
[[ -r /etc/devfleet/restic.env ]] || { echo 'backup not configured' >&2; exit 3; }

set -a
source /etc/devfleet/restic.env
set +a

exec 9>/run/lock/devfleet-vault-operation.lock
flock -n 9 || { echo 'Another Vault operation is already in progress.' >&2; exit 75; }

read -r restore_uuid </proc/sys/kernel/random/uuid
stamp="$(date +%Y%m%d-%H%M%S)-${restore_uuid%%-*}"
if [[ "$mode" == --canonical ]]; then
  target="/home/devrunner/workspaces/$project"
else
  # Project slugs are capped at 63 characters. Keep the stable source prefix
  # recognizable while leaving room for the collision-resistant recovery suffix.
  recovered_slug="${project:0:28}-recovered-$stamp"
  target="/home/devrunner/workspaces/$recovered_slug"
  [[ ! -e "$target" && ! -L "$target" ]] || { echo 'Recovered copy target already exists.' >&2; exit 5; }
fi
tmp="/home/devrunner/workspaces/.${project}.restore-$stamp.tmp"
canonical_quarantine=""
workspace_identity_matches() {
  local workspace=$1
  [[ -d "$workspace" && ! -L "$workspace" ]] || return 1
  local -a command=(python3 -I /opt/devfleet/devfleet/metadata_io.py --identity "$workspace" "$project" "$expected_project_id")
  if [[ "$mode" == transfer-copy ]]; then
    command+=("$expected_deployment_id" "$expected_source_host_id")
  fi
  "${command[@]}" >/dev/null 2>&1
}
cleanup_restore() {
  rc=$?
  trap - EXIT
  if [[ "$rc" -ne 0 && "$mode" == --canonical && -n "$canonical_quarantine" ]]; then
    if [[ ! -e "$target" && ! -L "$target" && -d "$canonical_quarantine" && ! -L "$canonical_quarantine" ]]; then
      if ! mv -T --no-clobber -- "$canonical_quarantine" "$target"; then
        echo 'Canonical restore rollback failed; the prior workspace remains quarantined.' >&2
        rc=6
      elif [[ -e "$canonical_quarantine" || -L "$canonical_quarantine" ]] || ! workspace_identity_matches "$target"; then
        echo 'Canonical restore rollback did not reach its identity-bound postcondition.' >&2
        rc=6
      fi
    else
      echo 'Canonical restore rollback was blocked; the prior workspace remains quarantined.' >&2
      rc=6
    fi
  fi
  rm -rf --one-file-system -- "$tmp"
  exit "$rc"
}
trap cleanup_restore EXIT

mapfile -t snapshots < <(restic snapshots --json | jq -r 'sort_by(.time)|reverse|.[].id')
for snapshot in "${snapshots[@]}"; do
  rm -rf --one-file-system -- "$tmp"
  mkdir -p "$tmp"
  if ! restic restore "$snapshot" --target "$tmp" --include "/home/devrunner/workspaces/$project/**" >/dev/null 2>&1; then
    continue
  fi
  source_dir="$tmp/home/devrunner/workspaces/$project"
  [[ -d "$source_dir" && ! -L "$source_dir" ]] || continue
  workspace_identity_matches "$source_dir" || continue
  if [[ "$mode" == --canonical ]]; then
    if [[ -e "$target" || -L "$target" ]]; then
      workspace_identity_matches "$target" || { echo 'Canonical restore target is not the expected owned workspace.' >&2; exit 5; }
      quarantine="/home/devrunner/.devfleet-quarantine/transfer-replaced-$stamp-$project"
      [[ ! -e "$quarantine" && ! -L "$quarantine" ]] || { echo 'Canonical restore quarantine target already exists.' >&2; exit 5; }
      mkdir -p /home/devrunner/.devfleet-quarantine
      canonical_quarantine="$quarantine"
      mv -T --no-clobber -- "$target" "$quarantine"
      [[ ! -e "$target" && ! -L "$target" && -d "$quarantine" && ! -L "$quarantine" ]] || { echo 'Canonical restore could not quarantine the existing workspace.' >&2; exit 5; }
    fi
  else
    [[ ! -e "$target" && ! -L "$target" ]] || { echo 'Recovered copy target appeared during restore.' >&2; exit 5; }
  fi
  mv -T --no-clobber -- "$source_dir" "$target"
  [[ ! -e "$source_dir" && -d "$target" && ! -L "$target" ]] || { echo 'Restored workspace promotion did not reach its safe postcondition.' >&2; exit 5; }
  if [[ "$mode" != --canonical ]] && ! workspace_identity_matches "$target"; then
    invalid_quarantine="/home/devrunner/.devfleet-quarantine/vault-recovery-invalid-$stamp-$project"
    [[ ! -e "$invalid_quarantine" && ! -L "$invalid_quarantine" ]] || { echo 'Recovered workspace identity quarantine target already exists.' >&2; exit 5; }
    mkdir -p /home/devrunner/.devfleet-quarantine
    mv -T --no-clobber -- "$target" "$invalid_quarantine"
    [[ ! -e "$target" && -d "$invalid_quarantine" && ! -L "$invalid_quarantine" ]] || { echo 'Recovered workspace identity failed and quarantine did not reach its safe postcondition.' >&2; exit 5; }
    echo 'Recovered workspace identity failed; the unmarked copy was quarantined.' >&2
    exit 5
  fi
  echo "$target"
  exit 0
done

echo 'Project was not found in any available snapshot.' >&2
exit 4

```


## FILE: source/linux/devfleet-rotate-compute-secrets

SHA256: 226ad81de29d261ac0cfb014556729cb97004305cf151c60261ca5ae1505d09e | Bytes: 4865 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'secret rotation requires root' >&2; exit 2; }
MODE=${1:-apply}
GENERATION=${2:-}
[[ $GENERATION =~ ^[0-9a-fA-F-]{36}$ ]] || { echo 'invalid secret generation' >&2; exit 2; }
RECOVERY="/var/lib/devfleet/secret-recovery/$GENERATION/compute"

if [[ $MODE == rollback ]]; then
  [[ -d $RECOVERY && ! -L $RECOVERY ]] || { echo 'compute recovery state is unavailable' >&2; exit 3; }
  install -o root -g devfleet-control -m 0640 "$RECOVERY/secrets.env" /etc/devfleet/secrets.env
  install -o root -g devfleet-control -m 0640 "$RECOVERY/config.json" /etc/devfleet/config.json
  if [[ -f "$RECOVERY/restic.env" ]]; then install -o root -g devfleet-backup -m 0640 "$RECOVERY/restic.env" /etc/devfleet/restic.env; else rm -f /etc/devfleet/restic.env; fi
  systemctl restart devfleet.service
  systemctl is-active --quiet devfleet.service
  printf '{"ok":true,"rolled_back":true,"generation":"%s"}\n' "$GENERATION"
  exit 0
fi
[[ $MODE == apply ]] || { echo 'mode must be apply or rollback' >&2; exit 2; }

PAYLOAD=$(mktemp /run/devfleet-secret-rotation.XXXXXX)
trap 'rm -f -- "$PAYLOAD"' EXIT
chmod 0600 "$PAYLOAD"
cat >"$PAYLOAD"
jq -e --arg generation "$GENERATION" '
  .schema_version == 1 and .secret_generation == $generation and
  (.deployment_id|type == "string") and (.node_id|type == "string") and
  (.admin_user|type == "string" and length > 0) and
  (.admin_password|type == "string" and length >= 24) and
  (.api_token|type == "string" and length >= 40) and
  (.host_control_token|type == "string" and length >= 40)
' "$PAYLOAD" >/dev/null || { echo 'invalid compute secret rotation payload' >&2; exit 2; }

CURRENT_DEPLOYMENT=$(jq -er '.deployment_id' /etc/devfleet/node-identity.json)
CURRENT_NODE=$(jq -er '.node_id' /etc/devfleet/node-identity.json)
[[ $(jq -r '.deployment_id' "$PAYLOAD") == "$CURRENT_DEPLOYMENT" && $(jq -r '.node_id' "$PAYLOAD") == "$CURRENT_NODE" ]] || {
  echo 'compute identity does not match secret rotation inventory' >&2
  exit 3
}

install -d -o root -g root -m 0700 "$RECOVERY"
[[ -e "$RECOVERY/committed" ]] && { echo 'secret generation was already committed' >&2; exit 3; }
install -o root -g root -m 0600 /etc/devfleet/secrets.env "$RECOVERY/secrets.env"
install -o root -g root -m 0600 /etc/devfleet/config.json "$RECOVERY/config.json"
[[ ! -f /etc/devfleet/restic.env ]] || install -o root -g root -m 0600 /etc/devfleet/restic.env "$RECOVERY/restic.env"

python3 - "$PAYLOAD" "$GENERATION" <<'PY'
import grp, json, os, tempfile, sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
generation = sys.argv[2]

def quote(value: str) -> str:
    if any(char in value for char in ('\x00', '\r', '\n')):
        raise SystemExit('secret contains a forbidden control character')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$').replace('`', '\\`') + '"'

env_rows = {
    'DEVFLEET_ADMIN_USER': payload['admin_user'],
    'DEVFLEET_ADMIN_PASSWORD': payload['admin_password'],
    'DEVFLEET_API_TOKEN': payload['api_token'],
}
fd, env_tmp = tempfile.mkstemp(prefix='.secrets.env.', dir='/etc/devfleet')
with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
    stream.write(''.join(f'{key}={quote(str(value))}\n' for key, value in env_rows.items()))
    stream.flush(); os.fsync(stream.fileno())
os.chown(env_tmp, 0, grp.getgrnam('devfleet-control').gr_gid); os.chmod(env_tmp, 0o640)
os.replace(env_tmp, '/etc/devfleet/secrets.env')

config_path = Path('/etc/devfleet/config.json')
config = json.loads(config_path.read_text(encoding='utf-8'))
config['secret_generation'] = generation
if config.get('host_control_enabled'):
    config['host_control_token'] = payload['host_control_token']
fd, config_tmp = tempfile.mkstemp(prefix='.config.', dir='/etc/devfleet')
with os.fdopen(fd, 'w', encoding='utf-8') as stream:
    json.dump(config, stream, separators=(',', ':')); stream.flush(); os.fsync(stream.fileno())
os.chown(config_tmp, 0, grp.getgrnam('devfleet-control').gr_gid); os.chmod(config_tmp, 0o640)
os.replace(config_tmp, config_path)
PY

systemctl restart devfleet.service
systemctl is-active --quiet devfleet.service
python3 - "$PAYLOAD" <<'PY'
import json, urllib.request, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
config = json.loads(Path('/etc/devfleet/config.json').read_text(encoding='utf-8'))
request = urllib.request.Request(
    f"http://127.0.0.1:{int(config['portal_port'])}/api/status",
    headers={'X-DevFleet-Token': payload['api_token']},
)
with urllib.request.urlopen(request, timeout=5) as response:
    if response.status != 200: raise SystemExit('rotated API credential was rejected')
PY
touch "$RECOVERY/verified"
printf '{"ok":true,"verified":true,"generation":"%s"}\n' "$GENERATION"

```


## FILE: source/linux/devfleet-rotate-vault-secrets

SHA256: 31cffd4c26ea1fd3e50ca108f7dced492159e5504673a17b6b7c0a624f347724 | Bytes: 4429 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'vault secret rotation requires root' >&2; exit 2; }
MODE=${1:-apply}
GENERATION=${2:-}
[[ $GENERATION =~ ^[0-9a-fA-F-]{36}$ ]] || { echo 'invalid secret generation' >&2; exit 2; }
RECOVERY="/var/lib/devfleet/secret-recovery/$GENERATION/vault"

if [[ $MODE == rollback ]]; then
  [[ -d $RECOVERY && ! -L $RECOVERY ]] || { echo 'vault recovery state is unavailable' >&2; exit 3; }
  install -o root -g resticvault -m 0640 "$RECOVERY/htpasswd" /etc/rest-server/htpasswd
  install -o root -g root -m 0600 "$RECOVERY/vault-admin.env" /etc/rest-server/vault-admin.env
  install -o root -g root -m 0600 "$RECOVERY/vault-public.json" /etc/devfleet-vault-public.json
  systemctl restart rest-server.service
  systemctl is-active --quiet rest-server.service
  printf '{"ok":true,"rolled_back":true,"generation":"%s"}\n' "$GENERATION"
  exit 0
fi
[[ $MODE == apply ]] || { echo 'mode must be apply or rollback' >&2; exit 2; }

PAYLOAD=$(mktemp /run/devfleet-vault-secret-rotation.XXXXXX)
trap 'rm -f -- "$PAYLOAD"' EXIT
chmod 0600 "$PAYLOAD"
cat >"$PAYLOAD"
jq -e --arg generation "$GENERATION" '
  .schema_version == 1 and .secret_generation == $generation and
  (.deployment_id|type == "string" and test("^[0-9a-fA-F-]{36}$")) and
  (.node_id|type == "string" and test("^[0-9a-fA-F-]{36}$")) and
  (.cluster|type == "string" and test("^[A-Za-z0-9._-]+$")) and
  (.rest_user|type == "string" and test("^[A-Za-z0-9._-]+$")) and
  (.rest_password|type == "string" and length >= 40) and
  (.restic_password|type == "string" and length >= 40)
' "$PAYLOAD" >/dev/null || { echo 'invalid vault secret rotation payload' >&2; exit 2; }
[[ $(jq -er '.cluster' /etc/devfleet-vault-public.json) == $(jq -r '.cluster' "$PAYLOAD") ]] || { echo 'vault cluster identity mismatch' >&2; exit 3; }
[[ $(jq -er '.deployment_id' /etc/devfleet-vault-identity.json) == $(jq -r '.deployment_id' "$PAYLOAD") && $(jq -er '.node_id' /etc/devfleet-vault-identity.json) == $(jq -r '.node_id' "$PAYLOAD") ]] || { echo 'vault immutable identity mismatch' >&2; exit 3; }

install -d -o root -g root -m 0700 "$RECOVERY"
[[ -e "$RECOVERY/committed" ]] && { echo 'secret generation was already committed' >&2; exit 3; }
install -o root -g root -m 0600 /etc/rest-server/htpasswd "$RECOVERY/htpasswd"
install -o root -g root -m 0600 /etc/rest-server/vault-admin.env "$RECOVERY/vault-admin.env"
install -o root -g root -m 0600 /etc/devfleet-vault-public.json "$RECOVERY/vault-public.json"
REST_USER=$(jq -r '.rest_user' "$PAYLOAD")
REST_PASSWORD=$(jq -r '.rest_password' "$PAYLOAD")
printf '%s\n' "$REST_PASSWORD" | htpasswd -iB /etc/rest-server/htpasswd "$REST_USER" >/dev/null
chown root:resticvault /etc/rest-server/htpasswd; chmod 0640 /etc/rest-server/htpasswd

python3 - "$PAYLOAD" <<'PY'
import json, os, tempfile, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
def quote(value: str) -> str:
    if any(c in value for c in ('\x00', '\r', '\n')): raise SystemExit('secret contains a forbidden control character')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
repository = f"/srv/restic/{payload['rest_user']}/{payload['cluster']}"
fd, temporary = tempfile.mkstemp(prefix='.vault-admin.', dir='/etc/rest-server')
with os.fdopen(fd, 'w', encoding='utf-8') as stream:
    stream.write('RESTIC_REPOSITORY=' + quote(repository) + '\n')
    stream.write('RESTIC_PASSWORD=' + quote(payload['restic_password']) + '\n')
    stream.flush(); os.fsync(stream.fileno())
os.chmod(temporary, 0o600); os.replace(temporary, '/etc/rest-server/vault-admin.env')

public_path = Path('/etc/devfleet-vault-public.json')
public = json.loads(public_path.read_text(encoding='utf-8'))
public['user'] = payload['rest_user']; public['secret_generation'] = payload['secret_generation']
fd, temporary = tempfile.mkstemp(prefix='.vault-public.', dir='/etc')
with os.fdopen(fd, 'w', encoding='utf-8') as stream:
    json.dump(public, stream, separators=(',', ':')); stream.flush(); os.fsync(stream.fileno())
os.chmod(temporary, 0o600); os.replace(temporary, public_path)
PY

systemctl restart rest-server.service
systemctl is-active --quiet rest-server.service
printf '%s\n' "$REST_PASSWORD" | htpasswd -iv /etc/rest-server/htpasswd "$REST_USER" >/dev/null
touch "$RECOVERY/verified"
printf '{"ok":true,"verified":true,"generation":"%s"}\n' "$GENERATION"

```


## FILE: source/linux/devfleet-safe-update

SHA256: 4a64a44a1d8a921bdededc65b093541ebd7c613430b414e0ea0445af4c04a7a6 | Bytes: 573 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
systemctl restart tailscaled || true
mode=$(jq -r '.docker_mode // "rootless"' /etc/devfleet/config.json)
if [[ $mode == rootless ]]; then
  uid=$(id -u devrunner)
  sudo -u devrunner XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user restart docker
else
  # rootful Docker inside the disposable VM
  systemctl restart containerd docker
fi
systemctl restart devfleet
systemctl restart devfleet-backup.timer

```


## FILE: source/linux/devfleet-set-peer

SHA256: 502799d1a0beca07f2605b1b767aaf8babc938c8e55f6d8af0ff4827b08fa830 | Bytes: 462 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
src=${1:?peer json required}
cleanup(){ if [[ "$src" == /tmp/* ]]; then rm -f -- "$src"; fi; }
trap cleanup EXIT
jq -e '.Name and .Url and .Token' "$src" >/dev/null
url=$(jq -r .Url "$src")
[[ "$url" =~ ^http://100\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]] || { echo 'Peer URL must use a Tailscale IPv4 address.' >&2; exit 2; }
install -o root -g devfleet-control -m 0640 "$src" /etc/devfleet/peer.json
systemctl restart devfleet

```


## FILE: source/linux/devfleet-switch-docker-mode

SHA256: 6773950522775354abe07a698c24bdce8b7f73b458e5963e308e8b64f44cf056 | Bytes: 1849 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Run as root.' >&2; exit 2; }
target=${1:-};ack=${2:-};[[ $target =~ ^(rootless|rootful)$ ]] || { echo 'Usage: devfleet-switch-docker-mode rootless|rootful [--acknowledge-rootful]' >&2; exit 2; };[[ $target != rootful || $ack == --acknowledge-rootful ]] || { echo 'Enabling rootful Docker requires --acknowledge-rootful.' >&2; exit 2; }
cfg=/etc/devfleet/config.json;current=$(jq -r '.docker_mode // "rootless"' "$cfg");[[ $current != "$target" ]] || { echo "Already $target";exit 0; };uid=$(id -u devrunner)
if [[ $current == rootless ]];then running=$(sudo -u devrunner env DOCKER_HOST="unix:///run/user/$uid/docker.sock" docker ps -q 2>/dev/null|wc -l);else running=$(docker ps -q 2>/dev/null|wc -l);fi
((running==0)) || { echo 'Stop all projects before switching Docker stores.' >&2;exit 3; };stamp=$(date -u +%Y%m%dT%H%M%SZ);report="/var/lib/devfleet/migrations/docker-mode-$stamp.txt";/usr/local/bin/devfleet-docker-mode-report >"$report"
if [[ $target == rootless ]];then systemctl disable --now docker.service docker.socket containerd.service 2>/dev/null||true;sudo -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user enable --now docker;else sudo -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user disable --now docker 2>/dev/null||true;systemctl enable --now containerd.service docker.socket docker.service;fi
tmp=$(mktemp);jq --arg mode "$target" '.docker_mode=$mode' "$cfg">"$tmp";install -m 0640 -o root -g devrunner "$tmp" "$cfg";rm -f "$tmp";systemctl restart devfleet.service;echo "Docker mode switched to $target. Stores were not migrated or deleted. Report: $report"

```


## FILE: source/linux/devfleet-user-repair

SHA256: eb6f98d1459e8fdae8b0bc3f7c8ba7d0164ce964a86d9d8c7277f936430c6e5a | Bytes: 455 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
mode=$(jq -r '.docker_mode // "rootless"' /etc/devfleet/config.json)
if [[ $mode == rootless ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  systemctl --user restart docker
else
  docker info >/dev/null || { echo 'Rootful Docker requires the Windows administrator Repair-DevFleet shortcut.' >&2; exit 3; }
fi
/usr/local/bin/devfleet-health

```


## FILE: source/linux/devfleet-vault-broker

SHA256: fcdfdcd5762286fafa0b2ce8a14353f9bf404717472515a8d43efa4f3e3a54b9 | Bytes: 11277 | Git mode: 100644

```
#!/usr/bin/env python3
"""Socket-activated, least-privilege broker for fixed Vault operations."""

from __future__ import annotations

import json
import os
import pwd
import re
import signal
import socket
import struct
import subprocess
from pathlib import Path


MAX_REQUEST_BYTES = 4096
MAX_RESPONSE_BYTES = 16384
REQUEST_TIMEOUT_SECONDS = 10
PROJECT_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{1,62}$")
PROJECT_ID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
HOST_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$")
WORKSPACES = Path("/home/devrunner/workspaces")
SAFE_ENV = {
    "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "LANG": "C.UTF-8",
}


class ProtocolError(ValueError):
    pass


def _receive_frame(connection: socket.socket) -> dict[str, object]:
    connection.settimeout(REQUEST_TIMEOUT_SECONDS)
    header = b""
    while len(header) < 4:
        chunk = connection.recv(4 - len(header))
        if not chunk:
            raise ProtocolError("Request frame is incomplete.")
        header += chunk
    (length,) = struct.unpack("!I", header)
    if length < 2 or length > MAX_REQUEST_BYTES:
        raise ProtocolError("Request frame length is invalid.")
    body = b""
    while len(body) < length:
        chunk = connection.recv(length - len(body))
        if not chunk:
            raise ProtocolError("Request frame body is incomplete.")
        body += chunk
    if connection.recv(1):
        raise ProtocolError("Only one request frame is accepted.")
    try:
        value = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProtocolError("Request frame is not valid JSON.") from exc
    if not isinstance(value, dict):
        raise ProtocolError("Request must be a JSON object.")
    return value


def _send_frame(connection: socket.socket, value: dict[str, object]) -> None:
    encoded = json.dumps(value, separators=(",", ":"), sort_keys=True).encode("utf-8")
    if len(encoded) > MAX_RESPONSE_BYTES:
        encoded = b'{"error":"Broker response exceeded its bound.","ok":false}'
    connection.sendall(struct.pack("!I", len(encoded)) + encoded)


def _assert_peer(connection: socket.socket) -> None:
    size = struct.calcsize("3i")
    _pid, uid, _gid = struct.unpack(
        "3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, size)
    )
    expected_uid = pwd.getpwnam("devfleet-control").pw_uid
    if uid != expected_uid:
        raise ProtocolError("Peer identity is not authorized.")


def _parse_request(value: dict[str, object]) -> tuple[str, str, str, str, str]:
    action = value.get("action")
    if action == "backup" and set(value) == {"action"}:
        return "backup", "", "", "", ""
    if action == "restore-copy" and set(value) == {
        "action",
        "project",
        "project_id",
    }:
        project = value.get("project")
        if not isinstance(project, str) or not PROJECT_RE.fullmatch(project):
            raise ProtocolError("Project identity is invalid.")
        project_id = value.get("project_id")
        if not isinstance(project_id, str) or not PROJECT_ID_RE.fullmatch(project_id):
            raise ProtocolError("Project ID is invalid.")
        return str(action), project, project_id, "", ""
    if action == "restore-transfer" and set(value) == {
        "action",
        "project",
        "project_id",
        "deployment_id",
        "source_host_id",
    }:
        project = value.get("project")
        project_id = value.get("project_id")
        deployment_id = value.get("deployment_id")
        source_host_id = value.get("source_host_id")
        if not isinstance(project, str) or not PROJECT_RE.fullmatch(project):
            raise ProtocolError("Project identity is invalid.")
        if not isinstance(project_id, str) or not PROJECT_ID_RE.fullmatch(project_id):
            raise ProtocolError("Project ID is invalid.")
        if not isinstance(deployment_id, str) or not PROJECT_ID_RE.fullmatch(deployment_id):
            raise ProtocolError("Deployment ID is invalid.")
        if not isinstance(source_host_id, str) or not HOST_ID_RE.fullmatch(source_host_id):
            raise ProtocolError("Source host identity is invalid.")
        return str(action), project, project_id, deployment_id, source_host_id
    raise ProtocolError("Requested Vault operation is not allowed.")


def _recovered_prefix(project: str) -> str:
    return f"{project[:28]}-recovered-"


def _quarantine_invalid_copy(target: Path, project: str) -> bool:
    """Move only an exact generated recovery target out of the workspace root."""
    if target.parent != WORKSPACES or target.is_symlink() or not target.is_dir():
        return False
    if re.fullmatch(re.escape(_recovered_prefix(project)) + r"[0-9]{8}-[0-9]{6}-[0-9a-f]{8}", target.name) is None:
        return False
    quarantine = Path("/home/devrunner/.devfleet-quarantine")
    destination = quarantine / f"vault-broker-invalid-{target.name}"
    if destination.exists() or destination.is_symlink():
        return False
    try:
        quarantine.mkdir(parents=True, exist_ok=True)
        os.rename(target, destination)
        return not target.exists() and destination.is_dir() and not destination.is_symlink()
    except OSError:
        return False


def _run_child(command: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    process = subprocess.Popen(
        command,
        env=SAFE_ENV,
        start_new_session=True,
        stderr=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
        return subprocess.CompletedProcess(command, 124, "", "")
    return subprocess.CompletedProcess(command, int(process.returncode), stdout, stderr)


def _restored_identity_matches(
    target: Path,
    project: str,
    project_id: str,
    deployment_id: str = "",
    source_host_id: str = "",
) -> bool:
    command = ["python3", "-I", "/opt/devfleet/devfleet/metadata_io.py", "--identity",
               str(target), project, project_id]
    if deployment_id or source_host_id:
        if not deployment_id or not source_host_id:
            return False
        command.extend([deployment_id, source_host_id])
    try:
        result = subprocess.run(command, env=SAFE_ENV, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                timeout=REQUEST_TIMEOUT_SECONDS, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def _run_fixed_operation(
    action: str,
    project: str,
    project_id: str,
    deployment_id: str = "",
    source_host_id: str = "",
) -> dict[str, object]:
    if action not in {"backup", "restore-copy", "restore-transfer"}:
        return {"ok": False, "error": "Vault restore action is unsupported.", "exit_code": 2}
    if not os.access("/etc/devfleet/restic.env", os.R_OK):
        return {"ok": False, "error": "Vault backup is not configured.", "exit_code": 3}
    if action == "backup":
        command = ["/usr/local/bin/devfleet-backup"]
        timeout = 1800
    else:
        command = ["/usr/local/bin/devfleet-restore-project", project, project_id]
        if action == "restore-transfer":
            command.extend(["transfer-copy", deployment_id, source_host_id])
        timeout = 3600
    completed = _run_child(command, timeout)
    if completed.returncode:
        if completed.returncode == 124:
            error, error_code = "Vault operation timed out.", "vault-operation-timeout"
        elif completed.returncode == 75:
            error, error_code = "Another Vault operation is already in progress.", "vault-operation-busy"
        elif completed.returncode == 5 and action.startswith("restore-"):
            error, error_code = "Vault restore failed its safety checks.", "restore-safety-conflict"
        else:
            error, error_code = "Vault operation failed.", "vault-operation-failed"
        return {
            "ok": False,
            "error": error,
            "error_code": error_code,
            "exit_code": int(completed.returncode),
        }
    if action == "backup":
        # The root-owned fixed child is authoritative: it exits nonzero whenever
        # restic fails.  latest.json remains dashboard telemetry and is deliberately
        # not an authorization receipt because devfleet-control can write it.
        return {
            "ok": True,
            "action": action,
            "local_backup_status": "verified",
            "vault_upload_status": "verified",
            "durability_level": "vault",
        }
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        return {"ok": False, "error": "Vault restore receipt is invalid.", "exit_code": 5}
    target = Path(lines[0])
    if action in {"restore-copy", "restore-transfer"}:
        expected_name = re.fullmatch(
            re.escape(_recovered_prefix(project)) + r"[0-9]{8}-[0-9]{6}-[0-9a-f]{8}",
            target.name,
        )
        valid_target = target.parent == WORKSPACES and expected_name is not None
    else:
        return {"ok": False, "error": "Vault restore action is unsupported.", "exit_code": 2}
    if (
        not valid_target
        or not target.is_dir()
        or target.is_symlink()
        or not _restored_identity_matches(target, project, project_id, deployment_id, source_host_id)
    ):
        if action in {"restore-copy", "restore-transfer"}:
            _quarantine_invalid_copy(target, project)
        return {"ok": False, "error": "Vault restore target is invalid.", "exit_code": 5}
    receipt = {
        "ok": True,
        "action": action,
        "project": project,
        "project_id": project_id,
        "target": str(target),
    }
    if action == "restore-transfer":
        receipt["deployment_id"] = deployment_id
        receipt["source_host_id"] = source_host_id
    return receipt


def main() -> int:
    connection = socket.socket(fileno=os.dup(0))
    try:
        try:
            _assert_peer(connection)
            request = _receive_frame(connection)
            action, project, project_id, deployment_id, source_host_id = _parse_request(request)
            response = _run_fixed_operation(
                action, project, project_id, deployment_id, source_host_id
            )
        except (ProtocolError, OSError, KeyError) as exc:
            response = {"ok": False, "error": str(exc), "exit_code": 2}
        _send_frame(connection, response)
        return 0
    finally:
        connection.close()


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/linux/devfleet-vault-health

SHA256: aef4f5a6daa89f7a2e669a1e773e32e358801c242458b4a36da0e02769114763 | Bytes: 349 | Git mode: 100644

```
#!/usr/bin/env bash
set -u
printf 'Vault: '; hostname
printf 'Tailscale: '; tailscale status --json --peers=false 2>/dev/null | jq -r '.BackendState // "not-connected"' || true
printf 'rest-server: '; systemctl is-active rest-server
printf 'Disk: '; df -h /srv/restic | tail -n1
printf 'Repository bytes: '; du -sh /srv/restic 2>/dev/null | cut -f1

```


## FILE: source/linux/devfleet-vault-maintenance

SHA256: bd9c01d8bf3ae54bbeba5f37b23d7dedc7e0a4a0778559d9c388f1b085e0c073 | Bytes: 408 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
keep=${1:-90d}
[[ "$keep" =~ ^[0-9]+[dmy]$ ]] || { echo invalid retention >&2; exit 2; }
set -a; source /etc/rest-server/vault-admin.env; set +a
systemctl stop rest-server
trap 'systemctl start rest-server' EXIT
if [[ -d "$RESTIC_REPOSITORY" ]]; then
  restic forget --keep-within "$keep" --prune
  restic check
else
  echo 'No repository has been initialized yet.'
fi

```


## FILE: source/linux/devfleet-vault-request

SHA256: 245458f58ef1a87ffd19abe2d6e3112e812d9b4ca6151158658be5f32b563fbb | Bytes: 4720 | Git mode: 100644

```
#!/usr/bin/env python3
"""Bounded client for the DevFleet Vault broker."""

from __future__ import annotations

import json
import re
import socket
import struct
import sys


SOCKET_PATH = "/run/devfleet-vault-broker.sock"
MAX_REQUEST_BYTES = 4096
MAX_RESPONSE_BYTES = 16384
PROJECT_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{1,62}$")
PROJECT_ID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
HOST_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$")
SAFE_FAILURE_CODES = frozenset(
    {
        "restore-safety-conflict",
        "vault-operation-busy",
        "vault-operation-failed",
        "vault-operation-timeout",
    }
)


def _request_from_argv(argv: list[str]) -> dict[str, str]:
    if argv == ["backup"]:
        return {"action": "backup"}
    if len(argv) == 3 and argv[0] == "restore-copy":
        if not PROJECT_RE.fullmatch(argv[1]):
            raise ValueError("Project identity is invalid.")
        if not PROJECT_ID_RE.fullmatch(argv[2]):
            raise ValueError("Project ID is invalid.")
        return {"action": argv[0], "project": argv[1], "project_id": argv[2]}
    if len(argv) == 5 and argv[0] == "restore-transfer":
        if not PROJECT_RE.fullmatch(argv[1]):
            raise ValueError("Project identity is invalid.")
        if not PROJECT_ID_RE.fullmatch(argv[2]):
            raise ValueError("Project ID is invalid.")
        if not PROJECT_ID_RE.fullmatch(argv[3]):
            raise ValueError("Deployment ID is invalid.")
        if not HOST_ID_RE.fullmatch(argv[4]):
            raise ValueError("Source host identity is invalid.")
        return {
            "action": "restore-transfer",
            "project": argv[1],
            "project_id": argv[2],
            "deployment_id": argv[3],
            "source_host_id": argv[4],
        }
    raise ValueError(
        "Usage: devfleet-vault-request backup | restore-copy PROJECT PROJECT_ID | restore-transfer PROJECT PROJECT_ID "
        "DEPLOYMENT_ID SOURCE_HOST_ID"
    )


def _receive_exact(connection: socket.socket, count: int) -> bytes:
    value = b""
    while len(value) < count:
        chunk = connection.recv(count - len(value))
        if not chunk:
            raise RuntimeError("Vault broker response ended early.")
        value += chunk
    return value


def main(argv: list[str]) -> int:
    try:
        request = _request_from_argv(argv)
        encoded = json.dumps(request, separators=(",", ":"), sort_keys=True).encode("utf-8")
        if len(encoded) > MAX_REQUEST_BYTES:
            raise ValueError("Vault broker request exceeded its bound.")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(5)
            connection.connect(SOCKET_PATH)
            # The fixed child owns at most 3600 seconds, then the broker and its
            # service get bounded cleanup time before this client can time out.
            connection.settimeout(3690)
            connection.sendall(struct.pack("!I", len(encoded)) + encoded)
            connection.shutdown(socket.SHUT_WR)
            (length,) = struct.unpack("!I", _receive_exact(connection, 4))
            if length < 2 or length > MAX_RESPONSE_BYTES:
                raise RuntimeError("Vault broker response length is invalid.")
            response_bytes = _receive_exact(connection, length)
            if connection.recv(1):
                raise RuntimeError("Vault broker sent more than one response frame.")
        response = json.loads(response_bytes.decode("utf-8"))
        if not isinstance(response, dict) or response.get("ok") is not True:
            detail = response.get("error") if isinstance(response, dict) else "Invalid broker response."
            error_code = response.get("error_code") if isinstance(response, dict) else None
            exit_code = response.get("exit_code") if isinstance(response, dict) else None
            if (
                error_code in SAFE_FAILURE_CODES
                and isinstance(exit_code, int)
                and not isinstance(exit_code, bool)
                and -255 <= exit_code <= 255
                and exit_code != 0
            ):
                detail = f"{detail} [error_code={error_code}; exit_code={exit_code}]"
            print(str(detail or "Vault broker rejected the operation."), file=sys.stderr)
            return 1
        print(json.dumps(response, separators=(",", ":"), sort_keys=True))
        return 0
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

```


## FILE: source/linux/upgrade-compute.sh

SHA256: f754f18cf80416026dea3f0a0b37772b419751aaec0198fd914c1ab87d8b5aec | Bytes: 97 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
sudo bash "${1:?payload}/linux/bootstrap-compute.sh" "$1"

```


## FILE: source/pytest.ini

SHA256: 6a96ba0e2d5a8296fb90f474da9d2f0173d3e41eba18965513f711104155f913 | Bytes: 41 | Git mode: 100644

```
[pytest]
testpaths = tests
addopts = -ra

```


## FILE: source/templates/cpp-cmake/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/cpp-cmake/.ai-bridge/codexpro-project-instructions.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/cpp-cmake/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/cpp-cmake/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/cpp-cmake/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/cpp-cmake/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/cpp-cmake/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/cpp-cmake/.devcontainer/devcontainer.json

SHA256: 445934f639925a25401e37333f549c7f1a0cb1cbd7521b7ee6309da00f64e622 | Bytes: 209 | Git mode: 100644

```
{
  "name": "__PROJECT_NAME__",
  "dockerComposeFile": "../compose.yaml",
  "service": "dev",
  "workspaceFolder": "/workspaces/__PROJECT_SLUG__",
  "shutdownAction": "stopCompose",
  "remoteUser": "vscode"
}

```


## FILE: source/templates/cpp-cmake/.devfleet/bootstrap.sh

SHA256: 0c27aca8e0c1121a29c7384e5a262913033dc1db108cdac32a119ebce92b203a | Bytes: 116 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
echo "Preview template: install dependencies inside this project container."

```


## FILE: source/templates/cpp-cmake/.devfleet/codexpro-bootstrap.sh

SHA256: 18459cba289cd6d0dd94081388234128aff3b7ac8e3609488569764af30ede0b | Bytes: 2254 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
root=$(pwd -P)
workspace_root=${DEVFLEET_WORKSPACES_ROOT:-/workspaces}
[[ "$workspace_root" == /* && "$workspace_root" != */ ]] || { echo 'DEVFLEET_WORKSPACES_ROOT must be an absolute directory.' >&2; exit 2; }
[[ "$root" == "$workspace_root"/* ]] || { echo "CodexPro root must be under $workspace_root." >&2; exit 2; }
project_rel=${root#"$workspace_root"/}
[[ "$project_rel" != */* && -n "$project_rel" ]] || { echo 'CodexPro root must identify one project.' >&2; exit 2; }
runtime="$root/.devfleet/runtime"; bridge="$root/.ai-bridge/local-agent"; mkdir -p "$runtime" "$bridge/logs"
log="$runtime/codexpro-bootstrap.log"; status="$runtime/codexpro-status.json"; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
health_url=${DEVFLEET_CODEXPRO_HEALTH_URL:-http://127.0.0.1:8787/healthz}
write_status(){ python3 - "$status" "$1" "$2" "$now" <<'PY2'
import json,sys
p,state,msg,now=sys.argv[1:];open(p,'w').write(json.dumps({'state':state,'healthy':state=='healthy','message':msg,'updated_at':now},indent=2)+'\n')
PY2
}
if DEVFLEET_CODEXPRO_HEALTH_URL="$health_url" python3 - <<'PY2' >/dev/null 2>&1
import urllib.request
import os
urllib.request.urlopen(os.environ['DEVFLEET_CODEXPRO_HEALTH_URL'],timeout=2)
PY2
then write_status healthy 'CodexPro loopback health endpoint is responding.'; echo 'CodexPro is already healthy.' | tee -a "$log"; exit 0; fi
if ! command -v codexpro >/dev/null 2>&1; then write_status unavailable 'CodexPro executable is not installed in this project container.'; echo 'CodexPro is unavailable. Install it using your verified private/local installation source, then rerun this hook. No credential is embedded.' | tee -a "$log"; exit 0; fi
export CODEXPRO_TOOL_CARDS=${CODEXPRO_TOOL_CARDS:-1}
( codexpro start >>"$log" 2>&1 & )
sleep 2
if DEVFLEET_CODEXPRO_HEALTH_URL="$health_url" python3 - <<'PY2' >/dev/null 2>&1
import urllib.request
import os
urllib.request.urlopen(os.environ['DEVFLEET_CODEXPRO_HEALTH_URL'],timeout=2)
PY2
then write_status healthy 'CodexPro started successfully.'; exit 0; fi
write_status authorization-required 'CodexPro is installed but not healthy; inspect the log for authorization or configuration requirements.'
echo "CodexPro did not become healthy. Review $log"; exit 0

```


## FILE: source/templates/cpp-cmake/.devfleet/codexpro-