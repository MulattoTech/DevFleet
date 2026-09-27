# DevFleet source part 024

Full-source UTF-8 byte interval [1069500, 1116000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 38f30997d99f5f93527b94168289a217457e7259981c1ceb4e5d9d32fb1e7863

<!-- BEGIN SOURCE SLICE -->
json
import os
import pwd
import re
import shutil
import stat
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit


RELEASE_RUN_ID_PATTERN = re.compile(r"(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*")
VAULT_SCENARIOS = {"permanent-delete", "delete-restore", "vault"}
VAULT_INSTALLED_BIN = Path("/usr/local/bin")
VAULT_STATUS_CONFIG = Path("/var/lib/devfleet/backup-status/config.json")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def scenario_configuration(installed: dict, root: Path, suffix: str, scenario: str) -> dict:
    config = {
        **installed,
        "node_name": f"devfleet-e2e-{suffix}",
        "deployment_id": f"e2e-{suffix}",
        "workspaces": str(root / "workspaces"),
        "quarantine": str(root / "quarantine"),
        "peer_file": str(root / "peer.json"),
        "runtime_root": str(root / "runtime"),
        "cache_root": str(root / "cache"),
        "allow_permanent_delete": True,
        "require_tailscale": True,
        "public_binding_allowed": False,
        "tailnet_cidr": "100.64.0.0/10",
        "host_control_enabled": False,
    }
    if scenario in VAULT_SCENARIOS:
        # The installed backup/restore entrypoints own these exact roots. A
        # successful backup of unrelated paths is not destructive-test coverage.
        require(installed.get("workspaces") == "/home/devrunner/workspaces" and installed.get("quarantine") == "/home/devrunner/.devfleet-quarantine", "Positive Vault scenario configuration is outside the installed backup roots.")
        for key in ("workspaces", "quarantine", "node_name", "deployment_id"):
            config[key] = installed[key]
    return config


def require_vault_fixture(source_root: Path) -> None:
    bootstrap = source_root / "linux" / "bootstrap-vault.sh"
    require(bootstrap.is_file(), "Exact candidate Vault bootstrap is missing.")
    bootstrap_text = bootstrap.read_text(encoding="utf-8")
    require("tailscale ip -4" in bootstrap_text and "append-only" in bootstrap_text and "tailscale0" in bootstrap_text, "Vault bootstrap lacks canonical private-transport/append-only enforcement.")
    # Validate the effective installed entrypoints, not a literal environment
    # variable token in a script that correctly sources its protected config.
    for name in ("devfleet-backup", "devfleet-restore-project", "devfleet-vault-request"):
        candidate = source_root / "linux" / name
        installed = VAULT_INSTALLED_BIN / name
        require(candidate.is_file() and installed.is_file() and not installed.is_symlink(), "Exact candidate Vault entrypoint is missing or unsafe.")
        require(hashlib.sha256(candidate.read_bytes()).digest() == hashlib.sha256(installed.read_bytes()).digest(), "Installed Vault entrypoint differs from the exact candidate.")
    require(VAULT_STATUS_CONFIG.is_file() and not VAULT_STATUS_CONFIG.is_symlink(), "Positive scenario requires a configured authenticated Vault fixture; unconfigured deletion refusal is a separate negative case.")
    try:
        configuration = json.loads(VAULT_STATUS_CONFIG.read_text(encoding="utf-8"))
        repository = configuration["repository"]
        require(isinstance(repository, str) and repository.startswith("rest:http://"), "Vault fixture requires Tailscale REST transport.")
        parsed = urlsplit(repository.removeprefix("rest:"))
        private = ipaddress.IPv4Address(parsed.hostname) in ipaddress.IPv4Network("100.64.0.0/10")
        require(private and parsed.port is not None and 0 < parsed.port <= 65535 and bool(parsed.path) and parsed.username is None and parsed.password is None, "Vault fixture requires Tailscale REST transport with separately protected authentication.")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise RuntimeError("Configured Vault fixture has invalid Tailscale REST configuration.") from exc
    # This presence/transport check is not authentication credit. Only successful
    # production broker backup plus exact restored bytes below can earn that.


def command(args: list[str], *, timeout: int = 300, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)
    if check and result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {args[0]}: {(result.stderr or result.stdout)[-1500:]}")
    return result


def wait_operation(operations, operation_id: str, timeout: float = 120.0) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        record = operations.get_operation(operation_id)
        if record["state"] in {"completed", "failed", "cancelled", "interrupted"}:
            return record
        time.sleep(0.05)
    raise RuntimeError(f"Operation {operation_id} did not become terminal.")


class Scenario:
    def __init__(self, source_root: Path, run_id: str, scenario: str) -> None:
        self.source_root = source_root.resolve()
        self.run_id = run_id
        self.scenario = scenario
        suffix = hashlib.sha256(f"{run_id}:{scenario}".encode()).hexdigest()[:10]
        self.suffix = suffix
        self.root = Path("/tmp/devfleet-release-e2e") / suffix / scenario
        require(self.root.is_relative_to(Path("/tmp/devfleet-release-e2e")), "Scenario root escaped its disposable parent.")
        if self.root.exists():
            shutil.rmtree(self.root)
        self.root.mkdir(parents=True)
        installed_config = json.loads(Path("/etc/devfleet/config.json").read_text(encoding="utf-8"))
        devrunner_uid = pwd.getpwnam("devrunner").pw_uid
        docker_socket = Path(f"/run/user/{devrunner_uid}/docker.sock")
        socket_stat = docker_socket.stat()
        require(devrunner_uid > 0 and stat.S_ISSOCK(socket_stat.st_mode) and socket_stat.st_uid == devrunner_uid, "The rootless Docker socket is not owned by devrunner.")
        docker_host = f"unix://{docker_socket}"
        config = scenario_configuration(installed_config, self.root, suffix, scenario)
        config_path = self.root / "config.json"
        config_path.write_text(json.dumps(config), encoding="utf-8")
        os.environ["DEVFLEET_CONFIG_PATH"] = str(config_path)
        os.environ["DOCKER_HOST"] = docker_host
        os.environ["PYTHONPATH"] = str(self.source_root / "app")
        sys.path.insert(0, str(self.source_root / "app"))
        from devfleet import containers, operations, projects

        projects.TEMPLATE_ROOT = self.source_root / "templates"
        self.containers = containers
        self.operations = operations
        self.projects = projects
        self.docker_host = docker_host
        self.foreign_ids: list[str] = []
        self.slugs: list[str] = []

    def slug(self, stem: str) -> str:
        value = f"e2e-{stem}-{self.suffix}"
        self.slugs.append(value)
        return value

    def create_project(self, stem: str, *, start: bool = True) -> tuple[str, dict]:
        slug = self.slug(stem)
        metadata = self.projects.create_project(
            slug=slug,
            display_name=f"DevFleet E2E {stem}",
            template="generic",
            profile="strict",
            resource_profile="small",
            runtime_isolation="container",
            use_ollama=False,
        )
        require(metadata["managed_by"] == "devfleet" and metadata["slug"] == slug, "Created project lacks exact ownership metadata.")
        if start:
            self.projects.start_project(slug)
            require(self.projects.inspect_runtime(slug)["running"] is True, "Created project runtime did not start.")
        return slug, metadata

    def create_foreign_container(self, image: str, name: str) -> str:
        result = command(["docker", "run", "-d", "--name", name, "--label", "io.devfleet.managed-by=foreign", image, "sh", "-lc", "sleep 600"])
        immutable_id = result.stdout.strip()
        require(re.fullmatch(r"[0-9a-f]{64}", immutable_id) is not None, "Foreign container did not return an immutable Docker identity.")
        self.foreign_ids.append(immutable_id)
        return immutable_id

    def running_container(self, slug: str) -> tuple[str, str, str]:
        compose = self.projects.compose_file(self.projects.SETTINGS.workspaces / slug)
        require(compose is not None, "Project has no Compose runtime.")
        result = self.projects.run([*self.projects.compose_args(self.projects.SETTINGS.workspaces / slug, compose), "ps", "--quiet"], cwd=self.projects.SETTINGS.workspaces / slug)
        container_id = result.stdout.strip().splitlines()[0]
        inspected = json.loads(command(["docker", "inspect", container_id]).stdout)[0]
        return inspected["Id"], inspected["Config"]["Image"], inspected["Name"].lstrip("/")

    def permanent_delete(self) -> dict:
        require_vault_fixture(self.source_root)
        slug, metadata = self.create_project("delete")
        workspace = self.projects.SETTINGS.workspaces / slug
        sentinel = workspace / "release-sentinel.txt"
        sentinel.write_text("permanent-delete-evidence\n", encoding="utf-8")
        result = self.projects.destroy_project(slug, slug, f"DESTROY {slug}")
        require(not workspace.exists(), "Permanent delete left the authoritative workspace behind.")
        tombstones = list((self.projects.SETTINGS.runtime_root / "recovery-tombstones").glob(f"{slug}-*.json"))
        require(len(tombstones) == 1, "Permanent delete did not retain exactly one recovery tombstone.")
        tombstone = json.loads(tombstones[0].read_text(encoding="utf-8"))
        backups = self.projects.SETTINGS.runtime_root / "workspace-backups" / tombstone["backup_id"]
        require(backups.is_dir() and re.fullmatch(r"[0-9a-f]{64}", tombstone["backup_sha256"]), "Safety backup identity is incomplete.")
        restored_sha = self.verify_vault_copy(slug, metadata, b"permanent-delete-evidence\n")
        return {"workspaceAbsent": True, "projectId": metadata["project_id"], "backupId": tombstone["backup_id"], "backupSha256": tombstone["backup_sha256"], "tombstone": tombstones[0].name, "productResult": result[-1000:], "vaultSentinelSha256": restored_sha, "actualProjectVaultRecovery": "PASS"}

    def delete_restore(self) -> dict:
        require_vault_fixture(self.source_root)
        slug, metadata = self.create_project("restore")
        workspace = self.projects.SETTINGS.workspaces / slug
        sentinel = workspace / "release-sentinel.txt"
        expected = hashlib.sha256(f"{self.run_id}:{slug}".encode()).hexdigest()
        sentinel.write_text(expected + "\n", encoding="utf-8")
        self.projects.destroy_project(slug, slug, f"DESTROY {slug}")
        self.verify_vault_copy(slug, metadata, (expected + "\n").encode())
        tombstone_path = next((self.projects.SETTINGS.runtime_root / "recovery-tombstones").glob(f"{slug}-*.json"))
        tombstone = json.loads(tombstone_path.read_text(encoding="utf-8"))
        restored = self.projects.restore_deleted_project(slug, tombstone["backup_id"], project_id=metadata["project_id"], confirm_restore=True)
        require(sentinel.read_text(encoding="utf-8").strip() == expected, "Delete/restore did not recover exact sentinel content.")
        require(restored["project"]["project_id"] == metadata["project_id"], "Delete/restore changed project identity.")
        self.projects.start_project(slug)
        require(self.projects.runtime_health(slug)["healthy"] is True, "Restored project runtime did not return healthy.")
        self.projects.stop_project(slug)
        return {"projectId": metadata["project_id"], "backupId": tombstone["backup_id"], "backupSha256": restored["backup_sha256"], "sentinelSha256": hashlib.sha256(sentinel.read_bytes()).hexdigest(), "runtimeRestarted": True}

    def stopped_project(self) -> dict:
        slug, metadata = self.create_project("stopped")
        before = self.projects.inspect_runtime(slug)
        self.projects.stop_project(slug)
        stopped = self.projects.inspect_runtime(slug)
        health = self.projects.runtime_health(slug)
        require(before["running"] is True and stopped["running"] is False, "Stopped-project state transition was not truthful.")
        require(health["healthy"] is False and not str(self.projects.load_meta(self.projects.SETTINGS.workspaces / slug).get("runtime_address") or ""), "Stopped project retained a live runtime claim.")
        self.projects.start_project(slug)
        require(self.projects.inspect_runtime(slug)["running"] is True, "Stopped-project recovery did not restart the owned runtime.")
        self.projects.stop_project(slug)
        return {"projectId": metadata["project_id"], "runningBefore": True, "stoppedRecognized": True, "staleAddressRejected": True, "restartRecovered": True}

    def host_concurrency(self) -> dict:
        operations = self.operations
        started = threading.Event()
        release = threading.Event()
        active = 0
        maximum_same = 0
        lock = threading.Lock()

        def held(ctx):
            nonlocal active, maximum_same
            with lock:
                active += 1
                maximum_same = max(maximum_same, active)
            started.set()
            release.wait(10)
            with lock:
                active -= 1
            return "held"

        first = operations.submit_operation("e2e-mutation", "same-project", held, idempotency_key=f"e2e:{self.suffix}:same")
        require(started.wait(5), "First bounded mutation did not start.")
        duplicate = operations.submit_operation("e2e-mutation", "same-project", lambda _ctx: "duplicate", idempotency_key=f"e2e:{self.suffix}:same")
        second = operations.submit_operation("e2e-conflict", "same-project", lambda _ctx: "conflict")
        release.set()
        first_record = wait_operation(operations, first)
        second_record = wait_operation(operations, second)
        require(duplicate == first and first_record["state"] == "completed", "Operation idempotency did not reuse the live operation.")
        require(second_record["state"] == "failed" and second_record.get("error") == "operation_locked", "Conflicting same-project mutation was not serialized.")
        require(maximum_same == 1, "Same-project mutations overlapped.")

        barrier = threading.Barrier(2)
        independent_active = 0
        independent_maximum = 0

        def independent(_ctx):
            nonlocal independent_active, independent_maximum
            with lock:
                independent_active += 1
                independent_maximum = max(independent_maximum, independent_active)
            barrier.wait(timeout=5)
            time.sleep(0.2)
            with lock:
                independent_active -= 1
            return "independent"

        ids = [operations.submit_operation("e2e-read", name, independent) for name in ("project-a", "project-b")]
        records = [wait_operation(operations, value) for value in ids]
        require(all(record["state"] == "completed" for record in records) and independent_maximum == 2, "Independent project operations did not execute independently.")
        return {"sameOperationIdempotent": True, "sameProjectMaximumConcurrency": maximum_same, "conflictingMutationState": second_record["state"], "independentProjectMaximumConcurrency": independent_maximum, "leasesReleased": True}

    def operation_recovery(self) -> dict:
        op_path = self.root / "orphan-operation-id.txt"
        counter_path = self.root / "destructive-counter.txt"
        child_code = """
import os,time
from pathlib import Path
from devfleet import operations
counter=Path(os.environ['DEVFLEET_E2E_COUNTER'])
def work(ctx):
    counter.write_text('1\\n',encoding='utf-8');ctx.update(25,'fixture mutation entered','mutation');time.sleep(600)
op=operations.submit_operation('e2e-destructive','orphan-project',work,idempotency_key='e2e-orphan')
Path(os.environ['DEVFLEET_E2E_OP']).write_text(op,encoding='utf-8')
while True: time.sleep(1)
"""
        env = os.environ.copy()
        env["PYTHONPATH"] = str(self.source_root / "app")
        env["DEVFLEET_E2E_COUNTER"] = str(counter_path)
        env["DEVFLEET_E2E_OP"] = str(op_path)
        child = subprocess.Popen([sys.executable, "-c", child_code], env=env)
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and not op_path.exists():
                time.sleep(0.1)
            require(op_path.exists(), "Recovery child did not persist an operation identity.")
            op_id = op_path.read_text(encoding="utf-8").strip()
            record_path = self.operations.SETTINGS.operations / f"{op_id}.json"
            while time.monotonic() < deadline:
                record = json.loads(record_path.read_text(encoding="utf-8"))
                if record["state"] == "running" and counter_path.exists():
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError("Recovery child operation did not enter running state.")
            child.terminate()
            child.wait(timeout=10)
            lease = json.loads(record_path.read_text(encoding="utf-8"))["lease_expires_at"]
            lease_epoch = __import__("datetime").datetime.fromisoformat(lease.replace("Z", "+00:00")).timestamp()
            time.sleep(max(0.0, lease_epoch - time.time()) + 0.5)
            reconcile_code = "from devfleet.operations import reconcile_operations; import json; print(json.dumps(reconcile_operations()))"
            recovered = json.loads(command([sys.executable, "-c", reconcile_code], timeout=20).stdout)
            record = json.loads(record_path.read_text(encoding="utf-8"))
            require(op_id in recovered and record["state"] == "interrupted" and record["recovery_required"] is True, "Expired worker lease was not reconciled truthfully.")
            require(counter_path.read_text(encoding="utf-8").splitlines() == ["1"], "Interrupted mutation executed more than once.")
            return {"operationId": op_id, "originatingProcessExited": True, "leaseExpired": True, "reconciledState": record["state"], "recoveryRequired": True, "destructiveEntryCount": 1}
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=10)

    def ownership(self) -> dict:
        slug, metadata = self.create_project("ownership")
        owned_id, image, owned_name = self.running_container(slug)
        listed = {row["id"] for row in self.containers.list_containers()}
        require(owned_id in listed, "Owned container was absent from the authorized container inventory.")
        foreign_name = f"devfleet-e2e-foreign-{self.suffix}"
        foreign_id = self.create_foreign_container(image, foreign_name)
        require(foreign_id not in {row["id"] for row in self.containers.list_containers()}, "Foreign container leaked into the authorized inventory.")
        rejected = False
        try:
            self.containers.container_action(foreign_id, "remove")
        except ValueError:
            rejected = True
        require(rejected and command(["docker", "inspect", foreign_id], check=False).returncode == 0, "Foreign container mutation was not rejected and preserved.")
        self.projects.stop_project(slug)
        same_name_id = self.create_foreign_container(image, owned_name)
        same_name_rejected = False
        try:
            self.containers.container_action(owned_name, "remove")
        except ValueError:
            same_name_rejected = True
        require(same_name_rejected and command(["docker", "inspect", same_name_id], check=False).returncode == 0, "Same-name foreign replacement was not rejected and preserved.")
        return {"projectId": metadata["project_id"], "ownedContainerAccepted": True, "ownedImmutableId": owned_id, "foreignContainerRejected": True, "sameNameReplacementRejected": True, "foreignResourcesPreserved": True}

    def verify_vault_copy(self, slug: str, metadata: dict, expected: bytes) -> str:
        receipt = self.projects._vault_request("restore-copy", slug, metadata["project_id"], timeout=3720)
        target = Path(self.projects._validate_recovered_vault_copy(slug, metadata, str(receipt.get("target") or "")))
        require(target.resolve().parent == self.projects.SETTINGS.workspaces.resolve() and target != self.projects.SETTINGS.workspaces / slug and not target.is_symlink(), "Vault restored copy escaped its owned project boundary.")
        sentinel = target / "release-sentinel.txt"
        require(sentinel.is_file() and not sentinel.is_symlink() and sentinel.read_bytes() == expected, "Authenticated Vault restore did not recover the actual project sentinel.")
        return hashlib.sha256(sentinel.read_bytes()).hexdigest()

    def vault(self) -> dict:
        require_vault_fixture(self.source_root)
        slug, metadata = self.create_project("vault", start=False)
        sentinel = self.projects.SETTINGS.workspaces / slug / "release-sentinel.txt"
        expected = f"vault-{self.run_id}\n".encode()
        sentinel.write_bytes(expected)
        backup = json.loads(self.projects.backup_project(slug))
        require(backup.get("ok") is True and backup.get("vault_upload_status") == "verified" and backup.get("durability_level") == "vault", "Production backup did not verify authenticated Vault durability.")
        restored = Path(self.projects.restore_from_vault(slug)) / "release-sentinel.txt"
        require(restored.is_file() and not restored.is_symlink() and restored.read_bytes() == expected, "Authenticated Vault restore changed the actual project sentinel.")
        return {"projectId": metadata["project_id"], "resticBackup": "PASS", "resticRestore": "PASS", "sentinelSha256": hashlib.sha256(restored.read_bytes()).hexdigest(), "credentialInEvidence": False, "liveRemoteVault": "PASS", "actualProjectCovered": True}

    def cleanup(self) -> None:
        for slug in reversed(self.slugs):
            project = self.projects.SETTINGS.workspaces / slug
            if project.is_dir():
                try:
                    self.projects.stop_project(slug)
                except Exception:
                    pass
        for immutable_id in reversed(self.foreign_ids):
            command(["docker", "rm", "-f", immutable_id], timeout=60, check=False)
        if self.root.exists() and self.root.is_relative_to(Path("/tmp/devfleet-release-e2e")):
            shutil.rmtree(self.root)

    def run(self) -> dict:
        command(["docker", "version", "--format", "{{.Server.Version}}"], timeout=30)
        functions = {
            "permanent-delete": self.permanent_delete,
            "delete-restore": self.delete_restore,
            "stopped-project": self.stopped_project,
            "host-concurrency": self.host_concurrency,
            "operation-recovery": self.operation_recovery,
            "ownership": self.ownership,
            "vault": self.vault,
        }
        try:
            evidence = functions[self.scenario]()
            return {"status": "PASS", "scenario": self.scenario, "runId": self.run_id, "sourceVersion": (self.source_root / "VERSION").read_text(encoding="utf-8").strip(), "rootlessDocker": True, "dockerOwnerUid": int(re.search(r"/run/user/([0-9]+)/", self.docker_host).group(1)), "evidence": evidence, "cleanup": "PASS", "cleanupScope": "temporary scenario root and stopped owned workloads", "canonicalFixtureDisposal": "REQUIRED_BY_NATIVE_CHECKPOINT_RESTORE" if self.scenario in VAULT_SCENARIOS else "NOT_APPLICABLE"}
        finally:
            self.cleanup()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--scenario", choices=("permanent-delete", "delete-restore", "stopped-project", "host-concurrency", "operation-recovery", "ownership", "vault"), required=True)
    args = parser.parse_args()
    try:
        require(len(args.run_id) <= 128 and RELEASE_RUN_ID_PATTERN.fullmatch(args.run_id) is not None, "Invalid release run identity.")
        require((args.source_root / "VERSION").is_file() and (args.source_root / "app" / "devfleet" / "projects.py").is_file(), "Exact candidate source root is incomplete.")
        print(json.dumps(Scenario(args.source_root, args.run_id, args.scenario).run(), sort_keys=True))
        return 0
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "scenario": args.scenario, "error": str(exc)[-3000:]}, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1

SHA256: 75a9ae97cb6cedb6afd0f8286c08e4eb085f68b941e524f519a3f5620ef31d90 | Bytes: 344483 | Git mode: 100644

```
Set-StrictMode -Version Latest
Import-Module ThreadJob -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot '..\GuestSession.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\HostSafety.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Evidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\FullRelease.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\InteractiveLogon.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\TailscaleE2E.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\HarnessBudget.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\MultipassDiagnostic.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\RealUseAcceptance.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WpfLaunchContract.psm1') -Force

$script:CanonicalIntegrationOwnershipPath = 'C:\ProgramData\DevFleetHostAgent\integration-ownership.json'

function Resolve-DevFleetNestedScenarioIdentity {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$PhaseId,
        [Parameter(Mandatory)][ValidateSet('permanent-delete','delete-restore','stopped-project','host-concurrency','operation-recovery','ownership','vault')][string]$Scenario
    )
    if($RunId.Length -gt 128 -or $RunId -cnotmatch '\A(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z'){
        throw 'Nested scenario RunId failed ownership validation.'
    }
    $expectedPhase=$Scenario.ToUpperInvariant()
    if($PhaseId -cne $expectedPhase){throw 'Nested scenario phase does not match its destructive scenario identity.'}
    $root="/tmp/devfleet-e2e/$RunId/$PhaseId"
    if($root -cnotmatch '\A/tmp/devfleet-e2e/(?:e2e|fullrelease)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*/[A-Z0-9]+(?:-[A-Z0-9]+)*\z'){
        throw 'Nested scenario root failed ownership validation.'
    }
    [pscustomobject]@{runId=$RunId;phaseId=$PhaseId;scenario=$Scenario;root=$root}
}

# Provider payloads cross JSON/ remoting boundaries as PSCustomObject,
# Hashtable, or OrderedDictionary. Keep lifecycle decisions independent of
# that representation and use these helpers at every trust boundary.
function Get-LifecycleProperty {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][string]$Name,[ref]$Found)
    $Found.Value=$false
    if($null -eq $Value){return $null}
    if($Value -is [System.Collections.IDictionary]){
        foreach($key in $Value.Keys){if([string]$key -ieq $Name){$Found.Value=$true;return $Value[$key]}}
        return $null
    }
    foreach($property in @($Value.PSObject.Properties)){if([string]$property.Name -ieq $Name){$Found.Value=$true;return $property.Value}}
    return $null
}
function Get-LifecyclePropertyNames {
    param([AllowNull()][object]$Value)
    if($null -eq $Value){return @()}
    if($Value -is [System.Collections.IDictionary]){return @($Value.Keys|ForEach-Object{[string]$_})}
    return @($Value.PSObject.Properties|ForEach-Object{[string]$_.Name})
}
function Test-LifecycleProperty {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][string]$Name)
    $found=$false;[void](Get-LifecycleProperty -Value $Value -Name $Name -Found ([ref]$found));return $found
}

function Get-DevFleetLifecycleRoleKind {
    param([Parameter(Mandatory)][string]$Role)
    switch -CaseSensitive ($Role) {
        'Primary / Desktop' { return 'Desktop' }
        'Laptop / Surrogate' { return 'Laptop' }
        default { throw "TERMINAL_FAILURE: unsupported product lifecycle role '$Role'." }
    }
}

function Get-DevFleetLifecycleStageMarkerPattern {
    param([string]$ExpectedComputeInstanceName,[string]$ExpectedVaultInstanceName)
    $substeps='multipass-resolved|isolation-verified|instance-present|instance-absent|instance-started|instance-launched|instance-ready|payload-transferred|payload-extracted'
    $alternatives=[Collections.Generic.List[string]]::new()
    $alternatives.Add('prereqs-(?:Desktop|Laptop)');$alternatives.Add('host-agent');$alternatives.Add('windows-tailscale')
    if($ExpectedComputeInstanceName -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){$alternatives.Add(('compute-{0}(?:-(?:{1}))?' -f [regex]::Escape($ExpectedComputeInstanceName),$substeps))}
    if($ExpectedVaultInstanceName -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){$alternatives.Add(('vault(?:-(?:{0}))?' -f $substeps))}
    return '^stage-(?:'+($alternatives -join '|')+')\.complete$'
}
function Test-DevFleetLifecycleStageMarkerName {
    param([Parameter(Mandatory)][string]$Name,[string]$ExpectedComputeInstanceName,[string]$ExpectedVaultInstanceName)
    return $Name -match (Get-DevFleetLifecycleStageMarkerPattern -ExpectedComputeInstanceName $ExpectedComputeInstanceName -ExpectedVaultInstanceName $ExpectedVaultInstanceName)
}

function Get-DevFleetProductObservationIdentity {
    param([Parameter(Mandatory)][object]$Context,[Parameter(Mandatory)][string]$Role)
    $roleKind=Get-DevFleetLifecycleRoleKind -Role $Role
    $workspaceFound=$false;$workspace=Get-LifecycleProperty $Context 'workspaceRoot' ([ref]$workspaceFound)
    if(-not $workspaceFound -or [string]::IsNullOrWhiteSpace([string]$workspace)){
        $runDirFound=$false;$runDir=Get-LifecycleProperty $Context 'runDir' ([ref]$runDirFound)
        if(-not $runDirFound -or [string]::IsNullOrWhiteSpace([string]$runDir)){throw 'TERMINAL_FAILURE: product compute identity has no workspace or run evidence root.'}
        $workspace=(Resolve-Path -LiteralPath (Join-Path ([string]$runDir) '..\..\..\..')).Path
    }else{$workspace=(Resolve-Path -LiteralPath ([string]$workspace)).Path}
    $configPath=Join-Path $workspace 'source\config\devfleet.config.json'
    $candidatePath=Join-Path $workspace 'CURRENT-CANDIDATE.json'
    if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw 'TERMINAL_FAILURE: exact candidate product configuration is missing.'}
    if(-not(Test-Path -LiteralPath $candidatePath -PathType Leaf)){throw 'TERMINAL_FAILURE: current candidate binding is missing.'}
    try{$candidate=Get-Content -LiteralPath $candidatePath -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'TERMINAL_FAILURE: current candidate binding is unreadable.'}
    if(-not [bool]$candidate.candidateIsCurrent -or [bool]$candidate.sourceChangedSinceCandidate -or [bool]$candidate.rebuildRequired -or [string]$candidate.shippingInputIdentity -cne [string]$candidate.candidateShippingInputIdentity){throw 'TERMINAL_FAILURE: current candidate binding does not authorize the product configuration.'}
    $configEntries=@($candidate.candidateShippingInputs|Where-Object{[string]$_.root -ceq 'source' -and ([string]$_.path -replace '\\','/') -ceq 'config/devfleet.config.json'})
    if($configEntries.Count -ne 1 -or [string]$configEntries[0].sha256 -notmatch '^[0-9a-f]{64}$'){throw 'TERMINAL_FAILURE: candidate product configuration inventory binding is missing or ambiguous.'}
    $configSha256=(Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($configSha256 -cne [string]$configEntries[0].sha256){throw 'TERMINAL_FAILURE: product configuration does not match the current candidate inventory.'}
    try{$config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'TERMINAL_FAILURE: exact candidate product configuration is unreadable.'}
    $primary=[string]$config.Primary.InstanceName;$failover=[string]$config.Failover.InstanceName;$vault=[string]$config.Vault.InstanceName
    foreach($entry in @([ordered]@{kind='Primary';name=$primary},[ordered]@{kind='Failover';name=$failover},[ordered]@{kind='Vault';name=$vault})){if([string]$entry.name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'){throw "TERMINAL_FAILURE: exact candidate $([string]$entry.kind) instance identity is missing or malformed."}}
    if(@(@($primary,$failover,$vault)|Select-Object -Unique).Count -ne 3){throw 'TERMINAL_FAILURE: candidate product instance identities are not unique.'}
    $contextConfigFound=$false;$contextConfig=Get-LifecycleProperty $Context 'config' ([ref]$contextConfigFound);$cleanupName=''
    if($contextConfigFound -and $contextConfig){$nestedFound=$false;$nested=Get-LifecycleProperty $contextConfig 'NestedLinux' ([ref]$nestedFound);if($nestedFound -and $nested){$cleanupFound=$false;$cleanupName=[string](Get-LifecycleProperty $nested 'Name' ([ref]$cleanupFound))}}
    if($cleanupName -and $cleanupName -in @($primary,$failover,$vault)){throw 'TERMINAL_FAILURE: product instance identity overlaps the harness cleanup identity.'}
    $compute=if($roleKind -ceq 'Desktop'){$primary}else{$failover};$vaultForRole=if($roleKind -ceq 'Laptop'){$vault}else{''}
    $targets=[Collections.Generic.List[object]]::new();$targets.Add([pscustomobject][ordered]@{instanceName=$compute;nodeRole=if($roleKind -ceq 'Desktop'){'primary'}else{'surrogate'};kind='compute'})
    if($vaultForRole){$targets.Add([pscustomobject][ordered]@{instanceName=$vaultForRole;nodeRole='vault';kind='vault'})}
    return [pscustomobject][ordered]@{role=$Role;roleKind=$roleKind;computeInstanceName=$compute;vaultInstanceName=$vaultForRole;targets=@($targets);candidateCommit=[string]$candidate.candidateGitCommit;shippingInputIdentity=[string]$candidate.shippingInputIdentity;configPath=$configPath;configSha256=$configSha256;cleanupInstanceName=$cleanupName}
}

function Get-DevFleetProductComputeInstanceName {
    param([Parameter(Mandatory)][object]$Context,[string]$Role='Primary / Desktop')
    return [string](Get-DevFleetProductObservationIdentity -Context $Context -Role $Role).computeInstanceName
}

function Resolve-DevFleetLifecycleStageMarkerObservation {
    param(
        [Parameter(Mandatory)][object]$Observation,
        [Parameter(Mandatory)][string]$AllowedPattern,
        [Parameter(Mandatory)][string]$ExpectedStageRole,
        [AllowEmptyString()][string]$TransactionId,
        [Parameter(Mandatory)][string]$PayloadSha256,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$InvocationStartUtc
    )
    $markersFound=$false;$markers=@(Get-LifecycleProperty $Observation 'stageMarkers' ([ref]$markersFound));if(-not $markersFound){$markers=@()}
    $errorsFound=$false;$existingErrors=@(Get-LifecycleProperty $Observation 'stageMarkerErrors' ([ref]$errorsFound));if(-not $errorsFound){$existingErrors=@()}
    $accepted=[Collections.Generic.List[object]]::new();$rejected=[Collections.Generic.List[object]]::new()
    foreach($existing in $existingErrors){$nameFound=$false;$name=[string](Get-LifecycleProperty $existing 'name' ([ref]$nameFound));$errorFound=$false;$detail=[string](Get-LifecycleProperty $existing 'error' ([ref]$errorFound));$rejected.Add([pscustomobject][ordered]@{name=if($nameFound){$name}else{''};error=if($errorFound -and $detail){$detail}else{'stage marker was rejected by the collector'}})}
    $start=[datetime]::MinValue;if(-not [datetime]::TryParse($InvocationStartUtc,[ref]$start)){throw 'TERMINAL_FAILURE: lifecycle invocation start is malformed.'};$start=$start.ToUniversalTime()
    foreach($marker in $markers){
        $nameFound=$false;$name=[string](Get-LifecycleProperty $marker 'name' ([ref]$nameFound));$reason=''
        if(-not $nameFound -or $name -notmatch $AllowedPattern){$reason='stage marker name is not allowlisted'}
        $values=[ordered]@{};foreach($field in @('transactionId','payloadSha256','action','role','stage','completedUtc')){$found=$false;$values[$field]=Get-LifecycleProperty $marker $field ([ref]$found);if(-not $found -and -not $reason){$reason='stage marker is malformed'}}
        $completed=[datetime]::MinValue;if(-not $reason -and (-not [datetime]::TryParse([string]$values.completedUtc,[ref]$completed) -or $completed.ToUniversalTime() -lt $start)){$reason='stage marker is stale, malformed, or not bound to the current lifecycle'}
        if(-not $reason -and (([string]$values.transactionId) -notmatch '^[0-9a-fA-F]{32}$' -or ([string]$values.payloadSha256) -cne $PayloadSha256 -or ([string]$values.action) -cne $Action -or ([string]$values.role) -cne $ExpectedStageRole -or ($TransactionId -and ([string]$values.transactionId) -cne $TransactionId) -or (([string]$values.stage)+'.complete') -cne $name)){$reason='stage marker is stale, malformed, or not bound to the current lifecycle'}
        if($reason){$rejected.Add([pscustomobject][ordered]@{name=$name;error=$reason});continue}
        $pathFound=$false;$path=[string](Get-LifecycleProperty $marker 'path' ([ref]$pathFound));$shaFound=$false;$sha=[string](Get-LifecycleProperty $marker 'sha256' ([ref]$shaFound));$lastWriteFound=$false;$lastWrite=[string](Get-LifecycleProperty $marker 'lastWriteUtc' ([ref]$lastWriteFound))
        $accepted.Add([pscustomobject][ordered]@{name=$name;path=if($pathFound){$path}else{''};transactionId=[string]$values.transactionId;payloadSha256=[string]$values.payloadSha256;action=[string]$values.action;role=[string]$values.role;stage=[string]$values.stage;completedUtc=$completed.ToUniversalTime().ToString('o');lastWriteUtc=if($lastWriteFound){$lastWrite}else{''};sha256=if($shaFound){$sha}else{''}})
    }
    $set={param($target,$name,$value)if($target -is [System.Collections.IDictionary]){$target[$name]=$value}else{$target|Add-Member -NotePropertyName $name -NotePropertyValue $value -Force}}
    &$set $Observation 'stageMarkers' @($accepted);&$set $Observation 'stageMarkerErrors' @($rejected)
    return $Observation
}

function Get-WpfFailureDescriptor {
    param([Parameter(Mandatory)][object]$Report)
    $errorFound=$false;$errorValue=Get-LifecycleProperty $Report 'error' ([ref]$errorFound)
    $classFound=$false;$classValue=Get-LifecycleProperty $Report 'failureClass' ([ref]$classFound)
    [pscustomobject]@{
        failureClass=if($classFound -and [string]$classValue){[string]$classValue}else{'UNCLASSIFIED_PRODUCT_FAILURE'}
        error=if($errorFound -and [string]$errorValue){[string]$errorValue}else{'WPF boundary returned no primary error.'}
    }
}

function Test-RebootBoundaryIdentity {
    param(
        [Parameter(Mandatory)][psobject]$PriorCheckpoint,
        [AllowNull()][psobject]$CurrentCheckpoint,
        [int]$MaxGeneration = 3
    )
    if (-not $CurrentCheckpoint) { return $false }
    foreach($required in @('checkpointGeneration','transactionId','action','role','payloadSha256','state')){if(-not (Test-LifecycleProperty -Value $CurrentCheckpoint -Name $required)){return $false}}
    # Exactly one product generation is allowed to authorize one reboot.  A
    # jump (for example 1 -> 3) is an ambiguous/foreign lifecycle and must
    # never be treated as a valid boundary.
    $found=$false;$currentGeneration=Get-LifecycleProperty $CurrentCheckpoint 'checkpointGeneration' ([ref]$found);if(-not $found){return $false};$found=$false;$priorGenerationValue=Get-LifecycleProperty $PriorCheckpoint 'checkpointGeneration' ([ref]$found);if(-not $found){return $false};$generation=0;$priorGeneration=0;if(-not [int]::TryParse([string]$currentGeneration,[ref]$generation)-or-not [int]::TryParse([string]$priorGenerationValue,[ref]$priorGeneration)){return $false}
    # checkpointGeneration -ne PriorCheckpoint.checkpointGeneration + 1 is
    # the fail-closed rule (expressed with parsed numeric values below).
    if ($generation -ne ($priorGeneration + 1)) { return $false }
    if ($generation -gt $MaxGeneration) { return $false }
    foreach ($name in @('transactionId','action','role','payloadSha256')) {
        $currentFound=$false;$currentValue=Get-LifecycleProperty $CurrentCheckpoint $name ([ref]$currentFound);$priorFound=$false;$priorValue=Get-LifecycleProperty $PriorCheckpoint $name ([ref]$priorFound);if(-not $currentFound -or -not $priorFound -or [string]$currentValue -cne [string]$priorValue) { return $false }
    }
    $found=$false;$state=Get-LifecycleProperty $CurrentCheckpoint 'state' ([ref]$found);return ($found -and [string]$state -eq 'waiting-for-reboot')
}

function ConvertTo-CanonicalLifecycleCheckpoint {
    param([AllowNull()][object]$Checkpoint)
    if(-not $Checkpoint){return $null}
    $hasCheckpointGeneration=Test-LifecycleProperty -Value $Checkpoint -Name 'checkpointGeneration'
    $hasGeneration=Test-LifecycleProperty -Value $Checkpoint -Name 'generation'
    if(-not $hasCheckpointGeneration -and -not $hasGeneration){return $null}
    $checkpointGeneration=0;$generation=0
    $found=$false;$checkpointGenerationValue=Get-LifecycleProperty $Checkpoint 'checkpointGeneration' ([ref]$found);if($hasCheckpointGeneration -and -not [int]::TryParse([string]$checkpointGenerationValue,[ref]$checkpointGeneration)){return $null}
    $found=$false;$generationValue=Get-LifecycleProperty $Checkpoint 'generation' ([ref]$found);if($hasGeneration -and -not [int]::TryParse([string]$generationValue,[ref]$generation)){return $null}
    if(-not $hasCheckpointGeneration){$checkpointGeneration=$generation}
    if(-not $hasGeneration){$generation=$checkpointGeneration}
    if($generation -ne $checkpointGeneration){return $null}
    $copy=[ordered]@{}
    if($Checkpoint -is [System.Collections.IDictionary]){foreach($key in $Checkpoint.Keys){$copy[[string]$key]=$Checkpoint[$key]}}else{foreach($property in $Checkpoint.PSObject.Properties){$copy[$property.Name]=$property.Value}}
    $copy.generation=$generation
    $copy.checkpointGeneration=$checkpointGeneration
    return [pscustomobject]$copy
}

function Test-NoActiveProductCheckpoint {
    param([AllowNull()][object]$Value,[int]$Depth=0,[System.Collections.Generic.HashSet[int]]$Seen,[string]$Path='root')
    if($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive -or $Value -is [datetime] -or $Value -is [guid]){return $true}
    if($Depth -gt 12){return $false}
    if(-not $Seen){$Seen=[System.Collections.Generic.HashSet[int]]::new()};$identity=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Value);if(-not $Seen.Add($identity)){return $false}
    # IDictionary (including [ordered] test/projection payloads) is enumerable,
    # but its entries are lifecycle fields rather than a signal-free list. Walk
    # entries by key so generation/checkpoint fields cannot be hidden, while
    # avoiding the false cycle reports caused by enumerating dictionary views.
    if($Value -is [System.Collections.IDictionary]){
        foreach($entry in $Value.GetEnumerator()){
            $lower=([string]$entry.Key).ToLowerInvariant();$item=$entry.Value;$childPath=if($Path -eq 'root'){([string]$entry.Key)}else{"$Path.$([string]$entry.Key)"}
            if($lower -eq 'rawactivelifecyclesignals' -and $item -and @($item).Count -gt 0){foreach($signal in @($item)){$kindFound=$false;$kind=Get-LifecycleProperty $signal 'kind' ([ref]$kindFound);$pathFound=$false;$signalPath=Get-LifecycleProperty $signal 'path' ([ref]$pathFound);$valueFound=$false;$signalValue=Get-LifecycleProperty $signal 'value' ([ref]$valueFound);$zero=0;$benign=($kindFound -and [string]$kind -ieq 'checkpointgeneration' -and $pathFound -and [string]$signalPath -eq 'progress.checkpointGeneration' -and [int]::TryParse([string]$signalValue,[ref]$zero) -and $zero -eq 0 -and [string]$signalValue -match '^0$');if(-not $benign){return $false}}}
            if($lower -eq 'checkpoint' -and $null -ne $item){return $false}
            if($lower -eq 'checkpointpresent' -and [bool]$item){return $false}
            if($lower -in @('checkpointgeneration','generation')){$zeroValue=0;$zeroAllowed=($lower -eq 'checkpointgeneration' -and ($Path -eq 'progress' -or $Path -match '\.progress$') -and [int]::TryParse([string]$item,[ref]$zeroValue) -and $zeroValue -eq 0 -and [string]$item -match '^0$');if(-not $zeroAllowed){return $false}}
            if($lower -eq 'state' -and [string]$item -ieq 'waiting-for-reboot'){return $false}
            if($lower -in @('installledger','ownershipledger','installstate','ownership','receipt')){continue}
            $childSeen=[System.Collections.Generic.HashSet[int]]::new($Seen);if(-not (Test-NoActiveProductCheckpoint -Value $item -Depth ($Depth+1) -Seen $childSeen -Path $childPath)){return $false}
        }
        return $true
    }
    if($Value -is [System.Collections.IEnumerable]){foreach($item in $Value){$childSeen=[System.Collections.Generic.HashSet[int]]::new($Seen);if(-not (Test-NoActiveProductCheckpoint -Value $item -Depth ($Depth+1) -Seen $childSeen -Path ($Path+'[]'))){return $false}};return $true}
    foreach($property in @($Value.PSObject.Properties)){
        $name=[string]$property.Name;$item=$property.Value;$lower=$name.ToLowerInvariant()
        if($lower -eq 'rawactivelifecyclesignals' -and $item -and @($item).Count -gt 0){foreach($signal in @($item)){$kindFound=$false;$kind=Get-LifecycleProperty $signal 'kind' ([ref]$kindFound);$pathFound=$false;$signalPath=Get-LifecycleProperty $signal 'path' ([ref]$pathFound);$valueFound=$false;$signalValue=Get-LifecycleProperty $signal 'value' ([ref]$valueFound);$zero=0;$benign=($kindFound -and [string]$kind -ieq 'checkpointgeneration' -and $pathFound -and [string]$signalPath -eq 'progress.checkpointGeneration' -and [int]::TryParse([string]$signalValue,[ref]$zero) -and $zero -eq 0 -and [string]$signalValue -match '^0$');if(-not $benign){return $false}}}
        if($lower -eq 'checkpoint' -and $null -ne $item){return $false}
        if($lower -eq 'checkpointpresent' -and [bool]$item){return $false}
        if($lower -in @('checkpointgeneration','generation')){
            $zeroValue=0;$zeroAllowed=($lower -eq 'checkpointgeneration' -and ($Path -eq 'progress' -or $Path -match '\.progress$') -and [int]::TryParse([string]$item,[ref]$zeroValue) -and $