# DevFleet source part 054

Full-source UTF-8 byte interval [2464500, 2511000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: bba6ba7f45770626bd3e7d627c1dc7780e9bb2803ffca6efa75b014793bfdc69

<!-- BEGIN SOURCE SLICE -->
ovided harmless smoke/health/test operation and inspect returned operation status/logs | Real workload starts and becomes healthy; operation ID reaches terminal success; UI result agrees with backend/container evidence |
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

SHA256: f2b7119dd9724aaa251f560317903c3550535f8a7e7b4cbf2cf75f5263769756 | Bytes: 6427 | Git mode: 100644

```
# E authorization and unchanged safety contract

Effective only when adopted by the user in the current Codex thread. Dylan approved the
four decisions recorded in START and authorized useful Luna delegation/nesting and a
Ralph-style continuous improvement loop. The operating values below are this kit's
concrete implementation of that approval, not claims about platform-enforced guarantees.

## Superseded procedural restrictions

E replaces the exhausted A–D per-invocation reauthorization/closeout-only rules with ONE
bounded diagnosis → demonstrated correction → validation → full-release continuation.
Old counts and outcomes stay immutable historical evidence; do not reset or spend an
old conditional reserve. Use E's own ledger. A failed but informative experiment does
not require another user prompt when its next discriminating step fits E.

E replaces the six-helper LIFETIME creation quota. Reuse concurrent slots and create new
useful helpers as needed under ORCHESTRATION. Old six-used records remain history, not
remaining authorization. The old depth-2 prohibition is replaced by root-approved deeper
delegation within the same global pool. This is NOT six or twelve slots per parent.

Helpers may write requested reports/proposed patches and run bounded local tests ONLY
in root-assigned, isolated scratch directories. Sol alone writes/integrates canonical
source/tooling/authority/memory and commits. Helpers never operate the lab or signing.
During diagnostics, limited immutable-snapshot analysis may overlap local runtime as
specified in ORCHESTRATION. Before exact proofs/FullRelease, quiesce every helper.

E explicitly permits one reusable, temporary diagnostic checkpoint of the exact existing
L1, with the checkpoint lifecycle in DIAGNOSTICS. Canonical CLEAN is untouched. It also
permits required diagnostic-only nested instances inside that L1, fenced by immutable
identity/proven ownership and an explicit root-owned resource ledger. It does not
permit a new host VM, another physical machine, protected production, or a preview release.

## Finite campaign envelope

- Up to TWELVE focused mutating diagnostic experiments for E, shared across all roles,
  hypotheses, restarts and descendants. An invocation that starts/resets a launch or
  mutates a dependency as an experiment consumes one slot, even if it fails before boot.
  One planned launch with its bounded observation/cleanup is one experiment; do not
  hide several fresh launches inside a single numbered script.
- Necessary initial checkpoint preparation and standard cleanup are recorded operations,
  not extra product experiments. Their own finite deadlines and fail-closed errors apply.
  Read-only observations, local behavioral tests and analysis do not consume launch slots.
- After diagnosis/correction qualification: all required first executions of Proof #1,
  Proof #2, U01–U05, standard-token coverage, maintenance/sentinels, FullRelease and
  reconciliation/cleanup are authorized in the installed dependency order.
- Up to FOUR additional corrective runtime gate replays across E. Each requires a new,
  demonstrated, in-scope correction or controlled environment repair and focused evidence.
  It is not four retries per gate, agent, role or candidate. An unexplained repeated full
  install is NOT eligible. Never reuse or splice failed FullRelease RunIds into success.
- Source/local-test iterations have no arbitrary numeric cap while they add validated
  information. LOOP's no-information detector, actual usage limits and user stop remain.
  These generous ceilings are not targets and cannot be increased silently by Sol.

A narrowly proved downstream defect may be corrected within the SAME envelope without
another permission message. New architecture, protected-resource access, security weakening,
new host configuration, or a new extensive failure class requires escalation. Do not keep
performing speculative full installations to consume the allowance.

## Lab and host fence

| Resource | Allowed identity |
|---|---|
| Workstation | MULATTOTECHBOX; never reboot/shut down |
| Workspace | `C:\Users\Dylan\Documents\Codex\2026-08-12\ex-2\work\DevFleet-v1.2.13-development` |
| L1 | `DevFleet-E2E-Win11-01`, ID `84b7d8b8-ee6c-4085-aa29-4b0adc316de2` |
| Canonical CLEAN | `DevFleet-E2E-CLEAN`, ID `19865b76-4c3a-44f7-ba39-841e9d3c40c9` |
| Known harness L2 | `DevFleet-E2E-Linux-01`, positively owned INSIDE exact L1 |

Product instances named `devfleet-primary`, Failover or Vault inside exact L1 and temporary
E diagnostic instances must be separately inventoried and fenced. Their names NEVER authorize
access to same-name resources on the physical host. Full inventory failure means UNKNOWN,
not ABSENT. Do not create a diagnostic VM in a different backend to claim the shipping backend
works. No simultaneous mutating experiments against the one daemon/L1.

Never touch AMD/Radeon, BIOS/UEFI, MulattoTechSurface, host `devfleet-primary`,
`devfleet-project-m-techlabs-job-finder`, `DevFleet-H10-Linux`, or other foreign/protected
resources. Never push GitHub; export signing keys; expose E2EAdmin plaintext/hash/DPAPI
or Host Agent token/HMAC; disable Defender/AMSI/security; weaken auth/ownership/trust;
clear legitimate servicing state to green a test; or perform F-005/formatter-only cleanup.

No new host resource allocation/RAM override, global installs, firewall changes, NAT/switch
changes, security-policy bypass, arbitrary app shutdown, or machine-wide workaround.
Fresh native HOST-SAFETY and exact ownership are prerequisites for runtime. Do not use this
approval to introduce `-KeepLab`, synthetic success, acceptance waivers or broad process kills.

Root may perform a documented, reversible non-security dependency recovery INSIDE exact L1
(e.g. the owned Multipass service), after evidence capture, no active install and a recorded
experiment. Prove its causal effect; restarting a daemon until it works is not a fix. A change
needed on normal installations must be supported/reproducible, not hidden in the diagnostic
checkpoint. Prohibited host/security changes still require stopping, not inventing consent.

Only sign with the existing `CN=DevFleet Private Personal Code Signing`, thumbprint
`DE42CD7369A01E9357BDA13597C0173E5E703E9D`, RSA 3072. Never export its private key.
Final or paused safe lab state: L1 OFF / L2 ABSENT, all owned nested instances accounted for.

```


## FILE: docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/DIAGNOSTICS.md

SHA256: 323a8c0b51355c4a9b3ef764c03e159013427483276dec3035c06214c417b621 | Bytes: 8689 | Git mode: 100644

```
# Multipass-first diagnostic matrix

These are isolated dependency/integration experiments, NEVER release proof. Diagnose the
last observed launch/daemon-readiness gap without redoing the solved WPF investigation.
Use existing safe harness primitives and actual command contracts; implement only missing
collector/test glue. Do not spend a long run merely to find which command is active.

## Prepare once; preserve canonical CLEAN

Reconcile sole ownership, exact L1/CLEAN GUIDs, candidate and live runtime before mutation.
Record actual L1 resources/free space and applicable dependency versions/backend, service
account/context, nested-virtualization exposure and network prerequisites via safe reads.
Compare candidate Primary/Failover/Vault demands with capacity INSIDE L1 and physical-host
headroom. Do not infer capacity from physical RAM alone, change host allocations, or assume
that a large dynamic disk reserves all its nominal size immediately.

Restore verified canonical CLEAN. Reach an ordinary prerequisite-ready state through existing
supported scoped installation/diagnostic primitives, with no active product transaction and
no run-created L2 instances. Do not erase checkpoints/receipts to simulate that condition.
Use the same applicable dependency version/backend as the candidate; do not silently upgrade
or switch a backend. Stop on required protected/security changes.

Create ONE separately named diagnostic checkpoint of exact L1 after safe quiescence. Record
actual new GUID, parent/source CLEAN GUID, VM ID, UTC, prerequisite/package versions,
configuration identity, and proof of empty owned L2 inventory. Prefer a shut-down, disk-
consistent diagnostic baseline when supported. Never rename, delete, recreate or overwrite
canonical CLEAN. If a reusable prerequisite state cannot be reached without fabricating
product state, record it and use the shortest honest supported diagnostic path instead.

A diagnostic checkpoint may contain local credentials/configuration: never export it, VM
disks, memory, DPAPI or secrets into an audit or helper packet. Before each restore capture
needed non-secret evidence; restore only when all experiment-owned processes are terminal
and owned nested resources have been accounted for. Checkpoint reuse must not retain the
running daemon's stale requests or a half-created VM and pretend it is an independent trial.

Delete only E's exact temporary checkpoint after diagnostics and before certification, using
supported removal/merge with bounded verification. Never manually delete AVHDX/VHDX files or
checkpoint chains. At an administrative pause, the prerequisite-only checkpoint may remain
local if logged and L2-free; final release/blocked closeout removes it when safe. A failed
merge/cleanup is reported, not concealed by claiming absence. Clean proofs use canonical CLEAN.

## Collector acceptance before launch

Use a tested bounded collector whose own failure cannot suppress the primary product error.
Record only allowlisted non-secret context and exact operation boundaries; never whole raw
command lines, secret-file contents/hashes, environment dumps or credentials.

Minimum observation set: run/experiment and context IDs; image/release identifier (and digest
where available); backend/version; requested resources; task/PID+creation/path lineage;
operation start/end/deadline/native exit; Multipass service events; applicable Hyper-V or
VirtualBox backend events/VM IDs; guest boot/IP/SSH/cloud-init state when accessible; last
valid product marker plus reader status; dropped/truncated/timeout flags. Discover actual
log/provider availability. An absent provider is unavailable evidence, not a clean log.

Capture independent service/backend evidence even if Multipass CLI inventory times out. Keep
one serialized bounded CLI probe stream, no flood of overlapping `list/info` queries. A
backend-created VM, a boot screen, an address, working SSH, completed cloud-init and completed
DevFleet are DISTINCT milestones. Diagnostic breadcrumbs do not fabricate semantic product
progress or move the shipping observer's absolute deadline.

Test collector success, unavailable source, nonzero exit, timeout, malformed data, wrong VM,
wrong run, partial output, redaction and primary-error preservation with local fixtures first.
Maintain existing WPF/role/marker/ownership/deadline contracts. No source-string-only PASS.

## Ordered comparisons — branch on evidence rather than run every cell

| ID | Controlled question and setup | Required distinguishing evidence |
|---|---|---|
| M0 | Current dependency/backend and capacity survey; no new launch | Actual inside-L1 CPU/memory/disk, dependency identities/service state, readiness and observation plan; no mutation on unsafe conditions |
| M1 | Plain Multipass launch of the candidate's applicable Ubuntu image, without DevFleet or release observer; use safe modest resources recorded as diagnostic deviations | Did image acquisition, backend create, boot, IP, SSH and cloud-init complete? Native results, backend/service events and cleanup identity |
| M2 | Same image/backend/account baseline; use exact product CPU/memory/disk profile, without DevFleet-specific cloud-init | Is the difference resource/profile related? All non-target differences, including warm/cold image cache, disclosed |
| M3 | Exact relevant candidate launch inputs/cloud-init in the ordinary equivalent context, without release observer | Which additional input triggers failure? Real current candidate content/identity; approved test credentials handled locally; no fake install-state files |
| M4 | Production invocation and observation enabled, from equivalent diagnostic baseline | Does account/environment, production call path or observer interaction change the result? Real argument builder and consumers; no production identity mocked away |
| M5 | Evidence-supported minimal correction and repeat of the implicated comparison | Causal discriminating evidence, focused behavioral/environment regression, exact change and stable required launch path |

M1's smaller profile is for diagnosis ONLY. It cannot certify the larger shipping config.
Where two steps are identical, combine them and record equivalent coverage. When M1 fails,
stop the later product cells and investigate that dependency first. When M1 passes and M2
fails, diagnose capacity/backend rejection. When M2 passes and M3 fails, isolate launch inputs
or guest initialization. When M3 passes and M4 fails, isolate invocation/observer interference.
Do not infer root cause from this table without actual controlled evidence.

Change ONE causal factor per contrast where possible. Immutable identity/run names naturally
change; record them. Same image digest and cache condition matter: cold versus warm startup
is not a clean proof of a code correction. Cache warming may be a useful controlled experiment,
not a hidden precondition smuggled into certification. Diagnostic names are never accepted as
product markers; exact product role/transaction/payload identity remains required in proofs.

No plain diagnostic cloud-init may accidentally contact protected projects, real external
secrets, or activate production integrations. Use disposable test values only where supported
and label deviations. A launch-only M3 does not pass bootstrap/services/ownership/health.

## Failure and screenshot fallback

Before reset/restart/cleanup, collect the smallest sufficient non-secret failure evidence.
Multipass launch timeout may mean download, backend creation, boot, IP, SSH, daemon contention,
or initialization trouble; root must locate the actual boundary. Do not choose one by CPU.

Use existing safe console/serial capture if available and bound to exact nested VM identity.
Otherwise ask Dylan once for the specific console within exact disposable L1, including the
experiment/VM name and what must be visible. Do not ask for host desktop/credential screens.
This is the already approved targeted observation, not a manual installation that earns PASS.
Provide a bounded opportunity for it during an active diagnostic; never wait indefinitely with
VMs running. On unavailable input, preserve evidence, terminalize safely and record the exact
observation needed. Console images are non-authoritative context alongside actual run records.

After a correction, document whether it is shipping, tooling, or an environment precondition.
A necessary environment setup must be reproducible through supported paths from canonical
CLEAN; a successful repaired diagnostic snapshot alone is insufficient. No protected host
configuration fix is implicitly authorized. Follow RELEASE-CLOSEOUT before certification.

```


## FILE: docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/LOOP.md

SHA256: db08c6c3d8fed87cc3d6c807d494b52a5b09c956a3c17624473b329bb751652e | Bytes: 6309 | Git mode: 100644

```
# Evidence-driven goal loop and durable memory

Use native Codex Goal mode when available. This is a Ralph-INSPIRED bounded work/check loop,
not a fresh-process shell loop and not permission to run forever. No hook that reruns the
same prompt until it sees a magic word. A string saying PASS is not the validator.

## One iteration

READ current state/evidence → choose ONE unresolved question → delegate independent support
→ execute the smallest informative action → verify actual result → integrate a demonstrated
correction if warranted → write concise state/memory → continue to the next justified action.

Root stays responsible for the critical path. Parallel helpers cannot choose competing live
experiments. Avoid plan-only turns when authorized execution can proceed. A negative result
that falsifies a hypothesis is useful progress; another unchanged log dump is not.

Before runtime, reserve an experiment or corrective replay and record question, input tuple,
controlled differences, expected distinguishing observations, finite time budget, native
cleanup owner and source baseline. Counters are durable before launch and are never refunded
because a process failed early. Read-only/local tests are separately classified.

The loop may recover from narrowly proved in-scope downstream defects without another user
prompt. Historical permission exhaustion is not a blocker under adopted E. Diagnosis still
has to justify another expensive installation; a new model/agent/session does not justify it.

## Non-progress circuit breaker

Compute/record a compact fingerprint from candidate/material-tooling + failed operation +
normalized failure class + actual last stable observation + relevant environment/input
state. Track eliminated hypotheses, new measured boundary, tested patch or satisfied gate.
New comments, formatting, agent count, RunId or timestamp alone are not new information.

After TWO consecutive iterations on the same fingerprint with no new evidence, falsified
hypothesis, demonstrated correction or satisfied gate: do not perform a third blind runtime
attempt. Synthesize once using existing evidence, use the targeted console fallback when it
can distinguish the alternatives, or escalate with a focused diagnostic package. A local
negative test with a new falsification is not counted as an unchanged iteration.

Stop substantive work for: exhausted E runtime allowance; repeated unexplained failure;
unsafe/ambiguous ownership; actual platform/security restriction; prohibited new scope;
user stop; usage/budget exhaustion; required unavailable observation. State the specific
condition and earliest unresolved boundary, not merely that a counter is nonzero.

## Goal lifecycle is separate from release truth

Use `/goal <objective>` to establish the persistent objective; `/goal` shows it. User controls
include `/goal pause`, `/goal resume`, `/goal clear`. Runtime capability and budget can vary.
A goal is thread-scoped, not an OS service: do not promise that it runs with the CLI closed,
restarts after a crash, bypasses quotas, or enforces safety outside the active runtime.

Check actual goal/budget capability once. Do not automatically increase budgets, use paid
usage resets, start substitute threads or change global configuration to escape a limit.
If Goal mode is unavailable, execute this workflow as a normal prompt in the same session;
do not install an external Ralph tool or start researching orchestrators instead of DevFleet.

On a real blocker, write E state `BLOCKED_NEEDS_INPUT` or `BLOCKED_BUDGET`, safely close the
lab, report the cause and ask the user to pause the goal if it remains active. Do not claim
that the model can invoke a lifecycle action the actual tool schema does not support. A
native continuation after an E blocker must not reopen runtime; return the unchanged blocker
without another tool/retry loop. Never mark the release goal complete because a diagnostic
package validated, cleanup succeeded, or a guardrail stopped the work.

## Local wait ownership

Use the existing finite local harness to own waiting, primary outcome, evidence and exact
cleanup. Verify that contract before long operations. Do not make this a new background
service. Use supported long waits/event notifications; where polling is necessary, batch
it and act only on a meaningful state change or terminal outcome. Goal interruption or
an agent finishing must not orphan a scheduled task/process/VM. Keep the CLI open during work.

Do not shorten a valid critical path just to fit an arbitrary campaign duration. No parent
clamping below child requirements; no fresh full timeout after owner time is consumed;
no increased global process timeout; CPU/PID churn does not reset semantic progress. The
1,800-second product semantic watchdog remains unless a separately proved contract defect
justifies a tested correction—not because a diagnosis needs more time.

## Memory and resume

Store concise E STATE.json + STATE.md, EXPERIMENTS.md, TEAM.md and DECISIONS.md beneath
`audit/agent-memory/campaigns/DF-STABLE-20260906-E/`. These are workflow state/indexes, NOT
release authority. Use MEMORY-TEMPLATES only for absent files; never reseed existing state.

Root is their sole writer. Update atomically/read back at launch reservation, meaningful
result, accepted/rejected hypothesis, source freeze, proof outcome, pause, and closeout.
Keep large logs in their native run directory; use exact paths/hashes rather than copying
them into context. Link proven anti-regressions into existing EDGE-CASES with applicability,
regression and evidence. Preserve disproved ideas as disproved; no mythology from old prose.

For the native audit builder, explicitly include these exact E docs/memory/experiment
records through its sanitized current allowlist when needed. Do not dump all scratch, old
archives, raw logs, secrets or VM files. Test any packaging change before finalization.

Resume reads small state then checks live authority/process ownership. An incomplete last
operation must be reconciled, not relaunched. Claim neither cleanup nor no-active-processes
from unavailable inventory. If JSON/Markdown/native records disagree, reconcile from native
evidence before mutation. Compaction/resume preserves counters, leases and next action.

```


## FILE: docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/MEMORY-TEMPLATES.md

SHA256: 49bb79e111ca5d8ec0227e5c123aea59901fab64e0cfa323fca6bfd84fe54d35 | Bytes: 3864 | Git mode: 100644

````
# E memory templates — root initializes only missing files

Destination: `audit/agent-memory/campaigns/DF-STABLE-20260906-E/`.
This document is a TEMPLATE. No proposed field is an observation or release authority.
Root fills live values on adoption, atomically saves/read-backs, and uses existing native
run ownership mechanisms rather than pretending this JSON alone is a mutex/watchdog.

## STATE.json (small machine-readable workflow projection)

```json
{
  "schemaVersion": 1,
  "campaign": "DF-STABLE-20260906-E",
  "authorityKind": "workflow_projection_not_release_authority",
  "updatedAtUtc": null,
  "status": "NOT_STARTED",
  "phase": "RECONCILE",
  "rootSessionId": null,
  "nativeAuthorityPath": "evidence/CURRENT-RELEASE-AUTHORITY.json",
  "nativeAuthoritySha256": null,
  "tuple": null,
  "activeRun": null,
  "diagnosticExperiments": {"consumed": 0, "limit": 12},
  "correctiveGateReplays": {"consumed": 0, "limit": 4},
  "helperConcurrency": {"requested": 12, "effective": null, "open": 0},
  "diagnosticCheckpoint": null,
  "lastFailureFingerprint": null,
  "unchangedIterations": 0,
  "provenFindings": [],
  "openHypotheses": [],
  "nextAction": "Reconcile live ownership and evidence before mutation",
  "stopReason": null,
  "labState": {"l1": "UNVERIFIED", "l2": "UNVERIFIED", "evidence": null}
}
```

On first adoption historical A–D counts are LINKED, not entered as consumed E operations.
Any already-existing E counters survive restarts and reinstallation; unknown running operations
must be reconciled before new reservations. A new user-authorized policy is not a rewritten
historical result. Increment E counters durably before their qualifying operation starts.

## STATE.md

Current objective / phase / one exact next action; native evidence pointer/hash; candidate and
material-tooling identities; last proven observation; hypotheses marked unproven; resource/
process ownership; checkpoint status; remaining operational envelope; current stop condition.
Keep this small enough to read every resumed session, with links rather than pasted logs.

## EXPERIMENTS.md

| Experiment | Question | Inputs/baseline/image/cache/context | Controlled change | Expected contrast | Command family + deadlines | Outcome + actual evidence | Cleanup | Counts |
|---|---|---|---|---|---|---|---|---|

Allowed outcomes include PLANNED, RUNNING, PASS_DIAGNOSTIC, FAIL, TIMEOUT, INCONCLUSIVE,
CANCELLED and BLOCKED. PASS_DIAGNOSTIC is never Proof PASS. Record complete/partial/error
collectors and original UTC instants, not guessed normalized values. No raw secret arguments.

## TEAM.md

| Lease | Agent ID | Parent/depth | Task/source fingerprint | Requested/effective model/effort | Descendant reservations | Status/result | Root disposition |
|---|---|---|---|---|---|---|---|

Slots represent concurrent leases, NOT lifetime quotas. Link the historical six helpers instead
of erasing them. Pending spawns count. Close/release only after confirmed termination; lower
actual backend capacity wins. Snapshot-only workers cannot initiate their own live reads.

## DECISIONS.md

For each consequential choice: hypothesis; concrete evidence; accepted/rejected/unknown;
minimal change; classification (shipping/tooli