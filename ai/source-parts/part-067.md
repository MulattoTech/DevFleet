# DevFleet source part 067

Full-source UTF-8 byte interval [3069000, 3115500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2e55dfd7a882914d46a521c8d46913425d7e3165771b590d4976274a1d964d60

<!-- BEGIN SOURCE SLICE -->
, "runArgs", "privileged", "capAdd", "securityOpt", "features", "overrideFeatureInstallOrder",
    "initializeCommand", "onCreateCommand", "updateContentCommand", "postCreateCommand", "postStartCommand",
    "postAttachCommand", "forwardPorts", "portsAttributes", "otherPortsAttributes", "appPort", "init", "customizations",
    "hostRequirements", "waitFor", "userEnvProbe", "secrets",
}


def finding(severity: str, code: str, message: str, file: str = "") -> dict[str, str]:
    return {"severity": severity, "code": code, "message": message, "file": file}


def _unsafe_source(source: str) -> str | None:
    source = source.strip()
    norm = source.replace("\\", "/")
    if not source:
        return "empty path"
    if "$" in source:
        return "environment-variable interpolation"
    if WINDOWS_PATH.search(source) or UNC_PATH.search(source):
        return "Windows/UNC host path"
    if DOCKER_SOCKET.search(source):
        return "Docker socket"
    if source.startswith(("/", "~")):
        return "absolute host path"
    if ".." in PurePosixPath(norm).parts:
        return "parent-directory traversal"
    return None


def _severity(profile: str, kind: str) -> str:
    p = get_profile(profile)
    if kind in {"hardening", "health"}:
        return "critical" if p.block_hardening else "warning"
    if kind in {"device", "privileged"}:
        return "warning" if p.name == "fast" else "critical"
    return "critical"


def _inside_project(project: Path, candidate: Path) -> bool:
    try:
        candidate.resolve(strict=False).relative_to(project.resolve())
        return True
    except ValueError:
        return False


def _contains_symlink(project: Path, candidate: Path) -> bool:
    try:
        relative = candidate.relative_to(project)
    except ValueError:
        return True
    current = project
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            return True
    return False


def _reference(project: Path, base: Path, raw: Any, rel: str, kind: str, findings: list[dict[str, str]], references: set[Path], *, required: bool = False) -> Path | None:
    path_code = "docker.mount-resolution" if kind == "bind mount source" else "docker.build-context" if kind == "build.context" else "compose.path-escape"
    value = str(raw or "").strip()
    reason = _unsafe_source(value)
    if reason:
        findings.append(finding("critical", "compose.path-reference", f"{kind} is unsafe ({reason}): {value!r}.", rel))
        return None
    candidate = (base / value).resolve(strict=False)
    if not _inside_project(project, candidate):
        findings.append(finding("critical", path_code, f"{kind} resolves outside the project boundary: {value!r}.", rel))
        return None
    lexical = base / value
    if _contains_symlink(project, lexical):
        findings.append(finding("critical", path_code, f"{kind} may not traverse a symlink: {value!r}.", rel))
        return None
    if required and not candidate.is_file():
        findings.append(finding("critical", "compose.missing-reference", f"Referenced {kind} does not exist: {value!r}.", rel))
        return None
    references.add(candidate)
    return candidate


def _short_bind_source(value: str) -> str | None:
    value = value.strip()
    if not value:
        return None
    if WINDOWS_PATH.search(value) or UNC_PATH.search(value) or DOCKER_SOCKET.search(value):
        return value
    if ":" not in value:
        return value if value.startswith((".", "..", "/", "~")) else None
    return value.split(":", 1)[0]


def _volume_source(value: Any) -> tuple[str, bool]:
    if isinstance(value, dict):
        kind = str(value.get("type", "volume")).lower()
        source = str(value.get("source") or value.get("src") or "")
        return source, kind == "bind"
    source = _short_bind_source(str(value))
    return source or "", source is not None


def _parse_yaml(path: Path) -> dict[str, Any] | None:
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return None
    return value if isinstance(value, dict) else None


def _iter_env_files(value: Any) -> Iterable[Any]:
    if isinstance(value, (str, dict)):
        return (value,)
    return value or ()


def _strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from _strings(key)
            yield from _strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)


def _preflight_compose(project: Path, path: Path, findings: list[dict[str, str]], references: set[Path], seen: set[Path], state: dict[str, int], depth: int) -> dict[str, Any] | None:
    rel = str(path.relative_to(project)) if _inside_project(project, path) else str(path)
    if depth > MAX_REFERENCE_DEPTH:
        findings.append(finding("critical", "compose.reference-depth", "Compose reference depth exceeds the bounded policy.", rel))
        return None
    path = path.resolve(strict=False)
    if path in seen:
        return _parse_yaml(path)
    if len(seen) >= MAX_REFERENCE_FILES:
        findings.append(finding("critical", "compose.reference-count", "Compose reference count exceeds the bounded policy.", rel))
        return None
    seen.add(path)
    if not path.is_file():
        findings.append(finding("critical", "compose.missing-reference", "Compose configuration is missing.", rel))
        return None
    state["bytes"] += path.stat().st_size
    if state["bytes"] > MAX_REFERENCE_BYTES:
        findings.append(finding("critical", "compose.reference-bytes", "Compose referenced input bytes exceed the bounded policy.", rel))
        return None
    data = _parse_yaml(path)
    if data is None:
        findings.append(finding("error", "yaml.invalid", "Compose configuration is not a YAML object.", rel))
        return None
    if any("${" in text for text in _strings(data)):
        findings.append(finding("critical", "compose.interpolation", "Compose environment interpolation is blocked in the security-reviewed subset.", rel))
    for key in data:
        if not str(key).startswith("x-") and key not in COMPOSE_TOP_LEVEL_KEYS:
            findings.append(finding("critical", "compose.unknown-field", f"Unreviewed top-level Compose field is blocked: {key!r}.", rel))
    includes = data.get("include")
    if includes:
        findings.append(finding("critical", "compose.include", "Compose include is blocked until a bounded resolver is certified.", rel))
        entries = includes if isinstance(includes, list) else [includes]
        for entry in entries:
            include_path = entry.get("path") if isinstance(entry, dict) else entry
            included = _reference(project, path.parent, include_path, rel, "Compose include", findings, references)
            if included and included.is_file():
                _preflight_compose(project, included, findings, references, seen, state, depth + 1)
    services = data.get("services") or {}
    if not isinstance(services, dict):
        findings.append(finding("error", "compose.services", "Compose services must be a mapping.", rel))
        return data
    for name, service in services.items():
        if not isinstance(service, dict):
            findings.append(finding("error", "compose.service", f"Compose service {name!r} must be a mapping.", rel))
            continue
        for key in service:
            if key not in COMPOSE_SERVICE_KEYS and not str(key).startswith("x-"):
                findings.append(finding("critical", "compose.unknown-field", f"Unreviewed service field is blocked: {name}.{key}.", rel))
        extends = service.get("extends")
        if extends:
            findings.append(finding("critical", "compose.extends", "Compose extends is blocked until effective-model resolution is certified.", rel))
            if isinstance(extends, dict) and extends.get("file"):
                inherited = _reference(project, path.parent, extends.get("file"), rel, "Compose extends file", findings, references)
                if inherited and inherited.is_file():
                    _preflight_compose(project, inherited, findings, references, seen, state, depth + 1)
        for env_file in _iter_env_files(service.get("env_file")):
            env_path = env_file.get("path") if isinstance(env_file, dict) else env_file
            _reference(project, path.parent, env_path, rel, "env_file", findings, references)
        build = service.get("build")
        if isinstance(build, str):
            _reference(project, path.parent, build, rel, "build.context", findings, references)
        elif isinstance(build, dict):
            context = build.get("context")
            if context:
                context_path = _reference(project, path.parent, context, rel, "build.context", findings, references)
                if context_path and build.get("dockerfile"):
                    _reference(project, context_path.parent, build.get("dockerfile"), rel, "build.dockerfile", findings, references, required=True)
        for volume in service.get("volumes") or ():
            source, is_bind = _volume_source(volume)
            if is_bind:
                _reference(project, path.parent, source, rel, "bind mount source", findings, references)
        for key in ("secrets", "configs"):
            value = service.get(key)
            if value:
                findings.append(finding("critical", "compose.secret-config", f"Service {name}.{key} is blocked until host-file authorization is certified.", rel))
    for key in ("secrets", "configs"):
        declarations = data.get(key)
        if isinstance(declarations, dict):
            for name, declaration in declarations.items():
                if isinstance(declaration, dict) and declaration.get("file"):
                    _reference(project, path.parent, declaration["file"], rel, f"{key}.{name} file", findings, references, required=True)
                if declaration:
                    findings.append(finding("critical", "compose.secret-config", f"Top-level {key}.{name} is blocked until host-file authorization is certified.", rel))
    return data


def _scan_compose_service(project: Path, path: Path, name: str, svc: dict[str, Any], profile: str, out: list[dict[str, str]]) -> None:
    rel = str(path.relative_to(project))
    metadata: dict[str, Any] = {}
    try:
        value = read_project_metadata(project).value
        metadata = value if isinstance(value, dict) else {}
    except Exception:
        pass
    for key in COMPOSE_UNSUPPORTED_KEYS:
        if key in svc and svc.get(key) not in (None, False, [], {}):
            out.append(finding("critical", f"compose.{key.replace('_', '-')}", f"{name}.{key} is blocked by the supported Compose security policy.", rel))
    if svc.get("container_name"):
        out.append(finding("critical" if profile == "strict" else "warning", "docker.container-name", f"{name}: explicit container_name can collide across projects.", rel))
    if svc.get("privileged") is True:
        severity = _severity(profile, "privileged")
        if profile == "fast" and not metadata.get("allow_privileged"):
            severity = "critical"
        out.append(finding(severity, "docker.privileged", f"{name}: privileged mode requires Fast Trusted plus project-level acknowledgement.", rel))
    for key in COMPOSE_HOST_NAMESPACE_KEYS:
        value = str(svc.get(key, "")).lower()
        if value == "host" or value.startswith(("container:", "service:")):
            out.append(finding("critical", "docker.host-namespace", f"{name}: {key}={value} is forbidden.", rel))
    caps = [str(x).upper() for x in (svc.get("cap_add") or [])]
    if caps:
        severity = _severity(profile, "device")
        if profile == "fast" and not metadata.get("allow_privileged"):
            severity = "critical"
        out.append(finding(severity, "docker.capabilities", f"{name}: capabilities require explicit reviewed acknowledgement: {caps}.", rel))
    if svc.get("devices"):
        severity = _severity(profile, "device")
        if profile == "fast" and not metadata.get("allow_devices"):
            severity = "critical"
        out.append(finding(severity, "docker.devices", f"{name}: device access requires Fast Trusted plus project-level acknowledgement.", rel))
    for volume in svc.get("volumes") or ():
        source, is_bind = _volume_source(volume)
        if is_bind:
            reason = _unsafe_source(source)
            if reason:
                out.append(finding("critical", "docker.mount", f"{name}: rejected {reason}: {source!r}.", rel))
    build = svc.get("build")
    if build:
        context = build if isinstance(build, str) else str(build.get("context", "."))
        reason = _unsafe_source(context)
        if reason and context not in {".", "./"}:
            out.append(finding("critical", "docker.build-context", f"{name}: rejected {reason}: {context}.", rel))
        if isinstance(build, dict) and build.get("privileged"):
            out.append(finding("critical", "docker.build-privileged", f"{name}: privileged image builds are blocked.", rel))
        if isinstance(build, dict) and build.get("secrets"):
            out.append(finding("critical", "docker.build-secrets", f"{name}: build secrets are blocked.", rel))
        context_path = (path.parent / context).resolve(strict=False)
        dockerfile_name = "Dockerfile" if isinstance(build, str) else str(build.get("dockerfile", "Dockerfile"))
        dockerfile = (context_path / dockerfile_name).resolve(strict=False)
        if _inside_project(project, dockerfile) and dockerfile.is_file():
            users = []
            for line in dockerfile.read_text(encoding="utf-8", errors="ignore").splitlines():
                parts = line.split(None, 1)
                if len(parts) == 2 and parts[0].upper() == "USER":
                    users.append(parts[1].strip())
            if not users or users[-1].lower() in {"root", "0", "0:0"}:
                out.append(finding(_severity(profile, "hardening"), "docker.non-root-user", f"{name}: Dockerfile does not finish with a non-root USER.", str(dockerfile.relative_to(project))))
    for env_file in _iter_env_files(svc.get("env_file")):
        value = str(env_file.get("path", "")) if isinstance(env_file, dict) else str(env_file)
        reason = _unsafe_source(value)
        if reason:
            out.append(finding("critical", "docker.env-file", f"{name}: unsafe env_file ({reason}): {value}.", rel))
    for port in svc.get("ports") or ():
        state, text = _port_state(port)
        if state == "public":
            out.append(finding("critical", "docker.port-public", f"{name}: public/unbound port publication is forbidden: {text}.", rel))
        elif state == "tailnet" and not (get_profile(profile).allow_tailnet and SETTINGS.allow_tailnet_ports):
            out.append(finding("critical", "docker.port-tailnet", f"{name}: tailnet port requires policy approval: {text}.", rel))
    if "healthcheck" not in svc:
        out.append(finding(_severity(profile, "health"), "docker.healthcheck", f"{name}: no container healthcheck is defined.", rel))
    image = str(svc.get("image", ""))
    if image.endswith(":latest") or (image and ":" not in image):
        out.append(finding(_severity(profile, "hardening"), "docker.unpinned-image", f"{name}: development image is not pinned.", rel))
    security = [str(x).lower() for x in (svc.get("security_opt") or [])]
    if any("unconfined" in x for x in security):
        out.append(finding("critical", "docker.unconfined", f"{name}: unconfined security profile is forbidden.", rel))
    if not any("no-new-privileges" in x for x in security):
        out.append(finding(_severity(profile, "hardening"), "docker.no-new-privileges", f"{name}: no-new-privileges is not set.", rel))


def _strip_jsonc(text: str) -> str:
    result: list[str] = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        char = text[i]
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            i += 1
            continue
        if char == '"':
            in_string = True
            result.append(char)
            i += 1
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
        else:
            result.append(char)
            i += 1
    return re.sub(r",\s*([}\]])", r"\1", "".join(result))


def _parse_jsonc(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(_strip_jsonc(path.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def _scan_devcontainer(project: Path, profile: str, out: list[dict[str, str]], references: set[Path]) -> None:
    path = project / ".devcontainer/devcontainer.json"
    if not path.exists():
        return
    rel = str(path.relative_to(project))
    if path.is_symlink():
        out.append(finding("critical", "project.symlink-config", "devcontainer.json may not be a symbolic link.", rel))
        return
    data = _parse_jsonc(path)
    if data is None:
        out.append(finding("error", "devcontainer.json.invalid", "devcontainer.json is not valid bounded JSONC.", rel))
        return
    for key in data:
        if key not in DEVCONTAINER_KEYS and not key.startswith("x-"):
            out.append(finding("critical", "devcontainer.unknown-field", f"Unreviewed Dev Container field is blocked: {key!r}.", rel))
    compose_files = data.get("dockerComposeFile")
    compose_files = compose_files if isinstance(compose_files, list) else ([compose_files] if compose_files else [])
    for compose_file in compose_files:
        lexical = path.parent / str(compose_file)
        candidate = lexical.resolve(strict=False)
        if not _inside_project(project, candidate) or _contains_symlink(project, lexical):
            out.append(finding("critical", "devcontainer.compose-path", "dockerComposeFile escapes the project or crosses a symlink.", rel))
        elif candidate.is_file():
            references.add(candidate)
    if data.get("initializeCommand") is not None:
        out.append(finding("critical", "devcontainer.host-command", "initializeCommand executes on the host and is blocked.", rel))
    if data.get("privileged") is True:
        out.append(finding(_severity(profile, "privileged"), "devcontainer.privileged", "Privileged Dev Container mode is blocked without an explicit reviewed exception.", rel))
    if data.get("capAdd"):
        out.append(finding("critical", "devcontainer.capabilities", "Dev Container capabilities are blocked in the supported subset.", rel))
    if data.get("securityOpt"):
        out.append(finding("critical", "devcontainer.security-options", "Dev Container security options are blocked in the supported subset.", rel))
    run_args = data.get("runArgs")
    if run_args:
        if not isinstance(run_args, list) or any(not isinstance(item, str) for item in run_args):
            out.append(finding("critical", "devcontainer.run-args", "runArgs must be a list of strings and is blocked by default.", rel))
        else:
            dangerous = {"--privileged", "--network", "--pid", "--ipc", "--uts", "--userns", "--volume", "-v", "--mount", "--device", "--cap-add", "--security-opt", "--env-file"}
            for arg in run_args:
                if arg.split("=", 1)[0] in dangerous:
                    out.append(finding("critical", "devcontainer.run-args-dangerous", f"Dangerous Dev Container runtime argument is blocked: {arg!r}.", rel))
            out.append(finding("critical", "devcontainer.run-args", "runArgs are rejected by default until each runtime option has a reviewed allowlist entry.", rel))
    if data.get("workspaceMount"):
        out.append(finding("critical", "devcontainer.workspace-mount", "workspaceMount is blocked until its host-path contract is authorized.", rel))
    if data.get("mounts"):
        out.append(finding("critical", "devcontainer.mount", "Dev Container mounts are blocked until their complete host-path and socket semantics are authorized.", rel))
    features = data.get("features")
    if features:
        out.append(finding("critical", "devcontainer.features-unsupported", "Dev Container Features are blocked until immutable resolution and derived runtime metadata are validated.", rel))
        if isinstance(features, dict):
            for feature in features:
                if str(feature).startswith((".", "/", "~")):
                    lexical = path.parent / str(feature)
                    if not _inside_project(project, lexical) or _contains_symlink(project, lexical):
                        out.append(finding("critical", "devcontainer.feature-path", "Local Feature path escapes the project or crosses a symlink.", rel))


def _port_state(port: Any) -> tuple[str, str]:
    if isinstance(port, dict):
        host = str(port.get("host_ip", ""))
        text = json.dumps(port, sort_keys=True)
    else:
        text = str(port)
        parts = text.rsplit(":", 2)
        host = parts[0] if len(parts) >= 3 else ""
    if host in {"127.0.0.1", "::1", "[::1]"}:
        return "loopback", text
    if host.startswith("100."):
        try:
            n = int(host.split(".")[1])
            return ("tailnet" if 64 <= n <= 127 else "public"), text
        except Exception:
            pass
    return "public", text


def _scan(project: Path, profile: str) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    references: set[Path] = set()
    found = False
    for relative in COMPOSE_FILES:
        path = project / relative
        if not path.exists():
            continue
        found = True
        if path.is_symlink():
            out.append(finding("critical", "project.symlink-config", "Container configuration may not be a symbolic link.", relative))
            continue
        document = _preflight_compose(project, path, out, references, set(), {"bytes": 0}, 0)
        if document:
            services = document.get("services") or {}
            if isinstance(services, dict):
                for name, service in services.items():
                    if isinstance(service, dict):
                        _scan_compose_service(project, path, str(name), service, profile, out)
    dc = project / ".devcontainer/devcontainer.json"
    if dc.exists():
        found = True
        _scan_devcontainer(project, profile, out, references)
    if not found:
        out.append(finding("warning", "project.no-container-config", "No supported Compose or Dev Container configuration found."))
    for pth in project.rglob("*"):
        if pth.is_symlink():
            try:
                pth.resolve().relative_to(project.resolve())
            except ValueError:
                out.append(finding("critical", "project.symlink-escape", "Symbolic link resolves outside the project.", str(pth.relative_to(project))))
    return sorted(out, key=lambda x: {"critical": 0, "error": 1, "warning": 2, "info": 3}.get(x["severity"], 9))


def _fingerprint(project: Path, profile: str) -> str:
    h = hashlib.sha256()
    for value in (ANALYZER_POLICY_VERSION, COMPOSE_SUPPORTED_SCHEMA, DEVCONTAINER_SUPPORTED_SCHEMA, profile):
        h.update(value.encode("utf-8"))
        h.update(b"\0")
    try:
        files = sorted(project.rglob("*"), key=lambda item: str(item.relative_to(project)))
    except OSError:
        files = []
    for path in files:
        try:
            relative = path.relative_to(project)
            if relative.as_posix() == ".devfleet/runtime/analyzer-cache.json" or not path.is_file():
                continue
            h.update(str(relative).encode("utf-8"))
            h.update(b"\0")
            if path.is_symlink():
                h.update(b"symlink:")
                h.update(str(path.resolve(strict=False)).encode("utf-8"))
            else:
                h.update(b"file:")
                h.update(hashlib.sha256(path.read_bytes()).digest())
            h.update(b"\0")
        except (OSError, ValueError):
            h.update(f"unreadable:{path}".encode("utf-8"))
    return h.hexdigest()


def analyze_project(project: Path, profile: str | None = None, force: bool = False) -> list[dict[str, str]]:
    profile = (profile or SETTINGS.development_profile).lower()
    fp = _fingerprint(project, profile)
    cache = project / ".devfleet/runtime/analyzer-cache.json"
    if SETTINGS.enable_analyzer_cache and not force:
        try:
            data = json.loads(cache.read_text(encoding="utf-8"))
            if data.get("fingerprint") == fp and data.get("policyVersion") == ANALYZER_POLICY_VERSION:
                return data.get("findings", [])
        except Exception:
            pass
    findings = _scan(project, profile)
    if SETTINGS.enable_analyzer_cache:
        atomic_json(cache, {"fingerprint": fp, "policyVersion": ANALYZER_POLICY_VERSION, "findings": findings})
    return findings


def has_blockers(findings: list[dict[str, str]]) -> bool:
    return any(x["severity"] in {"critical", "error"} for x in findings)

```


## FILE: source/app/devfleet/auth.py

SHA256: 9810905e7e2ab9d1f1a426ffb9644e2c388de5d199aedf9848f953918ff7cb3d | Bytes: 13026 | Git mode: 100644

```
from __future__ import annotations
import hashlib, hmac, json, secrets, time, threading, math, os, tempfile
from contextlib import contextmanager
from pathlib import Path
from fastapi import Header, HTTPException, Request, status
from .core import SETTINGS, atomic_json

SESSION_COOKIE = "devfleet_session"
LOGIN_CSRF_COOKIE = "devfleet_login_csrf"
SESSION_TTL = 12 * 60 * 60
REMEMBERED_TTL = 7 * 24 * 60 * 60
SESSION_SAMESITE = "strict"
SESSION_SECURE_COOKIE = True
_SESSION_LOCK = threading.RLock()
_LOGIN_LOCK = threading.RLock()
_LOGIN_FAILURES = {}
_SOURCE_FAILURES = {}
_CREDENTIAL_FAILURES = {}
_GLOBAL_FAILURES = []
_BACKOFF_BASE = 0.25
_BACKOFF_MAX = 8.0
_SOURCE_WINDOW = 15 * 60
_GLOBAL_WINDOW = 60.0
_GLOBAL_LIMIT = 40


def _session_path() -> Path:
    return SETTINGS.runtime_root / "sessions.json"


@contextmanager
def _session_file_lock():
    """Serialize the complete sessions read/modify/write transaction across workers."""
    path = _session_path().with_name("sessions.json.lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = open(path, "a+b")
    try:
        if os.name != "nt":
            os.chmod(path, 0o600)
    except OSError:
        pass
    try:
        if os.name != "nt":
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        else:
            import msvcrt

            handle.seek(0, os.SEEK_END)
            if handle.tell() == 0:
                handle.write(b"0")
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
        yield
    finally:
        try:
            if os.name != "nt":
                import fcntl

                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
            else:
                import msvcrt

                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        finally:
            handle.close()
    try:
        if os.name != "nt":
            path.chmod(0o600)
    except OSError:
        pass


def _load_sessions() -> dict[str, dict]:
    try:
        value = json.loads(_session_path().read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _save_sessions(value: dict[str, dict]) -> None:
    path = _session_path()
    parent = path.parent
    parent.mkdir(parents=True, exist_ok=True)
    if os.name != "nt":
        try:
            parent.chmod(0o700)
        except OSError:
            pass
    payload = json.dumps(value, indent=2, sort_keys=True, default=str) + "\n"
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(parent)
    )
    try:
        if hasattr(os, "fchmod"):
            os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            fd = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        replace_error = None
        for attempt in range(6):
            try:
                os.replace(temp_name, path)
                replace_error = None
                break
            except PermissionError as exc:
                replace_error = exc
                if os.name != "nt" or attempt == 5:
                    raise
                time.sleep(0.02 * (attempt + 1))
        if replace_error is not None:
            raise replace_error
    finally:
        if fd != -1:
            os.close(fd)
        try:
            Path(temp_name).unlink(missing_ok=True)
        except OSError:
            pass
    if os.name != "nt":
        try:
            path.chmod(0o600)
        except OSError:
            pass


def _credential_generation() -> str:
    return hashlib.sha256(
        (str(SETTINGS.admin_user) + "\0" + str(SETTINGS.admin_password)).encode()
    ).hexdigest()


def _prune_sessions(
    sessions: dict[str, dict], now: int | None = None
) -> dict[str, dict]:
    now = int(time.time() if now is None else now)
    return {
        k: v
        for k, v in sessions.items()
        if isinstance(v, dict) and int(v.get("expires_at", 0)) > now
    }


def login_csrf_token() -> str:
    return secrets.token_urlsafe(32)


def session_cookie_options(request: Request | None = None) -> dict:
    """Cookie settings for callers that emit the session cookie.

    v1.2.1's route signatures remain unchanged; this centralizes the strict,
    secure-compatible policy for future/compatible emitters.
    """
    return {
        "httponly": True,
        "samesite": SESSION_SAMESITE,
        "secure": bool(request and request.url.scheme == "https"),
        "path": "/",
    }


def safe_next(value: str | None) -> str:
    value = str(value or "/").strip()
    if (
        not value.startswith("/")
        or value.startswith("//")
        or "\\" in value
        or "://" in value
    ):
        return "/"
    return value


def _backoff_key(user: str, source: str | None = None) -> str:
    return f'{source or "unknown"}:{user}'


def _source_key(source: str | None) -> str:
    return str(source or "unknown").strip().lower()[:200]


def _credential_key(user: str) -> str:
    return hashlib.sha256(str(user or "").strip().lower().encode()).hexdigest()


def _backoff_seconds(entries: dict[str, dict], key: str, now: float) -> float:
    entry = entries.get(key)
    return max(0.0, float(entry["until"]) - now) if entry else 0.0


def login_backoff_seconds(
    user: str, source: str | None = None, now: float | None = None
) -> float:
    now = time.monotonic() if now is None else now
    key = _backoff_key(user, source)
    with _LOGIN_LOCK:
        entry = _LOGIN_FAILURES.get(key)
        return max(0.0, float(entry["until"]) - now) if entry else 0.0


def _record_login_failure(
    user: str, source: str | None = None, now: float | None = None
) -> None:
    now = time.monotonic() if now is None else now
    key = _backoff_key(user, source)
    with _LOGIN_LOCK:
        cutoff = now - _SOURCE_WINDOW
        _LOGIN_FAILURES.update(
            {k: v for k, v in _LOGIN_FAILURES.items() if v["last"] >= cutoff}
        )
        entry = _LOGIN_FAILURES.get(key, {"count": 0, "last": now, "until": now})
        count = min(int(entry["count"]) + 1, 8)
        entry = {
            "count": count,
            "last": now,
            "until": now + min(_BACKOFF_MAX, _BACKOFF_BASE * (2 ** (count - 1))),
        }
        _LOGIN_FAILURES[key] = entry
        for entries, entry_key in (
            (_SOURCE_FAILURES, _source_key(source)),
            (_CREDENTIAL_FAILURES, _credential_key(user)),
        ):
            old = entries.get(entry_key, {"count": 0, "last": now, "until": now})
            n = min(int(old["count"]) + 1, 8)
            entries[entry_key] = {
                "count": n,
                "last": now,
                "until": now + min(_BACKOFF_MAX, _BACKOFF_BASE * (2 ** (n - 1))),
            }
        _GLOBAL_FAILURES[:] = [t for t in _GLOBAL_FAILURES if t >= now - _GLOBAL_WINDOW]
        if len(_GLOBAL_FAILURES) < _GLOBAL_LIMIT:
            _GLOBAL_FAILURES.append(now)


def login_retry_after(
    user: str, source: str | None = None, now: float | None = None
) -> int:
    now = time.monotonic() if now is None else now
    with _LOGIN_LOCK:
        source_delay = _backoff_seconds(_SOURCE_FAILURES, _source_key(source), now)
        credential_delay = _backoff_seconds(
            _CREDENTIAL_FAILURES, _credential_key(user), now
        )
        global_delay = 0.0
        if len(_GLOBAL_FAILURES) >= _GLOBAL_LIMIT:
            global_delay = max(0.0, (_GLOBAL_FAILURES[0] + _GLOBAL_WINDOW) - now)
    return max(0, math.ceil(max(source_delay, credential_delay, global_delay)))


def valid_credentials(user: str, password: str, source: str | None = None) -> bool:
    user = str(user or "")
    password = str(password or "")
    # Keep both comparisons on every credential attempt.  Input-shape
    # rejection is applied only after the comparisons so an invalid username
    # cannot skip the password comparison.
    user_ok = hmac.compare_digest(user, SETTINGS.admin_user)
    password_ok = hmac.compare_digest(password, SETTINGS.admin_password)
    valid = bool(user.strip() and password and (user_ok & password_ok))
    if not user.strip() or not password:
        _record_login_failure(user, source)
        return False
    if not valid:
        if login_retry_after(user, source):
            return False
        _record_login_failure(user, source)
    else:
        # A correct credential must not be permanently locked out by earlier
        # failures for the same account; throttle invalid attempts while allowing
        # the owner to recover without waiting for the backoff window.
        with _LOGIN_LOCK:
            _LOGIN_FAILURES.pop(_backoff_key(user, source), None)
            _CREDENTIAL_FAILURES.pop(_credential_key(user), None)
            _SOURCE_FAILURES.pop(_source_key(source), None)
    return valid


def issue_session(user: str, remember: bool = False) -> tuple[str, int, str]:
    now = int(time.time())
    ttl = REMEMBERED_TTL if remember else SESSION_TTL
    session_id = secrets.token_urlsafe(32)
    csrf = secrets.token_urlsafe(32)
    with _SESSION_LOCK, _session_file_lock():
        sessions = _prune_sessions(_load_sessions())
        sessions[session_id] = {
            "user": user,
            "issued_at": now,
            "expires_at": now + ttl,
            "csrf": csrf,
            "credential_generation": _credential_generation(),
        }
        _save_sessions(sessions)
    return session_id, ttl, csrf


def _session_file_generation() -> tuple[int, int]:
    try:
        stat = _session_path().stat()
        return (int(stat.st_mtime_ns), int(stat.st_size))
    except OSError:
        return (0, 0)


def _request_session_record(request: Request) -> dict | None:
    token = request.cookies.get(SESSION_COOKIE)
    signature = (token, _credential_generation(), _session_file_generation())
    state = getattr(request, "state", None)
    cached = (
        getattr(state, "devfleet_session_cache", None) if state is not None else None
    )
    if isinstance(cached, dict) and cached.get("signature") == signature:
        return cached.get("record")
    with _SESSION_LOCK, _session_file_lock():
        record = _prune_sessions(_load_sessions()).get(token or "")
    if (
        not isinstance(record, dict)
        or record.get("user") != SETTINGS.admin_user
        or record.get("credential_generation") != signature[1]
        or int(record.get("expires_at", 0)) <= int(time.time())
    ):
        record = None
    if state is not None:
        state.devfleet_session_cache = {"signature": signature, "record": record}
    return record


def validate_session(token: str | None) -> str | None:
    if not token:
        return None
    with _SESSION_LOCK, _session_file_lock():
        record = _prune_sessions(_load_sessions()).get(token)
    if (
        not isinstance(record, dict)
        or record.get("user") != SETTINGS.admin_user
        or record.get("credential_generation") != _credential_generation()
    ):
        return None
    if int(record.get("expires_at", 0)) <= int(time.time()):
        revoke_session(token)
        return None
    return str(record["user"])


def session_user(request: Request) -> str | None:
    record = _request_session_record(request)
    return str(record["user"]) if isinstance(record, dict) else None


def check_session(request: Request) -> None:
    if not session_user(request):
        raise HTTPException(status_code=401, detail="Login required.")


def session_csrf_token(request: Request) -> str:
    record = _request_session_record(request)
    return str(record.get("csrf", "")) if isinstance(record, dict) else ""


def validate_login_csrf(cookie: str | None, form_value: str) -> bool:
    return bool(cookie and form_value) and hmac.compare_digest(cookie, form_value)


def validate_session_csrf(request: Request, form_value: str) -> bool:
    return bool(form_value) and hmac.compare_digest(
        session_csrf_token(request), form_value
    )


def revoke_session(token: str | None) -> None:
    if not token:
        return
    with _SESSION_LOCK, _session_file_lock():
        sessions = _load_sessions()
        sessions.pop(token, None)
        _save_sessions(sessions)


def api_token_valid(token: str | None) -> bool:
    """Validate the API token without short-circuiting the digest comparison."""
    expected = str(SETTINGS.api_token or "")
    supplied = str(token or "")
    configured = bool(expected.strip())
    provided = bool(supplied.strip())
    matches = hmac.compare_digest(supplied, expected)
    return configured and provided and matches


def check_api(x_devfleet_token: str = Header(default="")) -> None:
    if not api_token_valid(x_devfleet_token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API token"
        )

```


## FILE: source/app/devfleet/caches.py

SHA256: 9772d26aae5fa5d81142a9e1e29361886b9effbaa92f3eef8a99724bd985441d | Bytes: 1733 | Git mode: 100644

```
from __future__ import annotations
from pathlib import Path
from typing import Any
import yaml
from .core import SETTINGS
MOUNTS={'python':[('pip','/home/vscode/.cache/pip'),('uv','/home/vscode/.cache/uv')],'javascript':[('npm','/home/node/.npm'),('pnpm','/home/node/.local/share/pnpm/store')],'typescript':[('npm','/home/node/.npm'),('pnpm','/home/node/.local/share/pnpm/store')],'java':[('maven','/home/vscode/.m2/repository'),('gradle','/home/vscode/.gradle/caches')],'kotlin':[('maven','/home/vscode/.m2/repository'),('gradle','/home/vscode/.gradle/caches')],'csharp':[('nuget','/home/vscode/.nuget/packages')],'go':[('go-mod','/go/pkg/mod'),('go-build','/home/vscode/.cache/go-build')],'rust':[('cargo-registry','/usr/local/cargo/registry'),('cargo-git','/usr/local/cargo/git')],'php':[('composer','/home/vscode/.cache/composer')],'ruby':[('bundler','/usr/local/bundle/cache')]}
def cache_override(project:Path,compose_file:Path,meta:dict[str,Any])->Path|None:
 if not SETTINGS.enable_shared_caches or meta.get('profile',SETTINGS.development_profile)=='strict':return None
 mounts=MOUNTS.get(str(meta.get('language','')).lower(),[])
 if not mounts:return None
 data=yaml.safe_load(compose_file.read_text()) or {};services=data.get('services') or {};override={'services':{}}
 for service in services:
  volumes=[]
  for name,target in mounts:
   source=SETTINGS.cache_root/name;source.mkdir(parents=True,exist_ok=True);volumes.append({'type':'bind','source':str(source),'target':target})
  override['services'][service]={'volumes':volumes}
 out=SETTINGS.runtime_root/'compose-overrides'/f'{project.name}.cache.yaml';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(yaml.safe_dump(override,sort_keys=False));return out

```


## FILE: source/app/devfleet/codexpro.py

SHA256: 30b25cb2a5e7479b08aeb3e1b161fe5b53d6eafe21f6b53ea6d2b827df5689a4 | Bytes: 867 | Git mode: 100644

```
from __future__ import annotations
import json,time
from pathlib import Path
from typing import Any
from .core import SETTINGS
def codexpro_status(project:Path)->dict[str,Any]:
 runtime=project/'.ai-bridge/local-agent';status=project/'.devfleet/runtime/codexpro-status.json';log=project/'.devfleet/runtime/codexpro-bootstrap.log';handoff=project/'.ai-bridge/current-plan.md'
 data={'healthy':False,'state':'not-bootstrapped','workspace':str(project),'runtime_log':str(log),'model_endpoint':SETTINGS.ollama_base_url,'handoff_age_seconds':None}
 try:data.update(json.loads(status.read_text()))
 except Exception:pass
 if handoff.exists():data['handoff_age_seconds']=max(0,int(time.time()-handoff.stat().st_mtime))
 data['runtime_directory']=str(runtime);return data
def bootstrap_command(project:Path)->list[str]:return [str(project/'.devfleet/codexpro-bootstrap.sh')]

```


## FILE: source/app/devfleet/configuration.py

SHA256: 3ad7879d81b09b62d176c5483204281caf4d7f81a57d03d6fd77cf9a7f4c1ee1 | Bytes: 4081 | Git mode: 100644

```
from __future__ import annotations
from copy import deepcopy
from typing import Any
SCHEMA_VERSION=2
PROFILE_NAMES={'strict','balanced','fast'}
DOCKER_MODES={'rootless','rootful'}

def _setdefault_path(data:dict[str,Any],path:tuple[str,...],value:Any)->None:
    cur=data
    for key in path[:-1]:cur=cur.setdefault(key,{})
    cur.setdefault(path[-1],value)

def migrate_cluster_config(source:dict[str,Any],*,clean_install:bool=False)->tuple[dict[str,Any],list[str]]:
    data=deepcopy(source); version=int(data.get('SchemaVersion',1)); changes=[]
    if version>2: raise ValueError(f'Configuration schema {version} is newer than this package supports.')
    if version==1:
        profile='balanced' if clean_install else 'strict'
        _setdefault_path(data,('Hosts',),{'DesktopFriendlyName':'DevFleet Primary','LaptopFriendlyName':'DevFleet Surrogate'})
        for key,friendly,alias in [('Primary','CodexDevVM','CodexDevVM'),('Failover','DevFleetFailover','DevFleetFailover'),('Vault','DevFleetVault','DevFleetVault')]:
            node=data.setdefault(key,{}); node.setdefault('FriendlyName',friendly); node.setdefault('SshAlias',alias)
        data.setdefault('Development',{'Profile':profile,'EnableSharedBuildCaches':profile!='strict','EnableAnalyzerCache':True,'EnableTrustedOrchestrator':True,'AllowLoopbackPortPublishing':True,'AllowTailnetPortPublishing':profile!='strict','AutoStartCodexPro':True,'AutoStartProjectServices':True,'RequireConfirmationForRoutineRebuild':False,'RequireConfirmationForRoutineRepair':False,'BackupBeforeRebuild':False,'BackupBeforeQuarantine':True})
        data.setdefault('Docker',{'PrimaryMode':'rootless','FailoverMode':'rootless','EnableBuildKit':True,'EnableSharedBuildCache':profile!='strict','EnableRegistryCache':False,'RootfulModeAcknowledged':False})
        data.setdefault('CodexPro',{'Mode':'project-scoped-adapter','AutoBootstrap':True,'ToolCards':True,'DefaultHost':'127.0.0.1','DefaultPort':8787,'SharedTransportStatus':'adapter-only-until-a-verified-multi-workspace-registration-interface-is-exposed'})
        ollama=data.setdefault('Ollama',{}); ollama.setdefault('PreferredBaseUrl',''); ollama.setdefault('Profile','stable-interactive'); ollama.setdefault('ProfilesFile','config/ollama-profiles.json')
        network=data.setdefault('Network',{}); network.setdefault('TailnetCidr','100.64.0.0/10'); network.setdefault('PublicBindingAllowed',False)
        backup=data.setdefault('Backup',{}); backup.setdefault('RequireVerifiedBackupBeforeQuarantine',True); backup.setdefault('OfflineExportEnabled',True)
        safety=data.setdefault('Safety',{}); safety.setdefault('BlockWindowsPaths',True); safety.setdefault('BlockUncPaths',True); safety.setdefault('BlockWorkspaceEscape',True); safety.setdefault('OrdinaryContainersMayMountDockerSocket',False)
        data.setdefault('LanguagePolicy',{'DefaultAutomation':'python','DefaultWindowsAdministration':'powershell','DefaultLinuxAdministration':'bash-or-python','DefaultCrossPlatformCli':'go','DefaultWebFrontend':'typescript','DefaultRapidApi':'python-fastapi'})
        data['SchemaVersion']=2
        changes += ['SchemaVersion: 1 -> 2',f'Development.Profile: {profile}','Existing rootless Docker stores preserved; no implicit image/volume migration','Primary friendly name and SSH alias: CodexDevVM; instance remains devfleet-primary']
    data['PackageVersion']=__import__('devfleet.version',fromlist=['__version__']).__version__
    return data,changes

def validate_cluster_config(data:dict[str,Any])->None:
    if int(data.get('SchemaVersion',0))!=2: raise ValueError('SchemaVersion must be 2 after migration.')
    if str(data.get('Development',{}).get('Profile','')).lower() not in PROFILE_NAMES: raise ValueError('Unknown development profile.')
    for key in ('PrimaryMode','FailoverMode'):
        if str(data.get('Docker',{}).get(key,'')).lower() not in DOCKER_MODES: raise ValueError(f'Docker.{key} must be rootless or rootful.')
    if data.get('Safety',{}).get('AllowDockerTcp'): raise ValueError('Unauthenticated Docker TCP remains unsupported.')

```


## FILE: source/app/devfleet/containers.py

SHA256: 56dc9aa80609796d45523c4d701e05afde736cccbc9a925fab4f8d50304dc600 | Bytes: 11180 | Git mode: 100644

```
from __future__ import annotations

import json
import re
from typing import Any

from .core import SETTINGS, run, safe_child, validate_project_id, validate_slug
from .metadata_io import read_project_metadata


_CONTAINER_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
_ACTIONS = {
    "start": "start",
    "stop": "stop",
    "restart": "restart",
    "pause": "pause",
    "unpause": "unpause",
    "rem