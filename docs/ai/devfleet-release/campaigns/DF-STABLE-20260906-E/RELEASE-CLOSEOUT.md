# Transition from diagnosis to full stable internal release

The installed `docs/ai/devfleet-release/DONE.md` and TEST-PLAN remain the acceptance contract.
Dylan explicitly declined a Desktop-only preview. No feature merge, new preview label or
subset of gates substitutes for the full v1.2.13 internal-release result.

## Leave diagnostic mode deliberately

Require a demonstrably successful required dependency/integration path and an explanation
supported by controlled evidence of the original failure or necessary precondition. Failed
attempts remain preserved. A lucky success after several blind restarts is not qualification.
State remaining uncertainty truthfully; do not promote 'environment issue' into a root cause.

Finish the focused correction and actual behavioral regressions. Verify Desktop/Primary AND
Laptop/Failover+Vault identity/producer-to-consumer paths before freezing material tooling.
Existing WPF tests and satisfied same-input contracts need verification, not automatic reruns.

Classify changes through the native complete shipping inventory/rules, including added or
deleted files. Workflow memory/tooling changes do not automatically require a rebuild. If
shipping inputs are unchanged and artifacts coherent, reuse candidate `bf8ee641...` ONLY
while live authority proves it current. Preserve the original build commit even if HEAD moves.

If shipping changes are required: finish their tests, freeze/commit inputs, then build/sign
one replacement for that frozen set using native scripts. New further shipping changes may
justify another replacement; new sessions, helpers or copied docs do not. Never inject altered
shipping scripts into old signed bytes and claim exact proof. Never hand-set promotion fields.

Before certification remove E's diagnostic checkpoint safely, return to verified canonical
CLEAN, remove/account for every E nested instance, quiesce all helpers/local helper children,
and confirm required host safety. Refresh native material-tooling provenance truthfully.
No product acceptance may rely on a private diagnostic service/cache/config workaround that
cannot be obtained by the supported product/install path from canonical CLEAN.

## Execute remaining real acceptance

Follow the native dependency order and existing entrypoint schemas; inspect parameters once,
do not invent flags. `Finalize-CandidateEvidence.ps1` uses `-Workspace`, not `-WorkspaceRoot`;
do not rerun it reflexively after memory writes and clear useful proof state.

Require two independent current exact proofs with canonical CLEAN, new RunIds and correct
Desktop and Laptop/Failover/Vault coverage. OBSERVER_HANDOFF, ContractProbe, a plain Ubuntu
VM, a manual console screenshot or a mocked test is not an installation proof.

Complete the existing U01–U05 actual-use/recovery coverage or prove equivalent CURRENT runtime
coverage: disposable project create/use, stop/restart, backup, quarantine/restore, and supported
Vault recovery. Include genuine standard-token evidence; an elevated coordinator is not that
context. Do not substitute empty fixtures or simulated successful health for real operation.

Complete maintenance/sentinels, Repair, Clean Reinstall, Uninstall, Factory Reset, Reboot/Resume
5/5, one coherent current FullRelease, all Host Agent/WPF/Linux/Windows/ownership/Vault/surrogate/
Tailscale gates, RECONCILE and durable CLEANUP. Do not run FullRelease twice merely to create
more reports, or splice failures together. Material source/tooling changes invalidate affected
lineage and require truthful requalification; never edit old proof-start hashes to match today.

Only declare `PASS — INTERNAL RELEASE ELIGIBLE` when native current authority and evidence
show candidate coherent/current, source unchanged, rebuildRequired=false, proofs 2/2,
maintenance/sentinels and 5/5, FullRelease and every installed DONE gate PASS, RECONCILE PASS,
CLEANUP PASS, L1 OFF/L2 ABSENT, current RELEASE-mode audit validation, and:
`validationEvidenceCurrent=true`, `fullReleasePassed=true`, `internalPromotionAllowed=true`,
`publicPromotionAllowed=false`, `publicPublisherTrust=false`, F-005 NO.

Capture the known-good baseline and FEATURE-HANDOFF only after all that. Astra feature work
remains separate; no public trust, GitHub push or production deployment is implied by PASS.

## Actual closeout, whether passed or blocked

Retain native experiment/proof/failure records and exact source. Preserve sanitized evidence
before destructive cleanup. Positively verify L1 OFF and all owned nested L2 instances ABSENT
via complete applicable backend inventories; no unknown instance silently disappears from scope.
Check the diagnostic checkpoint lifecycle and no campaign processes/helpers remain.

Update native handoff and small memory. Generate ONE fresh canonical
`outputs/DevFleet-v1.2.13-AI-Audit-LATEST.zip` at final release, genuine blocked escalation, or
user-requested audit—not every informative experiment. Validate clean extraction in truthful
RELEASE or DIAGNOSTIC mode, including source/evidence hashes, redaction/secret scan, provenance
and bundle/current-state match. Write the SHA-256 sidecar LAST after final ZIP bytes.

Print exact ZIP path/bytes/hash/sidecar, current tuple, proven cause vs unknowns, meaningful
experiments, actual gate outcomes/RunIds, consumed E allowance, verified final lab/checkpoint
state and truthful verdict. If packaging/cleanup fails, report it as an additional concrete
blocker; never silently refer to an older LATEST archive. A good diagnostic closeout is not
completion of the release goal.
