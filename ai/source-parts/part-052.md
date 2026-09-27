# DevFleet source part 052

Full-source UTF-8 byte interval [2371500, 2418000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 9e9ef6939d77ed036e311a422fae792b31970ce9b1f25348bf177fbc5d417e29

<!-- BEGIN SOURCE SLICE -->
tifact identities without expanding public trust.

Use native authority generators/validators only where needed; do not run candidate finalization
reflexively after each session or memory update: it can reset current proof state. Do not hand-edit
promotion flags, rebrand historical proof bytes, or equate a diagnostic ZIP with release acceptance.

```


## FILE: docs/ai/devfleet-release/SOURCES.md

SHA256: 1487a17c669a0b3bdc92d123d59ba8b6fb650d5e27c33a8a38af6b41eb88c6a7 | Bytes: 2954 | Git mode: 100644

```
# Provenance and design boundary

## Supplied evidence, not a fresh live inspection

- `DEVFLEET-AI-OPERATING-RULES.md`
  SHA-256: `00273b4c777b4d4bd9cb985ac07383d1a5e4f8ab7abd91633a28a30ccc6bdded`
- `DEVFLEET-KNOWN-EDGE-CASES.md`
  SHA-256: `532cc1f520d2cd7ac5c329d7d21145212e8f25dd38e0ba5edbfc9f266fc8b296`
- `Codex_CLI_Output_(DevFleet)_Updated-9-5-26-458PM.md`
  SHA-256: `af8a160054ee2bf51802473d04966cd2535c38a16236679c5417cbe5f5f57853`
- `DevFleet-v1.2.13-AI-Audit-LATEST(20260905-215907).zip`
  SHA-256: `5c5154c4257d5852b532a3b465b95e865fcbe07892c505f30883b7219b6becca`

Relevant members of the latest audit: CURRENT-CANDIDATE.json;
audit/AFTER-ACTION-REPORT.md; audit/NEXT-CODEX-HANDOFF.json;
audit/SOL-HELPER-ALLOCATION-LEDGER.json; audit/SOL-HELPER-FINDINGS.json;
evidence/campaigns/wpf-no-report-20260905-ledger.json; current driver/contract/test files;
source/tools/release_fingerprint.py; source/docs/03-DAILY-USE.md; source/docs/04-RECOVERY.md.
Archive `release-tooling/` may represent native `tools/` files. Live paths are verified before use.

Historical safeguards and exact resource/signing identities derive from the supplied operating
contract. Seed current values and local test counts derive from the latest uploaded records;
no live Windows validation is claimed by this package. Earlier snapshot values remain historical.

## Newly designed workflow in this package

Milestone S0–S5 organization, DF-STABLE-20260905-A with three renewed readiness invocations
and two shared corrective replays, memory file organization/update triggers, U01–U05 acceptance
mapping, installer behavior and feature-handoff structure are proposed implementation choices
for the user's requested approach. Explicit user adoption makes the revised workflow active.
They are not rules or results discovered in the old audit. All native release gates are retained.

U01–U05 use the shipped daily-use/recovery semantics but are not claimed to be existing complete
E2E tests. Read the live operation contracts before implementing/checking them. Existing docs'
production-instance example commands are not authorized targets for disposable testing.

## Official Codex integration references checked September 5, 2026

- AGENTS.md discovery and precedence:
  https://developers.openai.com/codex/agent-configuration/agents-md
- Skill metadata, explicit invocation and progressive disclosure:
  https://developers.openai.com/codex/build-skills
- Repository-local skills pattern:
  https://developers.openai.com/blog/skills-agents-sdk

Root AGENTS receives only a compact routing block. A nonempty existing AGENTS.override.md
has precedence, so the installer appends the block there instead of creating a shadowing
file. Existing text is preserved. Skill lives under .agents/skills/devfleet-release-control/.
No new global Codex configuration or model selector is installed. Runtime availability and
permissions are still checked in the resumed session.

```


## FILE: docs/ai/devfleet-release/START-HERE.md

SHA256: 1db4b3e90ff920c341fa74382d7c99579afe9ecd1705eecf5da078ea994455b8 | Bytes: 3485 | Git mode: 100644

```
# DevFleet v1.2.13 — start here

Package: `DF-RELEASE-WORKFLOW-20260905-v1`.
Objective: **PASS — INTERNAL RELEASE ELIGIBLE**, then preserve a stable baseline for
separate Astra feature development. No claim of public-release trust is authorized.

## What this package changes

This is user-requested orchestration and memory, not a new product framework. It retains
the current implementation and native validators. After explicit adoption, WORKFLOW's
renewed, separate readiness/product retry allowances replace the old exhausted two-attempt
instruction. The historical 2/2 remains untouched. Existing Sol authority and six-helper,
depth-two policy remain; used helper slots are not reset.

## Entry sequence — use selected fields, not giant JSON dumps

1. Read SAFETY-AND-AUTHORITY, WORKFLOW and DONE once. Read `audit/agent-memory/CURRENT.md`
   and `audit/agent-memory/INDEX.md`. Existing applicable AGENTS instructions still apply.
2. Check live Git branch/HEAD/diff classification and exact coordinator/lab ownership.
   An active operation or uncertain owner is not permission to start a competitor.
3. Read the live `audit/NEXT-CODEX-HANDOFF.json`, `CURRENT-CANDIDATE.json`,
   `evidence/CURRENT-RELEASE-AUTHORITY.json`, `evidence/CURRENT-STATUS.json`,
   `evidence/CURRENT-GATES.json`, and `finalization-state.json`, plus only the terminal
   records relevant to their current RunIds. Consult YOLO-RESUME-HANDOFF only as a
   possibly older administrative snapshot. A newer coherent terminal record wins.
4. Resolve the actual next action. Seed memory describes the September 5 upload;
   it does not force that upload's HEAD, hashes, budget, status or VM state onto live data.
5. Classify the newly installed stable Markdown/skill/root instruction block. Verify
   actual shipping/tooling inventory membership. Stage only those explicit stable paths
   in one orchestration commit when the existing repo policy permits; do not stage the
   whole dirty tree. Dynamic memory lives under `audit/agent-memory/`, not shipping roots.
6. Do the earliest incomplete milestone; consult TEST-PLAN and COMMAND-MAP as needed.
   Do not repeat finished specialist reviews or rewrite the corrected WPF driver by default.

## File map

| File | Use |
|---|---|
| SAFETY-AND-AUTHORITY.md | Immutable boundaries, root/helper authority, candidate discipline |
| WORKFLOW.md | Milestone ladder, new retry authorization, stop rules and code freeze |
| TEST-PLAN.md | Specific executable test obligations and real-use acceptance scenarios |
| COMMAND-MAP.md | Existing entrypoints, safe parameter discovery and evidence capture |
| DONE.md | Exact release and feature-handoff completion criteria |
| MEMORY-PROTOCOL.md | Automatic event-driven Markdown updates, provenance and invalidation |
| CLOSEOUT.md | Safe pause, blocker and release packaging |
| FEATURE-HANDOFF.md | Stable baseline and separate Astra feature work |
| SOURCES.md | Uploaded evidence provenance versus newly designed workflow rules |

The memory index points to short current state, known edges, decisions, attempts, test
results and helper allocation. Archive notes are read on demand, never all at startup.

## Minimum useful progress report

`Milestone; actual observation; passing/failed test or RunId; exact blocker; next action.`
Do not give a release percentage or predicted completion time. During long local waits,
let the bounded harness wait; report actual state transitions rather than repeated polling.

```


## FILE: docs/ai/devfleet-release/TEST-PLAN.md

SHA256: 63f145252da56aaa1a92c53fc19b804aab44d5cf56d6c2d6a1395fd84b3a35d5 | Bytes: 23598 | Git mode: 100644

```
# Concrete verification and acceptance plan

This file specifies behavior to verify; it does not assert these tests have passed or that
all requested coverage already exists. Reuse current tests; add only genuinely missing
behavioral cases. The latest uploaded suite results are evidence-scoped in memory/TEST-RESULTS.
Counts are not targets: 26/26 alone does not show which production behaviors were exercised.

Every result needs test/RunId, test and relevant production-input identity, command, runtime,
exit code, expected versus actual outcome, time and evidence path. Missing evidence is
UNVERIFIED. Required environment-specific tests may not be relabeled PASS because skipped.
A missing proposed new module is a scaffolding failure, not reproduction of the original bug.

## A — focused local/behavioral contracts, before more live diagnostics

Primary existing suite:
`automation/release-e2e/tests/Test-WpfLaunchBoundaryBehavior.ps1`.
Supporting suite:
`automation/release-e2e/tests/Test-LifecycleObserverBehavior.ps1`.
Exercise actual production builders/parsers/supervisor boundaries, not only regex strings.

| ID | Arrange and exercise | Required result |
|---|---|---|
| B01 | Generate initial and resume launch specifications; invoke the real driver parser in ContractProbe mode with real quoting, role names and spaced paths | Initial has no elevated-resume flag; resume has it; acknowledged vector equals generated vector; no product launched |
| B02 | Task Scheduler normalizes the same local account name; inject same and different SID resolutions; vary run level/logon enum, executable or arguments | Same identity allowed; different SID/session/enum/path/arguments rejected before task start; semantic identity replaces account-text equality |
| B03 | Follow actual remote pre-task validation and local task validation, including restricted-session dependency boundary | No unguarded staged-module dependency in the remote registration path; local tests distinguish source-only check from executed remote behavior |
| B04 | Run the actual copied driver with contract module deliberately missing; similarly malformed launch request or failed startup before UIA | Finite nonzero result, dependency-free primary terminal with exact run/launch/payload/candidate identity where available, completion false, no candidate launch; cannot hang before reporting |
| B05 | Inject consumed owner time, late child creation, no-progress and advancing valid progress; also invalid parent allowance | Child uses remaining budget and terminal margin; absolute budget never moves; insufficient hierarchy rejected before mutation; CPU/PID churn does not reset product progress |
| B06 | Inject a worker stuck in a real isolation boundary; simulate worker early exit and report-read/write/enrichment failure | Supervisor terminalizes within its owned budget, attempts exact worker cleanup only, preserves primary error; test asynchronous timeout does not merely leave a hidden uncontrolled call |
| B07 | Drive real completion branch with executionAlreadyStarted=true and completed, pending, failed, cancelled or missing terminal outcomes | Already-running still observed; no completed PASS when completionVerified=false; no candidate kill/close during in-progress or transferred pending ownership |
| B08 | Supply pending with and without validated durable transaction/payload state and explicit ownership transfer | Only validated pending accepted as pending; it is never final lifecycle PASS; lifecycle owner responsible after transfer |
| B09 | Supply missing/truncated/wrong-run/wrong-launch/wrong-transaction/wrong-payload/wrong-candidate/stale/duplicate-or-regressed sequence reports | Reject invalid evidence; finite truthful observer failure; same-run malformed evidence cannot become PASS; sequence monotonicity checked against previous accepted state, not merely sequence > 0 |
| B10 | Supply successful UI state, durable terminal evidence and a product-reported failure through production branches | Correct distinction between observer failure and actual product failure; completion requires matching durable/install/health evidence at lifecycle layer |
| B11 | Deserialize UTC/offset timestamps and round-trip without culture-dependent stringification | Same instant and required precision retained; raw historical evidence unchanged |
| B12 | Child exits while descendant keeps output handles open; CIM lookup races process exit | Capture direct exit, bounded drain, truthful output completeness, no killing legitimate descendants for EOF; null/exited lookup cannot mask primary error |

Use existing injected clocks/adapters where they exercise real logic. A pure policy helper
result does not prove its caller enforces the policy; test the actual branch for B06–B10
when coverage is absent. Do not rebuild a whole test framework for this checklist.

### Focused correction result — 2026-09-06

The pre-correction production paths failed the new behavioral checks for two real reasons:
`Wait-WpfBoundReport` could consume a late report before enforcing its absolute cutoff, and
`Resolve-DevFleetNestedL2Inventory` treated a missing Multipass executable as L2 ABSENT.
The production fresh-install lifecycle also left completion observation in the synchronous
UI worker even though the existing durable product observer already understands bound guest
stage markers, checkpoints, receipts, ownership and authenticated health.

The minimal correction now:

- transfers the exact candidate PID/start-time/session, run/launch/payload and optional
  transaction from the WPF boundary to `Wait-DevFleetProductLifecycleTransition` without
  calling that transfer pending or claiming product completion;
- lets only monotonic transaction/payload-bound guest stage markers and other durable product
  state reset the semantic product watchdog; static UI text, CPU, heartbeats and PID churn do not;
- carries one fixed owner absolute deadline into every lifecycle observation instead of
  granting a fresh child budget after WPF/reboot time has been consumed;
- accepts a valid terminal file collected late only when its trusted atomic file-write time
  proves it existed before cutoff, and rejects a result first established at/after cutoff;
- rejects wrong run, launch, transaction, payload, candidate, deadline, malformed, duplicate
  or regressed evidence as deadline-extending progress; and
- returns L2 UNVERIFIED when the Multipass CLI is absent unless complete read-only in-L1
  Hyper-V and VirtualBox backend inventories establish exact absence.

Focused results on the frozen working inputs:

| Runtime / suite | Result | Relevant proof and limit |
|---|---|---|
| PowerShell 7 `Test-WpfLaunchBoundaryBehavior.ps1` | PASS 46/46 | Real launch builder and Windows PowerShell driver parser, immutable cutoff/late collection, identity rejection, observer handoff, stuck/early worker and cleanup ownership |
| Windows PowerShell 5.1 `Test-WpfLaunchBoundaryBehavior.ps1` | PASS 46/46 | Confirms the production task/driver parser path; test literals avoid encoding-dependent UI separators |
| PowerShell 7 `Test-LifecycleObserverBehavior.ps1` | PASS 126/126 | Static WPF status for more than 1,800 simulated seconds while seven bound durable guest markers reach completion inside a fixed 7,200-second owner deadline; true no-progress, CPU-only activity, absolute cutoff, generation-zero adoption and conservative L2 inventory cases |
| PowerShell 7 `Invoke-HarnessTests.ps1` | PASS 110/110 | Broader harness contract after the correction |
| PowerShell 7 authority/final convergence/interactive/release/security/runtime checks | PASS | Timestamp round-trip; 12/12; 54/54; 7/7; Host Agent poison/TOCTOU fixture; repository-local Python |

The lifecycle suite's injected-provider seam requires `Start-ThreadJob`, which is available in
the repository PowerShell 7 runtime but not the installed Windows PowerShell 5.1 environment.
Attempting that suite in Windows PowerShell therefore terminates as an unsupported bounded-test
primitive; it is not a product result. The Windows PowerShell code that actually runs in the
scheduled WPF task is separately parsed and exercised by the 46/46 boundary suite.

The standard-token installer self-test was not relabeled PASS: this coordinator is elevated,
so the test correctly stops because it requires a genuinely non-administrator caller. Reuse
only unchanged-input valid standard-token evidence at certification, or record the gap honestly.
None of these local results is a real installer lifecycle success or a release proof.

## DF-STABLE-20260906-B exact replay result

The one supplemented exact Proof #1 replay was consumed by
`e2e-exact-candidate-proof-stable-20260906-p1-supplement-b1`. It is **BLOCKED** and earns no
proof credit. The WPF correction itself live-passed: initial launch and elevated resume both
published exact `OBSERVER_HANDOFF` records, claimed neither pending nor completion, and left
cleanup to `Wait-DevFleetProductLifecycleTransition`.

Generation 0 reached a valid transaction/payload-bound reboot checkpoint. After reboot,
generation 1 wrote exact `stage-prereqs-Desktop.complete` and `stage-host-agent.complete`
markers; Host Agent became Running and its listener became available. At
`2026-09-06T03:16:58.6195807Z`, the product entered a persistent Multipass child operation.
For the remainder of the 1,800-second semantic window it emitted no guest
`bootstrap-progress.json`, consumed receipt, valid install state or terminal product failure.
The candidate and installer processes remained present and Multipass CPU increased, but those
signals correctly did not extend the semantic deadline. The lifecycle owner terminalized at
generation 1 with `NO_PROGRESS_TIMEOUT` and exact cleanup proved L2 ABSENT / L1 OFF.

This is a new shipping/runtime product-lifecycle blocker after the repaired WPF boundary, not
evidence that the observer failed. Preserved evidence narrows the unresolved sub-boundary to
the compute provisioning operation after instance creation and before the first guest marker;
because process arguments were deliberately redacted, it does not prove whether payload
transfer or the stdin-bound guest bootstrap was the stalled substep. Do not claim either as the
root cause without new evidence. Supplement B is exhausted 1/1, so no further product replay is
authorized. Source-level work must preserve this distinction and any future replay requires new
explicit authority, frozen material inputs, exact CLEAN and fresh HOST-SAFETY.

Primary evidence:

- proof start SHA-256 `80416023d201674b54ea5d1856293df4846a8fa0c8e473a418f437262c2ce870`;
- resume WPF evidence SHA-256 `887e9bf52faeb1a0b9323fe9fb4f5200ad1fd60b746402fdbf953a56bd373111`;
- generation-1 lifecycle record SHA-256 `04df45224355e621cea78b6d9c4db4b7d1898d467f40dfa54e2b511b87ff5427`;
- 225-sample observer record SHA-256 `7c5e9e35805d2d1422badebd844c2aea60e88004474a15935ba7ceea68ad2cc2`;
- lifecycle terminal SHA-256 `428094c2dededc25156d5b5f5cc4e7968e59be73599a2efc97fb36733885e225`;
- cleanup SHA-256 `8dcd988243616a2420dbe05e5a81bf67d607ed54261cb02540c6863b29085783`.

## DF-STABLE-20260906-C Multipass/bootstrap correction

The preserved Supplement B run remains unable to prove whether payload transfer or stdin-bound
bootstrap caused its stall. Focused source review nevertheless demonstrated three same-boundary
shipping/tooling defects: synchronous stdin preceded output drains and effective wait ownership;
both Linux entrypoints read stdin before durable progress/traps/deadlines; and the guest-marker
reader discarded native outcomes so failure could look like absence. These static defects are not
retroactively asserted as the historical run's proven cause.

The C correction is acceptable for candidate freeze only when all of these behavioral cases pass:

| Suite / boundary | Required current result |
|---|---|
| `Test-ExternalStandardInputBoundary.ps1` | Never-read stdin, output backpressure, broken pipe, early exit, EOF and one shared absolute deadline terminate with the correct primary result |
| `Test-BootstrapInputBoundary.ps1` | Production compute/vault entrypoints validate bound non-secret identity before stdin; valid, empty, invalid, truncated and withheld dummy input have finite outcomes and leave no secret temp file |
| `Test-DependencyProbeBoundary.ps1` | Production dependency/version probing inherits the owning stage, kills a nonreturning child, retries only `Broken` under one immutable deadline and never revives an unsupported result |
| `Test-ProcessOutputDrain.ps1` | Existing direct-exit/bounded-drain behavior remains; production bootstrap builder emits allowlisted substeps and no secret argument |
| `Test-LifecycleObserverBehavior.ps1` | Valid/absent/native-failure/timeout/malformed/wrong-identity marker reads remain distinct; only monotonic valid marker progress resets semantics; guest FAILED/TIMED_OUT is a product terminal |
| Full `source/tests` plus affected release harness contracts | No regression on the frozen inputs; platform skips stay explicit |

The corrected signed run must expose allowlisted host markers for Multipass resolution,
isolation, instance presence/absence, launch/start, readiness, payload transfer and extraction,
then a durable guest `secretsInput` STARTED/COMPLETED or terminal marker.
Absence is valid only from an explicit successful inventory plus native exit 44 for the exact
marker path. Collector failure, timeout, invalid JSON and identity mismatch remain observer
evidence and cannot extend the product deadline. The optional C diagnostic is unnecessary when
these signals are available in the exact proof; skipping it preserves its 0/1 allowance and does
not turn the proof into a diagnostic.

Observed C result: diagnostic 1/1 proved the pre-isolation dependency probe defect and the frozen
shipping correction passed all focused contracts. Corrective exact Proof #1 1/1 then stopped after
three lifecycle samples because the production observer constructed its compute-marker allowlist
from the harness cleanup L2 name `DevFleet-E2E-Linux-01`, not the signed product Primary identity
`devfleet-primary`. Two current product stage markers were therefore rejected as unsafe before a
Multipass/bootstrap outcome could be observed. This is a proven harness/tooling defect, not a
product failure or proof PASS. The tooling-only correction derives the exact product identity from
the current candidate shipping config, keeps cleanup identity separate, and preserves rejected
marker names in normalized evidence. Its focused results are lifecycle 144/144, WPF 46/46 and
harness 110/110. C's proof replay is consumed; no additional live product replay is authorized.

## S1 — actual target launcher readiness (not a release proof)

Use the existing `audit/automation-harness/Invoke-WpfBoundaryContractDiagnostic.ps1`
after inspecting its live parameters and side effects. Latest archive does not contain
that entrypoint; do not reconstruct it from a transcript if the live file exists.

Required observations in positively identified CLEAN L1:

- Fresh permitted HOST-SAFETY, correct L1/CLEAN identity and real nonzero E2EAdmin desktop.
- Real PowerShell Direct -> registered scheduled-task -> actual driver bootstrap/parser.
- Registered principal identity and enum/executable/argument readback match intended launch.
- Both initial and resume acknowledgement match run/launch IDs, staged driver/contract/EXE
  hashes, session, mode and candidate argument vector; resume includes elevated-resume.
- No candidate product launch or product mutation in ContractProbe. A process STARTED marker,
  task Running or parser success on the host is not this target-environment result.
- Bounded acknowledgement/terminal collection, task cleanup and durable L1/L2 terminal evidence.
- Security configuration unchanged. A managed policy rejection remains a real prerequisite blocker.

## S2/S3 — genuine clean installation and repeatability

Proof #1 and Proof #2 each start independently from canonical CLEAN with new RunIds,
fresh safety, exact signed artifacts and current material tooling. Prefer Proof #1 as
both first real lifecycle observation and first qualifying proof; no duplicate long smoke.

Trace exact EXE launch -> actual WPF reviewed plan/confirmation -> product operation ->
required L1 reboot(s) -> new boot identity -> native resume -> increasing valid checkpoint
state -> matching consumed receipt/install state -> canonical ownership -> authenticated health.
Require real Windows services/Host Agent/guest Linux behavior under the native gate definitions.
Assert no unexpected extra writer, duplicate integration adoption, stuck pending operation,
foreign-resource deletion, stale receipt acceptance or unexplained background execution.

Test required Desktop and Laptop/Failover/Vault paths through existing authorized lab/surrogate
coverage. A second Desktop pass is not evidence for an untested Laptop scenario. No physical
Surface or protected production VM operation is authorized by this requirement.

## U — real daily-use acceptance within the disposable deployment

These are new explicit acceptance obligations based on existing daily-use/recovery behavior,
not claims of already implemented end-to-end tests. Map them to existing runtime tests first.
Use a unique disposable project (for example `df-accept-<short-run-id>`) and harmless known
text file; never actual user projects, external Git pushes, host paths or privileged containers.
Use the real dashboard/user-facing operation flow, not direct success-state writes. Check
backend receipts/logs as corroboration. Keep the fixture small; no new host VM is required.

| ID | Actual user journey | Observable pass condition |
|---|---|---|
| U01 | Authenticate to disposable dashboard; create a generic/Python/Node project using an existing supported template | Project directory and metadata are correct; expected .devcontainer/.devfleet/Compose assets exist; credentials not logged |
| U02 | Start project, run its provided harmless smoke/health/test operation and inspect returned operation status/logs | Real workload starts and becomes healthy; operation ID reaches terminal success; UI result agrees with backend/container evidence |
| U03 | Stop, restart, then reopen/reconnect to the dashboard after permitted service/guest restart in the disposable deployment | No duplicate writer/container; same project/data remains; health recovers and operation is not left permanently pending |
| U04 | Write known fixture content, use supported immediate backup and Quarantine, then Restore; verify checksum/content | Backup precedes quarantine; quarantine is not permanent deletion; restore does not overwrite a foreign existing directory; known data recovered |
| U05 | Use supported restore-copy-from-vault/recovery path in the authorized scenario; also exercise existing blocked-start/security/ownership regression fixtures | Restored copy contains the fixture without overwriting an existing project; unsafe/unowned operation is rejected; original remains usable; only intended owner can start |

Do not test destructive policy by attacking a real user resource. Use existing safe fixtures
for negative cases. Do not use docs' production-oriented sample commands literally; bind every
instance target to the authorized disposable scenario. If U04/U05 need Vault services not yet
available during Proof #1, run there during the supported Vault/maintenance scenario before
teardown and before final acceptance. Missing backup/pairing is not permission to skip them
silently. A bounded real-use test gap gets explicit evidence and an implementation action.

## M — maintenance and safety coverage, 5/5

| Operation | Required observable behavior |
|---|---|
| Repair | Repairs the supported disposable fault/owned integration without taking over foreign resources; authentic health restored |
| Clean Reinstall | Runs its supported backup/plan/ownership path and produces coherent restored installation; no silent deletion outside owned scope |
| Uninstall | Removes only owned integrations/resources per the actual supported uninstall contract; preserves promised user data/backups and foreign sentinels |
| Factory Reset | Enforces actual backup/confirmation/ownership requirements; resets only the documented owned scope; rejection cases fail closed |
| Reboot/Resume | Durable checkpoints survive required boundary; current transaction/payload resumes once; terminal receipt/install state/health verified |

Do not invent data-preservation semantics: read the current operation contract before each
scenario and assert those semantics. Use current focused Windows/safety sentinels, Host Agent,
ownership/recovery/destructive, Linux, Vault, surrogate and Tailscale gates. A deferred pairing
launch flag is not a universal waiver for the Tailscale release gate. Resolve it as the existing
contract requires; external authorization gaps remain documented blockers.

## Aggregate and non-VM prerequisites

Reuse exact unchanged durable evidence; rerun affected suites once after material change:
WPF boundary; lifecycle observer; interactive logon; release integrity; final convergence;
Host Agent poison/security; relevant installer self-tests including standard-token behavior;
PowerShell parse checks; `git diff --check`; relevant Linux/Bash checks. Actual test parameters
and runtime context are in COMMAND-MAP. A test run under Administrator cannot prove a
standard-token path. Add targeted Windows PowerShell versus PowerShell 7 coverage where used.

Complete one coherent FullRelease, current RECONCILE, durable CLEANUP and final audit validation.
Attach result provenance; report PASS, FAIL, BLOCKED, NOT_RUN, UNVERIFIED and legitimate
contract-approved not-applicable outcomes distinctly. Never invent a new N/A waiver.

## DF-STABLE-20260906-D role-bound observer qualification

The pre-D production helper treated every lifecycle as Primary. The focused Laptop regression
therefore failed before correction at `production caller derives candidate Failover identity for
Laptop / Surrogate`; no VM or product process was used. Commit `8a34166` makes the production
identity policy candidate-bound and role-aware, not caller-injected:

| Boundary | Required and observed local result |
|---|---|
| Desktop production chain | Real lifecycle resolver/waiter/collector/completion path accepts exact Primary shipping stages and the bound Primary guest marker; Vault and cleanup names are not authorized |
| Laptop production chain | Same production path derives and requires exact Failover plus Vault shipping identities; both bound guest markers are required for completion |
| Negative evidence | Wrong role, cleanup name, unknown stage, stale time, wrong transaction/payload, malformed marker and nonmonotonic progress remain rejected |
| Error normalization | Original collector errors and available rejected names survive; an absent historical name remains absent and is not reconstructed |
| Cleanup summary | Only PASS run-owned exact-proof cleanup with complete Hyper-V and VirtualBox in-L1 inventories publishes derived L1/L2 summaries; CLI-only absence is rejected |

Post-correction local results: lifecycle 164/164, WPF 46/46 and harness 112/112 PASS.
These are tooling-only qualification and no proof credit. The exact signed candidate remains
unchanged. D's first Proof #1 must use a new RunId, canonical CLEAN and fresh HOST-SAFETY after
native tooling provenance is frozen. Its reserved retry conditions are defined in WORKFLOW.md.

```


## FILE: docs/ai/devfleet-release/WORKFLOW.md

SHA256: 27f360ddc4f70be93ab23ab23808be08a456523453050347c624df0ce4e52c2e | Bytes: 15344 | Git mode: 100644

```
# Stabilization workflow and renewed runtime authorization

Policy ID: **DF-STABLE-20260905-A**. This is a new user-adopted orchestration policy,
not a finding about the old campaign. It explicitly authorizes validating the corrections
already written after the earlier 2/2 diagnostic cap stopped execution.

The original failures remain immutable history. Record this authorization as a continuation
linked to `evidence/campaigns/wpf-no-report-20260905-ledger.json`, not a reset of that file.
Do not amend immutable proof-start records or silently rewrite old attempt counts.

## Milestones — continue automatically while prerequisites pass

| ID | Objective | Exit condition / next action |
|---|---|---|
| S0 | Reconcile live state and sole ownership | Exact tuple, changed-file classification, active-run resolution, latest terminal states, test reuse and readiness gap are known |
| S1 | Validate corrected launch plumbing | Local affected behavioral contracts valid; real target initial/resume ContractProbe acknowledgements and identity readback pass; no product launched |
| S2 | Observe a real installation | Exact signed installer starts from canonical CLEAN, crosses required reboot boundaries, reaches genuine durable completion and authenticated health |
| S3 | Prove repeatability and real use | Two independent current qualifying proofs with required role coverage; U01–U05 actual-use/recovery acceptance recorded |
| S4 | Certify the frozen tuple | Current maintenance/sentinels, one coherent FullRelease, maintenance 5/5, all mandatory gates, RECONCILE and durable CLEANUP |
| S5 | Preserve and hand off | Final RELEASE-mode audit validated; DONE satisfied; stable source/artifacts pinned; feature handoff prepared |

At entry select the earliest milestone lacking **current valid evidence**. Skip none on
memory assertions; repeat none merely because a chat changed. Do not rebuild existing
launch code or add more observations before testing the corrected boundary unless source
or failed local tests identify a specific remaining defect.

For S1 use the existing diagnostic and real Windows PowerShell parser/interactive task path.
Confirm both initial and elevated-resume vectors, actual task principal/SID/session, staged
hashes and no product mutation. A successful ContractProbe satisfies S1 only.

For S2, prefer a properly configured real Proof #1 that also supplies the first successful
lifecycle observation. Do not add a redundant full-install smoke. Check the existing proof
entrypoint's real role coverage: its title alone does not prove Desktop or Laptop coverage.
If the entrypoint cannot represent a required role, minimally connect an existing supported
role path before freezing; do not invent a command-line switch or weaken the requirement.

S2 completion must establish actual checkpoint consumption, installed state, canonical
ownership, expected services and authenticated health, not just window text or exit 0.
Expected L1 reboot is observed by a changed boot identity; host reboot is forbidden.

For S3 run the second proof with a new RunId and clean starting state under the same tuple,
including prescribed Laptop/Failover/Vault and surrogate coverage. Only use the already
sanctioned surrogate in the authorized lab; do not touch the real Surface or create extra
host VMs. Attach real-use acceptance before the existing test teardown when supported.
No manual console interaction or diagnostic checkpoint can silently earn clean automated
certification. If a manual diagnostic was needed, disclose it and repeat the qualifying
scenario cleanly after correction.

For S4 follow the existing native phase dependency order. Reuse evidence across adjacent
checks only when the native contract explicitly permits it. One coherent successful
FullRelease is required; failed or historical runs cannot be stitched together.

## New bounded allowance — startup is not a full-install attempt

These are proposed controls adopted by the user's continuation prompt, not historical facts.
Counters persist across pauses, compaction, new RunIds and model changes.

**Readiness allowance: at most THREE new top-level launcher-readiness invocations.**
One invocation can test initial and resume modes in the same bounded run. The first tests
the existing correction. Up to two further invocations require a distinct evidenced,
corrected defect with focused local validation. No identical blind rerun. The previous two
attempts remain recorded as historical 2/2 and do not consume this explicitly renewed allowance.
Pure local tests and read-only HOST-SAFETY checks are not live invocations, but do not loop
over failed prerequisites. Count a readiness invocation before it mutates/starts the lab;
record failures before product launch accurately. If the product unexpectedly launches,
classify conservatively as real product execution as well; do not hide it as a cheap probe.

**Product/certification allowance: required first executions plus at most TWO corrective
replays in total.** The baseline executions are Proof #1, Proof #2, prescribed focused
maintenance/sentinels and one FullRelease, with native deduplication where permitted.
This is not two attempts per phase, per model or per failure class. Any replacement/replay
of a product, proof, maintenance or FullRelease invocation consumes the shared replay pool,
including failures before launch after entry into that product invocation. A changed candidate
or tooling tuple does not reset the pool. Each invocation is reserved before start; capture
actual productStarted as true/false/unknown in its result. Required phases not yet attempted
are not replays. Successful first executions do not consume corrective replays.

A replay requires a narrow proven cause, a correction, a relevant test demonstrating the
behavior, and fresh safety/coherence. Proofs invalidated by material changes must be
requalified honestly; this can consume remaining replays. If the remaining pool cannot
finish current qualification, stop with the precise gap instead of using stale passes.
The point is to permit testing a demonstrated correction, not to authorize serial guesses.

Stop speculative runtime before exhaustion if the same unexplained failure recurs, evidence
remains blind, a substantial new shipping defect emerges, or ownership/security is uncertain.
After exhausted readiness/replay allowance, produce a focused current diagnostic closeout;
source-only analysis does not grant more VM attempts. Additional runtime needs new explicit
user authorization. No renamed campaign, hidden retries or changing limits inside the ledger.

## Before every real operation

Write a compact attempt entry with RunId; class; policy/counter reservation; question;
exact candidate/shipping/release/tooling identities; actual entrypoint/parameters/script
hash; expected semantic observations; operation and enclosing deadlines; cleanup owner;
HOST-SAFETY evidence; and protected-resource fence. Reuse the existing native ledger when
appropriate; otherwise use `audit/agent-memory/attempts/` records, not another promotion engine.

Derive finite deadlines from live owners, not guessed campaign length. Preserve
`operation < stage < role transaction < observer absolute < release watchdog` and a
separate semantic no-progress watchdog. Child calls consume remaining owner budget.
A small acknowledgement deadline is not a limit on the whole valid installer lifecycle.
Fail an invalid parent/child budget before VM mutation, not by clipping a valid child.
Do not extend absolute deadlines because CPU, PID or UI activity changes.

## When observation fails

Require the last durable boundary, exact launch/product identity, raw error, elapsed/remaining
owner budget, valid product progress and process exit information. Write primary failure
before optional UIA diagnostics. A UIA call that hangs must not block its supervisor's
terminal report or steal ownership of legitimate installer descendants.

If the observer still cannot explain the state, use a supported, exact-L1-bound console
observation plus product logs before another broad source search. Avoid the same stuck UIA
call for this fallback. Capture only that disposable VM, not the host desktop or unrelated
applications. Do not capture credentials. If no safe supported console capability exists,
request one targeted observation from Dylan; do not claim computer-use capability or mutate
the host to obtain it. Preserve/terminalize the bounded operation safely rather than wait forever.
A manual observation diagnoses; it does not replace the mandatory automated proof.

## Freeze and execute

Land focused fixes, tests and stable orchestration inputs before certification. Freeze material
shipping and harness code across successful qualifying runs. Markdown runtime memory can update
under its non-shipping audit path; verify actual inventory rules and never exclude real product
or harness inputs to avoid invalidation. Do not rerun candidate finalization just to capture a
memory edit. Do not edit acceptance criteria to match an observed failure.

Local harnesses own long waits. Use long supported waits or sparse batched state-change checks;
no continuous model polling, helper waves or side work on the same lab. Continue until a true
release, concrete blocker, or user pause—not until a plan or documentation update is written.

## Adopted supplement — DF-STABLE-20260906-B

The user explicitly adopted **DF-STABLE-20260906-B** after DF-STABLE-20260905-A was
exhausted. It does not reset or relabel any prior attempt. Historical diagnostics remain
2/2, readiness remains 3/3, and shared corrective product replays remain 2/2.

This supplement authorizes exactly **one additional exact Proof #1 replay**. Reserve it
before entry and use a new RunId. It is conditional on all of the following:

- focused production-path regressions for durable product progress, immutable report
  deadlines/identity, stuck UIA, and conservative L2 absence are passing;
- the material tooling correction is committed and frozen;
- live candidate, shipping, release, tooling and signed-artifact coherence is current,
  with no shipping-input drift or rebuild requirement;
- sole campaign ownership and the exact L1/CLEAN immutable identities are reverified;
- fresh HOST-SAFETY passes at the prescribed boundary; and
- the exact proof starts from canonical CLEAN. A missing Multipass CLI alone is never L2
  absence: read-only in-L1 backend inventories must prove ABSENT or the result is UNVERIFIED.

Do not run another standalone ContractProbe or readiness invocation. This one replay is for
the real signed installation and qualifying Proof #1 path. If it passes, proceed to the
previously authorized, unattempted Proof #2, real-use/recovery, maintenance, FullRelease,
RECONCILE, CLEANUP and audit gates. Those first executions are not new replays.

If the supplemented Proof #1 repeats an unexplained failure, stop product retries and close
out with the exact evidence. A further replay requires new explicit authority. Neither a
chat restart, documentation change, tooling fingerprint refresh nor a renamed RunId creates
additional runtime allowance.

## Adopted supplement — DF-STABLE-20260906-C

The user explicitly adopted **DF-STABLE-20260906-C** for the Multipass/bootstrap boundary.
It preserves, without resetting or relabeling, historical diagnostics 2/2, readiness 3/3,
DF-STABLE-A corrective replays 2/2 and DF-STABLE-B replay 1/1.

This supplement authorizes focused non-VM source diagnosis, behavioral regressions and the
smallest evidence-supported correction of stdin supervision, bootstrap input and guest-marker
observation. Shipping-input edits must be frozen, committed and used to build/sign/bind one
truthful replacement candidate; edited shipping scripts may not be injected into the old signed
installation and treated as exact-candidate proof.

After those regressions pass, it authorizes at most **one instrumented live diagnostic** only
when the active substep remains unknowable without it, and **one corrective exact Proof #1
attempt** only after the correction, current candidate/tooling coherence, exact lab ownership,
canonical CLEAN and fresh HOST-SAFETY are established. The diagnostic 1/1 was consumed by
`e2e-multipass-bootstrap-diagnostic-20260906-c1` and earned no proof credit. It proved the active
substep was the unbounded runtime dependency/version probe before isolation or instance lookup,
not payload transfer or stdin bootstrap. The corrective Proof #1 remains 0/1 reserved. A
successful qualifying Proof #1
continues into the still-unattempted required downstream gates; a repeated unexplained product
failure stops further product retries.

Before a live attempt, evidence must distinguish instance readiness, payload transfer, stdin
delivery/closure, guest bootstrap entry and the first valid transaction/payload-bound guest
progress. The corrected production path additionally distinguishes Multipass resolution,
isolation, instance presence/absence, launch/start, readiness, transfer and extraction before
guest entry. Empty output or a failed native command is not marker absence, and process/CPU activity
is not semantic product progress. Helper creation remains globally exhausted at 6/6 after the
single authorized independent falsification review; all helpers must remain quiesced for runtime.

## Adopted supplement — DF-STABLE-20260906-D

The user explicitly adopted **DF-STABLE-20260906-D** for the role-bound product observer.
It preserves every earlier counter exactly: historical diagnostics 2/2, readiness 3/3,
DF-STABLE-A corrective replays 2/2, DF-STABLE-B replay 1/1, and DF-STABLE-C diagnostic
1/1 plus proof 1/1. It authorizes no readiness or standalone diagnostic operation.

The first D exact Proof #1 may start only after the production lifecycle derives its exact
candidate-bound product targets by role: `Primary / Desktop` observes Primary only, while
`Laptop / Surrogate` observes Failover plus Vault. The harness cleanup identity is never a
product target. Missing, unsupported, wrong-role, stale, malformed, wrong-transaction or
wrong-payload evidence fails closed and cannot establish completion. Focused production-path
tests must replace only external process/VM/transport I/O and must exercise the real resolver,
waiter, collector and completion authority before the attempt is reserved.

D authorizes **one new exact Proof #1**. One reserve retry exists only if that attempt is
stopped by a newly proven narrow harness-only defect, a behavioral regression demonstrates
the correction, shipping inputs remain unchanged, and exact cleanup plus coherence are
verified. An unexplained stall, product failure, environment failure or repeated class does
not unlock the reserve. A passing Proof #1 continues directly to the unattempted downstream
gates under DONE.md; a downstream failure grants no new replay.

Run-owned exact-proof cleanup must publish current derived terminal summaries through the
validated cleanup evidence producer. CLI absence alone is insufficient for L2 ABSENT: the
source record must contain complete successful read-only in-L1 backend inventories. Derived
summaries preserve source RunId, SHA-256 and original UTC instants and explicitly remain
safety cleanup rather than certified release CLEANUP.

```


## FILE: docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/AUTHORIZATION.md

SHA256: f2b7119dd