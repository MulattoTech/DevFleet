# DevFleet source part 058

Full-source UTF-8 byte interval [2650500, 2697000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: d4772c2630b13f89eef3955fe49aa29fe2dcc93a2c5ad1d8c41c88ae16691a0e

<!-- BEGIN SOURCE SLICE -->
  try
        {
            await process.WaitForExitAsync(timeout.Token).ConfigureAwait(false);
            var exitCode = process.ExitCode;
            try { await Task.WhenAll(stdoutTask, stderrTask).WaitAsync(TimeSpan.FromSeconds(5)).ConfigureAwait(false); }
            catch (TimeoutException) { }
            var outputComplete = stdoutTask.Status == TaskStatus.RanToCompletion && stderrTask.Status == TaskStatus.RanToCompletion;
            return new ProcessResult(
                exitCode,
                stdoutTask.Status == TaskStatus.RanToCompletion ? stdoutTask.Result : "",
                stderrTask.Status == TaskStatus.RanToCompletion ? stderrTask.Result : "",
                outputComplete);
        }
        catch (OperationCanceledException)
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
            try { await Task.WhenAll(stdoutTask, stderrTask).WaitAsync(TimeSpan.FromSeconds(5)).ConfigureAwait(false); } catch { }
            var outputComplete = stdoutTask.Status == TaskStatus.RanToCompletion && stderrTask.Status == TaskStatus.RanToCompletion;
            return new ProcessResult(-2, stdoutTask.Status == TaskStatus.RanToCompletion ? stdoutTask.Result : "", $"Process timed out after {timeoutSeconds}s. { (stderrTask.Status == TaskStatus.RanToCompletion ? stderrTask.Result : "") }", outputComplete);
        }
    }
}

public sealed class RecordingProcessRunner : IProcessRunner
{
    private readonly Queue<ProcessResult> _results = new();
    public List<ProcessInvocation> Invocations { get; } = [];
    public void QueueResult(ProcessResult result) => _results.Enqueue(result);
    public ProcessResult Run(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null)
    {
        Invocations.Add(new ProcessInvocation(fileName, arguments, workingDirectory));
        return _results.Count > 0 ? _results.Dequeue() : new ProcessResult(0, "fixture success", "");
    }
}

public interface IFileSystem
{
    bool FileExists(string path);
    void CopyFile(string source, string destination, bool overwrite);
    void DeleteFile(string path);
    IReadOnlyList<string> EnumerateFiles(string root);
}

public sealed class RealFileSystem : IFileSystem
{
    public bool FileExists(string path) => File.Exists(path);
    public void CopyFile(string source, string destination, bool overwrite) { Directory.CreateDirectory(Path.GetDirectoryName(destination)!); File.Copy(source, destination, overwrite); }
    public void DeleteFile(string path) { if (File.Exists(path)) File.Delete(path); }
    public IReadOnlyList<string> EnumerateFiles(string root) => Directory.Exists(root) ? Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).ToArray() : [];
}

public interface IRegistryManager { void RemoveExact(string key); }
public interface IServiceManager { bool IsHealthy(string serviceName); void StopOwned(string serviceName); }
public interface IShortcutManager { void RemoveExact(string path); }
public interface IFirewallManager { void RemoveExact(string ruleName); }
public interface ISshManager { void RemoveManagedBlock(string marker); }
public interface IVsCodeManager { void RemoveManagedAlias(string alias); }
public interface IDependencyInstaller { DependencyResult VerifyAndInstall(string dependencyRoot); }

public sealed record DependencyResult(bool Available, bool InstalledByDevFleet, bool RebootRequired, string Detail);

public sealed class DependencyDefinition
{
    public string Id { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Classification { get; init; } = "OPTIONAL";
    public bool Required { get; init; }
    public string[] Roles { get; init; } = [];
    public string[] Features { get; init; } = [];
    public string MinimumSupportedVersion { get; init; } = "0.0.0";
    public int? MaximumMajor { get; init; }
    public string[] ExecutableProbes { get; init; } = [];
    public string[] RegistryProbes { get; init; } = [];
    public string[] AppPathsProbes { get; init; } = [];
    public string[] KnownVendorInstallLocations { get; init; } = [];
    public string? WingetPackageId { get; init; }
    public OfficialResolver DirectOfficialVendorResolver { get; init; } = new();
    public InstallerAuthenticityPolicy InstallerAuthenticityPolicy { get; init; } = new();
    public string[] SilentInstallArguments { get; init; } = [];
    public string RebootSemantics { get; init; } = "0";
    public VersionProbe VersionProbe { get; init; } = new();
    public string PostInstallExecutableDiscovery { get; init; } = "rediscover from all supported probes";
    public string PostInstallVersionVerification { get; init; } = "verify installed version";

    // Compatibility aliases retained for existing installer UI/tests while the manifest is canonical.
    public string Name => DisplayName;
    public string Executable => ExecutableProbes.FirstOrDefault() ?? "";
    public Version MinimumVersion => Version.TryParse(MinimumSupportedVersion, out var v) ? v : new Version(0, 0);
    public string WingetId => WingetPackageId ?? "";
    public Uri OfficialMetadata => new(DirectOfficialVendorResolver.MetadataUri);
}

public sealed class OfficialResolver
{
    public string Type { get; init; } = "";
    public string MetadataUri { get; init; } = "https://example.invalid/";
    public string? OfficialPageUri { get; init; }
    public string? DirectUri { get; init; }
    public string? ExpectedOwner { get; init; }
    public string? ExpectedRepository { get; init; }
    public string[] AllowedHosts { get; init; } = [];
    public string? AssetRegex { get; init; }
    public string? OfficialPageAssetRegex { get; init; }
}

public sealed class InstallerAuthenticityPolicy
{
    public string Strategy { get; init; } = "Authenticode";
    public bool Required { get; init; }
    public string[] AllowedSignerPatterns { get; init; } = [];
    public string[] AllowedSignerSubjectsExact { get; init; } = [];
    public string InstalledExecutableTrust { get; init; } = "signed-executable";
    public string[] Extensions { get; init; } = [];
}

public static class SignerIdentity
{
    public static string NormalizeSubject(string subject)
    {
        if (string.IsNullOrWhiteSpace(subject)) return "";
        try
        {
            var formatted = new X500DistinguishedName(subject).Format(false);
            return Regex.Replace(formatted, @"\s+", "").Trim().ToUpperInvariant();
        }
        catch { return Regex.Replace(subject, @"\s+", "").Trim().ToUpperInvariant(); }
    }

    public static bool MatchesExact(string subject, IEnumerable<string> expected)
        => expected.Any(value => NormalizeSubject(subject).Equals(NormalizeSubject(value), StringComparison.Ordinal));
}

public static class VendorReleaseAuthenticity
{
    public static string NormalizeDigest(string digest)
    {
        var normalized = (digest ?? "").Trim();
        if (normalized.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase)) normalized = normalized[7..];
        if (!Regex.IsMatch(normalized, "^[0-9a-fA-F]{64}$")) throw new InvalidDataException("Vendor release digest must be a SHA-256 value.");
        return normalized.ToLowerInvariant();
    }

    public static string VerifySha256(string path, string expectedDigest)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("Vendor release artifact is missing.", path);
        var expected = NormalizeDigest(expectedDigest);
        using var stream = File.OpenRead(path);
        var actual = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException($"Vendor release SHA-256 mismatch for {Path.GetFileName(path)}: expected {expected}, got {actual}.");
        return actual;
    }
}

public sealed class VersionProbe
{
    public string[] Arguments { get; init; } = ["--version"];
    public string? Regex { get; init; } = @"(?<!\d)(\d+\.\d+(?:\.\d+){0,2})";
}

public sealed class DependencyManifestDocument
{
    public int SchemaVersion { get; init; }
    public string ManifestVersion { get; init; } = "";
    public string SupportedProfile { get; init; } = "";
    public List<DependencyDefinition> Dependencies { get; init; } = [];
}

public sealed record DependencyDetection(string Name, bool Found, string ExecutablePath, Version? Version, bool Compatible, string Source, string Classification)
{
    public string Status => !Found ? "Missing" : Version is null ? "Broken" : Compatible ? "Compatible" : "Outdated";
}
public sealed record WingetHealth(string Status, string ExecutablePath, string Version, string Detail);
public sealed record TailscaleAuthentication(string State, Uri? AuthenticationUri, string Detail, bool TimedOut = false);

public sealed record InstallStage(string Name, string Script, IReadOnlyList<string> Roles);

public static class InstallerStageCatalog
{
    public static IReadOnlyList<InstallStage> ForRole(string role)
    {
        if (role.Contains("Laptop", StringComparison.OrdinalIgnoreCase))
            return [
                new("Preflight", "windows/00-Preflight.ps1", ["Laptop"]),
                new("Prerequisites", "windows/01-Install-Prerequisites.ps1", ["Laptop"]),
                new("Windows Tailscale", "windows/04a-Connect-WindowsTailscale.ps1", ["Laptop"]),
                new("Host Agent", "windows/Install-DevFleet-HostAgent.ps1", ["Laptop"]),
                new("Failover compute", "windows/02-Provision-ComputeNode.ps1", ["Laptop"]),
                new("Vault", "windows/03-Provision-Vault.ps1", ["Laptop"]),
                new("Failover Tailscale", "windows/04-Connect-Tailscale.ps1", ["Laptop"]),
                new("Vault client", "windows/05-Configure-LocalVaultClient.ps1", ["Laptop"]),
                new("Shortcuts", "windows/08-Install-Shortcuts.ps1", ["Laptop"]),
                new("Laptop bootstrap export", "windows/09-Export-Laptop-Bootstrap.ps1", ["Laptop"]),
                new("Verification", "windows/Test-DevFleet.ps1", ["Laptop"])
            ];
        if (role.Contains("Desktop", StringComparison.OrdinalIgnoreCase) || role.Contains("Primary", StringComparison.OrdinalIgnoreCase))
            return [
                new("Preflight", "windows/00-Preflight.ps1", ["Desktop"]),
                new("Prerequisites", "windows/01-Install-Prerequisites.ps1", ["Desktop"]),
                new("Windows Tailscale", "windows/04a-Connect-WindowsTailscale.ps1", ["Desktop"]),
                new("Host Agent", "windows/Install-DevFleet-HostAgent.ps1", ["Desktop"]),
                new("Primary compute", "windows/02-Provision-ComputeNode.ps1", ["Desktop"]),
                new("Primary Tailscale", "windows/04-Connect-Tailscale.ps1", ["Desktop"]),
                new("Shortcuts", "windows/08-Install-Shortcuts.ps1", ["Desktop"]),
                new("Desktop pairing export", "windows/10-Export-Desktop-Pairing.ps1", ["Desktop"]),
                new("Verification", "windows/Test-DevFleet.ps1", ["Desktop"])
            ];
        throw new InvalidOperationException($"Unsupported DevFleet role: {role}");
    }
}

public sealed record InstallerExecutionReport(string Mode, string Role, IReadOnlyList<string> Stages, bool NetworkDownloadsAttempted, int ExitCode, string Detail);

public sealed class InstallService
{
    // Compatibility name retained for existing diagnostics; the effective
    // connected transaction deadline is role-aware and composed by
    // DeadlinePolicy.GetConnectedTransactionBudgetSeconds.
    public static readonly int ConnectedInstallTimeoutSeconds = DeadlinePolicy.DesktopTransactionSeconds;
    private readonly IProcessRunner _runner;
    private readonly bool _usesDefaultRunner;
    public InstallService(IProcessRunner? runner = null)
    {
        _usesDefaultRunner = runner is null;
        _runner = runner ?? new ProcessRunner(DeadlinePolicy.DesktopTransactionSeconds, allowEnvironmentOverride: false);
    }

    public InstallerExecutionReport Run(string releaseRoot, string role, string mode, Action<string>? progress = null, bool deferNetworkPairing = false, bool acknowledgeRootfulDocker = false, string? transactionId = null, string? transactionPayloadSha256 = null, string? transactionAction = null, string? transactionRole = null, string? transactionPreparedUtc = null)
    {
        var stages = InstallerStageCatalog.ForRole(role);
        foreach (var stage in stages) progress?.Invoke($"Stage planned: {stage.Name} ({stage.Script})");
        var script = Path.Combine(releaseRoot, "Install-DevFleet.ps1");
        if (!File.Exists(script)) throw new FileNotFoundException("The real DevFleet installation entry point is missing.", script);
        var normalizedRole = role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
        var transactionBudgetSeconds = DeadlinePolicy.GetConnectedTransactionBudgetSeconds(normalizedRole);
        var transactionDeadlineUtc = DateTime.UtcNow.AddSeconds(transactionBudgetSeconds);
        var bootstrap = Path.Combine(releaseRoot, "Bootstrap-Install.ps1");
        var entry = File.Exists(bootstrap) ? bootstrap : script;
        var args = new List<string> { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", entry, "-Role", normalizedRole, "-NonInteractive", "-PackageRoot", releaseRoot, "-InstallationMode", "Connected", "-SkipWindowsUpdates", "-TransactionDeadlineUtc", transactionDeadlineUtc.ToString("O"), "-DeadlinePolicyVersion", DeadlinePolicy.Version };
        if (!string.IsNullOrWhiteSpace(transactionId) && !string.IsNullOrWhiteSpace(transactionPayloadSha256) && !string.IsNullOrWhiteSpace(transactionAction) && !string.IsNullOrWhiteSpace(transactionRole) && !string.IsNullOrWhiteSpace(transactionPreparedUtc))
        {
            var propagatedRole = transactionRole.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
            args.AddRange(["-TransactionId", transactionId, "-TransactionPayloadSha256", transactionPayloadSha256, "-TransactionAction", transactionAction, "-TransactionRole", propagatedRole, "-TransactionPreparedUtc", transactionPreparedUtc]);
        }
        if (deferNetworkPairing) args.Add("-DeferNetworkPairing");
        if (acknowledgeRootfulDocker) args.Add("-AcknowledgeRootfulDocker");
        progress?.Invoke($"Invoking actual connected installation chain: {Path.GetFileName(entry)} -Role {normalizedRole} -NonInteractive -InstallationMode Connected{(deferNetworkPairing ? " -DeferNetworkPairing" : "")}");
        var runner = _usesDefaultRunner ? new ProcessRunner(transactionBudgetSeconds, allowEnvironmentOverride: false) : _runner;
        var result = runner.Run(FindPowerShell(entry), args, releaseRoot);
        if (result.ExitCode == 3010)
            return new InstallerExecutionReport(mode, normalizedRole, Array.Empty<string>(), true, result.ExitCode, "The verified installer entry point persisted a reboot checkpoint." + (result.OutputComplete ? "" : " Redirected output was incomplete after the bounded post-exit drain."));
        if (result.ExitCode != 0) throw new InvalidOperationException($"DevFleet installation chain failed ({result.ExitCode}): {result.StandardError}{(result.OutputComplete ? "" : " [redirected output incomplete after bounded post-exit drain]")}");
        foreach (var stage in stages) progress?.Invoke($"Stage verified by entry-point completion: {stage.Name}");
        return new InstallerExecutionReport(mode, normalizedRole, stages.Select(s => s.Name).ToArray(), true, result.ExitCode, result.OutputComplete ? result.StandardOutput.Trim() : "Installer entry point exited 0; redirected output was incomplete after the bounded post-exit drain.");
    }

    private static string FindPowerShell(string entry) => TrustedExecutableResolver.PowerShellPath();
}

internal static class TrustedExecutableResolver
{
    public static string PowerShellPath()
    {
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var pwsh = Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe");
        if (File.Exists(pwsh)) return pwsh;
        var systemPowerShell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        if (File.Exists(systemPowerShell)) return systemPowerShell;
        throw new FileNotFoundException("No trusted machine PowerShell executable was found.");
    }

    public static string SystemExecutable(string name)
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), name);
        if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0) return path;
        throw new FileNotFoundException($"No trusted system executable was found: {name}", path);
    }

    public static string VsCodePath()
    {
        var candidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft VS Code", "Code.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft VS Code", "Code.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Microsoft VS Code", "Code.exe")
        };
        foreach (var candidate in candidates)
        {
            if (!File.Exists(candidate) || (File.GetAttributes(candidate) & FileAttributes.ReparsePoint) != 0) continue;
            var full = Path.GetFullPath(candidate);
            if (full.EndsWith(Path.Combine("Microsoft VS Code", "Code.exe"), StringComparison.OrdinalIgnoreCase)) return full;
        }
        throw new FileNotFoundException("A trusted Microsoft VS Code installation was not found in an expected install root.");
    }
}

public sealed class RepairService
{
    private readonly InstallService _install;
    public RepairService(InstallService? install = null) => _install = install ?? new InstallService();
    public InstallerExecutionReport Repair(string releaseRoot, string role, Action<string>? progress = null, bool deferNetworkPairing = false, bool acknowledgeRootfulDocker = false, string? transactionId = null, string? transactionPayloadSha256 = null, string? transactionAction = null, string? transactionRole = null, string? transactionPreparedUtc = null) => _install.Run(releaseRoot, role, "Repair", progress, deferNetworkPairing, acknowledgeRootfulDocker, transactionId, transactionPayloadSha256, transactionAction, transactionRole, transactionPreparedUtc);
}

public sealed class CleanReinstallService
{
    public void PreserveAndReconcile(IReadOnlyList<DiscoveredProject> projects, Action<string>? progress = null)
    {
        progress?.Invoke($"Clean Reinstall preservation plan verified for {projects.Count} discovered project(s); project VMs and backups remain outside the control-plane removal scope.");
    }
}

public sealed class UninstallService
{
    public void RemoveOwnedControlPlane(IReadOnlyList<string> files, IReadOnlyList<string> shortcuts, Action<string>? progress = null)
    {
        foreach (var file in files.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (File.Exists(file)) File.Delete(file);
            if (File.Exists(file)) throw new IOException($"Owned file remains after uninstall cleanup: {file}");
            progress?.Invoke($"Uninstall verified owned file absent: {file}");
        }
        foreach (var shortcut in shortcuts.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (File.Exists(shortcut)) File.Delete(shortcut);
            if (File.Exists(shortcut)) throw new IOException($"Owned shortcut remains after uninstall cleanup: {shortcut}");
            progress?.Invoke($"Uninstall verified owned shortcut absent: {shortcut}");
        }
    }
}

public static class CleanupJournalService
{
    private sealed class Journal
    {
        public int SchemaVersion { get; set; } = 1;
        public string TransactionId { get; set; } = "";
        public string Mode { get; set; } = "";
        public string InstallationGeneration { get; set; } = "";
        public string PayloadFingerprint { get; set; } = "";
        public List<string> CompletedStages { get; set; } = [];
        public string State { get; set; } = "in-progress";
        public string? LastError { get; set; }
        public string UpdatedUtc { get; set; } = "";
    }

    private static string PathFor(string mode) => Path.Combine(AppPaths.StateRoot, $"{mode.ToLowerInvariant()}-cleanup-journal.json");
    private static Journal ReadOrCreate(string mode, string transactionId, string installationGeneration, string payloadFingerprint)
    {
        var path = PathFor(mode);
        if (File.Exists(path))
        {
            var existing = JsonSerializer.Deserialize<Journal>(File.ReadAllText(path));
            if (existing is not null && existing.Mode.Equals(mode, StringComparison.OrdinalIgnoreCase) && existing.TransactionId == transactionId && existing.InstallationGeneration == installationGeneration && existing.PayloadFingerprint == payloadFingerprint) return existing;
        }
        return new Journal { TransactionId = transactionId, Mode = mode, InstallationGeneration = installationGeneration, PayloadFingerprint = payloadFingerprint, UpdatedUtc = DateTime.UtcNow.ToString("O") };
    }

    private static void Save(string mode, Journal journal)
    {
        Directory.CreateDirectory(AppPaths.StateRoot);
        journal.UpdatedUtc = DateTime.UtcNow.ToString("O");
        var path = PathFor(mode); var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(journal, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, path, true);
    }

    public static void Execute(string mode, string transactionId, IReadOnlyList<(string Name, Action Action)> stages, Action<string>? progress = null, string installationGeneration = "", string payloadFingerprint = "")
    {
        var journal = ReadOrCreate(mode, transactionId, installationGeneration, payloadFingerprint); Save(mode, journal);
        foreach (var stage in stages)
        {
            if (journal.CompletedStages.Contains(stage.Name, StringComparer.OrdinalIgnoreCase)) continue;
            try
            {
                stage.Action();
                journal.CompletedStages.Add(stage.Name); journal.LastError = null; Save(mode, journal);
                progress?.Invoke($"Cleanup stage completed: {stage.Name}");
            }
            catch (Exception ex)
            {
                journal.State = "incomplete"; journal.LastError = ex.Message; Save(mode, journal);
                throw;
            }
        }
        journal.State = "completed"; journal.LastError = null; Save(mode, journal);
        var activePath = PathFor(mode); var historyRoot = Path.Combine(AppPaths.StateRoot, "cleanup-history"); Directory.CreateDirectory(historyRoot);
        File.Move(activePath, Path.Combine(historyRoot, $"{mode.ToLowerInvariant()}-{transactionId}.json"), true);
    }
}

public sealed class FactoryResetService
{
    private readonly VmOwnershipService _vms;
    public FactoryResetService(BackupVerificationService _, VmOwnershipService vms) { _vms = vms; }
    public void DeleteSelected(DiscoveredProject project, Action<string>? progress = null)
    {
        // Historical backups are restore points only.  Destructive authorization
        // must use a new backup made for this exact reset transaction.
        var backup = _vms.CreateFreshSafetyBackup(project, progress);
        if (!backup.IsVerified) throw new InvalidOperationException($"Factory Reset blocked for {project.Slug}: fresh safety backup verification failed.");
        _vms.DeleteOwnedExact(project.ProjectId, project.RuntimeId, backup, progress);
    }
}

public sealed class DependencyService
{
    private readonly IProcessRunner _runner;
    private readonly HttpClient _http;
    private readonly Dictionary<string, string> _verifiedVendorDigests = new(StringComparer.OrdinalIgnoreCase);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { PropertyNameCaseInsensitive = true };
    public DependencyService(IProcessRunner? runner = null, HttpClient? http = null) { _runner = runner ?? new ProcessRunner(); _http = http ?? new HttpClient(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromMinutes(5) }; }
    public static IReadOnlyList<DependencyDefinition> Catalog { get; } = LoadCatalog();

    private static IReadOnlyList<DependencyDefinition> LoadCatalog()
    {
#if DEBUG
        var path = Environment.GetEnvironmentVariable("DEVFLEET_SETUP_DEPENDENCY_MANIFEST");
        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
            return ReadManifest(File.ReadAllText(path));
#endif
        var release = Path.Combine(AppPaths.InstallRoot, "Release", PayloadManifest.DevFleetVersion, "dependencies.json");
        if (File.Exists(release)) return ReadManifest(File.ReadAllText(release));
        var assembly = typeof(DependencyService).Assembly;
        var resource = assembly.GetManifestResourceNames().FirstOrDefault(x => x.EndsWith("dependencies.json", StringComparison.OrdinalIgnoreCase));
        if (resource is not null)
        {
            using var stream = assembly.GetManifestResourceStream(resource);
            using var reader = new StreamReader(stream ?? throw new InvalidDataException("Dependency manifest resource is unavailable."));
            return ReadManifest(reader.ReadToEnd());
        }
        throw new InvalidDataException("Canonical dependencies.json was not embedded or staged.");
    }

    private static IReadOnlyList<DependencyDefinition> ReadManifest(string json)
    {
        var manifest = JsonSerializer.Deserialize<DependencyManifestDocument>(json, JsonOptions)
            ?? throw new InvalidDataException("Canonical dependency manifest is empty.");
        if (manifest.SchemaVersion != 1 || manifest.ManifestVersion != PayloadManifest.DevFleetVersion || manifest.Dependencies.Count == 0)
            throw new InvalidDataException("Canonical dependency manifest version or schema is invalid.");
        return manifest.Dependencies;
    }

    public DependencyDetection Detect(DependencyDefinition dependency)
    {
        DependencyDetection? firstObserved = null;
        foreach (var candidate in CandidatePaths(dependency).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!File.Exists(candidate)) continue;
            if (!IsTrustedInstalledDependency(candidate, dependency)) continue;
            var version = ReadVersion(candidate, dependency);
            var compatible = version is not null && version >= dependency.MinimumVersion && (!dependency.MaximumMajor.HasValue || version.Major <= dependency.MaximumMajor.Value);
            var observed = new DependencyDetection(dependency.Name, true, Path.GetFullPath(candidate), version, compatible, "trusted machine PATH/HKLM/known-path discovery", dependency.Classification);
            firstObserved ??= observed;
            if (compatible) return observed;
        }
        return firstObserved ?? new(dependency.Name, false, "", null, false, "not detected or no trusted candidate", dependency.Classification);
    }

    public DependencyDetection ResolveCompatibleVersion(DependencyDefinition dependency) => Detect(dependency);

    public WingetHealth GetWingetHealth()
    {
        var wingetPolicy = new DependencyDefinition { DisplayName = "WinGet", InstallerAuthenticityPolicy = new InstallerAuthenticityPolicy { Required = true, AllowedSignerSubjectsExact = ["CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"] } };
        var winget = LocateOnPath("winget.exe", wingetPolicy);
        if (winget is null) return new("Missing", "", "", "winget.exe was not found on PATH.");
        var info = _runner.Run(winget, ["--version"]);
        if (info.ExitCode != 0) return new("Broken", winget, "", "winget --version failed: " + info.StandardError.Trim());
        if (!info.OutputComplete) return new("Broken", winget, "", "winget --version output was incomplete after the bounded post-exit drain.");
        var version = ExtractVersion(info.StandardOutput + " " + info.StandardError)?.ToString() ?? "Unknown";
        var sources = _runner.Run(winget, ["source", "list", "--disable-interactivity"]);
        if (sources.ExitCode != 0) return new("SourceBroken", winget, version, "winget source list failed: " + sources.StandardError.Trim());
        if (!sources.OutputComplete) return new("SourceBroken", winget, version, "winget source list output was incomplete after the bounded post-exit drain.");
        var search = _runner.Run(winget, ["search", "--id", "Microsoft.PowerShell", "--exact", "--source", "winget", "--disable-interactivity"]);
        if (search.ExitCode != 0) return new("SourceBroken", winget, version, "winget search failed: " + search.StandardError.Trim());
        if (!search.OutputComplete) return new("SourceBroken", winget, version, "winget search output was incomplete after the bounded post-exit drain.");
        return new("Healthy", winget, version, "version, source list and package search succeeded.");
    }

    public ProcessResult RepairWinget()
    {
        var command = "Install-PackageProvider -Name NuGet -Force | Out-Null; Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null; Repair-WinGetPackageManager -Force -Latest";
        return _runner.Run(TrustedExecutableResolver.PowerShellPath(), ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command]);
    }

    public string DownloadOfficial(DependencyDefinition dependency, string destinationRoot)
    {
        Directory.CreateDirectory(destinationRoot);
        var winget = GetWingetHealth();
        if (winget.Status == "Healthy" && !string.IsNullOrWhiteSpace(dependency.WingetPackageId))
        {
            var result = _runner.Run(winget.ExecutablePath, ["download", "--id", dependency.WingetPackageId!, "--exact", "--source", "winget", "--accept-source-agreements", "--accept-package-agreements", "--download-directory", destinationRoot]);
            if (result.ExitCode == 0)
            {
                var package = Directory.EnumerateFiles(destinationRoot, "*", SearchOption.AllDirectories).OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();
                if (package is not null) return package;
            }
        }
        return DownloadDirectOfficial(dependency, destinationRoot);
    }

    private string DownloadDirectOfficial(DependencyDefinition dependency, string destinationRoot)
    {
        if (dependency.DirectOfficialVendorResolver.Type.Equals("windows-capability", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"{dependency.Name} requires the supported Windows capability path; no executable vendor payload is applicable.");
        var metadataUri = dependency.OfficialMetadata;
        if (!dependency.DirectOfficialVendorResolver.AllowedHosts.Contains(metadataUri.Host, StringComparer.OrdinalIgnoreCase))
            throw new InvalidDataException($"Official metadata host is not allowlisted for {dependency.Name}: {metadataUri.Host}");
        using var response = GetAllowlistedResponse(metadataUri, dependency.DirectOfficialVendorResolver.AllowedHosts, dependency.Name);
        response.EnsureSuccessStatusCode();
        var pattern = dependency.DirectOfficialVendorResolver.AssetRegex ?? throw new InvalidDataException($"No official asset rule for {dependency.Name}.");
        string assetName;
        Uri url;
        string? expectedDigest = null;
        if (dependency.DirectOfficialVendorResolver.Type.Equals("github-release", StringComparison.OrdinalIgnoreCase))
        {
            using var json = JsonDocument.Parse(response.Content.ReadAsStream());
            var root = json.RootElement;
            var tag = root.GetProperty("tag_name").GetString() ?? throw new InvalidDataException($"Official release tag is missing for {dependency.Name}.");
            if (!string.IsNullOrWhiteSpace(dependency.DirectOfficialVendorResolver.ExpectedOwner) && root.GetProperty("author").GetProperty("login").GetString() != dependency.DirectOfficialVendorResolver.ExpectedOwner)
                throw new InvalidDataException($"Official release owner mismatch for {dependency.Name}.");
            if (!string.IsNullOrWhiteSpace(dependency.DirectOfficialVendorResolver.ExpectedRepository) && !(root.GetProperty("html_url").GetString() ?? "").Contains($"/{dependency.DirectOfficialVendorResolver.ExpectedOwner}/{dependency.DirectOfficialVendorResolver.ExpectedRepository}/releases/", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"Official release repository mismatch for {dependency.Name}.");
            string? pageAssetName = null;
            if (!string.IsNullOrWhiteSpace(dependency.DirectOfficialVendorResolver.OfficialPageUri))
            {
                using var pageResponse = GetAllowlistedResponse(new Uri(dependency.DirectOfficialVendorResolver.OfficialPageUri), dependency.DirectOfficialVendorResolver.AllowedHosts, dependency.Name);
                var page = pageResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                var pagePattern = dependency.DirectOfficialVendorResolver.OfficialPageAssetRegex ?? pattern;
                foreach (Match match in Regex.Matches(page, "href\\s*=\\s*['\"](?<href>[^'\"]+)['\"]", RegexOptions.IgnoreCase))
                {
                    var href = match.Groups["href"].Value;
                    if (Uri.TryCreate(href, UriKind.Absolute, out var pageUri) && Regex.IsMatch(Path.GetFileName(pageUri.AbsolutePath), pagePattern) && pageUri.AbsolutePath.Contains($"/releases/download/{tag}/", StringComparison.OrdinalIgnoreCase))
                    {
                        pageAssetName = Path.GetFileName(pageUri.AbsolutePath);
                        break;
                    }
                }
                if (pageAssetName is null) throw new InvalidDataException($"Official download page did not identify a release asset matching tag {tag} for {dependency.Name}.");
            }
            var assets = root.GetProperty("assets").EnumerateArray().Where(x => Regex.IsMatch(x.GetProperty("name").GetString() ?? "", pattern) && (pageAssetName is null || x.GetProperty("name").GetString() == pageAssetName)).ToArray();
            if (assets.Length != 1) throw new InvalidDataException($"Expected exactly one official x64 asset for {dependency.Name}, found {assets.Length}.");
            var asset = assets[0];
            assetName = asset.GetProperty("name").GetString()!;
            url = new Uri(asset.GetProperty("browser_download_url").GetString() ?? "");
            if (!url.AbsolutePath.Contains($"/{dependency.DirectOfficialVendorResolver.ExpectedOwner}/{dependency.DirectOfficialVendorResolver.ExpectedRepository}/releases/download/{tag}/", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException($"Official release asset path/tag mismatch for {dependency.Name}.");
            if (asset.TryGetProperty("digest", out var digestElement)) expectedDigest = digestElement.GetString();
        }
        else if (dependency.DirectOfficialVendorResolver.Type.Equals("official-download-page", StringComparison.OrdinalIgnoreCase))
        {
            if (!string.IsNullOrWhiteSpace(dependency.DirectOfficialVendorResolver.DirectUri))
            {
                var directUri = new Uri(dependency.DirectOfficialVendorResolver.DirectUri);
                if (!dependency.DirectOfficialVendorResolver.AllowedHosts.Contains(directUri.Host, StringComparer.OrdinalIgnoreCase)) throw new InvalidDataException($"Official direct URI host is not allowlisted for {dependency.Name}: {directUri.Host}");
                using var directResponse = GetAllowlistedResponse(directUri, dependency.DirectOfficialVendorResolver.AllowedHosts, dependency.Name);
                url = directResponse.RequestMessage?.RequestUri ?? directUri;
                assetName = Path.GetFileName(url.AbsolutePath);
                if (string.IsNullOrWhiteSpace(assetName) || !Regex.IsMatch(assetName, pattern)) throw new InvalidDataException($"Official direct URI resolved to an unexpected asset for {dependency.Name}: {assetName}");
            }
            else
            {
                var html = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                var links = Regex.Matches(html, @"href\s*=\s*[""'](?<href>[^""']+)[""']", RegexOptions.IgnoreCase).Select(x => x.Groups["href"].Value);
                var selected = links.Select(x => Uri.TryCreate(metadataUri, x, out var candidate) ? candidate : null).Where(x => x is not null && dependency.DirectOfficialVendorResolver.AllowedHosts.Contains(x.Host, StringComparer.OrdinalIgnoreCase) && Regex.IsMatch(Path.GetFileName(x.AbsolutePath), pattern)).FirstOrDefault();
                if (selected is null) throw new InvalidDataException($"No allowlisted official download-page asset matched for {dependency.Name}.");
                url = selected;
                assetName = Path.GetFileName(url.AbsolutePath);
            }
        }
        else throw new InvalidOperationException($"Direct official resolver is not implemented for {dependency.Name}; refusing an unauthenticated fallback. Metadata: {dependency.OfficialMetadata}");
        if (!dependency.DirectOfficialVendorResolver.AllowedHosts.Contains(url.Host, StringComparer.OrdinalIgnoreCase)) throw new InvalidDataException($"Official asset host is not allowlisted for {dependency.Name}: {url.Host}");
        var path = Path.Combine(destinationRoot, assetName);
        Exception? last = null;
        for (var attempt = 1; attempt <= 3; attempt++)
        {
            try
            {
                using var downloadResponse = GetAllowlistedResponse(url, dependency.DirectOfficialVendorResolver.AllowedHosts, dependency.Name);
                using var download = downloadResponse.Content.ReadAsStream();
                using var output = File.Create(path);
                download.CopyTo(output);
                if (dependency.InstallerAuthenticityPolicy.Strategy is "VendorReleaseSha256" or "AuthenticodeOrVendorReleaseSha256")
                {
                    if (string.IsNullOrWhiteSpace(expectedDigest)) throw new InvalidDataException($"Official vendor release did not provide a SHA-256 digest for {dependency.Name}.");
                    _verifiedVendorDigests[path] = VendorReleaseAuthenticity.NormalizeDigest(expectedDigest);
                    VendorReleaseAuthenticity.VerifySha256(path, expectedDigest);
                }
                return path;
            }
            catch (Exception ex) when (attempt < 3) { last = ex; Thread.Sleep(TimeSpan.FromSeconds(attempt)); }
        }
        throw new IOException($"Official download failed after bounded retries for {dependency.Name}.", last);
    }

    public void VerifyInstaller(string installerPath, DependencyDefinition? dependency = null)
    {
        if (!File.Exists(installerPath)) throw new FileNotFoundException("Dependency installer is missing.", installerPath);
        if (dependency?.InstallerAuthenticityPolicy.Strategy is "VendorReleaseSha256" or "AuthenticodeOrVendorReleaseSha256")
        {
            if (!_verifiedVendorDigests.TryGetValue(installerPath, out var digest)) throw new InvalidDataException($"No verified official vendor digest is bound to {Path.GetFileName(installerPath)}.");
            VendorReleaseAuthenticity.VerifySha256(installerPath, digest);
            return;
        }
        var escaped = installerPath.Replace("'", "''");
        var result = _runner.Run(TrustedExecutableResolver.PowerShellPath(), ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", $"$s=Get-AuthenticodeSignature -LiteralPath '{escaped}'; if($s.Status -ne 'Valid'){{exit 9}}; $s.SignerCertificate.Subject"]);
        if (result.ExitCode != 0 || !result.OutputComplete || string.IsNullOrWhiteSpace(result.StandardOutput)) throw new InvalidDataException($"Authenticode verification failed for {Path.GetFileName(installerPath)}{(result.OutputComplete ? "." : ": redirected signer output was incomplete.")}");
        if (dependency is not null && dependency.InstallerAuthenticityPolicy.AllowedSignerSubjectsExact.Length > 0)
        {
            var subject = result.StandardOutput.Trim();
            if (!SignerIdentity.MatchesExact(subject, dependency.InstallerAuthenticityPolicy.AllowedSignerSubjectsExact))
                throw new InvalidDataException($"Authenticode signer is not allowlisted for {dependency.Name}: {subject}");
        }
        else if (dependency is not null && dependency.InstallerAuthenticityPolicy.AllowedSignerPatterns.Length > 0)
            throw new InvalidDataException($"Legacy substring signer policy is rejected for {dependency.Name}; release policy must provide AllowedSignerSubjectsExact.");
    }

    private HttpResponseMessage GetAllowlistedResponse(Uri initialUri, IReadOnlyCollection<string> allowedHosts, string dependencyName)
    {
        var uri = initialUri;
        for (var hop = 0; hop <= 5; hop++)
        {
            if (!uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(uri.Host) || !string.IsNullOrEmpty(uri.UserInfo))
                throw new InvalidDataException($"Official download redirect is not an allowlisted HTTPS URI for {dependencyName}: {uri}");
            if (!allowedHosts.Contains(uri.Host, StringComparer.OrdinalIgnoreCase))
                throw new InvalidDataException($"Official download host is not allowlisted for {dependencyName}: {uri.Host}");
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            request.Headers.UserAgent.ParseAdd($"DevFleet-Setup/{PayloadManifest.InstallerVersion}");
            var response = _http.Send(request);
            if ((int)response.StatusCode is >= 300 and <= 399)
            {
                var location = response.Headers.Location;
                response.Dispose();
                if (location is null) throw new InvalidDataException($"Official download redirect omitted Location for {dependencyName}.");
                uri = new Uri(uri, location);
                continue;
            }
            response.EnsureSuccessStatusCode();
            return response;
        }
        throw new InvalidDataException($"Official download exceeded the redirect limit for {dependencyName}.");
    }

    public DependencyResult Install(DependencyDefinition dependency, string installerPath)
    {
        VerifyInstaller(installerPath, dependency);
        var args = dependency.SilentInstallArguments.Length == 0 ? ["/quiet", "/norestart"] : dependency.SilentInstallArguments;
        ProcessResult result = Path.GetExtension(installerPath).Equals(".msi", StringComparison.OrdinalIgnoreCase)
            ? _runner.Run(TrustedExecutableResolver.SystemExecutable("msiexec.exe"), ["/i", installerPath, .. args])
            : _runner.Run(installerPath, args);
        if (result.ExitCode is not (0 or 3010)) throw new InvalidOperationException($"{dependency.Name} installation failed ({result.ExitCode}): {result.StandardError}");
        var detected = Detect(dependency);
        if (!detected.Compatible) throw new InvalidOperationException($"{dependency.Name} completed but a compatible executable was not discovered.");
        return new(true, true, result.ExitCode == 3010, $"{dependency.Name} {detected.Version} at {detected.ExecutablePath}");
    }

    public IReadOnlyList<DependencyDetection> DetectAll() => Catalog.Select(Detect).ToArray();
    public DependencyResult VerifyLocalPayload(string dependencyRoot)
    {
        if (!Directory.Exists(dependencyRoot)) return new(false, false, false, "Offline prerequisite payload directory is absent.");
        var manifestPath = Path.Combine(dependencyRoot, "OFFLINE-DEPENDENCIES.json");
        if (!File.Exists(manifestPath)) return new(false, false, false, "Release-bound offline dependency manifest is absent.");
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(manifestPath));
            var root = document.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != 2 || root.GetProperty("devfleetVersion").GetString() != PayloadManifest.DevFleetVersion || !root.TryGetProperty("releaseBinding", out _))
                return new(false, false, false, "Offline dependency manifest is not bound to this release.");
            if (!root.TryGetProperty("payloads", out var payloads) || payloads.ValueKind != JsonValueKind.Array)
                return new(false, false, false, "Release-bound offline payload entries are absent.");
            var entries = payloads.EnumerateArray().ToArray();
            var entryByName = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in entries)
            {
                var fileName = entry.GetProperty("filename").GetString() ?? "";
                var dependencyId = entry.GetProperty("dependencyId").GetString() ?? "";
                var expectedSha = entry.GetProperty("sha256").GetString() ?? "";
                var expectedSize = entry.GetProperty("sizeBytes").GetInt64();
                if (string.IsNullOrWhiteSpace(dependencyId) || string.IsNullOrWhiteSpace(fileName) || Path.IsPathRooted(fileName) || fileName.Contains("..", StringComparison.Ordinal) || !Regex.IsMatch(expectedSha, "^[0-9a-fA-F]{64}$") || expectedSize < 0 || !entryByName.TryAdd(fileName, entry))
                    return new(false, false, false, "Offline payload manifest contains an invalid or duplicate entry.");
            }
            var files = Directory.EnumerateFiles(dependencyRoot, "*", SearchOption.AllDirectories)
                .Where(path => !path.Equals(manifestPath, StringComparison.OrdinalIgnoreCase))
                .ToArray();
            var actualByName = files.ToDictionary(path => Path.GetRelativePath(dependencyRoot, path), StringComparer.OrdinalIgnoreCase);
            if (actualByName.Keys.Any(name => !ent