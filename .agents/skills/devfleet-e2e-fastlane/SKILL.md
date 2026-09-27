---
name: devfleet-e2e-fastlane
description: Use when DevFleet certification is slow, repeated VM retries are proposed, current proofs may be reusable, lifecycle timing or checkpoint evidence is confusing, or a Warp Time/simulation shortcut is requested.
---

# DevFleet E2E fastlane

Speed up diagnosis, not the meaning of PASS. The same candidate must retain its current proofs unless a native material identity actually changes. This skill and its reports grant **no release credit** and cannot launch a VM.

## Entry

Read native authority and the release-control skill; current user model/ownership policy wins over historical model labels. Start zero helpers when the next action is an already-authorized run. Do not repeatedly ingest the whole audit.

From the repository root:

```powershell
& .\.venv-test\Scripts\python.exe .\.agents\skills\devfleet-e2e-fastlane\scripts\fastlane.py inspect --repo .
& .\.venv-test\Scripts\python.exe .\.agents\skills\devfleet-e2e-fastlane\scripts\fastlane.py test --repo . --area quick
```

`inspect` is **READ_ONLY_REVALIDATION** of the real prior proof/token/artifact binding, not a new proof. It uses the unchanged native validators. Exact lineage-bound receipts are copied only to a temporary outside-repository view, so the native nested/root evidence-layout difference does not waste another lab run. No timestamp-based file selection or edited native receipts.

`test` uses existing native regression functions with mocked VM/transport I/O and injected `ClockProvider`/sleep. Reports/logs go outside the checkout. Choose one area: `clock`, `observer`, `vault`, `acceptance`, `quick`, or `all`; do not blindly repeat all areas at every turn. A nonzero exit, timeout or material drift blocks reliance on the diagnostic. Inspect failure logs, not just the summary.

## Live boundary

The security scan or another ROOT on this checkout must be quiescent or independently isolated before live ownership. No raw/no-override HOST-SAFETY pass means no certified FullRelease; permission for an experimental proof is not a change to the final validator. Refresh native host, current tuple, exact L1/CLEAN and required nested L2 state immediately before reservation/runtime. Diagnostic reports are never admission tickets.

## Shorten the feedback loop

Before a VM retry: preserve the actual failure, reproduce it with an existing callback seam, fix the source, test the failure and controls, then classify shipping/tooling drift. Reuse valid tests/evidence rather than rebuilding for a chat or skill change. Never patch packaged EXE/TAR/ZIP contents in place.

A same-candidate checkpoint may accelerate a separately authorized diagnostic after exact native provenance verification. An old installed checkpoint cannot validate a newer payload. Final certification remains one coherent current FullRelease with actual install/reboot, backup/restore, U01–U05 and certified cleanup. No historical phase stitching.

Do not alter VM/host clocks, shrink real timeouts, pre-mark stages, replace real authentication/health with fixtures, turn partial backup into success, or suppress a verified security finding. A time simulation is not a VM simulation.

See [checkpoint and timing guidance](references/acceleration.md). On closeout, record exact results, next falsifiable action and actual ownership/cleanup. Never claim the remaining runtime gates were tested by this fastlane.
