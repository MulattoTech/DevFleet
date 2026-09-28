# DevFleet source part 075

Full-source UTF-8 byte interval [3441000, 3487500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 21520037f973a527506f69457f234755e1475f5c7cb668effcfda374bb20bde3

<!-- BEGIN SOURCE SLICE -->
roject.iterdir()):
        if not allow_overwrite:
            raise ValueError(
                "Restore refuses to overwrite a non-empty workspace without explicit overwrite confirmation."
            )
        backup_project(slug)
    result = restore_workspace_archive(archive, project, slug)
    restored = load_meta(project)
    restored.update(
        {
            "backup_status": "verified",
            "backup_id": backup_id,
            "backup_path": str(archive),
            "backup_sha256": verified["archive_sha256"],
            "backup_manifest": str(directory / "manifest.json"),
            "updated_at": now_iso(),
            "last_restore_at": now_iso(),
        }
    )
    _write_project_metadata(project, restored)
    return {
        "ok": True,
        "backup_id": backup_id,
        "backup_sha256": verified["archive_sha256"],
        "project": restored,
        "restore": result,
    }


def _recovery_tombstone_path(slug: str, project_id: str) -> Path:
    safe_id = re.sub(r"[^0-9a-fA-F-]", "", str(project_id)) or "unknown"
    return SETTINGS.runtime_root / "recovery-tombstones" / f"{validate_slug(slug)}-{safe_id}.json"


def _write_recovery_tombstone(meta: dict[str, Any], binding: dict[str, Any]) -> Path:
    tombstone = {
        "schema_version": 1,
        "managed_by": "devfleet",
        "project_id": str(meta.get("project_id") or ""),
        "slug": validate_slug(str(meta.get("slug") or "")),
        "runtime_provider": str(meta.get("runtime_provider") or "docker-compose"),
        "host_id": str(meta.get("host_id") or SETTINGS.host_id),
        "backup_id": str(binding.get("backup_id") or ""),
        "backup_sha256": str(binding.get("backup_sha256") or ""),
        "backup_reference": meta.get("backup_reference"),
        "created_at": now_iso(),
    }
    path = _recovery_tombstone_path(tombstone["slug"], tombstone["project_id"])
    path.parent.mkdir(parents=True, exist_ok=True)
    atomic_json(path, tombstone)
    return path


def restore_deleted_project(
    slug: str,
    backup_id: str,
    *,
    project_id: str,
    confirm_restore: bool = False,
) -> dict[str, Any]:
    """Recover a permanently deleted local project from a bound tombstone.

    This path is intentionally separate from live-workspace restore: there is
    no current workspace identity to trust, so the durable tombstone and
    archive metadata must establish every identity before promotion.
    """
    slug = validate_slug(slug)
    project_id = str(project_id or "")
    if not confirm_restore:
        raise ValueError("Deleted-project restore requires explicit confirmation.")
    tombstone_path = _recovery_tombstone_path(slug, project_id)
    if not tombstone_path.is_file():
        raise FileNotFoundError("No durable recovery tombstone exists for this project identity.")
    try:
        tombstone = json.loads(tombstone_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError("Recovery tombstone is invalid.") from exc
    if tombstone.get("slug") != slug or str(tombstone.get("project_id") or "") != project_id:
        raise ValueError("Recovery tombstone identity does not match the requested project.")
    if str(tombstone.get("backup_id") or "") != backup_id:
        raise ValueError("Requested backup is not the tombstone-bound backup.")
    if str(tombstone.get("runtime_provider") or "") != "docker-compose":
        raise ValueError("Deleted VM workspace recovery requires the provider restore lifecycle and cannot use a local archive path.")
    directory = (SETTINGS.runtime_root / "workspace-backups" / backup_id).resolve()
    root = (SETTINGS.runtime_root / "workspace-backups").resolve()
    if directory.parent != root or not directory.is_dir():
        raise FileNotFoundError(backup_id)
    manifest_path = directory / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError("Recovery backup manifest is invalid.") from exc
    if manifest.get("slug") != slug or str(manifest.get("project_id") or "") != project_id:
        raise ValueError("Recovery backup identity does not match the tombstone.")
    workspace = manifest.get("workspace") if isinstance(manifest.get("workspace"), dict) else {}
    archive = Path(str(workspace.get("archive_path") or ""))
    verified = validate_archive(archive, slug)
    expected_sha = str(tombstone.get("backup_sha256") or workspace.get("archive_sha256") or "")
    if verified.get("archive_sha256") != expected_sha or str(workspace.get("archive_sha256") or "") != expected_sha:
        raise ValueError("Recovery archive hash does not match the tombstone and manifest.")
    project = safe_child(SETTINGS.workspaces, slug)
    if project.exists():
        raise ValueError("Deleted-project restore requires an absent destination; no overwrite was performed.")
    restored = restore_workspace_archive(archive, project, slug)
    recovered_meta = load_authoritative_project_identity_for_mutation(project)
    if str(recovered_meta.get("project_id") or "") != project_id or str(recovered_meta.get("slug") or "") != slug or str(recovered_meta.get("managed_by") or "") != "devfleet":
        raise ValueError("Recovered workspace metadata does not prove exact DevFleet ownership.")
    return {"ok": True, "project": recovered_meta, "backup_id": backup_id, "backup_sha256": expected_sha, "restore": restored, "tombstone": str(tombstone_path)}


def rebuild_project(slug: str) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    cf = compose_file(project)
    if SETTINGS.backup_before_rebuild:
        backup_project(slug)
    if provider_for(meta).is_vm:
        result = VmRuntimeOperations.command(
            slug, meta, "project-rebuild", command_key="rebuild"
        )
        return str(result.get("output") or result.get("message") or result)[-12000:]
    if cf:
        _write_current_compose_ownership(project, cf, meta)
        _assert_current_compose_safety(project, meta)
        run([*compose_args(project, cf), "build", "--pull"], cwd=project, timeout=1800)
    return start_project(slug)


def _command(slug: str, key: str, default: str, timeout: int = 1800) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    cf = compose_file(project)
    command = str(meta.get(key) or default).strip()
    if (
        len(command) > 512
        or command.startswith(("/", "~"))
        or ".." in command
        or not (
            command == "true"
            or re.fullmatch(
                r"\./\.devfleet/(bootstrap|health-check|smoke-test|codexpro-bootstrap)\.sh",
                command,
            )
        )
    ):
        raise ValueError("Project command is unsafe or unsupported.")
    if provider_for(meta).is_vm:
        key_map = {
            "bootstrap_command": "project-bootstrap",
            "health_command": "project-health",
            "test_command": "project-test",
            "start_command": "project-start",
            "stop_command": "project-stop",
            "restart_command": "project-restart",
            "rebuild_command": "project-rebuild",
            "logs_command": "project-logs",
            "codexpro_command": "project-bootstrap",
        }
        operation = key_map.get(key)
        if not operation:
            raise ValueError(
                "This VM project command is not an approved provider operation."
            )
        result = VmRuntimeOperations.command(slug, meta, operation, command_key=key)
        return str(result.get("output") or result.get("message") or result)[-12000:]
    if cf:
        _assert_current_compose_safety(project, meta)
        services = run(
            [*compose_args(project, cf), "config", "--services"], cwd=project
        ).stdout.split()
        r = run(
            [
                *compose_args(project, cf),
                "run",
                "--rm",
                services[0],
                "sh",
                "-lc",
                command,
            ],
            cwd=project,
            timeout=timeout,
        )
    else:
        raise ValueError(
            "Host-shell fallback is disabled for project commands without a Compose runtime."
        )
    return (r.stdout + r.stderr)[-12000:]


def bootstrap_project(slug: str) -> str:
    return _command(slug, "bootstrap_command", "./.devfleet/bootstrap.sh", 3600)


def health_project(slug: str) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    try:
        out = _command(slug, "health_command", "./.devfleet/health-check.sh", 300)
    except Exception as exc:
        with project_metadata_transaction(project) as meta:
            meta.update(
                {
                    "health_status": "unhealthy",
                    "health_scope": "application-check-failed",
                    "health_contract": "exit-code-0-healthy",
                    "last_health_check": now_iso(),
                    "last_error": str(exc)[-1000:],
                }
            )
        raise
    with project_metadata_transaction(project) as meta:
        meta.update(
            {
                "health_status": "healthy",
                "health_scope": "application-check",
                "health_contract": "exit-code-0-healthy",
                "last_health_check": now_iso(),
            }
        )
    return out


def test_project(slug: str) -> str:
    out = _command(slug, "test_command", "./.devfleet/smoke-test.sh")
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    meta["last_successful_test"] = now_iso()
    _commit_project_metadata(project, meta)
    return out


def quarantine_project(slug: str) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    if provider_for(meta).is_vm:
        stop_project(slug)
        backup = backup_project(slug)
        result = VmRuntimeOperations.quarantine(slug, meta)
        meta.update(
            {
                "lifecycle_status": "quarantined",
                "runtime_status": "quarantined",
                "health_status": "unknown",
                "quarantine_state": "quarantined",
                "backup_status": "verified",
                "updated_at": now_iso(),
            }
        )
        _commit_project_metadata(project, meta)
        return json.dumps(
            {
                "ok": True,
                "provider": "multipass-host-agent",
                "backup": backup,
                "runtime": result,
            },
            default=str,
        )
    stop_project(slug)
    if SETTINGS.backup_before_quarantine:
        backup_project(slug)
    SETTINGS.quarantine.mkdir(parents=True, exist_ok=True)
    dest = SETTINGS.quarantine / f"{time.strftime('%Y%m%d-%H%M%S')}-{slug}"
    try:
        project.rename(dest)
    except OSError as exc:
        # Workspaces and the quarantine volume can be separate filesystems. A
        # plain rename is atomic only on one filesystem; fall back to shutil.move
        # after the verified backup so the safe cleanup action still completes.
        if exc.errno != errno.EXDEV:
            raise
        shutil.move(str(project), str(dest))
    return str(dest)


def list_quarantine() -> list[dict[str, str]]:
    SETTINGS.quarantine.mkdir(parents=True, exist_ok=True)
    return [
        {"name": p.name, "path": str(p)}
        for p in sorted(SETTINGS.quarantine.iterdir(), reverse=True)
        if p.is_dir() and not p.is_symlink()
    ]


def _load_quarantine_identity(project: Path, expected_slug: str) -> dict[str, Any]:
    """Validate owned metadata inside a timestamp-prefixed quarantine directory."""
    try:
        value = read_project_metadata(project).value
    except FileNotFoundError as exc:
        raise ValueError(
            "Quarantine restore requires real, nonsymlink ownership metadata."
        ) from exc
    except (OSError, ValueError, UnicodeError) as exc:
        raise ValueError("Quarantine restore ownership metadata is malformed.") from exc
    if not isinstance(value, dict):
        raise ValueError("Quarantine restore ownership metadata must be a JSON object.")
    try:
        schema = int(value.get("schema_version"))
    except (TypeError, ValueError) as exc:
        raise ValueError("Quarantine restore ownership schema is missing.") from exc
    slug = str(value.get("slug") or "").strip()
    identity = str(value.get("identity") or slug).strip()
    project_id = str(value.get("project_id") or "").strip()
    provider = str(value.get("runtime_provider") or "").strip().lower()
    runtime_id = str(value.get("runtime_id") or "").strip()
    if (
        schema < 3
        or str(value.get("managed_by") or "").strip().lower() != "devfleet"
        or slug != expected_slug
        or identity != expected_slug
        or validate_slug(slug) != expected_slug
    ):
        raise ValueError(
            "Quarantine restore metadata does not bind to the quarantined project name."
        )
    if not re.fullmatch(r"[0-9a-fA-F-]{16,128}", project_id):
        raise ValueError("Quarantine restore project ID is missing or malformed.")
    if provider not in {
        "docker-compose",
        "multipass-host-agent",
        "multipass",
        "virtualbox",
    }:
        raise ValueError("Quarantine restore runtime provider is missing or unsupported.")
    if runtime_id and (
        len(runtime_id) > 128
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]*", runtime_id)
    ):
        raise ValueError("Quarantine restore runtime identity is malformed.")
    if not str(value.get("host_id") or "").strip():
        raise ValueError("Quarantine restore deployment/node ownership is missing.")
    return _MetadataSnapshot(value)


def restore_quarantine(name: str) -> str:
    match = re.fullmatch(
        r"(?P<stamp>[0-9]{8}-[0-9]{6})-(?P<slug>[a-z0-9][a-z0-9._-]{1,62})",
        str(name or ""),
    )
    if match is None or "/" in name or "\\" in name or name in {".", ".."}:
        raise ValueError("Invalid quarantine name.")
    try:
        time.strptime(match.group("stamp"), "%Y%m%d-%H%M%S")
    except ValueError as exc:
        raise ValueError("Invalid quarantine timestamp.") from exc
    base = SETTINGS.quarantine.resolve()
    lexical = base / name
    if lexical.is_symlink() or not lexical.is_dir():
        raise FileNotFoundError(name)
    src = lexical.resolve(strict=True)
    if src.parent != base or src.name != name:
        raise ValueError("Quarantine restore source is outside the authorized root.")
    slug = validate_slug(match.group("slug"))
    _load_quarantine_identity(src, slug)
    dest = safe_child(SETTINGS.workspaces, slug)
    if dest.exists() or dest.is_symlink():
        raise ValueError(
            "Quarantine restore is blocked: the exact owned workspace path already exists."
        )
    moved = False
    try:
        try:
            src.rename(dest)
        except OSError as exc:
            if exc.errno != errno.EXDEV:
                raise
            shutil.move(str(src), str(dest))
        moved = True
        if src.exists() or src.is_symlink() or not dest.is_dir() or dest.is_symlink():
            raise ValueError(
                "Quarantine restore did not produce a safe workspace directory."
            )
        load_authoritative_project_identity_for_mutation(dest)
    except Exception:
        if moved and dest.is_dir() and not dest.is_symlink() and not src.exists():
            try:
                dest.rename(src)
            except OSError as rollback_exc:
                if rollback_exc.errno != errno.EXDEV:
                    raise RuntimeError(
                        "Quarantine restore failed and rollback could not preserve the source."
                    ) from rollback_exc
                try:
                    shutil.move(str(dest), str(src))
                except Exception as fallback_exc:
                    raise RuntimeError(
                        "Quarantine restore failed and rollback could not preserve the source."
                    ) from fallback_exc
        raise
    return str(dest)


def _validate_recovered_vault_copy(
    source_slug: str,
    source_identity: dict[str, Any],
    raw_target: str,
) -> str:
    base = SETTINGS.workspaces.resolve()
    target = Path(raw_target)
    expected_prefix = f"{source_slug[:28]}-recovered-"
    expected_name = re.fullmatch(
        re.escape(expected_prefix) + r"[0-9]{8}-[0-9]{6}-[0-9a-f]{8}",
        target.name,
    )
    if (
        not target.is_absolute()
        or target.parent != base
        or expected_name is None
        or target.is_symlink()
        or not target.is_dir()
        or target.resolve() != base / target.name
    ):
        raise RuntimeError("Vault restored-copy target is outside the authorized workspace boundary.")
    validate_slug(target.name)
    expected_project_id = validate_project_id(
        str(source_identity.get("project_id") or "")
    )
    # Establish control-owned recovery authority before consulting metadata in
    # the developer-writable restored workspace.  A failed identity validation
    # intentionally leaves this marker in place so the copy cannot become a
    # normally mutable project by rewriting project.json.
    _record_vault_recovery_copy(
        target,
        source_slug=source_slug,
        source_project_id=expected_project_id,
    )
    try:
        restored = read_project_metadata(target).value
    except FileNotFoundError as exc:
        raise RuntimeError(
            "Vault restored copy has no authoritative project metadata."
        ) from exc
    except MetadataSafetyError as exc:
        raise RuntimeError(
            "Vault restored copy has no authoritative project metadata."
        ) from exc
    except (OSError, ValueError, UnicodeError) as exc:
        raise RuntimeError("Vault restored-copy project metadata is malformed.") from exc
    try:
        restored_schema = int(restored.get("schema_version"))
    except (AttributeError, TypeError, ValueError) as exc:
        raise RuntimeError("Vault restored-copy project metadata is unsupported.") from exc
    if (
        not isinstance(restored, dict)
        or restored_schema < 3
        or str(restored.get("managed_by") or "").lower() != "devfleet"
        or str(restored.get("slug") or "") != source_slug
        or str(restored.get("identity") or restored.get("slug") or "") != source_slug
        or str(restored.get("project_id") or "") != expected_project_id
    ):
        raise RuntimeError("Vault restored-copy project identity does not match the requested source.")
    # A recovered copy is data recovery, not implicit project adoption.  Keeping
    # the source identity intact makes every mutation through the new path fail
    # closed until a separate, explicit adoption workflow assigns new ownership.
    return str(target)


def restore_from_vault(slug: str, canonical: bool = False) -> str:
    slug = validate_slug(slug)
    if canonical:
        raise ValueError(
            "Standalone canonical Vault restore is disabled; use restore-copy or the authenticated ownership-transfer workflow."
        )
    project = safe_child(SETTINGS.workspaces, slug)
    with _destructive_lock(slug):
        identity = load_authoritative_project_identity_for_mutation(project)
        project_id = validate_project_id(str(identity.get("project_id") or ""))
        action = "restore-copy"
        receipt = _vault_request(action, slug, project_id, timeout=3720)
        target = str(receipt.get("target") or "")
        if not target:
            raise RuntimeError("Vault broker did not return a restored workspace target.")
        return _validate_recovered_vault_copy(slug, identity, target)


def project_logs(slug: str, tail: int = 150) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    if provider_for(meta).is_vm:
        result = VM_RUNTIME.logs(slug, meta, tail=tail)
        return str(
            result.get("output")
            or result.get("logs")
            or result.get("message")
            or result
        )[-30000:]
    cf = compose_file(project)
    if cf:
        return (
            run(
                [
                    *compose_args(project, cf),
                    "logs",
                    "--no-color",
                    "--tail",
                    str(max(1, min(tail, 500))),
                ],
                cwd=project,
                check=False,
                timeout=60,
            ).stdout
            or ""
        )[-30000:]
    return "No Compose runtime log available."


def bootstrap_codexpro(slug: str) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    if provider_for(meta).is_vm:
        result = VmRuntimeOperations.command(
            slug, meta, "project-bootstrap", command_key="codexpro"
        )
        return str(result.get("output") or result.get("message") or result)[-12000:]
    return _hook(project, compose_file(project))


def destroy_project(slug: str, confirm_slug: str = "", confirm_phrase: str = "") -> str:
    with _destructive_lock(slug):
        project = safe_child(SETTINGS.workspaces, slug)
        meta = load_authoritative_project_identity_for_mutation(project)
        if not SETTINGS.allow_permanent_delete:
            raise ValueError("Permanent project deletion is disabled by policy.")
        if confirm_slug != slug or confirm_phrase != f"DESTROY {slug}":
            raise ValueError(
                "Permanent deletion requires the exact project slug and confirmation phrase."
            )
        safety = safety_backup_project(slug, _lock_held=True)
        meta = safety["meta"]
        binding = safety["binding"]
        backup_result = safety["result"]
        backup_id = str(binding["backup_id"])
        backup_sha256 = str(binding["backup_sha256"])
        _assert_safety_binding_current(project, binding)
        if provider_for(meta).is_vm:
            if str(meta.get("runtime_id") or ""):
                meta["lifecycle_status"] = "destroying"
                meta["provisioning_status"] = "destroying"
                meta["updated_at"] = now_iso()
                _commit_project_metadata(project, meta)
                result = VmRuntimeOperations.destroy(
                    slug,
                    meta,
                    confirm_slug=confirm_slug,
                    confirm_phrase=confirm_phrase,
                    backup_verified=True,
                    backup_id=backup_id,
                    backup_sha256=backup_sha256,
                )
            else:
                result = {
                    "message": "No project VM was allocated; fresh safety workspace archive verified."
                }
        else:
            result = {
                "message": "Project containers quiesced and fresh safety backup verified."
            }
        _assert_safety_binding_current(project, binding)
        tombstone_path = _write_recovery_tombstone(meta, binding)
        shutil.rmtree(project)
        if project.exists():
            raise RuntimeError(
                "Permanent deletion post-condition failed: workspace still exists."
            )
        return (
            str(result.get("message", "Project destroyed."))
            + f" Workspace permanently removed after exact fresh backup binding; recovery tombstone {tombstone_path.name} retained."
        )

```


## FILE: source/app/devfleet/request_guards.py

SHA256: 5162c54a20a1dfa99eea6eeed3773127a7f4714d067e7f5455b3adff1632f83a | Bytes: 8224 | Git mode: 100644

```
"""Bounded admission guards for expensive HTTP parser paths."""
from __future__ import annotations

import logging
import re
import time
from collections.abc import Awaitable, Callable
from typing import Any

from .auth import api_token_valid


LOGGER = logging.getLogger("devfleet.http_admission")
LOGIN_BODY_LIMIT = 64 * 1024
API_BODY_LIMIT = 256 * 1024
DEFAULT_BODY_LIMIT = 256 * 1024
MAX_HEADER_BYTES = 16 * 1024
MAX_HEADER_COUNT = 64
MAX_RANGE_HEADER_BYTES = 4096
MAX_RANGE_COUNT = 8
_RANGE_RE = re.compile(r"^(?:\d+-\d*|-\d+)$")


def _header_map(scope: dict[str, Any]) -> dict[str, str]:
    return {
        bytes(name).decode("latin-1").lower(): bytes(value).decode("latin-1")
        for name, value in scope.get("headers", [])
    }


def _peer(scope: dict[str, Any]) -> str:
    client = scope.get("client")
    return str(client[0])[:200] if client else "unknown"


def _reject_reason(scope: dict[str, Any], reason: str, *, declared: int | None, observed: int, started: float) -> None:
    headers = _header_map(scope)
    LOGGER.warning(
        "bounded HTTP request rejected peer=%s path=%s content_type=%s declared_bytes=%s observed_bytes=%s reason=%s elapsed_ms=%.2f",
        _peer(scope), str(scope.get("path", ""))[:256], headers.get("content-type", "")[:120],
        declared if declared is not None else "missing", observed, reason,
        (time.perf_counter() - started) * 1000,
    )


class RequestAdmissionRejected(Exception):
    def __init__(self, status: int, reason: str) -> None:
        super().__init__(reason)
        self.status = status
        self.reason = reason


def _declared_length(headers: dict[str, str]) -> int | None:
    raw = headers.get("content-length")
    if raw is None:
        return None
    try:
        value = int(raw.strip())
    except ValueError as exc:
        raise RequestAdmissionRejected(400, "invalid Content-Length") from exc
    if value < 0:
        raise RequestAdmissionRejected(400, "invalid Content-Length")
    return value


def validate_range_header(value: str | None) -> tuple[bool, str]:
    if not value:
        return True, ""
    if len(value.encode("latin-1", errors="replace")) > MAX_RANGE_HEADER_BYTES:
        return False, "range header too long"
    if not value.lower().startswith("bytes="):
        return False, "unsupported range unit"
    ranges = [part.strip() for part in value[6:].split(",")]
    if not ranges or len(ranges) > MAX_RANGE_COUNT or any(not _RANGE_RE.fullmatch(part) for part in ranges):
        return False, "malformed or excessive range set"
    return True, ""


async def _send_rejection(send: Callable[..., Awaitable[None]], status: int, reason: str) -> None:
    body = (reason + "\n").encode("utf-8")
    await send({"type": "http.response.start", "status": status, "headers": [(b"content-type", b"text/plain; charset=utf-8"), (b"content-length", str(len(body)).encode("ascii"))]})
    await send({"type": "http.response.body", "body": body})


async def _send_api_token_rejection(send: Callable[..., Awaitable[None]]) -> None:
    body = b'{"detail":"Invalid API token"}'
    await send({"type": "http.response.start", "status": 401, "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode("ascii"))]})
    await send({"type": "http.response.body", "body": body})


class RequestAdmissionMiddleware:
    """Reject bounded parser abuse before FastAPI dependency/form parsing."""

    def __init__(self, app: Callable[..., Awaitable[None]]) -> None:
        self.app = app

    async def __call__(self, scope: dict[str, Any], receive: Callable[..., Awaitable[dict[str, Any]]], send: Callable[..., Awaitable[None]]) -> None:
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return
        headers = _header_map(scope)
        started = time.perf_counter()
        header_bytes = sum(len(name) + len(value) for name, value in scope.get("headers", []))
        if len(scope.get("headers", [])) > MAX_HEADER_COUNT or header_bytes > MAX_HEADER_BYTES:
            _reject_reason(scope, "header budget exceeded", declared=None, observed=0, started=started)
            await _send_rejection(send, 431, "request headers exceed the bounded limit")
            return

        path = str(scope.get("path", ""))
        if path.startswith("/static"):
            valid, reason = validate_range_header(headers.get("range"))
            if not valid:
                _reject_reason(scope, reason, declared=None, observed=0, started=started)
                await _send_rejection(send, 416, "range request is not accepted")
                return

        method = str(scope.get("method", "")).upper()
        body_bearing = method in {"POST", "PUT", "PATCH"}
        is_api = path.startswith("/api/")
        if is_api and not api_token_valid(headers.get("x-devfleet-token")):
            _reject_reason(scope, "invalid API token", declared=None, observed=0, started=started)
            await _send_api_token_rejection(send)
            return

        is_login = path == "/login" and method == "POST"
        if is_login:
            limit = LOGIN_BODY_LIMIT
        elif body_bearing and is_api:
            limit = API_BODY_LIMIT
        elif body_bearing:
            limit = DEFAULT_BODY_LIMIT
        else:
            limit = None
        try:
            declared = _declared_length(headers)
        except RequestAdmissionRejected as exc:
            _reject_reason(scope, exc.reason, declared=None, observed=0, started=started)
            await _send_rejection(send, exc.status, exc.reason)
            return
        if is_login:
            content_type = headers.get("content-type", "").lower()
            if not (content_type.startswith("application/x-www-form-urlencoded") or content_type.startswith("multipart/form-data;")):
                _reject_reason(scope, "unsupported login content type", declared=declared, observed=0, started=started)
                await _send_rejection(send, 415, "login requires a bounded form content type")
                return
        if limit is not None and declared is not None and declared > limit:
            reason = "declared login body exceeds limit" if is_login else "declared request body exceeds limit"
            message = "login form body exceeds the bounded limit" if is_login else "request body exceeds the bounded limit"
            _reject_reason(scope, reason, declared=declared, observed=0, started=started)
            await _send_rejection(send, 413, message)
            return

        if limit is not None:
            # Read only the bounded body before invoking FastAPI.  The
            # buffer can never exceed `limit`; an over-limit chunk is rejected
            # without being retained, so parser work cannot start first and
            # turn the admission failure into a generic 400 response.
            buffered: list[dict[str, Any]] = []
            observed = 0
            while True:
                message = await receive()
                if message.get("type") != "http.request":
                    buffered.append(message)
                    break
                body = message.get("body", b"") or b""
                observed += len(body)
                if observed > limit:
                    reason = "observed login body exceeds limit" if is_login else "observed request body exceeds limit"
                    message = "login form body exceeds the bounded limit" if is_login else "request body exceeds the bounded limit"
                    _reject_reason(scope, reason, declared=declared, observed=observed, started=started)
                    await _send_rejection(send, 413, message)
                    return
                buffered.append(message)
                if not message.get("more_body", False):
                    break
            replay = iter(buffered)

            async def bounded_receive() -> dict[str, Any]:
                try:
                    return next(replay)
                except StopIteration:
                    return {"type": "http.disconnect"}

            await self.app(scope, bounded_receive, send)
            return

        await self.app(scope, receive, send)

```


## FILE: source/app/devfleet/resource_profiles.py

SHA256: 9bec3c14f6019fe4439065f8419dd7f11cc2de01ed9e9bd15bbbc5bf94102eb1 | Bytes: 14021 | Git mode: 100644

```
"""Central resource profiles and host-safe allocation policy."""
from __future__ import annotations

from dataclasses import asdict, dataclass
import json
from pathlib import Path
from typing import Any

import yaml

from .core import atomic_text


_RESOURCE_POLICY_DEFAULTS = {
    "schemaVersion": 1,
    "policyVersion": "1.0.0",
    "physicalFloorMinGiB": 8.0,
    "physicalFloorPercent": 0.10,
    "commitHeadroomFloorMinGiB": 16.0,
    "commitHeadroomPercent": 0.20,
    "commitUsageLimitPercent": 80.0,
}
_RESOURCE_POLICY_PATH = Path(__file__).resolve().parents[2] / "config" / "resource-policy.json"
try:
    _RESOURCE_POLICY = {**_RESOURCE_POLICY_DEFAULTS, **json.loads(_RESOURCE_POLICY_PATH.read_text(encoding="utf-8"))}
except (OSError, ValueError, TypeError):
    _RESOURCE_POLICY = dict(_RESOURCE_POLICY_DEFAULTS)
RESOURCE_POLICY_VERSION = str(_RESOURCE_POLICY["policyVersion"])


@dataclass(frozen=True)
class ResourceProfile:
    name: str
    label: str
    cpus: float
    memory: str
    disk_gb: int
    pids: int
    rationale: str

    @property
    def vcpus(self) -> float:
        return self.cpus

    @property
    def memory_gb(self) -> float:
        return float(str(self.memory).lower().replace("gb", "").replace("g", "").strip())

    def limits(self, runtime_type: str = "container") -> dict[str, Any]:
        result = {
            "cpus": self.cpus,
            "memory": self.memory,
            "memory_gb": self.memory_gb,
            "disk_gb": self.disk_gb,
            "pids": self.pids,
        }
        if runtime_type == "vm":
            result["vcpus"] = self.vcpus
        return result


@dataclass(frozen=True)
class HostResourcePolicy:
    # Legacy fields remain for config compatibility; adaptive admission below
    # is the authoritative host-memory rule and does not use fixed reserves.
    minimum_free_memory_gb: float = 0.0
    reserved_memory_gb: float = 0.0
    reserved_logical_processors: float = 2.0
    minimum_free_disk_gb: float = 50.0
    maximum_vm_count: int = 4
    maximum_parallel_provisioning: int = 1
    max_project_cpus: float = 6.0
    max_project_memory_gb: float = 12.0
    max_project_disk_gb: float = 120.0


@dataclass(frozen=True)
class AdaptiveHostThresholds:
    physical_floor_gb: float
    commit_headroom_floor_gb: float
    commit_usage_limit_percent: float = 80.0


def adaptive_host_thresholds(usable_physical_gb: float, commit_limit_gb: float) -> AdaptiveHostThresholds:
    """Return the versioned host-admission floors used by E2E and capacity UI."""
    usable = float(usable_physical_gb)
    commit_limit = float(commit_limit_gb)
    if usable < 0 or commit_limit < 0:
        raise ValueError("Host memory values must be non-negative.")
    return AdaptiveHostThresholds(
        physical_floor_gb=max(float(_RESOURCE_POLICY["physicalFloorMinGiB"]), usable * float(_RESOURCE_POLICY["physicalFloorPercent"])),
        commit_headroom_floor_gb=max(float(_RESOURCE_POLICY["commitHeadroomFloorMinGiB"]), commit_limit * float(_RESOURCE_POLICY["commitHeadroomPercent"])),
        commit_usage_limit_percent=float(_RESOURCE_POLICY["commitUsageLimitPercent"]),
    )


def evaluate_host_memory_admission(
    *,
    usable_physical_gb: float,
    available_physical_gb: float,
    commit_limit_gb: float,
    committed_gb: float,
    projected_allocation_gb: float,
    resource_exhaustion: bool = False,
) -> dict[str, Any]:
    thresholds = adaptive_host_thresholds(usable_physical_gb, commit_limit_gb)
    projected_available = float(available_physical_gb) - float(projected_allocation_gb)
    projected_headroom = float(commit_limit_gb) - float(committed_gb) - float(projected_allocation_gb)
    commit_percent = (float(committed_gb) / float(commit_limit_gb) * 100.0) if commit_limit_gb else 100.0
    return {
        "policy_version": RESOURCE_POLICY_VERSION,
        "physical_floor_gb": round(thresholds.physical_floor_gb, 2),
        "commit_headroom_floor_gb": round(thresholds.commit_headroom_floor_gb, 2),
        "projected_available_physical_gb": round(projected_available, 2),
        "projected_commit_headroom_gb": round(projected_headroom, 2),
        "current_commit_usage_percent": round(commit_percent, 2),
        "resource_exhaustion": bool(resource_exhaustion),
        "start_safe": bool(
            projected_available >= thresholds.physical_floor_gb
            and projected_headroom >= thresholds.commit_headroom_floor_gb
            and commit_percent < thresholds.commit_usage_limit_percent
            and not resource_exhaustion
        ),
    }


def resolved_resource_metadata(
    profile_name: str,
    runtime_type: str = "container",
    *,
    actual_runtime_resources: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Keep requested profile, resolved limits, and observed runtime separate."""
    if profile_name == "custom":
        requested = dict(actual_runtime_resources or {})
    else:
        requested = resource_metadata(profile_name, runtime_type)
    resolved = dict(requested)
    actual = dict(actual_runtime_resources or {})
    drift = {
        key: {"expected": resolved.get(key), "actual": actual.get(key)}
        for key in ("cpus", "memory_gb", "disk_gb")
        if key in actual and str(actual.get(key)) != str(resolved.get(key))
    }
    return {
        "policy_version": RESOURCE_POLICY_VERSION,
        "requested_profile": profile_name,
        "requested_limits": requested,
        "resolved_resources": resolved,
        "actual_runtime_resources": actual,
        "resource_drift": drift,
        "resource_drift_status": "RESOURCE DRIFT" if drift else "MATCH",
    }


RESOURCE_PROFILES = {
    "small": ResourceProfile("small", "Light", 1.0, "2g", 20, 512, "Lightweight prototype or automation workload."),
    "standard": ResourceProfile("standard", "Standard", 2.0, "4g", 40, 768, "Normal web, API, CLI, or service development."),
    "large": ResourceProfile("large", "Performance", 4.0, "8g", 80, 1536, "Multi-service, production-like, or data-heavy development."),
    "xlarge": ResourceProfile("xlarge", "Intensive", 6.0, "12g", 120, 2048, "Heavy build or infrastructure workload; still GPU-free."),
}

RUNTIME_ISOLATIONS = {
    "container": "Project-isolated containers on the shared DevFleet host",
    "vm": "Dedicated Multipass VM (host-assisted provisioning; no GPU path)",
}

LAPTOP_PROFILE_DEFAULT = {"failover_memory_gb": 5.0, "vault_memory_gb": 2.0}
LAPTOP_PROFILE_MINIMUM_TESTED = {"failover_memory_gb": 4.0, "vault_memory_gb": 2.0}


def laptop_surrogate_profile(*, failover_memory_gb: float = 5.0, vault_memory_gb: float = 2.0) -> dict[str, float]:
    """Return the conservative tested Laptop/Surrogate memory profile."""
    failover = float(failover_memory_gb)
    vault = float(vault_memory_gb)
    if failover < LAPTOP_PROFILE_MINIMUM_TESTED["failover_memory_gb"] or vault < LAPTOP_PROFILE_MINIMUM_TESTED["vault_memory_gb"]:
        raise ValueError("Laptop/Surrogate memory is below the lowest tested stable profile.")
    return {"failover_memory_gb": failover, "vault_memory_gb": vault}


def policy_from_config(values: dict[str, Any] | None = None) -> HostResourcePolicy:
    values = values or {}
    aliases = {
        "minimum_free_memory": "minimum_free_memory_gb",
        "reserved_memory": "reserved_memory_gb",
        "reserved_logical_processors": "reserved_logical_processors",
        "minimum_free_disk": "minimum_free_disk_gb",
        "max_vm_count": "maximum_vm_count",
        "maximum_vm_count": "maximum_vm_count",
        "max_parallel_provisioning": "maximum_parallel_provisioning",
    }
    normalized = {aliases.get(k, k): v for k, v in values.items()}
    defaults = asdict(HostResourcePolicy())
    for key, default in defaults.items():
        if key in normalized:
            try:
                defaults[key] = type(default)(normalized[key])
            except (TypeError, ValueError):
                raise ValueError(f"Invalid host resource policy value: {key}")
    return HostResourcePolicy(**defaults)


def get_resource_profile(name: str) -> ResourceProfile:
    key = str(name or "").strip().lower()
    if key not in RESOURCE_PROFILES:
        raise ValueError(f"Unknown resource profile: {key}")
    return RESOURCE_PROFILES[key]


def custom_resource_metadata(values: dict[str, Any], *, runtime_type: str = "container") -> dict[str, Any]:
    """Validate dashboard-supplied limits without allowing privileged PID mode."""
    if str(values.get("pid_mode", "private") or "private").lower() != "private":
        raise ValueError("Host PID namespace is not supported by the safe DevFleet runtime policy.")
    return validate_resource_limits(values, runtime_type=runtime_type)


def validate_resource_limits(values: dict[str, Any], *, runtime_type: str = "container", policy: HostResourcePolicy | None = None) -> dict[str, Any]:
    policy = policy or HostResourcePolicy()
    try:
        cpus = float(values.get("cpus", values.get("vcpus")))
        memory_gb = float(values.get("memory_gb", str(values.get("memory", "")).lower().replace("gb", "").replace("g", "")))
        disk_gb = int(values.get("disk_gb"))
        pids = int(values.get("pids", 0))
    except (TypeError, ValueError):
        raise ValueError("Resource limits must contain numeric CPU, memory, disk, and PID values.")
    if cpus < 1 or cpus > policy.max_project_cpus:
        raise ValueError("CPU allocation is outside the host-agent policy.")
    if memory_gb < 2 or memory_gb > policy.max_project_memory_gb:
        raise ValueError("Memory allocation is outside the host-agent policy.")
    if disk_gb < 20 or disk_gb > policy.max_project_disk_gb:
        raise ValueError("Disk allocation is outside the host-agent policy.")
    if pids < 0 or pids > 4096:
        raise ValueError("PID limit is outside the host-agent policy.")
    return {
        "cpus": cpus,
        "vcpus": cpus,
        "memory_gb": memory_gb,
        "memory": f"{int(memory_gb) if memory_gb.is_integer() else memory_gb:g}g",
        "disk_gb": disk_gb,
        "pids": pids,
        "runtime_type": runtime_type,
    }


def capacity_allows(capacity: dict[str, Any], limits: dict[str, Any]) -> tuple[bool, str]:
    checks = (
        ("allocatable_cpus", float(limits.get("cpus", limits.get("vcpus", 0))), "CPU"),
        ("allocatable_memory_gb", float(limits.get("memory_gb", 0)), "memory"),
        ("allocatable_disk_gb", float(limits.get("disk_gb", 0)), "disk"),
    )
    for key, requested, label in checks:
        available = float(capacity.get(key, 0) or 0)
        if requested > available:
            return False, f"Host capacity is below the safe threshold for {label}: requested {requested:g}, available {available:g}."
    return True, "Host capacity is sufficient."


def recommend_resource_profile(*, scale: str = "", intent: str = "", project_kind: str = "", language: str = "", framework: str = "") -> ResourceProfile:
    scale = str(scale or "").lower()
    intent = str(intent or "").lower()
    kind = str(project_kind or "").lower()
    language = str(language or "").lower()
    framework = str(framework or "").lower()
    if scale == "large" or kind in {"infrastructure-service", "full-stack-web"} or "data" in kind or "spark" in framework:
        return RESOURCE_PROFILES["large"]
    if intent == "production" and (kind in {"web-frontend", "rapid-api", "full-stack-web"} or framework in {"next.js", "spring", "spring-boot", "fastapi"}):
        return RESOURCE_PROFILES["large"]
    if scale == "medium" or intent == "production" or language in {"java", "csharp", "c++", "cpp", "rust"}:
        return RESOURCE_PROFILES["standard"]
    return RESOURCE_PROFILES["small"]


def recommend_runtime_isolation(*, scale: str = "", intent: str = "", project_kind: str = "") -> str:
    if str(scale or "").lower() == "large" and str(intent or "").lower() == "production":
        return "vm"
    if str(project_kind or "").lower() == "infrastructure-service":
        return "vm"
    return "container"


def resource_metadata(name: str, runtime_type: str = "container") -> dict[str, Any]:
    profile = get_resource_profile(name)
    return {**asdict(profile), **profile.limits(runtime_type)}


def resource_override_path(project: Path) -> Path:
    return project / ".devfleet" / "runtime-resources.yaml"


def ownership_override_path(project: Path) -> Path:
    return project / ".devfleet" / "runtime-ownership.yaml"


def write_ownership_override(project: Path, compose_file: Path, labels: dict[str, str]) -> Path | None:
    try:
        document = yaml.safe_load(compose_file.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        return None
    services = document.get("services") if isinstance(document, dict) else None
    if not isinstance(services, dict) or not services:
        return None
    override = {"services": {str(service): {"labels": dict(labels)} for service in services}}
    destination = ownership_override_path(project)
    atomic_text(destination, yaml.safe_dump(override, sort_keys=False))
    return destination


def write_resource_override(project: Path, compose_file: Path, profile_name: str | dict[str, Any]) -> Path | None:
    if isinstance(profile_name, dict):
        limits = custom_resource_metadata(profile_name, runtime_type="container")
    else:
        limits = get_resource_profile(profile_name).limits("container")
    try:
        document = yaml.safe_load(compose_file.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        return None
    services = document.get("services") if isinstance(document, dict) else None
    if not isinstance(services, dict) or not services:
        return None
    override = {"services": {str(service): {"cpus": limits["cpus"], "mem_limit": limits["memory"], "pids_limit": limits["pids"]} for service in services}}
    destination = resource_override_path(project)
    atomic_text(destination, yaml.safe_dump(override, sort_keys=False))
    return destination

```


## FILE: source/app/devfleet/runtim