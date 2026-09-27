# DevFleet source part 071

Full-source UTF-8 byte interval [3255000, 3301500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: abbcba0ab13cc0283547cac058b4e072db6e38397e93128b6e3fd40c27aecb4e

<!-- BEGIN SOURCE SLICE -->
meta.get("identity") or meta.get("slug") or slug))


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
        if selected_isolation == "vm":
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
                _write_project_metadata(projec