# DevFleet source part 081

Full-source UTF-8 byte interval [3720000, 3766500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2d4ad1ece02e5b226caa316a5556d2ca65a8f42980a0812ce1081419d53dd0b7

<!-- BEGIN SOURCE SLICE -->
requires a separate laptop-admin action.

## Dashboard redundancy

The two dashboards are stateless peers. Either one can display/control its local node and proxy safe project actions to the other over a random API token on Tailscale.

The dashboards are deliberately **not** a shared multi-writer database and do not automatically promote a project. Projects are recovered to the other node from restic or GitHub. Peer-unreachable and peer-running states require explicit override before start.

## What the dashboard cannot do

- start a Windows VM that is currently stopped—the desktop shortcut performs that job;
- delete or purge a Multipass VM;
- access the vault filesystem directly;
- prune/forget vault snapshots;
- permanently delete quarantined projects;
- mount or browse Windows drives.

Keeping these powers out of the web service is part of the security design, not an unfinished feature.

## v1.1.0 control plane

`devfleet-primary` is displayed as `CodexDevVM`; it is not renamed. Both compute VMs run the same authenticated FastAPI dashboard. The VM-level controller can use the selected Docker socket, while application containers cannot. The laptop remains the primary UI and hosts failover plus the Docker-free append-only vault.

````


## FILE: source/docs/02-INSTALL-ORDER.md

SHA256: 4ed32904f5194bf15804565bbd254bcb91479b7b87552780723c737f6b92d75e | Bytes: 4071 | Git mode: 100644

````
# Exact installation order

Extract the package into a local folder on both computers. Keep the same package version on each computer.

## Phase A — laptop first

Double-click:

```text
START-HERE-LAPTOP.cmd
```

Or run manually from an elevated PowerShell 7 window:

```powershell
pwsh -File .\Install-DevFleet.ps1 -Role Laptop
```

The laptop phase:

1. checks virtualization, disk, RAM, CPU, Windows edition, and emulator conflicts;
2. installs/updates PowerShell, Git, VS Code, Tailscale, 7-Zip, GitHub CLI, OpenSSH Client, Multipass, and Hyper-V or VirtualBox;
3. disables Multipass host mounts;
4. connects the Windows host to Tailscale;
5. creates `devfleet-failover` and `devfleet-vault`;
6. installs rootless Docker and the failover dashboard;
7. installs the Vault Tailscale client from its verified signed repository, performs protected OAuth enrollment, verifies its authenticated private address, then installs the append-only vault service;
8. connects the failover VM to Tailscale;
9. initializes encrypted 15-minute backups;
10. creates shortcuts;
11. writes an encrypted `devfleet-laptop-bootstrap-*.dfe` bundle under `C:\ProgramData\DevFleet\exports`.

If Windows requests a reboot, reboot and double-click the same file again. Existing completed resources are reused; the installer refuses automatic VM destruction.

Laptop / Failover / Vault installation and Repair require connected Tailscale pairing. Normal setup uses the protected OAuth client-secret workflow with deterministic `tag:devfleet` identities; browser/device approval is manual recovery only. The Desktop-only deferral option cannot complete this role because Vault service and backup transport require authenticated Tailscale addresses. On Desktop, complete deferred pairing by running Repair with the deferral option cleared.

Copy the generated encrypted bundle to the desktop. Keep its passphrase.

## Phase B — desktop

Double-click:

```text
START-HERE-DESKTOP.cmd
```

Enter the laptop bootstrap bundle path when prompted. Manual equivalent:

```powershell
pwsh -File .\Install-DevFleet.ps1 -Role Desktop `
  -BundlePath "X:\Path\devfleet-laptop-bootstrap-YYYYMMDD-HHMMSS.dfe"
```

The desktop phase creates the primary VM, imports vault access, pairs primary-to-failover control, and outputs `devfleet-desktop-pairing-*.dfe` under `C:\ProgramData\DevFleet\exports`.

Copy that pairing bundle back to the laptop.

## Phase C — finish two-way pairing on laptop

Open PowerShell 7 as Administrator in the extracted package folder:

```powershell
pwsh -File .\windows\Complete-Cluster.ps1 `
  -DesktopPairingBundlePath "X:\Path\devfleet-desktop-pairing-YYYYMMDD-HHMMSS.dfe"
```

## Phase D — GitHub authentication

Run the command only on the physical computer that locally owns each VM:

```powershell
# Desktop
pwsh -File .\windows\Configure-GitHub.ps1 -InstanceName devfleet-primary

# Laptop
pwsh -File .\windows\Configure-GitHub.ps1 -InstanceName devfleet-failover
```

Approve the browser/device flow.

## Phase E — validate before real work

```powershell
pwsh -File .\windows\Test-DevFleet.ps1 -AllLocalInstances
pwsh -File .\tools\Verify-Package.ps1
```

Then:

1. use **DevFleet – Show Credentials**;
2. open **DevFleet – Open Dashboard**;
3. create a `generic` project named `devfleet-smoke-test`;
4. start it and confirm the analyzer has no blockers;
5. wait at least 15 minutes and confirm a backup timestamp appears;
6. quarantine and restore the test project;
7. stop/delete the test project only after confirming recovery works.

## v1.1.0 client completion

After pairing, `Complete-Cluster.ps1` configures the SSH aliases and core VS Code extensions. Re-run `client\Configure-VSCode.ps1` for optional language groups, optionally run `client\Configure-DockerContext.ps1`, then configure/test Ollama on MulattoTechBox. The clean desktop install uses rootless Docker; a v1.0 upgrade stays rootless. Existing explicit Docker mode choices are preserved during schema-2 migration. For upgrades, use `Upgrade-DevFleet.ps1` rather than the clean installer.

````


## FILE: source/docs/03-DAILY-USE.md

SHA256: 9c528be76c5285ec85c9eb2ae71fb68ac551dff06c54aef64d5b5c4f67013eb4 | Bytes: 2726 | Git mode: 100644

````
# Daily use

## Start from either computer

Double-click **DevFleet – Open Dashboard**. The shortcut starts that computer's local compute VM, finds its Tailscale IP, and opens the dashboard. Use **DevFleet – Show Credentials** for the random local dashboard password.

Double-click **DevFleet – Open VS Code** to connect through standard OpenSSH over Tailscale. Select a project and run:

```text
Dev Containers: Reopen in Container
```

## Create a project

The dashboard accepts:

- a lowercase project slug;
- display name;
- generic, Python, or Node template;
- optional GitHub HTTPS/SSH repository URL;
- local or peer target node.

Each generated project has `.devcontainer`, `.devfleet`, and a hardened Compose definition. The analyzer blocks startup for privileged containers, host networking, dangerous capabilities, Docker sockets, absolute host paths, Windows/UNC paths, or `../` sibling-workspace mounts.

## Delete safely

The dashboard action is named **Quarantine**, not permanent delete. It:

1. stops the container;
2. requires a successful immediate backup;
3. moves the directory to a timestamped quarantine path;
4. leaves it available for one-click restore.

Permanent purge is separate and confirmation-protected:

```powershell
pwsh -File .\windows\Invoke-Quarantine-Maintenance.ps1 `
  -InstanceName devfleet-primary -OlderThanDays 30
```

Run the equivalent against `devfleet-failover` only after checking its backups.

## Failover

When the desktop is unavailable:

1. open the laptop dashboard;
2. restore a new copy from the vault or clone from GitHub;
3. verify the primary is truly down/not writing;
4. check **failover override**;
5. start the recovered project.

When the desktop returns, stop one writer first. Commit/push or back up the failover changes, then restore/merge on the primary. Never intentionally run the same project on both nodes.

## Updates

Ubuntu unattended security updates are enabled. Use **DevFleet – Update Safely** for reviewed host/guest updates. Multipass is excluded by default because hypervisor upgrades deserve a current backup and explicit `-IncludeMultipass` choice.

## Offline vault copy

On the laptop, periodically use **DevFleet – Export Offline Vault Copy** and choose an external drive. The export stops the REST service briefly, copies the already encrypted repository, writes a SHA-256 file, and restarts the service. Disconnect the drive afterward.

## v1.1.0 daily workflow

Open the dashboard shortcut on either computer, create a language-aware project, then use `ssh CodexDevVM` or VS Code Remote SSH. Routine start/stop/health/test/rebuild operations are nonblocking and expose operation IDs, progress, timestamps, results, and logs.

````


## FILE: source/docs/04-RECOVERY.md

SHA256: ab36d4634d1477f69ef0c4b910dcfa16b6eb157e7e72b081066ce643f36ce2e3 | Bytes: 2082 | Git mode: 100644

````
# Recovery

## Quarantined project

Use the dashboard **Restore** button. The original project path is recreated without overwriting an existing folder.

## Corrupted or missing project

Use **Restore copy from vault**. DevFleet searches snapshots newest-first and restores the newest snapshot that actually contains that project into a new `PROJECT-recovered-TIMESTAMP` directory. Existing files are not overwritten.

## Primary VM destroyed

1. Re-run the desktop START-HERE installer; it creates a new primary without automatically deleting anything.
2. Supply the laptop bootstrap bundle.
3. authenticate Tailscale/GitHub;
4. restore projects from the vault or clone from GitHub;
5. re-run the desktop pairing export and laptop completion step if credentials changed.

## Failover VM destroyed

Re-run the laptop installer **without deleting `devfleet-vault`**. Reconfigure/restore projects from the existing vault.

## Vault VM damaged

Committed work remains in GitHub. Live primary/failover copies remain usable. Restore the vault from your newest offline encrypted export only after preserving the damaged VM and validating the export checksum.

## Manual retention and integrity check

Compute nodes never run `forget` or `prune`. From the laptop only:

```powershell
pwsh -File .\windows\Invoke-Vault-Maintenance.ps1
```

The script snapshots the vault VM, stops append-only service access, applies retention locally, prunes, checks the repository, and restarts the service.

## Diagnostics

```powershell
pwsh -File .\windows\Export-Diagnostics.ps1 -AllLocalInstances
```

The resulting ZIP contains host/VM status and service logs but intentionally excludes DevFleet secrets.

## v1.1.0 guided ownership transfer

When both nodes are reachable, Transfer stops the active copy, creates/verifies an append-only backup, restores a canonical copy on the peer, transfers the ownership lease by starting only the target, and reports progress. A peer-unreachable failover requires explicit split-brain acknowledgement. Read-only status/log/backup inspection remains available.

````


## FILE: source/docs/05-SECURITY-MODEL.md

SHA256: cc5a849cfe183f417cc6ee4600c0605e5258dddf9e3fc71f7de9451a7019bf2c | Bytes: 3166 | Git mode: 100644

```
# Security model

## Project-container restrictions

Startup is blocked for:

- privileged containers;
- host networking;
- `ALL` or `SYS_ADMIN` capabilities;
- Docker socket mounts;
- absolute Linux host paths;
- Windows drive-letter or UNC paths;
- `../` parent/sibling workspace bind mounts;
- published ports that do not bind to VM loopback (`127.0.0.1` or `::1`);
- device passthrough, `volumes_from`, host namespaces, or unconfined security profiles;
- invalid Compose/devcontainer configuration.

Only project-relative bind paths and named Docker volumes are accepted by the analyzer. Generated templates also drop all capabilities and set `no-new-privileges:true`.

## Rootless control plane

Docker runs as `devrunner` inside each compute VM. Rootful Docker services are disabled. The dashboard can control the rootless daemon and VM project folders, but cannot see Windows files because none are mounted.

The dashboard's repair button runs an unprivileged user-service repair. Root/VM/package repair remains a separate Windows administrator shortcut that takes a Multipass snapshot first.

## Network and web security

- Windows hosts and all VMs connect to Tailscale.
- UFW denies inbound traffic except SSH/dashboard/vault ports on `tailscale0`.
- VS Code uses ordinary OpenSSH keys over the encrypted Tailscale network; Tailscale SSH interception is not required.
- The dashboard uses random HTTP Basic credentials and same-origin POST checks.
- Peer APIs use separate random tokens.
- Security headers disable framing and restrict content/form origins.
- Docker TCP is never exposed.

The dashboard is HTTP rather than public TLS because traffic is restricted to the encrypted tailnet. Do not expose its port through router forwarding, Funnel, Serve, public reverse proxies, or a LAN-wide firewall rule.

## Backup security

Restic encrypts before upload. The vault server is append-only and uses private per-user repository paths. Compute-node credentials can read/add snapshots but cannot prune or delete prior snapshots through the REST interface. Vault-admin retention credentials never leave the vault VM.

## Remaining risks

- Windows administrator activity or administrator-level ransomware can delete Multipass VM files.
- Laptop disk failure can destroy the online vault unless an offline export exists.
- Compromised Tailscale, GitHub, or Windows accounts can expose access.
- Malicious code can exfiltrate data present inside its own project/container.
- Explicit failover override can create divergent writers.
- A software defect in Multipass, Docker, the Linux kernel, or this package could weaken isolation.

This is defense in depth and recovery-oriented isolation, not a mathematical guarantee.

## v1.1.0 profile invariant

Balanced is a practical development profile inside an already disposable VM, not a removal of host-file or vault boundaries. Fast Trusted can relax VM-internal container hardening only after explicit acknowledgement. No profile enables Windows mounts, Docker 2375, public dashboard exposure, ordinary docker.sock mounts, vault-admin credentials, sibling-workspace access, or deletion outside approved roots.

```


## FILE: source/docs/06-CODEXPRO-INTEGRATION.md

SHA256: 04a3d4244d99396de9a9b17ed21567aa4a491e724a551b8b211cd556de88fe80 | Bytes: 3732 | Git mode: 100644

````
# CodexPro integration

DevFleet separates **VM/container lifecycle authority** from **repository-scoped coding access**.

- The authenticated DevFleet VM controller may use the selected rootless or rootful Docker socket.
- Ordinary project containers, including CodexPro tooling inside them, are not automatically given `docker.sock`.
- New projects, sibling-container operations, failover, backup, quarantine, and restore go through DevFleet.
- Each project keeps its own allowed root, metadata, logs, runtime state, prompts, and `.ai-bridge` continuity files.

Each generated project includes:

```text
.devfleet/codexpro-bootstrap.sh
.devfleet/codexpro.env.example
.devfleet/codexpro-profile.json
.devfleet/prompts/session-bootstrap.md
.devfleet/prompts/reconnect.md
.devfleet/prompts/broken-session-recovery.md
.ai-bridge/handoff-template.md
```

## Verified live capabilities

The live CodexPro interface used while building v1.1.0 exposed:

- configuration/status inspection;
- opening one configured workspace;
- project and global skill discovery;
- bounded context, file reads, writes, and exact edits;
- controlled verification commands;
- Git status/diff review;
- handoff files and read-only session browsing.

It did **not** expose a documented multi-root registration API, a connector-authorization command, hidden ChatGPT headers, model-routing controls, quota bypasses, or a public context-cache control. DevFleet does not invent those capabilities. Its closest supported architecture is a shared VM lifecycle/status controller plus a project-local CodexPro adapter and profile.

## Idempotent bootstrap adapter

When a project starts, DevFleet executes `.devfleet/codexpro-bootstrap.sh` inside that project's running container. The adapter:

1. requires the canonical root `/workspaces/<project-slug>`;
2. creates `.devfleet/runtime` and `.ai-bridge/local-agent/logs`;
3. checks the loopback health endpoint first;
4. detects the `codexpro` executable;
5. starts it with the verified `codexpro start` interface when available;
6. writes an actionable status file and log;
7. exits successfully when already healthy or when installation/authorization is the only missing manual step.

No private credential or connector URL is embedded. The only verified environment variable placed in the example file is `CODEXPRO_TOOL_CARDS=1`. The exact private/local installation source and ChatGPT connector authorization remain manual because they are not exposed by the connected tool interface.

## Project profile

The observed workspace-scoped values are preserved as documentation, not treated as a universal installer schema:

```text
defaultRoot=/workspaces/<project-slug>
allowedRoots=[/workspaces/<project-slug>]
authEnabled=true
bashMode=full
bashTranscript=full
writeMode=workspace
toolMode=full
inheritEnv=false
contextDir=.ai-bridge
maxReadBytes=180000
maxWriteBytes=1000000
maxOutputBytes=120000
maxSearchResults=200
```

Keep `.git`, dependencies, `.env*`, private keys, `.ssh`, build outputs, models, caches, coverage, and `.ai-bridge/local-agent` excluded from broad context loading. One project must not broaden its allowed root to a sibling repository. VM-level Docker actions belong to DevFleet rather than arbitrary repository code.

## Efficient session startup

The generated session prompt directs the connected assistant to call configuration/status first, self-test only when fresh/broken/reconfigured, open without a full tree, load skills and authoritative instructions, inspect Git/context selectively, prefer diffs and changed-file manifests, and update a compact handoff before context becomes crowded. This improves practical throughput without claiming that model rate limits can be changed.

````


## FILE: source/docs/07-OFFICIAL-SOURCES.md

SHA256: 24dc3b375dd5380ad3eef4d4a2b9ea3c90f02352136ceee936edde8865773429 | Bytes: 1748 | Git mode: 100644

```
# Official implementation references

These are the primary references used for the package design. Re-check them before making major architecture changes because software behavior can change.

- Microsoft Hyper-V overview: https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/overview
- Canonical Multipass documentation: https://documentation.ubuntu.com/multipass/
- Multipass `local.privileged-mounts`: https://documentation.ubuntu.com/multipass/latest/reference/settings/local-privileged-mounts/
- Docker Engine install on Ubuntu: https://docs.docker.com/engine/install/ubuntu/
- Docker rootless mode: https://docs.docker.com/engine/security/rootless/
- VS Code remote Docker host / Remote SSH + Dev Containers: https://code.visualstudio.com/remote/advancedcontainers/develop-remote-host
- Tailscale Windows installation: https://tailscale.com/docs/install/windows
- restic repository preparation and password automation: https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html
- rest-server append-only and private repository behavior: https://github.com/restic/rest-server
- Ubuntu unattended upgrades: https://documentation.ubuntu.com/server/how-to/software/automatic-updates/

## v1.1.0 additional sources

- PowerShell binary/archive and installation methods: https://learn.microsoft.com/powershell/scripting/install/alternate-install-methods
- Ollama FAQ and environment configuration: https://docs.ollama.com/faq
- Ollama OpenAI compatibility: https://docs.ollama.com/openai
- VS Code remote Docker host: https://code.visualstudio.com/remote/advancedcontainers/develop-remote-host
- Multipass snapshots: https://documentation.ubuntu.com/multipass/latest/how-to-guides/manage-instances/create-a-snapshot/

```


## FILE: source/docs/08-DEVELOPMENT-PROFILES.md

SHA256: 78cdead576d5def42520f8276f09d14ebacd60fc19edf3e29f79d98a9fc1a02d | Bytes: 1940 | Git mode: 100644

````
# Development profiles

**Strict** preserves v1.0-equivalent behavior for unknown repositories, third-party Compose files, security-sensitive work, and unreviewed automation. Rootless Docker is expected; tailnet ports/shared caches are disabled; missing hardening can block.

**Balanced** is the recommended normal profile. It retains Windows-host, workspace, ownership, and vault boundaries while enabling trusted orchestration, shared caches, loopback/authenticated-tailnet ports, routine operations without repeated confirmation, and analyzer caching. Missing non-root USER, no-new-privileges, healthchecks, or fully pinned development images are warnings unless combined with a boundary escape.

**Fast Trusted Development** is explicit, visible, logged, and reversible. It can use rootful Docker inside the disposable VM and declared devices/capabilities. Application containers still do not receive docker.sock automatically. Windows folders, unauthenticated Docker TCP, vault-admin credentials, public exposure, and path/deletion boundaries remain protected.

Docker mode is a node property. Run `devfleet-docker-mode-report`, stop projects, then use `sudo devfleet-switch-docker-mode rootful --acknowledge-rootful` or `rootless`. Stores are separate and never silently migrated.

## Changing Docker mode safely

Use the Windows administrator wrapper so the authoritative schema-2 configuration and the selected VM stay aligned:

```powershell
pwsh -File .\windows\Set-DevFleetDockerMode.ps1 -NodeRole Primary -Mode rootful -AcknowledgeRootful
pwsh -File .\windows\Set-DevFleetDockerMode.ps1 -NodeRole Primary -Mode rootless
```

The wrapper verifies host-mount isolation, takes a stopped-state Multipass snapshot, records both Docker stores, requires all projects to be stopped, switches services, updates configuration, and runs a health check. It never copies, prunes, or deletes images, containers, or volumes from either store.

````


## FILE: source/docs/09-LANGUAGE-SELECTION.md

SHA256: fc1505fce91fcbc2c07793e56e49d1b1595c8fe1d1c5d0a06d61ce99d61dc9a1 | Bytes: 1091 | Git mode: 100644

```
# Language selection

These rankings are Dylan's engineering preferences, not claimed scientific model benchmarks. Defaults: Python for automation/AI/data/FastAPI; PowerShell for Windows administration; Bash/Python for Linux administration; Go for cross-platform/infrastructure CLIs; TypeScript for frontend/full-stack/extensions; C# for Windows/.NET; Java/Kotlin for enterprise; Rust for memory-sensitive components; Swift for Apple; Flutter for cross-platform mobile; SQL migrations plus typed models for relational persistence.

Core templates: `generic`, `python`, `python-fastapi`, `node`, `typescript-node`, `typescript-next`, `go-service`, `dotnet-service`, `java-spring`, `rust-service`.

Preview templates: `kotlin-service`, `php-laravel`, `ruby-rails`, `flutter`, `elixir-phoenix`, `cpp-cmake`, `shell-automation`, `data-r`, `scientific-julia`, `sql-project`.

Every generated project records language/framework/rationale/scale/intent/testing/profile/Ollama/worktree metadata in `.devfleet/project.json`, README, and architecture documentation. Avoid unnecessary polyglot designs.

```


## FILE: source/docs/10-OLLAMA-AND-GPU.md

SHA256: 1c62c6d556381f532b86eb7fe737d9e39a5726a4a457127e1adfe4a8404d9992 | Bytes: 1347 | Git mode: 100644

```
# Ollama and RX 7900 XTX

Keep Ollama on MulattoTechBox Windows unless real testing proves a better supported path. Do not assume Hyper-V/Multipass GPU passthrough. DevFleet prefers the desktop's authenticated Tailscale address and retains `http://192.168.1.243:11434/v1` as fallback. The one authoritative endpoint lives in installed schema-2 configuration and is propagated during project generation.

Profiles: Stable Interactive (low latency, 1–2 requests), Large Context (one primary analysis task), Parallel Agents (more concurrency with smaller contexts). `Configure-Ollama.ps1` uses documented `OLLAMA_HOST`, `OLLAMA_CONTEXT_LENGTH`, `OLLAMA_NUM_PARALLEL`, `OLLAMA_MAX_LOADED_MODELS`, `OLLAMA_MAX_QUEUE`, and `OLLAMA_KEEP_ALIVE`. `Test-Ollama.ps1` checks `/v1/models`, expected model availability, optional chat completion, and `ollama ps` GPU/CPU observation when local.


`Configure-Ollama.ps1` binds Ollama to the Windows host's Tailscale IPv4 address rather than a wildcard, creates a Windows Firewall rule limited to the tailnet CIDR, and records the MagicDNS name as the preferred client endpoint when Tailscale reports one. It does not add ROCm, HIP, Vulkan, or AMD-specific variables. After changing an installed endpoint, safely refresh each compute node so its generated service configuration receives the authoritative value.

```


## FILE: source/docs/11-REMOTE-VSCODE.md

SHA256: adf463bf6333f1ff118433701d9bccb9038dc12c1c512a95f2932b46f5e3ad6b | Bytes: 1184 | Git mode: 100644

````
# Remote VS Code

The laptop is the primary client and does not require Docker Desktop for main workloads. `Configure-SSH.ps1` creates `CodexDevVM` and failover aliases using the generated Ed25519 key and Tailscale IP. `Configure-DockerContext.ps1` creates Docker-over-SSH only; it never opens TCP 2375. `Configure-VSCode.ps1` installs real Remote SSH/Dev Containers and language extension groups and supplies exclusions for dependencies, caches, models, generated artifacts, and `.ai-bridge/local-agent`.

Typical commands:

```powershell
ssh CodexDevVM
code --remote ssh-remote+CodexDevVM /home/devrunner/workspaces/<project>
docker --context Codexdevvm ps
```


## Extension placement

Install Remote SSH and Remote Explorer on Windows. When VS Code opens `CodexDevVM`, allow language servers, linters, debuggers, and Dev Containers support to install in the remote environment when VS Code recommends it; UI-only extensions may remain local. The supplied extension lists are grouped so Python/web/enterprise/systems tooling can be added only for the projects that need it. The reference settings are copied for review rather than overwriting an existing personal `settings.json`.

````


## FILE: source/docs/12-UPGRADING-FROM-1.0.0.md

SHA256: 28666495394ce7fa029bbf0c0d0949512333328d28181fb238bd901345af30f2 | Bytes: 1101 | Git mode: 100644

````
# DevFleet v1.0.0 to v1.1.0 migration

Run the preview and then the upgrade from an elevated PowerShell 7 terminal:

```powershell
pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0 -PreviewOnly
pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0
```

The entry point backs up `C:\ProgramData\DevFleet` configuration, secrets, exports, and package metadata; validates Multipass host-mount isolation; stops each local DevFleet VM; creates a named snapshot; restores the prior running state; previews schema 2; and refreshes only existing instances. It does not delete or recreate VMs, projects, Git repositories, Docker stores/volumes, backup credentials, restic snapshots, vault data, Tailscale identities, SSH keys, dashboard credentials, pairing data, quarantine, or custom values.

A schema-1 baseline becomes Strict/rootless first. Rootless and rootful Docker have separate stores; optional switching requires a report, stopped projects, and explicit rootful acknowledgement. Re-running the v1.1 upgrade is safe and creates another recovery set rather than resetting the selected v1.1 profile.

````


## FILE: source/docs/13-PERFORMANCE-TUNING.md

SHA256: 04264853da9e3a2d5baa1002ccf43018df4af3c2d79bbf8236909e262a44501f | Bytes: 2023 | Git mode: 100644

```
# Performance tuning and practical token efficiency

DevFleet does not claim to alter ChatGPT/model quotas. It improves throughput with selective file loading, initial workspace opening without a full tree, search/read targeting, diff-oriented review, concise `.ai-bridge` handoffs, cached analyzer fingerprints, changed-file manifests, reusable dependency/BuildKit caches, one canonical checkout plus Git worktrees, and exclusions for dependencies/generated/model/cache/binary/runtime data.

Control ownership:
- ChatGPT controls the selected model, app/connector availability, memory/settings, and product usage limits.
- CodexPro controls verified roots, auth, tool/write/bash/transcript modes, output limits, blocked globs, and exposed tools.
- DevFleet controls VMs, Docker mode, lifecycle, leases, backups, analyzer, operations, peer transfer, and dashboard.
- The project controls committed instructions, `.devfleet/project.json`, Compose/Dev Container files, tests, language metadata, and `.ai-bridge` handoffs.
- Ollama controls the local endpoint, model availability, context/concurrency/queue settings, and observable GPU/CPU placement.
- Hidden headers, connector-retention flags, model-routing overrides, context-cache bypasses, and rate-limit bypasses are not fabricated.

Use the included session bootstrap/reconnect/broken-session/handoff prompts. Call `server_config` first, self-test only for fresh/broken/reconfigured sessions, open without a full tree, and verify tool reachability before long work.


The DevFleet package verifier and file-change manifest prevent repeated broad inspection of unchanged package content. Per-project analyzer fingerprints cover Compose, Dev Container, Dockerfile, environment-file, metadata, symlink, and bind-target inputs and are invalidated when those inputs change. Docker BuildKit's daemon-local cache is reused within each selected Docker store; dependency-manager caches are mounted only through trusted generated overrides and never include source repositories.

```


## FILE: source/docs/RELEASE-FINGERPRINT-SCHEMA.md

SHA256: 0e83ab1f2f01961b14ddc261a76128fa8f27ad35c04c63e732ef5824620ec80f | Bytes: 677 | Git mode: 100644

```
# Release fingerprint schema

Schema 2 is the current DevFleet release identity format. It removes checkout-local
absolute artifact paths and host filesystem permission bits from the hashed identity.
Artifacts are identified by logical name, byte length, and SHA-256. Source file modes
come from the same hook-mode contract used to write the canonical TAR and portable
archive: contracted template hooks are `0755`, and every other shipping file is
`0644`.

Schema 1 records remain valid only as explicitly historical evidence. They must not
be promoted as the identity of a current candidate because their IDs can vary by
checkout location and host permission representation.

```


## FILE: source/docs/host-agent-portability.md

SHA256: b7c8271409e747cc03a5214b7d082b9673e3e69131edd6a534db613bf6bb8faf | Bytes: 1504 | Git mode: 100644

```
# DevFleet host-agent portability

The dashboard talks to a narrow authenticated host-agent contract rather than directly to Multipass. A second Windows host such as MulattoTechSurface only needs the same contract and a host-specific configuration file.

Required configuration values are `HostId`, `HostName`, `ListenPrefix`, `TokenPath`, `MultipassPath`, `MultipassVersion`, `UbuntuImage`, `BootTimeoutSeconds`, `SshPublicKeyPath`, and `ResourcePolicy`. The resource policy must include host reserves, `MaximumVmCount`, `MaximumParallelProvisioning`, and project CPU, memory, and disk ceilings.

Portability rules:

- Keep the host identity unique and verify it on every authenticated response.
- Discover Multipass and actual host capacity on the target; do not copy MulattoTechBox capacity values blindly.
- Keep `gpu_enabled`, `gpu`, and `gpu_passthrough` false unless a separately reviewed provider is introduced.
- Use the same deterministic project VM naming and ownership registry on every host.
- Do not migrate or recreate an existing project automatically. Reconcile first, then require an explicit transfer operation.
- Keep host-agent install, firewall scope, and scheduled-task settings in the host-specific installer; the dashboard and provider contract remain shared.

The current package intentionally does not install or configure the Surface host. This document and the provider boundary are the preparation for a later one-package patch and a separately gated host-specific install.

```


## FILE: source/linux/bootstrap-compute.sh

SHA256: 512bc920be2372e2211f897ba6b83dcfa72b4c5c8973f5f8f548363425880645 | Bytes: 26944 | Git mode: 100644

```
#!/usr/bin/env bash
set -Eeuo pipefail

PAYLOAD=${1:?payload path required}
shift
export DEBIAN_FRONTEND=noninteractive
SECRETS_SOURCE=""
SECRETS_STDIN_REQUESTED=0
TRANSACTION_ID="${DEVFLEET_TRANSACTION_ID:-}"
PAYLOAD_SHA256="${DEVFLEET_PAYLOAD_SHA256:-}"
BOOTSTRAP_MAX_SECONDS="${DEVFLEET_BOOTSTRAP_MAX_SECONDS:-6600}"
SECRETS_INPUT_MAX_SECONDS=60
PACKAGE_VERSION=""
NODE_ROLE=""
while (($#)); do
  case "$1" in
    --secrets-stdin) SECRETS_STDIN_REQUESTED=1 ;;
    --transaction-id) TRANSACTION_ID=${2:?transaction id required}; shift ;;
    --payload-sha256) PAYLOAD_SHA256=${2:?payload sha256 required}; shift ;;
    --bootstrap-max-seconds) BOOTSTRAP_MAX_SECONDS=${2:?bootstrap max seconds required}; shift ;;
    --package-version) PACKAGE_VERSION=${2:?package version required}; shift ;;
    --node-role) NODE_ROLE=${2:?node role required}; shift ;;
    *) echo "unsupported bootstrap argument" >&2; exit 64 ;;
  esac
  shift
done

# Validate non-secret launch identity before creating files or waiting on stdin.
if [[ "$SECRETS_STDIN_REQUESTED" -ne 1 ]]; then echo 'Refusing legacy plaintext node-secrets.json input; use --secrets-stdin.' >&2; exit 64; fi
if [[ -z "$TRANSACTION_ID" || "$TRANSACTION_ID" =~ [^0-9a-fA-F] || ${#TRANSACTION_ID} -ne 32 ]]; then echo 'invalid transaction id' >&2; exit 64; fi
if [[ -z "$PAYLOAD_SHA256" || "$PAYLOAD_SHA256" =~ [^0-9a-fA-F] || ${#PAYLOAD_SHA256} -ne 64 ]]; then echo 'invalid payload sha256' >&2; exit 64; fi
if [[ ! "$BOOTSTRAP_MAX_SECONDS" =~ ^[0-9]+$ || "$BOOTSTRAP_MAX_SECONDS" -le 0 ]]; then echo 'invalid bootstrap owner deadline' >&2; exit 64; fi
[[ "$PACKAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'invalid bound package version' >&2; exit 64; }
[[ "$NODE_ROLE" =~ ^(primary|surrogate)$ ]] || { echo 'invalid bound node role' >&2; exit 64; }
BOUND_PACKAGE_VERSION=$PACKAGE_VERSION
BOUND_NODE_ROLE=$NODE_ROLE
INPUT_HELPER="$PAYLOAD/linux/bootstrap-input.sh"
[[ -f "$INPUT_HELPER" ]] || { echo 'missing bootstrap input helper' >&2; exit 4; }
# shellcheck source=bootstrap-input.sh
source "$INPUT_HELPER"

# Component deadlines are absolute and subordinate to the bootstrap owner.
BOOTSTRAP_STARTED_EPOCH=$(date +%s)
BOOTSTRAP_DEADLINE_EPOCH=$((BOOTSTRAP_STARTED_EPOCH + BOOTSTRAP_MAX_SECONDS))
PROGRESS_PATH=/var/lib/devfleet/bootstrap-progress.json
install -d -o root -g root -m 0750 /var/lib/devfleet
PROGRESS_SEQUENCE=0
CURRENT_COMPONENT=''
COMPONENT_DEADLINE_EPOCH=$BOOTSTRAP_DEADLINE_EPOCH
COMPONENT_TERMINALIZED=0
if [[ -f "$PROGRESS_PATH" ]] && jq -e --arg tx "$TRANSACTION_ID" --arg payload "$PAYLOAD_SHA256" '.transactionId==$tx and .payloadSha256==$payload and (.sequence|numbers)' "$PROGRESS_PATH" >/dev/null 2>&1; then
  PROGRESS_SEQUENCE=$(jq -r --arg tx "$TRANSACTION_ID" --arg payload "$PAYLOAD_SHA256" 'select(.transactionId==$tx and .payloadSha256==$payload) | .sequence' "$PROGRESS_PATH")
fi
write_progress() {
  local component=$1 state=$2 tmp now
  [[ "$component" =~ ^(secretsInput|packagePrerequisites|dockerRepositoryAndInstall|tailscaleRepositoryAndInstall|rootlessRuntime|nodeToolchain|pythonRuntime|serviceAndFirewallFinalization|bootstrap)$ ]] || return 1
  [[ "$state" =~ ^(STARTED|COMPLETED|FAILED|TIMED_OUT)$ ]] || return 1
  PROGRESS_SEQUENCE=$((PROGRESS_SEQUENCE + 1)); now=$(date -u +%Y-%m-%dT%H:%M:%SZ); tmp=$(mktemp /var/lib/devfleet/bootstrap-progress.XXXXXX)
  jq -n --arg tx "$TRANSACTION_ID" --arg payload "$PAYLOAD_SHA256" --arg component "$component" --arg state "$state" --arg now "$now" --arg version "$PACKAGE_VERSION" --arg role "$NODE_ROLE" --argjson sequence "$PROGRESS_SEQUENCE" '{schemaVersion:1,transactionId:$tx,payloadSha256:$payload,sequence:$sequence,component:$component,state:$state,updatedUtc:$now,packageVersion:$version,nodeRole:$role}' > "$tmp"
  chown root:root "$tmp"; chmod 0640 "$tmp"; sync -d "$tmp" 2>/dev/null || true; mv -f -- "$tmp" "$PROGRESS_PATH"; chown root:root "$PROGRESS_PATH"; chmod 0640 "$PROGRESS_PATH"
}
remaining_seconds() { echo $((COMPONENT_DEADLINE_EPOCH - $(date +%s))); }
run_bounded() {
  local remaining rc=0
  remaining=$(remaining_seconds)
  if (( remaining <= 0 )); then write_progress "$CURRENT_COMPONENT" TIMED_OUT || true; COMPONENT_TERMINALIZED=1; return 124; fi
  timeout --foreground --kill-after=10s "${remaining}s" "$@" || rc=$?
  if (( rc == 124 || rc == 137 )); then write_progress "$CURRENT_COMPONENT" TIMED_OUT || true; COMPONENT_TERMINALIZED=1; fi
  return "$rc"
}
run_bounded_command() {
  local command=$1; shift; local remaining; remaining=$(remaining_seconds)
  if [[ "$command" == "/usr/bin/apt-get" ]]; then set -- -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=2 "$@"; fi
  if [[ "$command" == "/usr/bin/curl" ]]; then set -- --connect-timeout 20 --max-time "$remaining" "$@"; fi
  run_bounded "$command" "$@"
}
apt-get() { run_bounded_command /usr/bin/apt-get "$@"; }
curl() { run_bounded_command /usr/bin/curl "$@"; }
gpg() { run_bounded_command /usr/bin/gpg "$@"; }
systemctl() { run_bounded_command /usr/bin/systemctl "$@"; }
npm() { run_bounded_command /usr/bin/npm "$@"; }
begin_component() { CURRENT_COMPONENT=$1; COMPONENT_TERMINALIZED=0; local max=$2 now; now=$(date +%s); COMPONENT_DEADLINE_EPOCH=$((now + max)); if (( COMPONENT_DEADLINE_EPOCH > BOOTSTRAP_DEADLINE_EPOCH )); then COMPONENT_DEADLINE_EPOCH=$BOOTSTRAP_DEADLINE_EPOCH; fi; write_progress "$CURRENT_COMPONENT" STARTED; }
complete_component() { write_progress "$CURRENT_COMPONENT" COMPLETED; CURRENT_COMPONENT=''; COMPONENT_TERMINALIZED=0; }
finish_bootstrap() {
  local rc=$? cleanup_rc=0
  trap - ERR EXIT
  rm -f -- "${SECRETS_SOURCE-}" "${SECRETS_ENV_TMP-}" "${DOCKER_KEY-}" "${TAILSCALE_KEY-}" || cleanup_rc=$?
  if [[ -n ${NPM_TMP-} ]]; then rm -rf -- "$NPM_TMP" || cleanup_rc=$?; fi
  if (( rc == 0 )); then rc=$cleanup_rc; fi
  if (( rc != 0 )) && [[ ${COMPONENT_TERMINALIZED:-0} -eq 0 ]]; then
    write_progress "${CURRENT_COMPONENT:-bootstrap}" FAILED || true
  fi
  exit "$rc"
}
trap finish_bootstrap EXIT
trap 'exit $?' ERR

begin_component secretsInput "$SECRETS_INPUT_MAX_SECONDS"
set +e
SECRETS_SOURCE=$(devfleet_capture_json_stdin '/run/devfleet-node-secrets.XXXXXX' "$COMPONENT_DEADLINE_EPOCH")
input_rc=$?
set -e
if (( input_rc != 0 )); then
  if (( input_rc == 124 || input_rc == 137 )); then write_progress secretsInput TIMED_OUT || true; else write_progress secretsInput FAILED || true; fi
  COMPONENT_TERMINALIZED=1
  echo 'bounded secret input delivery failed' >&2
  exit "$input_rc"
fi
fail_input() { local message=$1 code=${2:-2}; write_progress secretsInput FAILED || true; COMPONENT_TERMINALIZED=1; echo "$message" >&2; exit "$code"; }

JQ() { jq -r "$1" "$SECRETS_SOURCE"; }
NODE_NAME=$(JQ .NodeName); NODE_ROLE=$(JQ .NodeRole); FRIENDLY_NAME=$(JQ '.FriendlyName // .NodeName')
PORT=$(JQ .PortalPort); ADMIN_USER=$(JQ .AdminUser); ADMIN_PASSWORD=$(JQ .AdminPassword); API_TOKEN=$(JQ .ApiToken)
DEPLOYMENT_ID=$(JQ '.DeploymentId // ""'); NODE_ID=$(JQ .NodeId); COORDINATOR_NODE_ID=$(JQ '.CoordinatorNodeId // ""')
PROTOCOL_VERSION=$(JQ '.ProtocolVersion // 1'); OLLAMA_BASE=$(JQ .OllamaBaseUrl); OLLAMA_MODEL=$(JQ .OllamaModel)
OLLAMA_PROFILE=$(JQ '.OllamaProfile // "stable-interactive"'); DEVELOPMENT_PROFILE=$(JQ '.DevelopmentProfile // "strict"')
DOCKER_MODE=$(JQ '.DockerMode // "rootless"'); SHARED_CACHES=$(JQ '.EnableSharedCaches // false')
ANALYZER_CACHE=$(JQ '.EnableAnalyzerCache // true'); AUTO_CODEX=$(JQ '.AutoStartCodexPro // true')
ALLOW_TAILNET=$(JQ '.AllowTailnetPorts // false'); BACKUP_REBUILD=$(JQ '.BackupBeforeRebuild // false')
BACKUP_QUARANTINE=$(JQ '.BackupBeforeQuarantine // true'); BACKUP_INTERVAL=$(JQ '.BackupIntervalMinutes // 15')
INPUT_PACKAGE_VERSION=$(JQ .PackageVersion)
INPUT_NODE_ROLE=$NODE_ROLE
[[ "$INPUT_PACKAGE_VERSION" == "$BOUND_PACKAGE_VERSION" ]] || fail_input 'secret input package identity mismatch'
[[ "$INPUT_NODE_ROLE" == "$BOUND_NODE_ROLE" ]] || fail_input 'secret input node role mismatch'
PACKAGE_VERSION=$INPUT_PACKAGE_VERSION
[[ $PACKAGE_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail_input 'invalid PackageVersion'
[[ -n "$NODE_ID" && "$NODE_ID" != 'null' ]] || fail_input 'missing node identity' 3
[[ $DEVELOPMENT_PROFILE =~ ^(strict|balanced|fast)$ ]] || fail_input 'invalid development profile'
[[ $DOCKER_MODE =~ ^(rootless|rootful)$ ]] || fail_input 'invalid Docker mode'
[[ $PORT =~ ^[0-9]+$ && $PORT -ge 1024 && $PORT -le 65535 ]] || fail_input 'invalid portal port'
[[ $BACKUP_INTERVAL =~ ^[0-9]+$ && $BACKUP_INTERVAL -ge 1 && $BACKUP_INTERVAL -le 10080 ]] || fail_input 'invalid backup interval'
for value_name in NODE_NAME NODE_ROLE FRIENDLY_NAME ADMIN_USER ADMIN_PASSWORD API_TOKEN DEPLOYMENT_ID NODE_ID COORDINATOR_NODE_ID OLLAMA_BASE OLLAMA_MODEL OLLAMA_PROFILE; do
  value=${!value_name-}
  [[ $value != *$'\r'* && $value != *$'\n'* ]] || fail_input "invalid newline in $value_name"
done
complete_component

POLICY="$PAYLOAD/linux/dependency-policy.json"
[[ -f "$POLICY" ]] || { echo "missing dependency policy" >&2; exit 4; }
JQ_POLICY() { jq -r "$1" "$POLICY"; }
EXPECTED_TAILSCALE_FPR=$(JQ_POLICY .tailscale.signingKeySha256Fingerprint)
EXPECTED_DOCKER_FPR=$(JQ_POLICY .docker.signingKeySha256Fingerprint)
NODE_MIN_MAJOR=$(JQ_POLICY .node.minimumMajor)
NODE_CLI_VERSION=$(JQ_POLICY .node.devcontainersCliVersion)
NODE_CLI_INTEGRITY=$(JQ_POLICY .node.devcontainersCliIntegrity)
MUTABLE_PATH_CONTRACT="$PAYLOAD/app/systemd/mutable-paths.json"
[[ -f "$MUTABLE_PATH_CONTRACT" ]] || { echo "missing systemd mutable-path contract" >&2; exit 4; }
[[ $(jq -er ".schema_version" "$MUTABLE_PATH_CONTRACT") == 1 ]] || { echo "unsupported systemd mutable-path contract" >&2; exit 4; }
WORKSPACES=$(jq -er ".workspace" "$MUTABLE_PATH_CONTRACT")
QUARANTINE=$(jq -er ".quarantine" "$MUTABLE_PATH_CONTRACT")
TRANSACTION_ROOT=$(jq -er ".transaction_root" "$MUTABLE_PATH_CONTRACT")
for mutable_path in "$WORKSPACES" "$QUARANTINE" "$TRANSACTION_ROOT"; do
  [[ $mutable_path =~ ^/[A-Za-z0-9._/-]+$ && $mutable_path != *//* && $mutable_path != */../* && $mutable_path != */.. ]] || {
    echo "unsafe systemd mutable path contract" >&2
    exit 4
  }
done
[[ $WORKSPACES != "$QUARANTINE" ]] || { echo "systemd mutable paths must be distinct" >&2; exit 4; }
[[ $TRANSACTION_ROOT == "$WORKSPACES/.devfleet-transactions" ]] || { echo "restore transaction root must be a protected workspace sibling" >&2; exit 4; }

begin_component packagePrerequisites 900
apt-get update
apt-get install -y ca-certificates curl gnupg jq unzip acl python3-venv python3-pip uidmap dbus-user-session slirp4netns fuse-overlayfs iptables ufw restic git openssl
install -m 0755 -d /etc/apt/keyrings
. /etc/os-release
ARCH=$(dpkg --print-architecture)
complete_component

begin_component dockerRepositoryAndInstall 1200
DOCKER_KEY=$(mktemp)
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "https://download.docker.com/linux/ubuntu/gpg" -o "$DOCKER_KEY"
OBSERVED_DOCKER_FPR=$(gpg --show-keys --with-colons "$DOCKER_KEY" | awk -F: '$1=="fpr"{print toupper($10);exit}')
[[ "$OBSERVED_DOCKER_FPR" == "$EXPECTED_DOCKER_FPR" ]] || { echo "Docker signing-key identity mismatch" >&2; exit 4; }
gpg --dearmor < "$DOCKER_KEY" > /etc/apt/keyrings/docker.gpg
rm -f "$DOCKER_KEY"
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
complete_component

begin_component tailscaleRepositoryAndInstall 1200
TAILSCALE_KEY=$(mktemp)
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" -o "$TAILSCALE_KEY"
OBSERVED_TAILSCALE_FPR=$(gpg --show-keys --with-colons "$TAILSCALE_KEY" | awk -F: '$1=="pub"{count++;pending=1;next} pending && $1=="fpr"{fingerprint=toupper($10);pending=0} END{if(count!=1 || pending || length(fingerprint)!=40)exit 4;print fingerprint}')
[[ "$OBSERVED_TAILSCALE_FPR" == "$EXPECTED_TAILSCALE_FPR" ]] || { echo "Tailscale signing-key identity mismatch" >&2; exit 4; }
install -m 0644 "$TAILSCALE_KEY" /usr/share/keyrings/tailscale-archive-keyring.gpg
rm -f "$TAILSCALE_KEY"
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu $VERSION_CODENAME main" > /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale
systemctl enable --now tailscaled
complete_component

begin_component rootlessRuntime 600
# Rootless Docker is the default and devrunner must not inherit the
# host-equivalent rootful docker-group privilege.  A deliberate rootful
# deployment requires an explicitly privileged helper/profile outside the
# normal DevFleet service account.
getent passwd devfleet-control >/dev/null || run_bounded useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin devfleet-control
getent passwd devfleet-backup >/dev/null || run_bounded useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin devfleet-backup
# The service group is created by the service-account setup above.  Grant it
# traversal of the root only after that group exists; the bootstrap entrypoint
# must remain runnable on a clean image where the group is not yet present.
run_bounded chown root:devfleet-control /var/lib/devfleet
run_bounded chmod 0750 /var/lib/devfleet
run_bounded usermod --append --groups devrunner devfleet-control
run_bounded gpasswd --delete devrunner sudo >/dev/null 2>&1 || true
rm -f /etc/sudoers.d/devfleet-devrunner
getent group docker >/dev/null || true
run_bounded install -d -o root -g devfleet-control -m 0750 "$WORKSPACES" "$QUARANTINE"
run_bounded install -d -o devfleet-control -g devfleet-control -m 0700 "$TRANSACTION_ROOT"
run_bounded install -d -o devrunner -g devrunner -m 0700 /home/devrunner/.devfleet
run_bounded install -d -o devfleet-control -g devfleet-control -m 0750 /var/lib/devfleet/runtime /var/lib/devfleet/migrations
run_bounded install -d -o devrunner -g devrunner /var/cache/devfleet
run_bounded setfacl -m u:devrunner:rx,u:devfleet-backup:rwx,d:u:devrunner:rwx,d:u:devfleet-backup:rwx "$WORKSPACES" "$QUARANTINE"
# Re-bootstrap must also remove the obsolete broad backup-service grant from
# DevFleet's private 