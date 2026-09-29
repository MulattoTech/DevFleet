# DevFleet source access and certification review

DevFleet v1.2.13 certification is **INCOMPLETE / BLOCKED**. This public repository contains reviewed publishable source, installer payload, release tooling and review documents. It excludes native credentials, VM/checkpoints, private ledgers, signed release artifacts and certification authority. A public clone cannot inherit native qualification.

Original source snapshot: e9068790ae9b0f55baa25b258791cb14c9e7091f. There are 981 indexed native source/tooling/docs files and 131 ordered source-text parts, each under 50,000 UTF-8 bytes. The full-source document is larger than that limit; retrieve by subsystem and report coverage honestly.

Start with [source index](INDEX.md), [file inventory](ORIGINAL-SOURCE-INVENTORY.json), [certification handoff](CERTIFICATION-HANDOFF.md), [latest diagnostic](diagnostics/2026-09-29-image-remote.md), [build guide](../BUILD-FROM-CLONE.md), [DONE](../docs/ai/devfleet-release/DONE.md) and [test plan](../docs/ai/devfleet-release/TEST-PLAN.md).

First verify actual repository access by reading source/VERSION and a concrete function in tools/baseline_lineage.py. State which files were inspected. A URL alone is not proof of access.

Current native qualification, generation-5 baseline binding, VM-free preflight and authenticated readiness passed. R5 Laptop installation BLOCKED before Failover creation with an unavailable image remote. A separately approved catalog diagnostic did not reproduce that failure; its first lookup succeeded before force-update. No new product installation or nested VM launch was attempted. The diagnostic ended with repaired CLEAN restored, nested L2 ABSENT and L1 Off.

Current role proof credit remains 0/2. R3 proofs and 17 older FullRelease phases are historical. R5 Laptop allowance is consumed, and its required sequence blocks Desktop and FullRelease admission. Any replacement runtime requires its own exact native authorization. Do not restart valid qualification or baseline binding for a new conversation.

Return a minimal causal patch and meaningful failing-before/passing-after tests. Distinguish product faults from harness/admission defects and current from historical evidence. Never fabricate approval or PASS, weaken safety/identity/authentication, reset attempts, publish private host evidence or claim public promotion. Reconcile original-host native authority before any certification action.
