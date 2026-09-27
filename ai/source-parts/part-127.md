# DevFleet source part 127

Full-source UTF-8 byte interval [5859000, 5888497); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: afb09d2948ef4d857c1465c3c89fa33d692392d16607f754aba2fefe1c72ddea

<!-- BEGIN SOURCE SLICE -->
, str(closure["fullReleaseRunId"]), layout, require_archive=(layout == "workspace"), closure=closure)
    if final.get("releaseAuditRunId") != release_audit["runId"]:
        raise ValueError("FINAL-ACCEPTANCE release-audit lineage is stale or spliced")
    bindings = final.get("bindings")
    if not isinstance(bindings, dict):
        raise ValueError("FINAL-ACCEPTANCE evidence bindings are missing")
    expected_hashes = {
        "standardTokenPointerSha256": closure["standardToken"]["pointerSha256"],
        "standardTokenCanonicalSha256": closure["standardToken"]["canonicalSha256"],
        "standardTokenRawReportSha256": closure["standardToken"]["rawReportSha256"],
        "fullReleaseRunStateSha256": closure["fullRelease"]["runStateSha256"],
        "fullReleasePhaseRecordsSha256": closure["fullRelease"]["phaseRecordsSha256"],
        "realUseBindingSha256": closure["fullRelease"]["realUseBindingSha256"],
        "realUsePrepareSha256": closure["fullRelease"]["realUsePrepareSha256"],
        "realUseReportSha256": closure["fullRelease"]["realUseReportSha256"],
        "realUseSummarySha256": closure["fullRelease"]["realUseSummarySha256"],
        "cleanupSha256": closure["fullRelease"]["cleanupSha256"],
        "postCleanupSha256": closure["fullRelease"]["postCleanupSha256"],
        "terminalL1Sha256": closure["fullRelease"]["l1Sha256"],
        "terminalL2Sha256": closure["fullRelease"]["l2Sha256"],
        "releaseAuditPointerSha256": release_audit["pointerSha256"],
        "releaseAuditArchiveSha256": release_audit["archiveSha256"],
        "releaseAuditReportSha256": release_audit["reportSha256"],
        "releaseAuditManifestSha256": release_audit["manifestSha256"],
        "releaseAuditValidationSha256": release_audit["releaseValidationSha256"],
    }
    if set(bindings) != set(expected_hashes) or any(str(bindings.get(key) or "").lower() != str(value).lower() for key, value in expected_hashes.items()):
        raise ValueError("FINAL-ACCEPTANCE evidence hash closure is incomplete or changed")
    safety = final.get("safety")
    required_false = ("f005Attempted", "formatterOnlyAuditCleanupPerformed", "f005StructuralRefactoringPerformed", "protectedProductionMutated", "hostRebooted", "amdRadeonTouched", "biosUefiTouched", "mulattoTechSurfaceTouched", "githubPushed", "privateSigningKeyExported", "ramPressureOverrideUsed")
    if not isinstance(safety, dict) or any(safety.get(key) is not False for key in required_false) or safety.get("productionUnchanged") is not True or safety.get("disposableLabOnly") is not True:
        raise ValueError("FINAL-ACCEPTANCE safety/F-005 assertions are missing or unsafe")
    gates = final.get("gates")
    required_gates = {"candidate": "PASS", "proofs": "2/2 PASS", "fullRelease": "PASS", "realUseAcceptance": "U01-U05 PASS", "maintenance": "5/5 PASS", "standardToken": "PASS", "reconcile": "PASS", "cleanup": "PASS", "l1": "OFF", "l2": "ABSENT", "releaseAudit": "PASS"}
    if not isinstance(gates, dict) or set(gates) != set(required_gates) or any(gates.get(key) != value for key, value in required_gates.items()):
        raise ValueError("FINAL-ACCEPTANCE gate closure is incomplete")
    return {"status": "PASS", "releaseEligible": True, "internalPromotionAllowed": True, "publicPromotionAllowed": False, "candidateTuple": expected, "proofRunIds": closure["proofRunIds"], "fullReleaseRunId": closure["fullReleaseRunId"], "standardTokenRunId": closure["standardToken"]["runId"], "releaseAuditRunId": release_audit["runId"], "finalAcceptanceSha256": sha(final_path)}


def validate_historical_proof_sources(root: Path, current: dict) -> None:
    historical_start = str(current.get("proofStartHistoricalPath") or "")
    parts = PurePosixPath(historical_start.replace("\\", "/"))
    if len(parts.parts) != 4 or parts.parts[:2] != ("release-tooling", "historical") or parts.name != "proof-start.json" or parts.is_absolute() or ".." in parts.parts or not (root / historical_start).is_file():
        raise ValueError("diagnostic bundle is missing the exact historical proof-start archive path")
    start = read_json(root / historical_start)
    provenance = start.get("provenance") if isinstance(start.get("provenance"), dict) else {}
    historical_root = (root / historical_start).parent
    historical_sources = {
        "proofScriptSha256": historical_root / "run-exact-candidate-proof.ps1",
        "invokeRealProductPhaseSha256": historical_root / "Invoke-RealProductPhase.psm1",
        "invokeWpfUiAutomationSha256": historical_root / "Invoke-WpfUiAutomation.ps1",
    }
    for key, path in historical_sources.items():
        expected = str(provenance.get(key) or "").lower()
        if not re.fullmatch(r"[0-9a-f]{64}", expected) or not path.is_file() or sha(path) != expected:
            raise ValueError(f"historical proof-start source cannot be verified: {key}")


def _validate_diagnostic(root: Path, names: set[str]) -> dict[str, object]:
    candidate_record = read_json(root / "CURRENT-CANDIDATE.json")
    manifest = read_json(root / "AUDIT-MANIFEST.json")
    if FAILED_ATTEMPT_SNAPSHOT in names:
        missing = sorted((FAILED_ATTEMPT_CURRENT_RECORDS | FAILED_ATTEMPT_INVENTORY_FILES) - names)
        if missing:
            raise ValueError(f"failed-attempt diagnostic blocker records are missing: {missing}")
        state = read_json(root / "finalization-state.json")
        if (state.get("status"), state.get("blocker_code"), state.get("candidate_is_current"), state.get("source_changed_since_candidate"), state.get("rebuild_required"), state.get("artifact_tuple_matches_candidate"), state.get("full_release_passed"), state.get("internal_promotion_allowed"), state.get("public_promotion_allowed")) != ("BLOCKED — USER ACTION REQUIRED", FAILED_ATTEMPT_BLOCKER, False, True, True, False, False, False, False):
            raise ValueError("failed replacement-attempt authority flags are not truthful")
        attempt = state.get("failed_replacement_attempt")
        if not isinstance(attempt, dict) or attempt.get("snapshotPath") != FAILED_ATTEMPT_SNAPSHOT or attempt.get("blockerCode") != FAILED_ATTEMPT_BLOCKER:
            raise ValueError("failed replacement-attempt authority binding is missing")
        terminal = attempt.get("terminalEvidence")
        if not isinstance(terminal, dict) or not isinstance(terminal.get("l1"), dict) or not isinstance(terminal.get("l2"), dict):
            raise ValueError("failed replacement-attempt terminal L1/L2 evidence is missing")
        proof = read_json(root / "evidence/CURRENT-PROOF.json")
        attempted = read_json(root / "audit/attemptedReplacementCandidate.json")
        failure = read_json(root / "audit/candidateBindingFailure.json")
        expected = {
            "attemptedCommit": "21752fc0e50978183322204c523b40947d073aa0",
            "commitShippingInputIdentity": "6e0bac4b4eebc83cdcd9eddda2008607ba15c8835e5c72a931792f5b83c653f4",
            "buildTimeShippingInputIdentity": "3a65fd54d70fe05565ac3a32f73100ca2c81a77a4008feb361f99f229f025f8a",
        }
        if proof.get("status") != "NOT_OBSERVED" or proof.get("outcome") != "NOT_OBSERVED" or proof.get("blockerCode") != FAILED_ATTEMPT_BLOCKER:
            raise ValueError("failed-attempt CURRENT-PROOF contradicts the blocker authority")
        if attempted.get("snapshotPath") != FAILED_ATTEMPT_SNAPSHOT or attempted.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or any(attempted.get(key) != value for key, value in expected.items()):
            raise ValueError("attemptedReplacementCandidate contradicts the failed-attempt authority")
        if attempted.get("artifactTupleValid") is not True or attempted.get("artifactTupleMatchesCandidate") is not False or attempted.get("buildInvocationCount") != 1 or attempted.get("signingInvocationCount") != 1:
            raise ValueError("attemptedReplacementCandidate one-shot/artifact state is invalid")
        if failure.get("blockerCode") != FAILED_ATTEMPT_BLOCKER or any(failure.get(key) != value for key, value in expected.items()) or failure.get("artifactTupleValid") is not True or failure.get("artifactTupleMatchesCandidate") is not False or failure.get("currentProofOutcome") != "NOT_OBSERVED":
            raise ValueError("candidateBindingFailure contradicts the failed-attempt authority")
        manifest = read_json(root / "AUDIT-MANIFEST.json")
        inventory = manifest.get("evidenceInventory")
        if not isinstance(inventory, list) or {str(row.get("path")) for row in inventory if isinstance(row, dict)} != FAILED_ATTEMPT_CURRENT_RECORDS:
            raise ValueError("failed-attempt evidenceInventory is missing or incomplete")
        for row in inventory:
            relative = str(row.get("path"))
            path = root / Path(*relative.split("/"))
            if relative in FAILED_ATTEMPT_CURRENT_RECORDS and (not path.is_file() or int(row.get("bytes", -1)) != path.stat().st_size or str(row.get("sha256") or "").lower() != sha(path) or row.get("mode") != "0644"):
                raise ValueError(f"failed-attempt evidenceInventory hash/mode mismatch: {relative}")
        modes = read_json(root / "EVIDENCE-MODES.json")
        mode_by_path = {str(row.get("path")): row for row in modes if isinstance(row, dict)} if isinstance(modes, list) else {}
        if set(mode_by_path) != FAILED_ATTEMPT_CURRENT_RECORDS or any(row.get("posixMode") != 420 or row.get("mode") != "0644" for row in mode_by_path.values()):
            raise ValueError("failed-attempt evidence mode inventory is missing or contradictory")
        hash_rows = {}
        for line in (root / "EVIDENCE-SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
            if line.strip():
                digest, relative = line.split("  ", 1)
                hash_rows[relative] = digest.lower()
        if set(hash_rows) != FAILED_ATTEMPT_CURRENT_RECORDS or any(hash_rows[path] != next(row["sha256"] for row in inventory if row.get("path") == path) for path in FAILED_ATTEMPT_CURRENT_RECORDS):
            raise ValueError("failed-attempt evidence hash inventory is missing or contradictory")
        return {"status": "PASS_WITH_BLOCKER", "bundleMode": "diagnostic", "diagnostic": True, "blockerCode": FAILED_ATTEMPT_BLOCKER, "releaseEligible": False, "candidateIsCurrent": False, "sourceChangedSinceCandidate": True, "rebuildRequired": True, "proofOutcome": "NOT_OBSERVED", "filesChecked": len(names)}
    candidate_commit = str(candidate_record.get("candidateCommit") or candidate_record.get("candidateGitCommit") or "").lower()
    if candidate_commit != HISTORICAL_CANDIDATE:
        state = read_json(root / "finalization-state.json")
        flags = (state.get("candidate_is_current"), state.get("source_changed_since_candidate"), state.get("rebuild_required"), state.get("full_release_passed"), state.get("internal_promotion_allowed"), state.get("public_promotion_allowed"))
        current_pending = (True, False, False, False, False, False)
        invalidated_pending = (False, True, True, False, False, False)
        if flags not in {current_pending, invalidated_pending}:
            raise ValueError("generic diagnostic candidate authority flags are not truthful")
        current = read_json(root / "evidence/CURRENT-PROOF.json")
        summary = read_json(root / "evidence/FULLRELEASE-SUMMARY.json")
        if not summary.get("diagnosticOnly") and not summary.get("historicalEvidenceOnly"):
            raise ValueError("generic diagnostic summary must be marked diagnosticOnly or historicalEvidenceOnly")
        proof_outcome = str(current.get("outcome") or "")
        if proof_outcome == "NOT_OBSERVED":
            if str(current.get("status")) not in {"BLOCKED", "NOT_OBSERVED"}:
                raise ValueError("generic diagnostic NOT_OBSERVED proof status is not fail-closed")
        elif proof_outcome == "PASS":
            # A current exact-candidate proof may have passed before a later
            # FullRelease attempt was blocked. Preserve that truthful proof in
            # a diagnostic bundle while requiring its complete native proof
            # closure and keeping every release-promotion flag false.
            final = current.get("proofFinal")
            if (current.get("status") != "PASS"
                    or current.get("proofStartCurrent") is not True
                    or current.get("certificationEligible") is not True
                    or current.get("diagnosticOnly") is not False
                    or not isinstance(final, dict)
                    or final.get("status") != "PASS"
                    or final.get("runId") != current.get("runId")
                    or final.get("certificationEligible") is not True
                    or final.get("diagnosticOnly") is not False
                    or not isinstance(final.get("cleanup"), dict)
                    or final["cleanup"].get("status") != "PASS"):
                raise ValueError("generic diagnostic PASS proof lacks its current qualifying native closure")
            if summary.get("fullReleasePassed") is not False:
                raise ValueError("generic diagnostic PASS proof is paired with a contradictory FullRelease status")
        else:
            raise ValueError("generic diagnostic current proof outcome is not fail-closed")
        invalidated = flags == invalidated_pending
        if invalidated:
            authorization = state.get("authorized_correction")
            paths = authorization.get("shipping_paths") if isinstance(authorization, dict) else None
            working = candidate_record.get("workingTreeTuple")
            if not isinstance(paths, list) or not paths or not isinstance(working, dict):
                raise ValueError("invalidated diagnostic is missing its exact correction or working-tree tuple")
            for key in ("shippingInputIdentity", "canonicalizedShippingInputIdentity", "toolingFingerprintId"):
                value = str(working.get(key) or "")
                if len(value) != 64 or any(ch not in "0123456789abcdefABCDEF" for ch in value):
                    raise ValueError(f"invalidated diagnostic working-tree tuple is malformed: {key}")
        return {"status": "PASS_WITH_BLOCKER", "bundleMode": "diagnostic", "diagnostic": True, "blockerCode": "CANDIDATE_INVALIDATED_REBUILD_REQUIRED" if invalidated else "DIAGNOSTIC_PROOF_PENDING", "releaseEligible": False, "candidateIsCurrent": not invalidated, "sourceChangedSinceCandidate": invalidated, "rebuildRequired": invalidated, "proofOutcome": proof_outcome, "filesChecked": len(names)}
    provenance_values = [value for value in (candidate_record.get("historicalProvenance"), manifest.get("historicalProvenance") if isinstance(manifest, dict) else None) if isinstance(value, dict)]
    provenance = provenance_values[0] if provenance_values else None
    if not isinstance(provenance, dict):
        raise ValueError("diagnostic bundle requires structured historicalProvenance")
    if any(value != provenance for value in provenance_values[1:]):
        raise ValueError("diagnostic historical provenance declarations disagree")
    if str(provenance.get("candidateCommit") or "").lower() != HISTORICAL_CANDIDATE:
        raise ValueError("diagnostic candidate is not the preserved 2739 object")
    if str(provenance.get("provenanceCommit") or provenance.get("sourceCommit") or "").lower() != HISTORICAL_PROVENANCE:
        raise ValueError("diagnostic provenance is not the preserved f334 object")
    if str(provenance.get("materialization") or "") != "git-archive" or provenance.get("coreAutocrlf") is not False:
        raise ValueError("diagnostic provenance is not deterministic core.autocrlf=false materialization")
    if str(provenance.get("lineEndingComparison") or "").upper() not in {"CRLF_ONLY", "CRLF-ONLY"}:
        raise ValueError("diagnostic provenance is not a proven CRLF-only comparison")
    if str(provenance.get("historicalShippingInputIdentity") or "").lower() != HISTORICAL_SHIPPING_IDENTITY:
        raise ValueError("diagnostic historical shipping identity is not the preserved value")
    if str(provenance.get("historicalReleaseFingerprintId") or "").lower() != HISTORICAL_RELEASE_FINGERPRINT:
        raise ValueError("diagnostic historical release fingerprint is not the preserved value")
    if str(candidate_record.get("devfleetVersion") or "") != "1.2.13" or str(candidate_record.get("installerVersion") or "") != "1.4.1":
        raise ValueError("diagnostic historical candidate version tuple is not the exact 1.2.13/1.4.1 tuple")
    mode = candidate_record.get("candidateShippingModeContract")
    if not isinstance(mode, dict) or set(mode) != {"schemaVersion", "defaultMode", "executableMode", "executableByContract"} or mode.get("schemaVersion") != 1 or mode.get("defaultMode") != "0644" or mode.get("executableMode") != "0755" or not isinstance(mode.get("executableByContract"), list) or mode["executableByContract"] != sorted(str(path) for path in mode["executableByContract"]):
        raise ValueError("diagnostic historical candidate mode contract is incomplete or non-canonical")
    labels = provenance.get("identityLabels") if isinstance(provenance.get("identityLabels"), dict) else {}
    if not str(labels.get("preservedCanonicalShippingInputIdentity") or "").lower().startswith("454edc") or not str(labels.get("rawGitShippingInputIdentity") or "").lower().startswith("cdab") or not str(labels.get("rawGitReleaseFingerprintId") or "").lower().startswith("eba40"):
        raise ValueError("diagnostic historical identity labels are incomplete")
    recorded_paths = {str(path).replace("\\", "/") for path in provenance.get("authorizedCurrentShippingPaths", []) if str(path)}
    if recorded_paths != AUTHORIZED_SHIPPING_PATHS:
        raise ValueError("diagnostic historical provenance does not bind exactly the seven authorized shipping paths")
    rows = candidate_record.get("candidateShippingInputs")
    if not isinstance(rows, list) or not rows:
        raise ValueError("diagnostic candidate shipping rows are mandatory offline evidence")
    recomputed_identity = _candidate_shipping_identity(rows, candidate_record.get("devfleetVersion"), candidate_record.get("installerVersion"), candidate_record.get("candidateShippingModeContract") or {})
    if str(provenance.get("recomputedCandidateShippingInputIdentity") or "").lower() != recomputed_identity or recomputed_identity != HISTORICAL_RAW_GIT_SHIPPING_IDENTITY:
        raise ValueError("diagnostic candidate shipping identity was not recomputed from embedded rows")
    release_file = root / "outputs/release-fingerprint.json"
    release = read_json(release_file) if release_file.is_file() else {}
    release_rows = release.get("shippingInputs")
    if not isinstance(release_rows, list) or not release_rows:
        raise ValueError("diagnostic release rows are missing")
    release_payload = {key: release.get(key) for key in ("schemaVersion", "devfleetVersion", "installerVersion", "shippingModeContract")}
    # release_fingerprint.py canonicalizes each root independently (source
    # first, installer-source second); preserve that authoritative order.
    release_payload["shippingInputs"] = release_rows
    release_payload["artifacts"] = release.get("artifacts", [])
    recomputed_release = hashlib.sha256(json.dumps(release_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    if recomputed_release != HISTORICAL_RELEASE_FINGERPRINT or str(release.get("releaseFingerprintId") or "").lower() != recomputed_release:
        raise ValueError("diagnostic release rows do not recompute to the preserved fingerprint")
    declared_recomputed_release = str(provenance.get("recomputedHistoricalReleaseFingerprintId") or "").lower()
    if not declared_recomputed_release or declared_recomputed_release != recomputed_release:
        raise ValueError("diagnostic historical release fingerprint closure is not recomputed")
    state = read_json(root / "finalization-state.json")
    release_artifacts = {str(row.get("name") or "").lower().replace("-", "").replace("_", ""): row for row in release.get("artifacts", []) if isinstance(row, dict)}
    state_candidate = state.get("candidate") if isinstance(state, dict) else None
    if not isinstance(state_candidate, dict):
        raise ValueError("diagnostic candidate artifact tuple is missing")
    candidate_artifacts = {str(value.get("name") or key).lower().replace("-", "").replace("_", ""): value for key, value in state_candidate.items() if isinstance(value, dict)}
    for key in ("exe", "tar", "portable", "installersource"):
        expected = next((row for name, row in release_artifacts.items() if key in name), None)
        observed = next((row for name, row in candidate_artifacts.items() if key in name), None)
        if expected is None or observed is None or str(expected.get("sha256") or "").lower() != str(observed.get("sha256") or "").lower() or int(expected.get("bytes", -1)) != int(observed.get("bytes", -2)):
            raise ValueError(f"diagnostic artifact closure mismatch: {key}")
    state_flags = (state.get("candidate_is_current"), state.get("source_changed_since_candidate"), state.get("rebuild_required"), state.get("full_release_passed"), state.get("internal_promotion_allowed"), state.get("public_promotion_allowed"))
    if state_flags != (False, True, True, False, False, False):
        raise ValueError("diagnostic authority flags are not truthful")
    if provenance.get("releaseEligible") is not False or provenance.get("promotionAllowed") is not False:
        raise ValueError("diagnostic historical provenance cannot be promoted")
    current = read_json(root / "evidence/CURRENT-PROOF.json")
    if str(current.get("outcome")) != "NOT_OBSERVED" or str(current.get("status")) not in {"BLOCKED", "NOT_OBSERVED"}:
        raise ValueError("diagnostic bundle must preserve a blocked NOT_OBSERVED current proof")
    handoff = read_json(root / "audit/CURRENT-HANDOFF.json")
    classification = str(current.get("blockerClassification") or handoff.get("blockerClassification") or "")
    if "RELEASE HARNESS" not in classification or ("EVIDENCE TOOLING" not in classification and "/ TOOLING" not in classification):
        raise ValueError("diagnostic bundle blocker classification is not release harness/evidence tooling")
    validate_historical_proof_sources(root, current)
    summary = read_json(root / "evidence/FULLRELEASE-SUMMARY.json")
    if not summary.get("diagnosticOnly") and not summary.get("historicalEvidenceOnly"):
        raise ValueError("blocked FullRelease summary must be marked diagnosticOnly or historicalEvidenceOnly")
    if bool(state.get("full_release_passed")) or bool(state.get("internal_promotion_allowed")) or bool(state.get("public_promotion_allowed")):
        raise ValueError("diagnostic bundle cannot claim promotion or FullRelease PASS")
    return {"status": "PASS_WITH_BLOCKER", "bundleMode": "diagnostic", "diagnostic": True, "releaseEligible": False, "candidateIsCurrent": False, "sourceChangedSinceCandidate": True, "rebuildRequired": True, "proofOutcome": "NOT_OBSERVED", "filesChecked": len(names)}


def validate_release_evidence(root: Path, *, require_release_audit: bool = False) -> dict[str, object]:
    """Validate the current workspace through cleanup, without granting promotion.

    This is deliberately separate from FINAL-ACCEPTANCE.  The immutable release
    audit is produced only after this closure passes, and FINAL-ACCEPTANCE is
    produced only after the immutable audit has also been revalidated.
    """
    root = root.resolve()
    closure = _validate_current_release_evidence(root, "workspace")
    result: dict[str, object] = {
        "status": "PASS",
        "bundleMode": "pre-acceptance",
        "releaseEligible": False,
        "internalPromotionAllowed": False,
        "publicPromotionAllowed": False,
        **closure,
        "standardTokenRunId": closure["standardToken"]["runId"],
    }
    if require_release_audit:
        result["releaseAudit"] = _validate_release_audit(
            root,
            closure["candidateTuple"],
            str(closure["fullReleaseRunId"]),
            "workspace",
            require_archive=True,
            closure=closure,
        )
        result["releaseAuditRunId"] = result["releaseAudit"]["runId"]
    return result


def validate(archive: Path, mode: str = "final") -> dict[str, object]:
    if mode == "final":
        mode = "release"
    if mode not in {"diagnostic", "pre-acceptance", "release"}:
        raise ValueError("bundle mode must be diagnostic, pre-acceptance, or release")
    if not archive.is_file():
        raise ValueError(f"bundle is missing: {archive}")
    temp = Path(tempfile.mkdtemp(prefix="DevFleet release bundle "))
    try:
        with zipfile.ZipFile(archive) as bundle:
            names = {PurePosixPath(info.filename.replace("\\", "/")).as_posix() for info in bundle.infolist()}
            required = (DIAGNOSTIC_REQUIRED if mode == "diagnostic"
                        else PRE_ACCEPTANCE_REQUIRED if mode == "pre-acceptance"
                        else REQUIRED)
            missing = sorted(required - names)
            if missing:
                raise ValueError(f"current release evidence missing: {missing}")
            names = _safe_extract(bundle, temp)
        root = temp
        candidate_result = _validate_candidate_bound(root, "diagnostic" if mode == "diagnostic" else "release")
        sys.path.insert(0, str(root / "release-tooling"))
        from validate_audit_coherence import validate as validate_coherence  # type: ignore
        validate_coherence(root)
        authority_state = read_json(root / "finalization-state.json")
        expected_head = str(authority_state.get("repository_head") or authority_state.get("repositoryHead") or "")
        candidate = str(authority_state.get("candidate_git_commit") or authority_state.get("candidateGitCommit") or "")
        shipping = str(authority_state.get("shipping_input_identity") or authority_state.get("shippingInputIdentity") or "")
        release = str(authority_state.get("releaseFingerprintId") or "")
        tooling = str(authority_state.get("toolingFingerprintId") or "")
        if mode == "diagnostic":
            result = _validate_diagnostic(root, names)
            result["candidateBoundVerification"] = candidate_result
            return result
        if mode == "pre-acceptance":
            forbidden = {name for name in names if name == "evidence/FINAL-ACCEPTANCE.json" or name.startswith("evidence/release-audits/") or name == "evidence/CURRENT-RELEASE-AUDIT.json"}
            if forbidden:
                raise ValueError(f"pre-acceptance audit contains post-audit evidence (cycle): {sorted(forbidden)}")
            closure = _validate_current_release_evidence(root, "bundle")
            return {
                "status": "PASS", "bundleMode": "pre-acceptance",
                "releaseEligible": False, "internalPromotionAllowed": False,
                "publicPromotionAllowed": False, "filesChecked": len(names),
                "candidateBoundVerification": candidate_result,
                "candidateTuple": closure["candidateTuple"],
                "fullReleaseRunId": closure["fullReleaseRunId"],
                "standardTokenRunId": closure["standardToken"]["runId"],
                "proofRunIds": closure["proofRunIds"],
            }
        final = validate_final_acceptance(root, "bundle")
        return {**final, "bundleMode": "release", "filesChecked": len(names), "candidateBoundVerification": candidate_result}
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--archive", type=Path)
    source.add_argument("--workspace-root", type=Path)
    parser.add_argument("--mode", choices=("diagnostic", "pre-acceptance", "release"), default="release")
    parser.add_argument("--check", choices=("release-evidence", "pre-acceptance", "final-acceptance"))
    parser.add_argument("--final-record", type=Path, help="candidate FINAL-ACCEPTANCE path for workspace pre-publication validation")
    args = parser.parse_args()
    try:
        if args.archive:
            if args.check or args.final_record:
                raise ValueError("--check/--final-record are only valid with --workspace-root")
            result = validate(args.archive.resolve(), args.mode)
        else:
            if not args.check:
                raise ValueError("--workspace-root requires --check")
            if args.mode != "release":
                raise ValueError("--mode is only valid with --archive")
            if args.final_record and args.check != "final-acceptance":
                raise ValueError("--final-record requires --check final-acceptance")
            if args.check == "final-acceptance":
                result = validate_final_acceptance(args.workspace_root.resolve(), "workspace", args.final_record)
            else:
                result = validate_release_evidence(args.workspace_root, require_release_audit=(args.check == "pre-acceptance"))
        print(json.dumps(result, sort_keys=True))
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"RELEASE BUNDLE FAIL: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

```
