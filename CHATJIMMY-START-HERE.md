# DevFleet source access and certification review

DevFleet v1.2.13 certification is **INCOMPLETE**. This public repository provides the current publishable source, installer payload, release tooling, release contracts and review documents. It does not provide the original host's credentials, VM/checkpoints, private ledgers, signed artifacts or proof authority. A GitHub clone cannot inherit native qualification.

Original source snapshot: 78e92440a51717f09f92676cba9c0b2e67d7b06c.

Pinned public source commit: [c8073061dbea](https://github.com/MulattoTech/DevFleet/tree/c8073061dbea9a52ee52d9cda4a1f00d06a82857). The later README/documentation commit does not alter the 976 indexed original-source files. Start with [the source index](INDEX.md), [file inventory](ORIGINAL-SOURCE-INVENTORY.json), [certification handoff](CERTIFICATION-HANDOFF.md), [build guide](../BUILD-FROM-CLONE.md), [release DONE contract](../docs/ai/devfleet-release/DONE.md), and [test plan](../docs/ai/devfleet-release/TEST-PLAN.md). The full text and ordered sub-50,000-byte parts are indexed under ai/source-parts; the binary payload remains in its normal source path.

First verify that your tool can actually open this repository. Read source/VERSION and a concrete function in tools/baseline_lineage.py, then state which files you inspected. A URL alone does not prove access; if access fails, request the necessary part files. The complete multi-megabyte source cannot fit into a single model context, so review by subsystem and report coverage honestly.

The current native boundary is a late nested Primary Multipass/SSH readiness timeout in an older blocked FullRelease, followed by a changed tooling tuple that makes those proofs historical. The installed generation-4 baseline does not bind the new tuple; an isolated generation-5/R2-REPAIR-5 proposal is unintegrated and unapproved. See CERTIFICATION-HANDOFF.md and the README progress matrix. Preserve all failed attempts and signed artifact lineage.

Return a minimal code patch, exact tests/logs/hashes and a causal explanation. Distinguish product defects from harness/admission faults and historical from current proof. Never fabricate approval, credentials, native PASS or release eligibility. Do not push private host evidence, weaken safety/security/ownership, reset ledgers, rebuild signed bytes for a documentation change, or claim public promotion. The original host's current native authority must be reconciled again before any certification action.
