# DevFleet source part 071

Full-source UTF-8 byte interval [3255000, 3301500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: a10e64a7e4a652c2ea0a18152776a11a6dea78082c88595c807a907a19c56e3d

<!-- BEGIN SOURCE SLICE -->
rt_directories()
        try:
            current = self.stat_file()
        except FileNotFoundError:
            current = None
        if current is not None:
            _require_kind(current, stat.S_IFREG)
        observed = self.binding(current)
        if observed != expected:
            raise MetadataSafetyError("Metadata identity or contents changed during the operation.")


def read_project_metadata(project: Path) -> MetadataRecord:
    with _MetadataLocation(project) as location:
        observed = location.stat_file()
        _require_kind(observed, stat.S_IFREG)
        expected = location.binding(observed)
        flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_BINARY", 0)
        if POSIX_FD_HARDENING:
            flags |= os.O_NOFOLLOW | os.O_NONBLOCK
            fd = os.open("project.json", flags, dir_fd=location.directory_fd)
        else:
            fd = os.open(location.directory / "project.json", flags)
        try:
            actual = os.fstat(fd)
            _require_kind(actual, stat.S_IFREG)
            if _version(actual) != _version(observed):
                raise MetadataSafetyError("Metadata file changed before it could be opened.")
            with os.fdopen(fd, "rb", closefd=False) as handle:
                raw = handle.read()
            if _version(os.fstat(fd)) != _version(observed):
                raise MetadataSafetyError("Metadata file changed while it was being read.")
            location.assert_binding(expected)
            value = json.loads(raw.decode("utf-8"))
            location.assert_binding(expected)
            if _version(os.fstat(fd)) != _version(observed):
                raise MetadataSafetyError("Metadata file changed while it was being parsed.")
            return MetadataRecord(value, raw, expected)
        finally:
            os.close(fd)


def write_project_metadata(
    project: Path, value: Any, *, expected: MetadataBinding | None = None,
    create: bool = False,
) -> MetadataBinding:
    raw = (json.dumps(value, indent=2, sort_keys=True, default=str) + "\n").encode("utf-8")
    return write_project_metadata_bytes(project, raw, expected=expected, create=create)


def write_project_metadata_bytes(
    project: Path, raw: bytes, *, expected: MetadataBinding | None = None,
    create: bool = False,
) -> MetadataBinding:
    """Replace metadata inside pinned parents, preserving raw rollback bytes.

    The prior binding is checked immediately before publication. Replacement is
    not an inode compare-and-swap against a hostile writer of the same directory:
    callers still serialize cooperating writers. Even a concurrent parent rename
    cannot redirect the POSIX write into its replacement directory.
    """
    if not isinstance(raw, bytes):
        raise TypeError("Metadata bytes must be bytes.")
    with _MetadataLocation(project, create_directory=create) as location:
        try:
            current = location.stat_file()
        except FileNotFoundError:
            current = None
        if current is not None:
            _require_kind(current, stat.S_IFREG)
        if expected is None:
            if not create or current is not None:
                raise MetadataSafetyError("Existing metadata writes require the prior identity binding.")
            expected = location.binding(None)
        location.assert_binding(expected)
        temporary = f".project.json.{uuid.uuid4().hex}.tmp"
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_BINARY", 0)
        fd = None
        temporary_identity = None
        try:
            if POSIX_FD_HARDENING:
                fd = os.open(temporary, flags | os.O_NOFOLLOW, 0o600, dir_fd=location.directory_fd)
            else:
                fd = os.open(location.directory / temporary, flags, 0o600)
            _require_kind(os.fstat(fd), stat.S_IFREG)
            temporary_identity = _identity(os.fstat(fd))
            with os.fdopen(fd, "wb", closefd=False) as handle:
                handle.write(raw)
                handle.flush()
                enable_inherited_backup_read(fd, parent=location.directory_fd)
                os.fsync(fd)
            written = os.fstat(fd)
            _require_kind(written, stat.S_IFREG)
            written_version = _version(written)
            location.assert_binding(expected)
            staged = location.stat_file(temporary)
            _require_kind(staged, stat.S_IFREG)
            if _version(staged) != written_version or _version(os.fstat(fd)) != written_version:
                raise MetadataSafetyError("Metadata temporary file changed before replacement.")
            if POSIX_FD_HARDENING:
                if expected.file_identity is None:
                    # Atomic first publication must not overwrite a file that
                    # appeared after the absence check. Link only if absent,
                    # then drop the temporary name before the regular-file check.
                    os.link(temporary, "project.json", src_dir_fd=location.directory_fd,
                            dst_dir_fd=location.directory_fd, follow_symlinks=False)
                    os.unlink(temporary, dir_fd=location.directory_fd)
                else:
                    os.replace(temporary, "project.json", src_dir_fd=location.directory_fd,
                               dst_dir_fd=location.directory_fd)
                os.fsync(location.directory_fd)
            else:
                # CRT descriptors deny file deletion; parent directory handles
                # remain pinned while the temporary file is closed and renamed.
                os.close(fd)
                fd = None
                replace = os.rename if expected.file_identity is None else os.replace
                replace(location.directory / temporary, location.directory / "project.json")
            location.assert_directories()
            committed = location.stat_file()
            _require_kind(committed, stat.S_IFREG)
            if _identity(committed) != temporary_identity:
                raise MetadataSafetyError("Committed metadata does not match the written file.")
            binding = location.binding(committed)
            location.assert_binding(binding)
            return binding
        finally:
            if fd is not None:
                os.close(fd)
            if temporary_identity is not None:
                with contextlib.suppress(OSError):
                    if _identity(location.stat_file(temporary)) == temporary_identity:
                        if POSIX_FD_HARDENING:
                            os.unlink(temporary, dir_fd=location.directory_fd)
                        else:
                            os.unlink(location.directory / temporary)


def metadata_identity_matches(
    value: Any, slug: str, project_id: str,
    deployment_id: str | None = None, host_id: str | None = None,
) -> bool:
    if not isinstance(value, dict) or isinstance(value.get("schema_version"), bool):
        return False
    try:
        schema = int(value.get("schema_version"))
    except (TypeError, ValueError, OverflowError):
        return False
    return bool(
        schema >= 3
        and value.get("managed_by") == "devfleet"
        and value.get("slug") == slug
        and (value.get("identity") if value.get("identity") is not None else slug) == slug
        and value.get("project_id") == project_id
        and (deployment_id is None or value.get("deployment_id") == deployment_id)
        and (host_id is None or value.get("host_id") == host_id)
    )


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) not in {4, 5, 6} or args[0] != "--identity":
        return 2
    _action, workspace, slug, project_id, *optional = args
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,62}", slug) or not re.fullmatch(
        r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", project_id
    ):
        return 2
    try:
        record = read_project_metadata(Path(workspace))
        return 0 if metadata_identity_matches(record.value, slug, project_id, *optional) else 1
    except (OSError, ValueError, UnicodeError):
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/app/devfleet/node_registry.py

SHA256: ffd562d4c2685dacea1e183e708530ea4ccf04c20f19e2969d827190b286600b | Bytes: 5199 | Git mode: 100644

```
"""Durable Primary/Surrogate node identity registry without leader election."""
from __future__ import annotations

import json
import uuid
from pathlib import Path
from typing import Any, Iterable

from .core import SETTINGS, atomic_json, now_iso

VALID_ROLES = {"primary", "surrogate", "server"}


def _new_id() -> str:
    return str(uuid.uuid4())


class NodeRegistry:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or SETTINGS.runtime_root / "node-registry.json"

    def _empty(self) -> dict[str, Any]:
        return {"schema_version": 1, "deployment_id": "", "nodes": []}

    def load(self) -> dict[str, Any]:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return self._empty()
        if not isinstance(data, dict) or not isinstance(data.get("nodes", []), list):
            raise ValueError("Node registry is invalid; refusing to infer identities.")
        data.setdefault("schema_version", 1)
        data.setdefault("deployment_id", "")
        return data

    def _save(self, data: dict[str, Any]) -> None:
        if not data.get("deployment_id"):
            raise ValueError("A deployment identity is required.")
        atomic_json(self.path, data)

    def ensure_local(self, *, node_name: str, node_role: str, friendly_name: str = "", deployment_id: str | None = None, coordinator_node_id: str | None = None, capabilities: Iterable[str] = ()) -> dict[str, Any]:
        role = str(node_role or "").strip().lower()
        if role not in VALID_ROLES:
            raise ValueError(f"Unsupported node role: {node_role}")
        data = self.load()
        requested_deployment = str(deployment_id or data.get("deployment_id") or "").strip()
        if not requested_deployment:
            requested_deployment = _new_id()
        if data.get("deployment_id") and data["deployment_id"] != requested_deployment:
            raise ValueError("Deployment identity mismatch; refusing to create a second deployment.")
        data["deployment_id"] = requested_deployment
        name = str(node_name or "").strip()
        if not name:
            raise ValueError("Node name is required.")
        existing = next((n for n in data["nodes"] if isinstance(n, dict) and n.get("node_name") == name), None)
        if existing is not None:
            if existing.get("node_role") != role or existing.get("deployment_id") != requested_deployment:
                raise ValueError("Existing node identity conflicts with the requested role or deployment.")
            existing.update({"friendly_name": friendly_name or existing.get("friendly_name") or name, "capabilities": sorted({str(x) for x in capabilities} | set(existing.get("capabilities") or [])), "coordinator_node_id": coordinator_node_id or existing.get("coordinator_node_id"), "last_seen": now_iso(), "connectivity": "online"})
            self._save(data)
            return dict(existing)
        if role == "surrogate" and not coordinator_node_id:
            raise ValueError("A Surrogate requires an explicit coordinator_node_id.")
        node = {"deployment_id": requested_deployment, "node_id": _new_id(), "node_name": name, "friendly_name": friendly_name or name, "node_role": role, "capabilities": sorted({str(x) for x in capabilities}), "coordinator_node_id": coordinator_node_id if role == "surrogate" else None, "protocol_version": 1, "devfleet_version": "", "health": "unknown", "connectivity": "online", "last_seen": now_iso(), "failover_priority": 100, "compute_capacity": {}, "vault_capability": False, "storage_capacity": {}, "tailscale": {"node": "", "ipv4": "", "ipv6": ""}, "registration_state": "registered"}
        data["nodes"].append(node)
        self._save(data)
        return dict(node)

    def register(self, node: dict[str, Any]) -> dict[str, Any]:
        required = ("deployment_id", "node_id", "node_name", "node_role")
        if any(not str(node.get(key) or "").strip() for key in required):
            raise ValueError("Node registration requires deployment, node, name, and role identities.")
        role = str(node["node_role"]).lower()
        if role not in VALID_ROLES:
            raise ValueError("Unsupported node role.")
        data = self.load()
        if data.get("deployment_id") and data["deployment_id"] != node["deployment_id"]:
            raise ValueError("Node belongs to a different deployment.")
        data["deployment_id"] = node["deployment_id"]
        existing = next((n for n in data["nodes"] if n.get("node_id") == node["node_id"]), None)
        if existing is not None:
            if any(existing.get(key) != node.get(key) for key in ("node_name", "node_role", "deployment_id")):
                raise ValueError("Duplicate node ID has conflicting identity.")
            existing.update(node)
            existing["last_seen"] = now_iso()
            self._save(data)
            return dict(existing)
        data["nodes"].append(dict(node))
        self._save(data)
        return dict(node)

    def list_nodes(self) -> list[dict[str, Any]]:
        return [dict(item) for item in self.load()["nodes"] if isinstance(item, dict)]

```


## FILE: source/app/devfleet/ollama.py

SHA256: 5805e067353f237924b00fff0b0c595db779ccea061b7ad5e34186052dec0e6e | Bytes: 943 | Git mode: 100644

```
from __future__ import annotations
from typing import Any
import httpx
from .core import SETTINGS
def ollama_health(*,queue_probe:bool=False)->dict[str,Any]:
 if not SETTINGS.ollama_base_url:return {'configured':False}
 base=SETTINGS.ollama_base_url.rstrip('/')
 try:
  r=httpx.get(base+'/models',timeout=1.5);r.raise_for_status();models=r.json().get('data',[]);names=[str(x.get('id','')) for x in models]
  out={'configured':True,'ok':True,'endpoint':base,'model':SETTINGS.ollama_model,'model_available':SETTINGS.ollama_model in names,'models':names[:20],'profile':SETTINGS.ollama_profile}
  if queue_probe:
   p=httpx.post(base+'/chat/completions',json={'model':SETTINGS.ollama_model,'messages':[{'role':'user','content':'Reply OK'}],'max_tokens':4},timeout=60);out['queue_response']=p.status_code
  return out
 except Exception as exc:return {'configured':True,'ok':False,'endpoint':base,'error':str(exc),'profile':SETTINGS.ollama_profile}

```


## FILE: source/app/devfleet/operations.py

SHA256: d60334d923abed24439342e38ce4061e702b76a64813082718d29946e6832437 | Bytes: 12217 | Git mode: 100644

```
"""Durable, bounded operation state with per-project serialization."""
from __future__ import annotations

import json
import secrets
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable

from .core import SETTINGS, atomic_json, now_iso


OP_ID_RE = r"^[a-z0-9][a-z0-9._-]{1,127}$"
_EXECUTOR = ThreadPoolExecutor(max_workers=2, thread_name_prefix="devfleet-op")
_ADMISSION = threading.BoundedSemaphore(2)
_LOCK = threading.RLock()
_ACTIVE_LOCKS: dict[str, threading.Lock] = {}
_WORKER_INSTANCE_ID = secrets.token_hex(12)
_LEASE_SECONDS = 45
_QUEUED_SECONDS = 15
_HEARTBEAT_INTERVAL_SECONDS = max(1, _LEASE_SECONDS // 3)


def _lease_until() -> str:
    return (datetime.now(timezone.utc) + timedelta(seconds=_LEASE_SECONDS)).isoformat()


def _lease_expired(value: Any) -> bool:
    if not value:
        return True
    try:
        timestamp = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return True
    if timestamp.tzinfo is None:
        timestamp = timestamp.replace(tzinfo=timezone.utc)
    return timestamp <= datetime.now(timezone.utc)


def _queued_expired(data: dict[str, Any]) -> bool:
    return _lease_expired(data.get("queued_deadline_at") or data.get("lease_expires_at"))


def reconcile_operations() -> list[str]:
    """Mark work that lost its process lease as recoverable, never as complete."""
    recovered: list[str] = []
    if not SETTINGS.operations.exists():
        return recovered
    for record_path in SETTINGS.operations.glob("*.json"):
        try:
            data = json.loads(record_path.read_text(encoding="utf-8"))
            if not isinstance(data, dict) or data.get("state") not in {"queued", "running"}:
                continue
            # Worker identity is diagnostic only.  Lease expiry, not a process
            # restart or instance-id mismatch, is the authority for orphaning
            # work.  A live foreign worker must retain ownership during a
            # rolling restart.
            expired = _queued_expired(data) if data.get("state") == "queued" else _lease_expired(data.get("lease_expires_at"))
            if not expired:
                continue
            op_id = str(data.get("operation_id") or data.get("id") or record_path.stem)
            update_operation(
                op_id,
                state="interrupted",
                current_step="reconciliation-required",
                message="The previous worker stopped before this operation reached a terminal state.",
                recovery_required=True,
                worker_instance_id=None,
                lease_expires_at=None,
                reconciled_at=now_iso(),
                log="Worker lease expired or belonged to a previous process instance.",
            )
            recovered.append(op_id)
        except (OSError, ValueError, json.JSONDecodeError):
            continue
    return recovered


def _path(op_id: str) -> Path:
    import re

    if not re.fullmatch(OP_ID_RE, str(op_id or "")):
        raise ValueError("Invalid operation id.")
    return SETTINGS.operations / f"{op_id}.json"


def _load(op_id: str) -> dict[str, Any]:
    path = _path(op_id)
    last_error: Exception | None = None
    for _ in range(5):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            break
        except (PermissionError, json.JSONDecodeError) as exc:
            last_error = exc
            time.sleep(0.01)
        except OSError as exc:
            raise FileNotFoundError(op_id) from exc
    else:
        raise FileNotFoundError(op_id) from last_error
    if not isinstance(data, dict):
        raise ValueError("Operation record is not an object.")
    return data


def update_operation(op_id: str, **changes: Any) -> dict[str, Any]:
    with _LOCK:
        data = _load(op_id)
        log = changes.pop("log", None)
        if log:
            data.setdefault("log", []).append({"time": now_iso(), "message": str(log)[-4000:]})
            data["log"] = data["log"][-200:]
        data.update(changes)
        data["updated_at"] = now_iso()
        atomic_json(_path(op_id), data)
        return data


def _renew_operation_lease(op_id: str) -> bool:
    """Renew only a still-running operation owned by this worker."""
    with _LOCK:
        try:
            data = _load(op_id)
        except (FileNotFoundError, ValueError):
            return False
        if data.get("state") != "running" or data.get("worker_instance_id") != _WORKER_INSTANCE_ID:
            return False
        data["lease_expires_at"] = _lease_until()
        data["heartbeat_at"] = now_iso()
        data["updated_at"] = now_iso()
        atomic_json(_path(op_id), data)
        return True


def _operation_heartbeat(op_id: str, stop: threading.Event) -> None:
    while not stop.wait(_HEARTBEAT_INTERVAL_SECONDS):
        if not _renew_operation_lease(op_id):
            return


@dataclass
class OperationContext:
    operation_id: str

    def update(self, progress: int, message: str, step: str | None = None) -> None:
        changes: dict[str, Any] = {"progress": max(0, min(100, int(progress))), "message": str(message)}
        if step:
            changes["current_step"] = step
        changes.update({"last_progress_at": now_iso(), "lease_expires_at": _lease_until()})
        update_operation(self.operation_id, **changes)

    def log(self, message: str) -> None:
        update_operation(self.operation_id, log=message)

    def set_runtime(self, runtime_id: str) -> None:
        update_operation(self.operation_id, runtime_id=runtime_id)


def _find_idempotent(key: str) -> str | None:
    if not key or not SETTINGS.operations.exists():
        return None
    for record_path in SETTINGS.operations.glob("*.json"):
        try:
            data = json.loads(record_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if data.get("idempotency_key") == key and data.get("state") in {"queued", "running"}:
            if (data.get("state") == "queued" and _queued_expired(data)) or (data.get("state") == "running" and _lease_expired(data.get("lease_expires_at"))):
                continue
            return str(data.get("id"))
    return None


def submit_operation(
    kind: str,
    project: str,
    func: Callable[[OperationContext], Any],
    *,
    project_id: str = "",
    runtime_id: str = "",
    idempotency_key: str = "",
    host_id: str | None = None,
) -> str:
    SETTINGS.operations.mkdir(parents=True, exist_ok=True)
    reconcile_operations()
    with _LOCK:
        existing = _find_idempotent(idempotency_key)
        if existing:
            return existing
        op_id = f"{kind.lower().replace('_', '-')}-{secrets.token_hex(6)}"
        record = {
            "id": op_id,
            "operation_id": op_id,
            "kind": kind,
            "operation_type": kind,
            "project": project,
            "project_id": project_id,
            "host_id": host_id or SETTINGS.host_id,
            "runtime_id": runtime_id,
            "idempotency_key": idempotency_key,
            "state": "queued",
            "current_step": "queued",
            "progress": 0,
            "message": "Queued",
            "created_at": now_iso(),
            "started_at": None,
            "updated_at": now_iso(),
            "completed_at": None,
            "log": [],
            "recovery_metadata": {"resume_policy": "reconcile-before-retry"},
            "worker_instance_id": _WORKER_INSTANCE_ID,
            "operation_generation": 1,
            "lease_expires_at": None,
            "queued_deadline_at": (datetime.now(timezone.utc) + timedelta(seconds=_QUEUED_SECONDS)).isoformat(),
            "last_progress_at": now_iso(),
            "recovery_required": False,
        }
        atomic_json(_path(op_id), record)

    if not _ADMISSION.acquire(blocking=False):
        update_operation(
            op_id,
            state="failed",
            current_step="capacity",
            message="DevFleet is busy processing the maximum number of lifecycle operations; retry shortly.",
            error="operation_capacity",
            completed_at=now_iso(),
            lease_expires_at=None,
        )
        return op_id

    lock_key = f"project:{project.lower()}" if project else f"operation:{kind.lower()}"

    def runner() -> None:
        def admit_if_still_queued() -> bool:
            with _LOCK:
                data = _load(op_id)
                if data.get("state") != "queued":
                    return False
                if _queued_expired(data):
                    update_operation(op_id, state="interrupted", current_step="reconciliation-required", message="Queued operation expired before execution capacity became available.", recovery_required=True, completed_at=now_iso(), queued_deadline_at=None)
                    return False
                return True

        if not admit_if_still_queued():
            _ADMISSION.release()
            return
        with _LOCK:
            project_lock = _ACTIVE_LOCKS.setdefault(lock_key, threading.Lock())
        acquired = project_lock.acquire(blocking=False)
        if not acquired:
            update_operation(op_id, state="failed", current_step="locked", message="Another lifecycle operation is already active for this project.", error="operation_locked")
            _ADMISSION.release()
            return
        if not admit_if_still_queued():
            project_lock.release()
            _ADMISSION.release()
            return
        heartbeat_stop = threading.Event()
        heartbeat_thread: threading.Thread | None = None
        try:
            update_operation(op_id, state="running", current_step="starting", progress=1, message="Started", started_at=now_iso(), worker_instance_id=_WORKER_INSTANCE_ID, lease_expires_at=_lease_until(), queued_deadline_at=None, last_progress_at=now_iso())
            heartbeat_thread = threading.Thread(target=_operation_heartbeat, args=(op_id, heartbeat_stop), name=f"devfleet-heartbeat-{op_id}", daemon=True)
            heartbeat_thread.start()
            result = func(OperationContext(op_id))
            update_operation(op_id, state="completed", current_step="completed", progress=100, message="Completed", result=str(result)[-12000:], completed_at=now_iso(), lease_expires_at=None, last_progress_at=now_iso())
        except Exception as exc:  # the durable record is the recovery boundary
            message=str(exc)
            update_operation(op_id, state="failed", current_step="failed", message=message, friendly_error=message, recovery_actions=["Review the operation details.", "Re-check runtime and backup status before retrying."], error=traceback.format_exc()[-12000:], completed_at=now_iso(), lease_expires_at=None, last_progress_at=now_iso())
        finally:
            heartbeat_stop.set()
            if heartbeat_thread is not None and heartbeat_thread is not threading.current_thread():
                heartbeat_thread.join(timeout=max(1, _HEARTBEAT_INTERVAL_SECONDS))
            project_lock.release()
            _ADMISSION.release()

    try:
        _EXECUTOR.submit(runner)
    except Exception:
        _ADMISSION.release()
        raise
    return op_id


def get_operation(op_id: str) -> dict[str, Any]:
    reconcile_operations()
    return _load(op_id)


def list_operations(limit: int = 50) -> list[dict[str, Any]]:
    SETTINGS.operations.mkdir(parents=True, exist_ok=True)
    reconcile_operations()
    out: list[dict[str, Any]] = []
    for path in sorted(SETTINGS.operations.glob("*.json"), key=lambda item: item.stat().st_mtime, reverse=True)[: max(1, min(int(limit), 200))]:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                out.append(data)
        except (OSError, json.JSONDecodeError):
            continue
    return out


# Reconcile durable records when this process becomes the new operation owner.
reconcile_operations()

```


## FILE: source/app/devfleet/profiles.py

SHA256: 1cd0b8e2b31ac2ff724837205ac8f83d2ee6cb0916a679512f543b8557f2dcc5 | Bytes: 646 | Git mode: 100644

```
from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True)
class DevelopmentProfile:
    name:str; block_hardening:bool; allow_tailnet:bool; allow_devices:bool; allow_privileged:bool; shared_caches:bool

PROFILES={
 'strict':DevelopmentProfile('strict',True,False,False,False,False),
 'balanced':DevelopmentProfile('balanced',False,True,False,False,True),
 'fast':DevelopmentProfile('fast',False,True,True,True,True),
}
def get_profile(name:str)->DevelopmentProfile:
    key=(name or 'strict').lower()
    if key not in PROFILES: raise ValueError(f'Unknown development profile: {key}')
    return PROFILES[key]

```


## FILE: source/app/devfleet/projects.py

SHA256: 69e28afc1b739e74d8118ac34f4222db40f58b80a87fbef2f58c3be368bc4671 | Bytes: 197999 | Git mode: 100644

```
from __future__ import annotations
import base64, copy, errno, json, re, shutil, stat, time, uuid, hashlib, tarfile, os, contextlib
from urllib.parse import quote
from pathlib import Path
from typing import Any
from .core import (
    SETTINGS,
    atomic_bytes,
    atomic_json,
    atomic_text,
    now_iso,
    run,
    safe_child,
    validate_project_id,
    validate_slug,
)
from .analyzer import analyze_project, has_blockers
from .language_policy import TEMPLATES, recommend_template, template_metadata
from .caches import cache_override
from .leases import load_lease, update_lease, heartbeat_lease
from .codexpro import codexpro_status
from .resource_profiles import (
    get_resource_profile,
    resource_metadata,
    resource_override_path,
    ownership_override_path,
    recommend_resource_profile,
    recommend_runtime_isolation,
    write_resource_override,
    write_ownership_override,
    validate_resource_limits,
    custom_resource_metadata,
    capacity_allows,
    resolved_resource_metadata,
)
from .containers import container_ownership_labels
from .host_control import (
    destroy_project_vm,
    get_host_capacity,
    import_project_workspace,
    sync_project_vm_ssh_alias,
)
from .runtime import VM_RUNTIME, VmRuntimeOperations, provider_for, runtime_metadata
from .workspace_archives import (
    create_workspace_archive,
    inspect_workspace,
    restore_workspace_archive,
    validate_archive,
    write_backup_manifest,
)
from .metadata_io import (
    MetadataBinding,
    MetadataSafetyError,
    read_project_metadata,
    write_project_metadata,
    write_project_metadata_bytes,
)


class _MetadataSnapshot(dict[str, Any]):
    """Metadata mapping carrying the version observed before mutation."""

    def __init__(
        self,
        value: dict[str, Any],
        *,
        binding: MetadataBinding | None = None,
        raw: bytes = b"",
    ):
        super().__init__(value)
        self._observed = copy.deepcopy(value)
        self._metadata_binding = binding
        self._metadata_raw = raw

TEMPLATE_ROOT = Path("/opt/devfleet/project-templates")
GITHUB_URL_RE = re.compile(
    r"^(?:https://github\.com/[^/\s]+/[^/\s]+(?:\.git)?|git@github\.com:[^/\s]+/[^/\s]+(?:\.git)?|ssh://git@github\.com/[^/\s]+/[^/\s]+(?:\.git)?)$"
)
BRANCH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$")
PROJECT_COMMAND_KEYS = (
    "bootstrap_command",
    "health_command",
    "test_command",
    "format_command",
    "lint_command",
    "start_command",
    "stop_command",
    "restart_command",
    "rebuild_command",
    "logs_command",
    "codexpro_command",
)
VM_LIFECYCLE_COMMAND_KEYS = (
    "start_command",
    "stop_command",
    "restart_command",
    "rebuild_command",
    "logs_command",
)
FINGERPRINT_POLICY_VERSION = 1
FINGERPRINT_ALGORITHM = "sha256-relative-path-and-bytes-v1"
IGNORED_FINGERPRINT_DIRS = {
    "node_modules", ".next", "build", "dist", ".venv", "venv",
    ".pytest_cache", "__pycache__", ".test-runtime",
}
@contextlib.contextmanager
def _destructive_lock(slug: str):
    """Serialize destructive lifecycle work across API workers/processes."""
    root = (SETTINGS.runtime_root / "lifecycle-locks").resolve()
    root.mkdir(parents=True, exist_ok=True)
    path = root / f"{validate_slug(slug)}.lock"
    handle = path.open("a+b")
    lock_kind = "none"
    try:
        if handle.seek(0, os.SEEK_END) == 0:
            handle.write(b"0")
            handle.flush()
        handle.seek(0)
        try:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            lock_kind = "fcntl"
        except ImportError:
            import msvcrt

            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
            lock_kind = "msvcrt"
        yield
    finally:
        if lock_kind == "fcntl":
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        elif lock_kind == "msvcrt":
            import msvcrt

            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        handle.close()


@contextlib.contextmanager
def project_transfer_lock(slug: str):
    """Serialize one source-side ownership transfer with destructive work."""
    with _destructive_lock(validate_slug(slug)):
        yield


def _source_state_fingerprint(
    project: Path,
    *,
    include_generated: bool = False,
    exclude_ownership_lease: bool = False,
    return_full_lease_variant: bool = False,
) -> str | tuple[str, str]:
    """Hash source bytes, optionally capturing both lease variants in one walk."""
    digest = hashlib.sha256()
    full_digest = hashlib.sha256() if return_full_lease_variant else None
    for current, dirs, names in os.walk(project, topdown=True, followlinks=False):
        if not include_generated:
            dirs[:] = [d for d in dirs if d not in IGNORED_FINGERPRINT_DIRS]
        dirs[:] = sorted(dirs)
        for name in sorted(names):
            path = Path(current) / name
            rel = path.relative_to(project).as_posix()
            if rel == ".devfleet/project.json":
                continue
            excluded_lease = exclude_ownership_lease and rel == ".devfleet/ownership-lease.json"
            if excluded_lease and full_digest is None:
                continue
            if path.is_symlink() or not path.is_file():
                raise ValueError(
                    f"Workspace changed to an unsupported entry during destructive preparation: {rel}"
                )
            targets = ([digest] if not excluded_lease else []) + ([full_digest] if full_digest else [])
            for target in targets:
                target.update(rel.encode())
                target.update(b"\0")
            with path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    for target in targets:
                        target.update(chunk)
            for target in targets:
                target.update(b"\0")
    return (digest.hexdigest(), full_digest.hexdigest()) if full_digest else digest.hexdigest()


def _safety_backup_fields(
    result: dict[str, Any], meta: dict[str, Any]
) -> tuple[str, str, str]:
    runtime = result.get("runtime") if isinstance(result.get("runtime"), dict) else {}
    backup_id = str(
        result.get("backup_id")
        or runtime.get("backup_id")
        or meta.get("backup_id")
        or ""
    )
    backup_sha = str(
        result.get("backup_sha256")
        or runtime.get("backup_sha256")
        or meta.get("backup_sha256")
        or ""
    )
    status = str(
        result.get("backup_status")
        or runtime.get("backup_status")
        or meta.get("backup_status")
        or ""
    ).lower()
    return backup_id, backup_sha, status


def _assert_safety_binding_current(project: Path, binding: dict[str, Any]) -> None:
    """Fail closed if workspace bytes or exact project identity drifted."""
    policy = binding.get("fingerprint_policy")
    if not isinstance(policy, dict) or int(policy.get("schema_version", 0)) != FINGERPRINT_POLICY_VERSION:
        raise RuntimeError("Destructive deletion blocked: the safety fingerprint policy is missing or unsupported.")
    if policy.get("algorithm") != FINGERPRINT_ALGORITHM:
        raise RuntimeError("Destructive deletion blocked: the safety fingerprint algorithm is not recognized.")
    include_generated = bool(policy.get("include_generated"))
    expected_ignored = [] if include_generated else sorted(IGNORED_FINGERPRINT_DIRS)
    if sorted(policy.get("ignored_directories") or []) != expected_ignored:
        raise RuntimeError("Destructive deletion blocked: the recorded safety fingerprint policy is inconsistent.")
    current = _source_state_fingerprint(project, include_generated=include_generated)
    if current != str(binding.get("source_state_fingerprint") or ""):
        raise RuntimeError(
            "Destructive deletion blocked: workspace changed after the safety backup; no deletion was performed."
        )
    current_meta = load_meta(project)
    for key in ("project_id", "runtime_id"):
        expected = str(binding.get(key) or "")
        if expected and str(current_meta.get(key) or "") != expected:
            raise RuntimeError(
                f"Destructive deletion blocked: {key} changed after the safety backup; no deletion was performed."
            )


_SAFE_COMPOSE_COMMANDS = {
    "docker compose up -d --build",
    "docker compose down --remove-orphans",
    "docker compose restart",
    "docker compose build && docker compose up -d",
    "docker compose logs",
}


def metadata_path(project: Path) -> Path:
    return project / ".devfleet/project.json"


def _write_project_metadata(
    project: Path,
    value: dict[str, Any],
    *,
    expected: MetadataBinding | None = None,
    create: bool = False,
) -> MetadataBinding:
    """Commit metadata through one identity-bound descriptor transaction."""
    binding = expected or getattr(value, "_metadata_binding", None)
    if binding is None and not create:
        binding = read_project_metadata(project).binding
    refreshed = write_project_metadata(
        project, value, expected=binding, create=create
    )
    if isinstance(value, _MetadataSnapshot):
        value._metadata_binding = refreshed
        value._observed = copy.deepcopy(value)
    return refreshed


def _write_project_metadata_bytes(
    project: Path,
    raw: bytes,
    *,
    expected: MetadataBinding | None = None,
) -> MetadataBinding:
    binding = expected or read_project_metadata(project).binding
    return write_project_metadata_bytes(project, raw, expected=binding)


def _raw_meta(project: Path) -> dict[str, Any]:
    try:
        value = read_project_metadata(project).value
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, UnicodeError):
        return {}


def load_project_for_catalog(project: Path) -> dict[str, Any]:
    """Load display metadata with recovery defaults; never grants mutation authority."""
    record = None
    try:
        record = read_project_metadata(project)
        data = record.value
        data = data if isinstance(data, dict) else {}
        if not data:
            data = {}
    except Exception:
        data = {}
    runtime_isolation = str(data.get("runtime_isolation") or "container")
    runtime_type = str(data.get("runtime_type") or runtime_isolation)
    resource_profile = str(
        data.get("resource_profile") or data.get("project_scale") or "standard"
    ).lower()
    if resource_profile not in ("small", "standard", "large", "xlarge", "custom"):
        resource_profile = "standard"
    resource_limits = data.get("resource_limits")
    if not isinstance(resource_limits, dict):
        resource_limits = resource_metadata(
            resource_profile,
            runtime_type if runtime_type in ("container", "vm") else "container",
        )
    observed_resources = data.get("actual_runtime_resources") if isinstance(data.get("actual_runtime_resources"), dict) else (resource_limits if resource_profile == "custom" else None)
    resource_state = resolved_resource_metadata(
        resource_profile,
        runtime_type if runtime_type in ("container", "vm") else "container",
        actual_runtime_resources=observed_resources,
    )
    defaults = {
        "schema_version": 3,
        "project_id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"devfleet:{project.name}")),
        "slug": project.name,
        "identity": project.name,
        "display_name": project.name,
        "template": "existing",
        "profile": SETTINGS.development_profile,
        "runtime_isolation": runtime_isolation,
        "runtime_type": runtime_type,
        "runtime_provider": (
            "docker-compose" if runtime_isolation != "vm" else "multipass-host-agent"
        ),
        "runtime_status": "container-ready" if runtime_isolation != "vm" else "unknown",
        "lifecycle_status": "ready",
        "provisioning_status": "ready" if runtime_isolation != "vm" else "unknown",
        "health_status": "unknown",
        "health_scope": "not-checked",
        "workspace_location": str(project),
        "host_id": SETTINGS.node_name,
        "runtime_id": "",
        "gpu_enabled": False,
        "backup_status": "not-verified",
        "quarantine_state": "active",
        "last_error": "",
        "last_operation_id": "",
        "resource_profile": resource_profile,
        "resource_limits": resource_limits,
        "requested_resource_profile": resource_state["requested_profile"],
        "resolved_resources": resource_state["resolved_resources"],
        "actual_runtime_resources": resource_state["actual_runtime_resources"],
        "resource_policy_version": resource_state["policy_version"],
        "resource_drift": resource_state["resource_drift"],
        "resource_drift_status": resource_state["resource_drift_status"],
    }
    for key, value in defaults.items():
        data.setdefault(key, value)
    return _MetadataSnapshot(
        data,
        binding=record.binding if record is not None else None,
        raw=record.raw if record is not None else b"",
    )


def load_meta(project: Path) -> dict[str, Any]:
    """Compatibility alias for read-only/catalog callers.

    Dangerous operations must call load_authoritative_project_identity_for_mutation
    instead.  Keeping this alias makes the boundary explicit at call sites while
    preserving the existing catalog API.
    """
    return load_project_for_catalog(project)


def _vault_recovery_workspace_path(project: Path) -> str:
    """Return the normalized lexical workspace name, without following aliases."""
    return str(Path(os.path.abspath(os.fspath(project))))


_GENERATED_VAULT_RECOVERY_NAME_RE = re.compile(
    r"[a-z0-9][a-z0-9._-]{1,27}-recovered-"
    r"[0-9]{8}-[0-9]{6}-[0-9a-f]{8}\Z"
)


def _is_generated_vault_recovery_name(value: str) -> bool:
    """Match only the exact bounded namespace emitted by the Vault restorer."""
    return _GENERATED_VAULT_RECOVERY_NAME_RE.fullmatch(str(value or "")) is not None


def _vault_recovery_marker_path(project: Path) -> Path:
    project_path = _vault_recovery_workspace_path(project)
    digest = hashlib.sha256(project_path.encode("utf-8")).hexdigest()
    return SETTINGS.runtime_root / "vault-recovery-copies" / f"{digest}.json"


def _record_vault_recovery_copy(
    project: Path, *, source_slug: str, source_project_id: str
) -> None:
    """Persist recovery-only authority outside the developer-writable workspace."""
    project = Path(_vault_recovery_workspace_path(project))
    workspace_root = Path(os.path.abspath(os.fspath(SETTINGS.workspaces.resolve())))
    if project.parent != workspace_root or validate_slug(project.name) != project.name:
        raise RuntimeError("Vault recovery authority path is outside the workspace root.")
    marker_path = _vault_recovery_marker_path(project)
    marker_root = marker_path.parent
    marker_root.mkdir(parents=True, mode=0o750, exist_ok=True)
    if marker_root.is_symlink() or not marker_root.is_dir():
        raise RuntimeError("Vault recovery authority root is unsafe.")
    atomic_json(
        marker_path,
        {
            "schema_version": 1,
            "workspace_path": _vault_recovery_workspace_path(project),
            "workspace_name": project.name,
            "source_slug": validate_slug(source_slug),
            "source_project_id": validate_project_id(source_project_id),
            "created_at": now_iso(),
        },
    )


def _vault_recovery_copy_marker(
    project: Path, *, source_project_id: str
) -> dict[str, Any] | None:
    marker_path = _vault_recovery_marker_path(project)
    if not marker_path.exists():
        return None
    if marker_path.is_symlink() or not marker_path.is_file():
        raise ValueError("Mutation denied: Vault recovery authority is malformed.")
    try:
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(
            "Mutation denied: Vault recovery authority is malformed."
        ) from exc
    if (
        not isinstance(marker, dict)
        or marker.get("schema_version") != 1
        or marker.get("workspace_path") != _vault_recovery_workspace_path(project)
        or marker.get("workspace_name") != project.name
        or marker.get("source_project_id") != source_project_id
    ):
        raise ValueError("Mutation denied: Vault recovery authority is malformed.")
    return marker


def _transfer_pending_marker_path(project: Path) -> Path:
    workspace_path = str(Path(project).absolute())
    digest = hashlib.sha256(workspace_path.encode("utf-8")).hexdigest()
    return SETTINGS.runtime_root / "transfer-pending" / f"{digest}.json"


def _transfer_pending_marker(
    project: Path, *, project_id: str
) -> dict[str, Any] | None:
    marker_path = _transfer_pending_marker_path(project)
    if not marker_path.exists():
        return None
    if marker_path.is_symlink() or not marker_path.is_file():
        raise ValueError("Mutation denied: transfer authority is malformed.")
    try:
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError("Mutation denied: transfer authority is malformed.") from exc
    workspace_path = str(Path(project).absolute())
    if (
        not isinstance(marker, dict)
        or marker.get("schema_version") != 1
        or marker.get("workspace_path") != workspace_path
        or marker.get("workspace_name") != Path(project).name
        or marker.get("project_id") != project_id
        or not re.fullmatch(
            r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
            str(marker.get("deployment_id") or ""),
        )
        or not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}",
            str(marker.get("source_host_id") or ""),
        )
        or not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}",
            str(marker.get("destination_host_id") or ""),
        )
        or marker.get("source_host_id") == marker.get("destination_host_id")
    ):
        raise ValueError("Mutation denied: transfer authority is malformed.")
    return marker


def _record_