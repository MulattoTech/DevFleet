# DevFleet source part 124

Full-source UTF-8 byte interval [5719500, 5766000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 2bdf2d67591ca5b39e6fdc1128b5a5fc1f84bac77d6792dbef3700c557d420e7

<!-- BEGIN SOURCE SLICE -->
 / "outputs" / "DevFleet-v1.2.13-AI-Audit-LATEST.zip"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(entries: dict[str, bytes], name: str) -> dict:
    return json.loads(entries[name].decode("utf-8-sig"))


def put(entries: dict[str, bytes], name: str, value: object) -> None:
    entries[name] = (json.dumps(value, indent=2) + "\n").encode()


def canonical_shipping_rows(rows: list[dict]) -> list[dict]:
    return sorted(rows, key=lambda row: (0 if row["root"] == "source" else 1, tuple(part.casefold() for part in row["path"].split("/"))))


def shipping_identity(rows: list[dict], mode: dict, version: str, installer: str) -> str:
    payload = {"schemaVersion": 1, "devfleetVersion": version, "installerVersion": installer, "shippingModeContract": mode, "shippingInputs": canonical_shipping_rows(rows)}
    return digest(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode())


def release_identity(release: dict) -> str:
    payload = {key: release.get(key) for key in ("schemaVersion", "devfleetVersion", "installerVersion", "shippingModeContract")}
    payload["shippingInputs"] = release.get("shippingInputs")
    payload["artifacts"] = release.get("artifacts", [])
    return digest(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode())


def final_entries() -> dict[str, bytes]:
    with zipfile.ZipFile(ARCHIVE) as archive:
        entries = {name: archive.read(name) for name in archive.namelist() if not name.endswith("/")}
    state = read_json(entries, "finalization-state.json")
    candidate = str(state["candidate_git_commit"])
    head = str(state["repository_head"])
    manifest = read_json(entries, "AUDIT-MANIFEST.json")
    shipping_rows = []
    for row in manifest["sourceInventory"]:
        path = str(row["path"]).replace("\\", "/")
        if path.startswith("source/"):
            root_name, relative = "source", path[len("source/"):]
        elif path.startswith("installer-source/"):
            root_name, relative = "installer-source", path[len("installer-source/"):]
        else:
            continue
        shipping_rows.append({"root": root_name, "path": relative, "bytes": int(row["bytes"]), "sha256": str(row["sha256"]).lower(), "mode": str(row["mode"])})
    mode = manifest["shippingModeContract"]
    shipping_rows = canonical_shipping_rows(shipping_rows)
    shipping = shipping_identity(shipping_rows, mode, str(manifest["devfleetVersion"]), str(manifest["installerVersion"]))
    release_record = read_json(entries, "outputs/release-fingerprint.json")
    release_record.update({"devfleetVersion": manifest["devfleetVersion"], "installerVersion": manifest["installerVersion"], "shippingModeContract": mode, "shippingInputs": shipping_rows})
    release = release_identity(release_record)
    release_record["releaseFingerprintId"] = release
    put(entries, "outputs/release-fingerprint.json", release_record)
    tooling_record = read_json(entries, "outputs/tooling-fingerprint-current.json")
    tooling_record.update({"repositoryHead": head, "gitCommit": head, "candidateGitCommit": head, "shippingInputIdentity": shipping, "candidateShippingInputIdentity": shipping, "releaseFingerprintId": release})
    put(entries, "outputs/tooling-fingerprint-current.json", tooling_record)
    tooling = str(state["toolingFingerprintId"])
    run_id = "FullRelease-synthetic-current"
    state["repository_head"] = head
    state["candidate_git_commit"] = head
    state["candidate_shipping_input_identity"] = shipping
    state["shipping_input_identity"] = shipping
    state["releaseFingerprintId"] = release
    state.update({"source_changed_since_candidate": False, "rebuild_required": False, "source_identity_matches_candidate": True, "artifact_tuple_matches_candidate": True, "candidate_build_current": True, "candidate_is_current": True, "validation_evidence_current": True, "full_release_passed": True, "internal_promotion_allowed": True, "public_promotion_allowed": False, "full_release_run_id": run_id, "full_release_current": True})
    state.update({"status": "PASS", "release_status": "PASS", "blocker": None})
    candidate_record = read_json(entries, "CURRENT-CANDIDATE.json")
    candidate_record.pop("historicalProvenance", None)
    candidate_record.update({"repositoryHead": head, "gitCommit": head, "candidateCommit": head, "candidateShippingInputs": shipping_rows, "candidateShippingModeContract": mode, "shippingModeContract": mode, "shippingInputIdentity": shipping, "candidateShippingInputIdentity": shipping, "releaseFingerprintId": release, "candidateIsCurrent": True, "sourceChangedSinceCandidate": False, "rebuildRequired": False})
    candidate_record["candidateTuple"] = {"candidateCommit": head, "shippingInputIdentity": shipping, "releaseFingerprintId": release, "toolingFingerprintId": tooling}
    manifest.pop("historicalProvenance", None)
    manifest.update({"repositoryHead": head, "gitCommit": head, "candidateGitCommit": head, "shippingInputIdentity": shipping, "candidateShippingInputIdentity": shipping, "releaseFingerprintId": release, "candidate": candidate_record, "candidateIsCurrent": True, "sourceChangedSinceCandidate": False, "rebuildRequired": False})
    put(entries, "CURRENT-CANDIDATE.json", candidate_record)
    put(entries, "AUDIT-MANIFEST.json", manifest)
    artifact_manifest = read_json(entries, "outputs/final-artifact-hashes.json")
    artifact_manifest.update({"repositoryHead": head, "gitCommit": head, "candidateGitCommit": head, "shippingInputIdentity": shipping, "releaseFingerprintId": release, "sourceChangedSinceCandidate": False, "rebuildRequired": False, "sourceIdentityMatchesCandidate": True, "candidateBuildCurrent": True, "candidateIsCurrent": True, "validationEvidenceCurrent": True, "fullReleasePassed": True, "internalPromotionAllowed": True, "publicPromotionAllowed": False})
    put(entries, "outputs/final-artifact-hashes.json", artifact_manifest)
    tuple_value = {"repositoryHead": head, "candidateCommit": candidate, "shippingInputIdentity": shipping, "releaseFingerprintId": release, "toolingFingerprintId": tooling}
    tuple_value["candidateCommit"] = head

    # The archive contains several current-authority documents whose nested
    # ``candidate`` records predate this synthetic current-candidate fixture.
    # Rebind those records together, so the release-tooling validator sees one
    # coherent tuple while preserving any separately marked historical data.
    def rebind_current_authority(value: object) -> None:
        if isinstance(value, dict):
            for key in ("repositoryHead", "repository_head", "gitCommit", "git_commit", "candidateGitCommit", "candidate_git_commit", "candidateCommit", "candidate_commit"):
                if key in value:
                    value[key] = head
            for key in ("shippingInputIdentity", "shipping_input_identity", "candidateShippingInputIdentity", "candidate_shipping_input_identity"):
                if key in value:
                    value[key] = shipping
            for key in ("releaseFingerprintId",):
                if key in value:
                    value[key] = release
            for key in ("toolingFingerprintId",):
                if key in value:
                    value[key] = tooling
            for key in ("candidateIsCurrent", "candidate_is_current", "sourceIdentityMatchesCandidate", "source_identity_matches_candidate", "candidateBuildCurrent", "candidate_build_current", "validationEvidenceCurrent", "validation_evidence_current", "fullReleasePassed", "full_release_passed", "internalPromotionAllowed", "internal_promotion_allowed"):
                if key in value:
                    value[key] = True
            for key in ("sourceChangedSinceCandidate", "source_changed_since_candidate", "rebuildRequired", "rebuild_required", "publicPromotionAllowed", "public_promotion_allowed"):
                if key in value:
                    value[key] = False
            for child in value.values():
                rebind_current_authority(child)
        elif isinstance(value, list):
            for child in value:
                rebind_current_authority(child)

    # The shipping coherence gate inspects every top-level audit JSON record.
    # This isolated final-state fixture must project those mutable handoffs to
    # its synthetic tuple as well; nested historical originals are untouched.
    authority_names = {"evidence/CURRENT-STATUS.json", "evidence/CURRENT-GATES.json", "evidence/CURRENT-PROOF.json", "evidence/FULLRELEASE-SUMMARY.json", "evidence/CURRENT-HANDOFF.json", "evidence/CURRENT-RELEASE-AUTHORITY.json"}
    authority_names.update(name for name in entries if name.startswith("audit/") and name.count("/") == 1 and name.endswith(".json"))
    for authority_name in sorted(authority_names):
        authority = read_json(entries, authority_name)
        rebind_current_authority(authority)
        put(entries, authority_name, authority)

    # A release-good fixture must never smuggle the historical candidate
    # provenance that is tested separately in diagnostic mode.
    assert "historicalProvenance" not in candidate_record
    assert "historicalProvenance" not in manifest
    # Current authority evidence must bind the same synthetic current tuple;
    # preserved historical records, if any, remain untouched in their own
    # historical namespaces.
    handoff = read_json(entries, "audit/CURRENT-HANDOFF.json")
    handoff.update({"repositoryHead": head, "candidateCommit": head, "shippingInputIdentity": shipping, "candidateShippingInputIdentity": shipping, "releaseFingerprintId": release, "toolingFingerprintId": tooling, "candidateIsCurrent": True, "sourceChangedSinceCandidate": False, "rebuildRequired": False})
    put(entries, "audit/CURRENT-HANDOFF.json", handoff)
    put(entries, "finalization-state.json", state)
    current = read_json(entries, "evidence/CURRENT-PROOF.json")
    current.update({"status": "PASS", "outcome": "PASS", "fullReleaseRunId": run_id, **tuple_value})
    put(entries, "evidence/CURRENT-PROOF.json", current)
    summary = read_json(entries, "evidence/FULLRELEASE-SUMMARY.json")
    summary.update({"status": "PASS", "diagnosticOnly": False, "historicalEvidenceOnly": False, "latestRunId": run_id, "candidateTuple": tuple_value})
    put(entries, "evidence/FULLRELEASE-SUMMARY.json", summary)
    l1_terminal = {"name": "DevFleet-E2E-Win11-01", "id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "state": "Off", "timestamp": "2026-08-30T00:00:02Z", "timestampUtc": "2026-08-30T00:00:02Z", "runId": run_id, "ownershipScope": "exact disposable"}
    put(entries, "evidence/l1-terminal-state.json", l1_terminal)
    nested_observation = {"schemaVersion": 1, "runId": run_id, "status": "ABSENT", "expectedName": "DevFleet-E2E-Linux-01", "present": False, "observedUtc": "2026-08-30T00:00:01Z", "verification": "Bounded Multipass JSON inventory inside exact L1", "exactMatchCount": 0, "inventoryCount": 0, "backendInventories": [], "candidate": tuple_value, "l1": {"name": "DevFleet-E2E-Win11-01", "id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2"}, "nestedScope": "inside the exact L1 guest session", "observer": "Get-DevFleetNestedL2State", "evidenceClass": "FullRelease run-bound nested observation"}
    put(entries, "evidence/current-fullrelease/nested-l2-terminal-observation.json", nested_observation)
    nested_hash = digest(entries["evidence/current-fullrelease/nested-l2-terminal-observation.json"])
    l2_terminal = {"schemaVersion": 2, "expectedName": "DevFleet-E2E-Linux-01", "status": "ABSENT", "present": False, "timestamp": "2026-08-30T00:00:01Z", "timestampUtc": "2026-08-30T00:00:01Z", "verificationMethod": nested_observation["verification"], "ownershipScope": "exact expected nested L2 name inside exact disposable L1", "nestedScope": nested_observation["nestedScope"], "backendInventories": [], "runId": run_id, "sourceRunId": run_id, "sourceEvidence": "nested-l2-terminal-observation.json", "sourceEvidenceSha256": nested_hash, "l1Name": "DevFleet-E2E-Win11-01", "l1Id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "candidate": tuple_value, "evidenceClass": nested_observation["evidenceClass"], "certifiedReleaseCleanup": False}
    put(entries, "evidence/l2-terminal-state.json", l2_terminal)
    cleanup = {"status": "PASS", "runId": run_id, "candidate": tuple_value, "l1": {"name": "DevFleet-E2E-Win11-01", "id": "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "state": "Off", "deleted": False}, "guest": {"runRootAbsent": True, "nestedAbsent": True, "foreignResourcesMutated": False}, "productionTouched": False, "physicalSurfaceTouched": False}
    put(entries, "evidence/current-fullrelease/final-cleanup.json", cleanup)
    cleanup_hash = digest(entries["evidence/current-fullrelease/final-cleanup.json"])
    l1_hash = digest(entries["evidence/l1-terminal-state.json"])
    l2_hash = digest(entries["evidence/l2-terminal-state.json"])
    entries["evidence/current-fullrelease/l1-terminal-state.json"] = entries["evidence/l1-terminal-state.json"]
    entries["evidence/current-fullrelease/l2-terminal-state.json"] = entries["evidence/l2-terminal-state.json"]
    l1_hash = digest(entries["evidence/current-fullrelease/l1-terminal-state.json"])
    l2_hash = digest(entries["evidence/current-fullrelease/l2-terminal-state.json"])
    put(entries, "evidence/current-fullrelease/post-cleanup-finalization.json", {"schemaVersion": 3, "status": "PASS", "runId": run_id, "cleanupConsumed": True, "reconcileAfterCleanup": True, "cleanupEvidenceHash": cleanup_hash, "terminalL1Hash": l1_hash, "terminalL2Hash": l2_hash, "nestedL2Observation": "nested-l2-terminal-observation.json", "nestedL2ObservationSha256": nested_hash, "terminalL1Timestamp": "2026-08-30T00:00:02Z", "terminalL2Timestamp": "2026-08-30T00:00:01Z", "expectedL2Name": "DevFleet-E2E-Linux-01", "candidate": tuple_value, "liveChecks": {"l1ExactOff": True, "l2ExactAbsent": True, "hostSameNameL2Absent": True, "foreignResourcesMutated": False}})
    full_hashes = {**tuple_value, **{row["name"]: row["sha256"] for row in release_record["artifacts"]}}
    put(entries, "evidence/current-fullrelease/run-state.json", {"runId": run_id, "mode": "FullRelease", "finalStatus": "PASS", "candidateHashes": full_hashes, "completedPhases": sorted(REQUIRED_FULLRELEASE_PHASES)})
    real_binding_name = "evidence/current-fullrelease/real-use-acceptance-binding.json"
    real_prepare_name = "evidence/current-fullrelease/real-use-acceptance-prepare.json"
    put(entries, real_binding_name, {"schemaVersion": 1, "contract": "devfleet-real-use-acceptance-v1", "runId": run_id, "phaseId": "REAL-USE-ACCEPTANCE", "precedingPhase": "SURROGATE-DISPOSABLE", "candidate": tuple_value})
    put(entries, real_prepare_name, {"schemaVersion": 1, "contract": "devfleet-real-use-acceptance-v1", "status": "PREPARED", "stage": "prepare", "phaseId": "REAL-USE-ACCEPTANCE", "runId": run_id, "candidate": tuple_value})
    real_binding_hash = digest(entries[real_binding_name])
    real_prepare_hash = digest(entries[real_prepare_name])
    real_report = {"schemaVersion": 1, "contract": "devfleet-real-use-acceptance-v1", "status": "PASS", "stage": "resume", "phaseId": "REAL-USE-ACCEPTANCE", "runId": run_id, "candidate": tuple_value, "journeys": [{"id": name, "status": "PASS", "assertions": {"real": True, "endToEnd": True}} for name in ("U01", "U02", "U03", "U04", "U05")], "cleanup": {"status": "PASS", "ownedOnly": True, "errors": []}, "failure": None, "cleanupFailure": None}
    put(entries, "evidence/current-fullrelease/real-use-acceptance-report.json", real_report)
    real_hash = digest(entries["evidence/current-fullrelease/real-use-acceptance-report.json"])
    put(entries, "evidence/current-fullrelease/real-use-acceptance-evidence.json", {"contract": "devfleet-real-use-acceptance-evidence-v1", "status": "PASS", "runId": run_id, "credentialsStoredInEvidence": False, "internalPromotionAllowed": False, "journeys": [{"id": name, "status": "PASS"} for name in ("U01", "U02", "U03", "U04", "U05")], "evidence": {"binding": {"sha256": real_binding_hash}, "prepare": {"sha256": real_prepare_hash}, "report": {"sha256": real_hash}}})
    records = [{"id": phase, "status": "PASS", "runId": run_id} for phase in sorted(REQUIRED_FULLRELEASE_PHASES)]
    for record in records:
        if record["id"] == "HOST-SAFETY":
            record["evidence"] = {"startSafe": True, "rawHostSafetyStartSafe": True, "effectiveE2EStartAuthorized": True, "ramPressureOverrideAuthorized": False}
        elif record["id"] == "REAL-USE-ACCEPTANCE":
            record["evidence"] = {"executor": {"status": "REAL E2E PASS", "phase": "REAL-USE-ACCEPTANCE", "contract": "devfleet-real-use-acceptance-phase-v1", "candidate": tuple_value, "credentialsStoredInEvidence": False, "internalPromotionAllowed": False, "evidence": {"bindingPath": "C:/fixture/real-use-acceptance-binding.json", "bindingSha256": real_binding_hash, "preparePath": "C:/fixture/real-use-acceptance-prepare.json", "prepareSha256": real_prepare_hash, "reportPath": "C:/fixture/real-use-acceptance-report.json", "reportSha256": real_hash}}}
        elif record["id"] == "RECONCILE":
            record["evidence"] = {"executor": {"status": "REAL E2E PASS", "phase": "RECONCILE", "maintenance": "5/5", "candidate": tuple_value}}
    put(entries, "evidence/current-fullrelease/fullrelease-phase-records.json", records)
    entries["evidence/current-proof/product-lifecycle-progress.jsonl"] = b'{"heartbeat":true}\n'
    source_files = {"proofScriptSha256": "run-exact-candidate-proof.ps1", "invokeRealProductPhaseSha256": "Invoke-RealProductPhase.psm1", "invokeWpfUiAutomationSha256": "Invoke-WpfUiAutomation.ps1", "wpfLaunchContractSha256": "WpfLaunchContract.psm1"}
    source_bytes = {key: entries[f"release-tooling/proof-entrypoints/{name}"] for key, name in source_files.items()}
    proof_tuple = {"repositoryHead": head, "candidateCommit": head, "shippingInputIdentity": shipping, "releaseFingerprint": release, "toolingFingerprint": tooling}
    artifact_hashes = {entry["name"]: entry["sha256"] for entry in read_json(entries, "outputs/release-fingerprint.json")["artifacts"]}
    # Replace only this temporary fixture's proof namespace; the archive and
    # its historical evidence remain immutable on disk.
    for name in list(entries):
        if name.startswith("evidence/proof-runs/"):
            del entries[name]
    proof_ids = []
    for index in (1, 2):
        with tempfile.TemporaryDirectory() as directory:
            run, *_ = native_proof_fixture(Path(directory), laptop=(index == 2), index=index, config_bytes=entries["source/config/devfleet.config.json"], expected=proof_tuple, source_bytes=source_bytes, artifacts=artifact_hashes)
            proof_ids.append(run.name)
            for path in run.iterdir():
                entries[f"evidence/proof-runs/{run.name}/{path.name}"] = path.read_bytes()

    authority = read_json(entries, "evidence/CURRENT-RELEASE-AUTHORITY.json")
    authority["proofs"] = {"passing": 2, "required": 2, "status": "2 / 2 PASS", "runs": [{"runId": run_id_value, "status": "PASS"} for run_id_value in proof_ids]}
    put(entries, "evidence/CURRENT-RELEASE-AUTHORITY.json", authority)

    standard_id = "standard-token-synthetic-current"
    raw_name = f"evidence/standard-token/{standard_id}/installer-self-test-raw.txt"
    canonical_name = f"evidence/standard-token/{standard_id}/standard-token-evidence.json"
    entries[raw_name] = f"PASS\npayload={artifact_hashes['tar']}\n".encode()
    standard = {"schemaVersion": 1, "runId": standard_id, "status": "PASS", "standardNonAdministratorToken": True, "runDirectory": f"evidence/standard-token/{standard_id}", "rawReportPath": raw_name, "canonicalEvidencePath": canonical_name, "generatedAtUtc": "2026-09-16T00:00:00Z", "candidateBuildCommit": head, **tuple_value, "exe": next(row for row in release_record["artifacts"] if row["name"] == "exe"), "tar": next(row for row in release_record["artifacts"] if row["name"] == "tar"), "runner": {"path": "automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1", "sha256": digest(entries["automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1"])}, "token": {"standardNonAdministratorToken": True, "isAdministratorMember": False, "isAdministratorEnabled": False, "isElevated": False, "integrityLevel": "Medium"}, "exitCode": 0, "reportSha256": digest(entries[raw_name]), "requiredChecks": {name: True for name in ("pass", "payloadExtraction", "bootstrapEntrypoint", "parameterContract", "embeddedTarCount", "factoryResetBackupGate", "planSafety", "devfleetVersion", "installerVersion", "payloadSha")}, "residualSelfTestScratchCount": 0}
    put(entries, canonical_name, standard)
    entries["evidence/CURRENT-STANDARD-TOKEN.json"] = entries[canonical_name]

    full_bindings = {
        "runStateSha256": digest(entries["evidence/current-fullrelease/run-state.json"]),
        "phaseRecordsSha256": digest(entries["evidence/current-fullrelease/fullrelease-phase-records.json"]),
        "realUseBindingSha256": real_binding_hash,
        "realUsePrepareSha256": real_prepare_hash,
        "realUseReportSha256": real_hash,
        "realUseSummarySha256": digest(entries["evidence/current-fullrelease/real-use-acceptance-evidence.json"]),
        "cleanupSha256": digest(entries["evidence/current-fullrelease/final-cleanup.json"]),
        "postCleanupSha256": digest(entries["evidence/current-fullrelease/post-cleanup-finalization.json"]),
        "l1Sha256": l1_hash,
        "l2Sha256": l2_hash,
    }
    audit_id = "release-audit-synthetic-current"
    audit_prefix = f"evidence/release-audits/{audit_id}"
    report_name = f"{audit_prefix}/ai-audit-bundle-self-test.json"
    audit_manifest_name = f"{audit_prefix}/release-audit.manifest.json"
    audit_validation_name = f"{audit_prefix}/pre-acceptance-validation.json"
    synthetic_archive_hash = "a" * 64
    audit_report = {"status": "COMPLETE_FOR_AI_AUDIT", "bundleMode": "release", "releaseEligible": True, "internalPromotionAllowed": False, "publicPromotionAllowed": False, "publicPublisherTrust": False, "modeVerification": "PASS", "coherenceVerification": "PASS", "secretScan": "PASS", "archiveSha256": synthetic_archive_hash, "archiveBytes": 1234, "candidateTuple": tuple_value, "fullReleaseRunId": run_id, "standardTokenRunId": standard_id, "proofRunIds": proof_ids, "expectedSourceCount": 10, "includedSourceCount": 10, "checks": {"pythonCompile": "PASS", "powershellParse": "PASS"}}
    put(entries, report_name, audit_report)
    put(entries, audit_manifest_name, {"sha256": synthetic_archive_hash, "bytes": 1234, "selfTest": "PASS", "expectedSourceCount": 10, "includedSourceCount": 10})
    put(entries, audit_validation_name, {"status": "PASS", "bundleMode": "pre-acceptance", "releaseEligible": False, "internalPromotionAllowed": False, "publicPromotionAllowed": False, "candidateTuple": tuple_value, "fullReleaseRunId": run_id, "standardTokenRunId": standard_id, "proofRunIds": proof_ids})
    audit_pointer = {"schemaVersion": 1, "contract": "devfleet-pre-acceptance-release-audit-v1", "runId": audit_id, "status": "PASS", "bundleMode": "release", "releaseEligible": False, "internalPromotionAllowed": False, "publicPromotionAllowed": False, "publicPublisherTrust": False, "candidate": tuple_value, "fullReleaseRunId": run_id, "standardTokenRunId": standard_id, "proofRunIds": proof_ids, "inputs": {"fullReleaseRunStateSha256": full_bindings["runStateSha256"], "fullReleasePhaseRecordsSha256": full_bindings["phaseRecordsSha256"], "realUseBindingSha256": real_binding_hash, "realUsePrepareSha256": real_prepare_hash, "realUseReportSha256": real_hash, "realUseSummarySha256": full_bindings["realUseSummarySha256"], "cleanupSha256": full_bindings["cleanupSha256"], "postCleanupSha256": full_bindings["postCleanupSha256"], "terminalL1Sha256": l1_hash, "terminalL2Sha256": l2_hash, "standardTokenPointerSha256": digest(entries["evidence/CURRENT-STANDARD-TOKEN.json"]), "proofRunIds": proof_ids}, "evidence": {"archive": {"workspacePath": f"audit/release-audits/{audit_id}/release-audit.zip", "bundlePath": None, "bytes": 1234, "sha256": synthetic_archive_hash}, "report": {"workspacePath": f"audit/release-audits/{audit_id}/ai-audit-bundle-self-test.json", "bundlePath": report_name, "bytes": len(entries[report_name]), "sha256": digest(entries[report_name])}, "manifest": {"workspacePath": f"audit/release-audits/{audit_id}/release-audit.manifest.json", "bundlePath": audit_manifest_name, "bytes": len(entries[audit_manifest_name]), "sha256": digest(entries[audit_manifest_name])}, "releaseValidation": {"workspacePath": f"audit/release-audits/{audit_id}/pre-acceptance-validation.json", "bundlePath": audit_validation_name, "bytes": len(entries[audit_validation_name]), "sha256": digest(entries[audit_validation_name])}}, "checks": {"cleanExtraction": "PASS", "secrets": "PASS", "coherence": "PASS", "sourceCount": "PASS", "releaseValidation": "PASS"}, "gates": {"candidate": "PASS", "proofs": "2/2 PASS", "fullRelease": "PASS", "realUseAcceptance": "U01-U05 PASS", "maintenance": "5/5 PASS", "standardToken": "PASS", "reconcile": "PASS", "cleanup": "PASS", "l1": "OFF", "l2": "ABSENT", "releaseAudit": "PASS"}}
    put(entries, "evidence/CURRENT-RELEASE-AUDIT.json", audit_pointer)

    binding_values = {"standardTokenPointerSha256": digest(entries["evidence/CURRENT-STANDARD-TOKEN.json"]), "standardTokenCanonicalSha256": digest(entries[canonical_name]), "standardTokenRawReportSha256": digest(entries[raw_name]), "fullReleaseRunStateSha256": full_bindings["runStateSha256"], "fullReleasePhaseRecordsSha256": full_bindings["phaseRecordsSha256"], "realUseBindingSha256": real_binding_hash, "realUsePrepareSha256": real_prepare_hash, "realUseReportSha256": real_hash, "realUseSummarySha256": full_bindings["realUseSummarySha256"], "cleanupSha256": full_bindings["cleanupSha256"], "postCleanupSha256": full_bindings["postCleanupSha256"], "terminalL1Sha256": l1_hash, "terminalL2Sha256": l2_hash, "releaseAuditPointerSha256": digest(entries["evidence/CURRENT-RELEASE-AUDIT.json"]), "releaseAuditArchiveSha256": synthetic_archive_hash, "releaseAuditReportSha256": digest(entries[report_name]), "releaseAuditManifestSha256": digest(entries[audit_manifest_name]), "releaseAuditValidationSha256": digest(entries[audit_validation_name])}
    final = {"schemaVersion": 1, "contract": "devfleet-internal-final-acceptance-v1", "status": "PASS", "releaseEligible": True, "internalPromotionAllowed": True, "publicPromotionAllowed": False, "publicPublisherTrust": False, "candidate": {**tuple_value, "artifacts": {row["name"]: {"sha256": row["sha256"], "bytes": row["bytes"]} for row in release_record["artifacts"]}, "authenticode": {"status": "PASS", "signatureStatus": "Valid", "signerThumbprint": "DE42CD7369A01E9357BDA13597C0173E5E703E9D", "signerSubject": "CN=DevFleet Private Personal Code Signing", "codeSigningEkuVerified": True, "rsaBits": 3072, "exactCertificateMatch": True, "privateKeyExported": False}}, "proofRunIds": proof_ids, "fullReleaseRunId": run_id, "standardTokenRunId": standard_id, "releaseAuditRunId": audit_id, "bindings": binding_values, "gates": audit_pointer["gates"], "safety": {"f005Attempted": False, "formatterOnlyAuditCleanupPerformed": False, "f005StructuralRefactoringPerformed": False, "protectedProductionMutated": False, "hostRebooted": False, "amdRadeonTouched": False, "biosUefiTouched": False, "mulattoTechSurfaceTouched": False, "githubPushed": False, "privateSigningKeyExported": False, "ramPressureOverrideUsed": False, "productionUnchanged": True, "disposableLabOnly": True}}
    put(entries, "evidence/FINAL-ACCEPTANCE.json", final)
    return entries


def write_archive(entries: dict[str, bytes], path: Path) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)


def must_fail(entries: dict[str, bytes], mutate, label: str, mode: str = "final") -> None:
    changed = copy.deepcopy(entries)
    mutate(changed)
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "synthetic.zip"
        write_archive(changed, path)
        try:
            validate(path, mode)
        except ValueError:
            return
    raise AssertionError(f"negative bundle was accepted: {label}")


def main() -> None:
    # LATEST is the generic current-candidate diagnostic baseline. Historical
    # source checks have a separate deterministic fixture, independent of the
    # archive's optional historical pointer and old hard-coded candidate ID.
    diagnostic_result = validate(ARCHIVE, "diagnostic")
    assert diagnostic_result.get("status") == "PASS_WITH_BLOCKER"
    assert diagnostic_result.get("releaseEligible") is False
    # A pending diagnostic may truthfully have no current proof after rebind.
    # Compare with its actual pointer; final-mode acceptance remains strict.
    with zipfile.ZipFile(ARCHIVE) as archive:
        diagnostic_proof = json.loads(archive.read("evidence/CURRENT-PROOF.json").decode("utf-8-sig"))
    assert diagnostic_proof.get("outcome") in {"PASS", "NOT_OBSERVED"}
    assert diagnostic_result.get("proofOutcome") == diagnostic_proof["outcome"]
    assert diagnostic_result.get("candidateIsCurrent") is True
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        relative = "release-tooling/historical/fixture-proof/proof-start.json"
        historical_root = (root / relative).parent
        historical_root.mkdir(parents=True)
        source_map = {"proofScriptSha256": "run-exact-candidate-proof.ps1", "invokeRealProductPhaseSha256": "Invoke-RealProductPhase.psm1", "invokeWpfUiAutomationSha256": "Invoke-WpfUiAutomation.ps1"}
        provenance = {}
        for key, name in source_map.items():
            content = name.encode()
            (historical_root / name).write_bytes(content)
            provenance[key] = digest(content)
        (root / relative).write_text(json.dumps({"provenance": provenance}), encoding="utf-8")
        current = {"proofStartHistoricalPath": relative}
        validate_historical_proof_sources(root, current)
        source_path = historical_root / "run-exact-candidate-proof.ps1"
        original = source_path.read_bytes()
        for mutation in ("missing", "wrong"):
            if mutation == "missing":
                source_path.unlink()
            else:
                source_path.write_bytes(b"wrong historical bytes")
            try:
                validate_historical_proof_sources(root, current)
            except ValueError:
                pass
            else:
                raise AssertionError(f"{mutation} historical source was accepted")
            source_path.write_bytes(original)
    entries = final_entries()
    full_state = read_json(entries, "evidence/current-fullrelease/run-state.json")
    full_run_id = str(full_state["runId"])
    terminal_l1 = read_json(entries, "evidence/current-fullrelease/l1-terminal-state.json")
    terminal_l2 = read_json(entries, "evidence/current-fullrelease/l2-terminal-state.json")
    candidate_tuple = {key: str(full_state["candidateHashes"][key]) for key in ("repositoryHead", "candidateCommit", "shippingInputIdentity", "releaseFingerprintId", "toolingFingerprintId")}
    nested_validation_cases = 3
    nested_symlink_skipped = []
    with tempfile.TemporaryDirectory() as nested_directory:
        nested_root = Path(nested_directory)
        for name in ("nested-l2-terminal-observation.json",):
            (nested_root / name).write_bytes(entries[f"evidence/current-fullrelease/{name}"])
        _validate_nested_l2_terminal(nested_root, terminal_l2, terminal_l1, candidate_tuple, full_run_id)
        legacy_l2 = {"expectedName": "DevFleet-E2E-Linux-01", "status": "ABSENT", "present": False, "timestampUtc": "2026-08-30T00:00:01Z", "verificationMethod": "Get-VM -Name exact returned no VM"}
        try:
            _validate_nested_l2_terminal(nested_root, legacy_l2, terminal_l1, candidate_tuple, full_run_id)
        except ValueError:
            pass
        else:
            raise AssertionError("host-only L2 absence passed the nested terminal validator")
        nested_path = nested_root / "nested-l2-terminal-observation.json"
        valid_nested_bytes = nested_path.read_bytes()
        valid_nested = json.loads(valid_nested_bytes)
        for label, field, bad_value, message in (
            ("boolean exact-match count", "exactMatchCount", False, "zero exact matches"),
            ("boolean inventory count", "inventoryCount", True, "inventory completeness"),
        ):
            bad_nested = {**valid_nested, field: bad_value}
            bad_bytes = json.dumps(bad_nested).encode()
            nested_path.write_bytes(bad_bytes)
            bad_terminal = {**terminal_l2, "sourceEvidenceSha256": digest(bad_bytes)}
            try:
                _validate_nested_l2_terminal(nested_root, bad_terminal, terminal_l1, candidate_tuple, full_run_id)
            except ValueError as exc:
                if message not in str(exc):
                    raise AssertionError(f"{label} rejected for the wrong reason: {exc}") from exc
            else:
                raise AssertionError(f"{label} was accepted as exact nested terminal evidence")
        backend_verification = "Multipass CLI absent; complete read-only inventories from every supported in-L1 virtualization backend"
        duplicate_backend = {
            **valid_nested,
            "verification": backend_verification,
            "inventoryCount": 2,
            "backendInventories": [
                {"provider": "Hyper-V", "status": "PASS", "names": ["foreign-instance", "foreign-instance"], "verification": "bounded Hyper-V inventory"},
                {"provider": "VirtualBox", "status": "PASS", "names": [], "verification": "bounded VirtualBox inventory"},
            ],
        }
        duplicate_bytes = json.dumps(duplicate_backend).encode()
        nested_path.write_bytes(duplicate_bytes)
        duplicate_terminal = {**terminal_l2, "verificationMethod": backend_verification, "sourceEvidenceSha256": digest(duplicate_bytes)}
        try:
            _validate_nested_l2_terminal(nested_root, duplicate_terminal, terminal_l1, candidate_tuple, full_run_id)
        except ValueError as exc:
            if "duplicate instance name" not in str(exc):
                raise AssertionError(f"duplicate backend names were rejected for the wrong reason: {exc}") from exc
        else:
            raise AssertionError("duplicate nested backend names were accepted as complete absence evidence")
        nested_validation_cases += 1
        nested_path.write_bytes(valid_nested_bytes)
        with tempfile.TemporaryDirectory() as external_directory:
            outside = Path(external_directory) / "outside-nested-evidence.json"
            outside.write_bytes(valid_nested_bytes)
            nested_path.unlink()
            try:
                nested_path.symlink_to(outside)
            except (OSError, NotImplementedError) as exc:
                nested_path.write_bytes(valid_nested_bytes)
                nested_symlink_skipped.append(f"source symlink rejection ({type(exc).__name__})")
            else:
                try:
                    try:
                        _validate_nested_l2_terminal(nested_root, terminal_l2, terminal_l1, candidate_tuple, full_run_id)
                    except ValueError as exc:
                        if "reparse or symlink escape" not in str(exc):
                            raise AssertionError(f"source symlink rejected for the wrong reason: {exc}") from exc
                    else:
                        raise AssertionError("nested source symlink outside the FullRelease run root was accepted")
                    nested_validation_cases += 1
                finally:
                    nested_path.unlink(missing_ok=True)
                    nested_path.write_bytes(valid_nested_bytes)
    with tempfile.TemporaryDirectory() as directory:
        good = Path(directory) / "good.zip"
        write_archive(entries, good)
        validate(good, "final")
    must_fail(
        entries,
        lambda e: put(
            e,
            "evidence/current-fullrelease/run-state.json",
            {**read_json(e, "evidence/current-fullrelease/run-state.json"), "finalStatus": "BLOCKED"},
        ),
        "incomplete FullRelease remains pending and cannot validate",
    )
    must_fail(entries, lambda e: [e.update({f"evidence/proof-runs/e2e-proof2-synthetic/proof-start.json": json.dumps({**read_json(e, "evidence/proof-runs/e2e-proof2-synthetic/proof-start.json"), "provenance": {**read_json(e, "evidence/proof-runs/e2e-proof2-synthetic/proof-start.json")["provenance"], "transactionId": "transaction-1", "checkpointLineageId": "lineage-1"}}).encode()})], "reused transaction/lineage")
    must_fail(entries, lambda e: [e.update({"evidence/proof-runs/e2e-proof2-synthetic/proof-final.json": json.dumps({"runId": "wrong-run", "status": "PASS"}).encode()})], "mixed RunId")
    must_fail(entries, lambda e: [e.update({"evidence/current-fullrelease/post-cleanup-finalization.json": json.dumps({"status": "PASS", "runId": "FullRelease-synthetic-current", "cleanupConsumed": True, "reconcileAfterCleanup": True}).encode()})], "absent liveChecks")
    must_fail(entries, lambda e: [e.update({"evidence/current-fullrelease/post-cleanup-finalization.json": json.dumps({**read_json(e, "evidence/current-fullrelease/post-cleanup-finalization.json"), "liveChecks": {"l1ExactOff": False, "l2ExactAbsent": True}}).encode()})], "false liveChecks")
    must_fail(entries, lambda e: [e.update({"evidence/current-fullrelease/final-cleanup.json": b"{\"status\":\"tampered\"}"})], "cleanup hash mismatch")
    must_fail(entries, lambda e: [e.update({"evidence/l1-terminal-state.json": b"{\"state\":\"Running\"}"})], "terminal hash mismatch")
    must_fail(entries, lambda e: e.pop("evidence/FINAL-ACCEPTANCE.json"), "omitted FINAL-ACCEPTANCE")
    raw_path = read_json(entries, "evidence/CURRENT-STANDARD-TOKEN.json")["rawReportPath"]
    must_fail(entries, lambda e: e.update({raw_path: e[raw_path] + b"tamper\n"}), "tampered immutable standard-token raw report")
    must_fail(entries, lambda e: put(e, "evidence/FINAL-ACCEPTANCE.json", {**read_json(e, "evidence/FINAL-ACCEPTANCE.json"), "fullReleaseRunId": "FullRelease-stale"}), "stale FINAL-ACCEPTANCE tuple/lineage")
    audit_report_path = read_json(entries, "evidence/CURRENT-RELEASE-AUDIT.json")["evidence"]["report"]["bundlePath"]
    must_fail(entries, lambda e: e.update({audit_report_path: e[audit_report_path] + b"\n"}), "tampered immutable release-audit report")
    pre_entries = copy.deepcopy(entries)
    pre_entries.pop("evidence/FINAL-ACCEPTANCE.json")
    pre_entries.pop("evidence/CURRENT-RELEASE-AUDIT.json")
    for name in list(pre_entries):
        if name.startswith("evidence/release-audits/"):
            del pre_entries[name]
    with tempfile.TemporaryDirectory() as directory:
        pre_good = Path(directory) / "pre-good.zip"
        write_archive(pre_entries, pre_good)
        pre_result = validate(pre_good, "pre-acceptance")
        assert pre_result["status"] == "PASS" and pre_result["releaseEligible"] is False
    must_fail(pre_entries, lambda e: e.update({"evidence/FINAL-ACCEPTANCE.json": entries["evidence/FINAL-ACCEPTANCE.json"]}), "pre-acceptance FINAL cycle", "pre-acceptance")
    print(json.dumps({"status": "PASS", "cases": 13 + nested_validation_cases, "skipped": nested_symlink_skipped}))


if __name__ == "__main__":
    main()

```


## FILE: tools/validate_audit_coherence.py

SHA256: 13f4bfa1db5cedd99da67b211c0d18e3330d19e1291e8e027aa4152aff812b90 | Bytes: 18596 | Git mode: 100644

```
"""Validate current release-tooling authorities without rewriting identity."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any, Iterable

CURRENT_AUTHORITIES = (
    "AUDIT-MANIFEST.json", "CURRENT-CANDIDATE.json", "finalization-state.json",
    "outputs/final-artifact-hashes.json", "evidence/CURRENT-STATUS.json",
    "evidence/CURRENT-GATES.json", "evidence/CURRENT-PROOF.json",
    "evidence/FULLRELEASE-SUMMARY.json", "audit/CURRENT-HANDOFF.json",
    "evidence/CURRENT-HANDOFF.json",
)
REQUIRED_SOURCE_PROOF = "release-tooling/proof-entrypoints/run-exact-candidate-proof.ps1"
FAILED_ATTEMPT_SNAPSHOT = "audit/luna-high-failed-attempt-freeze-20260831T002237512571Z.json"
FAILED_ATTEMPT_SNAPSHOT_SHA256 = "ac37997945b6fa5ae9326b083ee730494b2c0c2e60d4809e7b49fc9707c0caac"
FAILED_ATTEMPT_BLOCKER = "REPLACEMENT_CANDIDATE_BINDING_MISMATCH"


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def walk(value: Any, location: str) -> Iterable[tuple[str, dict[str, Any]]]:
    if isinstance(value, dict):
        yield location, value
        for key, child in value.items():
            yield from walk(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk(child, f"{location}[{index}]")


def bool_value(value: Any, location: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{location} must be a JSON boolean")
    return value


def git_head(root: Path) -> str:
    try:
        return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def validate_failed_attempt_authority(root: Path, state: dict[str, Any]) -> dict[str, Any] | None:
    snapshot_path = root / Path(*FAILED_ATTEMPT_SNAPSHOT.split("/"))
    if not snapshot_path.is_file():
        return None
    if sha256(snapshot_path) != FAILED_ATTEMPT_SNAPSHOT_SHA256:
        raise ValueError("failed replacement-attempt snapshot is missing or hash-mismatched")
    snapshot = load(snapshot_path)
    if snapshot.get("immutableSnapshot") is not True or snapshot.get("freezeType") != "LUNA_HIGH_FAILED_ATTEMPT_EVIDENCE_FREEZE":
        raise ValueError("failed replacement-attempt snapshot is not immutable evidence")
    shipping = snapshot.get("shippingIdentity") if isinstance(snapshot.get("shippingIdentity"), dict) else {}
    archive = shipping.get("gitArchive") if isinstance(shipping.get("gitArchive"), dict) else {}
    live = shipping.get("buildTimeLive") if isinstance(shipping.get("buildTimeLive"), dict) else {}
    if archive.get("rowCount") != 730 or live.get("rowCount") != 730 or archive.get("identity") != "6e0bac4b4eebc83cdcd9eddda2008607ba15c8835e5c72a931792f5b83c653f4" or live.get("identity") != "3a65fd54d70fe05565ac3a32f73100ca2c81a77a4008feb361f99f229f025f8a":
        raise ValueError("failed replacement-attempt snapshot shipping identity is invalid")
    diff = shipping.get("normalizedRowDiff") if isinstance(shipping.get("normalizedRowDiff"), dict) else {}
    rows = diff.get("rows")
    if diff.get("rowCount") != 28 or diff.get("crlfOnlyRows") != 25 or diff.get("exactChangedRows") != 3 or not isinstance(rows, list) or len(rows) != 28:
        raise ValueError("failed replacement-attempt snapshot row partition is invalid")
    generated = {"source/CHECKSUMS.sha256", "installer-source/DevFleet.Setup/PayloadManifest.cs", "installer-source/INSTALLER-BUILD-MANIFEST.json"}
    if {f"{r.get('root')}/{r.get('path')}" for r in rows if isinstance(r, dict) and r.get("comparison") == "CONTENT_OR_GENERATED_CHANGE"} != generated or sum(1 for r in rows if isinstance(r, dict) and r.get("comparison") == "CRLF_ONLY_NORMALIZED_EQUAL") != 25:
        raise ValueError("failed replacement-attempt snapshot generated/CRLF partition is invalid")
    candidate_commit = str(
        state.get("candidate_git_commit")
        or state.get("candidateGitCommit")
        or state.get("candidateCommit")
        or ""
    ).lower()
    failed_attempt_bound = (
        candidate_commit == "21752fc0e50978183322204c523b40947d073aa0"
        or str(state.get("blocker_code") or "") == FAILED_ATTEMPT_BLOCKER
    )
    if not failed_attempt_bound:
        # The immutable failed-attempt snapshot is retained for historical
        # review.  Once current authority has advanced to another candidate,
        # it must not force the current state back to the old blocked tuple.
        return {
            "historicalFailedAttempt": True,
            "historicalFailedAttemptPath": FAILED_ATTEMPT_SNAPSHOT,
            "releaseEligible": False,
        }
    attempt = state.get("failed_replacement_attempt")
    if not isinstance(attempt, dict) or attempt.get("snapshotPath") != FAILED_ATTEMPT_SNAPSHOT or attempt.get("snapshotSha256") != FAILED_ATTEMPT_SNAPSHOT_SHA256 or attempt.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or attempt.get("artifactTupleValid") is not True or attempt.get("artifactTupleMatchesCandidate") is not False:
        raise ValueError("current authority does not bind the failed replacement attempt")
    if (state.get("candidate_is_current"), state.get("source_changed_since_candidate"), state.get("rebuild_required"), state.get("artifact_tuple_matches_candidate"), state.get("full_release_passed"), state.get("internal_promotion_allowed"), state.get("public_promotion_allowed")) != (False, True, True, False, False, False, False):
        raise ValueError("failed replacement-attempt authority flags are not truthful")
    if state.get("status") != "BLOCKED — USER ACTION REQUIRED" or state.get("blocker_code") != FAILED_ATTEMPT_BLOCKER:
        raise ValueError("failed replacement-attempt status is not user-action blocked")
    return {"status": "PASS_WITH_BLOCKER", "blockerCode": FAILED_ATTEMPT_BLOCKER, "releaseEligible": False}


def validate(root: Path) -> dict[str, Any]:
    root = root.resolve()
    state_path = root / "finalization-state.json"
    manifest_path = root / "outputs" / "final-artifact-hashes.json"
    if not state_path.is_file() or not manifest_path.is_file():
        raise ValueError("Current finalization state and artifact manifest are required")
    state, manife