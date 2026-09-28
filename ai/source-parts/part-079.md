# DevFleet source part 079

Full-source UTF-8 byte interval [3627000, 3673500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 4bae6cc4082a906481da970253811bde936abcd34264d943d94ae948b4e0652f

<!-- BEGIN SOURCE SLICE -->
 {
    let slugLocked = Boolean(slug.value);
    let lastGenerated = slug.value;
    slug.addEventListener('input', () => { slugLocked = slug.value !== lastGenerated; });
    name.addEventListener('input', () => {
      if (slugLocked) return;
      const generated = name.value.normalize('NFKD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[^a-zA-Z0-9._\s-]/g, '')
        .trim().toLowerCase().replace(/[\s_]+/g, '-')
        .replace(/-+/g, '-').replace(/^-|-$/g, '').slice(0, 63);
      slug.value = generated; lastGenerated = generated;
    });
  }

  const advancedToggle = document.getElementById('advanced-mode-toggle');
  const advancedEnabled = localStorage.getItem('devfleet.advanced') === '1' || document.body.classList.contains('advanced-mode');
  document.body.classList.toggle('advanced-mode', advancedEnabled);
  if (advancedToggle) {
    advancedToggle.checked = advancedEnabled;
    advancedToggle.addEventListener('change', () => {
      const enabled = advancedToggle.checked;
      localStorage.setItem('devfleet.advanced', enabled ? '1' : '0');
      document.cookie = `devfleet_advanced=${enabled ? '1' : '0'}; Path=/; SameSite=Lax`;
      document.body.classList.toggle('advanced-mode', enabled);
    });
  }

  function initEnvironmentWizard() {
    const form = document.querySelector('[data-environment-wizard]');
    if (!form || form.dataset.enhanced === '1') return;
    form.dataset.enhanced = '1';
    const summary = form.querySelector('[data-review-summary]');
    const status = form.querySelector('[data-review-status]');
    const values = (name) => form.elements[name]?.value?.trim() || '';
    const render = () => {
      const profile = values('resource_profile');
      const cpu = values('custom_cpus') || 'auto';
      const ram = values('custom_ram_gb') || 'auto';
      const disk = values('custom_disk_gb') || 'auto';
      const pid = values('pid_limit') || '4096';
      const mode = values('pid_mode') || 'private';
      const runtime = values('runtime_isolation') || 'recommended runtime';
      const selected = profile ? `${profile} profile` : 'automatic recommendation';
      if (summary) summary.textContent = `${selected} · ${runtime} · ${cpu} CPU · ${ram} GB RAM · ${disk} GB disk · ${mode} PID · limit ${pid}`;
      if (status) { status.textContent = 'Review before provisioning'; status.className = 'status-badge neutral'; }
    };
    form.addEventListener('input', render); form.addEventListener('change', render); render();
  }

  function initExistingEnvironmentWizard() {
    const shell = document.querySelector('[data-existing-environment-wizard]');
    if (!shell || shell.dataset.enhanced === '1') return;
    const form = shell.parentElement.querySelector('form.environment-form');
    if (!form) return;
    shell.dataset.enhanced = '1';
    const slug = shell.dataset.projectSlug;
    const review = shell.querySelector('[data-environment-review]');
    const preflight = shell.querySelector('[data-environment-preflight]');
    const customNames = ['custom_cpus','custom_ram_gb','custom_disk_gb','pid_mode','pid_limit'];
    const profile = () => form.elements.resource_profile?.value || '';
    const confirmButton = form.querySelector('[data-environment-confirm]') || form.querySelector('button[type="submit"]');
    let lastPreflight = null;
    let stage = 'environment';
    const setStage = (next) => {
      stage = next; form.dataset.wizardStage = next;
      shell.querySelectorAll('[data-wizard-stage]').forEach((button) => {
        const active = button.dataset.wizardStage === next;
        button.classList.toggle('active', active); button.setAttribute('aria-current', active ? 'step' : 'false');
      });
      if (preflight && next === 'review') preflight.textContent = 'Running read-only workspace and capacity preflight…';
      if (confirmButton) confirmButton.textContent = next === 'confirm' ? 'Confirm environment assignment' : `Continue to ${next === 'environment' ? 'Resources' : next === 'resources' ? 'Review' : 'Confirm'}`;
      if (review && next !== 'review') review.textContent = `Stage ${next}: select the requested environment and resources.`;
    };
    const copyCustomValues = () => customNames.forEach((name) => {
      const source = shell.querySelector(`[name="${name}"]`); if (!source) return;
      let target = form.elements[name];
      if (!target) { target = document.createElement('input'); target.type = 'hidden'; target.name = name; form.append(target); }
      target.value = profile() === 'custom' ? (source.value || '') : '';
    });
    const toggleCustom = () => {
      const enabled = profile() === 'custom';
      shell.querySelectorAll('[data-custom-resources] input, [data-custom-resources] select').forEach((control) => { control.disabled = !enabled; });
      shell.querySelector('[data-custom-resources]')?.classList.toggle('disabled', !enabled);
      copyCustomValues();
    };
    const loadPreflight = async () => {
      try {
        copyCustomValues(); const query = new URLSearchParams(new FormData(form));
        const response = await fetch(`/ui/projects/${encodeURIComponent(slug)}/preflight?${query}`, { cache: 'no-store', credentials: 'same-origin', headers: { Accept: 'application/json' } });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json(); lastPreflight = data; const limits = data.selected_limits || {};
        const current = data.current_runtime || {};
        if (review) review.textContent = `CURRENT → NEW\nProvider/runtime: ${current.runtime_provider || current.runtime_type || 'detected'} → ${data.selected_environment}\nWorkspace owner: ${current.workspace_user || 'devrunner'} → devrunner\nCPU/RAM/disk/PID: ${limits.cpus || '—'} / ${limits.memory || limits.memory_gb || '—'} / ${limits.disk_gb || '—'} / ${limits.pids || '—'}\nLifecycle/health: ${current.lifecycle_status || 'unknown'} / ${current.health_status || 'unknown'}\nActions: verified backup, source-runtime handling, provisioning/export, workspace and health verification, lifecycle restoration. Fallback: rollback retains the verified source/backup.`;
        const ready = Boolean(data.migration_ready);
        if (preflight) preflight.textContent = ready ? `Preflight ready: inspection, capacity, archive, compose, and worktree checks passed.` : `Preflight not ready: ${(data.blockers || ['unknown blocker']).join(' ')}`;
        if (confirmButton && stage === 'confirm') confirmButton.disabled = !ready;
      } catch (error) { lastPreflight = null; if (preflight) preflight.textContent = `Preflight unavailable: ${error.message}. Confirmation is disabled.`; if (confirmButton && stage === 'confirm') confirmButton.disabled = true; }
    };
    shell.querySelectorAll('[data-wizard-stage]').forEach((button) => button.addEventListener('click', async () => { setStage(button.dataset.wizardStage); if (stage === 'review' || stage === 'confirm') await loadPreflight(); }));
    form.addEventListener('change', toggleCustom); toggleCustom();
    form.addEventListener('submit', async (event) => {
      copyCustomValues();
      if (stage !== 'confirm') { event.preventDefault(); setStage(stage === 'environment' ? 'resources' : stage === 'resources' ? 'review' : 'confirm'); if (stage === 'review' || stage === 'confirm') await loadPreflight(); return; }
      if (!lastPreflight || !lastPreflight.migration_ready) { event.preventDefault(); await loadPreflight(); return; }
      if (!form.elements.wizard_confirmed) { const confirmed = document.createElement('input'); confirmed.type = 'hidden'; confirmed.name = 'wizard_confirmed'; confirmed.value = 'true'; form.append(confirmed); }
      const token = form.elements.csrf_token; if (token) token.value = currentCsrf();
      event.preventDefault();
      if (confirmButton) confirmButton.disabled = true;
      try {
        const response = await fetch(form.action, { method: 'POST', body: new URLSearchParams(new FormData(form)), credentials: 'same-origin', headers: { Accept: 'application/json', 'X-DevFleet-UI': '1' } });
        const data = await response.json().catch(() => ({})); if (!response.ok || !data.operation_id) throw new Error(data.detail || `HTTP ${response.status}`);
        if (preflight) preflight.textContent = 'Environment assignment queued. Tracking backup, runtime handling, provisioning, verification, health, lifecycle restoration, and rollback progress…';
        let pollDelay = 750; let failures = 0;
        const poll = async () => {
          try {
            const response = await fetch(`/ui/operations/${encodeURIComponent(data.operation_id)}`, { credentials: 'same-origin', headers: { Accept: 'application/json' } });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const operation = await response.json();
            const state = operation.state || operation.status || 'unknown';
            failures = 0;
            if (preflight) preflight.textContent = operation.message || state || 'Operation running';
            if (!['completed', 'failed', 'cancelled', 'interrupted'].includes(state)) {
              pollDelay = 750;
              setTimeout(poll, pollDelay);
            }
          } catch (error) {
            failures += 1;
            if (preflight) preflight.textContent = `Operation status temporarily unavailable: ${error.message}`;
            if (failures <= 5) { pollDelay = Math.min(8000, pollDelay * 2); setTimeout(poll, pollDelay); }
          }
        };
        poll();
      } catch (error) { if (preflight) preflight.textContent = `Environment assignment was not queued: ${error.message}`; if (confirmButton) confirmButton.disabled = false; }
    });
    setStage(stage);
  }

  function initProjectActions() {
    if (window.__devfleetProjectActionsBound) return;
    window.__devfleetProjectActionsBound = true;
    document.addEventListener('submit', async (event) => {
      const form = event.target.closest('form.project-action-form');
      if (!form) return;
      // One document-level listener covers SPA replacement and dynamic backup forms.
      event.preventDefault();
      if (form.dataset.pending === '1') return;
      form.dataset.pending = '1';
      const button = form.querySelector('button[type="submit"]') || form.querySelector('button');
      const action = form.dataset.projectAction || new URL(form.action, location.href).pathname.split('/').pop() || 'action';
      const slug = new URL(form.action, location.href).pathname.split('/')[2] || '';
      const originalLabel = button?.textContent || '';
      const status = form.querySelector('[data-project-action-status]') || document.createElement('span');
      status.dataset.projectActionStatus = '1'; status.className = 'project-action-status'; status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
      if (!status.parentElement) form.append(status);
      if (button) { button.disabled = true; button.setAttribute('aria-busy', 'true'); button.textContent = `${action.charAt(0).toUpperCase()}${action.slice(1)}…`; }
      status.textContent = `${action.charAt(0).toUpperCase()}${action.slice(1)} queued…`;
      try {
        const body = new URLSearchParams(new FormData(form)); body.set('csrf_token', currentCsrf());
        const response = await fetch(form.action, { method: 'POST', body, credentials: 'same-origin', headers: { Accept: 'application/json', 'X-DevFleet-UI': '1', 'Idempotency-Key': `project-action:${slug}:${action}` } });
        const data = await response.json().catch(() => ({}));
        if (!response.ok || !data.operation_id) throw new Error(data.detail || `HTTP ${response.status}`);
        status.textContent = 'Operation queued. Tracking progress…';
        const target = `/projects/${encodeURIComponent(slug)}?tab=${encodeURIComponent(new URL(location.href).searchParams.get('tab') || 'overview')}&operation=${encodeURIComponent(data.operation_id)}`;
        navigate(target);
      } catch (error) {
        form.dataset.pending = '0'; status.textContent = `${action.charAt(0).toUpperCase()}${action.slice(1)} failed. ${error.message}`; status.classList.add('error');
        if (button) { button.disabled = false; button.removeAttribute('aria-busy'); button.textContent = originalLabel; }
        const detail = document.createElement('details'); const summary = document.createElement('summary'); summary.textContent = 'Technical detail'; const pre = document.createElement('pre'); pre.textContent = String(error.stack || error.message || error); detail.append(summary, pre); form.append(detail);
      }
    });
  }

  function initializeView() {
    syncNavigation();
    initProjectActions();
    initEnvironmentWizard();
    initExistingEnvironmentWizard();
    initBackupHistory();
    initOperationProgress();
    initProjectLogs();
    initInfrastructure();
    requestAnimationFrame(() => { if (location.hash) document.getElementById(location.hash.slice(1))?.scrollIntoView(); });
  }

  function initBackupHistory() {
    const panel = document.querySelector('[data-backup-history]');
    if (!panel || panel.dataset.enhanced === '1') return;
    panel.dataset.enhanced = '1'; const list = panel.querySelector('[data-backup-list]'); const slug = panel.dataset.projectSlug;
    fetch(`/ui/projects/${encodeURIComponent(slug)}/backups`, { cache: 'no-store', credentials: 'same-origin', headers: { Accept: 'application/json' } })
      .then((response) => { if (!response.ok) throw new Error(`HTTP ${response.status}`); return response.json(); })
      .then((data) => {
        list.replaceChildren(); const backups = data.backups || [];
        if (!backups.length) { list.textContent = 'No local verified restore points are recorded yet.'; return; }
        backups.forEach((backup) => {
          const row = document.createElement('div'); row.className = 'backup-history-row';
          const details = document.createElement('span'); details.textContent = `${backup.backup_id} · ${backup.status} · ${backup.archive_sha256 || 'no hash'}`;
          row.append(details);
          if (backup.status === 'eligible') {
            const form = document.createElement('form'); form.method = 'post'; form.action = `/projects/${encodeURIComponent(slug)}/restore-backup`; form.className = 'project-action-form';
            const csrf = document.createElement('input'); csrf.type = 'hidden'; csrf.name = 'csrf_token'; form.append(csrf);
            [['backup_id', backup.backup_id], ['confirm_restore', 'true']].forEach(([name, value]) => { const input = document.createElement('input'); input.type = 'hidden'; input.name = name; input.value = value; form.append(input); });
            const overwrite = document.createElement('label'); overwrite.className = 'checkbox-label'; const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.name = 'allow_overwrite'; checkbox.value = 'true'; overwrite.append(checkbox, document.createTextNode(' Allow overwrite')); form.append(overwrite);
            const button = document.createElement('button'); button.type = 'submit'; button.className = 'button ghost'; button.textContent = 'Restore'; form.append(button); row.append(form);
          }
          list.append(row);
        });
        initProjectActions();
      }).catch((error) => { list.textContent = `Backup history unavailable: ${error.message}`; });
  }

  function initOperationProgress() {
    const banner = document.querySelector('.operation-banner[data-operation-id]');
    if (!banner || banner.dataset.enhanced === '1') return;
    banner.dataset.enhanced = '1';
    const id = banner.dataset.operationId;
    const message = banner.querySelector('[data-operation-message]');
    const progress = banner.querySelector('[data-operation-progress]');
    const meta = banner.querySelector('[data-operation-meta]');
    let timer = null;
    let retry = 0;
    const load = async () => {
      try {
        const response = await fetch(`/operations/${encodeURIComponent(id)}`, { cache: 'no-store', credentials: 'same-origin', headers: { Accept: 'application/json' } });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const op = await response.json();
        if (message) message.textContent = op.message || '';
        if (progress) { progress.style.width = `${Number(op.progress || 0)}%`; }
         if (meta) meta.textContent = `${op.progress || 0}% · ${op.state || 'unknown'}`;
         retry = 0;
         if (!['completed', 'failed', 'cancelled', 'interrupted'].includes(op.state)) timer = setTimeout(load, 1500);
         else if (banner.dataset.refreshed !== '1') { banner.dataset.refreshed = '1'; timer = setTimeout(() => { const refreshed = new URL(location.href); refreshed.searchParams.delete('operation'); navigate(refreshed.toString(), true); }, 500); }
       } catch (_) {
         retry = Math.min(retry + 1, 5); timer = setTimeout(load, Math.min(10000, 500 * (2 ** retry)));
       }
    };
    load();
    banner._devfleetOperationCleanup = () => { if (timer) clearTimeout(timer); };
  }

  function initProjectLogs() {
    const output = document.querySelector('.log-output[data-project-logs]');
    if (!output || output.dataset.enhanced === '1') return;
    output.dataset.enhanced = '1';
    const slug = output.dataset.projectLogs;
    const controls = document.createElement('div'); controls.className = 'log-controls';
    const tail = document.createElement('select'); tail.setAttribute('aria-label', 'Log lines');
    [50, 150, 300, 500].forEach((value) => { const option = new Option(`Last ${value} lines`, value); tail.add(option); });
    tail.value = localStorage.getItem('devfleet.project-log-tail') || '150';
    const refresh = document.createElement('button'); refresh.type = 'button'; refresh.className = 'button ghost'; refresh.textContent = 'Refresh';
    const pause = document.createElement('button'); pause.type = 'button'; pause.className = 'button ghost'; pause.textContent = 'Pause';
    const copy = document.createElement('button'); copy.type = 'button'; copy.className = 'button ghost'; copy.textContent = 'Copy';
    controls.append(tail, refresh, pause, copy); output.before(controls);
    let paused = false; let request = null; let activeController = null;
    const load = async () => {
      if (paused || request) return;
      // Human UI logs use the session-authenticated endpoint.  The machine API
      // intentionally remains token-protected and must never receive its token
      // through browser JavaScript.
      activeController = new AbortController();
      request = fetchWithTimeout(`/ui/projects/${encodeURIComponent(slug)}/logs?tail=${encodeURIComponent(tail.value)}`, { cache: 'no-store', credentials: 'same-origin', headers: { Accept: 'application/json' }, controller: activeController }, 10000)
        .then(async (response) => { const data = await response.json().catch(() => ({})); if (response.status === 409) { paused = true; return data; } if (!response.ok) throw new Error(`HTTP ${response.status}`); return data; })
        .then((data) => { output.textContent = data.logs || 'No logs.'; })
        .catch((error) => { output.textContent = error.name === 'AbortError' ? 'Log request ended — the runtime changed state or the 10-second timeout was reached.' : `Logs failed: ${error.message}`; })
        .finally(() => { request = null; });
      await request;
    };
    tail.addEventListener('change', () => { localStorage.setItem('devfleet.project-log-tail', tail.value); load(); });
    refresh.addEventListener('click', load);
    pause.addEventListener('click', () => { paused = !paused; pause.textContent = paused ? 'Resume' : 'Pause'; if (!paused) load(); });
    copy.addEventListener('click', async () => { try { await navigator.clipboard.writeText(output.textContent); copy.textContent = 'Copied'; setTimeout(() => { copy.textContent = 'Copy'; }, 1200); } catch (_) { copy.textContent = 'Copy unavailable'; } });
    load();
    output._devfleetLogCleanup = () => { paused = true; activeController?.abort('navigation-or-state-change'); };
  }

  function initInfrastructure() {
  const nodesHost = document.getElementById('cluster-nodes');
  const table = document.querySelector('#container-table tbody');
  const nodeFilter = document.getElementById('container-node-filter');
  const refreshSelect = document.getElementById('refresh-interval');
  const refreshButton = document.getElementById('refresh-cluster');
  const updated = document.getElementById('cluster-updated');
  const details = document.getElementById('container-details');
  const detailsTitle = document.getElementById('container-details-title');
  const inspect = document.getElementById('container-inspect');
  const logs = document.getElementById('container-logs');
  const closeDetails = document.getElementById('close-container-details');
  if (!nodesHost && !table) return;
  window.__devfleetStopInfrastructure?.();

  const savedInterval = localStorage.getItem('devfleet.refresh.interval');
  if (refreshSelect && savedInterval && [...refreshSelect.options].some((o) => o.value === savedInterval)) refreshSelect.value = savedInterval;
  let timer = null;
  let cluster = { nodes: [], containers: [] };
  try { const seed = JSON.parse(document.getElementById('devfleet-cluster-data')?.textContent || '{}'); if (seed && typeof seed === 'object') cluster = seed; } catch (_) { /* retain empty snapshot */ }

  const text = (value) => document.createTextNode(String(value ?? ''));
  const cell = (value, className) => { const el = document.createElement('td'); if (className) el.className = className; el.append(text(value)); return el; };
  const metric = (label, value) => {
    const el = document.createElement('div'); el.className = 'metric';
    const nameEl = document.createElement('span'); nameEl.className = 'metric-label'; nameEl.append(text(label));
    const valueEl = document.createElement('strong'); valueEl.append(text(value));
    el.append(nameEl, valueEl); return el;
  };

  function renderNodes() {
    if (!nodesHost) return;
    nodesHost.replaceChildren();
    (cluster.nodes || []).forEach((node) => {
      const card = document.createElement('article'); card.className = 'node-card';
      const heading = document.createElement('div'); heading.className = 'node-heading';
      const title = document.createElement('h3'); title.append(text(node.friendly_name || node.id));
      const online = node.status === 'online' && node.reachable !== false;
      const badge = document.createElement('span'); badge.className = `status-badge ${online ? 'ok' : 'bad'}`; badge.append(text(online ? 'Available' : 'Offline — unavailable'));
      heading.append(title, badge); card.append(heading);
      const sub = document.createElement('p'); sub.className = 'muted'; sub.append(text(`${node.node || node.id} · ${node.role || 'node'}`)); card.append(sub);
      const metrics = document.createElement('div'); metrics.className = 'metrics';
      const system = node.system || {}; const docker = node.docker || {};
      metrics.append(metric('CPU', `${system.cpu_percent ?? '—'}%`), metric('Memory', `${system.memory_percent ?? '—'}%`), metric('Disk free', `${system.disk_free_gb ?? '—'} GB`), metric('Containers', String((node.containers || []).length)));
      card.append(metrics);
      const runtime = document.createElement('p'); runtime.className = 'node-runtime';
      runtime.append(text(node.role === 'vault' ? `Vault listener: ${(node.vault || {}).status || 'unknown'}` : `Docker: ${docker.ok ? (docker.mode || 'ready') : 'unavailable'}`)); card.append(runtime);
      if (node.error) { const error = document.createElement('p'); error.className = 'error'; error.append(text(node.error)); card.append(error); }
      if (node.role !== 'vault' && !online) { const note = document.createElement('p'); note.className = 'muted'; note.append(text('Destination selection disabled until this node is reachable.')); card.append(note); }
      nodesHost.append(card);
    });
    if (!cluster.nodes?.length) { const empty = document.createElement('p'); empty.className = 'muted'; empty.append(text('No cluster data returned.')); nodesHost.append(empty); }
  }

  function renderNodeFilter() {
    if (!nodeFilter) return;
    const current = nodeFilter.value || 'all';
    const options = [{ id: 'all', label: 'All nodes' }, ...(cluster.nodes || []).filter((n) => n.role !== 'vault').map((n) => ({ id: n.id, label: n.friendly_name || n.id }))];
    nodeFilter.replaceChildren();
    options.forEach((item) => { const option = document.createElement('option'); option.value = item.id; option.append(text(item.label)); nodeFilter.append(option); });
    nodeFilter.value = options.some((o) => o.id === current) ? current : 'all';
  }

  function renderContainers() {
    if (!table || !nodeFilter) return;
    table.replaceChildren();
    const filter = nodeFilter.value || 'all';
    const rows = (cluster.containers || []).filter((item) => filter === 'all' || item.node_id === filter);
    if (!rows.length) { const row = document.createElement('tr'); const empty = cell('No containers are registered on this node. A healthy empty node is different from an unavailable node.', 'muted'); empty.colSpan = 8; row.append(empty); table.append(row); return; }
    rows.forEach((item) => {
      const row = document.createElement('tr');
      row.append(cell(item.node_name || item.node_id), cell(item.name), cell(item.image), cell(`${item.state} · ${item.status}`), cell(item.cpu_percent), cell(`${item.memory_usage} (${item.memory_percent})`), cell(item.network_io));
      const actions = document.createElement('td'); actions.className = 'container-actions';
      ['start','stop','restart','pause','unpause'].forEach((action) => {
        const button = document.createElement('button'); button.type = 'button'; button.className = 'container-action'; button.dataset.action = action; button.dataset.ref = item.id; button.dataset.scope = item.control_scope; button.append(text(action)); actions.append(button);
      });
      const inspectButton = document.createElement('button'); inspectButton.type = 'button'; inspectButton.className = 'container-inspect'; inspectButton.dataset.ref = item.id; inspectButton.dataset.name = item.name; inspectButton.dataset.scope = item.control_scope; inspectButton.append(text('details')); actions.append(inspectButton);
      const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'container-action danger'; remove.dataset.action = 'remove'; remove.dataset.ref = item.id; remove.dataset.scope = item.control_scope; remove.append(text('remove')); actions.append(remove);
      row.append(actions); table.append(row);
    });
  }

  async function refreshCluster() {
    if (refreshButton) refreshButton.disabled = true;
    try {
      const response = await fetch('/cluster/status', { cache: 'no-store', credentials: 'same-origin' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      cluster = await response.json(); renderNodes(); renderNodeFilter(); renderContainers();
      if (updated) updated.textContent = `Updated ${new Date().toLocaleTimeString()}`;
    } catch (error) {
      if (updated) updated.textContent = `Refresh failed: ${error.message}`;
    } finally { if (refreshButton) refreshButton.disabled = false; }
  }

  function scheduleRefresh() {
    if (!refreshSelect) return;
    if (timer) clearInterval(timer); timer = null;
    localStorage.setItem('devfleet.refresh.interval', refreshSelect.value);
    const seconds = Number(refreshSelect.value);
    if (seconds > 0) timer = setInterval(refreshCluster, seconds * 1000);
  }

  async function showDetails(ref, name, scope) {
    details.hidden = false; detailsTitle.textContent = `${name || ref} · details`; inspect.textContent = 'Loading inspect…'; logs.textContent = 'Loading logs…';
    const prefix = scope === 'peer' ? '/peer' : '';
    try { const r = await fetch(`${prefix}/containers/${encodeURIComponent(ref)}/inspect`, { cache: 'no-store' }); if (!r.ok) throw new Error(`HTTP ${r.status}`); inspect.textContent = JSON.stringify(await r.json(), null, 2); } catch (e) { inspect.textContent = `Inspect failed: ${e.message}`; }
    try { const r = await fetch(`${prefix}/containers/${encodeURIComponent(ref)}/logs?tail=200`, { cache: 'no-store' }); if (!r.ok) throw new Error(`HTTP ${r.status}`); logs.textContent = (await r.json()).logs || 'No logs.'; } catch (e) { logs.textContent = `Logs failed: ${e.message}`; }
  }

  document.addEventListener('click', async (event) => {
    const inspectButton = event.target.closest('.container-inspect');
    if (inspectButton) return showDetails(inspectButton.dataset.ref, inspectButton.dataset.name, inspectButton.dataset.scope);
    const actionButton = event.target.closest('.container-action');
    if (!actionButton) return;
    const action = actionButton.dataset.action; const ref = actionButton.dataset.ref; const scope = actionButton.dataset.scope;
    if (action === 'remove' && !window.confirm('Remove this container? This cannot be undone.')) return;
    actionButton.disabled = true;
    try {
      const prefix = scope === 'peer' ? '/peer' : '';
       const body = new URLSearchParams({ csrf_token: currentCsrf() }); if (action === 'remove') body.set('confirm_remove', 'true');
      const response = await fetch(`${prefix}/containers/${encodeURIComponent(ref)}/${action}`, { method: 'POST', body, credentials: 'same-origin' });
      if (!response.ok) throw new Error((await response.text()).slice(-500));
      await refreshCluster();
    } catch (error) { window.alert(`Container action failed: ${error.message}`); }
    finally { actionButton.disabled = false; }
  });

  nodeFilter?.addEventListener('change', renderContainers);
  refreshButton?.addEventListener('click', refreshCluster);
  refreshSelect?.addEventListener('change', scheduleRefresh);
  closeDetails?.addEventListener('click', () => { details.hidden = true; });
  renderNodes(); renderNodeFilter(); renderContainers();
  const shouldRefresh = new URL(location.href).searchParams.get('view') === 'infrastructure';
  if (shouldRefresh) refreshCluster();
  scheduleRefresh();
  window.__devfleetStopInfrastructure = () => { if (timer) clearInterval(timer); timer = null; };
  }

  initializeView();
})();

```


## FILE: source/app/static/style.css

SHA256: 9e95e0103e58d5d59f47b099381beb3f0e9af60b34a9a30fe00c121c04833128 | Bytes: 20663 | Git mode: 100644

```
:root{color-scheme:dark;font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0b1020;color:#f3f6ff;--bg:#0b1020;--surface:#131a2c;--surface-2:#18233a;--line:#2a3857;--muted:#8e9bb7;--text:#f3f6ff;--blue:#5b8cff;--blue-2:#2e63d2;--green:#35d49a;--yellow:#f0c96a;--red:#ed6b7a;--shadow:0 18px 50px rgba(0,0,0,.22)}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 80% -10%,#1c2b55 0,#0b1020 42%);color:var(--text)}a{color:#a9c5ff;text-decoration:none}a:hover{color:#d6e3ff}button,.button,input,select{font:inherit}button,.button{display:inline-flex;align-items:center;justify-content:center;gap:7px;border:1px solid transparent;border-radius:9px;padding:10px 14px;background:var(--blue-2);color:#fff;cursor:pointer;font-weight:650;text-decoration:none;transition:.18s ease}button:hover,.button:hover{filter:brightness(1.12);transform:translateY(-1px)}button:disabled,.button.disabled{opacity:.45;cursor:not-allowed;transform:none;filter:none}.button.ghost,button.ghost{background:#172542;border-color:#3a4d74;color:#d9e5ff}.button.danger,button.danger{background:#8f3046;border-color:#c2576a}.icon-button{padding:10px 12px;border:1px solid var(--line);border-radius:9px;background:#172542;color:#a9c5ff}.app-shell{display:flex;min-height:100vh}.sidebar{position:sticky;top:0;width:248px;height:100vh;display:flex;flex-direction:column;padding:26px 16px;border-right:1px solid rgba(89,111,160,.24);background:rgba(10,16,32,.82);backdrop-filter:blur(16px)}.brand{display:flex;align-items:center;gap:11px;padding:0 10px 34px;color:var(--text)}.brand-mark{display:grid;place-items:center;width:34px;height:34px;border-radius:10px;background:linear-gradient(135deg,#709bff,#385fd0);font-weight:800;font-size:.8rem;box-shadow:0 8px 24px rgba(58,102,220,.35)}.brand strong,.brand small{display:block}.brand small{margin-top:3px;color:var(--muted);font-size:.68rem}.primary-nav{display:grid;gap:5px}.primary-nav a{display:flex;align-items:center;gap:12px;padding:12px 13px;border-radius:9px;color:#aebbd5;font-size:.91rem}.primary-nav a span{width:18px;text-align:center;color:#8295bc}.primary-nav a:hover,.primary-nav a.active{background:#1a2948;color:#fff}.primary-nav a.active span{color:#78a1ff}.sidebar-footer{margin-top:auto;display:grid;gap:16px;padding:15px 10px 0;border-top:1px solid rgba(89,111,160,.22)}.node-presence{display:flex;align-items:center;gap:8px}.node-presence strong,.node-presence small{display:block}.node-presence small{margin-top:3px;color:var(--muted);font-size:.68rem}.presence-dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--green);box-shadow:0 0 0 4px rgba(53,212,154,.13)}.version-label{color:#63708b;font-size:.68rem}.app-main{width:min(100%,1460px);margin:0 auto;padding:0 42px 70px}.topbar{display:flex;align-items:center;justify-content:space-between;gap:22px;padding:34px 0 30px}.topbar h1{margin:4px 0 0;font-size:1.85rem;letter-spacing:-.03em}.topbar-actions{display:flex;align-items:center;gap:12px}.connection-pill{display:flex;align-items:center;gap:8px;padding:9px 13px;border:1px solid #2b4866;border-radius:999px;background:rgba(24,40,68,.55);color:#c4d4f1;font-size:.78rem}.eyebrow{margin:0;color:#7296ed;font-size:.68rem;font-weight:800;letter-spacing:.13em}.muted{color:var(--muted)}.error{color:#ff9daa}.danger-text{color:#ff8796}.hero-grid,.content-grid,.stats-grid,.node-grid,.project-card-grid,.summary-grid,.details-grid{display:grid;gap:16px}.hero-grid{grid-template-columns:minmax(0,1.6fr) minmax(280px,.8fr)}.content-grid.two-thirds{grid-template-columns:minmax(0,1.35fr) minmax(280px,.8fr)}.stats-grid{grid-template-columns:repeat(4,minmax(0,1fr));margin:18px 0}.panel,.hero-card,.health-card,.project-card,.stat-card,.empty-state{border:1px solid var(--line);border-radius:15px;background:linear-gradient(145deg,rgba(22,31,53,.96),rgba(15,23,40,.96));box-shadow:var(--shadow)}.panel{padding:22px;margin:16px 0}.hero-card{min-height:250px;padding:34px;background:linear-gradient(130deg,#203c7a,#17294e 57%,#111b31)}.hero-card h2{max-width:580px;margin:12px 0 10px;font-size:2.25rem;line-height:1.08;letter-spacing:-.04em}.hero-card p{max-width:610px;color:#b8c9e8;line-height:1.6}.hero-actions,.quick-actions,.card-actions,.quick-links,.action-stack,.actions{display:flex;align-items:center;flex-wrap:wrap;gap:9px}.hero-actions{margin-top:28px}.health-card{padding:24px}.card-heading,.section-heading,.project-card-top,.project-hero-row{display:flex;align-items:center;justify-content:space-between;gap:14px}.icon-tile{display:grid;place-items:center;width:38px;height:38px;border-radius:11px;font-weight:800}.icon-tile.green{background:rgba(53,212,154,.14);color:var(--green)}.health-card .card-heading{justify-content:flex-start}.health-card h3{margin:0}.health-score{margin:34px 0 7px;color:var(--green);font-size:1.65rem;font-weight:750}.health-card a{display:block;margin-top:21px;font-weight:650}.stat-card{display:grid;gap:5px;padding:18px 20px}.stat-card strong{font-size:1.75rem;letter-spacing:-.03em}.stat-card small,.stat-label{color:var(--muted);font-size:.75rem}.stat-label{color:#9eb2d9;text-transform:uppercase;letter-spacing:.08em;font-weight:700}.section-heading{margin-bottom:18px}.section-heading h2,.page-intro h2,.panel h2{margin:4px 0 0;font-size:1.28rem;letter-spacing:-.025em}.project-list{display:grid}.project-row{display:flex;align-items:center;gap:12px;padding:13px 5px;border-bottom:1px solid rgba(67,87,127,.35)}.project-row:last-child{border-bottom:0}.project-avatar{display:grid;place-items:center;width:34px;height:34px;flex:none;border-radius:10px;background:#263a68;color:#bcd0ff;font-weight:800}.project-avatar.large{width:44px;height:44px;font-size:1.1rem}.project-avatar.huge{width:64px;height:64px;font-size:1.45rem}.project-row-copy{display:grid;gap:4px;min-width:0;flex:1}.project-row-copy strong{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.project-row-copy small{color:var(--muted);font-size:.76rem}.chevron{color:#8094be;font-size:1.35rem}.status-badge{display:inline-flex;align-items:center;width:max-content;border-radius:999px;padding:4px 9px;font-size:.68rem;font-weight:750;text-transform:capitalize;white-space:nowrap}.status-badge.ok{background:rgba(53,212,154,.14);color:#66e2b2}.status-badge.warn{background:rgba(240,201,106,.14);color:#f3d47e}.status-badge.bad{background:rgba(237,107,122,.14);color:#ff9aa6}.activity-row{display:flex;align-items:center;gap:11px;padding:11px 0;border-bottom:1px solid rgba(67,87,127,.35)}.activity-row:last-child{border-bottom:0}.activity-row span:nth-child(2){display:grid;gap:3px;min-width:0;flex:1}.activity-row small,.activity-row time{color:var(--muted);font-size:.73rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.activity-row time{max-width:125px}.activity-dot{display:inline-block;width:8px;height:8px;flex:none;border-radius:50%}.activity-dot.ok{background:var(--green)}.activity-dot.warn{background:var(--yellow)}.activity-dot.bad{background:var(--red)}.page-intro{display:flex;align-items:end;justify-content:space-between;gap:20px;margin:8px 0 25px}.page-intro h2{font-size:2rem}.page-intro p{margin:9px 0 0}.project-card-grid{grid-template-columns:repeat(auto-fit,minmax(330px,1fr))}.project-card{padding:20px}.project-card-top{align-items:flex-start}.project-card-top h3{margin:2px 0 4px}.project-card-top>div{flex:1}.project-facts,.environment-summary{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:22px 0;padding:13px 0;border-top:1px solid var(--line);border-bottom:1px solid var(--line)}.project-facts div,.environment-summary div,.summary-grid div{display:grid;gap:5px}.project-facts small,.environment-summary small,.summary-grid small{color:var(--muted);font-size:.7rem}.project-facts strong,.environment-summary strong,.summary-grid strong{font-size:.82rem}.project-summary{min-height:22px;font-size:.8rem}.wizard-panel{scroll-margin-top:20px}.wizard-form{display:grid;gap:23px}.form-step{display:grid;grid-template-columns:32px 1fr;gap:14px;padding-bottom:21px;border-bottom:1px solid var(--line)}.step-number{display:grid;place-items:center;width:27px;height:27px;border-radius:50%;background:#263e78;color:#c9d9ff;font-size:.76rem;font-weight:800}.form-step h3{margin:2px 0 13px;font-size:.96rem}.form-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:13px}.form-grid label,.environment-form label,.danger-form label{display:grid;gap:6px;color:#b8c8e3;font-size:.78rem}.checkbox-label{display:flex!important;align-items:center;grid-template-columns:none!important}.checkbox-label input{width:auto}input,select{width:100%;padding:10px 11px;border:1px solid #3d4e73;border-radius:8px;background:#0e172a;color:#f4f7ff;outline:none}input:focus,select:focus{border-color:#70a0ff;box-shadow:0 0 0 3px rgba(91,140,255,.15)}.review-note{display:grid;gap:5px;padding:13px 15px;border:1px solid #3a4e78;border-radius:10px;background:rgba(28,48,88,.45);color:#c8d5ed;font-size:.78rem}.review-note span{color:var(--muted);line-height:1.5}.form-advanced{margin:0}.project-hero{margin:0 0 18px;padding:10px 0}.back-link{display:inline-block;margin-bottom:22px;color:#9bb8f7;font-size:.82rem}.project-hero-row{justify-content:flex-start}.project-hero-row>div:nth-child(2){flex:1}.project-hero h2{margin:4px 0;font-size:2rem;letter-spacing:-.04em}.hero-status{display:grid;justify-items:end;gap:8px}.hero-status small{color:var(--muted);font-size:.74rem}.quick-actions{margin-top:23px}.tabs{display:flex;gap:22px;margin:0 -2px 19px;border-bottom:1px solid var(--line)}.tabs a{padding:11px 3px;color:var(--muted);font-size:.82rem;font-weight:700;border-bottom:2px solid transparent}.tabs a.active,.tabs a:hover{color:#dce7ff;border-color:#6f9bff}.environment-form{display:grid;gap:15px;max-width:520px}.action-stack{display:grid;justify-items:start;align-items:start}.action-stack form{width:100%}.action-stack button{width:100%;justify-content:flex-start}.danger-panel{border-color:#6c3348;background:linear-gradient(145deg,rgba(56,27,47,.75),rgba(25,20,38,.95))}.danger-form{display:grid;gap:13px}.advanced{margin-top:14px;color:#a9bce0}.advanced summary{cursor:pointer;color:#8fa8d7;font-size:.76rem;font-weight:700}.advanced pre,pre{white-space:pre-wrap;word-break:break-word;max-height:430px;overflow:auto}.advanced pre{margin:10px 0 0;padding:13px;border:1px solid rgba(67,87,127,.5);border-radius:8px;background:#0a1222;color:#aebed9;font-size:.7rem}.summary-grid{grid-template-columns:repeat(4,1fr);margin:4px 0 2px}.node-grid{grid-template-columns:repeat(auto-fit,minmax(250px,1fr))}.node-card{margin:0;padding:17px;border:1px solid var(--line);border-radius:12px;background:#111b30}.node-heading{display:flex;align-items:center;justify-content:space-between;gap:9px}.node-heading h3{margin:0;font-size:.96rem}.node-card .metrics{display:grid;grid-template-columns:repeat(2,1fr);gap:8px;margin:15px 0}.metric{padding:9px;border-radius:7px;background:#0d1629}.metric-label{display:block;color:var(--muted);font-size:.68rem}.metric strong{font-size:.88rem}.node-runtime{margin:0;padding-top:10px;border-top:1px solid var(--line);color:#b7c8e7;font-size:.76rem}.container-panel{overflow:hidden}.monitor-controls{display:flex;align-items:end;gap:9px}.monitor-controls label{display:grid;gap:5px;color:var(--muted);font-size:.72rem}.monitor-controls select{padding:9px}.table-wrap{overflow:auto}.container-panel table{width:100%;min-width:950px;border-collapse:collapse}.container-panel th,.container-panel td{padding:11px 9px;border-bottom:1px solid rgba(67,87,127,.4);text-align:left;vertical-align:top;font-size:.75rem}.container-panel th{color:#96acd5;font-size:.67rem;letter-spacing:.08em;text-transform:uppercase}.container-actions{display:flex;flex-wrap:wrap;gap:5px}.container-actions button{padding:6px 8px;font-size:.68rem}.container-details{margin-top:18px}.details-grid{grid-template-columns:repeat(auto-fit,minmax(290px,1fr))}.operation-banner{display:grid;grid-template-columns:auto 1fr auto auto;align-items:center;gap:13px;margin:0 0 18px;padding:14px 16px;border:1px solid #385da1;border-radius:12px;background:#15284d}.operation-banner.failed{border-color:#8d4054;background:#3a1e32}.operation-banner.complete{border-color:#2d8b6b;background:#163d39}.operation-icon{display:grid;place-items:center;width:30px;height:30px;border-radius:50%;background:#2d5ab0;font-weight:800}.operation-banner.failed .operation-icon{background:#9c3d55}.operation-banner.complete .operation-icon{background:#238568}.operation-copy{display:grid;gap:6px}.operation-copy span{color:#b8c9e8;font-size:.78rem}.operation-meta{text-align:right;color:#adbfdf;font-size:.72rem}.progress-track{height:5px;overflow:hidden;border-radius:99px;background:#0d172a}.progress-track span{display:block;height:100%;border-radius:inherit;background:linear-gradient(90deg,#5688ff,#65d4bb)}.operation-details{margin:0}.operation-row{display:flex;align-items:flex-start;gap:13px;padding:16px 0;border-bottom:1px solid var(--line)}.operation-row:last-child{border-bottom:0}.operation-main{flex:1}.operation-main p{margin:5px 0 10px;color:var(--muted);font-size:.78rem}.operation-row .advanced{margin:0}.activity-panel{padding:22px}.empty-state{text-align:center;padding:45px 20px;color:var(--muted)}.empty-state h3{color:var(--text)}.code,code{padding:3px 6px;border-radius:5px;background:#0d1628;color:#b9d0ff;font-size:.78rem}
@media(max-width:980px){.sidebar{width:205px}.app-main{padding:0 24px 60px}.hero-grid,.content-grid.two-thirds{grid-template-columns:1fr}.stats-grid{grid-template-columns:repeat(2,1fr)}.summary-grid{grid-template-columns:repeat(2,1fr)}}
@media(max-width:680px){.app-shell{display:block}.sidebar{position:relative;width:auto;height:auto;padding:15px 16px;border-right:0;border-bottom:1px solid rgba(89,111,160,.24)}.brand{padding:0 0 15px}.primary-nav{display:flex;overflow:auto}.primary-nav a{padding:9px 11px;white-space:nowrap}.sidebar-footer{display:none}.app-main{padding:0 15px 45px}.topbar{align-items:flex-start;flex-direction:column;padding:23px 0}.topbar-actions{width:100%;justify-content:space-between}.topbar h1{font-size:1.55rem}.hero-card{padding:25px 21px}.hero-card h2{font-size:1.8rem}.stats-grid{gap:9px}.stat-card{padding:14px}.stat-card strong{font-size:1.35rem}.project-card-grid{grid-template-columns:1fr}.project-facts,.environment-summary{grid-template-columns:1fr 1fr}.project-hero-row{align-items:flex-start;flex-wrap:wrap}.hero-status{margin-left:78px;justify-items:start}.quick-actions .button,.quick-actions form{flex:1 1 auto}.operation-banner{grid-template-columns:auto 1fr}.operation-meta{grid-column:2;text-align:left}.operation-details{grid-column:2}.page-intro{align-items:flex-start;flex-direction:column}.page-intro h2{font-size:1.65rem}.section-heading{align-items:flex-start;flex-direction:column}.monitor-controls{width:100%;align-items:stretch}.monitor-controls label{flex:1}.monitor-controls button{align-self:end}.form-step{grid-template-columns:25px 1fr}.summary-grid{grid-template-columns:1fr 1fr}.tabs{gap:14px;overflow:auto}.tabs a{white-space:nowrap}}
/* 1.2.0 accessibility, advanced-mode, and runtime-state additions */
.icon-sprite{position:absolute;width:0;height:0;overflow:hidden}.primary-nav a svg{width:18px;height:18px;flex:none;color:#8295bc}.primary-nav a:hover svg,.primary-nav a.active svg{color:#78a1ff}.status-badge.neutral{background:rgba(142,155,183,.16);color:#b6c1d6}.advanced{display:none}.advanced-mode .advanced{display:block}.preference-panel{display:flex;align-items:center;justify-content:space-between;gap:14px}.preference-toggle{color:#c8d5ed!important}.help-text{font-size:.72rem;margin:.35rem 0 0}.logs-panel .log-output{min-height:280px;margin:0;padding:16px;border:1px solid var(--line);border-radius:10px;background:#091120;color:#c7d7f3;font:12px/1.55 ui-monospace,SFMono-Regu