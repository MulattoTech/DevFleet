# DevFleet source part 129

Full-source UTF-8 byte interval [5952000, 5998500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 488b19161cd6847f6681436812b2da2b7d5c82fbce1ab8f3515e3914a686ee2e

<!-- BEGIN SOURCE SLICE -->
lse) -> None:
    if not isinstance(record, dict):
        raise ValueError(f"{label} tuple is missing")
    aliases = {
        "repositoryHead": ("repositoryHead", "repository_head"),
        "candidateCommit": ("candidateCommit", "candidateGitCommit", "candidateBuildCommit", "candidate_git_commit", "gitCommit"),
        "shippingInputIdentity": ("shippingInputIdentity", "shipping_input_identity"),
        "releaseFingerprintId": (("releaseFingerprint", "releaseFingerprintId") if proof_names else ("releaseFingerprintId", "releaseFingerprint")),
        "toolingFingerprintId": (("toolingFingerprint", "toolingFingerprintId") if proof_names else ("toolingFingerprintId", "toolingFingerprint")),
    }
    for canonical, names in aliases.items():
        observed = next((str(record.get(name)) for name in names if record.get(name)), "")
        if observed != expected[canonical]:
            raise ValueError(f"{label} tuple mismatch: {canonical}")


def _layout_path(layout: str, workspace_path: str, bundle_path: str) -> str:
    return workspace_path if layout == "workspace" else bundle_path


def _validate_standard_token(root: Path, expected: dict[str, str], artifacts: dict[str, dict[str, object]], layout: str) -> dict[str, object]:
    pointer_path = root / "evidence/CURRENT-STANDARD-TOKEN.json"
    if not pointer_path.is_file():
        raise ValueError("CURRENT-STANDARD-TOKEN.json is missing")
    pointer = read_json(pointer_path)
    run_id = str(pointer.get("runId") or "")
    if not re.fullmatch(r"standard-token-[A-Za-z0-9-]+", run_id):
        raise ValueError("standard-token RunId is malformed")
    workspace_root = f"evidence/standard-token/{run_id}"
    bundle_root = f"evidence/standard-token/{run_id}"
    raw_relative = _layout_path(layout, f"{workspace_root}/installer-self-test-raw.txt", f"{bundle_root}/installer-self-test-raw.txt")
    canonical_relative = _layout_path(layout, f"{workspace_root}/standard-token-evidence.json", f"{bundle_root}/standard-token-evidence.json")
    raw = root / raw_relative
    canonical_path = root / canonical_relative
    if not raw.is_file() or not canonical_path.is_file():
        raise ValueError("immutable standard-token raw/canonical evidence is missing")
    canonical = read_json(canonical_path)
    if pointer != canonical:
        raise ValueError("CURRENT-STANDARD-TOKEN does not exactly match its immutable canonical evidence")
    if pointer.get("schemaVersion") != 1 or pointer.get("status") != "PASS" or pointer.get("standardNonAdministratorToken") is not True or pointer.get("exitCode") != 0 or pointer.get("residualSelfTestScratchCount") != 0:
        raise ValueError("standard-token result is not a genuine clean PASS")
    _assert_tuple(pointer, expected, "standard-token")
    if pointer.get("candidateBuildCommit") != expected["candidateCommit"]:
        raise ValueError("standard-token candidate build commit is stale")
    if pointer.get("runDirectory") != workspace_root or pointer.get("rawReportPath") != f"{workspace_root}/installer-self-test-raw.txt" or pointer.get("canonicalEvidencePath") != f"{workspace_root}/standard-token-evidence.json":
        raise ValueError("standard-token immutable paths are not canonical")
    required = pointer.get("requiredChecks")
    if not isinstance(required, dict) or set(required) != STANDARD_TOKEN_CHECKS or any(value is not True for value in required.values()):
        raise ValueError("standard-token required checks are missing, renamed, or false")
    token = pointer.get("token")
    if (not isinstance(token, dict) or token.get("standardNonAdministratorToken") is not True
            or token.get("isAdministratorMember") is not False or token.get("isAdministratorEnabled") is not False
            or token.get("isElevated") is not False or token.get("integrityLevel") not in {"Medium", "MediumPlus"}):
        raise ValueError("standard-token native token evidence is not a medium non-administrator token")
    if str(pointer.get("reportSha256") or "").lower() != sha(raw):
        raise ValueError("standard-token raw report hash mismatch")
    text = raw.read_text(encoding="utf-8-sig")
    if not re.search(r"(?m)^PASS\s*$", text) or f"payload={artifacts['tar']['sha256']}" not in text:
        raise ValueError("standard-token raw report does not bind PASS and the exact payload")
    for name in ("exe", "tar"):
        row = pointer.get(name)
        if not isinstance(row, dict) or str(row.get("sha256")) != str(artifacts[name]["sha256"]) or int(row.get("bytes", -1)) != int(artifacts[name]["bytes"]):
            raise ValueError(f"standard-token artifact mismatch: {name}")
    runner = pointer.get("runner")
    runner_relative = "automation/release-e2e/tests/Test-InstallerSelfTestStandardToken.ps1"
    if not isinstance(runner, dict) or runner.get("path") != runner_relative or str(runner.get("sha256") or "").lower() != sha(root / runner_relative):
        raise ValueError("standard-token runner bytes are missing or changed")
    return {
        "runId": run_id,
        "pointerSha256": sha(pointer_path),
        "canonicalSha256": sha(canonical_path),
        "rawReportSha256": sha(raw),
        "pointerPath": "evidence/CURRENT-STANDARD-TOKEN.json",
        "canonicalPath": canonical_relative,
        "rawReportPath": raw_relative,
    }


def _validate_real_use(record: dict[str, object], binding_path: Path, prepare_path: Path, report_path: Path, expected: dict[str, str], run_id: str) -> dict[str, object]:
    evidence = record.get("evidence") if isinstance(record, dict) else None
    executor = evidence.get("executor") if isinstance(evidence, dict) else None
    if not isinstance(executor, dict) or executor.get("status") != "REAL E2E PASS" or executor.get("phase") != "REAL-USE-ACCEPTANCE" or executor.get("contract") != "devfleet-real-use-acceptance-phase-v1":
        raise ValueError("FullRelease REAL-USE-ACCEPTANCE is not an explicit REAL E2E PASS")
    _assert_tuple(executor.get("candidate"), expected, "REAL-USE-ACCEPTANCE")
    binding = read_json(binding_path)
    if binding.get("schemaVersion") != 1 or binding.get("contract") != "devfleet-real-use-acceptance-v1" or binding.get("runId") != run_id or binding.get("phaseId") != "REAL-USE-ACCEPTANCE" or binding.get("precedingPhase") != "SURROGATE-DISPOSABLE":
        raise ValueError("REAL-USE-ACCEPTANCE durable binding contract is invalid")
    _assert_tuple(binding.get("candidate"), expected, "REAL-USE-ACCEPTANCE binding")
    prepare = read_json(prepare_path)
    if prepare.get("schemaVersion") != 1 or prepare.get("contract") != "devfleet-real-use-acceptance-v1" or prepare.get("status") != "PREPARED" or prepare.get("stage") != "prepare" or prepare.get("runId") != run_id or prepare.get("phaseId") != "REAL-USE-ACCEPTANCE":
        raise ValueError("REAL-USE-ACCEPTANCE durable prepare report is invalid")
    _assert_tuple(prepare.get("candidate"), expected, "REAL-USE-ACCEPTANCE prepare")
    report = read_json(report_path)
    if report.get("schemaVersion") != 1 or report.get("contract") != "devfleet-real-use-acceptance-v1" or report.get("status") != "PASS" or report.get("stage") != "resume" or report.get("phaseId") != "REAL-USE-ACCEPTANCE" or report.get("runId") != run_id:
        raise ValueError("REAL-USE-ACCEPTANCE report contract/status/RunId is invalid")
    _assert_tuple(report.get("candidate"), expected, "REAL-USE-ACCEPTANCE report")
    journeys = report.get("journeys")
    if not isinstance(journeys, list) or [row.get("id") for row in journeys if isinstance(row, dict)] != ["U01", "U02", "U03", "U04", "U05"] or any(row.get("status") != "PASS" for row in journeys if isinstance(row, dict)):
        raise ValueError("REAL-USE-ACCEPTANCE report does not contain ordered U01-U05 PASS")
    for row in journeys:
        assertions = row.get("assertions") if isinstance(row, dict) else None
        if not isinstance(assertions, dict) or not assertions or any(value is not True for value in assertions.values()):
            raise ValueError("REAL-USE-ACCEPTANCE journey contains an unproven assertion")
    cleanup = report.get("cleanup")
    if not isinstance(cleanup, dict) or cleanup.get("status") != "PASS" or cleanup.get("ownedOnly") is not True or cleanup.get("errors") not in ([], None) or report.get("failure") is not None or report.get("cleanupFailure") is not None:
        raise ValueError("REAL-USE-ACCEPTANCE cleanup is not a clean owned-only PASS")
    evidence_binding = executor.get("evidence")
    expected_files = {
        "binding": (binding_path, "bindingPath", "bindingSha256"),
        "prepare": (prepare_path, "preparePath", "prepareSha256"),
        "report": (report_path, "reportPath", "reportSha256"),
    }
    if not isinstance(evidence_binding, dict):
        raise ValueError("REAL-USE-ACCEPTANCE phase evidence bindings are missing")
    for label, (path, path_key, hash_key) in expected_files.items():
        if Path(str(evidence_binding.get(path_key) or "")).name != path.name or str(evidence_binding.get(hash_key) or "").lower() != sha(path):
            raise ValueError(f"REAL-USE-ACCEPTANCE phase does not bind durable {label} bytes")
    if executor.get("credentialsStoredInEvidence") is not False or executor.get("internalPromotionAllowed") is not False:
        raise ValueError("REAL-USE-ACCEPTANCE phase is not secret-safe/non-promoting")
    return {"bindingSha256": sha(binding_path), "prepareSha256": sha(prepare_path), "reportSha256": sha(report_path), "journeys": [row["id"] for row in journeys]}


def _canonical_shipping_rows(rows: list[object]) -> list[dict[str, object]]:
    """Normalize and order rows exactly like the candidate-bound validator."""
    normalized: list[dict[str, object]] = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("candidate shipping row is not an object")
        mode = str(row.get("mode") or "")
        if mode not in {"0644", "0755"}:
            raise ValueError("candidate shipping row has a missing or invalid mode")
        root = str(row.get("root") or "").replace("\\", "/").strip("/")
        path = str(row.get("path") or "").replace("\\", "/").lstrip("/")
        if root not in {"source", "installer-source"} or not path or ".." in PurePosixPath(path).parts:
            raise ValueError("candidate shipping row has an invalid path")
        normalized.append({"root": root, "path": path, "bytes": int(row.get("bytes", -1)), "sha256": str(row.get("sha256") or "").lower(), "mode": mode})
    return sorted(normalized, key=lambda row: (0 if row["root"] == "source" else 1, tuple(part.casefold() for part in str(row["path"]).split("/"))))


def _candidate_shipping_identity(rows: list[object], version: object, installer: object, mode: object) -> str:
    payload = {"schemaVersion": 1, "devfleetVersion": version, "installerVersion": installer, "shippingModeContract": mode, "shippingInputs": _canonical_shipping_rows(rows)}
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def _validate_candidate_bound(root: Path, mode: str) -> dict[str, object]:
    script = root / "source/tools/validate_audit_coherence.py"
    if not script.is_file():
        raise ValueError("candidate-bound validator is missing from the bundle")
    try:
        completed = subprocess.run([sys.executable, str(script), "--root", str(root), "--mode", mode], capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ValueError("candidate-bound validator could not be executed") from exc
    if completed.returncode != 0:
        raise ValueError(f"candidate-bound validator failed: {(completed.stderr or completed.stdout)[-2000:]}")
    try:
        result = json.loads(completed.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError) as exc:
        raise ValueError("candidate-bound validator did not return JSON") from exc
    expected = "PASS_WITH_BLOCKER" if mode == "diagnostic" else "PASS"
    if result.get("status") != expected:
        raise ValueError(f"candidate-bound validator returned {result.get('status')!r}, expected {expected!r}")
    if mode == "diagnostic" and result.get("releaseEligible") is not False:
        raise ValueError("candidate-bound diagnostic result is release eligible")
    return result


def _current_release_paths(root: Path, layout: str, state: dict[str, object]) -> tuple[Path, Path]:
    if layout == "bundle":
        return root / "evidence/current-fullrelease", root / "evidence/proof-runs"
    run_id = str(state.get("full_release_run_id") or "")
    if not run_id or not re.fullmatch(r"(?:e2e-)?fullrelease-[A-Za-z0-9-]+", run_id, re.IGNORECASE):
        raise ValueError("current FullRelease RunId is missing or malformed")
    return root / "audit/automation-harness/runs" / run_id, root / "audit/automation-harness/runs"


def _validate_workspace_candidate(root: Path, expected: dict[str, str], artifacts: dict[str, dict[str, object]]) -> None:
    head = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=30)
    if head.returncode != 0 or head.stdout.strip() != expected["repositoryHead"]:
        raise ValueError("live repository HEAD differs from the accepted tuple")
    manifest = read_json(root / "outputs/final-artifact-hashes.json")
    _assert_tuple(manifest, expected, "final artifact manifest")
    release_record = read_json(root / "outputs/release-fingerprint.json")
    tooling_record = read_json(root / "outputs/tooling-fingerprint-current.json")
    if release_record.get("releaseFingerprintId") != expected["releaseFingerprintId"] or not isinstance(release_record.get("toolingFingerprint"), dict) or release_record["toolingFingerprint"].get("toolingFingerprintId") != expected["toolingFingerprintId"]:
        raise ValueError("release fingerprint record disagrees with the accepted tuple")
    _assert_tuple(tooling_record, expected, "current tooling fingerprint")
    rows = manifest.get("artifacts")
    if not isinstance(rows, list) or {str(row.get("name")) for row in rows if isinstance(row, dict)} != set(artifacts):
        raise ValueError("final artifact manifest does not contain the exact artifact tuple")
    for row in rows:
        name = str(row["name"])
        expected_row = artifacts[name]
        if str(row.get("sha256") or "") != str(expected_row["sha256"]) or int(row.get("bytes", -1)) != int(expected_row["bytes"]):
            raise ValueError(f"final artifact manifest disagrees with release fingerprint: {name}")
        _checked_file(root, row.get("path"), row.get("sha256"), f"signed candidate artifact {name}", row.get("bytes"))
    certificate = manifest.get("publicCertificate")
    if not isinstance(certificate, dict):
        raise ValueError("public signing certificate identity is missing")
    _checked_file(root, certificate.get("path"), certificate.get("sha256"), "public signing certificate", certificate.get("bytes"))
    signing = read_json(root / "outputs/SIGNING-PROVIDER.json")
    final_exe = signing.get("finalSignedExe") if isinstance(signing, dict) else None
    if (signing.get("signatureStatus") != "Valid" or signing.get("signerThumbprint") != "DE42CD7369A01E9357BDA13597C0173E5E703E9D"
            or signing.get("signerSubject") != "CN=DevFleet Private Personal Code Signing"
            or signing.get("codeSigningEkuVerified") is not True or signing.get("rsaBits") != 3072
            or signing.get("privateKeyExportable") is not False or signing.get("privateKeyExported") is not False
            or signing.get("publicPublisherTrust") is not False or signing.get("publicPromotionAllowed") is not False
            or not isinstance(final_exe, dict) or final_exe.get("sha256") != artifacts["exe"]["sha256"] or int(final_exe.get("bytes", -1)) != int(artifacts["exe"]["bytes"])):
        raise ValueError("signing provider record is incomplete or disagrees with the signed EXE")
    identity_tool = root / "tools/compute_shipping_input_identity.py"
    manifest_artifact_paths: dict[str, Path] = {}
    for row in rows:
        name = str(row["name"])
        manifest_artifact_paths[name] = _checked_file(
            root, row.get("path"), row.get("sha256"),
            f"signed candidate artifact {name}", row.get("bytes"),
        )
    identity_arguments = [
        sys.executable, str(identity_tool),
        "--workspace", str(root), "--candidate-commit", expected["candidateCommit"],
    ]
    for name in sorted(artifacts):
        identity_arguments.extend(["--artifact", f"{name}={manifest_artifact_paths[name]}"])
    completed = subprocess.run(
        identity_arguments,
        capture_output=True, text=True, timeout=180,
    )
    if completed.returncode != 0:
        raise ValueError(f"live candidate identity recomputation failed: {(completed.stderr or completed.stdout)[-1000:]}")
    try:
        identity = json.loads(completed.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError) as exc:
        raise ValueError("live candidate identity recomputation did not return JSON") from exc
    exact = identity.get("liveShippingInputIdentity") == expected["shippingInputIdentity"]
    eol_only = identity.get("crlfOnlyMaterialization") is True and identity.get("candidateShippingInputIdentity") == expected["shippingInputIdentity"]
    if not exact and not eol_only:
        raise ValueError("live shipping inputs differ from the signed candidate")
    observed_release = identity.get("liveReleaseFingerprintId") if exact else identity.get("candidateReleaseFingerprintId")
    if observed_release != expected["releaseFingerprintId"]:
        raise ValueError("live/canonical release fingerprint differs from the accepted tuple")
    live_tooling = identity.get("liveToolingFingerprint")
    if not isinstance(live_tooling, dict) or live_tooling.get("toolingFingerprintId") != expected["toolingFingerprintId"]:
        raise ValueError("live tooling fingerprint differs from the accepted tuple")


def _validate_current_release_evidence(root: Path, layout: str) -> dict[str, object]:
    state = read_json(root / "finalization-state.json")
    expected = _tuple_from_state(state)
    artifacts = _artifact_map(root)
    if layout == "workspace":
        _validate_workspace_candidate(root, expected, artifacts)
    full_root, proof_root = _current_release_paths(root, layout, state)
    run_state_path = full_root / "run-state.json"
    records_path = full_root / "fullrelease-phase-records.json"
    if not run_state_path.is_file() or not records_path.is_file():
        raise ValueError("current FullRelease run-state or phase records are missing")
    run_state = read_json(run_state_path)
    run_id = str(run_state.get("runId") or "")
    if run_id != str(state.get("full_release_run_id") or run_id) or run_state.get("mode") != "FullRelease" or run_state.get("finalStatus") != "PASS":
        raise ValueError("current FullRelease is not one coherent terminal PASS")
    _assert_tuple(run_state.get("candidateHashes"), expected, "FullRelease run-state")
    full_summary = read_json(root / "evidence/FULLRELEASE-SUMMARY.json")
    if (full_summary.get("latestRunId") != run_id or full_summary.get("status") != "PASS" or full_summary.get("historicalEvidenceOnly") is not False):
        raise ValueError("FULLRELEASE-SUMMARY is not the current terminal PASS")
    _assert_tuple(full_summary.get("candidateTuple"), expected, "FULLRELEASE-SUMMARY")
    full_hashes = run_state.get("candidateHashes")
    for name in ("exe", "tar", "portable", "installerSource"):
        if not isinstance(full_hashes, dict) or str(full_hashes.get(name) or "") != str(artifacts[name]["sha256"]):
            raise ValueError(f"FullRelease artifact tuple mismatch: {name}")
    records = read_json(records_path)
    if not isinstance(records, list):
        raise ValueError("FullRelease phase records are not a list")
    by_id: dict[str, dict[str, object]] = {}
    record_ids: list[str] = []
    for row in records:
        if isinstance(row, dict) and row.get("id"):
            phase_id = str(row["id"])
            record_ids.append(phase_id)
            by_id[phase_id] = row
            if row.get("runId") and row.get("runId") != run_id:
                raise ValueError(f"FullRelease phase record is spliced to another RunId: {phase_id}")
    if len(record_ids) != len(set(record_ids)):
        raise ValueError("FullRelease phase records contain duplicate phase IDs")
    missing = sorted(REQUIRED_FULLRELEASE_PHASES - set(by_id))
    failed = sorted(phase for phase in REQUIRED_FULLRELEASE_PHASES if phase in by_id and by_id[phase].get("status") != "PASS")
    if missing or failed:
        raise ValueError(f"FullRelease mandatory phase closure is incomplete; missing={missing}; notPass={failed}")
    completed = set(str(value) for value in run_state.get("completedPhases", []) if value)
    if not REQUIRED_FULLRELEASE_PHASES.issubset(completed):
        raise ValueError("FullRelease run-state does not record every mandatory phase as completed")
    host = by_id["HOST-SAFETY"].get("evidence")
    if (not isinstance(host, dict) or host.get("startSafe") is not True
            or host.get("rawHostSafetyStartSafe") is not True
            or host.get("effectiveE2EStartAuthorized") is not True
            or host.get("ramPressureOverrideAuthorized") is not False):
        raise ValueError("FullRelease HOST-SAFETY is not a native no-override PASS")
    maintenance = [by_id[name] for name in sorted(MAINTENANCE_PHASES)]
    if len(maintenance) != 5 or any(row.get("status") != "PASS" for row in maintenance):
        raise ValueError("FullRelease maintenance is not 5/5 PASS")
    real_binding_path = full_root / "real-use-acceptance-binding.json"
    real_prepare_path = full_root / "real-use-acceptance-prepare.json"
    real_report_path = full_root / "real-use-acceptance-report.json"
    real_summary_path = full_root / "real-use-acceptance-evidence.json"
    if not all(path.is_file() for path in (real_binding_path, real_prepare_path, real_report_path, real_summary_path)):
        raise ValueError("FullRelease durable REAL-USE-ACCEPTANCE binding/prepare/report/summary is missing")
    real_use = _validate_real_use(by_id["REAL-USE-ACCEPTANCE"], real_binding_path, real_prepare_path, real_report_path, expected, run_id)
    real_summary = read_json(real_summary_path)
    if real_summary.get("contract") != "devfleet-real-use-acceptance-evidence-v1" or real_summary.get("status") != "PASS" or real_summary.get("runId") != run_id or real_summary.get("credentialsStoredInEvidence") is not False or real_summary.get("internalPromotionAllowed") is not False or [row.get("id") for row in real_summary.get("journeys", [])] != ["U01", "U02", "U03", "U04", "U05"] or any(row.get("status") != "PASS" for row in real_summary.get("journeys", [])):
        raise ValueError("REAL-USE-ACCEPTANCE durable summary is incomplete")
    summary_evidence = real_summary.get("evidence")
    if not isinstance(summary_evidence, dict):
        raise ValueError("REAL-USE-ACCEPTANCE summary evidence bindings are missing")
    for label in ("binding", "prepare", "report"):
        ref = summary_evidence.get(label)
        if not isinstance(ref, dict) or str(ref.get("sha256") or "").lower() != real_use[f"{label}Sha256"]:
            raise ValueError(f"REAL-USE-ACCEPTANCE summary does not bind durable {label} bytes")
    reconcile = by_id["RECONCILE"].get("evidence")
    reconcile_executor = reconcile.get("executor") if isinstance(reconcile, dict) else None
    if not isinstance(reconcile_executor, dict) or reconcile_executor.get("status") != "REAL E2E PASS" or reconcile_executor.get("phase") != "RECONCILE" or reconcile_executor.get("maintenance") != "5/5":
        raise ValueError("RECONCILE is not a current 5/5 REAL E2E PASS")
    _assert_tuple(reconcile_executor.get("candidate"), expected, "RECONCILE")
    cleanup = read_json(full_root / "final-cleanup.json")
    cleanup_l1 = cleanup.get("l1") if isinstance(cleanup.get("l1"), dict) else {}
    if (cleanup.get("status") != "PASS" or cleanup.get("runId") != run_id or cleanup.get("guest", {}).get("nestedAbsent") is not True or cleanup_l1.get("name") != "DevFleet-E2E-Win11-01"
            or str(cleanup_l1.get("id") or "") != "84b7d8b8-ee6c-4085-aa29-4b0adc316de2"
            or cleanup_l1.get("state") != "Off" or cleanup_l1.get("deleted") is not False
            or cleanup.get("productionTouched") is not False or cleanup.get("physicalSurfaceTouched") is not False
            or cleanup.get("guest", {}).get("runRootAbsent") is not True or cleanup.get("guest", {}).get("foreignResourcesMutated") is not False):
        raise ValueError("certified FullRelease CLEANUP is incomplete or unsafe")
    post_cleanup = read_json(full_root / "post-cleanup-finalization.json")
    if post_cleanup.get("status") != "PASS" or post_cleanup.get("runId") != run_id or post_cleanup.get("cleanupConsumed") is not True or post_cleanup.get("reconcileAfterCleanup") is not True:
        raise ValueError("post-cleanup finalization did not consume current RECONCILE/CLEANUP")
    live_checks = post_cleanup.get("liveChecks")
    if not isinstance(live_checks, dict) or live_checks.get("l1ExactOff") is not True or live_checks.get("l2ExactAbsent") is not True or live_checks.get("hostSameNameL2Absent") is not True or live_checks.get("foreignResourcesMutated") is not False:
        raise ValueError("post-cleanup exact live state is not L1 OFF / L2 ABSENT")
    _assert_tuple(post_cleanup.get("candidate"), expected, "post-cleanup finalization")
    cleanup_hash = str(post_cleanup.get("cleanupEvidenceHash") or "").lower()
    if cleanup_hash != sha(full_root / "final-cleanup.json"):
        raise ValueError("post-cleanup finalization does not bind final-cleanup.json")
    terminal_paths = {
        "terminalL1Hash": full_root / "l1-terminal-state.json",
        "terminalL2Hash": full_root / "l2-terminal-state.json",
    }
    for key, path in terminal_paths.items():
        if str(post_cleanup.get(key) or "").lower() != sha(path):
            raise ValueError(f"post-cleanup finalization does not bind {path.name}")
    l1, l2 = read_json(terminal_paths["terminalL1Hash"]), read_json(terminal_paths["terminalL2Hash"])
    if ((l1.get("name"), str(l1.get("id") or l1.get("vmId")), str(l1.get("state"))) != ("DevFleet-E2E-Win11-01", "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "Off")
            or not (l1.get("timestamp") or l1.get("timestampUtc")) or not l1.get("ownershipScope")):
        raise ValueError("FullRelease terminal L1 is not the exact disposable VM OFF")
    _validate_nested_l2_terminal(full_root, l2, l1, expected, run_id)
    nested_source_path = full_root / "nested-l2-terminal-observation.json"
    if str(post_cleanup.get("nestedL2Observation") or "") != "nested-l2-terminal-observation.json" or str(post_cleanup.get("nestedL2ObservationSha256") or "").lower() != sha(nested_source_path):
        raise ValueError("post-cleanup finalization does not bind the nested L2 source observation")
    if layout == "bundle":
        if sha(root / "evidence/l1-terminal-state.json") != sha(terminal_paths["terminalL1Hash"]) or sha(root / "evidence/l2-terminal-state.json") != sha(terminal_paths["terminalL2Hash"]):
            raise ValueError("bundle root terminal state disagrees with the current FullRelease")
    standard = _validate_standard_token(root, expected, artifacts, layout)

    authority = read_json(root / "evidence/CURRENT-RELEASE-AUTHORITY.json")
    _assert_tuple(authority, expected, "CURRENT-RELEASE-AUTHORITY")
    proof_rows = authority.get("proofs", {}).get("runs") if isinstance(authority.get("proofs"), dict) else None
    if not isinstance(proof_rows, list) or len(proof_rows) != 2:
        raise ValueError("current authority does not select exactly two passing proofs")
    run_ids = [str(row.get("runId") or "") for row in proof_rows if isinstance(row, dict)]
    transactions: list[str] = []
    lineages: list[str] = []
    roles: list[str] = []
    sources = {
        "proofScriptSha256": root / ("audit/run-exact-candidate-proof.ps1" if layout == "workspace" else "release-tooling/proof-entrypoints/run-exact-candidate-proof.ps1"),
        "invokeRealProductPhaseSha256": root / ("automation/release-e2e/modules/executors/Invoke-RealProductPhase.psm1" if layout == "workspace" else "release-tooling/proof-entrypoints/Invoke-RealProductPhase.psm1"),
        "invokeWpfUiAutomationSha256": root / ("automation/release-e2e/modules/executors/Invoke-WpfUiAutomation.ps1" if layout == "workspace" else "release-tooling/proof-entrypoints/Invoke-WpfUiAutomation.ps1"),
        "wpfLaunchContractSha256": root / ("automation/release-e2e/modules/executors/WpfLaunchContract.psm1" if layout == "workspace" else "release-tooling/proof-entrypoints/WpfLaunchContract.psm1"),
    }
    config_path = root / "source/config/devfleet.config.json"
    proof_expected = {"repositoryHead": expected["repositoryHead"], "candidateCommit": expected["candidateCommit"], "shippingInputIdentity": expected["shippingInputIdentity"], "releaseFingerprint": expected["releaseFingerprintId"], "toolingFingerprint": expected["toolingFingerprintId"]}
    artifact_hashes = {name: str(row["sha256"]) for name, row in artifacts.items()}
    baseline = load_accepted_baseline(root, expected, artifact_hashes)
    for run_id_value in run_ids:
        run = proof_root / run_id_value
        if layout == "workspace" and not (run / "proof-start.json").is_file():
            raise ValueError(f"current proof run is missing: {run_id_value}")
        tx, lineage, role = validate_native_proof(run, config_path, sources, proof_expected, artifact_hashes, baseline)
        transactions.append(tx); lineages.append(lineage); roles.append(role)
    validate_proof_independence(run_ids, transactions, lineages, roles)
    return {
        "candidateTuple": expected,
        "artifacts": artifacts,
        "fullReleaseRunId": run_id,
        "fullRelease": {
            "runStateSha256": sha(run_state_path), "phaseRecordsSha256": sha(records_path),
            "realUseBindingSha256": real_use["bindingSha256"], "realUsePrepareSha256": real_use["prepareSha256"],
            "realUseReportSha256": real_use["reportSha256"], "realUseSummarySha256": sha(real_summary_path),
            "cleanupSha256": sha(full_root / "final-cleanup.json"), "postCleanupSha256": sha(full_root / "post-cleanup-finalization.json"),
            "l1Sha256": sha(full_root / "l1-terminal-state.json"), "l2Sha256": sha(full_root / "l2-terminal-state.json"),
        },
        "standardToken": standard,
        "proofRunIds": run_ids,
        "proofTransactions": transactions,
        "proofLineages": lineages,
        "proofRoles": roles,
    }


def _validate_release_audit(root: Path, expected: dict[str, str], full_release_run_id: str, layout: str, *, require_archive: bool, closure: dict[str, object] | None = None) -> dict[str, object]:
    pointer_path = root / "evidence/CURRENT-RELEASE-AUDIT.json"
    if not pointer_path.is_file():
        raise ValueError("CURRENT-RELEASE-AUDIT.json is missing")
    pointer = read_json(pointer_path)
    if (pointer.get("schemaVersion") != 1 or pointer.get("contract") != "devfleet-pre-acceptance-release-audit-v1"
            or pointer.get("status") != "PASS" or pointer.get("bundleMode") != "release"
            or pointer.get("releaseEligible") is not False or pointer.get("internalPromotionAllowed") is not False
            or pointer.get("publicPromotionAllowed") is not False or pointer.get("publicPublisherTrust") is not False):
        raise ValueError("pre-acceptance RELEASE audit pointer is not a fail-closed PASS")
    _assert_tuple(pointer.get("candidate"), expected, "pre-acceptance RELEASE audit")
    if pointer.get("fullReleaseRunId") != full_release_run_id:
        raise ValueError("pre-acceptance RELEASE audit is spliced to another FullRelease")
    if closure is not None and (pointer.get("standardTokenRunId") != closure["standardToken"]["runId"] or pointer.get("proofRunIds") != closure["proofRunIds"]):
        raise ValueError("pre-acceptance RELEASE audit standard-token/proof lineage is stale or spliced")
    audit_id = str(pointer.get("runId") or "")
    if not re.fullmatch(r"release-audit-[A-Za-z0-9-]+", audit_id):
        raise ValueError("pre-acceptance RELEASE audit RunId is malformed")
    evidence = pointer.get("evidence")
    if not isinstance(evidence, dict) or set(evidence) != {"archive", "report", "manifest", "releaseValidation"}:
        raise ValueError("pre-acceptance RELEASE audit evidence bindings are missing")
    checked: dict[str, Path] = {}
    for key in ("report", "manifest", "releaseValidation"):
        ref = evidence.get(key)
        if not isinstance(ref, dict):
            raise ValueError(f"pre-acceptance RELEASE audit binding is missing: {key}")
        relative = _layout_path(layout, str(ref.get("workspacePath") or ""), str(ref.get("bundlePath") or ""))
        checked[key] = _checked_file(root, relative, ref.get("sha256"), f"pre-acceptance RELEASE audit {key}", ref.get("bytes"))
    archive_ref = evidence.get("archive")
    if not isinstance(archive_ref, dict) or not re.fullmatch(r"[0-9a-f]{64}", str(archive_ref.get("sha256") or "")) or int(archive_ref.get("bytes", 0)) <= 0:
        raise ValueError("pre-acceptance RELEASE audit archive identity is malformed")
    archive_path: Path | None = None
    if require_archive:
        archive_relative = _layout_path(layout, str(archive_ref.get("workspacePath") or ""), str(archive_ref.get("bundlePath") or ""))
        archive_path = _checked_file(root, archive_relative, archive_ref.get("sha256"), "pre-acceptance RELEASE audit archive", archive_ref.get("bytes"))
    report = read_json(checked["report"])
    if (report.get("status") != "COMPLETE_FOR_AI_AUDIT" or report.get("bundleMode") != "release"
            or report.get("releaseEligible") is not True or report.get("modeVerification") != "PASS"
            or report.get("coherenceVerification") != "PASS" or report.get("secretScan") != "PASS"
            or report.get("internalPromotionAllowed") is not False or report.get("publicPromotionAllowed") is not False
            or report.get("publicPublisherTrust") is not False
            or int(report.get("expectedSourceCount", -1)) <= 0
            or int(report.get("expectedSourceCount", -1)) != int(report.get("includedSourceCount", -2))):
        raise ValueError("pre-acceptance RELEASE audit clean-extraction report is not PASS")
    if str(report.get("archiveSha256") or "").lower() != str(archive_ref.get("sha256") or "").lower() or int(report.get("archiveBytes", -1)) != int(archive_ref.get("bytes", -2)):
        raise ValueError("pre-acceptance RELEASE audit report does not bind its immutable archive")
    _assert_tuple(report.get("candidateTuple"), expected, "pre-acceptance RELEASE audit report")
    if report.get("fullReleaseRunId") != full_release_run_id or report.get("standardTokenRunId") != pointer.get("standardTokenRunId") or report.get("proofRunIds") != pointer.get("proofRunIds"):
        raise ValueError("pre-acceptance RELEASE audit report lineage is stale or spliced")
    checks = report.get("checks")
    if not isinstance(checks, dict) or any(value not in {"PASS", "SKIPPED"} for value in checks.values()) or checks.get("pythonCompile") != "PASS" or checks.get("powershellParse") != "PASS":
        raise ValueError("pre-acceptance RELEASE audit checks are incomplete")
    manifest = read_json(checked["manifest"])
    if (str(manifest.get("sha256") or "").lower() != str(archive_ref.get("sha256") or "").lower()
            or int(manifest.get("bytes", -1)) != int(archive_ref.get("bytes", -2))
            or manifest.get("selfTest") != "PASS"
            or int(manifest.get("expectedSourceCount", -1)) != int(manifest.get("includedSourceCount", -2))):
        raise ValueError("pre-acceptance RELEASE audit manifest does not bind the immutable archive")
    validation = read_json(checked["releaseValidation"])
    if (validation.get("status") != "PASS" or validation.get("bundleMode") != "pre-acceptance" or validation.get("releaseEligible") is not False
            or validation.get("fullReleaseRunId") != full_release_run_id
            or validation.get("standardTokenRunId") != pointer.get("standardTokenRunId")):
        raise ValueError("pre-acceptance release-bundle validation is not a non-promoting PASS")
    validation_tuple = validation.get("candidateTuple")
    _assert_tuple(validation_tuple, expected, "pre-acceptance release-bundle validation")
    if validation.get("proofRunIds") != pointer.get("proofRunIds"):
        raise ValueError("pre-acceptance release audit proof lineage is spliced")
    checks_summary = pointer.get("checks")
    required_checks = {"cleanExtraction": "PASS", "secrets": "PASS", "coherence": "PASS", "sourceCount": "PASS", "releaseValidation": "PASS"}
    if not isinstance(checks_summary, dict) or set(checks_summary) != set(required_checks) or any(checks_summary.get(key) != value for key, value in required_checks.items()):
        raise ValueError("pre-acceptance RELEASE audit check summary is incomplete")
    inputs = pointer.get("inputs")
    if not isinstance(inputs, dict) or inputs.get("proofRunIds") != pointer.get("proofRunIds"):
        raise ValueError("pre-acceptance RELEASE audit input bindings are missing")
    input_hash_keys = {"fullReleaseRunStateSha256", "fullReleasePhaseRecordsSha256", "realUseBindingSha256", "realUsePrepareSha256", "realUseReportSha256", "realUseSummarySha256", "cleanupSha256", "postCleanupSha256", "terminalL1Sha256", "terminalL2Sha256", "standardTokenPointerSha256"}
    if set(inputs) != input_hash_keys | {"proofRunIds"}:
        raise ValueError("pre-acceptance RELEASE audit input binding set is not exact")
    for key in input_hash_keys:
        if not re.fullmatch(r"[0-9a-f]{64}", str(inputs.get(key) or "")):
            raise ValueError(f"pre-acceptance RELEASE audit input hash is malformed: {key}")
    if closure is not None:
        expected_inputs = {
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
            "standardTokenPointerSha256": closure["standardToken"]["pointerSha256"],
        }
        if any(str(inputs.get(key) or "").lower() != str(value).lower() for key, value in expected_inputs.items()):
            raise ValueError("pre-acceptance RELEASE audit input hashes do not match current evidence")
    if archive_path is not None:
        # Re-run the independent clean-extraction validator over the exact
        # immutable archive. The stored prevalidation JSON is evidence, not a
        # substitute for validating the bytes again at acceptance time.
        live_validation = validate(archive_path, "pre-acceptance")
        for key in ("status", "bundleMode", "releaseEligible", "fullReleaseRunId", "standardTokenRunId", "proofRunIds"):
            if live_validation.get(key) != validation.get(key):
                raise ValueError(f"immutable RELEASE audit revalidation disagrees with stored result: {key}")
        _assert_tuple(live_validation.get("candidateTuple"), expected, "revalidated immutable RELEASE audit")
    gates = pointer.get("gates")
    required_gates = {"candidate": "PASS", "proofs": "2/2 PASS", "fullRelease": "PASS", "realUseAcceptance": "U01-U05 PASS", "maintenance": "5/5 PASS", "standardToken": "PASS", "reconcile": "PASS", "cleanup": "PASS", "l1": "OFF", "l2": "ABSENT", "releaseAudit": "PASS"}
    if not isinstance(gates, dict) or set(gates) != set(required_gates) or any(gates.get(key) != value for key, value in required_gates.items()):
        raise ValueError("pre-acceptance RELEASE audit gate summary is incomplete")
    return {"runId": audit_id, "pointerSha256": sha(pointer_path), "archiveSha256": str(archive_ref["sha256"]), "reportSha256": sha(checked["report"]), "manifestSha256": sha(checked["manifest"]), "releaseValidationSha256": sha(checked["releaseValidation"])}


def validate_final_acceptance(root: Path, layout: str = "workspace", final_path: Path | None = None) -> dict[str, object]:
    if layout not in {"workspace", "bundle"}:
        raise ValueError("final acceptance layout must be workspace or bundle")
    final_path = final_path.resolve() if final_path is not None else root / "evidence/FINAL-ACCEPTANCE.json"
    if layout != "workspace" and final_path != root / "evidence/FINAL-ACCEPTANCE.json":
        raise ValueError("a FINAL-ACCEPTANCE override is valid only for workspace pre-publication checks")
    if not final_path.is_file():
        raise ValueError("FINAL-ACCEPTANCE.json is missing")
    final = read_json(final_path)
    if (final.get("schemaVersion") != 1 or final.get("contract") != "devfleet-internal-final-acceptance-v1"
            or final.get("status") != "PASS" or final.get("releaseEligible") is not True
            or final.get("internalPromotionAllowed") is not True
            or final.get("publicPromotionAllowed") is not False or final.get("publicPublisherTrust") is not False):
        raise ValueError("FINAL-ACCEPTANCE does not assert the exact internal-only PASS contract")
    closure = _validate_current_release_evidence(root, layout)
    expected = closure["candidateTuple"]
    _assert_tuple(final.get("candidate"), expected, "FINAL-ACCEPTANCE")
    artifacts = final.get("candidate", {}).get("artifacts") if isinstance(final.get("candidate"), dict) else None
    if not isinstance(artifacts, dict) or set(artifacts) != {"exe", "tar", "portable", "installerSource"}:
        raise ValueError("FINAL-ACCEPTANCE artifact tuple is missing")
    for name, observed in artifacts.items():
        expected_row = closure["artifacts"][name]
        if not isinstance(observed, dict) or str(observed.get("sha256") or "") != str(expected_row["sha256"]) or int(observed.get("bytes", -1)) != int(expected_row["bytes"]):
            raise ValueError(f"FINAL-ACCEPTANCE artifact tuple mismatch: {name}")
    signing = final.get("candidate", {}).get("authenticode") if isinstance(final.get("candidate"), dict) else None
    if (not isinstance(signing, dict) or signing.get("status") != "PASS" or signing.get("signatureStatus") != "Valid"
            or signing.get("signerThumbprint") != "DE42CD7369A01E9357BDA13597C0173E5E703E9D"
            or signing.get("signerSubject") != "CN=DevFleet Private Personal Code Signing"
            or signing.get("codeSigningEkuVerified") is not True or signing.get("rsaBits") != 3072
            or signing.get("exactCertificateMatch") is not True or signing.get("privateKeyExported") is not False):
        raise ValueError("FINAL-ACCEPTANCE Authenticode identity is incomplete")
    if final.get("proofRunIds") != closure["proofRunIds"] or final.get("fullReleaseRunId") != closure["fullReleaseRunId"] or final.get("standardTokenRunId") != closure["standardToken"]["runId"]:
        raise ValueError("FINAL-ACCEPTANCE proof/FullRelease/standard-token lineage is stale or spliced")
    release_audit = _validate_release_audit(root, expected, str(closure["fullReleaseRunId"]), layout, require_archive=(layout == "workspace"), closure=closure)
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
        raise ValueError("FINAL-ACCE