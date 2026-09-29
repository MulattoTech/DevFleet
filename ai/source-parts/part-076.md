# DevFleet source part 076

Full-source UTF-8 byte interval [3487500, 3534000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 4f657ac23707809c7c86efb384e8f381aeae3cc99bc549d9539641bdfafd9af3

<!-- BEGIN SOURCE SLICE -->
if is_login else "declared request body exceeds limit"
            message = "login form body exceeds the bounded limit" if is_login else "request body exceeds the bounded limit"
            _reject_reason(scope, reason, declared=declared, observed=0, started=started)
            await _send_rejection(send, 413, message)
            return

        if limit is not None:
            # Read only the bounded body before invoking FastAPI.  The
            # buffer can never exceed `limit`; an over-limit chunk is rejected
            # without being retained, so parser work cannot start first and
            # turn the admission failure into a generic 400 response.
            buffered: list[dict[str, Any]] = []
            observed = 0
            while True:
                message = await receive()
                if message.get("type") != "http.request":
                    buffered.append(message)
                    break
                body = message.get("body", b"") or b""
                observed += len(body)
                if observed > limit:
                    reason = "observed login body exceeds limit" if is_login else "observed request body exceeds limit"
                    message = "login form body exceeds the bounded limit" if is_login else "request body exceeds the bounded limit"
                    _reject_reason(scope, reason, declared=declared, observed=observed, started=started)
                    await _send_rejection(send, 413, message)
                    return
                buffered.append(message)
                if not message.get("more_body", False):
                    break
            replay = iter(buffered)

            async def bounded_receive() -> dict[str, Any]:
                try:
                    return next(replay)
                except StopIteration:
                    return {"type": "http.disconnect"}

            await self.app(scope, bounded_receive, send)
            return

        await self.app(scope, receive, send)

```


## FILE: source/app/devfleet/resource_profiles.py

SHA256: 9bec3c14f6019fe4439065f8419dd7f11cc2de01ed9e9bd15bbbc5bf94102eb1 | Bytes: 14021 | Git mode: 100644

```
"""Central resource profiles and host-safe allocation policy."""
from __future__ import annotations

from dataclasses import asdict, dataclass
import json
from pathlib import Path
from typing import Any

import yaml

from .core import atomic_text


_RESOURCE_POLICY_DEFAULTS = {
    "schemaVersion": 1,
    "policyVersion": "1.0.0",
    "physicalFloorMinGiB": 8.0,
    "physicalFloorPercent": 0.10,
    "commitHeadroomFloorMinGiB": 16.0,
    "commitHeadroomPercent": 0.20,
    "commitUsageLimitPercent": 80.0,
}
_RESOURCE_POLICY_PATH = Path(__file__).resolve().parents[2] / "config" / "resource-policy.json"
try:
    _RESOURCE_POLICY = {**_RESOURCE_POLICY_DEFAULTS, **json.loads(_RESOURCE_POLICY_PATH.read_text(encoding="utf-8"))}
except (OSError, ValueError, TypeError):
    _RESOURCE_POLICY = dict(_RESOURCE_POLICY_DEFAULTS)
RESOURCE_POLICY_VERSION = str(_RESOURCE_POLICY["policyVersion"])


@dataclass(frozen=True)
class ResourceProfile:
    name: str
    label: str
    cpus: float
    memory: str
    disk_gb: int
    pids: int
    rationale: str

    @property
    def vcpus(self) -> float:
        return self.cpus

    @property
    def memory_gb(self) -> float:
        return float(str(self.memory).lower().replace("gb", "").replace("g", "").strip())

    def limits(self, runtime_type: str = "container") -> dict[str, Any]:
        result = {
            "cpus": self.cpus,
            "memory": self.memory,
            "memory_gb": self.memory_gb,
            "disk_gb": self.disk_gb,
            "pids": self.pids,
        }
        if runtime_type == "vm":
            result["vcpus"] = self.vcpus
        return result


@dataclass(frozen=True)
class HostResourcePolicy:
    # Legacy fields remain for config compatibility; adaptive admission below
    # is the authoritative host-memory rule and does not use fixed reserves.
    minimum_free_memory_gb: float = 0.0
    reserved_memory_gb: float = 0.0
    reserved_logical_processors: float = 2.0
    minimum_free_disk_gb: float = 50.0
    maximum_vm_count: int = 4
    maximum_parallel_provisioning: int = 1
    max_project_cpus: float = 6.0
    max_project_memory_gb: float = 12.0
    max_project_disk_gb: float = 120.0


@dataclass(frozen=True)
class AdaptiveHostThresholds:
    physical_floor_gb: float
    commit_headroom_floor_gb: float
    commit_usage_limit_percent: float = 80.0


def adaptive_host_thresholds(usable_physical_gb: float, commit_limit_gb: float) -> AdaptiveHostThresholds:
    """Return the versioned host-admission floors used by E2E and capacity UI."""
    usable = float(usable_physical_gb)
    commit_limit = float(commit_limit_gb)
    if usable < 0 or commit_limit < 0:
        raise ValueError("Host memory values must be non-negative.")
    return AdaptiveHostThresholds(
        physical_floor_gb=max(float(_RESOURCE_POLICY["physicalFloorMinGiB"]), usable * float(_RESOURCE_POLICY["physicalFloorPercent"])),
        commit_headroom_floor_gb=max(float(_RESOURCE_POLICY["commitHeadroomFloorMinGiB"]), commit_limit * float(_RESOURCE_POLICY["commitHeadroomPercent"])),
        commit_usage_limit_percent=float(_RESOURCE_POLICY["commitUsageLimitPercent"]),
    )


def evaluate_host_memory_admission(
    *,
    usable_physical_gb: float,
    available_physical_gb: float,
    commit_limit_gb: float,
    committed_gb: float,
    projected_allocation_gb: float,
    resource_exhaustion: bool = False,
) -> dict[str, Any]:
    thresholds = adaptive_host_thresholds(usable_physical_gb, commit_limit_gb)
    projected_available = float(available_physical_gb) - float(projected_allocation_gb)
    projected_headroom = float(commit_limit_gb) - float(committed_gb) - float(projected_allocation_gb)
    commit_percent = (float(committed_gb) / float(commit_limit_gb) * 100.0) if commit_limit_gb else 100.0
    return {
        "policy_version": RESOURCE_POLICY_VERSION,
        "physical_floor_gb": round(thresholds.physical_floor_gb, 2),
        "commit_headroom_floor_gb": round(thresholds.commit_headroom_floor_gb, 2),
        "projected_available_physical_gb": round(projected_available, 2),
        "projected_commit_headroom_gb": round(projected_headroom, 2),
        "current_commit_usage_percent": round(commit_percent, 2),
        "resource_exhaustion": bool(resource_exhaustion),
        "start_safe": bool(
            projected_available >= thresholds.physical_floor_gb
            and projected_headroom >= thresholds.commit_headroom_floor_gb
            and commit_percent < thresholds.commit_usage_limit_percent
            and not resource_exhaustion
        ),
    }


def resolved_resource_metadata(
    profile_name: str,
    runtime_type: str = "container",
    *,
    actual_runtime_resources: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Keep requested profile, resolved limits, and observed runtime separate."""
    if profile_name == "custom":
        requested = dict(actual_runtime_resources or {})
    else:
        requested = resource_metadata(profile_name, runtime_type)
    resolved = dict(requested)
    actual = dict(actual_runtime_resources or {})
    drift = {
        key: {"expected": resolved.get(key), "actual": actual.get(key)}
        for key in ("cpus", "memory_gb", "disk_gb")
        if key in actual and str(actual.get(key)) != str(resolved.get(key))
    }
    return {
        "policy_version": RESOURCE_POLICY_VERSION,
        "requested_profile": profile_name,
        "requested_limits": requested,
        "resolved_resources": resolved,
        "actual_runtime_resources": actual,
        "resource_drift": drift,
        "resource_drift_status": "RESOURCE DRIFT" if drift else "MATCH",
    }


RESOURCE_PROFILES = {
    "small": ResourceProfile("small", "Light", 1.0, "2g", 20, 512, "Lightweight prototype or automation workload."),
    "standard": ResourceProfile("standard", "Standard", 2.0, "4g", 40, 768, "Normal web, API, CLI, or service development."),
    "large": ResourceProfile("large", "Performance", 4.0, "8g", 80, 1536, "Multi-service, production-like, or data-heavy development."),
    "xlarge": ResourceProfile("xlarge", "Intensive", 6.0, "12g", 120, 2048, "Heavy build or infrastructure workload; still GPU-free."),
}

RUNTIME_ISOLATIONS = {
    "container": "Project-isolated containers on the shared DevFleet host",
    "vm": "Dedicated Multipass VM (host-assisted provisioning; no GPU path)",
}

LAPTOP_PROFILE_DEFAULT = {"failover_memory_gb": 5.0, "vault_memory_gb": 2.0}
LAPTOP_PROFILE_MINIMUM_TESTED = {"failover_memory_gb": 4.0, "vault_memory_gb": 2.0}


def laptop_surrogate_profile(*, failover_memory_gb: float = 5.0, vault_memory_gb: float = 2.0) -> dict[str, float]:
    """Return the conservative tested Laptop/Surrogate memory profile."""
    failover = float(failover_memory_gb)
    vault = float(vault_memory_gb)
    if failover < LAPTOP_PROFILE_MINIMUM_TESTED["failover_memory_gb"] or vault < LAPTOP_PROFILE_MINIMUM_TESTED["vault_memory_gb"]:
        raise ValueError("Laptop/Surrogate memory is below the lowest tested stable profile.")
    return {"failover_memory_gb": failover, "vault_memory_gb": vault}


def policy_from_config(values: dict[str, Any] | None = None) -> HostResourcePolicy:
    values = values or {}
    aliases = {
        "minimum_free_memory": "minimum_free_memory_gb",
        "reserved_memory": "reserved_memory_gb",
        "reserved_logical_processors": "reserved_logical_processors",
        "minimum_free_disk": "minimum_free_disk_gb",
        "max_vm_count": "maximum_vm_count",
        "maximum_vm_count": "maximum_vm_count",
        "max_parallel_provisioning": "maximum_parallel_provisioning",
    }
    normalized = {aliases.get(k, k): v for k, v in values.items()}
    defaults = asdict(HostResourcePolicy())
    for key, default in defaults.items():
        if key in normalized:
            try:
                defaults[key] = type(default)(normalized[key])
            except (TypeError, ValueError):
                raise ValueError(f"Invalid host resource policy value: {key}")
    return HostResourcePolicy(**defaults)


def get_resource_profile(name: str) -> ResourceProfile:
    key = str(name or "").strip().lower()
    if key not in RESOURCE_PROFILES:
        raise ValueError(f"Unknown resource profile: {key}")
    return RESOURCE_PROFILES[key]


def custom_resource_metadata(values: dict[str, Any], *, runtime_type: str = "container") -> dict[str, Any]:
    """Validate dashboard-supplied limits without allowing privileged PID mode."""
    if str(values.get("pid_mode", "private") or "private").lower() != "private":
        raise ValueError("Host PID namespace is not supported by the safe DevFleet runtime policy.")
    return validate_resource_limits(values, runtime_type=runtime_type)


def validate_resource_limits(values: dict[str, Any], *, runtime_type: str = "container", policy: HostResourcePolicy | None = None) -> dict[str, Any]:
    policy = policy or HostResourcePolicy()
    try:
        cpus = float(values.get("cpus", values.get("vcpus")))
        memory_gb = float(values.get("memory_gb", str(values.get("memory", "")).lower().replace("gb", "").replace("g", "")))
        disk_gb = int(values.get("disk_gb"))
        pids = int(values.get("pids", 0))
    except (TypeError, ValueError):
        raise ValueError("Resource limits must contain numeric CPU, memory, disk, and PID values.")
    if cpus < 1 or cpus > policy.max_project_cpus:
        raise ValueError("CPU allocation is outside the host-agent policy.")
    if memory_gb < 2 or memory_gb > policy.max_project_memory_gb:
        raise ValueError("Memory allocation is outside the host-agent policy.")
    if disk_gb < 20 or disk_gb > policy.max_project_disk_gb:
        raise ValueError("Disk allocation is outside the host-agent policy.")
    if pids < 0 or pids > 4096:
        raise ValueError("PID limit is outside the host-agent policy.")
    return {
        "cpus": cpus,
        "vcpus": cpus,
        "memory_gb": memory_gb,
        "memory": f"{int(memory_gb) if memory_gb.is_integer() else memory_gb:g}g",
        "disk_gb": disk_gb,
        "pids": pids,
        "runtime_type": runtime_type,
    }


def capacity_allows(capacity: dict[str, Any], limits: dict[str, Any]) -> tuple[bool, str]:
    checks = (
        ("allocatable_cpus", float(limits.get("cpus", limits.get("vcpus", 0))), "CPU"),
        ("allocatable_memory_gb", float(limits.get("memory_gb", 0)), "memory"),
        ("allocatable_disk_gb", float(limits.get("disk_gb", 0)), "disk"),
    )
    for key, requested, label in checks:
        available = float(capacity.get(key, 0) or 0)
        if requested > available:
            return False, f"Host capacity is below the safe threshold for {label}: requested {requested:g}, available {available:g}."
    return True, "Host capacity is sufficient."


def recommend_resource_profile(*, scale: str = "", intent: str = "", project_kind: str = "", language: str = "", framework: str = "") -> ResourceProfile:
    scale = str(scale or "").lower()
    intent = str(intent or "").lower()
    kind = str(project_kind or "").lower()
    language = str(language or "").lower()
    framework = str(framework or "").lower()
    if scale == "large" or kind in {"infrastructure-service", "full-stack-web"} or "data" in kind or "spark" in framework:
        return RESOURCE_PROFILES["large"]
    if intent == "production" and (kind in {"web-frontend", "rapid-api", "full-stack-web"} or framework in {"next.js", "spring", "spring-boot", "fastapi"}):
        return RESOURCE_PROFILES["large"]
    if scale == "medium" or intent == "production" or language in {"java", "csharp", "c++", "cpp", "rust"}:
        return RESOURCE_PROFILES["standard"]
    return RESOURCE_PROFILES["small"]


def recommend_runtime_isolation(*, scale: str = "", intent: str = "", project_kind: str = "") -> str:
    if str(scale or "").lower() == "large" and str(intent or "").lower() == "production":
        return "vm"
    if str(project_kind or "").lower() == "infrastructure-service":
        return "vm"
    return "container"


def resource_metadata(name: str, runtime_type: str = "container") -> dict[str, Any]:
    profile = get_resource_profile(name)
    return {**asdict(profile), **profile.limits(runtime_type)}


def resource_override_path(project: Path) -> Path:
    return project / ".devfleet" / "runtime-resources.yaml"


def ownership_override_path(project: Path) -> Path:
    return project / ".devfleet" / "runtime-ownership.yaml"


def write_ownership_override(project: Path, compose_file: Path, labels: dict[str, str]) -> Path | None:
    try:
        document = yaml.safe_load(compose_file.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        return None
    services = document.get("services") if isinstance(document, dict) else None
    if not isinstance(services, dict) or not services:
        return None
    override = {"services": {str(service): {"labels": dict(labels)} for service in services}}
    destination = ownership_override_path(project)
    atomic_text(destination, yaml.safe_dump(override, sort_keys=False))
    return destination


def write_resource_override(project: Path, compose_file: Path, profile_name: str | dict[str, Any]) -> Path | None:
    if isinstance(profile_name, dict):
        limits = custom_resource_metadata(profile_name, runtime_type="container")
    else:
        limits = get_resource_profile(profile_name).limits("container")
    try:
        document = yaml.safe_load(compose_file.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        return None
    services = document.get("services") if isinstance(document, dict) else None
    if not isinstance(services, dict) or not services:
        return None
    override = {"services": {str(service): {"cpus": limits["cpus"], "mem_limit": limits["memory"], "pids_limit": limits["pids"]} for service in services}}
    destination = resource_override_path(project)
    atomic_text(destination, yaml.safe_dump(override, sort_keys=False))
    return destination

```


## FILE: source/app/devfleet/runtime.py

SHA256: 0fde1265ee3895e9dd1b0369256eca1e55fa51532ff1918982ad03ee4f5e4aad | Bytes: 11280 | Git mode: 100644

```
"""First-class project runtime/provider boundary.

The dashboard and project model express intent. Providers own mechanics. The
VM provider talks only to the authenticated host-agent client; no Multipass
command is reachable from a dashboard route.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

from .host_control import (
    destroy_project_vm,
    ensure_project_vm,
    get_host_capacity,
    get_provider_status,
    runtime_project_vm,
    stop_project_vm,
    export_project_workspace,
    export_project_workspace_to_source,
    restore_previous_source_workspace,
    project_vm_operation,
    list_project_vm_backups,
    inspect_project_vm_backup,
    restore_project_vm_backup,
    refresh_project_vm_connection_state,
    host_control_request,
)


@dataclass(frozen=True)
class RuntimeProvider:
    name: str
    runtime_type: str
    description: str
    gpu_enabled: bool = False

    @property
    def is_vm(self) -> bool:
        return self.runtime_type == "vm"


class ProjectRuntimeProvider(Protocol):
    provider: RuntimeProvider

    def create(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def start(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def stop(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def restart(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def inspect(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def health(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def backup(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def quarantine(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def restore(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def destroy(self, slug: str, metadata: dict[str, Any], **kwargs: Any) -> dict[str, Any]: ...
    def reconcile(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def refresh(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...
    def command(self, slug: str, metadata: dict[str, Any], operation: str, *, command_key: str = "", tail: int = 150) -> dict[str, Any]: ...
    def logs(self, slug: str, metadata: dict[str, Any], *, tail: int = 150) -> dict[str, Any]: ...
    def export(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]: ...


CONTAINER_PROVIDER = RuntimeProvider("docker-compose", "container", "Dedicated project containers on the current DevFleet VM.")
VM_PROVIDER = RuntimeProvider("multipass-host-agent", "vm", "Dedicated project VM managed by the authenticated Windows host agent; GPU access is disabled.")


def provider_for(metadata: dict[str, Any]) -> RuntimeProvider:
    recorded = str(metadata.get("runtime_provider") or "").lower()
    isolation = str(metadata.get("runtime_isolation") or metadata.get("runtime_type") or "container").lower()
    if recorded in {VM_PROVIDER.name, "multipass", "vm"} or isolation == "vm":
        return VM_PROVIDER
    return CONTAINER_PROVIDER


def runtime_metadata(provider: RuntimeProvider, *, status: str, **values: Any) -> dict[str, Any]:
    data = {
        "runtime_type": provider.runtime_type,
        "runtime_provider": provider.name,
        "runtime_status": status,
        "gpu_enabled": False,
    }
    data.update({key: value for key, value in values.items() if value is not None})
    return data


class MultipassRuntimeProvider:
    provider = VM_PROVIDER

    def create(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return ensure_project_vm(slug, metadata.get("resource_limits") or {}, project_id=str(metadata.get("project_id") or ""), git_url=str(metadata.get("git_url") or ""))

    def start(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return runtime_project_vm(slug, "start", runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def stop(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return stop_project_vm(slug, runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def restart(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return runtime_project_vm(slug, "restart", runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def inspect(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return runtime_project_vm(slug, "inspect", runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def health(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return runtime_project_vm(slug, "health", runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def backup(self, slug: str, metadata: dict[str, Any], *, consistency_level: str = "live-best-effort", destructive: bool = False) -> dict[str, Any]:
        return host_control_request("backup", {"slug": slug, "project_id": str(metadata.get("project_id") or ""), "consistency_level": consistency_level, "destructive": bool(destructive)}, runtime_id=str(metadata.get("runtime_id") or ""))

    def quarantine(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return runtime_project_vm(slug, "quarantine", runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def restore(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return runtime_project_vm(slug, "restore", runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def destroy(self, slug: str, metadata: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
        return destroy_project_vm(slug, str(kwargs.get("confirm_slug") or ""), str(kwargs.get("confirm_phrase") or ""), backup_verified=bool(kwargs.get("backup_verified")), backup_id=str(kwargs.get("backup_id") or ""), backup_sha256=str(kwargs.get("backup_sha256") or ""), cleanup_only=bool(kwargs.get("cleanup_only")), runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def reconcile(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return self.inspect(slug, metadata)

    def refresh(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return refresh_project_vm_connection_state(slug, str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def command(self, slug: str, metadata: dict[str, Any], operation: str, *, command_key: str = "", tail: int = 150) -> dict[str, Any]:
        return project_vm_operation(slug, operation, runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""), command_key=command_key, tail=tail)

    def logs(self, slug: str, metadata: dict[str, Any], *, tail: int = 150) -> dict[str, Any]:
        return self.command(slug, metadata, "project-logs", tail=tail)

    def export(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return export_project_workspace(slug, str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def list_backups(self, slug: str, metadata: dict[str, Any]) -> list[dict[str, Any]]:
        return list_project_vm_backups(slug, runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def inspect_backup(self, slug: str, metadata: dict[str, Any], backup_id: str) -> dict[str, Any]:
        return inspect_project_vm_backup(slug, backup_id, runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def restore_backup(self, slug: str, metadata: dict[str, Any], backup_id: str, *, confirm_restore: bool = False) -> dict[str, Any]:
        return restore_project_vm_backup(slug, backup_id, confirm_restore=confirm_restore, runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def export_to_source(self, slug: str, metadata: dict[str, Any], *, source_vm: str, replace_source: bool = False) -> dict[str, Any]:
        return export_project_workspace_to_source(slug, str(metadata.get("runtime_id") or ""), source_vm=source_vm, project_id=str(metadata.get("project_id") or ""), replace_source=replace_source)

    def restore_previous_source(self, slug: str, metadata: dict[str, Any], *, source_vm: str, previous_workspace_path: str) -> dict[str, Any]:
        return restore_previous_source_workspace(slug, str(metadata.get("runtime_id") or ""), source_vm=source_vm, project_id=str(metadata.get("project_id") or ""), previous_workspace_path=previous_workspace_path)


VM_RUNTIME = MultipassRuntimeProvider()


class VmRuntimeOperations:
    """Compatibility facade for existing project lifecycle code."""

    @staticmethod
    def ensure(slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return VM_RUNTIME.create(slug, metadata)

    @staticmethod
    def start(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.start(slug, metadata or {})

    @staticmethod
    def stop(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.stop(slug, metadata or {})

    @staticmethod
    def restart(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.restart(slug, metadata or {})

    @staticmethod
    def inspect(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.inspect(slug, metadata or {})

    @staticmethod
    def refresh(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.refresh(slug, metadata or {})

    @staticmethod
    def health(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.health(slug, metadata or {})

    @staticmethod
    def backup(slug: str, metadata: dict[str, Any] | None = None, *, consistency_level: str = "live-best-effort", destructive: bool = False) -> dict[str, Any]:
        return VM_RUNTIME.backup(slug, metadata or {}, consistency_level=consistency_level, destructive=destructive)

    @staticmethod
    def quarantine(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.quarantine(slug, metadata or {})

    @staticmethod
    def restore(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.restore(slug, metadata or {})

    @staticmethod
    def command(slug: str, metadata: dict[str, Any] | None, operation: str, *, command_key: str = "", tail: int = 150) -> dict[str, Any]:
        return VM_RUNTIME.command(slug, metadata or {}, operation, command_key=command_key, tail=tail)

    @staticmethod
    def destroy(slug: str, metadata: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
        return VM_RUNTIME.destroy(slug, metadata, **kwargs)


def host_capacity() -> dict[str, Any]:
    return get_host_capacity()


def provider_status() -> dict[str, Any]:
    return get_provider_status()

```


## FILE: source/app/devfleet/status.py

SHA256: d5c260df7828b383aa6c7f1d6ff2735783430e5db5457bdd2d5989316164607c | Bytes: 14255 | Git mode: 100644

```
from __future__ import annotations
import json,os,shutil,socket,time,threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any
import httpx,psutil
from .core import SETTINGS,load_peer,run
from .projects import list_projects,list_project_catalog
from .ollama import ollama_health
from .operations import list_operations
from .containers import list_containers
from .host_control import get_host_capacity,get_provider_status,host_control_status
from .version import __version__
from .node_registry import NodeRegistry
from urllib.parse import urlsplit

_RUNTIME_CACHE: tuple[float,dict[str,Any]]|None=None
_SNAPSHOT_LOCK=threading.RLock()
_SNAPSHOT_EXECUTOR=ThreadPoolExecutor(max_workers=2,thread_name_prefix='devfleet-snapshot')
_SNAPSHOTS:dict[str,dict[str,Any]]={
 'runtime':{'value':None,'updated_at':0.0,'refreshing':False,'last_duration_ms':None,'error':'','retry_after':0.0,'failures':0},
 'cluster':{'value':None,'updated_at':0.0,'refreshing':False,'last_duration_ms':None,'error':'','retry_after':0.0,'failures':0},
}
_SNAPSHOT_TTLS={'runtime':5.0,'cluster':20.0}
_PEER_BACKOFF_BASE=2.0;_PEER_BACKOFF_MAX=60.0;_PEER_FAILURE_WINDOW=300.0
_PEER_STATE={'failures':0,'last_failure':0.0,'retry_after':0.0,'circuit_until':0.0,'value':None,'inflight':False}

def _node_identity()->dict[str,Any]:
 try:
  registry=NodeRegistry().load();nodes=registry.get('nodes',[]) if isinstance(registry,dict) else []
  local=next((item for item in nodes if isinstance(item,dict) and item.get('node_name')==SETTINGS.node_name),None)
  return {'deployment_id':registry.get('deployment_id',''),'node_id':(local or {}).get('node_id',''),'node_role':(local or {}).get('node_role',SETTINGS.node_role),'coordinator_node_id':(local or {}).get('coordinator_node_id')}
 except (OSError,ValueError,TypeError):
  return {'deployment_id':'','node_id':'','node_role':SETTINGS.node_role,'coordinator_node_id':None}

_BACKUP_STATUS_PATH=Path('/var/lib/devfleet/backup-status/latest.json')
_BACKUP_CONFIG_PATH=Path('/var/lib/devfleet/backup-status/config.json')

def _backup_snapshot()->dict[str,Any]:
 try:
  data=json.loads(_BACKUP_STATUS_PATH.read_text(encoding='utf-8'))
  return data if isinstance(data,dict) else {}
 except (OSError,json.JSONDecodeError): return {}

def _cheap_runtime()->dict[str,Any]:
 hour=time.localtime().tm_hour;greeting='Good morning' if hour < 12 else 'Good afternoon' if hour < 18 else 'Good evening'
 return {'node':SETTINGS.node_name,'friendly_name':SETTINGS.friendly_name,'role':SETTINGS.node_role,'version':__version__,'greeting':f'{greeting}, developer','profile':SETTINGS.development_profile,'docker':{},'containers':[],'backup':backup_status(),'ollama':{'status':'not-yet-refreshed'},'system':{},'vault':{'status':'not-yet-refreshed'},'host_agent':{'status':'not-yet-refreshed'},'host_capacity':{'status':'not-yet-refreshed'},'vm_provider':{'status':'not-yet-refreshed'}}

def _refresh_snapshot(name:str)->None:
 with _SNAPSHOT_LOCK:
  state=_SNAPSHOTS[name]
  state['refreshing']=True
 started=time.monotonic()
 try:
  value=runtime_status() if name=='runtime' else cluster_status()
  error=''
 except Exception as exc:
  value=None;error=str(exc)[-500:]
 with _SNAPSHOT_LOCK:
   state=_SNAPSHOTS[name];state['refreshing']=False;state['last_duration_ms']=round((time.monotonic()-started)*1000,2);state['error']=error;now=time.monotonic()
   if value is not None:state['value']=value;state['updated_at']=now;state['retry_after']=0.0;state['failures']=0
   else:
    state['failures']=min(int(state.get('failures',0))+1,8);delay=min(60.0,2.0*(2**(state['failures']-1)));state['retry_after']=now+delay;state['updated_at']=now

def _schedule_snapshot(name:str)->None:
 with _SNAPSHOT_LOCK:
  if _SNAPSHOTS[name]['refreshing']:return
  # Reserve the refresh before submitting: concurrent readers can never queue
  # duplicate work between the check and executor.submit().
  _SNAPSHOTS[name]['refreshing']=True
 try:
  _SNAPSHOT_EXECUTOR.submit(_refresh_snapshot,name)
 except Exception:
  with _SNAPSHOT_LOCK:_SNAPSHOTS[name]['refreshing']=False

def _snapshot(name:str)->dict[str,Any]:
 now=time.monotonic()
 with _SNAPSHOT_LOCK:
  state=dict(_SNAPSHOTS[name]);value=state.get('value') or (_cheap_runtime() if name=='runtime' else {'updated_at':'','nodes':[],'containers':[]})
  age=(now-state['updated_at']) if state['updated_at'] else None
  stale=age is None or age>_SNAPSHOT_TTLS[name]
  refreshing=bool(state['refreshing']);retry_after=float(state.get('retry_after',0.0) or 0.0)
  if stale and now>=retry_after:_schedule_snapshot(name)
 result=dict(value);result['snapshot']={'last_updated':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(time.time()-age)) if age is not None else None,'age_seconds':round(age,3) if age is not None else None,'stale':stale,'refreshing':refreshing,'last_duration_ms':state.get('last_duration_ms'),'error':state.get('error','')}
 return result

def runtime_snapshot()->dict[str,Any]:return _snapshot('runtime')
def cluster_snapshot()->dict[str,Any]:return _snapshot('cluster')
def docker_status()->dict[str,Any]:
 try:r=run(['docker','info','--format','{{json .}}'],check=False,timeout=3)
 except Exception as exc:return {'ok':False,'mode':SETTINGS.docker_mode,'error':f'Docker status probe timed out: {exc}'}
 if r.returncode:return {'ok':False,'mode':SETTINGS.docker_mode,'error':r.stderr[-500:]}
 try:
  d=json.loads(r.stdout);return {'ok':True,'mode':SETTINGS.docker_mode,'rootless':any('rootless' in str(x) for x in d.get('SecurityOptions') or []),'containers':d.get('Containers'),'images':d.get('Images'),'driver':d.get('Driver'),'docker_root_dir':d.get('DockerRootDir')}
 except Exception as exc:return {'ok':False,'mode':SETTINGS.docker_mode,'error':str(exc)}

def system_status()->dict[str,Any]:
 disk=shutil.disk_usage(SETTINGS.workspaces)
 return {'cpu_percent':psutil.cpu_percent(interval=.05),'memory_percent':psutil.virtual_memory().percent,'disk_free_gb':round(disk.free/1024**3,1),'load':list(os.getloadavg()) if hasattr(os,'getloadavg') else []}

def vault_status()->dict[str,Any]:
 """Probe the append-only vault listener without requiring Docker or exposing credentials."""
 config_path=_BACKUP_CONFIG_PATH
 if not config_path.is_file():return {'configured':False,'status':'not-configured'}
 repository=''
 try: repository=str((json.loads(config_path.read_text(encoding='utf-8')) or {}).get('repository') or '')
 except (OSError,json.JSONDecodeError): return {'configured':True,'reachable':False,'status':'invalid-status-record'}
 if repository.startswith('rest:'):repository=repository[5:]
 parsed=urlsplit(repository)
 if parsed.scheme not in {'http','https'} or not parsed.hostname or not parsed.port:
  return {'configured':True,'reachable':False,'status':'invalid-repository-url'}
 started=time.monotonic()
 try:
  with socket.create_connection((parsed.hostname,parsed.port),timeout=1.5):pass
  return {'configured':True,'reachable':True,'status':'reachable','host':parsed.hostname,'port':parsed.port,'probe_ms':round((time.monotonic()-started)*1000)}
 except OSError as exc:
  return {'configured':True,'reachable':False,'status':'unreachable','host':parsed.hostname,'port':parsed.port,'error':str(exc)[-500:]}

def runtime_status()->dict[str,Any]:
 global _RUNTIME_CACHE
 now=time.monotonic()
 if _RUNTIME_CACHE and now-_RUNTIME_CACHE[0] < 2.0:return _RUNTIME_CACHE[1]
 docker=docker_status()
 try:containers=list_containers()
 except Exception as exc:containers=[];docker={**docker,'container_probe_error':str(exc)[-500:]}
 agent=host_control_status()
 capacity={'configured':False,'status':'not-configured'}
 provider={'configured':False,'status':'not-configured'}
 if agent.get('configured'):
  if agent.get('reachable'):
   try:capacity={'configured':True,'status':'ok',**get_host_capacity()}
   except Exception as exc:capacity={'configured':True,'status':'unavailable','error':str(exc)[-500:]}
   try:provider={'configured':True,'status':'ok',**get_provider_status()}
   except Exception as exc:provider={'configured':True,'status':'unavailable','error':str(exc)[-500:]}
  else:
   capacity={'configured':True,'status':'unreachable','error':agent.get('error','Host agent is unreachable.')}
   provider={'configured':True,'status':'unreachable','error':agent.get('error','Host agent is unreachable.')}
 raw_capacity=capacity.get('capacity',capacity) if isinstance(capacity,dict) else {}
 normalized_capacity={**raw_capacity,'configured':capacity.get('configured',False),'status':capacity.get('status',raw_capacity.get('health','unavailable')),'available':bool(capacity.get('ok',False) and raw_capacity),'reason':capacity.get('error','') or ('' if raw_capacity else 'Host capacity has not been checked.')}
 hour=time.localtime().tm_hour;greeting='Good morning' if hour < 12 else 'Good afternoon' if hour < 18 else 'Good evening'
 value={'node':SETTINGS.node_name,'friendly_name':SETTINGS.friendly_name,'role':SETTINGS.node_role,'node_identity':_node_identity(),'version':__version__,'greeting':f'{greeting}, developer','profile':SETTINGS.development_profile,'docker':docker,'containers':containers,'backup':backup_status(),'ollama':ollama_health(),'system':system_status(),'vault':vault_status(),'host_agent':agent,'host_capacity':normalized_capacity,'vm_provider':provider}
 _RUNTIME_CACHE=(now,value)
 return value
def backup_status()->dict[str,Any]:
 snapshot=_backup_snapshot()
 if not snapshot:return {'configured':_BACKUP_CONFIG_PATH.exists(),'status':'not-yet-refreshed'}
 # Restic may wait on repository/network state for many seconds. Do not make
 # every dashboard render wait on that probe; the backup action/diagnostics
 # remain responsible for authoritative backup verification.
 return {'configured':True,**snapshot}
def local_status(*,live:bool=False)->dict[str,Any]:
 runtime=runtime_status() if live else runtime_snapshot()
 return {**runtime,'projects':list_projects() if live else list_project_catalog(),'operations':list_operations(20)}

def peer_node_status()->dict[str,Any]:
 peer=load_peer()
 if not peer.get('Url') or not peer.get('Token'):return {'configured':False,'status':'not-configured'}
 now=time.monotonic()
 with _SNAPSHOT_LOCK:
   if _PEER_STATE.get('last_failure') and now-_PEER_STATE['last_failure']>_PEER_FAILURE_WINDOW:_PEER_STATE.update({'failures':0,'retry_after':0.0,'circuit_until':0.0})
   if now < _PEER_STATE['retry_after']:
    cached=_PEER_STATE.get('value');return cached if isinstance(cached,dict) else {'configured':True,'ok':False,'status':'backoff','retry_after':round(_PEER_STATE['retry_after']-now,2)}
   if now < _PEER_STATE['circuit_until']:
    cached=_PEER_STATE.get('value');return cached if isinstance(cached,dict) else {'configured':True,'ok':False,'status':'circuit-open'}
   if _PEER_STATE.get('inflight'):
    cached=_PEER_STATE.get('value');return cached if isinstance(cached,dict) else {'configured':True,'ok':False,'status':'refreshing'}
   _PEER_STATE['inflight']=True
 try:
  base=peer['Url'].rstrip('/');headers={'X-DevFleet-Token':peer['Token']};started=time.monotonic()
  r=httpx.get(base+'/api/node/status',headers=headers,timeout=2.5)
  if r.status_code==404:
   # v1.1 peers expose /api/status, which includes project and container
   # inventory and is slower than the lightweight node endpoint. Do not
   # classify a healthy peer as offline merely because this fallback needs
   # a few seconds to assemble its inventory.
   legacy=httpx.get(base+'/api/status',headers=headers,timeout=4.5);legacy.raise_for_status();data=legacy.json();data.setdefault('containers',[]);data['compatibility']='legacy';data['probe_ms']=round((time.monotonic()-started)*1000)
  else:
   r.raise_for_status();data=r.json();data['probe_ms']=round((time.monotonic()-started)*1000)
  result={'configured':True,'ok':True,'node':data}
  with _SNAPSHOT_LOCK:_PEER_STATE.update({'failures':0,'last_failure':0.0,'retry_after':0.0,'circuit_until':0.0,'value':result,'inflight':False})
  return result
 except Exception as exc:
  with _SNAPSHOT_LOCK:
   failures=_PEER_STATE['failures']+1;_PEER_STATE['failures']=failures;_PEER_STATE['last_failure']=now
   delay=min(_PEER_BACKOFF_MAX,_PEER_BACKOFF_BASE*(2**min(failures-1,5)));_PEER_STATE['retry_after']=time.monotonic()+delay
   if failures>=3:_PEER_STATE['circuit_until']=time.monotonic()+min(_PEER_BACKOFF_MAX,delay*2)
   _PEER_STATE['inflight']=False
  return {'configured':True,'ok':False,'status':'unreachable','error':str(exc)[-500:],'retry_after':round(delay,2)}

def cluster_status()->dict[str,Any]:
 local=runtime_status();peer=peer_node_status();nodes=[{**local,'id':local['node'],'status':'online','reachable':True,'destination_selectable':True}]
 if peer.get('ok'):
  remote=peer.get('node') or {};nodes.append({**remote,'id':remote.get('node','devfleet-failover'),'status':'online','reachable':True,'destination_selectable':True})
 else:
  nodes.append({'id':'devfleet-failover','node':'devfleet-failover','friendly_name':'DevFleetFailover','role':'failover','status':'offline','reachable':False,'destination_selectable':False,'error':peer.get('error') or peer.get('status','unavailable'),'containers':[],'docker':{'ok':False},'system':{}})
 vault=vault_status();nodes.append({'id':'devfleet-vault','node':'devfleet-vault','friendly_name':'DevFleetVault','role':'vault','status':'online' if vault.get('reachable') else 'offline','reachable':bool(vault.get('reachable')),'vault':vault,'containers':[],'docker':{'ok':False,'mode':'not-applicable'},'system':{}})
 containers=[]
 for node in nodes:
  for item in node.get('containers') or []:
   containers.append({**item,'node_id':node['id'],'node_name':node.get('friendly_name') or node['id'],'control_scope':'peer' if node['id']=='devfleet-failover' else 'local'})
 return {'updated_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'nodes':nodes,'containers':containers}
def peer_status()->dict[str,Any]:
 peer=load_peer()
 if not peer.get('Url') or not peer.get('Token'):return {'configured':False}
 try:
  r=httpx.get(peer['Url'].rstrip('/')+'/api/status',headers={'X-DevFleet-Token':peer['Token']},timeout=4.5);r.raise_for_status();return {'configured':True,'ok':True,'peer':r.json()}
 except Exception as exc:return {'configured':True,'ok':False,'error':str(exc)}

```


## FILE: source/app/devfleet/version.py

SHA256: a0a9c477ebd09f6fa0713427174d3f86c685de2004badcd8f0c8dfc039dd4251 | Bytes: 744 | Git mode: 100644

```
"""Single package-version source shared by API, UI, and release tooling."""
from __future__ import annotations

import os
from pathlib import Path


def package_version() -> str:
    configured = str(os.environ.get("DEVFLEET_VERSION", "")).strip()
    candidates = [Path(configured)] if configured else []
    here = Path(__file__).resolve()
    candidates.extend((here.parents[1] / "VERSION", here.parents[2] / "VERSION"))
    for path in candidates:
        try:
            value = path.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if value:
            return value
    raise RuntimeError("DevFleet VERSION file is missing or empty; refusing a stale fallback.")


__version__ = package_version()

```


## FILE: source/app/devfleet/workspace_archives.py

SHA256: fcc44f267e3c4d0e8f9a674fa52a1675d46a5cb9877af27f8bc3868643605c0f | Bytes: 52391 | Git mode: 100644

```
"""Verified workspace archives used by migration, backup, and deletion gates.

The archive format is deliberately boring: a gzip tar with one top-level
project directory.  We validate the source before writing and validate the
archive again after writing so a backup is never reported as verified merely
because a command returned zero.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import tarfile
import tempfile
import shutil
import uuid
import contextlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .core import atomic_json, now_iso, validate_slug


GENERATED_DIR_NAMES = {
    "node_modules", ".next", "build", "dist", ".venv", "venv",
    ".pytest_cache", "__pycache__", ".test-runtime",
}


# Linux is the deployed control-plane target.  Its openat/no-follow primitives
# let the archive code bind authorization to an already-open object instead of
# asking tarfile to reopen a mutable pathname.  Windows retains the historical
# compatibility implementation below; it is not promoted as Linux identity
# evidence.
POSIX_FD_HARDENING = os.name == "posix" and hasattr(os, "O_NOFOLLOW") and hasattr(os, "supports_dir_fd")


def _object_identity(result: os.stat_result) -> dict[str, int]:
    return {
        "st_dev": int(result.st_dev),
        "st_ino": int(result.st_ino),
        "st_type": int(stat.S_IFMT(result.st_mode)),
    }


def _identity_matches(result: os.stat_result, expected: dict[str, int] | None) -> bool:
    return expected is not None and _object_identity(result) == expected


def _fd_directory_flags() -> int:
    return os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)


def _fd_regular_flags() -> int:
    return os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)


def _open_verified_child(parent_fd: int, name: str, kind: int) -> tuple[int, os.stat_result]:
    observed = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if stat.S_IFMT(observed.st_mode) != kind:
        raise ValueError(f"Workspace entry changed type before it could be opened: {name}")
    if kind == stat.S_IFREG and observed.st_nlink != 1:
        raise ValueError(f"Workspace entry has an unexpected hard-link count: {name}")
    flags = _fd_directory_flags() if kind == stat.S_IFDIR else _fd_regular_flags()
    try:
        fd = os.open(name, flags, dir_fd=parent_fd)
    except OSError as exc:
        raise ValueError(f"Workspace entry could not be opened without following aliases: {name}") from exc
    try:
        actual = os.fstat(fd)
        if not _identity_matches(actual, _object_identity(observed)):
            raise ValueError(f"Workspace entry identity changed before it could be authorized: {name}")
        return fd, actual
    except Exception:
        os.close(fd)
        raise


def _open_verified_root(root: Path) -> tuple[int, os.stat_result, Path]:
    lexical = Path(os.path.abspath(os.fspath(root)))
    observed = os.lstat(lexical)
    if stat.S_IFMT(observed.st_mode) != stat.S_IFDIR:
        raise ValueError("Workspace must be a real directory.")
    try:
        fd = os.open(lexical, _fd_directory_flags())
    except OSError as exc:
        raise ValueError("Workspace root could not be opened without following aliases.") from exc
    try:
        actual = os.fstat(fd)
        if