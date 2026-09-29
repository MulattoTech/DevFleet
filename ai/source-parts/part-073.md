# DevFleet source part 073

Full-source UTF-8 byte interval [3348000, 3394500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 0324e034c2a6ba193864369c2e8638848bd13e2740c1afec64c7000a5d327e78

<!-- BEGIN SOURCE SLICE -->
elected_isolation == "vm":
            if operation_context:
                operation_context.update(
                    55, "Validating host capacity and creating dedicated VM", "creating"
                )
            # The local scaffold is authoritative. Provision the VM without a clone,
            # then import and verify the final scaffold so generated/template changes
            # cannot diverge from the VM workspace.
            vm_result = VmRuntimeOperations.ensure(slug, {**meta, "git_url": ""})
            runtime_id = vm_result.get("runtime_id") or vm_result.get("vm_name", "")
            imported = import_project_workspace(
                slug,
                str(runtime_id),
                source_vm=SETTINGS.node_name,
                project_id=project_id,
            )
            if (
                imported.get("ok") is False
                or imported.get("workspace_preserved") is not True
            ):
                raise RuntimeError(
                    "Host agent did not verify the new VM workspace import."
                )
            vm_result = {**vm_result, **imported}
            meta.update(
                runtime_metadata(
                    provider_for(meta),
                    status="ready",
                    runtime_id=runtime_id,
                    runtime_address=vm_result.get("address", ""),
                    provisioning_status="ready",
                    health_status="unknown",
                    health_scope="workspace-ready-not-app-healthy",
                    lifecycle_status="ready",
                )
            )
            meta["workspace_host"] = str(vm_result.get("address") or runtime_id)
            meta["updated_at"] = now_iso()
            _write_project_metadata(project, meta)
            meta["ssh_alias"] = str(runtime_id)
            sync_project_vm_ssh_alias(slug, str(runtime_id), project_id=project_id)
            _write_project_metadata(project, meta)
            if operation_context:
                operation_context.set_runtime(str(runtime_id))
            if operation_context:
                operation_context.update(
                    92,
                    "Dedicated VM workspace ready; application health remains unverified",
                    "verify",
                )
        else:
            meta["provisioning_status"] = "ready"
            meta["lifecycle_status"] = "ready"
            meta["health_status"] = "unknown"
            meta["health_scope"] = "not-checked"
            meta["updated_at"] = now_iso()
            _write_project_metadata(project, meta)
            if operation_context:
                operation_context.update(
                    92, "Container runtime metadata finalized", "verify"
                )
            update_lease(project, active=False, clean_shutdown=True)
        return meta
    except Exception as exc:
        if (
            project.exists()
            and project.resolve().parent == SETTINGS.workspaces.resolve()
        ):
            # Preserve a failed VM workspace and metadata for reconciliation. A
            # failed host operation must never be mistaken for a clean rollback.
            meta_path = metadata_path(project)
            if selected_isolation == "vm" and meta_path.is_file():
                try:
                    failed = read_project_metadata(project).value
                    failed.update(
                        {
                            "lifecycle_status": "failed",
                            "provisioning_status": "failed",
                            "health_status": "unknown",
                            "last_error": str(exc),
                            "updated_at": now_iso(),
                        }
                    )
                    _write_project_metadata(project, failed)
                except Exception:
                    pass
            elif worktree_source:
                run(
                    ["git", "worktree", "remove", "--force", str(project)],
                    cwd=safe_child(SETTINGS.workspaces, worktree_source),
                    check=False,
                    timeout=120,
                )
            elif project.is_dir() and selected_isolation != "vm":
                shutil.rmtree(project)
        raise


def _migration_snapshot_path(slug: str) -> Path:
    root = SETTINGS.runtime_root / "runtime-migrations"
    root.mkdir(parents=True, exist_ok=True)
    return (
        root
        / f'{validate_slug(slug)}-{time.strftime("%Y%m%d-%H%M%S")}-{uuid.uuid4().hex[:8]}.json'
    )


def _local_migration_backup(project: Path, slug: str, snapshot: Path) -> dict[str, str]:
    archive = snapshot.with_suffix(".workspace.tar.gz")
    result = create_workspace_archive(project, slug, archive)
    return {
        "path": str(archive),
        "sha256": str(result["archive_sha256"]),
        "size_bytes": str(result["archive_bytes"]),
        "files": str(result["files"]),
    }


def _restore_local_migration_backup(
    project: Path, slug: str, backup: dict[str, str]
) -> dict[str, Any]:
    archive = Path(str(backup.get("path") or ""))
    if not archive.is_file():
        raise FileNotFoundError("Migration backup archive is unavailable.")
    _verified_sha256(archive, str(backup.get("sha256") or ""))
    return restore_workspace_archive(archive, project, slug)


def assign_project_runtime(
    slug: str,
    runtime_isolation: str = "container",
    resource_profile: str = "",
    resource_limits: dict[str, Any] | None = None,
    operation_context: Any | None = None,
) -> dict[str, Any]:
    """Serialize the complete runtime-adoption transaction for one project."""
    slug = validate_slug(slug)
    with _destructive_lock(slug):
        return _assign_project_runtime_locked(
            slug,
            runtime_isolation,
            resource_profile,
            resource_limits,
            operation_context,
        )


def _assign_project_runtime_locked(
    slug: str,
    runtime_isolation: str = "container",
    resource_profile: str = "",
    resource_limits: dict[str, Any] | None = None,
    operation_context: Any | None = None,
) -> dict[str, Any]:
    """Assign an existing workspace to a supported runtime without moving its source directory.

    The source workspace remains on the current DevFleet VM. Container assignment
    updates the existing Compose project in place. VM assignment provisions a
    project VM through the authenticated host agent, imports the source workspace
    from the current VM, and only then persists the VM runtime metadata.
    """
    slug = validate_slug(slug)
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir() or project.is_symlink():
        raise ValueError("Existing project must be a safe workspace directory.")
    selected = str(runtime_isolation or "container").strip().lower()
    if selected not in {"container", "vm"}:
        raise ValueError("Environment type must be container or vm.")
    metadata_file = metadata_path(project)
    try:
        metadata_record = read_project_metadata(project)
        metadata_present = True
        previous_metadata_bytes = metadata_record.raw
        previous_raw = metadata_record.value
    except FileNotFoundError:
        metadata_present = False
        previous_metadata_bytes = b""
        previous_raw = {}
    except (OSError, ValueError, UnicodeError) as exc:
        raise ValueError(
            "Project metadata is malformed; repair it before changing the environment."
        ) from exc
    if not isinstance(previous_raw, dict):
        raise ValueError(
            "Project metadata must be a JSON object; repair it before changing the environment."
        )
    previous = load_authoritative_project_identity_for_mutation(
        project, allow_legacy_migration=True
    )
    previous_provider = provider_for(previous)
    previous_running = False
    command_readiness = project_command_readiness(project, previous_raw)
    if selected == "vm" and not command_readiness["ready"]:
        details = []
        if command_readiness["missing_required"]:
            details.append(
                "missing " + ", ".join(command_readiness["missing_required"])
            )
        if command_readiness["invalid_required"]:
            details.append(
                "unsafe or unsupported "
                + ", ".join(command_readiness["invalid_required"])
            )
        raise ValueError(
            "Dedicated VM lifecycle commands are not ready: " + "; ".join(details)
        )
    if previous_provider.is_vm:
        previous_running = str(previous.get("lifecycle_status") or "") == "running"
    else:
        previous_running = running(project)
    previous_lifecycle = "running" if previous_running else "stopped"
    previous_profile = str(previous.get("resource_profile") or "standard").lower()
    if resource_limits:
        selected_profile, limits = _resource_selection(
            "",
            resource_limits,
            selected,
            str(previous.get("project_scale") or ""),
            str(previous.get("intent") or ""),
            str(previous.get("project_kind") or ""),
            str(previous.get("language") or ""),
            str(previous.get("framework") or ""),
        )
    elif (
        not resource_profile
        and previous_profile == "custom"
        and isinstance(previous.get("resource_limits"), dict)
    ):
        selected_profile = "custom"
        limits = custom_resource_metadata(
            previous["resource_limits"], runtime_type=selected
        )
    else:
        selected_profile, limits = _resource_selection(
            resource_profile or previous_profile,
            None,
            selected,
            str(previous.get("project_scale") or ""),
            str(previous.get("intent") or ""),
            str(previous.get("project_kind") or ""),
            str(previous.get("language") or ""),
            str(previous.get("framework") or ""),
        )
    if selected == "vm":
        if (
            previous_provider.is_vm
            and str(previous.get("resource_profile") or selected_profile)
            != selected_profile
        ):
            raise ValueError(
                "Dedicated VM resources are fixed after creation; keep the current profile or create a new VM environment."
            )
        capacity_result = get_host_capacity()
        capacity = (
            capacity_result.get("capacity", capacity_result)
            if isinstance(capacity_result, dict)
            else {}
        )
        allowed, reason = capacity_allows(capacity, limits)
        if not allowed:
            raise ValueError(reason)
    if (
        selected == "container"
        and previous_provider.is_vm
        and not str(previous.get("runtime_id") or "")
    ):
        raise ValueError(
            "Dedicated VM metadata has no runtime identity; export is blocked until the VM is reconciled."
        )
    compose = compose_file(project)
    if selected == "container" and compose is None:
        raise ValueError(
            "This workspace has no supported Compose configuration for a container environment."
        )
    snapshot = _migration_snapshot_path(slug)
    override_file = resource_override_path(project)
    override_present = override_file.is_file()
    override_text = (
        override_file.read_text(encoding="utf-8") if override_present else ""
    )
    lease_file = project / ".devfleet/ownership-lease.json"
    lease_present = lease_file.is_file()
    lease_text = lease_file.read_text(encoding="utf-8") if lease_present else ""
    migration = {
        "schema_version": 4,
        "slug": slug,
        "project_id": str(previous.get("project_id") or ""),
        "source_runtime": detect_runtime(slug),
        "target_runtime": {
            "runtime_isolation": selected,
            "resource_profile": selected_profile,
            "resource_limits": limits,
        },
        "workspace": str(project),
        "created_at": now_iso(),
        "state": "prepared",
        "previous_metadata": previous_raw,
        "previous_metadata_b64": (
            base64.b64encode(previous_metadata_bytes).decode("ascii")
            if metadata_present
            else ""
        ),
        "previous_resource_override": {
            "present": override_present,
            "text": override_text,
        },
        "previous_lease": {"present": lease_present, "text": lease_text},
        "previous_lifecycle": previous_lifecycle,
        "backup_status": "pending",
        "runtime_id": "",
        "fallback_runtime": previous.get("runtime_id", ""),
        "command_resolution": command_readiness,
    }
    atomic_json(snapshot, migration)
    old_runtime_id = str(previous.get("runtime_id") or "")
    new_runtime_id = ""
    stopped_for_transition = False
    local_backup: dict[str, str] = {}
    source_promoted = False
    previous_workspace_path = ""
    source_vm_started_for_export = False
    source_vm_stopped_for_transition = False
    destination_started = False
    rollback_errors: list[str] = []
    backup_result: dict[str, Any] = {}
    imported: dict[str, Any] = {}
    try:
        if operation_context:
            operation_context.update(12, "Creating a rollback snapshot", "snapshot")
        # Preserve the exact pre-migration workspace before upgrading legacy
        # ownership metadata.  This archive plus previous_metadata_bytes is the
        # rollback boundary if the durable Vault backup or any later step fails.
        local_backup = _local_migration_backup(project, slug, snapshot)
        migration["backup_status"] = "verified-local-archive"
        migration["backup_artifact"] = local_backup
        migration["local_backup_completed_at"] = now_iso()
        atomic_json(snapshot, migration)
        if int(previous.get("schema_version") or 0) == 2:
            upgraded = {
                **previous,
                "schema_version": 5,
                "managed_by": "devfleet",
                "slug": slug,
                "identity": slug,
                "deployment_id": str(
                    previous.get("deployment_id") or SETTINGS.deployment_id
                ),
                "updated_at": now_iso(),
            }
            if not upgraded["deployment_id"]:
                raise ValueError(
                    "Legacy project migration requires the current deployment identity."
                )
            if not provider_for(upgraded).is_vm:
                upgraded["runtime_id"] = compose_name(slug)
                upgraded["host_id"] = SETTINGS.node_name
            _write_project_metadata(project, upgraded)
            previous = load_authoritative_project_identity_for_mutation(project)
        backup_result = json.loads(backup_project(slug))
        if str(backup_result.get("backup_status") or "").lower() != "verified":
            raise RuntimeError("Migration backup was not verified.")
        previous = load_authoritative_project_identity_for_mutation(project)
        migration["backup_status"] = "verified-local-and-vault"
        migration["backup_result"] = backup_result
        migration["backup_completed_at"] = now_iso()
        atomic_json(snapshot, migration)
        if selected == "vm":
            if previous_provider.is_vm:
                candidate = {
                    **previous,
                    "resource_profile": selected_profile,
                    "resource_limits": limits,
                }
                result = {
                    "runtime_id": old_runtime_id,
                    "address": str(previous.get("runtime_address") or ""),
                    "state": "ready",
                }
            else:
                if previous_running:
                    if operation_context:
                        operation_context.update(
                            28,
                            "Stopping the old container runtime before import",
                            "source-runtime",
                        )
                    stop_project(slug)
                    stopped_for_transition = True
                # Adoption imports the existing local workspace into the new VM.  Do not
                # clone the repository first: an existing project may have uncommitted
                # work, and a pre-cloned workspace would make the import correctly refuse
                # the target as non-empty.
                candidate = {
                    **previous,
                    **command_readiness["resolved_commands"],
                    "git_url": "",
                    "runtime_isolation": "vm",
                    "runtime_type": "vm",
                    "runtime_provider": "multipass-host-agent",
                    "resource_profile": selected_profile,
                    "resource_limits": limits,
                    "runtime_status": "provisioning",
                    "lifecycle_status": "provisioning",
                    "provisioning_status": "pending",
                    "health_status": "unknown",
                    "runtime_id": "",
                    "runtime_address": "",
                    "host_id": SETTINGS.expected_host_name or SETTINGS.node_name,
                    "gpu_enabled": False,
                    "last_error": "",
                    "updated_at": now_iso(),
                }
                # Stage self-contained, trusted command metadata before import so the
                # destination can run fixed Host Agent operations. Rollback restores the
                # exact legacy bytes captured above.
                _write_project_metadata(project, candidate)
                if operation_context:
                    operation_context.update(
                        42,
                        "Checking host capacity and creating the dedicated VM",
                        "provision",
                    )
                result = VmRuntimeOperations.ensure(slug, candidate)
                new_runtime_id = str(
                    result.get("runtime_id") or result.get("vm_name") or ""
                )
                if not new_runtime_id:
                    raise RuntimeError("Host agent created no runtime identity.")
                if operation_context:
                    operation_context.set_runtime(new_runtime_id)
                if operation_context:
                    operation_context.update(
                        72,
                        "Importing the existing workspace into the dedicated VM",
                        "workspace-import",
                    )
                imported = import_project_workspace(
                    slug,
                    new_runtime_id,
                    source_vm=SETTINGS.node_name,
                    project_id=str(candidate.get("project_id") or ""),
                )
                if (
                    imported.get("ok") is False
                    or imported.get("workspace_preserved") is not True
                ):
                    raise RuntimeError(
                        "Host agent did not verify the imported workspace."
                    )
                if (
                    imported.get("source_archive_sha256")
                    and imported.get("target_archive_sha256")
                    and imported["source_archive_sha256"]
                    != imported["target_archive_sha256"]
                ):
                    raise RuntimeError(
                        "Imported workspace archive hashes do not match."
                    )
                migration["import_verified"] = True
                migration["import_result"] = imported
                atomic_json(snapshot, migration)
                result = {**result, **imported}
                candidate.update(
                    runtime_metadata(
                        provider_for(candidate),
                        status="ready" if previous_running else "stopped",
                        runtime_id=str(
                            result.get("runtime_id") or old_runtime_id or new_runtime_id
                        ),
                        runtime_address=str(
                            result.get("address")
                            or previous.get("runtime_address")
                            or ""
                        ),
                        provisioning_status="ready",
                        health_status="unknown",
                        lifecycle_status="ready" if previous_running else "stopped",
                    )
                )
                candidate["health_scope"] = (
                    "workspace-ready-not-app-healthy"
                    if previous_running
                    else "not-checked-stopped"
                )
                candidate["resource_profile"] = selected_profile
                candidate["resource_limits"] = limits
                candidate["ssh_alias"] = (
                    str(candidate.get("runtime_id") or "devfleet-primary")
                    if selected == "vm"
                    else "devfleet-primary"
                )
                candidate["previous_runtime"] = {
                    "runtime_provider": previous_provider.name,
                    "runtime_type": previous_provider.runtime_type,
                    "runtime_id": old_runtime_id,
                    "was_running": previous_running,
                }
                candidate["runtime_migration_snapshot"] = str(snapshot)
                candidate["updated_at"] = now_iso()
                candidate["last_error"] = ""
                if selected == "vm":
                    sync_project_vm_ssh_alias(
                        slug,
                        str(candidate.get("runtime_id") or ""),
                        project_id=str(candidate.get("project_id") or ""),
                    )
                _write_project_metadata(project, candidate)
        else:
            if previous_provider.is_vm:
                if operation_context:
                    operation_context.update(
                        42,
                        "Exporting the verified VM workspace back to the source VM",
                        "vm-export",
                    )
                if not previous_running:
                    VmRuntimeOperations.start(slug, previous)
                    source_vm_started_for_export = True
                exported = VM_RUNTIME.export_to_source(
                    slug, previous, source_vm=SETTINGS.node_name, replace_source=True
                )
                migration["vm_export"] = exported
                source_promoted = bool(
                    exported.get("state") == "verified"
                    and exported.get("workspace_path")
                )
                previous_workspace_path = str(
                    exported.get("previous_workspace_path") or ""
                )
                migration["source_promoted"] = source_promoted
                migration["previous_workspace_path"] = previous_workspace_path
                atomic_json(snapshot, migration)
                if operation_context:
                    operation_context.update(
                        58,
                        "Stopping the old dedicated VM after verified export",
                        "source-runtime",
                    )
                stop_project(slug)
                source_vm_stopped_for_transition = True
                # The host agent has promoted the VM copy to the canonical source path.
                project = safe_child(SETTINGS.workspaces, slug)
                previous = load_meta(project)
                compose = compose_file(project)
                if compose is None:
                    raise ValueError(
                        "The exported VM workspace has no supported Compose configuration."
                    )
            if operation_context:
                operation_context.update(
                    68,
                    "Applying the selected container resources to the existing Compose project",
                    "container-runtime",
                )
            override = write_resource_override(project, compose, limits)
            if override is None:
                raise ValueError(
                    "Compose services could not be read; no container resource override was written."
                )
            fallback = {
                "runtime_provider": previous_provider.name,
                "runtime_type": previous_provider.runtime_type,
                "runtime_id": old_runtime_id,
                "runtime_address": str(previous.get("runtime_address") or ""),
                "was_running": previous_running,
                "lifecycle_status": previous_lifecycle,
                "workspace_path": (
                    str(exported.get("workspace_path") or "")
                    if previous_provider.is_vm
                    else str(project)
                ),
                "previous_workspace_path": previous_workspace_path,
            }
            candidate = {
                **previous,
                "schema_version": 5,
                "runtime_isolation": "container",
                "runtime_type": "container",
                "runtime_provider": "docker-compose",
                "runtime_status": "container-ready" if previous_running else "stopped",
                "lifecycle_status": "ready" if previous_running else "stopped",
                "provisioning_status": "ready",
                "health_status": "unknown",
                "health_scope": (
                    "not-checked" if previous_running else "not-checked-stopped"
                ),
                "resource_profile": selected_profile,
                "resource_limits": limits,
                "runtime_id": compose_name(slug),
                "runtime_address": "",
                "host_id": SETTINGS.node_name,
                "gpu_enabled": False,
                "runtime_migration_snapshot": str(snapshot),
                "previous_environment": fallback,
                "last_error": "",
                "updated_at": now_iso(),
            }
            if (
                previous_running
                and str(previous.get("resource_profile") or previous_profile)
                != selected_profile
            ):
                candidate["runtime_status"] = "restart-required"
            _write_project_metadata(project, candidate)
        if previous_running:
            if operation_context:
                operation_context.update(
                    78,
                    "Starting and checking the destination runtime",
                    "destination-start",
                )
            start_project(slug)
            destination_started = True
            runtime_check = runtime_health(slug)
            if not bool(runtime_check.get("ok", runtime_check.get("healthy", False))):
                raise RuntimeError(
                    f"Destination runtime health check failed: {runtime_check}"
                )
            app_output = health_project(slug)
            candidate = load_meta(project)
            if str(candidate.get("health_status") or "") != "healthy":
                raise RuntimeError("Destination application health was not verified.")
            destination_health = "healthy"
        else:
            if selected == "vm":
                # The destination application was never started. Preserve a stopped
                # source lifecycle by stopping only the VM, not by requiring an
                # application stop command that had no services to stop.
                VmRuntimeOperations.stop(slug, candidate)
            candidate = load_meta(project)
            candidate.update(
                {
                    "lifecycle_status": "stopped",
                    "runtime_status": "stopped",
                    "health_status": "unknown",
                    "health_scope": "not-checked-stopped",
                    "updated_at": now_iso(),
                }
            )
            _write_project_metadata(project, candidate)
            update_lease(project, active=False, clean_shutdown=True)
            runtime_check = {
                "ok": True,
                "healthy": False,
                "state": "stopped",
                "preserved_previous_lifecycle": True,
            }
            app_output = "Destination intentionally left stopped to preserve the prior lifecycle state."
            destination_health = "not-run-stopped"
        migration["state"] = "verified"
        migration["destination_runtime"] = runtime_check
        migration["destination_application_health"] = destination_health
        migration["destination_started"] = destination_started
        migration["runtime_id"] = str(
            new_runtime_id or old_runtime_id or candidate.get("runtime_id") or ""
        )
        atomic_json(snapshot, migration)
        migration["state"] = "completed"
        migration["completed_at"] = now_iso()
        atomic_json(snapshot, migration)
        if operation_context:
            operation_context.update(94, "Environment assignment verified", "verify")
        return {
            "ok": True,
            "project": candidate,
            "migration_snapshot": str(snapshot),
            "backup_status": "verified",
            "workspace_preserved": True,
            "runtime": (
                result
                if selected == "vm"
                else {
                    "provider": "docker-compose",
                    "resource_override": str(resource_override_path(project)),
                }
            ),
            "runtime_health": runtime_check,
            "application_health": destination_health,
            "application_health_output": (
                app_output[-2000:]
                if isinstance(app_output, str)
                else str(app_output)[-2000:]
            ),
        }
    except Exception as exc:
        migration["state"] = "rollback-required"
        migration["error"] = str(exc)
        migration["failed_at"] = now_iso()
        migration["runtime_id"] = str(new_runtime_id)
        atomic_json(snapshot, migration)
        # A VM retained after a failed migration is a first-class fallback.  It is
        # never silently deleted when the previous environment was a VM.
        if new_runtime_id and not previous_provider.is_vm:
            try:
                cleanup_hash = str(local_backup.get("sha256") or "")
                destroy_project_vm(
                    slug,
                    slug,
                    f"DESTROY {slug}",
                    backup_verified=True,
                    backup_id=str(backup_result.get("backup_id") or f"cleanup-{slug}"),
                    backup_sha256=str(backup_result.get("backup_sha256") or ""),
                    cleanup_only=True,
                    cleanup_stage=(
                        "post-import"
                        if imported.get("workspace_preserved") is True
                        else "pre-import"
                    ),
                    local_archive_sha256=cleanup_hash,
                    import_archive_sha256=str(
                        imported.get("archive_sha256")
                        or imported.get("source_archive_sha256")
                        or ""
                    ),
                    runtime_id=new_runtime_id,
                    project_id=str(previous.get("project_id") or ""),
                )
                migration["cleanup"] = (
                    "partially-created VM removed after import failure"
                )
            except Exception as cleanup_exc:
                migration["cleanup_required"] = True
                migration["cleanup_error"] = str(cleanup_exc)
                migration["cleanup_note"] = (
                    "Dedicated VM preserved for explicit host-agent reconciliation after migration failure."
                )
                rollback_errors.append(f"cleanup: {cleanup_exc}")
        if source_promoted:
            try:
                if previous_workspace_path:
                    restored = VM_RUNTIME.restore_previous_source(
                        slug,
                        previous,
                        source_vm=SETTINGS.node_name,
                        previous_workspace_path=previous_workspace_path,
                    )
                    if str(restored.get("state") or "") != "restored":
                        raise RuntimeError(
                            "Host agent did not confirm atomic previous-workspace restoration."
                        )
                    migration["workspace_restored"] = True
                    migration["previous_workspace_consumed"] = True
                    migration["previous_workspace_restore"] = restored
                else:
                    _restore_local_migration_backup(project, slug, local_backup)
                    migration["workspace_restored"] = True
                    migration["workspace_restore_fallback"] = (
                        "local-archive-no-previous-path"
                    )
            except Exception as restore_workspace_exc:
                rollback_errors.append(f"workspace: {restore_workspace_exc}")
        if (
            stopped_for_transition
            or source_vm_stopped_for_transition
            or source_vm_started_for_export
        ):
            try:
                if previous_running:
                    if previous_provider.is_vm:
                        VmRuntimeOperations.start(slug, previous)
                    else:
                        start_project(slug)
                elif previous_provider.is_vm and source_vm_started_for_export:
                    VmRuntimeOperations.stop(slug, previous)
            except Exception as restore_exc:
                rollback_errors.append(f"runtime: {restore_exc}")
        # Restore the exact legacy/control bytes only after the previous runtime
        # state is recovered. Public lifecycle entrypoints intentionally reject
        # legacy metadata and therefore cannot be used after this boundary.
        try:
            if metadata_present:
                _write_project_metadata_bytes(project, previous_metadata_bytes)
        except Exception as metadata_restore_exc:
            rollback_errors.append(f"metadata: {metadata_restore_exc}")
        try:
            if override_present:
                atomic_text(override_file, override_text)
            elif override_file.exists():
                override_file.unlink()
        except Exception as override_restore_exc:
            rollback_errors.append(f"override: {override_restore_exc}")
        try:
            if lease_present:
                atomic_text(lease_file, lease_text)
            elif lease_file.exists():
                lease_file.unlink()
        except Exception as lease_restore_exc:
            rollback_errors.append(f"lease: {lease_restore_exc}")
        if rollback_errors:
            migration["state"] = "rollback-incomplete"
            migration["rollback_errors"] = rollback_errors
            migration["failure_state"] = {
                "previous_lifecycle": previous_lifecycle,
                "destination_started": destination_started,
                "source_promoted": source_promoted,
                "requires_reconciliation": True,
            }
        else:
            migration["state"] = "rolled-back"
            migration["rollback_completed_at"] = now_iso()
        atomic_json(snapshot, migration)
        raise


def _verified_sha256(path: Path, expected: str) -> str:
    if not path.is_file() or path.is_symlink():
        raise FileNotFoundError(f"Recovery artifact is unavailable: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    if (
        not re.fullmatch(r"[0-9a-f]{64}", str(expected or ""))
        or actual != str(expected).lower()
    ):
        raise ValueError(f"Recovery artifact SHA-256 mismatch: {path}")
    return actual


def reconcile_failed_migration(
    slug: str, migration_snapshot: str, confirm_phrase: str = ""
) -> dict[str, Any]:
    """Reconcile one known rollback-incomplete container-to-VM transaction."""
    slug = validate_slug(slug)
    if confirm_phrase != f"RECONCILE {slug}":
        raise ValueError(
            "Failed-migration reconciliation requires the exact project confirmation phrase."
        )
    root = (SETTINGS.runtime_root / "runtime-migrations").resolve()
    snapshot = Path(str(migration_snapshot or "")).resolve()
    if (
        not snapshot.is_relative_to(root)
        or snapshot.parent != root
        or not re.fullmatch(
            rf"{re.escape(slug)}-[0-9]{{8}}-[0-9]{{6}}-[0-9a-f]{{8}}\.json",
            snapshot.name,
        )
    ):
        raise ValueError(
            "Migration snapshot path is outside the managed runtime-migrations directory."
        )
    data = _json_object(snapshot)
    if data.get("state") != "rollback-incomplete" or not data.get("cleanup_required"):
        raise ValueError(
            "Only a cleanup-required rollback-incomplete migration may be reconciled."
        )
    if str(data.get("slug") or "") != slug:
        raise ValueError(
            "Migration snapshot slug does not match the requested project."
        )
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    if provider_for(meta).is_vm:
        raise ValueError(
            "Source project metadata was not restored to the container environment."
        )
    if running(project):
        raise ValueError(
            "Source container must remain stopped during failed-migration reconciliation."
        )
    runtime_id = str(data.get("runtime_id") or "")
    expected_runtime = f"devfleet-project-{slug}"
    if runtime_id != expected_runtime:
        raise ValueError(
            "Migration snapshot runtime identity is not the deterministic project VM name."
        )
    backup = (
        data.get("backup_result") if isinstance(data.get("backup_result"), dict) else {}
    )
    local = (
        data.get("backup_artifact")
        if isinstance(data.get("backup_artifact"), dict)
        else {}
    )
    if str(backup.get("backup_status") or "").lower() != "verified":
        raise ValueError(
            "Migration snapshot does not contain a verified provider-aware backup."
        )
    provider_sha = _verified_sha256(
        Path(str(backup.get("backup_path") or "")),
        str(backup.get("backup_sha256") or ""),
    )
    local_sha = _verified_sha256(
        Path(str(local.get("path") or "")), str(local.get("sha256") or "")
    )
    result = destroy_project_vm(
        slug,
        slug,
        f"DESTROY {slug}",
        backup_verified=True,
        backup_id=str(backup.get("backup_id") or ""),
        backup_sha256=provider_sha,
        cleanup_only=True,
        cleanup_stage="post-import",
        local_archive_sha256=local_sha,
        import_archive_sha256=str(
            (data.get("import_result") or {}).get("archive_sha256") or ""
        ),
        runtime_id=runtime_id,
        project_id=str(data.get("project_id") or meta.get("project_id") or ""),
    )
    reconciliation = {
        "schema_version": 1,
        "slug": slug,
        "project_id": str(data.get("project_id") or meta.get("project_id") or ""),
        "runtime_id": runtime_id,
        "original_snapshot": str(snapshot),
        "original_snapshot_state": str(data.get("state")),
        "state": "reconciled",
        "reconciled_at": now_iso(),
        "backup_id": str(backup.get("backup_id") or ""),
        "provider_backup_sha256": provider_sha,
        "local_archive_sha256": local_sha,
        "host_cleanup": result,
        "source_environment": detect_runtime(slug),
    }
    record = snapshot.with_suffix(".reconciliation.json")
    atomic_json(record, reconciliation)
    return {
        "ok": True,
        "state": "reconciled",
        "reconciliation_record": str(record),
        "original_snapshot_preserved": True,
        "runtime_id": runtime_id,
        "cleanup": result,
        "source_environment": reconciliation["source_environment"],
    }


def _hook(project: Path, cf: Path | None) -> str:
    hook = project / ".devfleet/codexpro-bootstrap.sh"
    if not SETTINGS.auto_start_codexpro or not hook.exists():
        return "CodexPro auto-bootstrap disabled or hook absent."
    command = (
        "test -f ./.devfleet/codexpro-bootstrap.sh && ./.devfleet/codexpro-bootstrap.sh"
    )
    if cf:
        services = run(
            [*compose_args(project, cf), "config", "--services"],
            cwd=project,
            check=False,
        ).stdout.split()
        if services:
            return (
                run(
                    [
                        *compose_args(project, cf),
                        "exec",
                        "-T",
                        services[0],
                        "sh",
                        "-lc",
                        command,
                    ],
                    cwd=project,
                    check=False,
                    timeout=900,
                ).stdout
                or ""
            )[-4000:]
    ids = run(
        [
            "docker",
            "ps",
            "-q",
            "--filter",
            f"label=devcontainer.local_folder={project}",
        ],
        check=False,
    ).stdout.split()
    return (
        (
            run(
                ["docker", "exec", ids[0], "sh", "-lc", command],
                check=False,
                timeout=900,
            ).stdout
            or ""
        )[-4000:]
        if ids
        else "No running container."
    )


def start_project(slug: str, override_failover: bool = False) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    _assert_current_compose_safety(project, meta)
    if provider_for(meta).is_vm:
        meta.update(
            {
                "lifecycle_status": "starting",
                "runtime_status": "starting",
                "health_scope": "transition",
                "last_error": "",
                "workspace_provisioned": False,
                "updated_at": now_iso(),
            }
        )
        _write_project_metadata(project, meta)
        try:
            result = VmRuntimeOperations.start(slug, meta)
            meta.update(
                runtime_metadata(
                    provider_for(meta),
                    status="starting",
                    runtime_id=result.get("runtime_id")
                    or result.get("vm_name", meta.get("runtime_id", "")),
                    runtime_address=result.get(
                        "address", meta.get("runtime_address", "")
                    ),
                    provisioning_status="ready",
                    health_status="unknown",
                    health_scope="runtime-ready-not-app-healthy",
                    lifecycle_status="starting",
                )
            )
            _record_vm_readiness(meta, result, workspace_provisioned=False)
            project_result = VM_RUNTIME.command(
                slug, meta, "project-start", command_key="start"
            )
            meta.update(
                {
                    "lifecycle_status": "running",
                    "runtime_status": "running",
                    "health_status": "unknown",
                    "health_scope": "runtime-ready-not-app-healthy",
                    "updated_at": now_iso(),
                }
            )
            _record_vm_readiness(meta, result, workspace_provisioned=True)
            _write_project_metadata(project, meta)
            update_lease(project, active=True)
            return str(
                project_result.get("output")
                or result.get(
                    "message", "Dedicated project VM and project services started."
                )
            )
        except Exception as exc:
            meta.update(
                {
                    "lifecycle_status": "failed",
                    "runtime_status": "failed",
                    "health_status": "unknown",
                    "health_scope": "not-ready",
                    "last_error": str(exc)[-1000:],
                    "updated_at": now_iso(),
                }
            )
            _write_project_metadata(project, meta)
            raise
    cf = compose_file(project)
    if cf:
        _assert_current_compose_safety(project, meta)
        _write_current_compose_ownership(project, cf, meta)
        r = run(
            [*compose_args(project, cf), "up", "-d", "--build"],
            cwd=project,
            timeout=1800,
        )
    elif (project / ".devcontainer/devcontainer.json").exists():
        r = run(
            ["devcontainer", "up", "--workspace-folder", str(project)],
            cwd=project,
            timeout=1800,
        )
    else:
        raise ValueError("No supported container configuration.")
    meta["lifecycle_status"] = "running"
    meta["runtime_status"] = "running"
    meta["updated_at"] = now_iso()
    _write_project_metadata(project, meta)
    update_lease(project, active=True)
    return ((r.stdout + r.stderr) + "\n" + _hook(project, cf))[-12000:]


def stop_project(slug: str) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    if provider_for(meta).is_vm:
        meta.update(
            {
                "lifecycle_status": "stopping",
                "runtime_status": "stopping",
                "health_scope": "transition",
                "updated_at": now_iso(),
            }
        )
        _write_project_metadata(project, meta)
        try:
            project_result = VM_RUNTIME.command(
                slug, meta, "project-stop", command_key="stop"
            )
            result = VmRuntimeOperations.stop(slug, meta)
            if meta.get("runtime_address"):
                meta["last_known_runtime_address"] = meta.get("runtime_address")
            meta.update(
                {
                    "runtime_address": "",
                    "workspace_host"