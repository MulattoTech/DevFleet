# DevFleet source part 070

Full-source UTF-8 byte interval [3208500, 3255000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 70a160b9e2b14a6b171bfad8a55e55725c0b251a52456fe0e8bb1c9980523fb7

<!-- BEGIN SOURCE SLICE -->
ect_kind=project_kind,
        language=language,
        framework=framework,
    )
    return {
        "resource_profile": resource.name,
        "resource_limits": resource.__dict__,
        "runtime_isolation": recommend_runtime_isolation(
            scale=scale, intent=intent, project_kind=project_kind
        ),
        "runtime_options": RUNTIME_ISOLATIONS,
    }


@app.post("/projects/create")
def project_create(
    request: Request,
    slug: str = Form(...),
    display_name: str = Form(""),
    template: str = Form("auto"),
    git_url: str = Form(""),
    target: str = Form("local"),
    language: str = Form(""),
    framework: str = Form(""),
    scale: str = Form("small"),
    intent: str = Form("prototype"),
    testing_level: str = Form("standard"),
    profile: str = Form("balanced"),
    resource_profile: str = Form(""),
    runtime_isolation: str = Form(""),
    use_ollama: bool = Form(False),
    worktree_source: str = Form(""),
    worktree_branch: str = Form(""),
    project_kind: str = Form(""),
    custom_cpus: str = Form(""),
    custom_ram_gb: str = Form(""),
    custom_disk_gb: str = Form(""),
    pid_mode: str = Form("private"),
    pid_limit: str = Form("4096"),
    csrf_token: str = Form(""),
):
    ui(request, csrf_token)
    payload = {
        "slug": slug,
        "display_name": display_name,
        "template": template,
        "git_url": git_url,
        "language": language,
        "framework": framework,
        "scale": scale,
        "intent": intent,
        "testing_level": testing_level,
        "profile": profile,
        "resource_profile": resource_profile,
        "resource_limits": _form_resource_limits(
            resource_profile,
            custom_cpus,
            custom_ram_gb,
            custom_disk_gb,
            pid_limit,
            pid_mode,
        ),
        "runtime_isolation": runtime_isolation,
        "use_ollama": use_ollama,
        "worktree_source": worktree_source,
        "worktree_branch": worktree_branch,
        "project_kind": project_kind,
    }
    if profile == "fast":
        raise HTTPException(
            400,
            "Use the explicit Fast profile acknowledgement after creating the project in Balanced mode.",
        )

    def task(ctx):
        ctx.update(10, "Validating project request", "validate")
        result = (
            peer_call("POST", "/api/projects/create", payload)
            if target == "peer"
            else create_project(operation_context=ctx, **payload)
        )
        ctx.update(90, "Project runtime provisioned", "verify")
        return result

    return redirect(
        submit_operation("peer-create" if target == "peer" else "create", slug, task)
    )


@app.get("/projects/{slug}", response_class=HTMLResponse)
def project_page(request: Request, slug: str):
    ui(request)
    return index(
        request,
        operation=request.query_params.get("operation", ""),
        view="project",
        project=slug,
    )


@app.get("/projects/{slug}/workspace")
def project_workspace(request: Request, slug: str):
    ui(request)
    _require_owned_project_for_mutation(slug)
    result = open_workspace(slug)
    if not result.get("ok"):
        raise HTTPException(
            409, str(result.get("error") or "Workspace is not ready to open.")
        )
    return RedirectResponse(str(result["launcher_uri"]), status_code=307)


@app.post("/projects/{slug}/environment")
def project_environment(
    request: Request,
    slug: str,
    runtime_isolation: str = Form("container"),
    resource_profile: str = Form(""),
    custom_cpus: str = Form(""),
    custom_ram_gb: str = Form(""),
    custom_disk_gb: str = Form(""),
    pid_mode: str = Form("private"),
    pid_limit: str = Form("4096"),
    wizard_confirmed: bool = Form(False),
    csrf_token: str = Form(""),
):
    ui(request, csrf_token)
    if not wizard_confirmed:
        raise HTTPException(
            400,
            "Complete the Environment, Resources, Review, and Confirm stages before applying this assignment.",
        )
    _require_owned_project_for_mutation(slug, allow_legacy_migration=True)
    preflight = _preflight(
        slug,
        runtime_isolation,
        resource_profile,
        custom_cpus,
        custom_ram_gb,
        custom_disk_gb,
        pid_mode,
        pid_limit,
    )
    if not preflight["migration_ready"]:
        raise HTTPException(
            409,
            "Environment preflight is not ready: " + "; ".join(preflight["blockers"]),
        )
    limits = _form_resource_limits(
        resource_profile,
        custom_cpus,
        custom_ram_gb,
        custom_disk_gb,
        pid_limit,
        pid_mode,
    )

    def task(ctx):
        ctx.update(
            8, "Validating the existing workspace and selected environment", "validate"
        )
        result = assign_project_runtime(
            slug, runtime_isolation, resource_profile, limits, operation_context=ctx
        )
        ctx.log(json.dumps(result, default=str)[-4000:])
        return result

    operation_id = submit_operation(
        "runtime-adoption",
        slug,
        task,
        idempotency_key=f'runtime-adoption:{slug}:{runtime_isolation}:{resource_profile or "current"}',
    )
    if ui_wants_json(request):
        return JSONResponse(
            {
                "ok": True,
                "operation_id": operation_id,
                "message": "Environment assignment queued.",
            },
            status_code=202,
        )
    return redirect(operation_id)


@app.post("/projects/{slug}/{action}")
def project_action(
    request: Request,
    slug: str,
    action: str,
    confirm_failover: bool = Form(False),
    confirm_quarantine: bool = Form(False),
    confirm_slug: str = Form(""),
    confirm_phrase: str = Form(""),
    backup_id: str = Form(""),
    confirm_restore: bool = Form(False),
    allow_overwrite: bool = Form(False),
    csrf_token: str = Form(""),
):
    ui(request, csrf_token)
    if action not in PROJECT_ACTIONS:
        raise HTTPException(404, "Unknown project action.")
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
    if action == "quarantine" and not confirm_quarantine:
        raise HTTPException(400, "Quarantine requires explicit acknowledgement.")
    if action == "destroy" and (
        confirm_slug != slug or confirm_phrase != f"DESTROY {slug}"
    ):
        raise HTTPException(400, "Permanent destruction requires exact confirmation.")
    if action == "restore-backup" and (not confirm_restore or not backup_id):
        raise HTTPException(400, "Backup restore requires an identified backup and explicit confirmation.")

    payload = {
        "confirm_failover": confirm_failover,
        "confirm_quarantine": confirm_quarantine,
        "confirm_slug": confirm_slug,
        "confirm_phrase": confirm_phrase,
        "backup_id": backup_id,
        "confirm_restore": confirm_restore,
        "allow_overwrite": allow_overwrite,
    }
    shared_task = _project_action_task(slug, action, payload)
    def task(ctx):
        return shared_task(ctx)

    idempotency_key = _action_idempotency_key(slug, action, payload)
    operation_id = submit_operation(action, slug, task, idempotency_key=idempotency_key)
    if ui_wants_json(request):
        return JSONResponse({"ok": True, "operation_id": operation_id}, status_code=202)
    return redirect(operation_id)


@app.post("/projects/{slug}/profile")
def project_profile(
    request: Request,
    slug: str,
    profile: str = Form(...),
    confirm_fast: bool = Form(False),
    allow_devices: bool = Form(False),
    allow_privileged: bool = Form(False),
    csrf_token: str = Form(""),
):
    ui(request, csrf_token)
    profile = profile.lower()
    if profile not in {"strict", "balanced", "fast"}:
        raise HTTPException(400, "Unknown profile.")
    if profile == "fast" and not confirm_fast:
        raise HTTPException(400, "Fast Trusted mode requires explicit acknowledgement.")
    if (allow_devices or allow_privileged) and (profile != "fast" or not confirm_fast):
        raise HTTPException(
            400, "Device or privileged access requires Fast Trusted acknowledgement."
        )
    project = safe_child(SETTINGS.workspaces, slug)
    meta = _require_owned_project_for_mutation(slug)
    previous = str(meta.get("profile") or SETTINGS.development_profile)
    meta.setdefault("profile_history", []).append(
        {
            "from": previous,
            "to": profile,
            "time": __import__("time").strftime(
                "%Y-%m-%dT%H:%M:%SZ", __import__("time").gmtime()
            ),
        }
    )
    meta["profile_history"] = meta["profile_history"][-50:]
    meta["profile"] = profile
    meta["allow_tailnet_ports"] = profile != "strict"
    meta["allow_devices"] = bool(allow_devices) if profile == "fast" else False
    meta["allow_privileged"] = bool(allow_privileged) if profile == "fast" else False
    commit_project_metadata(project, meta)
    analyze_project(project, profile, force=True)
    return RedirectResponse("/", 303)


@app.post("/peer/projects/{slug}/{action}")
def peer_project_action(
    request: Request,
    slug: str,
    action: str,
    confirm_failover: bool = Form(False),
    confirm_quarantine: bool = Form(False),
    csrf_token: str = Form(""),
):
    ui(request, csrf_token)
    payload = {
        "confirm_failover": bool(confirm_failover),
        "confirm_quarantine": bool(confirm_quarantine),
    }

    def task(ctx):
        ctx.update(15, "Sending authenticated action to peer")
        result = peer_call("POST", f"/api/projects/{slug}/{action}", payload)
        ctx.log(str(result)[-4000:])
        ctx.update(90, "Peer action completed")
        return result

    return redirect(submit_operation("peer-" + action, slug, task))


@app.post("/repair")
def repair(request: Request, csrf_token: str = Form("")):
    ui(request, csrf_token)

    def task(ctx):
        ctx.update(20, "Running non-destructive node repair")
        result = run(["/usr/local/bin/devfleet-user-repair"], timeout=600).stdout[
            -8000:
        ]
        ctx.log(result)
        ctx.update(90, "Repair health checks completed")
        return result

    return redirect(submit_operation("repair", "node", task))


@app.post("/projects/{slug}/transfer-to-peer")
def transfer(request: Request, slug: str, csrf_token: str = Form("")):
    ui(request, csrf_token)
    metadata = _require_owned_project_for_mutation(slug)
    if metadata.get("runtime_isolation") == "vm":
        raise HTTPException(
            409,
            "Dedicated-VM peer transfer is blocked until a verified node-to-node VM transfer protocol is available. The current VM remains the canonical owner.",
        )
    state = peer_node_status()
    if not state.get("ok"):
        raise HTTPException(
            409,
            "DevFleetFailover is offline or unavailable; ownership transfer is disabled.",
        )
    project_id = str(metadata.get("project_id") or "")
    deployment_id = str(metadata.get("deployment_id") or "")
    source_host_id = str(metadata.get("host_id") or "")
    try:
        validate_project_id(project_id)
        validate_project_id(deployment_id)
    except ValueError as exc:
        raise HTTPException(409, "Project transfer identity is incomplete.") from exc
    if not source_host_id:
        raise HTTPException(409, "Project transfer source host identity is missing.")
    if (
        deployment_id != str(SETTINGS.deployment_id or "")
        or source_host_id != SETTINGS.host_id
    ):
        raise HTTPException(
            409, "Project transfer source is not owned by this node and deployment."
        )
    peer_node = state.get("node") if isinstance(state.get("node"), dict) else {}
    peer_identity = (
        peer_node.get("node_identity")
        if isinstance(peer_node.get("node_identity"), dict)
        else {}
    )
    destination_host_id = str(peer_node.get("node") or "")
    if (
        not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", destination_host_id
        )
        or destination_host_id == source_host_id
        or str(peer_identity.get("deployment_id") or "") != deployment_id
    ):
        raise HTTPException(
            409, "Peer transfer identity is not bound to this deployment."
        )

    def task(ctx):
        with project_transfer_lock(slug):
            return guided_transfer(
                slug,
                ctx,
                stop=stop_project,
                backup=backup_project,
                assert_quiesced=assert_project_quiesced_for_transfer,
                project_id=project_id,
                deployment_id=deployment_id,
                source_host_id=source_host_id,
                destination_host_id=destination_host_id,
                finalize_source=finalize_source_transfer,
                peer_call=peer_call,
            )

    return redirect(
        submit_operation(
            "ownership-transfer",
            slug,
            task,
            project_id=project_id,
            runtime_id=str(metadata.get("runtime_id") or ""),
            host_id=source_host_id,
            idempotency_key=(
                f"ownership-transfer:{slug}:{project_id}:{deployment_id}:"
                f"{source_host_id}:{destination_host_id}"
            ),
        )
    )


@app.post("/quarantine/restore")
def restore(request: Request, name: str = Form(...), csrf_token: str = Form("")):
    ui(request, csrf_token)

    def task(ctx):
        ctx.update(20, "Restoring reversible quarantine entry")
        result = restore_quarantine(name)
        ctx.update(90, "Quarantine entry restored")
        return result

    return redirect(submit_operation("restore-quarantine", name, task))


@app.get("/projects/{slug}/logs", response_class=HTMLResponse)
def logs(request: Request, slug: str):
    ui(request)
    safe_child(SETTINGS.workspaces, slug)
    return RedirectResponse(f"/projects/{slug}?tab=logs", 303)


@app.get("/ui/projects/{slug}/logs")
def ui_project_logs(request: Request, slug: str, tail: int = 150):
    ui(request)
    project = safe_child(SETTINGS.workspaces, slug)
    if not project.is_dir():
        raise HTTPException(404, "Project not found.")
    meta = _require_owned_project_for_mutation(slug)
    capabilities = project_capabilities(slug, meta)
    if not capabilities["can_query_logs"]:
        return JSONResponse(
            {
                "ok": False,
                "slug": slug,
                "state": capabilities["lifecycle_state"],
                "terminal": True,
                "logs": "Start the project to view live logs.",
                "capabilities": capabilities,
            },
            status_code=409,
        )
    bounded = max(1, min(int(tail), 500))
    try:
        logs_value = project_logs(slug, tail=bounded)
    except FileNotFoundError:
        raise HTTPException(404, "Project not found.")
    except (OSError, ValueError, RuntimeError) as exc:
        raise HTTPException(503, f"Project logs unavailable: {str(exc)[-500:]}")
    return JSONResponse(
        {
            "ok": True,
            "slug": slug,
            "tail": bounded,
            "provider": meta.get("runtime_provider")
            or meta.get("runtime_isolation")
            or "unknown",
            "logs": str(logs_value)[-30000:],
        }
    )


@app.get("/api/projects/{slug}/runtime", dependencies=[Depends(check_api)])
def api_project_runtime(slug: str):
    project = safe_child(SETTINGS.workspaces, slug)
    meta = _require_owned_project_for_mutation(slug)
    capabilities = project_capabilities(slug, meta)
    if not capabilities["can_query_live_metrics"]:
        return {
            "ok": True,
            "project": meta,
            "capabilities": capabilities,
            "runtime": {
                "status": "unavailable",
                "reason": capabilities["status_reason"],
                "live_metrics": "unavailable",
            },
            "health": {
                "status": "not-checked",
                "reason": (
                    "environment stopped"
                    if capabilities["lifecycle_state"] == "stopped"
                    else capabilities["status_reason"]
                ),
            },
        }
    return {
        "ok": True,
        "project": meta,
        "capabilities": capabilities,
        "runtime": inspect_runtime(slug),
        "health": runtime_health(slug),
    }


@app.get("/api/projects/{slug}/capabilities", dependencies=[Depends(check_api)])
def api_project_capabilities(slug: str):
    metadata = _require_owned_project_for_mutation(slug)
    return {"ok": True, "capabilities": project_capabilities(slug, metadata)}


@app.get("/api/projects/{slug}/workspace", dependencies=[Depends(check_api)])
def api_project_workspace(slug: str):
    _require_owned_project_for_mutation(slug)
    return open_workspace(slug)


@app.get("/api/projects/{slug}/logs", dependencies=[Depends(check_api)])
def api_project_logs(slug: str, tail: int = 150):
    metadata = _require_owned_project_for_mutation(slug)
    capabilities = project_capabilities(slug, metadata)
    if not capabilities["can_query_logs"]:
        raise HTTPException(
            409,
            f"Logs unavailable: {capabilities['status_reason'] or 'environment is not ready.'}",
        )
    bounded = max(1, min(int(tail), 500))
    return {
        "ok": True,
        "slug": slug,
        "tail": bounded,
        "logs": project_logs(slug, tail=bounded),
    }


@app.get("/ui/projects/{slug}/backups")
def ui_project_backups(request: Request, slug: str):
    ui(request)
    _require_owned_project_for_mutation(slug)
    return JSONResponse({"ok": True, "backups": list_backups(slug)})


@app.get("/api/projects/{slug}/backups", dependencies=[Depends(check_api)])
def api_project_backups(slug: str):
    _require_owned_project_for_mutation(slug)
    return {"ok": True, "backups": list_backups(slug)}


@app.get("/api/projects/{slug}/environment", dependencies=[Depends(check_api)])
def api_project_environment(slug: str):
    _require_owned_project_for_mutation(slug)
    detected = detect_runtime(slug)
    capacity = {}
    try:
        capacity = get_host_capacity()
    except Exception as exc:
        capacity = {"ok": False, "status": "unavailable", "error": str(exc)[-500:]}
    nodes = []
    for node in cluster_status().get("nodes", []):
        nodes.append(
            {
                "id": node.get("id"),
                "name": node.get("friendly_name") or node.get("id"),
                "status": node.get("status"),
                "reachable": bool(node.get("reachable")),
                "selectable": bool(
                    node.get("destination_selectable", node.get("reachable"))
                ),
                "reason": node.get("error", ""),
            }
        )
    return {
        "ok": True,
        "project": detected,
        "detected_runtime": detected,
        "runtime_options": RUNTIME_ISOLATIONS,
        "resource_profiles": {
            name: profile.__dict__ for name, profile in RESOURCE_PROFILES.items()
        },
        "capacity": capacity,
        "nodes": nodes,
        "workspace_preserved_by_default": True,
    }


@app.get("/api/projects/{slug}/preflight", dependencies=[Depends(check_api)])
def api_project_preflight(
    slug: str,
    runtime_isolation: str = "",
    resource_profile: str = "",
    custom_cpus: str = "",
    custom_ram_gb: str = "",
    custom_disk_gb: str = "",
    pid_mode: str = "private",
    pid_limit: str = "4096",
):
    return _preflight(
        slug,
        runtime_isolation,
        resource_profile,
        custom_cpus,
        custom_ram_gb,
        custom_disk_gb,
        pid_mode,
        pid_limit,
    )


@app.get("/ui/projects/{slug}/preflight")
def ui_project_preflight(
    request: Request,
    slug: str,
    runtime_isolation: str = "",
    resource_profile: str = "",
    custom_cpus: str = "",
    custom_ram_gb: str = "",
    custom_disk_gb: str = "",
    pid_mode: str = "private",
    pid_limit: str = "4096",
):
    ui(request)
    try:
        return JSONResponse(
            _preflight(
                slug,
                runtime_isolation,
                resource_profile,
                custom_cpus,
                custom_ram_gb,
                custom_disk_gb,
                pid_mode,
                pid_limit,
            )
        )
    except FileNotFoundError:
        raise HTTPException(404, "Project not found.")


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
        self.asse