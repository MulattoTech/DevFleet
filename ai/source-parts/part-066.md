# DevFleet source part 066

Full-source UTF-8 byte interval [3022500, 3069000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 590ba53d523a18d03dbfccc8dd90a286f47ac7abcb4c54722ed41191feaa59ef

<!-- BEGIN SOURCE SLICE -->
project or crosses a symlink.", rel))


def _port_state(port: Any) -> tuple[str, str]:
    if isinstance(port, dict):
        host = str(port.get("host_ip", ""))
        text = json.dumps(port, sort_keys=True)
    else:
        text = str(port)
        parts = text.rsplit(":", 2)
        host = parts[0] if len(parts) >= 3 else ""
    if host in {"127.0.0.1", "::1", "[::1]"}:
        return "loopback", text
    if host.startswith("100."):
        try:
            n = int(host.split(".")[1])
            return ("tailnet" if 64 <= n <= 127 else "public"), text
        except Exception:
            pass
    return "public", text


def _scan(project: Path, profile: str) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    references: set[Path] = set()
    found = False
    for relative in COMPOSE_FILES:
        path = project / relative
        if not path.exists():
            continue
        found = True
        if path.is_symlink():
            out.append(finding("critical", "project.symlink-config", "Container configuration may not be a symbolic link.", relative))
            continue
        document = _preflight_compose(project, path, out, references, set(), {"bytes": 0}, 0)
        if document:
            services = document.get("services") or {}
            if isinstance(services, dict):
                for name, service in services.items():
                    if isinstance(service, dict):
                        _scan_compose_service(project, path, str(name), service, profile, out)
    dc = project / ".devcontainer/devcontainer.json"
    if dc.exists():
        found = True
        _scan_devcontainer(project, profile, out, references)
    if not found:
        out.append(finding("warning", "project.no-container-config", "No supported Compose or Dev Container configuration found."))
    for pth in project.rglob("*"):
        if pth.is_symlink():
            try:
                pth.resolve().relative_to(project.resolve())
            except ValueError:
                out.append(finding("critical", "project.symlink-escape", "Symbolic link resolves outside the project.", str(pth.relative_to(project))))
    return sorted(out, key=lambda x: {"critical": 0, "error": 1, "warning": 2, "info": 3}.get(x["severity"], 9))


def _fingerprint(project: Path, profile: str) -> str:
    h = hashlib.sha256()
    for value in (ANALYZER_POLICY_VERSION, COMPOSE_SUPPORTED_SCHEMA, DEVCONTAINER_SUPPORTED_SCHEMA, profile):
        h.update(value.encode("utf-8"))
        h.update(b"\0")
    try:
        files = sorted(project.rglob("*"), key=lambda item: str(item.relative_to(project)))
    except OSError:
        files = []
    for path in files:
        try:
            relative = path.relative_to(project)
            if relative.as_posix() == ".devfleet/runtime/analyzer-cache.json" or not path.is_file():
                continue
            h.update(str(relative).encode("utf-8"))
            h.update(b"\0")
            if path.is_symlink():
                h.update(b"symlink:")
                h.update(str(path.resolve(strict=False)).encode("utf-8"))
            else:
                h.update(b"file:")
                h.update(hashlib.sha256(path.read_bytes()).digest())
            h.update(b"\0")
        except (OSError, ValueError):
            h.update(f"unreadable:{path}".encode("utf-8"))
    return h.hexdigest()


def analyze_project(project: Path, profile: str | None = None, force: bool = False) -> list[dict[str, str]]:
    profile = (profile or SETTINGS.development_profile).lower()
    fp = _fingerprint(project, profile)
    cache = project / ".devfleet/runtime/analyzer-cache.json"
    if SETTINGS.enable_analyzer_cache and not force:
        try:
            data = json.loads(cache.read_text(encoding="utf-8"))
            if data.get("fingerprint") == fp and data.get("policyVersion") == ANALYZER_POLICY_VERSION:
                return data.get("findings", [])
        except Exception:
            pass
    findings = _scan(project, profile)
    if SETTINGS.enable_analyzer_cache:
        atomic_json(cache, {"fingerprint": fp, "policyVersion": ANALYZER_POLICY_VERSION, "findings": findings})
    return findings


def has_blockers(findings: list[dict[str, str]]) -> bool:
    return any(x["severity"] in {"critical", "error"} for x in findings)

```


## FILE: source/app/devfleet/auth.py

SHA256: 9810905e7e2ab9d1f1a426ffb9644e2c388de5d199aedf9848f953918ff7cb3d | Bytes: 13026 | Git mode: 100644

```
from __future__ import annotations
import hashlib, hmac, json, secrets, time, threading, math, os, tempfile
from contextlib import contextmanager
from pathlib import Path
from fastapi import Header, HTTPException, Request, status
from .core import SETTINGS, atomic_json

SESSION_COOKIE = "devfleet_session"
LOGIN_CSRF_COOKIE = "devfleet_login_csrf"
SESSION_TTL = 12 * 60 * 60
REMEMBERED_TTL = 7 * 24 * 60 * 60
SESSION_SAMESITE = "strict"
SESSION_SECURE_COOKIE = True
_SESSION_LOCK = threading.RLock()
_LOGIN_LOCK = threading.RLock()
_LOGIN_FAILURES = {}
_SOURCE_FAILURES = {}
_CREDENTIAL_FAILURES = {}
_GLOBAL_FAILURES = []
_BACKOFF_BASE = 0.25
_BACKOFF_MAX = 8.0
_SOURCE_WINDOW = 15 * 60
_GLOBAL_WINDOW = 60.0
_GLOBAL_LIMIT = 40


def _session_path() -> Path:
    return SETTINGS.runtime_root / "sessions.json"


@contextmanager
def _session_file_lock():
    """Serialize the complete sessions read/modify/write transaction across workers."""
    path = _session_path().with_name("sessions.json.lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = open(path, "a+b")
    try:
        if os.name != "nt":
            os.chmod(path, 0o600)
    except OSError:
        pass
    try:
        if os.name != "nt":
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        else:
            import msvcrt

            handle.seek(0, os.SEEK_END)
            if handle.tell() == 0:
                handle.write(b"0")
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
        yield
    finally:
        try:
            if os.name != "nt":
                import fcntl

                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
            else:
                import msvcrt

                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        finally:
            handle.close()
    try:
        if os.name != "nt":
            path.chmod(0o600)
    except OSError:
        pass


def _load_sessions() -> dict[str, dict]:
    try:
        value = json.loads(_session_path().read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _save_sessions(value: dict[str, dict]) -> None:
    path = _session_path()
    parent = path.parent
    parent.mkdir(parents=True, exist_ok=True)
    if os.name != "nt":
        try:
            parent.chmod(0o700)
        except OSError:
            pass
    payload = json.dumps(value, indent=2, sort_keys=True, default=str) + "\n"
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(parent)
    )
    try:
        if hasattr(os, "fchmod"):
            os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            fd = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        replace_error = None
        for attempt in range(6):
            try:
                os.replace(temp_name, path)
                replace_error = None
                break
            except PermissionError as exc:
                replace_error = exc
                if os.name != "nt" or attempt == 5:
                    raise
                time.sleep(0.02 * (attempt + 1))
        if replace_error is not None:
            raise replace_error
    finally:
        if fd != -1:
            os.close(fd)
        try:
            Path(temp_name).unlink(missing_ok=True)
        except OSError:
            pass
    if os.name != "nt":
        try:
            path.chmod(0o600)
        except OSError:
            pass


def _credential_generation() -> str:
    return hashlib.sha256(
        (str(SETTINGS.admin_user) + "\0" + str(SETTINGS.admin_password)).encode()
    ).hexdigest()


def _prune_sessions(
    sessions: dict[str, dict], now: int | None = None
) -> dict[str, dict]:
    now = int(time.time() if now is None else now)
    return {
        k: v
        for k, v in sessions.items()
        if isinstance(v, dict) and int(v.get("expires_at", 0)) > now
    }


def login_csrf_token() -> str:
    return secrets.token_urlsafe(32)


def session_cookie_options(request: Request | None = None) -> dict:
    """Cookie settings for callers that emit the session cookie.

    v1.2.1's route signatures remain unchanged; this centralizes the strict,
    secure-compatible policy for future/compatible emitters.
    """
    return {
        "httponly": True,
        "samesite": SESSION_SAMESITE,
        "secure": bool(request and request.url.scheme == "https"),
        "path": "/",
    }


def safe_next(value: str | None) -> str:
    value = str(value or "/").strip()
    if (
        not value.startswith("/")
        or value.startswith("//")
        or "\\" in value
        or "://" in value
    ):
        return "/"
    return value


def _backoff_key(user: str, source: str | None = None) -> str:
    return f'{source or "unknown"}:{user}'


def _source_key(source: str | None) -> str:
    return str(source or "unknown").strip().lower()[:200]


def _credential_key(user: str) -> str:
    return hashlib.sha256(str(user or "").strip().lower().encode()).hexdigest()


def _backoff_seconds(entries: dict[str, dict], key: str, now: float) -> float:
    entry = entries.get(key)
    return max(0.0, float(entry["until"]) - now) if entry else 0.0


def login_backoff_seconds(
    user: str, source: str | None = None, now: float | None = None
) -> float:
    now = time.monotonic() if now is None else now
    key = _backoff_key(user, source)
    with _LOGIN_LOCK:
        entry = _LOGIN_FAILURES.get(key)
        return max(0.0, float(entry["until"]) - now) if entry else 0.0


def _record_login_failure(
    user: str, source: str | None = None, now: float | None = None
) -> None:
    now = time.monotonic() if now is None else now
    key = _backoff_key(user, source)
    with _LOGIN_LOCK:
        cutoff = now - _SOURCE_WINDOW
        _LOGIN_FAILURES.update(
            {k: v for k, v in _LOGIN_FAILURES.items() if v["last"] >= cutoff}
        )
        entry = _LOGIN_FAILURES.get(key, {"count": 0, "last": now, "until": now})
        count = min(int(entry["count"]) + 1, 8)
        entry = {
            "count": count,
            "last": now,
            "until": now + min(_BACKOFF_MAX, _BACKOFF_BASE * (2 ** (count - 1))),
        }
        _LOGIN_FAILURES[key] = entry
        for entries, entry_key in (
            (_SOURCE_FAILURES, _source_key(source)),
            (_CREDENTIAL_FAILURES, _credential_key(user)),
        ):
            old = entries.get(entry_key, {"count": 0, "last": now, "until": now})
            n = min(int(old["count"]) + 1, 8)
            entries[entry_key] = {
                "count": n,
                "last": now,
                "until": now + min(_BACKOFF_MAX, _BACKOFF_BASE * (2 ** (n - 1))),
            }
        _GLOBAL_FAILURES[:] = [t for t in _GLOBAL_FAILURES if t >= now - _GLOBAL_WINDOW]
        if len(_GLOBAL_FAILURES) < _GLOBAL_LIMIT:
            _GLOBAL_FAILURES.append(now)


def login_retry_after(
    user: str, source: str | None = None, now: float | None = None
) -> int:
    now = time.monotonic() if now is None else now
    with _LOGIN_LOCK:
        source_delay = _backoff_seconds(_SOURCE_FAILURES, _source_key(source), now)
        credential_delay = _backoff_seconds(
            _CREDENTIAL_FAILURES, _credential_key(user), now
        )
        global_delay = 0.0
        if len(_GLOBAL_FAILURES) >= _GLOBAL_LIMIT:
            global_delay = max(0.0, (_GLOBAL_FAILURES[0] + _GLOBAL_WINDOW) - now)
    return max(0, math.ceil(max(source_delay, credential_delay, global_delay)))


def valid_credentials(user: str, password: str, source: str | None = None) -> bool:
    user = str(user or "")
    password = str(password or "")
    # Keep both comparisons on every credential attempt.  Input-shape
    # rejection is applied only after the comparisons so an invalid username
    # cannot skip the password comparison.
    user_ok = hmac.compare_digest(user, SETTINGS.admin_user)
    password_ok = hmac.compare_digest(password, SETTINGS.admin_password)
    valid = bool(user.strip() and password and (user_ok & password_ok))
    if not user.strip() or not password:
        _record_login_failure(user, source)
        return False
    if not valid:
        if login_retry_after(user, source):
            return False
        _record_login_failure(user, source)
    else:
        # A correct credential must not be permanently locked out by earlier
        # failures for the same account; throttle invalid attempts while allowing
        # the owner to recover without waiting for the backoff window.
        with _LOGIN_LOCK:
            _LOGIN_FAILURES.pop(_backoff_key(user, source), None)
            _CREDENTIAL_FAILURES.pop(_credential_key(user), None)
            _SOURCE_FAILURES.pop(_source_key(source), None)
    return valid


def issue_session(user: str, remember: bool = False) -> tuple[str, int, str]:
    now = int(time.time())
    ttl = REMEMBERED_TTL if remember else SESSION_TTL
    session_id = secrets.token_urlsafe(32)
    csrf = secrets.token_urlsafe(32)
    with _SESSION_LOCK, _session_file_lock():
        sessions = _prune_sessions(_load_sessions())
        sessions[session_id] = {
            "user": user,
            "issued_at": now,
            "expires_at": now + ttl,
            "csrf": csrf,
            "credential_generation": _credential_generation(),
        }
        _save_sessions(sessions)
    return session_id, ttl, csrf


def _session_file_generation() -> tuple[int, int]:
    try:
        stat = _session_path().stat()
        return (int(stat.st_mtime_ns), int(stat.st_size))
    except OSError:
        return (0, 0)


def _request_session_record(request: Request) -> dict | None:
    token = request.cookies.get(SESSION_COOKIE)
    signature = (token, _credential_generation(), _session_file_generation())
    state = getattr(request, "state", None)
    cached = (
        getattr(state, "devfleet_session_cache", None) if state is not None else None
    )
    if isinstance(cached, dict) and cached.get("signature") == signature:
        return cached.get("record")
    with _SESSION_LOCK, _session_file_lock():
        record = _prune_sessions(_load_sessions()).get(token or "")
    if (
        not isinstance(record, dict)
        or record.get("user") != SETTINGS.admin_user
        or record.get("credential_generation") != signature[1]
        or int(record.get("expires_at", 0)) <= int(time.time())
    ):
        record = None
    if state is not None:
        state.devfleet_session_cache = {"signature": signature, "record": record}
    return record


def validate_session(token: str | None) -> str | None:
    if not token:
        return None
    with _SESSION_LOCK, _session_file_lock():
        record = _prune_sessions(_load_sessions()).get(token)
    if (
        not isinstance(record, dict)
        or record.get("user") != SETTINGS.admin_user
        or record.get("credential_generation") != _credential_generation()
    ):
        return None
    if int(record.get("expires_at", 0)) <= int(time.time()):
        revoke_session(token)
        return None
    return str(record["user"])


def session_user(request: Request) -> str | None:
    record = _request_session_record(request)
    return str(record["user"]) if isinstance(record, dict) else None


def check_session(request: Request) -> None:
    if not session_user(request):
        raise HTTPException(status_code=401, detail="Login required.")


def session_csrf_token(request: Request) -> str:
    record = _request_session_record(request)
    return str(record.get("csrf", "")) if isinstance(record, dict) else ""


def validate_login_csrf(cookie: str | None, form_value: str) -> bool:
    return bool(cookie and form_value) and hmac.compare_digest(cookie, form_value)


def validate_session_csrf(request: Request, form_value: str) -> bool:
    return bool(form_value) and hmac.compare_digest(
        session_csrf_token(request), form_value
    )


def revoke_session(token: str | None) -> None:
    if not token:
        return
    with _SESSION_LOCK, _session_file_lock():
        sessions = _load_sessions()
        sessions.pop(token, None)
        _save_sessions(sessions)


def api_token_valid(token: str | None) -> bool:
    """Validate the API token without short-circuiting the digest comparison."""
    expected = str(SETTINGS.api_token or "")
    supplied = str(token or "")
    configured = bool(expected.strip())
    provided = bool(supplied.strip())
    matches = hmac.compare_digest(supplied, expected)
    return configured and provided and matches


def check_api(x_devfleet_token: str = Header(default="")) -> None:
    if not api_token_valid(x_devfleet_token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API token"
        )

```


## FILE: source/app/devfleet/caches.py

SHA256: 9772d26aae5fa5d81142a9e1e29361886b9effbaa92f3eef8a99724bd985441d | Bytes: 1733 | Git mode: 100644

```
from __future__ import annotations
from pathlib import Path
from typing import Any
import yaml
from .core import SETTINGS
MOUNTS={'python':[('pip','/home/vscode/.cache/pip'),('uv','/home/vscode/.cache/uv')],'javascript':[('npm','/home/node/.npm'),('pnpm','/home/node/.local/share/pnpm/store')],'typescript':[('npm','/home/node/.npm'),('pnpm','/home/node/.local/share/pnpm/store')],'java':[('maven','/home/vscode/.m2/repository'),('gradle','/home/vscode/.gradle/caches')],'kotlin':[('maven','/home/vscode/.m2/repository'),('gradle','/home/vscode/.gradle/caches')],'csharp':[('nuget','/home/vscode/.nuget/packages')],'go':[('go-mod','/go/pkg/mod'),('go-build','/home/vscode/.cache/go-build')],'rust':[('cargo-registry','/usr/local/cargo/registry'),('cargo-git','/usr/local/cargo/git')],'php':[('composer','/home/vscode/.cache/composer')],'ruby':[('bundler','/usr/local/bundle/cache')]}
def cache_override(project:Path,compose_file:Path,meta:dict[str,Any])->Path|None:
 if not SETTINGS.enable_shared_caches or meta.get('profile',SETTINGS.development_profile)=='strict':return None
 mounts=MOUNTS.get(str(meta.get('language','')).lower(),[])
 if not mounts:return None
 data=yaml.safe_load(compose_file.read_text()) or {};services=data.get('services') or {};override={'services':{}}
 for service in services:
  volumes=[]
  for name,target in mounts:
   source=SETTINGS.cache_root/name;source.mkdir(parents=True,exist_ok=True);volumes.append({'type':'bind','source':str(source),'target':target})
  override['services'][service]={'volumes':volumes}
 out=SETTINGS.runtime_root/'compose-overrides'/f'{project.name}.cache.yaml';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(yaml.safe_dump(override,sort_keys=False));return out

```


## FILE: source/app/devfleet/codexpro.py

SHA256: 30b25cb2a5e7479b08aeb3e1b161fe5b53d6eafe21f6b53ea6d2b827df5689a4 | Bytes: 867 | Git mode: 100644

```
from __future__ import annotations
import json,time
from pathlib import Path
from typing import Any
from .core import SETTINGS
def codexpro_status(project:Path)->dict[str,Any]:
 runtime=project/'.ai-bridge/local-agent';status=project/'.devfleet/runtime/codexpro-status.json';log=project/'.devfleet/runtime/codexpro-bootstrap.log';handoff=project/'.ai-bridge/current-plan.md'
 data={'healthy':False,'state':'not-bootstrapped','workspace':str(project),'runtime_log':str(log),'model_endpoint':SETTINGS.ollama_base_url,'handoff_age_seconds':None}
 try:data.update(json.loads(status.read_text()))
 except Exception:pass
 if handoff.exists():data['handoff_age_seconds']=max(0,int(time.time()-handoff.stat().st_mtime))
 data['runtime_directory']=str(runtime);return data
def bootstrap_command(project:Path)->list[str]:return [str(project/'.devfleet/codexpro-bootstrap.sh')]

```


## FILE: source/app/devfleet/configuration.py

SHA256: 3ad7879d81b09b62d176c5483204281caf4d7f81a57d03d6fd77cf9a7f4c1ee1 | Bytes: 4081 | Git mode: 100644

```
from __future__ import annotations
from copy import deepcopy
from typing import Any
SCHEMA_VERSION=2
PROFILE_NAMES={'strict','balanced','fast'}
DOCKER_MODES={'rootless','rootful'}

def _setdefault_path(data:dict[str,Any],path:tuple[str,...],value:Any)->None:
    cur=data
    for key in path[:-1]:cur=cur.setdefault(key,{})
    cur.setdefault(path[-1],value)

def migrate_cluster_config(source:dict[str,Any],*,clean_install:bool=False)->tuple[dict[str,Any],list[str]]:
    data=deepcopy(source); version=int(data.get('SchemaVersion',1)); changes=[]
    if version>2: raise ValueError(f'Configuration schema {version} is newer than this package supports.')
    if version==1:
        profile='balanced' if clean_install else 'strict'
        _setdefault_path(data,('Hosts',),{'DesktopFriendlyName':'DevFleet Primary','LaptopFriendlyName':'DevFleet Surrogate'})
        for key,friendly,alias in [('Primary','CodexDevVM','CodexDevVM'),('Failover','DevFleetFailover','DevFleetFailover'),('Vault','DevFleetVault','DevFleetVault')]:
            node=data.setdefault(key,{}); node.setdefault('FriendlyName',friendly); node.setdefault('SshAlias',alias)
        data.setdefault('Development',{'Profile':profile,'EnableSharedBuildCaches':profile!='strict','EnableAnalyzerCache':True,'EnableTrustedOrchestrator':True,'AllowLoopbackPortPublishing':True,'AllowTailnetPortPublishing':profile!='strict','AutoStartCodexPro':True,'AutoStartProjectServices':True,'RequireConfirmationForRoutineRebuild':False,'RequireConfirmationForRoutineRepair':False,'BackupBeforeRebuild':False,'BackupBeforeQuarantine':True})
        data.setdefault('Docker',{'PrimaryMode':'rootless','FailoverMode':'rootless','EnableBuildKit':True,'EnableSharedBuildCache':profile!='strict','EnableRegistryCache':False,'RootfulModeAcknowledged':False})
        data.setdefault('CodexPro',{'Mode':'project-scoped-adapter','AutoBootstrap':True,'ToolCards':True,'DefaultHost':'127.0.0.1','DefaultPort':8787,'SharedTransportStatus':'adapter-only-until-a-verified-multi-workspace-registration-interface-is-exposed'})
        ollama=data.setdefault('Ollama',{}); ollama.setdefault('PreferredBaseUrl',''); ollama.setdefault('Profile','stable-interactive'); ollama.setdefault('ProfilesFile','config/ollama-profiles.json')
        network=data.setdefault('Network',{}); network.setdefault('TailnetCidr','100.64.0.0/10'); network.setdefault('PublicBindingAllowed',False)
        backup=data.setdefault('Backup',{}); backup.setdefault('RequireVerifiedBackupBeforeQuarantine',True); backup.setdefault('OfflineExportEnabled',True)
        safety=data.setdefault('Safety',{}); safety.setdefault('BlockWindowsPaths',True); safety.setdefault('BlockUncPaths',True); safety.setdefault('BlockWorkspaceEscape',True); safety.setdefault('OrdinaryContainersMayMountDockerSocket',False)
        data.setdefault('LanguagePolicy',{'DefaultAutomation':'python','DefaultWindowsAdministration':'powershell','DefaultLinuxAdministration':'bash-or-python','DefaultCrossPlatformCli':'go','DefaultWebFrontend':'typescript','DefaultRapidApi':'python-fastapi'})
        data['SchemaVersion']=2
        changes += ['SchemaVersion: 1 -> 2',f'Development.Profile: {profile}','Existing rootless Docker stores preserved; no implicit image/volume migration','Primary friendly name and SSH alias: CodexDevVM; instance remains devfleet-primary']
    data['PackageVersion']=__import__('devfleet.version',fromlist=['__version__']).__version__
    return data,changes

def validate_cluster_config(data:dict[str,Any])->None:
    if int(data.get('SchemaVersion',0))!=2: raise ValueError('SchemaVersion must be 2 after migration.')
    if str(data.get('Development',{}).get('Profile','')).lower() not in PROFILE_NAMES: raise ValueError('Unknown development profile.')
    for key in ('PrimaryMode','FailoverMode'):
        if str(data.get('Docker',{}).get(key,'')).lower() not in DOCKER_MODES: raise ValueError(f'Docker.{key} must be rootless or rootful.')
    if data.get('Safety',{}).get('AllowDockerTcp'): raise ValueError('Unauthenticated Docker TCP remains unsupported.')

```


## FILE: source/app/devfleet/containers.py

SHA256: 56dc9aa80609796d45523c4d701e05afde736cccbc9a925fab4f8d50304dc600 | Bytes: 11180 | Git mode: 100644

```
from __future__ import annotations

import json
import re
from typing import Any

from .core import SETTINGS, run, safe_child, validate_project_id, validate_slug
from .metadata_io import read_project_metadata


_CONTAINER_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
_ACTIONS = {
    "start": "start",
    "stop": "stop",
    "restart": "restart",
    "pause": "pause",
    "unpause": "unpause",
    "remove": "rm",
}
_IMMUTABLE_CONTAINER_ID = re.compile(r"^[0-9a-fA-F]{64}$")
OWNERSHIP_LABELS = {
    "managed_by": "io.devfleet.managed-by",
    "project_id": "io.devfleet.project-id",
    "slug": "io.devfleet.project-slug",
    "runtime_id": "io.devfleet.runtime-id",
    "deployment_id": "io.devfleet.deployment-id",
    "host_id": "io.devfleet.host-id",
}


def container_ownership_labels(metadata: dict[str, Any]) -> dict[str, str]:
    values = {
        "managed_by": str(metadata.get("managed_by") or "").strip().lower(),
        "project_id": str(metadata.get("project_id") or "").strip(),
        "slug": str(metadata.get("slug") or "").strip(),
        "runtime_id": str(metadata.get("runtime_id") or "").strip(),
        "deployment_id": str(metadata.get("deployment_id") or "").strip(),
        "host_id": str(metadata.get("host_id") or "").strip(),
    }
    if values["managed_by"] != "devfleet":
        raise ValueError("Container ownership binding is missing the DevFleet manager identity.")
    validate_project_id(values["project_id"])
    validate_slug(values["slug"])
    if any(not values[key] for key in ("runtime_id", "deployment_id", "host_id")):
        raise ValueError("Container ownership binding is incomplete.")
    return {label: values[field] for field, label in OWNERSHIP_LABELS.items()}


def _authoritative_container_binding(inspected: dict[str, Any]) -> tuple[str, dict[str, str]]:
    immutable_id = str(inspected.get("Id") or "").strip()
    if not _IMMUTABLE_CONTAINER_ID.fullmatch(immutable_id):
        raise ValueError("Container ownership verification failed: Docker returned no canonical immutable ID.")
    config = inspected.get("Config")
    labels = config.get("Labels") if isinstance(config, dict) else None
    if not isinstance(labels, dict):
        raise ValueError("Container ownership verification failed: container labels are missing.")
    slug = str(labels.get(OWNERSHIP_LABELS["slug"]) or "")
    try:
        slug = validate_slug(slug)
        project = safe_child(SETTINGS.workspaces, slug)
    except ValueError as exc:
        raise ValueError("Container ownership verification failed: project slug binding is invalid.") from exc
    try:
        metadata = read_project_metadata(project).value
    except (OSError, ValueError, UnicodeError, TypeError) as exc:
        raise ValueError("Container ownership verification failed: authoritative project state is unreadable.") from exc
    if not isinstance(metadata, dict) or str(metadata.get("runtime_provider") or "") != "docker-compose":
        raise ValueError("Container ownership verification failed: project is not currently Compose-managed.")
    expected = container_ownership_labels(metadata)
    if expected[OWNERSHIP_LABELS["deployment_id"]] != SETTINGS.deployment_id or expected[OWNERSHIP_LABELS["host_id"]] != SETTINGS.host_id:
        raise ValueError("Container ownership verification failed: project deployment or host binding is not current.")
    mismatches = [key for key, value in expected.items() if str(labels.get(key) or "") != value]
    compose_project = str(labels.get("com.docker.compose.project") or "")
    compose_service = str(labels.get("com.docker.compose.service") or "")
    if compose_project != expected[OWNERSHIP_LABELS["runtime_id"]] or not compose_service:
        mismatches.append("com.docker.compose.project/service")
    if mismatches:
        raise ValueError("Container ownership verification failed: complete DevFleet/Compose binding does not match current project state (" + ", ".join(sorted(set(mismatches))) + ").")
    return immutable_id, expected


def validate_container_ref(value: str) -> str:
    value = str(value or "").strip()
    if not _CONTAINER_ID.fullmatch(value):
        raise ValueError("Invalid container reference.")
    return value


def _json_lines(args: list[str], timeout: int = 8) -> list[dict[str, Any]]:
    result = run(args, check=False, timeout=timeout)
    rows: list[dict[str, Any]] = []
    for line in (result.stdout or "").splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            rows.append(value)
    return rows


def _docker_inspect(ref: str) -> dict[str, Any]:
    result = run(["docker", "inspect", ref], check=False, timeout=10)
    if result.returncode:
        raise ValueError((result.stderr or "Container not found.").strip()[-1000:])
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError("Docker returned invalid inspect data.") from exc
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
        raise ValueError("Container not found.")
    return data[0]


def _authorized_read(ref: str) -> tuple[str, dict[str, str], dict[str, Any]]:
    """Resolve, bind, and revalidate a read before data can leave the service."""
    inspected = _docker_inspect(ref)
    immutable_id, expected = _authoritative_container_binding(inspected)
    try:
        current = _docker_inspect(immutable_id)
    except ValueError as exc:
        raise ValueError("Container ownership verification failed: immutable container disappeared before the read.") from exc
    current_id, current_expected = _authoritative_container_binding(current)
    if current_id != immutable_id or current_expected != expected:
        raise ValueError("Container ownership verification failed: immutable identity changed before the read.")
    return immutable_id, expected, current


def list_containers() -> list[dict[str, Any]]:
    """Return a safe, Portainer-style summary without exposing the Docker socket."""
    containers = _json_lines([
        "docker", "ps", "-a", "--no-trunc", "--format",
        "{{json .}}",
    ])
    stats = _json_lines([
        "docker", "stats", "--no-stream", "--format", "{{json .}}",
    ])
    stats_by_id = {str(item.get("ID") or ""): item for item in stats}
    result: list[dict[str, Any]] = []
    for item in containers:
        ref = str(item.get("ID") or "")
        if not ref:
            continue
        try:
            immutable_id, expected, inspected = _authorized_read(ref)
        except ValueError:
            # A Docker-engine container without a current authoritative DevFleet
            # binding is deliberately absent, including from metrics.
            continue
        stat = stats_by_id.get(immutable_id) or {}
        name = str(inspected.get("Name") or item.get("Names") or immutable_id[:12]).lstrip("/")
        result.append({
            "id": immutable_id,
            "short_id": immutable_id[:12],
            "name": name,
            "image": item.get("Image") or "",
            "state": item.get("State") or "unknown",
            "status": item.get("Status") or "",
            "created": item.get("CreatedAt") or "",
            "ports": item.get("Ports") or "",
            "labels": expected,
            "cpu_percent": stat.get("CPUPerc") or "—",
            "memory_usage": stat.get("MemUsage") or "—",
            "memory_percent": stat.get("MemPerc") or "—",
            "network_io": stat.get("NetIO") or "—",
            "block_io": stat.get("BlockIO") or "—",
            "pids": stat.get("PIDs") or "—",
        })
    return result


def inspect_container(ref: str) -> dict[str, Any]:
    ref = validate_container_ref(ref)
    _, _, inspected = _authorized_read(ref)
    return inspected


def container_logs(ref: str, tail: int = 200) -> str:
    ref = validate_container_ref(ref)
    tail = max(1, min(int(tail), 1000))
    immutable_id, _, _ = _authorized_read(ref)
    result = run([
        "docker", "logs", "--timestamps", "--tail", str(tail), immutable_id,
    ], check=False, timeout=15)
    output = ((result.stdout or "") + (result.stderr or "")).strip()
    return output[-30000:] or "No container log output."


def container_action(ref: str, action: str) -> str:
    ref = validate_container_ref(ref)
    command = _ACTIONS.get(str(action or "").lower())
    if not command:
        raise ValueError("Unsupported container action.")
    inspected = _docker_inspect(ref)
    immutable_id, expected = _authoritative_container_binding(inspected)
    slug = expected[OWNERSHIP_LABELS["slug"]]
    project_id = expected[OWNERSHIP_LABELS["project_id"]]
    # Lazy import avoids the projects -> containers module dependency cycle.
    # Both paths use the same cross-process lock and control-owned marker.
    from .projects import (
        load_authoritative_project_identity_for_mutation,
        project_transfer_lock,
    )

    with project_transfer_lock(slug):
        try:
            current = _docker_inspect(ref)
        except ValueError as exc:
            raise ValueError("Container ownership verification failed: immutable container disappeared before mutation; no same-name replacement was touched.") from exc
        current_id, current_expected = _authoritative_container_binding(current)
        if current_id != immutable_id or current_expected != expected:
            raise ValueError("Container ownership verification failed: immutable identity changed before mutation.")
        project = safe_child(SETTINGS.workspaces, slug)
        authoritative = load_authoritative_project_identity_for_mutation(project)
        if (
            str(authoritative.get("runtime_provider") or "") != "docker-compose"
            or container_ownership_labels(authoritative) != expected
            or str(authoritative.get("project_id") or "") != project_id
        ):
            raise ValueError(
                "Container ownership verification failed: authoritative project identity changed before mutation."
            )
        # Reinspect the immutable ID after the authority decision. A receiver cannot
        # create pending authority or promote a replacement while this lock is held.
        try:
            final = _docker_inspect(immutable_id)
        except ValueError as exc:
            raise ValueError(
                "Container ownership verification failed: immutable container disappeared before mutation."
            ) from exc
        final_id, final_expected = _authoritative_container_binding(final)
        if final_id != immutable_id or final_expected != expected:
            raise ValueError(
                "Container ownership verification failed: immutable identity changed before mutation."
            )
        result = run(["docker", command, immutable_id], check=False, timeout=60)
        if result.returncode:
            raise ValueError((result.stderr or result.stdout or "Docker action failed.").strip()[-2000:])
        return (result.stdout or result.stderr or f"Container {action} completed.").strip()[-4000:]

```


## FILE: source/app/devfleet/core.py

SHA256: 244499e96e005ac615042edbe10082a93110f186de8340cdc8a77c95341ac77c | Bytes: 13760 | Git mode: 100644

```
"""Shared DevFleet settings, validation, and crash-safe filesystem helpers.

This module deliberately contains no host-management logic.  Host changes are
made only through the narrow authenticated host-agent client.
"""
from __future__ import annotations

import json
import ipaddress
import os
import re
import secrets
import stat
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .metadata_io import enable_inherited_backup_read

try:
    import pwd
except ImportError:  # pragma: no cover - Windows has no pwd module.
    pwd = None


CONFIG_PATH = Path(os.environ.get("DEVFLEET_CONFIG_PATH", "/etc/devfleet/config.json"))
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{1,62}$")
PROJECT_ID_RE = re.compile(r"^[0-9a-fA-F-]{36}$")


@dataclass(frozen=True)
class Settings:
    node_name: str
    deployment_id: str
    node_role: str
    friendly_name: str
    portal_port: int
    workspaces: Path
    quarantine: Path
    peer_file: Path
    runtime_root: Path
    cache_root: Path
    ollama_base_url: str
    ollama_model: str
    ollama_profile: str
    development_profile: str
    docker_mode: str
    docker_host: str
    docker_owner_uid: int | None
    enable_shared_caches: bool
    enable_analyzer_cache: bool
    auto_start_codexpro: bool
    allow_tailnet_ports: bool
    backup_before_rebuild: bool
    backup_before_quarantine: bool
    allow_permanent_delete: bool
    host_control_enabled: bool
    host_control_url: str
    host_control_token: str
    expected_host_name: str
    host_agent_timeout_seconds: int
    host_resource_policy: dict[str, Any]
    admin_user: str
    admin_password: str
    api_token: str
    require_tailscale: bool
    tailnet_cidr: str
    public_binding_allowed: bool

    @property
    def operations(self) -> Path:
        return self.runtime_root / "operations"

    @property
    def host_id(self) -> str:
        return self.node_name


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _default_config() -> dict[str, Any]:
    root = Path(os.environ.get("DEVFLEET_TEST_ROOT", "/tmp/devfleet"))
    return {
        "node_name": os.environ.get("DEVFLEET_NODE_NAME", "devfleet-primary"),
        "deployment_id": os.environ.get("DEVFLEET_DEPLOYMENT_ID", ""),
        "node_role": "primary",
        "friendly_name": "DevFleet",
        "portal_port": 8787,
        "workspaces": str(root / "workspaces"),
        "quarantine": str(root / "quarantine"),
        "peer_file": str(root / "peer.json"),
        "runtime_root": str(root / "runtime"),
        "cache_root": str(root / "cache"),
        "docker_mode": "rootless",
        "docker_host": os.environ.get("DOCKER_HOST", ""),
        "host_resource_policy": {},
        "require_tailscale": True,
        "tailnet_cidr": "100.64.0.0/10",
        "public_binding_allowed": False,
    }


def load_settings() -> Settings:
    if CONFIG_PATH.exists():
        try:
            if os.name != "nt" and str(CONFIG_PATH).startswith("/etc/devfleet/"):
                stat = CONFIG_PATH.stat()
                if stat.st_uid != 0 or stat.st_mode & 0o022:
                    raise ValueError("security configuration ownership or permissions are unsafe")
            cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, TypeError) as exc:
            raise ValueError("security configuration is missing, malformed, or unreadable; refusing fail-open defaults") from exc
        if not isinstance(cfg, dict):
            raise ValueError("security configuration must be a JSON object")
    else:
        cfg = _default_config()
    policy = dict(cfg.get("host_resource_policy") or {})
    return Settings(
        node_name=str(cfg.get("node_name", cfg.get("host_id", "devfleet-primary"))),
        deployment_id=str(cfg.get("deployment_id", "")),
        node_role=str(cfg.get("node_role", "primary")),
        friendly_name=str(cfg.get("friendly_name", cfg.get("node_name", "DevFleet"))),
        portal_port=int(cfg.get("portal_port", 8787)),
        workspaces=Path(cfg.get("workspaces", "/var/lib/devfleet/workspaces")),
        quarantine=Path(cfg.get("quarantine", "/var/lib/devfleet/quarantine")),
        peer_file=Path(cfg.get("peer_file", "/etc/devfleet/peer.json")),
        runtime_root=Path(cfg.get("runtime_root", "/var/lib/devfleet/runtime")),
        cache_root=Path(cfg.get("cache_root", "/var/cache/devfleet")),
        ollama_base_url=str(cfg.get("ollama_base_url", "")),
        ollama_model=str(cfg.get("ollama_model", "")),
        ollama_profile=str(cfg.get("ollama_profile", "stable-interactive")),
        development_profile=str(cfg.get("development_profile", "strict")),
        docker_mode=str(cfg.get("docker_mode", "rootless")),
        docker_host=str(os.environ.get("DOCKER_HOST", cfg.get("docker_host", ""))),
        docker_owner_uid=(int(os.environ["DEVFLEET_DOCKER_OWNER_UID"]) if os.environ.get("DEVFLEET_DOCKER_OWNER_UID") else (int(cfg["docker_owner_uid"]) if cfg.get("docker_owner_uid") is not None else None)),
        enable_shared_caches=bool(cfg.get("enable_shared_caches", False)),
        enable_analyzer_cache=bool(cfg.get("enable_analyzer_cache", True)),
        auto_start_codexpro=bool(cfg.get("auto_start_codexpro", True)),
        allow_tailnet_ports=bool(cfg.get("allow_tailnet_ports", False)),
        backup_before_rebuild=bool(cfg.get("backup_before_rebuild", False)),
        backup_before_quarantine=bool(cfg.get("backup_before_quarantine", True)),
        allow_permanent_delete=bool(cfg.get("allow_permanent_delete", False)),
        host_control_enabled=_env_bool("DEVFLEET_HOST_CONTROL_ENABLED", bool(cfg.get("host_control_enabled", False))),
        host_control_url=str(os.environ.get("DEVFLEET_HOST_CONTROL_URL", cfg.get("host_control_url", ""))),
        host_control_token=str(os.environ.get("DEVFLEET_HOST_CONTROL_TOKEN", cfg.get("host_control_token", ""))),
        expected_host_name=str(cfg.get("expected_host_name", cfg.get("host_name", os.environ.get("COMPUTERNAME", "devfleet-host")))),
        host_agent_timeout_seconds=int(cfg.get("host_agent_timeout_seconds", 30)),
        host_resource_policy=policy,
        admin_user=os.environ.get("DEVFLEET_ADMIN_USER", ""),
        admin_password=os.environ.get("DEVFLEET_ADMIN_PASSWORD", ""),
        api_token=os.environ.get("DEVFLEET_API_TOKEN", ""),
        require_tailscale=bool(cfg.get("require_tailscale", cfg.get("RequireTailscale", True))),
        tailnet_cidr=str(cfg.get("tailnet_cidr", cfg.get("TailnetCidr", "100.64.0.0/10"))),
        public_binding_allowed=bool(cfg.get("public_binding_allowed", cfg.get("PublicBindingAllowed", False))),
    )


SETTINGS = load_settings()


_ROOTLESS_DOCKER_HOST = re.compile(r"^unix:///run/user/(?P<uid>[1-9][0-9]*)/docker\.sock$")


def _expected_docker_owner_uid() -> int:
    if SETTINGS.docker_owner_uid is not None:
        return SETTINGS.docker_owner_uid
    if pwd is not None:
        try:
            return int(pwd.getpwnam("devrunner").pw_uid)
        except KeyError:
            pass
    raise RuntimeError("Rootless Docker owner identity is not configured; refusing to guess from the controller UID.")


def _validate_rootless_docker_host(raw: str) -> str:
    match = _ROOTLESS_DOCKER_HOST.fullmatch(str(raw or "").strip())
    if not match:
        raise RuntimeError("Rootless Docker requires an explicit unix:///run/user/<devrunner-uid>/docker.sock endpoint.")
    configured_uid = int(match.group("uid"))
    expected_uid = _expected_docker_owner_uid()
    if configured_uid != expected_uid:
        raise RuntimeError("Configured Docker socket UID is not the authoritative devrunner owner UID.")
    socket_path = Path(raw[len("unix://"):])
    try:
        socket_stat = os.lstat(socket_path)
    except OSError as exc:
        raise RuntimeError("Configured rootless Docker socket is missing or unreadable.") from exc
    if stat.S_ISLNK(socket_stat.st_mode) or not stat.S_ISSOCK(socket_stat.st_mode):
        raise RuntimeError("Configured rootless Docker endpoint is not a Unix socket.")
    if int(socket_stat.st_uid) != expected_uid:
        raise RuntimeError("Configured rootless Docker socket has an unexpected owner.")
    return raw


def client_allowed_by_network(host: str | None) -> bool:
    """Enforce the configured portal boundary using the TCP peer address.

    Loopback is always allowed for local bootstrap/proxy operations.  When the
    portal requires Tailscale, only the configured tailnet CIDR is accepted;
    arbitrary RFC1918 peers are deliberately not treated as trusted.
    """
    if SETTINGS.public_binding_allowed or not SETTINGS.require_tailscale:
        return True
    try:
        address = ipaddress.ip_address(str(host or "").split("%", 1)[0])
        if address.is_loopback:
            return True
        return address in ipaddress.ip_network(SETTINGS.tailnet_cidr, strict=False)
    except ValueError:
        return False


def validate_slug(value: str) -> str:
    value = str(value or "").strip().lower()
    if not SLUG_RE.fullmatch(value):
        raise ValueError("Project slug must be 2-63 lowercase letters, numbers, dots, underscores, or dashes.")
    return value


def validate_project_id(value: str) -> str:
    value = str(value or "").strip()
    if not PROJECT_ID_RE.fullmatch(value):
        raise ValueError("Project id must be a UUID-shaped value.")
    return value


def safe_child(base: Path, name: str) -> Path:
    slug = validate_slug(name)
    base_real = base.resolve()
    lexical = base_real / slug
    if lexical.is_symlink():
        raise ValueError("Project path may not be a symbolic link.")
    candidate = lexical.resolve(strict=False)
    if candidate.parent != base_real or candidate.name != slug:
        raise ValueError("Unsafe project path.")
    return candidate


def run(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    timeout: int = 900,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    """Run a known executable with bounded time and captured output."""
    if not cmd or any(not isinstance(part, str) or not part for part in cmd):
        rais