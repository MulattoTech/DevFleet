# Durable Markdown memory — maintained by Codex

Purpose: remember fixes, failures, decisions and next actions without re-reading giant
transcripts or turning guesses into facts. This is an agent-maintained file workflow,
not a database service, background daemon, automatic hook or guarantee of model compliance.
No new subscriptions, MCP servers, embeddings or global Codex-memory edits are needed.

## Where information belongs

| Path relative to repo | Meaning / authority |
|---|---|
| `audit/agent-memory/CURRENT.md` | Short navigation snapshot; exact next action and pointers; never release authority |
| `audit/agent-memory/INDEX.md` | Topic/keyword index into only relevant lessons |
| `audit/agent-memory/EDGE-CASES.md` | Stable anti-regression invariants, scoped by evidence and condition |
| `audit/agent-memory/DECISIONS.md` | Why an approach/policy was chosen and what would invalidate it |
| `audit/agent-memory/ATTEMPTS.md` and `attempts/` | Historical ledger pointers and newly authorized reservations/results |
| `audit/agent-memory/TEST-RESULTS.md` | Test IDs/inputs/outcome/evidence/limits; no inherited PASS without binding |
| `audit/agent-memory/HELPERS.md` | Compact projection of the native shared helper allocation |
| `audit/agent-memory/incidents/` | One durable record per meaningful failure class |
| `audit/agent-memory/sessions/` | Compact pause/closeout notes, created only at meaningful boundaries |

Use existing native JSON candidate/proof/release/attempt ledgers as the machine authority.
If a native ledger schema lacks a field, a separate Markdown reservation can record policy
accounting, but must not alter that schema or become a second release-authority generator.

## Write triggers — no routine manual journaling by Dylan

Sol updates memory in the same turn after: a test or live operation terminalizes; a cause is
proven or a hypothesis falsified; a fix is validated; candidate/tooling changes; a reusable
edge case is discovered; an authorized limit is consumed; or pause/blocker/release closeout.
Before a risky/long operation write its reservation and next expected evidence. After it
finishes reconcile result/counters before starting another. Do not add entries on every poll,
command or unchanged observation. Helpers return findings; only Sol edits shared memory.

A new fact record contains:
`ID; observed UTC; status; scope/tuple; symptom; evidence path + SHA-256 or exact symbol;
proven cause or hypothesis; action; regression; runtime validation level; invalidation trigger;
next action/supersedes.` Use `templates/INCIDENT.md` and `templates/ATTEMPT.md`.

Allowed labels: `HISTORICAL`, `HYPOTHESIS`, `PROVEN_SOURCE_DEFECT`, `FIX_IMPLEMENTED`,
`LOCAL_TESTED`, `LIVE_VALIDATED`, `RELEASE_CERTIFIED`, `FALSIFIED`, `SUPERSEDED`, `UNKNOWN`.
Do not flatten LOCAL_TESTED into LIVE_VALIDATED. The September 5 seed is offline and must
remain explicitly identified as such until new observations exist.

## Read and reuse rules

At resume read CURRENT + INDEX, verify live tuple, then read only matched incident/edge sections.
Before reopening a familiar issue, compare its exact symptom, validity scope and regression.
Reopen only with a recorded current contradiction or missing qualifying evidence; missing
release proof alone is not proof that every previously solved subproblem recurred.

Reuse a passing test only when relevant production/test/dependency/environment inputs match
its evidence. A recorded count without such provenance is informational, not certification.
When source changes, mark dependent results stale with a reason; do not delete their history.
A mutable summary cannot retroactively change the exact inputs of a completed proof.

## Bounded maintenance and integrity

Keep CURRENT approximately one screen (target <=150 lines) and INDEX <=100 lines. Put long
explanations in incident files. When a topic file grows past about 250 lines, archive closed
entries to a named incident/session and leave indexed summaries; do not lose provenance.
These are readability targets, not a reason to truncate essential evidence.

Write UTF-8 via temp file and atomic replace; Sol is the single writer. Preserve historical
facts and append corrections with `supersedes`, rather than quietly rewriting a false claim.
Use repo-relative links, UTC timestamps and explicit null/unknown values. No secrets, tokens,
credential hashes, private keys, unrestricted dumps or unrelated personal information.
Exclude installation backups/raw instructions from public or AI review bundles by default.

Dynamic memory is under audit to avoid routine edits becoming shipping changes in the
uploaded inventory model. Recheck live fingerprint rules. Freeze stable docs/skill/AGENTS
before qualification. Do not commit/rebind after each memory sentence or modify fingerprint
exclusions to hide material code changes. At closeout include sanitized relevant current
memory in the canonical audit only using the existing validated packaging approach; add
needed tooling coverage before certification if that builder does not already support it.
