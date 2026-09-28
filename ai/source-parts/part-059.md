# DevFleet source part 059

Full-source UTF-8 byte interval [2697000, 2743500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 017f3eed4c3db4b1096d2787556656bc60b9a422495439b94f2d509e629b04f4

<!-- BEGIN SOURCE SLICE -->
ryByName.ContainsKey(name)) || entryByName.Keys.Any(name => !actualByName.ContainsKey(name)))
                return new(false, false, false, "Offline payload files must match the release-bound manifest exactly.");
            foreach (var (fileName, entry) in entryByName)
            {
                var path = actualByName[fileName];
                var expectedSize = entry.GetProperty("sizeBytes").GetInt64();
                var expectedSha = entry.GetProperty("sha256").GetString()!.ToLowerInvariant();
                if (new FileInfo(path).Length != expectedSize) return new(false, false, false, $"Offline payload size mismatch: {fileName}.");
                using var stream = File.OpenRead(path);
                var actualSha = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
                if (!actualSha.Equals(expectedSha, StringComparison.OrdinalIgnoreCase)) return new(false, false, false, $"Offline payload SHA-256 mismatch: {fileName}.");
                if (!entry.TryGetProperty("signerPolicy", out var signerPolicy) || signerPolicy.ValueKind != JsonValueKind.Object)
                    return new(false, false, false, $"Offline payload signer policy is missing: {fileName}.");
            }
            return new(files.Length > 0, false, false, files.Length > 0 ? $"Verified {files.Length} exact release-bound local dependency payload file(s); no installer was executed." : "No release-bound offline dependency payloads are included.");
        }
        catch (Exception ex) { return new(false, false, false, $"Offline dependency manifest is invalid: {ex.Message}"); }
    }

    private IEnumerable<string> CandidatePaths(DependencyDefinition dependency)
    {
        foreach (var executable in dependency.ExecutableProbes)
        {
            foreach (var command in LocateOnPathAll(executable)) yield return command;
            foreach (var hive in new[] { Registry.LocalMachine })
            foreach (var view in new[] { $@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{executable}", $@"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\{executable}" })
            {
                using var key = hive.OpenSubKey(view); var value = key?.GetValue(null)?.ToString(); if (!string.IsNullOrWhiteSpace(value)) yield return value.Trim('"');
            }
        }
        foreach (var known in dependency.KnownVendorInstallLocations.Select(Environment.ExpandEnvironmentVariables)) yield return known;
    }

    private bool IsTrustedInstalledDependency(string executable, DependencyDefinition dependency)
    {
        var full = Path.GetFullPath(executable);
        if (Path.GetExtension(full).Equals(".cmd", StringComparison.OrdinalIgnoreCase) || Path.GetExtension(full).Equals(".bat", StringComparison.OrdinalIgnoreCase)) return false;
        if ((File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0) return false;
        string systemRoot;
        if (Path.GetFileName(full).Equals("winget.exe", StringComparison.OrdinalIgnoreCase))
        {
            // WinGet is trusted only beneath the exact physical AppX package
            // root returned by the identity probe, never merely because it is
            // somewhere below Program Files or a local WindowsApps alias.
            if (!TryGetTrustedWinGetPackageRoot(full, out systemRoot)) return false;
        }
        else if (!OwnedPathSafety.TryGetTrustedSystemRoot(full, out systemRoot)) return false;
        var trustedRoot = systemRoot;
        try
        {
            var cursor = new DirectoryInfo(Path.GetDirectoryName(full)!);
            var root = new DirectoryInfo(trustedRoot);
            if (!root.Exists || root.Attributes.HasFlag(FileAttributes.ReparsePoint)) return false;
            var reachedRoot = false;
            while (cursor is not null)
            {
                if ((cursor.Attributes & FileAttributes.ReparsePoint) != 0) return false;
                if (OperatingSystem.IsWindows())
                {
                    var acl = cursor.GetAccessControl();
                    foreach (var rule in acl.GetAccessRules(true, true, typeof(NTAccount)).OfType<FileSystemAccessRule>())
                    {
                        if (OwnedPathSafety.IsBroadUntrustedPrincipal(rule.IdentityReference.Value) && rule.AccessControlType == AccessControlType.Allow && OwnedPathSafety.HasPrimitiveMutationRights(rule.FileSystemRights)) return false;
                    }
                }
                if (cursor.FullName.TrimEnd(Path.DirectorySeparatorChar).Equals(root.FullName.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase))
                {
                    reachedRoot = true;
                    break;
                }
                cursor = cursor.Parent;
            }
            if (!reachedRoot) return false;
        }
        catch { return false; }
        var signer = ReadAuthenticodeSubject(full);
        var allowUnsignedInstalled = string.IsNullOrWhiteSpace(signer)
            && dependency.InstallerAuthenticityPolicy.InstalledExecutableTrust.Equals("signed-installer-locked-path", StringComparison.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(signer)) return allowUnsignedInstalled;
        var exact = dependency.InstallerAuthenticityPolicy.AllowedSignerSubjectsExact;
        if (exact.Length > 0) return SignerIdentity.MatchesExact(signer, exact);
        return dependency.InstallerAuthenticityPolicy.AllowedSignerPatterns.Length == 0;
    }

    private string? ReadAuthenticodeSubject(string executable)
    {
        var escaped = executable.Replace("'", "''", StringComparison.Ordinal);
        var result = _runner.Run(TrustedExecutableResolver.PowerShellPath(), ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", "$s=Get-AuthenticodeSignature -LiteralPath '" + escaped + "'; if($s.Status -ne 'Valid'){exit 9}; $s.SignerCertificate.Subject"]);
        return result.ExitCode == 0 && result.OutputComplete ? result.StandardOutput.Trim() : null;
    }

    private bool TryGetTrustedWinGetPackageRoot(string executable, out string packageRoot)
    {
        packageRoot = "";
        // The only accepted AppX identity is Microsoft.DesktopAppInstaller /
        // 8wekyb3d8bbwe, with an exact physical x64 package-root basename.
        var machineWindowsApps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsApps");
        var command = "Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' | ForEach-Object { $_.Name + '|' + $_.PublisherId + '|' + $_.InstallLocation }";
        var result = _runner.Run(TrustedExecutableResolver.PowerShellPath(), ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command]);
        if (result.ExitCode != 0 || !result.OutputComplete) return false;
        var matches = new List<string>();
        foreach (var line in result.StandardOutput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            var fields = line.Split('|', 3);
            if (fields.Length == 3 && OwnedPathSafety.IsExactWindowsAppxPackageCandidate(executable, fields[2].Trim(), machineWindowsApps, fields[0].Trim(), fields[1].Trim()))
            {
                matches.Add(Path.GetFullPath(fields[2].Trim()).TrimEnd(Path.DirectorySeparatorChar));
            }
        }
        if (matches.Distinct(StringComparer.OrdinalIgnoreCase).Count() != 1) return false;
        packageRoot = matches[0];
        return true;
    }

    private Version? ReadVersion(string executable, DependencyDefinition dependency)
    {
        if (dependency.Id == "virtualization-backend") return new Version(1, 0);
        var result = _runner.Run(executable, dependency.VersionProbe.Arguments);
        if (!result.OutputComplete) return null;
        var match = dependency.VersionProbe.Regex is null ? null : Regex.Match(result.StandardOutput + " " + result.StandardError, dependency.VersionProbe.Regex);
        return result.ExitCode == 0 && match is not null && match.Success && Version.TryParse(match.Groups[1].Value, out var version) ? version : null;
    }
    private static Version? ExtractVersion(string value) { var match = Regex.Match(value, @"(?<!\d)(\d+\.\d+(?:\.\d+){0,2})"); return match.Success && Version.TryParse(match.Groups[1].Value, out var v) ? v : null; }
    private static IEnumerable<string> LocateOnPathAll(string executable)
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        return path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries).Select(p => Path.Combine(p.Trim('"'), executable)).Where(File.Exists);
    }
    private string? LocateOnPath(string executable, DependencyDefinition dependency)
    {
        var candidates = LocateOnPathAll(executable).ToList();
        if (executable.Equals("winget.exe", StringComparison.OrdinalIgnoreCase))
        {
            var result = _runner.Run(TrustedExecutableResolver.PowerShellPath(), ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", "Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' | ForEach-Object { Join-Path $_.InstallLocation 'winget.exe' }"]);
            if (result.ExitCode == 0 && result.OutputComplete) candidates.AddRange(result.StandardOutput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries));
        }
        return candidates.Select(x => x.Trim()).Where(File.Exists).FirstOrDefault(path => IsTrustedInstalledDependency(path, dependency));
    }
}

public static class TailscaleAuthenticationService
{
    private static readonly Regex AuthUrl = new(@"https://login\.tailscale\.com/[A-Za-z0-9/_?=.&%-]+", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    public static Uri? ParseAuthenticationUri(string output)
    {
        var match = AuthUrl.Match(output ?? "");
        return match.Success && Uri.TryCreate(match.Value, UriKind.Absolute, out var uri) && uri.Host.Equals("login.tailscale.com", StringComparison.OrdinalIgnoreCase) ? uri : null;
    }
    public static TailscaleAuthentication Begin(IProcessRunner runner, string tailscalePath)
    {
        // Tailscale defaults to an unbounded wait when authentication is required.
        // Keep the UI responsive and expose the official URL after a bounded wait.
        var result = runner.Run(tailscalePath, ["up", "--timeout=30s"]);
        if (!result.OutputComplete) return new("Error", null, "Tailscale authentication output was incomplete; no authentication state or URL was accepted.");
        var uri = ParseAuthenticationUri(result.StandardOutput + Environment.NewLine + result.StandardError);
        if (uri is not null) return new("Authentication required", uri, "Open the official Tailscale authentication page after explicit user action.");
        if (result.ExitCode == 0) return new("Authenticated", null, "Tailscale reports an authenticated node.");
        return new("Error", null, $"Tailscale authentication command failed ({result.ExitCode}).");
    }
    public static async Task<TailscaleAuthentication> BeginAsync(IProcessRunner runner, string tailscalePath, CancellationToken cancellationToken = default)
    {
        var result = await runner.RunAsync(tailscalePath, ["up", "--timeout=30s"], cancellationToken: cancellationToken).ConfigureAwait(false);
        if (!result.OutputComplete) return new("Error", null, "Tailscale authentication output was incomplete; no authentication state or URL was accepted.");
        var uri = ParseAuthenticationUri(result.StandardOutput + Environment.NewLine + result.StandardError);
        if (uri is not null) return new("Authentication required", uri, "Open the official Tailscale authentication page after explicit user action.");
        if (result.ExitCode == 0) return new("Authenticated", null, "Tailscale reports an authenticated node.");
        return new("Error", null, $"Tailscale authentication command failed ({result.ExitCode}).");
    }
}

public sealed class RegistryService(IRegistryManager manager)
{
    public void RemoveExact(string key) => manager.RemoveExact(key);
}

public sealed class ShortcutService(IShortcutManager manager)
{
    public void RemoveExact(string path) => manager.RemoveExact(path);
}

public sealed class SshIntegrationService(ISshManager manager)
{
    public void RemoveManaged(string marker) => manager.RemoveManagedBlock(marker);
}

public sealed class VsCodeIntegrationService(IVsCodeManager manager)
{
    public void RemoveManaged(string alias) => manager.RemoveManagedAlias(alias);
}

public sealed class HostAgentService
{
    public bool IsPresent() => File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevFleetHostAgent", "DevFleet-HostAgent.ps1"));
}

public sealed class WindowsOwnedIntegrationCleanupService
{
    private readonly IProcessRunner _runner;
    public WindowsOwnedIntegrationCleanupService(IProcessRunner? runner = null) => _runner = runner ?? new ProcessRunner();
    public void Cleanup(InstallLedger ledger, Action<string>? progress = null)
    {
        if (!OperatingSystem.IsWindows()) return;
        if (ledger.WindowsIntegrations.Count == 0 || string.IsNullOrWhiteSpace(ledger.WindowsIntegrationOwnershipPath) || string.IsNullOrWhiteSpace(ledger.InstallationGeneration)) throw new InvalidOperationException("Windows integration cleanup requires an exact installation ownership binding; same-name foreign resources were preserved. Use the explicit legacy adoption workflow first.");
        var helper = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevFleetHostAgent", "Remove-DevFleet-OwnedIntegrations.ps1");
        if (!File.Exists(helper) || (File.GetAttributes(helper) & FileAttributes.ReparsePoint) != 0) throw new FileNotFoundException("Owned Windows integration cleanup helper is unavailable; resources were preserved.", helper);
        var result = _runner.Run(TrustedExecutableResolver.PowerShellPath(), ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper, "-OwnershipPath", ledger.WindowsIntegrationOwnershipPath, "-ExpectedGeneration", ledger.InstallationGeneration]);
        if (result.ExitCode != 0) throw new InvalidOperationException($"Owned integration cleanup failed or remained incomplete. Owned scheduled task remains after cleanup, owned firewall rule remains after cleanup, or owned service remains after cleanup: {result.StandardError.Trim()}");
        progress?.Invoke("Removed only ledger-bound DevFleet Host Agent task/service/firewall identities after live binding verification.");
    }
}

public sealed class RebootRequiredException(string message) : Exception(message);

public sealed record DiscoveredProject(string ProjectId, string Slug, string Provider, string RuntimeId, string OwnerProof, string BackupManifest, bool RestoreEligible)
{
    public string VmName { get; init; } = "";
    public string HostId { get; init; } = "";
    public string LifecycleState { get; init; } = "unknown";
    public bool IsDevFleetOwned { get; init; }
    public string OwnershipSource { get; init; } = "unknown";
    public bool ProjectIdVerified { get; init; }
    public bool RuntimeIdVerified { get; init; }
    public string AmbiguityReason { get; init; } = "";
    public string OwnershipStatus => IsDevFleetOwned && ProjectIdVerified && RuntimeIdVerified && string.IsNullOrWhiteSpace(AmbiguityReason) ? "VERIFIED" : (string.IsNullOrWhiteSpace(AmbiguityReason) ? "UNVERIFIED" : "AMBIGUOUS");
}

public sealed class ProjectDiscoveryService
{
    public IReadOnlyList<DiscoveredProject> Discover()
    {
        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        // An explicitly configured state root is the authoritative fixture/portable scope.
        // The normal production path remains Host Agent first when no override is present.
        var configuredStateRoot = TestEnvironment.IsTestProcess ? Environment.GetEnvironmentVariable("DEVFLEET_SETUP_STATE_ROOT") : null;
        var configured = new[] { Path.Combine(AppPaths.StateRoot, "projects.json"), Path.Combine(AppPaths.StateRoot, "HostAgent", "projects.json"), Path.Combine(AppPaths.StateRoot, "host-agent-registry.json") };
        var production = new[] { Path.Combine(programData, "DevFleetHostAgent", "projects.json"), Path.Combine(programData, "DevFleetHostAgent", "config.json"), Path.Combine(programData, "DevFleet", "projects.json") };
        var paths = string.IsNullOrWhiteSpace(configuredStateRoot) ? production.Concat(configured).ToArray() : configured.Concat(production).ToArray();
        foreach (var path in paths.Where(File.Exists))
        {
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                var values = doc.RootElement.ValueKind == JsonValueKind.Array ? doc.RootElement.EnumerateArray().ToArray() : doc.RootElement.TryGetProperty("projects", out var projects) ? (projects.ValueKind == JsonValueKind.Object ? projects.EnumerateObject().Select(x => x.Value).ToArray() : projects.EnumerateArray().ToArray()) : [];
                var data = values.Select(Parse).Where(x => x is not null).Cast<DiscoveredProject>().ToArray();
                if (data.Length > 0) return data;
            }
            catch { }
        }
        return StateStore.ReadLedger().OwnedResources.Where(x => !string.IsNullOrWhiteSpace(x.ProjectId)).Select(x => new DiscoveredProject(x.ProjectId, x.Identity, x.Kind.Contains("Multipass", StringComparison.OrdinalIgnoreCase) ? "Multipass" : x.Kind, x.Path, x.OwnerProof, "", false)
        {
            IsDevFleetOwned = x.OwnerProof.Equals("DevFleetLedger", StringComparison.OrdinalIgnoreCase),
            OwnershipSource = "installation-ledger",
            ProjectIdVerified = !string.IsNullOrWhiteSpace(x.ProjectId),
            RuntimeIdVerified = !string.IsNullOrWhiteSpace(x.Path) && !x.Path.Contains('*'),
            AmbiguityReason = x.OwnerProof.Equals("DevFleetLedger", StringComparison.OrdinalIgnoreCase) ? "" : "Ledger ownership marker is not the canonical DevFleet marker."
        }).ToArray();
    }

    private static DiscoveredProject? Parse(JsonElement item)
    {
        if (!item.TryGetProperty("project_id", out var pid) || !item.TryGetProperty("slug", out var slug) || !item.TryGetProperty("runtime_id", out var runtime)) return null;
        var projectId = pid.GetString() ?? "";
        var projectSlug = slug.GetString() ?? "";
        var runtimeId = runtime.GetString() ?? "";
        var managedBy = item.TryGetProperty("managed_by", out var managed) ? managed.GetString() ?? "" : "";
        var hostId = item.TryGetProperty("host_id", out var hostElement) ? hostElement.GetString() ?? "" : "";
        var project = new DiscoveredProject(projectId, projectSlug, "Multipass Host Agent", runtimeId, managedBy, "", true)
        {
            VmName = item.TryGetProperty("vm_name", out var vm) ? vm.GetString() ?? "" : "",
            HostId = hostId,
            LifecycleState = item.TryGetProperty("state", out var state) ? state.GetString() ?? "unknown" : "unknown",
            IsDevFleetOwned = managedBy.Equals("devfleet", StringComparison.OrdinalIgnoreCase),
            OwnershipSource = "host-agent-registry",
            ProjectIdVerified = !string.IsNullOrWhiteSpace(projectId),
            RuntimeIdVerified = !string.IsNullOrWhiteSpace(runtimeId) && !runtimeId.Contains('*'),
            AmbiguityReason = managedBy.Equals("devfleet", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(hostId) ? "" : "Host Agent registry did not provide a complete canonical DevFleet ownership record."
        };
        var backup = item.TryGetProperty("backup_manifest", out var explicitManifest) ? explicitManifest.GetString() : null;
        foreach (var backupRoot in new[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevFleetHostAgent", "backups"), Path.Combine(AppPaths.StateRoot, "backups") })
        {
            if (!string.IsNullOrWhiteSpace(backup) || !Directory.Exists(backupRoot)) continue;
            foreach (var candidate in Directory.EnumerateFiles(backupRoot, "*.json").OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase))
            {
                try
                {
                    using var backupDoc = JsonDocument.Parse(File.ReadAllText(candidate));
                    var root = backupDoc.RootElement;
                    var candidateProjectId = root.TryGetProperty("project_id", out var candidatePid) ? candidatePid.GetString() : null;
                    var rid = root.TryGetProperty("runtime_id", out var candidateRid) ? candidateRid.GetString() : null;
                    if (string.Equals(candidateProjectId, project.ProjectId, StringComparison.OrdinalIgnoreCase) && string.Equals(rid, project.RuntimeId, StringComparison.OrdinalIgnoreCase)) { backup = candidate; break; }
                }
                catch (JsonException) { }
            }
        }
        return project with { BackupManifest = backup ?? "" };
    }
}

public sealed record BackupReference(string Provider, string BackupId, string ProjectId, string Slug, string RuntimeId, string HostId, string ArchiveSha256, long ArchiveBytes, string ManifestSha256, string CreatedAt, string ConsistencyLevel);

public sealed record BackupVerification(string ProjectId, string BackupId, string ArchivePath, string ExpectedSha256, string ActualSha256, bool IdentityMatches, bool RestoreEligible, DateTime VerifiedUtc, BackupReference? Reference = null)
{
    public bool IsVerified => IdentityMatches && RestoreEligible && ExpectedSha256.Equals(ActualSha256, StringComparison.OrdinalIgnoreCase) && (Reference is not null ? Reference.ArchiveSha256.Equals(ActualSha256, StringComparison.OrdinalIgnoreCase) && Reference.ArchiveBytes >= 0 : File.Exists(ArchivePath));
}

public sealed class BackupVerificationService
{
    public BackupVerification Verify(DiscoveredProject project)
    {
        if (string.IsNullOrWhiteSpace(project.BackupManifest) || !File.Exists(project.BackupManifest)) return new(project.ProjectId, "", "", "", "", false, false, DateTime.UtcNow);
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(project.BackupManifest));
            var root = doc.RootElement;
            var projectId = root.TryGetProperty("project_id", out var pid) ? pid.GetString() ?? "" : root.TryGetProperty("projectId", out pid) ? pid.GetString() ?? "" : "";
            var archive = root.TryGetProperty("archive", out var ap) ? ap.GetString() ?? "" : root.TryGetProperty("archive_path", out ap) ? ap.GetString() ?? "" : root.TryGetProperty("archivePath", out ap) ? ap.GetString() ?? "" : "";
            var expected = root.TryGetProperty("sha256", out var sh) ? sh.GetString() ?? "" : root.TryGetProperty("archive_sha256", out sh) ? sh.GetString() ?? "" : "";
            var id = root.TryGetProperty("backup_id", out var bid) ? bid.GetString() ?? "" : root.TryGetProperty("backupId", out bid) ? bid.GetString() ?? "" : Path.GetFileNameWithoutExtension(archive);
            var actual = File.Exists(archive) ? Convert.ToHexString(ComputeSha256(archive)).ToLowerInvariant() : "";
            var slugMatches = !root.TryGetProperty("slug", out var sl) || string.Equals(sl.GetString(), project.Slug, StringComparison.OrdinalIgnoreCase);
            var runtimeMatches = !root.TryGetProperty("runtime_id", out var rt) || string.Equals(rt.GetString(), project.RuntimeId, StringComparison.OrdinalIgnoreCase);
            var hashesMatch = root.TryGetProperty("source_archive_sha256", out var source) && root.TryGetProperty("host_archive_sha256", out var host) && string.Equals(source.GetString(), host.GetString(), StringComparison.OrdinalIgnoreCase);
            return new(project.ProjectId, id, archive, expected, actual, projectId.Equals(project.ProjectId, StringComparison.OrdinalIgnoreCase) && slugMatches && runtimeMatches && hashesMatch, project.RestoreEligible, DateTime.UtcNow);
        }
        catch { return new(project.ProjectId, "", "", "", "", false, false, DateTime.UtcNow); }
    }

    private static byte[] ComputeSha256(string path)
    {
        using var stream = File.OpenRead(path);
        return SHA256.HashData(stream);
    }
}

public sealed record VmRecord(string Provider, string RuntimeId, string ProjectId, bool Owned, string Slug = "", string BackupId = "", string BackupSha256 = "");
public interface IVmProvider
{
    IReadOnlyList<VmRecord> Discover();
    BackupVerification CreateFreshBackup(VmRecord vm);
    void DeleteExact(VmRecord vm);
}

public sealed class RecordingVmProvider(IReadOnlyList<VmRecord> inventory) : IVmProvider
{
    public IReadOnlyList<VmRecord> Inventory { get; } = inventory;
    public List<string> DeletedRuntimeIds { get; } = [];
    public IReadOnlyList<VmRecord> Discover() => Inventory;
    public BackupVerification CreateFreshBackup(VmRecord vm) => throw new InvalidOperationException("Recording VM provider does not create destructive backups.");
    public void DeleteExact(VmRecord vm)
    {
        if (!vm.Owned) throw new InvalidOperationException("Refusing to delete an unproven VM.");
        if (vm.Provider.Equals("Multipass", StringComparison.OrdinalIgnoreCase) && vm.RuntimeId.Contains('*')) throw new InvalidOperationException("Wildcard VM deletion is forbidden.");
        DeletedRuntimeIds.Add(vm.RuntimeId);
    }
}

public sealed class MultipassHostAgentProvider : IVmProvider
{
    private readonly string _root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevFleetHostAgent");
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(30) };

    public IReadOnlyList<VmRecord> Discover()
    {
        var registry = Path.Combine(_root, "projects.json");
        if (!File.Exists(registry)) return [];
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(registry));
            var projects = doc.RootElement.TryGetProperty("projects", out var p) ? p : doc.RootElement;
            var result = new List<VmRecord>();
            foreach (var item in projects.ValueKind == JsonValueKind.Object ? projects.EnumerateObject().Select(x => x.Value) : projects.EnumerateArray())
            {
                var managed = item.TryGetProperty("managed_by", out var mb) && mb.GetString()?.Equals("devfleet", StringComparison.OrdinalIgnoreCase) == true;
                var projectId = item.TryGetProperty("project_id", out var id) ? id.GetString() ?? "" : "";
                var runtime = item.TryGetProperty("runtime_id", out var rid) ? rid.GetString() ?? "" : "";
                var slug = item.TryGetProperty("slug", out var s) ? s.GetString() ?? "" : "";
                var backup = FindLatestBackup(projectId, slug, runtime);
                result.Add(new VmRecord("Multipass Host Agent", runtime, projectId, managed, slug, backup.BackupId, backup.Sha256));
            }
            return result;
        }
        catch (JsonException) { return []; }
    }

    public BackupVerification CreateFreshBackup(VmRecord vm)
    {
        if (!vm.Owned || string.IsNullOrWhiteSpace(vm.ProjectId) || string.IsNullOrWhiteSpace(vm.RuntimeId) || string.IsNullOrWhiteSpace(vm.Slug))
            throw new InvalidOperationException("Fresh safety backup requires an exact owned project and runtime identity.");
        using var config = JsonDocument.Parse(File.ReadAllText(Path.Combine(_root, "config.json")));
        var prefix = config.RootElement.TryGetProperty("ListenPrefix", out var lp) ? lp.GetString() : "http://127.0.0.1:8791/";
        var tokenPath = config.RootElement.TryGetProperty("TokenPath", out var tp) ? tp.GetString() : null;
        if (string.IsNullOrWhiteSpace(tokenPath) || !File.Exists(tokenPath)) throw new InvalidOperationException("Host Agent token path is unavailable; fresh safety backup is blocked.");
        var backupBody = JsonSerializer.SerializeToUtf8Bytes(new { operation = "backup", slug = vm.Slug, project_id = vm.ProjectId, runtime_id = vm.RuntimeId });
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(BuildHostAgentBaseUri(prefix), $"v1/project-vms/{Uri.EscapeDataString(vm.RuntimeId)}/backup"));
        request.Content = new ByteArrayContent(backupBody);
        request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        AddRequestAuthentication(request, backupBody, File.ReadAllText(tokenPath).Trim(), config.RootElement.TryGetProperty("HostName", out var hostName) ? hostName.GetString() ?? "" : "");
        using var response = _http.Send(request);
        var bodyBytes = response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
        VerifyResponseAuthentication(request, response, bodyBytes, File.ReadAllText(tokenPath).Trim(), config.RootElement.TryGetProperty("HostName", out var responseHostName) ? responseHostName.GetString() ?? "" : "");
        var body = Encoding.UTF8.GetString(bodyBytes);
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException($"Host Agent rejected fresh safety backup ({(int)response.StatusCode}): {body}");
        using var document = JsonDocument.Parse(body); var root = document.RootElement;
        var id = root.TryGetProperty("backup_id", out var bid) ? bid.GetString() ?? "" : "";
        var sha = root.TryGetProperty("backup_sha256", out var sh) ? sh.GetString() ?? "" : "";
        var status = root.TryGetProperty("backup_status", out var st) ? st.GetString() ?? "" : "";
        if (!status.Equals("verified", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(id) || !Regex.IsMatch(sha, "^[0-9a-fA-F]{64}$"))
            throw new InvalidDataException("Host Agent fresh safety backup did not return a verified identity-bound backup reference.");
        if (!root.TryGetProperty("backup_reference", out var reference) || reference.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException("Host Agent fresh safety backup omitted its opaque provider reference.");
        var providerReference = new BackupReference(
            reference.GetProperty("provider").GetString() ?? "",
            reference.GetProperty("backup_id").GetString() ?? "",
            reference.GetProperty("project_id").GetString() ?? "",
            reference.GetProperty("slug").GetString() ?? "",
            reference.GetProperty("runtime_id").GetString() ?? "",
            reference.GetProperty("host_id").GetString() ?? "",
            reference.GetProperty("archive_sha256").GetString() ?? "",
            reference.GetProperty("archive_bytes").GetInt64(),
            reference.GetProperty("manifest_sha256").GetString() ?? "",
            reference.GetProperty("created_at").GetString() ?? "",
            reference.GetProperty("consistency_level").GetString() ?? "");
        if (!providerReference.Provider.Equals("multipass-host-agent", StringComparison.OrdinalIgnoreCase) || !providerReference.BackupId.Equals(id, StringComparison.OrdinalIgnoreCase) || !providerReference.ProjectId.Equals(vm.ProjectId, StringComparison.OrdinalIgnoreCase) || !providerReference.Slug.Equals(vm.Slug, StringComparison.OrdinalIgnoreCase) || !providerReference.RuntimeId.Equals(vm.RuntimeId, StringComparison.OrdinalIgnoreCase) || !providerReference.ArchiveSha256.Equals(sha, StringComparison.OrdinalIgnoreCase) || providerReference.ArchiveBytes < 0 || !Regex.IsMatch(providerReference.ManifestSha256, "^[0-9a-fA-F]{64}$"))
            throw new InvalidDataException("Host Agent backup reference identity or hash binding is invalid.");
        return new BackupVerification(vm.ProjectId, id, "", sha, sha, true, true, DateTime.UtcNow, providerReference);
    }

    public void DeleteExact(VmRecord vm)
    {
        if (!vm.Owned || string.IsNullOrWhiteSpace(vm.Slug) || string.IsNullOrWhiteSpace(vm.BackupId) || string.IsNullOrWhiteSpace(vm.BackupSha256))
            throw new InvalidOperationException("Host Agent destruction requires an owned project, exact slug, and selected verified backup.");
        var configPath = Path.Combine(_root, "config.json");
        using var config = JsonDocument.Parse(File.ReadAllText(configPath));
        var prefix = config.RootElement.TryGetProperty("ListenPrefix", out var lp) ? lp.GetString() : "http://127.0.0.1:8791/";
        var tokenPath = config.RootElement.TryGetProperty("TokenPath", out var tp) ? tp.GetString() : null;
        if (string.IsNullOrWhiteSpace(tokenPath) || !File.Exists(tokenPath)) throw new InvalidOperationException("Host Agent token path is unavailable; destruction is blocked.");
        var destroyBody = JsonSerializer.SerializeToUtf8Bytes(new { operation = "destroy", slug = vm.Slug, project_id = vm.ProjectId, confirm_slug = vm.Slug, confirm_phrase = $"DESTROY {vm.Slug}", backup_verified = true, backup_id = vm.BackupId, backup_sha256 = vm.BackupSha256 });
        using var request = new HttpRequestMessage(HttpMethod.Delete, new Uri(BuildHostAgentBaseUri(prefix), $"v1/project-vms/{Uri.EscapeDataString(vm.RuntimeId)}/destroy"));
        request.Content = new ByteArrayContent(destroyBody);
        request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        AddRequestAuthentication(request, destroyBody, File.ReadAllText(tokenPath).Trim(), config.RootElement.TryGetProperty("HostName", out var hostName) ? hostName.GetString() ?? "" : "");
        using var response = _http.Send(request);
        var bodyBytes = response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
        VerifyResponseAuthentication(request, response, bodyBytes, File.ReadAllText(tokenPath).Trim(), config.RootElement.TryGetProperty("HostName", out var responseHostName) ? responseHostName.GetString() ?? "" : "");
        var body = Encoding.UTF8.GetString(bodyBytes);
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException($"Host Agent rejected exact project destruction ({(int)response.StatusCode}): {body}");
        if (!body.Contains("\"state\":\"destroyed\"", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Host Agent destruction response did not prove destroyed state.");
    }

    private static Uri BuildHostAgentBaseUri(string? configuredPrefix)
    {
        var prefix = string.IsNullOrWhiteSpace(configuredPrefix) ? "http://127.0.0.1:8791/" : configuredPrefix.Trim();
        foreach (var scheme in new[] { "http://", "https://" })
        foreach (var wildcard in new[] { "+", "*" })
        {
            var marker = scheme + wildcard + ":";
            if (prefix.StartsWith(marker, StringComparison.OrdinalIgnoreCase))
            {
                prefix = scheme + "127.0.0.1:" + prefix[marker.Length..];
                break;
            }
        }
        if (!Uri.TryCreate(prefix.TrimEnd('/') + "/", UriKind.Absolute, out var uri) || uri is null || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) || !string.IsNullOrEmpty(uri.UserInfo))
            throw new InvalidOperationException("Host Agent listen prefix is not a valid local HTTP endpoint.");
        return uri;
    }

    private static void AddRequestAuthentication(HttpRequestMessage request, byte[] body, string key, string expectedHost)
    {
        if (string.IsNullOrWhiteSpace(key) || string.IsNullOrWhiteSpace(expectedHost)) throw new InvalidOperationException("Host Agent request authentication configuration is incomplete.");
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(System.Globalization.CultureInfo.InvariantCulture);
        var nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(18)).ToLowerInvariant();
        var prefix = Encoding.UTF8.GetBytes($"{request.Method.Method.ToUpperInvariant()}\n{request.RequestUri!.AbsolutePath}\n{timestamp}\n{nonce}\n");
        var suffix = Encoding.UTF8.GetBytes($"\n{expectedHost}");
        var material = new byte[prefix.Length + body.Length + suffix.Length];
        Buffer.BlockCopy(prefix, 0, material, 0, prefix.Length);
        Buffer.BlockCopy(body, 0, material, prefix.Length, body.Length);
        Buffer.BlockCopy(suffix, 0, material, prefix.Length + body.Length, suffix.Length);
        var signature = Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(key), material)).ToLowerInvariant();
        request.Headers.TryAddWithoutValidation("X-DevFleet-Host-Timestamp", timestamp);
        request.Headers.TryAddWithoutValidation("X-DevFleet-Host-Nonce", nonce);
        request.Headers.TryAddWithoutValidation("X-DevFleet-Host-Expected", expectedHost);
        request.Headers.TryAddWithoutValidation("X-DevFleet-Host-Signature", signature);
    }

    private static void VerifyResponseAuthentication(HttpRequestMessage request, HttpResponseMessage response, byte[] body, string key, string expectedHost)
    {
        if (string.IsNullOrWhiteSpace(key) || string.IsNullOrWhiteSpace(expectedHost)) throw new InvalidOperationException("Host Agent response authentication configuration is incomplete.");
        var timestamp = request.Headers.GetValues("X-DevFleet-Host-Timestamp").Single();
        var nonce = request.Headers.GetValues("X-DevFleet-Host-Nonce").Single();
        var provided = response.Headers.TryGetValues("X-DevFleet-Host-Response-Signature", out var values) ? values.SingleOrDefault() : null;
        var material = BuildAuthMaterial(request.Method.Method, request.RequestUri!.AbsolutePath, timestamp, nonce, ((int)response.StatusCode).ToString(System.Globalization.CultureInfo.InvariantCulture), body, expectedHost);
        var expected = Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(key), material)).ToLowerInvariant();
        var left = Encoding.ASCII.GetBytes(expected); var right = Encoding.ASCII.GetBytes((provided ?? "").ToLowerInvariant());
        if (left.Length != right.Length || !CryptographicOperations.FixedTimeEquals(left, right)) throw new InvalidDataException("Host Agent response authentication failed.");
    }

    private static byte[] BuildAuthMaterial(string method, string path, string timestamp, string nonce, string status, byte[] body, string expectedHost)
    {
        var parts = new[] { Encoding.UTF8.GetBytes(method.ToUpperInvariant()), Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(path), Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(timestamp), Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(nonce), Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(status), Encoding.UTF8.GetBytes("\n") , body, Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(expectedHost) };
        var length = parts.Sum(part => part.Length); var material = new byte[length]; var offset = 0;
        foreach (var part in parts) { Buffer.BlockCopy(part, 0, material, offset, part.Length); offset += part.Length; }
        return material;
    }

    private (string BackupId, string Sha256) FindLatestBackup(string projectId, string slug, string runtime)
    {
        var backupRoot = Path.Combine(_root, "backups");
        foreach (var manifest in Directory.Exists(backupRoot) ? Directory.EnumerateFiles(backupRoot, "*.json").OrderByDescending(File.GetLastWriteTimeUtc) : Enumerable.Empty<string>())
        {
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(manifest)); var r = doc.RootElement;
                if (r.TryGetProperty("project_id", out var pid) && pid.GetString() == projectId && r.TryGetProperty("slug", out var sl) && sl.GetString() == slug && r.TryGetProperty("runtime_id", out var rt) && rt.GetString() == runtime)
                    return (r.TryGetProperty("backup_id", out var bid) ? bid.GetString() ?? "" : Path.GetFileNameWithoutExtension(manifest), r.TryGetProperty("archive_sha256", out var sh) ? sh.GetString() ?? "" : "");
            }
            catch (JsonException) { }
        }
        return ("", "");
    }
}

public sealed class VmOwnershipService
{
    private readonly IVmProvider _provider;
    public VmOwnershipService(IVmProvider provider) => _provider = provider;
    public void DeleteOwnedExact(string projectId, string runtimeId, Action<string>? progress = null)
        => DeleteOwnedExact(projectId, runtimeId, null, progress);
    public void DeleteOwnedExact(string projectId, string runtimeId, BackupVerification? selectedBackup, Action<string>? progress = null)
    {
        var before = _provider.Discover().ToArray();
        var vm = before.SingleOrDefault(x => x.ProjectId.Equals(projectId, StringComparison.OrdinalIgnoreCase) && x.RuntimeId.Equals(runtimeId, StringComparison.OrdinalIgnoreCase));
        if (vm is null || !vm.Owned) throw new InvalidOperationException($"No independently owned VM matched project={projectId}, runtime={runtimeId}.");
        if (selectedBackup is not null)
        {
            if (!selectedBackup.IsVerified || !selectedBackup.ProjectId.Equals(projectId, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Exact selected backup binding is invalid.");
            vm = vm with { BackupId = selectedBackup.BackupId, BackupSha256 = selectedBackup.ActualSha256 };
            progress?.Invoke($"Exact selected backup bound: {selectedBackup.BackupId} sha256={selectedBackup.ActualSha256}");
        }
        _provider.DeleteExact(vm);
        progress?.Invoke($"Provider-aware exact deletion verified: {vm.Provider} {vm.RuntimeId}");
        var unrelated = before.Where(x => !x.RuntimeId.Equals(runtimeId, StringComparison.OrdinalIgnoreCase)).Select(x => x.RuntimeId).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (_provider.Discover().Where(x => unrelated.Contains(x.RuntimeId)).Count() != unrelated.Count) throw new InvalidOperationException("Unrelated VM inventory changed during exact deletion.");
    }

    public BackupVerification CreateFreshSafetyBackup(DiscoveredProject project, Action<string>? progress = null)
    {
        var vm = _provider.Discover().SingleOrDefault(x => x.ProjectId.Equals(project.ProjectId, StringComparison.OrdinalIgnoreCase) && x.RuntimeId.Equals(project.RuntimeId, StringComparison.OrdinalIgnoreCase));
        if (vm is null || !vm.Owned) throw new InvalidOperationException($"No independently owned VM matched project={project.ProjectId}, runtime={project.RuntimeId}.");
        var backup = _provider.CreateFreshBackup(vm);
        if (!backup.IsVerified || !backup.ProjectId.Equals(project.ProjectId, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Fresh safety backup identity verification failed.");
        progress?.Invoke($"Fresh Factory Reset safety backup bound: {backup.BackupId} sha256={backup.ActualSha256}");
        return backup;
    }
}

public sealed class TransactionService
{
    private readonly Stack<(string Name, Action Rollback)> _rollback = new();
    private readonly InstallerLogger _logger;
    public TransactionService(InstallerLogger logger) => _logger = logger;
    public void Execute(string name, Action action, Action rollback, Action<string>? progress = null)
    {
        _logger.Write($"step={name} state=planned"); progress?.Invoke($"Planned: {name}");
        action(); _rollback.Push((name, rollback)); _logger.Write($"step={name} state=verified"); progress?.Invoke($"Verified: {name}");
    }
    public void Rollback(Action<string>? progress = null)
    {
        while (_rollback.Count > 0)
        {
            var step = _rollback.Pop();
            try { step.Rollback(); _logger.Write($"step={step.Name} state=rolled-back"); progress?.Invoke($"Rolled back: {step.Name}"); }
            catch (Exception ex) { _logger.Write($"step={step.Name} state=rollback-incomplete error={ex.Message}"); progress?.Invoke($"Rollback incomplete: {step.Name}"); }
        }
    }
}

public static class RebootCheckpointService
{
    // The supported Windows prerequisite graph has at most three legitimate
    // reboot boundaries (PowerShell/servicing, Hyper-V, and final servicing).
    // Keep this explicit and bounded: an unexpected fourth boundary fails
    // closed instead of becoming an unbounded reboot loop.
    public const int MaxRebootBoundaries = 3;
    public static string Path => System.IO.Path.Combine(AppPaths.InstallerRoot, "resume-checkpoint.json");
    private static string ConsumedPath(string transactionId) => System.IO.Path.Combine(AppPaths.InstallerRoot, "resume-consumed", $"{transactionId}.json");
    private static string ScriptStateRoot => TestEnvironment.IsTestProcess
        ? AppPaths.StateRoot
        : System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevFleet");

    private static bool IsSameScriptTransaction(JsonElement existing, InstallerPlan plan, string role)
    {
        var normalizedRole = role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
        return existing.TryGetProperty("transactionId", out var transactionId) &&
               existing.TryGetProperty("payloadSha256", out var payloadSha256) &&
               existing.TryGetProperty("action", out var action) &&
               existing.TryGetProperty("role", out var existingRole) &&
               existing.TryGetProperty("acknowledgeRootfulDocker", out var acknowledgement) &&
               acknowledgement.ValueKind is JsonValueKind.True or JsonValueKind.False &&
               transactionId.GetString() == plan.TransactionId &&
               payloadSha256.GetString() == PayloadManifest.PayloadSha256 &&
               action.GetString() == plan.Mode.ToString() &&
               existingRole.GetString() == normalizedRole &&
               acknowledgement.GetBoolean() == plan.AcknowledgeRootfulDocker;
    }

    private static void ClearStaleStageMarkers(string role, Action<string>? progress = null)
    {
        var roots = new[] { ScriptStateRoot, AppPaths.InstallerRoot }
            .Select(System.IO.Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase);
        foreach (var root in roots)
        {
            if (!Directory.Exists(root)) continue;
            foreach (var marker in Directory.EnumerateFiles(root, "stage-*.complete", SearchOption.TopDirectoryOnly).ToArray())
            {
                var full = System.IO.Path.GetFullPath(marker);
                if (!ful