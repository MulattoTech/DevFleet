# DevFleet source part 075

Full-source UTF-8 byte interval [3441000, 3487500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 414118b5725464f39ece560d260aed9e3994bc835a08bf30d0d8242b8236d067

<!-- BEGIN SOURCE SLICE -->
 destructive: bool = False,
) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir():
        raise FileNotFoundError(slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    if provider_for(meta).is_vm:
        if not str(meta.get("runtime_id") or ""):
            if str(meta.get("lifecycle_status") or "") != "failed":
                raise RuntimeError(
                    "A VM project without a runtime id is not in a verified failed-provisioning state."
                )
            root = SETTINGS.runtime_root / "workspace-backups"
            backup_id = f'{validate_slug(slug)}-{time.strftime("%Y%m%d-%H%M%S")}-{uuid.uuid4().hex[:8]}'
            directory = root / backup_id
            archive = directory / f"{validate_slug(slug)}.tar.gz"
            result = create_workspace_archive(project, slug, archive, include_generated=destructive, consistency_level=consistency_level)
            manifest = write_backup_manifest(
                directory,
                slug=slug,
                project_id=str(meta.get("project_id") or ""),
                runtime={"provider": "local-workspace-archive", "runtime_id": ""},
                archive=result,
                consistency_level=consistency_level,
            )
            meta.update(
                {
                    "backup_status": "verified",
                    "backup_id": backup_id,
                    "backup_path": str(archive),
                    "backup_sha256": result["archive_sha256"],
                    "backup_manifest": str(directory / "manifest.json"),
                    "updated_at": now_iso(),
                }
            )
            _write_project_metadata(project, meta)
            return json.dumps(
                {
                    "ok": True,
                    "provider": "local-workspace-archive",
                    "backup_status": "verified",
                    "backup_id": backup_id,
                    "backup_path": str(archive),
                    "backup_sha256": result["archive_sha256"],
                    "manifest": manifest,
                }
            )
        result = VmRuntimeOperations.backup(slug, meta, consistency_level=consistency_level, destructive=destructive)
        if str(result.get("backup_status", "")).lower() != "verified":
            raise RuntimeError(
                "Host provider did not return a verified workspace backup artifact."
            )
        meta.update(
            {
                "backup_status": "verified",
                "backup_id": result.get("backup_id", ""),
                "backup_sha256": result.get("backup_sha256", ""),
                "backup_manifest_sha256": result.get("manifest_sha256", ""),
                "backup_reference": result.get("backup_reference"),
                "updated_at": now_iso(),
            }
        )
        _write_project_metadata(project, meta)
        update_lease(project, backup_time=now_iso())
        return json.dumps(
            {
                "ok": True,
                "provider": "multipass-host-agent",
                "backup_status": meta["backup_status"],
                "runtime": result,
            },
            default=str,
        )
    root = SETTINGS.runtime_root / "workspace-backups"
    backup_id = (
        f'{validate_slug(slug)}-{time.strftime("%Y%m%d-%H%M%S")}-{uuid.uuid4().hex[:8]}'
    )
    directory = root / backup_id
    archive = directory / f"{validate_slug(slug)}.tar.gz"
    result = create_workspace_archive(project, slug, archive, include_generated=destructive, consistency_level=consistency_level)
    manifest = write_backup_manifest(
        directory,
        slug=slug,
        project_id=str(meta.get("project_id") or ""),
        runtime={"provider": "docker-compose", "runtime_id": ""},
        archive=result,
        consistency_level=consistency_level,
    )
    vault = _vault_request("backup", timeout=1860)
    if (
        vault.get("local_backup_status") != "verified"
        or vault.get("vault_upload_status") != "verified"
        or vault.get("durability_level") != "vault"
    ):
        raise RuntimeError("Vault broker did not verify the encrypted backup upload.")
    meta.update(
        {
            "backup_status": "verified",
            "backup_id": backup_id,
            "backup_path": str(archive),
            "backup_sha256": result["archive_sha256"],
            "backup_manifest": str(directory / "manifest.json"),
            "updated_at": now_iso(),
        }
    )
    _write_project_metadata(project, meta)
    update_lease(project, backup_time=now_iso())
    return json.dumps(
        {
            "ok": True,
            "provider": "docker-compose",
            "backup_status": "verified",
            "backup_id": backup_id,
            "backup_path": str(archive),
            "backup_sha256": result["archive_sha256"],
            "vault_exit_code": 0,
            "vault_upload_status": "verified",
            "durability_level": "vault",
            "manifest": manifest,
        },
        default=str,
    )


def safety_backup_project(slug: str, _lock_held: bool = False) -> dict[str, Any]:
    """Stop managed writers, create a fresh stable backup, and bind its identity."""
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir() or project.is_symlink():
        raise ValueError("Project workspace is not a safe directory.")
    with contextlib.nullcontext() if _lock_held else _destructive_lock(slug):
        meta = load_authoritative_project_identity_for_mutation(project)
        transaction_id = f"destroy-{uuid.uuid4().hex}"
        meta.update(
            {
                "lifecycle_status": "destructive-quiesce-pending",
                "destructive_transaction_id": transaction_id,
                "updated_at": now_iso(),
            }
        )
        _write_project_metadata(project, meta)
        stop_project(slug)
        refreshed = load_authoritative_project_identity_for_mutation(project)
        if provider_for(refreshed).is_vm:
            if str(refreshed.get("lifecycle_status") or "").lower() == "running":
                raise RuntimeError(
                    "Destructive deletion blocked: owned VM is still running after quiesce."
                )
        elif running(project):
            raise RuntimeError(
                "Destructive deletion blocked: DevFleet-owned containers remain running after compose down."
            )
        meta = load_authoritative_project_identity_for_mutation(project)
        meta.update(
            {
                "lifecycle_status": "destructive-quiesced",
                "destructive_transaction_id": transaction_id,
                "updated_at": now_iso(),
            }
        )
        _write_project_metadata(project, meta)
        # backup_project records its verified backup in ownership-lease.json.
        # Exclude that one self-update only from the during-backup comparison;
        # the final binding still includes the complete post-backup lease.
        before = _source_state_fingerprint(
            project, include_generated=True, exclude_ownership_lease=True
        )
        # Consistency is transaction-local and explicit.  The signature check
        # keeps older focused test doubles compatible without reintroducing
        # mutable module state.
        import inspect
        backup_signature = inspect.signature(backup_project)
        if "consistency_level" in backup_signature.parameters:
            result = json.loads(backup_project(slug, consistency_level="quiesced", destructive=True))
        else:
            result = json.loads(backup_project(slug))
        result.setdefault("consistency_level", "quiesced")
        meta = load_authoritative_project_identity_for_mutation(project)
        after, bound_fingerprint = _source_state_fingerprint(
            project,
            include_generated=True,
            exclude_ownership_lease=True,
            return_full_lease_variant=True,
        )
        if before != after:
            raise RuntimeError(
                "Destructive deletion blocked: workspace changed during the safety backup; no deletion was performed."
            )
        backup_id, backup_sha, status = _safety_backup_fields(result, meta)
        if (
            status != "verified"
            or not backup_id
            or not re.fullmatch(r"[0-9a-f]{64}", backup_sha.lower())
        ):
            raise RuntimeError(
                "Destructive deletion blocked: fresh safety backup was not cryptographically verified."
            )
        provider = provider_for(meta)
        if provider.is_vm:
            reference = result.get("backup_reference") or (result.get("runtime") or {}).get("backup_reference") or meta.get("backup_reference")
            from .host_control import validate_backup_reference
            checked_reference = validate_backup_reference(reference, project_id=str(meta.get("project_id") or ""), slug=slug, runtime_id=str(meta.get("runtime_id") or ""))
            if checked_reference["archive_sha256"].lower() != backup_sha.lower():
                raise RuntimeError("Destructive deletion blocked: provider backup reference hash changed after verification.")
            meta["backup_reference"] = checked_reference
        else:
            archive = Path(str(result.get("backup_path") or meta.get("backup_path") or ""))
            if not archive.is_file():
                raise RuntimeError("Destructive deletion blocked: fresh safety backup archive is unavailable.")
            verified = validate_archive(archive, slug)
            if verified.get("archive_sha256", "").lower() != backup_sha.lower():
                raise RuntimeError("Destructive deletion blocked: fresh safety backup hash changed after verification.")
        binding = {
            "transaction_id": transaction_id,
            "project_id": str(meta.get("project_id") or ""),
            "runtime_id": str(meta.get("runtime_id") or ""),
            "backup_id": backup_id,
            "backup_sha256": backup_sha.lower(),
            "source_state_fingerprint": bound_fingerprint,
            "fingerprint_policy": {
                "schema_version": FINGERPRINT_POLICY_VERSION,
                "algorithm": FINGERPRINT_ALGORITHM,
                "include_generated": True,
                "ignored_directories": [],
                "result": "verified",
            },
            "created_at": now_iso(),
        }
        meta.update(
            {
                "lifecycle_status": "destructive-backup-verified",
                "destructive_backup_binding": binding,
                "updated_at": now_iso(),
            }
        )
        _write_project_metadata(project, meta)
        return {"result": result, "binding": binding, "meta": meta}


def list_backups(slug: str) -> list[dict[str, Any]]:
    slug = validate_slug(slug)
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    project_id = str(meta.get("project_id") or "")
    if provider_for(meta).is_vm and str(meta.get("runtime_id") or ""):
        return VM_RUNTIME.list_backups(slug, meta)
    root = SETTINGS.runtime_root / "workspace-backups"
    items = []
    if root.is_dir():
        for directory in sorted(
            (p for p in root.iterdir() if p.is_dir()), reverse=True
        ):
            manifest_file = directory / "manifest.json"
            try:
                manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if manifest.get("slug") != slug or (
                project_id and str(manifest.get("project_id") or "") != project_id
            ):
                continue
            workspace = (
                manifest.get("workspace")
                if isinstance(manifest.get("workspace"), dict)
                else {}
            )
            archive = Path(str(workspace.get("archive_path") or ""))
            digest = str(workspace.get("archive_sha256") or "")
            eligible = archive.is_file()
            if eligible:
                try:
                    eligible = (
                        validate_archive(archive, slug).get("archive_sha256") == digest
                    )
                except (OSError, ValueError, tarfile.TarError):
                    eligible = False
            items.append(
                {
                    "backup_id": directory.name,
                    "created_at": manifest.get("created_at", ""),
                    "project_id": manifest.get("project_id", ""),
                    "provider": str(
                        (manifest.get("runtime") or {}).get("provider")
                        or "docker-compose"
                    ),
                    "runtime_id": str(
                        (manifest.get("runtime") or {}).get("runtime_id") or ""
                    ),
                    "archive_path": str(archive),
                    "archive_bytes": archive.stat().st_size if archive.is_file() else 0,
                    "archive_sha256": digest,
                    "sha_verified": eligible,
                    "restore_eligible": eligible,
                    "reason": (
                        ""
                        if eligible
                        else "Archive is missing or failed SHA/path verification."
                    ),
                    "status": "eligible" if eligible else "invalid",
                    "manifest_path": str(manifest_file),
                }
            )
    return items


def restore_backup(
    slug: str,
    backup_id: str,
    confirm_restore: bool = False,
    allow_overwrite: bool = False,
) -> dict[str, Any]:
    slug = validate_slug(slug)
    if "/" in backup_id or "\\" in backup_id or backup_id in {".", ".."}:
        raise ValueError("Invalid backup identifier.")
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    project_id = str(meta.get("project_id") or "")
    if provider_for(meta).is_vm and str(meta.get("runtime_id") or ""):
        if not confirm_restore:
            raise ValueError("Backup restore requires explicit confirmation.")
        if not allow_overwrite:
            raise ValueError(
                "VM backup restore replaces the current workspace and requires explicit overwrite confirmation."
            )
        result = VM_RUNTIME.restore_backup(slug, meta, backup_id, confirm_restore=True)
        restored = {
            **meta,
            "backup_status": "verified",
            "backup_id": backup_id,
            "backup_sha256": str(result.get("backup_sha256") or ""),
            "updated_at": now_iso(),
            "last_restore_at": now_iso(),
        }
        _write_project_metadata(project, restored)
        return {
            "ok": True,
            "provider": "multipass-host-agent",
            "backup_id": backup_id,
            "backup_sha256": restored["backup_sha256"],
            "project": restored,
            "restore": result,
        }
    directory = (SETTINGS.runtime_root / "workspace-backups" / backup_id).resolve()
    root = (SETTINGS.runtime_root / "workspace-backups").resolve()
    if directory.parent != root or not directory.is_dir():
        raise FileNotFoundError(backup_id)
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    workspace = (
        manifest.get("workspace") if isinstance(manifest.get("workspace"), dict) else {}
    )
    archive = Path(str(workspace.get("archive_path") or ""))
    if (
        manifest.get("slug") != slug
        or str(manifest.get("project_id") or "") != project_id
    ):
        raise ValueError("Backup identity does not match this project.")
    if not confirm_restore:
        raise ValueError("Backup restore requires explicit confirmation.")
    verified = validate_archive(archive, slug)
    if verified.get("archive_sha256") != str(workspace.get("archive_sha256") or ""):
        raise ValueError("Backup archive hash does not match its manifest.")
    if project.exists() and any(project.iterdir()):
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
            reason = "declared login body exceeds limit" 