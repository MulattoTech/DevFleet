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
