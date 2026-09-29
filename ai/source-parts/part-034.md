# DevFleet source part 034

Full-source UTF-8 byte interval [1534500, 1581000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: fd3c2116e0beb802b83574b2b3db82e1d9c3775af9afb641fa91654298ed25b0

<!-- BEGIN SOURCE SLICE -->
identity(path, self.fixture, self.request["execution"])
        self.store.verify_owner(path, self.fixture)
        return meta

    def observe_runtime(self, *, running: bool, healthy: bool = False) -> dict[str, Any]:
        meta = self.identity()
        containers = self.probe.containers(self.fixture["projectId"])
        persistent: list[dict[str, Any]] = []
        for item in containers:
            labels = (item.get("Config") or {}).get("Labels") or {}
            require(isinstance(labels, dict), "CONTAINER_LABELS_INVALID")
            for key, label in LABELS.items():
                require(labels.get(label) == str(meta.get(key, "")), "CONTAINER_OWNERSHIP_MISMATCH")
            require(labels.get("com.docker.compose.project") == self.fixture["runtimeId"]
                    and labels.get("com.docker.compose.service"), "COMPOSE_IDENTITY_MISMATCH")
            require(SHA256.fullmatch(str(item.get("Id", ""))), "CONTAINER_ID_NOT_CANONICAL")
            if str(labels.get("com.docker.compose.oneoff", "")).lower() == "true":
                require(not (item.get("State") or {}).get("Running"), "TRANSIENT_WRITER_REMAINS")
                continue
            persistent.append(item)
        active = [item for item in persistent if (item.get("State") or {}).get("Running") is True]
        require(len(active) == (1 if running else 0), "PERSISTENT_WRITER_COUNT_MISMATCH")
        ui_page = self.ui.page(f"/projects/{self.fixture['slug']}")
        require(ui_page.project_states and ui_page.project_states == [("running" if running else "stopped")],
                "UI_RUNTIME_STATE_DISAGREES")
        require(meta.get("lifecycle_status") == ("running" if running else "stopped"), "BACKEND_RUNTIME_STATE_DISAGREES")
        if healthy:
            require(meta.get("health_status") == "healthy", "APPLICATION_NOT_HEALTHY")
        ids = []
        for item in active:
            observed = self.ui.json("/containers/" + item["Id"] + "/inspect")
            require(observed.get("Id") == item["Id"] and (observed.get("State") or {}).get("Running") is True,
                    "UI_CONTAINER_INSPECT_DISAGREES")
            if healthy:
                require((item.get("State") or {}).get("Health", {}).get("Status") == "healthy", "CONTAINER_NOT_HEALTHY")
            ids.append(item["Id"])
        return {"persistentContainerIds": ids, "persistentWriters": len(active), "healthy": healthy}

    def wait_healthy(self) -> dict[str, Any]:
        # Docker healthcheck is independent of the successful user health job.
        deadline = min(self.ui.deadline, self.ui.clock() + 180)
        while True:
            try:
                return self.observe_runtime(running=True, healthy=True)
            except AcceptanceError as exc:
                if exc.code not in {"CONTAINER_NOT_HEALTHY"} or self.ui.clock() >= deadline:
                    raise
                self.ui.sleep(min(1.0, max(0.0, deadline - self.ui.clock())))

    def assert_no_pending(self) -> None:
        for entry in self.state["operations"]:
            operation = self.ui.json("/ui/operations/" + entry["id"])
            require(operation.get("state") == entry["expectedState"], "ACCEPTANCE_OPERATION_PENDING_OR_CHANGED")

    def prepare(self, credentials: tuple[str, str]) -> None:
        require(not self.state["prepared"] and not self.fixture, "PREPARE_ALREADY_ATTEMPTED")
        self.state["preflight"] = self.probe.preflight(self.request)
        self.begin("U01")
        self.ui.login(*credentials)
        slug = "df-accept-" + hashlib.sha256(self.request["runId"].encode()).hexdigest()[:12]
        path = safe_child(self.store.workspaces, slug)
        require(not path.exists(), "FIXTURE_ALREADY_EXISTS")
        self.state["fixture"] = {"slug": slug, "originalPath": str(path), "recoveredPath": ""}
        self.save()
        self.operation("create", page="/?view=projects", route="/projects/create", project=slug,
                       fields={"slug": slug, "display_name": slug, "template": "generic", "target": "local",
                               "runtime_isolation": "container", "resource_profile": "small", "scale": "small",
                               "intent": "prototype", "profile": "balanced", "testing_level": "standard",
                               "git_url": "", "language": "", "framework": "", "pid_mode": "private", "pid_limit": "4096"})
        meta = self.store.metadata(path)
        require(PROJECT_ID.fullmatch(str(meta.get("project_id", ""))), "CREATED_PROJECT_ID_INVALID")
        self.fixture.update(projectId=meta["project_id"], runtimeId=meta.get("runtime_id", ""))
        self.store.verify_identity(path, self.fixture, self.request["execution"])
        require(meta.get("template") == "generic", "CREATED_TEMPLATE_MISMATCH")
        for asset in ("compose.yaml", ".devcontainer/devcontainer.json", ".devfleet/project.json",
                      ".devfleet/smoke-test.sh", ".devfleet/health-check.sh"):
            require((path / asset).is_file() and not (path / asset).is_symlink(), "TEMPLATE_ASSET_MISSING")
        owner = {"schemaVersion": 1, "runId": self.request["runId"], "slug": slug,
                 "projectId": meta["project_id"], "nonce": secrets.token_hex(24)}
        self.fixture["owner"] = owner
        sentinel = f"DevFleet real-use acceptance\nrun:{owner['runId']}\nnonce:{owner['nonce']}\n".encode()
        for name, data in ((OWNER_FILE, canonical(owner)), (SENTINEL_FILE, sentinel)):
            with (path / name).open("xb") as stream:
                stream.write(data)
        self.fixture["sentinelSha256"] = hashlib.sha256(sentinel).hexdigest()
        self.state["ledger"].append({"kind": "project", "path": str(path)})
        self.save()
        self.complete("U01", {"template": "generic", "projectId": meta["project_id"]})
        self.begin("U02")
        self.operation("start")
        self.operation("health")
        test = self.operation("test")
        require(SMOKE_TEXT in str(test.get("result", "")), "TEMPLATE_SMOKE_OUTPUT_MISSING")
        runtime = self.wait_healthy()
        self.complete("U02", runtime)
        self.begin("U03")
        self.operation("stop")
        self.observe_runtime(running=False)
        self.operation("start")
        self.operation("health")
        self.wait_healthy()
        self.assert_no_pending()
        self.state["serviceBeforeRestart"] = self.probe.service()
        self.state["prepared"] = True
        self.save()

    def backup_evidence(self, path: Path) -> dict[str, Any]:
        meta = self.store.verify_identity(path, self.fixture, self.request["execution"])
        require(meta.get("backup_status") == "verified", "PRODUCT_BACKUP_NOT_VERIFIED")
        evidence = self.store.verify_backup(meta, self.fixture)
        if evidence["path"] not in {entry["path"] for entry in self.state["ledger"]}:
            self.state["ledger"].append(evidence)
            self.save()
        return evidence

    def u04(self) -> None:
        self.begin("U04")
        self.identity()
        backup_root = self.store.runtime / "workspace-backups"
        self.state["backupBaseline"] = sorted(path.name for path in backup_root.iterdir()) if backup_root.is_dir() else []
        self.state["backupDiscoveryRequired"] = True
        self.save()
        result = self.operation("backup", page=f"/projects/{self.fixture['slug']}?tab=backups")
        try:
            receipt = json.loads(result["result"]) if isinstance(result.get("result"), str) else result["result"]
        except (KeyError, json.JSONDecodeError):
            raise AcceptanceError("BACKUP_RECEIPT_INVALID") from None
        # Even an insufficient durability receipt can have created a valid local
        # archive. Bind that fixture before rejecting Vault acceptance.
        immediate = self.backup_evidence(self.original())
        require(isinstance(receipt, dict) and receipt.get("ok") is True and receipt.get("backup_status") == "verified"
                and receipt.get("vault_upload_status") == "verified" and receipt.get("durability_level") == "vault",
                "VAULT_UPLOAD_NOT_VERIFIED")
        require(receipt.get("backup_id") == immediate["backupId"] and receipt.get("backup_sha256") == immediate["archiveSha256"],
                "BACKUP_RECEIPT_DISAGREES")
        self.state["quarantineUnverified"] = True
        self.save()
        quarantined = self.operation("quarantine", page=f"/projects/{self.fixture['slug']}?tab=isolate",
                                    fields={"confirm_quarantine": "true"})
        path = exact_returned_child(self.store.quarantine, quarantined.get("result"), "QUARANTINE_PATH_INVALID")
        require(re.fullmatch(r"[0-9]{8}-[0-9]{6}-" + re.escape(self.fixture["slug"]), path.name),
                "QUARANTINE_NAME_INVALID")
        self.store.verify_identity(path, self.fixture, self.request["execution"])
        self.store.verify_owner(path, self.fixture)
        require(not Path(self.fixture["originalPath"]).exists(), "QUARANTINE_ORIGINAL_REMAINS")
        self.state["ledger"].append({"kind": "quarantine", "path": str(path)})
        self.state["quarantineUnverified"] = False
        self.save()
        quarantine_backup = self.backup_evidence(path)
        require(not any((item.get("State") or {}).get("Running") for item in self.probe.containers(self.fixture["projectId"])),
                "QUARANTINED_RUNTIME_REMAINS")
        collision = safe_child(self.store.workspaces, self.fixture["slug"])
        collision.mkdir()
        marker = canonical({"runId": self.request["runId"], "nonce": self.fixture["owner"]["nonce"], "collision": True})
        with (collision / OWNER_FILE).open("xb") as stream:
            stream.write(marker)
        self.state["collisionSha256"] = hashlib.sha256(marker).hexdigest()
        self.save()
        try:
            failed = self.operation("restore-quarantine", page="/?view=settings", route="/quarantine/restore",
                                    fields={"name": path.name}, match_fields={"name": path.name},
                                    project=path.name, expected="failed")
            require("already exists" in str(failed.get("error", "")), "QUARANTINE_COLLISION_WRONG_FAILURE")
            require(list(collision.iterdir()) == [collision / OWNER_FILE]
                    and digest(collision / OWNER_FILE) == self.state["collisionSha256"], "COLLISION_WAS_MODIFIED")
            self.store.verify_owner(path, self.fixture)
        finally:
            self.remove_collision()
        self.operation("restore-quarantine", page="/?view=settings", route="/quarantine/restore",
                       fields={"name": path.name}, match_fields={"name": path.name}, project=path.name)
        require(not path.exists(), "QUARANTINE_RESTORE_SOURCE_REMAINS")
        self.identity()
        self.complete("U04", {"immediateBackup": immediate, "quarantineBackup": quarantine_backup,
                              "quarantineName": path.name, "sentinelSha256": self.fixture["sentinelSha256"]})

    def remove_collision(self) -> None:
        if not self.state.get("collisionSha256"):
            return
        path = safe_child(self.store.workspaces, self.fixture["slug"], exists=True)
        require(list(path.iterdir()) == [path / OWNER_FILE] and not (path / OWNER_FILE).is_symlink()
                and digest(path / OWNER_FILE) == self.state["collisionSha256"], "COLLISION_CLEANUP_REFUSED")
        (path / OWNER_FILE).unlink()
        path.rmdir()
        self.state.pop("collisionSha256")
        self.save()

    @contextlib.contextmanager
    def fixture_edit(self, relative: str, replacement: bytes):
        require(relative in {"compose.yaml", ".devfleet/ownership-lease.json"}, "FIXTURE_EDIT_NOT_ALLOWED")
        path = self.original() / relative
        require(path.is_file() and not path.is_symlink() and not path.parent.is_symlink(), "FIXTURE_EDIT_PATH_UNSAFE")
        original = path.read_bytes()
        require(len(original) < 65536, "FIXTURE_EDIT_SOURCE_TOO_LARGE")
        entry = {"relative": relative, "originalBase64": base64.b64encode(original).decode("ascii"),
                 "originalSha256": hashlib.sha256(original).hexdigest(), "replacementSha256": hashlib.sha256(replacement).hexdigest()}
        self.state["temporaryEdits"].append(entry)
        self.save()
        path.write_bytes(replacement)
        body_failure = None
        try:
            yield
        except BaseException as exc:
            body_failure = exc
            raise
        finally:
            try:
                require(not path.is_symlink() and digest(path) == entry["replacementSha256"], "FIXTURE_EDIT_CHANGED_EXTERNALLY")
                path.write_bytes(original)
                self.state["temporaryEdits"].remove(entry)
                self.save()
            except Exception as cleanup_exc:
                if body_failure is None:
                    raise
                self.record_failure(body_failure)
                self.record_failure(cleanup_exc, cleanup=True)

    def u05(self) -> None:
        self.begin("U05")
        before = self.identity()
        existing_names = {path.name for path in self.store.workspaces.iterdir()}
        # A failed or malformed return still requires explicit parent cleanup;
        # never silently claim that an unobserved recovery produced no files.
        self.state["recoveryUnverified"] = True
        self.save()
        result = self.operation("restore-vault", page=f"/projects/{self.fixture['slug']}?tab=backups")
        copy = self.store.verify_copy(result.get("result"), self.fixture, self.request["execution"])
        require(copy.name not in existing_names, "RESTORE_COPY_OVERWROTE_EXISTING_PATH")
        self.fixture["recoveredPath"] = str(copy)
        self.state["ledger"].append({"kind": "recovered-copy", "path": str(copy)})
        self.state["recoveryUnverified"] = False
        self.save()
        after = self.identity()
        require(all(before.get(key) == after.get(key) for key in ("project_id", "slug", "runtime_id", "deployment_id", "host_id")),
                "ORIGINAL_CHANGED_DURING_COPY")
        # The unadopted copy must be rejected synchronously, before admission to
        # the asynchronous worker pool. No positive action form exists for it.
        page = self.ui.page(f"/projects/{self.fixture['slug']}")
        require(page.csrf, "RECOVERED_COPY_PROBE_CSRF_MISSING")
        operations_before = self.store.operation_ids()
        copy_start_route = f"/projects/{copy.name}/start"
        rejected = self.ui.request("POST", copy_start_route, {"csrf_token": page.csrf})
        require(rejected.status == 409, "RECOVERED_COPY_START_NOT_REJECTED")
        operations_after = self.store.operation_ids()
        require(operations_before == operations_after, "RECOVERED_COPY_OPERATION_WAS_CREATED")
        copy_start = {"route": copy_start_route, "httpStatus": 409, "operationCreated": False,
                      "beforeInventorySha256": hashlib.sha256(canonical(operations_before)).hexdigest(),
                      "afterInventorySha256": hashlib.sha256(canonical(operations_after)).hexdigest()}
        self.store.verify_copy(str(copy), self.fixture, self.request["execution"])
        require(not any((item.get("State") or {}).get("Running") for item in self.probe.containers(self.fixture["projectId"])),
                "RECOVERED_COPY_STARTED_WRITER")
        compose = self.original() / "compose.yaml"
        text = compose.read_text(encoding="utf-8")
        # Existing harmless security corpus: unsupported execution field. This
        # never requests privileged mode, a host path, or any actual host resource.
        require(re.search(r"(?m)^  [A-Za-z0-9_-]+:\s*$", text), "GENERIC_COMPOSE_SHAPE_UNEXPECTED")
        edited = re.sub(r"(?m)^(  [A-Za-z0-9_-]+:\s*)$", r"\1\n    future_execution_field: true", text, count=1)
        with self.fixture_edit("compose.yaml", edited.encode("utf-8")):
            failed = self.operation("start", expected="failed")
            require("security analyzer" in str(failed.get("error", "")).lower(), "SECURITY_FIXTURE_WRONG_FAILURE")
            require(not self.probe.containers(self.fixture["projectId"]), "SECURITY_FIXTURE_CREATED_CONTAINER")
        lease = read_json(self.original() / ".devfleet" / "ownership-lease.json")
        foreign = {**lease, "active": True, "active_node": "df-accept-foreign-" + self.fixture["slug"][-12:]}
        with self.fixture_edit(".devfleet/ownership-lease.json", canonical(foreign)):
            failed = self.operation("start", expected="failed")
            require("ownership lease" in str(failed.get("error", "")).lower(), "OWNERSHIP_FIXTURE_WRONG_FAILURE")
            require(not self.probe.containers(self.fixture["projectId"]), "OWNERSHIP_FIXTURE_CREATED_CONTAINER")
        self.operation("start")
        self.operation("health")
        runtime = self.wait_healthy()
        self.store.verify_copy(str(copy), self.fixture, self.request["execution"])
        self.assert_no_pending()
        self.complete("U05", {**runtime, "recoveredPath": str(copy), "copyAdopted": False, "copyStart": copy_start,
                              "sentinelSha256": self.fixture["sentinelSha256"]})

    def resume(self, credentials: tuple[str, str]) -> None:
        require(self.state.get("prepared") is True and not self.state.get("resumed") and not self.state.get("failure"),
                "RESUME_NOT_PREPARED")
        require(self.state["cleanup"]["status"] == "NOT_RUN", "RESUME_ALREADY_CLEANED")
        preflight = self.probe.preflight(self.request)
        previous, current = self.state["serviceBeforeRestart"], preflight["service"]
        require(previous["bootId"] == current["bootId"], "UNEXPECTED_GUEST_REBOOT")
        require(previous["invocationId"] != current["invocationId"], "SERVICE_RESTART_NOT_OBSERVED")
        self.ui.login(*credentials)
        self.identity()
        self.operation("health")
        runtime = self.wait_healthy()
        self.assert_no_pending()
        self.complete("U03", {**runtime, "serviceBefore": previous, "serviceAfter": current,
                              "sentinelSha256": self.fixture["sentinelSha256"]})
        self.u04()
        self.u05()
        self.state["resumed"] = True
        self.save()

    def restore_edits(self) -> None:
        for edit in list(reversed(self.state["temporaryEdits"])):
            require(edit["relative"] in {"compose.yaml", ".devfleet/ownership-lease.json"}, "CLEANUP_EDIT_INVALID")
            path = self.original() / edit["relative"]
            require(path.is_file() and not path.is_symlink() and not path.parent.is_symlink(), "CLEANUP_EDIT_PATH_UNSAFE")
            original = base64.b64decode(edit["originalBase64"], validate=True)
            require(hashlib.sha256(original).hexdigest() == edit["originalSha256"], "CLEANUP_EDIT_HASH_INVALID")
            require(digest(path) in {edit["replacementSha256"], edit["originalSha256"]}, "CLEANUP_EDIT_CHANGED_EXTERNALLY")
            path.write_bytes(original)
            self.state["temporaryEdits"].remove(edit)
            self.save()

    def discover_backup_fixtures(self) -> None:
        """Account for an archive written before a broker/operation failure."""
        if not self.state.get("backupDiscoveryRequired"):
            return
        root = self.store.runtime / "workspace-backups"
        if not root.exists():
            return
        require(root.is_dir() and not root.is_symlink(), "CLEANUP_BACKUP_ROOT_UNSAFE")
        baseline = set(self.state["backupBaseline"])
        for directory in root.iterdir():
            if directory.name in baseline or not directory.name.startswith(self.fixture["slug"] + "-"):
                continue
            manifest = read_json(directory / "manifest.json")
            require(manifest.get("project_id") == self.fixture["projectId"] and manifest.get("slug") == self.fixture["slug"],
                    "CLEANUP_NEW_BACKUP_NOT_OWNED")
            meta = {"backup_id": directory.name, "backup_path": str(directory / (self.fixture["slug"] + ".tar.gz")),
                    "backup_sha256": manifest.get("workspace", {}).get("archive_sha256")}
            evidence = self.store.verify_backup(meta, self.fixture)
            if evidence["path"] not in {entry["path"] for entry in self.state["ledger"]}:
                self.state["ledger"].append(evidence)
                self.save()

    def cleanup(self) -> None:
        cleanup = self.state["cleanup"]
        if cleanup["status"] == "PASS":
            return
        require(self.fixture.get("projectId") and self.fixture.get("owner"), "CLEANUP_FIXTURE_NOT_BOUND")
        self.remove_collision()
        self.restore_edits()
        # Never delete a path while an accepted asynchronous operation can still
        # mutate it. A failed/expired operation is not evidence its worker died.
        for entry in self.state["operations"]:
            value = self.ui.json("/ui/operations/" + entry["id"])
            require(value.get("state") in {"completed", "failed"}, "CLEANUP_OPERATION_NOT_QUIESCENT")
        original = Path(self.fixture["originalPath"])
        if original.exists():
            self.identity()
            if self.probe.containers(self.fixture["projectId"]):
                # Cleanup is still an authenticated product operation, including
                # partially failed starts where the rendered stop button is absent.
                self.operation("stop", negative_fixture=True)
        require(not self.probe.containers(self.fixture["projectId"]), "CLEANUP_CONTAINERS_REMAIN")
        require(not self.state.get("recoveryUnverified"), "CLEANUP_UNVERIFIED_RECOVERY_REQUIRES_PARENT")
        require(not self.state.get("quarantineUnverified"), "CLEANUP_UNVERIFIED_QUARANTINE_REQUIRES_PARENT")
        self.discover_backup_fixtures()
        for entry in reversed(self.state["ledger"]):
            path = Path(entry["path"])
            if not path.exists():
                cleanup["resources"].append({"kind": entry["kind"], "path": str(path), "status": "ABSENT"})
                continue
            if entry["kind"] == "backup":
                require(path.parent == self.store.runtime / "workspace-backups" and not path.is_symlink(),
                        "CLEANUP_BACKUP_PATH_INVALID")
                manifest = read_json(path / "manifest.json")
                require(digest(path / "manifest.json") == entry["manifestSha256"]
                        and manifest.get("project_id") == self.fixture["projectId"]
                        and manifest.get("backup_id") == entry["backupId"], "CLEANUP_BACKUP_IDENTITY_MISMATCH")
                require(not any(item.is_symlink() for item in path.rglob("*")), "CLEANUP_TREE_SYMLINK_REJECTED")
                shutil.rmtree(path)
            else:
                self.store.remove_owned_tree(path, self.fixture)
            require(not path.exists(), "CLEANUP_RESOURCE_REMAINS")
            cleanup["resources"].append({"kind": entry["kind"], "path": str(path), "status": "REMOVED"})
            self.save()
        cleanup["status"] = "PASS"
        self.save()

    def record_failure(self, exc: BaseException, *, cleanup: bool = False) -> None:
        code = exc.code if isinstance(exc, AcceptanceError) else "UNEXPECTED_DRIVER_FAILURE"
        if cleanup:
            self.state["cleanupFailure"] = self.state["cleanupFailure"] or {"code": code}
            self.state["cleanup"]["status"] = "BLOCKED"
            self.state["cleanup"]["errors"].append(code)
        elif self.state["failure"] is None:
            self.state["failure"] = {"code": code, "journey": self.state["currentJourney"]}
            for row in self.state["journeys"]:
                if row["id"] == self.state["currentJourney"] and row["status"] != "PASS":
                    row["status"] = "BLOCKED"
        self.save()

    def report(self, stage: str) -> dict[str, Any]:
        passed = (self.state["resumed"] and self.state["cleanup"]["status"] == "PASS"
                  and not self.state["failure"] and not self.state["cleanupFailure"]
                  and all(row["status"] == "PASS" and row["assertions"] == {key: True for key in ASSERTIONS[row["id"]]}
                          for row in self.state["journeys"])
                  and {row["id"] for row in self.state["journeys"]} == set(ASSERTIONS)
                  and len(self.state["journeys"]) == 5)
        prepared = self.state["prepared"] and not self.state["failure"] and not self.state["cleanupFailure"] and stage == "prepare"
        fixture = {key: self.fixture[key] for key in ("slug", "projectId", "sentinelSha256", "originalPath", "recoveredPath")
                   if key in self.fixture}
        result = {
            "schemaVersion": 1, "contract": CONTRACT, "status": "PASS" if passed else "PREPARED" if prepared else "BLOCKED",
            "stage": stage, "runId": self.request["runId"], "phaseId": "REAL-USE-ACCEPTANCE",
            "candidate": self.request["candidate"],
            "execution": {**self.request["execution"], "uiTransport": "authenticated-http-form",
                          "browserJavascriptExercised": False},
            "runnerSha256": self.request["runnerSha256"], "startedAtUtc": self.state["startedAtUtc"],
            "finishedAtUtc": utc_now(), "deadlineUtc": self.request["deadlineUtc"],
            "journeys": self.state["journeys"], "operations": self.state["operations"], "fixture": fixture,
            "cleanup": self.state["cleanup"], "failure": self.state["failure"], "cleanupFailure": self.state["cleanupFailure"],
        }
        all_secrets = self.ui.secret_values + self.ui.transport.secrets()
        return redact(result, all_secrets)

    def execute(self, stage: str, credentials: tuple[str, str]) -> dict[str, Any]:
        try:
            if stage == "prepare":
                self.prepare(credentials)
            elif stage == "resume":
                self.resume(credentials)
            else:
                self.probe.preflight(self.request)
                self.ui.login(*credentials)
        except Exception as exc:
            self.record_failure(exc)
        if stage != "prepare" or self.state["failure"]:
            try:
                if self.fixture.get("projectId") and self.fixture.get("owner"):
                    self.cleanup()
                elif self.fixture:
                    raise AcceptanceError("CLEANUP_PARTIAL_CREATE_REQUIRES_PARENT")
            except Exception as exc:
                self.record_failure(exc, cleanup=True)
        return self.report(stage)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, choices=("prepare", "resume", "cleanup"))
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    result: dict[str, Any]
    try:
        require(args.input.resolve() not in {args.state.resolve(), args.output.resolve()}
                and args.state.resolve() != args.output.resolve(), "INPUT_OUTPUT_PATH_COLLISION")
        request = normalized_request(read_json(args.input), digest(Path(__file__)))
        require(args.stage != "prepare" or not args.state.exists(), "PREPARE_STATE_ALREADY_EXISTS")
        state = read_json(args.state) if args.stage != "prepare" else None
        dashboard = Dashboard(HttpTransport(request["baseUrl"]), instant(request["deadlineUtc"]))
        runner = AcceptanceRunner(request, args.state, dashboard, NativeProbe(), state=state)
        credentials = (os.environ.get("DEVFLEET_ADMIN_USER", ""), os.environ.get("DEVFLEET_ADMIN_PASSWORD", ""))
        result = runner.execute(args.stage, credentials)
    except Exception as exc:
        result = {"schemaVersion": 1, "contract": CONTRACT, "status": "BLOCKED", "stage": args.stage,
                  "phaseId": "REAL-USE-ACCEPTANCE",
                  "failure": {"code": exc.code if isinstance(exc, AcceptanceError) else "DRIVER_INITIALIZATION_FAILED"},
                  "cleanup": {"status": "NOT_RUN", "ownedOnly": True}}
    try:
        write_json(args.output, result)
    except Exception:
        # No traceback, command line, secret-containing response or raw exception.
        print(json.dumps({"status": "BLOCKED", "failure": {"code": "EVIDENCE_WRITE_FAILED"}}))
        return 1
    print(json.dumps({"status": result["status"], "contract": CONTRACT, "stage": args.stage,
                      "evidenceSha256": digest(args.output)}, sort_keys=True))
    return 0 if result["status"] in {"PASS", "PREPARED"} else 1


if __name__ == "__main__":
    raise SystemExit(main())

```


## FILE: automation/release-e2e/modules/executors/Invoke-SecurityPoisonPhase.ps1

SHA256: 38c5bd51d2b597f37d3cf5df55fe821c9d0064bcb6b601853b8e3fd4fae63821 | Bytes: 5408 | Git mode: 100644

```
[CmdletBinding()]
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
$ErrorActionPreference='Stop'
$context=$ContextJson|ConvertFrom-Json -ErrorAction Stop
$workspace=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$candidatePath=[string]$context.candidate.candidate.path
$candidateItem=Get-Item -LiteralPath $candidatePath -ErrorAction Stop
$candidateSha=(Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
if($candidateSha -ne [string]$context.candidate.candidate.sha256 -or [int64]$candidateItem.Length -ne [int64]$context.candidate.candidate.bytes){throw 'Security-Poison exact candidate changed before adversarial execution.'}
$candidateTuple=[ordered]@{releaseFingerprintId=[string]$context.candidate.releaseFingerprintId;toolingFingerprintId=[string]$context.candidate.toolingFingerprintId;gitCommit=[string]$context.candidate.gitCommit;exeSha256=$candidateSha;exeBytes=[int64]$candidateItem.Length}
$runDir=[string]$context.runDir;New-Item -ItemType Directory -Force -Path $runDir|Out-Null
$python=if(Test-Path -LiteralPath (Join-Path $workspace '.venv-test\Scripts\python.exe')){(Join-Path $workspace '.venv-test\Scripts\python.exe')}else{(Get-Command python.exe -ErrorAction Stop).Source}
$scenarioDefinitions=@(
    [ordered]@{id='DEPENDENCY-TRUST';command='tests/test_installed_dependency_authenticity.py tests/test_v1211_release_contract.py';reason='canonical redirect and exact signer policy plus bootstrap boundary tests'},
    [ordered]@{id='PROVISIONING-OWNERSHIP';command='automation/release-e2e/tests/Test-SecurityPoisonHostAgent.ps1';reason='real inter-process registry stress and same-name collision fixture'},
    [ordered]@{id='HOST-AGENT-PROTOCOL';command='tests/test_host_transport.py tests/test_host_agent_integration.py';reason='real local signed endpoint, tamper binding, and authenticated error responses'},
    [ordered]@{id='PROJECT-MUTATION-AUTHORITY';command='tests/test_project_safety.py tests/test_v126_dynamic_vm_hotfix.py';reason='missing/foreign identity and address-only readiness fail-closed tests'},
    [ordered]@{id='SSH-READINESS';command='tests/test_v126_dynamic_vm_hotfix.py tests/test_v124_vm_creation_ssh.py';reason='proof-bearing connection state is required before workspace readiness'},
    [ordered]@{id='SECURITY-CONFIGURATION';command='tests/test_security_config.py tests/test_configuration.py';reason='malformed and unsafe policy fixtures fail closed'},
    [ordered]@{id='PACKAGE-WATCHDOG';command='tests/test_verify_package_watchdog.py';reason='timeout, descendant termination, and bounded output fixtures'}
)
function Initialize-DevFleetSecurityPoisonProcessEnvironment {
    if([string]::IsNullOrWhiteSpace([string]$env:COMPUTERNAME)){
        $computerName=[Environment]::MachineName
        if([string]::IsNullOrWhiteSpace($computerName)){throw 'Native machine identity is unavailable for SECURITY-POISON child execution.'}
        $env:COMPUTERNAME=$computerName
    }
    if([string]::IsNullOrWhiteSpace([string]${env:ProgramFiles(x86)})){
        $programFilesX86=[Environment]::GetFolderPath('ProgramFilesX86')
        if([string]::IsNullOrWhiteSpace($programFilesX86)){throw 'Native Program Files (x86) path is unavailable for SECURITY-POISON child execution.'}
        ${env:ProgramFiles(x86)}=$programFilesX86
    }
}
Import-Module (Join-Path $PSScriptRoot '..\Evidence.psm1') -Force
$records=[Collections.Generic.List[object]]::new()
foreach($scenario in $scenarioDefinitions){
    $started=(Get-Date).ToUniversalTime().ToString('o');$output=@();$exit=0;$command=[string]$scenario.command
    if($scenario.id -eq 'PROVISIONING-OWNERSHIP'){
        Initialize-DevFleetSecurityPoisonProcessEnvironment
        $output=& pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $workspace $command) -WorkspaceRoot $workspace 2>&1;$exit=$LASTEXITCODE
    }else{
        $paths=@($command -split '\s+')
        Push-Location (Join-Path $workspace 'source');try{$output=& $python -m pytest -q @paths 2>&1;$exit=$LASTEXITCODE}finally{Pop-Location}
    }
    $text=($output|ForEach-Object{[string]$_}) -join "`n"
    $records.Add([ordered]@{id=$scenario.id;status=if($exit -eq 0){'PASS'}else{'FAIL'};exitCode=$exit;startedAt=$started;completedAt=(Get-Date).ToUniversalTime().ToString('o');testCommand=$command;reason=$scenario.reason;outputExcerpt=if($text.Length -gt 4000){$text.Substring($text.Length-4000)}else{$text}})
    $allPassed=($exit -eq 0 -and $records.Count -eq $scenarioDefinitions.Count)
    $evidence=[ordered]@{schemaVersion=1;status=if($exit -ne 0){'FAIL'}elseif($allPassed){'REAL E2E PASS'}else{'IN_PROGRESS'};phase='SECURITY-POISON';candidate=$candidateTuple;fixturePolicy=[ordered]@{malware=$false;credentialsAccessed=$false;productionMutation=$false;resources='temporary test roots and loopback endpoint only'};scenarios=@($records);allRequiredScenariosPassed=$allPassed}
    $evidencePath=Join-Path $runDir 'SECURITY-POISON-evidence.json'
    try { Write-EvidenceJson -Path $evidencePath -Value $evidence }
    catch {
        if($exit -ne 0){throw "SECURITY-POISON scenario $($scenario.id) failed with exit $exit; its evidence could not be persisted."}
        throw
    }
    if($exit -ne 0){throw "SECURITY-POISON scenario $($scenario.id) failed. Evidence has been retained under $runDir."}
}
$evidence|ConvertTo-Json -Depth 16 -Compress

```


## FILE: automation/release-e2e/modules/executors/Invoke-TailscalePhase.ps1

SHA256: b01b6c2141955adb2c9544ecf9ab4d7d4ce3322ec01e62bfffd20009e216da95 | Bytes: 234 | Git mode: 100644

```
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
Import-Module (Join-Path $PSScriptRoot 'Invoke-RealProductPhase.psm1') -Force
Invoke-RealProductPhase -ContextJson $ContextJson | ConvertTo-Json -Depth 32 -Compress

```


## FILE: automation/release-e2e/modules/executors/Invoke-WpfPhase.ps1

SHA256: b01b6c2141955adb2c9544ecf9ab4d7d4ce3322ec01e62bfffd20009e216da95 | Bytes: 234 | Git mode: 100644

```
param([string]$ContextJson = $env:DEVFLEET_FULLRELEASE_CONTEXT_JSON)
Import-Module (Join-Path $PSScriptRoot 'Invoke-RealProductPhase.psm1') -Force
Invoke-RealProductPhase -ContextJson $ContextJson | ConvertTo-Json -Depth 32 -Compress

```


## FILE: automation/release-e2e/modules/executors/Invoke-WpfUiAutomation.ps1

SHA256: bc6fe36716dc608d213d08abab8c61082f9f68b0dfe9e680e874222bcec2b44a | Bytes: 35816 | Git mode: 100644

```
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExePath,
    [Parameter(Mandatory)][string]$Action,
    [string]$Role = 'Primary / Desktop',
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$StartedPath,
    [string]$CheckpointPath,
    [string]$WorkerResultPath,
    [Parameter(Mandatory)][string]$LaunchRequestPath,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$LaunchId,
    [AllowEmptyString()][string]$TransactionId = '',
    [Parameter(Mandatory)][string]$PayloadSha256,
    [Parameter(Mandatory)][ValidateSet('direct','initial','resume','fallback')][string]$LaunchMode,
    [Parameter(Mandatory)][string]$ObserverDeadlineUtc,
    [Parameter(Mandatory)][int]$ExpectedInteractiveSessionId,
    [switch]$AllowMutation,
    [switch]$AllowRebootRequired,
    [switch]$UseDurableCompletionFallback,
    [switch]$ElevatedResume,
    [switch]$ContractProbe,
    [switch]$WorkerMode,
    [int]$CandidateProcessId,
    [string]$ExpectedCandidateStartUtc
)

$ErrorActionPreference = 'Stop'
$contractModule = Join-Path $PSScriptRoot 'WpfLaunchContract.psm1'
$driverPid = [int]$PID
$driverSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
$candidateHash = ''
$candidateArguments = @()
$process = $null
$cleanupDisposition = 'NONE'
$sequence = 0
$semanticProgressSequence = 0
$specification = $null

function Write-BootstrapAtomicJson([string]$Path, [object]$Value) {
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 24) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Read-BootstrapLaunchSpecification([string]$Path, [string]$DeadlineUtc) {
    # PowerShell Direct can start the registered task just before the atomic
    # launch-request move becomes visible in the task's interactive session.
    # Wait only for that bounded visibility condition; the immutable binding
    # and all hash/identity checks still run after the exact request is read.
    $waitDeadline = [DateTime]::UtcNow.AddSeconds(15)
    try {
        $observerDeadline = ([DateTimeOffset]::Parse($DeadlineUtc)).UtcDateTime
        if ($observerDeadline.AddSeconds(-1) -lt $waitDeadline) { $waitDeadline = $observerDeadline.AddSeconds(-1) }
    } catch {}
    $lastReadError = $null
    do {
        try {
            if (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop) {
                return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop)
            }
        } catch { $lastReadError = $_.Exception.Message }
        if ([DateTime]::UtcNow -ge $waitDeadline) { break }
        Start-Sleep -Milliseconds 100
    } while ($true)
    if ($lastReadError) { throw "Launch request was not readable before the bounded bootstrap deadline: $lastReadError" }
    throw "Launch request did not become visible before the bounded bootstrap deadline: $Path"
}

try {
    $specification = Read-BootstrapLaunchSpecification -Path $LaunchRequestPath -DeadlineUtc $ObserverDeadlineUtc
    $candidateHash = [string]$specification.candidateSha256
    Import-Module $contractModule -Force -ErrorAction Stop
} catch {
    $bootstrapError = $_.Exception.Message
    try {
        Write-BootstrapAtomicJson -Path $OutputPath -Value ([ordered]@{
            schemaVersion=2; contract='devfleet-wpf-terminal-v2'; status='OBSERVER_FAILURE'; terminal=$true; completionVerified=$false;
            failureClass='DRIVER_BOOTSTRAP_FAILURE'; error="WPF driver bootstrap failed before contract binding: $bootstrapError";
            runId=$RunId; launchId=$LaunchId; transactionId=$TransactionId; payloadSha256=$PayloadSha256; candidateSha256=$candidateHash;
            sequence=1; phase='DRIVER_BOOTSTRAP'; lastDurableStep='TASK_PROCESS_STARTED'; launchMode=$LaunchMode; elevatedResume=[bool]$ElevatedResume;
            action=$Action; role=$Role; driverPid=$driverPid; driverSessionId=$driverSessionId; processId=$null; candidateArguments=@();
            mutationInvoked=$false; productStarted=$false; cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER'; deadlineUtc=$ObserverDeadlineUtc;
            contractModulePath=$contractModule; timestampUtc=(Get-Date).ToUniversalTime().ToString('o')
        })
    } catch {}
    exit 2
}

function Get-ProcessIdentityEvidence([int]$Id, [int]$ExpectedSessionId) {
    try {
        $row = Get-CimInstance Win32_Process -Filter "ProcessId=$Id" -ErrorAction Stop
        if (-not $row) { return $null }
        $owner = Invoke-CimMethod -InputObject $row -MethodName GetOwner -ErrorAction Stop
        $processInfo = Get-Process -Id $Id -ErrorAction Stop
        if ([int]$processInfo.SessionId -ne $ExpectedSessionId) { return $null }
        return [ordered]@{present=$true;pid=$Id;user=[string]$owner.User;domain=[string]$owner.Domain;owner=([string]$owner.Domain+'\'+[string]$owner.User);sessionId=[int]$processInfo.SessionId}
    } catch { return $null }
}

function Write-BoundaryCheckpoint([string]$Phase, [string]$Status, [hashtable]$Detail) {
    $script:sequence++
    $entry = [ordered]@{
        schemaVersion=2; contract='devfleet-wpf-checkpoint-v2'; runId=$RunId; launchId=$LaunchId; transactionId=$TransactionId;
        payloadSha256=$PayloadSha256; candidateSha256=$script:candidateHash; sequence=$script:sequence; phase=$Phase; status=$Status;
        deadlineUtc=$ObserverDeadlineUtc; timestampUtc=(Get-Date).ToUniversalTime().ToString('o')
    }
    if ($Detail) { foreach ($key in $Detail.Keys) { $entry[$key] = $Detail[$key] } }
    if ($CheckpointPath) { Write-WpfAtomicJson -Path $CheckpointPath -Value $entry }
    return [pscustomobject]$entry
}

function New-MinimalTerminal([string]$Status, [string]$FailureClass, [string]$ErrorMessage, [string]$LastStep) {
    $script:sequence++
    return [pscustomobject][ordered]@{
        schemaVersion=2; contract='devfleet-wpf-terminal-v2'; status=$Status; terminal=$true; completionVerified=$false;
        failureClass=$FailureClass; error=$ErrorMessage; runId=$RunId; launchId=$LaunchId; transactionId=$TransactionId;
        payloadSha256=$PayloadSha256; candidateSha256=$script:candidateHash; sequence=$script:sequence; phase='WPF'; lastDurableStep=$LastStep;
        launchMode=$LaunchMode; elevatedResume=[bool]$ElevatedResume; action=$Action; role=$Role; driverPid=$driverPid;
        driverSessionId=$driverSessionId; processId=if($script:process){[int]$script:process.Id}else{$null};
        candidateArguments=@($script:candidateArguments); cleanupDisposition='RELINQUISH_LIFECYCLE_OWNER';
        deadlineUtc=$ObserverDeadlineUtc; timestampUtc=(Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-MinDeadline([datetime]$Maximum) {
    $absolute = ConvertTo-WpfUtcInstant $ObserverDeadlineUtc
    if ($absolute -lt $Maximum) { return $absolute }
    return $Maximum
}

function Read-ObservedJsonFile([string]$Path,[ValidateSet('TERMINAL','PROGRESS')][string]$Kind) {
    try {
        # The worker publishes these files with an atomic replace while the
        # supervisor polls them.  A short-lived access-denied from the guest
        # filesystem must remain an absent observation; the bounded watchdog
        # below will retry and will still terminalize on its deadline.
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop)) { return $null }
        $value = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return [pscustomobject][ordered]@{contract='devfleet-wpf-file-observation-v1';kind=$Kind;value=$value;fileWriteUtc=$item.LastWriteTimeUtc.ToString('o')}
    } catch { return $null }
}

$actualBinding = @{
    ExePath=$ExePath;Action=$Action;Role=$Role;OutputPath=$OutputPath;StartedPath=$StartedPath;CheckpointPath=$CheckpointPath;
    WorkerResultPath=$WorkerResultPath;LaunchRequestPath=$LaunchRequestPath;RunId=$RunId;LaunchId=$LaunchId;TransactionId=$TransactionId;
    PayloadSha256=$PayloadSha256;LaunchMode=$LaunchMode;ObserverDeadlineUtc=$ObserverDeadlineUtc;
    ExpectedInteractiveSessionId=$ExpectedInteractiveSessionId;AllowMutation=[bool]$AllowMutation;AllowRebootRequired=[bool]$AllowRebootRequired;
    UseDurableCompletionFallback=[bool]$UseDurableCompletionFallback;ElevatedResume=[bool]$ElevatedResume;ContractProbe=[bool]$ContractProbe;
    ContractModulePath=$contractModule
}

if (-not $WorkerMode) {
    try {
        Assert-WpfDriverBinding -Specification $specification -Actual $actualBinding | Out-Null
        $candidateHash = [string]$specification.candidateSha256
        $candidateArguments = @($specification.candidateArguments | ForEach-Object { [string]$_ })
        if ($ContractProbe) {
            Write-WpfAtomicJson -Path $OutputPath -Value ([ordered]@{
                schemaVersion=2;status='CONTRACT_PROBE_PASS';terminal=$false;completionVerified=$false;runId=$RunId;launchId=$LaunchId;
                transactionId=$TransactionId;payloadSha256=$PayloadSha256;candidateSha256=$candidateHash;launchMode=$LaunchMode;
                elevatedResume=[bool]$ElevatedResume;candidateArguments=@($candidateArguments);driverPid=$driverPid;driverSessionId=$driverSessionId
            })
            exit 0
        }
        if ($driverSessionId -ne $ExpectedInteractiveSessionId -or $driverSessionId -eq 0) { throw 'WPF supervisor did not bind to the expected interactive session.' }
        $bound = Write-BoundaryCheckpoint -Phase 'DRIVER_BOUND' -Status 'PASS' -Detail @{driverPid=$driverPid;driverSessionId=$driverSessionId;driverSha256=[string]$specification.driverSha256;launchMode=$LaunchMode;elevatedResume=[bool]$ElevatedResume}
        if ($StartedPath) { Write-WpfAtomicJson -Path $StartedPath -Value $bound }

        $process = Start-Process -FilePath $ExePath -ArgumentList (ConvertTo-WpfCommandLine -Tokens $candidateArguments) -PassThru
        Start-Sleep -Milliseconds 200
        $process.Refresh()
        $processStartUtc = $process.StartTime.ToUniversalTime().ToString('o')
        if ($process.SessionId -ne $ExpectedInteractiveSessionId -or $process.SessionId -eq 0) { throw 'Exact candidate launched outside the expected interactive session.' }
        $candidateIdentity = Get-ProcessIdentityEvidence -Id $process.Id -ExpectedSessionId $ExpectedInteractiveSessionId
        if (-not $candidateIdentity) { throw 'Exact candidate launch identity could not be proven.' }
        $launchAck = Write-BoundaryCheckpoint -Phase 'LAUNCH_ACKNOWLEDGED' -Status 'PASS' -Detail @{
            processId=[int]$process.Id;processStartTime=$processStartUtc;sessionId=[int]$process.SessionId;candidateIdentity=$candidateIdentity;
            candidatePath=$ExePath;can