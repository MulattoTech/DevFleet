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
