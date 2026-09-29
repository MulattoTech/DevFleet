# DevFleet source part 055

Full-source UTF-8 byte interval [2511000, 2557500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 781ed9caad239525f9c531d3b8cad5bac63bb2f6ef91928c5767fac931eb1cf8

<!-- BEGIN SOURCE SLICE -->
ng/environment/workflow); behavioral test and
actual result; live validation state; applies-to fingerprints; counterexample; rollback.
Prefer a short entry in existing EDGE-CASES once truly solved; do not assert global fixes from
one mock test. Record when environment assumptions differ from the shipping deployment path.

## Resume/stop record

Capture active process ownership and outcome before updating 'next action'. A crash/compaction
is not permission to re-execute the last script. A blocked console request includes exact VM,
question and safe terminal state; never leave unbounded work running while waiting for a reply.

````


## FILE: docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/ORCHESTRATION.md

SHA256: 5b12cdf940bc643cc751dfa60f606b7742569dc16b803bcc51b794efcc6221a7 | Bytes: 6153 | Git mode: 100644

```
# Sol coordinator, elastic Luna helpers, single lab owner

## Execution policy

Sol XHigh stays coordinator; changing root models is not part of this amendment. Default
helper is `gpt-5.6-luna` at `high`; choose `medium` for bounded indexing/comparisons and
`xhigh` for difficult causal/invariant questions. Use only efforts the catalog supports.
No blanket XHigh for every grep. Terra/Spark remain optional only for a genuinely better
small task and a backend-verified native route; do not spend a wave fixing model routing.

The launcher requests TWELVE concurrent helpers (thirteen threads including root in V2).
This is a concurrency envelope, NOT a lifetime helper count or quota to fill. Start with
up to four useful independent lanes; expand only when the task graph and resources justify
it. Close finished workers and reuse their slots; keep creation history, status and actual
model/effort. Respect any lower actual backend, account, rate or host-resource limit.

Depth is normally root → specialist → focused worker. Deeper delegation is authorized when
Sol assigns a concrete independent subproblem and a bounded slot reservation; arbitrary
extra layers that just relay messages are waste. All descendants share ONE global pool.
`agents.max_depth` does not enforce depth in V2. Native limits and actual tools win.
No separate Codex CLI/app-server fleet, external Ralph plugin, or custom orchestration daemon.

## Scheduling and slot ownership

Sol maintains TEAM.md (and a small JSON projection when native operations need it) with
slot, agent ID/path, parent, depth, task ID, source/evidence fingerprint, requested/effective
model/effort, state and reserved descendant slots. Reserve before spawning; count pending
spawns and waiting supervisor threads. Reclaim only after known termination/closure; an
unknown agent is not a free slot. Failed routing is recorded once and falls back to verified
Luna or root execution, not a retry storm or silent model substitution.

A parent can allocate only the unused descendant slots leased to it. It cannot create its
own pool or pass along copies of the same reservation. Every packet includes the global
policy, exact remaining reservation and expiry/stop condition. Grandchildren/deeper workers
must inherit the same lab and authority prohibitions. Sol may flatten the tree when this
is faster. Native metadata, not a worker's self-description, establishes its routing.

## Initial independent lanes — adapt to current evidence, do not force all four

| Lane | Suggested effort | Deliverable |
|---|---|---|
| Dependency/environment analysis | Luna high | Interpret frozen service/backend/capacity evidence; rank discriminating experiments, not speculative host changes |
| Production call-path analysis | Luna xhigh when needed | Trace exact candidate launch inputs, identity, image, cloud-init, account context and observation interaction |
| Behavioral regression/collector work | Luna high | A bounded failing production-path test or isolated collector prototype in assigned scratch, with before/after expected outcomes |
| Evidence/cleanup adversarial review | Luna high or medium | Falsify causal claims; check safe checkpoint/resource identity, collector redaction, missing data and eventual gate coverage |

Sol handles live observations, integration and decisions. A specialist must return the useful
answer promptly, not a new general architecture or another broad project audit. Do not send
identical questions to many agents and vote. Use at most one fresh independent review of the
integrated correction unless new evidence changes it.

## Real parallelism without shared-state corruption

Helpers read root-pinned immutable snapshots of only relevant current files/evidence. Include
exact source commit/file hashes; never accidentally inspect `audit-extract` as current source.
Normal context is a concise self-contained packet (`fork_turns="none" where supported), not
the entire large root thread. Give tests the actual production path, not a helper that bypasses it.

Helpers may write only their assigned `outputs/agent-scratch/DF-STABLE-20260906-E/<TaskId>/`
(or another root-verified nonshipping ignored scratch path). No canonical source, .git,
shared memory, candidate, signature, native release evidence or shared test cache writes.
Use isolated fixtures/temp paths and existing runtimes; no global packages. Proposed patches
are reviewed/applied by Sol. Root tests the integration before material source freeze.

Only Sol starts, stops, snapshots, restores, queries or otherwise operates live lab interfaces.
Helpers request observations from Sol; they do not each run `multipass list`, remoting calls,
Hyper-V queries or watchdogs. This avoids accidental observer contention with the daemon.

During a focused diagnostic, up to TWO lightweight helpers may analyze already captured
immutable artifacts while the local harness waits, provided fresh resource checks permit it.
No local test suites/builds/scans or writes to frozen material inputs during a live run.
Throttle to zero on pressure or when no independent useful work exists. This limited overlap
supersedes the previous blanket pre-runtime helper ban for DIAGNOSTICS ONLY.

Before exact proofs, maintenance runtime or FullRelease: all helpers and their local child
processes must be completed/quiescent. Freeze material source/tooling. Serializing the single
lab is deliberate; parallelizing analysis does not make two competing VM owners safe.

## Worker packet/result contract

Packet: TaskId; exact question; relevance to current blocker; input paths/hashes; known solved
issues; allowed scratch path; expected deliverable; tests allowed; budget/stop; parent/depth;
reserved child slots; authority/safety restrictions; no secret or live-resource access.

Result: finding/no-finding; exact references; proven vs inferred vs unknown; smallest fix;
falsification/regression; actual tests/exit/output completeness; changes only in assigned
scratch; descendants closed. Root records acceptance/rejection and rationale. On cancellation,
workers return useful partial evidence instead of continuing silently.

```


## FILE: docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/RELEASE-CLOSEOUT.md

SHA256: 2080eef88b882d8f060d511315fd9c612702ce944289afc4ec5088a13d3115d0 | Bytes: 5587 | Git mode: 100644

```
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

```


## FILE: docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/SOURCES.md

SHA256: 61338ce0fdcbe93f7c752ec984897e2c1bd280f76f87a010037dab2dfc14a871 | Bytes: 2866 | Git mode: 100644

```
# Basis and verification limits

## User-supplied project basis

- Latest uploaded `NEXT-CODEX-HANDOFF.md`: authority
  `fb99f29ce7a5cbc47d501007299e34be9ee43ca74a661f37f3e2e0858d6cdf5f`;
  D HEAD `1678a254...`, candidate `bf8ee641...`, unresolved Multipass boundary.
- `AFTER-ACTION-REPORT.md`, D closeout 2026-09-06T16:50Z: WPF handoffs, five accepted
  markers, 164 samples and NO_PROGRESS_TIMEOUT; zero proof credit; exact cleanup.
- Latest uploaded `DevFleet-v1.2.13-AI-Audit-LATEST.zip`: current machine-readable authority
  and the installed release-control workflow/DONE, skill and agent-memory documents.
- Stable operating rules and known edge cases: unchanged safety/release discipline except
  for the explicit procedural amendments authorized by Dylan's latest answers.
- User decisions: checkpoint yes; consolidated bounded cycle yes; preview no; targeted
  console check yes; expanded useful Luna delegation/nesting and a goal-style loop yes.

The E diagnostic matrix, concurrency default, experiment envelope and added memory layout
are newly designed workflow recommendations adopted by the supplied prompt, not observations
of current runtime success. No new live VM observation or candidate verification is claimed.

## Current primary documentation checked September 6, 2026

- OpenAI, Using Goals in Codex:
  https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex
- OpenAI, Follow a goal:
  https://developers.openai.com/codex/use-cases/follow-goals/
- OpenAI, Codex CLI reference (resume / config / YOLO):
  https://developers.openai.com/codex/cli/reference
- OpenAI, Subagents and custom instructions:
  https://developers.openai.com/codex/subagents
  https://developers.openai.com/codex/agent-configuration/agents-md
- OpenAI version-pinned v0.153.4 config schema and implementation:
  https://raw.githubusercontent.com/openai/codex/rust-v0.153.4/codex-rs/core/config.schema.json
  https://raw.githubusercontent.com/openai/codex/rust-v0.153.4/codex-rs/core/src/config/mod.rs
- Canonical, Multipass launch/start troubleshooting and logs:
  https://documentation.ubuntu.com/multipass/en/latest/how-to-guides/troubleshoot/troubleshoot-launch-start-issues/
  https://documentation.ubuntu.com/multipass/en/latest/how-to-guides/troubleshoot/access-logs/
- Geoffrey Huntley, original Ralph approach (inspiration, not an installed dependency):
  https://ghuntley.com/ralph/

Native goals are persisted thread objectives with continuation/stop/budget semantics, not a
universal unattended daemon. V2 depth is not controlled by agents.max_depth. Requested model,
concurrency and permissions must be verified against the user's actual running CLI/backend.
The launcher does not install/upgrade Codex, alter authentication or force unsupported routes.
No promise is made that a larger agent pool makes this particular VM boot faster.

```


## FILE: docs/ai/devfleet-release/campaigns/DF-STABLE-20260906-E/START.md

SHA256: 88abbcc0138819559b3c2712719ae737b0ed7317e781292d9d5e2ce68b80afd3 | Bytes: 3544 | Git mode: 100644

```
# DF-STABLE-20260906-E — start here

This is an amendment to the INSTALLED DevFleet release workflow, not a replacement
codebase, release waiver, new harness project, or current-state authority file.
Activate it only through Dylan's explicit adoption/goal instruction. It records his
September 6 answers: diagnostic checkpoint YES; consolidated bounded diagnosis and
repair YES; Desktop-only preview NO; targeted disposable-VM console observation YES.
His new delegation authorization supersedes the old six-created-helper ceiling.

## Entry sequence

1. Read `AUTHORIZATION.md`, `ORCHESTRATION.md`, and `LOOP.md` in this directory.
   Read the installed `docs/ai/devfleet-release/SAFETY-AND-AUTHORITY.md` and `DONE.md`.
   E overrides only the older procedural restrictions explicitly listed in AUTHORIZATION.
   Platform restrictions and all unchanged safety/release conditions remain binding.
2. Reconcile sole coordinator/lab ownership and live Git, candidate and current proof
   authority. Read the current native handoff and small memory CURRENT/ATTEMPTS/HELPERS.
   Do not reload every historical transcript or treat this offline packet as live evidence.
3. Create or resume E's state under `audit/agent-memory/campaigns/DF-STABLE-20260906-E/`
   using `MEMORY-TEMPLATES.md`. Preserve any existing E state and every historical A–D run.
   Add navigation links to existing memory; do not replace it with these templates.
4. Verify actual root, helper model routing, native concurrency and goal support once.
   The launcher's requested settings are not proof of the effective runtime settings.
5. Give useful independent questions to Luna helpers. Sol performs root integration and
   is the ONLY live lab operator. Follow DIAGNOSTICS before another complete proof.
6. Continue the evidence-driven loop to the full installed DONE contract, or stop safely
   for one of LOOP's concrete escalation conditions. Do not stop at writing these files.

## Offline orientation — verify live; do not rebind to these values

| Field | Uploaded D closeout |
|---|---|
| Repository/tooling HEAD | `1678a2547efa5ab2192d46a51d7e793171e4970f` |
| Candidate build commit | `bf8ee64179dfa2dd36b2772fdbd1608c4408415e` |
| Shipping identity | `a26130c7b023106b1e78f068d4610fea443196624a342bd8a6ec352b0f65ae9f` |
| Release fingerprint | `908daa6058dbbca3edc69fde1d0ca953ceb439040585335178088e96814b5635` |
| Tooling fingerprint | `b921fd9a3b1af567e14a4b0c630f4583f67a3713b6309c03b074f9c903629351` |
| Last failed proof | `e2e-exact-candidate-proof-stable-20260906-p1-supplement-d1` |
| Proof credit | 0/2; FullRelease not run for current candidate |
| Shipping/build | Recorded unchanged; rebuildRequired=false |

Both signed WPF legs returned OBSERVER_HANDOFF. The Desktop observer accepted five
markers with zero role/identity errors, ending at
`stage-compute-devfleet-primary-instance-absent.complete`. Subsequent inventory was
INVENTORY_TIMEOUT; 164 samples ended at the unchanged 1,800-second semantic deadline.
No complete product installation was established. Multipass launch/daemon readiness is
the unresolved boundary, not a proven root cause. Recorded cleanup was L1 OFF/L2 ABSENT.

Keep solved launch-mode, interactive-login, role identity, checkpoint acknowledgement,
stdin/dependency deadline and post-exit drain corrections unless new evidence contradicts
them. The configuration and chronology needed to reproduce the last boundary matter more
than rereading the original WPF investigation. Sources and verification limits: SOURCES.md.

```


## FILE: docs/ai/devfleet-release/templates/ATTEMPT.md

SHA256: 49cd4f7aab1fe95fa5444b5a191a80856e815519b5f3dfa2a0b8ded5386e5093 | Bytes: 1193 | Git mode: 100644

```
# <RunId> — attempt reservation and result

Policy: DF-STABLE-20260905-A
Class: READINESS | PRODUCT_FIRST_EXECUTION | CORRECTIVE_REPLAY | SOURCE_ONLY
Status: RESERVED | RUNNING | PASS | FAIL | BLOCKED | CANCELLED | UNKNOWN
Reserved UTC: <time>
Slot: <readiness 1..3, required phase identity, or shared replay 1..2>
Historical predecessor: <old/new attempt path; do not rewrite it>

## Question and prerequisites
Hypothesis / specific missing observation:
Changed inputs and focused regression justifying a retry:
HEAD / candidate / shipping / release / tooling:
Entrypoint, actual parameters, runtime and script SHA-256:
HOST-SAFETY record/hash and exact L1/CLEAN/owned L2 fence:
Owner process identity and cleanup owner:
Operation/child/parent deadlines and terminalization margin:
Expected semantic observations and stop rule:

## Actual result
Started/completed UTC:
Product started: true | false | unknown (with evidence)
Last durable boundary and run/launch/transaction/payload identities:
Exit code, status and primary error:
Evidence paths/SHA-256:
L1 / L2 / owned workers/helpers (state, method, time, continuity):
Effect on counters and dependent proof validity:
Next exact action:

```


## FILE: docs/ai/devfleet-release/templates/INCIDENT.md

SHA256: 8b1dfaa39db730d4a56b7a30794cd340a28ef9ae979f654cee061ee0c64b6fa2 | Bytes: 536 | Git mode: 100644

```
# <stable incident ID and short title>

Status: HYPOTHESIS | PROVEN_SOURCE_DEFECT | FIX_IMPLEMENTED | LOCAL_TESTED | LIVE_VALIDATED | RELEASE_CERTIFIED | FALSIFIED | HISTORICAL | SUPERSEDED
Observed UTC:
Scope / relevant source-tooling tuple:
Symptom and distinguishing boundary:
Evidence paths/hashes or exact symbols:
Proven cause (or explicitly unproven hypothesis):
Correction and commit:
Regression and actual result:
Live validation / missing observation:
Do not repeat:
Reopen only when:
Supersedes / superseded by:
Next action:

```


## FILE: docs/ai/devfleet-release/templates/SESSION.md

SHA256: 12178ac191d569e826eb87f35355834e2476b8e1c22b49dce09d99f5fcbe4009 | Bytes: 501 | Git mode: 100644

```
# Session boundary — <UTC/session ID>

Boundary: PAUSE | BLOCKER | RELEASE
Live HEAD / candidate / shipping / release / tooling:
Milestone and exact blocker:
Changed files by classification:
Tests/runs completed with evidence:
Readiness/replay reservations and consumption; historical ledger pointer:
Helper slots used/reserved/active and native ledger:
Owned process / L1 / L2 terminal evidence:
Uncommitted work preserved:
Audit path/hash/mode when required:
Single next action and prerequisites:

```


## FILE: installer-source/Assets/README.md

SHA256: 2078e9a68c7d64bc6d228479cc67bca8d96c453ba18029732515d034784f2821 | Bytes: 248 | Git mode: 100644

```
# Branding Assets

This build does not include a third-party or fabricated trust/logo asset. The WPF shell uses its product text and conservative native controls. A legitimate M-TechLabs icon can be added later without changing installer behavior.

```


## FILE: installer-source/BUILD-INSTRUCTIONS.md

SHA256: 2e12dc6c44bcaf136d8d67b812bd9610b4142073f4de32a71d0d2dad8f8a4e15 | Bytes: 1024 | Git mode: 100644

```
# DevFleet v1.2.13 Installer Build

The installer is a .NET 8 WPF, self-contained `win-x64` application with `PublishSingleFile=true`. The build intentionally has no NuGet application dependencies. A clean build machine needs the .NET 8 SDK and the Windows Desktop targeting pack.

1. Prepare and prove idempotence with `Prepare-ReleaseInputs.ps1 -Mode Prepare -ProveIdempotent` before committing the shipping inputs.
2. After the candidate commit is frozen, use `Build-Release.ps1 -VerifyFrozenInputs`; it verifies the commit-sourced generated bytes before restore/build/sign.
3. Restore with an explicitly approved NuGet source: `dotnet restore DevFleet.Setup/DevFleet.Setup.csproj --source https://api.nuget.org/v3/index.json --runtime win-x64`.
4. Run `DevFleet.Setup.Tests` for the destructive-safety plan tests and the published EXE with `--self-test` using test-only state/install roots.

The final binary is architecture-specific and unsigned in this build. No fake trust root or self-signed certificate is created.

```


## FILE: installer-source/BUILDING.md

SHA256: 94ee82f0cfc9a58725f0669ff8dcb4354945ba094ac92deef902b0649c2595bb | Bytes: 824 | Git mode: 100644

````
# Building DevFleet Setup

Use a workspace-local .NET 8 SDK. The target PC does not need .NET because the published WPF installer is self-contained, single-file, and `win-x64`.

Full release:

```powershell
 .\Prepare-ReleaseInputs.ps1 -Mode Prepare -SourceRoot <source> -PreviousPortableZip <previous-portable.zip> -OutputDirectory <outputs> -SigningProfile PrivateSelfSigned -ProveIdempotent
 # Commit the prepared shipping inputs, then build only from the frozen commit.
 .\Build-Release.ps1 -SourceRoot <source> -PreviousPortableZip <previous-portable.zip> -OutputDirectory <outputs> -DotNet <dotnet.exe> -SigningProfile PrivateSelfSigned -VerifyFrozenInputs
```

Installer-only iteration after the embedded TAR is current:

```powershell
.\Fast-Rebuild-Installer.ps1 -OutputDirectory <outputs> -DotNet <dotnet.exe>
```

````


## FILE: installer-source/Build-Release.ps1

SHA256: 591d8b8a2684ab5f772d27c15db2637b0f19e702fbe73331d03d4444a4bb7647 | Bytes: 32505 | Git mode: 100644

```
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourceRoot,
  [Parameter(Mandatory)][string]$PreviousPortableZip,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [string]$DotNet = 'dotnet',
  [switch]$UnsignedDeveloperBuild,
  [switch]$VerifyFrozenInputs,
  [switch]$PrepareReleaseInputs,
  [string]$SignToolPath,
  [string]$SigningDlibPath,
  [string]$SigningMetadataPath,
  [string]$CertificateThumbprint,
  [string]$OsvScannerPath = '',
  [ValidateSet('PublicTrusted','PrivateSelfSigned')][string]$SigningProfile = 'PublicTrusted',
  [string]$TimestampUrl = 'http://timestamp.acs.microsoft.com'
)
$ErrorActionPreference='Stop'
if($UnsignedDeveloperBuild -and $PSBoundParameters.ContainsKey('SigningProfile')){throw 'UnsignedDeveloperBuild cannot be combined with an explicit signing profile.'}
$installerRoot=$PSScriptRoot
$releasePowerShell = @((Join-Path $PSHOME 'powershell.exe'),(Join-Path $PSHOME 'pwsh.exe')) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $releasePowerShell) { throw "Trusted build PowerShell executable was not found under $PSHOME" }
if($PrepareReleaseInputs){
  & $releasePowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installerRoot 'Prepare-ReleaseInputs.ps1') -Mode Prepare -SourceRoot $SourceRoot -PreviousPortableZip $PreviousPortableZip -OutputDirectory $OutputDirectory -SigningProfile $SigningProfile -ProveIdempotent
  if($LASTEXITCODE){throw 'Release-input preparation failed.'}
  exit 0
}
if(-not $VerifyFrozenInputs){throw 'Build-Release requires -VerifyFrozenInputs; tracked release inputs must be prepared and committed before build/sign.'}
$privateIdentityPreflight=$null
if(-not $UnsignedDeveloperBuild -and $SigningProfile -eq 'PrivateSelfSigned'){
  if($CertificateThumbprint -cne 'DE42CD7369A01E9357BDA13597C0173E5E703E9D'){throw 'RELEASE BLOCKED — the authorized existing DevFleet signing thumbprint must be supplied exactly.'}
  Import-Module (Join-Path $installerRoot 'PrivateSelfSignedSigning.psm1') -Force
  $privateIdentityPreflight=Initialize-DevFleetPrivateSigningIdentity -TrustSigningHost -RequiredThumbprint $CertificateThumbprint -RequireExisting
}
$source=(Resolve-Path -LiteralPath $SourceRoot).Path
$previous=(Resolve-Path -LiteralPath $PreviousPortableZip).Path
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$outputs=(Resolve-Path -LiteralPath $OutputDirectory).Path
$workspaceRoot=Split-Path -Parent $source
$priorStatePath=Join-Path $workspaceRoot 'finalization-state.json'
$authorizedCorrection=[ordered]@{shipping_paths=@()}
if(Test-Path -LiteralPath $priorStatePath -PathType Leaf){
  try{$priorState=Get-Content -LiteralPath $priorStatePath -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'RELEASE BLOCKED — prior finalization authority is unreadable.'}
  [string[]]$authorizedPaths=@($priorState.authorized_correction.shipping_paths|ForEach-Object{([string]$_).Trim().Replace('\','/').TrimStart('/')}|Where-Object{$_}|Sort-Object -Unique)
  # Machine-readable path inventories use ordinal ordering, not the host's
  # culture-sensitive collation (which places CHECKSUMS after lowercase app).
  [Array]::Sort($authorizedPaths,[StringComparer]::Ordinal)
  foreach($authorizedPath in $authorizedPaths){
    if($authorizedPath -notmatch '^(source|installer-source)/' -or $authorizedPath -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($authorizedPath)){throw "RELEASE BLOCKED — authorized correction path is invalid: $authorizedPath"}
  }
  $authorizedCorrection.shipping_paths=@($authorizedPaths)
}
$releasePythonCandidate=Join-Path $workspaceRoot 'source\.venv-test\Scripts\python.exe'
$releasePython=if(Test-Path -LiteralPath $releasePythonCandidate -PathType Leaf){$releasePythonCandidate}else{(Get-Command python.exe -ErrorAction Stop).Source}
$releaseToolingRequirements=Join-Path $workspaceRoot 'tools\release-tooling-requirements.txt'
if(-not (Test-Path -LiteralPath $releaseToolingRequirements -PathType Leaf)){throw 'RELEASE BLOCKED — pinned release-tooling requirements are missing.'}
& $releasePython -c "import packaging, cvss; assert packaging.__version__ == '26.3'; assert cvss.__version__ == '3.6'"
if($LASTEXITCODE){throw 'RELEASE BLOCKED — the pinned packaging/cvss release-tool dependencies are unavailable.'}
$shippingIdentityTool=Join-Path $workspaceRoot 'tools\compute_shipping_input_identity.py'
$candidateGitCommit=(& git -C $workspaceRoot rev-parse HEAD 2>$null).Trim()
$verificationMarker = & $releasePowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installerRoot 'Prepare-ReleaseInputs.ps1') -Mode Verify -SourceRoot $source -PreviousPortableZip $previous -OutputDirectory $outputs -SigningProfile $SigningProfile -CandidateCommit $candidateGitCommit | Select-Object -Last 1
if($LASTEXITCODE){throw 'RELEASE BLOCKED — prepared shipping inputs do not reproduce exactly from the candidate commit.'}
$verification = $verificationMarker | ConvertFrom-Json
if($verification.status -ne 'PASS'){throw 'RELEASE BLOCKED — frozen release-input verification did not PASS.'}
$buildSource=[string]$verification.sourceRoot
$buildInstaller=[string]$verification.installerRoot
$candidateIdentityJson = & $releasePython $shippingIdentityTool --workspace $workspaceRoot --candidate-commit $candidateGitCommit | Select-Object -Last 1
if($LASTEXITCODE){throw 'RELEASE BLOCKED — candidate shipping identity could not be computed.'}
$candidateIdentity = $candidateIdentityJson | ConvertFrom-Json
function Normalize-CrlfOnly([byte[]]$Bytes) {
  $out = New-Object System.Collections.Generic.List[byte]
  for($i=0; $i -lt $Bytes.Length; $i++) {
    if($Bytes[$i] -eq 13) {
      if($i + 1 -ge $Bytes.Length -or $Bytes[$i + 1] -ne 10) { throw 'RELEASE BLOCKED — live shipping input contains a lone CR; only CRLF materialization is permitted.' }
      [void]$out.Add(10); $i++; continue
    }
    [void]$out.Add($Bytes[$i])
  }
  return $out.ToArray()
}
function Test-ByteArrayEqual([byte[]]$Left,[byte[]]$Right) {
  if($Left.Length -ne $Right.Length){return $false}
  for($i=0;$i -lt $Left.Length;$i++){if($Left[$i] -ne $Right[$i]){return $false}}
  return $true
}
$candidateKeys=@($candidateIdentity.candidateShippingInputs | ForEach-Object { "$($_.root)/$($_.path)" })
$liveKeys=@($candidateIdentity.liveShippingInputs | ForEach-Object { "$($_.root)/$($_.path)" })
if($candidateKeys.Count -ne $liveKeys.Count -or @((Compare-Object -ReferenceObject $candidateKeys -DifferenceObject $liveKeys -IncludeEqual:$false)).Count -ne 0){throw 'RELEASE BLOCKED — live and candidate shipping input row sets differ.'}
foreach($row in @($candidateIdentity.candidateShippingInputs)) {
  $rootPath = if([string]$row.root -ceq 'source'){$source}else{Join-Path $workspaceRoot 'installer-source'}
  $candidateRoot = if([string]$row.root -ceq 'source'){$buildSource}else{$buildInstaller}
  $livePath = Join-Path $rootPath ([string]$row.path).Replace('/','\')
  $candidatePath = Join-Path $candidateRoot ([string]$row.path).Replace('/','\')
  if(-not (Test-Path -LiteralPath $livePath -PathType Leaf) -or -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)){throw "RELEASE BLOCKED — shipping input is missing from live or candidate tree: $($row.root)/$($row.path)"}
  $liveBytes=[IO.File]::ReadAllBytes($livePath); $candidateBytes=[IO.File]::ReadAllBytes($candidatePath)
  if(-not (Test-ByteArrayEqual $liveBytes $candidateBytes)) {
    $normalizedLive=Normalize-CrlfOnly $liveBytes
    if(-not (Test-ByteArrayEqual $normalizedLive $candidateBytes)){throw "RELEASE BLOCKED — live checkout shipping input differs substantively from the candidate commit: $($row.root)/$($row.path)"}
  }
}
$stageIdentityJson = & $releasePython $shippingIdentityTool --source-root $buildSource --installer-root $buildInstaller | Select-Object -Last 1
if($LASTEXITCODE){throw 'RELEASE BLOCKED — staged shipping identity could not be computed.'}
$stageIdentity = $stageIdentityJson | ConvertFrom-Json
if([string]$stageIdentity.shippingInputIdentity -cne [string]$candidateIdentity.candidateShippingInputIdentity){throw 'RELEASE BLOCKED — staged shipping identity does not match the candidate commit.'}
$verifiedOutputs=[string]$verification.outputDirectory
$verifiedTar=Join-Path $verifiedOutputs "devfleet-v$((Get-Content -LiteralPath (Join-Path $buildSource 'VERSION') -Raw).Trim()).tar.gz"
$verifiedPortable=Join-Path $verifiedOutputs "DevFleet-v$((Get-Content -LiteralPath (Join-Path $buildSource 'VERSION') -Raw).Trim())-Portable-Codebase-Verified-r1.zip"
if(-not (Test-Path -LiteralPath $verifiedTar) -or -not (Test-Path -LiteralPath $verifiedPortable)){throw 'RELEASE BLOCKED — frozen verification did not produce authoritative TAR and portable artifacts.'}
Copy-Item -LiteralPath $verifiedTar -Destination (Join-Path $outputs (Split-Path -Leaf $verifiedTar)) -Force
Copy-Item -LiteralPath $verifiedPortable -Destination (Join-Path $outputs (Split-Path -Leaf $verifiedPortable)) -Force
function Assert-StageShippingIdentity([string]$Phase) {
  $currentJson = & $releasePython $shippingIdentityTool --source-root $buildSource --installer-root $buildInstaller | Select-Object -Last 1
  if($LASTEXITCODE){throw "RELEASE BLOCKED — shipping identity recomputation failed at $Phase."}
  $current = $currentJson | ConvertFrom-Json
  if([string]$current.shippingInputIdentity -cne [string]$candidateIdentity.candidateShippingInputIdentity){throw "RELEASE BLOCKED — shipping identity changed at $Phase."}
}
$devfleetVersion=(Get-Content -LiteralPath (Join-Path $buildSource 'VERSION') -Raw).Trim()
$installerVersion=(Get-Content -LiteralPath (Join-Path $buildInstaller 'INSTALLER_VERSION') -Raw).Trim()
if($devfleetVersion -notmatch '^\d+\.\d+\.\d+$'){throw "Release source VERSION is not semantic: $devfleetVersion"}
if($installerVersion -notmatch '^\d+\.\d+\.\d+$'){throw "Installer VERSION is not semantic: $installerVersion"}
$assemblyVersion="$installerVersion.0"
$advisoryReport = Join-Path $outputs 'dependency-advisory-gate.json'
& $releasePython (Join-Path $buildSource 'tools\check_dependency_advisories.py') --lock (Join-Path $buildSource 'app\requirements-hashed.txt') --allowlist (Join-Path $buildSource 'linux\dependency-advisory-allowlist.json') --output $advisoryReport
if($LASTEXITCODE){throw 'Dependency security-freshness gate blocked the release build.'}
$osvScanner=if($OsvScannerPath){$OsvScannerPath}elseif($env:DEVFLEET_OSV_SCANNER_PATH){$env:DEVFLEET_OSV_SCANNER_PATH}else{(Get-Command osv-scanner.exe -ErrorAction SilentlyContinue).Source}
if(-not $osvScanner -or -not (Test-Path -LiteralPath $osvScanner -PathType Leaf)){throw 'RELEASE BLOCKED — first-party OSV-Scanner is unavailable; dependency reconciliation is fail-closed.'}
$osvReconciliation = Join-Path $outputs 'independent-osv-reconciliation.json'
& $releasePython (Join-Path $workspaceRoot 'tools\reconcile_osv_scanner.py') --scanner $osvScanner --lock (Join-Path $buildSource 'app\requirements-hashed.txt') --custom-report $advisoryReport --output $osvReconciliation
if($LASTEXITCODE){throw 'Independent OSV-Scanner reconciliation blocked the release build.'}
$tar=Join-Path $outputs "devfleet-v$devfleetVersion.tar.gz"
$hash=(Get-FileHash -LiteralPath $tar -Algorithm SHA256).Hash.ToLowerInvariant()
if((Get-Content -LiteralPath (Join-Path $buildInstaller 'DevFleet.Setup\PayloadManifest.cs') -Raw) -notmatch [regex]::Escape($hash)){throw 'PayloadManifest.cs is not synchronized with the frozen TAR SHA-256.'}
if((Get-Content -LiteralPath (Join-Path $buildInstaller 'DevFleet.Setup\DevFleet.Setup.csproj') -Raw) -notmatch [regex]::Escape("devfleet-v$devfleetVersion.tar.gz")){throw 'Installer project payload metadata is not synchronized with the frozen version.'}
if((Get-Content -LiteralPath (Join-Path $buildInstaller 'DevFleet.Setup\app.manifest') -Raw) -notmatch ('assemblyIdentity\s+version="'+[regex]::Escape($assemblyVersion)+'"')){throw 'Windows application manifest identity is not synchronized with the frozen installer version.'}
$sourceZip = Join-Path $outputs "DevFleet-v$devfleetVersion-Installer-Source.zip"
& $releasePowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $buildSource 'tools\Build-InstallerSourceZip.ps1') -SourceRoot $buildSource -InstallerRoot $buildInstaller -OutputPath $sourceZip
if($LASTEXITCODE){throw 'Installer source archive build failed.'}
& $releasePython (Join-Path $buildSource 'tools\release_fingerprint.py') --source-root $buildSource --installer-root $buildInstaller --output (Join-Path $outputs 'release-fingerprint.json') --artifact "tar=$tar" --artifact "portable=$(Join-Path $outputs "DevFleet-v$devfleetVersion-Portable-Codebase-Verified-r1.zip")" --artifact "installerSource=$sourceZip"
if($LASTEXITCODE){throw 'Release fingerprint generation failed.'}
& $DotNet restore (Join-Path $buildInstaller 'DevFleet.Setup\DevFleet.Setup.csproj')
if($LASTEXITCODE){throw 'dotnet restore failed.'}
& $DotNet build (Join-Path $buildInstaller 'DevFleet.Setup\DevFleet.Setup.csproj') -c Release --no-restore
if($LASTEXITCODE){throw 'dotnet build failed.'}
& $DotNet run --project (Join-Path $buildInstaller 'DevFleet.Setup.Tests\DevFleet.Setup.Tests.csproj') -c Release
if($LASTEXITCODE){throw 'installer tests failed.'}
$publish=Join-Path $outputs 'publish';New-Item -ItemType Directory -Path $publish -Force|Out-Null
& $DotNet publish (Join-Path $buildInstaller 'DevFleet.Setup\DevFleet.Setup.csproj') -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $publish
if($LASTEXITCODE){throw 'installer publish failed.'}
$unsignedExe=Join-Path $outputs "DevFleet-Setup-v$devfleetVersion-win-x64.exe"
Copy-Item -LiteralPath (Join-Path $publish 'DevFleet.Setup.exe') -Destination $unsignedExe -Force
$selfTest=Join-Path $outputs 'unsigned-self-test.txt'
$env:DEVFLEET_SELF_TEST_OUTPUT=$selfTest
$selfTestProcess=Start-Process -FilePath $unsignedExe -ArgumentList '--self-test' -Wait -PassThru
Remove-Item Env:DEVFLEET_SELF_TEST_OUTPUT -ErrorAction SilentlyContinue
if($selfTestProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $selfTest) -or (Get-Content -LiteralPath $selfTest -Raw) -notmatch '(?m)^PASS(?:\r?$)'){throw 'Unsigned installer self-test failed.'}
Assert-StageShippingIdentity 'pre-sign'
$portable = Join-Path $outputs "DevFleet-v$devfleetVersion-Portable-Codebase-Verified-r1.zip"
$fingerprintArgs = @(
  ("--artifact=exe=$unsignedExe"),
  ("--artifact=tar=$tar"),
  ("--artifact=portable=$portable"),
  ("--artifact=installerSource=$sourceZip")
)
& $releasePython (Join-Path $buildSource 'tools\release_fingerprint.py') --source-root $buildSource --installer-root $buildInstaller --output (Join-Path $outputs 'release-fingerprint.json') @fingerprintArgs
if($LASTEXITCODE){throw 'Final release fingerprint generation failed.'}
$artifactRows = @(
  [ordered]@{name='exe';path="outputs/DevFleet-Setup-v$devfleetVersion-win-x64.exe";bytes=(Get-Item $unsignedExe).Length;sha256=(Get-FileHash $unsignedExe -Algorithm SHA256).Hash.ToLowerInvariant()},
  [ordered]@{name='tar';path="outputs/devfleet-v$devfleetVersion.tar.gz";bytes=(Get-Item $tar).Length;sha256=(Get-FileHash $tar -Algorithm SHA256).Hash.ToLowerInvariant()},
  [ordered]@{name='portable';path="outputs/DevFleet-v$devfleetVersion-Portable-Codebase-Verified-r1.zip";bytes=(Get-Item $portable).Length;sha256=(Get-FileHash $portable -Algorithm SHA256).Hash.ToLowerInvariant()},
  [ordered]@{name='installerSource';path="outputs/DevFleet-v$devfleetVersion-Installer-Source.zip";bytes=(Get-Item $sourceZip).Length;sha256=(Get-FileHash $sourceZip -Algorithm SHA256).Hash.ToLowerInvariant()}
)
$fingerprintObject=Get-Content (Join-Path $outputs 'release-fingerprint.json') -Raw | ConvertFrom-Json
if([int]$fingerprintObject.schemaVersion -ne 2){throw 'Current candidate release fingerprint must use schema v2.'}
$candidateGitBranch=(& git -C $workspaceRoot branch --show-current 2>$null).Trim()
if($candidateGitCommit -notmatch '^[0-9a-fA-F]{40}$' -or -not $candidateGitBranch){throw 'Release candidate identity could not be bound to a local Git commit and branch.'}
$signingState='PRE-SIGN UNSIGNED — Authenticode signing and verification occur later in this invocation'
$currentTooling = [ordered]@{schemaVersion=2;releaseFingerprintSchemaVersion=2;releaseFingerprintId=$fingerprintObject.releaseFingerprintId;toolingFingerprintId=$fingerprintObject.toolingFingerprint.toolingFingerprintId;toolingInputs=$fingerprintObject.toolingFingerprint.toolingInputs;artifacts=$artifactRows;generatedAt=(Get-Date).ToUniversalTime().ToString('o')}
$currentToolingPath = Join-Path $outputs 'tooling-fingerprint-current.json'
$currentToolingTemporary = "$currentToolingPath.$([guid]::NewGuid().ToString('N')).tmp"
try {
  [IO.File]::WriteAllText($currentToolingTemporary, (($currentTooling | ConvertTo-Json -Depth 12) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $currentToolingTemporary -Destination $currentToolingPath -Force
} finally {
  Remove-Item -LiteralPath $currentToolingTemporary -Force -ErrorAction SilentlyContinue
}
$finalManifest = [ordered]@{schemaVersion=2;releaseFingerprintSchemaVersion=2;releaseVersion=$devfleetVersion;installerVersion=$installerVersion;gitCommit=$candidateGitCommit;branch=$candidateGitBranch;candidateGitCommit=$candidateGitCommit;shippingInputIdentity=$candidateIdentity.candidateShippingInputIdentity;candidateShippingInputIdentity=$candidateIdentity.candidateShippingInputIdentity;releaseFingerprintId=$fingerprintObject.releaseFingerprintId;toolingFingerprintId=$fingerprintObject.toolingFingerprint.toolingFingerprintId;artifacts=$artifactRows;sourceChangedSinceCandidate=$false;rebuildRequired=$false;sourceIdentityMatchesCandidate=$true;artifactTupleMatchesCandidate=$true;candidateBuildCurrent=$true;candidateIsCurrent=$true;validationEvidenceCurrent=$false;fullReleasePassed=$false;physicalSurrogateCertificationCurrent=$false;internalPromotionAllowed=$false;publicPromotionAllowed=$false;releaseStatus='BLOCKED';signingState=$signingState;signing=$signingState}
$finalManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputs 'final-artifact-hashes.json') -Encoding utf8
$state=[ordered]@{
  release_version=$devfleetVersion;installer_version=$installerVersion;workspace=$workspaceRoot;branch=$candidateGitBranch;git_commit=$candidateGitCommit;candidate_git_commit=$candidateGitCommit;shipping_input_identity=$candidateIdentity.candidateShippingInputIdentity;candidate_shipping_input_identity=$candidateIdentity.candidateShippingInputIdentity;current_phase='candidate-built-awaiting-clean-fullrelease';last_completed_phase='candidate-build-and-self-test';status='BLOCKED';authorized_correction=$authorizedCorrection;source_changed_since_candidate=$false;rebuild_required=$false;source_identity_matches_candidate=$true;artifact_tuple_matches_candidate=$true;candidate_build_current=$true;candidate_is_current=$true;validation_evidence_current=$false;full_release_passed=$false;physical_surrogate_certification_current=$false;internal_promotion_allowed=$false;public_promotion_allowed=$false;release_status='BLOCKED';signing_state=$signingState;release_fingerprint_schema_version=2;releaseFingerprintId=$fingerprintObject.releaseFingerprintId;toolingFingerprintId=$fingerprintObject.toolingFingerprint.toolingFingerprintId;production_safety=[ordered]@{production_unchanged=$true;mulattotechsurface_touched=$false;scope='disposable DevFleet-E2E resources only'};candidate=[ordered]@{exe=$artifactRows[0];tar=$artifactRows[1];portable=$artifactRows[2];installer_source=$artifactRows[3]};self_test=(Get-Content (Join-Path $outputs 'unsigned-self-test.txt') -Raw);gates=[ordered]@{dependency_matrix='UNVERIFIED — exact candidate FullRelease required';wpf='UNVERIFIED — exact candidate FullRelease required';linux='UNVERIFIED — exact candidate Linux validation required';primary='UNVERIFIED — exact candidate FullRelease required';repair='UNVERIFIED — exact candidate FullRelease required';clean_reinstall='UNVERIFIED — exact candidate FullRelease required';uninstall='UNVERIFIED — exact candidate FullRelease required';factory_reset='UNVERIFIED — exact candidate FullRelease required';reboot_resume='UNVERIFIED — exact candidate FullRelease required';maintenance='UNVERIFIED — 0/5 promoted for current candidate';stopped_project='UNVERIFIED — exact candidate FullRelease required';tailscale_install_deferred='UNVERIFIED — exact candidate FullRelease required';tailscale_full_auth='UNVERIFIED — exact candidate FullRelease required';automation_harness='IMPLEMENTED — non-shipping tooling; complete FullRelease not yet certified'};blockers=@('Final clean-room FullRelease against this exact candidate is required.','Physical MulattoTechSurface Laptop/Surrogate validation is required before v1.2.13 can be final.')
}
$state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $workspaceRoot 'finalization-state.json') -Encoding utf8
@("DevFleet $devfleetVersion / Installer $installerVersion","Status: candidate current; awaiting exact-candidate clean FullRelease","Git commit: $candidateGitCommit","Release fingerprint: $($fingerprintObject.releaseFingerprintId)","Tooling fingerprint: $($fingerprintObject.toolingFingerprint.toolingFingerprintId)",'Source changed since candidate: FALSE','Rebuild required: FALSE','Candidate is current: TRUE','All expensive ac