---
name: devfleet-release-control
description: Continue, repair, certify, pause, or hand off the DevFleet v1.2.13 release campaign using current native authority and evidence-preserving corrections. Use for DevFleet release execution; not for feature development or production deployment.
metadata:
  short-description: Operate DevFleet release certification safely
---

# DevFleet release control

Treat this as an execution skill for the existing DevFleet release system, not permission
to redesign the product or weaken certification. Start at
`docs/ai/devfleet-release/START-HERE.md` and reconcile current machine-readable authority
before acting.

At session entry:
1. Read the root `AGENTS.md`.
2. Read `START-HERE.md`, `SAFETY-AND-AUTHORITY.md`, `WORKFLOW.md`, and `DONE.md`.
3. Read `audit/agent-memory/CURRENT.md` only as an index.
4. Read live authority/evidence for the current candidate and identify the earliest
   incomplete truthful gate.
5. If campaign E is adopted, route through
   `docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/START.md`.

Use native machine-readable authority for candidate identity, gate state, reservations,
RunIds, cleanup, and promotion. Markdown summaries and historical evidence never promote
a release.

For immutable release truth and host-safety boundaries, read
[references/authority-and-safety.md](references/authority-and-safety.md).
For harness/gate-mechanics repairs and corrective attempts, read
[references/correction-and-attempts.md](references/correction-and-attempts.md).

For pause, handoff, memory, and final packaging, read
[references/closeout-and-memory.md](references/closeout-and-memory.md).

## Execution loop

Reconcile live authority → diagnose the earliest failed/incomplete gate read-only →
make the smallest causal mechanics correction when justified → run focused regression
tests → reserve one bounded attempt in native state → fresh preflight → execute →
terminalize/verify cleanup → reconcile native authority again.

Do not spend another VM/lab cycle on an unchanged cause. A passing diagnostic, launcher
probe, source test, or fixture is not installed-product proof. Prefer a qualifying real
lifecycle run when prerequisites are already satisfied.

The primary/root agent is the single authoritative writer and lab operator. Helpers may
perform independent read-only analysis, code tracing, and focused review within the live
delegation limits, but may not become competing owners of the lab or promotion state.

After a meaningful result, update durable memory and the next action in the same turn.
On a real pause, blocker, or success, follow `CLOSEOUT.md`. Never create final acceptance
or claim `PASS — INTERNAL RELEASE ELIGIBLE` unless current native authority itself says so.

When the user asks only for status, prefer the reusable `$release-live-monitor` skill or
the project evidence triage skill instead of mutating release state. For DevFleet's compact
live panel, run `.agents/skills/devfleet-release-control/scripts/Watch-ReleaseStatus.ps1`;
use `-Once` for a snapshot.

## Fast VM-free feedback before another lab attempt

For slow lifecycle/reboot debugging, evidence-layout mismatches or a proposed proof rerun, use [devfleet-e2e-fastlane](../devfleet-e2e-fastlane/SKILL.md). Revalidate the current signed candidate and existing proof/token binding first; do not repeat a valid proof for a new model, conversation or skill change. Select only the relevant mocked/injected-clock regression area. These tests grant no certification or live-start authorization. The current user-selected ROOT remains sole operator; historical model names are not a reason to switch it.
