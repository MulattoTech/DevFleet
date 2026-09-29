# DevFleet source part 059

Full-source UTF-8 byte interval [2697000, 2743500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: b94a62d00be614278202fc0ee0e7ff058f915dfd615acd3af0df276aac642868

<!-- BEGIN SOURCE SLICE -->
, "--exact", "--source", "winget", "--accept-source-agreements", "--accept-package-agreements", "--download-directory", destinationRoot]);
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
            if (actualByName.Keys.Any(name => !entryByName.ContainsKey(name)) || entryByName.Keys.Any(name => !actualByName.ContainsKey(name)))
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
        var providerReference