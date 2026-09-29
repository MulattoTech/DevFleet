# DevFleet source part 083

Full-source UTF-8 byte interval [3813000, 3859500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 94e406024de614dd8b3353da1fa1e3b094f04a0f3682df2a719389f7759b5b2c

<!-- BEGIN SOURCE SLICE -->
bservation when local.


`Configure-Ollama.ps1` binds Ollama to the Windows host's Tailscale IPv4 address rather than a wildcard, creates a Windows Firewall rule limited to the tailnet CIDR, and records the MagicDNS name as the preferred client endpoint when Tailscale reports one. It does not add ROCm, HIP, Vulkan, or AMD-specific variables. After changing an installed endpoint, safely refresh each compute node so its generated service configuration receives the authoritative value.

```


## FILE: source/docs/11-REMOTE-VSCODE.md

SHA256: adf463bf6333f1ff118433701d9bccb9038dc12c1c512a95f2932b46f5e3ad6b | Bytes: 1184 | Git mode: 100644

````
# Remote VS Code

The laptop is the primary client and does not require Docker Desktop for main workloads. `Configure-SSH.ps1` creates `CodexDevVM` and failover aliases using the generated Ed25519 key and Tailscale IP. `Configure-DockerContext.ps1` creates Docker-over-SSH only; it never opens TCP 2375. `Configure-VSCode.ps1` installs real Remote SSH/Dev Containers and language extension groups and supplies exclusions for dependencies, caches, models, generated artifacts, and `.ai-bridge/local-agent`.

Typical commands:

```powershell
ssh CodexDevVM
code --remote ssh-remote+CodexDevVM /home/devrunner/workspaces/<project>
docker --context Codexdevvm ps
```


## Extension placement

Install Remote SSH and Remote Explorer on Windows. When VS Code opens `CodexDevVM`, allow language servers, linters, debuggers, and Dev Containers support to install in the remote environment when VS Code recommends it; UI-only extensions may remain local. The supplied extension lists are grouped so Python/web/enterprise/systems tooling can be added only for the projects that need it. The reference settings are copied for review rather than overwriting an existing personal `settings.json`.

````


## FILE: source/docs/12-UPGRADING-FROM-1.0.0.md

SHA256: 28666495394ce7fa029bbf0c0d0949512333328d28181fb238bd901345af30f2 | Bytes: 1101 | Git mode: 100644

````
# DevFleet v1.0.0 to v1.1.0 migration

Run the preview and then the upgrade from an elevated PowerShell 7 terminal:

```powershell
pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0 -PreviewOnly
pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0
```

The entry point backs up `C:\ProgramData\DevFleet` configuration, secrets, exports, and package metadata; validates Multipass host-mount isolation; stops each local DevFleet VM; creates a named snapshot; restores the prior running state; previews schema 2; and refreshes only existing instances. It does not delete or recreate VMs, projects, Git repositories, Docker stores/volumes, backup credentials, restic snapshots, vault data, Tailscale identities, SSH keys, dashboard credentials, pairing data, quarantine, or custom values.

A schema-1 baseline becomes Strict/rootless first. Rootless and rootful Docker have separate stores; optional switching requires a report, stopped projects, and explicit rootful acknowledgement. Re-running the v1.1 upgrade is safe and creates another recovery set rather than resetting the selected v1.1 profile.

````


## FILE: source/docs/13-PERFORMANCE-TUNING.md

SHA256: 04264853da9e3a2d5baa1002ccf43018df4af3c2d79bbf8236909e262a44501f | Bytes: 2023 | Git mode: 100644

```
# Performance tuning and practical token efficiency

DevFleet does not claim to alter ChatGPT/model quotas. It improves throughput with selective file loading, initial workspace opening without a full tree, search/read targeting, diff-oriented review, concise `.ai-bridge` handoffs, cached analyzer fingerprints, changed-file manifests, reusable dependency/BuildKit caches, one canonical checkout plus Git worktrees, and exclusions for dependencies/generated/model/cache/binary/runtime data.

Control ownership:
- ChatGPT controls the selected model, app/connector availability, memory/settings, and product usage limits.
- CodexPro controls verified roots, auth, tool/write/bash/transcript modes, output limits, blocked globs, and exposed tools.
- DevFleet controls VMs, Docker mode, lifecycle, leases, backups, analyzer, operations, peer transfer, and dashboard.
- The project controls committed instructions, `.devfleet/project.json`, Compose/Dev Container files, tests, language metadata, and `.ai-bridge` handoffs.
- Ollama controls the local endpoint, model availability, context/concurrency/queue settings, and observable GPU/CPU placement.
- Hidden headers, connector-retention flags, model-routing overrides, context-cache bypasses, and rate-limit bypasses are not fabricated.

Use the included session bootstrap/reconnect/broken-session/handoff prompts. Call `server_config` first, self-test only for fresh/broken/reconfigured sessions, open without a full tree, and verify tool reachability before long work.


The DevFleet package verifier and file-change manifest prevent repeated broad inspection of unchanged package content. Per-project analyzer fingerprints cover Compose, Dev Container, Dockerfile, environment-file, metadata, symlink, and bind-target inputs and are invalidated when those inputs change. Docker BuildKit's daemon-local cache is reused within each selected Docker store; dependency-manager caches are mounted only through trusted generated overrides and never include source repositories.

```


## FILE: source/docs/RELEASE-FINGERPRINT-SCHEMA.md

SHA256: 0e83ab1f2f01961b14ddc261a76128fa8f27ad35c04c63e732ef5824620ec80f | Bytes: 677 | Git mode: 100644

```
# Release fingerprint schema

Schema 2 is the current DevFleet release identity format. It removes checkout-local
absolute artifact paths and host filesystem permission bits from the hashed identity.
Artifacts are identified by logical name, byte length, and SHA-256. Source file modes
come from the same hook-mode contract used to write the canonical TAR and portable
archive: contracted template hooks are `0755`, and every other shipping file is
`0644`.

Schema 1 records remain valid only as explicitly historical evidence. They must not
be promoted as the identity of a current candidate because their IDs can vary by
checkout location and host permission representation.

```


## FILE: source/docs/host-agent-portability.md

SHA256: b7c8271409e747cc03a5214b7d082b9673e3e69131edd6a534db613bf6bb8faf | Bytes: 1504 | Git mode: 100644

```
# DevFleet host-agent portability

The dashboard talks to a narrow authenticated host-agent contract rather than directly to Multipass. A second Windows host such as MulattoTechSurface only needs the same contract and a host-specific configuration file.

Required configuration values are `HostId`, `HostName`, `ListenPrefix`, `TokenPath`, `MultipassPath`, `MultipassVersion`, `UbuntuImage`, `BootTimeoutSeconds`, `SshPublicKeyPath`, and `ResourcePolicy`. The resource policy must include host reserves, `MaximumVmCount`, `MaximumParallelProvisioning`, and project CPU, memory, and disk ceilings.

Portability rules:

- Keep the host identity unique and verify it on every authenticated response.
- Discover Multipass and actual host capacity on the target; do not copy MulattoTechBox capacity values blindly.
- Keep `gpu_enabled`, `gpu`, and `gpu_passthrough` false unless a separately reviewed provider is introduced.
- Use the same deterministic project VM naming and ownership registry on every host.
- Do not migrate or recreate an existing project automatically. Reconcile first, then require an explicit transfer operation.
- Keep host-agent install, firewall scope, and scheduled-task settings in the host-specific installer; the dashboard and provider contract remain shared.

The current package intentionally does not install or configure the Surface host. This document and the provider boundary are the preparation for a later one-package patch and a separately gated host-specific install.

```


## FILE: source/linux/bootstrap-compute.sh

SHA256: 512bc920be2372e2211f897ba6b83dcfa72b4c5c8973f5f8f548363425880645 | Bytes: 26944 | Git mode: 100644

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
BOOTSTRAP_MAX_SECONDS="${DEVFLEET_BOOTSTRAP_MAX_SECONDS:-6600}"
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
    *) echo "unsupported bootstrap argument" >&2; exit 64 ;;
  esac
  shift
done

# Validate non-secret launch identity before creating files or waiting on stdin.
if [[ "$SECRETS_STDIN_REQUESTED" -ne 1 ]]; then echo 'Refusing legacy plaintext node-secrets.json input; use --secrets-stdin.' >&2; exit 64; fi
if [[ -z "$TRANSACTION_ID" || "$TRANSACTION_ID" =~ [^0-9a-fA-F] || ${#TRANSACTION_ID} -ne 32 ]]; then echo 'invalid transaction id' >&2; exit 64; fi
if [[ -z "$PAYLOAD_SHA256" || "$PAYLOAD_SHA256" =~ [^0-9a-fA-F] || ${#PAYLOAD_SHA256} -ne 64 ]]; then echo 'invalid payload sha256' >&2; exit 64; fi
if [[ ! "$BOOTSTRAP_MAX_SECONDS" =~ ^[0-9]+$ || "$BOOTSTRAP_MAX_SECONDS" -le 0 ]]; then echo 'invalid bootstrap owner deadline' >&2; exit 64; fi
[[ "$PACKAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'invalid bound package version' >&2; exit 64; }
[[ "$NODE_ROLE" =~ ^(primary|surrogate)$ ]] || { echo 'invalid bound node role' >&2; exit 64; }
BOUND_PACKAGE_VERSION=$PACKAGE_VERSION
BOUND_NODE_ROLE=$NODE_ROLE
INPUT_HELPER="$PAYLOAD/linux/bootstrap-input.sh"
[[ -f "$INPUT_HELPER" ]] || { echo 'missing bootstrap input helper' >&2; exit 4; }
# shellcheck source=bootstrap-input.sh
source "$INPUT_HELPER"

# Component deadlines are absolute and subordinate to the bootstrap owner.
BOOTSTRAP_STARTED_EPOCH=$(date +%s)
BOOTSTRAP_DEADLINE_EPOCH=$((BOOTSTRAP_STARTED_EPOCH + BOOTSTRAP_MAX_SECONDS))
PROGRESS_PATH=/var/lib/devfleet/bootstrap-progress.json
install -d -o root -g root -m 0750 /var/lib/devfleet
PROGRESS_SEQUENCE=0
CURRENT_COMPONENT=''
COMPONENT_DEADLINE_EPOCH=$BOOTSTRAP_DEADLINE_EPOCH
COMPONENT_TERMINALIZED=0
if [[ -f "$PROGRESS_PATH" ]] && jq -e --arg tx "$TRANSACTION_ID" --arg payload "$PAYLOAD_SHA256" '.transactionId==$tx and .payloadSha256==$payload and (.sequence|numbers)' "$PROGRESS_PATH" >/dev/null 2>&1; then
  PROGRESS_SEQUENCE=$(jq -r --arg tx "$TRANSACTION_ID" --arg payload "$PAYLOAD_SHA256" 'select(.transactionId==$tx and .payloadSha256==$payload) | .sequence' "$PROGRESS_PATH")
fi
write_progress() {
  local component=$1 state=$2 tmp now
  [[ "$component" =~ ^(secretsInput|packagePrerequisites|dockerRepositoryAndInstall|tailscaleRepositoryAndInstall|rootlessRuntime|nodeToolchain|pythonRuntime|serviceAndFirewallFinalization|bootstrap)$ ]] || return 1
  [[ "$state" =~ ^(STARTED|COMPLETED|FAILED|TIMED_OUT)$ ]] || return 1
  PROGRESS_SEQUENCE=$((PROGRESS_SEQUENCE + 1)); now=$(date -u +%Y-%m-%dT%H:%M:%SZ); tmp=$(mktemp /var/lib/devfleet/bootstrap-progress.XXXXXX)
  jq -n --arg tx "$TRANSACTION_ID" --arg payload "$PAYLOAD_SHA256" --arg component "$component" --arg state "$state" --arg now "$now" --arg version "$PACKAGE_VERSION" --arg role "$NODE_ROLE" --argjson sequence "$PROGRESS_SEQUENCE" '{schemaVersion:1,transactionId:$tx,payloadSha256:$payload,sequence:$sequence,component:$component,state:$state,updatedUtc:$now,packageVersion:$version,nodeRole:$role}' > "$tmp"
  chown root:root "$tmp"; chmod 0640 "$tmp"; sync -d "$tmp" 2>/dev/null || true; mv -f -- "$tmp" "$PROGRESS_PATH"; chown root:root "$PROGRESS_PATH"; chmod 0640 "$PROGRESS_PATH"
}
remaining_seconds() { echo $((COMPONENT_DEADLINE_EPOCH - $(date +%s))); }
run_bounded() {
  local remaining rc=0
  remaining=$(remaining_seconds)
  if (( remaining <= 0 )); then write_progress "$CURRENT_COMPONENT" TIMED_OUT || true; COMPONENT_TERMINALIZED=1; return 124; fi
  timeout --foreground --kill-after=10s "${remaining}s" "$@" || rc=$?
  if (( rc == 124 || rc == 137 )); then write_progress "$CURRENT_COMPONENT" TIMED_OUT || true; COMPONENT_TERMINALIZED=1; fi
  return "$rc"
}
run_bounded_command() {
  local command=$1; shift; local remaining; remaining=$(remaining_seconds)
  if [[ "$command" == "/usr/bin/apt-get" ]]; then set -- -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=2 "$@"; fi
  if [[ "$command" == "/usr/bin/curl" ]]; then set -- --connect-timeout 20 --max-time "$remaining" "$@"; fi
  run_bounded "$command" "$@"
}
apt-get() { run_bounded_command /usr/bin/apt-get "$@"; }
curl() { run_bounded_command /usr/bin/curl "$@"; }
gpg() { run_bounded_command /usr/bin/gpg "$@"; }
systemctl() { run_bounded_command /usr/bin/systemctl "$@"; }
npm() { run_bounded_command /usr/bin/npm "$@"; }
begin_component() { CURRENT_COMPONENT=$1; COMPONENT_TERMINALIZED=0; local max=$2 now; now=$(date +%s); COMPONENT_DEADLINE_EPOCH=$((now + max)); if (( COMPONENT_DEADLINE_EPOCH > BOOTSTRAP_DEADLINE_EPOCH )); then COMPONENT_DEADLINE_EPOCH=$BOOTSTRAP_DEADLINE_EPOCH; fi; write_progress "$CURRENT_COMPONENT" STARTED; }
complete_component() { write_progress "$CURRENT_COMPONENT" COMPLETED; CURRENT_COMPONENT=''; COMPONENT_TERMINALIZED=0; }
finish_bootstrap() {
  local rc=$? cleanup_rc=0
  trap - ERR EXIT
  rm -f -- "${SECRETS_SOURCE-}" "${SECRETS_ENV_TMP-}" "${DOCKER_KEY-}" "${TAILSCALE_KEY-}" || cleanup_rc=$?
  if [[ -n ${NPM_TMP-} ]]; then rm -rf -- "$NPM_TMP" || cleanup_rc=$?; fi
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
SECRETS_SOURCE=$(devfleet_capture_json_stdin '/run/devfleet-node-secrets.XXXXXX' "$COMPONENT_DEADLINE_EPOCH")
input_rc=$?
set -e
if (( input_rc != 0 )); then
  if (( input_rc == 124 || input_rc == 137 )); then write_progress secretsInput TIMED_OUT || true; else write_progress secretsInput FAILED || true; fi
  COMPONENT_TERMINALIZED=1
  echo 'bounded secret input delivery failed' >&2
  exit "$input_rc"
fi
fail_input() { local message=$1 code=${2:-2}; write_progress secretsInput FAILED || true; COMPONENT_TERMINALIZED=1; echo "$message" >&2; exit "$code"; }

JQ() { jq -r "$1" "$SECRETS_SOURCE"; }
NODE_NAME=$(JQ .NodeName); NODE_ROLE=$(JQ .NodeRole); FRIENDLY_NAME=$(JQ '.FriendlyName // .NodeName')
PORT=$(JQ .PortalPort); ADMIN_USER=$(JQ .AdminUser); ADMIN_PASSWORD=$(JQ .AdminPassword); API_TOKEN=$(JQ .ApiToken)
DEPLOYMENT_ID=$(JQ '.DeploymentId // ""'); NODE_ID=$(JQ .NodeId); COORDINATOR_NODE_ID=$(JQ '.CoordinatorNodeId // ""')
PROTOCOL_VERSION=$(JQ '.ProtocolVersion // 1'); OLLAMA_BASE=$(JQ .OllamaBaseUrl); OLLAMA_MODEL=$(JQ .OllamaModel)
OLLAMA_PROFILE=$(JQ '.OllamaProfile // "stable-interactive"'); DEVELOPMENT_PROFILE=$(JQ '.DevelopmentProfile // "strict"')
DOCKER_MODE=$(JQ '.DockerMode // "rootless"'); SHARED_CACHES=$(JQ '.EnableSharedCaches // false')
ANALYZER_CACHE=$(JQ '.EnableAnalyzerCache // true'); AUTO_CODEX=$(JQ '.AutoStartCodexPro // true')
ALLOW_TAILNET=$(JQ '.AllowTailnetPorts // false'); BACKUP_REBUILD=$(JQ '.BackupBeforeRebuild // false')
BACKUP_QUARANTINE=$(JQ '.BackupBeforeQuarantine // true'); BACKUP_INTERVAL=$(JQ '.BackupIntervalMinutes // 15')
INPUT_PACKAGE_VERSION=$(JQ .PackageVersion)
INPUT_NODE_ROLE=$NODE_ROLE
[[ "$INPUT_PACKAGE_VERSION" == "$BOUND_PACKAGE_VERSION" ]] || fail_input 'secret input package identity mismatch'
[[ "$INPUT_NODE_ROLE" == "$BOUND_NODE_ROLE" ]] || fail_input 'secret input node role mismatch'
PACKAGE_VERSION=$INPUT_PACKAGE_VERSION
[[ $PACKAGE_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail_input 'invalid PackageVersion'
[[ -n "$NODE_ID" && "$NODE_ID" != 'null' ]] || fail_input 'missing node identity' 3
[[ $DEVELOPMENT_PROFILE =~ ^(strict|balanced|fast)$ ]] || fail_input 'invalid development profile'
[[ $DOCKER_MODE =~ ^(rootless|rootful)$ ]] || fail_input 'invalid Docker mode'
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
