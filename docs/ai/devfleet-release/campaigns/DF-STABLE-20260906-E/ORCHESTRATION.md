# Sol coordinator, elastic Luna helpers, single lab owner

## Execution policy

Sol XHigh stays coordinator; changing root models is not part of this amendment. Default
helper is `gpt-5.6-luna` at `high`; choose `medium` for bounded indexing/comparisons and
`xhigh` for difficult causal/invariant questions. Use only efforts the catalog supports.
No blanket XHigh for every grep. Terra/Spark remain optional only for a genuinely better
small task and a backend-verified native route; do not spend a wave fixing model routing.

The launcher requests TWELVE concurrent helpers (thirteen threads including root in V2).
This is a concurrency envelope, NOT a lifetime helper count or quota to fill. Start with
up to four useful independent lanes; expand only when the task graph and resources justify
it. Close finished workers and reuse their slots; keep creation history, status and actual
model/effort. Respect any lower actual backend, account, rate or host-resource limit.

Depth is normally root → specialist → focused worker. Deeper delegation is authorized when
Sol assigns a concrete independent subproblem and a bounded slot reservation; arbitrary
extra layers that just relay messages are waste. All descendants share ONE global pool.
`agents.max_depth` does not enforce depth in V2. Native limits and actual tools win.
No separate Codex CLI/app-server fleet, external Ralph plugin, or custom orchestration daemon.

## Scheduling and slot ownership

Sol maintains TEAM.md (and a small JSON projection when native operations need it) with
slot, agent ID/path, parent, depth, task ID, source/evidence fingerprint, requested/effective
model/effort, state and reserved descendant slots. Reserve before spawning; count pending
spawns and waiting supervisor threads. Reclaim only after known termination/closure; an
unknown agent is not a free slot. Failed routing is recorded once and falls back to verified
Luna or root execution, not a retry storm or silent model substitution.

A parent can allocate only the unused descendant slots leased to it. It cannot create its
own pool or pass along copies of the same reservation. Every packet includes the global
policy, exact remaining reservation and expiry/stop condition. Grandchildren/deeper workers
must inherit the same lab and authority prohibitions. Sol may flatten the tree when this
is faster. Native metadata, not a worker's self-description, establishes its routing.

## Initial independent lanes — adapt to current evidence, do not force all four

| Lane | Suggested effort | Deliverable |
|---|---|---|
| Dependency/environment analysis | Luna high | Interpret frozen service/backend/capacity evidence; rank discriminating experiments, not speculative host changes |
| Production call-path analysis | Luna xhigh when needed | Trace exact candidate launch inputs, identity, image, cloud-init, account context and observation interaction |
| Behavioral regression/collector work | Luna high | A bounded failing production-path test or isolated collector prototype in assigned scratch, with before/after expected outcomes |
| Evidence/cleanup adversarial review | Luna high or medium | Falsify causal claims; check safe checkpoint/resource identity, collector redaction, missing data and eventual gate coverage |

Sol handles live observations, integration and decisions. A specialist must return the useful
answer promptly, not a new general architecture or another broad project audit. Do not send
identical questions to many agents and vote. Use at most one fresh independent review of the
integrated correction unless new evidence changes it.

## Real parallelism without shared-state corruption

Helpers read root-pinned immutable snapshots of only relevant current files/evidence. Include
exact source commit/file hashes; never accidentally inspect `audit-extract` as current source.
Normal context is a concise self-contained packet (`fork_turns="none" where supported), not
the entire large root thread. Give tests the actual production path, not a helper that bypasses it.

Helpers may write only their assigned `outputs/agent-scratch/DF-STABLE-20260906-E/<TaskId>/`
(or another root-verified nonshipping ignored scratch path). No canonical source, .git,
shared memory, candidate, signature, native release evidence or shared test cache writes.
Use isolated fixtures/temp paths and existing runtimes; no global packages. Proposed patches
are reviewed/applied by Sol. Root tests the integration before material source freeze.

Only Sol starts, stops, snapshots, restores, queries or otherwise operates live lab interfaces.
Helpers request observations from Sol; they do not each run `multipass list`, remoting calls,
Hyper-V queries or watchdogs. This avoids accidental observer contention with the daemon.

During a focused diagnostic, up to TWO lightweight helpers may analyze already captured
immutable artifacts while the local harness waits, provided fresh resource checks permit it.
No local test suites/builds/scans or writes to frozen material inputs during a live run.
Throttle to zero on pressure or when no independent useful work exists. This limited overlap
supersedes the previous blanket pre-runtime helper ban for DIAGNOSTICS ONLY.

Before exact proofs, maintenance runtime or FullRelease: all helpers and their local child
processes must be completed/quiescent. Freeze material source/tooling. Serializing the single
lab is deliberate; parallelizing analysis does not make two competing VM owners safe.

## Worker packet/result contract

Packet: TaskId; exact question; relevance to current blocker; input paths/hashes; known solved
issues; allowed scratch path; expected deliverable; tests allowed; budget/stop; parent/depth;
reserved child slots; authority/safety restrictions; no secret or live-resource access.

Result: finding/no-finding; exact references; proven vs inferred vs unknown; smallest fix;
falsification/regression; actual tests/exit/output completeness; changes only in assigned
scratch; descendants closed. Root records acceptance/rejection and rationale. On cancellation,
workers return useful partial evidence instead of continuing silently.
