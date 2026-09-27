"""Isolated driver-contract tests. These fixtures do not earn live acceptance."""
from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import time
import urllib.parse
import uuid

import pytest


DRIVER = Path(__file__).parents[1] / "modules" / "executors" / "Invoke-RealUseAcceptance.py"
SPEC = importlib.util.spec_from_file_location("real_use_acceptance_driver", DRIVER)
driver = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = driver
SPEC.loader.exec_module(driver)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


@pytest.fixture
def request_data(tmp_path):
    paths = {key: str(tmp_path / key) for key in ("workspaces", "quarantine", "runtimeRoot")}
    for path in paths.values():
        Path(path).mkdir()
    (Path(paths["runtimeRoot"]) / "operations").mkdir()
    return {
        "schemaVersion": 1, "runId": "fullrelease-unit-real-use-20260916T000000Z",
        "deadlineUtc": (datetime.now(timezone.utc) + timedelta(hours=12)).isoformat(),
        "runnerSha256": driver.digest(DRIVER),
        "candidate": {
            "repositoryHead": "a" * 40, "candidateCommit": "b" * 40,
            "shippingInputIdentity": "c" * 64, "releaseFingerprintId": "d" * 64,
            "toolingFingerprintId": "e" * 64, "exeSha256": "f" * 64, "tarSha256": "1" * 64,
        },
        "execution": {
            "role": "Laptop / Surrogate", "vmName": "DevFleet-E2E-Unit", "vmId": str(uuid.uuid4()),
            "computeInstanceName": "DevFleetFailover", "vaultInstanceName": "DevFleetVault",
            "deploymentId": str(uuid.uuid4()), "nodeId": str(uuid.uuid4()), "nodeName": "unit-surrogate",
            "transactionId": str(uuid.uuid4()), "invocationId": str(uuid.uuid4()),
            "surrogateEvidenceSha256": "2" * 64,
        },
        "paths": paths, "baseUrl": "http://127.0.0.1:8787",
    }


class FakeDaemon:
    """Small product transport adapter; models receipts, not success-state bypass."""
    def __init__(self, request):
        self.request_data = request
        self.root = Path(request["paths"]["workspaces"])
        self.quarantine = Path(request["paths"]["quarantine"])
        self.runtime = Path(request["paths"]["runtimeRoot"])
        self.sequence = 0
        self.operations = {}
        self.container_data = {}
        self.requests = []
        self.snapshots = {}
        self.logged_in = False
        self.csrf = "csrf-sensitive-fixture-value"
        self.password = "password-sensitive-fixture-value"
        self.cookie = "session-sensitive-fixture-value"
        self.fault = ""

    def secrets(self):
        return [self.cookie]

    def form(self, action, fields=None):
        inputs = {"csrf_token": self.csrf, **(fields or {})}
        return '<form method="post" action="' + action + '">' + "".join(
            f'<input name="{key}" value="{value}">' for key, value in inputs.items()) + "</form>"

    def response(self, value, status=200, headers=None):
        return driver.Response(status, headers or {}, json.dumps(value) if isinstance(value, dict) else value)

    def metadata(self, slug):
        return json.loads((self.root / slug / ".devfleet/project.json").read_text())

    def save_metadata(self, slug, meta):
        write_json(self.root / slug / ".devfleet/project.json", meta)

    def request(self, method, route, fields, timeout):
        assert 0 < timeout <= 30
        self.requests.append((method, route, dict(fields or {})))
        parsed = urllib.parse.urlsplit(route)
        query = urllib.parse.parse_qs(parsed.query)
        if route == "/login" and method == "GET":
            return self.response(self.form("/login"))
        if route == "/login" and method == "POST":
            assert fields["csrf_token"] == self.csrf
            if fields.get("username") != "unit-admin" or fields.get("password") != self.password:
                return self.response("not logged in", 401)
            self.logged_in = True
            return self.response("", 303, {"location": "/"})
        if not self.logged_in:
            return self.response("", 303, {"location": "/login"})
        if method == "GET" and parsed.path.startswith("/ui/operations/"):
            value = copy.deepcopy(self.operations[parsed.path.rsplit("/", 1)[-1]])
            return self.response(value)
        if method == "GET" and parsed.path.startswith("/containers/"):
            identifier = parsed.path.split("/")[2]
            return self.response(copy.deepcopy(self.container_data[identifier]))
        if method == "GET":
            body = self.form("/logout")
            if "operation" in query:
                op_id = query["operation"][0]
                state = self.operations[op_id]["state"]
                css = "complete" if state == "completed" else "failed" if state == "failed" else ""
                if self.fault == "rendered-disagreement":
                    css = "failed" if css == "complete" else "complete"
                body += f'<section class="operation-banner {css}" data-operation-id="{op_id}"></section>'
            if query.get("view") == ["projects"]:
                body += self.form("/projects/create")
            if query.get("view") == ["settings"]:
                for path in self.quarantine.iterdir():
                    if path.is_dir():
                        body += self.form("/quarantine/restore", {"name": path.name})
            if parsed.path.startswith("/projects/"):
                slug = parsed.path.split("/")[2]
                if (self.root / slug).is_dir() and (self.root / slug / ".devfleet/project.json").exists():
                    meta = self.metadata(slug)
                    body += f'<section data-project-state="{meta["lifecycle_status"]}"></section>'
                    for action in ("start", "stop", "restart", "health", "test", "backup", "quarantine", "restore-vault"):
                        body += self.form(f"/projects/{slug}/{action}")
            return self.response(body)
        assert method == "POST" and fields["csrf_token"] == self.csrf
        if parsed.path.startswith("/projects/"):
            slug = parsed.path.split("/")[2]
            if "-recovered-" in slug and parsed.path.endswith("/start"):
                if self.fault == "copy-admitted":
                    return self.admit("start", slug, "completed", "")
                if self.fault == "copy-operation-created":
                    self.admit("start", slug, "failed", "")
                return self.response("recovery-only", 409)
        if parsed.path == "/projects/create":
            kind, slug = "create", fields["slug"]
        elif parsed.path == "/quarantine/restore":
            kind, slug = "restore-quarantine", fields["name"]
        else:
            slug, kind = parsed.path.split("/")[2:4]
        try:
            value = self.action(kind, slug, fields)
            return self.admit(kind, slug, "completed", value)
        except ValueError as exc:
            return self.admit(kind, slug, "failed", "", str(exc))

    def admit(self, kind, slug, state, result, error=""):
        self.sequence += 1
        op_id = f"op-{self.sequence:08d}"
        value = {"id": op_id, "kind": kind, "project": slug, "state": state,
                 "result": result, "error": error, "log": [{"message": "private arbitrary log " + self.password}]}
        self.operations[op_id] = value
        write_json(self.runtime / "operations" / (op_id + ".json"), value)
        return self.response("", 303, {"location": "/?operation=" + op_id})

    def action(self, kind, slug, fields):
        path = self.root / slug
        if kind == "create":
            assert fields["template"] == "generic"
            assert fields["runtime_isolation"] == "container" and fields["git_url"] == ""
            assert fields["profile"] == "balanced" and fields.get("use_ollama", "") == ""
            path.mkdir()
            (path / ".devfleet").mkdir()
            (path / ".devcontainer").mkdir()
            (path / "compose.yaml").write_text("services:\n  dev:\n    image: harmless\n")
            (path / ".devcontainer/devcontainer.json").write_text("{}")
            for name in ("smoke-test", "health-check"):
                (path / ".devfleet" / (name + ".sh")).write_text("#!/bin/sh\ntrue\n")
            meta = {"schema_version": 3, "managed_by": "devfleet", "slug": slug,
                    "project_id": str(uuid.uuid4()), "runtime_id": "df_" + slug.replace("-", "_"),
                    "runtime_provider": "docker-compose", "deployment_id": self.request_data["execution"]["deploymentId"],
                    "host_id": self.request_data["execution"]["nodeName"], "template": "generic",
                    "lifecycle_status": "ready", "health_status": "unknown"}
            self.save_metadata(slug, meta)
            write_json(path / ".devfleet/ownership-lease.json", {"active": False, "active_node": meta["host_id"]})
            return meta
        if kind == "restore-quarantine":
            quarantined = self.quarantine / slug
            meta = json.loads((quarantined / ".devfleet/project.json").read_text())
            target = self.root / meta["slug"]
            if target.exists():
                raise ValueError("Quarantine restore blocked: path already exists.")
            quarantined.rename(target)
            return str(target)
        meta = self.metadata(slug)
        if kind == "start":
            lease = json.loads((path / ".devfleet/ownership-lease.json").read_text())
            if lease.get("active") and lease.get("active_node") != meta["host_id"]:
                raise ValueError("Ownership lease belongs to a foreign node.")
            if "future_execution_field" in (path / "compose.yaml").read_text():
                raise ValueError("Security analyzer found blocking boundary violations.")
            meta["lifecycle_status"] = "running"
            self.save_metadata(slug, meta)
            identifier = hashlib.sha256((slug + str(self.sequence)).encode()).hexdigest()
            self.container_data[identifier] = {
                "Id": identifier, "State": {"Running": True, "Health": {"Status": "healthy"}},
                "Config": {"Labels": {
                    **{label: meta[key] for key, label in driver.LABELS.items()},
                    "com.docker.compose.project": meta["runtime_id"], "com.docker.compose.service": "dev",
                }},
            }
            return "started"
        if kind == "stop":
            self.container_data = {key: item for key, item in self.container_data.items()
                                   if item["Config"]["Labels"]["io.devfleet.project-id"] != meta["project_id"]}
            meta["lifecycle_status"] = "stopped"
            self.save_metadata(slug, meta)
            return "stopped"
        if kind in {"health", "test"}:
            if self.fault == "health-failure" and kind == "health":
                raise ValueError("health failure with " + self.password)
            if kind == "health":
                meta["health_status"] = "healthy"
                self.save_metadata(slug, meta)
            return "Template smoke test passed."
        if kind == "backup":
            backup_id = slug + "-20260916-000000-" + f"{self.sequence:08x}"
            backup_dir = self.runtime / "workspace-backups" / backup_id
            backup_dir.mkdir(parents=True)
            archive = backup_dir / (slug + ".tar.gz")
            archive.write_bytes(b"fake archive " + (path / driver.SENTINEL_FILE).read_bytes())
            archive_hash = driver.digest(archive)
            manifest = {"schema_version": 1, "backup_id": backup_id, "project_id": meta["project_id"], "slug": slug,
                        "verification": {"status": "verified", "integrity_verified": True},
                        "workspace": {"archive_sha256": archive_hash}}
            write_json(backup_dir / "manifest.json", manifest)
            meta.update(backup_id=backup_id, backup_path=str(archive), backup_sha256=archive_hash, backup_status="verified")
            self.save_metadata(slug, meta)
            snapshot = self.runtime / "fake-remote-snapshots" / backup_id
            shutil.copytree(path, snapshot)
            self.snapshots[slug] = snapshot
            if self.fault == "broker-failed-after-archive":
                raise ValueError("Vault broker unavailable")
            return json.dumps({"ok": True, "backup_id": backup_id, "backup_sha256": archive_hash,
                               "backup_status": "verified", "vault_upload_status": "verified",
                               "durability_level": "local" if self.fault == "local-only-backup" else "vault"})
        if kind == "quarantine":
            assert fields["confirm_quarantine"] == "true"
            self.action("stop", slug, {})
            self.action("backup", slug, {})
            destination = self.quarantine / ("20260916-000000-" + slug)
            path.rename(destination)
            return str(destination)
        if kind == "restore-vault":
            destination = self.root / (slug + "-recovered-20260916-000000-1234abcd")
            shutil.copytree(self.snapshots[slug], destination)
            if self.fault == "copy-content":
                (destination / driver.SENTINEL_FILE).write_text("changed")
            return str(destination)
        raise AssertionError(kind)


class FakeProbe:
    def __init__(self, daemon):
        self.daemon = daemon
        self.generation = "a"
        self.boot = str(uuid.uuid4())

    def service(self):
        return {"invocationId": self.generation * 32, "pid": 123 if self.generation == "a" else 124,
                "active": True, "user": "devfleet-control", "bootId": self.boot}

    def preflight(self, request):
        return {"service": self.service(), "brokerAccessible": True, "vaultTransport": "tailscale-rest"}

    def containers(self, project_id):
        return [copy.deepcopy(item) for item in self.daemon.container_data.values()
                if item["Config"]["Labels"]["io.devfleet.project-id"] == project_id]


def make_runner(request, tmp_path):
    daemon = FakeDaemon(request)
    probe = FakeProbe(daemon)
    ui = driver.Dashboard(daemon, driver.instant(request["deadlineUtc"]))
    runner = driver.AcceptanceRunner(request, tmp_path / "state.json", ui, probe)
    return runner, daemon, probe


def resume_runner(request, runner, daemon, probe):
    ui = driver.Dashboard(daemon, driver.instant(request["deadlineUtc"]))
    return driver.AcceptanceRunner(request, runner.state_path, ui, probe, state=driver.read_json(runner.state_path))


def test_two_stage_real_route_contract(request_data, tmp_path):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    prepared = runner.execute("prepare", ("unit-admin", daemon.password))
    assert prepared["status"] == "PREPARED", prepared
    assert [row["status"] for row in prepared["journeys"]] == ["PASS", "PASS", "IN_PROGRESS", "NOT_RUN", "NOT_RUN"]
    assert prepared["cleanup"]["status"] == "NOT_RUN"
    probe.generation = "b"
    resumed = resume_runner(request_data, runner, daemon, probe)
    report = resumed.execute("resume", ("unit-admin", daemon.password))
    assert report["status"] == "PASS", report
    assert [row["id"] for row in report["journeys"]] == ["U01", "U02", "U03", "U04", "U05"]
    assert all(row["assertions"] == {key: True for key in driver.ASSERTIONS[row["id"]]} for row in report["journeys"])
    copy_start = report["journeys"][4]["observations"]["copyStart"]
    assert copy_start["httpStatus"] == 409 and copy_start["operationCreated"] is False
    assert copy_start["beforeInventorySha256"] == copy_start["afterInventorySha256"]
    assert report["journeys"][4]["observations"]["copyAdopted"] is False
    assert report["cleanup"]["status"] == "PASS"
    assert not list(Path(request_data["paths"]["workspaces"]).iterdir())
    assert not list(Path(request_data["paths"]["quarantine"]).iterdir())
    assert daemon.container_data == {}
    serialized = json.dumps(report)
    for secret in (daemon.password, daemon.csrf, daemon.cookie, "unit-admin"):
        assert secret not in serialized
    assert "private arbitrary log" not in serialized
    assert report["execution"]["browserJavascriptExercised"] is False
    assert not any("/api/" in route for _, route, _ in daemon.requests)


@pytest.mark.parametrize("fault,code", [
    ("health-failure", "OPERATION_UNEXPECTED_TERMINAL"),
    ("rendered-disagreement", "RENDERED_OPERATION_DISAGREES"),
])
def test_prepare_failures_cleanup_without_laundering_primary(request_data, tmp_path, fault, code):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    daemon.fault = fault
    report = runner.execute("prepare", ("unit-admin", daemon.password))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == code
    assert daemon.password not in json.dumps(report)
    assert any(row["state"] in {"failed", "completed"} for row in report["operations"])
    assert not any(row["status"] == "PASS" for row in report["journeys"] if row["id"] in {"U02", "U03", "U04", "U05"})


@pytest.mark.parametrize("fault,code", [
    ("local-only-backup", "VAULT_UPLOAD_NOT_VERIFIED"),
    ("copy-content", "FIXTURE_SENTINEL_MISMATCH"),
    ("copy-admitted", "RECOVERED_COPY_START_NOT_REJECTED"),
    ("copy-operation-created", "RECOVERED_COPY_OPERATION_WAS_CREATED"),
])
def test_resume_rejects_false_recovery_proofs(request_data, tmp_path, fault, code):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    assert runner.execute("prepare", ("unit-admin", daemon.password))["status"] == "PREPARED"
    probe.generation = "b"
    daemon.fault = fault
    report = resume_runner(request_data, runner, daemon, probe).execute("resume", ("unit-admin", daemon.password))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == code, report
    assert report["journeys"][4]["status"] != "PASS"
    assert daemon.password not in json.dumps(report)
    if fault == "copy-content":
        assert report["cleanup"]["status"] == "BLOCKED"
        assert report["cleanupFailure"]["code"] == "CLEANUP_UNVERIFIED_RECOVERY_REQUIRES_PARENT"


def test_failed_broker_archive_is_discovered_and_cleaned(request_data, tmp_path):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    probe.generation = "b"
    daemon.fault = "broker-failed-after-archive"
    report = resume_runner(request_data, runner, daemon, probe).execute("resume", ("unit-admin", daemon.password))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == "OPERATION_UNEXPECTED_TERMINAL"
    assert report["cleanup"]["status"] == "PASS", report
    assert not list((Path(request_data["paths"]["runtimeRoot"]) / "workspace-backups").iterdir())
    assert any(row["kind"] == "backup" and row["status"] == "REMOVED" for row in report["cleanup"]["resources"])


@pytest.mark.parametrize("restart,reboot,code", [
    (False, False, "SERVICE_RESTART_NOT_OBSERVED"),
    (True, True, "UNEXPECTED_GUEST_REBOOT"),
])
def test_resume_requires_service_only_restart(request_data, tmp_path, restart, reboot, code):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    if restart:
        probe.generation = "b"
    if reboot:
        probe.boot = str(uuid.uuid4())
    report = resume_runner(request_data, runner, daemon, probe).execute("resume", ("unit-admin", daemon.password))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == code


def test_cleanup_failure_does_not_replace_primary(request_data, tmp_path, monkeypatch):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    daemon.fault = "health-failure"
    def bad_cleanup():
        raise RuntimeError("cleanup leaked " + daemon.password)
    monkeypatch.setattr(runner, "cleanup", bad_cleanup)
    report = runner.execute("prepare", ("unit-admin", daemon.password))
    assert report["failure"]["code"] == "OPERATION_UNEXPECTED_TERMINAL"
    assert report["cleanupFailure"]["code"] == "UNEXPECTED_DRIVER_FAILURE"
    assert report["cleanup"]["status"] == "BLOCKED"
    assert daemon.password not in json.dumps(report)
    assert "cleanup leaked" not in json.dumps(report)


def test_owner_mismatch_refuses_cleanup(request_data, tmp_path):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    path = Path(runner.fixture["originalPath"])
    write_json(path / driver.OWNER_FILE, {"runId": "someone-else"})
    with pytest.raises(driver.AcceptanceError, match="FIXTURE_OWNER_MISMATCH"):
        runner.cleanup()
    assert path.is_dir()


@pytest.mark.parametrize("mutation,code", [
    ("path", "RESTORE_COPY_PATH_INVALID"),
    ("name", "RESTORE_COPY_NAME_INVALID"),
    ("identity", "PROJECT_IDENTITY_CHANGED"),
    ("content", "FIXTURE_SENTINEL_MISMATCH"),
    ("owner", "FIXTURE_OWNER_MISMATCH"),
])
def test_copy_path_identity_checksum_are_independent(request_data, tmp_path, mutation, code):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    original = Path(runner.fixture["originalPath"])
    target = original.with_name(original.name + "-recovered-20260916-000000-1234abcd")
    shutil.copytree(original, target)
    supplied = str(target)
    if mutation == "path":
        supplied = str(target.parent / ".." / target.name)
    elif mutation == "name":
        different = target.with_name("another-project")
        target.rename(different)
        supplied = str(different)
    elif mutation == "identity":
        value = json.loads((target / ".devfleet/project.json").read_text())
        value["project_id"] = str(uuid.uuid4())
        write_json(target / ".devfleet/project.json", value)
    elif mutation == "content":
        (target / driver.SENTINEL_FILE).write_text("not the snapshot")
    else:
        write_json(target / driver.OWNER_FILE, {"runId": "foreign"})
    with pytest.raises(driver.AcceptanceError, match=code):
        runner.store.verify_copy(supplied, runner.fixture, request_data["execution"])
    assert original.is_dir()


def test_fixture_edit_restores_exact_bytes_when_body_fails(request_data, tmp_path):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    path = Path(runner.fixture["originalPath"]) / "compose.yaml"
    original = path.read_bytes()
    with pytest.raises(ValueError):
        with runner.fixture_edit("compose.yaml", b"temporary fixture"):
            raise ValueError("failure")
    assert path.read_bytes() == original
    assert runner.state["temporaryEdits"] == []


def test_request_rejects_external_origin_and_changed_hash(request_data):
    assert driver.normalized_request(request_data, driver.digest(DRIVER))["runId"] == request_data["runId"]
    changed = copy.deepcopy(request_data)
    changed["baseUrl"] = "http://100.1.2.3:8787"
    with pytest.raises(driver.AcceptanceError, match="DASHBOARD_ORIGIN_INVALID"):
        driver.normalized_request(changed, driver.digest(DRIVER))
    with pytest.raises(driver.AcceptanceError, match="RUNNER_HASH_MISMATCH"):
        driver.normalized_request(request_data, "0" * 64)


def test_request_and_fixture_binding_cannot_be_changed_on_resume(request_data, tmp_path):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    changed = copy.deepcopy(request_data)
    changed["candidate"]["tarSha256"] = "0" * 64
    with pytest.raises(driver.AcceptanceError, match="RESUME_BINDING_MISMATCH"):
        resume_runner(changed, runner, daemon, probe)
    state = driver.read_json(runner.state_path)
    state["fixture"]["slug"] = "real-user-project"
    with pytest.raises(driver.AcceptanceError, match="RESUME_FIXTURE_SCOPE_MISMATCH"):
        driver.AcceptanceRunner(request_data, runner.state_path, runner.ui, probe, state=state)


def test_resume_cannot_extend_owner_deadline(request_data, tmp_path):
    runner, daemon, probe = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    changed = copy.deepcopy(request_data)
    changed["deadlineUtc"] = (datetime.now(timezone.utc) + timedelta(hours=13)).isoformat()
    with pytest.raises(driver.AcceptanceError, match="RESUME_CANNOT_EXTEND_DEADLINE"):
        resume_runner(changed, runner, daemon, probe)


def test_forged_pass_without_five_assertion_sets_is_not_pass(request_data, tmp_path):
    runner, _, _ = make_runner(request_data, tmp_path)
    runner.state["prepared"] = runner.state["resumed"] = True
    runner.state["cleanup"]["status"] = "PASS"
    for row in runner.state["journeys"]:
        row["status"] = "PASS"
    assert runner.report("resume")["status"] == "BLOCKED"


def test_failed_login_never_creates_fixture_or_prints_credentials(request_data, tmp_path):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    report = runner.execute("prepare", ("unit-admin", "wrong-password-sensitive"))
    assert report["status"] == "BLOCKED"
    assert report["failure"]["code"] == "DASHBOARD_LOGIN_FAILED"
    assert not list(Path(request_data["paths"]["workspaces"]).iterdir())
    assert "wrong-password-sensitive" not in json.dumps(report)


def test_missing_csrf_form_is_not_submitted():
    page = driver.Page('<form method="post" action="/projects/create"><input name="slug" value="demo"></form>')
    with pytest.raises(driver.AcceptanceError, match="DASHBOARD_CSRF_MISSING"):
        page.form("/projects/create")


def test_external_operation_redirect_is_rejected(request_data):
    class Transport:
        def request(self, method, route, fields, timeout):
            if method == "GET":
                return driver.Response(200, {}, '<form method="post" action="/projects/create"><input name="csrf_token" value="hidden"></form>')
            return driver.Response(303, {"location": "https://external.invalid/?operation=op-one"}, "")
        def secrets(self):
            return []
    ui = driver.Dashboard(Transport(), driver.instant(request_data["deadlineUtc"]))
    with pytest.raises(driver.AcceptanceError, match="OPERATION_REDIRECT_INVALID"):
        ui.submit("/", "/projects/create")


def test_operation_identity_is_required_before_observation():
    class Transport:
        def request(self, method, route, fields, timeout):
            return driver.Response(200, {}, json.dumps({"id": "op-other", "kind": "start",
                                                      "project": "demo", "state": "completed"}))
        def secrets(self):
            return []
    ui = driver.Dashboard(Transport(), time.time() + 10)
    with pytest.raises(driver.AcceptanceError, match="OPERATION_IDENTITY_MISMATCH"):
        ui.wait_operation("op-one", "start", "demo", "completed", 1)


def test_collision_cleanup_refuses_changed_directory(request_data, tmp_path):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    original = Path(runner.fixture["originalPath"])
    shutil.rmtree(original)
    original.mkdir()
    (original / driver.OWNER_FILE).write_bytes(b"collision")
    runner.state["collisionSha256"] = driver.digest(original / driver.OWNER_FILE)
    (original / "foreign-preserve.txt").write_text("preserve")
    with pytest.raises(driver.AcceptanceError, match="COLLISION_CLEANUP_REFUSED"):
        runner.remove_collision()
    assert (original / "foreign-preserve.txt").read_text() == "preserve"


def test_fixture_restore_failure_preserves_body_failure(request_data, tmp_path):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    path = Path(runner.fixture["originalPath"]) / "compose.yaml"
    with pytest.raises(driver.AcceptanceError, match="PRIMARY_TEST_FAILURE"):
        with runner.fixture_edit("compose.yaml", b"known edit"):
            path.write_bytes(b"changed by another actor")
            raise driver.AcceptanceError("PRIMARY_TEST_FAILURE")
    assert runner.state["failure"]["code"] == "PRIMARY_TEST_FAILURE"
    assert runner.state["cleanupFailure"]["code"] == "FIXTURE_EDIT_CHANGED_EXTERNALLY"
    assert path.read_bytes() == b"changed by another actor"


def test_native_observer_does_not_propagate_dashboard_credentials(monkeypatch):
    probe = object.__new__(driver.NativeProbe)
    probe.docker_host = "unix:///run/user/1000/docker.sock"
    monkeypatch.setenv("DEVFLEET_ADMIN_PASSWORD", "never-to-child-process")
    captured = {}
    class Completed:
        returncode = 0
        stdout = "active\n"
    def run(arguments, **kwargs):
        captured.update(kwargs)
        return Completed()
    monkeypatch.setattr(driver.subprocess, "run", run)
    assert probe.command(["/usr/bin/systemctl", "is-active", "devfleet.service"]) == "active\n"
    assert "DEVFLEET_ADMIN_PASSWORD" not in captured["env"]
    assert captured["timeout"] == 30


def test_backup_checksum_mismatch_is_not_accepted(request_data, tmp_path):
    runner, daemon, _ = make_runner(request_data, tmp_path)
    runner.execute("prepare", ("unit-admin", daemon.password))
    daemon.action("backup", runner.fixture["slug"], {})
    meta = runner.identity()
    Path(meta["backup_path"]).write_bytes(b"corrupted")
    with pytest.raises(driver.AcceptanceError, match="BACKUP_ARCHIVE_HASH_MISMATCH"):
        runner.store.verify_backup(meta, runner.fixture)


def test_redaction_covers_nested_values_and_short_exact_secret():
    value = {"error": "server said password-one and csrf-value", "rows": [{"value": "x"}], "ok": True}
    result = driver.redact(value, ["password-one", "csrf-value", "x"])
    assert result == {"error": "server said [REDACTED] and [REDACTED]",
                      "rows": [{"value": "[REDACTED]"}], "ok": True}


def test_cross_origin_request_is_rejected_before_open():
    transport = driver.HttpTransport("http://127.0.0.1:8787")
    with pytest.raises(driver.AcceptanceError, match="CROSS_ORIGIN_REQUEST_REJECTED"):
        transport.request("POST", "//external.invalid/steal", {"password": "secret"}, 1)


def test_http_transport_uses_same_origin_no_secret_url(monkeypatch):
    transport = driver.HttpTransport("http://127.0.0.1:8787")
    observed = []
    class Stream(io.BytesIO):
        code = 200
        headers = {}
    class Opener:
        def open(self, request, timeout):
            observed.append(request)
            return Stream(b"ok")
    transport.opener = Opener()
    transport.request("POST", "/login", {"password": "sensitive-password"}, 1)
    request = observed[0]
    assert request.full_url == "http://127.0.0.1:8787/login"
    assert request.get_header("Origin") == "http://127.0.0.1:8787"
    assert request.get_header("Referer") == "http://127.0.0.1:8787/"
    assert b"sensitive-password" in request.data
    assert "sensitive-password" not in request.full_url


def test_operation_timeout_is_finite_and_never_passes():
    clock = [100.0]
    class Transport:
        def request(self, method, route, fields, timeout):
            return driver.Response(200, {}, json.dumps({"id": "op-one", "kind": "start", "project": "unit-project", "state": "running"}))
        def secrets(self):
            return []
    ui = driver.Dashboard(Transport(), 103, clock=lambda: clock[0], sleep=lambda amount: clock.__setitem__(0, clock[0] + amount))
    with pytest.raises(driver.AcceptanceError, match="OPERATION_DEADLINE_EXPIRED"):
        ui.wait_operation("op-one", "start", "unit-project", "completed", 2)
    assert clock[0] == 102


def test_invalid_cli_input_is_sanitized_and_no_pass(tmp_path, capsys):
    source, state, output = tmp_path / "input.json", tmp_path / "state.json", tmp_path / "output.json"
    source.write_text('{"password":"must-not-be-printed"')
    result = driver.main(["--stage", "prepare", "--input", str(source), "--state", str(state), "--output", str(output)])
    assert result == 1
    printed = capsys.readouterr()
    assert "must-not-be-printed" not in printed.out + printed.err + output.read_text()
    assert json.loads(output.read_text())["status"] == "BLOCKED"
    assert not state.exists()
