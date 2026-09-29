# DevFleet source part 095

Full-source UTF-8 byte interval [4371000, 4417500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 174dd10ccac4e66fa0f4c99b710b5ea894cc9cc052378c2e80289f022c3661b9

<!-- BEGIN SOURCE SLICE -->
ml").write_text("services:\n  app:\n    image: ubuntu:24.04\n", encoding="utf-8")
    metadata_file = project / ".devfleet" / "project.json"
    metadata_file.write_text("{not-json", encoding="utf-8")

    with pytest.raises(ValueError, match="malformed"):
        projects.assign_project_runtime(slug, "container", "small")

    assert metadata_file.read_text() == "{not-json"

```


## FILE: source/tests/test_failover.py

SHA256: b69044da502f5c37cc4cd12d91091606a314ba90f0ff1157002439abb7ca5e6c | Bytes: 11565 | Git mode: 100644

```
from __future__ import annotations

from collections import deque

import pytest

from devfleet import failover
from devfleet.failover import guided_transfer


class C:
    def __init__(self):
        self.events = []

    def update(self, progress, message):
        self.events.append((progress, message))


def _receipt(operation_id: str) -> dict[str, object]:
    return {
        "ok": True,
        "accepted": True,
        "operation_id": operation_id,
        "operation_url": f"/api/operations/{operation_id}",
    }


def _record(operation_id: str, state: str, **extra: object) -> dict[str, object]:
    return {"operation_id": operation_id, "id": operation_id, "state": state, **extra}


TRANSFER = {
    "project_id": "12345678-1234-1234-1234-123456789abc",
    "deployment_id": "deployment-1234",
    "source_host_id": "devfleet-primary",
    "destination_host_id": "devfleet-failover",
}


def _run_transfer(peer, events, *, finalize_source=None):
    if finalize_source is None:
        finalize_source = lambda slug, project_id, destination_host_id: events.append(
            ("finalized", slug, project_id, destination_host_id)
        )
    return guided_transfer(
        "demo",
        C(),
        stop=lambda slug: events.append(("stop", slug)),
        backup=lambda slug: events.append(("backup", slug)),
        assert_quiesced=lambda slug, project_id: events.append(
            ("quiesced", slug, project_id)
        ),
        finalize_source=finalize_source,
        peer_call=peer,
        **TRANSFER,
    )


def test_guided_transfer_rejects_non_distinct_destination_before_stop():
    with pytest.raises(ValueError, match="distinct destination"):
        guided_transfer(
            "demo",
            C(),
            stop=lambda _: (_ for _ in ()).throw(RuntimeError("must not run")),
            backup=lambda _: (_ for _ in ()).throw(RuntimeError("must not run")),
            assert_quiesced=lambda *_: (_ for _ in ()).throw(
                RuntimeError("must not run")
            ),
            finalize_source=lambda *_: (_ for _ in ()).throw(
                RuntimeError("must not run")
            ),
            peer_call=lambda *_: (_ for _ in ()).throw(RuntimeError("must not run")),
            **{**TRANSFER, "destination_host_id": "DEVFLEET-PRIMARY"},
        )


def test_guided_transfer_receives_finalizes_then_activates_and_starts_atomically():
    events = []
    responses = {
        ("POST", "/api/transfers/receive"): deque([_receipt("receive-op")]),
        ("GET", "/api/operations/receive-op"): deque(
            [_record("receive-op", "running"), _record("receive-op", "completed")]
        ),
        ("POST", "/api/transfers/activate"): deque([_receipt("activate-op")]),
        ("GET", "/api/operations/activate-op"): deque(
            [_record("activate-op", "running"), _record("activate-op", "completed")]
        ),
    }

    def peer(method, path, payload, timeout):
        events.append(("peer", method, path, payload, timeout))
        return responses[(method, path)].popleft()

    _run_transfer(peer, events)

    sequence = [(event[1], event[2]) for event in events if event[0] == "peer"]
    assert sequence == [
        ("POST", "/api/transfers/receive"),
        ("GET", "/api/operations/receive-op"),
        ("GET", "/api/operations/receive-op"),
        ("POST", "/api/transfers/activate"),
        ("GET", "/api/operations/activate-op"),
        ("GET", "/api/operations/activate-op"),
    ]
    receive_request = next(
        event
        for event in events
        if event[:3] == ("peer", "POST", "/api/transfers/receive")
    )
    assert receive_request[3] == {
        "slug": "demo",
        **TRANSFER,
        "confirm_slug": "demo",
        "confirm_phrase": "RECEIVE TRANSFER demo",
    }
    activate_request = next(
        event
        for event in events
        if event[:3] == ("peer", "POST", "/api/transfers/activate")
    )
    assert activate_request[3] == {
        "slug": "demo",
        **TRANSFER,
        "confirm_slug": "demo",
        "confirm_phrase": "ACTIVATE TRANSFER demo",
    }
    assert [event[0] for event in events[:4]] == [
        "stop",
        "quiesced",
        "backup",
        "quiesced",
    ]
    assert all(event[4] > 0 for event in events if event[0] == "peer")
    finalize_index = next(
        index for index, event in enumerate(events) if event[0] == "finalized"
    )
    receive_completion_index = max(
        index
        for index, event in enumerate(events)
        if event[:3] == ("peer", "GET", "/api/operations/receive-op")
    )
    activate_index = next(
        index
        for index, event in enumerate(events)
        if event[:3] == ("peer", "POST", "/api/transfers/activate")
    )
    assert receive_completion_index < finalize_index < activate_index
    assert events[finalize_index] == (
        "finalized",
        "demo",
        TRANSFER["project_id"],
        TRANSFER["destination_host_id"],
    )


def test_guided_transfer_stops_when_source_is_not_quiesced():
    events = []

    def assert_quiesced(slug, project_id):
        events.append(("quiesced", slug, project_id))
        raise RuntimeError("source runtime remains active")

    with pytest.raises(RuntimeError, match="source runtime remains active"):
        guided_transfer(
            "demo",
            C(),
            stop=lambda slug: events.append(("stop", slug)),
            backup=lambda slug: events.append(("backup", slug)),
            assert_quiesced=assert_quiesced,
            finalize_source=lambda *_: pytest.fail("source must not finalize"),
            peer_call=lambda *_: pytest.fail(
                "peer must not receive an active source"
            ),
            **TRANSFER,
        )

    assert events == [
        ("stop", "demo"),
        ("quiesced", "demo", TRANSFER["project_id"]),
    ]


def test_guided_transfer_rechecks_quiescence_after_backup_before_peer_receive():
    events = []
    checks = {"count": 0}

    def assert_quiesced(slug, project_id):
        checks["count"] += 1
        events.append(("quiesced", slug, project_id))
        if checks["count"] == 2:
            raise RuntimeError("source became active during backup")

    with pytest.raises(RuntimeError, match="source became active during backup"):
        guided_transfer(
            "demo",
            C(),
            stop=lambda slug: events.append(("stop", slug)),
            backup=lambda slug: events.append(("backup", slug)),
            assert_quiesced=assert_quiesced,
            finalize_source=lambda *_: pytest.fail("source must not finalize"),
            peer_call=lambda *_: pytest.fail(
                "peer must not receive an active source"
            ),
            **TRANSFER,
        )

    assert events == [
        ("stop", "demo"),
        ("quiesced", "demo", TRANSFER["project_id"]),
        ("backup", "demo"),
        ("quiesced", "demo", TRANSFER["project_id"]),
    ]


def test_guided_transfer_does_not_start_after_failed_receive_operation():
    events = []

    def peer(method, path, payload, timeout):
        events.append((method, path))
        if method == "POST":
            return _receipt("receive-op")
        return _record("receive-op", "failed")

    with pytest.raises(RuntimeError, match="Peer receive transfer operation failed"):
        _run_transfer(peer, events)

    assert ("POST", "/api/transfers/activate") not in events
    assert not any(event[0] == "finalized" for event in events)


def test_guided_transfer_does_not_activate_when_source_finalization_fails():
    events = []
    responses = {
        ("POST", "/api/transfers/receive"): deque([_receipt("receive-op")]),
        ("GET", "/api/operations/receive-op"): deque(
            [_record("receive-op", "completed")]
        ),
    }

    def peer(method, path, payload, timeout):
        events.append(("peer", method, path))
        return responses[(method, path)].popleft()

    def finalize_source(slug, project_id, destination_host_id):
        events.append(("finalize", slug, project_id, destination_host_id))
        raise RuntimeError("sensitive source-finalization detail")

    with pytest.raises(RuntimeError, match="Source transfer finalization failed") as raised:
        _run_transfer(peer, events, finalize_source=finalize_source)

    assert "sensitive source-finalization detail" not in str(raised.value)
    assert ("peer", "POST", "/api/transfers/activate") not in events


@pytest.mark.parametrize("state", ["failed", "interrupted"])
def test_guided_transfer_ends_after_unsuccessful_atomic_activation(state):
    events = []
    responses = {
        ("POST", "/api/transfers/receive"): deque([_receipt("receive-op")]),
        ("GET", "/api/operations/receive-op"): deque(
            [_record("receive-op", "completed")]
        ),
        ("POST", "/api/transfers/activate"): deque([_receipt("activate-op")]),
        ("GET", "/api/operations/activate-op"): deque(
            [_record("activate-op", state, error="sensitive activation detail")]
        ),
    }

    def peer(method, path, payload, timeout):
        events.append(("peer", method, path))
        return responses[(method, path)].popleft()

    with pytest.raises(
        RuntimeError, match=fr"Peer activate transfer operation {state}"
    ) as raised:
        _run_transfer(peer, events)

    assert "sensitive activation detail" not in str(raised.value)
    assert any(event[0] == "finalized" for event in events)


def test_guided_transfer_does_not_activate_after_locked_receive_operation():
    events = []

    def peer(method, path, payload, timeout):
        events.append((method, path))
        if method == "POST":
            return _receipt("receive-op")
        return _record(
            "receive-op", "failed", current_step="locked", error="operation_locked"
        )

    with pytest.raises(RuntimeError, match="Peer receive transfer operation is locked"):
        _run_transfer(peer, events)

    assert ("POST", "/api/transfers/activate") not in events


def test_guided_transfer_times_out_before_activation(monkeypatch):
    now = {"value": 0.0}
    monkeypatch.setattr(failover, "PEER_OPERATION_TIMEOUT_SECONDS", 0.25)
    monkeypatch.setattr(failover, "PEER_OPERATION_POLL_INTERVAL_SECONDS", 0.25)
    monkeypatch.setattr(failover.time, "monotonic", lambda: now["value"])
    monkeypatch.setattr(
        failover.time,
        "sleep",
        lambda seconds: now.__setitem__("value", now["value"] + seconds),
    )
    events = []

    def peer(method, path, payload, timeout):
        events.append((method, path))
        if method == "POST":
            return _receipt("receive-op")
        return _record("receive-op", "running")

    with pytest.raises(RuntimeError, match="Peer receive transfer operation timed out"):
        _run_transfer(peer, events)

    assert ("POST", "/api/transfers/activate") not in events


def test_guided_transfer_rejects_malformed_operation_receipt_before_activation():
    events = []

    def peer(method, path, payload, timeout):
        events.append((method, path))
        return {
            "ok": True,
            "accepted": True,
            "operation_id": "receive-op",
            "operation_url": "/api/operations/other-op",
        }

    with pytest.raises(
        RuntimeError, match="Peer receive transfer operation response was malformed"
    ):
        _run_transfer(peer, events)

    assert ("POST", "/api/transfers/receive") in events
    assert ("POST", "/api/transfers/activate") not in events

```


## FILE: source/tests/test_hardening11_red_blue.py

SHA256: c0639e0edc66abb29fdac71605866a0f1a488de357df153d743f825a2898546e | Bytes: 13557 | Git mode: 100644

```
from __future__ import annotations

import json
import stat
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest

from devfleet import auth, containers, core
from devfleet.analyzer import analyze_project, has_blockers
from devfleet.core import SETTINGS


def _compose_project(tmp_path: Path, body: str) -> Path:
    project = tmp_path / "red-compose"
    project.mkdir()
    (project / "compose.yaml").write_text(body, encoding="utf-8")
    return project


@pytest.mark.parametrize("profile", ["strict", "balanced", "fast"])
@pytest.mark.parametrize(
    ("body", "code"),
    [
        ("services:\n  app:\n    privileged: true\n", "docker.privileged"),
        ("services:\n  app:\n    use_api_socket: true\n", "compose.use-api-socket"),
        ("services:\n  app:\n    volumes_from: [base]\n", "compose.volumes-from"),
        ("services:\n  app:\n    provider: {type: evil}\n", "compose.provider"),
        ("services:\n  app:\n    post_start: [{command: whoami, privileged: true}]\n", "compose.post-start"),
        ("services:\n  app:\n    future_execution_field: true\n", "compose.unknown-field"),
    ],
)
def test_compose_red_attack_corpus_blocks_every_profile(tmp_path: Path, profile: str, body: str, code: str) -> None:
    findings = analyze_project(_compose_project(tmp_path, body), profile, force=True)
    assert has_blockers(findings)
    assert code in {item["code"] for item in findings}


def test_compose_extends_nested_and_host_root_bind_are_not_effective_model_gaps(tmp_path: Path) -> None:
    project = _compose_project(
        tmp_path,
        """services:
  app:
    extends:
      file: middle.yml
      service: middle
""",
    )
    (project / "middle.yml").write_text(
        """services:
  middle:
    extends:
      file: evil.yml
      service: inherited
""",
        encoding="utf-8",
    )
    (project / "evil.yml").write_text(
        """services:
  inherited:
    privileged: true
    network_mode: host
    volumes: ["/:/host"]
""",
        encoding="utf-8",
    )
    findings = analyze_project(project, "strict", force=True)
    codes = {item["code"] for item in findings}
    assert has_blockers(findings)
    assert "compose.extends" in codes
    assert "docker.privileged" not in codes or "compose.extends" in codes


def test_compose_include_escape_and_symlink_escape_are_blocked(tmp_path: Path) -> None:
    project = _compose_project(tmp_path, "include:\n  - ../outside.yml\nservices: {}\n")
    findings = analyze_project(project, "strict", force=True)
    assert has_blockers(findings)
    assert "compose.include" in {item["code"] for item in findings}
    assert "compose.path-reference" in {item["code"] for item in findings}

    outside = tmp_path / "outside.yml"
    outside.write_text("services: {}\n", encoding="utf-8")
    link = project / "evil.yml"
    try:
        link.symlink_to(outside)
    except OSError:
        pytest.skip("symbolic-link creation unavailable")
    (project / "compose.yaml").write_text("""services:
  app:
    extends: {file: evil.yml, service: x}
""", encoding="utf-8")
    findings = analyze_project(project, "strict", force=True)
    assert {"compose.path-escape", "project.symlink-escape"} & {item["code"] for item in findings}


@pytest.mark.parametrize("argument", [
    "--privileged", "--network=host", "--network", "host", "--pid=host", "--pid", "host",
    "--ipc", "--uts", "--userns=host", "--volume=/:/host", "-v", "/:/host", "--mount", "type=bind,src=/,dst=/host",
    "--device=/dev/kvm", "--cap-add=SYS_ADMIN", "--security-opt", "seccomp=unconfined", "--env-file=/tmp/x",
])
@pytest.mark.parametrize("profile", ["strict", "balanced", "fast"])
def test_devcontainer_structured_runargs_attack_corpus_blocks(tmp_path: Path, argument: str, profile: str) -> None:
    project = tmp_path / "devcontainer"
    (project / ".devcontainer").mkdir(parents=True)
    (project / ".devcontainer/devcontainer.json").write_text(json.dumps({"image": "alpine:3.20", "runArgs": [argument]}), encoding="utf-8")
    findings = analyze_project(project, profile, force=True)
    assert has_blockers(findings)
    assert "devcontainer.run-args" in {item["code"] for item in findings} or "devcontainer.run-args-dangerous" in {item["code"] for item in findings}


def test_devcontainer_jsonc_known_good_and_features_fail_closed(tmp_path: Path) -> None:
    project = tmp_path / "devcontainer"
    (project / ".devcontainer").mkdir(parents=True)
    config = """{
      // JSONC comments are part of the Dev Container format.
      "name": "safe",
      "image": "alpine:3.20",
      "remoteUser": "nobody",
    }
    """
    path = project / ".devcontainer/devcontainer.json"
    path.write_text(config, encoding="utf-8")
    findings = analyze_project(project, "strict", force=True)
    assert "devcontainer.json.invalid" not in {item["code"] for item in findings}
    assert not has_blockers(findings)
    path.write_text('{"image":"alpine:3.20","features":{"ghcr.io/devcontainers/features/node:1":{}}}', encoding="utf-8")
    findings = analyze_project(project, "strict", force=True)
    assert "devcontainer.features-unsupported" in {item["code"] for item in findings}


def test_analyzer_cache_invalidates_when_only_transitive_compose_file_changes(tmp_path: Path) -> None:
    project = _compose_project(tmp_path, """services:
  app:
    extends: {file: evil.yml, service: inherited}
""")
    inherited = project / "evil.yml"
    inherited.write_text("services:\n  inherited:\n    image: alpine:3.20\n", encoding="utf-8")
    analyze_project(project, "strict", force=True)
    cache = project / ".devfleet/runtime/analyzer-cache.json"
    first = cache.read_text(encoding="utf-8")
    inherited.write_text("services:\n  inherited:\n    privileged: true\n", encoding="utf-8")
    analyze_project(project, "strict")
    second = cache.read_text(encoding="utf-8")
    assert first != second


CONTAINER_ID = "a" * 64
FOREIGN_ID = "b" * 64
PROJECT_ID = "12345678-1234-1234-1234-123456789abc"


def _owned_project(tmp_path: Path) -> None:
    project = tmp_path / "owned-app"
    (project / ".devfleet").mkdir(parents=True)
    (project / ".devfleet/project.json").write_text(json.dumps({
        "managed_by": "devfleet", "project_id": PROJECT_ID, "slug": "owned-app", "runtime_provider": "docker-compose",
        "runtime_id": "df_owned_app", "deployment_id": "deployment-123", "host_id": "test-node",
    }), encoding="utf-8")


def _owned_labels() -> dict[str, str]:
    return {
        "io.devfleet.managed-by": "devfleet", "io.devfleet.project-id": PROJECT_ID, "io.devfleet.project-slug": "owned-app",
        "io.devfleet.runtime-id": "df_owned_app", "io.devfleet.deployment-id": "deployment-123", "io.devfleet.host-id": "test-node",
        "com.docker.compose.project": "df_owned_app", "com.docker.compose.service": "app",
    }


def _inspect(container_id: str, labels: dict[str, str], name: str) -> dict:
    return {"Id": container_id, "Name": f"/{name}", "Config": {"Labels": labels}, "Secret": "only-for-authorized-read"}


def test_container_reads_filter_foreign_and_authorize_inspect_logs(monkeypatch, tmp_path: Path) -> None:
    _owned_project(tmp_path)
    monkeypatch.setattr(containers, "SETTINGS", replace(SETTINGS, workspaces=tmp_path, node_name="test-node", deployment_id="deployment-123"))
    owned = _inspect(CONTAINER_ID, _owned_labels(), "owned-app")
    foreign = _inspect(FOREIGN_ID, {"io.devfleet.managed-by": "other"}, "foreign")
    calls: list[list[str]] = []

    def fake_run(args, **_kwargs):
        calls.append(list(args))
        if args[:2] == ["docker", "ps"]:
            return SimpleNamespace(returncode=0, stdout="\n".join(json.dumps(x) for x in [
                {"ID": CONTAINER_ID, "Names": "owned-app", "Image": "safe", "State": "running"},
                {"ID": FOREIGN_ID, "Names": "foreign", "Image": "evil", "State": "running"},
            ]), stderr="")
        if args[:2] == ["docker", "stats"]:
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if args[:2] == ["docker", "inspect"]:
            value = owned if args[-1] in {CONTAINER_ID, "owned-app"} else foreign
            return SimpleNamespace(returncode=0, stdout=json.dumps([value]), stderr="")
        if args[:2] == ["docker", "logs"]:
            return SimpleNamespace(returncode=0, stdout="owned log", stderr="")
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(containers, "run", fake_run)
    listed = containers.list_containers()
    assert [item["id"] for item in listed] == [CONTAINER_ID]
    assert containers.inspect_container("owned-app")["Id"] == CONTAINER_ID
    assert containers.container_logs("owned-app") == "owned log"
    with pytest.raises(ValueError, match="ownership"):
        containers.inspect_container("foreign")
    with pytest.raises(ValueError, match="ownership"):
        containers.container_logs("foreign")
    assert not any(call[:2] == ["docker", "logs"] and call[-1] == FOREIGN_ID for call in calls)


def test_container_same_name_replacement_and_partial_labels_fail_closed(monkeypatch, tmp_path: Path) -> None:
    _owned_project(tmp_path)
    monkeypatch.setattr(containers, "SETTINGS", replace(SETTINGS, workspaces=tmp_path, node_name="test-node", deployment_id="deployment-123"))
    calls = {"inspect": 0}

    def fake_run(args, **_kwargs):
        if args[:2] == ["docker", "inspect"]:
            calls["inspect"] += 1
            value = _inspect(CONTAINER_ID, _owned_labels(), "same-name") if calls["inspect"] == 1 else _inspect(FOREIGN_ID, {"io.devfleet.managed-by": "other"}, "same-name")
            return SimpleNamespace(returncode=0, stdout=json.dumps([value]), stderr="")
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(containers, "run", fake_run)
    with pytest.raises(ValueError, match="ownership"):
        containers.inspect_container("same-name")


def test_rootless_endpoint_preserves_explicit_two_user_socket(monkeypatch) -> None:
    settings = replace(SETTINGS, docker_mode="rootless", docker_host="unix:///run/user/1000/docker.sock", docker_owner_uid=1000)
    monkeypatch.setattr(core, "SETTINGS", settings)
    monkeypatch.setattr(core.os, "lstat", lambda _path: SimpleNamespace(st_mode=stat.S_IFSOCK, st_uid=1000))
    captured = {}

    def fake_subprocess(_cmd, **kwargs):
        captured.update(kwargs)
        return SimpleNamespace(returncode=0, stdout="ok", stderr="")

    monkeypatch.setattr(core.subprocess, "run", fake_subprocess)
    monkeypatch.setenv("DOCKER_HOST", "unix:///run/user/1000/docker.sock")
    core.run(["docker", "info"], check=False)
    assert captured["env"]["DOCKER_HOST"] == "unix:///run/user/1000/docker.sock"


@pytest.mark.parametrize("host", ["unix:///run/user/4242/docker.sock", "tcp://127.0.0.1:2375", "", "unix:///run/user/1000/not-docker.sock"])
def test_rootless_endpoint_rejects_wrong_identity_or_shape(monkeypatch, host: str) -> None:
    settings = replace(SETTINGS, docker_mode="rootless", docker_host=host, docker_owner_uid=1000)
    monkeypatch.setattr(core, "SETTINGS", settings)
    monkeypatch.setattr(core.os, "lstat", lambda _path: SimpleNamespace(st_mode=stat.S_IFSOCK, st_uid=1000))
    with pytest.raises(RuntimeError):
        core._validate_rootless_docker_host(host)


def test_rootless_deployment_contract_is_explicit() -> None:
    unit = Path("source/app/systemd/devfleet.service").read_text(encoding="utf-8")
    core_text = Path("source/app/devfleet/core.py").read_text(encoding="utf-8")
    assert "SupplementaryGroups=devrunner" in unit
    assert "Environment=DOCKER_HOST=unix:///run/user/__DEVRUNNER_UID__/docker.sock" in unit
    assert "os.getuid" not in core_text
    assert "_validate_rootless_docker_host" in core_text


def test_rootless_docker_acl_is_reapplied_after_each_service_start() -> None:
    bootstrap = Path("source/linux/bootstrap-compute.sh").read_text(encoding="utf-8")
    drop_in = "/home/devrunner/.config/systemd/user/docker.service.d/devfleet-control-acl.conf"
    daemon_reload = (
        "sudo -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user daemon-reload"
    )
    enable_docker = (
        "sudo -u devrunner env HOME=/home/devrunner XDG_RUNTIME_DIR=/run/user/$uid "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user enable --now docker"
    )

    assert drop_in in bootstrap
    assert "ExecStartPost=/usr/bin/setfacl -m u:devfleet-control:rx %t" in bootstrap
    assert "ExecStartPost=/usr/bin/setfacl -m u:devfleet-control:rw %t/docker.sock" in bootstrap
    assert daemon_reload in bootstrap
    assert bootstrap.index(daemon_reload) < bootstrap.index(enable_docker)


def test_credential_comparison_count_is_constant(monkeypatch) -> None:
    monkeypatch.setattr(auth, "SETTINGS", replace(SETTINGS, admin_user="alice", admin_password="secret"))
    original = auth.hmac.compare_digest
    counts: list[int] = []
    calls = []

    def counted(left, right):
        calls.append((left, right))
        return original(left, right)

    monkeypatch.setattr(auth.hmac, "compare_digest", counted)
    for user, password in [("wrong", "wrong"), ("alice", "wrong"), ("wrong", "secret"), ("alice", "secret"), ("", "")]:
        calls.clear()
        auth.valid_credentials(user, password, source="red-blue-test")
        counts.append(len(calls))
    assert counts == [2, 2, 2, 2, 2]

```


## FILE: source/tests/test_hardening7_boundaries.py

SHA256: c76ba7108747796dc74b7ff6c4d026d5be2672dd2b4e99d14fc6f0f49bcbd8bb | Bytes: 8255 | Git mode: 100644

```
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json
import re

import yaml


ROOT = Path(__file__).parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_linux_bootstrap_has_stdin_only_secret_transport_and_separated_identities():
    bootstrap = read("linux/bootstrap-compute.sh")
    input_helper = read("linux/bootstrap-input.sh")
    service = read("app/systemd/devfleet.service")
    backup = read("app/systemd/devfleet-backup.service")
    assert "--secrets-stdin)" in bootstrap
    assert "devfleet_capture_json_stdin" in bootstrap
    assert "timeout --foreground --kill-after=5s" in input_helper
    assert "Refusing legacy plaintext node-secrets.json input" in bootstrap
    assert 'SECRETS_SOURCE="${PAYLOAD}/node-secrets.json"' not in bootstrap
    assert "User=devfleet-control" in service
    assert "Group=devfleet-control" in service
    assert "User=devfleet-backup" in backup
    assert "Group=devfleet-backup" in backup
    assert "chown root:devfleet-control /etc/devfleet/secrets.env" in bootstrap
    assert "chmod 0640 /etc/devfleet/secrets.env" in bootstrap
    assert "NOPASSWD:ALL" not in bootstrap
    assert "sudoers.d/devfleet-devrunner" in bootstrap


def test_windows_provisioning_never_writes_node_secret_file_or_passes_secret_argv():
    provision = read("windows/02-Provision-ComputeNode.ps1")
    common = read("windows/DevFleet.Common.psm1")
    assert "node-secrets.json" not in provision
    assert "New-DevFleetBootstrapBoundary" in provision
    assert "--secrets-stdin" in common
    assert ".extractionCommand" in provision
    assert ".bootstrapCommand" in provision
    assert "-StandardInputText" in provision
    assert "RedirectStandardInput" in common
    assert "-p$password" not in common
    assert "DFENV001" in common
    assert "AesGcm" in common


def test_live_vm_identity_is_guest_bound_and_stopped_operations_fail_closed():
    agent = read("windows/DevFleet-HostAgent.ps1")
    assert "project-runtime.json" in agent
    for field in ("managed_by", "project_id", "slug", "runtime_id", "host_id", "provisioning_attempt_id"):
        assert f"runtimeMeta.{field}" in agent
    assert "AllowStoppedTransition" in agent
    assert "Operation -eq 'start'" in agent
    assert "groups: [docker, sudo]" not in read("cloud-init/compute.yaml")
    assert "NOPASSWD:ALL" not in agent


def test_cleanup_is_postcondition_and_transaction_bound():
    lifecycle = read("../installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs")
    services = read("../installer-source/DevFleet.Setup/Services/InstallerServices.cs")
    assert "InstallationGeneration" in lifecycle
    assert "PayloadFingerprint" in lifecycle
    assert "Owned registry entry remains after cleanup" in lifecycle
    assert "Owned shortcut remains after cleanup" in lifecycle
    assert "Owned file remains after cleanup" in services
    assert "Owned scheduled task remains after cleanup" in lifecycle
    assert "cleanup-history" in lifecycle


def test_uac_does_not_stage_before_elevation_and_vscode_is_trusted():
    main = read("../installer-source/DevFleet.Setup/MainWindow.xaml.cs")
    app = read("../installer-source/DevFleet.Setup/App.xaml.cs")
    lifecycle = read("../installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs")
    assert "elevation-check" not in main
    assert "TrustedExecutableResolver.VsCodePath()" in app
    assert "UseShellExecute = false" in app
    assert "ArgumentList.Add" in app
    assert "Microsoft VS Code" in lifecycle


def test_safety_policy_restore_journal_compose_reanalysis_and_frontend_terminal_states():
    projects = read("app/devfleet/projects.py")
    restore = read("app/devfleet/workspace_archives.py")
    operations = read("app/devfleet/operations.py")
    frontend = read("app/static/app.js")
    assert "FINGERPRINT_POLICY_VERSION" in projects
    assert "fingerprint_policy" in projects
    assert "_assert_current_compose_safety" in projects
    assert "force=True" in projects
    for phase in ("PREPARED", "OLD_MOVED_TO_ROLLBACK", "NEW_PROMOTED", "POSTCHECK_PASSED", "COMMITTED"):
        assert phase in restore
    assert "BoundedSemaphore" in operations
    assert "queued_deadline_at" in operations
    for state in ("completed", "failed", "cancelled", "interrupted"):
        assert state in frontend


def test_yaml_generation_uses_rejecting_scalar_encoders():
    common = read("windows/DevFleet.Common.psm1")
    provision = read("windows/02-Provision-ComputeNode.ps1")
    vault = read("windows/03-Provision-Vault.ps1")
    assert "ConvertTo-YamlSingleQuotedScalar" in common
    assert "ConvertTo-ShellSingleQuotedScalar" in common
    assert "ConvertTo-YamlSingleQuotedScalar" in provision
    assert "ConvertTo-ShellSingleQuotedScalar" in provision
    assert "ConvertTo-YamlSingleQuotedScalar" in vault


def test_fresh_multipass_launch_has_one_bounded_exact_readiness_recovery():
    common = read("windows/DevFleet.Common.psm1")
    compute = read("windows/02-Provision-ComputeNode.ps1")
    vault = read("windows/03-Provision-Vault.ps1")
    assert "function Invoke-MultipassLaunchWithReadinessRecovery" in common
    assert "--timeout" in common
    assert "Fresh Multipass launch recovery refused existing instance" in common
    assert "multipass-stop-start" in common
    assert "Wait-MultipassReady -Name $InstanceName" in common
    for provisioner in (compute, vault):
        assert "Invoke-MultipassLaunchWithReadinessRecovery" in provisioner
        assert "-OnInstanceEstablished" in provisioner
        assert "-DeadlineUtc" in provisioner
        assert "$launchDeadline=[datetime]::MinValue" in provisioner
        assert "-DeadlineUtc $launchDeadline" in provisioner
        assert not re.search(r"-DeadlineUtc\s+\(if\s*\(", provisioner)


def test_fresh_multipass_launch_retries_inventory_with_the_existing_deadline():
    common = read("windows/DevFleet.Common.psm1")
    assert "function Invoke-MultipassInventoryWithBoundedRetry" in common
    assert "Invoke-MultipassInventoryWithBoundedRetry -InventoryScript $inventory" in common
    assert "DeadlineUtc" in common
    assert "inventory retry exhausted" in common
    assert "$after = @(&$inventory 60" not in common


def test_cloud_init_write_file_permissions_are_explicit_schema_strings():
    expected_0644_counts = {"cloud-init/compute.yaml": 3, "cloud-init/vault.yaml": 2}
    expected_total_counts = {"cloud-init/compute.yaml": 3, "cloud-init/vault.yaml": 3}
    for relative, expected_0644_count in expected_0644_counts.items():
        source = read(relative)
        assert source.count("permissions: !!str 0644") == expected_0644_count
        assert not re.search(r"(?m)^\s+permissions:\s+(?!!!str\b)\S+", source)

        document = yaml.safe_load(source)
        permissions = [entry["permissions"] for entry in document["write_files"]]
        assert len(permissions) == expected_total_counts[relative]
        assert all(isinstance(mode, str) and re.fullmatch(r"0[0-7]{3}", mode) for mode in permissions)


def test_project_metadata_transaction_preserves_concurrent_fields(tmp_path):
    from devfleet.projects import project_metadata_transaction

    project = tmp_path / "transaction-project"
    (project / ".devfleet").mkdir(parents=True)
    metadata = {
        "schema_version": 3,
        "managed_by": "devfleet",
        "slug": project.name,
        "identity": project.name,
        "project_id": "12345678-1234-1234-1234-123456789012",
        "runtime_provider": "docker-compose",
        "runtime_id": "",
        "host_id": "test-node",
        "health_status": "unknown",
        "lifecycle_status": "ready",
    }
    (project / ".devfleet/project.json").write_text(json.dumps(metadata), encoding="utf-8")

    def write_field(name, value):
        with project_metadata_transaction(project) as current:
            current[name] = value

    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda item: write_field(*item), (("field_a", "a"), ("field_b", "b"))))
    result = json.loads((project / ".devfleet/project.json").read_text(encoding="utf-8"))
    assert result["field_a"] == "a"
    assert result["field_b"] == "b"

```


## FILE: source/tests/test_hardening8_api_serialization.py

SHA256: 6af8731cc3e3d84adf2d355de336e1adf60780f5072dee5ac7b998124532ec29 | Bytes: 7410 | Git mode: 100644

```
import json
import threading
import time
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient

from devfleet import main, operations


def _project(tmp_path, slug="demo"):
    project = tmp_path / slug
    project.mkdir()
    return project


def _route_state(monkeypatch, tmp_path):
    project = _project(tmp_path)
    monkeypatch.setattr(main, "SETTINGS", replace(main.SETTINGS, workspaces=tmp_path))
    metadata = {
        "schema_version": 3,
        "managed_by": "devfleet",
        "project_id": "12345678-1234-1234-1234-123456789abc",
        "slug": "demo",
        "runtime_id": "df_demo",
        "host_id": "test-node",
        "runtime_provider": "docker-compose",
    }
    (project / ".devfleet").mkdir()
    (project / ".devfleet/project.json").write_text(
        json.dumps(metadata), encoding="utf-8"
    )
    monkeypatch.setattr(main, "load_meta", lambda _project: metadata)
    monkeypatch.setattr(main, "project_capabilities", lambda *_args: {"can_run_runtime_action": True, "status_reason": ""})
    return metadata


def test_api_mutator_is_accepted_by_durable_serializer_and_never_runs_inline(monkeypatch, tmp_path):
    metadata = _route_state(monkeypatch, tmp_path)
    submissions = []
    monkeypatch.setattr(main, "stop_project", lambda *_: pytest.fail("API mutator ran inline"))
    monkeypatch.setattr(main, "submit_operation", lambda *args, **kwargs: submissions.append((args, kwargs)) or "stop-op-1")

    response = TestClient(main.app).post(
        "/api/projects/demo/stop",
        headers={"X-DevFleet-Token": "test-token", "X-Idempotency-Key": "client-request-1"},
        json={},
    )

    assert response.status_code == 202
    assert response.json() == {
        "ok": True,
        "accepted": True,
        "operation_id": "stop-op-1",
        "operation_url": "/api/operations/stop-op-1",
    }
    args, kwargs = submissions[0]
    assert args[:2] == ("stop", "demo")
    assert kwargs["project_id"] == metadata["project_id"]
    assert kwargs["runtime_id"] == metadata["runtime_id"]
    assert kwargs["idempotency_key"].endswith(":client-request-1")


def test_read_only_api_actions_remain_synchronous(monkeypatch, tmp_path):
    _route_state(monkeypatch, tmp_path)
    monkeypatch.setattr(main, "inspect_runtime", lambda slug: {"slug": slug, "read_only": True})
    monkeypatch.setattr(main, "submit_operation", lambda *_args, **_kwargs: pytest.fail("read-only action was queued"))

    response = TestClient(main.app).post(
        "/api/projects/demo/inspect",
        headers={"X-DevFleet-Token": "test-token"},
        json={},
    )

    assert response.status_code == 200
    assert response.json() == {"ok": True, "output": {"slug": "demo", "read_only": True}}


def test_api_project_creation_uses_the_same_durable_admission(monkeypatch):
    submissions = []
    monkeypatch.setattr(main, "create_project", lambda **_kwargs: pytest.fail("API create ran inline"))
    monkeypatch.setattr(main, "submit_operation", lambda *args, **kwargs: submissions.append((args, kwargs)) or "create-op-1")

    response = TestClient(main.app).post(
        "/api/projects/create",
        headers={"X-DevFleet-Token": "test-token"},
        json={"slug": "new-app", "idempotency_key": "create-request-1"},
    )

    assert response.status_code == 202
    assert response.json()["operation_id"] == "create-op-1"
    assert submissions[0][0][:2] == ("create", "new-app")
    assert submissions[0][1]["idempotency_key"] == "project-create:new-app:create-request-1"


def test_action_classification_is_explicit_and_closed():
    assert main.PROJECT_READ_ONLY_ACTIONS == {"inspect", "runtime-health", "logs"}
    assert {
        "start", "stop", "restart", "rebuild", "backup", "bootstrap", "health", "test",
        "codexpro", "quarantine", "destroy", "restore-vault", "restore-backup",
        "analyze-force", "reconcile-failed-migration",
    } == main.PROJECT_MUTATING_ACTIONS
    assert main.PROJECT_ACTIONS == main.PROJECT_READ_ONLY_ACTIONS | main.PROJECT_MUTATING_ACTIONS


def _wait_terminal(operation_id, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        record = operations.get_operation(operation_id)
        if record["state"] in {"completed", "failed", "cancelled", "interrupted"}:
            return record
        time.sleep(0.01)
    raise AssertionError(f"operation {operation_id} did not become terminal")


@pytest.mark.parametrize(
    ("first_kind", "second_kind"),
    [("api-start", "api-stop"), ("api-destroy", "ui-start"), ("api-backup", "ui-start"), ("api-rebuild", "api-stop")],
)
def test_same_project_mutators_have_maximum_concurrency_one(monkeypatch, tmp_path, first_kind, second_kind):
    monkeypatch.setattr(operations, "SETTINGS", replace(operations.SETTINGS, runtime_root=tmp_path))
    started = threading.Event()
    release = threading.Event()
    active = 0
    maximum = 0
    guard = threading.Lock()

    def first(_ctx):
        nonlocal active, maximum
        with guard:
            active += 1
            maximum = max(maximum, active)
        started.set()
        release.wait(2)
        with guard:
            active -= 1
        return "first"

    def second(_ctx):
        nonlocal active, maximum
        with guard:
            active += 1
            maximum = max(maximum, active)
            active -= 1
        return "second"

    first_id = operations.submit_operation(first_kind, "demo", first)
    assert started.wait(1)
    second_id = operations.submit_operation(second_kind, "demo", second)
    release.set()
    assert _wait_terminal(first_id)["state"] == "completed"
    assert _wait_terminal(second_id)["state"] in {"completed", "failed"}
    assert maximum == 1


def test_cancelled_queued_operation_never_executes(monkeypatch, tmp_path):
    monkeypatch.setattr(operations, "SETTINGS", replace(operations.SETTINGS, runtime_root=tmp_path))
    queued = []

    class DeferredExecutor:
        def submit(self, callback):
            queued.append(callback)

    monkeypatch.setattr(operations, "_EXECUTOR", DeferredExecutor())
    ran = []
    operation_id = operations.submit_operation("api-start", "demo", lambda _ctx: ran.append(True))
    operations.update_operation(operation_id, state="cancelled", completed_at=operations.now_iso())

    queued[0]()

    assert ran == []
    assert operations.get_operation(operation_id)["state"] == "cancelled"


def test_operation_admission_backpressure_fails_closed(monkeypatch, tmp_path):
    monkeypatch.setattr(operations, "SETTINGS", replace(operations.SETTINGS, runtime_root=tmp_path))
    monkeypatch.setattr(operations, "_ADMISSION", threading.BoundedSemaphore(1))
    queued = []

    class DeferredExecutor:
        def submit(self, callback):
            queued.append(callback)

    monkeypatch.setattr(operations, "_EXECUTOR", DeferredExecutor())
    first = operations.submit_operation("api-start", "first", lambda _ctx: "held")
    second = operations.submit_operation("api-start", "second", lambda _ctx: pytest.fail("backpressured work ran"))

    assert operations.get_operation(first)["state"] == "queued"
    blocked = operations.get_operation(second)
    assert blocked["state"] == "failed"
    assert blocked["error"] == "operation_capacity"
    operations.update_operation(first, state="cancelled", completed_at=operations.now_iso())
    queued[0]()

```


## FILE: source/tests/test_hardening8_container_ownership.py

SHA256: a69ff2930191b209eff2bc8d772d2bcc824fa314f8fb54b464b4b7de975a9af2 | Bytes: 8949 | Git mode: 100644

```
import json
import contextlib
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from devfleet import containers, projects
from devfleet.core import SETTINGS


CONTAINER_ID = "a" * 64
PROJECT_ID = "12345678-1234-1234-1234-123456789abc"


def _project(tmp_path: Path, *, slug: str = "owned-app") -> dict:
    project = tmp_path / slug
    (project / ".devfleet").mkdir(parents=True)
    metadata = {
        "schema_version": 5,
        "managed_by": "devfleet",
        "project_id": PROJECT_ID,
        "slug": slug,
        "runtime_provider": "docker-compose",
        "runtime_id": "df_owned_app",
        "deployment_id": "deployment-123",
        "host_id": "test-node",
    }
    (project / ".devfleet/project.json").write_text(json.dumps(metadata), encoding="utf-8")
    return metadata


def _labels(**changes) -> dict[str, str]:
    labels = {
        "io.devfleet.managed-by": "devfleet",
        "io.devfleet.project-id": PROJECT_ID,
        "io.devfleet.project-slug": "owned-app",
        "io.devfleet.runtime-id": "df_owned_app",
        "io.devfleet.deployment-id": "deployment-123",
        "io.devfleet.host-id": "test-node",
        "com.docker.compose.project": "df_owned_app",
        "com.docker.compose.service": "app",
    }
    labels.update(changes)
    return labels


def _inspect(container_id: str = CONTAINER_ID, labels: dict | None = None, name: str = "/renamed-app") -> dict:
    return {"Id": container_id, "Name": name, "Config": {"Labels": labels if labels is not None else _labels()}}


def _runner(first: dict, second: dict | None = None):
    calls: list[list[str]] = []

    def fake_run(args, **_kwargs):
        calls.append(list(args))
        if args[:2] == ["docker", "inspect"]:
            value = first if len([c for c in calls if c[:2] == ["docker", "inspect"]]) == 1 else second
            if value is None:
                return SimpleNamespace(returncode=1, stdout="", stderr="No such container")
            return SimpleNamespace(returncode=0, stdout=json.dumps([value]), stderr="")
        return SimpleNamespace(returncode=0, stdout=args[-1], stderr="")

    return fake_run, calls


def _configure(monkeypatch, tmp_path):
    _project(tmp_path)
    settings = replace(
        SETTINGS,
        workspaces=tmp_path,
        runtime_root=tmp_path / "runtime",
        node_name="test-node",
        deployment_id="deployment-123",
    )
    monkeypatch.setattr(containers, "SETTINGS", settings)
    monkeypatch.setattr(projects, "SETTINGS", settings)


def _write_pending_marker(tmp_path: Path) -> None:
    project = tmp_path / "owned-app"
    marker = projects._transfer_pending_marker_path(project)
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "workspace_path": str(project.absolute()),
                "workspace_name": "owned-app",
                "project_id": PROJECT_ID,
                "deployment_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                "source_host_id": "devfleet-primary",
                "destination_host_id": "test-node",
                "state": "pending-source-finalization",
                "created_at": "2026-09-16T00:00:00Z",
            }
        ),
        encoding="utf-8",
    )


@pytest.mark.parametrize(
    "labels",
    [
        {},
        {"io.devfleet.managed-by": "devfleet"},
        _labels(**{"io.devfleet.project-id": "22345678-1234-1234-1234-123456789abc"}),
        _labels(**{"io.devfleet.deployment-id": "other-deployment"}),
        _labels(**{"com.docker.compose.project": "foreign-compose"}),
    ],
)
def test_foreign_partial_and_mismatched_containers_are_preserved(monkeypatch, tmp_path, labels):
    _configure(monkeypatch, tmp_path)
    fake_run, calls = _runner(_inspect(labels=labels))
    monkeypatch.setattr(containers, "run", fake_run)

    with pytest.raises(ValueError, match="ownership"):
        containers.container_action("foreign-db", "remove")

    assert not any(call[:2] == ["docker", "rm"] for call in calls)


@pytest.mark.parametrize(
    ("action", "docker_command"),
    [("start", "start"), ("stop", "stop"), ("restart", "restart"), ("pause", "pause"), ("unpause", "unpause"), ("remove", "rm")],
)
def test_every_legitimate_action_mutates_verified_immutable_id(monkeypatch, tmp_path, action, docker_command):
    _configure(monkeypatch, tmp_