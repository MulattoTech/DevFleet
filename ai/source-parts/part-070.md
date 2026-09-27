# DevFleet source part 070

Full-source UTF-8 byte interval [3208500, 3255000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 1f4cf821e6b91edd7fab21719eccdacc000eb254df01ec736b8f33973693b07e

<!-- BEGIN SOURCE SLICE -->
"lease_expires_at"))):
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

SHA256: 6ff44e69f1eb4219d8ba2f0a4bc8416c11c7378ce3cdabfcb7f8e78ee33e272b | Bytes: 196892 | Git mode: 100644

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


def _source_state_fingerprint(project: Path, *, include_generated: bool = False) -> str:
    """Hash source paths and bytes, excluding only DevFleet's mutable metadata."""
    digest = hashlib.sha256()
    for current, dirs, names in os.walk(project, topdown=True, followlinks=False):
        if not include_generated:
            dirs[:] = [d for d in dirs if d not in IGNORED_FINGERPRINT_DIRS]
        dirs[:] = sorted(dirs)
        for name in sorted(names):
            path = Path(current) / name
            rel = path.relative_to(project).as_posix()
            if rel == ".devfleet/project.json":
                continue
            if path.is_symlink() or not path.is_file():
                raise ValueError(
                    f"Workspace changed to an unsupported entry during destructive preparation: {rel}"
                )
            digest.update(rel.encode())
            digest.update(b"\0")
            with path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest.update(b"\0")
    return digest.hexdigest()


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


def _record_transfer_pending(
    project: Path,
    *,
    project_id: str,
    deployment_id: str,
    source_host_id: str,
    destination_host_id: str,
) -> dict[str, Any]:
    marker_path = _transfer_pending_marker_path(project)
    marker_root = marker_path.parent
    marker_root.mkdir(parents=True, mode=0o750, exist_ok=True)
    if marker_root.is_symlink() or not marker_root.is_dir():
        raise RuntimeError("Transfer authority root is unsafe.")
    marker = {
        "schema_version": 1,
        "workspace_path": str(Path(project).absolute()),
        "workspace_name": Path(project).name,
        "project_id": validate_project_id(project_id),
        "deployment_id": validate_project_id(deployment_id),
        "source_host_id": source_host_id,
        "destination_host_id": destination_host_id,
        "state": "pending-source-finalization",
        "created_at": now_iso(),
    }
    if (
        not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", source_host_id)
        or not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", destination_host_id
        )
        or source_host_id == destination_host_id
    ):
        raise ValueError("Transfer host identity is invalid.")
    atomic_json(marker_path, marker)
    if _transfer_pending_marker(project, project_id=project_id) != marker:
        raise RuntimeError("Transfer authority marker was not durable.")
    return marker


def _remove_transfer_pending(project: Path, expected: dict[str, Any]) -> None:
    current = _transfer_pending_marker(
        project, project_id=str(expected.get("project_id") or "")
    )
    for key in (
        "workspace_path",
        "workspace_name",
        "project_id",
        "deployment_id",
        "source_host_id",
        "destination_host_id",
        "state",
    ):
        if current is None or current.get(key) != expected.get(key):
            raise RuntimeError("Transfer authority marker changed before removal.")
    marker_path = _transfer_pending_marker_path(project)
    marker_path.unlink()
    if marker_path.exists() or marker_path.is_symlink():
        raise RuntimeError("Transfer authority marker removal was not durable.")


def load_authoritative_project_identity_for_mutation(
    project: Path,
    *,
    require_runtime: bool = False,
    allow_legacy_migration: bool = False,
    allow_pending_transfer: bool = False,
    allow_retired_transfer: bool = False,
) -> dict[str, Any]:
    """Return only a persisted DevFleet ownership record suitable for mutation.

    A directory under the workspace root is not evidence of DevFleet ownership.
    Missing, malformed, incomplete, or mismatched metadata fails closed and never
    receives the catalog loader's synthesized defaults.
    """
    project = Path(project)
    if not project.is_dir() or project.is_symlink():
        raise ValueError("Mutation requires a real project workspace directory.")
    try:
        record = read_project_metadata(project)
        value = record.value
    except FileNotFoundError as exc:
        raise ValueError(
            "Mutation denied: persisted DevFleet ownership metadata is missing."
        ) from exc
    except MetadataSafetyError as exc:
        raise ValueError(
            "Mutation denied: persisted DevFleet ownership metadata is missing."
        ) from exc
    except (OSError, ValueError, UnicodeError) as exc:
        raise ValueError(
            "Mutation denied: project ownership metadata is malformed."
        ) from exc
    if not isinstance(value, dict):
        raise ValueError(
            "Mutation denied: project ownership metadata must be a JSON object."
        )
    try:
        schema = int(value.get("schema_version"))
    except (TypeError, ValueError) as exc:
        raise ValueError(
            "Mutation denied: project ownership schema/version is missing."
        ) from exc
    legacy = (
        schema == 2
        and allow_legacy_migration
        and str(value.get("managed_by") or "").strip().lower() == "devfleet"
        and str(value.get("identity") or "").strip()
        == str(value.get("slug") or "").strip()
    )
    if schema < 3 and not legacy:
        raise ValueError(
            "Mutation denied: project ownership schema/version is unsupported."
        )
    if not legacy and str(value.get("managed_by") or "").strip().lower() != "devfleet":
        raise ValueError(
            "Mutation denied: project is not explicitly marked as DevFleet-owned."
        )
    slug = str(value.get("slug") or "").strip()
    if not slug or slug != project.name or validate_slug(slug) != slug:
        raise ValueError(
            "Mutation denied: persisted project slug does not bind to the workspace path."
        )
    identity = str(value.get("identity") or slug).strip()
    if not identity or identity != slug or validate_slug(identity) != identity:
        raise ValueError(
            "Mutation denied: persisted project identity does not bind to the workspace path."
        )
    project_id = str(value.get("project_id") or "").strip()
    if not re.fullmatch(r"[0-9a-fA-F-]{16,128}", project_id):
        raise ValueError(
            "Mutation denied: persisted project ID is missing or malformed."
        )
    pending_marker = _transfer_pending_marker(project, project_id=project_id)
    persisted_pending_transfer = (
        str(value.get("transfer_state") or "") == "pending-source-finalization"
        or str(value.get("lifecycle_status") or "")
        == "ownership-transfer-pending"
    )
    if (
        pending_marker is not None or persisted_pending_transfer
    ) and not allow_pending_transfer:
        raise ValueError(
            "Mutation denied: ownership transfer awaits source finalization."
        )
    if (
        str(value.get("transfer_state") or "") == "source-retired"
        and not allow_retired_transfer
    ):
        raise ValueError(
            "Mutation denied: project ownership was transferred to another node."
        )
    recovery_marker = _vault_recovery_copy_marker(
        project, source_project_id=project_id
    )
    if recovery_marker is None and _is_generated_vault_recovery_name(project.name):
        raise ValueError(
            "Mutation denied: reserved Vault recovery namespace requires control-owned recovery authority."
        )
    if recovery_marker is not None:
        raise ValueError(
            "Mutation denied: recovered Vault copies require explicit adoption."
        )
    provider = str(value.get("runtime_provider") or "").strip().lower()
    if provider not in {
        "docker-compose",
        "multipass-host-agent",
        "multipass",
        "virtualbox",
    }:
        raise ValueError(
            "Mutation denied: persisted runtime provider is missing or unsupported."
        )
    runtime_id = str(value.get("runtime_id") or "").strip()
    if require_runtime and not runtime_id:
        raise ValueError("Mutation denied: persisted runtime identity is missing.")
    if runtime_id and (
        len(runtime_id) > 128
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]*", runtime_id)
    ):
        raise ValueError("Mutation denied: persisted runtime identity is malformed.")
    if not str(value.get("host_id") or "").strip():
        raise ValueError(
            "Mutation denied: persisted deployment/node ownership is missing."
        )
    return _MetadataSnapshot(value, binding=record.binding, raw=record.raw)


def _commit_project_metadata(project: Path, candidate: dict[str, Any]) -> None:
    """Commit only changes made since the caller's read under the project lock."""
    project = Path(os.path.abspath(os.fspath(project)))
    slug = validate_slug(project.name)
    observed = getattr(candidate, "_observed", None)
    with _destructive_lock(f"metadata-{slug}"):
        latest = load_authoritative_project_identity_for_mutation(project)
        if isinstance(observed, dict):
            sentinel = object()
            for key in set(observed) | set(candidate):
                before = observed.get(key, sentinel)
                after = candidate.get(key, sentinel)
                if before == after:
                    continue
                if key in candidate:
                    latest[key] = copy.deepcopy(candidate[key])
                else:
                    latest.pop(key, None)
        else:
            latest.update(copy.deepcopy(candidate))
        latest["updated_at"] = now_iso()
        _write_project_metadata(project, latest)


def commit_project_metadata(project: Path, candidate: dict[str, Any]) -> None:
    """Public identity-bound metadata commit for API modules."""
    _commit_project_metadata(project, candidate)


@contextlib.contextmanager
def project_metadata_transaction(project: Path):
    """Serialize read-modify-write metadata updates across API processes."""
    project = Path(os.path.abspath(os.fspath(project)))
    slug = validate_slug(project.name)
    with _destructive_lock(f"metadata-{slug}"):
        meta = load_authoritative_project_identity_for_mutation(project)
        yield meta
        meta["updated_at"] = now_iso()
        _write_project_metadata(project, meta)


def workspace_readiness(
    slug: str, metadata: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Return the single readiness contract used by UI and workspace launch."""
    meta = metadata or load_meta(safe_child(SETTINGS.workspaces, slug))
    provider = provider_for(meta)
    state = str(
        meta.get("lifecycle_status") or meta.get("runtime_status") or "unknown"
    ).lower()
    path = str(meta.get("workspace_path") or f"/home/devrunner/workspaces/{slug}")
    if not provider.is_vm:
        # Container application lifecycle and code-workspace lifecycle are separate.
        # The workspace is reached through the managed primary compute SSH target;
        # stopped Compose services must not make the code workspace appear absent.
        alias = str(
            meta.get("workspace_ssh_alias")
            or meta.get("ssh_alias")
            or SETTINGS.node_name
            or "devfleet-primary"
        )
        host = str(
            meta.get("workspace_host")
            or meta.get("host_id")
            or SETTINGS.node_name
            or "devfleet-primary"
        )
        provisioned = bool(meta.get("workspace_provisioned", bool(path)))
        accessible = bool(meta.get("workspace_accessible", True))
        ready = bool(path and alias and host and provisioned and accessible)
        reason = (
            ""
            if ready
            else (
                "Container workspace is not accessible from the primary compute host."
                if not accessible
                else "Container workspace has not been provisioned."
            )
        )
        return {
            "ready": ready,
            "status": "ready" if ready else "not-ready",
            "state": state,
            "reason": reason,
            "runtime_address": host,
            "ssh_alias": alias,
            "workspace_path": path,
            "host_key_pinned": bool(
                meta.get("ssh_host_key_pinned", meta.get("host_key_pinned", False))
            ),
            "authenticated_connection": bool(
                meta.get(
                    "ssh_authenticated", meta.get("authenticated_connection", False)
                )
            ),
            "validated": ready,
            "workspace_provisioned": provisioned,
            "application_running": state == "running",
        }
    if state == "stopped":
        reason = "Not ready — VM is stopped."
    elif state in {"starting", "provisioning", "restarting", "stopping"}:
        reason = f"Waiting — VM is {state}."
    else:
        reason = "Not ready — SSH readiness is being reconciled."
    address = str(meta.get("runtime_address") or "")
    alias = str(meta.get("ssh_alias") or "")
    pinned = bool(meta.get("ssh_host_key_pinned", meta.get("host_key_pinned", False)))
    authenticated = bool(
        meta.get("ssh_authenticated", meta.get("authenticated_connection", False))
    )
    validated = bool(meta.get("ssh_validation_passed", meta.get("validated", False)))
    provisioned = bool(meta.get("workspace_provisioned", False))
    ready = state == "running" and bool(
        address and alias and pinned and authenticated and validated and provisioned
    )
    if ready:
        reason = ""
    elif (
        state == "running"
        and address
        and alias
        and pinned
        and authenticated
        and validated
        and not provisioned
    ):
        reason = "Not ready — workspace path has not been verified."
    return {
        "ready": ready,
        "status": "ready" if ready else "not-ready",
        "state": state,
        "reason": reason,
        "runtime_address": address,
        "ssh_alias": alias,
        "workspace_path": path,
        "host_key_pinned": pinned,
        "authenticated_connection": authenticated,
        "validated": validated,
        "workspace_provisioned": provisioned,
    }


def project_capabilities(
    slug: str, metadata: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Return the server-authoritative, metadata-only project availability model.

    This function must never inspect, start, or contact a runtime.  Ordinary page
    rendering uses it to decide whether a live request is allowed at all.
    """
    meta = metadata or load_meta(safe_child(SETTINGS.workspaces, slug))
    readiness = workspace_readiness(slug, meta)
    provider = provider_for(meta)
    raw_state = (
        str(meta.get("lifecycle_status") or meta.get("runtime_status") or "unknown")
        .strip()
        .lower()
    )
    aliases = {
        "ready": "running",
        "healthy": "running",
        "container-ready": "running",
        "offline": "unreachable",
        "failed": "error",
    }
    state = aliases.get(raw_state, raw_state)
    transitioning = state in {"starting", "stopping", "restarting", "provisioning"}
    running_state = state == "running"
    stopped_state = state == "stopped"
    reachable = running_state and (
        not provider.is_vm or bool(meta.get("runtime_address"))
    )
    live = bool(running_state and reachable and not transitioning)
    return {
        "lifecycle_state": state,
        "runtime_provider": provider.name,
        "runtime_reachable": reachable,
        "runtime_transitioning": transitioning,
        "ssh_ready": (
            bool(readiness.get("ready"))
            if provider.is_vm
            else bool(readiness.get("ready"))
        ),
        "application_health_available": live,
        "logs_available": live,
        "live_metrics_available": live,
        "workspace_open_available": bool(readiness.get("ready")),
        "can_start": stopped_state or state in {"error", "unreachable", "unknown"},
        "can_stop": running_state or state == "starting",
        "can_restart": live,
        "can_query_live_metrics": live,
        "can_query_application_health": live,
        "can_query_logs": live,
        "can_open_workspace": bool(readiness.get("ready")),
        "can_run_runtime_tests": live,
        "can_run_runtime_action": live,
        "status_reason": (
            "Environment stopped."
            if stopped_state
            else (
                f"Environment {state}."
                if transitioning
                else "Runtime is unreachable." if state == "unreachable" else ""
            )
        ),
    }


def _record_vm_readiness(
    meta: dict[str, Any],
    result: dict[str, Any] | None = None,
    *,
    workspace_provisioned: bool | None = None,
) -> None:
    result = result if isinstance(result, dict) else {}
    for target, source in (
        ("runtime_id", "runtime_id"),
        ("runtime_address", "address"),
        ("ssh_alias", "ssh_alias"),
    ):
        value = result.get(source)
        if value is not None and str(value):
            meta[target] = str(value)
    if "host_key_pinned" in result:
        meta["ssh_host_key_pinned"] = bool(result.get("host_key_pinned"))
    if "authenticated_connection" in result:
        meta["ssh_authenticated"] = bool(result.get("authenticated_connection"))
    if "validated" in result:
        meta["ssh_validation_passed"] = bool(result.get("validated"))
    if workspace_provisioned is not None:
        meta["workspace_provisioned"] = bool(workspace_provisioned)
    if meta.get("runtime_address"):
        meta["workspace_host"] = str(meta["runtime_address"])
    meta["workspace_readiness_checked_at"] = now_iso()
    meta["workspace_readiness"] = workspace_readiness(str(meta.get("slug") or ""), meta)


def _json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _safe_vm_command(command: str) -> bool:
    cmd = str(command or "")
    hook_allowed = bool(
        re.fullmatch(
            r"\./\.devfleet/(bootstrap|health-check|smoke-test|codexpro-bootstrap)\.sh",
            cmd,
        )
    )
    compose_allowed = cmd in _SAFE_COMPOSE_COMMANDS
    forbidden = bool(
        re.search(r"[\r\n`$<>]", cmd)
        or re.search(
            r"(?i)(^|\s)(sudo|su|shutdown|reboot|poweroff|systemctl|service|multipass)(\s|$)",
            cmd,
        )
        or re.search(r"(?i)(rm\s+-rf|docker\s+(run|exec)|curl\s+|wget\s+)", cmd)
    )
    return 0 < len(cmd) <= 512 and (hook_allowed or compose_allowed) and not forbidden


def project_command_readiness(
    project: Path, metadata: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Resolve only fixed trusted command keys for legacy project metadata.

    Explicit project values win.  A missing key may fall back first to the copied
    project template and then to the canonical package template identified by the
    project's template id.  Every resolved value must still pass the Host Agent's
    fixed command allowlist.
    """
    raw = metadata if isinstance(metadata, dict) else _raw_meta(project)
    local_template = _json_object(project / ".devfleet/template.json")
    template_id = str(raw.get("template") or local_template.get("id") or "").strip()
    canonical_template: dict[str, Any] = {}
    if template_id and re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,62}", template_id):
        candidate = TEMPLATE_ROOT / template_id / ".devfleet/template.json"
        if candidate.is_file() and not candidate.is_symlink():
            canonical_template = _json_object(candidate)
    nested = raw.get("commands") if isinstance(raw.get("commands"), dict) else {}
    resolved: dict[str, str] = {}
    sources: dict[str, str] = {}
    invalid: dict[str, str] = {}
    for key in PROJECT_COMMAND_KEYS:
        present = False
        value: Any = ""
        source = ""
        if key in raw:
            present = True
            value = raw.get(key)
            source = "project.json"
        elif key in nested:
            present = True
            value = nested.get(key)
            source = "project.json.commands"
        elif key in local_template:
            present = True
            value = local_template.get(key)
            source = "project-template"
        elif key in canonical_template:
            present = True
            value = canonical_template.get(key)
            source = f"canonical-template:{template_id}"
        if not present or value is None or not str(value).strip():
            continue
        command = str(value).strip()
        if not _safe_vm_command(command):
            invalid[key] = source or "unknown"
            continue
        resolved[key] = command
        sources[key] = source
    missing = [key for key in VM_LIFECYCLE_COMMAND_KEYS if key not in resolved]
    invalid_required = {
        key: invalid[key] for key in VM_LIFECYCLE_COMMAND_KEYS if key in invalid
    }
    return {
        "ready": not missing and not invalid_required,
        "resolved_commands": resolved,
        "sources": sources,
        "required_commands": list(VM_LIFECYCLE_COMMAND_KEYS),
        "missing_required": missing,
        "invalid_required": invalid_required,
        "invalid_commands": invalid,
        "template_id": template_id,
    }


def detect_runtime(slug: str) -> dict[str, Any]:
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir():
        raise FileNotFoundError(slug)
    raw = _raw_meta(project)
    meta = load_meta(project)
    explicit = any(
        key in raw
        for key in (
            "runtime_isolation",
            "runtime_type",
            "runtime_provider",
            "resource_profile",
            "resource_limits",
        )
    )
    provider = provider_for(meta)
    return {
        "runtime_isolation": provider.runtime_type,
        "runtime_type": provider.runtime_type,
        "runtime_provider": provider.name,
        "resource_profile": str(meta.get("resource_profile") or "standard"),
        "resource_limits": meta.get("resource_limits")
        or resource_metadata(
            str(meta.get("resource_profile") or "standard"), provider.runtime_type
        ),
        "source": "metadata" if explicit else "inferred-from-existing-workspace",
        "workspace": str(project),
        "runtime_id": str(meta.get("runtime_id") or ""),
        "host_id": str(meta.get("host_id") or SETTINGS.node_name),
        "lifecycle_status": str(meta.get("lifecycle_status") or "unknown"),
        "provisioning_status": str(meta.get("provisioning_status") or "unknown"),
        "health_status": str(meta.get("health_status") or "unknown"),
    }


def project_identity(slug: str) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir():
        raise FileNotFoundError(slug)
    meta = load_meta(project)
    return validate_slug(str(