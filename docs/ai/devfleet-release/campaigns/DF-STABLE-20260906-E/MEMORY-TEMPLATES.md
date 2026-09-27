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
minimal change; classification (shipping/tooling/environment/workflow); behavioral test and
actual result; live validation state; applies-to fingerprints; counterexample; rollback.
Prefer a short entry in existing EDGE-CASES once truly solved; do not assert global fixes from
one mock test. Record when environment assumptions differ from the shipping deployment path.

## Resume/stop record

Capture active process ownership and outcome before updating 'next action'. A crash/compaction
is not permission to re-execute the last script. A blocked console request includes exact VM,
question and safe terminal state; never leave unbounded work running while waiting for a reply.
