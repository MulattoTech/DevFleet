# DevFleet source part 084

Full-source UTF-8 byte interval [3859500, 3906000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8f7be314498f872090dedc42f2f3d1a52df9fae08b6d49cd59bcc6223d73b88e

<!-- BEGIN SOURCE SLICE -->
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


## FILE: source/linux/devfleet-purge-quarantine

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
        if a