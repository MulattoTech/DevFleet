# DevFleet source part 085

Full-source UTF-8 byte interval [3906000, 3952500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 775edc8a753cf7cc7dc2b6532649db877f2a52c92c525c3883e9c958535fd757

<!-- BEGIN SOURCE SLICE -->
ction == "restore-transfer":
            command.extend(["transfer-copy", deployment_id, source_host_id])
        timeout = 3600
    completed = _run_child(command, timeout)
    if completed.returncode:
        if completed.returncode == 124:
            error, error_code = "Vault operation timed out.", "vault-operation-timeout"
        elif completed.returncode == 75:
            error, error_code = "Another Vault operation is already in progress.", "vault-operation-busy"
        elif completed.returncode == 5 and action.startswith("restore-"):
            error, error_code = "Vault restore failed its safety checks.", "restore-safety-conflict"
        else:
            error, error_code = "Vault operation failed.", "vault-operation-failed"
        return {
            "ok": False,
            "error": error,
            "error_code": error_code,
            "exit_code": int(completed.returncode),
        }
    if action == "backup":
        # The root-owned fixed child is authoritative: it exits nonzero whenever
        # restic fails.  latest.json remains dashboard telemetry and is deliberately
        # not an authorization receipt because devfleet-control can write it.
        return {
            "ok": True,
            "action": action,
            "local_backup_status": "verified",
            "vault_upload_status": "verified",
            "durability_level": "vault",
        }
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        return {"ok": False, "error": "Vault restore receipt is invalid.", "exit_code": 5}
    target = Path(lines[0])
    if action in {"restore-copy", "restore-transfer"}:
        expected_name = re.fullmatch(
            re.escape(_recovered_prefix(project)) + r"[0-9]{8}-[0-9]{6}-[0-9a-f]{8}",
            target.name,
        )
        valid_target = target.parent == WORKSPACES and expected_name is not None
    else:
        return {"ok": False, "error": "Vault restore action is unsupported.", "exit_code": 2}
    if (
        not valid_target
        or not target.is_dir()
        or target.is_symlink()
        or not _restored_identity_matches(target, project, project_id, deployment_id, source_host_id)
    ):
        if action in {"restore-copy", "restore-transfer"}:
            _quarantine_invalid_copy(target, project)
        return {"ok": False, "error": "Vault restore target is invalid.", "exit_code": 5}
    receipt = {
        "ok": True,
        "action": action,
        "project": project,
        "project_id": project_id,
        "target": str(target),
    }
    if action == "restore-transfer":
        receipt["deployment_id"] = deployment_id
        receipt["source_host_id"] = source_host_id
    return receipt


def main() -> int:
    connection = socket.socket(fileno=os.dup(0))
    try:
        try:
            _assert_peer(connection)
            request = _receive_frame(connection)
            action, project, project_id, deployment_id, source_host_id = _parse_request(request)
            response = _run_fixed_operation(
                action, project, project_id, deployment_id, source_host_id
            )
        except (ProtocolError, OSError, KeyError) as exc:
            response = {"ok": False, "error": str(exc), "exit_code": 2}
        _send_frame(connection, response)
        return 0
    finally:
        connection.close()


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: source/linux/devfleet-vault-health

SHA256: aef4f5a6daa89f7a2e669a1e773e32e358801c242458b4a36da0e02769114763 | Bytes: 349 | Git mode: 100644

```
#!/usr/bin/env bash
set -u
printf 'Vault: '; hostname
printf 'Tailscale: '; tailscale status --json --peers=false 2>/dev/null | jq -r '.BackendState // "not-connected"' || true
printf 'rest-server: '; systemctl is-active rest-server
printf 'Disk: '; df -h /srv/restic | tail -n1
printf 'Repository bytes: '; du -sh /srv/restic 2>/dev/null | cut -f1

```


## FILE: source/linux/devfleet-vault-maintenance

SHA256: bd9c01d8bf3ae54bbeba5f37b23d7dedc7e0a4a0778559d9c388f1b085e0c073 | Bytes: 408 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
keep=${1:-90d}
[[ "$keep" =~ ^[0-9]+[dmy]$ ]] || { echo invalid retention >&2; exit 2; }
set -a; source /etc/rest-server/vault-admin.env; set +a
systemctl stop rest-server
trap 'systemctl start rest-server' EXIT
if [[ -d "$RESTIC_REPOSITORY" ]]; then
  restic forget --keep-within "$keep" --prune
  restic check
else
  echo 'No repository has been initialized yet.'
fi

```


## FILE: source/linux/devfleet-vault-request

SHA256: 245458f58ef1a87ffd19abe2d6e3112e812d9b4ca6151158658be5f32b563fbb | Bytes: 4720 | Git mode: 100644

```
#!/usr/bin/env python3
"""Bounded client for the DevFleet Vault broker."""

from __future__ import annotations

import json
import re
import socket
import struct
import sys


SOCKET_PATH = "/run/devfleet-vault-broker.sock"
MAX_REQUEST_BYTES = 4096
MAX_RESPONSE_BYTES = 16384
PROJECT_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{1,62}$")
PROJECT_ID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
HOST_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$")
SAFE_FAILURE_CODES = frozenset(
    {
        "restore-safety-conflict",
        "vault-operation-busy",
        "vault-operation-failed",
        "vault-operation-timeout",
    }
)


def _request_from_argv(argv: list[str]) -> dict[str, str]:
    if argv == ["backup"]:
        return {"action": "backup"}
    if len(argv) == 3 and argv[0] == "restore-copy":
        if not PROJECT_RE.fullmatch(argv[1]):
            raise ValueError("Project identity is invalid.")
        if not PROJECT_ID_RE.fullmatch(argv[2]):
            raise ValueError("Project ID is invalid.")
        return {"action": argv[0], "project": argv[1], "project_id": argv[2]}
    if len(argv) == 5 and argv[0] == "restore-transfer":
        if not PROJECT_RE.fullmatch(argv[1]):
            raise ValueError("Project identity is invalid.")
        if not PROJECT_ID_RE.fullmatch(argv[2]):
            raise ValueError("Project ID is invalid.")
        if not PROJECT_ID_RE.fullmatch(argv[3]):
            raise ValueError("Deployment ID is invalid.")
        if not HOST_ID_RE.fullmatch(argv[4]):
            raise ValueError("Source host identity is invalid.")
        return {
            "action": "restore-transfer",
            "project": argv[1],
            "project_id": argv[2],
            "deployment_id": argv[3],
            "source_host_id": argv[4],
        }
    raise ValueError(
        "Usage: devfleet-vault-request backup | restore-copy PROJECT PROJECT_ID | restore-transfer PROJECT PROJECT_ID "
        "DEPLOYMENT_ID SOURCE_HOST_ID"
    )


def _receive_exact(connection: socket.socket, count: int) -> bytes:
    value = b""
    while len(value) < count:
        chunk = connection.recv(count - len(value))
        if not chunk:
            raise RuntimeError("Vault broker response ended early.")
        value += chunk
    return value


def main(argv: list[str]) -> int:
    try:
        request = _request_from_argv(argv)
        encoded = json.dumps(request, separators=(",", ":"), sort_keys=True).encode("utf-8")
        if len(encoded) > MAX_REQUEST_BYTES:
            raise ValueError("Vault broker request exceeded its bound.")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(5)
            connection.connect(SOCKET_PATH)
            # The fixed child owns at most 3600 seconds, then the broker and its
            # service get bounded cleanup time before this client can time out.
            connection.settimeout(3690)
            connection.sendall(struct.pack("!I", len(encoded)) + encoded)
            connection.shutdown(socket.SHUT_WR)
            (length,) = struct.unpack("!I", _receive_exact(connection, 4))
            if length < 2 or length > MAX_RESPONSE_BYTES:
                raise RuntimeError("Vault broker response length is invalid.")
            response_bytes = _receive_exact(connection, length)
            if connection.recv(1):
                raise RuntimeError("Vault broker sent more than one response frame.")
        response = json.loads(response_bytes.decode("utf-8"))
        if not isinstance(response, dict) or response.get("ok") is not True:
            detail = response.get("error") if isinstance(response, dict) else "Invalid broker response."
            error_code = response.get("error_code") if isinstance(response, dict) else None
            exit_code = response.get("exit_code") if isinstance(response, dict) else None
            if (
                error_code in SAFE_FAILURE_CODES
                and isinstance(exit_code, int)
                and not isinstance(exit_code, bool)
                and -255 <= exit_code <= 255
                and exit_code != 0
            ):
                detail = f"{detail} [error_code={error_code}; exit_code={exit_code}]"
            print(str(detail or "Vault broker rejected the operation."), file=sys.stderr)
            return 1
        print(json.dumps(response, separators=(",", ":"), sort_keys=True))
        return 0
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

```


## FILE: source/linux/upgrade-compute.sh

SHA256: f754f18cf80416026dea3f0a0b37772b419751aaec0198fd914c1ab87d8b5aec | Bytes: 97 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
sudo bash "${1:?payload}/linux/bootstrap-compute.sh" "$1"

```


## FILE: source/pytest.ini

SHA256: 6a96ba0e2d5a8296fb90f474da9d2f0173d3e41eba18965513f711104155f913 | Bytes: 41 | Git mode: 100644

```
[pytest]
testpaths = tests
addopts = -ra

```


## FILE: source/templates/cpp-cmake/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/cpp-cmake/.ai-bridge/codexpro-project-instructions.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/cpp-cmake/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/cpp-cmake/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/cpp-cmake/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/cpp-cmake/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/cpp-cmake/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/cpp-cmake/.devcontainer/devcontainer.json

SHA256: 445934f639925a25401e37333f549c7f1a0cb1cbd7521b7ee6309da00f64e622 | Bytes: 209 | Git mode: 100644

```
{
  "name": "__PROJECT_NAME__",
  "dockerComposeFile": "../compose.yaml",
  "service": "dev",
  "workspaceFolder": "/workspaces/__PROJECT_SLUG__",
  "shutdownAction": "stopCompose",
  "remoteUser": "vscode"
}

```


## FILE: source/templates/cpp-cmake/.devfleet/bootstrap.sh

SHA256: 0c27aca8e0c1121a29c7384e5a262913033dc1db108cdac32a119ebce92b203a | Bytes: 116 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
echo "Preview template: install dependencies inside this project container."

```


## FILE: source/templates/cpp-cmake/.devfleet/codexpro-bootstrap.sh

SHA256: 18459cba289cd6d0dd94081388234128aff3b7ac8e3609488569764af30ede0b | Bytes: 2254 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
root=$(pwd -P)
workspace_root=${DEVFLEET_WORKSPACES_ROOT:-/workspaces}
[[ "$workspace_root" == /* && "$workspace_root" != */ ]] || { echo 'DEVFLEET_WORKSPACES_ROOT must be an absolute directory.' >&2; exit 2; }
[[ "$root" == "$workspace_root"/* ]] || { echo "CodexPro root must be under $workspace_root." >&2; exit 2; }
project_rel=${root#"$workspace_root"/}
[[ "$project_rel" != */* && -n "$project_rel" ]] || { echo 'CodexPro root must identify one project.' >&2; exit 2; }
runtime="$root/.devfleet/runtime"; bridge="$root/.ai-bridge/local-agent"; mkdir -p "$runtime" "$bridge/logs"
log="$runtime/codexpro-bootstrap.log"; status="$runtime/codexpro-status.json"; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
health_url=${DEVFLEET_CODEXPRO_HEALTH_URL:-http://127.0.0.1:8787/healthz}
write_status(){ python3 - "$status" "$1" "$2" "$now" <<'PY2'
import json,sys
p,state,msg,now=sys.argv[1:];open(p,'w').write(json.dumps({'state':state,'healthy':state=='healthy','message':msg,'updated_at':now},indent=2)+'\n')
PY2
}
if DEVFLEET_CODEXPRO_HEALTH_URL="$health_url" python3 - <<'PY2' >/dev/null 2>&1
import urllib.request
import os
urllib.request.urlopen(os.environ['DEVFLEET_CODEXPRO_HEALTH_URL'],timeout=2)
PY2
then write_status healthy 'CodexPro loopback health endpoint is responding.'; echo 'CodexPro is already healthy.' | tee -a "$log"; exit 0; fi
if ! command -v codexpro >/dev/null 2>&1; then write_status unavailable 'CodexPro executable is not installed in this project container.'; echo 'CodexPro is unavailable. Install it using your verified private/local installation source, then rerun this hook. No credential is embedded.' | tee -a "$log"; exit 0; fi
export CODEXPRO_TOOL_CARDS=${CODEXPRO_TOOL_CARDS:-1}
( codexpro start >>"$log" 2>&1 & )
sleep 2
if DEVFLEET_CODEXPRO_HEALTH_URL="$health_url" python3 - <<'PY2' >/dev/null 2>&1
import urllib.request
import os
urllib.request.urlopen(os.environ['DEVFLEET_CODEXPRO_HEALTH_URL'],timeout=2)
PY2
then write_status healthy 'CodexPro started successfully.'; exit 0; fi
write_status authorization-required 'CodexPro is installed but not healthy; inspect the log for authorization or configuration requirements.'
echo "CodexPro did not become healthy. Review $log"; exit 0

```


## FILE: source/templates/cpp-cmake/.devfleet/codexpro-profile.json

SHA256: c7e30a70af40b8cbc64cd6db3f091ee908a8ccc70549780005b797fc9108fb44 | Bytes: 397 | Git mode: 100644

```
{
  "defaultRoot": "/workspaces/__PROJECT_SLUG__",
  "allowedRoots": [
    "/workspaces/__PROJECT_SLUG__"
  ],
  "authEnabled": true,
  "bashMode": "full",
  "bashTranscript": "full",
  "writeMode": "workspace",
  "toolMode": "full",
  "inheritEnv": false,
  "contextDir": ".ai-bridge",
  "maxReadBytes": 180000,
  "maxWriteBytes": 1000000,
  "maxOutputBytes": 120000,
  "maxSearchResults": 200
}

```


## FILE: source/templates/cpp-cmake/.devfleet/codexpro.env.example

SHA256: 86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30 | Bytes: 90 | Git mode: 100644

```
# Verified optional UI setting only. Do not store credentials here.
CODEXPRO_TOOL_CARDS=1

```


## FILE: source/templates/cpp-cmake/.devfleet/health-check.sh

SHA256: 04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311 | Bytes: 83 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -d .devfleet
./.devfleet/smoke-test.sh

```


## FILE: source/templates/cpp-cmake/.devfleet/project-tools.json

SHA256: cd4d78db29dabe909a6929b0a1dfb066d98d2b80bd59e490c1bd10a4fd6a0cb5 | Bytes: 297 | Git mode: 100644

```
{
  "id": "cpp-cmake",
  "language": "cpp",
  "framework": "cmake",
  "maturity": "preview",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "true",
  "lint_command": "true",
  "test_command": "./.devfleet/smoke-test.sh",
  "health_command": "./.devfleet/health-check.sh"
}

```


## FILE: source/templates/cpp-cmake/.devfleet/smoke-test.sh

SHA256: 95f6ec94983aec4d5f36460826e0d26aac2db481c25966728953d2f566f6cd31 | Bytes: 214 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -f README.md
test -f compose.yaml
test -f .devcontainer/devcontainer.json
test -f .devfleet/project.json -o -f .devfleet/template.json
echo "Template smoke test passed."

```


## FILE: source/templates/cpp-cmake/.devfleet/template.json

SHA256: 35339bcf595d1b776736804128076e41c74b343bdeb3241fda0da8921ee8c71d | Bytes: 637 | Git mode: 100644

```
{
  "id": "cpp-cmake",
  "language": "cpp",
  "framework": "cmake",
  "maturity": "preview",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "true",
  "lint_command": "true",
  "test_command": "./.devfleet/smoke-test.sh",
  "health_command": "./.devfleet/health-check.sh",
  "start_command": "docker compose up -d --build",
  "stop_command": "docker compose down --remove-orphans",
  "restart_command": "docker compose restart",
  "rebuild_command": "docker compose build && docker compose up -d",
  "logs_command": "docker compose logs",
  "codexpro_command": "./.devfleet/codexpro-bootstrap.sh"
}
```


## FILE: source/templates/cpp-cmake/.editorconfig

SHA256: 05f9463d683e5957ca2f7cad77a5fec2986298b1ea3c6ca314174805fa1aff44 | Bytes: 137 | Git mode: 100644

```
root = true
[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 2
[*.py]
indent_size = 4

```


## FILE: source/templates/cpp-cmake/.gitignore

SHA256: 8844bf55ab9a454e01fbeec045b6747de22e56d73b2e5dbb6dfd27228e84c7fe | Bytes: 133 | Git mode: 100644

```
.devfleet/runtime/
.ai-bridge/local-agent/
.env
.env.*
node_modules/
.venv/
__pycache__/
dist/
build/
target/
.next/
coverage/
*.log

```


## FILE: source/templates/cpp-cmake/README.md

SHA256: 228588bd8182b53ca0721b1342685e32c7afcb7f681cb513b87ab3e705cc8850 | Bytes: 358 | Git mode: 100644

```
# __PROJECT_NAME__

Language: `cpp`  
Framework: `cmake`  
DevFleet profile: `__PROJECT_PROFILE__`

Generated by DevFleet. Run `./.devfleet/bootstrap.sh`, `./.devfleet/health-check.sh`, and the test command recorded in `.devfleet/project.json`. Language selection follows Dylan's engineering preferences and is not presented as a scientific model benchmark.

```


## FILE: source/templates/cpp-cmake/compose.yaml

SHA256: 0aa515e43796e07025f2cfdcb121e0d6edad4cfea877399c65fa066a4ced6231 | Bytes: 468 | Git mode: 100644

```
services:
  dev:
    image: mcr.microsoft.com/devcontainers/cpp:1-ubuntu-24.04
    user: "vscode"
    working_dir: /workspaces/__PROJECT_SLUG__
    command: sh -lc "sleep infinity"
    init: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    volumes:
      - .:/workspaces/__PROJECT_SLUG__:cached
    healthcheck:
      test: ["CMD-SHELL", "test -d /workspaces/__PROJECT_SLUG__"]
      interval: 30s
      timeout: 5s
      retries: 3

```


## FILE: source/templates/cpp-cmake/docs/architecture.md

SHA256: 7f2df08e2676a8a97abf899c5b7c2caa96209ba308a6fde7c1fd527cb09fea23 | Bytes: 326 | Git mode: 100644

```
# Architecture

- Language: `cpp`
- Framework: `cmake`
- Scale/intent/testing/profile are recorded in `.devfleet/project.json`.
- Rationale: selected from Dylan's DevFleet engineering preferences; this is not a scientific model benchmark.
- Source remains in one canonical checkout; use Git worktrees for concurrent branches.

```


## FILE: source/templates/data-r/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/data-r/.ai-bridge/codexpro-project-instructions.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/data-r/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/data-r/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/data-r/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/data-r/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/data-r/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/data-r/.devcontainer/devcontainer.json

SHA256: 31743d0b403e9a20eb3dffd87c5033c90bd0c28a0f522633bef1b18235b2c065 | Bytes: 207 | Git mode: 100644

```
{
  "name": "__PROJECT_NAME__",
  "dockerComposeFile": "../compose.yaml",
  "service": "dev",
  "workspaceFolder": "/workspaces/__PROJECT_SLUG__",
  "shutdownAction": "stopCompose",
  "remoteUser": "root"
}

```


## FILE: source/templates/data-r/.devfleet/bootstrap.sh

SHA256: 0c27aca8e0c1121a29c7384e5a262913033dc1db108cdac32a119ebce92b203a | Bytes: 116 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
echo "Preview template: install dependencies inside this project container."

```


## FILE: source/templates/data-r/.devfleet/codexpro-bootstrap.sh

SHA256: 18459cba289cd6d0dd94081388234128aff3b7ac8e3609488569764af30ede0b | Bytes: 2254 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
root=$(pwd -P)
workspace_root=${DEVFLEET_WORKSPACES_ROOT:-/workspaces}
[[ "$workspace_root" == /* && "$workspace_root" != */ ]] || { echo 'DEVFLEET_WORKSPACES_ROOT must be an absolute directory.' >&2; exit 2; }
[[ "$root" == "$workspace_root"/* ]] || { echo "CodexPro root must be under $workspace_root." >&2; exit 2; }
project_rel=${root#"$workspace_root"/}
[[ "$project_rel" != */* && -n "$project_rel" ]] || { echo 'CodexPro root must identify one project.' >&2; exit 2; }
runtime="$root/.devfleet/runtime"; bridge="$root/.ai-bridge/local-agent"; mkdir -p "$runtime" "$bridge/logs"
log="$runtime/codexpro-bootstrap.log"; status="$runtime/codexpro-status.json"; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
health_url=${DEVFLEET_CODEXPRO_HEALTH_URL:-http://127.0.0.1:8787/healthz}
write_status(){ python3 - "$status" "$1" "$2" "$now" <<'PY2'
import json,sys
p,state,msg,now=sys.argv[1:];open(p,'w').write(json.dumps({'state':state,'healthy':state=='healthy','message':msg,'updated_at':now},indent=2)+'\n')
PY2
}
if DEVFLEET_CODEXPRO_HEALTH_URL="$health_url" python3 - <<'PY2' >/dev/null 2>&1
import urllib.request
import os
urllib.request.urlopen(os.environ['DEVFLEET_CODEXPRO_HEALTH_URL'],timeout=2)
PY2
then write_status healthy 'CodexPro loopback health endpoint is responding.'; echo 'CodexPro is already healthy.' | tee -a "$log"; exit 0; fi
if ! command -v codexpro >/dev/null 2>&1; then write_status unavailable 'CodexPro executable is not installed in this project container.'; echo 'CodexPro is unavailable. Install it using your verified private/local installation source, then rerun this hook. No credential is embedded.' | tee -a "$log"; exit 0; fi
export CODEXPRO_TOOL_CARDS=${CODEXPRO_TOOL_CARDS:-1}
( codexpro start >>"$log" 2>&1 & )
sleep 2
if DEVFLEET_CODEXPRO_HEALTH_URL="$health_url" python3 - <<'PY2' >/dev/null 2>&1
import urllib.request
import os
urllib.request.urlopen(os.environ['DEVFLEET_CODEXPRO_HEALTH_URL'],timeout=2)
PY2
then write_status healthy 'CodexPro started successfully.'; exit 0; fi
write_status authorization-required 'CodexPro is installed but not healthy; inspect the log for authorization or configuration requirements.'
echo "CodexPro did not become healthy. Review $log"; exit 0

```


## FILE: source/templates/data-r/.devfleet/codexpro-profile.json

SHA256: c7e30a70af40b8cbc64cd6db3f091ee908a8ccc70549780005b797fc9108fb44 | Bytes: 397 | Git mode: 100644

```
{
  "defaultRoot": "/workspaces/__PROJECT_SLUG__",
  "allowedRoots": [
    "/workspaces/__PROJECT_SLUG__"
  ],
  "authEnabled": true,
  "bashMode": "full",
  "bashTranscript": "full",
  "writeMode": "workspace",
  "toolMode": "full",
  "inheritEnv": false,
  "contextDir": ".ai-bridge",
  "maxReadBytes": 180000,
  "maxWriteBytes": 1000000,
  "maxOutputBytes": 120000,
  "maxSearchResults": 200
}

```


## FILE: source/templates/data-r/.devfleet/codexpro.env.example

SHA256: 86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30 | Bytes: 90 | Git mode: 100644

```
# Verified optional UI setting only. Do not store credentials here.
CODEXPRO_TOOL_CARDS=1

```


## FILE: source/templates/data-r/.devfleet/health-check.sh

SHA256: 04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311 | Bytes: 83 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -d .devfleet
./.devfleet/smoke-test.sh

```


## FILE: source/templates/data-r/.devfleet/project-tools.json

SHA256: 808c6a308c2e68d82e7f1c74e27f98b5dbf5903e1bfac70b9f777c890ca22ba2 | Bytes: 293 | Git mode: 100644

```
{
  "id": "data-r",
  "language": "r",
  "framework": "base-r",
  "maturity": "preview",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "true",
  "lint_command": "true",
  "test_command": "./.devfleet/smoke-test.sh",
  "health_command": "./.devfleet/health-check.sh"
}

```


## FILE: source/templates/data-r/.devfleet/smoke-test.sh

SHA256: 95f6ec94983aec4d5f36460826e0d26aac2db481c25966728953d2f566f6cd31 | Bytes: 214 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -f README.md
test -f compose.yaml
test -f .devcontainer/devcontainer.json
test -f .devfleet/project.json -o -f .devfleet/template.json
echo "Template smoke test passed."

```


## FILE: source/templates/data-r/.devfleet/template.json

SHA256: 1f3b10b31593c3747515102994c7414598bcffe28e47ac08418aa9eff572b748 | Bytes: 633 | Git mode: 100644

```
{
  "id": "data-r",
  "language": "r",
  "framework": "base-r",
  "maturity": "preview",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "true",
  "lint_command": "true",
  "test_command": "./.devfleet/smoke-test.sh",
  "health_command": "./.devfleet/health-check.sh",
  "start_command": "docker compose up -d --build",
  "stop_command": "docker compose down --remove-orphans",
  "restart_command": "docker compose restart",
  "rebuild_command": "docker compose build && docker compose up -d",
  "logs_command": "docker compose logs",
  "codexpro_command": "./.devfleet/codexpro-bootstrap.sh"
}
```


## FILE: source/templates/data-r/.editorconfig

SHA256: 05f9463d683e5957ca2f7cad77a5fec2986298b1ea3c6ca314174805fa1aff44 | Bytes: 137 | Git mode: 100644

```
root = true
[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 2
[*.py]
indent_size = 4

```


## FILE: source/templates/data-r/.gitignore

SHA256: 8844bf55ab9a454e01fbeec045b6747de22e56d73b2e5dbb6dfd27228e84c7fe | Bytes: 133 | Git mode: 100644

```
.devfleet/runtime/
.ai-bridge/local-agent/
.env
.env.*
node_modules/
.venv/
__pycache__/
dist/
build/
target/
.next/
coverage/
*.log

```


## FILE: source/templates/data-r/README.md

SHA256: ec91ebe76515639ed04056aa7dfe14f3c47c5c3c776de81f647565c4d6acfacd | Bytes: 357 | Git mode: 100644

```
# __PROJECT_NAME__

Language: `r`  
Framework: `base-r`  
DevFleet profile: `__PROJECT_PROFILE__`

Generated by DevFleet. Run `./.devfleet/bootstrap.sh`, `./.devfleet/health-check.sh`, and the test command recorded in `.devfleet/project.json`. Language selection follows Dylan's engineering preferences and is not presented as a scientific model benchmark.

```


## FILE: source/templates/data-r/compose.yaml

SHA256: 1c84cd5554f19af11ea76022af21546d1e08f6bb4abb34bf8ad42ec3b6009581 | Bytes: 434 | Git mode: 100644

```
services:
  dev:
    image: rocker/r-ver:4.4.2
    user: "root"
    working_dir: /workspaces/__PROJECT_SLUG__
    command: sh -lc "sleep infinity"
    init: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    volumes:
      - .:/workspaces/__PROJECT_SLUG__:cached
    healthcheck:
      test: ["CMD-SHELL", "test -d /workspaces/__PROJECT_SLUG__"]
      interval: 30s
      timeout: 5s
      retries: 3

```


## FILE: source/templates/data-r/docs/architecture.md

SHA256: 6cd72cb5a51cac627cba6256f617c70778cdb34113460b0fb596310a276240f8 | Bytes: 325 | Git mode: 100644

```
# Architecture

- Language: `r`
- Framework: `base-r`
- Scale/intent/testing/profile are recorded in `.devfleet/project.json`.
- Rationale: selected from Dylan's DevFleet engineering preferences; this is not a scientific model benchmark.
- Source remains in one canonical checkout; use Git worktrees for concurrent branches.

```


## FILE: source/templates/dotnet-service/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/dotnet-service/.ai-bridge/codexpro-project-instructions.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/dotnet-service/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/dotnet-service/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/dotnet-service/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/dotnet-service/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/dotnet-service/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/dotnet-service/.devcontainer/devcontainer.json

SHA256: 445934f639925a25401e37333f549c7f1a0cb1cbd7521b7ee6309da00f64e622 | Bytes: 209 | Git mode: 100644

```
{
  "name": "__PROJECT_NAME__",
  "dockerComposeFile": "../compose.yaml",
  "service": "dev",
  "workspaceFolder": "/workspaces/__PROJECT_SLUG__",
  "shutdownAction": "stopCompose",
  "remoteUser": "vscode"
}

```


## FILE: source/templates/dotnet-service/.devfleet/bootstrap.sh

SHA256: ec1e677581abb22ca7a86b4ef7e3c86708659f0784584daf6afb44125415a074 | Bytes: 54 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
dotnet restore

```


## FILE: source/templates/dotnet-service/.devfleet/codexpro-bootstrap.sh

SHA256: 18459cba289cd6d0dd94081388234128aff3b7ac8e3609488569764af30ede0b | Bytes: 2254 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
root=$(pwd -P)
workspace_root=${DEVFLEET_WORKSPACES_ROOT:-/workspaces}
[[ "$workspace_root" == /* && "$workspace_root" != */ ]] || { echo 'DEVFLEET_WORKSPACES_ROOT must be an absolute directory.' >&2; exit 2; }
[[ "$root" == "$workspace_root"/* ]] || { echo "CodexPro root must be under $workspace_root." >&2; exit 2; }
project_rel=${root#"$workspace_root"/}
[[ "$project_rel" != */* && -n "$project_rel" ]] || { echo 'CodexPro root must identify one project.' >&2; exit 2; }
runtime="$root/.devfleet/runtime"; bridge="$root/.ai-bridge/local-agent"; mkdir -p "$runtime" "$bridge/logs"
log="$runtime/codexpro-bootstrap.log"; status="$runtime/codexpro-status.json"; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
health_url=${DEVFLEET_CODEXPRO_HEALTH_URL:-http://127.0.0.1:8787/healthz}
write_status(){ python3 - "$status" "$1" "$2" "$now" <<'PY2'
import json,sys
p,state,msg,now=sys.argv[1:];open(p,'w').write(json.dumps({'state':state,'healthy':state=='healthy','message':msg,'updated_at':now},indent=2)+'\n')
PY2
}
if DEVFLEET_CODEXPRO_HEALTH_URL="$health_url" python3 - <<'PY2' >/dev/null 2>&1
import urllib.request
import os
urllib.request.urlopen(os.environ['DEVFLEET_CODEXPRO_HEALTH_URL'],timeout=2)
PY2
then write_status healthy 'CodexPro loopback health endpoint is responding.'; echo 'CodexPro is already healthy.' | tee -a "$log"; exit 0; fi
if ! command -v codexpro >/dev/null 2>&1; then write_status unavailable 'CodexPro executable is not installed in this project container.'; echo 'CodexPro is unavailable. Install it using your verified private/local installation source, then rerun this hook. No credential is embedded.' | tee -a "$log"; exit 0; fi
export CODEXPRO_TOOL_CARDS=${CODEXPRO_TOOL_CARDS:-1}
( codexpro start >>"$log" 2>&1 & )
sleep 2
if DEVFLEET_CODEXPRO_HEALTH_URL="$health_url" python3 - <<'PY2' >/dev/null 2>&1
import urllib.request
import os
urllib.request.urlopen(os.environ['DEVFLEET_CODEXPRO_HEALTH_URL'],timeout=2)
PY2
then write_status healthy 'CodexPro started successfully.'; exit 0; fi
write_status authorization-required 'CodexPro is installed but not healthy; inspect the log for authorization or configuration requirements.'
echo "CodexPro did not become healthy. Review $log"; exit 0

```


## FILE: source/templates/dotnet-service/.devfleet/codexpro-profile.json

SHA256: c7e30a70af40b8cbc64cd6db3f091ee908a8ccc70549780005b797fc9108fb44 | Bytes: 397 | Git mode: 100644

```
{
  "defaultRoot": "/workspaces/__PROJECT_SLUG__",
  "allowedRoots": [
    "/workspaces/__PROJECT_SLUG__"
  ],
  "authEnabled": true,
  "bashMode": "full",
  "bashTranscript": "full",
  "writeMode": "workspace",
  "toolMode": "full",
  "inheritEnv": false,
  "contextDir": ".ai-bridge",
  "maxReadBytes": 180000,
  "maxWriteBytes": 1000000,
  "maxOutputBytes": 120000,
  "maxSearchResults": 200
}

```


## FILE: source/templates/dotnet-service/.devfleet/codexpro.env.example

SHA256: 86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30 | Bytes: 90 | Git mode: 100644

```
# Verified optional UI setting only. Do not store credentials here.
CODEXPRO_TOOL_CARDS=1

```


## FILE: source/templates/dotnet-service/.devfleet/health-check.sh

SHA256: 04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311 | Bytes: 83 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -d .devfleet
./.devfleet/smoke-test.sh

```


## FILE: source/templates/dotnet-service/.devfleet/project-tools.json

SHA256: 26721a1313e9b66ca20366a2046829a6e9525653ad509d68f5349c5ccd7c5e4d | Bytes: 350 | Git mode: 100644

```
{
  "id": "dotnet-service",
  "language": "csharp",
  "framework": "aspnet-core",
  "maturity": "core",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "dotnet format",
  "lint_command": "dotnet build --no-restore -warnaserror",
  "test_command": "dotnet test --no-restore",
  "health_command": "./.devfleet/health-check.sh"
}

```


## FILE: source/templates/dotnet-service/.devfleet/smoke-test.sh

SHA256: 95f6ec94983aec4d5f36460826e0d26aac2db481c25966728953d2f566f6cd31 | Bytes: 214 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -f README.md
test -f compose.yaml
test -f .devcontainer/devcontainer.json
test -f .devfleet/project.json -o -f .devfleet/template.json
echo "Template smoke test passed."

```


## FILE: source/templates/dotnet-service/.devfleet/template.json

SHA256: d1aaee39b5fa228654d1e562218d09793f7b0b42f6b2cb684b5c20a8bdb19f09 | Bytes: 690 | Git mode: 100644

```
{
  "id": "dotnet-service",
  "language": "csharp",
  "framework": "aspnet-core",
  "maturity": "core",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "dotnet format",
  "lint_command": "dotnet build --no-restore -warnaserror",
  "test_command": "dotnet test --no-restore",
  "health_command": "./.devfleet/health-check.sh",
  "start_command": "docker compose up -d --build",
  "stop_command": "docker compose down --remove-orphans",
  "restart_command": "docker compose restart",
  "rebuild_command": "docker compose build && docker compose up -d",
  "logs_command": "docker compose logs",
  "codexpro_command": "./.devfleet/codexpro-bootstrap.sh"
}
```


## FILE: source/templates/dotnet-service/.editorconfig

SHA256: 05f9463d683e5957ca2f7cad77a5fec2986298b1ea3c6ca314174805fa1aff44 | Bytes: 137 | Git mode: 100644

```
root = true
[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 2
[*.py]
indent_size = 4

```


## FILE: source/templates/dotnet-service/.gitignore

SHA256: 8844bf55ab9a454e01fbeec045b6747de22e56d73b2e5dbb6dfd27228e84c7fe | Bytes: 133 | Git mode: 100644

```
.devfleet/runtime/
.ai-bridge/local-agent/
.env
.env.*
node_modules/
.venv/
__pycache__/
dist/
build/
target/
.next/
coverage/
*.log

```


## FILE: source/templates/dotnet-service/README.md

SHA256: ebbdb3332b9556c2f914c704d8a0a5505ca9ef9c39d79b2d77f06773e8d040d4 | Bytes: 367 | Git mode: 100644

```
# __PROJECT_NAME__

Language: `csharp`  
Framework: `aspnet-core`  
DevFleet profile: `__PROJECT_PROFILE__`

Generated by DevFleet. Run `./.devfleet/bootstrap.sh`, `./.devfleet/health-check.sh`, and the test command recorded in `.devfleet/project.json`. Language selection follows Dylan's engineering preferences and is not presented as a scientific model benchmark.

```


## FILE: source/templates/dotnet-service/compose.yaml

SHA256: 27689cd9a2e39c77afbea11502beea583dbb5f7cb4f88038b7e6e3f88f9aee84 | Bytes: 512 | Git mode: 100644

```
services:
  dev:
    image: mcr.microsoft.com/devcontainers/dotnet:1-8.0-bookworm
    user: "vscode"
    working_dir: /workspaces/__PROJECT_SLUG__
    command: sh -lc "sleep infinity"
    init: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    volumes:
      - .:/workspaces/__PROJECT_SLUG__:cached
    ports:
      - "127.0.0.1:8080:8080"
    healthcheck:
      test: ["CMD-SHELL", "test -d /workspaces/__PROJECT_SLUG__"]
      interval: 30s
      timeout: 5s
      retries: 3

```


## FILE: source/templates/dotnet-service/docs/architecture.md

SHA256: f8838fa8b3ba83bd35d7e14664bdfe8cfea7adbd3292b689e2550908d388eb8b | Bytes: 335 | Git mode: 100644

```
# Architecture

- Language: `csharp`
- Framework: `aspnet-core`
- Scale/intent/testing/profile are recorded in `.devfleet/project.json`.
- Rationale: selected from Dylan's DevFleet engineering preferences; this is not a scientific model benchmark.
- Source remains in one canonical checkout; use Git worktrees for concurrent branches.

```


## FILE: source/templates/dotnet-service/src/App/App.csproj

SHA256: cd8b60226e846d3819569814d937322bc3b4d055cb2cf2ef1a9fb9f345786f60 | Bytes: 186 | Git mode: 100644

```
<Project Sdk="Microsoft.NET.Sdk.Web"><PropertyGroup><TargetFramework>net8.0</TargetFramework><Nullable>enable</Nullable><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>

```


## FILE: source/templates/dotnet-service/src/App/Program.cs

SHA256: f899d19a0c23035a24153fa695bd5cf9043ff229ae0536dbb1ddceb2084da6dc | Bytes: 134 | Git mode: 100644

```
var builder=WebApplication.CreateBuilder(args);var app=builder.Build();app.MapGet("/healthz",()=>Results.Ok(new{ok=true}));app.Run();

```


## FILE: source/templates/dotnet-service/tests/Smoke/Smoke.csproj

SHA256: 66340917c9ec77aec68f1e42cbf5180ee73c216f16236a9053d2a4f6afc05da0 | Bytes: 359 | Git mode: 100644

```
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework><IsTestProject>true</IsTestProject></PropertyGroup><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*"/><PackageReference Include="xunit" Version="2.*"/><PackageReference Include="xunit.runner.visualstudio" Version="2.*"/></ItemGroup></Project>

```


## FILE: source/templates/dotnet-service/tests/Smoke/SmokeTest.cs

SHA256: 051b9b53201d40216dc80ea93710787582710326e80459bd4d2eb5bf96bd1712 | Bytes: 88 | Git mode: 100644

```
public class SmokeTest{[Xunit.Fact]public void MathWorks()=>Xunit.Assert.Equal(5,2+3);}

```


## FILE: source/templates/elixir-phoenix/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/elixir-phoenix/.ai-bridge/codexpro-project-instructions.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant