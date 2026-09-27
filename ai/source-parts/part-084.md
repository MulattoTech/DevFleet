# DevFleet source part 084

Full-source UTF-8 byte interval [3859500, 3906000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 87e685bf608b5e457df00c6d14136deefdba2d3c906a303b47580e146abc8c97

<!-- BEGIN SOURCE SLICE -->
handoff before context becomes crowded.

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
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/elixir-phoenix/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/elixir-phoenix/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/elixir-phoenix/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/elixir-phoenix/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/elixir-phoenix/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/elixir-phoenix/.devcontainer/devcontainer.json

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


## FILE: source/templates/elixir-phoenix/.devfleet/bootstrap.sh

SHA256: 0c27aca8e0c1121a29c7384e5a262913033dc1db108cdac32a119ebce92b203a | Bytes: 116 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
echo "Preview template: install dependencies inside this project container."

```


## FILE: source/templates/elixir-phoenix/.devfleet/codexpro-bootstrap.sh

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


## FILE: source/templates/elixir-phoenix/.devfleet/codexpro-profile.json

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


## FILE: source/templates/elixir-phoenix/.devfleet/codexpro.env.example

SHA256: 86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30 | Bytes: 90 | Git mode: 100644

```
# Verified optional UI setting only. Do not store credentials here.
CODEXPRO_TOOL_CARDS=1

```


## FILE: source/templates/elixir-phoenix/.devfleet/health-check.sh

SHA256: 04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311 | Bytes: 83 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -d .devfleet
./.devfleet/smoke-test.sh

```


## FILE: source/templates/elixir-phoenix/.devfleet/project-tools.json

SHA256: 9aa617fd91e8ba76c0289c8eef2f41033531e497c1f7020aeebc779140215e32 | Bytes: 307 | Git mode: 100644

```
{
  "id": "elixir-phoenix",
  "language": "elixir",
  "framework": "phoenix",
  "maturity": "preview",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "true",
  "lint_command": "true",
  "test_command": "./.devfleet/smoke-test.sh",
  "health_command": "./.devfleet/health-check.sh"
}

```


## FILE: source/templates/elixir-phoenix/.devfleet/smoke-test.sh

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


## FILE: source/templates/elixir-phoenix/.devfleet/template.json

SHA256: ada116c5fb800a6fa9db09b1c39944563feff9a26600d79ec81120e181ff799e | Bytes: 647 | Git mode: 100644

```
{
  "id": "elixir-phoenix",
  "language": "elixir",
  "framework": "phoenix",
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


## FILE: source/templates/elixir-phoenix/.editorconfig

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


## FILE: source/templates/elixir-phoenix/.gitignore

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


## FILE: source/templates/elixir-phoenix/README.md

SHA256: 86ac907798e2475ece41e4da3add7768efcbd3d7b749ae764028af6d18556446 | Bytes: 363 | Git mode: 100644

```
# __PROJECT_NAME__

Language: `elixir`  
Framework: `phoenix`  
DevFleet profile: `__PROJECT_PROFILE__`

Generated by DevFleet. Run `./.devfleet/bootstrap.sh`, `./.devfleet/health-check.sh`, and the test command recorded in `.devfleet/project.json`. Language selection follows Dylan's engineering preferences and is not presented as a scientific model benchmark.

```


## FILE: source/templates/elixir-phoenix/compose.yaml

SHA256: c2d252c95c1ba4c3349ebed46c7e0cc154558a18b6daa7c3cbfa9623e9999dda | Bytes: 510 | Git mode: 100644

```
services:
  dev:
    image: mcr.microsoft.com/devcontainers/base:1-ubuntu-24.04
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
      - "127.0.0.1:4000:4000"
    healthcheck:
      test: ["CMD-SHELL", "test -d /workspaces/__PROJECT_SLUG__"]
      interval: 30s
      timeout: 5s
      retries: 3

```


## FILE: source/templates/elixir-phoenix/docs/architecture.md

SHA256: 298034dab1c6a31f18a15c36c070df7f1e1abf1c9fcf3de0a366eed366d74f43 | Bytes: 331 | Git mode: 100644

```
# Architecture

- Language: `elixir`
- Framework: `phoenix`
- Scale/intent/testing/profile are recorded in `.devfleet/project.json`.
- Rationale: selected from Dylan's DevFleet engineering preferences; this is not a scientific model benchmark.
- Source remains in one canonical checkout; use Git worktrees for concurrent branches.

```


## FILE: source/templates/flutter/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/flutter/.ai-bridge/codexpro-project-instructions.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/flutter/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/flutter/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/flutter/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/flutter/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/flutter/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/flutter/.devcontainer/devcontainer.json

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


## FILE: source/templates/flutter/.devfleet/bootstrap.sh

SHA256: 0c27aca8e0c1121a29c7384e5a262913033dc1db108cdac32a119ebce92b203a | Bytes: 116 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
echo "Preview template: install dependencies inside this project container."

```


## FILE: source/templates/flutter/.devfleet/codexpro-bootstrap.sh

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


## FILE: source/templates/flutter/.devfleet/codexpro-profile.json

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


## FILE: source/templates/flutter/.devfleet/codexpro.env.example

SHA256: 86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30 | Bytes: 90 | Git mode: 100644

```
# Verified optional UI setting only. Do not store credentials here.
CODEXPRO_TOOL_CARDS=1

```


## FILE: source/templates/flutter/.devfleet/health-check.sh

SHA256: 04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311 | Bytes: 83 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -d .devfleet
./.devfleet/smoke-test.sh

```


## FILE: source/templates/flutter/.devfleet/project-tools.json

SHA256: ccde980799e84b21c3a72c6ed207f72392d9eb38f6754c780b54f722a9e42bb0 | Bytes: 298 | Git mode: 100644

```
{
  "id": "flutter",
  "language": "dart",
  "framework": "flutter",
  "maturity": "preview",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "true",
  "lint_command": "true",
  "test_command": "./.devfleet/smoke-test.sh",
  "health_command": "./.devfleet/health-check.sh"
}

```


## FILE: source/templates/flutter/.devfleet/smoke-test.sh

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


## FILE: source/templates/flutter/.devfleet/template.json

SHA256: 7ca190e7e910fbd534f125b4633cef84bb032378ddd6781fab5acaa2b2493735 | Bytes: 638 | Git mode: 100644

```
{
  "id": "flutter",
  "language": "dart",
  "framework": "flutter",
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


## FILE: source/templates/flutter/.editorconfig

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


## FILE: source/templates/flutter/.gitignore

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


## FILE: source/templates/flutter/README.md

SHA256: 6329a8cb3a85a5cb800b93eb3c8c09d9ad410e3155a98628eccef2ec441e1aaf | Bytes: 361 | Git mode: 100644

```
# __PROJECT_NAME__

Language: `dart`  
Framework: `flutter`  
DevFleet profile: `__PROJECT_PROFILE__`

Generated by DevFleet. Run `./.devfleet/bootstrap.sh`, `./.devfleet/health-check.sh`, and the test command recorded in `.devfleet/project.json`. Language selection follows Dylan's engineering preferences and is not presented as a scientific model benchmark.

```


## FILE: source/templates/flutter/compose.yaml

SHA256: c9f668fb7fa80610306f70b0a9f35b5f608b968d1ffa5a4acf64d6535e7a3638 | Bytes: 449 | Git mode: 100644

```
services:
  dev:
    image: ghcr.io/cirruslabs/flutter:stable
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


## FILE: source/templates/flutter/docs/architecture.md

SHA256: 32e45655fd2c249cf21c66683905451a443ae1c62e050fd6c911167637c6c53f | Bytes: 329 | Git mode: 100644

```
# Architecture

- Language: `dart`
- Framework: `flutter`
- Scale/intent/testing/profile are recorded in `.devfleet/project.json`.
- Rationale: selected from Dylan's DevFleet engineering preferences; this is not a scientific model benchmark.
- Source remains in one canonical checkout; use Git worktrees for concurrent branches.

```


## FILE: source/templates/generic/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/generic/.ai-bridge/codexp