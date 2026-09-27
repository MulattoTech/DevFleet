# Corrections and bounded attempts

## Mutable mechanics

Mechanics may be changed only when a causal failure is demonstrated and the correction
improves observation/recovery without making acceptance easier. Examples include bounded
retry counts, timeouts, no-progress budgets, observer race handling, transport recovery,
staging/cleanup implementation, error classification, and phase ordering.

A mechanics change must not widen an effective acceptance window, alter required phase
dependencies, broaden evidence/role equivalence, suppress a terminal state, or turn
UNKNOWN/timeout/NOT_OBSERVED/diagnostic evidence into PASS.

For each correction record: observed boundary, falsifiable cause, changed files, focused
regression, preserved invariant, and why release truth is not weakened. Preserve the failed
RunId. Recompute/invalidate dependent evidence when the change is material.

## Corrective attempts

A continuation request authorizes bounded in-scope engineering work, not unlimited retries.
Reserve another attempt only when the prior run is terminally clean, a changed falsifiable
condition exists, focused checks pass, live authority/candidate/ownership/HOST-SAFETY are
fresh, and the native attempt ledger can atomically record the new attempt.

Each reservation needs a unique RunId, exact tuple, owner, budget, cleanup plan, stop
condition, policy/counter allocation, and tri-state productStarted field. Markdown may
mirror but never authorize it.

Do not reset or erase historical counters. Do not retry an unchanged cause. If the user
grants a finite number of tries, stay inside that envelope. Without an explicit number,
use no more than five attempts for one newly proven causal boundary or the smaller native
policy remainder.

Stop for genuinely external choices/actions, missing credentials, browser approval,
unsafe/unknown host state, protected-resource conflict, ambiguous ownership, invalid
candidate, human-only observation, or a product-requirement/promotion-scope decision.
