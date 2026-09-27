---
name: devfleet-evidence-triage
description: Read and reconcile DevFleet release evidence without mutating the lab, candidate, or promotion state. Use for status checks, stale/conflicting summaries, blocker diagnosis, or deciding which evidence is authoritative.
metadata:
  short-description: Reconcile DevFleet release evidence read-only
---

# DevFleet evidence triage

This skill is read-only. Do not launch proof, rebuild, reserve attempts, clean labs, refresh
credentials, edit authority, or mutate release state.

Read the smallest set needed, preferring current native surfaces:
- `evidence/CURRENT-STATUS.json` for current high-level status and candidate binding.
- `evidence/CURRENT-GATES.json` for current gate detail.
- `evidence/FULLRELEASE-SUMMARY.json` for the active FullRelease run and phase.
- `evidence/CURRENT-RELEASE-AUTHORITY.json` when authority detail is needed.
- `finalization-state.json` only as a compatibility/closeout summary; compare timestamps
  and authority IDs before treating it as current.

Apply the precedence rules in
[references/evidence-precedence.md](references/evidence-precedence.md).

Report:
1. candidate/tooling identity coherence;
2. newest authority timestamp and ID;
3. proofs passed/required;
4. active FullRelease run, last completed phase, and current phase;
5. earliest incomplete/failed gate;
6. cleanup/HOST-SAFETY state when available;
7. whether any file is stale or contradictory;
8. the single next safe action.

Never promote a release from inference. If evidence disagrees, say which surface is newer,
which one is stale/secondary, and what must be refreshed or reconciled.

## Fast prior-proof revalidation

For exact proof files stored in a phase/lineage subdirectory or repeated candidate/token checks, use the `inspect` command in [devfleet-e2e-fastlane](../devfleet-e2e-fastlane/SKILL.md). It invokes unchanged native validators against a temporary, hash-bound view outside the checkout. It creates no proof or native authority and cannot start a VM. Do not invoke a mutating finalizer merely to repair a stale display.
