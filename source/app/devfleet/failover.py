from __future__ import annotations

import re
import time
from typing import Any, Callable, Protocol


PEER_OPERATION_TIMEOUT_SECONDS = 3700.0
PEER_OPERATION_POLL_INTERVAL_SECONDS = 0.5
PEER_REQUEST_TIMEOUT_SECONDS = 30.0
_OPERATION_ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z")
_PROJECT_ID_RE = re.compile(r"[0-9a-fA-F-]{16,128}\Z")
_TRANSFER_IDENTIFIER_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z")


class Progress(Protocol):
    def update(self, progress: int, message: str) -> None: ...


PeerCall = Callable[[str, str, dict[str, Any] | None, float], Any]


def _operation_endpoint(receipt: Any, phase: str) -> tuple[str, str]:
    """Accept only the native 202 receipt shape and its exact operation endpoint."""
    if (
        not isinstance(receipt, dict)
        or receipt.get("ok") is not True
        or receipt.get("accepted") is not True
    ):
        raise RuntimeError(f"Peer {phase} operation response was malformed.")
    operation_id = receipt.get("operation_id")
    if not isinstance(operation_id, str) or not _OPERATION_ID_RE.fullmatch(operation_id):
        raise RuntimeError(f"Peer {phase} operation response was malformed.")
    operation_url = receipt.get("operation_url")
    if operation_url != f"/api/operations/{operation_id}":
        raise RuntimeError(f"Peer {phase} operation response was malformed.")
    return operation_id, operation_url


def _remaining_request_timeout(deadline: float, phase: str) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise RuntimeError(f"Peer {phase} operation timed out.")
    return min(PEER_REQUEST_TIMEOUT_SECONDS, remaining)


def _await_peer_operation(
    receipt: Any,
    phase: str,
    peer_call: PeerCall,
    deadline: float,
) -> None:
    operation_id, operation_url = _operation_endpoint(receipt, phase)
    while True:
        request_timeout = _remaining_request_timeout(deadline, phase)
        record = peer_call("GET", operation_url, None, request_timeout)
        if not isinstance(record, dict):
            raise RuntimeError(f"Peer {phase} operation response was malformed.")
        record_ids = [record.get("operation_id"), record.get("id")]
        if operation_id not in record_ids or any(
            value is not None and value != operation_id for value in record_ids
        ):
            raise RuntimeError(f"Peer {phase} operation response was malformed.")
        state = record.get("state")
        if not isinstance(state, str):
            raise RuntimeError(f"Peer {phase} operation response was malformed.")
        if (
            state == "locked"
            or record.get("current_step") == "locked"
            or record.get("error") == "operation_locked"
        ):
            raise RuntimeError(f"Peer {phase} operation is locked.")
        if state == "completed":
            return
        if state in {"failed", "interrupted", "cancelled"}:
            raise RuntimeError(f"Peer {phase} operation {state}.")
        if state not in {"queued", "running"}:
            raise RuntimeError(f"Peer {phase} operation response was malformed.")
        remaining = _remaining_request_timeout(deadline, phase)
        time.sleep(min(PEER_OPERATION_POLL_INTERVAL_SECONDS, remaining))


def _submit_and_await_peer_operation(
    method: str,
    path: str,
    payload: dict[str, Any] | None,
    phase: str,
    peer_call: PeerCall,
) -> None:
    deadline = time.monotonic() + PEER_OPERATION_TIMEOUT_SECONDS
    receipt = peer_call(
        method, path, payload, _remaining_request_timeout(deadline, phase)
    )
    _await_peer_operation(receipt, phase, peer_call, deadline)


def _validated_transfer_identity(
    project_id: str,
    deployment_id: str,
    source_host_id: str,
    destination_host_id: str,
) -> tuple[str, str, str, str]:
    if not isinstance(project_id, str) or not _PROJECT_ID_RE.fullmatch(project_id):
        raise ValueError("Ownership transfer requires a valid persisted project ID.")
    if not isinstance(deployment_id, str) or not _TRANSFER_IDENTIFIER_RE.fullmatch(
        deployment_id
    ):
        raise ValueError("Ownership transfer requires a valid deployment ID.")
    if not isinstance(source_host_id, str) or not _TRANSFER_IDENTIFIER_RE.fullmatch(
        source_host_id
    ):
        raise ValueError("Ownership transfer requires a valid source host ID.")
    if not isinstance(destination_host_id, str) or not _TRANSFER_IDENTIFIER_RE.fullmatch(
        destination_host_id
    ):
        raise ValueError("Ownership transfer requires a valid destination host ID.")
    if source_host_id.casefold() == destination_host_id.casefold():
        raise ValueError("Ownership transfer requires a distinct destination host ID.")
    return project_id, deployment_id, source_host_id, destination_host_id


def guided_transfer(
    slug: str,
    ctx: Progress,
    *,
    stop: Callable[[str], Any],
    backup: Callable[[str], Any],
    assert_quiesced: Callable[[str, str], Any],
    project_id: str,
    deployment_id: str,
    source_host_id: str,
    destination_host_id: str,
    finalize_source: Callable[[str, str, str], Any],
    peer_call: PeerCall,
) -> str:
    (
        project_id,
        deployment_id,
        source_host_id,
        destination_host_id,
    ) = _validated_transfer_identity(
        project_id, deployment_id, source_host_id, destination_host_id
    )

    def transfer_payload(confirm_phrase: str) -> dict[str, Any]:
        return {
            "slug": slug,
            "project_id": project_id,
            "deployment_id": deployment_id,
            "source_host_id": source_host_id,
            "destination_host_id": destination_host_id,
            "confirm_slug": slug,
            "confirm_phrase": confirm_phrase,
        }

    ctx.update(5, "Stopping local project")
    stop(slug)
    assert_quiesced(slug, project_id)
    ctx.update(20, "Creating and verifying append-only backup")
    backup(slug)
    assert_quiesced(slug, project_id)
    ctx.update(45, "Receiving verified transfer on peer")
    _submit_and_await_peer_operation(
        "POST",
        "/api/transfers/receive",
        transfer_payload(f"RECEIVE TRANSFER {slug}"),
        "receive transfer",
        peer_call,
    )
    ctx.update(65, "Finalizing source ownership handoff")
    try:
        finalize_source(slug, project_id, destination_host_id)
    except Exception:
        raise RuntimeError("Source transfer finalization failed.") from None
    ctx.update(75, "Activating verified transfer on peer")
    _submit_and_await_peer_operation(
        "POST",
        "/api/transfers/activate",
        transfer_payload(f"ACTIVATE TRANSFER {slug}"),
        "activate transfer",
        peer_call,
    )
    ctx.update(95, "Ownership handoff activated and started on peer")
    return "Ownership transferred to peer."
