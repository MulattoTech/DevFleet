# Multipass-first diagnostic matrix

These are isolated dependency/integration experiments, NEVER release proof. Diagnose the
last observed launch/daemon-readiness gap without redoing the solved WPF investigation.
Use existing safe harness primitives and actual command contracts; implement only missing
collector/test glue. Do not spend a long run merely to find which command is active.

## Prepare once; preserve canonical CLEAN

Reconcile sole ownership, exact L1/CLEAN GUIDs, candidate and live runtime before mutation.
Record actual L1 resources/free space and applicable dependency versions/backend, service
account/context, nested-virtualization exposure and network prerequisites via safe reads.
Compare candidate Primary/Failover/Vault demands with capacity INSIDE L1 and physical-host
headroom. Do not infer capacity from physical RAM alone, change host allocations, or assume
that a large dynamic disk reserves all its nominal size immediately.

Restore verified canonical CLEAN. Reach an ordinary prerequisite-ready state through existing
supported scoped installation/diagnostic primitives, with no active product transaction and
no run-created L2 instances. Do not erase checkpoints/receipts to simulate that condition.
Use the same applicable dependency version/backend as the candidate; do not silently upgrade
or switch a backend. Stop on required protected/security changes.

Create ONE separately named diagnostic checkpoint of exact L1 after safe quiescence. Record
actual new GUID, parent/source CLEAN GUID, VM ID, UTC, prerequisite/package versions,
configuration identity, and proof of empty owned L2 inventory. Prefer a shut-down, disk-
consistent diagnostic baseline when supported. Never rename, delete, recreate or overwrite
canonical CLEAN. If a reusable prerequisite state cannot be reached without fabricating
product state, record it and use the shortest honest supported diagnostic path instead.

A diagnostic checkpoint may contain local credentials/configuration: never export it, VM
disks, memory, DPAPI or secrets into an audit or helper packet. Before each restore capture
needed non-secret evidence; restore only when all experiment-owned processes are terminal
and owned nested resources have been accounted for. Checkpoint reuse must not retain the
running daemon's stale requests or a half-created VM and pretend it is an independent trial.

Delete only E's exact temporary checkpoint after diagnostics and before certification, using
supported removal/merge with bounded verification. Never manually delete AVHDX/VHDX files or
checkpoint chains. At an administrative pause, the prerequisite-only checkpoint may remain
local if logged and L2-free; final release/blocked closeout removes it when safe. A failed
merge/cleanup is reported, not concealed by claiming absence. Clean proofs use canonical CLEAN.

## Collector acceptance before launch

Use a tested bounded collector whose own failure cannot suppress the primary product error.
Record only allowlisted non-secret context and exact operation boundaries; never whole raw
command lines, secret-file contents/hashes, environment dumps or credentials.

Minimum observation set: run/experiment and context IDs; image/release identifier (and digest
where available); backend/version; requested resources; task/PID+creation/path lineage;
operation start/end/deadline/native exit; Multipass service events; applicable Hyper-V or
VirtualBox backend events/VM IDs; guest boot/IP/SSH/cloud-init state when accessible; last
valid product marker plus reader status; dropped/truncated/timeout flags. Discover actual
log/provider availability. An absent provider is unavailable evidence, not a clean log.

Capture independent service/backend evidence even if Multipass CLI inventory times out. Keep
one serialized bounded CLI probe stream, no flood of overlapping `list/info` queries. A
backend-created VM, a boot screen, an address, working SSH, completed cloud-init and completed
DevFleet are DISTINCT milestones. Diagnostic breadcrumbs do not fabricate semantic product
progress or move the shipping observer's absolute deadline.

Test collector success, unavailable source, nonzero exit, timeout, malformed data, wrong VM,
wrong run, partial output, redaction and primary-error preservation with local fixtures first.
Maintain existing WPF/role/marker/ownership/deadline contracts. No source-string-only PASS.

## Ordered comparisons — branch on evidence rather than run every cell

| ID | Controlled question and setup | Required distinguishing evidence |
|---|---|---|
| M0 | Current dependency/backend and capacity survey; no new launch | Actual inside-L1 CPU/memory/disk, dependency identities/service state, readiness and observation plan; no mutation on unsafe conditions |
| M1 | Plain Multipass launch of the candidate's applicable Ubuntu image, without DevFleet or release observer; use safe modest resources recorded as diagnostic deviations | Did image acquisition, backend create, boot, IP, SSH and cloud-init complete? Native results, backend/service events and cleanup identity |
| M2 | Same image/backend/account baseline; use exact product CPU/memory/disk profile, without DevFleet-specific cloud-init | Is the difference resource/profile related? All non-target differences, including warm/cold image cache, disclosed |
| M3 | Exact relevant candidate launch inputs/cloud-init in the ordinary equivalent context, without release observer | Which additional input triggers failure? Real current candidate content/identity; approved test credentials handled locally; no fake install-state files |
| M4 | Production invocation and observation enabled, from equivalent diagnostic baseline | Does account/environment, production call path or observer interaction change the result? Real argument builder and consumers; no production identity mocked away |
| M5 | Evidence-supported minimal correction and repeat of the implicated comparison | Causal discriminating evidence, focused behavioral/environment regression, exact change and stable required launch path |

M1's smaller profile is for diagnosis ONLY. It cannot certify the larger shipping config.
Where two steps are identical, combine them and record equivalent coverage. When M1 fails,
stop the later product cells and investigate that dependency first. When M1 passes and M2
fails, diagnose capacity/backend rejection. When M2 passes and M3 fails, isolate launch inputs
or guest initialization. When M3 passes and M4 fails, isolate invocation/observer interference.
Do not infer root cause from this table without actual controlled evidence.

Change ONE causal factor per contrast where possible. Immutable identity/run names naturally
change; record them. Same image digest and cache condition matter: cold versus warm startup
is not a clean proof of a code correction. Cache warming may be a useful controlled experiment,
not a hidden precondition smuggled into certification. Diagnostic names are never accepted as
product markers; exact product role/transaction/payload identity remains required in proofs.

No plain diagnostic cloud-init may accidentally contact protected projects, real external
secrets, or activate production integrations. Use disposable test values only where supported
and label deviations. A launch-only M3 does not pass bootstrap/services/ownership/health.

## Failure and screenshot fallback

Before reset/restart/cleanup, collect the smallest sufficient non-secret failure evidence.
Multipass launch timeout may mean download, backend creation, boot, IP, SSH, daemon contention,
or initialization trouble; root must locate the actual boundary. Do not choose one by CPU.

Use existing safe console/serial capture if available and bound to exact nested VM identity.
Otherwise ask Dylan once for the specific console within exact disposable L1, including the
experiment/VM name and what must be visible. Do not ask for host desktop/credential screens.
This is the already approved targeted observation, not a manual installation that earns PASS.
Provide a bounded opportunity for it during an active diagnostic; never wait indefinitely with
VMs running. On unavailable input, preserve evidence, terminalize safely and record the exact
observation needed. Console images are non-authoritative context alongside actual run records.

After a correction, document whether it is shipping, tooling, or an environment precondition.
A necessary environment setup must be reproducible through supported paths from canonical
CLEAN; a successful repaired diagnostic snapshot alone is insufficient. No protected host
configuration fix is implicitly authorized. Follow RELEASE-CLOSEOUT before certification.
