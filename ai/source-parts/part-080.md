# DevFleet source part 080

Full-source UTF-8 byte interval [3673500, 3720000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 91c8074aa92c8bfa2b8607592d7b5f95b076b8fe6944cd5249d3da887bf68064

<!-- BEGIN SOURCE SLICE -->
 (shouldRefresh) refreshCluster();
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
.icon-sprite{position:absolute;width:0;height:0;overflow:hidden}.primary-nav a svg{width:18px;height:18px;flex:none;color:#8295bc}.primary-nav a:hover svg,.primary-nav a.active svg{color:#78a1ff}.status-badge.neutral{background:rgba(142,155,183,.16);color:#b6c1d6}.advanced{display:none}.advanced-mode .advanced{display:block}.preference-panel{display:flex;align-items:center;justify-content:space-between;gap:14px}.preference-toggle{color:#c8d5ed!important}.help-text{font-size:.72rem;margin:.35rem 0 0}.logs-panel .log-output{min-height:280px;margin:0;padding:16px;border:1px solid var(--line);border-radius:10px;background:#091120;color:#c7d7f3;font:12px/1.55 ui-monospace,SFMono-Regular,Consolas,monospace}.success{color:#66e2b2}.warning{color:#f3d47e}.truncate{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:220px}.safety-list{display:grid;gap:5px;margin-top:18px;padding-top:14px;border-top:1px solid var(--line)}.safety-list p{margin:0;color:#c6d3e9;font-size:.8rem}.danger-panel{position:relative}.button:focus-visible,a:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:2px solid #9ab8ff;outline-offset:2px}
/* DevFleet login landing page */
.login-page{min-height:100vh;display:grid;place-items:center;background:radial-gradient(circle at 15% 15%,rgba(67,118,255,.18),transparent 38%),#08101f;color:#eef4ff}
.login-shell{width:min(920px,calc(100% - 32px));display:grid;grid-template-columns:1fr minmax(320px,420px);gap:48px;align-items:center}
.login-brand h1{font-size:clamp(3rem,8vw,6rem);letter-spacing:-.07em;margin:.1em 0}.login-brand>p:not(.eyebrow){max-width:34rem;color:#a7b7d4;font-size:1.15rem;line-height:1.6}.eyebrow{color:#71a3ff;font-size:.72rem;font-weight:800;letter-spacing:.16em}
.login-card{background:rgba(18,31,56,.92);border:1px solid rgba(141,174,232,.25);border-radius:20px;padding:32px;box-shadow:0 28px 80px rgba(0,0,0,.35)}.login-card h2{margin:.25rem 0 1.5rem}.login-card label{display:block;margin:1rem 0 .35rem;color:#c6d3e8}.login-card input:not([type=checkbox]){width:100%;box-sizing:border-box;border:1px solid #41577d;border-radius:9px;background:#0b1528;color:#fff;padding:.75rem}.login-remember{display:flex!important;align-items:center;gap:.5rem;font-size:.9rem}.login-submit{width:100%;margin-top:1rem}.login-error{padding:.7rem;border-radius:8px;background:#4b1d2a;color:#ffb8c4}.login-footer{text-align:center;color:#8da0bf;margin:1.5rem 0 0;font-size:.85rem}
@media (max-width:720px){.login-shell{grid-template-columns:1fr;gap:18px}.login-brand{text-align:center}.login-brand h1{font-size:4rem}}
.inline-form{display:inline-flex;margin:0}.inline-form button{font:inherit}
.custom-resource-controls{margin:0;padding:15px;border:1px solid var(--line);border-radius:10px;background:rgba(12,22,41,.45)}.custom-resource-controls legend{padding:0 7px;color:#b9cbed;font-size:.8rem;font-weight:750}.wizard-review{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:14px 15px;border:1px solid #4669a4;border-radius:10px;background:rgba(28,48,88,.4)}.wizard-review div{display:grid;gap:5px}.wizard-review span:not(.status-badge){color:#b8c9e8;font-size:.78rem;line-height:1.45}.workspace-link{white-space:nowrap}.resource-allocation{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin:16px 0;padding:15px;border:1px solid var(--line);border-radius:10px;background:rgba(12,22,41,.45)}.resource-allocation div{display:grid;gap:4px}.resource-allocation small{color:var(--muted);font-size:.7rem}.resource-allocation strong{font-size:.82rem}.resource-telemetry{font-size:.75rem}.workspace-readiness-note,.project-action-status{display:block;margin-top:7px;color:var(--muted);font-size:.72rem;line-height:1.35}.project-action-status.error{color:#ff9daa}.project-action-form details{margin-top:8px}@media(max-width:680px){.resource-allocation{grid-template-columns:1fr 1fr}}
/* v1.2.11 authoritative stopped/transitioning project states */
.project-state-banner{display:flex;align-items:center;justify-content:space-between;gap:22px;margin:0 0 22px;padding:18px 20px;border:2px solid #7185a9;border-radius:14px;background:#17223a;box-shadow:var(--shadow)}.project-state-banner strong{display:block;font-size:1.1rem;letter-spacing:.01em}.project-state-banner p{max-width:720px;margin:6px 0 0;color:#d7e0f1;line-height:1.5}.project-state-banner.stopped{border-color:#a8b6ce;background:linear-gradient(120deg,#28334a,#192338)}.project-state-banner.transitioning{border-color:#f0c96a;background:#302b24}.project-state-banner.error{border-color:#ed6b7a;background:#3a202c}.strong-state .status-badge{padding:7px 12px;border:1px solid currentColor;font-size:.76rem;font-weight:850;letter-spacing:.08em;text-transform:uppercase}.state-stopped .status-badge{background:#c7d0df;color:#182238}.state-starting .status-badge,.state-stopping .status-badge,.state-provisioning .status-badge{background:#f0c96a;color:#211c12}.state-running .status-badge{background:#35d49a;color:#082419}.state-error .status-badge,.state-unreachable .status-badge{background:#ed6b7a;color:#2b0c13}.runtime-unavailable{margin:12px 0;padding:18px;border:1px dashed #7185a9;border-radius:10px;background:#111a2c;color:#dbe4f5}.runtime-unavailable p{margin:6px 0 0;color:var(--muted)}
@media(max-width:680px){.project-state-banner{align-items:flex-start;flex-direction:column}.project-state-banner form,.project-state-banner button{width:100%}}

```


## FILE: source/app/systemd/devfleet-backup.service

SHA256: 4262827dc7134b7a52088898b25c35eba6359089ca24b4149acc5053c5c877c9 | Bytes: 390 | Git mode: 100644

```
[Unit]
Description=DevFleet encrypted workspace backup
After=network-online.target tailscaled.service
[Service]
Type=oneshot
User=devfleet-backup
Group=devfleet-backup
ExecStart=/usr/local/bin/devfleet-backup
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/run/lock /var/lib/devfleet/backup-status
ReadOnlyPaths=__WORKSPACES__ __QUARANTINE__

```


## FILE: source/app/systemd/devfleet-backup.timer

SHA256: 52148ce1d51758771ea6aa53c5168ab750af865b40a4b084334359f800796a7e | Bytes: 207 | Git mode: 100644

```
[Unit]
Description=Run DevFleet workspace backup every 15 minutes
[Timer]
OnBootSec=5min
OnUnitActiveSec=__BACKUP_INTERVAL_MINUTES__min
RandomizedDelaySec=60
Persistent=true
[Install]
WantedBy=timers.target

```


## FILE: source/app/systemd/devfleet-vault-broker.socket

SHA256: 9bfd790f5f2152ac43bdc78fb56efc3924c1f10975f31c0995a1cb690d64836f | Bytes: 331 | Git mode: 100644

```
[Unit]
Description=DevFleet bounded Vault operation socket

[Socket]
ListenStream=/run/devfleet-vault-broker.sock
SocketUser=root
SocketGroup=devfleet-control
SocketMode=0660
Accept=yes
MaxConnections=1
MaxConnectionsPerSource=1
TriggerLimitIntervalSec=60s
TriggerLimitBurst=20
RemoveOnStop=true

[Install]
WantedBy=sockets.target

```


## FILE: source/app/systemd/devfleet-vault-broker@.service

SHA256: 4431ccb294f011419df43b9475954cfed6ff3f570d600074b4b5bda5037ef1da | Bytes: 866 | Git mode: 100644

```
[Unit]
Description=DevFleet bounded Vault operation broker
After=network-online.target tailscaled.service

[Service]
Type=exec
User=devfleet-backup
Group=devfleet-backup
ExecStart=/usr/local/bin/devfleet-vault-broker
StandardInput=socket
StandardOutput=socket
StandardError=journal
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=read-only
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
LockPersonality=true
RestrictRealtime=true
RestrictSUIDSGID=true
# Backup configuration creates this directory. Before configuration the broker
# must start to return its authenticated refusal; the absent path stays read-only.
ReadWritePaths=/run/lock -/var/lib/devfleet/backup-status __WORKSPACES__ __QUARANTINE__
UMask=0077
TimeoutStartSec=30
RuntimeMaxSec=3660
TimeoutStopSec=10
KillMode=control-group

```


## FILE: source/app/systemd/devfleet.service

SHA256: f33f84cc58fc18f2217a064cc40d9a55bbb14a008a664609b29d0518183a5cca | Bytes: 897 | Git mode: 100644

```
[Unit]
Description=DevFleet remote development control plane
After=network-online.target tailscaled.service
Wants=network-online.target
[Service]
User=devfleet-control
Group=devfleet-control
SupplementaryGroups=devrunner
WorkingDirectory=/opt/devfleet
Environment=PYTHONUNBUFFERED=1
Environment=DOCKER_HOST=unix:///run/user/__DEVRUNNER_UID__/docker.sock
EnvironmentFile=/etc/devfleet/secrets.env
# The application enforces loopback plus the configured Tailscale CIDR at the
# TCP peer boundary.  Do not trust forwarded headers from arbitrary interfaces.
ExecStart=/opt/devfleet/venv/bin/uvicorn devfleet.main:app --host 0.0.0.0 --port __PORT__
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=__WORKSPACES__ __QUARANTINE__ __TRANSACTION_ROOT__ /var/lib/devfleet /var/cache/devfleet
[Install]
WantedBy=multi-user.target

```


## FILE: source/app/systemd/mutable-paths.json

SHA256: 00862e8161b5dbe817a5e4a4e2ce662c67b43fa45c160a9070b5b624db1f8069 | Bytes: 202 | Git mode: 100644

```
{
  "schema_version": 1,
  "workspace": "/home/devrunner/workspaces",
  "quarantine": "/home/devrunner/.devfleet-quarantine",
  "transaction_root": "/home/devrunner/workspaces/.devfleet-transactions"
}

```


## FILE: source/app/templates/index.html

SHA256: 0fdd41703ebacd3f0231d7f18a74d908dbdc19f629f120d6af65c49b3707e559 | Bytes: 46645 | Git mode: 100644

```
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>DevFleet · {{ status.friendly_name }}</title>
<link rel="stylesheet" href="/static/style.css?v={{ version|default(status.version|default('unknown', true), true) }}-r5">
<script src="/static/app.js?v={{ version|default(status.version|default('unknown', true), true) }}-r5" defer></script>
</head>
<body class="{{ 'advanced-mode' if request.cookies.get('devfleet_advanced') == '1' else '' }}">
{% macro csrf() %}<input type="hidden" name="csrf_token" value="{{ csrf_token }}">{% endmacro %}
{% macro status_badge(value) %}{% set state=value|default('unknown', true)|lower %}<span class="status-badge {{ 'ok' if state in ['online','running','healthy','ready','completed','verified'] else 'neutral' if state in ['stopped','unknown','not-checked','not-verified','offline'] else 'warn' if state in ['starting','provisioning','restart-required','queued','degraded','unavailable'] else 'bad' }}" role="status">{{ state|replace('-', ' ') }}</span>{% endmacro %}
{% macro runtime_label(p) %}{% if p.runtime_isolation|default('container', true) == 'vm' %}Dedicated VM{% else %}Project-isolated containers{% endif %}{% endmacro %}
{% macro provider_label(p) %}{{ p.runtime_provider|default(p.provider|default('unassigned', true), true)|replace('-', ' ')|title }}{% endmacro %}
{% macro workspace_target(p) %}{% if p.runtime_isolation|default(p.runtime_type|default('container', true), true) == 'vm' and p.lifecycle_status|default('') == 'stopped' %}stopped — address refreshes on start{% else %}{{ p.workspace_host|default(p.runtime_address|default(p.host_id|default(provider_label(p), true), true), true) }}{% endif %}{% endmacro %}
{% macro open_workspace(p) %}{% set ssh_alias=p.ssh_alias|default(p.runtime_id if p.runtime_isolation|default('container', true) == 'vm' and p.runtime_id else 'devfleet-primary', true) %}{% set remote_path=p.workspace_path|default('/home/devrunner/workspaces/' ~ p.slug, true) %}{% set readiness=p.workspace_readiness|default({}, true) %}{% if readiness.ready %}<a class="button ghost workspace-link" href="/projects/{{ p.slug|urlencode }}/workspace" data-provider="{{ provider_label(p) }}" data-ssh-alias="{{ ssh_alias }}" data-workspace-target="{{ workspace_target(p) }}" title="Open {{ ssh_alias }}:{{ remote_path }} in VS Code">Open workspace</a>{% else %}<button class="button ghost disabled workspace-link" type="button" disabled data-provider="{{ provider_label(p) }}" data-ssh-alias="{{ ssh_alias }}" data-workspace-target="{{ workspace_target(p) }}" title="{{ readiness.reason|default('Workspace readiness has not been verified.', true) }}">Open workspace</button><small class="workspace-readiness-note">{{ readiness.reason|default('Workspace readiness has not been verified.', true) }}</small>{% endif %}{% endmacro %}
{% macro resource_allocation(p) %}{% set limits=p.resource_limits|default({}, true) %}<div class="resource-allocation" data-resource-profile="{{ p.resource_profile|default('standard', true) }}"><div><small>Environment</small><strong>{{ runtime_label(p) }}</strong></div><div><small>Allocation</small><strong>{{ p.resource_profile_label|default(p.resource_profile|default('standard', true)|title, true) }}</strong></div><div><small>CPU</small><strong>{{ limits.cpus|default(limits.vcpus|default('—', true), true) }}</strong></div><div><small>RAM</small><strong>{{ limits.memory|default(limits.memory_gb ~ ' GB' if limits.memory_gb else '—', true) }}</strong></div><div><small>Disk</small><strong>{{ limits.disk_gb|default('—', true) }} GB</strong></div><div><small>PID limit</small><strong>{{ 'Not applicable — VM isolation' if p.runtime_isolation|default(p.runtime_type|default('container', true), true) == 'vm' else limits.pids|default('—', true) }}</strong></div></div><p class="muted resource-telemetry"><strong>Runtime telemetry:</strong> {{ 'Unavailable while stopped' if p.lifecycle_status|default('') == 'stopped' else p.health_scope|default('Not checked', true)|replace('-', ' ')|title }}</p>{% endmacro %}
{% macro project_action(slug, action, label, style='') %}<form method="post" action="/projects/{{ slug }}/{{ action }}" class="project-action-form" data-project-action="{{ action }}">{{ csrf() }}<button class="{{ style }}" type="submit">{{ label }}</button></form>{% endmacro %}
  <div id="devfleet-csrf" data-token="{{ csrf_token }}" hidden></div>
  <script id="devfleet-cluster-data" type="application/json">{{ cluster|tojson }}</script>
  <svg class="icon-sprite" aria-hidden="true" focusable="false"><symbol id="icon-home" viewBox="0 0 24 24"><path d="M3 10.5 12 3l9 7.5v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 19.5z" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M9 21v-6h6v6" fill="none" stroke="currentColor" stroke-width="1.6"/></symbol><symbol id="icon-grid" viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="14" y="3" width="7" height="7" rx="1" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="3" y="14" width="7" height="7" rx="1" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="14" y="14" width="7" height="7" rx="1" fill="none" stroke="currentColor" stroke-width="1.6"/></symbol><symbol id="icon-server" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="6" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="3" y="14" width="18" height="6" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M7 7h.01M7 17h.01" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/></symbol><symbol id="icon-activity" viewBox="0 0 24 24"><path d="M3 12h4l2-7 4 14 2-7h6" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></symbol><symbol id="icon-settings" viewBox="0 0 24 24"><path d="M9.5 3h5l.7 2.2 2 .9 2.1-1 2.2 3.8-1.6 1.7v2.3l1.6 1.7-2.2 3.8-2.1-1-2 .9-.7 2.2h-5l-.7-2.2-2-.9-2.1 1-2.2-3.8 1.6-1.7v-2.3L2.5 8.9l2.2-3.8 2.1 1 2-.9z" fill="none" stroke="currentColor" stroke-width="1.4"/><circle cx="12" cy="12" r="2.5" fill="none" stroke="currentColor" stroke-width="1.6"/></symbol></svg>
<div class="app-shell" id="devfleet-app" data-view="{{ view }}">
  <aside class="sidebar">
    <a class="brand" href="/?view=overview"><span class="brand-mark">DF</span><span><strong>DevFleet</strong><small>Safe remote development</small></span></a>
    <nav class="primary-nav" aria-label="Primary navigation">
      <a class="{{ 'active' if view == 'overview' else '' }}" href="/?view=overview"><svg aria-hidden="true"><use href="#icon-home"></use></svg> Overview</a>
      <a class="{{ 'active' if view in ['projects','project'] else '' }}" href="/?view=projects"><svg aria-hidden="true"><use href="#icon-grid"></use></svg> Projects</a>
      <a class="{{ 'active' if view == 'infrastructure' else '' }}" href="/?view=infrastructure"><svg aria-hidden="true"><use href="#icon-server"></use></svg> Infrastructure</a>
      <a class="{{ 'active' if view == 'activity' else '' }}" href="/?view=activity"><svg aria-hidden="true"><use href="#icon-activity"></use></svg> Activity</a>
      <a class="{{ 'active' if view == 'settings' else '' }}" href="/?view=settings"><svg aria-hidden="true"><use href="#icon-settings"></use></svg> Settings</a>
    </nav>
    <div class="sidebar-footer">
      <div class="node-presence"><span class="presence-dot"></span><span><strong>{{ status.friendly_name }}</strong><small>{{ status.node }} · {{ status.role }}</small></span></div>
<span class="version-label">DevFleet v{{ status.version|default('unknown', true) }}</span>
    </div>
  </aside>
  <main class="app-main">
    <header class="topbar">
      <div><p class="eyebrow">{{ 'PROJECT WORKSPACE' if view == 'project' else view|upper }}</p><h1>{% if view == 'project' and selected_project %}{{ selected_project.display_name }}{% elif view == 'overview' %}{{ status.greeting|default('DevFleet overview', true) }}{% else %}{{ view|capitalize }}{% endif %}</h1></div>
      <div class="topbar-actions"><span class="connection-pill"><span class="presence-dot"></span> {{ status.friendly_name }} online</span><a class="button primary" href="/?view=projects#create-project">New project</a><form method="post" action="/logout" class="inline-form">{{ csrf() }}<button class="button ghost" type="submit">Sign out</button></form></div>
    </header>
    {% if operation %}
    <section class="operation-banner {{ 'failed' if operation.state == 'failed' else 'complete' if operation.state == 'completed' else '' }}" aria-live="polite" data-operation-id="{{ operation.id }}">
      <div class="operation-icon">{{ '!' if operation.state == 'failed' else '✓' if operation.state == 'completed' else '…' }}</div>
      <div class="operation-copy"><strong>{{ operation.kind|replace('-', ' ')|title }}</strong><span data-operation-message>{{ operation.message }}</span><div class="progress-track"><span data-operation-progress style="width:{{ operation.progress }}%"></span></div></div>
      <div class="operation-meta" data-operation-meta>{{ operation.progress }}% · {{ operation.state }}<br><small>Updated {{ operation.updated_at }}</small></div>
      <details class="advanced operation-details"><summary>Details</summary><pre>{% for line in operation.log %}{{ line.time }}  {{ line.message }}&#10;{% endfor %}{{ operation.result or operation.error or '' }}</pre></details>
    </section>
    {% endif %}

    {% if view == 'overview' %}
    <section class="hero-grid">
      <article class="hero-card"><div class="eyebrow">DEVFLEET OVERVIEW</div><h2>Your environments at a glance.</h2><p>Manage projects, runtime isolation, and infrastructure from one safe control plane. GPU passthrough remains disabled.</p><div class="hero-actions"><a class="button primary" href="/?view=projects">Open projects</a><a class="button ghost" href="/?view=infrastructure">View infrastructure</a></div></article>
      <article class="health-card"><div class="card-heading"><span class="icon-tile green">✓</span><div><h3>Node health</h3><p class="muted">{{ status.friendly_name }}</p></div></div><div class="health-score">{{ status.host_agent.status|default('ready', true)|replace('-', ' ')|title }}</div><p class="muted">Docker {{ status.docker.mode|default('ready', true) }} · {{ status.system.disk_free_gb }} GB free</p><a href="/?view=infrastructure">Inspect infrastructure →</a></article>
    </section>
    <section class="stats-grid">
      <article class="stat-card"><span class="stat-label">Projects</span><strong>{{ status.projects|length }}</strong><small>managed workspaces</small></article>
      <article class="stat-card"><span class="stat-label">Dedicated VMs</span><strong>{{ status.projects|selectattr('runtime_isolation','equalto','vm')|list|length }}</strong><small>project environments</small></article>
      <article class="stat-card"><span class="stat-label">Memory</span><strong>{{ status.system.memory_percent }}%</strong><small>host utilization</small></article>
      <article class="stat-card"><span class="stat-label">Disk free</span><strong>{{ status.system.disk_free_gb }}</strong><small>GB on the DevFleet host</small></article>
    </section>
    <section class="content-grid two-thirds">
      <article class="panel"><div class="section-heading"><div><p class="eyebrow">YOUR WORK</p><h2>Projects</h2></div><a href="/?view=projects">View all →</a></div><div class="project-list">{% for p in status.projects[:4] %}<a class="project-row" href="/projects/{{ p.slug }}"><span class="project-avatar">{{ (p.display_name|default(p.slug, true))[0]|upper }}</span><span class="project-row-copy"><strong>{{ p.display_name|default(p.slug, true) }}</strong><small>{{ runtime_label(p) }} · {{ p.resource_profile|default('standard', true)|title }}</small></span>{{ status_badge('running' if p.running else p.runtime_status|default('ready', true)) }}<span class="chevron">›</span></a>{% else %}<p class="muted">No projects yet.</p>{% endfor %}</div></article>
      <article class="panel"><div class="section-heading"><div><p class="eyebrow">RECENT</p><h2>Activity</h2></div><a href="/?view=activity">View all →</a></div>{% for op in status.operations[:5] %}<a class="activity-row" href="/?view=activity#{{ op.id }}"><span class="activity-dot {{ 'bad' if op.state == 'failed' else 'ok' if op.state == 'completed' else 'warn' }}"></span><span><strong>{{ op.kind|replace('-', ' ')|title }}</strong><small>{{ op.project }} · {{ op.message }}</small></span><time>{{ op.updated_at }}</time></a>{% else %}<p class="muted">No recent operations.</p>{% endfor %}</article>
    </section>
    <section class="panel"><div class="section-heading"><div><p class="eyebrow">CONNECTED INFRASTRUCTURE</p><h2>DevFleet nodes</h2></div><a href="/?view=infrastructure">Manage infrastructure →</a></div><div id="cluster-nodes" class="node-grid" data-endpoint="/cluster/status"><p class="muted">Loading node health…</p></div><span id="cluster-updated" class="muted"></span></section>

    {% elif view == 'projects' %}
    <section class="page-intro"><div><p class="eyebrow">WORKSPACES</p><h2>Projects</h2><p class="muted">Every project keeps its workspace and gets an explicit, reviewable environment assignment.</p></div><a class="button primary" href="#create-project">New project</a></section>
    <section class="project-card-grid">{% for p in status.projects %}<article class="project-card"><div class="project-card-top"><span class="project-avatar large">{{ (p.display_name|default(p.slug, true))[0]|upper }}</span><div><h3>{{ p.display_name|default(p.slug, true) }}</h3><p class="muted">{{ p.slug }}</p></div>{{ status_badge('running' if p.running else p.runtime_status|default('ready', true)) }}</div><div class="project-facts"><div><small>Environment</small><strong>{{ runtime_label(p) }}</strong></div><div><small>Provider</small><strong>{{ provider_label(p) }}</strong></div><div><small>Workspace</small><strong class="truncate">{{ workspace_target(p) }}</strong></div><div><small>Resources</small><strong>{{ p.resource_profile_label|default(p.resource_profile|default('standard', true)|title, true) }} · {{ p.resource_limits.cpus|default('—', true) }} CPU · {{ p.resource_limits.memory|default('—', true) }}</strong></div></div><p class="muted project-summary">{{ p.language|default('Existing', true)|title }}{% if p.framework %} · {{ p.framework }}{% endif %} · {{ 'Workspace ready' if p.workspace_readiness.ready else 'Workspace readiness pending' }}</p>{% if p.recovery_only %}<div class="runtime-unavailable" data-recovery-only="{{ p.slug }}"><strong>Recovery artifact only</strong><p>This restored copy is inert. Its files are available for inspection, but runtime actions require a separate explicit adoption.</p></div>{% else %}<div class="card-actions">{{ open_workspace(p) }}{% if p.running %}{{ project_action(p.slug,'stop','Stop','ghost') }}{% else %}{{ project_action(p.slug,'start','Start') }}{% endif %}<a class="icon-button" href="/projects/{{ p.slug }}?tab=settings" title="Project settings">•••</a></div>{% endif %}<details class="advanced"><summary>Advanced details</summary><pre>{{ {'provider':p.runtime_provider|default('docker-compose',true),'runtime_id':p.runtime_id|default('',true),'host_id':p.host_id|default('',true),'limits':p.resource_limits|default({},true),'workspace_readiness':p.workspace_readiness|default({},true),'backup':p.backup_status|default('not-verified',true)}|tojson(indent=2) }}</pre></details></article>{% else %}<article class="empty-state"><h3>No projects yet</h3><p>Create a project to get started.</p></article>{% endfor %}</section>
    <section id="create-project" class="panel wizard-panel"><div class="section-heading"><div><p class="eyebrow">PROJECT SETUP</p><h2>Create a project</h2><p class="muted">The wizard recommends resources from project complexity and keeps GPU access disabled.</p></div></div><form method="post" action="/projects/create" class="wizard-form" data-environment-wizard>{{ csrf() }}<div class="form-step"><span class="step-number">1</span><div><h3>Project identity</h3><div class="form-grid"><label>Name<input name="display_name" required autocomplete="off" placeholder="M0TechLabs Job Finder"></label><label>Slug<input name="slug" required pattern="[a-z0-9][a-z0-9._-]{1,62}" autocomplete="off" placeholder="m-techlabs-job-finder"></label><label>Project kind<select name="project_kind"><option value="">General</option><option>automation</option><option>rapid-api</option><option>cross-platform-cli</option><option>web-frontend</option><option>full-stack-web</option><option>infrastructure-service</option></select></label></div></div></div><div class="form-step"><span class="step-number">2</span><div><h3>Environment</h3><div class="form-grid"><label>Environment type<select name="runtime_isolation"><option value="">Recommend automatically</option><option value="container">Project-isolated containers on shared host</option><option value="vm">Dedicated project VM</option></select></label><label>Resources<select name="resource_profile"><option value="">Recommend automatically</option><option value="small">Small · 1 CPU · 2 GB · 20 GB</option><option value="standard">Standard · 2 CPU · 4 GB · 40 GB</option><option value="large">Large · 4 CPU · 8 GB · 80 GB</option><option value="xlarge">Extra large · 6 CPU · 12 GB · 120 GB</option></select></label><label>Scale<select name="scale"><option>small</option><option>medium</option><option>large</option></select></label><label>Intent<select name="intent"><option>prototype</option><option>production</option></select></label></div></div></div><details class="advanced form-advanced"><summary>Advanced project inputs</summary><div class="form-grid"><label>Template<select name="template"><option value="auto">Recommend automatically</option>{% for name in templates_catalog %}<option>{{ name }}</option>{% endfor %}</select></label><label>Language<input name="language" placeholder="python, typescript, go..."></label><label>Framework<input name="framework" placeholder="FastAPI, Next.js, Spring..."></label><label>GitHub URL<input name="git_url"></label><label>Worktree source<input name="worktree_source"></label><label>Worktree branch<input name="worktree_branch"></label><label>Security profile<select name="profile"><option>balanced</option><option>strict</option></select></label><label>Testing<select name="testing_level"><option>standard</option><option>minimal</option><option>comprehensive</option></select></label><label class="checkbox-label"><input type="checkbox" name="use_ollama"> Use Ollama</label></div></details><fieldset class="custom-resource-controls"><legend>Custom resource controls</legend><div class="form-grid"><label>CPU cores<input name="custom_cpus" type="number" min="1" max="32" step="1" placeholder="Auto"></label><label>RAM (GB)<input name="custom_ram_gb" type="number" min="1" max="256" step="1" placeholder="Auto"></label><label>Disk (GB)<input name="custom_disk_gb" type="number" min="20" max="2048" step="1" placeholder="Auto"></label><label>PID mode<select name="pid_mode"><option value="private">Private PID namespace</option><option value="host">Host PID namespace (review required)</option></select></label><label>PID limit<input name="pid_limit" type="number" min="64" max="65536" step="1" value="4096"></label></div><p class="muted help-text">These values are captured for review. Backend support may apply them during a later environment assignment.</p></fieldset><section class="wizard-review" aria-live="polite"><div><strong>Review environment</strong><span data-review-summary>Automatic recommendation · PID limit 4096</span></div><span class="status-badge neutral" data-review-status>Review before provisioning</span></section><div class="review-note"><strong>Before provisioning</strong><span>DevFleet checks host CPU, RAM, disk, VM count, and reserved headroom. Dedicated VMs are host-assisted, GPU-free, and rollback-aware.</span></div><button class="button primary" type="submit">Create project</button></form></section>

    {% elif view == 'project' and selected_project %}
    {% set p = selected_project %}{% set caps = p.capabilities|default({}, true) %}{% set lifecycle = caps.lifecycle_state|default(p.lifecycle_status|default('unknown', true), true) %}{% if p.recovery_only %}<section class="panel recovery-only-panel" data-recovery-only="{{ p.slug }}"><a class="back-link" href="/?view=projects">← All projects</a><div class="eyebrow">RECOVERY ARTIFACT</div><h2>{{ p.display_name|default(p.slug, true) }}</h2><p>This restored copy is intentionally inert. DevFleet will not inspect, start, modify, back up, restore, quarantine, or delete it as a managed project.</p><p class="muted">Workspace path: <code>{{ p.path }}</code></p><div class="runtime-unavailable"><strong>Separate adoption required</strong><p>Review the recovered files, then use a future explicit ownership-adoption workflow before enabling any runtime action. The original managed project remains unchanged.</p></div></section>{% else %}<section class="project-hero" data-project-state="{{ lifecycle }}"><a class="back-link" href="/?view=projects">← All projects</a>{% if lifecycle == 'stopped' %}<div class="project-state-banner stopped" role="status"><div><strong>Project is stopped</st