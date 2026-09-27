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
