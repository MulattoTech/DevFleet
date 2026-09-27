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
