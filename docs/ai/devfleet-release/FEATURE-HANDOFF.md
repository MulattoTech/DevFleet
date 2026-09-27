# Stable baseline and Astra feature track

This file defines separation; it does not authorize adding a particular feature now or
switching the active release root. Verify available model identifiers/capabilities when used.

Before release: Astra can work on a separately requested specification/prototype in another
feature worktree. It must not write the release worktree, artifacts, canonical evidence,
shared runtime configuration, credentials or certification lab. Do not run concurrent heavy
feature tests while the disposable release environment is using the host budget.

After DONE/D2: Sol records the stable baseline below in a new evidence-backed handoff, preserves
the signed candidate and known-good source/tooling reference with the native Git workflow,
and leaves release artifacts untouched. Avoid moving tags, hard resets and pushes.

## Handoff fields to populate only from proven release evidence

- Release eligibility verdict and evidence time.
- Stable source/tooling HEAD and original candidate build commit (not necessarily equal).
- Shipping/release/tooling identities; signed EXE/TAR/portable/installer-source paths and hashes.
- Two proof RunIds, role coverage, maintenance 5/5, FullRelease, real-use U01–U05 evidence.
- RECONCILE/CLEANUP and final L1/L2 state; RELEASE-mode audit ZIP/sidecar.
- Supported private/internal deployment scope and self-signed trust limitations.
- Known nonblocking limitations with source; no unresolved release blocker hidden as a feature.
- Exact read-only baseline/reference and separately chosen feature branch/worktree path.
- Recovery/rollback instructions and baseline regression commands.

No fields above are currently pre-populated with a release PASS.

## One-feature acceptance contract

Astra starts from the verified baseline and a single approved feature request. Define visible
user behavior, non-goals, affected modules, data/config compatibility, failure behavior,
security/ownership implications, tests and rollback before editing. Implement the smallest
useful slice; keep unrelated installer, provisioning, reboot, Vault and ownership changes out
unless that feature explicitly requires them. Do not rewrite the application to add one screen.

Run existing impacted regressions and new feature acceptance. Before integration, compare
shipping and tooling deltas and repeat the appropriate release qualification for the new
version. Never carry v1.2.13's passing certification forward onto changed feature bytes.
The stable baseline remains available even when the next version fails. Do not turn all future
feature development into another unlimited audit campaign.

## Release acceleration handoff

The bounded future-release sequence and validation matrix are maintained in
`audit/agent-memory/RELEASE-ACCELERATION.md`, `COMPONENT-MAP.md`, and
`VALIDATION-MATRIX.md`. They are navigation only: Vault-broker restore,
recovery-only identity/read boundaries, same-install REAL-USE U01-U05,
standard-token immutable evidence, and immutable final RELEASE audit/acceptance
remain required and currently unverified. Do not populate the release fields
above from these planning documents.
