"""Real Linux ACL regression: atomic metadata remains readable only by its backup identity."""
from __future__ import annotations
import errno
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
from types import SimpleNamespace

import pytest
from devfleet import core, metadata_io

BACKUP_UID = 60002
OTHER_UID = 60003
ACL_ACCESS = 'system.posix_acl_access'
ACL_DEFAULT = 'system.posix_acl_default'


def pack_acl(entries):
    return struct.pack('<I', 2) + b''.join(struct.pack('<HHI', *entry) for entry in entries)


def entries(raw):
    assert struct.unpack('<I', raw[:4]) == (2,)
    return list(struct.iter_unpack('<HHI', raw[4:]))


@pytest.fixture
def acl_workspace(monkeypatch):
    if sys.platform != 'linux' or not hasattr(os, 'geteuid') or os.geteuid() != 0:
        pytest.skip('Real different-UID ACL checks require Linux root in the isolated test environment')
    import pwd
    real_lookup = pwd.getpwnam
    monkeypatch.setattr(pwd, 'getpwnam', lambda name: SimpleNamespace(pw_uid=BACKUP_UID)
                        if name == 'devfleet-backup' else real_lookup(name))
    with tempfile.TemporaryDirectory(prefix='devfleet-acl-test-') as root:
        parent = Path(root)
        parent.chmod(0o755)
        workspace = parent / 'demo'
        workspace.mkdir()
        policy = pack_acl([(1,7,0xFFFFFFFF),(2,7,BACKUP_UID),(2,7,OTHER_UID),
                           (4,0,0xFFFFFFFF),(16,7,0xFFFFFFFF),(32,0,0xFFFFFFFF)])
        try:
            os.setxattr(workspace, ACL_ACCESS, policy)
            os.setxattr(workspace, ACL_DEFAULT, policy)
        except OSError as exc:
            if exc.errno in (errno.ENOTSUP, errno.EOPNOTSUPP):
                pytest.skip('Test filesystem does not support POSIX ACLs')
            raise
        yield workspace


def access_as(path, *, uid=BACKUP_UID, write=False):
    code = ('from pathlib import Path; import sys; '
            "p=Path(sys.argv[1]); " +
            ("f=p.open('ab'); f.close()" if write else 'p.read_bytes()'))
    result = subprocess.run([sys.executable, '-I', '-c', code, str(path)],
                            user=uid, group=uid, extra_groups=[], capture_output=True,
                            timeout=10, text=True)
    return result.returncode == 0


def assert_backup_only(path):
    assert access_as(path), 'The configured backup identity cannot read newly published metadata'
    assert not access_as(path, write=True), 'The backup identity must not write authoritative metadata'
    assert not access_as(path, uid=OTHER_UID), 'Enabling backup read must not unmask another inherited principal'
    assert path.stat().st_mode & 0o007 == 0, 'Metadata must not become world-accessible'


def test_metadata_create_and_replace_keep_backup_read_access(acl_workspace):
    p = acl_workspace
    binding = metadata_io.write_project_metadata(p, {'test': 'initial'}, create=True)
    assert_backup_only(p / '.devfleet/project.json')
    binding = metadata_io.write_project_metadata(p, {'test': 'replacement'}, expected=binding)
    assert_backup_only(p / '.devfleet/project.json')
    assert metadata_io.read_project_metadata(p).value == {'test': 'replacement'}


@pytest.mark.parametrize('writer,value', [(core.atomic_text, 'lease'), (core.atomic_bytes, b'lease'),
                                         (core.atomic_json, {'lease': 'closed'})])
def test_atomic_workspace_writes_keep_backup_read_access(acl_workspace, writer, value):
    path = acl_workspace / 'ownership-lease.json'
    writer(path, value)
    assert_backup_only(path)
    writer(path, value)
    assert_backup_only(path)


def test_paths_without_backup_acl_remain_private(tmp_path):
    path = tmp_path / 'private.json'
    core.atomic_json(path, {'private': True})
    if os.name == 'posix':
        assert path.stat().st_mode & 0o077 == 0


def test_metadata_replacement_does_not_reintroduce_a_removed_acl(acl_workspace):
    p = acl_workspace
    binding = metadata_io.write_project_metadata(p, {'test': 'initial'}, create=True)
    directory = p / '.devfleet'
    os.removexattr(directory, ACL_DEFAULT)
    binding = metadata_io.write_project_metadata(p, {'test': 'replacement'}, expected=binding)
    assert not access_as(directory / 'project.json')
    assert (directory / 'project.json').stat().st_mode & 0o077 == 0


def test_default_acl_mask_denial_is_not_overridden(acl_workspace):
    p = acl_workspace
    acl = entries(os.getxattr(p, ACL_DEFAULT))
    os.setxattr(p, ACL_DEFAULT, pack_acl([(t, 0 if t == 16 else v, u) for t,v,u in acl]))
    target = p / 'denied-by-parent.json'
    core.atomic_json(target, {'private': True})
    assert not access_as(target), 'An explicitly masked parent backup grant is not permission to read'
    assert target.stat().st_mode & 0o077 == 0


def test_failed_acl_application_does_not_replace_committed_metadata(acl_workspace, monkeypatch):
    p = acl_workspace
    binding = metadata_io.write_project_metadata(p, {'original': True}, create=True)
    previous = (p / '.devfleet/project.json').read_bytes()
    def deny(*args, **kwargs):
        raise OSError(errno.EACCES, 'synthetic ACL write refusal')
    monkeypatch.setattr(metadata_io.os, 'setxattr', deny)
    with pytest.raises(OSError):
        metadata_io.write_project_metadata(p, {'replacement': True}, expected=binding)
    assert (p / '.devfleet/project.json').read_bytes() == previous
    assert not list((p / '.devfleet').glob('.project.json.*.tmp'))


@pytest.mark.parametrize("publisher_default, expected_read, expected_write", [(7, True, True), (5, True, False), (0, False, False)])
def test_inherited_publisher_acl_survives_restore_owner_change(acl_workspace, publisher_default, expected_read, expected_write):
    """Restoration by an unprivileged backup UID cannot retain source ownership.

    Exercise the actual ACL publication, then the ownership transition on this
    disposable inode tree. This is not a restic/network certification test.
    """
    publisher_uid = 60004
    p = acl_workspace
    for attr in (ACL_ACCESS, ACL_DEFAULT):
        policy = entries(os.getxattr(p, attr))
        policy.insert(3, (2, 7 if attr == ACL_ACCESS else publisher_default, publisher_uid))
        policy.sort(key=lambda row: (row[0], row[2]))
        os.setxattr(p, attr, pack_acl(policy))
    code = (
        'import sys, pwd; from pathlib import Path; from types import SimpleNamespace; '
        f'sys.path.insert(0, {str(Path(metadata_io.__file__).parents[1])!r}); '
        'real = pwd.getpwnam; '
        f'pwd.getpwnam = lambda n: SimpleNamespace(pw_uid={BACKUP_UID}) '
        'if n == "devfleet-backup" else real(n); '
        'from devfleet.metadata_io import write_project_metadata; '
        'write_project_metadata(Path(sys.argv[1]), {"publisher": True}, create=True)'
    )
    created = subprocess.run([sys.executable, '-I', '-c', code, str(p)],
                             user=publisher_uid, group=publisher_uid, extra_groups=[],
                             capture_output=True, text=True, timeout=10)
    assert created.returncode == 0, created.stderr
    metadata = p / '.devfleet/project.json'
    assert access_as(metadata, uid=publisher_uid)
    assert_backup_only(metadata)
    # Restore returns inode ownership to the restoring identity. The original
    # publisher's *named* ACL must retain its formerly effective owner rights.
    os.chown(metadata, BACKUP_UID, BACKUP_UID)
    os.chown(metadata.parent, BACKUP_UID, BACKUP_UID)
    assert access_as(metadata, uid=publisher_uid) == expected_read, 'Restore changed the inherited publisher read policy'
    assert access_as(metadata, uid=publisher_uid, write=True) == expected_write, 'Restore changed the inherited publisher write policy'
    assert not access_as(metadata, uid=OTHER_UID), 'Restore must not revive an unrelated principal'
