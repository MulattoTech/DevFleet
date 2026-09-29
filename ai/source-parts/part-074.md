# DevFleet source part 074

Full-source UTF-8 byte interval [3394500, 3441000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 0dfd4607398f78df58a36f1aede81bef34fd95a91a3eea834edeab3c010b6deb

<!-- BEGIN SOURCE SLICE -->
: "",
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
        raise RuntimeError(
            "Canonical restore blocked: an owned project runtime is still running."
        )


def _assert_canonical_restore_quiesced(
    slug: str,
    *,
    expected_project_id: str | None = None,
    allow_pending_transfer: bool = False,
) -> dict[str, Any]:
    slug = validate_slug(slug)
    project = safe_child(SETTINGS.workspaces, slug)
    identity = load_authoritative_project_identity_for_mutation(
        project, allow_pending_transfer=allow_pending_transfer
    )
    project_id = validate_project_id(str(identity.get("project_id") or ""))
    if expected_project_id is not None and project_id != validate_project_id(
        expected_project_id
    ):
        raise ValueError("Canonical restore project identity does not match.")
    if str(identity.get("slug") or "") != slug or str(
        identity.get("identity") or ""
    ) != slug:
        raise ValueError("Canonical restore project identity does not bind to its path.")
    if provider_for(identity).is_vm:
        raise ValueError(
            "Canonical Vault restore for a dedicated VM requires a supported stopped-VM attestation. Use restore-copy instead."
        )
    try:
        lease = _read_strict_project_json(project, "ownership-lease.json")
    except ValueError as exc:
        raise ValueError(
            "Canonical restore requires a valid inactive ownership lease."
        ) from exc
    if (
        lease.get("project_identity") != slug
        or lease.get("project_id") != project_id
        or type(lease.get("active")) is not bool
        or lease.get("active") is not False
    ):
        raise ValueError(
            "Canonical restore requires an identity-bound inactive ownership lease."
        )
    clean_shutdown = lease.get("last_clean_shutdown")
    if not isinstance(clean_shutdown, str):
        raise ValueError("Canonical restore requires a verified clean shutdown.")
    try:
        time.strptime(clean_shutdown, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as exc:
        raise ValueError(
            "Canonical restore requires a verified clean shutdown."
        ) from exc
    _assert_no_running_project_containers(project, slug, project_id)
    return identity


def assert_project_quiesced_for_transfer(slug: str, project_id: str) -> None:
    """Recheck source quiescence while the caller holds project_transfer_lock."""
    identity = _assert_canonical_restore_quiesced(
        slug, expected_project_id=validate_project_id(project_id)
    )
    if (
        str(identity.get("deployment_id") or "") != str(SETTINGS.deployment_id or "")
        or str(identity.get("host_id") or "") != SETTINGS.host_id
    ):
        raise ValueError("Transfer source is not owned by this node and deployment.")


def finalize_source_transfer(
    slug: str, project_id: str, destination_host_id: str
) -> dict[str, Any]:
    """Retire the stopped source only after the peer start is terminally proven."""
    slug = validate_slug(slug)
    project_id = validate_project_id(project_id)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", destination_host_id):
        raise ValueError("Transfer destination host identity is invalid.")
    identity = _assert_canonical_restore_quiesced(
        slug, expected_project_id=project_id
    )
    if (
        str(identity.get("deployment_id") or "") != str(SETTINGS.deployment_id or "")
        or str(identity.get("host_id") or "") != SETTINGS.host_id
        or destination_host_id == SETTINGS.host_id
    ):
        raise ValueError("Transfer source finalization identity is inconsistent.")
    project = safe_child(SETTINGS.workspaces, slug)
    metadata_file = metadata_path(project)
    lease_file = project / ".devfleet/ownership-lease.json"
    metadata_before = bytes(getattr(identity, "_metadata_raw", b""))
    metadata_binding = getattr(identity, "_metadata_binding", None)
    if not metadata_before or metadata_binding is None:
        raise RuntimeError("Source transfer metadata binding is unavailable.")
    lease_before = lease_file.read_bytes()
    candidate = dict(identity)
    candidate.update(
        {
            "host_id": destination_host_id,
            "lifecycle_status": "transferred",
            "runtime_status": "stopped",
            "transfer_state": "source-retired",
            "transfer_source_host_id": SETTINGS.host_id,
            "transfer_destination_host_id": destination_host_id,
            "transferred_to_host_id": destination_host_id,
            "transferred_at": now_iso(),
            "updated_at": now_iso(),
        }
    )
    lease = _read_strict_project_json(project, "ownership-lease.json")
    lease.update(
        {
            "project_identity": slug,
            "project_id": project_id,
            "active": True,
            "active_node": destination_host_id,
            "heartbeat_time": now_iso(),
            "last_clean_shutdown": None,
        }
    )
    try:
        # Publish the foreign active lease first so a partial finalization still
        # fails closed at require_safe_start.
        atomic_json(lease_file, lease)
        _write_project_metadata(project, candidate, expected=metadata_binding)
        verified = load_authoritative_project_identity_for_mutation(
            project, allow_retired_transfer=True
        )
        verified_lease = _read_strict_project_json(project, "ownership-lease.json")
        if (
            str(verified.get("host_id") or "") != destination_host_id
            or verified_lease.get("active") is not True
            or verified_lease.get("active_node") != destination_host_id
        ):
            raise RuntimeError("Source transfer retirement was not durable.")
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
   