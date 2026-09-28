# DevFleet source part 083

Full-source UTF-8 byte interval [3813000, 3859500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2fdafeaffb10dae47715ff21367770a80d92af13d08f44743b7c0e91d39eb26d

<!-- BEGIN SOURCE SLICE -->
$DOCKER_MODE =~ ^(rootless|rootful)$ ]] || fail_input 'invalid Docker mode'
[[ $PORT =~ ^[0-9]+$ && $PORT -ge 1024 && $PORT -le 65535 ]] || fail_input 'invalid portal port'
[[ $BACKUP_INTERVAL =~ ^[0-9]+$ && $BACKUP_INTERVAL -ge 1 && $BACKUP_INTERVAL -le 10080 ]] || fail_input 'invalid backup interval'
for value_name in NODE_NAME NODE_ROLE FRIENDLY_NAME ADMIN_USER ADMIN_PASSWORD API_TOKEN DEPLOYMENT_ID NODE_ID COORDINATOR_NODE_ID OLLAMA_BASE OLLAMA_MODEL OLLAMA_PROFILE; do
  value=${!value_name-}
  [[ $value != *$'\r'* && $value != *$'\n'* ]] || fail_input "invalid newline in $value_name"
done
complete_component

POLICY="$PAYLOAD/linux/dependency-policy.json"
[[ -f "$POLICY" ]] || { echo "missing dependency policy" >&2; exit 4; }
JQ_POLICY() { jq -r "$1" "$POLICY"; }
EXPECTED_TAILSCALE_FPR=$(JQ_POLICY .tailscale.signingKeySha256Fingerprint)
EXPECTED_DOCKER_FPR=$(JQ_POLICY .docker.signingKeySha256Fingerprint)
NODE_MIN_MAJOR=$(JQ_POLICY .node.minimumMajor)
NODE_CLI_VERSION=$(JQ_POLICY .node.devcontainersCliVersion)
NODE_CLI_INTEGRITY=$(JQ_POLICY .node.devcontainersCliIntegrity)
MUTABLE_PATH_CONTRACT="$PAYLOAD/app/systemd/mutable-paths.json"
[[ -f "$MUTABLE_PATH_CONTRACT" ]] || { echo "missing systemd mutable-path contract" >&2; exit 4; }
[[ $(jq -er ".schema_version" "$MUTABLE_PATH_CONTRACT") == 1 ]] || { echo "unsupported systemd mutable-path contract" >&2; exit 4; }
WORKSPACES=$(jq -er ".workspace" "$MUTABLE_PATH_CONTRACT")
QUARANTINE=$(jq -er ".quarantine" "$MUTABLE_PATH_CONTRACT")
TRANSACTION_ROOT=$(jq -er ".transaction_root" "$MUTABLE_PATH_CONTRACT")
for mutable_path in "$WORKSPACES" "$QUARANTINE" "$TRANSACTION_ROOT"; do
  [[ $mutable_path =~ ^/[A-Za-z0-9._/-]+$ && $mutable_path != *//* && $mutable_path != */../* && $mutable_path != */.. ]] || {
    echo "unsafe systemd mutable path contract" >&2
    exit 4
  }
done
[[ $WORKSPACES != "$QUARANTINE" ]] || { echo "systemd mutable paths must be distinct" >&2; exit 4; }
[[ $TRANSACTION_ROOT == "$WORKSPACES/.devfleet-transactions" ]] || { echo "restore transaction root must be a protected workspace sibling" >&2; exit 4; }

begin_component packagePrerequisites 900
apt-get update
apt-get install -y ca-certificates curl gnupg jq unzip acl python3-venv python3-pip uidmap dbus-user-session slirp4netns fuse-overlayfs iptables ufw restic git openssl
install -m 0755 -d /etc/apt/keyrings
. /etc/os-release
ARCH=$(dpkg --print-architecture)
complete_component

begin_component dockerRepositoryAndInstall 1200
DOCKER_KEY=$(mktemp)
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "https://download.docker.com/linux/ubuntu/gpg" -o "$DOCKER_KEY"
OBSERVED_DOCKER_FPR=$(gpg --show-keys --with-colons "$DOCKER_KEY" | awk -F: '$1=="fpr"{print toupper($10);exit}')
[[ "$OBSERVED_DOCKER_FPR" == "$EXPECTED_DOCKER_FPR" ]] || { echo "Docker signing-key identity mismatch" >&2; exit 4; }
gpg --dearmor < "$DOCKER_KEY" > /etc/apt/keyrings/docker.gpg
rm -f "$DOCKER_KEY"
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
complete_component

begin_component tailscaleRepositoryAndInstall 1200
TAILSCALE_KEY=$(mktemp)
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" -o "$TAILSCALE_KEY"
OBSERVED_TAILSCALE_FPR=$(gpg --show-keys --with-colons "$TAILSCALE_KEY" | awk -F: '$1=="pub"{count++;pending=1;next} pending && $1=="fpr"{fingerprint=toupper($10);pending=0} END{if(count!=1 || pending || length(fingerprint)!=40)exit 4;print fingerprint}')
[[ "$OBSERVED_TAILSCALE_FPR" == "$EXPECTED_TAILSCALE_FPR" ]] || { echo "Tailscale signing-key identity mismatch" >&2; exit 4; }
install -m 0644 "$TAILSCALE_KEY" /usr/share/keyrings/tailscale-archive-keyring.gpg
rm -f "$TAILSCALE_KEY"
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu $VERSION_CODENAME main" > /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale
systemctl enable --now tailscaled
complete_component

begin_component rootlessRuntime 600
# Rootless Docker is the default and devrunner must not inherit the
# host-equivalent rootful docker-group privilege.  A deliberate rootful
# deployment requires an explicitly privileged helper/profile outside the
# normal DevFleet service account.
getent passwd devfleet-control >/dev/null || run_bounded useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin devfleet-control
getent passwd devfleet-backup >/dev/null || run_bounded useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin devfleet-backup
# The service group is created by the service-account setup above.  Grant it
# traversal of the root only after that group exists; the bootstrap entrypoint
# must remain runnable on a clean image where the group is not yet present.
run_bounded chown root:devfleet-control /var/lib/devfleet
run_bounded chmod 0750 /var/lib/devfleet
run_bounded usermod --append --groups devrunner devfleet-control
run_bounded gpasswd --delete devrunner sudo >/dev/null 2>&1 || true
rm -f /etc/sudoers.d/devfleet-devrunner
getent group docker >/dev/null || true
run_bounded install -d -o root -g devfleet-control -m 0750 "$WORKSPACES" "$QUARANTINE"
run_bounded install -d -o devfleet-control -g devfleet-control -m 0700 "$TRANSACTION_ROOT"
run_bounded install -d -o devrunner -g devrunner -m 0700 /home/devrunner/.devfleet
run_bounded install -d -o devfleet-control -g devfleet-control -m 0750 /var/lib/devfleet/runtime /var/lib/devfleet/migrations
run_bounded install -d -o devrunner -g devrunner /var/cache/devfleet
run_bounded setfacl -m u:devrunner:rx,u:devfleet-backup:rwx,d:u:devrunner:rwx,d:u:devfleet-backup:rwx "$WORKSPACES" "$QUARANTINE"
# Re-bootstrap must also remove the obsolete broad backup-service grant from
# DevFleet's private control directory.  The backup identity needs traversal of
# /home/devrunner and access to the explicit workspace/quarantine roots only.
run_bounded setfacl -x u:devfleet-backup /home/devrunner/.devfleet 2>/dev/null || true
run_bounded setfacl -x d:u:devfleet-backup /home/devrunner/.devfleet 2>/dev/null || true
run_bounded setfacl -m u:devfleet-control:rwx,d:u:devfleet-control:rwx "$WORKSPACES" "$QUARANTINE"
for d in pip uv npm pnpm maven gradle nuget go-mod go-build cargo-registry cargo-git composer bundler buildkit; do run_bounded install -d -o devrunner -g devrunner "/var/cache/devfleet/$d"; done
grep -q '^devrunner:' /etc/subuid || echo 'devrunner:100000:65536' >> /etc/subuid
grep -q '^devrunner:' /etc/subgid || echo 'devrunner:100000:65536' >> /etc/subgid
run_bounded loginctl enable-linger devrunner
run_bounded systemctl start "user@$(id -u devrunner).service" || true
run_bounded install -d -o devrunner -g devrunner /home/devrunner/.config/environment.d
printf 'PATH=/usr/bin:/bin:/usr/local/bin\n' > /home/devrunner/.config/environment.d/docker.conf
chown -R devrunner:devrunner /home/devrunner/.config /home/devrunner/.devfleet*

uid=$(id -u devrunner)
if [[ ! -f /home/devrunner/.config/systemd/user/docker.service ]]; then
  run_bounded sudo -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus dockerd-rootless-setuptool.sh install --force
fi
DOCKER_ACL_DROP_IN=/home/devrunner/.config/systemd/user/docker.service.d/devfleet-control-acl.conf
run_bounded install -d -o devrunner -g devrunner -m 0755 "$(dirname "$DOCKER_ACL_DROP_IN")"
cat > "$DOCKER_ACL_DROP_IN" <<'EOF'
[Service]
ExecStartPost=/usr/bin/setfacl -m u:devfleet-control:rx %t
ExecStartPost=/usr/bin/setfacl -m u:devfleet-control:rw %t/docker.sock
EOF
run_bounded chown devrunner:devrunner "$DOCKER_ACL_DROP_IN"
run_bounded chmod 0644 "$DOCKER_ACL_DROP_IN"
if [[ $DOCKER_MODE == rootless ]]; then
  systemctl disable --now docker.service docker.socket containerd.service 2>/dev/null || true
  run_bounded sudo -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user daemon-reload
  run_bounded sudo -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user enable --now docker
else
  echo 'Rootful Docker mode requires a separately provisioned privileged helper; bootstrap refuses to grant devrunner docker-group access.' >&2
  exit 5
fi
if [[ -d "/run/user/$uid" ]]; then
  run_bounded setfacl -m u:devfleet-control:rx "/run/user/$uid"
  [[ -S "/run/user/$uid/docker.sock" ]] && run_bounded setfacl -m u:devfleet-control:rw "/run/user/$uid/docker.sock" || true
fi
complete_component

begin_component nodeToolchain 600
if ! command -v node >/dev/null; then apt-get install -y nodejs npm; fi
NODE_MAJOR=$(node --version | sed -E 's/^v([0-9]+).*/\1/')
[[ $NODE_MAJOR =~ ^[0-9]+$ && $NODE_MAJOR -ge $NODE_MIN_MAJOR ]] || { echo "Ubuntu signed Node.js package is below the supported major version." >&2; exit 4; }
NPM_TMP=$(mktemp -d)
npm pack --ignore-scripts --pack-destination "$NPM_TMP" "@devcontainers/cli@$NODE_CLI_VERSION" >/dev/null
NPM_TARBALL=$(find "$NPM_TMP" -maxdepth 1 -type f -name '*.tgz' -print -quit)
NPM_INTEGRITY="sha512-$(openssl dgst -sha512 -binary "$NPM_TARBALL" | base64 -w0)"
[[ "$NPM_INTEGRITY" == "$NODE_CLI_INTEGRITY" ]] || { echo "@devcontainers/cli artifact integrity mismatch" >&2; exit 4; }
npm install --global --ignore-scripts "$NPM_TARBALL"
complete_component

begin_component pythonRuntime 1200
run_bounded rm -rf /opt/devfleet
run_bounded install -d /opt/devfleet
run_bounded cp -a "$PAYLOAD/app/." /opt/devfleet/
run_bounded install -m 0644 "$PAYLOAD/VERSION" /opt/devfleet/VERSION
run_bounded cp -a "$PAYLOAD/templates" /opt/devfleet/project-templates
[[ -f /opt/devfleet/requirements-hashed.txt ]] || { echo "missing hash-bound Python dependency lock" >&2; exit 4; }
run_bounded python3 -m venv /opt/devfleet/venv
run_bounded /opt/devfleet/venv/bin/pip install --timeout 30 --no-deps --require-hashes -r /opt/devfleet/requirements-hashed.txt
VENV_ORIGIN=$(/opt/devfleet/venv/bin/python - <<'PY'
import importlib.metadata as metadata
import sys
from pathlib import Path

prefix = Path(sys.prefix).resolve()
if Path(sys.base_prefix).resolve() == prefix:
    raise SystemExit("DevFleet venv is not isolated from the system interpreter")
for distribution in metadata.distributions():
    location = Path(distribution.locate_file("")).resolve()
    if prefix not in location.parents and location != prefix:
        raise SystemExit(f"runtime distribution escaped the DevFleet venv: {distribution.metadata['Name']}")
print(prefix)
PY
)
[[ "$VENV_ORIGIN" == "/opt/devfleet/venv" ]] || { echo "runtime package origin is outside the DevFleet venv" >&2; exit 4; }
run_bounded chown -R root:root /opt/devfleet
complete_component

begin_component serviceAndFirewallFinalization 600
run_bounded install -d -m 0750 -o root -g devfleet-control /etc/devfleet
run_bounded jq -n --arg schema "2" --arg version "$PACKAGE_VERSION" --arg node "$NODE_NAME" --arg role "$NODE_ROLE" --arg friendly "$FRIENDLY_NAME" --arg deployment "$DEPLOYMENT_ID" --arg id "$NODE_ID" --arg coordinator "$COORDINATOR_NODE_ID" --arg protocol "$PROTOCOL_VERSION" --arg port "$PORT" --arg ollamaBase "$OLLAMA_BASE" --arg ollamaModel "$OLLAMA_MODEL" --arg ollamaProfile "$OLLAMA_PROFILE" --arg profile "$DEVELOPMENT_PROFILE" --arg docker "$DOCKER_MODE" --arg tailnetCidr "100.64.0.0/10" --arg workspaces "$WORKSPACES" --arg quarantine "$QUARANTINE" --argjson shared "$SHARED_CACHES" --argjson analyzer "$ANALYZER_CACHE" --argjson auto "$AUTO_CODEX" --argjson tailnet "$ALLOW_TAILNET" --argjson rebuild "$BACKUP_REBUILD" --argjson quarantineEnabled "$BACKUP_QUARANTINE" --argjson portNumber "$PORT" '{schema_version:($schema|tonumber),package_version:$version,node_name:$node,node_role:$role,friendly_name:$friendly,deployment_id:$deployment,node_id:$id,coordinator_node_id:(if $coordinator == "" then "" else $coordinator end),protocol_version:($protocol|tonumber),portal_port:$portNumber,workspaces:$workspaces,quarantine:$quarantine,peer_file:"/etc/devfleet/peer.json",runtime_root:"/var/lib/devfleet/runtime",cache_root:"/var/cache/devfleet",ollama_base_url:$ollamaBase,ollama_model:$ollamaModel,ollama_profile:$ollamaProfile,development_profile:$profile,docker_mode:$docker,enable_shared_caches:$shared,enable_analyzer_cache:$analyzer,auto_start_codexpro:$auto,allow_tailnet_ports:$tailnet,require_tailscale:true,tailnet_cidr:$tailnetCidr,public_binding_allowed:false,backup_before_rebuild:$rebuild,backup_before_quarantine:$quarantineEnabled}' > /etc/devfleet/config.json
run_bounded jq -n --arg deployment "$DEPLOYMENT_ID" --arg id "$NODE_ID" --arg node "$NODE_NAME" --arg role "$NODE_ROLE" --arg coordinator "$COORDINATOR_NODE_ID" --arg protocol "$PROTOCOL_VERSION" '{schema_version:1,deployment_id:$deployment,node_id:$id,node_name:$node,node_role:$role,coordinator_node_id:$coordinator,protocol_version:($protocol|tonumber),registration_state:(if $role == "primary" then "coordinator" else "awaiting-primary-join" end)}' > /etc/devfleet/node-identity.json
if [[ -n "$DEPLOYMENT_ID" ]]; then
  run_bounded install -d -o devfleet-control -g devfleet-control -m 0750 /var/lib/devfleet/runtime
  run_bounded jq -n --arg deployment "$DEPLOYMENT_ID" --arg id "$NODE_ID" --arg node "$NODE_NAME" --arg friendly "$FRIENDLY_NAME" --arg role "$NODE_ROLE" --arg protocol "$PROTOCOL_VERSION" '{schema_version:1,deployment_id:$deployment,nodes:[{deployment_id:$deployment,node_id:$id,node_name:$node,friendly_name:$friendly,node_role:$role,capabilities:["primary-control","compute","backup"],coordinator_node_id:null,protocol_version:($protocol|tonumber),registration_state:"registered",connectivity:"online"}]}' > /var/lib/devfleet/runtime/node-registry.json
  run_bounded chown devfleet-control:devfleet-control /var/lib/devfleet/runtime/node-registry.json; run_bounded chmod 0640 /var/lib/devfleet/runtime/node-registry.json
fi
SECRETS_ENV_TMP=$(mktemp /etc/devfleet/.secrets.env.XXXXXX)
run_bounded python3 - "$SECRETS_ENV_TMP" "$SECRETS_SOURCE" <<'PY'
import json, sys
from pathlib import Path

def encode(value: str) -> str:
    if any(char in value for char in ('\x00', '\r', '\n')):
        raise SystemExit('secret contains a forbidden control character')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$').replace('`', '\\`') + '"'

rows = {
    'DEVFLEET_ADMIN_USER': '',
    'DEVFLEET_ADMIN_PASSWORD': '',
    'DEVFLEET_API_TOKEN': '',
}
source = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
rows['DEVFLEET_ADMIN_USER'] = str(source.get('AdminUser', ''))
rows['DEVFLEET_ADMIN_PASSWORD'] = str(source.get('AdminPassword', ''))
rows['DEVFLEET_API_TOKEN'] = str(source.get('ApiToken', ''))
target = Path(sys.argv[1])
target.write_text(''.join(f'{key}={encode(value)}\n' for key, value in rows.items()), encoding='utf-8', newline='\n')
target.chmod(0o640)
target.replace('/etc/devfleet/secrets.env')
PY
run_bounded rm -f -- "$SECRETS_SOURCE"
[[ -f /etc/devfleet/peer.json ]] || printf '{}\n' > /etc/devfleet/peer.json
for config_file in /etc/devfleet/*; do
  [[ -e "$config_file" || -L "$config_file" ]] || continue
  [[ "$config_file" == "/etc/devfleet/restic.env" ]] && continue
  [[ -f "$config_file" && ! -L "$config_file" ]] || { echo "Unsafe DevFleet configuration entry: $config_file" >&2; exit 1; }
  run_bounded chown root:devfleet-control -- "$config_file"
  run_bounded chmod 0640 -- "$config_file"
done
# A re-bootstrap must not move existing Vault credentials into the control
# service's group. Preserve the backup-only reader and its directory traverse.
if [[ -e /etc/devfleet/restic.env || -L /etc/devfleet/restic.env ]]; then
  [[ -f /etc/devfleet/restic.env && ! -L /etc/devfleet/restic.env ]] || { echo 'Unsafe restic credential path.' >&2; exit 1; }
  run_bounded chown root:devfleet-backup /etc/devfleet/restic.env
  run_bounded chmod 0640 /etc/devfleet/restic.env
  run_bounded setfacl -m u:devfleet-backup:--x /etc/devfleet
fi
chown root:devfleet-control /etc/devfleet/secrets.env; chmod 0640 /etc/devfleet/secrets.env
for f in devfleet-health devfleet-purge-quarantine devfleet-backup devfleet-restore-project devfleet-user-repair devfleet-docker-mode-report devfleet-vault-request; do run_bounded install -m 0755 "$PAYLOAD/linux/$f" "/usr/local/bin/$f"; done
run_bounded install -o root -g devfleet-backup -m 0750 "$PAYLOAD/linux/devfleet-vault-broker" /usr/local/bin/devfleet-vault-broker
for f in devfleet-repair devfleet-safe-update devfleet-configure-backup devfleet-set-peer devfleet-switch-docker-mode devfleet-register-node devfleet-join-deployment; do run_bounded install -m 0755 "$PAYLOAD/linux/$f" "/usr/local/sbin/$f"; done
run_bounded cp /opt/devfleet/systemd/devfleet.service /etc/systemd/system/devfleet.service
run_bounded sed -i "s|__PORT__|$PORT|g;s|__DEVRUNNER_UID__|$uid|g;s|__WORKSPACES__|$WORKSPACES|g;s|__QUARANTINE__|$QUARANTINE|g;s|__TRANSACTION_ROOT__|$TRANSACTION_ROOT|g" /etc/systemd/system/devfleet.service
run_bounded cp /opt/devfleet/systemd/devfleet-backup.service /etc/systemd/system/
run_bounded sed -i "s|__WORKSPACES__|$WORKSPACES|g;s|__QUARANTINE__|$QUARANTINE|g" /etc/systemd/system/devfleet-backup.service
run_bounded cp /opt/devfleet/systemd/devfleet-backup.timer /etc/systemd/system/
run_bounded sed -i "s/__BACKUP_INTERVAL_MINUTES__/$BACKUP_INTERVAL/g" /etc/systemd/system/devfleet-backup.timer
run_bounded cp /opt/devfleet/systemd/devfleet-vault-broker.socket /etc/systemd/system/
run_bounded cp /opt/devfleet/systemd/devfleet-vault-broker@.service /etc/systemd/system/
run_bounded sed -i "s|__WORKSPACES__|$WORKSPACES|g;s|__QUARANTINE__|$QUARANTINE|g" /etc/systemd/system/devfleet-vault-broker@.service
systemctl daemon-reload; systemctl enable --now devfleet.service devfleet-backup.timer devfleet-vault-broker.socket
# Add only the exact DevFleet-owned rules. Do not change the host's global
# default policy or activate UFW on behalf of an unrelated administrator.
ufw allow in on tailscale0 to any port 22 proto tcp comment 'DevFleet-owned tailscale SSH'
ufw allow in on tailscale0 to any port "$PORT" proto tcp comment 'DevFleet-owned tailscale Portal'
complete_component
write_progress bootstrap COMPLETED
echo "DevFleet compute bootstrap complete: $NODE_NAME ($NODE_ROLE, $DEVELOPMENT_PROFILE, $DOCKER_MODE)"

```


## FILE: source/linux/bootstrap-input.sh

SHA256: 9f91b7f6d75029c4fbe47004e5ba85a11442eb92cbabc053fbb857b78be984ad | Bytes: 1056 | Git mode: 100644

```
#!/usr/bin/env bash

# Capture one JSON document from stdin under the caller's immutable component
# deadline.  The caller owns the resulting file and must install an EXIT trap
# before invoking this function.  Nothing from stdin is written to stdout or
# diagnostics.
devfleet_capture_json_stdin() {
  local template=${1:?secret-file template required}
  local deadline_epoch=${2:?input deadline required}
  local now remaining secret_path rc=0

  [[ "$deadline_epoch" =~ ^[0-9]+$ ]] || return 64
  now=$(date +%s)
  remaining=$((deadline_epoch - now))
  (( remaining > 0 )) || return 124

  secret_path=$(mktemp "$template") || return 73
  chmod 0600 "$secret_path" || { rc=$?; rm -f -- "$secret_path"; return "$rc"; }
  timeout --foreground --kill-after=5s "${remaining}s" cat >"$secret_path" || rc=$?
  if (( rc != 0 )); then
    rm -f -- "$secret_path"
    return "$rc"
  fi
  if [[ ! -s "$secret_path" ]] || ! jq -e 'type == "object"' "$secret_path" >/dev/null 2>&1; then
    rm -f -- "$secret_path"
    return 65
  fi
  printf '%s' "$secret_path"
}

```


## FILE: source/linux/bootstrap-vault.sh

SHA256: 08899264e01566206e13f36f04cffda80991c39bc54babfa75f593ae09e7102c | Bytes: 13198 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
PAYLOAD=${1:?payload path required}
shift
export DEBIAN_FRONTEND=noninteractive
SECRETS_SOURCE=""
SECRETS_STDIN_REQUESTED=0
TRANSACTION_ID="${DEVFLEET_TRANSACTION_ID:-}"
PAYLOAD_SHA256="${DEVFLEET_PAYLOAD_SHA256:-}"
BOOTSTRAP_MAX_SECONDS="${DEVFLEET_BOOTSTRAP_MAX_SECONDS:-3900}"
SECRETS_INPUT_MAX_SECONDS=60
PACKAGE_VERSION=""
NODE_ROLE=""
while (($#)); do
  case "$1" in
    --secrets-stdin) SECRETS_STDIN_REQUESTED=1 ;;
    --transaction-id) TRANSACTION_ID=${2:?transaction id required}; shift ;;
    --payload-sha256) PAYLOAD_SHA256=${2:?payload sha256 required}; shift ;;
    --bootstrap-max-seconds) BOOTSTRAP_MAX_SECONDS=${2:?bootstrap max seconds required}; shift ;;
    --package-version) PACKAGE_VERSION=${2:?package version required}; shift ;;
    --node-role) NODE_ROLE=${2:?node role required}; shift ;;
    *) echo 'Unsupported Vault bootstrap argument.' >&2; exit 64 ;;
  esac
  shift
done

[[ "$SECRETS_STDIN_REQUESTED" -eq 1 && "$TRANSACTION_ID" =~ ^[0-9a-fA-F]{32}$ && "$PAYLOAD_SHA256" =~ ^[0-9a-fA-F]{64}$ && "$BOOTSTRAP_MAX_SECONDS" =~ ^[0-9]+$ && "$BOOTSTRAP_MAX_SECONDS" -gt 0 ]] || { echo 'Vault bootstrap requires bound transaction, payload, stdin, and finite owner deadline.' >&2; exit 64; }
[[ "$PACKAGE_VERSION" == 'vault' && "$NODE_ROLE" == 'vault' ]] || { echo 'Vault bootstrap launch identity is invalid.' >&2; exit 64; }
INPUT_HELPER="$PAYLOAD/linux/bootstrap-input.sh"
[[ -f "$INPUT_HELPER" ]] || { echo 'Missing bootstrap input helper.' >&2; exit 4; }
# shellcheck source=bootstrap-input.sh
source "$INPUT_HELPER"
BOOTSTRAP_STARTED_EPOCH=$(date +%s); BOOTSTRAP_DEADLINE_EPOCH=$((BOOTSTRAP_STARTED_EPOCH + BOOTSTRAP_MAX_SECONDS)); PROGRESS_PATH=/var/lib/devfleet/bootstrap-progress.json
install -d -o root -g root -m 0750 /var/lib/devfleet; PROGRESS_SEQUENCE=0; CURRENT_COMPONENT=''; COMPONENT_DEADLINE_EPOCH=$BOOTSTRAP_DEADLINE_EPOCH; COMPONENT_TERMINALIZED=0
if [[ -f "$PROGRESS_PATH" ]] && jq -e --arg tx "$TRANSACTION_ID" --arg payload "$PAYLOAD_SHA256" '.transactionId==$tx and .payloadSha256==$payload and (.sequence|numbers)' "$PROGRESS_PATH" >/dev/null 2>&1; then PROGRESS_SEQUENCE=$(jq -r --arg tx "$TRANSACTION_ID" --arg payload "$PAYLOAD_SHA256" 'select(.transactionId==$tx and .payloadSha256==$payload) | .sequence' "$PROGRESS_PATH"); fi
write_progress() { local component=$1 state=$2 tmp now; [[ "$component" =~ ^(secretsInput|packagePrerequisites|restServer|tailscaleChecks|serviceConfiguration|firewallFinalization|bootstrap)$ ]] || return 1; [[ "$state" =~ ^(STARTED|COMPLETED|FAILED|TIMED_OUT)$ ]] || return 1; PROGRESS_SEQUENCE=$((PROGRESS_SEQUENCE+1)); now=$(date -u +%Y-%m-%dT%H:%M:%SZ); tmp=$(mktemp /var/lib/devfleet/bootstrap-progress.XXXXXX); jq -n --arg tx "$TRANSACTION_ID" --arg payload "$PAYLOAD_SHA256" --arg component "$component" --arg state "$state" --arg now "$now" --arg version "$PACKAGE_VERSION" --arg role "$NODE_ROLE" --argjson sequence "$PROGRESS_SEQUENCE" '{schemaVersion:1,transactionId:$tx,payloadSha256:$payload,sequence:$sequence,component:$component,state:$state,updatedUtc:$now,packageVersion:$version,nodeRole:$role}' > "$tmp"; chown root:root "$tmp"; chmod 0640 "$tmp"; sync -d "$tmp" 2>/dev/null || true; mv -f -- "$tmp" "$PROGRESS_PATH"; chown root:root "$PROGRESS_PATH"; chmod 0640 "$PROGRESS_PATH"; }
remaining_seconds() { echo $((COMPONENT_DEADLINE_EPOCH - $(date +%s))); }
run_bounded() { local remaining rc=0; remaining=$(remaining_seconds); if (( remaining <= 0 )); then write_progress "$CURRENT_COMPONENT" TIMED_OUT || true; COMPONENT_TERMINALIZED=1; return 124; fi; timeout --foreground --kill-after=10s "${remaining}s" "$@" || rc=$?; if (( rc == 124 || rc == 137 )); then write_progress "$CURRENT_COMPONENT" TIMED_OUT || true; COMPONENT_TERMINALIZED=1; fi; return "$rc"; }
run_bounded_command() { local command=$1; shift; local remaining; remaining=$(remaining_seconds); if [[ "$command" == "/usr/bin/apt-get" ]]; then set -- -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=2 "$@"; fi; if [[ "$command" == "/usr/bin/curl" ]]; then set -- --connect-timeout 20 --max-time "$remaining" "$@"; fi; run_bounded "$command" "$@"; }
apt-get() { run_bounded_command /usr/bin/apt-get "$@"; }; curl() { run_bounded_command /usr/bin/curl "$@"; }; systemctl() { run_bounded_command /usr/bin/systemctl "$@"; }; ufw() { run_bounded_command /usr/sbin/ufw "$@"; }
begin_component() { CURRENT_COMPONENT=$1; COMPONENT_TERMINALIZED=0; local max=$2 now; now=$(date +%s); COMPONENT_DEADLINE_EPOCH=$((now+max)); if (( COMPONENT_DEADLINE_EPOCH > BOOTSTRAP_DEADLINE_EPOCH )); then COMPONENT_DEADLINE_EPOCH=$BOOTSTRAP_DEADLINE_EPOCH; fi; write_progress "$CURRENT_COMPONENT" STARTED; }
complete_component() { write_progress "$CURRENT_COMPONENT" COMPLETED; CURRENT_COMPONENT=''; COMPONENT_TERMINALIZED=0; }
finish_bootstrap() {
  local rc=$? cleanup_rc=0
  trap - ERR EXIT
  rm -f -- "${SECRETS_SOURCE-}" || cleanup_rc=$?
  if (( rc == 0 )); then rc=$cleanup_rc; fi
  if (( rc != 0 )) && [[ ${COMPONENT_TERMINALIZED:-0} -eq 0 ]]; then
    write_progress "${CURRENT_COMPONENT:-bootstrap}" FAILED || true
  fi
  exit "$rc"
}
trap finish_bootstrap EXIT
trap 'exit $?' ERR
begin_component secretsInput "$SECRETS_INPUT_MAX_SECONDS"
set +e
SECRETS_SOURCE=$(devfleet_capture_json_stdin '/run/devfleet-vault-secrets.XXXXXX' "$COMPONENT_DEADLINE_EPOCH")
input_rc=$?
set -e
if (( input_rc != 0 )); then
  if (( input_rc == 124 || input_rc == 137 )); then write_progress secretsInput TIMED_OUT || true; else write_progress secretsInput FAILED || true; fi
  COMPONENT_TERMINALIZED=1
  echo 'Bounded Vault secret input delivery failed.' >&2
  exit "$input_rc"
fi
SECRETS="$SECRETS_SOURCE"
fail_input() { local message=$1 code=${2:-4}; write_progress secretsInput FAILED || true; COMPONENT_TERMINALIZED=1; echo "$message" >&2; exit "$code"; }
PORT=$(jq -r .VaultPort "$SECRETS")
REST_USER=$(jq -r .RestUser "$SECRETS")
REST_PASSWORD=$(jq -r .RestPassword "$SECRETS")
RESTIC_PASSWORD=$(jq -r .ResticPassword "$SECRETS")
CLUSTER=$(jq -r .ClusterName "$SECRETS")
DEPLOYMENT_ID=$(jq -r .DeploymentId "$SECRETS")
NODE_ID=$(jq -r .NodeId "$SECRETS")
NODE_NAME=$(jq -r .NodeName "$SECRETS")
[[ ( -z $DEPLOYMENT_ID || $DEPLOYMENT_ID =~ ^[0-9a-fA-F-]{36}$ ) && $NODE_ID =~ ^[0-9a-fA-F-]{36}$ && -n $NODE_NAME && $NODE_NAME != 'null' ]] || fail_input 'Vault immutable identity is incomplete.'
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] && (( PORT >= 1 && PORT <= 65535 )) || fail_input 'Vault port is invalid.'
[[ "$REST_USER" =~ ^[A-Za-z0-9._-]+$ ]] || fail_input 'Vault REST user contains unsupported characters.'
[[ "$CLUSTER" =~ ^[A-Za-z0-9._-]+$ ]] || fail_input 'Vault cluster name contains unsupported characters.'
for value_name in REST_PASSWORD RESTIC_PASSWORD DEPLOYMENT_ID NODE_ID NODE_NAME; do value=${!value_name-}; [[ $value != *$'\r'* && $value != *$'\n'* ]] || fail_input "Vault secret input contains an invalid newline in $value_name."; done
complete_component
POLICY="$PAYLOAD/linux/dependency-policy.json"
[[ -f "$POLICY" ]] || { echo 'Missing canonical dependency policy.' >&2; exit 4; }
REST_SERVER_TAG=$(jq -r .restServer.tag "$POLICY")
REST_SERVER_SHA256=$(jq -r .restServer.sha256 "$POLICY")
begin_component packagePrerequisites 900
apt-get update
apt-get install -y curl ca-certificates jq apache2-utils ufw restic
complete_component
begin_component tailscaleChecks 600
if ! command -v tailscale >/dev/null; then echo 'Tailscale must be installed from the verified signed repository before Vault provisioning.' >&2; exit 4; fi
systemctl enable --now tailscaled
TAILSCALE_IP=$(run_bounded tailscale ip -4 2>/dev/null | awk 'NR==1 {print $1}')
[[ "$TAILSCALE_IP" =~ ^100\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] && (( 10#${BASH_REMATCH[1]} >= 64 && 10#${BASH_REMATCH[1]} <= 127 && 10#${BASH_REMATCH[2]} <= 255 && 10#${BASH_REMATCH[3]} <= 255 )) || { echo 'Vault refuses to start without an authenticated Tailscale IPv4 address in 100.64.0.0/10.' >&2; exit 4; }
complete_component

begin_component restServer 1200
# Resolve current rest-server/restic release binaries from the official GitHub API.
install_github_binary(){
  local repo=$1 asset_regex=$2 binary=$3
  local url
  local tag=${REST_SERVER_TAG:?REST_SERVER_TAG must be supplied by the pinned dependency policy}
  local digest=${REST_SERVER_SHA256:?REST_SERVER_SHA256 must be supplied by the pinned dependency policy}
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid pinned release tag" >&2; exit 3; }
  [[ "$digest" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Invalid pinned release digest" >&2; exit 3; }
  local asset="rest-server_${tag#v}_linux_amd64.tar.gz"
  local url="https://github.com/$repo/releases/download/$tag/$asset"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$url" -o "$tmp/pkg"
  printf '%s  %s\n' "$digest" "$tmp/pkg" | sha256sum --check --status || { echo "Pinned digest mismatch for $repo/$asset" >&2; exit 3; }
  tar -C "$tmp" -xzf "$tmp/pkg"; find "$tmp" -type f -name "$binary" -exec install -m 0755 {} "/usr/local/bin/$binary" \; -quit
}
[[ "$REST_SERVER_TAG" != "null" && "$REST_SERVER_SHA256" != "null" ]] || { echo 'Pinned rest-server policy is incomplete.' >&2; exit 4; }
install_github_binary restic/rest-server 'unused' rest-server
complete_component

begin_component serviceConfiguration 600
install -d -o resticvault -g resticvault -m 0700 /srv/restic
install -d -o root -g resticvault -m 0750 /etc/rest-server
install -d -o root -g root -m 0700 /root/.config/devfleet
printf '%s\n' "$REST_PASSWORD" | htpasswd -iBc /etc/rest-server/htpasswd "$REST_USER"
chown root:resticvault /etc/rest-server/htpasswd
chmod 0640 /etc/rest-server/htpasswd
export DEVFLEET_RESTIC_REPOSITORY="/srv/restic/$REST_USER/$CLUSTER"
export DEVFLEET_RESTIC_PASSWORD="$RESTIC_PASSWORD"
run_bounded python3 - <<'PY'
import os

def systemd_quote(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'

with open('/etc/rest-server/vault-admin.env', 'w', encoding='utf-8') as fh:
    fh.write('RESTIC_REPOSITORY=' + systemd_quote(os.environ['DEVFLEET_RESTIC_REPOSITORY']) + '\n')
    fh.write('RESTIC_PASSWORD=' + systemd_quote(os.environ['DEVFLEET_RESTIC_PASSWORD']) + '\n')
PY
chmod 0600 /etc/rest-server/vault-admin.env
cat >/etc/systemd/system/rest-server.service <<EOF
[Unit]
Description=DevFleet append-only restic REST server
After=network-online.target tailscaled.service
Wants=network-online.target
[Service]
User=resticvault
Group=resticvault
ExecStart=/usr/local/bin/rest-server --path /srv/restic --listen $TAILSCALE_IP:$PORT --append-only --private-repos --htpasswd-file /etc/rest-server/htpasswd
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/srv/restic
ProtectHome=true
[Install]
WantedBy=multi-user.target
EOF
install -m 0755 "$PAYLOAD/linux/devfleet-vault-health" /usr/local/sbin/devfleet-vault-health
install -m 0755 "$PAYLOAD/linux/devfleet-vault-maintenance" /usr/local/sbin/devfleet-vault-maintenance
systemctl daemon-reload
systemctl enable --now rest-server
complete_component
begin_component firewallFinalization 300
ip link show tailscale0 >/dev/null 2>&1 || { echo 'Tailscale interface is unavailable; refusing broad Vault firewall rules.' >&2; exit 4; }
# Add only exact DevFleet-owned rules. Preserve unrelated administrator policy
# and do not enable or reset the host firewall here.
ufw allow in on tailscale0 to any port 22 proto tcp comment 'DevFleet-owned tailscale SSH'
ufw allow in on tailscale0 to any port "$PORT" proto tcp comment 'DevFleet-owned tailscale Vault'
cat >/usr/local/sbin/devfleet-vault-firewall-refresh <<'FIREWALL_REFRESH'
#!/usr/bin/env bash
set -Eeuo pipefail
ip link show tailscale0 >/dev/null 2>&1 || exit 4
ufw allow in on tailscale0 to any port 22 proto tcp comment 'DevFleet-owned tailscale SSH'
ufw allow in on tailscale0 to any port __VAULT_PORT__ proto tcp comment 'DevFleet-owned tailscale Vault'
FIREWALL_REFRESH
sed -i "s/__VAULT_PORT__/$PORT/g" /usr/local/sbin/devfleet-vault-firewall-refresh
chmod 0755 /usr/local/sbin/devfleet-vault-firewall-refresh
cat >/etc/systemd/system/devfleet-vault-firewall-refresh.service <<'FIREWALL_UNIT'
[Unit]
Description=Refresh DevFleet Vault private-network firewall rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/devfleet-vault-firewall-refresh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FIREWALL_UNIT
systemctl daemon-reload
systemctl enable --now devfleet-vault-firewall-refresh.service
jq -n --arg cluster "$CLUSTER" --arg user "$REST_USER" --argjson port "$PORT" '{cluster:$cluster,port:$port,user:$user}' > /etc/devfleet-vault-public.json
jq -n --arg deployment "$DEPLOYMENT_ID" --arg id "$NODE_ID" --arg node "$NODE_NAME" '{schema_version:1,deployment_id:$deployment,node_id:$id,node_name:$node,node_role:"vault"}' > /etc/devfleet-vault-identity.json
chmod 0600 /etc/devfleet-vault-public.json
chmod 0600 /etc/devfleet-vault-identity.json
complete_component
write_progress bootstrap COMPLETED
echo 'DevFleet vault bootstrap complete.'

```


## FILE: source/linux/dependency-advisory-allowlist.json

SHA256: 81a515050e5d312ac4a453fa1bdaa999cfc11ad6a652659776bf5747c6b69168 | Bytes: 46 | Git mode: 100644

```
{
  "schema_version": 1,
  "exceptions": []
}

```


## FILE: source/linux/dependency-policy.json

SHA256: 9754d4c72b9a3c608f1ed1efda0d1ff7ae12f8d6be555ccd618466b8125c9269 | Bytes: 936 | Git mode: 100644

```
{
  "schemaVersion": 1,
  "tailscale": {
    "repository": "https://pkgs.tailscale.com/stable/ubuntu",
    "signingKeySha256Fingerprint": "2596A99EAAB33821893C0A79458CA832957F5868"
  },
  "docker": {
    "repository": "https://download.docker.com/linux/ubuntu",
    "signingKeySha256Fingerprint": "9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
  },
  "node": {
    "source": "Ubuntu signed apt repository",
    "minimumMajor": 18,
    "devcontainersCliVersion": "0.80.1",
    "devcontainersCliIntegrity": "sha512-FD6wq8ka2fVqybWooW++0UVTqo46TzxHblwTi9y58TqP3Qdx6iwMt/hzgjfcs865BtR36+wEg+qRPcKwxjzjBA=="
  },
  "restServer": {
    "owner": "restic",
    "repository": "rest-server",
    "tag": "v0.14.0",
    "asset": "rest-server_0.14.0_linux_amd64.tar.gz",
    "sha256": "4c9c95bc079a0334e81fad379b19dc5c3353c71c2c88d652cafce2081c2b1c66",
    "metadataSource": "https://api.github.com/repos/restic/rest-server/releases/tags/v0.14.0"
  }
}

```


## FILE: source/linux/devfleet-backup

SHA256: c1334694748167d8781713b3a74fe184b8a549dfde457a500233a97999e8f644 | Bytes: 1629 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
[[ -r /etc/devfleet/restic.env ]] || exit 0
set -a; source /etc/devfleet/restic.env; set +a
[[ -d /var/lib/devfleet/backup-status && -w /var/lib/devfleet/backup-status ]] || { echo 'Backup status directory is missing or not writable.' >&2; exit 3; }
[[ -d "${RESTIC_CACHE_DIR:-}" && -w "${RESTIC_CACHE_DIR:-}" ]] || { echo 'Restic cache directory is missing or not writable.' >&2; exit 3; }
exec 9>/run/lock/devfleet-vault-operation.lock
flock -n 9 || { echo 'Another Vault operation is already in progress.' >&2; exit 75; }
exclude=$(mktemp)
trap 'rm -f -- "$exclude"' EXIT
cat >"$exclude" <<'EOF'
**/node_modules
**/.venv
**/__pycache__
**/.pytest_cache
**/.mypy_cache
**/.next
**/dist
**/build
**/.cache
# The transaction journal is control-owned (0700) and is not workspace data.
# Keep the backup account from traversing this protected internal subtree.
/home/devrunner/workspaces/.devfleet-transactions
EOF
if restic backup /home/devrunner/workspaces /home/devrunner/.devfleet-quarantine --host "$(hostname)" --tag devfleet --exclude-file "$exclude" --exclude-caches; then
  printf '{"local_backup_status":"verified","vault_upload_status":"verified","durability_level":"vault"}\n' > /var/lib/devfleet/backup-status/latest.json
else
  backup_exit=$?
  # Preserve the fixed child cause (for example unreadable source data), never
  # accept a partial snapshot or expose private restic output through the broker.
  printf '{"local_backup_status":"failed","vault_upload_status":"failed","durability_level":"none"}\n' > /var/lib/devfleet/backup-status/latest.json
  exit "$backup_exit"
fi

```


## FILE: source/linux/devfleet-configure-backup

SHA256: f12c94fa0f12ba9482cbf8b10de3dfc5211d46f01863498af2a1a5d14849479e | Bytes: 2389 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
src=${1:?vault json required}
cleanup(){ if [[ "$src" == /tmp/* ]]; then rm -f -- "$src"; fi; }
trap cleanup EXIT
jq -e '.Repository and .RestUser and .RestPassword and .ResticPassword' "$src" >/dev/null
repo=$(jq -r .Repository "$src")
pairing_mode=$(jq -r '.PairingMode // "tailscale"' "$src")
[[ "$pairing_mode" == 'tailscale' ]] || { echo 'Authenticated Vault transport requires Tailscale; plaintext deferred-local transport is disabled.' >&2; exit 2; }
[[ "$repo" =~ ^rest:http://100\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/ ]] || { echo 'Repository must use a Tailscale IPv4 address.' >&2; exit 2; }
cat >/etc/devfleet/restic.env <<EOF
RESTIC_REPOSITORY=$repo
RESTIC_REST_USERNAME=$(jq -r .RestUser "$src")
RESTIC_REST_PASSWORD=$(jq -r .RestPassword "$src")
RESTIC_PASSWORD=$(jq -r .ResticPassword "$src")
RESTIC_CACHE_DIR=/var/lib/devfleet/backup-status/restic-cache
EOF
chown root:devfleet-backup /etc/devfleet/restic.env
chmod 0640 /etc/devfleet/restic.env
# Keep /etc/devfleet private while allowing only the backup service account to
# traverse it to the restic environment file whose group owns read access.
setfacl -m u:devfleet-backup:--x /etc/devfleet
# Keep the runtime state root private while allowing the backup service account
# to reach its separately permissioned status directory.
setfacl -m u:devfleet-backup:--x /var/lib/devfleet
# The backup source directories are deliberately private to devrunner and are
# granted only the traversal needed by the backup service account. Their child
# ACLs remain the authority for the actual files and directories read.
setfacl -m u:devfleet-backup:--x /home/devrunner
install -d -o devfleet-control -g devfleet-control -m 0750 /var/lib/devfleet/backup-status
setfacl -m u:devfleet-backup:rwx /var/lib/devfleet/backup-status
install -d -o devfleet-backup -g devfleet-backup -m 0700 /var/lib/devfleet/backup-status/restic-cache
jq -n --arg repository "$repo" '{repository:$repository}' >/var/lib/devfleet/backup-status/config.json
chown devfleet-control:devfleet-control /var/lib/devfleet/backup-status/config.json
chmod 0640 /var/lib/devfleet/backup-status/config.json
sudo -u devfleet-backup bash -lc 'set -a; source /etc/devfleet/restic.env; set +a; restic snapshots >/dev/null 2>&1 || restic init'
systemctl restart devfleet-backup.timer
sudo -u devfleet-backup /usr/local/bin/devfleet-backup

```


## FILE: source/linux/devfleet-docker-mode-report

SHA256: ad369c63d0363aa359ce1e34d37deeeb2947fc7d90f8a137cc4c14756b3e0017 | Bytes: 589 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
uid=$(id -u devrunner);echo "Selected mode: $(jq -r '.docker_mode // "rootless"' /etc/devfleet/config.json)";echo 'Rootless store:';sudo -u devrunner env DOCKER_HOST="unix:///run/user/$uid/docker.sock" docker info --format 'root={{.DockerRootDir}} containers={{.Containers}} images={{.Images}}' 2>/dev/null || echo unavailable;echo 'Rootful store:';docker info --format 'root={{.DockerRootDir}} containers={{.Containers}} images={{.Images}}' 2>/dev/null || echo unavailable;echo 'Stores are separate. DevFleet never silently copies or deletes them.'

```


## FILE: source/linux/devfleet-health

SHA256: 11e17775c3f5a9dc5a59e79d70aeb2adcb0f25a0a1a6b4ecaafb1feefd1fd78a | Bytes: 1352 | Git mode: 100644

```
#!/usr/bin/env bash
set -u
docker_mode=$(jq -r '.docker_mode // "rootless"' /etc/devfleet/config.json 2>/dev/null || echo rootless)
if [[ $docker_mode == rootless ]]; then export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"; export DOCKER_CONTEXT=rootless; else unset DOCKER_HOST; export DOCKER_CONTEXT=default; fi
fail=0
printf 'Node: '; hostname
printf 'Tailscale: '; tailscale status --json --peers=false 2>/dev/null | jq -r '.BackendState // "not-connected"' || echo unavailable
if [[ $docker_mode == rootless ]]; then
  printf 'Rootless Docker: '
  if docker info --format '{{json .SecurityOptions}}' 2>/dev/null | grep -q rootless; then echo OK; else echo FAIL; fail=1; fi
else
  printf 'Rootful Docker: '
  if docker info >/dev/null 2>&1; then echo OK; else echo FAIL; fail=1; fi
fi
printf 'DevFleet service: '; systemctl is-active devfleet || fail=1
printf 'Disk: '; df -h /home/devrunner | tail -n1
printf 'Workspaces: '; find /home/devrunner/workspaces -mindepth 1 -maxdepth 1 -type d | wc -l
printf 'Backup timer: '; systemctl is-active devfleet-backup.timer || true
if [[ -f /var/lib/devfleet/backup-status/latest.json ]]; then
  printf 'Backup status: '; jq -r '.durability_level // .local_backup_status // "unknown"' /var/lib/devfleet/backup-status/latest.json
else echo 'Backup: not configured or not yet verified'; fi
exit $fail

```


## FILE: source/linux/devfleet-join-deployment

SHA256: 9a542f43851dfe31cc37928d650463e5724e6f0156fbe484b95a101645ec16cf | Bytes: 5139 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
src=${1:?primary invitation required}; identity=/etc/devfleet/node-identity.json; config=/etc/devfleet/config.json; registry=/var/lib/devfleet/runtime/node-registry.json
[[ -f "$src" && -f "$identity" && -f "$config" ]] || { echo 'Joined-surrogate inputs are incomplete.' >&2; exit 3; }
uuid='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
jq -e --arg r "$uuid" '.node_role=="primary" and .protocol_version==1 and (.deployment_id|type=="string" and test($r)) and (.node_id|type=="string" and test($r))' "$src" >/dev/null || { echo 'Primary invitation identity or protocol is invalid.' >&2; exit 3; }
jq -e --arg r "$uuid" '.node_role=="surrogate" and (.deployment_id=="" or .deployment_id==null) and .protocol_version==1 and (.node_id|type=="string" and test($r)) and (.node_name|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$"))' "$identity" >/dev/null || { echo 'Existing node is not a valid unjoined Surrogate.' >&2; exit 3; }
node_id=$(jq -er '.node_id' "$identity"); node_name=$(jq -er '.node_name' "$identity")
jq -e --arg id "$node_id" --arg name "$node_name" '.node_role=="surrogate" and .node_id==$id and .node_name==$name and (.deployment_id=="" or .deployment_id==null) and .protocol_version==1' "$config" >/dev/null || { echo 'Surrogate configuration identity is missing or already joined.' >&2; exit 3; }
deployment=$(jq -er '.deployment_id' "$src"); primary=$(jq -er '.node_id' "$src"); protocol=$(jq -er '.protocol_version' "$src")
install -d -o devfleet-control -g devfleet-control -m 0750 /var/lib/devfleet/runtime
if [[ -f "$registry" ]]; then jq -e --arg d "$deployment" '.deployment_id==$d' "$registry" >/dev/null || { echo 'Local registry deployment mismatch.' >&2; exit 3; }; fi
tmpdir=$(mktemp -d /etc/devfleet/.join-deployment.XXXXXX); backupdir=$(mktemp -d /etc/devfleet/.join-deployment-backup.XXXXXX); restarted=0
cleanup(){ rm -rf -- "$tmpdir" "$backupdir"; }; trap cleanup EXIT
backup(){ local p=$1 n=$2; if [[ -e "$p" || -L "$p" ]]; then [[ -f "$p" && ! -L "$p" ]] || return 1; cp -p -- "$p" "$backupdir/$n"; stat -c '%u:%g:%a' "$p" >"$backupdir/$n.stat"; else : >"$backupdir/$n.absent"; fi; }
restore(){ local p=$1 n=$2; if [[ -f "$backupdir/$n.absent" ]]; then rm -f -- "$p"; return; fi; install -m 0600 "$backupdir/$n" "$p"; IFS=: read -r u g m <"$backupdir/$n.stat"; chown "$u:$g" "$p" && chmod "$m" "$p"; }
rollback(){ local rc=0; restore "$identity" identity || rc=1; restore "$config" config || rc=1; restore "$registry" registry || rc=1; if [[ $rc -eq 0 && $restarted -eq 1 ]]; then systemctl restart devfleet.service || rc=1; fi; [[ $rc -eq 0 ]] || { echo 'ROLLBACK_FAILED: joined-surrogate state could not be restored.' >&2; return 1; }; }
fail(){ echo "$1" >&2; rollback || exit 70; exit 1; }
backup "$identity" identity || exit 3; backup "$config" config || exit 3; backup "$registry" registry || exit 3
jq --arg d "$deployment" --arg c "$primary" --argjson p "$protocol" '.deployment_id=$d|.coordinator_node_id=$c|.registration_state="joined"|.protocol_version=$p' "$identity" >"$tmpdir/identity"
jq --arg d "$deployment" --arg c "$primary" --argjson p "$protocol" '.deployment_id=$d|.coordinator_node_id=$c|.registration_state="joined"|.protocol_version=$p' "$config" >"$tmpdir/config"
if [[ -f "$registry" ]]; then jq --arg d "$deployment" --arg id "$node_id" --arg n "$node_name" --arg c "$primary" --argjson p "$protocol" '.deployment_id=$d|.nodes=(.nodes//[])|if any(.nodes[];.node_id==$id) then .nodes |= map(if .node_id==$id then .deployment_id=$d|.node_name=$n|.node_role="surrogate"|.coordinator_node_id=$c|.protocol_version=$p|.registration_state="joined"|.connectivity="online" else . end) else .nodes += [{deployment_id:$d,node_id:$id,node_name:$n,node_role:"surrogate",capabilities:["compute"],coordinator_node_id:$c,protocol_version:$p,registration_state:"joined",connectivity:"online"}] end' "$registry" >"$tmpdir/registry"; else jq -n --arg d "$deployment" --arg id "$node_id" --arg n "$node_name" --arg c "$primary" --argjson p "$protocol" '{schema_version:1,deployment_id:$d,nodes:[{deployment_id:$d,node_id:$id,node_name:$n,node_role:"surrogate",capabilities:["compute"],coordinator_node_id:$c,protocol_version:$p,registration_state:"joined",connectivity:"online"}]}' >"$tmpdir/registry"; fi
install -o root -g devrunner -m 0640 "$tmpdir/identity" "$tmpdir/identity.ready" || fail 'Failed to stage joined node identity.'
install -o root -g devfleet-control -m 0640 "$tmpdir/config" "$tmpdir/config.ready" || fail 'Failed to stage joined config.'
install -o devfleet-control -g devfleet-control -m 0640 "$tmpdir/registry" "$tmpdir/registry.ready" || fail 'Failed to stage joined node registry.'
mv -f -- "$tmpdir/identity.ready" "$identity" || fail 'Failed to commit joined node identity.'; mv -f -- "$tmpdir/config.ready" "$config" || fail 'Failed to commit joined config.'; mv -f -- "$tmpdir/registry.ready" "$registry" || fail 'Failed to commit joined node registry.'
restarted=1; systemctl restart devfleet.service || fail 'Joined identity committed but daemon restart failed.'; restarted=0

```


## FILE: sour