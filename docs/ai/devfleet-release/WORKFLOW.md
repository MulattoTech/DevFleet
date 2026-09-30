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

If the earliest native gate is blocked, finish any already-started operation's
terminalization and owned cleanup, then use the [release-control blocked-lane rule](../../../.agents/skills/devfleet-release-control/SKILL.md#blocked-lane-continuation).
The fallback lane is public/source-only and grants no new runtime allowance. Record
its issue or PR, VM-free verification, and next material native re-entry condition in
the ongoing goal and current master tracker. Do not append fallback activity as a
charged native attempt or alter the native ledger/private evidence during public work.
Return to the earliest native gate only after that condition changes and current
native authority, owner and HostSafety are freshly reconciled.

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
