#!/usr/bin/env python3
"""Bounded, installed-daemon daily-use acceptance; never imports product code.

prepare -> parent restarts only devfleet.service -> resume

Credentials come only from DEVFLEET_ADMIN_USER/PASSWORD in the process environment.
The private state is a recovery journal, not release authority. Only a complete,
bound PASS report plus native parent validation can earn acceptance credit.
"""
from __future__ import annotations

import argparse
import base64
import contextlib
import hashlib
import http.cookiejar
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
from typing import Any, Callable
import urllib.error
import urllib.parse
import urllib.request


CONTRACT = "devfleet-real-use-acceptance-v1"
RUN_ID = re.compile(r"(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*")
IDENTIFIER = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
SLUG = re.compile(r"[a-z0-9][a-z0-9._-]{1,62}")
SHA256 = re.compile(r"[0-9a-f]{64}")
PROJECT_ID = re.compile(r"[0-9a-fA-F-]{16,128}")
CANDIDATE_FIELDS = (
    "repositoryHead", "candidateCommit", "shippingInputIdentity",
    "releaseFingerprintId", "toolingFingerprintId", "exeSha256", "tarSha256",
)
EXECUTION_FIELDS = (
    "role", "vmName", "vmId", "computeInstanceName", "vaultInstanceName",
    "deploymentId", "nodeId", "nodeName", "transactionId", "invocationId",
    "surrogateEvidenceSha256",
)
ASSERTIONS = {
    "U01": ("authenticatedDashboard", "templateCreated", "identityBound", "assetsPresent", "credentialsNotLogged"),
    "U02": ("startCompleted", "healthCompleted", "testCompleted", "smokeOutputObserved", "uiBackendContainerAgree"),
    "U03": ("stopCompleted", "restartCompleted", "serviceRestartObserved", "sameProjectAndData",
            "noDuplicateWriter", "noPendingOperations", "healthRecovered"),
    "U04": ("immediateBackupVerified", "vaultUploadVerified", "backupBeforeQuarantine",
            "quarantineReversible", "foreignCollisionRejected", "collisionPreserved",
            "restoreCompleted", "contentRecovered"),
    "U05": ("vaultCopyCompleted", "copyIdentityBound", "copyContentRecovered", "originalUnchanged",
            "copyStartRejected", "securityStartRejected", "foreignLeaseStartRejected",
            "originalUsable", "onlyIntendedOwnerStarts"),
}
# Includes product command maxima plus bounded queue/observation margins. The
# parent owns the larger phase deadline and must also budget cleanup separately.
OPERATION_SECONDS = {
    "create": 600, "start": 2100, "stop": 720, "restart": 2100,
    "health": 420, "test": 1920, "backup": 2400, "quarantine": 3300,
    "restore-quarantine": 300, "restore-vault": 3900, "analyze-force": 300,
}
MAX_DOCUMENT = 2 * 1024 * 1024
OWNER_FILE = ".df-real-use-owner.json"
SENTINEL_FILE = "df-real-use-sentinel.txt"
SMOKE_TEXT = "Template smoke test passed"
TERMINAL_STATES = frozenset({"completed", "failed", "interrupted", "cancelled", "canceled"})
LABELS = {
    "managed_by": "io.devfleet.managed-by",
    "project_id": "io.devfleet.project-id",
    "slug": "io.devfleet.project-slug",
    "runtime_id": "io.devfleet.runtime-id",
    "deployment_id": "io.devfleet.deployment-id",
    "host_id": "io.devfleet.host-id",
}


class AcceptanceError(Exception):
    """Only fixed, nonsecret error codes may cross the evidence boundary."""

    def __init__(self, code: str, receipt: dict[str, Any] | None = None):
        self.code = code if re.fullmatch(r"[A-Z][A-Z0-9_]{1,95}", code) else "UNCLASSIFIED_FAILURE"
        self.receipt = receipt
        super().__init__(self.code)


def require(condition: Any, code: str) -> None:
    if not condition:
        raise AcceptanceError(code)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def instant(value: Any) -> float:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        require(parsed.tzinfo is not None, "DEADLINE_TIMEZONE_REQUIRED")
        return parsed.timestamp()
    except (TypeError, ValueError, OverflowError):
        raise AcceptanceError("INVALID_TIMESTAMP") from None


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    require(path.is_file() and not path.is_symlink(), "JSON_FILE_UNSAFE_OR_ABSENT")
    require(path.stat().st_size <= MAX_DOCUMENT, "JSON_FILE_TOO_LARGE")
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError):
        raise AcceptanceError("INVALID_JSON_DOCUMENT") from None
    require(isinstance(value, dict), "JSON_OBJECT_REQUIRED")
    return value


def write_json(path: Path, value: Any) -> None:
    """Atomic private output; caller must provision its exact parent directory."""
    require(path.parent.is_dir() and not path.parent.is_symlink(), "OUTPUT_PARENT_UNSAFE")
    require(not path.is_symlink(), "OUTPUT_SYMLINK_REJECTED")
    temporary = path.with_name(path.name + ".tmp-" + secrets.token_hex(6))
    try:
        fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(canonical(value) + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        if os.name != "nt":
            path.chmod(0o600)
    finally:
        if temporary.exists():
            temporary.unlink()


def redact(value: Any, secret_values: list[str]) -> Any:
    """Defense in depth after allowlisting, including strings in exception tests."""
    if isinstance(value, dict):
        return {str(key): redact(item, secret_values) for key, item in value.items()}
    if isinstance(value, list):
        return [redact(item, secret_values) for item in value]
    if isinstance(value, str):
        for secret in sorted(set(secret_values), key=len, reverse=True):
            if secret and (len(secret) >= 4 or value == secret):
                value = value.replace(secret, "[REDACTED]")
        return value
    return value


def safe_child(root: Path, name: str, *, exists: bool = False) -> Path:
    require(bool(SLUG.fullmatch(name)), "UNSAFE_CHILD_NAME")
    require(root.is_absolute() and root.is_dir(), "UNSAFE_ROOT")
    for part in (root, *root.parents):
        require(not part.is_symlink(), "ROOT_SYMLINK_REJECTED")
    path = root / name
    require(not path.is_symlink() and path.resolve().parent == root.resolve(), "CHILD_BOUNDARY_VIOLATION")
    if exists:
        require(path.is_dir(), "OWNED_DIRECTORY_ABSENT")
    return path


def exact_returned_child(root: Path, value: Any, code: str) -> Path:
    require(isinstance(value, str) and "\x00" not in value, code)
    path = Path(value)
    require(path.is_absolute() and path.parent == root and path.name not in {"", ".", ".."}, code)
    require(str(path) == value and not path.is_symlink() and path.is_dir(), code)
    require(path.resolve().parent == root.resolve(), code)
    return path


def normalized_request(value: dict[str, Any], self_hash: str) -> dict[str, Any]:
    require(value.get("schemaVersion") == 1, "REQUEST_SCHEMA")
    run_id = value.get("runId", "")
    require(isinstance(run_id, str) and len(run_id) <= 128 and RUN_ID.fullmatch(run_id), "RUN_ID_INVALID")
    candidate, execution, paths = value.get("candidate"), value.get("execution"), value.get("paths")
    require(isinstance(candidate, dict) and isinstance(execution, dict) and isinstance(paths, dict), "REQUEST_BINDING_MISSING")
    for key in CANDIDATE_FIELDS:
        pattern = re.compile(r"[0-9a-f]{40,64}") if key in {"repositoryHead", "candidateCommit"} else SHA256
        require(isinstance(candidate.get(key), str) and pattern.fullmatch(candidate[key]), "CANDIDATE_BINDING_INVALID")
    require(value.get("runnerSha256") == self_hash, "RUNNER_HASH_MISMATCH")
    require(execution.get("role") == "Laptop / Surrogate", "ROLE_MISMATCH")
    for key in EXECUTION_FIELDS:
        require(isinstance(execution.get(key), str) and execution[key], "EXECUTION_BINDING_MISSING")
    for key in ("vmName", "vmId", "computeInstanceName", "vaultInstanceName", "deploymentId",
                "nodeId", "nodeName", "transactionId", "invocationId"):
        require(IDENTIFIER.fullmatch(execution[key]), "EXECUTION_IDENTIFIER_INVALID")
    require(execution["vmName"].lower().startswith("devfleet-e2e-"), "L1_SCOPE_INVALID")
    require(execution["computeInstanceName"] != execution["vaultInstanceName"], "PRODUCT_TARGETS_NOT_UNIQUE")
    require(SHA256.fullmatch(execution["surrogateEvidenceSha256"]), "SURROGATE_EVIDENCE_HASH_INVALID")
    for key in ("workspaces", "quarantine", "runtimeRoot"):
        require(isinstance(paths.get(key), str) and Path(paths[key]).is_absolute(), "INSTALLED_PATH_INVALID")
    require(len({paths[key] for key in ("workspaces", "quarantine", "runtimeRoot")}) == 3, "INSTALLED_PATHS_OVERLAP")
    url = urllib.parse.urlsplit(str(value.get("baseUrl", "")))
    require(url.scheme == "http" and url.hostname == "127.0.0.1" and url.port
            and not url.username and not url.password and url.path in {"", "/"}
            and not url.query and not url.fragment, "DASHBOARD_ORIGIN_INVALID")
    deadline = instant(value.get("deadlineUtc"))
    require(0 < deadline - time.time() <= 24 * 3600, "OWNER_DEADLINE_INVALID")
    return {
        "schemaVersion": 1, "runId": run_id, "runnerSha256": self_hash,
        "candidate": {key: candidate[key] for key in CANDIDATE_FIELDS},
        "execution": {key: execution[key] for key in EXECUTION_FIELDS},
        "paths": {key: paths[key] for key in ("workspaces", "quarantine", "runtimeRoot")},
        "baseUrl": f"http://127.0.0.1:{url.port}", "deadlineUtc": value["deadlineUtc"],
    }


def binding_hash(request: dict[str, Any]) -> str:
    # A resumed stage may have less time remaining, never a different identity.
    return hashlib.sha256(canonical({key: value for key, value in request.items() if key != "deadlineUtc"})).hexdigest()


@dataclass
class Response:
    status: int
    headers: dict[str, str]
    body: str


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class HttpTransport:
    def __init__(self, origin: str):
        self.origin = origin
        self.cookies = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(self.cookies), NoRedirect()
        )

    def request(self, method: str, route: str, fields: dict[str, str] | None, timeout: float) -> Response:
        require(route.startswith("/") and not route.startswith("//") and not urllib.parse.urlsplit(route).netloc,
                "CROSS_ORIGIN_REQUEST_REJECTED")
        headers = {"Accept": "text/html,application/json", "Origin": self.origin, "Referer": self.origin + "/"}
        data = None
        if fields is not None:
            data = urllib.parse.urlencode(fields).encode("utf-8")
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        req = urllib.request.Request(self.origin + route, data=data, headers=headers, method=method)
        try:
            try:
                stream = self.opener.open(req, timeout=timeout)
            except urllib.error.HTTPError as exc:
                stream = exc
            with stream:
                body = stream.read(MAX_DOCUMENT + 1)
                require(len(body) <= MAX_DOCUMENT, "HTTP_RESPONSE_TOO_LARGE")
                return Response(stream.code, {key.lower(): val for key, val in stream.headers.items()},
                                body.decode("utf-8", errors="replace"))
        except (urllib.error.URLError, TimeoutError, OSError):
            raise AcceptanceError("HTTP_TRANSPORT_FAILURE") from None

    def secrets(self) -> list[str]:
        return [cookie.value for cookie in self.cookies]


class Page(HTMLParser):
    def __init__(self, text: str):
        super().__init__(convert_charrefs=True)
        self.forms: list[dict[str, Any]] = []
        self.current: dict[str, Any] | None = None
        self.csrf = ""
        self.banners: dict[str, str] = {}
        self.project_states: list[str] = []
        self.text: list[str] = []
        self.feed(text)

    def handle_starttag(self, tag: str, attributes: list[tuple[str, str | None]]) -> None:
        attrs = dict(attributes)
        if tag == "form":
            self.current = {"action": attrs.get("action", ""), "method": attrs.get("method", "get").lower(), "fields": {}}
            self.forms.append(self.current)
        if tag == "input" and attrs.get("name") and self.current is not None:
            if "disabled" not in attrs and (attrs.get("type") not in {"checkbox", "radio"} or "checked" in attrs):
                self.current["fields"][attrs["name"]] = attrs.get("value", "")
        if attrs.get("name") == "csrf_token" and attrs.get("value"):
            self.csrf = str(attrs["value"])
        if attrs.get("id") == "devfleet-csrf":
            self.csrf = str(attrs.get("data-token") or self.csrf)
        if "data-operation-id" in attrs:
            classes = str(attrs.get("class") or "").split()
            self.banners[str(attrs["data-operation-id"])] = (
                "failed" if "failed" in classes else "completed" if "complete" in classes else "pending"
            )
        if "data-project-state" in attrs:
            self.project_states.append(str(attrs["data-project-state"]))

    def handle_endtag(self, tag: str) -> None:
        if tag == "form":
            self.current = None

    def handle_data(self, text: str) -> None:
        self.text.append(text)

    def form(self, action: str, match_fields: dict[str, str] | None = None) -> dict[str, Any]:
        matches = [form for form in self.forms if form["method"] == "post" and form["action"] == action
                   and all(form["fields"].get(key) == val for key, val in (match_fields or {}).items())]
        require(bool(matches), "DASHBOARD_FORM_MISSING")
        # The same action can legitimately appear in both project hero and tab.
        require(all(form["fields"].get("csrf_token") for form in matches), "DASHBOARD_CSRF_MISSING")
        return matches[0]


class Dashboard:
    def __init__(self, transport: Any, deadline: float, *, clock: Callable[[], float] = time.time,
                 sleep: Callable[[float], None] = time.sleep):
        self.transport, self.deadline, self.clock, self.sleep = transport, deadline, clock, sleep
        self.secret_values: list[str] = []

    def request(self, method: str, route: str, fields: dict[str, str] | None = None) -> Response:
        remaining = self.deadline - self.clock()
        require(remaining > 0, "OWNER_DEADLINE_EXPIRED")
        return self.transport.request(method, route, fields, min(30.0, remaining))

    def page(self, route: str) -> Page:
        response = self.request("GET", route)
        require(response.status == 200, "DASHBOARD_PAGE_NOT_AUTHENTICATED")
        page = Page(response.body)
        if page.csrf:
            self.secret_values.append(page.csrf)
        return page

    def login(self, username: str, password: str) -> None:
        require(username and password, "DASHBOARD_CREDENTIALS_MISSING")
        self.secret_values.extend((username, password))
        form = self.page("/login").form("/login")
        fields = dict(form["fields"])
        fields.update(username=username, password=password, next="/")
        response = self.request("POST", "/login", fields)
        require(response.status == 303 and response.headers.get("location") == "/", "DASHBOARD_LOGIN_FAILED")
        page = self.page("/")
        page.form("/logout")
        require(page.csrf, "AUTHENTICATED_CSRF_MISSING")

    def json(self, route: str) -> dict[str, Any]:
        response = self.request("GET", route)
        require(response.status == 200, "DASHBOARD_JSON_NOT_AVAILABLE")
        try:
            value = json.loads(response.body)
        except json.JSONDecodeError:
            raise AcceptanceError("DASHBOARD_JSON_INVALID") from None
        require(isinstance(value, dict), "DASHBOARD_JSON_INVALID")
        return value

    def submit(self, page_route: str, action: str, fields: dict[str, str] | None = None, *,
               match_fields: dict[str, str] | None = None, negative_fixture: bool = False) -> tuple[str, int]:
        page = self.page(page_route)
        if negative_fixture:
            require(page.csrf and action.startswith("/projects/"), "NEGATIVE_FIXTURE_FORM_INVALID")
            payload = {"csrf_token": page.csrf}
        else:
            payload = dict(page.form(action, match_fields)["fields"])
        payload.update(fields or {})
        require(payload.get("csrf_token"), "DASHBOARD_CSRF_MISSING")
        response = self.request("POST", action, payload)
        if response.status == 303:
            location = response.headers.get("location", "")
            parsed = urllib.parse.urlsplit(location)
            require(not parsed.scheme and not parsed.netloc and parsed.path == "/", "OPERATION_REDIRECT_INVALID")
            ids = urllib.parse.parse_qs(parsed.query).get("operation", [])
            require(len(ids) == 1, "OPERATION_ID_MISSING")
            op_id = ids[0]
        elif response.status == 202:
            try:
                op_id = json.loads(response.body).get("operation_id", "")
            except (AttributeError, json.JSONDecodeError):
                raise AcceptanceError("OPERATION_ID_MISSING") from None
        else:
            raise AcceptanceError("DASHBOARD_MUTATION_NOT_ACCEPTED")
        require(isinstance(op_id, str) and IDENTIFIER.fullmatch(op_id), "OPERATION_ID_INVALID")
        return op_id, response.status

    def wait_operation(self, op_id: str, kind: str, project: str, expected: str, timeout: float) -> tuple[dict[str, Any], dict[str, Any]]:
        boundary = min(self.deadline, self.clock() + timeout)
        while self.clock() < boundary:
            operation = self.json("/ui/operations/" + op_id)
            require(operation.get("id", operation.get("operation_id")) == op_id
                    and operation.get("kind") == kind and operation.get("project") == project,
                    "OPERATION_IDENTITY_MISMATCH")
            state = operation.get("state")
            require(state in TERMINAL_STATES | {"queued", "running"}, "OPERATION_STATE_INVALID")
            if state in TERMINAL_STATES:
                rendered = self.page("/?operation=" + op_id).banners.get(op_id)
                receipt = {
                    "id": op_id, "kind": kind, "project": project, "state": state,
                    "expectedState": expected, "renderedState": rendered,
                    "smokeOutputObserved": SMOKE_TEXT in str(operation.get("result", "")),
                }
                if rendered != state:
                    raise AcceptanceError("RENDERED_OPERATION_DISAGREES", receipt)
                if state != expected:
                    raise AcceptanceError("OPERATION_UNEXPECTED_TERMINAL", receipt)
                return operation, receipt
            self.sleep(min(1.0, max(0.0, boundary - self.clock())))
        raise AcceptanceError("OPERATION_DEADLINE_EXPIRED")


class NativeProbe:
    """Only read-only OS/product observations; no product function imports."""

    def __init__(self):
        import pwd
        self.control_uid = pwd.getpwnam("devfleet-control").pw_uid
        self.runner_uid = pwd.getpwnam("devrunner").pw_uid
        self.docker_host = f"unix:///run/user/{self.runner_uid}/docker.sock"

    def command(self, arguments: list[str], timeout: float = 30) -> str:
        try:
            result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout,
                                    check=False, env={"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                                                      "LANG": "C.UTF-8", "DOCKER_HOST": self.docker_host})
        except (OSError, subprocess.TimeoutExpired):
            raise AcceptanceError("NATIVE_OBSERVATION_FAILED") from None
        require(result.returncode == 0, "NATIVE_OBSERVATION_FAILED")
        require(len(result.stdout) <= MAX_DOCUMENT, "NATIVE_OBSERVATION_TOO_LARGE")
        return result.stdout

    def service(self) -> dict[str, Any]:
        text = self.command(["/usr/bin/systemctl", "show", "devfleet.service", "--property=InvocationID",
                             "--property=MainPID", "--property=ActiveState", "--property=User"])
        values = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
        require(values.get("ActiveState") == "active" and values.get("User") == "devfleet-control",
                "INSTALLED_DAEMON_NOT_ACTIVE")
        require(re.fullmatch(r"[0-9a-f]{32}", values.get("InvocationID", "")), "SERVICE_INVOCATION_INVALID")
        require(values.get("MainPID", "").isdigit() and int(values["MainPID"]) > 0, "SERVICE_PID_INVALID")
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        require(re.fullmatch(r"[0-9a-f-]{36}", boot), "BOOT_ID_INVALID")
        return {"invocationId": values["InvocationID"], "pid": int(values["MainPID"]),
                "active": True, "user": "devfleet-control", "bootId": boot}

    def preflight(self, request: dict[str, Any]) -> dict[str, Any]:
        require(os.geteuid() == self.control_uid, "DRIVER_REQUIRES_CONTROL_UID")
        config = read_json(Path("/etc/devfleet/config.json"))
        identity = read_json(Path("/etc/devfleet/node-identity.json"))
        expected = request["execution"]
        require(config.get("node_role") == identity.get("node_role") == "surrogate", "INSTALLED_ROLE_MISMATCH")
        for key, field in (("deployment_id", "deploymentId"), ("node_id", "nodeId"), ("node_name", "nodeName")):
            require(identity.get(key) == expected[field], "INSTALLED_NODE_IDENTITY_MISMATCH")
        require(config.get("deployment_id") == expected["deploymentId"] and config.get("node_name") == expected["nodeName"],
                "INSTALLED_CONFIG_IDENTITY_MISMATCH")
        for key, field in (("workspaces", "workspaces"), ("quarantine", "quarantine"), ("runtime_root", "runtimeRoot")):
            require(config.get(key) == request["paths"][field], "INSTALLED_PATH_MISMATCH")
            root = Path(config[key])
            require(root.is_dir() and not root.is_symlink(), "INSTALLED_PATH_UNAVAILABLE")
        require(request["baseUrl"] == f"http://127.0.0.1:{int(config.get('portal_port', 0))}", "INSTALLED_PORT_MISMATCH")
        require(config.get("backup_before_quarantine") is True, "QUARANTINE_BACKUP_POLICY_REQUIRED")
        require(config.get("docker_mode") == "rootless", "ROOTLESS_RUNTIME_REQUIRED")
        broker = Path("/run/devfleet-vault-broker.sock")
        require(broker.exists() and stat.S_ISSOCK(broker.stat().st_mode) and os.access(broker, os.R_OK | os.W_OK),
                "VAULT_BROKER_UNAVAILABLE")
        require(os.access("/usr/local/bin/devfleet-vault-request", os.X_OK), "VAULT_REQUEST_CLIENT_UNAVAILABLE")
        require(self.command(["/usr/bin/systemctl", "is-active", "devfleet-vault-broker.socket"]).strip() == "active",
                "VAULT_BROKER_UNIT_INACTIVE")
        backup = read_json(Path("/var/lib/devfleet/backup-status/config.json"))
        # Never emit repository, usernames, passwords, tokens or environment text.
        require(re.fullmatch(r"rest:http://100\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/[^\s?#]+",
                             str(backup.get("repository", ""))), "VAULT_TAILSCALE_TRANSPORT_NOT_CONFIGURED")
        self.command(["/usr/bin/docker", "--host", self.docker_host, "version", "--format", "{{.Server.Version}}"])
        return {"installedRole": "surrogate", "installedIdentityVerified": True, "brokerAccessible": True,
                "vaultTransport": "tailscale-rest", "rootlessDocker": True, "service": self.service()}

    def containers(self, project_id: str) -> list[dict[str, Any]]:
        require(PROJECT_ID.fullmatch(project_id), "PROJECT_ID_INVALID")
        ids = self.command(["/usr/bin/docker", "--host", self.docker_host, "ps", "-aq", "--no-trunc",
                            "--filter", "label=io.devfleet.project-id=" + project_id]).split()
        require(all(SHA256.fullmatch(item) for item in ids), "CONTAINER_ID_NOT_CANONICAL")
        if not ids:
            return []
        try:
            values = json.loads(self.command(["/usr/bin/docker", "--host", self.docker_host, "inspect", *ids]))
        except json.JSONDecodeError:
            raise AcceptanceError("CONTAINER_INSPECT_INVALID") from None
        require(isinstance(values, list) and len(values) == len(ids), "CONTAINER_INSPECT_INVALID")
        return values


class FixtureStore:
    def __init__(self, paths: dict[str, str]):
        self.workspaces = Path(paths["workspaces"])
        self.quarantine = Path(paths["quarantine"])
        self.runtime = Path(paths["runtimeRoot"])

    def metadata(self, path: Path) -> dict[str, Any]:
        require(path.is_dir() and not path.is_symlink() and not (path / ".devfleet").is_symlink(),
                "PROJECT_PATH_UNSAFE")
        return read_json(path / ".devfleet" / "project.json")

    def operation_ids(self) -> list[str]:
        root = self.runtime / "operations"
        require(root.is_dir() and not root.is_symlink(), "OPERATION_STORE_UNAVAILABLE")
        values = []
        for path in root.glob("*.json"):
            require(path.is_file() and not path.is_symlink() and IDENTIFIER.fullmatch(path.stem),
                    "OPERATION_STORE_UNSAFE")
            values.append(path.stem)
        return sorted(values)

    def verify_identity(self, path: Path, fixture: dict[str, Any], execution: dict[str, Any], *, copy: bool = False) -> dict[str, Any]:
        meta = self.metadata(path)
        require(int(meta.get("schema_version", 0)) >= 3 and meta.get("managed_by") == "devfleet",
                "PROJECT_OWNERSHIP_INVALID")
        require(meta.get("slug") == fixture["slug"] and meta.get("project_id") == fixture["projectId"]
                and meta.get("deployment_id") == execution["deploymentId"] and meta.get("host_id") == execution["nodeName"]
                and meta.get("runtime_provider") == "docker-compose" and meta.get("runtime_id") == fixture["runtimeId"],
                "PROJECT_IDENTITY_CHANGED")
        require(copy or path.name == fixture["slug"] or path.parent == self.quarantine, "PROJECT_PATH_IDENTITY_MISMATCH")
        return meta

    def verify_owner(self, path: Path, fixture: dict[str, Any]) -> None:
        marker = read_json(path / OWNER_FILE)
        require(marker == fixture["owner"], "FIXTURE_OWNER_MISMATCH")
        sentinel = path / SENTINEL_FILE
        require(sentinel.is_file() and not sentinel.is_symlink() and digest(sentinel) == fixture["sentinelSha256"],
                "FIXTURE_SENTINEL_MISMATCH")

    def verify_copy(self, value: Any, fixture: dict[str, Any], execution: dict[str, Any]) -> Path:
        path = exact_returned_child(self.workspaces, value, "RESTORE_COPY_PATH_INVALID")
        require(SLUG.fullmatch(path.name) and re.fullmatch(re.escape(fixture["slug"]) + r"-recovered-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}", path.name),
                "RESTORE_COPY_NAME_INVALID")
        require(path != self.workspaces / fixture["slug"], "RESTORE_COPY_OVERWROTE_ORIGINAL")
        self.verify_identity(path, fixture, execution, copy=True)
        self.verify_owner(path, fixture)
        return path

    def verify_backup(self, meta: dict[str, Any], fixture: dict[str, Any]) -> dict[str, Any]:
        backup_id = str(meta.get("backup_id", ""))
        require(backup_id.startswith(fixture["slug"] + "-") and IDENTIFIER.fullmatch(backup_id), "BACKUP_ID_INVALID")
        root = self.runtime / "workspace-backups"
        directory = root / backup_id
        require(directory.is_dir() and not root.is_symlink() and not directory.is_symlink()
                and directory.resolve().parent == root.resolve(), "BACKUP_PATH_INVALID")
        archive = directory / (fixture["slug"] + ".tar.gz")
        require(meta.get("backup_path") == str(archive) and archive.is_file() and not archive.is_symlink(),
                "BACKUP_ARCHIVE_PATH_INVALID")
        expected_hash = str(meta.get("backup_sha256", ""))
        require(SHA256.fullmatch(expected_hash) and digest(archive) == expected_hash, "BACKUP_ARCHIVE_HASH_MISMATCH")
        manifest_path = directory / "manifest.json"
        manifest = read_json(manifest_path)
        require(manifest.get("backup_id") == backup_id and manifest.get("project_id") == fixture["projectId"]
                and manifest.get("slug") == fixture["slug"] and manifest.get("verification", {}).get("integrity_verified") is True
                and manifest.get("verification", {}).get("status") == "verified"
                and manifest.get("workspace", {}).get("archive_sha256") == expected_hash, "BACKUP_MANIFEST_MISMATCH")
        return {"kind": "backup", "path": str(directory), "backupId": backup_id,
                "archiveSha256": expected_hash, "manifestSha256": digest(manifest_path)}

    def remove_owned_tree(self, path: Path, fixture: dict[str, Any]) -> None:
        require(path.parent in {self.workspaces, self.quarantine} and path.is_dir() and not path.is_symlink(),
                "CLEANUP_PATH_NOT_OWNED")
        self.verify_owner(path, fixture)
        require(not any(item.is_symlink() for item in path.rglob("*")), "CLEANUP_TREE_SYMLINK_REJECTED")
        shutil.rmtree(path)
        require(not path.exists(), "CLEANUP_DIRECTORY_REMAINS")


class AcceptanceRunner:
    def __init__(self, request: dict[str, Any], state_path: Path, dashboard: Dashboard, probe: Any,
                 *, store: FixtureStore | None = None, state: dict[str, Any] | None = None):
        self.request, self.state_path, self.ui, self.probe = request, state_path, dashboard, probe
        self.store = store or FixtureStore(request["paths"])
        self.state = state or {
            "schemaVersion": 1, "bindingHash": binding_hash(request), "runId": request["runId"],
            "startedAtUtc": utc_now(), "ownerDeadlineUtc": request["deadlineUtc"],
            "prepared": False, "resumed": False, "fixture": {},
            "journeys": [{"id": key, "status": "NOT_RUN", "assertions": {}, "observations": {}} for key in ASSERTIONS],
            "operations": [], "ledger": [], "temporaryEdits": [], "currentJourney": "",
            "cleanup": {"status": "NOT_RUN", "ownedOnly": True, "resources": [], "errors": [],
                        "vaultSnapshots": "RETAINED_APPEND_ONLY_IN_DISPOSABLE_VAULT"},
            "failure": None, "cleanupFailure": None,
        }
        require(self.state.get("schemaVersion") == 1 and self.state.get("bindingHash") == binding_hash(request)
                and self.state.get("runId") == request["runId"], "RESUME_BINDING_MISMATCH")
        require(instant(request["deadlineUtc"]) <= instant(self.state.get("ownerDeadlineUtc")),
                "RESUME_CANNOT_EXTEND_DEADLINE")
        if self.state["fixture"]:
            expected_slug = "df-accept-" + hashlib.sha256(request["runId"].encode()).hexdigest()[:12]
            require(self.fixture.get("slug") == expected_slug
                    and self.fixture.get("originalPath") == str(self.store.workspaces / expected_slug),
                    "RESUME_FIXTURE_SCOPE_MISMATCH")
            if self.fixture.get("owner"):
                require(self.fixture["owner"].get("runId") == request["runId"]
                        and self.fixture["owner"].get("slug") == expected_slug
                        and self.fixture["owner"].get("projectId") == self.fixture.get("projectId"),
                        "RESUME_FIXTURE_OWNER_MISMATCH")

    def save(self) -> None:
        write_json(self.state_path, self.state)

    @property
    def fixture(self) -> dict[str, Any]:
        return self.state["fixture"]

    def begin(self, journey: str) -> dict[str, Any]:
        self.state["currentJourney"] = journey
        row = next(row for row in self.state["journeys"] if row["id"] == journey)
        row["status"] = "IN_PROGRESS"
        self.save()
        return row

    def complete(self, journey: str, observations: dict[str, Any] | None = None) -> None:
        row = next(row for row in self.state["journeys"] if row["id"] == journey)
        row.update(status="PASS", assertions={key: True for key in ASSERTIONS[journey]}, observations=observations or {})
        self.save()

    def operation(self, kind: str, *, page: str | None = None, route: str | None = None,
                  fields: dict[str, str] | None = None, project: str | None = None,
                  match_fields: dict[str, str] | None = None, expected: str = "completed",
                  negative_fixture: bool = False) -> dict[str, Any]:
        slug = project or self.fixture["slug"]
        route = route or f"/projects/{slug}/{kind}"
        page = page or f"/projects/{self.fixture['slug']}"
        op_id, status = self.ui.submit(page, route, fields, match_fields=match_fields, negative_fixture=negative_fixture)
        require(op_id not in {row["id"] for row in self.state["operations"]}, "OPERATION_REUSED_FROM_PRIOR_STEP")
        entry = {"id": op_id, "kind": kind, "project": slug, "route": route, "httpStatus": status,
                 "state": "submitted", "expectedState": expected, "renderedState": "", "smokeOutputObserved": False}
        self.state["operations"].append(entry)
        self.save()
        try:
            result, receipt = self.ui.wait_operation(op_id, kind, slug, expected, OPERATION_SECONDS[kind])
        except AcceptanceError as exc:
            if exc.receipt:
                entry.update(exc.receipt)
                self.save()
            raise
        entry.update(receipt)
        self.save()
        return result

    def original(self) -> Path:
        return safe_child(self.store.workspaces, self.fixture["slug"], exists=True)

    def identity(self) -> dict[str, Any]:
        path = self.original()
        meta = self.store.verify_identity(path, self.fixture, self.request["execution"])
        self.store.verify_owner(path, self.fixture)
        return meta

    def observe_runtime(self, *, running: bool, healthy: bool = False) -> dict[str, Any]:
        meta = self.identity()
        containers = self.probe.containers(self.fixture["projectId"])
        persistent: list[dict[str, Any]] = []
        for item in containers:
            labels = (item.get("Config") or {}).get("Labels") or {}
            require(isinstance(labels, dict), "CONTAINER_LABELS_INVALID")
            for key, label in LABELS.items():
                require(labels.get(label) == str(meta.get(key, "")), "CONTAINER_OWNERSHIP_MISMATCH")
            require(labels.get("com.docker.compose.project") == self.fixture["runtimeId"]
                    and labels.get("com.docker.compose.service"), "COMPOSE_IDENTITY_MISMATCH")
            require(SHA256.fullmatch(str(item.get("Id", ""))), "CONTAINER_ID_NOT_CANONICAL")
            if str(labels.get("com.docker.compose.oneoff", "")).lower() == "true":
                require(not (item.get("State") or {}).get("Running"), "TRANSIENT_WRITER_REMAINS")
                continue
            persistent.append(item)
        active = [item for item in persistent if (item.get("State") or {}).get("Running") is True]
        require(len(active) == (1 if running else 0), "PERSISTENT_WRITER_COUNT_MISMATCH")
        ui_page = self.ui.page(f"/projects/{self.fixture['slug']}")
        require(ui_page.project_states and ui_page.project_states == [("running" if running else "stopped")],
                "UI_RUNTIME_STATE_DISAGREES")
        require(meta.get("lifecycle_status") == ("running" if running else "stopped"), "BACKEND_RUNTIME_STATE_DISAGREES")
        if healthy:
            require(meta.get("health_status") == "healthy", "APPLICATION_NOT_HEALTHY")
        ids = []
        for item in active:
            observed = self.ui.json("/containers/" + item["Id"] + "/inspect")
            require(observed.get("Id") == item["Id"] and (observed.get("State") or {}).get("Running") is True,
                    "UI_CONTAINER_INSPECT_DISAGREES")
            if healthy:
                require((item.get("State") or {}).get("Health", {}).get("Status") == "healthy", "CONTAINER_NOT_HEALTHY")
            ids.append(item["Id"])
        return {"persistentContainerIds": ids, "persistentWriters": len(active), "healthy": healthy}

    def wait_healthy(self) -> dict[str, Any]:
        # Docker healthcheck is independent of the successful user health job.
        deadline = min(self.ui.deadline, self.ui.clock() + 180)
        while True:
            try:
                return self.observe_runtime(running=True, healthy=True)
            except AcceptanceError as exc:
                if exc.code not in {"CONTAINER_NOT_HEALTHY"} or self.ui.clock() >= deadline:
                    raise
                self.ui.sleep(min(1.0, max(0.0, deadline - self.ui.clock())))

    def assert_no_pending(self) -> None:
        for entry in self.state["operations"]:
            operation = self.ui.json("/ui/operations/" + entry["id"])
            require(operation.get("state") == entry["expectedState"], "ACCEPTANCE_OPERATION_PENDING_OR_CHANGED")

    def prepare(self, credentials: tuple[str, str]) -> None:
        require(not self.state["prepared"] and not self.fixture, "PREPARE_ALREADY_ATTEMPTED")
        self.state["preflight"] = self.probe.preflight(self.request)
        self.begin("U01")
        self.ui.login(*credentials)
        slug = "df-accept-" + hashlib.sha256(self.request["runId"].encode()).hexdigest()[:12]
        path = safe_child(self.store.workspaces, slug)
        require(not path.exists(), "FIXTURE_ALREADY_EXISTS")
        self.state["fixture"] = {"slug": slug, "originalPath": str(path), "recoveredPath": ""}
        self.save()
        self.operation("create", page="/?view=projects", route="/projects/create", project=slug,
                       fields={"slug": slug, "display_name": slug, "template": "generic", "target": "local",
                               "runtime_isolation": "container", "resource_profile": "small", "scale": "small",
                               "intent": "prototype", "profile": "balanced", "testing_level": "standard",
                               "git_url": "", "language": "", "framework": "", "pid_mode": "private", "pid_limit": "4096"})
        meta = self.store.metadata(path)
        require(PROJECT_ID.fullmatch(str(meta.get("project_id", ""))), "CREATED_PROJECT_ID_INVALID")
        self.fixture.update(projectId=meta["project_id"], runtimeId=meta.get("runtime_id", ""))
        self.store.verify_identity(path, self.fixture, self.request["execution"])
        require(meta.get("template") == "generic", "CREATED_TEMPLATE_MISMATCH")
        for asset in ("compose.yaml", ".devcontainer/devcontainer.json", ".devfleet/project.json",
                      ".devfleet/smoke-test.sh", ".devfleet/health-check.sh"):
            require((path / asset).is_file() and not (path / asset).is_symlink(), "TEMPLATE_ASSET_MISSING")
        owner = {"schemaVersion": 1, "runId": self.request["runId"], "slug": slug,
                 "projectId": meta["project_id"], "nonce": secrets.token_hex(24)}
        self.fixture["owner"] = owner
        sentinel = f"DevFleet real-use acceptance\nrun:{owner['runId']}\nnonce:{owner['nonce']}\n".encode()
        for name, data in ((OWNER_FILE, canonical(owner)), (SENTINEL_FILE, sentinel)):
            with (path / name).open("xb") as stream:
                stream.write(data)
        self.fixture["sentinelSha256"] = hashlib.sha256(sentinel).hexdigest()
        self.state["ledger"].append({"kind": "project", "path": str(path)})
        self.save()
        self.complete("U01", {"template": "generic", "projectId": meta["project_id"]})
        self.begin("U02")
        self.operation("start")
        self.operation("health")
        test = self.operation("test")
        require(SMOKE_TEXT in str(test.get("result", "")), "TEMPLATE_SMOKE_OUTPUT_MISSING")
        runtime = self.wait_healthy()
        self.complete("U02", runtime)
        self.begin("U03")
        self.operation("stop")
        self.observe_runtime(running=False)
        self.operation("start")
        self.operation("health")
        self.wait_healthy()
        self.assert_no_pending()
        self.state["serviceBeforeRestart"] = self.probe.service()
        self.state["prepared"] = True
        self.save()

    def backup_evidence(self, path: Path) -> dict[str, Any]:
        meta = self.store.verify_identity(path, self.fixture, self.request["execution"])
        require(meta.get("backup_status") == "verified", "PRODUCT_BACKUP_NOT_VERIFIED")
        evidence = self.store.verify_backup(meta, self.fixture)
        if evidence["path"] not in {entry["path"] for entry in self.state["ledger"]}:
            self.state["ledger"].append(evidence)
            self.save()
        return evidence

    def u04(self) -> None:
        self.begin("U04")
        self.identity()
        backup_root = self.store.runtime / "workspace-backups"
        self.state["backupBaseline"] = sorted(path.name for path in backup_root.iterdir()) if backup_root.is_dir() else []
        self.state["backupDiscoveryRequired"] = True
        self.save()
        result = self.operation("backup", page=f"/projects/{self.fixture['slug']}?tab=backups")
        try:
            receipt = json.loads(result["result"]) if isinstance(result.get("result"), str) else result["result"]
        except (KeyError, json.JSONDecodeError):
            raise AcceptanceError("BACKUP_RECEIPT_INVALID") from None
        # Even an insufficient durability receipt can have created a valid local
        # archive. Bind that fixture before rejecting Vault acceptance.
        immediate = self.backup_evidence(self.original())
        require(isinstance(receipt, dict) and receipt.get("ok") is True and receipt.get("backup_status") == "verified"
                and receipt.get("vault_upload_status") == "verified" and receipt.get("durability_level") == "vault",
                "VAULT_UPLOAD_NOT_VERIFIED")
        require(receipt.get("backup_id") == immediate["backupId"] and receipt.get("backup_sha256") == immediate["archiveSha256"],
                "BACKUP_RECEIPT_DISAGREES")
        self.state["quarantineUnverified"] = True
        self.save()
        quarantined = self.operation("quarantine", page=f"/projects/{self.fixture['slug']}?tab=isolate",
                                    fields={"confirm_quarantine": "true"})
        path = exact_returned_child(self.store.quarantine, quarantined.get("result"), "QUARANTINE_PATH_INVALID")
        require(re.fullmatch(r"[0-9]{8}-[0-9]{6}-" + re.escape(self.fixture["slug"]), path.name),
                "QUARANTINE_NAME_INVALID")
        self.store.verify_identity(path, self.fixture, self.request["execution"])
        self.store.verify_owner(path, self.fixture)
        require(not Path(self.fixture["originalPath"]).exists(), "QUARANTINE_ORIGINAL_REMAINS")
        self.state["ledger"].append({"kind": "quarantine", "path": str(path)})
        self.state["quarantineUnverified"] = False
        self.save()
        quarantine_backup = self.backup_evidence(path)
        require(not any((item.get("State") or {}).get("Running") for item in self.probe.containers(self.fixture["projectId"])),
                "QUARANTINED_RUNTIME_REMAINS")
        collision = safe_child(self.store.workspaces, self.fixture["slug"])
        collision.mkdir()
        marker = canonical({"runId": self.request["runId"], "nonce": self.fixture["owner"]["nonce"], "collision": True})
        with (collision / OWNER_FILE).open("xb") as stream:
            stream.write(marker)
        self.state["collisionSha256"] = hashlib.sha256(marker).hexdigest()
        self.save()
        try:
            failed = self.operation("restore-quarantine", page="/?view=settings", route="/quarantine/restore",
                                    fields={"name": path.name}, match_fields={"name": path.name},
                                    project=path.name, expected="failed")
            require("already exists" in str(failed.get("error", "")), "QUARANTINE_COLLISION_WRONG_FAILURE")
            require(list(collision.iterdir()) == [collision / OWNER_FILE]
                    and digest(collision / OWNER_FILE) == self.state["collisionSha256"], "COLLISION_WAS_MODIFIED")
            self.store.verify_owner(path, self.fixture)
        finally:
            self.remove_collision()
        self.operation("restore-quarantine", page="/?view=settings", route="/quarantine/restore",
                       fields={"name": path.name}, match_fields={"name": path.name}, project=path.name)
        require(not path.exists(), "QUARANTINE_RESTORE_SOURCE_REMAINS")
        self.identity()
        self.complete("U04", {"immediateBackup": immediate, "quarantineBackup": quarantine_backup,
                              "quarantineName": path.name, "sentinelSha256": self.fixture["sentinelSha256"]})

    def remove_collision(self) -> None:
        if not self.state.get("collisionSha256"):
            return
        path = safe_child(self.store.workspaces, self.fixture["slug"], exists=True)
        require(list(path.iterdir()) == [path / OWNER_FILE] and not (path / OWNER_FILE).is_symlink()
                and digest(path / OWNER_FILE) == self.state["collisionSha256"], "COLLISION_CLEANUP_REFUSED")
        (path / OWNER_FILE).unlink()
        path.rmdir()
        self.state.pop("collisionSha256")
        self.save()

    @contextlib.contextmanager
    def fixture_edit(self, relative: str, replacement: bytes):
        require(relative in {"compose.yaml", ".devfleet/ownership-lease.json"}, "FIXTURE_EDIT_NOT_ALLOWED")
        path = self.original() / relative
        require(path.is_file() and not path.is_symlink() and not path.parent.is_symlink(), "FIXTURE_EDIT_PATH_UNSAFE")
        original = path.read_bytes()
        require(len(original) < 65536, "FIXTURE_EDIT_SOURCE_TOO_LARGE")
        entry = {"relative": relative, "originalBase64": base64.b64encode(original).decode("ascii"),
                 "originalSha256": hashlib.sha256(original).hexdigest(), "replacementSha256": hashlib.sha256(replacement).hexdigest()}
        self.state["temporaryEdits"].append(entry)
        self.save()
        path.write_bytes(replacement)
        body_failure = None
        try:
            yield
        except BaseException as exc:
            body_failure = exc
            raise
        finally:
            try:
                require(not path.is_symlink() and digest(path) == entry["replacementSha256"], "FIXTURE_EDIT_CHANGED_EXTERNALLY")
                path.write_bytes(original)
                self.state["temporaryEdits"].remove(entry)
                self.save()
            except Exception as cleanup_exc:
                if body_failure is None:
                    raise
                self.record_failure(body_failure)
                self.record_failure(cleanup_exc, cleanup=True)

    def u05(self) -> None:
        self.begin("U05")
        before = self.identity()
        existing_names = {path.name for path in self.store.workspaces.iterdir()}
        # A failed or malformed return still requires explicit parent cleanup;
        # never silently claim that an unobserved recovery produced no files.
        self.state["recoveryUnverified"] = True
        self.save()
        result = self.operation("restore-vault", page=f"/projects/{self.fixture['slug']}?tab=backups")
        copy = self.store.verify_copy(result.get("result"), self.fixture, self.request["execution"])
        require(copy.name not in existing_names, "RESTORE_COPY_OVERWROTE_EXISTING_PATH")
        self.fixture["recoveredPath"] = str(copy)
        self.state["ledger"].append({"kind": "recovered-copy", "path": str(copy)})
        self.state["recoveryUnverified"] = False
        self.save()
        after = self.identity()
        require(all(before.get(key) == after.get(key) for key in ("project_id", "slug", "runtime_id", "deployment_id", "host_id")),
                "ORIGINAL_CHANGED_DURING_COPY")
        # The unadopted copy must be rejected synchronously, before admission to
        # the asynchronous worker pool. No positive action form exists for it.
        page = self.ui.page(f"/projects/{self.fixture['slug']}")
        require(page.csrf, "RECOVERED_COPY_PROBE_CSRF_MISSING")
        operations_before = self.store.operation_ids()
        copy_start_route = f"/projects/{copy.name}/start"
        rejected = self.ui.request("POST", copy_start_route, {"csrf_token": page.csrf})
        require(rejected.status == 409, "RECOVERED_COPY_START_NOT_REJECTED")
        operations_after = self.store.operation_ids()
        require(operations_before == operations_after, "RECOVERED_COPY_OPERATION_WAS_CREATED")
        copy_start = {"route": copy_start_route, "httpStatus": 409, "operationCreated": False,
                      "beforeInventorySha256": hashlib.sha256(canonical(operations_before)).hexdigest(),
                      "afterInventorySha256": hashlib.sha256(canonical(operations_after)).hexdigest()}
        self.store.verify_copy(str(copy), self.fixture, self.request["execution"])
        require(not any((item.get("State") or {}).get("Running") for item in self.probe.containers(self.fixture["projectId"])),
                "RECOVERED_COPY_STARTED_WRITER")
        compose = self.original() / "compose.yaml"
        text = compose.read_text(encoding="utf-8")
        # Existing harmless security corpus: unsupported execution field. This
        # never requests privileged mode, a host path, or any actual host resource.
        require(re.search(r"(?m)^  [A-Za-z0-9_-]+:\s*$", text), "GENERIC_COMPOSE_SHAPE_UNEXPECTED")
        edited = re.sub(r"(?m)^(  [A-Za-z0-9_-]+:\s*)$", r"\1\n    future_execution_field: true", text, count=1)
        with self.fixture_edit("compose.yaml", edited.encode("utf-8")):
            failed = self.operation("start", expected="failed")
            require("security analyzer" in str(failed.get("error", "")).lower(), "SECURITY_FIXTURE_WRONG_FAILURE")
            require(not self.probe.containers(self.fixture["projectId"]), "SECURITY_FIXTURE_CREATED_CONTAINER")
        lease = read_json(self.original() / ".devfleet" / "ownership-lease.json")
        foreign = {**lease, "active": True, "active_node": "df-accept-foreign-" + self.fixture["slug"][-12:]}
        with self.fixture_edit(".devfleet/ownership-lease.json", canonical(foreign)):
            failed = self.operation("start", expected="failed")
            require("ownership lease" in str(failed.get("error", "")).lower(), "OWNERSHIP_FIXTURE_WRONG_FAILURE")
            require(not self.probe.containers(self.fixture["projectId"]), "OWNERSHIP_FIXTURE_CREATED_CONTAINER")
        self.operation("start")
        self.operation("health")
        runtime = self.wait_healthy()
        self.store.verify_copy(str(copy), self.fixture, self.request["execution"])
        self.assert_no_pending()
        self.complete("U05", {**runtime, "recoveredPath": str(copy), "copyAdopted": False, "copyStart": copy_start,
                              "sentinelSha256": self.fixture["sentinelSha256"]})

    def resume(self, credentials: tuple[str, str]) -> None:
        require(self.state.get("prepared") is True and not self.state.get("resumed") and not self.state.get("failure"),
                "RESUME_NOT_PREPARED")
        require(self.state["cleanup"]["status"] == "NOT_RUN", "RESUME_ALREADY_CLEANED")
        preflight = self.probe.preflight(self.request)
        previous, current = self.state["serviceBeforeRestart"], preflight["service"]
        require(previous["bootId"] == current["bootId"], "UNEXPECTED_GUEST_REBOOT")
        require(previous["invocationId"] != current["invocationId"], "SERVICE_RESTART_NOT_OBSERVED")
        self.ui.login(*credentials)
        self.identity()
        self.operation("health")
        runtime = self.wait_healthy()
        self.assert_no_pending()
        self.complete("U03", {**runtime, "serviceBefore": previous, "serviceAfter": current,
                              "sentinelSha256": self.fixture["sentinelSha256"]})
        self.u04()
        self.u05()
        self.state["resumed"] = True
        self.save()

    def restore_edits(self) -> None:
        for edit in list(reversed(self.state["temporaryEdits"])):
            require(edit["relative"] in {"compose.yaml", ".devfleet/ownership-lease.json"}, "CLEANUP_EDIT_INVALID")
            path = self.original() / edit["relative"]
            require(path.is_file() and not path.is_symlink() and not path.parent.is_symlink(), "CLEANUP_EDIT_PATH_UNSAFE")
            original = base64.b64decode(edit["originalBase64"], validate=True)
            require(hashlib.sha256(original).hexdigest() == edit["originalSha256"], "CLEANUP_EDIT_HASH_INVALID")
            require(digest(path) in {edit["replacementSha256"], edit["originalSha256"]}, "CLEANUP_EDIT_CHANGED_EXTERNALLY")
            path.write_bytes(original)
            self.state["temporaryEdits"].remove(edit)
            self.save()

    def discover_backup_fixtures(self) -> None:
        """Account for an archive written before a broker/operation failure."""
        if not self.state.get("backupDiscoveryRequired"):
            return
        root = self.store.runtime / "workspace-backups"
        if not root.exists():
            return
        require(root.is_dir() and not root.is_symlink(), "CLEANUP_BACKUP_ROOT_UNSAFE")
        baseline = set(self.state["backupBaseline"])
        for directory in root.iterdir():
            if directory.name in baseline or not directory.name.startswith(self.fixture["slug"] + "-"):
                continue
            manifest = read_json(directory / "manifest.json")
            require(manifest.get("project_id") == self.fixture["projectId"] and manifest.get("slug") == self.fixture["slug"],
                    "CLEANUP_NEW_BACKUP_NOT_OWNED")
            meta = {"backup_id": directory.name, "backup_path": str(directory / (self.fixture["slug"] + ".tar.gz")),
                    "backup_sha256": manifest.get("workspace", {}).get("archive_sha256")}
            evidence = self.store.verify_backup(meta, self.fixture)
            if evidence["path"] not in {entry["path"] for entry in self.state["ledger"]}:
                self.state["ledger"].append(evidence)
                self.save()

    def cleanup(self) -> None:
        cleanup = self.state["cleanup"]
        if cleanup["status"] == "PASS":
            return
        require(self.fixture.get("projectId") and self.fixture.get("owner"), "CLEANUP_FIXTURE_NOT_BOUND")
        self.remove_collision()
        self.restore_edits()
        # Never delete a path while an accepted asynchronous operation can still
        # mutate it. A failed/expired operation is not evidence its worker died.
        for entry in self.state["operations"]:
            value = self.ui.json("/ui/operations/" + entry["id"])
            require(value.get("state") in {"completed", "failed"}, "CLEANUP_OPERATION_NOT_QUIESCENT")
        original = Path(self.fixture["originalPath"])
        if original.exists():
            self.identity()
            if self.probe.containers(self.fixture["projectId"]):
                # Cleanup is still an authenticated product operation, including
                # partially failed starts where the rendered stop button is absent.
                self.operation("stop", negative_fixture=True)
        require(not self.probe.containers(self.fixture["projectId"]), "CLEANUP_CONTAINERS_REMAIN")
        require(not self.state.get("recoveryUnverified"), "CLEANUP_UNVERIFIED_RECOVERY_REQUIRES_PARENT")
        require(not self.state.get("quarantineUnverified"), "CLEANUP_UNVERIFIED_QUARANTINE_REQUIRES_PARENT")
        self.discover_backup_fixtures()
        for entry in reversed(self.state["ledger"]):
            path = Path(entry["path"])
            if not path.exists():
                cleanup["resources"].append({"kind": entry["kind"], "path": str(path), "status": "ABSENT"})
                continue
            if entry["kind"] == "backup":
                require(path.parent == self.store.runtime / "workspace-backups" and not path.is_symlink(),
                        "CLEANUP_BACKUP_PATH_INVALID")
                manifest = read_json(path / "manifest.json")
                require(digest(path / "manifest.json") == entry["manifestSha256"]
                        and manifest.get("project_id") == self.fixture["projectId"]
                        and manifest.get("backup_id") == entry["backupId"], "CLEANUP_BACKUP_IDENTITY_MISMATCH")
                require(not any(item.is_symlink() for item in path.rglob("*")), "CLEANUP_TREE_SYMLINK_REJECTED")
                shutil.rmtree(path)
            else:
                self.store.remove_owned_tree(path, self.fixture)
            require(not path.exists(), "CLEANUP_RESOURCE_REMAINS")
            cleanup["resources"].append({"kind": entry["kind"], "path": str(path), "status": "REMOVED"})
            self.save()
        cleanup["status"] = "PASS"
        self.save()

    def record_failure(self, exc: BaseException, *, cleanup: bool = False) -> None:
        code = exc.code if isinstance(exc, AcceptanceError) else "UNEXPECTED_DRIVER_FAILURE"
        if cleanup:
            self.state["cleanupFailure"] = self.state["cleanupFailure"] or {"code": code}
            self.state["cleanup"]["status"] = "BLOCKED"
            self.state["cleanup"]["errors"].append(code)
        elif self.state["failure"] is None:
            self.state["failure"] = {"code": code, "journey": self.state["currentJourney"]}
            for row in self.state["journeys"]:
                if row["id"] == self.state["currentJourney"] and row["status"] != "PASS":
                    row["status"] = "BLOCKED"
        self.save()

    def report(self, stage: str) -> dict[str, Any]:
        passed = (self.state["resumed"] and self.state["cleanup"]["status"] == "PASS"
                  and not self.state["failure"] and not self.state["cleanupFailure"]
                  and all(row["status"] == "PASS" and row["assertions"] == {key: True for key in ASSERTIONS[row["id"]]}
                          for row in self.state["journeys"])
                  and {row["id"] for row in self.state["journeys"]} == set(ASSERTIONS)
                  and len(self.state["journeys"]) == 5)
        prepared = self.state["prepared"] and not self.state["failure"] and not self.state["cleanupFailure"] and stage == "prepare"
        fixture = {key: self.fixture[key] for key in ("slug", "projectId", "sentinelSha256", "originalPath", "recoveredPath")
                   if key in self.fixture}
        result = {
            "schemaVersion": 1, "contract": CONTRACT, "status": "PASS" if passed else "PREPARED" if prepared else "BLOCKED",
            "stage": stage, "runId": self.request["runId"], "phaseId": "REAL-USE-ACCEPTANCE",
            "candidate": self.request["candidate"],
            "execution": {**self.request["execution"], "uiTransport": "authenticated-http-form",
                          "browserJavascriptExercised": False},
            "runnerSha256": self.request["runnerSha256"], "startedAtUtc": self.state["startedAtUtc"],
            "finishedAtUtc": utc_now(), "deadlineUtc": self.request["deadlineUtc"],
            "journeys": self.state["journeys"], "operations": self.state["operations"], "fixture": fixture,
            "cleanup": self.state["cleanup"], "failure": self.state["failure"], "cleanupFailure": self.state["cleanupFailure"],
        }
        all_secrets = self.ui.secret_values + self.ui.transport.secrets()
        return redact(result, all_secrets)

    def execute(self, stage: str, credentials: tuple[str, str]) -> dict[str, Any]:
        try:
            if stage == "prepare":
                self.prepare(credentials)
            elif stage == "resume":
                self.resume(credentials)
            else:
                self.probe.preflight(self.request)
                self.ui.login(*credentials)
        except Exception as exc:
            self.record_failure(exc)
        if stage != "prepare" or self.state["failure"]:
            try:
                if self.fixture.get("projectId") and self.fixture.get("owner"):
                    self.cleanup()
                elif self.fixture:
                    raise AcceptanceError("CLEANUP_PARTIAL_CREATE_REQUIRES_PARENT")
            except Exception as exc:
                self.record_failure(exc, cleanup=True)
        return self.report(stage)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, choices=("prepare", "resume", "cleanup"))
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    result: dict[str, Any]
    try:
        require(args.input.resolve() not in {args.state.resolve(), args.output.resolve()}
                and args.state.resolve() != args.output.resolve(), "INPUT_OUTPUT_PATH_COLLISION")
        request = normalized_request(read_json(args.input), digest(Path(__file__)))
        require(args.stage != "prepare" or not args.state.exists(), "PREPARE_STATE_ALREADY_EXISTS")
        state = read_json(args.state) if args.stage != "prepare" else None
        dashboard = Dashboard(HttpTransport(request["baseUrl"]), instant(request["deadlineUtc"]))
        runner = AcceptanceRunner(request, args.state, dashboard, NativeProbe(), state=state)
        credentials = (os.environ.get("DEVFLEET_ADMIN_USER", ""), os.environ.get("DEVFLEET_ADMIN_PASSWORD", ""))
        result = runner.execute(args.stage, credentials)
    except Exception as exc:
        result = {"schemaVersion": 1, "contract": CONTRACT, "status": "BLOCKED", "stage": args.stage,
                  "phaseId": "REAL-USE-ACCEPTANCE",
                  "failure": {"code": exc.code if isinstance(exc, AcceptanceError) else "DRIVER_INITIALIZATION_FAILED"},
                  "cleanup": {"status": "NOT_RUN", "ownedOnly": True}}
    try:
        write_json(args.output, result)
    except Exception:
        # No traceback, command line, secret-containing response or raw exception.
        print(json.dumps({"status": "BLOCKED", "failure": {"code": "EVIDENCE_WRITE_FAILED"}}))
        return 1
    print(json.dumps({"status": result["status"], "contract": CONTRACT, "stage": args.stage,
                      "evidenceSha256": digest(args.output)}, sort_keys=True))
    return 0 if result["status"] in {"PASS", "PREPARED"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
