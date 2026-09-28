# DevFleet source part 073

Full-source UTF-8 byte interval [3348000, 3394500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 7f992e7eeed13f8a786c11a53c5df476269f7d9b5a3681185d230a2aae13dc88

<!-- BEGIN SOURCE SLICE -->
 Do not
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
                    "workspace_host": "",
                    "lifecycle_status": "stopped",
                    "runtime_status": "stopped",
                    "health_status": "unknown",
                    "health_scope": "not-checked-stopped",
                    "workspace_provisioned": False,
                    "ssh_host_key_pinned": False,
                    "ssh_authenticated": False,
                    "ssh_validation_passed": False,
                    "updated_at": now_iso(),
                }
            )
            _record_vm_readiness(
                meta,
                {
                    "address": "",
                    "ssh_alias": meta.get("ssh_alias", ""),
                    "host_key_pinned": False,
                    "authenticated_connection": False,
                    "validated": False,
                },
                workspace_provisioned=False,
            )
            _write_project_metadata(project, meta)
            update_lease(project, active=False, clean_shutdown=True)
            return str(
                project_result.get("output")
                or result.get("message", "Dedicated project VM stopped.")
            )
        except Exception as exc:
            meta.update(
                {
                    "lifecycle_status": "failed",
                    "runtime_status": "failed",
                    "last_error": str(exc)[-1000:],
                    "updated_at": now_iso(),
                }
            )
            _write_project_metadata(project, meta)
            raise
    cf = compose_file(project)
    if cf:
        r = run(
            [*compose_args(project, cf), "down", "--remove-orphans"],
            cwd=project,
            timeout=600,
        )
        out = (r.stdout + r.stderr)[-4000:]
    else:
        ids = run(
            [
                "docker",
                "ps",
                "-aq",
                "--filter",
                f"label=devcontainer.local_folder={project}",
            ],
            check=False,
        ).stdout.split()
        if ids:
            run(["docker", "stop", *ids], timeout=300)
        out = "Stopped."
    meta["lifecycle_status"] = "stopped"
    meta["runtime_status"] = "stopped"
    meta["updated_at"] = now_iso()
    _write_project_metadata(project, meta)
    update_lease(project, active=False, clean_shutdown=True)
    return out


def restart_project(slug: str) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    if provider_for(meta).is_vm:
        meta.update(
            {
                "lifecycle_status": "restarting",
                "runtime_status": "restarting",
                "health_scope": "transition",
                "workspace_provisioned": False,
                "updated_at": now_iso(),
            }
        )
        _write_project_metadata(project, meta)
        try:
            result = VmRuntimeOperations.restart(slug, meta)
            meta.update(
                runtime_metadata(
                    provider_for(meta),
                    status="restarting",
                    runtime_id=result.get("runtime_id", meta.get("runtime_id", "")),
                    runtime_address=result.get(
                        "address", meta.get("runtime_address", "")
                    ),
                    health_status="unknown",
                    health_scope="runtime-ready-not-app-healthy",
                    lifecycle_status="restarting",
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
                    "updated_at": now_iso(),
                }
            )
            _record_vm_readiness(meta, result, workspace_provisioned=True)
            _write_project_metadata(project, meta)
            return str(
                project_result.get("output")
                or result.get(
                    "message",
                    "Dedicated project VM restarted and project services started.",
                )
            )
        except Exception as exc:
            meta.update(
                {
                    "lifecycle_status": "failed",
                    "runtime_status": "failed",
                    "last_error": str(exc)[-1000:],
                    "updated_at": now_iso(),
                }
            )
            _write_project_metadata(project, meta)
            raise
    stop_project(slug)
    return start_project(slug)


def inspect_runtime(slug: str) -> dict[str, Any]:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    if provider_for(meta).is_vm:
        return VmRuntimeOperations.inspect(slug, meta)
    return {
        "ok": True,
        "provider": provider_for(meta).name,
        "runtime_type": "container",
        "running": running(project),
        "project_id": meta.get("project_id"),
        "resource_limits": meta.get("resource_limits"),
    }


def runtime_health(slug: str) -> dict[str, Any]:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    if provider_for(meta).is_vm:
        inspection = VmRuntimeOperations.inspect(slug, meta)
        info = inspection.get("info") if isinstance(inspection, dict) else {}
        state = str((info or {}).get("state") or "").lower()
        if state != "running":
            return {
                "ok": True,
                "provider": provider_for(meta).name,
                "runtime_type": "vm",
                "runtime_id": meta.get("runtime_id"),
                "state": "stopped",
                "healthy": False,
                "runtime_health": "not-run-stopped",
                "application_healthy": False,
                "application_health": "not-run-stopped",
                "health_scope": "runtime-only",
                "guest_exec_performed": False,
                "project_id": meta.get("project_id"),
                "info": info or {},
                "note": "The VM is stopped; health inspection did not execute a guest command.",
            }
        result = VmRuntimeOperations.health(slug, meta)
        return {
            **result,
            "application_healthy": False,
            "health_scope": "runtime-only",
            "note": "Use the project health check for application health.",
        }
    is_running = running(project)
    return {
        "ok": True,
        "provider": provider_for(meta).name,
        "runtime_type": "container",
        "healthy": is_running,
        "application_healthy": is_running,
        "health_scope": "container-runtime",
        "project_id": meta.get("project_id"),
    }


def open_workspace(slug: str) -> dict[str, Any]:
    project = safe_child(SETTINGS.workspaces, slug)
    meta = load_authoritative_project_identity_for_mutation(project)
    provider = provider_for(meta)
    alias = str(meta.get("ssh_alias") or meta.get("runtime_id") or "devfleet-primary")
    remote_path = str(
        meta.get("workspace_path") or f"/home/devrunner/workspaces/{slug}"
    )
    if provider.is_vm:
        inspection = VmRuntimeOperations.inspect(slug, meta)
        info = inspection.get("info") if isinstance(inspection, dict) else {}
        runtime_state = str((info or {}).get("state") or "").lower()
        if runtime_state != "running":
            readiness = workspace_readiness(
                slug, {**meta, "lifecycle_status": runtime_state or "unknown"}
            )
            if runtime_state == "stopped":
                error = "Project VM is stopped. Start it explicitly before opening the workspace."
            else:
                error = (
                    readiness["reason"]
                    or f'Project VM is {runtime_state or "not ready"}. Wait until it is running before opening the workspace.'
                )
            return {
                "ok": False,
                "provider": provider.name,
                "state": runtime_state or readiness["state"],
                "runtime_health": f'not-run-{runtime_state or "unknown"}',
                "ssh_alias": alias,
                "workspace_path": remote_path,
                "launcher_uri": "",
                "readiness": readiness,
                "error": error,
            }
        meta.update({"lifecycle_status": "running", "runtime_status": "running"})
        readiness = workspace_readiness(slug, meta)
        if not readiness["ready"]:
            refreshed = VmRuntimeOperations.refresh(slug, meta)
            _record_vm_readiness(meta, refreshed, workspace_provisioned=True)
            # A legacy agent that returns only an address supplies no trust
            # proof. Preserve the address as diagnostic state, but leave the
            # workspace blocked until a current agent or a real trusted SSH
            # validation supplies all three proofs.
            meta.update({"last_connection_refresh": now_iso(), "updated_at": now_iso()})
            _write_project_metadata(project, meta)
            readiness = workspace_readiness(slug, meta)
            alias = str(meta.get("ssh_alias") or alias)
        if not readiness["ready"]:
            return {
                "ok": False,
                "provider": provider.name,
                "state": readiness["state"],
                "ssh_alias": alias,
                "workspace_path": remote_path,
                "launcher_uri": "",
                "readiness": readiness,
                "error": readiness["reason"] or "Workspace is not ready to open.",
            }
    else:
        readiness = workspace_readiness(slug, meta)
        alias = str(readiness.get("ssh_alias") or alias)
        remote_path = str(readiness.get("workspace_path") or remote_path)
        if not readiness["ready"]:
            return {
                "ok": False,
                "provider": provider.name,
                "state": readiness["state"],
                "ssh_alias": alias,
                "workspace_path": remote_path,
                "launcher_uri": "",
                "readiness": readiness,
                "error": readiness["reason"] or "Workspace is not ready to open.",
            }
    return {
        "ok": True,
        "provider": provider.name,
        "state": (
            "running"
            if provider.is_vm
            else ("running" if running(project) else "stopped")
        ),
        "runtime_address": str(meta.get("runtime_address") or ""),
        "ssh_alias": str(meta.get("ssh_alias") or alias),
        "workspace_path": remote_path,
        "readiness": readiness,
        "launcher_uri": f'vscode://vscode-remote/ssh-remote+{quote(str(meta.get("ssh_alias") or alias),safe="")}/{quote(remote_path.lstrip("/"),safe="/")}',
    }


def _vault_request(
    action: str,
    slug: str = "",
    project_id: str = "",
    *,
    timeout: int,
    deployment_id: str = "",
    source_host_id: str = "",
) -> dict[str, Any]:
    cmd = ["/usr/local/bin/devfleet-vault-request", action]
    if slug:
        cmd.extend([validate_slug(slug), validate_project_id(project_id)])
    if action == "restore-transfer":
        cmd.extend(
            [
                validate_project_id(deployment_id),
                source_host_id,
            ]
        )
    completed = run(cmd, timeout=timeout)
    try:
        receipt = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("Vault broker returned an invalid receipt.") from exc
    if not isinstance(receipt, dict) or receipt.get("ok") is not True:
        raise RuntimeError("Vault broker did not return a verified receipt.")
    if receipt.get("action") != action:
        raise RuntimeError("Vault broker receipt action does not match the request.")
    if slug and (
        receipt.get("project") != slug or receipt.get("project_id") != project_id
    ):
        raise RuntimeError("Vault broker receipt project identity does not match the request.")
    if action == "restore-transfer" and (
        receipt.get("deployment_id") != deployment_id
        or receipt.get("source_host_id") != source_host_id
    ):
        raise RuntimeError("Vault broker receipt transfer identity does not match the request.")
    return receipt


def _read_strict_project_json(project: Path, name: str) -> dict[str, Any]:
    """Read one control record without accepting symlinks or special files."""
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", name):
        raise ValueError("Project control record name is invalid.")
    project = Path(project)
    metadata_dir = project / ".devfleet"
    path = metadata_dir / name
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NONBLOCK", 0)
    if os.name != "nt" and hasattr(os, "O_NOFOLLOW") and hasattr(os, "O_DIRECTORY"):
        project_fd = metadata_fd = record_fd = -1
        try:
            project_fd = os.open(
                project,
                flags | os.O_DIRECTORY | os.O_NOFOLLOW,
            )
            metadata_fd = os.open(
                ".devfleet",
                flags | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=project_fd,
            )
            record_fd = os.open(
                name,
                flags | os.O_NOFOLLOW,
                dir_fd=metadata_fd,
            )
            record_stat = os.fstat(record_fd)
            if not stat.S_ISREG(record_stat.st_mode) or record_stat.st_size > 1024 * 1024:
                raise ValueError("Project control record is not a bounded regular file.")
            chunks: list[bytes] = []
            remaining = 1024 * 1024 + 1
            while remaining:
                chunk = os.read(record_fd, min(65536, remaining))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            if remaining == 0:
                raise ValueError("Project control record is too large.")
            raw = b"".join(chunks).decode("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            raise ValueError("Project control record is unreadable.") from exc
        finally:
            for fd in (record_fd, metadata_fd, project_fd):
                if fd >= 0:
                    os.close(fd)
    else:
        if (
            not project.is_dir()
            or project.is_symlink()
            or not metadata_dir.is_dir()
            or metadata_dir.is_symlink()
            or not path.is_file()
            or path.is_symlink()
        ):
            raise ValueError("Project control record is unavailable or unsafe.")
        try:
            raw = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise ValueError("Project control record is unreadable.") from exc
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError("Project control record is malformed.") from exc
    if not isinstance(value, dict):
        raise ValueError("Project control record must be a JSON object.")
    return value


def _assert_no_running_project_containers(
    project: Path, slug: str, project_id: str
) -> None:
    filters = (
        f"io.devfleet.project-id={project_id}",
        f"io.devfleet.project-slug={slug}",
        f"io.devfleet.runtime-id={compose_name(slug)}",
        f"com.docker.compose.project={compose_name(slug)}",
        f"devcontainer.local_folder={project}",
    )
    running_ids: set[str] = set()
    for label in filters:
        result = run(
            ["docker", "ps", "--quiet", "--filter", f"label={label}"],
            check=False,
            timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(
                "Canonical restore blocked: Docker quiescence probe failed."
            )
        running_ids.update(item for item in result.stdout.split() if item)
    if running_ids:
    