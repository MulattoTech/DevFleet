# DevFleet source part 087

Full-source UTF-8 byte interval [3999000, 4045500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 02f01d35faacaa4c2f5df31784cbc6ab0feb53a550d47b0af43041942b22b405

<!-- BEGIN SOURCE SLICE -->
implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/java-spring/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/java-spring/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/java-spring/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/java-spring/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/java-spring/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/java-spring/.devcontainer/devcontainer.json

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


## FILE: source/templates/java-spring/.devfleet/bootstrap.sh

SHA256: 98839bba33a1300e24c7e3972e17264fb12f7c2f9c29934a694adf95fc03a484 | Bytes: 73 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
mvn -B -ntp dependency:go-offline

```


## FILE: source/templates/java-spring/.devfleet/codexpro-bootstrap.sh

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


## FILE: source/templates/java-spring/.devfleet/codexpro-profile.json

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


## FILE: source/templates/java-spring/.devfleet/codexpro.env.example

SHA256: 86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30 | Bytes: 90 | Git mode: 100644

```
# Verified optional UI setting only. Do not store credentials here.
CODEXPRO_TOOL_CARDS=1

```


## FILE: source/templates/java-spring/.devfleet/health-check.sh

SHA256: 04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311 | Bytes: 83 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -d .devfleet
./.devfleet/smoke-test.sh

```


## FILE: source/templates/java-spring/.devfleet/project-tools.json

SHA256: a0c8a1832e788ccaea44c0c296f626c27d8d13883fb8c6de84a143b7fe79a11b | Bytes: 342 | Git mode: 100644

```
{
  "id": "java-spring",
  "language": "java",
  "framework": "spring-boot",
  "maturity": "core",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "mvn -B -ntp spotless:apply",
  "lint_command": "mvn -B -ntp -DskipTests verify",
  "test_command": "mvn -B -ntp test",
  "health_command": "./.devfleet/health-check.sh"
}

```


## FILE: source/templates/java-spring/.devfleet/smoke-test.sh

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


## FILE: source/templates/java-spring/.devfleet/template.json

SHA256: 37d151c720b0af43f536bbd95c8b7665b447c3ca6fe91a497988840e31d2c806 | Bytes: 682 | Git mode: 100644

```
{
  "id": "java-spring",
  "language": "java",
  "framework": "spring-boot",
  "maturity": "core",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "mvn -B -ntp spotless:apply",
  "lint_command": "mvn -B -ntp -DskipTests verify",
  "test_command": "mvn -B -ntp test",
  "health_command": "./.devfleet/health-check.sh",
  "start_command": "docker compose up -d --build",
  "stop_command": "docker compose down --remove-orphans",
  "restart_command": "docker compose restart",
  "rebuild_command": "docker compose build && docker compose up -d",
  "logs_command": "docker compose logs",
  "codexpro_command": "./.devfleet/codexpro-bootstrap.sh"
}
```


## FILE: source/templates/java-spring/.editorconfig

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


## FILE: source/templates/java-spring/.gitignore

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


## FILE: source/templates/java-spring/README.md

SHA256: fd016ac49d43aa3e49afc9f9870b077cb3a3ef4de04b7237d2a96c1e27f68459 | Bytes: 365 | Git mode: 100644

```
# __PROJECT_NAME__

Language: `java`  
Framework: `spring-boot`  
DevFleet profile: `__PROJECT_PROFILE__`

Generated by DevFleet. Run `./.devfleet/bootstrap.sh`, `./.devfleet/health-check.sh`, and the test command recorded in `.devfleet/project.json`. Language selection follows Dylan's engineering preferences and is not presented as a scientific model benchmark.

```


## FILE: source/templates/java-spring/compose.yaml

SHA256: 6bcf5303791609900f2c4ef9ae6491856d09511d49293763fc6348b651f75acc | Bytes: 509 | Git mode: 100644

```
services:
  dev:
    image: mcr.microsoft.com/devcontainers/java:1-21-bookworm
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


## FILE: source/templates/java-spring/docs/architecture.md

SHA256: 86d557dbfaee567a7248bf5e5951297247b0e1c51a340835a51b5d58b2d3a06d | Bytes: 333 | Git mode: 100644

```
# Architecture

- Language: `java`
- Framework: `spring-boot`
- Scale/intent/testing/profile are recorded in `.devfleet/project.json`.
- Rationale: selected from Dylan's DevFleet engineering preferences; this is not a scientific model benchmark.
- Source remains in one canonical checkout; use Git worktrees for concurrent branches.

```


## FILE: source/templates/java-spring/pom.xml

SHA256: 3247de893b1aeb4ae0a67988a896d86c7387e4cbaca99b73b9599ac641ee3fe9 | Bytes: 935 | Git mode: 100644

```
<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>com.devfleet</groupId><artifactId>__PROJECT_SLUG__</artifactId><version>0.1.0</version><parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.4.0</version></parent><properties><java.version>21</java.version></properties><dependencies><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency></dependencies><build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin><plugin><groupId>com.diffplug.spotless</groupId><artifactId>spotless-maven-plugin</artifactId><version>2.44.0</version></plugin></plugins></build></project>

```


## FILE: source/templates/java-spring/src/main/java/com/devfleet/Application.java

SHA256: ad69197be917ffdea77d7e907cb678318ec47f7d3e78b12d5f43d74d77399bc6 | Bytes: 356 | Git mode: 100644

```
package com.devfleet;import org.springframework.boot.*;import org.springframework.boot.autoconfigure.*;import org.springframework.web.bind.annotation.*;@SpringBootApplication@RestController public class Application{public static void main(String[]a){SpringApplication.run(Application.class,a);}@GetMapping("/healthz") public String health(){return "ok";}}

```


## FILE: source/templates/java-spring/src/test/java/com/devfleet/ApplicationTest.java

SHA256: 22f424b51758288b420bebd94b067b1d2252653a65cbf6b2eed7fbeebdc228a1 | Bytes: 168 | Git mode: 100644

```
package com.devfleet;import org.junit.jupiter.api.Test;import static org.junit.jupiter.api.Assertions.*;class ApplicationTest{@Test void smoke(){assertEquals(5,2+3);}}

```


## FILE: source/templates/kotlin-service/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/kotlin-service/.ai-bridge/codexpro-project-instructions.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/kotlin-service/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/kotlin-service/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/kotlin-service/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/kotlin-service/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/kotlin-service/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/kotlin-service/.devcontainer/devcontainer.json

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


## FILE: source/templates/kotlin-service/.devfleet/bootstrap.sh

SHA256: 0c27aca8e0c1121a29c7384e5a262913033dc1db108cdac32a119ebce92b203a | Bytes: 116 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
echo "Preview template: install dependencies inside this project container."

```


## FILE: source/templates/kotlin-service/.devfleet/codexpro-bootstrap.sh

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


## FILE: source/templates/kotlin-service/.devfleet/codexpro-profile.json

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


## FILE: source/templates/kotlin-service/.devfleet/codexpro.env.example

SHA256: 86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30 | Bytes: 90 | Git mode: 100644

```
# Verified optional UI setting only. Do not store credentials here.
CODEXPRO_TOOL_CARDS=1

```


## FILE: source/templates/kotlin-service/.devfleet/health-check.sh

SHA256: 04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311 | Bytes: 83 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -d .devfleet
./.devfleet/smoke-test.sh

```


## FILE: source/templates/kotlin-service/.devfleet/project-tools.json

SHA256: 869e89aa0bc1d1bdec1c11427c4ac6a5d1321d450c0d0e6dbd7a12742c5c64b8 | Bytes: 304 | Git mode: 100644

```
{
  "id": "kotlin-service",
  "language": "kotlin",
  "framework": "ktor",
  "maturity": "preview",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "true",
  "lint_command": "true",
  "test_command": "./.devfleet/smoke-test.sh",
  "health_command": "./.devfleet/health-check.sh"
}

```


## FILE: source/templates/kotlin-service/.devfleet/smoke-test.sh

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


## FILE: source/templates/kotlin-service/.devfleet/template.json

SHA256: 597e482e24351687974c9633db75466b9820bfd8042a45f77f6ded32fd367391 | Bytes: 644 | Git mode: 100644

```
{
  "id": "kotlin-service",
  "language": "kotlin",
  "framework": "ktor",
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


## FILE: source/templates/kotlin-service/.editorconfig

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


## FILE: source/templates/kotlin-service/.gitignore

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


## FILE: source/templates/kotlin-service/README.md

SHA256: 222c507208a17c9605ddeb3eabb9b25d57db94387b588255234d5b6cf2fb4844 | Bytes: 360 | Git mode: 100644

```
# __PROJECT_NAME__

Language: `kotlin`  
Framework: `ktor`  
DevFleet profile: `__PROJECT_PROFILE__`

Generated by DevFleet. Run `./.devfleet/bootstrap.sh`, `./.devfleet/health-check.sh`, and the test command recorded in `.devfleet/project.json`. Language selection follows Dylan's engineering preferences and is not presented as a scientific model benchmark.

```


## FILE: source/templates/kotlin-service/compose.yaml

SHA256: 6bcf5303791609900f2c4ef9ae6491856d09511d49293763fc6348b651f75acc | Bytes: 509 | Git mode: 100644

```
services:
  dev:
    image: mcr.microsoft.com/devcontainers/java:1-21-bookworm
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


## FILE: source/templates/kotlin-service/docs/architecture.md

SHA256: 20faaf7d122cfbccb34018198302faf2582997e78f8ef07d14e82cd03dd5bc65 | Bytes: 328 | Git mode: 100644

```
# Architecture

- Language: `kotlin`
- Framework: `ktor`
- Scale/intent/testing/profile are recorded in `.devfleet/project.json`.
- Rationale: selected from Dylan's DevFleet engineering preferences; this is not a scientific model benchmark.
- Source remains in one canonical checkout; use Git worktrees for concurrent branches.

```


## FILE: source/templates/node/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/node/.ai-bridge/codexpro-project-instructions.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/node/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/node/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/node/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/node/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/node/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/node/.devcontainer/devcontainer.json

SHA256: 2e3f9099163de6f42887fb921741b6c9f0eabbf14c86fc7e4f3ae66123ab577f | Bytes: 207 | Git mode: 100644

```
{
  "name": "__PROJECT_NAME__",
  "dockerComposeFile": "../compose.yaml",
  "service": "dev",
  "workspaceFolder": "/workspaces/__PROJECT_SLUG__",
  "shutdownAction": "stopCompose",
  "remoteUser": "node"
}

```


## FILE: source/templates/node/.devfleet/bootstrap.sh

SHA256: ab4fc5d4fbbb3c4a680f0ddc19ecf073186cd8a1fbd3599b12abdcb2036b3327 | Bytes: 61 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
npm ci || npm install

```


## FILE: source/templates/node/.devfleet/codexpro-bootstrap.sh

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


## FILE: source/templates/node/.devfleet/codexpro-profile.json

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


## FILE: source/templates/node/.devfleet/codexpro.env.example

SHA256: 86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30 | Bytes: 90 | Git mode: 100644

```
# Verified optional UI setting only. Do not store credentials here.
CODEXPRO_TOOL_CARDS=1

```


## FILE: source/templates/node/.devfleet/health-check.sh

SHA256: 04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311 | Bytes: 83 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -d .devfleet
./.devfleet/smoke-test.sh

```


## FILE: source/templates/node/.devfleet/project-tools.json

SHA256: 37583adeb827d30c66de7316ee56774431578eeeec863ff8911001d8654cb663 | Bytes: 296 | Git mode: 100644

```
{
  "id": "node",
  "language": "javascript",
  "framework": "node",
  "maturity": "core",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "npm run format",
  "lint_command": "npm run lint",
  "test_command": "npm test",
  "health_command": "./.devfleet/health-check.sh"
}

```


## FILE: source/templates/node/.devfleet/smoke-test.sh

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


## FILE: source/templates/node/.devfleet/template.json

SHA256: 3cb664ae3211703f0eadf5f169d158a94c18720768744a493988e961f1238bf2 | Bytes: 636 | Git mode: 100644

```
{
  "id": "node",
  "language": "javascript",
  "framework": "node",
  "maturity": "core",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "npm run format",
  "lint_command": "npm run lint",
  "test_command": "npm test",
  "health_command": "./.devfleet/health-check.sh",
  "start_command": "docker compose up -d --build",
  "stop_command": "docker compose down --remove-orphans",
  "restart_command": "docker compose restart",
  "rebuild_command": "docker compose build && docker compose up -d",
  "logs_command": "docker compose logs",
  "codexpro_command": "./.devfleet/codexpro-bootstrap.sh"
}
```


## FILE: source/templates/node/.editorconfig

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


## FILE: source/templates/node/.gitignore

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


## FILE: source/templates/node/README.md

SHA256: 7be4300262e1bf4b940993b5c354ca51976ea2063f9866eed9267dcbc146334f | Bytes: 364 | Git mode: 100644

```
# __PROJECT_NAME__

Language: `javascript`  
Framework: `node`  
DevFleet profile: `__PROJECT_PROFILE__`

Generated by DevFleet. Run `./.devfleet/bootstrap.sh`, `./.devfleet/health-check.sh`, and the test command recorded in `.devfleet/project.json`. Language selection follows Dylan's engineering preferences and is not presented as a scientific model benchmark.

```


## FILE: source/templates/node/compose.yaml

SHA256: bb7f04bb7ab2e6fc28d18ea16f6bfcade03f1904c3890569b059b52b4743ec0b | Bytes: 477 | Git mode: 100644

```
services:
  dev:
    image: mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm
    user: "node"
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


## FILE: source/templates/node/docs/architecture.md

SHA256: dea7ef0c36a88ea7235ddb2f7f8f1956815d4029b801eadc3b20327cb01e6e96 | Bytes: 332 | Git mode: 100644

```
# Architecture

- Language: `javascript`
- Framework: `node`
- Scale/intent/testing/profile are recorded in `.devfleet/project.json`.
- Rationale: selected from Dylan's DevFleet engineering preferences; this is not a scientific model benchmark.
- Source remains in one canonical checkout; use Git worktrees for concurrent branches.

```


## FILE: source/templates/node/package.json

SHA256: 2642292c5492fe051a2d40712be97bd1f53fae7af89ae8e496157e5faadfd532 | Bytes: 227 | Git mode: 100644

```
{
  "name": "__PROJECT_SLUG__",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test",
    "lint": "node --check src/index.js",
    "format": "npx --yes prettier --write ."
  }
}

```


## FILE: source/templates/node/src/index.js

SHA256: a94468f11b9e176ff2b3cf31080d67c2a31efc3dc4c0757abf90585f4e765f6a | Bytes: 29 | Git mode: 100644

```
export const add=(a,b)=>a+b;

```


## FILE: source/templates/node/test/index.test.js

SHA256: 9c2cdf677c2a6a83b26572eab35a5092fbafd765934dc94997433659908735ec | Bytes: 147 | Git mode: 100644

```
import test from "node:test";import assert from "node:assert/strict";import {add} from "../src/index.js";test("add",()=>assert.equal(add(2,3),5));

```


## FILE: source/templates/php-laravel/.ai-bridge/chatgpt-memory.md

SHA256: ba1d7efc17a095e70f6e77feb14e7e28097feceba6a6b4377105cb7d540a145f | Bytes: 143 | Git mode: 100644

```
# Project continuity

Keep this concise: current architecture, active branch, important decisions, and next safe action. Do not store secrets.

```


## FILE: source/templates/php-laravel/.ai-bridge/codexpro-project-instructions.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/php-laravel/.ai-bridge/current-plan.template.md

SHA256: 7d2bf9a23bf85e57c790e8476e763eef0ca516aae620bebdf5af91b575173ddb | Bytes: 69 | Git mode: 100644

```
# Current plan

Goal:
Changed files:
Verification:
Next safe action:

```


## FILE: source/templates/php-laravel/.ai-bridge/prompts/broken-session-recovery.md

SHA256: d77fe808e85dd804eee9a157e225a37d2990b4dc7c10e90e32f5cfb89e3b6135 | Bytes: 166 | Git mode: 100644

```
Call server_config, then codexpro_self_test. Reopen the current workspace without a full tree, inspect status and handoffs, and report the precise failed capability.

```


## FILE: source/templates/php-laravel/.ai-bridge/prompts/handoff-template.md

SHA256: a57d5e01214e57298501064614350de6b76a52133f32b990fda325e65735ca02 | Bytes: 78 | Git mode: 100644

```
Goal:
Decisions:
Changed files:
Checks run/results:
Open risks:
Next action:


```


## FILE: source/templates/php-laravel/.ai-bridge/prompts/reconnect.md

SHA256: 5123bafc6042da10c0e3afcad5b069de73a7b5858a2466a44d53b81fb14a88ab | Bytes: 105 | Git mode: 100644

```
Verify server_config and open_current_workspace, then load the latest concise handoff before continuing.

```


## FILE: source/templates/php-laravel/.ai-bridge/prompts/session-bootstrap.md

SHA256: 95198949e141746a7bbbdd1c198c1a06be917a469d7a9f33b898bb185f359bbd | Bytes: 641 | Git mode: 100644

```
Use CodexPro. Call server_config first. Run codexpro_self_test only for a fresh, broken, or reconfigured session. Open the current workspace with include_tree=false, include_skills=true, and include_global_skills=true. Load codex_context with include_diff=false. Read .ai-bridge/codexpro-project-instructions.md, .ai-bridge/chatgpt-memory.md, AGENTS.md, and relevant handoffs. Use targeted search/read and diff-oriented review; exclude dependencies, generated assets, caches, models, binaries, and .ai-bridge/local-agent. Continue routine implementation without repeated approval and update a concise handoff before context becomes crowded.

```


## FILE: source/templates/php-laravel/.devcontainer/devcontainer.json

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


## FILE: source/templates/php-laravel/.devfleet/bootstrap.sh

SHA256: 0c27aca8e0c1121a29c7384e5a262913033dc1db108cdac32a119ebce92b203a | Bytes: 116 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
echo "Preview template: install dependencies inside this project container."

```


## FILE: source/templates/php-laravel/.devfleet/codexpro-bootstrap.sh

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


## FILE: source/templates/php-laravel/.devfleet/codexpro-profile.json

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


## FILE: source/templates/php-laravel/.devfleet/codexpro.env.example

SHA256: 86fb4ee91504cb8000731a492eeda3e5025d974caf8e6b293442ac3e0d87fa30 | Bytes: 90 | Git mode: 100644

```
# Verified optional UI setting only. Do not store credentials here.
CODEXPRO_TOOL_CARDS=1

```


## FILE: source/templates/php-laravel/.devfleet/health-check.sh

SHA256: 04250439ee1563434ea08e8370c3cb89aca47d878fb364cc78c2aef978929311 | Bytes: 83 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail
test -d .devfleet
./.devfleet/smoke-test.sh

```


## FILE: source/templates/php-laravel/.devfleet/project-tools.json

SHA256: f00db1d49a906ca361332bf159f90049ca017b129917b5a806bc47f92cdaa4ac | Bytes: 301 | Git mode: 100644

```
{
  "id": "php-laravel",
  "language": "php",
  "framework": "laravel",
  "maturity": "preview",
  "bootstrap_command": "./.devfleet/bootstrap.sh",
  "format_command": "true",
  "lint_command": "true",
  "test_command": "./.devfleet/smoke-test.sh",
  "health_command": "./.devfleet/health-check.sh"
}

```


## FILE: source/templates/php-laravel/.devfleet/smoke-test.sh

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


## FILE: source/templates/php-laravel/.devfleet/template.json

SHA256: 0ed6d408d05c521541dda2791f2c6f9fbb8228b22d530774a382aa88fd2c4414 | Bytes: 641 | Git mode: 100644

```
{
  "id": "php-laravel",
  "language": "php",
  "framework": "laravel",
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


## FILE: source/templates/php-laravel/.editorconfig

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


## FILE: source/templates/php-laravel/.gitignore

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


## FILE: source/templates/php-laravel/README.md

SHA256: 1d062db755de6c3e975fdc27d449356946d405dd3aa5fc1a184536df018a895e | Bytes: 360 | Git mode: 100644

```
# __PROJECT_NAME__

Language: `php`  
Framework: `laravel`  
DevFleet profile: `__PROJECT_PROFILE__`

Generated by DevFleet. Run `./.devfleet/bootstrap.sh`, `./.devfleet/health-check.sh`, and the test command recorded in `.devfleet/project.json`. Language selection follows Dylan's engineering preferences and is not presented as a scientific model benchmark.

```


## FILE: source/templates/php-laravel/co