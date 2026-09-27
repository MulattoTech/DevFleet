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
