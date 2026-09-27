# DevFleet source part 076

Full-source UTF-8 byte interval [3487500, 3534000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 7449d6d654ec47063b5eecb82cacb03d5f5c1e26be9a568b82edd20ff0f58a00

<!-- BEGIN SOURCE SLICE -->
opened):
                    os.close(fd)
    finally:
        os.close(slug_fd)


def _posix_restore_journal(destination: Path, staging: Path, rollback: Path, transaction_root: Path, *, phase: str, destination_identity: dict[str, int] | None, staging_identity: dict[str, int], rollback_identity: dict[str, int] | None, restored_identity: dict[str, int] | None) -> dict[str, Any]:
    return {
        "schema_version": POSIX_RESTORE_JOURNAL_SCHEMA_VERSION,
        "slug": validate_slug(destination.name),
        "destination": str(destination),
        "transaction_root": str(transaction_root),
        "staging_root": str(staging),
        "rollback": str(rollback),
        "destination_identity": destination_identity,
        "staging_identity": staging_identity,
        "rollback_identity": rollback_identity,
        "restored_identity": restored_identity,
        "phase": phase,
        "updated_at": now_iso(),
    }


def _parse_posix_restore_journal(value: Any, destination: Path) -> dict[str, Any]:
    if not isinstance(value, dict) or value.get("schema_version") != POSIX_RESTORE_JOURNAL_SCHEMA_VERSION:
        raise ValueError("Restore journal schema version is unsupported.")
    if value.get("slug") != validate_slug(destination.name):
        raise ValueError("Restore journal slug does not match the requested workspace.")
    expected_destination = _absolute_path(destination)
    for field in ("destination", "transaction_root", "staging_root", "rollback"):
        raw = value.get(field)
        if not isinstance(raw, str) or _absolute_path(Path(raw)) != Path(raw):
            raise ValueError(f"Restore journal {field} is not a lexical absolute path.")
    if Path(value["destination"]) != expected_destination:
        raise ValueError("Restore journal destination does not match the requested workspace.")
    transaction_root = Path(value["transaction_root"])
    if transaction_root != expected_destination.parent / TRANSACTION_ROOT_NAME:
        raise ValueError("Restore journal transaction root is not the protected local root.")
    staging = Path(value["staging_root"])
    rollback = Path(value["rollback"])
    if staging.parent != transaction_root or rollback.parent != expected_destination.parent:
        raise ValueError("Restore journal transaction paths are not descriptor-bound siblings.")
    slug = validate_slug(destination.name)
    if not re.fullmatch(rf".{re.escape(slug)}-restore-[A-Za-z0-9_-]{{6,64}}", staging.name):
        raise ValueError("Restore journal staging identity is invalid.")
    if not re.fullmatch(rf".{re.escape(slug)}\.rollback-[0-9a-f]{{32}}", rollback.name):
        raise ValueError("Restore journal rollback identity is invalid.")
    for field in ("destination_identity", "staging_identity", "rollback_identity", "restored_identity"):
        identity = value.get(field)
        if identity is not None and (not isinstance(identity, dict) or set(identity) != {"st_dev", "st_ino", "st_type"} or not all(type(identity[key]) is int for key in identity)):
            raise ValueError(f"Restore journal {field} identity is malformed.")
    if value.get("phase") not in RESTORE_JOURNAL_PHASES:
        raise ValueError("Restore journal phase is unsupported.")
    if not isinstance(value.get("staging_identity"), dict):
        raise ValueError("Restore journal is missing the staging identity.")
    return value


def _posix_manual_recovery(destination: Path, journal_path: Path, reason: str) -> None:
    _write_restore_manual_recovery(destination, journal_path, reason)


def _reconcile_restore_transaction_posix(destination: Path) -> dict[str, Any] | None:
    destination = _absolute_path(destination)
    journal_path = _restore_journal_path(destination)
    if not journal_path.is_file():
        return None
    parent_fd = transaction_fd = None
    try:
        if _is_reparse_point(journal_path):
            raise ValueError("Restore transaction record is an alias.")
        record = _parse_posix_restore_journal(json.loads(journal_path.read_text(encoding="utf-8")), destination)
        parent_fd, _ = _open_directory_path(destination.parent)
        transaction_fd, _ = _open_verified_child(parent_fd, TRANSACTION_ROOT_NAME, stat.S_IFDIR)
        staging = Path(record["staging_root"])
        rollback = Path(record["rollback"])
        phase = record["phase"]
        staging_id = record["staging_identity"]
        rollback_id = record.get("rollback_identity")
        destination_id = record.get("destination_identity")
        restored_id = record.get("restored_identity")
        if _identity_at(transaction_fd, staging.name) != staging_id:
            raise RuntimeError("Restore staging identity is ambiguous; manual recovery required.")
        if phase in {"PREPARED", "OLD_MOVED_TO_ROLLBACK"}:
            if phase == "PREPARED":
                current_destination = _identity_at(parent_fd, destination.name)
                current_rollback = _identity_at(parent_fd, rollback.name)
                if current_destination != destination_id or current_rollback is not None:
                    raise RuntimeError("Restore PREPARED identities changed; manual recovery required.")
            else:
                if _identity_at(parent_fd, destination.name) is not None or _identity_at(parent_fd, rollback.name) != rollback_id:
                    raise RuntimeError("Restore rollback identities changed; manual recovery required.")
                os.rename(rollback.name, destination.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                if _identity_at(parent_fd, destination.name) != destination_id:
                    raise RuntimeError("Restore rollback promotion identity check failed; manual recovery required.")
        elif phase in {"NEW_PROMOTED", "POSTCHECK_PASSED", "COMMITTED"}:
            if _identity_at(parent_fd, destination.name) != restored_id:
                raise RuntimeError("Restore destination identity is ambiguous; manual recovery required.")
            if phase != "COMMITTED":
                try:
                    inspection = inspect_workspace(destination)
                    if not inspection["safe_for_archive"]:
                        raise ValueError("Restored workspace is not archive-safe.")
                except Exception:
                    if rollback_id is None or _identity_at(parent_fd, rollback.name) != rollback_id:
                        raise RuntimeError("Restore rollback identity is unavailable; manual recovery required.")
                    _remove_tree_at(parent_fd, destination.name, restored_id, "destination")
                    os.rename(rollback.name, destination.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                    if _identity_at(parent_fd, destination.name) != destination_id:
                        raise RuntimeError("Restore rollback verification failed; manual recovery required.")
        if _identity_at(transaction_fd, staging.name) != staging_id:
            raise RuntimeError("Restore staging changed before cleanup; manual recovery required.")
        _remove_tree_at(transaction_fd, staging.name, staging_id, "staging")
        if rollback_id is not None and _identity_at(parent_fd, rollback.name) is not None:
            if _identity_at(parent_fd, rollback.name) != rollback_id:
                raise RuntimeError("Restore rollback changed before cleanup; manual recovery required.")
            if _identity_at(parent_fd, destination.name) is None:
                raise RuntimeError("Restore cleanup lost the canonical destination; manual recovery required.")
            _remove_tree_at(parent_fd, rollback.name, rollback_id, "rollback")
        journal_path.unlink(missing_ok=True)
        return {"recovered": True, "phase": phase, "destination": str(destination)}
    except Exception as exc:
        reason = f"{type(exc).__name__}: {exc}"
        with contextlib.suppress(OSError):
            _posix_manual_recovery(destination, journal_path, reason)
        if isinstance(exc, RuntimeError) and "manual recovery required" in str(exc):
            raise
        raise RuntimeError("Unfinished workspace restore could not be reconciled safely; manual recovery required and cleanup was refused.") from exc
    finally:
        if transaction_fd is not None:
            os.close(transaction_fd)
        if parent_fd is not None:
            os.close(parent_fd)


def reconcile_restore_transaction(destination: Path) -> dict[str, Any] | None:
    if POSIX_FD_HARDENING:
        return _reconcile_restore_transaction_posix(destination)
    return _reconcile_restore_transaction_compat(destination)


def _reconcile_restore_transaction_compat(destination: Path) -> dict[str, Any] | None:
    """Compatibility recovery path for Windows unit-test support."""
    destination = destination.resolve(strict=False)
    journal_path = _restore_journal_path(destination)
    if not journal_path.is_file():
        return None
    try:
        if _is_reparse_point(journal_path):
            raise ValueError("Restore transaction record is a symlink or reparse point.")
        journal = json.loads(journal_path.read_text(encoding="utf-8"))
        transaction = _parse_restore_journal(journal, destination)
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
        reason = f"{type(exc).__name__}: {exc}"
        try:
            _write_restore_manual_recovery(destination, journal_path, reason)
        except OSError:
            pass
        raise RuntimeError("Unfinished workspace restore is unauthorized or unreadable; manual recovery required and cleanup was refused.") from exc
    phase = transaction.phase
    staged = transaction.staging_root
    rollback = transaction.rollback
    if phase in {"PREPARED", "OLD_MOVED_TO_ROLLBACK"}:
        if not destination.exists() and rollback.exists():
            os.replace(rollback, destination)
        if not destination.exists() and phase == "OLD_MOVED_TO_ROLLBACK":
            raise RuntimeError("Unfinished workspace restore lost both canonical and rollback identities; manual recovery required.")
    elif phase in {"NEW_PROMOTED", "POSTCHECK_PASSED"}:
        if not destination.is_dir() or destination.is_symlink():
            if rollback.exists():
                os.replace(rollback, destination)
            else:
                raise RuntimeError("Unfinished workspace restore has no safe canonical or rollback copy.")
        else:
            try:
                inspect_workspace(destination)
            except Exception:
                if rollback.exists():
                    shutil.rmtree(destination)
                    os.replace(rollback, destination)
                else:
                    raise
    if staged.exists():
        shutil.rmtree(staged, ignore_errors=True)
    if rollback.exists() and destination.exists():
        shutil.rmtree(rollback, ignore_errors=True)
    journal_path.unlink(missing_ok=True)
    return {"recovered": True, "phase": phase, "destination": str(destination)}


def _restore_workspace_archive_posix(archive_path: Path, destination: Path, slug: str) -> dict[str, Any]:
    slug = validate_slug(slug)
    verification = validate_archive(archive_path, slug)
    destination = _absolute_path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    reconcile_restore_transaction(destination)
    parent_fd, _ = _open_directory_path(destination.parent)
    transaction_fd = None
    staging_fd = None
    promoted_id = None
    old_destination_id = _identity_at(parent_fd, destination.name)
    rollback_name = f".{destination.name}.rollback-{uuid.uuid4().hex}"
    staging_name = f".{slug}-restore-{uuid.uuid4().hex}"
    rollback_id = None
    staging_id = None
    journal_path = _restore_journal_path(destination)
    transaction_root = destination.parent / TRANSACTION_ROOT_NAME
    staging = transaction_root / staging_name
    rollback = destination.parent / rollback_name
    try:
        transaction_fd, _ = _mkdir_verified_at(parent_fd, TRANSACTION_ROOT_NAME)
        os.mkdir(staging_name, 0o700, dir_fd=transaction_fd)
        staging_fd, staging_result = _open_verified_child(transaction_fd, staging_name, stat.S_IFDIR)
        staging_id = _object_identity(staging_result)
        if _identity_at(parent_fd, rollback_name) is not None:
            raise RuntimeError("Restore rollback name unexpectedly exists; manual recovery required.")
        journal = _posix_restore_journal(destination, staging, rollback, transaction_root, phase="PREPARED", destination_identity=old_destination_id, staging_identity=staging_id, rollback_identity=None, restored_identity=None)
        atomic_json(journal_path, journal)
        with tarfile.open(archive_path, "r:gz") as archive:
            _validate_members(archive, slug)
            _extract_archive_at_fd(archive, slug, staging_fd)
        restored_fd, restored_result = _open_verified_child(staging_fd, slug, stat.S_IFDIR)
        restored_id = _object_identity(restored_result)
        os.close(restored_fd)
        journal["restored_identity"] = restored_id
        atomic_json(journal_path, journal)
        if restored_result.st_dev != os.fstat(parent_fd).st_dev:
            raise ValueError("Workspace restore refused: staging and destination are on different filesystems.")
        if old_destination_id is not None:
            if _identity_at(parent_fd, destination.name) != old_destination_id or _identity_at(parent_fd, rollback_name) is not None:
                raise RuntimeError("Restore destination changed before rollback transition; manual recovery required.")
            os.rename(destination.name, rollback_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            rollback_id = _identity_at(parent_fd, rollback_name)
            if rollback_id != old_destination_id:
                raise RuntimeError("Restore rollback identity check failed; manual recovery required.")
            journal["rollback_identity"] = rollback_id
            journal["phase"] = "OLD_MOVED_TO_ROLLBACK"
            journal["updated_at"] = now_iso()
            atomic_json(journal_path, journal)
        if _identity_at(transaction_fd, staging_name) != staging_id or _identity_at(parent_fd, destination.name) is not None:
            raise RuntimeError("Restore staging or destination identity changed before promotion; manual recovery required.")
        os.rename(slug, destination.name, src_dir_fd=staging_fd, dst_dir_fd=parent_fd)
        promoted_id = _identity_at(parent_fd, destination.name)
        if promoted_id != restored_id:
            raise RuntimeError("Restore destination identity check failed; manual recovery required.")
        journal["phase"] = "NEW_PROMOTED"
        journal["updated_at"] = now_iso()
        atomic_json(journal_path, journal)
        inspection = inspect_workspace(destination)
        if not inspection["safe_for_archive"]:
            raise ValueError("Restored workspace failed the archive safety inspection.")
        journal["phase"] = "POSTCHECK_PASSED"
        journal["updated_at"] = now_iso()
        atomic_json(journal_path, journal)
        if rollback_id is not None:
            _remove_tree_at(parent_fd, rollback_name, rollback_id, "rollback")
        _remove_tree_at(transaction_fd, staging_name, staging_id, "staging")
        journal["phase"] = "COMMITTED"
        journal["updated_at"] = now_iso()
        atomic_json(journal_path, journal)
        journal_path.unlink(missing_ok=True)
        return {**verification, "workspace": str(destination), "restored": True, "inspection": inspection}
    except Exception as exc:
        # Roll back only identities proven to be the objects this transaction
        # created/moved.  A substituted destination or rollback is left in
        # place with a manual-recovery record rather than recursively deleting it.
        try:
            current_destination = _identity_at(parent_fd, destination.name)
            if promoted_id is not None:
                if current_destination != promoted_id:
                    raise RuntimeError("Restore promoted destination identity is ambiguous; manual recovery required.")
                _remove_tree_at(parent_fd, destination.name, promoted_id, "destination")
                current_destination = None
            if old_destination_id is not None and current_destination is None:
                current_rollback = _identity_at(parent_fd, rollback_name)
                if rollback_id is not None and current_rollback != rollback_id:
                    raise RuntimeError("Restore rollback identity is ambiguous; manual recovery required.")
                if current_rollback == old_destination_id or current_rollback == rollback_id:
                    os.rename(rollback_name, destination.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            if staging_id is not None and transaction_fd is not None and _identity_at(transaction_fd, staging_name) == staging_id:
                _remove_tree_at(transaction_fd, staging_name, staging_id, "staging")
        except Exception as rollback_exc:
            reason = f"{type(rollback_exc).__name__}: {rollback_exc}"
            with contextlib.suppress(OSError):
                _posix_manual_recovery(destination, journal_path, reason)
            raise RuntimeError("Workspace restore failed with ambiguous transaction identity; manual recovery required.") from rollback_exc
        raise
    finally:
        if staging_fd is not None:
            os.close(staging_fd)
        if transaction_fd is not None:
            os.close(transaction_fd)
        os.close(parent_fd)


def restore_workspace_archive(archive_path: Path, destination: Path, slug: str) -> dict[str, Any]:
    if POSIX_FD_HARDENING:
        return _restore_workspace_archive_posix(archive_path, destination, slug)
    return _restore_workspace_archive_compat(archive_path, destination, slug)


def _restore_workspace_archive_compat(archive_path: Path, destination: Path, slug: str) -> dict[str, Any]:
    """Restore one verified archive with rollback-safe sibling promotion.

    The existing workspace is never deleted before the staged tree has been
    validated.  Promotion is a same-filesystem rename, and the rollback sibling
    is retained until the promoted tree passes its post-promotion inspection.
    """
    slug = validate_slug(slug)
    verification = validate_archive(archive_path, slug)
    destination = destination.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    rollback = destination.parent / f'.{destination.name}.rollback-{uuid.uuid4().hex}'
    _reconcile_restore_transaction_compat(destination)
    journal_path = _restore_journal_path(destination)
    staging_root = Path(tempfile.mkdtemp(prefix=f'.{slug}-restore-', dir=str(destination.parent)))
    journal = {"schema_version": 1, "slug": slug, "destination": str(destination), "staging_root": str(staging_root), "rollback": str(rollback), "phase": "PREPARED", "updated_at": now_iso()}
    atomic_json(journal_path, journal)
    promoted = False
    try:
        with tarfile.open(archive_path, 'r:gz') as archive:
            _validate_members(archive, slug)
            # Members were validated above; extract explicitly so behavior does
            # not depend on Python's version-specific tar extraction filter.
            members = archive.getmembers()
            for member in members:
                safe_name = member.name.replace('\\', '/')
                target = staging_root.joinpath(*safe_name.split('/'))
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                    os.chmod(target, member.mode & 0o777)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise ValueError(f'Archive member could not be read: {member.name}')
                with source, target.open('xb') as destination_file:
                    shutil.copyfileobj(source, destination_file)
                # Tar metadata is untrusted.  Preserve only ordinary POSIX
                # permission bits; never restore setuid/setgid/sticky bits.
                os.chmod(target, member.mode & 0o777)
        restored = staging_root / slug
        if not restored.is_dir() or restored.is_symlink():
            raise ValueError('Verified archive did not produce a safe workspace directory.')
        _assert_same_filesystem(staging_root, destination.parent)
        if destination.exists():
            if destination.is_symlink() or not destination.is_dir():
                raise ValueError('Workspace destination is not a safe directory.')
            os.replace(destination, rollback)
            journal["phase"] = "OLD_MOVED_TO_ROLLBACK"; journal["updated_at"] = now_iso(); atomic_json(journal_path, journal)
        try:
            os.replace(restored, destination)
            promoted = True
            journal["phase"] = "NEW_PROMOTED"; journal["updated_at"] = now_iso(); atomic_json(journal_path, journal)
            inspection = inspect_workspace(destination)
            if not inspection['safe_for_archive']:
                raise ValueError('Restored workspace failed the archive safety inspection.')
            journal["phase"] = "POSTCHECK_PASSED"; journal["updated_at"] = now_iso(); atomic_json(journal_path, journal)
        except Exception:
            if destination.exists() and promoted:
                shutil.rmtree(destination)
            if rollback.exists() and not destination.exists():
                os.replace(rollback, destination)
            raise
        if rollback.exists():
            shutil.rmtree(rollback)
        journal["phase"] = "COMMITTED"; journal["updated_at"] = now_iso(); atomic_json(journal_path, journal)
        journal_path.unlink(missing_ok=True)
        return {**verification, 'workspace': str(destination), 'restored': True, 'inspection': inspection}
    finally:
        if staging_root.exists():
            shutil.rmtree(staging_root, ignore_errors=True)


def create_workspace_archive(
    root: Path,
    slug: str,
    destination: Path,
    *,
    include_generated: bool = False,
    consistency_level: str = "live-best-effort",
) -> dict[str, Any]:
    slug = validate_slug(slug)
    if POSIX_FD_HARDENING:
        inspection, entries = _capture_workspace_posix(root, include_generated=include_generated)
        if not inspection["safe_for_archive"]:
            _close_authorized_entries(entries)
            raise ValueError("Workspace contains symbolic links and cannot be archived safely.")
        destination.parent.mkdir(parents=True, exist_ok=True)
        fd, temp_name = tempfile.mkstemp(prefix=f".{slug}-", suffix=".tar.gz.tmp", dir=str(destination.parent))
        os.close(fd)
        temp_path = Path(temp_name)
        try:
            # Every regular member is streamed from the descriptor captured and
            # identity-checked above.  tarfile never reopens a workspace path.
            _write_authorized_tar(temp_path, slug, entries)
            verification = validate_archive(temp_path, slug)
            os.replace(temp_path, destination)
            return {
                **inspection,
                **verification,
                "archive_path": str(destination),
                "created_at": now_iso(),
                "consistency_level": consistency_level,
            }
        finally:
            _close_authorized_entries(entries)
            temp_path.unlink(missing_ok=True)
    inspection = inspect_workspace(root, include_generated=include_generated)
    if not inspection["safe_for_archive"]:
        raise ValueError("Workspace contains symbolic links and cannot be archived safely.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{slug}-", suffix=".tar.gz.tmp", dir=str(destination.parent))
    os.close(fd)
    temp_path = Path(temp_name)
    try:
        with tarfile.open(temp_path, "w:gz", dereference=False) as archive:
            archive.add(
                root,
                arcname=slug,
                recursive=True,
                filter=lambda info: _archive_filter(info, slug, include_generated=include_generated),
            )
        verification = validate_archive(temp_path, slug)
        os.replace(temp_path, destination)
        return {
            **inspection,
            **verification,
            "archive_path": str(destination),
            "created_at": now_iso(),
            "consistency_level": consistency_level,
        }
    finally:
        temp_path.unlink(missing_ok=True)


def _archive_filter(
    info: tarfile.TarInfo,
    slug: str,
    *,
    include_generated: bool = False,
) -> tarfile.TarInfo | None:
    relative_parts = Path(info.name).parts[1:]
    if not include_generated and any(part in GENERATED_DIR_NAMES for part in relative_parts):
        return None
    # The source walk rejects symlinks and unsupported filesystem entries; this
    # second check protects against a race between inspection and tar.add().
    if info.issym() or info.islnk() or info.isdev() or not (info.isdir() or info.isfile()):
        raise ValueError(f"Workspace contains an unsupported archive entry: {info.name}")
    return info


def write_backup_manifest(directory: Path, *, slug: str, project_id: str, runtime: dict[str, Any], archive: dict[str, Any], consistency_level: str = "live-best-effort") -> dict[str, Any]:
    if consistency_level not in {"live-best-effort", "quiesced", "application-consistent"}:
        raise ValueError("Unknown backup consistency level.")
    directory.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema_version": 1,
        "backup_id": directory.name,
        "created_at": archive.get("created_at") or now_iso(),
        "project_id": project_id,
        "slug": validate_slug(slug),
        "runtime": runtime,
        "workspace": {key: archive.get(key) for key in ("archive_path", "archive_sha256", "archive_bytes", "files", "bytes", "entries", "generated_dirs", "generated_details", "generated_bytes", "estimated_archive_bytes", "symlinks", "symlink_targets", "included_path_count", "included_file_count", "included_byte_count", "omitted_paths", "omission_policy_source")},
        "verification": {"status": "verified", "integrity_verified": True, "consistency_level": consistency_level, "consistency_level_source": "transaction-parameter", "verified_at": now_iso()},
    }
    atomic_json(directory / "manifest.json", manifest)
    return manifest

```


## FILE: source/app/requirements-hashed.txt

SHA256: fe238c807b668a2f7e0f2b929e24859260e6a7f76bd6762ac7b6b10ad7daac33 | Bytes: 54467 | Git mode: 100644

```
#
# This file is autogenerated by pip-compile with Python 3.12
# by the following command:
#
#    pip-compile --generate-hashes --output-file=source/app/requirements-hashed.h10.txt source/app/requirements.txt
#
annotated-doc==0.0.5 \
    --hash=sha256:117bac03a25ede5df5440e855b32d556049ca169ead221505badf432fed4b101 \
    --hash=sha256:c7e58ce09192557605d8bbd92836d7e1d520ac9580096042c0bfd197efacf1bb
    # via fastapi
annotated-types==0.8.0 \
    --hash=sha256:13b2beaad985e05e2d6407ee4c4f35590b11f8d693a258a561055cac8f64cab7 \
    --hash=sha256:f072f4d804ea359e4eaf198b1af7a8b0943881a87f31bb764f8bf219bb9419e0
    # via pydantic
anyio==4.14.2 \
    --hash=sha256:9f505dda5ac9f0c8309b5e8bd445a8c2bf7246f3ce950121e45ea15bc41d1494 \
    --hash=sha256:cfa139f3ed1a23ee8f88a145ddb5ac7605b8bbfd8592baacd7ce3d8bb4313c7f
    # via
    #   httpx
    #   starlette
    #   watchfiles
certifi==2026.7.22 \
    --hash=sha256:62f22742b58a1a33014a2b6b706588a8d7e2a88ae7bd1a6ebe8c992928483775 \
    --hash=sha256:741e2c3b351ddf169a738da9f2c048608ff7f2c5cc02f1ebc6b118bb090d5d55
    # via
    #   httpcore
    #   httpx
click==8.4.2 \
    --hash=sha256:9a6cea6e60b17ebe0a44c5cc636d94f09bd66142c1cd7d8b4cd731c4917a15f6 \
    --hash=sha256:e6f9f66136c816745b9d65817da91d61d957fb16e02e4dcd0552553c5a197b76
    # via uvicorn
fastapi==0.141.1 \
    --hash=sha256:bfb91aa2d334c61cb35ba9a116fc123b3d3df31640b801cf57a7a78ec3f603b3 \
    --hash=sha256:e8822fc40db1e1858054d7a949a888695bc9bdce70139178e33bd2871a453ca1
    # via -r source/app/requirements.txt
h11==0.16.0 \
    --hash=sha256:4e35b956cf45792e4caa5885e69fba00bdbc6ffafbfa020300e549b208ee5ff1 \
    --hash=sha256:63cf8bbe7522de3bf65932fda1d9c2772064ffb3dae62d55932da54b31cb6c86
    # via
    #   httpcore
    #   uvicorn
httpcore==1.0.9 \
    --hash=sha256:2d400746a40668fc9dec9810239072b40b4484b640a8c38fd654a024c7a1bf55 \
    --hash=sha256:6e34463af53fd2ab5d807f399a9b45ea31c3dfa2276f15a2c3f00afff6e176e8
    # via httpx
httptools==0.8.0 \
    --hash=sha256:0770728beb05094c809b98e814edff5fef69d26ad7d21185f2f6d5884a0ba683 \
    --hash=sha256:0ea897f0c729581ebf72131a438a7932d9b14efef72d75ada966700cac3caaeb \
    --hash=sha256:159e9ab5f701ccd42e555a12f1ad8ff69702910fc1c996cf2bb66e5fcb7a231b \
    --hash=sha256:19d1ee275bb59ba2643ba9a3a1e51cc0c788caf2b8df506368e03f56fdd08527 \
    --hash=sha256:20b4aac66ff65f7db06a375808b78f42a94970aa22e826b3cb2b43eb09174124 \
    --hash=sha256:2a021c3a8e65cc125390d72f59b968afca3bdcaff25bd67965e0a055a14946ca \
    --hash=sha256:2c032fa028f46871ec7e1fc59fc15e8023eab3e6bbe6ece786a1611719a5d081 \
    --hash=sha256:2d689918c15a013c65ef52d9fd495d766893ab831a2c8d89f2ac5940a5df847c \
    --hash=sha256:384c17174464c8e873398b7af24f0b1f44d992c820328413951a625323155d77 \
    --hash=sha256:425f83884fd6343828d8c565f046cb72b6d19063f6924093e11bcd8e1548cd09 \
    --hash=sha256:48774d39cbb70e2b1f71f88852a3087ae1d3a1eb80482bb48c13067ab080c14f \
    --hash=sha256:52dd695b865fe96d9d2b16b64a895f3f57bf3cb064e8383cd3b5713a069e8085 \
    --hash=sha256:57278e6fa0424c42a8a3e454828ab4f0aff27b40cddf9679579b98c6dce6a376 \
    --hash=sha256:5931891fb7b441b8a3853cf1b85c82c903defce084dd5f6771ca46e31bf862c5 \
    --hash=sha256:5d7fa4ba7292c1139c0526f0b5aad507c6263c948206ea1b1cbca015c8af1b62 \
    --hash=sha256:5eb911c515b96ee44bbd861e42cbefc488681d450545b1d02127f6136e3a86f5 \
    --hash=sha256:614ceea8ea606848bece2338ac03b3ce5324bcb4be8dc7d377ed708012fa4db8 \
    --hash=sha256:6a43c9dd399758ccc0531acb0a3c4a6c299ee893ee9400e9c893b7bdcfae0681 \
    --hash=sha256:6b2a32f18d97e16e90827d7a819ffa8dbd8cc245fc4e1fa9d1095b54ef4bd999 \
    --hash=sha256:7685df791fad561384bfb139e77fde27a1ffd93134e016f95a0db424ffbf77b1 \
    --hash=sha256:7b71e7d7031928c650e1006e6c03e911bf967f7c69c011d37d541c3e7bf55005 \
    --hash=sha256:880490234c10f70a9830743097e8958d6e4b9f5a0ffc24515023afeef984054d \
    --hash=sha256:88bdd940f2b5d487b4d032c6afa5489a7dc4694410d43de3c38c4fb3af0dc45d \
    --hash=sha256:88eead8ec8680a9f146c655bc88445a325bd7921cfd8194c7337e9467282427d \
    --hash=sha256:9518c406d7b310f05adb1a37f80acabac40504a575d7c0da6d3e365c695ac20d \
    --hash=sha256:9878eb2785ba5eb70631ad269b37976f73d647955e26c91d490eb8a4edfda4ba \
    --hash=sha256:9fc1644f415372cec4f8a5be3a64183737398f10dbb1263602a036427fe75247 \
    --hash=sha256:a1afd7c9fbff0d9f5d489c4ce2768bd09c84a46ddefc7161e6aa82ae35c85745 \
    --hash=sha256:a1b4c8e7a489a0d750d91894e9a8cdc295838f1924c0ca903ae993456fddec07 \
    --hash=sha256:a3b7387147361c3fd47a0bde763c5c91b5b4cd4dc9989b8ece84ff436c99843b \
    --hash=sha256:a6f21e2a3b0067bbe7f67e34cfd16276af556e5e52f4c7503be0cb5f90e905e4 \
    --hash=sha256:b15fc622b0f869d19207c4089a501d9bcc63ca5e071ffdd2f03f922df882dcb2 \
    --hash=sha256:b205e5f5523fa039679da0dfe5a10132b2a4abeae6a86fdd1ddc035f7f836557 \
    --hash=sha256:bbb8caadb2b742d293169d2b458b5c001ef70e3158704aa3d3ef9597624c5d1d \
    --hash=sha256:bf3b6f807c8541503cecfbb8a8dffb385640d0d96102f3d112aa8740f9b7c826 \
    --hash=sha256:c08ffe3e79756e0963cbc8fe410139f38a5884874b6f2e17761bef6563fdcd9b \
    --hash=sha256:c0d726cc107fceb7d45f978483b4b70dd8caa836f5914d3434bb18628eb73813 \
    --hash=sha256:c4a9f1707e4823d54dfec6c33fa3697d302aed536ed352a7ebb5a061ddb869d0 \
    --hash=sha256:cd96f29b4bab1d42fa6e3d008711c75e0f79e94e06827330160e3a304227f150 \
    --hash=sha256:d76ad7b951387e3632c8716a9bb03ac5b45c5f16119aa409db0459520887944e \
    --hash=sha256:da684f2e1aa2ee9bdcb083f3f3a68c5956750b375bc5df864d3a5f0c42a40b77 \
    --hash=sha256:de1ed58a974e75d56560acc7e7fed01a454994429456f65209789992e41f2568 \
    --hash=sha256:de242a49b5d18e0a8776e654e9f6bf6d89f3875a5c35b425a0e7ce940feb3fd6 \
    --hash=sha256:df31ef5494f406ab6cf827b7e64a22841c6e2d654100e6a116ea15b46d02d5e8 \
    --hash=sha256:e93c227b595c6926c1acee96891dd9da4be338cfbe82e5cd3bb9d8dd7dc4ac0b \
    --hash=sha256:eb3028cca2fc0a6d720e52ef61d8ebb62fcbfeb1de56874546d858d3f25a26b7 \
    --hash=sha256:ed377e64805bdba4943c82717333f8f8603a13b09aff9cead2717c6c817fb168 \
    --hash=sha256:ef7c3c97f4311c7be57e2986629df89d49cb434dbff78eafcd48c2bff986b15a \
    --hash=sha256:f256d6ce930c52ca1cb2a960b7da03548c454e7d28b06059ad41bfe789036ce0 \
    --hash=sha256:fe2a4c95aeba2209434e7b31172da572846cae8ca0bf1e7013e61b99fbbf5e72
    # via uvicorn
httpx==0.28.1 \
    --hash=sha256:75e98c5f16b0f35b567856f597f06ff2270a374470a5c2392242528e3e3e42fc \
    --hash=sha256:d909fcccc110f8c7faf814ca82a9a4d816bc5a6dbfea25d6591d6985b8ba59ad
    # via -r source/app/requirements.txt
idna==3.19 \
    --hash=sha256:5e0811a4383b21dc5838069f801c4fb62113b7447663d2530d2bd6e77b49bf15 \
    --hash=sha256:815e7be7a7806d54abb586dc943addc79e8b2ee16915059658cbeff4b1b43bf4
    # via
    #   anyio
    #   httpx
jinja2==3.1.6 \
    --hash=sha256:0137fb05990d35f1275a587e9aee6d56da821fc83491a0fb838183be43f66d6d \
    --hash=sha256:85ece4451f492d0c13c5dd7c13a64681a86afae63a5f347908daf103ce6d2f67
    # via -r source/app/requirements.txt
markupsafe==3.0.3 \
    --hash=sha256:0303439a41979d9e74d18ff5e2dd8c43ed6c6001fd40e5bf2e43f7bd9bbc523f \
    --hash=sha256:068f375c472b3e7acbe2d5318dea141359e6900156b5b2ba06a30b169086b91a \
    --hash=sha256:0bf2a864d67e76e5c9a34dc26ec616a66b9888e25e7b9460e1c76d3293bd9dbf \
    --hash=sha256:0db14f5dafddbb6d9208827849fad01f1a2609380add406671a26386cdf15a19 \
    --hash=sha256:0eb9ff8191e8498cca014656ae6b8d61f39da5f95b488805da4bb029cccbfbaf \
    --hash=sha256:0f4b68347f8c5eab4a13419215bdfd7f8c9b19f2b25520968adfad23eb0ce60c \
    --hash=sha256:1085e7fbddd3be5f89cc898938f42c0b3c711fdcb37d75221de2666af647c175 \
    --hash=sha256:116bb52f642a37c115f517494ea5feb03889e04df47eeff5b130b1808ce7c219 \
    --hash=sha256:12c63dfb4a98206f045aa9563db46507995f7ef6d83b2f68eda65c307c6829eb \
    --hash=sha256:133a43e73a802c5562be9bbcd03d090aa5a1fe899db609c29e8c8d815c5f6de6 \
    --hash=sha256:1353ef0c1b138e1907ae78e2f6c63ff67501122006b0f9abad68fda5f4ffc6ab \
    --hash=sha256:15d939a21d546304880945ca1ecb8a039db6b4dc49b2c5a400387cdae6a62e26 \
    --hash=sha256:177b5253b2834fe3678cb4a5f0059808258584c559193998be2601324fdeafb1 \
    --hash=sha256:1872df69a4de6aead3491198eaf13810b565bdbeec3ae2dc8780f14458ec73ce \
    --hash=sha256:1b4b79e8ebf6b55351f0d91fe80f893b4743f104bff22e90697db1590e47a218 \
    --hash=sha256:1b52b4fb9df4eb9ae465f8d0c228a00624de2334f216f178a995ccdcf82c4634 \
    --hash=sha256:1ba88449deb3de88bd40044603fafffb7bc2b055d626a330323a9ed736661695 \
    --hash=sha256:1cc7ea17a6824959616c525620e387f6dd30fec8cb44f649e31712db02123dad \
    --hash=sha256:218551f6df4868a8d527e3062d0fb968682fe92054e89978594c28e642c43a73 \
    --hash=sha256:26a5784ded40c9e318cfc2bdb30fe164bdb8665ded9cd64d500a34fb42067b1c \
    --hash=sha256:2713baf880df847f2bece4230d4d094280f4e67b1e813eec43b4c0e144a34ffe \
    --hash=sha256:2a15a08b17dd94c53a1da0438822d70ebcd13f8c3a95abe3a9ef9f11a94830aa \
    --hash=sha256:2f981d352f04553a7171b8e44369f2af4055f888dfb147d55e42d29e29e74559 \
    --hash=sha256:32001d6a8fc98c8cb5c947787c5d08b0a50663d139f1305bac5885d98d9b40fa \
    --hash=sha256:3524b778fe5cfb3452a09d31e7b5adefeea8c5be1d43c4f810ba09f2ceb29d37 \
    --hash=sha256:3537e01efc9d4dccdf77221fb1cb3b8e1a38d5428920e0657ce299b20324d758 \
    --hash=sha256:35add3b638a5d900e807944a078b51922212fb3dedb01633a8defc4b01a3c85f \
    --hash=sha256:38664109c14ffc9e7437e86b4dceb442b0096dfe3541d7864d9cbe1da4cf36c8 \
    --hash=sha256:3a7e8ae81ae39e62a41ec302f972ba6ae23a5c5396c8e60113e9066ef893da0d \
    --hash=sha256:3b562dd9e9ea93f13d53989d23a7e775fdfd1066c33494ff43f5418bc8c58a5c \
    --hash=sha256:457a69a9577064c05a97c41f4e65148652db078a3a509039e64d3467b9e7ef97 \
    --hash=sha256:4bd4cd07944443f5a265608cc6aab442e4f74dff8088b0dfc8238647b8f6ae9a \
    --hash=sha256:4e885a3d1efa2eadc93c894a21770e4bc67899e3543680313b09f139e149ab19 \
    --hash=sha256:4faffd047e07c38848ce017e8725090413cd80cbc23d86e55c587bf979e579c9 \
    --hash=sha256:509fa21c6deb7a7a273d629cf5ec029bc209d1a51178615ddf718f5918992ab9 \
    --hash=sha256:5678211cb9333a6468fb8d8be0305520aa073f50d17f089b5b4b477ea6e67fdc \
    --hash=sha256:591ae9f2a647529ca990bc681daebdd52c8791ff06c2bfa05b65163e28102ef2 \
    --hash=sha256:5a7d5dc5140555cf21a6fefbdbf8723f06fcd2f63ef108f2854de715e4422cb4 \
    --hash=sha256:69c0b73548bc525c8cb9a251cddf1931d1db4d2258e9599c28c07ef3580ef354 \
    --hash=sha256:6b5420a1d9450023228968e7e6a9ce57f65d148ab56d2313fcd589eee96a7a50 \
    --hash=sha256:722695808f4b6457b320fdc131280796bdceb04ab50fe1795cd540799ebe1698 \
    --hash=sha256:729586769a26dbceff69f7a7dbbf59ab6572b99d94576a5592625d5b411576b9 \
    --hash=sha256:77f0643abe7495da77fb436f50f8dab76dbc6e5fd25d39589a0f1fe6548bfa2b \
    --hash=sha256:795e7751525cae078558e679d646ae45574b47ed6e7771863fcc079a6171a0fc \
    --hash=sha256:7be7b61bb172e1ed687f1754f8e7484f1c8019780f6f6b0786e76bb01c2ae115 \
    --hash=sha256:7c3fb7d25180895632e5d3148dbdc29ea38ccb7fd210aa27acbd1201a1902c6e \
    --hash=sha256:7e68f88e5b8799aa49c85cd116c932a1ac15caaa3f5db09087854d218359e485 \
    --hash=sha256:83891d0e9fb81a825d9a6d61e3f07550ca70a076484292a70fde82c4b807286f \
    --hash=sha256:8485f406a96febb5140bfeca44a73e3ce5116b2501ac54fe953e488fb1d03b12 \
    --hash=sha256:8709b08f4a89aa7586de0aadc8da56180242ee0ada3999749b183aa23df95025 \
    --hash=sha256:8f71bc33915be5186016f675cd83a1e08523649b0e33efdb898db577ef5bb009 \
    --hash=sha256:915c04ba3851909ce68ccc2b8e2cd691618c4dc4c4232fb7982bca3f41fd8c3d \
    --hash=sha256:949b8d66bc381ee8b007cd945914c721d9aba8e27f71959d750a46f7c282b20b \
    --hash=sha256:94c6f0bb423f739146aec64595853541634bde58b2135f27f61c1ffd1cd4d16a \
    --hash=sha256:9a1abfdc021a164803f4d485104931fb8f8c1efd55bc6b748d2f5774e78b62c5 \
    --hash=sha256:9b79b7a16f7fedff2495d684f2b59b0457c3b493778c9eed31111be64d58279f \
    --hash=sha256:a320721ab5a1aba0a233739394eb907f8c8da5c98c9181d1161e77a0c8e36f2d \
    --hash=sha256:a4afe79fb3de0b7097d81da19090f4df4f8d3a2b3adaa8764138aac2e44f3af1 \
    --hash=sha256:ad2cf8aa28b8c020ab2fc8287b0f823d0a7d8630784c31e9ee5edea20f406287 \
    --hash=sha256:b8512a91625c9b3da6f127803b166b629725e68af71f8184ae7e7d54686a56d6 \
    --hash=sha256:bc51efed119bc9cfdf792cdeaa4d67e8f6fcccab66ed4bfdd6bde3e59bfcbb2f \
    --hash=sha256:bdc919ead48f234740ad807933cdf545180bfbe9342c2bb451556db2ed958581 \
    --hash=sha256:bdd37121970bfd8be76c5fb069c7751683bdf373db1ed6c010162b2a130248ed \
    --hash=sha256:be8813b57049a7dc738189df53d69395eba14fb99345e0a5994914a3864c8a4b \
    --hash=sha256:c0c0b3ade1c0b13b936d7970b1d37a57acde9199dc2aecc4c336773e1d86049c \
    --hash=sha256:c47a551199eb8eb2121d4f0f15ae0f923d31350ab9280078d1e5f12b249e0026 \
    --hash=sha256:c4ffb7ebf07cfe8931028e3e4c85f0357459a3f9f9490886198848f4fa002ec8 \
    --hash=sha256:ccfcd093f13f0f0b7fdd0f198b90053bf7b2f02a3927a30e63f3ccc9df56b676 \
    --hash=sha256:d2ee202e79d8ed691ceebae8e0486bd9a2cd4794cec4824e1c99b6f5009502f6 \
    --hash=sha256:d53197da72cc091b024dd97249dfc7794d6a56530370992a5e1a08983ad9230e \
    --hash=sha256:d6dd0be5b5b189d31db7cda48b91d7e0a9795f31430b7f271219ab30f1d3ac9d \
    --hash=sha256:d88b440e37a16e651bda4c7c2b930eb586fd15ca7406cb39e211fcff3bf3017d \
    --hash=sha256:de8a88e63464af587c950061a5e6a67d3632e36df62b986892331d4620a35c01 \
    --hash=sha256:df2449253ef108a379b8b5d6b43f4b1a8e81a061d6537becd5582fba5f9196d7 \
    --hash=sha256:e1c1493fb6e50ab01d20a22826e57520f1284df32f2d8601fdd90b6304601419 \
    --hash=sha256:e1cf1972137e83c5d4c136c43ced9ac51d0e124706ee1c8aa8532c1287fa8795 \
    --hash=sha256:e2103a929dfa2fcaf9bb4e7c091983a49c9ac3b19c9061b6d5427dd7d14d81a1 \
    --hash=sha256:e56b7d45a839a697b5eb268c82a71bd8c7f6c94d6fd50c3d577fa39a9f1409f5 \
    --hash=sha256:e8afc3f2ccfa24215f8cb28dcf43f0113ac3c37c2f0f0806d8c70e4228c5cf4d \
    --hash=sha256:e8fc20152abba6b83724d7ff268c249fa196d8259ff481f3b1476383f8f24e42 \
    --hash=sha256:eaa9599de571d72e2daf60164784109f19978b327a3910d3e9de8c97b5b70cfe \
    --hash=sha256:ec15a59cf5af7be74194f7ab02d0f59a62bdcf1a537677ce67a2537c9b87fcda \
    --hash=sha256:f190daf01f13c72eac4efd5c430a8de82489d9cff23c364c3ea822545032993e \
    --hash=sha256:f34c41761022dd093b4b6896d4810782ffbabe30f2d443ff5f083e0cbbb8c737 \
    --hash=sha256:f3e98bb3798ead92273dc0e5fd0f31ade220f59a266ffd8a4f6065e0a3ce0523 \
    --hash=sha256:f42d0984e947b8adf7dd6dde396e720934d12c506ce84eea8476409563607591 \
    --hash=sha256:f71a396b3bf33ecaa1626c255855702aca4d3d9fea5e051b41ac59a9c1c41edc \
    --hash=sha256:f9e130248f4462aaa8e2552d547f36ddadbeaa573879158d721bbd33dfe4743a \
    --hash=sha256:fed51ac40f757d41b7c48425901843666a6677e3e8eb0abcff09e4ba6e664f50
    # via jinja2
psutil==7.0.0 \
    --hash=sha256:101d71dc322e3cffd7cea0650b09b3d08b8e7c4109dd6809fe452dfd00e58b25 \
    --hash=sha256:1e744154a6580bc968a0195fd25e80432d3afec619daf145b9e5ba16cc1d688e \
    --hash=sha256:1fcee592b4c6f146991ca55919ea3d1f8926497a713ed7faaf8225e174581e91 \
    --hash=sha256:39db632f6bb862eeccf56660871433e111b6ea58f2caea825571951d4b6aa3da \
    --hash=sha256:4b1388a4f6875d7e2aff5c4ca1cc16c545ed41dd8bb596cefea80111db353a34 \
    --hash=sha256:4cf3d4eb1aa9b348dec30105c55cd9b7d4629285735a102beb4441e38db90553 \
    --hash=sha256:7be9c3eba38beccb6495ea33afd982a44074b78f28c434a1f51cc07fd315c456 \
    --hash=sha256:84df4eb63e16849689f76b1ffcb36db7b8de703d1bc1fe41773db487621b6c17 \
    --hash=sha256:a5f098451abc2828f7dc6b58d44b532b22f2088f4999a937557b603ce72b1993 \
    --hash=sha256:ba3fcef7523064a6c9da440fc4d6bd07da93ac726b5733c29027d7dc95b39d99
    # via -r source/app/requirements.txt
pydantic==2.13.4 \
    --hash=sha256:45a282cde31d808236fd7ea9d919b128653c8b38b393d1c4ab335c62924d9aba \
    --hash=sha256:c40756b57adaa8b1efeeced5c196f3f3b7c435f90e84ea7f443901bec8099ef6
    # via fastapi
pydantic-core==2.46.4 \
    --hash=sha256:00c603d540afdd6b80eb39f078f33ebd46211f02f33e34a32d9f053bba711de0 \
    --hash=sha256:0186750b482eefa11d7f435892b09c5c606193ef3375bcf94aa00ae6bfb66262 \
    --hash=sha256:041bde0a48fd37cf71cab1c9d56d3e8625a3793fef1f7dd232b3ff37e978ecda \
    --hash=sha256:0c563b08bca408dc7f65f700633d8442fffb2421fc47b8101377e9fd65051ff0 \
    --hash=sha256:0cbe8b01f948de4286c74cdd6c667aceb38f5c1e26f0693b3983d9d74887c65e \
    --hash=sha256:0ce40cd7b21210e99342afafbd4d0f76d784eb5b1d60f3bdc566be4983c6c73b \
    --hash=sha256:0e96592440881c74a213e5ad528e2b24d3d4f940de2766bed9010ab1d9e51594 \
    --hash=sha256:10e17cbb10a330363733efc4d7c4d0dd827ac0909b8f6a6542298fed1ea62f29 \
    --hash=sha256:133878133d271ade3d41d1bfb2a45ec38dbdbda40bc065921c6b04e4630127e2 \
    --hash=sha256:14d4edf427bdcf950a8a02d7cb44a08614388dd6e1bdcbf4f67504fa7887da9c \
    --hash=sha256:14f4c5d6db102bd796a627bbb3a17b4cf4574b9ae861d8b7c9a9661c6dd3362d \
    --hash=sha256:17299feefe090f2caa5b8e37222bb5f663e4935a8bfa6931d4102e5df1a9f398 \
    --hash=sha256:184c081504d17f1c1066e430e117142b2c77d9448a97f7b65c6ac9fd9aee238d \
    --hash=sha256:18e5ceec2ab67e6d5f1a9085e5a24c9c4e2ac4545730bfe668680bca05e555f3 \
    --hash=sha256:19e51f073cd3df251856a8a4189fbdf1de4012c3ebacfb1884f94f1eb406079f \
    --hash=sha256:1a7dd0b3ee80d90150e3495a3a13ac34dbcbfd4f012996a6a1d8900e91b5c0fb \
    --hash=sha256:1d8ba486450b14f3b1d63bc521d410ec7565e52f887b9fb671791886436a42f7 \
    --hash=sha256:2108ba5c1c1eca18030634489dc544844144ee36357f2f9f780b93e7ddbb44b5 \
    --hash=sha256:228ee9bae8bef5b1e97ec58302f80357c37199e0d0a99174e138d28e6957b9d9 \
    --hash=sha256:23ace664830ee0bfe014a0c7bc248b1f7f25ed7ad103852c317624a1083af462 \
    --hash=sha256:2412e734dcb48da14d4e4006b82b46b74f2518b8a26ee7e58c6844a6cd6d03c4 \
    --hash=sha256:29c61fc04a3d840155ff08e475a04809278972fe6aef51e2720554e96367e34b \
    --hash=sha256:2f84c03c8607173d16b5a854ec68a2f9079ae03237a54fb506d13af47e1d018d \
    --hash=sha256:3009f12e4e90b7f88b4f9adb1b0c4a3d58fe7820f3238c190047209d148026df \
    --hash=sha256:3245406455a5d98187ec35530fd772b1d799b26667980872c8d4614991e2c4a2 \
    --hash=sha256:3447661d99f75a3683a4cf5c87da72f2161964611864dbbeac7fbb118bb4bfc0 \
    --hash=sha256:372429a130e469c9cd698925ce5fc50940b7a1336b0d82038e63d5bbc4edc519 \
    --hash=sha256:395aebd9183f9d112f569aeb5b2214d1a10a33bec8456447f7fbdfa51d38d4cd \
    --hash=sha256:3a233125ac121aa3ffba9a2b59edfc4a985a76092dc8279586ab4b71390875e7 \
    --hash=sha256:3be77f45df024d789a672ae34f8b06fb346c4f9f46ea714956660ea4862e89ac \
    --hash=sha256:3bf92c5d0e00fefaab325a4d27828fe6b6e2a21848686b5b60d2d9eeb09d76c6 \
    --hash=sha256:3ecbc122d18468d06ca279dc26a8c2e2d5acb10943bb35e36ae92096dc3b5565 \
    --hash=sha256:3fb702cd90b0446a3a1c5e470bfa0dd23c0233b676a9099ddcc964fa6ca13898 \
    --hash=sha256:428e04521a40150c85216fc8b85e8d39fece235a9cf5e383761238c7fa9b96fb \
    --hash=sha256:432c179df7874eeb73307aad2df0755e1ae0efa61ff0ea89b93e194411ae3928 \
    --hash=sha256:4a05d69cba51d852c5c3e92758653245a50c0b646ced0cf05bd793ed592839d6 \
    --hash=sha256:4c63ebc82684aa89d9a3bcbd13d515b3be44250dc68dd3bd81526c1cb31286c3 \
    --hash=sha256:4fc73cb559bdb54b1134a706a2802a4cddd27a0633f5abb7e53056268751ac6a \
    --hash=sha256:4fcbe087dbc2068af7eda3aa87634eba216dbda64d1ae73c8684b621d33f6596 \
    --hash=sha256:56cb4851bcaf3d117eddcef4fe66afd750a50274b0da8e22be256d10e5611987 \
    --hash=sha256:5855698a4856556d86e8e6cd8434bc3ac0314ee8e12089ae0e143f64c6256e4e \
    --hash=sha256:5a4330cdbc57162e4b3aa303f588ba752257694c9c9be3e7ebb11b4aca659b5d \
    --hash=sha256:5b712b53160b79a5850310b912a5ef8e57e56947c8ad690c227f5c9d7e561712 \
    --hash=sha256:5d5902252db0d3cedf8d4a1bc68f70eeb430f7e4c7104c8c476753519b423008 \
    --hash=sha256:617d7e2ca7dcb8c5cf6bcb8c59b8832c94b36196bbf1cbd1bfb56ed341905edd \
    --hash=sha256:62f875393d7f270851f20523dd2e29f082bcc82292d66db2b64ea71f64b6e1c1 \
    --hash=sha256:633147d34cf4550417f12e2b1a0383973bdf5cdfde212cb09e9a581cf10820be \
    --hash=sha256:66ce7632c22d837c9530