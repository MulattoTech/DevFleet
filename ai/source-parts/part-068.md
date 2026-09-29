# DevFleet source part 068

Full-source UTF-8 byte interval [3115500, 3162000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 5203b09420d10f80c55d16511c8063f030eaf0d764b21b9d50010cba57273448

<!-- BEGIN SOURCE SLICE -->
ove": "rm",
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
        raise Va