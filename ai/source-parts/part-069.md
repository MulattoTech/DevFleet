# DevFleet source part 069

Full-source UTF-8 byte interval [3162000, 3208500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: be4a5ac37099a09314790fdec04323c3c42f34d116d284c8b0f65e78ea035c43

<!-- BEGIN SOURCE SLICE -->
lueError("Workspace imports are limited to a DevFleet source VM.")
    if not runtime_id:
        raise ValueError("A target project VM runtime id is required for workspace import.")
    payload = {"slug": slug, "project_id": project_id, "source_vm": source_vm}
    return host_control_request("import", payload, runtime_id=runtime_id)


def sync_project_vm_ssh_alias(slug: str, runtime_id: str, *, project_id: str = "") -> dict[str, Any]:
    """Create or refresh the host-owned alias for one dedicated project VM.

    The host agent derives both alias and address from its ownership registry;
    callers cannot submit SSH configuration text or an arbitrary host.
    """
    slug = validate_slug(slug)
    project_id = validate_project_id(project_id)
    if not runtime_id:
        raise ValueError("A project VM runtime id is required for SSH alias synchronization.")
    return host_control_request("sync-ssh-alias", {"slug": slug, "project_id": project_id}, runtime_id=runtime_id)


def refresh_project_vm_connection_state(slug: str, runtime_id: str, *, project_id: str = "") -> dict[str, Any]:
    """Reconcile the current owned VM address, registry, and pinned SSH alias."""
    slug = validate_slug(slug)
    project_id = validate_project_id(project_id)
    if not runtime_id:
        raise ValueError("A project VM runtime id is required for connection-state refresh.")
    return host_control_request("refresh-connection-state", {"slug": slug, "project_id": project_id}, runtime_id=runtime_id)


def export_project_workspace(slug: str, runtime_id: str, *, project_id: str = "") -> dict[str, Any]:
    slug = validate_slug(slug)
    project_id = validate_project_id(project_id)
    if not runtime_id:
        raise ValueError("A project VM runtime id is required for workspace export.")
    return host_control_request("export", {"slug": slug, "project_id": project_id}, runtime_id=runtime_id)


def export_project_workspace_to_source(slug: str, runtime_id: str, *, source_vm: str, project_id: str = "", replace_source: bool = False) -> dict[str, Any]:
    slug = validate_slug(slug)
    source_vm = validate_slug(source_vm)
    project_id = validate_project_id(project_id)
    if not source_vm.startswith("devfleet-") or not runtime_id:
        raise ValueError("VM export requires a DevFleet source VM and target runtime id.")
    return host_control_request("export-to-source", {"slug": slug, "project_id": project_id, "source_vm": source_vm, "replace_source": bool(replace_source)}, runtime_id=runtime_id)


def restore_previous_source_workspace(slug: str, runtime_id: str, *, source_vm: str, project_id: str, previous_workspace_path: str) -> dict[str, Any]:
    """Atomically reinstate the source workspace retained by a VM export."""
    slug = validate_slug(slug)
    source_vm = validate_slug(source_vm)
    project_id = validate_project_id(project_id)
    if not source_vm.startswith("devfleet-") or not runtime_id or not previous_workspace_path:
        raise ValueError("Restoring a previous source workspace requires a DevFleet source VM, runtime id, and retained path.")
    payload = {"slug": slug, "project_id": project_id, "source_vm": source_vm, "previous_workspace_path": previous_workspace_path}
    return host_control_request("restore-previous-source", payload, runtime_id=runtime_id)


def project_vm_operation(slug: str, operation: str, *, runtime_id: str = "", project_id: str = "", command_key: str = "", tail: int = 150) -> dict[str, Any]:
    slug = validate_slug(slug)
    project_id = validate_project_id(project_id)
    if operation not in {"project-start", "project-stop", "project-restart", "project-health", "project-test", "project-bootstrap", "project-rebuild", "project-logs"}:
        raise ValueError("Unsupported structured project VM operation.")
    payload: dict[str, Any] = {"slug": slug, "project_id": project_id}
    if command_key:
        payload["command_key"] = command_key
    if operation == "project-logs":
        payload["tail"] = max(1, min(int(tail), 500))
    return host_control_request(operation, payload, runtime_id=runtime_id)


def stop_project_vm(slug: str, *, runtime_id: str = "", project_id: str = "") -> dict[str, Any]:
    return runtime_project_vm(slug, "stop", runtime_id=runtime_id, project_id=project_id)


def destroy_project_vm(slug: str, confirm_slug: str, confirm_phrase: str, *, backup_verified: bool = False, backup_id: str = "", backup_sha256: str = "", cleanup_only: bool = False, cleanup_stage: str = "", local_archive_sha256: str = "", import_archive_sha256: str = "", runtime_id: str = "", project_id: str = "") -> dict[str, Any]:
    slug = validate_slug(slug)
    if confirm_slug != slug or confirm_phrase != f"DESTROY {slug}":
        raise ValueError("Permanent destruction requires the exact project slug and confirmation phrase.")
    if not cleanup_only and (not backup_id or not backup_sha256):
        raise ValueError("Permanent VM destruction requires an identified, hashed workspace backup artifact.")
    if cleanup_only:
        if not backup_verified or not backup_id:
            raise ValueError("Failed-migration cleanup requires a verified provider-aware backup identity.")
        if cleanup_stage not in {"pre-import", "post-import"}:
            raise ValueError("Failed-migration cleanup requires an explicit pre-import or post-import stage.")
        if not re.fullmatch(r"[0-9a-fA-F]{64}", str(backup_sha256 or "")) or not re.fullmatch(r"[0-9a-fA-F]{64}", str(local_archive_sha256 or "")):
            raise ValueError("Failed-migration cleanup requires verified provider and local archive SHA-256 values.")
        if cleanup_stage == "post-import" and import_archive_sha256 and not re.fullmatch(r"[0-9a-fA-F]{64}", str(import_archive_sha256)):
            raise ValueError("Failed-migration cleanup import archive SHA-256 is malformed.")
    payload = {"slug": slug, "project_id": project_id, "confirm_slug": confirm_slug, "confirm_phrase": confirm_phrase, "backup_verified": bool(backup_verified), "backup_id": backup_id, "backup_sha256": backup_sha256, "cleanup_only": bool(cleanup_only), "cleanup_stage": cleanup_stage, "local_archive_sha256": local_archive_sha256, "import_archive_sha256": import_archive_sha256}
    return host_control_request("destroy", payload, runtime_id=runtime_id)

```


## FILE: source/app/devfleet/language_policy.py

SHA256: d3c417f349ee93e1aefe323f09233c8e4e8d3f612914e97f0b9e32df5b81b289 | Bytes: 2079 | Git mode: 100644

```
from __future__ import annotations
TEMPLATES={
'generic':('other','none','core'),'python':('python','standard-library','core'),'python-fastapi':('python','fastapi','core'),'node':('javascript','node','core'),'typescript-node':('typescript','node','core'),'typescript-next':('typescript','nextjs','core'),'go-service':('go','net-http','core'),'dotnet-service':('csharp','aspnet-core','core'),'java-spring':('java','spring-boot','core'),'rust-service':('rust','axum','core'),
'kotlin-service':('kotlin','ktor','preview'),'php-laravel':('php','laravel','preview'),'ruby-rails':('ruby','rails','preview'),'flutter':('dart','flutter','preview'),'elixir-phoenix':('elixir','phoenix','preview'),'cpp-cmake':('cpp','cmake','preview'),'shell-automation':('shell','bash','preview'),'data-r':('r','base-r','preview'),'scientific-julia':('julia','base-julia','preview'),'sql-project':('sql','migrations','preview')}
def recommend_template(language:str='',framework:str='',scale:str='',intent:str='',project_kind:str='')->str:
 l=language.lower();f=framework.lower();k=project_kind.lower()
 if 'fastapi' in f or k=='rapid-api':return 'python-fastapi'
 if 'next' in f or k in {'web-frontend','full-stack-web','browser-extension','vscode-extension'}:return 'typescript-next' if 'next' in f or k=='full-stack-web' else 'typescript-node'
 return {'python':'python','javascript':'node','typescript':'typescript-node','go':'go-service','csharp':'dotnet-service','c#':'dotnet-service','java':'java-spring','rust':'rust-service','kotlin':'kotlin-service','php':'php-laravel','ruby':'ruby-rails','dart':'flutter','elixir':'elixir-phoenix','cpp':'cpp-cmake','c++':'cpp-cmake','shell':'shell-automation','bash':'shell-automation','r':'data-r','julia':'scientific-julia','sql':'sql-project'}.get(l,'generic')
def template_metadata(name:str)->dict[str,str]:
 language,framework,maturity=TEMPLATES[name];return {'language':language,'framework':framework,'template_maturity':maturity,'language_rationale':"Selected using Dylan's DevFleet engineering preferences; this is not a scientific model benchmark."}

```


## FILE: source/app/devfleet/leases.py

SHA256: 968255eb2ab9f4121cb561dc474a382b3c47e7dcbe8c08936cda7022abfb7b31 | Bytes: 1668 | Git mode: 100644

```
from __future__ import annotations
from pathlib import Path
from typing import Any
from .core import SETTINGS,atomic_json,now_iso,run
from .metadata_io import read_project_metadata
def lease_path(project:Path)->Path:return project/'.devfleet'/'ownership-lease.json'
def load_lease(project:Path)->dict[str,Any]:
 try:return __import__('json').loads(lease_path(project).read_text())
 except Exception:return {}
def _git(project:Path)->tuple[str,bool]:
 commit=run(['git','rev-parse','HEAD'],cwd=project,check=False,timeout=15).stdout.strip();dirty=bool(run(['git','status','--porcelain'],cwd=project,check=False,timeout=15).stdout.strip());return commit,dirty
def update_lease(project:Path,*,active:bool|None=None,clean_shutdown:bool|None=None,backup_time:str|None=None,active_node:str|None=None)->dict[str,Any]:
 data=load_lease(project);meta={}
 try:
  value=read_project_metadata(project).value
  meta=value if isinstance(value,dict) else {}
 except Exception:pass
 commit,dirty=_git(project);now=now_iso();data.update({'project_identity':meta.get('identity',project.name),'project_id':meta.get('project_id',''),'active_node':(active_node or SETTINGS.node_name) if active is not None else data.get('active_node'),'heartbeat_time':now,'git_commit':commit,'working_tree_dirty':dirty})
 if active is not None:
  data['active']=active
  if active:data['start_time']=now;data['last_clean_shutdown']=None
 if clean_shutdown is not None:data['last_clean_shutdown']=now if clean_shutdown else None
 if backup_time:data['last_backup']=backup_time
 atomic_json(lease_path(project),data);return data
def heartbeat_lease(project:Path)->dict[str,Any]:return update_lease(project)

```


## FILE: source/app/devfleet/main.py

SHA256: 1da87d821f4910f3d0e86f39592593a351b55ab83a62174b90ffa62a80add618 | Bytes: 67806 | Git mode: 100644

```
from __future__ import annotations
from urllib.parse import quote, urlsplit
import hashlib, html, hmac, json, logging, os, re
from pathlib import Path
from typing import Any
from fastapi import Depends, FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
import httpx
from .auth import (
    LOGIN_CSRF_COOKIE,
    SESSION_COOKIE,
    check_api,
    check_session,
    issue_session,
    login_csrf_token,
    login_retry_after,
    revoke_session,
    safe_next,
    session_cookie_options,
    session_csrf_token,
    session_user,
    validate_login_csrf,
    valid_credentials,
)
from .core import (
    SETTINGS,
    load_peer,
    safe_child,
    validate_project_id,
    validate_slug,
    run,
    client_allowed_by_network,
)
from .projects import (
    create_project,
    start_project,
    stop_project,
    restart_project,
    inspect_runtime,
    runtime_health,
    open_workspace,
    rebuild_project,
    quarantine_project,
    destroy_project,
    list_backups,
    restore_backup,
    list_quarantine,
    restore_quarantine,
    restore_from_vault,
    backup_project,
    test_project,
    load_authoritative_project_identity_for_mutation,
    load_meta,
    metadata_path,
    commit_project_metadata,
    project_logs,
    bootstrap_codexpro,
    bootstrap_project,
    health_project,
    assign_project_runtime,
    detect_runtime,
    project_command_readiness,
    project_capabilities,
    reconcile_failed_migration,
    assert_project_quiesced_for_transfer,
    finalize_source_transfer,
    project_transfer_lock,
    receive_transferred_project,
    activate_transferred_project,
)
from .status import (
    cluster_snapshot,
    local_status,
    peer_status,
    peer_node_status,
    runtime_status,
    cluster_status,
)
from .containers import (
    container_action,
    container_logs,
    inspect_container,
    list_containers,
    validate_container_ref,
)
from .operations import submit_operation, get_operation, list_operations
from .analyzer import analyze_project
from .language_policy import TEMPLATES, recommend_template
from .resource_profiles import (
    RESOURCE_PROFILES,
    RUNTIME_ISOLATIONS,
    capacity_allows,
    custom_resource_metadata,
    recommend_resource_profile,
    recommend_runtime_isolation,
)
from .host_control import host_control_status, get_host_capacity, get_provider_status
from .failover import guided_transfer
from .workspace_archives import inspect_workspace
from .request_guards import RequestAdmissionMiddleware
from .version import __version__

app = FastAPI(title="DevFleet", version=__version__, docs_url=None, redoc_url=None)
LOGGER = logging.getLogger("devfleet")
templates = Jinja2Templates(
    directory=str(
        Path(os.environ.get("DEVFLEET_TEMPLATE_DIR", "/opt/devfleet/templates"))
    )
)
app.mount(
    "/static",
    StaticFiles(
        directory=str(
            Path(os.environ.get("DEVFLEET_STATIC_DIR", "/opt/devfleet/static"))
        ),
        check_dir=True,
    ),
    name="static",
)
app.add_middleware(RequestAdmissionMiddleware)


def ui_csrf_token(request: Request | None = None) -> str:
    if request is None:
        raise ValueError("A request-bound session is required for UI CSRF generation.")
    return session_csrf_token(request)


def valid_ui_csrf(value: str, request: Request | None = None) -> bool:
    expected = ui_csrf_token(request)
    return bool(value and expected) and hmac.compare_digest(value, expected)


@app.middleware("http")
async def headers(request: Request, call_next):
    started = __import__("time").perf_counter()
    response = await call_next(request)
    duration = (__import__("time").perf_counter() - started) * 1000
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; style-src 'self'; script-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
    )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = (
        "public, max-age=31536000, immutable"
        if request.url.path.startswith("/static/")
        else "no-store"
    )
    response.headers["Server-Timing"] = f"app;dur={duration:.2f}"
    response.headers["X-DevFleet-Render-Ms"] = f"{duration:.2f}"
    return response


@app.middleware("http")
async def network_guard(request: Request, call_next):
    if not client_allowed_by_network(request.client.host if request.client else None):
        return JSONResponse(
            {
                "detail": "Portal access is restricted to loopback and the configured Tailscale network."
            },
            status_code=403,
        )
    return await call_next(request)


def _human_ui_route(path: str) -> bool:
    return path == "/" or path.startswith(
        (
            "/projects",
            "/cluster",
            "/containers",
            "/peer",
            "/operations",
            "/ui",
            "/quarantine",
            "/repair",
        )
    )


@app.middleware("http")
async def session_guard(request: Request, call_next):
    if _human_ui_route(request.url.path) and not session_user(request):
        target = request.url.path + (
            (f"?{request.url.query}") if request.url.query else ""
        )
        return RedirectResponse(
            "/login?next=" + quote(safe_next(target), safe="/?:=&%"), status_code=303
        )
    return await call_next(request)


def ui(request: Request, csrf_token: str = ""):
    check_session(request)
    if request.method not in {"GET", "HEAD", "OPTIONS"}:
        if not valid_ui_csrf(csrf_token, request):
            raise HTTPException(403, "A valid session CSRF token is required.")
        expected = f"{request.url.scheme}://{request.url.netloc}"
        origin = request.headers.get("origin", "").strip()
        referer = request.headers.get("referer", "").strip()
        candidate = origin if origin.lower() not in {"", "null"} else referer
        if candidate:
            try:
                p = urlsplit(candidate)
                request_parts = urlsplit(expected)
                same_scheme = p.scheme.lower() == request_parts.scheme.lower()
                same_host = (p.hostname or "").lower() == (
                    request_parts.hostname or ""
                ).lower()

                def effective_port(parts):
                    if parts.port is not None:
                        return parts.port
                    return {"http": 80, "https": 443}.get(parts.scheme.lower())

                same_port = effective_port(p) == effective_port(request_parts)
            except ValueError:
                same_scheme = same_host = same_port = False
            if not (same_scheme and same_host and same_port):
                LOGGER.warning(
                    "Rejected form origin: origin=%r referer=%r fetch_site=%r fetch_mode=%r fetch_dest=%r scheme=%r host=%r path=%r user_agent=%r",
                    origin,
                    referer,
                    request.headers.get("sec-fetch-site", ""),
                    request.headers.get("sec-fetch-mode", ""),
                    request.headers.get("sec-fetch-dest", ""),
                    request.url.scheme,
                    request.headers.get("host", ""),
                    request.url.path,
                    request.headers.get("user-agent", ""),
                )
                raise HTTPException(403, "Cross-origin form submission rejected.")
        elif request.headers.get("sec-fetch-site", "").lower() != "same-origin":
            LOGGER.warning(
                "Rejected unverifiable form: origin=%r referer=%r fetch_site=%r fetch_mode=%r fetch_dest=%r scheme=%r host=%r path=%r user_agent=%r",
                origin,
                referer,
                request.headers.get("sec-fetch-site", ""),
                request.headers.get("sec-fetch-mode", ""),
                request.headers.get("sec-fetch-dest", ""),
                request.url.scheme,
                request.headers.get("host", ""),
                request.url.path,
                request.headers.get("user-agent", ""),
            )
            raise HTTPException(403, "Cross-origin form submission rejected.")


def peer_call(
    method: str, path: str, payload: dict | None = None, timeout: float = 1800
):
    peer = load_peer()
    if not peer.get("Url") or not peer.get("Token"):
        raise ValueError("Peer is not configured.")
    with httpx.Client(timeout=timeout) as client:
        r = client.request(
            method,
            peer["Url"].rstrip("/") + path,
            headers={"X-DevFleet-Token": peer["Token"]},
            json=payload or {},
        )
        if r.status_code >= 400:
            raise ValueError(f"Peer error {r.status_code}: {r.text[-1000:]}")
        return r.json()


def require_safe_start(slug: str, confirmed: bool) -> None:
    project = safe_child(SETTINGS.workspaces, slug)
    authoritative = load_authoritative_project_identity_for_mutation(project)
    identity = validate_slug(
        str(authoritative.get("identity") or authoritative.get("slug") or slug)
    )
    try:
        lease = __import__("json").loads(
            (project / ".devfleet/ownership-lease.json").read_text()
        )
    except Exception:
        lease = {}
    if (
        lease.get("active")
        and lease.get("active_node")
        and lease.get("active_node") != SETTINGS.node_name
        and not confirmed
    ):
        raise ValueError(
            f"Ownership lease belongs to {lease.get('active_node')}. Use guided transfer or acknowledge failover risk."
        )
    meta = authoritative
    # A project already owned by this node is not a failover operation.  The
    # peer may be offline while the local VM/container still needs an ordinary
    # start or rebuild.  Foreign ownership leases remain blocked above.
    local_host_ids = {
        str(SETTINGS.node_name or "").strip().lower(),
        str(SETTINGS.expected_host_name or "").strip().lower(),
    }
    recorded_host = str(meta.get("host_id") or "").strip().lower()
    if recorded_host in local_host_ids and str(meta.get("runtime_provider") or "") in {
        "",
        "docker-compose",
        "multipass-host-agent",
    }:
        return
    state = peer_status()
    if not state.get("configured"):
        return
    if not state.get("ok") and not confirmed:
        raise ValueError(
            "Peer is unreachable. Confirm failover risk only after verifying the project is not active there."
        )
    if state.get("ok"):
        matches = [
            x
            for x in state["peer"].get("projects", [])
            if (x.get("identity") or x.get("slug")) == identity
        ]
        if (
            any(
                x.get("running") or (x.get("lease") or {}).get("active")
                for x in matches
            )
            and not confirmed
        ):
            raise ValueError(
                "Peer reports this project running or holding the active ownership lease. Use guided ownership transfer or explicitly acknowledge failover risk."
            )


PROJECT_READ_ONLY_ACTIONS = frozenset({
    "inspect",
    "runtime-health",
    "logs",
})
PROJECT_MUTATING_ACTIONS = frozenset({
    "start",
    "stop",
    "restart",
    "rebuild",
    "backup",
    "bootstrap",
    "health",
    "test",
    "codexpro",
    "quarantine",
    "destroy",
    "restore-vault",
    "restore-backup",
    "analyze-force",
    "reconcile-failed-migration",
})
PROJECT_ACTIONS = PROJECT_READ_ONLY_ACTIONS | PROJECT_MUTATING_ACTIONS


def _canonical_restore_requested(payload: dict[str, Any]) -> bool:
    value = payload.get("canonical", False)
    if type(value) is not bool:
        raise ValueError("Canonical Vault restore flag must be a JSON boolean.")
    return value is True


def _require_owned_project_for_mutation(
    slug: str, *, allow_legacy_migration: bool = False
) -> dict[str, Any]:
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir() or project.is_symlink():
        raise HTTPException(404, "Project not found.")
    try:
        return load_authoritative_project_identity_for_mutation(
            project, allow_legacy_migration=allow_legacy_migration
        )
    except (OSError, ValueError) as exc:
        raise HTTPException(409, str(exc)) from exc


def _project_action_task(slug: str, action: str, payload: dict[str, Any]):
    def task(ctx):
        if action in PROJECT_MUTATING_ACTIONS:
            load_authoritative_project_identity_for_mutation(
                safe_child(SETTINGS.workspaces, slug)
            )

        def progress(value: int, message: str, step: str | None = None) -> None:
            if ctx is not None:
                ctx.update(value, message, step)

        if action == "start":
            progress(10, "Checking ownership and analyzer")
            require_safe_start(slug, bool(payload.get("confirm_failover")))
            progress(35, "Building and starting project services")
            result = start_project(slug, bool(payload.get("confirm_failover")))
        elif action == "stop":
            progress(20, "Stopping project services")
            result = stop_project(slug)
        elif action == "restart":
            progress(20, "Restarting project runtime")
            result = restart_project(slug)
        elif action == "inspect":
            progress(25, "Inspecting project runtime")
            result = inspect_runtime(slug)
        elif action == "runtime-health":
            progress(25, "Checking project runtime health")
            result = runtime_health(slug)
        elif action == "rebuild":
            progress(10, "Checking ownership and analyzer")
            require_safe_start(slug, bool(payload.get("confirm_failover")))
            progress(30, "Rebuilding project images and services")
            result = rebuild_project(slug)
        elif action == "backup":
            progress(15, "Creating append-only encrypted backup")
            result = backup_project(slug)
        elif action == "bootstrap":
            progress(15, "Installing project dependencies")
            result = bootstrap_project(slug)
        elif action == "health":
            progress(25, "Running project health check")
            result = health_project(slug)
        elif action == "test":
            progress(15, "Running project test command")
            result = test_project(slug)
        elif action == "codexpro":
            progress(15, "Checking and bootstrapping CodexPro")
            result = bootstrap_codexpro(slug)
        elif action == "logs":
            progress(20, "Reading bounded project logs")
            result = project_logs(slug)
        elif action == "quarantine":
            progress(10, "Stopping project and verifying backup before quarantine")
            result = quarantine_project(slug)
        elif action == "destroy":
            progress(10, "Creating and verifying backup before permanent destruction")
            result = destroy_project(slug, str(payload.get("confirm_slug") or ""), str(payload.get("confirm_phrase") or ""))
        elif action == "restore-vault":
            canonical = _canonical_restore_requested(payload)
            if canonical and (
                str(payload.get("confirm_slug") or "") != slug
                or str(payload.get("confirm_phrase") or "")
                != f"RESTORE CANONICAL {slug}"
            ):
                raise ValueError("Canonical Vault restore requires exact confirmation.")
            if canonical:
                raise ValueError(
                    "Standalone canonical Vault restore is disabled; use restore-copy or guided ownership transfer."
                )
            progress(10, "Restoring project from encrypted vault")
            result = restore_from_vault(slug, canonical)
        elif action == "restore-backup":
            progress(10, "Verifying backup identity and archive hash")
            result = restore_backup(slug, str(payload.get("backup_id") or ""), confirm_restore=True, allow_overwrite=bool(payload.get("allow_overwrite")))
        elif action == "analyze-force":
            progress(20, "Running complete uncached analyzer scan")
            result = analyze_project(safe_child(SETTINGS.workspaces, slug), force=True)
        elif action == "reconcile-failed-migration":
            progress(10, "Reconciling failed migration ownership")
            result = reconcile_failed_migration(slug, str(payload.get("migration_snapshot") or ""), str(payload.get("confirm_phrase") or ""))
        else:
            raise ValueError("Unknown action.")
        if ctx is not None:
            ctx.log(str(result)[-4000:])
            ctx.update(90, "Operation command completed")
        return result

    return task


def _action_idempotency_key(slug: str, action: str, payload: dict[str, Any], supplied: str = "") -> str:
    supplied = str(supplied or payload.get("idempotency_key") or "").strip()
    if supplied and not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", supplied):
        raise HTTPException(400, "Idempotency key must be 1-128 safe identifier characters.")
    if supplied:
        return f"project-action:{slug}:{action}:{supplied}"
    if action in {"start", "stop", "restart"}:
        return f"project-action:{slug}:{action}"
    if action == "restore-backup" and payload.get("backup_id"):
        return f"project-action:{slug}:{action}:{payload['backup_id']}"
    return ""


def redirect(op_id: str):
    return RedirectResponse("/?operation=" + op_id, 303)


def _form_resource_limits(
    profile: str, cpus: str, ram_gb: str, disk_gb: str, pid_limit: str, pid_mode: str
) -> dict | None:
    # Presets deliberately ignore custom fields: browsers retain hidden inputs and
    # an old custom value must never silently override a selected preset.
    profile = str(profile or "").strip().lower()
    if profile and profile != "custom":
        if profile not in RESOURCE_PROFILES:
            raise HTTPException(400, "Unknown resource profile.")
        return None
    if profile == "custom":
        try:
            return custom_resource_metadata(
                {
                    "cpus": cpus,
                    "memory_gb": ram_gb,
                    "disk_gb": disk_gb,
                    "pids": pid_limit,
                    "pid_mode": pid_mode,
                }
            )
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
    values = {
        "cpus": cpus,
        "memory_gb": ram_gb,
        "disk_gb": disk_gb,
        "pids": pid_limit,
        "pid_mode": pid_mode,
    }
    if (
        not any(str(value or "").strip() for value in (cpus, ram_gb, disk_gb))
        and str(pid_limit or "4096") == "4096"
        and str(pid_mode or "private") == "private"
    ):
        return None
    selected = (
        RESOURCE_PROFILES.get(str(profile or "").lower())
        or RESOURCE_PROFILES["standard"]
    )
    return {
        "cpus": cpus or selected.cpus,
        "memory_gb": ram_gb or selected.memory_gb,
        "disk_gb": disk_gb or selected.disk_gb,
        "pids": pid_limit or selected.pids,
        "pid_mode": pid_mode or "private",
    }


def ui_wants_json(request: Request) -> bool:
    return (
        "application/json" in request.headers.get("accept", "").lower()
        or "x-devfleet-ui" in request.headers
    )


def _preflight(
    slug: str,
    runtime_isolation: str = "",
    resource_profile: str = "",
    custom_cpus: str = "",
    custom_ram_gb: str = "",
    custom_disk_gb: str = "",
    pid_mode: str = "private",
    pid_limit: str = "4096",
) -> dict:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = _require_owned_project_for_mutation(slug, allow_legacy_migration=True)
    inspection = inspect_workspace(project)
    selected = str(
        runtime_isolation or meta.get("runtime_isolation") or "container"
    ).lower()
    blockers = []
    warnings = []
    if selected not in {"container", "vm"}:
        blockers.append("Choose a supported environment type.")
    selected_profile = str(
        resource_profile or meta.get("resource_profile") or "standard"
    ).lower()
    try:
        limits = _form_resource_limits(
            selected_profile,
            custom_cpus,
            custom_ram_gb,
            custom_disk_gb,
            pid_limit,
            pid_mode,
        )
        if limits is None:
            profile = RESOURCE_PROFILES.get(
                selected_profile
            ) or recommend_resource_profile(
                scale=str(meta.get("project_scale") or ""),
                intent=str(meta.get("intent") or ""),
                project_kind=str(meta.get("project_kind") or ""),
                language=str(meta.get("language") or ""),
                framework=str(meta.get("framework") or ""),
            )
            selected_profile = profile.name
            limits = profile.limits(selected)
    except HTTPException as exc:
        limits = {}
        blockers.append(str(exc.detail))
    try:
        capacity_result = get_host_capacity()
        capacity = (
            capacity_result.get("capacity", capacity_result)
            if isinstance(capacity_result, dict)
            else {}
        )
    except Exception as exc:
        capacity = {"status": "unavailable", "error": str(exc)[-500:]}
        blockers.append("Host capacity could not be inspected.")
    capacity_ready = False
    if limits and isinstance(capacity, dict):
        capacity_ready, reason = capacity_allows(capacity, limits)
        if not capacity_ready:
            blockers.append(reason)
    archive_ready = bool(inspection.get("safe_for_archive"))
    if not archive_ready:
        blockers.append("Workspace contains symlinks and cannot be safely archived.")
    compose_ready = (
        selected == "vm"
        or (project / "compose.yaml").is_file()
        or (project / "docker-compose.yml").is_file()
        or (project / "docker-compose.yaml").is_file()
    )
    if not compose_ready:
        blockers.append("Container assignment requires a supported Compose file.")
    worktree_ready = not (selected == "vm" and bool(meta.get("worktree")))
    if not worktree_ready:
        blockers.append("Linked Git worktrees cannot be assigned to a dedicated VM.")
    command_readiness = project_command_readiness(project)
    lifecycle_commands_ready = selected != "vm" or bool(command_readiness.get("ready"))
    if not lifecycle_commands_ready:
        missing = ", ".join(command_readiness.get("missing_required") or [])
        invalid = ", ".join((command_readiness.get("invalid_required") or {}).keys())
        detail = "; ".join(
            part
            for part in (
                f"missing {missing}" if missing else "",
                f"unsafe or unsupported {invalid}" if invalid else "",
            )
            if part
        )
        blockers.append(
            "Dedicated VM lifecycle commands are not ready"
            + (f": {detail}" if detail else ".")
        )
    inspection_ok = True
    migration_ready = (
        inspection_ok
        and archive_ready
        and compose_ready
        and worktree_ready
        and lifecycle_commands_ready
        and capacity_ready
        and not blockers
    )
    return {
        "ok": migration_ready,
        "read_only": True,
        "project_id": meta.get("project_id"),
        "slug": slug,
        "workspace": inspection,
        "current_runtime": detect_runtime(slug),
        "selected_environment": selected,
        "selected_resource_profile": selected_profile,
        "selected_limits": limits,
        "capacity": capacity,
        "inspection_ok": inspection_ok,
        "migration_ready": migration_ready,
        "capacity_ready": capacity_ready,
        "archive_ready": archive_ready,
        "compose_ready": compose_ready,
        "worktree_ready": worktree_ready,
        "lifecycle_commands_ready": lifecycle_commands_ready,
        "lifecycle_commands": command_readiness,
        "blockers": blockers,
        "warnings": warnings,
        "target_vm_name": (
            f"devfleet-project-{slug}"
            if len(f"devfleet-project-{slug}") <= 60
            else "deterministic-name-hashed-by-host-agent"
        ),
        "migration_would_be_performed": False,
    }


def operation_or_404(op_id: str) -> dict:
    try:
        return get_operation(op_id)
    except (FileNotFoundError, ValueError):
        raise HTTPException(404, "Operation not found.")


@app.get("/healthz")
def healthz():
    return {"ok": True, "service": "devfleet", "agent_version": __version__}


@app.get("/login", response_class=HTMLResponse)
def login_page(request: Request, next: str = "/"):
    token = login_csrf_token()
    response = templates.TemplateResponse(
        request,
        "login.html",
        {
            "csrf_token": token,
            "next": safe_next(next),
            "version": __version__,
            "error": "",
        },
    )
    response.set_cookie(
        LOGIN_CSRF_COOKIE,
        token,
        max_age=600,
        httponly=True,
        samesite="strict",
        secure=request.url.scheme == "https",
        path="/",
    )
    return response


@app.post("/login", response_class=HTMLResponse)
def login_submit(
    request: Request,
    username: str = Form(""),
    password: str = Form(""),
    next: str = Form("/"),
    keep_signed_in: bool = Form(False),
    csrf_token: str = Form(""),
):
    target = safe_next(next)
    source = request.client.host if request.client else None

    def rejected(
        status_code: int = 401,
        error: str = "The username, password, or sign-in form token was not accepted.",
    ):
        token = request.cookies.get(LOGIN_CSRF_COOKIE) or login_csrf_token()
        response = templates.TemplateResponse(
            request,
            "login.html",
            {
                "csrf_token": token,
                "next": target,
                "version": __version__,
                "error": error,
            },
            status_code=status_code,
        )
        response.set_cookie(
            LOGIN_CSRF_COOKIE,
            token,
            max_age=600,
            httponly=True,
            samesite="strict",
            secure=request.url.scheme == "https",
            path="/",
        )
        return response

    if not validate_login_csrf(request.cookies.get(LOGIN_CSRF_COOKIE), csrf_token):
        return rejected()
    if not valid_credentials(username, password, source=source):
        retry_after = login_retry_after(username, source)
        if retry_after:
            response = rejected(429, "Too many sign-in attempts. Try again shortly.")
            response.headers["Retry-After"] = str(retry_after)
            return response
        return rejected()
    token, ttl, _csrf = issue_session(username, keep_signed_in)
    response = RedirectResponse(target, 303)
    response.set_cookie(
        SESSION_COOKIE, token, max_age=ttl, **session_cookie_options(request)
    )
    response.delete_cookie(LOGIN_CSRF_COOKIE, path="/")
    return response


@app.post("/logout")
def logout(request: Request, csrf_token: str = Form("")):
    ui(request, csrf_token)
    revoke_session(request.cookies.get(SESSION_COOKIE))
    response = RedirectResponse("/login?logged_out=1", 303)
    response.delete_cookie(SESSION_COOKIE, path="/")
    return response


@app.get("/api/status", dependencies=[Depends(check_api)])
def api_status(refresh: bool = False):
    return local_status(live=refresh)


@app.get("/api/node/status", dependencies=[Depends(check_api)])
def api_node_status():
    return runtime_status()


@app.get("/api/host/status", dependencies=[Depends(check_api)])
def api_host_status():
    return host_control_status()


@app.get("/api/host/capacity", dependencies=[Depends(check_api)])
def api_host_capacity():
    try:
        return get_host_capacity()
    except Exception as exc:
        return {"ok": False, "status": "unavailable", "error": str(exc)[-500:]}


@app.get("/api/provider/status", dependencies=[Depends(check_api)])
def api_provider_status():
    try:
        return get_provider_status()
    except Exception as exc:
        return {"ok": False, "status": "unavailable", "error": str(exc)[-500:]}


@app.get("/api/cluster/status", dependencies=[Depends(check_api)])
def api_cluster_status():
    return cluster_status()


@app.get("/api/containers", dependencies=[Depends(check_api)])
def api_containers():
    return {"containers": list_containers()}


@app.get("/api/containers/{container_ref}/inspect", dependencies=[Depends(check_api)])
def api_container_inspect(container_ref: str):
    try:
        return inspect_container(container_ref)
    except ValueError as exc:
        raise HTTPException(403, "Container is not an authorized DevFleet-owned resource.") from exc


@app.get("/api/containers/{container_ref}/logs", dependencies=[Depends(check_api)])
def api_container_logs(container_ref: str, tail: int = 200):
    try:
        return {"logs": container_logs(container_ref, tail)}
    except ValueError as exc:
        raise HTTPException(403, "Container is not an authorized DevFleet-owned resource.") from exc


@app.post("/api/containers/{container_ref}/{action}", dependencies=[Depends(check_api)])
def api_container_action(container_ref: str, action: str, payload: dict | None = None):
    payload = payload or {}
    if action == "remove" and not payload.get("confirm_remove"):
        raise HTTPException(400, "Removing a container requires explicit confirmation.")
    try:
        return {"ok": True, "output": container_action(container_ref, action)}
    except ValueError as exc:
        raise HTTPException(403, "Container is not an authorized DevFleet-owned resource.") from exc


@app.get("/cluster/status")
def cluster_status_ui(request: Request, refresh: bool = False):
    ui(request)
    return JSONResponse(cluster_status() if refresh else cluster_snapshot())


@app.get("/containers/{container_ref}/inspect")
def container_inspect_ui(request: Request, container_ref: str):
    ui(request)
    try:
        return JSONResponse(inspect_container(container_ref))
    except ValueError as exc:
        raise HTTPException(403, "Container is not an authorized DevFleet-owned resource.") from exc


@app.get("/containers/{container_ref}/logs")
def container_logs_ui(request: Request, container_ref: str, tail: int = 200):
    ui(request)
    try:
        return JSONResponse({"logs": container_logs(container_ref, tail)})
    except ValueError as exc:
        raise HTTPException(403, "Container is not an authorized DevFleet-owned resource.") from exc


@app.get("/peer/containers/{container_ref}/inspect")
def peer_container_inspect_ui(request: Request, container_ref: str):
    ui(request)
    return JSONResponse(
        peer_call(
            "GET", f"/api/containers/{validate_container_ref(container_ref)}/inspect"
        )
    )


@app.get("/peer/containers/{container_ref}/logs")
def peer_container_logs_ui(request: Request, container_ref: str, tail: int = 200):
    ui(request)
    return JSONResponse(
        peer_call(
            "GET",
            f"/api/containers/{validate_container_ref(container_ref)}/logs?tail={max(1,min(int(tail),1000))}",
        )
    )


@app.post("/containers/{container_ref}/{action}")
def container_action_ui(
    request: Request,
    container_ref: str,
    action: str,
    confirm_remove: bool = Form(False),
    csrf_token: str = Form(""),
):
    ui(request, csrf_token)
    if action == "remove" and not confirm_remove:
        raise HTTPException(400, "Removing a container requires explicit confirmation.")
    try:
        return JSONResponse({"ok": True, "output": container_action(container_ref, action)})
    except ValueError as exc:
        raise HTTPException(403, "Container is not an authorized DevFleet-owned resource.") from exc


@app.post("/peer/containers/{container_ref}/{action}")
def peer_container_action_ui(
    request: Request,
    container_ref: str,
    action: str,
    confirm_remove: bool = Form(False),
    csrf_token: str = Form(""),
):
    ui(request, csrf_token)
    if action == "remove" and not confirm_remove:
        raise HTTPException(400, "Removing a container requires explicit confirmation.")
    return JSONResponse(
        {
            "ok": True,
            "output": peer_call(
                "POST",
                f"/api/containers/{validate_container_ref(container_ref)}/{action}",
                {"confirm_remove": bool(confirm_remove)},
            ),
        }
    )


@app.get("/api/operations", dependencies=[Depends(check_api)])
def api_operations():
    return {"operations": list_operations()}


@app.get("/api/operations/{op_id}", dependencies=[Depends(check_api)])
def api_operation(op_id: str):
    return operation_or_404(op_id)


@app.get("/operations/{op_id}")
def operation_ui(request: Request, op_id: str):
    ui(request)
    return operation_or_404(op_id)


@app.get("/ui/operations/{op_id}")
def ui_operation(request: Request, op_id: str):
    ui(request)
    return JSONResponse(operation_or_404(op_id))


@app.get("/", response_class=HTMLResponse)
def index(
    request: Request, operation: str = "", view: str = "overview", project: str = ""
):
    ui(request)
    op = None
    if operation:
        try:
            op = get_operation(operation)
        except Exception:
            pass
    status = local_status()
    cluster = cluster_snapshot()
    peer_node = next(
        (
            node
            for node in cluster.get("nodes", [])
            if node.get("id") == "devfleet-failover"
        ),
        {},
    )
    peer = {
        "configured": bool(peer_node),
        "ok": bool(peer_node.get("reachable")),
        "peer": peer_node,
        "status": peer_node.get("status", "unavailable"),
        "error": peer_node.get("error", ""),
    }
    allowed_views = {
        "overview",
        "projects",
        "project",
        "infrastructure",
        "activity",
        "settings",
    }
    selected_view = view if view in allowed_views else "overview"
    selected_project = next(
        (item for item in status.get("projects", []) if item.get("slug") == project),
        None,
    )
    if selected_view == "project" and selected_project is None:
        raise HTTPException(404, "Project not found.")
    return templates.TemplateResponse(
        request,
        "index.html",
        {
            "status": status,
            "version": __version__,
            "peer": peer,
            "cluster": cluster,
            "quarantine": list_quarantine() if SETTINGS.quarantine.exists() else [],
            "templates_catalog": TEMPLATES,
            "operation": op,
            "csrf_token": ui_csrf_token(request),
            "view": selected_view,
            "selected_project": selected_project,
            "resource_profiles": RESOURCE_PROFILES,
            "runtime_isolations": RUNTIME_ISOLATIONS,
        },
    )


@app.get("/api/templates/recommend", dependencies=[Depends(check_api)])
def api_recommend(
    language: str = "",
    framework: str = "",
    scale: str = "",
    intent: str = "",
    project_kind: str = "",
):
    return {
        "template": recommend_template(language, framework, scale, intent, project_kind)
    }


@app.get("/api/runtime/recommend", dependencies=[Depends(check_api)])
def api_runtime_recommend(
    language: str = "",
    framework: str = "",
    scale: str = "",
    intent: str = "",
    project_kind: str = "",
):
    resource = recommend_resource_profile(
        scale=scale,
        intent=intent,
        proj