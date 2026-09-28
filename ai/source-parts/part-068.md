# DevFleet source part 068

Full-source UTF-8 byte interval [3115500, 3162000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: d73441ef87bfa57b1ed27bb38c430069c897ced3efda59521fec9e5572e1bc84

<!-- BEGIN SOURCE SLICE -->
alyzer_cache=bool(cfg.get("enable_analyzer_cache", True)),
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
        raise ValueError("Command arguments must be non-empty strings.")
    env = os.environ.copy()
    executable = Path(cmd[0]).name.lower()
    if SETTINGS.docker_mode == "rootless" and executable in {"docker", "docker.exe"}:
        env["DOCKER_HOST"] = _validate_rootless_docker_host(env.get("DOCKER_HOST") or SETTINGS.docker_host)
    elif SETTINGS.docker_mode != "rootless":
        env.pop("DOCKER_HOST", None)
    try:
        result = subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else None,
            env=env,
            text=True,
            capture_output=True,
            timeout=max(1, int(timeout)),
            check=False,
        )
    except FileNotFoundError as exc:
        if check:
            raise RuntimeError(f"Command not found: {cmd[0]}") from exc
        return subprocess.CompletedProcess(cmd, 127, "", str(exc))
    except subprocess.TimeoutExpired as exc:
        detail = ((exc.stdout or "") + "\n" + (exc.stderr or ""))[-2000:]
        if check:
            raise RuntimeError(f"Command timed out after {timeout}s: {cmd[0]}\n{detail}") from exc
        return subprocess.CompletedProcess(cmd, 124, exc.stdout or "", exc.stderr or "timeout")
    if check and result.returncode:
        detail = (result.stderr or result.stdout or "")[-4000:]
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(cmd)}\n{detail}")
    return result


def _atomic_replace(temp_name: str, path: Path) -> None:
    deadline = time.monotonic() + 0.5
    while True:
        try:
            os.replace(temp_name, path)
            return
        except PermissionError as exc:
            if getattr(exc, "winerror", None) not in {5, 32, 33} or time.monotonic() >= deadline:
                raise
            time.sleep(0.01)


def atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            handle.flush()
            enable_inherited_backup_read(handle.fileno(), parent=path.parent)
            os.fsync(handle.fileno())
        _atomic_replace(temp_name, path)
    finally:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass


def atomic_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            enable_inherited_backup_read(handle.fileno(), parent=path.parent)
            os.fsync(handle.fileno())
        _atomic_replace(temp_name, path)
    finally:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass


def atomic_json(path: Path, data: Any) -> None:
    atomic_text(path, json.dumps(data, indent=2, sort_keys=True, default=str) + "\n")


def load_peer() -> dict[str, Any]:
    try:
        data = json.loads(SETTINGS.peer_file.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

```


## FILE: source/app/devfleet/failover.py

SHA256: cd69e5b29293e828ef6c7cfcbc4538e73456e3ac3041fffb3ce2059375f81e5d | Bytes: 6853 | Git mode: 100644

```
from __future__ import annotations

import re
import time
from typing import Any, Callable, Protocol


PEER_OPERATION_TIMEOUT_SECONDS = 3700.0
PEER_OPERATION_POLL_INTERVAL_SECONDS = 0.5
PEER_REQUEST_TIMEOUT_SECONDS = 30.0
_OPERATION_ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z")
_PROJECT_ID_RE = re.compile(r"[0-9a-fA-F-]{16,128}\Z")
_TRANSFER_IDENTIFIER_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z")


class Progress(Protocol):
    def update(self, progress: int, message: str) -> None: ...


PeerCall = Callable[[str, str, dict[str, Any] | None, float], Any]


def _operation_endpoint(receipt: Any, phase: str) -> tuple[str, str]:
    """Accept only the native 202 receipt shape and its exact operation endpoint."""
    if (
        not isinstance(receipt, dict)
        or receipt.get("ok") is not True
        or receipt.get("accepted") is not True
    ):
        raise RuntimeError(f"Peer {phase} operation response was malformed.")
    operation_id = receipt.get("operation_id")
    if not isinstance(operation_id, str) or not _OPERATION_ID_RE.fullmatch(operation_id):
        raise RuntimeError(f"Peer {phase} operation response was malformed.")
    operation_url = receipt.get("operation_url")
    if operation_url != f"/api/operations/{operation_id}":
        raise RuntimeError(f"Peer {phase} operation response was malformed.")
    return operation_id, operation_url


def _remaining_request_timeout(deadline: float, phase: str) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise RuntimeError(f"Peer {phase} operation timed out.")
    return min(PEER_REQUEST_TIMEOUT_SECONDS, remaining)


def _await_peer_operation(
    receipt: Any,
    phase: str,
    peer_call: PeerCall,
    deadline: float,
) -> None:
    operation_id, operation_url = _operation_endpoint(receipt, phase)
    while True:
        request_timeout = _remaining_request_timeout(deadline, phase)
        record = peer_call("GET", operation_url, None, request_timeout)
        if not isinstance(record, dict):
            raise RuntimeError(f"Peer {phase} operation response was malformed.")
        record_ids = [record.get("operation_id"), record.get("id")]
        if operation_id not in record_ids or any(
            value is not None and value != operation_id for value in record_ids
        ):
            raise RuntimeError(f"Peer {phase} operation response was malformed.")
        state = record.get("state")
        if not isinstance(state, str):
            raise RuntimeError(f"Peer {phase} operation response was malformed.")
        if (
            state == "locked"
            or record.get("current_step") == "locked"
            or record.get("error") == "operation_locked"
        ):
            raise RuntimeError(f"Peer {phase} operation is locked.")
        if state == "completed":
            return
        if state in {"failed", "interrupted", "cancelled"}:
            raise RuntimeError(f"Peer {phase} operation {state}.")
        if state not in {"queued", "running"}:
            raise RuntimeError(f"Peer {phase} operation response was malformed.")
        remaining = _remaining_request_timeout(deadline, phase)
        time.sleep(min(PEER_OPERATION_POLL_INTERVAL_SECONDS, remaining))


def _submit_and_await_peer_operation(
    method: str,
    path: str,
    payload: dict[str, Any] | None,
    phase: str,
    peer_call: PeerCall,
) -> None:
    deadline = time.monotonic() + PEER_OPERATION_TIMEOUT_SECONDS
    receipt = peer_call(
        method, path, payload, _remaining_request_timeout(deadline, phase)
    )
    _await_peer_operation(receipt, phase, peer_call, deadline)


def _validated_transfer_identity(
    project_id: str,
    deployment_id: str,
    source_host_id: str,
    destination_host_id: str,
) -> tuple[str, str, str, str]:
    if not isinstance(project_id, str) or not _PROJECT_ID_RE.fullmatch(project_id):
        raise ValueError("Ownership transfer requires a valid persisted project ID.")
    if not isinstance(deployment_id, str) or not _TRANSFER_IDENTIFIER_RE.fullmatch(
        deployment_id
    ):
        raise ValueError("Ownership transfer requires a valid deployment ID.")
    if not isinstance(source_host_id, str) or not _TRANSFER_IDENTIFIER_RE.fullmatch(
        source_host_id
    ):
        raise ValueError("Ownership transfer requires a valid source host ID.")
    if not isinstance(destination_host_id, str) or not _TRANSFER_IDENTIFIER_RE.fullmatch(
        destination_host_id
    ):
        raise ValueError("Ownership transfer requires a valid destination host ID.")
    if source_host_id.casefold() == destination_host_id.casefold():
        raise ValueError("Ownership transfer requires a distinct destination host ID.")
    return project_id, deployment_id, source_host_id, destination_host_id


def guided_transfer(
    slug: str,
    ctx: Progress,
    *,
    stop: Callable[[str], Any],
    backup: Callable[[str], Any],
    assert_quiesced: Callable[[str, str], Any],
    project_id: str,
    deployment_id: str,
    source_host_id: str,
    destination_host_id: str,
    finalize_source: Callable[[str, str, str], Any],
    peer_call: PeerCall,
) -> str:
    (
        project_id,
        deployment_id,
        source_host_id,
        destination_host_id,
    ) = _validated_transfer_identity(
        project_id, deployment_id, source_host_id, destination_host_id
    )

    def transfer_payload(confirm_phrase: str) -> dict[str, Any]:
        return {
            "slug": slug,
            "project_id": project_id,
            "deployment_id": deployment_id,
            "source_host_id": source_host_id,
            "destination_host_id": destination_host_id,
            "confirm_slug": slug,
            "confirm_phrase": confirm_phrase,
        }

    ctx.update(5, "Stopping local project")
    stop(slug)
    assert_quiesced(slug, project_id)
    ctx.update(20, "Creating and verifying append-only backup")
    backup(slug)
    assert_quiesced(slug, project_id)
    ctx.update(45, "Receiving verified transfer on peer")
    _submit_and_await_peer_operation(
        "POST",
        "/api/transfers/receive",
        transfer_payload(f"RECEIVE TRANSFER {slug}"),
        "receive transfer",
        peer_call,
    )
    ctx.update(65, "Finalizing source ownership handoff")
    try:
        finalize_source(slug, project_id, destination_host_id)
    except Exception:
        raise RuntimeError("Source transfer finalization failed.") from None
    ctx.update(75, "Activating verified transfer on peer")
    _submit_and_await_peer_operation(
        "POST",
        "/api/transfers/activate",
        transfer_payload(f"ACTIVATE TRANSFER {slug}"),
        "activate transfer",
        peer_call,
    )
    ctx.update(95, "Ownership handoff activated and started on peer")
    return "Ownership transferred to peer."

```


## FILE: source/app/devfleet/host_control.py

SHA256: 47b084d09edea59545bad7d16bf197892edfd2fd1905e06f8fb418e5a466ce53 | Bytes: 20952 | Git mode: 100644

```
"""Narrow authenticated client for the Windows DevFleet host agent."""
from __future__ import annotations

import json
import re
import hashlib
import hmac
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from .core import SETTINGS, validate_project_id, validate_slug
from .resource_profiles import validate_resource_limits


_ACTION_TIMEOUTS = {
    "inspect": 10,
    "health": 15,
    "capacity": 10,
    "provider": 10,
    "start": 120,
    "stop": 120,
    "restart": 180,
    "create": 1200,
    "destroy": 600,
    "backup": 600,
    "list-backups": 30,
    "inspect-backup": 60,
    "restore-backup": 1200,
    "quarantine": 600,
    "restore": 600,
    "import": 900,
    "export": 1200,
    "export-to-source": 1200,
    "restore-previous-source": 300,
    "sync-ssh-alias": 30,
    "refresh-connection-state": 30,
    "project-start": 900,
    "project-stop": 900,
    "project-restart": 1200,
    "project-health": 120,
    "project-test": 1800,
    "project-bootstrap": 3600,
    "project-rebuild": 3600,
    "project-logs": 120,
}


def validate_backup_reference(
    reference: Any,
    *,
    provider: str = "multipass-host-agent",
    project_id: str = "",
    slug: str = "",
    runtime_id: str = "",
    host_id: str = "",
) -> dict[str, Any]:
    """Validate a provider-owned backup identity without accepting a path.

    A provider-local archive path is deliberately not part of the returned
    authority.  Only the provider can resolve and verify the opaque ID.
    """
    if not isinstance(reference, dict):
        raise RuntimeError("Host agent returned no provider-owned backup reference.")
    forbidden = {"backup_path", "archive_path", "manifest_path", "path"}
    if forbidden.intersection(reference):
        raise RuntimeError("Host agent exposed a provider-local backup path as authority.")
    expected = {
        "provider": provider,
        "project_id": project_id,
        "slug": slug,
        "runtime_id": runtime_id,
        "host_id": host_id,
    }
    for key, value in expected.items():
        if value and str(reference.get(key) or "") != str(value):
            raise RuntimeError(f"Provider backup reference {key} does not match the requested identity.")
    for key in ("backup_id", "archive_sha256", "manifest_sha256"):
        if not str(reference.get(key) or ""):
            raise RuntimeError(f"Provider backup reference is missing {key}.")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", str(reference["archive_sha256"])):
        raise RuntimeError("Provider backup reference archive hash is malformed.")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", str(reference["manifest_sha256"])):
        raise RuntimeError("Provider backup reference manifest hash is malformed.")
    if int(reference.get("archive_bytes") or 0) < 0:
        raise RuntimeError("Provider backup reference archive size is malformed.")
    return {key: reference[key] for key in ("provider", "backup_id", "project_id", "slug", "runtime_id", "host_id", "archive_sha256", "archive_bytes", "manifest_sha256", "created_at", "consistency_level") if key in reference}


def build_request_auth(method: str, path: str, body: bytes, key: str, expected_host: str, *, timestamp: int | None = None, nonce: str | None = None) -> dict[str, str]:
    """Build the non-bearer request-authentication headers.

    The key never appears in a request.  The server binds the MAC to the
    expected host, preventing a captured request from being redirected to a
    different configured Host Agent.
    """
    timestamp_text = str(int(time.time()) if timestamp is None else int(timestamp))
    nonce_text = nonce or secrets.token_urlsafe(24)
    material = b"\n".join((method.upper().encode(), path.encode(), timestamp_text.encode(), nonce_text.encode(), body, expected_host.encode()))
    signature = hmac.new(str(key).encode(), material, hashlib.sha256).hexdigest()
    return {"X-DevFleet-Host-Timestamp": timestamp_text, "X-DevFleet-Host-Nonce": nonce_text, "X-DevFleet-Host-Expected": expected_host, "X-DevFleet-Host-Signature": signature}


def _response_auth_material(
    method: str,
    path: str,
    timestamp: str,
    nonce: str,
    status: int,
    body: bytes,
    expected_host: str,
) -> bytes:
    return b"\n".join(
        (
            method.upper().encode(),
            path.encode(),
            str(timestamp).encode(),
            str(nonce).encode(),
            str(int(status)).encode(),
            body,
            expected_host.encode(),
        )
    )


def build_response_auth(
    method: str,
    path: str,
    status: int,
    body: bytes,
    key: str,
    expected_host: str,
    *,
    timestamp: str,
    nonce: str,
) -> str:
    """Return the response MAC bound to the exact authenticated request."""
    material = _response_auth_material(method, path, timestamp, nonce, status, body, expected_host)
    return hmac.new(str(key).encode(), material, hashlib.sha256).hexdigest()


def verify_response_auth(
    method: str,
    path: str,
    status: int,
    body: bytes,
    key: str,
    expected_host: str,
    *,
    timestamp: str,
    nonce: str,
    provided: str,
) -> None:
    expected = build_response_auth(
        method, path, status, body, key, expected_host, timestamp=timestamp, nonce=nonce
    )
    if not provided or not hmac.compare_digest(expected, str(provided).lower()):
        raise RuntimeError("Host agent response authentication failed.")


def _configured() -> None:
    if not SETTINGS.host_control_enabled or not SETTINGS.host_control_url or not SETTINGS.host_control_token:
        raise RuntimeError("Host VM control is not configured on this DevFleet node.")


def _url(path: str) -> str:
    _configured()
    base = SETTINGS.host_control_url.rstrip("/")
    return base + "/" + path.lstrip("/")


def _request(method: str, path: str, payload: dict[str, Any] | None = None, *, timeout: int = 30) -> dict[str, Any]:
    body = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        headers["Content-Type"] = "application/json"
    raw_body = body or b""
    expected_host = str(getattr(SETTINGS, "expected_host_name", "") or "")
    request_auth = build_request_auth(method, path, raw_body, SETTINGS.host_control_token, expected_host)
    headers.update(request_auth)
    request = urllib.request.Request(_url(path), data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=max(1, int(timeout))) as response:
            response_body = response.read()
            verify_response_auth(
                method,
                path,
                int(getattr(response, "status", response.getcode())),
                response_body,
                SETTINGS.host_control_token,
                expected_host,
                timestamp=request_auth["X-DevFleet-Host-Timestamp"],
                nonce=request_auth["X-DevFleet-Host-Nonce"],
                provided=response.headers.get("X-DevFleet-Host-Response-Signature", ""),
            )
            result = json.loads(response_body.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        response_body = exc.read()
        try:
            verify_response_auth(
                method,
                path,
                int(exc.code),
                response_body,
                SETTINGS.host_control_token,
                expected_host,
                timestamp=request_auth["X-DevFleet-Host-Timestamp"],
                nonce=request_auth["X-DevFleet-Host-Nonce"],
                provided=exc.headers.get("X-DevFleet-Host-Response-Signature", ""),
            )
        except RuntimeError:
            raise
        detail = response_body.decode("utf-8", errors="replace")[-2000:]
        raise RuntimeError(f"Host agent rejected request ({exc.code}): {detail}") from exc
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        raise RuntimeError(f"Host agent request failed: {exc}") from exc
    if not isinstance(result, dict) or not result.get("ok", False):
        raise RuntimeError(str(result.get("error") if isinstance(result, dict) else "Host agent returned an invalid response."))
    remote_host = str(result.get("host_name") or result.get("host_id") or "")
    if path != "/healthz" and SETTINGS.expected_host_name and remote_host.lower() != SETTINGS.expected_host_name.lower():
        raise RuntimeError(f"Host identity mismatch: expected {SETTINGS.expected_host_name}, received {remote_host}.")
    return result


def host_control_request(operation: str, payload: dict[str, Any], *, runtime_id: str = "") -> dict[str, Any]:
    """Compatibility entry point that maps intent to a fixed endpoint."""
    operation = str(operation or "").lower()
    if operation == "capacity":
        return _request("GET", "/v1/host/capacity", timeout=_ACTION_TIMEOUTS["capacity"])
    if operation == "provider":
        return _request("GET", "/v1/provider", timeout=_ACTION_TIMEOUTS["provider"])
    if operation == "ensure":
        return _request("POST", "/v1/project-vms", payload, timeout=_ACTION_TIMEOUTS["create"])
    runtime_id = runtime_id or str(payload.get("runtime_id") or "")
    if not runtime_id:
        raise ValueError("A runtime id is required for this host-agent operation.")
    encoded = urllib.parse.quote(runtime_id, safe="")
    if operation == "inspect":
        return _request("GET", f"/v1/project-vms/{encoded}", timeout=_ACTION_TIMEOUTS["inspect"])
    if operation == "destroy":
        # Keep the destructive request on the fixed action route so the
        # Windows host agent receives the JSON confirmation body reliably.
        return _request("POST", f"/v1/project-vms/{encoded}/destroy", payload, timeout=_ACTION_TIMEOUTS["destroy"])
    if operation in {"start", "stop", "restart", "health", "backup", "list-backups", "inspect-backup", "restore-backup", "quarantine", "restore", "export", "export-to-source", "restore-previous-source", "sync-ssh-alias", "refresh-connection-state", "project-start", "project-stop", "project-restart", "project-health", "project-test", "project-bootstrap", "project-rebuild", "project-logs"}:
        return _request("POST", f"/v1/project-vms/{encoded}/{operation}", payload, timeout=_ACTION_TIMEOUTS[operation])
    if operation == "import":
        return _request("POST", f"/v1/project-vms/{encoded}/import", payload, timeout=_ACTION_TIMEOUTS[operation])
    raise ValueError(f"Unsupported host-agent operation: {operation}")


def host_control_status() -> dict[str, Any]:
    if not SETTINGS.host_control_enabled or not SETTINGS.host_control_url or not SETTINGS.host_control_token:
        return {"configured": False, "reachable": False, "status": "not-configured"}
    try:
        result = _request("GET", "/healthz", timeout=5)
        return {"configured": True, "reachable": True, "status": "healthy", **result}
    except Exception as exc:
        return {"configured": True, "reachable": False, "status": "unreachable", "error": str(exc)[-500:]}


def get_host_capacity() -> dict[str, Any]:
    return host_control_request("capacity", {})


def get_provider_status() -> dict[str, Any]:
    return host_control_request("provider", {})


def ensure_project_vm(slug: str, resource_limits: dict[str, Any], *, project_id: str = "", git_url: str = "") -> dict[str, Any]:
    slug = validate_slug(slug)
    project_id = validate_project_id(project_id)
    limits = validate_resource_limits(resource_limits, runtime_type="vm")
    payload = {
        "project_id": project_id,
        "slug": slug,
        "resource_limits": limits,
        "git_url": git_url,
        "gpu": False,
        "gpu_passthrough": False,
    }
    return host_control_request("ensure", payload)


def runtime_project_vm(slug: str, operation: str, *, runtime_id: str = "", project_id: str = "") -> dict[str, Any]:
    payload = {"slug": validate_slug(slug), "project_id": project_id}
    return host_control_request(operation, payload, runtime_id=runtime_id)


def list_project_vm_backups(slug: str, *, runtime_id: str = "", project_id: str = "") -> list[dict[str, Any]]:
    result = host_control_request("list-backups", {"slug": validate_slug(slug), "project_id": validate_project_id(project_id)}, runtime_id=runtime_id)
    backups = result.get("backups")
    if not isinstance(backups, list):
        raise RuntimeError("Host agent returned an invalid backup list.")
    checked: list[dict[str, Any]] = []
    for item in backups:
        if not isinstance(item, dict):
            continue
        reference = item.get("backup_reference") or item
        checked_reference = validate_backup_reference(reference, project_id=project_id, slug=slug, runtime_id=runtime_id)
        checked.append({key: value for key, value in item.items() if key not in {"backup_path", "archive_path", "manifest_path"} and key != "backup_reference"} | {"backup_reference": checked_reference})
    return checked


def inspect_project_vm_backup(slug: str, backup_id: str, *, runtime_id: str = "", project_id: str = "") -> dict[str, Any]:
    payload = {"slug": validate_slug(slug), "project_id": validate_project_id(project_id), "backup_id": str(backup_id or "")}
    result = host_control_request("inspect-backup", payload, runtime_id=runtime_id)
    reference = validate_backup_reference((result.get("backup") or {}).get("backup_reference") or result.get("backup"), project_id=project_id, slug=slug, runtime_id=runtime_id)
    return {key: value for key, value in result.items() if key not in {"backup_path", "archive_path", "manifest_path"}} | {"backup_reference": reference}


def restore_project_vm_backup(slug: str, backup_id: str, *, confirm_restore: bool = False, runtime_id: str = "", project_id: str = "") -> dict[str, Any]:
    if not confirm_restore:
        raise ValueError("Backup restore requires explicit confirmation.")
    payload = {"slug": validate_slug(slug), "project_id": validate_project_id(project_id), "backup_id": str(backup_id or ""), "confirm_restore": True}
    return host_control_request("restore-backup", payload, runtime_id=runtime_id)


def import_project_workspace(slug: str, runtime_id: str, *, source_vm: str, project_id: str = "") -> dict[str, Any]:
    """Copy an existing workspace from the current DevFleet VM into an owned project VM."""
    slug = validate_slug(slug)
    source_vm = validate_slug(source_vm)
    project_id = validate_project_id(project_id)
    if not source_vm.startswith("devfleet-"):
        raise ValueError("Workspace imports are limited to a DevFleet source VM.")
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
    check_