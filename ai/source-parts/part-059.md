# DevFleet source part 059

Full-source UTF-8 byte interval [2697000, 2743500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 7fcc0318e9ef4b218eef7368f43e0c576e2b427f6e501cd41c3966c856308846

<!-- BEGIN SOURCE SLICE -->
Property("stage").GetString() == item.name;
                } catch { return false; }
            })
            .Select(item => item.name)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static string ResumeStage(IEnumerable<string> completedStages)
    {
        var completed = completedStages.ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (completed.Count == 0) return "bootstrap-entrypoint";
        if (!completed.Any(x => x.Equals("stage-prereqs-Desktop", StringComparison.OrdinalIgnoreCase) || x.Equals("stage-prereqs-Laptop", StringComparison.OrdinalIgnoreCase))) return "prerequisites";
        if (!completed.Contains("stage-host-agent")) return "host-agent";
        if (completed.Contains("stage-prereqs-Laptop"))
        {
            if (!completed.Contains("stage-compute-devfleet-failover")) return "compute-devfleet-failover";
            if (!completed.Contains("stage-vault")) return "vault";
        }
        else if (!completed.Contains("stage-compute-devfleet-primary")) return "compute-devfleet-primary";
        return "finalize";
    }

    private static void ValidateCompletedStages(JsonElement root, string role, out string[] completedStages)
    {
        completedStages = root.TryGetProperty("completedStages", out var stages)
            ? stages.EnumerateArray().Select(x => x.GetString() ?? "").ToArray()
            : [];
        var normalizedRole = role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
        var allowed = normalizedRole == "Desktop"
            ? new Regex("^stage-(prereqs-Desktop|windows-tailscale|host-agent|compute-devfleet-primary)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase)
            : new Regex("^stage-(prereqs-Laptop|windows-tailscale|host-agent|compute-devfleet-failover|vault)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
        if (completedStages.Any(x => string.IsNullOrWhiteSpace(x) || !allowed.IsMatch(x) || x.Contains(System.IO.Path.DirectorySeparatorChar) || x.Contains(System.IO.Path.AltDirectorySeparatorChar)) ||
            completedStages.Length != completedStages.Distinct(StringComparer.OrdinalIgnoreCase).Count())
            throw new InvalidDataException("A reboot checkpoint contains invalid or duplicate completed stage identities.");
        var completed = completedStages.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var prereq = $"stage-prereqs-{normalizedRole}";
        if (completed.Contains("stage-host-agent") && !completed.Contains(prereq) ||
            completed.Any(x => x.StartsWith("stage-compute-", StringComparison.OrdinalIgnoreCase) || x.Equals("stage-vault", StringComparison.OrdinalIgnoreCase)) && !completed.Contains("stage-host-agent"))
            throw new InvalidDataException("A reboot checkpoint contains out-of-order completed stage progress.");
        var expected = ResumeStage(completedStages);
        var stored = root.TryGetProperty("resumeStage", out var stage) ? stage.GetString() : null;
        if (!string.Equals(stored, expected, StringComparison.Ordinal)) throw new InvalidDataException("A reboot checkpoint has inconsistent durable stage progress.");
    }

    private static void ValidateIdentity(JsonElement root, InstallerPlan plan, string role, bool requirePlanTransaction, out string transactionId, out int generation, out bool acknowledgeRootfulDocker)
    {
        var state = root.GetProperty("state").GetString();
        var action = root.GetProperty("action").GetString();
        var checkpointRole = root.GetProperty("role").GetString();
        var payload = root.GetProperty("payloadSha256").GetString();
        transactionId = root.GetProperty("transactionId").GetString() ?? "";
        generation = root.GetProperty("checkpointGeneration").GetInt32();
        var installerVersion = root.GetProperty("installerVersion").GetString();
        var devFleetVersion = root.GetProperty("devFleetVersion").GetString();
        var declaredMaximum = root.GetProperty("maxRebootBoundaries").GetInt32();
        if (!root.TryGetProperty("acknowledgeRootfulDocker", out var acknowledgement) || acknowledgement.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new InvalidDataException("A reboot checkpoint omitted its reviewed rootful Docker acknowledgement state.");
        acknowledgeRootfulDocker = acknowledgement.GetBoolean();
        var generationOk = generation >= 1 && generation <= MaxRebootBoundaries;
        if (state != "waiting-for-reboot" || action != plan.Mode.ToString() || !string.Equals(checkpointRole, role, StringComparison.OrdinalIgnoreCase) || !string.Equals(payload, PayloadManifest.PayloadSha256, StringComparison.OrdinalIgnoreCase) || !string.Equals(installerVersion, PayloadManifest.InstallerVersion, StringComparison.Ordinal) || !string.Equals(devFleetVersion, PayloadManifest.DevFleetVersion, StringComparison.Ordinal) || declaredMaximum != MaxRebootBoundaries || !generationOk || !Regex.IsMatch(transactionId, "^[0-9a-f]{32}$", RegexOptions.CultureInvariant) || (requirePlanTransaction && (!string.Equals(transactionId, plan.TransactionId, StringComparison.Ordinal) || acknowledgeRootfulDocker != plan.AcknowledgeRootfulDocker)) || File.Exists(ConsumedPath(transactionId)))
            throw new InvalidDataException("A stale, tampered, or candidate-mismatched reboot checkpoint is present; refusing resume.");
        ValidateCompletedStages(root, role, out _);
    }

    public static void Write(InstallerPlan plan, string role, string? recovery, Action<string>? progress = null)
    {
        var generation = 1;
        var createdUtc = DateTime.UtcNow.ToString("O");
        if (File.Exists(Path))
        {
            using var prior = JsonDocument.Parse(File.ReadAllText(Path));
            ValidateIdentity(prior.RootElement, plan, role, requirePlanTransaction: true, out _, out var previousGeneration, out _);
            generation = previousGeneration + 1;
            if (prior.RootElement.TryGetProperty("createdUtc", out var created) && created.GetString() is { Length: > 0 } value) createdUtc = value;
        }
        if (generation > MaxRebootBoundaries) throw new InvalidOperationException($"DevFleet installation exceeded the supported reboot boundary limit ({MaxRebootBoundaries}); refusing another reboot.");
        var completedStages = ReadCompletedStages(plan, role);
        var resumeStage = ResumeStage(completedStages);
        StateStore.WriteJsonAtomically(Path, new { state = "waiting-for-reboot", action = plan.Mode.ToString(), plan.TransactionId, installerVersion = PayloadManifest.InstallerVersion, devFleetVersion = PayloadManifest.DevFleetVersion, payloadSha256 = PayloadManifest.PayloadSha256, role, acknowledgeRootfulDocker = plan.AcknowledgeRootfulDocker, completedStages, resumeStage, recoveryPath = recovery, checkpointGeneration = generation, maxRebootBoundaries = MaxRebootBoundaries, createdUtc, updatedUtc = DateTime.UtcNow.ToString("O") });
        progress?.Invoke($"Safe reboot checkpoint persisted: {Path}");
    }

    public static bool ValidateIfPresent(InstallerPlan plan, string role, Action<string>? progress = null)
    {
        if (!File.Exists(Path)) return false;
        using var document = JsonDocument.Parse(File.ReadAllText(Path));
        var root = document.RootElement;
        ValidateIdentity(root, plan, role, requirePlanTransaction: true, out _, out _, out _);
        ValidateActiveTransaction(plan, role);
        progress?.Invoke("Verified durable reboot checkpoint; resuming the same action and candidate without clearing recovery state.");
        return true;
    }

    public static bool BindPlanIfPresent(InstallerPlan plan, string role, Action<string>? progress = null)
    {
        if (!File.Exists(Path)) return false;
        using var document = JsonDocument.Parse(File.ReadAllText(Path));
        var root = document.RootElement;
        var transactionId = root.GetProperty("transactionId").GetString() ?? "";
        ValidateIdentity(root, plan, role, requirePlanTransaction: false, out _, out _, out var acknowledgeRootfulDocker);
        plan.TransactionId = transactionId;
        plan.AcknowledgeRootfulDocker = acknowledgeRootfulDocker;
        ValidateActiveTransaction(plan, role);
        progress?.Invoke("Bound the reviewed plan to the durable reboot transaction and generation.");
        return true;
    }

    public static void Consume(InstallerPlan plan, string role, Action<string>? progress = null)
    {
        if (!File.Exists(Path)) return;
        using var document = JsonDocument.Parse(File.ReadAllText(Path));
        var root = document.RootElement;
        var transactionId = root.GetProperty("transactionId").GetString() ?? "";
        var generation = root.GetProperty("checkpointGeneration").GetInt32();
        if (!Regex.IsMatch(transactionId, "^[0-9a-f]{32}$", RegexOptions.CultureInvariant) || generation < 1 || generation > MaxRebootBoundaries) throw new InvalidDataException("Refusing to consume an invalid reboot checkpoint identity.");
        ValidateIdentity(root, plan, role, requirePlanTransaction: true, out _, out _, out _);
        ValidateActiveTransaction(plan, role);
        var checkpointPayload = root.GetProperty("payloadSha256").GetString();
        if (!string.Equals(checkpointPayload, PayloadManifest.PayloadSha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Refusing to consume a checkpoint for a different payload.");
        StateStore.WriteJsonAtomically(ConsumedPath(transactionId), new { transactionId, checkpointGeneration = generation, action = root.GetProperty("action").GetString(), role = root.GetProperty("role").GetString(), installerVersion = root.GetProperty("installerVersion").GetString(), devFleetVersion = root.GetProperty("devFleetVersion").GetString(), payloadSha256 = checkpointPayload, acknowledgeRootfulDocker = root.GetProperty("acknowledgeRootfulDocker").GetBoolean(), completedStages = root.GetProperty("completedStages"), resumeStage = root.GetProperty("resumeStage").GetString(), consumedUtc = DateTime.UtcNow.ToString("O") });
        File.Delete(Path);
        var activePath = System.IO.Path.Combine(ScriptStateRoot, "active-transaction.json");
        if (File.Exists(activePath))
        {
            try { using var active = JsonDocument.Parse(File.ReadAllText(activePath)); if (active.RootElement.GetProperty("transactionId").GetString() == transactionId) File.Delete(activePath); } catch { }
        }
        progress?.Invoke("Durable reboot checkpoint consumed after verified completion.");
    }
}

public sealed record InstallerLaunchRequest(InstallerMode? Action, string? Role, bool ElevatedResume, bool DeferNetworkPairing, bool AcknowledgeRootfulDocker);

public static class InstallerLaunchContract
{
    public static InstallerLaunchRequest Parse(IEnumerable<string> arguments)
    {
        var args = arguments.ToArray();
        static string? ValueAfter(string[] values, string name)
        {
            var index = Array.FindIndex(values, value => value.Equals(name, StringComparison.OrdinalIgnoreCase));
            return index >= 0 && index + 1 < values.Length ? values[index + 1] : null;
        }

        var actionText = ValueAfter(args, "--action");
        InstallerMode? action = Enum.TryParse<InstallerMode>(actionText, true, out var parsedAction) ? parsedAction : null;
        return new InstallerLaunchRequest(
            action,
            ValueAfter(args, "--role"),
            args.Any(value => value.Equals("--elevated-resume", StringComparison.OrdinalIgnoreCase)),
            args.Any(value => value.Equals("--defer-network-pairing", StringComparison.OrdinalIgnoreCase)),
            args.Any(value => value.Equals("--acknowledge-rootful-docker", StringComparison.OrdinalIgnoreCase)));
    }

    public static IReadOnlyList<string> BuildElevatedResumeArguments(string role, InstallerMode mode, bool deferNetworkPairing, bool acknowledgeRootfulDocker)
    {
        var args = new List<string> { "--elevated-resume", "--action", mode.ToString(), "--role", role };
        if (deferNetworkPairing) args.Add("--defer-network-pairing");
        if (acknowledgeRootfulDocker) args.Add("--acknowledge-rootful-docker");
        return args;
    }
}

public static class ElevationService
{
    public static bool IsAdministrator => OperatingSystem.IsWindows() && new System.Security.Principal.WindowsPrincipal(System.Security.Principal.WindowsIdentity.GetCurrent()).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
    public static Process? RelaunchVerified(string role, InstallerMode mode, bool deferNetworkPairing = false, bool acknowledgeRootfulDocker = false)
    {
        var exe = Environment.ProcessPath ?? throw new InvalidOperationException("The verified installer executable path is unavailable.");
        var startInfo = new ProcessStartInfo { FileName = exe, Verb = "runas", UseShellExecute = true };
        foreach (var argument in InstallerLaunchContract.BuildElevatedResumeArguments(role, mode, deferNetworkPairing, acknowledgeRootfulDocker)) startInfo.ArgumentList.Add(argument);
        return Process.Start(startInfo);
    }
}

public static class LifecycleEngine
{
    public static InstallerExecutionReport? LastExecution { get; private set; }
    private static void AssertExactFactoryResetSelection(InstallerPlan plan)
    {
        if (plan.Mode != InstallerMode.FactoryReset || !plan.ProjectDataSelected) return;
        var requested = plan.SelectedProjectIds.Select(x => x.Trim()).Where(x => x.Length > 0).ToArray();
        if (requested.Length != requested.Distinct(StringComparer.OrdinalIgnoreCase).Count()) throw new InvalidOperationException("Factory Reset blocked: the reviewed execution set contains duplicate project IDs.");
        var reviewedIds = plan.SelectedProjects.Select(x => x.ProjectId.Trim()).Where(x => x.Length > 0).ToArray();
        if (reviewedIds.Length != requested.Length || reviewedIds.Length != reviewedIds.Distinct(StringComparer.OrdinalIgnoreCase).Count() || !reviewedIds.ToHashSet(StringComparer.OrdinalIgnoreCase).SetEquals(requested))
            throw new InvalidOperationException("Factory Reset blocked: the reviewed project records do not exactly match the requested execution set. Review and confirm again.");
        var current = new ProjectDiscoveryService().Discover();
        var currentSelected = current.Where(x => requested.Contains(x.ProjectId, StringComparer.OrdinalIgnoreCase)).ToArray();
        if (currentSelected.Length != requested.Length || !currentSelected.Select(x => x.ProjectId).ToHashSet(StringComparer.OrdinalIgnoreCase).SetEquals(requested)) throw new InvalidOperationException("Factory Reset blocked: the exact reviewed project selection changed before execution. Review and confirm again.");
        foreach (var reviewed in plan.SelectedProjects)
        {
            var now = currentSelected.SingleOrDefault(x => x.ProjectId.Equals(reviewed.ProjectId, StringComparison.OrdinalIgnoreCase));
            if (now is null || !now.Slug.Equals(reviewed.Slug, StringComparison.Ordinal) || !now.RuntimeId.Equals(reviewed.RuntimeId, StringComparison.Ordinal) || !now.OwnershipStatus.Equals("VERIFIED", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException($"Factory Reset blocked: reviewed project identity or ownership drifted for {reviewed.ProjectId}. Review and confirm again.");
        }
    }
    public static string Execute(InstallerPlan plan, string role, Action<string>? progress = null)
    {
        if (!plan.IsAllowed) throw new InvalidOperationException(string.Join(Environment.NewLine, plan.Blockers));
        if (plan.IsMutation && !ElevationService.IsAdministrator && !TestEnvironment.IsTestProcess)
            throw new InvalidOperationException("Machine-wide mutation requires UAC elevation. Relaunch the same verified installer with runas before executing.");
        var logger = new InstallerLogger();
        var tx = new TransactionService(logger);
        var ledger = StateStore.ReadLedger();
        var previousLedger = ledger;
        string? recovery = null;
        string? controlPlaneSnapshot = null;
        try
        {
            var resumed = RebootCheckpointService.ValidateIfPresent(plan, role, progress);
            if (plan.Mode is InstallerMode.Diagnostics or InstallerMode.RecoveryPackage) return PreflightService.ToText(PreflightService.Run());
            if (plan.Mode is InstallerMode.CleanReinstall or InstallerMode.Uninstall or InstallerMode.FactoryReset)
                recovery = RecoveryService.Create(plan.TransactionId, progress);
            if (plan.Mode == InstallerMode.CleanReinstall)
                controlPlaneSnapshot = ControlPlaneSnapshotService.Capture(plan.TransactionId, progress);
            if (plan.Mode == InstallerMode.FactoryReset && plan.ProjectDataSelected)
            {
                if (plan.SelectedProjects.Count == 0) throw new InvalidOperationException("Factory Reset blocked: no individual project is selected.");
                AssertExactFactoryResetSelection(plan);
                var factoryReset = new FactoryResetService(new BackupVerificationService(), new VmOwnershipService(new MultipassHostAgentProvider()));
                foreach (var project in plan.SelectedProjects) factoryReset.DeleteSelected(project, progress);
            }
            if (plan.Mode is InstallerMode.Uninstall or InstallerMode.FactoryReset)
                CleanupJournalService.Execute(plan.Mode.ToString(), plan.TransactionId, BuildMonotonicCleanupStages(ledger, progress), progress, ledger.InstallTimestampUtc, ledger.PackageSha256);
            else if (plan.Mode == InstallerMode.CleanReinstall)
                progress?.Invoke("Clean Reinstall is staged transactionally; the previous control plane remains available until replacement verification.");
            if (plan.Mode is InstallerMode.FreshInstall or InstallerMode.Repair or InstallerMode.CleanReinstall or InstallerMode.LocalUpdate)
            {
                var preparedUtc = RebootCheckpointService.PrepareScriptTransaction(plan, role, progress);
                var staged = PayloadService.StageVerifiedPayload(plan.TransactionId, progress);
                var releaseRoot = PayloadService.ExtractVerifiedPayload(staged, plan.TransactionId, progress);
                var fixture = TestEnvironment.IsTestProcess && string.Equals(Environment.GetEnvironmentVariable("DEVFLEET_SETUP_FIXTURE_MODE"), "1", StringComparison.Ordinal);
                if (plan.Mode == InstallerMode.Repair)
                {
                    var report = new RepairService(new InstallService(fixture ? new RecordingProcessRunner() : null)).Repair(releaseRoot, role, progress, plan.DeferNetworkPairing, plan.AcknowledgeRootfulDocker, plan.TransactionId, PayloadManifest.PayloadSha256, plan.Mode.ToString(), role, preparedUtc);
                    LastExecution = report;
                    progress?.Invoke($"Real repair entry-point completion verified: {string.Join(" -> ", report.Stages)}");
                }
                else
                {
                    var report = new InstallService(fixture ? new RecordingProcessRunner() : null).Run(releaseRoot, role, plan.Mode.ToString(), progress, plan.DeferNetworkPairing, plan.AcknowledgeRootfulDocker, plan.TransactionId, PayloadManifest.PayloadSha256, plan.Mode.ToString(), role, preparedUtc);
                    LastExecution = report;
                    if (report.ExitCode == 3010) throw new RebootRequiredException("DevFleet installation reached a safe reboot checkpoint.");
                    progress?.Invoke($"Real installer stage map complete: {string.Join(" -> ", report.Stages)}");
                }
                ledger = BuildLedger(releaseRoot, role, recovery);
                InstallStableLauncher(ledger, progress);
                CreateInstalledAppEntry(ledger); CreateShortcuts(ledger, progress);
                StateStore.WriteLedger(ledger); progress?.Invoke("Ownership ledger committed after verification.");
            }
            if (plan.Mode is InstallerMode.Uninstall or InstallerMode.FactoryReset)
            {
                foreach (var key in ledger.RegistryEntriesCreated) RemoveExactRegistryEntry(key, progress);
                File.Delete(AppPaths.LedgerPath);
            }
            logger.Write($"transaction={plan.TransactionId} state=completed");
            if (controlPlaneSnapshot is not null) ControlPlaneSnapshotService.Delete(controlPlaneSnapshot);
            RebootCheckpointService.Consume(plan, role, progress);
            return recovery ?? logger.LogPath;
        }
        catch (RebootRequiredException ex)
        {
            RebootCheckpointService.Write(plan, role, recovery, progress);
            logger.Write($"transaction={plan.TransactionId} state=waiting-for-reboot");
            progress?.Invoke($"Waiting for reboot: {ex.Message} Rerun DevFleet Setup to resume.");
            return recovery ?? logger.LogPath;
        }
        catch (Exception ex)
        {
            logger.Write($"transaction={plan.TransactionId} state=failed error={ex.Message}");
            if (plan.Mode is not (InstallerMode.Uninstall or InstallerMode.FactoryReset)) tx.Rollback(progress);
            if (controlPlaneSnapshot is not null)
            {
                ControlPlaneSnapshotService.Restore(controlPlaneSnapshot, progress);
                StateStore.WriteLedger(previousLedger);
            }
            throw;
        }
    }

    private static string JsonString(JsonElement value, string name) => value.TryGetProperty(name, out var property) ? property.ToString() : "";

    private static void ImportWindowsIntegrationOwnership(InstallLedger ledger)
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevFleetHostAgent", "integration-ownership.json");
        if (!File.Exists(path)) return;
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        if (root.GetProperty("SchemaVersion").GetInt32() != 1) throw new InvalidDataException("Windows integration ownership schema is unsupported.");
        ledger.InstallationGeneration = JsonString(root, "InstallationGeneration");
        ledger.WindowsIntegrationOwnershipPath = path;
        var marker = JsonString(root, "Marker");
        foreach (var item in root.GetProperty("ScheduledTasks").EnumerateArray())
            ledger.WindowsIntegrations.Add(new OwnedWindowsIntegration("ScheduledTask", JsonString(item, "Name"), JsonString(item, "Generation"), JsonString(item, "Marker") is { Length: > 0 } taskMarker ? taskMarker : marker, Executable: JsonString(item, "Executable"), Arguments: JsonString(item, "Arguments"), Principal: JsonString(item, "Principal"), LogonType: JsonString(item, "LogonType"), RunLevel: JsonString(item, "RunLevel"), Description: JsonString(item, "Description")));
        foreach (var item in root.GetProperty("FirewallRules").EnumerateArray())
            ledger.WindowsIntegrations.Add(new OwnedWindowsIntegration("FirewallRule", JsonString(item, "Name"), JsonString(item, "Generation"), JsonString(item, "Marker") is { Length: > 0 } firewallMarker ? firewallMarker : marker, Description: JsonString(item, "Description"), DisplayName: JsonString(item, "DisplayName"), Group: JsonString(item, "Group"), Direction: JsonString(item, "Direction"), Action: JsonString(item, "Action"), Protocol: JsonString(item, "Protocol"), LocalPort: JsonString(item, "LocalPort"), InterfaceAlias: JsonString(item, "InterfaceAlias"), RemoteAddress: JsonString(item, "RemoteAddress"), Profile: JsonString(item, "Profile")));
        foreach (var item in root.GetProperty("Services").EnumerateArray())
            ledger.WindowsIntegrations.Add(new OwnedWindowsIntegration("Service", JsonString(item, "Name"), JsonString(item, "Generation"), JsonString(item, "Marker") is { Length: > 0 } serviceMarker ? serviceMarker : marker, ImagePath: JsonString(item, "ImagePath"), Account: JsonString(item, "Account"), StartMode: JsonString(item, "StartMode")));
    }

    private static InstallLedger BuildLedger(string releaseRoot, string role, string? recovery)
    {
        var ledger = new InstallLedger { Role = role, PackageSha256 = PayloadManifest.PayloadSha256, InstallTimestampUtc = DateTime.UtcNow.ToString("O") };
        ledger.FilesInstalled.AddRange(Directory.EnumerateFiles(releaseRoot, "*", SearchOption.AllDirectories));
        ledger.OwnedResources.Add(new OwnedResource("release", "DevFleet release payload", "DevFleetLedger", releaseRoot));
        if (recovery is not null) ledger.OwnedResources.Add(new OwnedResource("recovery", "Recovery package", "DevFleetLedger", recovery));
        foreach (var dependency in new DependencyService().DetectAll().Where(x => x.Found))
        {
            ledger.PreExistingPrerequisites.Add($"{dependency.Name} {dependency.Version}");
            ledger.ResolvedPrerequisitePaths.Add($"{dependency.Name}|{dependency.ExecutablePath}");
        }
        ledger.ManagedSshMarkers.Add("# BEGIN DEVFLEET MANAGED|# END DEVFLEET MANAGED");
        ledger.ManagedVsCodeFiles.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Code", "User", "devfleet-settings.reference.jsonc"));
        ImportWindowsIntegrationOwnership(ledger);
        OwnedPathSafety.ValidateLedger(ledger);
        return ledger;
    }

    private static void RemoveOwnedControlPlane(InstallLedger ledger, Action<string>? progress)
    {
        new WindowsOwnedIntegrationCleanupService().Cleanup(ledger, progress);
        RemoveManagedSshAndVsCode(ledger, progress);
        ScheduleSelfRemoval(progress);
        foreach (var file in ledger.FilesInstalled.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var full = Path.GetFullPath(file);
            if (OwnedPathSafety.IsUnderOwnedRoot(full, AppPaths.InstallRoot) && File.Exists(full)) { File.Delete(full); progress?.Invoke($"Removed proven-owned program file: {full}"); }
        }
        foreach (var shortcut in ledger.ShortcutsCreated.Where(File.Exists)) { File.Delete(shortcut); progress?.Invoke($"Removed DevFleet shortcut: {shortcut}"); }
        var shortcutRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs", "DevFleet");
        if (Directory.Exists(shortcutRoot) && !Directory.EnumerateFileSystemEntries(shortcutRoot).Any()) Directory.Delete(shortcutRoot);
        foreach (var reg in ledger.RegistryEntriesCreated) RemoveExactRegistryEntry(reg, progress);
    }

    private static IReadOnlyList<(string Name, Action Action)> BuildMonotonicCleanupStages(InstallLedger ledger, Action<string>? progress)
    {
        return [
            ("stop-and-remove-owned-integrations", () => new WindowsOwnedIntegrationCleanupService().Cleanup(ledger, progress)),
            ("remove-managed-ssh-and-vscode-integrations", () => RemoveManagedSshAndVsCode(ledger, progress)),
            ("schedule-owned-self-removal", () => ScheduleSelfRemoval(progress)),
            ("remove-owned-program-files", () => InstallerEngine.RemoveLedgerFiles(ledger, progress)),
            ("remove-owned-shortcuts", () => { foreach (var shortcut in ledger.ShortcutsCreated.Distinct(StringComparer.OrdinalIgnoreCase)) { if (File.Exists(shortcut)) File.Delete(shortcut); if (File.Exists(shortcut)) throw new IOException($"Owned shortcut remains after cleanup: {shortcut}"); progress?.Invoke($"Removed and verified DevFleet shortcut: {shortcut}"); } }),
            ("remove-owned-registry-entries", () => { foreach (var reg in ledger.RegistryEntriesCreated.Distinct(StringComparer.OrdinalIgnoreCase)) RemoveExactRegistryEntry(reg, progress); })
        ];
    }

    private static void RemoveManagedSshAndVsCode(InstallLedger ledger, Action<string>? progress)
    {
        var sshConfig = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ssh", "config");
        if (File.Exists(sshConfig))
        {
            var text = File.ReadAllText(sshConfig);
            foreach (var marker in ledger.ManagedSshMarkers)
            {
                var parts = marker.Split('|', 2); if (parts.Length != 2) continue;
                var pattern = $@"(?ms)^\s*{Regex.Escape(parts[0])}\s*$.*?^\s*{Regex.Escape(parts[1])}\s*$\r?\n?";
                text = Regex.Replace(text, pattern, "");
            }
            File.WriteAllText(sshConfig, text);
            var remaining = File.ReadAllText(sshConfig);
            foreach (var marker in ledger.ManagedSshMarkers)
            {
                var parts = marker.Split('|', 2); if (parts.Length != 2) continue;
                if (remaining.Contains(parts[0], StringComparison.Ordinal) || remaining.Contains(parts[1], StringComparison.Ordinal))
                    throw new IOException($"Managed SSH marker remains after cleanup: {sshConfig}");
            }
            progress?.Invoke($"Removed and verified only the DevFleet managed SSH block: {sshConfig}");
        }
        foreach (var file in ledger.ManagedVsCodeFiles)
        {
            var expectedRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Code", "User") + Path.DirectorySeparatorChar;
            var full = Path.GetFullPath(file); if (OwnedPathSafety.IsUnderOwnedRoot(full, expectedRoot) && Path.GetFileName(full).Equals("devfleet-settings.reference.jsonc", StringComparison.OrdinalIgnoreCase))
            {
                if (File.Exists(full)) File.Delete(full);
                if (File.Exists(full)) throw new IOException($"Managed VS Code file remains after cleanup: {full}");
                progress?.Invoke($"Removed and verified exact DevFleet VS Code reference file: {full}");
            }
        }
    }

    private static void ScheduleSelfRemoval(Action<string>? progress)
    {
        var current = Environment.ProcessPath;
        var target = Path.Combine(AppPaths.InstallRoot, "DevFleet.Setup.exe");
        if (string.IsNullOrWhiteSpace(current) || !Path.GetFullPath(current).Equals(Path.GetFullPath(target), StringComparison.OrdinalIgnoreCase)) return;
        var helperDirectory = Path.Combine(AppPaths.CacheRoot, "SelfRemoval");
        SecureStagingService.EnsureDirectory(helperDirectory);
        var helper = Path.Combine(helperDirectory, $"DevFleet-Setup-Remove-{Guid.NewGuid():N}.ps1");
        using (var stream = new FileStream(helper, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        using (var writer = new StreamWriter(stream, new System.Text.UTF8Encoding(false)))
        {
            writer.Write("param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$Helper)\n$ErrorActionPreference='Stop'\nStart-Sleep -Milliseconds 500\nif(Test-Path -LiteralPath $Target -PathType Leaf){Remove-Item -LiteralPath $Target -Force}\nif(Test-Path -LiteralPath $Helper -PathType Leaf){Remove-Item -LiteralPath $Helper -Force}\n");
            writer.Flush();
            stream.Flush(true);
        }
        var powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powershell)) throw new FileNotFoundException("Windows PowerShell self-removal helper is unavailable.", powershell);
        var start = new ProcessStartInfo { FileName = powershell, UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden };
        foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", helper, "-Target", target, "-Helper", helper }) start.ArgumentList.Add(argument);
        if (Process.Start(start) is null) throw new InvalidOperationException("Unable to start the protected self-removal helper.");
        progress?.Invoke("Immediate exact self-removal helper scheduled from protected installer state with argument-bound paths.");
    }

    private static void RemoveExactRegistryEntry(string key, Action<string>? progress)
    {
        const string prefix = "HKLM\\";
        if (!key.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) { progress?.Invoke($"Preserved non-machine registry entry outside owned scope: {key}"); return; }
        var subkey = key[prefix.Length..];
        using var root = Microsoft.Win32.Registry.LocalMachine;
        try
        {
            root.DeleteSubKeyTree(subkey, throwOnMissingSubKey: false);
            using var remaining = root.OpenSubKey(subkey);
            if (remaining is not null) throw new IOException($"Owned registry entry remains after cleanup: {key}");
            progress?.Invoke($"Removed and verified exact registry ownership: {key}");
        }
        catch (UnauthorizedAccessException ex) { throw new IOException($"Registry cleanup blocked by access policy: {key}", ex); }
    }

    private static void InstallStableLauncher(InstallLedger ledger, Action<string>? progress)
    {
        var current = Environment.ProcessPath; if (string.IsNullOrWhiteSpace(current) || !File.Exists(current)) return;
        Directory.CreateDirectory(AppPaths.InstallRoot);
        var target = Path.Combine(AppPaths.InstallRoot, "DevFleet.Setup.exe");
        if (!Path.GetFullPath(current).Equals(Path.GetFullPath(target), StringComparison.OrdinalIgnoreCase)) File.Copy(current, target, true);
        ledger.FilesInstalled.Add(target); ledger.OwnedResources.Add(new OwnedResource("launcher", "DevFleet Setup", "DevFleetLedger", target)); progress?.Invoke($"Stable launcher target verified: {target}");
    }

    private static void CreateInstalledAppEntry(InstallLedger ledger)
    {
        using var key = Microsoft.Win32.Registry.LocalMachine.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\DevFleet");
        if (key is null) return;
        var exe = Path.Combine(AppPaths.InstallRoot, "DevFleet.Setup.exe");
        key.SetValue("DisplayName", "DevFleet"); key.SetValue("Publisher", "M-TechLabs"); key.SetValue("DisplayVersion", PayloadManifest.DevFleetVersion); key.SetValue("InstallLocation", AppPaths.InstallRoot); key.SetValue("UninstallString", $"\"{exe}\" --maintenance --action uninstall");
        ledger.RegistryEntriesCreated.Add(@"HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\DevFleet");
    }

    private static void CreateShortcuts(InstallLedger ledger, Action<string>? progress)
    {
        var exe = Path.Combine(AppPaths.InstallRoot, "DevFleet.Setup.exe");
        if (!File.Exists(exe)) return;
        var start = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs", "DevFleet"); Directory.CreateDirectory(start);
        foreach (var item in new[] { ("DevFleet", "--maintenance"), ("DevFleet Maintenance", "--maintenance") })
        {
            var path = Path.Combine(start, item.Item1 + ".lnk");
            try
            {
                var type = Type.GetTypeFromProgID("WScript.Shell"); if (type is null) continue;
                dynamic shell = Activator.CreateInstance(type)!; dynamic shortcut = shell.CreateShortcut(path); shortcut.TargetPath = exe; shortcut.Arguments = item.Item2; shortcut.WorkingDirectory = AppPaths.InstallRoot; shortcut.Description = "DevFleet installed launcher"; shortcut.Save(); ledger.ShortcutsCreated.Add(path); progress?.Invoke($"Shortcut target verified: {path} -> {exe} {item.Item2}");
            }
            catch { progress?.Invoke($"Shortcut COM creation unavailable in this environment: {path}"); }
        }
    }
}

```


## FILE: installer-source/DevFleet.Setup/Services/InstallerServices.cs

SHA256: 776f7362ad7aa5255cbcf6d8c44d2858193e2f00968bc342cffee45365e8a4f8 | Bytes: 44467 | Git mode: 100644

```
using System.Formats.Tar;
using System.IO.Compression;
using System.IO;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using Microsoft.Win32;

namespace DevFleet.Setup;

internal static class TestEnvironment
{
    private static bool _enabled;
    private static string? _selfTestRoot;
    public static bool IsTestProcess => _enabled;
    internal static void EnableForTests() => _enabled = true;

    internal static void EnableForSelfTest(string root)
    {
        var full = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var temp = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var prefix = "DevFleet-Setup-SelfTest-";
        var leaf = Path.GetFileName(full);
        var parent = Directory.GetParent(full)?.FullName?.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (!string.Equals(parent, temp, StringComparison.OrdinalIgnoreCase) ||
            !leaf.StartsWith(prefix, StringComparison.Ordinal) ||
            !Guid.TryParseExact(leaf[prefix.Length..], "N", out _))
            throw new InvalidDataException("Self-test root must be a fresh DevFleet GUID directory directly beneath the process temporary directory.");
        _enabled = true;
        _selfTestRoot = full;
    }

    internal static bool IsAuthorizedSelfTestPath(string path)
    {
        if (string.IsNullOrWhiteSpace(_selfTestRoot)) return false;
        var full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return full.Equals(_selfTestRoot, StringComparison.OrdinalIgnoreCase) ||
               full.StartsWith(_selfTestRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    internal static void ClearSelfTestRoot() => _selfTestRoot = null;
}

public static class AppPaths
{
    private static string? _selfTestInstallRoot;
    private static string? _selfTestStateRoot;
    public static string InstallRoot => _selfTestInstallRoot ?? (TestEnvironment.IsTestProcess ? Environment.GetEnvironmentVariable("DEVFLEET_SETUP_INSTALL_ROOT") : null)
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "M-TechLabs", "DevFleet");
    public static string StateRoot => _selfTestStateRoot ?? (TestEnvironment.IsTestProcess ? Environment.GetEnvironmentVariable("DEVFLEET_SETUP_STATE_ROOT") : null)
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "M-TechLabs", "DevFleet");
    public static string InstallerRoot => Path.Combine(StateRoot, "Installer");
    public static string CacheRoot => Path.Combine(StateRoot, "InstallerCache");
    public static string LogsRoot => Path.Combine(StateRoot, "Logs");
    public static string LedgerPath => Path.Combine(InstallerRoot, "install-state.json");

    internal static void ConfigureSelfTestRoots(string installRoot, string stateRoot)
    {
        _selfTestInstallRoot = Path.GetFullPath(installRoot);
        _selfTestStateRoot = Path.GetFullPath(stateRoot);
    }
}

public sealed class InstallLedger
{
    public string InstallerVersion { get; set; } = PayloadManifest.InstallerVersion;
    public string DevFleetVersion { get; set; } = PayloadManifest.DevFleetVersion;
    public string InstallTimestampUtc { get; set; } = DateTime.UtcNow.ToString("O");
    public string Role { get; set; } = "Standalone / unknown";
    public string PackageSha256 { get; set; } = PayloadManifest.PayloadSha256;
    public string InstallationGeneration { get; set; } = "";
    public string WindowsIntegrationOwnershipPath { get; set; } = "";
    public List<OwnedWindowsIntegration> WindowsIntegrations { get; set; } = [];
    public List<string> FilesInstalled { get; set; } = [];
    public List<string> ShortcutsCreated { get; set; } = [];
    public List<string> RegistryEntriesCreated { get; set; } = [];
    public List<OwnedResource> OwnedResources { get; set; } = [];
    public List<string> PrerequisitesInstalledByDevFleet { get; set; } = [];
    public List<string> PreExistingPrerequisites { get; set; } = [];
    public List<string> ManagedSshMarkers { get; set; } = [];
    public List<string> ManagedVsCodeFiles { get; set; } = [];
    public List<string> ResolvedPrerequisitePaths { get; set; } = [];
}

public static class OwnedPathSafety
{
    // Only primitive rights which can mutate a directory are security-relevant
    // here.  WriteData/CreateFiles and AppendData/CreateDirectories are enum
    // aliases; each is represented once.  Composite Modify and FullControl are
    // intentionally absent: their primitive mutation bits still intersect this
    // mask and are therefore rejected, while read-only ACEs cannot be promoted.
    public const FileSystemRights PrimitiveMutationRights =
        FileSystemRights.WriteData |
        FileSystemRights.AppendData |
        FileSystemRights.WriteExtendedAttributes |
        FileSystemRights.WriteAttributes |
        FileSystemRights.Delete |
        FileSystemRights.DeleteSubdirectoriesAndFiles |
        FileSystemRights.ChangePermissions |
        FileSystemRights.TakeOwnership;

    public static bool HasPrimitiveMutationRights(FileSystemRights rights)
        => (rights & PrimitiveMutationRights) != 0;

    public static bool IsBroadUntrustedPrincipal(string identity)
        => identity.Equals("Everyone", StringComparison.OrdinalIgnoreCase)
            || identity.EndsWith("\\Users", StringComparison.OrdinalIgnoreCase)
            || identity.Equals("NT AUTHORITY\\Authenticated Users", StringComparison.OrdinalIgnoreCase);

    // Return the exact system trust root for an existing candidate.  The
    // caller must stop ACL traversal at this root; inspecting parents above a
    // trusted root (for example C:\\) would import unrelated machine policy.
    public static bool TryGetTrustedSystemRoot(string candidate, out string root)
    {
        root = "";
        try
        {
            var full = Path.GetFullPath(candidate).TrimEnd(Path.DirectorySeparatorChar);
            var roots = new[]
            {
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                Environment.GetFolderPath(Environment.SpecialFolder.Windows)
            }
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Select(x => Path.GetFullPath(x).TrimEnd(Path.DirectorySeparatorChar))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Where(x => full.StartsWith(x + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            .ToArray();
            if (roots.Length != 1) return false;
            root = roots[0];
            return true;
        }
        catch { return false; }
    }

    // WinGet is trusted only when the executable is the direct child of one
    // physical, approved WindowsApps package root.  AppX identity is supplied
    // by the caller so this structural predicate is independently testable.
    public static bool IsExactWindowsAppxPackageCandidate(string executable, string packageRoot, string approvedWindowsAppsRoot, string packageName, string publisherId)
    {
        try
        {
            if (!packageName.Equals("Microsoft.DesktopAppInstaller", StringComparison.OrdinalIgnoreCase) || !publisherId.Equals("8wekyb3d8bbwe", StringComparison.OrdinalIgnoreCase)) return false;
            if (executable.Contains("..", StringComparison.Ordinal) || packageRoot.Contains("..", StringComparison.Ordinal) || approvedWindowsAppsRoot.Contains("..", StringComparison.Ordinal)) return false;
            var full = Path.GetFullPath(executable).TrimEnd(Path.DirectorySeparatorChar);
            var package = Path.GetFullPath(packageRoot).TrimEnd(Path.DirectorySeparatorChar);
            var approved = Path.GetFullPath(approvedWindowsAppsRoot).TrimEnd(Path.DirectorySeparatorChar);
            if (!full.Equals(executable.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase) || !package.Equals(packageRoot.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)) return false;
            if (!Path.GetFileName(full).Equals("winget.exe", StringComparison.OrdinalIgnoreCase)) return false;
            if (!Path.GetDirectoryName(full)!.Equals(package, StringComparison.OrdinalIgnoreCase)) return false;
            if (!Path.GetDirectoryName(package)!.Equals(approved, StringComparison.OrdinalIgnoreCase)) return false;
            var basename = Path.GetFileName(package);
            const string prefix = "Microsoft.DesktopAppInstaller_";
            const string suffix = "_x64__8wekyb3d8bbwe";
            if (!basename.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || !basename.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)) return false;
            var version = basename[prefix.Length..^suffix.Length];
            if (string.IsNullOrWhiteSpace(version) || version.Split('.').Any(part => part.Length == 0 || !part.All(char.IsDigit))) return false;
            var packageInfo = new DirectoryInfo(package);
            var approvedInfo = new DirectoryInfo(approved);
            if (!packageInfo.Exists || !approvedInfo.Exists || packageInfo.Attributes.HasFlag(FileAttributes.ReparsePoint) || approvedInfo.Attributes.HasFlag(FileAttributes.ReparsePoint)) return false;
            if (!File.Exists(full) || (File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0) return false;
            return true;
        }
        catch { return false; }
    }

    public static bool IsUnderOwnedRoot(string candidate, string root)
    {
        try
        {
            var full = Path.GetFullPath(candidate);
            if (File.Exists(full) && (File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0) return false;
            var ownedRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!full.StartsWith(ownedRoot, StringComparison.OrdinalIgnoreCase)) return false;
            var current = new DirectoryInfo(Path.GetDirectoryName(full)!);
            var rootInfo = new DirectoryInfo(root);
            if (rootInfo.Attributes.HasFlag(FileAttributes.ReparsePoint)) return false;
     