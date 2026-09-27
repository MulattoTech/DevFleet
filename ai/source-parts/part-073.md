# DevFleet source part 073

Full-source UTF-8 byte interval [3348000, 3394500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: c1937c165fc9092d5161864a20cdefc5acc65f59c04da142d3de1dd9c0499a8e

<!-- BEGIN SOURCE SLICE -->
.")
    except Exception as exc:
        rollback_errors = []
        for path, raw in ((metadata_file, metadata_before), (lease_file, lease_before)):
            try:
                if path == metadata_file:
                    _write_project_metadata_bytes(project, raw)
                else:
                    atomic_bytes(path, raw)
            except Exception as rollback_exc:
                rollback_errors.append(f"{path.name}: {rollback_exc}")
        if rollback_errors:
            raise RuntimeError(
                "Source transfer finalization failed and rollback was incomplete: "
                + "; ".join(rollback_errors)
            ) from exc
        raise
    return {
        "ok": True,
        "project": slug,
        "project_id": project_id,
        "source_host_id": SETTINGS.host_id,
        "destination_host_id": destination_host_id,
        "state": "transferred",
    }


def receive_transferred_project(
    slug: str,
    project_id: str,
    deployment_id: str,
    source_host_id: str,
    destination_host_id: str,
) -> dict[str, Any]:
    """Restore and adopt one authenticated peer transfer on the destination."""
    slug = validate_slug(slug)
    project_id = validate_project_id(project_id)
    deployment_id = validate_project_id(deployment_id)
    if deployment_id != str(SETTINGS.deployment_id or ""):
        raise ValueError("Transfer deployment identity does not match this node.")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", source_host_id):
        raise ValueError("Transfer source host identity is invalid.")
    if destination_host_id != SETTINGS.host_id:
        raise ValueError("Transfer destination host identity does not match this node.")
    project = safe_child(SETTINGS.workspaces, slug)
    with _destructive_lock(slug):
        destination_existed = project.exists() or project.is_symlink()
        if destination_existed:
            if not project.is_dir() or project.is_symlink():
                raise ValueError("Transfer destination path is unsafe.")
            existing = _assert_canonical_restore_quiesced(
                slug, expected_project_id=project_id
            )
            if str(existing.get("deployment_id") or "") != deployment_id:
                raise ValueError("Transfer destination deployment identity conflicts.")
        else:
            _assert_no_running_project_containers(project, slug, project_id)

        receipt = _vault_request(
            "restore-transfer",
            slug,
            project_id,
            timeout=3720,
            deployment_id=deployment_id,
            source_host_id=source_host_id,
        )
        staging = Path(
            _validate_recovered_vault_copy(
                slug,
                {
                    "project_id": project_id,
                },
                str(receipt.get("target") or ""),
            )
        )
        marker_path = _vault_recovery_marker_path(staging)
        restored_record = read_project_metadata(staging)
        restored = restored_record.value
        if (
            not isinstance(restored, dict)
            or str(restored.get("slug") or "") != slug
            or str(restored.get("identity") or restored.get("slug") or "") != slug
            or str(restored.get("project_id") or "") != project_id
            or str(restored.get("deployment_id") or "") != deployment_id
            or str(restored.get("host_id") or "") != source_host_id
            or provider_for(restored).is_vm
        ):
            raise ValueError("Restored transfer ownership identity does not match.")
        lease = _read_strict_project_json(staging, "ownership-lease.json")
        if (
            lease.get("project_identity") != slug
            or lease.get("project_id") != project_id
            or type(lease.get("active")) is not bool
            or lease.get("active") is not False
            or not isinstance(lease.get("last_clean_shutdown"), str)
        ):
            raise ValueError("Transferred backup is not cleanly quiesced.")
        try:
            time.strptime(lease["last_clean_shutdown"], "%Y-%m-%dT%H:%M:%SZ")
        except ValueError as exc:
            raise ValueError("Transferred backup is not cleanly quiesced.") from exc

        candidate = dict(restored)
        candidate.update(
            {
                "schema_version": max(5, int(candidate.get("schema_version") or 0)),
                "managed_by": "devfleet",
                "slug": slug,
                "identity": slug,
                "project_id": project_id,
                "deployment_id": deployment_id,
                "host_id": SETTINGS.host_id,
                "runtime_isolation": "container",
                "runtime_type": "container",
                "runtime_provider": "docker-compose",
                "runtime_id": compose_name(slug),
                "runtime_address": "",
                "workspace_location": str(project),
                "workspace_host": SETTINGS.node_name,
                "workspace_path": f"/home/devrunner/workspaces/{slug}",
                "lifecycle_status": "ownership-transfer-pending",
                "runtime_status": "stopped",
                "provisioning_status": "ready",
                "health_status": "unknown",
                "health_scope": "not-checked-stopped",
                "workspace_provisioned": False,
                "ssh_host_key_pinned": False,
                "ssh_authenticated": False,
                "ssh_validation_passed": False,
                "last_error": "",
                "transfer_state": "pending-source-finalization",
                "transfer_source_host_id": source_host_id,
                "transfer_destination_host_id": SETTINGS.host_id,
                "transferred_from_host_id": source_host_id,
                "transferred_at": now_iso(),
                "updated_at": now_iso(),
            }
        )
        lease.update(
            {
                "project_identity": slug,
                "project_id": project_id,
                "active": False,
                "active_node": SETTINGS.node_name,
                "last_clean_shutdown": now_iso(),
                "heartbeat_time": now_iso(),
            }
        )
        staging_metadata = metadata_path(staging)
        staging_lease = staging / ".devfleet/ownership-lease.json"
        staging_ownership = ownership_override_path(staging)
        staging_metadata_before = restored_record.raw
        staging_lease_before = staging_lease.read_bytes()
        staging_ownership_present = staging_ownership.is_file()
        staging_ownership_before = (
            staging_ownership.read_bytes() if staging_ownership_present else b""
        )
        compose = compose_file(staging)
        if compose is None:
            raise ValueError("Transferred project has no supported Compose configuration.")
        try:
            _write_project_metadata(
                staging, candidate, expected=restored_record.binding
            )
            labels = container_ownership_labels(candidate)
            if write_ownership_override(staging, compose, labels) is None:
                raise ValueError(
                    "Transferred project services could not be ownership-bound."
                )
            atomic_json(staging_lease, lease)
        except Exception as exc:
            rollback_errors: list[str] = []
            for path, raw in (
                (staging_metadata, staging_metadata_before),
                (staging_lease, staging_lease_before),
            ):
                try:
                    if path == staging_metadata:
                        _write_project_metadata_bytes(staging, raw)
                    else:
                        atomic_bytes(path, raw)
                except Exception as rollback_exc:
                    rollback_errors.append(f"{path.name}: {rollback_exc}")
            try:
                if staging_ownership_present:
                    atomic_bytes(staging_ownership, staging_ownership_before)
                elif staging_ownership.exists() and not staging_ownership.is_symlink():
                    staging_ownership.unlink()
            except Exception as rollback_exc:
                rollback_errors.append(
                    f"{staging_ownership.name}: {rollback_exc}"
                )
            if rollback_errors:
                raise RuntimeError(
                    "Transfer staging preparation failed and rollback was incomplete: "
                    + "; ".join(rollback_errors)
                ) from exc
            raise

        quarantine_root = SETTINGS.quarantine
        quarantine_root.mkdir(parents=True, exist_ok=True)
        if quarantine_root.is_symlink() or not quarantine_root.is_dir():
            raise ValueError("Transfer quarantine root is unsafe.")
        stamp = f'{time.strftime("%Y%m%d-%H%M%S")}-{uuid.uuid4().hex[:8]}'
        prior_quarantine = quarantine_root / f"transfer-replaced-{stamp}-{slug}"
        failed_quarantine = quarantine_root / f"transfer-failed-{stamp}-{slug}"
        if any(path.exists() or path.is_symlink() for path in (prior_quarantine, failed_quarantine)):
            raise RuntimeError("Transfer quarantine reservation collided.")
        transfer_marker = _record_transfer_pending(
            project,
            project_id=project_id,
            deployment_id=deployment_id,
            source_host_id=source_host_id,
            destination_host_id=destination_host_id,
        )
        prior_moved = False
        promoted = False
        try:
            if destination_existed:
                # Revalidate immediately before the namespace transaction.
                current = _assert_canonical_restore_quiesced(
                    slug,
                    expected_project_id=project_id,
                    allow_pending_transfer=True,
                )
                if str(current.get("deployment_id") or "") != deployment_id:
                    raise ValueError(
                        "Transfer destination deployment identity changed."
                    )
                project.rename(prior_quarantine)
                prior_moved = True
            elif project.exists() or project.is_symlink():
                raise RuntimeError("Transfer destination appeared before promotion.")
            staging.rename(project)
            promoted = True
            verified = load_authoritative_project_identity_for_mutation(
                project, allow_pending_transfer=True
            )
            if (
                str(verified.get("project_id") or "") != project_id
                or str(verified.get("host_id") or "") != SETTINGS.host_id
                or str(verified.get("runtime_id") or "") != compose_name(slug)
            ):
                raise RuntimeError("Transferred project ownership rebind was not durable.")
            _assert_canonical_restore_quiesced(
                slug,
                expected_project_id=project_id,
                allow_pending_transfer=True,
            )
        except Exception as exc:
            rollback_errors: list[str] = []
            if promoted and project.is_dir() and not project.is_symlink():
                try:
                    project.rename(failed_quarantine)
                except Exception as rollback_exc:
                    rollback_errors.append(f"failed-copy: {rollback_exc}")
            if prior_moved and not project.exists() and not project.is_symlink():
                try:
                    prior_quarantine.rename(project)
                except Exception as rollback_exc:
                    rollback_errors.append(f"prior-destination: {rollback_exc}")
            if not rollback_errors and (
                (not destination_existed and not project.exists())
                or (destination_existed and project.is_dir() and not project.is_symlink())
            ):
                try:
                    _remove_transfer_pending(project, transfer_marker)
                except Exception as rollback_exc:
                    rollback_errors.append(f"transfer-authority: {rollback_exc}")
            if rollback_errors or (prior_moved and not project.is_dir()):
                raise RuntimeError(
                    "Transfer promotion failed and destination rollback was incomplete: "
                    + "; ".join(rollback_errors)
                ) from exc
            raise
        try:
            if marker_path.is_file() and not marker_path.is_symlink():
                marker_path.unlink()
        except OSError:
            # A stale control-owned marker for the old staging pathname cannot
            # authorize or block the promoted canonical path.
            pass
        return {
            "ok": True,
            "project": slug,
            "project_id": project_id,
            "deployment_id": deployment_id,
            "source_host_id": source_host_id,
            "destination_host_id": SETTINGS.host_id,
            "state": "handoff-pending",
            "prior_destination_quarantine": (
                str(prior_quarantine) if prior_moved else ""
            ),
        }


def activate_transferred_project(
    slug: str,
    project_id: str,
    deployment_id: str,
    source_host_id: str,
    destination_host_id: str,
) -> dict[str, Any]:
    """Activate and start a pending destination after source retirement succeeds."""
    slug = validate_slug(slug)
    project_id = validate_project_id(project_id)
    deployment_id = validate_project_id(deployment_id)
    if deployment_id != str(SETTINGS.deployment_id or ""):
        raise ValueError("Transfer deployment identity does not match this node.")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", source_host_id):
        raise ValueError("Transfer source host identity is invalid.")
    if destination_host_id != SETTINGS.host_id or source_host_id == destination_host_id:
        raise ValueError("Transfer destination host identity does not match this node.")
    project = safe_child(SETTINGS.workspaces, slug)
    with _destructive_lock(slug):
        transfer_marker = _transfer_pending_marker(project, project_id=project_id)
        if transfer_marker is None or any(
            transfer_marker.get(key) != expected
            for key, expected in (
                ("project_id", project_id),
                ("deployment_id", deployment_id),
                ("source_host_id", source_host_id),
                ("destination_host_id", destination_host_id),
                ("state", "pending-source-finalization"),
            )
        ):
            raise ValueError("Pending transfer authority does not match.")
        identity = _assert_canonical_restore_quiesced(
            slug,
            expected_project_id=project_id,
            allow_pending_transfer=True,
        )
        if (
            str(identity.get("deployment_id") or "") != deployment_id
            or str(identity.get("host_id") or "") != destination_host_id
            or str(identity.get("transfer_state") or "")
            != "pending-source-finalization"
            or str(identity.get("transfer_source_host_id") or "") != source_host_id
            or str(identity.get("transfer_destination_host_id") or "")
            != destination_host_id
            or provider_for(identity).is_vm
        ):
            raise ValueError("Pending transfer ownership identity does not match.")
        metadata_file = metadata_path(project)
        lease_file = project / ".devfleet/ownership-lease.json"
        metadata_before = bytes(getattr(identity, "_metadata_raw", b""))
        metadata_binding = getattr(identity, "_metadata_binding", None)
        if not metadata_before or metadata_binding is None:
            raise RuntimeError("Pending transfer metadata binding is unavailable.")
        lease_before = lease_file.read_bytes()
        compose_command: list[str] = []
        start_attempted = False
        commit_started = False
        try:
            compose = compose_file(project)
            if compose is None:
                raise ValueError(
                    "Transferred project has no supported Compose configuration."
                )
            _assert_current_compose_safety(project, identity)
            _write_current_compose_ownership(project, compose, identity)
            compose_command = compose_args(project, compose)
            start_attempted = True
            result = run(
                [*compose_command, "up", "-d", "--build"],
                cwd=project,
                timeout=1800,
            )
            hook_output = _hook(project, compose)
            activated_at = now_iso()
            candidate = dict(identity)
            candidate.update(
                {
                    "lifecycle_status": "running",
                    "runtime_status": "running",
                    "transfer_state": "completed",
                    "transfer_activated_at": activated_at,
                    "updated_at": activated_at,
                }
            )
            lease = _read_strict_project_json(project, "ownership-lease.json")
            lease.update(
                {
                    "project_identity": slug,
                    "project_id": project_id,
                    "active": True,
                    "active_node": destination_host_id,
                    "start_time": activated_at,
                    "last_clean_shutdown": None,
                    "heartbeat_time": activated_at,
                }
            )
            commit_started = True
            _write_project_metadata(project, candidate, expected=metadata_binding)
            atomic_json(lease_file, lease)
            verified = load_authoritative_project_identity_for_mutation(
                project, allow_pending_transfer=True
            )
            verified_lease = _read_strict_project_json(
                project, "ownership-lease.json"
            )
            if (
                str(verified.get("transfer_state") or "") != "completed"
                or str(verified.get("lifecycle_status") or "") != "running"
                or str(verified.get("runtime_status") or "") != "running"
                or str(verified.get("host_id") or "") != destination_host_id
                or verified_lease.get("project_id") != project_id
                or verified_lease.get("active") is not True
                or verified_lease.get("active_node") != destination_host_id
            ):
                raise RuntimeError("Transfer destination activation was not durable.")
            # The control-owned marker is removed last. Until this exact commit,
            # every ordinary mutation entry point continues to fail closed.
            _remove_transfer_pending(project, transfer_marker)
            activated = load_authoritative_project_identity_for_mutation(project)
            if any(
                str(activated.get(key) or "") != expected
                for key, expected in (
                    ("project_id", project_id),
                    ("deployment_id", deployment_id),
                    ("host_id", destination_host_id),
                    ("transfer_source_host_id", source_host_id),
                    ("transfer_destination_host_id", destination_host_id),
                    ("transfer_state", "completed"),
                    ("lifecycle_status", "running"),
                    ("runtime_status", "running"),
                )
            ):
                raise RuntimeError("Activated transfer identity changed after commit.")
            started_lease = _read_strict_project_json(
                project, "ownership-lease.json"
            )
            if (
                started_lease.get("active") is not True
                or started_lease.get("active_node") != destination_host_id
                or started_lease.get("project_id") != project_id
            ):
                raise RuntimeError("Activated transfer lease did not bind to this node.")
        except Exception as exc:
            rollback_errors: list[str] = []
            if start_attempted and compose_command:
                try:
                    stopped = run(
                        [*compose_command, "down", "--remove-orphans"],
                        cwd=project,
                        check=False,
                        timeout=600,
                    )
                    if stopped.returncode != 0:
                        raise RuntimeError(
                            (stopped.stderr or stopped.stdout or "Docker stop failed.")[
                                -2000:
                            ]
                        )
                except Exception as rollback_exc:
                    rollback_errors.append(f"destination-runtime: {rollback_exc}")
            if commit_started:
                for path, raw in (
                    (metadata_file, metadata_before),
                    (lease_file, lease_before),
                ):
                    try:
                        if path == metadata_file:
                            _write_project_metadata_bytes(project, raw)
                        else:
                            atomic_bytes(path, raw)
                    except Exception as rollback_exc:
                        rollback_errors.append(f"{path.name}: {rollback_exc}")
            try:
                current_marker = _transfer_pending_marker(
                    project, project_id=project_id
                )
                if current_marker is None:
                    _record_transfer_pending(
                        project,
                        project_id=project_id,
                        deployment_id=deployment_id,
                        source_host_id=source_host_id,
                        destination_host_id=destination_host_id,
                    )
                elif any(
                    current_marker.get(key) != expected
                    for key, expected in (
                        ("project_id", project_id),
                        ("deployment_id", deployment_id),
                        ("source_host_id", source_host_id),
                        ("destination_host_id", destination_host_id),
                        ("state", "pending-source-finalization"),
                    )
                ):
                    raise RuntimeError("Pending transfer authority changed during activation.")
            except Exception as rollback_exc:
                rollback_errors.append(f"transfer-authority: {rollback_exc}")
            try:
                pending = load_authoritative_project_identity_for_mutation(
                    project, allow_pending_transfer=True
                )
                pending_lease = _read_strict_project_json(
                    project, "ownership-lease.json"
                )
                if (
                    str(pending.get("project_id") or "") != project_id
                    or str(pending.get("deployment_id") or "") != deployment_id
                    or str(pending.get("host_id") or "") != destination_host_id
                    or str(pending.get("transfer_state") or "")
                    != "pending-source-finalization"
                    or str(pending.get("lifecycle_status") or "")
                    != "ownership-transfer-pending"
                    or pending_lease.get("project_id") != project_id
                    or pending_lease.get("active") is not False
                    or pending_lease.get("active_node") != destination_host_id
                ):
                    raise RuntimeError(
                        "Pending transfer rollback identity is inconsistent."
                    )
            except Exception as rollback_exc:
                rollback_errors.append(f"pending-state: {rollback_exc}")
            if rollback_errors:
                raise RuntimeError(
                    "Transfer activation failed and rollback was incomplete: "
                    + "; ".join(rollback_errors)
                ) from exc
            raise
        return {
            "ok": True,
            "project": slug,
            "project_id": project_id,
            "deployment_id": deployment_id,
            "source_host_id": source_host_id,
            "destination_host_id": destination_host_id,
            "state": "activated-running",
            "output": ((result.stdout + result.stderr) + "\n" + hook_output)[-12000:],
        }


def backup_project(
    slug: str,
    *,
    consistency_level: str = "live-best-effort",
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
        before = _source_state_fingerprint(project, include_generated=True)
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
        after = _source_state_fingerprint(project, include_generated=True)
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
            "source_state_fingerprint": after,
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
        _assert_cu