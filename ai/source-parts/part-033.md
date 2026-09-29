# DevFleet source part 033

Full-source UTF-8 byte interval [1488000, 1534500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: fa2024a678ebd7d1763a4f0ead1e251d7685fcc7d2eb21da4b7da73bda709354

<!-- BEGIN SOURCE SLICE -->
e-real-uninstall';candidate=$result.candidate;guest=$result.guest;sentinels=$result.foreignSentinels;evidencePath=$result.evidencePath}
}

function Invoke-AiBundlePhase {
    param([Parameter(Mandatory)][psobject]$Context)
    $candidate = Assert-ExactCandidate $Context
    $workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $builder = Join-Path $workspace 'tools\Build-AIAuditBundle.ps1'
    $archive = Join-Path $workspace ('outputs\DevFleet-v{0}-AI-Audit-LATEST.zip' -f $Context.candidate.releaseVersion)
    if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw 'Canonical AI audit builder is missing.' }
    $buildOutput = @(& (Get-Command pwsh.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $builder -Workspace $workspace 2>&1)
    $buildExit = $LASTEXITCODE
    $buildRawPath = Join-Path ([string]$Context.runDir) 'ai-bundle-build-output.txt'
    $buildOutput | ForEach-Object { [string]$_ } | Set-Content -LiteralPath $buildRawPath -Encoding UTF8
    if ($buildExit -ne 0 -or -not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Canonical AI audit builder failed; evidence=$buildRawPath" }
    $report = Join-Path ([string]$Context.runDir) 'ai-audit-bundle-self-test.json'
    $builderReport = Join-Path $workspace 'audit\ai-audit-bundle-self-test.json'
    if (-not (Test-Path -LiteralPath $builderReport -PathType Leaf)) { throw 'Canonical builder validator report is missing.' }
    $validated = Get-Content -LiteralPath $builderReport -Raw | ConvertFrom-Json
    $manifest = "$archive.manifest.json"
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'Canonical AI audit sidecar manifest is missing.' }
    $bundleManifest = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ([string]$bundleManifest.selfTest -ne 'PASS' -or [int]$bundleManifest.expectedSourceCount -ne [int]$bundleManifest.includedSourceCount) { throw 'Canonical AI audit source inventory is incomplete.' }
    # The builder chooses its mode from truthful native state and has already
    # clean-extracted this archive. Bind reuse to its exact completed bytes.
    $archiveHash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$bundleManifest.sha256 -cne $archiveHash -or [long]$bundleManifest.bytes -ne [long](Get-Item -LiteralPath $archive).Length -or [string]$bundleManifest.path -cne [IO.Path]::GetFullPath($archive) -or [string]$validated.archive -cne [IO.Path]::GetFullPath($archive)) { throw 'Canonical builder validation archive binding mismatch.' }
    $validMode=([string]$validated.bundleMode -ceq 'diagnostic' -and [string]$validated.status -ceq 'PASS_WITH_BLOCKER' -and $validated.releaseEligible -eq $false) -or ([string]$validated.bundleMode -ceq 'release' -and [string]$validated.status -ceq 'COMPLETE_FOR_AI_AUDIT' -and $validated.releaseEligible -eq $true)
    if (-not $validMode -or [string]$validated.secretScan -cne 'PASS' -or [string]$validated.modeVerification -cne 'PASS' -or [int]$validated.includedSourceCount -ne [int]$bundleManifest.includedSourceCount) { throw 'Canonical builder validation report is not a successful matching round-trip.' }
    Copy-Item -LiteralPath $builderReport -Destination $report -Force
    $tarList = @(& tar.exe -tzf ([string]$Context.candidate.tar.path) 2>&1)
    if ($LASTEXITCODE -ne 0 -or @($tarList | Where-Object { $_ -match '(^|/)linux/bootstrap-compute\.sh$' }).Count -ne 1) { throw 'Standard TAR extraction cannot locate the exact Linux bootstrap entrypoint.' }
    return [ordered]@{status='REAL E2E PASS';phase='AI-BUNDLE';contract='current-candidate-audit-builder-validator';candidate=$candidate;archive=[ordered]@{path=$archive;bytes=[int64](Get-Item $archive).Length;sha256=(Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant();sourceCount=[int]$bundleManifest.includedSourceCount;validatorReport=$report};buildOutput=$buildRawPath;standardTarListing='PASS' }
}

function Invoke-ReconcilePhase {
    param([Parameter(Mandatory)][psobject]$Context)
    $candidate = Assert-ExactCandidate $Context
    $workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $head = (& git -C $workspace rev-parse HEAD).Trim()
    $manifest = Get-Content -LiteralPath (Join-Path $workspace 'outputs\final-artifact-hashes.json') -Raw | ConvertFrom-Json
    $state = Get-Content -LiteralPath (Join-Path $workspace 'finalization-state.json') -Raw | ConvertFrom-Json
    $release = Get-Content -LiteralPath (Join-Path $workspace 'outputs\release-fingerprint.json') -Raw | ConvertFrom-Json
    $tooling = Get-Content -LiteralPath (Join-Path $workspace 'outputs\tooling-fingerprint-current.json') -Raw | ConvertFrom-Json
    $currentShippingIdentity = [string]$state.shipping_input_identity
    if (-not $currentShippingIdentity -or [string]$state.candidate_git_commit -ne [string]$Context.candidate.gitCommit) { throw 'RECONCILE is missing independent repository-head/candidate identity.' }
    if ([string]$manifest.shippingInputIdentity -and [string]$manifest.shippingInputIdentity -ne $currentShippingIdentity) { throw 'RECONCILE shipping-input identity mismatch.' }
    foreach($pair in @(@('releaseFingerprintId',$Context.candidate.releaseFingerprintId,$manifest.releaseFingerprintId,$release.releaseFingerprintId,$tooling.releaseFingerprintId),@('toolingFingerprintId',$Context.candidate.toolingFingerprintId,$manifest.toolingFingerprintId,$release.toolingFingerprint.toolingFingerprintId,$tooling.toolingFingerprintId))){ if(@($pair[1..4] | ForEach-Object {[string]$_} | Select-Object -Unique).Count -ne 1){throw "RECONCILE identity mismatch: $($pair[0])"} }
    if (-not [bool]$state.candidate_is_current -or [bool]$state.source_changed_since_candidate -or [bool]$state.rebuild_required) { throw 'RECONCILE found a stale candidate state or rebuild requirement.' }
    $rows = @()
    $recordsPath = Join-Path ([string]$Context.runDir) 'fullrelease-phase-records.json'
    if (Test-Path -LiteralPath $recordsPath) { $rows = @(Get-Content -LiteralPath $recordsPath -Raw | ConvertFrom-Json) }
    $required = @('HOST-SAFETY','CANDIDATE-VERIFY','RESTORE-CLEAN','ESTABLISH-SESSION','DEPENDENCY-MATRIX','SECURITY-POISON','FRESH-INSTALL-WPF','PRIMARY','LINUX','HTTP-HOSTILE','MAINTENANCE-READY','WINDOWS-SENTINELS','REPAIR','CLEAN-REINSTALL','UNINSTALL','FACTORY-RESET','REBOOT-RESUME','PERMANENT-DELETE','DELETE-RESTORE','STOPPED-PROJECT','HOST-CONCURRENCY','OPERATION-RECOVERY','OWNERSHIP','VAULT','SURROGATE-DISPOSABLE','REAL-USE-ACCEPTANCE','TAILSCALE-DEFERRED','TAILSCALE-AUTH','AI-BUNDLE')
    $missing=@($required | Where-Object { $row=$rows | Where-Object id -eq $_ | Select-Object -Last 1; -not $row -or [string]$row.status -ne 'PASS' })
    if($missing.Count){throw "RECONCILE found mandatory phases missing or not PASS: $($missing -join ', ')"}
    $realUseRecord = @($rows | Where-Object { [string]$_.id -ceq 'REAL-USE-ACCEPTANCE' }) | Select-Object -Last 1
    Assert-RealUseAcceptancePhaseEvidence -PhaseResult $realUseRecord.evidence.executor -Context $Context | Out-Null
    $maintenance=@('REPAIR','CLEAN-REINSTALL','UNINSTALL','FACTORY-RESET','REBOOT-RESUME') | ForEach-Object { $rows | Where-Object id -eq $_ | Select-Object -Last 1 }
    if(@($maintenance).Count -ne 5){throw 'RECONCILE maintenance count is not 5/5.'}
    return [ordered]@{status='REAL E2E PASS';phase='RECONCILE';contract='exact-candidate-final-state-reconciliation';candidate=$candidate;repositoryHead=$head;candidateCommit=[string]$state.candidate_git_commit;shippingInputIdentity=$currentShippingIdentity;identities=[ordered]@{releaseFingerprintId=$release.releaseFingerprintId;toolingFingerprintId=$tooling.toolingFingerprintId};candidateState=[ordered]@{candidateIsCurrent=$state.candidate_is_current;sourceChangedSinceCandidate=$state.source_changed_since_candidate;rebuildRequired=$state.rebuild_required};mandatoryPhaseCount=$required.Count;maintenance='5/5';recordsPath=$recordsPath }
}

function Invoke-RealProductPhase {
    param([Parameter(Mandatory)][string]$ContextJson)
    $context = Read-PhaseContext $ContextJson
    # Generic Diagnostics is not a contract proof for named lifecycle phases; every such phase below dispatches scenario-specific evidence.
    switch ([string]$context.phaseId) {
        'DEPENDENCY-MATRIX' { return Invoke-DependencyMatrix $context }
        'SECURITY-POISON' { return Invoke-ActualWpfAction $context 'Diagnostics' -AllowMutation }
        'FRESH-INSTALL-WPF' {
            $ui=Invoke-SupportedFreshInstallLifecycle -Context $context -Role 'Primary / Desktop' -CompleteLifecycle
            if([string]$ui.status -ne 'REAL E2E PASS' -or -not [bool]$ui.completionVerified){throw "FRESH-INSTALL-WPF requires verified lifecycle completion; observed $([string]$ui.status)."}
            return $ui
        }
        'PRIMARY' { throw 'PRIMARY must be dispatched by Invoke-PrimaryPhase.ps1, not the generic product driver.' }
        'LINUX' { throw 'LINUX must be dispatched by Invoke-LinuxPhase.ps1, not the generic product driver.' }
        'HTTP-HOSTILE' { throw 'HTTP-HOSTILE must be dispatched by Invoke-HttpHostilePhase.ps1, not the generic product driver.' }
        'REPAIR' { return Invoke-ActualWpfAction $context 'Repair' -AllowMutation }
        'CLEAN-REINSTALL' { return Invoke-ActualWpfAction $context 'CleanReinstall' -AllowMutation }
        'UNINSTALL' { return Invoke-ActualWpfAction $context 'Uninstall' -AllowMutation }
        'FACTORY-RESET' { return Invoke-ActualWpfAction $context 'FactoryReset' -AllowMutation }
        'REBOOT-RESUME' { return Invoke-RebootResumePhase $context }
        'MAINTENANCE-READY-PROVISION' { return Invoke-ProductLifecycleConsumer -Context $context }
        'PERMANENT-DELETE' { return Invoke-NestedProductScenario $context 'permanent-delete' }
        'DELETE-RESTORE' { return Invoke-NestedProductScenario $context 'delete-restore' }
        'STOPPED-PROJECT' { return Invoke-NestedProductScenario $context 'stopped-project' }
        'HOST-CONCURRENCY' { return Invoke-NestedProductScenario $context 'host-concurrency' }
        'OPERATION-RECOVERY' { return Invoke-NestedProductScenario $context 'operation-recovery' }
        'OWNERSHIP' { return Invoke-NestedProductScenario $context 'ownership' }
        'WINDOWS-SENTINELS' { return Invoke-WindowsSentinelPhase $context }
        'VAULT' { return Invoke-NestedProductScenario $context 'vault' }
        'SURROGATE-DISPOSABLE' { return Invoke-SurrogateDisposablePhase $context }
        'REAL-USE-ACCEPTANCE' { return Invoke-RealUseAcceptancePhase -Context $context }
        'TAILSCALE-DEFERRED' { return Invoke-TailscalePolicyPhase $context }
        'TAILSCALE-AUTH' { return Invoke-TailscalePolicyPhase $context }
        'AI-BUNDLE' { return Invoke-AiBundlePhase $context }
        'RECONCILE' { return Invoke-ReconcilePhase $context }
        default { throw "No phase-specific product driver exists for $($context.phaseId)." }
    }
}

Export-ModuleMember -Function Get-DevFleetNestedPrimaryReadinessScriptBlock,New-DevFleetExactProofBinding,Invoke-RealProductPhase,Invoke-PrimaryRolePhase,Invoke-LinuxBootstrapPhase,Invoke-SupportedFreshInstallLifecycle,Invoke-ProductFreshInstallLifecycle,Invoke-DisposableSyntheticRebootProbe,Invoke-RebootResumePhase,Invoke-ProductLifecycleConsumer,Get-ProductLifecycleConsumerMode,Get-ProductLifecycleObservation,Wait-DevFleetProductLifecycleTransition,Test-ProductMeaningfulProgress,Test-RebootBoundaryIdentity,Get-DurableProgressClassification,Get-PhaseAwareBudgetSeconds,Resolve-GuestProgressMarkerRead,Add-GuestProgressMarkerObservation

```


## FILE: automation/release-e2e/modules/executors/Invoke-RealUseAcceptance.py

SHA256: 80d79b63d6f5eb5f69d7ebb5cdf4d00c8c30f33084d3b7cbc480019bed45e31a | Bytes: 63454 | Git mode: 100644

```
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
        meta = self.store.verify_