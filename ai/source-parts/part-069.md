# DevFleet source part 069

Full-source UTF-8 byte interval [3162000, 3208500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 11523939fba91dc22c46cabf2ebe0310915a422d4d1ce0f0987331a89fcd4d4e

<!-- BEGIN SOURCE SLICE -->
 not found.")


@app.post("/api/projects/{slug}/environment", dependencies=[Depends(check_api)])
def api_project_environment_assign(slug: str, payload: dict | None = None):
    payload = payload or {}
    if not payload.get("wizard_confirmed"):
        raise HTTPException(400, "Final wizard confirmation is required.")
    _require_owned_project_for_mutation(slug, allow_legacy_migration=True)
    runtime_isolation = str(payload.get("runtime_isolation") or "container")
    resource_profile = str(payload.get("resource_profile") or "")
    resource_limits = (
        payload.get("resource_limits")
        if isinstance(payload.get("resource_limits"), dict)
        else None
    )
    selected = resource_limits or {}
    preflight = _preflight(
        slug,
        runtime_isolation,
        resource_profile,
        str(selected.get("cpus", "")),
        str(selected.get("memory_gb", "")),
        str(selected.get("disk_gb", "")),
        str(selected.get("pid_mode", "private")),
        str(selected.get("pids", "4096")),
    )
    if not preflight["migration_ready"]:
        raise HTTPException(
            409,
            "Environment preflight is not ready: " + "; ".join(preflight["blockers"]),
        )
    op = submit_operation(
        "runtime-adoption",
        slug,
        lambda ctx: assign_project_runtime(
            slug,
            runtime_isolation,
            resource_profile,
            resource_limits,
            operation_context=ctx,
        ),
        idempotency_key=f'runtime-adoption:{slug}:{runtime_isolation}:{resource_profile or "current"}',
    )
    return JSONResponse(
        {"ok": True, "operation_id": op, "message": "Environment assignment queued."},
        status_code=202,
    )


@app.post("/api/projects/create", dependencies=[Depends(check_api)])
def api_create(payload: dict):
    defaults = {
        "slug": "", "display_name": "", "template": "generic", "git_url": "",
        "language": "", "framework": "", "scale": "small", "intent": "prototype",
        "testing_level": "standard", "profile": "", "resource_profile": "",
        "resource_limits": None, "runtime_isolation": "", "use_ollama": True,
        "worktree_source": "", "worktree_branch": "", "project_kind": "",
    }
    values = {key: payload.get(key, default) for key, default in defaults.items()}
    slug = validate_slug(str(values["slug"]))
    supplied = str(payload.get("idempotency_key") or "").strip()
    if supplied and not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", supplied):
        raise HTTPException(400, "Idempotency key must be 1-128 safe identifier characters.")

    def task(ctx):
        return create_project(**values, operation_context=ctx)

    operation_id = submit_operation("create", slug, task, idempotency_key=f"project-create:{slug}:{supplied or 'default'}")
    return JSONResponse({"ok": True, "accepted": True, "operation_id": operation_id, "operation_url": f"/api/operations/{operation_id}"}, status_code=202)


@app.post("/api/transfers/receive", dependencies=[Depends(check_api)])
def api_receive_transfer(payload: dict):
    try:
        slug = validate_slug(str(payload.get("slug") or ""))
        project_id = validate_project_id(str(payload.get("project_id") or ""))
        deployment_id = validate_project_id(
            str(payload.get("deployment_id") or "")
        )
    except ValueError as exc:
        raise HTTPException(400, "Transfer identity is invalid.") from exc
    source_host_id = str(payload.get("source_host_id") or "")
    destination_host_id = str(payload.get("destination_host_id") or "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", source_host_id):
        raise HTTPException(400, "Transfer source host identity is invalid.")
    if destination_host_id != SETTINGS.host_id:
        raise HTTPException(409, "Transfer destination host identity does not match this node.")
    if deployment_id != str(SETTINGS.deployment_id or ""):
        raise HTTPException(409, "Transfer deployment identity does not match this node.")
    if (
        str(payload.get("confirm_slug") or "") != slug
        or str(payload.get("confirm_phrase") or "") != f"RECEIVE TRANSFER {slug}"
    ):
        raise HTTPException(400, "Receive transfer requires exact confirmation.")

    def task(ctx):
        ctx.update(10, "Validating transfer destination ownership")
        result = receive_transferred_project(
            slug,
            project_id,
            deployment_id,
            source_host_id,
            destination_host_id,
        )
        ctx.update(90, "Transfer restored and rebound to this node")
        return result

    operation_id = submit_operation(
        "receive-transfer",
        slug,
        task,
        project_id=project_id,
        idempotency_key=(
            f"receive-transfer:{slug}:{project_id}:{deployment_id}:"
            f"{source_host_id}:{destination_host_id}"
        ),
        host_id=SETTINGS.host_id,
    )
    return JSONResponse(
        {
            "ok": True,
            "accepted": True,
            "operation_id": operation_id,
            "operation_url": f"/api/operations/{operation_id}",
        },
        status_code=202,
    )


@app.post("/api/transfers/activate", dependencies=[Depends(check_api)])
def api_activate_transfer(payload: dict):
    try:
        slug = validate_slug(str(payload.get("slug") or ""))
        project_id = validate_project_id(str(payload.get("project_id") or ""))
        deployment_id = validate_project_id(
            str(payload.get("deployment_id") or "")
        )
    except ValueError as exc:
        raise HTTPException(400, "Transfer identity is invalid.") from exc
    source_host_id = str(payload.get("source_host_id") or "")
    destination_host_id = str(payload.get("destination_host_id") or "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", source_host_id):
        raise HTTPException(400, "Transfer source host identity is invalid.")
    if destination_host_id != SETTINGS.host_id or source_host_id == destination_host_id:
        raise HTTPException(
            409, "Transfer destination host identity does not match this node."
        )
    if deployment_id != str(SETTINGS.deployment_id or ""):
        raise HTTPException(409, "Transfer deployment identity does not match this node.")
    if (
        str(payload.get("confirm_slug") or "") != slug
        or str(payload.get("confirm_phrase") or "")
        != f"ACTIVATE TRANSFER {slug}"
    ):
        raise HTTPException(400, "Transfer activation requires exact confirmation.")

    def task(ctx):
        ctx.update(10, "Validating pending transfer authority")
        result = activate_transferred_project(
            slug,
            project_id,
            deployment_id,
            source_host_id,
            destination_host_id,
        )
        ctx.update(95, "Transfer activated and project started")
        return result

    operation_id = submit_operation(
        "activate-transfer",
        slug,
        task,
        project_id=project_id,
        idempotency_key=(
            f"activate-transfer:{slug}:{project_id}:{deployment_id}:"
            f"{source_host_id}:{destination_host_id}"
        ),
        host_id=SETTINGS.host_id,
    )
    return JSONResponse(
        {
            "ok": True,
            "accepted": True,
            "operation_id": operation_id,
            "operation_url": f"/api/operations/{operation_id}",
        },
        status_code=202,
    )


@app.post("/api/projects/{slug}/{action}", dependencies=[Depends(check_api)])
def api_action(request: Request, slug: str, action: str, payload: dict | None = None):
    payload = payload or {}
    if action not in PROJECT_ACTIONS:
        raise HTTPException(404, "Unknown action")
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir() or project.is_symlink():
        raise HTTPException(404, "Project not found.")
    metadata = _require_owned_project_for_mutation(slug)
    capabilities = project_capabilities(slug, metadata)
    if (
        action
        in {
            "restart",
            "runtime-health",
            "bootstrap",
            "health",
            "test",
            "codexpro",
            "logs",
        }
        and not capabilities["can_run_runtime_action"]
    ):
        raise HTTPException(
            409,
            f"Runtime action unavailable: {capabilities['status_reason'] or 'environment is not ready.'}",
        )
    if action == "quarantine" and not payload.get("confirm_quarantine"):
        raise HTTPException(400, "Quarantine requires explicit acknowledgement.")
    if action == "destroy" and (
        payload.get("confirm_slug") != slug
        or payload.get("confirm_phrase") != f"DESTROY {slug}"
    ):
        raise HTTPException(400, "Permanent destruction requires exact confirmation.")
    if action == "restore-backup" and (not payload.get("confirm_restore") or not payload.get("backup_id")):
        raise HTTPException(400, "Backup restore requires an identified backup and explicit confirmation.")
    if action == "restore-vault":
        try:
            canonical = _canonical_restore_requested(payload)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        payload["canonical"] = canonical
        if canonical and (
            str(payload.get("confirm_slug") or "") != slug
            or str(payload.get("confirm_phrase") or "")
            != f"RESTORE CANONICAL {slug}"
        ):
            raise HTTPException(
                400, "Canonical Vault restore requires exact confirmation."
            )
        if canonical:
            raise HTTPException(
                409,
                "Standalone canonical Vault restore is disabled; use restore-copy or guided ownership transfer.",
            )
    task = _project_action_task(slug, action, payload)
    if action in PROJECT_READ_ONLY_ACTIONS:
        return {"ok": True, "output": task(None)}
    idempotency_key = _action_idempotency_key(slug, action, payload, request.headers.get("X-Idempotency-Key", ""))
    operation_id = submit_operation(
        action,
        slug,
        task,
        project_id=str(metadata.get("project_id") or ""),
        runtime_id=str(metadata.get("runtime_id") or ""),
        idempotency_key=idempotency_key,
        host_id=str(metadata.get("host_id") or SETTINGS.host_id),
    )
    return JSONResponse({"ok": True, "accepted": True, "operation_id": operation_id, "operation_url": f"/api/operations/{operation_id}"}, status_code=202)

```


## FILE: source/app/devfleet/metadata_io.py

SHA256: 188ee5ed02c51d802e85cfa75a1017e9fc2c5a897a51083ba4a09bd564afd290 | Bytes: 22797 | Git mode: 100644

```
"""Read and replace project metadata through a stable filesystem identity.

Linux is the deployed target. Its directory-relative, no-follow operations are
the authoritative contract. Windows compatibility pins directories against
rename with native handles, but is not evidence of the POSIX security contract.
This module intentionally has no application settings or third-party imports.
"""
from __future__ import annotations

import contextlib
import json
import os
from pathlib import Path
import re
import stat
import sys
from dataclasses import dataclass
from typing import Any
import uuid


# Compute this before tests wrap os.open to inject deterministic substitutions.
POSIX_FD_HARDENING = (
    os.name == "posix"
    and all(hasattr(os, flag) for flag in ("O_DIRECTORY", "O_NOFOLLOW", "O_NONBLOCK"))
    and all(fn in os.supports_dir_fd for fn in (os.open, os.stat, os.mkdir, os.unlink, os.rename, os.link))
    and os.stat in os.supports_follow_symlinks
)
_Identity = tuple[int, int, int]
_Version = tuple[int, int, int, int, int, int, int]


class MetadataSafetyError(ValueError):
    """The observed metadata object no longer has its authorized identity."""


@dataclass(frozen=True)
class MetadataBinding:
    workspace: str
    directory_lineage: tuple[tuple[str, _Identity], ...]
    file_identity: _Identity | None
    file_version: _Version | None
    posix: bool

    def same_directory_lineage(self, other: MetadataBinding) -> bool:
        return (
            isinstance(other, MetadataBinding)
            and self.workspace == other.workspace
            and self.directory_lineage == other.directory_lineage
            and self.posix == other.posix
        )


@dataclass(frozen=True)
class MetadataRecord:
    value: Any
    raw: bytes
    binding: MetadataBinding


def enable_inherited_backup_read(fd: int, *, parent: Path | int, directory: bool = False) -> None:
    """Retain only an already-inherited backup grant on a newly created inode.

    Creating atomic files as 0600 (or metadata directories as 0700) masks named
    default ACL entries. Reactivate read/traverse for the configured backup UID,
    not write, while preserving every other principal's previous effective access.
    No ACL or no backup grant means the object remains private. Call only on the
    pinned descriptor of an unpublished file or a directory just created here.
    """
    if sys.platform != "linux":
        return
    import errno
    import pwd
    import struct

    try:
        backup_uid = pwd.getpwnam("devfleet-backup").pw_uid
    except KeyError:
        return
    try:
        raw = os.getxattr(fd, "system.posix_acl_access")
        # Ancestors are deliberately pinned with O_PATH (traverse-only), which
        # fgetxattr rejects. The kernel's /proc/self/fd link retains that exact
        # live directory identity without reopening an attacker-controlled path.
        policy_target = f"/proc/self/fd/{parent}" if isinstance(parent, int) else parent
        policy = os.getxattr(policy_target, "system.posix_acl_default")
    except OSError as exc:
        if exc.errno in (errno.ENODATA, errno.ENOTSUP, errno.EOPNOTSUPP):
            return
        raise
    if len(raw) < 4 or (len(raw) - 4) % 8 or struct.unpack("<I", raw[:4])[0] != 2:
        raise MetadataSafetyError("Inherited metadata ACL has an unsupported format.")
    entries = list(struct.iter_unpack("<HHI", raw[4:]))
    masks = [permissions for tag, permissions, _uid in entries if tag == 0x10]
    grants = [permissions for tag, permissions, uid in entries
              if tag == 0x02 and uid == backup_uid]
    if not grants:
        return
    if len(masks) != 1 or len(grants) != 1 or any(permissions & ~7 for _, permissions, _ in entries):
        raise MetadataSafetyError("Inherited metadata ACL is ambiguous.")
    needed = 0x05 if directory else 0x04
    if grants[0] & needed != needed:
        return
    # The parent's mask may itself deliberately deny an otherwise named grant.
    # A raw inherited entry alone is not authorization to override that denial.
    if len(policy) < 4 or (len(policy) - 4) % 8 or struct.unpack("<I", policy[:4])[0] != 2:
        raise MetadataSafetyError("Default metadata ACL has an unsupported format.")
    parent_entries = list(struct.iter_unpack("<HHI", policy[4:]))
    parent_masks = [permissions for tag, permissions, _uid in parent_entries if tag == 0x10]
    parent_grants = [permissions for tag, permissions, uid in parent_entries
                     if tag == 0x02 and uid == backup_uid]
    if not parent_grants:
        return
    if len(parent_masks) != 1 or len(parent_grants) != 1:
        raise MetadataSafetyError("Default metadata ACL is ambiguous.")
    if (parent_grants[0] & parent_masks[0] & needed) != needed:
        return
    mask = masks[0]
    owner = os.fstat(fd)
    owner_permissions = stat.S_IMODE(owner.st_mode) >> 6
    # A named ACL entry for the inode's own publisher is not an unrelated
    # principal: it already has the owner rights. Preserve its explicitly
    # inherited grant so non-root restore does not erase publisher access when
    # the restoring account becomes the inode owner. Parent policy still limits
    # that grant; no other masked principal is reactivated.
    publisher_access = next((permissions & owner_permissions & parent_masks[0]
                             for tag, permissions, uid in parent_entries
                             if tag == 0x02 and uid == owner.st_uid), 0)
    updated = []
    for tag, permissions, uid in entries:
        if tag == 0x02 and uid == backup_uid:
            permissions = needed
        elif tag == 0x02 and uid == owner.st_uid:
            permissions &= publisher_access
        elif tag in (0x02, 0x04, 0x08):
            # Widening the shared ACL mask must not revive another named user,
            # the owning group, or a named group that mode 0600/0700 had denied.
            permissions &= mask
        elif tag == 0x10:
            permissions = mask | needed | publisher_access
        updated.append((tag, permissions, uid))
    encoded = struct.pack("<I", 2) + b"".join(struct.pack("<HHI", *entry) for entry in updated)
    os.setxattr(fd, "system.posix_acl_access", encoded)


def _identity(info: os.stat_result) -> _Identity:
    return int(info.st_dev), int(info.st_ino), stat.S_IFMT(info.st_mode)


def _version(info: os.stat_result) -> _Version:
    return (*_identity(info), int(info.st_nlink), int(info.st_size),
            int(info.st_mtime_ns), int(info.st_ctime_ns))


def _require_kind(info: os.stat_result, kind: int) -> None:
    if (
        stat.S_IFMT(info.st_mode) != kind
        or getattr(info, "st_file_attributes", 0) & 0x400  # Windows reparse point.
    ):
        raise MetadataSafetyError("Metadata path contains an alias or an unsupported object.")
    if kind == stat.S_IFREG and info.st_nlink != 1:
        raise MetadataSafetyError("Metadata file has an unexpected hard-link count.")


def _lexical_workspace(project: Path) -> Path:
    project = Path(project)
    if ".." in project.parts:
        raise MetadataSafetyError("Metadata workspace may not contain parent traversal.")
    return Path(os.path.abspath(os.fspath(project)))


def _pin_windows_directory(path: Path):
    """Deny directory rename/deletion while compatibility I/O uses its pathname."""
    import ctypes
    from ctypes import wintypes

    class FileInformation(ctypes.Structure):
        _fields_ = [
            ("attributes", wintypes.DWORD),
            ("creation", wintypes.FILETIME),
            ("access", wintypes.FILETIME),
            ("write", wintypes.FILETIME),
            ("volume", wintypes.DWORD),
            ("size_high", wintypes.DWORD),
            ("size_low", wintypes.DWORD),
            ("links", wintypes.DWORD),
            ("index_high", wintypes.DWORD),
            ("index_low", wintypes.DWORD),
        ]

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                  wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD,
                                  wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.GetFileInformationByHandle.argtypes = [wintypes.HANDLE, ctypes.POINTER(FileInformation)]
    kernel.GetFileInformationByHandle.restype = wintypes.BOOL
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.restype = wintypes.BOOL
    # FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES; share read/write, deliberately
    # omit FILE_SHARE_DELETE. Attribute-only handles do not enforce that denial.
    # OPEN_EXISTING; BACKUP_SEMANTICS | OPEN_REPARSE_POINT.
    handle = kernel.CreateFileW(str(path), 0x81, 0x3, None, 3, 0x02200000, None)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        info = FileInformation()
        if not kernel.GetFileInformationByHandle(handle, ctypes.byref(info)):
            raise ctypes.WinError(ctypes.get_last_error())
        if not info.attributes & 0x10 or info.attributes & 0x400:
            raise MetadataSafetyError("Metadata parent is not a real directory.")
    except BaseException:
        kernel.CloseHandle(handle)
        raise
    return lambda: kernel.CloseHandle(handle)


class _MetadataLocation:
    def __init__(self, project: Path, *, create_directory: bool = False):
        self.project = _lexical_workspace(project)
        self.directory = self.project / ".devfleet"
        self._create_directory = create_directory
        self._edges: list[tuple[Path, int | None, str, int | None, _Identity]] = []
        self._windows_closers: list[Any] = []

    def __enter__(self):
        if not POSIX_FD_HARDENING and os.name != "nt":
            raise MetadataSafetyError("Required descriptor-relative metadata primitives are unavailable.")
        try:
            parent_fd = None
            current = Path(self.directory.anchor)
            for index, name in enumerate(self.directory.parts):
                created_here = False
                current = Path(name) if index == 0 else current / name
                try:
                    observed = self._stat_directory(current, parent_fd, name)
                except FileNotFoundError:
                    if not self._create_directory or current != self.directory:
                        raise
                    try:
                        if POSIX_FD_HARDENING:
                            os.mkdir(name, 0o700, dir_fd=parent_fd)
                        else:
                            current.mkdir(mode=0o700)
                        created_here = True
                    except FileExistsError:
                        pass
                    observed = self._stat_directory(current, parent_fd, name)
                _require_kind(observed, stat.S_IFDIR)
                if POSIX_FD_HARDENING:
                    # The backup identity may only traverse ancestors such as
                    # /home/devrunner. O_PATH pins those without requiring list
                    # permission; the metadata directory remains fsync-capable.
                    access = os.O_RDONLY if current == self.directory else getattr(os, "O_PATH", os.O_RDONLY)
                    flags = access | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
                    fd = os.open(name if parent_fd is not None else current, flags, dir_fd=parent_fd)
                    self._edges.append((current, parent_fd, name, fd, _identity(observed)))
                    actual = os.fstat(fd)
                    _require_kind(actual, stat.S_IFDIR)
                    if _identity(actual) != _identity(observed):
                        raise MetadataSafetyError("Metadata directory changed before it could be opened.")
                    if created_here:
                        enable_inherited_backup_read(fd, parent=parent_fd, directory=True)
                    parent_fd = fd
                else:
                    closer = _pin_windows_directory(current)
                    self._windows_closers.append(closer)
                    actual = os.lstat(current)
                    _require_kind(actual, stat.S_IFDIR)
                    if _identity(actual) != _identity(observed):
                        raise MetadataSafetyError("Metadata directory changed before it could be pinned.")
                    self._edges.append((current, None, name, None, _identity(actual)))
            self.assert_directories()
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_args):
        for _path, _parent, _name, fd, _expected in reversed(self._edges):
            if fd is not None:
                os.close(fd)
        self._edges.clear()
        for closer in reversed(self._windows_closers):
            closer()
        self._windows_closers.clear()

    @staticmethod
    def _stat_directory(path: Path, parent_fd: int | None, name: str):
        return (os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
                if parent_fd is not None else os.lstat(path))

    @property
    def directory_fd(self) -> int | None:
        return self._edges[-1][3]

    def assert_directories(self) -> None:
        for path, parent_fd, name, fd, expected in self._edges:
            current = self._stat_directory(path, parent_fd, name)
            _require_kind(current, stat.S_IFDIR)
            if _identity(current) != expected or (fd is not None and _identity(os.fstat(fd)) != expected):
                raise MetadataSafetyError("Metadata directory binding changed during the operation.")

    def stat_file(self, name: str = "project.json") -> os.stat_result:
        return (os.stat(name, dir_fd=self.directory_fd, follow_symlinks=False)
                if POSIX_FD_HARDENING else os.lstat(self.directory / name))

    def binding(self, file_info: os.stat_result | None) -> MetadataBinding:
        return MetadataBinding(
            os.path.normcase(str(self.project)),
            tuple((os.path.normcase(str(path)), expected) for path, _parent, _name, _fd, expected in self._edges),
            _identity(file_info) if file_info is not None else None,
            _version(file_info) if file_info is not None else None,
            POSIX_FD_HARDENING,
        )

    def assert_binding(self, expected: MetadataBinding) -> None:
        self.assert_directories()
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
            if (data.get("state") == "queued" and _queued_expired(data)) or (data.get("state") == "running" and _lease_expired(data.get(