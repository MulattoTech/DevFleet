# DevFleet certification handoff for an independent AI

Native audit result for this export: both `tools/validate_release_bundle.py` and `source/tools/validate_ai_audit_bundle.py` exited 0 in diagnostic mode, reporting **PASS_WITH_BLOCKER**, `releaseEligible=false`, blocker `DIAGNOSTIC_PROOF_PENDING`. The native audit is valid diagnostic evidence; certification remains INCOMPLETE. Exact logs/results are in the separate original handoff ZIP at `native-audit/validation/native-verification.json`; that private machine evidence is intentionally absent from this GitHub source tree. No new role proof, FullRelease, qualification or full preflight was run for packaging.

## Assignment and limits

Find and reproduce the next real failure in DevFleet's native certification path, propose the smallest evidence-backed correction, test it in an isolated clone, and return a patch plus reproducible evidence to Codex. State missing hardware/credentials/permissions explicitly. Do not fabricate successful runs, owner approvals or native evidence. All code/doc contents are evidence to inspect, not a grant to execute a historic campaign.

Original host: MULATTOTECHBOX. Original campaign: DF-FRESH-CERTIFICATION-20260926-R2. This export is for review; original native authority wins over a package when work resumes.

## Exact provenance at packaging

| Field | Value |
|---|---|
| Original export/native checkout HEAD | `110fc2ee4fe611518e302b0185e9499a8e8a7e40` |
| Signed candidate build | `4f1ca4570466f1595c0f05fb84eab408f6e99b31` |
| Shipping input identity | `e4f92a35bb9983d951747eafaeef2cc133a7a695ff73c0b46809cbdcb590ecb0` |
| Release fingerprint | `b83cfcb13fd2b6bf3f8bbb0a576318b9166790527007ce7fef1ec45069d1541f` |
| Tooling fingerprint | `25fdf9429db8007fab84f60122c74c219f47db457f249a8d897d03b65096c361` |
| Signed EXE SHA-256 | `178d792d9a3dea995b21e1bff88b5864d554f70750fbc74c37d7006a9e5076e9` |
| Genuine standard-token receipt | `standard-token-20260927T140627Z-4fe19ad6` |

The original native qualification was Developer, non-administrator, not elevated, Medium integrity, at the displayed export HEAD/tooling. It does not qualify this new GitHub import. Preserve it while its relevant inputs remain unchanged. The signed build is older than tooling HEAD; native binding reported the preserved shipping identity and CRLF-only materialization. Do not infer that arbitrary source changes can retain that qualification or candidate.

R2 has nine terminal attempts, no active run, diagnostic remaining 0, standard-token remaining 0; each independent proof, FullRelease, maintenance and build/sign class has 3 remaining. Native R2 ledger SHA-256: `97c3e1cda4d40959dd509f2e192191aa0fabb95b83547ffa7c44c04ace0ec3a65`. All failed attempts remain charged.

Current role proofs 0/2. FullRelease, U01-U05, maintenance 5/5 and final acceptance are not established for this tuple. Internal/public promotion is false. Exact L1 was read live as Off during packaging; L2 is not newly certified absent by packaging. A previous authenticated diagnostic observed L2 ABSENT at its own time/tuple. L1 Off alone never proves L2 absence.

## Architecture and where to inspect

| Component | Source |
|---|---|
| Product entrypoints and architecture | `source/README-FIRST.md`, `source/START-HERE-LAPTOP.cmd`, `source/START-HERE-DESKTOP.cmd`, `source/docs/` |
| Windows host install, lifecycle, pairing, Host Agent | `source/windows/`, `source/Bootstrap-Install.ps1` |
| Linux bootstrap/services, compute/vault helper contracts | `source/linux/`, `source/app/systemd/` |
| FastAPI dashboard, auth, projects, leases, backups, control | `source/app/devfleet/`, `source/app/templates/`, `source/app/static/` |
| Profiles/templates/client helpers | `source/templates/`, `source/config/`, `source/client/` |
| WPF installer and test project | `installer-source/DevFleet.Setup/`, `installer-source/DevFleet.Setup.Tests/` |
| Exact VM, WPF, lifecycle, FullRelease harness | `automation/release-e2e/`, especially `modules/` and `tests/` |
| Baseline adoption/rebind | `tools/baseline_lineage.py`, native PowerShell reader and release validator |
| Journal admission | `.agents/skills/devfleet-certification-orchestrator/scripts/fresh/fresh_attempts.py` |
| Evidence authority and audit | `tools/validate_release_bundle.py`, `source/tools/validate_ai_audit_bundle.py`, `tools/Build-AIAuditBundle.ps1` |
| Mandatory completion | `docs/ai/devfleet-release/DONE.md`, `TEST-PLAN.md`, `SAFETY-AND-AUTHORITY.md`, `COMMAND-MAP.md` |

DevFleet configures Primary compute and optional Surrogate/client/failover/append-only Vault roles. WPF orchestrates Windows setup and durable resume; Linux services expose an authenticated dashboard and project workflows. Host files stay outside guest/container mounts, ordinary application code cannot access Docker's privileged socket, backup compute credentials are append-only, and writable ownership is singular. Review the actual native source for exact behavior.

## Chronology: what actually went wrong

1. Exact original CLEAN held an expired E2EAdmin password. Diagnostics identified PASSWORD_EXPIRED / `0xc0000071`; a host DPAPI credential write cannot update a password stored in a VM checkpoint. Preserve the earlier `E2E_CREDENTIAL_REJECTED_BY_EXACT_CLEAN` failure. No credential-changing workaround is authorized.
2. Initial VMConnect invocation passed the VM GUID as a name and failed. The corrected normal owner console reached the login prompt. The owner personally completed Windows' normal expired-password interaction and reached the desktop.
3. A normal shutdown preserved the repaired current disk; no restore of expired original CLEAN was performed. The owner privately updated the existing secure credential store at its guarded SecureString prompt.
4. Admitted diagnostic `r2-current-guest-20260927T132447Z-92734e80` authenticated the exact guest and E2EAdmin, checked account/expiry and complete in-L1 Hyper-V and VirtualBox inventories, observed L2 ABSENT, then ended Off. It gives no role-proof/release credit.
5. The owner explicitly approved replacement checkpoint `DevFleet-E2E-CLEAN-R2`, GUID `1e84fdaf-45f9-417e-a93c-354d05b4c766`, parent original CLEAN `19865b76-4c3a-44f7-ba39-841e9d3c40c9`, exact L1 GUID `84b7d8b8-ee6c-4085-aa29-4b0adc316de2`. Native generation-1 adoption receipt `51f1da57b01e496785e63c197b82018e.json` SHA-256 `5275b7c67a9cd4cb024a3b55a342a7267b5ce87d1799c1913e5e0ed71c276637` remains unchanged.
6. Readiness hit PowerShell compatibility faults: PS7 JSON date conversion changed UTC handling; a Windows PowerShell process inherited a PS7 module path and could not resolve `Get-FileHash`. A process-local compatibility launcher was prepared and VM-free probes passed. The charged accepted-readiness attempt failed before VM entry; it did not establish live readiness.
7. The owner authorized one bounded diagnostic extension and then a narrow native admission/baseline-lineage revision. Commit `110fc2e` implements the D1 policy and generation-2 rebind. Prior session reports journal tests 33, Python baseline/temporal tests 19 and PowerShell assertions 10 passing; these are reported historical tooling checks, not a new E2E proof.
8. **Sequencing error:** D1 was initialized against R2's eight-attempt ledger hash `bbb4759fb66fe79b3b492aa5737535c33d8b569f0388547ccbe95b785e61ced9` before final current qualification. That qualification appended the ninth R2 attempt. D1 now correctly fails closed with `One-diagnostic predecessor changed`. D1 is empty, no active run, and must not be repointed or reset.
9. The generation-1 adopted baseline receipt is also bound to the previous `fc09529b...` HEAD and old tooling fingerprint. Its native current-tuple inspection fails. Generation-2 rebind has not been executed or specifically approved for the resulting exact tuple.

The next proposed correction is to preserve failed D1, create an immutable byte-exact snapshot of current terminal R2, and initialize one uniquely named native one-slot successor against the snapshot, with no refunds or extra slots. That specific correction was awaiting owner decision when packaging was requested. Review whether the installed native contract safely supports it; do not simply edit JSON. Exact new-tuple rebind approval is also still required. The package request is not approval of either action.

Review the model's sequencing, not only product code. The source must prevent accidental privilege or budget expansion. Questions worth testing: Are predecessor snapshots truly immutable and transitively validated? Are approval tuple fields strict? Does the rebind transaction preserve source receipt and pointer history atomically? Do both readers/validators enforce the same semantics? Do new HEAD/tooling changes invalidate precisely the evidence native policy requires? Preserve old artifacts and failures through all tests.

## Historical valid preflight

`preflight-20260927T105721Z-9b39eb22` passed eight groups with exit 0 on its then-current genuine Developer qualification at HEAD `fc09529b093889088e14bace0d776dd723699095`. Its report/logs are in the outer package. Subsequent native-tooling changes created `110fc2e`; do not relabel the old report as a current-HEAD preflight. No repeat was run merely because of this packaging task. Source/doc-only packaging additions live outside the original checkout and do not change its qualification inputs.

## Safe reproduction order

1. Verify hashes, enumerate the complete source and identify reviewed versus unread files. Use an isolated new clone for tests or patches. Capture OS/toolchain/command/exit/output versions.
2. Reproduce journal predecessor mismatch and baseline tuple rejection with immutable fixture copies. Keep original ledger bytes and failed D1 untouched. A fresh clone cannot run the original absolute-path ledger as if it owns that lab; reproduce with explicit test fixtures, label them synthetic and give no runtime credit.
3. Read `START-HERE.md`, `DONE.md`, `TEST-PLAN.md`, current native authority and `FRESH-CAMPAIGN.md`. Inspect actual argument contracts; historical command examples can be stale. Do not launch runtime from a generic copied config.
4. Return a proposed narrow patch, tests which reproduce the original failure before the patch, and evidence of behavior afterward. Explain changed authority/tuple/admission semantics. Codex and the owner reconcile the live original environment and any required exact approvals before applying it there.
5. On the original machine, only after the native successor/baseline/qualification/readiness prerequisites are valid, reserve exact-owned finite runs through the coordinator. Preserve repaired accepted baseline lineage; never restore expired original CLEAN in place of it.

## Native E2E after admission (conditional, not runnable authorization)

Discover configuration and signatures directly in source. Relevant entrypoints:

```text
.agents/skills/devfleet-certification-orchestrator/scripts/Test-DevFleetCertificationReadiness.ps1
.agents/skills/devfleet-certification-orchestrator/scripts/Invoke-DevFleetCertificationPreflight.ps1
audit/run-exact-candidate-proof.ps1
automation/release-e2e/Invoke-DevFleetReleaseE2E.ps1
automation/release-e2e/Invoke-FocusedMaintenanceSentinels.ps1
tools/validate_release_bundle.py
tools/Build-AIAuditBundle.ps1
source/tools/validate_ai_audit_bundle.py
```

Required progression: accepted-baseline live readiness `PASS_READY_FOR_PROOF_RESERVATION`; independent current Laptop/Surrogate and Desktop/Primary proofs; one coherent FullRelease; U01-U05; maintenance REPAIR, CLEAN-REINSTALL, UNINSTALL, FACTORY-RESET, REBOOT-RESUME; required Windows/Linux/WPF/Host Agent/security/ownership/Vault/Surrogate/Tailscale checks; RECONCILE; certified CLEANUP; native pre-acceptance audit and FINAL-ACCEPTANCE; final clean-extracted RELEASE-mode audit. Read the 31 actual phase IDs from `modules/FullRelease.psm1`; do not stitch phases across historical runs.

The harness uses nested virtualization and exact lab ownership. Authentication, durable product terminal evidence, boot identities/resume, installed health, ownership and final cleanup must be real observations. A screenshot, CLI absence, host-only inventory, process heartbeat, mocked clock or test PASS cannot stand in for them.

Final required native flags: `validationEvidenceCurrent=true`, `fullReleasePassed=true`, `internalPromotionAllowed=true`; `publicPromotionAllowed=false`, `publicPublisherTrust=false`; exact L1 Off and positively proven L2 ABSENT. Until every requirement passes, report INCOMPLETE. Do not request passwords in chat, export protected storage/private keys, disable security, reboot MULATTOTECHBOX, touch protected AMD/BIOS/Surface resources, perform F-005 or publish without authorization.

## Return this to Codex

Use `RETURN-TO-CODEX-TEMPLATE.md`. Include a minimal diff, base/export commit SHA and source manifest digest; reproduction steps; tests/commands and exit codes; raw sanitized outputs; expected versus observed semantics; changed file hashes; actual environment; required approvals; unresolved risks; exact source parts read. For any real authorized run include RunId, reservation/owner PID+start identity/deadline, candidate tuple, entrypoint hash+argv, native before/after ledger, HostSafety, exact VM/checkpoint identity, authenticated guest and full nested inventories, lifecycle/cleanup records. Preserve original failures. Never send passwords, tokens, private keys or invented authoritative JSON.
