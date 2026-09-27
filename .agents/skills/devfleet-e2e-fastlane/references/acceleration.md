# Faster diagnosis without counterfeit E2E evidence

## Evidence levels and commands

| Level | What it proves | Command |
|---|---|---|
| Source/mock regression | Decision logic on synthetic inputs; no VM | `fastlane.py test --repo . --area quick` |
| Native prior-evidence revalidation | Previously completed real proofs still bind to this candidate | `fastlane.py inspect --repo .` |
| Owned checkpoint diagnostic | Specific installed behavior at a proven checkpoint | Only the existing native diagnostic entrypoint, after exact provenance/safety/authorization checks |
| Current certification | A coherent installed FullRelease and all native acceptance criteria | Existing release-control workflow, not this skill |

All commands require the repository's existing Python runtime. PowerShell tests need PowerShell 7. No global packages are installed. The test allowlist cannot select installers, live proof drivers, signing, or FullRelease. Results are written to a new external directory and execution stops at a failed/timeout suite. If a timeout leaves process cleanup uncertain, resolve the exact test descendants before considering the lab.

The `inspect` command imports ONLY the trusted live repository validator, not code extracted from a supplied archive. It verifies the live candidate, fresh genuine standard-token receipt, both current proof roles, their source/artifact bindings and independence. Its temporary proof views resolve missing root-level receipt copies ONLY from the exact phase and checkpoint lineage already named in that same proof, with matching hashes. Existing bad canonical files cause failure, not silent replacement. No native proof bytes are repaired or created.

## What to test first

| Symptom | Area | Existing native seam |
|---|---|---|
| Endless heartbeat, early/late timeout, reboot generation | `observer`, then `clock` | Actual lifecycle/WPF state machines with injected ClockProvider and SleepProvider |
| Multipass inventory hangs, readiness identity mismatch | `vault` | Real nested-readiness scriptblock with mocked service, daemon, VM and clock providers |
| Backup/delete/restore binds to wrong installation | `vault` | Configured Vault fixture/Primary identity guards and Python scenario tests |
| Proof file layout, source/tuple drift, audit closure | `inspect`, then `acceptance` | Unchanged proof and final-acceptance validators |
| Unknown class | `all` once | Eleven explicit offline suites; do not loop until green |

Only repeat relevant tests after a change. Never infer that a cached console PASS still applies: the runner records actual script hashes and checks material/native inputs before/after. It does not cache PASS or reset qualification budgets. The full original test suites remain available for release-required broad validation.

## Clock manipulation versus time-controlled testing

VirtualBox's Time Manager implements `WarpDrivePercentage` to change virtual clock rate. This is not extra CPU, disk or network bandwidth. Do not turn it on in DevFleet's certification lab: watchdog, reboot, authentication, package and external-service time would no longer have the ordinary timing semantics under test. Host and guest clocks remain untouched by the fastlane.

The supported shortcut is dependency-injected test time. DevFleet already exposes this in its production lifecycle observer and WPF contract. `Test-VirtualClock.ps1` tests actual native deadline functions over a 25-hour horizon and the real wait loop at a 30-minute no-progress cutoff without waiting those hours. Its temporary observations are outside the native proof directories and grant no release credit. This is not a whole operating-system/VM simulator.

Primary references:
- VirtualBox Time Manager source, `WarpDrivePercentage`: https://raw.githubusercontent.com/mirror/vbox/master/src/VBox/VMM/VMMR3/TM.cpp
- .NET deterministic time testing: https://learn.microsoft.com/en-us/dotnet/core/extensions/timeprovider-testing
- Hyper-V checkpoint semantics: https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/checkpoints

## Checkpoint reuse rules

A checkpoint name is not provenance. Before a diagnostic restore compare exact L1 ID, checkpoint GUID, configured Primary/Vault identities, candidate build commit, payload hash, shipping/release/tooling tuple, installation transaction and origin RunId. Require the native provenance validator, not merely `checkpoint_assessment`'s offline field check. A hash of a manifest proves its byte identity, not that its claims were observed.

The old MAINTENANCE-READY checkpoint can contain old software even when its name matches. A shipping change invalidates reuse for testing the replacement product; do not restore an old installation and copy new PASS labels. An unchanged candidate with verified current checkpoint provenance can support a bounded diagnostic, but it does not replace independent CLEAN-start proofs or the single coherent final FullRelease.

Do not create/change canonical CLEAN to speed up the run. Standard snapshots retain VM memory, while production snapshots do not; restoring either affects state outside simple elapsed-time arithmetic. Never copy security tokens/SSH identity from a snapshot into unrelated machines. Do not share warmed test state between independent role proofs.

## Immediate constraints in this campaign

At authoring, candidate `4f1ca4570466f1595c0f05fb84eab408f6e99b31` had two independently validated role proofs and a matching Developer receipt. The actual new FullRelease was not run. Reconcile live files; this sentence is not authority.

Recorded proof start-to-cleanup durations were about 14m25s for Laptop/Surrogate and 12m33s for Desktop/Primary. The historical failed FullRelease spent roughly 12m each on dependency matrix/fresh install/reboot, 15m on Linux, and 15m on MaintenanceReady. These observations concern different provenance; they are not a finish-time prediction or current phase credit.

A separate security scan on this checkout and raw/no-override memory admission have been current interlocks. Do not override either in this skill. Verified high-risk findings require triage and an explicit release-scope decision; an operational test pass is not a clean security audit. Isolate or quiesce other workloads before live mutations, without killing user applications automatically.

Package caches/preverified download staging may reduce repeated I/O in future work, but must preserve vendor signature/digest and expiry/revocation policy, native entrypoint behavior and independent clean-state tests. That optimization is NOT installed by this skill.
