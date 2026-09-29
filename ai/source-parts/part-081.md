# DevFleet source part 081

Full-source UTF-8 byte interval [3720000, 3766500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 97f98b5d07edfa1861868a66c14ada4023a37c38bd52d1cd0ff263ead6eb9116

<!-- BEGIN SOURCE SLICE -->
rong><p>{{ p.display_name|default(p.slug, true) }} is not currently running. Live metrics, application health, logs, and runtime actions are unavailable until the environment starts.</p></div>{{ project_action(p.slug,'start','Start Project','primary') }}</div>{% elif caps.runtime_transitioning %}<div class="project-state-banner transitioning" role="status"><div><strong>{{ lifecycle|replace('-', ' ')|title }}…</strong><p>Live tabs remain gated until the environment is running and ready.</p></div></div>{% elif lifecycle in ['unreachable','error'] %}<div class="project-state-banner error" role="alert"><div><strong>Runtime {{ lifecycle }}</strong><p>Live information is unavailable. Static configuration, backups, safety, activity, and settings remain usable.</p></div></div>{% endif %}<div class="project-hero-row"><span class="project-avatar huge">{{ (p.display_name|default(p.slug, true))[0]|upper }}</span><div><p class="eyebrow">PROJECT WORKSPACE</p><h2>{{ p.display_name|default(p.slug, true) }}</h2><p class="muted">{{ p.slug }} · {{ p.language|default('Existing project', true)|title }}{% if p.framework %} · {{ p.framework }}{% endif %}</p></div><div class="hero-status strong-state state-{{ lifecycle }}">{{ status_badge(lifecycle) }}<small>{{ caps.status_reason|default('Environment state is current.', true) }}</small></div></div><div class="quick-actions">{% if caps.can_stop %}{{ project_action(p.slug,'stop','Stop','ghost') }}{% elif caps.can_start %}{{ project_action(p.slug,'start','Start','primary') }}{% endif %}{% if caps.can_restart %}{{ project_action(p.slug,'restart','Restart','ghost') }}{% else %}<button class="button ghost disabled" type="button" disabled title="Start the project and wait for runtime readiness before restarting.">Restart unavailable</button>{% endif %}<a class="button ghost" href="/projects/{{ p.slug }}?tab=environment">Change environment</a><a class="button ghost" href="/projects/{{ p.slug }}?tab=settings">Project settings</a></div></section>
    <nav class="tabs" aria-label="Project sections"><a class="{{ 'active' if request.query_params.get('tab','overview') == 'overview' else '' }}" href="/projects/{{ p.slug }}?tab=overview">Overview</a><a class="{{ 'active' if request.query_params.get('tab') == 'environment' else '' }}" href="/projects/{{ p.slug }}?tab=environment">Environment</a><a class="{{ 'active' if request.query_params.get('tab') == 'logs' else '' }}" href="/projects/{{ p.slug }}?tab=logs">Logs</a><a class="{{ 'active' if request.query_params.get('tab') == 'backups' else '' }}" href="/projects/{{ p.slug }}?tab=backups">Backups</a><a class="{{ 'active' if request.query_params.get('tab') == 'safety' else '' }}" href="/projects/{{ p.slug }}?tab=safety">Safety</a><a class="{{ 'active' if request.query_params.get('tab') == 'isolate' else '' }}" href="/projects/{{ p.slug }}?tab=isolate">Isolate</a><a class="{{ 'active' if request.query_params.get('tab') == 'activity' else '' }}" href="/projects/{{ p.slug }}?tab=activity">Activity</a><a class="{{ 'active' if request.query_params.get('tab') == 'settings' else '' }}" href="/projects/{{ p.slug }}?tab=settings#advanced-controls">Advanced</a></nav>
    {% set project_tab = request.query_params.get('tab','overview') %}
    {% if project_tab == 'environment' %}
    <section class="panel environment-wizard-shell" data-existing-environment-wizard data-project-slug="{{ p.slug }}"><nav class="wizard-stage-nav" aria-label="Environment assignment stages"><button type="button" data-wizard-stage="environment">1. Environment</button><button type="button" data-wizard-stage="resources">2. Resources</button><button type="button" data-wizard-stage="review">3. Review</button><button type="button" data-wizard-stage="confirm">4. Confirm</button></nav><p class="muted" data-environment-preflight>Read-only preflight runs against the selected environment and resources.</p><fieldset class="custom-resource-controls" data-custom-resources><legend>Custom resources</legend><label>CPU<input type="number" name="custom_cpus" min="1" max="6" step="1" placeholder="CPU cores"></label><label>RAM GB<input type="number" name="custom_ram_gb" min="2" max="12" step="1" placeholder="RAM GB"></label><label>Disk GB<input type="number" name="custom_disk_gb" min="20" max="120" step="1" placeholder="Disk GB"></label><label>PID mode<select name="pid_mode"><option value="private">Private PID namespace</option></select></label><label>PID limit<input type="number" name="pid_limit" min="0" max="4096" value="4096"></label></fieldset><output data-environment-review aria-live="polite">CURRENT → NEW details will appear during Review.</output><div class="review-note"><strong>Confirm is deliberate</strong><span>Only a ready preflight enables the final assignment; a verified backup and fallback are retained if the operation rolls back.</span></div></section>
    <section class="content-grid two-thirds"><article class="panel"><div class="eyebrow">CURRENT DETECTION</div><h2>Environment</h2><p class="muted">DevFleet detected this workspace as {{ runtime_label(p)|lower }}. Review the runtime assignment, exact actions, and fallback behavior before confirming.</p><div class="environment-summary"><div><small>Environment type</small><strong>{{ runtime_label(p) }}</strong></div><div><small>Resources</small><strong>{{ p.resource_profile|default('standard', true)|title }}</strong></div><div><small>Health</small><strong>{{ p.health_status|default('unknown', true)|replace('-', ' ')|title }}</strong></div></div><form method="post" action="/projects/{{ p.slug }}/environment" class="environment-form">{{ csrf() }}<label>Environment type<select name="runtime_isolation"><option value="container" {{ 'selected' if p.runtime_isolation|default('container', true) == 'container' else '' }}>Project-isolated containers on shared host</option><option value="vm" {{ 'selected' if p.runtime_isolation|default('container', true) == 'vm' else '' }}>Dedicated project VM</option></select></label><label>Resources<select name="resource_profile">{% for name, profile in resource_profiles.items() %}<option value="{{ name }}" {{ 'selected' if p.resource_profile|default('standard', true) == name else '' }}>{{ profile.label }} · {{ profile.cpus }} CPU · {{ profile.memory }} · {{ profile.disk_gb }} GB</option>{% endfor %}<option value="custom" {{ 'selected' if p.resource_profile|default('', true) == 'custom' else '' }}>Custom</option></select></label><div class="review-note"><strong>Migration safety</strong><span>DevFleet creates a verified backup, validates capacity, verifies the workspace, and rolls metadata back if provisioning or import fails. Existing projects are never migrated automatically.</span></div><button class="button primary" type="submit" data-environment-confirm>Continue to Resources</button></form></article><article class="panel"><div class="eyebrow">DESTINATION</div><h3>Move to another node</h3><p class="muted">Ownership transfer is separate from runtime type. Offline destinations cannot be selected.</p>{% if peer.ok %}<form method="post" action="/projects/{{ p.slug }}/transfer-to-peer">{{ csrf() }}<button class="button ghost" type="submit">Move to DevFleetFailover</button></form>{% else %}<button class="button disabled" disabled title="Destination is offline">DevFleetFailover offline</button><p class="error">The failover node is unavailable, so transfer is disabled.</p>{% endif %}<details class="advanced"><summary>Advanced runtime record</summary><pre>{{ {'provider':p.runtime_provider|default('docker-compose',true),'runtime_id':p.runtime_id|default('',true),'runtime_address':p.runtime_address|default('',true),'host_id':p.host_id|default('',true),'limits':p.resource_limits|default({},true),'migration_snapshot':p.runtime_migration_snapshot|default('',true)}|tojson(indent=2) }}</pre></details></article></section>
    {{ resource_allocation(p) }}
    {% elif project_tab == 'logs' %}
     <section class="panel logs-panel"><div class="section-heading"><div><div class="eyebrow">RUNTIME LOGS</div><h2>Project logs</h2><p class="muted">Logs are fetched through the selected runtime provider; no host shell or machine API token is exposed.</p></div><span class="status-badge neutral">Session protected</span></div>{% if caps.can_query_logs %}<pre class="log-output" data-project-logs="{{ p.slug }}">Loading the latest bounded log tail…</pre>{% else %}<div class="runtime-unavailable" data-terminal-state="{{ lifecycle }}"><strong>Logs unavailable while {{ lifecycle }}</strong><p>{{ 'Start the project to view live logs.' if lifecycle == 'stopped' else 'Logs become available after the runtime reaches the ready state.' }}</p></div>{% endif %}<p class="muted">Stopped, transitioning, or unreachable runtimes use a terminal state instead of an indefinite spinner.</p></section>
    {% elif project_tab == 'backups' %}
    <section class="panel" data-backup-history data-project-slug="{{ p.slug }}"><div class="eyebrow">BACKUP HISTORY</div><h2>Verified restore points</h2><p class="muted">Each entry is identity-bound and re-hashed before restore. History loads through the session-authenticated endpoint.</p><div data-backup-list aria-live="polite">Loading backup history…</div></section>
    <section class="content-grid two-thirds"><article class="panel"><div class="eyebrow">RECOVERY ARTIFACTS</div><h2>Backups</h2><p class="muted">A backup is verified only when a recoverable workspace archive exists outside the runtime and its SHA-256 matches.</p><div class="environment-summary"><div><small>Status</small><strong>{{ p.backup_status|default('not-verified', true)|replace('-', ' ')|title }}</strong></div><div><small>Backup ID</small><strong>{{ p.backup_id|default('None', true) }}</strong></div><div><small>SHA-256</small><strong class="truncate">{{ p.backup_sha256|default('Not available', true) }}</strong></div></div>{{ project_action(p.slug,'backup','Create verified backup','primary') }}{% if p.backup_status == 'verified' %}<p class="success">Verified artifact: <code>{{ p.backup_path|default('recorded') }}</code></p>{% else %}<p class="warning">No verified workspace archive is recorded yet.</p>{% endif %}</article><article class="panel"><div class="eyebrow">RECOVERY POLICY</div><h3>Safe restore and deletion</h3><p class="muted">Restore is identity-bound and refuses to overwrite a non-empty workspace. Permanent deletion is blocked unless this project has a specific verified backup artifact.</p>{{ project_action(p.slug,'restore-vault','Restore copy from vault','ghost') }}<p class="muted">A Vault recovery creates a new recovered copy and preserves the original workspace.</p><details class="advanced"><summary>Backup manifest details</summary><pre>{{ {'manifest':p.backup_manifest|default('',true),'path':p.backup_path|default('',true),'sha256':p.backup_sha256|default('',true)}|tojson(indent=2) }}</pre></details></article></section>
    {% elif project_tab == 'safety' %}
    <section class="content-grid two-thirds"><article class="panel"><div class="eyebrow">SAFETY PROFILE</div><h2>Safety controls</h2><p class="muted">Choose the narrowest profile that supports the project. GPU passthrough, firewall changes, and host driver changes remain outside DevFleet.</p><form method="post" action="/projects/{{ p.slug }}/profile" class="form-grid">{{ csrf() }}<label>Profile<select name="profile"><option value="strict" {{ 'selected' if p.profile|default('balanced', true) == 'strict' else '' }}>Strict</option><option value="balanced" {{ 'selected' if p.profile|default('balanced', true) == 'balanced' else '' }}>Balanced</option><option value="fast" {{ 'selected' if p.profile|default('balanced', true) == 'fast' else '' }}>Fast Trusted</option></select></label><label class="checkbox-label"><input type="checkbox" name="confirm_fast"> Acknowledge Fast Trusted only if required</label><button class="button primary" type="submit">Save safety profile</button></form><div class="safety-list"><p><strong>Workspace boundary</strong> · {{ 'Protected' if not p.blockers else 'Review required' }}</p><p><strong>Runtime health</strong> · {{ p.health_scope|default('not-checked', true)|replace('-', ' ') }}</p><p><strong>Backup gate</strong> · {{ p.backup_status|default('not-verified', true)|replace('-', ' ') }}</p></div></article><article class="panel"><div class="eyebrow">ANALYZER</div><h3>Findings</h3>{% for finding in p.findings|default([], true) %}<p class="{{ finding.severity|default('info') }}"><strong>{{ finding.severity|default('info')|title }}</strong> · {{ finding.message }}</p>{% else %}<p class="success">No analyzer findings were recorded.</p>{% endfor %}<details class="advanced"><summary>Raw analyzer details</summary><pre>{{ p.findings|default([], true)|tojson(indent=2) }}</pre></details></article></section>
    <section class="panel advanced-permissions" data-fast-permissions><div class="eyebrow">FAST TRUSTED ADVANCED PERMISSIONS</div><h3>Explicit device and privileged access</h3><p class="muted">These permissions are inactive unless Fast Trusted is explicitly acknowledged. They remain disabled for Strict and Balanced profiles.</p><form method="post" action="/projects/{{ p.slug }}/profile" class="form-grid">{{ csrf() }}<input type="hidden" name="profile" value="fast"><label class="checkbox-label"><input type="checkbox" name="confirm_fast" required> I acknowledge Fast Trusted</label><label class="checkbox-label"><input type="checkbox" name="allow_devices" {{ 'checked' if p.allow_devices else '' }}> Allow devices</label><label class="checkbox-label"><input type="checkbox" name="allow_privileged" {{ 'checked' if p.allow_privileged else '' }}> Allow privileged runtime</label><button class="button ghost" type="submit">Save advanced permissions</button></form></section>
    {% elif project_tab == 'activity' %}
    <section class="panel"><div class="section-heading"><div><div class="eyebrow">PROJECT ACTIVITY</div><h2>Operations</h2></div><a href="/?view=activity">All activity →</a></div>{% for op in status.operations if op.project == p.slug %}<article class="operation-row" id="{{ op.id }}"><span class="activity-dot {{ 'bad' if op.state == 'failed' else 'ok' if op.state == 'completed' else 'warn' }}"></span><div><strong>{{ op.kind|replace('-', ' ')|title }}</strong><p class="muted">{{ op.message }} · {{ op.progress }}%</p></div><details class="advanced"><summary>Details</summary><pre>{{ op.log|tojson(indent=2) }}{{ op.result or op.error or '' }}</pre></details></article>{% else %}<p class="muted">No operations recorded for this project.</p>{% endfor %}</section>
    {% elif project_tab == 'settings' %}
     <section class="content-grid two-thirds"><article class="panel"><div class="eyebrow">SAFETY & SETUP</div><h2>Project settings</h2><div class="action-stack">{% if caps.can_run_runtime_action %}{{ project_action(p.slug,'runtime-health','Environment health','ghost') }}{{ project_action(p.slug,'bootstrap','Set up environment','ghost') }}{{ project_action(p.slug,'codexpro','Set up Codex','ghost') }}{% else %}<button class="button ghost disabled" type="button" disabled title="Runtime actions require a running, ready environment.">Runtime actions unavailable — {{ lifecycle }}</button>{% endif %}{{ project_action(p.slug,'analyze-force','Run safety scan','ghost') }}{{ project_action(p.slug,'backup','Create backup','ghost') }}</div><details class="advanced"><summary>Analyzer and runtime details</summary><pre>{{ {'capabilities':caps,'findings':p.findings|default([],true),'profile':p.profile|default('balanced',true),'analyzer_cache':p.analyzer_cache|default({},true),'backup_status':p.backup_status|default('not-verified',true),'lease':p.lease|default({},true)}|tojson(indent=2) }}</pre></details></article><article class="panel danger-panel"><div class="eyebrow danger-text">DANGER ZONE</div><h2>Delete project</h2><p class="muted">DevFleet will create and verify a backup before permanently deleting the project runtime and workspace.</p><form method="post" action="/projects/{{ p.slug }}/destroy" class="danger-form">{{ csrf() }}<label>Type the project slug<input name="confirm_slug" required placeholder="{{ p.slug }}"></label><label>Type the confirmation phrase<input name="confirm_phrase" required placeholder="DESTROY {{ p.slug }}"></label><button class="button danger" type="submit">Delete project permanently</button></form></article></section>
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
      "knownVendo