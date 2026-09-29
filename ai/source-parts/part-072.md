# DevFleet source part 072

Full-source UTF-8 byte interval [3301500, 3348000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8d61f3311f6e49e17fa0ee7741feb368b04d1dbee0c812544c0dfbb3e2fe4939

<!-- BEGIN SOURCE SLICE -->
transfer_pending(
    project: Path,
    *,
    project_id: str,
    deployment_id: str,
    source_host_id: str,
    destination_host_id: str,
) -> dict[str, Any]:
    marker_path = _transfer_pending_marker_path(project)
    marker_root = marker_path.parent
    marker_root.mkdir(parents=True, mode=0o750, exist_ok=True)
    if marker_root.is_symlink() or not marker_root.is_dir():
        raise RuntimeError("Transfer authority root is unsafe.")
    marker = {
        "schema_version": 1,
        "workspace_path": str(Path(project).absolute()),
        "workspace_name": Path(project).name,
        "project_id": validate_project_id(project_id),
        "deployment_id": validate_project_id(deployment_id),
        "source_host_id": source_host_id,
        "destination_host_id": destination_host_id,
        "state": "pending-source-finalization",
        "created_at": now_iso(),
    }
    if (
        not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", source_host_id)
        or not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", destination_host_id
        )
        or source_host_id == destination_host_id
    ):
        raise ValueError("Transfer host identity is invalid.")
    atomic_json(marker_path, marker)
    if _transfer_pending_marker(project, project_id=project_id) != marker:
        raise RuntimeError("Transfer authority marker was not durable.")
    return marker


def _remove_transfer_pending(project: Path, expected: dict[str, Any]) -> None:
    current = _transfer_pending_marker(
        project, project_id=str(expected.get("project_id") or "")
    )
    for key in (
        "workspace_path",
        "workspace_name",
        "project_id",
        "deployment_id",
        "source_host_id",
        "destination_host_id",
        "state",
    ):
        if current is None or current.get(key) != expected.get(key):
            raise RuntimeError("Transfer authority marker changed before removal.")
    marker_path = _transfer_pending_marker_path(project)
    marker_path.unlink()
    if marker_path.exists() or marker_path.is_symlink():
        raise RuntimeError("Transfer authority marker removal was not durable.")


def load_authoritative_project_identity_for_mutation(
    project: Path,
    *,
    require_runtime: bool = False,
    allow_legacy_migration: bool = False,
    allow_pending_transfer: bool = False,
    allow_retired_transfer: bool = False,
) -> dict[str, Any]:
    """Return only a persisted DevFleet ownership record suitable for mutation.

    A directory under the workspace root is not evidence of DevFleet ownership.
    Missing, malformed, incomplete, or mismatched metadata fails closed and never
    receives the catalog loader's synthesized defaults.
    """
    project = Path(project)
    if not project.is_dir() or project.is_symlink():
        raise ValueError("Mutation requires a real project workspace directory.")
    try:
        record = read_project_metadata(project)
        value = record.value
    except FileNotFoundError as exc:
        raise ValueError(
            "Mutation denied: persisted DevFleet ownership metadata is missing."
        ) from exc
    except MetadataSafetyError as exc:
        raise ValueError(
            "Mutation denied: persisted DevFleet ownership metadata is missing."
        ) from exc
    except (OSError, ValueError, UnicodeError) as exc:
        raise ValueError(
            "Mutation denied: project ownership metadata is malformed."
        ) from exc
    if not isinstance(value, dict):
        raise ValueError(
            "Mutation denied: project ownership metadata must be a JSON object."
        )
    try:
        schema = int(value.get("schema_version"))
    except (TypeError, ValueError) as exc:
        raise ValueError(
            "Mutation denied: project ownership schema/version is missing."
        ) from exc
    legacy = (
        schema == 2
        and allow_legacy_migration
        and str(value.get("managed_by") or "").strip().lower() == "devfleet"
        and str(value.get("identity") or "").strip()
        == str(value.get("slug") or "").strip()
    )
    if schema < 3 and not legacy:
        raise ValueError(
            "Mutation denied: project ownership schema/version is unsupported."
        )
    if not legacy and str(value.get("managed_by") or "").strip().lower() != "devfleet":
        raise ValueError(
            "Mutation denied: project is not explicitly marked as DevFleet-owned."
        )
    slug = str(value.get("slug") or "").strip()
    if not slug or slug != project.name or validate_slug(slug) != slug:
        raise ValueError(
            "Mutation denied: persisted project slug does not bind to the workspace path."
        )
    identity = str(value.get("identity") or slug).strip()
    if not identity or identity != slug or validate_slug(identity) != identity:
        raise ValueError(
            "Mutation denied: persisted project identity does not bind to the workspace path."
        )
    project_id = str(value.get("project_id") or "").strip()
    if not re.fullmatch(r"[0-9a-fA-F-]{16,128}", project_id):
        raise ValueError(
            "Mutation denied: persisted project ID is missing or malformed."
        )
    pending_marker = _transfer_pending_marker(project, project_id=project_id)
    persisted_pending_transfer = (
        str(value.get("transfer_state") or "") == "pending-source-finalization"
        or str(value.get("lifecycle_status") or "")
        == "ownership-transfer-pending"
    )
    if (
        pending_marker is not None or persisted_pending_transfer
    ) and not allow_pending_transfer:
        raise ValueError(
            "Mutation denied: ownership transfer awaits source finalization."
        )
    if (
        str(value.get("transfer_state") or "") == "source-retired"
        and not allow_retired_transfer
    ):
        raise ValueError(
            "Mutation denied: project ownership was transferred to another node."
        )
    recovery_marker = _vault_recovery_copy_marker(
        project, source_project_id=project_id
    )
    if recovery_marker is None and _is_generated_vault_recovery_name(project.name):
        raise ValueError(
            "Mutation denied: reserved Vault recovery namespace requires control-owned recovery authority."
        )
    if recovery_marker is not None:
        raise ValueError(
            "Mutation denied: recovered Vault copies require explicit adoption."
        )
    provider = str(value.get("runtime_provider") or "").strip().lower()
    if provider not in {
        "docker-compose",
        "multipass-host-agent",
        "multipass",
        "virtualbox",
    }:
        raise ValueError(
            "Mutation denied: persisted runtime provider is missing or unsupported."
        )
    runtime_id = str(value.get("runtime_id") or "").strip()
    if require_runtime and not runtime_id:
        raise ValueError("Mutation denied: persisted runtime identity is missing.")
    if runtime_id and (
        len(runtime_id) > 128
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]*", runtime_id)
    ):
        raise ValueError("Mutation denied: persisted runtime identity is malformed.")
    if not str(value.get("host_id") or "").strip():
        raise ValueError(
            "Mutation denied: persisted deployment/node ownership is missing."
        )
    return _MetadataSnapshot(value, binding=record.binding, raw=record.raw)


def _commit_project_metadata(project: Path, candidate: dict[str, Any]) -> None:
    """Commit only changes made since the caller's read under the project lock."""
    project = Path(os.path.abspath(os.fspath(project)))
    slug = validate_slug(project.name)
    observed = getattr(candidate, "_observed", None)
    with _destructive_lock(f"metadata-{slug}"):
        latest = load_authoritative_project_identity_for_mutation(project)
        if isinstance(observed, dict):
            sentinel = object()
            for key in set(observed) | set(candidate):
                before = observed.get(key, sentinel)
                after = candidate.get(key, sentinel)
                if before == after:
                    continue
                if key in candidate:
                    latest[key] = copy.deepcopy(candidate[key])
                else:
                    latest.pop(key, None)
        else:
            latest.update(copy.deepcopy(candidate))
        latest["updated_at"] = now_iso()
        _write_project_metadata(project, latest)


def commit_project_metadata(project: Path, candidate: dict[str, Any]) -> None:
    """Public identity-bound metadata commit for API modules."""
    _commit_project_metadata(project, candidate)


@contextlib.contextmanager
def project_metadata_transaction(project: Path):
    """Serialize read-modify-write metadata updates across API processes."""
    project = Path(os.path.abspath(os.fspath(project)))
    slug = validate_slug(project.name)
    with _destructive_lock(f"metadata-{slug}"):
        meta = load_authoritative_project_identity_for_mutation(project)
        yield meta
        meta["updated_at"] = now_iso()
        _write_project_metadata(project, meta)


def workspace_readiness(
    slug: str, metadata: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Return the single readiness contract used by UI and workspace launch."""
    meta = metadata or load_meta(safe_child(SETTINGS.workspaces, slug))
    provider = provider_for(meta)
    state = str(
        meta.get("lifecycle_status") or meta.get("runtime_status") or "unknown"
    ).lower()
    path = str(meta.get("workspace_path") or f"/home/devrunner/workspaces/{slug}")
    if not provider.is_vm:
        # Container application lifecycle and code-workspace lifecycle are separate.
        # The workspace is reached through the managed primary compute SSH target;
        # stopped Compose services must not make the code workspace appear absent.
        alias = str(
            meta.get("workspace_ssh_alias")
            or meta.get("ssh_alias")
            or SETTINGS.node_name
            or "devfleet-primary"
        )
        host = str(
            meta.get("workspace_host")
            or meta.get("host_id")
            or SETTINGS.node_name
            or "devfleet-primary"
        )
        provisioned = bool(meta.get("workspace_provisioned", bool(path)))
        accessible = bool(meta.get("workspace_accessible", True))
        ready = bool(path and alias and host and provisioned and accessible)
        reason = (
            ""
            if ready
            else (
                "Container workspace is not accessible from the primary compute host."
                if not accessible
                else "Container workspace has not been provisioned."
            )
        )
        return {
            "ready": ready,
            "status": "ready" if ready else "not-ready",
            "state": state,
            "reason": reason,
            "runtime_address": host,
            "ssh_alias": alias,
            "workspace_path": path,
            "host_key_pinned": bool(
                meta.get("ssh_host_key_pinned", meta.get("host_key_pinned", False))
            ),
            "authenticated_connection": bool(
                meta.get(
                    "ssh_authenticated", meta.get("authenticated_connection", False)
                )
            ),
            "validated": ready,
            "workspace_provisioned": provisioned,
            "application_running": state == "running",
        }
    if state == "stopped":
        reason = "Not ready — VM is stopped."
    elif state in {"starting", "provisioning", "restarting", "stopping"}:
        reason = f"Waiting — VM is {state}."
    else:
        reason = "Not ready — SSH readiness is being reconciled."
    address = str(meta.get("runtime_address") or "")
    alias = str(meta.get("ssh_alias") or "")
    pinned = bool(meta.get("ssh_host_key_pinned", meta.get("host_key_pinned", False)))
    authenticated = bool(
        meta.get("ssh_authenticated", meta.get("authenticated_connection", False))
    )
    validated = bool(meta.get("ssh_validation_passed", meta.get("validated", False)))
    provisioned = bool(meta.get("workspace_provisioned", False))
    ready = state == "running" and bool(
        address and alias and pinned and authenticated and validated and provisioned
    )
    if ready:
        reason = ""
    elif (
        state == "running"
        and address
        and alias
        and pinned
        and authenticated
        and validated
        and not provisioned
    ):
        reason = "Not ready — workspace path has not been verified."
    return {
        "ready": ready,
        "status": "ready" if ready else "not-ready",
        "state": state,
        "reason": reason,
        "runtime_address": address,
        "ssh_alias": alias,
        "workspace_path": path,
        "host_key_pinned": pinned,
        "authenticated_connection": authenticated,
        "validated": validated,
        "workspace_provisioned": provisioned,
    }


def project_capabilities(
    slug: str, metadata: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Return the server-authoritative, metadata-only project availability model.

    This function must never inspect, start, or contact a runtime.  Ordinary page
    rendering uses it to decide whether a live request is allowed at all.
    """
    meta = metadata or load_meta(safe_child(SETTINGS.workspaces, slug))
    readiness = workspace_readiness(slug, meta)
    provider = provider_for(meta)
    raw_state = (
        str(meta.get("lifecycle_status") or meta.get("runtime_status") or "unknown")
        .strip()
        .lower()
    )
    aliases = {
        "ready": "running",
        "healthy": "running",
        "container-ready": "running",
        "offline": "unreachable",
        "failed": "error",
    }
    state = aliases.get(raw_state, raw_state)
    transitioning = state in {"starting", "stopping", "restarting", "provisioning"}
    running_state = state == "running"
    stopped_state = state == "stopped"
    reachable = running_state and (
        not provider.is_vm or bool(meta.get("runtime_address"))
    )
    live = bool(running_state and reachable and not transitioning)
    return {
        "lifecycle_state": state,
        "runtime_provider": provider.name,
        "runtime_reachable": reachable,
        "runtime_transitioning": transitioning,
        "ssh_ready": (
            bool(readiness.get("ready"))
            if provider.is_vm
            else bool(readiness.get("ready"))
        ),
        "application_health_available": live,
        "logs_available": live,
        "live_metrics_available": live,
        "workspace_open_available": bool(readiness.get("ready")),
        "can_start": stopped_state or state in {"error", "unreachable", "unknown"},
        "can_stop": running_state or state == "starting",
        "can_restart": live,
        "can_query_live_metrics": live,
        "can_query_application_health": live,
        "can_query_logs": live,
        "can_open_workspace": bool(readiness.get("ready")),
        "can_run_runtime_tests": live,
        "can_run_runtime_action": live,
        "status_reason": (
            "Environment stopped."
            if stopped_state
            else (
                f"Environment {state}."
                if transitioning
                else "Runtime is unreachable." if state == "unreachable" else ""
            )
        ),
    }


def _record_vm_readiness(
    meta: dict[str, Any],
    result: dict[str, Any] | None = None,
    *,
    workspace_provisioned: bool | None = None,
) -> None:
    result = result if isinstance(result, dict) else {}
    for target, source in (
        ("runtime_id", "runtime_id"),
        ("runtime_address", "address"),
        ("ssh_alias", "ssh_alias"),
    ):
        value = result.get(source)
        if value is not None and str(value):
            meta[target] = str(value)
    if "host_key_pinned" in result:
        meta["ssh_host_key_pinned"] = bool(result.get("host_key_pinned"))
    if "authenticated_connection" in result:
        meta["ssh_authenticated"] = bool(result.get("authenticated_connection"))
    if "validated" in result:
        meta["ssh_validation_passed"] = bool(result.get("validated"))
    if workspace_provisioned is not None:
        meta["workspace_provisioned"] = bool(workspace_provisioned)
    if meta.get("runtime_address"):
        meta["workspace_host"] = str(meta["runtime_address"])
    meta["workspace_readiness_checked_at"] = now_iso()
    meta["workspace_readiness"] = workspace_readiness(str(meta.get("slug") or ""), meta)


def _json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _safe_vm_command(command: str) -> bool:
    cmd = str(command or "")
    hook_allowed = bool(
        re.fullmatch(
            r"\./\.devfleet/(bootstrap|health-check|smoke-test|codexpro-bootstrap)\.sh",
            cmd,
        )
    )
    compose_allowed = cmd in _SAFE_COMPOSE_COMMANDS
    forbidden = bool(
        re.search(r"[\r\n`$<>]", cmd)
        or re.search(
            r"(?i)(^|\s)(sudo|su|shutdown|reboot|poweroff|systemctl|service|multipass)(\s|$)",
            cmd,
        )
        or re.search(r"(?i)(rm\s+-rf|docker\s+(run|exec)|curl\s+|wget\s+)", cmd)
    )
    return 0 < len(cmd) <= 512 and (hook_allowed or compose_allowed) and not forbidden


def project_command_readiness(
    project: Path, metadata: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Resolve only fixed trusted command keys for legacy project metadata.

    Explicit project values win.  A missing key may fall back first to the copied
    project template and then to the canonical package template identified by the
    project's template id.  Every resolved value must still pass the Host Agent's
    fixed command allowlist.
    """
    raw = metadata if isinstance(metadata, dict) else _raw_meta(project)
    local_template = _json_object(project / ".devfleet/template.json")
    template_id = str(raw.get("template") or local_template.get("id") or "").strip()
    canonical_template: dict[str, Any] = {}
    if template_id and re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,62}", template_id):
        candidate = TEMPLATE_ROOT / template_id / ".devfleet/template.json"
        if candidate.is_file() and not candidate.is_symlink():
            canonical_template = _json_object(candidate)
    nested = raw.get("commands") if isinstance(raw.get("commands"), dict) else {}
    resolved: dict[str, str] = {}
    sources: dict[str, str] = {}
    invalid: dict[str, str] = {}
    for key in PROJECT_COMMAND_KEYS:
        present = False
        value: Any = ""
        source = ""
        if key in raw:
            present = True
            value = raw.get(key)
            source = "project.json"
        elif key in nested:
            present = True
            value = nested.get(key)
            source = "project.json.commands"
        elif key in local_template:
            present = True
            value = local_template.get(key)
            source = "project-template"
        elif key in canonical_template:
            present = True
            value = canonical_template.get(key)
            source = f"canonical-template:{template_id}"
        if not present or value is None or not str(value).strip():
            continue
        command = str(value).strip()
        if not _safe_vm_command(command):
            invalid[key] = source or "unknown"
            continue
        resolved[key] = command
        sources[key] = source
    missing = [key for key in VM_LIFECYCLE_COMMAND_KEYS if key not in resolved]
    invalid_required = {
        key: invalid[key] for key in VM_LIFECYCLE_COMMAND_KEYS if key in invalid
    }
    return {
        "ready": not missing and not invalid_required,
        "resolved_commands": resolved,
        "sources": sources,
        "required_commands": list(VM_LIFECYCLE_COMMAND_KEYS),
        "missing_required": missing,
        "invalid_required": invalid_required,
        "invalid_commands": invalid,
        "template_id": template_id,
    }


def detect_runtime(slug: str) -> dict[str, Any]:
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir():
        raise FileNotFoundError(slug)
    raw = _raw_meta(project)
    meta = load_meta(project)
    explicit = any(
        key in raw
        for key in (
            "runtime_isolation",
            "runtime_type",
            "runtime_provider",
            "resource_profile",
            "resource_limits",
        )
    )
    provider = provider_for(meta)
    return {
        "runtime_isolation": provider.runtime_type,
        "runtime_type": provider.runtime_type,
        "runtime_provider": provider.name,
        "resource_profile": str(meta.get("resource_profile") or "standard"),
        "resource_limits": meta.get("resource_limits")
        or resource_metadata(
            str(meta.get("resource_profile") or "standard"), provider.runtime_type
        ),
        "source": "metadata" if explicit else "inferred-from-existing-workspace",
        "workspace": str(project),
        "runtime_id": str(meta.get("runtime_id") or ""),
        "host_id": str(meta.get("host_id") or SETTINGS.node_name),
        "lifecycle_status": str(meta.get("lifecycle_status") or "unknown"),
        "provisioning_status": str(meta.get("provisioning_status") or "unknown"),
        "health_status": str(meta.get("health_status") or "unknown"),
    }


def project_identity(slug: str) -> str:
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir():
        raise FileNotFoundError(slug)
    meta = load_meta(project)
    return validate_slug(str(meta.get("identity") or meta.get("slug") or slug))


def compose_file(project: Path) -> Path | None:
    for rel in (
        "compose.yaml",
        "compose.yml",
        ".devcontainer/compose.yaml",
        ".devcontainer/docker-compose.yml",
        "docker-compose.yml",
    ):
        p = project / rel
        if (
            p.exists()
            and not p.is_symlink()
            and p.resolve().is_relative_to(project.resolve())
        ):
            return p
    return None


def compose_name(slug: str) -> str:
    return "df_" + slug.replace(".", "_").replace("-", "_")


def compose_args(project: Path, cf: Path) -> list[str]:
    args = ["docker", "compose", "-f", str(cf)]
    override = cache_override(project, cf, load_meta(project))
    if override:
        args += ["-f", str(override)]
    ownership_override = ownership_override_path(project)
    if ownership_override.is_file():
        args += ["-f", str(ownership_override)]
    resource_override = resource_override_path(project)
    if resource_override.is_file():
        args += ["-f", str(resource_override)]
    return args + ["-p", compose_name(project.name)]


def _write_current_compose_ownership(project: Path, compose: Path, metadata: dict[str, Any]) -> Path:
    expected_runtime = compose_name(project.name)
    if str(metadata.get("runtime_id") or "") != expected_runtime:
        raise ValueError("Compose runtime identity does not match the authoritative project identity.")
    labels = container_ownership_labels(metadata)
    result = write_ownership_override(project, compose, labels)
    if result is None:
        raise ValueError("Compose services could not be read; no ownership binding was written.")
    return result


def _assert_current_compose_safety(project: Path, meta: dict[str, Any]) -> None:
    """Re-analyze current compose bytes immediately before container creation."""
    findings = analyze_project(
        project,
        str(meta.get("profile") or SETTINGS.development_profile),
        force=True,
    )
    if has_blockers(findings):
        raise ValueError(
            "Security analyzer found blocking boundary violations in the current compose configuration."
        )


def _resource_selection(
    resource_profile: str,
    resource_limits: dict[str, Any] | None,
    runtime_type: str,
    scale: str,
    intent: str,
    project_kind: str,
    language: str,
    framework: str,
) -> tuple[str, dict[str, Any]]:
    if resource_limits:
        return "custom", custom_resource_metadata(
            resource_limits, runtime_type=runtime_type
        )
    recommended = recommend_resource_profile(
        scale=scale,
        intent=intent,
        project_kind=project_kind,
        language=language,
        framework=framework,
    )
    selected = str(resource_profile or recommended.name).lower()
    if selected not in {"small", "standard", "large", "xlarge"}:
        raise ValueError("Unknown resource profile.")
    return selected, validate_resource_limits(
        resource_metadata(selected, runtime_type), runtime_type=runtime_type
    )


def running(project: Path) -> bool:
    cf = compose_file(project)
    if cf:
        return bool(
            run(
                [*compose_args(project, cf), "ps", "--status", "running", "--quiet"],
                cwd=project,
                check=False,
                timeout=30,
            ).stdout.strip()
        )
    return bool(
        run(
            [
                "docker",
                "ps",
                "--filter",
                f"label=devcontainer.local_folder={project}",
                "--format",
                "{{.ID}}",
            ],
            check=False,
            timeout=30,
        ).stdout.strip()
    )


def git_summary(project: Path) -> dict[str, Any]:
    return {
        "commit": run(
            ["git", "rev-parse", "HEAD"], cwd=project, check=False, timeout=20
        ).stdout.strip(),
        "dirty": bool(
            run(
                ["git", "status", "--porcelain"], cwd=project, check=False, timeout=20
            ).stdout.strip()
        ),
    }


def _recovery_only_catalog_entry(
    project: Path, metadata: dict[str, Any], reason: str
) -> dict[str, Any]:
    """Describe restored/unadopted data without probing or mutating a runtime."""
    status_reason = (
        "Recovery-only workspace; explicit ownership adoption is required before "
        "runtime access."
    )
    capabilities = {
        "lifecycle_state": "recovery-only",
        "runtime_provider": str(
            metadata.get("runtime_provider")
            or metadata.get("runtime_isolation")
            or "unmanaged"
        ),
        "runtime_reachable": False,
        "runtime_transitioning": False,
        "ssh_ready": False,
        "application_health_available": False,
        "logs_available": False,
        "live_metrics_available": False,
        "workspace_open_available": False,
        "can_start": False,
        "can_stop": False,
        "can_restart": False,
        "can_query_live_metrics": False,
        "can_query_application_health": False,
        "can_query_logs": False,
        "can_open_workspace": False,
        "can_run_runtime_tests": False,
        "can_run_runtime_action": False,
        "status_reason": status_reason,
    }
    readiness = {
        "ready": False,
        "status": "recovery-only",
        "state": "recovery-only",
        "reason": status_reason,
        "runtime_address": "",
        "ssh_alias": "",
        "workspace_path": "",
        "host_key_pinned": False,
        "authenticated_connection": False,
        "validated": False,
        "workspace_provisioned": False,
    }
    return {
        **metadata,
        "slug": project.name,
        "display_name": str(metadata.get("display_name") or project.name),
        "path": str(project),
        "running": False,
        "lifecycle_status": "recovery-only",
        "runtime_status": "recovery-only",
        "lifecycle_state": "recovery-only",
        "capabilities": capabilities,
        "workspace_readiness": readiness,
        "resource_profile_label": "Recovery only",
        "findings": [
            {
                "severity": "critical",
                "code": "project.recovery-only",
                "message": status_reason,
                "file": str(metadata_path(project)),
            }
        ],
        "blockers": True,
        "analyzer_cache": {
            "enabled": SETTINGS.enable_analyzer_cache,
            "present": False,
        },
        "lease": {},
        "codexpro": {},
        "git": {"commit": "", "dirty": None},
        "docker_mode": SETTINGS.docker_mode,
        "catalog_only": True,
        "recovery_only": True,
        "ownership_error": str(reason)[-500:],
    }


def list_projects() -> list[dict[str, Any]]:
    SETTINGS.workspaces.mkdir(parents=True, exist_ok=True)
    out = []
    for p in sorted(SETTINGS.workspaces.iterdir()):
        if not p.is_dir():
            continue
        if p.is_symlink():
            out.append(
                {
                    "slug": p.name,
                    "identity": p.name,
                    "display_name": p.name,
                    "template": "unsafe-symlink",
                    "path": str(p),
                    "running": False,
                    "findings": [
                        {
                            "severity": "critical",
                            "code": "project.symlink-directory",
                            "message": "Workspace directories may not be symlinks.",
                            "file": p.name,
                        }
                    ],
                    "blockers": True,
                }
            )
            continue
        try:
            meta = load_authoritative_project_identity_for_mutation(
                p, allow_legacy_migration=True
            )
        except (OSError, ValueError) as exc:
            out.append(_recovery_only_catalog_entry(p, load_meta(p), str(exc)))
            continue
        profile = str(meta.get("profile") or SETTINGS.development_profile)
        findings = analyze_project(p, profile)
        readiness = workspace_readiness(p.name, meta)
        is_running = (
            (readiness["state"] == "running")
            if provider_for(meta).is_vm
            else running(p)
        )
        lease = heartbeat_lease(p) if is_running else load_lease(p)
        capabilities = project_capabilities(
            p.name,
            {
                **meta,
                "lifecycle_status": (
                    "running" if is_running else meta.get("lifecycle_status")
                ),
            },
        )
        try:
            profile_info = get_resource_profile(
                str(meta.get("resource_profile") or "standard")
            )
        except ValueError:
            profile_info = None
        cache_path = p / ".devfleet/runtime/analyzer-cache.json"
        cache_status = {
            "enabled": SETTINGS.enable_analyzer_cache,
            "present": cache_path.is_file(),
        }
        if cache_path.is_file():
            try:
                cached = json.loads(cache_path.read_text())
                cache_status.update(
                    {
                        "profile": cached.get("profile"),
                        "fingerprint": cached.get("fingerprint"),
                        "updated_at": time.strftime(
                            "%Y-%m-%dT%H:%M:%SZ",
                            time.gmtime(cache_path.stat().st_mtime),
                        ),
                    }
                )
            except Exception:
                cache_status["error"] = "unreadable cache"
        out.append(
            {
                **meta,
                "slug": p.name,
                "identity": str(meta.get("identity") or p.name),
                "path": str(p),
                "running": is_running,
                "lifecycle_state": capabilities["lifecycle_state"],
                "capabilities": capabilities,
                "workspace_readiness": readiness,
                "resource_profile_label": (
                    profile_info.label if profile_info else "Custom"
                ),
                "findings": findings,
                "blockers": has_blockers(findings),
                "analyzer_cache": cache_status,
                "lease": lease,
                "codexpro": codexpro_status(p),
                "git": git_summary(p),
                "docker_mode": SETTINGS.docker_mode,
            }
        )
    return out


def list_project_catalog() -> list[dict[str, Any]]:
    """Return only local metadata needed to render ordinary navigation.

    This deliberately does not run analyzer, Docker, Git, lease, or Codex probes.
    Authoritative details are refreshed by the runtime/status snapshot paths.
    """
    SETTINGS.workspaces.mkdir(parents=True, exist_ok=True)
    out = []
    for p in sorted(SETTINGS.workspaces.iterdir(), key=lambda item: item.name):
        if not p.is_dir():
            continue
        if p.is_symlink():
            out.append(
                {
                    "slug": p.name,
                    "identity": p.name,
                    "display_name": p.name,
                    "template": "unsafe-symlink",
                    "path": str(p),
                    "running": False,
                    "findings": [
                        {
                            "severity": "critical",
                            "code": "project.symlink-directory",
                            "message": "Workspace directories may not be symlinks.",
                            "file": p.name,
                        }
                    ],
                    "blockers": True,
                    "catalog_only": True,
                }
            )
            continue
        try:
            meta = load_authoritative_project_identity_for_mutation(
                p, allow_legacy_migration=True
            )
        except (OSError, ValueError) as exc:
            out.append(_recovery_only_catalog_entry(p, load_meta(p), str(exc)))
            continue
        readiness = workspace_readiness(p.name, meta)
        capabilities = project_capabilities(p.name, meta)
        try:
            profile_info = get_resource_profile(
                str(meta.get("resource_profile") or "standard")
            )
        except ValueError:
            profile_info = None
        out.append(
            {
                **meta,
                "slug": p.name,
                "identity": str(meta.get("identity") or p.name),
                "display_name": str(meta.get("display_name") or p.name),
                "path": str(p),
                "running": capabilities["lifecycle_state"] == "running",
                "lifecycle_state": capabilities["lifecycle_state"],
                "capabilities": capabilities,
                "workspace_readiness": readiness,
                "resource_profile_label": (
                    profile_info.label if profile_info else "Custom"
                ),
                "findings": (
                    meta.get("findings")
                    if isinstance(meta.get("findings"), list)
                    else []
                ),
                "blockers": bool(meta.get("blockers", False)),
                "lease": (
                    meta.get("lease") if isinstance(meta.get("lease"), dict) else {}
                ),
                "git": (
                    meta.get("git")
                    if isinstance(meta.get("git"), dict)
                    else {
                        "commit": meta.get("last_known_commit", ""),
                        "dirty": meta.get("last_known_dirty"),
                    }
                ),
                "codexpro": (
                    meta.get("codexpro")
                    if isinstance(meta.get("codexpro"), dict)
                    else {}
                ),
                "docker_mode": SETTINGS.docker_mode,
                "catalog_only": True,
            }
        )
    return out


def _copy_template(project: Path, template: str) -> None:
    src = TEMPLATE_ROOT / template
    if not src.is_dir():
        raise ValueError(f"Template is not installed: {template}")
    for item in src.iterdir():
        dest = project / item.name
        if dest.exists():
            continue
        shutil.copytree(item, dest) if item.is_dir() else shutil.copy2(item, dest)


TRUSTED_TEMPLATE_HOOKS = {
    "bootstrap.sh",
    "codexpro-bootstrap.sh",
    "health-check.sh",
    "smoke-test.sh",
}


def _replace(project: Path, tokens: dict[str, str]) -> None:
    for p in project.rglob("*"):
        if (
            ".git" in p.parts
            or p.is_symlink()
            or not p.is_file()
            or p.stat().st_size >= 1_000_000
        ):
            continue
        try:
            # Keep executable bits (especially .devfleet/*.sh hooks) when replacing
            # template tokens. Path.write_text creates a new file mode from the
            # process umask, which made freshly created projects' test/bootstrap
            # scripts non-executable on Linux.
            mode = p.stat().st_mode
            text = p.read_text()
            for k, v in tokens.items():
                text = text.replace(k, v)
            p.write_text(text)
            if p.parent.name == ".devfleet" and p.name in TRUSTED_TEMPLATE_HOOKS:
                p.chmod(mode | 0o111)
            else:
                p.chmod(mode)
        except (UnicodeDecodeError, OSError):
            pass


def create_project(
    slug: str,
    display_name: str = "",
    template: str = "generic",
    git_url: str = "",
    language: str = "",
    framework: str = "",
    scale: str = "small",
    intent: str = "prototype",
    testing_level: str = "standard",
    profile: str = "",
    resource_profile: str = "",
    resource_limits: dict[str, Any] | None = None,
    runtime_isolation: str = "",
    use_ollama: bool = True,
    worktree_source: str = "",
    worktree_branch: str = "",
    project_kind: str = "",
    operation_context: Any | None = None,
) -> dict[str, Any]:
    slug = validate_slug(slug)
    project = safe_child(SETTINGS.workspaces, slug)
    if project.exists():
        raise ValueError("Project already exists.")
    selected = (profile or SETTINGS.development_profile).lower()
    if selected not in {"strict", "balanced", "fast"}:
        raise ValueError("Profile must be strict, balanced, or fast.")
    selected_isolation = (
        runtime_isolation
        or recommend_runtime_isolation(
            scale=scale, intent=intent, project_kind=project_kind
        )
    ).lower()
    if selected_isolation not in {"container", "vm"}:
        raise ValueError("Runtime isolation must be container or vm.")
    selected_resource, selected_limits = _resource_selection(
        resource_profile,
        resource_limits,
        selected_isolation,
        scale,
        intent,
        project_kind,
        language,
        framework,
    )
    if template in {"auto", "recommended", ""}:
        template = recommend_template(language, framework, scale, intent, project_kind)
    if template not in TEMPLATES:
        raise ValueError("Unknown template.")
    if git_url and not GITHUB_URL_RE.fullmatch(git_url.strip()):
        raise ValueError("Git URL must be a GitHub HTTPS or SSH repository URL.")
    if worktree_source:
        source = safe_child(SETTINGS.workspaces, worktree_source)
        if not source.is_dir() or not (source / ".git").exists():
            raise ValueError(
                "Worktree source must be an existing DevFleet Git project."
            )
        if not BRANCH_RE.fullmatch(worktree_branch):
            raise ValueError("A safe worktree branch is required.")
        # `git worktree add` creates a linked destination even when the source has a
        # normal `.git` directory.  A linked worktree cannot safely be imported into
        # a dedicated VM, so reject the combination before any scaffold or provider
        # operation is created.
        if selected_isolation == "vm":
            raise ValueError(
                "Worktree-to-VM provisioning is blocked because Git worktrees are linked repositories; use a standalone clone/import instead. No VM was created."
            )
    try:
        project.parent.mkdir(parents=True, exist_ok=True)
        project_id = str(uuid.uuid4())
        if operation_context:
            operation_context.update(12, "Project identity reserved", "validate")
        if worktree_source:
            run(
                ["git", "worktree", "add", str(project), worktree_branch],
                cwd=source,
                timeout=600,
            )
        elif git_url:
            run(["git", "clone", "--", git_url, str(project)], timeout=600)
        else:
            project.mkdir()
        _copy_template(project, template)
        tm = template_metadata(template)
        details = json.loads((project / ".devfleet/template.json").read_text())
        chosen_language = language.strip().lower() or tm["language"]
        chosen_framework = framework.strip().lower() or tm["framework"]
        display_name = (display_name or slug).strip()
        if operation_context:
            operation_context.update(28, "Project scaffold created", "scaffold")
        if len(display_name) > 100 or any(ord(c) < 32 for c in display_name):
            raise ValueError("Invalid display name.")
        _replace(
            project,
            {
                "__PROJECT_SLUG__": slug,
                "__PROJECT_NAME__": display_name,
                "__PROJECT_LANGUAGE__": chosen_language,
                "__PROJECT_FRAMEWORK__": chosen_framework,
                "__PROJECT_PROFILE__": selected,
                "__OLLAMA_BASE_URL__": SETTINGS.ollama_base_url,
                "__OLLAMA_MODEL__": SETTINGS.ollama_model,
            },
        )
        hook = project / ".devfleet/codexpro-bootstrap.sh"
        if hook.exists():
            hook.chmod(hook.stat().st_mode | 0o111)
        meta = {
            "schema_version": 5,
            "managed_by": "devfleet",
            "project_id": project_id,
            "slug": slug,
            "identity": slug,
            "display_name": display_name,
            "template": template,
            "git_url": git_url,
            "created_at": now_iso(),
            "updated_at": now_iso(),
            "node_created": SETTINGS.node_name,
            "host_id": SETTINGS.node_name,
            "deployment_id": SETTINGS.deployment_id,
            "profile": selected,
            "docker_mode": SETTINGS.docker_mode,
            "language": chosen_language,
            "framework": chosen_framework,
            "language_rationale": tm["language_rationale"],
            "template_maturity": tm["template_maturity"],
            "project_scale": scale,
            "intent": intent,
            "testing_level": testing_level,
            "resource_profile": selected_resource,
            "resource_limits": selected_limits,
            "runtime_isolation": selected_isolation,
            "runtime_type": selected_isolation,
            "runtime_provider": (
                "multipass-host-agent"
                if selected_isolation == "vm"
                else "docker-compose"
            ),
            "runtime_status": (
                "host-provisioning-required"
                if selected_isolation == "vm"
                else "container-ready"
            ),
            "lifecycle_status": "provisioning",
            "provisioning_status": "pending",
            "health_status": "unknown",
            "runtime_id": compose_name(slug) if selected_isolation == "container" else "",
            "runtime_address": "",
            "gpu_enabled": False,
            "backup_status": "not-verified",
            "quarantine_state": "active",
            "last_error": "",
            "last_operation_id": "",
            "workspace_location": str(project),
            "workspace_host": SETTINGS.node_name,
            "workspace_user": "devrunner",
            "workspace_path": f"/home/devrunner/workspaces/{slug}",
            "use_ollama": bool(use_ollama),
            "ollama_endpoint": SETTINGS.ollama_base_url if use_ollama else "",
            "ollama_model": SETTINGS.ollama_model if use_ollama else "",
            "allow_tailnet_ports": selected != "strict",
            "allow_devices": False,
            "allow_privileged": False,
            "worktree": bool(worktree_source),
            "worktree_source": worktree_source,
            "worktree_branch": worktree_branch,
            "bootstrap_command": details.get(
                "bootstrap_command", "./.devfleet/bootstrap.sh"
            ),
            "format_command": details.get("format_command", ""),
            "lint_command": details.get("lint_command", ""),
            "test_command": details.get("test_command", "./.devfleet/smoke-test.sh"),
            "health_command": details.get(
                "health_command", "./.devfleet/health-check.sh"
            ),
            "start_command": details.get("start_command", ""),
            "stop_command": details.get("stop_command", ""),
            "restart_command": details.get("restart_command", ""),
            "rebuild_command": details.get("rebuild_command", ""),
            "logs_command": details.get("logs_command", ""),
            "codexpro_command": details.get("codexpro_command", ""),
        }
        meta["ssh_alias"] = (
            "devfleet-primary"
            if selected_isolation == "container"
            else f"devfleet-project-{slug}"
        )
        _write_project_metadata(project, meta, create=True)
        if operation_context:
            operation_context.update(45, "Runtime metadata persisted", "persist")
        compose = compose_file(project)
        if compose and selected_isolation == "container":
            _write_current_compose_ownership(project, compose, meta)
        if (
            compose
            and selected_isolation == "container"
            and write_resource_override(project, compose, selected_limits) is None
        ):
            raise ValueError(
                "Compose services could not be read; no resource override was written."
            )
        if not (project / ".git").exists():
            run(["git", "init"], cwd=project)
        run(["git", "add", "."], cwd=project, check=False)
        if s