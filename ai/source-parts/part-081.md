# DevFleet source part 081

Full-source UTF-8 byte interval [3720000, 3766500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 9ee3e2495a8a809e0a9512f8da05f9d487aed4ffee80d423bf540b6721f1ebf5

<!-- BEGIN SOURCE SLICE -->
="DESTROY {{ p.slug }}"></label><button class="button danger" type="submit">Delete project permanently</button></form></article></section>
     {% elif project_tab == 'isolate' %}<section class="panel danger-panel"><div class="eyebrow danger-text">ISOLATE PROJECT</div><h2>Quarantine this workspace</h2><p class="muted">Creates and verifies a backup, then stops the project before isolating it. This control stays reviewable and requires explicit acknowledgement.</p><form method="post" action="/projects/{{ p.slug }}/quarantine" class="danger-form">{{ csrf() }}<label class="checkbox-label"><input type="checkbox" name="confirm_quarantine" required> I understand this will make the project unavailable until restored.</label><button class="button danger" type="submit">Create backup &amp; isolate</button></form></section>
     {% else %}
    <div class="panel preference-panel"><label class="checkbox-label preference-toggle"><input id="advanced-mode-toggle" type="checkbox"> Show advanced diagnostics and raw internal data</label><p class="muted help-text">Keep this off for normal operation. It is stored on this browser only.</p></div>
    <section class="content-grid two-thirds"><article class="panel"><div class="eyebrow">WORKSPACE</div><h2>Project overview</h2><div class="environment-summary"><div><small>Environment</small><strong>{{ runtime_label(p) }}</strong></div><div><small>Provider</small><strong>{{ provider_label(p) }}</strong></div><div><small>Last backup</small><strong>{{ p.lease.last_backup|default('Not verified', true) }}</strong></div></div><p class="muted">Workspace path: <code>{{ p.path }}</code> · Target: <code>{{ workspace_target(p) }}</code></p><div class="quick-links">{{ open_workspace(p) }}<a class="button ghost" href="/projects/{{ p.slug }}?tab=environment">Change environment</a><a class="button ghost" href="/projects/{{ p.slug }}?tab=logs">Open logs</a></div></article><article class="panel"><div class="eyebrow">LIVE RUNTIME</div><h2>Current availability</h2><div class="environment-summary"><div><small>Live CPU</small><strong>{{ 'Available' if caps.can_query_live_metrics else 'Unavailable while ' ~ lifecycle }}</strong></div><div><small>Live memory</small><strong>{{ 'Available' if caps.can_query_live_metrics else 'Unavailable while ' ~ lifecycle }}</strong></div><div><small>Application health</small><strong>{{ p.health_status|default('unknown', true)|title if caps.can_query_application_health else 'Not checked — environment ' ~ lifecycle }}</strong></div></div>{% if caps.can_run_runtime_tests %}<div class="action-stack">{{ project_action(p.slug,'health','Check project health','ghost') }}{{ project_action(p.slug,'test','Run project tests','ghost') }}{{ project_action(p.slug,'codexpro','Set up Codex','ghost') }}</div>{% else %}<div class="runtime-unavailable"><strong>Runtime actions unavailable</strong><p>Start the project and wait for readiness to run health checks or tests.</p></div>{% endif %}<details id="advanced-controls" class="advanced"><summary>Advanced action references</summary><pre>Provider: {{ provider_label(p) }}&#10;Workspace target: {{ workspace_target(p) }}&#10;docker context: {{ p.docker_context|default(provider_label(p), true) }}</pre></details></article></section>{{ resource_allocation(p) }}
     {% endif %}
    {% endif %}

    {% elif view == 'infrastructure' %}
    <section class="page-intro"><div><p class="eyebrow">OPERATIONS</p><h2>Infrastructure</h2><p class="muted">Machines, containers, and VM capacity with safe, scoped controls.</p></div><div class="monitor-controls"><label>Auto-refresh<select id="refresh-interval" aria-label="Automatic refresh interval"><option value="0">Off</option><option value="5" selected>5 seconds</option><option value="10">10 seconds</option><option value="15">15 seconds</option><option value="30">30 seconds</option></select></label><button type="button" id="refresh-cluster" class="button ghost">Refresh now</button></div></section>
    <section class="panel"><div class="section-heading"><div><p class="eyebrow">MACHINES / DEVFLEET NODES</p><h2>Node health</h2></div><span id="cluster-updated" class="muted">Loading…</span></div><div id="cluster-nodes" class="node-grid" data-endpoint="/cluster/status"><p class="muted">Loading node health…</p></div></section>
    <section class="panel"><div class="section-heading"><div><p class="eyebrow">INFRASTRUCTURE / VM HOST</p><h2>VM Host</h2><p class="muted">{{ status.host_agent.status|default('ready', true)|replace('-', ' ')|title }} · {{ status.host_capacity.allocatable_memory_gb|default('—', true) }} GB safe memory available</p></div><span class="status-badge ok">GPU-free</span></div><div class="summary-grid"><div><small>Host identity</small><strong>{{ status.host_agent.host_name|default(status.friendly_name, true) }}</strong></div><div><small>Provider</small><strong>{{ status.vm_provider.provider|default('Multipass', true)|title }}</strong></div><div><small>Agent</small><strong>{{ status.host_agent.agent_version|default('Connected', true) }}</strong></div><div><small>Managed VMs</small><strong>{{ status.host_capacity.managed_vm_count|default('—', true) }}</strong></div></div><details class="advanced"><summary>Advanced Details</summary><div class="details-grid"><pre>{{ status.host_agent|tojson(indent=2) }}</pre><pre>{{ status.host_capacity|tojson(indent=2) }}</pre><pre>{{ status.vm_provider|tojson(indent=2) }}</pre></div></details></section>
    <section class="panel container-panel"><div class="section-heading"><div><p class="eyebrow">INFRASTRUCTURE / CONTAINERS</p><h2>Containers</h2><p class="muted">Portainer-style visibility without exposing Docker TCP or docker.sock.</p></div><label>Node<select id="container-node-filter" aria-label="Filter containers by node"><option value="all">All nodes</option></select></label></div><div class="table-wrap"><table id="container-table"><thead><tr><th>Node</th><th>Name</th><th>Image</th><th>State</th><th>CPU</th><th>Memory</th><th>Network I/O</th><th>Actions</th></tr></thead><tbody><tr><td colspan="8" class="muted">Loading container inventory…</td></tr></tbody></table></div><div id="container-details" class="container-details" hidden><div class="section-heading"><h3 id="container-details-title">Container details</h3><button type="button" id="close-container-details" class="button ghost">Close</button></div><div class="details-grid"><pre id="container-inspect"></pre><pre id="container-logs"></pre></div></div></section>

    {% elif view == 'activity' %}
    <section class="page-intro"><div><p class="eyebrow">AUDIT TRAIL</p><h2>Activity</h2><p class="muted">Operations are durable, progress-aware, and expandable when you need technical detail.</p></div></section><section class="panel activity-panel">{% for op in status.operations %}<article class="operation-row" id="{{ op.id }}"><span class="activity-dot {{ 'bad' if op.state == 'failed' else 'ok' if op.state == 'completed' else 'warn' }}"></span><div class="operation-main"><strong>{{ op.kind|replace('-', ' ')|title }}</strong><p>{{ op.project }} · {{ op.message }}</p><div class="progress-track"><span style="width:{{ op.progress }}%"></span></div></div><div class="operation-meta">{{ op.state }}<br><small>{{ op.updated_at }}</small></div><details class="advanced"><summary>Details</summary><pre>{{ op.log|tojson(indent=2) }}{{ op.result or op.error or '' }}</pre></details></article>{% else %}<p class="muted">No activity yet.</p>{% endfor %}</section>

    {% else %}
    <section class="page-intro"><div><p class="eyebrow">DEVFLEET SETTINGS</p><h2>Settings & safety</h2><p class="muted">Host-safe controls and diagnostics.</p></div></section><section class="content-grid two-thirds"><article class="panel"><div class="eyebrow">NODE HEALTH</div><h2>{{ status.friendly_name }}</h2><p class="muted">Profile {{ status.profile }} · Docker {{ status.docker.mode|default('unknown', true) }} · AMD graphics configuration is not managed by DevFleet.</p><form method="post" action="/repair">{{ csrf() }}<button class="button ghost">Run non-destructive repair</button></form><details class="advanced"><summary>Advanced health records</summary><div class="details-grid"><pre>{{ status.docker|tojson(indent=2) }}</pre><pre>{{ status.backup|tojson(indent=2) }}</pre><pre>{{ status.ollama|tojson(indent=2) }}</pre></div></details></article><article class="panel"><div class="eyebrow">RECOVERY</div><h2>Quarantine</h2><p class="muted">Quarantined workspaces are reversible and remain outside active projects.</p>{% for q in quarantine %}<form method="post" action="/quarantine/restore">{{ csrf() }}<input type="hidden" name="name" value="{{ q.name }}"><button class="button ghost">Restore {{ q.name }}</button></form>{% else %}<p class="muted">No quarantined projects.</p>{% endfor %}<details class="advanced"><summary>Peer diagnostics</summary><pre>{{ peer|tojson(indent=2) }}</pre></details></article></section>
    {% endif %}
  </main>
</div>
</body>
</html>

```


## FILE: source/app/templates/login.html

SHA256: 2545054327bb69d476b2fdb4b28ed75b12e1d30222a34cab8a46ebb82d2af4d1 | Bytes: 1660 | Git mode: 100644

```
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="dark">
  <title>Sign in · DevFleet</title>
<link rel="stylesheet" href="/static/style.css?v={{ version|default('unknown', true) }}-r5">
</head>
<body class="login-page">
  <main class="login-shell">
    <section class="login-brand" aria-labelledby="brand-title">
      <p class="eyebrow">SAFE REMOTE DEVELOPMENT</p>
      <h1 id="brand-title">DevFleet</h1>
      <p>Manage isolated development environments from one protected control plane.</p>
    </section>
    <section class="login-card" aria-labelledby="login-title">
      <p class="eyebrow">DEVELOPER ACCESS</p>
      <h2 id="login-title">Sign in to DevFleet</h2>
      {% if error %}<p class="login-error" role="alert">{{ error }}</p>{% endif %}
      <form method="post" action="/login">
        <input type="hidden" name="csrf_token" value="{{ csrf_token }}">
        <input type="hidden" name="next" value="{{ next }}">
        <label for="username">Username</label>
        <input id="username" name="username" autocomplete="username" required autofocus>
        <label for="password">Password</label>
        <input id="password" type="password" name="password" autocomplete="current-password" required>
        <label class="login-remember"><input type="checkbox" name="keep_signed_in" value="true"> Keep me signed in</label>
        <button class="button primary login-submit" type="submit">Sign in</button>
      </form>
      <p class="login-footer">DevFleet v{{ version }}</p>
    </section>
  </main>
</body>
</html>

```


## FILE: source/client/Configure-DockerContext.ps1

SHA256: d27ae17fba723ce41695a05d644d6ac5e4eb99557f6ff9296005e23e8e587058 | Bytes: 916 | Git mode: 100644

```
[CmdletBinding()]param([string]$ContextName='Codexdevvm')
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;Import-Module (Join-Path $root 'windows\DevFleet.Common.psm1') -Force;$config=Get-DevFleetConfig;if(-not(Get-Command docker.exe -ErrorAction SilentlyContinue)){throw 'Docker CLI is optional but must be installed to create a context. Docker Desktop is not required for main workloads.'};$uri="ssh://devrunner@$($config.Primary.SshAlias)";$exists=& docker.exe context ls --format '{{.Name}}'|Where-Object{$_ -eq $ContextName};if($exists){& docker.exe context update $ContextName --docker "host=$uri" --description 'DevFleet CodexDevVM over SSH'}else{& docker.exe context create $ContextName --docker "host=$uri" --description 'DevFleet CodexDevVM over SSH'};if($LASTEXITCODE){throw 'Docker context creation failed.'};Write-Host "Use: docker --context $ContextName ps" -ForegroundColor Green

```


## FILE: source/client/Configure-SSH.ps1

SHA256: 9376560ad72753307bf3ce174039807ad00e2bb13b12b9f6c2087ff630e141dc | Bytes: 1699 | Git mode: 100644

```
[CmdletBinding()]param([switch]$SkipConnectivityTest)
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;Import-Module (Join-Path $root 'windows\DevFleet.Common.psm1') -Force;$config=Get-DevFleetConfig;$key=Get-OrCreateDevFleetSshKey;$sshDir=Join-Path $env:USERPROFILE '.ssh';New-Item -ItemType Directory $sshDir -Force|Out-Null;$configFile=Join-Path $sshDir 'config';$begin='# BEGIN DEVFLEET MANAGED';$end='# END DEVFLEET MANAGED';$existing=if(Test-Path $configFile){Get-Content $configFile -Raw}else{''}
function Resolve-Host([string]$Instance){$mp=Get-MultipassExe;$raw=Invoke-External $mp @('exec',$Instance,'--','tailscale','ip','-4') -Capture;return ($raw -split "`n"|Select-Object -First 1).Trim()}
$blocks=@();foreach($n in @($config.Primary,$config.Failover)){try{$hostName=Resolve-Host $n.InstanceName}catch{$hostName=$n.InstanceName};$blocks+=@"
Host $($n.SshAlias)
    HostName $hostName
    User devrunner
    IdentityFile $($key.Replace('\','/'))
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 4
    TCPKeepAlive yes
    Compression yes
    ForwardAgent no
"@}
$managed=$begin+"`n"+($blocks -join "`n")+$end;if($existing -match '(?s)# BEGIN DEVFLEET MANAGED.*?# END DEVFLEET MANAGED'){$existing=[regex]::Replace($existing,'(?s)# BEGIN DEVFLEET MANAGED.*?# END DEVFLEET MANAGED',$managed)}else{$existing=$existing.TrimEnd()+"`n`n"+$managed+"`n"};Set-Content $configFile $existing -Encoding utf8;if(-not $SkipConnectivityTest){& ssh.exe -o BatchMode=yes -o ConnectTimeout=10 $config.Primary.SshAlias 'echo DevFleet SSH OK'};Write-Host "SSH aliases configured: $($config.Primary.SshAlias), $($config.Failover.SshAlias)" -ForegroundColor Green

```


## FILE: source/client/Configure-VSCode.ps1

SHA256: 38e8948c6ae1e6f3c9b5d605d5650666939fbe477d23b9b2c9329fdc22b92ad1 | Bytes: 950 | Git mode: 100644

```
[CmdletBinding()]param([string[]]$ExtensionSets=@('core'))
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;Import-Module (Join-Path $root 'windows\DevFleet.Common.psm1') -Force;$code=Get-VsCodeCli -AllowPerUser;if(-not $code){throw 'VS Code CLI was not found.'};$settingsDir=Join-Path $env:APPDATA 'Code\User';New-Item -ItemType Directory $settingsDir -Force|Out-Null;$source=Join-Path $PSScriptRoot 'vscode-settings.jsonc';$dest=Join-Path $settingsDir 'devfleet-settings.reference.jsonc';Copy-Item $source $dest -Force;foreach($set in $ExtensionSets){$list=Join-Path $PSScriptRoot "vscode-extensions-$set.txt";if(-not(Test-Path $list)){throw "Unknown extension set: $set"};foreach($ext in Get-Content $list){if($ext.Trim()){& $code --install-extension $ext.Trim() --force|Out-Null}}};Write-Host "VS Code extensions installed. Reference settings copied to $dest; merge reviewed values into settings.json." -ForegroundColor Green

```


## FILE: source/client/ssh-config.example

SHA256: f299ee1509445c514d3faf5d91db10f071768f6f62b5cc90223856bf2afbdeff | Bytes: 258 | Git mode: 100644

```
Host CodexDevVM
    HostName <PRIMARY_VM_TAILSCALE_NAME_OR_IP>
    User devrunner
    IdentityFile ~/.ssh/<DEVFLEET_KEY>
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 4
    TCPKeepAlive yes
    Compression yes
    ForwardAgent no

```


## FILE: source/client/vscode-extensions-core.txt

SHA256: 4cd73e74d6ab46ccbe37cb08c46200aa203747f3b6ac79bb823a1c03226911c1 | Bytes: 79 | Git mode: 100644

```
ms-vscode-remote.remote-ssh
ms-vscode-remote.remote-containers
eamodio.gitlens

```


## FILE: source/client/vscode-extensions-enterprise.txt

SHA256: 56eee44c27cdc6b543a8f58f580629bc9197a7123a74d4f05f063aac54745eb9 | Bytes: 49 | Git mode: 100644

```
ms-dotnettools.csdevkit
vscjava.vscode-java-pack

```


## FILE: source/client/vscode-extensions-python.txt

SHA256: aaa364399deda68c33ac158dbf32dad3dc4a4a522f66567df618d7bb3a48e131 | Bytes: 64 | Git mode: 100644

```
ms-python.python
charliermarsh.ruff
ms-python.mypy-type-checker

```


## FILE: source/client/vscode-extensions-systems.txt

SHA256: 25b7b8985b0071eeaa9a69e1304dec94beb5919b14f1303a6353124d2c3455c8 | Bytes: 53 | Git mode: 100644

```
golang.go
rust-lang.rust-analyzer
ms-vscode.cpptools

```


## FILE: source/client/vscode-extensions-web.txt

SHA256: 8eefa88fd78c091f9ac23130aef1399a649929fc6a895a05be4f3742c0aa874d | Bytes: 46 | Git mode: 100644

```
dbaeumer.vscode-eslint
esbenp.prettier-vscode

```


## FILE: source/client/vscode-settings.jsonc

SHA256: c5b88bbcff8c96b667cb46ea26eaabfb7336f2d7b5243f7a528553b825da0cf9 | Bytes: 882 | Git mode: 100644

```
{
  "remote.SSH.connectTimeout": 30,
  "remote.SSH.useLocalServer": true,
  "terminal.integrated.defaultProfile.windows": "PowerShell",
  "git.autofetch": true,
  "git.detectSubmodules": false,
  "files.watcherExclude": {"**/.git/objects/**": true,"**/node_modules/**": true,"**/.venv/**": true,"**/target/**": true,"**/.next/**": true,"**/.cache/**": true,"**/.ai-bridge/local-agent/**": true,"**/models/**": true,"**/data/generated/**": true},
  "search.exclude": {"**/node_modules": true,"**/.venv": true,"**/target": true,"**/.next": true,"**/dist": true,"**/build": true,"**/coverage": true,"**/.cache": true,"**/.ai-bridge/local-agent": true,"**/models": true,"**/*.bin": true,"**/*.safetensors": true},
  "python.analysis.exclude": ["**/.venv","**/.ai-bridge/local-agent","**/data/generated"],
  "typescript.tsserver.maxTsServerMemory": 4096,
  "editor.formatOnSave": true
}

```


## FILE: source/cloud-init/compute.yaml

SHA256: 00316cd0d11900a961163b07a24f26e9ebfc71830100847ce2cc10ef650ea4cf | Bytes: 1847 | Git mode: 100644

```
#cloud-config
hostname: __NODE_NAME__
manage_etc_hosts: true
package_update: true
package_upgrade: false
packages:
  - unzip
  - curl
  - ca-certificates
  - gnupg
  - jq
  - git
  - gh
  - openssh-server
  - python3
  - python3-venv
  - python3-pip
  - uidmap
  - dbus-user-session
  - slirp4netns
  - fuse-overlayfs
  - iptables
  - ufw
  - fail2ban
  - unattended-upgrades
users:
  - default
  - name: devrunner
    gecos: DevFleet restricted development user
    groups: [users]
    shell: /bin/bash
    lock_passwd: true
    sudo: []
write_files:
  - path: /etc/wsl.conf
    permissions: !!str 0644
    content: |
      [automount]
      enabled=false
      [interop]
      enabled=false
  - path: /etc/ssh/sshd_config.d/60-devfleet.conf
    permissions: !!str 0644
    content: |
      PasswordAuthentication no
      PermitRootLogin no
      AllowUsers ubuntu devrunner
      X11Forwarding no
      AllowAgentForwarding no
      AllowTcpForwarding yes
  - path: /etc/apt/apt.conf.d/20auto-upgrades
    permissions: !!str 0644
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";
runcmd:
  - systemctl enable --now ssh
  - systemctl enable --now fail2ban
  - loginctl enable-linger devrunner
  - install -d -o devrunner -g devrunner -m 0700 /home/devrunner/.ssh
  # DevFleet adds its distinct managed operator key after bootstrap.  Never
  # copy the administrator account's authorized_keys into devrunner.
  - touch /home/devrunner/.ssh/authorized_keys
  - chown devrunner:devrunner /home/devrunner/.ssh/authorized_keys
  - chmod 0600 /home/devrunner/.ssh/authorized_keys
  - sudo -u devrunner git config --global user.name __GIT_NAME_SHELL__
  - sudo -u devrunner git config --global user.email __GIT_EMAIL_SHELL__
final_message: "DevFleet base cloud-init complete for __NODE_ROLE__."

```


## FILE: source/cloud-init/vault.yaml

SHA256: 02799e2f3cac7df71db945030cce0d122d3663564db761197ade7e34d09f18ca | Bytes: 2314 | Git mode: 100644

```
#cloud-config
hostname: __NODE_NAME__
manage_etc_hosts: true
package_update: true
package_upgrade: false
packages:
  - unzip
  - curl
  - ca-certificates
  - gnupg
  - jq
  - openssh-server
  - apache2-utils
  - ufw
  - fail2ban
  - unattended-upgrades
users:
  - default
  - name: resticvault
    gecos: DevFleet backup vault service
    system: true
    shell: /usr/sbin/nologin
    homedir: /srv/restic
write_files:
  - path: /usr/local/sbin/devfleet-install-vault-tailscale
    permissions: !!str 0700
    content: |
      #!/usr/bin/env bash
      set -Eeuo pipefail
      export DEBIAN_FRONTEND=noninteractive
      . /etc/os-release
      [[ "$ID" == ubuntu && "$VERSION_CODENAME" =~ ^[a-z]+$ ]] || exit 4
      key=$(mktemp)
      trap 'rm -f -- "$key"' EXIT
      curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" -o "$key"
      observed=$(gpg --show-keys --with-colons "$key" | awk -F: '$1=="pub"{count++;pending=1;next} pending && $1=="fpr"{fingerprint=toupper($10);pending=0} END{if(count!=1 || pending || length(fingerprint)!=40)exit 4;print fingerprint}')
      [[ "$observed" == '__TAILSCALE_SIGNING_FINGERPRINT__' ]] || { echo 'Tailscale signing-key identity mismatch' >&2; exit 4; }
      install -m 0644 "$key" /usr/share/keyrings/tailscale-archive-keyring.gpg
      printf 'deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu %s main\n' "$VERSION_CODENAME" > /etc/apt/sources.list.d/tailscale.list
      apt-get update
      apt-get install -y tailscale
      systemctl enable --now tailscaled
  - path: /etc/ssh/sshd_config.d/60-devfleet-vault.conf
    permissions: !!str 0644
    content: |
      PasswordAuthentication no
      PermitRootLogin no
      AllowUsers ubuntu
      X11Forwarding no
      AllowAgentForwarding no
  - path: /etc/apt/apt.conf.d/20auto-upgrades
    permissions: !!str 0644
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";
runcmd:
  - [timeout, --signal=TERM, --kill-after=10s, 900s, /usr/local/sbin/devfleet-install-vault-tailscale]
  - systemctl enable --now ssh
  - systemctl enable --now fail2ban
final_message: "DevFleet vault base cloud-init complete."

```


## FILE: source/config/compose-security-policy.json

SHA256: e2db65056b5030e3547c8659563bdb0db197d71d6c6dfd50a609efddbd514279 | Bytes: 758 | Git mode: 100644

```
{
  "schemaVersion": 1,
  "policyVersion": "2.0.0",
  "compose": {
    "supportedSchema": "compose-spec-safe-subset-2026-08",
    "resolver": "none",
    "transitiveResolution": "fail-closed",
    "blockedFeatures": ["include", "extends", "use_api_socket", "volumes_from", "provider", "lifecycle-hooks", "host-backed-secrets-configs"],
    "maxReferenceDepth": 8,
    "maxReferenceFiles": 256,
    "maxReferenceBytes": 33554432,
    "environmentInterpolation": "blocked",
    "unknownExecutionFields": "blocked"
  },
  "devcontainer": {
    "supportedSchema": "devcontainer-json-safe-subset-2026-08",
    "jsonc": true,
    "runArgs": "reject-by-default",
    "features": "reject-unresolved",
    "hostCommands": "blocked",
    "hostMounts": "blocked"
  }
}

```


## FILE: source/config/devfleet.config.json

SHA256: e6d6d298e5437f994eeab4579253b1ef1bf49fe2ebeeffe01cd6e9ca30c65b5d | Bytes: 3298 | Git mode: 100644

```
{
  "SchemaVersion": 2,
  "PackageVersion": "1.2.13",
  "ClusterName": "dylan-devfleet",
  "Hosts": {
    "DesktopFriendlyName": "DevFleet Primary",
    "LaptopFriendlyName": "DevFleet Surrogate"
  },
  "Git": {
    "UserName": "Dylan Mellor",
    "Email": "dylanmellor@gmail.com",
    "DefaultOwner": "MulattoTech"
  },
  "Development": {
    "Profile": "balanced",
    "EnableSharedBuildCaches": true,
    "EnableAnalyzerCache": true,
    "EnableTrustedOrchestrator": true,
    "AllowLoopbackPortPublishing": true,
    "AllowTailnetPortPublishing": true,
    "AutoStartCodexPro": true,
    "AutoStartProjectServices": true,
    "RequireConfirmationForRoutineRebuild": false,
    "RequireConfirmationForRoutineRepair": false,
    "BackupBeforeRebuild": false,
    "BackupBeforeQuarantine": true
  },
  "Docker": {
    "PrimaryMode": "rootless",
    "FailoverMode": "rootless",
    "EnableBuildKit": true,
    "EnableSharedBuildCache": true,
    "EnableRegistryCache": false,
    "RootfulModeAcknowledged": false
  },
  "CodexPro": {
    "Mode": "project-scoped-adapter",
    "AutoBootstrap": true,
    "ToolCards": true,
    "DefaultHost": "127.0.0.1",
    "DefaultPort": 8787,
    "SharedTransportStatus": "adapter-only-until-a-verified-multi-workspace-registration-interface-is-exposed"
  },
  "Ollama": {
    "BaseUrl": "",
    "PreferredBaseUrl": "",
    "Model": "oaksight-gpt-oss-20b:latest",
    "Profile": "stable-interactive",
    "ProfilesFile": "config/ollama-profiles.json"
  },
  "Network": {
    "PortalPort": 8787,
    "VaultPort": 8000,
    "RequireTailscale": true,
    "TailnetCidr": "100.64.0.0/10",
    "PublicBindingAllowed": false
  },
  "Primary": {
    "InstanceName": "devfleet-primary",
    "FriendlyName": "CodexDevVM",
    "SshAlias": "CodexDevVM",
    "UbuntuImage": "24.04",
    "Cpus": 12,
      "Memory": "12G",
    "Disk": "220G"
  },
  "Failover": {
    "InstanceName": "devfleet-failover",
    "FriendlyName": "DevFleetFailover",
    "SshAlias": "DevFleetFailover",
    "UbuntuImage": "24.04",
    "Cpus": 4,
    "Memory": "8G",
    "Disk": "70G"
  },
  "Vault": {
    "InstanceName": "devfleet-vault",
    "FriendlyName": "DevFleetVault",
    "SshAlias": "DevFleetVault",
    "UbuntuImage": "24.04",
    "Cpus": 2,
    "Memory": "3G",
    "Disk": "160G"
  },
  "RoleProfiles": {
    "LaptopSurrogate": {
      "Recommended": {
        "FailoverMemory": "5G",
        "VaultMemory": "2G"
      },
      "MinimumTested": {
        "FailoverMemory": "4G",
        "VaultMemory": "2G"
      }
    }
  },
  "Backup": {
    "IntervalMinutes": 15,
    "KeepWithin": "90d",
    "QuarantineDays": 30,
    "RequireVerifiedBackupBeforeQuarantine": true,
    "OfflineExportEnabled": true
  },
  "Safety": {
    "DisableHostMounts": true,
    "AllowDockerTcp": false,
    "AllowPermanentDeleteInUi": false,
    "RequireRootlessDocker": false,
    "BlockWindowsPaths": true,
    "BlockUncPaths": true,
    "BlockWorkspaceEscape": true,
    "OrdinaryContainersMayMountDockerSocket": false
  },
  "LanguagePolicy": {
    "DefaultAutomation": "python",
    "DefaultWindowsAdministration": "powershell",
    "DefaultLinuxAdministration": "bash-or-python",
    "DefaultCrossPlatformCli": "go",
    "DefaultWebFrontend": "typescript",
    "DefaultRapidApi": "python-fastapi"
  }
}

```


## FILE: source/config/ollama-profiles.json

SHA256: 3e3b592adfe477dbc58c3995f8f34602f14d4145ef01b9b4cad117053c32b148 | Bytes: 961 | Git mode: 100644

```
{
  "stable-interactive": {
    "Description": "Low-latency coding and one or two concurrent requests.",
    "Environment": {
      "OLLAMA_CONTEXT_LENGTH": "32768",
      "OLLAMA_NUM_PARALLEL": "2",
      "OLLAMA_MAX_LOADED_MODELS": "1",
      "OLLAMA_MAX_QUEUE": "64",
      "OLLAMA_KEEP_ALIVE": "15m"
    }
  },
  "large-context": {
    "Description": "One primary repository-analysis task with reduced concurrency.",
    "Environment": {
      "OLLAMA_CONTEXT_LENGTH": "65536",
      "OLLAMA_NUM_PARALLEL": "1",
      "OLLAMA_MAX_LOADED_MODELS": "1",
      "OLLAMA_MAX_QUEUE": "32",
      "OLLAMA_KEEP_ALIVE": "30m"
    }
  },
  "parallel-agents": {
    "Description": "Several concurrent CodexPro requests using smaller per-request contexts.",
    "Environment": {
      "OLLAMA_CONTEXT_LENGTH": "16384",
      "OLLAMA_NUM_PARALLEL": "4",
      "OLLAMA_MAX_LOADED_MODELS": "1",
      "OLLAMA_MAX_QUEUE": "128",
      "OLLAMA_KEEP_ALIVE": "15m"
    }
  }
}

```


## FILE: source/config/resource-policy.json

SHA256: 8e93275c24263491338ac3939a808acdf07f15c3d0c45badda90edb51646de8d | Bytes: 214 | Git mode: 100644

```
{
  "schemaVersion": 1,
  "policyVersion": "1.0.0",
  "physicalFloorMinGiB": 8,
  "physicalFloorPercent": 0.10,
  "commitHeadroomFloorMinGiB": 16,
  "commitHeadroomPercent": 0.20,
  "commitUsageLimitPercent": 80
}

```


## FILE: source/dependencies.json

SHA256: b939c07de544806e87b8324c050a1a3aff6baac8b36fac57201d917ea8810b46 | Bytes: 19463 | Git mode: 100644

```
{
  "schemaVersion": 1,
  "manifestVersion": "1.2.13",
  "supportedProfile": "Windows 11 Pro x64, Internet-connected, administrator/UAC, hardware virtualization",
  "dependencies": [
    {
      "id": "powershell7",
      "displayName": "PowerShell 7",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["bootstrap", "installer"],
      "minimumSupportedVersion": "7.4.0",
      "maximumMajor": 7,
      "executableProbes": ["pwsh.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Microsoft\\PowerShellCore\\InstalledVersions"],
      "appPathsProbes": ["pwsh.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\PowerShell\\7\\pwsh.exe", "%LocalAppData%\\Microsoft\\powershell\\pwsh.exe"],
      "wingetPackageId": "Microsoft.PowerShell",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/PowerShell/PowerShell/releases/latest", "allowedHosts": ["api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"], "assetRegex": "^PowerShell-7\\.[0-9.]+-win-x64\\.msi$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".msi"] },
      "silentInstallArguments": ["/qn", "/norestart"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["-NoProfile", "-NonInteractive", "-Command", "$PSVersionTable.PSVersion.ToString()"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, registry and known locations",
      "postInstallVersionVerification": "pwsh version >= minimum and major policy"
    },
    {
      "id": "git",
      "displayName": "Git",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["source-control", "guest-bootstrap"],
      "minimumSupportedVersion": "2.40.0",
      "maximumMajor": null,
      "executableProbes": ["git.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\GitForWindows", "HKCU:\\SOFTWARE\\GitForWindows"],
      "appPathsProbes": ["git.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Git\\cmd\\git.exe", "%LocalAppData%\\Programs\\Git\\cmd\\git.exe"],
      "wingetPackageId": "Git.Git",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/git-for-windows/git/releases/latest", "allowedHosts": ["api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"], "assetRegex": "^Git-[0-9.]+-64-bit\\.exe$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Johannes Schindelin, O=Johannes Schindelin, L=Bruehl, C=DE"], "extensions": [".exe"] },
      "silentInstallArguments": ["/VERYSILENT", "/NORESTART", "/MERGETASKS=!runcode"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["--version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, registry and known locations",
      "postInstallVersionVerification": "git --version >= minimum"
    },
    {
      "id": "openssh-client",
      "displayName": "OpenSSH Client",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["ssh", "guest-bootstrap"],
      "minimumSupportedVersion": "8.1.0",
      "maximumMajor": null,
      "executableProbes": ["ssh.exe"],
      "registryProbes": [],
      "appPathsProbes": ["ssh.exe"],
      "knownVendorInstallLocations": ["%WINDIR%\\System32\\OpenSSH\\ssh.exe"],
      "wingetPackageId": null,
      "directOfficialVendorResolver": { "type": "windows-capability", "metadataUri": "https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse", "allowedHosts": ["learn.microsoft.com"], "assetRegex": null },
      "installerAuthenticityPolicy": { "required": false, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".exe"] },
      "silentInstallArguments": [],
      "rebootSemantics": "capability-dependent",
      "versionProbe": { "arguments": ["-V"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, capability and known location",
      "postInstallVersionVerification": "ssh -V >= minimum"
    },
    {
      "id": "multipass",
      "displayName": "Multipass",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["virtualization", "ubuntu-provisioning"],
      "minimumSupportedVersion": "1.13.0",
      "maximumMajor": 1,
      "executableProbes": ["multipass.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Canonical\\Multipass"],
      "appPathsProbes": ["multipass.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Multipass\\bin\\multipass.exe", "%ProgramFiles(x86)%\\Multipass\\bin\\multipass.exe"],
      "wingetPackageId": "Canonical.Multipass",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/canonical/multipass/releases/latest", "allowedHosts": ["api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"], "assetRegex": "(?i)^multipass.*win.*64.*\\.(msi|exe)$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=CANONICAL GROUP LIMITED, O=CANONICAL GROUP LIMITED, L=London, C=GB"], "installedExecutableTrust": "signed-installer-locked-path", "extensions": [".msi", ".exe"] },
      "silentInstallArguments": ["/quiet", "/norestart"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["version"], "regex": "(?m)^multipass\\s+(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, registry and known vendor locations",
      "postInstallVersionVerification": "multipass version and multipass list both succeed"
    },
    {
      "id": "virtualization-backend",
      "displayName": "Virtualization backend",
      "classification": "CORE_REQUIRED",
      "required": true,
      "roles": ["Desktop", "Laptop"],
      "features": ["multipass"],
      "minimumSupportedVersion": "0.0.0",
      "maximumMajor": null,
      "executableProbes": ["systeminfo.exe"],
      "registryProbes": [],
      "appPathsProbes": [],
      "knownVendorInstallLocations": [],
      "wingetPackageId": null,
      "directOfficialVendorResolver": { "type": "windows-feature-or-virtualbox", "metadataUri": "https://documentation.ubuntu.com/multipass/latest/how-to-guides/install-multipass", "allowedHosts": ["documentation.ubuntu.com"], "assetRegex": null },
      "installerAuthenticityPolicy": { "required": false, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US", "CN=Oracle Corporation, O=Oracle Corporation, L=Redwood City, S=California, C=US"], "extensions": [] },
      "silentInstallArguments": [],
      "rebootSemantics": "feature-dependent",
      "versionProbe": { "arguments": ["/FO", "LIST"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "verify Hyper-V capability or VirtualBox installation and Multipass driver",
      "postInstallVersionVerification": "backend capability and selected driver are usable"
    },
    {
      "id": "virtualbox",
      "displayName": "Oracle VirtualBox",
      "classification": "FEATURE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["multipass", "windows-home"],
      "minimumSupportedVersion": "7.0.0",
      "maximumMajor": null,
      "executableProbes": ["VBoxManage.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Oracle\\VirtualBox", "HKLM:\\SOFTWARE\\WOW6432Node\\Oracle\\VirtualBox"],
      "appPathsProbes": ["VBoxManage.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Oracle\\VirtualBox\\VBoxManage.exe", "%ProgramFiles(x86)%\\Oracle\\VirtualBox\\VBoxManage.exe"],
      "wingetPackageId": "Oracle.VirtualBox",
      "directOfficialVendorResolver": { "type": "official-download-page", "metadataUri": "https://www.virtualbox.org/wiki/Downloads", "allowedHosts": ["www.virtualbox.org", "download.virtualbox.org"], "assetRegex": "(?i)^VirtualBox-[0-9.]+-Win\\.exe$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Oracle Corporation, O=Oracle Corporation, L=Redwood City, S=California, C=US"], "extensions": [".exe"] },
      "silentInstallArguments": ["--silent", "--msiparams", "REBOOT=ReallySuppress"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["--version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover VBoxManage from HKLM App Paths and canonical Oracle machine locations",
      "postInstallVersionVerification": "VBoxManage --version >= minimum and Multipass virtualbox driver is selected"
    },
    {
      "id": "tailscale",
      "displayName": "Tailscale",
      "classification": "ROLE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["network-pairing", "failover", "vault"],
      "minimumSupportedVersion": "1.60.0",
      "maximumMajor": 1,
      "executableProbes": ["tailscale.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Tailscale"],
      "appPathsProbes": ["tailscale.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Tailscale\\tailscale.exe", "%ProgramFiles(x86)%\\Tailscale\\tailscale.exe"],
      "wingetPackageId": "Tailscale.Tailscale",
      "directOfficialVendorResolver": { "type": "official-download-page", "metadataUri": "https://tailscale.com/download/windows", "allowedHosts": ["tailscale.com", "pkgs.tailscale.com"], "assetRegex": "(?i)^tailscale-setup-latest\\.(exe|msi)$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Tailscale Inc., O=Tailscale Inc., L=Toronto, S=Ontario, C=CA, SERIALNUMBER=1131559-5, OID.2.5.4.15=Private Organization, OID.1.3.6.1.4.1.311.60.2.1.3=CA"], "extensions": [".exe", ".msi"] },
      "silentInstallArguments": ["/quiet"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths, registry and known locations",
      "postInstallVersionVerification": "tailscale version succeeds; auth remains explicit/deferred"
    },
    {
      "id": "vscode",
      "displayName": "VS Code",
      "classification": "RECOMMENDED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["editor", "remote-development"],
      "minimumSupportedVersion": "1.90.0",
      "maximumMajor": null,
      "executableProbes": ["code.cmd", "code.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"],
      "appPathsProbes": ["code.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\Microsoft VS Code\\bin\\code.cmd", "%LocalAppData%\\Programs\\Microsoft VS Code\\bin\\code.cmd"],
      "wingetPackageId": "Microsoft.VisualStudioCode",
      "directOfficialVendorResolver": { "type": "official-download-page", "metadataUri": "https://code.visualstudio.com/Download", "directUri": "https://update.code.visualstudio.com/latest/win32-x64/stable", "allowedHosts": ["code.visualstudio.com", "update.code.visualstudio.com", "vscode.download.prss.microsoft.com"], "assetRegex": "(?i)^VSCodeSetup-x64-[0-9.]+\\.exe$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".exe"] },
      "silentInstallArguments": ["/VERYSILENT", "/NORESTART"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["--version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover code.cmd/code.exe via PATH, registry and known locations",
      "postInstallVersionVerification": "code --version >= minimum"
    },
    {
      "id": "github-cli",
      "displayName": "GitHub CLI",
      "classification": "RECOMMENDED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["GitHub integration"],
      "minimumSupportedVersion": "2.40.0",
      "maximumMajor": null,
      "executableProbes": ["gh.exe"],
      "registryProbes": [],
      "appPathsProbes": ["gh.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\GitHub CLI\\gh.exe", "%LocalAppData%\\Programs\\GitHub CLI\\gh.exe"],
      "wingetPackageId": "GitHub.cli",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/cli/cli/releases/latest", "allowedHosts": ["api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"], "assetRegex": "(?i)^gh_.*_windows_amd64\\.msi$" },
      "installerAuthenticityPolicy": { "required": true, "allowedSignerSubjectsExact": ["CN=GitHub, Inc., O=GitHub, Inc., L=San Francisco, S=California, C=US"], "extensions": [".msi"] },
      "silentInstallArguments": ["/qn", "/norestart"],
      "rebootSemantics": "0-or-3010",
      "versionProbe": { "arguments": ["--version"], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, App Paths and known locations",
      "postInstallVersionVerification": "gh --version >= minimum"
    },
    {
      "id": "sevenzip",
      "displayName": "7-Zip",
      "classification": "OPTIONAL",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["encrypted-transfer-bundle"],
      "minimumSupportedVersion": "23.0.0",
      "maximumMajor": null,
      "executableProbes": ["7z.exe"],
      "registryProbes": ["HKLM:\\SOFTWARE\\7-Zip", "HKLM:\\SOFTWARE\\WOW6432Node\\7-Zip"],
      "appPathsProbes": ["7z.exe"],
      "knownVendorInstallLocations": ["%ProgramFiles%\\7-Zip\\7z.exe", "%ProgramFiles(x86)%\\7-Zip\\7z.exe"],
      "wingetPackageId": "7zip.7zip",
      "directOfficialVendorResolver": { "type": "github-release", "metadataUri": "https://api.github.com/repos/ip7z/7zip/releases/latest", "officialPageUri": "https://www.7-zip.org/download.html", "expectedOwner": "ip7z", "expectedRepository": "7zip", "allowedHosts": ["api.github.com", "github.com", "release-assets.githubusercontent.com"], "assetRegex": "(?i)^7z\\d+-x64\\.exe$", "officialPageAssetRegex": "(?i)^7z\\d+-x64\\.exe$" },
      "installerAuthenticityPolicy": { "strategy": "VendorReleaseSha256", "required": true, "allowedSignerSubjectsExact": ["CN=Igor Pavlov"], "extensions": [".exe"] },
      "silentInstallArguments": ["/S"],
      "rebootSemantics": "0",
      "versionProbe": { "arguments": [], "regex": "(?<!\\d)(\\d+\\.\\d+(?:\\.\\d+){0,2})" },
      "postInstallExecutableDiscovery": "rediscover command, registry and known locations",
      "postInstallVersionVerification": "7z executable is present and responds"
    },
    {
      "id": "remote-ssh-extension",
      "displayName": "Remote SSH extension",
      "classification": "FEATURE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["remote-development"],
      "minimumSupportedVersion": "0.0.0",
      "maximumMajor": null,
      "executableProbes": ["code.cmd"],
      "registryProbes": [],
      "appPathsProbes": [],
      "knownVendorInstallLocations": [],
      "wingetPackageId": null,
      "directOfficialVendorResolver": { "type": "vscode-extension", "metadataUri": "https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh", "allowedHosts": ["marketplace.visualstudio.com"], "assetRegex": null },
      "installerAuthenticityPolicy": { "required": false, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".vsix"] },
      "silentInstallArguments": ["--install-extension", "ms-vscode-remote.remote-ssh", "--force"],
      "rebootSemantics": "0",
      "versionProbe": { "arguments": [], "regex": null },
      "postInstallExecutableDiscovery": "resolve VS Code CLI and inspect extension list",
      "postInstallVersionVerification": "code --list-extensions contains ms-vscode-remote.remote-ssh"
    },
    {
      "id": "remote-explorer-extension",
      "displayName": "Remote Explorer extension",
      "classification": "FEATURE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["remote-development"],
      "minimumSupportedVersion": "0.0.0",
      "maximumMajor": null,
      "executableProbes": ["code.cmd"],
      "registryProbes": [],
      "appPathsProbes": [],
      "knownVendorInstallLocations": [],
      "wingetPackageId": null,
      "directOfficialVendorResolver": { "type": "vscode-extension", "metadataUri": "https://marketplace.visualstudio.com/items?itemName=ms-vscode.remote-explorer", "allowedHosts": ["marketplace.visualstudio.com"], "assetRegex": null },
      "installerAuthenticityPolicy": { "required": false, "allowedSignerSubjectsExact": ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"], "extensions": [".vsix"] },
      "silentInstallArguments": ["--install-extension", "ms-vscode.remote-explorer", "--force"],
      "rebootSemantics": "0",
      "versionProbe": { "arguments": [], "regex": null },
      "postInstallExecutableDiscovery": "resolve VS Code CLI and inspect extension list",
      "postInstallVersionVerification": "code --list-extensions contains ms-vscode.remote-explorer"
    },
    {
      "id": "dev-containers-extension",
      "displayName": "Dev Containers extension",
      "classification": "FEATURE_REQUIRED",
      "required": false,
      "roles": ["Desktop", "Laptop"],
      "features": ["remote-development", "containers"],
      "minimumSupportedVersion": "0.0.0",
      "maximumMajor": null,
      "executableProbes": ["code.cmd"],
      "registryProbes": [],
      "appPath